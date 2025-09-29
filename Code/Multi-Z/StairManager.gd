extends Node
class_name StairManager

signal player_z_level_changed(new_z_level: int)

@export_group("Stair Configuration")
@export var stairs: Array[StairData] = []
@export var stair_detection_interval: float = 0.1
@export var automatic_movement: bool = true
@export var movement_delay: float = 0.0

@export_group("Z-Level Settings")
@export var starting_z_level: int = 0

@export_group("Debug Settings")
@export var debug_enabled: bool = false
@export var debug_stair_detection: bool = false
@export var debug_player_position: bool = false
@export var debug_stair_lookup: bool = false

var player_entity: Node = null
var stair_tiles: Dictionary = {}
var player_current_z: int = 0
var detection_timer: float = 0.0

var z_level_manager: Node = null
var tile_occupancy_system: Node = null
var world: Node = null

var last_player_tile: Vector2i = Vector2i(-999, -999)
var detection_calls: int = 0
var just_moved_z_level: bool = false
var last_used_stair_tile: Vector2i = Vector2i(-999, -999)

func _ready():
	player_current_z = starting_z_level
	call_deferred("_initialize_systems")
	add_to_group("stair_manager")
	
	# Debugging for stairs array
	if debug_enabled:
		print("StairManager: Ready called. Stairs array size: ", stairs.size())
		_debug_stairs_array()

func _debug_stairs_array():
	print("=== STAIR ARRAY DEBUG ===")
	print("Total stairs in array: ", stairs.size())
	
	for i in range(stairs.size()):
		var stair = stairs[i]
		print("Stair [", i, "]:")
		
		if stair == null:
			print("  ERROR: Stair is NULL")
			continue
		
		if not stair is StairData:
			print("  ERROR: Stair is not StairData type, is: ", type_string(typeof(stair)))
			continue
		
		print("  Valid StairData found")
		print("  Name: ", stair.stair_name)
		print("  From Z: ", stair.from_z_level)
		print("  To Z: ", stair.to_z_level)
		print("  Bidirectional: ", stair.bidirectional)
		print("  Tile positions count: ", stair.tile_positions.size())
		
		if stair.tile_positions.size() > 0:
			print("  Tile positions: ", stair.tile_positions)
		
		if not stair.is_valid():
			print("  WARNING: Stair data is invalid (no tiles or same Z levels)")
	
	print("========================")

func _build_stair_lookup():
	stair_tiles.clear()
	
	if debug_stair_lookup:
		print("StairManager: Building stair lookup from ", stairs.size(), " stair configurations...")
	
	# Validation and debugging
	if stairs.size() == 0:
		print("StairManager: WARNING - No stairs configured in array!")
		return
	
	var valid_stairs_count = 0
	
	for i in range(stairs.size()):
		var stair_data = stairs[i]
		
		if not stair_data:
			print("StairManager: ERROR - Stair data at index ", i, " is null")
			continue
		
		if not stair_data is StairData:
			print("StairManager: ERROR - Object at index ", i, " is not StairData type")
			continue
		
		if not stair_data.is_valid():
			print("StairManager: WARNING - Stair at index ", i, " is invalid: ", stair_data.stair_name)
			continue
		
		valid_stairs_count += 1
		var from_z = stair_data.from_z_level
		var to_z = stair_data.to_z_level
		
		if debug_stair_lookup:
			print("StairManager: Processing valid stair '", stair_data.stair_name, "' from Z", from_z, " to Z", to_z, " with ", stair_data.tile_positions.size(), " tiles")
		
		# Initialize the from_z level if it doesn't exist
		if not from_z in stair_tiles:
			stair_tiles[from_z] = {}
		
		# Add all tile positions for this stair
		for tile_pos in stair_data.tile_positions:
			stair_tiles[from_z][tile_pos] = to_z
			if debug_stair_lookup:
				print("StairManager: Added stair tile at ", tile_pos, " (Z", from_z, " -> Z", to_z, ")")
		
		# Handle bidirectional stairs
		if stair_data.bidirectional:
			if not to_z in stair_tiles:
				stair_tiles[to_z] = {}
			
			for tile_pos in stair_data.tile_positions:
				stair_tiles[to_z][tile_pos] = from_z
				if debug_stair_lookup:
					print("StairManager: Added reverse stair tile at ", tile_pos, " (Z", to_z, " -> Z", from_z, ")")
	
	print("StairManager: Built stair lookup with ", valid_stairs_count, " valid stairs across ", stair_tiles.keys().size(), " Z-levels")
	
	if debug_enabled:
		_print_stair_lookup_summary()

func _print_stair_lookup_summary():
	print("=== STAIR LOOKUP SUMMARY ===")
	for z_level in stair_tiles.keys():
		var tiles_count = stair_tiles[z_level].keys().size()
		print("Z-Level ", z_level, ": ", tiles_count, " stair tiles")
		if debug_stair_lookup:
			for tile_pos in stair_tiles[z_level].keys():
				var target_z = stair_tiles[z_level][tile_pos]
				print("  ", tile_pos, " -> Z", target_z)
	print("===========================")

# Test function you can call from the debugger or a button
func test_stair_detection():
	print("=== TESTING STAIR DETECTION ===")
	_debug_stairs_array()
	_build_stair_lookup()
	
	if player_entity:
		var player_tile = _get_player_tile_position()
		var player_z = player_current_z
		print("Player at tile: ", player_tile, " on Z-level: ", player_z)
		
		var is_on_stair = _is_tile_stair(player_tile, player_z)
		print("Is on stair: ", is_on_stair)
		
		if is_on_stair:
			var target_z = stair_tiles[player_z][player_tile]
			print("Target Z-level: ", target_z)
	else:
		print("No player entity found")
	print("==============================")

# Add the rest of your existing functions here...
# (I'm including the key ones that might need debugging)

func _initialize_systems():
	_find_system_references()
	_build_stair_lookup()
	_find_player()
	_register_player_if_found()

func _find_system_references():
	world = get_tree().get_first_node_in_group("world")
	if not world:
		world = get_node_or_null("/root/World")
	
	if world:
		z_level_manager = world.get_node_or_null("ZLevelManager")
		tile_occupancy_system = world.get_node_or_null("TileOccupancySystem")
	
	if not z_level_manager:
		z_level_manager = get_tree().get_first_node_in_group("z_level_manager")
	
	if debug_enabled:
		print("StairManager: Found Z-Level Manager: ", z_level_manager != null)
		print("StairManager: Found Tile Occupancy: ", tile_occupancy_system != null)
		print("StairManager: Found World: ", world != null)

func _check_player_stair_position():
	if not player_entity:
		return
	
	detection_calls += 1
	var player_tile = _get_player_tile_position()
	
	if debug_player_position:
		print("StairManager: Player at tile ", player_tile, " on Z", player_current_z)
	
	if player_tile != last_player_tile:
		if debug_stair_detection:
			print("StairManager: Player moved from ", last_player_tile, " to ", player_tile)
		
		just_moved_z_level = false
		last_used_stair_tile = Vector2i(-999, -999)
		last_player_tile = player_tile
	
	if just_moved_z_level:
		if debug_stair_detection:
			print("StairManager: Skipping detection - just moved Z-level")
		return
	
	if player_tile == last_used_stair_tile:
		if debug_stair_detection:
			print("StairManager: Skipping detection - just used this stair tile")
		return
	
	var is_on_stair = _is_tile_stair(player_tile, player_current_z)
	
	if debug_stair_detection:
		print("StairManager: Checking tile ", player_tile, " on Z", player_current_z, " - Is stair: ", is_on_stair)
	
	if is_on_stair:
		var target_z = stair_tiles[player_current_z][player_tile]
		
		if debug_enabled:
			print("StairManager: Using stair at ", player_tile, " to move from Z", player_current_z, " to Z", target_z)
		
		last_used_stair_tile = player_tile
		just_moved_z_level = true
		
		if movement_delay > 0.0:
			await get_tree().create_timer(movement_delay).timeout
		
		_move_player_to_z_level(target_z)

func _is_tile_stair(tile_pos: Vector2i, z_level: int) -> bool:
	var has_z_level = z_level in stair_tiles
	var has_tile = has_z_level and tile_pos in stair_tiles[z_level]
	
	if debug_stair_detection:
		if not has_z_level:
			print("StairManager: No stairs configured for Z-level ", z_level)
		elif not has_tile:
			print("StairManager: Tile ", tile_pos, " not a stair on Z-level ", z_level)
			print("StairManager: Available stair tiles on Z", z_level, ": ", stair_tiles[z_level].keys())
	
	return has_tile

func _process(delta: float):
	if not player_entity:
		_find_player()
		return
	
	if not automatic_movement:
		return
	
	detection_timer += delta
	if detection_timer >= stair_detection_interval:
		detection_timer = 0.0
		_check_player_stair_position()

func _find_player():
	var players = get_tree().get_nodes_in_group("player_controller")
	if players.size() > 0:
		player_entity = players[0]
		if debug_enabled:
			print("StairManager: Found player entity: ", player_entity.name)
		_register_player_if_found()
	elif debug_enabled:
		print("StairManager: No player found in 'player_controller' group")

func _register_player_if_found():
	if not player_entity or not z_level_manager:
		if debug_enabled:
			print("StairManager: Cannot register player - Player: ", player_entity != null, ", Z-Manager: ", z_level_manager != null)
		return
	
	var player_tile = _get_player_tile_position()
	if debug_enabled:
		print("StairManager: Registering player at tile ", player_tile, " Z-level ", player_current_z)
	
	z_level_manager.register_entity(player_entity, player_current_z)
	
	if tile_occupancy_system:
		tile_occupancy_system.register_entity_at_tile(player_entity, player_tile, player_current_z)

func _get_player_tile_position() -> Vector2i:
	if not player_entity:
		return Vector2i.ZERO
	
	var tile_pos = Vector2i.ZERO
	
	if player_entity.has_method("get_current_tile_position"):
		tile_pos = player_entity.get_current_tile_position()
	elif "movement_component" in player_entity and player_entity.movement_component:
		if "current_tile_position" in player_entity.movement_component:
			tile_pos = player_entity.movement_component.current_tile_position
	elif world and world.has_method("world_to_tile"):
		tile_pos = world.world_to_tile(player_entity.global_position)
	
	return tile_pos

func _move_player_to_z_level(target_z: int):
	if target_z == player_current_z or not z_level_manager:
		just_moved_z_level = false
		return
	
	var old_z = player_current_z
	
	if debug_enabled:
		print("StairManager: Moving player from Z-level ", old_z, " to Z-level ", target_z)
	
	if z_level_manager.move_entity_to_z_level(player_entity, target_z):
		player_current_z = target_z
		emit_signal("player_z_level_changed", target_z)
		if debug_enabled:
			print("StairManager: Successfully moved player to Z-level ", target_z)
		
		call_deferred("_clear_movement_flag")
	else:
		if debug_enabled:
			print("StairManager: Failed to move player to Z-level ", target_z)
		just_moved_z_level = false

func _clear_movement_flag():
	just_moved_z_level = false
	if debug_stair_detection:
		print("StairManager: Cleared movement flag - can detect stairs again")

func get_player_z_level() -> int:
	return player_current_z

func refresh_stairs():
	_build_stair_lookup()

func get_stair_at_position(tile_pos: Vector2i, z_level: int) -> int:
	if _is_tile_stair(tile_pos, z_level):
		return stair_tiles[z_level][tile_pos]
	return -1
