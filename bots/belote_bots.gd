class_name BeloteBots
## The bot levels (GDD §5). « pimc » is the search bot Zinzin learns from; it is
## not offered at the table (too slow on a phone for now).

const LEVELS := ["facile", "difficile", "zinzin"]
const NAMES := {"facile": "Facile", "difficile": "Difficile", "zinzin": "Zinzin"}


static func make(level: String) -> BeloteBot:
    match level:
        "difficile":
            return BeloteBotDifficile.new()
        "zinzin":
            return BeloteBotZinzin.load_trained()
        "pimc":
            return BeloteBotPimc.new()
    return BeloteBot.new()
