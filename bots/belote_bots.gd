class_name BeloteBots
## The bot levels (GDD §5). « pimc » is a sampling search bot, used in the arena;
## it is not offered at the table (too slow on a phone for now).

const LEVELS := ["facile", "moyen", "difficile", "zinzin"]
const NAMES := {"facile": "Facile", "moyen": "Moyen", "difficile": "Difficile", "zinzin": "Zinzin"}
## How far off « Moyen » judges its hands at the bidding (tuned in the arena: +4
## points per hand against Facile, about half of Difficile's lead).
const MOYEN_BID_NOISE := 7.0


static func make(level: String) -> BeloteBot:
    match level:
        "moyen":
            var moyen := BeloteBotDifficile.new()
            moyen.bid_noise = MOYEN_BID_NOISE
            return moyen
        "difficile":
            return BeloteBotDifficile.new()
        "zinzin":
            return BeloteBotZinzin.load_trained()
        "pimc":
            return BeloteBotPimc.new()
    return BeloteBot.new()
