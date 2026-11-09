shader_type canvas_item;
// The Hi-Fi's "retro LCD" look: a small passive LCD of the early 2000s. Colours pulled toward grey, the blacks lifted
// to a dark slate, a cool green-grey cast, a faint pixel grid and a little haze.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float wash : hint_range(0.0, 1.0) = 0.32;
uniform float contrast : hint_range(0.3, 1.2) = 0.80;
uniform float lift : hint_range(0.0, 0.3) = 0.075;
uniform vec3 cast = vec3(0.86, 0.96, 0.93);
uniform float grid : hint_range(0.0, 0.4) = 0.10;
uniform float haze : hint_range(0.0, 0.2) = 0.035;

void fragment() {
	vec3 c = texture(screen_texture, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), wash);
	c = (c - 0.5) * contrast + 0.5 + lift;
	c *= cast;
	vec2 p = FRAGCOORD.xy;
	float row = step(0.5, fract(p.y * 0.5));
	float col = step(0.66, fract(p.x / 3.0));
	c *= 1.0 - grid * row - grid * 0.5 * col;
	c += haze;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
