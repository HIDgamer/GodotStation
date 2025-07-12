extends Node2D

class_name ProceduralSpaceBackground

# Configuration variables
@export var enabled: bool = true
@export_group("Chunk Settings")
@export var track_world_chunks: bool = true
@export var chunk_size: int = 16 
@export var tile_size: int = 32
@export var render_distance: int = 3 # Chunks around player

@export_group("Star Settings")
@export var star_density: float = 0.2 # Stars per tile
@export var star_colors: Array[Color] = [
	Color(1.0, 1.0, 1.0, 1.0),      # White
	Color(0.9, 0.9, 1.0, 1.0),      # Light blue
	Color(1.0, 0.9, 0.7, 1.0),      # Yellow
	Color(1.0, 0.8, 0.8, 1.0),      # Light red
	Color(0.8, 0.8, 1.0, 1.0),      # Light blue
	Color(0.7, 1.0, 1.0, 1.0),      # Cyan
]
@export var star_size_min: float = 1.0
@export var star_size_max: float = 3.0
@export var star_twinkle_speed: float = 0.3
@export var star_twinkle_amount: float = 0.2

@export_group("Nebula Settings")
@export var nebula_chance: float = 0.1 # Chance per chunk
@export var nebula_colors: Array[Color] = [
	Color(0.5, 0.2, 0.7, 0.05),    # Purple
	Color(0.2, 0.5, 0.7, 0.05),    # Blue
	Color(0.7, 0.3, 0.2, 0.05),    # Red
	Color(0.2, 0.7, 0.3, 0.05),    # Green
	Color(0.7, 0.6, 0.2, 0.05),    # Yellow
]
@export var nebula_size_min: float = 5
@export var nebula_size_max: float = 10
@export var nebula_density: float = 0.6

@export_group("Celestial Body Settings")
@export var celestial_body_chance: float = 0.02 # Chance per chunk
@export var planets_enabled: bool = true
@export var distant_stars_enabled: bool = true

# Runtime variables
var noise = FastNoiseLite.new()
var plasma_noise = FastNoiseLite.new()
var loaded_chunks = {}
var rng = RandomNumberGenerator.new()
var world_reference = null
var player_position = Vector2.ZERO
var current_time: float = 0.0

# Precalculated arrays for performance
var all_star_coords = []
var all_star_props = []
var all_nebulae = []
var all_celestial_bodies = []

# Tilemap references
var floor_tilemap: TileMap = null
var wall_tilemap: TileMap = null
var objects_tilemap: TileMap = null

func _ready():
	# Set up noise generators
	noise.seed = randi()
	noise.frequency = 0.004
	noise.fractal_octaves = 4
	
	plasma_noise.seed = randi() + 100
	plasma_noise.frequency = 0.002
	plasma_noise.fractal_octaves = 3
	plasma_noise.fractal_lacunarity = 2.5
	
	# Try to find world reference
	world_reference = get_parent()
	
	if world_reference and track_world_chunks:
		# Try to connect to world's chunk loading signal
		if world_reference.has_signal("chunks_loaded"):
			world_reference.connect("chunks_loaded", _on_world_chunks_loaded)
			print("ProceduralSpaceBackground: Connected to world's chunks_loaded signal")
	
	# Get chunk_size and tile_size from world if available
	if world_reference and "CHUNK_SIZE" in world_reference:
		chunk_size = world_reference.CHUNK_SIZE
		print("ProceduralSpaceBackground: Using world's CHUNK_SIZE: ", chunk_size)
	
	if world_reference and "TILE_SIZE" in world_reference:
		tile_size = world_reference.TILE_SIZE
		print("ProceduralSpaceBackground: Using world's TILE_SIZE: ", tile_size)
	
	# Try to get references to tilemaps through world
	find_tilemap_references()
	
	# Initial load
	if enabled:
		call_deferred("load_initial_chunks")

func _process(delta):
	if not enabled:
		return
	
	# Update time for animations
	current_time += delta
	
	# If we need to update with player position
	update_player_position()
	
	# Only update every 30 frames for performance
	if Engine.get_frames_drawn() % 30 == 0:
		update_visible_chunks()
	
	# Force redraw
	queue_redraw()

func _draw():
	if not enabled:
		return
	
	# Draw the background
	var viewport_rect = get_viewport_rect()
	
	# Calculate visible region
	var camera = get_viewport().get_camera_2d()
	var visible_rect = Rect2()
	
	if camera:
		var zoom = camera.zoom
		var screen_size = get_viewport_rect().size
		visible_rect = Rect2(
			camera.global_position - (screen_size / 2) / zoom,
			screen_size / zoom
		)
	else:
		visible_rect = viewport_rect
	
	# Draw stars with twinkle effect
	for i in range(all_star_coords.size()):
		var star_pos = all_star_coords[i]
		var props = all_star_props[i]
		
		# Only draw if in visible area (optimization)
		if visible_rect.has_point(star_pos):
			# Check if this star's position is now occupied (for dynamic world changes)
			var tile_coords = Vector2i(int(star_pos.x / tile_size), int(star_pos.y / tile_size))
			if is_tile_occupied(tile_coords):
				continue
				
			# Twinkle effect
			var twinkle = sin(current_time * star_twinkle_speed + props.seed) * star_twinkle_amount + 1.0
			var final_size = props.size * twinkle
			var alpha = clamp(0.5 + 0.5 * sin(current_time * 0.5 + props.seed * 10), 0.7, 1.0)
			
			var star_color = props.color
			star_color.a = alpha
			
			draw_circle(star_pos, final_size, star_color)
			
			# Draw glow for brighter stars
			if props.size > star_size_max * 0.7:
				var glow_color = props.color
				glow_color.a = 0.2 * alpha
				draw_circle(star_pos, props.size * 2, glow_color)
	
	# Draw nebulae in the background
	for nebula in all_nebulae:
		# Only draw if in visible area (optimization)
		if visible_rect.grow(nebula.size * tile_size).has_point(nebula.position):
			draw_nebula(nebula)
	
	# Draw celestial bodies
	for body in all_celestial_bodies:
		# Only draw if in visible area (optimization)
		if visible_rect.grow(body.size * tile_size).has_point(body.position):
			draw_celestial_body(body)

func load_initial_chunks():
	# Find player to center around
	var player = find_player()
	if player:
		player_position = player.global_position
		
	# Load chunks around this position
	load_chunks_around(player_position, render_distance)

func update_player_position():
	var player = find_player()
	if player:
		player_position = player.global_position

func find_player():
	# First try to use world's player reference
	if world_reference and "local_player" in world_reference and world_reference.local_player:
		return world_reference.local_player
	
	# Otherwise, find player in scene
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]
	
	return null

func update_visible_chunks():
	# Get chunks around player
	var chunk_pos = world_pos_to_chunk(player_position)
	load_chunks_around(player_position, render_distance)
	
	# Unload far chunks
	var unload_distance = render_distance + 2
	var chunk_keys_to_remove = []
	
	for chunk_key in loaded_chunks.keys():
		var parts = chunk_key.split("_")
		var chunk_x = int(parts[0])
		var chunk_y = int(parts[1])
		
		var dx = abs(chunk_x - chunk_pos.x)
		var dy = abs(chunk_y - chunk_pos.y)
		
		if dx > unload_distance or dy > unload_distance:
			chunk_keys_to_remove.append(chunk_key)
	
	# Remove far chunks
	for key in chunk_keys_to_remove:
		loaded_chunks.erase(key)
		
		# Remove stars from those chunks
		var chunk_parts = key.split("_")
		var chunk_x = int(chunk_parts[0])
		var chunk_y = int(chunk_parts[1])
		
		unload_chunk_elements(Vector2i(chunk_x, chunk_y))

func load_chunks_around(center_pos: Vector2, distance: int):
	var center_chunk = world_pos_to_chunk(center_pos)
	var newly_loaded = []
	
	# Load chunks in square pattern around center
	for x in range(center_chunk.x - distance, center_chunk.x + distance + 1):
		for y in range(center_chunk.y - distance, center_chunk.y + distance + 1):
			var chunk_pos = Vector2i(x, y)
			var chunk_key = str(x) + "_" + str(y)
			
			if not chunk_key in loaded_chunks:
				load_chunk(chunk_pos)
				loaded_chunks[chunk_key] = true
				newly_loaded.append(chunk_pos)
	
	return newly_loaded

func load_chunk(chunk_pos: Vector2i):
	# Use deterministic seed based on chunk position
	var chunk_seed = abs(int(chunk_pos.x * 1731 + chunk_pos.y * 7919))
	rng.seed = chunk_seed
	
	# Calculate world coordinates for this chunk
	var chunk_world_pos = chunk_to_world_pos(chunk_pos)
	var chunk_size_pixels = chunk_size * tile_size
	
	# Generate stars in this chunk
	generate_stars_in_chunk(chunk_pos, chunk_seed)
	
	# Chance for a nebula
	if rng.randf() < nebula_chance:
		generate_nebula_in_chunk(chunk_pos, chunk_seed)
	
	# Chance for a celestial body (planet, distant star, etc)
	if rng.randf() < celestial_body_chance:
		generate_celestial_body_in_chunk(chunk_pos, chunk_seed)

func generate_stars_in_chunk(chunk_pos: Vector2i, seed_value: int):
	# Determine number of stars based on density
	var chunk_area = chunk_size * chunk_size
	var num_stars = int(chunk_area * star_density)
	
	# Set random seed for deterministic generation
	rng.seed = seed_value
	
	# Get chunk area in world coordinates
	var chunk_world_pos = chunk_to_world_pos(chunk_pos)
	
	# Generate stars
	for i in range(num_stars):
		# Random position within chunk
		var x = chunk_world_pos.x + rng.randi_range(0, chunk_size * tile_size - 1)
		var y = chunk_world_pos.y + rng.randi_range(0, chunk_size * tile_size - 1)
		var star_pos = Vector2(x, y)
		
		# Get tile coordinates for this position
		var tile_coords = Vector2i(int(x / tile_size), int(y / tile_size))
		
		# Skip if this tile is occupied by game elements
		if is_tile_occupied(tile_coords):
			continue
			
		# Random properties using the RNG
		var star_color = star_colors[rng.randi() % star_colors.size()]
		var star_size = rng.randf_range(star_size_min, star_size_max)
		
		# Special case: some stars are brighter
		if rng.randf() < 0.1:
			star_size *= 1.5
			# Slightly shift color toward white for bright stars
			star_color = star_color.lerp(Color(1,1,1,1), 0.3)
		
		# Add to the arrays for drawing
		all_star_coords.append(star_pos)
		all_star_props.append({
			"color": star_color,
			"size": star_size,
			"seed": rng.randf() * 1000,
			"chunk": chunk_pos
		})

func generate_nebula_in_chunk(chunk_pos: Vector2i, seed_value: int):
	# Set random seed for deterministic generation
	rng.seed = seed_value + 1  # Use a different seed than stars
	
	# Get chunk area in world coordinates
	var chunk_world_pos = chunk_to_world_pos(chunk_pos)
	
	# Check if this chunk overlaps significantly with game tiles
	if is_chunk_mostly_occupied(chunk_pos):
		return  # Skip nebula generation for this chunk
	
	# Random properties
	var nebula_color = nebula_colors[rng.randi() % nebula_colors.size()]
	
	# Size in tiles (can extend beyond chunk)
	var nebula_size = rng.randf_range(nebula_size_min, nebula_size_max)
	
	# Position (can be partially outside the chunk)
	var offset_x = rng.randf_range(-nebula_size/2, nebula_size/2) * tile_size
	var offset_y = rng.randf_range(-nebula_size/2, nebula_size/2) * tile_size
	
	var nebula_pos = Vector2(
		chunk_world_pos.x + chunk_size * tile_size / 2 + offset_x,
		chunk_world_pos.y + chunk_size * tile_size / 2 + offset_y
	)
	
	# Check central position of nebula
	var central_tile = Vector2i(int(nebula_pos.x / tile_size), int(nebula_pos.y / tile_size))
	if is_tile_occupied(central_tile):
		# Try to find a nearby unoccupied position
		var found = false
		for attempt in range(5):  # Try 5 times
			offset_x = rng.randf_range(-nebula_size, nebula_size) * tile_size
			offset_y = rng.randf_range(-nebula_size, nebula_size) * tile_size
			
			nebula_pos = Vector2(
				chunk_world_pos.x + chunk_size * tile_size / 2 + offset_x,
				chunk_world_pos.y + chunk_size * tile_size / 2 + offset_y
			)
			
			central_tile = Vector2i(int(nebula_pos.x / tile_size), int(nebula_pos.y / tile_size))
			if !is_tile_occupied(central_tile):
				found = true
				break
		
		if !found:
			return  # Skip nebula if no suitable position found
	
	# Create nebula data
	var nebula = {
		"position": nebula_pos,
		"color": nebula_color,
		"size": nebula_size,
		"density": nebula_density, 
		"seed": rng.randi(),
		"noise_offset": Vector2(rng.randf() * 1000, rng.randf() * 1000),
		"chunk": chunk_pos,
		"shape": rng.randi() % 3  # 0: circular, 1: elliptical, 2: irregular
	}
	
	# Add secondary color for some variation
	if rng.randf() < 0.5:
		nebula["color2"] = nebula_colors[rng.randi() % nebula_colors.size()]
		# Make sure it's not the same as primary color
		while nebula.color.is_equal_approx(nebula.color2):
			nebula["color2"] = nebula_colors[rng.randi() % nebula_colors.size()]
	
	all_nebulae.append(nebula)

func generate_celestial_body_in_chunk(chunk_pos: Vector2i, seed_value: int):
	# Set random seed for deterministic generation
	rng.seed = seed_value + 2  # Use a different seed than stars and nebulae
	
	# Get chunk area in world coordinates
	var chunk_world_pos = chunk_to_world_pos(chunk_pos)
	
	# Check if this chunk overlaps significantly with game tiles
	if is_chunk_mostly_occupied(chunk_pos):
		return  # Skip celestial body generation for this chunk
	
	# Decide between planet or distant star
	var is_planet = planets_enabled && rng.randf() < 0.7
	
	if !is_planet && !distant_stars_enabled:
		return
	
	# Position (can be partially outside the chunk)
	var body_pos = Vector2(
		chunk_world_pos.x + rng.randf_range(0, chunk_size * tile_size),
		chunk_world_pos.y + rng.randf_range(0, chunk_size * tile_size)
	)
	
	# Check if this position is occupied
	var central_tile = Vector2i(int(body_pos.x / tile_size), int(body_pos.y / tile_size))
	if is_tile_occupied(central_tile):
		# Try to find a nearby unoccupied position
		var found = false
		for attempt in range(5):  # Try 5 times
			body_pos = Vector2(
				chunk_world_pos.x + rng.randf_range(0, chunk_size * tile_size),
				chunk_world_pos.y + rng.randf_range(0, chunk_size * tile_size)
			)
			
			central_tile = Vector2i(int(body_pos.x / tile_size), int(body_pos.y / tile_size))
			if !is_tile_occupied(central_tile):
				found = true
				break
		
		if !found:
			return  # Skip celestial body if no suitable position found
	
	var body = {
		"position": body_pos,
		"chunk": chunk_pos,
		"is_planet": is_planet,
		"seed": rng.randi()
	}
	
	if is_planet:
		# Planet properties
		body["size"] = rng.randf_range(1.5, 4.0)  # Size in tiles
		body["color"] = Color(
			rng.randf_range(0.3, 0.9),
			rng.randf_range(0.3, 0.9),
			rng.randf_range(0.3, 0.9),
			1.0
		)
		
		# Planet features
		body["has_rings"] = rng.randf() < 0.3
		body["has_atmosphere"] = rng.randf() < 0.7
		body["atmosphere_color"] = Color(
			rng.randf_range(0.5, 0.9),
			rng.randf_range(0.5, 0.9),
			rng.randf_range(0.5, 0.9),
			0.3
		)
		
		# Surface features (determine terrain type)
		var terrain_type = rng.randi() % 5  # 0: rocky, 1: gas, 2: ice, 3: earth-like, 4: molten
		body["terrain_type"] = terrain_type
		
		# Adjust color based on terrain type
		match terrain_type:
			0:  # Rocky
				body.color = Color(rng.randf_range(0.6, 0.8), rng.randf_range(0.5, 0.7), rng.randf_range(0.4, 0.6), 1.0)
			1:  # Gas
				body.color = Color(rng.randf_range(0.6, 0.9), rng.randf_range(0.6, 0.9), rng.randf_range(0.7, 1.0), 1.0)
				body.has_rings = rng.randf() < 0.5  # More likely to have rings
			2:  # Ice
				body.color = Color(rng.randf_range(0.7, 0.9), rng.randf_range(0.8, 1.0), rng.randf_range(0.9, 1.0), 1.0)
			3:  # Earth-like
				body.color = Color(rng.randf_range(0.2, 0.5), rng.randf_range(0.4, 0.7), rng.randf_range(0.7, 0.9), 1.0)
				body.has_atmosphere = true
				body.atmosphere_color = Color(0.5, 0.7, 0.9, 0.3)
			4:  # Molten
				body.color = Color(rng.randf_range(0.7, 1.0), rng.randf_range(0.2, 0.5), rng.randf_range(0.0, 0.3), 1.0)
				body.has_atmosphere = true
				body.atmosphere_color = Color(0.7, 0.3, 0.2, 0.4)
	else:
		# Distant star properties
		body["size"] = rng.randf_range(0.7, 1.5)  # Size in tiles
		
		# Color based on star type (white, blue, yellow, red)
		var star_type = rng.randi() % 4
		match star_type:
			0:  # White
				body["color"] = Color(1.0, 1.0, 1.0, 1.0)
			1:  # Blue
				body["color"] = Color(0.7, 0.8, 1.0, 1.0)
			2:  # Yellow
				body["color"] = Color(1.0, 0.9, 0.6, 1.0)
			3:  # Red
				body["color"] = Color(1.0, 0.6, 0.5, 1.0)
		
		# Add glow effect to distant stars
		body["glow"] = true
		body["glow_size"] = rng.randf_range(1.5, 3.0)
		body["glow_color"] = body.color
		body.glow_color.a = 0.3
	
	all_celestial_bodies.append(body)

func unload_chunk_elements(chunk_pos: Vector2i):
	# Remove stars from this chunk
	var i = 0
	while i < all_star_props.size():
		if all_star_props[i].chunk == chunk_pos:
			all_star_props.remove_at(i)
			all_star_coords.remove_at(i)
		else:
			i += 1
	
	# Remove nebulae from this chunk
	i = 0
	while i < all_nebulae.size():
		if all_nebulae[i].chunk == chunk_pos:
			all_nebulae.remove_at(i)
		else:
			i += 1
	
	# Remove celestial bodies from this chunk
	i = 0
	while i < all_celestial_bodies.size():
		if all_celestial_bodies[i].chunk == chunk_pos:
			all_celestial_bodies.remove_at(i)
		else:
			i += 1

func draw_nebula(nebula):
	var nebula_rect = Rect2(
		nebula.position - Vector2(nebula.size * tile_size / 2, nebula.size * tile_size / 2),
		Vector2(nebula.size * tile_size, nebula.size * tile_size)
	)
	
	# Skip drawing points on occupied tiles
	var skip_occupied_tiles = true  # Set to false if you want to render nebula over occupied tiles
	
	var points_count = int(nebula.size * nebula.size * nebula.density * 20)
	var has_second_color = "color2" in nebula
	
	# Draw nebula based on shape
	match nebula.shape:
		0: # Circular
			# Draw cloud of points
			for i in range(points_count):
				var angle = rng.randf() * TAU
				var distance = rng.randf() * nebula.size * tile_size / 2
				
				var point_pos = nebula.position + Vector2(cos(angle), sin(angle)) * distance
				
				# Use noise to determine opacity
				var noise_val = plasma_noise.get_noise_2d(
					point_pos.x + nebula.noise_offset.x,
					point_pos.y + nebula.noise_offset.y
				)
				
				# Skip if noise value is too low
				if noise_val < 0:
					continue
				
				var point_color = nebula.color
				
				# Use second color if available
				if has_second_color && rng.randf() < 0.5:
					point_color = nebula.color2
				
				# Adjust alpha based on noise and distance from center
				var dist_factor = 1.0 - (distance / (nebula.size * tile_size / 2))
				point_color.a = point_color.a * noise_val * dist_factor
				
				# Skip if tile is occupied
				if skip_occupied_tiles:
					var tile_coords = Vector2i(int(point_pos.x / tile_size), int(point_pos.y / tile_size))
					if is_tile_occupied(tile_coords):
						continue
				
				# Skip if tile is occupied
				if skip_occupied_tiles:
					var tile_coords = Vector2i(int(point_pos.x / tile_size), int(point_pos.y / tile_size))
					if is_tile_occupied(tile_coords):
						continue
				
				# Skip if tile is occupied
				if skip_occupied_tiles:
					var tile_coords = Vector2i(int(point_pos.x / tile_size), int(point_pos.y / tile_size))
					if is_tile_occupied(tile_coords):
						continue
						
				# Draw point
				draw_circle(point_pos, rng.randf_range(1, 3), point_color)
		
		1: # Elliptical
			# Calculate ellipse parameters
			var a = nebula.size * tile_size / 2
			var b = a * rng.randf_range(0.5, 0.8)
			var angle = rng.randf() * TAU
			
			# Draw cloud of points
			for i in range(points_count):
				var t = rng.randf() * TAU
				var r = rng.randf()
				
				# Calculate point on ellipse
				var x = r * a * cos(t)
				var y = r * b * sin(t)
				
				# Rotate point
				var rotated_x = x * cos(angle) - y * sin(angle)
				var rotated_y = x * sin(angle) + y * cos(angle)
				
				var point_pos = nebula.position + Vector2(rotated_x, rotated_y)
				
				# Use noise to determine opacity
				var noise_val = plasma_noise.get_noise_2d(
					point_pos.x + nebula.noise_offset.x,
					point_pos.y + nebula.noise_offset.y
				)
				
				# Skip if noise value is too low
				if noise_val < 0:
					continue
				
				var point_color = nebula.color
				
				# Use second color if available
				if has_second_color && rng.randf() < 0.5:
					point_color = nebula.color2
				
				# Adjust alpha based on noise and distance from center
				var dist_factor = 1.0 - (Vector2(rotated_x, rotated_y).length() / a)
				point_color.a = point_color.a * noise_val * dist_factor
				
				# Draw point
				draw_circle(point_pos, rng.randf_range(1, 3), point_color)
		
		2: # Irregular
			# Draw cloud of points with noise-based distribution
			for i in range(points_count):
				var x = rng.randf_range(-1, 1) * nebula.size * tile_size / 2
				var y = rng.randf_range(-1, 1) * nebula.size * tile_size / 2
				
				var point_pos = nebula.position + Vector2(x, y)
				
				# Use noise to determine if we should draw this point
				var noise_val = plasma_noise.get_noise_2d(
					point_pos.x + nebula.noise_offset.x,
					point_pos.y + nebula.noise_offset.y
				)
				
				# Skip if noise value is too low - this creates the irregular shape
				if noise_val < 0.1:
					continue
				
				var point_color = nebula.color
				
				# Use second color if available
				if has_second_color && rng.randf() < 0.5:
					point_color = nebula.color2
				
				# Adjust alpha based on noise
				point_color.a = point_color.a * noise_val
				
				# Draw point
				draw_circle(point_pos, rng.randf_range(1, 3), point_color)

func draw_celestial_body(body):
	var radius = body.size * tile_size / 2
	
	# Check one last time if this position is now occupied (in case of dynamic world changes)
	var central_tile = Vector2i(int(body.position.x / tile_size), int(body.position.y / tile_size))
	if is_tile_occupied(central_tile):
		return  # Skip drawing this celestial body
	
	if body.is_planet:
		# Draw atmosphere if present
		if body.has_atmosphere:
			var atmosphere_radius = radius * 1.2
			draw_circle(body.position, atmosphere_radius, body.atmosphere_color)
		
		# Draw planet base
		draw_circle(body.position, radius, body.color)
		
		# Draw surface features based on terrain type
		match body.terrain_type:
			0:  # Rocky - add craters
				for i in range(3 + rng.randi() % 5):
					var crater_angle = rng.randf() * TAU
					var crater_dist = rng.randf_range(0, radius * 0.7)
					var crater_pos = body.position + Vector2(cos(crater_angle), sin(crater_angle)) * crater_dist
					var crater_size = rng.randf_range(radius * 0.05, radius * 0.2)
					
					# Darker color for crater
					var crater_color = body.color.darkened(0.3)
					draw_circle(crater_pos, crater_size, crater_color)
			
			1:  # Gas - add bands
				for i in range(3 + rng.randi() % 3):
					var band_width = radius * rng.randf_range(0.05, 0.15)
					var band_offset = radius * rng.randf_range(-0.6, 0.6)
					var band_color = body.color.lightened(rng.randf_range(-0.2, 0.2))
					
					var rect = Rect2(
						Vector2(body.position.x - radius, body.position.y + band_offset - band_width/2),
						Vector2(radius * 2, band_width)
					)
					
					# Create a clipping mask for the band
					var canvas_item = get_canvas_item()
					RenderingServer.canvas_item_add_circle(canvas_item, body.position, radius, body.color.darkened(0.1))
					draw_rect(rect, band_color, true)
			
			2:  # Ice - add white patches
				for i in range(5 + rng.randi() % 5):
					var patch_angle = rng.randf() * TAU
					var patch_dist = rng.randf_range(0, radius * 0.8)
					var patch_pos = body.position + Vector2(cos(patch_angle), sin(patch_angle)) * patch_dist
					var patch_size = rng.randf_range(radius * 0.1, radius * 0.3)
					
					# Lighter color for ice patch
					var patch_color = body.color.lightened(0.3)
					patch_color.a = 0.7
					draw_circle(patch_pos, patch_size, patch_color)
			
			3:  # Earth-like - add continent-like shapes
				var continent_color = Color(0.3, 0.5, 0.2, 0.8)  # Green for land
				
				for i in range(2 + rng.randi() % 3):
					var patch_angle = rng.randf() * TAU
					var patch_dist = rng.randf_range(0, radius * 0.6)
					var patch_pos = body.position + Vector2(cos(patch_angle), sin(patch_angle)) * patch_dist
					var patch_size = rng.randf_range(radius * 0.2, radius * 0.5)
					
					# Draw irregular continent
					var points = PackedVector2Array()
					var num_points = 8 + rng.randi() % 5
					
					for j in range(num_points):
						var angle = j * TAU / num_points
						var distance = patch_size * rng.randf_range(0.7, 1.3)
						points.append(patch_pos + Vector2(cos(angle), sin(angle)) * distance)
					
					draw_colored_polygon(points, continent_color)
			
			4:  # Molten - add lava flows
				var lava_color = Color(1.0, 0.5, 0.0, 0.8)
				
				for i in range(3 + rng.randi() % 4):
					var start_angle = rng.randf() * TAU
					var start_pos = body.position + Vector2(cos(start_angle), sin(start_angle)) * radius * 0.2
					
					var points = PackedVector2Array()
					points.append(start_pos)
					
					var current_pos = start_pos
					var current_angle = start_angle
					
					for j in range(5 + rng.randi() % 5):
						current_angle += rng.randf_range(-0.5, 0.5)
						var step_length = radius * rng.randf_range(0.1, 0.2)
						current_pos += Vector2(cos(current_angle), sin(current_angle)) * step_length
						
						# Ensure point stays within planet radius
						if (current_pos - body.position).length() > radius:
							var dir = (current_pos - body.position).normalized()
							current_pos = body.position + dir * (radius * 0.95)
						
						points.append(current_pos)
					
					# End at edge of planet
					var dir = (current_pos - body.position).normalized()
					points.append(body.position + dir * radius)
					
					# Draw lava flow
					draw_polyline(points, lava_color, radius * 0.1)
		
		# Draw rings if present
		if body.has_rings:
			var ring_inner = radius * 1.3
			var ring_outer = radius * 2.0
			
			# Draw multiple semi-transparent rings
			for i in range(3):
				var ring_color = body.color.lightened(0.2)
				ring_color.a = 0.2 - i * 0.05
				
				draw_arc(body.position, ring_inner + i * (ring_outer - ring_inner)/3, 0, TAU, 32, ring_color, 2)
	else:
		# Distant star
		
		# Draw glow
		if body.glow:
			for i in range(3):
				var glow_radius = radius * body.glow_size * (1.0 - i * 0.2)
				var glow_color = body.glow_color
				glow_color.a = glow_color.a * (1.0 - i * 0.3)
				
				draw_circle(body.position, glow_radius, glow_color)
		
		# Draw core
		draw_circle(body.position, radius, body.color)
		
		# Draw light rays (for effect)
		var ray_length = radius * 3
		var num_rays = 4 + rng.randi() % 4
		
		for i in range(num_rays):
			var angle = i * TAU / num_rays + current_time * 0.05
			var end_pos = body.position + Vector2(cos(angle), sin(angle)) * ray_length
			
			var ray_color = body.color
			ray_color.a = 0.3
			
			draw_line(body.position + Vector2(cos(angle), sin(angle)) * radius,
					 end_pos, ray_color)

func world_pos_to_chunk(world_pos: Vector2) -> Vector2i:
	var tile_x = int(world_pos.x / tile_size)
	var tile_y = int(world_pos.y / tile_size)
	
	var chunk_x = floor(tile_x / float(chunk_size))
	var chunk_y = floor(tile_y / float(chunk_size))
	
	return Vector2i(chunk_x, chunk_y)

func chunk_to_world_pos(chunk_pos: Vector2i) -> Vector2:
	return Vector2(chunk_pos.x * chunk_size * tile_size, chunk_pos.y * chunk_size * tile_size)

# Add these new utility functions for tile occupancy checking

func find_tilemap_references():
	"""Try to find references to the tilemaps through the world"""
	if world_reference:
		# Try to get tilemap references from world
		floor_tilemap = world_reference.get_node_or_null("VisualTileMap/FloorTileMap")
		wall_tilemap = world_reference.get_node_or_null("VisualTileMap/WallTileMap")
		objects_tilemap = world_reference.get_node_or_null("VisualTileMap/ObjectsTileMap")
		
		if floor_tilemap or wall_tilemap or objects_tilemap:
			print("ProceduralSpaceBackground: Found tilemap references")

func is_tile_occupied(tile_coords: Vector2i) -> bool:
	"""Check if a tile is occupied by any game tiles"""
	# First check with world's is_valid_tile function if available
	if world_reference and world_reference.has_method("is_valid_tile"):
		if world_reference.is_valid_tile(tile_coords, 0):  # Using z_level 0
			return true
	
	# Direct check with tilemaps
	if floor_tilemap and floor_tilemap.get_cell_source_id(0, tile_coords) != -1:
		return true
		
	if wall_tilemap and wall_tilemap.get_cell_source_id(0, tile_coords) != -1:
		return true
		
	if objects_tilemap and objects_tilemap.get_cell_source_id(0, tile_coords) != -1:
		return true
	
	# Check if there's a zone tilemap
	var zone_tilemap = world_reference.get_node_or_null("VisualTileMap/ZoneTileMap")
	if zone_tilemap and zone_tilemap.get_cell_source_id(0, tile_coords) != -1:
		return true
	
	return false

func is_chunk_mostly_occupied(chunk_pos: Vector2i) -> bool:
	"""Check if a significant portion of a chunk has game tiles"""
	var occupied_count = 0
	var sample_points = 9  # Check 9 points in the chunk (3x3 grid)
	
	var chunk_world_pos = chunk_to_world_pos(chunk_pos)
	var step = chunk_size * tile_size / 4  # Divide chunk into 4x4 grid for sampling
	
	# Check a 3x3 grid of sample points
	for x in range(1, 4):
		for y in range(1, 4):
			var sample_pos = Vector2(
				chunk_world_pos.x + x * step,
				chunk_world_pos.y + y * step
			)
			
			var tile_coords = Vector2i(int(sample_pos.x / tile_size), int(sample_pos.y / tile_size))
			if is_tile_occupied(tile_coords):
				occupied_count += 1
	
	# If more than 1/3 of sample points are occupied, consider the chunk mostly occupied
	return occupied_count > (sample_points / 3)

func _on_world_chunks_loaded(chunk_positions, z_level):
	# Only care about z-level 0 for now
	if z_level != 0:
		return
	
	# Load space background for these chunks
	for chunk_pos in chunk_positions:
		var chunk_key = str(chunk_pos.x) + "_" + str(chunk_pos.y)
		if not chunk_key in loaded_chunks:
			load_chunk(chunk_pos)
			loaded_chunks[chunk_key] = true
