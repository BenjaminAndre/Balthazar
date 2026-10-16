class_name BeloteTrickRule
extends RefCounted
## Which cards a player may play into a trick (GDD §3.4): fournir, monter à
## l'atout, couper, surcouper, sous-couper. A variant can extend this class.


## `trick` holds the cards played so far, the first one by `leader`.
func legal_cards(hand: Array[int], trick: Array[int], leader: int, seat: int,
        trump: int, rules: BeloteRules) -> Array[int]:
    if trick.is_empty():
        return hand.duplicate()
    var led := Cards.suit_of(trick[0])
    var best_trump := _best_trump(trick, trump)
    var followers := _of_suit(hand, led)
    if not followers.is_empty():
        if led == trump:
            var higher := _higher_trumps(followers, best_trump, trump)
            return higher if not higher.is_empty() else followers
        return followers
    var master := (leader + BeloteCards.winning_index(trick, trump)) % 4
    if master % 2 == seat % 2 and not rules.must_trump_over_partner:
        return hand.duplicate()
    var trumps := _of_suit(hand, trump)
    if trumps.is_empty():
        return hand.duplicate()
    if best_trump < 0:
        return trumps
    var over := _higher_trumps(trumps, best_trump, trump)
    if not over.is_empty():
        return over
    # Can't overtrump and the partner isn't master: "pisser" (sous-couper).
    return hand.duplicate() if rules.free_undertrump else trumps


func _best_trump(trick: Array[int], trump: int) -> int:
    var best := -1
    for card in trick:
        if Cards.suit_of(card) == trump:
            best = maxi(best, BeloteCards.strength(card, trump))
    return best


func _higher_trumps(cards: Array[int], than: int, trump: int) -> Array[int]:
    var out: Array[int] = []
    for card in cards:
        if BeloteCards.strength(card, trump) > than:
            out.append(card)
    return out


func _of_suit(cards: Array[int], suit: int) -> Array[int]:
    var out: Array[int] = []
    for card in cards:
        if Cards.suit_of(card) == suit:
            out.append(card)
    return out
