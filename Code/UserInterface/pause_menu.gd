extends Control

@export var main_menu_scene: String = "res://Scenes/UI/Menus/Main_menu.tscn"
@export var settings_scene: String = "res://Scenes/UI/Menus/Settings.tscn"
@export var handle_esc_internally: bool = true

const MASTER_BUS = 0
const CONFIG_FILE_PATH = "user://settings.cfg"

signal pause_menu_closed()

# UI Node references
@onready var background = $Background
@onready var center_container = $CenterContainer
@onready var panel_container = $CenterContainer/PanelContainer
@onready var resume_button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ResumeButton
@onready var main_menu_button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/MainMenuButton
@onready var quit_button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/QuitButton
@onready var settings_button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SettingsPanelContainer/MarginContainer/VBoxContainer/SettingsButton
@onready var master_slider = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SettingsPanelContainer/MarginContainer/VBoxContainer/MasterVolumeContainer/MasterVolumeSlider
@onready var fullscreen_check = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SettingsPanelContainer/MarginContainer/VBoxContainer/FullscreenContainer/FullscreenCheckBox

var is_menu_active: bool = false

func _ready():
	"""Initialize the pause menu"""
	print("PauseMenu: Initializing...")
	
	# Ensure proper anchoring and sizing
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	add_to_group("pause_menu")
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	
	visible = false
	is_menu_active = false
	
	# Wait for all nodes to be ready
	await get_tree().process_frame
	
	setup_button_connections()
	setup_audio_controls()
	load_settings()
	
	print("PauseMenu: Initialization complete")

func setup_button_connections():
	"""Connect all button signals with error checking"""
	print("PauseMenu: Setting up button connections...")
	
	if resume_button:
		resume_button.pressed.connect(_on_resume_button_pressed)
	else:
		print("PauseMenu: Warning - Resume button not found")
	
	if main_menu_button:
		main_menu_button.pressed.connect(_on_main_menu_button_pressed)
	else:
		print("PauseMenu: Warning - Main menu button not found")
	
	if quit_button:
		quit_button.pressed.connect(_on_quit_button_pressed)
	else:
		print("PauseMenu: Warning - Quit button not found")
	
	if settings_button:
		settings_button.pressed.connect(_on_settings_button_pressed)
	else:
		print("PauseMenu: Warning - Settings button not found")

func setup_audio_controls():
	"""Setup audio sliders and fullscreen checkbox"""
	print("PauseMenu: Setting up audio controls...")
	
	if master_slider:
		master_slider.value_changed.connect(_on_master_volume_changed)
	else:
		print("PauseMenu: Warning - Master volume slider not found")
	
	if fullscreen_check:
		fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	else:
		print("PauseMenu: Warning - Fullscreen checkbox not found")

func _on_master_volume_changed(value: float):
	"""Handle master volume slider changes"""
	AudioServer.set_bus_volume_db(MASTER_BUS, value)

func _on_fullscreen_toggled(button_pressed: bool):
	"""Handle fullscreen checkbox changes"""
	var window_mode = DisplayServer.WINDOW_MODE_FULLSCREEN if button_pressed else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(window_mode)

func _input(event):
	"""Handle input events, especially ESC key"""
	if not is_inside_tree():
		return
	
	# Handle ESC key for pause menu toggle
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if handle_esc_internally:
			if is_menu_active:
				hide_pause_menu()
			else:
				show_pause_menu()
			get_viewport().set_input_as_handled()

func _gui_input(event):
	"""Handle GUI input events"""
	if not is_menu_active:
		return
	
	# Consume all input when menu is active to prevent background interaction
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		accept_event()

func show_pause_menu():
	"""Show the pause menu and pause the game"""
	print("PauseMenu: Showing pause menu")
	
	if is_menu_active:
		return
	
	is_menu_active = true
	visible = true
	get_tree().paused = true
	
	# Ensure the menu is properly sized and positioned
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Move to front
	move_to_front()
	
	# Grab focus for input handling
	if resume_button:
		resume_button.grab_focus()
	
	animate_menu_appearance()

func hide_pause_menu():
	"""Hide the pause menu and unpause the game"""
	print("PauseMenu: Hiding pause menu")
	
	if not is_menu_active:
		return
	
	is_menu_active = false
	save_settings()
	
	animate_menu_disappearance()
	
	# Unpause after animation completes
	await get_tree().create_timer(0.1, true, false, true).timeout
	get_tree().paused = false
	visible = false
	
	emit_signal("pause_menu_closed")

func toggle_pause():
	"""Toggle pause menu visibility and game pause state"""
	if is_menu_active:
		hide_pause_menu()
	else:
		show_pause_menu()

func animate_menu_appearance():
	"""Animate menu appearance"""
	if not panel_container:
		return
	
	panel_container.modulate.a = 0.0
	panel_container.scale = Vector2(0.8, 0.8)
	
	var tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.parallel().tween_property(panel_container, "modulate:a", 1.0, 0.2)
	tween.parallel().tween_property(panel_container, "scale", Vector2(1.0, 1.0), 0.2)
	tween.tween_callback(func(): print("PauseMenu: Animation complete"))

func animate_menu_disappearance():
	"""Animate menu disappearance"""
	if not panel_container:
		return
	
	var tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.parallel().tween_property(panel_container, "modulate:a", 0.0, 0.1)
	tween.parallel().tween_property(panel_container, "scale", Vector2(0.8, 0.8), 0.1)

func _on_resume_button_pressed():
	"""Handle resume button press"""
	print("PauseMenu: Resume button pressed")
	hide_pause_menu()

func _on_main_menu_button_pressed():
	"""Handle main menu button press"""
	print("PauseMenu: Main menu button pressed")
	save_settings()
	
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("return_to_main_menu"):
		# First unpause
		get_tree().paused = false
		is_menu_active = false
		animate_transition_to_main_menu(func(): game_manager.return_to_main_menu())
	else:
		get_tree().paused = false
		is_menu_active = false
		animate_transition_to_main_menu(func(): get_tree().change_scene_to_file(main_menu_scene))

func _on_quit_button_pressed():
	"""Handle quit button press"""
	print("PauseMenu: Quit button pressed")
	save_settings()
	animate_transition_to_quit()

func _on_settings_button_pressed():
	"""Handle settings button press"""
	print("PauseMenu: Settings button pressed")
	save_settings()
	is_menu_active = false
	visible = false
	
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("show_settings_from_pause"):
		game_manager.show_settings_from_pause()
	else:
		open_settings_fallback()

func open_settings_fallback():
	"""Fallback method to open settings if GameManager is unavailable"""
	if not ResourceLoader.exists(settings_scene):
		print("PauseMenu: Settings scene not found: ", settings_scene)
		# Re-show pause menu if settings can't be opened
		show_pause_menu()
		return
	
	var settings_resource = load(settings_scene)
	var settings_instance = settings_resource.instantiate()
	get_tree().root.add_child(settings_instance)
	
	if settings_instance.has_signal("settings_closed"):
		settings_instance.settings_closed.connect(_on_settings_closed)

func _on_settings_closed():
	"""Handle settings menu being closed"""
	print("PauseMenu: Settings closed, returning to pause menu")
	show_pause_menu()
	load_settings()

func animate_transition_to_main_menu(callback: Callable):
	"""Animate fade to main menu"""
	var fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().root.add_child(fade)
	
	var fade_tween = create_tween()
	fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fade_tween.tween_property(fade, "color", Color(0, 0, 0, 1), 0.5)
	fade_tween.tween_callback(func(): 
		callback.call()
		if is_instance_valid(fade):
			fade.queue_free()
	)

func animate_transition_to_quit():
	"""Animate fade to quit"""
	var fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().root.add_child(fade)
	
	var fade_tween = create_tween()
	fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fade_tween.tween_property(fade, "color", Color(0, 0, 0, 1), 0.5)
	fade_tween.tween_callback(get_tree().quit)

func load_settings():
	"""Load settings from config file"""
	print("PauseMenu: Loading settings...")
	
	var config = ConfigFile.new()
	var error = config.load(CONFIG_FILE_PATH)
	
	if error != OK:
		print("PauseMenu: No settings file found or error loading, using defaults")
		return
	
	# Load audio settings
	var master_volume = config.get_value("audio", "master_volume", -10.0)
	if master_slider:
		master_slider.value = master_volume
		AudioServer.set_bus_volume_db(MASTER_BUS, master_volume)
	
	# Load video settings
	var fullscreen = config.get_value("video", "fullscreen", false)
	if fullscreen_check:
		fullscreen_check.button_pressed = fullscreen

func save_settings():
	"""Save settings to config file"""
	print("PauseMenu: Saving settings...")
	
	var config = ConfigFile.new()
	config.load(CONFIG_FILE_PATH)  # Load existing settings first
	
	# Save audio settings
	if master_slider:
		config.set_value("audio", "master_volume", master_slider.value)
	
	# Save video settings
	if fullscreen_check:
		config.set_value("video", "fullscreen", fullscreen_check.button_pressed)
	
	var save_error = config.save(CONFIG_FILE_PATH)
	if save_error != OK:
		print("PauseMenu: Error saving settings: ", save_error)
	else:
		print("PauseMenu: Settings saved successfully")

func _exit_tree():
	"""Cleanup when the node is removed"""
	print("PauseMenu: Cleaning up...")
	if is_menu_active:
		get_tree().paused = false
