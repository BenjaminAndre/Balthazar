class_name LevelPicker
extends HBoxContainer
## « Bots : Facile / Difficile / Zinzin », remembered in the profile.

signal level_changed(level: String)


func _ready() -> void:
    add_theme_constant_override("separation", 8)
    alignment = BoxContainer.ALIGNMENT_CENTER
    var label := Label.new()
    label.text = "Bots :"
    label.add_theme_font_size_override("font_size", 22)
    label.add_theme_color_override("font_color", Color.WHITE)
    add_child(label)
    var group := ButtonGroup.new()
    for level in BeloteBots.LEVELS:
        var button := Button.new()
        button.text = BeloteBots.NAMES[level]
        button.toggle_mode = true
        button.button_group = group
        button.button_pressed = level == Session.bot_level
        button.add_theme_font_size_override("font_size", 20)
        button.add_theme_color_override("font_pressed_color", TableTheme.GREEN)
        button.custom_minimum_size = Vector2(110, 48)
        button.toggled.connect(func(on: bool) -> void:
            if on:
                Session.bot_level = level
                level_changed.emit(level))
        add_child(button)
