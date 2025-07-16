extends Node
class_name MovementComponent

## Handles all grid-based movement including walking, running, crawling, and zero-G movement

#region CONSTANTS
const TILE_SIZE: int = 32
const BASE_MOVE_TIME: float = 0.3
const RUNNING_MOVE_TIME: float = 0.2
const CRAWLING_MOVE_TIME: float = 0.35
const MIN_MOVE_INTERVAL: float = 0.01
const INPUT_BUFFER_TIME: float = 0.2

# Zero-G constants
const ZERO_G_THRUST: float = 4.0
const ZERO_G_DAMPING: float = 0.995
const ZERO_G_ROTATION_SPEED: float = 3.0
const ZERO_G_MAX_SPEED: float = 8.0
const ZERO_G_CONTROL_FACTOR: float = 0.15
const ZERO_G_BOUNCE_FACTOR: float = 0.8
const ZERO_G_GRID_SNAP_THRESHOLD: float = 0.25
#endregion

#region ENUMS
enum MovementState {
	IDLE,
	MOVING,
	RUNNING,
	STUNNED,
	CRAWLING,
	FLOATING
}

enum Direction {
	NONE = -1,
	NORTH = 0,
	EAST = 1,
	SOUTH = 2,
	WEST = 3,
	NORTHEAST = 4,
	SOUTHEAST = 5,
	SOUTHWEST = 6,
	NORTHWEST = 7
}

enum CollisionType {
	NONE,
	WALL,
	ENTITY,
	DENSE_OBJECT,
	DOOR_CLOSED,
	WINDOW
}
#endregion

#region SIGNALS
signal direction_changed (new_direction: int)
signal tile_changed(old_tile: Vector2i, new_tile: Vector2i)
signal state_changed(old_state: int, new_state: int)
signal entity_moved(old_tile: Vector2i, new_tile: Vector2i, entity: Node)
signal began_floating()
signal stopped_floating()
signal footstep(position: Vector2, floor_type: String)
signal bump(entity: Node, bumped_entity: Node, direction: Vector2i)
signal pushing_entity(pushed_entity: Node, direction: Vector2i)
#endregion

#region PROPERTIES
# Core references
var controller: Node = null
var world = null
var tile_occupancy_system = null
var sensory_system = null
var audio_system = null
var sprite_system = null

# Movement state
var current_state: int = MovementState.IDLE
var current_direction: int = Direction.SOUTH
var current_tile_position: Vector2i = Vector2i.ZERO
var previous_tile_position: Vector2i = Vector2i.ZERO
var target_tile_position: Vector2i = Vector2i.ZERO
var move_progress: float = 0.0
var is_moving: bool = false
var current_move_time: float = BASE_MOVE_TIME
var next_move_time: float = 0.0

# Movement flags
var is_local_player: bool = false
var allow_diagonal: bool = false
var is_sprinting: bool = false
var is_lying: bool = false
var is_stunned: bool = false
var is_floating: bool = false
var is_dragging_entity: bool = false

# Movement modifiers
var movement_speed_modifier: float = 1.0
var drag_slowdown_modifier: float = 0.6
var pull_speed_modifier: float = 0.7
var crawl_speed_multiplier: float = 0.5
var current_tile_friction: float = 1.0

# Input buffering
var input_buffer_timer: float = 0.0
var buffered_movement: Vector2i = Vector2i.ZERO
var last_input_direction: Vector2 = Vector2.ZERO

# Stamina system
var max_stamina: float = 100.0
var current_stamina: float = 100.0
var stamina_drain_rate: float = 3.33
var stamina_regen_rate: float = 5.0
var sprint_allowed: bool = true
var sprint_recovery_threshold: float = 25.0

# Zero-G properties
var velocity: Vector2 = Vector2.ZERO
var gravity_strength: float = 1.0
var inertia_dir: Vector2 = Vector2.ZERO
var last_push_time: float = 0.0
var entry_velocity: Vector2 = Vector2.ZERO

# Status
var stun_remaining: float = 0.0
var confusion_level: float = 0.0
#endregion

func initialize(init_data: Dictionary):
	"""Initialize the movement component with necessary references"""
	controller = init_data.get("controller")
	world = init_data.get("world")
	tile_occupancy_system = init_data.get("tile_occupancy_system")
	sensory_system = init_data.get("sensory_system")
	audio_system = init_data.get("audio_system")
	sprite_system = init_data.get("sprite_system")
	is_local_player = init_data.get("is_local_player", false)
	
	# Initialize position
	if controller:
		current_tile_position = world_to_tile(controller.position)
		previous_tile_position = current_tile_position
		target_tile_position = current_tile_position

func _physics_process(delta: float):
	"""Process movement physics"""
	if not is_local_player:
		return
	
	# Handle stun
	if is_stunned:
		process_stun(delta)
		return
	
	# Process movement based on state
	if is_floating:
		process_zero_g_movement(delta)
	else:
		process_grid_movement(delta)
	
	# Update stamina
	process_stamina(delta)

#region GRID MOVEMENT
func process_grid_movement(delta: float):
	"""Process standard grid-based movement"""
	if not is_moving:
		# Process buffered input
		if buffered_movement != Vector2i.ZERO and input_buffer_timer > 0:
			input_buffer_timer -= delta
			if input_buffer_timer <= 0:
				attempt_move(buffered_movement)
				buffered_movement = Vector2i.ZERO
		return
	
	# Update movement progress
	var progress_delta = delta / current_move_time
	move_progress += progress_delta
	
	if move_progress >= 1.0:
		complete_movement()
	else:
		# Interpolate position
		var start_pos = tile_to_world(current_tile_position)
		var end_pos = tile_to_world(target_tile_position)
		var eased_progress = ease_movement_progress(move_progress)
		
		if controller:
			controller.position = start_pos.lerp(end_pos, eased_progress)

func handle_move_input(direction: Vector2):
	"""Handle movement input with buffering"""
	if not is_local_player:
		return
	
	last_input_direction = direction
	var normalized_dir = get_normalized_input_direction(direction)
	
	if normalized_dir == Vector2i.ZERO:
		return
	
	if is_moving:
		# Buffer input if near end of movement
		if move_progress >= 0.7:
			buffered_movement = normalized_dir
			input_buffer_timer = INPUT_BUFFER_TIME
	else:
		attempt_move(normalized_dir)

func attempt_move(direction: Vector2i) -> bool:
	"""Attempt to move in the given direction"""
	if is_stunned or is_moving:
		return false
	
	# Check move timing
	var current_time = Time.get_ticks_msec() * 0.001
	if current_time < next_move_time:
		buffered_movement = direction
		input_buffer_timer = INPUT_BUFFER_TIME
		return false
	
	# Update facing
	update_facing_from_movement(direction)
	
	# Calculate target
	var target_tile = current_tile_position + direction
	
	# Check collision
	var collision = check_collision(target_tile)
	
	if collision == CollisionType.NONE:
		start_move_to(target_tile)
		return true
	else:
		handle_collision(collision, target_tile, direction)
		return false

func start_move_to(target: Vector2i):
	"""Start moving to target tile"""
	is_moving = true
	move_progress = 0.0
	target_tile_position = target
	
	# Set move timing
	next_move_time = Time.get_ticks_msec() * 0.001 + MIN_MOVE_INTERVAL
	calculate_move_time()
	
	# Update occupancy
	if tile_occupancy_system:
		tile_occupancy_system.move_entity(controller, current_tile_position, target_tile_position, controller.current_z_level)
	
	# Play sound
	emit_footstep_sound()
	
	# Update state
	if is_sprinting and not is_lying:
		set_state(MovementState.RUNNING)
	elif is_lying:
		set_state(MovementState.CRAWLING)
	else:
		set_state(MovementState.MOVING)

func complete_movement():
	"""Complete the current movement"""
	if not is_moving:
		return
	
	move_progress = 1.0
	is_moving = false
	
	# Update position
	if controller:
		controller.position = tile_to_world(target_tile_position)
	
	# Update tiles
	previous_tile_position = current_tile_position
	current_tile_position = target_tile_position
	
	# Emit signals
	emit_signal("tile_changed", previous_tile_position, current_tile_position)
	emit_signal("entity_moved", previous_tile_position, current_tile_position, controller)
	
	# Check environment
	check_tile_environment()
	
	# Update state
	if is_lying:
		set_state(MovementState.CRAWLING)
	else:
		set_state(MovementState.IDLE)
	
	# Process buffered movement
	if buffered_movement != Vector2i.ZERO and input_buffer_timer > INPUT_BUFFER_TIME * 0.5:
		var next_dir = buffered_movement
		buffered_movement = Vector2i.ZERO
		input_buffer_timer = 0
		await controller.get_tree().create_timer(0.05).timeout
		attempt_move(next_dir)

func move_externally(target_position: Vector2i, animated: bool = true, force: bool = false) -> bool:
	"""Move entity externally (by push, grab, etc)"""
	if is_moving and not force:
		return false
	
	if not is_valid_tile(target_position):
		return false
	
	var direction = target_position - current_tile_position
	if direction == Vector2i.ZERO:
		return true
	
	if animated:
		update_facing_from_movement(direction)
		start_external_move_to(target_position)
		return true
	else:
		return perform_instant_move(target_position)

func start_external_move_to(target: Vector2i):
	"""Start external movement animation"""
	is_moving = true
	move_progress = 0.0
	target_tile_position = target
	
	# Use faster external move time
	current_move_time = BASE_MOVE_TIME * 0.7
	
	# Update occupancy
	if tile_occupancy_system:
		tile_occupancy_system.move_entity(controller, current_tile_position, target_tile_position, controller.current_z_level)
	
	# Set appropriate state
	if is_lying:
		set_state(MovementState.CRAWLING)
	else:
		set_state(MovementState.MOVING)

func perform_instant_move(target_position: Vector2i) -> bool:
	"""Instantly move to target position"""
	var old_pos = current_tile_position
	
	# Update occupancy first
	if tile_occupancy_system:
		if not tile_occupancy_system.move_entity(controller, old_pos, target_position, controller.current_z_level):
			return false
	
	# Update position
	current_tile_position = target_position
	previous_tile_position = old_pos
	if controller:
		controller.position = tile_to_world(target_position)
	
	# Update facing
	var direction = target_position - old_pos
	if direction != Vector2i.ZERO:
		update_facing_from_movement(direction)
	
	# Emit signals
	emit_signal("tile_changed", old_pos, target_position)
	emit_signal("entity_moved", old_pos, target_position, controller)
	
	return true
#endregion

#region MOVEMENT HELPERS
func calculate_move_time():
	"""Calculate movement time based on current conditions"""
	# Base time
	if current_state == MovementState.RUNNING:
		current_move_time = RUNNING_MOVE_TIME
	elif current_state == MovementState.CRAWLING and is_lying:
		current_move_time = CRAWLING_MOVE_TIME
	else:
		current_move_time = BASE_MOVE_TIME
	
	# Apply modifiers
	if is_dragging_entity:
		current_move_time /= drag_slowdown_modifier
	
	current_move_time /= movement_speed_modifier
	current_move_time /= max(0.5, min(1.5, current_tile_friction))
	
	# Extra penalties
	if controller.grab_pull_component and controller.grab_pull_component.pulling_entity:
		current_move_time *= 1.2
	
	if is_lying:
		current_move_time *= 1.2

func get_normalized_input_direction(raw_input: Vector2) -> Vector2i:
	"""Convert raw input to cardinal direction"""
	if raw_input == Vector2.ZERO:
		raw_input = last_input_direction
	
	if raw_input == Vector2.ZERO:
		return Vector2i.ZERO
	
	# Force cardinal movement only
	var input_dir = Vector2i.ZERO
	if abs(raw_input.x) > abs(raw_input.y):
		input_dir.x = 1 if raw_input.x > 0 else -1
	else:
		input_dir.y = 1 if raw_input.y > 0 else -1
	
	# Apply confusion if active
	if confusion_level > 0:
		input_dir = apply_confusion(input_dir)
	
	return input_dir

func apply_confusion(input_dir: Vector2i) -> Vector2i:
	"""Apply confusion effect to movement"""
	if confusion_level > 40:
		# Completely random direction
		var dirs = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
		return dirs[randi() % 4]
	elif randf() < confusion_level * 0.015:
		# 90 degree turn
		if input_dir.x != 0:
			return Vector2i(0, [-1, 1][randi() % 2])
		else:
			return Vector2i([-1, 1][randi() % 2], 0)
	
	return input_dir

func ease_movement_progress(progress: float) -> float:
	"""Apply easing to movement progress"""
	return lerp(progress, progress * progress * (3.0 - 2.0 * progress), 0.3)

func toggle_run(is_running: bool):
	"""Toggle running state"""
	if is_running and (!sprint_allowed or current_stamina <= 0):
		if sensory_system:
			sensory_system.display_message("You're too exhausted to run!")
		return
	
	is_sprinting = is_running and sprint_allowed
	
	if is_sprinting and is_moving:
		set_state(MovementState.RUNNING)
	elif is_moving:
		set_state(MovementState.MOVING)
#endregion

#region COLLISION HANDLING
func check_collision(target_tile: Vector2i) -> int:
	"""Check for collision at target tile"""
	var z_level = controller.current_z_level if controller else 0
	
	# Check walls
	if is_wall_at(target_tile, z_level):
		return CollisionType.WALL
	
	# Check doors
	if is_closed_door_at(target_tile, z_level):
		return CollisionType.DOOR_CLOSED
	
	# Check entities
	if tile_occupancy_system:
		if tile_occupancy_system.has_dense_entity_at(target_tile, z_level, controller):
			# Special handling for grabbed entities
			if controller.grab_pull_component:
				var entity = tile_occupancy_system.get_entity_at(target_tile, z_level)
				if controller.grab_pull_component.is_entity_grabbed_by_me(entity):
					return CollisionType.NONE
			
			return CollisionType.ENTITY
	
	return CollisionType.NONE

func handle_collision(collision_type: int, target_tile: Vector2i, direction: Vector2i):
	"""Handle different collision types"""
	match collision_type:
		CollisionType.ENTITY:
			handle_entity_collision(target_tile, direction)
		CollisionType.DOOR_CLOSED:
			handle_door_collision(target_tile)
		CollisionType.WALL, CollisionType.WINDOW:
			if audio_system:
				audio_system.play_positioned_sound("bump", controller.position, 0.3)

func handle_entity_collision(target_tile: Vector2i, direction: Vector2i):
	"""Handle collision with an entity"""
	if not tile_occupancy_system:
		return
	
	var entity = tile_occupancy_system.get_entity_at(target_tile, controller.current_z_level)
	if not entity:
		return
	
	# Get intent from controller
	var intent = controller.intent_component.intent if controller.intent_component else 0
	
	match intent:
		0: # HELP
			handle_position_swap(entity, target_tile)
		1, 2, 3: # DISARM, GRAB, HARM
			handle_entity_push(entity, direction, target_tile)

func handle_position_swap(other_entity: Node, target_tile: Vector2i):
	"""Swap positions with another entity"""
	var other_pos = get_entity_tile_position(other_entity)
	var my_pos = current_tile_position
	
	# Move both entities
	if other_entity.has_method("move_externally"):
		other_entity.move_externally(my_pos)
	start_move_to(target_tile)
	
	if sensory_system:
		var name = other_entity.entity_name if "entity_name" in other_entity else other_entity.name
		sensory_system.display_message("You swap places with " + name + ".")

func handle_entity_push(entity: Node, direction: Vector2i, target_tile: Vector2i):
	"""Push an entity"""
	var push_target = target_tile + direction
	var push_collision = check_collision(push_target)
	
	if push_collision == CollisionType.NONE:
		# Push entity
		var push_success = false
		if entity.has_method("move_externally"):
			push_success = entity.move_externally(push_target, true, true)
		
		if push_success:
			start_move_to(target_tile)
			emit_signal("pushing_entity", entity, direction)
			
			if sensory_system:
				var name = entity.entity_name if "entity_name" in entity else entity.name
				sensory_system.display_message("You push " + name + "!")
		else:
			emit_signal("bump", controller, entity, direction)
	else:
		emit_signal("bump", controller, entity, direction)
		if audio_system:
			audio_system.play_positioned_sound("bump", controller.position, 0.3)

func handle_door_collision(target_tile: Vector2i):
	"""Handle collision with a door"""
	if world and world.has_method("toggle_door"):
		world.toggle_door(target_tile, controller.current_z_level)
		if audio_system:
			audio_system.play_positioned_sound("door_open", controller.position, 0.5)
#endregion

#region ZERO-G MOVEMENT
func process_zero_g_movement(delta: float):
	"""Process zero-gravity movement physics"""
	var input_dir = get_zero_g_input_direction()
	
	# Update facing
	if input_dir != Vector2.ZERO:
		var target_angle = input_dir.angle()
		var grid_dir = convert_angle_to_grid_direction(target_angle)
		if grid_dir != Direction.NONE:
			current_direction = grid_dir
			update_sprite_direction(grid_dir)
		
		# Apply thrust
		if check_zero_g_push_possible():
			velocity += input_dir * ZERO_G_THRUST * delta
			
			if audio_system and Time.get_ticks_msec() * 0.001 - last_push_time > 0.5:
				audio_system.play_positioned_sound("space_push", controller.position, 0.2)
				last_push_time = Time.get_ticks_msec() * 0.001
		else:
			velocity += input_dir * ZERO_G_THRUST * ZERO_G_CONTROL_FACTOR * delta
	
	# Apply damping
	velocity *= ZERO_G_DAMPING
	
	# Limit speed
	if velocity.length() > ZERO_G_MAX_SPEED:
		velocity = velocity.normalized() * ZERO_G_MAX_SPEED
	
	# Move position
	if velocity.length() > 0.01:
		var old_position = controller.position
		controller.position += velocity * delta * TILE_SIZE
		
		# Check collision
		var collision = check_zero_g_collision()
		if collision.collided:
			handle_zero_g_collision(collision, old_position)
		
		# Check tile change
		var new_tile_pos = world_to_tile(controller.position)
		if new_tile_pos != current_tile_position:
			handle_zero_g_tile_change(new_tile_pos)

func get_zero_g_input_direction() -> Vector2:
	"""Get input direction for zero-G movement"""
	if not controller or not controller.input_controller:
		return Vector2.ZERO
	
	var raw_input = controller.input_controller.process_movement_input()
	if raw_input == null or raw_input.length() < 0.1:
		return Vector2.ZERO
	
	return raw_input.normalized()

func check_zero_g_push_possible() -> bool:
	"""Check if we can push off something in zero-G"""
	var check_offsets = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	
	var current_pos = world_to_tile(controller.position)
	var z_level = controller.current_z_level if controller else 0
	
	for offset in check_offsets:
		var check_pos = current_pos + offset
		
		if is_wall_at(check_pos, z_level) or is_closed_door_at(check_pos, z_level):
			return true
		
		if tile_occupancy_system and tile_occupancy_system.has_dense_entity_at(check_pos, z_level, controller):
			return true
	
	return false

func check_zero_g_collision() -> Dictionary:
	"""Check for collision in zero-G movement"""
	var result = {
		"collided": false,
		"position": Vector2.ZERO,
		"normal": Vector2.ZERO,
		"entity": null
	}
	
	var current_pos = world_to_tile(controller.position)
	var check_offsets = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)
	]
	
	var bounds_min = controller.position - Vector2(TILE_SIZE * 0.4, TILE_SIZE * 0.4)
	var bounds_max = controller.position + Vector2(TILE_SIZE * 0.4, TILE_SIZE * 0.4)
	
	for offset in check_offsets:
		var check_pos = current_pos + offset
		var tile_center = tile_to_world(check_pos)
		var tile_bounds_min = tile_center - Vector2(TILE_SIZE * 0.5, TILE_SIZE * 0.5)
		var tile_bounds_max = tile_center + Vector2(TILE_SIZE * 0.5, TILE_SIZE * 0.5)
		
		if bounds_max.x > tile_bounds_min.x and bounds_min.x < tile_bounds_max.x and bounds_max.y > tile_bounds_min.y and bounds_min.y < tile_bounds_max.y:
			var z_level = controller.current_z_level if controller else 0
			
			if is_wall_at(check_pos, z_level) or is_closed_door_at(check_pos, z_level):
				var to_character = (controller.position - tile_center).normalized()
				result.collided = true
				result.position = tile_center
				result.normal = to_character
				return result
	
	return result

func handle_zero_g_collision(collision: Dictionary, old_position: Vector2):
	"""Handle collision in zero-G"""
	if not collision.collided:
		return
	
	if audio_system:
		var volume = min(0.3 + (velocity.length() * 0.1), 0.8)
		audio_system.play_positioned_sound("space_bump", controller.position, volume)
	
	if collision.normal != Vector2.ZERO:
		velocity = velocity.bounce(collision.normal) * ZERO_G_BOUNCE_FACTOR
		controller.position = old_position + collision.normal * 1.0
	else:
		velocity = -velocity * ZERO_G_BOUNCE_FACTOR
		controller.position = old_position

func handle_zero_g_tile_change(new_tile_pos: Vector2i):
	"""Handle tile change in zero-G"""
	var z_level = controller.current_z_level if controller else 0
	
	if is_valid_tile(new_tile_pos):
		var old_tile_pos = current_tile_position
		previous_tile_position = current_tile_position
		current_tile_position = new_tile_pos
		
		if tile_occupancy_system:
			tile_occupancy_system.move_entity(controller, old_tile_pos, new_tile_pos, z_level)
		
		emit_signal("tile_changed", old_tile_pos, new_tile_pos)
		emit_signal("entity_moved", old_tile_pos, new_tile_pos, controller)
		
		check_tile_environment()
		emit_footstep_sound(0.15)
	else:
		velocity = -velocity * 0.5

func set_gravity(has_gravity: bool):
	"""Set gravity state"""
	if has_gravity and is_floating:
		gravity_strength = 1.0
		is_floating = false
		
		if velocity.length() > 2.0:
			var landing_force = velocity.length() * 0.3
			if landing_force > 5.0:
				apply_knockback(velocity.normalized(), landing_force)
		
		velocity = Vector2.ZERO
		entry_velocity = Vector2.ZERO
		
		emit_signal("stopped_floating")
		set_state(MovementState.IDLE)
		
	elif not has_gravity and not is_floating:
		gravity_strength = 0.0
		is_floating = true
		
		if is_moving:
			var direction = Vector2(target_tile_position - current_tile_position).normalized()
			entry_velocity = direction * current_move_time * 3.0
			velocity = entry_velocity
			
			is_moving = false
			move_progress = 0.0
		else:
			entry_velocity = Vector2(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5))
			velocity = entry_velocity
		
		emit_signal("began_floating")
		set_state(MovementState.FLOATING)

func apply_zero_g_impulse(impulse: Vector2):
	"""Apply impulse in zero-G"""
	if is_floating:
		velocity += impulse / 70.0  # Assuming mass of 70
		if velocity.length() > ZERO_G_MAX_SPEED * 1.5:
			velocity = velocity.normalized() * ZERO_G_MAX_SPEED * 1.5
#endregion

#region STATE MANAGEMENT
func set_state(new_state: int):
	"""Set movement state"""
	if new_state != current_state:
		var old_state = current_state
		current_state = new_state
		
		# Reset speed when leaving crawling
		if old_state == MovementState.CRAWLING and new_state != MovementState.CRAWLING:
			movement_speed_modifier = 1.0
		
		# Handle state-specific logic
		match new_state:
			MovementState.STUNNED:
				is_stunned = true
			MovementState.CRAWLING:
				if is_lying:
					movement_speed_modifier = 0.5 * crawl_speed_multiplier
		
		emit_signal("state_changed", old_state, new_state)

func process_stun(delta: float):
	"""Process stun effect"""
	stun_remaining -= delta
	if stun_remaining <= 0:
		is_stunned = false
		set_state(MovementState.IDLE)

func process_stamina(delta: float):
	"""Process stamina drain and recovery"""
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

func _on_lying_state_changed(lying: bool):
	"""Handle lying state change from posture component"""
	is_lying = lying
	if lying:
		set_state(MovementState.CRAWLING)
	else:
		set_state(MovementState.IDLE)

func set_movement_modifier(modifier: float):
	"""Set movement speed modifier"""
	movement_speed_modifier = modifier

func set_speed_modifier(modifier: float):
	"""Set speed modifier from status effects"""
	movement_speed_modifier = modifier

func set_confusion(level: float):
	"""Set confusion level"""
	confusion_level = level

func apply_knockback(direction: Vector2, force: float):
	"""Apply knockback force"""
	if is_floating:
		velocity += direction * force * 0.5
		if velocity.length() > ZERO_G_MAX_SPEED * 1.5:
			velocity = velocity.normalized() * ZERO_G_MAX_SPEED * 1.5
	else:
		var knockback_tiles = int(force / 20.0)
		knockback_tiles = min(knockback_tiles, 10)
		
		if knockback_tiles > 0:
			var target = current_tile_position
			for i in range(knockback_tiles):
				var next_tile = target + Vector2i(int(direction.x), int(direction.y))
				if check_collision(next_tile) != CollisionType.NONE:
					break
				target = next_tile
			
			if target != current_tile_position:
				perform_instant_move(target)
#endregion

#region DIRECTION HANDLING
func update_facing_from_movement(movement_vector: Vector2i):
	"""Update facing direction from movement"""
	var new_direction = Direction.NONE
	
	if movement_vector.x > 0 and movement_vector.y == 0:
		new_direction = Direction.EAST
	elif movement_vector.x < 0 and movement_vector.y == 0:
		new_direction = Direction.WEST
	elif movement_vector.x == 0 and movement_vector.y < 0:
		new_direction = Direction.NORTH
	elif movement_vector.x == 0 and movement_vector.y > 0:
		new_direction = Direction.SOUTH
	elif movement_vector.x > 0 and movement_vector.y < 0:
		new_direction = Direction.NORTHEAST
	elif movement_vector.x > 0 and movement_vector.y > 0:
		new_direction = Direction.SOUTHEAST
	elif movement_vector.x < 0 and movement_vector.y > 0:
		new_direction = Direction.SOUTHWEST
	elif movement_vector.x < 0 and movement_vector.y < 0:
		new_direction = Direction.NORTHWEST
	
	current_direction = new_direction
	update_sprite_direction(new_direction)
	emit_signal("direction_changed", new_direction)

func update_sprite_direction(direction: int):
	"""Update sprite system direction"""
	if sprite_system:
		var sprite_dir = convert_to_sprite_direction(direction)
		if sprite_system:
			sprite_system.set_direction(sprite_dir)

func convert_angle_to_grid_direction(angle: float) -> int:
	"""Convert angle to Direction enum"""
	while angle < 0:
		angle += 2 * PI
	while angle >= 2 * PI:
		angle -= 2 * PI
	
	if angle >= 7 * PI / 4 or angle < PI / 4:
		return Direction.EAST
	elif angle >= PI / 4 and angle < 3 * PI / 4:
		return Direction.SOUTH
	elif angle >= 3 * PI / 4 and angle < 5 * PI / 4:
		return Direction.WEST
	elif angle >= 5 * PI / 4 and angle < 7 * PI / 4:
		return Direction.NORTH
	
	return Direction.NONE

func convert_to_sprite_direction(direction: int) -> int:
	"""Convert Direction enum to sprite system format"""
	match direction:
		Direction.NORTH:
			return 1
		Direction.EAST:
			return 2
		Direction.SOUTH:
			return 0
		Direction.WEST:
			return 3
		Direction.NORTHEAST:
			return 2
		Direction.SOUTHEAST:
			return 0
		Direction.SOUTHWEST:
			return 0
		Direction.NORTHWEST:
			return 3
		_:
			return 0
#endregion

#region HELPER FUNCTIONS
func world_to_tile(world_pos: Vector2) -> Vector2i:
	"""Convert world position to tile coordinates"""
	return Vector2i(int(world_pos.x / TILE_SIZE), int(world_pos.y / TILE_SIZE))

func tile_to_world(tile_pos: Vector2i) -> Vector2:
	"""Convert tile coordinates to world position"""
	return Vector2((tile_pos.x * TILE_SIZE) + (TILE_SIZE / 2.0), 
				   (tile_pos.y * TILE_SIZE) + (TILE_SIZE / 2.0))

func is_valid_tile(tile_pos: Vector2i) -> bool:
	"""Check if tile is valid"""
	if not world:
		return false
	
	var z_level = controller.current_z_level if controller else 0
	
	if world.has_method("is_in_zone"):
		return world.is_in_zone(tile_pos, z_level)
	
	var tile = world.get_tile_data(tile_pos, z_level)
	return tile != null

func is_wall_at(tile_pos: Vector2i, z_level: int) -> bool:
	"""Check if there's a wall at position"""
	if world and world.has_method("is_wall_at"):
		return world.is_wall_at(tile_pos, z_level)
	return false

func is_closed_door_at(tile_pos: Vector2i, z_level: int) -> bool:
	"""Check if there's a closed door at position"""
	if world and world.has_method("is_closed_door_at"):
		return world.is_closed_door_at(tile_pos, z_level)
	return false

func get_entity_tile_position(entity: Node) -> Vector2i:
	"""Get tile position of an entity"""
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

func is_adjacent_to(target: Node, allow_diagonal: bool = true) -> bool:
	"""Check if adjacent to target"""
	if not target:
		return false
	
	var my_pos = current_tile_position
	var target_pos = get_entity_tile_position(target)
	
	if my_pos == target_pos:
		return true
	
	var diff = target_pos - my_pos
	var distance = max(abs(diff.x), abs(diff.y))
	
	if distance > 1:
		return false
	
	if abs(diff.x) == 1 and abs(diff.y) == 1 and not allow_diagonal:
		return false
	
	return true

func check_tile_environment():
	"""Check environmental effects at current tile"""
	if not world:
		return
	
	var z_level = controller.current_z_level if controller else 0
	var tile_data = world.get_tile_data(current_tile_position, z_level)
	
	if not tile_data:
		return
	
	# Check for slippery floors
	if "slippery" in tile_data and tile_data.slippery:
		current_tile_friction = 0.2
		
		if not is_stunned and not is_floating and randf() < 0.4:
			slip(1.5)
	else:
		current_tile_friction = 1.0
	
	# Check for space
	if world.has_method("is_space") and world.is_space(current_tile_position, z_level):
		if not is_floating:
			set_gravity(false)
	elif is_floating:
		set_gravity(true)

func slip(duration: float):
	"""Apply slip effect"""
	if controller and controller.status_effect_component:
		controller.status_effect_component.apply_stun(duration)
	
	if sensory_system:
		sensory_system.display_message("You slip!")
	
	if audio_system:
		audio_system.play_positioned_sound("slip", controller.position, 0.6)

func emit_footstep_sound(volume_override: float = -1.0):
	"""Emit footstep sound"""
	var volume = 0.3
	if current_state == MovementState.RUNNING:
		volume = 0.5
	elif current_state == MovementState.CRAWLING:
		volume = 0.1
	
	if volume_override >= 0:
		volume = volume_override
	
	var floor_type = "floor"
	if world:
		var z_level = controller.current_z_level if controller else 0
		var tile_data = world.get_tile_data(current_tile_position, z_level)
		if tile_data and "floor_type" in tile_data:
			floor_type = tile_data.floor_type
	
	emit_signal("footstep", controller.position, floor_type)
	
	if audio_system:
		audio_system.play_positioned_sound("footstep", controller.position, volume, floor_type)

func get_current_tile_position() -> Vector2i:
	"""Get current tile position"""
	return current_tile_position

func get_current_direction() -> int:
	"""Get current facing direction"""
	return current_direction
#endregion
