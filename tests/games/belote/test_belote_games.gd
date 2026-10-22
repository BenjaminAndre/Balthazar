extends GutTest
## Whole games with random legal moves: no dead end, the points always add up,
## and the move log replays the same game.

const GAMES := 100


func test_random_games() -> void:
    var game := Belote.new()
    for seed_value in GAMES:
        var s: BeloteState = game.new_state(seed_value)
        var rng := RandomNumberGenerator.new()
        rng.seed = seed_value
        var steps := 0
        while not game.is_over(s) and steps < 5000:
            var moves := game.legal_moves(s)
            assert_false(moves.is_empty(), "seed %d: no legal move" % seed_value)
            var was_playing := s.phase == BeloteState.Phase.PLAYING
            var deal := s.deal_number
            game.apply(s, moves[rng.randi_range(0, moves.size() - 1)])
            if was_playing and (s.deal_number != deal or game.is_over(s)):
                _check_hand(s.last_hand, seed_value)
            steps += 1
        assert_true(game.is_over(s), "seed %d didn't finish" % seed_value)
        assert_gte(s.scores[s.winner], 101)
        var again := game.replay(seed_value, s.moves)
        assert_eq(again.scores, s.scores, "seed %d replays" % seed_value)


func _check_hand(result: Dictionary, seed_value: int) -> void:
    if result.outcome == "litige":
        return
    var extras: int = result.belote[0] + result.belote[1] + result.announces[0] + result.announces[1]
    var total: int = result.raw[0] + result.raw[1] - extras
    assert_true(total == 162 or total == 250, "seed %d: hand worth %d" % [seed_value, total])
