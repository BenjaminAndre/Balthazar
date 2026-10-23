extends GutTest
## The bot levels: what « Difficile » remembers, and that every level only plays legal moves.

const P := Cards.Suit.PIQUE
const CO := Cards.Suit.COEUR
const T := Cards.Suit.TREFLE
const R := Cards.Rank


func c(suit: int, rank: int) -> int:
    return Cards.make(suit, rank)


## A view of seat 0 in the middle of a hand, trumps at coeur, dealer 3 (seat 0 led first).
func view_after(played: Array, hand: Array) -> Dictionary:
    return {"seat": 0, "trump": CO, "dealer": 3, "hand": hand, "played": played,
            "trick": played.slice(played.size() - played.size() % 4), "trick_leader": 0,
            "taker": 0, "hand_sizes": [hand.size(), 8, 8, 8]}


func test_memory_sees_voids_caps_and_calls() -> void:
    # Trick 1, led by seat 0: seat 1 can't follow pique and doesn't cut while
    # seat 0 holds the trick, so it is out of pique and of coeur (trumps).
    # Seat 2, whose partner (0) holds the trick, discards a small trefle: a call.
    # Seat 3 cuts with the 7 of coeur.
    var played := [c(P, R.AS), c(T, R.ROI), c(T, R.SEPT), c(CO, R.SEPT)]
    var memory := BeloteMemory.from_view(view_after(played, [c(P, R.DIX)]))
    assert_true(memory.is_void(1, P))
    assert_true(memory.is_void(1, CO), "seat 1 had to cut and didn't")
    assert_eq(memory.calls[2], T, "a small card on the partner's trick calls that suit")
    assert_true(memory.is_void(3, P))
    assert_eq(memory.played_by[c(CO, R.SEPT)], 3)
    assert_eq(memory.tricks_won, [0, 1] as Array[int], "seat 3 cut: the trick is theirs")
    assert_false(memory.may_hold(1, c(CO, R.VALET)))


func test_memory_caps_trumps_when_a_seat_cannot_climb() -> void:
    # Seat 0 leads the 9 of coeur (trumps); seat 1 plays the 8: it holds no valet.
    var played := [c(CO, R.NEUF), c(CO, R.HUIT)]
    var memory := BeloteMemory.from_view(view_after(played, [c(P, R.DIX)]))
    assert_false(memory.may_hold(1, c(CO, R.VALET)))
    assert_true(memory.may_hold(2, c(CO, R.VALET)))


func test_every_level_plays_legal_moves_to_the_end() -> void:
    var game := Belote.new()
    var pimc := BeloteBotPimc.new()
    pimc.samples = 3
    var bots := [BeloteBotDifficile.new(), BeloteBotZinzin.load_trained(), pimc, BeloteBot.new()]
    for seed_value in 3:
        var s: BeloteState = game.new_state(seed_value)
        var steps := 0
        while not game.is_over(s) and steps < 3000:
            var view := game.view_for(s, s.to_act)
            var move: Dictionary = bots[s.to_act].choose(view)
            assert_true(view.legal.has(move), "seat %d played %s" % [s.to_act, move])
            game.apply(s, move)
            steps += 1
        assert_true(game.is_over(s))


func test_pimc_samples_fit_the_table() -> void:
    var game := Belote.new()
    var s: BeloteState = game.new_state(8)
    game.apply(s, {"kind": "take", "suit": Cards.suit_of(s.turned)})
    for i in 9:
        game.apply(s, game.legal_moves(s)[0])
    var view := game.view_for(s, s.to_act)
    var memory := BeloteMemory.from_view(view)
    var pimc := BeloteBotPimc.new()
    for i in 10:
        var hands := pimc.sample_hands(memory, view)
        assert_false(hands.is_empty())
        for seat in 4:
            assert_eq(hands[seat].size(), view.hand_sizes[seat])
            for card in hands[seat]:
                if seat != memory.seat:
                    assert_true(memory.may_hold(seat, card))


func test_difficile_beats_facile() -> void:
    var result := BotArena.match_up(BeloteBotDifficile.new(), BeloteBot.new(), 1500, 3000)
    gut.p("difficile vs facile: %+.1f ± %.1f" % [result.mean, 2 * result.stderr])
    assert_gt(result.mean - 2 * result.stderr, 0.0)


func test_memory_reads_turned_card_bids_and_contract() -> void:
    var view := view_after([c(P, R.AS)], [c(P, R.DIX)])
    view.taker = 2
    view.turned = c(CO, R.SEPT)
    view.bids = [{"seat": 1, "kind": "pass", "suit": -1, "round": 1},
            {"seat": 2, "kind": "take", "suit": CO, "round": 1}]
    var memory := BeloteMemory.from_view(view)
    assert_true(memory.may_hold(2, c(CO, R.SEPT)), "the turned card is in the taker's hand")
    assert_false(memory.may_hold(1, c(CO, R.SEPT)))
    memory.bid_trust = 1.0
    var valet := c(CO, R.VALET)
    assert_gt(memory.holds_probability(2, valet), memory.holds_probability(3, valet),
            "the taker more likely holds the valet")
    assert_lt(memory.holds_probability(1, valet), memory.holds_probability(3, valet),
            "who passed on the turned suit less likely holds it")
    var urgency := memory.contract_urgency()
    assert_between(urgency, 0.4, 0.6, "nothing scored yet: about half the points are needed")
