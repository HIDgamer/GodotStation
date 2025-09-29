extends Node

@export_group("Startup Settings")
@export var startup_delay: float = 5.0  # Delay before spawning starts
@export var debug_enabled: bool = true

@export_group("Difficulty Settings")
@export var current_difficulty: int = 3  # 1-5 difficulty levels
@export var base_spawn_interval: float = 15.0  # Base time between spawns
@export var movement_spawn_chance: float = 0.08  # Chance to spawn when player moves

@export_group("Horde Scaling")
@export var base_horde_size: int = 4
@export var kills_per_escalation: int = 3  # Every X kills increases horde size
@export var max_horde_size: int = 12

@export_group("Spawn Configuration")
@export var min_spawn_distance: int = 7  # Minimum tiles away from player
@export var max_spawn_distance: int = 15  # Maximum tiles away from player
@export var spawn_radius_attempts: int = 25  # Attempts to find valid spawn spot

@export_group("Alien Types")
@export var alien_scene_path: String = "res://Scenes/Characters/alien.tscn"
@export var available_alien_types: Array[String] = ["Drone"]

@export_group("World Detection")
@export var world_group_name: String = "world"
@export var hub_scene_name: String = "Hub"

# =============================================================================
# DIFFICULTY MULTIPLIERS
# =============================================================================

var difficulty_multipliers = {
	1: {"spawn_rate": 1.0, "horde_multiplier": 1.0, "movement_chance": 0.8},
	2: {"spawn_rate": 0.75, "horde_multiplier": 1.3, "movement_chance": 1.0},
	3: {"spawn_rate": 0.55, "horde_multiplier": 1.6, "movement_chance": 1.3},
	4: {"spawn_rate": 0.4, "horde_multiplier": 2.0, "movement_chance": 1.6},
	5: {"spawn_rate": 0.25, "horde_multiplier": 2.8, "movement_chance": 2.0}
}

# =============================================================================
# CORE VARIABLES
# =============================================================================

var game_manager: Node = null
var world: Node = null
var tile_occupancy_system: Node = null

# State management
var is_initialized: bool = false
var is_active: bool = false
var spawning_enabled: bool = false
var startup_timer: float = 0.0
var waiting_for_startup: bool = false

# NEW: Retry and delay systems
var initialization_retry_timer: float = 0.0
var initialization_retry_delay: float = 1.0  # Check every second
var initialization_retry_count: int = 0
var max_initialization_retries: int = 30  # Try for 30 seconds
var waiting_for_proper_world: bool = false

# Player tracking
var tracked_players: Dictionary = {}
var last_player_positions: Dictionary = {}

# Kill tracking and scaling
var total_player_kills: int = 0
var current_escalation_level: int = 0

# Spawn management
var spawn_timer: float = 0.0
var current_spawn_interval: float = 15.0
var active_aliens: Array[Node] = []

# Debug tracking
var debug_info: Dictionary = {}
var last_spawn_attempt_time: float = 0.0
var successful_spawns: int = 0
var failed_spawns: int = 0

# Signals
signal hive_mind_started()
signal alien_spawned(alien: Node, spawn_position: Vector2i)
signal horde_spawned(aliens: Array, spawn_positions: Array)
signal difficulty_changed(old_difficulty: int, new_difficulty: int)
signal escalation_level_increased(new_level: int, total_kills: int)
signal debug_info_updated(info: Dictionary)

# =============================================================================
# INITIALIZATION
# =============================================================================

func _ready():
	debug_log("HiveMind initializing...")
	_setup_debug_info()
	_calculate_spawn_interval()
	
	set_process(true)
	debug_log("HiveMind ready, starting delayed initialization...")
	
	# Start with a small delay to let the game settle
	await get_tree().create_timer(0.5).timeout
	_begin_initialization_process()

func _begin_initialization_process():
	debug_log("Beginning initialization process...")
	waiting_for_proper_world = true
	initialization_retry_count = 0
	_attempt_initialization()

func _attempt_initialization():
	debug_log("Attempting initialization (attempt " + str(initialization_retry_count + 1) + ")")
	
	if not _find_game_manager():
		debug_log("GameManager not found, will retry...")
		return
	
	# Debug: Show what nodes are in the world group
	var world_group_nodes = get_tree().get_nodes_in_group(world_group_name)
	debug_log("Nodes in '" + world_group_name + "' group: " + str(world_group_nodes.size()))
	for i in range(min(world_group_nodes.size(), 3)):  # Show first 3 nodes
		debug_log("  - " + str(world_group_nodes[i].name) + " (" + str(world_group_nodes[i].get_class()) + ")")
	
	if not _is_in_valid_game_world():
		debug_log("Not in valid game world yet, will retry...")
		return
	
	debug_log("Found valid game world, establishing connections...")
	_setup_connections()

func _find_game_manager() -> bool:
	if game_manager:
		return true
		
	game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		debug_log("GameManager found!")
		return true
	
	return false

func _is_in_valid_game_world() -> bool:
	if not game_manager:
		return false
	
	# Look for the actual world node in the "world" group
	var world_node = get_tree().get_first_node_in_group(world_group_name)
	
	if not world_node:
		debug_log("No world node found in group '" + world_group_name + "'")
		return false
	
	# Update our world reference to the actual world node
	world = world_node
	
	var world_name = world.name
	debug_log("Found world node in group: " + world_name)
	
	# Check if the world node is valid and ready
	if not is_instance_valid(world):
		debug_log("World node is not valid")
		return false
	
	debug_log("Valid world node found: " + world_name)
	return true

func _setup_connections():
	if game_manager.has_signal("world_loaded"):
		if not game_manager.world_loaded.is_connected(_on_world_loaded):
			game_manager.world_loaded.connect(_on_world_loaded)
			debug_log("Connected to world_loaded signal")
	
	if game_manager.has_signal("game_state_changed"):
		if not game_manager.game_state_changed.is_connected(_on_game_state_changed):
			game_manager.game_state_changed.connect(_on_game_state_changed)
			debug_log("Connected to game_state_changed signal")
	
	# Since we're already in a valid world, try to establish systems immediately
	_establish_world_system_references()

func _setup_debug_info():
	debug_info = {
		"is_initialized": false,
		"is_active": false,
		"spawning_enabled": false,
		"startup_timer": 0.0,
		"current_difficulty": current_difficulty,
		"total_kills": 0,
		"escalation_level": 0,
		"active_aliens_count": 0,
		"tracked_players_count": 0,
		"current_spawn_interval": current_spawn_interval,
		"time_until_next_spawn": 0.0,
		"successful_spawns": 0,
		"failed_spawns": 0,
		"last_spawn_attempt": "Never",
		"initialization_retry_count": 0,
		"waiting_for_proper_world": false,
		"current_world_name": "None",
		"world_group_count": 0
	}

# =============================================================================
# MAIN LOOP
# =============================================================================

func _process(delta: float):
	_update_debug_info()
	
	# Handle initialization retries
	if waiting_for_proper_world:
		_handle_initialization_retry(delta)
		return
	
	if not is_initialized:
		return
	
	if waiting_for_startup:
		_handle_startup_timer(delta)
		return
	
	if not is_active or not spawning_enabled:
		return
	
	_update_player_tracking()
	_update_spawn_timer(delta)
	_cleanup_dead_aliens()

func _handle_initialization_retry(delta: float):
	initialization_retry_timer += delta
	
	if initialization_retry_timer >= initialization_retry_delay:
		initialization_retry_timer = 0.0
		initialization_retry_count += 1
		
		if initialization_retry_count >= max_initialization_retries:
			debug_log("Max initialization retries reached, giving up")
			waiting_for_proper_world = false
			return
		
		_attempt_initialization()

func _handle_startup_timer(delta: float):
	startup_timer += delta
	
	if startup_timer >= startup_delay:
		waiting_for_startup = false
		spawning_enabled = true
		spawn_timer = 0.0  # Reset spawn timer
		debug_log("HiveMind startup complete! Spawning enabled.")
		emit_signal("hive_mind_started")

func _update_spawn_timer(delta: float):
	spawn_timer += delta
	
	if spawn_timer >= current_spawn_interval:
		spawn_timer = 0.0
		_attempt_scheduled_spawn()

# =============================================================================
# SYSTEM INTEGRATION (UPDATED)
# =============================================================================

func _on_world_loaded():
	debug_log("World loaded signal received...")
	
	# Reset world references
	world = null
	tile_occupancy_system = null
	
	# Wait a moment for world to settle and be added to groups
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout
	
	# Look for world node in the group
	world = get_tree().get_first_node_in_group(world_group_name)
	
	if not world:
		debug_log("No world node found in group '" + world_group_name + "' yet, will retry...")
		return
	
	debug_log("World node found in group: " + str(world.name) + ", establishing system references...")
	_establish_world_system_references()

func _establish_world_system_references():
	# Get the actual world node from the group
	if not world:
		world = get_tree().get_first_node_in_group(world_group_name)
	
	if not world:
		debug_log("ERROR: No world node found in group '" + world_group_name + "'!")
		return
	
	debug_log("Establishing world system references for: " + str(world.name))
	
	# Wait additional frames for world systems to initialize
	for i in range(3):
		await get_tree().process_frame
	
	# Try multiple strategies to find tile occupancy system
	_find_tile_occupancy_system()
	
	# Validate and initialize if ready
	if _validate_world_systems():
		waiting_for_proper_world = false
		is_initialized = true
		is_active = true
		waiting_for_startup = true
		startup_timer = 0.0
		
		debug_log("All world systems validated! Starting " + str(startup_delay) + " second countdown...")
	else:
		debug_log("World systems validation failed, will continue trying...")

func _find_tile_occupancy_system():
	debug_log("Searching for tile occupancy system...")
	
	# Strategy 1: Look for common names in world
	var tile_system_names = ["TileOccupancySystem", "TileSystem", "OccupancySystem", "TileManager"]
	
	for system_name in tile_system_names:
		tile_occupancy_system = world.get_node_or_null(system_name)
		if tile_occupancy_system:
			debug_log("Found tile system via name: " + system_name)
			return
	
	# Strategy 2: Search all children recursively
	tile_occupancy_system = _find_node_with_method(world, "has_dense_entity_at")
	if tile_occupancy_system:
		debug_log("Found tile system via method search: " + str(tile_occupancy_system.name))
		return
	
	# Strategy 3: Look for any node with "tile" in the name
	tile_occupancy_system = _find_node_by_name_pattern(world, "tile")
	if tile_occupancy_system:
		debug_log("Found tile system via pattern search: " + str(tile_occupancy_system.name))
		return
	
	debug_log("No tile occupancy system found after exhaustive search")

func _find_node_with_method(parent: Node, method_name: String) -> Node:
	for child in parent.get_children():
		if child.has_method(method_name):
			return child
		var result = _find_node_with_method(child, method_name)
		if result:
			return result
	return null

func _find_node_by_name_pattern(parent: Node, pattern: String) -> Node:
	for child in parent.get_children():
		if child.name.to_lower().contains(pattern.to_lower()):
			return child
		var result = _find_node_by_name_pattern(child, pattern)
		if result:
			return result
	return null

func _validate_world_systems() -> bool:
	debug_log("Validating world systems...")
	
	var all_valid = true
	var validation_score = 0
	var max_score = 0
	
	# Validate world (required)
	max_score += 3
	if not world:
		debug_log("VALIDATION FAILED: No world reference")
		all_valid = false
	else:
		debug_log("✓ World reference valid: " + str(world.name))
		validation_score += 1
		
		# Check world methods (nice to have but not required for basic functionality)
		if world.has_method("is_valid_tile"):
			debug_log("✓ World has is_valid_tile method")
			validation_score += 1
		else:
			debug_log("⚠ World missing is_valid_tile method (will use fallback)")
		
		if world.has_method("is_wall_at"):
			debug_log("✓ World has is_wall_at method")
			validation_score += 1
		else:
			debug_log("⚠ World missing is_wall_at method (will use fallback)")
	
	# Validate tile occupancy system (nice to have)
	max_score += 1
	if not tile_occupancy_system:
		debug_log("⚠ No tile occupancy system (will spawn without occupancy checks)")
	else:
		debug_log("✓ Tile occupancy system found: " + str(tile_occupancy_system.name))
		validation_score += 1
		
		if tile_occupancy_system.has_method("has_dense_entity_at"):
			debug_log("✓ Tile system has has_dense_entity_at method")
		else:
			debug_log("⚠ Tile system missing has_dense_entity_at method")
	
	# Validate GameManager (required)
	max_score += 1
	if not game_manager:
		debug_log("VALIDATION FAILED: No GameManager reference")
		all_valid = false
	else:
		debug_log("✓ GameManager reference valid")
		validation_score += 1
		
		if not game_manager.has_method("spawn_npc_at_tile"):
			debug_log("VALIDATION FAILED: GameManager missing spawn_npc_at_tile method")
			all_valid = false
		else:
			debug_log("✓ GameManager has spawn_npc_at_tile method")
	
	debug_log("Validation score: " + str(validation_score) + "/" + str(max_score))
	
	# We need at least the world and GameManager to function
	var minimum_valid = world != null and game_manager != null
	
	if minimum_valid:
		debug_log("System validation PASSED (minimum requirements met)")
	else:
		debug_log("System validation FAILED (minimum requirements not met)")
	
	return minimum_valid

func _on_game_state_changed(old_state, new_state):
	debug_log("Game state changed from " + str(old_state) + " to " + str(new_state))
	
	# If we're not initialized yet and game state indicates we're in-game, try to initialize
	if not is_initialized and game_manager and game_manager.has_method("is_in_game"):
		if game_manager.is_in_game():
			debug_log("Game state indicates in-game, attempting initialization...")
			waiting_for_proper_world = true
			initialization_retry_count = 0
			_attempt_initialization()
	
	if game_manager and game_manager.has_method("is_in_game"):
		var was_spawning = spawning_enabled
		var should_spawn = game_manager.is_in_game()
		
		if should_spawn and not was_spawning and is_initialized:
			# Game started, begin countdown
			waiting_for_startup = true
			startup_timer = 0.0
			debug_log("Game started, beginning startup countdown...")
		elif not should_spawn:
			# Game ended, stop spawning
			spawning_enabled = false
			waiting_for_startup = false
			_cleanup_all_aliens()
			debug_log("Game ended, cleaning up aliens...")

# =============================================================================
# IMPROVED SPAWN VALIDATION
# =============================================================================

func _is_valid_spawn_position(pos: Vector2i, player_pos: Vector2i) -> bool:
	var distance = _distance(pos, player_pos)
	if distance < min_spawn_distance or distance > max_spawn_distance:
		return false
	
	# Basic world validation with fallbacks
	if world:
		if world.has_method("is_valid_tile"):
			if not world.is_valid_tile(pos, 0):
				return false
		
		if world.has_method("is_wall_at"):
			if world.is_wall_at(pos, 0):
				return false
	
	# Occupancy check (optional)
	if tile_occupancy_system and tile_occupancy_system.has_method("has_dense_entity_at"):
		if tile_occupancy_system.has_dense_entity_at(pos, 0):
			return false
	
	return true

# =============================================================================
# DEBUG SYSTEM (UPDATED)
# =============================================================================

func _update_debug_info():
	var current_world_name = "None"
	var world_group_nodes = get_tree().get_nodes_in_group(world_group_name)
	
	if world:
		current_world_name = world.name
	elif not world_group_nodes.is_empty():
		current_world_name = "Group has " + str(world_group_nodes.size()) + " nodes"
	
	debug_info.merge({
		"is_initialized": is_initialized,
		"is_active": is_active,
		"spawning_enabled": spawning_enabled,
		"startup_timer": startup_timer,
		"waiting_for_startup": waiting_for_startup,
		"waiting_for_proper_world": waiting_for_proper_world,
		"initialization_retry_count": initialization_retry_count,
		"current_world_name": current_world_name,
		"world_group_count": world_group_nodes.size(),
		"current_difficulty": current_difficulty,
		"total_kills": total_player_kills,
		"escalation_level": current_escalation_level,
		"active_aliens_count": active_aliens.size(),
		"tracked_players_count": tracked_players.size(),
		"current_spawn_interval": current_spawn_interval,
		"time_until_next_spawn": max(0, current_spawn_interval - spawn_timer),
		"successful_spawns": successful_spawns,
		"failed_spawns": failed_spawns,
		"last_spawn_attempt": Time.get_datetime_string_from_unix_time(last_spawn_attempt_time) if last_spawn_attempt_time > 0 else "Never"
	}, true)
	
	emit_signal("debug_info_updated", debug_info)

# =============================================================================
# [REST OF THE CODE REMAINS THE SAME]
# =============================================================================

# [Include all the remaining functions from your original code here:
# - Player tracking functions
# - Spawning system functions  
# - Difficulty and scaling functions
# - Cleanup functions
# - Utility functions
# - Public interface functions
# etc.]

func _update_player_tracking():
	if not game_manager:
		return
	
	var players = game_manager.get_players()
	var current_positions = {}
	
	for player_id in players:
		var player_data = players[player_id]
		if player_data and "instance" in player_data and player_data.instance:
			var player_instance = player_data.instance
			if is_instance_valid(player_instance):
				var current_pos = _get_entity_position(player_instance)
				current_positions[player_id] = current_pos
				
				# Check if player moved
				if player_id in last_player_positions:
					var last_pos = last_player_positions[player_id]
					if last_pos != current_pos:
						_on_player_moved(player_id, last_pos, current_pos)
	
	last_player_positions = current_positions
	tracked_players = players

func _on_player_moved(player_id: int, old_pos: Vector2i, new_pos: Vector2i):
	if not spawning_enabled:
		return
	
	var difficulty_mult = difficulty_multipliers[current_difficulty]
	var adjusted_chance = movement_spawn_chance * difficulty_mult.movement_chance
	
	if randf() < adjusted_chance:
		debug_log("Movement spawn triggered for player " + str(player_id))
		_spawn_aliens_near_player(player_id, 1)

func _attempt_scheduled_spawn():
	last_spawn_attempt_time = Time.get_ticks_msec() / 1000.0
	
	if not _should_spawn():
		debug_log("Spawn conditions not met")
		failed_spawns += 1
		return
	
	var target_player_id = _select_target_player()
	if target_player_id == -1:
		debug_log("No valid target player found")
		failed_spawns += 1
		return
	
	var horde_size = _calculate_horde_size()
	debug_log("Attempting to spawn horde of size " + str(horde_size) + " near player " + str(target_player_id))
	
	var spawned_count = await _spawn_aliens_near_player(target_player_id, horde_size)
	if spawned_count > 0:
		successful_spawns += 1
		debug_log("Successfully spawned " + str(spawned_count) + " aliens")
	else:
		failed_spawns += 1
		debug_log("Failed to spawn any aliens")

func _should_spawn() -> bool:
	if tracked_players.is_empty():
		debug_log("Cannot spawn: no tracked players")
		return false
	
	if not game_manager or not game_manager.is_in_game():
		debug_log("Cannot spawn: game not in progress")
		return false
	
	# Check if world systems are available
	if not world:
		debug_log("Cannot spawn: no world reference")
		return false
	
	# Don't spawn too many aliens at once
	if active_aliens.size() >= max_horde_size * 3:
		debug_log("Cannot spawn: too many active aliens (" + str(active_aliens.size()) + ")")
		return false
	
	return true

func _select_target_player() -> int:
	for player_id in tracked_players:
		var player_data = tracked_players[player_id]
		if player_data and "instance" in player_data and player_data.instance:
			if is_instance_valid(player_data.instance):
				return player_id
	return -1

func _spawn_aliens_near_player(player_id: int, count: int) -> int:
	if not game_manager or not world:
		return 0
	
	var player_data = tracked_players.get(player_id)
	if not player_data or not player_data.instance:
		return 0
	
	var player_instance = player_data.instance
	if not is_instance_valid(player_instance):
		return 0
	
	var player_pos = _get_entity_position(player_instance)
	var spawn_positions = _find_spawn_positions(player_pos, count)
	
	if spawn_positions.is_empty():
		debug_log("No valid spawn positions found near player")
		return 0
	
	var spawned_aliens = []
	var spawned_count = 0
	
	for spawn_pos in spawn_positions:
		var alien = await _spawn_single_alien(spawn_pos)
		if alien:
			spawned_aliens.append(alien)
			active_aliens.append(alien)
			spawned_count += 1
			
			# Make alien target the player
			if alien.has_method("force_ai_target"):
				alien.force_ai_target(player_instance)
			
			emit_signal("alien_spawned", alien, spawn_pos)
	
	if spawned_aliens.size() > 1:
		emit_signal("horde_spawned", spawned_aliens, spawn_positions)
	
	return spawned_count

func _spawn_single_alien(spawn_pos: Vector2i) -> Node:
	if not game_manager:
		return null
	
	var alien_type = _select_alien_type()
	var alien_name = "HiveMind_" + alien_type + "_" + str(Time.get_ticks_msec())
	
	var alien = null
	
	# Try spawning from scene first
	if ResourceLoader.exists(alien_scene_path):
		alien = await game_manager.spawn_npc_from_scene(alien_scene_path, spawn_pos, 0, alien_name)
		if alien:
			debug_log("Spawned alien from scene at " + str(spawn_pos))
	
	# Fallback to default spawning method
	if not alien:
		alien = game_manager.spawn_npc_at_tile(spawn_pos, 0, alien_name)
		if alien:
			debug_log("Spawned alien using fallback method at " + str(spawn_pos))
	
	if alien:
		_configure_spawned_alien(alien, alien_type)
	else:
		debug_log("Failed to spawn alien at " + str(spawn_pos))
	
	return alien

func _configure_spawned_alien(alien: Node, alien_type: String):
	alien.set_meta("hive_mind_spawned", true)
	alien.set_meta("alien_type", alien_type)
	alien.set_meta("spawn_time", Time.get_ticks_msec())
	
	if alien.has_method("enable_ai"):
		alien.enable_ai()
	
	# Connect death signal to track kills
	if alien.has_signal("alien_died"):
		if not alien.alien_died.is_connected(_on_alien_died):
			alien.alien_died.connect(_on_alien_died.bind(alien))

func _find_spawn_positions(player_pos: Vector2i, count: int) -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	var attempts = 0
	var max_attempts = spawn_radius_attempts * count
	
	while positions.size() < count and attempts < max_attempts:
		attempts += 1
		
		var angle = randf() * TAU
		var distance = randf_range(min_spawn_distance, max_spawn_distance)
		
		var spawn_pos = Vector2i(
			player_pos.x + int(cos(angle) * distance),
			player_pos.y + int(sin(angle) * distance)
		)
		
		if _is_valid_spawn_position(spawn_pos, player_pos):
			positions.append(spawn_pos)
	
	debug_log("Found " + str(positions.size()) + " valid spawn positions out of " + str(attempts) + " attempts")
	return positions

func _select_alien_type() -> String:
	if available_alien_types.is_empty():
		return "Drone"
	return available_alien_types[randi() % available_alien_types.size()]

func _calculate_horde_size() -> int:
	var difficulty_mult = difficulty_multipliers[current_difficulty]
	var base_size = max(1, int(base_horde_size * difficulty_mult.horde_multiplier))
	var escalation_bonus = current_escalation_level
	return min(max_horde_size, base_size + escalation_bonus)

func _calculate_spawn_interval():
	var difficulty_mult = difficulty_multipliers[current_difficulty]
	current_spawn_interval = base_spawn_interval * difficulty_mult.spawn_rate

func set_difficulty(new_difficulty: int):
	if new_difficulty < 1 or new_difficulty > 5:
		return
	
	var old_difficulty = current_difficulty
	current_difficulty = clamp(new_difficulty, 1, 5)
	_calculate_spawn_interval()
	
	debug_log("Difficulty changed from " + str(old_difficulty) + " to " + str(current_difficulty))
	emit_signal("difficulty_changed", old_difficulty, current_difficulty)

func _on_alien_died(alien: Node):
	if active_aliens.has(alien):
		active_aliens.erase(alien)
	
	total_player_kills += 1
	debug_log("Alien died. Total kills: " + str(total_player_kills))
	_check_escalation()

func _check_escalation():
	var new_escalation_level = total_player_kills / kills_per_escalation
	
	if new_escalation_level > current_escalation_level:
		current_escalation_level = new_escalation_level
		debug_log("Escalation level increased to " + str(current_escalation_level))
		emit_signal("escalation_level_increased", current_escalation_level, total_player_kills)

func _cleanup_dead_aliens():
	var cleaned_count = 0
	var i = active_aliens.size() - 1
	while i >= 0:
		var alien = active_aliens[i]
		if not is_instance_valid(alien):
			active_aliens.remove_at(i)
			cleaned_count += 1
		i -= 1
	
	if cleaned_count > 0:
		debug_log("Cleaned up " + str(cleaned_count) + " dead aliens")

func _cleanup_all_aliens():
	var count = active_aliens.size()
	for alien in active_aliens:
		if is_instance_valid(alien):
			alien.queue_free()
	
	active_aliens.clear()
	debug_log("Cleaned up " + str(count) + " active aliens")

func debug_log(message: String):
	if debug_enabled:
		print("[HiveMind] " + message)

func _get_entity_position(entity: Node) -> Vector2i:
	if not entity:
		return Vector2i.ZERO
	
	if entity.has_method("get_current_tile_position"):
		return entity.get_current_tile_position()
	elif "current_tile_position" in entity:
		return entity.current_tile_position
	elif "position" in entity:
		return Vector2i(int(entity.position.x / 32), int(entity.position.y / 32))
	
	return Vector2i.ZERO

func _distance(a: Vector2i, b: Vector2i) -> float:
	return abs(a.x - b.x) + abs(a.y - b.y)

func enable_spawning():
	spawning_enabled = true
	debug_log("Spawning manually enabled")

func disable_spawning():
	spawning_enabled = false
	debug_log("Spawning manually disabled")

func reset_kill_count():
	total_player_kills = 0
	current_escalation_level = 0
	debug_log("Kill count reset")

func force_spawn_horde(player_id: int = -1, size: int = -1):
	if player_id == -1:
		player_id = _select_target_player()
	
	if player_id == -1:
		debug_log("Force spawn failed: no valid player")
		return
	
	if size == -1:
		size = _calculate_horde_size()
	
	debug_log("Force spawning horde of size " + str(size))
	_spawn_aliens_near_player(player_id, size)

func get_debug_info() -> Dictionary:
	return debug_info.duplicate()

func toggle_debug():
	debug_enabled = !debug_enabled
	debug_log("Debug mode " + ("enabled" if debug_enabled else "disabled"))
