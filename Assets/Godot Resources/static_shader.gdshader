shader_type canvas_item;

uniform float static_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float noise_speed : hint_range(1.0, 100.0) = 30.0;
uniform float noise_quality : hint_range(1.0, 10.0) = 3.0;
uniform float static_scale : hint_range(0.1, 10.0) = 1.0;
uniform float time = 0.0;

// Improved noise function for better-looking static
float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise(vec2 p, float t) {
    // Multi-layered noise for more organic static
    vec2 i = floor(p);
    vec2 f = fract(p);

    // Improved smoothing
    vec2 u = f * f * (3.0 - 2.0 * f);

    float a = rand(i + vec2(0.0, 0.0) + t);
    float b = rand(i + vec2(1.0, 0.0) + t);
    float c = rand(i + vec2(0.0, 1.0) + t);
    float d = rand(i + vec2(1.0, 1.0) + t);

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
    // Get the original texture color
    vec4 original_color = texture(TEXTURE, UV);

    if (static_intensity > 0.0) {
        // Generate multi-layered noise for more realistic static
        float n = 0.0;
        float amplitude = 1.0;
        float frequency = 1.0;
        float total_amplitude = 0.0;

        for (float i = 0.0; i < noise_quality; i++) {
            n += amplitude * noise(UV * static_scale * frequency * 100.0, time * (noise_speed / 30.0) + i * 1.3);
            total_amplitude += amplitude;
            amplitude *= 0.5;
            frequency *= 2.0;
        }

        n /= total_amplitude;

        // Create static with smoother edges
        float static_val = smoothstep(1.0 - static_intensity * 0.8, 1.0, n);

        // Mix with original color for better blending
        vec3 static_col = vec3(static_val);

        // Add color noise for more realistic TV static effect
        if (static_intensity > 0.5) {
            float r_offset = noise(UV * static_scale * 120.0, time * (noise_speed / 25.0));
            float g_offset = noise(UV * static_scale * 120.0, time * (noise_speed / 25.0) + 0.5);
            float b_offset = noise(UV * static_scale * 120.0, time * (noise_speed / 25.0) + 1.0);

            static_col = vec3(
                static_val * (0.7 + 0.3 * r_offset),
                static_val * (0.7 + 0.3 * g_offset),
                static_val * (0.7 + 0.3 * b_offset)
            );
        }

        // Apply scan lines for CRT effect as intensity increases
        if (static_intensity > 0.3) {
            float scan_line = sin(UV.y * 400.0) * 0.5 + 0.5;
            static_col *= 0.85 + 0.15 * scan_line;
        }

        // Blend with original based on intensity
        COLOR = mix(original_color, vec4(static_col, original_color.a), static_intensity);
    } else {
        COLOR = original_color;
    }
}