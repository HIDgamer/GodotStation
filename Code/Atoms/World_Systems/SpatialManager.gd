extends Node
class_name SpatialManager

# === CONSTANTS ===
const TILE_SIZE = 32  # Size of a tile in pixels - should match your game's tile size
const GRID_CELL_SIZE = 4  # Number of tiles per spatial partition cell (4x4 tiles per cell)
const MAX_Z_LEVELS = 10   # Maximum number of z-levels supported

# === ENUMS ===
enum QueryMode {
	EXACT,        # Exact position match
	OVERLAPPING,  # Any overlap
	CONTAINING,   # Fully contains
	NEAREST       # Find nearest
}

enum EntityFlags {
	NONE = 0,
	DENSE = 1,
	MOVABLE = 2,
	HEARING = 4,  # SS13-inspired for sound propagation
	CLIENT_CONTROLLED = 8,  # SS13-inspired for player entities
}

# === SPATIAL PARTITIONING ===
# Spatial grid using dictionary for O(1) lookups with better structure
# Format: _spatial_grid[z_level][cell_coords][entity_type] = [entities]
var _spatial_grid = {}

# Direct tile lookup for O(1) entity retrieval at exact positions
# Format: _tile_entities[z_level][tile_coords] = [entities]
var _tile_entities = {}

# Entity tracking systems with improved organization
var _all_entities = []  # All entities in the world
var _entity_by_id = {}  # Quick lookup by entity ID
var _entities_by_type = {}  # Entities grouped by type
var _entities_by_flag = {}  # Entities grouped by flags (dense, hearing, etc.)

# Entity metadata cache for quick property access without querying the entity directly
# Format: _entity_metadata[entity_id] = {position, tile_pos, z_level, cell, flags, etc.}
var _entity_metadata = {}

# Internal tracking dictionaries with improved naming
var _entity_current_cell = {}  # Maps entity_id to current spatial cell
var _entity_current_tile = {}  # Maps entity_id to current tile position
var _entity_current_z = {}     # Maps entity_id to current z-level

# Visibility caching with LRU implementation for better memory management
var _visibility_cache = {}  # Caches line of sight calculations
var _visibility_cache_order = []  # LRU tracking for cache entries
var _visibility_cache_size = 500  # Increased cache size for better performance

# Tile occupancy integration
var _tile_occupancy_system = null

# Debug flags
var _debug_enabled = false
var _visual_debug = false
var _debug_draw_node = null

# === SIGNALS ===
signal entity_registered(entity, old_metadata, new_metadata)
signal entity_unregistered(entity, metadata)
signal entity_moved(entity, old_tile, new_tile, old_z, new_z)
signal entity_flag_changed(entity, flag, enabled)
signal spatial_query_completed(query_id, result)

# === LIFECYCLE METHODS ===
func _ready():
	# Initialize spatial grid and supporting structures
	initialize()
	
	# Try to find tile occupancy system for integration
	_connect_to_occupancy_system()
	
	# Set up debug draw if needed
	if _visual_debug:
		_setup_debug_draw()

func _process(_delta):
	# Only used when debug drawing is enabled
	if _debug_draw_node and _visual_debug:
		_debug_draw_node.queue_redraw()

# === INITIALIZATION ===
func initialize():
	"""Initialize the spatial manager and all supporting data structures."""
	print("ImprovedSpatialManager: Initializing...")
	
	# Clear existing data
	_spatial_grid.clear()
	_tile_entities.clear()
	_all_entities.clear()
	_entity_by_id.clear()
	_entities_by_type.clear()
	_entities_by_flag.clear()
	_entity_metadata.clear()
	_entity_current_cell.clear()
	_entity_current_tile.clear()
	_entity_current_z.clear()
	_visibility_cache.clear()
	_visibility_cache_order.clear()
	
	# Initialize spatial grid for all z-levels
	for z in range(MAX_Z_LEVELS):
		_spatial_grid[z] = {}
		_tile_entities[z] = {}
		_visibility_cache[z] = {}
		_entities_by_flag[z] = {
			EntityFlags.DENSE: {},
			EntityFlags.MOVABLE: {},
			EntityFlags.HEARING: {},
			EntityFlags.CLIENT_CONTROLLED: {}
		}
	
	# Initialize flag categories
	for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.HEARING, EntityFlags.CLIENT_CONTROLLED]:
		_entities_by_flag[flag] = []
	
	print("ImprovedSpatialManager: Initialization complete")

func _connect_to_occupancy_system():
	"""Find and connect to the TileOccupancySystem if available."""
	# Try to find in the scene tree first
	_tile_occupancy_system = get_node_or_null("../TileOccupancySystem")
	
	# If not found as sibling, check parent and child nodes
	if not _tile_occupancy_system:
		_tile_occupancy_system = get_node_or_null("../ImprovedTileOccupancySystem")
	
	if not _tile_occupancy_system:
		_tile_occupancy_system = get_node_or_null("TileOccupancySystem")
	
	if not _tile_occupancy_system:
		# Try to find in the scene using groups
		var occupancy_systems = get_tree().get_nodes_in_group("tile_occupancy_system")
		if occupancy_systems.size() > 0:
			_tile_occupancy_system = occupancy_systems[0]
	
	if _tile_occupancy_system:
		print("ImprovedSpatialManager: Connected to TileOccupancySystem")

# === ENTITY REGISTRATION AND TRACKING ===
func register_entity(entity):
	"""Register an entity with the spatial manager for tracking."""
	# Validate entity has required properties
	if not _validate_entity(entity):
		push_warning("SpatialManager: Entity missing required properties: " + str(entity))
		return false
	
	var entity_id = entity.entity_id
	
	# Check if entity is already registered
	if entity_id in _entity_by_id:
		# Update existing entity instead of double-registering
		update_entity_position(entity)
		return true
	
	# Get entity metadata
	var metadata = _create_entity_metadata(entity)
	
	# Add to tracking collections
	_all_entities.append(entity)
	_entity_by_id[entity_id] = entity
	
	# Store by type
	var entity_type = metadata.entity_type
	if not entity_type in _entities_by_type:
		_entities_by_type[entity_type] = []
	_entities_by_type[entity_type].append(entity)
	
	# Store flags
	for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.HEARING, EntityFlags.CLIENT_CONTROLLED]:
		if metadata.flags & flag:
			_entities_by_flag[flag].append(entity)
	
	# Store by z-level flag for faster spatial queries
	var z_level = metadata.z_level
	for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.HEARING, EntityFlags.CLIENT_CONTROLLED]:
		if metadata.flags & flag:
			var tile_pos = metadata.tile_pos
			if not tile_pos in _entities_by_flag[z_level][flag]:
				_entities_by_flag[z_level][flag][tile_pos] = []
			_entities_by_flag[z_level][flag][tile_pos].append(entity)
	
	# Add to spatial grid and tile map
	_add_to_spatial_structures(entity, metadata)
	
	# Store metadata
	_entity_metadata[entity_id] = metadata
	
	# Connect to signals
	_connect_entity_signals(entity)
	
	# Emit signal
	emit_signal("entity_registered", entity, null, metadata)
	
	return true

func unregister_entity(entity):
	"""Unregister an entity from the spatial manager."""
	if not _validate_entity(entity):
		return false
	
	var entity_id = entity.entity_id
	
	# Skip if entity is not registered
	if not entity_id in _entity_by_id:
		return false
	
	# Get entity metadata
	var metadata = _entity_metadata[entity_id]
	
	# Remove from tracking collections
	_all_entities.erase(entity)
	_entity_by_id.erase(entity_id)
	
	# Remove from type collections
	var entity_type = metadata.entity_type
	if entity_type in _entities_by_type:
		_entities_by_type[entity_type].erase(entity)
	
	# Remove from flag collections
	for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.HEARING, EntityFlags.CLIENT_CONTROLLED]:
		if metadata.flags & flag:
			_entities_by_flag[flag].erase(entity)
	
	# Remove from z-level flag collections
	var z_level = metadata.z_level
	for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.HEARING, EntityFlags.CLIENT_CONTROLLED]:
		if metadata.flags & flag:
			var tile_pos = metadata.tile_pos
			if z_level in _entities_by_flag and flag in _entities_by_flag[z_level] and tile_pos in _entities_by_flag[z_level][flag]:
				_entities_by_flag[z_level][flag][tile_pos].erase(entity)
	
	# Remove from spatial grid and tile map
	_remove_from_spatial_structures(entity, metadata)
	
	# Clean up metadata
	_entity_current_cell.erase(entity_id)
	_entity_current_tile.erase(entity_id)
	_entity_current_z.erase(entity_id)
	_entity_metadata.erase(entity_id)
	
	# Disconnect signals
	_disconnect_entity_signals(entity)
	
	# Emit signal
	emit_signal("entity_unregistered", entity, metadata)
	
	return true

func update_entity_position(entity):
	"""Update an entity's position in the spatial grid."""
	if not _validate_entity(entity):
		return false
	
	var entity_id = entity.entity_id
	
	# Skip if entity is not registered
	if not entity_id in _entity_by_id:
		return register_entity(entity)
	
	# Get current metadata
	var old_metadata = _entity_metadata[entity_id]
	
	# Create new metadata based on current entity state
	var new_metadata = _create_entity_metadata(entity)
	
	# Check if position actually changed
	if old_metadata.tile_pos == new_metadata.tile_pos and old_metadata.z_level == new_metadata.z_level:
		return false  # No movement occurred
	
	# Remove from old spatial structures
	_remove_from_spatial_structures(entity, old_metadata)
	
	# Add to new spatial structures
	_add_to_spatial_structures(entity, new_metadata)
	
	# Update metadata
	_entity_metadata[entity_id] = new_metadata
	_entity_current_tile[entity_id] = new_metadata.tile_pos
	_entity_current_cell[entity_id] = new_metadata.cell
	_entity_current_z[entity_id] = new_metadata.z_level
	
	# Emit signal
	emit_signal("entity_moved", entity, old_metadata.tile_pos, new_metadata.tile_pos, 
				old_metadata.z_level, new_metadata.z_level)
	
	return true

func update_entity_flags(entity, flags, enabled = true):
	"""Update an entity's flags (dense, movable, etc.)."""
	if not _validate_entity(entity):
		return false
	
	var entity_id = entity.entity_id
	
	# Skip if entity is not registered
	if not entity_id in _entity_by_id:
		return false
	
	# Get current metadata
	var metadata = _entity_metadata[entity_id]
	var old_flags = metadata.flags
	
	# Update flags
	if enabled:
		metadata.flags |= flags
	else:
		metadata.flags &= ~flags
	
	# Skip if no change occurred
	if old_flags == metadata.flags:
		return false
	
	# Update flag collections
	for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.HEARING, EntityFlags.CLIENT_CONTROLLED]:
		if flag & flags:  # If this flag is being changed
			var was_set = old_flags & flag
			var is_set = metadata.flags & flag
			
			if was_set != is_set:
				if is_set:
					_entities_by_flag[flag].append(entity)
					
					# Add to z-level flag collections
					var z_level = metadata.z_level
					var tile_pos = metadata.tile_pos
					if not tile_pos in _entities_by_flag[z_level][flag]:
						_entities_by_flag[z_level][flag][tile_pos] = []
					_entities_by_flag[z_level][flag][tile_pos].append(entity)
				else:
					_entities_by_flag[flag].erase(entity)
					
					# Remove from z-level flag collections
					var z_level = metadata.z_level
					var tile_pos = metadata.tile_pos
					if z_level in _entities_by_flag and flag in _entities_by_flag[z_level] and tile_pos in _entities_by_flag[z_level][flag]:
						_entities_by_flag[z_level][flag][tile_pos].erase(entity)
				
				# Emit signal for each changed flag
				emit_signal("entity_flag_changed", entity, flag, is_set)
	
	# Update metadata
	_entity_metadata[entity_id] = metadata
	
	return true

# === SPATIAL STRUCTURE HELPERS ===
func _add_to_spatial_structures(entity, metadata):
	"""Add an entity to all spatial tracking structures."""
	var entity_id = entity.entity_id
	var z_level = metadata.z_level
	var tile_pos = metadata.tile_pos
	var cell = metadata.cell
	
	# Add to tile map
	if not tile_pos in _tile_entities[z_level]:
		_tile_entities[z_level][tile_pos] = []
	if not entity in _tile_entities[z_level][tile_pos]:
		_tile_entities[z_level][tile_pos].append(entity)
	
	# Add to spatial grid
	if not cell in _spatial_grid[z_level]:
		_spatial_grid[z_level][cell] = {}
	var entity_type = metadata.entity_type
	if not entity_type in _spatial_grid[z_level][cell]:
		_spatial_grid[z_level][cell][entity_type] = []
	if not entity in _spatial_grid[z_level][cell][entity_type]:
		_spatial_grid[z_level][cell][entity_type].append(entity)
	
	# Add to tile occupancy system if available
	if _tile_occupancy_system and _tile_occupancy_system.has_method("register_entity_at_tile"):
		_tile_occupancy_system.register_entity_at_tile(entity, tile_pos, z_level)
	
	# Store tracking info
	_entity_current_cell[entity_id] = cell
	_entity_current_tile[entity_id] = tile_pos
	_entity_current_z[entity_id] = z_level

func _remove_from_spatial_structures(entity, metadata):
	"""Remove an entity from all spatial tracking structures."""
	var entity_id = entity.entity_id
	var z_level = metadata.z_level
	var tile_pos = metadata.tile_pos
	var cell = metadata.cell
	
	# Remove from tile map
	if z_level in _tile_entities and tile_pos in _tile_entities[z_level]:
		_tile_entities[z_level][tile_pos].erase(entity)
		if _tile_entities[z_level][tile_pos].size() == 0:
			_tile_entities[z_level].erase(tile_pos)
	
	# Remove from spatial grid
	var entity_type = metadata.entity_type
	if z_level in _spatial_grid and cell in _spatial_grid[z_level] and entity_type in _spatial_grid[z_level][cell]:
		_spatial_grid[z_level][cell][entity_type].erase(entity)
		if _spatial_grid[z_level][cell][entity_type].size() == 0:
			_spatial_grid[z_level][cell].erase(entity_type)
		if _spatial_grid[z_level][cell].size() == 0:
			_spatial_grid[z_level].erase(cell)
	
	# Remove from tile occupancy system if available
	if _tile_occupancy_system and _tile_occupancy_system.has_method("remove_entity"):
		_tile_occupancy_system.remove_entity(entity, tile_pos, z_level)

# === ENTITY SIGNAL HANDLING ===
func _connect_entity_signals(entity):
	"""Connect to all signals from an entity that we need to track."""
	# Connect to entity_moved signal based on entity type
	if entity.has_signal("entity_moved"):
		if entity is GridMovementController:
			if not entity.is_connected("entity_moved", Callable(self, "_on_entity_moved")):
				entity.connect("entity_moved", Callable(self, "_on_entity_moved"))
		else:
			if not entity.is_connected("entity_moved", Callable(self, "_on_entity_moved").bind(entity)):
				entity.connect("entity_moved", Callable(self, "_on_entity_moved").bind(entity))
	
	# Connect to property_changed signal if available
	if entity.has_signal("property_changed"):
		if not entity.is_connected("property_changed", Callable(self, "_on_entity_property_changed").bind(entity)):
			entity.connect("property_changed", Callable(self, "_on_entity_property_changed").bind(entity))
	
	# Connect to z_level_changed signal if available
	if entity.has_signal("z_level_changed"):
		if not entity.is_connected("z_level_changed", Callable(self, "_on_entity_z_level_changed").bind(entity)):
			entity.connect("z_level_changed", Callable(self, "_on_entity_z_level_changed").bind(entity))

func _disconnect_entity_signals(entity):
	"""Disconnect all signals from an entity."""
	if entity.has_signal("entity_moved"):
		if entity.is_connected("entity_moved", Callable(self, "_on_entity_moved")):
			entity.disconnect("entity_moved", Callable(self, "_on_entity_moved"))
	
	if entity.has_signal("property_changed"):
		if entity.is_connected("property_changed", Callable(self, "_on_entity_property_changed").bind(entity)):
			entity.disconnect("property_changed", Callable(self, "_on_entity_property_changed").bind(entity))
	
	if entity.has_signal("z_level_changed"):
		if entity.is_connected("z_level_changed", Callable(self, "_on_entity_z_level_changed").bind(entity)):
			entity.disconnect("z_level_changed", Callable(self, "_on_entity_z_level_changed").bind(entity))

# === SIGNAL HANDLERS ===
func _on_entity_moved(old_pos, new_pos, entity = null):
	"""Handle entity movement signals."""
	# Handle different signal signatures
	var moving_entity
	var old_tile_pos
	var new_tile_pos
	
	if entity == null:
		# This came from an entity emitting (self, old_tile, new_tile)
		moving_entity = old_pos
		old_tile_pos = new_pos
		new_tile_pos = moving_entity.current_tile_position
	else:
		# This came from GridMovementController emitting (old_tile, new_tile, self)
		moving_entity = entity
		old_tile_pos = old_pos
		new_tile_pos = new_pos
	
	# Update position in our tracking system
	update_entity_position(moving_entity)

func _on_entity_property_changed(property_name, old_value, new_value, entity):
	"""Handle entity property change signals."""
	if not _validate_entity(entity):
		return
	
	match property_name:
		"entity_dense":
			# Update DENSE flag
			update_entity_flags(entity, EntityFlags.DENSE, new_value)
		"entity_type":
			# Update entity type - this requires re-registering the entity
			unregister_entity(entity)
			register_entity(entity)
		_:
			# Ignore other property changes
			pass

func _on_entity_z_level_changed(old_z, new_z, position, entity):
	"""Handle entity z-level change signals."""
	if not _validate_entity(entity):
		return
	
	# This will handle updating all spatial structures
	update_entity_position(entity)

# === SPATIAL QUERIES ===
func get_entities_at_tile(tile_pos: Vector2i, z_level: int = 0) -> Array:
	"""Get all entities at a specific tile."""
	if not z_level in _tile_entities or not tile_pos in _tile_entities[z_level]:
		return []
	
	# Return a copy to prevent modification of internal array
	return _tile_entities[z_level][tile_pos].duplicate()

func get_entities_in_tile_radius(center_tile: Vector2i, radius: int, z_level: int = 0) -> Array:
	"""Get all entities within a tile radius of the center tile."""
	var result = []
	
	# Skip if z-level doesn't exist
	if not z_level in _tile_entities:
		return result
	
	# Calculate bounds for optimization
	var min_x = max(center_tile.x - radius, 0)
	var min_y = max(center_tile.y - radius, 0)
	var max_x = center_tile.x + radius
	var max_y = center_tile.y + radius
	
	# Get cells that might contain relevant tiles
	var min_cell = _tile_to_cell_coords(Vector2i(min_x, min_y))
	var max_cell = _tile_to_cell_coords(Vector2i(max_x, max_y))
	
	# Track processed entities to avoid duplicates
	var processed_entities = {}
	
	# Iterate through potential cells for better cache locality
	for cell_y in range(min_cell.y, max_cell.y + 1):
		for cell_x in range(min_cell.x, max_cell.x + 1):
			var cell_coords = Vector2i(cell_x, cell_y)
			
			# Skip if cell doesn't exist in spatial grid
			if not _spatial_grid[z_level].has(cell_coords):
				continue
			
			# Check all entity types in this cell
			for entity_type in _spatial_grid[z_level][cell_coords]:
				for entity in _spatial_grid[z_level][cell_coords][entity_type]:
					# Skip if already processed
					if entity in processed_entities:
						continue
					
					# Get entity position
					var entity_tile = _get_entity_tile_position(entity)
					
					# Calculate Manhattan distance (grid-based)
					var distance = abs(entity_tile.x - center_tile.x) + abs(entity_tile.y - center_tile.y)
					
					# Add entity if within radius
					if distance <= radius:
						result.append(entity)
						processed_entities[entity] = true
	
	return result

func get_entities_near(position: Vector2, radius: float, z_level: int = 0) -> Array:
	"""Get entities near a world position with radius in pixels."""
	# Convert position to tile coordinates
	var center_tile = world_to_tile(position)
	
	# Convert radius from pixels to tiles (rounded up)
	var tile_radius = ceili(radius / TILE_SIZE)
	
	# Use tile-based function
	var entities = get_entities_in_tile_radius(center_tile, tile_radius, z_level)
	
	# Refine results with exact pixel distance if needed
	if fposmod(radius, TILE_SIZE) != 0.0:
		var filtered_entities = []
		for entity in entities:
			var distance = position.distance_to(entity.position)
			if distance <= radius:
				filtered_entities.append(entity)
		return filtered_entities
	
	return entities

func get_entities_in_cell(cell_coords: Vector2i, z_level: int = 0) -> Array:
	"""Get all entities in a specific spatial cell."""
	if not z_level in _spatial_grid or not cell_coords in _spatial_grid[z_level]:
		return []
	
	var result = []
	
	# Gather entities from all types in this cell
	for entity_type in _spatial_grid[z_level][cell_coords]:
		result.append_array(_spatial_grid[z_level][cell_coords][entity_type])
	
	return result

func get_entities_in_tile_rectangle(top_left: Vector2i, bottom_right: Vector2i, z_level: int = 0) -> Array:
	"""Get entities in a rectangular region defined by tile coordinates."""
	var result = []
	
	# Skip if z-level doesn't exist
	if not z_level in _tile_entities:
		return result
	
	# Calculate cell bounds for optimization
	var min_cell = _tile_to_cell_coords(top_left)
	var max_cell = _tile_to_cell_coords(bottom_right)
	
	# Track processed entities to avoid duplicates
	var processed_entities = {}
	
	# Iterate through potential cells
	for cell_y in range(min_cell.y, max_cell.y + 1):
		for cell_x in range(min_cell.x, max_cell.x + 1):
			var cell_coords = Vector2i(cell_x, cell_y)
			
			# Skip if cell doesn't exist
			if not _spatial_grid[z_level].has(cell_coords):
				continue
			
			# Check all entity types in this cell
			for entity_type in _spatial_grid[z_level][cell_coords]:
				for entity in _spatial_grid[z_level][cell_coords][entity_type]:
					# Skip if already processed
					if entity in processed_entities:
						continue
					
					# Get entity position
					var entity_tile = _get_entity_tile_position(entity)
					
					# Check if entity is within rectangle
					if (entity_tile.x >= top_left.x and entity_tile.x <= bottom_right.x and
						entity_tile.y >= top_left.y and entity_tile.y <= bottom_right.y):
						result.append(entity)
						processed_entities[entity] = true
	
	return result

func get_entities_in_rectangle(top_left: Vector2, bottom_right: Vector2, z_level: int = 0) -> Array:
	"""Get entities in a rectangle defined by world coordinates."""
	# Convert to tile coordinates
	var top_left_tile = world_to_tile(top_left)
	var bottom_right_tile = world_to_tile(bottom_right)
	
	# Use tile-based function
	return get_entities_in_tile_rectangle(top_left_tile, bottom_right_tile, z_level)

func get_entities_by_type(type: String, z_level = null) -> Array:
	"""Get entities of a specific type, optionally filtered by z-level."""
	if not type in _entities_by_type:
		return []
	
	if z_level == null:
		return _entities_by_type[type].duplicate()
	
	# Filter by z-level
	var result = []
	for entity in _entities_by_type[type]:
		if _entity_current_z.has(entity.entity_id) and _entity_current_z[entity.entity_id] == z_level:
			result.append(entity)
	
	return result

func get_entities_by_flag(flag: int, z_level = null) -> Array:
	"""Get entities with a specific flag (dense, movable, etc.)."""
	if z_level == null:
		return _entities_by_flag[flag].duplicate()
	
	# Filter by z-level
	var result = []
	for entity in _entities_by_flag[flag]:
		if _entity_current_z.has(entity.entity_id) and _entity_current_z[entity.entity_id] == z_level:
			result.append(entity)
	
	return result

func get_nearest_entity_of_type(position: Vector2, type: String, max_distance: float = 1000, z_level: int = 0) -> Object:
	"""Get the nearest entity of a type to a position."""
	# Get center tile
	var center_tile = world_to_tile(position)
	
	# Convert max distance from pixels to tiles
	var tile_radius = ceili(max_distance / TILE_SIZE)
	
	# Get all entities of this type in range
	var potential_entities = []
	var all_type_entities = get_entities_by_type(type, z_level)
	
	for entity in all_type_entities:
		var entity_tile = _get_entity_tile_position(entity)
		
		# Check Manhattan distance for quick filtering
		var manhattan_dist = abs(entity_tile.x - center_tile.x) + abs(entity_tile.y - center_tile.y)
		if manhattan_dist <= tile_radius:
			potential_entities.append(entity)
	
	# Find the nearest
	var nearest = null
	var nearest_distance = max_distance
	
	for entity in potential_entities:
		var distance = position.distance_to(entity.position)
		if distance < nearest_distance:
			nearest = entity
			nearest_distance = distance
	
	return nearest

func get_entity_by_id(entity_id: String) -> Object:
	"""Get entity by ID."""
	return _entity_by_id.get(entity_id, null)

# === ADVANCED SPATIAL QUERIES ===
func get_entities_with_predicate(predicate_func: Callable, z_level: int = 0) -> Array:
	"""Get entities that match a predicate function."""
	var result = []
	
	for entity in _all_entities:
		if _entity_current_z.get(entity.entity_id, 0) == z_level:
			if predicate_func.call(entity):
				result.append(entity)
	
	return result

func get_entities_of_types(types: Array, z_level = null) -> Array:
	"""Get entities of any of the specified types."""
	var result = []
	var processed_entities = {}
	
	for type in types:
		var type_entities = get_entities_by_type(type, z_level)
		for entity in type_entities:
			if not entity in processed_entities:
				result.append(entity)
				processed_entities[entity] = true
	
	return result

func get_entities_with_flags(flags: int, z_level = null) -> Array:
	"""Get entities with all of the specified flags."""
	var result = []
	
	for entity in _all_entities:
		if z_level != null and _entity_current_z.get(entity.entity_id, 0) != z_level:
			continue
		
		var metadata = _entity_metadata.get(entity.entity_id, null)
		if metadata != null and (metadata.flags & flags) == flags:
			result.append(entity)
	
	return result

# === RAYCASTING AND LINE OF SIGHT ===
func raycast(start: Vector2, end: Vector2, z_level: int = 0, exclude_entities: Array = []):
	"""Cast a ray from start to end, stopping at the first collision."""
	# Get world reference
	var world = get_node_or_null("/root/World")
	if not world:
		return null
	
	# Convert to tile coordinates
	var start_tile = world_to_tile(start)
	var end_tile = world_to_tile(end)
	
	# Use tile-based raycasting
	return raycast_tiles(start_tile, end_tile, z_level, exclude_entities)

func raycast_tiles(start_tile: Vector2i, end_tile: Vector2i, z_level: int = 0, exclude_entities: Array = []):
	"""Cast a ray using tile coordinates."""
	# Check if we have this calculation cached
	var cache_key = str(start_tile) + "-" + str(end_tile) + "-" + str(z_level) + "-" + str(exclude_entities.hash())
	if z_level in _visibility_cache and cache_key in _visibility_cache[z_level]:
		# Update LRU cache order
		_visibility_cache_order.erase(cache_key)
		_visibility_cache_order.append(cache_key)
		return _visibility_cache[z_level][cache_key]
	
	# Get world reference
	var world = get_node_or_null("/root/World")
	if not world:
		return null
	
	var tiles = get_tiles_in_line(start_tile, end_tile)
	
	# Result data
	var result = {
		"visible": true,
		"blocked_by_tile": null,
		"blocked_by_entity": null,
		"tiles": tiles,
		"hit_position": null,
		"hit_normal": null
	}
	
	# Skip the starting tile in the check
	for i in range(1, tiles.size()):
		var tile = tiles[i]
		
		# Check for wall or obstacle at this tile
		if world.has_method("is_wall_at") and world.is_wall_at(tile, z_level):
			result.visible = false
			result.blocked_by_tile = tile
			# Calculate hit position (center of blocking tile)
			result.hit_position = tile_to_world(tile)
			# Calculate hit normal (from end tile to blocking tile)
			var dir_to_previous = (tiles[i-1] - tile).normalized()
			result.hit_normal = dir_to_previous
			break
		
		# Check for closed door
		if world.has_method("is_closed_door_at") and world.is_closed_door_at(tile, z_level):
			result.visible = false
			result.blocked_by_tile = tile
			result.hit_position = tile_to_world(tile)
			var dir_to_previous = (tiles[i-1] - tile).normalized()
			result.hit_normal = dir_to_previous
			break
		
		# Check for dense entities
		var entities_at_tile = get_entities_at_tile(tile, z_level)
		for entity in entities_at_tile:
			# Skip entities in the exclude list
			if entity in exclude_entities:
				continue
				
			# Skip if entity is not dense
			var is_dense = false
			
			# Check if entity has a dense flag in metadata
			if entity.entity_id in _entity_metadata:
				is_dense = _entity_metadata[entity.entity_id].flags & EntityFlags.DENSE
			else:
				# Fallback to entity property
				is_dense = ("entity_dense" in entity) and entity.entity_dense
			
			if not is_dense:
				continue
				
			result.visible = false
			result.blocked_by_entity = entity
			result.hit_position = entity.position
			# Calculate hit normal (from end tile to blocking entity)
			var dir_to_previous = (tiles[i-1] - tile).normalized()
			result.hit_normal = dir_to_previous
			break
			
		# Break loop if we found a blocking entity
		if not result.visible:
			break
	
	# Cache the result
	_cache_visibility_result(cache_key, result, z_level)
	
	return result

func get_tiles_in_line(start: Vector2i, end: Vector2i) -> Array:
	"""Get all tiles along a line using Bresenham's algorithm."""
	var tiles = []
	
	var x0 = start.x
	var y0 = start.y
	var x1 = end.x
	var y1 = end.y
	
	var dx = abs(x1 - x0)
	var dy = -abs(y1 - y0)
	var sx = 1 if x0 < x1 else -1
	var sy = 1 if y0 < y1 else -1
	var err = dx + dy
	
	while true:
		tiles.append(Vector2i(x0, y0))
		
		if x0 == x1 and y0 == y1:
			break
			
		var e2 = 2 * err
		if e2 >= dy:
			if x0 == x1:
				break
			err += dy
			x0 += sx
		if e2 <= dx:
			if y0 == y1:
				break
			err += dx
			y0 += sy
	
	return tiles

func has_line_of_sight(from_tile: Vector2i, to_tile: Vector2i, z_level: int = 0) -> bool:
	"""Check if two tiles have line of sight."""
	var result = raycast_tiles(from_tile, to_tile, z_level)
	return result.visible

func has_world_line_of_sight(from_pos: Vector2, to_pos: Vector2, z_level: int = 0) -> bool:
	"""Check if two world positions have line of sight."""
	var from_tile = world_to_tile(from_pos)
	var to_tile = world_to_tile(to_pos)
	return has_line_of_sight(from_tile, to_tile, z_level)

func get_entities_in_line_of_sight(from_tile: Vector2i, max_distance: int, z_level: int = 0, filter_types: Array = []):
	"""Get entities in line of sight from a position, optionally filtered by type."""
	var result = []
	
	# Get all entities within max distance
	var entities = get_entities_in_tile_radius(from_tile, max_distance, z_level)
	
	# Filter by type if requested
	var filtered_entities = entities
	if filter_types.size() > 0:
		filtered_entities = []
		for entity in entities:
			if entity.entity_id in _entity_metadata:
				var entity_type = _entity_metadata[entity.entity_id].entity_type
				if entity_type in filter_types:
					filtered_entities.append(entity)
	
	# Check line of sight to each entity
	for entity in filtered_entities:
		var entity_tile = _get_entity_tile_position(entity)
		if has_line_of_sight(from_tile, entity_tile, z_level):
			result.append(entity)
	
	return result

# === CACHE MANAGEMENT ===
func _cache_visibility_result(key: String, result, z_level: int):
	"""Cache a visibility calculation result."""
	# Ensure z-level cache exists
	if not z_level in _visibility_cache:
		_visibility_cache[z_level] = {}
	
	# Manage cache size using LRU
	if _visibility_cache_order.size() >= _visibility_cache_size:
		# Remove oldest entry
		var oldest_key = _visibility_cache_order.pop_front()
		var oldest_z = int(oldest_key.split("-")[2])
		_visibility_cache[oldest_z].erase(oldest_key)
	
	# Add to cache
	_visibility_cache[z_level][key] = result
	_visibility_cache_order.append(key)

func clear_visibility_cache(z_level: int = -1):
	"""Clear visibility cache for a specific z-level or all z-levels."""
	if z_level == -1:
		# Clear all caches
		for z in _visibility_cache:
			_visibility_cache[z].clear()
		_visibility_cache_order.clear()
	elif z_level in _visibility_cache:
		# Remove all entries for this z-level from order list
		var keys_to_remove = []
		for key in _visibility_cache_order:
			if int(key.split("-")[2]) == z_level:
				keys_to_remove.append(key)
		
		for key in keys_to_remove:
			_visibility_cache_order.erase(key)
		
		# Clear the z-level cache
		_visibility_cache[z_level].clear()

# === UTILITY FUNCTIONS ===
func _validate_entity(entity) -> bool:
	"""Validate that an entity has required properties."""
	if not is_instance_valid(entity):
		return false
		
	# Required properties
	var has_entity_id = "entity_id" in entity
	var has_entity_type = "entity_type" in entity
	var has_position = "position" in entity
	
	return has_entity_id and has_entity_type and has_position

func _create_entity_metadata(entity) -> Dictionary:
	"""Create metadata for an entity."""
	var metadata = {}
	
	# Get entity ID and type
	metadata.entity_id = entity.entity_id
	metadata.entity_type = entity.entity_type
	
	# Get position data
	metadata.position = entity.position
	metadata.tile_pos = _get_entity_tile_position(entity)
	metadata.z_level = _get_entity_z_level(entity)
	metadata.cell = _tile_to_cell_coords(metadata.tile_pos)
	
	# Determine flags
	var flags = EntityFlags.NONE
	
	# Check for dense flag
	if "entity_dense" in entity and entity.entity_dense:
		flags |= EntityFlags.DENSE
	
	# Check for movable flag (most entities are movable by default)
	var is_movable = true
	if "entity_movable" in entity:
		is_movable = entity.entity_movable
	if is_movable:
		flags |= EntityFlags.MOVABLE
	
	# Check for hearing flag
	if "hearing_range" in entity and entity.hearing_range > 0:
		flags |= EntityFlags.HEARING
	
	# Check for client-controlled flag
	if "is_client_controlled" in entity and entity.is_client_controlled:
		flags |= EntityFlags.CLIENT_CONTROLLED
	elif "is_local_player" in entity and entity.is_local_player:
		flags |= EntityFlags.CLIENT_CONTROLLED
	
	metadata.flags = flags
	
	# Include any other useful properties
	if "mass" in entity:
		metadata.mass = entity.mass
	
	if "size" in entity:
		metadata.size = entity.size
	
	return metadata

func _tile_to_cell_coords(tile_pos: Vector2i) -> Vector2i:
	"""Convert tile coordinates to spatial cell coordinates."""
	return Vector2i(
		floor(tile_pos.x / GRID_CELL_SIZE),
		floor(tile_pos.y / GRID_CELL_SIZE)
	)

func _get_entity_z_level(entity) -> int:
	"""Extract z-level from entity."""
	if entity is GridMovementController:
		return entity.current_z_level
	elif "current_z_level" in entity:
		return entity.current_z_level
	elif "current_z" in entity:
		return entity.current_z
	
	return 0  # Default to ground level

func _get_entity_tile_position(entity) -> Vector2i:
	"""Extract tile position from entity."""
	# First check our tracking dictionary
	if entity.entity_id in _entity_current_tile:
		return _entity_current_tile[entity.entity_id]
		
	# Next try the entity's own properties
	if entity:
		return entity.movement_component.current_tile_position
	
	# Fallback: Calculate from world position
	return world_to_tile(entity.position)

func world_to_tile(world_pos: Vector2) -> Vector2i:
	"""Convert world position to tile position."""
	var world = get_node_or_null("/root/World")
	if world and world.has_method("get_tile_at"):
		return world.get_tile_at(world_pos)
	
	# Fallback implementation
	return Vector2i(int(world_pos.x / TILE_SIZE), int(world_pos.y / TILE_SIZE))

func tile_to_world(tile_pos: Vector2i) -> Vector2:
	"""Convert tile position to world position (center of tile)."""
	var world = get_node_or_null("/root/World")
	if world and world.has_method("tile_to_world"):
		return world.tile_to_world(tile_pos)
	
	# Fallback implementation
	return Vector2(
		(tile_pos.x * TILE_SIZE) + (TILE_SIZE / 2),
		(tile_pos.y * TILE_SIZE) + (TILE_SIZE / 2)
	)

# === INTEGRATION WITH OTHER SYSTEMS ===
func notify_tile_changed(tile_coords, z_level, old_data, new_data):
	"""Handle tile data changes from World system."""
	# Clear visibility cache for this tile
	for key in _visibility_cache_order.duplicate():
		var parts = key.split("-")
		if parts.size() >= 3:
			var tile_x = int(parts[0].split(",")[0].substr(1))
			var tile_y = int(parts[0].split(",")[1].substr(0, parts[0].split(",")[1].length() - 1))
			var cache_z = int(parts[2])
			
			if cache_z == z_level and (
				tile_coords.x == tile_x or
				tile_coords.y == tile_y or
				tile_coords.distance_to(Vector2i(tile_x, tile_y)) < 5
			):
				_visibility_cache_order.erase(key)
				_visibility_cache[cache_z].erase(key)

# === DEBUGGING ===
func _setup_debug_draw():
	"""Set up visual debugging."""
	_debug_draw_node = Node2D.new()
	_debug_draw_node.name = "DebugDraw"
	_debug_draw_node.z_index = 100  # Draw above everything
	add_child(_debug_draw_node)
	
	# Connect draw signal for custom drawing
	_debug_draw_node.connect("draw", Callable(self, "_on_debug_draw"))

func _on_debug_draw():
	"""Draw debug visualization for spatial grid."""
	if not _debug_draw_node or not _visual_debug:
		return
	
	# Draw the grid cells for the current z-level
	var z_level = 0  # Default to ground level
	
	# Try to get current z-level from World or player
	var world = get_node_or_null("/root/World")
	if world and "current_z_level" in world:
		z_level = world.current_z_level
	
	# Clear previous drawings
	_debug_draw_node.queue_redraw()
	
	# Draw occupied cells
	var cell_size = GRID_CELL_SIZE * TILE_SIZE
	
	for cell_coords in _spatial_grid[z_level].keys():
		var entity_count = 0
		var has_dense = false
		
		# Count entities in this cell
		for entity_type in _spatial_grid[z_level][cell_coords]:
			entity_count += _spatial_grid[z_level][cell_coords][entity_type].size()
			
			# Check if any entity is dense
			for entity in _spatial_grid[z_level][cell_coords][entity_type]:
				if _entity_metadata.has(entity.entity_id) and (_entity_metadata[entity.entity_id].flags & EntityFlags.DENSE):
					has_dense = true
					break
		
		# Skip empty cells
		if entity_count == 0:
			continue
		
		# Choose color based on contents
		var color = Color.GREEN if not has_dense else Color.RED
		color.a = 0.3  # Semi-transparent
		
		# Draw cell rectangle
		var top_left = Vector2(cell_coords.x * cell_size, cell_coords.y * cell_size)
		_debug_draw_node.draw_rect(Rect2(top_left, Vector2(cell_size, cell_size)), color, false, 2)
		
		# Draw entity count
		_debug_draw_node.draw_string(ThemeDB.fallback_font, top_left + Vector2(5, 20), 
								   str(entity_count), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	
	# Draw active cache entries
	var cache_count = _visibility_cache.get(z_level, {}).size()
	var cache_text = "Vis Cache: " + str(cache_count) + "/" + str(_visibility_cache_size)
	_debug_draw_node.draw_string(ThemeDB.fallback_font, Vector2(10, 10), 
							   cache_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.YELLOW)

func set_debug(enabled: bool, visual: bool = false):
	"""Enable or disable debugging features."""
	_debug_enabled = enabled
	_visual_debug = visual
	
	if _visual_debug and not _debug_draw_node:
		_setup_debug_draw()
	elif not _visual_debug and _debug_draw_node:
		_debug_draw_node.queue_free()
		_debug_draw_node = null

func get_debug_stats() -> Dictionary:
	"""Get debug statistics about the spatial manager."""
	var stats = {
		"total_entities": _all_entities.size(),
		"entity_types": {},
		"flags": {
			"dense": _entities_by_flag[EntityFlags.DENSE].size(),
			"movable": _entities_by_flag[EntityFlags.MOVABLE].size(),
			"hearing": _entities_by_flag[EntityFlags.HEARING].size(),
			"client_controlled": _entities_by_flag[EntityFlags.CLIENT_CONTROLLED].size(),
		},
		"cache_size": 0,
		"z_levels": {}
	}
	
	# Count entities by type
	for entity_type in _entities_by_type:
		stats.entity_types[entity_type] = _entities_by_type[entity_type].size()
	
	# Count cache entries
	for z in _visibility_cache:
		stats.cache_size += _visibility_cache[z].size()
	
	# Count entities by z-level
	for z in range(MAX_Z_LEVELS):
		var count = 0
		var cells = 0
		
		if z in _spatial_grid:
			cells = _spatial_grid[z].size()
			
			for cell in _spatial_grid[z]:
				for entity_type in _spatial_grid[z][cell]:
					count += _spatial_grid[z][cell][entity_type].size()
		
		stats.z_levels[z] = {
			"entities": count,
			"cells": cells
		}
	
	return stats

# === PUBLIC API FOR DENSE ENTITY QUERIES ===
func get_dense_entities_at_tile(tile_pos: Vector2i, z_level: int = 0) -> Array:
	"""Get all dense entities in a tile."""
	var all_entities = get_entities_at_tile(tile_pos, z_level)
	var dense_entities = []
	
	for entity in all_entities:
		if entity.entity_id in _entity_metadata and (_entity_metadata[entity.entity_id].flags & EntityFlags.DENSE):
			dense_entities.append(entity)
		elif "entity_dense" in entity and entity.entity_dense:
			dense_entities.append(entity)
	
	return dense_entities

func has_dense_entity_at(tile_pos: Vector2i, z_level: int = 0, exclude_entity = null) -> bool:
	"""Check if a tile has any dense entities."""
	var entities = get_entities_at_tile(tile_pos, z_level)
	
	for entity in entities:
		if entity == exclude_entity:
			continue
			
		if entity.entity_id in _entity_metadata and (_entity_metadata[entity.entity_id].flags & EntityFlags.DENSE):
			return true
		elif "entity_dense" in entity and entity.entity_dense:
			return true
	
	return false

func get_reachable_tiles(start_tile: Vector2i, max_distance: int, z_level: int = 0) -> Array:
	"""Flood-fill to find all tiles reachable within a distance."""
	var world = get_node_or_null("/root/World")
	if not world:
		return []
		
	var reachable = []
	var visited = {}
	var queue = []
	
	# Start with the starting tile
	queue.append({"tile": start_tile, "distance": 0})
	visited[start_tile] = true
	
	# Process queue
	while queue.size() > 0:
		var current = queue.pop_front()
		var current_tile = current.tile
		var current_distance = current.distance
		
		# Add to result
		reachable.append(current_tile)
		
		# Skip if at max distance
		if current_distance >= max_distance:
			continue
		
		# Check neighbors
		var neighbors = [
			Vector2i(current_tile.x + 1, current_tile.y),
			Vector2i(current_tile.x - 1, current_tile.y),
			Vector2i(current_tile.x, current_tile.y + 1),
			Vector2i(current_tile.x, current_tile.y - 1)
		]
		
		for neighbor in neighbors:
			if neighbor in visited:
				continue
				
			# Check if tile is blocked
			if world.has_method("is_wall_at") and world.is_wall_at(neighbor, z_level):
				continue
				
			if world.has_method("is_closed_door_at") and world.is_closed_door_at(neighbor, z_level):
				continue
				
			if has_dense_entity_at(neighbor, z_level):
				continue
				
			# Add to queue
			queue.append({"tile": neighbor, "distance": current_distance + 1})
			visited[neighbor] = true
	
	return reachable

# Get entities at world position with a small radius
func get_entities_at_world_pos(world_pos: Vector2, z_level: int = 0, radius: float = 5.0) -> Array:
	"""Get entities at or very near a specific world position."""
	return get_entities_near(world_pos, radius, z_level)
