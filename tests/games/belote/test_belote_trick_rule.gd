extends GutTest
## GDD §3.4. Trump is coeur in every test.

const P := Cards.Suit.PIQUE
const CO := Cards.Suit.COEUR
const T := Cards.Suit.TREFLE
const R := Cards.Rank

var rules: BeloteRules
var rule := BeloteTrickRule.new()


func before_each() -> void:
    rules = BeloteRules.new()


func c(suit: int, rank: int) -> int:
    return Cards.make(suit, rank)


func cards(list: Array) -> Array[int]:
    var out: Array[int] = []
    out.assign(list)
    return out


func legal(hand: Array, trick: Array, leader: int, seat: int) -> Array[int]:
    var result := rule.legal_cards(cards(hand), cards(trick), leader, seat, CO, rules)
    result.sort()
    return result


func sorted(list: Array) -> Array[int]:
    var out := cards(list)
    out.sort()
    return out


func test_lead_anything() -> void:
    var hand := [c(P, R.SEPT), c(CO, R.AS)]
    assert_eq(legal(hand, [], 0, 0), sorted(hand))


func test_must_follow_suit() -> void:
    assert_eq(legal([c(P, R.SEPT), c(T, R.DIX), c(CO, R.VALET)], [c(P, R.AS)], 0, 1),
            sorted([c(P, R.SEPT)]))


func test_must_climb_at_trump() -> void:
    var trick := [c(CO, R.NEUF)]
    assert_eq(legal([c(CO, R.VALET), c(CO, R.AS), c(P, R.SEPT)], trick, 0, 1),
            sorted([c(CO, R.VALET)]))
    assert_eq(legal([c(CO, R.AS), c(CO, R.SEPT), c(P, R.SEPT)], trick, 0, 1),
            sorted([c(CO, R.AS), c(CO, R.SEPT)]), "can't climb: any trump")


func test_must_trump_when_opponent_master() -> void:
    assert_eq(legal([c(CO, R.SEPT), c(CO, R.HUIT), c(T, R.ROI)], [c(P, R.AS)], 0, 1),
            sorted([c(CO, R.SEPT), c(CO, R.HUIT)]))


func test_free_when_partner_master() -> void:
    var hand := [c(CO, R.SEPT), c(T, R.ROI)]
    var trick := [c(P, R.AS), c(P, R.SEPT)]
    assert_eq(legal(hand, trick, 0, 2), sorted(hand))
    rules.must_trump_over_partner = true
    assert_eq(legal(hand, trick, 0, 2), sorted([c(CO, R.SEPT)]), "variant")


func test_must_overtrump() -> void:
    var trick := [c(P, R.AS), c(CO, R.NEUF)]
    assert_eq(legal([c(CO, R.VALET), c(CO, R.HUIT), c(T, R.ROI)], trick, 0, 2),
            sorted([c(CO, R.VALET)]))


func test_must_undertrump_when_cannot_overtrump() -> void:
    var hand := [c(CO, R.HUIT), c(CO, R.SEPT), c(T, R.ROI)]
    var trick := [c(P, R.AS), c(CO, R.NEUF)]
    assert_eq(legal(hand, trick, 0, 2), sorted([c(CO, R.HUIT), c(CO, R.SEPT)]), "pisser")
    rules.free_undertrump = true
    assert_eq(legal(hand, trick, 0, 2), sorted(hand), "variant")


func test_discard_without_suit_or_trump() -> void:
    var hand := [c(T, R.ROI), c(Cards.Suit.CARREAU, R.SEPT)]
    assert_eq(legal(hand, [c(P, R.AS)], 0, 1), sorted(hand))


func test_trick_winner() -> void:
    assert_eq(BeloteCards.winning_index(cards([c(P, R.AS), c(P, R.DIX), c(CO, R.SEPT)]), CO), 2)
    assert_eq(BeloteCards.winning_index(cards([c(P, R.SEPT), c(T, R.AS)]), CO), 0)
    assert_eq(BeloteCards.winning_index(cards([c(CO, R.AS), c(CO, R.NEUF), c(CO, R.VALET)]), CO), 2)
    assert_eq(BeloteCards.winning_index(cards([c(P, R.VALET), c(P, R.DIX)]), CO), 1)


func test_deck_is_worth_152() -> void:
    for trump in 4:
        var total := 0
        for card in Cards.COUNT:
            total += BeloteCards.points(card, trump)
        assert_eq(total, 152)
