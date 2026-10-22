class_name TableHost
extends Node
## Runs one Belote table: it owns the game state, plays the bots, and sends each
## human seat only what that seat may see (GDD §2). Seats are reached through
## `packet`: the table screen for the local player, the network link for others.
##
## A packet is {event, view}: `view` is `Belote.view_for()` plus the table's
## extras; `event` says what just happened, so the screen can animate it:
## - {kind: "start"}: a fresh or resumed table;
## - {kind: "move", seat, move, say, trick?, announces?, hand_end?, redeal?}.

signal packet(seat: int, data: Dictionary)

## Time a bot "thinks", and the extra wait after a trick so screens can show it.
var bot_delay := 0.7
var trick_pause := 1.8
var auto_bots := true

var game := Belote.new()
var bot := BeloteBot.new()
var state: BeloteState
## Which seats are played by people; the others are bots.
var humans: Array[bool] = [true, false, false, false]
var names: Array[String] = ["Vous", "Gauche", "Partenaire", "Droite"]

## Human seats still reading the hand summary: bots wait for all of them, a person for themself.
var _reading: Dictionary = {}
var _turn := 0
var _after_trick := false


func start(seed_value := -1) -> void:
    state = game.new_state(seed_value if seed_value >= 0 else randi())
    _reading.clear()
    resend()
    _schedule()


## Sends the whole table again: to one seat (after a reconnection), or to all.
func resend(seat := -1) -> void:
    if seat < 0:
        _broadcast({"kind": "start"})
    elif humans[seat]:
        packet.emit(seat, {"event": {"kind": "start"}, "view": view_for(seat)})


## A person takes a seat over from its bot, or leaves it to one.
func set_human(seat: int, human: bool) -> void:
    humans[seat] = human
    if not human:
        _reading.erase(seat)
    _schedule()


## A move from a seat. Ignored unless it is that seat's turn and the move is legal.
func submit(seat: int, move: Dictionary) -> void:
    if state == null or _reading.has(seat) or game.is_over(state):
        return
    if seat != state.to_act or not game.legal_moves(state).has(move):
        return
    _apply(seat, move)


## A human closed the hand summary.
func continue_from(seat: int) -> void:
    _reading.erase(seat)
    _schedule()


func view_for(seat: int) -> Dictionary:
    var view := game.view_for(state, seat)
    view.names = names.duplicate()
    view.humans = humans.duplicate()
    view.deal_number = state.deal_number
    view.target = game.rules.target
    # Points so far this hand (cards and settled announces), shown live on the table.
    view.live_points = [state.card_points[0] + state.announce_points[0],
            state.card_points[1] + state.announce_points[1]]
    return view


func _apply(seat: int, move: Dictionary) -> void:
    var event := {"kind": "move", "seat": seat, "move": move, "say": _say(seat, move)}
    var deal := state.deal_number
    var playing := state.phase == BeloteState.Phase.PLAYING
    var trick := state.trick.duplicate()
    var leader := state.trick_leader
    var taker := state.taker
    var trump := state.trump
    game.apply(state, move)
    if move.kind == "take":
        event.say = "Prend à %s" % Cards.SUIT_NAMES[move.suit]
    _after_trick = playing and trick.size() == 3
    if _after_trick:
        trick.append(move.card)
        event.trick = {"cards": trick, "leader": leader, "trump": trump,
                "winner": (leader + BeloteCards.winning_index(trick, trump)) % 4}
        if state.played.size() == 4:
            event.announces = _winning_announces()
    if state.deal_number != deal or game.is_over(state):
        if playing:
            event.hand_end = {"result": state.last_hand.duplicate(true), "taker": taker,
                    "trump": trump, "scores": state.scores.duplicate(),
                    "game_over": game.is_over(state), "winner": state.winner}
            for s in 4:
                if humans[s]:
                    _reading[s] = true
        else:
            event.redeal = true
    _broadcast(event)
    _schedule()


func _broadcast(event: Dictionary) -> void:
    for seat in 4:
        if humans[seat]:
            packet.emit(seat, {"event": event, "view": view_for(seat)})


## Lets the bot whose turn it is play after a short delay. Off when `auto_bots`
## is false: tests then drive the bots with `play_bot_turn()`.
func _schedule() -> void:
    _turn += 1
    if not auto_bots or not is_inside_tree() or not bot_to_play():
        return
    var turn := _turn
    await get_tree().create_timer(bot_delay + (trick_pause if _after_trick else 0.0)).timeout
    if turn == _turn:
        play_bot_turn()


func bot_to_play() -> bool:
    return state != null and not game.is_over(state) and _reading.is_empty() and not humans[state.to_act]


## Plays one bot move now. Returns false when it isn't a bot's turn.
func play_bot_turn() -> bool:
    if not bot_to_play():
        return false
    submit(state.to_act, bot.choose(game.view_for(state, state.to_act)))
    return true


## What a seat says as it moves: its bid, then its announces and belote as it plays.
func _say(seat: int, move: Dictionary) -> String:
    if move.kind == "pass":
        return "Passe"
    if move.kind != "play":
        return ""
    var words: Array[String] = []
    if state.hands[seat].size() == 8:
        for announce in state.announces[seat]:
            words.append(announce.name)
    var king := Cards.make(state.trump, Cards.Rank.ROI)
    var queen := Cards.make(state.trump, Cards.Rank.DAME)
    if seat == state.belote_seat and (move.card == king or move.card == queen):
        var other := queen if move.card == king else king
        words.append("Rebelote" if state.played.has(other) else "Belote")
    return ", ".join(words)


## After the first trick, the winning team's announces with their points, per seat.
func _winning_announces() -> Array:
    var out := ["", "", "", ""]
    if state.announce_team < 0:
        return out
    for seat in 4:
        if seat % 2 == state.announce_team and not state.announces[seat].is_empty():
            var parts: Array[String] = []
            for announce in state.announces[seat]:
                parts.append("%s (%d)" % [announce.name, announce.points])
            out[seat] = ", ".join(parts)
    return out
