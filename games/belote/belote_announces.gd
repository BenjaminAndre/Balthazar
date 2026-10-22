class_name BeloteAnnounces
extends RefCounted
## Announces (GDD §3.6): sequences and carrés found in an 8-card hand, and which
## one is best. A card counts in one announce only: carrés are taken first, then
## sequences from the cards left.
## An announce is {kind: "suite"|"carre", points, length, top, suit, cards, name}.

const CARRE_POINTS := {
    Cards.Rank.VALET: 200, Cards.Rank.NEUF: 150,
    Cards.Rank.AS: 100, Cards.Rank.DIX: 100, Cards.Rank.ROI: 100, Cards.Rank.DAME: 100,
}
const CARRE_NAMES := {
    Cards.Rank.VALET: "valets", Cards.Rank.NEUF: "9", Cards.Rank.AS: "as",
    Cards.Rank.DIX: "10", Cards.Rank.ROI: "rois", Cards.Rank.DAME: "dames",
}


## Every announce in the hand. Carrés of 7 and 8 are worth nothing, so they're left out.
func find(hand: Array[int]) -> Array[Dictionary]:
    var found: Array[Dictionary] = []
    for rank in CARRE_POINTS:
        var cards: Array[int] = []
        for suit in 4:
            if hand.has(Cards.make(suit, rank)):
                cards.append(Cards.make(suit, rank))
        if cards.size() == 4:
            found.append({"kind": "carre", "points": CARRE_POINTS[rank], "length": 4, "top": rank,
                    "suit": -1, "cards": cards, "name": "Carré de %s" % CARRE_NAMES[rank]})
    var free := hand.duplicate()
    for carre in found:
        for card in carre.cards:
            free.erase(card)
    # Rank enum order is the natural order 7 8 9 10 V D R A.
    for suit in 4:
        var run: Array[int] = []
        for rank in 9:
            if rank < 8 and free.has(Cards.make(suit, rank)):
                run.append(Cards.make(suit, rank))
                continue
            if run.size() >= 3:
                found.append(_suite(run, suit))
            run = []
    return found


func _suite(run: Array[int], suit: int) -> Dictionary:
    var points := 20 if run.size() == 3 else (50 if run.size() == 4 else 100)
    var name := "Tierce" if run.size() == 3 else ("Cinquante" if run.size() == 4 else "Cent")
    return {"kind": "suite", "points": points, "length": run.size(),
            "top": Cards.rank_of(run[-1]), "suit": suit, "cards": run.duplicate(), "name": name}


## True when announce `a` beats `b`: more points, then a carré over a sequence,
## then the longer sequence, then the higher top card, then a sequence in trumps.
## A full tie returns false, so the first seat to speak keeps the lead.
func beats(a: Dictionary, b: Dictionary, trump: int) -> bool:
    if a.points != b.points:
        return a.points > b.points
    if a.kind != b.kind:
        return a.kind == "carre"
    if a.length != b.length:
        return a.length > b.length
    if a.top != b.top:
        return a.top > b.top
    return a.suit == trump and b.suit != trump


## The team whose best announce wins, or -1 when nobody announced. `announces`
## holds one list per seat; `first` is the first seat to speak.
func winning_team(announces: Array, first: int, trump: int) -> int:
    var best: Dictionary = {}
    var best_seat := -1
    for k in 4:
        var seat := (first + k) % 4
        for announce in announces[seat]:
            if best.is_empty() or beats(announce, best, trump):
                best = announce
                best_seat = seat
    return -1 if best_seat < 0 else best_seat % 2
