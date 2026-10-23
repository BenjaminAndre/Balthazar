class_name BeloteMemory
extends RefCounted
## What a careful player knows from the table alone (one seat's view): who played
## each card, which suits each seat is out of, the strongest trump a seat may
## still hold, and the suit each seat called for (appel direct: a small card
## discarded on the partner's trick asks for that suit).

const NO_CAP := 99

var seat := 0
var trump := -1
var hand: Array[int] = []
## Cards neither in our hand nor played.
var unseen: Array[int] = []
## Per seat: {suit: true} for suits it has shown it is out of.
var voids: Array = [{}, {}, {}, {}]
## Per seat: it holds no trump at least as strong as this (BeloteCards.strength).
var trump_cap: Array[int] = [NO_CAP, NO_CAP, NO_CAP, NO_CAP]
## Per seat: the suit it called for, or -1.
var calls: Array[int] = [-1, -1, -1, -1]
## The trick on the table and who led it.
var trick: Array[int] = []
var leader := 0
## Who played each card so far: {card: seat}.
var played_by: Dictionary = {}
## Per team, this hand: tricks won and card points (dix de der comes at the end).
var tricks_won: Array[int] = [0, 0]
var card_points: Array[int] = [0, 0]
## Cards left in each seat's hand.
var hand_sizes: Array[int] = [8, 8, 8, 8]
## The seat that said « belote » (it holds the other honour), or -1.
var belote_seat := -1
## The taker, the turned card (in the taker's hand), and who passed at the first round.
var taker := -1
var turned := -1
var passed_first: Array[int] = []
## Public announce points per team, once the first trick has settled them.
var announce_points: Array[int] = [0, 0]
## How much the bids are believed (see bid_weight); set by the bot.
var bid_trust := 0.0


static func from_view(view: Dictionary) -> BeloteMemory:
    var memory := BeloteMemory.new()
    memory.seat = view.seat
    memory.trump = view.trump
    memory.hand.assign(view.hand)
    memory.trick.assign(view.trick)
    memory.leader = view.trick_leader
    memory.belote_seat = view.get("belote_seat", -1)
    memory.taker = view.get("taker", -1)
    memory.turned = view.get("turned", -1)
    for bid in view.get("bids", []):
        if bid.kind == "pass" and int(bid.round) == 1:
            memory.passed_first.append(int(bid.seat))
    if view.has("announce_points"):
        memory.announce_points.assign(view.announce_points)
    if view.has("hand_sizes"):
        memory.hand_sizes.assign(view.hand_sizes)
    var played: Array[int] = []
    played.assign(view.played)
    for card in Cards.COUNT:
        if not memory.hand.has(card) and not played.has(card):
            memory.unseen.append(card)
    if memory.trump < 0:
        return memory
    # Replay the hand: the first trick is led from the dealer's left, then by each winner.
    var lead := (int(view.dealer) + 1) % 4
    var i := 0
    while i < played.size():
        var cards: Array[int] = []
        for k in mini(4, played.size() - i):
            memory._learn(cards, played[i + k], (lead + k) % 4, lead)
            memory.played_by[played[i + k]] = (lead + k) % 4
            cards.append(played[i + k])
        if cards.size() == 4:
            lead = (lead + BeloteCards.winning_index(cards, memory.trump)) % 4
            memory.tricks_won[lead % 2] += 1
            for c in cards:
                memory.card_points[lead % 2] += BeloteCards.points(c, memory.trump)
        i += 4
    return memory


static func team(s: int) -> int:
    return s % 2


func is_void(s: int, suit: int) -> bool:
    return voids[s].has(suit)


## Whether seat `s` might still hold `card`, as far as the table shows.
func may_hold(s: int, card: int) -> bool:
    if s == seat or not unseen.has(card):
        return false
    # After « belote », the other of the king and queen of trumps is in that seat's hand.
    if belote_seat >= 0 and Cards.suit_of(card) == trump \
            and (Cards.rank_of(card) == Cards.Rank.ROI or Cards.rank_of(card) == Cards.Rank.DAME):
        return s == belote_seat
    # The turned card went to the taker.
    if card == turned and taker >= 0:
        return s == taker
    var suit := Cards.suit_of(card)
    if is_void(s, suit):
        return false
    return suit != trump or BeloteCards.strength(card, trump) < trump_cap[s]


## Whether some seat other than us might still hold a card of `suit`.
func anyone_may_hold_suit(suit: int, seats: Array) -> bool:
    for card in unseen:
        if Cards.suit_of(card) == suit:
            for s in seats:
                if may_hold(s, card):
                    return true
    return false


## Our card is the best left in its suit: nobody can follow higher.
func is_master(card: int) -> bool:
    for other in unseen:
        if Cards.suit_of(other) == Cards.suit_of(card) \
                and BeloteCards.strength(other, trump) > BeloteCards.strength(card, trump):
            return false
    return true


## Whether seat `s`, still to play, could beat `cards` (the trick as it would be).
## A seat is assumed to follow suit unless it has shown it is out of it.
func could_beat(s: int, cards: Array[int]) -> bool:
    var led := Cards.suit_of(cards[0])
    var best := cards[BeloteCards.winning_index(cards, trump)]
    var best_suit := Cards.suit_of(best)
    if not is_void(s, led):
        if best_suit != led:
            return false
        for card in unseen:
            if Cards.suit_of(card) == led and may_hold(s, card) \
                    and BeloteCards.strength(card, trump) > BeloteCards.strength(best, trump):
                return true
        return false
    for card in unseen:
        if Cards.suit_of(card) == trump and may_hold(s, card):
            if best_suit != trump or BeloteCards.strength(card, trump) > BeloteCards.strength(best, trump):
                return true
    return false


## Probability that seat `s` holds `card`: zero if the table rules it out,
## otherwise its share of the room left among the seats that may hold it,
## weighted by what the bids say (bid_weight).
func holds_probability(s: int, card: int) -> float:
    if not may_hold(s, card):
        return 0.0
    var room := 0.0
    for other in 4:
        if may_hold(other, card):
            room += hand_sizes[other] * bid_weight(other, card)
    return hand_sizes[s] * bid_weight(s, card) / room if room > 0.0 else 0.0


## How much more (or less) likely the bids make it that seat `s` holds `card`,
## scaled by bid_trust (0 = ignore the bids):
## - the taker usually holds the valet or the 9 of trumps;
## - someone who passed on the turned suit at the first round usually holds neither.
func bid_weight(s: int, card: int) -> float:
    if bid_trust <= 0.0 or Cards.suit_of(card) != trump:
        return 1.0
    var rank := Cards.rank_of(card)
    if rank != Cards.Rank.VALET and rank != Cards.Rank.NEUF:
        return 1.0
    if s == taker:
        return 1.0 + bid_trust
    if trump == Cards.suit_of(turned) and passed_first.has(s):
        return 1.0 / (1.0 + bid_trust)
    return 1.0


## Points our team still needs to decide the contract its way (taker: make it;
## defence: make it fail), against the points left in play. 0 when it is already
## decided either way, otherwise between 0 and 1: 1 means every point left is needed.
func contract_urgency() -> float:
    if taker < 0:
        return 0.0
    var points := [card_points[0] + announce_points[0], card_points[1] + announce_points[1]]
    var total := 162 + announce_points[0] + announce_points[1]
    if belote_seat >= 0:
        points[belote_seat % 2] += 20
        total += 20
    var taker_needs := total / 2 + 1
    var us := seat % 2
    var needed: int = (taker_needs if taker % 2 == us else total - taker_needs + 1) - points[us]
    var left := 162 - card_points[0] - card_points[1]
    if needed <= 0 or needed > left:
        return 0.0
    return float(needed) / left


## Probability that the team winning `cards` (the trick with our card added)
## still wins it once the seats left have played. Each seat left is assumed to
## take the trick whenever it can: by following higher, or, if it turns out to
## be out of the suit led, by cutting.
func keep_probability(cards: Array[int]) -> float:
    var winner := (leader + BeloteCards.winning_index(cards, trump)) % 4
    var keep := 1.0
    var led := Cards.suit_of(cards[0])
    var best := cards[BeloteCards.winning_index(cards, trump)]
    for k in range(cards.size(), 4):
        var s := (leader + k) % 4
        if team(s) == team(winner):
            continue
        var follows_higher := 1.0  # probability it holds none of the higher cards of the suit led
        var no_led := 1.0  # probability it holds no card of the suit led
        var no_cut := 1.0  # probability it holds no trump that takes the trick
        for card in unseen:
            var p := holds_probability(s, card)
            if p == 0.0:
                continue
            var suit := Cards.suit_of(card)
            if suit == led:
                no_led *= 1.0 - p
                if Cards.suit_of(best) == led and BeloteCards.strength(card, trump) > BeloteCards.strength(best, trump):
                    follows_higher *= 1.0 - p
            elif suit == trump and (Cards.suit_of(best) != trump
                    or BeloteCards.strength(card, trump) > BeloteCards.strength(best, trump)):
                no_cut *= 1.0 - p
        var beats := (1.0 - follows_higher) + no_led * (1.0 - no_cut)
        if led == trump:
            beats = 1.0 - follows_higher
        keep *= 1.0 - clampf(beats, 0.0, 1.0)
    return keep


## True when `cards` (the trick with our card added) cannot be taken by the seats still to play.
func surely_won(cards: Array[int]) -> bool:
    for k in range(cards.size(), 4):
        var s := (leader + k) % 4
        if team(s) != team((leader + BeloteCards.winning_index(cards, trump)) % 4) and could_beat(s, cards):
            return false
    return true


## Learns from `seat_played` playing `card` onto `before` (a trick led by `lead`).
func _learn(before: Array[int], card: int, seat_played: int, lead: int) -> void:
    if before.is_empty():
        return
    var led := Cards.suit_of(before[0])
    var suit := Cards.suit_of(card)
    var best_trump := -1
    for c in before:
        if Cards.suit_of(c) == trump:
            best_trump = maxi(best_trump, BeloteCards.strength(c, trump))
    var master := (lead + BeloteCards.winning_index(before, trump)) % 4
    var partner_master := team(master) == team(seat_played)
    if suit == led:
        if led == trump and BeloteCards.strength(card, trump) < best_trump:
            # Had to climb at trumps and didn't: nothing stronger left.
            trump_cap[seat_played] = mini(trump_cap[seat_played], best_trump)
        return
    voids[seat_played][led] = true
    if suit == trump:
        if best_trump >= 0 and BeloteCards.strength(card, trump) < best_trump and not partner_master:
            trump_cap[seat_played] = mini(trump_cap[seat_played], best_trump)
        return
    if led == trump or not partner_master:
        # Had to cut (or follow trumps) and couldn't.
        voids[seat_played][trump] = true
    elif calls[seat_played] < 0 and BeloteCards.points(card, trump) == 0:
        # A small card on the partner's trick: a call for that suit.
        calls[seat_played] = suit
