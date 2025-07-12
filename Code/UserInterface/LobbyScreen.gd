extends Control

# Game settings
var selected_map = "Station"
var selected_mode = "Standard"
var player_ready = false
var all_players_ready = false
var is_countdown_active = false
var countdown_time = 5

# UI references - update node paths to match your UI
@onready var player_list = $PanelContainer/MarginContainer/VBoxContainer/PlayerSection/PlayerList
@onready var status_label = $PanelContainer/MarginContainer/VBoxContainer/StatusLabel
@onready var ready_button = $PanelContainer/MarginContainer/VBoxContainer/GameControls/ReadyButton
@onready var start_game_button = $PanelContainer/MarginContainer/VBoxContainer/GameControls/StartGameButton
@onready var map_option = $PanelContainer/MarginContainer/VBoxContainer/SettingsSection/MapContainer/MapOption
@onready var mode_option = $PanelContainer/MarginContainer/VBoxContainer/SettingsSection/ModeContainer/ModeOption
@onready var countdown_label = $CountdownLabel
@onready var back_button = $BackButton
@onready var character_info = $CharacterInfo

# Game manager reference
var game_manager = null
var is_host = false
var local_peer_id = 1
var player_data = {}  # peer_id -> {name, ready, character, ...}

# Signals
signal back_pressed()
signal start_game(map_name, game_mode)

# Game state
var is_transitioning_to_game = false

# Initialize with game manager data
func initialize_from_game_manager(manager):
	game_manager = manager
	
	# Copy settings from game manager
	is_host = manager.is_host
	local_peer_id = manager.get_local_peer_id()
	
	# Copy player data
	player_data.clear()
	for player_id in manager.get_players():
		var player = manager.get_players()[player_id]
		player_data[player_id] = {
			"name": player.name,
			"ready": player.ready,
			"character": player.customization
		}
	
	# Update settings
	selected_map = manager.current_map
	selected_mode = manager.current_game_mode
	
	# Connect manager signals
	manager.player_registered.connect(_on_player_registered)
	manager.player_unregistered.connect(_on_player_unregistered)
	manager.player_ready_status_changed.connect(_on_player_ready_status_changed)
	manager.player_connected.connect(_on_player_connected)
	manager.player_disconnected.connect(_on_player_disconnected)
	manager.server_disconnected.connect(_on_server_disconnected)
	
	# Initialize UI
	initialize_ui()
	
	# Register ourselves if needed
	if !player_data.has(local_peer_id):
		var player_name = manager.get_player_name()
		var character_data = manager.get_character_data()
		
		# Add to player data
		player_data[local_peer_id] = {
			"name": player_name,
			"ready": false,
			"character": character_data
		}
	
	# Update UI
	update_player_list()
	update_start_button_visibility()
	
	# Set character info
	var character_name = "Unknown"
	if player_data.has(local_peer_id) and "name" in player_data[local_peer_id]:
		character_name = player_data[local_peer_id].name
	character_info.text = "Character: " + character_name

func _ready():
	# Connect button signals
	back_button.pressed.connect(_on_back_button_pressed)
	ready_button.pressed.connect(_on_ready_button_pressed)
	start_game_button.pressed.connect(_on_start_game_button_pressed)
	map_option.item_selected.connect(_on_map_selected)
	mode_option.item_selected.connect(_on_mode_selected)
	
	# Get game manager reference
	game_manager = get_node_or_null("/root/GameManager")
	
	if game_manager:
		# Initialize from game manager data
		initialize_from_game_manager(game_manager)
	else:
		# Fallback initialization if game manager not found
		print("ERROR: GameManager not found in lobby!")
		initialize_ui()

func initialize_ui():
	# Set defaults
	countdown_label.visible = false
	status_label.text = "Waiting for players..."
	
	# Clear player list
	player_list.clear()
	
	# Set map and mode options
	for i in range(map_option.get_item_count()):
		if map_option.get_item_text(i) == selected_map:
			map_option.selected = i
			break
	
	for i in range(mode_option.get_item_count()):
		if mode_option.get_item_text(i) == selected_mode:
			mode_option.selected = i
			break
	
	# Update UI based on host status
	update_start_button_visibility()

func update_player_list():
	# Clear and rebuild player list
	player_list.clear()
	
	for peer_id in player_data.keys():
		var player = player_data[peer_id]
		var ready_status = " [READY]" if player.ready else " [NOT READY]"
		var name_text = player.name + ready_status
		
		var is_local = peer_id == local_peer_id
		var is_player_host = peer_id == 1
		
		if is_local:
			name_text += " (You)"
		if is_player_host:
			name_text += " (Host)"
		
		player_list.add_item(name_text)

func update_start_button_visibility():
	# Always update based on host status from game manager
	if game_manager:
		is_host = game_manager.is_host
	
	start_game_button.visible = is_host
	
	# Only host can modify game settings
	map_option.disabled = !is_host
	mode_option.disabled = !is_host
	
	if is_host:
		start_game_button.disabled = !all_players_ready
	else:
		start_game_button.visible = false

func check_all_players_ready():
	all_players_ready = true
	
	for peer_id in player_data.keys():
		if !player_data[peer_id].ready:
			all_players_ready = false
			break
	
	update_start_button_visibility()
	
	if all_players_ready:
		status_label.text = "All players ready!"
	else:
		status_label.text = "Waiting for all players to be ready..."

# Start countdown sequence
func start_countdown():
	is_countdown_active = true
	countdown_time = 5
	countdown_label.visible = true
	countdown_label.text = str(countdown_time)
	
	status_label.text = "Game starting in " + str(countdown_time) + " seconds..."
	
	# Start countdown
	process_countdown()

func process_countdown():
	if !is_countdown_active:
		return
	
	# Wait 1 second
	await get_tree().create_timer(1.0).timeout
	
	countdown_time -= 1
	countdown_label.text = str(countdown_time)
	
	if countdown_time <= 0:
		is_countdown_active = false
		emit_signal("start_game", selected_map, selected_mode)
	else:
		# Continue countdown
		process_countdown()

func _on_back_button_pressed():
	if is_transitioning_to_game:
		return
		
	if game_manager:
		game_manager.disconnect_from_game()
	
	emit_signal("back_pressed")

func _on_ready_button_pressed():
	# Toggle ready status
	player_ready = !player_ready
	
	if game_manager:
		var peer_id = game_manager.get_local_peer_id()
		
		if peer_id > 0:
			# Update button text
			ready_button.text = "Cancel Ready" if player_ready else "Ready"
			
			# Update game manager
			game_manager.set_player_ready(peer_id, player_ready)
	else:
		# Fallback if game manager not found
		var peer_id = local_peer_id
		
		if peer_id in player_data:
			player_data[peer_id].ready = player_ready
			
			# Update button text
			ready_button.text = "Cancel Ready" if player_ready else "Ready"
			
			# Update UI
			update_player_list()
			check_all_players_ready()

func _on_start_game_button_pressed():
	if !is_host:
		return
	
	if !all_players_ready:
		status_label.text = "Cannot start: Not all players are ready"
		return
	
	if game_manager:
		# Use game manager to start the game
		game_manager.start_game(selected_map, selected_mode)
	else:
		# Start local countdown
		start_countdown()

func _on_map_selected(index):
	selected_map = map_option.get_item_text(index)
	
	if game_manager and is_host:
		game_manager.network_update_game_settings.rpc(selected_map, selected_mode)

func _on_mode_selected(index):
	selected_mode = mode_option.get_item_text(index)
	
	if game_manager and is_host:
		game_manager.network_update_game_settings.rpc(selected_map, selected_mode)

# Signal handlers for game manager events
func _on_player_registered(peer_id, player_name):
	if !player_data.has(peer_id):
		player_data[peer_id] = {
			"name": player_name,
			"ready": false,
			"character": {}
		}
	
	update_player_list()
	status_label.text = player_name + " has joined"

func _on_player_unregistered(peer_id):
	if player_data.has(peer_id):
		player_data.erase(peer_id)
	
	update_player_list()
	check_all_players_ready()

func _on_player_ready_status_changed(peer_id, is_ready):
	if player_data.has(peer_id):
		player_data[peer_id].ready = is_ready
	
	update_player_list()
	check_all_players_ready()

func _on_player_connected(peer_id):
	status_label.text = "Player " + str(peer_id) + " connected"

func _on_player_disconnected(peer_id):
	status_label.text = "Player " + str(peer_id) + " disconnected"
	
	# Player will be unregistered by the game manager, which will trigger _on_player_unregistered

func _on_server_disconnected():
	status_label.text = "Disconnected from host"
	
	# Return to main menu after a brief delay
	await get_tree().create_timer(2.0).timeout
	emit_signal("back_pressed")
