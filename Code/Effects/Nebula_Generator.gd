extends Node2D

# Nebula generator system - creates beautiful space nebulae

# Configuration variables
@export var nebula_count: int = 5
@export var nebula_colors: Array[Color] = [
	Color(0.5, 0.2, 0.7, 0.05),    # Purple
	Color(0.2, 0.5, 0.7, 0.05),    # Blue
	Color(0.7, 0.3, 0.2, 0.05),    # Red
	Color(0.2, 0.7, 0.3, 0.05),    # Green
	Color(0.7, 0.6, 0.2, 0.05),    # Yellow
]
@export var nebula_size_range: Vector2 = Vector2(500, 2000)
@export var noise_texture: NoiseTexture2D
@export var point_count_multiplier: float = 2.0  # Controls density of custom-drawn nebulae
@export var custom_drawing_enabled: bool = true  # Enable/disable custom drawing for performance

# Nebula types
enum NebulaType { CLOUD, SPIRAL, RING, IRREGULAR }

# Runtime variables
var rng = RandomNumberGenerator.new()
var nebulae = []
var particles: CPUParticles2D
var dynamic_sprites = []
var cloud_material = null
var noise = FastNoiseLite.new()
var plasma_noise = FastNoiseLite.new()
var viewport_rect = Rect2()
var current_time: float = 0.0  # Store time for use in _draw

func _ready():
	# Get particles system
	particles = get_node("DynamicNebulaParticles")
	
	# Create a canvas item material for cloud effects
	cloud_material = CanvasItemMaterial.new()
	cloud_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	
	# Initialize noise generators
	noise.seed = randi()
	noise.frequency = 0.005
	noise.fractal_octaves = 4
	
	plasma_noise.seed = randi() + 100
	plasma_noise.frequency = 0.003
	plasma_noise.fractal_octaves = 3
	plasma_noise.fractal_lacunarity = 2.5
	
	# Initialize nebula properties later
	call_deferred("initialize_materials")

func initialize_materials():
	# Set up material for particles
	if particles:
		particles.material = cloud_material
		particles.emitting = false  # We will handle emission manually

func initialize(seed_value: int):
	# Set seed
	rng.seed = seed_value
	noise.seed = seed_value
	plasma_noise.seed = seed_value + 100
	
	# Generate nebulae
	generate_nebulae()
	
	# Start particles effect
	if particles:
		configure_particles()
		particles.emitting = true

func update(delta: float, time: float):
	# Store current time for use in _draw
	current_time = time
	
	# Update viewport rect for culling
	if is_instance_valid(get_viewport()) and is_instance_valid(get_viewport().get_camera_2d()):
		var camera = get_viewport().get_camera_2d()
		var zoom = camera.zoom
		var screen_size = get_viewport_rect().size
		viewport_rect = Rect2(
			camera.global_position - (screen_size / 2) / zoom,
			screen_size / zoom
		)
	else:
		viewport_rect = get_viewport_rect()
		
	# Update nebula effects
	update_nebulae(delta, current_time)
	
	# Update custom visuals
	if custom_drawing_enabled:
		queue_redraw()

func generate_nebulae():
	# Clear any existing nebulae
	nebulae.clear()
	
	# Remove any existing sprite nodes
	for sprite in dynamic_sprites:
		if is_instance_valid(sprite):
			sprite.queue_free()
	dynamic_sprites.clear()
	
	# Create new nebulae
	for i in range(nebula_count):
		var nebula_type = rng.randi() % NebulaType.size()
		
		# Random position with good distribution
		var angle = rng.randf() * TAU
		var distance = rng.randf_range(1000, 5000)
		var pos = Vector2(cos(angle), sin(angle)) * distance
		
		# Random size
		var size = rng.randf_range(nebula_size_range.x, nebula_size_range.y)
		
		# Random color from the array
		var base_color = nebula_colors[rng.randi() % nebula_colors.size()]
		
		# Secondary color for some variation
		var has_secondary = rng.randf() < 0.7
		var secondary_color = nebula_colors[rng.randi() % nebula_colors.size()]
		while has_secondary and secondary_color.is_equal_approx(base_color):
			secondary_color = nebula_colors[rng.randi() % nebula_colors.size()]
		
		# Random noise offset for unique patterns
		var noise_offset = Vector2(rng.randf() * 1000, rng.randf() * 1000)
		
		# Create nebula data
		var nebula = {
			"position": pos,
			"size": size,
			"type": nebula_type,
			"color": base_color,
			"secondary_color": secondary_color if has_secondary else base_color,
			"noise_offset": noise_offset,
			"rotation": rng.randf() * TAU,
			"rotation_speed": rng.randf_range(-0.05, 0.05),
			"density": rng.randf_range(0.3, 0.7),
			"time_offset": rng.randf() * 10.0,  # For animation variation
			"draw_with_sprite": rng.randf() < 0.5  # Some nebulae use sprites, some use custom drawing
		}
		
		# Additional properties based on type
		match nebula_type:
			NebulaType.CLOUD:
				nebula["layers"] = rng.randi_range(2, 4)
				nebula["turbulence"] = rng.randf_range(0.1, 0.3)
				nebula["cloud_centers"] = generate_cloud_centers(
					rng.randi_range(4, 8), 
					size * 0.8
				)
			NebulaType.SPIRAL:
				nebula["arms"] = rng.randi_range(2, 4)
				nebula["arm_curvature"] = rng.randf_range(0.5, 1.5)
				nebula["tightness"] = rng.randf_range(1.0, 3.0)
				nebula["arm_width"] = rng.randf_range(0.1, 0.3)  # Width of the spiral arms
				nebula["rotation_dir"] = 1 if rng.randf() < 0.5 else -1  # Direction of spiral
			NebulaType.RING:
				nebula["inner_radius"] = rng.randf_range(0.3, 0.7)
				nebula["thickness"] = rng.randf_range(0.1, 0.3)
				nebula["distortion"] = rng.randf_range(0.0, 0.2)
				nebula["segments"] = rng.randi_range(1, 3)  # Number of ring segments (full ring if 1)
				nebula["segment_spacing"] = rng.randf_range(0.05, 0.2) if nebula.segments > 1 else 0.0
			NebulaType.IRREGULAR:
				nebula["fragments"] = rng.randi_range(3, 7)
				nebula["fragment_size"] = rng.randf_range(0.2, 0.5)
				nebula["fragment_positions"] = generate_fragment_positions(
					nebula.fragments, 
					size * 0.7
				)
				nebula["fragment_shapes"] = generate_fragment_shapes(nebula.fragments)
		
		# Create sprite nodes for sprite-based nebulae
		if nebula.draw_with_sprite:
			create_nebula_sprites(nebula)
		
		nebulae.append(nebula)

func generate_cloud_centers(count: int, max_radius: float) -> Array:
	var centers = []
	
	for i in range(count):
		var angle = rng.randf() * TAU
		var distance = rng.randf() * max_radius
		centers.append({
			"position": Vector2(cos(angle), sin(angle)) * distance,
			"size": rng.randf_range(0.2, 0.6),  # Relative size of this cloud within the nebula
			"density": rng.randf_range(0.5, 1.0)
		})
	
	return centers

func generate_fragment_positions(count: int, max_radius: float) -> Array:
	var positions = []
	
	for i in range(count):
		var angle = rng.randf() * TAU
		var distance = rng.randf() * max_radius
		positions.append(Vector2(cos(angle), sin(angle)) * distance)
	
	return positions

func generate_fragment_shapes(count: int) -> Array:
	var shapes = []
	
	for i in range(count):
		var point_count = rng.randi_range(5, 10)
		var points = []
		
		for j in range(point_count):
			var angle = j * TAU / point_count
			var radius = rng.randf_range(0.7, 1.3)  # Randomize radius for irregular shape
			points.append(Vector2(cos(angle), sin(angle)) * radius)
		
		shapes.append(PackedVector2Array(points))
	
	return shapes

func create_nebula_sprites(nebula):
	# For sprite-based nebulae, create sprite nodes with noise texture
	var sprite = Sprite2D.new()
	add_child(sprite)
	
	# Set texture
	sprite.texture = noise_texture
	
	# Set properties
	sprite.position = nebula.position
	sprite.scale = Vector2(nebula.size / 1000.0, nebula.size / 1000.0)  # Adjust scale based on texture size
	sprite.rotation = nebula.rotation
	
	# Set color
	sprite.modulate = nebula.color
	
	# Set material
	sprite.material = cloud_material.duplicate()
	
	# Add to dynamic sprites list
	dynamic_sprites.append(sprite)

func configure_particles():
	if particles:
		particles.emitting = false
		
		# Configure basic particle properties
		particles.emission_rect_extents = Vector2(3000, 3000)
		particles.amount = 500
		particles.lifetime = 60.0
		
		# Configure visual properties
		particles.gravity = Vector2.ZERO
		particles.scale_amount_min = 50.0
		particles.scale_amount_max = 150.0
		
		# Start emitting
		particles.emitting = true

func update_nebulae(delta: float, current_time: float):
	# Update sprite-based nebulae
	for i in range(min(nebulae.size(), dynamic_sprites.size())):
		var nebula = nebulae[i]
		var sprite = dynamic_sprites[i]
		
		if nebula.draw_with_sprite and is_instance_valid(sprite):
			# Update rotation
			nebula.rotation += nebula.rotation_speed * delta
			sprite.rotation = nebula.rotation
			
			# Pulse effect based on time
			var pulse = sin(current_time * 0.2 + nebula.noise_offset.x * 0.01) * 0.1 + 0.9
			sprite.scale = Vector2(nebula.size / 1000.0, nebula.size / 1000.0) * pulse
			
			# Color cycling for some nebulae
			if rng.randi() % 100 == 0:  # Occasional color shift
				var color_shift = sin(current_time * 0.1 + nebula.noise_offset.y * 0.01) * 0.1
				sprite.modulate = nebula.color.lightened(color_shift)
	
	# Update properties for all nebulae
	for nebula in nebulae:
		# Update rotation for all nebulae (even custom drawn ones)
		nebula.rotation += nebula.rotation_speed * delta

func _draw():
	if not custom_drawing_enabled:
		return
		
	# Draw custom nebulae
	for nebula in nebulae:
		# Skip sprite-rendered nebulae
		if nebula.draw_with_sprite:
			continue
			
		# Skip if outside viewport (with padding)
		if not viewport_rect.grow(nebula.size).has_point(nebula.position):
			continue
			
		# Draw based on type
		match nebula.type:
			NebulaType.CLOUD:
				draw_cloud_nebula(nebula, current_time)
			NebulaType.SPIRAL:
				draw_spiral_nebula(nebula, current_time)
			NebulaType.RING:
				draw_ring_nebula(nebula, current_time)
			NebulaType.IRREGULAR:
				draw_irregular_nebula(nebula, current_time)

func draw_cloud_nebula(nebula, current_time: float):
	# Draw a cloud-like nebula with multiple overlapping circles and noise
	
	# Set up transform
	var original_transform = get_global_transform()
	var xform = Transform2D()
	xform = xform.translated(nebula.position)
	xform = xform.rotated(nebula.rotation)
	set_nebula_transform(xform)
	
	# Calculate animation factors
	var time_offset = current_time * 0.1 + nebula.time_offset
	var pulse = sin(time_offset * 0.5) * 0.1 + 0.9  # Slow pulsation
	
	# Calculate how many points to draw based on density and size
	var point_count = int(nebula.size * nebula.density * 0.3 * point_count_multiplier)
	
	# Generate points for each cloud center
	for center in nebula.cloud_centers:
		var center_pos = center.position
		var center_radius = nebula.size * center.size
		
		# Draw cloud points
		for i in range(int(point_count * center.density)):
			# Use noise to determine if we draw this point
			var angle = rng.randf() * TAU
			var distance_factor = rng.randf()  # 0 to 1
			var distance = center_radius * pow(distance_factor, 0.5)  # More points toward center
			
			var point_pos = center_pos + Vector2(cos(angle), sin(angle)) * distance
			
			# Sample noise for this position
			var noise_val = plasma_noise.get_noise_2d(
				point_pos.x + nebula.noise_offset.x + time_offset * 10,
				point_pos.y + nebula.noise_offset.y + time_offset * 5
			)
			
			# Skip if noise value is too low
			if noise_val < -0.2:
				continue
			
			# Determine color
			var point_color = nebula.color
			
			# Use secondary color sometimes if available
			if "secondary_color" in nebula and rng.randf() < 0.3:
				point_color = nebula.secondary_color
			
			# Adjust alpha based on noise and distance from center
			var dist_factor = 1.0 - (distance / center_radius)
			point_color.a = point_color.a * max(0.2, noise_val + 0.5) * dist_factor * pulse
			
			# Draw point with varied size
			var point_size = rng.randf_range(1, 4)
			draw_circle(point_pos, point_size, point_color)
	
	# Reset transform
	set_nebula_transform(original_transform)

func draw_spiral_nebula(nebula, current_time: float):
	# Draw a spiral nebula using logarithmic spiral formula
	
	# Set up transform
	var original_transform = get_global_transform()
	var xform = Transform2D()
	xform = xform.translated(nebula.position)
	xform = xform.rotated(nebula.rotation + current_time * 0.02 * nebula.rotation_dir)  # Slowly rotate
	set_nebula_transform(xform)
	
	# Time-based animation factors
	var time_factor = current_time * 0.1 + nebula.time_offset
	var pulse = sin(time_factor) * 0.1 + 0.9
	
	# Calculate how many points to draw
	var point_count = int(nebula.size * nebula.density * 0.2 * point_count_multiplier)
	
	# Draw each spiral arm
	for arm in range(nebula.arms):
		var arm_angle_offset = arm * TAU / nebula.arms
		
		# Draw points along the spiral
		for i in range(point_count):
			# Logarithmic spiral formula: r = a*e^(b*theta)
			var t = float(i) / point_count  # 0 to 1
			var theta = t * 8 * PI * nebula.tightness  # How many revolutions
			var radius = nebula.size * 0.05 * exp(nebula.arm_curvature * theta) * t
			
			# Add some turbulence
			var noise_val = plasma_noise.get_noise_2d(
				theta * 10 + nebula.noise_offset.x + time_factor * 5,
				radius * 0.01 + nebula.noise_offset.y
			)
			
			# Calculate angle with arm offset
			var angle = theta + arm_angle_offset
			
			# Apply noise to radius
			radius *= (1.0 + noise_val * 0.2)
			
			# Calculate point position
			var point_pos = Vector2(cos(angle), sin(angle)) * radius
			
			# Calculate perpendicular direction for arm width
			var perp_angle = angle + PI/2
			var perp_dir = Vector2(cos(perp_angle), sin(perp_angle))
			
			# Sample multiple points perpendicular to the arm for width
			var arm_width = nebula.arm_width * nebula.size * (1 - 0.5 * t)  # Arms get thinner toward end
			
			# Draw multiple points for the arm width
			var width_samples = 3
			for w in range(width_samples):
				var width_t = (float(w) / (width_samples - 1) - 0.5) * 2  # -1 to 1
				var width_offset = perp_dir * arm_width * width_t
				var sample_pos = point_pos + width_offset
				
				# Determine color
				var point_color = nebula.color
				
				# Use secondary color sometimes if available
				if "secondary_color" in nebula and rng.randf() < 0.3:
					point_color = nebula.secondary_color
				
				# Fade alpha based on distance from spiral line
				var alpha_factor = 1.0 - abs(width_t)  # 1 at center, 0 at edges
				point_color.a = point_color.a * alpha_factor * pulse
				
				# Add extra fade toward the end of the spiral
				point_color.a *= (1.0 - 0.7 * t)
				
				# Draw point
				var point_size = rng.randf_range(1, 4) * (1.0 - 0.3 * t)
				draw_circle(sample_pos, point_size, point_color)
	
	# Reset transform
	set_nebula_transform(original_transform)

func draw_ring_nebula(nebula, current_time: float):
	# Draw a ring nebula with optional segments and distortion
	
	# Set up transform
	var original_transform = get_global_transform()
	var xform = Transform2D()
	xform = xform.translated(nebula.position)
	xform = xform.rotated(nebula.rotation + current_time * 0.01)  # Very slow rotation
	set_nebula_transform(xform)
	
	# Animation factors
	var time_factor = current_time * 0.1 + nebula.time_offset
	var pulse = sin(time_factor) * 0.05 + 0.95  # Subtle pulse
	
	# Calculate ring dimensions
	var outer_radius = nebula.size * 0.5
	var inner_radius = outer_radius * nebula.inner_radius
	var thickness = (outer_radius - inner_radius)
	
	# Calculate how many points to draw
	var point_count = int(nebula.size * nebula.density * 0.5 * point_count_multiplier)
	
	# Draw ring points
	for i in range(point_count):
		var angle = rng.randf() * TAU
		
		# For segmented rings, check if in a gap
		if nebula.segments > 1:
			var segment_angle = fmod(angle, TAU)
			var segment_size = TAU / nebula.segments
			var segment_gap = segment_size * nebula.segment_spacing
			var segment_with_gap = segment_size
			var segment_start = segment_with_gap * floor(segment_angle / segment_with_gap)
			var segment_end = segment_start + (segment_size - segment_gap)
			
			# Skip if in a gap
			if segment_angle > segment_end or segment_angle < segment_start:
				continue
		
		# Apply distortion to radius
		var distortion = 0.0
		if nebula.distortion > 0:
			distortion = sin(angle * 2 + time_factor) * nebula.distortion
		
		# Randomize radius within the ring thickness
		var radius_factor = rng.randf()  # 0 to 1
		var radius = inner_radius + thickness * radius_factor
		
		# Apply distortion and pulse
		radius *= (1.0 + distortion) * pulse
		
		# Calculate point position
		var point_pos = Vector2(cos(angle), sin(angle)) * radius
		
		# Apply noise-based density
		var noise_val = plasma_noise.get_noise_2d(
			point_pos.x * 0.01 + nebula.noise_offset.x + time_factor * 2,
			point_pos.y * 0.01 + nebula.noise_offset.y
		)
		
		# Skip if noise value is too low (creates density variations)
		if noise_val < -0.3:
			continue
		
		# Determine color
		var point_color = nebula.color
		
		# Use secondary color sometimes if available
		if "secondary_color" in nebula and rng.randf() < 0.4:
			point_color = nebula.secondary_color
		
		# Adjust alpha based on noise and position in the ring
		var ring_pos = abs(radius_factor - 0.5) * 2  # 0 at center of ring, 1 at edges
		point_color.a = point_color.a * (0.4 + 0.6 * noise_val) * (1.0 - 0.6 * ring_pos)
		
		# Draw point
		var point_size = rng.randf_range(1, 4) * (1.0 - 0.3 * ring_pos)
		draw_circle(point_pos, point_size, point_color)
	
	# Reset transform
	set_nebula_transform(original_transform)

func draw_irregular_nebula(nebula, current_time: float):
	# Draw an irregular nebula with multiple distorted shapes
	
	# Set up transform
	var original_transform = get_global_transform()
	var xform = Transform2D()
	xform = xform.translated(nebula.position)
	xform = xform.rotated(nebula.rotation)
	set_nebula_transform(xform)
	
	# Animation factors
	var time_factor = current_time * 0.1 + nebula.time_offset
	var pulse = sin(time_factor * 0.7) * 0.15 + 0.85  # Stronger pulse for irregular nebulae
	
	# Calculate base number of points
	var base_point_count = int(nebula.size * nebula.density * 0.2 * point_count_multiplier)
	
	# Draw points for each fragment
	for f in range(nebula.fragments):
		var fragment_pos = nebula.fragment_positions[f]
		var fragment_shape = nebula.fragment_shapes[f]
		var fragment_size = nebula.size * nebula.fragment_size
		
		# Calculate points for this fragment
		var fragment_point_count = int(base_point_count / nebula.fragments)
		
		# Draw cloud of points with noise-based distribution
		for i in range(fragment_point_count):
			# Random position around the fragment center
			var angle = rng.randf() * TAU
			var distance = fragment_size * rng.randf() 
			var base_pos = fragment_pos + Vector2(cos(angle), sin(angle)) * distance
			
			# Apply time-based movement
			var movement_offset = Vector2(
				sin(time_factor + fragment_pos.x * 0.01),
				cos(time_factor * 1.2 + fragment_pos.y * 0.01)
			) * fragment_size * 0.05
			
			var point_pos = base_pos + movement_offset
			
			# Sample noise
			var noise_val = plasma_noise.get_noise_2d(
				point_pos.x * 0.01 + nebula.noise_offset.x,
				point_pos.y * 0.01 + nebula.noise_offset.y + time_factor
			)
			
			# Skip if noise value is too low
			if noise_val < -0.2:
				continue
			
			# Calculate distance to fragment center
			var dist = point_pos.distance_to(fragment_pos) / fragment_size
			
			# Determine color
			var point_color = nebula.color
			
			# Use secondary color sometimes if available
			if "secondary_color" in nebula and rng.randf() < 0.4:
				point_color = nebula.secondary_color
			
			# Adjust alpha based on noise, distance, and pulse
			point_color.a = point_color.a * max(0, noise_val + 0.5) * (1.0 - dist * 0.8) * pulse
			
			# Draw point
			var point_size = rng.randf_range(1, 4) * (1.0 - dist * 0.5)
			draw_circle(point_pos, point_size, point_color)
	
	# Reset transform
	set_nebula_transform(original_transform)

func set_nebula_transform(xform: Transform2D):
	# This is a helper function to handle transforms for drawing
	var canvas_item = get_canvas_item()
	RenderingServer.canvas_item_set_transform(canvas_item, xform)
