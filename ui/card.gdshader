shader_type canvas_item;
// Shared by every CardView: a light from the top (slightly brighter top edge),
// and a glossy sheen that sweeps across the screen now and then, in screen
// space, so all cards catch the same light. The shadow drawn outside the card
// rectangle is left alone.

uniform vec2 card_size = vec2(126.0, 180.0);
uniform float sheen_strength = 0.16;

varying vec2 local;
varying vec2 world;

void vertex() {
	local = VERTEX;
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 c = COLOR;
	bool inside = local.x >= 0.0 && local.y >= 0.0 && local.x <= card_size.x && local.y <= card_size.y;
	if (inside) {
		float t = clamp(local.y / card_size.y, 0.0, 1.0);
		c.rgb *= 1.05 - 0.1 * t;
		// One sweep every ~7 s, from left to right across the table.
		float sweep = fract(TIME / 7.0) * 3200.0 - 800.0;
		float d = world.x + world.y * 0.5 - sweep;
		float band = 1.0 - smoothstep(0.0, 70.0, abs(d));
		c.rgb += band * sheen_strength * c.a;
	}
	COLOR = c;
}
