class_name BeloteRules
extends RefCounted
## One table's Belote variant (GDD §3): flags for small tweaks, and one strategy
## object per concern for deeper ones (Coinche will swap bidding and scoring).

## Cut (or overtrump) even when the partner is master of the trick.
var must_trump_over_partner := false
## When you can't overtrump, you may discard instead of undertrumping ("pisser").
var free_undertrump := false
## Hand scores rounded to the ten then divided by 10 (15 -> 1, 16 -> 2).
var rounded_scores := true
## A team reaching this score at the end of a hand wins the game.
var target := 101
## Tierces, cinquantes, cents and carrés (GDD §3.6).
var announces_enabled := true
## « Relance à 12 »: a player whose hand is worth this many points or fewer (at
## the bidding, before any trump) may ask for a redeal. -1 turns it off.
var redeal_max_points := -1

var trick_rule := BeloteTrickRule.new()
var announces := BeloteAnnounces.new()
var bidding := BeloteBidding.new()
var scoring := BeloteScoring.new()
