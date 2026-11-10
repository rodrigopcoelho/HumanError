shader_type canvas_item;
// Full-screen CRT pass for the HVC TERMINAL look.
// No geometric warping is applied, so mouse positions always match what is drawn.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float distortion = 1.0;   // chromatic aberration + vignette (accessibility: 0 disables)
uniform float noise_amt = 1.0;    // film grain (accessibility: 0 disables)
uniform float flicker_amt = 1.0;  // gentle brightness wobble (accessibility: 0 disables)
uniform float scanline_amt = 1.0;
uniform float glitch = 0.0;       // transient, driven by story events
uniform float corruption = 0.0;   // slow baseline that rises with the in-game day

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME;
	float g = glitch * distortion;
	float band = step(0.55, hash(vec2(floor(uv.y * 22.0), floor(t * 12.0))));
	float tear = (hash(vec2(floor(uv.y * 46.0), floor(t * 18.0))) - 0.5) * 0.05 * g * band;
	float wob = sin(uv.y * 5.0 + t * 0.6) * 0.0007 * corruption * distortion;
	uv.x += tear + wob;
	vec2 c = uv - 0.5;
	float ab = (0.0010 + 0.004 * g + 0.0010 * corruption) * distortion * (0.35 + dot(c, c) * 3.0);
	vec3 col;
	col.r = texture(screen_tex, uv + vec2(ab, 0.0)).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - vec2(ab, 0.0)).b;
	float sl = 0.5 + 0.5 * sin(FRAGCOORD.y * 3.14159);
	col *= 1.0 - 0.09 * scanline_amt * sl;
	float n = hash(FRAGCOORD.xy + fract(t) * 91.7) - 0.5;
	col += n * 0.045 * noise_amt * (1.0 + corruption);
	// Low-amplitude, slow wobble only: never a strobe.
	col *= 1.0 - 0.012 * flicker_amt * (0.5 + 0.5 * sin(t * 5.0)) * (1.0 + corruption);
	float vig = 1.0 - dot(c, c) * 0.85 * distortion;
	col *= clamp(vig, 0.0, 1.0);
	col = mix(col, col * vec3(0.92, 1.0, 0.94), 0.5);
	COLOR = vec4(col, 1.0);
}
