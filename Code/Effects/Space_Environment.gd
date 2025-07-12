extends Node2D

# Main controller for the space environment
# Handles player tracking and delegates to specialized systems

# Configuration variables
@export var enabled: bool = true
@export var player_path: NodePath
@export var chunk_size: int = 16 
@export var tile_size: int = 32
@export var render_distance: int = 3

# Runtime variables
var player = null
var last_player_pos = Vector2.ZERO
var last_chunk_pos = Vector2i.ZERO
var noise = FastNoiseLite.new()
var rng = RandomNumberGenerator.new()
var current_time: float = 0.0
var loaded_chunks = {}

# Tilemaps for collision detection (optional)
var floor_tilemap: TileMap = null
var wall_tilemap: TileMap = null
var objects_tilemap: TileMap = null

# Optimization variables
var update_interval: int = 5  # Update every 5 frames
var update_counter: int = 0

# System references
var star_fields = []
var nebula_generator = null
var planet_generator = null
var asteroid_fields = []
var sun = null
var space_debris = null

func _ready():
	# Initialize systems
	rng.randomize()
	noise.seed = rng.randi()
	noise.frequency = 0.005
	noise.fractal_octaves = 4
	
	# Find player
	if player_path:
		player = get_node_or_null(player_path)
	else:
		player = find_player()
	
	# Find world reference and try to get tilemap references
	var world = get_parent()
	if world:
		find_tilemap_references(world)
	
	# Get references to all systems
	initialize_system_references()
	
	# Initialize all systems
	call_deferred("initialize_all_systems")

func _process(delta):
	if not enabled:
		return
	
	# Update time for animations
	current_time += delta
	
	# Find player if not already found
	if not player:
		player = find_player()
		if not player:
			return
	
	update_counter += 1
	if update_counter >= update_interval:
		update_counter = 0
		
		# Check if player moved to a new chunk
		var player_pos = player.global_position
		var current_chunk_pos = world_pos_to_chunk(player_pos)
		
		if current_chunk_pos != last_chunk_pos or (player_pos - last_player_pos).length() > 500:
			# Update visible chunks
			update_visible_chunks(player_pos)
			last_player_pos = player_pos
			last_chunk_pos = current_chunk_pos
	
	# Update all systems
	update_all_systems(delta)

func initialize_system_references():
	# Get references to star fields
	star_fields.append(get_node_or_null("ParallaxBackground/DeepStarsLayer/StarField"))
	star_fields.append(get_node_or_null("ParallaxBackground/MidStarsLayer/StarField"))
	star_fields.append(get_node_or_null("ParallaxBackground/NearStarsLayer/StarField"))
	
	# Get reference to nebula generator
	nebula_generator = get_node_or_null("ParallaxBackground/NebulaLayer/NebulaGenerator")
	
	# Get reference to planet generator
	planet_generator = get_node_or_null("ParallaxBackground/PlanetLayer/PlanetGenerator")
	
	# Get reference to asteroid fields
	asteroid_fields.append(get_node_or_null("MidgroundLayer/AsteroidField1"))
	asteroid_fields.append(get_node_or_null("MidgroundLayer/AsteroidField2"))
	
	# Get reference to sun
	sun = get_node_or_null("ParallaxBackground/SunLayer/Sun")
	
	# Get reference to space debris
	space_debris = get_node_or_null("ForegroundLayer/SpaceDebris")

func initialize_all_systems():
	# Initialize star fields
	for field in star_fields:
		if field:
			field.initialize(rng.randi())
	
	# Initialize nebula generator
	if nebula_generator:
		nebula_generator.initialize(rng.randi())
	
	# Initialize planet generator
	if planet_generator:
		planet_generator.initialize(rng.randi())
	
	# Initialize asteroid fields
	for field in asteroid_fields:
		if field:
			field.initialize(rng.randi())
	
	# Initialize sun
	if sun:
		sun.initialize()
	
	# Initialize space debris
	if space_debris:
		space_debris.initialize(rng.randi())
	
	# Initial update
	if player:
		update_visible_chunks(player.global_position)

func update_all_systems(delta):
	# Update parallax background position based on player
	if player:
		var parallax = get_node_or_null("ParallaxBackground")
		if parallax:
			parallax.scroll_offset = -player.global_position
	
	# Update star fields
	for field in star_fields:
		if field:
			field.update(delta, current_time)
	
	# Update nebula generator
	if nebula_generator:
		nebula_generator.update(delta, current_time)
	
	# Update planet generator
	if planet_generator:
		planet_generator.update(delta, current_time)
	
	# Update asteroid fields
	for field in asteroid_fields:
		if field:
			field.update(delta, current_time, player.global_position if player else Vector2.ZERO)
	
	# Update sun
	if sun:
		sun.update(delta, current_time)
	
	# Update space debris
	if space_debris:
		space_debris.update(delta, current_time, player.global_position if player else Vector2.ZERO)

func update_visible_chunks(player_pos):
	# Get chunks around player
	var chunk_pos = world_pos_to_chunk(player_pos)
	var newly_loaded = load_chunks_around(player_pos, render_distance)
	
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
	
	# Create objects for this chunk if needed
	# For now, let our automated systems handle this
	pass

func find_player():
	# Find player in scene
	var players = get_tree().get_nodes_in_group("player_controller")
	if players.size() > 0:
		return players[0]
	
	return null

func find_tilemap_references(world):
	"""Try to find references to the tilemaps through the world"""
	# Try to get tilemap references from world
	floor_tilemap = world.get_node_or_null("VisualTileMap/FloorTileMap")
	wall_tilemap = world.get_node_or_null("VisualTileMap/WallTileMap")
	objects_tilemap = world.get_node_or_null("VisualTileMap/ObjectsTileMap")

func is_tile_occupied(tile_coords: Vector2i) -> bool:
	"""Check if a tile is occupied by any game tiles"""
	# First check with world's is_valid_tile function if available
	var world = get_parent()
	if world and world.has_method("is_valid_tile"):
		if world.is_valid_tile(tile_coords, 0):  # Using z_level 0
			return true
	
	# Direct check with tilemaps
	if floor_tilemap and floor_tilemap.get_cell_source_id(0, tile_coords) != -1:
		return true
		
	if wall_tilemap and wall_tilemap.get_cell_source_id(0, tile_coords) != -1:
		return true
		
	if objects_tilemap and objects_tilemap.get_cell_source_id(0, tile_coords) != -1:
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

func world_pos_to_chunk(world_pos: Vector2) -> Vector2i:
	var tile_x = int(world_pos.x / tile_size)
	var tile_y = int(world_pos.y / tile_size)
	
	var chunk_x = int(floor(tile_x / float(chunk_size)))
	var chunk_y = int(floor(tile_y / float(chunk_size)))
	
	return Vector2i(chunk_x, chunk_y)

func chunk_to_world_pos(chunk_pos: Vector2i) -> Vector2:
	return Vector2(chunk_pos.x * chunk_size * tile_size, chunk_pos.y * chunk_size * tile_size)
