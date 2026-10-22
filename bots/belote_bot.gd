class_name BeloteBot
extends RefCounted
## A rule-of-thumb Belote player (GDD §5). It sees only `Belote.view_for()`, like
## a human, so a stronger bot can replace it by overriding `choose()`.

## Hand value needed to take on the first round, and on the second.
var take_threshold := 50
var take_threshold_second := 56


## The move this seat makes, from its view of the table.
func choose(view: Dictionary) -> Dictionary:
    var legal: Array = view.legal
    if legal.size() == 1:
        return legal[0]
    if view.phase == BeloteState.Phase.PLAYING:
        return {"kind": "play", "card": _card(view)}
    return _bid(view)


func _bid(view: Dictionary) -> Dictionary:
    var hand: Array[int] = []
    hand.assign(view.hand)
    hand.append(view.turned)
    var best := {"kind": "pass"}
    var best_value := take_threshold if view.phase == BeloteState.Phase.BID_ROUND_1 \
            else take_threshold_second
    for move in view.legal:
        if move.kind == "take":
            var value := hand_value(hand, move.suit)
            if value >= best_value:
                best = move
                best_value = value
    return best


## A rough strength of `hand` with `trump` as trumps.
static func hand_value(hand: Array[int], trump: int) -> int:
    var value := 0
    var has_king := false
    var has_queen := false
    for card in hand:
        var rank := Cards.rank_of(card)
        if Cards.suit_of(card) == trump:
            value += maxi(BeloteCards.TRUMP_POINTS[rank], 2) + 4
            has_king = has_king or rank == Cards.Rank.ROI
            has_queen = has_queen or rank == Cards.Rank.DAME
        elif rank == Cards.Rank.AS:
            value += 11
        elif rank == Cards.Rank.DIX and hand.has(Cards.make(Cards.suit_of(card), Cards.Rank.AS)):
            value += 5
    if has_king and has_queen:
        value += 10
    return value


func _card(view: Dictionary) -> int:
    var legal: Array[int] = []
    for move in view.legal:
        legal.append(move.card)
    var trump: int = view.trump
    var trick: Array[int] = []
    trick.assign(view.trick)
    var unseen := _unseen(view)
    if trick.is_empty():
        return _lead(legal, view, unseen)
    var seat: int = view.seat
    var master := (int(view.trick_leader) + BeloteCards.winning_index(trick, trump)) % 4
    if master % 2 == seat % 2:
        return _charge(legal, trump)
    var winners: Array[int] = []
    for card in legal:
        var after := trick.duplicate()
        after.append(card)
        if BeloteCards.winning_index(after, trump) == trick.size():
            winners.append(card)
    if not winners.is_empty():
        return _weakest(winners, trump)
    return _cheapest(legal, trump)


## Leads a master trump when our side took, else a master card elsewhere,
## else a small card.
func _lead(legal: Array[int], view: Dictionary, unseen: Array[int]) -> int:
    var trump: int = view.trump
    var ours := int(view.taker) % 2 == int(view.seat) % 2
    var trumps_out := unseen.any(func(c: int) -> bool: return Cards.suit_of(c) == trump)
    var masters: Array[int] = []
    for card in legal:
        if _is_master(card, unseen, trump):
            masters.append(card)
    for card in masters:
        if Cards.suit_of(card) == trump and ours and trumps_out:
            return card
    for card in masters:
        if Cards.suit_of(card) != trump:
            return card
    var plain: Array[int] = []
    for card in legal:
        if Cards.suit_of(card) != trump:
            plain.append(card)
    return _cheapest(legal if plain.is_empty() else plain, trump)


## Partner holds the trick: give it points, but keep trumps.
func _charge(legal: Array[int], trump: int) -> int:
    var best := -1
    for card in legal:
        if Cards.suit_of(card) == trump:
            continue
        if best < 0 or BeloteCards.points(card, trump) > BeloteCards.points(best, trump):
            best = card
    return best if best >= 0 else _cheapest(legal, trump)


func _weakest(cards: Array[int], trump: int) -> int:
    var best := cards[0]
    for card in cards:
        if _cost(card, trump) < _cost(best, trump):
            best = card
    return best


## The card worth least to give away: few points, not a trump, low.
func _cheapest(cards: Array[int], trump: int) -> int:
    return _weakest(cards, trump)


func _cost(card: int, trump: int) -> int:
    var trump_cost := 100 if Cards.suit_of(card) == trump else 0
    return trump_cost + BeloteCards.points(card, trump) * 10 + BeloteCards.strength(card, trump)


func _is_master(card: int, unseen: Array[int], trump: int) -> bool:
    for other in unseen:
        if Cards.suit_of(other) == Cards.suit_of(card) \
                and BeloteCards.strength(other, trump) > BeloteCards.strength(card, trump):
            return false
    return true


## Cards neither in our hand nor played yet.
func _unseen(view: Dictionary) -> Array[int]:
    var out: Array[int] = []
    for card in Cards.COUNT:
        if not view.hand.has(card) and not view.played.has(card):
            out.append(card)
    return out
