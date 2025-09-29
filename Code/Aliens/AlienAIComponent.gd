extends Node
class_name AlienAIComponent

# =============================================================================
# CONFIGURATION
# =============================================================================

@export_group("AI Settings")
@export var ai_enabled: bool = true
@export var detection_range: float = 8.0
@export var attack_range: float = 1.5
@export var memory_duration: float = 8.0

@export_group("Performance")
@export var target_scan_interval: float = 0.4
@export var line_of_sight_check_interval: float = 0.2
@export var attack_cooldown: float = 1.0

@export_group("Behavior")
@export var lose_target_distance: float = 12.0
@export var dodge_chance: float = 0.3
@export var wander_chance: float = 0.1

# =============================================================================
# STATES
# =============================================================================

enum State {
	IDLE,
	HUNTING_DIRECT,      # Can see target, moving directly
	HUNTING_PATHFIND,    # Target blocked, using pathfinding
	ATTACKING,
	SEARCHING,           # Looking for target at memory location
	WANDERING
}

# =============================================================================
# CORE DATA
# =============================================================================

var controller: Node
var movement_component: Node
var world: Node
var tile_occupancy_system: Node
var interaction_component: Node

var current_state: State = State.IDLE
var current_target: Node = null

# Memory system
var last_known_target_position: Vector2i = Vector2i.ZERO
var memory_timer: float = 0.0
var has_memory: bool = false

# Line of sight and pathfinding
var path_to_target: Array[Vector2i] = []
var path_index: int = 0
var has_clear_line_of_sight: bool = false

# Timers
var scan_timer: float = 0.0
var los_check_timer: float = 0.0
var attack_timer: float = 0.0
var memory_update_timer: float = 0.0

# Signals
signal target_acquired(target: Node)
signal target_lost()
signal attack_attempted(target: Node)

# =============================================================================
# INITIALIZATION
# =============================================================================

func initialize(init_data: Dictionary):
	controller = init_data.get("controller")
	world = init_data.get("world")
	tile_occupancy_system = init_data.get("tile_occupancy_system")
	
	if controller:
		movement_component = controller.get_node_or_null("MovementComponent")
		interaction_component = controller.get_node_or_null("InteractionComponent")

func _ready():
	set_process(ai_enabled)

# =============================================================================
# MAIN LOOP
# =============================================================================

func _process(delta: float):
	if not ai_enabled or not movement_component:
		return
	
	scan_timer += delta
	los_check_timer += delta
	attack_timer += delta
	memory_timer += delta
	memory_update_timer += delta
	
	# Update memory
	if memory_update_timer >= 0.6:
		memory_update_timer = 0.0
		_update_memory()
	
	# Scan for targets
	if scan_timer >= target_scan_interval:
		scan_timer = 0.0
		_scan_for_targets()
	
	# Check line of sight for current target
	if current_target and los_check_timer >= line_of_sight_check_interval:
		los_check_timer = 0.0
		_check_line_of_sight_to_target()
	
	# Handle movement
	_handle_movement()
	
	# Handle combat
	_handle_combat()

# =============================================================================
# LINE OF SIGHT SYSTEM
# =============================================================================

func _check_line_of_sight_to_target():
	if not current_target or not is_instance_valid(current_target):
		return
	
	var my_pos = _get_my_position()
	var target_pos = _get_entity_position(current_target)
	
	has_clear_line_of_sight = _has_clear_line_of_sight(my_pos, target_pos)
	
	# Switch between direct hunting and pathfinding based on line of sight
	if current_state == State.HUNTING_DIRECT and not has_clear_line_of_sight:
		current_state = State.HUNTING_PATHFIND
		_calculate_simple_path(target_pos)
	elif current_state == State.HUNTING_PATHFIND and has_clear_line_of_sight:
		current_state = State.HUNTING_DIRECT
		path_to_target.clear()

func _has_clear_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	var tiles_in_line = _get_tiles_in_line(from, to)
	
	# Skip the starting tile
	if tiles_in_line.size() > 1:
		tiles_in_line.remove_at(0)
	
	for tile in tiles_in_line:
		if _is_tile_blocking_sight(tile):
			return false
	
	return true

func _get_tiles_in_line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var dx = abs(to.x - from.x)
	var dy = abs(to.y - from.y)
	var sx = 1 if from.x < to.x else -1
	var sy = 1 if from.y < to.y else -1
	var err = dx - dy
	
	var current = from
	
	while true:
		tiles.append(current)
		
		if current == to:
			break
		
		var e2 = 2 * err
		if e2 > -dy:
			err -= dy
			current.x += sx
		if e2 < dx:
			err += dx
			current.y += sy
	
	return tiles

func _is_tile_blocking_sight(tile: Vector2i) -> bool:
	if not world:
		return false
	
	return world.is_wall_at(tile, _get_z_level())

# =============================================================================
# MOVEMENT SYSTEM
# =============================================================================

func _handle_movement():
	if _is_currently_moving():
		return
	
	match current_state:
		State.HUNTING_DIRECT:
			_move_direct_to_target()
		State.HUNTING_PATHFIND:
			_follow_path_to_target()
		State.ATTACKING:
			_handle_attack_movement()
		State.SEARCHING:
			_move_to_memory_location()
		State.WANDERING:
			_move_randomly()
		State.IDLE:
			_maybe_start_wandering()

func _move_direct_to_target():
	if not current_target or not is_instance_valid(current_target):
		_lose_target()
		return
	
	var my_pos = _get_my_position()
	var target_pos = _get_entity_position(current_target)
	
	# Check distance
	if _distance(my_pos, target_pos) > lose_target_distance:
		_lose_target()
		return
	
	# Check if in attack range
	if _distance(my_pos, target_pos) <= attack_range:
		current_state = State.ATTACKING
		return
	
	# Calculate direction - only cardinal movement
	var direction = target_pos - my_pos
	var move_dir = Vector2i.ZERO
	
	# Choose either horizontal or vertical movement (prioritize larger distance)
	if abs(direction.x) >= abs(direction.y):
		# Move horizontally
		move_dir = Vector2i(clamp(direction.x, -1, 1), 0)
	else:
		# Move vertically
		move_dir = Vector2i(0, clamp(direction.y, -1, 1))
	
	# Try the chosen direction
	if _try_move(move_dir):
		return
	
	# If that direction is blocked, try the other axis
	if abs(direction.x) >= abs(direction.y):
		# Try vertical instead
		move_dir = Vector2i(0, clamp(direction.y, -1, 1))
	else:
		# Try horizontal instead
		move_dir = Vector2i(clamp(direction.x, -1, 1), 0)
	
	if _try_move(move_dir):
		return
	
	# If both cardinal movements fail, switch to pathfinding
	has_clear_line_of_sight = false
	current_state = State.HUNTING_PATHFIND
	_calculate_simple_path(target_pos)

func _follow_path_to_target():
	if path_to_target.is_empty():
		if current_target:
			_calculate_simple_path(_get_entity_position(current_target))
		return
	
	if path_index >= path_to_target.size():
		path_to_target.clear()
		path_index = 0
		return
	
	var my_pos = _get_my_position()
	var next_tile = path_to_target[path_index]
	
	# If we reached the current waypoint, advance
	if my_pos == next_tile:
		path_index += 1
		if path_index >= path_to_target.size():
			path_to_target.clear()
			path_index = 0
		return
	
	# Move toward next waypoint - only cardinal movement
	var direction = next_tile - my_pos
	var move_dir = Vector2i.ZERO
	
	# Choose either horizontal or vertical movement
	if abs(direction.x) >= abs(direction.y):
		move_dir = Vector2i(clamp(direction.x, -1, 1), 0)
	else:
		move_dir = Vector2i(0, clamp(direction.y, -1, 1))
	
	if not _try_move(move_dir):
		# Try the other axis if first choice fails
		if abs(direction.x) >= abs(direction.y):
			move_dir = Vector2i(0, clamp(direction.y, -1, 1))
		else:
			move_dir = Vector2i(clamp(direction.x, -1, 1), 0)
		
		if not _try_move(move_dir):
			# Path blocked, recalculate
			path_to_target.clear()
			path_index = 0

func _handle_attack_movement():
	if not current_target:
		current_state = State.IDLE
		return
	
	var my_pos = _get_my_position()
	var target_pos = _get_entity_position(current_target)
	var distance = _distance(my_pos, target_pos)
	
	# If target moved away, resume hunting
	if distance > attack_range * 1.5:
		if has_clear_line_of_sight:
			current_state = State.HUNTING_DIRECT
		else:
			current_state = State.HUNTING_PATHFIND
		return
	
	# Simple dodge after attack - only cardinal movement
	if attack_timer >= attack_cooldown and randf() < dodge_chance:
		var away_dir = my_pos - target_pos
		if away_dir != Vector2i.ZERO:
			# Choose either horizontal or vertical dodge
			var dodge_dir = Vector2i.ZERO
			if abs(away_dir.x) >= abs(away_dir.y):
				dodge_dir = Vector2i(clamp(away_dir.x, -1, 1), 0)
			else:
				dodge_dir = Vector2i(0, clamp(away_dir.y, -1, 1))
			_try_move(dodge_dir)

func _move_to_memory_location():
	if not has_memory:
		current_state = State.IDLE
		return
	
	if memory_timer >= memory_duration:
		_clear_memory()
		return
	
	var my_pos = _get_my_position()
	if my_pos == last_known_target_position:
		_clear_memory()
		return
	
	# Move toward memory location - only cardinal movement
	var direction = last_known_target_position - my_pos
	var move_dir = Vector2i.ZERO
	
	# Choose either horizontal or vertical movement
	if abs(direction.x) >= abs(direction.y):
		move_dir = Vector2i(clamp(direction.x, -1, 1), 0)
	else:
		move_dir = Vector2i(0, clamp(direction.y, -1, 1))
	
	_try_move(move_dir)

func _move_randomly():
	var directions = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	directions.shuffle()
	
	for direction in directions:
		if _try_move(direction):
			break
	
	if randf() < 0.3:
		current_state = State.IDLE

func _maybe_start_wandering():
	if randf() < wander_chance:
		current_state = State.WANDERING

# =============================================================================
# SIMPLE PATHFINDING (ONLY WHEN NEEDED)
# =============================================================================

func _calculate_simple_path(target_pos: Vector2i):
	var my_pos = _get_my_position()
	path_to_target = _find_simple_path(my_pos, target_pos)
	path_index = 0

func _find_simple_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	# Simple A* for when line of sight is blocked
	var open_set: Array[Vector2i] = [start]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0}
	var f_score: Dictionary = {start: _heuristic(start, goal)}
	
	var max_iterations = 100  # Keep it simple and fast
	var iterations = 0
	
	while open_set.size() > 0 and iterations < max_iterations:
		iterations += 1
		
		var current = _get_lowest_f_score(open_set, f_score)
		
		if current == goal:
			return _reconstruct_simple_path(came_from, current)
		
		open_set.erase(current)
		
		for neighbor in _get_cardinal_neighbors(current):
			if not _is_walkable(neighbor):
				continue
			
			var tentative_g = g_score.get(current, INF) + 1
			
			if tentative_g < g_score.get(neighbor, INF):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + _heuristic(neighbor, goal)
				
				if neighbor not in open_set:
					open_set.append(neighbor)
	
	return []

func _get_cardinal_neighbors(pos: Vector2i) -> Array[Vector2i]:
	return [
		Vector2i(pos.x + 1, pos.y),
		Vector2i(pos.x - 1, pos.y),
		Vector2i(pos.x, pos.y + 1),
		Vector2i(pos.x, pos.y - 1)
	]

func _get_lowest_f_score(open_set: Array[Vector2i], f_score: Dictionary) -> Vector2i:
	var lowest = open_set[0]
	var lowest_score = f_score.get(lowest, INF)
	
	for node in open_set:
		var score = f_score.get(node, INF)
		if score < lowest_score:
			lowest_score = score
			lowest = node
	
	return lowest

func _reconstruct_simple_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	
	while current in came_from:
		path.push_front(current)
		current = came_from[current]
	
	return path

func _heuristic(a: Vector2i, b: Vector2i) -> float:
	return abs(a.x - b.x) + abs(a.y - b.y)

# =============================================================================
# TARGET MANAGEMENT
# =============================================================================

func _scan_for_targets():
	if current_target and is_instance_valid(current_target):
		_update_target_memory()
		return
	
	var new_target = _find_nearest_target()
	if new_target:
		_acquire_target(new_target)
	elif has_memory and current_state == State.IDLE:
		current_state = State.SEARCHING

func _find_nearest_target() -> Node:
	if not tile_occupancy_system:
		return null
	
	var my_pos = _get_my_position()
	var best_target: Node = null
	var best_distance: float = detection_range + 1.0
	
	var radius = int(detection_range)
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			var check_pos = Vector2i(my_pos.x + x, my_pos.y + y)
			var distance = _distance(my_pos, check_pos)
			
			if distance > detection_range or distance >= best_distance:
				continue
			
			var entities = tile_occupancy_system.get_entities_at(check_pos, _get_z_level())
			for entity in entities:
				if _is_valid_target(entity):
					best_target = entity
					best_distance = distance
	
	return best_target

func _is_valid_target(entity: Node) -> bool:
	if not entity or not is_instance_valid(entity) or entity == controller:
		return false
	
	return entity.is_in_group("players") or entity.is_in_group("humans")

func _acquire_target(target: Node):
	current_target = target
	
	# Immediately check line of sight to determine hunting mode
	var my_pos = _get_my_position()
	var target_pos = _get_entity_position(target)
	has_clear_line_of_sight = _has_clear_line_of_sight(my_pos, target_pos)
	
	if has_clear_line_of_sight:
		current_state = State.HUNTING_DIRECT
	else:
		current_state = State.HUNTING_PATHFIND
		_calculate_simple_path(target_pos)
	
	_update_target_memory()
	emit_signal("target_acquired", target)

func _lose_target():
	current_target = null
	path_to_target.clear()
	path_index = 0
	
	if has_memory:
		current_state = State.SEARCHING
	else:
		current_state = State.IDLE
	
	emit_signal("target_lost")

# =============================================================================
# MEMORY SYSTEM
# =============================================================================

func _update_memory():
	if current_target and is_instance_valid(current_target):
		_update_target_memory()
	elif has_memory:
		memory_timer += memory_update_timer
		if memory_timer >= memory_duration:
			_clear_memory()

func _update_target_memory():
	if current_target and is_instance_valid(current_target):
		last_known_target_position = _get_entity_position(current_target)
		has_memory = true
		memory_timer = 0.0

func _clear_memory():
	has_memory = false
	memory_timer = 0.0
	if current_state == State.SEARCHING:
		current_state = State.IDLE

# =============================================================================
# COMBAT
# =============================================================================

func _handle_combat():
	if current_state != State.ATTACKING or attack_timer < attack_cooldown:
		return
	
	if not current_target or not is_instance_valid(current_target):
		return
	
	var distance = _distance(_get_my_position(), _get_entity_position(current_target))
	if distance <= attack_range:
		_execute_attack()
		attack_timer = 0.0

func _execute_attack():
	emit_signal("attack_attempted", current_target)
	
	if interaction_component and interaction_component.has_method("_handle_harm_interaction"):
		interaction_component._handle_harm_interaction(current_target, null)
	elif controller and controller.has_method("attack_target"):
		controller.attack_target(current_target)

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

func _try_move(direction: Vector2i) -> bool:
	if direction == Vector2i.ZERO:
		return false
	
	var target_tile = _get_my_position() + direction
	
	if not _is_walkable(target_tile):
		return false
	
	if movement_component.has_method("attempt_move"):
		return movement_component.attempt_move(direction)
	
	return false

func _is_currently_moving() -> bool:
	if not movement_component:
		return false
	
	if movement_component.has_method("is_moving"):
		return movement_component.is_moving()
	elif "is_moving" in movement_component:
		return movement_component.is_moving
	
	return false

func _is_walkable(pos: Vector2i) -> bool:
	if not world:
		return false
	
	var z_level = _get_z_level()
	
	if not world.is_valid_tile(pos, z_level):
		return false
	
	if world.is_wall_at(pos, z_level):
		return false
	
	if tile_occupancy_system and tile_occupancy_system.has_dense_entity_at(pos, z_level):
		var entities = tile_occupancy_system.get_entities_at(pos, z_level)
		for entity in entities:
			if entity == current_target or entity == controller:
				continue
			if "entity_dense" in entity and entity.entity_dense:
				return false
	
	return true

func _get_my_position() -> Vector2i:
	if movement_component and "current_tile_position" in movement_component:
		return movement_component.current_tile_position
	elif controller and "position" in controller:
		return Vector2i(int(controller.position.x / 32), int(controller.position.y / 32))
	return Vector2i.ZERO

func _get_entity_position(entity: Node) -> Vector2i:
	if not entity:
		return Vector2i.ZERO
	
	if "current_tile_position" in entity:
		return entity.current_tile_position
	elif "position" in entity:
		return Vector2i(int(entity.position.x / 32), int(entity.position.y / 32))
	
	return Vector2i.ZERO

func _get_z_level() -> int:
	if controller and "current_z_level" in controller:
		return controller.current_z_level
	return 0

func _distance(a: Vector2i, b: Vector2i) -> float:
	return abs(a.x - b.x) + abs(a.y - b.y)

# =============================================================================
# PUBLIC INTERFACE
# =============================================================================

func enable_ai():
	ai_enabled = true
	set_process(true)

func disable_ai():
	ai_enabled = false
	set_process(false)
	current_target = null
	current_state = State.IDLE
	_clear_memory()

func is_ai_enabled() -> bool:
	return ai_enabled

func get_current_state() -> State:
	return current_state

func get_current_target() -> Node:
	return current_target

func force_target(target: Node):
	if _is_valid_target(target):
		_acquire_target(target)

func get_debug_info() -> Dictionary:
	return {
		"ai_enabled": ai_enabled,
		"state": State.keys()[current_state],
		"has_target": current_target != null,
		"has_clear_los": has_clear_line_of_sight,
		"has_memory": has_memory,
		"memory_position": last_known_target_position,
		"path_length": path_to_target.size()
	}
