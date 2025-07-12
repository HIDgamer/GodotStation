extends Node
class_name TileEditorUI

# References
var editor_ref = null
var tileset_manager = null
var tile_placement_system = null

# UI Elements
var main_container: VBoxContainer = null
var tab_container: TabContainer = null
var tile_grid: GridContainer = null
var terrain_list: ItemList = null
var options_container: VBoxContainer = null
var preview_panel: Panel = null
var preview_texture_rect: TextureRect = null

# Current state
var current_layer = 0  # 0 = floor, 1 = wall, 2 = objects, 4 = zone
var current_terrain_id = -1
var current_tile_id = -1
var current_tile_type = ""
var current_atlas_coords = Vector2i(0, 0)

# Layer to tileset mapping
var layer_to_type = {
	0: "floor",  # Floor layer
	1: "wall",   # Wall layer
	2: "object", # Object layer
	4: "zone"    # Zone layer
}

# Signal
signal tile_selected(tile_id, tile_type, tile_coords, terrain_id)

func _init(p_editor_ref = null, p_tileset_manager = null, p_tile_placement_system = null):
	editor_ref = p_editor_ref
	tileset_manager = p_tileset_manager
	tile_placement_system = p_tile_placement_system

# Setup the tile editor UI
func setup(parent_node: Control):
	if not parent_node:
		return
	
	# Create main container
	main_container = VBoxContainer.new()
	main_container.name = "TileEditorContainer"
	main_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent_node.add_child(main_container)
	
	# Create tabs
	tab_container = TabContainer.new()
	tab_container.name = "TileEditorTabs"
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_container.add_child(tab_container)
	
	# Create tile selection tab
	_create_tile_selection_tab()
	
	# Create terrain tab if we have a tileset manager
	if tileset_manager:
		_create_terrain_tab()
	
	# Create options tab
	_create_options_tab()
	
	# Create preview tab
	_create_preview_tab()
	
	# Initialize with current layer
	set_active_layer(current_layer)

# Set active layer
func set_active_layer(layer_id: int):
	current_layer = layer_id
	
	# Update current tile type
	if layer_id in layer_to_type:
		current_tile_type = layer_to_type[layer_id]
	else:
		current_tile_type = ""
	
	# Update UI
	_update_tile_grid()
	_update_terrain_list()
	_update_preview_panel()

# Create tile selection tab
func _create_tile_selection_tab():
	var tile_tab = VBoxContainer.new()
	tile_tab.name = "Tiles"
	tab_container.add_child(tile_tab)
	
	# Add a scroll container for tiles
	var scroll = ScrollContainer.new()
	scroll.name = "TileScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile_tab.add_child(scroll)
	
	# Create a grid container for tiles
	tile_grid = GridContainer.new()
	tile_grid.name = "TileGrid"
	tile_grid.columns = 4
	tile_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(tile_grid)
	
	# Add search and filter options
	var filter_container = HBoxContainer.new()
	filter_container.name = "FilterContainer"
	tile_tab.add_child(filter_container)
	
	var search_label = Label.new()
	search_label.text = "Search:"
	filter_container.add_child(search_label)
	
	var search_box = LineEdit.new()
	search_box.name = "SearchBox"
	search_box.placeholder_text = "Search tiles..."
	search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_container.add_child(search_box)
	
	# Connect signals
	search_box.text_changed.connect(Callable(self, "_on_search_text_changed"))

# Create terrain tab
func _create_terrain_tab():
	var terrain_tab = VBoxContainer.new()
	terrain_tab.name = "Terrains"
	tab_container.add_child(terrain_tab)
	
	# Add a scroll container for terrains
	var scroll = ScrollContainer.new()
	scroll.name = "TerrainScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	terrain_tab.add_child(scroll)
	
	# Create list for terrain types
	terrain_list = ItemList.new()
	terrain_list.name = "TerrainList"
	terrain_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	terrain_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	terrain_list.select_mode = ItemList.SELECT_SINGLE
	scroll.add_child(terrain_list)
	
	# Connect signals
	terrain_list.item_selected.connect(Callable(self, "_on_terrain_selected"))

# Create options tab
func _create_options_tab():
	var options_tab = ScrollContainer.new()
	options_tab.name = "Options"
	tab_container.add_child(options_tab)
	
	# Create options container
	options_container = VBoxContainer.new()
	options_container.name = "OptionsContainer"
	options_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_tab.add_child(options_container)
	
	# Add auto-tiling option
	var auto_tiling_check = CheckBox.new()
	auto_tiling_check.name = "AutoTilingCheck"
	auto_tiling_check.text = "Enable Auto-Tiling"
	auto_tiling_check.button_pressed = true
	options_container.add_child(auto_tiling_check)
	
	# Add random variation option
	var random_variation_check = CheckBox.new()
	random_variation_check.name = "RandomVariationCheck"
	random_variation_check.text = "Enable Random Variations"
	random_variation_check.button_pressed = true
	options_container.add_child(random_variation_check)
	
	# Add fill similar only option
	var fill_similar_check = CheckBox.new()
	fill_similar_check.name = "FillSimilarCheck"
	fill_similar_check.text = "Fill Similar Tiles Only"
	fill_similar_check.button_pressed = true
	options_container.add_child(fill_similar_check)
	
	# Add fill threshold option
	var fill_threshold_container = HBoxContainer.new()
	options_container.add_child(fill_threshold_container)
	
	var fill_threshold_label = Label.new()
	fill_threshold_label.text = "Fill Threshold:"
	fill_threshold_container.add_child(fill_threshold_label)
	
	var fill_threshold_slider = HSlider.new()
	fill_threshold_slider.name = "FillThresholdSlider"
	fill_threshold_slider.min_value = 0.0
	fill_threshold_slider.max_value = 1.0
	fill_threshold_slider.step = 0.05
	fill_threshold_slider.value = 0.1
	fill_threshold_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill_threshold_container.add_child(fill_threshold_slider)
	
	# Add line drawing style option
	var line_style_container = HBoxContainer.new()
	options_container.add_child(line_style_container)
	
	var line_style_label = Label.new()
	line_style_label.text = "Line Drawing Style:"
	line_style_container.add_child(line_style_label)
	
	var line_style_option = OptionButton.new()
	line_style_option.name = "LineStyleOption"
	line_style_option.add_item("Straight", 0)
	line_style_option.add_item("Manhattan", 1)
	line_style_option.add_item("Bresenham", 2)
	line_style_option.selected = 0
	line_style_container.add_child(line_style_option)
	
	# Connect signals
	auto_tiling_check.toggled.connect(Callable(self, "_on_auto_tiling_toggled"))
	random_variation_check.toggled.connect(Callable(self, "_on_random_variation_toggled"))
	fill_similar_check.toggled.connect(Callable(self, "_on_fill_similar_toggled"))
	fill_threshold_slider.value_changed.connect(Callable(self, "_on_fill_threshold_changed"))
	line_style_option.item_selected.connect(Callable(self, "_on_line_style_selected"))

# Create preview tab
func _create_preview_tab():
	var preview_tab = VBoxContainer.new()
	preview_tab.name = "Preview"
	tab_container.add_child(preview_tab)
	
	# Create panel for preview
	preview_panel = Panel.new()
	preview_panel.name = "PreviewPanel"
	preview_panel.custom_minimum_size = Vector2(200, 200)
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_tab.add_child(preview_panel)
	
	# Create texture rect for tile preview
	preview_texture_rect = TextureRect.new()
	preview_texture_rect.name = "PreviewTextureRect"
	preview_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_texture_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_texture_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_panel.add_child(preview_texture_rect)
	
	# Add info panel below preview
	var info_container = VBoxContainer.new()
	info_container.name = "InfoContainer"
	preview_tab.add_child(info_container)
	
	var tile_info_label = Label.new()
	tile_info_label.name = "TileInfoLabel"
	tile_info_label.text = "No tile selected"
	info_container.add_child(tile_info_label)
	
	var terrain_info_label = Label.new()
	terrain_info_label.name = "TerrainInfoLabel"
	terrain_info_label.text = "Terrain: None"
	info_container.add_child(terrain_info_label)

# Update tile grid based on current layer
func _update_tile_grid():
	# Clear existing tiles
	for child in tile_grid.get_children():
		tile_grid.remove_child(child)
		child.queue_free()
	
	# Skip if no tileset manager
	if not tileset_manager:
		return
	
	# Get tileset for current layer
	var tileset_type = layer_to_type.get(current_layer, "")
	if tileset_type == "":
		return
	
	# Get tileset configurations
	var config = tileset_manager.tileset_configs.get(tileset_type, {})
	if config.is_empty():
		return
	
	# Create buttons for each tile in the tileset
	var regions = config.get("regions", [])
	
	for region in regions:
		var region_size = region.get("region_size", Vector2i(0, 0))
		if region_size.x <= 0 or region_size.y <= 0:
			continue
		
		var x_offset = region.get("x_offset", 0)
		var y_offset = region.get("y_offset", 0)
		
		# Add a region label
		var region_label = Label.new()
		region_label.text = region.get("name", "Unnamed Region")
		region_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile_grid.add_child(region_label)
		
		# Add spacer cells to fill the row
		for i in range(tile_grid.columns - 1):
			var spacer = Control.new()
			tile_grid.add_child(spacer)
		
		# Add buttons for each tile in the region
		for y in range(region_size.y):
			for x in range(region_size.x):
				var atlas_coords = Vector2i(x + x_offset, y + y_offset)
				
				# Create button with tile preview
				var button = Button.new()
				button.toggle_mode = true
				button.custom_minimum_size = Vector2(40, 40)
				
				# Store tile data in button metadata
				button.set_meta("tile_id", 0)  # Use first source by default
				button.set_meta("tile_type", tileset_type)
				button.set_meta("atlas_coords", atlas_coords)
				
				# Get terrain info if available
				var terrain_info = tileset_manager.get_terrain_info(tileset_type, atlas_coords)
				if not terrain_info.is_empty() and "terrain_id" in terrain_info:
					button.set_meta("terrain_id", terrain_info.terrain_id)
				else:
					button.set_meta("terrain_id", -1)
				
				# Create preview texture
				var preview_tex = _create_tile_preview_texture(tileset_type, atlas_coords)
				if preview_tex:
					var tex_rect = TextureRect.new()
					tex_rect.texture = preview_tex
					tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					tex_rect.custom_minimum_size = Vector2(32, 32)
					button.add_child(tex_rect)
				
				# Connect signal
				button.pressed.connect(Callable(self, "_on_tile_button_pressed").bind(button))
				
				tile_grid.add_child(button)

# Update terrain list based on current layer
func _update_terrain_list():
	# Skip if no terrain list or tileset manager
	if not terrain_list or not tileset_manager:
		return
	
	# Clear the list
	terrain_list.clear()
	
	# Get tileset for current layer
	var tileset_type = layer_to_type.get(current_layer, "")
	if tileset_type == "":
		return
	
	# Get terrain data
	var terrain_data = tileset_manager.terrain_data.get(tileset_type, {})
	if terrain_data.is_empty():
		return
	
	# Add an "All Tiles" option
	terrain_list.add_item("All Tiles")
	terrain_list.set_item_metadata(0, -1)  # -1 means no specific terrain
	
	# Add each terrain type
	var terrains = terrain_data.get("terrains", [])
	for i in range(terrains.size()):
		var terrain = terrains[i]
		var name = terrain.get("name", "Unnamed Terrain")
		var color = terrain.get("color", Color.WHITE)
		
		terrain_list.add_item(name)
		terrain_list.set_item_metadata(i + 1, i)  # +1 because "All Tiles" is at index 0
		terrain_list.set_item_icon_modulate(i + 1, color)

# Update preview panel
func _update_preview_panel():
	# Skip if no preview elements
	if not preview_texture_rect:
		return
	
	# Update texture if we have a tile selected
	if current_tile_type != "" and current_atlas_coords != Vector2i(-1, -1):
		var texture = _create_tile_preview_texture(current_tile_type, current_atlas_coords)
		preview_texture_rect.texture = texture
		
		# Update info labels
		var tile_info_label = preview_panel.get_parent().get_node_or_null("InfoContainer/TileInfoLabel")
		var terrain_info_label = preview_panel.get_parent().get_node_or_null("InfoContainer/TerrainInfoLabel")
		
		if tile_info_label:
			tile_info_label.text = "Tile: " + current_tile_type + " at " + str(current_atlas_coords)
		
		if terrain_info_label and tileset_manager:
			var terrain_info = tileset_manager.get_terrain_info(current_tile_type, current_atlas_coords)
			if not terrain_info.is_empty() and "terrain_id" in terrain_info and terrain_info.terrain_id >= 0:
				# Get terrain name if available
				var terrain_name = "Unknown"
				var terrain_data = tileset_manager.terrain_data.get(current_tile_type, {})
				var terrains = terrain_data.get("terrains", [])
				
				if terrain_info.terrain_id < terrains.size():
					terrain_name = terrains[terrain_info.terrain_id].get("name", "Unnamed")
				
				terrain_info_label.text = "Terrain: " + terrain_name + " (ID: " + str(terrain_info.terrain_id) + ")"
			else:
				terrain_info_label.text = "Terrain: None"

# Create a preview texture for a tile
func _create_tile_preview_texture(tile_type: String, atlas_coords: Vector2i) -> Texture2D:
	if not tileset_manager:
		return null
	
	# Get the tileset
	var tileset = tileset_manager.get_tileset(tile_type)
	if not tileset:
		return null
	
	# Get the source
	var source = tileset.get_source(0) as TileSetAtlasSource
	if not source:
		return null
	
	# Check if the tile exists
	if not source.has_tile(atlas_coords):
		return null
	
	# Get the region rect
	var region = source.get_tile_texture_region(atlas_coords)
	
	# Create an AtlasTexture
	var atlas_texture = AtlasTexture.new()
	atlas_texture.atlas = source.texture
	atlas_texture.region = region
	
	return atlas_texture

# Handle tile button pressed
func _on_tile_button_pressed(button: Button):
	# Unpress other buttons
	for child in tile_grid.get_children():
		if child is Button and child != button and child.button_pressed:
			child.button_pressed = false
	
	# Update current tile
	current_tile_id = button.get_meta("tile_id")
	current_tile_type = button.get_meta("tile_type")
	current_atlas_coords = button.get_meta("atlas_coords")
	current_terrain_id = button.get_meta("terrain_id")
	
	# Update preview
	_update_preview_panel()
	
	# Emit signal
	emit_signal("tile_selected", current_tile_id, current_tile_type, current_atlas_coords, current_terrain_id)
	
	# Update tile placement system if available
	if tile_placement_system:
		tile_placement_system.set_current_tile(current_tile_id, current_tile_type, current_atlas_coords)

# Handle terrain selected
func _on_terrain_selected(index: int):
	var terrain_id = terrain_list.get_item_metadata(index)
	
	# Filter the tile grid to show only tiles with this terrain
	_filter_tiles_by_terrain(terrain_id)

# Filter tiles by terrain
func _filter_tiles_by_terrain(terrain_id: int):
	# Skip if no tileset manager
	if not tileset_manager:
		return
	
	# Show all tiles if terrain_id is -1
	if terrain_id < 0:
		for child in tile_grid.get_children():
			if child is Button:
				child.visible = true
		return
	
	# Otherwise show only tiles with matching terrain
	for child in tile_grid.get_children():
		if child is Button:
			var child_terrain_id = child.get_meta("terrain_id", -1)
			child.visible = (child_terrain_id == terrain_id)

# Handle search text changed
func _on_search_text_changed(new_text: String):
	# Skip if search text is empty
	if new_text.strip_edges() == "":
		for child in tile_grid.get_children():
			if child is Button:
				child.visible = true
		return
	
	# Otherwise filter tiles by name or type
	for child in tile_grid.get_children():
		if child is Button:
			var tile_type = child.get_meta("tile_type", "")
			var contains_text = tile_type.to_lower().contains(new_text.to_lower())
			child.visible = contains_text

# Toggle settings
func _on_auto_tiling_toggled(toggled: bool):
	if tile_placement_system:
		tile_placement_system.toggle_auto_tiling(toggled)

func _on_random_variation_toggled(toggled: bool):
	if tile_placement_system:
		tile_placement_system.toggle_random_variations(toggled)

func _on_fill_similar_toggled(toggled: bool):
	if editor_ref and editor_ref.settings_manager:
		editor_ref.settings_manager.set_setting("tools/fill_similar_only", toggled)

func _on_fill_threshold_changed(value: float):
	if editor_ref and editor_ref.settings_manager:
		editor_ref.settings_manager.set_setting("tools/fill_threshold", value)

func _on_line_style_selected(index: int):
	if editor_ref and editor_ref.settings_manager:
		var style = "straight"
		match index:
			0: style = "straight"
			1: style = "manhattan"
			2: style = "bresenham"
		
		editor_ref.settings_manager.set_setting("tools/line_style", style)
