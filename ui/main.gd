extends Control
## Home screen: play against bots, open an online table, or join one by code.

var _name: LineEdit
var _code: LineEdit
var _message: Label
var _column: VBoxContainer


func _ready() -> void:
    theme = TableTheme.make()
    var felt := ColorRect.new()
    var mat := ShaderMaterial.new()
    mat.shader = preload("res://ui/felt.gdshader")
    felt.material = mat
    felt.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(felt)
    _column = VBoxContainer.new()
    _column.add_theme_constant_override("separation", 14)
    _column.alignment = BoxContainer.ALIGNMENT_CENTER
    add_child(_column)
    var version: String = ProjectSettings.get_setting("application/config/version")
    var title := _label("Balthazar", 56, Color.WHITE)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _column.add_child(title)
    var subtitle := _label("v%s" % version, 18, Color(1, 1, 1, 0.6))
    subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _column.add_child(subtitle)
    var sides := HBoxContainer.new()
    sides.add_theme_constant_override("separation", 48)
    _column.add_child(sides)
    # Left: against bots, one button per game.
    var solo := VBoxContainer.new()
    solo.add_theme_constant_override("separation", 12)
    sides.add_child(solo)
    solo.add_child(_heading("Contre des bots"))
    var games := GridContainer.new()
    games.columns = 2
    games.add_theme_constant_override("h_separation", 12)
    games.add_theme_constant_override("v_separation", 12)
    for info in GameCatalog.GAMES:
        var button := _button(info.name, func() -> void: Session.open_game(info.id))
        button.custom_minimum_size = Vector2(220, 64)
        games.add_child(button)
    solo.add_child(games)
    solo.add_child(LevelPicker.new())
    var tarot_note := _label("Au Tarot, les bots sont tous « Facile » pour l'instant.", 16, Color(1, 1, 1, 0.7))
    solo.add_child(tarot_note)
    # Right: with friends.
    var friends := VBoxContainer.new()
    friends.add_theme_constant_override("separation", 12)
    sides.add_child(friends)
    friends.add_child(_heading("Entre amis"))
    _name = _field("Votre pseudo", Session.player_name, 360)
    _name.text_changed.connect(func(text: String) -> void: Session.player_name = text)
    friends.add_child(_name)
    friends.add_child(_button("Créer une table", _host))
    var join := HBoxContainer.new()
    join.add_theme_constant_override("separation", 12)
    _code = _field("Code", "", 200)
    _code.text_changed.connect(func(text: String) -> void:
        var column := _code.caret_column
        _code.text = text.to_upper()
        _code.caret_column = column)
    _code.text_submitted.connect(func(_text: String) -> void: _join())
    join.add_child(_code)
    var join_button := _button("Rejoindre", _join)
    join_button.custom_minimum_size.x = 148
    join.add_child(join_button)
    friends.add_child(join)
    friends.add_child(_button("Paramètres", func() -> void: get_tree().change_scene_to_file("res://ui/settings.tscn")))
    _message = _label(Online.error, 20, Color(1, 0.75, 0.6))
    _message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _message.autowrap_mode = TextServer.AUTOWRAP_WORD
    _message.custom_minimum_size.x = 360
    _column.add_child(_message)
    resized.connect(func() -> void:
        mat.set_shader_parameter("size", size)
        _layout())
    _layout.call_deferred()


func _layout() -> void:
    var wanted := _column.get_combined_minimum_size()
    _column.size = wanted
    _column.position = (size - wanted) / 2


func _host() -> void:
    if _needs_name():
        return
    Online.host_table(Session.player_name)
    get_tree().change_scene_to_file("res://ui/lobby.tscn")


func _join() -> void:
    if _needs_name():
        return
    if _code.text.strip_edges().is_empty():
        _message.text = "Saisissez le code que l'hôte vous a donné."
        return
    Online.join_table(_code.text, Session.player_name)
    get_tree().change_scene_to_file("res://ui/lobby.tscn")


func _needs_name() -> bool:
    if Session.player_name.is_empty():
        _message.text = "Choisissez d'abord un pseudo."
        _name.grab_focus()
        return true
    return false


func _field(placeholder: String, text: String, width: float) -> LineEdit:
    var field := LineEdit.new()
    field.placeholder_text = placeholder
    field.text = text
    field.custom_minimum_size = Vector2(width, 60)
    field.add_theme_font_size_override("font_size", 24)
    field.alignment = HORIZONTAL_ALIGNMENT_CENTER
    return field


func _button(text: String, action: Callable) -> Button:
    var button := Button.new()
    button.text = text
    button.custom_minimum_size = Vector2(360, 68)
    button.pressed.connect(action)
    return button


func _label(text: String, font_size: int, color: Color) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    return label


## Android back on the home screen quits (the project turns off quit_on_go_back for the table).
func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_GO_BACK_REQUEST:
        get_tree().quit()


func _heading(text: String) -> Label:
    var label := _label(text, 26, Color(1, 0.84, 0.35))
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    return label
