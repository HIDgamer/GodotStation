@tool
extends PointLight2D

class_name AdvancedLight

# Direction enum with more options for finer control
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

# Core properties
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
		if _ambient_light:
			_ambient_light.color = light_color
		if _cone_light1:
			_cone_light1.color = light_color
		if _cone_light2:
			_cone_light2.color = light_color
		
@export var light_energy: float = 1.0:
	set(value):
		light_energy = value
		energy = light_energy
		_base_energy = light_energy
		if _ambient_light:
			_ambient_light.energy = light_energy * 0.7

@export var light_range: float = 200.0:
	set(value):
		light_range = value
		texture_scale = light_range / 100.0
		if _ambient_light:
			_ambient_light.texture_scale = (light_range / 100.0) * 1.2
		if _cone_light1:
			_cone_light1.texture_scale = light_range / 100.0
		if _cone_light2:
			_cone_light2.texture_scale = light_range / 100.0

# Wall Light specific properties
@export_group("Wall Light Properties")
@export var facing_direction: Direction = Direction.NORTH:
	set(value):
		facing_direction = value
		_update_sprite_animation()

# Emergency Light specific properties
@export_group("Emergency Light Properties")
@export var emergency_mode_active: bool = false:
	set(value):
		emergency_mode_active = value
		_update_emergency_state()
		
@export var rotation_speed: float = 3.0  # Rotations per second
@export var cone_offset: float = 0
@export var cone_color: Color = Color(1.0, 0.2, 0.2)  # Red emergency color
@export var ambient_color: Color = Color(0.6, 0.0, 0.0)  # Darker red for ambient light
@export var max_energy: float = 0.7

# Shadow properties
# Shadow properties
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
		if _ambient_light:
			_ambient_light.shadow_color = Color(0, 0, 0, shadow_strength)
		if _cone_light1:
			_cone_light1.shadow_color = Color(0, 0, 0, shadow_strength)
		if _cone_light2:
			_cone_light2.shadow_color = Color(0, 0, 0, shadow_strength)

# Visual effects
@export_group("Visual Effects")
@export var use_flicker: bool = false
@export var flicker_intensity: float = 0.1
@export var flicker_speed: float = 5.0
@export var use_pulse: bool = false
@export var pulse_intensity: float = 0.2
@export var pulse_speed: float = 1.0
@export var use_glow: bool = true:
	set(value):
		use_glow = value
		if has_node("GlowEffect"):
			$GlowEffect.visible = use_glow && is_active

@export_group("Entity Culling")
@export var enable_entity_culling: bool = true
@export var entity_detection_radius: float = 300.0
@export var entity_groups: Array[String] = ["entities", "players", "mobs"]
@export var culling_check_interval: float = 0.5

# Performance settings
@export_group("Performance")
@export var is_static: bool = false
@export var light_quality: int = 80
@export var update_interval: float = 0.05
@export var disable_when_offscreen: bool = true
@export var shadow_distance: float = 250.0

# Day/Night Cycle Integration
@export_group("Day/Night Cycle")
@export var auto_toggle_with_daylight: bool = false
@export var turn_on_time: float = 18.0  # 24-hour format (6:00 PM)
@export var turn_off_time: float = 6.0   # 24-hour format (6:00 AM)

# Internal variables
var _base_energy: float
var _flicker_time: float = 0.0
var _time: float = 0.0
var _culling_timer: float = 0.0
var _should_be_active: bool = true
var _manual_override: bool = false
var _is_baked: bool = false
var _original_texture: Texture2D
var _light_map_node: Sprite2D
var _update_timer: float = 0.0
var _player_camera: Camera2D = null
var _effects_energy_modifier: float = 0.0

# Emergency light components
@onready var _cone_light1: PointLight2D = $cone_light1
@onready var _cone_light2: PointLight2D = $cone_light2
@onready var _ambient_light: PointLight2D = $ambient_light

# References to child nodes
@onready var sprite_on: AnimatedSprite2D = $On if has_node("On") else null
@onready var sprite_off: AnimatedSprite2D = $Off if has_node("Off") else null

func _ready() -> void:
	_base_energy = light_energy
	
	if Engine.is_editor_hint():
		# Only update visuals in editor
		_update_light_state()
		return
	
	# Initialize based on the light mode
	_update_light_setup()
	
	# Set up initial state
	_update_light_state()
	if light_mode == LightMode.WALL_LIGHT:
		_update_sprite_animation()
	
	# Store original texture for reference
	if texture:
		_original_texture = texture
	
	# Connect to day/night cycle if available
	if auto_toggle_with_daylight && has_node("/root/DayNightCycle"):
		var day_night_cycle = get_node("/root/DayNightCycle")
		if day_night_cycle.has_signal("time_changed"):
			day_night_cycle.connect("time_changed", _on_day_night_time_changed)
	
	# For emergency light mode, find the player camera
	if light_mode == LightMode.EMERGENCY_LIGHT:
		await get_tree().process_frame
		_find_player_camera()
		_set_light_quality(light_quality)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	_time += delta
	_culling_timer += delta
	
	# Entity culling check
	if enable_entity_culling && _culling_timer >= culling_check_interval:
		_culling_timer = 0.0
		_check_nearby_entities()
	
	# Only process effects if the light should be active
	if !_should_be_active || !is_active:
		return
	
	# Visual effects processing
	if use_flicker:
		_flicker_time += delta * flicker_speed
		var flicker_value = sin(_flicker_time) * flicker_intensity
		energy = _base_energy + flicker_value
	
	if use_pulse:
		var pulse_value = pulse_intensity * sin(_time * pulse_speed)
		energy = _base_energy + pulse_value
	
	if light_mode == LightMode.WALL_LIGHT:
		# Wall light mode processing
		if is_active && use_flicker:
			_flicker_time += delta * flicker_speed
			var flicker_value = sin(_flicker_time) * flicker_intensity
			energy = _base_energy + flicker_value
	
	elif light_mode == LightMode.EMERGENCY_LIGHT:
		# Emergency light processing
		
		# Always update rotation every frame for smooth motion when active
		# Remove the emergency_mode_active condition so rotation always works in emergency mode
		if is_active:
			_update_rotation(delta)
		
		# The rest of the effects use the interval
		_update_timer += delta
		
		if _update_timer >= update_interval:
			_update_timer = 0.0
			_update_effects_and_optimizations(delta)

# Separate rotation update function to ensure smooth motion every frame
func _update_rotation(delta: float) -> void:
	if !_cone_light1 || !_cone_light2:
		return
		
	# Calculate rotation increment for this frame
	var rotation_increment = delta * rotation_speed * TAU
	
	# Rotate both cone lights
	_cone_light1.rotation += rotation_increment
	_cone_light2.rotation += rotation_increment
	
	# Keep rotations within 0 to TAU to avoid large numbers over time
	if _cone_light1.rotation > TAU:
		_cone_light1.rotation -= TAU
	if _cone_light2.rotation > TAU:
		_cone_light2.rotation -= TAU

func _update_all_shadows() -> void:
	if light_mode == LightMode.WALL_LIGHT:
		shadow_enabled = cast_shadows
	# Emergency lights always have shadows disabled for performance

func _update_shadow_smoothness() -> void:
	shadow_filter_smooth = shadow_smoothness

func _check_nearby_entities() -> void:
	var entities_nearby = false
	
	# Check each entity group
	for group_name in entity_groups:
		var entities = get_tree().get_nodes_in_group(group_name)
		for entity in entities:
			if entity && entity.has_method("get_global_position"):
				var distance = global_position.distance_to(entity.get_global_position())
				if distance <= entity_detection_radius:
					entities_nearby = true
					break
		
		if entities_nearby:
			break
	
	# Update light state based on entity proximity
	var new_state = entities_nearby || _manual_override
	if new_state != _should_be_active:
		_should_be_active = new_state
		_update_actual_light_state()

func _update_actual_light_state() -> void:
	var final_active = _should_be_active && is_active
	
	visible = final_active
	enabled = final_active
	
	if light_mode == LightMode.WALL_LIGHT:
		if sprite_on:
			sprite_on.visible = final_active
		if sprite_off:
			sprite_off.visible = not final_active
	
	elif light_mode == LightMode.EMERGENCY_LIGHT:
		if _cone_light1:
			_cone_light1.enabled = final_active
		if _cone_light2:
			_cone_light2.enabled = final_active
		if _ambient_light:
			_ambient_light.enabled = final_active

# Update all other effects and optimizations on interval
func _update_effects_and_optimizations(delta: float) -> void:
	if light_mode != LightMode.EMERGENCY_LIGHT:
		return
		
	# Check if we should be active based on distance to camera
	if disable_when_offscreen && _player_camera != null:
		var distance_to_camera = global_position.distance_to(_player_camera.global_position)
		var viewport_size = get_viewport_rect().size
		var max_visible_distance = max(viewport_size.x, viewport_size.y) * 0.75
		
		# Toggle active state based on visibility
		var should_be_active = distance_to_camera < max_visible_distance
		
		if should_be_active != is_active:
			is_active = should_be_active
			visible = is_active
			set_process(is_active)
			return
		
		# Handle shadow optimization
		var enable_shadows = distance_to_camera < shadow_distance
		shadow_enabled = enable_shadows
		if _cone_light1:
			_cone_light1.shadow_enabled = enable_shadows
		if _cone_light2:
			_cone_light2.shadow_enabled = enable_shadows
		if _ambient_light:
			_ambient_light.shadow_enabled = enable_shadows
	
	if !is_active:
		return
	
	_time += delta
	
	# Calculate light energy based on effects
	_effects_energy_modifier = 0.0
	
	if use_flicker:
		# Use noise-based flickering for more natural look
		_effects_energy_modifier += flicker_intensity * (randf() - 0.5) * 2.0
	
	if use_pulse:
		# Smooth sine wave pulsing
		_effects_energy_modifier += pulse_intensity * sin(_time * pulse_speed)
	
	# Apply the final energy value, clamped to avoid excessive brightness
	var current_energy = clamp(_base_energy + _effects_energy_modifier, 0.1, max_energy)
	energy = current_energy
	if _cone_light1:
		_cone_light1.energy = current_energy
	if _cone_light2:
		_cone_light2.energy = current_energy
	if _ambient_light:
		_ambient_light.energy = current_energy * 0.7  # Keep ambient light slightly dimmer

# Find the player camera for distance-based optimizations
func _find_player_camera() -> void:
	var cameras = get_tree().get_nodes_in_group("PlayerCamera")
	if cameras.size() > 0:
		_player_camera = cameras[0]
	else:
		# Fallback to any Camera2D in the scene
		var all_cameras = get_tree().get_nodes_in_group("Camera2D")
		if all_cameras.size() > 0:
			_player_camera = all_cameras[0]

# Set light quality based on performance needs
func _set_light_quality(quality: int) -> void:
	var shadow_resolution = 256
	var shadow_smooth = 1.5
	
	match quality:
		0: # Ultra Low
			shadow_enabled = false
			if _cone_light1:
				_cone_light1.shadow_enabled = false
			if _cone_light2:
				_cone_light2.shadow_enabled = false
			if _ambient_light:
				_ambient_light.shadow_enabled = false
			shadow_resolution = 128
		20: # Low
			shadow_enabled = true
			if _cone_light1:
				_cone_light1.shadow_enabled = true
			if _cone_light2:
				_cone_light2.shadow_enabled = true
			if _ambient_light:
				_ambient_light.shadow_enabled = true
			shadow_resolution = 256
			shadow_smooth = 0.0
		40: # Medium
			shadow_enabled = true
			if _cone_light1:
				_cone_light1.shadow_enabled = true
			if _cone_light2:
				_cone_light2.shadow_enabled = true
			if _ambient_light:
				_ambient_light.shadow_enabled = true
			shadow_resolution = 512
			shadow_smooth = 1.0
		60: # High
			shadow_enabled = true
			if _cone_light1:
				_cone_light1.shadow_enabled = true
			if _cone_light2:
				_cone_light2.shadow_enabled = true
			if _ambient_light:
				_ambient_light.shadow_enabled = true
			shadow_resolution = 1024
			shadow_smooth = 2.0
		80: # Very High (Default)
			shadow_enabled = true
			if _cone_light1:
				_cone_light1.shadow_enabled = true
			if _cone_light2:
				_cone_light2.shadow_enabled = true
			if _ambient_light:
				_ambient_light.shadow_enabled = true
			shadow_resolution = 2048
			shadow_smooth = 2.5
		100: # Ultra
			shadow_enabled = true
			if _cone_light1:
				_cone_light1.shadow_enabled = true
			if _cone_light2:
				_cone_light2.shadow_enabled = true
			if _ambient_light:
				_ambient_light.shadow_enabled = true
			shadow_resolution = 4096
			shadow_smooth = 3.0
	
	# Apply the settings
	shadow_filter_smooth = shadow_smooth
	if _cone_light1:
		_cone_light1.shadow_filter_smooth = shadow_smooth
	if _cone_light2:
		_cone_light2.shadow_filter_smooth = shadow_smooth
	if _ambient_light:
		_ambient_light.shadow_filter_smooth = shadow_smooth
	
	if shadow_enabled:
		ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/size", shadow_resolution)

func _update_light_setup() -> void:
	if light_mode == LightMode.EMERGENCY_LIGHT:
		_update_sprite_animation()
		# Create emergency light components if they don't exist
		if !_cone_light1:
			_cone_light1 = PointLight2D.new()
			_cone_light1.name = "ConeLight1"
			add_child(_cone_light1)
			
		if !_cone_light2:
			_cone_light2 = PointLight2D.new()
			_cone_light2.name = "ConeLight2"
			add_child(_cone_light2)
			
		if !_ambient_light:
			_ambient_light = PointLight2D.new()
			_ambient_light.name = "AmbientLight"
			add_child(_ambient_light)
		
		# Configure the cone lights
		_cone_light1.energy = _base_energy
		_cone_light1.texture_scale = light_range / 100.0
		_cone_light1.color = cone_color
		
		_cone_light2.energy = _base_energy
		_cone_light2.texture_scale = light_range / 100.0
		_cone_light2.color = cone_color
		# Set initial rotation offset for second cone
		_cone_light2.rotation = cone_offset
		
		# Configure the ambient circular light
		_ambient_light.energy = _base_energy * 0.7  # Slightly dimmer
		_ambient_light.texture_scale = (light_range / 100.0) * 1.2  # Slightly larger
		_ambient_light.color = ambient_color

		# For emergency lights, ensure sprites can rotate
		if sprite_on:
			sprite_on.rotation = 0
		if sprite_off:
			sprite_off.rotation = 0
		
	else:
		_update_sprite_animation()
		# Wall light mode - remove emergency components if they exist
		if _cone_light1:
			_cone_light1.queue_free()
			_cone_light1 = null
			
		if _cone_light2:
			_cone_light2.queue_free()
			_cone_light2 = null
			
		if _ambient_light:
			_ambient_light.queue_free()
			_ambient_light = null
			
		# Reset sprite rotations when switching to wall light mode
		if sprite_on:
			sprite_on.rotation = 0
		if sprite_off:
			sprite_off.rotation = 0

func _update_light_state() -> void:
	if enable_entity_culling && !Engine.is_editor_hint():
		_update_actual_light_state()
	else:
		# Direct state update when culling is disabled
		visible = is_active
		enabled = is_active
		
		if light_mode == LightMode.WALL_LIGHT:
			if sprite_on:
				sprite_on.visible = is_active
			if sprite_off:
				sprite_off.visible = not is_active
		# Update glow effect if it exists
		if has_node("GlowEffect"):
			$GlowEffect.visible = use_glow and is_active
	
	if light_mode == LightMode.EMERGENCY_LIGHT:
		# Update emergency light components
		if _cone_light1:
			_cone_light1.enabled = is_active
			_cone_light1.energy = _base_energy if is_active else 0.0
		if _cone_light2:
			_cone_light2.enabled = is_active
			_cone_light2.energy = _base_energy if is_active else 0.0
		if _ambient_light:
			_ambient_light.enabled = is_active
			_ambient_light.energy = _base_energy * 0.7 if is_active else 0.0

func _update_emergency_state() -> void:
	if light_mode != LightMode.EMERGENCY_LIGHT:
		return
		
	if emergency_mode_active:
		use_flicker = false
		flicker_intensity = 0.2
		if _cone_light1:
			_cone_light1.color = cone_color
		if _cone_light2:
			_cone_light2.color = cone_color
		if _ambient_light:
			_ambient_light.color = ambient_color
	else:
		use_flicker = false
		# Reset to normal colors but keep rotating
		if _cone_light1:
			_cone_light1.color = light_color
		if _cone_light2:
			_cone_light2.color = light_color
		if _ambient_light:
			_ambient_light.color = light_color

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
	
	# Only update animations if they exist
	if sprite_on.sprite_frames.has_animation(dir):
		sprite_on.animation = dir
	if sprite_off.sprite_frames.has_animation(dir):
		sprite_off.animation = dir

# Public methods for controlling the light
func turn_on() -> void:
	is_active = true

func turn_off() -> void:
	is_active = false

func toggle() -> void:
	is_active = !is_active

# Emergency mode control
func set_emergency_mode(enabled: bool = true) -> void:
	emergency_mode_active = enabled

# Set rotation speed at runtime
func set_rotation_speed(speed: float) -> void:
	rotation_speed = speed

# Set cone offset at runtime
func set_cone_offset(offset: float) -> void:
	cone_offset = offset
	# Update the second cone's position relative to the first
	if _cone_light2 && _cone_light1:
		_cone_light2.rotation = _cone_light1.rotation + cone_offset

# Day/Night cycle integration
func _on_day_night_time_changed(time: float) -> void:
	if !auto_toggle_with_daylight:
		return
		
	# Check if light should be on based on time
	if turn_on_time < turn_off_time:
		# Simple case: turn on in evening, off in morning
		if time >= turn_on_time || time < turn_off_time:
			turn_on()
		else:
			turn_off()
	else:
		# Complex case: on spans midnight
		if time >= turn_on_time || time < turn_off_time:
			turn_on()
		else:
			turn_off()

func _cleanup_emergency_lights() -> void:
	if _cone_light1:
		_cone_light1.queue_free()
		_cone_light1 = null
	if _cone_light2:
		_cone_light2.queue_free()
		_cone_light2 = null
	if _ambient_light:
		_ambient_light.queue_free()
		_ambient_light = null

func force_on(override: bool = true) -> void:
	"""Force the light to stay on regardless of entity culling"""
	_manual_override = override
	if override:
		_should_be_active = true
		_update_actual_light_state()

func force_off() -> void:
	"""Remove manual override and return to normal culling behavior"""
	_manual_override = false
