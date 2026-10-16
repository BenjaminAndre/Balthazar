class_name CardGame
extends RefCounted
## Common shape of every game in Balthazar (Belote, later Coinche and Tarot).
##
## A game object holds only the rules; all progress lives in a state object, so
## one game can drive many tables. Moves are small Dictionaries, which keeps them
## easy to log, replay and send over the network.


## A fresh state for a whole game (several hands), fully decided by the seed.
func new_state(_seed_value: int) -> RefCounted:
    return null


## The moves the seat whose turn it is may make. Empty when the game is over.
func legal_moves(_state: RefCounted) -> Array[Dictionary]:
    return []


## Plays one move for the seat whose turn it is. The move must be legal.
func apply(_state: RefCounted, _move: Dictionary) -> void:
    pass


func is_over(_state: RefCounted) -> bool:
    return true


## What one seat may see: its own hand, the table, the scores. Never other hands.
func view_for(_state: RefCounted, _seat: int) -> Dictionary:
    return {}
