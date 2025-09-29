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

@export_group("World Configuration")
@export var current_z_level: int = 0
@export var z_levels: int = 3
@export var tile_size: int = TILE_SIZE
@export var chunk_size: int = CHUNK_SIZE

@export_group("Atmosphere Settings")
@export var atmosphere_update_interval: float = ATMOSPHERE_UPDATE_INTERVAL
@export var enable_atmosphere_system: bool = true
@export var standard_atmosphere_pressure: float = 101.325
@export var standard_oxygen_ratio: float = 0.21
@export var standard_nitrogen_ratio: float = 0.79

@export_group("Multiplayer Settings")
@export var is_multiplayer_active: bool = false
@export var is_server: bool = false
@export var sync_interval: float = 0.5
@export var auto_detect_multiplayer: bool = true

@export_group("Performance Settings")
@export var enable_chunk_loading: bool = true
@export var enable_spatial_optimization: bool = true
@export var max_entities_per_update: int = 100
@export var entity_update_interval: float = 0.1

@export_group("Generation Settings")
@export var auto_generate_space_tiles: bool = true
@export var space_tile_probability: float = 0.1
@export var auto_detect_rooms: bool = true
@export var room_detection_enabled: bool = true

@export_group("Debug Settings")
@export var debug_mode: bool = false
@export var log_chunk_operations: bool = false
@export var log_entity_operations: bool = false
@export var show_performance_stats: bool = false

signal tile_changed(tile_coords, z_level, old_data, new_data)
signal tile_destroyed(coords, z_level)
signal player_changed_position(position, z_level)
signal object_interacted(tile_coords, z_level, object_type, action)
signal chunks_loaded(chunk_positions, z_level)
signal room_detected(room_id, room_data)
signal atmosphere_initialized(z_level, tile_count)

var world_data = {}
var loaded_chunks = {}
var chunk_entities = {}
var spatial_hash = {}
var rooms = {}
var tile_to_room = {}
var door_collision_data: Dictionary = {}

var atmosphere_step_timer = 0.0
var sync_timer = 0.0
var entity_update_timer = 0.0

var player = null
var local_player = null
var tilemap_visualizer_ref: Node = null
var all_players = []

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

var initialization_step = 0
var initialization_complete = false
var initialization_timer = 0.0
var initialization_frame_budget = 8.0

func _ready():
	set_process(true)
	call_deferred("begin_staged_initialization")

func begin_staged_initialization():
	initialization_step = 0
	initialization_timer = 0.0
	initialization_complete = false

func _process(delta):
	if not initialization_complete:
		initialization_timer += delta
		if initialization_timer >= 0.05:
			process_initialization_step()
			initialization_timer = 0.0
		return
	
	_update_atmosphere(delta)
	_update_multiplayer(delta)
	_update_entities(delta)
	
	if enable_chunk_loading:
		_update_chunk_loading()
	
	if Engine.get_frames_drawn() % 30 == 0:
		_update_players()

func process_initialization_step():
	var step_start_time = Time.get_ticks_msec()
	
	match initialization_step:
		0:
			_setup_multiplayer()
			initialization_step += 1
		1:
			_initialize_world_structure()
			initialization_step += 1
		2:
			_setup_basic_systems()
			initialization_step += 1
		3:
			call_deferred("_load_initial_world_data")
			initialization_step += 1
		4:
			initialization_step += 1
		5:
			_connect_to_door_manager()
			initialization_step += 1
		6:
			if enable_atmosphere_system:
				call_deferred("_initialize_atmosphere_deferred")
			initialization_step += 1
		7:
			call_deferred("_setup_player_deferred")
			initialization_step += 1
		8:
			call_deferred("_finalize_initialization")
			initialization_step += 1
		9:
			initialization_complete = true
	
	var step_time = Time.get_ticks_msec() - step_start_time
	if step_time > initialization_frame_budget:
		print("World: Initialization step ", initialization_step - 1, " took ", step_time, "ms")

func set_tilemap_visualizer(visualizer: Node):
	tilemap_visualizer_ref = visualizer
	print("World: Registered VisualTileMap for Z-level support")

func _setup_multiplayer():
	if auto_detect_multiplayer:
		is_multiplayer_active = (multiplayer && multiplayer.multiplayer_peer != null)
		is_server = (is_multiplayer_active && (multiplayer.is_server() || multiplayer.get_unique_id() == 1))

func _initialize_world_structure():
	for z in range(z_levels):
		world_data[z] = {}

func _setup_basic_systems():
	_setup_threading()
	_connect_player_spawner()
	_connect_atmosphere_system()

func _setup_threading():
	if thread_manager:
		return
	
	thread_manager = ThreadManager.new()
	thread_manager.name = "ThreadManager"
	add_child(thread_manager)
	thread_manager.set_world_reference(self)

func _connect_player_spawner():
	if player_spawner:
		player_spawner.spawned.connect(_on_player_spawned)

func _connect_atmosphere_system():
	if atmosphere_system:
		atmosphere_system.connect("atmosphere_changed", Callable(self, "_on_atmosphere_changed"))
		atmosphere_system.connect("reaction_occurred", Callable(self, "_on_reaction_occurred"))
		atmosphere_system.connect("breach_detected", Callable(self, "_on_breach_detected"))
		atmosphere_system.connect("breach_sealed", Callable(self, "_on_breach_sealed"))
		atmosphere_system.world = self

func _load_initial_world_data():
	await get_tree().process_frame
	
	var registered = await _register_critical_tiles_only()
	_add_z_connections()
	
	if enable_spatial_optimization:
		call_deferred("update_spatial_hash")
	
	if room_detection_enabled:
		call_deferred("detect_rooms_deferred")
	
	call_deferred("_setup_initial_chunks")
	
	if debug_mode:
		print("World: Loaded ", registered, " critical tiles from tilemaps")

func _register_critical_tiles_only() -> int:
	if not floor_tilemap or not wall_tilemap:
		return 0

	var registered_count = 0
	var frame_start_time = Time.get_ticks_msec()
	var processed_tiles = 0
	var max_tiles_per_frame = 50
	
	var floor_cells = floor_tilemap.get_used_cells(0)
	var wall_cells = wall_tilemap.get_used_cells(0)
	
	for cell in floor_cells:
		if processed_tiles >= max_tiles_per_frame:
			await get_tree().process_frame
			processed_tiles = 0
			frame_start_time = Time.get_ticks_msec()
		
		var tile_coords = Vector2i(cell.x, cell.y)
		var tile_data = _ensure_tile_exists(tile_coords, 0)
		
		var floor_type = _determine_floor_type_fast(tile_coords)
		tile_data[TileLayer.FLOOR] = {
			"type": floor_type,
			"collision": false,
			"health": 100,
			"material": floor_type
		}
		registered_count += 1
		processed_tiles += 1
	
	await get_tree().process_frame
	
	for cell in wall_cells:
		if processed_tiles >= max_tiles_per_frame:
			await get_tree().process_frame
			processed_tiles = 0
		
		var tile_coords = Vector2i(cell.x, cell.y)
		var tile_data = _ensure_tile_exists(tile_coords, 0)
		
		tile_data[TileLayer.WALL] = {
			"type": "wall",
			"material": "metal",
			"health": 100
		}
		tile_data["is_walkable"] = false
		registered_count += 1
		processed_tiles += 1
	
	return registered_count

func _determine_floor_type_fast(coords: Vector2i) -> String:
	var atlas_coords = floor_tilemap.get_cell_atlas_coords(0, coords)
	match atlas_coords.y:
		0: return "metal"
		1: return "carpet"
		_: return "floor"

func detect_rooms_deferred():
	await get_tree().process_frame
	await get_tree().process_frame
	
	rooms.clear()
	tile_to_room.clear()
	
	for z in world_data.keys():
		await _detect_rooms_for_z_level_deferred(z)

func _detect_rooms_for_z_level_deferred(z: int):
	if not world_data.has(z):
		return

	var layer = world_data[z]
	if typeof(layer) != TYPE_DICTIONARY:
		return

	var visited = {}
	var room_id = 0
	var processed_tiles = 0
	var max_tiles_per_frame = 30
	
	for coords in layer.keys():
		if processed_tiles >= max_tiles_per_frame:
			await get_tree().process_frame
			processed_tiles = 0
		
		if coords in visited:
			continue
		
		var room_tiles = _flood_fill_room(coords, z, visited)
		if room_tiles.size() > 0:
			_create_room(room_id, room_tiles, z)
			room_id += 1
		
		processed_tiles += 1

func _initialize_atmosphere_deferred():
	if not atmosphere_system:
		return
	
	await get_tree().process_frame
	
	atmosphere_system.active_cells = []
	atmosphere_system.active_count = 0
	
	var standard_atmosphere = _create_standard_atmosphere()
	
	for z in range(min(2, z_levels)):
		await _initialize_z_level_atmosphere_deferred(z, standard_atmosphere)
		await get_tree().process_frame
	
	if auto_generate_space_tiles:
		call_deferred("_initialize_space_tiles_deferred")

func _initialize_z_level_atmosphere_deferred(z: int, standard_atmosphere: Dictionary):
	var tiles_to_init = []
	var processed_tiles = 0
	var max_tiles_per_frame = 20
	
	if z in world_data:
		for coords in world_data[z]:
			if processed_tiles >= max_tiles_per_frame:
				await get_tree().process_frame
				processed_tiles = 0
			
			var tile = world_data[z][coords]
			
			if TileLayer.ATMOSPHERE in tile:
				atmosphere_system.add_active_cell(Vector3(coords.x, coords.y, z))
				continue
			
			if TileLayer.FLOOR in tile:
				tiles_to_init.append(coords)
			
			processed_tiles += 1
	
	if z == 0 and floor_tilemap:
		await _add_tilemap_atmosphere_tiles_deferred(tiles_to_init, z)
	
	processed_tiles = 0
	for coords in tiles_to_init:
		if processed_tiles >= max_tiles_per_frame:
			await get_tree().process_frame
			processed_tiles = 0
		
		add_atmosphere_to_tile(coords, z, standard_atmosphere)
		processed_tiles += 1
	
	emit_signal("atmosphere_initialized", z, tiles_to_init.size())

func _add_tilemap_atmosphere_tiles_deferred(tiles_to_init: Array, z: int):
	var processed_tiles = 0
	var max_tiles_per_frame = 30
	
	for cell in floor_tilemap.get_used_cells(0):
		if processed_tiles >= max_tiles_per_frame:
			await get_tree().process_frame
			processed_tiles = 0
		
		if cell in tiles_to_init:
			continue
		
		if not (z in world_data and cell in world_data[z]):
			add_tile(Vector3(cell.x, cell.y, z))
		
		if not (z in world_data and cell in world_data[z] and TileLayer.ATMOSPHERE in world_data[z][cell]):
			tiles_to_init.append(cell)
		
		processed_tiles += 1

func _initialize_space_tiles_deferred():
	await get_tree().process_frame
	
	var perimeter_tiles = _find_perimeter_tiles_limited()
	
	if is_multiplayer_active and not is_server:
		return
	
	await _generate_space_around_perimeter_deferred(perimeter_tiles)

func _find_perimeter_tiles_limited() -> Array:
	var perimeter_tiles = []
	var max_tiles = 100
	
	if zone_tilemap:
		var zone_tiles = zone_tilemap.get_used_cells(0)
		var processed = 0
		
		for zone_tile in zone_tiles:
			if processed >= max_tiles:
				break
			
			if _is_perimeter_tile(zone_tile):
				perimeter_tiles.append(zone_tile)
			
			processed += 1
	
	return perimeter_tiles

func _generate_space_around_perimeter_deferred(perimeter_tiles: Array):
	var processed_tiles = 0
	var max_tiles_per_frame = 10
	
	for perimeter_tile in perimeter_tiles:
		if processed_tiles >= max_tiles_per_frame:
			await get_tree().process_frame
			processed_tiles = 0
		
		_generate_limited_space_grid_around_tile(perimeter_tile)
		processed_tiles += 1

func _generate_limited_space_grid_around_tile(tile: Vector2i) -> int:
	var space_count = 0
	
	for x in range(-2, 3):
		for y in range(-2, 3):
			var space_tile = Vector2i(tile.x + x, tile.y + y)
			
			if _should_skip_space_tile(space_tile):
				continue
			
			space_count += _create_or_update_space_tile(space_tile)
			
			if space_count >= 5:
				break
		
		if space_count >= 5:
			break
	
	return space_count

func _setup_player_deferred():
	await get_tree().process_frame
	
	if is_multiplayer_active:
		return
	
	create_local_player()

func _finalize_initialization():
	await get_tree().process_frame
	
	if context_interaction_system:
		context_interaction_system.world = self
	
	if enable_chunk_loading:
		call_deferred("_initialize_chunk_culling")

func add_tile(coords: Vector3) -> Dictionary:
	var tile_data = _create_default_tile(coords)
	
	if not coords.z in world_data:
		world_data[coords.z] = {}
	
	var coords_2d = Vector2i(coords.x, coords.y)
	world_data[coords.z][coords_2d] = tile_data
	_add_to_spatial_hash(coords_2d, coords.z)
	
	return tile_data

func update_tile(coords, new_data, z_level = null):
	var level = _get_z_level(coords, z_level)
	var coords_2d = _get_coords_2d(coords)
	
	var old_data = get_tile_data(coords_2d, level)
	if old_data == null:
		old_data = add_tile(Vector3(coords_2d.x, coords_2d.y, level))
	
	if is_multiplayer_active and not is_server:
		network_request_tile_update.rpc_id(1, coords_2d.x, coords_2d.y, level, new_data)
		return old_data
	
	_apply_tile_changes(old_data, new_data)
	emit_signal("tile_changed", coords_2d, level, old_data, new_data)
	
	if is_multiplayer_active and is_server:
		network_update_tile.rpc(coords_2d.x, coords_2d.y, level, new_data)
	
	return old_data

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
	
	_update_tilemap_wall(coords, z_level, not wall_exists)
	
	if is_multiplayer_active and is_server:
		network_wall_toggled.rpc(coords.x, coords.y, z_level, not wall_exists)
	
	return not wall_exists

func get_tile_data(coords, layer = null):
	var z_level = _get_z_level(coords, layer)
	var coords_2d = _get_coords_2d(coords)
	
	if z_level in world_data and coords_2d in world_data[z_level]:
		return world_data[z_level][coords_2d]
	
	return null

func is_valid_tile(tile_coords: Vector2i, z_level = current_z_level) -> bool:
	# First try Z-level specific tilemap if visualizer is available
	if tilemap_visualizer_ref and tilemap_visualizer_ref.has_method("is_valid_tile_at_z_level"):
		return tilemap_visualizer_ref.is_valid_tile_at_z_level(tile_coords, z_level)
	
	# Fallback to original logic
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
	# First try Z-level specific tilemap if visualizer is available
	if tilemap_visualizer_ref and tilemap_visualizer_ref.has_method("is_wall_at_z_level"):
		return tilemap_visualizer_ref.is_wall_at_z_level(tile_coords, z_level)
	
	# Fallback to original logic for backward compatibility
	if wall_tilemap and wall_tilemap.get_cell_source_id(0, tile_coords) != -1:
		return true
	
	var tile_data = get_tile_data(tile_coords, z_level)
	return tile_data is Dictionary and TileLayer.WALL in tile_data and tile_data[TileLayer.WALL] != null

func has_z_level(z_level: int) -> bool:
	if tilemap_visualizer_ref and tilemap_visualizer_ref.has_method("has_z_level"):
		return tilemap_visualizer_ref.has_z_level(z_level)
	
	# Fallback - check if we have world data for this level
	return z_level in world_data

func has_ceiling_at(tile_coords: Vector2i, z_level: int) -> bool:
	# Check if there's a floor on the level above
	var above_z = z_level + 1
	if tilemap_visualizer_ref and tilemap_visualizer_ref.has_method("get_floor_tilemap"):
		var floor_above = tilemap_visualizer_ref.get_floor_tilemap(above_z)
		if floor_above:
			return floor_above.get_cell_source_id(0, tile_coords) != -1
	
	# Check world data
	var tile_above = get_tile_data(tile_coords, above_z)
	return tile_above != null and TileLayer.FLOOR in tile_above

func has_solid_floor_at(tile_coords: Vector2i, z_level: int) -> bool:
	if tilemap_visualizer_ref and tilemap_visualizer_ref.has_method("get_floor_tilemap"):
		var floor_tilemap = tilemap_visualizer_ref.get_floor_tilemap(z_level)
		if floor_tilemap:
			return floor_tilemap.get_cell_source_id(0, tile_coords) != -1
	
	# Check world data
	var tile_data = get_tile_data(tile_coords, z_level)
	return tile_data != null and TileLayer.FLOOR in tile_data

func is_space(tile_coords: Vector2i, z_level: int = current_z_level) -> bool:
	if z_level == 0:
		if zone_tilemap and zone_tilemap.get_cell_source_id(0, tile_coords) == -1:
			return true
		
		if _has_tilemap_data(tile_coords):
			return false
	
	var tile_data = get_tile_data(tile_coords, z_level)
	if tile_data and "is_space" in tile_data:
		return tile_data.is_space
	
	return not (z_level in world_data and tile_coords in world_data[z_level])

func is_in_zone(tile_coords: Vector2i, z_level: int = current_z_level) -> bool:
	return z_level == 0 and zone_tilemap and zone_tilemap.get_cell_source_id(0, tile_coords) != -1

func is_tile_blocked(coords, z_level = current_z_level):
	var tile_coords = _get_coords_2d(coords)
	
	if is_wall_at(tile_coords, z_level):
		return true
	
	if tile_occupancy_system:
		return tile_occupancy_system.has_dense_entity_at(tile_coords, z_level)
	
	var tile = get_tile_data(tile_coords, z_level)
	return _has_blocking_contents(tile)

func get_tile_at(world_position: Vector2, z_level = current_z_level) -> Vector2i:
	var tile_x = floor(world_position.x / tile_size)
	var tile_y = floor(world_position.y / tile_size)
	return Vector2i(tile_x, tile_y)

func tile_to_world(tile_pos: Vector2) -> Vector2:
	return Vector2(
		(tile_pos.x * tile_size) + (tile_size / 2.0), 
		(tile_pos.y * tile_size) + (tile_size / 2.0)
	)

func get_entities_at_tile(tile_coords, z_level):
	if tile_occupancy_system:
		return tile_occupancy_system.get_entities_at(tile_coords, z_level)
	
	var tile = get_tile_data(tile_coords, z_level)
	return tile.get("contents", []) if tile else []

func get_entities_in_radius(center: Vector2, radius: float, z_level = current_z_level) -> Array:
	if spatial_manager:
		return spatial_manager.get_entities_near(center, radius, z_level)
	
	if tile_occupancy_system:
		return _get_entities_from_occupancy_system(center, radius, z_level)
	
	return _get_entities_from_world_data(center, radius, z_level)

func get_entities_at_world_pos(world_pos: Vector2, z_level: int = 0, radius: float = 5.0) -> Array:
	return get_entities_in_radius(world_pos, radius, z_level)

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

func load_chunks_around(world_position: Vector2, z_level: int = current_z_level, radius: int = 2):
	var culling_system = get_node_or_null("ChunkCullingSystem")
	if culling_system:
		culling_system._update_all_chunk_visibility()
	
	return loaded_chunks

func load_chunk(chunk_pos: Vector2i, z_level: int):
	var chunk_bounds = _calculate_chunk_bounds(chunk_pos)
	var is_station_chunk = _check_if_station_chunk(chunk_pos, z_level)
	
	if z_level == 0:
		_generate_chunk_tiles(chunk_bounds, is_station_chunk, z_level)
	
	load_chunk_entities(chunk_pos, z_level, is_station_chunk)

func load_chunk_entities(chunk_pos: Vector2i, z_level: int, is_station_chunk: bool = false):
	var chunk_key = _get_chunk_key(chunk_pos, z_level)
	
	if chunk_key in chunk_entities:
		return
	
	chunk_entities[chunk_key] = []
	
	if not is_station_chunk and z_level == 0:
		_generate_chunk_entities(chunk_pos, z_level)

func unload_chunk_entities(chunk_pos: Vector2i, z_level: int):
	var chunk_key = _get_chunk_key(chunk_pos, z_level)
	
	if not chunk_key in chunk_entities:
		return
	
	for entity in chunk_entities[chunk_key]:
		_remove_entity_from_systems(entity)
	
	chunk_entities.erase(chunk_key)

func get_room_at_tile(tile_coords: Vector2i, z_level: int) -> Dictionary:
	var room_key = Vector3(tile_coords.x, tile_coords.y, z_level)
	if room_key in tile_to_room:
		var room_id = tile_to_room[room_key]
		if room_id in rooms:
			return rooms[room_id]
	
	return {}

func create_local_player():
	local_player = get_node_or_null("GridMovementController")
	
	if not local_player:
		local_player = _create_player_node()
		add_child(local_player)
	
	_setup_player_controller()
	_connect_player_signals(local_player)
	_register_player_with_systems(local_player)

func find_spawn_position() -> Vector2:
	var spawn_pos = Vector2(5 * tile_size, 5 * tile_size)
	
	if zone_tilemap:
		var cells = zone_tilemap.get_used_cells(0)
		if cells.size() > 0:
			spawn_pos = _calculate_center_position(cells)
	
	return spawn_pos

func create_standard_atmosphere() -> Dictionary:
	return {
		atmosphere_system.GAS_TYPE_OXYGEN: standard_atmosphere_pressure * standard_oxygen_ratio,
		atmosphere_system.GAS_TYPE_NITROGEN: standard_atmosphere_pressure * standard_nitrogen_ratio,
		"temperature": atmosphere_system.T20C
	}

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
		var atmosphere = _determine_tile_atmosphere(tile, standard_atmosphere)
		tile[TileLayer.ATMOSPHERE] = atmosphere
		atmosphere_system.add_active_cell(Vector3(coords.x, coords.y, z))
	else:
		push_error("Tile at %s is not a Dictionary: %s" % [coords, typeof(tile)])

func get_nearby_tiles(center: Vector2, radius: float, z_level = current_z_level) -> Array:
	var cell_bounds = _calculate_search_bounds(center, radius)
	var result = []
	
	for cell_x in range(cell_bounds.start_x, cell_bounds.end_x + 1):
		for cell_y in range(cell_bounds.start_y, cell_bounds.end_y + 1):
			var cell_key = Vector3(cell_x, cell_y, z_level)
			
			if cell_key in spatial_hash:
				result.append_array(_filter_tiles_by_distance(spatial_hash[cell_key], center, radius))
	
	return result

func update_spatial_hash():
	if not enable_spatial_optimization:
		return
		
	await get_tree().process_frame
	
	spatial_hash.clear()
	var processed_tiles = 0
	var max_tiles_per_frame = 100
	
	for z in world_data.keys():
		for coords in world_data[z].keys():
			if processed_tiles >= max_tiles_per_frame:
				await get_tree().process_frame
				processed_tiles = 0
			
			_add_to_spatial_hash(coords, z)
			processed_tiles += 1

func _connect_to_door_manager():
	var door_manager = get_node_or_null("/root/DoorManager")
	if door_manager:
		door_manager.door_registered.connect(_on_door_registered)
		door_manager.door_unregistered.connect(_on_door_unregistered)

func _on_door_registered(door: Door):
	if not door:
		return
	
	var collision_component = door.get_node_or_null("DoorCollisionComponent")
	if collision_component:
		collision_component.collision_state_changed.connect(_on_door_collision_changed.bind(door))
		collision_component.collision_tiles_updated.connect(_on_door_tiles_updated.bind(door))
		
		_register_door_tiles(door)

func _on_door_unregistered(door: Door):
	if not door:
		return
	
	_unregister_door_tiles(door)

func _on_door_collision_changed(door: Door, active: bool):
	_update_door_collision_data(door)

func _on_door_tiles_updated(door: Door, tiles: Array[Vector2i]):
	_update_door_collision_data(door)

func _register_door_tiles(door: Door):
	var collision_component = door.get_node_or_null("DoorCollisionComponent")
	if not collision_component:
		return
	
	var z_level = door.current_z_level
	if not z_level in door_collision_data:
		door_collision_data[z_level] = {}
	
	for tile_pos in collision_component.get_collision_tiles():
		if not tile_pos in door_collision_data[z_level]:
			door_collision_data[z_level][tile_pos] = []
		
		if door not in door_collision_data[z_level][tile_pos]:
			door_collision_data[z_level][tile_pos].append(door)

func _unregister_door_tiles(door: Door):
	for z_level in door_collision_data.keys():
		for tile_pos in door_collision_data[z_level].keys():
			door_collision_data[z_level][tile_pos].erase(door)
			
			if door_collision_data[z_level][tile_pos].is_empty():
				door_collision_data[z_level].erase(tile_pos)

func _update_door_collision_data(door: Door):
	_unregister_door_tiles(door)
	_register_door_tiles(door)

func is_door_blocking_tile(tile_pos: Vector2i, z_level: int, entity: Node = null) -> bool:
	if not z_level in door_collision_data:
		return false
	
	if not tile_pos in door_collision_data[z_level]:
		return false
	
	for door in door_collision_data[z_level][tile_pos]:
		if not is_instance_valid(door):
			continue
		
		var collision_component = door.get_node_or_null("DoorCollisionComponent")
		if not collision_component:
			continue
		
		if collision_component.blocks_tile(tile_pos):
			if entity and collision_component.can_entity_pass(entity, tile_pos):
				continue
			
			return true
	
	return false

func get_door_at_tile(tile_pos: Vector2i, z_level: int) -> Door:
	if not z_level in door_collision_data:
		return null
	
	if not tile_pos in door_collision_data[z_level]:
		return null
	
	for door in door_collision_data[z_level][tile_pos]:
		if is_instance_valid(door):
			return door
	
	return null

func get_all_doors_at_tile(tile_pos: Vector2i, z_level: int) -> Array[Door]:
	if not z_level in door_collision_data:
		return []
	
	if not tile_pos in door_collision_data[z_level]:
		return []
	
	var valid_doors: Array[Door] = []
	for door in door_collision_data[z_level][tile_pos]:
		if is_instance_valid(door):
			valid_doors.append(door)
	
	return valid_doors

func can_entity_move_to_tile(entity: Node, tile_pos: Vector2i, z_level: int) -> bool:
	if not z_level in door_collision_data:
		return true
	
	if not tile_pos in door_collision_data[z_level]:
		return true
	
	for door in door_collision_data[z_level][tile_pos]:
		if not is_instance_valid(door):
			continue
		
		var collision_component = door.get_node_or_null("DoorCollisionComponent")
		if not collision_component:
			continue
		
		if not collision_component.can_entity_pass(entity, tile_pos):
			return false
	
	return true

func get_door_collision_info(tile_pos: Vector2i, z_level: int) -> Dictionary:
	var info = {
		"has_doors": false,
		"doors": [],
		"blocked": false,
		"can_auto_open": false
	}
	
	var doors = get_all_doors_at_tile(tile_pos, z_level)
	if doors.is_empty():
		return info
	
	info.has_doors = true
	info.doors = doors
	
	for door in doors:
		var collision_component = door.get_node_or_null("DoorCollisionComponent")
		if collision_component and collision_component.is_collision_active():
			info.blocked = true
			
			if door.current_door_state == Door.DoorState.CLOSED and not door.locked:
				info.can_auto_open = true
	
	return info

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

func is_airtight_barrier(tile1_coords, tile2_coords, z_level):
	var tile1 = get_tile_data(tile1_coords, z_level)
	var tile2 = get_tile_data(tile2_coords, z_level)
	
	if not tile1 or not tile2:
		return true
	
	return (_has_wall_layer(tile1) or _has_wall_layer(tile2))

func _update_atmosphere(delta: float):
	if not enable_atmosphere_system or not initialization_complete:
		return
		
	atmosphere_step_timer += delta
	if atmosphere_step_timer >= atmosphere_update_interval:
		atmosphere_step_timer = 0.0
		if atmosphere_system:
			atmosphere_system.process_atmosphere_step()

func _update_multiplayer(delta: float):
	if not is_multiplayer_active:
		return
	
	sync_timer += delta
	if sync_timer >= sync_interval:
		sync_timer = 0.0

func _update_entities(delta: float):
	if not initialization_complete:
		return
	
	entity_update_timer += delta
	if entity_update_timer >= entity_update_interval:
		entity_update_timer = 0.0
		_process_entity_updates()

func _update_chunk_loading():
	if is_server and initialization_complete:
		_load_chunks_for_all_players()

func _update_players():
	if not initialization_complete:
		return
	
	_track_all_players()
	_update_player_states()

func _get_z_level(coords, z_level):
	if coords is Vector3:
		return coords.z
	return current_z_level if z_level == null else z_level

func _get_coords_2d(coords):
	if coords is Vector3:
		return Vector2i(coords.x, coords.y)
	elif coords is Vector2:
		return Vector2i(coords.x, coords.y)
	elif coords is Vector2i:
		return coords
	else:
		return Vector2i(0, 0)

func _apply_tile_changes(old_data: Dictionary, new_data: Dictionary):
	for key in new_data.keys():
		old_data[key] = new_data[key]

func _create_default_tile(coords: Vector3) -> Dictionary:
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
		"tile_position": Vector2(coords.x * tile_size, coords.y * tile_size),
		"radiation": 0.0,
		"light_level": 5.0,
		"damages": [],
		"has_gravity": true
	}

func _create_standard_atmosphere() -> Dictionary:
	return {
		atmosphere_system.GAS_TYPE_OXYGEN: standard_atmosphere_pressure * standard_oxygen_ratio,
		atmosphere_system.GAS_TYPE_NITROGEN: standard_atmosphere_pressure * standard_nitrogen_ratio,
		"temperature": atmosphere_system.T20C
	}

func _ensure_tile_exists(coords: Vector2i, z_level: int) -> Dictionary:
	var tile_data = get_tile_data(coords, z_level)
	if not tile_data:
		tile_data = add_tile(Vector3(coords.x, coords.y, z_level))
	return tile_data

func _update_tilemap_wall(coords: Vector2i, z_level: int, wall_exists: bool):
	if wall_tilemap and z_level == 0:
		if wall_exists:
			wall_tilemap.set_cell(0, coords, 0, Vector2i(0, 0))
		else:
			wall_tilemap.set_cell(0, coords, -1)

func _determine_tile_atmosphere(tile: Dictionary, standard_atmosphere: Dictionary) -> Dictionary:
	if "tile_type" in tile:
		match tile.tile_type:
			"space":
				return _create_space_atmosphere()
			"exterior":
				return _create_exterior_atmosphere(standard_atmosphere)
	
	if TileLayer.FLOOR in tile and "type" in tile[TileLayer.FLOOR]:
		if tile[TileLayer.FLOOR].type == "exterior":
			return _create_exterior_atmosphere(standard_atmosphere)
	
	return standard_atmosphere.duplicate()

func _create_space_atmosphere() -> Dictionary:
	return {
		atmosphere_system.GAS_TYPE_OXYGEN: 0.2,
		atmosphere_system.GAS_TYPE_NITROGEN: 0.5,
		"temperature": 3.0
	}

func _create_exterior_atmosphere(base_atmosphere: Dictionary) -> Dictionary:
	var exterior = base_atmosphere.duplicate()
	for gas_type in exterior:
		if gas_type != "temperature":
			exterior[gas_type] *= 0.7
	exterior["temperature"] = 273.15
	return exterior

func _add_z_connections():
	var connection_points = [
		Vector2(10, 10),
		Vector2(30, 30),
		Vector2(20, 5)
	]
	
	for point in connection_points:
		_create_z_connections_at_point(point)

func _create_z_connections_at_point(point: Vector2):
	for z in range(z_levels - 1):
		var lower_tile = get_tile_data(Vector3(point.x, point.y, z))
		var upper_tile = get_tile_data(Vector3(point.x, point.y, z + 1))
		
		if lower_tile and upper_tile:
			_create_bidirectional_z_connection(point, z, lower_tile, upper_tile)

func _create_bidirectional_z_connection(point: Vector2, z: int, lower_tile: Dictionary, upper_tile: Dictionary):
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

func _flood_fill_room(start_coord: Vector2i, z_level: int, visited: Dictionary) -> Array:
	var room_tiles = []
	var to_visit = [start_coord]
	
	while to_visit.size() > 0:
		var current = to_visit.pop_front()
		
		if current in visited:
			continue
		
		visited[current] = true
		room_tiles.append(current)
		
		_add_adjacent_tiles_to_visit(current, z_level, visited, to_visit)
	
	return room_tiles

func _add_adjacent_tiles_to_visit(current: Vector2i, z_level: int, visited: Dictionary, to_visit: Array):
	for neighbor in get_adjacent_tiles(current, z_level):
		if neighbor in visited:
			continue
		
		if not is_airtight_barrier(current, neighbor, z_level):
			to_visit.append(neighbor)

func _create_room(room_id: int, room_tiles: Array, z_level: int):
	rooms[room_id] = {
		"tiles": room_tiles,
		"z_level": z_level,
		"volume": room_tiles.size(),
		"atmosphere": _calculate_room_atmosphere(room_tiles, z_level),
		"connections": _detect_room_connections(room_tiles, z_level),
		"needs_equalization": false
	}
	
	for tile in room_tiles:
		tile_to_room[Vector3(tile.x, tile.y, z_level)] = room_id
	
	emit_signal("room_detected", room_id, rooms[room_id])

func _calculate_room_atmosphere(tiles, z_level):
	var total_gases = {}
	var total_energy = 0.0
	var tile_count = 0
	
	for tile_coords in tiles:
		var tile = get_tile_data(tile_coords, z_level)
		if tile is Dictionary or not TileLayer.ATMOSPHERE in tile:
			continue
		
		var atmo = tile[TileLayer.ATMOSPHERE]
		_accumulate_gas_data(atmo, total_gases)
		
		if "temperature" in atmo:
			total_energy += atmo.temperature
		
		tile_count += 1
	
	return _calculate_average_atmosphere(total_gases, total_energy, tile_count)

func _accumulate_gas_data(atmo: Dictionary, total_gases: Dictionary):
	for gas_key in atmo.keys():
		if gas_key != "temperature" and gas_key != "pressure" and typeof(atmo[gas_key]) == TYPE_FLOAT:
			if not gas_key in total_gases:
				total_gases[gas_key] = 0.0
			total_gases[gas_key] += atmo[gas_key]

func _calculate_average_atmosphere(total_gases: Dictionary, total_energy: float, tile_count: int) -> Dictionary:
	var result = {}
	
	if tile_count > 0:
		for gas_key in total_gases.keys():
			result[gas_key] = total_gases[gas_key] / tile_count
		
		if total_energy > 0:
			result["temperature"] = total_energy / tile_count
		
		result["pressure"] = _calculate_total_pressure(result)
	else:
		result = _create_default_atmosphere()
	
	return result

func _calculate_total_pressure(atmosphere: Dictionary) -> float:
	var total_pressure = 0.0
	for gas_key in atmosphere.keys():
		if gas_key != "temperature" and gas_key != "pressure":
			total_pressure += atmosphere[gas_key]
	return total_pressure

func _create_default_atmosphere() -> Dictionary:
	return {
		"oxygen": 0.0,
		"nitrogen": 0.0,
		"co2": 0.0,
		"temperature": 293.15,
		"pressure": 0.0
	}

func _detect_room_connections(room_tiles, z_level):
	var connections = []

	for tile_coords in room_tiles:
		var tile = get_tile_data(tile_coords, z_level)
		if not tile:
			continue

		connections.append_array(_find_tile_connections(tile, tile_coords))

	return connections

func _find_tile_connections(tile: Dictionary, tile_coords: Vector2i) -> Array:
	var connections = []
	
	if TileLayer.PIPE in tile:
		var pipe_connection = _create_pipe_connection(tile, tile_coords)
		if pipe_connection:
			connections.append(pipe_connection)
	
	if "z_connection" in tile:
		var z_connection = _create_z_connection(tile, tile_coords)
		if z_connection:
			connections.append(z_connection)
	
	return connections

func _create_pipe_connection(tile: Dictionary, tile_coords: Vector2i):
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

func _create_z_connection(tile: Dictionary, tile_coords: Vector2i):
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

func _add_to_spatial_hash(coords: Vector2, z_level = current_z_level):
	if not enable_spatial_optimization:
		return
		
	var cell_x = floor(coords.x / SPATIAL_CELL_SIZE)
	var cell_y = floor(coords.y / SPATIAL_CELL_SIZE)
	var cell_key = Vector3(cell_x, cell_y, z_level)
	
	if not cell_key in spatial_hash:
		spatial_hash[cell_key] = []
		
	if not coords in spatial_hash[cell_key]:
		spatial_hash[cell_key].append(coords)

func _calculate_search_bounds(center: Vector2, radius: float) -> Dictionary:
	return {
		"start_x": floor((center.x - radius) / SPATIAL_CELL_SIZE),
		"start_y": floor((center.y - radius) / SPATIAL_CELL_SIZE),
		"end_x": floor((center.x + radius) / SPATIAL_CELL_SIZE),
		"end_y": floor((center.y + radius) / SPATIAL_CELL_SIZE)
	}

func _filter_tiles_by_distance(tiles: Array, center: Vector2, radius: float) -> Array:
	var filtered = []
	
	for tile_coords in tiles:
		var tile_world_pos = Vector2(tile_coords.x * tile_size, tile_coords.y * tile_size)
		var distance = center.distance_to(tile_world_pos)
		
		if distance <= radius:
			filtered.append(tile_coords)
	
	return filtered

func _get_entities_from_occupancy_system(center: Vector2, radius: float, z_level: int) -> Array:
	var entities = []
	var tile_radius = ceil(radius / tile_size)
	var center_tile = get_tile_at(center)
	
	for x in range(-tile_radius, tile_radius + 1):
		for y in range(-tile_radius, tile_radius + 1):
			var check_tile = Vector2i(center_tile.x + x, center_tile.y + y)
			var tile_entities = tile_occupancy_system.get_entities_at(check_tile, z_level)
			
			entities.append_array(_filter_entities_by_distance(tile_entities, center, radius))
	
	return _remove_duplicate_entities(entities)

func _filter_entities_by_distance(entities: Array, center: Vector2, radius: float) -> Array:
	var filtered = []
	
	for entity in entities:
		if "position" in entity:
			var distance = center.distance_to(entity.position)
			if distance <= radius:
				filtered.append(entity)
	
	return filtered

func _remove_duplicate_entities(entities: Array) -> Array:
	var unique_entities = []
	for entity in entities:
		if not entity in unique_entities:
			unique_entities.append(entity)
	return unique_entities

func _get_entities_from_world_data(center: Vector2, radius: float, z_level: int) -> Array:
	var nearby_tiles = get_nearby_tiles(center, radius, z_level)
	var entities = []
	
	for tile_coords in nearby_tiles:
		var tile = get_tile_data(tile_coords, z_level)
		if tile and "contents" in tile:
			entities.append_array(tile.contents)
	
	return _remove_duplicate_entities(entities)

func _has_tilemap_data(coords: Vector2i) -> bool:
	if floor_tilemap and floor_tilemap.get_cell_source_id(0, coords) != -1:
		return true
	
	if wall_tilemap and wall_tilemap.get_cell_source_id(0, coords) != -1:
		return true
	
	var objects_tilemap = get_node_or_null("VisualTileMap/ObjectsTileMap")
	if objects_tilemap and objects_tilemap.get_cell_source_id(0, coords) != -1:
		return true
	
	return false

func _has_blocking_contents(tile: Dictionary) -> bool:
	if not tile or not "contents" in tile:
		return false
	
	for entity in tile.contents:
		if "blocks_movement" in entity and entity.blocks_movement:
			return true
	
	return false

func _has_wall_layer(tile: Dictionary) -> bool:
	return TileLayer.WALL in tile and tile[TileLayer.WALL] != null

func _setup_initial_chunks():
	var spawn_pos = find_spawn_position()
	
	if is_server:
		load_chunks_around(spawn_pos, 0, 2)

func _initialize_chunk_culling():
	await get_tree().process_frame
	
	var culling_system = ChunkCullingSystem.new()
	culling_system.name = "ChunkCullingSystem"
	add_child(culling_system)
	
	_setup_culling_optimization(culling_system)
	connect("player_changed_position", Callable(self, "_on_player_position_changed_culling"))
	
	return culling_system

func _setup_culling_optimization(culling_system: Node):
	var optimization_manager = get_node_or_null("/root/OptimizationManager")
	if optimization_manager:
		culling_system.occlusion_enabled = optimization_manager.settings.occlusion_culling
		optimization_manager.connect("settings_changed", Callable(self, "_on_optimization_settings_changed"))

func _is_perimeter_tile(tile: Vector2i) -> bool:
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

func _should_skip_space_tile(coords: Vector2i) -> bool:
	if zone_tilemap and zone_tilemap.get_cell_source_id(0, coords) != -1:
		return true
	
	if floor_tilemap and floor_tilemap.get_cell_source_id(0, coords) != -1:
		return true
	
	if wall_tilemap and wall_tilemap.get_cell_source_id(0, coords) != -1:
		return true
	
	return false

func _create_or_update_space_tile(coords: Vector2i) -> int:
	var tile_data = get_tile_data(coords, 0)
	
	if not tile_data:
		_create_space_tile(coords, 0)
		return 1
	elif not TileLayer.ATMOSPHERE in tile_data:
		_add_space_atmosphere_to_tile(tile_data)
		return 1
	
	_update_tile_space_properties(tile_data)
	return 0

func _create_space_tile(coords: Vector2i, z_level: int):
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
		"tile_position": Vector2(coords.x * tile_size, coords.y * tile_size)
	}
	
	if randf() < 0.02:
		tile_data["space_object"] = {
			"type": "asteroid",
			"size": randf_range(0.5, 2.0)
		}
	
	if not z_level in world_data:
		world_data[z_level] = {}
	
	world_data[z_level][coords] = tile_data
	_add_to_spatial_hash(coords, z_level)
	
	return tile_data

func _add_space_atmosphere_to_tile(tile_data: Dictionary):
	tile_data[TileLayer.ATMOSPHERE] = {
		atmosphere_system.GAS_TYPE_OXYGEN: 0.0,
		atmosphere_system.GAS_TYPE_NITROGEN: 0.0,
		"temperature": 2.7,
		"pressure": 0.0,
		"has_gravity": false
	}

func _update_tile_space_properties(tile_data: Dictionary):
	tile_data["is_space"] = true
	tile_data["has_gravity"] = false

func _calculate_chunk_bounds(chunk_pos: Vector2i) -> Dictionary:
	return {
		"start_x": chunk_pos.x * chunk_size,
		"start_y": chunk_pos.y * chunk_size,
		"end_x": chunk_pos.x * chunk_size + chunk_size - 1,
		"end_y": chunk_pos.y * chunk_size + chunk_size - 1
	}

func _check_if_station_chunk(chunk_pos: Vector2i, z_level: int) -> bool:
	if z_level != 0 or not zone_tilemap:
		return false
	
	var bounds = _calculate_chunk_bounds(chunk_pos)
	
	for x in range(bounds.start_x, bounds.end_x + 1, 4):
		for y in range(bounds.start_y, bounds.end_y + 1, 4):
			if zone_tilemap.get_cell_source_id(0, Vector2i(x, y)) != -1:
				return true
	
	return false

func _generate_chunk_tiles(bounds: Dictionary, is_station_chunk: bool, z_level: int):
	for x in range(bounds.start_x, bounds.end_x + 1):
		for y in range(bounds.start_y, bounds.end_y + 1):
			var tile_coords = Vector2i(x, y)
			
			if _has_existing_tile(tile_coords, z_level):
				continue
			
			if _should_generate_tile(tile_coords, bounds, is_station_chunk):
				if not get_tile_data(tile_coords, z_level):
					add_tile(Vector3(x, y, z_level))
			elif _should_create_space_tile(tile_coords, bounds, is_station_chunk):
				_create_space_tile(tile_coords, z_level)

func _has_existing_tile(coords: Vector2i, z_level: int) -> bool:
	var has_floor = floor_tilemap and floor_tilemap.get_cell_source_id(0, coords) != -1
	var has_wall = wall_tilemap and wall_tilemap.get_cell_source_id(0, coords) != -1
	return has_floor or has_wall

func _should_generate_tile(coords: Vector2i, bounds: Dictionary, is_station_chunk: bool) -> bool:
	return _has_existing_tile(coords, 0)

func _should_create_space_tile(tile_coords: Vector2i, bounds: Dictionary, is_station_chunk: bool) -> bool:
	if is_station_chunk:
		return false
	
	var is_edge = (tile_coords.x == bounds.start_x or tile_coords.x == bounds.end_x or 
				   tile_coords.y == bounds.start_y or tile_coords.y == bounds.end_y)
	
	return is_edge and randf() < space_tile_probability

func _get_chunk_key(chunk_pos: Vector2i, z_level: int) -> String:
	return str(chunk_pos.x) + "_" + str(chunk_pos.y) + "_" + str(z_level)

func _generate_chunk_entities(chunk_pos: Vector2i, z_level: int):
	var entity_count = randi() % 4
	
	for i in range(entity_count):
		var x = chunk_pos.x * chunk_size + randi() % chunk_size
		var y = chunk_pos.y * chunk_size + randi() % chunk_size
		var tile_coords = Vector2i(x, y)
		
		if is_valid_tile(tile_coords, z_level):
			continue

func _remove_entity_from_systems(entity: Node):
	if not entity or not is_instance_valid(entity):
		return
	
	if spatial_manager:
		spatial_manager.unregister_entity(entity)
	
	if tile_occupancy_system and "position" in entity:
		var entity_tile = Vector2i(
			floor(entity.position.x / tile_size),
			floor(entity.position.y / tile_size)
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

func _load_chunks_for_all_players():
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

func _track_all_players():
	var new_players = get_tree().get_nodes_in_group("player_controller")
	all_players = new_players
	
	for player in all_players:
		if player:
			_update_player_tracking(player)

func _update_player_tracking(player: Node):
	var grid_controller = player
	
	check_entity_void_status(
		player, 
		grid_controller.movement_component.current_tile_position, 
		grid_controller.current_z_level
	)
	
	if local_player == null and player.has_method("is_local_player") and player.is_local_player():
		local_player = player

func _update_player_states():
	pass

func _process_entity_updates():
	pass

func _create_player_node() -> Node2D:
	var player_node = Node2D.new()
	player_node.name = "Player"
	player_node.position = Vector2(tile_size * 5, tile_size * 5)
	return player_node

func _setup_player_controller():
	var grid_controller = local_player.get_parent()
	
	if not grid_controller:
		grid_controller = _create_grid_controller()
		local_player.add_child(grid_controller)

func _create_grid_controller() -> GridMovementController:
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

func _connect_player_signals(player_node):
	var grid_controller = player_node.get_node_or_null("GridMovementController")
	if not grid_controller:
		return
	
	_connect_signal_safe(grid_controller, "tile_changed", "_on_player_tile_changed")
	_connect_signal_safe(grid_controller, "state_changed", "_on_player_state_changed")
	
	if interaction_system and grid_controller.has_signal("interaction_requested"):
		var callable = Callable(interaction_system, "handle_use")
		if not grid_controller.is_connected("interaction_requested", callable):
			grid_controller.connect("interaction_requested", callable)
	
	if collision_resolver and grid_controller.has_signal("bump"):
		var callable = Callable(collision_resolver, "resolve_collision")
		if not grid_controller.is_connected("bump", callable):
			grid_controller.connect("bump", callable)

func _connect_signal_safe(source: Node, signal_name: String, method_name: String):
	if not source or not source.has_signal(signal_name):
		return
	
	var callable = Callable(self, method_name)
	if not source.is_connected(signal_name, callable):
		source.connect(signal_name, callable)

func _register_player_with_systems(player_node):
	var grid_controller = player_node.get_node_or_null("GridMovementController")
	if not grid_controller:
		return
	
	_register_with_sensory_system(grid_controller)
	_register_with_spatial_manager(grid_controller)
	_register_with_tile_occupancy(grid_controller)

func _register_with_sensory_system(grid_controller):
	if sensory_system:
		sensory_system.register_entity(grid_controller)

func _register_with_spatial_manager(grid_controller):
	if spatial_manager:
		spatial_manager.register_entity(grid_controller)

func _register_with_tile_occupancy(grid_controller):
	if tile_occupancy_system:
		var tile_pos = grid_controller.current_tile_position
		var z_level = grid_controller.current_z_level
		tile_occupancy_system.register_entity_at_tile(grid_controller, tile_pos, z_level)

func _calculate_center_position(cells: Array) -> Vector2:
	var sum_x = 0
	var sum_y = 0
	
	for cell in cells:
		sum_x += cell.x
		sum_y += cell.y
	
	return Vector2(
		(sum_x / cells.size()) * tile_size,
		(sum_y / cells.size()) * tile_size
	)

@rpc("authority", "call_remote", "reliable")
func network_sync_chunks(chunk_positions, z_level):
	if is_server:
		return
	
	for chunk_pos in chunk_positions:
		_queue_chunk_for_loading(chunk_pos, z_level)

func _queue_chunk_for_loading(chunk_pos: Vector2i, z_level: int):
	var chunk_key = _get_chunk_key(chunk_pos, z_level)
	
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
	
	_apply_tile_changes(old_data, new_data)
	emit_signal("tile_changed", coords_2d, z_level, old_data, new_data)

@rpc("any_peer", "call_local", "reliable")
func network_request_tile_update(x, y, z_level, new_data):
	if not is_server:
		return
	
	var coords_2d = Vector2i(x, y)
	update_tile(coords_2d, new_data, z_level)

@rpc("authority", "call_remote", "reliable")
func network_wall_toggled(x, y, z_level, wall_exists):
	if is_server:
		return
	
	_apply_wall_toggle_result(Vector2i(x, y), z_level, wall_exists)

func _apply_wall_toggle_result(coords: Vector2i, z_level: int, wall_exists: bool):
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
		_update_tilemap_wall(coords, z_level, wall_exists)

@rpc("any_peer", "call_local", "reliable")
func network_request_wall_toggle(x, y, z_level):
	if is_server:
		toggle_wall_at(Vector2i(x, y), z_level)

func _on_player_spawned(node):
	if node.is_in_group("player_controller"):
		var is_local_player = _determine_if_local_player(node)
		_configure_player_systems(node, is_local_player)
		_register_spawned_player_with_systems(node, is_local_player)
		
		if is_local_player:
			local_player = node

func _determine_if_local_player(player: Node) -> bool:
	if player.has_node("MultiplayerSynchronizer"):
		var sync = player.get_node("MultiplayerSynchronizer")
		return sync.get_multiplayer_authority() == multiplayer.get_unique_id()
	return false

func _configure_player_systems(player: Node, is_local: bool):
	_configure_player_camera(player, is_local)
	_configure_player_ui(player, is_local)
	_configure_player_input(player, is_local)
	
	if player.has_method("set_local_player"):
		player.set_local_player(is_local)

func _configure_player_camera(player: Node, is_local: bool):
	var camera = player.get_node_or_null("Camera2D")
	if camera:
		camera.enabled = is_local

func _configure_player_ui(player: Node, is_local: bool):
	var ui = player.get_node_or_null("PlayerUI")
	if ui:
		ui.visible = is_local

func _configure_player_input(player: Node, is_local: bool):
	var input_controller = player.get_node_or_null("InputController")
	if input_controller:
		input_controller.set_process_input(is_local)
		input_controller.set_process_unhandled_input(is_local)

func _register_spawned_player_with_systems(player: Node, is_local: bool):
	_register_with_click_handlers(player, is_local)
	_register_with_interaction_systems(player)
	_register_with_tile_occupancy_if_available(player)

func _register_with_click_handlers(player: Node, is_local: bool):
	if not is_local:
		return
	
	var click_handlers = get_tree().get_nodes_in_group("click_system")
	for handler in click_handlers:
		if handler.has_method("set_player_reference"):
			handler.set_player_reference(player)

func _register_with_interaction_systems(player: Node):
	var interaction_systems = get_tree().get_nodes_in_group("interaction_system")
	for system in interaction_systems:
		if system.has_method("register_player"):
			system.register_player(player, false)

func _register_with_tile_occupancy_if_available(player: Node):
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
	
	_handle_player_state_sounds(old_state, new_state, grid_controller)

func _handle_player_state_sounds(old_state: int, new_state: int, grid_controller: Node):
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
	
	_update_tile_atmosphere(tile_coords, z_level, new_data)
	_update_room_atmosphere(tile_coords, z_level)
	_notify_entities_of_atmosphere_change(tile_coords, z_level, new_data)

func _update_tile_atmosphere(coords: Vector2, z_level: int, new_data: Dictionary):
	var tile = get_tile_data(coords, z_level)
	if tile is Dictionary:
		tile[TileLayer.ATMOSPHERE] = new_data

func _update_room_atmosphere(coords: Vector2, z_level: int):
	var room_key = Vector3(coords.x, coords.y, z_level)
	if room_key in tile_to_room:
		var room_id = tile_to_room[room_key]
		if room_id in rooms:
			rooms[room_id].needs_equalization = true

func _notify_entities_of_atmosphere_change(coords: Vector2, z_level: int, new_data: Dictionary):
	if not tile_occupancy_system:
		return
	
	var entities = tile_occupancy_system.get_entities_at(coords, z_level)
	for entity in entities:
		if entity and entity.has_method("on_atmosphere_changed"):
			entity.on_atmosphere_changed(new_data)
		
		_update_entity_gravity(entity, new_data)

func _update_entity_gravity(entity: Node, atmosphere_data: Dictionary):
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
			_handle_plasma_combustion(tile_coords, z_level, intensity)

func _handle_plasma_combustion(coords: Vector2, z_level: int, intensity: float):
	var tile = get_tile_data(coords, z_level)
	if tile is Dictionary:
		tile["on_fire"] = true
		tile["light_source"] = intensity * 5.0
		tile["light_color"] = Color(1.0, 0.7, 0.2, 0.7)
	
	if sensory_system:
		var pos = Vector2(coords.x * tile_size, coords.y * tile_size)
		sensory_system.emit_sound(pos, z_level, "machinery", intensity, null)

func _on_breach_detected(coordinates):
	var tile_coords = Vector2(coordinates.x, coordinates.y)
	var z_level = coordinates.z
	
	var tile = get_tile_data(tile_coords, z_level)
	if tile is Dictionary:
		tile["breach"] = true
		tile["exposed_to_space"] = true
	
	if sensory_system:
		var pos = Vector2(tile_coords.x * tile_size, tile_coords.y * tile_size)
		sensory_system.emit_sound(pos, z_level, "alarm", 1.0, null)

func _on_breach_sealed(coordinates):
	var tile_coords = Vector2(coordinates.x, coordinates.y)
	var z_level = coordinates.z
	
	var tile = get_tile_data(tile_coords, z_level)
	if tile is Dictionary:
		tile["breach"] = false
		tile["exposed_to_space"] = false
