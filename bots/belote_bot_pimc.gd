class_name BeloteBotPimc
extends BeloteBotDifficile
## Perfect Information Monte Carlo: deals the unseen cards to the other seats in
## `samples` ways that agree with everything the table showed (BeloteMemory),
## plays each legal card out to the end of the hand in every one of those worlds
## with fast `rollout` bots, and keeps the card with the best average.
## It is the teacher that Zinzin learns from (tools/train.gd); it bids like
## « Difficile ».

var samples := 24
## The bots that finish the hand in each world.
var rollout: BeloteBot = BeloteBotDifficile.new()
var rng := RandomNumberGenerator.new()
## The average outcome (our lead in raw points) of each legal card at the last
## decision, for training: {card: value}.
var last_values: Dictionary = {}

var _game := Belote.new()


func choose(view: Dictionary) -> Dictionary:
    var legal: Array = view.legal
    if view.phase != BeloteState.Phase.PLAYING or legal.size() == 1:
        last_values = {}
        return super(view)
    last_values = evaluate(view)
    var best: Dictionary = legal[0]
    for move in legal:
        if last_values[move.card] > last_values[best.card]:
            best = move
    return best


## Average lead in raw points for every legal card, over the same sampled worlds.
func evaluate(view: Dictionary) -> Dictionary:
    var memory := BeloteMemory.from_view(view)
    var values := {}
    for move in view.legal:
        values[move.card] = 0.0
    var worlds := 0
    for i in samples:
        var hands := sample_hands(memory, view)
        if hands.is_empty():
            continue
        worlds += 1
        for move in view.legal:
            values[move.card] += _play_out(view, memory, hands, move.card)
    if worlds > 0:
        for card in values:
            values[card] /= worlds
    return values


## One deal of the unseen cards to the other seats that fits the table: the right
## number of cards each, no card in a suit a seat is out of, no trump above a
## seat's cap. Empty if none was found in a few tries.
func sample_hands(memory: BeloteMemory, view: Dictionary) -> Array:
    for attempt in 20:
        var hands := [[], [], [], []]
        hands[memory.seat] = memory.hand.duplicate()
        var room: Array[int] = []
        for s in 4:
            room.append(0 if s == memory.seat else int(view.hand_sizes[s]))
        var cards := memory.unseen.duplicate()
        # Most constrained cards first, ties broken at random.
        cards.shuffle()
        var holders := {}
        for card in cards:
            var seats := []
            for s in 4:
                if memory.may_hold(s, card):
                    seats.append(s)
            holders[card] = seats
        cards.sort_custom(func(a: int, b: int) -> bool: return holders[a].size() < holders[b].size())
        var ok := true
        for card in cards:
            var options := []
            for s in holders[card]:
                if room[s] > 0:
                    options.append(s)
            if options.is_empty():
                ok = false
                break
            var s: int = options[rng.randi_range(0, options.size() - 1)]
            hands[s].append(card)
            room[s] -= 1
        if ok:
            return hands
    return []


## Plays `card` then the rest of the hand in one world; returns our lead in raw points.
func _play_out(view: Dictionary, memory: BeloteMemory, hands: Array, card: int) -> float:
    var s := BeloteState.new()
    s.dealer = view.dealer
    s.phase = BeloteState.Phase.PLAYING
    s.to_act = memory.seat
    s.hands = []
    for h in hands:
        var typed: Array[int] = []
        typed.assign(h)
        s.hands.append(typed)
    s.taker = view.taker
    s.trump = memory.trump
    s.trick = memory.trick.duplicate()
    s.trick_leader = memory.leader
    s.played.assign(view.played)
    s.tricks_won = memory.tricks_won.duplicate()
    s.card_points = memory.card_points.duplicate()
    s.announces = [[], [], [], []]
    # Who holds (or held) the king and queen of trumps.
    var king := Cards.make(s.trump, Cards.Rank.ROI)
    var queen := Cards.make(s.trump, Cards.Rank.DAME)
    var king_at: int = memory.played_by.get(king, -1)
    var queen_at: int = memory.played_by.get(queen, -1)
    for seat in 4:
        if s.hands[seat].has(king):
            king_at = seat
        if s.hands[seat].has(queen):
            queen_at = seat
    s.belote_seat = king_at if king_at == queen_at else -1
    _game.apply(s, {"kind": "play", "card": card})
    while s.last_hand.is_empty():
        _game.apply(s, rollout.choose(_game.view_for(s, s.to_act)))
    var team := memory.seat % 2
    return float(s.last_hand.raw[team] - s.last_hand.raw[1 - team])
