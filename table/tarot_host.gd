class_name TarotHost
extends Node
## Runs one Tarot table for 3, 4 or 5 players (GDD §4.2), like TableHost for the
## Belote: it owns the state, plays the bots, and sends each human seat packets
## {event, view} with only what that seat may see. The same public API as
## TableHost, so the network link drives either.
## Events: {kind: "start"}, or {kind: "move", seat, move, say, trick?, chien?,
## hand_end?, redeal?}.

signal packet(seat: int, data: Dictionary)

var bot_delay := 0.7
var trick_pause := 1.8
var auto_bots := true

var players := 4
var game: Tarot
var bot := TarotBot.new()
## Only « Facile » exists at the Tarot for now.
var bot_level := "facile"
var state: TarotState
var humans: Array[bool] = []
var names: Array[String] = []
var settings: Dictionary = TableSettings.complete({})

var _reading: Dictionary = {}
var _turn := 0
var _after_trick := false


func _init(player_count := 4) -> void:
    players = player_count
    for seat in players:
        humans.append(seat == 0)
        names.append("")


func start(seed_value := -1) -> void:
    game = Tarot.new(players)
    state = game.new_state(seed_value if seed_value >= 0 else randi())
    _reading.clear()
    resend()
    _schedule()


func resend(seat := -1) -> void:
    if seat < 0:
        _broadcast({"kind": "start"})
    elif humans[seat]:
        packet.emit(seat, {"event": {"kind": "start"}, "view": view_for(seat)})


func set_human(seat: int, human: bool) -> void:
    humans[seat] = human
    if not human:
        _reading.erase(seat)
    _schedule()


func set_bot_level(_level: String) -> void:
    bot_level = "facile"


func submit(seat: int, move: Dictionary) -> void:
    if state == null or _reading.has(seat) or game.is_over(state):
        return
    if seat != state.to_act or not game.legal_moves(state).has(move):
        return
    _apply(seat, move)


func continue_from(seat: int) -> void:
    _reading.erase(seat)
    _schedule()


func view_for(seat: int) -> Dictionary:
    var view := game.view_for(state, seat)
    view.names = names.duplicate()
    view.humans = humans.duplicate()
    view.deal_number = state.deal_number
    view.bot_level = bot_level
    return view


func _apply(seat: int, move: Dictionary) -> void:
    var event := {"kind": "move", "seat": seat, "move": move, "say": _say(move)}
    var deal := state.deal_number
    var playing := state.phase == TarotState.Phase.PLAYING
    var bidding := state.phase == TarotState.Phase.BIDDING
    var trick := state.trick.duplicate()
    var leader := state.trick_leader
    game.apply(state, move)
    _after_trick = playing and trick.size() == players - 1
    if _after_trick:
        trick.append(move.card)
        event.trick = {"cards": trick, "leader": leader,
                "winner": (leader + TarotCards.winning_index(trick)) % players}
    if bidding and state.phase == TarotState.Phase.ECART:
        event.chien = state.chien.duplicate()
    if state.deal_number != deal or game.is_over(state):
        if playing:
            event.hand_end = {"result": state.last_hand.duplicate(true), "scores": state.scores.duplicate(),
                    "game_over": game.is_over(state), "winner": state.winner}
            for s in players:
                if humans[s]:
                    _reading[s] = true
        else:
            event.redeal = true
    _broadcast(event)
    _schedule()


func _say(move: Dictionary) -> String:
    match move.kind:
        "bid":
            return "Passe" if move.contract == TarotState.Contract.NONE \
                    else TarotState.CONTRACT_NAMES[move.contract]
        "call":
            var rank := "roi" if TarotCards.rank_of(move.card) == TarotCards.Rank.ROI else "dame"
            return "J'appelle le %s de %s" % [rank, Cards.SUIT_NAMES[TarotCards.suit_of(move.card)]]
        "play":
            return "Excuse" if move.card == TarotCards.EXCUSE else ""
    return ""


func _broadcast(event: Dictionary) -> void:
    for seat in players:
        if humans[seat]:
            packet.emit(seat, {"event": event, "view": view_for(seat)})


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


func play_bot_turn() -> bool:
    if not bot_to_play():
        return false
    submit(state.to_act, bot.choose(game.view_for(state, state.to_act)))
    return true
