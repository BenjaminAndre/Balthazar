class_name BeloteState
extends RefCounted
## Everything about one Belote game in progress. Only `Belote` changes it.
##
## Seats 0-3 go clockwise: the next seat is (seat + 1) % 4, on the left.
## Teams are seat % 2, so partners sit face to face.

enum Phase { BID_ROUND_1, BID_ROUND_2, PLAYING, GAME_OVER }

const SEATS := 4

var seed_value := 0
## Counts deals, including redeals after four passes twice; it seeds each shuffle.
var deal_number := 0
var dealer := 0
var phase := Phase.BID_ROUND_1
var to_act := 1

## One Array[int] per seat.
var hands: Array = []
## Cards still to deal once someone takes.
var stock: Array[int] = []
## The card turned up for the bidding.
var turned := -1
var passes := 0
var taker := -1
var trump := -1
## Seat holding the King and Queen of trumps, or -1 (GDD §3.5).
var belote_seat := -1

var trick: Array[int] = []
var trick_leader := 0
## {cards, leader, winner} of the last finished trick, for the UI.
var last_trick: Dictionary = {}
var tricks_won: Array[int] = [0, 0]
## Card points per team this hand, dix de der included.
var card_points: Array[int] = [0, 0]
## Announce points per team this hand (GDD §3.6, filled in slice 3).
var announce_points: Array[int] = [0, 0]

var scores: Array[int] = [0, 0]
## Raw points held back by a litige, won by the winner of the next hand.
var reserve := 0
## The result of the last finished hand (see BeloteScoring.score_hand).
var last_hand: Dictionary = {}
## Winning team once the game is over.
var winner := -1

## Every move played, in order: with `seed_value`, it replays the whole game.
var moves: Array[Dictionary] = []


static func next_seat(seat: int) -> int:
    return (seat + 1) % SEATS


static func team_of(seat: int) -> int:
    return seat % 2
