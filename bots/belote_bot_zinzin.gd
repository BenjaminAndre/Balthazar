class_name BeloteBotZinzin
extends BeloteBot
## « Zinzin »: every decision is a weighted sum of readable features, with weights
## (the genome) found by evolution against « Difficile » (tools/evolve.gd).
## Reading the trained weights tells what it learned, e.g. a big
## "charge_when_sure" means it loads points onto tricks it knows are won.
##
## Bidding: it takes the suit whose weighted hand value beats its threshold.
## Play: it plays the legal card with the highest score.

## Feature names, in genome order. Bidding first, then card play.
const BID_FEATURES := ["bid_valet", "bid_neuf", "bid_as_atout", "bid_dix_atout", "bid_petit_atout",
        "bid_longueur4", "bid_as", "bid_dix_garde", "bid_belote", "bid_partenaire_donne",
        "seuil_tour1", "seuil_tour2"]
const PLAY_FEATURES := ["points", "force", "atout", "gagne", "gagne_sur", "charge_si_sur",
        "atout_si_partenaire", "maitre", "entame_maitre", "entame_atout_preneur",
        "entame_atout_defense", "entame_appel", "entame_coupe_partenaire", "entame_coupe_adverse",
        "gagne_points_table", "gagne_en_dernier", "defausse_courte", "appel", "dix_expose",
        "belote", "coupe", "as_cote", "dix_cote", "charge_incertain"]

var genes: Dictionary = {}


static func load_trained() -> BeloteBotZinzin:
    var bot := BeloteBotZinzin.new()
    bot.genes = ZinzinGenome.GENES.duplicate()
    return bot


static func feature_names() -> Array:
    return BID_FEATURES + PLAY_FEATURES


func gene(name: String) -> float:
    return genes.get(name, 0.0)


func choose(view: Dictionary) -> Dictionary:
    var legal: Array = view.legal
    if legal.size() == 1:
        return legal[0]
    if view.phase != BeloteState.Phase.PLAYING:
        return _bid_weighted(view)
    var memory := BeloteMemory.from_view(view)
    var best: Dictionary = legal[0]
    var best_score := -INF
    for move in legal:
        var score := 0.0
        var features := card_features(move.card, memory, view)
        for name in features:
            score += features[name] * gene(name)
        if score > best_score:
            best_score = score
            best = move
    return best


func _bid_weighted(view: Dictionary) -> Dictionary:
    var hand: Array[int] = []
    hand.assign(view.hand)
    hand.append(view.turned)
    var first: bool = view.phase == BeloteState.Phase.BID_ROUND_1
    var best := {"kind": "pass"}
    var best_value := gene("seuil_tour1" if first else "seuil_tour2")
    for move in view.legal:
        if move.kind != "take":
            continue
        var value := 0.0
        var features := bid_features(hand, move.suit, view)
        for name in features:
            value += features[name] * gene(name)
        if value >= best_value:
            best = move
            best_value = value
    return best


static func bid_features(hand: Array[int], trump: int, view: Dictionary) -> Dictionary:
    var f := {}
    for name in BID_FEATURES:
        if not name.begins_with("seuil"):
            f[name] = 0.0
    var trumps := 0
    for card in hand:
        var suit := Cards.suit_of(card)
        var rank := Cards.rank_of(card)
        if suit == trump:
            trumps += 1
            match rank:
                Cards.Rank.VALET: f.bid_valet = 1.0
                Cards.Rank.NEUF: f.bid_neuf = 1.0
                Cards.Rank.AS: f.bid_as_atout = 1.0
                Cards.Rank.DIX: f.bid_dix_atout = 1.0
                _: f.bid_petit_atout += 1.0
        elif rank == Cards.Rank.AS:
            f.bid_as += 1.0
        elif rank == Cards.Rank.DIX and hand.has(Cards.make(suit, Cards.Rank.AS)):
            f.bid_dix_garde += 1.0
    f.bid_longueur4 = 1.0 if trumps >= 4 else 0.0
    if hand.has(Cards.make(trump, Cards.Rank.ROI)) and hand.has(Cards.make(trump, Cards.Rank.DAME)):
        f.bid_belote = 1.0
    f.bid_partenaire_donne = 1.0 if int(view.dealer) % 2 == int(view.seat) % 2 else 0.0
    return f


## The features of playing `card` now. All are between about -1 and 1.
static func card_features(card: int, memory: BeloteMemory, view: Dictionary) -> Dictionary:
    var trump := memory.trump
    var trick := memory.trick
    var me := memory.seat
    var partner := (me + 2) % 4
    var opponents := [(me + 1) % 4, (me + 3) % 4]
    var suit := Cards.suit_of(card)
    var is_trump := suit == trump
    var points := BeloteCards.points(card, trump)
    var f := {}
    for name in PLAY_FEATURES:
        f[name] = 0.0
    f.points = points / 20.0
    f.force = BeloteCards.strength(card, trump) / 7.0
    f.atout = 1.0 if is_trump else 0.0
    f.maitre = 1.0 if memory.is_master(card) else 0.0
    f.as_cote = 1.0 if not is_trump and Cards.rank_of(card) == Cards.Rank.AS else 0.0
    f.dix_cote = 1.0 if not is_trump and Cards.rank_of(card) == Cards.Rank.DIX else 0.0
    var king := Cards.make(trump, Cards.Rank.ROI)
    var queen := Cards.make(trump, Cards.Rank.DAME)
    if (card == king or card == queen) and (memory.hand.has(king) or memory.hand.has(queen)):
        f.belote = 1.0
    var count := 0
    for c in memory.hand:
        if Cards.suit_of(c) == suit:
            count += 1
    if trick.is_empty():
        var ours := int(view.taker) % 2 == me % 2
        f.entame_maitre = f.maitre
        f.entame_atout_preneur = 1.0 if is_trump and ours else 0.0
        f.entame_atout_defense = 1.0 if is_trump and not ours else 0.0
        f.entame_appel = 1.0 if memory.calls[partner] == suit and not is_trump else 0.0
        f.entame_coupe_partenaire = 1.0 if memory.is_void(partner, suit) and not is_trump \
                and not memory.is_void(partner, trump) else 0.0
        for o in opponents:
            if memory.is_void(o, suit) and not is_trump and not memory.is_void(o, trump):
                f.entame_coupe_adverse = 1.0
        var ten := Cards.make(suit, Cards.Rank.DIX)
        if not is_trump and memory.hand.has(ten) and card != ten \
                and not memory.hand.has(Cards.make(suit, Cards.Rank.AS)):
            f.dix_expose = 1.0
        return f
    var after := trick.duplicate()
    after.append(card)
    var led := Cards.suit_of(trick[0])
    var master := (memory.leader + BeloteCards.winning_index(trick, trump)) % 4
    var partner_master := master % 2 == me % 2
    var wins := BeloteCards.winning_index(after, trump) == trick.size()
    var surely := memory.surely_won(after) or after.size() == 4
    var ours_after := (memory.leader + BeloteCards.winning_index(after, trump)) % 4 % 2 == me % 2
    var on_table := 0
    for c in trick:
        on_table += BeloteCards.points(c, trump)
    f.gagne = 1.0 if wins else 0.0
    f.gagne_sur = 1.0 if wins and surely else 0.0
    f.charge_si_sur = points / 20.0 if ours_after and surely and not wins else 0.0
    # Risk: loading points onto a trick our side holds but could still lose.
    f.charge_incertain = points / 20.0 if ours_after and not surely and not wins else 0.0
    f.atout_si_partenaire = 1.0 if partner_master and is_trump and led != trump else 0.0
    f.gagne_points_table = on_table / 30.0 if wins else 0.0
    f.gagne_en_dernier = 1.0 if wins and trick.size() == 3 else 0.0
    f.coupe = 1.0 if wins and is_trump and led != trump else 0.0
    if suit != led and not is_trump:
        f.defausse_courte = 1.0 / count
        if partner_master and points == 0 and memory.calls[me] < 0:
            for c in memory.hand:
                if Cards.suit_of(c) == suit and memory.is_master(c):
                    f.appel = 1.0
    return f
