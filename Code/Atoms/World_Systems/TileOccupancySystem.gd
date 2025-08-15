extends Node2D
class_name TileOccupancySystem

# =============================================================================
# CONSTANTS
# =============================================================================

const TILE_SIZE = 32
const MAX_Z_LEVELS = 10
const ENTITY_CACHE_CLEANUP_INTERVAL = 30.0
const MAX_CACHED_ENTITIES = 1000
const RAYCAST_MAX_DISTANCE = 50

# =============================================================================
# ENUMS
# =============================================================================

enum CollisionType {
	NONE,
	WALL,
	ENTITY,
	DENSE_OBJECT
}

enum EntityFlags {
	NONE = 0,
	DENSE = 1,
	MOVABLE = 2,
	PUSHABLE = 4,
	ANCHORED = 8,
	ITEM = 16
}

enum PushResult {
	SUCCESS,
	FAILED_DENSE,
	FAILED_IMMOVABLE,
	FAILED_ANCHORED,
	FAILED_NO_SPACE,
	FAILED_TOO_HEAVY
}

enum SyncMode {
	AUTHORITY_ONLY,
	HOST_ONLY,
	ANY_PEER
}

# =============================================================================
# EXPORTS
# =============================================================================

@export_group("System Settings")
@export var auto_initialize: bool = true
@export var initialize_z_levels: int = 10
@export var entity_cache_enabled: bool = true
@export var spatial_manager_integration: bool = true

@export_group("Physics Settings")
@export var mass_factor: float = 0.2
@export var push_force_scale: float = 1.0
@export var push_threshold: float = 15.0
@export var collision_detection_enabled: bool = true

@export_group("Multiplayer Settings")
@export var enable_multiplayer_sync: bool = true
@export var sync_mode: SyncMode = SyncMode.HOST_ONLY
@export var sync_entity_flags: bool = true
@export var sync_push_attempts: bool = false

@export_group("Performance Settings")
@export var max_cached_entities: int = MAX_CACHED_ENTITIES
@export var cache_cleanup_interval: float = ENTITY_CACHE_CLEANUP_INTERVAL
@export var raycast_max_distance: int = RAYCAST_MAX_DISTANCE
@export var batch_processing_enabled: bool = true

@export_group("Debug Settings")
@export var debug_mode: bool = false
@export var visual_debug: bool = false
@export var log_level: int = 1
@export var debug_show_grid: bool = false
@export var performance_monitoring: bool = false

# =============================================================================
# SIGNALS
# =============================================================================

signal entity_registered(entity, tile_pos, z_level)
signal entity_unregistered(entity, tile_pos, z_level)
signal entity_moved(entity, from_pos, to_pos, z_level)
signal entities_collided(entity1, entity2, tile_pos, z_level)
signal push_attempted(pusher, target, direction, result, force)
signal tile_contents_changed(tile_pos, z_level)
signal network_sync_failed(operation, reason)

# =============================================================================
# PRIVATE VARIABLES
# =============================================================================

# Core data structures
var _occupancy = {}
var _entity_by_flag = {}
var _entity_properties = {}
var _entity_positions = {}
var _valid_tile_cache = {}
var _network_authority_cache = {}

# Performance tracking
var _push_stats = {}
var _operation_stats = {}

# System references
var _spatial_manager = null
var _world = null
var _cache_cleanup_timer: Timer

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready():
	if auto_initialize:
		initialize(initialize_z_levels)
	
	_setup_systems()
	_setup_multiplayer()
	_setup_cache_cleanup()
	_setup_performance_monitoring()
	
	add_to_group("tile_occupancy_system")
	_log_message("TileOccupancySystem initialized", 3)

func _process(_delta):
	if visual_debug and debug_show_grid:
		queue_redraw()

func _draw():
	if visual_debug and debug_show_grid:
		_draw_debug_grid()

# =============================================================================
# INITIALIZATION
# =============================================================================

func initialize(z_levels: int = MAX_Z_LEVELS):
	_log_message("Initializing with " + str(z_levels) + " z-levels", 3)
	
	_clear_all_data()
	_initialize_occupancy_grid(z_levels)
	_reset_statistics()

func _setup_systems():
	if spatial_manager_integration:
		_connect_to_spatial_manager()
	
	_connect_to_world()

func _setup_multiplayer():
	if not enable_multiplayer_sync:
		return
	
	if multiplayer:
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _setup_cache_cleanup():
	_cache_cleanup_timer = Timer.new()
	_cache_cleanup_timer.wait_time = cache_cleanup_interval
	_cache_cleanup_timer.timeout.connect(_cleanup_entity_cache)
	_cache_cleanup_timer.autostart = true
	add_child(_cache_cleanup_timer)

func _setup_performance_monitoring():
	if performance_monitoring:
		_operation_stats = {
			"registrations": 0,
			"unregistrations": 0,
			"moves": 0,
			"pushes": 0,
			"cache_hits": 0,
			"cache_misses": 0
		}

func _clear_all_data():
	_occupancy.clear()
	_entity_by_flag.clear()
	_entity_properties.clear()
	_entity_positions.clear()
	_valid_tile_cache.clear()
	_network_authority_cache.clear()

func _initialize_occupancy_grid(z_levels: int):
	for z in range(z_levels):
		_occupancy[z] = {}
		_entity_by_flag[z] = {}
		
		for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.PUSHABLE, EntityFlags.ANCHORED, EntityFlags.ITEM]:
			_entity_by_flag[z][flag] = {}

func _reset_statistics():
	_push_stats = {
		"attempts": 0,
		"successes": 0,
		"failures": {
			"dense": 0,
			"immovable": 0,
			"anchored": 0, 
			"no_space": 0,
			"too_heavy": 0
		}
	}

func _connect_to_spatial_manager():
	var managers = get_tree().get_nodes_in_group("spatial_manager")
	if managers.size() > 0:
		_spatial_manager = managers[0]
		_log_message("Connected to SpatialManager", 3)
	else:
		_log_message("SpatialManager not found", 2)

func _connect_to_world():
	_world = get_node_or_null("/root/World")
	
	if _world and _world.has_signal("tile_changed"):
		_world.connect("tile_changed", _on_world_tile_changed)
		_log_message("Connected to World", 3)

# =============================================================================
# ENTITY REGISTRATION
# =============================================================================

func register_multi_tile_entity(entity, tile_positions: Array[Vector2i], z_level: int) -> bool:
	if not _validate_entity(entity):
		_log_message("Invalid entity provided for multi-tile registration", 1)
		return false
	
	if not _is_network_authority_for_entity(entity):
		_log_message("No authority to register multi-tile entity", 2)
		return false
	
	_ensure_z_level_exists(z_level)
	
	if _is_entity_at_positions(entity, tile_positions, z_level):
		return true
	
	_remove_entity_from_all_positions(entity)
	
	if entity_cache_enabled:
		_cache_entity_properties(entity)
	
	if not _register_multi_tile_entity_in_grid(entity, tile_positions, z_level):
		return false
	
	if _should_sync_operation():
		_sync_multi_tile_entity_registration.rpc(entity.get_instance_id(), tile_positions, z_level)
	
	_emit_registration_signals(entity, tile_positions, z_level)
	_update_performance_stats("registrations")
	
	_log_message("Multi-tile entity registered at " + str(tile_positions) + ", z=" + str(z_level), 4)
	return true

func register_entity_at_tile(entity, tile_pos: Vector2i, z_level: int) -> bool:
	return register_multi_tile_entity(entity, [tile_pos], z_level)

func register_entity(entity) -> bool:
	var position_data = _get_entity_position_data(entity)
	if not position_data.valid:
		_log_message("Entity has no valid position for registration", 1)
		return false
	
	return register_entity_at_tile(entity, position_data.tile_pos, position_data.z_level)

func unregister_entity(entity, tile_pos: Vector2i, z_level: int) -> bool:
	return remove_multi_tile_entity(entity, [tile_pos], z_level)

func remove_multi_tile_entity(entity, tile_positions: Array[Vector2i], z_level: int) -> bool:
	if not is_instance_valid(entity):
		for tile_pos in tile_positions:
			_cleanup_invalid_entity_at_tile(tile_pos, z_level)
		return true
	
	if not _is_network_authority_for_entity(entity):
		_log_message("No authority to remove multi-tile entity", 2)
		return false
	
	if not _remove_multi_tile_entity_from_grid(entity, tile_positions, z_level):
		return false
	
	if _should_sync_operation():
		_sync_multi_tile_entity_removal.rpc(entity.get_instance_id(), tile_positions, z_level)
	
	_emit_unregistration_signals(entity, tile_positions, z_level)
	_update_performance_stats("unregistrations")
	
	_log_message("Multi-tile entity removed from " + str(tile_positions) + ", z=" + str(z_level), 4)
	return true

# =============================================================================
# ENTITY MOVEMENT
# =============================================================================

func move_entity(entity, from_pos: Vector2i, to_pos: Vector2i, z_level: int) -> bool:
	if not _validate_entity(entity) or from_pos == to_pos:
		return from_pos == to_pos
	
	if not _is_network_authority_for_entity(entity):
		_log_message("No authority to move entity", 2)
		return false
	
	if not _is_valid_tile(to_pos, z_level):
		_log_message("Target tile is invalid", 2)
		return false
	
	var entity_positions = _get_entity_tile_positions(entity)
	if entity_positions.size() == 1:
		return _move_single_tile_entity(entity, from_pos, to_pos, z_level)
	else:
		return _move_multi_tile_entity(entity, from_pos, to_pos, z_level)

func try_move_entity(entity, direction: Vector2i, z_level: int) -> Dictionary:
	var result = {
		"success": false,
		"collision": null,
		"collision_type": CollisionType.NONE,
		"new_position": null
	}
	
	if not _validate_entity(entity):
		return result
	
	var current_tile = get_entity_tile(entity)
	if current_tile == Vector2i(-1, -1):
		return result
	
	var target_tile = current_tile + direction
	
	if not _is_valid_tile(target_tile, z_level):
		result.collision_type = CollisionType.WALL
		return result
	
	var collision = check_collision(target_tile, z_level, entity)
	
	if collision.type == CollisionType.NONE:
		if move_entity(entity, current_tile, target_tile, z_level):
			result.success = true
			result.new_position = target_tile
	else:
		result.collision = collision.entity
		result.collision_type = collision.type
		
		if collision.type == CollisionType.ENTITY and collision.entity != null:
			var push_result = try_push_entity(entity, collision.entity, direction)
			
			if push_result.success:
				if move_entity(entity, current_tile, target_tile, z_level):
					result.success = true
					result.new_position = target_tile
			
			emit_signal("entities_collided", entity, collision.entity, target_tile, z_level)
	
	return result

# =============================================================================
# PUSH SYSTEM
# =============================================================================

func try_push_entity(pusher, target, direction: Vector2i) -> Dictionary:
	var result = {
		"success": false,
		"result_code": PushResult.FAILED_DENSE,
		"force_applied": 0.0
	}
	
	_push_stats.attempts += 1
	
	if not _validate_entity(pusher) or not _validate_entity(target):
		return result
	
	if not _can_entity_be_pushed(target):
		result.result_code = PushResult.FAILED_IMMOVABLE
		_push_stats.failures.immovable += 1
		_emit_push_result(pusher, target, direction, PushResult.FAILED_IMMOVABLE, 0.0)
		return result
	
	if _is_entity_anchored(target):
		result.result_code = PushResult.FAILED_ANCHORED
		_push_stats.failures.anchored += 1
		_emit_push_result(pusher, target, direction, PushResult.FAILED_ANCHORED, 0.0)
		return result
	
	var target_position = get_entity_tile(target)
	var target_z = get_entity_z_level(target)
	var push_target = target_position + direction
	
	if not can_entity_move_to(target, push_target, target_z):
		result.result_code = PushResult.FAILED_NO_SPACE
		_push_stats.failures.no_space += 1
		_emit_push_result(pusher, target, direction, PushResult.FAILED_NO_SPACE, 0.0)
		return result
	
	var effective_force = _get_entity_push_force(pusher) * push_force_scale
	var mass_resistance = _get_entity_mass(target) * mass_factor
	
	if mass_resistance > push_threshold and effective_force < mass_resistance:
		result.result_code = PushResult.FAILED_TOO_HEAVY
		_push_stats.failures.too_heavy += 1
		_emit_push_result(pusher, target, direction, PushResult.FAILED_TOO_HEAVY, effective_force)
		return result
	
	if move_entity(target, target_position, push_target, target_z):
		result.success = true
		result.result_code = PushResult.SUCCESS
		result.force_applied = effective_force
		_push_stats.successes += 1
		
		_notify_entity_pushed(target, pusher, direction)
		_emit_push_result(pusher, target, direction, PushResult.SUCCESS, effective_force)
	else:
		result.result_code = PushResult.FAILED_NO_SPACE
		_push_stats.failures.no_space += 1
		_emit_push_result(pusher, target, direction, PushResult.FAILED_NO_SPACE, effective_force)
	
	_update_performance_stats("pushes")
	return result

# =============================================================================
# COLLISION DETECTION
# =============================================================================

func check_collision(tile_pos: Vector2i, z_level: int, exclude_entity = null) -> Dictionary:
	var result = {
		"type": CollisionType.NONE,
		"entity": null,
		"tile": tile_pos
	}
	
	if not _is_valid_tile(tile_pos, z_level):
		result.type = CollisionType.WALL
		return result
	
	if _check_world_obstacles(tile_pos, z_level, result):
		return result
	
	if collision_detection_enabled:
		var entities = get_entities_at(tile_pos, z_level)
		for entity in entities:
			if entity == exclude_entity or not is_instance_valid(entity):
				continue
			
			if _is_entity_dense(entity):
				result.type = CollisionType.ENTITY
				result.entity = entity
				return result
	
	return result

func can_entity_move_to(entity, tile_pos: Vector2i, z_level: int) -> bool:
	if not _is_valid_tile(tile_pos, z_level):
		return false
	
	var entity_positions = _get_entity_tile_positions(entity)
	if entity_positions.size() == 1:
		var collision = check_collision(tile_pos, z_level, entity)
		return collision.type == CollisionType.NONE
	else:
		var current_positions = entity_positions
		var offset = tile_pos - current_positions[0]
		var new_positions: Array[Vector2i] = []
		
		for pos in current_positions:
			new_positions.append(pos + offset)
		
		return _can_multi_tile_entity_move_to(entity, new_positions, z_level)

# =============================================================================
# ENTITY QUERIES
# =============================================================================

func get_entities_at(tile_pos: Vector2i, z_level: int) -> Array:
	if not z_level in _occupancy or not tile_pos in _occupancy[z_level]:
		return []
	
	return _occupancy[z_level][tile_pos].duplicate()

func get_entity_at(tile_pos: Vector2i, z_level: int, type_name: String = ""):
	var entities = get_entities_at(tile_pos, z_level)
	
	if entities.size() == 0:
		return null
	
	if type_name.is_empty():
		return entities[0]
	
	for entity in entities:
		if is_instance_valid(entity) and _get_entity_property(entity, "entity_type") == type_name:
			return entity
	
	return null

func has_dense_entity_at(tile_pos: Vector2i, z_level: int, excluding_entity = null) -> bool:
	if z_level in _entity_by_flag and EntityFlags.DENSE in _entity_by_flag[z_level] and tile_pos in _entity_by_flag[z_level][EntityFlags.DENSE]:
		for entity in _entity_by_flag[z_level][EntityFlags.DENSE][tile_pos]:
			if entity != excluding_entity and is_instance_valid(entity):
				return true
	
	return false

func get_entity_position(entity) -> Dictionary:
	var entity_id = _get_entity_id(entity)
	
	if entity_id in _entity_positions:
		return _entity_positions[entity_id].duplicate()
	
	return {"valid": false}

func get_entity_tile(entity) -> Vector2i:
	var entity_positions = _get_entity_tile_positions(entity)
	if entity_positions.size() > 0:
		return entity_positions[0]
	
	var position_data = _get_entity_position_data(entity)
	if position_data.valid:
		return position_data.tile_pos
	
	return Vector2i(-1, -1)

func get_entity_z_level(entity) -> int:
	var entity_id = _get_entity_id(entity)
	
	if entity_id in _entity_positions:
		return _entity_positions[entity_id].z_level
	
	var position_data = _get_entity_position_data(entity)
	if position_data.valid:
		return position_data.z_level
	
	return -1

# =============================================================================
# RAYCASTING
# =============================================================================

func raycast(start_tile: Vector2i, end_tile: Vector2i, z_level: int) -> Dictionary:
	var result = {
		"hit": false,
		"hit_pos": null,
		"hit_entity": null,
		"hit_tile": null,
		"tiles": []
	}
	
	var tiles = _get_tiles_in_line(start_tile, end_tile)
	result.tiles = tiles
	
	if tiles.size() > 1:
		tiles.remove_at(0)
		
	if tiles.size() > raycast_max_distance:
		tiles = tiles.slice(0, raycast_max_distance)
	
	for tile_pos in tiles:
		var collision = check_collision(tile_pos, z_level)
		
		if collision.type != CollisionType.NONE:
			result.hit = true
			result.hit_tile = tile_pos
			result.hit_entity = collision.entity
			result.hit_pos = tile_to_world(tile_pos)
			break
	
	if not result.hit:
		result.hit_pos = tile_to_world(end_tile)
	
	return result

# =============================================================================
# COORDINATE CONVERSION
# =============================================================================

func world_to_tile(world_pos: Vector2) -> Vector2i:
	if _world and _world.has_method("get_tile_at"):
		return _world.get_tile_at(world_pos)
	
	return Vector2i(int(world_pos.x / TILE_SIZE), int(world_pos.y / TILE_SIZE))

func tile_to_world(tile_pos: Vector2i) -> Vector2:
	if _world and _world.has_method("tile_to_world"):
		return _world.tile_to_world(tile_pos)
	
	return Vector2(
		(tile_pos.x * TILE_SIZE) + (TILE_SIZE / 2),
		(tile_pos.y * TILE_SIZE) + (TILE_SIZE / 2)
	)

# =============================================================================
# MAINTENANCE AND CLEANUP
# =============================================================================

func clean_invalid_entities() -> int:
	var removed_count = 0
	
	for z in _occupancy.keys():
		var tiles_to_check = _occupancy[z].keys().duplicate()
		
		for tile_pos in tiles_to_check:
			if _cleanup_invalid_entity_at_tile(tile_pos, z):
				removed_count += 1
	
	_cleanup_entity_cache()
	
	if removed_count > 0:
		_log_message("Cleaned up " + str(removed_count) + " invalid entity references", 2)
	
	return removed_count

func update_entity_property(entity, property_name: String, new_value):
	if not is_instance_valid(entity):
		return
	
	var entity_id = _get_entity_id(entity)
	var old_position = get_entity_position(entity)
	
	if property_name in ["entity_dense", "dense"]:
		if entity_cache_enabled and entity_id in _entity_properties:
			_entity_properties[entity_id].dense = new_value
		
		if "valid" in old_position and old_position["valid"]:
			var flags = _get_entity_flags(entity)
			var positions = _get_entity_tile_positions(entity)
			for tile_pos in positions:
				_remove_entity_from_flag_collections(entity, tile_pos, old_position.z_level, flags)
				_add_entity_to_flag_collections(entity, tile_pos, old_position.z_level, flags)

# =============================================================================
# DEBUG AND STATISTICS
# =============================================================================

func get_debug_stats() -> Dictionary:
	return {
		"total_entities": get_entity_count(),
		"occupied_tiles": get_occupied_tile_count(),
		"cached_entities": _entity_properties.size() if entity_cache_enabled else 0,
		"z_levels": _get_z_level_stats(),
		"push_stats": get_push_stats(),
		"flag_counts": _get_flag_counts(),
		"network_active": _is_multiplayer_active(),
		"is_host": _is_multiplayer_host(),
		"performance_stats": _operation_stats if performance_monitoring else {}
	}

func get_entity_count(z_level = null) -> int:
	if z_level == null:
		var count = 0
		for z in _occupancy.keys():
			for tile in _occupancy[z].keys():
				count += _occupancy[z][tile].size()
		return count
	elif z_level in _occupancy:
		var count = 0
		for tile in _occupancy[z_level].keys():
			count += _occupancy[z_level][tile].size()
		return count
	
	return 0

func get_occupied_tile_count(z_level = null) -> int:
	if z_level == null:
		var count = 0
		for z in _occupancy.keys():
			count += _occupancy[z].keys().size()
		return count
	elif z_level in _occupancy:
		return _occupancy[z_level].keys().size()
	
	return 0

func get_push_stats() -> Dictionary:
	var success_rate = 0.0
	if _push_stats.attempts > 0:
		success_rate = float(_push_stats.successes) / float(_push_stats.attempts)
	
	var stats = _push_stats.duplicate(true)
	stats.success_rate = success_rate
	return stats

# =============================================================================
# PRIVATE HELPER METHODS
# =============================================================================

func _validate_entity(entity) -> bool:
	return is_instance_valid(entity) and "position" in entity

func _get_entity_id(entity):
	if not is_instance_valid(entity):
		return "INVALID"
	
	if "entity_id" in entity and entity.entity_id:
		return entity.entity_id
	
	return entity.get_instance_id()

func _get_entity_property(entity, property_name: String, default_value = null):
	if not is_instance_valid(entity):
		return default_value
	
	if property_name in entity:
		return entity[property_name]
	elif entity.has_method(property_name):
		return entity.call(property_name)
	else:
		return default_value

func _get_entity_position_data(entity) -> Dictionary:
	if not is_instance_valid(entity):
		return {"valid": false}
	
	var result = {
		"valid": true,
		"position": Vector2.ZERO,
		"tile_pos": Vector2i.ZERO,
		"z_level": 0
	}
	
	if entity.has_method("global_position"):
		result.position = entity.global_position
	elif "position" in entity:
		result.position = entity.position
	else:
		return {"valid": false}
	
	result.tile_pos = world_to_tile(result.position)
	
	if "current_z_level" in entity:
		result.z_level = entity.current_z_level
	elif "z_level" in entity:
		result.z_level = entity.z_level
	elif entity is Node2D:
		result.z_level = entity.z_index
	
	return result

func _is_entity_dense(entity) -> bool:
	if not is_instance_valid(entity):
		return false
	
	var entity_id = _get_entity_id(entity)
	
	if entity_cache_enabled and entity_id in _entity_properties:
		_update_performance_stats("cache_hits")
		return _entity_properties[entity_id].dense
	
	_update_performance_stats("cache_misses")
	return _is_entity_dense_direct(entity)

func _is_entity_dense_direct(entity) -> bool:
	if _get_entity_property(entity, "entity_type") == "item":
		var explicit_density = _get_entity_property(entity, "entity_dense", null)
		if explicit_density != null:
			return explicit_density
		return false
	
	return _get_entity_property(entity, "entity_dense", true)

func _get_entity_flags(entity) -> int:
	var flags = EntityFlags.NONE
	
	if _is_entity_dense_direct(entity):
		flags |= EntityFlags.DENSE
	
	if _get_entity_property(entity, "movable", true):
		flags |= EntityFlags.MOVABLE
	
	if _get_entity_property(entity, "can_be_pushed", true):
		flags |= EntityFlags.PUSHABLE
	
	if _get_entity_property(entity, "anchored", false):
		flags |= EntityFlags.ANCHORED
	
	if _get_entity_property(entity, "entity_type") == "item":
		flags |= EntityFlags.ITEM
	
	return flags

func _can_entity_be_pushed(entity) -> bool:
	var entity_id = _get_entity_id(entity)
	
	if entity_cache_enabled and entity_id in _entity_properties:
		return _entity_properties[entity_id].can_be_pushed
	
	return _get_entity_property(entity, "can_be_pushed", true)

func _is_entity_anchored(entity) -> bool:
	return _get_entity_property(entity, "anchored", false)

func _get_entity_push_force(entity) -> float:
	var entity_id = _get_entity_id(entity)
	
	if entity_cache_enabled and entity_id in _entity_properties:
		return _entity_properties[entity_id].push_force
	
	return _get_entity_property(entity, "push_force", 1.0)

func _get_entity_mass(entity) -> float:
	var entity_id = _get_entity_id(entity)
	
	if entity_cache_enabled and entity_id in _entity_properties:
		return _entity_properties[entity_id].mass
	
	return _get_entity_property(entity, "mass", 10.0)

func _get_entity_tile_positions(entity) -> Array[Vector2i]:
	var entity_id = _get_entity_id(entity)

	if entity_id in _entity_positions:
		var pos_data = _entity_positions[entity_id]

		if "tile_positions" in pos_data:
			var result: Array[Vector2i] = []
			for pos in pos_data.tile_positions:
				result.append(Vector2i(pos))
			return result

		elif "tile_pos" in pos_data:
			return [Vector2i(pos_data.tile_pos)]

	return []

func _ensure_z_level_exists(z_level: int):
	if not z_level in _occupancy:
		_occupancy[z_level] = {}
		_entity_by_flag[z_level] = {}
		
		for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.PUSHABLE, EntityFlags.ANCHORED, EntityFlags.ITEM]:
			_entity_by_flag[z_level][flag] = {}

func _is_entity_at_positions(entity, tile_positions: Array[Vector2i], z_level: int) -> bool:
	var current_positions = _get_entity_tile_positions(entity)
	var current_z = get_entity_z_level(entity)
	
	if current_z != z_level or current_positions.size() != tile_positions.size():
		return false
	
	for pos in tile_positions:
		if pos not in current_positions:
			return false
	
	return true

func _remove_entity_from_all_positions(entity):
	var entity_id = _get_entity_id(entity)
	if entity_id in _entity_positions:
		var pos_data = _entity_positions[entity_id]
		var positions = []
		
		if "tile_positions" in pos_data:
			positions = pos_data.tile_positions
		elif "tile_pos" in pos_data:
			positions = [pos_data.tile_pos]
		
		if positions.size() > 0:
			remove_multi_tile_entity(entity, positions, pos_data.z_level)

func _register_multi_tile_entity_in_grid(entity, tile_positions: Array[Vector2i], z_level: int) -> bool:
	var entity_id = _get_entity_id(entity)
	
	for tile_pos in tile_positions:
		if not tile_pos in _occupancy[z_level]:
			_occupancy[z_level][tile_pos] = []
		
		_occupancy[z_level][tile_pos].append(entity)
	
	var flags = _get_entity_flags(entity)
	for tile_pos in tile_positions:
		_add_entity_to_flag_collections(entity, tile_pos, z_level, flags)
	
	_entity_positions[entity_id] = {
		"tile_positions": tile_positions,
		"z_level": z_level
	}
	
	return true

func _remove_multi_tile_entity_from_grid(entity, tile_positions: Array[Vector2i], z_level: int) -> bool:
	if not z_level in _occupancy:
		return false
	
	var entity_id = _get_entity_id(entity)
	var removed_any = false
	
	for tile_pos in tile_positions:
		if tile_pos in _occupancy[z_level] and entity in _occupancy[z_level][tile_pos]:
			_occupancy[z_level][tile_pos].erase(entity)
			
			if _occupancy[z_level][tile_pos].size() == 0:
				_occupancy[z_level].erase(tile_pos)
			
			var flags = _get_entity_flags(entity)
			_remove_entity_from_flag_collections(entity, tile_pos, z_level, flags)
			removed_any = true
	
	if removed_any:
		_entity_positions.erase(entity_id)
	
	return removed_any

func _move_single_tile_entity(entity, from_pos: Vector2i, to_pos: Vector2i, z_level: int) -> bool:
	if not _move_entity_in_grid(entity, from_pos, to_pos, z_level):
		return false
	
	if _should_sync_operation():
		_sync_entity_movement.rpc(entity.get_instance_id(), from_pos, to_pos, z_level)
	
	emit_signal("entity_moved", entity, from_pos, to_pos, z_level)
	emit_signal("tile_contents_changed", from_pos, z_level)
	emit_signal("tile_contents_changed", to_pos, z_level)
	
	_update_performance_stats("moves")
	_log_message("Entity moved from " + str(from_pos) + " to " + str(to_pos), 4)
	return true

func _move_multi_tile_entity(entity, from_pos: Vector2i, to_pos: Vector2i, z_level: int) -> bool:
	var current_positions = _get_entity_tile_positions(entity)
	var offset = to_pos - from_pos
	var new_positions: Array[Vector2i] = []
	
	for pos in current_positions:
		new_positions.append(pos + offset)
	
	if not _can_multi_tile_entity_move_to(entity, new_positions, z_level):
		return false
	
	_remove_multi_tile_entity_from_grid(entity, current_positions, z_level)
	_register_multi_tile_entity_in_grid(entity, new_positions, z_level)
	
	if _should_sync_operation():
		_sync_multi_tile_entity_movement.rpc(entity.get_instance_id(), current_positions, new_positions, z_level)
	
	emit_signal("entity_moved", entity, from_pos, to_pos, z_level)
	for pos in current_positions:
		emit_signal("tile_contents_changed", pos, z_level)
	for pos in new_positions:
		emit_signal("tile_contents_changed", pos, z_level)
	
	_update_performance_stats("moves")
	_log_message("Multi-tile entity moved from " + str(current_positions) + " to " + str(new_positions), 4)
	return true

func _move_entity_in_grid(entity, from_pos: Vector2i, to_pos: Vector2i, z_level: int) -> bool:
	var entity_id = _get_entity_id(entity)
	
	if not (z_level in _occupancy and from_pos in _occupancy[z_level] and entity in _occupancy[z_level][from_pos]):
		return _register_multi_tile_entity_in_grid(entity, [to_pos], z_level)
	
	_occupancy[z_level][from_pos].erase(entity)
	if _occupancy[z_level][from_pos].size() == 0:
		_occupancy[z_level].erase(from_pos)
	
	if not to_pos in _occupancy[z_level]:
		_occupancy[z_level][to_pos] = []
	_occupancy[z_level][to_pos].append(entity)
	
	var flags = _get_entity_flags(entity)
	_remove_entity_from_flag_collections(entity, from_pos, z_level, flags)
	_add_entity_to_flag_collections(entity, to_pos, z_level, flags)
	
	_entity_positions[entity_id] = {
		"tile_positions": [to_pos],
		"z_level": z_level
	}
	
	return true

func _can_multi_tile_entity_move_to(entity, tile_positions: Array[Vector2i], z_level: int) -> bool:
	for tile_pos in tile_positions:
		if not _is_valid_tile(tile_pos, z_level):
			return false
		
		var collision = check_collision(tile_pos, z_level, entity)
		if collision.type != CollisionType.NONE:
			return false
	
	return true

func _add_entity_to_flag_collections(entity, tile_pos: Vector2i, z_level: int, flags: int):
	for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.PUSHABLE, EntityFlags.ANCHORED, EntityFlags.ITEM]:
		if flags & flag:
			if not tile_pos in _entity_by_flag[z_level][flag]:
				_entity_by_flag[z_level][flag][tile_pos] = []
			_entity_by_flag[z_level][flag][tile_pos].append(entity)

func _remove_entity_from_flag_collections(entity, tile_pos: Vector2i, z_level: int, flags: int):
	for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.PUSHABLE, EntityFlags.ANCHORED, EntityFlags.ITEM]:
		if flags & flag and tile_pos in _entity_by_flag[z_level][flag]:
			_entity_by_flag[z_level][flag][tile_pos].erase(entity)
			if _entity_by_flag[z_level][flag][tile_pos].size() == 0:
				_entity_by_flag[z_level][flag].erase(tile_pos)

func _cache_entity_properties(entity):
	var entity_id = _get_entity_id(entity)
	
	_entity_properties[entity_id] = {
		"dense": _is_entity_dense_direct(entity),
		"can_push": _get_entity_property(entity, "can_push", true),
		"can_be_pushed": _get_entity_property(entity, "can_be_pushed", true),
		"push_force": _get_entity_property(entity, "push_force", 1.0),
		"mass": _get_entity_property(entity, "mass", 10.0),
		"flags": _get_entity_flags(entity),
		"last_update_time": Time.get_ticks_msec()
	}

func _cleanup_entity_cache():
	if not entity_cache_enabled:
		return
	
	var current_time = Time.get_ticks_msec()
	var ids_to_remove = []
	
	for entity_id in _entity_properties.keys():
		var cache_entry = _entity_properties[entity_id]
		
		if entity_id is int:
			var entity = instance_from_id(entity_id)
			if not is_instance_valid(entity):
				ids_to_remove.append(entity_id)
				continue
		
		if current_time - cache_entry.last_update_time > cache_cleanup_interval * 1000:
			ids_to_remove.append(entity_id)
	
	for entity_id in ids_to_remove:
		_entity_properties.erase(entity_id)
		_entity_positions.erase(entity_id)
	
	if _entity_properties.size() > max_cached_entities:
		var sorted_entries = []
		for entity_id in _entity_properties.keys():
			sorted_entries.append([entity_id, _entity_properties[entity_id].last_update_time])
		
		sorted_entries.sort_custom(func(a, b): return a[1] < b[1])
		
		var excess_count = _entity_properties.size() - max_cached_entities
		for i in range(excess_count):
			var entity_id = sorted_entries[i][0]
			_entity_properties.erase(entity_id)
			_entity_positions.erase(entity_id)

func _cleanup_invalid_entity_at_tile(tile_pos: Vector2i, z_level: int) -> bool:
	if not z_level in _occupancy or not tile_pos in _occupancy[z_level]:
		return false
	
	var had_invalid = false
	var valid_entities = []
	
	for entity in _occupancy[z_level][tile_pos]:
		if is_instance_valid(entity):
			valid_entities.append(entity)
		else:
			had_invalid = true
	
	if had_invalid:
		if valid_entities.size() > 0:
			_occupancy[z_level][tile_pos] = valid_entities
		else:
			_occupancy[z_level].erase(tile_pos)
		
		for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.PUSHABLE, EntityFlags.ANCHORED, EntityFlags.ITEM]:
			if z_level in _entity_by_flag and flag in _entity_by_flag[z_level] and tile_pos in _entity_by_flag[z_level][flag]:
				var valid_flag_entities = []
				for entity in _entity_by_flag[z_level][flag][tile_pos]:
					if is_instance_valid(entity):
						valid_flag_entities.append(entity)
				
				if valid_flag_entities.size() > 0:
					_entity_by_flag[z_level][flag][tile_pos] = valid_flag_entities
				else:
					_entity_by_flag[z_level][flag].erase(tile_pos)
		
		emit_signal("tile_contents_changed", tile_pos, z_level)
		return true
	
	return false

func _check_world_obstacles(tile_pos: Vector2i, z_level: int, result: Dictionary) -> bool:
	if not _world:
		return false
	
	if _world.has_method("is_wall_at") and _world.is_wall_at(tile_pos, z_level):
		result.type = CollisionType.WALL
		return true
	
	return false

func _is_valid_tile(tile_pos: Vector2i, z_level: int) -> bool:
	var cache_key = str(tile_pos) + "_" + str(z_level)
	if cache_key in _valid_tile_cache:
		return _valid_tile_cache[cache_key]
	
	var is_valid = true
	
	if _world:
		if _world.has_method("is_valid_tile"):
			is_valid = _world.is_valid_tile(tile_pos, z_level)
		elif _world.has_method("get_tile_data"):
			is_valid = _world.get_tile_data(tile_pos, z_level) != null
	
	_valid_tile_cache[cache_key] = is_valid
	return is_valid

func _get_tiles_in_line(start: Vector2i, end: Vector2i) -> Array:
	var tiles = []
	var x0 = start.x
	var y0 = start.y
	var x1 = end.x
	var y1 = end.y
	
	var dx = abs(x1 - x0)
	var dy = abs(y1 - y0)
	var sx = 1 if x0 < x1 else -1
	var sy = 1 if y0 < y1 else -1
	var err = dx - dy
	
	while true:
		tiles.append(Vector2i(x0, y0))
		
		if x0 == x1 and y0 == y1:
			break
		
		var e2 = 2 * err
		if e2 > -dy:
			if x0 == x1:
				break
			err -= dy
			x0 += sx
		
		if e2 < dx:
			if y0 == y1:
				break
			err += dx
			y0 += sy
	
	return tiles

func _draw_debug_grid():
	var viewport_rect = get_viewport_rect()
	var camera_pos = Vector2.ZERO
	
	var camera = get_viewport().get_camera_2d()
	if camera:
		camera_pos = camera.global_position
	
	var screen_size = viewport_rect.size
	var top_left = camera_pos - screen_size/2
	var bottom_right = camera_pos + screen_size/2
	
	var start_tile = world_to_tile(top_left)
	var end_tile = world_to_tile(bottom_right)
	
	var z_level = 0
	if _world and "current_z_level" in _world:
		z_level = _world.current_z_level
	
	if not z_level in _occupancy:
		return
	
	for y in range(start_tile.y - 1, end_tile.y + 2):
		for x in range(start_tile.x - 1, end_tile.x + 2):
			var tile_pos = Vector2i(x, y)
			
			if not tile_pos in _occupancy[z_level]:
				continue
			
			var entities = _occupancy[z_level][tile_pos]
			var entity_count = entities.size()
			
			if entity_count == 0:
				continue
			
			var has_dense = false
			for entity in entities:
				if _is_entity_dense(entity):
					has_dense = true
					break
			
			var color = Color(0, 1, 0, 0.3) if not has_dense else Color(1, 0, 0, 0.3)
			var world_pos = tile_to_world(tile_pos)
			
			draw_rect(Rect2(world_pos - Vector2(TILE_SIZE/2, TILE_SIZE/2), Vector2(TILE_SIZE, TILE_SIZE)), color, false, 2)
			draw_string(ThemeDB.fallback_font, world_pos - Vector2(TILE_SIZE/4, 0), str(entity_count), HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color.WHITE)

# Network and multiplayer helpers
func _is_network_authority_for_entity(entity) -> bool:
	if not enable_multiplayer_sync or not _is_multiplayer_active():
		return true
	
	match sync_mode:
		SyncMode.HOST_ONLY:
			return _is_multiplayer_host()
		SyncMode.AUTHORITY_ONLY:
			if entity and entity.has_method("get_multiplayer_authority"):
				return entity.get_multiplayer_authority() == multiplayer.get_unique_id()
			return _is_multiplayer_host()
		SyncMode.ANY_PEER:
			return true
	
	return false

func _is_multiplayer_active() -> bool:
	return multiplayer and multiplayer.multiplayer_peer != null

func _is_multiplayer_host() -> bool:
	return _is_multiplayer_active() and multiplayer.get_unique_id() == 1

func _should_sync_operation() -> bool:
	return enable_multiplayer_sync and _is_multiplayer_active() and multiplayer.get_peers().size() > 0

func _notify_entity_pushed(target, pusher, direction: Vector2i):
	if target.has_method("pushed"):
		target.pushed(pusher, direction)

func _emit_push_result(pusher, target, direction: Vector2i, result_code: PushResult, force: float):
	emit_signal("push_attempted", pusher, target, direction, result_code, force)
	
	if sync_push_attempts and _should_sync_operation():
		_sync_push_attempt.rpc(pusher.get_instance_id(), target.get_instance_id(), direction, result_code, force)

func _emit_registration_signals(entity, tile_positions: Array[Vector2i], z_level: int):
	for tile_pos in tile_positions:
		emit_signal("entity_registered", entity, tile_pos, z_level)
		emit_signal("tile_contents_changed", tile_pos, z_level)

func _emit_unregistration_signals(entity, tile_positions: Array[Vector2i], z_level: int):
	for tile_pos in tile_positions:
		emit_signal("entity_unregistered", entity, tile_pos, z_level)
		emit_signal("tile_contents_changed", tile_pos, z_level)

func _update_performance_stats(stat_name: String):
	if not performance_monitoring:
		return
		
	if stat_name in _operation_stats:
		_operation_stats[stat_name] += 1

func _get_z_level_stats() -> Dictionary:
	var stats = {}
	for z in _occupancy.keys():
		stats[z] = {
			"tiles": _occupancy[z].keys().size(),
			"entities": get_entity_count(z)
		}
	return stats

func _get_flag_counts() -> Dictionary:
	var counts = {}
	var flag_names = ["dense", "movable", "pushable", "anchored", "item"]
	var flag_values = [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.PUSHABLE, EntityFlags.ANCHORED, EntityFlags.ITEM]
	
	for i in range(flag_names.size()):
		var flag = flag_values[i]
		var count = 0
		
		for z in _entity_by_flag.keys():
			if flag in _entity_by_flag[z]:
				for tile_pos in _entity_by_flag[z][flag]:
					count += _entity_by_flag[z][flag][tile_pos].size()
		
		counts[flag_names[i]] = count
	
	return counts

func _log_message(message: String, level: int = 3):
	if level <= log_level:
		var prefix = ["", "[ERROR] ", "[WARN] ", "[INFO] ", "[DEBUG] "][level]
		if debug_mode:
			print(prefix + "TileOccupancySystem: " + message)

# =============================================================================
# RPC METHODS
# =============================================================================

@rpc("any_peer", "call_local", "reliable")
func _sync_multi_tile_entity_registration(entity_id: int, tile_positions: Array[Vector2i], z_level: int):
	var entity = instance_from_id(entity_id)
	if not is_instance_valid(entity):
		return
	
	if _is_network_authority_for_entity(entity):
		return
	
	_register_multi_tile_entity_in_grid(entity, tile_positions, z_level)

@rpc("any_peer", "call_local", "reliable")
func _sync_multi_tile_entity_removal(entity_id: int, tile_positions: Array[Vector2i], z_level: int):
	var entity = instance_from_id(entity_id)
	if is_instance_valid(entity) and _is_network_authority_for_entity(entity):
		return
	
	_remove_multi_tile_entity_from_grid_by_id(entity_id, tile_positions, z_level)

@rpc("any_peer", "call_local", "reliable")
func _sync_entity_movement(entity_id: int, from_pos: Vector2i, to_pos: Vector2i, z_level: int):
	var entity = instance_from_id(entity_id)
	if not is_instance_valid(entity) or _is_network_authority_for_entity(entity):
		return
	
	_move_entity_in_grid(entity, from_pos, to_pos, z_level)

@rpc("any_peer", "call_local", "reliable")
func _sync_multi_tile_entity_movement(entity_id: int, old_positions: Array[Vector2i], new_positions: Array[Vector2i], z_level: int):
	var entity = instance_from_id(entity_id)
	if not is_instance_valid(entity) or _is_network_authority_for_entity(entity):
		return
	
	_remove_multi_tile_entity_from_grid(entity, old_positions, z_level)
	_register_multi_tile_entity_in_grid(entity, new_positions, z_level)

@rpc("any_peer", "call_local", "reliable")
func _sync_push_attempt(pusher_id: int, target_id: int, direction: Vector2i, result_code: PushResult, force: float):
	var pusher = instance_from_id(pusher_id)
	var target = instance_from_id(target_id)
	
	if is_instance_valid(pusher) and is_instance_valid(target):
		emit_signal("push_attempted", pusher, target, direction, result_code, force)

func _remove_multi_tile_entity_from_grid_by_id(entity_id: int, tile_positions: Array[Vector2i], z_level: int):
	if not z_level in _occupancy:
		return
	
	for tile_pos in tile_positions:
		if not tile_pos in _occupancy[z_level]:
			continue
		
		var entity_to_remove = null
		for entity in _occupancy[z_level][tile_pos]:
			if _get_entity_id(entity) == entity_id:
				entity_to_remove = entity
				break
		
		if entity_to_remove:
			_occupancy[z_level][tile_pos].erase(entity_to_remove)
			if _occupancy[z_level][tile_pos].size() == 0:
				_occupancy[z_level].erase(tile_pos)
			
			var flags = _get_entity_flags(entity_to_remove)
			_remove_entity_from_flag_collections(entity_to_remove, tile_pos, z_level, flags)
	
	_entity_positions.erase(entity_id)

# =============================================================================
# SIGNAL HANDLERS
# =============================================================================

func _on_world_tile_changed(tile_coords: Vector2i, z_level: int, old_data, new_data):
	var cache_key = str(tile_coords) + "_" + str(z_level)
	_valid_tile_cache.erase(cache_key)
	
	var old_blocked = _is_tile_data_blocked(old_data)
	var new_blocked = _is_tile_data_blocked(new_data)
	
	if old_blocked != new_blocked:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var neighbor = tile_coords + Vector2i(dx, dy)
				var neighbor_key = str(neighbor) + "_" + str(z_level)
				_valid_tile_cache.erase(neighbor_key)

func _is_tile_data_blocked(tile_data) -> bool:
	if not tile_data:
		return false
	
	if "wall" in tile_data and tile_data.wall != null:
		return true
	
	return false

func _on_peer_connected(peer_id: int):
	_log_message("Peer connected: " + str(peer_id), 3)

func _on_peer_disconnected(peer_id: int):
	_log_message("Peer disconnected: " + str(peer_id), 3)
	_cleanup_peer_entities(peer_id)

func _cleanup_peer_entities(peer_id: int):
	var entities_to_remove = []
	
	for entity_id in _entity_positions.keys():
		if entity_id is int:
			var entity = instance_from_id(entity_id)
			if is_instance_valid(entity) and entity.has_method("get_multiplayer_authority"):
				if entity.get_multiplayer_authority() == peer_id:
					entities_to_remove.append(entity)
	
	for entity in entities_to_remove:
		var pos = get_entity_position(entity)
		if pos.valid:
			var positions = _get_entity_tile_positions(entity)
			if positions.size() > 0:
				remove_multi_tile_entity(entity, positions, pos.z_level)
