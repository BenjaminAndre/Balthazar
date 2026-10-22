class_name Cards
## The 32-card piquet deck used by Belote, Coinche and Manille.
##
## A card is a plain int (0-31) so game states copy, compare and travel over the
## network cheaply: suit = card / 8, rank = card % 8. Tarot will get its own
## 78-card encoding.

enum Suit { PIQUE, COEUR, CARREAU, TREFLE }
enum Rank { SEPT, HUIT, NEUF, DIX, VALET, DAME, ROI, AS }

const COUNT := 32
const SUIT_LETTERS := ["P", "Co", "Ca", "T"]
const SUIT_NAMES := ["pique", "cœur", "carreau", "trèfle"]
const RANK_LETTERS := ["7", "8", "9", "10", "V", "D", "R", "A"]


static func make(suit: Suit, rank: Rank) -> int:
    return suit * 8 + rank


static func suit_of(card: int) -> Suit:
    return (card / 8) as Suit


static func rank_of(card: int) -> Rank:
    return (card % 8) as Rank


## Short Latin-only label such as "VT" (valet de trefle): non-Latin glyphs
## don't render in exported builds with the default font.
static func label(card: int) -> String:
    return RANK_LETTERS[rank_of(card)] + SUIT_LETTERS[suit_of(card)]


## All 32 cards shuffled with a seeded Fisher-Yates, so a seed replays a deal.
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
