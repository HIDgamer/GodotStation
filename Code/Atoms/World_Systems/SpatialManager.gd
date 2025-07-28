extends Node
class_name SpatialManager

const TILE_SIZE = 32
const GRID_CELL_SIZE = 4
const MAX_Z_LEVELS = 10

enum QueryMode {
	EXACT,
	OVERLAPPING,
	CONTAINING,
	NEAREST
}

enum EntityFlags {
	NONE = 0,
	DENSE = 1,
	MOVABLE = 2,
	HEARING = 4,
	CLIENT_CONTROLLED = 8,
}

var _spatial_grid = {}
var _tile_entities = {}
var _all_entities = []
var _entity_by_id = {}
var _entities_by_type = {}
var _entities_by_flag = {}
var _entity_metadata = {}
var _entity_current_cell = {}
var _entity_current_tile = {}
var _entity_current_z = {}

var _visibility_cache = {}
var _visibility_cache_order = []
var _visibility_cache_size = 500

var _tile_occupancy_system = null
var _debug_enabled = false

signal entity_registered(entity, old_metadata, new_metadata)
signal entity_unregistered(entity, metadata)
signal entity_moved(entity, old_tile, new_tile, old_z, new_z)
signal entity_flag_changed(entity, flag, enabled)
signal spatial_query_completed(query_id, result)

func _ready():
	initialize()
	_connect_to_occupancy_system()

func initialize():
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
	
	for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.HEARING, EntityFlags.CLIENT_CONTROLLED]:
		_entities_by_flag[flag] = []

func _connect_to_occupancy_system():
	_tile_occupancy_system = get_node_or_null("../TileOccupancySystem")
	
	if not _tile_occupancy_system:
		_tile_occupancy_system = get_node_or_null("../ImprovedTileOccupancySystem")
	
	if not _tile_occupancy_system:
		_tile_occupancy_system = get_node_or_null("TileOccupancySystem")
	
	if not _tile_occupancy_system:
		var occupancy_systems = get_tree().get_nodes_in_group("tile_occupancy_system")
		if occupancy_systems.size() > 0:
			_tile_occupancy_system = occupancy_systems[0]

func register_entity(entity):
	if not _validate_entity(entity):
		return false
	
	var entity_id = entity.entity_id
	
	if entity_id in _entity_by_id:
		update_entity_position(entity)
		return true
	
	var metadata = _create_entity_metadata(entity)
	
	_all_entities.append(entity)
	_entity_by_id[entity_id] = entity
	
	var entity_type = metadata.entity_type
	if not entity_type in _entities_by_type:
		_entities_by_type[entity_type] = []
	_entities_by_type[entity_type].append(entity)
	
	for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.HEARING, EntityFlags.CLIENT_CONTROLLED]:
		if metadata.flags & flag:
			_entities_by_flag[flag].append(entity)
	
	var z_level = metadata.z_level
	for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.HEARING, EntityFlags.CLIENT_CONTROLLED]:
		if metadata.flags & flag:
			var tile_pos = metadata.tile_pos
			if not tile_pos in _entities_by_flag[z_level][flag]:
				_entities_by_flag[z_level][flag][tile_pos] = []
			_entities_by_flag[z_level][flag][tile_pos].append(entity)
	
	_add_to_spatial_structures(entity, metadata)
	_entity_metadata[entity_id] = metadata
	_connect_entity_signals(entity)
	
	emit_signal("entity_registered", entity, null, metadata)
	return true

func unregister_entity(entity):
	if not _validate_entity(entity):
		return false
	
	var entity_id = entity.entity_id
	
	if not entity_id in _entity_by_id:
		return false
	
	var metadata = _entity_metadata[entity_id]
	
	_all_entities.erase(entity)
	_entity_by_id.erase(entity_id)
	
	var entity_type = metadata.entity_type
	if entity_type in _entities_by_type:
		_entities_by_type[entity_type].erase(entity)
	
	for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.HEARING, EntityFlags.CLIENT_CONTROLLED]:
		if metadata.flags & flag:
			_entities_by_flag[flag].erase(entity)
	
	var z_level = metadata.z_level
	for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.HEARING, EntityFlags.CLIENT_CONTROLLED]:
		if metadata.flags & flag:
			var tile_pos = metadata.tile_pos
			if z_level in _entities_by_flag and flag in _entities_by_flag[z_level] and tile_pos in _entities_by_flag[z_level][flag]:
				_entities_by_flag[z_level][flag][tile_pos].erase(entity)
	
	_remove_from_spatial_structures(entity, metadata)
	
	_entity_current_cell.erase(entity_id)
	_entity_current_tile.erase(entity_id)
	_entity_current_z.erase(entity_id)
	_entity_metadata.erase(entity_id)
	
	_disconnect_entity_signals(entity)
	
	emit_signal("entity_unregistered", entity, metadata)
	return true

func update_entity_position(entity):
	if not _validate_entity(entity):
		return false
	
	var entity_id = entity.entity_id
	
	if not entity_id in _entity_by_id:
		return register_entity(entity)
	
	var old_metadata = _entity_metadata[entity_id]
	var new_metadata = _create_entity_metadata(entity)
	
	if old_metadata.tile_pos == new_metadata.tile_pos and old_metadata.z_level == new_metadata.z_level:
		return false
	
	_remove_from_spatial_structures(entity, old_metadata)
	_add_to_spatial_structures(entity, new_metadata)
	
	_entity_metadata[entity_id] = new_metadata
	_entity_current_tile[entity_id] = new_metadata.tile_pos
	_entity_current_cell[entity_id] = new_metadata.cell
	_entity_current_z[entity_id] = new_metadata.z_level
	
	emit_signal("entity_moved", entity, old_metadata.tile_pos, new_metadata.tile_pos, 
				old_metadata.z_level, new_metadata.z_level)
	
	return true

func update_entity_flags(entity, flags, enabled = true):
	if not _validate_entity(entity):
		return false
	
	var entity_id = entity.entity_id
	
	if not entity_id in _entity_by_id:
		return false
	
	var metadata = _entity_metadata[entity_id]
	var old_flags = metadata.flags
	
	if enabled:
		metadata.flags |= flags
	else:
		metadata.flags &= ~flags
	
	if old_flags == metadata.flags:
		return false
	
	for flag in [EntityFlags.DENSE, EntityFlags.MOVABLE, EntityFlags.HEARING, EntityFlags.CLIENT_CONTROLLED]:
		if flag & flags:
			var was_set = old_flags & flag
			var is_set = metadata.flags & flag
			
			if was_set != is_set:
				if is_set:
					_entities_by_flag[flag].append(entity)
					
					var z_level = metadata.z_level
					var tile_pos = metadata.tile_pos
					if not tile_pos in _entities_by_flag[z_level][flag]:
						_entities_by_flag[z_level][flag][tile_pos] = []
					_entities_by_flag[z_level][flag][tile_pos].append(entity)
				else:
					_entities_by_flag[flag].erase(entity)
					
					var z_level = metadata.z_level
					var tile_pos = metadata.tile_pos
					if z_level in _entities_by_flag and flag in _entities_by_flag[z_level] and tile_pos in _entities_by_flag[z_level][flag]:
						_entities_by_flag[z_level][flag][tile_pos].erase(entity)
				
				emit_signal("entity_flag_changed", entity, flag, is_set)
	
	_entity_metadata[entity_id] = metadata
	return true

func _add_to_spatial_structures(entity, metadata):
	var entity_id = entity.entity_id
	var z_level = metadata.z_level
	var tile_pos = metadata.tile_pos
	var cell = metadata.cell
	
	if not tile_pos in _tile_entities[z_level]:
		_tile_entities[z_level][tile_pos] = []
	if not entity in _tile_entities[z_level][tile_pos]:
		_tile_entities[z_level][tile_pos].append(entity)
	
	if not cell in _spatial_grid[z_level]:
		_spatial_grid[z_level][cell] = {}
	var entity_type = metadata.entity_type
	if not entity_type in _spatial_grid[z_level][cell]:
		_spatial_grid[z_level][cell][entity_type] = []
	if not entity in _spatial_grid[z_level][cell][entity_type]:
		_spatial_grid[z_level][cell][entity_type].append(entity)
	
	if _tile_occupancy_system and _tile_occupancy_system.has_method("register_entity_at_tile"):
		_tile_occupancy_system.register_entity_at_tile(entity, tile_pos, z_level)
	
	_entity_current_cell[entity_id] = cell
	_entity_current_tile[entity_id] = tile_pos
	_entity_current_z[entity_id] = z_level

func _remove_from_spatial_structures(entity, metadata):
	var entity_id = entity.entity_id
	var z_level = metadata.z_level
	var tile_pos = metadata.tile_pos
	var cell = metadata.cell
	
	if z_level in _tile_entities and tile_pos in _tile_entities[z_level]:
		_tile_entities[z_level][tile_pos].erase(entity)
		if _tile_entities[z_level][tile_pos].size() == 0:
			_tile_entities[z_level].erase(tile_pos)
	
	var entity_type = metadata.entity_type
	if z_level in _spatial_grid and cell in _spatial_grid[z_level] and entity_type in _spatial_grid[z_level][cell]:
		_spatial_grid[z_level][cell][entity_type].erase(entity)
		if _spatial_grid[z_level][cell][entity_type].size() == 0:
			_spatial_grid[z_level][cell].erase(entity_type)
		if _spatial_grid[z_level][cell].size() == 0:
			_spatial_grid[z_level].erase(cell)
	
	if _tile_occupancy_system and _tile_occupancy_system.has_method("remove_entity"):
		_tile_occupancy_system.remove_entity(entity, tile_pos, z_level)

func _connect_entity_signals(entity):
	if entity.has_signal("entity_moved"):
		if entity is GridMovementController:
			if not entity.is_connected("entity_moved", Callable(self, "_on_entity_moved")):
				entity.connect("entity_moved", Callable(self, "_on_entity_moved"))
		else:
			if not entity.is_connected("entity_moved", Callable(self, "_on_entity_moved").bind(entity)):
				entity.connect("entity_moved", Callable(self, "_on_entity_moved").bind(entity))
	
	if entity.has_signal("property_changed"):
		if not entity.is_connected("property_changed", Callable(self, "_on_entity_property_changed").bind(entity)):
			entity.connect("property_changed", Callable(self, "_on_entity_property_changed").bind(entity))
	
	if entity.has_signal("z_level_changed"):
		if not entity.is_connected("z_level_changed", Callable(self, "_on_entity_z_level_changed").bind(entity)):
			entity.connect("z_level_changed", Callable(self, "_on_entity_z_level_changed").bind(entity))

func _disconnect_entity_signals(entity):
	if entity.has_signal("entity_moved"):
		if entity.is_connected("entity_moved", Callable(self, "_on_entity_moved")):
			entity.disconnect("entity_moved", Callable(self, "_on_entity_moved"))
	
	if entity.has_signal("property_changed"):
		if entity.is_connected("property_changed", Callable(self, "_on_entity_property_changed").bind(entity)):
			entity.disconnect("property_changed", Callable(self, "_on_entity_property_changed").bind(entity))
	
	if entity.has_signal("z_level_changed"):
		if entity.is_connected("z_level_changed", Callable(self, "_on_entity_z_level_changed").bind(entity)):
			entity.disconnect("z_level_changed", Callable(self, "_on_entity_z_level_changed").bind(entity))

func _on_entity_moved(old_pos, new_pos, entity = null):
	var moving_entity
	var old_tile_pos
	var new_tile_pos
	
	if entity == null:
		moving_entity = old_pos
		old_tile_pos = new_pos
		new_tile_pos = moving_entity.current_tile_position
	else:
		moving_entity = entity
		old_tile_pos = old_pos
		new_tile_pos = new_pos
	
	update_entity_position(moving_entity)

func _on_entity_property_changed(property_name, old_value, new_value, entity):
	if not _validate_entity(entity):
		return
	
	match property_name:
		"entity_dense":
			update_entity_flags(entity, EntityFlags.DENSE, new_value)
		"entity_type":
			unregister_entity(entity)
			register_entity(entity)

func _on_entity_z_level_changed(old_z, new_z, position, entity):
	if not _validate_entity(entity):
		return
	
	update_entity_position(entity)

func get_entities_at_tile(tile_pos: Vector2i, z_level: int = 0) -> Array:
	if not z_level in _tile_entities or not tile_pos in _tile_entities[z_level]:
		return []
	
	return _tile_entities[z_level][tile_pos].duplicate()

func get_entities_in_tile_radius(center_tile: Vector2i, radius: int, z_level: int = 0) -> Array:
	var result = []
	
	if not z_level in _tile_entities:
		return result
	
	var min_x = max(center_tile.x - radius, 0)
	var min_y = max(center_tile.y - radius, 0)
	var max_x = center_tile.x + radius
	var max_y = center_tile.y + radius
	
	var min_cell = _tile_to_cell_coords(Vector2i(min_x, min_y))
	var max_cell = _tile_to_cell_coords(Vector2i(max_x, max_y))
	
	var processed_entities = {}
	
	for cell_y in range(min_cell.y, max_cell.y + 1):
		for cell_x in range(min_cell.x, max_cell.x + 1):
			var cell_coords = Vector2i(cell_x, cell_y)
			
			if not _spatial_grid[z_level].has(cell_coords):
				continue
			
			for entity_type in _spatial_grid[z_level][cell_coords]:
				for entity in _spatial_grid[z_level][cell_coords][entity_type]:
					if entity in processed_entities:
						continue
					
					var entity_tile = _get_entity_tile_position(entity)
					
					var distance = abs(entity_tile.x - center_tile.x) + abs(entity_tile.y - center_tile.y)
					
					if distance <= radius:
						result.append(entity)
						processed_entities[entity] = true
	
	return result

func get_entities_near(position: Vector2, radius: float, z_level: int = 0) -> Array:
	var center_tile = world_to_tile(position)
	var tile_radius = ceili(radius / TILE_SIZE)
	
	var entities = get_entities_in_tile_radius(center_tile, tile_radius, z_level)
	
	if fposmod(radius, TILE_SIZE) != 0.0:
		var filtered_entities = []
		for entity in entities:
			var distance = position.distance_to(entity.position)
			if distance <= radius:
				filtered_entities.append(entity)
		return filtered_entities
	
	return entities

func get_entities_in_cell(cell_coords: Vector2i, z_level: int = 0) -> Array:
	if not z_level in _spatial_grid or not cell_coords in _spatial_grid[z_level]:
		return []
	
	var result = []
	
	for entity_type in _spatial_grid[z_level][cell_coords]:
		result.append_array(_spatial_grid[z_level][cell_coords][entity_type])
	
	return result

func get_entities_in_tile_rectangle(top_left: Vector2i, bottom_right: Vector2i, z_level: int = 0) -> Array:
	var result = []
	
	if not z_level in _tile_entities:
		return result
	
	var min_cell = _tile_to_cell_coords(top_left)
	var max_cell = _tile_to_cell_coords(bottom_right)
	
	var processed_entities = {}
	
	for cell_y in range(min_cell.y, max_cell.y + 1):
		for cell_x in range(min_cell.x, max_cell.x + 1):
			var cell_coords = Vector2i(cell_x, cell_y)
			
			if not _spatial_grid[z_level].has(cell_coords):
				continue
			
			for entity_type in _spatial_grid[z_level][cell_coords]:
				for entity in _spatial_grid[z_level][cell_coords][entity_type]:
					if entity in processed_entities:
						continue
					
					var entity_tile = _get_entity_tile_position(entity)
					
					if (entity_tile.x >= top_left.x and entity_tile.x <= bottom_right.x and
						entity_tile.y >= top_left.y and entity_tile.y <= bottom_right.y):
						result.append(entity)
						processed_entities[entity] = true
	
	return result

func get_entities_in_rectangle(top_left: Vector2, bottom_right: Vector2, z_level: int = 0) -> Array:
	var top_left_tile = world_to_tile(top_left)
	var bottom_right_tile = world_to_tile(bottom_right)
	
	return get_entities_in_tile_rectangle(top_left_tile, bottom_right_tile, z_level)

func get_entities_by_type(type: String, z_level = null) -> Array:
	if not type in _entities_by_type:
		return []
	
	if z_level == null:
		return _entities_by_type[type].duplicate()
	
	var result = []
	for entity in _entities_by_type[type]:
		if _entity_current_z.has(entity.entity_id) and _entity_current_z[entity.entity_id] == z_level:
			result.append(entity)
	
	return result

func get_entities_by_flag(flag: int, z_level = null) -> Array:
	if z_level == null:
		return _entities_by_flag[flag].duplicate()
	
	var result = []
	for entity in _entities_by_flag[flag]:
		if _entity_current_z.has(entity.entity_id) and _entity_current_z[entity.entity_id] == z_level:
			result.append(entity)
	
	return result

func get_nearest_entity_of_type(position: Vector2, type: String, max_distance: float = 1000, z_level: int = 0) -> Object:
	var center_tile = world_to_tile(position)
	var tile_radius = ceili(max_distance / TILE_SIZE)
	
	var potential_entities = []
	var all_type_entities = get_entities_by_type(type, z_level)
	
	for entity in all_type_entities:
		var entity_tile = _get_entity_tile_position(entity)
		
		var manhattan_dist = abs(entity_tile.x - center_tile.x) + abs(entity_tile.y - center_tile.y)
		if manhattan_dist <= tile_radius:
			potential_entities.append(entity)
	
	var nearest = null
	var nearest_distance = max_distance
	
	for entity in potential_entities:
		var distance = position.distance_to(entity.position)
		if distance < nearest_distance:
			nearest = entity
			nearest_distance = distance
	
	return nearest

func get_entity_by_id(entity_id: String) -> Object:
	return _entity_by_id.get(entity_id, null)

func get_entities_with_predicate(predicate_func: Callable, z_level: int = 0) -> Array:
	var result = []
	
	for entity in _all_entities:
		if _entity_current_z.get(entity.entity_id, 0) == z_level:
			if predicate_func.call(entity):
				result.append(entity)
	
	return result

func get_entities_of_types(types: Array, z_level = null) -> Array:
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
	var result = []
	
	for entity in _all_entities:
		if z_level != null and _entity_current_z.get(entity.entity_id, 0) != z_level:
			continue
		
		var metadata = _entity_metadata.get(entity.entity_id, null)
		if metadata != null and (metadata.flags & flags) == flags:
			result.append(entity)
	
	return result

func raycast(start: Vector2, end: Vector2, z_level: int = 0, exclude_entities: Array = []):
	var world = get_node_or_null("/root/World")
	if not world:
		return null
	
	var start_tile = world_to_tile(start)
	var end_tile = world_to_tile(end)
	
	return raycast_tiles(start_tile, end_tile, z_level, exclude_entities)

func raycast_tiles(start_tile: Vector2i, end_tile: Vector2i, z_level: int = 0, exclude_entities: Array = []):
	var cache_key = str(start_tile) + "-" + str(end_tile) + "-" + str(z_level) + "-" + str(exclude_entities.hash())
	if z_level in _visibility_cache and cache_key in _visibility_cache[z_level]:
		_visibility_cache_order.erase(cache_key)
		_visibility_cache_order.append(cache_key)
		return _visibility_cache[z_level][cache_key]
	
	var world = get_node_or_null("/root/World")
	if not world:
		return null
	
	var tiles = get_tiles_in_line(start_tile, end_tile)
	
	var result = {
		"visible": true,
		"blocked_by_tile": null,
		"blocked_by_entity": null,
		"tiles": tiles,
		"hit_position": null,
		"hit_normal": null
	}
	
	for i in range(1, tiles.size()):
		var tile = tiles[i]
		
		if world.has_method("is_wall_at") and world.is_wall_at(tile, z_level):
			result.visible = false
			result.blocked_by_tile = tile
			result.hit_position = tile_to_world(tile)
			var dir_to_previous = (tiles[i-1] - tile).normalized()
			result.hit_normal = dir_to_previous
			break
		
		if world.has_method("is_closed_door_at") and world.is_closed_door_at(tile, z_level):
			result.visible = false
			result.blocked_by_tile = tile
			result.hit_position = tile_to_world(tile)
			var dir_to_previous = (tiles[i-1] - tile).normalized()
			result.hit_normal = dir_to_previous
			break
		
		var entities_at_tile = get_entities_at_tile(tile, z_level)
		for entity in entities_at_tile:
			if entity in exclude_entities:
				continue
				
			var is_dense = false
			
			if entity.entity_id in _entity_metadata:
				is_dense = _entity_metadata[entity.entity_id].flags & EntityFlags.DENSE
			else:
				is_dense = ("entity_dense" in entity) and entity.entity_dense
			
			if not is_dense:
				continue
				
			result.visible = false
			result.blocked_by_entity = entity
			result.hit_position = entity.position
			var dir_to_previous = (tiles[i-1] - tile).normalized()
			result.hit_normal = dir_to_previous
			break
			
		if not result.visible:
			break
	
	_cache_visibility_result(cache_key, result, z_level)
	
	return result

func get_tiles_in_line(start: Vector2i, end: Vector2i) -> Array:
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
	var result = raycast_tiles(from_tile, to_tile, z_level)
	return result.visible

func has_world_line_of_sight(from_pos: Vector2, to_pos: Vector2, z_level: int = 0) -> bool:
	var from_tile = world_to_tile(from_pos)
	var to_tile = world_to_tile(to_pos)
	return has_line_of_sight(from_tile, to_tile, z_level)

func get_entities_in_line_of_sight(from_tile: Vector2i, max_distance: int, z_level: int = 0, filter_types: Array = []):
	var result = []
	
	var entities = get_entities_in_tile_radius(from_tile, max_distance, z_level)
	
	var filtered_entities = entities
	if filter_types.size() > 0:
		filtered_entities = []
		for entity in entities:
			if entity.entity_id in _entity_metadata:
				var entity_type = _entity_metadata[entity.entity_id].entity_type
				if entity_type in filter_types:
					filtered_entities.append(entity)
	
	for entity in filtered_entities:
		var entity_tile = _get_entity_tile_position(entity)
		if has_line_of_sight(from_tile, entity_tile, z_level):
			result.append(entity)
	
	return result

func _cache_visibility_result(key: String, result, z_level: int):
	if not z_level in _visibility_cache:
		_visibility_cache[z_level] = {}
	
	if _visibility_cache_order.size() >= _visibility_cache_size:
		var oldest_key = _visibility_cache_order.pop_front()
		var oldest_z = int(oldest_key.split("-")[2])
		_visibility_cache[oldest_z].erase(oldest_key)
	
	_visibility_cache[z_level][key] = result
	_visibility_cache_order.append(key)

func clear_visibility_cache(z_level: int = -1):
	if z_level == -1:
		for z in _visibility_cache:
			_visibility_cache[z].clear()
		_visibility_cache_order.clear()
	elif z_level in _visibility_cache:
		var keys_to_remove = []
		for key in _visibility_cache_order:
			if int(key.split("-")[2]) == z_level:
				keys_to_remove.append(key)
		
		for key in keys_to_remove:
			_visibility_cache_order.erase(key)
		
		_visibility_cache[z_level].clear()

func _validate_entity(entity) -> bool:
	if not is_instance_valid(entity):
		return false
		
	var has_entity_id = "entity_id" in entity
	var has_entity_type = "entity_type" in entity
	var has_position = "position" in entity
	
	return has_entity_id and has_entity_type and has_position

func _create_entity_metadata(entity) -> Dictionary:
	var metadata = {}
	
	metadata.entity_id = entity.entity_id
	metadata.entity_type = entity.entity_type
	
	metadata.position = entity.position
	metadata.tile_pos = _get_entity_tile_position(entity)
	metadata.z_level = _get_entity_z_level(entity)
	metadata.cell = _tile_to_cell_coords(metadata.tile_pos)
	
	var flags = EntityFlags.NONE
	
	if "entity_dense" in entity and entity.entity_dense:
		flags |= EntityFlags.DENSE
	
	var is_movable = true
	if "entity_movable" in entity:
		is_movable = entity.entity_movable
	if is_movable:
		flags |= EntityFlags.MOVABLE
	
	if "hearing_range" in entity and entity.hearing_range > 0:
		flags |= EntityFlags.HEARING
	
	if "is_client_controlled" in entity and entity.is_client_controlled:
		flags |= EntityFlags.CLIENT_CONTROLLED
	elif "is_local_player" in entity and entity.is_local_player:
		flags |= EntityFlags.CLIENT_CONTROLLED
	
	metadata.flags = flags
	
	if "mass" in entity:
		metadata.mass = entity.mass
	
	if "size" in entity:
		metadata.size = entity.size
	
	return metadata

func _tile_to_cell_coords(tile_pos: Vector2i) -> Vector2i:
	return Vector2i(
		floor(tile_pos.x / GRID_CELL_SIZE),
		floor(tile_pos.y / GRID_CELL_SIZE)
	)

func _get_entity_z_level(entity) -> int:
	if entity is GridMovementController:
		return entity.current_z_level
	elif "current_z_level" in entity:
		return entity.current_z_level
	elif "current_z" in entity:
		return entity.current_z
	
	return 0

func _get_entity_tile_position(entity) -> Vector2i:
	if entity.entity_id in _entity_current_tile:
		return _entity_current_tile[entity.entity_id]
		
	if entity:
		return entity.movement_component.current_tile_position
	
	return world_to_tile(entity.position)

func world_to_tile(world_pos: Vector2) -> Vector2i:
	var world = get_node_or_null("/root/World")
	if world and world.has_method("get_tile_at"):
		return world.get_tile_at(world_pos)
	
	return Vector2i(int(world_pos.x / TILE_SIZE), int(world_pos.y / TILE_SIZE))

func tile_to_world(tile_pos: Vector2i) -> Vector2:
	var world = get_node_or_null("/root/World")
	if world and world.has_method("tile_to_world"):
		return world.tile_to_world(tile_pos)
	
	return Vector2(
		(tile_pos.x * TILE_SIZE) + (TILE_SIZE / 2),
		(tile_pos.y * TILE_SIZE) + (TILE_SIZE / 2)
	)

func notify_tile_changed(tile_coords, z_level, old_data, new_data):
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

func get_debug_stats() -> Dictionary:
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
	
	for entity_type in _entities_by_type:
		stats.entity_types[entity_type] = _entities_by_type[entity_type].size()
	
	for z in _visibility_cache:
		stats.cache_size += _visibility_cache[z].size()
	
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

func get_dense_entities_at_tile(tile_pos: Vector2i, z_level: int = 0) -> Array:
	var all_entities = get_entities_at_tile(tile_pos, z_level)
	var dense_entities = []
	
	for entity in all_entities:
		if entity.entity_id in _entity_metadata and (_entity_metadata[entity.entity_id].flags & EntityFlags.DENSE):
			dense_entities.append(entity)
		elif "entity_dense" in entity and entity.entity_dense:
			dense_entities.append(entity)
	
	return dense_entities

func has_dense_entity_at(tile_pos: Vector2i, z_level: int = 0, exclude_entity = null) -> bool:
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
	var world = get_node_or_null("/root/World")
	if not world:
		return []
		
	var reachable = []
	var visited = {}
	var queue = []
	
	queue.append({"tile": start_tile, "distance": 0})
	visited[start_tile] = true
	
	while queue.size() > 0:
		var current = queue.pop_front()
		var current_tile = current.tile
		var current_distance = current.distance
		
		reachable.append(current_tile)
		
		if current_distance >= max_distance:
			continue
		
		var neighbors = [
			Vector2i(current_tile.x + 1, current_tile.y),
			Vector2i(current_tile.x - 1, current_tile.y),
			Vector2i(current_tile.x, current_tile.y + 1),
			Vector2i(current_tile.x, current_tile.y - 1)
		]
		
		for neighbor in neighbors:
			if neighbor in visited:
				continue
				
			if world.has_method("is_wall_at") and world.is_wall_at(neighbor, z_level):
				continue
				
			if world.has_method("is_closed_door_at") and world.is_closed_door_at(neighbor, z_level):
				continue
				
			if has_dense_entity_at(neighbor, z_level):
				continue
				
			queue.append({"tile": neighbor, "distance": current_distance + 1})
			visited[neighbor] = true
	
	return reachable

func get_entities_at_world_pos(world_pos: Vector2, z_level: int = 0, radius: float = 5.0) -> Array:
	return get_entities_near(world_pos, radius, z_level)
