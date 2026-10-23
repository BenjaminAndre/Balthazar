class_name GameCatalog
## The games offered (GDD §4): their id, name and number of players.

const GAMES := [
    {"id": "belote", "name": "Belote", "players": 4},
    {"id": "tarot3", "name": "Tarot à 3", "players": 3},
    {"id": "tarot4", "name": "Tarot à 4", "players": 4},
    {"id": "tarot5", "name": "Tarot à 5", "players": 5},
]


static func info(game_id: String) -> Dictionary:
    for game in GAMES:
        if game.id == game_id:
            return game
    return GAMES[0]
