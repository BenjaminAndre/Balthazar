extends Node
## Autoload: carries what the next table screen should do across a scene change
## (solo game, host of an online table, or guest). Empty means a solo game.

## Called once with the table screen when it opens.
var table_setup := Callable()


## Opens the table screen, set up by `setup(table)`.
func open_table(setup: Callable) -> void:
    table_setup = setup
    get_tree().change_scene_to_file("res://ui/table.tscn")


## The pending setup, cleared so that it runs once.
func take_table_setup() -> Callable:
    var setup := table_setup
    table_setup = Callable()
    return setup
const PROFILE := "user://profile.cfg"

## The player's name at online tables, kept between launches.
var player_name: String:
    get:
        return _profile().get_value("profile", "name", "")
    set(value):
        _save("name", value.strip_edges().left(16))

## The bots' level (BeloteBots.LEVELS), kept between launches.
var bot_level: String:
    get:
        return _profile().get_value("profile", "bots", "difficile")
    set(value):
        _save("bots", value)

var _config: ConfigFile


func _profile() -> ConfigFile:
    if _config == null:
        _config = ConfigFile.new()
        _config.load(PROFILE)
    return _config


func _save(key: String, value: Variant) -> void:
    _profile().set_value("profile", key, value)
    _config.save(PROFILE)


## A raw value of the profile (TableSettings keeps its settings there as JSON).
func get_raw(key: String, default: Variant) -> Variant:
    return _profile().get_value("profile", key, default)


func set_raw(key: String, value: Variant) -> void:
    _save(key, value)
