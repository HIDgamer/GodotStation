extends Control
class_name ContextMenuSystem

# Signal declarations
signal option_selected(option)
signal menu_closed()

# References
var world = null
var player = null
var click_system = null

# Menu properties
var menu_visible = false
var current_target = null
var menu_position = Vector2.ZERO
var option_list = []

# UI components
var option_container: VBoxContainer
var menu_panel: PanelContainer
var animation_player: AnimationPlayer
var title_label: Label
var scroll_container: ScrollContainer

# Appearance
@export var menu_width: int = 220
@export var max_menu_height: int = 320
@export var option_height: int = 36
@export var use_icons: bool = true
@export var show_title: bool = true
@export var title_height: int = 30

# Initialize the system
func _ready():
	# Create UI elements with improved styling
	_create_ui_elements()
	
	# Hide menu initially
	menu_panel.visible = false
	menu_visible = false
	
	# Try to get click system
	click_system = get_node_or_null("/root/ClickSystem")
	if !click_system and get_parent():
		click_system = get_parent().get_node_or_null("ClickSystem")
	
	# Connect signals if click system found
	if click_system:
		if click_system.has_signal("entity_clicked") and !click_system.is_connected("entity_clicked", Callable(self, "_on_entity_clicked")):
			click_system.connect("entity_clicked", Callable(self, "_on_entity_clicked"))
		
		if click_system.has_signal("tile_clicked") and !click_system.is_connected("tile_clicked", Callable(self, "_on_tile_clicked")):
			click_system.connect("tile_clicked", Callable(self, "_on_tile_clicked"))

# Create necessary UI elements with improved styling
func _create_ui_elements():
	# Create menu panel using PanelContainer for better styling
	menu_panel = PanelContainer.new()
	menu_panel.name = "ContextMenu"
	menu_panel.visible = false
	menu_panel.custom_minimum_size = Vector2(menu_width, 0)  # Height will be determined by content
	menu_panel.pivot_offset = Vector2(menu_width/2, 0)  # For animations
	
	# Add a style to the panel
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.15, 0.15, 0.2, 0.95)
	panel_style.set_border_width_all(1)
	panel_style.border_color = Color(0.3, 0.3, 0.4, 1.0)
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	panel_style.shadow_color = Color(0, 0, 0, 0.3)
	panel_style.shadow_size = 4
	panel_style.shadow_offset = Vector2(2, 2)
	menu_panel.add_theme_stylebox_override("panel", panel_style)
	
	add_child(menu_panel)
	
	# Create a VBoxContainer as the main container
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	menu_panel.add_child(vbox)
	
	# Create title label (optional)
	if show_title:
		title_label = Label.new()
		title_label.text = "Interaction Menu"
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_label.custom_minimum_size = Vector2(0, title_height)
		title_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
		title_label.add_theme_font_size_override("font_size", 14)
		
		# Add a separator
		var separator = HSeparator.new()
		var sep_style = StyleBoxFlat.new()
		sep_style.bg_color = Color(0.3, 0.3, 0.4, 0.6)
		sep_style.content_margin_top = 1
		separator.add_theme_stylebox_override("separator", sep_style)
		
		vbox.add_child(title_label)
		vbox.add_child(separator)
	
	# Create scroll container for options
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	
	# Create a MarginContainer to add padding
	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	
	vbox.add_child(scroll_container)
	scroll_container.add_child(margin)
	
	# Create VBox for options
	option_container = VBoxContainer.new()
	option_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	option_container.add_theme_constant_override("separation", 6)
	margin.add_child(option_container)
	
	# Create animation player
	animation_player = AnimationPlayer.new()
	menu_panel.add_child(animation_player)
	
	# Create animations
	_create_animations()

# Create animations for menu - updated for Godot 4
func _create_animations():
	# Create an animation library
	var library = AnimationLibrary.new()
	
	# Create open animation
	var open_anim = Animation.new()
	open_anim.length = 0.3
	
	# Add a scale track
	var track_idx = open_anim.add_track(Animation.TYPE_VALUE)
	open_anim.track_set_path(track_idx, ".:scale")
	open_anim.track_insert_key(track_idx, 0.0, Vector2(1.0, 0.0))
	open_anim.track_insert_key(track_idx, 0.2, Vector2(1.0, 1.1))
	open_anim.track_insert_key(track_idx, 0.3, Vector2(1.0, 1.0))
	
	# Add modulate track for fade in
	track_idx = open_anim.add_track(Animation.TYPE_VALUE)
	open_anim.track_set_path(track_idx, ".:modulate")
	open_anim.track_insert_key(track_idx, 0.0, Color(1, 1, 1, 0))
	open_anim.track_insert_key(track_idx, 0.3, Color(1, 1, 1, 1))
	
	# Add the animation to the library
	library.add_animation("open", open_anim)
	
	# Create close animation
	var close_anim = Animation.new()
	close_anim.length = 0.3
	
	# Add a scale track
	track_idx = close_anim.add_track(Animation.TYPE_VALUE)
	close_anim.track_set_path(track_idx, ".:scale")
	close_anim.track_insert_key(track_idx, 0.0, Vector2(1.0, 1.0))
	close_anim.track_insert_key(track_idx, 0.3, Vector2(1.0, 0.0))
	
	# Add modulate track for fade out
	track_idx = close_anim.add_track(Animation.TYPE_VALUE)
	close_anim.track_set_path(track_idx, ".:modulate")
	close_anim.track_insert_key(track_idx, 0.0, Color(1, 1, 1, 1))
	close_anim.track_insert_key(track_idx, 0.3, Color(1, 1, 1, 0))
	
	# Add the animation to the library
	library.add_animation("close", close_anim)
	
	# Add the library to the animation player
	animation_player.add_animation_library("", library)

# Process input to handle menu closing
func _input(event):
	if !menu_visible:
		return
	
	# Close menu on escape or click outside
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_menu()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Only close if clicked outside the menu
		if !menu_panel.get_global_rect().has_point(event.position):
			close_menu()

# Show the context menu for an entity
func show_entity_menu(entity, position):
	if !entity:
		return
	
	# Clear previous options
	_clear_options()
	
	# Set current target
	current_target = entity
	
	# Set title if visible
	if show_title and title_label:
		if "name" in entity and entity.name:
			title_label.text = entity.name
		elif "entity_type" in entity:
			title_label.text = entity.entity_type.capitalize()
		else:
			title_label.text = "Interaction Menu"
	
	# Generate menu options for entity
	var options = []
	
	# If entity has method to provide options
	if entity.has_method("get_interaction_options"):
		options = entity.get_interaction_options(player)
	else:
		# Default options based on entity properties
		options = _generate_default_entity_options(entity)
	
	# Set options and position
	_set_options(options)
	_position_menu(position)
	
	# Show menu
	menu_panel.scale = Vector2(1.0, 0.0)
	menu_panel.modulate = Color(1, 1, 1, 0)
	menu_panel.visible = true
	menu_visible = true
	animation_player.play("open")

# Show the context menu for a tile
func show_tile_menu(tile_coords, z_level, position):
	# Clear previous options
	_clear_options()
	
	# Set tile as current target
	current_target = {"tile": tile_coords, "z_level": z_level}
	
	# Set title if visible
	if show_title and title_label:
		title_label.text = "Tile Options"
	
	# Generate menu options for tile
	var options = _generate_tile_options(tile_coords, z_level)
	
	# Set options and position
	_set_options(options)
	_position_menu(position)
	
	# Show menu
	menu_panel.scale = Vector2(1.0, 0.0)
	menu_panel.modulate = Color(1, 1, 1, 0)
	menu_panel.visible = true
	menu_visible = true
	animation_player.play("open")

# Generate default options for an entity
func _generate_default_entity_options(entity):
	var options = []
	
	# Always add examine
	options.append({
		"name": "Examine",
		"icon": "examine",
		"callback": Callable(self, "_on_examine_selected").bind(entity),
		"color": Color(0.4, 0.7, 1.0)
	})
	
	# Add options based on entity type
	if "entity_type" in entity:
		match entity.entity_type:
			"character":
				options.append({
					"name": "Talk to",
					"icon": "talk",
					"callback": Callable(self, "_on_talk_selected").bind(entity),
					"color": Color(0.4, 0.9, 0.4)
				})
				
				options.append({
					"name": "Attack",
					"icon": "attack",
					"callback": Callable(self, "_on_attack_selected").bind(entity),
					"color": Color(1.0, 0.4, 0.4)
				})
				
			"item":
				if "pickupable" in entity and entity.pickupable:
					options.append({
						"name": "Pick up",
						"icon": "pickup",
						"callback": Callable(self, "_on_pickup_selected").bind(entity),
						"color": Color(0.9, 0.8, 0.3)
					})
				
				options.append({
					"name": "Use",
					"icon": "use",
					"callback": Callable(self, "_on_use_selected").bind(entity),
					"color": Color(0.5, 0.9, 0.5)
				})
	
	# Add options based on components
	if "door" in entity:
		var door_text = "Close" if "closed" in entity.door and !entity.door.closed else "Open"
		options.append({
			"name": door_text + " Door",
			"icon": "door",
			"callback": Callable(self, "_on_toggle_door_selected").bind(entity),
			"color": Color(0.7, 0.6, 0.9)
		})
	
	return options

# Generate options for a tile
func _generate_tile_options(tile_coords, z_level):
	var options = []
	
	# Get tile data
	var tile_data = null
	if world and world.has_method("get_tile_data"):
		tile_data = world.get_tile_data(tile_coords, z_level)
	
	# Always add examine
	options.append({
		"name": "Examine Tile",
		"icon": "examine", 
		"callback": Callable(self, "_on_examine_tile_selected").bind(tile_coords, z_level),
		"color": Color(0.4, 0.7, 1.0)
	})
	
	# Add movement option
	options.append({
		"name": "Move Here",
		"icon": "move",
		"callback": Callable(self, "_on_move_to_tile_selected").bind(tile_coords, z_level),
		"color": Color(0.5, 0.8, 0.5)
	})
	
	# Check for tile objects
	if tile_data:
		# Door options
		if "door" in tile_data and tile_data.door:
			var door_text = "Open" if "closed" in tile_data.door and tile_data.door.closed else "Close"
			options.append({
				"name": door_text + " Door",
				"icon": "door",
				"callback": Callable(self, "_on_toggle_tile_door_selected").bind(tile_coords, z_level),
				"color": Color(0.7, 0.6, 0.9)
			})
			
			# Lock option
			if "locked" in tile_data.door:
				var lock_text = "Unlock" if tile_data.door.locked else "Lock"
				options.append({
					"name": lock_text + " Door",
					"icon": "lock",
					"callback": Callable(self, "_on_toggle_door_lock_selected").bind(tile_coords, z_level),
					"color": Color(0.9, 0.6, 0.3)
				})
		
		# Window options
		if "window" in tile_data:
			options.append({
				"name": "Knock on Window",
				"icon": "knock",
				"callback": Callable(self, "_on_knock_window_selected").bind(tile_coords, z_level),
				"color": Color(0.8, 0.8, 0.4)
			})
	
	return options

# Set menu options with styled buttons
func _set_options(options):
	option_list = options
	
	# Create button for each option
	for option in options:
		# Create a styled button
		var button = _create_styled_button(option)
		
		# Add to container
		option_container.add_child(button)
	
	# Update panel size based on content
	if options.size() > 0:
		await get_tree().process_frame
		# Calculate total height but cap at max_menu_height
		var content_height = min(option_container.get_combined_minimum_size().y, max_menu_height)
		
		# Add title height if shown
		if show_title:
			content_height += title_height + 10  # Title + separator + padding
		
		# Adjust size
		scroll_container.custom_minimum_size.y = content_height
		menu_panel.custom_minimum_size.y = content_height + 16  # Account for padding

# Create a styled button for an option
func _create_styled_button(option):
	# Use a container for better styling
	var container = PanelContainer.new()
	container.custom_minimum_size.y = option_height
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Create a style
	var button_style = StyleBoxFlat.new()
	
	# Use option color if provided, otherwise use default
	var option_color = Color(0.25, 0.25, 0.35, 0.8) 
	if "color" in option:
		option_color = Color(option.color.r, option.color.g, option.color.b, 0.2)
	
	button_style.bg_color = option_color
	button_style.corner_radius_top_left = 3
	button_style.corner_radius_top_right = 3
	button_style.corner_radius_bottom_left = 3
	button_style.corner_radius_bottom_right = 3
	
	# Set hover and pressed states
	var hover_style = button_style.duplicate()
	hover_style.bg_color = Color(option_color.r + 0.1, option_color.g + 0.1, option_color.b + 0.1, 0.6)
	
	var pressed_style = button_style.duplicate()
	pressed_style.bg_color = Color(option_color.r - 0.1, option_color.g - 0.1, option_color.b - 0.1, 0.8)
	
	container.add_theme_stylebox_override("panel", button_style)
	
	# Create a button in the container
	var button = Button.new()
	button.text = option.name
	button.flat = true
	button.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	
	# Add hover styles to container
	container.mouse_entered.connect(func(): container.add_theme_stylebox_override("panel", hover_style))
	container.mouse_exited.connect(func(): container.add_theme_stylebox_override("panel", button_style))
	button.button_down.connect(func(): container.add_theme_stylebox_override("panel", pressed_style))
	button.button_up.connect(func(): container.add_theme_stylebox_override("panel", hover_style))
	
	container.add_child(button)
	
	# Add icon if specified and enabled
	if use_icons and "icon" in option and option.icon:
		var icon_path = "res://icons/" + option.icon + ".png"
		if ResourceLoader.exists(icon_path):
			button.icon = load(icon_path)
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.add_theme_constant_override("icon_max_width", 24)
		
		# If we can't find the icon, try a TextureRect with a placeholder
		elif "color" in option:
			var icon_container = MarginContainer.new()
			icon_container.add_theme_constant_override("margin_left", 4)
			icon_container.add_theme_constant_override("margin_right", 8)
			icon_container.add_theme_constant_override("margin_top", 4)
			icon_container.add_theme_constant_override("margin_bottom", 4)
			icon_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			
			var icon_rect = ColorRect.new()
			icon_rect.custom_minimum_size = Vector2(24, 24)
			icon_rect.color = option.color
			
			icon_container.add_child(icon_rect)
			container.add_child(icon_container)
			
			# Move to the left
			container.move_child(icon_container, 0)
			
			# Add some margin to the button text
			button.add_theme_constant_override("margin_left", 32)
	
	# Connect button
	button.pressed.connect(_on_option_button_pressed.bind(option))
	
	return container

# Clear all menu options
func _clear_options():
	# Remove all children
	for child in option_container.get_children():
		child.queue_free()
	
	option_list = []

# Position the menu at screen coordinates
func _position_menu(position):
	menu_position = position
	
	# Account for screen edges
	var viewport_size = get_viewport_rect().size
	var menu_size = menu_panel.get_combined_minimum_size()
	
	# Adjust for right edge
	if position.x + menu_size.x > viewport_size.x:
		position.x = viewport_size.x - menu_size.x
	
	# Adjust for bottom edge
	if position.y + menu_size.y > viewport_size.y:
		position.y = viewport_size.y - menu_size.y
	
	# Ensure it stays on screen (min positions)
	position.x = max(position.x, 0)
	position.y = max(position.y, 0)
	
	# Set position
	menu_panel.position = position

# Close the context menu
func close_menu():
	if !menu_visible:
		return
	
	# Play close animation
	animation_player.play("close")
	
	# Hide after animation
	await animation_player.animation_finished
	menu_panel.visible = false
	menu_visible = false
	current_target = null
	
	# Signal that menu was closed
	emit_signal("menu_closed")

# Handler for option button pressed
func _on_option_button_pressed(option):
	# Call the option callback
	if "callback" in option and option.callback is Callable:
		option.callback.call()
	
	# Emit option selected signal
	emit_signal("option_selected", option)
	
	# Close the menu
	close_menu()

# Event handlers for world signals
func _on_entity_clicked(entity, mouse_button, shift_pressed, ctrl_pressed, alt_pressed):
	# Show context menu on right click
	if mouse_button == MOUSE_BUTTON_RIGHT and !shift_pressed and !ctrl_pressed and !alt_pressed:
		show_entity_menu(entity, get_viewport().get_mouse_position())

func _on_tile_clicked(tile_coords, z_level, mouse_button, shift_pressed, ctrl_pressed, alt_pressed):
	# Show context menu on right click
	if mouse_button == MOUSE_BUTTON_RIGHT and !shift_pressed and !ctrl_pressed and !alt_pressed:
		show_tile_menu(tile_coords, z_level, get_viewport().get_mouse_position())

# Option callback handlers
func _on_examine_selected(entity):
	if player and player.has_method("ShiftClickOn"):
		player.ShiftClickOn(entity)

func _on_talk_selected(entity):
	# Implement talk functionality
	if entity.has_method("talk_to"):
		entity.talk_to(player)

func _on_attack_selected(entity):
	if player and player.has_method("attack"):
		if player.has_method("get_active_item"):
			var active_item = player.get_active_item()
			player.attack(entity, active_item)
		else:
			player.attack(entity, null)  # Unarmed

func _on_pickup_selected(entity):
	if player and player.has_method("try_pick_up_item"):
		player.try_pick_up_item(entity)

func _on_use_selected(entity):
	if player and player.has_method("interact_with_entity"):
		player.interact_with_entity(entity)

func _on_toggle_door_selected(entity):
	if entity.has_method("toggle"):
		entity.toggle(player)

func _on_examine_tile_selected(tile_coords, z_level):
	if player and player.has_method("examine_tile"):
		player.examine_tile(tile_coords, z_level)
	elif player and player.has_method("ShiftClickOn"):
		# Fallback - create a dummy target
		var target = {"tile": tile_coords, "z_level": z_level}
		player.ShiftClickOn(target)

func _on_move_to_tile_selected(tile_coords, z_level):
	if player and player.has_method("move_to_tile"):
		player.move_to_tile(tile_coords, z_level)
	elif player and player.has_method("_on_tile_clicked"):
		# Fallback - simulate a left click
		player._on_tile_clicked(tile_coords, MOUSE_BUTTON_LEFT, false, false, false)

func _on_toggle_tile_door_selected(tile_coords, z_level):
	if world and world.has_method("toggle_door"):
		world.toggle_door(tile_coords, z_level)

func _on_toggle_door_lock_selected(tile_coords, z_level):
	if world and world.has_method("toggle_door_lock"):
		world.toggle_door_lock(tile_coords, z_level)

func _on_knock_window_selected(tile_coords, z_level):
	if world and world.has_method("knock_window"):
		world.knock_window(tile_coords, z_level)

# Public API
func set_player(player_ref):
	player = player_ref

func set_world(world_ref):
	world = world_ref

func set_click_system(click_system_ref):
	if click_system:
		# Disconnect old signals
		if click_system.has_signal("entity_clicked") and click_system.is_connected("entity_clicked", Callable(self, "_on_entity_clicked")):
			click_system.disconnect("entity_clicked", Callable(self, "_on_entity_clicked"))
		
		if click_system.has_signal("tile_clicked") and click_system.is_connected("tile_clicked", Callable(self, "_on_tile_clicked")):
			click_system.disconnect("tile_clicked", Callable(self, "_on_tile_clicked"))
	
	# Set new click system
	click_system = click_system_ref
	
	# Connect to new signals
	if click_system:
		if click_system.has_signal("entity_clicked") and !click_system.is_connected("entity_clicked", Callable(self, "_on_entity_clicked")):
			click_system.connect("entity_clicked", Callable(self, "_on_entity_clicked"))
		
		if click_system.has_signal("tile_clicked") and !click_system.is_connected("tile_clicked", Callable(self, "_on_tile_clicked")):
			click_system.connect("tile_clicked", Callable(self, "_on_tile_clicked"))

# Show a context menu with custom options
func show_context_menu(options, position, title="Options"):
	# Clear previous options
	_clear_options()
	
	# Set title if showing
	if show_title and title_label:
		title_label.text = title
	
	# Set options and position
	_set_options(options)
	_position_menu(position)
	
	# Show menu
	menu_panel.scale = Vector2(1.0, 0.0)
	menu_panel.modulate = Color(1, 1, 1, 0)
	menu_panel.visible = true
	menu_visible = true
	animation_player.play("open")
