shader_type canvas_item;
// The table mat: woven felt, a soft lamp drifting over it, a darker edge and a
// stitched oval around the play area. Procedural, so it stays sharp on any screen.

uniform vec4 felt : source_color = vec4(0.06, 0.32, 0.18, 1.0);
uniform vec4 stitch : source_color = vec4(0.85, 0.75, 0.45, 1.0);
uniform vec2 size = vec2(1600.0, 720.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 px = UV * size;
	// Large soft blotches plus a fine cross weave.
	float blotch = fbm(px * 0.006);
	float weave = noise(px * vec2(0.9, 0.25)) * 0.5 + noise(px * vec2(0.25, 0.9)) * 0.5;
	vec3 c = felt.rgb * (0.86 + 0.18 * blotch + 0.08 * weave);

	// A lamp above the table, swaying very slowly.
	vec2 q = (UV - 0.5) * vec2(size.x / size.y, 1.0);
	vec2 lamp = vec2(0.06 * sin(TIME * 0.15), -0.08 + 0.03 * cos(TIME * 0.11));
	float light = 1.0 - smoothstep(0.0, 1.1, length(q - lamp));
	c *= 0.55 + 0.6 * light;

	// Stitched oval around the play area.
	vec2 e = q / vec2(0.62, 0.36);
	float ring = abs(length(e) - 1.0);
	float angle = atan(e.y, e.x);
	float dash = step(0.5, fract(angle * 40.0));
	float line = (1.0 - smoothstep(0.0, 0.006, ring)) * dash;
	c = mix(c, stitch.rgb * (0.5 + 0.5 * light), line * 0.35);
	// A faint pressed groove next to the stitches.
	c *= 1.0 - 0.12 * (1.0 - smoothstep(0.0, 0.02, abs(length(e) - 1.04)));

	COLOR = vec4(c, 1.0);
}
