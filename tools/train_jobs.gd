class_name TrainJobs
## The work of tools/train.gd, shared by the trainer and its worker processes
## (tools/train_worker.gd). GDScript threads hardly speed this up (they contend
## on shared engine data), so the trainer runs separate processes instead.
## A job is a Dictionary:
## - {kind: "evaluate", genome, opponents, deals, anchor_weight, seed_base}
##   -> {fitness, anchor, weight};
## - {kind: "anchor", genome, deals, first_seed} -> {fitness, anchor, weight}, against Difficile only;
## - {kind: "check", genome, deals, first_seed} -> {mean, stderr, deals}.


static func run(job: Dictionary) -> Dictionary:
    match job.kind:
        "check":
            return BotArena.match_up(bot(job.genome), BeloteBotDifficile.new(), int(job.deals), int(job.first_seed))
        "anchor":
            var anchor := play(bot(job.genome), BeloteBotDifficile.new(), int(job.deals), int(job.first_seed))
            return {"fitness": anchor.lead + 20.0 * (anchor.wins - 0.5), "anchor": anchor.lead,
                    "weight": int(job.deals)}
    return evaluate(job.genome, job.opponents, int(job.deals), int(job.anchor_weight), int(job.seed_base))


## The genome against Difficile (anchor_weight times the deals, counting double)
## and against each opponent genome, on the same deals for every genome.
static func evaluate(genome: Dictionary, opponents: Array, deals: int, anchor_weight: int, seed_base: int) -> Dictionary:
    var anchor := play(bot(genome), BeloteBotDifficile.new(), deals * anchor_weight, seed_base)
    var lead := 0.0
    var wins := 0.0
    for k in opponents.size():
        var result := play(bot(genome), bot(opponents[k]), deals, seed_base + 500000 + k * deals)
        lead += result.lead
        wins += result.wins
    lead /= maxf(opponents.size(), 1)
    wins /= maxf(opponents.size(), 1)
    # Difficile counts double; the hands won count too, 20 points for winning them all.
    var fitness: float = (2.0 * anchor.lead + lead) / 3.0 + 20.0 * ((2.0 * anchor.wins + wins) / 3.0 - 0.5)
    return {"fitness": fitness, "anchor": anchor.lead, "weight": deals * anchor_weight}


## {lead: average lead per hand, wins: share of deals won} for bot A, which
## partners itself in seats 0 and 2; every deal is played twice, teams swapped.
static func play(a: BeloteBot, b: BeloteBot, deals: int, first_seed: int) -> Dictionary:
    var game := Belote.new()
    var lead := 0.0
    var won := 0.0
    for d in deals:
        var points := BotArena.duplicate_lead(game, a, b, first_seed + d)
        lead += points
        won += 1.0 if points > 0 else (0.5 if points == 0 else 0.0)
    return {"lead": lead / deals, "wins": won / deals}


static func bot(genome: Dictionary) -> BeloteBotZinzin:
    var zinzin := BeloteBotZinzin.new()
    zinzin.genes = genome
    return zinzin
