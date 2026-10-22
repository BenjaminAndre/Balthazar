extends SceneTree
## Trains « Zinzin » headless, in three stages, and writes bots/zinzin_genome.gd
## and docs/zinzin.md (what it learned):
##     godot --headless --path . -s res://tools/train.gd -- [deals] [generations] [samples]
##
## 1. Teacher: the PIMC bot (seats 0 and 2) plays `deals` deals against « Difficile »
##    and records, at each decision, how every legal card turned out in its sampled worlds.
## 2. Imitation: Zinzin's play weights are fitted so that its softmax over the legal
##    cards matches the teacher's (softmax regression on soft targets).
## 3. Reinforcement: evolution strategies (antithetic, rank-based) tune every gene,
##    bidding thresholds and risk weights included, on the points won in duplicate
##    matches against « Difficile ».
## Progress is printed as it goes; run it in the background and read the log.

const TEMPERATURE := 10.0  # points: how sharply the teacher's values become targets
const POPULATION := 8  # antithetic pairs per generation
const EVAL_DEALS := 120
const SIGMA := 0.12
const STEP := 0.06
## Genes on a points scale move ten times further per step.
const BIG_GENES := ["bid_", "seuil_"]

var _started := 0


func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    var deals := int(args[0]) if args.size() > 0 else 300
    var generations := int(args[1]) if args.size() > 1 else 40
    var samples := int(args[2]) if args.size() > 2 else 16
    _started = Time.get_ticks_msec()
    var genes: Dictionary = ZinzinGenome.GENES.duplicate()
    for name in BeloteBotZinzin.feature_names():
        if not genes.has(name):
            genes[name] = 0.0
    var before := _measure(genes, 600, 50000)
    _log("start: zinzin vs difficile %+.1f ± %.1f" % [before.mean, 2 * before.stderr])
    if deals > 0:
        var data := _teach(deals, samples)
        _log("teacher: %d decisions recorded" % data.size())
        _imitate(genes, data)
        var imitated := _measure(genes, 600, 50000)
        _log("after imitation: zinzin vs difficile %+.1f ± %.1f" % [imitated.mean, 2 * imitated.stderr])
        _write_genome(genes)
    genes = _evolve(genes, generations)
    _write_genome(genes)
    _report(genes)
    quit()


# --- 1. Teacher ------------------------------------------------------------------------

func _teach(deals: int, samples: int) -> Array:
    var game := Belote.new()
    var teacher := BeloteBotPimc.new()
    teacher.samples = samples
    teacher.rng.seed = 7
    var other := BeloteBotDifficile.new()
    var data := []
    for i in deals:
        var state: BeloteState = game.new_state(20000 + i)
        while state.last_hand.is_empty() and state.deal_number < 20:
            var seat := state.to_act
            var view := game.view_for(state, seat)
            if seat % 2 == 0:
                var move := teacher.choose(view)
                if not teacher.last_values.is_empty():
                    var memory := BeloteMemory.from_view(view)
                    var entry := {"features": [], "values": []}
                    for card in teacher.last_values:
                        entry.features.append(BeloteBotZinzin.card_features(card, memory, view))
                        entry.values.append(teacher.last_values[card])
                    data.append(entry)
                game.apply(state, move)
            else:
                game.apply(state, other.choose(view))
        if (i + 1) % 25 == 0:
            _log("teacher: %d/%d deals, %d decisions" % [i + 1, deals, data.size()])
    return data


# --- 2. Imitation ------------------------------------------------------------------------

func _imitate(genes: Dictionary, data: Array) -> void:
    var names: Array = BeloteBotZinzin.PLAY_FEATURES
    var rate := 0.5
    for epoch in 300:
        var gradient := {}
        for name in names:
            gradient[name] = 0.0
        var loss := 0.0
        for entry in data:
            var target := _softmax(entry.values, 1.0 / TEMPERATURE)
            var scores := []
            for f in entry.features:
                var s := 0.0
                for name in names:
                    s += f[name] * genes[name]
                scores.append(s)
            var model := _softmax(scores, 1.0)
            for k in model.size():
                loss -= target[k] * log(maxf(model[k], 1e-9))
                var diff: float = model[k] - target[k]
                for name in names:
                    gradient[name] += diff * entry.features[k][name]
        for name in names:
            # Small L2 pull, so unused features stay near zero.
            genes[name] -= rate * (gradient[name] / data.size() + 0.001 * genes[name])
        if epoch % 50 == 0:
            _log("imitation epoch %d: loss %.4f" % [epoch, loss / data.size()])


func _softmax(values: Array, scale: float) -> Array:
    var top := -INF
    for v in values:
        top = maxf(top, v * scale)
    var exps := []
    var total := 0.0
    for v in values:
        var e := exp(v * scale - top)
        exps.append(e)
        total += e
    for k in exps.size():
        exps[k] /= total
    return exps


# --- 3. Evolution strategies --------------------------------------------------------------

func _evolve(genes: Dictionary, generations: int) -> Dictionary:
    var names: Array = BeloteBotZinzin.feature_names()
    var rng := RandomNumberGenerator.new()
    rng.seed = 99
    var best := genes.duplicate()
    var best_score := -INF
    for generation in generations:
        var seed_base := 100000 + generation * 1000
        var noises := []
        var scores := []
        for i in POPULATION:
            var noise := {}
            for name in names:
                noise[name] = rng.randfn(0.0, 1.0)
            noises.append(noise)
            for sign in [1.0, -1.0]:
                var trial := _shift(genes, noise, sign * SIGMA)
                scores.append(_measure(trial, EVAL_DEALS, seed_base).mean)
        # Rank-based weights: robust to the noise of card luck.
        var order := range(scores.size())
        order.sort_custom(func(a: int, b: int) -> bool: return scores[a] < scores[b])
        var ranks := []
        ranks.resize(scores.size())
        for r in order.size():
            ranks[order[r]] = float(r) / (order.size() - 1) - 0.5
        var step := {}
        for name in names:
            step[name] = 0.0
        for i in POPULATION:
            var weight: float = ranks[2 * i] - ranks[2 * i + 1]
            for name in names:
                step[name] += weight * noises[i][name]
        genes = _shift(genes, step, STEP / POPULATION)
        var current := _measure(genes, EVAL_DEALS * 2, 500000 + generation * 1000)
        _log("generation %d: %+.1f ± %.1f (best trial %+.1f)" % [generation, current.mean,
                2 * current.stderr, scores.max()])
        if current.mean > best_score:
            best_score = current.mean
            best = genes.duplicate()
            _write_genome(best)
    return best


func _shift(genes: Dictionary, direction: Dictionary, amount: float) -> Dictionary:
    var out := genes.duplicate()
    for name in direction:
        var scale := 10.0 if BIG_GENES.any(func(p: String) -> bool: return name.begins_with(p)) else 1.0
        out[name] = genes.get(name, 0.0) + direction[name] * amount * scale
    return out


func _measure(genes: Dictionary, deals: int, first_seed: int) -> Dictionary:
    var bot := BeloteBotZinzin.new()
    bot.genes = genes
    return BotArena.match_up(bot, BeloteBotDifficile.new(), deals, first_seed)


# --- Output --------------------------------------------------------------------------------

func _write_genome(genes: Dictionary) -> void:
    var lines := ["class_name ZinzinGenome", "## The weights of « Zinzin » (BeloteBotZinzin), written by tools/train.gd.", "",
            "const GENES := {"]
    for name in BeloteBotZinzin.feature_names():
        lines.append("    \"%s\": %.4f," % [name, genes.get(name, 0.0)])
    lines.append("}")
    var file := FileAccess.open("res://bots/zinzin_genome.gd", FileAccess.WRITE)
    file.store_string("\n".join(lines) + "\n")


func _report(genes: Dictionary) -> void:
    var bot := BeloteBotZinzin.new()
    bot.genes = genes
    var lines := ["# Ce que Zinzin a appris", "",
            "Écrit par `tools/train.gd` le %s." % Time.get_datetime_string_from_system(false, true), "",
            "## Résultats (points d'avance par donne, donnes dupliquées)", ""]
    for level in ["facile", "difficile"]:
        var result := BotArena.match_up(bot, BeloteBots.make(level), 1000, 900000)
        lines.append("- contre %s : %+.1f ± %.1f" % [BeloteBots.NAMES[level], result.mean, 2 * result.stderr])
    lines.append_array(["", "## Jeu de la carte : poids les plus forts", "",
            "Un poids positif pousse à jouer la carte qui a ce trait, un négatif à l'éviter.", ""])
    var play: Array = BeloteBotZinzin.PLAY_FEATURES.duplicate()
    play.sort_custom(func(a: String, b: String) -> bool: return absf(genes[a]) > absf(genes[b]))
    for name in play:
        lines.append("- `%s` : %+.2f" % [name, genes[name]])
    lines.append_array(["", "## Enchères", ""])
    for name in BeloteBotZinzin.BID_FEATURES:
        lines.append("- `%s` : %.1f" % [name, genes[name]])
    var file := FileAccess.open("res://docs/zinzin.md", FileAccess.WRITE)
    file.store_string("\n".join(lines) + "\n")
    _log("report written to docs/zinzin.md")


func _log(text: String) -> void:
    print("[%5.0f s] %s" % [(Time.get_ticks_msec() - _started) / 1000.0, text])
