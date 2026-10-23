class_name SettingsForm
extends VBoxContainer
## The table settings (TableSettings.SCHEMA) as a list of toggles, grouped by
## « Général » and each game. Editable on the Paramètres screen and for the
## lobby's host; read-only for the guests.

signal setting_changed(group: String, key: String, value: Variant)

var settings: Dictionary = {}
var editable := true
## Groups to show; empty shows them all.
var groups: Array = []


func _init(table_settings: Dictionary, can_edit := true, shown_groups: Array = []) -> void:
    settings = TableSettings.complete(table_settings)
    editable = can_edit
    groups = shown_groups


func _ready() -> void:
    add_theme_constant_override("separation", 8)
    var current := ""
    for entry in TableSettings.SCHEMA:
        var group: String = entry[0]
        if not groups.is_empty() and not groups.has(group):
            continue
        if group != current:
            current = group
            add_child(_label(TableSettings.GROUP_NAMES[group], 24, TableTheme.RED))
        add_child(_row(group, entry[1], entry[2], entry[3]))


func _row(group: String, key: String, title: String, hint: String) -> Control:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 16)
    var text := VBoxContainer.new()
    text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    text.add_child(_label(title, 22, TableTheme.INK))
    var detail := _label(hint, 16, TableTheme.INK.lightened(0.35))
    detail.autowrap_mode = TextServer.AUTOWRAP_WORD
    detail.custom_minimum_size.x = 420
    text.add_child(detail)
    row.add_child(text)
    var toggle := Button.new()
    toggle.toggle_mode = true
    toggle.button_pressed = settings[group][key]
    toggle.disabled = not editable
    toggle.custom_minimum_size = Vector2(130, 52)
    toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    toggle.add_theme_font_size_override("font_size", 20)
    toggle.add_theme_color_override("font_pressed_color", TableTheme.GREEN)
    toggle.text = "Activé" if toggle.button_pressed else "Désactivé"
    toggle.toggled.connect(func(on: bool) -> void:
        toggle.text = "Activé" if on else "Désactivé"
        settings[group][key] = on
        setting_changed.emit(group, key, on))
    row.add_child(toggle)
    return row


func _label(text: String, font_size: int, color: Color) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    return label
