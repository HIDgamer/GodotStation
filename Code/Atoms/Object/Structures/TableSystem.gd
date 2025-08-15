extends BaseObject
class_name TableSystem

# Table system for handling connected table tiles
@export_group("Table Settings")
@export var table_type: String = "metal"
@export var can_flip: bool = true
@export var flip_strength: float = 100.0
@export var table_health: float = 100.0
@export var reinforced: bool = false

# Tilemap integration
var table_tilemap: TileMap = null
var tile_coord: Vector2i = Vector2i.ZERO
var connected_tables: Array = []
var is_flipped: bool = false
var flip_direction: Vector2 = Vector2.ZERO

# Signals
signal table_flipped(direction)
signal table_restored()
signal items_thrown(items_array)
signal table_connected(other_table)
signal table_disconnected(other_table)

func _ready():
	super()
	entity_type = "table"
	climbable = true
	climb_delay = CLIMB_DELAY_SHORT
	
	add_to_group("tables")
	add_to_group("climbable")
	
	setup_table_tilemap()
	find_connected_tables()

func setup_table_tilemap():
	"""Set up tilemap integration"""
	# Find or create tilemap
	table_tilemap = get_node_or_null("../TableTilemap")
	if not table_tilemap:
		var world = get_parent()
		if world:
			table_tilemap = world.get_node_or_null("TableTilemap")
	
	if table_tilemap:
		# Calculate tile coordinate
		var tile_size = table_tilemap.tile_set.tile_size if table_tilemap.tile_set else Vector2i(32, 32)
		tile_coord = Vector2i(
			int(global_position.x / tile_size.x),
			int(global_position.y / tile_size.y)
		)
		
		# Set tile in tilemap
		var source_id = get_table_source_id()
		var atlas_coord = get_table_atlas_coord()
		table_tilemap.set_cell(0, tile_coord, source_id, atlas_coord)

func get_table_source_id() -> int:
	"""Get tilemap source ID for this table type"""
	match table_type:
		"metal":
			return 0
		"wood":
			return 1
		"reinforced":
			return 2
		_:
			return 0

func get_table_atlas_coord() -> Vector2i:
	"""Get atlas coordinates for table appearance"""
	if is_flipped:
		return Vector2i(1, 0)  # Flipped table sprite
	else:
		return Vector2i(0, 0)  # Normal table sprite

# MULTIPLAYER SYNCHRONIZATION
@rpc("any_peer", "call_local", "reliable")
func sync_table_flipped(flip_dir: Vector2, user_network_id: String):
	var user = find_user_by_network_id(user_network_id)
	_flip_table_internal(flip_dir, user)

@rpc("any_peer", "call_local", "reliable")
func sync_table_restored(user_network_id: String):
	var user = find_user_by_network_id(user_network_id)
	_restore_table_internal(user)

# TABLE FLIPPING SYSTEM
func flip_table(user, direction: Vector2 = Vector2.ZERO) -> bool:
	"""Flip the table in a direction"""
	if is_flipped or not can_flip:
		return false
	
	if not can_interact(user):
		return false
	
	# Check if table line is straight (can't flip connected tables that aren't in a line)
	if not is_table_line_straight():
		show_user_message(user, "The connected tables are too wide to flip!")
		return false
	
	# Calculate flip direction if not provided
	if direction == Vector2.ZERO:
		direction = (global_position - user.global_position).normalized()
	
	_flip_table_internal(direction, user)
	
	# Sync across network
	if multiplayer.has_multiplayer_peer():
		sync_table_flipped.rpc(direction, get_user_network_id(user))
	
	return true

func _flip_table_internal(direction: Vector2, user = null):
	"""Internal table flipping logic"""
	is_flipped = true
	flip_direction = direction
	
	# Throw items on table
	throw_table_items(direction)
	
	# Update visual appearance
	update_table_appearance()
	
	# Flip connected tables
	flip_connected_tables(direction)
	
	# Play effects
	play_table_flip_effects()
	
	emit_signal("table_flipped", direction)
	
	if user:
		show_user_message(user, "You flip " + get_entity_name(self) + "!")

func restore_table(user = null) -> bool:
	"""Restore flipped table to normal position"""
	if not is_flipped:
		return false
	
	_restore_table_internal(user)
	
	# Sync across network
	if multiplayer.has_multiplayer_peer():
		sync_table_restored.rpc(get_user_network_id(user))
	
	return true

func _restore_table_internal(user = null):
	"""Internal table restoration logic"""
	is_flipped = false
	flip_direction = Vector2.ZERO
	
	# Update visual appearance
	update_table_appearance()
	
	# Restore connected tables
	restore_connected_tables()
	
	emit_signal("table_restored")
	
	if user:
		show_user_message(user, "You restore " + get_entity_name(self) + " to its normal position.")

func throw_table_items(direction: Vector2):
	"""Throw all items on the table"""
	var items_on_table = get_items_on_table()
	var thrown_items = []
	
	for item in items_on_table:
		if item.has_method("apply_throw_force"):
			var throw_direction = direction + Vector2(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3))
			var throw_force = flip_strength + randf_range(-20, 20)
			item.apply_throw_force(throw_direction, throw_force)
			thrown_items.append(item)
	
	emit_signal("items_thrown", thrown_items)

func get_items_on_table() -> Array:
	"""Get all items currently on the table"""
	var items = []
	var world = get_parent()
	
	if not world:
		return items
	
	for child in world.get_children():
		if child == self:
			continue
		
		if child.is_in_group("items") and is_on_table(child):
			items.append(child)
	
	return items

func is_on_table(item) -> bool:
	"""Check if an item is on this table"""
	var distance = global_position.distance_to(item.global_position)
	return distance <= 24.0  # Within table bounds

# TABLE CONNECTION SYSTEM
func find_connected_tables():
	"""Find tables connected to this one"""
	connected_tables.clear()
	
	var world = get_parent()
	if not world:
		return
	
	var nearby_tables = []
	for child in world.get_children():
		if child == self or not child.is_in_group("tables"):
			continue
		
		var distance = global_position.distance_to(child.global_position)
		if distance <= 48.0:  # Adjacent table distance
			nearby_tables.append(child)
	
	# Check for actual connections (adjacent tiles)
	for table in nearby_tables:
		if is_table_adjacent(table):
			connect_to_table(table)

func is_table_adjacent(other_table) -> bool:
	"""Check if another table is adjacent to this one"""
	var our_tile = world_to_tile(global_position)
	var other_tile = world_to_tile(other_table.global_position)
	
	var diff = (our_tile - other_tile).abs()
	return (diff.x == 1 and diff.y == 0) or (diff.x == 0 and diff.y == 1)

func connect_to_table(other_table):
	"""Connect to another table"""
	if other_table not in connected_tables:
		connected_tables.append(other_table)
		
		# Ensure bidirectional connection
		if other_table.has_method("connect_to_table") and self not in other_table.connected_tables:
			other_table.connect_to_table(self)
		
		emit_signal("table_connected", other_table)

func disconnect_from_table(other_table):
	"""Disconnect from another table"""
	if other_table in connected_tables:
		connected_tables.erase(other_table)
		
		# Ensure bidirectional disconnection
		if other_table.has_method("disconnect_from_table") and self in other_table.connected_tables:
			other_table.disconnect_from_table(self)
		
		emit_signal("table_disconnected", other_table)

func is_table_line_straight() -> bool:
	"""Check if connected tables form a straight line"""
	if connected_tables.size() <= 1:
		return true
	
	# Simple implementation: check if all tables are in a single row or column
	var our_tile = world_to_tile(global_position)
	var same_row = true
	var same_col = true
	
	for table in connected_tables:
		var table_tile = world_to_tile(table.global_position)
		if table_tile.y != our_tile.y:
			same_row = false
		if table_tile.x != our_tile.x:
			same_col = false
	
	return same_row or same_col

func flip_connected_tables(direction: Vector2):
	"""Flip all connected tables"""
	for table in connected_tables:
		if table.has_method("_flip_table_internal") and not table.is_flipped:
			table._flip_table_internal(direction)

func restore_connected_tables():
	"""Restore all connected tables"""
	for table in connected_tables:
		if table.has_method("_restore_table_internal") and table.is_flipped:
			table._restore_table_internal()

# VISUAL AND AUDIO EFFECTS
func update_table_appearance():
	"""Update table visual appearance"""
	if table_tilemap:
		var atlas_coord = get_table_atlas_coord()
		table_tilemap.set_cell(0, tile_coord, get_table_source_id(), atlas_coord)
	
	# Update sprite if using sprite instead of tilemap
	var sprite = get_node_or_null("Icon")
	if sprite:
		if is_flipped:
			sprite.rotation_degrees = 90
			sprite.position.y += 8
		else:
			sprite.rotation_degrees = 0
			sprite.position.y = 0

func play_table_flip_effects():
	"""Play sound and visual effects for table flipping"""
	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager:
		audio_manager.play_positioned_sound("table_flip", global_position, 0.7)
	
	# Screen shake for nearby players
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		var distance = global_position.distance_to(player.global_position)
		if distance <= 200.0:
			if player.has_method("apply_screen_shake"):
				var shake_intensity = (200.0 - distance) / 200.0
				player.apply_screen_shake(shake_intensity * 0.3, 0.5)

# INTERACTION OVERRIDES
func attack_hand(user, params = null) -> bool:
	"""Handle hand interactions"""
	var intent = get_user_intent(user)
	
	match intent:
		3: # HARM - flip table
			if not is_flipped:
				return flip_table(user)
			else:
				return restore_table(user)
		_:
			return super.attack_hand(user, params)

func attackby(item, user, params = null) -> bool:
	"""Handle item interactions"""
	if not item or not user:
		return false
	
	# Handle construction/deconstruction
	if item.tool_behaviour == "wrench":
		return await deconstruct_table(user, item)
	
	return super.attackby(item, user, params)

func deconstruct_table(user, tool) -> bool:
	"""Deconstruct the table"""
	if is_flipped:
		show_user_message(user, "You need to restore the table first!")
		return false
	
	show_user_message(user, "You start deconstructing " + get_entity_name(self) + "...")
	
	# Play construction sound
	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager:
		audio_manager.play_positioned_sound("ratchet", global_position, 0.5)
	
	# Simulate work time
	await get_tree().create_timer(3.0).timeout
	
	# Create materials
	create_table_materials()
	
	# Remove from tilemap
	if table_tilemap:
		table_tilemap.erase_cell(0, tile_coord)
	
	# Disconnect from other tables
	var tables_to_disconnect = connected_tables.duplicate()
	for table in tables_to_disconnect:
		disconnect_from_table(table)
	
	show_user_message(user, "You deconstruct " + get_entity_name(self) + ".")
	
	# Remove self
	queue_free()
	return true

func create_table_materials():
	"""Create materials when table is deconstructed"""
	var material_scene = null
	
	match table_type:
		"metal":
			material_scene = preload("res://Items/Materials/MetalSheets.tscn")
		"wood":
			material_scene = preload("res://Items/Materials/WoodPlanks.tscn")
		"reinforced":
			material_scene = preload("res://Items/Materials/ReinforcedSheets.tscn")
	
	if material_scene:
		var material = material_scene.instantiate()
		get_parent().add_child(material)
		material.global_position = global_position

# DESTRUCTION HANDLING
func obj_destruction(damage_amount: float, damage_type: String, damage_flag: String, attacker = null):
	"""Handle table destruction"""
	# Throw items when destroyed
	if not is_flipped:
		var random_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
		throw_table_items(random_direction)
	
	# Remove from tilemap
	if table_tilemap:
		table_tilemap.erase_cell(0, tile_coord)
	
	# Disconnect from other tables
	var tables_to_disconnect = connected_tables.duplicate()
	for table in tables_to_disconnect:
		disconnect_from_table(table)
	
	super.obj_destruction(damage_amount, damage_type, damage_flag, attacker)

# UTILITY METHODS
func world_to_tile(world_pos: Vector2) -> Vector2i:
	"""Convert world position to tile coordinates"""
	var tile_size = Vector2i(32, 32)
	if table_tilemap and table_tilemap.tile_set:
		tile_size = table_tilemap.tile_set.tile_size
	
	return Vector2i(
		int(world_pos.x / tile_size.x),
		int(world_pos.y / tile_size.y)
	)

func tile_to_world(tile_pos: Vector2i) -> Vector2:
	"""Convert tile coordinates to world position"""
	var tile_size = Vector2i(32, 32)
	if table_tilemap and table_tilemap.tile_set:
		tile_size = table_tilemap.tile_set.tile_size
	
	return Vector2(
		tile_pos.x * tile_size.x + tile_size.x / 2,
		tile_pos.y * tile_size.y + tile_size.y / 2
	)

func get_user_network_id(user) -> String:
	"""Get network ID for user"""
	if not user:
		return ""
	
	if user.has_method("get_network_id"):
		return user.get_network_id()
	elif "peer_id" in user:
		return "player_" + str(user.peer_id)
	else:
		return user.get_path()

func find_user_by_network_id(network_id: String):
	"""Find user by network ID"""
	if network_id == "":
		return null
	
	if network_id.begins_with("player_"):
		var peer_id_str = network_id.split("_")[1]
		var peer_id_val = peer_id_str.to_int()
		var players = get_tree().get_nodes_in_group("players")
		for player in players:
			if "peer_id" in player and player.peer_id == peer_id_val:
				return player
	
	return get_node_or_null(network_id)
