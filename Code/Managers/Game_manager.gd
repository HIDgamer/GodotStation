extends Node

# Scene paths
const MAIN_MENU_SCENE = "res://Scenes/UI/Menus/Settings.tscn"
const NETWORK_UI_SCENE = "res://Scenes/UI/Menus/network_ui.tscn"
const LOBBY_SCENE = "res://Scenes/UI/Menus/lobby_ui.tscn"
const WORLD_SCENE = "res://Scenes/Maps/Zypharion.tscn" 
const PLAYER_SCENE_PATH = "res://Scenes/Characters/human.tscn"
const DEFAULT_PORT = 7777
const MAX_PLAYERS = 16

enum GameState {MAIN_MENU, NETWORK_SETUP, LOBBY, PLAYING, GAME_OVER, SETTINGS}
enum GameMode {SINGLE_PLAYER, MULTIPLAYER_HOST, MULTIPLAYER_CLIENT}

# Game state
var current_state = GameState.MAIN_MENU
var previous_state = GameState.MAIN_MENU
var current_game_mode = GameMode.SINGLE_PLAYER

# Scene instances
var main_menu_instance = null
var network_ui_instance = null
var lobby_instance = null
var world_instance = null
var settings_instance = null

# Player information
var players = {}
var local_player_id = 1
var local_player_instance = null

# Game settings
var current_map = "Station"
var current_game_mode_setting = "Standard"
var map_paths = {
	"Station": "res://Scenes/Maps/Zypharion.tscn",
	"Outpost": "res://Scenes/Maps/Outpost.tscn",
	"Research": "res://Scenes/Maps/Research.tscn"
}

# Character data
var character_data = {}

# Multiplayer
var player_scene = null
var connected_peers = []
var network_peer = null
var connection_in_progress = false
var spawn_points = []
var next_spawn_index = 0

# System references
var world_ref = null
var tile_occupancy_system = null
var spatial_manager = null
var sensory_system = null
var atmosphere_system = null
var audio_manager = null
var interaction_system = null

# Signals
signal game_state_changed(old_state, new_state)
signal player_registered(player_id, player_name)
signal player_unregistered(player_id)
signal player_ready_status_changed(player_id, is_ready)
signal world_loaded()
signal character_data_updated(data)
signal host_ready()
signal player_connected(peer_id)
signal player_disconnected(peer_id)
signal connection_failed()
signal server_disconnected()
signal systems_initialized()

func _ready():
	get_tree().paused = false
	
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	load_core_scenes()
	load_character_data()

func load_core_scenes():
	if player_scene == null:
		player_scene = load(PLAYER_SCENE_PATH)
		if player_scene == null:
			push_error("GameManager: Could not load player scene from: " + PLAYER_SCENE_PATH)

# Game mode detection
func is_single_player() -> bool:
	return current_game_mode == GameMode.SINGLE_PLAYER

func is_multiplayer_host() -> bool:
	return current_game_mode == GameMode.MULTIPLAYER_HOST

func is_multiplayer_client() -> bool:
	return current_game_mode == GameMode.MULTIPLAYER_CLIENT

func is_multiplayer() -> bool:
	return current_game_mode == GameMode.MULTIPLAYER_HOST or current_game_mode == GameMode.MULTIPLAYER_CLIENT

func setup_singleplayer_peer():
	var peer = OfflineMultiplayerPeer.new()
	multiplayer.multiplayer_peer = peer
	local_player_id = 1
	connected_peers = [1]

# World loading and setup
func load_world(map_path = WORLD_SCENE):
	get_tree().change_scene_to_file(map_path)
	await get_tree().process_frame
	await get_tree().process_frame
	
	world_instance = get_tree().current_scene
	world_ref = world_instance
	
	await get_tree().create_timer(0.1).timeout
	find_world_systems()
	find_spawn_points()
	await get_tree().create_timer(0.2).timeout
	
	match current_game_mode:
		GameMode.SINGLE_PLAYER:
			setup_singleplayer()
		GameMode.MULTIPLAYER_HOST:
			await get_tree().create_timer(0.3).timeout
			spawn_player(1)
			for peer_id in connected_peers:
				if peer_id != 1:
					spawn_player(peer_id)
		GameMode.MULTIPLAYER_CLIENT:
			pass
	
	emit_signal("world_loaded")

func find_world_systems():
	if world_instance == null:
		return
	
	tile_occupancy_system = world_instance.get_node_or_null("TileOccupancySystem")
	spatial_manager = world_instance.get_node_or_null("SpatialManager")
	sensory_system = world_instance.get_node_or_null("SensorySystem")
	atmosphere_system = world_instance.get_node_or_null("AtmosphereSystem")
	audio_manager = world_instance.get_node_or_null("AudioManager")
	
	var interaction_systems = get_tree().get_nodes_in_group("interaction_system")
	if interaction_systems.size() > 0:
		interaction_system = interaction_systems[0]
	else:
		interaction_system = world_instance.get_node_or_null("InteractionSystem")

func find_spawn_points():
	spawn_points = []
	next_spawn_index = 0
	
	if world_instance:
		var spawn_points_node = world_instance.get_node_or_null("SpawnPoints")
		if spawn_points_node:
			for child in spawn_points_node.get_children():
				spawn_points.append(child.global_position)
		
		if spawn_points.size() == 0:
			for child in world_instance.get_children():
				if child.name.begins_with("SpawnPoint"):
					spawn_points.append(child.global_position)
		
		if spawn_points.size() == 0:
			spawn_points = [Vector2(100, 100), Vector2(200, 100), Vector2(100, 200), Vector2(200, 200)]

func get_spawn_position(peer_id: int) -> Vector2:
	if spawn_points.size() == 0:
		find_spawn_points()
	
	if peer_id <= spawn_points.size():
		return spawn_points[peer_id - 1]
	
	var pos = spawn_points[next_spawn_index]
	next_spawn_index = (next_spawn_index + 1) % spawn_points.size()
	return pos

# Singleplayer setup
func setup_singleplayer():
	current_game_mode = GameMode.SINGLE_PLAYER
	setup_singleplayer_peer()
	
	if player_scene == null:
		player_scene = load(PLAYER_SCENE_PATH)
		if player_scene == null:
			return
	
	setup_local_player()

func setup_local_player():
	if multiplayer.multiplayer_peer == null:
		setup_singleplayer_peer()
	
	local_player_id = multiplayer.get_unique_id()
	
	var player_instance = player_scene.instantiate()
	player_instance.name = "LocalPlayer"
	
	player_instance.set_meta("is_player", true)
	player_instance.set_meta("is_npc", false)
	player_instance.set_meta("peer_id", local_player_id)
	player_instance.set_multiplayer_authority(local_player_id)
	
	var spawn_pos = get_spawn_position(local_player_id)
	player_instance.position = spawn_pos
	
	players[local_player_id] = {
		"id": local_player_id,
		"name": get_player_name(),
		"ready": true,
		"instance": player_instance,
		"customization": character_data.duplicate()
	}
	
	world_instance.add_child(player_instance)
	local_player_instance = player_instance
	
	setup_player_camera(player_instance, local_player_id)
	setup_player_controller(player_instance, local_player_id, true)
	
	# Apply character customization after a short delay
	await get_tree().create_timer(0.2).timeout
	apply_character_customization_to_player(player_instance, character_data)
	
	await get_tree().create_timer(0.1).timeout
	_notify_systems_of_entity_spawn(player_instance, false)

func setup_player_controller(player_instance: Node, peer_id: int, is_local: bool):
	var movement_controller = get_movement_controller(player_instance)
	
	if movement_controller:
		movement_controller.peer_id = peer_id
		movement_controller.is_local_player = is_local
		
		if is_single_player():
			if movement_controller.has_method("setup_singleplayer"):
				movement_controller.setup_singleplayer()
			elif movement_controller.has_method("initialize"):
				var init_data = create_init_data(player_instance, peer_id, is_local)
				movement_controller.initialize(init_data)
		else:
			if movement_controller.has_method("setup_multiplayer"):
				movement_controller.setup_multiplayer(peer_id)
			elif movement_controller.has_method("initialize"):
				var init_data = create_init_data(player_instance, peer_id, is_local)
				movement_controller.initialize(init_data)

func get_movement_controller(player_instance: Node) -> Node:
	var movement_controller = player_instance.get_node_or_null("MovementComponent")
	if not movement_controller:
		movement_controller = player_instance.get_node_or_null("GridMovementController")
	if not movement_controller:
		movement_controller = player_instance
	return movement_controller

func create_init_data(player_instance: Node, peer_id: int, is_local: bool) -> Dictionary:
	return {
		"controller": player_instance,
		"world": world_instance,
		"tile_occupancy_system": tile_occupancy_system,
		"sensory_system": sensory_system,
		"audio_system": audio_manager,
		"sprite_system": get_sprite_system(player_instance),
		"peer_id": peer_id,
		"is_local_player": is_local
	}

func setup_player_camera(player_instance: Node, peer_id: int):
	var camera = player_instance.get_node_or_null("Camera2D")
	if not camera:
		camera = player_instance.get_node_or_null("PlayerCamera")
		if not camera:
			camera = player_instance.get_node_or_null("Camera")
	
	if camera:
		var is_local_player = false
		
		if is_single_player():
			is_local_player = true
		else:
			var local_id = multiplayer.get_unique_id()
			is_local_player = (peer_id == local_id)
		
		camera.enabled = is_local_player
		
		if is_local_player:
			camera.make_current()

# Multiplayer hosting and joining
func host_game(port: int = DEFAULT_PORT, use_upnp: bool = true) -> bool:
	current_game_mode = GameMode.MULTIPLAYER_HOST
	
	if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer = null
	
	if MultiplayerManager:
		var success = MultiplayerManager.host_game(port, use_upnp)
		if success:
			network_peer = multiplayer.multiplayer_peer
			local_player_id = 1
			connected_peers = [1]
			
			register_player(local_player_id, get_player_name())
			
			call_deferred("emit_signal", "host_ready")
			call_deferred("show_lobby")
			
			return true
		else:
			current_game_mode = GameMode.SINGLE_PLAYER
			return false
	else:
		return host_game_manual(port, use_upnp)

func host_game_manual(port: int = DEFAULT_PORT, use_upnp: bool = true) -> bool:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	
	if error != OK:
		current_game_mode = GameMode.SINGLE_PLAYER
		return false
	
	if use_upnp:
		setup_upnp(port)
	
	multiplayer.multiplayer_peer = peer
	network_peer = peer
	local_player_id = 1
	connected_peers = [1]
	
	register_player(local_player_id, get_player_name())
	
	call_deferred("emit_signal", "host_ready")
	call_deferred("show_lobby")
	
	return true

func join_game(address: String, port: int = DEFAULT_PORT) -> bool:
	if connection_in_progress:
		return false
	
	current_game_mode = GameMode.MULTIPLAYER_CLIENT
	
	if MultiplayerManager:
		var success = MultiplayerManager.join_game(address, port)
		if success:
			network_peer = multiplayer.multiplayer_peer
			connection_in_progress = true
			return true
		else:
			current_game_mode = GameMode.SINGLE_PLAYER
			return false
	else:
		return join_game_manual(address, port)

func join_game_manual(address: String, port: int = DEFAULT_PORT) -> bool:
	connection_in_progress = true
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	
	if error != OK:
		connection_in_progress = false
		current_game_mode = GameMode.SINGLE_PLAYER
		return false
	
	multiplayer.multiplayer_peer = peer
	network_peer = peer
	
	return true

func disconnect_from_game():
	if MultiplayerManager:
		MultiplayerManager.disconnect_from_game()
	
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
		network_peer = null
	
	current_game_mode = GameMode.SINGLE_PLAYER
	connected_peers = []
	connection_in_progress = false
	players.clear()

# Player spawning
func spawn_player(peer_id: int):
	if is_multiplayer() and not is_multiplayer_host():
		return
		
	if is_single_player():
		if peer_id == local_player_id:
			setup_local_player()
	else:
		if MultiplayerManager:
			var spawn_pos = get_spawn_position(peer_id)
			var customization = get_player_customization(peer_id)
			MultiplayerManager.spawn_player(peer_id, spawn_pos, customization)
		else:
			spawn_player_on_network.rpc(peer_id, get_spawn_position(peer_id))

@rpc("authority", "call_local", "reliable")
func spawn_player_on_network(peer_id: int, spawn_position: Vector2):
	if MultiplayerManager:
		var character_data = get_player_customization(peer_id)
		MultiplayerManager.spawn_player_for_peer.rpc(peer_id, spawn_position, character_data)
	else:
		spawn_player_legacy(peer_id, spawn_position)

func spawn_player_legacy(peer_id: int, spawn_position: Vector2):
	if player_scene == null:
		player_scene = load(PLAYER_SCENE_PATH)
		if player_scene == null:
			return
	
	var player_instance = player_scene.instantiate()
	player_instance.name = str(peer_id)
	
	player_instance.set_meta("is_player", true)
	player_instance.set_meta("is_npc", false)
	player_instance.set_meta("peer_id", peer_id)
	player_instance.set_multiplayer_authority(peer_id)
	player_instance.position = spawn_position
	
	var customization = get_player_customization(peer_id)
	
	var world = get_tree().current_scene
	if is_instance_valid(world):
		world.add_child(player_instance)
		
		await get_tree().create_timer(0.2).timeout
		
		setup_player_camera(player_instance, peer_id)
		
		var is_local = (peer_id == multiplayer.get_unique_id())
		setup_player_controller(player_instance, peer_id, is_local)
		
		if peer_id in players:
			players[peer_id].instance = player_instance
		
		apply_character_customization_to_player(player_instance, customization)
		
		await get_tree().create_timer(0.1).timeout
		_notify_systems_of_entity_spawn(get_movement_controller(player_instance), false)
	else:
		player_instance.queue_free()

func _notify_systems_of_entity_spawn(entity_controller, is_npc: bool = false):
	if tile_occupancy_system and tile_occupancy_system.has_method("register_entity_at_tile"):
		var pos = entity_controller.get_current_tile_position()
		var z_level = entity_controller.current_z_level
		tile_occupancy_system.register_entity_at_tile(entity_controller, pos, z_level)
	
	if spatial_manager and spatial_manager.has_method("register_entity"):
		spatial_manager.register_entity(entity_controller)
	
	if not is_npc:
		if interaction_system and interaction_system.has_method("register_player"):
			interaction_system.register_player(entity_controller, true)
		
		var click_handlers = get_tree().get_nodes_in_group("click_system")
		for handler in click_handlers:
			if handler.has_method("set_player_reference"):
				handler.set_player_reference(entity_controller)
		
		var player_systems = get_tree().get_nodes_in_group("player_aware_system")
		for system in player_systems:
			if system.has_method("register_player"):
				system.register_player(entity_controller)
	
	emit_signal("systems_initialized")

# Character customization system
func get_sprite_system(player_instance: Node) -> Node:
	var sprite_system = null
	
	var possible_paths = [
		"SpriteSystem",
		"sprite_system", 
		"Sprite",
		"CharacterSprite",
		"Visuals/SpriteSystem",
		"HumanSpriteSystem"
	]
	
	for path in possible_paths:
		sprite_system = player_instance.get_node_or_null(path)
		if sprite_system:
			break
	
	return sprite_system

func apply_character_customization_to_player(player_instance: Node, customization: Dictionary):
	if customization.size() == 0:
		return
	
	var sprite_system = get_sprite_system(player_instance)
	
	if sprite_system:
		if sprite_system.has_method("apply_character_data"):
			sprite_system.apply_character_data(customization)
		elif sprite_system.has_method("apply_customization"):
			sprite_system.apply_customization(customization)

# Character data management
func set_character_data(data):
	print("GameManager: Setting character data with ", data.size(), " properties")
	character_data = data.duplicate()
	
	# Save immediately
	save_character_data()
	
	# Update player data
	var player_id = get_local_peer_id()
	if player_id == 0:
		player_id = 1  # Fallback for singleplayer
	
	if player_id in players:
		players[player_id].customization = character_data.duplicate()
		
		# Update name if it changed
		if "name" in character_data:
			players[player_id].name = character_data.name
	else:
		# Create player entry if it doesn't exist
		players[player_id] = {
			"id": player_id,
			"name": get_player_name(),
			"ready": false,
			"instance": null,
			"customization": character_data.duplicate()
		}
	
	# Sync in multiplayer
	if is_multiplayer():
		sync_character_data.rpc(player_id, character_data.duplicate())
	
	# Apply to existing player if spawned
	if local_player_instance and is_instance_valid(local_player_instance):
		apply_character_customization_to_player(local_player_instance, character_data)
	
	emit_signal("character_data_updated", character_data)
	print("GameManager: Character data set and saved successfully")

func get_character_data():
	return character_data.duplicate()

func save_character_data():
	var file = FileAccess.open("user://character_data.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(character_data))
		file.close()
		print("GameManager: Character data saved to disk")
	else:
		print("GameManager: Failed to save character data to disk")

func load_character_data():
	if not FileAccess.file_exists("user://character_data.json"):
		print("GameManager: No character data file found")
		return false
	
	var file = FileAccess.open("user://character_data.json", FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()
		
		var json_result = JSON.parse_string(json_string)
		
		if json_result:
			character_data = json_result
			print("GameManager: Character data loaded from disk with ", character_data.size(), " properties")
			return true
		else:
			print("GameManager: Failed to parse character data JSON")
	else:
		print("GameManager: Failed to open character data file")
	
	return false

func reapply_character_customization():
	print("GameManager: Providing character customization data: ", character_data.size(), " items")
	return character_data.duplicate()

# Multiplayer character data sync
@rpc("any_peer", "call_local", "reliable")
func sync_character_data(peer_id: int, character_customization: Dictionary):
	print("GameManager: Syncing character data for peer ", peer_id)
	
	if peer_id in players:
		players[peer_id].customization = character_customization.duplicate()
		
		# Update name if provided
		if "name" in character_customization:
			players[peer_id].name = character_customization.name
		
		# Apply to existing player instance
		if "instance" in players[peer_id] and players[peer_id].instance:
			var player_instance = players[peer_id].instance
			if is_instance_valid(player_instance):
				apply_character_customization_to_player(player_instance, character_customization)
	
	# Update lobby if available
	update_lobby_ui()

@rpc("any_peer", "call_local", "reliable")
func sync_game_settings(map_name: String, game_mode: String):
	"""Sync game settings across all clients"""
	print("GameManager: Syncing game settings - Map: ", map_name, " Mode: ", game_mode)
	
	current_map = map_name
	current_game_mode_setting = game_mode
	
	# Update lobby if available
	if lobby_instance and is_instance_valid(lobby_instance):
		if lobby_instance.has_method("update_game_settings"):
			lobby_instance.update_game_settings(map_name, game_mode)

@rpc("any_peer", "call_local", "reliable")
func request_character_data(requesting_peer_id: int):
	"""Request character data from all players (called by new clients)"""
	if is_multiplayer_host():
		# Send all player character data to the requesting peer
		for player_id in players:
			if "customization" in players[player_id]:
				sync_character_data.rpc_id(requesting_peer_id, player_id, players[player_id].customization)

# Player management
func get_local_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 1  # Singleplayer default
	return multiplayer.get_unique_id()

func get_players():
	return players

func get_player_data(player_id):
	if player_id in players:
		return players[player_id]
	return null

func register_player(player_id, player_name):
	if not player_id in players:
		players[player_id] = {
			"id": player_id,
			"name": player_name,
			"ready": false,
			"instance": null,
			"customization": character_data.duplicate() if character_data.size() > 0 else {}
		}
		
		if is_multiplayer():
			var player_info = {
				"name": player_name,
				"customization": character_data.duplicate() if character_data.size() > 0 else {}
			}
			network_register_player.rpc(player_id, player_info)
		
		emit_signal("player_registered", player_id, player_name)
		update_lobby_ui()

func unregister_player(player_id):
	if player_id in players:
		players.erase(player_id)
		emit_signal("player_unregistered", player_id)
		update_lobby_ui()

func set_player_ready(player_id, is_ready):
	"""Set a player's ready status"""
	if player_id in players:
		players[player_id].ready = is_ready
		
		# Update ready status on the network if in multiplayer
		if is_multiplayer():
			network_set_player_ready.rpc(player_id, is_ready)
		
		emit_signal("player_ready_status_changed", player_id, is_ready)
		update_lobby_ui()

func check_all_players_ready() -> bool:
	"""Check if all players are ready"""
	var all_ready = true
	
	for player_id in players:
		if !players[player_id].ready:
			all_ready = false
			break
	
	return all_ready

func get_player_name():
	if "name" in character_data:
		return character_data.name
	return "Player"

func get_player_customization(player_id):
	if player_id in players and "customization" in players[player_id] and players[player_id].customization.size() > 0:
		return players[player_id].customization
	
	if character_data.size() > 0:
		return character_data
	
	return {}

@rpc("any_peer", "call_local", "reliable")
func network_register_player(player_id, player_info):
	var player_name = player_info.name if "name" in player_info else "Player" + str(player_id)
	var customization = player_info.customization if "customization" in player_info else {}
	
	if not player_id in players:
		players[player_id] = {
			"id": player_id,
			"name": player_name,
			"ready": false,
			"instance": null,
			"customization": customization
		}
		
		emit_signal("player_registered", player_id, player_name)
		update_lobby_ui()

@rpc("any_peer", "call_local", "reliable")
func network_set_player_ready(player_id, is_ready):
	"""Network RPC to set player ready status"""
	print("GameManager: RPC set player ready", player_id, is_ready)
	
	if player_id in players:
		players[player_id].ready = is_ready
		
		emit_signal("player_ready_status_changed", player_id, is_ready)
		update_lobby_ui()
		
		# Check if all players are ready
		check_all_players_ready()

# Signal handlers
func _on_peer_connected(peer_id: int):
	connected_peers.append(peer_id)
	
	if is_multiplayer_host():
		# Send existing players data to the new peer
		for pid in players:
			var player_info = {
				"name": players[pid].name,
				"customization": players[pid].customization if "customization" in players[pid] else {}
			}
			network_register_player.rpc_id(peer_id, pid, player_info)
		
		# If in-game, spawn players
		if current_state == GameState.PLAYING:
			await get_tree().create_timer(1.0).timeout
			
			for existing_peer_id in connected_peers:
				if existing_peer_id != peer_id:
					spawn_player_for_peer(existing_peer_id, peer_id)
			
			spawn_player(peer_id)
	
	emit_signal("player_connected", peer_id)

func _on_peer_disconnected(peer_id: int):
	if connected_peers.has(peer_id):
		connected_peers.erase(peer_id)
	
	if MultiplayerManager:
		MultiplayerManager.despawn_player(peer_id)
	else:
		remove_player_instance(peer_id)
	
	unregister_player(peer_id)
	emit_signal("player_disconnected", peer_id)

func _on_connected_to_server():
	local_player_id = multiplayer.get_unique_id()
	connection_in_progress = false
	
	# Register ourselves with the server including character data
	var player_info = {
		"name": get_player_name(),
		"customization": character_data.duplicate()
	}
	network_register_player.rpc(local_player_id, player_info)
	
	# Request character data from other players
	request_character_data.rpc(local_player_id)
	
	call_deferred("show_lobby")

func _on_connection_failed():
	multiplayer.multiplayer_peer = null
	network_peer = null
	connection_in_progress = false
	current_game_mode = GameMode.SINGLE_PLAYER
	emit_signal("connection_failed")

func _on_server_disconnected():
	multiplayer.multiplayer_peer = null
	network_peer = null
	connection_in_progress = false
	current_game_mode = GameMode.SINGLE_PLAYER
	players.clear()
	emit_signal("server_disconnected")
	call_deferred("return_to_main_menu")

func spawn_player_for_peer(existing_peer_id: int, new_peer_id: int):
	if MultiplayerManager:
		var spawn_pos = get_spawn_position(existing_peer_id)
		var customization = get_player_customization(existing_peer_id)
		MultiplayerManager.spawn_player_for_peer.rpc_id(new_peer_id, existing_peer_id, spawn_pos, customization)

func remove_player_instance(peer_id: int):
	var world = get_tree().current_scene
	if is_instance_valid(world):
		var player_node = world.get_node_or_null(str(peer_id))
		if player_node:
			player_node.queue_free()
	
	if peer_id in players:
		players[peer_id].instance = null

# Utility functions
func setup_upnp(port: int) -> bool:
	var upnp = UPNP.new()
	var discover_result = upnp.discover()
	
	if discover_result != UPNP.UPNP_RESULT_SUCCESS:
		return false
	
	if upnp.get_gateway() and upnp.get_gateway().is_valid_gateway():
		var map_result_udp = upnp.add_port_mapping(port, port, "Multiplayer Game UDP", "UDP", 0)
		var map_result_tcp = upnp.add_port_mapping(port, port, "Multiplayer Game TCP", "TCP", 0)
		
		if map_result_udp != UPNP.UPNP_RESULT_SUCCESS or map_result_tcp != UPNP.UPNP_RESULT_SUCCESS:
			return false
		
		return true
	
	return false

# UI Management
func change_state(new_state):
	var old_state = current_state
	current_state = new_state
	emit_signal("game_state_changed", old_state, new_state)

func show_main_menu():
	clear_current_ui()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
	change_state(GameState.MAIN_MENU)

func show_network_ui():
	clear_current_ui()
	get_tree().change_scene_to_file(NETWORK_UI_SCENE)
	change_state(GameState.NETWORK_SETUP)

func show_lobby():
	clear_current_ui()
	get_tree().change_scene_to_file(LOBBY_SCENE)
	
	await get_tree().process_frame
	lobby_instance = get_tree().current_scene
	
	if lobby_instance:
		if lobby_instance.has_signal("back_pressed") and !lobby_instance.is_connected("back_pressed", Callable(self, "show_network_ui")):
			lobby_instance.back_pressed.connect(show_network_ui)
			
		if lobby_instance.has_signal("start_game") and !lobby_instance.is_connected("start_game", Callable(self, "start_game")):
			lobby_instance.start_game.connect(start_game)
		
		if lobby_instance.has_method("initialize_from_game_manager"):
			lobby_instance.initialize_from_game_manager(self)
	
	change_state(GameState.LOBBY)

func start_game(map_name = "", game_mode = ""):
	if map_name == "":
		map_name = current_map
	
	if game_mode == "":
		game_mode = current_game_mode_setting
	
	var map_path = map_paths.get(map_name, WORLD_SCENE)
	
	if is_multiplayer() and is_multiplayer_host():
		network_start_game_countdown.rpc()
		await get_tree().create_timer(5.0).timeout
		network_start_game.rpc(map_name)
	elif is_single_player():
		load_world(map_path)
		change_state(GameState.PLAYING)

func return_to_main_menu():
	disconnect_from_game()
	players.clear()
	show_main_menu()

func clear_current_ui():
	main_menu_instance = null
	network_ui_instance = null
	lobby_instance = null
	settings_instance = null

func update_lobby_ui():
	if lobby_instance and is_instance_valid(lobby_instance):
		if lobby_instance.has_method("update_player_list"):
			lobby_instance.update_player_list()

# Game settings management
func update_game_settings(map_name: String, game_mode: String):
	"""Update game settings and sync to all clients"""
	current_map = map_name
	current_game_mode_setting = game_mode
	
	# Sync in multiplayer
	if is_multiplayer() and is_multiplayer_host():
		sync_game_settings.rpc(map_name, game_mode)
	
	# Update lobby UI
	update_lobby_ui()

@rpc("authority", "call_local", "reliable")
func network_start_game_countdown():
	if lobby_instance and is_instance_valid(lobby_instance):
		if lobby_instance.has_method("start_countdown"):
			lobby_instance.start_countdown()

@rpc("authority", "call_local", "reliable")
func network_start_game(map_name):
	var map_path = map_paths.get(map_name, WORLD_SCENE)
	load_world(map_path)
	change_state(GameState.PLAYING)
