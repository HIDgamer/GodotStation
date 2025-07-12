extends Node2D

# Impact effect configurator script
# Creates a brief particle effect at impact point

# Configuration variables
@export var lifetime: float = 0.6  # How long the effect lasts
@export var auto_destroy: bool = true  # Whether to automatically free after playing
@export var impact_strength: float = 1.0  # How strong the impact is (affects particles/sound)
@export var impact_type: String = "generic"  # Type of impact (can be "metal", "concrete", "dirt", etc.)

# Internal variables
var played: bool = false
var impact_particles: Array = []
var surface_normal: Vector2 = Vector2.UP

func _ready():
	# Get references to all particle systems
	for child in get_children():
		if child is GPUParticles2D:
			impact_particles.append(child)
			
	# Start the effect immediately
	play_effect()
	
	# Set up auto-destroy timer if enabled
	if auto_destroy:
		var timer = Timer.new()
		timer.wait_time = lifetime
		timer.one_shot = true
		timer.autostart = true
		timer.timeout.connect(queue_free)
		add_child(timer)

# Play the impact effect with given parameters
func play_effect():
	if played:
		return
		
	played = true
	
	# Adjust particle effects based on impact_strength
	for particles in impact_particles:
		# Start emission
		particles.emitting = true
		
		# Scale amount based on impact strength
		if particles.amount > 5:  # Don't reduce below a minimum
			particles.amount = int(particles.amount * clamp(impact_strength, 0.5, 2.0))
		
		# Adjust emission speed based on impact strength
		if particles.process_material:
			if "initial_velocity_min" in particles.process_material:
				particles.process_material.initial_velocity_min *= impact_strength
			if "initial_velocity_max" in particles.process_material:
				particles.process_material.initial_velocity_max *= impact_strength
	
	# Set up impact sound if present
	var sound = get_node_or_null("ImpactSound")
	if sound and sound is AudioStreamPlayer2D:
		# Adjust volume and pitch based on impact strength
		sound.volume_db = linear_to_db(clamp(impact_strength, 0.5, 2.0))
		sound.pitch_scale = randf_range(0.9, 1.1) * clamp(impact_strength, 0.8, 1.2)
		sound.play()
	
	# Set up a flash effect if available
	var flash = get_node_or_null("ImpactFlash")
	if flash and flash is Node2D:
		var flash_tween = create_tween()
		flash_tween.tween_property(flash, "modulate:a", 0.0, 0.2)

# Set the surface normal to orient particles relative to the impact surface
func set_surface_normal(normal: Vector2):
	surface_normal = normal.normalized()
	
	# Rotate the node to align with the surface normal
	rotation = surface_normal.angle() - PI/2
	
	# Update particles directions to emit away from the surface
	for particles in impact_particles:
		if particles.process_material and "direction" in particles.process_material:
			# The direction is relative to the node's rotation
			particles.process_material.direction = Vector3(0, -1, 0)

# Configure the effect based on provided parameters
func configure(strength: float = 1.0, type: String = "generic", norm: Vector2 = Vector2.UP):
	impact_strength = strength
	impact_type = type
	set_surface_normal(norm)
	
	# Adjust appearance based on surface type
	match impact_type:
		"metal":
			# More sparks, metallic sound
			adjust_for_metal()
		"concrete", "stone":
			# More dust, harder impact sound
			adjust_for_concrete()
		"dirt", "sand":
			# Lots of dust, softer impact sound
			adjust_for_dirt()
		"wood":
			# Wood chips, hollow sound
			adjust_for_wood()
		_:  # Default/generic
			pass

# Specialized configuration functions
func adjust_for_metal():
	var sparks = get_node_or_null("SparkParticles")
	if sparks and sparks is GPUParticles2D:
		sparks.amount *= 1.5
	
	var sound = get_node_or_null("ImpactSound")
	if sound and sound is AudioStreamPlayer2D:
		sound.pitch_scale *= 1.2

func adjust_for_concrete():
	var dust = get_node_or_null("DustParticles")
	if dust and dust is GPUParticles2D:
		dust.amount *= 1.8
		
	var sound = get_node_or_null("ImpactSound")
	if sound and sound is AudioStreamPlayer2D:
		sound.pitch_scale *= 0.9
		sound.volume_db += 2

func adjust_for_dirt():
	var dust = get_node_or_null("DustParticles")
	if dust and dust is GPUParticles2D:
		dust.amount *= 2.5
		if dust.process_material:
			dust.process_material.initial_velocity_max *= 0.7
			
	var sound = get_node_or_null("ImpactSound")
	if sound and sound is AudioStreamPlayer2D:
		sound.pitch_scale *= 0.7
		sound.volume_db -= 3

func adjust_for_wood():
	var chips = get_node_or_null("ChipsParticles")
	if chips and chips is GPUParticles2D:
		chips.amount *= 1.5
		
	var sound = get_node_or_null("ImpactSound")
	if sound and sound is AudioStreamPlayer2D:
		sound.pitch_scale *= 1.1
