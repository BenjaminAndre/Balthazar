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
var bot: BeloteBot = BeloteBots.make("facile")
var bot_level := "facile"
var state: BeloteState
## Which seats are played by people; the others are bots.
var humans: Array[bool] = [true, false, false, false]
var names: Array[String] = ["Vous", "Gauche", "Partenaire", "Droite"]
## The table settings (TableSettings); set before start().
var settings: Dictionary = TableSettings.complete({})

## Human seats still reading the hand summary: bots wait for all of them, a person for themself.
var _reading: Dictionary = {}
var _turn := 0
var _after_trick := false


func start(seed_value := -1) -> void:
    game = Belote.new(TableSettings.belote_rules(settings))
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


## Which bots play the free seats (BeloteBots.LEVELS).
func set_bot_level(level: String) -> void:
    bot_level = level
    bot = BeloteBots.make(level)


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
    view.bot_level = bot_level
    # Points so far this hand, shown live on the table: cards won, and apart the
    # settled announces plus the belote once it has been said.
    view.live_points = state.card_points.duplicate()
    var extra := state.announce_points.duplicate()
    if view.belote_seat >= 0:
        extra[view.belote_seat % 2] += BeloteScoring.BELOTE
    view.live_extra = extra
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
    if not auto_bots or not is_inside_tree():
        return
    if auto_finish_card() >= 0:
        _auto_finish()
        return
    if not bot_to_play():
        return
    var turn := _turn
    await get_tree().create_timer(bot_delay + (trick_pause if _after_trick else 0.0)).timeout
    if turn == _turn:
        play_bot_turn()


## « Fin automatique »: plays the person's card after a short pause; the next
## lead follows the same way, since the claimed tricks are theirs.
func _auto_finish() -> void:
    var turn := _turn
    await get_tree().create_timer(bot_delay + (trick_pause if _after_trick else 0.0)).timeout
    var card := auto_finish_card()
    if turn == _turn and card >= 0:
        submit(state.to_act, {"kind": "play", "card": card})


## With « Fin automatique », the card to play for the person who leads when every
## card they hold surely wins, whatever the others hold (the host sees all hands);
## -1 otherwise. Trumps go first, strongest first, to draw the others' trumps.
func auto_finish_card() -> int:
    if state == null or game.is_over(state) or state.phase != BeloteState.Phase.PLAYING:
        return -1
    if not TableSettings.value(settings, "general", "auto_finish"):
        return -1
    var seat := state.to_act
    if not humans[seat] or _reading.has(seat) or not state.trick.is_empty():
        return -1
    var trump := state.trump
    var others: Array[int] = []
    for s in 4:
        if s != seat:
            others.append_array(state.hands[s])
    var their_best_trump := -1
    for card in others:
        if Cards.suit_of(card) == trump:
            their_best_trump = maxi(their_best_trump, BeloteCards.strength(card, trump))
    var mine: Array[int] = state.hands[seat]
    var my_trumps := 0
    for card in mine:
        if Cards.suit_of(card) == trump:
            my_trumps += 1
            if BeloteCards.strength(card, trump) < their_best_trump:
                return -1
    # Each trump we lead takes one trump from every other hand.
    var most_trumps := 0
    for s in 4:
        if s != seat:
            var count := 0
            for card in state.hands[s]:
                if Cards.suit_of(card) == trump:
                    count += 1
            most_trumps = maxi(most_trumps, count)
    for card in mine:
        if Cards.suit_of(card) == trump:
            continue
        # A side card wins only once nobody can cut any more, and if nobody follows higher.
        if most_trumps > my_trumps:
            return -1
        for other in others:
            if Cards.suit_of(other) == Cards.suit_of(card) \
                    and BeloteCards.strength(other, trump) > BeloteCards.strength(card, trump):
                return -1
    var best := -1
    for card in mine:
        if best < 0 or _finish_order(card, trump) > _finish_order(best, trump):
            best = card
    return best


func _finish_order(card: int, trump: int) -> int:
    return (100 if Cards.suit_of(card) == trump else 0) + BeloteCards.strength(card, trump)


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
    if move.kind == "relance":
        return "Relance (11 points ou moins)"
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
