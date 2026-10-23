shader_type canvas_item;
// Shared by every CardView: a light from the top, the top edge slightly brighter
// than the bottom. The shadow drawn outside the card rectangle is left alone.

uniform vec2 card_size = vec2(126.0, 180.0);

varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec4 c = COLOR;
	if (local.x >= 0.0 && local.y >= 0.0 && local.x <= card_size.x && local.y <= card_size.y) {
		c.rgb *= 1.05 - 0.1 * clamp(local.y / card_size.y, 0.0, 1.0);
	}
	COLOR = c;
}
