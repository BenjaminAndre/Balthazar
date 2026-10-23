class_name TarotState
extends RefCounted
## Everything about one Tarot game in progress (GDD §4.2). Only `Tarot` changes it.
## Seats 0..players-1 go clockwise, like the Belote: the next seat is (seat + 1) % players.

enum Phase { BIDDING, CALLING, ECART, PLAYING, GAME_OVER }
## Contracts, from the weakest. NONE = nobody took yet.
enum Contract { NONE, PETITE, GARDE, GARDE_SANS, GARDE_CONTRE }

const CONTRACT_NAMES := ["", "Petite", "Garde", "Garde sans", "Garde contre"]
const MULTIPLIERS := [0, 1, 2, 4, 6]

var players := 4
var seed_value := 0
## Counts deals, redeals included; it seeds each shuffle.
var deal_number := 0
## Deals played to the end (redeals not counted); the game lasts `deals_per_game`.
var deals_played := 0
var deals_per_game := 8
var dealer := 0
var phase := Phase.BIDDING
var to_act := 1

## One Array[int] per seat.
var hands: Array = []
var chien: Array[int] = []
## Per seat: its bid (Contract), or -1 while it hasn't spoken. PASS is NONE.
var bids: Array[int] = []
var contract := Contract.NONE
var taker := -1
## Five players: the card the taker called (a king, or a queen when it holds all
## the kings) and its holder, the partner. Unknown to the others until it is played.
var called_card := -1
var partner := -1
## The taker's discards (the écart), which count for the taker's side.
var ecart: Array[int] = []

var trick: Array[int] = []
var trick_leader := 0
var last_trick: Dictionary = {}
## Per seat: the cards it won (the Excuse stays with whoever played it).
var won: Array = []
## Who played the Excuse, and who won that trick (for the half point given back).
var excuse_owner := -1
var excuse_winner := -1
## Who won the last trick, when it held the Petit (« petit au bout »), or -1.
var petit_au_bout := -1
## Cards played this deal, in order: public.
var played: Array[int] = []
## Who played each card this deal (public): {card: seat}.
var played_by: Dictionary = {}

## Cumulative score per seat.
var scores: Array[int] = []
## The result of the last finished deal (see TarotScoring.score_deal).
var last_hand: Dictionary = {}
var winner := -1

## Every move played, in order: with `seed_value`, it replays the whole game.
var moves: Array[Dictionary] = []


func next_seat(seat: int) -> int:
    return (seat + 1) % players


## Seats on the taker's side: the taker and, at five, its partner.
func taker_side(seat: int) -> bool:
    return seat == taker or (seat == partner and partner >= 0)


func chien_size() -> int:
    return 3 if players == 5 else 6
