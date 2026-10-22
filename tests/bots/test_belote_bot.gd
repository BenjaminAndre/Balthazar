extends GutTest
## Bots only make legal moves, finish games, and beat random play.

const GAMES := 100


func test_bots_finish_games_and_beat_random_play() -> void:
    var game := Belote.new()
    var bot := BeloteBot.new()
    var bot_wins := 0
    for seed_value in GAMES:
        var s: BeloteState = game.new_state(seed_value)
        var rng := RandomNumberGenerator.new()
        rng.seed = seed_value
        var steps := 0
        while not game.is_over(s) and steps < 5000:
            var view := game.view_for(s, s.to_act)
            var move: Dictionary
            if s.to_act % 2 == 0:
                move = bot.choose(view)
                assert_true(view.legal.has(move), "seed %d: bot played %s" % [seed_value, move])
            else:
                move = view.legal[rng.randi_range(0, view.legal.size() - 1)]
            game.apply(s, move)
            steps += 1
        assert_true(game.is_over(s))
        if s.winner == 0:
            bot_wins += 1
    gut.p("bots won %d of %d against random play" % [bot_wins, GAMES])
    assert_gt(bot_wins, GAMES * 7 / 10)


func test_bot_takes_a_strong_hand() -> void:
    var hand: Array[int] = [Cards.make(Cards.Suit.COEUR, Cards.Rank.VALET),
            Cards.make(Cards.Suit.COEUR, Cards.Rank.NEUF), Cards.make(Cards.Suit.PIQUE, Cards.Rank.AS),
            Cards.make(Cards.Suit.TREFLE, Cards.Rank.SEPT), Cards.make(Cards.Suit.CARREAU, Cards.Rank.HUIT)]
    var view := {"phase": BeloteState.Phase.BID_ROUND_1, "hand": hand,
            "turned": Cards.make(Cards.Suit.COEUR, Cards.Rank.SEPT),
            "legal": [{"kind": "pass"}, {"kind": "take", "suit": Cards.Suit.COEUR}]}
    assert_eq(BeloteBot.new().choose(view), {"kind": "take", "suit": Cards.Suit.COEUR})
