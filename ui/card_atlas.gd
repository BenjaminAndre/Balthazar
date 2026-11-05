class_name CardAtlas
## Every card of a deck (and its back) drawn once by CardPainter into one texture,
## shadow included. A card on screen (CardView) is then a single textured quad
## cut from that texture: all cards share it, so Godot draws them in a few
## batches instead of thousands of separate shapes (GDD §8).
## Decks: "belote" (32 cards) and "tarot" (78). The back is the last cell.

## The card as baked, before scaling: big enough for a phone's hand cards.
const CARD := Vector2(182, 260)
## Room around the card for its shadow (left/top, right/bottom).
const PAD_START := Vector2(4, 4)
const PAD_END := Vector2(14, 16)
const CELL := CARD + PAD_START + PAD_END
const COLUMNS := {"belote": 6, "tarot": 9}
const COUNTS := {"belote": 32, "tarot": 78}

static var _textures: Dictionary = {}


static func is_ready(deck: String) -> bool:
    return _textures.has(deck)


static func texture(deck: String) -> Texture2D:
    return _textures.get(deck)


## The texture region of `card` (-1: the back), shadow included.
static func region(deck: String, card: int) -> Rect2:
    var index: int = COUNTS[deck] if card < 0 else card
    var columns: int = COLUMNS[deck]
    return Rect2(Vector2(index % columns, index / columns) * CELL, CELL)


## Bakes the deck once (a few frames, rendered under `node`); later calls return at once.
static func ensure(deck: String, node: Node) -> void:
    if _textures.has(deck) or DisplayServer.get_name() == "headless":
        return
    var columns: int = COLUMNS[deck]
    var cells: int = COUNTS[deck] + 1
    var rows := ceili(float(cells) / columns)
    var viewport := SubViewport.new()
    viewport.size = Vector2i(Vector2(columns, rows) * CELL)
    viewport.transparent_bg = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
    for index in cells:
        var card := -1 if index == COUNTS[deck] else index
        var painter := CardPainter.new(card, CARD, deck == "tarot")
        painter.position = Vector2(index % columns, index / columns) * CELL + PAD_START
        viewport.add_child(painter)
    node.add_child(viewport)
    # Low-processor mode only draws when the screen changes: draw for the bake.
    var low := OS.low_processor_usage_mode
    OS.low_processor_usage_mode = false
    await RenderingServer.frame_post_draw
    await RenderingServer.frame_post_draw
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty():
        # Headless (tests): nothing was rendered; cards just stay blank.
        viewport.queue_free()
        OS.low_processor_usage_mode = low
        return
    # Mipmaps keep the small cards (opponents, announces) smooth when scaled down.
    image.generate_mipmaps()
    _textures[deck] = ImageTexture.create_from_image(image)
    viewport.queue_free()
    OS.low_processor_usage_mode = low
