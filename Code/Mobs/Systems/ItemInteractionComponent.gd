extends Node
class_name ItemInteractionComponent

## Handles item pickup, drop, throw, and inventory interactions

#region CONSTANTS
const PICKUP_RANGE: float = 1.5  # tiles
const THROW_RANGE_BASE: float = 10.0  # tiles
const MIN_THROW_DISTANCE: float = 1.0  # tiles
const DROP_DISTANCE: float = 0.5  # tiles
const THROW_COOLDOWN_DURATION: float = 0.5
#endregion

#region SIGNALS
signal item_picked_up(item: Node)
signal item_dropped(item: Node)
signal item_thrown(item: Node, target_position: Vector2)
signal throw_mode_changed(enabled: bool)
signal throw_trajectory_updated(trajectory: Array)
signal active_hand_changed(hand_index: int, item: Node)
#endregion

#region PROPERTIES
# Core references
var controller: Node = null
var inventory_system = null
var sensory_system = null
var audio_system = null
var world = null
var tile_occupancy_system = null

# Throw mode state
var throw_mode: bool = false
var is_throw_mode_active: bool = false
var throw_target_item: Node = null
var throw_trajectory: Array = []
var throw_power: float = 1.0
var throw_toggle_cooldown: float = 0.0

# Item interaction state
var active_hand_index: int = 0
var held_items: Array = [null, null]
#endregion

func initialize(init_data: Dictionary):
	"""Initialize the item interaction component"""
	controller = init_data.get("controller")
	inventory_system = init_data.get("inventory_system")
	sensory_system = init_data.get("sensory_system")
	audio_system = init_data.get("audio_system")
	world = init_data.get("world")
	tile_occupancy_system = init_data.get("tile_occupancy_system")
	
	# Initialize held items array
	held_items = [null, null]

func _process(delta: float):
	"""Update throw mode cooldown"""
	if throw_toggle_cooldown > 0:
		throw_toggle_cooldown -= delta
	
	# Update throw trajectory if in throw mode
	if is_throw_mode_active and throw_target_item:
		update_throw_trajectory()

#region ITEM PICKUP
func try_pick_up_item(item: Node) -> bool:
	"""Attempt to pick up an item"""
	if not item:
		return false
	
	# Verify inventory system
	if not find_inventory_system():
		show_message("ERROR: No inventory system found!")
		return false
	
	# Check if pickupable
	if not ("pickupable" in item and item.pickupable):
		show_message("You can't pick that up.")
		return false
	
	# Check distance
	var distance = controller.position.distance_to(item.position)
	if distance > PICKUP_RANGE * 32:  # Convert to pixels
		show_message("That's too far away.")
		return false
	
	# Face the item
	if controller.interaction_component:
		controller.interaction_component.face_entity(item)
	
	# Try to pick up
	if inventory_system.has_method("pick_up_item"):
		var success = inventory_system.pick_up_item(item)
		
		if success:
			# Play sound
			if audio_system:
				audio_system.play_positioned_sound("pickup", controller.position, 0.3)
			
			# Show message
			var item_name = item.item_name if "item_name" in item else item.name
			show_message("You pick up " + item_name + ".")
			
			# Emit signal
			emit_signal("item_picked_up", item)
			
			# Update UI
			force_ui_refresh()
			
			return true
		else:
			show_message("Your hands are full!")
			return false
	
	return false

func try_pickup_nearest_item() -> bool:
	"""Pick up the nearest item within range"""
	var nearest_item = null
	var nearest_distance = PICKUP_RANGE * 32
	
	# Get nearby items
	var nearby_items = get_items_in_radius(controller.position, nearest_distance)
	
	# Find closest pickupable
	for item in nearby_items:
		if not is_instance_valid(item):
			continue
		
		if not ("pickupable" in item and item.pickupable):
			continue
		
		var distance = controller.position.distance_to(item.position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_item = item
	
	# Pick up if found
	if nearest_item:
		return try_pick_up_item(nearest_item)
	else:
		show_message("There's nothing nearby to pick up.")
		return false
#endregion

#region ITEM DROP
func drop_active_item(throw_force: float = 0.0) -> bool:
	"""Drop the currently held item"""
	var active_item = get_active_item()
	if not active_item:
		return false
	
	# Calculate drop position
	var drop_dir = get_drop_direction()
	var drop_pos = controller.position + drop_dir * 32.0 * DROP_DISTANCE
	
	# Prepare item
	active_item.global_position = drop_pos
	
	# Handle drop/throw
	if inventory_system:
		var slot = get_item_slot(active_item)
		
		if throw_force > 0.0:
			# Throwing
			inventory_system.unequip_item(slot)
			
			if active_item.has_method("apply_throw_force"):
				active_item.apply_throw_force(drop_dir, throw_force * 100.0, controller)
			elif active_item.has_method("throw"):
				active_item.throw(controller, drop_dir)
			
			if audio_system:
				audio_system.play_positioned_sound("throw", controller.position, 0.4)
		else:
			# Normal drop
			var success = false
			if slot != 0:
				success = inventory_system.drop_item(slot)
			else:
				success = inventory_system.drop_item(active_item)
			
			if not success:
				return false
			
			if audio_system:
				audio_system.play_positioned_sound("drop", controller.position, 0.3)
		
		# Message
		var item_name = active_item.item_name if "item_name" in active_item else active_item.name
		var action = "drop" if throw_force <= 0.0 else "toss"
		show_message("You " + action + " " + item_name + ".")
		
		# Emit signal
		emit_signal("item_dropped", active_item)
		
		# Update UI
		force_ui_refresh()
		
		return true
	
	return false

func get_drop_direction() -> Vector2:
	"""Get direction to drop items based on facing"""
	if not controller.movement_component:
		return Vector2.DOWN
	
	var drop_dir = Vector2.DOWN
	
	match controller.movement_component.current_direction:
		0: # NORTH
			drop_dir = Vector2(0, -1)
		1: # EAST
			drop_dir = Vector2(1, 0)
		2: # SOUTH
			drop_dir = Vector2(0, 1)
		3: # WEST
			drop_dir = Vector2(-1, 0)
		4: # NORTHEAST
			drop_dir = Vector2(1, -1).normalized()
		5: # SOUTHEAST
			drop_dir = Vector2(1, 1).normalized()
		6: # SOUTHWEST
			drop_dir = Vector2(-1, 1).normalized()
		7: # NORTHWEST
			drop_dir = Vector2(-1, -1).normalized()
	
	return drop_dir
#endregion

#region THROW MODE
func toggle_throw_mode() -> bool:
	"""Toggle throw mode on/off"""
	if throw_toggle_cooldown > 0:
		return false
	
	if not find_inventory_system():
		show_message("ERROR: No inventory system found!")
		return false
	
	throw_mode = not throw_mode
	
	var active_item = get_active_item()
	
	if throw_mode:
		# Don't enter if no item
		if not active_item:
			throw_mode = false
			show_message("You have nothing to throw!")
			return false
		
		# Activate throw mode
		is_throw_mode_active = true
		throw_target_item = active_item
		
		show_message("You prepare to throw " + get_item_name(active_item) + ".")
		
		# Update trajectory
		update_throw_trajectory()
		
		# Update cursor
		var cursor_controller = controller.get_parent().get_node_or_null("CursorController")
		if cursor_controller and cursor_controller.has_method("set_cursor_mode"):
			cursor_controller.set_cursor_mode("throw")
		
		# Highlight item
		if active_item.has_method("set_highlighted"):
			active_item.set_highlighted(true)
		
		throw_toggle_cooldown = THROW_COOLDOWN_DURATION
		
		emit_signal("throw_mode_changed", true)
		return true
	else:
		exit_throw_mode()
		return false

func exit_throw_mode():
	"""Exit throw mode"""
	if not is_throw_mode_active:
		return
	
	is_throw_mode_active = false
	throw_mode = false
	
	# Remove highlight
	if throw_target_item:
		if throw_target_item.has_method("set_highlighted"):
			throw_target_item.set_highlighted(false)
	
	throw_target_item = null
	
	# Clear trajectory
	emit_signal("throw_trajectory_updated", [])
	
	# Reset cursor
	var cursor_controller = controller.get_parent().get_node_or_null("CursorController")
	if cursor_controller and cursor_controller.has_method("set_cursor_mode"):
		cursor_controller.set_cursor_mode("default")
	
	show_message("You relax your throwing arm.")
	
	emit_signal("throw_mode_changed", false)

func update_throw_trajectory():
	"""Update throw trajectory visualization"""
	if not is_throw_mode_active or not throw_target_item:
		return
	
	# Get mouse position
	var mouse_world_pos = controller.get_global_mouse_position()
	
	# Calculate max throw distance
	var max_throw_dist = calculate_max_throw_distance()
	
	# Limit to max distance
	var direction = (mouse_world_pos - controller.position).normalized()
	var distance = controller.position.distance_to(mouse_world_pos)
	
	if distance > max_throw_dist:
		mouse_world_pos = controller.position + direction * max_throw_dist
	
	# Check for collisions
	var final_position = check_throw_path(controller.position, mouse_world_pos)
	
	# Calculate trajectory points
	var trajectory = calculate_trajectory_points(controller.position, final_position)
	
	emit_signal("throw_trajectory_updated", trajectory)

func throw_at_tile(tile_coords: Vector2i) -> bool:
	"""Throw held item at tile position"""
	if not is_throw_mode_active or not throw_target_item:
		return false
	
	var world_position = tile_to_world(tile_coords)
	return throw_item_at_position(throw_target_item, world_position)

func throw_item_at_position(item: Node, world_position: Vector2) -> bool:
	"""Throw an item at a world position"""
	if not item or not inventory_system:
		return false
	
	# Face target
	if controller.interaction_component:
		controller.interaction_component.face_entity(world_position)
	
	# Save position
	var original_position = controller.position
	
	# Get item slot
	var slot = get_item_slot(item)
	
	# Remove from inventory
	if slot != 0:
		inventory_system.unequip_item(slot)
	else:
		inventory_system.remove_item(item)
	
	# Find landing position
	var landing_position = find_throw_landing_position(original_position, world_position)
	
	# Perform throw
	var success = false
	if item.has_method("throw_at_target"):
		item.throw_at_target(controller, landing_position)
		success = true
	elif item.has_method("throw"):
		var direction = (landing_position - original_position).normalized()
		item.throw(controller, direction)
		success = true
	
	if success:
		# Play sound
		if audio_system:
			audio_system.play_positioned_sound("throw", controller.position, 0.4)
		
		# Visual feedback
		var item_name = get_item_name(item)
		show_message("You throw " + item_name + "!")
		
		# Exit throw mode
		exit_throw_mode()
		
		emit_signal("item_thrown", item, landing_position)
	
	return success
#endregion

#region THROW HELPERS
func calculate_max_throw_distance() -> float:
	"""Calculate maximum throw distance"""
	var max_dist = THROW_RANGE_BASE * 32  # Convert to pixels
	
	# Get strength modifier
	var strength_modifier = 1.0
	var stats_system = controller.get_parent().get_node_or_null("StatsSystem")
	if stats_system and stats_system.has_method("get_throw_strength_multiplier"):
		strength_modifier = stats_system.get_throw_strength_multiplier()
	
	max_dist *= max(strength_modifier, 0.5)
	
	# Apply item mass penalty
	if throw_target_item and "mass" in throw_target_item and throw_target_item.mass > 0:
		var mass_penalty = clamp(1.0 - (throw_target_item.mass - 1.0) * 0.05, 0.2, 1.0)
		max_dist *= mass_penalty
	
	# Apply item's own modifiers
	if throw_target_item:
		if "throw_range_multiplier" in throw_target_item:
			max_dist *= throw_target_item.throw_range_multiplier
		
		if "throw_range" in throw_target_item and throw_target_item.throw_range > 0:
			var item_max = throw_target_item.throw_range * 32
			max_dist = min(max_dist, item_max)
	
	return max_dist

func check_throw_path(start_pos: Vector2, end_pos: Vector2) -> Vector2:
	"""Check throw path for obstacles"""
	if not controller.movement_component:
		return end_pos
	
	var start_tile = world_to_tile(start_pos)
	var end_tile = world_to_tile(end_pos)
	
	var path_tiles = get_line_tiles(start_tile, end_tile)
	
	# Skip starting tile
	if path_tiles.size() > 1:
		path_tiles.remove_at(0)
	
	# Check each tile
	for tile_pos in path_tiles:
		if is_tile_blocking_throw(tile_pos):
			var index = path_tiles.find(tile_pos)
			if index > 0:
				var landing_tile = path_tiles[index - 1]
				return tile_to_world(landing_tile)
			else:
				return start_pos
	
	return end_pos

func find_throw_landing_position(start_pos: Vector2, target_pos: Vector2) -> Vector2:
	"""Find where thrown item will land"""
	return check_throw_path(start_pos, target_pos)

func is_tile_blocking_throw(tile_pos: Vector2i) -> bool:
	"""Check if tile blocks thrown items"""
	var z_level = controller.current_z_level if controller else 0
	
	# Check walls
	if world and world.has_method("is_wall_at") and world.is_wall_at(tile_pos, z_level):
		return true
	
	# Check closed doors
	if world and world.has_method("is_closed_door_at") and world.is_closed_door_at(tile_pos, z_level):
		return true
	
	# Check windows
	if world and world.has_method("is_window_at") and world.is_window_at(tile_pos, z_level):
		return true
	
	# Check dense entities
	if tile_occupancy_system and tile_occupancy_system.has_dense_entity_at(tile_pos, z_level, controller):
		return true
	
	return false

func calculate_trajectory_points(start_pos: Vector2, end_pos: Vector2) -> Array:
	"""Calculate trajectory arc points"""
	var trajectory = []
	var segments = 20
	var distance = start_pos.distance_to(end_pos)
	var arc_height = min(distance * 0.2, 32.0)
	
	for i in range(segments + 1):
		var t = float(i) / segments
		
		var x = lerp(start_pos.x, end_pos.x, t)
		var y = lerp(start_pos.y, end_pos.y, t)
		
		# Add arc
		var height_offset = 4.0 * arc_height * t * (1.0 - t)
		y += -height_offset  # Negative for upward arc
		
		trajectory.append(Vector2(x, y))
	
	return trajectory

func get_line_tiles(start: Vector2i, end: Vector2i) -> Array:
	"""Get tiles along a line (Bresenham's algorithm)"""
	var tiles = []
	
	var x0 = start.x
	var y0 = start.y
	var x1 = end.x
	var y1 = end.y
	
	var dx = abs(x1 - x0)
	var dy = abs(y1 - y0)
	var sx = 1 if x0 < x1 else -1
	var sy = 1 if y0 < y1 else -1
	var err = dx - dy
	
	tiles.append(Vector2i(x0, y0))
	
	while x0 != x1 or y0 != y1:
		var e2 = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy
		
		tiles.append(Vector2i(x0, y0))
	
	return tiles
#endregion

#region HAND MANAGEMENT
func swap_active_hand() -> int:
	"""Swap between hands"""
	active_hand_index = 1 - active_hand_index
	
	var active_item = get_active_item()
	
	emit_signal("active_hand_changed", active_hand_index, active_item)
	
	var hand_name = "right" if active_hand_index == 0 else "left"
	if active_item:
		show_message("You switch to your " + hand_name + " hand (" + get_item_name(active_item) + ").")
	else:
		show_message("You switch to your " + hand_name + " hand.")
	
	return active_hand_index

func get_active_item() -> Node:
	"""Get currently held item"""
	if inventory_system and inventory_system.has_method("get_active_item"):
		return inventory_system.get_active_item()
	
	if held_items.size() > active_hand_index:
		return held_items[active_hand_index]
	
	return null

func get_item_in_hand(hand_index: int) -> Node:
	"""Get item in specific hand"""
	if inventory_system and inventory_system.has_method("get_item_in_slot"):
		var slot = 2 if hand_index == 0 else 1  # RIGHT_HAND : LEFT_HAND
		return inventory_system.get_item_in_slot(slot)
	
	if held_items.size() > hand_index:
		return held_items[hand_index]
	
	return null
#endregion

#region HELPERS
func find_inventory_system() -> bool:
	"""Find inventory system if not referenced"""
	if inventory_system:
		return true
	
	# Try multiple locations
	inventory_system = controller.get_node_or_null("InventorySystem")
	if inventory_system:
		return true
	
	inventory_system = controller.get_parent().get_node_or_null("InventorySystem")
	if inventory_system:
		return true
	
	if controller.get_parent().has_method("get_inventory_system"):
		inventory_system = controller.get_parent().get_inventory_system()
		if inventory_system:
			return true
	
	return false

func get_items_in_radius(center: Vector2, radius: float) -> Array:
	"""Get all items within radius"""
	var items = []
	
	if world and world.has_method("get_entities_in_radius"):
		var z_level = controller.current_z_level if controller else 0
		var entities = world.get_entities_in_radius(center, radius, z_level)
		
		for entity in entities:
			if "entity_type" in entity and entity.entity_type == "item":
				items.append(entity)
	else:
		var all_items = controller.get_tree().get_nodes_in_group("items")
		for item in all_items:
			if item.global_position.distance_to(center) <= radius:
				items.append(item)
	
	return items

func get_item_slot(item: Node) -> int:
	"""Get inventory slot of item"""
	if inventory_system and inventory_system.has_method("get_item_slot"):
		return inventory_system.get_item_slot(item)
	
	# Check hands
	if held_items[0] == item:
		return 2  # RIGHT_HAND
	elif held_items[1] == item:
		return 1  # LEFT_HAND
	
	return 0  # NONE

func get_item_name(item: Node) -> String:
	"""Get display name for item"""
	if "item_name" in item:
		return item.item_name
	elif "name" in item:
		return item.name
	else:
		return "something"

func tile_to_world(tile_pos: Vector2i) -> Vector2:
	"""Convert tile to world position"""
	return Vector2((tile_pos.x * 32) + 16, (tile_pos.y * 32) + 16)

func world_to_tile(world_pos: Vector2) -> Vector2i:
	"""Convert world to tile position"""
	return Vector2i(int(world_pos.x / 32), int(world_pos.y / 32))

func show_message(text: String):
	"""Display message"""
	if sensory_system:
		sensory_system.display_message(text)

func force_ui_refresh():
	"""Force UI to refresh"""
	var ui = controller.get_node_or_null("../PlayerUI")
	if ui:
		if ui.has_method("force_ui_refresh"):
			ui.force_ui_refresh()
		elif ui.has_method("update_all_slots"):
			ui.update_all_slots()
			ui.update_active_hand()
#endregion
