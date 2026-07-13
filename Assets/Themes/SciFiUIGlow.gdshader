shader_type canvas_item;

// SciFi UI Glow Shader - Adds subtle glow effect to UI elements
// Use on CanvasLayer or Panel for enhanced sci-fi appearance

uniform float glow_strength: hint_range(0.0, 2.0) = 0.8;
uniform float glow_speed: hint_range(0.1, 5.0) = 2.0;
uniform vec3 glow_color: hint_color = vec3(0.2, 1.0, 1.0);

void fragment() {
	vec4 base_color = texture(TEXTURE, UV);
	
	// Create pulsing glow effect
	float glow = 0.5 + 0.5 * sin(TIME * glow_speed);
	
	// Apply glow to edges
	float edge_glow = (1.0 - length(UV - 0.5) * 2.0);
	edge_glow = smoothstep(0.3, 0.8, edge_glow);
	
	// Combine effects
	vec3 final_color = base_color.rgb + (glow_color * edge_glow * glow * glow_strength);
	
	COLOR = vec4(final_color, base_color.a);
}
