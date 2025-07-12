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
@export_group("Shadow Properties")
@export var cast_shadows: bool = true:
	set(value):
		cast_shadows = value
		shadow_enabled = cast_shadows
		if _ambient_light:
			_ambient_light.shadow_enabled = cast_shadows
		if _cone_light1:
			_cone_light1.shadow_enabled = cast_shadows
		if _cone_light2:
			_cone_light2.shadow_enabled = cast_shadows
		
@export var shadow_smoothness: float = 5.0:
	set(value):
		shadow_smoothness = value
		shadow_filter_smooth = shadow_smoothness
		if _ambient_light:
			_ambient_light.shadow_filter_smooth = shadow_smoothness
		if _cone_light1:
			_cone_light1.shadow_filter_smooth = shadow_smoothness
		if _cone_light2:
			_cone_light2.shadow_filter_smooth = shadow_smoothness
		
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

# Performance settings
@export_group("Performance")
@export var is_static: bool = false
@export var light_quality: int = 80
@export var update_interval: float = 0.05
@export var disable_when_offscreen: bool = true
@export var shadow_distance: float = 250.0
@export var auto_bake_on_ready: bool = false
@export var baked_light_texture: Texture2D

# Day/Night Cycle Integration
@export_group("Day/Night Cycle")
@export var auto_toggle_with_daylight: bool = false
@export var turn_on_time: float = 18.0  # 24-hour format (6:00 PM)
@export var turn_off_time: float = 6.0   # 24-hour format (6:00 AM)

# Internal variables
var _flicker_time: float = 0.0
var _base_energy: float
var _is_baked: bool = false
var _original_texture: Texture2D
var _light_map_node: Sprite2D
var _time: float = 0.0
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
	
	# Bake light if requested
	if auto_bake_on_ready && is_static && light_mode == LightMode.WALL_LIGHT:
		call_deferred("bake_light")
	
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
	# Skip processing if in editor or baked
	if Engine.is_editor_hint() || (_is_baked && light_mode == LightMode.WALL_LIGHT):
		return
	
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
	# Update light visibility
	visible = is_active
	enabled = is_active
	
	if light_mode == LightMode.WALL_LIGHT:
		# Update sprites if they exist
		if sprite_on:
			sprite_on.visible = is_active
		if sprite_off:
			sprite_off.visible = not is_active
		
		# Update glow effect if it exists
		if has_node("GlowEffect"):
			$GlowEffect.visible = use_glow and is_active
	
	elif light_mode == LightMode.EMERGENCY_LIGHT:
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

# Light baking functionality (only for Wall Light mode)
func bake_light() -> void:
	if light_mode != LightMode.WALL_LIGHT:
		push_warning("Light baking is only available for Wall Light mode.")
		return
		
	if !is_static:
		push_warning("Attempting to bake a non-static light. Set 'is_static' to true first.")
		return
	
	if _is_baked:
		push_warning("Light already baked.")
		return
	
	var viewport = SubViewport.new()
	viewport.size = Vector2(light_range * 2, light_range * 2)
	viewport.transparent_bg = true
	
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	
	# Create a duplicate of this light for the viewport
	var temp_light = duplicate()
	temp_light.position = Vector2(light_range, light_range)
	
	# Add to the scene temporarily
	viewport.add_child(temp_light)
	get_tree().root.add_child(viewport)
	
	# Wait for the viewport to render
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Get the rendered texture
	var img = viewport.get_texture().get_image()
	var tex = ImageTexture.create_from_image(img)
	
	# Create or get light map node
	if !_light_map_node:
		_light_map_node = Sprite2D.new()
		_light_map_node.name = "BakedLight"
		_light_map_node.centered = true
		add_child(_light_map_node)
	
	# Apply the baked texture
	_light_map_node.texture = tex
	_light_map_node.modulate = light_color
	_light_map_node.modulate.a = energy
	baked_light_texture = tex
	
	# Disable the dynamic light
	enabled = false
	_is_baked = true
	
	var node_name = name.replace(" ", "_")
	var file_path = "user://baked_light_" + node_name + ".res"
	
	# Store the baked texture for later use
	ResourceSaver.save(tex, file_path)
	
	# Clean up
	viewport.queue_free()
	
	print("Light baked successfully!")

# Use a pre-baked texture
func use_baked_texture(texture_path: String = "") -> void:
	if light_mode != LightMode.WALL_LIGHT:
		push_warning("Baked textures are only available for Wall Light mode.")
		return
		
	if texture_path.is_empty() && baked_light_texture:
		# Use the assigned texture
		_apply_baked_texture(baked_light_texture)
	elif !texture_path.is_empty():
		# Load and apply the texture
		var tex = load(texture_path)
		if tex:
			_apply_baked_texture(tex)
		else:
			push_error("Failed to load baked texture from: " + texture_path)

func _apply_baked_texture(tex: Texture2D) -> void:
	if !_light_map_node:
		_light_map_node = Sprite2D.new()
		_light_map_node.name = "BakedLight"
		_light_map_node.centered = true
		add_child(_light_map_node)
	
	_light_map_node.texture = tex
	_light_map_node.modulate = light_color
	_light_map_node.modulate.a = energy
	
	# Disable the dynamic light
	enabled = false
	_is_baked = true

# Utility to batch bake all static lights in a scene
static func bake_all_static_lights(root_node: Node) -> void:
	var lights = []
	_find_all_static_lights(root_node, lights)
	
	print("Found " + str(lights.size()) + " static lights to bake")
	
	for light in lights:
		if light is AdvancedLight && light.light_mode == LightMode.WALL_LIGHT:
			light.bake_light()
			# Wait a bit between bakes to avoid overloading
			await light.get_tree().create_timer(0.1).timeout

static func _find_all_static_lights(node: Node, result: Array) -> void:
	if node is AdvancedLight && node.is_static:
		result.append(node)
	
	for child in node.get_children():
		_find_all_static_lights(child, result)
