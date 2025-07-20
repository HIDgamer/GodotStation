extends Node2D
class_name ClickSystem

# === SIGNALS ===
signal tile_clicked(tile_coords, mouse_button, shift_pressed, ctrl_pressed, alt_pressed)
signal entity_clicked(entity, mouse_button, shift_pressed, ctrl_pressed, alt_pressed)
signal radial_menu_requested(entity, options, screen_position)
signal click_started(position, button_index)
signal click_ended(position, button_index)
signal click_dragged(from_position, to_position, button_index)
signal middle_drag_started(position, target)
signal context_menu_requested(position, target)

# === ENUMS ===
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
	DRAGGING,
	MIDDLE_DRAGGING
}

# === CONSTANTS ===
const TILE_SIZE = 32  # Size of tiles in pixels
const DOUBLE_CLICK_TIME = 0.3  # Time window for double clicks in seconds
const DRAG_START_DISTANCE = 5  # Pixels needed to start a drag
const CLICK_COOLDOWN = 0.1  # Cooldown between clicks in seconds
const ENTITY_CLICK_PRIORITY = true  # Prioritize entities over tiles when both are clickable

# === MEMBER VARIABLES ===
# Click tracking
var last_click_position: Vector2 = Vector2.ZERO
var last_click_time: float = 0.0
var last_click_button: int = -1
var click_start_position: Vector2 = Vector2.ZERO
var is_dragging: bool = false
var drag_state: int = DragState.NONE
var click_cooldown_timer: float = 0.0
var click_intercepted: bool = false

# Entity tracking
var drag_source = null  # Entity being dragged
var middle_drag_source = null  # Entity/atom being middle-dragged
var hover_entity = null  # Currently hovered entity
var last_entity_clicked = null  # Last entity that was clicked on

# References to other systems
var world = null  # Reference to world node
var player = null  # Reference to player entity (GridMovementController)
var tile_occupancy_system = null  # Reference to tile occupancy system
var spatial_manager = null  # Reference to spatial manager
var sensory_system = null  # Reference to sensory system
var radial_menu = null  # Reference to radial menu
var context_menu = null  # Reference to context menu
var cursor_controller = null  # Reference to cursor controller
var player_ui = null

# Click preference settings
var preserve_click_params: bool = true  # Whether to preserve click params for future operations
var click_params: Dictionary = {}  # Stored click parameters

# Visual effects
var drag_line: Line2D = null
var middle_drag_time: float = 0.0
var middle_drag_entity = null

# Player preferences
var click_drag_enabled: bool = true
var double_click_enabled: bool = true
var middle_click_toggle: bool = true
var right_click_for_context: bool = true
var allow_shift_clicking: bool = true
var show_click_effects: bool = true
var click_through_windows: bool = false

# === INITIALIZATION ===
func _ready():
	set_process_input(true)
	set_process(true)
	
	# Register with input priority system
	var input_manager = get_node_or_null("/root/InputPriorityManager")
	if input_manager:
		input_manager.register_ui_system(self)
	
	print("ClickSystem: Initializing...")
	
	# Find world reference
	world = get_parent()
	if !world or !world.has_method("get_tile_data"):
		# Try finding the world node by type or name
		world = find_parent_of_type("World")
		if !world:
			world = get_node_or_null("/root/World")
			if !world:
				# Last attempt - look for any node named World
				var nodes = get_tree().get_nodes_in_group("world")
				if nodes.size() > 0:
					world = nodes[0]
	
	# Log world status
	if world:
		print("ClickSystem: Found world reference: ", world.name)
	else:
		push_error("ClickSystem: Could not find world reference!")
	
	# Init drag line for visual feedback
	drag_line = Line2D.new()
	drag_line.width = 2.0
	drag_line.default_color = Color(1, 1, 0, 0.7)
	drag_line.visible = false
	add_child(drag_line)
	
	# Add to click_system group for other systems to find
	add_to_group("click_system")
	
	# Attempt to find an existing cursor controller
	cursor_controller = get_node_or_null("/root/CursorController")
	if !cursor_controller:
		cursor_controller = get_node_or_null("../CursorController")
	
	# Connect to scene tree signals
	get_tree().node_added.connect(_on_node_added_to_scene)
	
	# Get player preferences from settings if available
	var settings = _get_settings()
	if settings:
		click_drag_enabled = settings.get_setting("controls", "click_drag_enabled", true)
		double_click_enabled = settings.get_setting("controls", "double_click_enabled", true)
		allow_shift_clicking = settings.get_setting("controls", "allow_shift_clicking", true)
		show_click_effects = settings.get_setting("interface", "show_click_effects", true)
		click_through_windows = settings.get_setting("controls", "click_through_windows", false)
	
	# Defer connection to other systems
	call_deferred("connect_to_systems")

func connect_to_systems():
	print("ClickSystem: Connecting to systems...")
	
	# Find player with retry
	if !player:
		find_player_reference()
	
	# Connect to world systems
	if world:
		tile_occupancy_system = world.get_node_or_null("TileOccupancySystem")
		spatial_manager = world.get_node_or_null("SpatialManager")
		sensory_system = world.get_node_or_null("SensorySystem")
		print("ClickSystem: World systems - TileOccupancy:", !!tile_occupancy_system, " Spatial:", !!spatial_manager, " Sensory:", !!sensory_system)
	
	# Ensure radial menu exists
	ensure_radial_menu_exists()
	
	# Retry connection after delay if player not found
	if !player:
		print("ClickSystem: Player not found, retrying in 1 second...")
		get_tree().create_timer(1.0).timeout.connect(connect_to_systems)
	
	print("ClickSystem: System connection complete")
	print("  - Player: ", "Found" if player else "Not found")
	print("  - World: ", "Found" if world else "Not found")
	print("  - RadialMenu: ", "Found" if radial_menu else "Not found")

# === INPUT PROCESSING ===
func _input(event):
	# Only handle mouse events
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	
	# CRITICAL: Only process input if we have a valid LOCAL player
	if not player or not is_instance_valid(player):
		return
	
	# Verify this is actually a local player, not an NPC
	if player.has_meta("is_npc") and player.get_meta("is_npc"):
		print("ClickSystem: Refusing to process input - player reference is an NPC!")
		return
	
	# Verify player is local
	if "is_local_player" in player and not player.is_local_player:
		return
	
	# Let UI handle the event first
	if should_ui_handle_event(event):
		return
	
	# Process the event
	if event is InputEventMouseButton:
		handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		handle_mouse_motion(event)

# Comprehensive UI event detection
func should_ui_handle_event(event) -> bool:
	if not event is InputEventMouseButton:
		return false
	
	if not event.pressed:
		return false
	
	var mouse_pos = event.position
	
	# Method 1: Check PlayerUI first (highest priority)
	if player_ui and player_ui.has_method("is_position_in_ui_element"):
		if player_ui.is_position_in_ui_element(mouse_pos):
			print("ClickSystem: UI click detected by PlayerUI")
			return true
	
	# Method 2: Check for UI elements using viewport's GUI
	var viewport = get_viewport()
	if viewport:
		# Check if there's a Control under the mouse
		var gui = viewport.gui_get_focus_owner()
		if gui and gui is Control:
			var global_rect = gui.get_global_rect()
			if global_rect.has_point(mouse_pos):
				print("ClickSystem: UI click detected by viewport GUI")
				return true
	
	# Method 3: Check specific UI groups
	var ui_groups = ["ui_elements", "ui_buttons", "hud_elements", "interface", "menu", "windows"]
	for group_name in ui_groups:
		var nodes = get_tree().get_nodes_in_group(group_name)
		for node in nodes:
			if node is Control and node.visible and node.mouse_filter != Control.MOUSE_FILTER_IGNORE:
				if node.get_global_rect().has_point(mouse_pos):
					print("ClickSystem: UI click detected in group: ", group_name)
					return true
	
	# Method 4: Check CanvasLayers for UI
	var canvas_layers = get_tree().get_nodes_in_group("canvas_layer")
	for layer in canvas_layers:
		if layer is CanvasLayer and layer.visible:
			if check_canvas_layer_for_ui_simple(layer, mouse_pos):
				print("ClickSystem: UI click detected in CanvasLayer")
				return true
	
	return false

func check_canvas_layer_for_ui_simple(canvas_layer: CanvasLayer, click_position: Vector2) -> bool:
	if not canvas_layer.visible:
		return false
	
	# Check direct children only
	for child in canvas_layer.get_children():
		if child is Control and child.visible:
			if child.mouse_filter == Control.MOUSE_FILTER_IGNORE:
				continue
				
			if child.get_global_rect().has_point(click_position):
				return true
	
	return false

# UI detection
func is_clicking_on_ui(click_position: Vector2) -> bool:
	"""Determine if a click should be intercepted by UI elements"""
	
	# Method 1: Check PlayerUI first (highest priority)
	if player_ui and player_ui.has_method("is_position_in_ui_element"):
		if player_ui.is_position_in_ui_element(click_position):
			print("ClickSystem: PlayerUI detected click at ", click_position)
			return true
	
	# Method 2: Check specific UI groups (more targeted than recursive check)
	var ui_groups = ["ui_elements", "ui_buttons", "hud_elements", "interface", "menu"]
	for group_name in ui_groups:
		var nodes = get_tree().get_nodes_in_group(group_name)
		for node in nodes:
			if node is Control and node.visible:
				# Respect mouse filter settings
				if node.mouse_filter == Control.MOUSE_FILTER_IGNORE:
					continue
					
				if node.get_global_rect().has_point(click_position):
					print("ClickSystem: Found UI element in group: ", group_name, " - ", node.name)
					return true
	
	# Method 3: Check Canvas Layers (but only direct children that are Controls)
	var canvas_layers = get_tree().get_nodes_in_group("canvas_layer")
	for layer in canvas_layers:
		if layer is CanvasLayer and check_canvas_layer_ui(layer, click_position):
			return true
	
	# Method 4: Fallback check for any CanvasLayer
	var all_canvas_layers = get_tree().get_nodes_in_group("canvas_layer")
	if all_canvas_layers.is_empty():
		# If no canvas layers in group, find them manually
		all_canvas_layers = find_canvas_layers_recursive(get_tree().root)
	
	for layer in all_canvas_layers:
		if layer is CanvasLayer:
			var layer_name = layer.name.to_lower()
			if layer_name.contains("ui") or layer_name.contains("hud") or layer_name.contains("menu"):
				if check_canvas_layer_ui_strict(layer, click_position):
					return true
	
	return false

# More restrictive canvas layer check
func check_canvas_layer_ui_strict(canvas_layer: CanvasLayer, click_position: Vector2) -> bool:
	"""Check CanvasLayer for UI elements with stricter filtering"""
	if not canvas_layer.visible:
		return false
	
	# Only check direct children that are actually interactive
	for child in canvas_layer.get_children():
		if not child is Control or not child.visible:
			continue
			
		# Skip if mouse filter is set to ignore
		if child.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
			
		# Check if this control is at the position
		if child.get_global_rect().has_point(click_position):
			print("ClickSystem: Found UI control in CanvasLayer: ", child.name)
			return true
			
		# Check interactive children (buttons, etc.)
		if check_control_children_recursive(child, click_position):
			return true
	
	return false

# Recursive check but only for interactive UI elements
func check_control_children_recursive(control: Control, click_position: Vector2) -> bool:
	"""Recursively check Control children but only interactive ones"""
	if not control.visible:
		return false
		
	for child in control.get_children():
		if not child is Control or not child.visible:
			continue
			
		# Skip if mouse filter is set to ignore (respects the UI setup)
		if child.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			# Still check children in case they can receive input
			if check_control_children_recursive(child, click_position):
				return true
			continue
		
		# Check if this control is at the position and can actually receive input
		if child.get_global_rect().has_point(click_position):
			# Additional check: make sure it's actually an interactive element
			if child is Button or child is TextureButton or child.mouse_filter == Control.MOUSE_FILTER_STOP:
				print("ClickSystem: Found interactive UI control: ", child.name)
				return true
		
		# Recursively check children
		if check_control_children_recursive(child, click_position):
			return true
	
	return false

# Helper to find canvas layers
func find_canvas_layers_recursive(node: Node) -> Array:
	"""Find all CanvasLayer nodes in the tree"""
	var canvas_layers = []
	
	if node is CanvasLayer:
		canvas_layers.append(node)
	
	for child in node.get_children():
		canvas_layers.append_array(find_canvas_layers_recursive(child))
	
	return canvas_layers

# Check CanvasLayer for UI elements
func check_canvas_layer_ui(canvas_layer: CanvasLayer, click_position: Vector2) -> bool:
	if not canvas_layer.visible:
		return false
	
	for child in canvas_layer.get_children():
		if check_ui_nodes_recursive(child, click_position):
			return true
	
	return false

# Recursively check UI nodes
func check_ui_nodes_recursive(node: Node, click_position: Vector2) -> bool:
	# Skip non-UI nodes for performance
	if not (node is Control or node is CanvasLayer or node is Window):
		# Only check children if this could be a UI container
		if node.name.to_lower().contains("ui") or node.name.to_lower().contains("hud") or node.name.to_lower().contains("menu"):
			for child in node.get_children():
				if check_ui_nodes_recursive(child, click_position):
					return true
		return false
	
	# Check Control nodes
	if node is Control:
		if not node.visible:
			return false
			
		# Skip if mouse filter is ignore
		if node.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			# Still check children in case they can receive input
			for child in node.get_children():
				if check_ui_nodes_recursive(child, click_position):
					return true
			return false
		
		# Check if point is in this control
		if node.get_global_rect().has_point(click_position):
			print("ClickSystem: Found UI control: ", node.name, " at ", node.get_global_rect())
			return true
		
		# Check children
		for child in node.get_children():
			if check_ui_nodes_recursive(child, click_position):
				return true
	
	# Check CanvasLayer nodes
	elif node is CanvasLayer:
		if check_canvas_layer_ui(node, click_position):
			return true
	
	# Check Window nodes (Godot 4)
	elif node is Window:
		if node.visible:
			var window_rect = Rect2(Vector2.ZERO, node.size)
			if window_rect.has_point(click_position):
				return true
	
	return false

#region CLICK HANDLING
# button press handling
func handle_button_press(button_index: int, mouse_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	"""Handle mouse button press with improved accuracy and UI coordination"""
	
	# Double-check UI interference (belt and suspenders approach)
	if is_clicking_on_ui(mouse_pos):
		print("ClickSystem: Last-chance UI check blocked click")
		click_intercepted = true
		return
	
	# Store click start data
	click_start_position = mouse_pos
	last_click_button = button_index
	click_intercepted = false
	
	# Get precise global mouse position
	var world_pos = get_global_mouse_position()
	
	# Check for double click
	var current_time = Time.get_ticks_msec() / 1000.0
	var is_double_click = false
	
	if double_click_enabled and button_index == last_click_button:
		var time_since_last_click = current_time - last_click_time
		var distance_from_last_click = mouse_pos.distance_to(last_click_position)
		
		if time_since_last_click < DOUBLE_CLICK_TIME and distance_from_last_click < 10:
			var current_target = get_most_accurate_entity_at_position(world_pos)
			if current_target == last_entity_clicked and current_target != null:
				is_double_click = true
				print("ClickSystem: Double-click detected on entity: ", current_target.name)
	
	# Update click tracking
	last_click_position = mouse_pos
	last_click_time = current_time
	
	# Emit signal
	emit_signal("click_started", mouse_pos, button_index)
	
	# Get the most accurate entity at the click position
	var click_target = get_most_accurate_entity_at_position(world_pos)
	
	# Store the clicked entity
	if button_index == MOUSE_BUTTON_LEFT:
		last_entity_clicked = click_target
	
	# Handle based on button type
	match button_index:
		MOUSE_BUTTON_LEFT:
			if is_double_click:
				handle_double_left_click(mouse_pos, shift_pressed, ctrl_pressed, alt_pressed)
			else:
				handle_left_click_press(mouse_pos, shift_pressed, ctrl_pressed, alt_pressed)
				
		MOUSE_BUTTON_RIGHT:
			handle_right_click_press(mouse_pos, shift_pressed, ctrl_pressed, alt_pressed)
			
		MOUSE_BUTTON_MIDDLE:
			handle_middle_click_press(mouse_pos, shift_pressed, ctrl_pressed, alt_pressed)
			
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			handle_scroll(button_index == MOUSE_BUTTON_WHEEL_UP, shift_pressed, ctrl_pressed, alt_pressed)

# click handlers
func click_on_entity(entity, button_index: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	if !entity:
		return
	
	print("ClickSystem: Clicking on entity: ", entity.name, " with button: ", button_index)
	
	# Emit entity clicked signal
	emit_signal("entity_clicked", entity, button_index, shift_pressed, ctrl_pressed, alt_pressed)
	
	# Track entity
	last_entity_clicked = entity
	
	# Route to player's interaction system
	if player and player.has_method("process_interaction"):
		player.process_interaction(entity, button_index, shift_pressed, ctrl_pressed, alt_pressed)
	else:
		# Fallback to old method
		handle_entity_interaction_fallback(entity, button_index, shift_pressed, ctrl_pressed, alt_pressed)

func click_on_tile(tile_coords: Vector2i, button_index: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	print("ClickSystem: Clicking on tile: ", tile_coords, " with button: ", button_index)
	
	# Emit tile clicked signal
	emit_signal("tile_clicked", tile_coords, button_index, shift_pressed, ctrl_pressed, alt_pressed)
	
	# Let player handle the click on the tile
	if player and player.has_method("_on_tile_clicked"):
		player._on_tile_clicked(tile_coords, button_index, shift_pressed, ctrl_pressed, alt_pressed)
	else:
		handle_tile_interaction_fallback(tile_coords, button_index, shift_pressed, ctrl_pressed, alt_pressed)

# Fallback interaction handling for backwards compatibility
func handle_entity_interaction_fallback(entity, button_index: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	if !player:
		return
	
	# Handle modifier-based interactions
	if shift_pressed and not ctrl_pressed and not alt_pressed:
		# Examine
		if player.has_method("handle_examine_interaction"):
			player.handle_examine_interaction(entity)
		return
	
	if ctrl_pressed and not shift_pressed and not alt_pressed:
		# Pull/drag
		if player.has_method("handle_ctrl_interaction"):
			player.handle_ctrl_interaction(entity)
		return
	
	# Standard interaction based on player's current intent
	if button_index == MOUSE_BUTTON_LEFT:
		if player.has_method("handle_intent_interaction"):
			player.handle_intent_interaction(entity)
		elif player.has_method("on_entity_clicked"):
			player.on_entity_clicked(entity, button_index, shift_pressed, ctrl_pressed, alt_pressed)
	
	# If the entity has a specific interaction method, use it
	if button_index == MOUSE_BUTTON_LEFT and entity.has_method("interact"):
		entity.interact(player)

func handle_tile_interaction_fallback(tile_coords: Vector2i, button_index: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	if !player:
		return
	
	# Handle right click on tile
	if button_index == MOUSE_BUTTON_RIGHT and player.has_method("handle_tile_context_menu"):
		player.handle_tile_context_menu(tile_coords, player.current_z_level if "current_z_level" in player else 0)
	
	# Handle middle click on tile (point)
	elif button_index == MOUSE_BUTTON_MIDDLE and player.has_method("point_to"):
		var world_pos = tile_to_world(tile_coords)
		player.point_to(world_pos)

# Process hover effects and cooldowns
func _process(delta):
	# CRITICAL: Don't process if no valid local player
	if not player or not is_instance_valid(player):
		return
	
	# Don't process for NPCs
	if player.has_meta("is_npc") and player.get_meta("is_npc"):
		return
	
	# Update click cooldown timer
	if click_cooldown_timer > 0:
		click_cooldown_timer -= delta
	
	# Update middle drag time if active
	if drag_state == DragState.MIDDLE_DRAGGING:
		middle_drag_time += delta
		
		# Reset middle drag if it's been too long
		if middle_drag_time > 3.0:  # 3 second timeout
			cancel_middle_drag()
	
	# Update hover entity
	update_hover_entity()

# === MOUSE EVENT HANDLERS ===
func handle_mouse_button(event: InputEventMouseButton):
	# CRITICAL: Validate player before processing
	if not player or not is_instance_valid(player):
		return
	
	# Reject input from NPCs
	if player.has_meta("is_npc") and player.get_meta("is_npc"):
		print("ClickSystem: ERROR - Rejecting input from NPC!")
		return
	
	# Verify local player
	if "is_local_player" in player and not player.is_local_player:
		return
	
	# Ignore if click cooldown is active
	if click_cooldown_timer > 0:
		return
	
	# Get mouse position
	var mouse_pos = event.position
	
	# Extract modifier keys
	var shift_pressed = event.shift_pressed
	var ctrl_pressed = event.ctrl_pressed
	var alt_pressed = event.alt_pressed
	
	# Store click parameters
	if preserve_click_params:
		click_params = {
			"shift": shift_pressed,
			"ctrl": ctrl_pressed,
			"alt": alt_pressed,
			"position": mouse_pos,
			"screen_position": mouse_pos,
			"world_position": get_global_mouse_position()
		}
	
	# Handle button press events
	if event.pressed:
		handle_button_press(event.button_index, mouse_pos, shift_pressed, ctrl_pressed, alt_pressed)
	else:
		handle_button_release(event.button_index, mouse_pos, shift_pressed, ctrl_pressed, alt_pressed)

func handle_mouse_motion(event: InputEventMouseMotion):
	# Check for drag operations
	if drag_state != DragState.NONE:
		# Regular dragging
		if drag_state == DragState.DRAGGING and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			handle_drag(event.position)
		
		# Middle button dragging
		elif drag_state == DragState.MIDDLE_DRAGGING and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			handle_middle_drag(event.position)
	
	# Update hover effects
	var mouse_pos = event.position
	var world_pos = get_global_mouse_position()
	
	# Update the cursor if we have a controller
	if cursor_controller:
		if is_position_interactable(world_pos):
			cursor_controller.set_cursor_mode("pointer")
		else:
			cursor_controller.set_cursor_mode("default")

# === BUTTON HANDLERS ===

func handle_button_release(button_index: int, mouse_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	# Calculate distance moved since click start
	var distance_moved = mouse_pos.distance_to(click_start_position)
	
	# Emit signal
	emit_signal("click_ended", mouse_pos, button_index)
	
	# Handle based on button type
	match button_index:
		MOUSE_BUTTON_LEFT:
			# If we weren't dragging or moved very little, treat as a click
			if !is_dragging or distance_moved < DRAG_START_DISTANCE:
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
	
	# Reset drag state
	if button_index == MOUSE_BUTTON_LEFT and drag_state == DragState.DRAGGING:
		drag_state = DragState.NONE
		drag_source = null
		drag_line.visible = false
		
	if button_index == MOUSE_BUTTON_MIDDLE and drag_state == DragState.MIDDLE_DRAGGING:
		drag_state = DragState.NONE
		middle_drag_source = null
		middle_drag_time = 0.0
		drag_line.visible = false
	
	# Start cooldown timer
	click_cooldown_timer = CLICK_COOLDOWN

# === CLICK TYPE HANDLERS ===
func handle_left_click_press(mouse_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	print("ClickSystem: Left click at ", mouse_pos)
	
	# Get entity or tile at position
	var world_pos = get_global_mouse_position()
	var click_target = get_most_accurate_entity_at_position(world_pos)
	
	print("ClickSystem: Click target found: ", click_target.name if click_target else "none")
	
	# Regular click handling
	if click_target:
		print("ClickSystem: Routing entity click to player")
		route_entity_click(click_target, MOUSE_BUTTON_LEFT, shift_pressed, ctrl_pressed, alt_pressed)
		drag_source = click_target
	else:
		# Click on tile instead
		var tile_pos = get_tile_at_position(world_pos)
		print("ClickSystem: Routing tile click to player at ", tile_pos)
		route_tile_click(tile_pos, MOUSE_BUTTON_LEFT, shift_pressed, ctrl_pressed, alt_pressed)

func route_entity_click(entity, button_index: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	if !entity:
		print("ClickSystem: Cannot route click - entity is null")
		return
	
	print("ClickSystem: Routing entity click - ", entity.name, " button:", button_index)
	
	# Emit entity clicked signal first
	emit_signal("entity_clicked", entity, button_index, shift_pressed, ctrl_pressed, alt_pressed)
	
	# Track entity
	last_entity_clicked = entity
	
	# Ensure we have a valid player reference
	if !player:
		print("ClickSystem: Error - No player reference set!")
		find_player_reference()
		if !player:
			print("ClickSystem: Critical error - Cannot find player!")
			return
	
	# Route to player's interaction system
	if player.has_method("process_interaction"):
		print("ClickSystem: Calling player.process_interaction")
		var result = player.process_interaction(entity, button_index, shift_pressed, ctrl_pressed, alt_pressed)
		print("ClickSystem: Interaction result: ", result)
	elif player.has_method("_on_entity_clicked"):
		print("ClickSystem: Calling player._on_entity_clicked (fallback)")
		player._on_entity_clicked(entity, button_index, shift_pressed, ctrl_pressed, alt_pressed)
	else:
		print("ClickSystem: Error - Player has no interaction methods!")
		# Emergency fallback
		handle_entity_interaction_emergency_fallback(entity, button_index, shift_pressed, ctrl_pressed, alt_pressed)

func route_tile_click(tile_coords: Vector2i, button_index: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	print("ClickSystem: Routing tile click - ", tile_coords, " button:", button_index)
	
	# Emit tile clicked signal
	emit_signal("tile_clicked", tile_coords, button_index, shift_pressed, ctrl_pressed, alt_pressed)
	
	# Ensure we have a valid player reference
	if !player:
		print("ClickSystem: Error - No player reference for tile click!")
		find_player_reference()
		if !player:
			return
	
	# Let player handle the tile click
	if player.has_method("_on_tile_clicked"):
		print("ClickSystem: Calling player._on_tile_clicked")
		player._on_tile_clicked(tile_coords, button_index, shift_pressed, ctrl_pressed, alt_pressed)
	else:
		print("ClickSystem: Player has no _on_tile_clicked method")
		# Fallback tile interaction
		handle_tile_interaction_fallback(tile_coords, button_index, shift_pressed, ctrl_pressed, alt_pressed)

func find_player_reference():
	print("ClickSystem: Searching for LOCAL player reference...")
	
	var potential_players = []
	
	# Method 1: Check player_controller group - EXCLUDE NPCs
	potential_players = get_tree().get_nodes_in_group("player_controller")
	for p in potential_players:
		# Skip NPCs
		if p.is_in_group("npcs"):
			continue
		if p.has_meta("is_npc") and p.get_meta("is_npc"):
			continue
		# Prefer local players
		if "is_local_player" in p and p.is_local_player:
			player = p
			print("ClickSystem: Found LOCAL player in player_controller group: ", player.name)
			return
	
	# Method 2: Check players group - EXCLUDE NPCs
	potential_players = get_tree().get_nodes_in_group("players")
	for p in potential_players:
		# Skip NPCs
		if p.is_in_group("npcs"):
			continue
		if p.has_meta("is_npc") and p.get_meta("is_npc"):
			continue
		# Prefer local players
		if "is_local_player" in p and p.is_local_player:
			player = p
			print("ClickSystem: Found LOCAL player in players group: ", player.name)
			return
	
	# Method 3: Look for nodes
	potential_players = get_tree().get_nodes_in_group("entities")
	for entity in potential_players:
		# Skip NPCs
		if entity.is_in_group("npcs"):
			continue
		if entity.has_meta("is_npc") and entity.get_meta("is_npc"):
			continue
		
		# Check for player-like methods
		if entity.has_method("process_interaction") and entity.has_method("get_active_item"):
			# Prefer local players
			if "is_local_player" in entity and entity.is_local_player:
				player = entity
				print("ClickSystem: Found LOCAL player by entity methods: ", player.name)
				return
	
	print("ClickSystem: Could not find LOCAL player reference!")

func handle_entity_interaction_emergency_fallback(entity, button_index: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	print("ClickSystem: Using emergency fallback for entity interaction")
	
	# Try to call the entity's interaction methods directly
	if button_index == MOUSE_BUTTON_LEFT:
		if shift_pressed:
			# Examine
			examine_entity(entity)
		elif entity.has_method("attack_hand") and player:
			# Try basic interaction
			entity.attack_hand(player)
		elif entity.has_method("interact") and player:
			entity.interact(player)
		else:
			print("ClickSystem: Entity ", entity.name, " has no interaction methods")
	elif button_index == MOUSE_BUTTON_RIGHT:
		# Show context menu if available
		if radial_menu:
			show_radial_menu(entity, get_viewport().get_mouse_position())

func handle_left_click_release(mouse_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	# Normal clicks are already handled in the press handler
	pass

func handle_right_click_press(mouse_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	# Get entity or tile at position
	var world_pos = get_global_mouse_position()
	var click_target = get_clickable_at_position(world_pos)
	
	# Store for context menu if needed
	last_entity_clicked = click_target
	
	# Alternate interaction for right click
	if click_target:
		click_on_entity(click_target, MOUSE_BUTTON_RIGHT, shift_pressed, ctrl_pressed, alt_pressed)
	else:
		# Click on tile instead
		var tile_pos = get_tile_at_position(world_pos)
		click_on_tile(tile_pos, MOUSE_BUTTON_RIGHT, shift_pressed, ctrl_pressed, alt_pressed)

func handle_right_click_release(mouse_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	if right_click_for_context:
		# Show context menu for target entity or tile
		if last_entity_clicked:
			# Request entity context menu
			emit_signal("context_menu_requested", mouse_pos, last_entity_clicked)
			
			# Show radial menu if available
			if radial_menu:
				show_radial_menu(last_entity_clicked, mouse_pos)
		else:
			# Request tile context menu if we're not clicking on an entity
			var tile_pos = get_tile_at_position(get_global_mouse_position())
			emit_signal("context_menu_requested", mouse_pos, {"type": "tile", "position": tile_pos})

func handle_middle_click_press(mouse_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	# Get entity or tile at position
	var world_pos = get_global_mouse_position()
	var click_target = get_clickable_at_position(world_pos)
	
	# Start middle drag if there's a target
	if click_target:
		middle_drag_source = click_target
		drag_state = DragState.MIDDLE_DRAGGING
		middle_drag_time = 0.0
		
		# Set up drag line
		drag_line.clear_points()
		drag_line.add_point(world_pos)
		drag_line.add_point(world_pos)
		drag_line.default_color = Color(0, 0.8, 1.0, 0.7)  # Cyan for middle drag
		drag_line.visible = true
		
		# Emit signal
		emit_signal("middle_drag_started", world_pos, click_target)
	
	# Process middle click differently based on modifiers
	if click_target:
		click_on_entity(click_target, MOUSE_BUTTON_MIDDLE, shift_pressed, ctrl_pressed, alt_pressed)
	else:
		# Click on tile
		var tile_pos = get_tile_at_position(world_pos)
		click_on_tile(tile_pos, MOUSE_BUTTON_MIDDLE, shift_pressed, ctrl_pressed, alt_pressed)

func handle_middle_click_release(mouse_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	# Middle click specific actions (e.g., swap active hand)
	if player and player.has_method("swap_active_hand"):
		player.swap_active_hand()

func handle_double_left_click(mouse_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	# Get entity or tile at position
	var world_pos = get_global_mouse_position()
	var click_target = get_clickable_at_position(world_pos)
	
	if click_target:
		# Handle entity double click
		if click_target is Node and player:
			# Check if we can reach the target
			if player.has_method("is_adjacent_to") and player.is_adjacent_to(click_target):
				# Execute player action like attack_self on the target
				if player.has_method("attack_self"):
					player.attack_self()
				
				# Try double click on the object itself
				if click_target.has_method("double_click"):
					click_target.double_click(player)
				
				# Try alternative path
				if is_instance_valid(player) and player.has_method("DblClickOn"):
					player.DblClickOn(click_target, "")
	else:
		# Handle tile double click (e.g., run to location)
		var tile_pos = get_tile_at_position(world_pos)

func handle_scroll(scroll_up: bool, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	# Handle mousewheel scrolling
	if player:
		# Check for item cycling
		var inventory_system = player.get_node_or_null("InventorySystem") 
		if inventory_system:
			if shift_pressed and ctrl_pressed:
				# Cycle modes or special actions
				pass
			elif shift_pressed:
				# Cycle intent
				if player.has_method("cycle_intent"):
					player.cycle_intent()
			elif ctrl_pressed:
				# Cycle target zone
				cycle_target_zone(scroll_up)
			else:
				# Default: cycle active items
				if inventory_system.has_method("cycle_active_item"):
					inventory_system.cycle_active_item(scroll_up)

# === DRAG HANDLERS ===
func handle_drag(mouse_pos: Vector2):
	# If we're not already dragging, check if we should start
	if !is_dragging:
		var distance = mouse_pos.distance_to(click_start_position)
		if distance > DRAG_START_DISTANCE:
			is_dragging = true
			drag_state = DragState.DRAGGING
			
			# Set up drag line
			drag_line.clear_points()
			drag_line.add_point(click_start_position)
			drag_line.add_point(mouse_pos)
			drag_line.visible = true
	
	# Update drag line if we're dragging
	if is_dragging:
		if drag_line.get_point_count() >= 2:
			drag_line.set_point_position(1, mouse_pos)
		
		# Emit signal
		emit_signal("click_dragged", click_start_position, mouse_pos, MOUSE_BUTTON_LEFT)

func handle_middle_drag(mouse_pos: Vector2):
	# Update middle drag visuals
	if drag_line.visible:
		if drag_line.get_point_count() >= 2:
			drag_line.set_point_position(1, mouse_pos)
	
	# Check for direction changes in middle drag
	if middle_drag_source:
		# Get direction from drag source to current mouse position
		var source_pos = middle_drag_source.global_position if "global_position" in middle_drag_source else get_global_mouse_position()
		var drag_dir = (get_global_mouse_position() - source_pos).normalized()
		
		# Update entity of drag direction
		if middle_drag_source.has_method("on_middle_drag"):
			middle_drag_source.on_middle_drag(drag_dir)

func end_drag(mouse_pos: Vector2):
	if !drag_source:
		return
	
	# Calculate final position
	var target_pos = get_global_mouse_position()
	var target = get_clickable_at_position(target_pos)
	
	# Handle mousedrop between source and target
	if target and drag_source != target:
		handle_mouse_drop(drag_source, target)
	
	# Reset drag
	drag_line.visible = false
	is_dragging = false

func end_middle_drag(mouse_pos: Vector2):
	# Find target entity
	var target_pos = get_global_mouse_position()
	var target = get_clickable_at_position(target_pos)
	
	# Get drag direction and distance
	var source_pos = middle_drag_source.global_position if "global_position" in middle_drag_source else Vector2.ZERO
	var drag_dir = (target_pos - source_pos).normalized()
	var distance = source_pos.distance_to(target_pos)
	
	# Do something specific with middle drag
	if middle_drag_source and player:
		# Handle specific middle drag actions based on what's being dragged
		var source_type = get_entity_type(middle_drag_source)
		
		match source_type:
			"entity", "character":
				# Point to location 
				if player.has_method("point_to"):
					player.point_to(target_pos)
			"item":
				# Throw the item
				if player.has_method("throw_item_at_position"):
					player.throw_item_at_position(middle_drag_source, target_pos)
			_:
				# Default - try to let the entity handle it
				if middle_drag_source.has_method("on_middle_drag_end"):
					middle_drag_source.on_middle_drag_end(target_pos, target)
	
	# Reset middle drag
	drag_line.visible = false
	middle_drag_time = 0.0

# Cancel a middle drag operation
func cancel_middle_drag():
	middle_drag_source = null
	middle_drag_time = 0.0
	drag_state = DragState.NONE
	drag_line.visible = false

# === INTERACTION HANDLERS ===
func handle_mouse_drop(source, target):
	# Check if source can be dropped on target
	if !source or !target:
		return
	
	if player:
		# Let player handle it first if it has the method
		if player.has_method("MouseDrop"):
			player.MouseDrop(source, target)
		
		# Check if target can accept the dropped item
		elif target.has_method("MouseDrop_T"):
			target.MouseDrop_T(source, player)
		
		# Check if the source is an item
		elif "item_name" in source and source.has_method("handle_drop"):
			# Try different ways to handle item dropping on target
			if "inventory_system" in player and player.inventory_system:
				var container_used = false
				
				# Check if target is a container
				if "is_container" in target and target.is_container:
					# Try to put the item in the container
					if target.has_method("add_item"):
						if player.inventory_system.remove_item(source):
							target.add_item(source)
							container_used = true
				
				# No container handling - try to equip if target is player
				if !container_used and target == player:
					# Try to equip the item on self
					if player.inventory_system.has_method("equip_item_to_appropriate_slot"):
						player.inventory_system.equip_item_to_appropriate_slot(source)

# Handle default attack if specified
func handle_attack(source, target):
	# Get the active item from the source
	var active_item = null
	if source.has_method("get_active_item"):
		active_item = source.get_active_item()
	
	# Check if active item is a weapon
	if active_item and "tool_behaviour" in active_item and active_item.tool_behaviour == "weapon":
		# Attack with weapon
		if active_item.has_method("attack"):
			active_item.attack(target, source)
	elif active_item:
		# Attack with non-weapon item
		if active_item.has_method("attack"):
			active_item.attack(target, source)
	else:
		# Unarmed attack
		if source.has_method("attack_unarmed"):
			source.attack_unarmed(target)

# === RADIAL MENU ===
func ensure_radial_menu_exists():
	# Check if a RadialMenu node already exists
	var existing_menu = get_node_or_null("/root/RadialMenu")
	if existing_menu:
		radial_menu = existing_menu
		return
	
	# Look for a radial menu in the scene
	var candidate_menus = get_tree().get_nodes_in_group("radial_menu")
	if candidate_menus.size() > 0:
		radial_menu = candidate_menus[0]
		return
	
	# Create a new RadialMenu if we have the scene
	var radial_menu_scene = load("res://Scenes/UI/Player/RadialMenu.tscn") if ResourceLoader.exists("res://Scenes/UI/Player/RadialMenu.tscn") else null
	if radial_menu_scene:
		radial_menu = radial_menu_scene.instantiate()
		radial_menu.name = "RadialMenu"
		get_tree().root.add_child(radial_menu)
		
		# Connect signals
		if radial_menu.has_signal("option_selected") and !radial_menu.is_connected("option_selected", Callable(self, "_on_radial_option_selected")):
			radial_menu.connect("option_selected", Callable(self, "_on_radial_option_selected"))
	else:
		print("ClickSystem: RadialMenu.tscn not found. No radial menu will be available.")

func show_radial_menu(entity, screen_position: Vector2):
	if !radial_menu:
		return
	
	# Generate options for the entity
	var options = []
	
	# Get options from entity if it provides them
	if entity.has_method("get_interaction_options"):
		options = entity.get_interaction_options(player)
	else:
		# Generate default options
		options = generate_default_options(entity)
	
	# Show the menu
	radial_menu.show_menu(options, screen_position)
	
	# Emit signal for other systems
	emit_signal("radial_menu_requested", entity, options, screen_position)

func generate_default_options(entity):
	var options = []
	
	# Add examine option
	options.append({
		"name": "Examine",
		"icon": "examine",
		"callback": func(): examine_entity(entity)
	})
	
	# Add type-specific options
	if "entity_type" in entity:
		match entity.entity_type:
			"item":
				if "pickupable" in entity and entity.pickupable:
					options.append({
						"name": "Pick Up",
						"icon": "pickup",
						"callback": func(): pick_up_item(entity)
					})
				
				options.append({
					"name": "Use",
					"icon": "use",
					"callback": func(): use_item(entity)
				})
			
			"character":
				options.append({
					"name": "Talk To",
					"icon": "talk",
					"callback": func(): talk_to_entity(entity)
				})
				
				options.append({
					"name": "Attack",
					"icon": "attack",
					"callback": func(): attack_entity(entity)
				})
	
	# Add NPC-specific options
	if entity.has_meta("is_npc") and entity.get_meta("is_npc"):
		options.append({
			"name": "Follow",
			"icon": "follow",
			"callback": func(): set_npc_follow(entity)
		})
		
		options.append({
			"name": "Stop",
			"icon": "stop",
			"callback": func(): set_npc_stop(entity)
		})
	
	return options

func _on_radial_option_selected(option, entity):
	# Execute the callback
	if "callback" in option and option.callback is Callable:
		option.callback.call()

# === TARGET ZONE HANDLING ===
func cycle_target_zone(direction_up: bool):
	if !player:
		return
	
	# Find current zone
	var current_zone = ""
	if "zone_selected" in player:
		current_zone = player.zone_selected
	
	# Define zones in order
	var zones = [
		player.BODY_ZONE_HEAD,
		player.BODY_ZONE_CHEST,
		player.BODY_ZONE_L_ARM,
		player.BODY_ZONE_R_ARM,
		player.BODY_ZONE_L_LEG,
		player.BODY_ZONE_R_LEG
	]
	
	# Find current index
	var current_index = zones.find(current_zone)
	if current_index == -1:
		current_index = 0
	
	# Calculate next index
	var next_index = current_index
	if direction_up:
		next_index = (current_index + 1) % zones.size()
	else:
		next_index = (current_index - 1 + zones.size()) % zones.size()
	
	# Set new zone
	if player.has_method("set_selected_zone"):
		player.set_selected_zone(zones[next_index])

# === ENTITY INTERACTION HELPERS ===
func examine_entity(entity):
	if !entity:
		return
	
	# Use the entity's examine method if available
	if entity.has_method("examine"):
		var examine_text = entity.examine(player)
		
		# Use sensory system to display text if available
		if sensory_system:
			sensory_system.display_message(examine_text)
		else:
			# Fallback to print
			print("Examining: ", entity.name if "name" in entity else "Unknown")
			print(examine_text)

# Examine a tile
func examine_tile(tile_coords, z_level):
	if !world:
		return
	
	var tile_data = world.get_tile_data(tile_coords, z_level)
	if !tile_data:
		return
	
	var description = "You see nothing special."
	
	# Generate description based on tile components
	if "door" in tile_data:
		description = "A door. It appears to be " + ("closed" if tile_data.door.closed else "open") + "."
		
		if "locked" in tile_data.door and tile_data.door.locked:
			description += " It seems to be locked."
			
		if "broken" in tile_data.door and tile_data.door.broken:
			description += " It looks broken."
	
	elif "window" in tile_data:
		description = "A window made of glass."
		
		if "reinforced" in tile_data.window and tile_data.window.reinforced:
			description += " It appears to be reinforced."
			
		if "health" in tile_data.window and tile_data.window.health < tile_data.window.max_health:
			description += " It has some cracks."
	
	elif "floor" in tile_data:
		description = "A " + tile_data.floor.type + " floor."
	
	elif "wall" in tile_data:
		description = "A solid wall made of " + tile_data.wall.material + "."
	
	# Display the description
	if sensory_system:
		sensory_system.display_message(description)
	else:
		print("Examining tile: ", description)

func pick_up_item(item):
	if !item or !player:
		return
	
	# Use player to pick up item
	if player.has_method("try_pick_up_item"):
		player.try_pick_up_item(item)
	elif player.has_method("pick_up_item"):
		player.pick_up_item(item)

func use_item(item):
	if !item or !player:
		return
	
	# Use the item's use method if available
	if item.has_method("use"):
		item.use(player)
	
	# Fallback to interact
	elif item.has_method("interact"):
		item.interact(player)

func talk_to_entity(entity):
	if !entity or !player:
		return
	
	# Use the entity's talk method if available
	if entity.has_method("talk"):
		entity.talk(player)
	elif entity.has_method("speak_to"):
		entity.speak_to(player)

func attack_entity(entity):
	if !entity or !player:
		return
	
	# Use player to attack
	if player.has_method("attack"):
		player.attack(entity)
	
	# Alternative methods if needed
	elif player.has_method("attack_atom"):
		player.attack_atom(entity)

# NPC-specific interaction helpers
func set_npc_follow(npc):
	if !npc or !player:
		return
	
	if npc.has_method("set_follow_target"):
		npc.set_follow_target(player)
	elif npc.has_method("follow"):
		npc.follow(player)

func set_npc_stop(npc):
	if !npc:
		return
	
	if npc.has_method("stop"):
		npc.stop()
	elif npc.has_method("set_follow_target"):
		npc.set_follow_target(null)

# === UTILITY FUNCTIONS ===
func get_tile_at_position(world_pos: Vector2) -> Vector2i:
	# Convert world position to tile coordinates
	var tile_x = int(world_pos.x / TILE_SIZE)
	var tile_y = int(world_pos.y / TILE_SIZE)
	return Vector2i(tile_x, tile_y)

func tile_to_world(tile_pos: Vector2i) -> Vector2:
	# Convert tile position to world coordinates (center of tile)
	return Vector2(
		(tile_pos.x * TILE_SIZE) + (TILE_SIZE / 2.0),
		(tile_pos.y * TILE_SIZE) + (TILE_SIZE / 2.0)
	)

func get_clickable_at_position(world_pos: Vector2):
	var entity = find_best_entity_under_cursor(world_pos)
	return entity

func is_position_interactable(world_pos: Vector2) -> bool:
	# Check if there's a clickable entity
	if get_clickable_at_position(world_pos):
		return true
	
	# Check if tile is interactable
	var tile_pos = get_tile_at_position(world_pos)
	var z_level = player.current_z_level if player else 0
	
	if world and world.has_method("is_valid_tile"):
		return world.is_valid_tile(tile_pos, z_level)
	
	return false

func is_point_inside_sprite(sprite: Node2D, global_point: Vector2) -> bool:
	"""Simple hit testing"""
	
	# For HumanSpriteSystem, check if point is within any visible body part
	if sprite is HumanSpriteSystem:
		return is_point_inside_human_sprite_system(sprite, global_point)
	
	# For regular Sprite2D nodes, do simple bounds checking
	elif sprite is Sprite2D:
		return is_point_inside_sprite2d(sprite, global_point)
	
	# For other Node2D types, just check if they have a position and are reasonably close
	else:
		var distance = global_point.distance_to(sprite.global_position)
		return distance <= 32.0  # Within one tile

func is_point_inside_human_sprite_system(human_sprite_system: HumanSpriteSystem, global_point: Vector2) -> bool:
	"""Check if point hits any visible body part of the character"""
	
	# Quick distance check first - if too far away, definitely not a hit
	var distance = global_point.distance_to(human_sprite_system.global_position)
	if distance > 48.0:  # 1.5 tiles max distance
		return false
	
	# Check each visible body part sprite
	var sprites_container = human_sprite_system.get_node_or_null("Sprites")
	if not sprites_container:
		return false
	
	# Check body parts in order of visual priority
	var body_part_names = ["BodySprite", "HeadSprite", "LeftArmSprite", "RightArmSprite", 
						   "LeftHandSprite", "RightHandSprite", "LeftLegSprite", "RightLegSprite",
						   "LeftFootSprite", "RightFootSprite"]
	
	for part_name in body_part_names:
		var sprite = sprites_container.get_node_or_null(part_name)
		if sprite and sprite.visible and sprite.texture:
			if is_point_inside_sprite2d(sprite, global_point):
				return true
	
	# Also check equipment sprites if visible
	var equipment_container = human_sprite_system.get_node_or_null("EquipmentContainer")
	if equipment_container:
		for child in equipment_container.get_children():
			if child is Node2D:
				for equipment_child in child.get_children():
					if equipment_child is Sprite2D and equipment_child.visible and equipment_child.texture:
						if is_point_inside_sprite2d(equipment_child, global_point):
							return true
	
	return false

func is_point_inside_sprite2d(sprite: Sprite2D, global_point: Vector2) -> bool:
	"""Simple bounds-based hit testing for Sprite2D"""
	
	if not sprite.visible or not sprite.texture:
		return false
	
	# Convert global point to sprite's local coordinates
	var local_point = sprite.to_local(global_point)
	
	# Get sprite bounds
	var texture_size = sprite.texture.get_size()
	var sprite_size = texture_size
	
	# Account for region if enabled
	if sprite.region_enabled:
		sprite_size = sprite.region_rect.size
	
	# Account for scale
	sprite_size *= sprite.scale
	
	# Since sprite is centered, bounds are from -size/2 to size/2
	var half_size = sprite_size / 2.0
	
	# Check if point is within bounds
	return (local_point.x >= -half_size.x and local_point.x <= half_size.x and
			local_point.y >= -half_size.y and local_point.y <= half_size.y)

func get_most_accurate_entity_at_position(world_pos: Vector2):
	print("ClickSystem: Looking for entity at ", world_pos)
	
	var candidates = []
	var max_distance = 20.0
	
	var clickables = get_tree().get_nodes_in_group("clickable_entities")
	
	for entity in clickables:
		if not is_instance_valid(entity):
			continue
		
		# NO LONGER FILTERING OUT NPCs - they should be clickable!
		# This was the bug - the old code was intentionally skipping all NPCs
		
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
			print("ClickSystem: Found candidate: ", entity.name, " distance: ", distance, " is_npc: ", entity.has_meta("is_npc") and entity.get_meta("is_npc"))
	
	if candidates.size() == 0:
		print("ClickSystem: No clickable entities found")
		return null
	
	# Sort by priority first, then by distance
	candidates.sort_custom(func(a, b): 
		if a.priority != b.priority:
			return a.priority > b.priority  # Higher priority first
		return a.distance < b.distance     # Closer distance if same priority
	)
	
	var best_candidate = candidates[0]
	print("ClickSystem: Selected entity: ", best_candidate.entity.name, " (priority: ", best_candidate.priority, ", distance: ", best_candidate.distance, ")")
	
	return best_candidate.entity

func get_entity_click_priority(entity) -> int:
	var priority = 0
	
	# Check if entity has explicit click priority
	if "click_priority" in entity:
		priority = entity.click_priority
	elif entity.has_meta("click_priority"):
		priority = entity.get_meta("click_priority")
	
	# Boost priority for certain entity types
	if "entity_type" in entity:
		match entity.entity_type:
			"character", "mob":
				priority += 20  # Characters are high priority
			"item":
				priority += 10  # Items are medium priority
			"structure":
				priority += 5   # Structures are lower priority
	
	# NPCs get slightly lower priority than players but are still clickable
	if entity.has_meta("is_npc") and entity.get_meta("is_npc"):
		priority += 15  # NPCs are high priority but slightly less than players
	
	# Boost priority for items that can be picked up
	if "pickupable" in entity and entity.pickupable:
		priority += 15
	
	# Boost priority for interactive objects
	if entity.has_method("interact") or entity.has_method("attack_hand"):
		priority += 5
	
	return priority

func find_best_entity_under_cursor(position: Vector2) -> Node:
	var clickable_nodes = get_tree().get_nodes_in_group("clickable_entities")
	var best_entity = null
	var closest_distance = 32.0  # Max click distance (1 tile)
	
	for node in clickable_nodes:
		if not is_instance_valid(node):
			continue
		
		# NO LONGER FILTERING OUT NPCs - they should be clickable!
		
		var node_pos = Vector2.ZERO
		if "global_position" in node:
			node_pos = node.global_position
		elif "position" in node:
			node_pos = node.position
		else:
			continue
			
		var distance = position.distance_to(node_pos)
		if distance < closest_distance:
			closest_distance = distance
			best_entity = node
	
	return best_entity

func is_click_intercepted_by_ui(click_position: Vector2) -> bool:
	"""Determine if a click should be intercepted by UI elements"""
	# Always check if PlayerUI wants this click first
	if player_ui and player_ui.has_method("is_position_in_ui_element"):
		if player_ui.is_position_in_ui_element(click_position):
			# PlayerUI will handle this click
			return true
	
	# Otherwise check other UI elements as before
	var ui_elements = get_tree().get_nodes_in_group("ui_elements")
	for element in ui_elements:
		if element is Control and element.visible and element.get_global_rect().has_point(click_position):
			# Skip if the control explicitly passes mouse events
			if element.mouse_filter == Control.MOUSE_FILTER_IGNORE:
				continue
				
			# The element will intercept the click
			return true
	
	# Check UI buttons group
	var ui_buttons = get_tree().get_nodes_in_group("ui_buttons")
	for button in ui_buttons:
		if button is Control and button.visible and button.get_global_rect().has_point(click_position):
			# The button will intercept the click
			return true
			
	return false

func _check_canvaslayer_for_ui(canvas_layer: CanvasLayer, position: Vector2) -> bool:
	"""Helper function to recursively check a CanvasLayer for UI elements at a position"""
	for child in canvas_layer.get_children():
		# Skip non-Control nodes and invisible nodes
		if not child is Control or not child.visible:
			continue
		
		# Skip if the control explicitly passes mouse events
		if child.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
			
		# Check if this control is at the position
		if child.get_global_rect().has_point(position):
			if click_through_windows and child.is_in_group("windows"):
				continue
			
			# This control will intercept the click
			return true
			
		# Recursively check children of containers
		if child is Container or child is Control:
			for sub_child in child.get_children():
				if sub_child is Control and sub_child.visible:
					# Skip if the child passes mouse events
					if sub_child.mouse_filter == Control.MOUSE_FILTER_IGNORE:
						continue
						
					if sub_child.get_global_rect().has_point(position):
						if click_through_windows and sub_child.is_in_group("windows"):
							continue
						
						# This control will intercept the click
						return true
	
	return false

func get_entity_type(entity) -> String:
	# Try to determine entity type
	if !entity:
		return "unknown"
	
	# Check for entity_type property
	if "entity_type" in entity:
		return entity.entity_type
	
	# Check for class inheritance or groups
	if entity.is_in_group("items"):
		return "item"
	elif entity.is_in_group("characters") or entity.is_in_group("npcs"):
		return "character"
	elif entity.is_in_group("clickable_entities"):
		return "entity"
	
	return "unknown"

func update_hover_entity():
	# Find entity under mouse cursor
	var mouse_pos = get_viewport().get_mouse_position()
	var world_pos = get_global_mouse_position()
	var entity = get_clickable_at_position(world_pos)
	
	# If entity changed, update hover status
	if entity != hover_entity:
		# Remove hover effect from previous entity
		if hover_entity and hover_entity.has_method("set_highlighted"):
			hover_entity.set_highlighted(false)
		
		# Set new hover entity
		hover_entity = entity
		
		# Add hover effect to new entity
		if hover_entity and hover_entity.has_method("set_highlighted"):
			hover_entity.set_highlighted(true)
		
		# Update cursor if we have a controller
		if cursor_controller:
			if hover_entity:
				cursor_controller.set_cursor_mode("pointer")
			else:
				cursor_controller.set_cursor_mode("default")

func _on_node_added_to_scene(node):
	# Check if this is a player controller
	if !player and node.is_in_group("player_controller"):
		player = node
		print("ClickSystem: Automatically found player controller node:", node.name)

func find_parent_of_type(type_name):
	var current = get_parent()
	while current:
		if current.get_class() == type_name:
			return current
		current = current.get_parent()
	return null

func _get_settings():
	# Try to get settings from global managers
	var settings = get_node_or_null("/root/SettingsManager")
	if !settings:
		settings = get_node_or_null("/root/GameSettings")
	return settings

# === PUBLIC API ===
func set_player_reference(player_node):
	# Validate that this is actually a player, not an NPC
	if not player_node:
		player = null
		print("ClickSystem: Player reference cleared")
		return
	
	# CRITICAL: Reject NPCs
	if player_node.has_meta("is_npc") and player_node.get_meta("is_npc"):
		print("ClickSystem: ERROR - Attempted to set NPC as player reference! Rejecting.")
		return
	
	# Verify this is marked as a player
	if not (player_node.has_meta("is_player") and player_node.get_meta("is_player")):
		print("ClickSystem: WARNING - Player node not properly marked as player")
	
	# Verify it's a local player
	if "is_local_player" in player_node and not player_node.is_local_player:
		print("ClickSystem: WARNING - Setting non-local player as reference")
	
	player = player_node
	print("ClickSystem: Player reference set to: ", player.name)
	
	# Validate that the player has required methods
	if not player.has_method("process_interaction"):
		print("ClickSystem: Warning - Player missing process_interaction method!")

func register_player_ui(ui_instance):
	"""Register the PlayerUI to ensure proper coordination"""
	player_ui = ui_instance
	print("ClickSystem: PlayerUI registered: ", ui_instance.name if ui_instance else "NULL")

func set_grid_controller_reference(controller):
	# For backward compatibility - in our structure, player IS the grid controller
	player = controller
	print("ClickSystem: Player reference set to: ", player.name if player else "NULL")

func set_click_through_windows(enable: bool):
	click_through_windows = enable

func set_click_drag_enabled(enable: bool):
	click_drag_enabled = enable

func set_double_click_enabled(enable: bool):
	double_click_enabled = enable
