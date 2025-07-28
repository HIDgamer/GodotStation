extends Control

@export var game_scene_path: String = "res://Scenes/Maps/Zypharion.tscn"
@export var multiplayer_scene_path: String = "res://Scenes/UI/Menus/network_ui.tscn" 
@export var settings_scene_path: String = "res://Scenes/UI/Menus/Settings.tscn"
@export var character_creation_path: String = "res://Scenes/UI/Menus/character_creation.tscn"

const FADE_DURATION = 0.5
const BUTTON_HOVER_SCALE = 1.05
const STAR_TWINKLE_DURATION = 2.0

@onready var play_button = $CenterContainer/MainPanel/MarginContainer/VBoxContainer/MenuOptions/PlayButton
@onready var multiplayer_button = $CenterContainer/MainPanel/MarginContainer/VBoxContainer/MenuOptions/MultiplayerButton
@onready var settings_button = $CenterContainer/MainPanel/MarginContainer/VBoxContainer/MenuOptions/SettingsButton
@onready var quit_button = $CenterContainer/MainPanel/MarginContainer/VBoxContainer/MenuOptions/QuitButton
@onready var star_field = $Background/StarField

func _ready():
	setup_initial_state()
	connect_button_signals()
	setup_button_animations()
	animate_entrance()
	start_star_animations()

func setup_initial_state():
	"""Initialize menu with proper state and clean multiplayer connections"""
	reset_multiplayer_state()
	modulate.a = 0

func reset_multiplayer_state():
	"""Ensure any existing multiplayer connections are properly closed"""
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

func connect_button_signals():
	"""Connect all menu button press events to their respective handlers"""
	play_button.pressed.connect(_on_play_button_pressed)
	multiplayer_button.pressed.connect(_on_multiplayer_button_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)

func setup_button_animations():
	"""Configure hover animations for all menu buttons"""
	var buttons = [play_button, multiplayer_button, settings_button, quit_button]
	
	for button in buttons:
		button.mouse_entered.connect(_on_button_hover.bind(button, true))
		button.mouse_exited.connect(_on_button_hover.bind(button, false))

func animate_entrance():
	"""Perform fade-in animation when menu becomes visible"""
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, FADE_DURATION)

func start_star_animations():
	"""Initialize twinkling animations for background stars"""
	for star in star_field.get_children():
		animate_star_twinkle(star)

func animate_star_twinkle(star: Node):
	"""Create twinkling effect for individual background stars"""
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(star, "modulate:a", 0.3, STAR_TWINKLE_DURATION * randf_range(0.8, 1.2))
	tween.tween_property(star, "modulate:a", 1.0, STAR_TWINKLE_DURATION * randf_range(0.8, 1.2))

func _on_button_hover(button: Button, is_hovering: bool):
	"""Handle button hover animations for visual feedback"""
	var tween = create_tween()
	var target_scale = Vector2.ONE * BUTTON_HOVER_SCALE if is_hovering else Vector2.ONE
	tween.tween_property(button, "scale", target_scale, 0.2)

func _on_play_button_pressed():
	"""Handle single player game start button press"""
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("handle_main_menu_play"):
		game_manager.handle_main_menu_play()
	else:
		configure_singleplayer_mode()
		transition_to_scene(character_creation_path)

func _on_multiplayer_button_pressed():
	"""Handle multiplayer setup button press"""
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("handle_main_menu_multiplayer"):
		game_manager.handle_main_menu_multiplayer()
	else:
		configure_multiplayer_mode()
		transition_to_scene(character_creation_path)

func _on_settings_button_pressed():
	"""Handle settings menu button press"""
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("show_settings"):
		game_manager.show_settings()
	else:
		transition_to_scene(settings_scene_path)

func _on_quit_button_pressed():
	"""Handle application quit button press"""
	animate_exit_and_quit()

func configure_singleplayer_mode():
	"""Configure game manager for single player mode"""
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		reset_multiplayer_state()
		if game_manager.has_method("change_state"):
			game_manager.change_state(game_manager.GameState.MAIN_MENU)

func configure_multiplayer_mode():
	"""Configure game manager for multiplayer mode"""
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		if game_manager.has_method("change_state"):
			game_manager.change_state(game_manager.GameState.NETWORK_SETUP)

func animate_exit_and_quit():
	"""Perform fade-out animation before quitting the application"""
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	tween.tween_callback(get_tree().quit)

func transition_to_scene(target_scene: String):
	"""Transition to specified scene with validation and animation"""
	if not validate_scene_path(target_scene):
		return
	
	animate_scene_transition(target_scene)

func validate_scene_path(scene_path: String) -> bool:
	"""Verify that the target scene file exists before transitioning"""
	if not ResourceLoader.exists(scene_path):
		push_error("Main Menu: Scene file not found: " + scene_path)
		return false
	return true

func animate_scene_transition(target_scene: String):
	"""Perform fade-out animation before changing to target scene"""
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): 
		get_tree().change_scene_to_file(target_scene)
	)
