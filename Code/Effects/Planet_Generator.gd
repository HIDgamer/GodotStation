extends Node2D

# Planet generator system - creates diverse, animated planets with texture support

# Configuration variables
@export var planet_count: int = 7
@export var planet_types: Array[String] = ["rocky", "gas", "ice", "earth", "volcanic", "ringed", "desert"]
@export var min_distance: float = 3000.0
@export var max_distance: float = 8000.0
@export var size_range: Vector2 = Vector2(200, 800)
@export var movement_speed_range: Vector2 = Vector2(0.02, 0.1)

# Planet texture settings
@export_group("Planet Textures")
@export var use_textures: bool = true
@export var gas_planet_textures: Array[Texture2D]
@export var ice_planet_textures: Array[Texture2D]
@export var desert_planet_textures: Array[Texture2D]
@export var moon_textures: Array[Texture2D]

# Visual effect settings
@export_group("Visual Effects")
@export var atmosphere_glow: bool = true
@export var cloud_layers: bool = true
@export var surface_details: bool = true
@export var ring_quality: int = 1  # 1=low, 2=medium, 3=high

# Runtime variables
var rng = RandomNumberGenerator.new()
var planets = []
var planet_nodes = []
var planet_materials = {}
var current_time: float = 0.0

# Planet class - handles individual planet behavior
class Planet:
	var position: Vector2
	var size: float
	var type: String
	var color: Color
	var secondary_color: Color
	var rotation_speed: float
	var orbit_speed: float
	var orbit_distance: float
	var orbit_center: Vector2
	var orbit_angle: float
	var has_atmosphere: bool
	var atmosphere_color: Color
	var has_rings: bool
	var ring_color: Color
	var unique_seed: int
	var moons: Array = []
	var surface_details = {}
	var texture: Texture2D = null
	var cloud_texture: Texture2D = null
	var ring_texture: Texture2D = null
	var node: Node2D = null
	
	func _init(p_params: Dictionary):
		# Transfer all parameters to properties
		position = p_params.get("position", Vector2.ZERO)
		size = p_params.get("size", 100.0)
		type = p_params.get("type", "rocky")
		color = p_params.get("color", Color.WHITE)
		secondary_color = p_params.get("secondary_color", Color.GRAY)
		rotation_speed = p_params.get("rotation_speed", 0.1)
		orbit_speed = p_params.get("orbit_speed", 0.0)
		orbit_distance = p_params.get("orbit_distance", 0.0)
		orbit_center = p_params.get("orbit_center", Vector2.ZERO)
		orbit_angle = p_params.get("orbit_angle", 0.0)
		has_atmosphere = p_params.get("has_atmosphere", false)
		atmosphere_color = p_params.get("atmosphere_color", Color(0.5, 0.7, 1.0, 0.3))
		has_rings = p_params.get("has_rings", false)
		ring_color = p_params.get("ring_color", Color(0.7, 0.7, 0.8, 0.5))
		unique_seed = p_params.get("unique_seed", 0)
		texture = p_params.get("texture", null)
		cloud_texture = p_params.get("cloud_texture", null)
		ring_texture = p_params.get("ring_texture", null)
		node = p_params.get("node", null)
		
		# Copy moons if provided
		if "moons" in p_params:
			moons = p_params.moons.duplicate()
		
		# Copy surface details if provided
		if "surface_details" in p_params:
			surface_details = p_params.surface_details.duplicate()
	
	func update(delta: float, current_time: float):
		# Update orbit position if planet orbits
		if orbit_distance > 0.0:
			orbit_angle += orbit_speed * delta
			position = orbit_center + Vector2(
				cos(orbit_angle) * orbit_distance,
				sin(orbit_angle) * orbit_distance
			)
			
			# Update node position if it exists
			if node:
				node.position = position
		
		# Update moons
		for moon in moons:
			moon.orbit_angle += moon.orbit_speed * delta
			moon.position = position + Vector2(
				cos(moon.orbit_angle) * moon.orbit_distance,
				sin(moon.orbit_angle) * moon.orbit_distance
			)
			
			# Update moon node position if it exists
			if moon.node:
				moon.node.position = moon.position
		
		# Update any surface animations or effects (implemented by planet types)
		match type:
			"gas":
				# Animate gas bands and cloud layers
				if "cloud_layer" in surface_details and surface_details.cloud_layer:
					var cloud_rotation = surface_details.cloud_layer.rotation
					cloud_rotation += delta * surface_details.cloud_speed
					surface_details.cloud_layer.rotation = cloud_rotation

# Moon class - simplified planet for moons
class Moon:
	var position: Vector2
	var size: float
	var color: Color
	var orbit_distance: float
	var orbit_angle: float
	var orbit_speed: float
	var texture: Texture2D = null
	var node: Node2D = null
	
	func _init(p_params: Dictionary):
		position = p_params.get("position", Vector2.ZERO)
		size = p_params.get("size", 20.0)
		color = p_params.get("color", Color.LIGHT_GRAY)
		orbit_distance = p_params.get("orbit_distance", 100.0)
		orbit_angle = p_params.get("orbit_angle", 0.0)
		orbit_speed = p_params.get("orbit_speed", 0.5)
		texture = p_params.get("texture", null)
		node = p_params.get("node", null)

func _ready():
	# Initialize materials
	initialize_materials()

func initialize_materials():
	# Create material for planets with atmosphere
	var atmosphere_material = CanvasItemMaterial.new()
	atmosphere_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	planet_materials["atmosphere"] = atmosphere_material
	
	# Create material for planet rings
	var ring_material = CanvasItemMaterial.new()
	ring_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	planet_materials["ring"] = ring_material
	
	# Create material for lava/glow
	var glow_material = CanvasItemMaterial.new()
	glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	planet_materials["glow"] = glow_material

func initialize(seed_value: int):
	# Set seed
	rng.seed = seed_value
	
	# Generate planets
	generate_planets()

func update(delta: float, time: float):
	# Store current time
	current_time = time
	
	# Update planets
	for planet in planets:
		planet.update(delta, current_time)

func generate_planets():
	# Clear existing planets
	planets.clear()
	
	# Remove existing planet nodes
	for node in planet_nodes:
		if is_instance_valid(node):
			node.queue_free()
	planet_nodes.clear()
	
	# Create new planets
	for i in range(planet_count):
		# Create planet with random properties
		var planet_type = planet_types[rng.randi() % planet_types.size()]
		
		# Generate position with good distribution
		var angle = rng.randf() * TAU
		var distance = rng.randf_range(min_distance, max_distance)
		var pos = Vector2(cos(angle), sin(angle)) * distance
		
		# Generate size
		var size = rng.randf_range(size_range.x, size_range.y)
		
		# Determine if planet has orbital movement
		var is_orbiting = rng.randf() < 0.7
		var orbit_params = {}
		
		if is_orbiting:
			orbit_params = {
				"orbit_center": Vector2.ZERO,
				"orbit_distance": distance,
				"orbit_angle": angle,
				"orbit_speed": rng.randf_range(0.01, 0.05) # radians per second
			}
		
		# Create base planet parameters
		var planet_params = {
			"position": pos,
			"size": size,
			"type": planet_type,
			"rotation_speed": rng.randf_range(0.01, 0.1),
			"unique_seed": rng.randi(),
			"has_atmosphere": planet_type in ["gas", "earth", "volcanic"],
			"has_rings": planet_type == "ringed" or (planet_type == "gas" and rng.randf() < 0.7)
		}
		
		# Add orbit parameters if applicable
		if is_orbiting:
			planet_params.merge(orbit_params)
		
		# Select texture based on planet type
		if use_textures:
			match planet_type:
				"gas":
					if gas_planet_textures.size() > 0:
						planet_params["texture"] = gas_planet_textures[rng.randi() % gas_planet_textures.size()]
				"ice":
					if ice_planet_textures.size() > 0:
						planet_params["texture"] = ice_planet_textures[rng.randi() % ice_planet_textures.size()]
				"desert":
					if desert_planet_textures.size() > 0:
						planet_params["texture"] = desert_planet_textures[rng.randi() % desert_planet_textures.size()]
		
		# Add planet-type specific properties
		match planet_type:
			"gas":
				planet_params["color"] = Color(rng.randf_range(0.6, 0.9), rng.randf_range(0.6, 0.9), rng.randf_range(0.7, 1.0))
				planet_params["secondary_color"] = planet_params.color.lightened(0.2)
				planet_params["atmosphere_color"] = Color(planet_params.color.r, planet_params.color.g, planet_params.color.b, 0.4)
				planet_params["surface_details"] = {
					"band_count": rng.randi_range(3, 6),
					"band_contrast": rng.randf_range(0.1, 0.3),
					"cloud_speed": rng.randf_range(0.02, 0.1)
				}
			"ice":
				planet_params["color"] = Color(rng.randf_range(0.7, 0.9), rng.randf_range(0.8, 1.0), rng.randf_range(0.9, 1.0))
				planet_params["secondary_color"] = Color(0.8, 0.9, 1.0, 0.8)
				planet_params["surface_details"] = {
					"crack_count": rng.randi_range(4, 8),
					"ice_patch_count": rng.randi_range(5, 10)
				}
			"ringed":
				planet_params["color"] = Color(rng.randf_range(0.6, 0.8), rng.randf_range(0.6, 0.8), rng.randf_range(0.7, 0.9))
				planet_params["secondary_color"] = planet_params.color.lightened(0.2)
				planet_params["ring_color"] = Color(rng.randf_range(0.7, 0.9), rng.randf_range(0.7, 0.9), rng.randf_range(0.7, 0.9), 0.7)
				planet_params["surface_details"] = {
					"ring_inner_radius": size * 1.3,
					"ring_outer_radius": size * 2.2,
					"ring_tilt": rng.randf_range(-0.3, 0.3)
				}
			"desert":
				planet_params["color"] = Color(rng.randf_range(0.8, 0.9), rng.randf_range(0.6, 0.8), rng.randf_range(0.2, 0.5))
				planet_params["secondary_color"] = planet_params.color.darkened(0.3)
				planet_params["surface_details"] = {
					"dune_count": rng.randi_range(5, 10),
					"dune_size": rng.randf_range(size * 0.1, size * 0.3)
				}
		
		# Add moons to some planets
		var moon_count = 0
		if size > 400:
			moon_count = rng.randi_range(1, 3)
		elif size > 300:
			moon_count = rng.randi_range(0, 2)
		elif size > 200:
			moon_count = rng.randi_range(0, 1)
		
		var moons = []
		for m in range(moon_count):
			var moon_size = size * rng.randf_range(0.1, 0.25)
			var moon_distance = size * rng.randf_range(1.5, 3.0)
			var moon_angle = rng.randf() * TAU
			var moon_speed = rng.randf_range(0.2, 0.5)
			
			# Choose random moon texture if available
			var moon_texture = null
			if use_textures and moon_textures.size() > 0:
				moon_texture = moon_textures[rng.randi() % moon_textures.size()]
			
			var moon_params = {
				"position": Vector2.ZERO,  # Will be set during update
				"size": moon_size,
				"color": Color(rng.randf_range(0.6, 0.8), rng.randf_range(0.6, 0.8), rng.randf_range(0.6, 0.8)),
				"orbit_distance": moon_distance,
				"orbit_angle": moon_angle,
				"orbit_speed": moon_speed,
				"texture": moon_texture
			}
			
			moons.append(Moon.new(moon_params))
		
		planet_params["moons"] = moons
		
		# Create planet object
		var planet = Planet.new(planet_params)
		planets.append(planet)
		
		# Create node for planet
		create_planet_node(planet)

func create_planet_node(planet):
	# Create a Node2D to hold all parts of the planet
	var planet_node = Node2D.new()
	add_child(planet_node)
	planet_node.position = planet.position
	
	# Store reference to node in planet object
	planet.node = planet_node
	
	# Create base planet sprite
	var sprite = Sprite2D.new()
	planet_node.add_child(sprite)
	
	# Use texture if provided, otherwise create a gradient
	if planet.texture != null:
		sprite.texture = planet.texture
	else:
		# Create a gradient texture
		var gradient = Gradient.new()
		gradient.add_point(0.0, planet.color)
		gradient.add_point(0.7, planet.color.darkened(0.2))
		gradient.add_point(1.0, planet.color.darkened(0.4))
		
		var texture = GradientTexture2D.new()
		texture.gradient = gradient
		texture.width = 256
		texture.height = 256
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.4, 0.4)  # Slightly offset for 3D look
		texture.fill_to = Vector2(1.2, 1.2)
		
		sprite.texture = texture
	
	# Set size
	sprite.scale = Vector2(planet.size / sprite.texture.get_width(), planet.size / sprite.texture.get_height())
	
	# Set rotation speed
	var rotator = Timer.new()
	rotator.wait_time = 0.05  # Update rotation 20 times per second
	rotator.autostart = true
	rotator.timeout.connect(_on_planet_rotation_timer.bind(sprite, planet.rotation_speed))
	planet_node.add_child(rotator)
	
	# Add type-specific details
	match planet.type:
				
		"gas":
			# Add cloud layer
			if cloud_layers:
				var cloud_layer = add_cloud_layer(planet_node, planet)
				planet.surface_details["cloud_layer"] = cloud_layer
			
			# Add atmosphere glow
			if atmosphere_glow and planet.has_atmosphere:
				add_atmosphere(planet_node, planet)
				
		"ice":
			# Add ice details
			if surface_details and not planet.texture:
				add_ice_details(planet_node, planet)
				
		"ringed":
			# Add rings
			if planet.has_rings:
				add_rings(planet_node, planet)
				
		"desert":
			# Add desert details
			if surface_details and not planet.texture:
				add_desert_details(planet_node, planet)
	
	# Add moons
	for moon in planet.moons:
		create_moon_node(planet_node, moon)
	
	# Store the node
	planet_nodes.append(planet_node)

# Helper functions for planet type-specific details

func add_cloud_layer(planet_node, planet):
	# Add cloud layer to gas planets and earth-like planets
	var cloud_sprite = Sprite2D.new()
	planet_node.add_child(cloud_sprite)
	
	# Create cloud texture
	var cloud_gradient = Gradient.new()
	
	if planet.type == "gas":
		cloud_gradient.add_point(0.0, Color(1,1,1,0))
		cloud_gradient.add_point(0.4, Color(1,1,1,0))
		cloud_gradient.add_point(0.7, Color(1,1,1,0.2))
		cloud_gradient.add_point(1.0, Color(1,1,1,0.4))
	else:  # Earth-like
		cloud_gradient.add_point(0.0, Color(1,1,1,0))
		cloud_gradient.add_point(0.5, Color(1,1,1,0))
		cloud_gradient.add_point(0.7, Color(1,1,1,0.3))
		cloud_gradient.add_point(1.0, Color(1,1,1,0.7))
	
	var cloud_texture = GradientTexture2D.new()
	cloud_texture.gradient = cloud_gradient
	cloud_texture.width = 256
	cloud_texture.height = 256
	cloud_texture.fill = GradientTexture2D.FILL_RADIAL
	cloud_texture.fill_from = Vector2(0.5, 0.5)
	cloud_texture.fill_to = Vector2(1.0, 1.0)
	
	# Or use texture if provided
	if planet.cloud_texture != null:
		cloud_sprite.texture = planet.cloud_texture
	else:
		cloud_sprite.texture = cloud_texture
	
	# Size and blend mode
	cloud_sprite.scale = Vector2(
		planet.size * 1.1 / cloud_sprite.texture.get_width(),
		planet.size * 1.1 / cloud_sprite.texture.get_height()
	)
	
	if "cloud" in planet_materials:
		cloud_sprite.material = planet_materials.cloud
	
	return cloud_sprite

func add_atmosphere(planet_node, planet):
	# Add atmosphere glow
	var atmo_sprite = Sprite2D.new()
	planet_node.add_child(atmo_sprite)
	
	var atmo_gradient = Gradient.new()
	atmo_gradient.add_point(0.0, Color(planet.atmosphere_color.r, planet.atmosphere_color.g, planet.atmosphere_color.b, 0.0))
	atmo_gradient.add_point(0.7, planet.atmosphere_color)
	atmo_gradient.add_point(1.0, Color(planet.atmosphere_color.r, planet.atmosphere_color.g, planet.atmosphere_color.b, 0.0))
	
	var atmo_texture = GradientTexture2D.new()
	atmo_texture.gradient = atmo_gradient
	atmo_texture.width = 512
	atmo_texture.height = 512
	atmo_texture.fill = GradientTexture2D.FILL_RADIAL
	atmo_texture.fill_from = Vector2(0.5, 0.5)
	atmo_texture.fill_to = Vector2(1.0, 1.0)
	
	atmo_sprite.texture = atmo_texture
	atmo_sprite.scale = Vector2(1.2 * planet.size / 512.0, 1.2 * planet.size / 512.0)
	
	if "atmosphere" in planet_materials:
		atmo_sprite.material = planet_materials.atmosphere

func add_ice_details(planet_node, planet):
	# Add ice details to ice planets
	var ice_container = Node2D.new()
	planet_node.add_child(ice_container)
	
	# Add ice patches
	for i in range(planet.surface_details.ice_patch_count):
		var ice_patch = Sprite2D.new()
		ice_container.add_child(ice_patch)
		
		# Create ice patch texture
		var ice_gradient = Gradient.new()
		ice_gradient.add_point(0.0, planet.secondary_color)
		ice_gradient.add_point(0.7, planet.secondary_color.lightened(0.2))
		ice_gradient.add_point(1.0, Color(planet.secondary_color.r, planet.secondary_color.g, planet.secondary_color.b, 0.0))
		
		var ice_texture = GradientTexture2D.new()
		ice_texture.gradient = ice_gradient
		ice_texture.width = 128
		ice_texture.height = 128
		ice_texture.fill = GradientTexture2D.FILL_RADIAL
		ice_texture.fill_from = Vector2(0.4, 0.4)
		ice_texture.fill_to = Vector2(1.0, 1.0)
		
		ice_patch.texture = ice_texture
		
		# Position and size
		var angle = rng.randf() * TAU
		var distance = planet.size * rng.randf_range(0.2, 0.7)
		ice_patch.position = Vector2(cos(angle), sin(angle)) * distance
		
		var patch_size = planet.size * rng.randf_range(0.1, 0.3)
		ice_patch.scale = Vector2(patch_size/128, patch_size/128)
		
		# Random rotation
		ice_patch.rotation = rng.randf() * TAU
		
		# Blend mode for ice patches
		var material = CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		ice_patch.material = material

func add_rings(planet_node, planet):
	# Add rings to ringed planets
	var ring_sprite = Sprite2D.new()
	planet_node.add_child(ring_sprite)
	
	# Use texture if provided, otherwise create one
	if planet.ring_texture != null:
		ring_sprite.texture = planet.ring_texture
	else:
		var ring_gradient = Gradient.new()
		ring_gradient.add_point(0.0, Color(0,0,0,0))
		ring_gradient.add_point(0.4, Color(0,0,0,0))
		ring_gradient.add_point(0.6, planet.ring_color)
		ring_gradient.add_point(0.8, planet.ring_color)
		ring_gradient.add_point(1.0, Color(0,0,0,0))
		
		var ring_texture = GradientTexture2D.new()
		ring_texture.gradient = ring_gradient
		ring_texture.width = 512
		ring_texture.height = 128
		ring_texture.fill = GradientTexture2D.FILL_RADIAL
		ring_texture.fill_from = Vector2(0.5, 0.5)
		ring_texture.fill_to = Vector2(1.0, 0.5)
		
		ring_sprite.texture = ring_texture
	
	# Set ring size and orientation
	ring_sprite.scale = Vector2(2.0 * planet.size / 512.0, 0.5 * planet.size / 128.0)
	
	# Apply tilt
	var tilt = planet.surface_details.ring_tilt
	ring_sprite.rotation = PI * tilt
	
	# Set material
	if "ring" in planet_materials:
		ring_sprite.material = planet_materials.ring

func add_desert_details(planet_node, planet):
	# Add desert details
	var dunes_container = Node2D.new()
	planet_node.add_child(dunes_container)
	
	# Add dune patterns
	for i in range(planet.surface_details.dune_count):
		var dune = Sprite2D.new()
		dunes_container.add_child(dune)
		
		# Create dune texture
		var dune_gradient = Gradient.new()
		dune_gradient.add_point(0.0, planet.secondary_color.darkened(0.3))
		dune_gradient.add_point(0.3, planet.secondary_color)
		dune_gradient.add_point(0.7, planet.secondary_color.lightened(0.1))
		dune_gradient.add_point(1.0, Color(planet.secondary_color.r, planet.secondary_color.g, planet.secondary_color.b, 0.0))
		
		var dune_texture = GradientTexture2D.new()
		dune_texture.gradient = dune_gradient
		dune_texture.width = 128
		dune_texture.height = 64
		dune_texture.fill = GradientTexture2D.FILL_LINEAR
		dune_texture.fill_from = Vector2(0, 0.5)
		dune_texture.fill_to = Vector2(1, 0.5)
		
		dune.texture = dune_texture
		
		# Position and size
		var angle = rng.randf() * TAU
		var distance = planet.size * rng.randf_range(0.2, 0.7)
		dune.position = Vector2(cos(angle), sin(angle)) * distance
		
		var dune_size = planet.surface_details.dune_size
		dune.scale = Vector2(dune_size/128, dune_size/64)
		
		# Random rotation
		dune.rotation = rng.randf() * TAU
		
		# Blend mode for dunes
		var material = CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
		dune.material = material

func create_moon_node(planet_node, moon):
	# Create node for moon
	var moon_sprite = Sprite2D.new()
	planet_node.add_child(moon_sprite)
	
	# Use texture if provided, otherwise create a gradient
	if moon.texture != null:
		moon_sprite.texture = moon.texture
	else:
		# Create texture
		var gradient = Gradient.new()
		gradient.add_point(0.0, moon.color)
		gradient.add_point(0.6, moon.color.darkened(0.2))
		gradient.add_point(1.0, moon.color.darkened(0.5))
		
		var texture = GradientTexture2D.new()
		texture.gradient = gradient
		texture.width = 128
		texture.height = 128
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.4, 0.4)
		texture.fill_to = Vector2(1.2, 1.2)
		
		moon_sprite.texture = texture
	
	# Set position and size
	moon_sprite.position = moon.position
	moon_sprite.scale = Vector2(
		moon.size / moon_sprite.texture.get_width(), 
		moon.size / moon_sprite.texture.get_height()
	)
	
	# Create simple shadow overlay
	var shadow = Sprite2D.new()
	moon_sprite.add_child(shadow)
	
	var shadow_gradient = Gradient.new()
	shadow_gradient.add_point(0.0, Color(0,0,0,0.5))
	shadow_gradient.add_point(0.5, Color(0,0,0,0.2))
	shadow_gradient.add_point(1.0, Color(0,0,0,0))
	
	var shadow_texture = GradientTexture2D.new()
	shadow_texture.gradient = shadow_gradient
	shadow_texture.width = 128
	shadow_texture.height = 128
	shadow_texture.fill = GradientTexture2D.FILL_RADIAL
	shadow_texture.fill_from = Vector2(0.3, 0.3)
	shadow_texture.fill_to = Vector2(0.8, 0.8)
	
	shadow.texture = shadow_texture
	shadow.scale = Vector2(1.0, 1.0)
	
	# Set blend mode
	var material = CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	shadow.material = material
	
	# Store reference to node in moon object
	moon.node = moon_sprite

func _on_planet_rotation_timer(sprite, rotation_speed):
	# Rotate the planet sprite
	sprite.rotation += rotation_speed
