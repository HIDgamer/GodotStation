shader_type canvas_item;
render_mode blend_add, light_only;

uniform float softness : hint_range(0.0, 1.0) = 0.5;
uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform vec4 color_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	// Sample the light texture (if any)
	vec4 tex = texture(TEXTURE, UV);

	// Calculate distance from center for soft edge
	float dist = distance(UV, vec2(0.5));
	float fade = smoothstep(1.0 - softness, 1.0, dist);

	// Apply tint, fade, and intensity
	vec4 final_color = tex * color_tint * intensity;
	final_color.a *= (1.0 - fade);

	COLOR = final_color;
}
