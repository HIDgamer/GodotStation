extends Camera2D
class_name RevampedPlayerCamera

# ===== Basic Camera Parameters =====
@export var target_path: NodePath
@export_group("Movement Settings")
@export var camera_speed: float = 3.0  # Lower = smoother but slower
@export var camera_easing: Tween.EaseType = Tween.EASE_OUT
@export var camera_transition: Tween.TransitionType = Tween.TRANS_SINE
@export var deadzone_size: Vector2 = Vector2(10, 10)  # Small deadzone to prevent micro-movements

@export_group("Zoom Settings")
@export var zoom_speed: float = 3.0  # Reduced for smoother zooming
@export var default_zoom: Vector2 = Vector2(1.0, 1.0)
@export var min_zoom: float = 0.5
@export var max_zoom: float = 3.0

# ===== Anti-Motion Sickness Options =====
@export_group("Comfort Settings")
@export var reduced_motion_mode: bool = false  # Option for players prone to motion sickness
@export var reduced_effects_strength: float = 0.5  # How much to reduce effects (0-1)
@export var steady_cam: bool = false  # Ultra-stable camera with minimal movements

# ===== Camera Effects =====
@export_group("Effects")
@export var enable_screen_shake: bool = true
@export var enable_static_effect: bool = true
@export var enable_emp_effect: bool = true
@export var enable_room_based_limits: bool = true
@export var enable_smooth_transitions: bool = true

# ===== Advanced Effects =====
@export_group("Screen Shake")
@export var trauma_reduction_rate: float = 1.2  # Faster trauma reduction
@export var max_trauma: float = 1.0  
@export var max_shake_offset: Vector2 = Vector2(70, 50)  # Reduced maximum shake
@export var max_shake_rotation: float = 0.05  # Reduced maximum rotation
@export var noise_shake_speed: float = 20.0  # Slower noise movement
@export var noise_shake_strength: float = 40.0  # Reduced strength
@export var trauma_exponent: float = 2.0  # Higher = more easing (2.0 = quadratic falloff)

@export_group("Look Ahead")
@export var look_ahead_factor: float = 0.1  # Reduced for less movement
@export var max_look_ahead: float = 80.0  # Cap maximum look-ahead distance
@export var look_ahead_smoothing: float = 0.15  # Smooths look-ahead changes
@export var mouse_look_ahead_factor: float = 0.1  # Reduced from original
@export var enable_mouse_influence: bool = true
@export var mouse_deadzone: float = 0.1  # Ignore small mouse movements

# ===== Visual Effects =====
@export_group("Visual Effects")
@export var static_intensity_max: float = 0.5  # Reduced maximum static
@export var static_fade_speed: float = 0.8  # How quickly static fades
@export var vignette_intensity_max: float = 0.7  # Maximum vignette darkness
@export var vignette_smoothness: float = 0.3  # Vignette edge softness

# ===== References =====
@onready var noise: FastNoiseLite = FastNoiseLite.new()
@onready var static_overlay: ColorRect = $StaticOverlay if has_node("StaticOverlay") else null
@onready var vignette_overlay: ColorRect = $VignetteOverlay if has_node("VignetteOverlay") else null
@onready var transition_rect: ColorRect = $TransitionRect if has_node("TransitionRect") else null
@onready var animation_player: AnimationPlayer = $AnimationPlayer if has_node("AnimationPlayer") else null
@onready var blur_effect: ColorRect = $BlurEffect if has_node("BlurEffect") else null

# ===== Runtime variables =====
var target: Node2D = null
var trauma: float = 0.0  # Current trauma value (0-1)
var target_zoom: Vector2 = Vector2.ONE
var static_intensity: float = 0.0
var static_noise_time: float = 0.0
var current_room_limits: Rect2 = Rect2()
var previous_target_position: Vector2 = Vector2.ZERO
var target_velocity: Vector2 = Vector2.ZERO
var filtered_velocity: Vector2 = Vector2.ZERO  # Smoothed velocity
var velocity_history: Array[Vector2] = []
var target_room: Node2D = null
var is_transitioning: bool = false
var is_emp_affected: bool = false
var emp_timer: float = 0.0
var emp_duration: float = 0.0
var vacuum_exposure: bool = false
var oxygen_level: float = 1.0
var current_look_ahead: Vector2 = Vector2.ZERO  # Smoothed look ahead
var desired_position: Vector2 = Vector2.ZERO
var last_stable_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Initialize noise for screen shake with better frequency settings
	noise.seed = randi()
	noise.frequency = 0.3  # Lower frequency for smoother noise
	noise.fractal_octaves = 3  # Adds more detail to the noise
	
	# Setup camera properties
	position_smoothing_enabled = true
	position_smoothing_speed = camera_speed
	
	# Optional: enable drag margins for more dynamic movement
	drag_horizontal_enabled = false
	drag_vertical_enabled = false
	
	# Initialize target
	if target_path:
		target = get_node(target_path)
		if target:
			previous_target_position = target.global_position
			last_stable_position = target.global_position
	
	# Initialize static effect shader
	if static_overlay:
		_setup_static_shader()
	
	# Initialize vignette shader
	if vignette_overlay:
		_setup_vignette_shader()
		
	# Initialize blur effect
	if blur_effect:
		_setup_blur_shader()
	
	# Set default zoom
	zoom = default_zoom
	target_zoom = default_zoom
	
	# Initialize velocity history buffer for smoother velocity calculations
	velocity_history.resize(5)
	for i in range(velocity_history.size()):
		velocity_history[i] = Vector2.ZERO
	
	# Initialize room detection
	if enable_room_based_limits:
		detect_current_room()

func _process(delta: float) -> void:
	if target == null:
		return
	
	# Apply reduced motion settings if enabled
	var effect_multiplier = 1.0
	if reduced_motion_mode:
		effect_multiplier = reduced_effects_strength
	
	# Calculate target velocity with smoothing
	calculate_smooth_velocity(delta)
	
	# Follow target with improved look-ahead
	if !is_transitioning:
		follow_target_smoothly(delta, effect_multiplier)
	
	# Handle zoom with easing
	handle_zoom_smoothly(delta)
	
	# Apply screen shake if enabled, with anti-motion sickness options
	if enable_screen_shake and !steady_cam:
		apply_improved_screen_shake(delta, effect_multiplier)
	else:
		# Reset shake effects when disabled
		offset = Vector2.ZERO
		rotation = 0.0
	
	# Apply static effect if enabled
	if enable_static_effect:
		apply_static_effect(delta, effect_multiplier)
	
	# Handle EMP effects with reduced intensity option
	if enable_emp_effect and is_emp_affected:
		handle_emp_effect(delta, effect_multiplier)
	
	# Update room detection
	if enable_room_based_limits:
		update_room_detection(delta)
	
	# Handle environmental effects
	handle_environmental_effects(delta, effect_multiplier)

func calculate_smooth_velocity(delta: float) -> void:
	# Calculate raw velocity
	var raw_velocity = (target.global_position - previous_target_position) / delta
	previous_target_position = target.global_position
	
	# Add to velocity history
	velocity_history.pop_back()
	velocity_history.push_front(raw_velocity)
	
	# Calculate weighted average (more weight to recent velocities)
	filtered_velocity = Vector2.ZERO
	var total_weight = 0.0
	for i in range(velocity_history.size()):
		var weight = velocity_history.size() - i
		filtered_velocity += velocity_history[i] * weight
		total_weight += weight
	
	if total_weight > 0:
		filtered_velocity /= total_weight
	
	# Apply deadzone to prevent micro-movements
	if filtered_velocity.length() < 5.0:
		filtered_velocity = Vector2.ZERO
	
	# Store for use in other functions
	target_velocity = filtered_velocity

func follow_target_smoothly(delta: float, effect_multiplier: float = 1.0) -> void:
	if target == null:
		return
	
	var target_pos = target.global_position
	
	# Store the last stable position when the target isn't moving much
	if target_velocity.length() < 10.0:
		last_stable_position = lerp(last_stable_position, target_pos, delta * 3.0)
	
	# Apply deadzone to prevent micro-movements
	var offset_from_last_position = target_pos - global_position
	if offset_from_last_position.length() < deadzone_size.length() and !steady_cam:
		# Target is basically in the same place, don't move the camera
		return
	
	# Calculate velocity-based look-ahead with smoothing and clamping
	var desired_look_ahead = Vector2.ZERO
	if !steady_cam:
		var normalized_velocity = target_velocity.normalized()
		var velocity_length = target_velocity.length()
		
		# Apply non-linear scaling to velocity for look-ahead (sqrt for less aggressive scaling)
		var scaled_velocity = sqrt(velocity_length) * normalized_velocity
		var raw_look_ahead = scaled_velocity * look_ahead_factor * effect_multiplier
		
		# Clamp look-ahead to maximum distance
		if raw_look_ahead.length() > max_look_ahead:
			raw_look_ahead = raw_look_ahead.normalized() * max_look_ahead
		
		desired_look_ahead = raw_look_ahead
		
		# Add mouse-based look-ahead if enabled
		if enable_mouse_influence:
			var mouse_pos = get_viewport().get_mouse_position()
			var screen_center = get_viewport_rect().size / 2
			var mouse_offset = (mouse_pos - screen_center) / zoom
			
			# Apply deadzone to mouse influence
			if mouse_offset.length() > screen_center.length() * mouse_deadzone:
				# Limit the mouse influence distance
				var max_mouse_distance = 150.0
				if mouse_offset.length() > max_mouse_distance:
					mouse_offset = mouse_offset.normalized() * max_mouse_distance
				
				desired_look_ahead += mouse_offset * mouse_look_ahead_factor * effect_multiplier
	
	# Smooth the look-ahead changes to prevent jarring camera movements
	current_look_ahead = current_look_ahead.lerp(desired_look_ahead, delta * (1.0 / look_ahead_smoothing))
	
	# Set the target position with smoothed look-ahead
	desired_position = target_pos + current_look_ahead
	
	# Apply room limits if enabled
	if enable_room_based_limits and current_room_limits != Rect2():
		# Get half viewport size adjusted for zoom
		var half_viewport = get_viewport_rect().size / (2.0 * zoom)
		
		# Apply limits with margin for viewport size
		desired_position.x = clamp(
			desired_position.x,
			current_room_limits.position.x + half_viewport.x,
			current_room_limits.end.x - half_viewport.x
		)
		desired_position.y = clamp(
			desired_position.y,
			current_room_limits.position.y + half_viewport.y,
			current_room_limits.end.y - half_viewport.y
		)
	
	# Let built-in smoothing handle the actual movement to the desired position
	global_position = desired_position

func handle_zoom_smoothly(delta: float) -> void:
	# Interpolate current zoom toward target zoom with easing
	var zoom_change = target_zoom - zoom
	
	# Apply non-linear easing to zoom changes (feels more natural)
	var eased_zoom_change = zoom_change * (1.0 - exp(-zoom_speed * delta))
	zoom += eased_zoom_change

func apply_improved_screen_shake(delta: float, effect_multiplier: float = 1.0) -> void:
	# Reduce trauma over time with configurable rate
	trauma = max(trauma - delta * trauma_reduction_rate, 0.0)
	
	if trauma > 0.0:
		# Calculate shake intensity with configurable exponent for more natural feel
		var shake_intensity = pow(trauma, trauma_exponent) * effect_multiplier
		
		# Use noise to create smooth random shake with better frequency control
		var time = Time.get_ticks_msec() / 1000.0
		
		# Add some randomness to the shake directions for more organic feel
		var noise_x = noise.get_noise_2d(time * noise_shake_speed, 0) 
		var noise_y = noise.get_noise_2d(0, time * noise_shake_speed)
		var noise_r = noise.get_noise_2d(time * noise_shake_speed * 0.8, time * noise_shake_speed * 0.8)
		
		# Apply non-linear transformation to make shake feel more natural
		noise_x = sign(noise_x) * pow(abs(noise_x), 0.8)
		noise_y = sign(noise_y) * pow(abs(noise_y), 0.8)
		
		# Apply shake to camera
		offset.x = noise_x * shake_intensity * max_shake_offset.x
		offset.y = noise_y * shake_intensity * max_shake_offset.y
		rotation = noise_r * shake_intensity * max_shake_rotation
	else:
		# Reset camera offset and rotation when no trauma
		offset = offset.lerp(Vector2.ZERO, delta * 10.0)  # Smooth reset
		rotation = lerp(rotation, 0.0, delta * 10.0)  # Smooth reset

func _setup_static_shader() -> void:
	static_overlay.material = ShaderMaterial.new()
	static_overlay.material.shader = load("res://Assets/Godot Resources/static_shader.gdshader")
	if not ResourceLoader.exists("res://Assets/Godot Resources/static_shader.gdshader"):
		# Create the shader if it doesn't exist
		print("Static shader not found. Please create it using the provided code.")
	
	# Set initial shader parameters
	static_overlay.material.set_shader_parameter("static_intensity", 0.0)
	static_overlay.material.set_shader_parameter("noise_speed", 30.0)
	static_overlay.material.set_shader_parameter("noise_quality", 3.0)
	static_overlay.material.set_shader_parameter("static_scale", 1.0)

func _setup_vignette_shader() -> void:
	vignette_overlay.material = ShaderMaterial.new()
	vignette_overlay.material.shader = load("res://Assets/Godot Resources/vignette_shader.gdshader")
	if not ResourceLoader.exists("res://Assets/Godot Resources/vignette_shader.gdshader"):
		print("Vignette shader not found. Please create it using the provided code.")
	
	# Set initial shader parameters
	vignette_overlay.material.set_shader_parameter("vignette_intensity", 0.0)
	vignette_overlay.material.set_shader_parameter("vignette_smoothness", vignette_smoothness)
	vignette_overlay.material.set_shader_parameter("vignette_color", Color(0.0, 0.0, 0.0, 1.0))

func _setup_blur_shader() -> void:
	blur_effect.material = ShaderMaterial.new()
	blur_effect.material.shader = load("res://Assets/Godot Resources/gaussian_blur.gdshader")
	if not ResourceLoader.exists("res://Assets/Godot Resources/gaussian_blur.gdshader"):
		print("Blur shader not found. Please create it using the provided code.")
	
	# Set initial shader parameters
	blur_effect.material.set_shader_parameter("blur_amount", 0.0)
	blur_effect.visible = false

func apply_static_effect(delta: float, effect_multiplier: float = 1.0) -> void:
	if static_overlay == null:
		return
	
	# Update static noise time
	static_noise_time += delta
	
	# Apply the static intensity to the shader
	if static_overlay.material:
		static_overlay.material.set_shader_parameter("static_intensity", static_intensity * effect_multiplier)
		static_overlay.material.set_shader_parameter("time", static_noise_time)
	
	# Gradually reduce static effect unless affected by EMP
	if !is_emp_affected:
		static_intensity = max(static_intensity - delta * static_fade_speed, 0.0)

func handle_emp_effect(delta: float, effect_multiplier: float = 1.0) -> void:
	# Update EMP timer
	emp_timer += delta
	
	if emp_timer >= emp_duration:
		# EMP effect ends
		is_emp_affected = false
		emp_timer = 0.0
	else:
		# Apply EMP effects with reduced intensity
		var emp_strength = effect_multiplier
		
		# 1. Random static with smoother transitions
		var target_static = randf_range(0.3, static_intensity_max) * emp_strength
		static_intensity = lerp(static_intensity, target_static, delta * 3.0)
		
		# 2. Random zoom changes, less frequent and less extreme
		if randf() < 0.03 * emp_strength:  # Reduced chance for zoom change
			var random_zoom = randf_range(0.9, 1.1)  # Less extreme zoom
			target_zoom = default_zoom * random_zoom
		
		# 3. Random offset jumps with smoother transitions
		if randf() < 0.01 * emp_strength:  # Reduced chance for offset jump
			var target_offset = Vector2(
				randf_range(-20, 20),
				randf_range(-20, 20)
			) * emp_strength
			
			# Create a tween for smoother transition to the random offset
			var tween = create_tween()
			tween.tween_property(self, "offset", target_offset, 0.1)
			tween.tween_property(self, "offset", Vector2.ZERO, 0.3)

func update_room_detection(delta: float) -> void:
	# Check if player has changed rooms
	var new_room = detect_current_room()
	
	if new_room != target_room and new_room != null:
		# Room transition
		if enable_smooth_transitions and !is_transitioning:
			transition_to_room(new_room)
		else:
			# Immediate transition
			target_room = new_room
			update_camera_limits_for_room(new_room)

func detect_current_room() -> Node2D:
	# This is a placeholder implementation
	# In a real game, you'd want to detect which room the player is in
	# based on collision layers, area2D detection, etc.
	
	# Look for rooms (assuming they have a group "room")
	var rooms = get_tree().get_nodes_in_group("room")
	for room in rooms:
		if room is Node2D and room.has_method("contains_point"):
			if room.contains_point(target.global_position):
				return room
	
	return null

func update_camera_limits_for_room(room: Node2D) -> void:
	# Get room boundaries (assuming room has a method to provide its bounds)
	if room.has_method("get_bounds"):
		current_room_limits = room.get_bounds()
		
		# Apply limits to camera with smoothing
		limit_left = int(current_room_limits.position.x)
		limit_top = int(current_room_limits.position.y)
		limit_right = int(current_room_limits.end.x)
		limit_bottom = int(current_room_limits.end.y)
		
		# Enable limits with smoothing
		limit_smoothed = true

func transition_to_room(new_room: Node2D) -> void:
	is_transitioning = true
	
	# Apply blur during transition
	if blur_effect:
		blur_effect.visible = true
		var blur_tween = create_tween()
		blur_tween.tween_property(blur_effect.material, "shader_parameter/blur_amount", 2.0, 0.3)
	
	# Start transition animation
	if animation_player and animation_player.has_animation("room_transition"):
		animation_player.play("room_transition")
		await animation_player.animation_finished
	else:
		# Create a fade transition if no animation is available
		if transition_rect:
			transition_rect.modulate.a = 0
			var fade_in = create_tween()
			fade_in.tween_property(transition_rect, "modulate:a", 1.0, 0.3)
			await fade_in.finished
			
			# Update the target room and limits
			target_room = new_room
			update_camera_limits_for_room(new_room)
			
			var fade_out = create_tween()
			fade_out.tween_property(transition_rect, "modulate:a", 0.0, 0.3)
			await fade_out.finished
		else:
			# Simple delay if no transition rect
			await get_tree().create_timer(0.3).timeout
			target_room = new_room
			update_camera_limits_for_room(new_room)
	
	# Remove blur after transition
	if blur_effect:
		var blur_tween = create_tween()
		blur_tween.tween_property(blur_effect.material, "shader_parameter/blur_amount", 0.0, 0.3)
		await blur_tween.finished
		blur_effect.visible = false
	
	is_transitioning = false

func handle_environmental_effects(delta: float, effect_multiplier: float = 1.0) -> void:
	# Handle oxygen level effects on camera
	if vacuum_exposure:
		# Gradually reduce oxygen level in vacuum
		oxygen_level = max(oxygen_level - delta * 0.1, 0.0)
	else:
		# Gradually restore oxygen level
		oxygen_level = min(oxygen_level + delta * 0.2, 1.0)
	
	# Apply oxygen level effects
	apply_oxygen_effects(oxygen_level, delta, effect_multiplier)

func apply_oxygen_effects(oxygen_level: float, delta: float, effect_multiplier: float = 1.0) -> void:
	# Apply vignette effect based on oxygen level
	if vignette_overlay and vignette_overlay.material:
		var target_intensity = (1.0 - oxygen_level) * vignette_intensity_max * effect_multiplier
		var current_intensity = vignette_overlay.material.get_shader_parameter("vignette_intensity")
		
		# Smoothly transition vignette intensity
		var new_intensity = lerp(current_intensity, target_intensity, delta * 2.0)
		vignette_overlay.material.set_shader_parameter("vignette_intensity", new_intensity)
	
	# Apply subtle zoom and shake at low oxygen
	if oxygen_level < 0.5:
		# Subtle zoom out to simulate tunnel vision, less extreme with reduced motion
		var oxygen_zoom_factor = 1.0 - ((0.5 - oxygen_level) * 0.2 * effect_multiplier)
		target_zoom = default_zoom * oxygen_zoom_factor
		
		# Add slight trauma for dizziness, reduced with reduced motion
		if oxygen_level < 0.3 and !steady_cam:
			add_trauma(0.05 * delta * effect_multiplier)

# ===== Public methods to interact with the camera system =====

func add_trauma(amount: float) -> void:
	# Add screen shake trauma, clamped to max_trauma
	trauma = min(trauma + amount, max_trauma)

func set_static(amount: float) -> void:
	# Set static effect intensity (0-1)
	static_intensity = clamp(amount, 0.0, 1.0)

func apply_emp(duration: float, intensity: float = 1.0) -> void:
	# Trigger an EMP effect
	is_emp_affected = true
	emp_duration = duration
	emp_timer = 0.0
	static_intensity = clamp(intensity, 0.0, static_intensity_max)
	add_trauma(0.3 * intensity)  # Reduced trauma compared to original

func set_zoom_level(level: float) -> void:
	# Set a new zoom level, clamped between min and max
	var new_zoom = clamp(level, min_zoom, max_zoom)
	target_zoom = Vector2(new_zoom, new_zoom)

func set_vacuum_exposure(exposed: bool) -> void:
	# Set whether the player is exposed to vacuum
	vacuum_exposure = exposed

func focus_on_position(global_pos: Vector2, duration: float = 1.0) -> void:
	# Temporarily focus the camera on a specific position with smooth transitions
	var original_target = target
	var original_position = global_position
	
	# Disable following temporarily
	target = null
	
	# Create a tween for smooth movement
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "global_position", global_pos, duration * 0.4)
	
	# Wait before returning to player
	await tween.finished
	await get_tree().create_timer(duration * 0.2).timeout
	
	# Return to player with another tween
	var tween2 = create_tween()
	tween2.set_trans(Tween.TRANS_SINE)
	tween2.set_ease(Tween.EASE_IN_OUT)
	tween2.tween_property(self, "global_position", original_target.global_position, duration * 0.4)
	
	# Re-enable following
	await tween2.finished
	target = original_target

func shake_camera(intensity: float, duration: float = 0.5) -> void:
	# Create a sustained shake with smoother falloff
	add_trauma(intensity)
	
	# Create a tween to add and then smoothly reduce trauma
	var tween = create_tween()
	tween.tween_method(func(t): add_trauma(intensity * (1.0 - t) * 0.2), 0.0, 1.0, duration)

func toggle_reduced_motion_mode(enable: bool) -> void:
	# Allow turning reduced motion mode on/off
	reduced_motion_mode = enable

func toggle_steady_cam(enable: bool) -> void:
	# Allow turning ultra-stable camera mode on/off
	steady_cam = enable
	if steady_cam:
		# Reset effects when enabling steady cam
		trauma = 0.0
		offset = Vector2.ZERO
		rotation = 0.0

# Helper function to reset camera to defaults
func reset_to_defaults() -> void:
	target_zoom = default_zoom
	trauma = 0.0
	static_intensity = 0.0
	offset = Vector2.ZERO
	rotation = 0.0
	is_emp_affected = false
	vacuum_exposure = false
	oxygen_level = 1.0
	current_look_ahead = Vector2.ZERO
