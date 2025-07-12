extends CanvasLayer

# Config file path
const CONFIG_FILE_PATH = "user://settings.cfg"

# Audio bus indices
const MASTER_BUS = 0
const MUSIC_BUS = 1
const SFX_BUS = 2

# Resolution options with more choices
var resolutions = [
	Vector2i(1280, 720),    # 720p
	Vector2i(1366, 768),    # Common laptop resolution
	Vector2i(1600, 900),    # 900p
	Vector2i(1680, 1050),   # 16:10 resolution
	Vector2i(1920, 1080),   # 1080p
	Vector2i(2560, 1440),   # 1440p
	Vector2i(3840, 2160)    # 4K
]

# Graphics quality options
var shadow_quality_options = ["Off", "Low", "Medium", "High"]
var antialiasing_options = ["None", "MSAA 2x", "MSAA 4x", "MSAA 8x", "FXAA"]
var texture_quality_options = ["Low", "Medium", "High"]

# Input mapping variables
var action_list = []
var button_list = {}
var currently_remapping = false
var action_to_remap = ""
var ignore_next_key = false

# Config file
var config = ConfigFile.new()

# Optimization manager reference
var optimization_manager = null

func _ready():
	print("Settings: Initializing")
	
	# Connect signals
	$SettingsUI/BackButton.pressed.connect(_on_back_button_pressed)
	$SettingsUI/PanelContainer/MarginContainer/ButtonContainer/SaveButton.pressed.connect(_on_save_button_pressed)
	$SettingsUI/PanelContainer/MarginContainer/ButtonContainer/ResetButton.pressed.connect(_on_reset_button_pressed)
	$SettingsUI/PanelContainer/MarginContainer/ButtonContainer/ResetControlsButton.pressed.connect(_on_reset_controls_button_pressed)
	
	# Get tab container
	var tabs = $SettingsUI/PanelContainer/MarginContainer/TabContainer
	
	# Connect tab change signal
	tabs.tab_changed.connect(_on_tab_changed)
	
	# Setup resolution dropdown
	var resolution_option = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/ResolutionSection/ResolutionOption
	resolution_option.clear()
	for i in range(resolutions.size()):
		var res = resolutions[i]
		resolution_option.add_item(str(res.x) + "x" + str(res.y), i)
	print("Settings: Added", resolutions.size(), "resolution options")
	
	# Find the optimization tab in the tab container
	var optimization_tab = tabs.get_node_or_null("Optimization")
	if optimization_tab == null:
		# Create Optimization tab if not found
		add_optimization_tab(tabs)
	
	# Setup graphics quality options
	setup_graphics_options()
	
	# Connect graphics settings signals
	setup_graphics_signals()
	
	# Connect audio settings signals
	setup_audio_signals()
	
	# Setup dynamic input mapping
	setup_input_mapping()
	
	# Find OptimizationManager
	await get_tree().process_frame
	optimization_manager = get_node_or_null("/root/OptimizationManager")
	if optimization_manager:
		print("Settings: Found OptimizationManager")
	else:
		print("Settings: OptimizationManager not found")
	
	# Add a fade-in animation when the settings screen loads
	$SettingsUI.modulate.a = 0
	var tween = create_tween()
	tween.tween_property($SettingsUI, "modulate:a", 1.0, 0.5)
	
	# Ensure proper process mode for paused state
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Check if we're in a pause menu context and handle accordingly
	check_pause_context()
	
	# Load settings from file
	load_settings()
	print("Settings: Initialization complete")

func add_optimization_tab(tabs):
	print("Settings: Adding Optimization tab")
	
	# Load optimization tab scene
	var opt_tab_scene = load("res://Scenes/UI/Ingame/optimization_tap.tscn")
	if opt_tab_scene:
		var opt_tab = opt_tab_scene.instantiate()
		
		# Add as a tab to the TabContainer
		tabs.add_child(opt_tab)
		
		# Set the tab title
		tabs.set_tab_title(tabs.get_tab_count() - 1, "Optimization")
		
		print("Settings: Optimization tab added successfully")
	else:
		print("Settings: Failed to load Optimization tab scene")

func setup_graphics_options():
	# Setup shadow quality dropdown
	var shadow_option = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/ShadowSection/ShadowOption
	shadow_option.clear()
	for i in range(shadow_quality_options.size()):
		shadow_option.add_item(shadow_quality_options[i], i)
	
	# Setup anti-aliasing dropdown
	var aa_option = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/AntiAliasingSection/AntiAliasingOption
	aa_option.clear()
	for i in range(antialiasing_options.size()):
		aa_option.add_item(antialiasing_options[i], i)
	
	# Setup texture quality dropdown
	var tex_option = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/TextureSection/TextureOption
	tex_option.clear()
	for i in range(texture_quality_options.size()):
		tex_option.add_item(texture_quality_options[i], i)

func setup_graphics_signals():
	# Resolution
	var resolution_option = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/ResolutionSection/ResolutionOption
	resolution_option.item_selected.connect(func(index): _set_resolution(index))
	
	# Fullscreen
	var fullscreen_check = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/DisplaySection/FullscreenCheck
	fullscreen_check.toggled.connect(func(button_pressed): 
		print("Settings: Fullscreen toggled to", button_pressed)
		if button_pressed:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			# Ensure resolution is reapplied when exiting fullscreen
			_set_resolution(resolution_option.selected)
	)
	
	# VSync
	var vsync_check = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/DisplaySection/VsyncCheck
	vsync_check.toggled.connect(func(button_pressed): 
		print("Settings: VSync toggled to", button_pressed)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if button_pressed else DisplayServer.VSYNC_DISABLED)
	)
	
	# Shadow quality
	var shadow_option = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/ShadowSection/ShadowOption
	shadow_option.item_selected.connect(func(index): apply_shadow_quality(index))
	
	# Anti-aliasing
	var aa_option = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/AntiAliasingSection/AntiAliasingOption
	aa_option.item_selected.connect(func(index): apply_antialiasing(index))
	
	# Texture quality
	var tex_option = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/TextureSection/TextureOption
	tex_option.item_selected.connect(func(index): apply_texture_quality(index))
	
	# Advanced settings - Show FPS
	var fps_check = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Advanced/ScrollContainer/AdvancedOptionsContainer/DebugSection/DebugContainer/ShowFPSCheck
	fps_check.toggled.connect(func(button_pressed): 
		# Update the setting
		config.set_value("advanced", "show_fps", button_pressed)
		
		# Find or create FPS display
		if button_pressed:
			var performance_monitor = get_node_or_null("/root/PerformanceMonitor")
			if not performance_monitor:
				# Try to create performance monitor
				var perf_scene = load("res://Scenes/UI/Ingame/preformance_monitor.tscn")
				if perf_scene:
					performance_monitor = perf_scene.instantiate()
					performance_monitor.name = "PerformanceMonitor"
					get_tree().root.add_child(performance_monitor)
		else:
			# Hide/remove FPS display if it exists
			var performance_monitor = get_node_or_null("/root/PerformanceMonitor")
			if performance_monitor:
				performance_monitor.visible = false
	)

func setup_audio_signals():
	# Connect audio sliders
	var master_slider = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Audio/MasterSection/MasterVolumeSlider
	var music_slider = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Audio/MusicSection/MusicVolumeSlider
	var sfx_slider = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Audio/SFXSection/SFXVolumeSlider
	
	# Connect value labels
	var master_value = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Audio/MasterSection/MasterVolumeValue
	var music_value = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Audio/MusicSection/MusicVolumeValue
	var sfx_value = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Audio/SFXSection/SFXVolumeValue
	
	master_slider.value_changed.connect(func(value): 
		AudioServer.set_bus_volume_db(MASTER_BUS, value)
		master_value.text = str(value) + " dB"
	)
	
	music_slider.value_changed.connect(func(value): 
		AudioServer.set_bus_volume_db(MUSIC_BUS, value)
		music_value.text = str(value) + " dB"
	)
	
	sfx_slider.value_changed.connect(func(value): 
		AudioServer.set_bus_volume_db(SFX_BUS, value)
		sfx_value.text = str(value) + " dB"
	)

func check_pause_context():
	var is_in_pause_context = get_tree().paused
	
	# Also check if any parent has 'pause' in the name
	if not is_in_pause_context:
		var parent = get_parent()
		while parent:
			if "pause" in parent.name.to_lower():
				is_in_pause_context = true
				print("Settings: Detected we're in pause menu context")
				break
			parent = parent.get_parent()
	
	if not is_in_pause_context:
		# We're in the main menu, make sure the game is not paused
		get_tree().paused = false
		print("Settings: Not in pause context, ensuring game is unpaused")

func _on_tab_changed(tab_idx):
	var tab_name = $SettingsUI/PanelContainer/MarginContainer/TabContainer.get_tab_title(tab_idx)
	print("Settings: Switched to tab:", tab_name)
	
	# If switching to Controls tab, refresh the mappings
	if tab_name == "Controls":
		setup_input_mapping()
	
	# If switching to Optimization tab
	if tab_name == "Optimization":
		# Optimization tab will auto-load settings from the OptimizationManager
		pass

func _on_back_button_pressed():
	print("Settings: Back button pressed")
	
	# Save settings before leaving
	save_settings()
	
	# If we have an OptimizationManager, save its settings too
	if optimization_manager:
		optimization_manager.save_settings()
	
	# Start fading out the UI
	var tween = create_tween()
	tween.tween_property($SettingsUI, "modulate:a", 0.0, 0.3)
	
	# Use GameManager to handle navigation back if available
	var game_manager = get_node_or_null("/root/GameManager")
	
	tween.finished.connect(func():
		if game_manager and game_manager.has_method("return_from_settings"):
			# Let GameManager handle the navigation
			game_manager.return_from_settings()
		else:
			# Fallback handling for when GameManager isn't available
			handle_navigation_back()
	)

func handle_navigation_back():
	print("Settings: Determining where to navigate back to")
	
	# CASE 1: If we're in a pause context, find and show the pause menu
	if get_tree().paused:
		print("Settings: We're in pause context")
		
		# Try to find the pause menu
		var pause_menu = find_pause_menu()
		if pause_menu:
			print("Settings: Found pause menu, making it visible")
			pause_menu.visible = true
		else:
			print("Settings: No pause menu found but we're paused. Unpausing.")
			get_tree().paused = false
		
		queue_free()
		return
	
	# CASE 2: Check if we're a child of another UI element
	var parent = get_parent()
	if parent and parent.has_method("_on_settings_closed"):
		print("Settings: We're a child of another UI, notifying parent")
		self.visible = false
		parent._on_settings_closed()
		return
	
	# CASE 3: Use GameManager if available
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		print("Settings: Using GameManager for navigation")
		
		# Simple approach - just go back to main menu
		# This is safer and prevents crashes
		if game_manager.has_method("show_main_menu"):
			queue_free()
			game_manager.show_main_menu()
			return
	
	# CASE 4: Fallback - go to main menu directly
	print("Settings: Using fallback - direct scene change to main menu")
	queue_free()
	get_tree().change_scene_to_file("res://Scenes/UI/Menus/Main_menu.tscn")

func find_pause_menu():
	# Try to find the pause menu in multiple ways
	
	# 1. Try GameManager's pause_menu child
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		var pause_menu = game_manager.get_node_or_null("pause_menu")
		if pause_menu:
			return pause_menu
	
	# 2. Try pause_menu group
	var pause_menus = get_tree().get_nodes_in_group("pause_menu")
	if pause_menus.size() > 0:
		return pause_menus[0]
	
	# 3. Try finding any node with "pause" in the name
	var root = get_tree().root
	for node in root.get_children():
		if "pause" in node.name.to_lower():
			return node
	
	return null

func _on_save_button_pressed():
	save_settings()
	
	# Save optimization settings if available
	if optimization_manager:
		optimization_manager.save_settings()
	
	# Show a brief confirmation message
	var save_button = $SettingsUI/PanelContainer/MarginContainer/ButtonContainer/SaveButton
	var original_text = save_button.text
	save_button.text = "Settings Saved!"
	
	# Reset button text after delay
	await get_tree().create_timer(1.0).timeout
	save_button.text = original_text

func _on_reset_button_pressed():
	# Reset to default settings
	apply_default_settings()
	
	# Reset optimization settings if available
	if optimization_manager:
		var recommended_tier = optimization_manager.estimate_system_capabilities()
		optimization_manager.apply_quality_preset(recommended_tier)
	
	# Show a brief confirmation message
	var reset_button = $SettingsUI/PanelContainer/MarginContainer/ButtonContainer/ResetButton
	var original_text = reset_button.text
	reset_button.text = "Settings Reset!"
	
	# Reset button text after delay
	await get_tree().create_timer(1.0).timeout
	reset_button.text = original_text

func _on_reset_controls_button_pressed():
	reset_input_mappings()
	
	# Show a brief confirmation message
	var reset_controls_button = $SettingsUI/PanelContainer/MarginContainer/ButtonContainer/ResetControlsButton
	var original_text = reset_controls_button.text
	reset_controls_button.text = "Controls Reset!"
	
	# Reset button text after delay
	await get_tree().create_timer(1.0).timeout
	reset_controls_button.text = original_text

func apply_default_settings():
	# Get UI references
	var resolution_option = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/ResolutionSection/ResolutionOption
	var fullscreen_check = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/DisplaySection/FullscreenCheck
	var vsync_check = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/DisplaySection/VsyncCheck
	var shadow_option = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/ShadowSection/ShadowOption
	var aa_option = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/AntiAliasingSection/AntiAliasingOption
	var tex_option = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/TextureSection/TextureOption
	
	var master_slider = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Audio/MasterSection/MasterVolumeSlider
	var music_slider = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Audio/MusicSection/MusicVolumeSlider
	var sfx_slider = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Audio/SFXSection/SFXVolumeSlider
	
	# Default values
	resolution_option.selected = 4  # 1920x1080
	fullscreen_check.button_pressed = false
	vsync_check.button_pressed = true
	shadow_option.selected = 2  # Medium
	aa_option.selected = 1  # MSAA 2x
	tex_option.selected = 1  # Medium
	
	master_slider.value = -10
	music_slider.value = -15
	sfx_slider.value = -10
	
	# Advanced tab settings
	var show_fps_check = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Advanced/ScrollContainer/AdvancedOptionsContainer/DebugSection/DebugContainer/ShowFPSCheck
	show_fps_check.button_pressed = false
	
	# Update labels
	$SettingsUI/PanelContainer/MarginContainer/TabContainer/Audio/MasterSection/MasterVolumeValue.text = "-10 dB"
	$SettingsUI/PanelContainer/MarginContainer/TabContainer/Audio/MusicSection/MusicVolumeValue.text = "-15 dB"
	$SettingsUI/PanelContainer/MarginContainer/TabContainer/Audio/SFXSection/SFXVolumeValue.text = "-10 dB"
	
	# Apply settings
	apply_graphics_settings()
	apply_audio_settings()
	
	# Reset input mappings
	reset_input_mappings()

func apply_graphics_settings():
	var resolution_option = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/ResolutionSection/ResolutionOption
	var fullscreen_check = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/DisplaySection/FullscreenCheck
	var vsync_check = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/DisplaySection/VsyncCheck
	var shadow_option = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/ShadowSection/ShadowOption
	var aa_option = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/AntiAliasingSection/AntiAliasingOption
	var tex_option = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/TextureSection/TextureOption
	
	# Apply VSSync
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_check.button_pressed else DisplayServer.VSYNC_DISABLED
	)
	
	# Apply window mode and resolution
	if fullscreen_check.button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_set_resolution(resolution_option.selected)
	
	# Apply other graphics settings
	apply_shadow_quality(shadow_option.selected)
	apply_antialiasing(aa_option.selected)
	apply_texture_quality(tex_option.selected)

func apply_audio_settings():
	var master_slider = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Audio/MasterSection/MasterVolumeSlider
	var music_slider = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Audio/MusicSection/MusicVolumeSlider
	var sfx_slider = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Audio/SFXSection/SFXVolumeSlider
	
	# Apply audio settings
	AudioServer.set_bus_volume_db(MASTER_BUS, master_slider.value)
	AudioServer.set_bus_volume_db(MUSIC_BUS, music_slider.value)
	AudioServer.set_bus_volume_db(SFX_BUS, sfx_slider.value)

func _set_resolution(index):
	if index >= 0 and index < resolutions.size():
		# Only change resolution if we're in windowed mode
		var current_mode = DisplayServer.window_get_mode()
		if current_mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_size(resolutions[index])
			# Center the window
			var screen_size = DisplayServer.screen_get_size()
			var window_size = DisplayServer.window_get_size()
			DisplayServer.window_set_position(Vector2i(
				(screen_size.x - window_size.x) / 2, 
				(screen_size.y - window_size.y) / 2
			))

func apply_shadow_quality(quality_index):
	# If we have an OptimizationManager, let it handle shadow quality
	if optimization_manager:
		optimization_manager.set_setting("shadow_quality", quality_index)
		return
	
	# Fallback implementation for a WorldEnvironment
	print("Settings: Shadow quality set to " + shadow_quality_options[quality_index])
	
	var world_env = get_tree().get_first_node_in_group("world_environment") 
	if world_env and world_env.environment:
		var env = world_env.environment
		
		match quality_index:
			0:  # Off
				env.set_shadow_enabled(false)
			1:  # Low
				env.set_shadow_enabled(true)
				env.set_volumetric_fog_enabled(false)
				env.set_ssao_enabled(false)
			2:  # Medium
				env.set_shadow_enabled(true)
				env.set_volumetric_fog_enabled(false)
				env.set_ssao_enabled(true)
			3:  # High
				env.set_shadow_enabled(true)
				env.set_volumetric_fog_enabled(true)
				env.set_ssao_enabled(true)

func apply_antialiasing(aa_index):
	# Apply anti-aliasing settings to viewport
	print("Settings: Anti-aliasing set to " + antialiasing_options[aa_index])
	
	var viewport = get_viewport()
	if viewport:
		match aa_index:
			0:  # None
				viewport.set_msaa_3d(Viewport.MSAA_DISABLED) 
				viewport.set_screen_space_aa(Viewport.SCREEN_SPACE_AA_DISABLED)
			1:  # MSAA 2x
				viewport.set_msaa_3d(Viewport.MSAA_2X)
				viewport.set_screen_space_aa(Viewport.SCREEN_SPACE_AA_DISABLED)
			2:  # MSAA 4x
				viewport.set_msaa_3d(Viewport.MSAA_4X)
				viewport.set_screen_space_aa(Viewport.SCREEN_SPACE_AA_DISABLED)
			3:  # MSAA 8x
				viewport.set_msaa_3d(Viewport.MSAA_8X)
				viewport.set_screen_space_aa(Viewport.SCREEN_SPACE_AA_DISABLED)
			4:  # FXAA
				viewport.set_msaa_3d(Viewport.MSAA_DISABLED)
				viewport.set_screen_space_aa(Viewport.SCREEN_SPACE_AA_FXAA)

func apply_texture_quality(quality_index):
	# Apply texture quality settings
	print("Settings: Texture quality set to " + texture_quality_options[quality_index])
	
	match quality_index:
		0:  # Low
			# Set lower texture quality
			ProjectSettings.set_setting("rendering/textures/default_filters/texture_mipmap_bias", 1.0)
			ProjectSettings.set_setting("rendering/textures/default_filters/anisotropic_filtering_level", 1)
		1:  # Medium
			# Set medium texture quality
			ProjectSettings.set_setting("rendering/textures/default_filters/texture_mipmap_bias", 0.0)
			ProjectSettings.set_setting("rendering/textures/default_filters/anisotropic_filtering_level", 4)
		2:  # High
			# Set high texture quality
			ProjectSettings.set_setting("rendering/textures/default_filters/texture_mipmap_bias", -0.5)
			ProjectSettings.set_setting("rendering/textures/default_filters/anisotropic_filtering_level", 16)

func save_settings():
	# Graphics settings
	var resolution_option = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/ResolutionSection/ResolutionOption
	var fullscreen_check = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/DisplaySection/FullscreenCheck
	var vsync_check = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/DisplaySection/VsyncCheck
	var shadow_option = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/ShadowSection/ShadowOption
	var aa_option = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/AntiAliasingSection/AntiAliasingOption
	var tex_option = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/TextureSection/TextureOption
	
	config.set_value("graphics", "resolution_index", resolution_option.selected)
	config.set_value("graphics", "fullscreen", fullscreen_check.button_pressed)
	config.set_value("graphics", "vsync", vsync_check.button_pressed)
	config.set_value("graphics", "shadow_quality", shadow_option.selected)
	config.set_value("graphics", "antialiasing", aa_option.selected)
	config.set_value("graphics", "texture_quality", tex_option.selected)
	
	# Audio settings
	var master_slider = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Audio/MasterSection/MasterVolumeSlider
	var music_slider = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Audio/MusicSection/MusicVolumeSlider
	var sfx_slider = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Audio/SFXSection/SFXVolumeSlider
	
	config.set_value("audio", "master_volume", master_slider.value)
	config.set_value("audio", "music_volume", music_slider.value)
	config.set_value("audio", "sfx_volume", sfx_slider.value)
	
	# Advanced settings
	var show_fps_check = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Advanced/ScrollContainer/AdvancedOptionsContainer/DebugSection/DebugContainer/ShowFPSCheck
	
	config.set_value("advanced", "show_fps", show_fps_check.button_pressed)
	
	# Save all to file
	var error = config.save(CONFIG_FILE_PATH)
	if error != OK:
		print("Settings: Failed to save config file. Error: ", error)
	else:
		print("Settings: Settings saved successfully")

func load_settings():
	# Load config file if it exists
	var error = config.load(CONFIG_FILE_PATH)
	if error != OK:
		# File doesn't exist or couldn't be loaded, use defaults
		print("Settings: No config file found or error loading. Using defaults.")
		apply_default_settings()
		return
	
	# Graphics settings
	var resolution_option = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/ResolutionSection/ResolutionOption
	var fullscreen_check = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/DisplaySection/FullscreenCheck
	var vsync_check = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/DisplaySection/VsyncCheck
	var shadow_option = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/ShadowSection/ShadowOption
	var aa_option = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/AntiAliasingSection/AntiAliasingOption
	var tex_option = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Graphics/ScrollContainer/OptionsContainer/TextureSection/TextureOption
	
	# Load and validate resolution index
	var resolution_index = config.get_value("graphics", "resolution_index", 4)  # Default to 1920x1080
	if resolution_index < 0 or resolution_index >= resolutions.size():
		resolution_index = 4  # Default to 1920x1080
	
	resolution_option.selected = resolution_index
	fullscreen_check.button_pressed = config.get_value("graphics", "fullscreen", false)
	vsync_check.button_pressed = config.get_value("graphics", "vsync", true)
	
	# Load and validate shadow quality
	var shadow_index = config.get_value("graphics", "shadow_quality", 2)  # Default to Medium
	if shadow_index < 0 or shadow_index >= shadow_quality_options.size():
		shadow_index = 2
	shadow_option.selected = shadow_index
	
	# Load and validate anti-aliasing
	var aa_index = config.get_value("graphics", "antialiasing", 1)  # Default to MSAA 2x
	if aa_index < 0 or aa_index >= antialiasing_options.size():
		aa_index = 1
	aa_option.selected = aa_index
	
	# Load and validate texture quality
	var tex_index = config.get_value("graphics", "texture_quality", 1)  # Default to Medium
	if tex_index < 0 or tex_index >= texture_quality_options.size():
		tex_index = 1
	tex_option.selected = tex_index
	
	# Audio settings
	var master_slider = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Audio/MasterSection/MasterVolumeSlider
	var music_slider = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Audio/MusicSection/MusicVolumeSlider
	var sfx_slider = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Audio/SFXSection/SFXVolumeSlider
	
	var master_value = config.get_value("audio", "master_volume", -10.0)
	var music_value = config.get_value("audio", "music_volume", -15.0)
	var sfx_value = config.get_value("audio", "sfx_volume", -10.0)
	
	master_slider.value = master_value
	music_slider.value = music_value
	sfx_slider.value = sfx_value
	
	# Update volume labels
	$SettingsUI/PanelContainer/MarginContainer/TabContainer/Audio/MasterSection/MasterVolumeValue.text = str(master_value) + " dB"
	$SettingsUI/PanelContainer/MarginContainer/TabContainer/Audio/MusicSection/MusicVolumeValue.text = str(music_value) + " dB"
	$SettingsUI/PanelContainer/MarginContainer/TabContainer/Audio/SFXSection/SFXVolumeValue.text = str(sfx_value) + " dB"
	
	# Advanced settings
	var show_fps_check = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Advanced/ScrollContainer/AdvancedOptionsContainer/DebugSection/DebugContainer/ShowFPSCheck
	show_fps_check.button_pressed = config.get_value("advanced", "show_fps", false)
	
	# Apply loaded FPS setting
	if show_fps_check.button_pressed:
		# Try to create or show performance monitor
		var performance_monitor = get_node_or_null("/root/PerformanceMonitor")
		if not performance_monitor:
			var perf_scene = load("res://Scenes/UI/Ingame/preformance_monitor.tscn")
			if perf_scene:
				performance_monitor = perf_scene.instantiate()
				performance_monitor.name = "PerformanceMonitor"
				get_tree().root.add_child(performance_monitor)
	
	# Apply the loaded settings
	apply_graphics_settings()
	apply_audio_settings()
	
	# Load input mappings
	load_input_mappings()

# Set up dynamic input mapping display with categorization
func setup_input_mapping():
	# Get controls container
	var controls_list = $SettingsUI/PanelContainer/MarginContainer/TabContainer/Controls/ScrollContainer/ControlsList
	
	# Clear existing children (in case this function is called again)
	for child in controls_list.get_children():
		child.queue_free()
	
	# Start with a clean slate
	action_list.clear()
	button_list.clear()
	
	# Get all actions from project settings, and sort them for better display
	action_list = InputMap.get_actions()
	action_list.sort()
	
	# Filter out actions that begin with "ui_" (those are engine defaults)
	var filtered_actions = []
	for action in action_list:
		var action_str = action as String
		if not action_str.begins_with("ui_"):
			filtered_actions.append(action)
	
	action_list = filtered_actions
	
	# Categorize actions for better organization
	var movement_actions = []
	var interaction_actions = []
	var combat_actions = []
	var other_actions = []
	
	for action in action_list:
		var action_str = action as String
		if action_str.begins_with("move_") or action_str.contains("jump") or action_str.contains("sprint"):
			movement_actions.append(action)
		elif action_str.contains("interact") or action_str.contains("use") or action_str.contains("item"):
			interaction_actions.append(action)
		elif action_str.contains("attack") or action_str.contains("fire") or action_str.contains("reload"):
			combat_actions.append(action)
		else:
			other_actions.append(action)
	
	# Add section headers and controls
	if movement_actions.size() > 0:
		add_control_section("Movement", movement_actions, controls_list)
	
	if interaction_actions.size() > 0:
		add_control_section("Interaction", interaction_actions, controls_list)
	
	if combat_actions.size() > 0:
		add_control_section("Combat", combat_actions, controls_list)
	
	if other_actions.size() > 0:
		add_control_section("Other", other_actions, controls_list)

func add_control_section(section_name, actions, controls_list):
	# Add section header
	var section_label = Label.new()
	section_label.text = section_name
	section_label.add_theme_font_size_override("font_size", 16)
	controls_list.add_child(section_label)
	
	# Add separator
	var separator = HSeparator.new()
	controls_list.add_child(separator)
	
	# Add actions
	for action in actions:
		# Create container for this action
		var hbox = HBoxContainer.new()
		
		# Create label with readable action name
		var label = Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = action.capitalize().replace("_", " ")
		hbox.add_child(label)
		
		# Create button for key binding
		var button = Button.new()
		button.custom_minimum_size.x = 120
		update_button_text(button, action)
		
		# Connect button signal
		button.pressed.connect(_on_key_button_pressed.bind(action, button))
		
		# Store reference to button
		button_list[action] = button
		
		# Add button to container
		hbox.add_child(button)
		
		# Add container to the list
		controls_list.add_child(hbox)
	
	# Add spacing after section
	var spacer = Control.new()
	spacer.custom_minimum_size.y = 10
	controls_list.add_child(spacer)

# Update button text based on the current key binding
func update_button_text(button: Button, action: String):
	# Get the first key in the mapping (for simplicity)
	var events = InputMap.action_get_events(action)
	
	if events.size() > 0:
		# Different event types need different handling
		var event = events[0]
		if event is InputEventKey:
			button.text = OS.get_keycode_string(event.keycode)
		elif event is InputEventMouseButton:
			button.text = "Mouse " + str(event.button_index)
		elif event is InputEventJoypadButton:
			button.text = "Joy Button " + str(event.button_index)
		elif event is InputEventJoypadMotion:
			button.text = "Joy Axis " + str(event.axis)
		else:
			button.text = "Unknown"
	else:
		button.text = "Unassigned"

# Handle key button press (to start remapping)
func _on_key_button_pressed(action, button):
	if currently_remapping:
		return
	
	currently_remapping = true
	action_to_remap = action
	button.text = "Press any key..."
	
	# Set a slight delay to avoid capturing the button press itself
	ignore_next_key = true
	get_tree().create_timer(0.1).timeout.connect(func(): ignore_next_key = false)

# Handle input to detect key presses for remapping
func _input(event):
	if currently_remapping and not ignore_next_key:
		if event is InputEventKey or event is InputEventMouseButton:
			if event is InputEventKey and event.keycode == KEY_ESCAPE:
				# Escape cancels remapping
				currently_remapping = false
				update_button_text(button_list[action_to_remap], action_to_remap)
			else:
				# Remap the action
				InputMap.action_erase_events(action_to_remap)
				InputMap.action_add_event(action_to_remap, event)
				
				# Update button text
				update_button_text(button_list[action_to_remap], action_to_remap)
				
				# Reset state
				currently_remapping = false
				
				# Save the new mapping
				save_input_mapping(action_to_remap, event)
			
			get_viewport().set_input_as_handled()

# Reset input mappings to project defaults
func reset_input_mappings():
	# Clear the custom input mappings section from config
	config.load(CONFIG_FILE_PATH)
	
	var found_keys = []
	for section in config.get_sections():
		if section == "input":
			for key in config.get_section_keys(section):
				found_keys.append(key)
	
	for key in found_keys:
		config.erase_section_key("input", key)
	
	config.save(CONFIG_FILE_PATH)
	
	# Reset the input map to project defaults
	InputMap.load_from_project_settings()
	
	# Update the UI
	setup_input_mapping()

# Save a specific input mapping
func save_input_mapping(action: String, event):
	config.load(CONFIG_FILE_PATH)
	
	# Store the event properties
	if event is InputEventKey:
		config.set_value("input", action, {
			"type": "key",
			"keycode": event.keycode,
			"physical_keycode": event.physical_keycode
		})
	elif event is InputEventMouseButton:
		config.set_value("input", action, {
			"type": "mouse",
			"button_index": event.button_index
		})
	elif event is InputEventJoypadButton:
		config.set_value("input", action, {
			"type": "joy_button",
			"button_index": event.button_index
		})
	elif event is InputEventJoypadMotion:
		config.set_value("input", action, {
			"type": "joy_motion",
			"axis": event.axis,
			"axis_value": event.axis_value
		})
	
	config.save(CONFIG_FILE_PATH)

# Load custom input mappings
func load_input_mappings():
	if !config.has_section("input"):
		return
	
	var input_keys = config.get_section_keys("input")
	for action in input_keys:
		if !InputMap.has_action(action):
			continue
		
		var mapping = config.get_value("input", action)
		
		# Clear existing events for this action
		InputMap.action_erase_events(action)
		
		# Create and add the appropriate event
		var event = null
		
		match mapping.get("type", ""):
			"key":
				event = InputEventKey.new()
				event.keycode = mapping.get("keycode", 0)
				event.physical_keycode = mapping.get("physical_keycode", 0)
			"mouse":
				event = InputEventMouseButton.new()
				event.button_index = mapping.get("button_index", 0)
			"joy_button":
				event = InputEventJoypadButton.new()
				event.button_index = mapping.get("button_index", 0)
			"joy_motion":
				event = InputEventJoypadMotion.new()
				event.axis = mapping.get("axis", 0)
				event.axis_value = mapping.get("axis_value", 0)
		
		if event:
			InputMap.action_add_event(action, event)
