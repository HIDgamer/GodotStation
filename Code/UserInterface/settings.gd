extends CanvasLayer

# Configuration management
const CONFIG_FILE_PATH = "user://settings.cfg"

# Audio bus configuration
const MASTER_BUS = 0
const MUSIC_BUS = 1
const SFX_BUS = 2

# Display resolution options
var available_resolutions = [
	Vector2i(1280, 720),    # HD
	Vector2i(1366, 768),    # Laptop standard
	Vector2i(1600, 900),    # HD+
	Vector2i(1680, 1050),   # WSXGA+
	Vector2i(1920, 1080),   # Full HD
	Vector2i(2560, 1440),   # QHD
	Vector2i(3840, 2160)    # 4K UHD
]

# Graphics quality configuration
var shadow_quality_levels = ["Disabled", "Low", "Medium", "High"]
var antialiasing_levels = ["None", "MSAA 2x", "MSAA 4x", "MSAA 8x", "FXAA"]
var texture_quality_levels = ["Low", "Medium", "High"]

# Input mapping system
var input_actions_list = []
var control_buttons_map = {}
var is_remapping_input = false
var current_remapping_action = ""
var should_ignore_next_input = false

# System references
var config_file = ConfigFile.new()
var optimization_manager = null

# Animation constants
const FADE_DURATION = 0.5
const BUTTON_FEEDBACK_DURATION = 1.0

func _ready():
	print("Settings: Initializing system configuration interface")
	
	initialize_settings_interface()
	setup_ui_connections()
	configure_graphics_options()
	setup_audio_system()
	configure_input_mapping()
	await initialize_optimization_system()
	load_configuration_from_file()
	setup_interface_animations()
	
	print("Settings: System configuration interface ready")

func initialize_settings_interface():
	"""Initialize the settings interface with proper process mode and animations"""
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Initial fade-in animation
	$SettingsUI.modulate.a = 0
	var tween = create_tween()
	tween.tween_property($SettingsUI, "modulate:a", 1.0, FADE_DURATION)
	
	# Check if we're in a paused game context
	detect_pause_context()

func setup_ui_connections():
	"""Connect all UI element signals to their handlers"""
	# Main navigation buttons
	$SettingsUI/BackButton.pressed.connect(_on_return_button_pressed)
	$SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/ActionButtons/SaveButton.pressed.connect(_on_save_configuration_pressed)
	$SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/ActionButtons/ResetButton.pressed.connect(_on_reset_defaults_pressed)
	$SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/ActionButtons/ResetControlsButton.pressed.connect(_on_reset_controls_pressed)
	
	# Tab change detection
	var tab_container = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer
	tab_container.tab_changed.connect(_on_configuration_tab_changed)

func configure_graphics_options():
	"""Setup graphics configuration dropdowns and options"""
	setup_resolution_options()
	setup_graphics_quality_options()
	connect_graphics_signals()

func setup_resolution_options():
	"""Configure available display resolutions"""
	var resolution_dropdown = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/ResolutionSection/ResolutionOption
	resolution_dropdown.clear()
	
	for i in range(available_resolutions.size()):
		var resolution = available_resolutions[i]
		resolution_dropdown.add_item(str(resolution.x) + "x" + str(resolution.y), i)
	
	print("Settings: Configured ", available_resolutions.size(), " resolution options")

func setup_graphics_quality_options():
	"""Configure graphics quality dropdown menus"""
	# Shadow quality options
	var shadow_dropdown = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/ShadowSection/ShadowOption
	shadow_dropdown.clear()
	for i in range(shadow_quality_levels.size()):
		shadow_dropdown.add_item(shadow_quality_levels[i], i)
	
	# Anti-aliasing options
	var aa_dropdown = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/AntiAliasingSection/AntiAliasingOption
	aa_dropdown.clear()
	for i in range(antialiasing_levels.size()):
		aa_dropdown.add_item(antialiasing_levels[i], i)
	
	# Texture quality options
	var texture_dropdown = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/TextureSection/TextureOption
	texture_dropdown.clear()
	for i in range(texture_quality_levels.size()):
		texture_dropdown.add_item(texture_quality_levels[i], i)

func connect_graphics_signals():
	"""Connect graphics control signals to their handlers"""
	# Resolution control
	var resolution_dropdown = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/ResolutionSection/ResolutionOption
	resolution_dropdown.item_selected.connect(_on_resolution_changed)
	
	# Display mode controls
	var fullscreen_toggle = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/DisplayOptions/FullscreenCheck
	fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	
	var vsync_toggle = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/DisplayOptions/VsyncCheck
	vsync_toggle.toggled.connect(_on_vsync_toggled)
	
	# Quality controls
	var shadow_dropdown = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/ShadowSection/ShadowOption
	shadow_dropdown.item_selected.connect(_on_shadow_quality_changed)
	
	var aa_dropdown = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/AntiAliasingSection/AntiAliasingOption
	aa_dropdown.item_selected.connect(_on_antialiasing_changed)
	
	var texture_dropdown = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/TextureSection/TextureOption
	texture_dropdown.item_selected.connect(_on_texture_quality_changed)

func setup_audio_system():
	"""Configure audio system controls and connections"""
	var master_slider = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/AUDIO/MasterSection/MasterVolumeSlider
	var music_slider = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/AUDIO/MusicSection/MusicVolumeSlider
	var sfx_slider = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/AUDIO/SFXSection/SFXVolumeSlider
	
	var master_value = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/AUDIO/MasterSection/MasterVolumeValue
	var music_value = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/AUDIO/MusicSection/MusicVolumeValue
	var sfx_value = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/AUDIO/SFXSection/SFXVolumeValue
	
	# Connect audio slider signals
	master_slider.value_changed.connect(func(value): 
		AudioServer.set_bus_volume_db(MASTER_BUS, value)
		master_value.text = str(int(value)) + " dB"
	)
	
	music_slider.value_changed.connect(func(value): 
		AudioServer.set_bus_volume_db(MUSIC_BUS, value)
		music_value.text = str(int(value)) + " dB"
	)
	
	sfx_slider.value_changed.connect(func(value): 
		AudioServer.set_bus_volume_db(SFX_BUS, value)
		sfx_value.text = str(int(value)) + " dB"
	)

func configure_input_mapping():
	"""Setup dynamic input mapping interface"""
	refresh_input_mapping_display()

func refresh_input_mapping_display():
	"""Refresh the input mapping interface with current bindings"""
	var controls_container = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/CONTROLS/ScrollContainer/ControlsList
	
	# Clear existing controls
	for child in controls_container.get_children():
		child.queue_free()
	
	input_actions_list.clear()
	control_buttons_map.clear()
	
	# Get all input actions and filter system ones
	var all_actions = InputMap.get_actions()
	all_actions.sort()
	
	var filtered_actions = []
	for action in all_actions:
		var action_str = action as String
		if not action_str.begins_with("ui_"):
			filtered_actions.append(action)
	
	input_actions_list = filtered_actions
	
	# Categorize actions for better organization
	var action_categories = categorize_input_actions(input_actions_list)
	
	# Create UI for each category
	for category_name in action_categories.keys():
		if action_categories[category_name].size() > 0:
			create_input_category_section(category_name, action_categories[category_name], controls_container)

func categorize_input_actions(actions: Array) -> Dictionary:
	"""Organize input actions into logical categories"""
	var categories = {
		"Movement": [],
		"Interaction": [],
		"Combat": [],
		"Interface": [],
		"Other": []
	}
	
	for action in actions:
		var action_str = action as String
		if action_str.contains("move") or action_str.contains("jump") or action_str.contains("sprint"):
			categories["Movement"].append(action)
		elif action_str.contains("interact") or action_str.contains("use") or action_str.contains("item"):
			categories["Interaction"].append(action)
		elif action_str.contains("attack") or action_str.contains("fire") or action_str.contains("reload"):
			categories["Combat"].append(action)
		elif action_str.contains("menu") or action_str.contains("pause") or action_str.contains("inventory"):
			categories["Interface"].append(action)
		else:
			categories["Other"].append(action)
	
	return categories

func create_input_category_section(category_name: String, actions: Array, container: Node):
	"""Create a section for a category of input actions"""
	# Category header
	var header_label = Label.new()
	header_label.text = category_name.to_upper()
	header_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1, 1))
	header_label.add_theme_font_size_override("font_size", 14)
	container.add_child(header_label)
	
	# Separator
	var separator = HSeparator.new()
	container.add_child(separator)
	
	# Action controls
	for action in actions:
		create_input_binding_control(action, container)
	
	# Spacing
	var spacer = Control.new()
	spacer.custom_minimum_size.y = 15
	container.add_child(spacer)

func create_input_binding_control(action: String, container: Node):
	"""Create a control for binding an input action"""
	var control_container = HBoxContainer.new()
	
	# Action label
	var action_label = Label.new()
	action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_label.text = action.capitalize().replace("_", " ")
	action_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1, 1))
	control_container.add_child(action_label)
	
	# Key binding button
	var binding_button = Button.new()
	binding_button.custom_minimum_size.x = 150
	update_binding_button_text(binding_button, action)
	binding_button.pressed.connect(_on_input_binding_requested.bind(action, binding_button))
	
	control_buttons_map[action] = binding_button
	control_container.add_child(binding_button)
	
	container.add_child(control_container)

func update_binding_button_text(button: Button, action: String):
	"""Update button text to show current key binding"""
	var action_events = InputMap.action_get_events(action)
	
	if action_events.size() > 0:
		var event = action_events[0]
		if event is InputEventKey:
			button.text = OS.get_keycode_string(event.keycode)
		elif event is InputEventMouseButton:
			button.text = "Mouse " + str(event.button_index)
		elif event is InputEventJoypadButton:
			button.text = "Gamepad " + str(event.button_index)
		else:
			button.text = "Unknown"
	else:
		button.text = "Unbound"

func initialize_optimization_system():
	"""Initialize the optimization system integration"""
	await get_tree().process_frame
	optimization_manager = get_node_or_null("/root/OptimizationManager")
	
	if optimization_manager:
		print("Settings: Optimization system integration active")
	else:
		print("Settings: Optimization system not available")

func setup_interface_animations():
	"""Setup interface animations and visual feedback"""
	# Performance monitor toggle
	var fps_toggle = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/ADVANCED/ScrollContainer/AdvancedOptionsContainer/PerformanceOptions/ShowFPSCheck
	fps_toggle.toggled.connect(_on_performance_monitor_toggled)

func detect_pause_context():
	"""Detect if we're in a paused game context"""
	var is_paused_context = get_tree().paused
	
	if not is_paused_context:
		var parent = get_parent()
		while parent:
			if "pause" in parent.name.to_lower():
				is_paused_context = true
				print("Settings: Detected pause menu context")
				break
			parent = parent.get_parent()
	
	if not is_paused_context:
		get_tree().paused = false
		print("Settings: Operating in main menu context")

func _on_configuration_tab_changed(tab_index: int):
	"""Handle configuration tab changes"""
	var tab_container = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer
	var tab_name = tab_container.get_tab_title(tab_index)
	print("Settings: Switched to configuration tab: ", tab_name)
	
	if tab_name == "CONTROLS":
		refresh_input_mapping_display()

func _on_return_button_pressed():
	"""Handle return to previous interface"""
	print("Settings: Returning to previous interface")
	
	save_configuration_to_file()
	
	if optimization_manager:
		optimization_manager.save_settings()
	
	animate_interface_exit()

func animate_interface_exit():
	"""Animate interface exit and handle navigation"""
	var tween = create_tween()
	tween.tween_property($SettingsUI, "modulate:a", 0.0, 0.3)
	
	tween.finished.connect(handle_navigation_return)

func handle_navigation_return():
	"""Handle navigation back to previous interface"""
	var game_manager = get_node_or_null("/root/GameManager")
	
	if game_manager and game_manager.has_method("return_from_settings"):
		game_manager.return_from_settings()
	else:
		determine_return_destination()

func determine_return_destination():
	"""Determine where to navigate back to"""
	if get_tree().paused:
		var pause_menu = find_pause_menu_interface()
		if pause_menu:
			pause_menu.visible = true
		else:
			get_tree().paused = false
		queue_free()
		return
	
	# Navigate back to main menu as fallback
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("show_main_menu"):
		queue_free()
		game_manager.show_main_menu()
	else:
		queue_free()
		get_tree().change_scene_to_file("res://Scenes/UI/Menus/Main_menu.tscn")

func find_pause_menu_interface():
	"""Locate the pause menu interface if it exists"""
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		var pause_menu = game_manager.get_node_or_null("pause_menu")
		if pause_menu:
			return pause_menu
	
	var pause_menus = get_tree().get_nodes_in_group("pause_menu")
	if pause_menus.size() > 0:
		return pause_menus[0]
	
	return null

func _on_save_configuration_pressed():
	"""Handle configuration save request"""
	save_configuration_to_file()
	
	if optimization_manager:
		optimization_manager.save_settings()
	
	show_action_feedback($SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/ActionButtons/SaveButton, "CONFIGURATION SAVED")

func _on_reset_defaults_pressed():
	"""Handle reset to default configuration"""
	apply_default_configuration()
	
	if optimization_manager:
		var recommended_quality = optimization_manager.estimate_system_capabilities()
		optimization_manager.apply_quality_preset(recommended_quality)
	
	show_action_feedback($SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/ActionButtons/ResetButton, "DEFAULTS RESTORED")

func _on_reset_controls_pressed():
	"""Handle input controls reset"""
	reset_input_bindings()
	show_action_feedback($SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/ActionButtons/ResetControlsButton, "CONTROLS RESET")

func show_action_feedback(button: Button, message: String):
	"""Show visual feedback for user actions"""
	var original_text = button.text
	button.text = message
	
	await get_tree().create_timer(BUTTON_FEEDBACK_DURATION).timeout
	button.text = original_text

# Graphics event handlers
func _on_resolution_changed(index: int):
	apply_resolution_setting(index)

func _on_fullscreen_toggled(enabled: bool):
	apply_fullscreen_setting(enabled)

func _on_vsync_toggled(enabled: bool):
	apply_vsync_setting(enabled)

func _on_shadow_quality_changed(index: int):
	apply_shadow_quality_setting(index)

func _on_antialiasing_changed(index: int):
	apply_antialiasing_setting(index)

func _on_texture_quality_changed(index: int):
	apply_texture_quality_setting(index)

func _on_performance_monitor_toggled(enabled: bool):
	toggle_performance_monitor(enabled)

func _on_input_binding_requested(action: String, button: Button):
	"""Handle input binding change requests"""
	if is_remapping_input:
		return
	
	is_remapping_input = true
	current_remapping_action = action
	button.text = "Press any key..."
	
	should_ignore_next_input = true
	get_tree().create_timer(0.1).timeout.connect(func(): should_ignore_next_input = false)

func _input(event):
	"""Handle input events for key remapping"""
	if is_remapping_input and not should_ignore_next_input:
		if event is InputEventKey or event is InputEventMouseButton:
			if event is InputEventKey and event.keycode == KEY_ESCAPE:
				cancel_input_remapping()
			else:
				apply_input_remapping(event)
			
			get_viewport().set_input_as_handled()

func cancel_input_remapping():
	"""Cancel the current input remapping operation"""
	is_remapping_input = false
	update_binding_button_text(control_buttons_map[current_remapping_action], current_remapping_action)

func apply_input_remapping(event):
	"""Apply a new input mapping"""
	InputMap.action_erase_events(current_remapping_action)
	InputMap.action_add_event(current_remapping_action, event)
	
	update_binding_button_text(control_buttons_map[current_remapping_action], current_remapping_action)
	save_input_mapping(current_remapping_action, event)
	
	is_remapping_input = false

# Graphics application functions
func apply_resolution_setting(index: int):
	if index >= 0 and index < available_resolutions.size():
		var current_mode = DisplayServer.window_get_mode()
		if current_mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_size(available_resolutions[index])
			center_window()

func center_window():
	var screen_size = DisplayServer.screen_get_size()
	var window_size = DisplayServer.window_get_size()
	DisplayServer.window_set_position(Vector2i(
		(screen_size.x - window_size.x) / 2, 
		(screen_size.y - window_size.y) / 2
	))

func apply_fullscreen_setting(enabled: bool):
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var resolution_dropdown = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/ResolutionSection/ResolutionOption
		apply_resolution_setting(resolution_dropdown.selected)

func apply_vsync_setting(enabled: bool):
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED
	)

func apply_shadow_quality_setting(quality_index: int):
	if optimization_manager:
		optimization_manager.set_setting("shadow_quality", quality_index)
	else:
		print("Settings: Shadow quality set to ", shadow_quality_levels[quality_index])

func apply_antialiasing_setting(aa_index: int):
	var viewport = get_viewport()
	if viewport:
		match aa_index:
			0: # None
				viewport.set_msaa_3d(Viewport.MSAA_DISABLED)
				viewport.set_screen_space_aa(Viewport.SCREEN_SPACE_AA_DISABLED)
			1: # MSAA 2x
				viewport.set_msaa_3d(Viewport.MSAA_2X)
				viewport.set_screen_space_aa(Viewport.SCREEN_SPACE_AA_DISABLED)
			2: # MSAA 4x
				viewport.set_msaa_3d(Viewport.MSAA_4X)
				viewport.set_screen_space_aa(Viewport.SCREEN_SPACE_AA_DISABLED)
			3: # MSAA 8x
				viewport.set_msaa_3d(Viewport.MSAA_8X)
				viewport.set_screen_space_aa(Viewport.SCREEN_SPACE_AA_DISABLED)
			4: # FXAA
				viewport.set_msaa_3d(Viewport.MSAA_DISABLED)
				viewport.set_screen_space_aa(Viewport.SCREEN_SPACE_AA_FXAA)

func apply_texture_quality_setting(quality_index: int):
	match quality_index:
		0: # Low
			ProjectSettings.set_setting("rendering/textures/default_filters/texture_mipmap_bias", 1.0)
			ProjectSettings.set_setting("rendering/textures/default_filters/anisotropic_filtering_level", 1)
		1: # Medium
			ProjectSettings.set_setting("rendering/textures/default_filters/texture_mipmap_bias", 0.0)
			ProjectSettings.set_setting("rendering/textures/default_filters/anisotropic_filtering_level", 4)
		2: # High
			ProjectSettings.set_setting("rendering/textures/default_filters/texture_mipmap_bias", -0.5)
			ProjectSettings.set_setting("rendering/textures/default_filters/anisotropic_filtering_level", 16)

func toggle_performance_monitor(enabled: bool):
	config_file.set_value("advanced", "show_fps", enabled)
	
	if enabled:
		var performance_monitor = get_node_or_null("/root/PerformanceMonitor")
		if not performance_monitor:
			var perf_scene = load("res://Scenes/UI/Ingame/preformance_monitor.tscn")
			if perf_scene:
				performance_monitor = perf_scene.instantiate()
				performance_monitor.name = "PerformanceMonitor"
				get_tree().root.add_child(performance_monitor)
	else:
		var performance_monitor = get_node_or_null("/root/PerformanceMonitor")
		if performance_monitor:
			performance_monitor.visible = false

# Configuration management
func save_configuration_to_file():
	"""Save current configuration to file"""
	save_graphics_configuration()
	save_audio_configuration()
	save_advanced_configuration()
	
	var error = config_file.save(CONFIG_FILE_PATH)
	if error != OK:
		print("Settings: Configuration save failed. Error: ", error)
	else:
		print("Settings: Configuration saved successfully")

func load_configuration_from_file():
	"""Load configuration from file"""
	var error = config_file.load(CONFIG_FILE_PATH)
	if error != OK:
		print("Settings: No configuration file found, using defaults")
		apply_default_configuration()
		return
	
	load_graphics_configuration()
	load_audio_configuration()
	load_advanced_configuration()
	load_input_mappings()

func save_graphics_configuration():
	var resolution_dropdown = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/ResolutionSection/ResolutionOption
	var fullscreen_toggle = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/DisplayOptions/FullscreenCheck
	var vsync_toggle = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/DisplayOptions/VsyncCheck
	var shadow_dropdown = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/ShadowSection/ShadowOption
	var aa_dropdown = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/AntiAliasingSection/AntiAliasingOption
	var texture_dropdown = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/TextureSection/TextureOption
	
	config_file.set_value("graphics", "resolution_index", resolution_dropdown.selected)
	config_file.set_value("graphics", "fullscreen", fullscreen_toggle.button_pressed)
	config_file.set_value("graphics", "vsync", vsync_toggle.button_pressed)
	config_file.set_value("graphics", "shadow_quality", shadow_dropdown.selected)
	config_file.set_value("graphics", "antialiasing", aa_dropdown.selected)
	config_file.set_value("graphics", "texture_quality", texture_dropdown.selected)

func save_audio_configuration():
	var master_slider = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/AUDIO/MasterSection/MasterVolumeSlider
	var music_slider = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/AUDIO/MusicSection/MusicVolumeSlider
	var sfx_slider = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/AUDIO/SFXSection/SFXVolumeSlider
	
	config_file.set_value("audio", "master_volume", master_slider.value)
	config_file.set_value("audio", "music_volume", music_slider.value)
	config_file.set_value("audio", "sfx_volume", sfx_slider.value)

func save_advanced_configuration():
	var fps_toggle = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/ADVANCED/ScrollContainer/AdvancedOptionsContainer/PerformanceOptions/ShowFPSCheck
	config_file.set_value("advanced", "show_fps", fps_toggle.button_pressed)

func load_graphics_configuration():
	var resolution_dropdown = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/ResolutionSection/ResolutionOption
	var fullscreen_toggle = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/DisplayOptions/FullscreenCheck
	var vsync_toggle = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/DisplayOptions/VsyncCheck
	var shadow_dropdown = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/ShadowSection/ShadowOption
	var aa_dropdown = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/AntiAliasingSection/AntiAliasingOption
	var texture_dropdown = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/TextureSection/TextureOption
	
	resolution_dropdown.selected = config_file.get_value("graphics", "resolution_index", 4)
	fullscreen_toggle.button_pressed = config_file.get_value("graphics", "fullscreen", false)
	vsync_toggle.button_pressed = config_file.get_value("graphics", "vsync", true)
	shadow_dropdown.selected = config_file.get_value("graphics", "shadow_quality", 2)
	aa_dropdown.selected = config_file.get_value("graphics", "antialiasing", 1)
	texture_dropdown.selected = config_file.get_value("graphics", "texture_quality", 1)
	
	apply_all_graphics_settings()

func load_audio_configuration():
	var master_slider = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/AUDIO/MasterSection/MasterVolumeSlider
	var music_slider = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/AUDIO/MusicSection/MusicVolumeSlider
	var sfx_slider = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/AUDIO/SFXSection/SFXVolumeSlider
	
	master_slider.value = config_file.get_value("audio", "master_volume", -10.0)
	music_slider.value = config_file.get_value("audio", "music_volume", -15.0)
	sfx_slider.value = config_file.get_value("audio", "sfx_volume", -10.0)
	
	apply_all_audio_settings()

func load_advanced_configuration():
	var fps_toggle = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/ADVANCED/ScrollContainer/AdvancedOptionsContainer/PerformanceOptions/ShowFPSCheck
	fps_toggle.button_pressed = config_file.get_value("advanced", "show_fps", false)
	
	if fps_toggle.button_pressed:
		toggle_performance_monitor(true)

func apply_default_configuration():
	"""Apply default configuration values"""
	# Set default UI values
	var resolution_dropdown = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/ResolutionSection/ResolutionOption
	resolution_dropdown.selected = 4  # 1920x1080
	
	var fullscreen_toggle = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/DisplayOptions/FullscreenCheck
	fullscreen_toggle.button_pressed = false
	
	var vsync_toggle = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/DisplayOptions/VsyncCheck
	vsync_toggle.button_pressed = true
	
	# Apply the settings
	apply_all_graphics_settings()
	apply_all_audio_settings()
	reset_input_bindings()

func apply_all_graphics_settings():
	var resolution_dropdown = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/ResolutionSection/ResolutionOption
	var fullscreen_toggle = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/DisplayOptions/FullscreenCheck
	var vsync_toggle = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/DisplayOptions/VsyncCheck
	var shadow_dropdown = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/ShadowSection/ShadowOption
	var aa_dropdown = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/AntiAliasingSection/AntiAliasingOption
	var texture_dropdown = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/GRAPHICS/ScrollContainer/OptionsContainer/TextureSection/TextureOption
	
	apply_vsync_setting(vsync_toggle.button_pressed)
	apply_fullscreen_setting(fullscreen_toggle.button_pressed)
	apply_shadow_quality_setting(shadow_dropdown.selected)
	apply_antialiasing_setting(aa_dropdown.selected)
	apply_texture_quality_setting(texture_dropdown.selected)

func apply_all_audio_settings():
	var master_slider = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/AUDIO/MasterSection/MasterVolumeSlider
	var music_slider = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/AUDIO/MusicSection/MusicVolumeSlider
	var sfx_slider = $SettingsUI/CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/AUDIO/SFXSection/SFXVolumeSlider
	
	AudioServer.set_bus_volume_db(MASTER_BUS, master_slider.value)
	AudioServer.set_bus_volume_db(MUSIC_BUS, music_slider.value)
	AudioServer.set_bus_volume_db(SFX_BUS, sfx_slider.value)

# Input mapping functions
func save_input_mapping(action: String, event):
	if event is InputEventKey:
		config_file.set_value("input", action, {
			"type": "key",
			"keycode": event.keycode,
			"physical_keycode": event.physical_keycode
		})
	elif event is InputEventMouseButton:
		config_file.set_value("input", action, {
			"type": "mouse",
			"button_index": event.button_index
		})

func load_input_mappings():
	if not config_file.has_section("input"):
		return
	
	var input_keys = config_file.get_section_keys("input")
	for action in input_keys:
		if not InputMap.has_action(action):
			continue
		
		var mapping = config_file.get_value("input", action)
		InputMap.action_erase_events(action)
		
		var event = null
		match mapping.get("type", ""):
			"key":
				event = InputEventKey.new()
				event.keycode = mapping.get("keycode", 0)
				event.physical_keycode = mapping.get("physical_keycode", 0)
			"mouse":
				event = InputEventMouseButton.new()
				event.button_index = mapping.get("button_index", 0)
		
		if event:
			InputMap.action_add_event(action, event)

func reset_input_bindings():
	"""Reset all input bindings to project defaults"""
	config_file.load(CONFIG_FILE_PATH)
	
	if config_file.has_section("input"):
		var input_keys = config_file.get_section_keys("input")
		for key in input_keys:
			config_file.erase_section_key("input", key)
	
	config_file.save(CONFIG_FILE_PATH)
	InputMap.load_from_project_settings()
	refresh_input_mapping_display()
