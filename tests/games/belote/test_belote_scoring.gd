extends GutTest
## GDD §3.7.

var rules: BeloteRules


func before_each() -> void:
    rules = BeloteRules.new()


func hand(taker: int, cards: Array, tricks: Array = [4, 4], belote_seat := -1) -> BeloteState:
    var s := BeloteState.new()
    s.taker = taker
    s.card_points.assign(cards)
    s.tricks_won.assign(tricks)
    s.belote_seat = belote_seat
    return s


func score(s: BeloteState) -> Dictionary:
    return rules.scoring.score_hand(s, rules)


func test_rounding() -> void:
    assert_eq(BeloteScoring.round_points(15, rules), 1)
    assert_eq(BeloteScoring.round_points(16, rules), 2)
    assert_eq(BeloteScoring.round_points(17, rules), 2)
    assert_eq(BeloteScoring.round_points(162, rules), 16)
    rules.rounded_scores = false
    assert_eq(BeloteScoring.round_points(15, rules), 15)


func test_contract_made() -> void:
    var r := score(hand(0, [92, 70]))
    assert_eq(r.outcome, "fait")
    assert_eq(r.points, [9, 7])


func test_both_sixes_make_17() -> void:
    assert_eq(score(hand(0, [96, 66])).points, [10, 7])


func test_contract_judged_on_raw_points() -> void:
    var r := score(hand(0, [82, 80]))
    assert_eq(r.outcome, "fait")
    assert_eq(r.points, [8, 8])


func test_dedans() -> void:
    var r := score(hand(0, [70, 92]))
    assert_eq(r.outcome, "dedans")
    assert_eq(r.raw, [0, 162])
    assert_eq(r.points, [0, 16])


func test_belote_stays_with_holder_when_dedans() -> void:
    var r := score(hand(0, [60, 102], [4, 4], 2))
    assert_eq(r.outcome, "dedans")
    assert_eq(r.raw, [20, 162])
    assert_eq(r.points, [2, 16])


func test_belote_can_save_the_contract() -> void:
    var r := score(hand(1, [86, 76], [4, 4], 3))
    assert_eq(r.outcome, "fait", "76 + 20 beats 86")
    assert_eq(r.raw, [86, 96])


func test_capot() -> void:
    var r := score(hand(0, [162, 0], [8, 0]))
    assert_eq(r.raw, [250, 0])
    assert_eq(r.points, [25, 0])


func test_defence_capot() -> void:
    var r := score(hand(0, [0, 162], [0, 8]))
    assert_eq(r.outcome, "dedans")
    assert_eq(r.raw, [0, 250])


func test_litige_reserve_goes_to_next_winner() -> void:
    var first := score(hand(0, [81, 81]))
    assert_eq(first.outcome, "litige")
    assert_eq(first.points, [0, 8])
    assert_eq(first.reserve, 81)
    var next := hand(1, [70, 92])
    next.reserve = first.reserve
    var r := score(next)
    assert_eq(r.outcome, "fait")
    assert_eq(r.points, [7, 17], "9 + the 8 held back")
    assert_eq(r.reserve, 0)


func test_unrounded_variant() -> void:
    rules.rounded_scores = false
    assert_eq(score(hand(0, [92, 70])).points, [92, 70])
