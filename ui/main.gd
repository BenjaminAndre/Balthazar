extends Control
## Placeholder home screen until the table UI lands (GDD, slice 5).


func _ready() -> void:
    var version: String = ProjectSettings.get_setting("application/config/version")
    $Title.text = "Balthazar  v%s" % version
