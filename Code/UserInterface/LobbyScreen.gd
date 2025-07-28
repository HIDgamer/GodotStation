extends Control

var selected_map = "Station"
var selected_mode = "Standard"
var player_ready = false
var all_players_ready = false
var is_countdown_active = false
var countdown_time = 5

@onready var player_list = $PanelContainer/MarginContainer/VBoxContainer/PlayerSection/PlayerList
@onready var status_label = $PanelContainer/MarginContainer/VBoxContainer/StatusLabel
@onready var ready_button = $PanelContainer/MarginContainer/VBoxContainer/GameControls/ReadyButton
@onready var start_game_button = $PanelContainer/MarginContainer/VBoxContainer/GameControls/StartGameButton
@onready var map_option = $PanelContainer/MarginContainer/VBoxContainer/SettingsSection/MapContainer/MapOption
@onready var mode_option = $PanelContainer/MarginContainer/VBoxContainer/SettingsSection/ModeContainer/ModeOption
@onready var countdown_label = $CountdownLabel
@onready var back_button = $BackButton
@onready var character_info = $CharacterInfo

var game_manager = null
var local_peer_id = 1
var player_data = {}

signal back_pressed()
signal start_game(map_name, game_mode)

var is_transitioning_to_game = false

func _ready():
	connect_ui_signals()
	initialize_lobby()

func connect_ui_signals():
	"""Connect all UI button and control signals to their handlers"""
	back_button.pressed.connect(_on_back_button_pressed)
	ready_button.pressed.connect(_on_ready_button_pressed)
	start_game_button.pressed.connect(_on_start_game_button_pressed)
	map_option.item_selected.connect(_on_map_selected)
	mode_option.item_selected.connect(_on_mode_selected)

func initialize_lobby():
	"""Initialize lobby with default settings and find game manager"""
	game_manager = get_node_or_null("/root/GameManager")
	
	if game_manager:
		initialize_from_game_manager(game_manager)
	else:
		initialize_ui()

func initialize_from_game_manager(manager):
	"""Initialize lobby using data from the game manager"""
	game_manager = manager
	
	local_peer_id = manager.get_local_peer_id()
	if local_peer_id == 0:
		local_peer_id = 1
	
	copy_player_data_from_manager()
	copy_settings_from_manager()
	connect_manager_signals()
	initialize_ui()
	update_player_list()
	update_start_button_visibility()
	set_character_info()

func copy_player_data_from_manager():
	"""Copy player data from the game manager to local storage"""
	player_data.clear()
	var players = game_manager.get_players()
	for player_id in players:
		var player = players[player_id]
		player_data[player_id] = {
			"name": player.name,
			"ready": player.ready,
			"character": player.get("customization", {})
		}

func copy_settings_from_manager():
	"""Copy game settings from the game manager"""
	selected_map = game_manager.current_map
	selected_mode = game_manager.current_game_mode_setting

func connect_manager_signals():
	"""Connect game manager signals for player and game state updates"""
	var signal_connections = [
		["player_registered", "_on_player_registered"],
		["player_unregistered", "_on_player_unregistered"],
		["player_ready_status_changed", "_on_player_ready_status_changed"],
		["player_connected", "_on_player_connected"],
		["player_disconnected", "_on_player_disconnected"],
		["server_disconnected", "_on_server_disconnected"]
	]
	
	for connection in signal_connections:
		var signal_name = connection[0]
		var method_name = connection[1]
		
		if game_manager.has_signal(signal_name):
			if not game_manager.is_connected(signal_name, Callable(self, method_name)):
				game_manager.connect(signal_name, Callable(self, method_name))

func set_character_info():
	"""Set the character information display"""
	var character_name = "Unknown"
	if player_data.has(local_peer_id):
		var player = player_data[local_peer_id]
		if "name" in player:
			character_name = player.name
		elif "character" in player and "name" in player.character:
			character_name = player.character.name
	
	character_info.text = "Character: " + character_name

func initialize_ui():
	"""Initialize UI elements with default values"""
	countdown_label.visible = false
	status_label.text = "Waiting for players..."
	
	player_list.clear()
	
	update_dropdown_selections()
	update_start_button_visibility()

func update_dropdown_selections():
	"""Update map and mode dropdown selections to match current settings"""
	for i in range(map_option.get_item_count()):
		if map_option.get_item_text(i) == selected_map:
			map_option.selected = i
			break
	
	for i in range(mode_option.get_item_count()):
		if mode_option.get_item_text(i) == selected_mode:
			mode_option.selected = i
			break

func update_player_list():
	"""Rebuild the player list display with current player data"""
	player_list.clear()
	
	for peer_id in player_data.keys():
		var player = player_data[peer_id]
		var ready_status = " [READY]" if player.ready else " [NOT READY]"
		var name_text = player.name + ready_status
		
		var is_local = peer_id == local_peer_id
		var is_player_host = is_host_peer(peer_id)
		
		if is_local:
			name_text += " (You)"
		if is_player_host:
			name_text += " (Host)"
		
		player_list.add_item(name_text)

func is_host_peer(peer_id: int) -> bool:
	"""Check if a specific peer is the host"""
	if game_manager:
		if game_manager.is_single_player():
			return peer_id == local_peer_id
		elif game_manager.is_multiplayer():
			return peer_id == 1
	
	return peer_id == 1

func is_local_player_host() -> bool:
	"""Check if the local player is the host"""
	if game_manager:
		if game_manager.is_single_player():
			return true
		elif game_manager.is_multiplayer_host():
			return true
		else:
			return false
	
	return local_peer_id == 1

func update_start_button_visibility():
	"""Update start button visibility and state based on host status and player readiness"""
	var is_host = is_local_player_host()
	
	start_game_button.visible = is_host
	
	map_option.disabled = not is_host
	mode_option.disabled = not is_host
	
	if is_host:
		start_game_button.disabled = not all_players_ready
	else:
		start_game_button.visible = false
	
	update_status_text()

func update_status_text():
	"""Update the status label text based on current lobby state"""
	if game_manager:
		if game_manager.is_single_player():
			status_label.text = "Single Player - Ready to start!"
		elif is_local_player_host():
			if all_players_ready:
				status_label.text = "All players ready - Ready to start!"
			else:
				status_label.text = "Waiting for all players to be ready..."
		else:
			status_label.text = "Waiting for host to start the game..."

func check_all_players_ready():
	"""Check if all players are ready and update UI accordingly"""
	all_players_ready = true
	
	if game_manager and game_manager.is_single_player():
		all_players_ready = true
	else:
		for peer_id in player_data.keys():
			if not player_data[peer_id].ready:
				all_players_ready = false
				break
	
	update_start_button_visibility()

func start_countdown():
	"""Begin the game start countdown sequence"""
	is_countdown_active = true
	countdown_time = 5
	countdown_label.visible = true
	countdown_label.text = str(countdown_time)
	
	status_label.text = "Game starting in " + str(countdown_time) + " seconds..."
	
	process_countdown()

func process_countdown():
	"""Process the countdown timer and handle game start"""
	if not is_countdown_active:
		return
	
	await get_tree().create_timer(1.0).timeout
	
	countdown_time -= 1
	countdown_label.text = str(countdown_time)
	
	if countdown_time <= 0:
		is_countdown_active = false
		emit_signal("start_game", selected_map, selected_mode)
	else:
		process_countdown()

func _on_back_button_pressed():
	"""Handle back button press to return to previous menu"""
	if is_transitioning_to_game:
		return
		
	if game_manager:
		if game_manager.is_multiplayer():
			game_manager.disconnect_from_game()
	
	emit_signal("back_pressed")

func _on_ready_button_pressed():
	"""Handle ready button press to toggle player ready status"""
	player_ready = not player_ready
	
	if game_manager:
		var peer_id = game_manager.get_local_peer_id()
		if peer_id == 0:
			peer_id = 1
		
		ready_button.text = "Cancel Ready" if player_ready else "Ready"
		
		if peer_id in player_data:
			player_data[peer_id].ready = player_ready
		
		if game_manager.has_method("set_player_ready"):
			game_manager.set_player_ready(peer_id, player_ready)
		
		update_player_list()
		
		if game_manager.is_single_player() and player_ready:
			check_all_players_ready()
	else:
		handle_ready_fallback()

func handle_ready_fallback():
	"""Handle ready status when game manager is unavailable"""
	var peer_id = local_peer_id
	
	if peer_id in player_data:
		player_data[peer_id].ready = player_ready
		
	ready_button.text = "Cancel Ready" if player_ready else "Ready"
	update_player_list()
	check_all_players_ready()

func _on_start_game_button_pressed():
	"""Handle start game button press"""
	if not is_local_player_host():
		return
	
	if game_manager and game_manager.is_single_player():
		if player_ready:
			game_manager.start_game(selected_map, selected_mode)
		else:
			status_label.text = "Please ready up before starting the game"
		return
	
	if not all_players_ready:
		status_label.text = "Cannot start: Not all players are ready"
		return
	
	if game_manager:
		game_manager.start_game(selected_map, selected_mode)
	else:
		start_countdown()

func _on_map_selected(index):
	"""Handle map selection change"""
	selected_map = map_option.get_item_text(index)
	
	if game_manager and is_local_player_host():
		game_manager.current_map = selected_map
		
		if game_manager.is_multiplayer() and game_manager.has_method("sync_game_settings"):
			game_manager.sync_game_settings.rpc(selected_map, selected_mode)

func _on_mode_selected(index):
	"""Handle game mode selection change"""
	selected_mode = mode_option.get_item_text(index)
	
	if game_manager and is_local_player_host():
		game_manager.current_game_mode_setting = selected_mode
		
		if game_manager.is_multiplayer() and game_manager.has_method("sync_game_settings"):
			game_manager.sync_game_settings.rpc(selected_map, selected_mode)

@rpc("authority", "call_local", "reliable")
func sync_game_settings(map_name: String, game_mode: String):
	"""Receive game settings synchronization from host"""
	update_game_settings(map_name, game_mode)

func update_game_settings(map_name, game_mode):
	"""Update local game settings with values from host"""
	selected_map = map_name
	selected_mode = game_mode
	
	update_dropdown_selections()

func _on_player_registered(peer_id, player_name):
	"""Handle notification of new player registration"""
	if not player_data.has(peer_id):
		player_data[peer_id] = {
			"name": player_name,
			"ready": false,
			"character": {}
		}
	else:
		player_data[peer_id].name = player_name
	
	update_player_list()
	
	if game_manager and game_manager.is_single_player():
		status_label.text = "Welcome, " + player_name + "!"
	else:
		status_label.text = player_name + " has joined"

func _on_player_unregistered(peer_id):
	"""Handle notification of player leaving"""
	if player_data.has(peer_id):
		var player_name = player_data[peer_id].name
		player_data.erase(peer_id)
		
		update_player_list()
		check_all_players_ready()
		
		if game_manager and game_manager.is_multiplayer():
			status_label.text = player_name + " has left"

func _on_player_ready_status_changed(peer_id, is_ready):
	"""Handle notification of player ready status change"""
	if player_data.has(peer_id):
		player_data[peer_id].ready = is_ready
	
	if peer_id == local_peer_id:
		player_ready = is_ready
		ready_button.text = "Cancel Ready" if player_ready else "Ready"
	
	update_player_list()
	check_all_players_ready()

func _on_player_connected(peer_id):
	"""Handle notification of player connection"""
	if game_manager and game_manager.is_multiplayer():
		status_label.text = "Player " + str(peer_id) + " connected"

func _on_player_disconnected(peer_id):
	"""Handle notification of player disconnection"""
	if game_manager and game_manager.is_multiplayer():
		status_label.text = "Player " + str(peer_id) + " disconnected"

func _on_server_disconnected():
	"""Handle notification of server disconnection"""
	status_label.text = "Disconnected from host"
	
	await get_tree().create_timer(2.0).timeout
	emit_signal("back_pressed")

func _on_character_data_updated(peer_id: int, character_data: Dictionary):
	"""Handle character data updates from other players"""
	if player_data.has(peer_id):
		player_data[peer_id].character = character_data
		
		if "name" in character_data and character_data.name != player_data[peer_id].name:
			player_data[peer_id].name = character_data.name
			update_player_list()
		
		if peer_id == local_peer_id:
			var character_name = character_data.get("name", "Unknown")
			character_info.text = "Character: " + character_name
