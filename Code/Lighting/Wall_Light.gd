@tool
extends PointLight2D

class_name AdvancedLight

enum Direction {
	NORTH,
	EAST,
	SOUTH,
	WEST
}

enum LightMode {
	WALL_LIGHT,
	EMERGENCY_LIGHT
}

@export_group("Light Core")
@export var light_mode: LightMode = LightMode.WALL_LIGHT:
	set(value):
		light_mode = value
		_update_light_setup()

@export var is_active: bool = true:
	set(value):
		is_active = value
		_update_light_state()

@export var light_color: Color = Color(1.0, 0.9, 0.7, 1.0):
	set(value):
		light_color = value
		color = light_color
		if cone_light:
			cone_light.color = light_color

@export var light_energy: float = 1.0:
	set(value):
		light_energy = value
		energy = light_energy
		_base_energy = light_energy

@export var light_range: float = 200.0:
	set(value):
		light_range = value
		texture_scale = light_range / 100.0
		if cone_light:
			cone_light.texture_scale = light_range / 100.0

@export_group("Wall Light Properties")
@export var facing_direction: Direction = Direction.NORTH:
	set(value):
		facing_direction = value
		_update_sprite_animation()

@export_group("Emergency Light Properties")
@export var emergency_mode_active: bool = false:
	set(value):
		emergency_mode_active = value
		_update_emergency_state()
		
@export var rotation_speed: float = 3.0
@export var cone_offset: float = 0
@export var cone_color: Color = Color(1.0, 0.2, 0.2)
@export var ambient_color: Color = Color(0.6, 0.0, 0.0)
@export var max_energy: float = 0.7

@export_group("Shadow Properties")
@export var cast_shadows: bool = true:
	set(value):
		cast_shadows = value
		_update_all_shadows()
		
@export var shadow_smoothness: float = 5.0:
	set(value):
		shadow_smoothness = value
		_update_shadow_smoothness()
		
@export var shadow_strength: float = 1.0:
	set(value):
		shadow_strength = value
		shadow_color = Color(0, 0, 0, shadow_strength)
		if cone_light:
			cone_light.shadow_color = Color(0, 0, 0, shadow_strength)

@export_group("Visual Effects")
@export var use_flicker: bool = false
@export var flicker_intensity: float = 0.1
@export var flicker_speed: float = 5.0
@export var use_pulse: bool = false
@export var pulse_intensity: float = 0.2
@export var pulse_speed: float = 1.0

@export_group("Performance")
@export var is_static: bool = false
@export var light_quality: int = 80
@export var update_interval: float = 0.05
@export var culling_distance: float = 480.0
@export var shadow_distance: float = 250.0

@export_group("Day/Night Cycle")
@export var auto_toggle_with_daylight: bool = false
@export var turn_on_time: float = 18.0
@export var turn_off_time: float = 6.0

var _base_energy: float
var _flicker_time: float = 0.0
var _time: float = 0.0
var _is_baked: bool = false
var _original_texture: Texture2D
var _light_map_node: Sprite2D
var _update_timer: float = 0.0
var _player: Node2D = null
var _effects_energy_modifier: float = 0.0
var _culling_timer: float = 0.0
var _culling_check_interval: float = 0.5

@onready var cone_light: PointLight2D = $cone_light
@onready var sprite_on: AnimatedSprite2D = $On if has_node("On") else null
@onready var sprite_off: AnimatedSprite2D = $Off if has_node("Off") else null

func _ready() -> void:
	_base_energy = light_energy
	
	if Engine.is_editor_hint():
		_update_light_state()
		return
	
	_update_light_setup()
	_update_light_state()
	
	if light_mode == LightMode.WALL_LIGHT:
		_update_sprite_animation()
	
	if texture:
		_original_texture = texture
	
	if auto_toggle_with_daylight && has_node("/root/DayNightCycle"):
		var day_night_cycle = get_node("/root/DayNightCycle")
		if day_night_cycle.has_signal("time_changed"):
			day_night_cycle.connect("time_changed", _on_day_night_time_changed)
	
	if light_mode == LightMode.EMERGENCY_LIGHT:
		await get_tree().process_frame
		_set_light_quality(light_quality)
	
	_find_player()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	_time += delta
	_culling_timer += delta
	
	if _culling_timer >= _culling_check_interval:
		_culling_timer = 0.0
		_check_player_distance()
	
	if !visible || !is_active:
		return
	
	if use_flicker:
		_flicker_time += delta * flicker_speed
		var flicker_value = sin(_flicker_time) * flicker_intensity
		energy = _base_energy + flicker_value
	
	if use_pulse:
		var pulse_value = pulse_intensity * sin(_time * pulse_speed)
		energy = _base_energy + pulse_value
	
	if light_mode == LightMode.WALL_LIGHT:
		if is_active && use_flicker:
			_flicker_time += delta * flicker_speed
			var flicker_value = sin(_flicker_time) * flicker_intensity
			energy = _base_energy + flicker_value
	
	elif light_mode == LightMode.EMERGENCY_LIGHT:
		if is_active:
			_update_rotation(delta)
		
		_update_timer += delta
		
		if _update_timer >= update_interval:
			_update_timer = 0.0
			_update_effects_and_optimizations(delta)

func _find_player() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]

func _check_player_distance() -> void:
	if !_player:
		_find_player()
		return
	
	if !_player:
		return
	
	var distance = global_position.distance_to(_player.global_position)
	visible = distance <= culling_distance

func _update_rotation(delta: float) -> void:
	if !cone_light:
		return
		
	var rotation_increment = delta * rotation_speed * TAU
	cone_light.rotation += rotation_increment
	
	if cone_light.rotation > TAU:
		cone_light.rotation -= TAU

func _update_all_shadows() -> void:
	if light_mode == LightMode.WALL_LIGHT:
		shadow_enabled = cast_shadows

func _update_shadow_smoothness() -> void:
	shadow_filter_smooth = shadow_smoothness

func _update_effects_and_optimizations(delta: float) -> void:
	if light_mode != LightMode.EMERGENCY_LIGHT:
		return
		
	if _player != null:
		var distance_to_player = global_position.distance_to(_player.global_position)
		var enable_shadows = distance_to_player < shadow_distance
		shadow_enabled = enable_shadows
		if cone_light:
			cone_light.shadow_enabled = enable_shadows
	
	if !is_active:
		return
	
	_time += delta
	_effects_energy_modifier = 0.0
	
	if use_flicker:
		_effects_energy_modifier += flicker_intensity * (randf() - 0.5) * 2.0
	
	if use_pulse:
		_effects_energy_modifier += pulse_intensity * sin(_time * pulse_speed)
	
	var current_energy = clamp(_base_energy + _effects_energy_modifier, 0.1, max_energy)
	energy = current_energy
	if cone_light:
		cone_light.energy = current_energy

func _set_light_quality(quality: int) -> void:
	var shadow_resolution = 256
	var shadow_smooth = 1.5
	
	match quality:
		0:
			shadow_enabled = false
			if cone_light:
				cone_light.shadow_enabled = false
			shadow_resolution = 128
		20:
			shadow_enabled = true
			if cone_light:
				cone_light.shadow_enabled = true
			shadow_resolution = 256
			shadow_smooth = 0.0
		40:
			shadow_enabled = true
			if cone_light:
				cone_light.shadow_enabled = true
			shadow_resolution = 512
			shadow_smooth = 1.0
		60:
			shadow_enabled = true
			if cone_light:
				cone_light.shadow_enabled = true
			shadow_resolution = 1024
			shadow_smooth = 2.0
		80:
			shadow_enabled = true
			if cone_light:
				cone_light.shadow_enabled = true
			shadow_resolution = 2048
			shadow_smooth = 2.5
		100:
			shadow_enabled = true
			if cone_light:
				cone_light.shadow_enabled = true
			shadow_resolution = 4096
			shadow_smooth = 3.0
	
	shadow_filter_smooth = shadow_smooth
	if cone_light:
		cone_light.shadow_filter_smooth = shadow_smooth
	
	if shadow_enabled:
		ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/size", shadow_resolution)

func _update_light_setup() -> void:
	if light_mode == LightMode.EMERGENCY_LIGHT:
		_update_sprite_animation()
		if !cone_light:
			cone_light = PointLight2D.new()
			cone_light.name = "ConeLight"
			add_child(cone_light)
		
		cone_light.energy = _base_energy
		cone_light.texture_scale = light_range / 100.0
		cone_light.color = cone_color
		
		if sprite_on:
			sprite_on.rotation = 0
		if sprite_off:
			sprite_off.rotation = 0
		
	else:
		_update_sprite_animation()
		if cone_light:
			cone_light.queue_free()
			cone_light = null
			
		if sprite_on:
			sprite_on.rotation = 0
		if sprite_off:
			sprite_off.rotation = 0

func _update_light_state() -> void:
	enabled = is_active
	
	if light_mode == LightMode.WALL_LIGHT:
		if sprite_on:
			sprite_on.visible = is_active
		if sprite_off:
			sprite_off.visible = not is_active
	
	if light_mode == LightMode.EMERGENCY_LIGHT:
		if cone_light:
			cone_light.enabled = is_active
			cone_light.energy = _base_energy if is_active else 0.0

func _update_emergency_state() -> void:
	if light_mode != LightMode.EMERGENCY_LIGHT:
		return
		
	if emergency_mode_active:
		use_flicker = false
		flicker_intensity = 0.2
		if cone_light:
			cone_light.color = cone_color
	else:
		use_flicker = false
		if cone_light:
			cone_light.color = light_color

func _update_sprite_animation() -> void:
	if !sprite_on || !sprite_off:
		return
		
	var dir := ""
	match facing_direction:
		Direction.NORTH:
			dir = "North"
		Direction.EAST:
			dir = "East"
		Direction.SOUTH:
			dir = "South"
		Direction.WEST:
			dir = "West"
	
	if sprite_on.sprite_frames.has_animation(dir):
		sprite_on.animation = dir
	if sprite_off.sprite_frames.has_animation(dir):
		sprite_off.animation = dir

func turn_on() -> void:
	is_active = true

func turn_off() -> void:
	is_active = false

func toggle() -> void:
	is_active = !is_active

func set_emergency_mode(enabled: bool = true) -> void:
	emergency_mode_active = enabled

func set_rotation_speed(speed: float) -> void:
	rotation_speed = speed

func _on_day_night_time_changed(time: float) -> void:
	if !auto_toggle_with_daylight:
		return
		
	if turn_on_time < turn_off_time:
		if time >= turn_on_time || time < turn_off_time:
			turn_on()
		else:
			turn_off()
	else:
		if time >= turn_on_time || time < turn_off_time:
			turn_on()
		else:
			turn_off()

func _cleanup_emergency_lights() -> void:
	if cone_light:
		cone_light.queue_free()
		cone_light = null
