extends Node2D

# Sun system - creates dynamic, animated sun with effects

# Configuration variables
@export var core_size: float = 400.0 
@export var corona_size: float = 1000.0
@export var flare_count: int = 6
@export var light_energy: float = 1.2
@export var light_radius: float = 6000.0
@export var corona_texture: Texture2D
@export var flare_texture: Texture2D

# Runtime variables
var rng = RandomNumberGenerator.new()
var flares = []
var corona_particles: CPUParticles2D
var core_sprite: Sprite2D
var light: Light2D
var current_time: float = 0.0
var pulse_phase: float = 0.0
var corona_rotation: float = 0.0
var active_flare: int = -1
var flare_timer: float = 0.0
var corona_material: CanvasItemMaterial

# Solar flare class
class SolarFlare:
	var position: Vector2
	var angle: float
	var length: float
	var width: float
	var lifetime: float
	var current_life: float
	var sprite: Sprite2D
	
	func _init(p_params: Dictionary):
		position = p_params.get("position", Vector2.ZERO)
		angle = p_params.get("angle", 0.0)
		length = p_params.get("length", 500.0)
		width = p_params.get("width", 100.0)
		lifetime = p_params.get("lifetime", 3.0)
		current_life = lifetime
		sprite = p_params.get("sprite", null)
	
	func update(delta: float):
		current_life -= delta
		
		# Update visibility based on life remaining
		if sprite and is_instance_valid(sprite):
			# Fade in quickly, fade out slowly
			var alpha = 1.0
			if current_life < lifetime * 0.7:
				alpha = current_life / (lifetime * 0.7)
			elif current_life > lifetime * 0.9:
				alpha = (lifetime - current_life) / (lifetime * 0.1)
			
			# Update sprite alpha
			var color = sprite.modulate
			color.a = alpha
			sprite.modulate = color
	
	func is_alive() -> bool:
		return current_life > 0

func _ready():
	# Get node references
	core_sprite = get_node_or_null("CoreSprite")
	corona_particles = get_node_or_null("CoronaParticles")
	light = get_node_or_null("Light2D")
	
	# Create material for corona
	corona_material = CanvasItemMaterial.new()
	corona_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	
	# Set initial values
	rng.randomize()
	pulse_phase = rng.randf() * TAU

func initialize():
	# Configure core sprite
	if core_sprite:
		core_sprite.scale = Vector2(core_size / 512.0, core_size / 512.0)
		
		# Set material
		core_sprite.material = corona_material.duplicate()
	
	# Configure corona particles
	if corona_particles:
		# Configure particles for corona
		corona_particles.emission_sphere_radius = core_size
		corona_particles.amount = 100
		corona_particles.lifetime = 3.0
		corona_particles.scale_amount_min = 100.0
		corona_particles.scale_amount_max = 200.0
		corona_particles.initial_velocity_min = 20.0
		corona_particles.initial_velocity_max = 50.0
		
		# Color and material
		corona_particles.color = Color(1, 0.7, 0.2, 0.2)
		corona_particles.material = corona_material.duplicate()
		
		# Start emission
		corona_particles.emitting = true
	
	# Configure light
	if light:
		light.energy = light_energy
		light.texture_scale = light_radius / 512.0
	
	# Create flare sprites
	create_flare_sprites()

func update(delta: float, current_time: float):
	# Update time
	self.current_time = current_time
	
	# Update core pulsing
	update_core_pulse(delta)
	
	# Update corona rotation
	corona_rotation += delta * 0.02
	if core_sprite:
		core_sprite.rotation = corona_rotation
	
	# Update existing flares
	update_flares(delta)
	
	# Check for new flare
	if active_flare == -1:
		flare_timer -= delta
		if flare_timer <= 0:
			# Random time until next flare
			flare_timer = rng.randf_range(5.0, 15.0)
			
			# Trigger a random flare
			active_flare = rng.randi() % flare_count
			trigger_flare(active_flare)
	
	# Redraw custom effects
	queue_redraw()

func update_core_pulse(delta: float):
	# Update pulse phase
	pulse_phase += delta * 0.3
	
	# Calculate pulse factor (between 0.9 and 1.1)
	var pulse = 0.9 + 0.2 * (0.5 + 0.5 * sin(pulse_phase))
	
	# Apply to core sprite
	if core_sprite:
		core_sprite.scale = Vector2(core_size / 512.0, core_size / 512.0) * pulse
	
	# Update light energy
	if light:
		light.energy = light_energy * (0.9 + 0.2 * (0.5 + 0.5 * sin(pulse_phase * 1.2)))

func create_flare_sprites():
	# Create sprite nodes for solar flares
	for i in range(flare_count):
		var flare_sprite = Sprite2D.new()
		add_child(flare_sprite)
		
		# Set texture
		flare_sprite.texture = flare_texture
		
		# Calculate position around sun
		var angle = i * TAU / flare_count
		var pos = Vector2(cos(angle), sin(angle)) * core_size
		flare_sprite.position = pos
		flare_sprite.rotation = angle
		
		# Size proportional to core size but varies
		var size_variation = rng.randf_range(0.8, 1.2)
		flare_sprite.scale = Vector2(
			core_size / 128.0 * size_variation,
			core_size / 512.0 * size_variation
		)
		
		# Invisible initially
		flare_sprite.modulate.a = 0.0
		
		# Set material
		flare_sprite.material = corona_material.duplicate()
		
		# Create flare object
		var flare = SolarFlare.new({
			"position": pos,
			"angle": angle,
			"length": core_size * 2 * size_variation,
			"width": core_size * 0.5 * size_variation,
			"lifetime": rng.randf_range(3.0, 6.0),
			"sprite": flare_sprite
		})
		
		flares.append(flare)

func trigger_flare(flare_index: int):
	if flare_index >= 0 and flare_index < flares.size():
		var flare = flares[flare_index]
		flare.current_life = flare.lifetime
		
		# Apply some variation
		var size_variation = rng.randf_range(0.8, 1.2)
		flare.sprite.scale = Vector2(
			core_size / 128.0 * size_variation,
			core_size / 512.0 * size_variation
		)
		
		# Randomly adjust angle slightly for variation
		var angle_variation = rng.randf_range(-0.2, 0.2)
		flare.sprite.rotation = flare.angle + angle_variation

func update_flares(delta: float):
	# Update all flares
	for i in range(flares.size()):
		var flare = flares[i]
		flare.update(delta)
		
		# Check if active flare has ended
		if i == active_flare and not flare.is_alive():
			active_flare = -1

func _draw():
	# Optionally draw custom effects for the sun
	
	# Draw corona glow
	if false:  # Disabled as we're using sprites and particles
		var corona_color = Color(1.0, 0.7, 0.2, 0.2)
		draw_circle(Vector2.ZERO, corona_size, corona_color)
	
	# Draw active flares
	for flare in flares:
		if flare.is_alive():
			# We're using sprites for flares, but could add additional effects here
			pass
