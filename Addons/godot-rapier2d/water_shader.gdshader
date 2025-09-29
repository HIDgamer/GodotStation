shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture;
uniform sampler2D noise_texture : filter_nearest, repeat_enable; // still used for subtle shimmer

uniform float distortion = 0.015; // how much background bends
uniform float wave_strength = 0.02; // how much the waves warp the UV
uniform float shimmer_strength = 0.03; // how strong the shimmer highlight is

uniform vec2 wave_scale1 = vec2(6.0, 2.0); // frequency of first wave
uniform vec2 wave_scale2 = vec2(3.0, 4.0); // frequency of second wave
uniform float wave_speed1 = 0.8; // speed of first wave
uniform float wave_speed2 = 1.2; // speed of second wave

varying vec2 globalposition;

void vertex() {
    globalposition = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
    // Base texture sample (your water tile texture)
    vec4 base_col = texture(TEXTURE, UV);

    // --- Ocean-like wave distortion ---
    vec2 uv = globalposition / 32.0;

    // Two wave layers at different scales and speeds
    float wave1 = sin(uv.x * wave_scale1.x + TIME * wave_speed1) * cos(uv.y * wave_scale1.y + TIME * wave_speed1);
    float wave2 = sin(uv.y * wave_scale2.y + TIME * wave_speed2) * cos(uv.x * wave_scale2.x + TIME * wave_speed2);

    // Combine waves into a distortion vector
    vec2 wave_offset = vec2(wave1, wave2) * wave_strength;

    // Sample screen texture with refractive wave offset
    vec4 screen_col = texture(screen_texture, SCREEN_UV + wave_offset * distortion);

    // --- Subtle shimmer using noise ---
    vec2 shimmer_uv = UV * 3.0 + vec2(TIME * 0.2, TIME * 0.15);
    float shimmer = texture(noise_texture, shimmer_uv).r;
    base_col.rgb += shimmer * shimmer_strength;

    // Final composite
    COLOR = base_col * screen_col;
}
