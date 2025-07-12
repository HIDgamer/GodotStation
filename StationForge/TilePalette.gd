extends ScrollContainer

signal tile_selected(tile_id, tile_type, atlas_coords, terrain_id)

# References
@onready var grid_container = $GridContainer
var editor_ref = null

# Tile display properties
@export var tile_button_size: int = 40
@export var tile_button_padding: int = 2
@export var show_tile_names: bool = true

# Current selections
var current_layer: int = 0
var current_tile_id: int = -1
var current_tile_type: String = ""
var current_tile_properties: Dictionary = {}

# Tile button references
var floor_tile_buttons = {}
var wall_tile_buttons = {}
var object_tile_buttons = {}
var zone_tile_buttons = {}

var import_system = null  # Reference to TileImportSystem

# Category tabs
var category_tabs = null
var subcategory_tabs = {}

func _ready():
	# Try to get editor reference
	editor_ref = get_node_or_null("/root/Editor")
	
	# Initialize with empty palette
	setup_empty_palette()
	
	# Connect signals with editor
	if editor_ref:
		if editor_ref.has_signal("active_layer_changed"):
			editor_ref.connect("active_layer_changed", Callable(self, "_on_editor_layer_changed"))

# Setup an empty palette initially
func setup_empty_palette():
	# Clear any existing buttons
	for child in grid_container.get_children():
		grid_container.remove_child(child)
		child.queue_free()
	
	# Add a label explaining how to add tiles
	var info_label = Label.new()
	info_label.text = "No tiles available.\nImport tiles using the Import button above."
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info_label.custom_minimum_size = Vector2(200, 100)
	grid_container.add_child(info_label)

func setup_palette():
	# Clear any existing buttons
	for child in grid_container.get_children():
		grid_container.remove_child(child)
		child.queue_free()
	
	# Create tabs for categories and subcategories if not already created
	_setup_category_tabs()
	
	# Get import system reference if not already set
	if not import_system:
		import_system = get_node_or_null("/root/TileImportSystem")
	
	# Check if we have any imported tiles
	var has_tiles = false
	if import_system:
		for category in import_system.tile_library:
			if import_system.tile_library[category].size() > 0:
				has_tiles = true
				break
	
	if has_tiles:
		# Load tiles based on the current category and subcategory
		_load_tiles_for_current_category()
	else:
		# Show empty palette message
		setup_empty_palette()

func setup_floor_tiles():
	floor_tile_buttons.clear()
	
	# Get floor types from TileDefinitions
	var floor_types = TileDefinitions.FLOOR_TYPES
	
	# Create a button for each floor type
	for type_id in floor_types:
		var type_data = floor_types[type_id]
		
		# Create button
		var button = create_tile_button(
			type_data.name,
			type_id,
			type_data.atlas_coords,
			type_data.properties
		)
		
		# Add to grid
		grid_container.add_child(button)
		
		# Store reference
		floor_tile_buttons[type_id] = button

func setup_wall_tiles():
	wall_tile_buttons.clear()
	
	# Get wall types from TileDefinitions
	var wall_types = TileDefinitions.WALL_TYPES
	
	# Create a button for each wall type
	for type_id in wall_types:
		var type_data = wall_types[type_id]
		
		# Create button
		var button = create_tile_button(
			type_data.name,
			type_id,
			type_data.atlas_coords,
			type_data.properties
		)
		
		# Add to grid
		grid_container.add_child(button)
		
		# Store reference
		wall_tile_buttons[type_id] = button

func setup_object_tiles():
	object_tile_buttons.clear()
	
	# Get object types from TileDefinitions
	var object_types = TileDefinitions.OBJECT_TYPES
	
	# Create a button for each object type
	for type_id in object_types:
		var type_data = object_types[type_id]
		
		# Create button
		var button = create_tile_button(
			type_data.name,
			type_id,
			type_data.atlas_coords,
			type_data.properties
		)
		
		# Add to grid
		grid_container.add_child(button)
		
		# Store reference
		object_tile_buttons[type_id] = button

func setup_zone_tiles():
	zone_tile_buttons.clear()
	
	# Get zone types from TileDefinitions
	var zone_types = TileDefinitions.ZONE_TYPES
	
	# Create a button for each zone type
	for type_id in zone_types:
		var type_data = zone_types[type_id]
		
		# Create button
		var button = create_tile_button(
			type_data.name,
			type_id,
			type_data.atlas_coords,
			type_data.properties
		)
		
		# Add to grid
		grid_container.add_child(button)
		
		# Store reference
		zone_tile_buttons[type_id] = button

func create_tile_button(name: String, type_id: String, atlas_coords: Vector2i, properties: Dictionary) -> Button:
	# Create button
	var button = Button.new()
	
	# Set size
	button.custom_minimum_size = Vector2(tile_button_size, tile_button_size)
	
	# Set appearance
	button.flat = false
	button.toggle_mode = true
	button.tooltip_text = name
	
	# Set text if enabled
	if show_tile_names:
		button.text = name
	
	# Store tile data
	button.set_meta("tile_id", get_tile_source_id_for_type(type_id))
	button.set_meta("tile_type", type_id)
	button.set_meta("atlas_coords", atlas_coords)
	button.set_meta("properties", properties)
	
	# Connect pressed signal
	button.connect("pressed", Callable(self, "_on_tile_button_pressed").bind(button))
	
	return button

func get_tile_source_id_for_type(type_id: String) -> int:
	# For simplicity, we'll use the index in our tileset
	# In a real implementation, you'd map to your tileset source ids
	
	# Different tile types can use different source ids
	# For now, use 0 as the default source id
	return 0

func _on_tile_button_pressed(button: Button):
	# Unpress other buttons
	for child in grid_container.get_children():
		if child != button and child is Button and child.button_pressed:
			child.button_pressed = false
	
	# Update current selection
	current_tile_id = button.get_meta("tile_id")
	current_tile_type = button.get_meta("tile_type")
	current_tile_properties = button.get_meta("properties")
	
	# Emit signal
	emit_signal("tile_selected", current_tile_id, current_tile_type, current_tile_properties)
	
	# Update editor
	if editor_ref and editor_ref.has_method("set_current_tile"):
		editor_ref.set_current_tile(current_tile_id, current_tile_type, button.get_meta("atlas_coords"))

func _on_editor_layer_changed(layer_id: int):
	current_layer = layer_id
	setup_palette()

func set_active_layer(layer_id: int):
	current_layer = layer_id
	setup_palette()

func refresh():
	_load_tiles_for_current_category()

# Set up category tabs
func _setup_category_tabs():
	if not category_tabs:
		# Create category tabs container
		category_tabs = TabContainer.new()
		category_tabs.set_anchors_preset(Control.PRESET_FULL_RECT)
		
		# Add to parent before grid_container
		var parent = grid_container.get_parent()
		var idx = parent.get_children().find(grid_container)
		if idx >= 0:
			parent.remove_child(grid_container)
			parent.add_child(category_tabs)
			
			# Create containers for each category
			_create_category_tab("Floor", "floor")
			_create_category_tab("Wall", "wall")
			_create_category_tab("Object", "object")
			_create_category_tab("Zone", "zone")
		else:
			push_error("Could not find grid_container in parent")

# Create a tab for a tile category
func _create_category_tab(display_name: String, category_id: String):
	# Create container for this category
	var container = VBoxContainer.new()
	container.name = category_id + "Container"
	
	# Create subcategory tabs
	var subcategory_container = TabContainer.new()
	subcategory_container.name = category_id + "Subcategories"
	subcategory_container.tab_changed.connect(Callable(self, "_on_subcategory_changed").bind(category_id))
	
	# Store for later reference
	subcategory_tabs[category_id] = subcategory_container
	
	# Add import button
	var import_button = Button.new()
	import_button.text = "Import Tiles..."
	import_button.pressed.connect(Callable(self, "_on_import_button_pressed").bind(category_id))
	
	# Add to container
	container.add_child(import_button)
	container.add_child(subcategory_container)
	
	# Add to category tabs
	category_tabs.add_child(container)
	
	# Set tab title
	var idx = category_tabs.get_tab_count() - 1
	category_tabs.set_tab_title(idx, display_name)
	
	# Connect tab changed signal if this is the first tab
	if idx == 0:
		category_tabs.tab_changed.connect(Callable(self, "_on_category_changed"))

# Load tiles for the current category and subcategory
func _load_tiles_for_current_category():
	# Make sure we have category tabs
	if not category_tabs:
		# Fall back to old implementation
		_load_tiles_direct()
		return
	
	# Get current category
	var current_tab = category_tabs.current_tab
	if current_tab < 0:
		return
	
	var category_container = category_tabs.get_child(current_tab)
	var category_id = category_container.name.replace("Container", "")
	
	# Get current subcategory
	var subcategory_tabs_container = subcategory_tabs.get(category_id)
	if not subcategory_tabs_container:
		return
	
	var current_subcategory_tab = subcategory_tabs_container.current_tab
	if current_subcategory_tab < 0:
		return
	
	var subcategory_container = subcategory_tabs_container.get_child(current_subcategory_tab)
	var subcategory_id = subcategory_container.name.replace("Container", "")
	
	# Clear grid container and add it to the subcategory container
	if grid_container.get_parent():
		grid_container.get_parent().remove_child(grid_container)
	
	subcategory_container.add_child(grid_container)
	
	# Clear existing buttons
	for child in grid_container.get_children():
		grid_container.remove_child(child)
		child.queue_free()
	
	# Load tiles for this category/subcategory
	_load_tiles_for_category_subcategory(category_id, subcategory_id)

# Load tiles directly (old method, as fallback)
func _load_tiles_direct():
	# Clear any existing buttons
	for child in grid_container.get_children():
		grid_container.remove_child(child)
		child.queue_free()
	
	# Create buttons based on the current layer
	match current_layer:
		0: # Floor layer
			setup_floor_tiles()
		1: # Wall layer
			setup_wall_tiles()
		2: # Objects layer
			setup_object_tiles()
		4: # Zone layer
			setup_zone_tiles()

# Load tiles for a specific category and subcategory
func _load_tiles_for_category_subcategory(category: String, subcategory: String):
	# Check if import system is available
	if not import_system:
		var import_node = get_node_or_null("/root/StationForge/TileImportSystem")
		if import_node:
			import_system = import_node
	
	# Load built-in tiles first
	_load_builtin_tiles(category, subcategory)
	
	# Load imported tiles
	if import_system:
		_load_imported_tiles(category, subcategory)

# Load built-in tiles from TileDefinitions
func _load_builtin_tiles(category: String, subcategory: String):
	var tiles_dict = {}
	
	# Get tiles dictionary based on category
	match category:
		"floor":
			tiles_dict = TileDefinitions.FLOOR_TYPES
		"wall":
			tiles_dict = TileDefinitions.WALL_TYPES
		"object":
			tiles_dict = TileDefinitions.OBJECT_TYPES
		"zone":
			tiles_dict = TileDefinitions.ZONE_TYPES
	
	# Create a button for each matching tile
	for type_id in tiles_dict:
		var type_data = tiles_dict[type_id]
		
		# Check if subcategory matches
		var tile_subcategory = ""
		if "properties" in type_data:
			tile_subcategory = type_data.properties.get("material", "")
		
		if subcategory == "all" or tile_subcategory == subcategory:
			# Create button
			var button = create_tile_button(
				type_data.name,
				type_id,
				type_data.atlas_coords,
				type_data.properties
			)
			
			# Add to grid
			grid_container.add_child(button)

# Load imported tiles from the TileImportSystem
func _load_imported_tiles(category: String, subcategory: String):
	if not import_system:
		return
	
	# Get tiles for this category
	var all_tiles = import_system.get_tiles_by_category(category)
	
	# Filter by subcategory
	for tile_info in all_tiles:
		var tile_data = tile_info.data
		var tile_id = tile_info.id
		
		# Check subcategory
		var tile_subcategory = tile_data.get("subcategory", "")
		
		if subcategory == "all" or tile_subcategory == subcategory:
			# Get texture
			var texture = import_system.get_tile_texture(category, tile_id)
			
			# Create button with texture preview
			var button = create_imported_tile_button(
				tile_data.get("name", "Unnamed"),
				tile_id,
				tile_data.get("atlas_coords", Vector2i(0, 0)),
				tile_data.get("properties", {}),
				texture
			)
			
			# Add to grid
			grid_container.add_child(button)

# Create a button for an imported tile
func create_imported_tile_button(name: String, tile_id: String, atlas_coords: Vector2i, 
		properties: Dictionary, texture = null) -> Button:
	# Create button
	var button = Button.new()
	
	# Set size
	button.custom_minimum_size = Vector2(tile_button_size, tile_button_size)
	
	# Set appearance
	button.flat = false
	button.toggle_mode = true
	button.tooltip_text = name
	
	# Add texture if available
	if texture:
		var texture_rect = TextureRect.new()
		texture_rect.texture = texture
		texture_rect.expand = true
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture_rect.custom_minimum_size = Vector2(tile_button_size - 6, tile_button_size - 6)
		texture_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		texture_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		
		button.add_child(texture_rect)
	else:
		# Set text if enabled
		if show_tile_names:
			button.text = name
	
	# Store tile data
	button.set_meta("tile_id", get_tile_source_id_for_imported_tile(tile_id))
	button.set_meta("tile_type", tile_id)
	button.set_meta("atlas_coords", atlas_coords)
	button.set_meta("properties", properties)
	button.set_meta("imported", true)
	
	# Connect pressed signal
	button.pressed.connect(Callable(self, "_on_tile_button_pressed").bind(button))
	
	return button

# Get source ID for imported tiles
func get_tile_source_id_for_imported_tile(tile_id: String) -> int:
	# Implementation depends on how your EnhancedTilesetManager handles imported tiles
	# For simplicity, we'll return a specific source ID for imported tiles
	return 100  # This should match your EnhancedTilesetManager's import source ID

# Update subcategory tabs for the given category
func _update_subcategory_tabs(category: String):
	var subcategory_tabs_container = subcategory_tabs.get(category)
	if not subcategory_tabs_container:
		return
	
	# Clear existing tabs
	for child in subcategory_tabs_container.get_children():
		subcategory_tabs_container.remove_child(child)
		child.queue_free()
	
	# Get unique subcategories for this category
	var subcategories = _get_subcategories_for_category(category)
	
	# Always add "All" tab
	var all_container = VBoxContainer.new()
	all_container.name = "allContainer"
	subcategory_tabs_container.add_child(all_container)
	
	# Add tabs for each subcategory
	for subcategory in subcategories:
		var container = VBoxContainer.new()
		container.name = subcategory + "Container"
		subcategory_tabs_container.add_child(container)
		
		var idx = subcategory_tabs_container.get_tab_count() - 1
		subcategory_tabs_container.set_tab_title(idx, subcategory.capitalize())
	
	# Set "All" as the tab title for first tab
	if subcategory_tabs_container.get_tab_count() > 0:
		subcategory_tabs_container.set_tab_title(0, "All")

# Get unique subcategories for a category
func _get_subcategories_for_category(category: String) -> Array:
	var subcategories = []
	
	# Check built-in tiles
	var tiles_dict = {}
	
	# Get tiles dictionary based on category
	match category:
		"floor":
			tiles_dict = TileDefinitions.FLOOR_TYPES
		"wall":
			tiles_dict = TileDefinitions.WALL_TYPES
		"object":
			tiles_dict = TileDefinitions.OBJECT_TYPES
		"zone":
			tiles_dict = TileDefinitions.ZONE_TYPES
	
	# Get subcategories from properties
	for type_id in tiles_dict:
		var type_data = tiles_dict[type_id]
		
		if "properties" in type_data:
			var material = type_data.properties.get("material", "")
			if material != "" and not material in subcategories:
				subcategories.append(material)
	
	# Get subcategories from imported tiles
	if import_system:
		var all_tiles = import_system.get_tiles_by_category(category)
		
		for tile_info in all_tiles:
			var tile_data = tile_info.data
			var subcategory = tile_data.get("subcategory", "")
			
			if subcategory != "" and not subcategory in subcategories:
				subcategories.append(subcategory)
	
	return subcategories

# Signal handlers for category/subcategory changes
func _on_category_changed(tab: int):
	_update_subcategory_tabs(category_tabs.get_child(tab).name.replace("Container", ""))
	_load_tiles_for_current_category()

func _on_subcategory_changed(tab: int, category: String):
	_load_tiles_for_current_category()

# Show tile import dialog for a specific category
func _on_import_button_pressed(category: String):
	# Get reference to import UI
	var import_ui = get_node_or_null("/root/StationForge/TileImportUI")
	if import_ui:
		# Set category
		var category_selector = import_ui.get_node_or_null("ImportDialog/VBoxContainer/CategorySelector")
		if category_selector:
			match category:
				"floor": category_selector.selected = 0
				"wall": category_selector.selected = 1
				"object": category_selector.selected = 2
				"zone": category_selector.selected = 3
		
		# Show dialog
		import_ui.show_dialog()
