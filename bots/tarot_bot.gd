class_name TarotBot
extends RefCounted
## « Facile » at the Tarot (GDD §5): simple rules on its own view only.
## - Bids by a rough hand value: oudlers, trumps, kings.
## - Calls (five players) the king of its longest suit it doesn't hold.
## - Discards its smallest cards, from its shortest suits.
## - Plays: wins a trick worth having as cheaply as it can, gives points to a
##   trick its side surely holds, otherwise plays small; saves the Petit and
##   doesn't keep the Excuse for the last trick.

## Hand value needed for each contract, for an 18-card hand (scaled by hand size).
var thresholds := {TarotState.Contract.PETITE: 40, TarotState.Contract.GARDE: 56,
        TarotState.Contract.GARDE_SANS: 76, TarotState.Contract.GARDE_CONTRE: 92}


func choose(view: Dictionary) -> Dictionary:
    var legal: Array = view.legal
    if legal.size() == 1:
        return legal[0]
    match int(view.phase):
        TarotState.Phase.BIDDING:
            return _bid(view)
        TarotState.Phase.CALLING:
            return _call(view)
        TarotState.Phase.ECART:
            return _discard(view)
    return {"kind": "play", "card": _card(view)}


## Oudlers, trumps (big ones count more), kings and queens, scaled to 18 cards.
static func hand_value(hand: Array) -> float:
    var value := 0.0
    for card in hand:
        if TarotCards.is_oudler(card):
            value += 10.0
        elif TarotCards.is_trump(card):
            value += 2.0 + (1.5 if TarotCards.trump_value(card) >= 15 else 0.0)
        elif TarotCards.rank_of(card) == TarotCards.Rank.ROI:
            value += 6.0
        elif TarotCards.rank_of(card) == TarotCards.Rank.DAME:
            value += 2.0
    return value * 18.0 / maxf(hand.size(), 1)


func _bid(view: Dictionary) -> Dictionary:
    var value := hand_value(view.hand)
    var best := {"kind": "bid", "contract": TarotState.Contract.NONE}
    for move in view.legal:
        if move.contract > best.contract and value >= thresholds.get(move.contract, 999):
            best = move
    return best


func _call(view: Dictionary) -> Dictionary:
    var best: Dictionary = view.legal[0]
    var best_count := -1
    for move in view.legal:
        if view.hand.has(move.card):
            continue
        var count := 0
        for card in view.hand:
            if TarotCards.suit_of(card) == TarotCards.suit_of(move.card):
                count += 1
        if count > best_count:
            best = move
            best_count = count
    return best


func _discard(view: Dictionary) -> Dictionary:
    var best: Dictionary = view.legal[0]
    var best_cost := INF
    for move in view.legal:
        var card: int = move.card
        var count := 0
        for c in view.hand:
            if TarotCards.suit_of(c) == TarotCards.suit_of(card):
                count += 1
        # Short suits first (to cut them later), and small cards before big ones.
        var cost := count * 10.0 + TarotCards.half_points(card) * 3.0 + TarotCards.strength(card)
        if TarotCards.is_trump(card):
            cost += 1000.0
        if cost < best_cost:
            best = move
            best_cost = cost
    return best


func _card(view: Dictionary) -> int:
    var cards: Array[int] = []
    for move in view.legal:
        cards.append(move.card)
    var trick: Array = view.trick
    var hand: Array = view.hand
    # Never keep the Excuse for the last trick, where it would be lost.
    if cards.has(TarotCards.EXCUSE) and hand.size() <= 2:
        return TarotCards.EXCUSE
    if trick.is_empty():
        return _lead(cards, view)
    var players: int = view.players
    var seat: int = view.seat
    var winner := (int(view.trick_leader) + TarotCards.winning_index(trick)) % players
    var on_table := 0
    for c in trick:
        on_table += TarotCards.half_points(c)
    var last := trick.size() == players - 1
    if _same_side(winner, seat, view):
        # Our side holds it: give points if we're last, otherwise play small.
        return _most_points(cards) if last else _smallest(cards)
    var winners: Array[int] = []
    for card in cards:
        if card == TarotCards.EXCUSE:
            continue
        var after := trick.duplicate()
        after.append(card)
        if TarotCards.winning_index(after) == trick.size():
            winners.append(card)
    if not winners.is_empty() and (last or on_table >= 5):
        return _cheapest_winner(winners)
    # Can't (or needn't) win: the Excuse saves a good card, otherwise play small.
    var smallest := _smallest(cards)
    if cards.has(TarotCards.EXCUSE) and TarotCards.half_points(smallest) >= 5:
        return TarotCards.EXCUSE
    return smallest


func _lead(cards: Array[int], view: Dictionary) -> int:
    var taker: bool = int(view.taker) == int(view.seat)
    var best := -1
    var best_score := -INF
    for card in cards:
        if card == TarotCards.EXCUSE or card == TarotCards.PETIT:
            continue
        var score := 0.0
        if TarotCards.is_trump(card):
            # The taker draws trumps with big ones; the defence leads suits.
            score = (TarotCards.trump_value(card) / 21.0) * (2.0 if taker else -2.0)
        else:
            # Kings first, otherwise small cards.
            score = 3.0 if TarotCards.rank_of(card) == TarotCards.Rank.ROI else -TarotCards.half_points(card) / 3.0
        if score > best_score:
            best = card
            best_score = score
    return best if best >= 0 else cards[0]


func _same_side(a: int, b: int, view: Dictionary) -> bool:
    if a == b:
        return true
    var taker: int = view.taker
    var partner: int = view.partner
    var a_taker := a == taker or (partner >= 0 and a == partner)
    var b_taker := b == taker or (partner >= 0 and b == partner)
    # At five, before the call is revealed, a defender only trusts known defenders.
    if int(view.players) == 5 and partner < 0 and not b_taker:
        return false
    return a_taker == b_taker


func _smallest(cards: Array[int]) -> int:
    var best := -1
    for card in cards:
        if card == TarotCards.EXCUSE:
            continue
        if card == TarotCards.PETIT and cards.size() > 1:
            continue
        if best < 0 or _value(card) < _value(best):
            best = card
    return best if best >= 0 else cards[0]


func _most_points(cards: Array[int]) -> int:
    var best := -1
    for card in cards:
        if card == TarotCards.EXCUSE:
            continue
        if TarotCards.is_trump(card) and not TarotCards.is_oudler(card):
            continue
        if card == TarotCards.VINGT_ET_UN:
            continue
        if best < 0 or TarotCards.half_points(card) > TarotCards.half_points(best):
            best = card
    return best if best >= 0 else _smallest(cards)


func _cheapest_winner(winners: Array[int]) -> int:
    var best := winners[0]
    for card in winners:
        if _value(card) < _value(best):
            best = card
    return best


## For giving away: points first, then strength; trumps cost more than suit cards.
func _value(card: int) -> float:
    var value := TarotCards.half_points(card) * 10.0 + TarotCards.strength(card)
    if TarotCards.is_trump(card):
        value += 30.0
    return value
