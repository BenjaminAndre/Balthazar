extends GutTest


func test_make_round_trips_suit_and_rank() -> void:
    var card := Cards.make(Cards.Suit.TREFLE, Cards.Rank.VALET)
    assert_eq(Cards.suit_of(card), Cards.Suit.TREFLE)
    assert_eq(Cards.rank_of(card), Cards.Rank.VALET)
    assert_eq(Cards.label(card), "VT")


func test_shuffle_is_a_permutation() -> void:
    var deck := Cards.shuffled(42)
    assert_eq(deck.size(), 32)
    var sorted := deck.duplicate()
    sorted.sort()
    for i in 32:
        assert_eq(sorted[i], i)


func test_same_seed_same_deal() -> void:
    assert_eq(Cards.shuffled(7), Cards.shuffled(7))
    assert_ne(Cards.shuffled(7), Cards.shuffled(8))
