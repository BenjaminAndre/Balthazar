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
