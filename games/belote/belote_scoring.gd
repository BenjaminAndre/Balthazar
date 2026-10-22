class_name BeloteScoring
extends RefCounted
## Scores one Belote hand (GDD §3.7): fait, dedans, capot, litige, belote and
## the rounding to tens.

const CAPOT := 250
const HAND_TOTAL := 162
const BELOTE := 20


## Returns {outcome, raw: [a, b], points: [a, b], reserve}:
## - outcome is "fait", "dedans" or "litige";
## - raw holds each team's points before rounding, and decides the contract;
## - points is what goes on the score sheet, after rounding and any litige reserve won;
## - reserve is the raw litige reserve carried into the next hand;
## - announces and belote are each team's raw announce and belote points.
func score_hand(s: BeloteState, rules: BeloteRules) -> Dictionary:
    var taker_team := BeloteState.team_of(s.taker)
    var defence := 1 - taker_team
    var cards := s.card_points.duplicate()
    for team in 2:
        if s.tricks_won[team] == 8:
            cards[team] = CAPOT
            cards[1 - team] = 0
    var belote: Array[int] = [0, 0]
    if s.belote_seat >= 0:
        belote[BeloteState.team_of(s.belote_seat)] = BELOTE
    var totals: Array[int] = [0, 0]
    for team in 2:
        totals[team] = cards[team] + s.announce_points[team] + belote[team]

    var raw: Array[int] = totals.duplicate()
    var outcome := "fait"
    var reserve := s.reserve
    var reserve_winner := taker_team
    if totals[taker_team] < totals[defence]:
        outcome = "dedans"
        var won := CAPOT if s.tricks_won[defence] == 8 else HAND_TOTAL
        raw[defence] = won + s.announce_points[0] + s.announce_points[1] + belote[defence]
        raw[taker_team] = belote[taker_team]
        reserve_winner = defence
    elif totals[taker_team] == totals[defence]:
        outcome = "litige"
        raw[taker_team] = 0
        reserve += totals[taker_team]
        reserve_winner = -1

    var points: Array[int] = [round_points(raw[0], rules), round_points(raw[1], rules)]
    if reserve_winner >= 0 and reserve > 0:
        points[reserve_winner] += round_points(reserve, rules)
        reserve = 0
    return {"outcome": outcome, "raw": raw, "points": points, "reserve": reserve,
            "announces": s.announce_points.duplicate(), "belote": belote}


## To the nearest ten, a 5 rounding down, then divided by 10: 15 -> 1, 16 -> 2.
static func round_points(raw: int, rules: BeloteRules) -> int:
    return (raw + 4) / 10 if rules.rounded_scores else raw
