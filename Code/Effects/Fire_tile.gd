extends Area2D
class_name FireEffect

# Fire properties
var burn_damage = 5.0
var burn_stacks = 10
var duration = 15.0  # Seconds
var burn_interval = 1.0  # Seconds between damage ticks
var heat = 800  # Heat level (affects nearby objects)
var fire_radius = 16.0  # Default radius in pixels
var fire_intensity = 1.0  # Scaling factor
var fire_color = Color(1.0, 0.7, 0.3, 1.0)  # Default orange fire color

# State tracking
var entities_in_fire = []
var players_in_fire = []  # Track players separately for optimized checks
var timer = 0.0
var flame = null

# Visual components
var fire_particles = null
var ember_particles = null
var heat_particles = null
var spark_particles = null
var smoke_puffs = null
var heat_distortion = null

# Lighting and sound
var fire_light = null
var secondary_light = null
var fire_sound = null
var crackle_sound = null

func _ready():
	# Make sure we're in the right groups
	if not is_in_group("fire"):
		add_to_group("fire")
	if not is_in_group("hazards"):
		add_to_group("hazards")
	
	# Connect signals for detecting entities entering/exiting fire
	if not is_connected("body_entered", _on_body_entered):
		connect("body_entered", _on_body_entered)
	if not is_connected("body_exited", _on_body_exited):
		connect("body_exited", _on_body_exited)
	
	# Start the burn timer
	if has_node("DurationTimer"):
		$DurationTimer.wait_time = duration
		$DurationTimer.start()
	else:
		var timer_node = Timer.new()
		timer_node.name = "DurationTimer"
		timer_node.wait_time = duration
		timer_node.one_shot = true
		timer_node.autostart = true
		timer_node.timeout.connect(_on_duration_timer_timeout)
		add_child(timer_node)
	
	# Start the burn interval timer
	if has_node("BurnTimer"):
		$BurnTimer.wait_time = burn_interval
		$BurnTimer.start()
	else:
		var timer_node = Timer.new()
		timer_node.name = "BurnTimer"
		timer_node.wait_time = burn_interval
		timer_node.autostart = true
		timer_node.timeout.connect(_on_burn_timer_timeout)
		add_child(timer_node)
	
	# Start the flicker timer for the light
	if has_node("FlickerTimer"):
		$FlickerTimer.start()
	else:
		var timer_node = Timer.new()
		timer_node.name = "FlickerTimer"
		timer_node.wait_time = 0.1
		timer_node.autostart = true
		timer_node.timeout.connect(_on_flicker_timer_timeout)
		add_child(timer_node)
	
	# Get reference to main flame sprite
	flame = get_node_or_null("Flame")
	
	# Set up visual components
	setup_visual_components()
	
	# Set up collision shape
	setup_collision_shape()
	
	# Start playing sounds
	setup_sounds()

func _process(delta):
	# Track overall duration
	timer += delta
	
	# If we exceed duration, begin fading out
	if timer >= duration and not has_node("FadeOut"):
		start_fade_out()
	
	# Play flame animation if it exists
	if flame and flame.has_method("play"):
		flame.play()
	
	# Update fire particles for more dynamic movement
	if fire_particles and fire_particles.process_material:
		# Add slight variation to particle emission
		if randf() < 0.1:  # 10% chance each frame
			fire_particles.amount = int(clamp(fire_particles.amount + randf_range(-5, 5), 70, 90))
	
	# Occasionally spawn smoke puffs
	if smoke_puffs and randf() < 0.02:  # 2% chance each frame
		spawn_smoke_puff()
	
	# Occasionally spawn sparks
	if spark_particles and randf() < 0.05:  # 5% chance each frame
		spawn_spark()

# Set up all visual components
func setup_visual_components():
	# Set up main fire particles
	setup_fire_particles()
	
	# Set up ember particles
	setup_ember_particles()
	
	# Set up heat particles
	setup_heat_particles()
	
	# Set up spark particles
	setup_spark_particles()
	
	# Set up smoke puffs system
	setup_smoke_puffs()
	
	# Set up heat distortion
	setup_heat_distortion()
	
	# Set up fire light
	setup_fire_light()

# Set up main fire particles
func setup_fire_particles():
	fire_particles = get_node_or_null("FireParticles")
	if not fire_particles:
		# Main fire particles might be already set up in the scene
		return
	
	# Update fire particles material properties based on current settings
	if fire_particles.process_material:
		var material = fire_particles.process_material
		
		# Update emission radius
		material.emission_sphere_radius = fire_radius * 0.5
		
		# Update colors based on fire color
		if material.color_ramp and material.color_ramp.gradient:
			var gradient = material.color_ramp.gradient
			if gradient.get_point_count() >= 4:
				# Create color with adjusted values (Godot will automatically clamp values between 0-1)
				var color1 = Color(fire_color.r, fire_color.g + 0.2, fire_color.b - 0.2, 1.0)
				var color2 = Color(fire_color.r, fire_color.g - 0.2, fire_color.b - 0.2, 1.0)
				var color3 = Color(fire_color.r - 0.2, fire_color.g - 0.5, fire_color.b, 0.8)
				var color4 = Color(fire_color.r - 0.6, fire_color.g - 0.6, fire_color.b, 0.0)
				
				gradient.set_color(0, color1)
				gradient.set_color(1, color2)
				gradient.set_color(2, color3)
				gradient.set_color(3, color4)
		
		# Update velocity based on intensity
		material.initial_velocity_min = 20.0 * fire_intensity
		material.initial_velocity_max = 80.0 * fire_intensity

# Set up ember particles
func setup_ember_particles():
	ember_particles = get_node_or_null("EmberParticles")
	if not ember_particles:
		ember_particles = GPUParticles2D.new()
		ember_particles.name = "EmberParticles"
		ember_particles.emitting = true
		ember_particles.amount = 20
		ember_particles.lifetime = 2.0
		ember_particles.explosiveness = 0.0
		ember_particles.randomness = 0.5
		add_child(ember_particles)
		
		# Create ember particle material
		var material = ParticleProcessMaterial.new()
		
		# Emission settings
		material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		material.emission_sphere_radius = fire_radius * 0.3
		
		# Movement
		material.direction = Vector3(0, -1, 0)
		material.spread = 30.0
		material.gravity = Vector3(0, -30, 0)  # Upward drift
		material.initial_velocity_min = 10.0 * fire_intensity
		material.initial_velocity_max = 30.0 * fire_intensity
		
		# Add turbulence
		material.turbulence_enabled = true
		material.turbulence_noise_strength = 1.0
		material.turbulence_noise_scale = 1.0
		
		# Size
		material.scale_min = 0.1
		material.scale_max = 0.3
		
		# Scale over lifetime
		var curve = Curve.new()
		curve.add_point(Vector2(0, 1.0))
		curve.add_point(Vector2(0.8, 0.8))
		curve.add_point(Vector2(1, 0.0))
		
		var scale_curve = CurveTexture.new()
		scale_curve.curve = curve
		material.scale_curve = scale_curve
		
		# Color and transparency
		var gradient = Gradient.new()
		gradient.add_point(0, Color(1.0, 0.8, 0.4, 1.0))
		gradient.add_point(0.3, Color(1.0, 0.6, 0.1, 0.8))
		gradient.add_point(0.7, Color(0.9, 0.3, 0.0, 0.6))
		gradient.add_point(1, Color(0.7, 0.1, 0.0, 0.0))
		
		var gradient_texture = GradientTexture1D.new()
		gradient_texture.gradient = gradient
		material.color_ramp = gradient_texture
		
		ember_particles.process_material = material

# Set up heat particles
func setup_heat_particles():
	heat_particles = get_node_or_null("HeatParticles")
	if not heat_particles:
		heat_particles = GPUParticles2D.new()
		heat_particles.name = "HeatParticles"
		heat_particles.emitting = true
		heat_particles.amount = 30
		heat_particles.lifetime = 1.5
		heat_particles.explosiveness = 0.0
		heat_particles.randomness = 0.3
		add_child(heat_particles)
		
		# Create heat particle material
		var material = ParticleProcessMaterial.new()
		
		# Emission settings
		material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		material.emission_sphere_radius = fire_radius * 0.4
		
		# Movement
		material.direction = Vector3(0, -1, 0)
		material.spread = 20.0
		material.gravity = Vector3(0, -40, 0)  # Faster upward drift
		material.initial_velocity_min = 5.0 * fire_intensity
		material.initial_velocity_max = 15.0 * fire_intensity
		
		# Size
		material.scale_min = 0.5
		material.scale_max = 1.5
		
		# Scale over lifetime - start invisible, grow, then shrink
		var curve = Curve.new()
		curve.add_point(Vector2(0, 0.0))
		curve.add_point(Vector2(0.2, 0.8))
		curve.add_point(Vector2(0.8, 0.6))
		curve.add_point(Vector2(1, 0.0))
		
		var scale_curve = CurveTexture.new()
		scale_curve.curve = curve
		material.scale_curve = scale_curve
		
		# Color and transparency - heat distortion effect
		var gradient = Gradient.new()
		gradient.add_point(0, Color(1.0, 0.9, 0.5, 0.0))
		gradient.add_point(0.2, Color(1.0, 0.9, 0.5, 0.1))
		gradient.add_point(0.8, Color(0.8, 0.5, 0.2, 0.05))
		gradient.add_point(1, Color(0.5, 0.3, 0.1, 0.0))
		
		var gradient_texture = GradientTexture1D.new()
		gradient_texture.gradient = gradient
		material.color_ramp = gradient_texture
		
		heat_particles.process_material = material

# Set up spark particles
func setup_spark_particles():
	spark_particles = get_node_or_null("SparkParticles")
	if not spark_particles:
		spark_particles = GPUParticles2D.new()
		spark_particles.name = "SparkParticles"
		spark_particles.emitting = false  # Will be triggered on demand
		spark_particles.amount = 15
		spark_particles.lifetime = 1.0
		spark_particles.one_shot = true
		spark_particles.explosiveness = 1.0
		spark_particles.randomness = 0.5
		add_child(spark_particles)
		
		# Create spark particle material
		var material = ParticleProcessMaterial.new()
		
		# Emission settings
		material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
		
		# Movement
		material.direction = Vector3(0, -1, 0)
		material.spread = 180.0
		material.gravity = Vector3(0, 30, 0)  # Slight downward for realistic arc
		material.initial_velocity_min = 30.0 * fire_intensity
		material.initial_velocity_max = 80.0 * fire_intensity
		
		# Size
		material.scale_min = 0.1
		material.scale_max = 0.3
		
		# Scale over lifetime
		var curve = Curve.new()
		curve.add_point(Vector2(0, 1.0))
		curve.add_point(Vector2(0.7, 0.7))
		curve.add_point(Vector2(1, 0.0))
		
		var scale_curve = CurveTexture.new()
		scale_curve.curve = curve
		material.scale_curve = scale_curve
		
		# Color and transparency - bright yellow/orange sparks
		var gradient = Gradient.new()
		gradient.add_point(0, Color(1.0, 1.0, 0.5, 1.0))
		gradient.add_point(0.4, Color(1.0, 0.8, 0.3, 0.8))
		gradient.add_point(0.7, Color(1.0, 0.4, 0.0, 0.5))
		gradient.add_point(1, Color(0.7, 0.2, 0.0, 0.0))
		
		var gradient_texture = GradientTexture1D.new()
		gradient_texture.gradient = gradient
		material.color_ramp = gradient_texture
		
		spark_particles.process_material = material

# Set up smoke puffs system
func setup_smoke_puffs():
	smoke_puffs = get_node_or_null("SmokePuffs")
	if not smoke_puffs:
		smoke_puffs = GPUParticles2D.new()
		smoke_puffs.name = "SmokePuffs"
		smoke_puffs.emitting = false  # Will be triggered on demand
		smoke_puffs.amount = 5
		smoke_puffs.lifetime = 3.0
		smoke_puffs.one_shot = true
		smoke_puffs.explosiveness = 0.8
		smoke_puffs.randomness = 0.4
		add_child(smoke_puffs)
		
		# Create smoke particle material
		var material = ParticleProcessMaterial.new()
		
		# Emission settings
		material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		material.emission_sphere_radius = fire_radius * 0.2
		
		# Movement
		material.direction = Vector3(0, -1, 0)
		material.spread = 30.0
		material.gravity = Vector3(0, -10, 0)  # Slow upward drift
		material.initial_velocity_min = 5.0
		material.initial_velocity_max = 15.0
		
		# Add turbulence for wispy smoke
		material.turbulence_enabled = true
		material.turbulence_noise_strength = 2.0
		material.turbulence_noise_scale = 2.0
		
		# Size
		material.scale_min = 1.0
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
		
		# Color and transparency - dark smoke
		var gradient = Gradient.new()
		gradient.add_point(0, Color(0.3, 0.3, 0.3, 0.0))
		gradient.add_point(0.1, Color(0.3, 0.3, 0.3, 0.3))
		gradient.add_point(0.8, Color(0.2, 0.2, 0.2, 0.2))
		gradient.add_point(1, Color(0.1, 0.1, 0.1, 0.0))
		
		var gradient_texture = GradientTexture1D.new()
		gradient_texture.gradient = gradient
		material.color_ramp = gradient_texture
		
		smoke_puffs.process_material = material

# Set up heat distortion
func setup_heat_distortion():
	heat_distortion = get_node_or_null("HeatDistortion")
	if not heat_distortion:
		heat_distortion = Sprite2D.new()
		heat_distortion.name = "HeatDistortion"
		
		# In an actual implementation, you would load a distortion shader material
		# heat_distortion.material = load("res://materials/heat_distortion_material.tres")
		
		heat_distortion.scale = Vector2(fire_radius / 32.0, fire_radius / 32.0) * fire_intensity
		heat_distortion.modulate = Color(1, 1, 1, 0.3)
		add_child(heat_distortion)
		
		# Animate heat distortion
		var tween = create_tween()
		tween.set_loops()
		tween.tween_property(heat_distortion, "scale", Vector2(fire_radius / 28.0, fire_radius / 28.0) * fire_intensity, 1.0)
		tween.tween_property(heat_distortion, "scale", Vector2(fire_radius / 32.0, fire_radius / 32.0) * fire_intensity, 1.0)

# Set up fire light
func setup_fire_light():
	fire_light = get_node_or_null("FireLight")
	if fire_light:
		# Update light color and energy
		fire_light.color = fire_color
		fire_light.energy = 1.0 * fire_intensity
		fire_light.texture_scale = fire_radius / 64.0 * 3.0  # Scale based on fire size
	
	secondary_light = get_node_or_null("SecondaryLight")
	if not secondary_light:
		secondary_light = PointLight2D.new()
		secondary_light.name = "SecondaryLight"
		secondary_light.color = Color(fire_color.r - 0.2, fire_color.g - 0.3, fire_color.b - 0.2, 1.0)
		secondary_light.energy = 0.5 * fire_intensity
		secondary_light.texture_scale = fire_radius / 64.0 * 2.0
		secondary_light.position = Vector2(0, -fire_radius * 0.3)  # Slightly above the main fire
		add_child(secondary_light)

# Set up collision shape
func setup_collision_shape():
	var collision_shape = get_node_or_null("CollisionShape2D")
	if collision_shape:
		# Adjust collision shape to match fire radius
		if collision_shape.shape is CircleShape2D:
			collision_shape.shape.radius = fire_radius
	else:
		# Create a collision shape if one doesn't exist
		collision_shape = CollisionShape2D.new()
		collision_shape.name = "CollisionShape2D"
		var shape = CircleShape2D.new()
		shape.radius = fire_radius
		collision_shape.shape = shape
		add_child(collision_shape)

# Set up sound components
func setup_sounds():
	fire_sound = get_node_or_null("FireSound")
	if fire_sound:
		# Adjust volume based on fire size and intensity
		fire_sound.volume_db = -10.0 + 5.0 * log(fire_intensity)
		fire_sound.play()
	
	crackle_sound = get_node_or_null("CrackleSound")
	if not crackle_sound:
		crackle_sound = AudioStreamPlayer2D.new()
		crackle_sound.name = "CrackleSound"
		crackle_sound.volume_db = -15.0
		crackle_sound.max_distance = 500
		
		# In an actual implementation, you'd load the sound file
		# crackle_sound.stream = load("res://assets/audio/effects/fire_crackle.ogg")
		
		add_child(crackle_sound)
		
		# Start with a slight delay
		var timer = Timer.new()
		timer.wait_time = 0.3
		timer.one_shot = true
		timer.autostart = true
		timer.timeout.connect(func(): crackle_sound.play())
		add_child(timer)
		
		# Setup random crackling
		var crackle_timer = Timer.new()
		crackle_timer.name = "CrackleTimer"
		crackle_timer.wait_time = 0.5
		crackle_timer.autostart = true
		crackle_timer.timeout.connect(func():
			if randf() < 0.4:  # 40% chance each time
				crackle_sound.pitch_scale = randf_range(0.9, 1.1)
				crackle_sound.play()
		)
		add_child(crackle_timer)

# Set fire properties from outside
func set_fire_properties(radius: float, damage: float, intensity: float = 1.0, color: Color = Color(1.0, 0.7, 0.3, 1.0), time: float = 15.0):
	fire_radius = radius
	burn_damage = damage
	fire_intensity = intensity
	fire_color = color
	duration = time
	
	# Update collision shape
	if has_node("CollisionShape2D") and $CollisionShape2D.shape is CircleShape2D:
		$CollisionShape2D.shape.radius = radius
	
	# Update fire particles
	if fire_particles and fire_particles.process_material:
		# Scale amount based on radius and intensity
		fire_particles.amount = int(80.0 * (radius / 16.0) * intensity)
		
		# Update emission radius
		fire_particles.process_material.emission_sphere_radius = radius * 0.5
		
		# Update velocities
		fire_particles.process_material.initial_velocity_min = 20.0 * intensity
		fire_particles.process_material.initial_velocity_max = 80.0 * intensity
	
	# Update ember particles
	if ember_particles and ember_particles.process_material:
		ember_particles.amount = int(20.0 * (radius / 16.0) * intensity)
		ember_particles.process_material.emission_sphere_radius = radius * 0.3
		ember_particles.process_material.initial_velocity_min = 10.0 * intensity
		ember_particles.process_material.initial_velocity_max = 30.0 * intensity
	
	# Update heat particles
	if heat_particles and heat_particles.process_material:
		heat_particles.amount = int(30.0 * (radius / 16.0) * intensity)
		heat_particles.process_material.emission_sphere_radius = radius * 0.4
	
	# Update spark particles
	if spark_particles and spark_particles.process_material:
		spark_particles.amount = int(15.0 * (radius / 16.0) * intensity)
		spark_particles.process_material.initial_velocity_min = 30.0 * intensity
		spark_particles.process_material.initial_velocity_max = 80.0 * intensity
	
	# Update smoke puffs
	if smoke_puffs and smoke_puffs.process_material:
		smoke_puffs.process_material.emission_sphere_radius = radius * 0.2
	
	# Update heat distortion
	if heat_distortion:
		heat_distortion.scale = Vector2(radius / 32.0, radius / 32.0) * intensity
		
		# Re-animate
		var tween = create_tween()
		tween.set_loops()
		tween.tween_property(heat_distortion, "scale", Vector2(radius / 28.0, radius / 28.0) * intensity, 1.0)
		tween.tween_property(heat_distortion, "scale", Vector2(radius / 32.0, radius / 32.0) * intensity, 1.0)
	
	# Update lights
	if fire_light:
		fire_light.color = color
		fire_light.energy = 1.0 * intensity
		fire_light.texture_scale = radius / 64.0 * 3.0
	
	if secondary_light:
		secondary_light.color = Color(color.r - 0.2, color.g - 0.3, color.b - 0.2, 1.0)
		secondary_light.energy = 0.5 * intensity
		secondary_light.texture_scale = radius / 64.0 * 2.0
		secondary_light.position = Vector2(0, -radius * 0.3)
	
	# Update timers
	if has_node("DurationTimer"):
		$DurationTimer.wait_time = time
		$DurationTimer.start()
	
	# Update sounds
	if fire_sound:
		fire_sound.volume_db = -10.0 + 5.0 * log(intensity)
	
	if crackle_sound:
		crackle_sound.volume_db = -15.0 + 5.0 * log(intensity)

# Enhanced method to apply damage to an entity
func apply_damage_to_entity(entity):
	if not is_instance_valid(entity):
		return
		
	# Try various health systems to ensure damage is applied
	var damage_applied = false
	
	# Direct damage methods
	if entity.has_method("apply_damage"):
		var damage_type = entity.DamageType.BURN if "DamageType" in entity else "burn"
		entity.apply_damage(burn_damage, damage_type)
		damage_applied = true
	elif entity.has_method("take_damage"):
		entity.take_damage(burn_damage, "fire", "fire")
		damage_applied = true
		
	# Try to find health system if direct methods didn't work
	if not damage_applied:
		var health_system = null
		
		# Check if entity has health_system property
		if "health_system" in entity and entity.health_system:
			health_system = entity.health_system
		# Check if it's accessible as a child node
		elif entity.has_node("HealthSystem"):
			health_system = entity.get_node("HealthSystem")
		# Check if the parent has it
		elif entity.get_parent() and entity.get_parent().has_node("HealthSystem"):
			health_system = entity.get_parent().get_node("HealthSystem")
		# Try health connector
		elif entity.has_node("HealthConnector"):
			var health_connector = entity.get_node("HealthConnector")
			if health_connector.has_method("apply_damage"):
				health_connector.apply_damage(burn_damage, "burn")
				damage_applied = true
		elif entity.get_parent() and entity.get_parent().has_node("HealthConnector"):
			var health_connector = entity.get_parent().get_node("HealthConnector")
			if health_connector.has_method("apply_damage"):
				health_connector.apply_damage(burn_damage, "burn")
				damage_applied = true
		
		# If we found a health system, apply damage directly
		if health_system and health_system.has_method("apply_damage"):
			var damage_type = health_system.DamageType.BURN if "DamageType" in health_system else 1
			health_system.apply_damage(burn_damage, damage_type)
			damage_applied = true
		elif health_system and health_system.has_method("adjustFireLoss"):
			health_system.adjustFireLoss(burn_damage)
			damage_applied = true
	
	# Apply fire status effects
	if entity.has_method("ignite"):
		entity.ignite(burn_stacks)
	elif entity.has_method("add_fire_stacks"):
		entity.add_fire_stacks(burn_stacks)
	elif entity.has_method("apply_status_effect"):
		entity.apply_status_effect("burning", 5.0, burn_stacks/10.0)
		
	# Visual feedback for players
	if entity.is_in_group("players") or "is_local_player" in entity:
		var sensory_system = null
		
		if "sensory_system" in entity and entity.sensory_system:
			sensory_system = entity.sensory_system
		elif entity.has_node("SensorySystem"):
			sensory_system = entity.get_node("SensorySystem")
		elif entity.get_parent() and entity.get_parent().has_node("SensorySystem"):
			sensory_system = entity.get_parent().get_node("SensorySystem")
		
		if sensory_system and sensory_system.has_method("display_message"):
			if randf() < 0.3:  # Don't spam too many messages
				var messages = [
					"The fire burns your skin!",
					"You feel intense heat!",
					"The flames sear your flesh!"
				]
				sensory_system.display_message(messages[randi() % messages.size()], "red")

# Track entities that enter the fire
func _on_body_entered(body):
	if not is_instance_valid(body):
		return
		
	if body.is_in_group("entities") and not body in entities_in_fire:
		entities_in_fire.append(body)
		
		# Apply initial effects
		apply_damage_to_entity(body)
	
	# Special handling for players
	if (body.is_in_group("players") or "is_local_player" in body) and not body in players_in_fire:
		players_in_fire.append(body)
		
		# Apply initial effects
		apply_damage_to_entity(body)
		
		# Play fire sound for local player if applicable
		if "is_local_player" in body and body.is_local_player and body.has_node("AudioListener2D"):
			if fire_sound:
				fire_sound.volume_db += 5.0  # Increase volume when player is in fire

# Remove entities that leave the fire
func _on_body_exited(body):
	if not is_instance_valid(body):
		return
		
	if body in entities_in_fire:
		entities_in_fire.erase(body)
	
	if body in players_in_fire:
		players_in_fire.erase(body)
		
		# Restore normal fire sound volume
		if "is_local_player" in body and body.is_local_player and body.has_node("AudioListener2D"):
			if fire_sound:
				fire_sound.volume_db -= 5.0  # Decrease volume when player leaves fire

# Apply burn damage to all entities in the fire
func _on_burn_timer_timeout():
	# Process regular entities
	for entity in entities_in_fire.duplicate():  # Use duplicate to safely modify while iterating
		if not is_instance_valid(entity):
			entities_in_fire.erase(entity)
			continue
		
		# Apply damage and effects
		apply_damage_to_entity(entity)
	
	# Process players separately for any special handling
	for player in players_in_fire.duplicate():  # Use duplicate to safely modify while iterating
		if not is_instance_valid(player):
			players_in_fire.erase(player)
			continue
		
		# Apply damage and effects with potential special player handling
		apply_damage_to_entity(player)

# Random light flicker
func _on_flicker_timer_timeout():
	if fire_light:
		fire_light.energy = randf_range(0.8, 1.2) * fire_intensity
	
	if secondary_light:
		secondary_light.energy = randf_range(0.4, 0.6) * fire_intensity
		# Slightly move the secondary light for more realistic effect
		secondary_light.position = Vector2(randf_range(-2, 2), -fire_radius * 0.3 + randf_range(-2, 2))

# Start fading out when duration expires
func _on_duration_timer_timeout():
	start_fade_out()

# Start fade out process
func start_fade_out():
	# Check if already fading out
	if has_node("FadeOut"):
		return
	
	# Create a new node to handle the fade out
	var fade_out = Node.new()
	fade_out.name = "FadeOut"
	add_child(fade_out)
	
	# Create a tween for fading
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Fade out fire particles
	if fire_particles:
		tween.tween_property(fire_particles, "modulate:a", 0.0, 2.0)
	
	# Fade out ember particles
	if ember_particles:
		tween.tween_property(ember_particles, "modulate:a", 0.0, 1.5)
	
	# Fade out heat particles
	if heat_particles:
		tween.tween_property(heat_particles, "modulate:a", 0.0, 1.0)
	
	# Fade out heat distortion
	if heat_distortion:
		tween.tween_property(heat_distortion, "modulate:a", 0.0, 1.0)
	
	# Fade out flames
	if flame:
		tween.tween_property(flame, "modulate:a", 0.0, 2.0)
	
	# Fade out lights
	if fire_light:
		tween.tween_property(fire_light, "energy", 0.0, 2.0)
	
	if secondary_light:
		tween.tween_property(secondary_light, "energy", 0.0, 1.5)
	
	# Fade out sounds
	if fire_sound:
		tween.tween_property(fire_sound, "volume_db", -40.0, 2.0)
	
	if crackle_sound:
		tween.tween_property(crackle_sound, "volume_db", -40.0, 1.5)
	
	# Queue free after fade out
	tween.tween_callback(queue_free).set_delay(2.0)
	
	# Stop burning entities
	if has_node("BurnTimer"):
		$BurnTimer.stop()
	
	# Reduce collision shape to prevent new entities from being affected
	if has_node("CollisionShape2D"):
		var tween2 = create_tween()
		tween2.tween_property($CollisionShape2D, "scale", Vector2.ZERO, 1.0)

# Spawn a smoke puff
func spawn_smoke_puff():
	if smoke_puffs:
		smoke_puffs.global_position = global_position + Vector2(randf_range(-fire_radius * 0.5, fire_radius * 0.5), 0)
		smoke_puffs.emitting = true
		
		# Reset emitting after a short delay
		var timer = get_tree().create_timer(0.1)
		timer.timeout.connect(func(): smoke_puffs.emitting = false)

# Spawn a spark
func spawn_spark():
	if spark_particles:
		spark_particles.global_position = global_position + Vector2(randf_range(-fire_radius * 0.3, fire_radius * 0.3), 0)
		spark_particles.emitting = true
		
		# Reset emitting after a short delay
		var timer = get_tree().create_timer(0.1)
		timer.timeout.connect(func(): spark_particles.emitting = false)
		
		# Play crackle sound if it exists
		if crackle_sound and randf() < 0.3:  # 30% chance for sound with spark
			crackle_sound.pitch_scale = randf_range(0.9, 1.1)
			crackle_sound.play()

# Custom method to check if an object has a method (renamed to avoid conflict)
func can_call_method(obj, method_name: String) -> bool:
	return obj and is_instance_valid(obj) and obj.has_method(method_name)
