extends Control
## Home screen: one way in for now, a game against 3 bots.


func _ready() -> void:
    var version: String = ProjectSettings.get_setting("application/config/version")
    $Title.text = "Balthazar  v%s" % version
    var play := Button.new()
    play.text = "Belote contre 3 bots"
    play.add_theme_font_size_override("font_size", 30)
    play.custom_minimum_size = Vector2(360, 80)
    play.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://ui/table.tscn"))
    add_child(play)
    play.anchor_left = 0.5
    play.anchor_right = 0.5
    play.anchor_top = 0.5
    play.anchor_bottom = 0.5
    play.offset_left = -180
    play.offset_right = 180
    play.offset_top = 70
    play.offset_bottom = 150


## Android back on the home screen quits (the project turns off quit_on_go_back for the table).
func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_GO_BACK_REQUEST:
        get_tree().quit()
