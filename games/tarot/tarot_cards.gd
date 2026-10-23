class_name TarotCards
## The 78-card Tarot deck (GDD §4.2). A card is an int:
## - 0-55: the four suits, suit * 14 + rank, rank 0-13 for 1..10, Valet,
##   Cavalier, Dame, Roi (suits in the order of `Cards.Suit`);
## - 56-76: the trumps (atouts) 1 to 21;
## - 77: the Excuse.
## Points are counted in half points, to stay in integers: the deck is worth 182
## half points (91 points).

const COUNT := 78
const TRUMP_BASE := 56
const EXCUSE := 77
const PETIT := TRUMP_BASE  # the 1 of trumps
const VINGT_ET_UN := TRUMP_BASE + 20
const OUDLERS := [PETIT, VINGT_ET_UN, EXCUSE]

enum Rank { R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, VALET, CAVALIER, DAME, ROI }

const RANK_LABELS := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "V", "C", "D", "R"]
## Half points by rank, for the suit cards.
const RANK_HALF_POINTS := [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 3, 5, 7, 9]
## The pseudo-suit of the trumps and of the Excuse.
const TRUMP_SUIT := 4
const EXCUSE_SUIT := 5


static func make(suit: int, rank: int) -> int:
    return suit * 14 + rank


static func trump(value: int) -> int:
    return TRUMP_BASE + value - 1


static func is_trump(card: int) -> bool:
    return card >= TRUMP_BASE and card < EXCUSE


## 0-3 for the suits, TRUMP_SUIT, or EXCUSE_SUIT.
static func suit_of(card: int) -> int:
    if card == EXCUSE:
        return EXCUSE_SUIT
    if is_trump(card):
        return TRUMP_SUIT
    return card / 14


static func rank_of(card: int) -> int:
    return card % 14 if card < TRUMP_BASE else -1


## The trump's number (1-21), or 0 for a suit card or the Excuse.
static func trump_value(card: int) -> int:
    return card - TRUMP_BASE + 1 if is_trump(card) else 0


static func is_oudler(card: int) -> bool:
    return card == PETIT or card == VINGT_ET_UN or card == EXCUSE


static func half_points(card: int) -> int:
    if is_oudler(card):
        return 9
    if is_trump(card):
        return 1
    return RANK_HALF_POINTS[rank_of(card)]


## Strength within its own suit (trumps by number); the Excuse has none.
static func strength(card: int) -> int:
    if card == EXCUSE:
        return -1
    return trump_value(card) if is_trump(card) else rank_of(card)


static func label(card: int) -> String:
    if card == EXCUSE:
        return "Excuse"
    if is_trump(card):
        return "%d d'atout" % trump_value(card)
    return "%s %s" % [RANK_LABELS[rank_of(card)], Cards.SUIT_NAMES[suit_of(card)]]


## All 78 cards shuffled with a seeded Fisher-Yates.
static func shuffled(seed_value: int) -> Array[int]:
    var deck: Array[int] = []
    for card in COUNT:
        deck.append(card)
    var rng := RandomNumberGenerator.new()
    rng.seed = seed_value
    for i in range(COUNT - 1, 0, -1):
        var j := rng.randi_range(0, i)
        var tmp := deck[i]
        deck[i] = deck[j]
        deck[j] = tmp
    return deck


## Index in `trick` of the card winning it: the highest trump, otherwise the
## highest card of the suit led (the first card that isn't the Excuse). The
## Excuse never wins, unless it is alone.
static func winning_index(trick: Array) -> int:
    var led := led_suit(trick)
    var best := -1
    for i in trick.size():
        var card: int = trick[i]
        if card == EXCUSE:
            continue
        if best < 0 or _beats(card, trick[best], led):
            best = i
    return maxi(best, 0)


## The suit to follow: that of the first card that isn't the Excuse, or -1.
static func led_suit(trick: Array) -> int:
    for card in trick:
        if card != EXCUSE:
            return suit_of(card)
    return -1


static func _beats(card: int, other: int, led: int) -> bool:
    var suit := suit_of(card)
    var other_suit := suit_of(other)
    if suit == other_suit:
        return strength(card) > strength(other)
    if suit == TRUMP_SUIT:
        return true
    if other_suit == TRUMP_SUIT:
        return false
    return suit == led
