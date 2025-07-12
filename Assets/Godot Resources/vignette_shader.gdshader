shader_type canvas_item;

uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.5;
uniform float vignette_smoothness : hint_range(0.0, 5.0) = 0.5;
uniform vec4 vignette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float pulse_speed : hint_range(0.0, 10.0) = 1.0;
uniform float pulse_intensity : hint_range(0.0, 1.0) = 0.2;

void fragment() {
    // Get the original texture color
    vec4 original_color = texture(TEXTURE, UV);

    if (vignette_intensity > 0.0) {
        // Calculate distance from center with more precision
        vec2 center = vec2(0.5);
        vec2 uv_centered = UV - center;

        // Make the vignette slightly oval (feels more natural for human vision)
        uv_centered.x *= 1.1;

        float dist = length(uv_centered);

        // Adjusted vignette formula for smoother falloff
        float vignette = smoothstep(0.4, 0.4 + vignette_smoothness, dist * (1.0 + vignette_intensity));

        // Add subtle pulsing when oxygen is low (intensity > 0.5)
        if (vignette_intensity > 0.5) {
            float pulse = pulse_intensity * sin(TIME * pulse_speed) * (vignette_intensity - 0.5) * 2.0;
            vignette += pulse * vignette; // Only pulse the existing vignette
        }

        // Mix the vignette with original color
        vec4 vignette_effect = mix(original_color, vignette_color, vignette * vignette_intensity);

        // Add subtle desaturation as oxygen decreases
        if (vignette_intensity > 0.3) {
            // Convert to grayscale
            float gray = dot(vignette_effect.rgb, vec3(0.299, 0.587, 0.114));
            vec3 desaturated = vec3(gray);

            // Mix with color based on intensity
            float desaturation_factor = smoothstep(0.3, 1.0, vignette_intensity) * 0.5;
            vignette_effect.rgb = mix(vignette_effect.rgb, desaturated, desaturation_factor);
        }

        COLOR = vignette_effect;
    } else {
        COLOR = original_color;
    }
}