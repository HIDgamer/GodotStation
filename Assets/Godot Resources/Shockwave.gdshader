shader_type canvas_item;

// Shockwave parameters
uniform float wave_intensity : hint_range(0.0, 1.0) = 0.1;
uniform float wave_thickness : hint_range(0.0, 0.5) = 0.1;
uniform float wave_speed : hint_range(0.1, 5.0) = 1.0;
uniform float max_radius : hint_range(0.1, 2.0) = 1.0;
uniform float distortion_intensity : hint_range(0.0, 1.0) = 0.3;
uniform vec4 wave_color : source_color = vec4(1.0, 1.0, 1.0, 0.2);
uniform bool invert_direction = false;

// Use global time by default but allow overriding for precise control
uniform bool use_custom_time = false;
uniform float custom_time = 0.0;

// Noise settings for a more organic shockwave
uniform bool use_noise = true;
uniform float noise_intensity : hint_range(0.0, 0.2) = 0.02;

// Screen texture to sample from (for distortion)
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

// Noise function - returns a value between -1.0 and 1.0
float noise(vec2 uv) {
    return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453) * 2.0 - 1.0;
}

void fragment() {
    // Calculate time based on either global time or custom time
    float time = use_custom_time ? custom_time : TIME;
    time *= wave_speed;

    // Calculate normalized distance from center (0.5, 0.5)
    vec2 center = vec2(0.5, 0.5);
    float dist = distance(UV, center) * 2.0; // Range 0.0 to ~1.0 for a centered circle

    // Calculate the current radius of the wave
    float wave_radius = min(time, max_radius);

    // Calculate the wave front - a ring expanding outward
    float wave_front = smoothstep(wave_radius - wave_thickness, wave_radius, dist) *
                       smoothstep(wave_radius + wave_thickness, wave_radius, dist);

    // Apply noise if enabled
    if (use_noise) {
        float angle = atan(UV.y - 0.5, UV.x - 0.5);
        float noise_val = noise(vec2(angle * 10.0, time * 2.0)) * noise_intensity;
        wave_front *= (1.0 + noise_val);
    }

    // Adjust intensity based on how far the wave has traveled
    float intensity_falloff = 1.0 - min(wave_radius / max_radius, 1.0);
    wave_front *= wave_intensity * intensity_falloff;

    // Direction vector for distortion (radial from center)
    vec2 direction = normalize(UV - center);
    if (invert_direction) {
        direction = -direction;
    }

    // Distortion vector
    vec2 distortion = direction * wave_front * distortion_intensity;

    // Sample the screen texture with distortion
    vec4 screen_color = texture(SCREEN_TEXTURE, SCREEN_UV + distortion);

    // Blend with wave color
    vec4 final_color = mix(screen_color, wave_color, wave_front * wave_color.a);

    // Add a subtle glow to the wave front
    float glow = wave_front * 0.5;
    final_color.rgb += wave_color.rgb * glow;

    COLOR = final_color;
}