extends GrabPullComponent
class_name AlienGrabPullComponent

const CARRY_SPEED_PENALTY: float = 0.7
const CARRY_STAMINA_DRAIN: float = 2.0
const CARRY_SIZE_LIMIT: float = 1.2

enum AlienCarryState {
	NOT_CARRYING,
	CARRYING_ON_BACK,
	DRAGGING
}

var alien_carry_state: int = AlienCarryState.NOT_CARRYING
var carried_entity: Node = null
var carry_position_offset: Vector2 = Vector2(0, -8)

signal alien_carry_started(entity: Node)
signal alien_carry_stopped(entity: Node)

func initialize(init_data: Dictionary):
	super.initialize(init_data)

func handle_grab_prey():
	if not is_multiplayer_authority():
		return
	
	var nearest_target = find_nearest_grabbable_target()
	if not nearest_target:
		print("No grabbable target found")
		return
	
	if alien_carry_state != AlienCarryState.NOT_CARRYING:
		print("Already carrying something")
		return
	
	if grabbing_entity and grabbing_entity == nearest_target:
		print("Already grabbing this target")
		return
	
	print("Attempting to grab: ", nearest_target.name)
	attempt_alien_grab(nearest_target)

func handle_carry_prey():
	if not is_multiplayer_authority():
		return
	
	if grabbing_entity and can_carry_entity(grabbing_entity):
		print("Starting to carry grabbed entity: ", grabbing_entity.name)
		start_alien_carry(grabbing_entity)

func find_nearest_grabbable_target() -> Node:
	if not tile_occupancy_system:
		return null
	
	var my_pos = controller.movement_component.current_tile_position
	var search_radius = 2
	var nearest_target = null
	var nearest_distance = 999.0
	
	for x in range(my_pos.x - search_radius, my_pos.x + search_radius + 1):
		for y in range(my_pos.y - search_radius, my_pos.y + search_radius + 1):
			var tile_pos = Vector2i(x, y)
			var entities = tile_occupancy_system.get_entities_at(tile_pos, controller.current_z_level)
			
			for entity in entities:
				if can_alien_grab(entity):
					var distance = my_pos.distance_to(Vector2(tile_pos))
					if distance < nearest_distance:
						nearest_distance = distance
						nearest_target = entity
	
	return nearest_target

func can_alien_grab(target: Node) -> bool:
	if not target or target == controller:
		return false
	
	if not is_living_entity(target):
		return false
	
	if not can_carry_entity(target):
		return false
	
	if not _is_adjacent_to(target):
		return false
	
	return true

func is_living_entity(entity: Node) -> bool:
	# Check if entity is in valid groups
	if not (entity.is_in_group("players") or entity.is_in_group("humans")):
		return false
	
	if entity.has_node("HealthSystem"):
		var health_sys = entity.get_node("HealthSystem")
		return health_sys.current_state != health_sys.HealthState.DEAD
	
	if "entity_type" in entity:
		return entity.entity_type in ["character", "mob", "human"]
	
	return true

func can_carry_entity(target: Node) -> bool:
	if not target:
		return false
	
	if "mass" in target and "mass" in controller:
		var mass_ratio = target.mass / controller.mass
		if mass_ratio > CARRY_SIZE_LIMIT:
			return false
	
	if "w_class" in target and target.w_class > 4:
		return false
	
	return true

func attempt_alien_grab(target: Node) -> bool:
	if not can_alien_grab(target):
		print("Cannot grab target: ", target.name)
		return false
	
	var grab_success_chance = calculate_alien_grab_chance(target)
	print("Grab chance: ", grab_success_chance, "%")
	
	if randf() * 100.0 < grab_success_chance:
		print("Grab successful!")
		execute_alien_grab(target)
		return true
	else:
		print("Grab failed!")
		return false

func calculate_alien_grab_chance(target: Node) -> float:
	var base_chance = 75.0
	
	if "is_unconscious" in target and target.is_unconscious:
		base_chance += 20.0
	elif "is_stunned" in target and target.is_stunned:
		base_chance += 15.0
	elif "is_lying" in target and target.is_lying:
		base_chance += 10.0
	
	if target.has_node("HealthSystem"):
		var health_sys = target.get_node("HealthSystem")
		var health_percent = health_sys.health / health_sys.max_health
		if health_percent < 0.5:
			base_chance += (0.5 - health_percent) * 30.0
	
	if "mass" in target and "mass" in controller:
		var mass_ratio = controller.mass / target.mass
		if mass_ratio > 1.5:
			base_chance += 15.0
		elif mass_ratio < 0.8:
			base_chance -= 10.0
	
	return clamp(base_chance, 20.0, 95.0)

func execute_alien_grab(target: Node):
	print("Executing grab on: ", target.name)
	
	# Use the base grab functionality first
	if grab_entity(target, GrabPullComponent.GrabState.PASSIVE):
		print("Base grab successful")
		
		# Immediately start alien carrying
		if start_alien_carry(target):
			print("Alien carry started successfully")
		else:
			print("Failed to start alien carry")
		
		if audio_system:
			audio_system.play_positioned_sound("alien_grab", controller.position, 0.6)
		
		if target.has_method("add_status_effect") and not ("is_unconscious" in target and target.is_unconscious):
			target.add_status_effect("terrified", 10.0, 2.0)
	else:
		print("Base grab failed")

func start_alien_carry(target: Node) -> bool:
	if alien_carry_state != AlienCarryState.NOT_CARRYING:
		print("Already in carrying state: ", alien_carry_state)
		return false
	
	if not can_carry_entity(target):
		print("Cannot carry entity: ", target.name)
		return false
	
	print("Starting alien carry for: ", target.name)
	alien_carry_state = AlienCarryState.CARRYING_ON_BACK
	carried_entity = target
	
	position_carried_entity()
	
	if controller.movement_component:
		controller.movement_component.set_movement_modifier(CARRY_SPEED_PENALTY)
	
	target.set_meta("being_carried_by_alien", true)
	controller.set_meta("carrying_prey", true)
	
	if audio_system:
		audio_system.play_positioned_sound("alien_carry", controller.position, 0.5)
	
	sync_alien_carry_start.rpc(_get_entity_network_id(target))
	emit_signal("alien_carry_started", target)
	
	print("Alien carry state set to: ", alien_carry_state)
	return true

func stop_alien_carry():
	if alien_carry_state == AlienCarryState.NOT_CARRYING or not carried_entity:
		return
	
	print("Stopping alien carry for: ", carried_entity.name)
	var target = carried_entity
	
	if controller.movement_component:
		controller.movement_component.set_movement_modifier(1.0)
	
	target.set_meta("being_carried_by_alien", false)
	controller.set_meta("carrying_prey", false)
	
	release_carried_entity()
	
	alien_carry_state = AlienCarryState.NOT_CARRYING
	carried_entity = null
	
	sync_alien_carry_stop.rpc()
	emit_signal("alien_carry_stopped", target)

func position_carried_entity():
	if not carried_entity or not controller:
		return
	
	var my_pos = controller.movement_component.current_tile_position
	
	if carried_entity.has_method("move_externally"):
		carried_entity.move_externally(my_pos, false, true)
	
	carried_entity.position = controller.position + carry_position_offset
	
	if "z_index" in carried_entity:
		carried_entity.z_index = controller.z_index + 1

func release_carried_entity():
	if not carried_entity:
		return
	
	print("Releasing carried entity: ", carried_entity.name)
	var drop_position = find_drop_position()
	
	if carried_entity:
		carried_entity.register_with_tile_system()
	
	if "z_index" in carried_entity:
		carried_entity.z_index = 0

func find_drop_position() -> Vector2i:
	var my_pos = controller.movement_component.current_tile_position
	# Only use cardinal directions - no diagonals
	var offsets = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	
	for offset in offsets:
		var test_pos = my_pos + offset
		if is_valid_drop_position(test_pos):
			return test_pos
	
	return my_pos

func is_valid_drop_position(pos: Vector2i) -> bool:
	if not world:
		return false
	
	var z_level = controller.current_z_level
	
	if world.has_method("is_valid_tile") and not world.is_valid_tile(pos, z_level):
		return false
	
	if world.has_method("is_wall_at") and world.is_wall_at(pos, z_level):
		return false
	
	if tile_occupancy_system and tile_occupancy_system.has_method("has_dense_entity_at"):
		return not tile_occupancy_system.has_dense_entity_at(pos, z_level)
	
	return true

func start_synchronized_follow(grabber_previous_position: Vector2i, grabber_move_time: float):
	if alien_carry_state == AlienCarryState.CARRYING_ON_BACK and carried_entity:
		sync_carried_entity_movement(grabber_previous_position, grabber_move_time)
	else:
		super.start_synchronized_follow(grabber_previous_position, grabber_move_time)

func sync_carried_entity_movement(grabber_previous_position: Vector2i, grabber_move_time: float):
	if not carried_entity or not is_instance_valid(carried_entity):
		return
	
	var carried_controller = _get_entity_controller(carried_entity)
	if not carried_controller or not carried_controller.movement_component:
		return
	
	var my_current_pos = controller.movement_component.current_tile_position
	var movement_comp = carried_controller.movement_component
	
	if movement_comp.is_moving:
		movement_comp.complete_movement()
	
	movement_comp.current_tile_position = my_current_pos
	carried_entity.position = controller.position + carry_position_offset
	
	var target_id = _get_entity_network_id(carried_entity)
	if target_id != "":
		sync_carried_entity_position.rpc(target_id, my_current_pos, carried_entity.position)

func process_alien_carry_effects(delta: float):
	if alien_carry_state == AlienCarryState.NOT_CARRYING:
		return
	
	if controller.has_method("adjustStaminaLoss"):
		controller.adjustStaminaLoss(CARRY_STAMINA_DRAIN * delta)
	
	if carried_entity and controller:
		position_carried_entity()
	
	if should_drop_carried_entity():
		stop_alien_carry()

func should_drop_carried_entity() -> bool:
	if not carried_entity or not is_instance_valid(carried_entity):
		return true
	
	if controller.has_method("is_stunned") and controller.is_stunned():
		return true
	
	if controller.has_node("HealthSystem"):
		var health_sys = controller.get_node("HealthSystem")
		if health_sys.current_state == health_sys.HealthState.CRITICAL:
			return true
	
	return false

func _process(delta: float):
	if is_multiplayer_authority() and alien_carry_state != AlienCarryState.NOT_CARRYING:
		process_alien_carry_effects(delta)

func release_grab() -> bool:
	print("Release grab called")
	if alien_carry_state != AlienCarryState.NOT_CARRYING:
		stop_alien_carry()
	
	return super.release_grab()

func is_grabbing() -> bool:
	var base_grabbing = grabbing_entity != null
	var alien_carrying = alien_carry_state != AlienCarryState.NOT_CARRYING
	var result = base_grabbing or alien_carrying
	
	# Debug output
	if result:
		print("is_grabbing: true - base_grabbing: ", base_grabbing, ", alien_carrying: ", alien_carrying, ", carry_state: ", alien_carry_state)
	
	return result

# Additional method for AI to check carry state specifically
func get_alien_carry_state() -> int:
	return alien_carry_state

func is_carrying() -> bool:
	return alien_carry_state != AlienCarryState.NOT_CARRYING

@rpc("any_peer", "call_local", "reliable")
func sync_alien_carry_start(target_network_id: String):
	if is_multiplayer_authority():
		return
	
	var target = _find_entity_by_network_id(target_network_id)
	if target:
		alien_carry_state = AlienCarryState.CARRYING_ON_BACK
		carried_entity = target
		position_carried_entity()
		emit_signal("alien_carry_started", target)

@rpc("any_peer", "call_local", "reliable")
func sync_alien_carry_stop():
	if is_multiplayer_authority():
		return
	
	if carried_entity:
		emit_signal("alien_carry_stopped", carried_entity)
	
	alien_carry_state = AlienCarryState.NOT_CARRYING
	carried_entity = null

@rpc("any_peer", "call_local", "reliable")
func sync_carried_entity_position(target_network_id: String, tile_pos: Vector2i, world_pos: Vector2):
	if is_multiplayer_authority():
		return
	
	var target = _find_entity_by_network_id(target_network_id)
	if target:
		var target_controller = _get_entity_controller(target)
		if target_controller and target_controller.movement_component:
			target_controller.movement_component.current_tile_position = tile_pos
		target.position = world_pos
