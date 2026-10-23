class_name TableSettings
## A table's settings (GDD §7): general ones, then one group per game. They live
## in the player's profile (load_profile), are used as they are for a solo
## game, and are brought into an online lobby by the host, who can change them
## there before starting. Settings are plain Dictionaries, easy to save and to send.

## Every setting with its default value.
const DEFAULTS := {
    "general": {"auto_finish": true},
    "belote": {"announces": true, "relance_12": false},
}

## What the screens show: [group, key, label, hint].
const SCHEMA := [
    ["general", "auto_finish", "Fin automatique",
            "Quand la suite de la donne est gagnée d'avance, vos cartes se jouent toutes seules."],
    ["belote", "announces", "Annonces", "Tierces, cinquantes, cents et carrés."],
    ["belote", "relance_12", "Relance à 12",
            "Avec 11 points ou moins en main, on peut demander à redistribuer."],
]

const GROUP_NAMES := {"general": "Général", "belote": "Belote"}


## `settings` completed with the defaults of anything missing (or of a new setting).
static func complete(settings: Dictionary) -> Dictionary:
    var out := DEFAULTS.duplicate(true)
    for group in settings:
        if out.has(group) and settings[group] is Dictionary:
            for key in settings[group]:
                if out[group].has(key):
                    out[group][key] = settings[group][key]
    return out


static func value(settings: Dictionary, group: String, key: String) -> Variant:
    return complete(settings)[group][key]


## The Belote rules these settings ask for.
static func belote_rules(settings: Dictionary) -> BeloteRules:
    var rules := BeloteRules.new()
    rules.announces_enabled = value(settings, "belote", "announces")
    rules.redeal_max_points = 11 if value(settings, "belote", "relance_12") else -1
    return rules


## The settings saved in the player's profile (Session), completed with the defaults.
static func load_profile() -> Dictionary:
    var saved: Variant = JSON.parse_string(str(Engine.get_main_loop().root.get_node("Session").get_raw("settings", "{}")))
    return complete(saved if saved is Dictionary else {})


static func save_profile(settings: Dictionary) -> void:
    Engine.get_main_loop().root.get_node("Session").set_raw("settings", JSON.stringify(complete(settings)))
