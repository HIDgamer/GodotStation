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
signal weapon_fired(target_position, weapon) # New signal for weapon firing

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

# Weapon tracking
var is_in_combat_mode: bool = false  # Whether the player is in combat mode

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
	# Try to find player (GridMovementController) if not already set
	if !player:
		# Look in player_controller group
		var players = get_tree().get_nodes_in_group("player_controller")
		if players.size() > 0:
			player = players[0]
			print("ClickSystem: Found player controller: ", player.name)
		else:
			print("ClickSystem: No player controller found in group 'player_controller'")
			
	# Connect to tile system if world exists
	if world:
		tile_occupancy_system = world.get_node_or_null("TileOccupancySystem")
		spatial_manager = world.get_node_or_null("SpatialManager")
		sensory_system = world.get_node_or_null("SensorySystem")
	
	# Create or find radial menu
	ensure_radial_menu_exists()
	
	print("ClickSystem: Connected to systems")
	print("  - Player: ", "Found" if player else "Not found")
	print("  - TileOccupancySystem: ", "Found" if tile_occupancy_system else "Not found")
	print("  - SpatialManager: ", "Found" if spatial_manager else "Not found")
	print("  - CursorController: ", "Found" if cursor_controller else "Not found")

# === INPUT PROCESSING ===
func _input(event):
	# Only handle mouse events
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	
	# Check if UI system is handling this input
	var input_manager = get_node_or_null("/root/InputPriorityManager")
	if input_manager and input_manager.is_ui_active():
		# UI is active - don't process this event
		return
	
	# Check if this event should be intercepted by UI
	if event is InputEventMouseButton and event.pressed:
		if input_manager and input_manager.is_over_ui(event.position):
			# UI will handle this - don't process
			return
	
	# Process as normal - UI isn't handling this
	if event is InputEventMouseButton:
		handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		handle_mouse_motion(event)

# Process hover effects and cooldowns
func _process(delta):
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
			if is_in_combat_mode:
				cursor_controller.set_cursor_mode("target")
			else:
				cursor_controller.set_cursor_mode("pointer")
		else:
			if is_in_combat_mode:
				cursor_controller.set_cursor_mode("target")
			else:
				cursor_controller.set_cursor_mode("default")

# === BUTTON HANDLERS ===
func handle_button_press(button_index: int, mouse_pos: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	"""Handle mouse button press with improved accuracy"""
	# Check if UI should intercept this click
	if is_click_intercepted_by_ui(mouse_pos):
		click_intercepted = true
		return
	
	# Store click start data
	click_start_position = mouse_pos
	last_click_button = button_index
	click_intercepted = false
	
	# Get precise global mouse position
	var world_pos = get_global_mouse_position()
	
	# Check for double click with improved accuracy
	var current_time = Time.get_ticks_msec() / 1000.0
	var is_double_click = false
	
	if double_click_enabled and button_index == last_click_button:
		var time_since_last_click = current_time - last_click_time
		var distance_from_last_click = mouse_pos.distance_to(last_click_position)
		
		# More accurate double-click criteria
		if time_since_last_click < DOUBLE_CLICK_TIME and distance_from_last_click < 10:
			# Check if the same entity is clicked twice
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
	# Get entity or tile at position
	var world_pos = get_global_mouse_position()
	var click_target = get_clickable_at_position(world_pos)
	
	# First, try to fire weapon if we have one and are in combat mode or holding Shift
	if try_fire_active_weapon(world_pos, shift_pressed):
		# Weapon fired, don't do normal click handling
		return
	
	# Regular click handling for entities and tiles
	if click_target:
		click_on_entity(click_target, MOUSE_BUTTON_LEFT, shift_pressed, ctrl_pressed, alt_pressed)
		drag_source = click_target
	else:
		# Click on tile instead
		var tile_pos = get_tile_at_position(world_pos)
		click_on_tile(tile_pos, MOUSE_BUTTON_LEFT, shift_pressed, ctrl_pressed, alt_pressed)

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

# === WEAPON HANDLING ===

# Try to fire the player's active weapon
func try_fire_active_weapon(target_position, force_fire = false) -> bool:
	if !player:
		return false
	
	# Get active weapon
	var weapon = get_active_weapon()
	if !weapon:
		return false
	
	# Try to fire the weapon
	if weapon.has_method("try_fire"):
		if weapon.try_fire(target_position):
			# Weapon fired successfully
			emit_signal("weapon_fired", target_position, weapon)
			
			# Add small cooldown to prevent double fires
			click_cooldown_timer = CLICK_COOLDOWN * 2
			return true
	
	return false

# Get the player's active weapon if one exists
func get_active_weapon():
	if !player:
		return null
	
	# Try to get active item
	var active_item = null
	
	# First try WeaponController
	var weapon_controller = player.get_node_or_null("WeaponController")
	if weapon_controller and weapon_controller.has_method("get_active_weapon"):
		active_item = weapon_controller.get_active_weapon()
	
	# Fall back to inventory system
	if !active_item and player.has_method("get_active_item"):
		active_item = player.get_active_item()
	elif !active_item and player.has_node("InventorySystem"):
		var inventory = player.get_node("InventorySystem")
		if inventory.has_method("get_active_item"):
			active_item = inventory.get_active_item()
	
	# Check if the active item is a weapon
	if active_item:
		if ("tool_behaviour" in active_item and active_item.tool_behaviour == "weapon") or active_item.has_method("try_fire"):
			return active_item
	
	return null

# === INTERACTION HANDLERS ===
func click_on_entity(entity, button_index: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	if !entity:
		return
	
	# Emit entity clicked signal
	emit_signal("entity_clicked", entity, button_index, shift_pressed, ctrl_pressed, alt_pressed)
	
	# Track entity
	last_entity_clicked = entity
	
	# Let player handle the click on the entity
	if player:
		# Determine interaction based on modifier keys
		if shift_pressed and ctrl_pressed:
			if player.has_method("CtrlShiftClickOn"):
				player.CtrlShiftClickOn(entity)
		elif shift_pressed:
			if player.has_method("ShiftClickOn"):
				player.ShiftClickOn(entity)
		elif ctrl_pressed:
			if player.has_method("CtrlClickOn"):
				player.CtrlClickOn(entity)
		elif alt_pressed:
			if player.has_method("AltClickOn"):
				player.AltClickOn(entity)
		else:
			# Standard interaction - check for combat mode first
			if is_in_combat_mode and button_index == MOUSE_BUTTON_LEFT:
				handle_attack(player, entity)
			else:
				# Normal interaction
				if button_index == MOUSE_BUTTON_LEFT:
					# First check on_entity_clicked which is more explicit
					if player.has_method("on_entity_clicked"):
						player.on_entity_clicked(entity)
					else:
						# Fall back to ClickOn which is more general
						player.ClickOn(entity)
				elif button_index == MOUSE_BUTTON_RIGHT:
					if player.has_method("RightClickOn"):
						player.RightClickOn(entity)
				elif button_index == MOUSE_BUTTON_MIDDLE:
					if player.has_method("MiddleClickOn"):
						player.MiddleClickOn(entity)
	
	# If the entity has a specific interaction method, use it
	if button_index == MOUSE_BUTTON_LEFT and entity.has_method("interact"):
		entity.interact(player)

func click_on_tile(tile_coords: Vector2i, button_index: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	# Emit tile clicked signal
	emit_signal("tile_clicked", tile_coords, button_index, shift_pressed, ctrl_pressed, alt_pressed)
	
	# Let player handle the click on the tile
	if player:
		# Handle clicks on tiles
		if player.has_method("_on_tile_clicked"):
			player._on_tile_clicked(tile_coords, button_index, shift_pressed, ctrl_pressed, alt_pressed)
		else:
			# Handle right click on tile
			if button_index == MOUSE_BUTTON_RIGHT and player.has_method("handle_tile_context_menu"):
				player.handle_tile_context_menu(tile_coords, player.current_z_level)
			
			# Handle middle click on tile
			elif button_index == MOUSE_BUTTON_MIDDLE and player.has_method("point_to"):
				var world_pos = tile_to_world(tile_coords)
				player.point_to(world_pos)

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
	
	# Add weapon-specific options if entity is a weapon
	if "tool_behaviour" in entity and entity.tool_behaviour == "weapon":
		# Add firing mode toggle option
		options.append({
			"name": "Toggle Firing Mode",
			"icon": "mode",
			"callback": func(): toggle_weapon_firing_mode(entity)
		})
		
		# Add safety toggle option
		options.append({
			"name": "Toggle Safety",
			"icon": "safety",
			"callback": func(): toggle_weapon_safety(entity)
		})
		
		# Add reload option if weapon has ammo
		if "current_ammo" in entity and "max_rounds" in entity:
			options.append({
				"name": "Reload",
				"icon": "reload",
				"callback": func(): reload_weapon(entity)
			})
		
		# Add wielding toggle for two-handed weapons
		if "two_handed" in entity and entity.two_handed:
			options.append({
				"name": "Toggle Wielding",
				"icon": "wield",
				"callback": func(): toggle_weapon_wielding(entity)
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
	
	return options

func _on_radial_option_selected(option, entity):
	# Execute the callback
	if "callback" in option and option.callback is Callable:
		option.callback.call()

# Weapon-specific radial menu actions
func toggle_weapon_firing_mode(weapon):
	if weapon.has_method("toggle_firing_mode"):
		weapon.toggle_firing_mode()

func toggle_weapon_safety(weapon):
	if weapon.has_method("toggle_safety"):
		weapon.toggle_safety()

func reload_weapon(weapon):
	if weapon.has_method("start_reload"):
		weapon.start_reload()

func toggle_weapon_wielding(weapon):
	if weapon.has_method("toggle_wielding") and player:
		weapon.toggle_wielding(player)

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
	return find_best_entity_under_cursor(world_pos)

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
	"""Perform pixel-perfect hit testing for a sprite or sprite-like node"""
	var texture = null
	var use_pixel_test = false
	
	# Get the texture based on node type
	if sprite is Sprite2D:
		texture = sprite.texture
		use_pixel_test = true
	elif sprite is HumanSpriteSystem and sprite.sprite_frames:
		var frames = sprite.sprite_frames
		if frames.has_animation(sprite.animation):
			texture = frames.get_frame_texture(sprite.animation, sprite.frame)
			use_pixel_test = true
	elif "texture" in sprite and sprite.texture != null:
		texture = sprite.texture
		use_pixel_test = true
	
	# If we couldn't get a texture or shouldn't do pixel testing
	if not texture or not use_pixel_test:
		return false
	
	# Convert global point to local coordinates
	var local_point = sprite.to_local(global_point)
	
	# Get sprite dimensions and scale
	var sprite_width = texture.get_width()
	var sprite_height = texture.get_height()
	var sprite_scale = Vector2(1, 1)
	
	if "scale" in sprite:
		sprite_scale = sprite.scale
	
	# Adjust for sprite's origin, offset and scale
	var sprite_offset = Vector2.ZERO
	if "offset" in sprite:
		sprite_offset = sprite.offset
	
	# Calculate texture coordinates
	var tex_x = (local_point.x / sprite_scale.x) + (sprite_width * 0.5) - sprite_offset.x
	var tex_y = (local_point.y / sprite_scale.y) + (sprite_height * 0.5) - sprite_offset.y
	
	# Check if outside texture bounds
	if tex_x < 0 or tex_x >= sprite_width or tex_y < 0 or tex_y >= sprite_height:
		return false
	
	# If we have image data available, check pixel transparency
	var img = null
	
	# Try to get image data
	if texture.get_class() == "ImageTexture" or texture.get_class() == "CompressedTexture2D":
		# In Godot 4, get_image() returns a copy of the image
		img = texture.get_image() if texture.has_method("get_image") else null
	
	# Check pixel alpha if we have image data
	if img != null and not img.is_empty():
		# Get pixel alpha at that position
		var color = img.get_pixel(int(tex_x), int(tex_y))
		return color.a > 0.1  # Require at least 10% opacity to be clickable
	
	# Fallback: no image data available, assume opaque
	return true

func get_most_accurate_entity_at_position(world_pos: Vector2):
	"""Get the most accurately clicked entity using pixel-perfect testing when possible"""
	# Get candidates using the existing method
	var candidates = []
	var z_level = player.current_z_level if player else 0
	
	# Use spatial partitioning if available
	if spatial_manager and spatial_manager.has_method("get_entities_in_radius"):
		candidates = spatial_manager.get_entities_in_radius(world_pos, 20, z_level)
	else:
		# Fall back to checking all clickable entities
		var clickables = get_tree().get_nodes_in_group("clickable_entities")
		for entity in clickables:
			if is_instance_valid(entity):
				var entity_pos = Vector2.ZERO
				if "global_position" in entity:
					entity_pos = entity.global_position
				elif "position" in entity:
					entity_pos = entity.position
				else:
					continue
				
				if world_pos.distance_to(entity_pos) <= 20:
					candidates.append(entity)
	
	# No candidates found
	if candidates.size() == 0:
		return null
	
	# First check for sprites that have pixel-perfect hit detection
	for entity in candidates:
		var sprite = null
		
		# Find the sprite component
		if entity is Sprite2D:
			sprite = entity
		elif entity.has_node("HumanSpriteSystem"):
			sprite = entity.get_node("HumanSpriteSystem")
		elif entity.has_node("HumanSpriteSystem"):
			var visual = entity.get_node("HumanSpriteSystem")
			if visual is Sprite2D:
				sprite = visual
		
		# If entity has a sprite, try pixel-perfect detection
		if sprite:
			if is_point_inside_sprite(sprite, world_pos):
				return entity
	
	# Fall back to the top candidate based on priority
	return candidates[0]

func find_best_entity_under_cursor(position: Vector2) -> Node:
	"""Find the most relevant entity under the cursor in Godot 4"""
	# Priority queue for entities (will be sorted by priority)
	var entities = []
	
	# Step 1: Get all entities in clickable_entities group
	var clickable_nodes = get_tree().get_nodes_in_group("clickable_entities")
	
	# Filter down to those close to the click
	var max_click_distance = 32.0  # Max distance to consider for clicking
	
	for node in clickable_nodes:
		# Skip invalid nodes
		if not is_instance_valid(node):
			continue
			
		# Get node position
		var node_pos = Vector2.ZERO
		if "global_position" in node:
			node_pos = node.global_position
		elif "position" in node:
			node_pos = node.position
		else:
			continue
			
		# Check distance
		var distance = position.distance_to(node_pos)
		if distance > max_click_distance:
			continue
			
		# Get node priority
		var priority = 0
		if "click_priority" in node:
			priority = node.click_priority
		elif node is Node2D:
			# Use z_index for Node2D
			priority = node.z_index
			
		# Check for sprite for potential pixel-perfect testing
		var has_sprite = false
		var sprite_node = null
		
		if node is Sprite2D or node is AnimatedSprite2D:
			has_sprite = true
			sprite_node = node
		elif node.has_node("Sprite2D"):
			has_sprite = true
			sprite_node = node.get_node("Sprite2D")
		elif node.has_node("AnimatedSprite2D"):
			has_sprite = true
			sprite_node = node.get_node("AnimatedSprite2D")
			
		# Do pixel-perfect testing if possible
		var is_pixel_perfect = false
		if has_sprite and sprite_node:
			is_pixel_perfect = is_point_inside_sprite(sprite_node, position)
			# Boost priority for pixel-perfect hits
			if is_pixel_perfect:
				priority += 1000  # Large priority boost for pixel-perfect
				
		# Add to candidates list with metadata
		entities.append({
			"node": node,
			"distance": distance,
			"priority": priority,
			"pixel_perfect": is_pixel_perfect
		})
	
	# No entities found
	if entities.size() == 0:
		return null
		
	# Sort entities by priority (higher is better)
	entities.sort_custom(func(a, b): 
		# Pixel-perfect hits get highest priority
		if a.pixel_perfect and not b.pixel_perfect:
			return true
		if b.pixel_perfect and not a.pixel_perfect:
			return false
			
		# Then check priority value
		if a.priority != b.priority:
			return a.priority > b.priority
			
		# Then check distance (closer is better)
		return a.distance < b.distance
	)
	
	# Return the highest priority entity
	return entities[0].node

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
		
	# Check for weapon
	if "tool_behaviour" in entity and entity.tool_behaviour == "weapon":
		return "weapon"
	
	# Check for class inheritance or groups
	if entity.is_in_group("items"):
		return "item"
	elif entity.is_in_group("characters"):
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
			if is_in_combat_mode:
				cursor_controller.set_cursor_mode("target")
			elif hover_entity:
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
	player = player_node
	print("ClickSystem: Player reference set to: ", player.name if player else "NULL")

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
	
# Set combat mode
func toggle_combat_mode(enabled: bool):
	is_in_combat_mode = enabled
	
# Check if the player is in combat mode
func is_combat_mode_active() -> bool:
	return is_in_combat_mode

func register_player_ui(ui_instance):
	"""Register the PlayerUI to ensure proper coordination"""
	player_ui = ui_instance
	print("ClickSystem: PlayerUI registered for click coordination")
