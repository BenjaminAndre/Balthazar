class_name TarotScoring
extends RefCounted
## Scores one Tarot deal (GDD §4.2): the points the taker's side needs depend on
## its oudlers (56, 51, 41 or 36). The deal is worth (25 + the gap) times the
## contract's multiplier, plus the petit au bout, and is paid by each defender to
## the taker's side.

## Points needed by number of oudlers, in half points.
const NEEDED := [112, 102, 82, 72]
const BASE := 25
const PETIT_AU_BOUT := 10


## Returns {made, points (half points of the taker's side), needed, oudlers,
## contract, taker, partner, value (signed, per defender), petit_au_bout, changes: [per seat]}.
func score_deal(s: TarotState) -> Dictionary:
    var side_cards: Array[int] = []
    for seat in s.players:
        if s.taker_side(seat):
            side_cards.append_array(s.won[seat])
    side_cards.append_array(s.ecart)
    if s.contract == TarotState.Contract.GARDE_SANS:
        side_cards.append_array(s.chien)
    var points := 0
    var oudlers := 0
    for card in side_cards:
        points += TarotCards.half_points(card)
        if TarotCards.is_oudler(card):
            oudlers += 1
    # The Excuse's owner gave the trick's winner a half point in exchange.
    if s.excuse_owner >= 0 and s.taker_side(s.excuse_owner) != s.taker_side(s.excuse_winner):
        points += -1 if s.taker_side(s.excuse_owner) else 1
    var needed: int = NEEDED[oudlers]
    var made := points >= needed
    # The gap in whole points, a half point rounded up.
    var gap := (absi(points - needed) + 1) / 2
    var multiplier: int = TarotState.MULTIPLIERS[s.contract]
    var value := (BASE + gap) * multiplier * (1 if made else -1)
    if s.petit_au_bout >= 0:
        value += PETIT_AU_BOUT * multiplier * (1 if s.taker_side(s.petit_au_bout) else -1)
    var changes: Array[int] = []
    var defenders := 0
    for seat in s.players:
        changes.append(0)
        if not s.taker_side(seat):
            defenders += 1
    for seat in s.players:
        if not s.taker_side(seat):
            changes[seat] = -value
    if s.partner >= 0:
        # Five players with a partner: the taker gets two shares, the partner one.
        changes[s.taker] = 2 * value
        changes[s.partner] = value
    else:
        changes[s.taker] = defenders * value
    return {"made": made, "points": points, "needed": needed, "oudlers": oudlers,
            "contract": s.contract, "taker": s.taker, "partner": s.partner, "value": value,
            "petit_au_bout": s.petit_au_bout, "changes": changes}
