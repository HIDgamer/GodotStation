extends Node
class_name ZLevelMovementComponent

signal z_level_changed(old_z: int, new_z: int)
signal stair_movement_completed(old_z: int, new_z: int)

@export_group("Z-Movement Settings")
@export var enable_manual_movement: bool = false
@export var show_movement_messages: bool = true

var controller = null
var world = null
var sensory_system = null
var z_level_manager = null
var stair_manager = null
var tile_occupancy_system = null

var current_z_level: int = 0
var is_moving: bool = false

func initialize(init_data: Dictionary):
	controller = init_data.get("controller")
	world = init_data.get("world")
	sensory_system = init_data.get("sensory_system")
	tile_occupancy_system = init_data.get("tile_occupancy_system")
	current_z_level = controller.current_z_level if controller else 0
	
	_find_z_level_systems()
	_register_with_systems()
	_connect_signals()

func _find_z_level_systems():
	if world:
		z_level_manager = world.get_node_or_null("ZLevelManager")
		stair_manager = world.get_node_or_null("StairManager")
	
	if not z_level_manager:
		z_level_manager = get_tree().get_first_node_in_group("z_level_manager")
	
	if not stair_manager:
		stair_manager = get_tree().get_first_node_in_group("stair_manager")

func _register_with_systems():
	if z_level_manager and controller:
		z_level_manager.register_entity(controller, current_z_level)
	
	if tile_occupancy_system and controller:
		var current_pos = _get_current_tile_position()
		if tile_occupancy_system.has_method("register_entity_at_tile"):
			tile_occupancy_system.register_entity_at_tile(controller, current_pos, current_z_level)

func _connect_signals():
	if stair_manager and stair_manager.has_signal("player_z_level_changed"):
		stair_manager.connect("player_z_level_changed", _on_stair_triggered_z_change)
	
	if z_level_manager and z_level_manager.has_signal("z_level_changed"):
		z_level_manager.connect("z_level_changed", _on_z_level_manager_changed)

func move_up() -> bool:
	if not enable_manual_movement:
		if show_movement_messages:
			_show_message("Use stairs to move between levels!")
		return false
	
	if is_moving:
		return false
	
	var target_z = current_z_level + 1
	return _attempt_manual_move(target_z, "up")

func move_down() -> bool:
	if not enable_manual_movement:
		if show_movement_messages:
			_show_message("Use stairs to move between levels!")
		return false
	
	if is_moving:
		return false
	
	var target_z = current_z_level - 1
	return _attempt_manual_move(target_z, "down")

func _attempt_manual_move(target_z: int, direction: String) -> bool:
	if target_z < 0:
		if show_movement_messages:
			_show_message("Can't go any lower!")
		return false
	
	if not _is_valid_z_level(target_z):
		if show_movement_messages:
			_show_message("Can't go any higher!")
		return false
	
	is_moving = true
	
	if show_movement_messages:
		_show_message("Moving " + direction + " to level " + str(target_z))
	
	var success = _move_to_z_level(target_z)
	is_moving = false
	
	return success

func _move_to_z_level(new_z: int) -> bool:
	if z_level_manager and controller:
		return z_level_manager.move_entity_to_z_level(controller, new_z)
	else:
		_update_local_z_level(new_z)
		return true

func _update_local_z_level(new_z: int):
	var old_z = current_z_level
	current_z_level = new_z
	
	if controller:
		controller.current_z_level = new_z
	
	emit_signal("z_level_changed", old_z, new_z)

func _on_stair_triggered_z_change(new_z: int):
	if new_z != current_z_level and not is_moving:
		is_moving = true
		
		if show_movement_messages:
			var direction = "up" if new_z > current_z_level else "down"
			_show_message("Moving " + direction + " via stairs...")
		
		var old_z = current_z_level
		
		if z_level_manager and controller:
			z_level_manager.move_entity_to_z_level(controller, new_z)
		else:
			_update_local_z_level(new_z)
		
		emit_signal("stair_movement_completed", old_z, new_z)
		is_moving = false

func _on_z_level_manager_changed(entity: Node, old_z: int, new_z: int):
	if entity != controller:
		return
	
	if new_z != current_z_level:
		_update_local_z_level(new_z)

func _is_valid_z_level(z_level: int) -> bool:
	if z_level_manager:
		return z_level >= 0 and z_level < z_level_manager.max_z_levels
	elif world and world.has_method("has_z_level"):
		return world.has_z_level(z_level)
	else:
		return z_level >= 0 and z_level < 10

func _get_current_tile_position() -> Vector2i:
	if controller.has_method("get_current_tile_position"):
		return controller.get_current_tile_position()
	elif "movement_component" in controller and controller.movement_component:
		if "current_tile_position" in controller.movement_component:
			return controller.movement_component.current_tile_position
	
	return Vector2i.ZERO

func _show_message(text: String):
	if not show_movement_messages:
		return
	
	if sensory_system and sensory_system.has_method("display_message"):
		sensory_system.display_message(text)
	else:
		print("ZLevelMovement: ", text)

func get_current_z_level() -> int:
	return current_z_level

func force_z_level(new_z_level: int):
	if z_level_manager and controller:
		z_level_manager.move_entity_to_z_level(controller, new_z_level)
	else:
		_update_local_z_level(new_z_level)

func is_manual_movement_enabled() -> bool:
	return enable_manual_movement

func is_currently_moving() -> bool:
	return is_moving

func can_move_z_level() -> bool:
	return not is_moving

func get_movement_state() -> Dictionary:
	return {
		"current_z_level": current_z_level,
		"is_moving": is_moving,
		"manual_movement_enabled": enable_manual_movement,
		"has_z_level_manager": z_level_manager != null,
		"has_stair_manager": stair_manager != null
	}

func debug_print_state():
	var state = get_movement_state()
	print("=== ZLevelMovementComponent State ===")
	for key in state.keys():
		print(key, ": ", state[key])
	print("====================================")

func _exit_tree():
	if z_level_manager and controller:
		z_level_manager.unregister_entity(controller)
