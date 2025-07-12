extends Node
class_name EditorUIEnhancer

# References
var editor_ref = null
var settings_manager = null
var zone_manager = null
var lighting_system = null
var preview_mode = null

# UI elements
var settings_dialog: Window = null
var atmosphere_panel: Panel = null
var lighting_panel: Panel = null
var preview_panel: Panel = null
var zone_tools_container: HBoxContainer = null
var lighting_tools_container: HBoxContainer = null
var preview_tools_container: HBoxContainer = null

func _init(p_editor_ref, p_settings_manager = null, p_zone_manager = null, p_lighting_system = null, p_preview_mode = null):
	editor_ref = p_editor_ref
	settings_manager = p_settings_manager
	zone_manager = p_zone_manager
	lighting_system = p_lighting_system
	preview_mode = p_preview_mode

# Setup UI elements for all new features
func setup():
	if not editor_ref:
		return
	
	# Set up all UI elements
	_setup_settings_dialog()
	_setup_zone_tools()
	_setup_lighting_tools()
	_setup_preview_tools()
	_setup_main_menu_items()
	
	# Connect signals
	_connect_signals()

# Set up the settings dialog
func _setup_settings_dialog():
	if not editor_ref.has_node("UI/Dialogs"):
		return
	
	var dialogs = editor_ref.get_node("UI/Dialogs")
	
	# Create settings dialog
	settings_dialog = Window.new()
	settings_dialog.title = "StationForge Settings"
	settings_dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	settings_dialog.size = Vector2i(800, 600)
	settings_dialog.visible = false
	settings_dialog.unresizable = false
	settings_dialog.close_requested.connect(Callable(self, "_on_settings_dialog_close"))
	
	dialogs.add_child(settings_dialog)
	
	# Create dialog content
	var main_container = VBoxContainer.new()
	main_container.anchors_preset = Control.PRESET_FULL_RECT
	main_container.offset_left = 10
	main_container.offset_top = 10
	main_container.offset_right = -10
	main_container.offset_bottom = -10
	settings_dialog.add_child(main_container)
	
	# Create tabs
	var tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_container.add_child(tabs)
	
	# Add tabs for different settings categories
	_create_display_settings_tab(tabs)
	_create_editor_settings_tab(tabs)
	_create_map_settings_tab(tabs)
	_create_tools_settings_tab(tabs)
	_create_atmosphere_settings_tab(tabs)
	_create_lighting_settings_tab(tabs)
	_create_preview_settings_tab(tabs)
	_create_ui_settings_tab(tabs)
	_create_paths_settings_tab(tabs)
	
	# Add buttons at bottom
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_END
	main_container.add_child(button_container)
	
	var reset_button = Button.new()
	reset_button.text = "Reset to Default"
	reset_button.pressed.connect(Callable(self, "_on_reset_settings"))
	button_container.add_child(reset_button)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_container.add_child(spacer)
	
	var cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(Callable(self, "_on_settings_dialog_close"))
	button_container.add_child(cancel_button)
	
	var apply_button = Button.new()
	apply_button.text = "Apply"
	apply_button.pressed.connect(Callable(self, "_on_apply_settings"))
	button_container.add_child(apply_button)
	
	var ok_button = Button.new()
	ok_button.text = "OK"
	ok_button.pressed.connect(Callable(self, "_on_ok_settings"))
	button_container.add_child(ok_button)

# Create display settings tab
func _create_display_settings_tab(tabs: TabContainer):
	var tab = VBoxContainer.new()
	tab.name = "Display"
	tabs.add_child(tab)
	
	var grid = GridContainer.new()
	grid.columns = 2
	tab.add_child(grid)
	
	# Grid settings
	_add_setting_label(grid, "Grid Visibility:")
	var show_grid = CheckBox.new()
	show_grid.text = "Show Grid"
	show_grid.button_pressed = settings_manager.get_setting("display/show_grid", true)
	show_grid.set_meta("setting_path", "display/show_grid")
	grid.add_child(show_grid)
	
	_add_setting_label(grid, "Grid Opacity:")
	var grid_opacity = HSlider.new()
	grid_opacity.min_value = 0.0
	grid_opacity.max_value = 1.0
	grid_opacity.step = 0.05
	grid_opacity.value = settings_manager.get_setting("display/grid_opacity", 0.3)
	grid_opacity.set_meta("setting_path", "display/grid_opacity")
	grid.add_child(grid_opacity)
	
	_add_setting_label(grid, "Grid Major Lines:")
	var grid_major = CheckBox.new()
	grid_major.text = "Show Major Lines"
	grid_major.button_pressed = settings_manager.get_setting("display/grid_major_lines", true)
	grid_major.set_meta("setting_path", "display/grid_major_lines")
	grid.add_child(grid_major)
	
	_add_setting_label(grid, "Major Lines Interval:")
	var major_interval = SpinBox.new()
	major_interval.min_value = 2
	major_interval.max_value = 20
	major_interval.value = settings_manager.get_setting("display/grid_major_interval", 5)
	major_interval.set_meta("setting_path", "display/grid_major_interval")
	grid.add_child(major_interval)
	
	_add_setting_label(grid, "Grid Color:")
	var grid_color = ColorPickerButton.new()
	grid_color.color = settings_manager.get_setting("display/grid_color", Color(0.5, 0.5, 0.5, 0.2))
	grid_color.set_meta("setting_path", "display/grid_color")
	grid.add_child(grid_color)
	
	_add_setting_label(grid, "Major Lines Color:")
	var major_color = ColorPickerButton.new()
	major_color.color = settings_manager.get_setting("display/grid_major_color", Color(0.5, 0.5, 0.5, 0.4))
	major_color.set_meta("setting_path", "display/grid_major_color")
	grid.add_child(major_color)
	
	# Other display settings
	_add_setting_label(grid, "Snap to Grid:")
	var snap_grid = CheckBox.new()
	snap_grid.text = "Enable"
	snap_grid.button_pressed = settings_manager.get_setting("display/snap_to_grid", true)
	snap_grid.set_meta("setting_path", "display/snap_to_grid")
	grid.add_child(snap_grid)
	
	_add_setting_label(grid, "Show Ruler:")
	var show_ruler = CheckBox.new()
	show_ruler.text = "Enable"
	show_ruler.button_pressed = settings_manager.get_setting("display/show_ruler", false)
	show_ruler.set_meta("setting_path", "display/show_ruler")
	grid.add_child(show_ruler)
	
	_add_setting_label(grid, "Show Coordinates:")
	var show_coords = CheckBox.new()
	show_coords.text = "Enable"
	show_coords.button_pressed = settings_manager.get_setting("display/show_coordinates", true)
	show_coords.set_meta("setting_path", "display/show_coordinates")
	grid.add_child(show_coords)

# Create editor settings tab
func _create_editor_settings_tab(tabs: TabContainer):
	var tab = VBoxContainer.new()
	tab.name = "Editor"
	tabs.add_child(tab)
	
	var grid = GridContainer.new()
	grid.columns = 2
	tab.add_child(grid)
	
	# Autosave settings
	_add_setting_label(grid, "Autosave:")
	var autosave = CheckBox.new()
	autosave.text = "Enable"
	autosave.button_pressed = settings_manager.get_setting("editor/autosave_enabled", true)
	autosave.set_meta("setting_path", "editor/autosave_enabled")
	grid.add_child(autosave)
	
	_add_setting_label(grid, "Autosave Interval (s):")
	var autosave_interval = SpinBox.new()
	autosave_interval.min_value = 30
	autosave_interval.max_value = 3600
	autosave_interval.value = settings_manager.get_setting("editor/autosave_interval", 300)
	autosave_interval.set_meta("setting_path", "editor/autosave_interval")
	grid.add_child(autosave_interval)
	
	# Undo settings
	_add_setting_label(grid, "Undo History Size:")
	var undo_size = SpinBox.new()
	undo_size.min_value = 10
	undo_size.max_value = 200
	undo_size.value = settings_manager.get_setting("editor/undo_history_size", 50)
	undo_size.set_meta("setting_path", "editor/undo_history_size")
	grid.add_child(undo_size)
	
	# Layer settings
	_add_setting_label(grid, "Inactive Layer Transparency:")
	var layer_transparency = HSlider.new()
	layer_transparency.min_value = 0.0
	layer_transparency.max_value = 1.0
	layer_transparency.step = 0.05
	layer_transparency.value = settings_manager.get_setting("editor/layer_transparency", 0.3)
	layer_transparency.set_meta("setting_path", "editor/layer_transparency")
	grid.add_child(layer_transparency)
	
	# Confirmation settings
	_add_setting_label(grid, "Confirm Deletions:")
	var confirm_del = CheckBox.new()
	confirm_del.text = "Enable"
	confirm_del.button_pressed = settings_manager.get_setting("editor/confirm_deletions", true)
	confirm_del.set_meta("setting_path", "editor/confirm_deletions")
	grid.add_child(confirm_del)
	
	# Selection settings
	_add_setting_label(grid, "Auto-Center Selection:")
	var auto_center = CheckBox.new()
	auto_center.text = "Enable"
	auto_center.button_pressed = settings_manager.get_setting("editor/auto_center_selection", true)
	auto_center.set_meta("setting_path", "editor/auto_center_selection")
	grid.add_child(auto_center)

# Create map settings tab
func _create_map_settings_tab(tabs: TabContainer):
	var tab = VBoxContainer.new()
	tab.name = "Map"
	tabs.add_child(tab)
	
	var grid = GridContainer.new()
	grid.columns = 2
	tab.add_child(grid)
	
	# Default map size settings
	_add_setting_label(grid, "Default Map Width:")
	var def_width = SpinBox.new()
	def_width.min_value = 10
	def_width.max_value = 1000
	def_width.value = settings_manager.get_setting("map/default_width", 100)
	def_width.set_meta("setting_path", "map/default_width")
	grid.add_child(def_width)
	
	_add_setting_label(grid, "Default Map Height:")
	var def_height = SpinBox.new()
	def_height.min_value = 10
	def_height.max_value = 1000
	def_height.value = settings_manager.get_setting("map/default_height", 100)
	def_height.set_meta("setting_path", "map/default_height")
	grid.add_child(def_height)
	
	_add_setting_label(grid, "Default Z-Levels:")
	var def_z_levels = SpinBox.new()
	def_z_levels.min_value = 1
	def_z_levels.max_value = 10
	def_z_levels.value = settings_manager.get_setting("map/default_z_levels", 3)
	def_z_levels.set_meta("setting_path", "map/default_z_levels")
	grid.add_child(def_z_levels)
	
	# Color scheme
	_add_setting_label(grid, "Color Scheme:")
	var color_scheme = OptionButton.new()
	color_scheme.add_item("Default", 0)
	color_scheme.add_item("High Contrast", 1)
	color_scheme.add_item("Minimal", 2)
	color_scheme.add_item("Dark", 3)
	color_scheme.add_item("Light", 4)
	var current_scheme = settings_manager.get_setting("map/map_color_scheme", "default")
	var scheme_index = 0
	match current_scheme:
		"default": scheme_index = 0
		"high_contrast": scheme_index = 1
		"minimal": scheme_index = 2
		"dark": scheme_index = 3
		"light": scheme_index = 4
	color_scheme.selected = scheme_index
	color_scheme.set_meta("setting_path", "map/map_color_scheme")
	grid.add_child(color_scheme)

# Create tools settings tab
func _create_tools_settings_tab(tabs: TabContainer):
	var tab = VBoxContainer.new()
	tab.name = "Tools"
	tabs.add_child(tab)
	
	var grid = GridContainer.new()
	grid.columns = 2
	tab.add_child(grid)
	
	# Fill tool settings
	_add_setting_label(grid, "Fill Similar Only:")
	var fill_similar = CheckBox.new()
	fill_similar.text = "Enable"
	fill_similar.button_pressed = settings_manager.get_setting("tools/fill_similar_only", true)
	fill_similar.set_meta("setting_path", "tools/fill_similar_only")
	grid.add_child(fill_similar)
	
	_add_setting_label(grid, "Fill Threshold:")
	var fill_threshold = HSlider.new()
	fill_threshold.min_value = 0.0
	fill_threshold.max_value = 1.0
	fill_threshold.step = 0.05
	fill_threshold.value = settings_manager.get_setting("tools/fill_threshold", 0.1)
	fill_threshold.set_meta("setting_path", "tools/fill_threshold")
	grid.add_child(fill_threshold)
	
	# Line tool settings
	_add_setting_label(grid, "Line Drawing Style:")
	var line_style = OptionButton.new()
	line_style.add_item("Straight", 0)
	line_style.add_item("Manhattan", 1)
	line_style.add_item("Bresenham", 2)
	var current_style = settings_manager.get_setting("tools/line_style", "straight")
	var style_index = 0
	match current_style:
		"straight": style_index = 0
		"manhattan": style_index = 1
		"bresenham": style_index = 2
	line_style.selected = style_index
	line_style.set_meta("setting_path", "tools/line_style")
	grid.add_child(line_style)
	
	# Selection settings
	_add_setting_label(grid, "Selection Drag Threshold:")
	var drag_threshold = SpinBox.new()
	drag_threshold.min_value = 1
	drag_threshold.max_value = 10
	drag_threshold.value = settings_manager.get_setting("tools/selection_drag_threshold", 3)
	drag_threshold.set_meta("setting_path", "tools/selection_drag_threshold")
	grid.add_child(drag_threshold)
	
	# Multi-tile mode
	_add_setting_label(grid, "Multi-Tile Mode:")
	var multi_tile_mode = OptionButton.new()
	multi_tile_mode.add_item("Rectangle", 0)
	multi_tile_mode.add_item("Ellipse", 1)
	multi_tile_mode.add_item("Free-Form", 2)
	var current_mode = settings_manager.get_setting("tools/multi_tile_mode", "rectangle")
	var mode_index = 0
	match current_mode:
		"rectangle": mode_index = 0
		"ellipse": mode_index = 1
		"free_form": mode_index = 2
	multi_tile_mode.selected = mode_index
	multi_tile_mode.set_meta("setting_path", "tools/multi_tile_mode")
	grid.add_child(multi_tile_mode)

# Create atmosphere settings tab
func _create_atmosphere_settings_tab(tabs: TabContainer):
	var tab = VBoxContainer.new()
	tab.name = "Atmosphere"
	tabs.add_child(tab)
	
	var grid = GridContainer.new()
	grid.columns = 2
	tab.add_child(grid)
	
	# Zone overlay settings
	_add_setting_label(grid, "Show Zone Overlay:")
	var show_overlay = CheckBox.new()
	show_overlay.text = "Enable"
	show_overlay.button_pressed = settings_manager.get_setting("atmosphere/show_zone_overlay", false)
	show_overlay.set_meta("setting_path", "atmosphere/show_zone_overlay")
	grid.add_child(show_overlay)
	
	_add_setting_label(grid, "Zone Overlay Opacity:")
	var overlay_opacity = HSlider.new()
	overlay_opacity.min_value = 0.0
	overlay_opacity.max_value = 1.0
	overlay_opacity.step = 0.05
	overlay_opacity.value = settings_manager.get_setting("atmosphere/zone_overlay_opacity", 0.3)
	overlay_opacity.set_meta("setting_path", "atmosphere/zone_overlay_opacity")
	grid.add_child(overlay_opacity)
	
	_add_setting_label(grid, "Zone Overlay Mode:")
	var overlay_mode = OptionButton.new()
	overlay_mode.add_item("Zone Type", 0)
	overlay_mode.add_item("Pressure", 1)
	overlay_mode.add_item("Temperature", 2)
	overlay_mode.add_item("Atmosphere", 3)
	overlay_mode.add_item("Gravity", 4)
	var current_mode = settings_manager.get_setting("atmosphere/zone_overlay_mode", "type")
	var mode_index = 0
	match current_mode:
		"type": mode_index = 0
		"pressure": mode_index = 1
		"temperature": mode_index = 2
		"atmosphere": mode_index = 3
		"gravity": mode_index = 4
	overlay_mode.selected = mode_index
	overlay_mode.set_meta("setting_path", "atmosphere/zone_overlay_mode")
	grid.add_child(overlay_mode)
	
	# Simulation settings
	_add_setting_label(grid, "Simulation Speed:")
	var sim_speed = HSlider.new()
	sim_speed.min_value = 0.1
	sim_speed.max_value = 5.0
	sim_speed.step = 0.1
	sim_speed.value = settings_manager.get_setting("atmosphere/simulation_speed", 1.0)
	sim_speed.set_meta("setting_path", "atmosphere/simulation_speed")
	grid.add_child(sim_speed)
	
	_add_setting_label(grid, "Auto-Simulate:")
	var auto_sim = CheckBox.new()
	auto_sim.text = "Enable"
	auto_sim.button_pressed = settings_manager.get_setting("atmosphere/auto_simulate", false)
	auto_sim.set_meta("setting_path", "atmosphere/auto_simulate")
	grid.add_child(auto_sim)

# Create lighting settings tab
func _create_lighting_settings_tab(tabs: TabContainer):
	var tab = VBoxContainer.new()
	tab.name = "Lighting"
	tabs.add_child(tab)
	
	var grid = GridContainer.new()
	grid.columns = 2
	tab.add_child(grid)
	
	# Lighting preview settings
	_add_setting_label(grid, "Show Lights Preview:")
	var show_preview = CheckBox.new()
	show_preview.text = "Enable"
	show_preview.button_pressed = settings_manager.get_setting("lighting/show_lights_preview", false)
	show_preview.set_meta("setting_path", "lighting/show_lights_preview")
	grid.add_child(show_preview)
	
	_add_setting_label(grid, "Ambient Light Level:")
	var ambient_light = HSlider.new()
	ambient_light.min_value = 0.0
	ambient_light.max_value = 1.0
	ambient_light.step = 0.05
	ambient_light.value = settings_manager.get_setting("lighting/ambient_light_level", 0.8)
	ambient_light.set_meta("setting_path", "lighting/ambient_light_level")
	grid.add_child(ambient_light)
	
	_add_setting_label(grid, "Light Attenuation:")
	var attenuation = HSlider.new()
	attenuation.min_value = 0.5
	attenuation.max_value = 5.0
	attenuation.step = 0.1
	attenuation.value = settings_manager.get_setting("lighting/light_attenuation", 1.5)
	attenuation.set_meta("setting_path", "lighting/light_attenuation")
	grid.add_child(attenuation)
	
	# Shadow settings
	_add_setting_label(grid, "Enable Shadows:")
	var enable_shadows = CheckBox.new()
	enable_shadows.text = "Enable"
	enable_shadows.button_pressed = settings_manager.get_setting("lighting/enable_shadows", true)
	enable_shadows.set_meta("setting_path", "lighting/enable_shadows")
	grid.add_child(enable_shadows)
	
	_add_setting_label(grid, "Shadow Intensity:")
	var shadow_intensity = HSlider.new()
	shadow_intensity.min_value = 0.0
	shadow_intensity.max_value = 1.0
	shadow_intensity.step = 0.05
	shadow_intensity.value = settings_manager.get_setting("lighting/shadow_intensity", 0.7)
	shadow_intensity.set_meta("setting_path", "lighting/shadow_intensity")
	grid.add_child(shadow_intensity)

# Create preview settings tab
func _create_preview_settings_tab(tabs: TabContainer):
	var tab = VBoxContainer.new()
	tab.name = "Preview"
	tabs.add_child(tab)
	
	var grid = GridContainer.new()
	grid.columns = 2
	tab.add_child(grid)
	
	# Preview mode settings
	_add_setting_label(grid, "Player Move Speed:")
	var move_speed = HSlider.new()
	move_speed.min_value = 1.0
	move_speed.max_value = 10.0
	move_speed.step = 0.5
	move_speed.value = settings_manager.get_setting("preview/player_move_speed", 5.0)
	move_speed.set_meta("setting_path", "preview/player_move_speed")
	grid.add_child(move_speed)
	
	_add_setting_label(grid, "Show Debug Overlay:")
	var debug_overlay = CheckBox.new()
	debug_overlay.text = "Enable"
	debug_overlay.button_pressed = settings_manager.get_setting("preview/show_debug_overlay", true)
	debug_overlay.set_meta("setting_path", "preview/show_debug_overlay")
	grid.add_child(debug_overlay)
	
	_add_setting_label(grid, "Auto-Open Doors:")
	var auto_open = CheckBox.new()
	auto_open.text = "Enable"
	auto_open.button_pressed = settings_manager.get_setting("preview/auto_open_doors", true)
	auto_open.set_meta("setting_path", "preview/auto_open_doors")
	grid.add_child(auto_open)
	
	_add_setting_label(grid, "Simulate Atmosphere:")
	var sim_atmos = CheckBox.new()
	sim_atmos.text = "Enable"
	sim_atmos.button_pressed = settings_manager.get_setting("preview/simulate_atmosphere", true)
	sim_atmos.set_meta("setting_path", "preview/simulate_atmosphere")
	grid.add_child(sim_atmos)

# Create UI settings tab
func _create_ui_settings_tab(tabs: TabContainer):
	var tab = VBoxContainer.new()
	tab.name = "UI"
	tabs.add_child(tab)
	
	var grid = GridContainer.new()
	grid.columns = 2
	tab.add_child(grid)
	
	# Theme settings
	_add_setting_label(grid, "Theme:")
	var theme = OptionButton.new()
	theme.add_item("Dark", 0)
	theme.add_item("Light", 1)
	theme.add_item("Classic", 2)
	var current_theme = settings_manager.get_setting("ui/theme", "dark")
	var theme_index = 0
	match current_theme:
		"dark": theme_index = 0
		"light": theme_index = 1
		"classic": theme_index = 2
	theme.selected = theme_index
	theme.set_meta("setting_path", "ui/theme")
	grid.add_child(theme)
	
	# Toolbar position
	_add_setting_label(grid, "Toolbar Position:")
	var toolbar_pos = OptionButton.new()
	toolbar_pos.add_item("Top", 0)
	toolbar_pos.add_item("Left", 1)
	toolbar_pos.add_item("Right", 2)
	var current_pos = settings_manager.get_setting("ui/toolbar_position", "top")
	var pos_index = 0
	match current_pos:
		"top": pos_index = 0
		"left": pos_index = 1
		"right": pos_index = 2
	toolbar_pos.selected = pos_index
	toolbar_pos.set_meta("setting_path", "ui/toolbar_position")
	grid.add_child(toolbar_pos)
	
	# Sidebar width
	_add_setting_label(grid, "Sidebar Width:")
	var sidebar_width = SpinBox.new()
	sidebar_width.min_value = 150
	sidebar_width.max_value = 500
	sidebar_width.value = settings_manager.get_setting("ui/sidebar_width", 250)
	sidebar_width.set_meta("setting_path", "ui/sidebar_width")
	grid.add_child(sidebar_width)
	
	# Status bar
	_add_setting_label(grid, "Show Status Bar:")
	var status_bar = CheckBox.new()
	status_bar.text = "Enable"
	status_bar.button_pressed = settings_manager.get_setting("ui/show_status_bar", true)
	status_bar.set_meta("setting_path", "ui/show_status_bar")
	grid.add_child(status_bar)
	
	# Layer bar
	_add_setting_label(grid, "Show Layer Bar:")
	var layer_bar = CheckBox.new()
	layer_bar.text = "Enable"
	layer_bar.button_pressed = settings_manager.get_setting("ui/show_layer_bar", true)
	layer_bar.set_meta("setting_path", "ui/show_layer_bar")
	grid.add_child(layer_bar)
	
	# Tool tooltips
	_add_setting_label(grid, "Show Tool Tooltips:")
	var tool_tips = CheckBox.new()
	tool_tips.text = "Enable"
	tool_tips.button_pressed = settings_manager.get_setting("ui/show_tool_tooltips", true)
	tool_tips.set_meta("setting_path", "ui/show_tool_tooltips")
	grid.add_child(tool_tips)

# Create paths settings tab
func _create_paths_settings_tab(tabs: TabContainer):
	var tab = VBoxContainer.new()
	tab.name = "Paths"
	tabs.add_child(tab)
	
	var grid = GridContainer.new()
	grid.columns = 2
	tab.add_child(grid)
	
	# Save directory
	_add_setting_label(grid, "Default Save Directory:")
	var save_dir_hbox = HBoxContainer.new()
	grid.add_child(save_dir_hbox)
	
	var save_dir = LineEdit.new()
	save_dir.text = settings_manager.get_setting("paths/last_save_directory", "user://maps/")
	save_dir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_dir.set_meta("setting_path", "paths/last_save_directory")
	save_dir_hbox.add_child(save_dir)
	
	var save_dir_button = Button.new()
	save_dir_button.text = "Browse..."
	save_dir_button.pressed.connect(Callable(self, "_on_browse_save_dir"))
	save_dir_hbox.add_child(save_dir_button)
	
	# Export directory
	_add_setting_label(grid, "Default Export Directory:")
	var export_dir_hbox = HBoxContainer.new()
	grid.add_child(export_dir_hbox)
	
	var export_dir = LineEdit.new()
	export_dir.text = settings_manager.get_setting("paths/last_export_directory", "user://exports/")
	export_dir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_dir.set_meta("setting_path", "paths/last_export_directory")
	export_dir_hbox.add_child(export_dir)
	
	var export_dir_button = Button.new()
	export_dir_button.text = "Browse..."
	export_dir_button.pressed.connect(Callable(self, "_on_browse_export_dir"))
	export_dir_hbox.add_child(export_dir_button)
	
	# Custom assets directory
	_add_setting_label(grid, "Custom Assets Directory:")
	var assets_dir_hbox = HBoxContainer.new()
	grid.add_child(assets_dir_hbox)
	
	var assets_dir = LineEdit.new()
	assets_dir.text = settings_manager.get_setting("paths/custom_assets_directory", "user://assets/")
	assets_dir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	assets_dir.set_meta("setting_path", "paths/custom_assets_directory")
	assets_dir_hbox.add_child(assets_dir)
	
	var assets_dir_button = Button.new()
	assets_dir_button.text = "Browse..."
	assets_dir_button.pressed.connect(Callable(self, "_on_browse_assets_dir"))
	assets_dir_hbox.add_child(assets_dir_button)
	
	# Recent files
	_add_setting_label(grid, "Recent Files:")
	var recent_files_vbox = VBoxContainer.new()
	grid.add_child(recent_files_vbox)
	
	var recent_files_list = ItemList.new()
	recent_files_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	recent_files_list.set_meta("recent_files_list", true)
	recent_files_vbox.add_child(recent_files_list)
	
	# Populate recent files
	var recent_files = settings_manager.get_setting("paths/recent_files", [])
	for file in recent_files:
		recent_files_list.add_item(file)
	
	# Clear button
	var clear_button = Button.new()
	clear_button.text = "Clear Recent Files"
	clear_button.pressed.connect(Callable(self, "_on_clear_recent_files"))
	recent_files_vbox.add_child(clear_button)

# Helper to add setting label
func _add_setting_label(parent: Control, text: String):
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(label)

# Set up zone tools
func _setup_zone_tools():
	if not editor_ref.has_node("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar"):
		return
	
	var toolbar = editor_ref.get_node("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar")
	
	# Get the existing zone tools container if it exists
	zone_tools_container = toolbar.get_node_or_null("ZoneToolsSection")
	if zone_tools_container:
		return
	
	# Create zone tools section
	zone_tools_container = HBoxContainer.new()
	zone_tools_container.name = "ZoneToolsSection"
	toolbar.add_child(zone_tools_container)
	
	# Add divider
	var separator = VSeparator.new()
	zone_tools_container.add_child(separator)
	
	# Add section label
	var label = Label.new()
	label.text = "Zones:"
	zone_tools_container.add_child(label)
	
	# Add zone type selector
	var zone_type = OptionButton.new()
	zone_type.name = "ZoneTypeButton"
	zone_type.add_item("Interior", ZoneManager.ZoneType.INTERIOR)
	zone_type.add_item("Maintenance", ZoneManager.ZoneType.MAINTENANCE)
	zone_type.add_item("Exterior", ZoneManager.ZoneType.EXTERIOR)
	zone_type.selected = 0
	zone_tools_container.add_child(zone_type)
	
	# Add zone tools
	var place_zone_button = Button.new()
	place_zone_button.name = "PlaceZoneButton"
	place_zone_button.text = "Place"
	place_zone_button.toggle_mode = true
	zone_tools_container.add_child(place_zone_button)
	
	var fill_zone_button = Button.new()
	fill_zone_button.name = "FillZoneButton"
	fill_zone_button.text = "Fill"
	fill_zone_button.toggle_mode = true
	zone_tools_container.add_child(fill_zone_button)
	
	var rect_zone_button = Button.new()
	rect_zone_button.name = "RectZoneButton"
	rect_zone_button.text = "Rectangle"
	rect_zone_button.toggle_mode = true
	zone_tools_container.add_child(rect_zone_button)
	
	var erase_zone_button = Button.new()
	erase_zone_button.name = "EraseZoneButton"
	erase_zone_button.text = "Erase"
	erase_zone_button.toggle_mode = true
	zone_tools_container.add_child(erase_zone_button)
	
	# Add visualization button
	var visualize_button = Button.new()
	visualize_button.name = "VisualizeButton"
	visualize_button.text = "Visualize"
	visualize_button.toggle_mode = true
	zone_tools_container.add_child(visualize_button)
	
	# Add simulation button
	var simulate_button = Button.new()
	simulate_button.name = "SimulateButton"
	simulate_button.text = "Simulate"
	simulate_button.toggle_mode = true
	zone_tools_container.add_child(simulate_button)

# Set up lighting tools
func _setup_lighting_tools():
	if not editor_ref.has_node("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar"):
		return
	
	var toolbar = editor_ref.get_node("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar")
	
	# Get the existing lighting tools container if it exists
	lighting_tools_container = toolbar.get_node_or_null("LightingToolsSection")
	if lighting_tools_container:
		return
	
	# Create lighting tools section
	lighting_tools_container = HBoxContainer.new()
	lighting_tools_container.name = "LightingToolsSection"
	toolbar.add_child(lighting_tools_container)
	
	# Add divider
	var separator = VSeparator.new()
	lighting_tools_container.add_child(separator)
	
	# Add section label
	var label = Label.new()
	label.text = "Lighting:"
	lighting_tools_container.add_child(label)
	
	# Add light tools
	var place_light_button = Button.new()
	place_light_button.name = "PlaceLightButton"
	place_light_button.text = "Place Light"
	place_light_button.toggle_mode = true
	lighting_tools_container.add_child(place_light_button)
	
	var erase_light_button = Button.new()
	erase_light_button.name = "EraseLightButton"
	erase_light_button.text = "Erase Light"
	erase_light_button.toggle_mode = true
	lighting_tools_container.add_child(erase_light_button)
	
	var light_preview_button = Button.new()
	light_preview_button.name = "LightPreviewButton"
	light_preview_button.text = "Preview"
	light_preview_button.toggle_mode = true
	lighting_tools_container.add_child(light_preview_button)
	
	# Add ambient light slider
	var light_label = Label.new()
	light_label.text = "Ambient:"
	lighting_tools_container.add_child(light_label)
	
	var ambient_slider = HSlider.new()
	ambient_slider.name = "AmbientSlider"
	ambient_slider.min_value = 0.0
	ambient_slider.max_value = 1.0
	ambient_slider.step = 0.05
	ambient_slider.value = settings_manager.get_setting("lighting/ambient_light_level", 0.8)
	ambient_slider.custom_minimum_size = Vector2(100, 0)
	lighting_tools_container.add_child(ambient_slider)

# Set up preview tools
func _setup_preview_tools():
	if not editor_ref.has_node("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar"):
		return
	
	var toolbar = editor_ref.get_node("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar")
	
	# Get the existing preview tools container if it exists
	preview_tools_container = toolbar.get_node_or_null("PreviewToolsSection")
	if preview_tools_container:
		return
	
	# Create preview tools section
	preview_tools_container = HBoxContainer.new()
	preview_tools_container.name = "PreviewToolsSection"
	toolbar.add_child(preview_tools_container)
	
	# Add divider
	var separator = VSeparator.new()
	preview_tools_container.add_child(separator)
	
	# Add section label
	var label = Label.new()
	label.text = "Preview:"
	preview_tools_container.add_child(label)
	
	# Add preview tools
	var start_preview_button = Button.new()
	start_preview_button.name = "StartPreviewButton"
	start_preview_button.text = "Start Preview"
	preview_tools_container.add_child(start_preview_button)
	
	var stop_preview_button = Button.new()
	stop_preview_button.name = "StopPreviewButton"
	stop_preview_button.text = "Stop Preview"
	preview_tools_container.add_child(stop_preview_button)
	
	# Add other preview options
	var validate_button = Button.new()
	validate_button.name = "ValidateButton"
	validate_button.text = "Validate Map"
	preview_tools_container.add_child(validate_button)

# Set up main menu items
func _setup_main_menu_items():
	if not editor_ref.has_node("UI/MainPanel/VBoxContainer/TopMenu"):
		return
	
	var top_menu = editor_ref.get_node("UI/MainPanel/VBoxContainer/TopMenu")
	
	# Modify View menu
	var view_menu = top_menu.get_node_or_null("ViewMenu")
	if view_menu and view_menu is MenuButton:
		var popup = view_menu.get_popup()
		
		# Check if items already exist
		var has_zone_item = false
		var has_light_item = false
		
		for i in range(popup.item_count):
			var item_id = popup.get_item_id(i)
			if item_id == 100:
				has_zone_item = true
			elif item_id == 110:
				has_light_item = true
		
		# Add zone visualization items if they don't exist
		if not has_zone_item:
			popup.add_separator()
			popup.add_item("Zone Visualization", 100)
			popup.add_submenu_item("Zone View Mode", "ZoneViewMenu", 101)
			
			# Create zone view submenu
			var zone_view_menu = PopupMenu.new()
			zone_view_menu.name = "ZoneViewMenu"
			zone_view_menu.add_item("Zone Types", 200)
			zone_view_menu.add_item("Pressure", 201)
			zone_view_menu.add_item("Temperature", 202)
			zone_view_menu.add_item("Atmosphere", 203)
			zone_view_menu.add_item("Gravity", 204)
			popup.add_child(zone_view_menu)
			
			# Connect zone view menu
			zone_view_menu.id_pressed.connect(Callable(self, "_on_zone_view_menu_item_selected"))
		
		# Add lighting visualization items if they don't exist
		if not has_light_item:
			if not has_zone_item:  # Only add separator if we didn't already add one
				popup.add_separator()
			popup.add_item("Lighting Preview", 110)
			popup.add_item("Adjust Ambient Light", 111)
		
		# Connect signals if not already connected
		if not popup.is_connected("id_pressed", Callable(self, "_on_view_menu_item_selected")):
			popup.id_pressed.connect(Callable(self, "_on_view_menu_item_selected"))
	
	# Modify Tools menu
	var tools_menu = top_menu.get_node_or_null("ToolsMenu")
	if tools_menu and tools_menu is MenuButton:
		var popup = tools_menu.get_popup()
		
		# Check if items already exist
		var has_validate_item = false
		
		for i in range(popup.item_count):
			var item_id = popup.get_item_id(i)
			if item_id == 300:
				has_validate_item = true
				break
		
		# Add items if they don't exist
		if not has_validate_item:
			# Add separator
			popup.add_separator()
			
			# Add validation item
			popup.add_item("Validate Map", 300)
			
			# Add preview item
			popup.add_item("Start Preview Mode", 301)
			
			# Add atmosphere simulation
			popup.add_item("Simulate Atmosphere", 302)
		
		# Connect signals if not already connected
		if not popup.is_connected("id_pressed", Callable(self, "_on_tools_menu_item_selected")):
			popup.id_pressed.connect(Callable(self, "_on_tools_menu_item_selected"))
	
	# Add Settings menu if not exists
	if not top_menu.has_node("SettingsMenu"):
		var settings_menu = MenuButton.new()
		settings_menu.name = "SettingsMenu"
		settings_menu.text = "Settings"
		settings_menu.flat = false
		
		# Add after Tools menu
		var tools_index = top_menu.get_children().find(tools_menu)
		if tools_index != -1:
			top_menu.add_child_below_node(tools_menu, settings_menu)
		else:
			top_menu.add_child(settings_menu)
		
		# Set up popup
		var popup = settings_menu.get_popup()
		popup.add_item("Editor Settings", 400)
		popup.add_separator()
		popup.add_item("Import Settings", 401)
		popup.add_item("Export Settings", 402)
		popup.add_separator()
		popup.add_item("Reset to Default", 403)
		
		# Connect signals
		popup.id_pressed.connect(Callable(self, "_on_settings_menu_item_selected"))

# Connect signals
func _connect_signals():
	# Connect settings manager signals
	if settings_manager:
		if not settings_manager.is_connected("settings_changed", Callable(self, "_on_setting_changed")):
			settings_manager.connect("settings_changed", Callable(self, "_on_setting_changed"))
		
		if not settings_manager.is_connected("settings_loaded", Callable(self, "_on_settings_loaded")):
			settings_manager.connect("settings_loaded", Callable(self, "_on_settings_loaded"))
	
	# Connect zone tool signals
	if zone_tools_container:
		var zone_type_button = zone_tools_container.get_node_or_null("ZoneTypeButton")
		if zone_type_button and not zone_type_button.is_connected("item_selected", Callable(self, "_on_zone_type_selected")):
			zone_type_button.connect("item_selected", Callable(self, "_on_zone_type_selected"))
			
		var place_zone_button = zone_tools_container.get_node_or_null("PlaceZoneButton")
		if place_zone_button and not place_zone_button.is_connected("pressed", Callable(self, "_on_place_zone_tool_selected")):
			place_zone_button.connect("pressed", Callable(self, "_on_place_zone_tool_selected"))
			
		var fill_zone_button = zone_tools_container.get_node_or_null("FillZoneButton")
		if fill_zone_button and not fill_zone_button.is_connected("pressed", Callable(self, "_on_fill_zone_tool_selected")):
			fill_zone_button.connect("pressed", Callable(self, "_on_fill_zone_tool_selected"))
			
		var rect_zone_button = zone_tools_container.get_node_or_null("RectZoneButton")
		if rect_zone_button and not rect_zone_button.is_connected("pressed", Callable(self, "_on_rect_zone_tool_selected")):
			rect_zone_button.connect("pressed", Callable(self, "_on_rect_zone_tool_selected"))
			
		var erase_zone_button = zone_tools_container.get_node_or_null("EraseZoneButton")
		if erase_zone_button and not erase_zone_button.is_connected("pressed", Callable(self, "_on_erase_zone_tool_selected")):
			erase_zone_button.connect("pressed", Callable(self, "_on_erase_zone_tool_selected"))
			
		var visualize_button = zone_tools_container.get_node_or_null("VisualizeButton")
		if visualize_button and not visualize_button.is_connected("toggled", Callable(self, "_on_visualize_zones_toggled")):
			visualize_button.connect("toggled", Callable(self, "_on_visualize_zones_toggled"))
			
		var simulate_button = zone_tools_container.get_node_or_null("SimulateButton")
		if simulate_button and not simulate_button.is_connected("toggled", Callable(self, "_on_simulate_atmosphere_toggled")):
			simulate_button.connect("toggled", Callable(self, "_on_simulate_atmosphere_toggled"))
	
	# Connect lighting tool signals
	if lighting_tools_container:
		var place_light_button = lighting_tools_container.get_node_or_null("PlaceLightButton")
		if place_light_button and not place_light_button.is_connected("pressed", Callable(self, "_on_place_light_tool_selected")):
			place_light_button.connect("pressed", Callable(self, "_on_place_light_tool_selected"))
			
		var erase_light_button = lighting_tools_container.get_node_or_null("EraseLightButton")
		if erase_light_button and not erase_light_button.is_connected("pressed", Callable(self, "_on_erase_light_tool_selected")):
			erase_light_button.connect("pressed", Callable(self, "_on_erase_light_tool_selected"))
			
		var light_preview_button = lighting_tools_container.get_node_or_null("LightPreviewButton")
		if light_preview_button and not light_preview_button.is_connected("toggled", Callable(self, "_on_light_preview_toggled")):
			light_preview_button.connect("toggled", Callable(self, "_on_light_preview_toggled"))
			
		var ambient_slider = lighting_tools_container.get_node_or_null("AmbientSlider")
		if ambient_slider and not ambient_slider.is_connected("value_changed", Callable(self, "_on_ambient_light_changed")):
			ambient_slider.connect("value_changed", Callable(self, "_on_ambient_light_changed"))
	
	# Connect preview tool signals
	if preview_tools_container:
		var start_preview_button = preview_tools_container.get_node_or_null("StartPreviewButton")
		if start_preview_button and not start_preview_button.is_connected("pressed", Callable(self, "_on_start_preview")):
			start_preview_button.connect("pressed", Callable(self, "_on_start_preview"))
			
		var stop_preview_button = preview_tools_container.get_node_or_null("StopPreviewButton")
		if stop_preview_button and not stop_preview_button.is_connected("pressed", Callable(self, "_on_stop_preview")):
			stop_preview_button.connect("pressed", Callable(self, "_on_stop_preview"))
			
		var validate_button = preview_tools_container.get_node_or_null("ValidateButton")
		if validate_button and not validate_button.is_connected("pressed", Callable(self, "_on_validate_map")):
			validate_button.connect("pressed", Callable(self, "_on_validate_map"))

# Handler for zone type selection
func _on_zone_type_selected(index: int):
	if zone_manager:
		var zone_type_button = zone_tools_container.get_node_or_null("ZoneTypeButton")
		if zone_type_button:
			var zone_type = zone_type_button.get_selected_id()
			zone_manager.set_active_zone_type(zone_type)

# Handler for zone tool selection
func _on_place_zone_tool_selected():
	if zone_manager:
		zone_manager.set_current_tool("place")
		_update_zone_tool_buttons("PlaceZoneButton")
		
		# Tell editor to switch to zone layer
		if editor_ref and editor_ref.has_method("set_active_layer"):
			editor_ref.set_active_layer(4)  # Zone layer index

func _on_fill_zone_tool_selected():
	if zone_manager:
		zone_manager.set_current_tool("fill")
		_update_zone_tool_buttons("FillZoneButton")
		
		# Tell editor to switch to zone layer
		if editor_ref and editor_ref.has_method("set_active_layer"):
			editor_ref.set_active_layer(4)  # Zone layer index

func _on_rect_zone_tool_selected():
	if zone_manager:
		zone_manager.set_current_tool("rect")
		_update_zone_tool_buttons("RectZoneButton")
		
		# Tell editor to switch to zone layer
		if editor_ref and editor_ref.has_method("set_active_layer"):
			editor_ref.set_active_layer(4)  # Zone layer index

func _on_erase_zone_tool_selected():
	if zone_manager:
		zone_manager.set_current_tool("erase")
		_update_zone_tool_buttons("EraseZoneButton")
		
		# Tell editor to switch to zone layer
		if editor_ref and editor_ref.has_method("set_active_layer"):
			editor_ref.set_active_layer(4)  # Zone layer index

# Helper to update zone tool button states
func _update_zone_tool_buttons(active_button: String):
	var buttons = ["PlaceZoneButton", "FillZoneButton", "RectZoneButton", "EraseZoneButton"]
	
	for button_name in buttons:
		var button = zone_tools_container.get_node_or_null(button_name)
		if button:
			button.button_pressed = (button_name == active_button)

# Handler for toggling zone visualization
func _on_visualize_zones_toggled(toggled: bool):
	var visualize_button = zone_tools_container.get_node_or_null("VisualizeButton")
	
	if visualize_button:
		if zone_manager:
			# Get current visualization mode
			var mode = settings_manager.get_setting("atmosphere/zone_overlay_mode", "type")
			var mode_enum = 0 # Default to type
			
			match mode:
				"type": mode_enum = 0
				"pressure": mode_enum = 1
				"temperature": mode_enum = 2
				"atmosphere": mode_enum = 3
				"gravity": mode_enum = 4
			
			zone_manager.set_visualization_mode(mode_enum if toggled else -1)
			
			# Update setting
			settings_manager.set_setting("atmosphere/show_zone_overlay", toggled)

# Handler for toggling atmosphere simulation
func _on_simulate_atmosphere_toggled(toggled: bool):
	var simulate_button = zone_tools_container.get_node_or_null("SimulateButton")
	
	if simulate_button and zone_manager:
		if toggled:
			zone_manager.start_atmosphere_simulation()
		else:
			zone_manager.stop_atmosphere_simulation()
		
		# Update setting
		settings_manager.set_setting("atmosphere/auto_simulate", toggled)

# Handler for lighting tool selection
func _on_place_light_tool_selected():
	if lighting_system:
		if editor_ref and editor_ref.has_method("set_current_tool"):
			editor_ref.set_current_tool("place_light")
		_update_light_tool_buttons("PlaceLightButton")

func _on_erase_light_tool_selected():
	if lighting_system:
		if editor_ref and editor_ref.has_method("set_current_tool"):
			editor_ref.set_current_tool("erase_light")
		_update_light_tool_buttons("EraseLightButton")

# Helper to update light tool button states
func _update_light_tool_buttons(active_button: String):
	var buttons = ["PlaceLightButton", "EraseLightButton"]
	
	for button_name in buttons:
		var button = lighting_tools_container.get_node_or_null(button_name)
		if button:
			button.button_pressed = (button_name == active_button)

# Handler for toggling light preview
func _on_light_preview_toggled(toggled: bool):
	var preview_button = lighting_tools_container.get_node_or_null("LightPreviewButton")
	
	if preview_button and lighting_system:
		lighting_system.show_preview(toggled)
		
		# Update setting
		settings_manager.set_setting("lighting/show_lights_preview", toggled)

# Handler for changing ambient light
func _on_ambient_light_changed(value: float):
	if lighting_system:
		lighting_system.set_ambient_light(value)
		
		# Update setting
		settings_manager.set_setting("lighting/ambient_light_level", value)

# Handler for preview mode
func _on_start_preview():
	if preview_mode:
		preview_mode.start_preview()

func _on_stop_preview():
	if preview_mode:
		preview_mode.stop_preview()

# Handler for map validation
func _on_validate_map():
	if editor_ref and "map_validator" in editor_ref:
		var validator = editor_ref.map_validator
		var issues = validator.validate_map()
		
		# Show validation report
		_show_validation_report(validator.get_validation_report())

# Show validation report dialog
func _show_validation_report(report: String):
	# Create dialog if doesn't exist
	if not editor_ref.has_node("UI/Dialogs/ValidationReportDialog"):
		var dialog = Window.new()
		dialog.name = "ValidationReportDialog"
		dialog.title = "Map Validation Report"
		dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
		dialog.size = Vector2i(600, 500)
		dialog.visible = false
		dialog.unresizable = false
		
		editor_ref.get_node("UI/Dialogs").add_child(dialog)
		
		# Add content
		var vbox = VBoxContainer.new()
		vbox.anchors_preset = Control.PRESET_FULL_RECT
		vbox.offset_left = 10
		vbox.offset_top = 10
		vbox.offset_right = -10
		vbox.offset_bottom = -10
		dialog.add_child(vbox)
		
		# Add report text
		var report_text = TextEdit.new()
		report_text.name = "ReportText"
		report_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
		report_text.editable = false
		vbox.add_child(report_text)
		
		# Add close button
		var close_button = Button.new()
		close_button.text = "Close"
		close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
		close_button.pressed.connect(Callable(self, "_on_validation_dialog_close"))
		vbox.add_child(close_button)
	
	# Set report text
	var report_text = editor_ref.get_node("UI/Dialogs/ValidationReportDialog/VBoxContainer/ReportText")
	report_text.text = report
	
	# Show dialog
	editor_ref.get_node("UI/Dialogs/ValidationReportDialog").visible = true

# Close validation report dialog
func _on_validation_dialog_close():
	if editor_ref.has_node("UI/Dialogs/ValidationReportDialog"):
		editor_ref.get_node("UI/Dialogs/ValidationReportDialog").visible = false

# Settings dialog handlers
func _on_settings_dialog_close():
	if settings_dialog:
		settings_dialog.visible = false

func _on_apply_settings():
	if settings_dialog:
		# Collect all settings
		_save_settings_from_dialog()
		
		# Apply settings immediately
		_apply_settings_to_editor()

func _on_ok_settings():
	if settings_dialog:
		# Apply settings
		_save_settings_from_dialog()
		_apply_settings_to_editor()
		
		# Close dialog
		settings_dialog.visible = false

func _on_reset_settings():
	if settings_manager:
		# Reset settings
		settings_manager.reset_to_default()
		
		# Close and reopen dialog to refresh UI
		if settings_dialog:
			settings_dialog.visible = false
			settings_dialog.visible = true

# Save settings from dialog controls
func _save_settings_from_dialog():
	if not settings_dialog or not settings_manager:
		return
	
	# Get all tab containers
	var tabs = settings_dialog.get_node("VBoxContainer/TabContainer")
	
	# Process each tab
	for tab_idx in range(tabs.get_tab_count()):
		var tab = tabs.get_tab_control(tab_idx)
		
		# Process all controls in tab
		_process_settings_controls(tab)
	
	# Save settings to file
	settings_manager.save_settings()

# Apply settings to editor
func _apply_settings_to_editor():
	if not editor_ref or not settings_manager:
		return
	
	# Apply grid settings
	if "grid" in editor_ref:
		editor_ref.grid.toggle_grid_visibility(settings_manager.get_setting("display/show_grid", true))
		editor_ref.grid.grid_color = settings_manager.get_setting("display/grid_color", Color(0.5, 0.5, 0.5, 0.2))
		editor_ref.grid.major_grid_color = settings_manager.get_setting("display/grid_major_color", Color(0.5, 0.5, 0.5, 0.4))
		editor_ref.grid.show_major_lines = settings_manager.get_setting("display/grid_major_lines", true)
		editor_ref.grid.major_grid_interval = settings_manager.get_setting("display/grid_major_interval", 5)
		editor_ref.grid.show_cursor = settings_manager.get_setting("display/show_coordinates", true)
		editor_ref.grid.queue_redraw()
	
	# Apply layer transparency
	if editor_ref.floor_tilemap and editor_ref.wall_tilemap and editor_ref.objects_tilemap and editor_ref.zone_tilemap:
		var transparency = settings_manager.get_setting("editor/layer_transparency", 0.3)
		editor_ref.floor_tilemap.modulate.a = 1.0 if editor_ref.get_active_layer() == 0 else transparency
		editor_ref.wall_tilemap.modulate.a = 1.0 if editor_ref.get_active_layer() == 1 else transparency
		editor_ref.objects_tilemap.modulate.a = 1.0 if editor_ref.get_active_layer() == 2 else transparency
		editor_ref.zone_tilemap.modulate.a = 1.0 if editor_ref.get_active_layer() == 4 else transparency
	
	# Apply lighting settings
	if lighting_system:
		lighting_system.set_ambient_light(settings_manager.get_setting("lighting/ambient_light_level", 0.8))
		lighting_system.show_preview(settings_manager.get_setting("lighting/show_lights_preview", false))
		
		# Update UI
		var ambient_slider = lighting_tools_container.get_node_or_null("AmbientSlider")
		if ambient_slider:
			ambient_slider.value = settings_manager.get_setting("lighting/ambient_light_level", 0.8)
		
		var preview_button = lighting_tools_container.get_node_or_null("LightPreviewButton")
		if preview_button:
			preview_button.button_pressed = settings_manager.get_setting("lighting/show_lights_preview", false)
	
	# Apply zone and atmosphere settings
	if zone_manager:
		var show_overlay = settings_manager.get_setting("atmosphere/show_zone_overlay", false)
		var mode = settings_manager.get_setting("atmosphere/zone_overlay_mode", "type")
		var mode_enum = 0
		
		match mode:
			"type": mode_enum = 0
			"pressure": mode_enum = 1
			"temperature": mode_enum = 2
			"atmosphere": mode_enum = 3
			"gravity": mode_enum = 4
		
		zone_manager.set_visualization_mode(mode_enum if show_overlay else -1)
		
		if settings_manager.get_setting("atmosphere/auto_simulate", false):
			zone_manager.start_atmosphere_simulation()
		else:
			zone_manager.stop_atmosphere_simulation()
		
		# Update UI
		var visualize_button = zone_tools_container.get_node_or_null("VisualizeButton")
		if visualize_button:
			visualize_button.button_pressed = show_overlay
		
		var simulate_button = zone_tools_container.get_node_or_null("SimulateButton")
		if simulate_button:
			simulate_button.button_pressed = settings_manager.get_setting("atmosphere/auto_simulate", false)
	
	# Apply preview settings
	if preview_mode:
		preview_mode.PLAYER_MOVE_SPEED = settings_manager.get_setting("preview/player_move_speed", 5.0)
	
	# Apply UI settings
	var sidebar_width = settings_manager.get_setting("ui/sidebar_width", 250)
	if editor_ref.has_node("UI/MainPanel/VBoxContainer/HSplitContainer"):
		editor_ref.get_node("UI/MainPanel/VBoxContainer/HSplitContainer").split_offset = sidebar_width
	
	var show_status_bar = settings_manager.get_setting("ui/show_status_bar", true)
	if editor_ref.has_node("UI/MainPanel/VBoxContainer/StatusBar"):
		editor_ref.get_node("UI/MainPanel/VBoxContainer/StatusBar").visible = show_status_bar

# Recursively process controls to find settings
func _process_settings_controls(parent: Control):
	for child in parent.get_children():
		# Check if control has setting path
		if child.has_meta("setting_path"):
			var path = child.get_meta("setting_path")
			var value = null
			
			# Get value based on control type
			if child is CheckBox:
				value = child.button_pressed
			elif child is SpinBox:
				value = child.value
			elif child is HSlider:
				value = child.value
			elif child is ColorPickerButton:
				value = child.color
			elif child is OptionButton:
				var id = child.get_selected_id()
				var text = child.get_item_text(child.selected)
				
				# Convert to appropriate value based on path
				match path:
					"map/map_color_scheme":
						match id:
							0: value = "default"
							1: value = "high_contrast"
							2: value = "minimal"
							3: value = "dark"
							4: value = "light"
					"tools/line_style":
						match id:
							0: value = "straight"
							1: value = "manhattan"
							2: value = "bresenham"
					"tools/multi_tile_mode":
						match id:
							0: value = "rectangle"
							1: value = "ellipse"
							2: value = "free_form"
					"atmosphere/zone_overlay_mode":
						match id:
							0: value = "type"
							1: value = "pressure"
							2: value = "temperature"
							3: value = "atmosphere"
							4: value = "gravity"
					"ui/theme":
						match id:
							0: value = "dark"
							1: value = "light"
							2: value = "classic"
					"ui/toolbar_position":
						match id:
							0: value = "top"
							1: value = "left"
							2: value = "right"
					_:
						value = id
			elif child is LineEdit:
				value = child.text
			
			# Save setting if we got a value
			if value != null:
				settings_manager.set_setting(path, value)
		
		# Process children recursively if it's a container
		if child is Container:
			_process_settings_controls(child)

# Handle directory browsing
func _on_browse_save_dir():
	# Would show a file dialog to select save directory
	if editor_ref.has_node("UI/Dialogs/SaveMapDialog"):
		var dialog = editor_ref.get_node("UI/Dialogs/SaveMapDialog")
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		dialog.title = "Select Default Save Directory"
		dialog.dialog_hide_on_ok = false
		dialog.file_selected.connect(Callable(self, "_on_save_dir_selected"), CONNECT_ONE_SHOT)
		dialog.visible = true

func _on_save_dir_selected(path: String):
	if settings_manager:
		settings_manager.set_setting("paths/last_save_directory", path)
		
		# Update dialog control
		var save_dir = settings_dialog.get_node_or_null("VBoxContainer/TabContainer/Paths/GridContainer/HBoxContainer/LineEdit")
		if save_dir:
			save_dir.text = path

func _on_browse_export_dir():
	# Would show a file dialog to select export directory
	if editor_ref.has_node("UI/Dialogs/ExportDialog"):
		var dialog = editor_ref.get_node("UI/Dialogs/ExportDialog")
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		dialog.title = "Select Default Export Directory"
		dialog.dialog_hide_on_ok = false
		dialog.file_selected.connect(Callable(self, "_on_export_dir_selected"), CONNECT_ONE_SHOT)
		dialog.visible = true

func _on_export_dir_selected(path: String):
	if settings_manager:
		settings_manager.set_setting("paths/last_export_directory", path)
		
		# Update dialog control
		var export_dir = settings_dialog.get_node_or_null("VBoxContainer/TabContainer/Paths/GridContainer/HBoxContainer2/LineEdit")
		if export_dir:
			export_dir.text = path

func _on_browse_assets_dir():
	# Would show a file dialog to select assets directory
	if editor_ref.has_node("UI/Dialogs/OpenMapDialog"):
		var dialog = editor_ref.get_node("UI/Dialogs/OpenMapDialog")
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		dialog.title = "Select Custom Assets Directory"
		dialog.dialog_hide_on_ok = false
		dialog.file_selected.connect(Callable(self, "_on_assets_dir_selected"), CONNECT_ONE_SHOT)
		dialog.visible = true

func _on_assets_dir_selected(path: String):
	if settings_manager:
		settings_manager.set_setting("paths/custom_assets_directory", path)
		
		# Update dialog control
		var assets_dir = settings_dialog.get_node_or_null("VBoxContainer/TabContainer/Paths/GridContainer/HBoxContainer3/LineEdit")
		if assets_dir:
			assets_dir.text = path

func _on_clear_recent_files():
	if settings_manager:
		settings_manager.clear_recent_files()
		
		# Update list in dialog
		var list = settings_dialog.get_node_or_null("VBoxContainer/TabContainer/Paths/GridContainer/VBoxContainer/ItemList")
		if list:
			list.clear()

# Handle view menu selections
func _on_view_menu_item_selected(id: int):
	match id:
		0: # Show Grid
			if editor_ref and "grid" in editor_ref:
				var show_grid = not settings_manager.get_setting("display/show_grid", true)
				settings_manager.set_setting("display/show_grid", show_grid)
				editor_ref.grid.toggle_grid_visibility(show_grid)
		1: # Snap to Grid
			var snap_to_grid = not settings_manager.get_setting("display/snap_to_grid", true)
			settings_manager.set_setting("display/snap_to_grid", snap_to_grid)
		2: # Reset View
			if editor_ref and editor_ref.has_node("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport/EditorCamera"):
				var camera = editor_ref.get_node("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport/EditorCamera")
				camera.reset_view()
		3: # Z-Level Up
			if editor_ref and editor_ref.has_method("set_z_level"):
				editor_ref.set_z_level(editor_ref.current_z_level + 1)
		4: # Z-Level Down
			if editor_ref and editor_ref.has_method("set_z_level"):
				editor_ref.set_z_level(editor_ref.current_z_level - 1)
		100:  # Zone Visualization
			if zone_manager:
				var visualize_button = zone_tools_container.get_node_or_null("VisualizeButton")
				if visualize_button:
					visualize_button.button_pressed = !visualize_button.button_pressed
					_on_visualize_zones_toggled(visualize_button.button_pressed)
		110:  # Lighting Preview
			if lighting_system:
				var preview_button = lighting_tools_container.get_node_or_null("LightPreviewButton")
				if preview_button:
					preview_button.button_pressed = !preview_button.button_pressed
					_on_light_preview_toggled(preview_button.button_pressed)
		111:  # Adjust Ambient Light
			# Show the settings dialog and navigate to the Lighting tab
			if settings_dialog:
				settings_dialog.visible = true
				var tabs = settings_dialog.get_node_or_null("VBoxContainer/TabContainer")
				if tabs:
					for i in range(tabs.get_tab_count()):
						if tabs.get_tab_title(i) == "Lighting":
							tabs.current_tab = i
							break

# Handle zone view menu selections
func _on_zone_view_menu_item_selected(id: int):
	if zone_manager:
		var mode = -1
		var mode_name = "type"
		
		match id:
			200:  # Zone Types
				mode = 0
				mode_name = "type"
			201:  # Pressure
				mode = 1
				mode_name = "pressure"
			202:  # Temperature
				mode = 2
				mode_name = "temperature"
			203:  # Atmosphere
				mode = 3
				mode_name = "atmosphere"
			204:  # Gravity
				mode = 4
				mode_name = "gravity"
		
		# Check if visualization is on
		var visualize_button = zone_tools_container.get_node_or_null("VisualizeButton")
		if visualize_button and visualize_button.button_pressed:
			zone_manager.set_visualization_mode(mode)
		
		# Update setting
		settings_manager.set_setting("atmosphere/zone_overlay_mode", mode_name)

# Handle tools menu selections
func _on_tools_menu_item_selected(id: int):
	match id:
		300:  # Validate Map
			_on_validate_map()
		301:  # Start Preview Mode
			_on_start_preview()
		302:  # Simulate Atmosphere
			if zone_manager:
				var simulate_button = zone_tools_container.get_node_or_null("SimulateButton")
				if simulate_button:
					simulate_button.button_pressed = !simulate_button.button_pressed
					_on_simulate_atmosphere_toggled(simulate_button.button_pressed)

# Handle settings menu selections
func _on_settings_menu_item_selected(id: int):
	match id:
		400:  # Editor Settings
			if settings_dialog:
				settings_dialog.visible = true
		401:  # Import Settings
			if settings_manager:
				# Show a file dialog
				if editor_ref.has_node("UI/Dialogs/OpenMapDialog"):
					var dialog = editor_ref.get_node("UI/Dialogs/OpenMapDialog")
					dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
					dialog.title = "Import Settings"
					dialog.dialog_hide_on_ok = false
					dialog.filters = PackedStringArray(["*.cfg ; Config Files"])
					dialog.file_selected.connect(Callable(self, "_on_import_settings_file_selected"), CONNECT_ONE_SHOT)
					dialog.visible = true
		402:  # Export Settings
			if settings_manager:
				# Show a file dialog
				if editor_ref.has_node("UI/Dialogs/SaveMapDialog"):
					var dialog = editor_ref.get_node("UI/Dialogs/SaveMapDialog")
					dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
					dialog.title = "Export Settings"
					dialog.dialog_hide_on_ok = false
					dialog.filters = PackedStringArray(["*.cfg ; Config Files"])
					dialog.file_selected.connect(Callable(self, "_on_export_settings_file_selected"), CONNECT_ONE_SHOT)
					dialog.visible = true
		403:  # Reset to Default
			if settings_manager:
				settings_manager.reset_to_default()

func _on_import_settings_file_selected(path: String):
	if settings_manager:
		settings_manager.import_settings(path)

func _on_export_settings_file_selected(path: String):
	if settings_manager:
		settings_manager.export_settings(path)

# Handle setting changed
func _on_setting_changed(path: String, value):
	# Apply setting immediately if needed
	match path:
		"display/show_grid":
			if editor_ref and "grid" in editor_ref:
				editor_ref.grid.toggle_grid_visibility(value)
		"display/grid_opacity":
			if editor_ref and "grid" in editor_ref:
				editor_ref.grid.grid_color.a = value
				editor_ref.grid.queue_redraw()
		"display/grid_major_lines":
			if editor_ref and "grid" in editor_ref:
				editor_ref.grid.show_major_lines = value
				editor_ref.grid.queue_redraw()
		"display/grid_major_interval":
			if editor_ref and "grid" in editor_ref:
				editor_ref.grid.major_grid_interval = value
				editor_ref.grid.queue_redraw()
		"display/grid_color":
			if editor_ref and "grid" in editor_ref:
				editor_ref.grid.grid_color = value
				editor_ref.grid.queue_redraw()
		"display/grid_major_color":
			if editor_ref and "grid" in editor_ref:
				editor_ref.grid.major_grid_color = value
				editor_ref.grid.queue_redraw()
		"display/show_coordinates":
			if editor_ref and "grid" in editor_ref:
				editor_ref.grid.show_cursor = value
				editor_ref.grid.queue_redraw()
		"editor/layer_transparency":
			if editor_ref and editor_ref.get_active_layer() != -1:
				# Update all layer transparencies
				editor_ref.floor_tilemap.modulate.a = 1.0 if editor_ref.get_active_layer() == 0 else value
				editor_ref.wall_tilemap.modulate.a = 1.0 if editor_ref.get_active_layer() == 1 else value
				editor_ref.objects_tilemap.modulate.a = 1.0 if editor_ref.get_active_layer() == 2 else value
				editor_ref.zone_tilemap.modulate.a = 1.0 if editor_ref.get_active_layer() == 4 else value
		"lighting/ambient_light_level":
			if lighting_system:
				lighting_system.set_ambient_light(value)
				
				# Update slider if exists
				var slider = lighting_tools_container.get_node_or_null("AmbientSlider")
				if slider:
					slider.value = value
		"lighting/show_lights_preview":
			if lighting_system:
				lighting_system.show_preview(value)
				
				# Update button if exists
				var button = lighting_tools_container.get_node_or_null("LightPreviewButton")
				if button:
					button.button_pressed = value
		"atmosphere/show_zone_overlay":
			if zone_manager:
				# Get current visualization mode
				var mode = settings_manager.get_setting("atmosphere/zone_overlay_mode", "type")
				var mode_enum = 0 # Default to type
				
				match mode:
					"type": mode_enum = 0
					"pressure": mode_enum = 1
					"temperature": mode_enum = 2
					"atmosphere": mode_enum = 3
					"gravity": mode_enum = 4
				
				zone_manager.set_visualization_mode(mode_enum if value else -1)
				
				# Update button if exists
				var button = zone_tools_container.get_node_or_null("VisualizeButton")
				if button:
					button.button_pressed = value
		"atmosphere/auto_simulate":
			if zone_manager:
				if value:
					zone_manager.start_atmosphere_simulation()
				else:
					zone_manager.stop_atmosphere_simulation()
				
				# Update button if exists
				var button = zone_tools_container.get_node_or_null("SimulateButton")
				if button:
					button.button_pressed = value
		"ui/sidebar_width":
			if editor_ref and editor_ref.has_node("UI/MainPanel/VBoxContainer/HSplitContainer"):
				editor_ref.get_node("UI/MainPanel/VBoxContainer/HSplitContainer").split_offset = value
		"ui/show_status_bar":
			if editor_ref and editor_ref.has_node("UI/MainPanel/VBoxContainer/StatusBar"):
				editor_ref.get_node("UI/MainPanel/VBoxContainer/StatusBar").visible = value
		"preview/player_move_speed":
			if preview_mode:
				preview_mode.PLAYER_MOVE_SPEED = value

# Handle all settings loaded
func _on_settings_loaded():
	# Apply all relevant settings
	_apply_settings_to_editor()
