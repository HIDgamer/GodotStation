extends Control
class_name AdminSpawner

signal item_spawned(item_path: String, position: Vector2)
signal spawner_closed

# Core references
var world_node = null
var game_manager = null

# UI nodes
@onready var main_panel = $MainPanel
@onready var close_button = $MainPanel/VBox/Header/TitleBar/CloseButton
@onready var status_label = $MainPanel/VBox/Header/StatusLabel
@onready var search_edit = $MainPanel/VBox/Controls/SearchBar/SearchEdit
@onready var category_option = $MainPanel/VBox/Controls/FilterBar/CategoryOption
@onready var items_list = $MainPanel/VBox/ItemsContainer/ItemsScroll/ItemsList
@onready var selected_info = $MainPanel/VBox/Footer/SelectedInfo
@onready var spawn_mode_button = $MainPanel/VBox/Footer/ButtonsContainer/SpawnModeButton
@onready var quick_spawn_button = $MainPanel/VBox/Footer/ButtonsContainer/QuickSpawnButton

# State
var spawnable_items: Dictionary = {}
var filtered_items: Array = []
var selected_item = null
var spawn_mode: bool = false
var categories: Array = ["All"]

# Drag and resize
var is_dragging: bool = false
var is_resizing: bool = false
var drag_offset: Vector2
var resize_edge: String = ""
var resize_threshold: float = 10.0
var min_size: Vector2 = Vector2(400, 300)
var max_size: Vector2 = Vector2(1200, 800)
var resize_start_pos: Vector2
var resize_start_size: Vector2
var resize_start_panel_pos: Vector2

# Configuration
var configured_directories = [
	"res://Scenes/Characters/",
	"res://Scenes/Items/Bullets_Magazines/",
	"res://Scenes/Items/Grenades/",
	"res://Scenes/Items/Guns/",
	"res://Scenes/Items/Medical/",
	"res://Scenes/Items/Melee/",
	"res://Scenes/Objects/Machinery/"
]

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Setup drag/resize for main panel
	main_panel.gui_input.connect(_on_panel_gui_input)
	
	# Setup systems
	find_world_systems()
	setup_ui()
	load_all_items()
	
	# Start hidden
	hide()

func find_world_systems():
	"""Find references to world systems"""
	print("AdminSpawner: Searching for world systems...")
	
	# Try multiple approaches to find world
	var search_methods = [
		func(): return get_tree().current_scene,
		func(): return get_node_or_null("/root/World"),
		func(): return get_node_or_null("../World"),
		func(): return get_node_or_null("../../World"),
		func(): return get_parent().get_node_or_null("World"),
		func(): return get_parent().get_parent().get_node_or_null("World")
	]
	
	for method in search_methods:
		var candidate = method.call()
		if candidate and (candidate.name == "World" or candidate.has_method("add_child")):
			world_node = candidate
			print("AdminSpawner: Found world node: ", world_node.name, " at path: ", world_node.get_path())
			break
	
	# Also search by group
	if not world_node:
		var world_groups = ["world", "main_world", "game_world"]
		for group_name in world_groups:
			var nodes = get_tree().get_nodes_in_group(group_name)
			if nodes.size() > 0:
				world_node = nodes[0]
				print("AdminSpawner: Found world node via group '", group_name, "': ", world_node.name)
				break
	
	# Find GameManager
	game_manager = get_node_or_null("/root/GameManager")
	if not game_manager:
		var managers = get_tree().get_nodes_in_group("game_manager")
		if managers.size() > 0:
			game_manager = managers[0]
	
	print("AdminSpawner: World found: ", world_node != null)
	print("AdminSpawner: GameManager found: ", game_manager != null)
	
	if world_node:
		print("AdminSpawner: World path: ", world_node.get_path())
	if game_manager:
		print("AdminSpawner: GameManager path: ", game_manager.get_path())

func setup_ui():
	"""Initialize UI elements"""
	# Setup categories
	category_option.clear()
	for category in categories:
		category_option.add_item(category)
	
	# Connect signals
	close_button.pressed.connect(_on_close_pressed)
	search_edit.text_changed.connect(_on_search_changed)
	category_option.item_selected.connect(_on_category_changed)
	spawn_mode_button.pressed.connect(_on_spawn_mode_pressed)
	quick_spawn_button.pressed.connect(_on_quick_spawn_pressed)
	
	update_ui_state()

func load_all_items():
	"""Load items from all configured directories"""
	print("AdminSpawner: Loading items from configured directories...")
	
	var total_items = 0
	for dir_path in configured_directories:
		print("AdminSpawner: Checking directory: ", dir_path)
		if DirAccess.dir_exists_absolute(dir_path):
			var items_before = spawnable_items.size()
			scan_directory(dir_path)
			var items_added = spawnable_items.size() - items_before
			print("AdminSpawner: Added ", items_added, " items from ", dir_path)
			total_items += items_added
		else:
			print("AdminSpawner: Directory not found: ", dir_path)
	
	refresh_categories()
	filter_and_display_items()
	print("AdminSpawner: Total items loaded: ", total_items)
	print("AdminSpawner: Categories: ", categories)

func scan_directory(dir_path: String):
	"""Recursively scan directory for .tscn files"""
	var dir = DirAccess.open(dir_path)
	if not dir:
		return
	
	_scan_recursive(dir, dir_path, get_category_from_path(dir_path))

func _scan_recursive(dir: DirAccess, current_path: String, category: String):
	"""Recursive directory scanning"""
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if dir.current_is_dir() and not file_name.begins_with("."):
			# Scan subdirectory
			var subdir = DirAccess.open(current_path + "/" + file_name)
			if subdir:
				_scan_recursive(subdir, current_path + "/" + file_name, category)
		elif file_name.ends_with(".tscn"):
			# Add scene file
			add_item_from_file(current_path + "/" + file_name, category)
		
		file_name = dir.get_next()

func get_category_from_path(path: String) -> String:
	"""Extract category name from directory path"""
	var segments = path.split("/")
	if segments.size() > 0:
		var last_segment = segments[-1]
		if last_segment != "":
			return last_segment.capitalize()
	return "Custom"

func add_item_from_file(file_path: String, category: String):
	"""Add an item from a scene file"""
	if not ResourceLoader.exists(file_path):
		print("AdminSpawner: Scene not found: ", file_path)
		return
	
	# Try to load the scene to validate it
	var scene_resource = load(file_path)
	if not scene_resource:
		print("AdminSpawner: Failed to load scene: ", file_path)
		return
	
	var scene_name = file_path.get_file().get_basename()
	
	# Skip if already exists
	if scene_name in spawnable_items:
		print("AdminSpawner: Item already exists: ", scene_name)
		return
	
	# Auto-detect better category if needed
	if category == "Custom":
		category = detect_category_from_name(scene_name, file_path)
	
	var item_data = {
		"name": scene_name,
		"display_name": format_display_name(scene_name),
		"scene_path": file_path,
		"category": category
	}
	
	spawnable_items[scene_name] = item_data
	print("AdminSpawner: Added item: ", scene_name, " (", category, ")")

func detect_category_from_name(name: String, path: String) -> String:
	"""Auto-detect category from item name and path"""
	var name_lower = name.to_lower()
	var path_lower = path.to_lower()
	
	var keywords = {
		"Characters": ["human", "character", "mob", "npc", "person"],
		"Medical": ["medkit", "bandage", "syringe", "pill", "medical"],
		"Weapons": ["gun", "rifle", "pistol", "weapon", "knife", "sword"],
		"Tools": ["wrench", "screwdriver", "crowbar", "tool"],
		"Machines": ["vendor", "machine", "computer", "console"],
		"Structures": ["wall", "door", "window", "structure"]
	}
	
	for category in keywords:
		for keyword in keywords[category]:
			if keyword in name_lower or keyword in path_lower:
				return category
	
	return "Items"

func format_display_name(name: String) -> String:
	"""Format scene name for display"""
	# Replace underscores with spaces and capitalize
	return name.replace("_", " ").capitalize()

func refresh_categories():
	"""Update category list"""
	var new_categories = ["All"]
	for item in spawnable_items.values():
		if item.category not in new_categories:
			new_categories.append(item.category)
	
	categories = new_categories
	
	# Update UI
	var selected = category_option.selected if category_option.selected >= 0 else 0
	category_option.clear()
	for category in categories:
		category_option.add_item(category)
	
	if selected < categories.size():
		category_option.selected = selected

func filter_and_display_items():
	"""Filter items and update display"""
	filtered_items.clear()
	
	var search_text = search_edit.text.to_lower()
	var selected_category = categories[category_option.selected] if category_option.selected >= 0 else "All"
	
	for item in spawnable_items.values():
		# Category filter
		if selected_category != "All" and item.category != selected_category:
			continue
		
		# Search filter
		if search_text != "" and not item.display_name.to_lower().contains(search_text):
			continue
		
		filtered_items.append(item)
	
	# Sort alphabetically
	filtered_items.sort_custom(func(a, b): return a.display_name < b.display_name)
	
	update_items_display()

func update_items_display():
	"""Update the items list display"""
	# Clear existing items
	for child in items_list.get_children():
		child.queue_free()
	
	await get_tree().process_frame
	
	# Add filtered items
	for item in filtered_items:
		var item_button = create_item_button(item)
		items_list.add_child(item_button)

func create_item_button(item: Dictionary) -> Button:
	"""Create a button for an item"""
	var button = Button.new()
	button.text = item.display_name
	button.tooltip_text = "Path: " + item.scene_path + "\nCategory: " + item.category
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 32
	
	# Connect selection
	button.pressed.connect(_on_item_selected.bind(item))
	
	return button

func update_ui_state():
	"""Update UI elements based on current state"""
	# Update selected info
	if selected_item:
		selected_info.text = "Selected: " + selected_item.display_name
	else:
		selected_info.text = "No item selected"
	
	# Update status label for spawn mode
	if status_label:
		if spawn_mode:
			status_label.text = "🎯 SPAWN MODE ACTIVE - Click outside panel to spawn, ESC to cancel"
		else:
			status_label.text = ""
	
	# Update buttons
	var has_selection = selected_item != null
	spawn_mode_button.disabled = not has_selection
	quick_spawn_button.disabled = not has_selection
	
	# Update spawn mode button text
	if spawn_mode:
		spawn_mode_button.text = "🚫 Cancel Spawn Mode"
		spawn_mode_button.modulate = Color(1.0, 0.7, 0.7)
	else:
		spawn_mode_button.text = "🎯 Enter Spawn Mode"
		spawn_mode_button.modulate = Color.WHITE
	
	# Update selected button appearance
	update_button_selection()

func update_button_selection():
	"""Update visual selection of item buttons"""
	for child in items_list.get_children():
		if child is Button:
			if selected_item and child.text == selected_item.display_name:
				child.modulate = Color(0.8, 1.0, 0.8)
			else:
				child.modulate = Color.WHITE

func _input(event):
	if not visible:
		return
	
	# Handle escape key
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if spawn_mode:
			cancel_spawn_mode()
		else:
			close_spawner()
		get_viewport().set_input_as_handled()
	
	# Handle spawn mode clicking (only if not dragging/resizing)
	if spawn_mode and event is InputEventMouseButton and not is_dragging and not is_resizing:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Check if click is outside the panel
			var panel_rect = Rect2(main_panel.global_position, main_panel.size)
			if not panel_rect.has_point(event.global_position):
				handle_spawn_click(event.global_position)
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancel_spawn_mode()
			get_viewport().set_input_as_handled()

func handle_spawn_click(global_pos: Vector2):
	"""Handle spawn mode clicking"""
	if not selected_item:
		print("AdminSpawner: No item selected for spawning")
		cancel_spawn_mode()
		return
	
	print("AdminSpawner: Attempting to spawn ", selected_item.display_name)
	
	# Convert to world position
	var camera = get_viewport().get_camera_2d()
	var world_pos = global_pos
	if camera:
		world_pos = camera.get_global_mouse_position()
		print("AdminSpawner: Converted to world position: ", world_pos)
	else:
		print("AdminSpawner: No camera found, using raw position: ", world_pos)
	
	# Try spawning
	var success = false
	
	# Check if it's a human/character
	if is_character_item(selected_item):
		print("AdminSpawner: Detected character item, trying character spawn")
		success = await spawn_as_character(world_pos)
	
	if not success:
		print("AdminSpawner: Trying object spawn")
		success = spawn_as_object(world_pos)
	
	if success:
		# Emit signal
		emit_signal("item_spawned", selected_item.scene_path, world_pos)
		print("AdminSpawner: Successfully spawned item")
		cancel_spawn_mode()
	else:
		print("AdminSpawner: Failed to spawn item")

func is_character_item(item: Dictionary) -> bool:
	"""Check if item is a character/human"""
	var indicators = ["human", "character", "mob", "npc", "person"]
	var name_lower = item.name.to_lower()
	var category_lower = item.category.to_lower()
	var path_lower = item.scene_path.to_lower()
	
	for indicator in indicators:
		if indicator in name_lower or indicator in category_lower or indicator in path_lower:
			return true
	
	return false

func spawn_as_character(world_pos: Vector2) -> bool:
	"""Spawn item as character using GameManager"""
	if not game_manager:
		print("AdminSpawner: No GameManager found for character spawning")
		return false
	
	var tile_pos = world_pos_to_tile(world_pos)
	var z_level = get_current_z_level()
	
	print("AdminSpawner: Spawning character at tile: ", tile_pos, " z_level: ", z_level)
	
	# Try to use GameManager spawn method
	if game_manager.has_method("spawn_npc_at_tile"):
		var npc_name = selected_item.name + "_" + str(Time.get_ticks_msec())
		var result = await game_manager.spawn_npc_at_tile(tile_pos, z_level, npc_name)
		return result != null
	else:
		print("AdminSpawner: GameManager has no spawn_npc_at_tile method")
		return false

func spawn_as_object(world_pos: Vector2) -> bool:
	"""Spawn item as regular object"""
	print("AdminSpawner: Loading scene: ", selected_item.scene_path)
	
	# Verify scene exists
	if not ResourceLoader.exists(selected_item.scene_path):
		print("AdminSpawner: Scene file does not exist: ", selected_item.scene_path)
		return false
	
	# Load scene
	var scene = load(selected_item.scene_path)
	if not scene:
		print("AdminSpawner: Failed to load scene: ", selected_item.scene_path)
		return false
	
	print("AdminSpawner: Scene loaded successfully")
	
	# Instantiate
	var instance = scene.instantiate()
	if not instance:
		print("AdminSpawner: Failed to instantiate scene")
		return false
	
	print("AdminSpawner: Scene instantiated")
	
	# Set position
	if instance.has_method("set_global_position"):
		instance.set_global_position(world_pos)
	elif "global_position" in instance:
		instance.global_position = world_pos
	elif "position" in instance:
		instance.position = world_pos
	
	print("AdminSpawner: Position set to: ", world_pos)
	
	# Find a suitable parent
	var parent_node = find_spawn_parent()
	if parent_node:
		parent_node.add_child(instance)
		print("AdminSpawner: Added to parent: ", parent_node.name, " at path: ", parent_node.get_path())
		return true
	else:
		print("AdminSpawner: No suitable parent found")
		instance.queue_free()
		return false

func find_spawn_parent() -> Node:
	"""Find suitable parent for spawning objects"""
	# Try in order of preference
	var candidates = []
	
	# Add world node if found
	if world_node:
		candidates.append(world_node)
	
	# Add current scene
	candidates.append(get_tree().current_scene)
	
	# Add root
	candidates.append(get_tree().root)
	
	# Try each candidate
	for candidate in candidates:
		if candidate and candidate.has_method("add_child"):
			print("AdminSpawner: Using spawn parent: ", candidate.name, " at ", candidate.get_path())
			return candidate
	
	print("AdminSpawner: No suitable spawn parent found")
	return null

func world_pos_to_tile(world_pos: Vector2) -> Vector2i:
	"""Convert world position to tile coordinates"""
	var tile_size = 32  # Standard tile size
	return Vector2i(int(world_pos.x / tile_size), int(world_pos.y / tile_size))

func get_current_z_level() -> int:
	"""Get current Z level"""
	if world_node and "current_z_level" in world_node:
		return world_node.current_z_level
	return 0

# Signal handlers
func _on_close_pressed():
	close_spawner()

func _on_search_changed(new_text: String):
	filter_and_display_items()

func _on_category_changed(index: int):
	filter_and_display_items()

func _on_item_selected(item: Dictionary):
	selected_item = item
	print("AdminSpawner: Selected ", item.display_name)
	update_ui_state()

func _on_spawn_mode_pressed():
	if spawn_mode:
		cancel_spawn_mode()
	else:
		enter_spawn_mode()

func _on_quick_spawn_pressed():
	if not selected_item:
		return
	
	print("AdminSpawner: Quick spawning ", selected_item.display_name)
	
	# Spawn at center of screen
	var viewport_size = get_viewport().get_visible_rect().size
	var center_pos = viewport_size / 2
	
	var camera = get_viewport().get_camera_2d()
	if camera:
		center_pos = camera.get_screen_center_position()
	
	# Try spawning
	var success = false
	
	if is_character_item(selected_item):
		success = await spawn_as_character(center_pos)
	
	if not success:
		success = spawn_as_object(center_pos)
	
	if success:
		emit_signal("item_spawned", selected_item.scene_path, center_pos)
		print("AdminSpawner: Quick spawn successful")
	else:
		print("AdminSpawner: Quick spawn failed")

# Drag and resize functionality
func _on_panel_gui_input(event):
	"""Handle panel dragging and resizing"""
	if event is InputEventMouseMotion:
		if not is_dragging and not is_resizing:
			# Update cursor for resize edges
			var edge = get_resize_edge(event.global_position)
			update_cursor(edge)
		
		if is_resizing:
			handle_resize(event)
		elif is_dragging:
			handle_drag(event)
	
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var edge = get_resize_edge(event.global_position)
				if edge != "":
					start_resize(event, edge)
				else:
					start_drag(event)
			else:
				stop_drag_resize()

func get_resize_edge(mouse_pos: Vector2) -> String:
	"""Determine which edge is being hovered for resizing"""
	var panel_rect = main_panel.get_rect()
	var panel_pos = main_panel.global_position
	var panel_size = main_panel.size
	
	var left = abs(mouse_pos.x - panel_pos.x) < resize_threshold
	var right = abs(mouse_pos.x - (panel_pos.x + panel_size.x)) < resize_threshold
	var top = abs(mouse_pos.y - panel_pos.y) < resize_threshold
	var bottom = abs(mouse_pos.y - (panel_pos.y + panel_size.y)) < resize_threshold
	
	# Check corners first
	if top and left: return "top_left"
	if top and right: return "top_right" 
	if bottom and left: return "bottom_left"
	if bottom and right: return "bottom_right"
	
	# Check edges
	if left: return "left"
	if right: return "right"
	if top: return "top"
	if bottom: return "bottom"
	
	return ""

func update_cursor(edge: String):
	"""Update cursor based on resize edge"""
	match edge:
		"left", "right":
			mouse_default_cursor_shape = Control.CURSOR_HSIZE
		"top", "bottom":
			mouse_default_cursor_shape = Control.CURSOR_VSIZE
		"top_left", "bottom_right":
			mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
		"top_right", "bottom_left":
			mouse_default_cursor_shape = Control.CURSOR_BDIAGSIZE
		_:
			mouse_default_cursor_shape = Control.CURSOR_ARROW

func start_drag(event):
	"""Start dragging the panel"""
	is_dragging = true
	drag_offset = main_panel.global_position - event.global_position

func start_resize(event, edge):
	"""Start resizing the panel"""
	is_resizing = true
	resize_edge = edge
	resize_start_pos = event.global_position
	resize_start_size = main_panel.size

func handle_drag(event):
	"""Handle panel dragging"""
	var new_pos = event.global_position + drag_offset
	
	# Keep panel within viewport bounds
	var viewport = get_viewport()
	if viewport:
		var viewport_size = viewport.get_visible_rect().size
		var panel_size = main_panel.size
		
		new_pos.x = clamp(new_pos.x, 0, viewport_size.x - panel_size.x)
		new_pos.y = clamp(new_pos.y, 0, viewport_size.y - panel_size.y)
	
	main_panel.position = new_pos

func handle_resize(event):
	"""Handle panel resizing"""
	var delta = event.global_position - resize_start_pos
	var old_size = main_panel.size
	var old_pos = main_panel.position
	var new_size = resize_start_size
	var new_pos = old_pos
	
	# Calculate new size based on resize edge
	match resize_edge:
		"left":
			new_size.x = resize_start_size.x - delta.x
		"right":
			new_size.x = resize_start_size.x + delta.x
		"top":
			new_size.y = resize_start_size.y - delta.y
		"bottom":
			new_size.y = resize_start_size.y + delta.y
		"top_left":
			new_size.x = resize_start_size.x - delta.x
			new_size.y = resize_start_size.y - delta.y
		"top_right":
			new_size.x = resize_start_size.x + delta.x
			new_size.y = resize_start_size.y - delta.y
		"bottom_left":
			new_size.x = resize_start_size.x - delta.x
			new_size.y = resize_start_size.y + delta.y
		"bottom_right":
			new_size.x = resize_start_size.x + delta.x
			new_size.y = resize_start_size.y + delta.y
	
	# Apply size constraints
	new_size.x = clamp(new_size.x, min_size.x, max_size.x)
	new_size.y = clamp(new_size.y, min_size.y, max_size.y)
	
	# Calculate position adjustment for left/top edges
	# When resizing from left/top, position needs to move by the difference in size
	var size_diff = new_size - old_size
	
	match resize_edge:
		"left", "top_left", "bottom_left":
			new_pos.x = old_pos.x - size_diff.x
		"top", "top_left", "top_right":
			new_pos.y = old_pos.y - size_diff.y
	
	# Keep panel within viewport bounds
	var viewport = get_viewport()
	if viewport:
		var viewport_size = viewport.get_visible_rect().size
		new_pos.x = clamp(new_pos.x, 0, viewport_size.x - new_size.x)
		new_pos.y = clamp(new_pos.y, 0, viewport_size.y - new_size.y)
	
	# Apply new size and position
	main_panel.size = new_size
	main_panel.position = new_pos

func stop_drag_resize():
	"""Stop dragging/resizing"""
	is_dragging = false
	is_resizing = false
	resize_edge = ""
	mouse_default_cursor_shape = Control.CURSOR_ARROW

# Public methods
func show_spawner():
	"""Show the spawner UI"""
	show()

func close_spawner():
	"""Close the spawner UI"""
	if spawn_mode:
		cancel_spawn_mode()
	hide()
	emit_signal("spawner_closed")

func enter_spawn_mode():
	"""Enter spawn mode"""
	if not selected_item:
		return
	
	spawn_mode = true
	print("AdminSpawner: Entered spawn mode for ", selected_item.display_name)
	update_ui_state()

func cancel_spawn_mode():
	"""Cancel spawn mode"""
	spawn_mode = false
	print("AdminSpawner: Cancelled spawn mode")
	update_ui_state()

func reload_items():
	"""Reload all items"""
	spawnable_items.clear()
	categories = ["All"]
	load_all_items()
