extends Node2D
class_name TileOccupancySystem

#region CONSTANTS AND ENUMS
const TILE_SIZE = 32
const MAX_Z_LEVELS = 10
const ENTITY_CACHE_CLEANUP_INTERVAL = 30.0  # seconds
const MAX_CACHED_ENTITIES = 1000
const RAYCAST_MAX_DISTANCE = 50

# Collision types for improved collision detection
enum CollisionType {
	NONE,
	WALL,
	ENTITY,
	DENSE_OBJECT,
	DOOR_CLOSED,
	WINDOW
}

# Entity property flags
enum EntityFlags {
	NONE = 0,
	DENSE = 1,
	MOVABLE = 2,
	PUSHABLE = 4,
	ANCHORED = 8,
	ITEM = 16
}

# Push result codes
enum PushResult {
	SUCCESS,
	FAILED_DENSE,
	FAILED_IMMOVABLE,
	FAILED_ANCHORED,
	FAILED_NO_SPACE,
	FAILED_TOO_HEAVY
}

# Network sync modes
enum SyncMode {
	AUTHORITY_ONLY,  # Only authority can make changes
	HOST_ONLY,       # Only host can make changes
	ANY_PEER         # Any peer can make changes (with validation)
}
#endregion

#region PROPERTIES AND SIGNALS
# Primary occupancy grid - organized by z-level then by Vector2i tile coordinate
var _occupancy = {}
# Secondary organization by entity properties for faster queries
var _entity_by_flag = {}
# Entity properties cache for optimized lookups
var _entity_properties = {}
# Entity position tracking
var _entity_positions = {}
# Push statistics for debugging and balancing
var _push_stats = {}
# Cache for tile validity checking
var _valid_tile_cache = {}
# Network sync state
var _network_authority_cache = {}

# Settings
@export_group("System Settings")
@export var auto_initialize: bool = true
@export var initialize_z_levels: int = 10
@export var entity_cache_enabled: bool = true
@export var spatial_manager_integration: bool = true

@export_subgroup("Physics Settings")
@export var mass_factor: float = 0.2
@export var push_force_scale: float = 1.0
@export var push_threshold: float = 15.0

@export_subgroup("Multiplayer Settings")
@export var enable_multiplayer_sync: bool = true
@export var sync_mode: SyncMode = SyncMode.HOST_ONLY
@export var sync_entity_flags: bool = true
@export var sync_push_attempts: bool = false

@export_subgroup("Debug Settings")
@export var debug_mode: bool = false
@export var visual_debug: bool = false
@export var log_level: int = 1
@export var debug_show_grid: bool = false

# References to other systems
var _spatial_manager = null
var _world = null
var _cache_cleanup_timer: Timer

# Signals
signal entity_registered(entity, tile_pos, z_level)
signal entity_unregistered(entity, tile_pos, z_level)
signal entity_moved(entity, from_pos, to_pos, z_level)
signal entities_collided(entity1, entity2, tile_pos, z_level)
signal push_attempted(pusher, target, direction, result, force)
signal tile_contents_changed(tile_pos, z_level)
signal network_sync_failed(operation, reason)
#endregion

#region LIFECYCLE METHODS
func _ready():
	if auto_initialize:
		initialize(initialize_z_levels)
	
	_setup_systems()
	_setup_multiplayer()
	_setup_cache_cleanup()
	
	add_to_group("tile_occupancy_system")
	print_log("TileOccupancySystem initialized", 3)

func _setup_systems():
	"""Initialize system connections and visual debugging"""
	if visual_debug:
		set_process(true)
	
	if spatial_manager_integration:
		_connect_to_spatial_manager()
	
	_connect_to_world()

func _setup_multiplayer():
	"""Setup multiplayer synchronization"""
	if not enable_multiplayer_sync:
		return
	
	# Connect to multiplayer signals if available
	if multiplayer:
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _setup_cache_cleanup():
	"""Setup automatic cache cleanup"""
	_cache_cleanup_timer = Timer.new()
	_cache_cleanup_timer.wait_time = ENTITY_CACHE_CLEANUP_INTERVAL
	_cache_cleanup_timer.timeout.connect(_cleanup_entity_cache)
	_cache_cleanup_timer.autostart = true
	add_child(_cache_cleanup_timer)

func _process(_delta):
	if visual_debug and debug_show_grid:
		queue_redraw()

func _draw():
	if not visual_debug or not debug_show_grid:
		return
	
	_draw_debug_grid()
#endregion

#region INITIALIZATION
func initialize(z_levels: int = MAX_Z_LEVELS):
	"""Initialize the tile occupancy system."""
	print_log("Initializing with " + str(z_levels) + " z-levels", 3)
	
	_clear_all_data()
	_initialize_occupancy_grid(z_levels)
	_reset_push_stats()

func _clear_all_data():
	"""Clear all internal data structures"""
	_occupancy.clear()
	_entity_by_flag.clear()
	_entity_properties.clear()
	_entity_positions.clear()
	_valid_tile_cache.clear()
	_network_authority_cache.clear()

func _initialize_occupancy_grid(z_levels: int):
	"""Initialize occupancy grid for all z-levels"""
	for z in range(z_levels):
		_occupancy[z] = {}
		_entity_by_flag[z] = {}
		
		for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.PUSHABLE, EntityFlags.ANCHORED, EntityFlags.ITEM]:
			_entity_by_flag[z][flag] = {}

func _reset_push_stats():
	"""Reset push statistics."""
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
	"""Find and connect to the SpatialManager if available."""
	var managers = get_tree().get_nodes_in_group("spatial_manager")
	if managers.size() > 0:
		_spatial_manager = managers[0]
		print_log("Connected to SpatialManager", 3)
	else:
		print_log("SpatialManager not found", 2)

func _connect_to_world():
	"""Find and connect to the World if available."""
	_world = get_node_or_null("/root/World")
	
	if _world and _world.has_signal("tile_changed"):
		_world.connect("tile_changed", _on_world_tile_changed)
		print_log("Connected to World", 3)
#endregion

#region MULTIPLAYER NETWORK AUTHORITY
func _is_network_authority_for_entity(entity) -> bool:
	"""Check if this peer has authority over the entity"""
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
	"""Check if multiplayer is currently active"""
	return multiplayer and multiplayer.multiplayer_peer != null

func _is_multiplayer_host() -> bool:
	"""Check if this instance is the multiplayer host"""
	return _is_multiplayer_active() and multiplayer.get_unique_id() == 1

func _should_sync_operation() -> bool:
	"""Check if operations should be synced over network"""
	return enable_multiplayer_sync and _is_multiplayer_active() and multiplayer.get_peers().size() > 0
#endregion

#region ENTITY REGISTRATION AND MANAGEMENT
func register_entity_at_tile(entity, tile_pos: Vector2i, z_level: int) -> bool:
	"""Register an entity at a specific tile position."""
	if not _validate_entity(entity):
		print_log("Invalid entity provided for registration", 1)
		return false
	
	# Check network authority
	if not _is_network_authority_for_entity(entity):
		print_log("No authority to register entity", 2)
		return false
	
	# Ensure z_level exists
	_ensure_z_level_exists(z_level)
	
	# Check if entity is already at this position
	if _is_entity_at_position(entity, tile_pos, z_level):
		return true
	
	# Remove from previous position if registered elsewhere
	_remove_entity_from_previous_position(entity)
	
	# Cache entity properties
	if entity_cache_enabled:
		_cache_entity_properties(entity)
	
	# Register entity in occupancy grid
	if not _register_entity_in_grid(entity, tile_pos, z_level):
		return false
	
	# Sync over network if needed
	if _should_sync_operation():
		_sync_entity_registration.rpc(entity.get_instance_id(), tile_pos, z_level)
	
	# Emit signals
	emit_signal("entity_registered", entity, tile_pos, z_level)
	emit_signal("tile_contents_changed", tile_pos, z_level)
	
	print_log("Entity registered at " + str(tile_pos) + ", z=" + str(z_level), 4)
	return true

@rpc("any_peer", "call_local", "reliable")
func _sync_entity_registration(entity_id: int, tile_pos: Vector2i, z_level: int):
	"""Network sync for entity registration"""
	var entity = instance_from_id(entity_id)
	if not is_instance_valid(entity):
		return
	
	# Only process if we don't have authority (to avoid double registration)
	if _is_network_authority_for_entity(entity):
		return
	
	_register_entity_in_grid(entity, tile_pos, z_level)

func _register_entity_in_grid(entity, tile_pos: Vector2i, z_level: int) -> bool:
	"""Internal method to register entity in the grid"""
	var entity_id = _get_entity_id(entity)
	
	# Ensure tile exists in the dictionary
	if not tile_pos in _occupancy[z_level]:
		_occupancy[z_level][tile_pos] = []
	
	# Add entity to the occupancy grid
	_occupancy[z_level][tile_pos].append(entity)
	
	# Add to flag collections
	var flags = _get_entity_flags(entity)
	_add_entity_to_flag_collections(entity, tile_pos, z_level, flags)
	
	# Update entity position tracking
	_entity_positions[entity_id] = {
		"tile_pos": tile_pos,
		"z_level": z_level
	}
	
	return true

func register_entity(entity) -> bool:
	"""Register an entity at its current position."""
	var position_data = _get_entity_position_data(entity)
	if not position_data.valid:
		print_log("Entity has no valid position for registration", 1)
		return false
	
	return register_entity_at_tile(entity, position_data.tile_pos, position_data.z_level)

func remove_entity(entity, tile_pos: Vector2i, z_level: int) -> bool:
	"""Remove an entity from a specific tile."""
	if not is_instance_valid(entity):
		return _cleanup_invalid_entity_at_tile(tile_pos, z_level)
	
	# Check network authority
	if not _is_network_authority_for_entity(entity):
		print_log("No authority to remove entity", 2)
		return false
	
	if not _remove_entity_from_grid(entity, tile_pos, z_level):
		return false
	
	# Sync over network if needed
	if _should_sync_operation():
		_sync_entity_removal.rpc(entity.get_instance_id(), tile_pos, z_level)
	
	# Emit signals
	emit_signal("entity_unregistered", entity, tile_pos, z_level)
	emit_signal("tile_contents_changed", tile_pos, z_level)
	
	print_log("Entity removed from " + str(tile_pos) + ", z=" + str(z_level), 4)
	return true

@rpc("any_peer", "call_local", "reliable")
func _sync_entity_removal(entity_id: int, tile_pos: Vector2i, z_level: int):
	"""Network sync for entity removal"""
	var entity = instance_from_id(entity_id)
	if is_instance_valid(entity) and _is_network_authority_for_entity(entity):
		return
	
	_remove_entity_from_grid_by_id(entity_id, tile_pos, z_level)

func _remove_entity_from_grid(entity, tile_pos: Vector2i, z_level: int) -> bool:
	"""Internal method to remove entity from grid"""
	if not z_level in _occupancy or not tile_pos in _occupancy[z_level]:
		return false
	
	var entity_id = _get_entity_id(entity)
	
	if entity in _occupancy[z_level][tile_pos]:
		_occupancy[z_level][tile_pos].erase(entity)
		
		# Clean up empty tile
		if _occupancy[z_level][tile_pos].size() == 0:
			_occupancy[z_level].erase(tile_pos)
		
		# Remove from flag collections
		var flags = _get_entity_flags(entity)
		_remove_entity_from_flag_collections(entity, tile_pos, z_level, flags)
		
		# Update tracking
		_entity_positions.erase(entity_id)
		
		return true
	
	return false

func move_entity(entity, from_pos: Vector2i, to_pos: Vector2i, z_level: int) -> bool:
	"""Move an entity from one tile to another on the same z-level."""
	if not _validate_entity(entity) or from_pos == to_pos:
		return from_pos == to_pos  # True if same position, false if invalid
	
	# Check network authority
	if not _is_network_authority_for_entity(entity):
		print_log("No authority to move entity", 2)
		return false
	
	if not _is_valid_tile(to_pos, z_level):
		print_log("Target tile is invalid", 2)
		return false
	
	if not _move_entity_in_grid(entity, from_pos, to_pos, z_level):
		return false
	
	# Sync over network if needed
	if _should_sync_operation():
		_sync_entity_movement.rpc(entity.get_instance_id(), from_pos, to_pos, z_level)
	
	# Emit signals
	emit_signal("entity_moved", entity, from_pos, to_pos, z_level)
	emit_signal("tile_contents_changed", from_pos, z_level)
	emit_signal("tile_contents_changed", to_pos, z_level)
	
	print_log("Entity moved from " + str(from_pos) + " to " + str(to_pos), 4)
	return true

@rpc("any_peer", "call_local", "reliable")
func _sync_entity_movement(entity_id: int, from_pos: Vector2i, to_pos: Vector2i, z_level: int):
	"""Network sync for entity movement"""
	var entity = instance_from_id(entity_id)
	if not is_instance_valid(entity) or _is_network_authority_for_entity(entity):
		return
	
	_move_entity_in_grid(entity, from_pos, to_pos, z_level)

func _move_entity_in_grid(entity, from_pos: Vector2i, to_pos: Vector2i, z_level: int) -> bool:
	"""Internal method to move entity in grid"""
	var entity_id = _get_entity_id(entity)
	
	# Check if entity is at from_pos
	if not (z_level in _occupancy and from_pos in _occupancy[z_level] and entity in _occupancy[z_level][from_pos]):
		# Entity not found at from_pos, just register at to_pos
		return _register_entity_in_grid(entity, to_pos, z_level)
	
	# Remove from old position
	_occupancy[z_level][from_pos].erase(entity)
	if _occupancy[z_level][from_pos].size() == 0:
		_occupancy[z_level].erase(from_pos)
	
	# Add to new position
	if not to_pos in _occupancy[z_level]:
		_occupancy[z_level][to_pos] = []
	_occupancy[z_level][to_pos].append(entity)
	
	# Update flag collections
	var flags = _get_entity_flags(entity)
	_remove_entity_from_flag_collections(entity, from_pos, z_level, flags)
	_add_entity_to_flag_collections(entity, to_pos, z_level, flags)
	
	# Update tracking
	_entity_positions[entity_id] = {
		"tile_pos": to_pos,
		"z_level": z_level
	}
	
	return true
#endregion

#region COLLISION AND MOVEMENT
func try_move_entity(entity, direction: Vector2i, z_level: int) -> Dictionary:
	"""Try to move an entity in a direction, handling collisions."""
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
	
	# Check if target is valid
	if not _is_valid_tile(target_tile, z_level):
		result.collision_type = CollisionType.WALL
		return result
	
	# Check for collisions
	var collision = check_collision(target_tile, z_level, entity)
	
	if collision.type == CollisionType.NONE:
		# No collision, move entity
		if move_entity(entity, current_tile, target_tile, z_level):
			result.success = true
			result.new_position = target_tile
	else:
		# Handle collision
		result.collision = collision.entity
		result.collision_type = collision.type
		
		# Try to push if blocked by entity
		if collision.type == CollisionType.ENTITY and collision.entity != null:
			var push_result = try_push_entity(entity, collision.entity, direction)
			
			if push_result.success:
				if move_entity(entity, current_tile, target_tile, z_level):
					result.success = true
					result.new_position = target_tile
			
			emit_signal("entities_collided", entity, collision.entity, target_tile, z_level)
	
	return result

func try_push_entity(pusher, target, direction: Vector2i) -> Dictionary:
	"""Try to push an entity in a direction."""
	var result = {
		"success": false,
		"result_code": PushResult.FAILED_DENSE,
		"force_applied": 0.0
	}
	
	_push_stats.attempts += 1
	
	if not _validate_entity(pusher) or not _validate_entity(target):
		return result
	
	# Check if target can be pushed
	if not _can_entity_be_pushed(target):
		result.result_code = PushResult.FAILED_IMMOVABLE
		_push_stats.failures.immovable += 1
		_emit_push_result(pusher, target, direction, PushResult.FAILED_IMMOVABLE, 0.0)
		return result
	
	# Check if target is anchored
	if _is_entity_anchored(target):
		result.result_code = PushResult.FAILED_ANCHORED
		_push_stats.failures.anchored += 1
		_emit_push_result(pusher, target, direction, PushResult.FAILED_ANCHORED, 0.0)
		return result
	
	# Calculate push mechanics
	var target_position = get_entity_tile(target)
	var target_z = get_entity_z_level(target)
	var push_target = target_position + direction
	
	if not can_entity_move_to(target, push_target, target_z):
		result.result_code = PushResult.FAILED_NO_SPACE
		_push_stats.failures.no_space += 1
		_emit_push_result(pusher, target, direction, PushResult.FAILED_NO_SPACE, 0.0)
		return result
	
	# Calculate forces
	var effective_force = _get_entity_push_force(pusher) * push_force_scale
	var mass_resistance = _get_entity_mass(target) * mass_factor
	
	if mass_resistance > push_threshold and effective_force < mass_resistance:
		result.result_code = PushResult.FAILED_TOO_HEAVY
		_push_stats.failures.too_heavy += 1
		_emit_push_result(pusher, target, direction, PushResult.FAILED_TOO_HEAVY, effective_force)
		return result
	
	# Execute push
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
	
	return result

func _emit_push_result(pusher, target, direction: Vector2i, result_code: PushResult, force: float):
	"""Emit push attempt signal and sync if needed"""
	emit_signal("push_attempted", pusher, target, direction, result_code, force)
	
	if sync_push_attempts and _should_sync_operation():
		_sync_push_attempt.rpc(pusher.get_instance_id(), target.get_instance_id(), direction, result_code, force)

@rpc("any_peer", "call_local", "reliable")
func _sync_push_attempt(pusher_id: int, target_id: int, direction: Vector2i, result_code: PushResult, force: float):
	"""Network sync for push attempts"""
	var pusher = instance_from_id(pusher_id)
	var target = instance_from_id(target_id)
	
	if is_instance_valid(pusher) and is_instance_valid(target):
		emit_signal("push_attempted", pusher, target, direction, result_code, force)

func check_collision(tile_pos: Vector2i, z_level: int, exclude_entity = null) -> Dictionary:
	"""Check for collision at a target tile."""
	var result = {
		"type": CollisionType.NONE,
		"entity": null,
		"tile": tile_pos
	}
	
	# Check tile validity
	if not _is_valid_tile(tile_pos, z_level):
		result.type = CollisionType.WALL
		return result
	
	# Check world-based obstacles
	if _check_world_obstacles(tile_pos, z_level, result):
		return result
	
	# Check for entities
	var entities = get_entities_at(tile_pos, z_level)
	for entity in entities:
		if entity == exclude_entity or not is_instance_valid(entity):
			continue
		
		# Check for doors first
		if _is_door_entity(entity):
			if _is_door_closed(entity):
				result.type = CollisionType.DOOR_CLOSED
				result.entity = entity
				return result
		# Check for dense entities
		elif _is_entity_dense(entity):
			result.type = CollisionType.ENTITY
			result.entity = entity
			return result
	
	return result

func _check_world_obstacles(tile_pos: Vector2i, z_level: int, result: Dictionary) -> bool:
	"""Check for world-based obstacles and update result if found"""
	if not _world:
		return false
	
	if _world.has_method("is_wall_at") and _world.is_wall_at(tile_pos, z_level):
		result.type = CollisionType.WALL
		return true
	
	if _world.has_method("is_closed_door_at") and _world.is_closed_door_at(tile_pos, z_level):
		result.type = CollisionType.DOOR_CLOSED
		return true
	
	if _world.has_method("is_window_at") and _world.is_window_at(tile_pos, z_level):
		result.type = CollisionType.WINDOW
		return true
	
	return false

func can_entity_move_to(entity, tile_pos: Vector2i, z_level: int) -> bool:
	"""Check if an entity can move to a specific tile."""
	if not _is_valid_tile(tile_pos, z_level):
		return false
	
	var collision = check_collision(tile_pos, z_level, entity)
	return collision.type == CollisionType.NONE
#endregion

#region ENTITY QUERIES AND HELPERS
func get_entities_at(tile_pos: Vector2i, z_level: int) -> Array:
	"""Get all entities at a specific tile."""
	if not z_level in _occupancy or not tile_pos in _occupancy[z_level]:
		return []
	
	return _occupancy[z_level][tile_pos].duplicate()

func get_entity_at(tile_pos: Vector2i, z_level: int, type_name: String = ""):
	"""Get the first entity (or of a specific type) at a tile."""
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
	"""Check if a tile has any dense entities (excluding the specified entity)."""
	if z_level in _entity_by_flag and EntityFlags.DENSE in _entity_by_flag[z_level] and tile_pos in _entity_by_flag[z_level][EntityFlags.DENSE]:
		for entity in _entity_by_flag[z_level][EntityFlags.DENSE][tile_pos]:
			if entity != excluding_entity and is_instance_valid(entity):
				return true
	
	return false

func get_entity_position(entity) -> Dictionary:
	"""Get an entity's current registered position."""
	var entity_id = _get_entity_id(entity)
	
	if entity_id in _entity_positions:
		return _entity_positions[entity_id].duplicate()
	
	return {"valid": false}

func get_entity_tile(entity) -> Vector2i:
	"""Get an entity's current tile position."""
	var entity_id = _get_entity_id(entity)
	
	if entity_id in _entity_positions:
		return _entity_positions[entity_id].tile_pos
	
	var position_data = _get_entity_position_data(entity)
	if position_data.valid:
		return position_data.tile_pos
	
	return Vector2i(-1, -1)

func get_entity_z_level(entity) -> int:
	"""Get an entity's current z-level."""
	var entity_id = _get_entity_id(entity)
	
	if entity_id in _entity_positions:
		return _entity_positions[entity_id].z_level
	
	var position_data = _get_entity_position_data(entity)
	if position_data.valid:
		return position_data.z_level
	
	return -1

func raycast(start_tile: Vector2i, end_tile: Vector2i, z_level: int) -> Dictionary:
	"""Cast a ray from start to end, stopping at the first collision."""
	var result = {
		"hit": false,
		"hit_pos": null,
		"hit_entity": null,
		"hit_tile": null,
		"tiles": []
	}
	
	var tiles = _get_tiles_in_line(start_tile, end_tile)
	result.tiles = tiles
	
	# Skip the starting tile and limit distance
	if tiles.size() > 1:
		tiles.remove_at(0)
		
	# Limit raycast distance
	if tiles.size() > RAYCAST_MAX_DISTANCE:
		tiles = tiles.slice(0, RAYCAST_MAX_DISTANCE)
	
	# Check each tile for collision
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
#endregion

#region UTILITY FUNCTIONS
func world_to_tile(world_pos: Vector2) -> Vector2i:
	"""Convert world position to tile position."""
	if _world and _world.has_method("get_tile_at"):
		return _world.get_tile_at(world_pos)
	
	return Vector2i(int(world_pos.x / TILE_SIZE), int(world_pos.y / TILE_SIZE))

func tile_to_world(tile_pos: Vector2i) -> Vector2:
	"""Convert tile position to world position (center of tile)."""
	if _world and _world.has_method("tile_to_world"):
		return _world.tile_to_world(tile_pos)
	
	return Vector2(
		(tile_pos.x * TILE_SIZE) + (TILE_SIZE / 2),
		(tile_pos.y * TILE_SIZE) + (TILE_SIZE / 2)
	)

func clean_invalid_entities() -> int:
	"""Clean up any invalid entity references."""
	var removed_count = 0
	
	for z in _occupancy.keys():
		var tiles_to_check = _occupancy[z].keys().duplicate()
		
		for tile_pos in tiles_to_check:
			if _cleanup_invalid_entity_at_tile(tile_pos, z):
				removed_count += 1
	
	_cleanup_entity_cache()
	
	if removed_count > 0:
		print_log("Cleaned up " + str(removed_count) + " invalid entity references", 2)
	
	return removed_count

func get_debug_stats() -> Dictionary:
	"""Get detailed statistics about the system."""
	return {
		"total_entities": get_entity_count(),
		"occupied_tiles": get_occupied_tile_count(),
		"cached_entities": _entity_properties.size() if entity_cache_enabled else 0,
		"z_levels": _get_z_level_stats(),
		"push_stats": get_push_stats(),
		"flag_counts": _get_flag_counts(),
		"network_active": _is_multiplayer_active(),
		"is_host": _is_multiplayer_host()
	}

func print_log(message: String, level: int = 3):
	"""Print a log message based on log level."""
	if level <= log_level:
		var prefix = ["", "[ERROR] ", "[WARN] ", "[INFO] ", "[DEBUG] "][level]
		if debug_mode:
			print(prefix + "TileOccupancySystem: " + message)
#endregion

#region PRIVATE HELPER METHODS
func _ensure_z_level_exists(z_level: int):
	"""Ensure a z-level exists in the data structures"""
	if not z_level in _occupancy:
		_occupancy[z_level] = {}
		_entity_by_flag[z_level] = {}
		
		for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.PUSHABLE, EntityFlags.ANCHORED, EntityFlags.ITEM]:
			_entity_by_flag[z_level][flag] = {}

func _is_entity_at_position(entity, tile_pos: Vector2i, z_level: int) -> bool:
	"""Check if entity is already at the specified position"""
	var entity_id = _get_entity_id(entity)
	if entity_id in _entity_positions:
		var current_pos = _entity_positions[entity_id]
		return current_pos.tile_pos == tile_pos and current_pos.z_level == z_level
	return false

func _remove_entity_from_previous_position(entity):
	"""Remove entity from its previous position if registered elsewhere"""
	var entity_id = _get_entity_id(entity)
	if entity_id in _entity_positions:
		var current_pos = _entity_positions[entity_id]
		remove_entity(entity, current_pos.tile_pos, current_pos.z_level)

func _add_entity_to_flag_collections(entity, tile_pos: Vector2i, z_level: int, flags: int):
	"""Add entity to appropriate flag collections"""
	for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.PUSHABLE, EntityFlags.ANCHORED, EntityFlags.ITEM]:
		if flags & flag:
			if not tile_pos in _entity_by_flag[z_level][flag]:
				_entity_by_flag[z_level][flag][tile_pos] = []
			_entity_by_flag[z_level][flag][tile_pos].append(entity)

func _remove_entity_from_flag_collections(entity, tile_pos: Vector2i, z_level: int, flags: int):
	"""Remove entity from flag collections"""
	for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.PUSHABLE, EntityFlags.ANCHORED, EntityFlags.ITEM]:
		if flags & flag and tile_pos in _entity_by_flag[z_level][flag]:
			_entity_by_flag[z_level][flag][tile_pos].erase(entity)
			if _entity_by_flag[z_level][flag][tile_pos].size() == 0:
				_entity_by_flag[z_level][flag].erase(tile_pos)

func _remove_entity_from_grid_by_id(entity_id: int, tile_pos: Vector2i, z_level: int):
	"""Remove entity from grid by ID (for network sync)"""
	if not z_level in _occupancy or not tile_pos in _occupancy[z_level]:
		return
	
	var entity_to_remove = null
	for entity in _occupancy[z_level][tile_pos]:
		if _get_entity_id(entity) == entity_id:
			entity_to_remove = entity
			break
	
	if entity_to_remove:
		_remove_entity_from_grid(entity_to_remove, tile_pos, z_level)

func _cache_entity_properties(entity):
	"""Cache entity properties for faster access."""
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
	"""Clean up old entries in entity cache"""
	if not entity_cache_enabled:
		return
	
	var current_time = Time.get_ticks_msec()
	var ids_to_remove = []
	
	for entity_id in _entity_properties.keys():
		var cache_entry = _entity_properties[entity_id]
		
		# Remove if entity is invalid or cache is too old
		if entity_id is int:
			var entity = instance_from_id(entity_id)
			if not is_instance_valid(entity):
				ids_to_remove.append(entity_id)
				continue
		
		# Remove old cache entries
		if current_time - cache_entry.last_update_time > ENTITY_CACHE_CLEANUP_INTERVAL * 1000:
			ids_to_remove.append(entity_id)
	
	for entity_id in ids_to_remove:
		_entity_properties.erase(entity_id)
		_entity_positions.erase(entity_id)
	
	# Limit cache size
	if _entity_properties.size() > MAX_CACHED_ENTITIES:
		var sorted_entries = []
		for entity_id in _entity_properties.keys():
			sorted_entries.append([entity_id, _entity_properties[entity_id].last_update_time])
		
		sorted_entries.sort_custom(func(a, b): return a[1] < b[1])
		
		var excess_count = _entity_properties.size() - MAX_CACHED_ENTITIES
		for i in range(excess_count):
			var entity_id = sorted_entries[i][0]
			_entity_properties.erase(entity_id)
			_entity_positions.erase(entity_id)

func _cleanup_invalid_entity_at_tile(tile_pos: Vector2i, z_level: int) -> bool:
	"""Clean up any invalid entities at a specific tile."""
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
		
		# Clean up flag collections
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

func _validate_entity(entity) -> bool:
	"""Validate that an entity can be used in the system."""
	return is_instance_valid(entity) and "position" in entity

func _get_entity_id(entity):
	"""Get a reliable entity identifier."""
	if not is_instance_valid(entity):
		return "INVALID"
	
	if "entity_id" in entity and entity.entity_id:
		return entity.entity_id
	
	return entity.get_instance_id()

func _get_entity_property(entity, property_name: String, default_value = null):
	"""Safely get an entity property with fallback."""
	if not is_instance_valid(entity):
		return default_value
	
	if property_name in entity:
		return entity[property_name]
	elif entity.has_method(property_name):
		return entity.call(property_name)
	else:
		return default_value

func _get_entity_position_data(entity) -> Dictionary:
	"""Get an entity's position and z-level."""
	if not is_instance_valid(entity):
		return {"valid": false}
	
	var result = {
		"valid": true,
		"position": Vector2.ZERO,
		"tile_pos": Vector2i.ZERO,
		"z_level": 0
	}
	
	# Get world position
	if entity.has_method("global_position"):
		result.position = entity.global_position
	elif "position" in entity:
		result.position = entity.position
	else:
		return {"valid": false}
	
	result.tile_pos = world_to_tile(result.position)
	
	# Get z-level
	if "current_z_level" in entity:
		result.z_level = entity.current_z_level
	elif "z_level" in entity:
		result.z_level = entity.z_level
	elif entity is Node2D:
		result.z_level = entity.z_index
	
	return result

func _is_entity_dense(entity) -> bool:
	"""Check if an entity is dense (has collision)."""
	if not is_instance_valid(entity):
		return false
	
	var entity_id = _get_entity_id(entity)
	
	if entity_cache_enabled and entity_id in _entity_properties:
		return _entity_properties[entity_id].dense
	
	return _is_entity_dense_direct(entity)

func _is_entity_dense_direct(entity) -> bool:
	"""Check entity density directly (no caching)."""
	if _get_entity_property(entity, "entity_type") == "item":
		var explicit_density = _get_entity_property(entity, "entity_dense", null)
		if explicit_density != null:
			return explicit_density
		return false
	
	return _get_entity_property(entity, "entity_dense", true)

func _get_entity_flags(entity) -> int:
	"""Calculate entity flags based on its properties."""
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
	"""Check if an entity can be pushed."""
	var entity_id = _get_entity_id(entity)
	
	if entity_cache_enabled and entity_id in _entity_properties:
		return _entity_properties[entity_id].can_be_pushed
	
	return _get_entity_property(entity, "can_be_pushed", true)

func _is_entity_anchored(entity) -> bool:
	"""Check if an entity is anchored (can't be moved)."""
	return _get_entity_property(entity, "anchored", false)

func _get_entity_push_force(entity) -> float:
	"""Get an entity's push force."""
	var entity_id = _get_entity_id(entity)
	
	if entity_cache_enabled and entity_id in _entity_properties:
		return _entity_properties[entity_id].push_force
	
	return _get_entity_property(entity, "push_force", 1.0)

func _get_entity_mass(entity) -> float:
	"""Get an entity's mass."""
	var entity_id = _get_entity_id(entity)
	
	if entity_cache_enabled and entity_id in _entity_properties:
		return _entity_properties[entity_id].mass
	
	return _get_entity_property(entity, "mass", 10.0)

func _notify_entity_pushed(target, pusher, direction: Vector2i):
	"""Notify target entity that it was pushed"""
	if target.has_method("pushed"):
		target.pushed(pusher, direction)

func _is_door_entity(entity) -> bool:
	"""Check if entity is a door"""
	return entity.is_in_group("doors") or _get_entity_property(entity, "entity_type") == "door"

func _is_door_closed(entity) -> bool:
	"""Check if door entity is closed"""
	return "is_open" in entity and not entity.is_open

func _is_valid_tile(tile_pos: Vector2i, z_level: int) -> bool:
	"""Check if a tile is valid (exists in the world)."""
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
	"""Get tiles along a line using Bresenham's algorithm."""
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
	"""Draw visual debug information"""
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

func get_entity_count(z_level = null) -> int:
	"""Get total number of entities being tracked."""
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
	"""Get number of occupied tiles."""
	if z_level == null:
		var count = 0
		for z in _occupancy.keys():
			count += _occupancy[z].keys().size()
		return count
	elif z_level in _occupancy:
		return _occupancy[z_level].keys().size()
	
	return 0

func get_push_stats() -> Dictionary:
	"""Get statistics about pushing attempts."""
	var success_rate = 0.0
	if _push_stats.attempts > 0:
		success_rate = float(_push_stats.successes) / float(_push_stats.attempts)
	
	var stats = _push_stats.duplicate(true)
	stats.success_rate = success_rate
	return stats

func _get_z_level_stats() -> Dictionary:
	"""Get statistics for each z-level"""
	var stats = {}
	for z in _occupancy.keys():
		stats[z] = {
			"tiles": _occupancy[z].keys().size(),
			"entities": get_entity_count(z)
		}
	return stats

func _get_flag_counts() -> Dictionary:
	"""Get entity counts by flag type"""
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
#endregion

#region SIGNAL HANDLERS
func _on_world_tile_changed(tile_coords, z_level, old_data, new_data):
	"""Handle tile data changes from World."""
	var cache_key = str(tile_coords) + "_" + str(z_level)
	_valid_tile_cache.erase(cache_key)
	
	# Clear cache for surrounding tiles if blocking status changed
	var old_blocked = _is_tile_data_blocked(old_data)
	var new_blocked = _is_tile_data_blocked(new_data)
	
	if old_blocked != new_blocked:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var neighbor = tile_coords + Vector2i(dx, dy)
				var neighbor_key = str(neighbor) + "_" + str(z_level)
				_valid_tile_cache.erase(neighbor_key)

func _is_tile_data_blocked(tile_data) -> bool:
	"""Check if tile data represents a blocked tile"""
	if not tile_data:
		return false
	
	if "wall" in tile_data and tile_data.wall != null:
		return true
	
	if "door" in tile_data and "closed" in tile_data.door and tile_data.door.closed:
		return true
	
	return false

func _on_peer_connected(peer_id: int):
	"""Handle new peer connection"""
	print_log("Peer connected: " + str(peer_id), 3)

func _on_peer_disconnected(peer_id: int):
	"""Handle peer disconnection"""
	print_log("Peer disconnected: " + str(peer_id), 3)
	# Clean up any entities belonging to this peer
	_cleanup_peer_entities(peer_id)

func _cleanup_peer_entities(peer_id: int):
	"""Clean up entities belonging to a disconnected peer"""
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
			remove_entity(entity, pos.tile_pos, pos.z_level)
#endregion
