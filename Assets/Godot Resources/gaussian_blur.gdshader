shader_type canvas_item;

uniform float blur_amount : hint_range(0.0, 5.0) = 0.8;
uniform float transition_blur : hint_range(0.0, 1.0) = 0.5;

// Helper function for gaussian weight
float gaussian(float x, float sigma) {
    return exp(-(x * x) / (2.0 * sigma * sigma)) / (sqrt(2.0 * 3.14159) * sigma);
}

void fragment() {
    if (blur_amount <= 0.0) {
        COLOR = texture(TEXTURE, UV);
    }

    // Get original pixel color
    vec4 original_color = texture(TEXTURE, UV);

    // Calculate blur based on amount (adaptive blur radius)
    float sigma = blur_amount * 0.5;
    int radius = int(sigma * 3.0);
    radius = max(1, min(radius, 15)); // Limit radius for performance

    vec4 blurred_color = vec4(0.0);
    float total_weight = 0.0;

    // Two-pass Gaussian blur (separable)
    // Horizontal pass
    for (int x = -radius; x <= radius; x++) {
        float weight = gaussian(float(x), sigma);
        vec2 offset = vec2(float(x) * TEXTURE_PIXEL_SIZE.x, 0.0);
        blurred_color += texture(TEXTURE, UV + offset) * weight;
        total_weight += weight;
    }
    blurred_color /= total_weight;

    // Vertical pass
    vec4 temp = blurred_color;
    blurred_color = vec4(0.0);
    total_weight = 0.0;

    for (int y = -radius; y <= radius; y++) {
        float weight = gaussian(float(y), sigma);
        vec2 offset = vec2(0.0, float(y) * TEXTURE_PIXEL_SIZE.y);
        blurred_color += texture(TEXTURE, UV + offset) * weight;
        total_weight += weight;
    }
    blurred_color /= total_weight;

    // Apply mild chromatic aberration for transition effect
    if (transition_blur > 0.0) {
        float aberration_amount = transition_blur * 0.02;
        vec2 direction = UV - vec2(0.5);

        vec4 r_color = texture(TEXTURE, UV + direction * aberration_amount);
        vec4 g_color = texture(TEXTURE, UV);
        vec4 b_color = texture(TEXTURE, UV - direction * aberration_amount);

        vec4 aberration = vec4(r_color.r, g_color.g, b_color.b, 1.0);

        blurred_color = mix(blurred_color, aberration, transition_blur);
    }

    COLOR = blurred_color;
}