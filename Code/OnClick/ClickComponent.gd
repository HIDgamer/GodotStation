extends Node
class_name ClickComponent

#region EXPORTS AND CONFIGURATION
@export_group("Click Settings")
@export var tile_size: int = 32
@export var double_click_time: float = 0.3
@export var drag_start_distance: float = 8.0
@export var click_cooldown: float = 0.1
@export var drag_hold_time: float = 0.2
@export var drop_target_radius: float = 48.0

@export_group("Drag Options")
@export var drag_enabled: bool = true
@export var shift_drag_enabled: bool = true
@export var hold_drag_enabled: bool = true
@export var alt_drag_enabled: bool = true

@export_group("Visual Feedback")
@export var drag_line_width: float = 2.0
@export var drag_line_color: Color = Color(1, 1, 0, 0.7)
@export var drop_indicator_color: Color = Color(0.8, 1.2, 0.8, 0.7)
#endregion

#region CONSTANTS AND ENUMS
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

enum DragState {
	NONE,
	PENDING,
	DRAGGING,
	MIDDLE_DRAGGING,
	DROP_TARGETING
}
#endregion

#region SIGNALS
signal tile_clicked(tile_coords: Vector2i, mouse_button: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool)
signal entity_clicked(entity: Node, mouse_button: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool)
signal drag_operation_started(entity: Node, drag_type: int)
signal drag_operation_ended(entity: Node, success: bool)
signal combat_mode_changed(enabled: bool)
#endregion

#region PROPERTIES
# Click tracking variables
var last_click_position: Vector2 = Vector2.ZERO
var last_click_time: float = 0.0
var last_click_button: int = -1
var click_start_position: Vector2 = Vector2.ZERO
var click_start_time: float = 0.0
var is_dragging: bool = false
var drag_state: int = DragState.NONE
var click_cooldown_timer: float = 0.0
var drag_hold_timer: float = 0.0

# Entity and interaction tracking
var hover_entity: Node = null
var last_entity_clicked: Node = null
var potential_drag_entity: Node = null
var drag_start_entity: Node = null

# Component references
var controller: Node = null
var world: Node = null
var inventory_system: Node = null
var interaction_component: Node = null
var weapon_handling_component: Node = null
var drag_drop_coordinator: Node = null
var player_ui: Node = null

# Visual feedback elements
var drag_line: Line2D = null
var drop_target_indicator: Sprite2D = null
#endregion

#region INITIALIZATION
func initialize(init_data: Dictionary):
	"""Initialize the click component with required dependencies"""
	controller = init_data.get("controller")
	world = init_data.get("world")
	inventory_system = init_data.get("inventory_system")
	
	if controller:
		interaction_component = controller.get_node_or_null("InteractionComponent")
		weapon_handling_component = controller.get_node_or_null("WeaponHandlingComponent")
		drag_drop_coordinator = controller.get_node_or_null("DragDropCoordinator")
	
	_setup_visual_feedback()
	_setup_drag_drop_integration()

func _setup_visual_feedback():
	"""Create visual feedback elements for drag operations"""
	drag_line = Line2D.new()
	drag_line.width = drag_line_width
	drag_line.default_color = drag_line_color
	drag_line.visible = false
	add_child(drag_line)
	
	drop_target_indicator = Sprite2D.new()
	drop_target_indicator.modulate = drop_indicator_color
	drop_target_indicator.visible = false
	add_child(drop_target_indicator)

func _setup_drag_drop_integration():
	"""Set up integration with drag-drop coordinator"""
	if drag_drop_coordinator:
		if not drag_drop_coordinator.is_connected("drag_started", _on_drag_started):
			drag_drop_coordinator.drag_started.connect(_on_drag_started)
		if not drag_drop_coordinator.is_connected("drag_ended", _on_drag_ended):
			drag_drop_coordinator.drag_ended.connect(_on_drag_ended)

func register_player_ui(ui_instance: Node):
	"""Register the PlayerUI component for click coordination"""
	player_ui = ui_instance
#endregion

#region INPUT PROCESSING
func _input(event: InputEvent):
	if not controller:
		return
	
	if _should_ui_handle_event(event):
		return
	
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

func _process(delta: float):
	_update_timers(delta)
	_update_hover_entity()

func _update_timers(delta: float):
	"""Update internal timers for cooldowns and drag operations"""
	if click_cooldown_timer > 0:
		click_cooldown_timer -= delta
	
	if drag_hold_timer > 0:
		drag_hold_timer -= delta
		if drag_hold_timer <= 0 and drag_state == DragState.PENDING:
			_attempt_hold_drag()
#endregion

#region MOUSE BUTTON HANDLING
func _handle_mouse_button(event: InputEventMouseButton):
	if click_cooldown_timer > 0:
		return
	
	var mouse_pos = event.position
	var shift_pressed = event.shift_pressed
	var ctrl_pressed = event.ctrl_pressed
	var alt_pressed = event.alt_pressed
	
	if event.pressed:
		_handle_button_press(event.button_index, mouse_pos, shift_pressed, ctrl_pressed, alt_pressed)
	else:
		_handle_button_release(event.button_index, mouse_pos, shift_pressed, ctrl_pressed, alt_pressed)

func _handle_button_press(button_index: int, mouse_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	click_start_position = mouse_pos
	click_start_time = Time.get_ticks_msec() / 1000.0
	last_click_button = button_index
	
	var world_pos = controller.get_global_mouse_position()
	var current_time = Time.get_ticks_msec() / 1000.0
	var is_double_click = _check_double_click(button_index, mouse_pos, current_time)
	
	match button_index:
		MOUSE_BUTTON_LEFT:
			if is_double_click:
				_handle_double_left_click(world_pos, shift_pressed, ctrl_pressed, alt_pressed)
			else:
				_handle_left_click_press(world_pos, shift_pressed, ctrl_pressed, alt_pressed)
		MOUSE_BUTTON_RIGHT:
			_handle_right_click_press(world_pos, shift_pressed, ctrl_pressed, alt_pressed)
		MOUSE_BUTTON_MIDDLE:
			_handle_middle_click_press(world_pos, shift_pressed, ctrl_pressed, alt_pressed)

func _handle_button_release(button_index: int, mouse_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	var distance_moved = mouse_pos.distance_to(click_start_position)
	
	match button_index:
		MOUSE_BUTTON_LEFT:
			_handle_left_click_release(mouse_pos, distance_moved, shift_pressed, ctrl_pressed, alt_pressed)
		MOUSE_BUTTON_RIGHT:
			_handle_right_click_release(mouse_pos, shift_pressed, ctrl_pressed, alt_pressed)
		MOUSE_BUTTON_MIDDLE:
			_handle_middle_click_release(mouse_pos, shift_pressed, ctrl_pressed, alt_pressed)
	
	_reset_drag_state(button_index)
	click_cooldown_timer = click_cooldown

func _check_double_click(button_index: int, mouse_pos: Vector2, current_time: float) -> bool:
	"""Check if this constitutes a double-click"""
	if button_index != last_click_button:
		return false
	
	var time_since_last_click = current_time - last_click_time
	var distance_from_last_click = mouse_pos.distance_to(last_click_position)
	
	last_click_position = mouse_pos
	last_click_time = current_time
	
	if time_since_last_click < double_click_time and distance_from_last_click < 10:
		var current_target = _get_entity_at_position(controller.get_global_mouse_position())
		if current_target == last_entity_clicked and current_target != null:
			return true
	
	return false
#endregion

#region LEFT CLICK HANDLING
func _handle_left_click_press(world_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	var click_target = _get_entity_at_position(world_pos)
	
	# Handle drag-specific interactions first
	if drag_enabled and click_target:
		potential_drag_entity = click_target
		
		if shift_pressed and shift_drag_enabled:
			_attempt_shift_drag(click_target, world_pos)
		elif alt_pressed and alt_drag_enabled:
			_attempt_alt_drag(click_target, world_pos)
		elif hold_drag_enabled:
			drag_state = DragState.PENDING
			drag_hold_timer = drag_hold_time
	
	# Handle weapons and normal interactions
	if click_target:
		if _is_weapon(click_target) and (shift_pressed or ctrl_pressed or alt_pressed):
			_route_entity_click(click_target, MOUSE_BUTTON_LEFT, shift_pressed, ctrl_pressed, alt_pressed)
			get_viewport().set_input_as_handled()
			return
		
		if weapon_handling_component and weapon_handling_component.is_wielding_weapon():
			if not _is_special_weapon_click(shift_pressed, ctrl_pressed, alt_pressed):
				weapon_handling_component._start_firing()
				return
		
		_route_entity_click(click_target, MOUSE_BUTTON_LEFT, shift_pressed, ctrl_pressed, alt_pressed)
	else:
		if weapon_handling_component and weapon_handling_component.is_wielding_weapon():
			if not _is_special_weapon_click(shift_pressed, ctrl_pressed, alt_pressed):
				weapon_handling_component._start_firing()
				return
		
		var tile_pos = _get_tile_at_position(world_pos)
		_route_tile_click(tile_pos, MOUSE_BUTTON_LEFT, shift_pressed, ctrl_pressed, alt_pressed)

func _handle_left_click_release(mouse_pos: Vector2, distance_moved: float, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	# Handle drag operation end
	if drag_state == DragState.DRAGGING and drag_drop_coordinator:
		var success = drag_drop_coordinator.end_drag_operation(true)
		emit_signal("drag_operation_ended", drag_start_entity, success)
		_cleanup_drag_visuals()
		return
	
	# Stop weapon firing
	if weapon_handling_component and weapon_handling_component.is_wielding_weapon():
		weapon_handling_component._stop_firing()
	
	# Handle normal click if no significant drag occurred
	if distance_moved < drag_start_distance and drag_state != DragState.DRAGGING:
		pass # This was a normal click, not a drag

func _handle_double_left_click(world_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	var click_target = _get_entity_at_position(world_pos)
	
	if click_target and controller.has_method("is_adjacent_to") and controller.is_adjacent_to(click_target):
		# Special double-click interactions
		if click_target.has_method("double_click"):
			click_target.double_click(controller)
		elif click_target.is_in_group("furniture") and click_target.has_method("buckle_self"):
			click_target.buckle_self(controller)
		elif controller.has_method("attack_self"):
			controller.attack_self()
#endregion

#region DRAG OPERATIONS
func _attempt_shift_drag(entity: Node, world_pos: Vector2) -> bool:
	"""Attempt to start shift-drag operation"""
	if not drag_drop_coordinator:
		return false
	
	var success = drag_drop_coordinator.start_drag_operation(entity, world_pos)
	
	if success:
		drag_state = DragState.DRAGGING
		drag_start_entity = entity
		_setup_drag_visual_feedback(world_pos)
		
		get_viewport().set_input_as_handled()
		emit_signal("drag_operation_started", entity, drag_drop_coordinator.get_current_drag_type())
	
	return success

func _attempt_hold_drag() -> bool:
	"""Attempt to start hold-drag operation"""
	if not potential_drag_entity or not drag_drop_coordinator:
		return false
	
	var world_pos = controller.get_global_mouse_position()
	var current_mouse_pos = get_viewport().get_mouse_position()
	var distance = current_mouse_pos.distance_to(click_start_position)
	
	# Only start hold-drag if mouse hasn't moved much
	if distance < drag_start_distance:
		var success = drag_drop_coordinator.start_drag_operation(potential_drag_entity, world_pos)
		
		if success:
			drag_state = DragState.DRAGGING
			drag_start_entity = potential_drag_entity
			_setup_drag_visual_feedback(world_pos)
			
			emit_signal("drag_operation_started", potential_drag_entity, drag_drop_coordinator.get_current_drag_type())
			return true
	
	# Clear pending state
	drag_state = DragState.NONE
	potential_drag_entity = null
	return false

func _attempt_alt_drag(entity: Node, world_pos: Vector2) -> bool:
	"""Attempt alt-drag for special interactions"""
	# Alt-drag can be used for special furniture interactions
	if entity.is_in_group("furniture") and entity.has_method("start_furniture_drag"):
		return entity.start_furniture_drag(controller)
	
	# Default to normal drag
	return _attempt_shift_drag(entity, world_pos)

func _setup_drag_visual_feedback(start_pos: Vector2):
	"""Set up visual feedback for drag operation"""
	drag_line.clear_points()
	drag_line.add_point(start_pos)
	drag_line.add_point(start_pos)
	drag_line.visible = true

func _cleanup_drag_visuals():
	"""Clean up drag visual feedback"""
	drag_line.visible = false
	drop_target_indicator.visible = false

func _reset_drag_state(button_index: int):
	"""Reset drag state after button release"""
	if button_index == MOUSE_BUTTON_LEFT:
		drag_state = DragState.NONE
		potential_drag_entity = null
		drag_start_entity = null
		drag_hold_timer = 0.0
#endregion

#region MOUSE MOTION HANDLING
func _handle_mouse_motion(event: InputEventMouseMotion):
	var current_mouse_pos = event.position
	
	# Update drag visuals if dragging
	if drag_state == DragState.DRAGGING and drag_line.visible:
		var world_pos = controller.get_global_mouse_position()
		if drag_line.get_point_count() >= 2:
			drag_line.set_point_position(1, world_pos)
		
		_update_drop_target_indicators(world_pos)
	
	# Check if we should cancel pending drag due to movement
	elif drag_state == DragState.PENDING:
		var distance = current_mouse_pos.distance_to(click_start_position)
		if distance > drag_start_distance:
			drag_state = DragState.NONE
			potential_drag_entity = null
			drag_hold_timer = 0.0

func _update_drop_target_indicators(world_pos: Vector2):
	"""Update drop target visual indicators"""
	if not drag_drop_coordinator:
		return
	
	# This is handled by the drag-drop coordinator
	# We just need to make sure our visuals are in sync
#endregion

#region RIGHT AND MIDDLE CLICK HANDLING
func _handle_right_click_press(world_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	var click_target = _get_entity_at_position(world_pos)
	
	if click_target:
		_route_entity_click(click_target, MOUSE_BUTTON_RIGHT, shift_pressed, ctrl_pressed, alt_pressed)
	else:
		var tile_pos = _get_tile_at_position(world_pos)
		_route_tile_click(tile_pos, MOUSE_BUTTON_RIGHT, shift_pressed, ctrl_pressed, alt_pressed)

func _handle_right_click_release(mouse_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	pass

func _handle_middle_click_press(world_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	var click_target = _get_entity_at_position(world_pos)
	
	if click_target:
		_route_entity_click(click_target, MOUSE_BUTTON_MIDDLE, shift_pressed, ctrl_pressed, alt_pressed)
	else:
		var tile_pos = _get_tile_at_position(world_pos)
		_route_tile_click(tile_pos, MOUSE_BUTTON_MIDDLE, shift_pressed, ctrl_pressed, alt_pressed)

func _handle_middle_click_release(mouse_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	if controller and controller.has_method("swap_active_hand"):
		# Don't allow hand swapping while wielding weapon or dragging
		if weapon_handling_component and not weapon_handling_component.can_switch_hands_currently():
			return
		
		if drag_state != DragState.NONE:
			return
		
		controller.swap_active_hand()
#endregion

#region INTERACTION ROUTING
func _route_entity_click(entity: Node, button_index: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	if not entity:
		return
	
	emit_signal("entity_clicked", entity, button_index, shift_pressed, ctrl_pressed, alt_pressed)
	last_entity_clicked = entity
	
	# Enhanced interaction routing based on modifiers and context
	if button_index == MOUSE_BUTTON_LEFT:
		# Check for special drag interactions first
		if shift_pressed and drag_enabled:
			return
		
		# Check for weapon interactions
		if _is_weapon(entity) and weapon_handling_component:
			if _handle_weapon_entity_click(entity, button_index, shift_pressed, ctrl_pressed, alt_pressed):
				return
		
		# Check for furniture-specific interactions
		if entity.is_in_group("furniture"):
			_handle_furniture_interaction(entity, shift_pressed, ctrl_pressed, alt_pressed)
			return
		
		# Check for storage interactions
		if entity.is_in_group("storage_containers"):
			_handle_storage_interaction(entity, shift_pressed, ctrl_pressed, alt_pressed)
			return
	
	# Fall back to normal interaction component
	if interaction_component:
		interaction_component.process_interaction(entity, button_index, shift_pressed, ctrl_pressed, alt_pressed)

func _handle_furniture_interaction(furniture: Node, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	"""Handle enhanced furniture interactions"""
	if ctrl_pressed and furniture.has_method("buckle_self"):
		furniture.buckle_self(controller)
	elif alt_pressed and furniture.has_method("start_furniture_drag") and not furniture.get("anchored"):
		furniture.start_furniture_drag(controller)
	elif interaction_component:
		interaction_component.process_interaction(furniture, MOUSE_BUTTON_LEFT, shift_pressed, ctrl_pressed, alt_pressed)

func _handle_storage_interaction(storage: Node, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	"""Handle enhanced storage interactions"""
	if shift_pressed and inventory_system:
		# Shift-click to quick-store active item
		var active_item = inventory_system.get_active_item()
		if active_item and storage.has_method("store_item"):
			storage.store_item(active_item, controller)
			return
	
	# Normal storage interaction
	if interaction_component:
		interaction_component.process_interaction(storage, MOUSE_BUTTON_LEFT, shift_pressed, ctrl_pressed, alt_pressed)

func _route_tile_click(tile_coords: Vector2i, button_index: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	emit_signal("tile_clicked", tile_coords, button_index, shift_pressed, ctrl_pressed, alt_pressed)
	
	# Check if we're wielding a weapon and this is a firing action
	if weapon_handling_component and weapon_handling_component.is_wielding_weapon():
		if button_index == MOUSE_BUTTON_LEFT and not _is_special_weapon_click(shift_pressed, ctrl_pressed, alt_pressed):
			var world_pos = _tile_to_world(tile_coords)
			weapon_handling_component.fire_weapon_at_position(weapon_handling_component.get_wielded_weapon(), world_pos)
			return
	
	if interaction_component:
		interaction_component.handle_tile_click(tile_coords, button_index, shift_pressed, ctrl_pressed, alt_pressed)
#endregion

#region ENTITY DETECTION AND HOVER
func _update_hover_entity():
	"""Update hover entity tracking with drag awareness"""
	var mouse_pos = get_viewport().get_mouse_position()
	var entity = _get_entity_at_position(mouse_pos)
	
	if entity != hover_entity:
		if hover_entity and hover_entity.has_method("set_highlighted"):
			hover_entity.set_highlighted(false)
		
		hover_entity = entity
		
		if hover_entity and hover_entity.has_method("set_highlighted"):
			# Only highlight if not in drag mode or if it's a valid drop target
			var should_highlight = true
			
			if drag_state == DragState.DRAGGING and drag_drop_coordinator:
				should_highlight = false  # Let drag-drop coordinator handle highlighting
			
			if should_highlight:
				hover_entity.set_highlighted(true)

func _get_entity_at_position(world_pos: Vector2) -> Node:
	"""Enhanced entity detection with drag-aware priority"""
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
				"priority": _get_entity_click_priority(entity)
			})
	
	if candidates.size() == 0:
		return null
	
	candidates.sort_custom(func(a, b): 
		if a.priority != b.priority:
			return a.priority > b.priority
		return a.distance < b.distance
	)
	
	return candidates[0].entity

func _get_entity_click_priority(entity: Node) -> int:
	"""Enhanced priority calculation with drag awareness"""
	var priority = 0
	
	if "click_priority" in entity:
		priority = entity.click_priority
	elif entity.has_meta("click_priority"):
		priority = entity.get_meta("click_priority")
	
	# Base priorities by entity type
	if "entity_type" in entity:
		match entity.entity_type:
			"character", "mob":
				priority += 20
			"gun", "weapon":
				priority += 18
			"item":
				priority += 10
			"furniture":
				priority += 12
			"storage":
				priority += 11
			"structure":
				priority += 5
	
	# Boost priority for drag-enabled entities when in drag mode
	if drag_enabled and entity.is_in_group("draggable_furniture"):
		priority += 5
	
	# Boost priority for drop targets when dragging
	if drag_state == DragState.DRAGGING:
		if entity.is_in_group("buckle_targets") or entity.is_in_group("item_drop_targets"):
			priority += 15
	
	# Other priority modifiers
	if entity.has_meta("is_npc") and entity.get_meta("is_npc"):
		priority += 15
	
	if "pickupable" in entity and entity.pickupable:
		priority += 15
	
	if entity.has_method("interact") or entity.has_method("attack_hand"):
		priority += 5
	
	if _is_weapon(entity):
		priority += 25
	
	return priority
#endregion

#region WEAPON INTERACTION HANDLING
func _handle_weapon_entity_click(weapon: Node, button_index: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool) -> bool:
	"""Handle clicking on weapon entities with special modifiers"""
	if button_index != MOUSE_BUTTON_LEFT:
		return false
	
	if alt_pressed and not shift_pressed and not ctrl_pressed:
		get_viewport().set_input_as_handled()
		return weapon_handling_component.handle_weapon_alt_click(weapon)
	
	if ctrl_pressed and not shift_pressed and not alt_pressed:
		get_viewport().set_input_as_handled()
		return weapon_handling_component.handle_weapon_ctrl_click(weapon)
	
	if not shift_pressed and not ctrl_pressed and not alt_pressed:
		return _handle_weapon_reload_interaction(weapon)
	
	return false

func _handle_weapon_reload_interaction(weapon: Node) -> bool:
	"""Handle weapon reload interactions"""
	if not inventory_system or not weapon_handling_component:
		return false
	
	var active_item = inventory_system.get_active_item()
	
	if active_item and _is_magazine(active_item):
		return weapon_handling_component.handle_weapon_click_with_magazine(weapon, active_item)
	
	if not active_item:
		return weapon_handling_component.handle_weapon_click_with_empty_hand(weapon)
	
	return false

func _is_magazine(item: Node) -> bool:
	"""Check if item is a magazine"""
	if not item:
		return false
	
	if item.get_script():
		var script_path = str(item.get_script().get_path())
		if "Magazine" in script_path:
			return true
	
	if "ammo_type" in item and "current_ammo" in item:
		return true
	
	if "entity_type" in item and item.entity_type == "magazine":
		return true
	
	return false
#endregion

#region DRAG AND DROP EVENT HANDLERS
func _on_drag_started(entity: Node, drag_type: int):
	"""Handle drag operation started"""
	drag_state = DragState.DRAGGING
	
	# Update UI to show drag state
	if player_ui and player_ui.has_method("set_drag_mode"):
		player_ui.set_drag_mode(true)

func _on_drag_ended(entity: Node, drop_target: Node, success: bool):
	"""Handle drag operation ended"""
	drag_state = DragState.NONE
	_cleanup_drag_visuals()
	
	# Update UI to clear drag state
	if player_ui and player_ui.has_method("set_drag_mode"):
		player_ui.set_drag_mode(false)
#endregion

#region UTILITY FUNCTIONS
func _should_ui_handle_event(event: InputEvent) -> bool:
	"""Enhanced UI handling check"""
	if not event is InputEventMouseButton or not event.pressed:
		return false
	
	var mouse_pos = event.position
	
	if player_ui and player_ui.has_method("is_position_in_ui_element"):
		return player_ui.is_position_in_ui_element(mouse_pos)
	
	return _is_clicking_on_ui(mouse_pos)

func _is_clicking_on_ui(click_position: Vector2) -> bool:
	"""Check if mouse position is over UI elements"""
	var ui_groups = ["ui_elements", "ui_buttons", "hud_elements", "interface", "menu"]
	
	for group_name in ui_groups:
		var nodes = get_tree().get_nodes_in_group(group_name)
		for node in nodes:
			if node is Control and node.visible and node.mouse_filter != Control.MOUSE_FILTER_IGNORE:
				if node.get_global_rect().has_point(click_position):
					return true
	
	return false

func _is_weapon(item: Node) -> bool:
	"""Check if item is a weapon"""
	if not item:
		return false
	
	if item.get_script():
		var script_path = str(item.get_script().get_path())
		if "Gun" in script_path or "Weapon" in script_path:
			return true
	
	if item.has_method("fire_gun") or item.has_method("fire_weapon") or item.has_method("use_weapon"):
		return true
	
	if "entity_type" in item and item.entity_type == "gun":
		return true
	
	return false

func _is_special_weapon_click(shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool) -> bool:
	"""Check if this is a special weapon interaction click"""
	return shift_pressed or ctrl_pressed or alt_pressed

func _get_tile_at_position(world_pos: Vector2) -> Vector2i:
	"""Convert world position to tile coordinates"""
	var tile_x = int(world_pos.x / tile_size)
	var tile_y = int(world_pos.y / tile_size)
	return Vector2i(tile_x, tile_y)

func _tile_to_world(tile_pos: Vector2i) -> Vector2:
	"""Convert tile position to world coordinates"""
	return Vector2(
		(tile_pos.x * tile_size) + (tile_size / 2.0),
		(tile_pos.y * tile_size) + (tile_size / 2.0)
	)
#endregion

#region CONFIGURATION GETTERS/SETTERS
func set_drag_enabled(enabled: bool):
	"""Enable/disable drag operations"""
	drag_enabled = enabled

func set_shift_drag_enabled(enabled: bool):
	"""Enable/disable shift-drag operations"""
	shift_drag_enabled = enabled

func set_hold_drag_enabled(enabled: bool):
	"""Enable/disable hold-drag operations"""
	hold_drag_enabled = enabled

func set_alt_drag_enabled(enabled: bool):
	"""Enable/disable alt-drag operations"""
	alt_drag_enabled = enabled

func is_drag_in_progress() -> bool:
	"""Check if a drag operation is in progress"""
	return drag_state == DragState.DRAGGING

func get_current_drag_entity() -> Node:
	"""Get currently dragged entity"""
	return drag_start_entity
#endregion
