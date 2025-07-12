extends Control

# Path to the scenes
@export var game_scene_path: String = "res://Scenes/Maps/Zypharion.tscn"
@export var multiplayer_scene_path: String = "res://Scenes/UI/Menus/network_ui.tscn" 
@export var settings_scene_path: String = "res://Scenes/UI/Menus/Settings.tscn"
@export var character_creation_path: String = "res://Scenes/UI/Menus/character_creation.tscn"

# Called when the node enters the scene tree for the first time
func _ready():
	# Connect button signals
	$PanelContainer/MarginContainer/MenuOptions/PlayButton.pressed.connect(_on_play_button_pressed)
	$PanelContainer/MarginContainer/MenuOptions/MultiplayerButton.pressed.connect(_on_multiplayer_button_pressed)
	$PanelContainer/MarginContainer/MenuOptions/SettingsButton.pressed.connect(_on_settings_button_pressed)
	$PanelContainer/MarginContainer/MenuOptions/QuitButton.pressed.connect(_on_quit_button_pressed)
	
	# Reset multiplayer - IMPORTANT FOR CLEAN STATE
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	
	# Add a fade-in animation when the menu loads
	modulate.a = 0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.5)

# Play button pressed - Single player mode
func _on_play_button_pressed():
	print("Main Menu: Play button pressed - starting single player game")
	
	# Configure for singleplayer in GameManager
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		# Reset network state
		if multiplayer.multiplayer_peer:
			multiplayer.multiplayer_peer.close()
			multiplayer.multiplayer_peer = null
		
		# Set game state to MAIN_MENU to indicate singleplayer flow
		game_manager.change_state(game_manager.GameState.MAIN_MENU)
	
	# Transition to character creation
	transition_to_scene(character_creation_path)

# Multiplayer button pressed
func _on_multiplayer_button_pressed():
	print("Main Menu: Multiplayer button pressed")
	
	# Set state to indicate multiplayer flow
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.change_state(game_manager.GameState.NETWORK_SETUP)
	
	# First go to character creation
	transition_to_scene(character_creation_path)

# Settings button pressed
func _on_settings_button_pressed():
	print("Main Menu: Settings button pressed")
	
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("show_settings"):
		game_manager.show_settings()
	else:
		# Fallback direct scene change
		transition_to_scene(settings_scene_path)

# Quit button pressed
func _on_quit_button_pressed():
	print("Main Menu: Quit button pressed")
	
	# Create a fade-out effect before quitting
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(get_tree().quit)

# Helper function to transition between scenes with a fade effect
func transition_to_scene(target_scene: String):
	print("Main Menu: Transitioning to scene: ", target_scene)
	
	# Verify the scene exists before attempting to load it
	if not ResourceLoader.exists(target_scene):
		push_error("Main Menu: Scene does not exist: " + target_scene)
		return
	
	# Fade out
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): 
		print("Main Menu: Changing scene to: ", target_scene)
		get_tree().change_scene_to_file(target_scene)
	)
