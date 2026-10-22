class_name BotArena
## Measures one bot against another with duplicate hands: every deal is played
## twice, the two bots swapping teams, so the luck of the cards cancels out.
## The score is A's average lead in raw points per hand (cards, announces,
## belote; a hand worth 162, or 250 for a capot).
## Each deal starts from a score drawn from its seed (swapped with the teams), so
## bots that bid by the score meet every situation.


## {mean, stderr, deals}: A's average lead per hand over `deals` deals.
static func match_up(bot_a: BeloteBot, bot_b: BeloteBot, deals: int, first_seed := 1000) -> Dictionary:
    var game := Belote.new()
    var sum := 0.0
    var squares := 0.0
    for i in deals:
        var lead := duplicate_lead(game, bot_a, bot_b, first_seed + i)
        sum += lead
        squares += lead * lead
    var mean := sum / deals
    var variance := maxf(squares / deals - mean * mean, 0.0)
    return {"mean": mean, "stderr": sqrt(variance / deals), "deals": deals}


## A's lead on one deal, played twice with the teams (and the score) swapped.
static func duplicate_lead(game: Belote, bot_a: BeloteBot, bot_b: BeloteBot, seed_value: int) -> float:
    var scores := [(seed_value * 37) % 90, (seed_value * 61) % 90]
    var first := play_hand(game, seed_value, [bot_a, bot_b, bot_a, bot_b], scores)
    var second := play_hand(game, seed_value, [bot_b, bot_a, bot_b, bot_a], [scores[1], scores[0]])
    return ((first[0] - first[1]) + (second[1] - second[0])) / 2.0


## Plays the deal `seed_value` with `bots` in seats 0-3 from the score `scores`,
## redealing while everybody passes, and returns each team's raw points for the
## first hand played.
static func play_hand(game: Belote, seed_value: int, bots: Array, scores := [0, 0]) -> Array:
    var state: BeloteState = game.new_state(seed_value)
    state.scores.assign(scores)
    while state.last_hand.is_empty() and state.deal_number < 20:
        var bot: BeloteBot = bots[state.to_act]
        game.apply(state, bot.choose(game.view_for(state, state.to_act)))
    if state.last_hand.is_empty():
        return [0, 0]
    return state.last_hand.raw
