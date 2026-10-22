extends SceneTree
## Evolves « Zinzin » headless (GDD §5), and writes bots/zinzin_genome.gd and
## docs/zinzin.md:
##     godot --headless --path . -s res://tools/train.gd -- [generations] [deals per opponent]
##
## 50 genomes evolve. Each generation they all play the same deals against the
## same opponents, so that only their play makes the difference:
## - « Difficile », which never changes: the anchor. It is deterministic, so six
##   anchors are six times the deals, and it counts double in the fitness;
## - 4 genomes drawn from the previous generation's best, and the champion.
## A genome always partners itself (seats 0 and 2), and every deal is played twice
## with the teams swapped. The work runs in parallel worker processes.
##
## Against the luck of the cards:
## - a genome's results add up over the generations it survives, so a survivor's
##   score gets more and more precise and a lucky newcomer can't stay on top;
## - the 12 best are replayed on REFINE_DEALS more deals before choosing the elites;
## - mutation starts strong (exploration) and fades (convergence).
## One line per generation goes to stdout and train.log (project root, git-ignored):
## the leader's accumulated score and deals, the population's diversity, and every
## CHECK_EVERY generations the leader against Difficile on 1000 deals nobody trains on.

const EVOLVING := 50
const ANCHOR_WEIGHT := 6
const RIVALS := 4
const ELITE := 8
const REFINED := 12
const REFINE_DEALS := 250
const CHECK_EVERY := 5
const CHECK_DEALS := 1000
const LOG := "res://train.log"
## Worker processes: most of the cores, leaving a few for the rest of the PC.
const WORKERS := 16

var _rng := RandomNumberGenerator.new()
var _started := 0
## Per genome (by its JSON): {fitness, anchor, weight}, sums weighted by deals.
var _history: Dictionary = {}


func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    var generations := int(args[0]) if args.size() > 0 else 100
    var deals := int(args[1]) if args.size() > 1 else 32
    _rng.seed = 2026
    _started = Time.get_ticks_msec()
    _log("— entraînement : %d génomes, Difficile fixe (poids %d), %d générations, %d donnes par adversaire, %d processus" % [
            EVOLVING, ANCHOR_WEIGHT, generations, deals, WORKERS])
    var start := _complete(ZinzinGenome.GENES.duplicate())
    var population: Array = []
    for i in EVOLVING:
        # A fifth start near the current genome, the rest anywhere: discovery.
        population.append(_mutate(start, 1.0, 0.35) if i < EVOLVING / 5 else _random_genome())
    var rivals: Array = []
    for i in RIVALS:
        rivals.append(population[_rng.randi_range(0, EVOLVING - 1)])
    var champion: Dictionary = start
    var best_check := _check(start)
    _log("départ : génome actuel contre Difficile %+.1f ± %.1f (sur %d donnes)" % [
            best_check.mean, 2 * best_check.stderr, CHECK_DEALS])
    var best_mean: float = best_check.mean
    for generation in generations:
        var progress := float(generation) / maxf(generations - 1, 1)
        var opponents := rivals.duplicate()
        opponents.append(champion)
        var seed_base := 1000000 + generation * 10000
        var jobs := []
        for genome in population:
            jobs.append({"kind": "evaluate", "genome": genome, "opponents": opponents, "deals": deals,
                    "anchor_weight": ANCHOR_WEIGHT, "seed_base": seed_base})
        var results := _run_jobs(jobs)
        for i in EVOLVING:
            _record(population[i], results[i])
        # Replay the front runners on more deals before trusting their rank.
        var order := _ranked(population)
        jobs = []
        for k in REFINED:
            jobs.append({"kind": "anchor", "genome": population[order[k]], "deals": REFINE_DEALS,
                    "first_seed": seed_base + 7000})
        results = _run_jobs(jobs)
        for k in REFINED:
            _record(population[order[k]], results[k])
        order = _ranked(population)
        var leader: Dictionary = population[order[0]]
        var record: Dictionary = _history[_key(leader)]
        var line := "génération %3d · tête : %+5.1f contre Difficile sur %4d donnes cumulées · diversité %.2f · mutation %2.0f %% · %s" % [
                generation, record.anchor / record.weight, record.weight, _diversity(population),
                100.0 * lerpf(0.35, 0.05, progress), _summary(leader)]
        if generation % CHECK_EVERY == CHECK_EVERY - 1:
            var check := _check(leader)
            line += "\n           ↳ contrôle sur %d donnes inédites : %+.1f ± %.1f" % [CHECK_DEALS, check.mean, 2 * check.stderr]
            if check.mean > best_mean:
                best_mean = check.mean
                champion = leader.duplicate()
                _write_genome(champion)
                line += " · nouveau champion enregistré"
        _log(line)
        rivals.clear()
        for i in RIVALS:
            rivals.append(population[order[_rng.randi_range(0, ELITE - 1)]])
        population = _next_generation(population, order, progress)
    _report(champion)
    quit()


# --- Scores that add up -------------------------------------------------------------------

func _key(genome: Dictionary) -> String:
    return JSON.stringify(genome)


func _record(genome: Dictionary, result: Dictionary) -> void:
    var key := _key(genome)
    var w := float(result.weight)
    var record: Dictionary = _history.get(key, {"fitness": 0.0, "anchor": 0.0, "weight": 0.0})
    record.fitness += result.fitness * w
    record.anchor += result.anchor * w
    record.weight += w
    _history[key] = record


## Indices of the population, best accumulated fitness first.
func _ranked(population: Array) -> Array:
    var means := []
    for genome in population:
        var record: Dictionary = _history[_key(genome)]
        means.append(record.fitness / record.weight)
    var order := range(population.size())
    order.sort_custom(func(a: int, b: int) -> bool: return means[a] > means[b])
    return order


## Average spread of the genes across the population, in mutation steps.
func _diversity(population: Array) -> float:
    var total := 0.0
    var names := BeloteBotZinzin.gene_names()
    for name in names:
        var mean := 0.0
        for genome in population:
            mean += genome[name] / population.size()
        var variance := 0.0
        for genome in population:
            variance += pow(genome[name] - mean, 2) / population.size()
        total += sqrt(variance) / BeloteBotZinzin.GENES_INFO[name][2]
    return total / names.size()


# --- Worker processes ------------------------------------------------------------------------

## The genome against Difficile on CHECK_DEALS deals kept for checks only.
func _check(genome: Dictionary) -> Dictionary:
    var chunks := WORKERS
    var per := CHECK_DEALS / chunks
    var jobs := []
    for c in chunks:
        jobs.append({"kind": "check", "genome": genome, "deals": per, "first_seed": 90000000 + c * per})
    var results := _run_jobs(jobs)
    # Pool the chunks: mean of means, and the standard error of the whole.
    var mean := 0.0
    var variance := 0.0
    for r in results:
        mean += r.mean / chunks
    for r in results:
        variance += (r.stderr * r.stderr * per + (r.mean - mean) * (r.mean - mean)) / chunks
    return {"mean": mean, "stderr": sqrt(variance / (per * chunks))}


## Splits `jobs` among WORKERS godot processes and returns the results in order.
func _run_jobs(jobs: Array) -> Array:
    var dir := OS.get_user_data_dir().path_join("train")
    DirAccess.make_dir_recursive_absolute(dir)
    var slices := []
    for w in WORKERS:
        slices.append([])
    for i in jobs.size():
        slices[i % WORKERS].append(jobs[i])
    var running := []
    for w in WORKERS:
        if slices[w].is_empty():
            continue
        var input := dir.path_join("jobs_%d.json" % w)
        var output := dir.path_join("results_%d.json" % w)
        DirAccess.remove_absolute(output)
        var file := FileAccess.open(input, FileAccess.WRITE)
        file.store_string(JSON.stringify(slices[w]))
        file.close()
        var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path",
                ProjectSettings.globalize_path("res://"), "-s", "res://tools/train_worker.gd", "--", input, output])
        running.append([w, pid, output])
    var results := []
    results.resize(jobs.size())
    for entry in running:
        while OS.is_process_running(entry[1]):
            OS.delay_msec(50)
        var parsed: Array = JSON.parse_string(FileAccess.get_file_as_string(entry[2]))
        for k in parsed.size():
            results[entry[0] + k * WORKERS] = parsed[k]
    return results


# --- Selection and variation ----------------------------------------------------------------

## The elites stay as they are (their scores keep adding up); the others are
## children of tournament winners, mutated less and less as the run goes on.
func _next_generation(population: Array, order: Array, progress: float) -> Array:
    var next := []
    for k in ELITE:
        next.append(population[order[k]])
    var rate := lerpf(0.35, 0.05, progress)
    var strength := lerpf(0.6, 0.15, progress)
    while next.size() < EVOLVING:
        var mother: Dictionary = population[_tournament(order)]
        var father: Dictionary = population[_tournament(order)]
        var child := {}
        for name in BeloteBotZinzin.gene_names():
            child[name] = mother[name] if _rng.randf() < 0.5 else father[name]
        next.append(_mutate(child, strength, rate))
    return next


## The better of three random members (by rank).
func _tournament(order: Array) -> int:
    var best := EVOLVING
    for t in 3:
        best = mini(best, _rng.randi_range(0, EVOLVING - 1))
    return order[best]


func _mutate(genome: Dictionary, strength: float, rate: float) -> Dictionary:
    var out := genome.duplicate()
    for name in BeloteBotZinzin.gene_names():
        if _rng.randf() < rate:
            out[name] = _clamp(name, out[name] + _rng.randfn(0.0, BeloteBotZinzin.GENES_INFO[name][2] * strength))
    return out


func _random_genome() -> Dictionary:
    var genome := {}
    for name in BeloteBotZinzin.gene_names():
        var info: Array = BeloteBotZinzin.GENES_INFO[name]
        genome[name] = _clamp(name, info[1] + _rng.randfn(0.0, info[2] * 3.0))
    return genome


## Genes added since the genome was written start at their Difficile-like value.
func _complete(genome: Dictionary) -> Dictionary:
    for name in BeloteBotZinzin.gene_names():
        if not genome.has(name):
            genome[name] = BeloteBotZinzin.GENES_INFO[name][1]
    return genome


## Probabilities stay between 0 and 1; the rest is free.
func _clamp(name: String, value: float) -> float:
    return clampf(value, 0.0, 1.0) if name.begins_with("confiance") else value


func _summary(genome: Dictionary) -> String:
    return "prise %.0f/%.0f (audace %+.1f) · confiance partenaire %.2f · prendre le pli %.2f · atouts %.1f (marge %+.1f)" % [
            genome.seuil_tour1, genome.seuil_tour2, genome.audace_marque, genome.confiance_partenaire,
            genome.confiance_gain, genome.tirer_atouts, genome.marge_atouts]


# --- Output --------------------------------------------------------------------------------

func _write_genome(genes: Dictionary) -> void:
    var lines := ["class_name ZinzinGenome", "## The settings of « Zinzin » (BeloteBotZinzin), written by tools/train.gd.", "",
            "const GENES := {"]
    for name in BeloteBotZinzin.gene_names():
        lines.append("    \"%s\": %.4f," % [name, genes[name]])
    lines.append("}")
    var file := FileAccess.open("res://bots/zinzin_genome.gd", FileAccess.WRITE)
    file.store_string("\n".join(lines) + "\n")


func _report(genes: Dictionary) -> void:
    var lines := ["# Ce que Zinzin a appris", "",
            "Écrit par `tools/train.gd` le %s." % Time.get_datetime_string_from_system(false, true), "",
            "## Résultats", "", "Points d'avance par donne, sur des donnes dupliquées jamais vues :", ""]
    var against_difficile := _check(genes)
    lines.append("- contre Difficile : %+.1f ± %.1f (%d donnes)" % [against_difficile.mean,
            2 * against_difficile.stderr, CHECK_DEALS])
    var against_facile := BotArena.match_up(TrainJobs.bot(genes), BeloteBot.new(), 1000, 95000000)
    lines.append("- contre Facile : %+.1f ± %.1f (1000 donnes)" % [against_facile.mean, 2 * against_facile.stderr])
    lines.append_array(["", "## Ses réglages", "", "| Réglage | Valeur | Départ (façon Difficile) |", "|---|---|---|"])
    for name in BeloteBotZinzin.gene_names():
        var info: Array = BeloteBotZinzin.GENES_INFO[name]
        lines.append("| %s | %.2f | %.2f |" % [info[0], genes[name], info[1]])
    var file := FileAccess.open("res://docs/zinzin.md", FileAccess.WRITE)
    file.store_string("\n".join(lines) + "\n")
    _log("rapport écrit dans docs/zinzin.md")


func _log(text: String) -> void:
    var line := "[%5.0f s] %s" % [(Time.get_ticks_msec() - _started) / 1000.0, text]
    print(line)
    var file := FileAccess.open(LOG, FileAccess.READ_WRITE if FileAccess.file_exists(LOG) else FileAccess.WRITE)
    file.seek_end()
    file.store_line(line)
    file.close()
