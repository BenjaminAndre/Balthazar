extends Control
## Paramètres: the table settings of the profile (TableSettings). A solo game uses
## them as they are; an online table starts from the host's, which the host can
## still change in the lobby.

var _panel: PanelContainer


func _ready() -> void:
    theme = TableTheme.make()
    var felt := ColorRect.new()
    var mat := ShaderMaterial.new()
    mat.shader = preload("res://ui/felt.gdshader")
    felt.material = mat
    felt.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(felt)
    _panel = PanelContainer.new()
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 14)
    _panel.add_child(column)
    var title := Label.new()
    title.text = "Paramètres"
    title.add_theme_font_size_override("font_size", 34)
    title.add_theme_color_override("font_color", TableTheme.INK)
    column.add_child(title)
    var form := SettingsForm.new(TableSettings.load_profile())
    form.setting_changed.connect(func(_group: String, _key: String, _value: Variant) -> void:
        TableSettings.save_profile(form.settings))
    column.add_child(form)
    var back := Button.new()
    back.text = "Retour"
    back.custom_minimum_size = Vector2(200, 60)
    back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    back.pressed.connect(_back)
    column.add_child(back)
    add_child(_panel)
    resized.connect(func() -> void:
        mat.set_shader_parameter("size", size)
        _center())
    _center.call_deferred()


func _center() -> void:
    _panel.position = (size - _panel.get_combined_minimum_size()) / 2


func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_GO_BACK_REQUEST:
        _back()


func _back() -> void:
    get_tree().change_scene_to_file("res://ui/main.tscn")
