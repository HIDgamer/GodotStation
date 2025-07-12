shader_type canvas_item;

uniform vec4 hair_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float dark_factor : hint_range(0.05, 0.5) = 0.3; // How dark the darkest parts should be
uniform float brightness : hint_range(0.5, 2.0) = 1.3; // Overall brightness adjustment

void fragment() {
	vec4 texture_color = texture(TEXTURE, UV);
	
	// Skip fully transparent pixels
	if (texture_color.a <= 0.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
	}
	
	// Calculate grayscale value (luminance)
	float gray = dot(texture_color.rgb, vec3(0.299, 0.587, 0.114));
	
	// Apply brightness boost
	gray = clamp(gray * brightness, 0.0, 1.0);
	
	// Remap grayscale value from [0, 1] to [dark_factor, 1]
	// This ensures even completely black pixels (gray = 0) get some color
	float remapped_gray = dark_factor + gray * (1.0 - dark_factor);
	
	// Apply the hair color with the remapped grayscale
	vec3 new_color = hair_color.rgb * remapped_gray;
	
	// Preserve the original alpha
	COLOR = vec4(new_color, texture_color.a);
}