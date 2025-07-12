shader_type canvas_item;

uniform float glow_strength : hint_range(0.0, 2.0) = 1.0;
uniform vec4 glow_color : source_color = vec4(0.3, 0.6, 1.0, 0.7);
uniform float outline_thickness : hint_range(0.0, 5.0) = 1.0;
uniform bool pulse_enabled = true;
uniform float pulse_speed : hint_range(0.1, 5.0) = 1.0;

void fragment() {
    vec4 original_color = texture(TEXTURE, UV);
    
    // Create outline effect
    float outline = 0.0;
    vec2 size = TEXTURE_PIXEL_SIZE * outline_thickness;
    
    for(float x = -outline_thickness; x <= outline_thickness; x++) {
        for(float y = -outline_thickness; y <= outline_thickness; y++) {
            vec2 offset = vec2(x, y) * size;
            outline += texture(TEXTURE, UV + offset).a;
        }
    }
    
    outline = min(outline, 1.0);
    
    // Pulsing effect
    float pulse = 1.0;
    if (pulse_enabled) {
        pulse = 0.5 + sin(TIME * pulse_speed * 3.14) * 0.5;
    }
    
    // Apply glow outside the original texture
    vec4 color = original_color;
    if (original_color.a < 0.01 && outline > 0.0) {
        color = glow_color;
        color.a = outline * glow_strength * pulse;
    }
    
    // Apply subtle glow on the texture itself
    if (original_color.a > 0.01) {
        // Blend in a bit of the glow color
        float strength = glow_strength * pulse * 0.3;
        color = mix(original_color, vec4(glow_color.rgb, original_color.a), strength);
    }
    
    COLOR = color;
}