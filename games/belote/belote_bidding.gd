class_name BeloteBidding
extends RefCounted
## Belote classique bidding (GDD §3.2): take the turned suit on the first round,
## or name another suit on the second; four passes twice means a redeal.


func legal_bids(state: BeloteState) -> Array[Dictionary]:
    var bids: Array[Dictionary] = [{"kind": "pass"}]
    var turned_suit := Cards.suit_of(state.turned)
    if state.phase == BeloteState.Phase.BID_ROUND_1:
        bids.append({"kind": "take", "suit": turned_suit})
    else:
        for suit in 4:
            if suit != turned_suit:
                bids.append({"kind": "take", "suit": suit})
    return bids


enum Outcome { NEXT, SECOND_ROUND, REDEAL, TAKEN }


## Records a bid and says what happens next. `Belote` does the dealing.
func apply_bid(state: BeloteState, bid: Dictionary) -> Outcome:
    if bid.kind == "take":
        state.taker = state.to_act
        state.trump = bid.suit
        return Outcome.TAKEN
    state.passes += 1
    state.to_act = BeloteState.next_seat(state.to_act)
    if state.passes < BeloteState.SEATS:
        return Outcome.NEXT
    return Outcome.SECOND_ROUND if state.phase == BeloteState.Phase.BID_ROUND_1 else Outcome.REDEAL
