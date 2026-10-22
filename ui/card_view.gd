class_name CardView
extends Control
## One card, face up or (card = -1) face down, drawn in code: a soft drop shadow,
## a lit paper face, and a shared shader for light and sheen (card.gdshader).

signal pressed(card: int)

const RANKS := ["7", "8", "9", "10", "V", "D", "R", "A"]
const PAPER := Color(0.99, 0.97, 0.92)
const EDGE := Color(0.55, 0.5, 0.42)
const BACK := Color(0.52, 0.08, 0.12)
const BACK_DARK := Color(0.36, 0.04, 0.08)
const GOLD := Color(0.9, 0.76, 0.4)

## One material per card size, so the shader knows the card's rectangle.
static var _materials: Dictionary = {}

var card := -1
## Greyed out: not playable now.
var dimmed := false
## Raised off the table (a playable card): a longer shadow.
var lifted := false:
    set(value):
        lifted = value
        queue_redraw()


func _init(card_value := -1, card_size := Vector2(90, 130)) -> void:
    card = card_value
    size = card_size
    custom_minimum_size = card_size
    pivot_offset = card_size / 2
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    material = _material_for(card_size)


static func _material_for(card_size: Vector2) -> ShaderMaterial:
    var key := Vector2i(card_size)
    if not _materials.has(key):
        var mat := ShaderMaterial.new()
        mat.shader = preload("res://ui/card.gdshader")
        mat.set_shader_parameter("card_size", card_size)
        _materials[key] = mat
    return _materials[key]


func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        pressed.emit(card)
        accept_event()


func _draw() -> void:
    var radius := int(size.x * 0.08)
    var rect := Rect2(Vector2.ZERO, size)
    # Two shadows, a wide faint one and a close darker one: reads as a card above cloth.
    var far := 10.0 if lifted else 5.0
    _rounded(rect.grow(2).grow_individual(0, 0, 0, 0), Color(0, 0, 0, 0.18), radius + 3, Vector2(far * 0.6, far))
    _rounded(rect, Color(0, 0, 0, 0.3), radius, Vector2(far * 0.25, far * 0.45))
    _rounded(rect, EDGE, radius, Vector2.ZERO)
    var face := rect.grow(-1.5)
    _rounded(face, PAPER, radius - 1, Vector2.ZERO)
    if card < 0:
        _draw_back(face, radius)
    else:
        _draw_face()
    if dimmed:
        _rounded(rect, Color(0.05, 0.08, 0.06, 0.45), radius, Vector2.ZERO)


func _rounded(rect: Rect2, color: Color, radius: int, offset: Vector2) -> void:
    var box := StyleBoxFlat.new()
    box.bg_color = color
    box.set_corner_radius_all(maxi(radius, 0))
    box.anti_aliasing = true
    draw_style_box(box, Rect2(rect.position + offset, rect.size))


## A classic French back: white margin, deep red panel, a gold diamond lattice
## and a medallion with a B.
func _draw_back(face: Rect2, radius: int) -> void:
    var panel := face.grow(-size.x * 0.07)
    _rounded(panel, BACK, maxi(radius - 3, 2), Vector2.ZERO)
    var step := panel.size.x / 5.0
    var half := step * 0.5
    var rows := int(panel.size.y / step) + 1
    for j in rows + 1:
        for i in 6:
            var c := panel.position + Vector2(i * step, j * step + fmod(panel.size.y, step) * 0.5)
            _diamond(c, half * 0.92, panel, BACK_DARK)
            _diamond(c, half * 0.35, panel, GOLD.darkened(0.25))
    draw_rect(panel.grow(-2), GOLD, false, 1.5)
    var center := panel.get_center()
    var r := panel.size.x * 0.27
    draw_circle(center, r, BACK)
    draw_arc(center, r, 0, TAU, 40, GOLD, 2.0, true)
    draw_arc(center, r * 0.8, 0, TAU, 40, GOLD.darkened(0.2), 1.0, true)
    var font := get_theme_default_font()
    var font_size := int(r * 1.3)
    var text_size := font.get_string_size("B", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
    draw_string(font, center + Vector2(-text_size.x / 2, font_size * 0.36), "B",
            HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, GOLD)


## A diamond clipped to `clip` (kept whole only when it fits, so edges stay clean).
func _diamond(c: Vector2, r: float, clip: Rect2, color: Color) -> void:
    var points := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
    for i in points.size():
        points[i] = points[i].clamp(clip.position + Vector2.ONE * 2, clip.end - Vector2.ONE * 2)
    draw_colored_polygon(points, color)


func _draw_face() -> void:
    var suit := Cards.suit_of(card)
    var rank := Cards.rank_of(card)
    var color := SuitIcon.color_of(suit)
    var font := get_theme_default_font()
    var font_size := int(size.y * 0.17)
    var corner := Vector2(size.x * 0.17, size.y * 0.05 + font_size)
    _corner(font, font_size, rank, suit, color, corner)
    # The same corner upside down, bottom right.
    draw_set_transform(size, PI, Vector2.ONE)
    _corner(font, font_size, rank, suit, color, corner)
    draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
    var middle := size / 2 + Vector2(0, size.y * 0.02)
    if rank == Cards.Rank.VALET or rank == Cards.Rank.DAME or rank == Cards.Rank.ROI:
        var frame := Rect2(size * Vector2(0.24, 0.2), size * Vector2(0.52, 0.6))
        _rounded(frame, Color(0.97, 0.92, 0.8), 4, Vector2.ZERO)
        draw_rect(frame, GOLD.darkened(0.3), false, 1.5)
        var big := int(size.y * 0.3)
        var letter: String = RANKS[rank]
        var ls := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, big)
        draw_string(font, frame.get_center() + Vector2(-ls.x / 2, -size.y * 0.02), letter,
                HORIZONTAL_ALIGNMENT_LEFT, -1, big, color)
        SuitIcon.paint(self, suit, frame.get_center() + Vector2(0, size.y * 0.17), size.x * 0.2)
    else:
        SuitIcon.paint(self, suit, middle, size.x * (0.5 if rank == Cards.Rank.AS else 0.38))


func _corner(font: Font, font_size: int, rank: int, suit: int, color: Color, at: Vector2) -> void:
    var text: String = RANKS[rank]
    var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
    draw_string(font, Vector2(at.x - w / 2, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
    SuitIcon.paint(self, suit, Vector2(at.x, at.y + size.y * 0.1), size.x * 0.16)
