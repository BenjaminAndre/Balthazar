extends GutTest
## GDD §3.4: when the partner holds the trick, a player without the suit led may
## play anything. Checked on every such position of many random games.


func test_free_discard_whenever_partner_is_master() -> void:
    var game := Belote.new()
    var checked := 0
    for seed_value in 60:
        var s: BeloteState = game.new_state(seed_value)
        var rng := RandomNumberGenerator.new()
        rng.seed = seed_value
        while not game.is_over(s):
            if s.phase == BeloteState.Phase.PLAYING and not s.trick.is_empty():
                var led := Cards.suit_of(s.trick[0])
                var hand: Array[int] = s.hands[s.to_act]
                var has_led := hand.any(func(c: int) -> bool: return Cards.suit_of(c) == led)
                var master := (s.trick_leader + BeloteCards.winning_index(s.trick, s.trump)) % 4
                if not has_led and master % 2 == s.to_act % 2:
                    var legal := game.legal_cards(s)
                    legal.sort()
                    var all := hand.duplicate()
                    all.sort()
                    assert_eq(legal, all, "seed %d: partner master, trick %s" % [seed_value, s.trick])
                    checked += 1
            var moves := game.legal_moves(s)
            game.apply(s, moves[rng.randi_range(0, moves.size() - 1)])
    gut.p("checked %d positions" % checked)
    assert_gt(checked, 100)
