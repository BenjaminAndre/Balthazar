class_name CardView
extends Control
## One card on the table, face up or (card = -1) face down: a single quad cut
## from its deck's CardAtlas, so every card shares one texture and the table
## draws in a few batches. The shadow is part of the baked image.

signal pressed(card: int)

const GOLD := Color(0.9, 0.76, 0.4)

var card := -1
## A Tarot card (TarotCards) instead of a 32-card one.
var tarot := false
## Greyed out: not playable now.
var dimmed := false:
    set(value):
        dimmed = value
        self_modulate = Color(0.62, 0.62, 0.62) if dimmed else Color.WHITE
## Gold outline: the card winning the trick so far.
var highlighted := false
## Raised off the table (a playable card).
var lifted := false


func _init(card_value := -1, card_size := Vector2(90, 130)) -> void:
    card = card_value
    size = card_size
    custom_minimum_size = card_size
    pivot_offset = card_size / 2
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        pressed.emit(card)
        accept_event()


func _draw() -> void:
    var deck := "tarot" if tarot else "belote"
    var atlas := CardAtlas.texture(deck)
    if atlas == null:
        return
    # The baked cell holds the card plus room for its shadow: scale it all alike.
    var scale_factor := size / CardAtlas.CARD
    var rect := Rect2(-CardAtlas.PAD_START * scale_factor, CardAtlas.CELL * scale_factor)
    draw_texture_rect_region(atlas, rect, CardAtlas.region(deck, card))
    if highlighted:
        var glow := StyleBoxFlat.new()
        glow.draw_center = false
        glow.set_border_width_all(4)
        glow.border_color = GOLD.lightened(0.2)
        glow.set_corner_radius_all(int(size.x * 0.08) + 2)
        glow.shadow_color = Color(1, 0.85, 0.4, 0.5)
        glow.shadow_size = 8
        draw_style_box(glow, Rect2(Vector2.ZERO, size).grow(3))
