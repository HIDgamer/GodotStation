extends Node2D
class_name World

const TILE_SIZE = 32
const SPATIAL_CELL_SIZE = 4
const CHUNK_SIZE = 16
const ATMOSPHERE_UPDATE_INTERVAL = 0.5

enum TileLayer {
	FLOOR,
	WALL,
	WIRE,
	PIPE,
	ATMOSPHERE
}

var world_data = {}
var loaded_chunks = {}
var chunk_entities = {}
var spatial_hash = {}
var rooms = {}
var tile_to_room = {}

var current_z_level = 0
var z_levels = 3
var atmosphere_step_timer = 0.0

var player = null
var local_player = null
var all_players = []

var is_multiplayer_active = false
var is_server = false
var sync_interval = 0.5
var sync_timer = 0.0

@onready var spatial_manager = $SpatialManager
@onready var tile_occupancy_system = $TileOccupancySystem
@onready var atmosphere_system = $AtmosphereSystem
@onready var floor_tilemap = $VisualTileMap/FloorTileMap
@onready var wall_tilemap = $VisualTileMap/WallTileMap
@onready var zone_tilemap = $VisualTileMap/ZoneTileMap
@onready var sensory_system = $SensorySystem
@onready var collision_resolver = $CollisionResolver
@onready var wall_slide_system = $WallSlideSystem
@onready var interaction_system = $InteractionSystem
@onready var context_interaction_system = $ContextInteractionSystem
@onready var audio_system_enhancer = $AudioSystemEnhancer
@onready var system_manager = $SystemManager
@onready var player_spawner = $"../MultiplayerSpawner"

var thread_manager = null

signal tile_changed(tile_coords, z_level, old_data, new_data)
signal tile_destroyed(coords, z_level)
signal player_changed_position(position, z_level)
signal door_toggled(tile_coords, z_level, is_open)
signal object_interacted(tile_coords, z_level, object_type, action)
signal chunks_loaded(chunk_positions, z_level)

func _ready():
	setup_multiplayer()
	initialize_world_structure()
	setup_systems()
	load_world_data()
	initialize_atmosphere()
	setup_player()
	finalize_initialization()

func _process(delta):
	update_atmosphere(delta)
	update_multiplayer(delta)
	update_chunk_loading()
	
	if Engine.get_frames_drawn() % 30 == 0:
		update_players()

func setup_multiplayer():
	is_multiplayer_active = (multiplayer && multiplayer.multiplayer_peer != null)
	is_server = (is_multiplayer_active && (multiplayer.is_server() || multiplayer.get_unique_id() == 1))

func initialize_world_structure():
	for z in range(z_levels):
		world_data[z] = {}

func setup_systems():
	setup_threading()
	connect_player_spawner()
	connect_atmosphere_system()

func setup_threading():
	thread_manager = ThreadManager.new()
	thread_manager.name = "ThreadManager"
	add_child(thread_manager)
	thread_manager.set_world_reference(self)

func connect_player_spawner():
	if player_spawner:
		player_spawner.spawned.connect(_on_player_spawned)

func connect_atmosphere_system():
	if atmosphere_system:
		atmosphere_system.connect("atmosphere_changed", Callable(self, "_on_atmosphere_changed"))
		atmosphere_system.connect("reaction_occurred", Callable(self, "_on_reaction_occurred"))
		atmosphere_system.connect("breach_detected", Callable(self, "_on_breach_detected"))
		atmosphere_system.connect("breach_sealed", Callable(self, "_on_breach_sealed"))
		atmosphere_system.world = self

func load_world_data():
	var registered = register_tilemap_tiles()
	add_z_connections()
	update_spatial_hash()
	detect_rooms()
	setup_initial_chunks()

func initialize_atmosphere():
	if not atmosphere_system:
		return
	
	atmosphere_system.active_cells = []
	atmosphere_system.active_count = 0
	
	var standard_atmosphere = create_standard_atmosphere()
	
	for z in range(z_levels):
		initialize_z_level_atmosphere(z, standard_atmosphere)
	
	initialize_space_tiles()

func create_standard_atmosphere() -> Dictionary:
	return {
		atmosphere_system.GAS_TYPE_OXYGEN: atmosphere_system.ONE_ATMOSPHERE * atmosphere_system.O2STANDARD,
		atmosphere_system.GAS_TYPE_NITROGEN: atmosphere_system.ONE_ATMOSPHERE * atmosphere_system.N2STANDARD,
		"temperature": atmosphere_system.T20C
	}

func initialize_z_level_atmosphere(z: int, standard_atmosphere: Dictionary):
	var tiles_to_init = []
	
	if z in world_data:
		for coords in world_data[z]:
			var tile = world_data[z][coords]
			
			if TileLayer.ATMOSPHERE in tile:
				atmosphere_system.add_active_cell(Vector3(coords.x, coords.y, z))
				continue
			
			if TileLayer.FLOOR in tile:
				tiles_to_init.append(coords)
	
	if z == 0 and floor_tilemap:
		add_tilemap_atmosphere_tiles(tiles_to_init, z)
	
	for coords in tiles_to_init:
		add_atmosphere_to_tile(coords, z, standard_atmosphere)

func add_tilemap_atmosphere_tiles(tiles_to_init: Array, z: int):
	for cell in floor_tilemap.get_used_cells(0):
		if cell in tiles_to_init:
			continue
		
		if not (z in world_data and cell in world_data[z]):
			add_tile(Vector3(cell.x, cell.y, z))
		
		if not (z in world_data and cell in world_data[z] and TileLayer.ATMOSPHERE in world_data[z][cell]):
			tiles_to_init.append(cell)

func add_atmosphere_to_tile(coords: Vector2i, z: int, standard_atmosphere: Dictionary):
	if not world_data.has(z):
		push_error("Z-level %d not found in world_data" % z)
		return
	
	var tilemap = world_data[z]
	if not tilemap.has(coords):
		push_error("Tile at %s not found in Z-level %d" % [coords, z])
		return
	
	var tile = tilemap[coords]
	
	if tile is Dictionary:
		var atmosphere = determine_tile_atmosphere(tile, standard_atmosphere)
		tile[TileLayer.ATMOSPHERE] = atmosphere
		atmosphere_system.add_active_cell(Vector3(coords.x, coords.y, z))
	else:
		push_error("Tile at %s is not a Dictionary: %s" % [coords, typeof(tile)])


func determine_tile_atmosphere(tile: Dictionary, standard_atmosphere: Dictionary) -> Dictionary:
	if "tile_type" in tile:
		match tile.tile_type:
			"space":
				return create_space_atmosphere()
			"exterior":
				return create_exterior_atmosphere(standard_atmosphere)
	
	if TileLayer.FLOOR in tile and "type" in tile[TileLayer.FLOOR]:
		if tile[TileLayer.FLOOR].type == "exterior":
			return create_exterior_atmosphere(standard_atmosphere)
	
	return standard_atmosphere.duplicate()

func create_space_atmosphere() -> Dictionary:
	return {
		atmosphere_system.GAS_TYPE_OXYGEN: 0.2,
		atmosphere_system.GAS_TYPE_NITROGEN: 0.5,
		"temperature": 3.0
	}

func create_exterior_atmosphere(base_atmosphere: Dictionary) -> Dictionary:
	var exterior = base_atmosphere.duplicate()
	for gas_type in exterior:
		if gas_type != "temperature":
			exterior[gas_type] *= 0.7
	exterior["temperature"] = 273.15
	return exterior

func setup_player():
	if is_multiplayer_active:
		return
	
	create_local_player()

func create_local_player():
	local_player = get_node_or_null("GridMovementController")
	
	if not local_player:
		local_player = create_player_node()
		add_child(local_player)
	
	setup_player_controller()
	connect_player_signals(local_player)
	register_player_with_systems(local_player)

func create_player_node() -> Node2D:
	var player_node = Node2D.new()
	player_node.name = "Player"
	player_node.position = Vector2(TILE_SIZE * 5, TILE_SIZE * 5)
	return player_node

func setup_player_controller():
	var grid_controller = local_player.get_parent()
	
	if not grid_controller:
		grid_controller = create_grid_controller()
		local_player.add_child(grid_controller)

func create_grid_controller() -> GridMovementController:
	var controller = GridMovementController.new()
	controller.name = "GridMovementController"
	controller.entity_id = "player"
	controller.entity_name = "Player"
	controller.entity_type = "character"
	controller.current_z_level = 0
	
	var tile_pos = get_tile_at(local_player.position)
	controller.current_tile_position = tile_pos
	controller.previous_tile_position = tile_pos
	controller.target_tile_position = tile_pos
	
	return controller

func finalize_initialization():
	await get_tree().create_timer(0.1).timeout
	
	if context_interaction_system:
		context_interaction_system.world = self
	
	initialize_chunk_culling()

func update_atmosphere(delta: float):
	atmosphere_step_timer += delta
	if atmosphere_step_timer >= ATMOSPHERE_UPDATE_INTERVAL:
		atmosphere_step_timer = 0.0
		if atmosphere_system:
			atmosphere_system.process_atmosphere_step()

func update_multiplayer(delta: float):
	if not is_multiplayer_active:
		return
	
	sync_timer += delta
	if sync_timer >= sync_interval:
		sync_timer = 0.0

func update_chunk_loading():
	if is_server:
		load_chunks_for_all_players()

func update_players():
	track_all_players()
	update_player_states()

func track_all_players():
	var new_players = get_tree().get_nodes_in_group("player_controller")
	all_players = new_players
	
	for player in all_players:
		if player:
			update_player_tracking(player)

func update_player_tracking(player: Node):
	var grid_controller = player
	
	check_entity_void_status(
		player, 
		grid_controller.movement_component.current_tile_position, 
		grid_controller.current_z_level
	)
	
	if local_player == null and player.has_method("is_local_player") and player.is_local_player():
		local_player = player

func update_player_states():
	pass

func load_chunks_for_all_players():
	if not is_server:
		return
	
	for player in all_players:
		if player.has_node("GridMovementController"):
			var grid_controller = player.get_node("GridMovementController")
			
			var newly_loaded = load_chunks_around(
				player.position, 
				grid_controller.current_z_level, 
				2
			)
			
			if newly_loaded.size() > 0:
				network_sync_chunks.rpc(newly_loaded, grid_controller.current_z_level)

func add_tile(coords: Vector3) -> Dictionary:
	var tile_data = create_default_tile(coords)
	
	if not coords.z in world_data:
		world_data[coords.z] = {}
	
	var coords_2d = Vector2i(coords.x, coords.y)
	world_data[coords.z][coords_2d] = tile_data
	add_to_spatial_hash(coords_2d, coords.z)
	
	return tile_data

func create_default_tile(coords: Vector3) -> Dictionary:
	return {
		TileLayer.FLOOR: {
			"type": "floor",
			"collision": false,
			"health": 100,
			"material": "metal"
		},
		TileLayer.WALL: null,
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
			"temperature": 293.15,
			"pressure": 101.325,
		},
		"contents": [],
		"tile_position": Vector2(coords.x * TILE_SIZE, coords.y * TILE_SIZE),
		"radiation": 0.0,
		"light_level": 5.0,
		"damages": [],
		"has_gravity": true
	}

func register_tilemap_tiles() -> int:
	if not floor_tilemap or not wall_tilemap:
		return 0

	var registered_count = 0
	
	registered_count += register_floor_tiles()
	registered_count += register_wall_tiles()
	registered_count += register_object_tiles()
	
	return registered_count

func register_floor_tiles() -> int:
	var count = 0
	
	for cell in floor_tilemap.get_used_cells(0):
		var tile_coords = Vector2i(cell.x, cell.y)
		var tile_data = ensure_tile_exists(tile_coords, 0)
		
		var floor_type = determine_floor_type(tile_coords)
		tile_data[TileLayer.FLOOR] = {
			"type": floor_type,
			"collision": false,
			"health": 100,
			"material": floor_type
		}
		count += 1
	
	return count

func register_wall_tiles() -> int:
	var count = 0
	
	for cell in wall_tilemap.get_used_cells(0):
		var tile_coords = Vector2i(cell.x, cell.y)
		var tile_data = ensure_tile_exists(tile_coords, 0)
		
		var wall_material = determine_wall_material(tile_coords)
		tile_data[TileLayer.WALL] = {
			"type": "wall",
			"material": wall_material,
			"health": 100
		}
		tile_data["is_walkable"] = false
		count += 1
	
	return count

func register_object_tiles() -> int:
	var objects_tilemap = get_node_or_null("VisualTileMap/ObjectsTileMap")
	if not objects_tilemap:
		return 0
	
	var count = 0
	
	for cell in objects_tilemap.get_used_cells(0):
		var tile_coords = Vector2i(cell.x, cell.y)
		var tile_data = ensure_tile_exists(tile_coords, 0)
		
		register_object_at_tile(tile_data, tile_coords, objects_tilemap)
		count += 1
	
	return count

func ensure_tile_exists(coords: Vector2i, z_level: int) -> Dictionary:
	var tile_data = get_tile_data(coords, z_level)
	if not tile_data:
		tile_data = add_tile(Vector3(coords.x, coords.y, z_level))
	return tile_data

func determine_floor_type(coords: Vector2i) -> String:
	var tile_data_obj = floor_tilemap.get_cell_tile_data(0, coords)
	if tile_data_obj:
		var terrain_id = tile_data_obj.terrain
		var floor_type = get_floor_type_from_terrain(terrain_id)
		if floor_type:
			return floor_type
	
	var atlas_coords = floor_tilemap.get_cell_atlas_coords(0, coords)
	return get_floor_type_from_atlas(atlas_coords)

func get_floor_type_from_terrain(terrain_id: int) -> String:
	var visualizer = get_node_or_null("VisualTileMap/TileMapVisualizer")
	if visualizer and "floor_terrain_mapping" in visualizer:
		for type_name in visualizer.floor_terrain_mapping.keys():
			var terrain_info = visualizer.floor_terrain_mapping[type_name]
			if terrain_info.terrain == terrain_id:
				return type_name
	return ""

func get_floor_type_from_atlas(atlas_coords: Vector2i) -> String:
	match atlas_coords.y:
		0: return "metal"
		1: return "carpet"
		_: return "floor"

func determine_wall_material(coords: Vector2i) -> String:
	var tile_data_obj = wall_tilemap.get_cell_tile_data(0, coords)
	if tile_data_obj:
		var terrain_id = tile_data_obj.terrain
		var wall_material = get_wall_material_from_terrain(terrain_id)
		if wall_material:
			return wall_material
	
	var atlas_coords = wall_tilemap.get_cell_atlas_coords(0, coords)
	return get_wall_material_from_atlas(atlas_coords)

func get_wall_material_from_terrain(terrain_id: int) -> String:
	var visualizer = get_node_or_null("VisualTileMap/TileMapVisualizer")
	if visualizer and "wall_terrain_mapping" in visualizer:
		for type_name in visualizer.wall_terrain_mapping.keys():
			var terrain_info = visualizer.wall_terrain_mapping[type_name]
			if terrain_info.terrain == terrain_id:
				return type_name
	return ""

func get_wall_material_from_atlas(atlas_coords: Vector2i) -> String:
	match atlas_coords.y:
		1: return "insulated"
		2: return "glass"
		_: return "metal"

func register_object_at_tile(tile_data: Dictionary, coords: Vector2i, objects_tilemap: TileMap):
	var atlas_coords = objects_tilemap.get_cell_atlas_coords(0, coords)
	
	if atlas_coords == Vector2i(0, 1) or atlas_coords == Vector2i(1, 1):
		var is_closed = (atlas_coords.x == 0)
		tile_data["door"] = {
			"closed": is_closed,
			"locked": false,
			"material": "metal",
			"health": 100
		}

func update_tile(coords, new_data, z_level = null):
	var level = get_z_level(coords, z_level)
	var coords_2d = get_coords_2d(coords)
	
	var old_data = get_tile_data(coords_2d, level)
	if old_data == null:
		old_data = add_tile(Vector3(coords_2d.x, coords_2d.y, level))
	
	if is_multiplayer_active and not is_server:
		network_request_tile_update.rpc_id(1, coords_2d.x, coords_2d.y, level, new_data)
		return old_data
	
	apply_tile_changes(old_data, new_data)
	emit_signal("tile_changed", coords_2d, level, old_data, new_data)
	
	if is_multiplayer_active and is_server:
		network_update_tile.rpc(coords_2d.x, coords_2d.y, level, new_data)
	
	return old_data

func get_z_level(coords, z_level):
	if coords is Vector3:
		return coords.z
	return current_z_level if z_level == null else z_level

func get_coords_2d(coords):
	if coords is Vector3:
		return Vector2i(coords.x, coords.y)
	elif coords is Vector2:
		return Vector2i(coords.x, coords.y)
	elif coords is Vector2i:
		return coords
	else:
		return Vector2i(0, 0)

func apply_tile_changes(old_data: Dictionary, new_data: Dictionary):
	for key in new_data.keys():
		old_data[key] = new_data[key]

func toggle_door(tile_coords, z_level):
	var tile = get_tile_data(tile_coords, z_level)
	if tile == null or not "door" in tile or not tile.door:
		return false
	
	if is_multiplayer_active and not is_server:
		network_request_door_toggle.rpc_id(1, tile_coords.x, tile_coords.y, z_level)
		return true
	
	tile.door.closed = not tile.door.closed
	emit_signal("door_toggled", tile_coords, z_level, not tile.door.closed)
	
	update_room_connections(tile_coords, z_level)
	
	if is_multiplayer_active and is_server:
		network_door_toggled.rpc(tile_coords.x, tile_coords.y, z_level, not tile.door.closed)
	
	return true

func update_room_connections(tile_coords: Vector2i, z_level: int):
	var room_key = Vector3(tile_coords.x, tile_coords.y, z_level)
	if room_key in tile_to_room:
		var room_id = tile_to_room[room_key]
		if room_id in rooms:
			rooms[room_id].needs_equalization = true

func toggle_wall_at(coords: Vector2i, z_level: int) -> bool:
	if is_multiplayer_active and not is_server:
		network_request_wall_toggle.rpc_id(1, coords.x, coords.y, z_level)
		return false
	
	var tile = get_tile_data(coords, z_level)
	if not tile:
		tile = add_tile(Vector3(coords.x, coords.y, z_level))
	
	var wall_exists = TileLayer.WALL in tile and tile[TileLayer.WALL] != null
	
	if wall_exists:
		tile[TileLayer.WALL] = null
	else:
		tile[TileLayer.WALL] = {
			"type": "wall",
			"material": "metal",
			"health": 100
		}
	
	tile["is_walkable"] = not wall_exists
	emit_signal("tile_changed", coords, z_level, tile, tile)
	
	update_tilemap_wall(coords, z_level, not wall_exists)
	
	if is_multiplayer_active and is_server:
		network_wall_toggled.rpc(coords.x, coords.y, z_level, not wall_exists)
	
	return not wall_exists

func update_tilemap_wall(coords: Vector2i, z_level: int, wall_exists: bool):
	if wall_tilemap and z_level == 0:
		if wall_exists:
			wall_tilemap.set_cell(0, coords, 0, Vector2i(0, 0))
		else:
			wall_tilemap.set_cell(0, coords, -1)

func initialize_chunk_culling():
	var culling_system = ChunkCullingSystem.new()
	culling_system.name = "ChunkCullingSystem"
	add_child(culling_system)
	
	setup_culling_optimization(culling_system)
	connect("player_changed_position", Callable(self, "_on_player_position_changed_culling"))
	
	return culling_system

func setup_culling_optimization(culling_system: Node):
	var optimization_manager = get_node_or_null("/root/OptimizationManager")
	if optimization_manager:
		culling_system.occlusion_enabled = optimization_manager.settings.occlusion_culling
		optimization_manager.connect("settings_changed", Callable(self, "_on_optimization_settings_changed"))

func load_chunks_around(world_position: Vector2, z_level: int = current_z_level, radius: int = 2):
	var culling_system = get_node_or_null("ChunkCullingSystem")
	if culling_system:
		culling_system.update_all_chunk_visibility()
	
	return loaded_chunks

func load_chunk(chunk_pos: Vector2i, z_level: int):
	var chunk_bounds = calculate_chunk_bounds(chunk_pos)
	var is_station_chunk = check_if_station_chunk(chunk_pos, z_level)
	
	if z_level == 0:
		generate_chunk_tiles(chunk_bounds, is_station_chunk, z_level)
	
	load_chunk_entities(chunk_pos, z_level, is_station_chunk)

func calculate_chunk_bounds(chunk_pos: Vector2i) -> Dictionary:
	return {
		"start_x": chunk_pos.x * CHUNK_SIZE,
		"start_y": chunk_pos.y * CHUNK_SIZE,
		"end_x": chunk_pos.x * CHUNK_SIZE + CHUNK_SIZE - 1,
		"end_y": chunk_pos.y * CHUNK_SIZE + CHUNK_SIZE - 1
	}

func check_if_station_chunk(chunk_pos: Vector2i, z_level: int) -> bool:
	if z_level != 0 or not zone_tilemap:
		return false
	
	var bounds = calculate_chunk_bounds(chunk_pos)
	
	for x in range(bounds.start_x, bounds.end_x + 1, 4):
		for y in range(bounds.start_y, bounds.end_y + 1, 4):
			if zone_tilemap.get_cell_source_id(0, Vector2i(x, y)) != -1:
				return true
	
	return false

func generate_chunk_tiles(bounds: Dictionary, is_station_chunk: bool, z_level: int):
	for x in range(bounds.start_x, bounds.end_x + 1):
		for y in range(bounds.start_y, bounds.end_y + 1):
			var tile_coords = Vector2i(x, y)
			
			if has_existing_tile(tile_coords, z_level):
				continue
			
			if should_generate_tile(tile_coords, bounds, is_station_chunk):
				if not get_tile_data(tile_coords, z_level):
					add_tile(Vector3(x, y, z_level))
			elif should_create_space_tile(tile_coords, bounds, is_station_chunk):
				create_space_tile(tile_coords, z_level)

func has_existing_tile(coords: Vector2i, z_level: int) -> bool:
	var has_floor = floor_tilemap and floor_tilemap.get_cell_source_id(0, coords) != -1
	var has_wall = wall_tilemap and wall_tilemap.get_cell_source_id(0, coords) != -1
	return has_floor or has_wall

func should_generate_tile(coords: Vector2i, bounds: Dictionary, is_station_chunk: bool) -> bool:
	return has_existing_tile(coords, 0)

func should_create_space_tile(coords: Vector2i, bounds: Dictionary, is_station_chunk: bool) -> bool:
	if is_station_chunk:
		return false
	
	var is_edge = (coords.x == bounds.start_x or coords.x == bounds.end_x or 
				   coords.y == bounds.start_y or coords.y == bounds.end_y)
	
	return is_edge and randf() < 0.1

func create_space_tile(coords: Vector2i, z_level: int):
	if get_tile_data(coords, z_level):
		return
	
	var tile_data = {
		TileLayer.ATMOSPHERE: {
			"oxygen": 0.0,
			"nitrogen": 0.0,
			"temperature": 2.7,
			"pressure": 0.0,
			"has_gravity": false
		},
		"is_space": true,
		"has_gravity": false,
		"tile_position": Vector2(coords.x * TILE_SIZE, coords.y * TILE_SIZE)
	}
	
	if randf() < 0.02:
		tile_data["space_object"] = {
			"type": "asteroid",
			"size": randf_range(0.5, 2.0)
		}
	
	if not z_level in world_data:
		world_data[z_level] = {}
	
	world_data[z_level][coords] = tile_data
	add_to_spatial_hash(coords, z_level)
	
	return tile_data

func get_tile_at(world_position: Vector2, z_level = current_z_level) -> Vector2i:
	var tile_x = floor(world_position.x / TILE_SIZE)
	var tile_y = floor(world_position.y / TILE_SIZE)
	return Vector2i(tile_x, tile_y)

func tile_to_world(tile_pos: Vector2) -> Vector2:
	return Vector2(
		(tile_pos.x * TILE_SIZE) + (TILE_SIZE / 2.0), 
		(tile_pos.y * TILE_SIZE) + (TILE_SIZE / 2.0)
	)

func get_tile_data(coords, layer = null):
	var z_level = get_z_level(coords, layer)
	var coords_2d = get_coords_2d(coords)
	
	if z_level in world_data and coords_2d in world_data[z_level]:
		return world_data[z_level][coords_2d]
	
	return null

func is_valid_tile(coords, z_level = current_z_level) -> bool:
	var tile_coords = get_coords_2d(coords)
	
	if z_level == 0:
		if zone_tilemap and zone_tilemap.get_cell_source_id(0, tile_coords) != -1:
			return true
		
		if floor_tilemap and floor_tilemap.get_cell_source_id(0, tile_coords) != -1:
			return true
		
		if wall_tilemap and wall_tilemap.get_cell_source_id(0, tile_coords) != -1:
			return true
		
		var objects_tilemap = get_node_or_null("VisualTileMap/ObjectsTileMap")
		if objects_tilemap and objects_tilemap.get_cell_source_id(0, tile_coords) != -1:
			return true
	
	return z_level in world_data and tile_coords in world_data[z_level]

func is_wall_at(tile_coords: Vector2i, z_level: int = current_z_level) -> bool:
	if wall_tilemap.get_cell_source_id(0, tile_coords) != -1:
		return true
	
	var tile_data = get_tile_data(tile_coords, z_level)
	return tile_data is Dictionary and TileLayer.WALL in tile_data and tile_data[TileLayer.WALL] != null

func get_adjacent_tiles(coords, z_level):
	var adjacents = [
		Vector2(coords.x + 1, coords.y),
		Vector2(coords.x - 1, coords.y),
		Vector2(coords.x, coords.y + 1),
		Vector2(coords.x, coords.y - 1)
	]
	
	var valid_adjacents = []
	for adj in adjacents:
		if get_tile_data(adj, z_level) != null:
			valid_adjacents.append(adj)
	
	return valid_adjacents

func add_to_spatial_hash(coords: Vector2, z_level = current_z_level):
	var cell_x = floor(coords.x / SPATIAL_CELL_SIZE)
	var cell_y = floor(coords.y / SPATIAL_CELL_SIZE)
	var cell_key = Vector3(cell_x, cell_y, z_level)
	
	if not cell_key in spatial_hash:
		spatial_hash[cell_key] = []
		
	if not coords in spatial_hash[cell_key]:
		spatial_hash[cell_key].append(coords)

func update_spatial_hash():
	spatial_hash.clear()
	
	for z in world_data.keys():
		for coords in world_data[z].keys():
			add_to_spatial_hash(coords, z)

func connect_player_signals(player_node):
	var grid_controller = player_node.get_node_or_null("GridMovementController")
	if not grid_controller:
		return
	
	connect_signal_safe(grid_controller, "tile_changed", "_on_player_tile_changed")
	connect_signal_safe(grid_controller, "state_changed", "_on_player_state_changed")
	
	if interaction_system and grid_controller.has_signal("interaction_requested"):
		var callable = Callable(interaction_system, "handle_use")
		if not grid_controller.is_connected("interaction_requested", callable):
			grid_controller.connect("interaction_requested", callable)
	
	if collision_resolver and grid_controller.has_signal("bump"):
		var callable = Callable(collision_resolver, "resolve_collision")
		if not grid_controller.is_connected("bump", callable):
			grid_controller.connect("bump", callable)

func connect_signal_safe(source: Node, signal_name: String, method_name: String):
	if not source or not source.has_signal(signal_name):
		return
	
	var callable = Callable(self, method_name)
	if not source.is_connected(signal_name, callable):
		source.connect(signal_name, callable)

func register_player_with_systems(player_node):
	var grid_controller = player_node.get_node_or_null("GridMovementController")
	if not grid_controller:
		return
	
	register_with_sensory_system(grid_controller)
	register_with_spatial_manager(grid_controller)
	register_with_tile_occupancy(grid_controller)

func register_with_sensory_system(grid_controller):
	if sensory_system:
		sensory_system.register_entity(grid_controller)

func register_with_spatial_manager(grid_controller):
	if spatial_manager:
		spatial_manager.register_entity(grid_controller)

func register_with_tile_occupancy(grid_controller):
	if tile_occupancy_system:
		var tile_pos = grid_controller.current_tile_position
		var z_level = grid_controller.current_z_level
		tile_occupancy_system.register_entity_at_tile(grid_controller, tile_pos, z_level)

func find_spawn_position() -> Vector2:
	var spawn_pos = Vector2(5 * TILE_SIZE, 5 * TILE_SIZE)
	
	if zone_tilemap:
		var cells = zone_tilemap.get_used_cells(0)
		if cells.size() > 0:
			spawn_pos = calculate_center_position(cells)
	
	return spawn_pos

func calculate_center_position(cells: Array) -> Vector2:
	var sum_x = 0
	var sum_y = 0
	
	for cell in cells:
		sum_x += cell.x
		sum_y += cell.y
	
	return Vector2(
		(sum_x / cells.size()) * TILE_SIZE,
		(sum_y / cells.size()) * TILE_SIZE
	)

func setup_initial_chunks():
	var spawn_pos = find_spawn_position()
	
	if is_server:
		load_chunks_around(spawn_pos, 0, 2)

func initialize_space_tiles():
	var perimeter_tiles = find_perimeter_tiles()
	
	if is_multiplayer_active and not is_server:
		return
	
	generate_space_around_perimeter(perimeter_tiles)

func find_perimeter_tiles() -> Array:
	var perimeter_tiles = []
	
	if zone_tilemap:
		perimeter_tiles = find_zone_perimeter_tiles()
	else:
		perimeter_tiles = find_wall_perimeter_tiles()
	
	return perimeter_tiles

func find_zone_perimeter_tiles() -> Array:
	var perimeter_tiles = []
	var zone_tiles = zone_tilemap.get_used_cells(0)
	
	for zone_tile in zone_tiles:
		if is_perimeter_tile(zone_tile):
			perimeter_tiles.append(zone_tile)
	
	return perimeter_tiles

func is_perimeter_tile(tile: Vector2i) -> bool:
	var neighbors = [
		Vector2i(tile.x + 1, tile.y),
		Vector2i(tile.x - 1, tile.y),
		Vector2i(tile.x, tile.y + 1),
		Vector2i(tile.x, tile.y - 1)
	]
	
	for neighbor in neighbors:
		if zone_tilemap.get_cell_source_id(0, neighbor) == -1:
			return true
	
	return false

func find_wall_perimeter_tiles() -> Array:
	var perimeter_tiles = []
	
	for z in world_data.keys():
		if int(z) != 0:
			continue
		
		for coords in world_data[z].keys():
			if is_wall_at(coords, z) and has_empty_neighbors(coords, z):
				perimeter_tiles.append(coords)
	
	return perimeter_tiles

func has_empty_neighbors(coords: Vector2i, z_level: int) -> bool:
	var neighbors = [
		Vector2i(coords.x + 1, coords.y),
		Vector2i(coords.x - 1, coords.y),
		Vector2i(coords.x, coords.y + 1),
		Vector2i(coords.x, coords.y - 1)
	]
	
	for neighbor in neighbors:
		if not is_valid_tile(neighbor, z_level):
			return true
	
	return false

func generate_space_around_perimeter(perimeter_tiles: Array):
	var space_count = 0
	
	for perimeter_tile in perimeter_tiles:
		space_count += generate_space_grid_around_tile(perimeter_tile)

func generate_space_grid_around_tile(tile: Vector2i) -> int:
	var space_count = 0
	
	for x in range(-3, 4):
		for y in range(-3, 4):
			var space_tile = Vector2i(tile.x + x, tile.y + y)
			
			if should_skip_space_tile(space_tile):
				continue
			
			space_count += create_or_update_space_tile(space_tile)
	
	return space_count

func should_skip_space_tile(coords: Vector2i) -> bool:
	if zone_tilemap and zone_tilemap.get_cell_source_id(0, coords) != -1:
		return true
	
	if floor_tilemap and floor_tilemap.get_cell_source_id(0, coords) != -1:
		return true
	
	if wall_tilemap and wall_tilemap.get_cell_source_id(0, coords) != -1:
		return true
	
	return false

func create_or_update_space_tile(coords: Vector2i) -> int:
	var tile_data = get_tile_data(coords, 0)
	
	if not tile_data:
		create_space_tile(coords, 0)
		return 1
	elif not TileLayer.ATMOSPHERE in tile_data:
		add_space_atmosphere_to_tile(tile_data)
		return 1
	
	update_tile_space_properties(tile_data)
	return 0

func add_space_atmosphere_to_tile(tile_data: Dictionary):
	tile_data[TileLayer.ATMOSPHERE] = {
		atmosphere_system.GAS_TYPE_OXYGEN: 0.0,
		atmosphere_system.GAS_TYPE_NITROGEN: 0.0,
		"temperature": 2.7,
		"pressure": 0.0,
		"has_gravity": false
	}

func update_tile_space_properties(tile_data: Dictionary):
	tile_data["is_space"] = true
	tile_data["has_gravity"] = false

func add_z_connections():
	var connection_points = [
		Vector2(10, 10),
		Vector2(30, 30),
		Vector2(20, 5)
	]
	
	for point in connection_points:
		create_z_connections_at_point(point)

func create_z_connections_at_point(point: Vector2):
	for z in range(z_levels - 1):
		var lower_tile = get_tile_data(Vector3(point.x, point.y, z))
		var upper_tile = get_tile_data(Vector3(point.x, point.y, z + 1))
		
		if lower_tile and upper_tile:
			create_bidirectional_z_connection(point, z, lower_tile, upper_tile)

func create_bidirectional_z_connection(point: Vector2, z: int, lower_tile: Dictionary, upper_tile: Dictionary):
	var connection_type = "stairs" if z == 0 else "elevator"
	
	lower_tile["z_connection"] = {
		"type": connection_type,
		"direction": "up",
		"target": Vector3(point.x, point.y, z + 1)
	}
	
	upper_tile["z_connection"] = {
		"type": connection_type,
		"direction": "down",
		"target": Vector3(point.x, point.y, z)
	}

func detect_rooms():
	rooms.clear()
	tile_to_room.clear()
	
	for z in world_data.keys():
		detect_rooms_for_z_level(z)

func detect_rooms_for_z_level(z: int):
	var visited = {}
	var room_id = 0
	
	for coords in world_data[z].keys():
		if coords in visited:
			continue
		
		var room_tiles = flood_fill_room(coords, z, visited)
		if room_tiles.size() > 0:
			create_room(room_id, room_tiles, z)
			room_id += 1

func flood_fill_room(start_coords: Vector2i, z_level: int, visited: Dictionary) -> Array:
	var room_tiles = []
	var to_visit = [start_coords]
	
	while to_visit.size() > 0:
		var current = to_visit.pop_front()
		
		if current in visited:
			continue
		
		visited[current] = true
		room_tiles.append(current)
		
		add_adjacent_tiles_to_visit(current, z_level, visited, to_visit)
	
	return room_tiles

func add_adjacent_tiles_to_visit(current: Vector2i, z_level: int, visited: Dictionary, to_visit: Array):
	for neighbor in get_adjacent_tiles(current, z_level):
		if neighbor in visited:
			continue
		
		if not is_airtight_barrier(current, neighbor, z_level):
			to_visit.append(neighbor)

func create_room(room_id: int, room_tiles: Array, z_level: int):
	rooms[room_id] = {
		"tiles": room_tiles,
		"z_level": z_level,
		"volume": room_tiles.size(),
		"atmosphere": calculate_room_atmosphere(room_tiles, z_level),
		"connections": detect_room_connections(room_tiles, z_level),
		"needs_equalization": false
	}
	
	for tile in room_tiles:
		tile_to_room[Vector3(tile.x, tile.y, z_level)] = room_id

func calculate_room_atmosphere(tiles, z_level):
	var total_gases = {}
	var total_energy = 0.0
	var tile_count = 0
	
	for tile_coords in tiles:
		var tile = get_tile_data(tile_coords, z_level)
		if tile is Dictionary or not TileLayer.ATMOSPHERE in tile:
			continue
		
		var atmo = tile[TileLayer.ATMOSPHERE]
		accumulate_gas_data(atmo, total_gases)
		
		if "temperature" in atmo:
			total_energy += atmo.temperature
		
		tile_count += 1
	
	return calculate_average_atmosphere(total_gases, total_energy, tile_count)

func accumulate_gas_data(atmo: Dictionary, total_gases: Dictionary):
	for gas_key in atmo.keys():
		if gas_key != "temperature" and gas_key != "pressure" and typeof(atmo[gas_key]) == TYPE_FLOAT:
			if not gas_key in total_gases:
				total_gases[gas_key] = 0.0
			total_gases[gas_key] += atmo[gas_key]

func calculate_average_atmosphere(total_gases: Dictionary, total_energy: float, tile_count: int) -> Dictionary:
	var result = {}
	
	if tile_count > 0:
		for gas_key in total_gases.keys():
			result[gas_key] = total_gases[gas_key] / tile_count
		
		if total_energy > 0:
			result["temperature"] = total_energy / tile_count
		
		result["pressure"] = calculate_total_pressure(result)
	else:
		result = create_default_atmosphere()
	
	return result

func calculate_total_pressure(atmosphere: Dictionary) -> float:
	var total_pressure = 0.0
	for gas_key in atmosphere.keys():
		if gas_key != "temperature" and gas_key != "pressure":
			total_pressure += atmosphere[gas_key]
	return total_pressure

func create_default_atmosphere() -> Dictionary:
	return {
		"oxygen": 0.0,
		"nitrogen": 0.0,
		"co2": 0.0,
		"temperature": 293.15,
		"pressure": 0.0
	}

func detect_room_connections(room_tiles, z_level):
	var connections = []

	for tile_coords in room_tiles:
		var tile = get_tile_data(tile_coords, z_level)
		if not tile:
			continue

		connections.append_array(find_tile_connections(tile, tile_coords))

	return connections

func find_tile_connections(tile: Dictionary, tile_coords: Vector2i) -> Array:
	var connections = []
	
	if "door" in tile and tile.door:
		connections.append(create_door_connection(tile, tile_coords))
	
	if TileLayer.PIPE in tile:
		var pipe_connection = create_pipe_connection(tile, tile_coords)
		if pipe_connection:
			connections.append(pipe_connection)
	
	if "z_connection" in tile:
		var z_connection = create_z_connection(tile, tile_coords)
		if z_connection:
			connections.append(z_connection)
	
	return connections

func create_door_connection(tile: Dictionary, tile_coords: Vector2i) -> Dictionary:
	var door = tile.door
	var is_closed = false
	if door and "closed" in door:
		is_closed = door.closed
	
	return {
		"type": "door",
		"tile": tile_coords,
		"state": "closed" if is_closed else "open"
	}

func create_pipe_connection(tile: Dictionary, tile_coords: Vector2i):
	if not TileLayer.PIPE in tile:
		return null
	
	var pipe = tile[TileLayer.PIPE]
	if pipe and "content_type" in pipe and pipe.content_type == "air":
		var network_id = -1
		if "network_id" in pipe:
			network_id = pipe.network_id
		
		return {
			"type": "vent",
			"tile": tile_coords,
			"network_id": network_id
		}
	return null

func create_z_connection(tile: Dictionary, tile_coords: Vector2i):
	if not "z_connection" in tile:
		return null
	
	var z_conn = tile.z_connection
	if z_conn and "type" in z_conn and "target" in z_conn and "direction" in z_conn:
		return {
			"type": z_conn.type,
			"tile": tile_coords,
			"target": z_conn.target,
			"direction": z_conn.direction
		}
	return null

func get_nearby_tiles(center: Vector2, radius: float, z_level = current_z_level) -> Array:
	var cell_bounds = calculate_search_bounds(center, radius)
	var result = []
	
	for cell_x in range(cell_bounds.start_x, cell_bounds.end_x + 1):
		for cell_y in range(cell_bounds.start_y, cell_bounds.end_y + 1):
			var cell_key = Vector3(cell_x, cell_y, z_level)
			
			if cell_key in spatial_hash:
				result.append_array(filter_tiles_by_distance(spatial_hash[cell_key], center, radius))
	
	return result

func calculate_search_bounds(center: Vector2, radius: float) -> Dictionary:
	return {
		"start_x": floor((center.x - radius) / SPATIAL_CELL_SIZE),
		"start_y": floor((center.y - radius) / SPATIAL_CELL_SIZE),
		"end_x": floor((center.x + radius) / SPATIAL_CELL_SIZE),
		"end_y": floor((center.y + radius) / SPATIAL_CELL_SIZE)
	}

func filter_tiles_by_distance(tiles: Array, center: Vector2, radius: float) -> Array:
	var filtered = []
	
	for tile_coords in tiles:
		var tile_world_pos = Vector2(tile_coords.x * TILE_SIZE, tile_coords.y * TILE_SIZE)
		var distance = center.distance_to(tile_world_pos)
		
		if distance <= radius:
			filtered.append(tile_coords)
	
	return filtered

func get_entities_in_radius(center: Vector2, radius: float, z_level = current_z_level) -> Array:
	if spatial_manager:
		return spatial_manager.get_entities_near(center, radius, z_level)
	
	if tile_occupancy_system:
		return get_entities_from_occupancy_system(center, radius, z_level)
	
	return get_entities_from_world_data(center, radius, z_level)

func get_entities_from_occupancy_system(center: Vector2, radius: float, z_level: int) -> Array:
	var entities = []
	var tile_radius = ceil(radius / TILE_SIZE)
	var center_tile = get_tile_at(center)
	
	for x in range(-tile_radius, tile_radius + 1):
		for y in range(-tile_radius, tile_radius + 1):
			var check_tile = Vector2i(center_tile.x + x, center_tile.y + y)
			var tile_entities = tile_occupancy_system.get_entities_at(check_tile, z_level)
			
			entities.append_array(filter_entities_by_distance(tile_entities, center, radius))
	
	return remove_duplicate_entities(entities)

func filter_entities_by_distance(entities: Array, center: Vector2, radius: float) -> Array:
	var filtered = []
	
	for entity in entities:
		if "position" in entity:
			var distance = center.distance_to(entity.position)
			if distance <= radius:
				filtered.append(entity)
	
	return filtered

func remove_duplicate_entities(entities: Array) -> Array:
	var unique_entities = []
	for entity in entities:
		if not entity in unique_entities:
			unique_entities.append(entity)
	return unique_entities

func get_entities_from_world_data(center: Vector2, radius: float, z_level: int) -> Array:
	var nearby_tiles = get_nearby_tiles(center, radius, z_level)
	var entities = []
	
	for tile_coords in nearby_tiles:
		var tile = get_tile_data(tile_coords, z_level)
		if tile and "contents" in tile:
			entities.append_array(tile.contents)
	
	return remove_duplicate_entities(entities)

func is_space(tile_coords: Vector2i, z_level: int = current_z_level) -> bool:
	if z_level == 0:
		if zone_tilemap and zone_tilemap.get_cell_source_id(0, tile_coords) == -1:
			return true
		
		if has_tilemap_data(tile_coords):
			return false
	
	var tile_data = get_tile_data(tile_coords, z_level)
	if tile_data and "is_space" in tile_data:
		return tile_data.is_space
	
	return not (z_level in world_data and tile_coords in world_data[z_level])

func has_tilemap_data(coords: Vector2i) -> bool:
	if floor_tilemap and floor_tilemap.get_cell_source_id(0, coords) != -1:
		return true
	
	if wall_tilemap and wall_tilemap.get_cell_source_id(0, coords) != -1:
		return true
	
	var objects_tilemap = get_node_or_null("VisualTileMap/ObjectsTileMap")
	if objects_tilemap and objects_tilemap.get_cell_source_id(0, coords) != -1:
		return true
	
	return false

func is_in_zone(tile_coords: Vector2i, z_level: int = current_z_level) -> bool:
	return z_level == 0 and zone_tilemap and zone_tilemap.get_cell_source_id(0, tile_coords) != -1

func is_tile_blocked(coords, z_level = current_z_level):
	var tile_coords = get_coords_2d(coords)
	
	if is_wall_at(tile_coords, z_level):
		return true
	
	var tile = get_tile_data(tile_coords, z_level)
	if tile and has_closed_door(tile):
		return true
	
	if tile_occupancy_system:
		return tile_occupancy_system.has_dense_entity_at(tile_coords, z_level)
	
	return has_blocking_contents(tile)

func has_closed_door(tile: Dictionary) -> bool:
	if not tile or not "door" in tile:
		return false
	
	var door = tile.door
	return door and "closed" in door and door.closed

func has_blocking_contents(tile: Dictionary) -> bool:
	if not tile or not "contents" in tile:
		return false
	
	for entity in tile.contents:
		if "blocks_movement" in entity and entity.blocks_movement:
			return true
	
	return false

func is_airtight_barrier(tile1_coords, tile2_coords, z_level):
	var tile1 = get_tile_data(tile1_coords, z_level)
	var tile2 = get_tile_data(tile2_coords, z_level)
	
	if not tile1 or not tile2:
		return true
	
	return (has_wall_layer(tile1) or has_wall_layer(tile2) or 
			has_closed_door(tile1) or has_closed_door(tile2))

func has_wall_layer(tile: Dictionary) -> bool:
	return TileLayer.WALL in tile and tile[TileLayer.WALL] != null

func get_entities_at_tile(tile_coords, z_level):
	if tile_occupancy_system:
		return tile_occupancy_system.get_entities_at(tile_coords, z_level)
	
	var tile = get_tile_data(tile_coords, z_level)
	return tile.get("contents", []) if tile else []

func check_entity_void_status(entity, tile_pos, z_level):
	if not entity:
		return
	
	var in_space = is_space(tile_pos, z_level)
	var zero_g_controller = entity.get_node_or_null("ZeroGController")
	
	if zero_g_controller:
		if in_space and not zero_g_controller.is_in_zero_g():
			zero_g_controller.activate_zero_g()
		elif not in_space and zero_g_controller.is_in_zero_g():
			zero_g_controller.deactivate_zero_g()

func get_floor_type(tile_coords, z_level):
	var tile = get_tile_data(tile_coords, z_level)
	if tile is Dictionary:
		var floor = tile.get(TileLayer.FLOOR)
		if floor and "type" in floor:
			return floor.type
	return "floor"

func count_tiles() -> int:
	var count = 0
	for z in world_data.keys():
		count += world_data[z].size()
	return count

func load_chunk_entities(chunk_pos: Vector2i, z_level: int, is_station_chunk: bool = false):
	var chunk_key = get_chunk_key(chunk_pos, z_level)
	
	if chunk_key in chunk_entities:
		return
	
	chunk_entities[chunk_key] = []
	
	if not is_station_chunk and z_level == 0:
		generate_chunk_entities(chunk_pos, z_level)

func get_chunk_key(chunk_pos: Vector2i, z_level: int) -> String:
	return str(chunk_pos.x) + "_" + str(chunk_pos.y) + "_" + str(z_level)

func generate_chunk_entities(chunk_pos: Vector2i, z_level: int):
	var entity_count = randi() % 4
	
	for i in range(entity_count):
		var x = chunk_pos.x * CHUNK_SIZE + randi() % CHUNK_SIZE
		var y = chunk_pos.y * CHUNK_SIZE + randi() % CHUNK_SIZE
		var tile_coords = Vector2i(x, y)
		
		if is_valid_tile(tile_coords, z_level):
			continue

func unload_chunk_entities(chunk_pos: Vector2i, z_level: int):
	var chunk_key = get_chunk_key(chunk_pos, z_level)
	
	if not chunk_key in chunk_entities:
		return
	
	for entity in chunk_entities[chunk_key]:
		remove_entity_from_systems(entity)
	
	chunk_entities.erase(chunk_key)

func remove_entity_from_systems(entity: Node):
	if not entity or not is_instance_valid(entity):
		return
	
	if spatial_manager:
		spatial_manager.unregister_entity(entity)
	
	if tile_occupancy_system and "position" in entity:
		var entity_tile = Vector2i(
			floor(entity.position.x / TILE_SIZE),
			floor(entity.position.y / TILE_SIZE)
		)
		var z_level = entity.get("current_z_level") if entity.has_method("get") else 0
		tile_occupancy_system.remove_entity(entity, entity_tile, z_level)
	
	var is_persistent = false
	if entity.has_method("get"):
		is_persistent = entity.get("persistent")
	elif "persistent" in entity:
		is_persistent = entity.persistent
	
	if not is_persistent:
		entity.queue_free()

@rpc("authority", "call_remote", "reliable")
func network_sync_chunks(chunk_positions, z_level):
	if is_server:
		return
	
	for chunk_pos in chunk_positions:
		queue_chunk_for_loading(chunk_pos, z_level)

func queue_chunk_for_loading(chunk_pos: Vector2i, z_level: int):
	var chunk_key = get_chunk_key(chunk_pos, z_level)
	
	if chunk_key in loaded_chunks:
		return
	
	loaded_chunks[chunk_key] = true

@rpc("authority", "call_remote", "reliable")
func network_update_tile(x, y, z_level, new_data):
	if is_server:
		return
	
	var coords_2d = Vector2i(x, y)
	var old_data = get_tile_data(coords_2d, z_level)
	
	if old_data == null:
		old_data = add_tile(Vector3(x, y, z_level))
	
	apply_tile_changes(old_data, new_data)
	emit_signal("tile_changed", coords_2d, z_level, old_data, new_data)

@rpc("any_peer", "call_local", "reliable")
func network_request_tile_update(x, y, z_level, new_data):
	if not is_server:
		return
	
	var coords_2d = Vector2i(x, y)
	update_tile(coords_2d, new_data, z_level)

@rpc("authority", "call_remote", "reliable")
func network_door_toggled(x, y, z_level, is_open):
	if is_server:
		return
	
	var tile_coords = Vector2i(x, y)
	var tile = get_tile_data(tile_coords, z_level)
	
	if tile and "door" in tile and tile.door:
		tile.door.closed = not is_open
		emit_signal("door_toggled", tile_coords, z_level, is_open)

@rpc("any_peer", "call_local", "reliable")
func network_request_door_toggle(x, y, z_level):
	if is_server:
		toggle_door(Vector2i(x, y), z_level)

@rpc("authority", "call_remote", "reliable")
func network_wall_toggled(x, y, z_level, wall_exists):
	if is_server:
		return
	
	apply_wall_toggle_result(Vector2i(x, y), z_level, wall_exists)

func apply_wall_toggle_result(coords: Vector2i, z_level: int, wall_exists: bool):
	var tile = get_tile_data(coords, z_level)
	if not tile:
		tile = add_tile(Vector3(coords.x, coords.y, z_level))
	
	if tile:
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
		
		emit_signal("tile_changed", coords, z_level, tile, tile)
		update_tilemap_wall(coords, z_level, wall_exists)

@rpc("any_peer", "call_local", "reliable")
func network_request_wall_toggle(x, y, z_level):
	if is_server:
		toggle_wall_at(Vector2i(x, y), z_level)

func _on_player_spawned(node):
	if node.is_in_group("player_controller"):
		var is_local_player = determine_if_local_player(node)
		configure_player_systems(node, is_local_player)
		register_spawned_player_with_systems(node, is_local_player)
		
		if is_local_player:
			local_player = node

func determine_if_local_player(player: Node) -> bool:
	if player.has_node("MultiplayerSynchronizer"):
		var sync = player.get_node("MultiplayerSynchronizer")
		return sync.get_multiplayer_authority() == multiplayer.get_unique_id()
	return false

func configure_player_systems(player: Node, is_local: bool):
	configure_player_camera(player, is_local)
	configure_player_ui(player, is_local)
	configure_player_input(player, is_local)
	
	if player.has_method("set_local_player"):
		player.set_local_player(is_local)

func configure_player_camera(player: Node, is_local: bool):
	var camera = player.get_node_or_null("Camera2D")
	if camera:
		camera.enabled = is_local

func configure_player_ui(player: Node, is_local: bool):
	var ui = player.get_node_or_null("PlayerUI")
	if ui:
		ui.visible = is_local

func configure_player_input(player: Node, is_local: bool):
	var input_controller = player.get_node_or_null("InputController")
	if input_controller:
		input_controller.set_process_input(is_local)
		input_controller.set_process_unhandled_input(is_local)

func register_spawned_player_with_systems(player: Node, is_local: bool):
	register_with_click_handlers(player, is_local)
	register_with_interaction_systems(player)
	register_with_tile_occupancy_if_available(player)

func register_with_click_handlers(player: Node, is_local: bool):
	if not is_local:
		return
	
	var click_handlers = get_tree().get_nodes_in_group("click_system")
	for handler in click_handlers:
		if handler.has_method("set_player_reference"):
			handler.set_player_reference(player)

func register_with_interaction_systems(player: Node):
	var interaction_systems = get_tree().get_nodes_in_group("interaction_system")
	for system in interaction_systems:
		if system.has_method("register_player"):
			system.register_player(player, false)

func register_with_tile_occupancy_if_available(player: Node):
	if tile_occupancy_system and tile_occupancy_system.has_method("register_entity"):
		tile_occupancy_system.register_entity(player)

func _on_player_position_changed_culling(position, z_level):
	var culling_system = get_node_or_null("ChunkCullingSystem")
	if culling_system and z_level != culling_system.current_z_level:
		culling_system.set_z_level(z_level)

func _on_optimization_settings_changed(setting_name, new_value):
	var culling_system = get_node_or_null("ChunkCullingSystem")
	if culling_system and setting_name == "occlusion_culling":
		culling_system.set_occlusion_enabled(new_value)

func _on_player_tile_changed(old_tile, new_tile):
	if not player:
		return
	
	var grid_controller = player.get_node_or_null("GridMovementController")
	if not grid_controller:
		return
	
	var z_level = grid_controller.current_z_level
	emit_signal("player_changed_position", player.position, z_level)
	
	check_entity_void_status(player, new_tile, z_level)
	
	if sensory_system:
		var floor_type = get_floor_type(new_tile, z_level)
		sensory_system.emit_footstep_sound(grid_controller)

func _on_player_state_changed(old_state, new_state):
	if not player:
		return
	
	var grid_controller = player.get_node_or_null("GridMovementController")
	if not grid_controller:
		return
	
	handle_player_state_sounds(old_state, new_state, grid_controller)

func handle_player_state_sounds(old_state: int, new_state: int, grid_controller: Node):
	if not sensory_system:
		return
	
	var position = player.position
	var z_level = grid_controller.current_z_level
	
	match new_state:
		2:
			sensory_system.emit_sound(position, z_level, "footstep", 0.7, grid_controller)
		3:
			sensory_system.emit_sound(position, z_level, "thud", 0.5, grid_controller)
		4:
			sensory_system.emit_sound(position, z_level, "footstep", 0.2, grid_controller)
		5:
			if old_state != 5:
				sensory_system.emit_sound(position, z_level, "thud", 0.3, grid_controller)

func _on_atmosphere_changed(coordinates, old_data, new_data):
	var tile_coords = Vector2(coordinates.x, coordinates.y)
	var z_level = coordinates.z
	
	update_tile_atmosphere(tile_coords, z_level, new_data)
	update_room_atmosphere(tile_coords, z_level)
	notify_entities_of_atmosphere_change(tile_coords, z_level, new_data)

func update_tile_atmosphere(coords: Vector2, z_level: int, new_data: Dictionary):
	var tile = get_tile_data(coords, z_level)
	if tile is Dictionary:
		tile[TileLayer.ATMOSPHERE] = new_data

func update_room_atmosphere(coords: Vector2, z_level: int):
	var room_key = Vector3(coords.x, coords.y, z_level)
	if room_key in tile_to_room:
		var room_id = tile_to_room[room_key]
		if room_id in rooms:
			rooms[room_id].needs_equalization = true

func notify_entities_of_atmosphere_change(coords: Vector2, z_level: int, new_data: Dictionary):
	if not tile_occupancy_system:
		return
	
	var entities = tile_occupancy_system.get_entities_at(coords, z_level)
	for entity in entities:
		if entity and entity.has_method("on_atmosphere_changed"):
			entity.on_atmosphere_changed(new_data)
		
		update_entity_gravity(entity, new_data)

func update_entity_gravity(entity: Node, atmosphere_data: Dictionary):
	if not entity or not atmosphere_data or not "has_gravity" in atmosphere_data:
		return
	
	var zero_g_controller = entity.get_node_or_null("ZeroGController")
	if zero_g_controller:
		if atmosphere_data.has_gravity:
			zero_g_controller.deactivate_zero_g()
		else:
			zero_g_controller.activate_zero_g()

func _on_reaction_occurred(coordinates, reaction_name, intensity):
	var tile_coords = Vector2(coordinates.x, coordinates.y)
	var z_level = coordinates.z
	
	match reaction_name:
		"plasma_combustion":
			handle_plasma_combustion(tile_coords, z_level, intensity)

func handle_plasma_combustion(coords: Vector2, z_level: int, intensity: float):
	var tile = get_tile_data(coords, z_level)
	if tile is Dictionary:
		tile["on_fire"] = true
		tile["light_source"] = intensity * 5.0
		tile["light_color"] = Color(1.0, 0.7, 0.2, 0.7)
	
	if sensory_system:
		var pos = Vector2(coords.x * TILE_SIZE, coords.y * TILE_SIZE)
		sensory_system.emit_sound(pos, z_level, "machinery", intensity, null)

func _on_breach_detected(coordinates):
	var tile_coords = Vector2(coordinates.x, coordinates.y)
	var z_level = coordinates.z
	
	var tile = get_tile_data(tile_coords, z_level)
	if tile is Dictionary:
		tile["breach"] = true
		tile["exposed_to_space"] = true
	
	if sensory_system:
		var pos = Vector2(tile_coords.x * TILE_SIZE, tile_coords.y * TILE_SIZE)
		sensory_system.emit_sound(pos, z_level, "alarm", 1.0, null)

func _on_breach_sealed(coordinates):
	var tile_coords = Vector2(coordinates.x, coordinates.y)
	var z_level = coordinates.z
	
	var tile = get_tile_data(tile_coords, z_level)
	if tile is Dictionary:
		tile["breach"] = false
		tile["exposed_to_space"] = false
