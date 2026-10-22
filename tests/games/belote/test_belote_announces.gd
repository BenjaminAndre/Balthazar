extends GutTest
## GDD §3.6.

const P := Cards.Suit.PIQUE
const CO := Cards.Suit.COEUR
const CA := Cards.Suit.CARREAU
const T := Cards.Suit.TREFLE
const R := Cards.Rank

var announces := BeloteAnnounces.new()


func c(suit: int, rank: int) -> int:
    return Cards.make(suit, rank)


func hand(list: Array) -> Array[int]:
    var out: Array[int] = []
    out.assign(list)
    return out


func names(found: Array[Dictionary]) -> Array:
    return found.map(func(a: Dictionary) -> String: return "%s %d" % [a.name, a.points])


func test_sequences() -> void:
    var found := announces.find(hand([c(P, R.SEPT), c(P, R.HUIT), c(P, R.NEUF),
            c(CO, R.DIX), c(CO, R.VALET), c(CO, R.DAME), c(CO, R.ROI), c(T, R.AS)]))
    assert_eq(names(found), ["Tierce 20", "Cinquante 50"])


func test_cent_and_long_run() -> void:
    var found := announces.find(hand([c(CA, R.SEPT), c(CA, R.HUIT), c(CA, R.NEUF), c(CA, R.DIX),
            c(CA, R.VALET), c(CA, R.DAME), c(P, R.AS), c(T, R.AS)]))
    assert_eq(names(found), ["Cent 100"])
    assert_eq(found[0].length, 6)
    assert_eq(found[0].top, R.DAME)


func test_run_ending_on_ace() -> void:
    var found := announces.find(hand([c(T, R.DAME), c(T, R.ROI), c(T, R.AS),
            c(P, R.SEPT), c(CO, R.NEUF), c(CA, R.DIX), c(P, R.VALET), c(CO, R.SEPT)]))
    assert_eq(names(found), ["Tierce 20"])
    assert_eq(found[0].top, R.AS)


func test_carres() -> void:
    var valets := hand([c(P, R.VALET), c(CO, R.VALET), c(CA, R.VALET), c(T, R.VALET),
            c(P, R.SEPT), c(CO, R.SEPT), c(CA, R.SEPT), c(T, R.SEPT)])
    assert_eq(names(announces.find(valets)), ["Carré de valets 200"], "carré de 7 worth nothing")
    var neufs := hand([c(P, R.NEUF), c(CO, R.NEUF), c(CA, R.NEUF), c(T, R.NEUF)])
    assert_eq(names(announces.find(neufs)), ["Carré de 9 150"])
    var huits := hand([c(P, R.HUIT), c(CO, R.HUIT), c(CA, R.HUIT), c(T, R.HUIT)])
    assert_eq(names(announces.find(huits)), [])


func test_card_counts_in_one_announce_only() -> void:
    var found := announces.find(hand([c(P, R.ROI), c(CO, R.ROI), c(CA, R.ROI), c(T, R.ROI),
            c(P, R.DAME), c(P, R.VALET)]))
    assert_eq(names(found), ["Carré de rois 100"], "the king of spades is in the carré")
    found = announces.find(hand([c(P, R.ROI), c(CO, R.ROI), c(CA, R.ROI), c(T, R.ROI),
            c(P, R.DAME), c(P, R.VALET), c(P, R.DIX)]))
    assert_eq(names(found), ["Carré de rois 100", "Tierce 20"], "D V 10 without the king")


func test_comparison() -> void:
    var tierce_as := {"kind": "suite", "points": 20, "length": 3, "top": R.AS, "suit": P}
    var tierce_roi := {"kind": "suite", "points": 20, "length": 3, "top": R.ROI, "suit": CO}
    var tierce_as_trump := {"kind": "suite", "points": 20, "length": 3, "top": R.AS, "suit": CO}
    var cinquante := {"kind": "suite", "points": 50, "length": 4, "top": R.DIX, "suit": T}
    assert_true(announces.beats(tierce_as, tierce_roi, CO), "higher top")
    assert_true(announces.beats(cinquante, tierce_as, CO), "more points")
    assert_true(announces.beats(tierce_as_trump, tierce_as, CO), "equal, in trumps")
    assert_false(announces.beats(tierce_as, tierce_as_trump, CO))
    var plain := {"kind": "suite", "points": 20, "length": 3, "top": R.AS, "suit": T}
    assert_false(announces.beats(plain, tierce_as, CO), "full tie: first to speak keeps it")


func test_winning_team_and_points() -> void:
    var tierce := {"kind": "suite", "points": 20, "length": 3, "top": R.ROI, "suit": P, "name": "Tierce"}
    var better := {"kind": "suite", "points": 20, "length": 3, "top": R.AS, "suit": T, "name": "Tierce"}
    assert_eq(announces.winning_team([[tierce], [better], [], []], 0, CO), 1)
    assert_eq(announces.winning_team([[tierce], [tierce.duplicate()], [], []], 1, CO), 1, "seat 1 speaks first")
    assert_eq(announces.winning_team([[], [], [], []], 0, CO), -1)


func test_announces_score_after_first_trick() -> void:
    var game := Belote.new()
    for seed_value in 200:
        var s: BeloteState = game.new_state(seed_value)
        game.apply(s, {"kind": "take", "suit": Cards.suit_of(s.turned)})
        var any := false
        for list in s.announces:
            any = any or not list.is_empty()
        if not any:
            continue
        for i in 4:
            game.apply(s, game.legal_moves(s)[0])
        assert_ne(s.announce_team, -1)
        var expected := 0
        for seat in 4:
            if seat % 2 == s.announce_team:
                for a in s.announces[seat]:
                    expected += a.points
        assert_eq(s.announce_points[s.announce_team], expected)
        assert_eq(s.announce_points[1 - s.announce_team], 0)
        var view := game.view_for(s, 0)
        var shown := false
        for seat in 4:
            for a in view.announces[seat]:
                shown = shown or a.has("cards")
        assert_true(shown, "winning cards shown during the second trick")
        return
    fail_test("no hand with announces in 200 seeds")
