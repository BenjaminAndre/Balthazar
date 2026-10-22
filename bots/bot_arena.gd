class_name BotArena
## Measures one bot against another with duplicate hands: every deal is played
## twice, the two bots swapping teams, so the luck of the cards cancels out.
## The score is A's average lead in raw points per hand (cards, announces,
## belote; a hand worth 162, or 250 for a capot).


## {mean, stderr, deals}: A's average lead per hand over `deals` deals.
static func match_up(bot_a: BeloteBot, bot_b: BeloteBot, deals: int, first_seed := 1000) -> Dictionary:
    var game := Belote.new()
    var sum := 0.0
    var squares := 0.0
    for i in deals:
        var seed_value := first_seed + i
        var first := play_hand(game, seed_value, [bot_a, bot_b, bot_a, bot_b])
        var second := play_hand(game, seed_value, [bot_b, bot_a, bot_b, bot_a])
        var lead: float = ((first[0] - first[1]) + (second[1] - second[0])) / 2.0
        sum += lead
        squares += lead * lead
    var mean := sum / deals
    var variance := maxf(squares / deals - mean * mean, 0.0)
    return {"mean": mean, "stderr": sqrt(variance / deals), "deals": deals}


## Plays the deal `seed_value` with `bots` in seats 0-3, redealing while everybody
## passes, and returns each team's raw points for the first hand played.
static func play_hand(game: Belote, seed_value: int, bots: Array) -> Array:
    var state: BeloteState = game.new_state(seed_value)
    while state.last_hand.is_empty() and state.deal_number < 20:
        var bot: BeloteBot = bots[state.to_act]
        game.apply(state, bot.choose(game.view_for(state, state.to_act)))
    if state.last_hand.is_empty():
        return [0, 0]
    return state.last_hand.raw
