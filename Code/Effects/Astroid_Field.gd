extends Node2D

# Asteroid field system - creates dynamic asteroid fields

# Configuration variables
@export var asteroid_count: int = 30
@export var size_range: Vector2 = Vector2(20, 80)
@export var field_radius: float = 1200.0
@export var movement_speed_range: Vector2 = Vector2(20, 60)
@export var rotation_speed_range: Vector2 = Vector2(0.3, 1.5)
@export var asteroid_types: Array[String] = ["rocky", "metallic", "icy"]
@export var player_push_force: float = 200.0
@export var player_push_radius: float = 300.0

# Runtime variables
var rng = RandomNumberGenerator.new()
var asteroids = []
var asteroid_sprites = []

# Asteroid class - handles individual asteroid behavior
class Asteroid:
	var position: Vector2
	var velocity: Vector2
	var size: float
	var rotation_speed: float
	var current_rotation: float = 0.0
	var type: String
	var color: Color
	var field_center: Vector2
	var field_radius: float
	var shape_points: PackedVector2Array
	var collision_radius: float
	var unique_id: int
	
	func _init(p_params: Dictionary):
		# Transfer parameters to properties
		position = p_params.get("position", Vector2.ZERO)
		velocity = p_params.get("velocity", Vector2.ZERO)
		size = p_params.get("size", 30.0)
		rotation_speed = p_params.get("rotation_speed", 1.0)
		type = p_params.get("type", "rocky")
		color = p_params.get("color", Color.GRAY)
		field_center = p_params.get("field_center", Vector2.ZERO)
		field_radius = p_params.get("field_radius", 1000.0)
		unique_id = p_params.get("unique_id", 0)
		
		# Generate shape points
		generate_shape(p_params.get("edge_count", 6), p_params.get("irregularity", 0.3))
		
		# Calculate collision radius
		calculate_collision_radius()
	
	func generate_shape(edge_count: int, irregularity: float):
		shape_points = PackedVector2Array()
		var rng = RandomNumberGenerator.new()
		rng.seed = unique_id
		
		for i in range(edge_count):
			var angle = i * TAU / edge_count
			
			# Apply some randomness to radius while maintaining overall size
			var rand_radius = size * (1.0 - irregularity/2 + rng.randf() * irregularity)
			
			# Add point
			shape_points.append(Vector2(cos(angle), sin(angle)) * rand_radius)
	
	func calculate_collision_radius():
		# Find the furthest point from center
		var max_dist = 0.0
		for point in shape_points:
			var dist = point.length()
			if dist > max_dist:
				max_dist = dist
		
		collision_radius = max_dist
	
	func update(delta: float, player_pos = null):
		# Apply rotation
		current_rotation += rotation_speed * delta
		
		# Apply movement
		position += velocity * delta
		
		# Keep within field radius
		var to_center = field_center - position
		var dist_to_center = to_center.length()
		
		# If asteroid starts to leave field, redirect it back
		if dist_to_center > field_radius - size:
			# Gradual redirection toward center
			var redirect_force = 0.5 * (dist_to_center - (field_radius - size)) / size
			velocity = velocity.lerp(to_center.normalized() * velocity.length(), redirect_force * delta)
		
		# Optional: interact with player if position provided
		if player_pos:
			var to_player = player_pos - position
			var dist_to_player = to_player.length()
			
			# If player is close, apply gentle push away
			if dist_to_player < 300.0:
				var push_force = 300.0 / max(dist_to_player, 50.0)
				velocity = velocity - to_player.normalized() * push_force * delta

func _ready():
	# Create initial asteroids
	pass

func initialize(seed_value: int):
	# Set seed
	rng.seed = seed_value
	
	# Generate asteroids
	generate_asteroids()

func update(delta: float, current_time: float, player_position: Vector2 = Vector2.ZERO):
	# Update asteroids
	for i in range(asteroids.size()):
		var asteroid = asteroids[i]
		asteroid.update(delta, player_position)
		
		# Update sprite node positions
		if i < asteroid_sprites.size():
			var sprite = asteroid_sprites[i]
			if is_instance_valid(sprite):
				sprite.position = asteroid.position
				sprite.rotation = asteroid.current_rotation
	
	# Check for asteroid collisions (optional)
	if rng.randi() % 60 == 0:  # Only check occasionally for performance
		check_asteroid_collisions()
	
	# Redraw custom visuals
	queue_redraw()

func generate_asteroids():
	# Clear existing asteroids
	asteroids.clear()
	
	# Remove existing sprite nodes
	for sprite in asteroid_sprites:
		if is_instance_valid(sprite):
			sprite.queue_free()
	asteroid_sprites.clear()
	
	# Create new asteroids
	for i in range(asteroid_count):
		# Random position within field radius
		var angle = rng.randf() * TAU
		var distance = rng.randf() * field_radius
		var pos = Vector2(cos(angle), sin(angle)) * distance
		
		# Random properties
		var size = rng.randf_range(size_range.x, size_range.y)
		var asteroid_type = asteroid_types[rng.randi() % asteroid_types.size()]
		
		# Random movement
		var velocity_angle = rng.randf() * TAU
		var speed = rng.randf_range(movement_speed_range.x, movement_speed_range.y)
		var velocity = Vector2(cos(velocity_angle), sin(velocity_angle)) * speed
		
		# Adjust velocity to favor orbiting motion for better visual effect
		var orbit_blend = rng.randf_range(0.5, 0.9)  # How much to blend with orbital motion
		var orbital_velocity = Vector2(-pos.y, pos.x).normalized() * speed
		velocity = velocity.lerp(orbital_velocity, orbit_blend)
		
		# Create color based on type
		var color: Color
		match asteroid_type:
			"rocky":
				color = Color(rng.randf_range(0.5, 0.7), rng.randf_range(0.3, 0.5), rng.randf_range(0.2, 0.4))
			"metallic":
				color = Color(rng.randf_range(0.6, 0.8), rng.randf_range(0.6, 0.8), rng.randf_range(0.7, 0.9))
			"icy":
				color = Color(rng.randf_range(0.7, 0.9), rng.randf_range(0.8, 1.0), rng.randf_range(0.9, 1.0))
			_:
				color = Color.GRAY
		
		# Create asteroid parameters
		var asteroid_params = {
			"position": position + pos,  # Position relative to field center
			"velocity": velocity,
			"size": size,
			"rotation_speed": rng.randf_range(rotation_speed_range.x, rotation_speed_range.y),
			"type": asteroid_type,
			"color": color,
			"field_center": position,  # Field is centered on this node
			"field_radius": field_radius,
			"edge_count": rng.randi_range(5, 10),
			"irregularity": rng.randf_range(0.2, 0.5),
			"unique_id": rng.randi()
		}
		
		# Create asteroid object
		var asteroid = Asteroid.new(asteroid_params)
		asteroids.append(asteroid)
		
		# Create sprite for the asteroid
		create_asteroid_sprite(asteroid)

func create_asteroid_sprite(asteroid):
	# Create polygon node
	var polygon = Polygon2D.new()
	add_child(polygon)
	
	# Set polygon properties
	polygon.position = asteroid.position
	polygon.polygon = asteroid.shape_points
	polygon.color = asteroid.color
	
	# Add a slight gradient for 3D effect
	var gradient = Gradient.new()
	gradient.add_point(0.0, asteroid.color)
	gradient.add_point(1.0, asteroid.color.darkened(0.5))
	
	var gradient_texture = GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.width = 256
	gradient_texture.height = 256
	gradient_texture.fill = GradientTexture2D.FILL_RADIAL
	gradient_texture.fill_from = Vector2(0.3, 0.3)
	gradient_texture.fill_to = Vector2(0.7, 0.7)
	
	# Add texture to polygon
	polygon.texture = gradient_texture
	
	# Add outline
	var outline = Line2D.new()
	polygon.add_child(outline)
	outline.points = PackedVector2Array(asteroid.shape_points) + PackedVector2Array([asteroid.shape_points[0]])
	outline.width = 2.0
	outline.default_color = asteroid.color.darkened(0.3)
	
	# Type-specific effects
	match asteroid.type:
		"metallic":
			# Add shine effect
			var shine = Polygon2D.new()
			polygon.add_child(shine)
			
			# Create smaller polygon for shine
			var shine_points = []
			for point in asteroid.shape_points:
				shine_points.append(point * 0.6)
			
			shine.polygon = PackedVector2Array(shine_points)
			shine.color = asteroid.color.lightened(0.3)
			shine.position = Vector2(asteroid.size * 0.2, -asteroid.size * 0.2)
			
		"icy":
			# Add ice crystal effects
			var crystal_count = rng.randi_range(2, 5)
			
			for i in range(crystal_count):
				var crystal = Polygon2D.new()
				polygon.add_child(crystal)
				
				var angle = rng.randf() * TAU
				var distance = asteroid.size * rng.randf_range(0.3, 0.7)
				var crystal_pos = Vector2(cos(angle), sin(angle)) * distance
				
				# Create diamond shape
				var crystal_size = asteroid.size * rng.randf_range(0.1, 0.3)
				var crystal_points = PackedVector2Array([
					Vector2(0, -crystal_size),
					Vector2(crystal_size * 0.7, 0),
					Vector2(0, crystal_size),
					Vector2(-crystal_size * 0.7, 0)
				])
				
				crystal.polygon = crystal_points
				crystal.position = crystal_pos
				crystal.color = Color(0.8, 0.9, 1.0, 0.7)
				crystal.rotation = rng.randf() * TAU
	
	# Store the node
	asteroid_sprites.append(polygon)

func check_asteroid_collisions():
	# Simple collision detection
	for i in range(asteroids.size()):
		for j in range(i + 1, asteroids.size()):
			var a1 = asteroids[i]
			var a2 = asteroids[j]
			
			# Skip if either asteroid is too far away
			var distance = (a1.position - a2.position).length()
			if distance > a1.collision_radius + a2.collision_radius:
				continue
			
			# Apply collision response - bounce off each other
			var collision_normal = (a2.position - a1.position).normalized()
			
			# Calculate relative velocity
			var relative_velocity = a2.velocity - a1.velocity
			var velocity_along_normal = relative_velocity.dot(collision_normal)
			
			# Only resolve if objects are moving toward each other
			if velocity_along_normal < 0:
				# Calculate restitution (bounciness)
				var restitution = 0.8
				
				# Calculate impulse scalar
				var impulse_scalar = -(1 + restitution) * velocity_along_normal
				impulse_scalar /= 1/a1.size + 1/a2.size
				
				# Apply impulse
				var impulse = collision_normal * impulse_scalar
				a1.velocity -= impulse / a1.size
				a2.velocity += impulse / a2.size
				
				# Push apart slightly to prevent sticking
				var separation_vector = collision_normal * (a1.collision_radius + a2.collision_radius - distance + 1)
				a1.position -= separation_vector * 0.5
				a2.position += separation_vector * 0.5
				
				# Update sprite positions
				if i < asteroid_sprites.size() and is_instance_valid(asteroid_sprites[i]):
					asteroid_sprites[i].position = a1.position
				
				if j < asteroid_sprites.size() and is_instance_valid(asteroid_sprites[j]):
					asteroid_sprites[j].position = a2.position

func _draw():
	# Optionally draw debug visuals
	if false:  # Set to true for debugging
		# Draw field boundary
		draw_circle_arc(position, field_radius, 0, TAU, Color(1, 1, 1, 0.2))
		
		# Draw asteroid collision radii
		for asteroid in asteroids:
			draw_circle_arc(asteroid.position, asteroid.collision_radius, 0, TAU, Color(1, 0, 0, 0.2))

# Helper function for drawing arcs
func draw_circle_arc(center, radius, angle_from, angle_to, color):
	var nb_points = 32
	var points_arc = PackedVector2Array()
	
	for i in range(nb_points + 1):
		var angle_point = angle_from + i * (angle_to - angle_from) / nb_points
		points_arc.push_back(center + Vector2(cos(angle_point), sin(angle_point)) * radius)
	
	for i in range(nb_points):
		draw_line(points_arc[i], points_arc[i + 1], color)
