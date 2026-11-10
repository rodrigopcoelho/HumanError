shader_type canvas_item;
// Applied to photographs (portraits, wallpapers) so they read as corrupted memories.

uniform float intensity : hint_range(0.0, 1.0) = 0.25;
uniform float invert : hint_range(0.0, 1.0) = 0.0;
uniform float darken : hint_range(0.0, 1.0) = 0.0;
uniform float motion : hint_range(0.0, 1.0) = 1.0; // 0 freezes the effect (reduced distortion)
uniform vec4 tint : source_color = vec4(0.60, 0.75, 0.60, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float t = floor(TIME * 1.5 * motion);
	float row = floor(uv.y * 40.0);
	float sel = step(1.0 - 0.18 * intensity, hash(vec2(row, t)));
	uv.x += (hash(vec2(row, t + 3.0)) - 0.5) * 0.12 * intensity * sel;
	vec2 blk = floor(uv * vec2(14.0, 18.0));
	float bsel = step(1.0 - 0.05 * intensity, hash(blk + t * 0.37));
	uv += (vec2(hash(blk), hash(blk + 7.0)) - 0.5) * 0.08 * bsel;
	float sp = 0.004 + 0.012 * intensity;
	vec3 col;
	col.r = texture(TEXTURE, uv + vec2(sp, 0.0)).r;
	col.g = texture(TEXTURE, uv).g;
	col.b = texture(TEXTURE, uv - vec2(sp, 0.0)).b;
	float lum = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(lum) * tint.rgb * 1.5, 0.55);
	col = mix(col, 1.0 - col, invert);
	col *= 1.0 - 0.10 * sin(UV.y * 500.0);
	col *= 1.0 - darken;
	COLOR = vec4(col, texture(TEXTURE, UV).a);
}
