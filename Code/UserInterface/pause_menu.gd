extends CanvasLayer

@export var main_menu_scene: String = "res://Scenes/UI/Menus/Main_menu.tscn"
@export var settings_scene: String = "res://Scenes/UI/Menus/Settings.tscn"
@export var handle_esc_internally: bool = false

const MASTER_BUS = 0
const CONFIG_FILE_PATH = "user://settings.cfg"

signal pause_menu_closed()

func _ready():
	layer = 150
	follow_viewport_enabled = true
	add_to_group("pause_menu")
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	
	visible = false
	
	setup_button_connections()
	setup_audio_controls()
	load_settings()

func setup_button_connections():
	$CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ResumeButton.pressed.connect(_on_resume_button_pressed)
	$CenterContainer/PanelContainer/MarginContainer/VBoxContainer/MainMenuButton.pressed.connect(_on_main_menu_button_pressed)
	$CenterContainer/PanelContainer/MarginContainer/VBoxContainer/QuitButton.pressed.connect(_on_quit_button_pressed)
	$CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SettingsPanelContainer/MarginContainer/VBoxContainer/SettingsButton.pressed.connect(_on_settings_button_pressed)

func setup_audio_controls():
	var master_slider = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SettingsPanelContainer/MarginContainer/VBoxContainer/MasterVolumeContainer/MasterVolumeSlider
	var fullscreen_check = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SettingsPanelContainer/MarginContainer/VBoxContainer/FullscreenContainer/FullscreenCheckBox
	
	master_slider.value_changed.connect(func(value): AudioServer.set_bus_volume_db(MASTER_BUS, value))
	fullscreen_check.toggled.connect(func(button_pressed): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if button_pressed else DisplayServer.WINDOW_MODE_WINDOWED))

func _input(event):
	if not visible:
		return
		
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if handle_esc_internally:
			toggle_pause()
		get_viewport().set_input_as_handled()

func _process(_delta):
	if handle_esc_internally and Input.is_action_just_pressed("esc") and not get_tree().paused:
		toggle_pause()

func toggle_pause():
	visible = !visible
	get_tree().paused = visible
	
	if !visible:
		save_settings()
		emit_signal("pause_menu_closed")
	
	animate_menu_transition()

func animate_menu_transition():
	$CenterContainer/PanelContainer.scale = Vector2(0.9, 0.9) if visible else Vector2(1, 1)
	var tween = create_tween()
	tween.tween_property($CenterContainer/PanelContainer, "scale", Vector2(1, 1) if visible else Vector2(0.9, 0.9), 0.1)

func show_pause_menu():
	visible = true
	get_tree().paused = true
	animate_menu_transition()

func hide_pause_menu():
	visible = false
	get_tree().paused = false
	save_settings()
	emit_signal("pause_menu_closed")

func _on_resume_button_pressed():
	hide_pause_menu()

func _on_main_menu_button_pressed():
	save_settings()
	get_tree().paused = false
	
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("return_to_main_menu"):
		animate_transition_to_main_menu(func(): game_manager.return_to_main_menu())
	else:
		animate_transition_to_main_menu(func(): get_tree().change_scene_to_file(main_menu_scene))

func _on_quit_button_pressed():
	save_settings()
	animate_transition_to_quit()

func _on_settings_button_pressed():
	save_settings()
	visible = false
	
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("show_settings_from_pause"):
		game_manager.show_settings_from_pause()
	else:
		open_settings_fallback()

func open_settings_fallback():
	var settings_instance = ResourceLoader.load(settings_scene).instantiate()
	get_tree().root.add_child(settings_instance)
	
	if settings_instance.has_signal("settings_closed"):
		settings_instance.settings_closed.connect(_on_settings_closed)

func _on_settings_closed():
	visible = true
	load_settings()

func animate_transition_to_main_menu(callback: Callable):
	var fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.anchors_preset = Control.PRESET_FULL_RECT
	get_tree().root.add_child(fade)
	
	var fade_tween = create_tween()
	fade_tween.tween_property(fade, "color", Color(0, 0, 0, 1), 0.5)
	fade_tween.tween_callback(func(): 
		callback.call()
		fade.queue_free()
	)

func animate_transition_to_quit():
	var fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.anchors_preset = Control.PRESET_FULL_RECT
	get_tree().root.add_child(fade)
	
	var fade_tween = create_tween()
	fade_tween.tween_property(fade, "color", Color(0, 0, 0, 1), 0.5)
	fade_tween.tween_callback(get_tree().quit)

func load_settings():
	var config = ConfigFile.new()
	var error = config.load(CONFIG_FILE_PATH)
	
	if error != OK:
		return
	
	var master_volume = config.get_value("audio", "master_volume", -10.0)
	var master_slider = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SettingsPanelContainer/MarginContainer/VBoxContainer/MasterVolumeContainer/MasterVolumeSlider
	master_slider.value = master_volume
	AudioServer.set_bus_volume_db(MASTER_BUS, master_volume)
	
	var fullscreen = config.get_value("video", "fullscreen", false)
	var fullscreen_check = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SettingsPanelContainer/MarginContainer/VBoxContainer/FullscreenContainer/FullscreenCheckBox
	fullscreen_check.button_pressed = fullscreen

func save_settings():
	var config = ConfigFile.new()
	config.load(CONFIG_FILE_PATH)
	
	var master_slider = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SettingsPanelContainer/MarginContainer/VBoxContainer/MasterVolumeContainer/MasterVolumeSlider
	var fullscreen_check = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SettingsPanelContainer/MarginContainer/VBoxContainer/FullscreenContainer/FullscreenCheckBox
	
	config.set_value("audio", "master_volume", master_slider.value)
	config.set_value("video", "fullscreen", fullscreen_check.button_pressed)
	
	config.save(CONFIG_FILE_PATH)
