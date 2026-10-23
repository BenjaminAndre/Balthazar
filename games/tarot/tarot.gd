class_name Tarot
extends CardGame
## French Tarot for 3, 4 or 5 players (GDD §4.2) as a CardGame. Moves:
## {"kind": "bid", "contract": TarotState.Contract (NONE = pass)},
## {"kind": "call", "card": c} (five players), {"kind": "discard", "card": c}
## (the écart), {"kind": "play", "card": c}.

var players := 4
var scoring := TarotScoring.new()


func _init(player_count := 4) -> void:
    players = player_count


func new_state(seed_value: int) -> RefCounted:
    var state := TarotState.new()
    state.players = players
    state.seed_value = seed_value
    state.deals_per_game = 2 * players
    state.dealer = 0
    for seat in players:
        state.scores.append(0)
    _deal(state)
    return state


func replay(seed_value: int, moves: Array[Dictionary]) -> TarotState:
    var state: TarotState = new_state(seed_value)
    for move in moves:
        apply(state, move)
    return state


func is_over(state: RefCounted) -> bool:
    return (state as TarotState).phase == TarotState.Phase.GAME_OVER


func legal_moves(state: RefCounted) -> Array[Dictionary]:
    var s := state as TarotState
    var moves: Array[Dictionary] = []
    match s.phase:
        TarotState.Phase.BIDDING:
            moves.append({"kind": "bid", "contract": TarotState.Contract.NONE})
            var best := _best_bid(s)
            for contract in range(best + 1, TarotState.Contract.GARDE_CONTRE + 1):
                moves.append({"kind": "bid", "contract": contract})
        TarotState.Phase.CALLING:
            for card in callable_cards(s):
                moves.append({"kind": "call", "card": card})
        TarotState.Phase.ECART:
            for card in discardable_cards(s):
                moves.append({"kind": "discard", "card": card})
        TarotState.Phase.PLAYING:
            for card in legal_cards(s):
                moves.append({"kind": "play", "card": card})
    return moves


## Five players: the kings, or the queens when the taker holds every king.
func callable_cards(s: TarotState) -> Array[int]:
    var hand: Array[int] = s.hands[s.taker]
    var rank := TarotCards.Rank.ROI
    var kings := 0
    for suit in 4:
        if hand.has(TarotCards.make(suit, TarotCards.Rank.ROI)):
            kings += 1
    if kings == 4:
        rank = TarotCards.Rank.DAME
    var out: Array[int] = []
    for suit in 4:
        out.append(TarotCards.make(suit, rank))
    return out


## The écart may not hold kings or oudlers; trumps only when nothing else is left.
func discardable_cards(s: TarotState) -> Array[int]:
    var hand: Array[int] = s.hands[s.taker]
    var plain: Array[int] = []
    var trumps: Array[int] = []
    for card in hand:
        if TarotCards.is_oudler(card):
            continue
        if TarotCards.is_trump(card):
            trumps.append(card)
        elif TarotCards.rank_of(card) != TarotCards.Rank.ROI:
            plain.append(card)
    return plain if not plain.is_empty() else trumps


## Following (GDD §4.2): the suit led, else a trump (higher than the trick's
## best if possible), else anything. The Excuse may always be played. At five,
## the called suit may not be led at the first trick, except with the called card.
func legal_cards(s: TarotState) -> Array[int]:
    var hand: Array[int] = s.hands[s.to_act]
    if s.trick.is_empty():
        if players == 5 and s.played.is_empty() and s.called_card >= 0:
            var called_suit := TarotCards.suit_of(s.called_card)
            var allowed: Array[int] = []
            for card in hand:
                if TarotCards.suit_of(card) != called_suit or card == s.called_card:
                    allowed.append(card)
            if not allowed.is_empty():
                return allowed
        return hand.duplicate()
    var led := TarotCards.led_suit(s.trick)
    if led < 0:
        return hand.duplicate()  # only the Excuse so far: free
    var out: Array[int] = []
    if hand.has(TarotCards.EXCUSE):
        out.append(TarotCards.EXCUSE)
    var following := _of_suit(hand, led)
    if led != TarotCards.TRUMP_SUIT and not following.is_empty():
        out.append_array(following)
        return out
    var trumps := _of_suit(hand, TarotCards.TRUMP_SUIT)
    if trumps.is_empty():
        return hand.duplicate()
    var best := 0
    for card in s.trick:
        if TarotCards.is_trump(card):
            best = maxi(best, TarotCards.trump_value(card))
    var higher: Array[int] = []
    for card in trumps:
        if TarotCards.trump_value(card) > best:
            higher.append(card)
    out.append_array(higher if not higher.is_empty() else trumps)
    return out


func apply(state: RefCounted, move: Dictionary) -> void:
    var s := state as TarotState
    assert(legal_moves(s).has(move), "illegal move %s" % move)
    s.moves.append(move)
    match move.kind:
        "bid":
            _bid(s, move.contract)
        "call":
            s.called_card = move.card
            s.partner = s.taker
            for seat in players:
                if s.hands[seat].has(move.card):
                    s.partner = seat
            # Calling one's own card: the taker plays alone.
            if s.partner == s.taker:
                s.partner = -1
            _after_contract(s)
        "discard":
            s.hands[s.taker].erase(move.card)
            s.ecart.append(move.card)
            if s.ecart.size() == s.chien_size():
                _start_play(s)
        "play":
            _play(s, move.card)


func view_for(state: RefCounted, seat: int) -> Dictionary:
    var s := state as TarotState
    var sizes: Array[int] = []
    for hand in s.hands:
        sizes.append(hand.size())
    # The partner is public once the called card has been played.
    var partner_known: bool = s.called_card >= 0 and s.played.has(s.called_card)
    # After a petite or a garde, the chien is shown to everyone while the taker discards.
    var chien_shown: bool = s.phase == TarotState.Phase.ECART
    return {
        "game": "tarot",
        "players": players,
        "seat": seat,
        "phase": s.phase,
        "dealer": s.dealer,
        "to_act": s.to_act,
        "hand": (s.hands[seat] as Array[int]).duplicate(),
        "hand_sizes": sizes,
        "bids": s.bids.duplicate(),
        "contract": s.contract,
        "taker": s.taker,
        "called_card": s.called_card,
        "partner": s.partner if partner_known or seat == s.partner else -1,
        "chien": s.chien.duplicate() if chien_shown else [],
        "ecart": s.ecart.duplicate() if seat == s.taker else [],
        "trick": s.trick.duplicate(),
        "trick_leader": s.trick_leader,
        "last_trick": s.last_trick.duplicate(true),
        "played": s.played.duplicate(),
        "scores": s.scores.duplicate(),
        "deals_played": s.deals_played,
        "deals_per_game": s.deals_per_game,
        "last_hand": s.last_hand.duplicate(true),
        "winner": s.winner,
        "legal": legal_moves(s) if s.to_act == seat else [],
    }


# --- Dealing and bidding ------------------------------------------------------------

func _deal(s: TarotState) -> void:
    for attempt in 50:
        var deck := TarotCards.shuffled(s.seed_value * 1000003 + s.deal_number)
        var per := (TarotCards.COUNT - s.chien_size()) / players
        s.hands = []
        for seat in players:
            var hand: Array[int] = []
            hand.assign(deck.slice(seat * per, (seat + 1) * per))
            s.hands.append(hand)
        s.chien.assign(deck.slice(players * per))
        if not _petit_sec(s):
            break
        # « Petit sec »: someone holds the Petit as their only trump, without the Excuse: redeal.
        s.deal_number += 1
    s.phase = TarotState.Phase.BIDDING
    s.bids = []
    for seat in players:
        s.bids.append(-1)
    s.contract = TarotState.Contract.NONE
    s.taker = -1
    s.called_card = -1
    s.partner = -1
    s.ecart.clear()
    s.trick.clear()
    s.last_trick = {}
    s.won = []
    for seat in players:
        var pile: Array[int] = []
        s.won.append(pile)
    s.excuse_owner = -1
    s.excuse_winner = -1
    s.petit_au_bout = -1
    s.played.clear()
    s.played_by.clear()
    s.to_act = s.next_seat(s.dealer)


func _petit_sec(s: TarotState) -> bool:
    for hand in s.hands:
        if hand.has(TarotCards.PETIT) and not hand.has(TarotCards.EXCUSE):
            var trumps := 0
            for card in hand:
                if TarotCards.is_trump(card):
                    trumps += 1
            if trumps == 1:
                return true
    return false


func _best_bid(s: TarotState) -> int:
    var best := TarotState.Contract.NONE
    for bid in s.bids:
        best = maxi(best, bid)
    return best


## Each player speaks once, from the dealer's left, and must bid higher than before.
func _bid(s: TarotState, contract: int) -> void:
    s.bids[s.to_act] = contract
    if contract > TarotState.Contract.NONE:
        s.contract = contract
        s.taker = s.to_act
    var spoken := 0
    for bid in s.bids:
        if bid >= 0:
            spoken += 1
    if spoken < players:
        s.to_act = s.next_seat(s.to_act)
        return
    if s.taker < 0:
        # Nobody took: the next dealer deals again.
        s.dealer = s.next_seat(s.dealer)
        s.deal_number += 1
        _deal(s)
        return
    if players == 5:
        s.phase = TarotState.Phase.CALLING
        s.to_act = s.taker
    else:
        _after_contract(s)


## The chien: taken into the hand (petite, garde), kept unseen for the taker
## (garde sans) or given to the defence (garde contre).
func _after_contract(s: TarotState) -> void:
    if s.contract <= TarotState.Contract.GARDE:
        s.hands[s.taker].append_array(s.chien)
        s.phase = TarotState.Phase.ECART
        s.to_act = s.taker
        return
    _start_play(s)


func _start_play(s: TarotState) -> void:
    s.phase = TarotState.Phase.PLAYING
    s.trick_leader = s.next_seat(s.dealer)
    s.to_act = s.trick_leader


# --- Play ----------------------------------------------------------------------------

func _play(s: TarotState, card: int) -> void:
    s.hands[s.to_act].erase(card)
    s.trick.append(card)
    s.played.append(card)
    s.played_by[card] = s.to_act
    if s.trick.size() < players:
        s.to_act = s.next_seat(s.to_act)
        return
    var winner := (s.trick_leader + TarotCards.winning_index(s.trick)) % players
    var last: bool = s.hands[winner].is_empty()
    for i in s.trick.size():
        var c: int = s.trick[i]
        var by := (s.trick_leader + i) % players
        if c == TarotCards.EXCUSE and not last:
            # The Excuse stays with its owner, who gives the winner a half point back.
            s.won[by].append(c)
            s.excuse_owner = by
            s.excuse_winner = winner
        else:
            s.won[winner].append(c)
    if last and s.trick.has(TarotCards.PETIT):
        s.petit_au_bout = winner
    s.last_trick = {"cards": s.trick.duplicate(), "leader": s.trick_leader, "winner": winner}
    s.trick.clear()
    s.trick_leader = winner
    s.to_act = winner
    if last:
        _end_deal(s)


func _end_deal(s: TarotState) -> void:
    s.last_hand = scoring.score_deal(s)
    for seat in players:
        s.scores[seat] += s.last_hand.changes[seat]
    s.deals_played += 1
    if s.deals_played >= s.deals_per_game:
        var best := 0
        for seat in players:
            if s.scores[seat] > s.scores[best]:
                best = seat
        s.winner = best
        s.phase = TarotState.Phase.GAME_OVER
        return
    s.dealer = s.next_seat(s.dealer)
    s.deal_number += 1
    _deal(s)


func _of_suit(cards: Array[int], suit: int) -> Array[int]:
    var out: Array[int] = []
    for card in cards:
        if TarotCards.suit_of(card) == suit:
            out.append(card)
    return out
