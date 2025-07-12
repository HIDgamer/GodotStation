extends GPUParticles2D
class_name FlashEffect

# Flash effect constants
const DEFAULT_FLASH_LIFETIME = 0.5
const DEFAULT_FLASH_INTENSITY = 5.0
const DEFAULT_FLASH_RADIUS = 300.0
const DEFAULT_DURATION_MULTIPLIER = 1.0

# Properties
var flash_lifetime = DEFAULT_FLASH_LIFETIME
var flash_intensity = DEFAULT_FLASH_INTENSITY
var flash_radius = DEFAULT_FLASH_RADIUS
var duration_multiplier = DEFAULT_DURATION_MULTIPLIER
var flash_color = Color(1.0, 1.0, 1.0, 1.0)
var apply_screen_shake = true

# Component references
var flash_light = null
var shockwave_particles = null
var smoke_particles = null
var ring_particles = null
var secondary_particles = null
var bloom_particles = null
var audio_player = null
var secondary_audio = null

func _ready():
	# Set up main flash particles
	emitting = false
	one_shot = true
	explosiveness = 1.0
	randomness = 0.1
	lifetime = flash_lifetime
	amount = 1
	
	# Check if we have all the necessary components
	setup_visual_components()
	
	# Set up lighting
	setup_lighting()
	
	# Set up audio
	setup_audio()
	
	# Set timeout to clean up
	var timer = Timer.new()
	timer.name = "CleanupTimer"
	timer.wait_time = 4.0 * duration_multiplier
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(queue_free)
	add_child(timer)

# Set up all visual components
func setup_visual_components():
	# Set up flash light
	setup_flash_light()
	
	# Set up shockwave particles
	setup_shockwave_particles()
	
	# Set up smoke particles
	setup_smoke_particles()
	
	# Set up ring particles
	setup_ring_particles()
	
	# Set up secondary particles (new)
	setup_secondary_particles()
	
	# Set up bloom particles (new)
	setup_bloom_particles()

# Set up flash light
func setup_flash_light():
	flash_light = get_node_or_null("FlashLight")
	if flash_light:
		flash_light.energy = flash_intensity
		flash_light.color = flash_color
		flash_light.texture_scale = flash_radius / DEFAULT_FLASH_RADIUS * 5.0
		
		# Setup light animation
		var tween = create_tween()
		tween.tween_property(flash_light, "energy", 0.0, flash_lifetime * 2.0 * duration_multiplier)
	else:
		# Create new flash light
		flash_light = PointLight2D.new()
		flash_light.name = "FlashLight"
		flash_light.energy = flash_intensity
		flash_light.color = flash_color
		flash_light.shadow_enabled = true
		flash_light.shadow_filter = 1
		flash_light.shadow_filter_smooth = 2.0
		flash_light.texture_scale = flash_radius / DEFAULT_FLASH_RADIUS * 5.0
		add_child(flash_light)
		
		# Setup light animation
		var tween = create_tween()
		tween.tween_property(flash_light, "energy", 0.0, flash_lifetime * 2.0 * duration_multiplier)

# Set up shockwave particles
func setup_shockwave_particles():
	shockwave_particles = get_node_or_null("ShockwaveParticles")
	if shockwave_particles:
		shockwave_particles.emitting = false
		shockwave_particles.one_shot = true
		
		# Update lifetime based on duration_multiplier
		shockwave_particles.lifetime = shockwave_particles.lifetime * duration_multiplier
	else:
		# Create new shockwave particles
		shockwave_particles = GPUParticles2D.new()
		shockwave_particles.name = "ShockwaveParticles"
		shockwave_particles.emitting = false
		shockwave_particles.amount = 1
		shockwave_particles.lifetime = flash_lifetime
		shockwave_particles.one_shot = true
		shockwave_particles.explosiveness = 1.0
		add_child(shockwave_particles)
		
		# Create shockwave material
		var material = ParticleProcessMaterial.new()
		
		# Set emission to point
		material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
		
		# No gravity or initial velocity
		material.direction = Vector3(0, 0, 0)
		material.spread = 0.0
		material.gravity = Vector3(0, 0, 0)
		material.initial_velocity_min = 0.0
		material.initial_velocity_max = 0.0
		
		# Scale over lifetime - grow rapidly
		var curve = Curve.new()
		curve.add_point(Vector2(0, 0.2))
		curve.add_point(Vector2(0.2, 2.0))
		curve.add_point(Vector2(1, 15.0))
		
		var scale_curve = CurveTexture.new()
		scale_curve.curve = curve
		material.scale_curve = scale_curve
		
		# Color and transparency
		var gradient = Gradient.new()
		gradient.add_point(0, Color(flash_color.r, flash_color.g, flash_color.b, 0.8))
		gradient.add_point(0.3, Color(flash_color.r, flash_color.g * 0.9, flash_color.b * 0.6, 0.6))
		gradient.add_point(0.7, Color(flash_color.r * 0.9, flash_color.g * 0.6, flash_color.b * 0.3, 0.4))
		gradient.add_point(1, Color(flash_color.r * 0.7, flash_color.g * 0.3, flash_color.b * 0.0, 0.0))
		
		var gradient_texture = GradientTexture1D.new()
		gradient_texture.gradient = gradient
		material.color_ramp = gradient_texture
		
		shockwave_particles.process_material = material

# Set up smoke particles
func setup_smoke_particles():
	smoke_particles = get_node_or_null("SmokeParticles")
	if smoke_particles:
		smoke_particles.emitting = false
		smoke_particles.one_shot = true
		
		# Update lifetime based on duration_multiplier
		smoke_particles.lifetime = smoke_particles.lifetime * duration_multiplier
	else:
		# Create new smoke particles
		smoke_particles = GPUParticles2D.new()
		smoke_particles.name = "SmokeParticles"
		smoke_particles.emitting = false
		smoke_particles.amount = 30
		smoke_particles.lifetime = 3.0
		smoke_particles.one_shot = true
		smoke_particles.explosiveness = 0.8
		smoke_particles.randomness = 0.5
		add_child(smoke_particles)
		
		# Create smoke material
		var material = ParticleProcessMaterial.new()
		
		# Emission settings
		material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		material.emission_sphere_radius = 20.0
		
		# Movement
		material.direction = Vector3(0, -1, 0)
		material.spread = 180.0
		material.gravity = Vector3(0, -10, 0)  # Slight upward drift
		material.initial_velocity_min = 10.0
		material.initial_velocity_max = 30.0
		
		# Add turbulence for more realistic smoke
		material.turbulence_enabled = true
		material.turbulence_noise_strength = 2.0
		material.turbulence_noise_scale = 2.0
		
		# Size
		material.scale_min = 0.5
		material.scale_max = 2.0
		
		# Scale over lifetime
		var curve = Curve.new()
		curve.add_point(Vector2(0, 0.2))
		curve.add_point(Vector2(0.3, 1.0))
		curve.add_point(Vector2(0.7, 1.2))
		curve.add_point(Vector2(1, 0.8))
		
		var scale_curve = CurveTexture.new()
		scale_curve.curve = curve
		material.scale_curve = scale_curve
		
		# Color and transparency
		var gradient = Gradient.new()
		gradient.add_point(0, Color(0.9, 0.9, 0.9, 0.0))
		gradient.add_point(0.1, Color(0.8, 0.8, 0.8, 0.5))
		gradient.add_point(0.7, Color(0.6, 0.6, 0.6, 0.3))
		gradient.add_point(1, Color(0.4, 0.4, 0.4, 0.0))
		
		var gradient_texture = GradientTexture1D.new()
		gradient_texture.gradient = gradient
		material.color_ramp = gradient_texture
		
		smoke_particles.process_material = material

# Set up ring particles
func setup_ring_particles():
	ring_particles = get_node_or_null("RingParticles")
	if ring_particles:
		ring_particles.emitting = false
		ring_particles.one_shot = true
		
		# Update lifetime based on duration_multiplier
		ring_particles.lifetime = ring_particles.lifetime * duration_multiplier
	else:
		# Create new ring particles
		ring_particles = GPUParticles2D.new()
		ring_particles.name = "RingParticles"
		ring_particles.emitting = false
		ring_particles.amount = 120
		ring_particles.lifetime = 0.7
		ring_particles.one_shot = true
		ring_particles.explosiveness = 1.0
		add_child(ring_particles)
		
		# Create ring material
		var material = ParticleProcessMaterial.new()
		
		# Emission settings - ring shape
		material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		material.emission_ring_radius = 10.0
		material.emission_ring_inner_radius = 5.0
		material.emission_ring_height = 1.0
		material.emission_ring_axis = Vector3(0, 0, 1)
		
		# Movement - outward expansion
		material.direction = Vector3(0, 0, 0)
		material.spread = 180.0
		material.gravity = Vector3(0, 0, 0)
		material.initial_velocity_min = 30.0
		material.initial_velocity_max = 80.0
		
		# Add drag
		material.damping_min = 20.0
		material.damping_max = 40.0
		
		# Size
		material.scale_min = 0.1
		material.scale_max = 0.3
		
		# Scale over lifetime
		var curve = Curve.new()
		curve.add_point(Vector2(0, 1.0))
		curve.add_point(Vector2(0.5, 0.5))
		curve.add_point(Vector2(1, 0.0))
		
		var scale_curve = CurveTexture.new()
		scale_curve.curve = curve
		material.scale_curve = scale_curve
		
		# Color and transparency - bright to fade
		var gradient = Gradient.new()
		gradient.add_point(0, Color(1.0, 1.0, 1.0, 1.0))
		gradient.add_point(0.2, Color(flash_color.r, flash_color.g, flash_color.b, 0.8))
		gradient.add_point(0.5, Color(flash_color.r, flash_color.g * 0.7, flash_color.b * 0.4, 0.4))
		gradient.add_point(1, Color(flash_color.r * 0.5, flash_color.g * 0.3, flash_color.b * 0.1, 0.0))
		
		var gradient_texture = GradientTexture1D.new()
		gradient_texture.gradient = gradient
		material.color_ramp = gradient_texture
		
		ring_particles.process_material = material

# Set up secondary particles (new)
func setup_secondary_particles():
	secondary_particles = get_node_or_null("SecondaryParticles")
	if not secondary_particles:
		secondary_particles = GPUParticles2D.new()
		secondary_particles.name = "SecondaryParticles"
		secondary_particles.emitting = false
		secondary_particles.amount = 40
		secondary_particles.lifetime = 0.8
		secondary_particles.one_shot = true
		secondary_particles.explosiveness = 0.9
		secondary_particles.randomness = 0.3
		add_child(secondary_particles)
		
		# Create secondary material
		var material = ParticleProcessMaterial.new()
		
		# Emission settings
		material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		material.emission_sphere_radius = 5.0
		
		# Movement
		material.direction = Vector3(0, 0, 0)
		material.spread = 180.0
		material.gravity = Vector3(0, 0, 0)
		material.initial_velocity_min = 20.0
		material.initial_velocity_max = 60.0
		
		# Add drag
		material.damping_min = 10.0
		material.damping_max = 30.0
		
		# Size
		material.scale_min = 0.2
		material.scale_max = 0.6
		
		# Scale over lifetime
		var curve = Curve.new()
		curve.add_point(Vector2(0, 0.8))
		curve.add_point(Vector2(0.4, 1.0))
		curve.add_point(Vector2(1, 0.0))
		
		var scale_curve = CurveTexture.new()
		scale_curve.curve = curve
		material.scale_curve = scale_curve
		
		# Color and transparency - customized by flash color
		var gradient = Gradient.new()
		gradient.add_point(0, Color(1.0, 1.0, 1.0, 1.0))
		gradient.add_point(0.3, Color(flash_color.r, flash_color.g, flash_color.b, 0.7))
		gradient.add_point(0.7, Color(flash_color.r * 0.8, flash_color.g * 0.5, flash_color.b * 0.2, 0.4))
		gradient.add_point(1, Color(flash_color.r * 0.6, flash_color.g * 0.3, flash_color.b * 0.1, 0.0))
		
		var gradient_texture = GradientTexture1D.new()
		gradient_texture.gradient = gradient
		material.color_ramp = gradient_texture
		
		secondary_particles.process_material = material

# Set up bloom particles (new)
func setup_bloom_particles():
	bloom_particles = get_node_or_null("BloomParticles")
	if not bloom_particles:
		bloom_particles = GPUParticles2D.new()
		bloom_particles.name = "BloomParticles"
		bloom_particles.emitting = false
		bloom_particles.amount = 1
		bloom_particles.lifetime = flash_lifetime * 0.5
		bloom_particles.one_shot = true
		bloom_particles.explosiveness = 1.0
		add_child(bloom_particles)
		
		# Create bloom material
		var material = ParticleProcessMaterial.new()
		
		# Emission at center
		material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
		
		# No movement
		material.direction = Vector3(0, 0, 0)
		material.spread = 0.0
		material.gravity = Vector3(0, 0, 0)
		material.initial_velocity_min = 0.0
		material.initial_velocity_max = 0.0
		
		# Size - large bloom effect
		material.scale_min = 10.0
		material.scale_max = 10.0
		
		# Scale over lifetime - quick expansion then fade
		var curve = Curve.new()
		curve.add_point(Vector2(0, 0.2))
		curve.add_point(Vector2(0.1, 1.5))
		curve.add_point(Vector2(0.6, 1.0))
		curve.add_point(Vector2(1, 0.0))
		
		var scale_curve = CurveTexture.new()
		scale_curve.curve = curve
		material.scale_curve = scale_curve
		
		# Color and transparency - bright white to flash color fade
		var gradient = Gradient.new()
		gradient.add_point(0, Color(1.0, 1.0, 1.0, 1.0))
		gradient.add_point(0.2, Color(1.0, 1.0, 1.0, 0.8))
		gradient.add_point(0.5, Color(flash_color.r, flash_color.g, flash_color.b, 0.4))
		gradient.add_point(1, Color(flash_color.r * 0.8, flash_color.g * 0.5, flash_color.b * 0.2, 0.0))
		
		var gradient_texture = GradientTexture1D.new()
		gradient_texture.gradient = gradient
		material.color_ramp = gradient_texture
		
		bloom_particles.process_material = material

# Set up lighting
func setup_lighting():
	# Main flash light is already set up in setup_flash_light()
	
	# Add secondary light for subtle background illumination
	var secondary_light = get_node_or_null("SecondaryLight")
	if not secondary_light:
		secondary_light = PointLight2D.new()
		secondary_light.name = "SecondaryLight"
		secondary_light.color = flash_color.lightened(0.2)
		secondary_light.energy = flash_intensity * 0.5
		secondary_light.texture_scale = flash_radius / DEFAULT_FLASH_RADIUS * 8.0
		add_child(secondary_light)
		
		# Setup light animation
		var tween = create_tween()
		tween.tween_property(secondary_light, "energy", 0.0, flash_lifetime * 3.0 * duration_multiplier)

# Set up audio
func setup_audio():
	audio_player = get_node_or_null("AudioPlayer")
	if audio_player:
		audio_player.volume_db = 10.0  # Loud!
		audio_player.max_distance = 2000
	else:
		# Create new audio player
		audio_player = AudioStreamPlayer2D.new()
		audio_player.name = "AudioPlayer"
		audio_player.volume_db = 10.0
		audio_player.max_distance = 2000
		
		# In an actual implementation, you'd load the sound file
		# audio_player.stream = load("res://assets/audio/effects/flash.ogg")
		
		add_child(audio_player)
	
	# Add secondary audio effect for atmospheric ringing
	secondary_audio = get_node_or_null("SecondaryAudio")
	if not secondary_audio:
		secondary_audio = AudioStreamPlayer2D.new()
		secondary_audio.name = "SecondaryAudio"
		secondary_audio.volume_db = 0.0
		secondary_audio.pitch_scale = 0.8
		secondary_audio.max_distance = 1500
		
		# In an actual implementation, you'd load the sound file
		# secondary_audio.stream = load("res://assets/audio/effects/flash_ring.ogg")
		
		add_child(secondary_audio)
		
		# Create fade out for secondary audio
		var tween = create_tween()
		tween.tween_property(secondary_audio, "volume_db", -40.0, 3.0 * duration_multiplier)

# Start all particle systems and effects
func start_emission():
	emitting = true
	
	if shockwave_particles:
		shockwave_particles.emitting = true
	
	if smoke_particles:
		smoke_particles.emitting = true
	
	if ring_particles:
		ring_particles.emitting = true
	
	if secondary_particles:
		secondary_particles.emitting = true
	
	if bloom_particles:
		bloom_particles.emitting = true
	
	if audio_player:
		audio_player.play()
	
	if secondary_audio:
		secondary_audio.play()
	
	# Apply screen shake
	if apply_screen_shake:
		create_screen_shake(flash_intensity * 0.15)  # Moderate shake

# Configure flash effects (intensity, radius, etc.)
func configure(radius: float = DEFAULT_FLASH_RADIUS, intensity: float = DEFAULT_FLASH_INTENSITY, duration_mult: float = DEFAULT_DURATION_MULTIPLIER, color: Color = Color(1.0, 1.0, 1.0, 1.0), shake: bool = true):
	# Store configuration
	flash_radius = radius
	flash_intensity = intensity
	duration_multiplier = duration_mult
	flash_color = color
	apply_screen_shake = shake
	
	# Scale the radius and intensity based on the input
	var scale_factor = radius / DEFAULT_FLASH_RADIUS
	
	# Adjust main flash
	if flash_light:
		flash_light.energy = intensity
		flash_light.color = color
		flash_light.texture_scale = scale_factor * 5.0
		
		# Update light fadeout
		var tween = create_tween()
		tween.tween_property(flash_light, "energy", 0.0, flash_lifetime * 2.0 * duration_mult)
	
	# Adjust shockwave size
	if shockwave_particles and shockwave_particles.process_material:
		if shockwave_particles.process_material.scale_curve:
			var curve = shockwave_particles.process_material.scale_curve.curve
			if curve and curve.get_point_count() >= 3:
				# Adjust the final point to match the radius
				var final_scale = 15.0 * scale_factor
				curve.set_point_value(2, final_scale)
		
		# Update color ramp
		if shockwave_particles.process_material.color_ramp and shockwave_particles.process_material.color_ramp.gradient:
			var gradient = shockwave_particles.process_material.color_ramp.gradient
			if gradient.get_point_count() >= 4:
				gradient.set_color(0, Color(color.r, color.g, color.b, 0.8))
				gradient.set_color(1, Color(color.r, color.g * 0.9, color.b * 0.6, 0.6))
				gradient.set_color(2, Color(color.r * 0.9, color.g * 0.6, color.b * 0.3, 0.4))
				gradient.set_color(3, Color(color.r * 0.7, color.g * 0.3, color.b * 0.0, 0.0))
	
	# Adjust smoke particles
	if smoke_particles:
		smoke_particles.lifetime = 3.0 * duration_mult
	
	# Adjust ring particles
	if ring_particles and ring_particles.process_material:
		ring_particles.lifetime = 0.7 * duration_mult
		
		# Adjust velocities
		ring_particles.process_material.initial_velocity_min = 30.0 * intensity
		ring_particles.process_material.initial_velocity_max = 80.0 * intensity
		
		# Update color ramp
		if ring_particles.process_material.color_ramp and ring_particles.process_material.color_ramp.gradient:
			var gradient = ring_particles.process_material.color_ramp.gradient
			if gradient.get_point_count() >= 4:
				gradient.set_color(1, Color(color.r, color.g, color.b, 0.8))
				gradient.set_color(2, Color(color.r, color.g * 0.7, color.b * 0.4, 0.4))
				gradient.set_color(3, Color(color.r * 0.5, color.g * 0.3, color.b * 0.1, 0.0))
	
	# Adjust secondary particles
	if secondary_particles and secondary_particles.process_material:
		secondary_particles.lifetime = 0.8 * duration_mult
		
		# Update color ramp
		if secondary_particles.process_material.color_ramp and secondary_particles.process_material.color_ramp.gradient:
			var gradient = secondary_particles.process_material.color_ramp.gradient
			if gradient.get_point_count() >= 4:
				gradient.set_color(1, Color(color.r, color.g, color.b, 0.7))
				gradient.set_color(2, Color(color.r * 0.8, color.g * 0.5, color.b * 0.2, 0.4))
				gradient.set_color(3, Color(color.r * 0.6, color.g * 0.3, color.b * 0.1, 0.0))
	
	# Adjust bloom particles
	if bloom_particles:
		bloom_particles.lifetime = flash_lifetime * 0.5 * duration_mult
		
		# Update color ramp
		if bloom_particles.process_material and bloom_particles.process_material.color_ramp and bloom_particles.process_material.color_ramp.gradient:
			var gradient = bloom_particles.process_material.color_ramp.gradient
			if gradient.get_point_count() >= 4:
				gradient.set_color(2, Color(color.r, color.g, color.b, 0.4))
				gradient.set_color(3, Color(color.r * 0.8, color.g * 0.5, color.b * 0.2, 0.0))
	
	# Adjust secondary light
	var secondary_light = get_node_or_null("SecondaryLight")
	if secondary_light:
		secondary_light.color = color.lightened(0.2)
		secondary_light.energy = intensity * 0.5
		secondary_light.texture_scale = scale_factor * 8.0
		
		# Update light fadeout
		var tween = create_tween()
		tween.tween_property(secondary_light, "energy", 0.0, flash_lifetime * 3.0 * duration_mult)
	
	# Adjust audio (if any)
	if audio_player:
		audio_player.volume_db = 10.0 + (5.0 * log(intensity))
	
	if secondary_audio:
		secondary_audio.volume_db = 0.0 + (5.0 * log(intensity * 0.5))
		var tween = create_tween()
		tween.tween_property(secondary_audio, "volume_db", -40.0, 3.0 * duration_mult)
	
	# Update cleanup timer
	var cleanup_timer = get_node_or_null("CleanupTimer")
	if cleanup_timer:
		cleanup_timer.wait_time = 4.0 * duration_mult

# Create a screen shake effect
func create_screen_shake(intensity: float = 0.5):
	var camera = get_viewport().get_camera_2d()
	if camera and camera.has_method("add_trauma"):
		camera.add_trauma(intensity)
	else:
		# Try to find a camera shake manager in the scene
		var camera_shake = get_node_or_null("/root/CameraShake")
		if camera_shake and camera_shake.has_method("add_trauma"):
			camera_shake.add_trauma(intensity)
		else:
			# If no camera shake system exists, create a basic one
			basic_screen_shake(intensity)

# Basic screen shake if no camera trauma system exists
func basic_screen_shake(intensity: float = 0.5):
	var camera = get_viewport().get_camera_2d()
	if not camera:
		return
	
	var original_offset = camera.offset
	var shake_amount = 10.0 * intensity
	
	var tween = create_tween()
	tween.tween_property(camera, "offset", Vector2(randf_range(-1, 1) * shake_amount, randf_range(-1, 1) * shake_amount), 0.1)
	tween.tween_property(camera, "offset", Vector2(randf_range(-1, 1) * shake_amount, randf_range(-1, 1) * shake_amount), 0.1)
	tween.tween_property(camera, "offset", Vector2(randf_range(-1, 1) * shake_amount * 0.5, randf_range(-1, 1) * shake_amount * 0.5), 0.1)
	tween.tween_property(camera, "offset", original_offset, 0.1)
