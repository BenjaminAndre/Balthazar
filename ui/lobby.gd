extends Control
## An online table's lobby (GDD §2): first the friends gather with the code; then
## the host picks the game (Belote, Tarot à 3, 4 or 5), the bots and the
## settings, and starts. Everyone comes back here after a game.

var _panel: PanelContainer
## Screenshots and tests show a lobby without Tube: {state, code, info, my_seat, host}.
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
        _:
            column.add_child(_label("Hors ligne", 30))
    if Online.error != "" and preview.is_empty():
        column.add_child(_label(Online.error, 20, TableTheme.RED))
    if info.has("people"):
        column.add_child(HSeparator.new())
        var body := HBoxContainer.new()
        body.add_theme_constant_override("separation", 36)
        body.add_child(_people_and_game(info, hosting))
        var game_id: String = info.get("game", "belote")
        var form := SettingsForm.new(info.get("settings", {}), hosting,
                ["general", "belote"] if game_id == "belote" else ["general"])
        form.setting_changed.connect(func(group: String, key: String, value: Variant) -> void:
            Online.link.set_setting(group, key, value))
        body.add_child(form)
        column.add_child(body)
    column.add_child(_buttons(info, hosting, online_state))
    add_child(_panel)
    _center.call_deferred()


## Left side: who is here, the game, and the bots.
func _people_and_game(info: Dictionary, hosting: bool) -> Control:
    var left := VBoxContainer.new()
    left.add_theme_constant_override("separation", 10)
    var people: Array = info.people
    var game_id: String = info.get("game", "belote")
    var players: int = info.get("players", 4)
    left.add_child(_label("À la table (%d)" % people.size(), 22, TableTheme.INK))
    for i in people.size():
        var person: Dictionary = people[i]
        var text: String = person.name + (" (hôte)" if i == 0 else "")
        if not person.here:
            text += " · absent, un bot joue"
        left.add_child(_label(text, 22, TableTheme.INK.lightened(0.0 if person.here else 0.4)))
    left.add_child(_label("Jeu", 22, TableTheme.RED))
    if hosting:
        var games := GridContainer.new()
        games.columns = 2
        games.add_theme_constant_override("h_separation", 8)
        games.add_theme_constant_override("v_separation", 8)
        var group := ButtonGroup.new()
        for game in GameCatalog.GAMES:
            var button := Button.new()
            button.text = game.name
            button.toggle_mode = true
            button.button_group = group
            button.button_pressed = game.id == game_id
            button.custom_minimum_size = Vector2(170, 50)
            button.add_theme_font_size_override("font_size", 20)
            button.add_theme_color_override("font_pressed_color", TableTheme.GREEN)
            button.toggled.connect(func(on: bool) -> void:
                if on:
                    Online.link.set_game(game.id))
            games.add_child(button)
        left.add_child(games)
    else:
        left.add_child(_label(GameCatalog.info(game_id).name, 24, TableTheme.INK))
    var free := players - people.size()
    var hint := ""
    if free < 0:
        hint = "%d joueurs de trop pour ce jeu (%d places)." % [-free, players]
    elif game_id == "belote":
        hint = "Le premier arrivé après l'hôte est son partenaire. %s" % _bots_text(free)
    else:
        hint = _bots_text(free)
    var hint_label := _label(hint, 16, TableTheme.RED if free < 0 else TableTheme.INK.lightened(0.35))
    hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
    hint_label.custom_minimum_size.x = 380
    left.add_child(hint_label)
    if game_id == "belote":
        if hosting:
            var picker := LevelPicker.new()
            picker.level_changed.connect(func(level: String) -> void: Online.link.set_bot_level(level))
            var row := PanelContainer.new()
            var dark := StyleBoxFlat.new()
            dark.bg_color = Color(0.08, 0.3, 0.17)
            dark.set_corner_radius_all(10)
            dark.set_content_margin_all(8)
            row.add_theme_stylebox_override("panel", dark)
            row.add_child(picker)
            left.add_child(row)
        elif info.has("bots"):
            left.add_child(_label("Bots : %s" % BeloteBots.NAMES.get(info.bots, info.bots), 20))
    return left


func _bots_text(free: int) -> String:
    if free <= 0:
        return "Toutes les places sont prises."
    return "%d place%s libre%s : %s." % [free, "s" if free > 1 else "", "s" if free > 1 else "",
            "un bot la tient" if free == 1 else "des bots les tiennent"]


func _buttons(info: Dictionary, hosting: bool, online_state: int) -> Control:
    var buttons := HBoxContainer.new()
    buttons.alignment = BoxContainer.ALIGNMENT_CENTER
    buttons.add_theme_constant_override("separation", 16)
    if hosting:
        var start := Button.new()
        start.text = "Lancer la partie"
        start.disabled = not info.get("can_start", true)
        start.pressed.connect(func() -> void: Online.link.start_game())
        buttons.add_child(start)
    elif online_state == Online.State.JOINED:
        var waiting := "Une partie est en cours : l'hôte revient bientôt." if info.get("started", false) \
                else "L'hôte choisit le jeu et lance la partie…"
        buttons.add_child(_label(waiting, 22))
    var quit := Button.new()
    quit.text = "Quitter"
    quit.pressed.connect(_leave)
    buttons.add_child(quit)
    return buttons


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
    Session.open_game(Online.link.game_id, func(table: Node) -> void: Online.attach_table(table))


func _leave() -> void:
    Online.leave()
    get_tree().change_scene_to_file("res://ui/main.tscn")
