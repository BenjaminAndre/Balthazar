extends GutTest
## A host and two guests in one process, each under its own multiplayer root, joined
## by in-memory LoopbackPeers (no socket: this PC has no network rights). The link
## only sees Godot's multiplayer API, so these are the same RPCs as over Tube.

var host_api: SceneMultiplayer
var roots: Array[Node] = []
var links: Array[TableLink] = []
var peers: Array[LoopbackPeer] = []
## Per link: every packet its screen received.
var inboxes: Array = []


func before_each() -> void:
    roots.clear()
    links.clear()
    peers.clear()
    inboxes.clear()
    var hub := LoopbackPeer.host()
    for i in 3:
        var root := Node.new()
        root.name = "Peer%d" % i
        add_child(root)
        var link := TableLink.new()
        link.name = "Link"
        root.add_child(link)
        var api := SceneMultiplayer.new()
        get_tree().set_multiplayer(api, root.get_path())
        var peer: LoopbackPeer = hub if i == 0 else hub.add_client(i + 1)
        api.multiplayer_peer = peer
        roots.append(root)
        links.append(link)
        peers.append(peer)
        var inbox := []
        inboxes.append(inbox)
        link.packet_received.connect(func(data: Dictionary) -> void: inbox.append(data))
    host_api = get_tree().get_multiplayer(roots[0].get_path())
    await wait_until(func() -> bool: return host_api.get_peers().size() == 2, 5.0)


func after_each() -> void:
    for i in roots.size():
        peers[i].close()
        get_tree().set_multiplayer(null, roots[i].get_path())
        roots[i].queue_free()


func _seat_everyone() -> void:
    links[0].open("Hôte")
    links[1].join("Alice")
    links[2].join("Bob")
    await wait_until(_bob_seated, 5.0)


func _bob_seated() -> bool:
    var seats: Array = links[2].info.get("seats", [])
    return seats.size() == 4 and seats[1].name == "Bob"


func test_guests_get_seats_partner_first() -> void:
    await _seat_everyone()
    var seats: Array = links[0].info.seats
    assert_eq(seats[0].name, "Hôte")
    assert_eq(seats[2].name, "Alice", "the first guest sits opposite the host")
    assert_eq(seats[1].name, "Bob")
    assert_false(seats[3].human, "the last seat is a bot")


func test_a_whole_online_game() -> void:
    await _seat_everyone()
    links[0].host.bot_delay = 0.0
    links[0].host.trick_pause = 0.0
    for link in links:
        link.screen_attached()
    links[0].start_game(5)
    await wait_until(func() -> bool: return links[1].my_seat == 2 and links[2].my_seat == 1, 5.0)
    var bot := BeloteBot.new()
    var done := func() -> bool:
        # Play like three screens: answer our turn and close the summaries.
        for i in 3:
            var inbox: Array = inboxes[i]
            while not inbox.is_empty():
                var data: Dictionary = inbox.pop_front()
                var view: Dictionary = data.view
                assert_false(view.has("hands"), "nobody receives the other hands")
                assert_eq(view.seat, links[i].my_seat)
                if data.event.has("hand_end"):
                    links[i].continue_hand()
                if data.event.has("hand_end") and data.event.hand_end.game_over:
                    continue
                if view.to_act == view.seat and not view.legal.is_empty():
                    links[i].submit(bot.choose(view))
        return links[0].host.game.is_over(links[0].host.state)
    await wait_until(done, 60.0)
    var s: BeloteState = links[0].host.state
    assert_true(links[0].host.game.is_over(s), "stuck: phase %d, to act %d, moves %d, reading %s, humans %s" % [
            s.phase, s.to_act, s.moves.size(), links[0].host._reading, links[0].host.humans])


func test_a_guest_who_drops_is_replaced_by_a_bot_then_gets_the_seat_back() -> void:
    await _seat_everyone()
    for link in links:
        link.screen_attached()
    links[0].start_game(5)
    await wait_until(func() -> bool: return links[2].my_seat == 1, 5.0)
    peers[2].close()
    await wait_until(func() -> bool: return not links[0].host.humans[1], 5.0)
    assert_false(links[0].info.seats[1].here)
    assert_eq(links[0].info.seats[1].name, "Bob", "the seat stays Bob's")
    # Bob comes back on a new connection, under the same name.
    var api := get_tree().get_multiplayer(roots[2].get_path()) as SceneMultiplayer
    peers[2] = peers[0].add_client(9)
    api.multiplayer_peer = peers[2]
    await wait_until(func() -> bool: return host_api.get_peers().has(9), 5.0)
    links[2].join("Bob")
    await wait_until(func() -> bool: return links[0].host.humans[1], 5.0)
    assert_eq(links[2].my_seat, 1)
    await wait_until(func() -> bool: return inboxes[2].any(_is_start), 5.0)
    assert_true(inboxes[2].any(_is_start), "the table is sent again")


func _is_start(data: Dictionary) -> bool:
    return data.event.kind == "start"
