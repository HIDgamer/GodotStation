extends Node2D
class_name DoorCollisionComponent

enum CollisionMode {
	DISABLED,
	TILE_BASED,
	PHYSICS_BASED,
	HYBRID
}

@export var collision_mode: CollisionMode = CollisionMode.TILE_BASED
@export var debug_collision: bool = false

var door: Door
var world = null
var tile_occupancy_system = null
var collision_tiles: Array[Vector2i] = []
var collision_active: bool = false
var last_door_state: Door.DoorState
var is_registered_with_occupancy: bool = false

signal collision_state_changed(active: bool)
signal collision_tiles_updated(tiles: Array[Vector2i])

func _ready():
	door = get_parent() as Door
	if not door:
		push_error("DoorCollisionComponent must be child of Door")
		return
	
	_setup_systems()
	_connect_door_signals()
	call_deferred("_initialize_collision_state")

func _setup_systems():
	world = get_tree().get_first_node_in_group("world")
	
	if world:
		tile_occupancy_system = world.get_node_or_null("TileOccupancySystem")
		if not tile_occupancy_system:
			await get_tree().process_frame
			tile_occupancy_system = world.get_node_or_null("TileOccupancySystem")

func _connect_door_signals():
	if door:
		door.door_state_changed.connect(_on_door_state_changed)
		door.door_opened.connect(_on_door_opened)
		door.door_closed.connect(_on_door_closed)

func _initialize_collision_state():
	if not door:
		return
	
	collision_tiles = door.get_door_tiles()
	last_door_state = door.current_door_state
	
	await get_tree().process_frame
	
	_update_collision_state()

func _on_door_state_changed(door_instance: Door, old_state: Door.DoorState, new_state: Door.DoorState):
	last_door_state = new_state
	call_deferred("_update_collision_state")

func _on_door_opened(door_instance: Door):
	_set_collision_active(false)

func _on_door_closed(door_instance: Door):
	_set_collision_active(true)

func _update_collision_state():
	if not door:
		return
	
	var should_be_active = _should_collision_be_active()
	
	# Update collision tiles first
	_update_collision_tiles()
	
	# Then update active state
	if collision_active != should_be_active:
		_set_collision_active(should_be_active)

func _should_collision_be_active() -> bool:
	match door.current_door_state:
		Door.DoorState.CLOSED:
			return true
		Door.DoorState.CLOSING:
			return true
		Door.DoorState.DENIED:
			return true
		Door.DoorState.MALFUNCTIONING:
			return door.obj_integrity > door.integrity_failure
		Door.DoorState.OPEN:
			return false
		Door.DoorState.OPENING:
			return true
		_:
			return true

func _process(_delta):
	if debug_collision:
		queue_redraw()

func _set_collision_active(active: bool):
	if collision_active == active:
		return
	
	collision_active = active
	
	match collision_mode:
		CollisionMode.TILE_BASED:
			_update_tile_collision(active)
		CollisionMode.PHYSICS_BASED:
			_update_physics_collision(active)
		CollisionMode.HYBRID:
			_update_tile_collision(active)
			_update_physics_collision(active)
	
	if debug_collision:
		print("Door collision ", "ACTIVE" if active else "INACTIVE", " for ", door.machinery_id, " State: ", Door.DoorState.keys()[door.current_door_state])
		print("Collision tiles: ", collision_tiles)
		queue_redraw()
	
	emit_signal("collision_state_changed", active)

func _update_tile_collision(active: bool):
	if not tile_occupancy_system or not door:
		return
	
	door.entity_dense = active
	
	if active:
		_register_multi_tile_collision()
	else:
		_unregister_multi_tile_collision()
	
	_update_world_tile_data(active)

func _register_multi_tile_collision():
	if not tile_occupancy_system or not door or collision_tiles.is_empty():
		return
	
	if is_registered_with_occupancy:
		# Clean up old registration first
		_unregister_multi_tile_collision()
	
	# Register as multi-tile entity
	var success = tile_occupancy_system.register_multi_tile_entity(door, collision_tiles, door.current_z_level)
	
	if success:
		is_registered_with_occupancy = true
		if debug_collision:
			print("Registered multi-tile door collision at tiles: ", collision_tiles, " for door: ", door.machinery_id)
	else:
		if debug_collision:
			print("Failed to register multi-tile door collision for door: ", door.machinery_id)

func _unregister_multi_tile_collision():
	if not tile_occupancy_system or not door or not is_registered_with_occupancy:
		return
	
	if not collision_tiles.is_empty():
		tile_occupancy_system.remove_multi_tile_entity(door, collision_tiles, door.current_z_level)
		if debug_collision:
			print("Unregistered multi-tile door collision from tiles: ", collision_tiles, " for door: ", door.machinery_id)
	
	is_registered_with_occupancy = false

func _update_world_tile_data(active: bool):
	if not world or not world.has_method("update_tile_collision"):
		return
	
	for tile_pos in collision_tiles:
		world.update_tile_collision(tile_pos, door.current_z_level, active, door)

func _update_physics_collision(active: bool):
	var collision_shape = door.get_node_or_null("CollisionShape2D")
	if collision_shape:
		collision_shape.disabled = not active

func _update_collision_tiles():
	var new_tiles = door.get_door_tiles()
	
	if collision_tiles != new_tiles:
		if debug_collision:
			print("Door collision tiles changing from ", collision_tiles, " to ", new_tiles, " for door: ", door.machinery_id)
		
		# Clean up old tiles
		_cleanup_old_collision_tiles()
		
		# Update to new tiles
		collision_tiles = new_tiles
		
		# Apply collision to new tiles if currently active
		if collision_active:
			_register_multi_tile_collision()
		
		emit_signal("collision_tiles_updated", collision_tiles)

func _cleanup_old_collision_tiles():
	if not tile_occupancy_system or not door or collision_tiles.is_empty():
		return
	
	# Unregister the old multi-tile entity
	_unregister_multi_tile_collision()
	
	if debug_collision:
		print("Cleaned up old collision tiles: ", collision_tiles, " for door: ", door.machinery_id)

func force_collision_update():
	if debug_collision:
		print("Force collision update for door: ", door.machinery_id if door else "unknown")
		print("Current tiles: ", collision_tiles)
		print("Door tiles: ", door.get_door_tiles() if door else "no door")
	
	_update_collision_state()

func set_collision_mode(new_mode: CollisionMode):
	if collision_mode == new_mode:
		return
	
	_cleanup_current_collision_mode()
	collision_mode = new_mode
	_update_collision_state()

func _cleanup_current_collision_mode():
	match collision_mode:
		CollisionMode.TILE_BASED:
			_unregister_multi_tile_collision()
		CollisionMode.PHYSICS_BASED:
			_update_physics_collision(false)
		CollisionMode.HYBRID:
			_unregister_multi_tile_collision()
			_update_physics_collision(false)

func is_collision_active() -> bool:
	return collision_active

func get_collision_tiles() -> Array[Vector2i]:
	return collision_tiles.duplicate()

func blocks_tile(tile_pos: Vector2i) -> bool:
	return collision_active and tile_pos in collision_tiles

func can_entity_pass(entity: Node, tile_pos: Vector2i) -> bool:
	if not blocks_tile(tile_pos):
		if door and door.current_door_state == Door.DoorState.CLOSING:
			_cancel_door_closing()
		return true
	
	if not door or not entity:
		return false
	
	if entity == door:
		return true
	
	if door.has_method("_check_access") and door._check_access(entity):
		if door.current_door_state == Door.DoorState.CLOSED:
			call_deferred("_try_auto_open_for_entity", entity)
		return false
	
	return false

func _cancel_door_closing():
	if door and door.has_method("cancel_closing"):
		door.cancel_closing()
		if debug_collision:
			print("Door closing cancelled for ", door.machinery_id)

func has_blocking_entities() -> bool:
	if not tile_occupancy_system or not door:
		return false
	
	var z_level = door.current_z_level
	
	for tile_pos in collision_tiles:
		var entities_at_tile = tile_occupancy_system.get_entities_at(tile_pos, z_level)
		
		for entity in entities_at_tile:
			if entity != door and is_instance_valid(entity):
				if debug_collision:
					print("Blocking entity found: ", entity, " at tile ", tile_pos)
				return true
	
	return false

func can_door_close() -> bool:
	return not has_blocking_entities()

func _try_auto_open_for_entity(entity: Node):
	if door and door.can_be_bumped and door.current_door_state == Door.DoorState.CLOSED:
		door.open_door(entity)

func _draw():
	if not debug_collision:
		return
	
	for tile_pos in collision_tiles:
		var world_pos = _tile_to_world_local(tile_pos)
		var rect = Rect2(world_pos - Vector2(16, 16), Vector2(32, 32))
		
		var color: Color
		match door.current_door_state:
			Door.DoorState.CLOSED:
				color = Color.RED
			Door.DoorState.OPENING:
				color = Color.YELLOW
			Door.DoorState.OPEN:
				color = Color.GREEN
			Door.DoorState.CLOSING:
				color = Color.BLUE
			Door.DoorState.DENIED:
				color = Color.PURPLE
			_:
				color = Color.GRAY
		
		color.a = 0.4 if collision_active else 0.2
		
		draw_rect(rect, color, true)
		draw_rect(rect, color * 1.5, false, 2)
		
		if collision_active:
			var font = ThemeDB.fallback_font
			var state_text = Door.DoorState.keys()[door.current_door_state]
			draw_string(font, world_pos - Vector2(10, -5), state_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.WHITE)
		
		if collision_tiles.size() > 1:
			var font = ThemeDB.fallback_font
			var tile_index = collision_tiles.find(tile_pos)
			draw_string(font, world_pos + Vector2(-15, 15), str(tile_index), HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color.CYAN)

func _tile_to_world_local(tile_pos: Vector2i) -> Vector2:
	var world_pos = Vector2((tile_pos.x * 32) + 16, (tile_pos.y * 32) + 16)
	return to_local(world_pos)

func set_debug_collision(enabled: bool):
	debug_collision = enabled
	set_process(enabled)
	if enabled:
		queue_redraw()

func _exit_tree():
	_cleanup_current_collision_mode()
