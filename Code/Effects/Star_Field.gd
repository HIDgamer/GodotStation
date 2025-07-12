extends Node2D

# Star field system - enhanced star rendering with particles

# Configuration variables
@export var particle_count: int = 1000
@export var particle_lifetime: float = 60.0
@export var emission_rect: Vector2 = Vector2(2000, 2000)
@export var star_colors: Array[Color] = [
	Color(1.0, 1.0, 1.0, 1.0),      # White
	Color(0.9, 0.9, 1.0, 1.0),      # Light blue
	Color(1.0, 0.9, 0.7, 1.0),      # Yellow
	Color(1.0, 0.8, 0.8, 1.0),      # Light red
	Color(0.8, 0.8, 1.0, 1.0),      # Light blue
	Color(0.7, 1.0, 1.0, 1.0),      # Cyan
]
@export var size_range: Vector2 = Vector2(1.0, 3.0)
@export var twinkle_speed: float = 0.3
@export var twinkle_amount: float = 0.2
@export var bright_star_chance: float = 0.1

# Runtime variables
var rng = RandomNumberGenerator.new()
var particles: CPUParticles2D
var special_stars = []  # Stores data for stars with special effects

# Star types for special effects
enum StarType { NORMAL, TWINKLE, PULSE, BINARY, FLARE }

func _ready():
	# Get particle system
	particles = get_node("StarParticles")

func initialize(seed_value: int):
	# Set seed
	rng.seed = seed_value
	
	# Configure particles
	if particles:
		# Basic configuration
		particles.emitting = false  # Stop default emission
		particles.amount = particle_count
		particles.lifetime = particle_lifetime
		particles.emission_rect_extents = emission_rect / 2
		
		# Size configuration
		particles.scale_amount_min = size_range.x
		particles.scale_amount_max = size_range.y
		
		# Generate stars manually for better control
		generate_stars()
		
		# Start emitting
		particles.emitting = true

func update(delta: float, current_time: float):
	# Update special stars (those with animation effects)
	update_special_stars(delta, current_time)

func generate_stars():
	# Clear any existing particles
	particles.restart()
	particles.emitting = false
	
	# Create special stars (with animation)
	special_stars.clear()
	
	# Calculate how many special stars to create
	var special_count = int(particle_count * 0.2)  # 20% of stars have special effects
	
	for i in range(special_count):
		# Determine star type
		var star_type = StarType.NORMAL
		var roll = rng.randf()
		
		if roll < 0.6:
			star_type = StarType.TWINKLE
		elif roll < 0.8:
			star_type = StarType.PULSE
		elif roll < 0.95:
			star_type = StarType.BINARY
		else:
			star_type = StarType.FLARE
		
		# Create random position
		var pos = Vector2(
			rng.randf_range(-emission_rect.x/2, emission_rect.x/2),
			rng.randf_range(-emission_rect.y/2, emission_rect.y/2)
		)
		
		# Random color and size
		var color_idx = rng.randi() % star_colors.size()
		var base_color = star_colors[color_idx]
		
		# Make some stars brighter
		var size_multi = 1.0
		if rng.randf() < bright_star_chance:
			size_multi = rng.randf_range(1.5, 2.5)
			# Brighten color for these special stars
			base_color = base_color.lightened(0.2)
		
		var size = rng.randf_range(size_range.x, size_range.y) * size_multi
		
		# Add to special stars list
		special_stars.append({
			"position": pos,
			"color": base_color,
			"size": size,
			"type": star_type,
			"phase": rng.randf() * TAU,  # Random starting phase
			"speed": rng.randf_range(0.5, 1.5) * twinkle_speed,
			"binary_distance": rng.randf_range(size/2, size*2) if star_type == StarType.BINARY else 0.0,
			"binary_period": rng.randf_range(1.0, 3.0) if star_type == StarType.BINARY else 0.0,
			"flare_chance": rng.randf_range(0.001, 0.005) if star_type == StarType.FLARE else 0.0,
			"flare_duration": 0.0,  # Current flare time if active
			"secondary_color": star_colors[rng.randi() % star_colors.size()] if star_type == StarType.BINARY else base_color
		})

func update_special_stars(delta: float, current_time: float):
	# Skip if no particles system
	if not particles:
		return
	
	# Currently just using the basic CPUParticles2D system
	# In a real implementation, you would need to manage custom drawing
	# for the special stars using _draw() or additional sprites
	pass

func _draw():
	# In a real implementation, you would draw the special stars here
	# For now, we're using the CPUParticles2D system for simplicity
	pass

# Helper functions for star effects

func calculate_twinkle(star, current_time: float) -> float:
	return sin(current_time * star.speed + star.phase) * twinkle_amount + 1.0

func calculate_pulse(star, current_time: float) -> float:
	# Slower, more pronounced effect than twinkle
	return max(0.8, abs(sin(current_time * star.speed * 0.5 + star.phase)) * 0.5 + 0.8)

func calculate_flare(star, delta: float, current_time: float) -> Dictionary:
	var is_flaring = false
	var flare_intensity = 0.0
	
	# Check if currently flaring
	if star.flare_duration > 0:
		star.flare_duration -= delta
		# Calculate intensity curve - bright flash then fade
		var normalized_time = 1.0 - star.flare_duration / 2.0  # 2 second flares
		flare_intensity = sin(normalized_time * PI) * 2.0
		is_flaring = true
	# Check for new flare
	elif rng.randf() < star.flare_chance * delta * 60:  # Adjusted for frame rate
		star.flare_duration = rng.randf_range(1.0, 2.0)  # 1-2 second flare
		is_flaring = true
		flare_intensity = 0.1  # Starting intensity
	
	return {"is_flaring": is_flaring, "intensity": flare_intensity}

func calculate_binary_positions(star, current_time: float) -> Array:
	var angle = current_time * (1.0 / star.binary_period)
	
	var pos1 = star.position + Vector2(cos(angle), sin(angle)) * star.binary_distance * 0.5
	var pos2 = star.position - Vector2(cos(angle), sin(angle)) * star.binary_distance * 0.5
	
	return [pos1, pos2]
