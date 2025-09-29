shader_type canvas_item;

uniform float blur_amount : hint_range(0.0, 10.0) = 2.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.8;
uniform float scale_factor : hint_range(0.1, 2.0) = 0.95;
uniform vec4 atmospheric_tint : source_color = vec4(0.7, 0.8, 1.0, 1.0);
uniform float desaturation : hint_range(0.0, 1.0) = 0.2;
uniform float chromatic_aberration : hint_range(0.0, 2.0) = 0.5;
uniform int z_distance : hint_range(1, 10) = 1;

uniform float depth_fog_density : hint_range(0.0, 1.0) = 0.3;
uniform float perspective_distortion : hint_range(0.0, 0.5) = 0.1;
uniform float edge_fade_width : hint_range(0.0, 0.5) = 0.15;
uniform bool enable_noise = true;
uniform float noise_intensity : hint_range(0.0, 0.2) = 0.05;

varying vec2 world_position;
varying vec2 screen_position;

vec2 get_blur_offset(int sample_index, int total_samples) {
    float angle = float(sample_index) * 6.28318 / float(total_samples);
    return vec2(cos(angle), sin(angle));
}

vec4 sample_texture_blur(sampler2D tex, vec2 uv, float blur_radius) {
    vec4 color = vec4(0.0);
    int samples = max(4, int(blur_radius * 8.0));
    
    color += texture(tex, uv) * 0.4;
    
    float total_weight = 0.4;
    
    for (int i = 0; i < samples; i++) {
        vec2 offset = get_blur_offset(i, samples) * blur_radius;
        float weight = 1.0 - (float(i) / float(samples));
        color += texture(tex, uv + offset) * weight;
        total_weight += weight;
    }
    
    return color / total_weight;
}

vec3 apply_chromatic_aberration(sampler2D tex, vec2 uv, float intensity) {
    float offset = intensity * 0.01;
    
    float r = texture(tex, uv + vec2(offset, 0.0)).r;
    float g = texture(tex, uv).g;
    float b = texture(tex, uv - vec2(offset, 0.0)).b;
    
    return vec3(r, g, b);
}

vec3 desaturate_color(vec3 color, float amount) {
    float luminance = dot(color, vec3(0.299, 0.587, 0.114));
    return mix(color, vec3(luminance), amount);
}

vec2 apply_perspective_distortion(vec2 uv, float intensity) {
    vec2 center = vec2(0.5);
    vec2 offset = uv - center;
    float distance_from_center = length(offset);
    
    float distortion = 1.0 + (distance_from_center * intensity);
    return center + (offset * distortion);
}

float get_edge_fade_factor(vec2 uv) {
    vec2 fade_uv = abs(uv - vec2(0.5)) * 2.0;
    float fade_x = smoothstep(1.0 - edge_fade_width, 1.0, fade_uv.x);
    float fade_y = smoothstep(1.0 - edge_fade_width, 1.0, fade_uv.y);
    return 1.0 - max(fade_x, fade_y);
}

float simple_noise(vec2 uv) {
    return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
}

vec4 apply_depth_fog(vec4 color, float fog_factor) {
    vec3 fog_color = atmospheric_tint.rgb;
    return vec4(mix(color.rgb, fog_color, fog_factor), color.a);
}

void vertex() {
    world_position = VERTEX;
    screen_position = UV;
    
    vec2 pivot = vec2(0.5);
    VERTEX = (VERTEX - pivot) * scale_factor + pivot;
}

void fragment() {
    vec2 distorted_uv = apply_perspective_distortion(UV, perspective_distortion * float(z_distance) * 0.1);
    
    if (distorted_uv.x < 0.0 || distorted_uv.x > 1.0 || distorted_uv.y < 0.0 || distorted_uv.y > 1.0) {
        COLOR = vec4(0.0);
    }
    
    vec4 base_color;
    
    if (blur_amount > 0.1) {
        base_color = sample_texture_blur(TEXTURE, distorted_uv, blur_amount * TEXTURE_PIXEL_SIZE.x * 100.0);
    } else {
        base_color = texture(TEXTURE, distorted_uv);
    }
    
    if (chromatic_aberration > 0.1) {
        base_color.rgb = apply_chromatic_aberration(TEXTURE, distorted_uv, chromatic_aberration);
    }
    
    base_color.rgb = desaturate_color(base_color.rgb, desaturation);
    
    float fog_factor = depth_fog_density * (float(z_distance) / 10.0);
    base_color = apply_depth_fog(base_color, fog_factor);
    
    base_color.rgb = mix(base_color.rgb, atmospheric_tint.rgb, atmospheric_tint.a * 0.3);
    
    if (enable_noise) {
        float noise = simple_noise(distorted_uv * 100.0 + TIME * 0.1) - 0.5;
        base_color.rgb += noise * noise_intensity * float(z_distance) * 0.1;
    }
    
    float edge_fade = get_edge_fade_factor(UV);
    base_color.a *= edge_fade;
    
    base_color.a *= opacity;
    
    COLOR = base_color;
}