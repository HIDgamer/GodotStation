extends CanvasLayer

# Scene paths
@export var main_menu_scene: String = "res://Scenes/UI/Menus/Main_menu.tscn"
@export var settings_scene: String = "res://Scenes/UI/Menus/Settings.tscn"
@export var handle_esc_internally: bool = false

# Audio bus indices
const MASTER_BUS = 0

# Config file path
const CONFIG_FILE_PATH = "user://settings.cfg"

# Called when the node enters the scene tree for the first time
func _ready():
	# Add to pause_menu group for easier finding
	add_to_group("pause_menu")
	
	# Hide menu when first created
	visible = false
	
	# Connect button signals
	$CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ResumeButton.pressed.connect(_on_resume_button_pressed)
	$CenterContainer/PanelContainer/MarginContainer/VBoxContainer/MainMenuButton.pressed.connect(_on_main_menu_button_pressed)
	$CenterContainer/PanelContainer/MarginContainer/VBoxContainer/QuitButton.pressed.connect(_on_quit_button_pressed)
	$CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SettingsPanelContainer/MarginContainer/VBoxContainer/SettingsButton.pressed.connect(_on_settings_button_pressed)
	
	# Connect volume and fullscreen signals
	var master_slider = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SettingsPanelContainer/MarginContainer/VBoxContainer/MasterVolumeContainer/MasterVolumeSlider
	var fullscreen_check = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SettingsPanelContainer/MarginContainer/VBoxContainer/FullscreenContainer/FullscreenCheckBox
	
	master_slider.value_changed.connect(func(value): AudioServer.set_bus_volume_db(MASTER_BUS, value))
	fullscreen_check.toggled.connect(func(button_pressed): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if button_pressed else DisplayServer.WINDOW_MODE_WINDOWED))
	
	# Load settings
	load_settings()
	
	# Set up process mode for pausing
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta):
	# Toggle pause menu with Escape key only if internal handling is enabled
	if handle_esc_internally and Input.is_action_just_pressed("esc"):
		toggle_pause()

func toggle_pause():
	visible = !visible
	get_tree().paused = visible
	
	# If closing the menu, save settings
	if !visible:
		save_settings()
	
	# Visual effect for opening/closing
	$CenterContainer/PanelContainer.scale = Vector2(0.9, 0.9) if visible else Vector2(1, 1)
	var tween = create_tween()
	tween.tween_property($CenterContainer/PanelContainer, "scale", Vector2(1, 1) if visible else Vector2(0.9, 0.9), 0.1)

func _on_resume_button_pressed():
	toggle_pause()

func _on_main_menu_button_pressed():
	# Save settings before leaving
	save_settings()
	
	# Unpause game before changing scenes
	get_tree().paused = false
	
	# Use GameManager to handle the transition
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		# Fade out effect
		var fade = ColorRect.new()
		fade.color = Color(0, 0, 0, 0)
		fade.anchors_preset = Control.PRESET_FULL_RECT
		get_tree().root.add_child(fade)
		
		var fade_tween = create_tween()
		fade_tween.tween_property(fade, "color", Color(0, 0, 0, 1), 0.5)
		fade_tween.tween_callback(func(): 
			game_manager.return_to_main_menu()
			fade.queue_free()
		)
	else:
		# Fallback to direct scene change
		get_tree().change_scene_to_file(main_menu_scene)

func _on_quit_button_pressed():
	# Save settings before quitting
	save_settings()
	
	# Fade out effect
	var fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.anchors_preset = Control.PRESET_FULL_RECT
	get_tree().root.add_child(fade)
	
	var fade_tween = create_tween()
	fade_tween.tween_property(fade, "color", Color(0, 0, 0, 1), 0.5)
	fade_tween.tween_callback(get_tree().quit)

func _on_settings_button_pressed():
	# Save current quick settings
	save_settings()
	
	# Hide pause menu temporarily
	visible = false
	
	# Use GameManager if available
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("show_settings"):
		game_manager.show_settings()
	else:
		# Fallback to direct loading
		var settings_instance = ResourceLoader.load(settings_scene).instantiate()
		get_tree().root.add_child(settings_instance)

# Called when settings screen is closed
func _on_settings_closed():
	# Make pause menu visible again
	visible = true
	
	# Load saved settings
	load_settings()

# Load the current settings for quick adjustments
func load_settings():
	var config = ConfigFile.new()
	var error = config.load(CONFIG_FILE_PATH)
	
	if error != OK:
		# File doesn't exist or couldn't be loaded, use defaults
		return
	
	# Load volume setting
	var master_volume = config.get_value("audio", "master_volume", -10.0)
	var master_slider = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SettingsPanelContainer/MarginContainer/VBoxContainer/MasterVolumeContainer/MasterVolumeSlider
	master_slider.value = master_volume
	AudioServer.set_bus_volume_db(MASTER_BUS, master_volume)
	
	# Load fullscreen setting
	var fullscreen = config.get_value("video", "fullscreen", false)
	var fullscreen_check = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SettingsPanelContainer/MarginContainer/VBoxContainer/FullscreenContainer/FullscreenCheckBox
	fullscreen_check.button_pressed = fullscreen

# Save the current settings
func save_settings():
	var config = ConfigFile.new()
	
	# Try to load existing settings first
	config.load(CONFIG_FILE_PATH)
	
	# Get current values
	var master_slider = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SettingsPanelContainer/MarginContainer/VBoxContainer/MasterVolumeContainer/MasterVolumeSlider
	var fullscreen_check = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SettingsPanelContainer/MarginContainer/VBoxContainer/FullscreenContainer/FullscreenCheckBox
	
	# Update settings
	config.set_value("audio", "master_volume", master_slider.value)
	config.set_value("video", "fullscreen", fullscreen_check.button_pressed)
	
	# Save to file
	config.save(CONFIG_FILE_PATH)
