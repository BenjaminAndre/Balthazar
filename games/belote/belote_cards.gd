class_name BeloteCards
## Card strengths and points in Belote (GDD §3.3).
## Arrays are indexed by `Cards.Rank`: 7, 8, 9, 10, V, D, R, A.

const TRUMP_STRENGTH := [0, 1, 6, 4, 7, 2, 3, 5]  # V 9 A 10 R D 8 7
const PLAIN_STRENGTH := [0, 1, 2, 6, 3, 4, 5, 7]  # A 10 R D V 9 8 7
const TRUMP_POINTS := [0, 0, 14, 10, 20, 3, 4, 11]
const PLAIN_POINTS := [0, 0, 0, 10, 2, 3, 4, 11]
const DIX_DE_DER := 10


static func strength(card: int, trump: int) -> int:
    var rank := Cards.rank_of(card)
    return TRUMP_STRENGTH[rank] if Cards.suit_of(card) == trump else PLAIN_STRENGTH[rank]


static func points(card: int, trump: int) -> int:
    var rank := Cards.rank_of(card)
    return TRUMP_POINTS[rank] if Cards.suit_of(card) == trump else PLAIN_POINTS[rank]


## Index in `trick` of the card currently winning it: the best trump if any,
## otherwise the best card of the suit led.
static func winning_index(trick: Array[int], trump: int) -> int:
    var best := 0
    for i in range(1, trick.size()):
        if _beats(trick[i], trick[best], Cards.suit_of(trick[0]), trump):
            best = i
    return best


static func _beats(card: int, other: int, led: int, trump: int) -> bool:
    var suit := Cards.suit_of(card)
    var other_suit := Cards.suit_of(other)
    if suit == other_suit:
        return strength(card, trump) > strength(other, trump)
    if suit == trump:
        return true
    if other_suit == trump:
        return false
    return suit == led
