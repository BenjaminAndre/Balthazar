class_name Belote
extends CardGame
## Belote classique (GDD §3) as a CardGame. Moves:
## {"kind": "pass"}, {"kind": "take", "suit": s} and {"kind": "play", "card": c}.

var rules: BeloteRules


func _init(table_rules: BeloteRules = null) -> void:
    rules = table_rules if table_rules else BeloteRules.new()


func new_state(seed_value: int) -> RefCounted:
    var state := BeloteState.new()
    state.seed_value = seed_value
    state.dealer = 0
    _deal(state)
    return state


## Replays a whole logged game, for tests and, later, a ranked-game referee.
func replay(seed_value: int, moves: Array[Dictionary]) -> BeloteState:
    var state: BeloteState = new_state(seed_value)
    for move in moves:
        apply(state, move)
    return state


func legal_moves(state: RefCounted) -> Array[Dictionary]:
    var s := state as BeloteState
    match s.phase:
        BeloteState.Phase.BID_ROUND_1, BeloteState.Phase.BID_ROUND_2:
            return rules.bidding.legal_bids(s)
        BeloteState.Phase.PLAYING:
            var moves: Array[Dictionary] = []
            for card in legal_cards(s):
                moves.append({"kind": "play", "card": card})
            return moves
    return []


## The cards the seat to act may play now.
func legal_cards(state: BeloteState) -> Array[int]:
    return rules.trick_rule.legal_cards(state.hands[state.to_act], state.trick,
            state.trick_leader, state.to_act, state.trump, rules)


func apply(state: RefCounted, move: Dictionary) -> void:
    var s := state as BeloteState
    assert(legal_moves(s).has(move), "illegal move %s" % move)
    s.moves.append(move)
    if s.phase != BeloteState.Phase.PLAYING:
        s.bids.append({"seat": s.to_act, "kind": move.kind, "suit": move.get("suit", -1),
                "round": 1 if s.phase == BeloteState.Phase.BID_ROUND_1 else 2})
    if s.phase == BeloteState.Phase.PLAYING:
        _play(s, move.card)
        return
    match rules.bidding.apply_bid(s, move):
        BeloteBidding.Outcome.SECOND_ROUND:
            s.phase = BeloteState.Phase.BID_ROUND_2
            s.passes = 0
            s.to_act = BeloteState.next_seat(s.dealer)
        BeloteBidding.Outcome.REDEAL:
            s.dealer = BeloteState.next_seat(s.dealer)
            s.deal_number += 1
            _deal(s)
        BeloteBidding.Outcome.TAKEN:
            _finish_deal(s)


func is_over(state: RefCounted) -> bool:
    return (state as BeloteState).phase == BeloteState.Phase.GAME_OVER


func view_for(state: RefCounted, seat: int) -> Dictionary:
    var s := state as BeloteState
    var sizes: Array[int] = []
    for hand in s.hands:
        sizes.append(hand.size())
    return {
        "seat": seat,
        "phase": s.phase,
        "dealer": s.dealer,
        "to_act": s.to_act,
        "hand": (s.hands[seat] as Array[int]).duplicate(),
        "hand_sizes": sizes,
        "turned": s.turned,
        "taker": s.taker,
        "trump": s.trump,
        "trick": s.trick.duplicate(),
        "trick_leader": s.trick_leader,
        "last_trick": s.last_trick.duplicate(true),
        "scores": s.scores.duplicate(),
        "reserve": s.reserve,
        "last_hand": s.last_hand.duplicate(true),
        "played": s.played.duplicate(),
        "bids": s.bids.duplicate(true),
        "announce_points": s.announce_points.duplicate(),
        "announces": _declared(s),
        "announce_team": s.announce_team,
        "belote_seat": _belote_said(s),
        "winner": s.winner,
        "legal": legal_moves(s) if s.to_act == seat else [],
    }


## The seat that said « belote », once it has played the king or queen of trumps
## (everyone heard it), or -1.
func _belote_said(s: BeloteState) -> int:
    if s.belote_seat < 0 or s.phase != BeloteState.Phase.PLAYING:
        return -1
    if s.played.has(Cards.make(s.trump, Cards.Rank.ROI)) or s.played.has(Cards.make(s.trump, Cards.Rank.DAME)):
        return s.belote_seat
    return -1


## What the table knows of each seat's announces: their names once the seat has
## played its first card, and the cards of the winning team during the second trick.
func _declared(s: BeloteState) -> Array:
    var out := []
    for seat in BeloteState.SEATS:
        var list := []
        var declared: bool = s.phase == BeloteState.Phase.PLAYING and s.hands[seat].size() < 8
        var shown: bool = s.played.size() >= 4 and s.played.size() < 8 \
                and BeloteState.team_of(seat) == s.announce_team
        if declared and s.played.size() < 8:
            for announce in s.announces[seat]:
                var entry := {"name": announce.name, "points": announce.points}
                if shown:
                    entry.cards = (announce.cards as Array[int]).duplicate()
                list.append(entry)
        out.append(list)
    return out


## Deals 3 then 2 cards to each, from the dealer's left, and turns the next one.
func _deal(s: BeloteState) -> void:
    var deck := Cards.shuffled(s.seed_value * 1000003 + s.deal_number)
    s.hands = []
    for seat in BeloteState.SEATS:
        var hand: Array[int] = []
        s.hands.append(hand)
    var next := 0
    for count in [3, 2]:
        for k in BeloteState.SEATS:
            var seat := (s.dealer + 1 + k) % BeloteState.SEATS
            for i in count:
                s.hands[seat].append(deck[next])
                next += 1
    s.turned = deck[next]
    s.stock = deck.slice(next + 1)
    s.phase = BeloteState.Phase.BID_ROUND_1
    s.passes = 0
    s.taker = -1
    s.trump = -1
    s.belote_seat = -1
    s.trick.clear()
    s.last_trick = {}
    s.tricks_won = [0, 0]
    s.card_points = [0, 0]
    s.announce_points = [0, 0]
    s.announces = [[], [], [], []]
    s.announce_team = -1
    s.played.clear()
    s.bids.clear()
    s.to_act = BeloteState.next_seat(s.dealer)


## The taker gets the turned card and 2 more, the others 3 each.
func _finish_deal(s: BeloteState) -> void:
    s.hands[s.taker].append(s.turned)
    var next := 0
    for k in BeloteState.SEATS:
        var seat := (s.dealer + 1 + k) % BeloteState.SEATS
        var count := 2 if seat == s.taker else 3
        for i in count:
            s.hands[seat].append(s.stock[next])
            next += 1
    s.stock.clear()
    var king := Cards.make(s.trump, Cards.Rank.ROI)
    var queen := Cards.make(s.trump, Cards.Rank.DAME)
    for seat in BeloteState.SEATS:
        if s.hands[seat].has(king) and s.hands[seat].has(queen):
            s.belote_seat = seat
    if rules.announces_enabled:
        for seat in BeloteState.SEATS:
            s.announces[seat] = rules.announces.find(s.hands[seat])
    s.phase = BeloteState.Phase.PLAYING
    s.trick_leader = BeloteState.next_seat(s.dealer)
    s.to_act = s.trick_leader


func _play(s: BeloteState, card: int) -> void:
    s.hands[s.to_act].erase(card)
    s.trick.append(card)
    s.played.append(card)
    if s.trick.size() < BeloteState.SEATS:
        s.to_act = BeloteState.next_seat(s.to_act)
        return
    var winner := (s.trick_leader + BeloteCards.winning_index(s.trick, s.trump)) % BeloteState.SEATS
    var team := BeloteState.team_of(winner)
    for c in s.trick:
        s.card_points[team] += BeloteCards.points(c, s.trump)
    s.tricks_won[team] += 1
    s.last_trick = {"cards": s.trick.duplicate(), "leader": s.trick_leader, "winner": winner}
    s.trick.clear()
    if s.played.size() == BeloteState.SEATS:
        _settle_announces(s)
    s.trick_leader = winner
    s.to_act = winner
    if s.hands[winner].is_empty():
        s.card_points[team] += BeloteCards.DIX_DE_DER
        _end_hand(s)


## After the first trick, only the team with the best announce scores, all of its own.
func _settle_announces(s: BeloteState) -> void:
    s.announce_team = rules.announces.winning_team(s.announces, s.trick_leader, s.trump)
    if s.announce_team < 0:
        return
    for seat in BeloteState.SEATS:
        if BeloteState.team_of(seat) == s.announce_team:
            for announce in s.announces[seat]:
                s.announce_points[s.announce_team] += announce.points


func _end_hand(s: BeloteState) -> void:
    s.last_hand = rules.scoring.score_hand(s, rules)
    for team in 2:
        s.scores[team] += s.last_hand.points[team]
    s.reserve = s.last_hand.reserve
    var best := 0 if s.scores[0] > s.scores[1] else 1
    if s.scores[best] >= rules.target and s.scores[0] != s.scores[1]:
        s.winner = best
        s.phase = BeloteState.Phase.GAME_OVER
        return
    s.dealer = BeloteState.next_seat(s.dealer)
    s.deal_number += 1
    _deal(s)
