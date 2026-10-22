class_name SuitIcon
extends Control
## A suit drawn with circles and polygons: the default font has no ♠♥♦♣ glyphs
## in exported builds (CLAUDE.md).

const RED := Color(0.8, 0.1, 0.12)
const BLACK := Color(0.08, 0.08, 0.1)

var suit := 0:
    set(value):
        suit = value
        queue_redraw()


func _draw() -> void:
    paint(self, suit, size / 2, minf(size.x, size.y) * 0.9)


static func color_of(suit_value: int) -> Color:
    return RED if suit_value == Cards.Suit.COEUR or suit_value == Cards.Suit.CARREAU else BLACK


## Draws `suit_value` on `ci`, centred on `c`, about `s` pixels tall.
static func paint(ci: CanvasItem, suit_value: int, c: Vector2, s: float) -> void:
    var color := color_of(suit_value)
    match suit_value:
        Cards.Suit.COEUR:
            var r := s * 0.27
            ci.draw_circle(c + Vector2(-r * 0.95, -r * 0.55), r, color)
            ci.draw_circle(c + Vector2(r * 0.95, -r * 0.55), r, color)
            ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 1.9, -r * 0.3),
                    c + Vector2(r * 1.9, -r * 0.3), c + Vector2(0, s * 0.5)]), color)
        Cards.Suit.CARREAU:
            ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.5),
                    c + Vector2(s * 0.37, 0), c + Vector2(0, s * 0.5), c + Vector2(-s * 0.37, 0)]), color)
        Cards.Suit.PIQUE:
            var r := s * 0.25
            ci.draw_circle(c + Vector2(-r * 0.95, r * 0.25), r, color)
            ci.draw_circle(c + Vector2(r * 0.95, r * 0.25), r, color)
            ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 1.9, r * 0.05),
                    c + Vector2(r * 1.9, r * 0.05), c + Vector2(0, -s * 0.5)]), color)
            ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, r * 0.2),
                    c + Vector2(-r * 0.75, s * 0.5), c + Vector2(r * 0.75, s * 0.5)]), color)
        Cards.Suit.TREFLE:
            var r := s * 0.2
            ci.draw_circle(c + Vector2(0, -s * 0.24), r, color)
            ci.draw_circle(c + Vector2(-s * 0.22, s * 0.04), r, color)
            ci.draw_circle(c + Vector2(s * 0.22, s * 0.04), r, color)
            ci.draw_circle(c + Vector2(0, -s * 0.04), r * 0.6, color)
            ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.05),
                    c + Vector2(-r * 0.8, s * 0.5), c + Vector2(r * 0.8, s * 0.5)]), color)
