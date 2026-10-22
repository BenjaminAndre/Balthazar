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


## The player's name at online tables, kept between launches.
var player_name := "":
    get:
        if player_name == "":
            var config := ConfigFile.new()
            if config.load(PROFILE) == OK:
                player_name = config.get_value("profile", "name", "")
        return player_name
    set(value):
        player_name = value.strip_edges().left(16)
        var config := ConfigFile.new()
        config.set_value("profile", "name", player_name)
        config.save(PROFILE)

const PROFILE := "user://profile.cfg"
