extends Node2D
class_name World

# === CONSTANTS ===
const TILE_SIZE = 32  # Size in pixels of each tile
const SPATIAL_CELL_SIZE = 4  # Number of tiles per spatial cell for spatial hashing
const CHUNK_SIZE = 16  # Number of tiles per chunk

# === ENUMS ===
# Layer definitions for tiles
enum TileLayer {
	FLOOR,
	WALL,
	WIRE,
	PIPE,
	ATMOSPHERE
}

# === PROPERTIES ===
# World data structure - organized by z-level
var world_data = {}  # Dictionary of z-level -> Dictionary of Vector2i -> tile data

# Chunck data
var loaded_chunks = {}  # Track which chunks are loaded
var chunk_entities = {}  # Track entities in each chunk
var pending_chunks = []  # Chunks waiting to be processed

# Spatial partitioning
var spatial_hash = {}  # Optimization for spatial lookups

# Room detection
var rooms = {}  # Dictionary of room_id -> room data
var tile_to_room = {}  # Mapping of Vector3(x,y,z) -> room_id

# Z-level handling
var current_z_level = 0
var z_levels = 3  # Number of vertical levels

# Performance settings
var atmosphere_step_timer = 0.0
const ATMOSPHERE_UPDATE_INTERVAL = 0.5  # Update atmosphere every 0.5 seconds

# Player reference
var player = null

# === CORE SYSTEMS ===
# These are accessed frequently and benefit from direct access
@onready var spatial_manager = $SpatialManager
@onready var tile_occupancy_system = $TileOccupancySystem
@onready var atmosphere_system = $AtmosphereSystem

# === AUXILIARY SYSTEMS ===
# Visual systems
@onready var floor_tilemap = $VisualTileMap/FloorTileMap
@onready var wall_tilemap = $VisualTileMap/WallTileMap
@onready var zone_tilemap = $VisualTileMap/ZoneTileMap

# Gameplay systems
@onready var sensory_system = $SensorySystem
@onready var collision_resolver = $CollisionResolver
@onready var wall_slide_system = $WallSlideSystem
@onready var interaction_system = $InteractionSystem
@onready var context_interaction_system = $ContextInteractionSystem
@onready var audio_system_enhancer = $AudioSystemEnhancer

# Management systems
@onready var system_manager = $SystemManager
@onready var player_spawner = $"../MultiplayerSpawner"

# Threading system
var threading_system = null
var thread_manager = null

# === SIGNALS ===
signal tile_changed(tile_coords, z_level, old_data, new_data)
signal tile_destroyed(coords, z_level)
signal player_changed_position(position, z_level)
signal door_toggled(tile_coords, z_level, is_open)
signal object_interacted(tile_coords, z_level, object_type, action)

# Player reference
var local_player = null
var all_players = []  # Track all connected players

# Multiplayer synchronization
var is_multiplayer_active = false
var is_server = false
var sync_interval = 0.5  # How often to sync world state (in seconds)
var sync_timer = 0.0
var last_sync_time = 0.0

signal chunks_loaded(chunk_positions, z_level)

# ===================================
# === INITIALIZATION & LIFECYCLE ====
# ===================================

# Main initialization function
func _ready():
	print("World: Starting initialization sequence")
	
	# Determine if we're in multiplayer mode and if we're the server
	is_multiplayer_active = (multiplayer && multiplayer.multiplayer_peer != null)
	is_server = (is_multiplayer_active && (multiplayer.is_server() || multiplayer.get_unique_id() == 1))
	
	print("World: Multiplayer: ", is_multiplayer_active, " | Server: ", is_server)
	
	# 1. Initialize world data structure first
	initialize_world_data_structure()
	
	# 2. Set up system manager and core systems
	initialize_core_systems()
	
	# 3. Initialize the physical world and structures (now with tilemap registration)
	initialize_world()
	
	# 4. Initialize atmosphere with better tilemap support
	initialize_atmosphere()
	
	# 5. Initialize and configure player
	initialize_player()
	
	# 6. Connect signals between systems
	connect_systems()
	
	# 7. Register existing entities with tracking systems
	register_existing_entities()
	
	# 8. Final initialization steps
	finalize_initialization()
	
	# 9. Load initial chunks around spawn
	if is_server:
		var spawn_pos = Vector2(5 * TILE_SIZE, 5 * TILE_SIZE)  # Default
		if zone_tilemap:
			# Try to find center of zone
			var cells = zone_tilemap.get_used_cells(0)
			if cells.size() > 0:
				# Calculate average position
				var sum_x = 0
				var sum_y = 0
				for cell in cells:
					sum_x += cell.x
					sum_y += cell.y
				spawn_pos = Vector2(
					(sum_x / cells.size()) * TILE_SIZE,
					(sum_y / cells.size()) * TILE_SIZE
				)
		
		load_chunks_around(spawn_pos, current_z_level, 2)
		
	# Initialize chunk culling system
	initialize_chunk_culling()
	
	print("World: Initialization complete with ", count_tiles(), " total tiles")

# Update process function to handle chunk loading
func _process(delta):
	# Process atmosphere updates periodically
	atmosphere_step_timer += delta
	if atmosphere_step_timer >= ATMOSPHERE_UPDATE_INTERVAL:
		atmosphere_step_timer = 0.0
		if atmosphere_system:
			atmosphere_system.process_atmosphere_step()
	
	# Update sync timer
	if is_multiplayer_active:
		sync_timer += delta
		if sync_timer >= sync_interval:
			sync_timer = 0.0
			process_pending_chunks()
	
	# Process pending chunks
	if is_server and pending_chunks.size() > 0:
		process_pending_chunks()
	
	# Only check for player void status and chunk loading every few frames
	if Engine.get_frames_drawn() % 30 == 0:
		update_player_tracking()
		
		# Only server loads chunks
		if is_server:
			load_chunks_for_all_players()

# Update player tracking
func update_player_tracking():
	# Find all players in the scene 
	var new_players = get_tree().get_nodes_in_group("player_controller")
	
	# Update our tracking list
	all_players = new_players
	
	# Check void status for all players
	for player in all_players:
		if player:
			var grid_controller = player
			
			# Check void status
			check_entity_void_status(
				player, 
				grid_controller.current_tile_position, 
				grid_controller.current_z_level
			)
			
			# Find our local player
			if local_player == null and player.has_method("is_local_player") and player.is_local_player():
				local_player = player
				print("World: Found local player: ", player.name)

# Load chunks for all connected players
func load_chunks_for_all_players():
	if !is_server:
		return
		
	for player in all_players:
		if player.has_node("GridMovementController"):
			var grid_controller = player.get_node("GridMovementController")
			
			# Update chunks around this player
			var newly_loaded = load_chunks_around(
				player.position, 
				grid_controller.current_z_level, 
				2  # 2 chunk radius
			)
			
			# Notify clients of newly loaded chunks if needed
			if newly_loaded.size() > 0:
				network_sync_chunks.rpc(newly_loaded, grid_controller.current_z_level)

# Process pending chunk synchronization
func process_pending_chunks():
	if pending_chunks.size() == 0:
		return
		
	var chunks_to_process = pending_chunks.slice(0, min(5, pending_chunks.size()))
	
	for chunk_data in chunks_to_process:
		if chunk_data.has("chunk_pos") and chunk_data.has("z_level"):
			load_chunk(chunk_data.chunk_pos, chunk_data.z_level)
		
		# Remove from pending list
		pending_chunks.erase(chunk_data)
	
	print("World: Processed ", chunks_to_process.size(), " pending chunks, ", pending_chunks.size(), " remaining")

# Initialize the physical world with tilemap integration
func initialize_world():
	print("World: Initializing physical world")
	
	# Register existing TileMap tiles to world data
	var registered = register_tilemap_tiles()
	print("World: Registered " + str(registered) + " tiles from tilemaps")
	
	# Add z-level connections
	add_z_connections()
	
	# Initialize spatial hash
	update_spatial_hash()
	
	# Detect rooms for atmosphere simulation
	detect_rooms()
	
	# Standardize world data format
	convert_world_data_to_consistent_format()
	
	# Set up initial chunks around map center
	setup_initial_chunks()

# Set up initial loaded chunks
func setup_initial_chunks():
	# Find valid position (either player or center of zone)
	var spawn_pos = Vector2(5 * TILE_SIZE, 5 * TILE_SIZE)  # Default
	
	if zone_tilemap:
		# Try to find center of zone
		var cells = zone_tilemap.get_used_cells(0)
		if cells.size() > 0:
			# Calculate average position
			var sum_x = 0
			var sum_y = 0
			for cell in cells:
				sum_x += cell.x
				sum_y += cell.y
			spawn_pos = Vector2(
				(sum_x / cells.size()) * TILE_SIZE,
				(sum_y / cells.size()) * TILE_SIZE
			)
	
	# Only server loads initial chunks
	if is_server:
		print("World: Loading initial chunks around " + str(spawn_pos))
		load_chunks_around(spawn_pos, 0, 2)  # 2 chunk radius

func initialize_atmosphere():
	if not atmosphere_system:
		print("AtmosphereSystem: Cannot initialize - no atmosphere system found")
		return
	
	print("World: Initializing atmosphere system...")
	
	# Make sure we've registered tilemap tiles before initializing atmosphere
	ensure_tilemap_tiles_registered()
	
	# Reset active cells in atmosphere system
	atmosphere_system.active_cells = []
	atmosphere_system.active_count = 0
	
	# Standard atmosphere
	var standard_atmosphere = {
		atmosphere_system.GAS_TYPE_OXYGEN: atmosphere_system.ONE_ATMOSPHERE * atmosphere_system.O2STANDARD,
		atmosphere_system.GAS_TYPE_NITROGEN: atmosphere_system.ONE_ATMOSPHERE * atmosphere_system.N2STANDARD,
		"temperature": atmosphere_system.T20C
	}
	
	# Loop through all z-levels
	for z in range(z_levels):
		# Find tiles that need atmosphere
		var tiles_to_init = []
		
		if z in world_data:
			for coords in world_data[z]:
				var tile = world_data[z][coords]
				
				# Skip tiles with existing atmosphere
				if TileLayer.ATMOSPHERE in tile:
					# Add to active cells if it has atmosphere
					atmosphere_system.add_active_cell(Vector3(coords.x, coords.y, z))
					continue
				
				# Add to initialization list if it needs atmosphere
				if TileLayer.FLOOR in tile:
					tiles_to_init.append(coords)
		
		# For z_level 0, also check tilemaps directly
		if z == 0 and floor_tilemap:
			for cell in floor_tilemap.get_used_cells(0):
				# Skip if already processed
				if cell in tiles_to_init or (z in world_data and cell in world_data[z] and 
				   TileLayer.ATMOSPHERE in world_data[z][cell]):
					continue
				
				# Check if we have data for this tile
				if not (z in world_data and cell in world_data[z]):
					# Create tile data if it doesn't exist
					add_tile(Vector3(cell.x, cell.y, z))
				
				# Add to initialization list
				tiles_to_init.append(cell)
		
		# Initialize atmosphere for all collected tiles
		for coords in tiles_to_init:
			var tile = world_data[z][coords]
			
			# Create standard atmosphere data
			var atmosphere = standard_atmosphere.duplicate()
			
			# Adjust based on tile type
			if "tile_type" in tile:
				if tile.tile_type == "space":
					# Space has minimal atmosphere
					atmosphere = {
						atmosphere_system.GAS_TYPE_OXYGEN: 0.2,
						atmosphere_system.GAS_TYPE_NITROGEN: 0.5,
						"temperature": 3.0  # Near vacuum
					}
				elif tile.tile_type == "exterior":
					# Exterior has colder, thinner air
					atmosphere = {
						atmosphere_system.GAS_TYPE_OXYGEN: atmosphere_system.ONE_ATMOSPHERE * atmosphere_system.O2STANDARD * 0.7,
						atmosphere_system.GAS_TYPE_NITROGEN: atmosphere_system.ONE_ATMOSPHERE * atmosphere_system.N2STANDARD * 0.7,
						"temperature": 273.15  # 0°C
					}
			# Also check floor type
			elif TileLayer.FLOOR in tile and "type" in tile[TileLayer.FLOOR]:
				var floor_type = tile[TileLayer.FLOOR].type
				# Adjust atmosphere based on floor type
				if floor_type == "exterior":
					atmosphere = {
						atmosphere_system.GAS_TYPE_OXYGEN: atmosphere_system.ONE_ATMOSPHERE * atmosphere_system.O2STANDARD * 0.7,
						atmosphere_system.GAS_TYPE_NITROGEN: atmosphere_system.ONE_ATMOSPHERE * atmosphere_system.N2STANDARD * 0.7,
						"temperature": 273.15  # 0°C
					}
			
			# Add atmosphere data to tile
			tile[TileLayer.ATMOSPHERE] = atmosphere
			
			# Add to active cells
			atmosphere_system.add_active_cell(Vector3(coords.x, coords.y, z))
	
	# Initialize space around the station
	initialize_space_atmosphere()
	
	print("AtmosphereSystem: Initialized atmospheres for ", atmosphere_system.active_count, " cells")

# Make sure tilemap tiles are registered
func ensure_tilemap_tiles_registered():
	# Only register if we have very few tiles (indicating they haven't been registered yet)
	var tile_count = count_tiles()
	if tile_count < 10 and floor_tilemap:
		print("World: Very few tiles detected (" + str(tile_count) + ") - registering tilemap tiles")
		register_tilemap_tiles()

# Initialize atmosphere for space around the station
func initialize_space_atmosphere():
	print("World: Setting up space atmosphere...")
	
	# Find the station perimeter
	var perimeter_tiles = []
	
	# For z-level 0, use zone system if available
	if zone_tilemap != null:
		# Get all tiles that are inside zones (station tiles)
		var zone_tiles = zone_tilemap.get_used_cells(0)
		
		# Find perimeter tiles (tiles with at least one space neighbor)
		for zone_tile in zone_tiles:
			# Check if this tile is on the perimeter (has at least one neighbor that's space)
			var neighbors = [
				Vector2i(zone_tile.x + 1, zone_tile.y),
				Vector2i(zone_tile.x - 1, zone_tile.y),
				Vector2i(zone_tile.x, zone_tile.y + 1),
				Vector2i(zone_tile.x, zone_tile.y - 1)
			]
			
			for neighbor in neighbors:
				if zone_tilemap.get_cell_source_id(0, neighbor) == -1:
					perimeter_tiles.append(zone_tile)
					break
	else:
		# Fall back to finding edges by checking for walls
		for z in world_data.keys():
			if int(z) != 0:  # Only for z-level 0
				continue
				
			for coords in world_data[z].keys():
				# Check if this tile has a wall
				if is_wall_at(coords, z):
					# Check neighbors
					var neighbors = [
						Vector2i(coords.x + 1, coords.y),
						Vector2i(coords.x - 1, coords.y),
						Vector2i(coords.x, coords.y + 1),
						Vector2i(coords.x, coords.y - 1)
					]
					
					for neighbor in neighbors:
						if not is_valid_tile(neighbor, z):
							perimeter_tiles.append(coords)
							break
	
	# Only create space on the server in multiplayer
	if !is_multiplayer_active or is_server:
		# Create space atmosphere around the perimeter
		var space_count = 0
		for perimeter_tile in perimeter_tiles:
			# Create space in a 3-tile radius from each perimeter tile
			for x in range(-3, 4):
				for y in range(-3, 4):
					var space_tile = Vector2i(perimeter_tile.x + x, perimeter_tile.y + y)
					
					# Skip if inside a zone
					if zone_tilemap and zone_tilemap.get_cell_source_id(0, space_tile) != -1:
						continue
					
					# Skip if it has tilemap data
					if floor_tilemap and floor_tilemap.get_cell_source_id(0, space_tile) != -1:
						continue
						
					if wall_tilemap and wall_tilemap.get_cell_source_id(0, space_tile) != -1:
						continue
					
					# Create space tile with vacuum atmosphere
					var tile_data = get_tile_data(space_tile, 0)
					if not tile_data:
						tile_data = create_space_tile(space_tile, 0)
						space_count += 1
					elif not TileLayer.ATMOSPHERE in tile_data:
						# Add space atmosphere
						tile_data[TileLayer.ATMOSPHERE] = {
							atmosphere_system.GAS_TYPE_OXYGEN: 0.0,
							atmosphere_system.GAS_TYPE_NITROGEN: 0.0,
							"temperature": 2.7,  # Near vacuum
							"pressure": 0.0,
							"has_gravity": false
						}
						space_count += 1
					
					# Mark as space
					tile_data["is_space"] = true
					tile_data["has_gravity"] = false
					
					# Add to atmosphere system's active cells
					atmosphere_system.add_active_cell(Vector3(space_tile.x, space_tile.y, 0))
		
		print("World: Created " + str(space_count) + " space atmosphere tiles")

# Initialize the base world data structure
func initialize_world_data_structure():
	print("World: Initializing world data structure")
	
	# Create empty dictionaries for each z-level
	for z in range(z_levels):
		world_data[z] = {}
	
	print("World: Base world data structure created")
	print("World: TileLayer enum: ", TileLayer)

# Initialize core game systems
func initialize_core_systems():
	print("World: Initializing core systems")
	
	# Set up threading
	setup_threading()
	
	# Connect to spawner
	if player_spawner:
		player_spawner.spawned.connect(_on_player_spawned)
	
	# Initialize atmosphere system
	if atmosphere_system:
		atmosphere_system.connect("atmosphere_changed", Callable(self, "_on_atmosphere_changed"))
		atmosphere_system.connect("reaction_occurred", Callable(self, "_on_reaction_occurred"))
		atmosphere_system.connect("breach_detected", Callable(self, "_on_breach_detected"))
		atmosphere_system.connect("breach_sealed", Callable(self, "_on_breach_sealed"))
		
		# Set world reference
		atmosphere_system.world = self
		
		print("World: Atmosphere System initialized")

# Complete final initialization steps
func finalize_initialization():
	print("World: Performing final initialization steps")
	
	# Wait briefly for systems to initialize
	await get_tree().create_timer(0.1).timeout
	
	# Ensure all systems have proper world references
	if context_interaction_system:
		context_interaction_system.world = self

# === PLAYER MANAGEMENT ===

# Initialize or convert the player for local use
func initialize_player():
	print("World: Initializing player")
	
	# In multiplayer, we'll initialize via the spawn system instead
	if is_multiplayer_active:
		return
	
	# Find existing player node
	local_player = get_node_or_null("GridMovementController")
	
	if not local_player:
		# Create player
		local_player = Node2D.new()
		local_player.name = "Player"
		local_player.position = Vector2(TILE_SIZE * 5, TILE_SIZE * 5)  # Start position
		add_child(local_player)
		print("World: Created new Player node")
	
	# Check if player has GridMovementController
	var grid_controller = local_player.get_parent()
	
	if not grid_controller:
		# Create new grid controller
		grid_controller = GridMovementController.new()
		grid_controller.name = "GridMovementController"
		
		# Set default properties
		grid_controller.entity_id = "player"
		grid_controller.entity_name = "Player"
		grid_controller.entity_type = "character"
		grid_controller.current_z_level = 0
		
		# Add to player
		local_player.add_child(grid_controller)
		
		# Initialize position
		var tile_pos = get_tile_at(local_player.position)
		grid_controller.current_tile_position = tile_pos
		grid_controller.previous_tile_position = tile_pos
		grid_controller.target_tile_position = tile_pos
		
		print("World: Setup GridMovementController at position ", tile_pos)
	
	# Connect player signals
	connect_player_signals(local_player)
	
	# Register player with systems
	register_player_with_systems(local_player)
	
	print("World: Player initialization complete at position ", local_player.position)

# Connect player signals
func connect_player_signals(player_node):
	var grid_controller = player_node.get_node_or_null("GridMovementController")
	if grid_controller:
		# Connect tile change signal
		if grid_controller.has_signal("tile_changed") and !grid_controller.is_connected("tile_changed", Callable(self, "_on_player_tile_changed")):
			grid_controller.connect("tile_changed", Callable(self, "_on_player_tile_changed"))
		
		# Connect state change signal
		if grid_controller.has_signal("state_changed") and !grid_controller.is_connected("state_changed", Callable(self, "_on_player_state_changed")):
			grid_controller.connect("state_changed", Callable(self, "_on_player_state_changed"))
		
		# Connect interaction signals
		if grid_controller.has_signal("interaction_requested") and interaction_system:
			if !grid_controller.is_connected("interaction_requested", Callable(interaction_system, "handle_use")):
				grid_controller.connect("interaction_requested", Callable(interaction_system, "handle_use"))
		
		# Connect bumping signals
		if grid_controller.has_signal("bump") and collision_resolver:
			if !grid_controller.is_connected("bump", Callable(collision_resolver, "resolve_collision")):
				grid_controller.connect("bump", Callable(collision_resolver, "resolve_collision"))

# Register player with systems
func register_player_with_systems(player_node):
	# Grid controller reference
	var grid_controller = player_node.get_node_or_null("GridMovementController")
	if !grid_controller:
		return
	
	# Register with Sensory System
	if sensory_system:
		sensory_system.register_entity(grid_controller)
	
	# Register with Spatial Manager
	if spatial_manager:
		spatial_manager.register_entity(grid_controller)
	
	# Register with Tile Occupancy System
	if tile_occupancy_system:
		var tile_pos = grid_controller.current_tile_position
		var z_level = grid_controller.current_z_level
		tile_occupancy_system.register_entity_at_tile(grid_controller, tile_pos, z_level)
		print("World: Registered player with TileOccupancySystem at position ", tile_pos)
	
	print("World: Player registered with all systems")

# Called when a new player is spawned
func _on_player_spawned(node):
	print("World: Player spawned: ", node.name)
	
	# Check if this is a player controller
	if node.is_in_group("player_controller"):
		# Check if this is the local player
		var is_local_player = false
		if node.has_node("MultiplayerSynchronizer"):
			var sync = node.get_node("MultiplayerSynchronizer")
			is_local_player = sync.get_multiplayer_authority() == multiplayer.get_unique_id()
		
		# Configure player systems
		_configure_player_systems(node, is_local_player)
		
		# Register with interaction systems
		_register_player_with_systems(node, is_local_player)
		
		# Store local player reference if this is our player
		if is_local_player:
			local_player = node
			print("World: Set local player to: ", node.name)

# ==============================
# === TILE & WORLD FUNCTIONS ===
# ==============================

# Create a new tile with default data
func add_tile(coords: Vector3):
	# Create a new tile with comprehensive data
	var tile_data = {
		TileLayer.FLOOR: {
			"type": "floor",
			"collision": false,
			"health": 100,
			"material": "metal"
		},
		TileLayer.WALL: null,  # No wall by default
		TileLayer.WIRE: {
			"power": false,
			"network_id": -1
		},
		TileLayer.PIPE: {
			"content_type": "none",
			"pressure": 0,
			"flow_direction": Vector2.ZERO
		},
		TileLayer.ATMOSPHERE: {
			"oxygen": 21.0,
			"nitrogen": 78.0,
			"co2": 0.1,
			"temperature": 293.15,  # 20°C in Kelvin
			"pressure": 101.325,    # Standard pressure in kPa
		},
		"contents": [],  # Entities on this tile
		"tile_position": Vector2(coords.x * TILE_SIZE, coords.y * TILE_SIZE),
		"radiation": 0.0,
		"light_level": 5.0,
		"damages": [],  # List of damage states this tile has
		"has_gravity": true  # By default, all tiles have gravity
	}
	
	# Ensure we have a dictionary for this z-level
	if not coords.z in world_data:
		world_data[coords.z] = {}
	
	# Store the tile data at the coordinates
	var coords_2d = Vector2i(coords.x, coords.y)  # Use Vector2i consistently
	world_data[coords.z][coords_2d] = tile_data
	
	# Add to spatial hash
	add_to_spatial_hash(coords_2d, coords.z)
	
	return tile_data

func register_tilemap_tiles():
	print("World: Registering TileMap tiles in world data...")

	if !floor_tilemap or !wall_tilemap:
		print("World: Cannot register tiles - missing TileMaps")
		return 0

	var registered_count = 0

	# Register floor tiles
	for cell in floor_tilemap.get_used_cells(0):  # Layer 0
		var tile_coords = Vector2i(cell.x, cell.y)
		var z_level = 0  # Assume ground level for now

		# Get or create tile data
		var tile_data = get_tile_data(tile_coords, z_level)
		if !tile_data:
			tile_data = add_tile(Vector3(tile_coords.x, tile_coords.y, z_level))
			registered_count += 1

		# Determine floor type
		var floor_type = "floor"  # Default

		# Try terrain-based approach first
		var tile_data_obj = floor_tilemap.get_cell_tile_data(0, tile_coords)
		if tile_data_obj:
			var terrain_id = tile_data_obj.terrain
			var visualizer = get_node_or_null("VisualTileMap/TileMapVisualizer")
			if visualizer and "floor_terrain_mapping" in visualizer:
				for type_name in visualizer.floor_terrain_mapping.keys():
					var terrain_info = visualizer.floor_terrain_mapping[type_name]
					if terrain_info.terrain == terrain_id:
						floor_type = type_name
						break
		else:
			# Fall back to atlas coordinates
			var atlas_coords = floor_tilemap.get_cell_atlas_coords(0, tile_coords)
			if atlas_coords.y == 0:
				floor_type = "metal"
			elif atlas_coords.y == 1:
				floor_type = "carpet"

		tile_data[TileLayer.FLOOR] = {
			"type": floor_type,
			"collision": false,
			"health": 100,
			"material": floor_type
		}

	# Register wall tiles
	for cell in wall_tilemap.get_used_cells(0):  # Layer 0
		var tile_coords = Vector2i(cell.x, cell.y)
		var z_level = 0  # Ground level

		# Get or create tile data
		var tile_data = get_tile_data(tile_coords, z_level)
		if !tile_data:
			tile_data = add_tile(Vector3(tile_coords.x, tile_coords.y, z_level))
			registered_count += 1

		var wall_material = "metal"  # Default

		var tile_data_obj = wall_tilemap.get_cell_tile_data(0, tile_coords)
		if tile_data_obj:
			var terrain_id = tile_data_obj.terrain
			var visualizer = get_node_or_null("VisualTileMap/TileMapVisualizer")
			if visualizer and "wall_terrain_mapping" in visualizer:
				for type_name in visualizer.wall_terrain_mapping.keys():
					var terrain_info = visualizer.wall_terrain_mapping[type_name]
					if terrain_info.terrain == terrain_id:
						wall_material = type_name
						break
		else:
			var atlas_coords = wall_tilemap.get_cell_atlas_coords(0, tile_coords)
			if atlas_coords.y == 1:
				wall_material = "insulated"
			elif atlas_coords.y == 2:
				wall_material = "glass"

		tile_data[TileLayer.WALL] = {
			"type": "wall",
			"material": wall_material,
			"health": 100
		}

		tile_data["is_walkable"] = false

	# Register objects/doors if we have an objects tilemap
	var objects_tilemap = get_node_or_null("VisualTileMap/ObjectsTileMap")
	if objects_tilemap:
		for cell in objects_tilemap.get_used_cells(0):
			var tile_coords = Vector2i(cell.x, cell.y)
			var z_level = 0

			var tile_data = get_tile_data(tile_coords, z_level)
			if !tile_data:
				tile_data = add_tile(Vector3(tile_coords.x, tile_coords.y, z_level))
				registered_count += 1

			var atlas_coords = objects_tilemap.get_cell_atlas_coords(0, tile_coords)

			# Handle doors
			if atlas_coords == Vector2i(0, 1) or atlas_coords == Vector2i(1, 1):
				var is_closed = (atlas_coords.x == 0)

				tile_data["door"] = {
					"closed": is_closed,
					"locked": false,
					"material": "metal",
					"health": 100
				}

	print("World: Registered " + str(registered_count) + " TileMap tiles")
	return registered_count

func update_tile(coords, new_data, z_level = null):
	# Handle both Vector3 and Vector2+z_level
	var level
	var coords_2d
	
	if coords is Vector3:
		level = coords.z
		coords_2d = Vector2(coords.x, coords.y)
	else:
		level = current_z_level if z_level == null else z_level
		coords_2d = coords
	
	# Get existing tile data
	var old_data = get_tile_data(coords_2d, level)
	
	# Create new tile if it doesn't exist
	if old_data == null:
		old_data = add_tile(Vector3(coords_2d.x, coords_2d.y, level))
	
	# Only the server should directly update tiles in multiplayer
	if is_multiplayer_active and !is_server:
		# Clients request changes instead of making them directly
		network_request_tile_update.rpc_id(1, coords_2d.x, coords_2d.y, level, new_data)
		return old_data
	
	# Update tile data
	for key in new_data.keys():
		old_data[key] = new_data[key]
	
	# Emit signal for systems to respond
	emit_signal("tile_changed", coords_2d, level, old_data, new_data)
	
	# Notify clients if we're the server
	if is_multiplayer_active and is_server:
		network_update_tile.rpc(coords_2d.x, coords_2d.y, level, new_data)
	
	return old_data

# Toggle a door open/closed
func toggle_door(tile_coords, z_level):
	var tile = get_tile_data(tile_coords, z_level)
	if tile == null or not "door" in tile:
		return false
	
	# In multiplayer, only the server should directly change doors
	if is_multiplayer_active and !is_server:
		# Request door toggle from server
		network_request_door_toggle.rpc_id(1, tile_coords.x, tile_coords.y, z_level)
		return true
	
	# Toggle door state
	tile.door.closed = !tile.door.closed
	
	# Emit door toggled signal
	emit_signal("door_toggled", tile_coords, z_level, !tile.door.closed)
	
	# If door is part of a room, mark room for equalization
	var room_key = Vector3(tile_coords.x, tile_coords.y, z_level)
	if room_key in tile_to_room:
		var room_id = tile_to_room[room_key]
		if room_id in rooms:
			rooms[room_id].needs_equalization = true
	
	# Update atmosphere system
	if atmosphere_system:
		if tile.door.closed:
			# Recalculate rooms since a door closed
			detect_rooms()
		else:
			# Door opened, allow atmosphere to equalize
			var connected_rooms = []
			
			# Check adjacent tiles for different rooms
			for neighbor in get_adjacent_tiles(tile_coords, z_level):
				var neighbor_key = Vector3(neighbor.x, neighbor.y, z_level)
				if neighbor_key in tile_to_room:
					var room_id = tile_to_room[neighbor_key]
					if !room_id in connected_rooms:
						connected_rooms.append(room_id)
			
			# Mark connected rooms for equalization
			for room_id in connected_rooms:
				if room_id in rooms:
					rooms[room_id].needs_equalization = true
	
	# Notify clients about door state change
	if is_multiplayer_active and is_server:
		network_door_toggled.rpc(tile_coords.x, tile_coords.y, z_level, !tile.door.closed)
	
	return true

# Toggle a wall at a position
func toggle_wall_at(coords: Vector2i, z_level: int) -> bool:
	# In multiplayer, only the server can create/remove walls
	if is_multiplayer_active and !is_server:
		# Request wall toggle from server
		network_request_wall_toggle.rpc_id(1, coords.x, coords.y, z_level)
		return false
	
	var tile = get_tile_data(coords, z_level)
	if !tile:
		# Create a new tile if none exists
		tile = add_tile(Vector3(coords.x, coords.y, z_level))
	
	# Toggle wall state
	var wall_exists = TileLayer.WALL in tile and tile[TileLayer.WALL] != null
	
	if wall_exists:
		tile[TileLayer.WALL] = null  # Remove wall
	else:
		tile[TileLayer.WALL] = {  # Add wall
			"type": "wall",
			"material": "metal",
			"health": 100
		}
	
	# Update walkability
	tile["is_walkable"] = !(!wall_exists)
	
	# Notify systems of the change
	emit_signal("tile_changed", coords, z_level, tile, tile)
	
	# Sync with clients if we're the server
	if is_multiplayer_active and is_server:
		network_wall_toggled.rpc(coords.x, coords.y, z_level, !wall_exists)
	
	# Update wall tilemap if it exists
	if wall_tilemap and z_level == 0:
		if !wall_exists:
			# Add wall tile to tilemap
			wall_tilemap.set_cell(0, coords, 0, Vector2i(0, 0))
		else:
			# Remove wall tile from tilemap
			wall_tilemap.set_cell(0, coords, -1)
	
	return !wall_exists  # Return if wall now exists

# === CHUNK CULLING INTEGRATION ===
# Initialize chunk culling system
func initialize_chunk_culling():
	print("World: Initializing chunk culling system")
	
	# Create the chunk culling system
	var culling_system = ChunkCullingSystem.new()
	culling_system.name = "ChunkCullingSystem"
	add_child(culling_system)
	
	# Configure based on optimization settings
	var optimization_manager = get_node_or_null("/root/OptimizationManager")
	if optimization_manager:
		culling_system.occlusion_enabled = optimization_manager.settings.occlusion_culling
		
		# Connect signals
		optimization_manager.connect("settings_changed", Callable(self, "_on_optimization_settings_changed"))
	
	# Connect to our own signals
	connect("player_changed_position", Callable(self, "_on_player_position_changed_culling"))
	
	print("World: Chunk culling system initialized")
	return culling_system

# Called when a player changes position (for culling updates)
func _on_player_position_changed_culling(position, z_level):
	var culling_system = get_node_or_null("ChunkCullingSystem")
	if culling_system:
		# Update z-level tracking
		if z_level != culling_system.current_z_level:
			culling_system.set_z_level(z_level)

# Called when optimization settings change
func _on_optimization_settings_changed(setting_name, new_value):
	var culling_system = get_node_or_null("ChunkCullingSystem")
	if culling_system:
		match setting_name:
			"occlusion_culling":
				culling_system.set_occlusion_enabled(new_value)

func load_chunks_around(world_position: Vector2, z_level: int = current_z_level, radius: int = 2):
	var newly_loaded = []
	
	# Call the original implementation (already in your World class)
	# This loads the actual chunks
	var loaded_chunks = $YOUR_ORIGINAL_IMPLEMENTATION
	
	# Ensure culling system is updated with new chunks
	var culling_system = get_node_or_null("ChunkCullingSystem")
	if culling_system:
		# Force an update of chunk visibility
		culling_system.update_all_chunk_visibility()
	
	return loaded_chunks  # Return result from original function

# Load a specific chunk
func load_chunk(chunk_pos: Vector2i, z_level: int):
	print("World: Loading chunk at ", chunk_pos, " z-level ", z_level)
	
	# Calculate tile range for this chunk
	var start_x = chunk_pos.x * CHUNK_SIZE
	var start_y = chunk_pos.y * CHUNK_SIZE
	var end_x = start_x + CHUNK_SIZE - 1
	var end_y = start_y + CHUNK_SIZE - 1
	
	# Determine if this chunk is part of the space station
	var is_station_chunk = false
	if z_level == 0 and zone_tilemap:
		# Sample a few tiles to see if any are in the zone
		for x in range(start_x, end_x + 1, 4):
			for y in range(start_y, end_y + 1, 4):
				if zone_tilemap.get_cell_source_id(0, Vector2i(x, y)) != -1:
					is_station_chunk = true
					break
			if is_station_chunk:
				break
	
	# Register any tiles from tilemaps for z_level 0
	if z_level == 0:
		for x in range(start_x, end_x + 1):
			for y in range(start_y, end_y + 1):
				var tile_coords = Vector2i(x, y)
				
				# Check for tilemap tiles
				var has_floor = floor_tilemap and floor_tilemap.get_cell_source_id(0, tile_coords) != -1
				var has_wall = wall_tilemap and wall_tilemap.get_cell_source_id(0, tile_coords) != -1
				
				if has_floor or has_wall:
					# Ensure this tile exists in world_data
					if not get_tile_data(tile_coords, z_level):
						add_tile(Vector3(x, y, z_level))
				# Create space tiles around station or at chunk edges
				elif is_station_chunk == false and (x == start_x or x == end_x or y == start_y or y == end_y):
					# Add some space tiles (more at edges for transition)
					if randf() < 0.1:  # 10% chance at edges
						create_space_tile(tile_coords, z_level)
	
	# Create entities in this chunk if it's not a station chunk
	load_chunk_entities(chunk_pos, z_level, is_station_chunk)

# Create a space tile with minimal properties
func create_space_tile(coords: Vector2i, z_level: int):
	# Skip if tile already exists
	if get_tile_data(coords, z_level):
		return
	
	# Create a minimal space tile
	var tile_data = {
		TileLayer.ATMOSPHERE: {
			"oxygen": 0.0,
			"nitrogen": 0.0,
			"temperature": 2.7,  # Near vacuum temperature
			"pressure": 0.0,
			"has_gravity": false
		},
		"is_space": true,
		"has_gravity": false,
		"tile_position": Vector2(coords.x * TILE_SIZE, coords.y * TILE_SIZE)
	}
	
	# Add asteroid or space object randomly
	if randf() < 0.02:  # 2% chance
		tile_data["space_object"] = {
			"type": "asteroid",
			"size": randf_range(0.5, 2.0)
		}
	
	# Add to world data
	if not z_level in world_data:
		world_data[z_level] = {}
	
	world_data[z_level][coords] = tile_data
	
	# Add to spatial hash
	add_to_spatial_hash(coords, z_level)
	
	return tile_data

# Unload a specific chunk
func unload_chunk(chunk_pos: Vector2i, z_level: int):
	print("World: Unloading chunk at ", chunk_pos, " z-level ", z_level)
	
	# Calculate tile range
	var start_x = chunk_pos.x * CHUNK_SIZE
	var start_y = chunk_pos.y * CHUNK_SIZE
	var end_x = start_x + CHUNK_SIZE - 1
	var end_y = start_y + CHUNK_SIZE - 1
	
	# Unload entities first
	unload_chunk_entities(chunk_pos, z_level)
	
	# Only remove space tiles, keep station tiles intact
	if z_level == 0:
		for x in range(start_x, end_x + 1):
			for y in range(start_y, end_y + 1):
				var tile_coords = Vector2i(x, y)
				
				# Skip if this is a station tile (in zone or has tilemap data)
				if zone_tilemap and zone_tilemap.get_cell_source_id(0, tile_coords) != -1:
					continue
				
				if floor_tilemap and floor_tilemap.get_cell_source_id(0, tile_coords) != -1:
					continue
					
				if wall_tilemap and wall_tilemap.get_cell_source_id(0, tile_coords) != -1:
					continue
				
				# Remove from world data if it's a space tile
				if z_level in world_data and tile_coords in world_data[z_level]:
					var tile = world_data[z_level][tile_coords]
					if tile and "is_space" in tile and tile.is_space:
						world_data[z_level].erase(tile_coords)

# Load entities in a chunk
func load_chunk_entities(chunk_pos: Vector2i, z_level: int, is_station_chunk: bool = false):
	var chunk_key = str(chunk_pos.x) + "_" + str(chunk_pos.y) + "_" + str(z_level)
	
	# Skip if already loaded
	if chunk_key in chunk_entities:
		return
	
	chunk_entities[chunk_key] = []
	
	# Add space entities (asteroids, debris) to non-station chunks
	if not is_station_chunk and z_level == 0:
		# Add 0-3 space entities
		var entity_count = randi() % 4
		
		for i in range(entity_count):
			# Random position within chunk
			var x = chunk_pos.x * CHUNK_SIZE + randi() % CHUNK_SIZE
			var y = chunk_pos.y * CHUNK_SIZE + randi() % CHUNK_SIZE
			var tile_coords = Vector2i(x, y)
			
			# Skip if there's already something here
			if is_valid_tile(tile_coords, z_level):
				continue

# Convert world position to tile coordinates
func get_tile_at(world_position: Vector2, z_level = current_z_level) -> Vector2i:
	var tile_x = floor(world_position.x / TILE_SIZE)
	var tile_y = floor(world_position.y / TILE_SIZE)
	return Vector2i(tile_x, tile_y)

# Convert tile coordinates to world position (centered in tile)
func tile_to_world(tile_pos: Vector2) -> Vector2:
	return Vector2(
		(tile_pos.x * TILE_SIZE) + (TILE_SIZE / 2.0), 
		(tile_pos.y * TILE_SIZE) + (TILE_SIZE / 2.0)
	)

# Get tile data with robust error handling
func get_tile_data(coords, layer = null):
	# Handle both Vector3 and Vector2+z_level
	var z_level
	var coords_2d
	
	if coords is Vector3:
		z_level = int(coords.z)  # Always convert to integer
		coords_2d = Vector2i(coords.x, coords.y)
	else:
		z_level = int(current_z_level if layer == null else layer)  # Convert to integer
		coords_2d = Vector2i(coords.x, coords.y)
	
	# First try integer lookup (preferred after conversion)
	if z_level in world_data and coords_2d in world_data[z_level]:
		return world_data[z_level][coords_2d]
	
	# Fall back to float lookup if needed
	var float_z = float(z_level)
	if float_z in world_data and coords_2d in world_data[float_z]:
		return world_data[float_z][coords_2d]
	
	return null

# Check if a tile is valid
func is_valid_tile(coords, z_level = current_z_level) -> bool:
	# Convert coords to Vector2i if needed
	var tile_coords = coords
	if coords is Vector3:
		tile_coords = Vector2i(coords.x, coords.y)
	elif coords is Vector2:
		tile_coords = Vector2i(coords.x, coords.y)
	
	# Check with zone system first (for z_level 0)
	if z_level == 0 and zone_tilemap != null:
		if zone_tilemap.get_cell_source_id(0, tile_coords) != -1:
			return true
	
	# Direct tilemap check for z_level 0
	if z_level == 0:
		# Check floor tilemap
		if floor_tilemap and floor_tilemap.get_cell_source_id(0, tile_coords) != -1:
			return true
		
		# Check wall tilemap
		if wall_tilemap and wall_tilemap.get_cell_source_id(0, tile_coords) != -1:
			return true
			
		# Check objects tilemap
		var objects_tilemap = get_node_or_null("VisualTileMap/ObjectsTileMap")
		if objects_tilemap and objects_tilemap.get_cell_source_id(0, tile_coords) != -1:
			return true
	
	# Fall back to the world_data dictionary method
	if z_level in world_data and tile_coords in world_data[z_level]:
		return true
	
	return false

# Check if a tile has a wall
func is_wall_at(tile_coords: Vector2i, z_level: int = current_z_level) -> bool:
	# First check the actual wall tilemap - most reliable source
	if wall_tilemap != null and z_level == 0:
		# Get the cell at this position
		var cell_source_id = wall_tilemap.get_cell_source_id(0, tile_coords)
		if cell_source_id != -1:
			return true
	
	# Fallback to world_data if needed
	var tile_data = get_tile_data(tile_coords, z_level)
	if tile_data is Dictionary and TileLayer.WALL in tile_data and tile_data[TileLayer.WALL] != null:
		return true
		
	return false

# Get adjacent tiles (orthogonal neighbors)
func get_adjacent_tiles(coords, z_level):
	# Return coordinates of adjacent tiles (north, south, east, west)
	var adjacents = [
		Vector2(coords.x + 1, coords.y),
		Vector2(coords.x - 1, coords.y),
		Vector2(coords.x, coords.y + 1),
		Vector2(coords.x, coords.y - 1)
	]
	
	# Filter out invalid tiles
	var valid_adjacents = []
	for adj in adjacents:
		if get_tile_data(adj, z_level) != null:
			valid_adjacents.append(adj)
	
	return valid_adjacents

# Add a coordinate to the spatial hash
func add_to_spatial_hash(coords: Vector2, z_level = current_z_level):
	var cell_x = floor(coords.x / SPATIAL_CELL_SIZE)
	var cell_y = floor(coords.y / SPATIAL_CELL_SIZE)
	var cell_key = Vector3(cell_x, cell_y, z_level)
	
	if not cell_key in spatial_hash:
		spatial_hash[cell_key] = []
		
	if not coords in spatial_hash[cell_key]:
		spatial_hash[cell_key].append(coords)

# Update the entire spatial hash
func update_spatial_hash():
	# Clear and rebuild the spatial hash
	spatial_hash.clear()
	
	for z in world_data.keys():
		for coords in world_data[z].keys():
			add_to_spatial_hash(coords, z)

# Setup threading system for performance
func setup_threading():
	print("World: Initializing threading system")
	
	# Create thread manager
	thread_manager = ThreadManager.new()
	thread_manager.name = "ThreadManager"
	add_child(thread_manager)
	
	# Create threading system
	threading_system = WorldThreadingSystem.new(self)
	threading_system.name = "WorldThreadingSystem"
	add_child(threading_system)
	
	# Set world reference in thread manager
	thread_manager.set_world_reference(self)
	
	print("World: Threading system initialized")

# Connect signals between systems
func connect_systems():
	# Connect TileOccupancySystem to InteractionSystem
	if tile_occupancy_system and interaction_system:
		if tile_occupancy_system.has_signal("entities_collided") and !tile_occupancy_system.is_connected("entities_collided", Callable(interaction_system, "handle_collision")):
			tile_occupancy_system.connect("entities_collided", Callable(interaction_system, "handle_bump"))
	
	# Connect InteractionSystem to SensorySystem for sound propagation
	if interaction_system and sensory_system:
		if interaction_system.has_signal("interaction_completed") and !interaction_system.is_connected("interaction_completed", Callable(self, "_on_interaction_completed")):
			interaction_system.connect("interaction_completed", Callable(self, "_on_interaction_completed"))
	
	# Connect AtmosphereSystem to TileOccupancySystem for entity effects
	if atmosphere_system and tile_occupancy_system:
		if atmosphere_system.has_signal("atmosphere_changed") and !atmosphere_system.is_connected("atmosphere_changed", Callable(self, "_on_atmosphere_for_entities")):
			atmosphere_system.connect("atmosphere_changed", Callable(self, "_on_atmosphere_for_entities"))

# Register existing entities with tile occupancy system
func register_existing_entities():
	if !tile_occupancy_system:
		return
	
	print("World: Registering existing entities with TileOccupancySystem")
	
	# Find all entities in the world and register them
	var entities = []
	
	# Get entities from spatial manager if available
	if spatial_manager and ("all_entities") in spatial_manager:
		entities = spatial_manager.all_entities
	else:
		# Fallback to finding entities manually
		for z in world_data.keys():
			for tile_coords in world_data[z].keys():
				var tile_data = world_data[z][tile_coords]
				if "contents" in tile_data and tile_data.contents.size() > 0:
					for entity in tile_data.contents:
						if !entity in entities:
							entities.append(entity)
	
	print("World: Found ", entities.size(), " entities to register")
	
	# Register each entity with tile occupancy
	for entity in entities:
		var position = entity.position if "position" in entity else Vector2.ZERO
		var tile_pos = get_tile_at(position)
		
		var z_level = 0
		if "current_z_level" in entity:
			z_level = entity.current_z_level
		elif entity is GridMovementController:
			z_level = entity.current_z_level
		
		# Register with tile occupancy
		tile_occupancy_system.register_entity_at_tile(entity, tile_pos, z_level)
		
		print("World: Registered entity with tile occupancy: ", entity.name if "name" in entity else "Unknown")

# When all systems are initialized and ready
func _on_systems_initialized():
	print("World: All systems are initialized and ready")
	
	# Now that systems are ready, register existing entities with tile occupancy
	register_existing_entities()

# === RPC METHODS FOR MULTIPLAYER ===

# Synchronize chunk loading between server and clients
@rpc("authority", "call_remote", "reliable")
func network_sync_chunks(chunk_positions, z_level):
	if is_server:
		return
		
	print("World: Received chunk sync for ", chunk_positions.size(), " chunks")
	
	# Add chunks to pending list
	for chunk_pos in chunk_positions:
		var chunk_key = str(chunk_pos.x) + "_" + str(chunk_pos.y) + "_" + str(z_level)
		
		# Skip if already loaded
		if chunk_key in loaded_chunks:
			continue
			
		# Add to pending list
		pending_chunks.append({
			"chunk_pos": chunk_pos,
			"z_level": z_level
		})
		
		loaded_chunks[chunk_key] = true

# Server update of tile data to clients
@rpc("authority", "call_remote", "reliable")
func network_update_tile(x, y, z_level, new_data):
	if is_server:
		return
		
	# Get existing tile data
	var coords_2d = Vector2i(x, y)
	var old_data = get_tile_data(coords_2d, z_level)
	
	# Create tile if it doesn't exist
	if old_data == null:
		old_data = add_tile(Vector3(x, y, z_level))
	
	# Update tile data
	for key in new_data.keys():
		old_data[key] = new_data[key]
	
	# Emit signal for systems to respond
	emit_signal("tile_changed", coords_2d, z_level, old_data, new_data)

# Client request for tile update (sent to server)
@rpc("any_peer", "call_local", "reliable")
func network_request_tile_update(x, y, z_level, new_data):
	if !is_server:
		return
		
	# Validate data before applying
	var coords_2d = Vector2i(x, y)
	var old_data = get_tile_data(coords_2d, z_level)
	
	# Create tile if it doesn't exist
	if old_data == null:
		old_data = add_tile(Vector3(x, y, z_level))
	
	# Update tile data
	for key in new_data.keys():
		old_data[key] = new_data[key]
	
	# Emit signal for systems to respond
	emit_signal("tile_changed", coords_2d, z_level, old_data, new_data)
	
	# Notify all clients
	network_update_tile.rpc(x, y, z_level, new_data)

# Notify clients about door state change
@rpc("authority", "call_remote", "reliable")
func network_door_toggled(x, y, z_level, is_open):
	if is_server:
		return
		
	var tile_coords = Vector2i(x, y)
	var tile = get_tile_data(tile_coords, z_level)
	
	# Ensure door exists
	if tile == null or not "door" in tile:
		return
	
	# Update door state
	tile.door.closed = !is_open
	
	# Emit signal
	emit_signal("door_toggled", tile_coords, z_level, is_open)

# Client request for door toggle
@rpc("any_peer", "call_local", "reliable")
func network_request_door_toggle(x, y, z_level):
	if !is_server:
		return
		
	var tile_coords = Vector2i(x, y)
	toggle_door(tile_coords, z_level)

# Notify clients about wall toggle
@rpc("authority", "call_remote", "reliable")
func network_wall_toggled(x, y, z_level, wall_exists):
	if is_server:
		return
		
	var tile_coords = Vector2i(x, y)
	var tile = get_tile_data(tile_coords, z_level)
	
	if !tile:
		# Create a new tile if none exists
		tile = add_tile(Vector3(x, y, z_level))
	
	# Set wall state
	if wall_exists:
		tile[TileLayer.WALL] = {
			"type": "wall",
			"material": "metal",
			"health": 100
		}
		tile["is_walkable"] = false
	else:
		tile[TileLayer.WALL] = null
		tile["is_walkable"] = true
	
	# Emit signal
	emit_signal("tile_changed", tile_coords, z_level, tile, tile)
	
	# Update tilemap
	if wall_tilemap and z_level == 0:
		if wall_exists:
			wall_tilemap.set_cell(0, tile_coords, 0, Vector2i(0, 0))
		else:
			wall_tilemap.set_cell(0, tile_coords, -1)

# Client request for wall toggle
@rpc("any_peer", "call_local", "reliable")
func network_request_wall_toggle(x, y, z_level):
	if !is_server:
		return
		
	var tile_coords = Vector2i(x, y)
	toggle_wall_at(tile_coords, z_level)

func modify_tilemap_visualizer():
	# Get the TileMapVisualizer
	var visualizer = get_node_or_null("VisualTileMap/TileMapVisualizer")
	if visualizer:
		# Disable preserve_existing_tiles to ensure proper visualization
		visualizer.preserve_existing_tiles = false
		
		# Force refresh visualization
		if visualizer.has_method("refresh_visualization"):
			visualizer.refresh_visualization()
			print("World: Refreshed TileMapVisualizer")

# Configure player systems based on locality
func _configure_player_systems(player, is_local):
	# Enable/disable camera
	var camera = player.get_node_or_null("Camera2D")
	if camera:
		camera.enabled = is_local
	
	# Enable/disable UI
	var ui = player.get_node_or_null("PlayerUI")
	if ui:
		ui.visible = is_local
	
	# Configure input processing
	var input_controller = player.get_node_or_null("InputController")
	if input_controller:
		input_controller.set_process_input(is_local)
		input_controller.set_process_unhandled_input(is_local)
	
	# Configure EntityIntegration
	if player and player.has_method("set_local_player"):
		player.set_local_player(is_local)

# Register player with all world interaction systems
func _register_player_with_systems(player, is_local):
	# Find ClickHandler in the world
	var click_handlers = get_tree().get_nodes_in_group("click_system")
	for handler in click_handlers:
		# If this is our local player, set the reference in ClickHandler
		if is_local and handler.has_method("set_player_reference"):
			handler.set_player_reference(player)
			print("World: Set player reference in ClickHandler for: ", player.name)
	
	# Find interaction systems
	var interaction_systems = get_tree().get_nodes_in_group("interaction_system")
	for system in interaction_systems:
		if system.has_method("register_player"):
			system.register_player(player, is_local)
			print("World: Registered player with InteractionSystem: ", player.name)
	
	# Find tile occupancy system and register player
	if tile_occupancy_system and tile_occupancy_system.has_method("register_entity"):
		tile_occupancy_system.register_entity(player)
		print("World: Registered player with TileOccupancySystem: ", player.name)

# Used to check if a tile should be treated as space/void
func is_space(tile_coords: Vector2i, z_level: int = current_z_level) -> bool:
	# If we have a zone system, anything outside a zone is space
	if z_level == 0 and zone_tilemap != null:
		if zone_tilemap.get_cell_source_id(0, tile_coords) == -1:
			return true
	
	# Check tilemaps directly for z_level 0
	if z_level == 0:
		if floor_tilemap and floor_tilemap.get_cell_source_id(0, tile_coords) != -1:
			return false
		if wall_tilemap and wall_tilemap.get_cell_source_id(0, tile_coords) != -1:
			return false
		
		var objects_tilemap = get_node_or_null("VisualTileMap/ObjectsTileMap")
		if objects_tilemap and objects_tilemap.get_cell_source_id(0, tile_coords) != -1:
			return false
	
	# Check for explicit space flag in tile data
	var tile_data = get_tile_data(tile_coords, z_level)
	if tile_data and "is_space" in tile_data:
		return tile_data.is_space
	
	# Otherwise check if the tile doesn't exist in world_data
	return !z_level in world_data or !tile_coords in world_data[z_level]

# Check if a position is in a valid zone (considered "inside")
func is_in_zone(tile_coords: Vector2i, z_level: int = current_z_level) -> bool:
	# For now, only z_level 0 has zones
	if z_level != 0 or zone_tilemap == null:
		return false
		
	return zone_tilemap.get_cell_source_id(0, tile_coords) != -1

# Check if tile is blocked (any obstacle, not just walls)
func is_tile_blocked(coords, z_level = current_z_level):
	# Convert coords to Vector2i if needed
	var tile_coords = coords
	if coords is Vector3:
		tile_coords = Vector2i(coords.x, coords.y)
	elif coords is Vector2:
		tile_coords = Vector2i(coords.x, coords.y)
	
	# Check for walls first (most common blocker)
	if is_wall_at(tile_coords, z_level):
		return true
	
	# Check for closed door
	var tile = get_tile_data(tile_coords, z_level)
	if tile != null and "door" in tile and "closed" in tile.door and tile.door.closed:
		return true
	
	# Use tile occupancy system if available
	if tile_occupancy_system:
		return tile_occupancy_system.has_dense_entity_at(tile_coords, z_level)
	
	# Fallback: Check for blocking entities
	if tile != null and "contents" in tile:
		for entity in tile.contents:
			if "blocks_movement" in entity and entity.blocks_movement:
				return true
				
	return false

# Check if there's an airtight barrier between tiles
func is_airtight_barrier(tile1_coords, tile2_coords, z_level):
	# Get tile data
	var tile1 = get_tile_data(tile1_coords, z_level)
	var tile2 = get_tile_data(tile2_coords, z_level)
	
	if tile1 == null or tile2 == null:
		return true  # Consider out of bounds as airtight
	
	# Check for walls
	if TileLayer.WALL in tile1:
		return true  # Wall blocks air
	
	if TileLayer.WALL in tile2:
		return true  # Wall blocks air
	
	# Check for doors
	if "door" in tile1 and "closed" in tile1.door and tile1.door.closed:
		return true  # Closed door blocks air
	
	if "door" in tile2 and "closed" in tile2.door and tile2.door.closed:
		return true  # Closed door blocks air
	
	return false

# Get entities at a specific tile
func get_entities_at_tile(tile_coords, z_level):
	# Use tile occupancy system if available
	if tile_occupancy_system:
		return tile_occupancy_system.get_entities_at(tile_coords, z_level)
	
	# Fallback to manual check
	var tile = get_tile_data(tile_coords, z_level)
	if tile and "contents" in tile:
		return tile.contents
	
	return []

# ==============================
# === SPATIAL HASH FUNCTIONS ===
# ==============================

# Get tiles in a radius around a center point
func get_nearby_tiles(center: Vector2, radius: float, z_level = current_z_level) -> Array:
	var start_cell_x = floor((center.x - radius) / SPATIAL_CELL_SIZE)
	var start_cell_y = floor((center.y - radius) / SPATIAL_CELL_SIZE)
	var end_cell_x = floor((center.x + radius) / SPATIAL_CELL_SIZE)
	var end_cell_y = floor((center.y + radius) / SPATIAL_CELL_SIZE)
	
	var result = []
	
	for cell_x in range(start_cell_x, end_cell_x + 1):
		for cell_y in range(start_cell_y, end_cell_y + 1):
			var cell_key = Vector3(cell_x, cell_y, z_level)
			
			if cell_key in spatial_hash:
				for tile_coords in spatial_hash[cell_key]:
					# Calculate actual distance
					var tile_world_pos = Vector2(tile_coords.x * TILE_SIZE, tile_coords.y * TILE_SIZE)
					var distance = center.distance_to(tile_world_pos)
					
					if distance <= radius:
						result.append(tile_coords)
	
	return result

# Get entities in a radius
func get_entities_in_radius(center: Vector2, radius: float, z_level = current_z_level) -> Array:
	# Use the spatial manager for entity queries
	if spatial_manager:
		return spatial_manager.get_entities_near(center, radius, z_level)
	
	# Use tile occupancy system if available
	if tile_occupancy_system:
		var entities = []
		var tile_radius = ceil(radius / TILE_SIZE)
		
		# Get all tiles in radius
		for x in range(-tile_radius, tile_radius + 1):
			for y in range(-tile_radius, tile_radius + 1):
				var tile_center = get_tile_at(center)
				var check_tile = Vector2i(tile_center.x + x, tile_center.y + y)
				
				# Get entities at this tile
				var tile_entities = tile_occupancy_system.get_entities_at(check_tile, z_level)
				for entity in tile_entities:
					# Only include entities within actual radius
					if "position" in entity:
						var distance = center.distance_to(entity.position)
						if distance <= radius and !entity in entities:
							entities.append(entity)
		
		return entities
	
	# Fallback method
	var nearby_tiles = get_nearby_tiles(center, radius, z_level)
	var entities = []
	
	for tile_coords in nearby_tiles:
		var tile = get_tile_data(tile_coords, z_level)
		if tile != null and "contents" in tile:
			entities.append_array(tile.contents)
	
	# Remove duplicates
	var unique_entities = []
	for entity in entities:
		if not entity in unique_entities:
			unique_entities.append(entity)
	
	return unique_entities

# ==============================
# === ATMOSPHERE & ROOMS ===
# ==============================

# Get tile atmosphere data for the atmosphere system
func get_tile_atmosphere_data(coords, z_level):
	return get_tile_data(coords, z_level)

# Get tile hazards
func get_tile_hazards(coords, z_level = current_z_level):
	# Return an array of hazards on a specific tile
	var hazards = []
	var tile = get_tile_data(coords, z_level)
	
	if tile == null:
		return hazards
	
	# Check for slippery floors
	if TileLayer.FLOOR in tile:
		var floor_data = tile.get(TileLayer.FLOOR) if TileLayer.FLOOR in tile else null

		if "friction" in floor_data and floor_data.friction < 0.5:  # Very slippery
			hazards.append({
				"type": "slippery",
				"slip_chance": clamp(1.0 - floor_data.friction * 2, 0.0, 0.9),
				"slip_time": clamp(2.0 - floor_data.friction * 2, 0.5, 2.0),
				"slip_direction": Vector2.ZERO  # Random direction handled by entity
			})
	
	# Check for radiation
	if "radiation" in tile and tile.radiation > 0.1:
		hazards.append({
			"type": "radiation",
			"radiation_level": tile.radiation
		})
	
	# Check for extreme temperatures
	if TileLayer.ATMOSPHERE in tile:
		var atmo = tile.get(TileLayer.ATMOSPHERE) if TileLayer.ATMOSPHERE in tile else null
		if "temperature" in atmo:
			# Temperature-based hazards
			if atmo.temperature > 360:  # Over ~90°C
				hazards.append({
					"type": "damage",
					"damage_amount": (atmo.temperature - 360) * 0.1,
					"damage_type": "heat"
				})
			elif atmo.temperature < 260:  # Under ~-10°C
				hazards.append({
					"type": "damage",
					"damage_amount": (260 - atmo.temperature) * 0.1,
					"damage_type": "cold"
				})
	
	# Check for vacuum
	if TileLayer.ATMOSPHERE in tile:
		var atmo = tile.get(TileLayer.ATMOSPHERE) if TileLayer.ATMOSPHERE in tile else null
		if "pressure" in atmo and atmo.pressure < 10:  # Very low pressure
			hazards.append({
				"type": "vacuum",
				"severity": clamp(1.0 - (atmo.pressure / 10.0), 0.0, 1.0)
			})
			
	# Check for fire
	if "on_fire" in tile and tile.on_fire:
		hazards.append({
			"type": "damage",
			"damage_amount": 5.0,  # Fire damage per second
			"damage_type": "fire"
		})
	
	return hazards

# Detect rooms for atmosphere simulation
func detect_rooms():
	rooms.clear()
	tile_to_room.clear()
	
	# For each z-level
	for z in world_data.keys():
		var visited = {}
		var room_id = 0
		
		# Flood fill to detect rooms
		for coords in world_data[z].keys():
			if coords in visited:
				continue
				
			var room_tiles = flood_fill_room(coords, z, visited)
			if room_tiles.size() > 0:
				rooms[room_id] = {
					"tiles": room_tiles,
					"z_level": z,
					"volume": room_tiles.size(),
					"atmosphere": calculate_room_atmosphere(room_tiles, z),
					"connections": detect_room_connections(room_tiles, z),
					"needs_equalization": false
				}
				
				# Map tiles to room
				for tile in room_tiles:
					tile_to_room[Vector3(tile.x, tile.y, z)] = room_id
					
				room_id += 1

# Flood fill to find connected rooms
func flood_fill_room(start_coords, z_level, visited):
	var room_tiles = []
	var to_visit = [start_coords]
	
	while to_visit.size() > 0:
		var current = to_visit.pop_front()
		
		if current in visited:
			continue
			
		visited[current] = true
		room_tiles.append(current)
		
		# Check neighbors
		for neighbor in get_adjacent_tiles(current, z_level):
			if neighbor in visited:
				continue
				
			# Skip walls and solid barriers
			if is_airtight_barrier(current, neighbor, z_level):
				continue
				
			to_visit.append(neighbor)
	
	return room_tiles

# Calculate average atmosphere for a room
func calculate_room_atmosphere(tiles, z_level):
	# Calculate average atmosphere for all tiles in a room
	var total_gases = {}
	var total_energy = 0.0
	var tile_count = 0
	
	for tile_coords in tiles:
		var tile = get_tile_data(tile_coords, z_level)
		if tile == null or not TileLayer.ATMOSPHERE in tile:
			continue
			
		var atmo = tile.get(TileLayer.ATMOSPHERE) if TileLayer.ATMOSPHERE in tile else null
		
		# Sum all gases
		for gas_key in atmo.keys():
			if gas_key != "temperature" and gas_key != "pressure" and typeof(atmo[gas_key]) == TYPE_FLOAT:
				if not gas_key in total_gases:
					total_gases[gas_key] = 0.0
				total_gases[gas_key] += atmo[gas_key]
		
		# Sum energy (temperature)
		if "temperature" in atmo:
			total_energy += atmo.temperature
			
		tile_count += 1
	
	# Calculate averages
	var result = {}
	
	if tile_count > 0:
		# Gas averages
		for gas_key in total_gases.keys():
			result[gas_key] = total_gases[gas_key] / tile_count
			
		# Temperature average
		if total_energy > 0:
			result["temperature"] = total_energy / tile_count
			
		# Calculate pressure
		var total_pressure = 0.0
		for gas_key in result.keys():
			if gas_key != "temperature" and gas_key != "pressure":
				total_pressure += result[gas_key]
		
		result["pressure"] = total_pressure
	else:
		# Default atmosphere if no valid tiles
		result = {
			"oxygen": 0.0,
			"nitrogen": 0.0,
			"co2": 0.0,
			"temperature": 293.15,
			"pressure": 0.0
		}
	
	return result

# Detect connections between rooms
func detect_room_connections(room_tiles, z_level):
	var connections = []

	for tile_coords in room_tiles:
		var tile = get_tile_data(tile_coords, z_level)
		if tile == null:
			continue  # Skip null tiles

		# Check for doors or other connectors
		if "door" in tile:
			var door = tile.door
			if door != null and "closed" in door:
				connections.append({
					"type": "door",
					"tile": tile_coords,
					"state": "closed" if door.closed else "open"
				})

		# Check for vents (pipes containing air)
		if TileLayer.PIPE in tile:
			var pipe = tile.get(TileLayer.PIPE)
			if pipe != null and "content_type" in pipe and pipe.content_type == "air":
				var network_id = pipe.network_id if "network_id" in pipe else null
				connections.append({
					"type": "vent",
					"tile": tile_coords,
					"network_id": network_id
				})

		# Check for z-level connections
		if "z_connection" in tile:
			var z_conn = tile.z_connection
			if z_conn != null and "type" in z_conn and "target" in z_conn and "direction" in z_conn:
				connections.append({
					"type": z_conn.type,
					"tile": tile_coords,
					"target": z_conn.target,
					"direction": z_conn.direction
				})

	return connections

# Add z-level connections
func add_z_connections():
	# Add stairs/elevators between floors
	var connection_points = [
		Vector2(10, 10),
		Vector2(30, 30),
		Vector2(20, 5)
	]
	
	for point in connection_points:
		for z in range(z_levels - 1):
			var lower_tile = get_tile_data(Vector3(point.x, point.y, z))
			var upper_tile = get_tile_data(Vector3(point.x, point.y, z + 1))
			
			if lower_tile != null and upper_tile != null and lower_tile is Dictionary and upper_tile is Dictionary:
				lower_tile["z_connection"] = {
					"type": "stairs" if z == 0 else "elevator",
					"direction": "up",
					"target": Vector3(point.x, point.y, z + 1)
				}
				
				upper_tile["z_connection"] = {
					"type": "stairs" if z == 0 else "elevator",
					"direction": "down",
					"target": Vector3(point.x, point.y, z)
				}

# ==============================
# === DOOR & OBJECT FUNCTIONS ===
# ==============================

# Get door at tile position
func get_door_at(tile_coords, z_level):
	var tile = get_tile_data(tile_coords, z_level)
	if tile and "door" in tile:
		return tile.door
	return null

# Create a breach in the world (for explosive decompression)
func trigger_explosive_decompression(breach_coords, z_level, radius = 5, force = 15.0):
	# Convert to world position
	var breach_position = tile_to_world(breach_coords)
	
	# Mark tile as breached
	var breach_tile = get_tile_data(breach_coords, z_level)
	if breach_tile is Dictionary:
		breach_tile["breach"] = true
		breach_tile["exposed_to_space"] = true
		
		# Update atmosphere data
		if TileLayer.ATMOSPHERE in breach_tile:
			breach_tile[TileLayer.ATMOSPHERE]["pressure"] = 0.0
			breach_tile[TileLayer.ATMOSPHERE]["has_gravity"] = false
	
	# Find all entities within radius
	var affected_tiles = get_nearby_tiles(breach_position, radius * TILE_SIZE, z_level)
	var affected_entities = []
	
	# Find all entities in affected area
	for tile_coords in affected_tiles:
		# Set gravity to false in tiles around breach
		set_tile_gravity(tile_coords, z_level, false)
		
		# Get entities at this tile
		if tile_occupancy_system:
			var entities = tile_occupancy_system.get_entities_at(tile_coords, z_level)
			for entity in entities:
				if !entity in affected_entities:
					affected_entities.append(entity)
	
	# Apply explosive force to entities
	for entity in affected_entities:
		var zero_g_controller = entity.get_node_or_null("ZeroGController")
		if zero_g_controller:
			# Apply explosion impulse to entity
			zero_g_controller.apply_explosion_impulse(breach_position, force, radius * TILE_SIZE)
	
	# Play breach sound
	if sensory_system:
		sensory_system.emit_sound(breach_position, z_level, "breach", 1.0, null)
	
	# Notify atmosphere system of breach
	if atmosphere_system:
		atmosphere_system.emit_signal("breach_detected", Vector3(breach_coords.x, breach_coords.y, z_level))
	
	# Return a status
	return affected_entities.size()

# Set gravity state for a tile
func set_tile_gravity(tile_coords, z_level, has_gravity):
	var tile = get_tile_data(tile_coords, z_level)
	if !tile:
		# Create tile if it doesn't exist
		tile = add_tile(Vector3(tile_coords.x, tile_coords.y, z_level))
	
	# Get previous gravity state
	var old_has_gravity = true
	if "has_gravity" in tile:
		old_has_gravity = tile.has_gravity
	
	# No change needed
	if old_has_gravity == has_gravity:
		return false
	
	# Update gravity state
	tile["has_gravity"] = has_gravity
	
	# Update atmosphere data
	if TileLayer.ATMOSPHERE in tile:
		tile[TileLayer.ATMOSPHERE]["has_gravity"] = has_gravity
	
	# Emit tile changed signal
	emit_signal("tile_changed", tile_coords, z_level, tile, tile)
	
	# Check for entities in this tile that need updating
	if tile_occupancy_system:
		var entities = tile_occupancy_system.get_entities_at(tile_coords, z_level)
		for entity in entities:
			# Update ZeroGController if available
			var zero_g_controller = entity.get_node_or_null("ZeroGController")
			if zero_g_controller:
				if has_gravity:
					zero_g_controller.deactivate_zero_g()
				else:
					zero_g_controller.activate_zero_g()
	
	return true

# Create a zero-g zone
func create_zero_g_zone(start_coords, end_coords, z_level, has_gravity = false):
	var modified_tiles = 0
	
	# Ensure start is top-left, end is bottom-right
	var start_x = min(start_coords.x, end_coords.x)
	var start_y = min(start_coords.y, end_coords.y)
	var end_x = max(start_coords.x, end_coords.x)
	var end_y = max(start_coords.y, end_coords.y)
	
	# Set gravity state for all tiles in the zone
	for x in range(start_x, end_x + 1):
		for y in range(start_y, end_y + 1):
			var tile_coords = Vector2i(x, y)
			if set_tile_gravity(tile_coords, z_level, has_gravity):
				modified_tiles += 1
	
	# Recalculate rooms if any tiles were modified
	if modified_tiles > 0:
		detect_rooms()
	
	return modified_tiles

# Check if an entity is in void space
func check_entity_void_status(entity, tile_pos, z_level):
	# Skip if entity is null
	if !entity:
		return
		
	# Check if we're in space (void)
	var in_space = is_space(tile_pos, z_level)
	
	# Get zero-g controller if available
	var zero_g_controller = entity.get_node_or_null("ZeroGController")
	if zero_g_controller:
		if in_space and !zero_g_controller.is_in_zero_g():
			# Entity entered void - activate zero-g
			zero_g_controller.activate_zero_g()
			print("World: Entity entered void - activating zero-g")
		elif !in_space and zero_g_controller.is_in_zero_g():
			# Entity left void - deactivate zero-g
			zero_g_controller.deactivate_zero_g()
			print("World: Entity left void - deactivating zero-g")

# Get floor type at a tile position
func get_floor_type(tile_coords, z_level):
	var tile = get_tile_data(tile_coords, z_level)
	if tile is Dictionary:
		var floor = tile.get(TileLayer.FLOOR, null)
		if floor != null and "type" in floor:
			return floor.type
	return "floor"  # Default

# ==============================
# === UTILITY FUNCTIONS ===
# ==============================

# Convert the world data to a consistent format
func convert_world_data_to_consistent_format():
	print("World: Converting world data to consistent integer format...")
	var new_world_data = {}
	
	# Convert all float keys to integers for consistency
	for z in world_data.keys():
		var new_z = int(z)  # Convert to integer
		new_world_data[new_z] = {}
		
		# Copy all tiles
		for coords in world_data[z].keys():
			new_world_data[new_z][coords] = world_data[z][coords]
	
	# Replace with standardized data
	world_data = new_world_data
	print("World: World data converted to integer z-levels")

# Find a valid position in the world
func find_valid_position(z_level, max_tries = 100):
	# Try to find a valid position inside a zone
	if zone_tilemap != null and z_level == 0:
		# Get all cells from the zone tilemap
		var zone_cells = zone_tilemap.get_used_cells(0)
		if zone_cells.size() > 0:
			# Return a random zone cell
			return zone_cells[randi() % zone_cells.size()]
	
	# Default return position
	return Vector2i(5, 5)

# Count the total number of tiles
func count_tiles() -> int:
	var count = 0
	for z in world_data.keys():
		count += world_data[z].size()
	return count

# Ensure z level is normalized to integer
func normalize_z_level(z):
	return int(z)  # Always convert to integer for consistency

# Debug player position
func debug_player_position():
	if !player:
		return
		
	var grid_controller = player.get_node_or_null("GridMovementController")
	if !grid_controller:
		return
		
	var pos = grid_controller.current_tile_position
	var z = int(grid_controller.current_z_level)
	
	print("\n=== PLAYER POSITION DEBUG ===")
	print("Position: ", pos, " Z-level: ", z)
	print("Tile exists: ", get_tile_data(pos, z) != null)
	
	var tile = get_tile_data(pos, z)
	if tile:
		print("Tile has wall: ", TileLayer.WALL in tile)
	
	print("=== DEBUG END ===\n")

# Print world data summary
func print_world_data_summary():
	print("\n=== WORLD DATA SUMMARY ===")
	for z in world_data.keys():
		var tile_count = world_data[z].size()
		print("Z-level ", z, ": ", tile_count, " tiles")
		
		# Check key types
		if tile_count > 0:
			var first_key = world_data[z].keys()[0]
			print("  First key type: ", typeof(first_key), " value: ", first_key)
			
			# Check if we can look up using Vector2i
			var as_vector2i = Vector2i(first_key.x, first_key.y)
			print("  Can lookup with Vector2i: ", as_vector2i in world_data[z])
	print("===========================\n")

# ==============================
# === SIGNAL HANDLERS ===
# ==============================

# Player tile change handler
func _on_player_tile_changed(old_tile, new_tile):
	# Update display for new tile position
	if player:
		var grid_controller = player.get_node_or_null("GridMovementController")
		if grid_controller:
			var z_level = grid_controller.current_z_level
			emit_signal("player_changed_position", player.position, z_level)
			
			# Check for void/space transition
			check_entity_void_status(player, new_tile, z_level)
			
			# Play footstep sound
			if sensory_system:
				var floor_type = get_floor_type(new_tile, z_level)
				sensory_system.emit_footstep_sound(grid_controller)
			
			# Check for hazards at new position
			var hazards = get_tile_hazards(new_tile, z_level)
			for hazard in hazards:
				# Apply hazard effects
				if hazard.type == "slippery":
					if randf() < hazard.slip_chance:
						grid_controller.slip(hazard.slip_time)

# Player state change handler
func _on_player_state_changed(old_state, new_state):
	# Handle state changes for effects, sounds, etc.
	if player:
		var grid_controller = player.get_node_or_null("GridMovementController")
		if !grid_controller:
			return
			
		# The state values for GridMovementController
		# 0: IDLE, 1: MOVING, 2: RUNNING, 3: STUNNED, 4: CRAWLING, 5: FLOATING
		match new_state:
			0:  # IDLE
				# Stop any movement sounds or effects
				pass
				
			1:  # MOVING
				# Normal walking
				pass
				
			2:  # RUNNING
				# If running, emit louder footstep
				if sensory_system:
					sensory_system.emit_sound(player.position, grid_controller.current_z_level, "footstep", 0.7, grid_controller)
			
			5:  # FLOATING
				# First time entering zero-g
				if old_state != 5 and sensory_system:
					sensory_system.emit_sound(player.position, grid_controller.current_z_level, "thud", 0.3, grid_controller)
				
			3:  # STUNNED
				# Effects for being stunned
				if sensory_system:
					sensory_system.emit_sound(player.position, grid_controller.current_z_level, "thud", 0.5, grid_controller)
					
			4:  # CRAWLING
				# Crawling makes less noise but is slow
				if sensory_system:
					sensory_system.emit_sound(player.position, grid_controller.current_z_level, "footstep", 0.2, grid_controller)
					
		# Check if state changed to/from FLOATING for atmosphere effects
		if (old_state == 5 and new_state != 5):
			# Returning to gravity
			if sensory_system:
				sensory_system.emit_sound(player.position, grid_controller.current_z_level, "thud", 0.4, grid_controller)
				
		# Update tile hazard effects based on new state
		# For example, slippery floors are more dangerous when running
		var current_tile_hazards = get_tile_hazards(grid_controller.current_tile_position, grid_controller.current_z_level)
		for hazard in current_tile_hazards:
			# Apply hazard effects based on movement state
			if hazard.type == "slippery" and new_state == 2:  # RUNNING
				# Higher chance to slip when running on slippery surface
				if randf() < hazard.slip_chance * 1.5:
					grid_controller.slip(hazard.slip_time * 1.2)
					if sensory_system:
						sensory_system.emit_sound(player.position, grid_controller.current_z_level, "thud", 0.6, grid_controller)

# Interaction completed handler
func _on_interaction_completed(source, target, mode, result):
	# Play appropriate sounds based on interaction
	if sensory_system:
		var sound_type = "interact"
		var volume = 0.5
		
		# Determine sound based on interaction mode
		match mode:
			0:  # EXAMINE
				sound_type = "examine"
				volume = 0.2
			1:  # USE
				sound_type = "interact"
				volume = 0.4
			2:  # MANIPULATE
				sound_type = "manipulate"
				volume = 0.5
			3:  # TOOL
				sound_type = "tool"
				volume = 0.6
			4:  # ATTACK
				sound_type = "attack"
				volume = 0.7
			5:  # SPEAK
				sound_type = "speak"
				volume = 0.5
			
		# Play sound
		if target and "position" in target:
			sensory_system.emit_sound(target.position, current_z_level, sound_type, volume, source)
		elif source and "position" in source:
			sensory_system.emit_sound(source.position, current_z_level, sound_type, volume, source)

# Atmosphere changed handler
func _on_atmosphere_changed(coordinates, old_data, new_data):
	# Update tile data with new atmosphere values
	var tile_coords = Vector2(coordinates.x, coordinates.y)
	var z_level = coordinates.z
	
	var tile = get_tile_data(tile_coords, z_level)
	if tile is Dictionary:
		if tile != null:
			# Update the atmosphere data
			tile[TileLayer.ATMOSPHERE] = new_data
		
		# Update room data if this tile is part of a room
		var room_key = Vector3(tile_coords.x, tile_coords.y, z_level)
		if room_key in tile_to_room:
			var room_id = tile_to_room[room_key]
			if room_id in rooms:
				rooms[room_id].needs_equalization = true
		
		# Check for effects on entities in this tile
		if tile_occupancy_system:
			var entities = tile_occupancy_system.get_entities_at(tile_coords, z_level)
			for entity in entities:
				if entity != null and entity.has_method("on_atmosphere_changed"):
					entity.on_atmosphere_changed(new_data)
				
				# Check for gravity changes
				if "has_gravity" in new_data:
					var zero_g_controller = entity.get_node_or_null("ZeroGController")
					if zero_g_controller:
						if new_data.has_gravity:
							zero_g_controller.deactivate_zero_g()
						else:
							zero_g_controller.activate_zero_g()

# Handle atmosphere changes for entities
func _on_atmosphere_for_entities(coordinates, old_data, new_data):
	var tile_coords = Vector2(coordinates.x, coordinates.y)
	var z_level = coordinates.z
	
	# Get all entities at this tile
	var entities = []
	
	if tile_occupancy_system:
		entities = tile_occupancy_system.get_entities_at(tile_coords, z_level)
	else:
		var tile = get_tile_data(tile_coords, z_level)
		if tile and "contents" in tile:
			entities = tile.contents
	
	# Update entities with atmosphere changes
	for entity in entities:
		# Check for gravity changes
		if "has_gravity" in new_data and "has_gravity" in old_data:
			if new_data.has_gravity != old_data.has_gravity:
				if entity is GridMovementController:
					entity.set_gravity(new_data.has_gravity)
		
		# Check for pressure/temperature damage
		if "pressure" in new_data and new_data.pressure < 10:
			# Vacuum damage
			if entity.has_method("take_damage"):
				entity.take_damage(0.5, "vacuum")
		
		if "temperature" in new_data:
			if new_data.temperature > 360:
				# Heat damage
				if entity.has_method("take_damage"):
					entity.take_damage((new_data.temperature - 360) * 0.05, "heat")
			elif new_data.temperature < 260:
				# Cold damage
				if entity.has_method("take_damage"):
					entity.take_damage((260 - new_data.temperature) * 0.05, "cold")

# Reaction occurred handler
func _on_reaction_occurred(coordinates, reaction_name, intensity):
	# Handle visual/gameplay effects of reactions
	var tile_coords = Vector2(coordinates.x, coordinates.y)
	var z_level = coordinates.z
	
	match reaction_name:
		"plasma_combustion":
			# Create fire effects for plasma combustion
			var tile = get_tile_data(tile_coords, z_level)
			if tile is Dictionary:
				if tile != null:
					tile["on_fire"] = true
					
					# Create light from fire
					tile["light_source"] = intensity * 5.0
					tile["light_color"] = Color(1.0, 0.7, 0.2, 0.7)  # Orange fire
				
				# Make fire sound through sensory system
				if sensory_system:
					var pos = Vector2(tile_coords.x * TILE_SIZE, tile_coords.y * TILE_SIZE)
					sensory_system.emit_sound(pos, z_level, "machinery", intensity, null)

# Breach detected handler
func _on_breach_detected(coordinates):
	# Handle a breach (depressurization, alarm, etc)
	var tile_coords = Vector2(coordinates.x, coordinates.y)
	var z_level = coordinates.z
	
	var tile = get_tile_data(tile_coords, z_level)
	if tile != null:
		if tile is Dictionary:
			# Set breach flag directly in tile data
			tile["breach"] = true
			tile["exposed_to_space"] = true
		
		# Make breach sound through sensory system
		if sensory_system:
			var pos = Vector2(tile_coords.x * TILE_SIZE, tile_coords.y * TILE_SIZE)
			sensory_system.emit_sound(pos, z_level, "alarm", 1.0, null)

# Breach sealed handler
func _on_breach_sealed(coordinates):
	# Handle a breach being sealed
	var tile_coords = Vector2(coordinates.x, coordinates.y)
	var z_level = coordinates.z
	
	var tile = get_tile_data(tile_coords, z_level)
	if tile != null:
		if tile is Dictionary:
			tile["breach"] = false
			tile["exposed_to_space"] = false

# Unload entities in a chunk
func unload_chunk_entities(chunk_pos: Vector2i, z_level: int):
	var chunk_key = str(chunk_pos.x) + "_" + str(chunk_pos.y) + "_" + str(z_level)
	
	# Skip if not loaded
	if not chunk_key in chunk_entities:
		return
	
	# Unregister all entities
	for entity in chunk_entities[chunk_key]:
		if entity and is_instance_valid(entity):
			# Remove from tracking systems
			if spatial_manager:
				spatial_manager.unregister_entity(entity)
			
			if tile_occupancy_system:
				var entity_tile = Vector2i(
					floor(entity.position.x / TILE_SIZE),
					floor(entity.position.y / TILE_SIZE)
				)
				tile_occupancy_system.remove_entity(entity, entity_tile, z_level)
			
			# Free entity unless it's persistent
			if "persistent" not in entity or not entity.persistent:
				entity.queue_free()
	
	# Clear chunk entity list
	chunk_entities.erase(chunk_key)

func get_tile_terrain_type(tilemap: TileMap, tile_coords: Vector2i, terrain_mapping: Dictionary) -> String:
	# Default type
	var default_type = "floor" if tilemap == floor_tilemap else "metal"
	
	# Get cell data
	var source_id = tilemap.get_cell_source_id(0, tile_coords)
	if source_id == -1:
		return default_type
		
	# Get TileData
	var tile_data = tilemap.get_cell_tile_data(0, tile_coords)
	if not tile_data:
		return default_type
	
	# Get terrain set and terrain from TileData
	var terrain_set = tile_data.get_terrain_set()
	var terrain = tile_data.get_terrain()
	
	# If not using terrain, try to determine from atlas coords
	if terrain_set < 0 or terrain < 0:
		var atlas_coords = tilemap.get_cell_atlas_coords(0, tile_coords)
		# Simple mapping based on atlas coordinates
		# Adjust this based on your specific tileset layout
		if atlas_coords.y == 0:
			return "metal"
		elif atlas_coords.y == 1:
			return "carpet" if tilemap == floor_tilemap else "insulated"
		elif atlas_coords.y == 2:
			return "wood" if tilemap == floor_tilemap else "glass"
		else:
			return default_type
	
	# Try to match terrain set and terrain to a type in mapping
	for type_name in terrain_mapping.keys():
		var terrain_info = terrain_mapping[type_name]
		if terrain_info.terrain_set == terrain_set and terrain_info.terrain == terrain:
			return type_name
	
	# Fall back to using just the terrain set
	for type_name in terrain_mapping.keys():
		var terrain_info = terrain_mapping[type_name]
		if terrain_info.terrain_set == terrain_set:
			return type_name
	
	return default_type

# Check if a position has a closed door
func is_closed_door_at(tile_coords: Vector2i, z_level: int = current_z_level) -> bool:
	# Get tile data
	var tile = get_tile_data(tile_coords, z_level)
	if not tile:
		return false
	
	# Check for door data
	if "door" in tile and "closed" in tile.door:
		return tile.door.closed
	
	# Also check for door entity
	var entity = get_door_entity_at(tile_coords, z_level)
	if entity and "is_open" in entity:
		return !entity.is_open
	
	return false

# Get a door entity at a specific tile
func get_door_entity_at(tile_coords: Vector2i, z_level: int = current_z_level) -> Object:
	if tile_occupancy_system:
		var entities = tile_occupancy_system.get_entities_at(tile_coords, z_level)
		for entity in entities:
			if entity.is_in_group("doors") or ("entity_type" in entity and entity.entity_type == "door"):
				return entity
	
	return null

# Set door state in tile data
func set_door_state(tile_coords: Vector2i, z_level: int, is_closed: bool):
	var tile = get_tile_data(tile_coords, z_level)
	if not tile:
		# Create tile if it doesn't exist
		tile = add_tile(Vector3(tile_coords.x, tile_coords.y, z_level))
	
	# Ensure door data exists
	if not "door" in tile:
		tile["door"] = {}
	
	# Set closed state
	tile.door["closed"] = is_closed
	
	# Update tile data
	update_tile(tile_coords, tile, z_level)

# Emit signal when door state changes
func emit_door_state_changed(tile_coords: Vector2i, z_level: int, is_open: bool):
	emit_signal("door_toggled", tile_coords, z_level, is_open)
