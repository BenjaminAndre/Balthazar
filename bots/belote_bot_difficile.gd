class_name BeloteBotDifficile
extends BeloteBot
## « Difficile »: counts the cards (BeloteMemory) and plays like a careful club
## player. It draws trumps when its side took, cashes master cards where nobody
## can cut, and gives the partner a cut. It loads points onto a trick only when
## the trick is surely won, and makes and follows direct calls: a small card
## discarded on the partner's trick asks for that suit.

## Bidding: hand value needed to take on each round, with the turned card counted.
var take_first := 50
var take_second := 54
## « Moyen » misjudges its hands at the bidding: its hand value is off by a
## random amount of about this many points (0 for « Difficile »). The error
## depends only on the hand, so the same hand is always judged the same way.
var bid_noise := 0.0


func choose(view: Dictionary) -> Dictionary:
    var legal: Array = view.legal
    if legal.size() == 1:
        return legal[0]
    if view.phase != BeloteState.Phase.PLAYING:
        return _bid_hard(view)
    var memory := BeloteMemory.from_view(view)
    var cards: Array[int] = []
    for move in legal:
        cards.append(move.card)
    var card := _lead_hard(cards, memory, view) if memory.trick.is_empty() else _follow(cards, memory)
    return {"kind": "play", "card": card}


# --- Bidding ---------------------------------------------------------------------

func _bid_hard(view: Dictionary) -> Dictionary:
    var hand: Array[int] = []
    hand.assign(view.hand)
    var best := {"kind": "pass"}
    var first: bool = view.phase == BeloteState.Phase.BID_ROUND_1
    var best_value := float(take_first if first else take_second)
    for move in view.legal:
        if move.kind != "take":
            continue
        var with_turned := hand.duplicate()
        with_turned.append(view.turned)
        var value := float(strength_of(with_turned, move.suit)) + _misjudgement(hand, move.suit, view)
        # Our partner is the dealer: the turned card is theirs to pick up too, a small bonus.
        if int(view.dealer) % 2 == int(view.seat) % 2:
            value += 3
        if value >= best_value:
            best = move
            best_value = value
    return best


## Moyen's error when valuing `hand` for `suit` (0 without bid_noise).
func _misjudgement(hand: Array[int], suit: int, view: Dictionary) -> float:
    if bid_noise <= 0.0:
        return 0.0
    var sorted := hand.duplicate()
    sorted.sort()
    var rng := RandomNumberGenerator.new()
    rng.seed = hash([sorted, suit, view.turned, view.seat])
    return rng.randfn(0.0, bid_noise)


## A hand's worth with `trump` as trumps: trump honours and length, side aces,
## guarded tens, belote.
static func strength_of(hand: Array[int], trump: int) -> int:
    var value := 0
    var trumps := 0
    var has_king := false
    var has_queen := false
    for card in hand:
        var suit := Cards.suit_of(card)
        var rank := Cards.rank_of(card)
        if suit == trump:
            trumps += 1
            value += BeloteCards.TRUMP_POINTS[rank]
            has_king = has_king or rank == Cards.Rank.ROI
            has_queen = has_queen or rank == Cards.Rank.DAME
        elif rank == Cards.Rank.AS:
            value += 11
        elif rank == Cards.Rank.DIX and hand.has(Cards.make(suit, Cards.Rank.AS)):
            value += 6
    value += trumps * 6
    if trumps >= 4:
        value += 8
    if has_king and has_queen:
        value += 10
    return value


# --- Leading -----------------------------------------------------------------------

func _lead_hard(cards: Array[int], memory: BeloteMemory, view: Dictionary) -> int:
    var trump := memory.trump
    var me := memory.seat
    var partner := (me + 2) % 4
    var opponents := [(me + 1) % 4, (me + 3) % 4]
    var ours := int(view.taker) % 2 == me % 2
    var opponents_may_trump := memory.anyone_may_hold_suit(trump, opponents)
    # 1. Our side took: draw the opponents' trumps with a master trump.
    if ours and opponents_may_trump:
        for card in cards:
            if Cards.suit_of(card) == trump and memory.is_master(card):
                return card
    # 2. The partner called a suit: lead our smallest card there.
    var called := memory.calls[partner]
    if called >= 0 and called != trump:
        var small := _lowest_in(cards, called, trump)
        if small >= 0:
            return small
    # 3. Cash a master card in a suit the opponents can follow or can't cut.
    for card in cards:
        var suit := Cards.suit_of(card)
        if suit == trump or not memory.is_master(card):
            continue
        var safe := true
        for o in opponents:
            if memory.is_void(o, suit) and not memory.is_void(o, trump) and opponents_may_trump:
                safe = false
        if safe:
            return card
    # 4. Give the partner a cut: a small card in a suit they are out of.
    if not memory.is_void(partner, trump):
        for suit in 4:
            if suit != trump and memory.is_void(partner, suit):
                var small := _lowest_in(cards, suit, trump)
                if small >= 0:
                    return small
    # 5. Otherwise a small card, not from a suit where we hold an unguarded ten.
    var best := -1
    for card in cards:
        if Cards.suit_of(card) == trump and not ours:
            continue
        if best < 0 or _lead_cost(card, cards, trump) < _lead_cost(best, cards, trump):
            best = card
    return best if best >= 0 else _weakest(cards, trump)


func _lead_cost(card: int, cards: Array[int], trump: int) -> int:
    var cost := _cost(card, trump)
    var suit := Cards.suit_of(card)
    var ten := Cards.make(suit, Cards.Rank.DIX)
    if suit != trump and cards.has(ten) and card != ten and not cards.has(Cards.make(suit, Cards.Rank.AS)):
        cost += 60  # leading this suit would expose our ten
    return cost


func _lowest_in(cards: Array[int], suit: int, trump: int) -> int:
    var best := -1
    for card in cards:
        if Cards.suit_of(card) == suit and (best < 0 or _cost(card, trump) < _cost(best, trump)):
            best = card
    return best


# --- Following ---------------------------------------------------------------------

func _follow(cards: Array[int], memory: BeloteMemory) -> int:
    var trump := memory.trump
    var trick := memory.trick
    var me := memory.seat
    var master := (memory.leader + BeloteCards.winning_index(trick, trump)) % 4
    var last := trick.size() == 3
    var on_table := 0
    for c in trick:
        on_table += BeloteCards.points(c, trump)
    if master % 2 == me % 2:
        return _partner_holds(cards, memory, last)
    # The opponents hold the trick: win it as cheaply as possible, when it can be kept.
    var sure: Array[int] = []
    var winners: Array[int] = []
    for card in cards:
        var after := trick.duplicate()
        after.append(card)
        if BeloteCards.winning_index(after, trump) == trick.size():
            winners.append(card)
            if last or memory.surely_won(after):
                sure.append(card)
    if not sure.is_empty():
        return _weakest(sure, trump)
    if not winners.is_empty() and on_table >= 10:
        # Worth fighting for even if it may be taken back: our strongest try.
        var strongest := winners[0]
        for card in winners:
            if BeloteCards.strength(card, trump) > BeloteCards.strength(strongest, trump):
                strongest = card
        return strongest
    if not winners.is_empty() and Cards.suit_of(winners[0]) == trump and Cards.suit_of(trick[0]) != trump:
        # Forced to cut anyway: the smallest trump that cuts.
        return _weakest(winners, trump)
    return _discard(cards, memory)


## Our partner holds the trick: load points when it is surely ours, call otherwise.
func _partner_holds(cards: Array[int], memory: BeloteMemory, last: bool) -> int:
    var trump := memory.trump
    var trick := memory.trick
    var safe := last
    if not safe:
        var probe := trick.duplicate()
        probe.append(_weakest(cards, trump))
        safe = memory.surely_won(probe)
    var led := Cards.suit_of(trick[0])
    var following := cards.all(func(c: int) -> bool: return Cards.suit_of(c) == led)
    if safe:
        # Load the biggest non-trump card we can spare (not a master ace we can cash later).
        var best := -1
        for card in cards:
            if Cards.suit_of(card) == trump and Cards.suit_of(trick[0]) != trump:
                continue
            if not following and memory.is_master(card) and Cards.rank_of(card) == Cards.Rank.AS:
                continue
            if best < 0 or BeloteCards.points(card, trump) > BeloteCards.points(best, trump):
                best = card
        if best >= 0:
            return best
    if not following:
        var call := _call(cards, memory)
        if call >= 0:
            return call
    return _discard(cards, memory)


## Appel direct: the smallest card of a side suit where we hold the master card.
func _call(cards: Array[int], memory: BeloteMemory) -> int:
    var trump := memory.trump
    if memory.calls[memory.seat] >= 0:
        return -1
    for card in cards:
        var suit := Cards.suit_of(card)
        if suit == trump or not memory.is_master(card):
            continue
        var small := _lowest_in(cards, suit, trump)
        if small >= 0 and small != card and BeloteCards.points(small, trump) == 0:
            return small
    return -1


## Nothing to win: give the least, from short side suits first (to cut them later),
## keeping trumps and master cards.
func _discard(cards: Array[int], memory: BeloteMemory) -> int:
    var trump := memory.trump
    var best := -1
    var best_cost := 1 << 30
    for card in cards:
        var suit := Cards.suit_of(card)
        var count := 0
        for c in memory.hand:
            if Cards.suit_of(c) == suit:
                count += 1
        var cost := _cost(card, trump) * 4 + count * 3
        if memory.is_master(card) and suit != trump:
            cost += 80
        if cost < best_cost:
            best = card
            best_cost = cost
    return best
