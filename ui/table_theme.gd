class_name TableTheme
## The look shared by every screen: buttons and panels made of the same card
## paper as the deck, edged in gold, with a soft shadow on the felt.

const PAPER := Color(0.99, 0.97, 0.92)
const PAPER_DOWN := Color(0.9, 0.86, 0.76)
const INK := Color(0.2, 0.13, 0.08)
const GOLD := Color(0.78, 0.62, 0.3)
const RED := Color(0.7, 0.1, 0.12)
const GREEN := Color(0.12, 0.42, 0.22)


static func make() -> Theme:
    var theme := Theme.new()
    theme.default_font_size = 22
    theme.set_stylebox("normal", "Button", _box(PAPER, 4))
    theme.set_stylebox("hover", "Button", _box(PAPER.lightened(0.3), 5))
    theme.set_stylebox("pressed", "Button", _box(PAPER_DOWN, 1))
    theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
    theme.set_stylebox("disabled", "Button", _box(PAPER_DOWN.darkened(0.1), 0))
    for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
        theme.set_color(state, "Button", INK)
    theme.set_font_size("font_size", "Button", 26)
    theme.set_stylebox("panel", "PanelContainer", panel())
    theme.set_stylebox("normal", "LineEdit", _box(PAPER, 0))
    theme.set_color("font_color", "LineEdit", INK)
    theme.set_color("font_placeholder_color", "LineEdit", Color(INK, 0.45))
    theme.set_color("caret_color", "LineEdit", INK)
    return theme


static func panel() -> StyleBoxFlat:
    var box := _box(PAPER, 10)
    box.set_content_margin_all(26)
    box.set_corner_radius_all(16)
    return box


static func _box(color: Color, shadow: int) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = color
    box.border_color = GOLD
    box.set_border_width_all(2)
    box.set_corner_radius_all(12)
    box.set_content_margin_all(14)
    box.content_margin_left = 24
    box.content_margin_right = 24
    box.shadow_color = Color(0, 0, 0, 0.35)
    box.shadow_size = shadow
    box.shadow_offset = Vector2(0, shadow * 0.6)
    box.anti_aliasing = true
    return box
