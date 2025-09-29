extends Node
class_name MovementComponent

@export_group("Movement Settings")
@export var tile_size: int = 32
@export var base_move_time: float = 0.3
@export var running_move_time: float = 0.2
@export var crawling_move_time: float = 0.35
@export var min_move_interval: float = 0.01
@export var allow_diagonal: bool = false

@export_group("Input Settings")
@export var input_buffer_time: float = 0.2
@export var auto_sprint: bool = false

@export_group("Physics Settings")
@export var drift_speed: float = 8.0
@export var spin_speed: float = 0.3
@export var drift_friction: float = 0.98
@export var min_drift_speed: float = 0.1

@export_group("Knockback Settings")
@export var knockback_gravity: float = 980.0
@export var knockback_air_resistance: float = 0.99
@export var knockback_spin_multiplier: float = 2.0
@export var knockback_min_force: float = 50.0
@export var knockback_landing_threshold: float = 20.0

@export_group("Stamina Settings")
@export var max_stamina: float = 100.0
@export var stamina_drain_rate: float = 3.33
@export var stamina_regen_rate: float = 5.0
@export var sprint_recovery_threshold: float = 25.0

@export_group("Speed Modifiers")
@export var drag_slowdown_modifier: float = 0.6
@export var pull_speed_modifier: float = 0.7
@export var crawl_speed_multiplier: float = 0.5

@export_group("Network Settings")
@export var sync_interval: float = 0.1
@export var network_interpolation_enabled: bool = true

enum MovementState {
	IDLE, MOVING, RUNNING, STUNNED, CRAWLING, DRIFTING, FLYING
}

enum Direction {
	NONE = -1, NORTH = 0, EAST = 1, SOUTH = 2, WEST = 3,
	NORTHEAST = 4, SOUTHEAST = 5, SOUTHWEST = 6, NORTHWEST = 7
}

enum CollisionType {
	NONE, WALL, ENTITY, DENSE_OBJECT, DOOR
}

signal direction_changed(new_direction: int)
signal tile_changed(old_tile: Vector2i, new_tile: Vector2i)
signal state_changed(old_state: int, new_state: int)
signal entity_moved(old_tile: Vector2i, new_tile: Vector2i, entity: Node)
signal began_drifting()
signal stopped_drifting()
signal began_flying()
signal landed()
signal footstep(position: Vector2, floor_type: String)
signal bump(entity: Node, bumped_entity: Node, direction: Vector2i)
signal pushing_entity(pushed_entity: Node, direction: Vector2i)
signal movement_attempt(direction: Vector2i)

var controller: Node = null
var world = null
var tile_occupancy_system = null
var sensory_system = null
var audio_system = null
var sprite_system = null

@export var current_state: int = MovementState.IDLE : set = _set_current_state
@export var current_direction: int = Direction.SOUTH : set = _set_current_direction
@export var current_tile_position: Vector2i = Vector2i.ZERO : set = _set_current_tile_position
@export var target_tile_position: Vector2i = Vector2i.ZERO : set = _set_target_tile_position
@export var move_progress: float = 0.0 : set = _set_move_progress
@export var is_moving: bool = false : set = _set_is_moving
@export var is_drifting: bool = false : set = _set_is_drifting
@export var is_flying: bool = false : set = _set_is_flying

@export var physics_velocity: Vector2 = Vector2.ZERO : set = _set_physics_velocity
@export var physics_position: Vector2 = Vector2.ZERO : set = _set_physics_position
@export var angular_velocity: float = 0.0 : set = _set_angular_velocity
@export var current_rotation: float = 0.0 : set = _set_current_rotation

var previous_tile_position: Vector2i = Vector2i.ZERO
var current_move_time: float = 0.0
var next_move_time: float = 0.0
var is_local_player: bool = false
var is_sprinting: bool = false
var is_lying: bool = false
var is_stunned: bool = false
var is_dragging_entity: bool = false

var movement_speed_modifier: float = 1.0
var current_tile_friction: float = 1.0
var current_stamina: float = 100.0
var sprint_allowed: bool = true

var input_buffer_timer: float = 0.0
var buffered_movement: Vector2i = Vector2i.ZERO
var last_input_direction: Vector2 = Vector2.ZERO

var drift_direction: Vector2 = Vector2.ZERO
var last_movement_direction: Vector2 = Vector2.ZERO
var spin_rotation: float = 0.0

var flight_start_position: Vector2 = Vector2.ZERO
var flight_target_position: Vector2 = Vector2.ZERO
var flight_duration: float = 0.0
var flight_elapsed: float = 0.0
var landing_forced_lying: bool = false

var stun_remaining: float = 0.0
var confusion_level: float = 0.0

var peer_id: int = 1
var network_position: Vector2 = Vector2.ZERO
var sync_timer: float = 0.0

var grab_component: Node = null
var posture_component: Node = null

var collision_cache: Dictionary = {}
var collision_cache_timer: float = 0.0
var collision_cache_lifetime: float = 0.5

func _ready():
	current_stamina = max_stamina

func initialize(init_data: Dictionary):
	controller = init_data.get("controller")
	world = init_data.get("world")
	tile_occupancy_system = init_data.get("tile_occupancy_system")
	sensory_system = init_data.get("sensory_system")
	audio_system = init_data.get("audio_system")
	sprite_system = init_data.get("sprite_system")
	is_local_player = init_data.get("is_local_player", false)
	peer_id = init_data.get("peer_id", 1)
	
	_cache_component_references()
	_initialize_position()

func _cache_component_references():
	if not controller:
		return
	
	grab_component = controller.get_node_or_null("GrabPullComponent")
	if not grab_component:
		grab_component = controller.get_node_or_null("AlienGrabPullComponent")
	
	posture_component = controller.get_node_or_null("PostureComponent")
	if not posture_component:
		posture_component = controller.get_node_or_null("AlienPostureComponent")

func _initialize_position():
	if controller:
		current_tile_position = world_to_tile(controller.position)
		previous_tile_position = current_tile_position
		target_tile_position = current_tile_position
		network_position = controller.position
		physics_position = controller.position

func _set_current_state(value: int):
	var old_state = current_state
	current_state = value
	if old_state != current_state:
		emit_signal("state_changed", old_state, current_state)

func _set_current_direction(value: int):
	current_direction = value
	_update_sprite_direction(current_direction)
	emit_signal("direction_changed", current_direction)

func _set_current_tile_position(value: Vector2i):
	var old_pos = current_tile_position
	current_tile_position = value
	if old_pos != current_tile_position:
		emit_signal("tile_changed", old_pos, current_tile_position)

func _set_target_tile_position(value: Vector2i):
	target_tile_position = value

func _set_move_progress(value: float):
	move_progress = value

func _set_is_moving(value: bool):
	is_moving = value

func _set_is_drifting(value: bool):
	var old_drifting = is_drifting
	is_drifting = value
	if old_drifting != is_drifting:
		if is_drifting:
			emit_signal("began_drifting")
		else:
			emit_signal("stopped_drifting")

func _set_is_flying(value: bool):
	var old_flying = is_flying
	is_flying = value
	if old_flying != is_flying:
		if is_flying:
			emit_signal("began_flying")
		else:
			emit_signal("landed")

func _set_physics_velocity(value: Vector2):
	physics_velocity = value

func _set_physics_position(value: Vector2):
	physics_position = value

func _set_angular_velocity(value: float):
	angular_velocity = value

func _set_current_rotation(value: float):
	current_rotation = value
	if sprite_system and sprite_system.has_method("_set_rotation"):
		sprite_system._set_rotation(current_rotation)

func _physics_process(delta: float):
	sync_timer += delta
	collision_cache_timer += delta
	
	if collision_cache_timer >= collision_cache_lifetime:
		_clear_collision_cache()
		collision_cache_timer = 0.0
	
	if is_multiplayer_authority():
		_process_authority_movement(delta)
		_process_stamina(delta)
		_handle_network_sync(delta)
	else:
		_process_client_movement(delta)

func _process_authority_movement(delta: float):
	if is_stunned:
		_process_stun(delta)
		return
	
	if is_flying:
		_process_physics_flight(delta)
	elif is_drifting:
		_process_enhanced_drift_movement(delta)
	else:
		_process_grid_movement(delta)

func _process_client_movement(delta: float):
	if network_interpolation_enabled and controller:
		_interpolate_to_network_position(delta)

func _handle_network_sync(delta: float):
	if controller and (controller.position.distance_to(network_position) > 1.0 or sync_timer >= sync_interval):
		sync_position.rpc(controller.position, current_tile_position, is_moving, move_progress)
		network_position = controller.position
		sync_timer = 0.0

func _process_grid_movement(delta: float):
	if not is_moving:
		_process_input_buffer(delta)
		return
	
	var progress_delta = delta / current_move_time
	move_progress += progress_delta
	
	if move_progress >= 1.0:
		_complete_movement()
	else:
		_interpolate_movement_position()

func _process_input_buffer(delta: float):
	if is_multiplayer_authority() and buffered_movement != Vector2i.ZERO and input_buffer_timer > 0:
		input_buffer_timer -= delta
		if input_buffer_timer <= 0:
			attempt_move(buffered_movement)
			buffered_movement = Vector2i.ZERO

func _interpolate_movement_position():
	var start_pos = tile_to_world(current_tile_position)
	var end_pos = tile_to_world(target_tile_position)
	var eased_progress = _ease_movement_progress(move_progress)
	
	if controller:
		controller.position = start_pos.lerp(end_pos, eased_progress)

func handle_move_input(direction: Vector2):
	if not is_local_player or not is_multiplayer_authority():
		return
	
	last_input_direction = direction
	var normalized_dir = _get_normalized_input_direction(direction)
	
	if normalized_dir == Vector2i.ZERO:
		return
	
	if normalized_dir != Vector2i.ZERO:
		last_movement_direction = Vector2(normalized_dir.x, normalized_dir.y).normalized()
	
	emit_signal("movement_attempt", normalized_dir)
	
	if is_moving:
		if move_progress >= 0.7:
			buffered_movement = normalized_dir
			input_buffer_timer = input_buffer_time
	else:
		attempt_move(normalized_dir)

func attempt_move(direction: Vector2i) -> bool:
	if not is_multiplayer_authority() or is_stunned or is_moving or is_flying:
		return false
	
	var current_time = Time.get_ticks_msec() * 0.001
	if current_time < next_move_time:
		buffered_movement = direction
		input_buffer_timer = input_buffer_time
		return false
	
	_update_facing_from_movement(direction)
	var target_tile = current_tile_position + direction
	var collision = _check_collision(target_tile)
	
	if collision == CollisionType.NONE:
		_start_move_to(target_tile)
		return true
	else:
		_handle_collision(collision, target_tile, direction)
		return false

func _start_move_to(target: Vector2i):
	is_moving = true
	move_progress = 0.0
	target_tile_position = target
	
	next_move_time = Time.get_ticks_msec() * 0.001 + min_move_interval
	_calculate_move_time()
	
	if tile_occupancy_system:
		tile_occupancy_system.move_entity(controller, current_tile_position, target_tile_position, controller.current_z_level)
	
	_handle_grabbed_entity_movement()
	_set_movement_state()
	
	if is_multiplayer_authority():
		sync_movement_start.rpc(current_tile_position, target_tile_position, current_direction, current_move_time, current_state)

func _handle_grabbed_entity_movement():
	var grab_comp = get_grab_component()
	if grab_comp and grab_comp.has_method("grabbing_entity") and grab_comp.grabbing_entity:
		if grab_comp.has_method("start_synchronized_follow"):
			grab_comp.start_synchronized_follow(current_tile_position, current_move_time)

func _set_movement_state():
	if is_sprinting and not is_lying:
		set_state(MovementState.RUNNING)
	elif is_lying:
		set_state(MovementState.CRAWLING)
	else:
		set_state(MovementState.MOVING)

func _complete_movement():
	if not is_moving:
		return
	
	move_progress = 1.0
	is_moving = false
	
	if controller:
		controller.position = tile_to_world(target_tile_position)
	
	previous_tile_position = current_tile_position
	current_tile_position = target_tile_position
	
	if is_multiplayer_authority():
		emit_signal("tile_changed", previous_tile_position, current_tile_position)
		emit_signal("entity_moved", previous_tile_position, current_tile_position, controller)
		sync_tile_change.rpc(previous_tile_position, current_tile_position)
		sync_movement_complete.rpc(current_tile_position, controller.position)
	
	check_tile_environment()
	
	if is_multiplayer_authority() and not is_drifting:
		var floor_type = _get_floor_type(current_tile_position)
		sync_footstep.rpc(controller.position, floor_type)
	
	_finalize_movement_state()
	_process_buffered_input()

func _finalize_movement_state():
	if is_lying:
		set_state(MovementState.CRAWLING)
	else:
		set_state(MovementState.IDLE)

func _process_buffered_input():
	if is_multiplayer_authority() and buffered_movement != Vector2i.ZERO and input_buffer_timer > input_buffer_time * 0.5:
		var next_dir = buffered_movement
		buffered_movement = Vector2i.ZERO
		input_buffer_timer = 0
		await controller.get_tree().create_timer(0.05).timeout
		attempt_move(next_dir)

func move_externally(target_position: Vector2i, animated: bool = true, force: bool = false) -> bool:
	if is_moving and not force:
		return false
	
	if not _is_valid_tile(target_position):
		return false
	
	var direction = target_position - current_tile_position
	if direction == Vector2i.ZERO:
		return true
	
	if animated:
		_update_facing_from_movement(direction)
		_start_external_move_to(target_position)
		return true
	else:
		return _perform_instant_move(target_position)

func _start_external_move_to(target: Vector2i):
	is_moving = true
	move_progress = 0.0
	target_tile_position = target
	current_move_time = base_move_time * 0.7
	
	if tile_occupancy_system:
		tile_occupancy_system.move_entity(controller, current_tile_position, target_tile_position, controller.current_z_level)
	
	if is_lying:
		set_state(MovementState.CRAWLING)
	else:
		set_state(MovementState.MOVING)
	
	if is_multiplayer_authority():
		sync_external_movement.rpc(current_tile_position, target_tile_position, current_move_time, true)

func _perform_instant_move(target_position: Vector2i) -> bool:
	var old_pos = current_tile_position
	
	if tile_occupancy_system and tile_occupancy_system.has_method("move_entity"):
		if not tile_occupancy_system.move_entity(controller, old_pos, target_position, controller.current_z_level):
			return false
	
	current_tile_position = target_position
	previous_tile_position = old_pos
	if controller:
		controller.position = tile_to_world(target_position)
	
	var direction = target_position - old_pos
	if direction != Vector2i.ZERO:
		_update_facing_from_movement(direction)
	
	if is_multiplayer_authority():
		emit_signal("tile_changed", old_pos, target_position)
		emit_signal("entity_moved", old_pos, target_position, controller)
		sync_tile_change.rpc(old_pos, target_position)
		sync_position.rpc(controller.position, current_tile_position, false, 0.0)
		network_position = controller.position
	
	return true

func _check_collision(target_tile: Vector2i) -> int:
	var cache_key = str(target_tile.x) + "_" + str(target_tile.y)
	
	if collision_cache.has(cache_key):
		return collision_cache[cache_key]
	
	var z_level = controller.current_z_level if controller else 0
	var collision_result = CollisionType.NONE
	
	if _is_wall_at(target_tile, z_level):
		collision_result = CollisionType.WALL
	elif _check_door_collision(target_tile, z_level) != CollisionType.NONE:
		collision_result = _check_door_collision(target_tile, z_level)
	elif _check_entity_collision(target_tile, z_level):
		collision_result = CollisionType.ENTITY
	
	collision_cache[cache_key] = collision_result
	return collision_result

func _check_entity_collision(target_tile: Vector2i, z_level: int) -> bool:
	if tile_occupancy_system:
		if tile_occupancy_system.has_dense_entity_at(target_tile, z_level, controller):
			var entity = tile_occupancy_system.get_entity_at(target_tile, z_level)
			var grab_comp = get_grab_component()
			if grab_comp and grab_comp.has_method("is_entity_grabbed_by_me"):
				if grab_comp.is_entity_grabbed_by_me(entity):
					return false
			return true
	return false

func _check_door_collision(target_tile: Vector2i, z_level: int) -> int:
	if not tile_occupancy_system:
		return CollisionType.NONE
	
	var door_entity = tile_occupancy_system.get_entity_at(target_tile, z_level, "door")
	if not door_entity or not is_instance_valid(door_entity):
		return CollisionType.NONE
	
	if not door_entity.has_method("blocks_movement"):
		return CollisionType.NONE
	
	var door_blocks = door_entity.blocks_movement()
	if not door_blocks:
		return CollisionType.NONE
	
	set_meta("last_blocking_door", door_entity)
	
	if door_entity.has_method("_check_access") and door_entity._check_access(controller):
		call_deferred("_try_auto_open_door", door_entity)
		return CollisionType.NONE
	
	return CollisionType.DOOR

func _handle_collision(collision_type: int, target_tile: Vector2i, direction: Vector2i):
	if is_multiplayer_authority():
		sync_collision_event.rpc(collision_type, target_tile, direction)
	
	_handle_collision_effects(collision_type, target_tile, direction)

func _handle_collision_effects(collision_type: int, target_tile: Vector2i, direction: Vector2i):
	match collision_type:
		CollisionType.ENTITY:
			if is_multiplayer_authority():
				_handle_entity_collision(target_tile, direction)
		CollisionType.WALL:
			if audio_system:
				audio_system.play_positioned_sound("bump", controller.position, 0.3)
		CollisionType.DOOR:
			_handle_door_collision_effects(target_tile, direction)

func _handle_door_collision_effects(target_tile: Vector2i, direction: Vector2i):
	var blocking_door = get_meta("last_blocking_door", null)
	
	if not blocking_door or not is_instance_valid(blocking_door):
		return
	
	if blocking_door.has_method("on_bump"):
		var bump_result = blocking_door.on_bump(controller, direction)
		if not bump_result:
			return
	
	if audio_system:
		if blocking_door.has_method("_check_access") and blocking_door._check_access(controller):
			audio_system.play_positioned_sound("door_try", controller.position, 0.3)
		else:
			audio_system.play_positioned_sound("door_deny", controller.position, 0.4)
	
	if blocking_door.has_method("_check_access") and not blocking_door._check_access(controller):
		if sensory_system:
			sensory_system.display_message("Access denied.")

func _handle_entity_collision(target_tile: Vector2i, direction: Vector2i):
	if not is_multiplayer_authority() or not tile_occupancy_system:
		return
	
	var entity = tile_occupancy_system.get_entity_at(target_tile, controller.current_z_level)
	if not entity:
		return
	
	var intent = _get_controller_intent()
	var pusher_name = _get_entity_name(controller)
	
	if entity.has_method("on_bump"):
		var bump_blocked = entity.on_bump(controller, direction)
		emit_signal("bump", controller, entity, direction)
		
		if not bump_blocked:
			return
	
	match intent:
		0:
			var swap_result = _handle_position_swap(entity, target_tile)
			var interaction_type = 0 if swap_result else 2
			sync_entity_interaction.rpc(interaction_type, target_tile, direction, pusher_name)
		1, 2, 3:
			var push_result = _handle_entity_push(entity, direction, target_tile)
			var interaction_type = 1 if push_result else 2
			sync_entity_interaction.rpc(interaction_type, target_tile, direction, pusher_name)

func _handle_position_swap(other_entity: Node, target_tile: Vector2i) -> bool:
	var other_pos = _get_entity_tile_position(other_entity)
	var my_pos = current_tile_position
	
	var other_moved = false
	if other_entity.has_method("move_externally"):
		other_moved = other_entity.move_externally(my_pos)
	
	if other_moved:
		_start_move_to(target_tile)
		
		if sensory_system:
			var name = other_entity.entity_name if "entity_name" in other_entity else other_entity.name
			sensory_system.display_message("You swap places with " + name + ".")
		
		return true
	
	return false

func _handle_entity_push(entity: Node, direction: Vector2i, target_tile: Vector2i) -> bool:
	var push_target = target_tile + direction
	var push_collision = _check_collision(push_target)
	
	if push_collision == CollisionType.NONE:
		var push_success = false
		if entity and entity.has_method("move_externally"):
			push_success = entity.move_externally(push_target, true, true)
		
		if push_success:
			_start_move_to(target_tile)
			emit_signal("pushing_entity", entity, direction)
			
			if sensory_system:
				var name = entity.entity_name if "entity_name" in entity else entity.name
				sensory_system.display_message("You push " + name + "!")
			
			return true
	
	emit_signal("bump", controller, entity, direction)
	return false

func _clear_collision_cache():
	collision_cache.clear()

func _process_enhanced_drift_movement(delta: float):
	if not controller:
		return
	
	if drift_direction.length() > min_drift_speed:
		var drift_force = drift_direction * drift_speed * delta * tile_size
		controller.position += drift_force
		
		drift_direction *= drift_friction
		
		if drift_direction.length() < min_drift_speed:
			drift_direction = Vector2.ZERO
		
		if is_multiplayer_authority():
			var new_tile_pos = world_to_tile(controller.position)
			if new_tile_pos != current_tile_position:
				_handle_drift_tile_change(new_tile_pos)
	
	if is_multiplayer_authority():
		spin_rotation += spin_speed * delta
		if spin_rotation > 2 * PI:
			spin_rotation -= 2 * PI
		
		current_rotation = spin_rotation
		
		if randf() < 0.05:
			sync_drift_state.rpc(is_drifting, drift_direction, spin_rotation)

func start_drifting():
	if not is_multiplayer_authority():
		return
	
	if last_movement_direction.length() > 0.1:
		drift_direction = last_movement_direction.normalized() * 1.5
	else:
		var angle = randf() * 2 * PI
		drift_direction = Vector2(cos(angle), sin(angle)) * 0.8
	
	if is_moving:
		is_moving = false
		move_progress = 0.0
		if controller:
			controller.position = tile_to_world(current_tile_position)
	
	is_drifting = true
	set_state(MovementState.DRIFTING)
	spin_rotation = 0.0
	
	sync_drift_state.rpc(is_drifting, drift_direction, spin_rotation)
	emit_signal("began_drifting")

func stop_drifting():
	if not is_multiplayer_authority():
		return
	
	is_drifting = false
	drift_direction = Vector2.ZERO
	spin_rotation = 0.0
	current_rotation = 0.0
	
	if sprite_system:
		if sprite_system.has_method("clear_rotation"):
			sprite_system.clear_rotation()
		else:
			sprite_system._set_rotation(0.0)
	
	set_state(MovementState.IDLE)
	sync_drift_state.rpc(is_drifting, drift_direction, spin_rotation)
	emit_signal("stopped_drifting")

func _handle_drift_tile_change(new_tile_pos: Vector2i):
	if not is_multiplayer_authority():
		return
	
	var z_level = controller.current_z_level if controller else 0
	
	if _is_valid_tile(new_tile_pos) and can_entity_move_to(controller, new_tile_pos, z_level):
		var old_tile_pos = current_tile_position
		previous_tile_position = current_tile_position
		current_tile_position = new_tile_pos
		
		if tile_occupancy_system and tile_occupancy_system.has_method("move_entity"):
			tile_occupancy_system.move_entity(controller, old_tile_pos, new_tile_pos, z_level)
		
		emit_signal("tile_changed", old_tile_pos, new_tile_pos)
		emit_signal("entity_moved", old_tile_pos, new_tile_pos, controller)
		sync_tile_change.rpc(old_tile_pos, new_tile_pos)
		
		check_tile_environment()
	else:
		drift_direction = -drift_direction * 0.3
		
		var door = _get_door_at_tile(new_tile_pos, z_level)
		if door and door.has_method("_check_access") and door._check_access(controller):
			call_deferred("_try_auto_open_door", door)
		
		sync_drift_state.rpc(is_drifting, drift_direction, spin_rotation)

func _process_physics_flight(delta: float):
	if not controller or not is_flying:
		return
	
	flight_elapsed += delta
	
	var progress = flight_elapsed / flight_duration
	if progress >= 1.0:
		_complete_physics_flight()
		return
	
	var horizontal_progress = progress
	var horizontal_pos = flight_start_position.lerp(flight_target_position, horizontal_progress)
	var arc_height = 60.0 * sin(progress * PI)
	var current_pos = horizontal_pos + Vector2(0, -arc_height)
	
	controller.position = current_pos
	physics_position = current_pos
	
	angular_velocity *= knockback_air_resistance
	current_rotation += angular_velocity * delta
	
	var current_tile = world_to_tile(current_pos)
	if _is_wall_at(current_tile, controller.current_z_level):
		_complete_physics_flight()
	
	if is_multiplayer_authority() and randf() < 0.1:
		sync_physics_flight.rpc(current_pos, current_rotation, angular_velocity, flight_elapsed)

func _complete_physics_flight():
	if not is_multiplayer_authority():
		return
	
	is_flying = false
	angular_velocity = 0.0
	current_rotation = 0.0
	flight_elapsed = 0.0
	
	var final_tile = world_to_tile(controller.position)
	if _is_valid_tile(final_tile):
		current_tile_position = final_tile
		controller.position = tile_to_world(final_tile)
	
	var posture_comp = get_posture_component()
	if landing_forced_lying and posture_comp:
		if posture_comp.has_method("force_lie_down"):
			posture_comp.force_lie_down()
		landing_forced_lying = false
	
	if audio_system:
		audio_system.play_positioned_sound("body_fall", controller.position, 0.6)
	
	if controller.has_node("StatusEffectComponent"):
		var status_effect_comp = controller.get_node("StatusEffectComponent")
		if status_effect_comp.has_method("apply_stun"):
			status_effect_comp.apply_stun(0.5)
	
	set_state(MovementState.IDLE)
	sync_landing.rpc(controller.position, final_tile)

func apply_knockback(direction: Vector2, force: float):
	if not is_multiplayer_authority():
		return
	
	if force < knockback_min_force:
		return
	
	if is_drifting:
		var knockback_drift = direction.normalized() * (force * 0.02)
		drift_direction += knockback_drift
		drift_direction = drift_direction.limit_length(3.0)
		
		angular_velocity += (force * 0.1) * (randf() - 0.5) * 2.0
		
		sync_drift_state.rpc(is_drifting, drift_direction, spin_rotation)
	else:
		_start_physics_flight(direction, force)

func _start_physics_flight(direction: Vector2, force: float):
	if not is_multiplayer_authority():
		return
	
	if is_moving:
		is_moving = false
		move_progress = 0.0
	
	var normalized_dir = direction.normalized()
	var flight_distance = min(force * 0.8, 200.0)
	flight_duration = sqrt(flight_distance / 100.0) * 0.8
	
	flight_start_position = controller.position
	flight_target_position = flight_start_position + (normalized_dir * flight_distance)
	
	_validate_flight_path(normalized_dir, flight_distance)
	
	is_flying = true
	flight_elapsed = 0.0
	
	angular_velocity = (force * knockback_spin_multiplier * 0.01) * (randf() - 0.5) * 2.0
	landing_forced_lying = force > 100.0
	
	set_state(MovementState.FLYING)
	sync_flight_start.rpc(flight_start_position, flight_target_position, flight_duration, angular_velocity, landing_forced_lying)

func _validate_flight_path(normalized_dir: Vector2, flight_distance: float):
	var steps = int(flight_distance / tile_size)
	for i in range(steps):
		var check_pos = flight_start_position + (normalized_dir * i * tile_size)
		var check_tile = world_to_tile(check_pos)
		if _is_wall_at(check_tile, controller.current_z_level):
			flight_target_position = check_pos - (normalized_dir * tile_size)
			break

func set_state(new_state: int):
	if new_state != current_state:
		var old_state = current_state
		current_state = new_state
		
		if is_multiplayer_authority():
			sync_state_change.rpc(new_state)
		
		_apply_state_effects(old_state, new_state)
		emit_signal("state_changed", old_state, new_state)

func _apply_state_effects(old_state: int, new_state: int):
	if old_state == MovementState.CRAWLING and new_state != MovementState.CRAWLING:
		movement_speed_modifier = 1.0
	
	match new_state:
		MovementState.STUNNED:
			is_stunned = true
		MovementState.CRAWLING:
			if is_lying:
				movement_speed_modifier = 0.5 * crawl_speed_multiplier

func _process_stun(delta: float):
	stun_remaining -= delta
	if stun_remaining <= 0:
		is_stunned = false
		set_state(MovementState.IDLE)

func _calculate_move_time():
	if current_state == MovementState.RUNNING:
		current_move_time = running_move_time
	elif current_state == MovementState.CRAWLING and is_lying:
		current_move_time = crawling_move_time
	else:
		current_move_time = base_move_time
	
	if is_dragging_entity:
		current_move_time /= drag_slowdown_modifier
	
	current_move_time /= movement_speed_modifier
	current_move_time /= max(0.5, min(1.5, current_tile_friction))
	
	var grab_comp = get_grab_component()
	if grab_comp and grab_comp.has_method("pulling_entity") and grab_comp.pulling_entity:
		current_move_time *= 1.2
	
	if is_lying:
		current_move_time *= 1.2

func _process_stamina(delta: float):
	if is_sprinting and is_moving:
		current_stamina = max(0, current_stamina - stamina_drain_rate * delta)
		
		if current_stamina <= 0 and sprint_allowed:
			sprint_allowed = false
			is_sprinting = false
			if sensory_system:
				sensory_system.display_message("You're too exhausted to keep running!")
	else:
		if current_stamina < max_stamina:
			var recovery_mult = 1.5 if is_lying else 1.0
			current_stamina = min(max_stamina, current_stamina + stamina_regen_rate * recovery_mult * delta)
			
			if not sprint_allowed and current_stamina >= sprint_recovery_threshold:
				sprint_allowed = true
				if sensory_system:
					sensory_system.display_message("You've caught your breath.")

func toggle_run(is_running: bool):
	if not is_multiplayer_authority():
		return
		
	if is_running and (not sprint_allowed or current_stamina <= 0):
		if sensory_system:
			sensory_system.display_message("You're too exhausted to run!")
		return
	
	is_sprinting = is_running and sprint_allowed
	
	if is_sprinting and is_moving:
		set_state(MovementState.RUNNING)
	elif is_moving:
		set_state(MovementState.MOVING)

func check_tile_environment():
	if not world:
		return
	
	var z_level = controller.current_z_level if controller else 0
	var tile_data = _get_tile_data(z_level)
	
	if not tile_data:
		return
	
	_process_tile_effects(tile_data, z_level)

func _get_tile_data(z_level: int):
	if world.has_method("get_tile_data"):
		return world.get_tile_data(current_tile_position, z_level)
	elif world.has_method("get_tile_at"):
		var world_pos = tile_to_world(current_tile_position)
		return world.get_tile_at(world_pos)
	return null

func _process_tile_effects(tile_data: Dictionary, z_level: int):
	if "slippery" in tile_data and tile_data.slippery:
		current_tile_friction = 0.2
		
		if not is_stunned and not is_drifting and randf() < 0.4:
			_slip(1.5)
	else:
		current_tile_friction = 1.0
	
	var is_space_tile = _check_space_tile(tile_data, z_level)
	
	if is_space_tile:
		if not is_drifting:
			start_drifting()
	elif is_drifting:
		stop_drifting()

func _check_space_tile(tile_data: Dictionary, z_level: int) -> bool:
	if world.has_method("is_space"):
		return world.is_space(current_tile_position, z_level)
	elif "space" in tile_data:
		return tile_data.space
	return false

func _slip(duration: float):
	if controller and controller.has_node("StatusEffectComponent"):
		var status_effect_comp = controller.get_node("StatusEffectComponent")
		if status_effect_comp.has_method("apply_stun"):
			status_effect_comp.apply_stun(duration)
	
	if sensory_system:
		sensory_system.display_message("You slip!")
	
	if audio_system:
		audio_system.play_positioned_sound("slip", controller.position, 0.6)

func _update_facing_from_movement(movement_vector: Vector2i):
	var new_direction = _calculate_direction_from_vector(movement_vector)
	
	current_direction = new_direction
	_update_sprite_direction(new_direction)
	emit_signal("direction_changed", new_direction)
	
	if is_multiplayer_authority():
		sync_direction_change.rpc(current_direction)

func _calculate_direction_from_vector(movement_vector: Vector2i) -> int:
	if movement_vector.x > 0 and movement_vector.y == 0:
		return Direction.EAST
	elif movement_vector.x < 0 and movement_vector.y == 0:
		return Direction.WEST
	elif movement_vector.x == 0 and movement_vector.y < 0:
		return Direction.NORTH
	elif movement_vector.x == 0 and movement_vector.y > 0:
		return Direction.SOUTH
	elif movement_vector.x > 0 and movement_vector.y < 0:
		return Direction.NORTHEAST
	elif movement_vector.x > 0 and movement_vector.y > 0:
		return Direction.SOUTHEAST
	elif movement_vector.x < 0 and movement_vector.y > 0:
		return Direction.SOUTHWEST
	elif movement_vector.x < 0 and movement_vector.y < 0:
		return Direction.NORTHWEST
	else:
		return Direction.NONE

func _update_sprite_direction(direction: int):
	if sprite_system:
		if sprite_system.has_method("get_alien_type"):
			sprite_system.set_direction(direction)
		else:
			var sprite_dir = _convert_to_sprite_direction(direction)
			sprite_system.set_direction(sprite_dir)

func _convert_to_sprite_direction(direction: int) -> int:
	match direction:
		Direction.NORTH: return 1
		Direction.EAST: return 2
		Direction.SOUTH: return 0
		Direction.WEST: return 3
		Direction.NORTHEAST: return 2
		Direction.SOUTHEAST: return 0
		Direction.SOUTHWEST: return 0
		Direction.NORTHWEST: return 3
		_: return 0

func _get_normalized_input_direction(raw_input: Vector2) -> Vector2i:
	if raw_input == Vector2.ZERO:
		raw_input = last_input_direction
	
	if raw_input == Vector2.ZERO:
		return Vector2i.ZERO
	
	var input_dir = Vector2i.ZERO
	if abs(raw_input.x) > abs(raw_input.y):
		input_dir.x = 1 if raw_input.x > 0 else -1
	else:
		input_dir.y = 1 if raw_input.y > 0 else -1
	
	if confusion_level > 0:
		input_dir = _apply_confusion(input_dir)
	
	return input_dir

func _apply_confusion(input_dir: Vector2i) -> Vector2i:
	if confusion_level > 40:
		var dirs = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
		return dirs[randi() % 4]
	elif randf() < confusion_level * 0.015:
		if input_dir.x != 0:
			return Vector2i(0, [-1, 1][randi() % 2])
		else:
			return Vector2i([-1, 1][randi() % 2], 0)
	
	return input_dir

func world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x / tile_size), int(world_pos.y / tile_size))

func tile_to_world(tile_pos: Vector2i) -> Vector2:
	return Vector2((tile_pos.x * tile_size) + (tile_size / 2.0), 
				   (tile_pos.y * tile_size) + (tile_size / 2.0))

func _is_valid_tile(tile_pos: Vector2i) -> bool:
	if not world:
		return false
	
	var z_level = controller.current_z_level if controller else 0
	
	if world.has_method("is_in_zone"):
		return world.is_in_zone(tile_pos, z_level)
	elif world.has_method("is_valid_tile"):
		return world.is_valid_tile(tile_pos, z_level)
	elif world.has_method("get_tile_at"):
		var tile = world.get_tile_at(Vector2(tile_pos.x * tile_size, tile_pos.y * tile_size))
		return tile != null
	
	return tile_pos.x >= -1000 and tile_pos.x <= 1000 and tile_pos.y >= -1000 and tile_pos.y <= 1000

func _is_wall_at(tile_pos: Vector2i, z_level: int) -> bool:
	if world and world.has_method("is_wall_at"):
		return world.is_wall_at(tile_pos, z_level)
	elif world and world.has_method("get_tile_data"):
		var tile_data = world.get_tile_data(tile_pos, z_level)
		if tile_data and "wall" in tile_data:
			return tile_data.wall
	return false

func _get_door_at_tile(tile_pos: Vector2i, z_level: int):
	if not tile_occupancy_system:
		return null
		
	return tile_occupancy_system.get_entity_at(tile_pos, z_level, "door")

func _get_entity_tile_position(entity: Node) -> Vector2i:
	if not entity:
		return Vector2i.ZERO
	
	if "current_tile_position" in entity:
		return entity.current_tile_position
	elif "tile_position" in entity:
		return entity.tile_position
	elif "global_position" in entity:
		return world_to_tile(entity.global_position)
	elif "position" in entity:
		return world_to_tile(entity.position)
	
	return Vector2i.ZERO

func _get_entity_name(entity: Node) -> String:
	if "entity_name" in entity and entity.entity_name != "":
		return entity.entity_name
	elif "name" in entity:
		return entity.name
	else:
		return "someone"

func _get_floor_type(tile_pos: Vector2i) -> String:
	if world and world.has_method("get_tile_data"):
		var z_level = controller.current_z_level if controller else 0
		var tile_data = world.get_tile_data(tile_pos, z_level)
		if tile_data and "floor" in tile_data:
			return tile_data.floor.get("type", "metal")
	return "metal"

func _get_controller_intent() -> int:
	if controller.has_node("IntentComponent"):
		var intent_comp = controller.get_node("IntentComponent")
		if "intent" in intent_comp:
			return intent_comp.intent
	
	if controller.is_in_group("aliens"):
		return 3
	
	return 0

func _ease_movement_progress(progress: float) -> float:
	return lerp(progress, progress * progress * (3.0 - 2.0 * progress), 0.3)

func _try_auto_open_door(door):
	if door and is_instance_valid(door) and door.has_method("open_door"):
		door.open_door(controller)

func _interpolate_to_network_position(delta: float):
	if not controller:
		return
		
	var distance = controller.position.distance_to(network_position)
	if distance > 0.5:
		var interpolation_speed = 8.0
		controller.position = controller.position.lerp(network_position, interpolation_speed * delta)

func get_grab_component() -> Node:
	if not grab_component and controller:
		grab_component = controller.get_node_or_null("GrabPullComponent")
		if not grab_component:
			grab_component = controller.get_node_or_null("AlienGrabPullComponent")
	return grab_component

func get_posture_component() -> Node:
	if not posture_component and controller:
		posture_component = controller.get_node_or_null("PostureComponent")
		if not posture_component:
			posture_component = controller.get_node_or_null("AlienPostureComponent")
	return posture_component

func is_adjacent_to(target: Node, allow_diagonal: bool = true) -> bool:
	if not target:
		return false
	
	var my_pos = current_tile_position
	var target_pos = _get_entity_tile_position(target)
	
	if my_pos == target_pos:
		return true
	
	var diff = target_pos - my_pos
	var distance = max(abs(diff.x), abs(diff.y))
	
	if distance > 1:
		return false
	
	if abs(diff.x) == 1 and abs(diff.y) == 1 and not allow_diagonal:
		return false
	
	return true

func can_entity_move_to(entity, tile_pos: Vector2i, z_level: int) -> bool:
	if not _is_valid_tile(tile_pos):
		return false
	
	var collision = _check_collision(tile_pos)
	if collision == CollisionType.WALL:
		return false
	
	if collision == CollisionType.DOOR:
		var door = _get_door_at_tile(tile_pos, z_level)
		if door and door.has_method("_check_access"):
			return door._check_access(entity)
		return false
	
	return collision == CollisionType.NONE

func get_current_tile_position() -> Vector2i:
	return current_tile_position

func get_current_direction() -> int:
	return current_direction

func _on_lying_state_changed(lying: bool):
	is_lying = lying
	if lying:
		set_state(MovementState.CRAWLING)
	else:
		set_state(MovementState.IDLE)

func set_movement_modifier(modifier: float):
	movement_speed_modifier = modifier

func set_speed_modifier(modifier: float):
	movement_speed_modifier = modifier

func set_confusion(level: float):
	confusion_level = level

func setup_singleplayer():
	is_local_player = true
	peer_id = 1
	network_interpolation_enabled = false

func setup_multiplayer(player_peer_id: int):
	peer_id = player_peer_id
	is_local_player = (peer_id == multiplayer.get_unique_id())
	network_interpolation_enabled = not is_local_player

@rpc("any_peer", "unreliable_ordered", "call_local")
func sync_position(pos: Vector2, tile_pos: Vector2i, moving: bool, progress: float):
	network_position = pos
	if not is_multiplayer_authority():
		current_tile_position = tile_pos
		is_moving = moving
		move_progress = progress
		if controller and controller.position.distance_to(pos) > tile_size:
			controller.position = pos

@rpc("any_peer", "reliable", "call_local")
func sync_movement_start(start_tile: Vector2i, target_tile: Vector2i, direction: int, move_time: float, state: int):
	if not is_multiplayer_authority():
		_apply_movement_start(start_tile, target_tile, direction, move_time, state)

@rpc("any_peer", "reliable", "call_local")
func sync_movement_complete(final_tile: Vector2i, final_pos: Vector2):
	if not is_multiplayer_authority():
		_apply_movement_complete(final_tile, final_pos)

@rpc("any_peer", "reliable", "call_local")
func sync_external_movement(start_tile: Vector2i, target_tile: Vector2i, move_time: float, animated: bool):
	if not is_multiplayer_authority():
		_apply_external_movement(start_tile, target_tile, move_time, animated)

@rpc("any_peer", "reliable", "call_local")
func sync_direction_change(new_direction: int):
	if not is_multiplayer_authority():
		current_direction = new_direction

@rpc("any_peer", "reliable", "call_local")
func sync_state_change(new_state: int):
	if not is_multiplayer_authority():
		current_state = new_state

@rpc("any_peer", "reliable", "call_local")
func sync_drift_state(drifting: bool, drift_dir: Vector2, rotation: float):
	if not is_multiplayer_authority():
		is_drifting = drifting
		drift_direction = drift_dir
		spin_rotation = rotation

@rpc("any_peer", "reliable", "call_local")
func sync_physics_flight(pos: Vector2, rotation: float, ang_vel: float, elapsed: float):
	if not is_multiplayer_authority():
		physics_position = pos
		current_rotation = rotation
		angular_velocity = ang_vel
		flight_elapsed = elapsed
		if controller:
			controller.position = pos

@rpc("any_peer", "reliable", "call_local")
func sync_flight_start(start_pos: Vector2, target_pos: Vector2, duration: float, ang_vel: float, forced_lying: bool):
	if not is_multiplayer_authority():
		is_flying = true
		flight_start_position = start_pos
		flight_target_position = target_pos
		flight_duration = duration
		angular_velocity = ang_vel
		landing_forced_lying = forced_lying
		flight_elapsed = 0.0
		set_state(MovementState.FLYING)

@rpc("any_peer", "reliable", "call_local")
func sync_landing(final_pos: Vector2, final_tile: Vector2i):
	if not is_multiplayer_authority():
		is_flying = false
		angular_velocity = 0.0
		current_rotation = 0.0
		flight_elapsed = 0.0
		current_tile_position = final_tile
		if controller:
			controller.position = final_pos
		set_state(MovementState.IDLE)

@rpc("any_peer", "reliable", "call_local")
func sync_tile_change(old_tile: Vector2i, new_tile: Vector2i):
	if not is_multiplayer_authority():
		emit_signal("tile_changed", old_tile, new_tile)
		emit_signal("entity_moved", old_tile, new_tile, controller)

@rpc("any_peer", "reliable", "call_local")
func sync_collision_event(collision_type: int, target_tile: Vector2i, direction: Vector2i):
	if not is_multiplayer_authority():
		_handle_collision_effects(collision_type, target_tile, direction)

@rpc("any_peer", "reliable", "call_local")
func sync_entity_interaction(interaction_type: int, target_tile: Vector2i, direction: Vector2i, pusher_name: String):
	if not is_multiplayer_authority():
		_handle_remote_entity_interaction(interaction_type, target_tile, direction, pusher_name)

@rpc("any_peer", "reliable", "call_local")
func sync_footstep(position: Vector2, floor_type: String):
	if audio_system:
		audio_system.play_positioned_sound("footstep_" + floor_type, position, 0.2)

func _handle_remote_entity_interaction(interaction_type: int, target_tile: Vector2i, direction: Vector2i, pusher_name: String):
	match interaction_type:
		0:
			if sensory_system:
				sensory_system.display_message("You swap places with " + pusher_name + ".")
		1:
			if sensory_system:
				sensory_system.display_message(pusher_name + " pushes you!")
		2:
			if audio_system:
				audio_system.play_positioned_sound("bump", controller.position, 0.3)

func _apply_movement_start(start_tile: Vector2i, target_tile: Vector2i, direction: int, move_time: float, state: int):
	current_tile_position = start_tile
	target_tile_position = target_tile
	current_direction = direction
	current_move_time = move_time
	current_state = state
	is_moving = true
	move_progress = 0.0
	
	if tile_occupancy_system:
		tile_occupancy_system.move_entity(controller, current_tile_position, target_tile_position, controller.current_z_level)

func _apply_movement_complete(final_tile: Vector2i, final_pos: Vector2):
	is_moving = false
	move_progress = 1.0
	previous_tile_position = current_tile_position
	current_tile_position = final_tile
	
	if controller:
		controller.position = final_pos
	
	emit_signal("tile_changed", previous_tile_position, current_tile_position)
	emit_signal("entity_moved", previous_tile_position, current_tile_position, controller)

func _apply_external_movement(start_tile: Vector2i, target_tile: Vector2i, move_time: float, animated: bool):
	current_tile_position = start_tile
	target_tile_position = target_tile
	current_move_time = move_time
	
	if animated:
		is_moving = true
		move_progress = 0.0
		
		if tile_occupancy_system:
			tile_occupancy_system.move_entity(controller, current_tile_position, target_tile_position, controller.current_z_level)
	else:
		previous_tile_position = current_tile_position
		current_tile_position = target_tile_position
		
		if controller:
			controller.position = tile_to_world(target_tile_position)
		
		emit_signal("tile_changed", previous_tile_position, current_tile_position)
		emit_signal("entity_moved", previous_tile_position, current_tile_position, controller)
