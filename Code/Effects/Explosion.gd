extends GPUParticles2D

# Constants
const LIFETIME = 2.0  # How long the main particles live
const PARTICLE_COUNT = 30
const LIGHT_FLICKER_INTENSITY_MIN = 0.7
const LIGHT_FLICKER_INTENSITY_MAX = 1.2
const LIGHT_FLICKER_INTERVAL_MIN = 0.03
const LIGHT_FLICKER_INTERVAL_MAX = 0.08

# Properties for enhanced explosion
var impact_radius: float = 3.0
var intensity: float = 1.0
var has_applied_impact = false
var camera_shake_strength = 20.0  # Camera shake intensity
var camera_shake_duration = 0.7   # Camera shake duration

# Physics impact variables
var affected_objects = []
var max_force_distance = 300.0

# Shader-based shockwave effect
var shockwave_effect = null

func _ready():
	# Set up basic properties
	emitting = false
	amount = PARTICLE_COUNT
	one_shot = true
	explosiveness = 0.95  # Burst most particles at once
	randomness = 0.4
	lifetime = LIFETIME
	
	# Initialize child nodes
	if has_node("ShockwaveRing") and $ShockwaveRing.process_material:
		$ShockwaveRing.emitting = false
		$ShockwaveRing.one_shot = true
		$ShockwaveRing.explosiveness = 1.0
		
	if has_node("DebrisParticles") and $DebrisParticles.process_material:
		$DebrisParticles.emitting = false
		$DebrisParticles.one_shot = true
		$DebrisParticles.explosiveness = 0.9
		$DebrisParticles.randomness = 0.5
		
	if has_node("FlameParticles") and $FlameParticles.process_material:
		$FlameParticles.emitting = false
		$FlameParticles.one_shot = true
		$FlameParticles.explosiveness = 0.8
		
	if has_node("SparkParticles") and $SparkParticles.process_material:
		$SparkParticles.emitting = false
		$SparkParticles.one_shot = true
		$SparkParticles.explosiveness = 1.0
	
	# Set up explosion animation sprite
	if has_node("Explosion"):
		$Explosion.visible = false
		$Explosion.frame = 0
	
	# Set up lights
	if has_node("ExplosionLight"):
		$ExplosionLight.energy = 0
		$ExplosionLight.shadow_enabled = true
		
	if has_node("SecondaryLight"):
		$SecondaryLight.energy = 0
		$SecondaryLight.shadow_enabled = true
		
		# Set up flicker timer for more dynamic lighting
		if $SecondaryLight.has_node("FlickerTimer"):
			$SecondaryLight/FlickerTimer.wait_time = randf_range(LIGHT_FLICKER_INTERVAL_MIN, LIGHT_FLICKER_INTERVAL_MAX)
	
	# Configure audio
	if has_node("ExplosionSound"):
		$ExplosionSound.pitch_scale = randf_range(0.9, 1.1)  # Random pitch variation
		$ExplosionSound.volume_db = 0  # Base volume
		
	if has_node("DebrisSound"):
		$DebrisSound.pitch_scale = randf_range(0.85, 1.15)
		
	if has_node("FlameSound"):
		$FlameSound.pitch_scale = randf_range(0.9, 1.1)
	
	# Start the sequence immediately
	start_explosion_sequence()
	
	# Set up timeout to free the node after particles are done
	var timer = get_tree().create_timer(LIFETIME * 1.5)
	timer.timeout.connect(queue_free)

# Trigger the full explosion sequence with proper timing
func start_explosion_sequence():
	# Main flash and initial explosion
	if has_node("ExplosionLight"):
		var tween = create_tween()
		tween.tween_property($ExplosionLight, "energy", 4.0 * intensity, 0.05)
		tween.tween_property($ExplosionLight, "energy", 2.0 * intensity, 0.3)
		tween.tween_property($ExplosionLight, "energy", 0.0, 2.0)
		
	if has_node("SecondaryLight"):
		var tween = create_tween()
		tween.tween_property($SecondaryLight, "energy", 2.0 * intensity, 0.1)
		tween.tween_property($SecondaryLight, "energy", 1.0 * intensity, 0.5)
		tween.tween_property($SecondaryLight, "energy", 0.0, 3.0)
	
	# Create shader-based shockwave effect
	create_shader_shockwave()
	
	# Immediate effects
	if has_node("Explosion"):
		$Explosion.visible = true
		$Explosion.play("Explosion")
	
	# Slightly delayed effects (core explosion)
	await get_tree().create_timer(0.05).timeout
	emitting = true
	
	if has_node("FlameParticles"):
		$FlameParticles.emitting = true
		
	if has_node("SparkParticles"):
		$SparkParticles.emitting = true
		
	# Create camera shake
	apply_camera_shake()
	
	# Slightly more delayed effects (debris)
	await get_tree().create_timer(0.1).timeout
	if has_node("DebrisParticles"):
		$DebrisParticles.emitting = true
		
	if has_node("DebrisSound"):
		$DebrisSound.play()
		
	# Play explosion sound
	if has_node("ExplosionSound"):
		$ExplosionSound.play()
		
	# Delayed flame sound
	await get_tree().create_timer(0.2).timeout
	if has_node("FlameSound"):
		$FlameSound.play()

# Create shader-based shockwave effect
func create_shader_shockwave():
	# Instantiate the shader effect
	var shockwave = preload("res://Scenes/Effects/Shockwave.tscn").instantiate()
	get_tree().get_root().add_child(shockwave)
	
	# Center the shockwave on the explosion position
	var viewport_size = get_viewport_rect().size
	shockwave.global_position = global_position - (viewport_size / 2)
	
	# Configure based on explosion properties
	var size_factor = impact_radius / 3.0
	var intensity_factor = intensity * 1.2  # Slightly boost intensity for better visibility
	
	# Set wave color based on explosion type (default is slight blue tint)
	var wave_color = Color(0.8, 0.9, 1.0, 0.2)
	
	shockwave.configure(intensity_factor, size_factor, intensity_factor)
	shockwave.set_wave_color(wave_color)
	shockwave.set_wave_speed(2.0)  # Faster wave speed for more dramatic effect
	shockwave.auto_free = true
	
	# Start the effect
	shockwave.play()
	
	# Store reference
	shockwave_effect = shockwave

# Apply camera shake effect
func apply_camera_shake():
	# Find the current camera and apply shake
	var viewport = get_viewport()
	if viewport and viewport.get_camera_2d():
		var camera = viewport.get_camera_2d()
		if camera.has_method("add_trauma"):
			# If the camera has a screen shake controller attached
			camera.add_trauma(intensity * 0.7)
		else:
			# Manual shake implementation
			var initial_pos = camera.position
			var shake_tween = create_tween()
			
			# Generate a few random offsets
			for i in range(6):
				var offset = Vector2(
					randf_range(-camera_shake_strength, camera_shake_strength),
					randf_range(-camera_shake_strength, camera_shake_strength)
				) * intensity
				
				# Decrease intensity over time
				offset *= 1.0 - (i / 6.0)
				
				# Add shake keyframe
				shake_tween.tween_property(camera, "offset", offset, 0.1)
			
			# Return to original position
			shake_tween.tween_property(camera, "offset", Vector2.ZERO, 0.2)

# Apply physical impact to objects in range
func _apply_physics_impact():
	if has_applied_impact:
		return
		
	has_applied_impact = true
	
	# Find all physics bodies in range
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	
	# Set up collision shape for the query (circular shape)
	var shape = CircleShape2D.new()
	shape.radius = impact_radius * 100  # Convert to pixels
	query.shape = shape
	query.transform = Transform2D(0, global_position)
	query.collision_mask = 0xFFFFFFFF  # All layers
	
	# Get all bodies in range
	var results = space_state.intersect_shape(query)
	
	# Apply force to each body
	for result in results:
		var collider = result.collider
		
		# Skip if not a physics body or already processed
		if not (collider is RigidBody2D) or collider in affected_objects:
			continue
			
		affected_objects.append(collider)
		
		# Calculate force based on distance
		var direction = (collider.global_position - global_position).normalized()
		var distance = collider.global_position.distance_to(global_position)
		var force_strength = clamp(1.0 - (distance / max_force_distance), 0.1, 1.0)
		force_strength *= 1000.0 * intensity  # Base force
		
		# Apply impulse at center of mass
		collider.apply_central_impulse(direction * force_strength)

# Configure explosion properties
func configure(new_impact_radius: float = 3.0, new_intensity: float = 1.0):
	impact_radius = new_impact_radius
	intensity = new_intensity
	
	# Scale particle systems based on parameters
	var scale_factor = impact_radius / 3.0
	
	# Adjust main particles
	amount = int(PARTICLE_COUNT * scale_factor)
	
	if process_material:
		process_material.emission_sphere_radius = 20.0 * scale_factor
		process_material.initial_velocity_max *= intensity
	
	# Adjust child particles
	if has_node("ShockwaveRing") and $ShockwaveRing.process_material:
		$ShockwaveRing.process_material.scale_min *= scale_factor
		$ShockwaveRing.process_material.scale_max *= scale_factor
	
	if has_node("DebrisParticles") and $DebrisParticles.process_material:
		$DebrisParticles.amount = int(30 * scale_factor)
		$DebrisParticles.lifetime = 2.0 * intensity
		if $DebrisParticles.process_material:
			$DebrisParticles.process_material.initial_velocity_max *= intensity
	
	if has_node("FlameParticles") and $FlameParticles.process_material:
		$FlameParticles.amount = int(40 * scale_factor)
		if $FlameParticles.process_material:
			$FlameParticles.process_material.emission_sphere_radius = 15.0 * scale_factor
			$FlameParticles.process_material.initial_velocity_max *= intensity
	
	if has_node("SparkParticles") and $SparkParticles.process_material:
		$SparkParticles.amount = int(60 * scale_factor)
		if $SparkParticles.process_material:
			$SparkParticles.process_material.initial_velocity_max *= intensity
	
	# Adjust explosion sprite scale
	if has_node("Explosion"):
		$Explosion.scale = Vector2(10, 10) * scale_factor
	
	# Adjust lights
	if has_node("ExplosionLight"):
		$ExplosionLight.texture_scale = 3.0 * scale_factor
		
	if has_node("SecondaryLight"):
		$SecondaryLight.texture_scale = 2.1 * scale_factor
	
	# Adjust camera shake based on intensity
	camera_shake_strength = 20.0 * intensity
	camera_shake_duration = 0.7 * intensity

# Light flicker effect for more dynamic lighting
func _on_flicker_timer_timeout():
	if has_node("SecondaryLight"):
		# Random energy fluctuation
		var current_energy = $SecondaryLight.energy
		if current_energy > 0:
			$SecondaryLight.energy = current_energy * randf_range(LIGHT_FLICKER_INTENSITY_MIN, LIGHT_FLICKER_INTENSITY_MAX)
		
		# Reset timer with random interval
		$SecondaryLight/FlickerTimer.wait_time = randf_range(LIGHT_FLICKER_INTERVAL_MIN, LIGHT_FLICKER_INTERVAL_MAX)
		$SecondaryLight/FlickerTimer.start()
