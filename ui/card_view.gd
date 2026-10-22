class_name CardView
extends Control
## One card, face up or (card = -1) face down, drawn in code.

signal pressed(card: int)

const RANKS := ["7", "8", "9", "10", "V", "D", "R", "A"]

var card := -1
## Greyed out: not playable now.
var dimmed := false


func _init(card_value := -1, card_size := Vector2(90, 130)) -> void:
    card = card_value
    size = card_size
    custom_minimum_size = card_size
    mouse_filter = Control.MOUSE_FILTER_IGNORE


func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        pressed.emit(card)
        accept_event()


func _draw() -> void:
    var box := StyleBoxFlat.new()
    box.set_corner_radius_all(int(size.x * 0.09))
    box.set_border_width_all(2)
    box.border_color = Color(0.25, 0.25, 0.3)
    box.bg_color = Color(0.98, 0.97, 0.93) if card >= 0 else Color(0.16, 0.24, 0.55)
    draw_style_box(box, Rect2(Vector2.ZERO, size))
    if card < 0:
        var inner := Rect2(size * 0.12, size * 0.76)
        draw_rect(inner, Color(0.85, 0.75, 0.4), false, 2.0)
        draw_line(inner.position, inner.end, Color(0.85, 0.75, 0.4, 0.6), 2.0)
        draw_line(Vector2(inner.end.x, inner.position.y), Vector2(inner.position.x, inner.end.y),
                Color(0.85, 0.75, 0.4, 0.6), 2.0)
        return
    var suit := Cards.suit_of(card)
    var color := SuitIcon.color_of(suit)
    var font := get_theme_default_font()
    var font_size := int(size.y * 0.2)
    draw_string(font, Vector2(size.x * 0.08, size.y * 0.04 + font_size), RANKS[Cards.rank_of(card)],
            HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
    SuitIcon.paint(self, suit, Vector2(size.x * 0.21, size.y * 0.4), size.x * 0.2)
    SuitIcon.paint(self, suit, Vector2(size.x * 0.6, size.y * 0.68), size.x * 0.46)
    if dimmed:
        var shade := StyleBoxFlat.new()
        shade.set_corner_radius_all(int(size.x * 0.09))
        shade.bg_color = Color(0, 0, 0, 0.4)
        draw_style_box(shade, Rect2(Vector2.ZERO, size))
