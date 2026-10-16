extends GutTest
## Dealing and bidding (GDD §3.2).

var game := Belote.new()


func test_first_deal() -> void:
    var s: BeloteState = game.new_state(1)
    assert_eq(s.dealer, 0)
    assert_eq(s.to_act, 1, "the dealer's left speaks first")
    for hand in s.hands:
        assert_eq(hand.size(), 5)
    assert_eq(s.stock.size(), 11)
    assert_between(s.turned, 0, 31)


func test_take_on_first_round_completes_the_deal() -> void:
    var s: BeloteState = game.new_state(1)
    var turned := s.turned
    game.apply(s, {"kind": "pass"})
    game.apply(s, {"kind": "take", "suit": Cards.suit_of(turned)})
    assert_eq(s.taker, 2)
    assert_eq(s.trump, Cards.suit_of(turned))
    assert_eq(s.phase, BeloteState.Phase.PLAYING)
    assert_true(s.hands[2].has(turned))
    var seen: Dictionary = {}
    for hand in s.hands:
        assert_eq(hand.size(), 8)
        for card in hand:
            seen[card] = true
    assert_eq(seen.size(), 32)
    assert_eq(s.to_act, 1, "the dealer's left leads")


func test_second_round_offers_other_suits() -> void:
    var s: BeloteState = game.new_state(1)
    for i in 4:
        game.apply(s, {"kind": "pass"})
    assert_eq(s.phase, BeloteState.Phase.BID_ROUND_2)
    assert_eq(s.to_act, 1)
    var takes := game.legal_moves(s).filter(func(m: Dictionary) -> bool: return m.kind == "take")
    assert_eq(takes.size(), 3)
    for m in takes:
        assert_ne(m.suit, Cards.suit_of(s.turned))


func test_eight_passes_redeal_with_next_dealer() -> void:
    var s: BeloteState = game.new_state(1)
    for i in 8:
        game.apply(s, {"kind": "pass"})
    assert_eq(s.phase, BeloteState.Phase.BID_ROUND_1)
    assert_eq(s.dealer, 1)
    assert_eq(s.to_act, 2)
    assert_eq(s.deal_number, 1)


func test_belote_holder_is_found() -> void:
    for seed_value in 30:
        var s: BeloteState = game.new_state(seed_value)
        game.apply(s, {"kind": "take", "suit": Cards.suit_of(s.turned)})
        var king := Cards.make(s.trump, Cards.Rank.ROI)
        var queen := Cards.make(s.trump, Cards.Rank.DAME)
        var holder := -1
        for seat in 4:
            if s.hands[seat].has(king) and s.hands[seat].has(queen):
                holder = seat
        assert_eq(s.belote_seat, holder)


func test_view_hides_other_hands() -> void:
    var s: BeloteState = game.new_state(3)
    var view := game.view_for(s, 2)
    assert_eq(view.hand, s.hands[2])
    assert_false(view.has("hands"))
    assert_false(view.has("stock"))
    assert_eq(view.legal, [], "not seat 2's turn")
    assert_false(game.view_for(s, 1).legal.is_empty())
