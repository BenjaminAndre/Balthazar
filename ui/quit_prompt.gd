class_name QuitPrompt
extends Control
## Asks the player to confirm before leaving a game for the main menu, so a stray tap on
## the Quitter button cannot end it. The question covers the table with a dimmed layer,
## which takes every tap meanwhile. `confirmed` is emitted on "Quitter"; "Rester" just
## closes the question.

signal confirmed


func _init() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP
    var shade := ColorRect.new()
    shade.color = Color(0, 0, 0, 0.5)
    shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    shade.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(shade)
    var question := Label.new()
    question.text = "Quitter la partie en cours ?"
    question.add_theme_font_size_override("font_size", 28)
    question.add_theme_color_override("font_color", TableTheme.INK)
    var buttons := HBoxContainer.new()
    buttons.alignment = BoxContainer.ALIGNMENT_CENTER
    buttons.add_theme_constant_override("separation", 16)
    buttons.add_child(_button("Rester", queue_free))
    buttons.add_child(_button("Quitter", func() -> void: confirmed.emit()))
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 20)
    column.add_child(question)
    column.add_child(buttons)
    var panel := PanelContainer.new()
    panel.add_child(column)
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    center.add_child(panel)
    add_child(center)


func _button(text: String, action: Callable) -> Button:
    var button := Button.new()
    button.text = text
    button.custom_minimum_size = Vector2(170, 60)
    button.pressed.connect(action)
    return button
