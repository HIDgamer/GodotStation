extends Node2D

# Space debris system - small particles floating in space

# Configuration variables
@export var particle_count: int = 80
@export var emission_rect: Vector2 = Vector2(2500, 2500)
@export var debris_colors: Array[Color] = [
	Color(0.8, 0.8, 0.9, 0.3),
	Color(0.7, 0.7, 0.8, 0.3),
	Color(0.6, 0.6, 0.7, 0.3),
	Color(0.7, 0.8, 0.9, 0.3)
]
@export var size_range: Vector2 = Vector2(1, 8)
@export var velocity_range: Vector2 = Vector2(30, 80)
@export var spawn_distance: float = 1500.0
@export var despawn_distance: float = 2000.0

# Runtime variables
var rng = RandomNumberGenerator.new()
var particles: CPUParticles2D
var debris_objects = []

# Debris class - individual debris object with custom behavior
class DebrisObject:
	var position: Vector2
	var velocity: Vector2
	var size: float
	var color: Color
	var rotation_speed: float
	var current_rotation: float = 0.0
	var sprite: Sprite2D
	var type: int  # 0: dust, 1: small debris, 2: metal fragment
	
	func _init(p_params: Dictionary):
		position = p_params.get("position", Vector2.ZERO)
		velocity = p_params.get("velocity", Vector2.ZERO)
		size = p_params.get("size", 2.0)
		color = p_params.get("color", Color.WHITE)
		rotation_speed = p_params.get("rotation_speed", 0.1)
		type = p_params.get("type", 0)
		sprite = p_params.get("sprite", null)
	
	func update(delta: float):
		# Apply movement
		position += velocity * delta
		
		# Apply rotation
		current_rotation += rotation_speed * delta
		
		# Update sprite if available
		if sprite and is_instance_valid(sprite):
			sprite.position = position
			sprite.rotation = current_rotation

func _ready():
	# Get particles system
	particles = get_node_or_null("DebrisParticles")

func initialize(seed_value: int):
	# Set seed
	rng.seed = seed_value
	
	# Configure particles
	if particles:
		particles.emitting = false
		
		# Configure emission shape
		particles.emission_rect_extents = emission_rect / 2
		
		# Configure particle properties
		particles.amount = particle_count
		particles.lifetime = 20.0
		particles.direction = Vector2(0, 0)
		particles.spread = 180
		particles.initial_velocity_min = velocity_range.x
		particles.initial_velocity_max = velocity_range.y
		particles.scale_amount_min = size_range.x
		particles.scale_amount_max = size_range.y
		
		# Start emission
		particles.emitting = true
	
	# Create custom debris objects
	create_custom_debris()

func update(delta: float, current_time: float, player_position: Vector2):
	# Update custom debris objects
	update_debris_objects(delta)
	
	# Check for out-of-range debris and replace them
	manage_debris_range(player_position)
	
	# Redraw custom effects
	queue_redraw()

func create_custom_debris():
	# Clear existing debris
	for debris in debris_objects:
		if debris.sprite and is_instance_valid(debris.sprite):
			debris.sprite.queue_free()
	debris_objects.clear()
	
	# Create new debris objects with sprites
	var custom_count = 30  # Number of custom debris objects with sprites
	
	for i in range(custom_count):
		# Random position
		var pos = Vector2(
			rng.randf_range(-emission_rect.x/2, emission_rect.x/2),
			rng.randf_range(-emission_rect.y/2, emission_rect.y/2)
		)
		
		# Random velocity
		var angle = rng.randf() * TAU
		var speed = rng.randf_range(velocity_range.x, velocity_range.y)
		var vel = Vector2(cos(angle), sin(angle)) * speed
		
		# Random size and rotation
		var size = rng.randf_range(size_range.x * 1.5, size_range.y * 2)  # Larger than particles
		var rot_speed = rng.randf_range(-1.0, 1.0)
		
		# Random type
		var type = rng.randi() % 3
		
		# Color based on type
		var color = debris_colors[rng.randi() % debris_colors.size()]
		if type == 1:
			# Small debris - darker
			color = color.darkened(0.3)
		elif type == 2:
			# Metal fragment - shinier
			color = color.lightened(0.2)
		
		# Create sprite
		var debris_sprite = create_debris_sprite(type, size, color)
		add_child(debris_sprite)
		debris_sprite.position = pos
		
		# Create debris object
		var debris = DebrisObject.new({
			"position": pos,
			"velocity": vel,
			"size": size,
			"color": color,
			"rotation_speed": rot_speed,
			"type": type,
			"sprite": debris_sprite
		})
		
		debris_objects.append(debris)

func create_debris_sprite(type: int, size: float, color: Color) -> Sprite2D:
	var sprite = Sprite2D.new()
	
	# Create different appearance based on type
	match type:
		0:  # Dust
			# Simple circle gradient
			var gradient = Gradient.new()
			gradient.add_point(0.0, color)
			gradient.add_point(1.0, Color(color.r, color.g, color.b, 0.0))
			
			var texture = GradientTexture2D.new()
			texture.gradient = gradient
			texture.width = 16
			texture.height = 16
			texture.fill = GradientTexture2D.FILL_RADIAL
			texture.fill_from = Vector2(0.5, 0.5)
			texture.fill_to = Vector2(1.0, 0.5)
			
			sprite.texture = texture
			sprite.scale = Vector2(size / 16.0, size / 16.0)
			
		1:  # Small debris - irregular shape
			var polygon = Polygon2D.new()
			sprite.add_child(polygon)
			
			# Generate irregular polygon
			var points = []
			var point_count = rng.randi_range(4, 7)
			
			for i in range(point_count):
				var angle = i * TAU / point_count
				var radius = size * (0.7 + rng.randf() * 0.6)
				points.append(Vector2(cos(angle), sin(angle)) * radius)
			
			polygon.polygon = PackedVector2Array(points)
			polygon.color = color
			
			# Add outline
			var outline = Line2D.new()
			polygon.add_child(outline)
			outline.points = PackedVector2Array(points + [points[0]])  # Close the loop
			outline.width = 1.0
			outline.default_color = color.darkened(0.3)
			
		2:  # Metal fragment - angular with shine
			var polygon = Polygon2D.new()
			sprite.add_child(polygon)
			
			# Generate angular shape
			var points = []
			var point_count = rng.randi_range(3, 5)
			
			for i in range(point_count):
				var angle = i * TAU / point_count
				var radius = size * (0.8 + rng.randf() * 0.4)
				points.append(Vector2(cos(angle), sin(angle)) * radius)
			
			polygon.polygon = PackedVector2Array(points)
			polygon.color = color
			
			# Add shine spot
			var shine = Polygon2D.new()
			polygon.add_child(shine)
			
			var shine_points = []
			for p in points:
				shine_points.append(p * 0.5)
			
			shine.polygon = PackedVector2Array(shine_points)
			shine.color = color.lightened(0.5)
			shine.color.a = 0.7
			shine.position = Vector2(size * 0.1, -size * 0.1)
			
			# Add outline
			var outline = Line2D.new()
			polygon.add_child(outline)
			outline.points = PackedVector2Array(points + [points[0]])  # Close the loop
			outline.width = 2.0
			outline.default_color = color.lightened(0.2)
	
	# Apply canvas material for better blending
	var material = CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sprite.material = material
	
	return sprite

func update_debris_objects(delta: float):
	# Update all debris objects
	for debris in debris_objects:
		debris.update(delta)

func manage_debris_range(player_position: Vector2):
	# Check each debris object
	for debris in debris_objects:
		var distance = (debris.position - player_position).length()
		
		# If too far from player, reposition
		if distance > despawn_distance:
			# Create new position near player but in screen direction
			var angle = rng.randf() * TAU
			var spawn_pos = player_position + Vector2(cos(angle), sin(angle)) * spawn_distance
			
			# Reset the debris
			debris.position = spawn_pos
			
			# New velocity
			var new_angle = rng.randf() * TAU
			var new_speed = rng.randf_range(velocity_range.x, velocity_range.y)
			debris.velocity = Vector2(cos(new_angle), sin(new_angle)) * new_speed

func _draw():
	# Optional custom drawing for debug purposes
	if false:  # Set to true for debug visualization
		# Draw emission rect centered on origin
		var rect = Rect2(
			-emission_rect.x/2, -emission_rect.y/2,
			emission_rect.x, emission_rect.y
		)
		draw_rect(rect, Color(1, 1, 1, 0.1), false, 2.0)
