extends GutTest
## The Tarot engine (GDD §4.2) at 3, 4 and 5 players.

const P := Cards.Suit.PIQUE
const CO := Cards.Suit.COEUR
const R := TarotCards.Rank


func t(value: int) -> int:
    return TarotCards.trump(value)


func test_deck_is_worth_91_points_with_3_oudlers() -> void:
    var total := 0
    var oudlers := 0
    for card in TarotCards.COUNT:
        total += TarotCards.half_points(card)
        if TarotCards.is_oudler(card):
            oudlers += 1
    assert_eq(total, 182)
    assert_eq(oudlers, 3)


func test_deal_sizes() -> void:
    for players in [3, 4, 5]:
        var game := Tarot.new(players)
        var s: TarotState = game.new_state(1)
        for hand in s.hands:
            assert_eq(hand.size(), {3: 24, 4: 18, 5: 15}[players])
        assert_eq(s.chien.size(), 3 if players == 5 else 6)


func test_trick_winner() -> void:
    var led_coeur := [TarotCards.make(CO, R.R5), TarotCards.make(CO, R.ROI), TarotCards.make(P, R.ROI)]
    assert_eq(TarotCards.winning_index(led_coeur), 1)
    assert_eq(TarotCards.winning_index([TarotCards.make(CO, R.R5), t(2), t(1)]), 1)
    assert_eq(TarotCards.winning_index([TarotCards.EXCUSE, TarotCards.make(CO, R.R5), TarotCards.make(CO, R.R9)]), 2,
            "after the Excuse, the next card sets the suit")


func _state_with(hands: Array, trick: Array) -> TarotState:
    var s := TarotState.new()
    s.players = 4
    s.phase = TarotState.Phase.PLAYING
    s.hands = []
    for h in hands:
        var typed: Array[int] = []
        typed.assign(h)
        s.hands.append(typed)
    s.trick.assign(trick)
    s.trick_leader = 0
    s.to_act = trick.size()
    return s


func sorted(list: Array) -> Array[int]:
    var out: Array[int] = []
    out.assign(list)
    out.sort()
    return out


func test_must_follow_then_trump_then_overtrump() -> void:
    var game := Tarot.new(4)
    var hand := [TarotCards.make(CO, R.R2), t(3), t(10), TarotCards.EXCUSE]
    var s := _state_with([[], hand, [], []], [TarotCards.make(CO, R.ROI)])
    assert_eq(sorted(game.legal_cards(s)), sorted([TarotCards.make(CO, R.R2), TarotCards.EXCUSE]))
    var no_coeur := [TarotCards.make(P, R.R2), t(3), t(10), TarotCards.EXCUSE]
    s = _state_with([[], [], no_coeur, []], [TarotCards.make(CO, R.ROI), t(5)])
    assert_eq(sorted(game.legal_cards(s)), sorted([t(10), TarotCards.EXCUSE]), "must overtrump the 5")
    s = _state_with([[], [], [TarotCards.make(P, R.R2), t(3), TarotCards.EXCUSE], []], [TarotCards.make(CO, R.ROI), t(5)])
    assert_eq(sorted(game.legal_cards(s)), sorted([t(3), TarotCards.EXCUSE]), "can't overtrump: still a trump")


func test_ecart_excludes_kings_and_oudlers() -> void:
    var game := Tarot.new(4)
    for seed_value in 40:
        var s: TarotState = game.new_state(seed_value)
        game.apply(s, {"kind": "bid", "contract": TarotState.Contract.PETITE})
        for i in 3:
            game.apply(s, {"kind": "bid", "contract": TarotState.Contract.NONE})
        assert_eq(s.phase, TarotState.Phase.ECART)
        assert_eq(s.hands[s.taker].size(), 24)
        for card in game.discardable_cards(s):
            assert_false(TarotCards.is_oudler(card))
            assert_false(not TarotCards.is_trump(card) and TarotCards.rank_of(card) == R.ROI)


func test_score_example() -> void:
    # A garde made by 6 points with 2 oudlers, at four: (25 + 6) x 2 = 62 per defender.
    var s := TarotState.new()
    s.players = 4
    s.contract = TarotState.Contract.GARDE
    s.taker = 0
    s.won = [[], [], [], []]
    s.scores.assign([0, 0, 0, 0])
    # 41 + 6 = 47 points = 94 half points: 2 oudlers (18), 4 kings (36), 4 queens (28), 12 small cards.
    var cards: Array[int] = [TarotCards.PETIT, TarotCards.VINGT_ET_UN]
    for suit in 4:
        cards.append(TarotCards.make(suit, R.ROI))
        cards.append(TarotCards.make(suit, R.DAME))
        for rank in 3:
            cards.append(TarotCards.make(suit, rank))
    s.won[0].assign(cards)
    var result := TarotScoring.new().score_deal(s)
    assert_true(result.made)
    assert_eq(result.oudlers, 2)
    assert_eq(result.value, 62)
    assert_eq(result.changes, [186, -62, -62, -62] as Array[int])


func test_random_games_finish_and_scores_sum_to_zero() -> void:
    var bot := TarotBot.new()
    for players in [3, 4, 5]:
        var game := Tarot.new(players)
        for seed_value in 15:
            var s: TarotState = game.new_state(seed_value)
            var rng := RandomNumberGenerator.new()
            rng.seed = seed_value
            var steps := 0
            while not game.is_over(s) and steps < 20000:
                var view := game.view_for(s, s.to_act)
                var move: Dictionary
                if s.to_act == 0:
                    move = bot.choose(view)
                    assert_true(view.legal.has(move), "%d players, seed %d: bot played %s" % [players, seed_value, move])
                else:
                    move = view.legal[rng.randi_range(0, view.legal.size() - 1)]
                game.apply(s, move)
                steps += 1
            assert_true(game.is_over(s), "%d players, seed %d didn't finish" % [players, seed_value])
            var total := 0
            for score in s.scores:
                total += score
            assert_eq(total, 0, "scores always sum to zero")
            assert_eq(game.replay(seed_value, s.moves).scores, s.scores, "replays")


func test_view_hides_other_hands_and_the_partner() -> void:
    var game := Tarot.new(5)
    var s: TarotState = game.new_state(3)
    var view := game.view_for(s, 1)
    assert_eq(view.hand, s.hands[1])
    assert_false(view.has("hands"))
    assert_eq(view.chien, [])
