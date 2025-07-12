extends ColorRect

# Shockwave effect controller

# Configuration properties
@export var duration: float = 1.0
@export var auto_play: bool = true
@export var auto_free: bool = true
@export var intensity_multiplier: float = 1.0
@export var size_multiplier: float = 1.0
@export var distortion_multiplier: float = 1.0

# State tracking
var playing: bool = false
var elapsed_time: float = 0.0
var total_duration: float = 0.0

# Optional visual components
@onready var ring_glow = $RingGlow if has_node("RingGlow") else null

func _ready():
	# Initialize the effect
	material.set_shader_parameter("custom_time", 0.0)
	
	# Hide by default until played
	visible = false
	
	# Calculate effective duration based on max_radius and wave_speed
	var max_radius = material.get_shader_parameter("max_radius")
	var wave_speed = material.get_shader_parameter("wave_speed")
	total_duration = max_radius / wave_speed
	
	# Apply multipliers
	apply_multipliers()
	
	# Auto-start if configured
	if auto_play:
		play()

func _process(delta):
	if playing:
		elapsed_time += delta
		
		# Update shader time parameter
		material.set_shader_parameter("custom_time", elapsed_time)
		
		# Update ring glow scale
		if ring_glow:
			var progress = min(elapsed_time / total_duration, 1.0)
			ring_glow.scale = Vector2(progress, progress) * 2.0 * size_multiplier
			ring_glow.modulate.a = max(0.3 * (1.0 - progress), 0.0)
		
		# Check if effect is complete
		if elapsed_time >= total_duration:
			on_complete()

# Start playing the effect
func play():
	if playing:
		return
		
	playing = true
	elapsed_time = 0.0
	visible = true
	
	# Reset ring scale
	if ring_glow:
		ring_glow.scale = Vector2(0.1, 0.1)
		ring_glow.modulate.a = 0.3

# Apply intensity multipliers to shader parameters
func apply_multipliers():
	# Adjust wave intensity
	var base_intensity = material.get_shader_parameter("wave_intensity")
	material.set_shader_parameter("wave_intensity", base_intensity * intensity_multiplier)
	
	# Adjust max radius (size)
	var base_radius = material.get_shader_parameter("max_radius")
	material.set_shader_parameter("max_radius", base_radius * size_multiplier)
	
	# Adjust distortion intensity
	var base_distortion = material.get_shader_parameter("distortion_intensity")
	material.set_shader_parameter("distortion_intensity", base_distortion * distortion_multiplier)
	
	# Update duration based on new values
	var max_radius = material.get_shader_parameter("max_radius")
	var wave_speed = material.get_shader_parameter("wave_speed")
	total_duration = max_radius / wave_speed

# Handle effect completion
func on_complete():
	playing = false
	visible = false
	
	# Free the node if auto_free is enabled
	if auto_free:
		queue_free()

# Configure the effect
func configure(new_intensity: float = 1.0, new_size: float = 1.0, new_distortion: float = 1.0):
	intensity_multiplier = new_intensity
	size_multiplier = new_size
	distortion_multiplier = new_distortion
	
	apply_multipliers()
	
	return self  # Allow method chaining

# Customize color effect
func set_wave_color(color: Color):
	material.set_shader_parameter("wave_color", color)
	
	if ring_glow:
		ring_glow.modulate = Color(color.r, color.g, color.b, 0.3)
	
	return self  # Allow method chaining

# Set the wave speed
func set_wave_speed(speed: float):
	material.set_shader_parameter("wave_speed", speed)
	
	# Update duration
	var max_radius = material.get_shader_parameter("max_radius")
	total_duration = max_radius / speed
	
	return self  # Allow method chaining

# Set wave thickness
func set_wave_thickness(thickness: float):
	material.set_shader_parameter("wave_thickness", thickness)
	return self  # Allow method chaining

# Utility function to create and play shockwave at a position
static func create_at_position(position: Vector2, parent_node: Node, size: float = 1.0, intensity: float = 1.0):
	var shockwave = preload("res://Scenes/Effects/Shockwave.tscn").instantiate()
	parent_node.add_child(shockwave)
	
	# Center on position
	shockwave.global_position = position - shockwave.size / 2
	
	# Configure and play
	shockwave.configure(intensity, size, intensity)
	shockwave.play()
	
	return shockwave
