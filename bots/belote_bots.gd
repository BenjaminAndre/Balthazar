class_name BeloteBots
## The bot levels (GDD §5). « pimc » is a sampling search bot, used in the arena; it is
## not offered at the table (too slow on a phone for now).

const LEVELS := ["facile", "difficile", "zinzin"]
## Shown names. The ids stay as they were (saved profiles, training): the
## rule-based "difficile" is shown as « Moyen », the trained "zinzin" as « Difficile ».
const NAMES := {"facile": "Facile", "difficile": "Moyen", "zinzin": "Difficile"}


static func make(level: String) -> BeloteBot:
    match level:
        "difficile":
            return BeloteBotDifficile.new()
        "zinzin":
            return BeloteBotZinzin.load_trained()
        "pimc":
            return BeloteBotPimc.new()
    return BeloteBot.new()
