extends Control

# Subsystem references
var settings_manager = null
var zone_manager = null
var lighting_system = null
var preview_mode = null
var ui_enhancer = null
var object_placer = null
var map_validator = null
var tile_editor_ui = null
var tile_placement_system = null
var tileset_manager = null

# Map data
var current_map_name = "New Map"
var current_map_path = ""
var map_width = 100
var map_height = 100
var z_levels = 3
var current_z_level = 0

# Grid size
var CELL_SIZE = 32

# Editor state
var current_tool = "place"
var current_layer = 0  # 0 = floor, 1 = wall, 2 = objects, 3 = wire, 4 = zone
var current_tile_id = -1
var current_tile_type = ""
var current_tile_coords = Vector2i(0, 0)
var is_placing = false
var is_erasing = false
var is_selecting = false
var selection_start = Vector2i(0, 0)
var selection_end = Vector2i(0, 0)
var selection_active = false
var mouse_grid_position = Vector2i(0, 0)
var mouse_world_position = Vector2(0, 0)

# Tilemaps
@onready var floor_tilemap = $UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport/FloorTileMap
@onready var wall_tilemap = $UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport/WallTileMap
@onready var objects_tilemap = $UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport/ObjectsTileMap
@onready var zone_tilemap = $UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport/ZoneTileMap

# UI references
@onready var camera = $UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport/EditorCamera
@onready var grid = $UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport/Grid
@onready var status_info = $UI/MainPanel/VBoxContainer/StatusBar/HBoxContainer/StatusInfo
@onready var z_level_info = $UI/MainPanel/VBoxContainer/StatusBar/HBoxContainer/ZLevelInfo

# Signals
signal active_layer_changed(layer_id)
signal tool_changed(tool_name)
signal z_level_changed(z_level)
signal selection_changed(start, end)
signal preview_started
signal preview_ended

func _ready():
	# Initialize subsystems
	_initialize_subsystems()
	
	# Initialize UI
	_setup_ui()
	
	# Connect input events
	set_process_input(true)
	
	# Set initial active layer
	set_active_layer(0)
	
	# Initialize tile import system
	_initialize_tile_import_system()
	
	# Start autosave timer if enabled
	if settings_manager.get_setting("editor/autosave_enabled", true):
		$AutosaveTimer.wait_time = settings_manager.get_setting("editor/autosave_interval", 300)
		$AutosaveTimer.start()

func _initialize_subsystems():
	# Initialize settings manager
	if has_node("SettingsManager"):
		settings_manager = $SettingsManager
		settings_manager.load_settings()
	else:
		push_error("SettingsManager node not found!")
		return
	
	# Initialize tileset manager
	if has_node("EnhancedTilesetManager"):
		tileset_manager = $EnhancedTilesetManager
	else:
		push_error("EnhancedTilesetManager node not found!")
		return
	
	# Initialize tile placement system
	if has_node("TilePlacementSystem"):
		tile_placement_system = $TilePlacementSystem
		tile_placement_system.editor_ref = self
		tile_placement_system.tileset_manager = tileset_manager
		tile_placement_system.initialize_tilemaps()
	else:
		push_error("TilePlacementSystem node not found!")
		return
	
	# Initialize tile editor UI
	if has_node("TileEditorUI"):
		tile_editor_ui = $TileEditorUI
		tile_editor_ui.editor_ref = self
		tile_editor_ui.tileset_manager = tileset_manager
		tile_editor_ui.tile_placement_system = tile_placement_system
		
		# Set up tile editor UI
		var side_panel = get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/SidePanel/ToolTabs/TilesTab")
		if side_panel:
			tile_editor_ui.setup(side_panel)
		else:
			push_error("Tile tab panel not found!")
	else:
		push_error("TileEditorUI node not found!")
		return
	
	# Initialize object placer
	if has_node("AdvancedObjectPlacer"):
		object_placer = $AdvancedObjectPlacer
		
		var object_container = get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport/PlacedObjects")
		var preview_container = get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport/PreviewContainer")
		return
	
	# Initialize zone manager
	if has_node("ZoneManager") and zone_tilemap:
		zone_manager = $ZoneManager
		zone_manager.editor_ref = self
		zone_manager.zone_tilemap = zone_tilemap
	else:
		push_error("ZoneManager node or zone_tilemap not found!")
		return
	
	# Initialize lighting system
	if has_node("LightingSystem"):
		lighting_system = $LightingSystem
		lighting_system.editor_ref = self
		
		var light_container = get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport/LightSources")
		var darkness_layer = get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport/DarknessLayer")
		
		if light_container and darkness_layer:
			lighting_system.light_container = light_container
			lighting_system.darkness_layer = darkness_layer
		else:
			push_error("Lighting containers not found!")
	else:
		push_error("LightingSystem node not found!")
		return
	
	# Initialize preview mode
	if has_node("PreviewMode"):
		preview_mode = $PreviewMode
		preview_mode.editor_ref = self
	else:
		push_error("PreviewMode node not found!")
		return
	
	# Initialize map validator
	if has_node("MapValidator"):
		map_validator = $MapValidator
		map_validator.editor_ref = self
	else:
		push_error("MapValidator node not found!")
		return
	
	# Initialize UI enhancer (should be last so it can connect to all other subsystems)
	if has_node("EditorUIEnhancer"):
		ui_enhancer = $EditorUIEnhancer
		ui_enhancer.editor_ref = self
		ui_enhancer.settings_manager = settings_manager
		ui_enhancer.zone_manager = zone_manager
		ui_enhancer.lighting_system = lighting_system
		ui_enhancer.preview_mode = preview_mode
		ui_enhancer.setup()
	else:
		push_error("EditorUIEnhancer node not found!")
		return
	
	# Set map dimensions
	map_width = settings_manager.get_setting("map/default_width", 100)
	map_height = settings_manager.get_setting("map/default_height", 100)
	z_levels = settings_manager.get_setting("map/default_z_levels", 3)
	
	# Apply settings
	_apply_settings()

func _initialize_tile_import_system():
	var import_system = $TileImportSystem
	var import_ui = $TileImportUI
	
	if import_system and import_ui:
		import_system.initialize(self, tileset_manager)
		import_ui.initialize(self, import_system, get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/SidePanel/ToolTabs/TilesTab/TilePalette"))
		
		# Connect signals
		import_system.connect("tile_library_updated", Callable(self, "_on_tile_library_updated"))
		
		# Set reference in the tile palette
		var tile_palette = get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/SidePanel/ToolTabs/TilesTab/TilePalette")
		if tile_palette:
			tile_palette.import_system = import_system

func _on_tile_library_updated():
	# Refresh tile palette
	var tile_palette = get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/SidePanel/ToolTabs/TilesTab/TilePalette")
	if tile_palette and tile_palette.has_method("refresh"):
		tile_palette.refresh()

func _setup_ui():
	# Connect toolbar buttons for tools
	_connect_toolbar_buttons()
	
	# Connect menu items
	_connect_menu_items()
	
	# Connect tab changers
	_connect_tabs()
	
	# Connect tile palette to tile editor UI
	var tile_palette = get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/SidePanel/ToolTabs/TilesTab/TilePalette")
	if tile_palette and tile_editor_ui:
		tile_editor_ui.connect("tile_selected", Callable(self, "_on_tile_selected"))
	
	# Connect object list
	var object_list = get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/SidePanel/ToolTabs/ObjectsTab/ObjectsList")
	if object_list:
		object_list.connect("object_selected", Callable(self, "_on_object_selected"))
	
	# Update status bar
	_update_status_bar()

func _connect_toolbar_buttons():
	# Tool buttons
	var place_button = get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/HBoxContainer/ToolsSection/PlaceButton")
	if place_button:
		place_button.pressed.connect(Callable(self, "_on_place_tool_selected"))
	
	var erase_button = get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/HBoxContainer/ToolsSection/EraseButton")
	if erase_button:
		erase_button.pressed.connect(Callable(self, "_on_erase_tool_selected"))
	
	var select_button = get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/HBoxContainer/ToolsSection/SelectButton")
	if select_button:
		select_button.pressed.connect(Callable(self, "_on_select_tool_selected"))
	
	var fill_button = get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/HBoxContainer/ToolsSection/FillButton")
	if fill_button:
		fill_button.pressed.connect(Callable(self, "_on_fill_tool_selected"))
	
	var line_button = get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/HBoxContainer/ToolsSection/LineButton")
	if line_button:
		line_button.pressed.connect(Callable(self, "_on_line_tool_selected"))
	
	# Layer buttons
	var floor_button = get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/HBoxContainer/LayersSection/FloorButton")
	if floor_button:
		floor_button.pressed.connect(Callable(self, "_on_floor_layer_selected"))
	
	var wall_button = get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/HBoxContainer/LayersSection/WallButton")
	if wall_button:
		wall_button.pressed.connect(Callable(self, "_on_wall_layer_selected"))
	
	var objects_button = get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/HBoxContainer/LayersSection/ObjectsButton")
	if objects_button:
		objects_button.pressed.connect(Callable(self, "_on_objects_layer_selected"))
	
	var zone_button = get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/HBoxContainer/LayersSection/ZoneButton")
	if zone_button:
		zone_button.pressed.connect(Callable(self, "_on_zone_layer_selected"))
	
	# Object buttons
	var object_place_button = get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/HBoxContainer/ObjectToolsSection/ObjectPlaceButton")
	if object_place_button:
		object_place_button.pressed.connect(Callable(self, "_on_object_place_selected"))
	
	var object_erase_button = get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/HBoxContainer/ObjectToolsSection/ObjectEraseButton")
	if object_erase_button:
		object_erase_button.pressed.connect(Callable(self, "_on_object_erase_selected"))
	
	var object_select_button = get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/HBoxContainer/ObjectToolsSection/ObjectSelectButton")
	if object_select_button:
		object_select_button.pressed.connect(Callable(self, "_on_object_select_selected"))
	
	var object_rotate_button = get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/HBoxContainer/ObjectToolsSection/ObjectRotateButton")
	if object_rotate_button:
		object_rotate_button.pressed.connect(Callable(self, "_on_object_rotate_selected"))

func _connect_menu_items():
	# File menu
	var file_menu = get_node_or_null("UI/MainPanel/VBoxContainer/TopMenu/FileMenu")
	if file_menu:
		file_menu.get_popup().id_pressed.connect(Callable(self, "_on_file_menu_item_selected"))
	
	# Edit menu
	var edit_menu = get_node_or_null("UI/MainPanel/VBoxContainer/TopMenu/EditMenu")
	if edit_menu:
		edit_menu.get_popup().id_pressed.connect(Callable(self, "_on_edit_menu_item_selected"))
	
	# View menu
	var view_menu = get_node_or_null("UI/MainPanel/VBoxContainer/TopMenu/ViewMenu")
	if view_menu:
		view_menu.get_popup().id_pressed.connect(Callable(self, "_on_view_menu_item_selected"))
	
	# Tools menu
	var tools_menu = get_node_or_null("UI/MainPanel/VBoxContainer/TopMenu/ToolsMenu")
	if tools_menu:
		tools_menu.get_popup().id_pressed.connect(Callable(self, "_on_tools_menu_item_selected"))
	
	# Settings menu
	var settings_menu = get_node_or_null("UI/MainPanel/VBoxContainer/TopMenu/SettingsMenu")
	if settings_menu:
		settings_menu.get_popup().id_pressed.connect(Callable(self, "_on_settings_menu_item_selected"))

func _connect_tabs():
	var tool_tabs = get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/SidePanel/ToolTabs")
	if tool_tabs:
		tool_tabs.tab_changed.connect(Callable(self, "_on_tool_tab_changed"))

func _apply_settings():
	# Apply grid settings
	if grid:
		grid.toggle_grid_visibility(settings_manager.get_setting("display/show_grid", true))
		grid.grid_color = settings_manager.get_setting("display/grid_color", Color(0.5, 0.5, 0.5, 0.2))
		grid.major_grid_color = settings_manager.get_setting("display/grid_major_color", Color(0.5, 0.5, 0.5, 0.4))
		grid.show_major_lines = settings_manager.get_setting("display/grid_major_lines", true)
		grid.major_grid_interval = settings_manager.get_setting("display/grid_major_interval", 5)
		grid.show_cursor = settings_manager.get_setting("display/show_coordinates", true)
	
	# Apply UI settings
	var sidebar_width = settings_manager.get_setting("ui/sidebar_width", 250)
	var split_container = get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer")
	if split_container:
		split_container.split_offset = sidebar_width
	
	var show_status_bar = settings_manager.get_setting("ui/show_status_bar", true)
	var status_bar = get_node_or_null("UI/MainPanel/VBoxContainer/StatusBar")
	if status_bar:
		status_bar.visible = show_status_bar
	
	# Apply layer transparency
	var transparency = settings_manager.get_setting("editor/layer_transparency", 0.3)
	_update_layer_visibility(current_layer)

func _process(delta):
	# Update mouse position
	var mouse_pos = get_viewport().get_mouse_position()
	var viewport_container = get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport")
	
	if viewport_container and viewport_container.get_global_rect().has_point(mouse_pos):
		# Get local position within viewport
		var local_pos = viewport_container.get_local_mouse_position()
		
		# Convert to world coordinates
		var world_pos = camera.position + local_pos - viewport_container.size / 2
		
		# Convert to grid position
		mouse_world_position = world_pos
		mouse_grid_position = Vector2i(int(world_pos.x) / CELL_SIZE, int(world_pos.y) / CELL_SIZE)
		
		# Update grid cursor
		if grid:
			grid.get_global_mouse_position()
		
		# Update status bar
		_update_status_bar()

func _input(event):
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventKey:
		_handle_key_press(event)

func _handle_mouse_button(event):
	if event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_click()
	else:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_release()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_release()

func _handle_left_click():
	match current_tool:
		"place":
			is_placing = true
			if tile_placement_system:
				tile_placement_system.place_tile(mouse_grid_position, current_z_level)
			else:
				_place_tile(mouse_grid_position, current_z_level)
		"erase":
			is_erasing = true
			if tile_placement_system:
				tile_placement_system.erase_tile(mouse_grid_position, current_z_level)
			else:
				_erase_tile(mouse_grid_position, current_z_level)
		"select":
			is_selecting = true
			selection_start = mouse_grid_position
			selection_end = mouse_grid_position
			selection_active = true
			emit_signal("selection_changed", selection_start, selection_end)
		"fill":
			if tile_placement_system:
				tile_placement_system.fill_area(mouse_grid_position, current_z_level)
			else:
				_fill_area(mouse_grid_position, current_z_level)
		"line":
			is_placing = true
			selection_start = mouse_grid_position
		"place_object":
			if object_placer:
				object_placer.place_object(mouse_grid_position, current_z_level)
		"erase_object":
			if object_placer:
				object_placer.remove_object(mouse_grid_position, current_z_level)
		"select_object":
			if object_placer:
				object_placer.select_object_at(mouse_grid_position, current_z_level)
		"rotate_object":
			if object_placer:
				var obj = object_placer.object_at_position(mouse_grid_position, current_z_level)
				if obj:
					object_placer.rotate_selected_object()
		"place_light":
			if lighting_system:
				lighting_system.place_light(mouse_grid_position, current_z_level)
		"erase_light":
			if lighting_system:
				lighting_system.remove_light(mouse_grid_position, current_z_level)

func _handle_right_click():
	# Right click typically cancels current operation or opens context menu
	is_placing = false
	is_erasing = false
	is_selecting = false
	
	# Clear selection
	if selection_active:
		selection_active = false
		emit_signal("selection_changed", Vector2i.ZERO, Vector2i.ZERO)
	
	# Show context menu if applicable
	# _show_context_menu(mouse_grid_position)

func _handle_left_release():
	if current_tool == "line" and is_placing:
		if tile_placement_system:
			tile_placement_system.draw_line(selection_start, mouse_grid_position, current_z_level)
		else:
			_draw_line(selection_start, mouse_grid_position, current_z_level)
	
	is_placing = false
	is_erasing = false
	
	if is_selecting:
		is_selecting = false
		selection_end = mouse_grid_position
		emit_signal("selection_changed", selection_start, selection_end)
	
func _handle_right_release():
	# Handle right mouse release if needed
	pass

func _handle_key_press(event):
	if event.pressed:
		match event.keycode:
			KEY_DELETE:
				if selection_active:
					_delete_selection()
			KEY_ESCAPE:
				# Cancel current operation
				is_placing = false
				is_erasing = false
				is_selecting = false
				selection_active = false
				emit_signal("selection_changed", Vector2i.ZERO, Vector2i.ZERO)
			KEY_1:
				set_active_layer(0)  # Floor
			KEY_2:
				set_active_layer(1)  # Wall
			KEY_3:
				set_active_layer(2)  # Objects
			KEY_4:
				set_active_layer(4)  # Zone
			KEY_Q:
				set_current_tool("place")
			KEY_W:
				set_current_tool("erase")
			KEY_E:
				set_current_tool("select")
			KEY_R:
				set_current_tool("fill")
			KEY_T:
				set_current_tool("line")
			KEY_PAGEUP:
				set_z_level(current_z_level + 1)
			KEY_PAGEDOWN:
				set_z_level(current_z_level - 1)

# Legacy tile operations - will use TilePlacementSystem if available
func _place_tile(position: Vector2i, z_level: int):
	if current_tile_id == -1 or current_tile_type == "":
		return
	
	var atlas_coords = current_tile_coords
	
	match current_layer:
		0:  # Floor
			floor_tilemap.set_cell(0, position, current_tile_id, atlas_coords)
		1:  # Wall
			wall_tilemap.set_cell(0, position, current_tile_id, atlas_coords)
		2:  # Objects
			objects_tilemap.set_cell(0, position, current_tile_id, atlas_coords)
		4:  # Zone
			if zone_manager:
				var zone_id = zone_manager.get_active_zone()
				if zone_id != -1:
					zone_manager.add_tile_to_zone(zone_id, position)

func _erase_tile(position: Vector2i, z_level: int):
	match current_layer:
		0:  # Floor
			floor_tilemap.set_cell(0, position, -1)
		1:  # Wall
			wall_tilemap.set_cell(0, position, -1)
		2:  # Objects
			objects_tilemap.set_cell(0, position, -1)
		4:  # Zone
			if zone_manager:
				zone_manager.remove_tile_from_zone(position)

func _fill_area(position: Vector2i, z_level: int):
	if current_tile_id == -1 or current_tile_type == "":
		return
	
	var atlas_coords = current_tile_coords
	
	match current_layer:
		0:  # Floor
			_fill_tilemap(floor_tilemap, position, current_tile_id, atlas_coords)
		1:  # Wall
			_fill_tilemap(wall_tilemap, position, current_tile_id, atlas_coords)
		2:  # Objects
			_fill_tilemap(objects_tilemap, position, current_tile_id, atlas_coords)
		4:  # Zone
			if zone_manager:
				var zone_id = zone_manager.get_active_zone()
				if zone_id != -1:
					zone_manager.fill_area(zone_id, position)

func _fill_tilemap(tilemap: TileMap, start_pos: Vector2i, source_id: int, atlas_coords: Vector2i):
	var fill_similar_only = settings_manager.get_setting("tools/fill_similar_only", true)
	var fill_threshold = settings_manager.get_setting("tools/fill_threshold", 0.1)
	
	var fill_cells = []
	var check_cells = [start_pos]
	var checked_cells = {}
	
	# Target value to replace
	var target_source_id = tilemap.get_cell_source_id(0, start_pos)
	var target_atlas_coords = Vector2i(-1, -1)
	if target_source_id != -1:
		target_atlas_coords = tilemap.get_cell_atlas_coords(0, start_pos)
	
	while check_cells.size() > 0:
		var pos = check_cells.pop_front()
		
		# Skip if already checked
		if pos in checked_cells:
			continue
		
		checked_cells[pos] = true
		
		# Check if cell matches what we're looking for
		var current_source_id = tilemap.get_cell_source_id(0, pos)
		
		var matches = false
		if fill_similar_only:
			# Only fill cells with matching source/atlas
			if current_source_id == target_source_id:
				if target_source_id == -1 or tilemap.get_cell_atlas_coords(0, pos) == target_atlas_coords:
					matches = true
		else:
			# Fill any cell
			matches = true
		
		if matches:
			fill_cells.append(pos)
			
			# Add neighbors to check
			check_cells.append(Vector2i(pos.x + 1, pos.y))
			check_cells.append(Vector2i(pos.x - 1, pos.y))
			check_cells.append(Vector2i(pos.x, pos.y + 1))
			check_cells.append(Vector2i(pos.x, pos.y - 1))
	
	# Fill all matching cells
	for pos in fill_cells:
		tilemap.set_cell(0, pos, source_id, atlas_coords)

func _draw_line(start: Vector2i, end: Vector2i, z_level: int):
	if current_tile_id == -1 or current_tile_type == "":
		return
	
	var atlas_coords = current_tile_coords
	
	# Get line style
	var line_style = settings_manager.get_setting("tools/line_style", "straight")
	
	var line_points = []
	
	match line_style:
		"straight":
			line_points = _get_straight_line(start, end)
		"manhattan":
			line_points = _get_manhattan_line(start, end)
		"bresenham":
			line_points = _get_bresenham_line(start, end)
	
	# Place tiles along the line
	for point in line_points:
		_place_tile(point, z_level)

func _get_straight_line(start: Vector2i, end: Vector2i) -> Array:
	var line_points = []
	
	# Get number of steps based on longest dimension
	var dx = abs(end.x - start.x)
	var dy = abs(end.y - start.y)
	var steps = max(dx, dy)
	
	if steps == 0:
		return [start]  # Just the starting point
	
	# Calculate increment per step
	var x_inc = float(end.x - start.x) / steps
	var y_inc = float(end.y - start.y) / steps
	
	# Draw line
	for i in range(steps + 1):
		var x = start.x + int(round(x_inc * i))
		var y = start.y + int(round(y_inc * i))
		line_points.append(Vector2i(x, y))
	
	return line_points

func _get_manhattan_line(start: Vector2i, end: Vector2i) -> Array:
	var line_points = []
	
	# First go along x
	var x = start.x
	var step_x = 1 if end.x > start.x else -1
	while x != end.x:
		line_points.append(Vector2i(x, start.y))
		x += step_x
	
	# Then go along y
	var y = start.y
	var step_y = 1 if end.y > start.y else -1
	while y != end.y + step_y:
		line_points.append(Vector2i(end.x, y))
		y += step_y
	
	return line_points

func _get_bresenham_line(start: Vector2i, end: Vector2i) -> Array:
	var line_points = []
	
	var x0 = start.x
	var y0 = start.y
	var x1 = end.x
	var y1 = end.y
	
	var dx = abs(x1 - x0)
	var dy = -abs(y1 - y0)
	var sx = 1 if x0 < x1 else -1
	var sy = 1 if y0 < y1 else -1
	var err = dx + dy
	
	while true:
		line_points.append(Vector2i(x0, y0))
		
		if x0 == x1 and y0 == y1:
			break
		
		var e2 = 2 * err
		if e2 >= dy:
			if x0 == x1:
				break
			err += dy
			x0 += sx
		
		if e2 <= dx:
			if y0 == y1:
				break
			err += dx
			y0 += sy
	
	return line_points

func _delete_selection():
	if not selection_active:
		return
	
	var min_x = min(selection_start.x, selection_end.x)
	var max_x = max(selection_start.x, selection_end.x)
	var min_y = min(selection_start.y, selection_end.y)
	var max_y = max(selection_start.y, selection_end.y)
	
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if tile_placement_system:
				tile_placement_system.erase_tile(Vector2i(x, y), current_z_level)
			else:
				_erase_tile(Vector2i(x, y), current_z_level)

# Tool selection handlers
func set_current_tool(tool_name: String):
	current_tool = tool_name
	emit_signal("tool_changed", tool_name)
	
	# Update toolbar button states
	_update_tool_buttons(tool_name)
	
	# Update status bar
	_update_status_bar()

func _update_tool_buttons(tool_name: String):
	var place_button = get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/HBoxContainer/ToolsSection/PlaceButton")
	var erase_button = get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/HBoxContainer/ToolsSection/EraseButton")
	var select_button = get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/HBoxContainer/ToolsSection/SelectButton")
	var fill_button = get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/HBoxContainer/ToolsSection/FillButton")
	var line_button = get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/HBoxContainer/ToolsSection/LineButton")
	
	if place_button: place_button.button_pressed = (tool_name == "place")
	if erase_button: erase_button.button_pressed = (tool_name == "erase")
	if select_button: select_button.button_pressed = (tool_name == "select")
	if fill_button: fill_button.button_pressed = (tool_name == "fill")
	if line_button: line_button.button_pressed = (tool_name == "line")
	
	var obj_place_button = get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/HBoxContainer/ObjectToolsSection/ObjectPlaceButton")
	var obj_erase_button = get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/HBoxContainer/ObjectToolsSection/ObjectEraseButton")
	var obj_select_button = get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/HBoxContainer/ObjectToolsSection/ObjectSelectButton")
	var obj_rotate_button = get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/HBoxContainer/ObjectToolsSection/ObjectRotateButton")
	
	if obj_place_button: obj_place_button.button_pressed = (tool_name == "place_object")
	if obj_erase_button: obj_erase_button.button_pressed = (tool_name == "erase_object")
	if obj_select_button: obj_select_button.button_pressed = (tool_name == "select_object")
	if obj_rotate_button: obj_rotate_button.button_pressed = (tool_name == "rotate_object")

func _on_place_tool_selected():
	set_current_tool("place")

func _on_erase_tool_selected():
	set_current_tool("erase")

func _on_select_tool_selected():
	set_current_tool("select")

func _on_fill_tool_selected():
	set_current_tool("fill")

func _on_line_tool_selected():
	set_current_tool("line")

func _on_object_place_selected():
	set_current_tool("place_object")
	
	# Switch to objects tab if not already there
	var tool_tabs = get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/SidePanel/ToolTabs")
	if tool_tabs:
		for i in range(tool_tabs.get_tab_count()):
			if tool_tabs.get_tab_title(i) == "Objects":
				tool_tabs.current_tab = i
				break

func _on_object_erase_selected():
	set_current_tool("erase_object")

func _on_object_select_selected():
	set_current_tool("select_object")

func _on_object_rotate_selected():
	set_current_tool("rotate_object")

# Layer selection handlers
func set_active_layer(layer_id: int):
	current_layer = layer_id
	emit_signal("active_layer_changed", layer_id)
	
	# Update layer buttons
	_update_layer_buttons(layer_id)
	
	# Update layer visibility
	_update_layer_visibility(layer_id)
	
	# Update status bar
	_update_status_bar()
	
	# Update tile placement system layer
	if tile_placement_system:
		tile_placement_system.set_current_layer(layer_id)
	
	# Update tile editor UI
	if tile_editor_ui:
		tile_editor_ui.set_active_layer(layer_id)

func _update_layer_buttons(layer_id: int):
	var floor_button = get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/HBoxContainer/LayersSection/FloorButton")
	var wall_button = get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/HBoxContainer/LayersSection/WallButton")
	var objects_button = get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/HBoxContainer/LayersSection/ObjectsButton")
	var zone_button = get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/HBoxContainer/LayersSection/ZoneButton")
	
	if floor_button: floor_button.button_pressed = (layer_id == 0)
	if wall_button: wall_button.button_pressed = (layer_id == 1)
	if objects_button: objects_button.button_pressed = (layer_id == 2)
	if zone_button: zone_button.button_pressed = (layer_id == 4)

func _update_layer_visibility(layer_id: int):
	var transparency = settings_manager.get_setting("editor/layer_transparency", 0.3)
	
	if floor_tilemap:
		floor_tilemap.modulate.a = 1.0 if layer_id == 0 else transparency
	
	if wall_tilemap:
		wall_tilemap.modulate.a = 1.0 if layer_id == 1 else transparency
	
	if objects_tilemap:
		objects_tilemap.modulate.a = 1.0 if layer_id == 2 else transparency
	
	if zone_tilemap:
		zone_tilemap.modulate.a = 1.0 if layer_id == 4 else transparency

func _on_floor_layer_selected():
	set_active_layer(0)

func _on_wall_layer_selected():
	set_active_layer(1)

func _on_objects_layer_selected():
	set_active_layer(2)

func _on_zone_layer_selected():
	set_active_layer(4)

# Z-level management
func set_z_level(z_level: int):
	# Clamp to valid range
	z_level = clamp(z_level, 0, z_levels - 1)
	
	if z_level != current_z_level:
		current_z_level = z_level
		emit_signal("z_level_changed", z_level)
		
		# Update z-level info
		z_level_info.text = "Z-Level: " + str(current_z_level)
		
		# Update tilemap visibility
		# TODO: Implement tilemap z-level switching
		
		# Let zone manager know
		if zone_manager:
			zone_manager.set_current_z_level(z_level)

func _on_z_level_up_pressed():
	set_z_level(current_z_level + 1)

func _on_z_level_down_pressed():
	set_z_level(current_z_level - 1)

# Tile selection
func set_current_tile(tile_id: int, tile_type: String, atlas_coords: Vector2i):
	current_tile_id = tile_id
	current_tile_type = tile_type
	current_tile_coords = atlas_coords
	
	# Update tile placement system if available
	if tile_placement_system:
		tile_placement_system.set_current_tile(tile_id, tile_type, atlas_coords)

func _on_tile_selected(tile_id: int, tile_type: String, atlas_coords: Vector2i, terrain_id: int = -1):
	set_current_tile(tile_id, tile_type, atlas_coords)

# Object selection
func _on_object_selected(object_type: String):
	# Set object type in the placer
	if object_placer:
		object_placer.set_object_type(object_type)
	
	# Switch to object placement tool
	set_current_tool("place_object")

# Tab switching
func _on_tool_tab_changed(tab_index: int):
	var tool_tabs = get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/SidePanel/ToolTabs")
	if tool_tabs:
		var tab_name = tool_tabs.get_tab_title(tab_index)
		
		match tab_name:
			"Tiles":
				# Switch to appropriate place tool based on layer
				set_current_tool("place")
			"Objects":
				# Switch to object placement
				set_current_tool("place_object")
			"Properties":
				# Switch to selection tool
				set_current_tool("select")
			"Zones":
				# Switch to zone layer and tools
				set_active_layer(4)
				if zone_manager and ui_enhancer:
					ui_enhancer._on_place_zone_tool_selected()
			"Lighting":
				# Switch to lighting tools
				set_current_tool("place_light")

# Status bar updates
func _update_status_bar():
	if not status_info:
		return
	
	var layer_name = ""
	match current_layer:
		0: layer_name = "Floor"
		1: layer_name = "Wall"
		2: layer_name = "Objects"
		3: layer_name = "Wire"
		4: layer_name = "Zone"
	
	var tile_info = ""
	if current_tile_type != "":
		tile_info = " | Tile: " + current_tile_type
	
	status_info.text = "Position: (" + str(mouse_grid_position.x) + ", " + str(mouse_grid_position.y) + ") | Layer: " + layer_name + " | Tool: " + current_tool.capitalize() + tile_info

# Menu handlers
func _on_file_menu_item_selected(id: int):
	match id:
		0:  # New Map
			_show_new_map_dialog()
		1:  # Open Map
			_show_open_map_dialog()
		2:  # Save Map
			if current_map_path != "":
				save_map(current_map_path)
			else:
				_show_save_map_dialog()
		3:  # Save Map As
			_show_save_map_dialog()
		4:  # Exit
			get_tree().quit()

func _on_edit_menu_item_selected(id: int):
	match id:
		0:  # Undo
			_undo()
		1:  # Redo
			_redo()
		2:  # Copy
			_copy_selection()
		3:  # Paste
			_paste_selection()
		4:  # Delete
			_delete_selection()
		5:  # Select All
			_select_all()

func _on_view_menu_item_selected(id: int):
	match id:
		0:  # Show Grid
			var show_grid = !settings_manager.get_setting("display/show_grid", true)
			settings_manager.set_setting("display/show_grid", show_grid)
			grid.toggle_grid_visibility(show_grid)
		1:  # Snap to Grid
			var snap = !settings_manager.get_setting("display/snap_to_grid", true)
			settings_manager.set_setting("display/snap_to_grid", snap)
		2:  # Reset View
			camera.reset_view()
		3:  # Z-Level Up
			set_z_level(current_z_level + 1)
		4:  # Z-Level Down
			set_z_level(current_z_level - 1)

func _on_tools_menu_item_selected(id: int):
	match id:
		0:  # Export to Game
			_show_export_dialog()
		1:  # Import from Game
			_show_import_dialog()
		2:  # Settings
			if ui_enhancer:
				ui_enhancer._on_settings_menu_item_selected(400)  # Show settings dialog
		300:  # Validate Map
			if map_validator:
				map_validator.validate_map()
		301:  # Start Preview Mode
			start_preview_mode()
		302:  # Simulate Atmosphere
			if ui_enhancer:
				ui_enhancer._on_simulate_atmosphere()
		303:  # Import Tiles
			var import_ui = $TileImportUI
			if import_ui:
				import_ui.show_dialog()

func _on_settings_menu_item_selected(id: int):
	# Let the UI enhancer handle settings menu
	if ui_enhancer:
		ui_enhancer._on_settings_menu_item_selected(id)

# File operations
func _show_new_map_dialog():
	var dialog = get_node_or_null("UI/Dialogs/NewMapDialog")
	if dialog:
		# Set default values from settings
		var name_edit = dialog.get_node_or_null("VBoxContainer/GridContainer/NameEdit")
		var width_edit = dialog.get_node_or_null("VBoxContainer/GridContainer/WidthEdit")
		var height_edit = dialog.get_node_or_null("VBoxContainer/GridContainer/HeightEdit")
		var z_levels_edit = dialog.get_node_or_null("VBoxContainer/GridContainer/ZLevelsEdit")
		
		if name_edit:
			name_edit.text = "New Map"
		
		if width_edit:
			width_edit.value = settings_manager.get_setting("map/default_width", 100)
		
		if height_edit:
			height_edit.value = settings_manager.get_setting("map/default_height", 100)
		
		if z_levels_edit:
			z_levels_edit.value = settings_manager.get_setting("map/default_z_levels", 3)
		
		# Connect signals if not connected
		var create_button = dialog.get_node_or_null("VBoxContainer/HBoxContainer/CreateButton")
		if create_button and not create_button.is_connected("pressed", Callable(self, "_on_new_map_create")):
			create_button.pressed.connect(Callable(self, "_on_new_map_create"))
		
		var cancel_button = dialog.get_node_or_null("VBoxContainer/HBoxContainer/CancelButton")
		if cancel_button and not cancel_button.is_connected("pressed", Callable(self, "_on_new_map_cancel")):
			cancel_button.pressed.connect(Callable(self, "_on_new_map_cancel"))
		
		dialog.visible = true

func _on_new_map_create():
	var dialog = get_node_or_null("UI/Dialogs/NewMapDialog")
	if dialog:
		var name_edit = dialog.get_node_or_null("VBoxContainer/GridContainer/NameEdit")
		var width_edit = dialog.get_node_or_null("VBoxContainer/GridContainer/WidthEdit")
		var height_edit = dialog.get_node_or_null("VBoxContainer/GridContainer/HeightEdit")
		var z_levels_edit = dialog.get_node_or_null("VBoxContainer/GridContainer/ZLevelsEdit")
		
		if name_edit and width_edit and height_edit and z_levels_edit:
			create_new_map(
				name_edit.text, 
				int(width_edit.value), 
				int(height_edit.value), 
				int(z_levels_edit.value)
			)
		
		dialog.visible = false

func _on_new_map_cancel():
	var dialog = get_node_or_null("UI/Dialogs/NewMapDialog")
	if dialog:
		dialog.visible = false

func create_new_map(map_name: String, width: int, height: int, num_z_levels: int):
	# Clear existing map
	_clear_map()
	
	# Set map properties
	current_map_name = map_name
	current_map_path = ""
	map_width = width
	map_height = height
	z_levels = num_z_levels
	current_z_level = 0
	
	# Update title
	var map_label = get_node_or_null("UI/MainPanel/VBoxContainer/TopMenu/MapNameLabel")
	if map_label:
		map_label.text = current_map_name
	
	# Update z-level info
	z_level_info.text = "Z-Level: " + str(current_z_level)
	
	# Initialize default zone
	if zone_manager:
		zone_manager.create_zone(ZoneManager.ZoneType.INTERIOR, "Main Interior")

func _clear_map():
	# Clear all tilemaps
	if floor_tilemap:
		floor_tilemap.clear()
	
	if wall_tilemap:
		wall_tilemap.clear()
	
	if objects_tilemap:
		objects_tilemap.clear()
	
	if zone_tilemap:
		zone_tilemap.clear()
	
	# Clear placed objects
	var placed_objects = get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport/PlacedObjects")
	if placed_objects:
		for child in placed_objects.get_children():
			child.queue_free()
	
	# Clear lights
	var light_container = get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport/LightSources")
	if light_container:
		for child in light_container.get_children():
			child.queue_free()
	
	# Reset zone manager
	if zone_manager:
		zone_manager.clear_zones()

func _show_open_map_dialog():
	var dialog = get_node_or_null("UI/Dialogs/OpenMapDialog")
	if dialog:
		dialog.current_path = settings_manager.get_setting("paths/last_save_directory", "user://maps/")
		dialog.visible = true

func _on_map_file_selected(path: String):
	load_map(path)

func _show_save_map_dialog():
	var dialog = get_node_or_null("UI/Dialogs/SaveMapDialog")
	if dialog:
		dialog.current_path = settings_manager.get_setting("paths/last_save_directory", "user://maps/")
		dialog.visible = true

func _on_save_file_selected(path: String):
	save_map(path)

func _show_export_dialog():
	var dialog = get_node_or_null("UI/Dialogs/ExportDialog")
	if dialog:
		dialog.current_path = settings_manager.get_setting("paths/last_export_directory", "user://exports/")
		dialog.visible = true

func _show_import_dialog():
	var dialog = get_node_or_null("UI/Dialogs/OpenMapDialog")
	if dialog:
		dialog.current_path = settings_manager.get_setting("paths/last_export_directory", "user://exports/")
		dialog.visible = true

func save_map(path: String) -> bool:
	# Create map data
	var map_data = {
		"name": current_map_name,
		"width": map_width,
		"height": map_height,
		"z_levels": z_levels,
		"floors": {},
		"walls": {},
		"objects": {},
		"zones": {},
		"placed_objects": {},
		"lights": {},
		"metadata": {}
	}
	
	# Save floor tiles
	if floor_tilemap:
		for cell in floor_tilemap.get_used_cells(0):
			var source_id = floor_tilemap.get_cell_source_id(0, cell)
			var atlas_coords = floor_tilemap.get_cell_atlas_coords(0, cell)
			var key = str(cell.x) + "," + str(cell.y) + "," + str(current_z_level)
			map_data.floors[key] = {
				"source_id": source_id,
				"atlas_coords": {
					"x": atlas_coords.x,
					"y": atlas_coords.y
				}
			}
	
	# Save wall tiles
	if wall_tilemap:
		for cell in wall_tilemap.get_used_cells(0):
			var source_id = wall_tilemap.get_cell_source_id(0, cell)
			var atlas_coords = wall_tilemap.get_cell_atlas_coords(0, cell)
			var key = str(cell.x) + "," + str(cell.y) + "," + str(current_z_level)
			map_data.walls[key] = {
				"source_id": source_id,
				"atlas_coords": {
					"x": atlas_coords.x,
					"y": atlas_coords.y
				}
			}
	
	# Save object tiles
	if objects_tilemap:
		for cell in objects_tilemap.get_used_cells(0):
			var source_id = objects_tilemap.get_cell_source_id(0, cell)
			var atlas_coords = objects_tilemap.get_cell_atlas_coords(0, cell)
			var key = str(cell.x) + "," + str(cell.y) + "," + str(current_z_level)
			map_data.objects[key] = {
				"source_id": source_id,
				"atlas_coords": {
					"x": atlas_coords.x,
					"y": atlas_coords.y
				}
			}
	
	# Save zones
	if zone_manager:
		zone_manager.save_to_map_data(map_data)
	
	# Save placed objects
	if object_placer:
		map_data.placed_objects = object_placer.save_objects_data()
	
	# Save lights
	if lighting_system:
		map_data.lights = lighting_system.save_lights_data()
	
	# Convert to JSON
	var json_string = JSON.stringify(map_data, "  ")
	
	# Save to file
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		
		# Update map path and name
		current_map_path = path
		var map_label = get_node_or_null("UI/MainPanel/VBoxContainer/TopMenu/MapNameLabel")
		if map_label:
			map_label.text = current_map_name
		
		# Add to recent files
		settings_manager.add_recent_file(path)
		
		# Save last directory
		var dir_path = path.get_base_dir()
		settings_manager.set_setting("paths/last_save_directory", dir_path)
		
		return true
	
	return false

func load_map(path: String) -> bool:
	# Read JSON from file
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return false
	
	var json_string = file.get_as_text()
	
	# Parse JSON
	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		print("JSON Parse Error: ", json.get_error_message(), " at line ", json.get_error_line())
		return false
	
	var map_data = json.get_data()
	
	# Clear existing map
	_clear_map()
	
	# Set map properties
	current_map_name = map_data.name
	current_map_path = path
	map_width = map_data.width
	map_height = map_data.height
	z_levels = map_data.z_levels
	current_z_level = 0
	
	# Update title
	var map_label = get_node_or_null("UI/MainPanel/VBoxContainer/TopMenu/MapNameLabel")
	if map_label:
		map_label.text = current_map_name
	
	# Update z-level info
	z_level_info.text = "Z-Level: " + str(current_z_level)
	
	# Load floor tiles
	if "floors" in map_data and floor_tilemap:
		for key in map_data.floors:
			var coords = key.split(",")
			if coords.size() >= 3:
				var pos = Vector2i(int(coords[0]), int(coords[1]))
				var z = int(coords[2])
				
				if z == current_z_level:  # Only load current z-level
					var tile_data = map_data.floors[key]
					var source_id = tile_data.source_id
					var atlas_coords = Vector2i(tile_data.atlas_coords.x, tile_data.atlas_coords.y)
					
					floor_tilemap.set_cell(0, pos, source_id, atlas_coords)
	
	# Load wall tiles
	if "walls" in map_data and wall_tilemap:
		for key in map_data.walls:
			var coords = key.split(",")
			if coords.size() >= 3:
				var pos = Vector2i(int(coords[0]), int(coords[1]))
				var z = int(coords[2])
				
				if z == current_z_level:  # Only load current z-level
					var tile_data = map_data.walls[key]
					var source_id = tile_data.source_id
					var atlas_coords = Vector2i(tile_data.atlas_coords.x, tile_data.atlas_coords.y)
					
					wall_tilemap.set_cell(0, pos, source_id, atlas_coords)
	
	# Load object tiles
	if "objects" in map_data and objects_tilemap:
		for key in map_data.objects:
			var coords = key.split(",")
			if coords.size() >= 3:
				var pos = Vector2i(int(coords[0]), int(coords[1]))
				var z = int(coords[2])
				
				if z == current_z_level:  # Only load current z-level
					var tile_data = map_data.objects[key]
					var source_id = tile_data.source_id
					var atlas_coords = Vector2i(tile_data.atlas_coords.x, tile_data.atlas_coords.y)
					
					objects_tilemap.set_cell(0, pos, source_id, atlas_coords)
	
	# Load zones
	if zone_manager and "zones" in map_data.metadata:
		zone_manager.load_from_map_data(map_data)
	
	# Load placed objects
	if "placed_objects" in map_data and object_placer:
		object_placer.load_objects_data(map_data.placed_objects)
	
	# Load lights
	if "lights" in map_data and lighting_system:
		lighting_system.load_lights_data(map_data.lights)
	
	# Add to recent files
	settings_manager.add_recent_file(path)
	
	# Save last directory
	var dir_path = path.get_base_dir()
	settings_manager.set_setting("paths/last_save_directory", dir_path)
	
	return true

# Edit operations
func _undo():
	# TODO: Implement undo system
	pass

func _redo():
	# TODO: Implement redo system
	pass

func _copy_selection():
	# TODO: Implement copy/paste system
	pass

func _paste_selection():
	# TODO: Implement copy/paste system
	pass

func _select_all():
	selection_start = Vector2i(0, 0)
	selection_end = Vector2i(map_width - 1, map_height - 1)
	selection_active = true
	emit_signal("selection_changed", selection_start, selection_end)

# Autosave handler
func _on_autosave_timeout():
	if current_map_path != "" and settings_manager.get_setting("editor/autosave_enabled", true):
		save_map(current_map_path)

# Preview mode
func start_preview_mode():
	if preview_mode:
		preview_mode.start_preview()
		emit_signal("preview_started")

func stop_preview_mode():
	if preview_mode:
		preview_mode.stop_preview()
		emit_signal("preview_ended")

# Helpers
func get_cell_size() -> int:
	return CELL_SIZE

func get_active_layer() -> int:
	return current_layer
