extends Node
class_name AlienAI

const DETECTION_RANGE: float = 15.0
const STALKING_DISTANCE: float = 8.0
const CAUTIOUS_STALKING_DISTANCE: float = 12.0
const MIN_STALKING_DISTANCE: float = 3.0
const ATTACK_RANGE: float = 1.5
const INVESTIGATE_RANGE: float = 3.0
const REST_DURATION: float = 8.0
const PATROL_RADIUS: int = 6
const ATTACK_DAMAGE: float = 25.0
const LIMB_DAMAGE: float = 15.0
const DISCOVERY_TIME: float = 1.5
const MEMORY_TIME: float = 300.0
const DOOR_WAIT_TIME: float = 2.0
const DOOR_INTERACTION_RANGE: float = 1.2
const AMBUSH_WAIT_TIME: float = 5.0
const HEALING_THRESHOLD: float = 30.0
const CAPTURE_HEALTH_THRESHOLD: float = 40.0
const STATIONARY_TIME_THRESHOLD: float = 15.0

enum AIState {
	DORMANT,
	RESTING,
	PATROLLING,
	STALKING,
	INVESTIGATING,
	ATTACKING,
	RETREATING,
	WAITING_FOR_DOOR,
	AMBUSHING,
	CAPTURING,
	DRAGGING,
	HEALING,
	FLEEING
}

signal ai_state_changed(old_state: int, new_state: int)
signal prey_detected(prey: Node)
signal prey_captured(prey: Node)
signal alien_wounded(attacker: Node)

var controller: Node = null
var movement_component: Node = null
var world: Node = null
var tile_occupancy_system: Node = null
var audio_system: Node = null
var navigation_agent: NavigationAgent2D = null
var grab_component: Node = null
var health_system: Node = null

@export var current_state: int = AIState.DORMANT : set = _set_current_state
@export var ai_enabled: bool = true
@export var alien_id: String = ""

var tracked_entities: Dictionary = {}
var primary_target: Node = null
var nest_position: Vector2i = Vector2i.ZERO
var patrol_points: Array[Vector2i] = []
var current_patrol_index: int = 0
var base_patrol_radius: int = 6
var current_patrol_radius: int = 6
var max_patrol_radius: int = 20

var last_prey_position: Vector2i = Vector2i.ZERO
var last_prey_seen_time: float = 0.0
var investigate_position: Vector2i = Vector2i.ZERO
var ambush_position: Vector2i = Vector2i.ZERO

var state_timer: float = 0.0
var decision_timer: float = 0.0
var scan_timer: float = 0.0
var discovery_timer: float = 0.0
var door_wait_timer: float = 0.0
var ambush_timer: float = 0.0
var expansion_timer: float = 0.0
var stationary_check_timer: float = 0.0

var attacker_entity: Node = null
var wounded_aggression_multiplier: float = 1.0
var is_healing: bool = false
var dragged_entity: Node = null

var current_blocking_door: Node = null
var door_interaction_timer: float = 0.0
var last_known_prey_position: Vector2i = Vector2i.ZERO

var entity_last_positions: Dictionary = {}
var entity_stationary_times: Dictionary = {}

var stalking_position: Vector2i = Vector2i.ZERO
var stalking_timer: float = 0.0

func _set_current_state(value: int):
	var old_state = current_state
	current_state = value
	state_timer = 0.0
	
	if old_state != current_state:
		emit_signal("ai_state_changed", old_state, current_state)
		on_state_changed()

func initialize(init_data: Dictionary):
	controller = init_data.get("controller")
	world = init_data.get("world")
	tile_occupancy_system = init_data.get("tile_occupancy_system")
	audio_system = init_data.get("audio_system")
	
	if controller:
		movement_component = controller.get_node_or_null("MovementComponent")
		grab_component = controller.get_node_or_null("AlienGrabPullComponent")
		health_system = controller.get_node_or_null("AlienHealthSystem")
	
	setup_navigation()
	
	if movement_component:
		nest_position = movement_component.current_tile_position
		setup_initial_patrol_points()
	
	if alien_id.is_empty():
		alien_id = "alien_" + str(controller.get_instance_id())
	
	if health_system:
		health_system.damage_taken.connect(_on_damage_received)
	
	current_state = AIState.RESTING

func setup_navigation():
	navigation_agent = NavigationAgent2D.new()
	navigation_agent.radius = 16.0
	navigation_agent.neighbor_distance = 50.0
	navigation_agent.max_neighbors = 10
	navigation_agent.time_horizon = 1.5
	navigation_agent.max_speed = 200.0
	navigation_agent.path_desired_distance = 8.0
	navigation_agent.target_desired_distance = 16.0
	navigation_agent.path_max_distance = 500.0
	navigation_agent.avoidance_enabled = true
	navigation_agent.debug_enabled = true
	controller.add_child(navigation_agent)

func _process(delta: float):
	if not ai_enabled or not controller or not movement_component:
		return
	
	state_timer += delta
	decision_timer += delta
	scan_timer += delta
	last_prey_seen_time += delta
	door_wait_timer += delta
	door_interaction_timer += delta
	ambush_timer += delta
	expansion_timer += delta
	stationary_check_timer += delta
	stalking_timer += delta
	
	update_tracked_entities(delta)
	update_entity_stationary_status(delta)
	
	if scan_timer >= 1.0:
		scan_for_prey()
		scan_timer = 0.0
	
	if decision_timer >= get_decision_interval():
		make_decision()
		decision_timer = 0.0
	
	if expansion_timer >= 30.0:
		expand_patrol_area()
		expansion_timer = 0.0
	
	execute_current_state()

func get_decision_interval() -> float:
	match current_state:
		AIState.ATTACKING:
			return 0.6
		AIState.STALKING:
			return 1.0
		AIState.AMBUSHING:
			return 0.5
		AIState.FLEEING:
			return 0.8
		AIState.CAPTURING, AIState.DRAGGING:
			return 1.5
		AIState.INVESTIGATING:
			return 1.2
		AIState.WAITING_FOR_DOOR:
			return 0.5
		_:
			return 2.0

func update_tracked_entities(delta: float):
	var entities_to_remove = []
	
	for entity in tracked_entities.keys():
		if not is_instance_valid(entity):
			entities_to_remove.append(entity)
			continue
		
		tracked_entities[entity].last_seen_time += delta
		
		var entity_pos = get_entity_position(entity)
		if entity_pos != Vector2i(-1, -1):
			tracked_entities[entity].last_known_position = entity_pos
	
	for entity in entities_to_remove:
		tracked_entities.erase(entity)
		if entity == primary_target:
			primary_target = null

func update_entity_stationary_status(delta: float):
	if stationary_check_timer < 2.0:
		return
	
	stationary_check_timer = 0.0
	
	for entity in tracked_entities.keys():
		if not is_instance_valid(entity):
			continue
		
		var current_pos = get_entity_position(entity)
		if current_pos == Vector2i(-1, -1):
			continue
		
		if entity in entity_last_positions:
			if entity_last_positions[entity] == current_pos:
				if entity in entity_stationary_times:
					entity_stationary_times[entity] += 2.0
				else:
					entity_stationary_times[entity] = 2.0
			else:
				entity_stationary_times[entity] = 0.0
		
		entity_last_positions[entity] = current_pos

func expand_patrol_area():
	if tracked_entities.size() == 0 and current_state in [AIState.PATROLLING, AIState.RESTING]:
		current_patrol_radius = min(current_patrol_radius + 2, max_patrol_radius)
		setup_patrol_points()

func scan_for_prey():
	if not tile_occupancy_system:
		return
	
	var my_pos = movement_component.current_tile_position
	var best_prey = null
	var closest_distance = DETECTION_RANGE + 1.0
	
	for x in range(my_pos.x - int(DETECTION_RANGE), my_pos.x + int(DETECTION_RANGE) + 1):
		for y in range(my_pos.y - int(DETECTION_RANGE), my_pos.y + int(DETECTION_RANGE) + 1):
			var tile_pos = Vector2i(x, y)
			var distance = my_pos.distance_to(Vector2(tile_pos))
			
			if distance > DETECTION_RANGE or distance >= closest_distance:
				continue
			
			var entities = tile_occupancy_system.get_entities_at(tile_pos, controller.current_z_level)
			for entity in entities:
				if entity == controller or not is_valid_prey(entity):
					continue
				
				if has_line_of_sight(my_pos, tile_pos):
					best_prey = entity
					closest_distance = distance
					last_prey_position = tile_pos
					last_known_prey_position = tile_pos
					last_prey_seen_time = 0.0
					
					track_entity(entity, tile_pos)

	if best_prey and best_prey != primary_target:
		set_primary_target(best_prey)

func track_entity(entity: Node, position: Vector2i):
	if entity in tracked_entities:
		tracked_entities[entity].last_seen_time = 0.0
		tracked_entities[entity].last_known_position = position
	else:
		tracked_entities[entity] = {
			"last_seen_time": 0.0,
			"last_known_position": position,
			"discovery_time": Time.get_ticks_msec() / 1000.0,
			"threat_level": assess_entity_threat_level(entity)
		}
		emit_signal("prey_detected", entity)

func set_primary_target(entity: Node):
	primary_target = entity
	if current_state in [AIState.RESTING, AIState.PATROLLING]:
		current_state = AIState.STALKING

func assess_entity_threat_level(entity: Node) -> float:
	var threat_level = 1.0
	
	if entity.has_node("InventorySystem"):
		var inventory = entity.get_node("InventorySystem")
		if inventory.has_method("has_weapon_equipped") and inventory.has_weapon_equipped():
			threat_level += 2.0
		if inventory.has_method("get_equipped_items"):
			var items = inventory.get_equipped_items()
			threat_level += items.size() * 0.3
	
	if entity.has_node("HealthSystem"):
		var health_sys = entity.get_node("HealthSystem")
		if health_sys.health < health_sys.max_health * 0.5:
			threat_level *= 0.7
	
	return threat_level

func has_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	var line_points = bresenham_line(from, to)
	
	for point in line_points:
		if point == from:
			continue
		if world.is_wall_at(point, controller.current_z_level):
			return false
		
		if is_closed_door_at(point):
			return false
	
	return true

func is_closed_door_at(pos: Vector2i) -> bool:
	if not tile_occupancy_system:
		return false
	
	var entities = tile_occupancy_system.get_entities_at(pos, controller.current_z_level)
	for entity in entities:
		if entity.is_in_group("doors"):
			if entity.has_method("is_closed") and entity.is_closed():
				return true
			if entity.has_method("blocks_movement") and entity.blocks_movement():
				return true
	return false

func get_door_at(pos: Vector2i) -> Node:
	if not tile_occupancy_system:
		return null
	
	var entities = tile_occupancy_system.get_entities_at(pos, controller.current_z_level)
	for entity in entities:
		if entity.is_in_group("doors"):
			return entity
	return null

func bresenham_line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var x0 = from.x
	var y0 = from.y
	var x1 = to.x
	var y1 = to.y
	
	var dx = abs(x1 - x0)
	var dy = abs(y1 - y0)
	var sx = 1 if x0 < x1 else -1
	var sy = 1 if y0 < y1 else -1
	var err = dx - dy
	
	while true:
		points.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		
		var e2 = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy
	
	return points

func is_valid_prey(entity: Node) -> bool:
	if not entity or not is_instance_valid(entity):
		return false
	
	return entity.is_in_group("players") or entity.is_in_group("humans")

func make_decision():
	update_healing_status()
	
	if should_heal():
		current_state = AIState.HEALING
		return
	
	if should_capture_stationary_entity():
		return
	
	if should_prioritize_attacker():
		primary_target = attacker_entity
		current_state = AIState.STALKING
		return
	
	match current_state:
		AIState.RESTING:
			if state_timer > REST_DURATION:
				current_state = AIState.PATROLLING
		
		AIState.PATROLLING:
			if primary_target and is_instance_valid(primary_target):
				current_state = AIState.STALKING
		
		AIState.STALKING:
			handle_stalking_decisions()
		
		AIState.INVESTIGATING:
			handle_investigating_decisions()
		
		AIState.ATTACKING:
			handle_attacking_decisions()
		
		AIState.AMBUSHING:
			handle_ambushing_decisions()
		
		AIState.CAPTURING:
			handle_capturing_decisions()
		
		AIState.DRAGGING:
			handle_dragging_decisions()
		
		AIState.FLEEING:
			handle_fleeing_decisions()
		
		AIState.HEALING:
			handle_healing_decisions()
		
		AIState.WAITING_FOR_DOOR:
			if door_wait_timer > DOOR_WAIT_TIME:
				if current_blocking_door and current_blocking_door.has_method("is_open") and current_blocking_door.is_open():
					current_state = AIState.STALKING if primary_target else AIState.PATROLLING
				else:
					current_state = AIState.PATROLLING
					current_blocking_door = null

func should_heal() -> bool:
	if not health_system:
		return false
	
	return health_system.health < HEALING_THRESHOLD and current_state != AIState.HEALING

func should_capture_stationary_entity() -> bool:
	for entity in entity_stationary_times.keys():
		if entity_stationary_times[entity] >= STATIONARY_TIME_THRESHOLD and is_instance_valid(entity):
			primary_target = entity
			current_state = AIState.CAPTURING
			return true
	return false

func should_prioritize_attacker() -> bool:
	return attacker_entity != null and is_instance_valid(attacker_entity) and wounded_aggression_multiplier > 1.0

func handle_stalking_decisions():
	if not primary_target or not is_instance_valid(primary_target):
		find_new_target()
		return
	
	var target_pos = get_entity_position(primary_target)
	if target_pos == Vector2i(-1, -1):
		current_state = AIState.INVESTIGATING
		investigate_position = last_known_prey_position
		return
	
	var distance = get_distance_to_target(primary_target)
	
	if distance <= ATTACK_RANGE:
		current_state = AIState.CAPTURING

func handle_investigating_decisions():
	if primary_target and is_instance_valid(primary_target):
		var target_pos = get_entity_position(primary_target)
		if target_pos != Vector2i(-1, -1):
			current_state = AIState.STALKING
			return
	
	if state_timer > 20.0:
		current_state = AIState.PATROLLING

func handle_attacking_decisions():
	if not primary_target or not is_instance_valid(primary_target):
		current_state = AIState.PATROLLING
		return
	
	var distance = get_distance_to_target(primary_target)
	if distance > ATTACK_RANGE * 2:
		current_state = AIState.STALKING
	elif state_timer > 10.0:
		current_state = AIState.STALKING

func handle_ambushing_decisions():
	if ambush_timer > AMBUSH_WAIT_TIME:
		if primary_target and is_instance_valid(primary_target):
			var distance = get_distance_to_target(primary_target)
			if distance <= ATTACK_RANGE * 1.5:
				current_state = AIState.ATTACKING
			else:
				current_state = AIState.STALKING
		else:
			current_state = AIState.PATROLLING

func handle_capturing_decisions():
	if not primary_target or not is_instance_valid(primary_target):
		current_state = AIState.PATROLLING
		return
	
	# Check if we successfully grabbed the entity
	if grab_component:
		var is_alien_carrying = false
		
		# Check AlienGrabPullComponent specific carrying state
		if grab_component.has_method("get") and grab_component.get("alien_carry_state") != null:
			is_alien_carrying = grab_component.alien_carry_state != 0  # NOT_CARRYING = 0
		
		# Also check general grabbing state
		var is_grabbing = grab_component.has_method("is_grabbing") and grab_component.is_grabbing()
		
		if is_alien_carrying or is_grabbing:
			print("Alien successfully grabbed prey, transitioning to DRAGGING state")
			current_state = AIState.DRAGGING
			dragged_entity = primary_target
			return
	
	# If we're here, we haven't grabbed yet - try to grab
	var distance = get_distance_to_target(primary_target)
	if distance <= ATTACK_RANGE:
		attempt_capture()

func handle_dragging_decisions():
	if not dragged_entity or not is_instance_valid(dragged_entity):
		print("Lost dragged entity, returning to patrol")
		current_state = AIState.PATROLLING
		dragged_entity = null
		return
	
	# Check if we're still carrying the entity
	if grab_component:
		var is_alien_carrying = false
		
		if grab_component.has_method("get") and grab_component.get("alien_carry_state") != null:
			is_alien_carrying = grab_component.alien_carry_state != 0
		
		var is_grabbing = grab_component.has_method("is_grabbing") and grab_component.is_grabbing()
		
		if not is_alien_carrying and not is_grabbing:
			print("No longer carrying entity, returning to patrol")
			current_state = AIState.PATROLLING
			dragged_entity = null
			return
	
	var my_pos = movement_component.current_tile_position
	var nest_distance = my_pos.distance_to(Vector2(nest_position))
	
	# If we're at the nest, drop the entity
	if nest_distance <= 2.0:
		print("Reached nest, dropping prey")
		if grab_component and grab_component.has_method("release_grab"):
			grab_component.release_grab()
		if grab_component and grab_component.has_method("stop_alien_carry"):
			grab_component.stop_alien_carry()
		
		dragged_entity = null
		emit_signal("prey_captured", primary_target)
		primary_target = null
		current_state = AIState.RESTING
	else:
		# Move towards nest
		move_toward_target_position(nest_position)

func handle_fleeing_decisions():
	if not primary_target or not is_instance_valid(primary_target):
		current_state = AIState.PATROLLING
		return
	
	var distance = get_distance_to_target(primary_target)
	if distance > STALKING_DISTANCE:
		current_state = AIState.STALKING

func handle_healing_decisions():
	var my_pos = movement_component.current_tile_position
	var nest_distance = my_pos.distance_to(Vector2(nest_position))
	
	if nest_distance > 2.0:
		move_toward_target_position(nest_position)
	else:
		if health_system and health_system.health >= health_system.max_health * 0.8:
			is_healing = false
			current_state = AIState.RESTING

func find_new_target():
	primary_target = null
	
	for entity in tracked_entities.keys():
		if is_instance_valid(entity):
			primary_target = entity
			break
	
	if not primary_target:
		current_state = AIState.PATROLLING

func execute_current_state():
	match current_state:
		AIState.RESTING:
			rest_behavior()
		AIState.PATROLLING:
			patrol_behavior()
		AIState.STALKING:
			stalk_behavior()
		AIState.INVESTIGATING:
			investigate_behavior()
		AIState.ATTACKING:
			attack_behavior()
		AIState.AMBUSHING:
			ambush_behavior()
		AIState.CAPTURING:
			capture_behavior()
		AIState.DRAGGING:
			drag_behavior()
		AIState.FLEEING:
			flee_behavior()
		AIState.HEALING:
			healing_behavior()
		AIState.WAITING_FOR_DOOR:
			wait_for_door_behavior()

func rest_behavior():
	pass

func patrol_behavior():
	if patrol_points.is_empty():
		setup_patrol_points()
		return
	
	var my_pos = movement_component.current_tile_position
	var target = patrol_points[current_patrol_index]
	
	if my_pos.distance_to(Vector2(target)) < 2.0:
		current_patrol_index = (current_patrol_index + 1) % patrol_points.size()
		target = patrol_points[current_patrol_index]
	
	move_toward_target_position(target)

func stalk_behavior():
	if not primary_target or not is_instance_valid(primary_target):
		return
	
	var prey_pos = get_entity_position(primary_target)
	if prey_pos == Vector2i(-1, -1):
		current_state = AIState.INVESTIGATING
		investigate_position = last_known_prey_position
		return
	
	var my_pos = movement_component.current_tile_position
	var distance = my_pos.distance_to(Vector2(prey_pos))
	
	if distance <= ATTACK_RANGE:
		move_toward_target_position(prey_pos)
	elif distance > STALKING_DISTANCE * 2:
		move_toward_target_position(prey_pos)
	else:
		if stalking_timer > 3.0 or stalking_position == Vector2i.ZERO:
			find_stalking_position(prey_pos)
			stalking_timer = 0.0
		
		if stalking_position != Vector2i.ZERO:
			move_toward_target_position(stalking_position)

func find_stalking_position(prey_pos: Vector2i):
	var my_pos = movement_component.current_tile_position
	var directions = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)
	]
	
	var best_position = Vector2i.ZERO
	var best_score = -1.0
	
	for dir in directions:
		for distance in range(3, 8):
			var test_pos = prey_pos + dir * distance
			
			if not is_position_valid(test_pos) or world.is_wall_at(test_pos, controller.current_z_level):
				continue
			
			var cover_score = 0.0
			
			for check_dir in directions:
				var check_pos = test_pos + check_dir
				if world.is_wall_at(check_pos, controller.current_z_level):
					cover_score += 1.0
			
			var distance_to_prey = test_pos.distance_to(Vector2(prey_pos))
			if distance_to_prey < MIN_STALKING_DISTANCE or distance_to_prey > STALKING_DISTANCE:
				continue
			
			var los_blocked = not has_line_of_sight(test_pos, prey_pos)
			if los_blocked:
				cover_score += 2.0
			
			var distance_from_current = my_pos.distance_to(Vector2(test_pos))
			cover_score -= distance_from_current * 0.1
			
			if cover_score > best_score:
				best_score = cover_score
				best_position = test_pos
	
	if best_position != Vector2i.ZERO:
		stalking_position = best_position
	else:
		stalking_position = prey_pos + Vector2i(2, 0)

func investigate_behavior():
	if investigate_position == Vector2i.ZERO:
		return
	
	var my_pos = movement_component.current_tile_position
	var distance = my_pos.distance_to(Vector2(investigate_position))
	
	if distance > INVESTIGATE_RANGE:
		move_toward_target_position(investigate_position)
	else:
		circle_around_position(investigate_position, INVESTIGATE_RANGE)

func attack_behavior():
	if not primary_target or not is_instance_valid(primary_target):
		return
	
	var distance = get_distance_to_target(primary_target)
	if distance <= ATTACK_RANGE:
		if state_timer >= 0.8:
			perform_attack()
			state_timer = 0.0
	else:
		move_toward_target_position(get_entity_position(primary_target))

func ambush_behavior():
	if ambush_position == Vector2i.ZERO:
		return
	
	var my_pos = movement_component.current_tile_position
	var distance = my_pos.distance_to(Vector2(ambush_position))
	
	if distance > 1.0:
		move_toward_target_position(ambush_position)

func capture_behavior():
	if not primary_target or not is_instance_valid(primary_target):
		return
	var is_grabbing = grab_component.is_grabbing()
	var distance = get_distance_to_target(primary_target)
	if distance <= ATTACK_RANGE:
		attempt_capture()
	elif not is_grabbing:
		move_toward_target_position(get_entity_position(primary_target))
	else:
		move_toward_target_position(nest_position)

func drag_behavior():
	if not dragged_entity or not is_instance_valid(dragged_entity):
		return
	
	move_toward_target_position(nest_position)

func flee_behavior():
	if not primary_target or not is_instance_valid(primary_target):
		return
	
	var prey_pos = get_entity_position(primary_target)
	move_away_from_position(prey_pos)

func healing_behavior():
	move_toward_target_position(nest_position)

func wait_for_door_behavior():
	if current_blocking_door and door_interaction_timer > 1.0:
		if current_blocking_door.has_method("interact"):
			current_blocking_door.interact(controller)
			door_interaction_timer = 0.0

func perform_attack():
	if not primary_target or not is_instance_valid(primary_target):
		return
	
	if controller.has_method("handle_primary_attack"):
		controller.handle_primary_attack()
	
	if primary_target.has_method("take_damage"):
		primary_target.take_damage(ATTACK_DAMAGE, "brute")
	
	if audio_system:
		audio_system.play_positioned_sound("alien_attack", controller.position, 0.8)

func attempt_capture():
	if not grab_component or not primary_target:
		return
	
	print("Attempting to capture prey...")
	
	if grab_component:
		grab_component.handle_grab_prey()
	
	# After grabbing, try to start carrying if grab was successful
	if grab_component:
		grab_component.handle_carry_prey()
		_set_current_state(11)

func move_toward_target_position(target: Vector2i):
	if not navigation_agent:
		return
	
	var world_target = world.tile_to_world(Vector2(target))
	navigation_agent.target_position = world_target
	
	if navigation_agent.is_navigation_finished():
		return
	
	var next_position = navigation_agent.get_next_path_position()
	var current_pos = controller.global_position
	var direction = (next_position - current_pos).normalized()
	
	if movement_component.has_method("attempt_move"):
		var tile_direction = Vector2i(round(direction.x), round(direction.y))
		if tile_direction != Vector2i.ZERO:
			movement_component.attempt_move(tile_direction)

func move_away_from_position(avoid_pos: Vector2i):
	var my_pos = movement_component.current_tile_position
	var away_direction = my_pos - avoid_pos
	
	var direction = Vector2i.ZERO
	if abs(away_direction.x) > abs(away_direction.y):
		direction.x = 1 if away_direction.x > 0 else -1
	else:
		direction.y = 1 if away_direction.y > 0 else -1
	
	if movement_component.has_method("attempt_move"):
		movement_component.attempt_move(direction)

func circle_around_position(center: Vector2i, radius: float):
	var my_pos = movement_component.current_tile_position
	var angle = state_timer * 0.5
	
	var target_x = center.x + int(cos(angle) * radius)
	var target_y = center.y + int(sin(angle) * radius)
	var target = Vector2i(target_x, target_y)
	
	move_toward_target_position(target)

func is_position_valid(pos: Vector2i) -> bool:
	if not world:
		return true
	
	return world.is_valid_tile(pos, controller.current_z_level)

func get_distance_to_target(target: Node) -> float:
	if not target:
		return 999.0
	
	var my_pos = movement_component.current_tile_position
	var target_pos = get_entity_position(target)
	return my_pos.distance_to(Vector2(target_pos))

func get_entity_position(entity: Node) -> Vector2i:
	if not entity or not is_instance_valid(entity):
		return Vector2i(-1, -1)
	
	if "current_tile_position" in entity:
		return entity.current_tile_position
	elif entity.has_method("get_current_tile_position"):
		return entity.get_current_tile_position()
	elif entity.has_node("MovementComponent"):
		var movement = entity.get_node("MovementComponent")
		if "current_tile_position" in movement:
			return movement.current_tile_position
	
	return Vector2i(-1, -1)

func setup_initial_patrol_points():
	current_patrol_radius = base_patrol_radius
	setup_patrol_points()

func setup_patrol_points():
	patrol_points.clear()
	
	var angles = [0, PI/2, PI, 3*PI/2, PI/4, 3*PI/4, 5*PI/4, 7*PI/4]
	for angle in angles:
		var offset = Vector2(cos(angle), sin(angle)) * current_patrol_radius
		var point = nest_position + Vector2i(int(offset.x), int(offset.y))
		
		if is_position_valid(point):
			patrol_points.append(point)
	
	if patrol_points.is_empty():
		patrol_points.append(nest_position)

func update_healing_status():
	if not health_system:
		return
	
	if is_healing and health_system.health >= health_system.max_health * 0.9:
		is_healing = false

func _on_damage_received(amount: float, damage_type: int, zone: String, source):
	if source and is_instance_valid(source) and source != controller:
		attacker_entity = source
		wounded_aggression_multiplier = min(3.0, wounded_aggression_multiplier + 0.5)
		
		if source not in tracked_entities:
			track_entity(source, get_entity_position(source))
		
		emit_signal("alien_wounded", source)

func on_state_changed():
	match current_state:
		AIState.INVESTIGATING:
			if investigate_position == Vector2i.ZERO:
				investigate_position = last_known_prey_position
		AIState.ATTACKING:
			discovery_timer = 0.0
		AIState.WAITING_FOR_DOOR:
			door_wait_timer = 0.0
			door_interaction_timer = 0.0
		AIState.AMBUSHING:
			ambush_timer = 0.0
		AIState.HEALING:
			is_healing = true
		AIState.STALKING:
			stalking_position = Vector2i.ZERO
			stalking_timer = 0.0

func set_ai_enabled(enabled: bool):
	ai_enabled = enabled
	if enabled and current_state == AIState.DORMANT:
		current_state = AIState.RESTING

func get_state_name(state: int) -> String:
	match state:
		AIState.DORMANT: return "Dormant"
		AIState.RESTING: return "Resting"
		AIState.PATROLLING: return "Patrolling"
		AIState.STALKING: return "Stalking"
		AIState.INVESTIGATING: return "Investigating"
		AIState.ATTACKING: return "Attacking"
		AIState.AMBUSHING: return "Ambushing"
		AIState.CAPTURING: return "Capturing"
		AIState.DRAGGING: return "Dragging"
		AIState.FLEEING: return "Fleeing"
		AIState.HEALING: return "Healing"
		AIState.WAITING_FOR_DOOR: return "Waiting for Door"
		_: return "Unknown"

func get_debug_info() -> Dictionary:
	return {
		"alien_id": alien_id,
		"state": get_state_name(current_state),
		"primary_target": primary_target.name if primary_target else "None",
		"tracked_entities": tracked_entities.size(),
		"patrol_radius": current_patrol_radius,
		"wounded_aggression": wounded_aggression_multiplier,
		"is_healing": is_healing,
		"attacker": attacker_entity.name if attacker_entity else "None",
		"position": movement_component.current_tile_position if movement_component else Vector2i.ZERO,
		"navigation_target": navigation_agent.target_position if navigation_agent else Vector2.ZERO
	}
