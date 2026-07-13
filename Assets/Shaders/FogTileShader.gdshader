shader_type canvas_item;

uniform sampler2D wall_texture : filter_nearest, repeat_disable;
uniform vec2 player_position;
uniform ivec2 map_min;
uniform ivec2 map_size;
uniform vec2 map_offset;
uniform int view_range = 20;
uniform int tile_scale = 8;

float sample_wall(vec2 world_pos) {
    vec2 tile_pos = floor(world_pos / 32.0);
    ivec2 tile_coord = ivec2(tile_pos) - map_min;
    ivec2 scaled_coord = tile_coord * tile_scale + tile_scale / 2;
    
    if (scaled_coord.x >= 0 && scaled_coord.x < map_size.x &&
        scaled_coord.y >= 0 && scaled_coord.y < map_size.y) {
        vec2 tex_uv = (vec2(scaled_coord) + 0.5) / vec2(map_size);
        return texture(wall_texture, tex_uv).r;
    }
    return 0.0;
}

// Simple hash for dithering
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

bool is_blocked(vec2 from, vec2 to, float max_check, vec2 pixel_pos) {
    vec2 delta = to - from;
    float total = length(delta);
    if (total < 1.0) return false;
    
    vec2 dir = delta / total;
    float check_dist = min(total, max_check);
    
    // Use pixel position for consistent dithering
    float dither = hash(pixel_pos) * 4.0 - 2.0;
    float step = 4.0 + dither; // Vary step slightly per pixel
    int steps = int(check_dist / step);
    
    for (int i = 1; i <= steps; i++) {
        float d = float(i) * step;
        if (d >= check_dist) break;
        
        vec2 p = from + dir * d;
        if (sample_wall(p) > 0.5) {
            return true;
        }
    }
    
    return false;
}

void fragment() {
    vec2 rect_size = vec2(map_size) / float(tile_scale) * 32.0;
    vec2 world_pos = UV * rect_size + map_offset;
    
    float frag_dist = distance(world_pos, player_position);
    float max_dist = float(view_range) * 32.0;
    
    bool is_wall = sample_wall(world_pos) > 0.5;
    float visibility = 1.0 - clamp(frag_dist / max_dist, 0.0, 1.0);
    
    if (frag_dist > max_dist) {
        COLOR = vec4(0.0, 0.0, 0.0, 1.0);
    } else if (is_wall) {
        if (is_blocked(player_position, world_pos, frag_dist - 48.0, world_pos)) {
            COLOR = vec4(0.0, 0.0, 0.0, 1.0);
        } else {
            COLOR = vec4(0.0, 0.0, 0.0, 0.0);
        }
    } else {
        if (is_blocked(player_position, world_pos, frag_dist, world_pos)) {
            COLOR = vec4(0.0, 0.0, 0.0, 1.0);
        } else {
            COLOR = vec4(0.0, 0.0, 0.0, 1.0 - visibility);
        }
    }
}