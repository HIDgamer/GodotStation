extends Node
class_name ItemInteractionComponent

# Range and distance constants
const PICKUP_RANGE: float = 1.5
const THROW_RANGE_BASE: float = 10.0
const MIN_THROW_DISTANCE: float = 1.0
const DROP_DISTANCE: float = 0.5
const THROW_COOLDOWN_DURATION: float = 0.5

# Signals for item interaction events
signal item_picked_up(item: Node)
signal item_dropped(item: Node)
signal item_thrown(item: Node, target_position: Vector2)
signal throw_mode_changed(enabled: bool)
signal throw_trajectory_updated(trajectory: Array)
signal active_hand_changed(hand_index: int, item: Node)

# Component references
var controller: Node = null
var inventory_system: Node = null
var weapon_handling_component: Node = null
var sensory_system: Node = null
var audio_system: Node = null
var world: Node = null
var tile_occupancy_system: Node = null

# Throw mode state
@export var throw_mode: bool = false : set = _set_throw_mode
@export var is_throw_mode_active: bool = false : set = _set_throw_mode_active
@export var throw_target_item_id: String = "" : set = _set_throw_target_item_id
@export var active_hand_index: int = 0 : set = _set_active_hand_index

# Throw operation variables
var throw_trajectory: Array = []
var throw_power: float = 1.0
var throw_toggle_cooldown: float = 0.0
var cached_throw_target_item: Node = null

# Property setters with signal emission
func _set_throw_mode(value: bool):
	if throw_mode != value:
		throw_mode = value
		emit_signal("throw_mode_changed", throw_mode)

func _set_throw_mode_active(value: bool):
	if is_throw_mode_active != value:
		is_throw_mode_active = value
		emit_signal("throw_mode_changed", is_throw_mode_active)

func _set_throw_target_item_id(value: String):
	if throw_target_item_id != value:
		throw_target_item_id = value
		cached_throw_target_item = null

func _set_active_hand_index(value: int):
	if active_hand_index != value:
		active_hand_index = value
		var item = get_active_item()
		emit_signal("active_hand_changed", active_hand_index, item)

# Returns the currently targeted item for throwing
func get_throw_target_item() -> Node:
	if not cached_throw_target_item and throw_target_item_id != "":
		cached_throw_target_item = get_item_by_network_id(throw_target_item_id)
	return cached_throw_target_item

func initialize(init_data: Dictionary):
	controller = init_data.get("controller")
	inventory_system = init_data.get("inventory_system")
	sensory_system = init_data.get("sensory_system")
	audio_system = init_data.get("audio_system")
	world = init_data.get("world")
	tile_occupancy_system = init_data.get("tile_occupancy_system")
	
	# Get weapon handling component reference
	if controller:
		weapon_handling_component = controller.get_node_or_null("WeaponHandlingComponent")

# Updates throw trajectory and cooldowns each frame
func _process(delta: float):
	if throw_toggle_cooldown > 0:
		throw_toggle_cooldown -= delta
	
	if is_throw_mode_active and get_throw_target_item():
		update_throw_trajectory()

# Attempts to pick up an item from the world
func try_pick_up_item(item: Node) -> bool:
	if not item:
		return false
	
	if not find_inventory_system():
		show_message("ERROR: No inventory system found!")
		return false
	
	if not ("pickupable" in item and item.pickupable):
		show_message("You can't pick that up.")
		return false
	
	var distance = controller.position.distance_to(item.position)
	if distance > PICKUP_RANGE * 32:
		show_message("That's too far away.")
		return false
	
	face_towards_item(item)
	
	var success = inventory_system.pick_up_item(item)
	
	if success:
		handle_successful_pickup(item)
		return true
	
	return false

# Handles successful item pickup
func handle_successful_pickup(item: Node):
	if audio_system:
		audio_system.play_positioned_sound("pickup", controller.position, 0.3)
	
	var item_name = get_item_name(item)
	var picker_name = get_entity_name(controller)
	show_message(picker_name + " picks up " + item_name + ".")
	
	emit_signal("item_picked_up", item)
	force_ui_refresh()
	
	var item_id = get_item_network_id(item)
	if item_id != "":
		sync_pickup_item.rpc(item_id, picker_name)

# Attempts to pick up the nearest item in range
func try_pickup_nearest_item() -> bool:
	var nearest_item = find_nearest_pickupable_item()
	
	if nearest_item:
		return try_pick_up_item(nearest_item)
	else:
		show_message("There's nothing nearby to pick up.")
		return false

# Finds the nearest pickupable item in range
func find_nearest_pickupable_item() -> Node:
	var nearest_item = null
	var nearest_distance = PICKUP_RANGE * 32
	
	var nearby_items = get_items_in_radius(controller.position, nearest_distance)
	
	for item in nearby_items:
		if not is_instance_valid(item):
			continue
		
		if not ("pickupable" in item and item.pickupable):
			continue
		
		var distance = controller.position.distance_to(item.position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_item = item
	
	return nearest_item

# Drops the currently active item
func drop_active_item(throw_force: float = 0.0) -> bool:
	if not find_inventory_system():
		return false
	
	var active_item = inventory_system.get_active_item()
	
	if not active_item:
		show_message("You have nothing to drop!")
		return false
	
	var drop_dir = get_drop_direction()
	var item_name = get_item_name(active_item)
	var dropper_name = get_entity_name(controller)
	
	var success = false
	
	if throw_force > 0.0:
		success = execute_throw_drop(active_item, drop_dir, throw_force, item_name, dropper_name)
	else:
		success = execute_normal_drop(active_item, drop_dir, item_name, dropper_name)
	
	if success:
		force_ui_refresh()
	
	return success

# Executes throw-based item drop
func execute_throw_drop(item: Node, drop_dir: Vector2, throw_force: float, item_name: String, dropper_name: String) -> bool:
	var success = inventory_system.throw_item(inventory_system.active_hand, drop_dir, throw_force)
	
	if success:
		if audio_system:
			audio_system.play_positioned_sound("throw", controller.position, 0.4)
		
		show_message(dropper_name + " throws " + item_name + "!")
		emit_signal("item_dropped", item)
		sync_drop_item.rpc(dropper_name, item_name, "throws")
	
	return success

# Executes normal item drop
func execute_normal_drop(item: Node, drop_dir: Vector2, item_name: String, dropper_name: String) -> bool:
	var result = inventory_system.drop_item(inventory_system.active_hand, drop_dir, false)
	
	if result == inventory_system.ITEM_UNEQUIP_DROPPED:
		if audio_system:
			audio_system.play_positioned_sound("drop", controller.position, 0.3)
		
		show_message(dropper_name + " drops " + item_name + ".")
		emit_signal("item_dropped", item)
		sync_drop_item.rpc(dropper_name, item_name, "drops")
		return true
	
	return false

# Calculates drop direction based on entity facing
func get_drop_direction() -> Vector2:
	if not controller.has_method("get_current_direction"):
		return Vector2.DOWN
	
	var current_direction = controller.get_current_direction()
	
	match current_direction:
		0: return Vector2(0, -1)
		1: return Vector2(1, 0)
		2: return Vector2(0, 1)
		3: return Vector2(-1, 0)
		4: return Vector2(1, -1).normalized()
		5: return Vector2(1, 1).normalized()
		6: return Vector2(-1, 1).normalized()
		7: return Vector2(-1, -1).normalized()
		_: return Vector2.DOWN

# Uses the currently active item
func use_active_item() -> bool:
	if not find_inventory_system():
		return false
	
	var active_item = inventory_system.get_active_item()
	if not active_item:
		return false
	
	# Check if item is a weapon and delegate to weapon handling component
	if is_weapon(active_item) and weapon_handling_component:
		return weapon_handling_component.handle_weapon_use(active_item)
	
	var item_name = get_item_name(active_item)
	var user_name = get_entity_name(controller)
	
	var success = await inventory_system.use_active_item()
	
	if success:
		handle_successful_use(user_name, item_name)
	
	return success

# Uses an item in a specific equipment slot
func use_item_in_slot(slot: int) -> bool:
	if not find_inventory_system():
		return false
	
	var item = inventory_system.get_item_in_slot(slot)
	if not item:
		return false
	
	# Check if item is a weapon and delegate to weapon handling component
	if is_weapon(item) and weapon_handling_component:
		return weapon_handling_component.handle_weapon_use(item)
	
	var item_name = get_item_name(item)
	var user_name = get_entity_name(controller)
	
	var used = await try_use_item_methods(item)
	
	if used:
		handle_successful_use(user_name, item_name)
	
	return used

# Attempts various use methods on an item
func try_use_item_methods(item: Node) -> bool:
	if item.has_method("use"):
		return await item.use(controller)
	elif item.has_method("interact"):
		return await item.interact(controller)
	elif item.has_method("attack_self"):
		return await item.attack_self(controller)
	
	return false

# Handles successful item use
func handle_successful_use(user_name: String, item_name: String):
	force_ui_refresh()
	show_message(user_name + " uses " + item_name + ".")
	
	var use_data = {
		"user_name": user_name,
		"item_name": item_name
	}
	sync_use_item.rpc(use_data)

# Toggles throw mode on and off
func toggle_throw_mode() -> bool:
	if throw_toggle_cooldown > 0:
		return false
	
	if not find_inventory_system():
		show_message("ERROR: No inventory system found!")
		return false
	
	var new_throw_mode = not throw_mode
	var active_item = inventory_system.get_active_item()
	var user_name = get_entity_name(controller)
	
	# Don't allow throw mode if weapon is wielded
	if weapon_handling_component and weapon_handling_component.is_wielding_weapon():
		show_message("You can't throw while wielding a weapon!")
		return false
	
	if new_throw_mode:
		return activate_throw_mode(active_item, user_name)
	else:
		deactivate_throw_mode(user_name)
		return true

# Activates throw mode with active item
func activate_throw_mode(active_item: Node, user_name: String) -> bool:
	if not active_item:
		show_message("You have nothing to throw!")
		return false
	
	# Don't allow throwing weapons
	if is_weapon(active_item):
		show_message("You can't throw weapons like that!")
		return false
	
	throw_mode = true
	is_throw_mode_active = true
	throw_target_item_id = get_item_network_id(active_item)
	cached_throw_target_item = active_item
	
	var item_name = get_item_name(active_item)
	show_message(user_name + " prepares to throw " + item_name + ".")
	
	setup_throw_mode_visuals(active_item)
	
	throw_toggle_cooldown = THROW_COOLDOWN_DURATION
	
	sync_throw_mode_toggle.rpc({
		"enable": true,
		"user_name": user_name,
		"item_name": item_name
	})
	
	return true

# Deactivates throw mode
func deactivate_throw_mode(user_name: String):
	_exit_throw_mode()
	
	sync_throw_mode_toggle.rpc({
		"enable": false,
		"user_name": user_name,
		"item_name": ""
	})

# Sets up visual elements for throw mode
func setup_throw_mode_visuals(active_item: Node):
	update_throw_trajectory()
	
	var cursor_controller = controller.get_parent().get_node_or_null("CursorController")
	if cursor_controller and cursor_controller.has_method("set_cursor_mode"):
		cursor_controller.set_cursor_mode("throw")
	
	if active_item and active_item.has_method("set_highlighted"):
		active_item.set_highlighted(true)

# Exits throw mode and cleans up
func _exit_throw_mode():
	if not is_throw_mode_active:
		return
	
	is_throw_mode_active = false
	throw_mode = false
	
	cleanup_throw_mode_visuals()
	
	throw_target_item_id = ""
	cached_throw_target_item = null
	
	emit_signal("throw_trajectory_updated", [])
	show_message("You relax your throwing arm.")

# Cleans up throw mode visual elements
func cleanup_throw_mode_visuals():
	var target_item = get_throw_target_item()
	if target_item and is_instance_valid(target_item):
		if target_item.has_method("set_highlighted"):
			target_item.set_highlighted(false)
	
	var cursor_controller = controller.get_parent().get_node_or_null("CursorController")
	if cursor_controller and cursor_controller.has_method("set_cursor_mode"):
		cursor_controller.set_cursor_mode("default")

# Updates throw trajectory visualization
func update_throw_trajectory():
	if not is_throw_mode_active:
		return
	
	var mouse_world_pos = controller.get_global_mouse_position()
	var max_throw_dist = calculate_max_throw_distance()
	
	var direction = (mouse_world_pos - controller.position).normalized()
	var distance = controller.position.distance_to(mouse_world_pos)
	
	if distance > max_throw_dist:
		mouse_world_pos = controller.position + direction * max_throw_dist
	
	var final_position = check_throw_path(controller.position, mouse_world_pos)
	var trajectory = calculate_trajectory_points(controller.position, final_position)
	
	emit_signal("throw_trajectory_updated", trajectory)
	
	sync_throw_trajectory.rpc({
		"trajectory": trajectory,
		"player_id": get_entity_name(controller),
		"start_pos": controller.position,
		"end_pos": final_position
	})

# Throws item at a specific tile
func throw_at_tile(tile_coords: Vector2i) -> bool:
	if not is_throw_mode_active:
		return false
	
	var world_position = tile_to_world(tile_coords)
	return throw_item_at_position(world_position)

# Throws item at a world position
func throw_item_at_position(world_position: Vector2) -> bool:
	if not is_throw_mode_active or not find_inventory_system():
		return false
	
	var active_item = inventory_system.get_active_item()
	if not active_item:
		return false
	
	var item_name = get_item_name(active_item)
	var thrower_name = get_entity_name(controller)
	
	face_towards_position(world_position)
	
	var success = inventory_system.throw_item_to_position(inventory_system.active_hand, world_position)
	
	if success:
		handle_successful_throw(thrower_name, item_name, world_position, active_item)
		return true
	
	return false

# Handles successful item throw
func handle_successful_throw(thrower_name: String, item_name: String, world_position: Vector2, item: Node):
	if audio_system:
		audio_system.play_positioned_sound("throw", controller.position, 0.4)
	
	show_message(thrower_name + " throws " + item_name + "!")
	
	_exit_throw_mode()
	
	emit_signal("item_thrown", item, world_position)
	force_ui_refresh()
	
	sync_throw_item.rpc(thrower_name, item_name, world_position)

# Swaps the active hand
func swap_active_hand() -> int:
	print("ItemInteractionComponent: swap_active_hand called")
	
	if not find_inventory_system():
		print("ItemInteractionComponent: No inventory system found")
		return 0
	
	# Check if hands are occupied by weapon wielding
	if weapon_handling_component and weapon_handling_component.is_hands_occupied():
		print("ItemInteractionComponent: Hands are occupied by weapon")
		show_message("You can't switch hands while wielding a weapon!")
		return active_hand_index
	
	print("ItemInteractionComponent: Calling inventory_system.switch_active_hand()")
	var new_hand = inventory_system.switch_active_hand()
	var new_hand_index = 0 if new_hand == inventory_system.EquipSlot.RIGHT_HAND else 1
	active_hand_index = new_hand_index
	
	var active_item = inventory_system.get_active_item()
	
	emit_signal("active_hand_changed", active_hand_index, active_item)
	
	handle_hand_swap_feedback(new_hand_index, active_item)
	
	return active_hand_index

# Handles feedback for hand swapping
func handle_hand_swap_feedback(hand_index: int, active_item: Node):
	var hand_name = "right" if hand_index == 0 else "left"
	var item_name = ""
	var user_name = get_entity_name(controller)
	
	if active_item:
		item_name = get_item_name(active_item)
		show_message(user_name + " switches to their " + hand_name + " hand (" + item_name + ").")
	else:
		show_message(user_name + " switches to their " + hand_name + " hand.")
	
	force_ui_refresh()
	sync_hand_swap.rpc(user_name, hand_name, item_name)

# Handle weapon interactions with other items
func handle_weapon_interaction_with_item(weapon: Node, target_item: Node) -> bool:
	if not weapon_handling_component:
		return false
	
	# Check if target item is a magazine
	if is_magazine(target_item):
		return weapon_handling_component.handle_weapon_click_with_magazine(weapon, target_item)
	
	return false

# Handle clicking weapon with empty hand
func handle_weapon_empty_hand_click(weapon: Node) -> bool:
	if not weapon_handling_component:
		return false
	
	return weapon_handling_component.handle_weapon_click_with_empty_hand(weapon)

# Handle special weapon UI interactions
func handle_weapon_alt_click(weapon: Node) -> bool:
	if not weapon_handling_component:
		return false
	
	return weapon_handling_component.handle_weapon_alt_click(weapon)

func handle_weapon_ctrl_click(weapon: Node) -> bool:
	if not weapon_handling_component:
		return false
	
	return weapon_handling_component.handle_weapon_ctrl_click(weapon)

# Returns the currently active item
func get_active_item() -> Node:
	if not find_inventory_system():
		return null
	
	return inventory_system.get_active_item()

# Returns item in specified hand
func get_item_in_hand(hand_index: int) -> Node:
	if not find_inventory_system():
		return null
	
	var slot = inventory_system.EquipSlot.RIGHT_HAND if hand_index == 0 else inventory_system.EquipSlot.LEFT_HAND
	return inventory_system.get_item_in_slot(slot)

# Checks throw path for obstacles and returns final position
func check_throw_path(start_pos: Vector2, end_pos: Vector2) -> Vector2:
	if not controller.has_method("get_current_tile_position"):
		return end_pos
	
	var start_tile = world_to_tile(start_pos)
	var end_tile = world_to_tile(end_pos)
	
	var path_tiles = get_line_tiles(start_tile, end_tile)
	
	if path_tiles.size() > 1:
		path_tiles.remove_at(0)
	
	for tile_pos in path_tiles:
		if is_tile_blocking_throw(tile_pos):
			var index = path_tiles.find(tile_pos)
			if index > 0:
				var landing_tile = path_tiles[index - 1]
				return tile_to_world(landing_tile)
			else:
				return start_pos
	
	return end_pos

# Checks if a tile blocks thrown items
func is_tile_blocking_throw(tile_pos: Vector2i) -> bool:
	var z_level = controller.current_z_level if "current_z_level" in controller else 0
	
	if world and world.has_method("is_wall_at") and world.is_wall_at(tile_pos, z_level):
		return true
	
	if world and world.has_method("is_closed_door_at") and world.is_closed_door_at(tile_pos, z_level):
		return true
	
	if world and world.has_method("is_window_at") and world.is_window_at(tile_pos, z_level):
		return true
	
	if tile_occupancy_system and tile_occupancy_system.has_method("has_dense_entity_at"):
		if tile_occupancy_system.has_dense_entity_at(tile_pos, z_level, controller):
			return true
	
	return false

# Calculates trajectory points for throw visualization
func calculate_trajectory_points(start_pos: Vector2, end_pos: Vector2) -> Array:
	var trajectory = []
	var segments = 20
	var distance = start_pos.distance_to(end_pos)
	var arc_height = min(distance * 0.2, 32.0)
	
	for i in range(segments + 1):
		var t = float(i) / segments
		
		var x = lerp(start_pos.x, end_pos.x, t)
		var y = lerp(start_pos.y, end_pos.y, t)
		
		var height_offset = 4.0 * arc_height * t * (1.0 - t)
		y += -height_offset
		
		trajectory.append(Vector2(x, y))
	
	return trajectory

# Generates line of tiles using Bresenham's algorithm
func get_line_tiles(start: Vector2i, end: Vector2i) -> Array:
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

# Utility functions for item type checking
func is_weapon(item: Node) -> bool:
	if not item:
		return false
	
	# Check entity type
	if item.entity_type == "gun":
		return true
	
	return false

func is_magazine(item: Node) -> bool:
	if not item:
		return false
	
	# Check script path
	if item.get_script():
		var script_path = str(item.get_script().get_path())
		if "Magazine" in script_path:
			return true
	
	# Check for magazine-specific properties
	if "ammo_type" in item and "current_ammo" in item:
		return true
	
	# Check entity type
	if "entity_type" in item and item.entity_type == "magazine":
		return true
	
	return false

# Network synchronization RPC functions
@rpc("any_peer", "call_local", "reliable")
func sync_pickup_item(item_network_id: String, picker_name: String):
	var item = get_item_by_network_id(item_network_id)
	if not item:
		return
	
	if audio_system:
		audio_system.play_positioned_sound("pickup", controller.position, 0.3)
	
	var item_name = get_item_name(item)
	show_message(picker_name + " picks up " + item_name + ".")

@rpc("any_peer", "call_local", "reliable")
func sync_drop_item(dropper_name: String, item_name: String, action: String):
	show_message(dropper_name + " " + action + " " + item_name + ".")

@rpc("any_peer", "call_local", "reliable")
func sync_use_item(use_data: Dictionary):
	var user_name = use_data.get("user_name", "Someone")
	var item_name = use_data.get("item_name", "something")
	
	show_message(user_name + " uses " + item_name + ".")

@rpc("any_peer", "call_local", "reliable")
func sync_throw_mode_toggle(toggle_data: Dictionary):
	var enable = toggle_data.get("enable", false)
	var user_name = toggle_data.get("user_name", "Someone")
	var item_name = toggle_data.get("item_name", "")
	
	if enable and item_name != "":
		show_message(user_name + " prepares to throw " + item_name + ".")
	else:
		show_message(user_name + " relaxes their throwing arm.")

@rpc("any_peer", "call_local", "reliable")
func sync_throw_trajectory(trajectory_data: Dictionary):
	var trajectory = trajectory_data.get("trajectory", [])
	var player_id = trajectory_data.get("player_id", "")
	
	if player_id != get_entity_name(controller):
		emit_signal("throw_trajectory_updated", trajectory)

@rpc("any_peer", "call_local", "reliable")
func sync_throw_item(thrower_name: String, item_name: String, world_position: Vector2):
	show_message(thrower_name + " throws " + item_name + "!")

@rpc("any_peer", "call_local", "reliable")
func sync_hand_swap(user_name: String, hand_name: String, item_name: String):
	if item_name != "":
		show_message(user_name + " switches to their " + hand_name + " hand (" + item_name + ").")
	else:
		show_message(user_name + " switches to their " + hand_name + " hand.")

# Network ID management functions
func get_item_network_id(item: Node) -> String:
	if not item:
		return ""
	
	if inventory_system and inventory_system.has_method("get_item_network_id"):
		return inventory_system.get_item_network_id(item)
	
	if item.has_method("get_network_id"):
		return item.get_network_id()
	elif "network_id" in item:
		return str(item.network_id)
	elif item.has_meta("network_id"):
		return str(item.get_meta("network_id"))
	
	var new_id = str(item.get_instance_id()) + "_" + str(Time.get_ticks_msec())
	item.set_meta("network_id", new_id)
	return new_id

func get_item_by_network_id(network_id: String) -> Node:
	if network_id == "":
		return null
	
	if inventory_system and inventory_system.has_method("find_item_by_network_id"):
		return inventory_system.find_item_by_network_id(network_id)
	
	if world and world.has_method("get_item_by_network_id"):
		return world.get_item_by_network_id(network_id)
	
	var all_items = get_tree().get_nodes_in_group("items")
	for item in all_items:
		if get_item_network_id(item) == network_id:
			return item
	
	return null

# Throw distance calculation
func calculate_max_throw_distance() -> float:
	var max_dist = THROW_RANGE_BASE * 32
	
	var strength_modifier = get_strength_modifier()
	max_dist *= max(strength_modifier, 0.5)
	
	var active_item = get_active_item()
	if active_item:
		max_dist = apply_item_throw_modifiers(max_dist, active_item)
	
	return max_dist

# Gets strength modifier for throwing
func get_strength_modifier() -> float:
	var stats_system = controller.get_parent().get_node_or_null("StatsSystem")
	if stats_system and stats_system.has_method("get_throw_strength_multiplier"):
		return stats_system.get_throw_strength_multiplier()
	return 1.0

# Applies item-specific throw distance modifiers
func apply_item_throw_modifiers(max_dist: float, item: Node) -> float:
	if "mass" in item and item.mass > 0:
		var mass_penalty = clamp(1.0 - (item.mass - 1.0) * 0.05, 0.2, 1.0)
		max_dist *= mass_penalty
	
	if "throw_range_multiplier" in item:
		max_dist *= item.throw_range_multiplier
	
	if "throw_range" in item and item.throw_range > 0:
		var item_max = item.throw_range * 32
		max_dist = min(max_dist, item_max)
	
	return max_dist

# Inventory system management
func find_inventory_system() -> bool:
	if inventory_system:
		return true
	
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
	
	for child in controller.get_children():
		if child.has_method("get_script") and child.get_script() and "InventorySystem" in str(child.get_script().get_path()):
			inventory_system = child
			return true
	
	return false

# Item search and utility functions
func get_items_in_radius(center: Vector2, radius: float) -> Array:
	var items = []
	
	if world and world.has_method("get_entities_in_radius"):
		var z_level = controller.current_z_level if "current_z_level" in controller else 0
		var entities = world.get_entities_in_radius(center, radius, z_level)
		
		for entity in entities:
			if is_item_entity(entity):
				items.append(entity)
	else:
		var all_items = controller.get_tree().get_nodes_in_group("items")
		for item in all_items:
			if item.global_position.distance_to(center) <= radius:
				items.append(item)
	
	return items

func is_item_entity(entity: Node) -> bool:
	if entity.has_method("get_script") and entity.get_script():
		var script = entity.get_script()
		return script and "Item" in str(script.get_path())
	return false

# Name and entity management
func get_entity_name(entity: Node) -> String:
	if "entity_name" in entity and entity.entity_name != "":
		return entity.entity_name
	elif "name" in entity:
		return entity.name
	else:
		return "someone"

func get_item_name(item: Node) -> String:
	if not item:
		return "nothing"
	
	if "item_name" in item:
		return item.item_name
	elif "name" in item:
		return item.name
	else:
		return "something"

# Coordinate conversion functions
func tile_to_world(tile_pos: Vector2i) -> Vector2:
	return Vector2((tile_pos.x * 32) + 16, (tile_pos.y * 32) + 16)

func world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x / 32), int(world_pos.y / 32))

# Entity facing functions
func face_towards_item(item: Node):
	if controller.has_method("face_entity"):
		controller.face_entity(item)
	elif controller.interaction_component and controller.interaction_component.has_method("face_entity"):
		controller.interaction_component.face_entity(item)

func face_towards_position(position: Vector2):
	if controller.has_method("face_entity"):
		controller.face_entity(position)
	elif controller.interaction_component and controller.interaction_component.has_method("face_entity"):
		controller.interaction_component.face_entity(position)

# UI and feedback functions
func show_message(text: String):
	if sensory_system:
		if sensory_system.has_method("display_message"):
			sensory_system.display_message(text)
		elif sensory_system.has_method("add_message"):
			sensory_system.add_message(text)

func force_ui_refresh():
	var ui = controller.get_node_or_null("PlayerUI")
	if ui:
		if ui.has_method("force_ui_refresh"):
			ui.force_ui_refresh()
		elif ui.has_method("update_all_slots"):
			ui.update_all_slots()
			if ui.has_method("update_active_hand"):
				ui.update_active_hand()
