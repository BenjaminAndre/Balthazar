extends GutTest
## v0.2.7 settings: relance à 12, fin automatique, and the defaults.

const CO := Cards.Suit.COEUR
const P := Cards.Suit.PIQUE
const T := Cards.Suit.TREFLE
const R := Cards.Rank


func c(suit: int, rank: int) -> int:
    return Cards.make(suit, rank)


func test_defaults_fill_missing_settings() -> void:
    var settings := TableSettings.complete({"belote": {"relance_12": true}})
    assert_true(settings.general.auto_finish)
    assert_true(settings.belote.announces)
    assert_true(settings.belote.relance_12)
    var rules := TableSettings.belote_rules(settings)
    assert_eq(rules.redeal_max_points, 11)


func test_relance_offered_to_a_weak_hand_and_redeals() -> void:
    var rules := BeloteRules.new()
    rules.redeal_max_points = 11
    var game := Belote.new(rules)
    for seed_value in 300:
        var s: BeloteState = game.new_state(seed_value)
        var weak := BeloteBidding.hand_points(s.hands[s.to_act]) <= 11
        var moves := game.legal_moves(s)
        assert_eq(moves.has({"kind": "relance"}), weak)
        if weak:
            game.apply(s, {"kind": "relance"})
            assert_eq(s.deal_number, 1)
            assert_eq(s.dealer, 1, "the deal passes on")
            return
    fail_test("no weak hand in 300 deals")


func test_relance_off_by_default() -> void:
    var game := Belote.new()
    for seed_value in 50:
        assert_false(game.legal_moves(game.new_state(seed_value)).has({"kind": "relance"}))


func _host_with(hands: Array) -> TableHost:
    var host := TableHost.new()
    host.auto_bots = false
    add_child_autofree(host)
    host.start(1)
    var s := host.state
    s.phase = BeloteState.Phase.PLAYING
    s.trump = CO
    s.taker = 0
    s.to_act = 0
    s.trick.clear()
    s.hands = []
    for h in hands:
        var typed: Array[int] = []
        typed.assign(h)
        s.hands.append(typed)
    return host


func test_auto_finish_plays_trumps_first_when_everything_wins() -> void:
    var host := _host_with([[c(CO, R.VALET), c(P, R.AS)], [c(CO, R.SEPT), c(P, R.SEPT)],
            [c(P, R.HUIT), c(T, R.NEUF)], [c(T, R.DIX), c(T, R.HUIT)]])
    assert_eq(host.auto_finish_card(), c(CO, R.VALET))


func test_no_auto_finish_when_an_opponent_keeps_a_trump() -> void:
    var host := _host_with([[c(CO, R.VALET), c(P, R.AS)], [c(CO, R.SEPT), c(CO, R.HUIT)],
            [c(P, R.HUIT), c(T, R.NEUF)], [c(T, R.DIX), c(T, R.HUIT)]])
    assert_eq(host.auto_finish_card(), -1, "two trumps against one: the ace could be cut")


func test_no_auto_finish_when_turned_off() -> void:
    var host := _host_with([[c(CO, R.VALET), c(P, R.AS)], [c(CO, R.SEPT), c(P, R.SEPT)],
            [c(P, R.HUIT), c(T, R.NEUF)], [c(T, R.DIX), c(T, R.HUIT)]])
    host.settings = TableSettings.complete({"general": {"auto_finish": false}})
    assert_eq(host.auto_finish_card(), -1)
