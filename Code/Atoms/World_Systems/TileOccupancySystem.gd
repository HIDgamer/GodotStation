extends Node2D
class_name TileOccupancySystem

#region CONSTANTS AND ENUMS
const TILE_SIZE = 32  # Size of a tile in pixels
const MAX_Z_LEVELS = 10  # Maximum number of z-levels

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
#endregion

#region PROPERTIES AND SIGNALS
# Primary occupancy grid - organized by z-level then by Vector2i tile coordinate
# Format: _occupancy[z_level][Vector2i(x,y)] = [entity1, entity2, ...]
var _occupancy = {}

# Secondary organization by entity properties for faster queries
# Format: _entity_by_flag[z_level][flag][Vector2i(x,y)] = [entity1, entity2, ...]
var _entity_by_flag = {}

# Entity properties cache for optimized lookups
# Format: _entity_properties[entity.get_instance_id()] = {dense, can_push, mass, etc}
var _entity_properties = {}

# Entity position tracking
# Format: _entity_positions[entity.get_instance_id()] = {tile_pos, z_level}
var _entity_positions = {}

# Push statistics for debugging and balancing
var _push_stats = {
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

# Settings
@export_group("System Settings")
@export var auto_initialize: bool = true
@export var initialize_z_levels: int = 10
@export var entity_cache_enabled: bool = true
@export var spatial_manager_integration: bool = true

@export_subgroup("Physics Settings")
@export var mass_factor: float = 0.2  # How much mass affects pushing
@export var push_force_scale: float = 1.0  # Global scale for push forces
@export var push_threshold: float = 15.0  # Minimum force needed to push heavy objects

@export_subgroup("Debug Settings")
@export var debug_mode: bool = false
@export var visual_debug: bool = false
@export var log_level: int = 1  # 0=none, 1=errors, 2=warnings, 3=info, 4=verbose
@export var debug_show_grid: bool = false
@export var debug_collisions: bool = false

# References to other systems
var _spatial_manager = null
var _world = null

# Cache for tile validity checking
var _valid_tile_cache = {}

# Signals
signal entity_registered(entity, tile_pos, z_level)
signal entity_unregistered(entity, tile_pos, z_level)
signal entity_moved(entity, from_pos, to_pos, z_level)
signal entities_collided(entity1, entity2, tile_pos, z_level)
signal push_attempted(pusher, target, direction, result, force)
signal tile_contents_changed(tile_pos, z_level)
#endregion

#region LIFECYCLE METHODS
func _ready():
	# Initialize the system
	if auto_initialize:
		initialize(initialize_z_levels)
	
	# Set up debugging
	if visual_debug:
		set_process(true)
	else:
		set_process(false)
	
	# Set up signal connections
	if spatial_manager_integration:
		_connect_to_spatial_manager()
	
	# Connect to world system if available
	_connect_to_world()
	
	# Register with groups for easy access
	add_to_group("tile_occupancy_system")
	
	# Log initialization
	if debug_mode:
		print_debug("ImprovedTileOccupancySystem initialized")

func _process(_delta):
	# Only used when visual debug is enabled
	if visual_debug:
		queue_redraw()

func _physics_process(_delta):
	# Process any physics-based operations here
	pass

func _draw():
	# Visual debugging
	if not visual_debug or not debug_show_grid:
		return
	
	# Get visible screen area
	var viewport_rect = get_viewport_rect()
	var camera_pos = Vector2.ZERO
	
	# Try to get camera if available
	var camera = get_viewport().get_camera_2d()
	if camera:
		camera_pos = camera.global_position
	
	# Calculate visible area in tile coordinates
	var screen_size = get_viewport_rect().size
	var top_left = camera_pos - screen_size/2
	var bottom_right = camera_pos + screen_size/2
	
	# Convert to tile coordinates
	var start_tile = world_to_tile(top_left)
	var end_tile = world_to_tile(bottom_right)
	
	# Get the current z level
	var z_level = 0
	if _world and "current_z_level" in _world:
		z_level = _world.current_z_level
	
	# Ensure the z-level exists
	if not z_level in _occupancy:
		return
	
	# Draw occupied tiles in the visible area
	for y in range(start_tile.y - 1, end_tile.y + 2):
		for x in range(start_tile.x - 1, end_tile.x + 2):
			var tile_pos = Vector2i(x, y)
			
			# Skip if tile is not occupied
			if not tile_pos in _occupancy[z_level]:
				continue
			
			var entities = _occupancy[z_level][tile_pos]
			var entity_count = entities.size()
			
			# Skip empty tiles
			if entity_count == 0:
				continue
			
			# Check for dense entities
			var has_dense = false
			for entity in entities:
				if _is_entity_dense(entity):
					has_dense = true
					break
			
			# Choose color based on contents
			var color = Color(0, 1, 0, 0.3)  # Green for normal tiles
			if has_dense:
				color = Color(1, 0, 0, 0.3)  # Red for tiles with dense entities
			
			# Draw tile
			var world_pos = tile_to_world(tile_pos)
			draw_rect(Rect2(world_pos - Vector2(TILE_SIZE/2, TILE_SIZE/2), Vector2(TILE_SIZE, TILE_SIZE)), color, false, 2)
			
			# Draw entity count
			var label_pos = world_pos - Vector2(TILE_SIZE/4, 0)
			draw_string(ThemeDB.fallback_font, label_pos, str(entity_count), HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color.WHITE)
#endregion

#region INITIALIZATION
func initialize(z_levels: int = MAX_Z_LEVELS):
	"""Initialize the tile occupancy system."""
	print_log("Initializing with " + str(z_levels) + " z-levels", 3)
	
	# Clear existing data
	_occupancy.clear()
	_entity_by_flag.clear()
	_entity_properties.clear()
	_entity_positions.clear()
	_valid_tile_cache.clear()
	
	# Initialize occupancy grid for all z-levels
	for z in range(z_levels):
		_occupancy[z] = {}
		_entity_by_flag[z] = {}
		
		# Initialize flags for each z-level
		for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.PUSHABLE, EntityFlags.ANCHORED, EntityFlags.ITEM]:
			_entity_by_flag[z][flag] = {}
	
	# Reset push statistics
	_reset_push_stats()

func _connect_to_spatial_manager():
	"""Find and connect to the SpatialManager if available."""
	# Search in parent nodes
	_spatial_manager = get_node_or_null("../SpatialManager")
	if not _spatial_manager:
		_spatial_manager = get_node_or_null("../ImprovedSpatialManager")
	
	# Search as sibling
	if not _spatial_manager:
		_spatial_manager = get_node_or_null("SpatialManager")
	
	# Search in scene using groups
	if not _spatial_manager:
		var managers = get_tree().get_nodes_in_group("spatial_manager")
		if managers.size() > 0:
			_spatial_manager = managers[0]
	
	if _spatial_manager:
		print_log("Connected to SpatialManager", 3)
	else:
		print_log("SpatialManager not found", 2)

func _connect_to_world():
	"""Find and connect to the World if available."""
	# Try to find the World node
	_world = get_node_or_null("/root/World")
	
	if _world:
		# Connect to relevant signals
		if _world.has_signal("tile_changed") and not _world.is_connected("tile_changed", Callable(self, "_on_world_tile_changed")):
			_world.connect("tile_changed", Callable(self, "_on_world_tile_changed"))
		
		print_log("Connected to World", 3)
	else:
		print_log("World not found", 2)

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
#endregion

#region ENTITY REGISTRATION AND MANAGEMENT
func register_entity_at_tile(entity, tile_pos: Vector2i, z_level: int) -> bool:
	"""Register an entity at a specific tile position."""
	# Validate input
	if not _validate_entity(entity):
		print_log("Invalid entity provided for registration", 1)
		return false
	
	# Make sure z_level exists
	if not z_level in _occupancy:
		_occupancy[z_level] = {}
		_entity_by_flag[z_level] = {}
		for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.PUSHABLE, EntityFlags.ANCHORED, EntityFlags.ITEM]:
			_entity_by_flag[z_level][flag] = {}
	
	# Check if entity is already at this tile
	var entity_id = _get_entity_id(entity)
	if entity_id in _entity_positions:
		var current_pos = _entity_positions[entity_id]
		if current_pos.tile_pos == tile_pos and current_pos.z_level == z_level:
			return true  # Already registered at this position
	
	# If entity is registered elsewhere, unregister it first
	if entity_id in _entity_positions:
		var current_pos = _entity_positions[entity_id]
		remove_entity(entity, current_pos.tile_pos, current_pos.z_level)
	
	# Create the entity property cache
	if entity_cache_enabled and not entity_id in _entity_properties:
		_cache_entity_properties(entity)
	
	# Ensure tile exists in the dictionary
	if not tile_pos in _occupancy[z_level]:
		_occupancy[z_level][tile_pos] = []
	
	# Add entity to the occupancy grid
	_occupancy[z_level][tile_pos].append(entity)
	
	# Add to flag collections
	var flags = _get_entity_flags(entity)
	for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.PUSHABLE, EntityFlags.ANCHORED, EntityFlags.ITEM]:
		if flags & flag:
			if not tile_pos in _entity_by_flag[z_level][flag]:
				_entity_by_flag[z_level][flag][tile_pos] = []
			_entity_by_flag[z_level][flag][tile_pos].append(entity)
	
	# Update entity position tracking
	_entity_positions[entity_id] = {
		"tile_pos": tile_pos,
		"z_level": z_level
	}
	
	# Emit signals
	emit_signal("entity_registered", entity, tile_pos, z_level)
	emit_signal("tile_contents_changed", tile_pos, z_level)
	
	print_log("Entity registered at " + str(tile_pos) + ", z=" + str(z_level), 4)
	
	return true

func register_entity(entity) -> bool:
	"""Register an entity at its current position."""
	# Get entity position
	var position_data = _get_entity_position_data(entity)
	if not position_data.valid:
		print_log("Entity has no valid position for registration", 1)
		return false
	
	# Register at current position
	return register_entity_at_tile(entity, position_data.tile_pos, position_data.z_level)

func remove_entity(entity, tile_pos: Vector2i, z_level: int) -> bool:
	"""Remove an entity from a specific tile."""
	# Check if entity is valid
	if not is_instance_valid(entity):
		# Special handling for invalid entities - try to clean them up
		return _cleanup_invalid_entity_at_tile(tile_pos, z_level)
	
	# Ensure z_level exists
	if not z_level in _occupancy:
		return false
	
	# Ensure tile exists
	if not tile_pos in _occupancy[z_level]:
		return false
	
	# Get entity ID
	var entity_id = _get_entity_id(entity)
	
	# Remove from occupancy grid
	if entity in _occupancy[z_level][tile_pos]:
		_occupancy[z_level][tile_pos].erase(entity)
		
		# Remove tile if empty
		if _occupancy[z_level][tile_pos].size() == 0:
			_occupancy[z_level].erase(tile_pos)
		
		# Remove from flag collections
		var flags = _get_entity_flags(entity)
		for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.PUSHABLE, EntityFlags.ANCHORED, EntityFlags.ITEM]:
			if flags & flag and tile_pos in _entity_by_flag[z_level][flag]:
				_entity_by_flag[z_level][flag][tile_pos].erase(entity)
				if _entity_by_flag[z_level][flag][tile_pos].size() == 0:
					_entity_by_flag[z_level][flag].erase(tile_pos)
		
		# Update tracking
		_entity_positions.erase(entity_id)
		
		# Emit signals
		emit_signal("entity_unregistered", entity, tile_pos, z_level)
		emit_signal("tile_contents_changed", tile_pos, z_level)
		
		print_log("Entity removed from " + str(tile_pos) + ", z=" + str(z_level), 4)
		
		return true
	
	return false

func has_lying_entity_at(tile_pos: Vector2i, z_level: int) -> bool:
	"""Check if a tile has any lying entities"""
	if not z_level in _occupancy or not tile_pos in _occupancy[z_level]:
		return false
	
	for entity in _occupancy[z_level][tile_pos]:
		if not is_instance_valid(entity):
			continue
		
		if "is_lying" in entity and entity.is_lying:
			return true
		elif entity.has_method("get") and entity.get("is_lying"):
			if entity.get("is_lying"):
				return true
	
	return false

func unregister_entity(entity) -> bool:
	"""Unregister an entity from anywhere it might be registered."""
	# Check if entity is valid
	if not is_instance_valid(entity):
		print_log("Trying to unregister invalid entity", 2)
		return false
	
	# Get entity ID
	var entity_id = _get_entity_id(entity)
	
	# Check if we know where this entity is
	if entity_id in _entity_positions:
		var pos_data = _entity_positions[entity_id]
		var result = remove_entity(entity, pos_data.tile_pos, pos_data.z_level)
		
		# Clean up entity cache
		if entity_cache_enabled and entity_id in _entity_properties:
			_entity_properties.erase(entity_id)
		
		return result
	
	# If we don't know the position, search for the entity
	print_log("Entity position unknown, searching all tiles", 3)
	return _find_and_remove_entity(entity)

func move_entity(entity, from_pos: Vector2i, to_pos: Vector2i, z_level: int) -> bool:
	"""Move an entity from one tile to another on the same z-level."""
	# Check if entity is valid
	if not _validate_entity(entity):
		print_log("Invalid entity provided for movement", 1)
		return false
	
	# Check if tiles are the same
	if from_pos == to_pos:
		return true  # Nothing to do
	
	# Check if the target tile is valid
	if not _is_valid_tile(to_pos, z_level):
		print_log("Target tile is invalid", 2)
		return false
	
	# Get entity ID
	var entity_id = _get_entity_id(entity)
	
	# First check if entity is at from_pos
	if z_level in _occupancy and from_pos in _occupancy[z_level] and entity in _occupancy[z_level][from_pos]:
		# Remove from old position
		_occupancy[z_level][from_pos].erase(entity)
		if _occupancy[z_level][from_pos].size() == 0:
			_occupancy[z_level].erase(from_pos)
		
		# Remove from old flag collections
		var flags = _get_entity_flags(entity)
		for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.PUSHABLE, EntityFlags.ANCHORED, EntityFlags.ITEM]:
			if flags & flag and from_pos in _entity_by_flag[z_level][flag]:
				_entity_by_flag[z_level][flag][from_pos].erase(entity)
				if _entity_by_flag[z_level][flag][from_pos].size() == 0:
					_entity_by_flag[z_level][flag].erase(from_pos)
		
		# Add to new position
		if not to_pos in _occupancy[z_level]:
			_occupancy[z_level][to_pos] = []
		_occupancy[z_level][to_pos].append(entity)
		
		# Add to new flag collections
		for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.PUSHABLE, EntityFlags.ANCHORED, EntityFlags.ITEM]:
			if flags & flag:
				if not to_pos in _entity_by_flag[z_level][flag]:
					_entity_by_flag[z_level][flag][to_pos] = []
				_entity_by_flag[z_level][flag][to_pos].append(entity)
		
		# Update tracking
		_entity_positions[entity_id] = {
			"tile_pos": to_pos,
			"z_level": z_level
		}
		
		# Emit signals
		emit_signal("entity_moved", entity, from_pos, to_pos, z_level)
		emit_signal("tile_contents_changed", from_pos, z_level)
		emit_signal("tile_contents_changed", to_pos, z_level)
		
		print_log("Entity moved from " + str(from_pos) + " to " + str(to_pos) + ", z=" + str(z_level), 4)
		
		return true
	else:
		# Entity not found at from_pos, just register at to_pos
		print_log("Entity not found at source position, registering at target", 3)
		return register_entity_at_tile(entity, to_pos, z_level)

func move_entity_z(entity, from_pos: Vector2i, to_pos: Vector2i, from_z: int, to_z: int) -> bool:
	"""Move an entity between z-levels."""
	# Check if entity is valid
	if not _validate_entity(entity):
		print_log("Invalid entity provided for z movement", 1)
		return false
	
	# Remove from old z-level
	var removed = remove_entity(entity, from_pos, from_z)
	
	# Add to new z-level
	var added = register_entity_at_tile(entity, to_pos, to_z)
	
	print_log("Entity moved from z=" + str(from_z) + " to z=" + str(to_z), 3)
	
	# Both operations should succeed
	return removed and added

func update_entity_position(entity) -> bool:
	"""Update an entity's position based on its current world position."""
	# Get entity position data
	var position_data = _get_entity_position_data(entity)
	if not position_data.valid:
		print_log("Entity has no valid position for update", 1)
		return false
	
	# Get entity ID
	var entity_id = _get_entity_id(entity)
	
	# Check if we know the current position
	if entity_id in _entity_positions:
		var current_pos = _entity_positions[entity_id]
		
		# If position hasn't changed, do nothing
		if current_pos.tile_pos == position_data.tile_pos and current_pos.z_level == position_data.z_level:
			return true
		
		# Move to new position
		if current_pos.z_level == position_data.z_level:
			return move_entity(entity, current_pos.tile_pos, position_data.tile_pos, current_pos.z_level)
		else:
			return move_entity_z(entity, current_pos.tile_pos, position_data.tile_pos, current_pos.z_level, position_data.z_level)
	else:
		# No current position, just register
		return register_entity_at_tile(entity, position_data.tile_pos, position_data.z_level)
#endregion

#region ENTITY PROPERTY MANAGEMENT
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

func update_entity_property(entity, property_name: String, value):
	"""Update a cached entity property."""
	if not is_instance_valid(entity) or not entity_cache_enabled:
		return
	
	var entity_id = _get_entity_id(entity)
	
	# If entity isn't cached yet, cache it now
	if not entity_id in _entity_properties:
		_cache_entity_properties(entity)
		return
	
	# Update the property
	_entity_properties[entity_id][property_name] = value
	
	# Special handling for property changes that affect flags
	match property_name:
		"dense", "entity_dense":
			var is_dense = bool(value)
			var old_flags = _entity_properties[entity_id].flags
			var new_flags = old_flags
			
			if is_dense:
				new_flags |= EntityFlags.DENSE
			else:
				new_flags &= ~EntityFlags.DENSE
			
			# If flags changed, update flag collections
			if old_flags != new_flags:
				_update_entity_flags(entity, old_flags, new_flags)
				_entity_properties[entity_id].flags = new_flags
		
		"can_be_pushed":
			var can_push = bool(value)
			var old_flags = _entity_properties[entity_id].flags
			var new_flags = old_flags
			
			if can_push:
				new_flags |= EntityFlags.PUSHABLE
			else:
				new_flags &= ~EntityFlags.PUSHABLE
			
			# If flags changed, update flag collections
			if old_flags != new_flags:
				_update_entity_flags(entity, old_flags, new_flags)
				_entity_properties[entity_id].flags = new_flags
	
	# Update last update time
	_entity_properties[entity_id].last_update_time = Time.get_ticks_msec()

func _update_entity_flags(entity, old_flags: int, new_flags: int):
	"""Update entity flag collections when flags change."""
	# Skip if entity isn't registered
	var entity_id = _get_entity_id(entity)
	if not entity_id in _entity_positions:
		return
	
	# Get current position
	var pos_data = _entity_positions[entity_id]
	var tile_pos = pos_data.tile_pos
	var z_level = pos_data.z_level
	
	# Process each flag type
	for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.PUSHABLE, EntityFlags.ANCHORED, EntityFlags.ITEM]:
		var was_set = (old_flags & flag) != 0
		var is_set = (new_flags & flag) != 0
		
		if was_set != is_set:
			if is_set:
				# Add to flag collection
				if not tile_pos in _entity_by_flag[z_level][flag]:
					_entity_by_flag[z_level][flag][tile_pos] = []
				_entity_by_flag[z_level][flag][tile_pos].append(entity)
			else:
				# Remove from flag collection
				if tile_pos in _entity_by_flag[z_level][flag] and entity in _entity_by_flag[z_level][flag][tile_pos]:
					_entity_by_flag[z_level][flag][tile_pos].erase(entity)
					if _entity_by_flag[z_level][flag][tile_pos].size() == 0:
						_entity_by_flag[z_level][flag].erase(tile_pos)
#endregion

#region ENTITY QUERIES AND HELPERS
func get_entities_at(tile_pos: Vector2i, z_level: int) -> Array:
	"""Get all entities at a specific tile."""
	if not z_level in _occupancy or not tile_pos in _occupancy[z_level]:
		return []
	
	# Return a copy to prevent modification of internal array
	return _occupancy[z_level][tile_pos].duplicate()

func get_entity_at(tile_pos: Vector2i, z_level: int, type_name: String = ""):
	"""Get the first entity (or of a specific type) at a tile."""
	var entities = get_entities_at(tile_pos, z_level)
	
	if entities.size() == 0:
		return null
	
	# If type is specified, filter for that type
	if type_name != "":
		for entity in entities:
			if is_instance_valid(entity) and _get_entity_property(entity, "entity_type") == type_name:
				return entity
		return null
	else:
		# Return the first entity
		return entities[0]

func get_entities_of_type_at(tile_pos: Vector2i, z_level: int, type_name: String) -> Array:
	"""Get all entities of a specific type at a tile."""
	var entities = get_entities_at(tile_pos, z_level)
	var result = []
	
	for entity in entities:
		if is_instance_valid(entity) and _get_entity_property(entity, "entity_type") == type_name:
			result.append(entity)
	
	return result

func get_entities_with_flag_at(tile_pos: Vector2i, z_level: int, flag: int) -> Array:
	"""Get all entities with a specific flag at a tile."""
	if not z_level in _entity_by_flag or not flag in _entity_by_flag[z_level] or not tile_pos in _entity_by_flag[z_level][flag]:
		return []
	
	# Return a copy to prevent modification of internal array
	return _entity_by_flag[z_level][flag][tile_pos].duplicate()

func has_entity_at(tile_pos: Vector2i, z_level: int, type_name: String = "") -> bool:
	"""Check if a tile has any entity (or a specific type)."""
	if not z_level in _occupancy or not tile_pos in _occupancy[z_level]:
		return false
	
	# If no type specified, check for any entity
	if type_name == "":
		return _occupancy[z_level][tile_pos].size() > 0
	
	# Check for specific type
	for entity in _occupancy[z_level][tile_pos]:
		if is_instance_valid(entity) and _get_entity_property(entity, "entity_type") == type_name:
			return true
	
	return false

func has_dense_entity_at(tile_pos: Vector2i, z_level: int, excluding_entity = null) -> bool:
	"""Check if a tile has any dense entities (excluding the specified entity)."""
	# Use flag collection for faster lookup
	if z_level in _entity_by_flag and EntityFlags.DENSE in _entity_by_flag[z_level] and tile_pos in _entity_by_flag[z_level][EntityFlags.DENSE]:
		for entity in _entity_by_flag[z_level][EntityFlags.DENSE][tile_pos]:
			# Skip if it's the excluding entity or invalid
			if entity == excluding_entity or not is_instance_valid(entity):
				continue
			
			return true
	
	return false

func get_dense_entities_at(tile_pos: Vector2i, z_level: int) -> Array:
	"""Get all dense entities at a tile."""
	if not z_level in _entity_by_flag or not EntityFlags.DENSE in _entity_by_flag[z_level] or not tile_pos in _entity_by_flag[z_level][EntityFlags.DENSE]:
		return []
	
	# Return a copy to prevent modification of internal array
	return _entity_by_flag[z_level][EntityFlags.DENSE][tile_pos].duplicate()

func get_item_entities_at(tile_pos: Vector2i, z_level: int) -> Array:
	"""Get all item entities at a tile."""
	if not z_level in _entity_by_flag or not EntityFlags.ITEM in _entity_by_flag[z_level] or not tile_pos in _entity_by_flag[z_level][EntityFlags.ITEM]:
		return []
	
	# Return a copy to prevent modification of internal array
	return _entity_by_flag[z_level][EntityFlags.ITEM][tile_pos].duplicate()

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
	
	# Fallback to calculating from entity position
	var position_data = _get_entity_position_data(entity)
	if position_data.valid:
		return position_data.tile_pos
	
	return Vector2i(-1, -1)  # Invalid position

func get_entity_z_level(entity) -> int:
	"""Get an entity's current z-level."""
	var entity_id = _get_entity_id(entity)
	
	if entity_id in _entity_positions:
		return _entity_positions[entity_id].z_level
	
	# Fallback to calculating from entity
	var position_data = _get_entity_position_data(entity)
	if position_data.valid:
		return position_data.z_level
	
	return -1  # Invalid z-level

func _is_entity_dense(entity) -> bool:
	"""Check if an entity is dense (has collision)."""
	if not is_instance_valid(entity):
		return false
	
	var entity_id = _get_entity_id(entity)
	
	# Use cached property if available
	if entity_cache_enabled and entity_id in _entity_properties:
		return _entity_properties[entity_id].dense
	
	# Get directly
	return _is_entity_dense_direct(entity)

func _is_entity_dense_direct(entity) -> bool:
	"""Check entity density directly (no caching)."""
	# Check if entity is an item - items should be passable by default
	if _get_entity_property(entity, "entity_type") == "item":
		# If it has an explicit entity_dense property, use that, otherwise consider items non-dense
		var explicit_density = _get_entity_property(entity, "entity_dense", null)
		if explicit_density != null:
			return explicit_density
		return false
	
	# Otherwise, check for entity_dense property with default true
	return _get_entity_property(entity, "entity_dense", true)

func _get_entity_flags(entity) -> int:
	"""Calculate entity flags based on its properties."""
	var flags = EntityFlags.NONE
	
	# Dense flag
	if _is_entity_dense_direct(entity):
		flags |= EntityFlags.DENSE
	
	# Movable flag (most entities are movable by default)
	var is_movable = _get_entity_property(entity, "movable", true)
	if is_movable:
		flags |= EntityFlags.MOVABLE
	
	# Pushable flag
	var is_pushable = _get_entity_property(entity, "can_be_pushed", true)
	if is_pushable:
		flags |= EntityFlags.PUSHABLE
	
	# Anchored flag
	var is_anchored = _get_entity_property(entity, "anchored", false)
	if is_anchored:
		flags |= EntityFlags.ANCHORED
	
	# Item flag
	var is_item = _get_entity_property(entity, "entity_type") == "item"
	if is_item:
		flags |= EntityFlags.ITEM
	
	return flags
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
	
	# Validate entity
	if not _validate_entity(entity):
		return result
	
	# Get current position
	var current_tile = get_entity_tile(entity)
	if current_tile == Vector2i(-1, -1):
		return result
	
	# Calculate target tile
	var target_tile = current_tile + direction
	
	# Check if target is valid
	if not _is_valid_tile(target_tile, z_level):
		result.collision_type = CollisionType.WALL
		return result
	
	# Check for collisions
	var collision = check_collision(target_tile, z_level, entity)
	
	if collision.type == CollisionType.NONE:
		# No collision, move entity
		var moved = move_entity(entity, current_tile, target_tile, z_level)
		result.success = moved
		result.new_position = target_tile
	else:
		# Collision detected
		result.collision = collision.entity
		result.collision_type = collision.type
		
		# Try to push entities if blocked by an entity
		if collision.type == CollisionType.ENTITY and collision.entity != null:
			# Calculate push force
			var push_force = _get_entity_property(entity, "push_force", 1.0)
			
			# Try to push
			var push_result = try_push_entity(entity, collision.entity, direction)
			
			if push_result.success:
				# Entity was pushed, now we can move
				var moved = move_entity(entity, current_tile, target_tile, z_level)
				result.success = moved
				result.new_position = target_tile
			
			# Emit collision signal regardless of whether push succeeded
			emit_signal("entities_collided", entity, collision.entity, target_tile, z_level)
	
	return result

func try_push_entity(pusher, target, direction: Vector2i) -> Dictionary:
	"""Try to push an entity in a direction."""
	var result = {
		"success": false,
		"result_code": PushResult.FAILED_DENSE,
		"force_applied": 0.0
	}
	
	# Update push statistics
	_push_stats.attempts += 1
	
	# Validate entities
	if not _validate_entity(pusher) or not _validate_entity(target):
		return result
	
	# Check if target can be pushed
	if not _can_entity_be_pushed(target):
		result.result_code = PushResult.FAILED_IMMOVABLE
		_push_stats.failures.immovable += 1
		emit_signal("push_attempted", pusher, target, direction, PushResult.FAILED_IMMOVABLE, 0.0)
		return result
	
	# Check if target is anchored
	if _is_entity_anchored(target):
		result.result_code = PushResult.FAILED_ANCHORED
		_push_stats.failures.anchored += 1
		emit_signal("push_attempted", pusher, target, direction, PushResult.FAILED_ANCHORED, 0.0)
		return result
	
	# Get target position
	var target_position = get_entity_tile(target)
	var target_z = get_entity_z_level(target)
	var push_target = target_position + direction
	
	# Check if push target is valid
	if not can_entity_move_to(target, push_target, target_z):
		result.result_code = PushResult.FAILED_NO_SPACE
		_push_stats.failures.no_space += 1
		emit_signal("push_attempted", pusher, target, direction, PushResult.FAILED_NO_SPACE, 0.0)
		return result
	
	# Calculate push force
	var pusher_force = _get_entity_push_force(pusher)
	var target_mass = _get_entity_mass(target)
	
	# Apply mass factor to determine if push succeeds
	var effective_force = pusher_force * push_force_scale
	var mass_resistance = target_mass * mass_factor
	
	# Heavy objects need more force
	if mass_resistance > push_threshold and effective_force < mass_resistance:
		result.result_code = PushResult.FAILED_TOO_HEAVY
		_push_stats.failures.too_heavy += 1
		emit_signal("push_attempted", pusher, target, direction, PushResult.FAILED_TOO_HEAVY, effective_force)
		return result
	
	# Push succeeded, move the entity
	var moved = move_entity(target, target_position, push_target, target_z)
	
	if moved:
		result.success = true
		result.result_code = PushResult.SUCCESS
		result.force_applied = effective_force
		
		# Update statistics
		_push_stats.successes += 1
		
		# Let target know it was pushed
		if target.has_method("pushed"):
			target.pushed(pusher, direction)
		
		emit_signal("push_attempted", pusher, target, direction, PushResult.SUCCESS, effective_force)
	else:
		result.result_code = PushResult.FAILED_NO_SPACE
		_push_stats.failures.no_space += 1
		emit_signal("push_attempted", pusher, target, direction, PushResult.FAILED_NO_SPACE, effective_force)
	
	return result

func _can_entity_be_pushed(entity) -> bool:
	"""Check if an entity can be pushed."""
	if not is_instance_valid(entity):
		return false
	
	var entity_id = _get_entity_id(entity)
	
	# Use cached value if available
	if entity_cache_enabled and entity_id in _entity_properties:
		return _entity_properties[entity_id].can_be_pushed
	
	# Get directly
	return _get_entity_property(entity, "can_be_pushed", true)

func _is_entity_anchored(entity) -> bool:
	"""Check if an entity is anchored (can't be moved)."""
	return _get_entity_property(entity, "anchored", false)

func _get_entity_push_force(entity) -> float:
	"""Get an entity's push force."""
	var entity_id = _get_entity_id(entity)
	
	# Use cached value if available
	if entity_cache_enabled and entity_id in _entity_properties:
		return _entity_properties[entity_id].push_force
	
	# Get directly
	return _get_entity_property(entity, "push_force", 1.0)

func _get_entity_mass(entity) -> float:
	"""Get an entity's mass."""
	var entity_id = _get_entity_id(entity)
	
	# Use cached value if available
	if entity_cache_enabled and entity_id in _entity_properties:
		return _entity_properties[entity_id].mass
	
	# Get directly
	return _get_entity_property(entity, "mass", 10.0)
#endregion

#region UTILITY FUNCTIONS
func world_to_tile(world_pos: Vector2) -> Vector2i:
	"""Convert world position to tile position."""
	if _world and _world.has_method("get_tile_at"):
		return _world.get_tile_at(world_pos)
	
	# Default implementation
	return Vector2i(int(world_pos.x / TILE_SIZE), int(world_pos.y / TILE_SIZE))

func tile_to_world(tile_pos: Vector2i) -> Vector2:
	"""Convert tile position to world position (center of tile)."""
	if _world and _world.has_method("tile_to_world"):
		return _world.tile_to_world(tile_pos)
	
	# Default implementation
	return Vector2(
		(tile_pos.x * TILE_SIZE) + (TILE_SIZE / 2),
		(tile_pos.y * TILE_SIZE) + (TILE_SIZE / 2)
	)

func _is_valid_tile(tile_pos: Vector2i, z_level: int) -> bool:
	"""Check if a tile is valid (exists in the world)."""
	# Check cache first
	var cache_key = str(tile_pos) + "_" + str(z_level)
	if cache_key in _valid_tile_cache:
		return _valid_tile_cache[cache_key]
	
	var is_valid = true
	
	# Use World system if available
	if _world:
		if _world.has_method("is_valid_tile"):
			is_valid = _world.is_valid_tile(tile_pos, z_level)
		elif _world.has_method("get_tile_data"):
			is_valid = _world.get_tile_data(tile_pos, z_level) != null
	
	# Cache the result
	_valid_tile_cache[cache_key] = is_valid
	
	return is_valid

func clear_valid_tile_cache():
	"""Clear the valid tile cache."""
	_valid_tile_cache.clear()

func _validate_entity(entity) -> bool:
	"""Validate that an entity can be used in the system."""
	if not is_instance_valid(entity):
		return false
	
	# Check if entity has a position
	if not "position" in entity:
		return false
	
	return true

func _get_entity_id(entity):
	"""Get a reliable entity identifier."""
	if not is_instance_valid(entity):
		return "INVALID"
	
	# Prefer object's own ID if it has one
	if "entity_id" in entity and entity.entity_id:
		return entity.entity_id
	
	# Otherwise use the instance ID
	return entity.get_instance_id()

func _get_entity_property(entity, property_name: String, default_value = null):
	"""Safely get an entity property with fallback."""
	if not is_instance_valid(entity):
		return default_value
	
	if property_name in entity:
		# Direct property access
		return entity[property_name]
	elif entity.has_method(property_name):
		# Method call
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
	
	# Get tile position
	result.tile_pos = world_to_tile(result.position)
	
	# Get z-level
	if entity is GridMovementController:
		result.z_level = entity.current_z_level
	elif "current_z_level" in entity:
		result.z_level = entity.current_z_level
	elif "z_level" in entity:
		result.z_level = entity.z_level
	elif entity is Node2D:
		# Use z_index as fallback
		result.z_level = entity.z_index
	
	return result

func _cleanup_invalid_entity_at_tile(tile_pos: Vector2i, z_level: int) -> bool:
	"""Clean up any invalid entities at a specific tile."""
	if not z_level in _occupancy or not tile_pos in _occupancy[z_level]:
		return false
	
	var had_invalid = false
	var valid_entities = []
	
	# Check each entity at this tile
	for entity in _occupancy[z_level][tile_pos]:
		if is_instance_valid(entity):
			valid_entities.append(entity)
		else:
			had_invalid = true
			print_log("Cleaned up invalid entity at " + str(tile_pos) + ", z=" + str(z_level), 2)
	
	if had_invalid:
		# Update with only valid entities
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
		
		# Emit signal
		emit_signal("tile_contents_changed", tile_pos, z_level)
		
		return true
	
	return false

func _find_and_remove_entity(entity) -> bool:
	"""Find an entity anywhere in the system and remove it."""
	# Get entity ID
	var entity_id = _get_entity_id(entity)
	
	# Search all z-levels
	for z in _occupancy.keys():
		for tile_pos in _occupancy[z].keys():
			if entity in _occupancy[z][tile_pos]:
				# Found it, remove it
				_occupancy[z][tile_pos].erase(entity)
				
				# Clean up empty tile
				if _occupancy[z][tile_pos].size() == 0:
					_occupancy[z].erase(tile_pos)
				
				# Remove from flag collections
				for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.PUSHABLE, EntityFlags.ANCHORED, EntityFlags.ITEM]:
					if flag in _entity_by_flag[z] and tile_pos in _entity_by_flag[z][flag]:
						_entity_by_flag[z][flag][tile_pos].erase(entity)
						if _entity_by_flag[z][flag][tile_pos].size() == 0:
							_entity_by_flag[z][flag].erase(tile_pos)
				
				# Clean up entity cache
				if entity_cache_enabled and entity_id in _entity_properties:
					_entity_properties.erase(entity_id)
				
				# Clean up position tracking
				_entity_positions.erase(entity_id)
				
				# Emit signals
				emit_signal("entity_unregistered", entity, tile_pos, z)
				emit_signal("tile_contents_changed", tile_pos, z)
				
				print_log("Entity found and removed from " + str(tile_pos) + ", z=" + str(z), 3)
				
				return true
	
	# Entity not found
	print_log("Entity not found for removal", 2)
	return false

func print_log(message: String, level: int = 3):
	"""Print a log message based on log level."""
	if level <= log_level:
		var prefix = ""
		match level:
			1: prefix = "[ERROR] "
			2: prefix = "[WARN] "
			3: prefix = "[INFO] "
			4: prefix = "[DEBUG] "
		
		if debug_mode:
			print(prefix + "TileOccupancySystem: " + message)
#endregion

#region SIGNAL HANDLERS
func _on_world_tile_changed(tile_coords, z_level, old_data, new_data):
	"""Handle tile data changes from World."""
	# Clear valid tile cache for this tile
	var cache_key = str(tile_coords) + "_" + str(z_level)
	_valid_tile_cache.erase(cache_key)
	
	# Check for changes that affect entities
	var old_tile_blocked = _is_tile_blocked(old_data)
	var new_tile_blocked = _is_tile_blocked(new_data)
	
	if old_tile_blocked != new_tile_blocked:
		# Clear cache for surrounding tiles
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var neighbor = tile_coords + Vector2i(dx, dy)
				var neighbor_key = str(neighbor) + "_" + str(z_level)
				_valid_tile_cache.erase(neighbor_key)
	
	# Handle entity impact of tile changes
	if new_tile_blocked and tile_coords in _occupancy.get(z_level, {}):
		# Tile now blocked, might need to move entities
		var entities = get_entities_at(tile_coords, z_level)
		for entity in entities:
			# If entity is dense, it might need special handling
			if _is_entity_dense(entity):
				# In most cases, the world system should handle what to do with entities
				# This is just a signal that the situation has changed
				emit_signal("entities_collided", entity, null, tile_coords, z_level)

func _is_tile_blocked(tile_data) -> bool:
	"""Check if a tile is blocked (has wall or is otherwise impassable)."""
	if not tile_data:
		return false
	
	# Check for walls
	if "wall" in tile_data and tile_data.wall != null:
		return true
	
	# Check for closed doors
	if "door" in tile_data and "closed" in tile_data.door and tile_data.door.closed:
		return true
	
	return false
#endregion

#region PUBLIC QUERY API
func get_entity_count(z_level = null) -> int:
	"""Get total number of entities being tracked."""
	if z_level == null:
		# Count across all z-levels
		var count = 0
		for z in _occupancy.keys():
			for tile in _occupancy[z].keys():
				count += _occupancy[z][tile].size()
		return count
	elif z_level in _occupancy:
		# Count for specific z-level
		var count = 0
		for tile in _occupancy[z_level].keys():
			count += _occupancy[z_level][tile].size()
		return count
	
	return 0

func get_occupied_tile_count(z_level = null) -> int:
	"""Get number of occupied tiles."""
	if z_level == null:
		# Count across all z-levels
		var count = 0
		for z in _occupancy.keys():
			count += _occupancy[z].keys().size()
		return count
	elif z_level in _occupancy:
		# Count for specific z-level
		return _occupancy[z_level].keys().size()
	
	return 0

func get_push_stats() -> Dictionary:
	"""Get statistics about pushing attempts."""
	# Calculate success rate
	var success_rate = 0.0
	if _push_stats.attempts > 0:
		success_rate = float(_push_stats.successes) / float(_push_stats.attempts)
	
	# Add calculated stats
	var stats = _push_stats.duplicate(true)
	stats.success_rate = success_rate
	
	return stats

func get_entity_metadata(entity):
	"""Get an entity's cached metadata (for debugging)."""
	var entity_id = _get_entity_id(entity)
	
	if entity_cache_enabled and entity_id in _entity_properties:
		return _entity_properties[entity_id].duplicate()
	
	return null

func get_entities_in_area(top_left: Vector2i, bottom_right: Vector2i, z_level: int) -> Array:
	"""Get all entities in a rectangular area."""
	var result = []
	
	if not z_level in _occupancy:
		return result
	
	# Process each tile in the area
	for y in range(top_left.y, bottom_right.y + 1):
		for x in range(top_left.x, bottom_right.x + 1):
			var tile_pos = Vector2i(x, y)
			if tile_pos in _occupancy[z_level]:
				for entity in _occupancy[z_level][tile_pos]:
					if is_instance_valid(entity) and not entity in result:
						result.append(entity)
	
	return result

func get_entities_in_radius(center: Vector2i, radius: int, z_level: int) -> Array:
	"""Get all entities within a tile radius."""
	var result = []
	var processed = {}
	
	if not z_level in _occupancy:
		return result
	
	# Process each tile in the area
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var tile_pos = Vector2i(x, y)
			
			# Check if within radius (approximating a circle)
			var dx = tile_pos.x - center.x
			var dy = tile_pos.y - center.y
			var distance_squared = dx * dx + dy * dy
			
			if distance_squared <= radius * radius:
				if tile_pos in _occupancy[z_level]:
					for entity in _occupancy[z_level][tile_pos]:
						var entity_id = _get_entity_id(entity)
						if is_instance_valid(entity) and not entity_id in processed:
							result.append(entity)
							processed[entity_id] = true
	
	return result

func raycast(start_tile: Vector2i, end_tile: Vector2i, z_level: int) -> Dictionary:
	"""Cast a ray from start to end, stopping at the first collision."""
	var result = {
		"hit": false,
		"hit_pos": null,
		"hit_entity": null,
		"hit_tile": null,
		"tiles": []
	}
	
	# Use Bresenham's algorithm to get tiles along the line
	var tiles = _get_tiles_in_line(start_tile, end_tile)
	result.tiles = tiles
	
	# Skip the starting tile
	if tiles.size() > 1:
		tiles.remove_at(0)
	
	# Check each tile for collision
	for tile_pos in tiles:
		# Check for walls first
		if _world and _world.has_method("is_wall_at") and _world.is_wall_at(tile_pos, z_level):
			result.hit = true
			result.hit_tile = tile_pos
			result.hit_pos = tile_to_world(tile_pos)
			break
		
		# Check for dense entities
		var dense_entities = get_dense_entities_at(tile_pos, z_level)
		if dense_entities.size() > 0:
			result.hit = true
			result.hit_tile = tile_pos
			result.hit_entity = dense_entities[0]
			result.hit_pos = dense_entities[0].position
			break
		
		# Check for other obstacles
		if _world:
			if _world.has_method("is_closed_door_at") and _world.is_closed_door_at(tile_pos, z_level):
				result.hit = true
				result.hit_tile = tile_pos
				result.hit_pos = tile_to_world(tile_pos)
				break
	
	# If no hit, set the end position
	if not result.hit:
		result.hit_pos = tile_to_world(end_tile)
	
	return result

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

func clean_invalid_entities() -> int:
	"""Clean up any invalid entity references."""
	var removed_count = 0
	
	# Process each z-level
	for z in _occupancy.keys():
		var tiles_to_check = _occupancy[z].keys().duplicate()
		
		for tile_pos in tiles_to_check:
			# Clean up invalid entities at this tile
			if _cleanup_invalid_entity_at_tile(tile_pos, z):
				removed_count += 1
	
	# Clean up entity cache
	if entity_cache_enabled:
		var ids_to_remove = []
		for entity_id in _entity_properties.keys():
			if entity_id is int:  # If using instance ID
				var entity = instance_from_id(entity_id)
				if not is_instance_valid(entity):
					ids_to_remove.append(entity_id)
		
		for entity_id in ids_to_remove:
			_entity_properties.erase(entity_id)
			_entity_positions.erase(entity_id)
	
	if removed_count > 0:
		print_log("Cleaned up " + str(removed_count) + " invalid entity references", 2)
	
	return removed_count

func get_debug_stats() -> Dictionary:
	"""Get detailed statistics about the system."""
	var stats = {
		"total_entities": get_entity_count(),
		"occupied_tiles": get_occupied_tile_count(),
		"cached_entities": _entity_properties.size() if entity_cache_enabled else 0,
		"z_levels": {},
		"push_stats": get_push_stats(),
		"flag_counts": {}
	}
	
	# Add z-level statistics
	for z in _occupancy.keys():
		stats.z_levels[z] = {
			"tiles": _occupancy[z].keys().size(),
			"entities": get_entity_count(z)
		}
	
	# Add flag counts
	for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.PUSHABLE, EntityFlags.ANCHORED, EntityFlags.ITEM]:
		var count = 0
		
		for z in _entity_by_flag.keys():
			if flag in _entity_by_flag[z]:
				for tile_pos in _entity_by_flag[z][flag]:
					count += _entity_by_flag[z][flag][tile_pos].size()
		
		var flag_name = ""
		match flag:
			EntityFlags.DENSE: flag_name = "dense"
			EntityFlags.MOVABLE: flag_name = "movable"
			EntityFlags.PUSHABLE: flag_name = "pushable"
			EntityFlags.ANCHORED: flag_name = "anchored"
			EntityFlags.ITEM: flag_name = "item"
		
		stats.flag_counts[flag_name] = count
	
	return stats

# Special method for handling door secondary tiles
func door_set_secondary_tile_property(door_entity, secondary_tile_pos: Vector2i, z_level: int, property_name: String, value):
	"""Update properties for a door's secondary tile without changing the door's position."""
	if not _validate_entity(door_entity):
		return false
	
	# Check if the entity is registered at this tile
	var entities_at_tile = get_entities_at(secondary_tile_pos, z_level)
	
	if not door_entity in entities_at_tile:
		# Register door at this secondary position
		register_entity_at_tile(door_entity, secondary_tile_pos, z_level)
	
	# Now update the property
	update_entity_property(door_entity, property_name, value)
	
	# This change affects collision
	emit_signal("tile_contents_changed", secondary_tile_pos, z_level)
	
	return true

# Enhance can_entity_move_to to better check for doors
func can_entity_move_to(entity, tile_pos: Vector2i, z_level: int) -> bool:
	"""Check if an entity can move to a specific tile."""
	# Check if the tile exists
	if not _is_valid_tile(tile_pos, z_level):
		return false
	
	# Check for walls via World system
	if _world and _world.has_method("is_wall_at") and _world.is_wall_at(tile_pos, z_level):
		return false
	
	# Check for closed doors directly
	var door_entity = null
	var entities = get_entities_at(tile_pos, z_level)
	for potential_door in entities:
		if potential_door.is_in_group("doors") or ("entity_type" in potential_door and potential_door.entity_type == "door"):
			door_entity = potential_door
			break
	
	if door_entity:
		if "is_open" in door_entity and not door_entity.is_open:
			# Door is closed, check if entity can pass through doors
			if (entity.has_method("can_pass_through_doors") and entity.can_pass_through_doors()) or \
			   ("can_pass_through_doors" in entity and entity.can_pass_through_doors):
				# Special entity that can pass through doors
				return true
			
			# If the entity is trying to bump the door to open it, the door handles this
			if entity.has_method("on_bump_door"):
				entity.on_bump_door(door_entity)
				if "is_open" in door_entity and door_entity.is_open:
					# Door was opened, allow movement next frame
					return false
			
			# Otherwise, entity cannot move through closed door
			return false
	
	# Also check World's is_closed_door_at method if available
	if _world and _world.has_method("is_closed_door_at") and _world.is_closed_door_at(tile_pos, z_level):
		return false
	
	# Check for dense entities
	if has_dense_entity_at(tile_pos, z_level, entity):
		return false
	
	return true

func check_collision(tile_pos: Vector2i, z_level: int, exclude_entity = null) -> Dictionary:
	"""Check for collision at a target tile."""
	var result = {
		"type": CollisionType.NONE,
		"entity": null,
		"tile": tile_pos
	}
	
	# Check if tile is valid
	if not _is_valid_tile(tile_pos, z_level):
		result.type = CollisionType.WALL
		return result
	
	# Check for walls (via World)
	if _world:
		if _world.has_method("is_wall_at") and _world.is_wall_at(tile_pos, z_level):
			result.type = CollisionType.WALL
			return result
	
	# Check specifically for doors first
	var door_entity = null
	var entities = get_entities_at(tile_pos, z_level)
	for entity in entities:
		if entity != exclude_entity and is_instance_valid(entity) and \
		   (entity.is_in_group("doors") or ("entity_type" in entity and entity.entity_type == "door")):
			door_entity = entity
			break
	
	if door_entity:
		if "is_open" in door_entity and not door_entity.is_open:
			result.type = CollisionType.DOOR_CLOSED
			result.entity = door_entity
			return result
	
	# Also check World's is_closed_door_at method
	if _world and _world.has_method("is_closed_door_at") and _world.is_closed_door_at(tile_pos, z_level):
		result.type = CollisionType.DOOR_CLOSED
		return result
	
	# Check for window
	if _world and _world.has_method("is_window_at") and _world.is_window_at(tile_pos, z_level):
		result.type = CollisionType.WINDOW
		return result
	
	# Check for dense entities
	for entity in entities:
		if entity != exclude_entity and entity != door_entity and is_instance_valid(entity):
			if _is_entity_dense(entity):
				result.type = CollisionType.ENTITY
				result.entity = entity
				return result
	
	return result

# Get all door entities
func get_all_doors(z_level: int = -1) -> Array:
	"""Get all registered door entities."""
	var doors = []
	
	# If a specific z-level is provided
	if z_level >= 0:
		for tile_pos in _occupancy.get(z_level, {}).keys():
			for entity in _occupancy[z_level][tile_pos]:
				if is_instance_valid(entity) and \
				   (entity.is_in_group("doors") or ("entity_type" in entity and entity.entity_type == "door")) and \
				   not entity in doors:
					doors.append(entity)
		return doors
	
	# Get doors from all z-levels
	for z in _occupancy.keys():
		for tile_pos in _occupancy[z].keys():
			for entity in _occupancy[z][tile_pos]:
				if is_instance_valid(entity) and \
				   (entity.is_in_group("doors") or ("entity_type" in entity and entity.entity_type == "door")) and \
				   not entity in doors:
					doors.append(entity)
	
	return doors
#endregion
