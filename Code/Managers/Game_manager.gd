extends Node

# ==== CONSTANTS ====
# Scene paths
const MAIN_MENU_SCENE = "res://Scenes/UI/Menus/Settings.tscn"
const NETWORK_UI_SCENE = "res://Scenes/UI/Menus/network_ui.tscn"
const LOBBY_SCENE = "res://Scenes/UI/Menus/lobby_ui.tscn"
const WORLD_SCENE = "res://Scenes/Maps/Zypharion.tscn" 
const PLAYER_SCENE_PATH = "res://Scenes/Characters/human.tscn"
const DEFAULT_PORT = 7777
const MAX_PLAYERS = 16

# ==== ENUMS ====
enum GameState {MAIN_MENU, NETWORK_SETUP, LOBBY, PLAYING, GAME_OVER, SETTINGS}

# ==== VARIABLES ====
# Game state
var current_state = GameState.MAIN_MENU
var previous_state = GameState.MAIN_MENU

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
var player_camera = null

# Game settings
var current_map = "Station"
var current_game_mode = "Standard"
var map_paths = {
	"Station": "res://Scenes/Maps/Zypharion.tscn",
	"Outpost": "res://Scenes/Maps/Outpost.tscn",
	"Research": "res://Scenes/Maps/Research.tscn"
}

# Character data
var character_data = {}

# Multiplayer
var player_scene = null
var camera_scene = null
var is_host: bool = false
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

# ==== SIGNALS ====
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
signal ghost_mode_activated(ghost)
signal ghost_mode_deactivated(ghost, entity)
signal entity_possessed(ghost, entity)
signal possession_ended(ghost, entity)

# ==== INITIALIZATION ====
func _ready():
	print("GameManager: Initializing")
	
	# Make sure game is unpaused
	get_tree().paused = false
	
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	# Pre-load necessary scenes
	load_core_scenes()
	
	# Try to load character data
	load_character_data()

# Load core scenes that will be needed
func load_core_scenes():
	# Load player scene
	if player_scene == null:
		player_scene = load(PLAYER_SCENE_PATH)
		if player_scene == null:
			push_error("GameManager: Could not load player scene from: " + PLAYER_SCENE_PATH)

# ==== WORLD LOADING ====
# Load the game world with enhanced setup
func load_world(map_path = WORLD_SCENE):
	print("GameManager: Loading world:", map_path)
	
	# Change scene to the world
	get_tree().change_scene_to_file(map_path)
	
	# Wait for the scene to be fully loaded
	await get_tree().process_frame
	await get_tree().process_frame  # Wait an extra frame for stability
	
	# Get world reference
	world_instance = get_tree().current_scene
	world_ref = world_instance
	print("GameManager: Current scene loaded: " + world_instance.name)
	
	# Wait for world to be ready before getting systems
	await get_tree().create_timer(0.1).timeout
	
	# Find and store references to important world systems
	find_world_systems()
	
	# Find spawn points in the world
	find_spawn_points()
	print("GameManager: Found " + str(spawn_points.size()) + " spawn points")
	
	# Wait a bit more for world systems to be ready
	await get_tree().create_timer(0.2).timeout
	
	# Setup based on multiplayer or single player
	if network_peer and is_host:
		# Multiplayer host mode - spawn all connected peers
		await get_tree().create_timer(0.3).timeout
		for peer_id in connected_peers:
			spawn_player(peer_id)
	elif network_peer:
		# Multiplayer client mode - wait for server to spawn us
		print("GameManager: Client waiting for server to spawn player")
	else:
		# Singleplayer mode - spawn the local player
		print("GameManager: Setting up singleplayer mode")
		setup_singleplayer()
	
	emit_signal("world_loaded")

# Find and store references to important world systems
func find_world_systems():
	if world_instance == null:
		push_error("GameManager: Cannot find world systems - world_instance is null")
		return
	
	# Find essential systems
	tile_occupancy_system = world_instance.get_node_or_null("TileOccupancySystem")
	spatial_manager = world_instance.get_node_or_null("SpatialManager")
	sensory_system = world_instance.get_node_or_null("SensorySystem")
	atmosphere_system = world_instance.get_node_or_null("AtmosphereSystem")
	audio_manager = world_instance.get_node_or_null("AudioManager")
	
	# Find interaction system (might be in different places)
	var interaction_systems = get_tree().get_nodes_in_group("interaction_system")
	if interaction_systems.size() > 0:
		interaction_system = interaction_systems[0]
	else:
		interaction_system = world_instance.get_node_or_null("InteractionSystem")
	
	print("GameManager: World systems lookup complete")
	log_system_status()

# Log the status of found systems
func log_system_status():
	print("--- System Status ---")
	print("TileOccupancySystem: ", "Found" if tile_occupancy_system else "Missing")
	print("SpatialManager: ", "Found" if spatial_manager else "Missing")
	print("SensorySystem: ", "Found" if sensory_system else "Missing")
	print("AtmosphereSystem: ", "Found" if atmosphere_system else "Missing")
	print("AudioManager: ", "Found" if audio_manager else "Missing")
	print("InteractionSystem: ", "Found" if interaction_system else "Missing")
	print("--------------------")

# Find spawn points in the world
func find_spawn_points():
	spawn_points = []
	next_spawn_index = 0
	
	# Look for spawn point nodes in the world
	if world_instance:
		# First try to find a SpawnPoints node that might contain spawn points
		var spawn_points_node = world_instance.get_node_or_null("SpawnPoints")
		if spawn_points_node:
			# Add all children of the SpawnPoints node as spawn positions
			for child in spawn_points_node.get_children():
				spawn_points.append(child.global_position)
		
		# If no spawn points found, look for nodes named "SpawnPoint*"
		if spawn_points.size() == 0:
			for child in world_instance.get_children():
				if child.name.begins_with("SpawnPoint"):
					spawn_points.append(child.global_position)
		
		# If still no spawn points, add default locations
		if spawn_points.size() == 0:
			# Add some default spawn positions
			spawn_points = [
				Vector2(100, 100),
				Vector2(200, 100),
				Vector2(100, 200),
				Vector2(200, 200)
			]
	
	print("GameManager: Found", spawn_points.size(), "spawn points")

# Get a spawn position for a player
func get_spawn_position(peer_id: int) -> Vector2:
	# Make sure spawn points are initialized
	if spawn_points.size() == 0:
		find_spawn_points()
	
	# If we have specific spawn point for this peer, use it
	if peer_id < spawn_points.size():
		return spawn_points[peer_id]
	
	# Otherwise, use round-robin assignment
	var pos = spawn_points[next_spawn_index]
	next_spawn_index = (next_spawn_index + 1) % spawn_points.size()
	return pos

# ==== PLAYER SETUP ====
# Setup singleplayer mode
func setup_singleplayer():
	# Ensure player scene is loaded
	if player_scene == null:
		player_scene = load(PLAYER_SCENE_PATH)
		if player_scene == null:
			push_error("GameManager: Could not load player scene for singleplayer!")
			return
	setup_normal_player()
	
	print("GameManager: Singleplayer setup complete")

# Normal player setup (non-debug mode)
func setup_normal_player():
	# Create player instance
	var player_instance = player_scene.instantiate()
	player_instance.name = "LocalPlayer"
	
	# Get spawn position
	var spawn_pos = get_spawn_position(1)  # Use ID 1 for singleplayer
	player_instance.position = spawn_pos
	print("GameManager: Player spawn position: ", spawn_pos)
	
	# Store player in players dictionary for singleplayer
	players[1] = {
		"id": 1,
		"name": get_player_name(),
		"ready": true,
		"instance": player_instance,
		"customization": character_data.duplicate() if character_data.size() > 0 else {}
	}
	
	# Add player to the current scene
	print("GameManager: Adding player to scene: " + world_instance.name)
	world_instance.add_child(player_instance)
	
	# Store local player reference
	local_player_instance = player_instance
	
	# Check for existing camera in the player
	var existing_camera = player_instance.get_node_or_null("Camera2D")
	if existing_camera:
		# Use existing camera
		print("GameManager: Using existing camera on player")
		existing_camera.enabled = true
		player_camera = existing_camera
	
	# Initialize player for singleplayer
	print("GameManager: Setting up player for singleplayer")
	var grid_controller = player_instance
	if grid_controller:
		# Setup for singleplayer
		if grid_controller.has_method("setup_singleplayer"):
			grid_controller.setup_singleplayer()
			print("GameManager: Player setup complete via setup_singleplayer()")
		else:
			print("GameManager: WARNING - GridMovementController has no setup_singleplayer method!")
			# Fallback manual setup
			grid_controller.set_local_player(true)
	else:
		print("GameManager: WARNING - Player has no GridMovementController!")
	
	# Setup input controller if not already present
	var input_controller = player_instance.get_node_or_null("InputController")
	if input_controller == null:
		setup_input_controller_for_entity(player_instance)
	else:
		# Ensure input controller is connected to entity
		if input_controller.has_method("connect_to_entity"):
			input_controller.connect_to_entity(grid_controller)
	
	# Register with systems after a short delay
	await get_tree().create_timer(0.2).timeout
	_notify_systems_of_player_spawn(player_instance)

# Helper function to setup input controller for any entity
func setup_input_controller_for_entity(entity_instance):
	print("GameManager: Setting up InputController for entity")
	
	# Check for GridMovementController
	var grid_controller = entity_instance
	if grid_controller == null:
		push_error("GameManager: Cannot setup InputController - no GridMovementController found!")
		return
	
	# Check for existing InputController
	var input_controller = entity_instance.get_node_or_null("InputController")
	if input_controller == null:
		# Create input controller
		var InputControllerClass = load("res://Scripts/InputController.gd")
		if InputControllerClass == null:
			push_error("GameManager: Could not load InputController script!")
			return
		
		input_controller = InputControllerClass.new()
		input_controller.name = "InputController"
		entity_instance.add_child(input_controller)
	
	# Connect to GridMovementController
	if input_controller.has_method("connect_to_entity"):
		input_controller.connect_to_entity(grid_controller)
	
	print("GameManager: InputController setup complete for", entity_instance.name)

# Notify all necessary systems about player spawn
func _notify_systems_of_player_spawn(player_instance):
	print("GameManager: Notifying systems of player spawn")
	
	# Find grid controller
	var grid_controller = player_instance
	if grid_controller == null:
		push_error("GameManager: Cannot notify systems - player has no GridMovementController!")
		return
	
	# Register with TileOccupancySystem
	if tile_occupancy_system and tile_occupancy_system.has_method("register_entity"):
		tile_occupancy_system.register_entity(grid_controller)
		print("GameManager: Registered player with TileOccupancySystem")
	
	# Register with SpatialManager
	if spatial_manager and spatial_manager.has_method("register_entity"):
		spatial_manager.register_entity(grid_controller)
		print("GameManager: Registered player with SpatialManager")
	
	# Register with InteractionSystem
	if interaction_system and interaction_system.has_method("register_player"):
		interaction_system.register_player(player_instance, true)  # true = is local player
		print("GameManager: Registered player with InteractionSystem")
	
	# Find click handlers and set player reference
	var click_handlers = get_tree().get_nodes_in_group("click_system")
	for handler in click_handlers:
		if handler.has_method("set_player_reference"):
			handler.set_player_reference(player_instance)
			print("GameManager: Set player reference in ClickHandler")
	
	# Find other systems
	var other_systems = get_tree().get_nodes_in_group("player_aware_system")
	for system in other_systems:
		if system.has_method("register_player"):
			system.register_player(player_instance)
			print("GameManager: Registered player with system: " + system.name)
	
	# Emit systems initialized signal for any listeners
	emit_signal("systems_initialized")

# Reload systems when needed (e.g., after scene change)
func reload_systems():
	find_world_systems()
	
	# If we have a local player, ensure it's properly set up
	if local_player_instance and is_instance_valid(local_player_instance):
		_notify_systems_of_player_spawn(local_player_instance)
	
	emit_signal("systems_initialized")

# ==== CAMERA MANAGEMENT ==== 
# Helper function to explicitly toggle between cameras
func toggle_active_camera(active_entity_node, inactive_entity_node):
	print("GameManager: Toggling camera from", inactive_entity_node.name, "to", active_entity_node.name)
	
	if local_player_instance and is_instance_valid(local_player_instance) and local_player_instance.has_node("Camera2D"):
		local_player_instance.get_node("Camera2D").enabled = false
	# Now enable only the active camera
	var active_camera = active_entity_node.get_node_or_null("Camera2D")
	if active_camera:
		active_camera.enabled = true
		print("GameManager: Enabled camera on", active_entity_node.name)
	else:
		print("GameManager: WARNING - No camera found on", active_entity_node.name)

# ==== MULTIPLAYER ====
# Host a new game
func host_game(port: int = DEFAULT_PORT, use_upnp: bool = true) -> bool:
	print("GameManager: Attempting to host on port", port)
	
	# Create the server peer
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	
	if error != OK:
		print("GameManager: Failed to create server:", error)
		return false
	
	# Configure UPNP if enabled
	if use_upnp:
		setup_upnp(port)
	
	# Set as multiplayer peer
	multiplayer.multiplayer_peer = peer
	network_peer = peer
	is_host = true
	local_player_id = 1  # Host always gets ID 1
	connected_peers = [1]  # Host is always peer 1
	
	# Register local player
	register_player(1, get_player_name())
	
	# Host ready
	call_deferred("emit_signal", "host_ready")
	
	# Transition to lobby after successful host
	call_deferred("show_lobby")
	
	print("GameManager: Server started successfully on port", port)
	return true

# Join an existing game
func join_game(address: String, port: int = DEFAULT_PORT) -> bool:
	print("GameManager: Attempting to join", address, ":", port)
	
	if connection_in_progress:
		return false
	
	connection_in_progress = true
	
	# Create the client peer
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	
	if error != OK:
		print("GameManager: Failed to create client:", error)
		connection_in_progress = false
		return false
	
	# Set as multiplayer peer
	multiplayer.multiplayer_peer = peer
	network_peer = peer
	is_host = false
	
	print("GameManager: Client attempting to connect to", address, ":", port)
	return true

# Disconnect from current multiplayer game
func disconnect_from_game():
	# Clean up the multiplayer peer
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
		network_peer = null
	
	# Reset state
	is_host = false
	connected_peers = []
	connection_in_progress = false
	players.clear()
	
	print("GameManager: Disconnected from game")

# Get local player's peer ID
func get_local_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_unique_id()

# Get list of connected peers
func get_connected_peers() -> Array:
	if multiplayer.multiplayer_peer == null:
		return []
	
	var peers = multiplayer.get_peers()
	peers.append(1)  # Add server (ID 1)
	return peers

# Setup UPnP port forwarding
func setup_upnp(port: int) -> bool:
	var upnp = UPNP.new()
	var discover_result = upnp.discover()
	
	if discover_result != UPNP.UPNP_RESULT_SUCCESS:
		print("GameManager: UPNP discover failed:", discover_result)
		return false
	
	if upnp.get_gateway() and upnp.get_gateway().is_valid_gateway():
		# Try to map both UDP and TCP
		var map_result_udp = upnp.add_port_mapping(port, port, "Multiplayer Game UDP", "UDP", 0)
		var map_result_tcp = upnp.add_port_mapping(port, port, "Multiplayer Game TCP", "TCP", 0)
		
		if map_result_udp != UPNP.UPNP_RESULT_SUCCESS or map_result_tcp != UPNP.UPNP_RESULT_SUCCESS:
			print("GameManager: UPNP port mapping failed")
			return false
		
		print("GameManager: UPNP port mapping successful")
		print("GameManager: External IP:", upnp.query_external_address())
		return true
	
	print("GameManager: UPNP no valid gateway found")
	return false

# Spawn a player instance in the world
func spawn_player(peer_id: int):
	if !is_host:
		# Only the host can spawn players
		return
		
	print("GameManager: Attempting to spawn player for peer", peer_id)
	
	# Use MultiplayerSpawner to spawn the player across the network
	# This RPC call should trigger the MultiplayerSpawner
	spawn_player_on_network.rpc(peer_id, get_spawn_position(peer_id))

# Create a new RPC method that signals the MultiplayerSpawner
@rpc("authority", "call_local", "reliable")
func spawn_player_on_network(peer_id: int, spawn_position: Vector2):
	print("GameManager: Spawning player on network for peer", peer_id)
	
	# The MultiplayerSpawner will handle the instantiation,
	# but we need to instantiate the scene ourselves that will be replicated
	
	# Check if we have a valid player scene    
	if player_scene == null:
		print("GameManager: ERROR - Could not load player scene!")
		player_scene = load(PLAYER_SCENE_PATH)
		if player_scene == null:
			print("GameManager: CRITICAL ERROR - Failed to load player scene!")
			return
	
	# Create player instance
	var player_instance = player_scene.instantiate()
	
	# Set unique name based on peer ID
	player_instance.name = str(peer_id)
	
	# Set initial position
	player_instance.position = spawn_position
	
	# Get player customization
	var customization = {}
	if peer_id in players and "customization" in players[peer_id]:
		customization = players[peer_id].customization
	
	# Add player to the world
	var world = get_tree().current_scene
	if is_instance_valid(world):
		world.add_child(player_instance)
		
		# Initialize player
		if player_instance.has_method("setup_multiplayer"):
			player_instance.setup_multiplayer(peer_id)
		
		# Store player instance
		if peer_id in players:
			players[peer_id].instance = player_instance
		
		# Apply customization if possible
		if player_instance.has_node("HumanSpriteSystem"):
			var sprite_system = player_instance.get_node("HumanSpriteSystem")
			if customization.size() > 0:
				# Try apply_character_data first (correct method)
				if sprite_system.has_method("apply_character_data"):
					print("GameManager: Applying customization via apply_character_data")
					sprite_system.apply_character_data(customization)
				# Fallback to apply_customization (in case method was renamed)
				elif sprite_system.has_method("apply_customization"):
					print("GameManager: Applying customization via apply_customization")
					sprite_system.apply_customization(customization)
	else:
		print("GameManager: No valid world to add player to")
		player_instance.queue_free()

# Remove player instance
func remove_player_instance(peer_id: int):
	# Find player instance in the world
	var world = get_tree().current_scene
	if is_instance_valid(world):
		var player_node = world.get_node_or_null(str(peer_id))
		if player_node:
			player_node.queue_free()
			print("GameManager: Removed player instance for peer", peer_id)
	
	# Clear instance reference in player data
	if peer_id in players:
		players[peer_id].instance = null

# Register a player with the network (called by all peers)
@rpc("any_peer", "call_local", "reliable")
func network_register_player(player_id, player_info):
	print("GameManager: RPC register player", player_id)
	
	# Extract info from the player_info dictionary
	var player_name = player_info.name if "name" in player_info else "Player" + str(player_id)
	var customization = player_info.customization if "customization" in player_info else {}
	
	# Register the player
	if not player_id in players:
		players[player_id] = {
			"id": player_id,
			"name": player_name,
			"ready": false,
			"instance": null,
			"customization": customization
		}
		
		emit_signal("player_registered", player_id, player_name)
		
		# Update lobby if available
		update_lobby_ui()

# Set player ready status
@rpc("any_peer", "call_local", "reliable")
func network_set_player_ready(player_id, is_ready):
	print("GameManager: RPC set player ready", player_id, is_ready)
	
	if player_id in players:
		players[player_id].ready = is_ready
		
		emit_signal("player_ready_status_changed", player_id, is_ready)
		
		# Update lobby if available
		update_lobby_ui()
		
		# Check if all players are ready
		check_all_players_ready()

# Update game settings
@rpc("any_peer", "call_local", "reliable")
func network_update_game_settings(map_name, game_mode):
	print("GameManager: RPC update game settings", map_name, game_mode)
	
	current_map = map_name
	current_game_mode = game_mode
	
	# Update lobby UI if available
	if lobby_instance and is_instance_valid(lobby_instance):
		if lobby_instance.has_method("update_game_settings"):
			lobby_instance.update_game_settings(map_name, game_mode)

# Start game countdown
@rpc("authority", "call_local", "reliable")
func network_start_game_countdown():
	print("GameManager: RPC start game countdown")
	
	# Update lobby UI if available
	if lobby_instance and is_instance_valid(lobby_instance):
		if lobby_instance.has_method("start_countdown"):
			lobby_instance.start_countdown()

# Start the game
@rpc("authority", "call_local", "reliable")
func network_start_game(map_name):
	print("GameManager: RPC start game", map_name)
	
	# Get the map path
	var map_path = map_paths.get(map_name, WORLD_SCENE)
	
	# Load the world
	load_world(map_path)
	
	# Change state
	change_state(GameState.PLAYING)

# ==== SIGNAL HANDLERS ====
# Multiplayer signal handlers
func _on_peer_connected(peer_id: int):
	print("GameManager: Peer connected:", peer_id)
	connected_peers.append(peer_id)
	
	# If we're the host, send all player data to the new peer
	if is_host:
		# Send existing players data to the new peer
		for pid in players:
			var player_info = {
				"name": players[pid].name,
				"customization": players[pid].customization if "customization" in players[pid] else {}
			}
			network_register_player.rpc_id(peer_id, pid, player_info)
			network_set_player_ready.rpc_id(peer_id, pid, players[pid].ready)
		
		# Send current game settings
		network_update_game_settings.rpc_id(peer_id, current_map, current_game_mode)
	
	emit_signal("player_connected", peer_id)

func _on_peer_disconnected(peer_id: int):
	print("GameManager: Peer disconnected:", peer_id)
	
	# Remove peer from connected list
	if connected_peers.has(peer_id):
		connected_peers.erase(peer_id)
	
	# Remove player instance if in game
	remove_player_instance(peer_id)
	
	# Unregister the player
	unregister_player(peer_id)
	
	emit_signal("player_disconnected", peer_id)

func _on_connected_to_server():
	print("GameManager: Successfully connected to server")
	local_player_id = multiplayer.get_unique_id()
	connection_in_progress = false
	
	# Register ourselves with the server
	var player_info = {
		"name": get_player_name(),
		"customization": character_data.duplicate()
	}
	network_register_player.rpc(local_player_id, player_info)
	
	# Transition to lobby after successful connection
	call_deferred("show_lobby")

func _on_connection_failed():
	print("GameManager: Failed to connect to server")
	multiplayer.multiplayer_peer = null
	network_peer = null
	connection_in_progress = false
	emit_signal("connection_failed")

func _on_server_disconnected():
	print("GameManager: Disconnected from server")
	multiplayer.multiplayer_peer = null
	network_peer = null
	connection_in_progress = false
	
	# Clear player data
	players.clear()
	
	emit_signal("server_disconnected")
	
	# Return to main menu
	call_deferred("return_to_main_menu")

# ==== PLAYER MANAGEMENT ====
# Register a player with the game
func register_player(player_id, player_name):
	print("GameManager: Registering player:", player_id, player_name)
	
	# Create player entry if it doesn't exist
	if not player_id in players:
		players[player_id] = {
			"id": player_id,
			"name": player_name,
			"ready": false,
			"instance": null,
			"customization": character_data.duplicate() if character_data.size() > 0 else {}
		}
		
		# Call RPC to register player with all peers if in multiplayer
		if network_peer:
			var player_info = {
				"name": player_name,
				"customization": character_data.duplicate() if character_data.size() > 0 else {}
			}
			network_register_player.rpc(player_id, player_info)
		
		emit_signal("player_registered", player_id, player_name)
		
		# Update lobby if available
		update_lobby_ui()

# Remove a player from the game
func unregister_player(player_id):
	if player_id in players:
		var player_name = players[player_id].name
		players.erase(player_id)
		
		emit_signal("player_unregistered", player_id)
		
		# Update lobby if available
		update_lobby_ui()

# Set a player's ready status
func set_player_ready(player_id, is_ready):
	if player_id in players:
		players[player_id].ready = is_ready
		
		# Update ready status on the network if in multiplayer
		if network_peer:
			network_set_player_ready.rpc(player_id, is_ready)
		
		emit_signal("player_ready_status_changed", player_id, is_ready)
		
		# Update lobby if available
		update_lobby_ui()

# Check if all players are ready
func check_all_players_ready() -> bool:
	var all_ready = true
	
	for player_id in players:
		if !players[player_id].ready:
			all_ready = false
			break
	
	return all_ready

# Get all registered players
func get_players():
	return players

# Get data for a specific player
func get_player_data(player_id):
	if player_id in players:
		return players[player_id]
	return null

# Get player data formatted for network transmission
func get_players_data():
	var data = {}
	for player_id in players:
		data[str(player_id)] = {
			"name": players[player_id].name,
			"ready": players[player_id].ready,
			"customization": players[player_id].customization if "customization" in players[player_id] else {}
		}
	return data

# Get player name (from character data or default)
func get_player_name():
	if "name" in character_data:
		return character_data.name
	return "Player"

# Get customization data for a player
func get_player_customization(player_id):
	# Check player data first
	if player_id in players and "customization" in players[player_id] and players[player_id].customization.size() > 0:
		return players[player_id].customization
	
	# Use local character data if available
	if character_data.size() > 0:
		return character_data
	
	# Default customization
	return {
		"skin_color": Color(0.9, 0.75, 0.6),
		"hair_style": 0,
		"hair_color": Color(0.2, 0.1, 0.05),
		"eye_color": Color(0.2, 0.4, 0.8),
		"shirt_color": Color(0.2, 0.3, 0.8),
		"pants_color": Color(0.2, 0.2, 0.3)
	}

# Update the lobby UI
func update_lobby_ui():
	if lobby_instance and is_instance_valid(lobby_instance):
		if lobby_instance.has_method("update_player_list"):
			lobby_instance.update_player_list()

# ==== UI MANAGEMENT ====
# Change the current game state
func change_state(new_state):
	var old_state = current_state
	current_state = new_state
	
	print("GameManager: State change from ", _state_to_string(old_state), " to ", _state_to_string(new_state))
	
	# Emit signal for state change
	emit_signal("game_state_changed", old_state, new_state)

# Convert state enum to string for debugging
func _state_to_string(state):
	match state:
		GameState.MAIN_MENU:
			return "MAIN_MENU"
		GameState.NETWORK_SETUP:
			return "NETWORK_SETUP"
		GameState.LOBBY:
			return "LOBBY"
		GameState.PLAYING:
			return "PLAYING"
		GameState.GAME_OVER:
			return "GAME_OVER"
		GameState.SETTINGS:
			return "SETTINGS"
		_:
			return "UNKNOWN"

# Show the main menu
func show_main_menu():
	print("GameManager: Showing main menu")
	
	# Clear any existing UI
	clear_current_ui()
	
	# Change scene to main menu
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
	
	# Update state
	change_state(GameState.MAIN_MENU)

# Show the network setup UI
func show_network_ui():
	print("GameManager: Showing network UI")
	
	# Clear any existing UI
	clear_current_ui()
	
	# Change scene to network UI
	get_tree().change_scene_to_file(NETWORK_UI_SCENE)
	
	# Update state
	change_state(GameState.NETWORK_SETUP)

# Show the lobby
func show_lobby():
	print("GameManager: Showing lobby")
	
	# Clear any existing UI
	clear_current_ui()
	
	# Change scene to lobby
	get_tree().change_scene_to_file(LOBBY_SCENE)
	
	# Wait for the scene to be fully loaded and ready
	await get_tree().process_frame
	
	# Now it's safe to get the scene reference
	lobby_instance = get_tree().current_scene
	
	# Connect to necessary signals
	if lobby_instance:
		# Connect the back button
		if lobby_instance.has_signal("back_pressed") and !lobby_instance.is_connected("back_pressed", Callable(self, "show_network_ui")):
			lobby_instance.back_pressed.connect(show_network_ui)
			
		# Connect the start game signal
		if lobby_instance.has_signal("start_game") and !lobby_instance.is_connected("start_game", Callable(self, "start_game")):
			lobby_instance.start_game.connect(start_game)
		
		# Initialize the lobby with current data
		if lobby_instance.has_method("initialize_from_game_manager"):
			lobby_instance.initialize_from_game_manager(self)
	
	# Update state
	change_state(GameState.LOBBY)

# Start the game
func start_game(map_name = "", game_mode = ""):
	print("GameManager: Starting game")
	
	# Use parameters if provided, otherwise use current settings
	if map_name == "":
		map_name = current_map
	
	if game_mode == "":
		game_mode = current_game_mode
	
	# Use map path
	var map_path = map_paths.get(map_name, WORLD_SCENE)
	
	# In multiplayer, only the host can start the game
	if network_peer and is_host:
		# Start the countdown on all clients
		network_start_game_countdown.rpc()
		
		# Wait for countdown and then start
		await get_tree().create_timer(5.0).timeout
		
		# Start the game on all clients
		network_start_game.rpc(map_name)
	elif !network_peer:
		# Direct single player start
		load_world(map_path)
		
		# Update state
		change_state(GameState.PLAYING)

# Return to the main menu
func return_to_main_menu():
	print("GameManager: Returning to main menu")
	
	# Disconnect multiplayer if connected
	disconnect_from_game()
	
	# Clear player data
	players.clear()
	
	# Change scene to main menu
	show_main_menu()

# Clear all UI instances
func clear_current_ui():
	main_menu_instance = null
	network_ui_instance = null
	lobby_instance = null
	settings_instance = null

# Pause menu handling
func toggle_pause_menu(show_pause: bool = false):
	var pause_menu = get_node_or_null("pause_menu")
	
	if !pause_menu and current_state == GameState.PLAYING:
		# Create pause menu if it doesn't exist
		var pause_scene = load("res://Scenes/UI/Player/pause_menu.tscn")
		if pause_scene:
			pause_menu = pause_scene.instantiate()
			pause_menu.name = "pause_menu"
			add_child(pause_menu)
	
	if pause_menu:
		if show_pause:
			pause_menu.toggle_pause()

# Show settings
func show_settings():
	print("GameManager: Showing settings")
	
	# Store the current state to return to later
	previous_state = current_state
	
	# Clear any existing UI
	clear_current_ui()
	
	# Load settings scene
	var settings_scene = load("res://Scenes/UI/Menus/Settings.tscn")
	if settings_scene:
		settings_instance = settings_scene.instantiate()
		get_tree().root.add_child(settings_instance)
	else:
		push_error("GameManager: Could not load settings scene!")
		return
	
	# Update state
	change_state(GameState.SETTINGS)

# Return from settings
func return_from_settings():
	print("GameManager: Returning from settings to previous state: " + _state_to_string(previous_state))
	
	# Remove settings instance
	if settings_instance and is_instance_valid(settings_instance):
		settings_instance.queue_free()
	settings_instance = null
	
	# Return to the previous state
	match previous_state:
		GameState.MAIN_MENU:
			show_main_menu()
		GameState.NETWORK_SETUP:
			show_network_ui()
		GameState.LOBBY:
			show_lobby()
		GameState.PLAYING:
			# If we were in the playing state, we need to make the pause menu visible again
			var pause_menu = get_node_or_null("pause_menu")
			if pause_menu:
				pause_menu.visible = true
			change_state(GameState.PLAYING)
		_:
			# Default to main menu if something went wrong
			show_main_menu()

# ==== CHARACTER DATA ====
# Save character data to disk
func save_character_data():
	var file = FileAccess.open("user://character_data.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(character_data))
		file.close()

# Load character data from disk
func load_character_data():
	if not FileAccess.file_exists("user://character_data.json"):
		return false
	
	var file = FileAccess.open("user://character_data.json", FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		var json_result = JSON.parse_string(json_string)
		
		if json_result:
			character_data = json_result
			return true
	
	return false

# Store character data
func set_character_data(data):
	character_data = data
	
	# Save to disk
	save_character_data()
	
	# Emit signal
	character_data_updated.emit(character_data)
	
	# Update in player data
	var player_id = multiplayer.get_unique_id()
	if player_id in players:
		players[player_id].customization = data.duplicate()
	
	# Update on the network if in multiplayer
	if network_peer:
		var player_info = {
			"name": get_player_name(),
			"customization": character_data.duplicate()
		}
		network_register_player.rpc(player_id, player_info)

# Get character data
func get_character_data():
	return character_data

# Reapply character customization
func reapply_character_customization():
	print("GameManager: Providing character customization data:", character_data.size(), "items")
	# This is used by the sprite system to get customization data
	return character_data

# ==== DEBUG UTILS ====
# Handle debug command input
func handle_debug_command(command: String):
	var parts = command.split(" ")
	if parts.size() == 0:
		return
	
	match parts[0]:
		"teleport":
			if parts.size() >= 3:
				var x = int(parts[1])
				var y = int(parts[2])
				teleport_player(Vector2(x, y))
		"reload_systems":
			reload_systems()
		"print_systems":
			log_system_status()
		"help":
			print("Debug commands:")
			print("teleport X Y - Teleport player to coordinates")
			print("toggle_admin - Toggle admin mode")
			print("toggle_debug - Toggle debug mode")
			print("reload_systems - Reload system references")
			print("print_systems - Print system status")

# Teleport player to position
func teleport_player(position: Vector2):
	if local_player_instance and is_instance_valid(local_player_instance):
		local_player_instance.position = position
		var grid_controller = local_player_instance
		if grid_controller:
			grid_controller.current_tile_position = grid_controller.world_to_tile(position)
			grid_controller.previous_tile_position = grid_controller.current_tile_position
			print("GameManager: Teleported player to ", position)
