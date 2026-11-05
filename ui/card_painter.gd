class_name CardPainter
extends Control
## Draws one card in code, once: its soft drop shadow, the lit paper face (with
## card.gdshader) and the face or the back. Only CardAtlas uses it, to bake every
## card of a deck into one texture; the table shows cards as CardView, which cut
## them out of that texture.

const RANKS := ["7", "8", "9", "10", "V", "D", "R", "A"]
const PAPER := Color(0.99, 0.97, 0.92)
const EDGE := Color(0.55, 0.5, 0.42)
const BACK := Color(0.52, 0.08, 0.12)
const BACK_DARK := Color(0.36, 0.04, 0.08)
const GOLD := Color(0.9, 0.76, 0.4)

var card := -1
## A Tarot card (TarotCards) instead of a 32-card one.
var tarot := false


func _init(card_value := -1, card_size := Vector2(90, 130), tarot_card := false) -> void:
    card = card_value
    tarot = tarot_card
    size = card_size
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    var mat := ShaderMaterial.new()
    mat.shader = preload("res://ui/card.gdshader")
    mat.set_shader_parameter("card_size", card_size)
    material = mat


func _draw() -> void:
    var radius := int(size.x * 0.08)
    var rect := Rect2(Vector2.ZERO, size)
    # Two shadows, a wide faint one and a close darker one: reads as a card above cloth.
    var far := 5.0 * size.y / 180.0
    _rounded(rect.grow(2), Color(0, 0, 0, 0.18), radius + 3, Vector2(far * 0.6, far))
    _rounded(rect, Color(0, 0, 0, 0.3), radius, Vector2(far * 0.25, far * 0.45))
    _rounded(rect, EDGE, radius, Vector2.ZERO)
    var face := rect.grow(-1.5)
    _rounded(face, PAPER, radius - 1, Vector2.ZERO)
    if card < 0:
        _draw_back(face, radius)
    elif tarot:
        _draw_tarot_face()
    else:
        _draw_face()



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
    _corner(font, font_size, RANKS[rank], suit, color, corner)
    # The same corner upside down, bottom right.
    draw_set_transform(size, PI, Vector2.ONE)
    _corner(font, font_size, RANKS[rank], suit, color, corner)
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


func _corner(font: Font, font_size: int, text: String, suit: int, color: Color, at: Vector2) -> void:
    var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
    draw_string(font, Vector2(at.x - w / 2, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
    if suit >= 0:
        SuitIcon.paint(self, suit, Vector2(at.x, at.y + size.y * 0.1), size.x * 0.16)


## A Tarot face: suit cards like the 32-card deck (with the Cavalier), numbered
## trumps on a blue panel, and the Excuse with its star.
func _draw_tarot_face() -> void:
    var font := get_theme_default_font()
    var font_size := int(size.y * 0.16)
    var corner := Vector2(size.x * 0.17, size.y * 0.05 + font_size)
    var middle := size / 2 + Vector2(0, size.y * 0.02)
    var ink := Color(0.12, 0.2, 0.45)
    if card == TarotCards.EXCUSE:
        _tarot_corners(font, font_size, "E", -1, ink, corner)
        _star(middle, size.x * 0.3, Color(0.85, 0.55, 0.1))
        var text := "Excuse"
        var small := int(size.y * 0.1)
        var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
        draw_string(font, Vector2(size.x / 2 - w / 2, size.y * 0.84), text, HORIZONTAL_ALIGNMENT_LEFT, -1, small, ink)
        return
    if TarotCards.is_trump(card):
        var number := str(TarotCards.trump_value(card))
        _tarot_corners(font, font_size, number, -1, ink, corner)
        var panel := Rect2(size * Vector2(0.22, 0.2), size * Vector2(0.56, 0.6))
        _rounded(panel, Color(0.82, 0.88, 0.98), 5, Vector2.ZERO)
        draw_rect(panel, ink.lightened(0.3), false, 1.5)
        var big := int(size.y * 0.32)
        var w := font.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
        draw_string(font, panel.get_center() + Vector2(-w / 2, big * 0.36), number,
                HORIZONTAL_ALIGNMENT_LEFT, -1, big, ink)
        if TarotCards.is_oudler(card):
            _star(panel.position + Vector2(panel.size.x / 2, size.y * 0.06), size.x * 0.07, GOLD.darkened(0.2))
        return
    var suit := TarotCards.suit_of(card)
    var rank := TarotCards.rank_of(card)
    var color := SuitIcon.color_of(suit)
    var label: String = TarotCards.RANK_LABELS[rank]
    _tarot_corners(font, font_size, label, suit, color, corner)
    if rank >= TarotCards.Rank.VALET:
        var frame := Rect2(size * Vector2(0.24, 0.2), size * Vector2(0.52, 0.6))
        _rounded(frame, Color(0.97, 0.92, 0.8), 4, Vector2.ZERO)
        draw_rect(frame, GOLD.darkened(0.3), false, 1.5)
        var big := int(size.y * 0.3)
        var ls := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, big)
        draw_string(font, frame.get_center() + Vector2(-ls.x / 2, -size.y * 0.02), label,
                HORIZONTAL_ALIGNMENT_LEFT, -1, big, color)
        SuitIcon.paint(self, suit, frame.get_center() + Vector2(0, size.y * 0.17), size.x * 0.2)
    else:
        SuitIcon.paint(self, suit, middle, size.x * 0.4)


func _tarot_corners(font: Font, font_size: int, text: String, suit: int, color: Color, corner: Vector2) -> void:
    _corner(font, font_size, text, suit, color, corner)
    draw_set_transform(size, PI, Vector2.ONE)
    _corner(font, font_size, text, suit, color, corner)
    draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


## A five-pointed star centred on `c`.
func _star(c: Vector2, r: float, color: Color) -> void:
    var points := PackedVector2Array()
    for i in 10:
        var angle := -PI / 2 + i * PI / 5
        var radius := r if i % 2 == 0 else r * 0.45
        points.append(c + Vector2(cos(angle), sin(angle)) * radius)
    draw_colored_polygon(points, color)
