extends GutTest
## TableHost: a whole game with human seats played through packets only.


func test_full_game_through_packets() -> void:
    var host := TableHost.new()
    host.auto_bots = false
    host.humans = [true, false, true, false]
    add_child_autofree(host)
    var inbox: Array = []
    host.packet.connect(func(seat: int, data: Dictionary) -> void: inbox.append([seat, data]))
    host.start(11)
    var bot := BeloteBot.new()
    var hands_ended := 0
    var steps := 0
    while not host.game.is_over(host.state) and steps < 5000:
        steps += 1
        # Answer every packet like a screen would: close summaries, play on our turn.
        while not inbox.is_empty():
            var item: Array = inbox.pop_front()
            var seat: int = item[0]
            var view: Dictionary = item[1].view
            var event: Dictionary = item[1].event
            assert_eq(view.seat, seat)
            assert_false(view.has("hands"), "a seat never gets the other hands")
            if event.has("hand_end"):
                hands_ended += 1
                host.continue_from(seat)
        if host.bot_to_play():
            host.play_bot_turn()
        elif host.humans[host.state.to_act]:
            var view := host.view_for(host.state.to_act)
            host.submit(host.state.to_act, bot.choose(view))
    assert_true(host.game.is_over(host.state))
    assert_gt(hands_ended, 0)


func test_rejects_moves_out_of_turn_and_while_reading() -> void:
    var host := TableHost.new()
    host.auto_bots = false
    host.humans = [true, true, true, true]
    add_child_autofree(host)
    host.start(3)
    var to_act := host.state.to_act
    host.submit((to_act + 1) % 4, {"kind": "pass"})
    assert_eq(host.state.moves.size(), 0, "not that seat's turn")
    host.submit(to_act, {"kind": "play", "card": 0})
    assert_eq(host.state.moves.size(), 0, "illegal during bidding")
    host.submit(to_act, {"kind": "pass"})
    assert_eq(host.state.moves.size(), 1)
