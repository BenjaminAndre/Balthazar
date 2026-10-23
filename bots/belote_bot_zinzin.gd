class_name BeloteBotZinzin
extends BeloteBot
## « Zinzin »: a few readable settings, found by evolution (tools/train.gd). They
## follow the axes of card play: how much power to spend and how many points to
## give, how far to trust the partner, whether to set things up or cash now,
## and which suit to use when the suit is free.
## "Trust" and "this trick is ours" are probabilities from BeloteMemory: the
## genome only chooses the thresholds, i.e. how much risk to take.

## Each gene: [meaning shown in the training log and report, Difficile-like value, step size].
const GENES_INFO := {
    "seuil_tour1": ["prise au 1er tour : valeur de main exigée", 50.0, 4.0],
    "seuil_tour2": ["prise au 2e tour : valeur de main exigée", 54.0, 4.0],
    "tirer_atouts": ["préparer : faire tomber les atouts quand on a pris", 3.0, 0.8],
    "encaisser": ["encaisser tout de suite ses cartes maîtresses", 2.0, 0.8],
    "danger_coupe": ["éviter d'entamer une couleur que l'adversaire coupe", 3.0, 0.8],
    "suivre_appel": ["confiance : entamer la couleur appelée par le partenaire", 2.5, 0.8],
    "coupe_partenaire": ["préparer : faire couper le partenaire", 1.5, 0.8],
    "entame_basse": ["entamer petit plutôt que fort", 1.0, 0.6],
    "confiance_gain": ["prendre le pli si on le garde avec cette probabilité", 0.5, 0.08],
    "points_pour_risquer": ["points sur la table pour tenter un pli incertain", 10.0, 4.0],
    "confiance_partenaire": ["charger le pli du partenaire à partir de cette probabilité", 0.5, 0.08],
    "appel": ["appeler (petite carte d'une couleur maîtresse) plutôt que se défausser", 1.0, 0.6],
    "chicane": ["se défausser d'une couleur courte pour pouvoir couper", 1.0, 0.6],
    "eviter_appel_adverse": ["éviter d'entamer la couleur qu'un adversaire a appelée", 1.0, 0.6],
    "marge_atouts": ["ne tirer les atouts qu'avec au moins cette avance en atouts", 0.0, 0.8],
    "audace_marque": ["prendre plus volontiers quand on est mené à la marque", 0.0, 4.0],
    "risque_contrat": ["baisser ses exigences de sécurité quand le contrat se joue", 0.0, 0.15],
    "lecture_encheres": ["croire les enchères (le preneur a valet ou 9, qui a passé ne les a pas)", 1.0, 0.6],
}

var genes: Dictionary = {}


static func load_trained() -> BeloteBotZinzin:
    var bot := BeloteBotZinzin.new()
    bot.genes = ZinzinGenome.GENES.duplicate()
    return bot


## A genome that plays roughly like « Difficile ».
static func difficile_like() -> Dictionary:
    var genome := {}
    for name in GENES_INFO:
        genome[name] = GENES_INFO[name][1]
    return genome


static func gene_names() -> Array:
    return GENES_INFO.keys()


func gene(name: String) -> float:
    return genes.get(name, GENES_INFO[name][1])


func choose(view: Dictionary) -> Dictionary:
    var legal: Array = view.legal
    if legal.size() == 1:
        return legal[0]
    if view.phase != BeloteState.Phase.PLAYING:
        return _take_or_pass(view)
    var memory := BeloteMemory.from_view(view)
    memory.bid_trust = maxf(gene("lecture_encheres"), 0.0)
    var cards: Array[int] = []
    for move in legal:
        cards.append(move.card)
    var card: int
    if memory.trick.is_empty():
        card = _lead_card(cards, memory, view)
    else:
        card = _follow_card(cards, memory)
    return {"kind": "play", "card": card}


func _take_or_pass(view: Dictionary) -> Dictionary:
    var hand: Array[int] = []
    hand.assign(view.hand)
    hand.append(view.turned)
    var best := {"kind": "pass"}
    var first: bool = view.phase == BeloteState.Phase.BID_ROUND_1
    var best_value := gene("seuil_tour1" if first else "seuil_tour2")
    # Behind at the score: a lower bar (by up to audace_marque points of hand value).
    var scores: Array = view.get("scores", [0, 0])
    var behind: float = scores[1 - int(view.seat) % 2] - scores[int(view.seat) % 2]
    best_value -= gene("audace_marque") * clampf(behind / 30.0, -1.0, 1.0)
    for move in view.legal:
        if move.kind != "take":
            continue
        var value := float(BeloteBotDifficile.strength_of(hand, move.suit))
        if int(view.dealer) % 2 == int(view.seat) % 2:
            value += 3.0
        if value >= best_value:
            best = move
            best_value = value
    return best


# --- Leading: the suit is free; set up or cash; power ------------------------------

func _lead_card(cards: Array[int], memory: BeloteMemory, view: Dictionary) -> int:
    var trump := memory.trump
    var me := memory.seat
    var partner := (me + 2) % 4
    var opponents := [(me + 1) % 4, (me + 3) % 4]
    var ours := int(view.taker) % 2 == me % 2
    var opponents_trump := memory.anyone_may_hold_suit(trump, opponents)
    # Trump count: ours against how many the opponents may still hold.
    var trump_lead := -INF
    if ours and opponents_trump:
        var mine := 0.0
        for c in memory.hand:
            if Cards.suit_of(c) == trump:
                mine += 1.0
        var theirs := 0.0
        for c in memory.unseen:
            if Cards.suit_of(c) == trump:
                for o in opponents:
                    theirs += memory.holds_probability(o, c)
        trump_lead = mine - theirs
    var best := cards[0]
    var best_score := -INF
    for card in cards:
        var suit := Cards.suit_of(card)
        var master := memory.is_master(card)
        var score := 0.0
        if suit == trump:
            if ours and opponents_trump and master and trump_lead >= gene("marge_atouts"):
                score += gene("tirer_atouts")
            elif not ours:
                score -= 1.0
        else:
            var cut_risk := false
            for o in opponents:
                if memory.is_void(o, suit) and not memory.is_void(o, trump) and opponents_trump:
                    cut_risk = true
            if cut_risk:
                score -= gene("danger_coupe")
            elif master:
                score += gene("encaisser")
            if memory.calls[partner] == suit:
                score += gene("suivre_appel")
            for o in opponents:
                if memory.calls[o] == suit:
                    score -= gene("eviter_appel_adverse")
            if memory.is_void(partner, suit) and not memory.is_void(partner, trump):
                score += gene("coupe_partenaire")
            var ten := Cards.make(suit, Cards.Rank.DIX)
            if memory.hand.has(ten) and card != ten and not memory.hand.has(Cards.make(suit, Cards.Rank.AS)):
                score -= 1.0  # would expose our ten
        # Power dial: positive leads low, negative leads high (masters aside).
        if not master:
            score += gene("entame_basse") * (1.0 - BeloteCards.strength(card, trump) / 7.0)
        score -= BeloteCards.points(card, trump) / 40.0
        if score > best_score:
            best_score = score
            best = card
    return best


# --- Following ------------------------------------------------------------------------

func _follow_card(cards: Array[int], memory: BeloteMemory) -> int:
    var trump := memory.trump
    var trick := memory.trick
    var me := memory.seat
    var master := (memory.leader + BeloteCards.winning_index(trick, trump)) % 4
    var following := cards.all(func(c: int) -> bool: return Cards.suit_of(c) == Cards.suit_of(trick[0]))
    if master % 2 == me % 2:
        # Trust: does the partner keep the trick whatever we play?
        var probe := trick.duplicate()
        probe.append(_weakest(cards, trump))
        if memory.keep_probability(probe) >= _threshold("confiance_partenaire", memory):
            var loaded := _most_points(cards, memory, following)
            if loaded >= 0:
                return loaded
        return _give_least(cards, memory, following, true)
    # The opponents hold the trick: take it when we would keep it, as cheaply as possible.
    var on_table := 0
    for c in trick:
        on_table += BeloteCards.points(c, trump)
    var keepers: Array[int] = []
    var winners: Array[int] = []
    for card in cards:
        var after := trick.duplicate()
        after.append(card)
        if BeloteCards.winning_index(after, trump) == trick.size():
            winners.append(card)
            if memory.keep_probability(after) >= _threshold("confiance_gain", memory):
                keepers.append(card)
    if not keepers.is_empty():
        return _weakest(keepers, trump)
    if not winners.is_empty() and on_table >= gene("points_pour_risquer"):
        var strongest := winners[0]
        for card in winners:
            if BeloteCards.strength(card, trump) > BeloteCards.strength(strongest, trump):
                strongest = card
        return strongest
    if not winners.is_empty() and winners.size() == cards.size():
        return _weakest(winners, trump)
    return _give_least(cards, memory, following, false)


## Loads the trick: the most points we can spare (no trump on a side suit, and no
## master ace while we are out of the suit and could cash it later).
func _most_points(cards: Array[int], memory: BeloteMemory, following: bool) -> int:
    var trump := memory.trump
    var led := Cards.suit_of(memory.trick[0])
    var best := -1
    for card in cards:
        if Cards.suit_of(card) == trump and led != trump:
            continue
        if not following and memory.is_master(card) and Cards.rank_of(card) == Cards.Rank.AS:
            continue
        if best < 0 or BeloteCards.points(card, trump) > BeloteCards.points(best, trump):
            best = card
    return best


## Nothing to win or load: give the least. When out of the suit, the suit is free:
## call a suit where we hold the master card, or shorten a suit to cut it later.
func _give_least(cards: Array[int], memory: BeloteMemory, following: bool, partner_holds: bool) -> int:
    var trump := memory.trump
    var best := cards[0]
    var best_score := -INF
    for card in cards:
        var suit := Cards.suit_of(card)
        var score := -BeloteCards.points(card, trump) / 5.0 - BeloteCards.strength(card, trump) / 7.0
        if suit == trump and Cards.suit_of(memory.trick[0]) != trump:
            score -= 2.0
        if not following and suit != trump:
            if memory.is_master(card):
                score -= 3.0
            var count := 0
            var holds_master := false
            for c in memory.hand:
                if Cards.suit_of(c) == suit:
                    count += 1
                    holds_master = holds_master or (memory.is_master(c) and c != card)
            score += gene("chicane") / count
            if partner_holds and holds_master and BeloteCards.points(card, trump) == 0 \
                    and memory.calls[memory.seat] < 0:
                score += gene("appel")
        if score > best_score:
            best_score = score
            best = card
    return best


## A trust threshold, lowered when the contract is at stake: the more of the
## points left our side needs, the more risk it takes (risque_contrat).
func _threshold(name: String, memory: BeloteMemory) -> float:
    return clampf(gene(name) - gene("risque_contrat") * memory.contract_urgency(), 0.0, 1.0)
