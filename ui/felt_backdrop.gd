class_name FeltBackdrop
extends ColorRect
## The table mat behind every screen. felt.gdshader is costly per pixel (layered
## noise), so it is rendered once per screen size, at half resolution (it is soft
## anyway), and then shown as a plain image. Plain green until it is ready.

const FELT := Color(0.08, 0.33, 0.19)

static var _cache: Dictionary = {}

var _texture: Texture2D


func _ready() -> void:
    color = FELT
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    resized.connect(_bake)
    _bake()


func _draw() -> void:
    if _texture:
        draw_texture_rect(_texture, Rect2(Vector2.ZERO, size), false)


func _bake() -> void:
    var full := Vector2i(size)
    if full.x < 16 or full.y < 16 or DisplayServer.get_name() == "headless":
        return
    if _cache.has(full):
        _texture = _cache[full]
        queue_redraw()
        return
    var viewport := SubViewport.new()
    viewport.size = full / 2
    viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
    var rect := ColorRect.new()
    rect.size = Vector2(viewport.size)
    var mat := ShaderMaterial.new()
    mat.shader = preload("res://ui/felt.gdshader")
    # The shader works in screen pixels: give it the full size, rendered at half.
    mat.set_shader_parameter("size", Vector2(full))
    rect.material = mat
    viewport.add_child(rect)
    add_child(viewport)
    # Low-processor mode only draws when the screen changes: draw for the bake.
    var low := OS.low_processor_usage_mode
    OS.low_processor_usage_mode = false
    await RenderingServer.frame_post_draw
    await RenderingServer.frame_post_draw
    OS.low_processor_usage_mode = low
    if not is_instance_valid(viewport):
        return
    var image := viewport.get_texture().get_image()
    viewport.queue_free()
    if image == null or image.is_empty():
        return  # headless (tests): plain green
    _cache[full] = ImageTexture.create_from_image(image)
    if Vector2i(size) == full:
        _texture = _cache[full]
        queue_redraw()
