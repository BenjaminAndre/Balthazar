extends Control
## Home screen: a game against 3 bots for now.


func _ready() -> void:
    theme = TableTheme.make()
    var felt := $Felt as ColorRect
    var mat := ShaderMaterial.new()
    mat.shader = preload("res://ui/felt.gdshader")
    felt.material = mat
    resized.connect(func() -> void: mat.set_shader_parameter("size", size))
    var version: String = ProjectSettings.get_setting("application/config/version")
    $Title.text = "Balthazar  v%s" % version
    var play := Button.new()
    play.text = "Belote contre 3 bots"
    play.custom_minimum_size = Vector2(360, 80)
    play.pressed.connect(func() -> void: Session.open_table(Callable()))
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
