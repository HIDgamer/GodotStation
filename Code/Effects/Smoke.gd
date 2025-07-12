extends GPUParticles2D

# Constants
const DEFAULT_LIFETIME = 15.0
const DEFAULT_AMOUNT = 400
const DEFAULT_RADIUS = 200.0

# Variables
var smoke_lifetime = DEFAULT_LIFETIME
var smoke_radius = DEFAULT_RADIUS
var smoke_color = Color(0.7, 0.7, 0.7, 0.85)  # Consistent grey with higher opacity

func _ready():
	# Set high z-index to ensure smoke renders above other entities
	z_index = 100
	z_as_relative = false
	
	# Set up basic properties
	emitting = false
	one_shot = false  # Continuous emission
	explosiveness = 0.3  # Some bursting
	randomness = 0.6  # Slightly more randomness
	lifetime = smoke_lifetime
	amount = DEFAULT_AMOUNT
	
	# Make sure we have a process material
	if not process_material:
		setup_particle_material()
	else:
		# Update existing material
		update_material_properties()
	
	# Set up tendrils if they exist
	setup_tendrils()
	
	# Set up distortion effect
	setup_distortion()
	
	# Play smoke sound if present
	if has_node("SmokeSound"):
		$SmokeSound.play()
	
	# Connect timer timeout if present
	if has_node("Timer"):
		$Timer.wait_time = smoke_lifetime
		$Timer.start()

# Set up the particle material if needed
func setup_particle_material():
	var material = ParticleProcessMaterial.new()
	
	# Emission settings
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = smoke_radius * 0.3  # Larger initial emission size
	
	# Movement
	material.direction = Vector3(0, -1, 0)
	material.spread = 180.0
	material.gravity = Vector3(0, -4, 0)  # Slightly stronger upward drift
	material.initial_velocity_min = 10.0
	material.initial_velocity_max = 25.0
	
	# Randomize movement
	material.angular_velocity_min = -4.0
	material.angular_velocity_max = 4.0
	material.linear_accel_min = -1.5
	material.linear_accel_max = 1.5
	material.radial_accel_min = -1.0
	material.radial_accel_max = 1.0
	material.tangential_accel_min = -1.0
	material.tangential_accel_max = 1.0
	material.damping_min = 0.8
	material.damping_max = 2.5
	
	# Size
	material.scale_min = 0.8
	material.scale_max = 3.0
	
	# Scale over lifetime (start small, grow, then shrink)
	var curve = Curve.new()
	curve.add_point(Vector2(0, 0.2))    # Start small
	curve.add_point(Vector2(0.3, 1.2))   # Grow to full size plus extra
	curve.add_point(Vector2(0.7, 1.4))   # Slight expansion
	curve.add_point(Vector2(1, 0.7))    # Shrink at end
	
	var scale_curve = CurveTexture.new()
	scale_curve.curve = curve
	material.scale_curve = scale_curve
	
	# Color and transparency
	material.color = smoke_color
	
	var gradient = Gradient.new()
	gradient.add_point(0, Color(smoke_color.r, smoke_color.g, smoke_color.b, 0.0))  # Start transparent
	gradient.add_point(0.1, Color(smoke_color.r, smoke_color.g, smoke_color.b, smoke_color.a * 0.9))  # Fade in
	gradient.add_point(0.7, Color(smoke_color.r, smoke_color.g, smoke_color.b, smoke_color.a))  # Hold opacity
	gradient.add_point(1.0, Color(smoke_color.r, smoke_color.g, smoke_color.b, 0.0))  # Fade out
	
	var gradient_texture = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	
	material.color_ramp = gradient_texture
	
	# Set billboarding mode
	material.billboard_mode = 3  # BILLBOARD_ENABLED
	
	# Add turbulence for more realistic smoke movement
	material.turbulence_enabled = true
	material.turbulence_noise_strength = 0.8
	material.turbulence_noise_scale = 3.5
	
	# Apply material
	process_material = material

# Update existing material properties
func update_material_properties():
	if process_material:
		# Update color (ensure it's grey)
		process_material.color = smoke_color
		process_material.hue_variation_min = 0  # No color variation
		process_material.hue_variation_max = 0  # No color variation
		
		# Update turbulence for more realistic movement
		process_material.turbulence_enabled = true
		process_material.turbulence_noise_strength = 0.8
		process_material.turbulence_noise_scale = 3.5
		
		# Ensure emission size is appropriate
		process_material.emission_sphere_radius = smoke_radius * 0.3
		
		# Update color ramp if it exists
		if process_material.color_ramp and process_material.color_ramp.gradient:
			var gradient = process_material.color_ramp.gradient
			# Reset the gradient colors to ensure proper grey smoke
			if gradient.get_point_count() >= 4:
				gradient.set_color(0, Color(smoke_color.r, smoke_color.g, smoke_color.b, 0.0))
				gradient.set_color(1, Color(smoke_color.r, smoke_color.g, smoke_color.b, smoke_color.a * 0.9))
				gradient.set_color(2, Color(smoke_color.r, smoke_color.g, smoke_color.b, smoke_color.a))
				gradient.set_color(3, Color(smoke_color.r, smoke_color.g, smoke_color.b, 0.0))

# Set up tendrils for more realistic smoke
func setup_tendrils():
	if has_node("SmokeTendrils"):
		var tendrils = $SmokeTendrils
		
		# Create 3 tendril particles for more realistic smoke movement
		for i in range(3):
			var tendril = GPUParticles2D.new()
			tendril.name = "Tendril" + str(i)
			tendril.texture = texture  # Use same texture as main smoke
			tendril.amount = 40
			tendril.lifetime = smoke_lifetime * 0.7
			tendril.explosiveness = 0.1
			tendril.randomness = 0.8
			tendril.z_index = z_index - 1  # Slightly behind main smoke
			
			# Create tendril material
			var material = ParticleProcessMaterial.new()
			material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			material.emission_sphere_radius = smoke_radius * 0.4
			material.direction = Vector3(cos(i * 2.0 * PI / 3.0), sin(i * 2.0 * PI / 3.0), 0).normalized()
			material.spread = 30.0
			material.initial_velocity_min = 8.0
			material.initial_velocity_max = 15.0
			material.gravity = Vector3(0, -3, 0)
			material.scale_min = 0.4
			material.scale_max = 1.2
			
			# Tendril color (slightly darker smoke)
			material.color = Color(smoke_color.r * 0.9, smoke_color.g * 0.9, smoke_color.b * 0.9, smoke_color.a * 0.7)
			
			# Opacity curve
			var gradient = Gradient.new()
			gradient.add_point(0, Color(smoke_color.r * 0.9, smoke_color.g * 0.9, smoke_color.b * 0.9, 0.0))
			gradient.add_point(0.2, Color(smoke_color.r * 0.9, smoke_color.g * 0.9, smoke_color.b * 0.9, smoke_color.a * 0.5))
			gradient.add_point(0.8, Color(smoke_color.r * 0.9, smoke_color.g * 0.9, smoke_color.b * 0.9, smoke_color.a * 0.3))
			gradient.add_point(1.0, Color(smoke_color.r * 0.9, smoke_color.g * 0.9, smoke_color.b * 0.9, 0.0))
			
			var gradient_texture = GradientTexture1D.new()
			gradient_texture.gradient = gradient
			material.color_ramp = gradient_texture
			
			# Add turbulence
			material.turbulence_enabled = true
			material.turbulence_noise_strength = 0.5
			material.turbulence_noise_scale = 2.0
			
			tendril.process_material = material
			tendrils.add_child(tendril)
			tendril.emitting = true

# Set up heat distortion effect
func setup_distortion():
	if has_node("HeatDistortion"):
		var distortion = $HeatDistortion
		distortion.modulate = Color(1, 1, 1, 0.15)  # More subtle distortion
		distortion.scale = Vector2(4, 4)  # Larger area

# Set smoke properties from outside
func set_smoke_properties(radius: float, duration: float, color: Color = Color(0.7, 0.7, 0.7, 0.85)):
	smoke_radius = radius
	smoke_lifetime = duration
	smoke_color = color
	
	# Update parameters
	lifetime = smoke_lifetime
	
	# If we already have a timer, update it
	if has_node("Timer"):
		$Timer.wait_time = smoke_lifetime
		$Timer.start()
	
	# Update material if it exists
	if process_material:
		update_material_properties()
	
	# Update amount based on radius for consistent density
	amount = int(DEFAULT_AMOUNT * (radius / DEFAULT_RADIUS))
	amount = clamp(amount, 80, 600)  # Ensure reasonable range
	
	# Re-setup tendrils and distortion
	if has_node("SmokeTendrils"):
		# Clear existing tendrils
		for child in $SmokeTendrils.get_children():
			child.queue_free()
		setup_tendrils()
	
	setup_distortion()

# Handle timer timeout - stop emitting and cleanup
func _on_timer_timeout():
	# Stop emitting new particles
	emitting = false
	
	# Stop emitting tendrils if present
	if has_node("SmokeTendrils"):
		for tendril in $SmokeTendrils.get_children():
			if tendril is GPUParticles2D:
				tendril.emitting = false
	
	# Wait for existing particles to finish, then queue_free
	var cleanup_timer = get_tree().create_timer(lifetime * 0.8)  # Slight extra time
	cleanup_timer.timeout.connect(queue_free)
