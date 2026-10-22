extends Control
## An online table before the game (GDD §2): the code to share, the four seats,
## and for the host the button that starts the game.

var _panel: PanelContainer
## Screenshots and tests show a lobby without Tube: {state, code, info, my_seat}.
var preview: Dictionary = {}


func _ready() -> void:
    theme = TableTheme.make()
    var felt := ColorRect.new()
    var mat := ShaderMaterial.new()
    mat.shader = preload("res://ui/felt.gdshader")
    felt.material = mat
    felt.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(felt)
    resized.connect(func() -> void:
        mat.set_shader_parameter("size", size)
        _center())
    Online.changed.connect(_refresh)
    Online.link.started.connect(_on_started)
    _refresh()


func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_GO_BACK_REQUEST:
        _leave()


func _refresh() -> void:
    if _panel:
        _panel.queue_free()
    var online_state: int = preview.get("state", Online.state)
    var code: String = preview.get("code", Online.code)
    var info: Dictionary = preview.get("info", Online.link.info)
    var my_seat: int = preview.get("my_seat", Online.link.my_seat)
    var hosting := online_state == Online.State.HOSTING
    _panel = PanelContainer.new()
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 12)
    _panel.add_child(column)
    match online_state:
        Online.State.CREATING:
            column.add_child(_label("Création de la table…", 30))
        Online.State.JOINING:
            column.add_child(_label("Connexion à la table %s…" % code, 30))
        Online.State.HOSTING, Online.State.JOINED:
            var row := HBoxContainer.new()
            row.add_theme_constant_override("separation", 16)
            row.add_child(_label("Table", 30))
            row.add_child(_label(code, 44, TableTheme.RED))
            var copy := Button.new()
            copy.text = "Copier le code"
            copy.add_theme_font_size_override("font_size", 20)
            copy.pressed.connect(func() -> void: DisplayServer.clipboard_set(code))
            row.add_child(copy)
            column.add_child(row)
            column.add_child(_label("Donnez ce code à vos amis : ils le saisissent dans « Rejoindre ».",
                    18, TableTheme.INK.lightened(0.3)))
        _:
            column.add_child(_label("Hors ligne", 30))
    if Online.error != "" and preview.is_empty():
        column.add_child(_label(Online.error, 20, TableTheme.RED))
    var seats: Array = info.get("seats", [])
    if not seats.is_empty():
        column.add_child(HSeparator.new())
        var grid := GridContainer.new()
        grid.columns = 2
        grid.add_theme_constant_override("h_separation", 32)
        grid.add_theme_constant_override("v_separation", 8)
        for seat in [0, 2, 1, 3]:
            var entry: Dictionary = seats[seat]
            grid.add_child(_label("Équipe %d" % (seat % 2 + 1), 20, TableTheme.INK.lightened(0.35)))
            var text: String = entry.name if entry.human else "Bot"
            if seat == 0:
                text += " (hôte)"
            if seat == my_seat:
                text += " · vous"
            if entry.human and not entry.here:
                text += " · absent, un bot joue"
            grid.add_child(_label(text, 24, TableTheme.INK if entry.human else TableTheme.INK.lightened(0.45)))
        column.add_child(grid)
        column.add_child(_label("Les partenaires sont dans la même équipe. Les places libres sont tenues par des bots.",
                16, TableTheme.INK.lightened(0.35)))
    var buttons := HBoxContainer.new()
    buttons.alignment = BoxContainer.ALIGNMENT_CENTER
    buttons.add_theme_constant_override("separation", 16)
    if hosting:
        var start := Button.new()
        start.text = "Lancer la partie"
        start.pressed.connect(func() -> void: Online.link.start_game())
        buttons.add_child(start)
    elif online_state == Online.State.JOINED:
        buttons.add_child(_label("L'hôte lance la partie…", 22))
    var quit := Button.new()
    quit.text = "Quitter"
    quit.pressed.connect(_leave)
    buttons.add_child(quit)
    column.add_child(buttons)
    add_child(_panel)
    _center.call_deferred()


func _center() -> void:
    if is_instance_valid(_panel):
        _panel.position = (size - _panel.get_combined_minimum_size()) / 2


func _label(text: String, font_size: int, color := TableTheme.INK) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    return label


func _on_started() -> void:
    Session.open_table(func(table: Node) -> void: Online.attach_table(table))


func _leave() -> void:
    Online.leave()
    get_tree().change_scene_to_file("res://ui/main.tscn")
