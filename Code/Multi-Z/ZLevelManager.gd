extends Node
class_name ZLevelManager

signal z_level_changed(entity: Node, old_z: int, new_z: int)
signal entity_moved_z_level(entity: Node, old_z: int, new_z: int, position: Vector2i)

@export_group("Z-Level Configuration")
@export var max_z_levels: int = 10
@export var default_z_level: int = 0

var entities_by_z_level: Dictionary = {}
var entity_z_levels: Dictionary = {}

var world: Node = null
var tile_occupancy_system: Node = null
var tilemap_visualizer: Node = null
var stair_manager: Node = null
var z_level_visual_manager: Node = null

func _ready():
	add_to_group("z_level_manager")
	call_deferred("_initialize_system")

func _initialize_system():
	_find_system_references()
	_initialize_z_level_tracking()

func _find_system_references():
	world = get_tree().get_first_node_in_group("world")
	
	if world:
		tile_occupancy_system = world.get_node_or_null("TileOccupancySystem")
		tilemap_visualizer = world.get_node_or_null("VisualTileMap")
		z_level_visual_manager = world.get_node_or_null("ZLevelVisualManager")
		stair_manager = world.get_node_or_null("StairManager")
	if not tile_occupancy_system:
		tile_occupancy_system = get_tree().get_first_node_in_group("tile_occupancy_system")
	
	if not stair_manager:
		stair_manager = get_tree().get_first_node_in_group("stair_manager")
	
	if not z_level_visual_manager:
		z_level_visual_manager = get_tree().get_first_node_in_group("z_level_visual_manager")
	
	if stair_manager and stair_manager.has_signal("player_z_level_changed"):
		stair_manager.connect("player_z_level_changed", _on_stair_triggered_z_change)
		print("ZLevelManager: Connected to StairManager")
	else:
		print("ZLevelManager: Warning - StairManager not found or missing signal")
	
	print("ZLevelManager: Found systems - Tile Occupancy: ", tile_occupancy_system != null, ", Tilemap Visualizer: ", tilemap_visualizer != null, ", Z Visual Manager: ", z_level_visual_manager != null)

func _initialize_z_level_tracking():
	for z in range(max_z_levels):
		entities_by_z_level[z] = []
	
	call_deferred("_register_existing_players")

func _register_existing_players():
	var players = get_tree().get_nodes_in_group("player_controller")
	for player in players:
		var z_level = default_z_level
		if "current_z_level" in player:
			z_level = player.current_z_level
		
		register_entity(player, z_level)
		print("ZLevelManager: Registered existing player at Z-level ", z_level)
		
		if z_level_visual_manager:
			z_level_visual_manager.set_active_z_level(z_level)

func register_entity(entity: Node, z_level: int = default_z_level):
	if not entity:
		return
	
	var entity_id = _get_entity_id(entity)
	
	if entity_id in entity_z_levels:
		var old_z = entity_z_levels[entity_id]
		_remove_entity_from_z_level(entity, old_z)
	
	if not z_level in entities_by_z_level:
		entities_by_z_level[z_level] = []
	
	entities_by_z_level[z_level].append(entity)
	entity_z_levels[entity_id] = z_level
	
	if "current_z_level" in entity:
		entity.current_z_level = z_level

func unregister_entity(entity: Node):
	if not entity:
		return
	
	var entity_id = _get_entity_id(entity)
	if entity_id in entity_z_levels:
		var z_level = entity_z_levels[entity_id]
		_remove_entity_from_z_level(entity, z_level)
		entity_z_levels.erase(entity_id)

func move_entity_to_z_level(entity: Node, target_z: int, target_position: Vector2i = Vector2i(-1, -1)) -> bool:
	if not entity or target_z < 0 or target_z >= max_z_levels:
		print("ZLevelManager: Invalid entity or Z-level for movement: ", target_z)
		return false
	
	var entity_id = _get_entity_id(entity)
	var old_z = entity_z_levels.get(entity_id, default_z_level)
	
	if old_z == target_z:
		return true
	
	print("ZLevelManager: Moving entity from Z-level ", old_z, " to ", target_z)
	
	_remove_entity_from_z_level(entity, old_z)
	
	if not target_z in entities_by_z_level:
		entities_by_z_level[target_z] = []
	
	entities_by_z_level[target_z].append(entity)
	entity_z_levels[entity_id] = target_z
	
	if "current_z_level" in entity:
		entity.current_z_level = target_z
	
	if "z_level_component" in entity and entity.z_level_component:
		entity.z_level_component.current_z_level = target_z
	
	if target_position != Vector2i(-1, -1):
		_move_entity_to_position(entity, target_position)
	
	if tile_occupancy_system:
		var current_pos = _get_entity_tile_position(entity)
		if tile_occupancy_system.has_method("move_entity_z"):
			tile_occupancy_system.move_entity_z(entity, current_pos, current_pos, old_z, target_z)
		elif tile_occupancy_system.has_method("unregister_entity") and tile_occupancy_system.has_method("register_entity_at_tile"):
			tile_occupancy_system.unregister_entity(entity, current_pos, old_z)
			tile_occupancy_system.register_entity_at_tile(entity, current_pos, target_z)
	
	emit_signal("z_level_changed", entity, old_z, target_z)
	emit_signal("entity_moved_z_level", entity, old_z, target_z, _get_entity_tile_position(entity))
	
	if entity.is_in_group("player_controller") and z_level_visual_manager:
		z_level_visual_manager.set_active_z_level(target_z)
	
	print("ZLevelManager: Successfully moved entity to Z-level ", target_z)
	return true

func get_entity_z_level(entity: Node) -> int:
	if not entity:
		return -1
	
	var entity_id = _get_entity_id(entity)
	return entity_z_levels.get(entity_id, -1)

func get_entities_on_z_level(z_level: int) -> Array:
	return entities_by_z_level.get(z_level, []).duplicate()

func _get_entity_id(entity: Node) -> String:
	if "entity_id" in entity and entity.entity_id != "":
		return entity.entity_id
	return str(entity.get_instance_id())

func _remove_entity_from_z_level(entity: Node, z_level: int):
	if z_level in entities_by_z_level:
		entities_by_z_level[z_level].erase(entity)

func _get_entity_tile_position(entity: Node) -> Vector2i:
	if entity.has_method("get_current_tile_position"):
		return entity.get_current_tile_position()
	elif "movement_component" in entity and entity.movement_component:
		if "current_tile_position" in entity.movement_component:
			return entity.movement_component.current_tile_position
	
	return Vector2i.ZERO

func _move_entity_to_position(entity: Node, position: Vector2i):
	if entity.has_method("move_externally"):
		entity.move_externally(position, true, false)
	elif "movement_component" in entity and entity.movement_component:
		if entity.movement_component.has_method("move_externally"):
			entity.movement_component.move_externally(position, true, false)
		else:
			entity.movement_component.current_tile_position = position
			entity.movement_component.previous_tile_position = position
			if world and world.has_method("tile_to_world"):
				entity.position = world.tile_to_world(position)

func _on_stair_triggered_z_change(new_z_level: int):
	print("ZLevelManager: Stair triggered Z-level change to ", new_z_level)
	var players = get_tree().get_nodes_in_group("player_controller")
	if players.size() > 0:
		var player = players[0]
		move_entity_to_z_level(player, new_z_level)
	else:
		print("ZLevelManager: No player found for stair movement")

func is_wall_at(tile_coords: Vector2i, z_level: int) -> bool:
	if not tilemap_visualizer:
		return false
	
	var wall_tilemap = tilemap_visualizer.get_wall_tilemap(z_level)
	if wall_tilemap:
		return wall_tilemap.get_cell_source_id(0, tile_coords) != -1
	
	return false

func is_valid_tile(tile_coords: Vector2i, z_level: int) -> bool:
	if not tilemap_visualizer:
		return false
	
	var floor_tilemap = tilemap_visualizer.get_floor_tilemap(z_level)
	if floor_tilemap:
		return floor_tilemap.get_cell_source_id(0, tile_coords) != -1
	
	return false

func get_debug_info() -> Dictionary:
	return {
		"total_entities": entity_z_levels.size(),
		"entities_by_z_level": _get_entity_counts_by_z(),
		"max_z_levels": max_z_levels,
		"systems_connected": {
			"tile_occupancy": tile_occupancy_system != null,
			"tilemap_visualizer": tilemap_visualizer != null,
			"stair_manager": stair_manager != null,
			"z_visual_manager": z_level_visual_manager != null
		}
	}

func _get_entity_counts_by_z() -> Dictionary:
	var counts = {}
	for z in entities_by_z_level.keys():
		counts[z] = entities_by_z_level[z].size()
	return counts

func debug_print_entities():
	print("=== Z-Level Manager Debug ===")
	for z in entities_by_z_level.keys():
		var entities = entities_by_z_level[z]
		print("Z-Level ", z, ": ", entities.size(), " entities")
		for entity in entities:
			if is_instance_valid(entity):
				print("  - ", entity.name)
	print("=============================")

func force_update_visual_system():
	if z_level_visual_manager:
		var players = get_tree().get_nodes_in_group("player_controller")
		if players.size() > 0:
			var player = players[0]
			var player_z = get_entity_z_level(player)
			if player_z >= 0:
				z_level_visual_manager.set_active_z_level(player_z)
