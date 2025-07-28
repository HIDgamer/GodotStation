extends Node

signal player_connected(peer_id)
signal player_disconnected(peer_id)
signal connection_failed()
signal server_disconnected()
signal host_ready()

const DEFAULT_PORT = 7777
const MAX_PLAYERS = 16

var player_scene: PackedScene = preload("res://Scenes/Characters/human.tscn")

# Network state
var connected_peers = []
var connection_in_progress = false
var is_hosting = false
var is_client = false

# Player instances
var spawned_players = {}

func _ready():
	connect_multiplayer_signals()

func connect_multiplayer_signals():
	"""Connect to multiplayer signals"""
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host_game(port: int = DEFAULT_PORT, use_upnp: bool = true) -> bool:
	"""Start hosting multiplayer game"""
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	
	if error != OK:
		print("MultiplayerManager: Failed to create server on port ", port)
		return false
	
	if use_upnp:
		setup_upnp(port)
	
	multiplayer.multiplayer_peer = peer
	connected_peers = [1]
	is_hosting = true
	is_client = false
	
	print("MultiplayerManager: Successfully hosting on port ", port)
	call_deferred("emit_signal", "host_ready")
	return true

func join_game(address: String, port: int = DEFAULT_PORT) -> bool:
	"""Join multiplayer game"""
	if connection_in_progress:
		print("MultiplayerManager: Connection already in progress")
		return false
	
	connection_in_progress = true
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	
	if error != OK:
		print("MultiplayerManager: Failed to create client connection to ", address, ":", port)
		connection_in_progress = false
		return false
	
	multiplayer.multiplayer_peer = peer
	is_hosting = false
	is_client = true
	
	print("MultiplayerManager: Attempting to connect to ", address, ":", port)
	return true

func disconnect_from_game():
	"""Disconnect and cleanup"""
	print("MultiplayerManager: Disconnecting from game")
	cleanup_players()
	
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	
	connected_peers = []
	connection_in_progress = false
	is_hosting = false
	is_client = false

func spawn_player(peer_id: int, spawn_position: Vector2 = Vector2.ZERO, character_data: Dictionary = {}):
	"""Spawn player for peer (host authority only)"""
	if not is_multiplayer_host():
		print("MultiplayerManager: Only host can spawn players")
		return
	
	if spawn_position == Vector2.ZERO:
		spawn_position = get_default_spawn_position(peer_id)
	
	print("MultiplayerManager: Spawning player for peer ", peer_id, " at ", spawn_position)
	spawn_player_for_peer.rpc(peer_id, spawn_position, character_data)

@rpc("authority", "call_local", "reliable")
func spawn_player_for_peer(peer_id: int, spawn_position: Vector2, character_data: Dictionary = {}):
	"""Create player instance across all clients"""
	if not player_scene:
		print("MultiplayerManager: No player scene available")
		return
	
	var player_instance = player_scene.instantiate()
	player_instance.name = "Player_" + str(peer_id)
	player_instance.position = spawn_position
	
	setup_player_metadata(player_instance, peer_id)
	
	var world = get_world_node()
	if world:
		world.add_child(player_instance)
		await get_tree().process_frame
		
		setup_player_systems(player_instance, peer_id)
		apply_character_customization(player_instance, character_data)
		
		spawned_players[peer_id] = player_instance
		print("MultiplayerManager: Successfully spawned player for peer ", peer_id)
	else:
		print("MultiplayerManager: Failed to find world node")
		player_instance.queue_free()

func despawn_player(peer_id: int):
	"""Remove player (host authority only)"""
	if not is_multiplayer_host():
		print("MultiplayerManager: Only host can despawn players")
		return
	
	print("MultiplayerManager: Despawning player for peer ", peer_id)
	despawn_player_for_peer.rpc(peer_id)

@rpc("authority", "call_local", "reliable")
func despawn_player_for_peer(peer_id: int):
	"""Remove player instance across all clients"""
	if peer_id in spawned_players:
		var player_instance = spawned_players[peer_id]
		if is_instance_valid(player_instance):
			print("MultiplayerManager: Removing player instance for peer ", peer_id)
			player_instance.queue_free()
		spawned_players.erase(peer_id)

func get_player_instance(peer_id: int) -> Node:
	"""Get player instance for peer"""
	return spawned_players.get(peer_id, null)

func get_local_player() -> Node:
	"""Get local player instance"""
	if not is_multiplayer_active():
		return null
	return get_player_instance(multiplayer.get_unique_id())

func get_all_players() -> Array:
	"""Get all valid player instances"""
	var players = []
	for peer_id in spawned_players:
		var player = spawned_players[peer_id]
		if is_instance_valid(player):
			players.append(player)
	return players

@rpc("any_peer", "call_local", "reliable")
func update_player_customization(peer_id: int, character_data: Dictionary):
	"""Update player appearance across clients"""
	print("MultiplayerManager: Updating customization for peer ", peer_id)
	if peer_id in spawned_players:
		var player_instance = spawned_players[peer_id]
		if is_instance_valid(player_instance):
			apply_character_customization(player_instance, character_data)

func sync_player_customization(peer_id: int, character_data: Dictionary):
	"""Sync player customization from host"""
	if is_multiplayer_host():
		update_player_customization.rpc(peer_id, character_data)

func is_multiplayer_active() -> bool:
	"""Check if multiplayer is active"""
	return multiplayer.multiplayer_peer != null and (is_hosting or is_client)

func is_multiplayer_host() -> bool:
	"""Check if this is host"""
	return is_hosting and multiplayer.multiplayer_peer != null

func is_multiplayer_client() -> bool:
	"""Check if this is client"""
	return is_client and multiplayer.multiplayer_peer != null

func get_local_peer_id() -> int:
	"""Get local peer ID"""
	if multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_unique_id()

func get_connected_peers() -> Array:
	"""Get all connected peer IDs"""
	if multiplayer.multiplayer_peer == null:
		return []
	
	var peers = multiplayer.get_peers()
	peers.append(1)
	return peers

func setup_player_metadata(player_instance: Node, peer_id: int):
	"""Configure player metadata and authority"""
	player_instance.set_meta("is_player", true)
	player_instance.set_meta("is_npc", false)
	player_instance.set_meta("peer_id", peer_id)
	
	player_instance.set_multiplayer_authority(peer_id)
	
	print("MultiplayerManager: Set authority for peer ", peer_id, " on player instance")

func setup_player_systems(player_instance: Node, peer_id: int):
	"""Configure player systems"""
	setup_player_camera(player_instance, peer_id)
	setup_movement_controller(player_instance, peer_id)
	setup_interaction_components(player_instance, peer_id)

func setup_player_camera(player_instance: Node, peer_id: int):
	"""Configure camera - only local player gets active camera"""
	var camera = find_camera(player_instance)
	if camera:
		var is_local_player = (peer_id == multiplayer.get_unique_id())
		camera.enabled = is_local_player
		
		if is_local_player:
			camera.make_current()
			print("MultiplayerManager: Activated camera for local player ", peer_id)

func setup_movement_controller(player_instance: Node, peer_id: int):
	"""Configure movement controller"""
	var movement_controller = get_movement_controller(player_instance)
	if movement_controller:
		movement_controller.set_multiplayer_authority(peer_id)
		
		if "peer_id" in movement_controller:
			movement_controller.peer_id = peer_id
		if "is_local_player" in movement_controller:
			movement_controller.is_local_player = (peer_id == multiplayer.get_unique_id())
		
		if movement_controller.has_method("setup_multiplayer"):
			movement_controller.setup_multiplayer(peer_id)
		
		print("MultiplayerManager: Configured movement controller for peer ", peer_id)

func setup_interaction_components(player_instance: Node, peer_id: int):
	"""Setup interaction components"""
	var interaction_component = player_instance.get_node_or_null("ItemInteractionComponent")
	if interaction_component:
		interaction_component.set_multiplayer_authority(peer_id)
		
		if interaction_component.has_method("initialize"):
			var init_data = {
				"controller": player_instance,
				"peer_id": peer_id,
				"is_local_player": (peer_id == multiplayer.get_unique_id()),
				"world": get_world_node(),
				"inventory_system": find_inventory_system(player_instance),
				"sensory_system": find_sensory_system(),
				"audio_system": find_audio_system()
			}
			interaction_component.initialize(init_data)
			print("MultiplayerManager: Initialized interaction component for peer ", peer_id)
	
	var inventory_system = find_inventory_system(player_instance)
	if inventory_system:
		inventory_system.set_multiplayer_authority(peer_id)

func apply_character_customization(player_instance: Node, character_data: Dictionary):
	"""Apply character customization to player"""
	if character_data.is_empty():
		return
	
	await get_tree().create_timer(0.1).timeout
	
	var sprite_system = find_sprite_system(player_instance)
	if sprite_system:
		print("MultiplayerManager: Applying character customization")
		if sprite_system.has_method("apply_character_data"):
			sprite_system.apply_character_data(character_data)
		elif sprite_system.has_method("apply_customization"):
			sprite_system.apply_customization(character_data)
		else:
			apply_individual_customization(sprite_system, character_data)

func apply_individual_customization(sprite_system: Node, character_data: Dictionary):
	"""Apply individual customization properties"""
	if "sex" in character_data and sprite_system.has_method("set_sex"):
		sprite_system.set_sex(character_data.sex)
	
	if "race" in character_data and sprite_system.has_method("set_race"):
		sprite_system.set_race(character_data.race)
	
	if "hair_texture" in character_data and "hair_color" in character_data:
		apply_hair_customization(sprite_system, character_data)
	
	if "facial_hair_texture" in character_data and "facial_hair_color" in character_data:
		apply_facial_hair_customization(sprite_system, character_data)

func apply_hair_customization(sprite_system: Node, character_data: Dictionary):
	"""Apply hair customization"""
	if not sprite_system.has_method("set_hair"):
		return
	
	var hair_color = parse_color(character_data.hair_color)
	var hair_texture = load_texture_resource(character_data.hair_texture)
	
	if hair_texture:
		sprite_system.set_hair(hair_texture, hair_color)

func apply_facial_hair_customization(sprite_system: Node, character_data: Dictionary):
	"""Apply facial hair customization"""
	if not sprite_system.has_method("set_facial_hair"):
		return
	
	var facial_hair_color = parse_color(character_data.facial_hair_color)
	var facial_hair_texture = load_texture_resource(character_data.facial_hair_texture)
	
	if facial_hair_texture:
		sprite_system.set_facial_hair(facial_hair_texture, facial_hair_color)

func get_movement_controller(player_instance: Node) -> Node:
	"""Find movement controller"""
	var movement_controller = player_instance.get_node_or_null("MovementComponent")
	if not movement_controller:
		movement_controller = player_instance.get_node_or_null("GridMovementController")
	if not movement_controller:
		movement_controller = player_instance
	return movement_controller

func find_camera(player_instance: Node) -> Camera2D:
	"""Find camera component"""
	var camera = player_instance.get_node_or_null("Camera2D")
	if not camera:
		camera = player_instance.get_node_or_null("PlayerCamera")
	if not camera:
		camera = player_instance.get_node_or_null("Camera")
	return camera

func find_sprite_system(player_instance: Node) -> Node:
	"""Find sprite system"""
	var sprite_paths = [
		"HumanSpriteSystem", "SpriteSystem", "sprite_system",
		"Sprite", "CharacterSprite", "Visuals/SpriteSystem"
	]
	
	for path in sprite_paths:
		var sprite_system = player_instance.get_node_or_null(path)
		if sprite_system:
			return sprite_system
	
	return null

func find_inventory_system(player_instance: Node) -> Node:
	"""Find inventory system"""
	var inventory_system = player_instance.get_node_or_null("InventorySystem")
	if not inventory_system:
		inventory_system = player_instance.get_node_or_null("Inventory")
	return inventory_system

func find_sensory_system() -> Node:
	"""Find sensory system in world"""
	var world = get_world_node()
	if world:
		return world.get_node_or_null("SensorySystem")
	return null

func find_audio_system() -> Node:
	"""Find audio system in world"""
	var world = get_world_node()
	if world:
		return world.get_node_or_null("AudioManager")
	return null

func parse_color(color_data) -> Color:
	"""Parse color from data"""
	if typeof(color_data) == TYPE_DICTIONARY:
		return Color(color_data.r, color_data.g, color_data.b, color_data.get("a", 1.0))
	return color_data

func load_texture_resource(texture_path: String) -> Texture2D:
	"""Load texture from path"""
	if texture_path.is_empty():
		return null
	
	var asset_manager = get_node_or_null("/root/CharacterAssetManager")
	if asset_manager:
		return asset_manager.get_resource(texture_path)
	else:
		return load(texture_path)

func get_world_node() -> Node:
	"""Get world node"""
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		world = get_tree().current_scene
	return world

func get_default_spawn_position(peer_id: int) -> Vector2:
	"""Calculate default spawn position"""
	var spawn_x = 100 + (peer_id * 64)
	var spawn_y = 100
	return Vector2(spawn_x, spawn_y)

func setup_upnp(port: int) -> bool:
	"""Setup UPnP port forwarding"""
	print("MultiplayerManager: Attempting UPnP setup for port ", port)
	var upnp = UPNP.new()
	var discover_result = upnp.discover()
	
	if discover_result != UPNP.UPNP_RESULT_SUCCESS:
		print("MultiplayerManager: UPnP discovery failed")
		return false
	
	if upnp.get_gateway() and upnp.get_gateway().is_valid_gateway():
		var map_result_udp = upnp.add_port_mapping(port, port, "Multiplayer Game UDP", "UDP", 0)
		var map_result_tcp = upnp.add_port_mapping(port, port, "Multiplayer Game TCP", "TCP", 0)
		
		var success = (map_result_udp == UPNP.UPNP_RESULT_SUCCESS and 
				map_result_tcp == UPNP.UPNP_RESULT_SUCCESS)
		
		if success:
			print("MultiplayerManager: UPnP port forwarding successful")
		else:
			print("MultiplayerManager: UPnP port forwarding failed")
		
		return success
	
	print("MultiplayerManager: No valid UPnP gateway found")
	return false

func cleanup_players():
	"""Remove all spawned players"""
	print("MultiplayerManager: Cleaning up all players")
	for peer_id in spawned_players:
		var player_instance = spawned_players[peer_id]
		if is_instance_valid(player_instance):
			player_instance.queue_free()
	spawned_players.clear()

func _on_peer_connected(peer_id: int):
	"""Handle peer connection"""
	print("MultiplayerManager: Peer ", peer_id, " connected")
	connected_peers.append(peer_id)
	emit_signal("player_connected", peer_id)

func _on_peer_disconnected(peer_id: int):
	"""Handle peer disconnection"""
	print("MultiplayerManager: Peer ", peer_id, " disconnected")
	if connected_peers.has(peer_id):
		connected_peers.erase(peer_id)
	
	if is_multiplayer_host():
		despawn_player(peer_id)
	
	emit_signal("player_disconnected", peer_id)

func _on_connected_to_server():
	"""Handle successful server connection"""
	print("MultiplayerManager: Successfully connected to server")
	connection_in_progress = false

func _on_connection_failed():
	"""Handle connection failure"""
	print("MultiplayerManager: Connection failed")
	multiplayer.multiplayer_peer = null
	connection_in_progress = false
	is_hosting = false
	is_client = false
	emit_signal("connection_failed")

func _on_server_disconnected():
	"""Handle server disconnection"""
	print("MultiplayerManager: Server disconnected")
	cleanup_players()
	multiplayer.multiplayer_peer = null
	connection_in_progress = false
	is_hosting = false
	is_client = false
	emit_signal("server_disconnected")
