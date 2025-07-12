shader_type canvas_item;

// Player and FOV settings
uniform sampler2D SCREEN_TEXTURE: hint_screen_texture, filter_linear_mipmap;
uniform vec2 player_position = vec2(0.5, 0.5);
uniform float player_direction = 0.0; // Direction angle in radians
uniform float fov_angle = 1.57; // FOV width in radians (90 degrees)
uniform float fov_range = 0.3; // How far the player can see (normalized 0-1)
uniform float aura_radius = 0.05; // Radius of always-visible circle around player
uniform float peripheral_vision = 0.2; // How much to see outside the main cone
uniform float blur_strength = 3.0; // Blur intensity
uniform float darkness = 0.7; // How dark the areas outside FOV are (0-1)
uniform float smooth_edges = 0.02; // Smoothness of FOV edges

void fragment() {
    // Original screen texture
    vec4 original = texture(SCREEN_TEXTURE, SCREEN_UV);

    // Calculate screen aspect ratio
    float aspect_ratio = 1.0 / SCREEN_PIXEL_SIZE.y * SCREEN_PIXEL_SIZE.x;

    // Calculate vector from player to this pixel
    vec2 to_pixel = SCREEN_UV - player_position;

    // Calculate distance (before aspect ratio adjustment for true circular aura)
    float true_distance = length(to_pixel);

    // Adjust for aspect ratio for directional calculations
    to_pixel.x *= aspect_ratio;
    float adjusted_distance = length(to_pixel);

    // Calculate player's forward vector based on direction
    // IMPORTANT: The direction is counter-clockwise from the positive X axis
    vec2 player_forward = vec2(cos(player_direction), sin(player_direction));
    // Adjust forward vector for aspect ratio
    player_forward.x *= aspect_ratio;
    player_forward = normalize(player_forward);

    // Calculate the angle between forward vector and direction to pixel
    float angle = 0.0;
    if (adjusted_distance > 0.001) { // Avoid division by zero
        vec2 norm_to_pixel = normalize(to_pixel);
        float dot_product = dot(player_forward, norm_to_pixel);
        angle = acos(clamp(dot_product, -1.0, 1.0));
    }

    // Calculate visibility factor (1.0 = fully visible, 0.0 = not visible)
    float visibility = 0.0;
    float half_fov = fov_angle * 0.5;

    // Within aura radius - always visible
    if (true_distance <= aura_radius) {
        visibility = 1.0;
    }
    // Within FOV cone
    else if (angle <= half_fov && adjusted_distance <= fov_range) {
        // Smooth falloff near edges
        float angle_falloff = smoothstep(half_fov, half_fov - smooth_edges, angle);
        float distance_falloff = smoothstep(fov_range, fov_range - smooth_edges * 5.0, adjusted_distance);
        visibility = angle_falloff * distance_falloff;
    }
    // Peripheral vision
    else {
        // Calculate peripheral vision falloff
        float angle_factor = 1.0 - smoothstep(half_fov, PI, angle);
        float distance_factor = 1.0 - smoothstep(aura_radius, fov_range, adjusted_distance);
        visibility = angle_factor * distance_factor * peripheral_vision;
    }

    // Apply blur and darkness based on visibility
    vec4 final_color;

    if (visibility < 0.99) {
        // Calculate blur strength based on visibility
        float blur_pixels = blur_strength * (1.0 - visibility);

        // Apply box blur
        vec4 blurred = vec4(0.0);
        float total_weight = 0.0;

        for (float x = -3.0; x <= 3.0; x += 1.0) {
            for (float y = -3.0; y <= 3.0; y += 1.0) {
                vec2 offset = vec2(x, y) * blur_pixels / 500.0;
                blurred += texture(SCREEN_TEXTURE, SCREEN_UV + offset);
                total_weight += 1.0;
            }
        }
        blurred /= total_weight;

        // Darken areas outside FOV
        blurred.rgb *= mix(1.0 - darkness, 1.0, visibility);

        // Smooth transition between original and blurred
        final_color = mix(blurred, original, smoothstep(0.0, 0.99, visibility));
    } else {
        final_color = original;
    }

    COLOR = final_color;
}