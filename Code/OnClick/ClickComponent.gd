extends Node
class_name ClickComponent

# Signals for click events and interactions
signal tile_clicked(tile_coords: Vector2i, mouse_button: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool)
signal entity_clicked(entity: Node, mouse_button: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool)
signal combat_mode_changed(enabled: bool)

# Click behavior types
enum ClickType {
	NORMAL,
	SHIFT,
	CTRL,
	ALT,
	SHIFT_CTRL,
	SHIFT_ALT,
	CTRL_ALT,
	SHIFT_CTRL_ALT
}

# Drag states for mouse operations
enum DragState {
	NONE,
	DRAGGING,
	MIDDLE_DRAGGING
}

# Configuration constants
const TILE_SIZE = 32
const DOUBLE_CLICK_TIME = 0.3
const DRAG_START_DISTANCE = 5
const CLICK_COOLDOWN = 0.1

# Click tracking variables
var last_click_position: Vector2 = Vector2.ZERO
var last_click_time: float = 0.0
var last_click_button: int = -1
var click_start_position: Vector2 = Vector2.ZERO
var is_dragging: bool = false
var drag_state: int = DragState.NONE
var click_cooldown_timer: float = 0.0

# Entity and interaction tracking
var hover_entity: Node = null
var last_entity_clicked: Node = null

# Component references
var controller: Node = null
var world: Node = null
var inventory_system: Node = null
var interaction_component: Node = null
var weapon_handling_component: Node = null
var player_ui: Node = null

# Visual feedback elements
var drag_line: Line2D = null

func initialize(init_data: Dictionary):
	controller = init_data.get("controller")
	world = init_data.get("world")
	inventory_system = init_data.get("inventory_system")
	
	if controller:
		interaction_component = controller.get_node_or_null("InteractionComponent")
		weapon_handling_component = controller.get_node_or_null("WeaponHandlingComponent")
	
	setup_drag_line()

# Creates visual drag line for feedback
func setup_drag_line():
	drag_line = Line2D.new()
	drag_line.width = 2.0
	drag_line.default_color = Color(1, 1, 0, 0.7)
	drag_line.visible = false
	add_child(drag_line)

# Registers the PlayerUI component for click coordination
func register_player_ui(ui_instance: Node):
	player_ui = ui_instance

# Main input handler for mouse events
func _input(event: InputEvent):
	if not controller or not controller.is_local_player:
		return
	
	if should_ui_handle_event(event):
		return
	
	if event is InputEventMouseButton:
		handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		handle_mouse_motion(event)

# Determines if UI should handle the input event
func should_ui_handle_event(event: InputEvent) -> bool:
	if not event is InputEventMouseButton or not event.pressed:
		return false
	
	var mouse_pos = event.position
	
	if player_ui and player_ui.has_method("is_position_in_ui_element"):
		return player_ui.is_position_in_ui_element(mouse_pos)
	
	return is_clicking_on_ui(mouse_pos)

# Checks if mouse position is over UI elements
func is_clicking_on_ui(click_position: Vector2) -> bool:
	var ui_groups = ["ui_elements", "ui_buttons", "hud_elements", "interface", "menu"]
	
	for group_name in ui_groups:
		var nodes = get_tree().get_nodes_in_group(group_name)
		for node in nodes:
			if node is Control and node.visible and node.mouse_filter != Control.MOUSE_FILTER_IGNORE:
				if node.get_global_rect().has_point(click_position):
					return true
	
	return false

# Processes mouse button events
func handle_mouse_button(event: InputEventMouseButton):
	if click_cooldown_timer > 0:
		return
	
	var mouse_pos = event.position
	var shift_pressed = event.shift_pressed
	var ctrl_pressed = event.ctrl_pressed
	var alt_pressed = event.alt_pressed
	
	if event.pressed:
		handle_button_press(event.button_index, mouse_pos, shift_pressed, ctrl_pressed, alt_pressed)
	else:
		handle_button_release(event.button_index, mouse_pos, shift_pressed, ctrl_pressed, alt_pressed)

# Handles mouse button press events
func handle_button_press(button_index: int, mouse_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	click_start_position = mouse_pos
	last_click_button = button_index
	
	var world_pos = controller.get_global_mouse_position()
	var current_time = Time.get_ticks_msec() / 1000.0
	var is_double_click = false
	
	if button_index == last_click_button:
		var time_since_last_click = current_time - last_click_time
		var distance_from_last_click = mouse_pos.distance_to(last_click_position)
		
		if time_since_last_click < DOUBLE_CLICK_TIME and distance_from_last_click < 10:
			var current_target = get_entity_at_position(world_pos)
			if current_target == last_entity_clicked and current_target != null:
				is_double_click = true
	
	last_click_position = mouse_pos
	last_click_time = current_time
	
	match button_index:
		MOUSE_BUTTON_LEFT:
			if is_double_click:
				handle_double_left_click(world_pos, shift_pressed, ctrl_pressed, alt_pressed)
			else:
				handle_left_click_press(world_pos, shift_pressed, ctrl_pressed, alt_pressed)
		
		MOUSE_BUTTON_RIGHT:
			handle_right_click_press(world_pos, shift_pressed, ctrl_pressed, alt_pressed)
		
		MOUSE_BUTTON_MIDDLE:
			handle_middle_click_press(world_pos, shift_pressed, ctrl_pressed, alt_pressed)

# Handles left mouse button press
func handle_left_click_press(world_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	var click_target = get_entity_at_position(world_pos)
	
	# Check if we're wielding a weapon and this is a firing action
	if weapon_handling_component and weapon_handling_component.is_wielding_weapon():
		if not click_target or not is_special_weapon_click(shift_pressed, ctrl_pressed, alt_pressed):
			# This is a normal left click while wielding - start firing
			weapon_handling_component.start_firing()
			return
	
	if click_target:
		route_entity_click(click_target, MOUSE_BUTTON_LEFT, shift_pressed, ctrl_pressed, alt_pressed)
	else:
		var tile_pos = get_tile_at_position(world_pos)
		route_tile_click(tile_pos, MOUSE_BUTTON_LEFT, shift_pressed, ctrl_pressed, alt_pressed)

# Check if this is a special weapon interaction click
func is_special_weapon_click(shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool) -> bool:
	return shift_pressed or ctrl_pressed or alt_pressed

# Routes entity click to interaction component with weapon handling
func route_entity_click(entity: Node, button_index: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	if not entity:
		return
	
	emit_signal("entity_clicked", entity, button_index, shift_pressed, ctrl_pressed, alt_pressed)
	last_entity_clicked = entity
	
	# Check for weapon interactions first
	if is_weapon(entity) and weapon_handling_component:
		if handle_weapon_entity_click(entity, button_index, shift_pressed, ctrl_pressed, alt_pressed):
			return
	
	# Fall back to normal interaction component
	if interaction_component:
		interaction_component.process_interaction(entity, button_index, shift_pressed, ctrl_pressed, alt_pressed)

# Handle clicking on weapon entities with special modifiers
func handle_weapon_entity_click(weapon: Node, button_index: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool) -> bool:
	if button_index != MOUSE_BUTTON_LEFT:
		return false
	
	# Alt+click to cycle firing mode
	if alt_pressed and not shift_pressed and not ctrl_pressed:
		return weapon_handling_component.handle_weapon_alt_click(weapon)
	
	# Ctrl+click to eject magazine to floor
	if ctrl_pressed and not shift_pressed and not alt_pressed:
		return weapon_handling_component.handle_weapon_ctrl_click(weapon)
	
	# Check for reload interactions
	if not shift_pressed and not ctrl_pressed and not alt_pressed:
		return handle_weapon_reload_interaction(weapon)
	
	return false

# Handle weapon reload interactions
func handle_weapon_reload_interaction(weapon: Node) -> bool:
	if not inventory_system or not weapon_handling_component:
		return false
	
	# Get active item
	var active_item = inventory_system.get_active_item()
	
	# If holding a magazine, try to reload the weapon
	if active_item and is_magazine(active_item):
		return weapon_handling_component.handle_weapon_click_with_magazine(weapon, active_item)
	
	# If holding nothing, try to extract magazine from weapon
	if not active_item:
		return weapon_handling_component.handle_weapon_click_with_empty_hand(weapon)
	
	return false

# Routes tile click to interaction component
func route_tile_click(tile_coords: Vector2i, button_index: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	emit_signal("tile_clicked", tile_coords, button_index, shift_pressed, ctrl_pressed, alt_pressed)
	
	# Check if we're wielding a weapon and this is a firing action
	if weapon_handling_component and weapon_handling_component.is_wielding_weapon():
		if button_index == MOUSE_BUTTON_LEFT and not is_special_weapon_click(shift_pressed, ctrl_pressed, alt_pressed):
			# Fire weapon at tile
			var world_pos = tile_to_world(tile_coords)
			weapon_handling_component.fire_weapon_at_position(weapon_handling_component.get_wielded_weapon(), world_pos)
			return
	
	if interaction_component:
		interaction_component.handle_tile_click(tile_coords, button_index, shift_pressed, ctrl_pressed, alt_pressed)

# Handles right mouse button press
func handle_right_click_press(world_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	var click_target = get_entity_at_position(world_pos)
	
	if click_target:
		route_entity_click(click_target, MOUSE_BUTTON_RIGHT, shift_pressed, ctrl_pressed, alt_pressed)
	else:
		var tile_pos = get_tile_at_position(world_pos)
		route_tile_click(tile_pos, MOUSE_BUTTON_RIGHT, shift_pressed, ctrl_pressed, alt_pressed)

# Handles middle mouse button press
func handle_middle_click_press(world_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	var click_target = get_entity_at_position(world_pos)
	
	if click_target:
		route_entity_click(click_target, MOUSE_BUTTON_MIDDLE, shift_pressed, ctrl_pressed, alt_pressed)
	else:
		var tile_pos = get_tile_at_position(world_pos)
		route_tile_click(tile_pos, MOUSE_BUTTON_MIDDLE, shift_pressed, ctrl_pressed, alt_pressed)

# Handles double left click events
func handle_double_left_click(world_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	var click_target = get_entity_at_position(world_pos)
	
	if click_target and controller.has_method("is_adjacent_to") and controller.is_adjacent_to(click_target):
		if controller.has_method("attack_self"):
			controller.attack_self()
		
		if click_target.has_method("double_click"):
			click_target.double_click(controller)

# Handles mouse button release events
func handle_button_release(button_index: int, mouse_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	var distance_moved = mouse_pos.distance_to(click_start_position)
	
	match button_index:
		MOUSE_BUTTON_LEFT:
			# Handle weapon firing stop
			if weapon_handling_component and weapon_handling_component.is_wielding_weapon():
				weapon_handling_component.stop_firing()
			
			if not is_dragging or distance_moved < DRAG_START_DISTANCE:
				handle_left_click_release(mouse_pos, shift_pressed, ctrl_pressed, alt_pressed)
			else:
				end_drag(mouse_pos)
			is_dragging = false
		
		MOUSE_BUTTON_RIGHT:
			handle_right_click_release(mouse_pos, shift_pressed, ctrl_pressed, alt_pressed)
		
		MOUSE_BUTTON_MIDDLE:
			if drag_state == DragState.MIDDLE_DRAGGING:
				end_middle_drag(mouse_pos)
			else:
				handle_middle_click_release(mouse_pos, shift_pressed, ctrl_pressed, alt_pressed)
	
	reset_drag_state(button_index)
	click_cooldown_timer = CLICK_COOLDOWN

# Resets drag state after button release
func reset_drag_state(button_index: int):
	if button_index == MOUSE_BUTTON_LEFT and drag_state == DragState.DRAGGING:
		drag_state = DragState.NONE
		drag_line.visible = false
	
	if button_index == MOUSE_BUTTON_MIDDLE and drag_state == DragState.MIDDLE_DRAGGING:
		drag_state = DragState.NONE
		drag_line.visible = false

# Handles left click release events
func handle_left_click_release(mouse_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	pass

# Handles right click release events
func handle_right_click_release(mouse_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	pass

# Handles middle click release events
func handle_middle_click_release(mouse_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	if controller and controller.has_method("swap_active_hand"):
		# Don't allow hand swapping while wielding weapon
		if weapon_handling_component and not weapon_handling_component.can_switch_hands_currently():
			return
		controller.swap_active_hand()

# Processes mouse motion events
func handle_mouse_motion(event: InputEventMouseMotion):
	if drag_state != DragState.NONE:
		if drag_state == DragState.DRAGGING and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			handle_drag(event.position)
		elif drag_state == DragState.MIDDLE_DRAGGING and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			handle_middle_drag(event.position)
	
	update_hover_entity()

# Handles drag operations
func handle_drag(mouse_pos: Vector2):
	if not is_dragging:
		var distance = mouse_pos.distance_to(click_start_position)
		if distance > DRAG_START_DISTANCE:
			is_dragging = true
			drag_state = DragState.DRAGGING
			setup_drag_visual(click_start_position, mouse_pos)
	
	if is_dragging and drag_line.get_point_count() >= 2:
		drag_line.set_point_position(1, mouse_pos)

# Handles middle mouse drag operations
func handle_middle_drag(mouse_pos: Vector2):
	if drag_line.visible and drag_line.get_point_count() >= 2:
		drag_line.set_point_position(1, mouse_pos)

# Sets up visual feedback for dragging
func setup_drag_visual(start_pos: Vector2, end_pos: Vector2):
	drag_line.clear_points()
	drag_line.add_point(start_pos)
	drag_line.add_point(end_pos)
	drag_line.visible = true

# Ends drag operation
func end_drag(mouse_pos: Vector2):
	drag_line.visible = false
	is_dragging = false

# Ends middle drag operation
func end_middle_drag(mouse_pos: Vector2):
	drag_line.visible = false

# Updates hover entity tracking
func update_hover_entity():
	var mouse_pos = controller.get_global_mouse_position()
	var entity = get_entity_at_position(mouse_pos)
	
	if entity != hover_entity:
		if hover_entity and hover_entity.has_method("set_highlighted"):
			hover_entity.set_highlighted(false)
		
		hover_entity = entity
		
		if hover_entity and hover_entity.has_method("set_highlighted"):
			hover_entity.set_highlighted(true)

# Finds the best entity at a given position
func get_entity_at_position(world_pos: Vector2) -> Node:
	var candidates = []
	var max_distance = 20.0
	
	var clickables = get_tree().get_nodes_in_group("clickable_entities")
	
	for entity in clickables:
		if not is_instance_valid(entity):
			continue
		
		var entity_pos = Vector2.ZERO
		if "global_position" in entity:
			entity_pos = entity.global_position
		elif "position" in entity:
			entity_pos = entity.position
		else:
			continue
		
		var distance = world_pos.distance_to(entity_pos)
		if distance <= max_distance:
			candidates.append({
				"entity": entity,
				"distance": distance,
				"priority": get_entity_click_priority(entity)
			})
	
	if candidates.size() == 0:
		return null
	
	candidates.sort_custom(func(a, b): 
		if a.priority != b.priority:
			return a.priority > b.priority
		return a.distance < b.distance
	)
	
	return candidates[0].entity

# Calculates click priority for entities
func get_entity_click_priority(entity: Node) -> int:
	var priority = 0
	
	if "click_priority" in entity:
		priority = entity.click_priority
	elif entity.has_meta("click_priority"):
		priority = entity.get_meta("click_priority")
	
	if "entity_type" in entity:
		match entity.entity_type:
			"character", "mob":
				priority += 20
			"gun", "weapon":
				priority += 18  # High priority for weapons
			"item":
				priority += 10
			"structure":
				priority += 5
	
	if entity.has_meta("is_npc") and entity.get_meta("is_npc"):
		priority += 15
	
	if "pickupable" in entity and entity.pickupable:
		priority += 15
	
	if entity.has_method("interact") or entity.has_method("attack_hand"):
		priority += 5
	
	# Boost priority for weapons to make them easier to click
	if is_weapon(entity):
		priority += 25
	
	return priority

# Utility functions for item type checking
func is_weapon(item: Node) -> bool:
	if not item:
		return false
	
	# Check if item extends Gun class or has weapon methods
	if item.get_script():
		var script_path = str(item.get_script().get_path())
		if "Gun" in script_path or "Weapon" in script_path:
			return true
	
	# Check for weapon-specific methods
	if item.has_method("fire_gun") or item.has_method("fire_weapon") or item.has_method("use_weapon"):
		return true
	
	# Check entity type
	if "entity_type" in item and item.entity_type == "gun":
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

# Converts world position to tile coordinates
func get_tile_at_position(world_pos: Vector2) -> Vector2i:
	var tile_x = int(world_pos.x / TILE_SIZE)
	var tile_y = int(world_pos.y / TILE_SIZE)
	return Vector2i(tile_x, tile_y)

# Converts tile position to world coordinates
func tile_to_world(tile_pos: Vector2i) -> Vector2:
	return Vector2(
		(tile_pos.x * TILE_SIZE) + (TILE_SIZE / 2.0),
		(tile_pos.y * TILE_SIZE) + (TILE_SIZE / 2.0)
	)

# Updates component state each frame
func _process(delta: float):
	if click_cooldown_timer > 0:
		click_cooldown_timer -= delta
