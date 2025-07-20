extends Node

signal player_connected(peer_id)
signal player_disconnected(peer_id)
signal connection_failed()
signal server_disconnected()
signal host_ready()

const DEFAULT_PORT = 7777
const MAX_PLAYERS = 16

var player_scene: PackedScene = load("res://Scenes/Characters/human.tscn")

# Internal state
var connected_peers = []
var local_player_id = 1
var connection_in_progress = false

# Spawned players tracking
var spawned_players = {}

# Game mode tracking
var is_hosting = false
var is_client = false

static func get_instance() -> MultiplayerManager:
	return Engine.get_singleton("MultiplayerManager")

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host_game(port: int = DEFAULT_PORT, use_upnp: bool = true) -> bool:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	
	if error != OK:
		return false
	
	if use_upnp:
		setup_upnp(port)
	
	multiplayer.multiplayer_peer = peer
	local_player_id = 1
	connected_peers = [1]
	is_hosting = true
	is_client = false
	
	call_deferred("emit_signal", "host_ready")
	
	return true

func join_game(address: String, port: int = DEFAULT_PORT) -> bool:
	if connection_in_progress:
		return false
	
	connection_in_progress = true
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	
	if error != OK:
		connection_in_progress = false
		return false
	
	multiplayer.multiplayer_peer = peer
	is_hosting = false
	is_client = true
	
	return true

func disconnect_from_game():
	for peer_id in spawned_players:
		var player_instance = spawned_players[peer_id]
		if is_instance_valid(player_instance):
			player_instance.queue_free()
	spawned_players.clear()
	
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	
	connected_peers = []
	connection_in_progress = false
	is_hosting = false
	is_client = false

func get_local_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_unique_id()

func get_connected_peers() -> Array:
	if multiplayer.multiplayer_peer == null:
		return []
	
	var peers = multiplayer.get_peers()
	peers.append(1)
	return peers

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

func is_multiplayer_active() -> bool:
	return multiplayer.multiplayer_peer != null and (is_hosting or is_client)

func is_multiplayer_host() -> bool:
	return is_hosting and multiplayer.multiplayer_peer != null

func is_multiplayer_client() -> bool:
	return is_client and multiplayer.multiplayer_peer != null

@rpc("authority", "call_local", "reliable")
func spawn_player_for_peer(peer_id: int, spawn_position: Vector2, character_data: Dictionary = {}):
	print("MultiplayerManager: Spawning player for peer ", peer_id, " with customization data")
	
	if not player_scene:
		return
	
	if not is_multiplayer_active():
		return
	
	var player_instance = player_scene.instantiate()
	player_instance.name = "Player_" + str(peer_id)
	player_instance.position = spawn_position
	
	player_instance.set_meta("is_player", true)
	player_instance.set_meta("is_npc", false)
	player_instance.set_meta("peer_id", peer_id)
	player_instance.set_multiplayer_authority(peer_id)
	
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		world = get_tree().current_scene
	
	if world:
		world.add_child(player_instance)
		await get_tree().process_frame
		
		setup_player_camera(player_instance, peer_id)
		
		var movement_controller = get_movement_controller(player_instance)
		if movement_controller:
			movement_controller.peer_id = peer_id
			movement_controller.is_local_player = (peer_id == multiplayer.get_unique_id())
			
			if movement_controller.has_method("setup_multiplayer"):
				movement_controller.setup_multiplayer(peer_id)
			elif movement_controller.has_method("initialize"):
				var init_data = {
					"controller": player_instance,
					"peer_id": peer_id,
					"world": world,
					"is_local_player": (peer_id == multiplayer.get_unique_id())
				}
				movement_controller.initialize(init_data)
		
		# Apply character customization with a small delay to ensure sprite system is ready
		if character_data.size() > 0:
			await get_tree().create_timer(0.1).timeout
			apply_character_customization(player_instance, character_data)
		
		spawned_players[peer_id] = player_instance
		
		print("MultiplayerManager: Successfully spawned player for peer ", peer_id)
	else:
		player_instance.queue_free()

func get_movement_controller(player_instance: Node) -> Node:
	var movement_controller = player_instance.get_node_or_null("MovementComponent")
	if not movement_controller:
		movement_controller = player_instance.get_node_or_null("GridMovementController")
	if not movement_controller:
		movement_controller = player_instance
	return movement_controller

func setup_player_camera(player_instance: Node, peer_id: int):
	var camera = player_instance.get_node_or_null("Camera2D")
	if not camera:
		camera = player_instance.get_node_or_null("PlayerCamera")
		if not camera:
			camera = player_instance.get_node_or_null("Camera")
	
	if camera:
		var is_local_player = (peer_id == multiplayer.get_unique_id())
		camera.enabled = is_local_player
		
		if is_local_player:
			camera.make_current()
			print("MultiplayerManager: Camera enabled for local player (peer ", peer_id, ")")

func apply_character_customization(player_instance: Node, character_data: Dictionary):
	print("MultiplayerManager: Applying character customization for player with ", character_data.size(), " properties")
	
	var sprite_system = null
	
	# Try multiple paths to find the sprite system
	var possible_paths = [
		"HumanSpriteSystem",
		"SpriteSystem",
		"sprite_system", 
		"Sprite",
		"CharacterSprite",
		"Visuals/SpriteSystem"
	]
	
	for path in possible_paths:
		sprite_system = player_instance.get_node_or_null(path)
		if sprite_system:
			print("MultiplayerManager: Found sprite system at path: ", path)
			break
	
	if sprite_system:
		# Try different methods to apply customization
		if sprite_system.has_method("apply_character_data"):
			print("MultiplayerManager: Applying customization via apply_character_data")
			sprite_system.apply_character_data(character_data)
		elif sprite_system.has_method("apply_customization"):
			print("MultiplayerManager: Applying customization via apply_customization")
			sprite_system.apply_customization(character_data)
		else:
			print("MultiplayerManager: Sprite system found but no customization method available")
			
			# Try to apply individual properties if the methods exist
			if "sex" in character_data and sprite_system.has_method("set_sex"):
				sprite_system.set_sex(character_data.sex)
			
			if "race" in character_data and sprite_system.has_method("set_race"):
				sprite_system.set_race(character_data.race)
			
			# Apply hair
			if "hair_texture" in character_data and "hair_color" in character_data and sprite_system.has_method("set_hair"):
				var hair_color = character_data.hair_color
				if typeof(hair_color) == TYPE_DICTIONARY:
					hair_color = Color(hair_color.r, hair_color.g, hair_color.b, hair_color.get("a", 1.0))
				
				var asset_manager = get_node_or_null("/root/CharacterAssetManager")
				var hair_texture = null
				if asset_manager and character_data.hair_texture:
					hair_texture = asset_manager.get_resource(character_data.hair_texture)
				elif character_data.hair_texture:
					hair_texture = load(character_data.hair_texture)
				
				if hair_texture:
					sprite_system.set_hair(hair_texture, hair_color)
			
			# Apply facial hair
			if "facial_hair_texture" in character_data and "facial_hair_color" in character_data and sprite_system.has_method("set_facial_hair"):
				var facial_hair_color = character_data.facial_hair_color
				if typeof(facial_hair_color) == TYPE_DICTIONARY:
					facial_hair_color = Color(facial_hair_color.r, facial_hair_color.g, facial_hair_color.b, facial_hair_color.get("a", 1.0))
				
				var asset_manager = get_node_or_null("/root/CharacterAssetManager")
				var facial_hair_texture = null
				if asset_manager and character_data.facial_hair_texture:
					facial_hair_texture = asset_manager.get_resource(character_data.facial_hair_texture)
				elif character_data.facial_hair_texture:
					facial_hair_texture = load(character_data.facial_hair_texture)
				
				if facial_hair_texture:
					sprite_system.set_facial_hair(facial_hair_texture, facial_hair_color)
			
			# Apply underwear
			if "underwear_texture" in character_data and sprite_system.has_method("set_underwear"):
				var asset_manager = get_node_or_null("/root/CharacterAssetManager")
				var underwear_texture = null
				if asset_manager and character_data.underwear_texture:
					underwear_texture = asset_manager.get_resource(character_data.underwear_texture)
				elif character_data.underwear_texture:
					underwear_texture = load(character_data.underwear_texture)
				
				if underwear_texture:
					sprite_system.set_underwear(underwear_texture)
			
			# Apply undershirt
			if "undershirt_texture" in character_data and sprite_system.has_method("set_undershirt"):
				var asset_manager = get_node_or_null("/root/CharacterAssetManager")
				var undershirt_texture = null
				if asset_manager and character_data.undershirt_texture:
					undershirt_texture = asset_manager.get_resource(character_data.undershirt_texture)
				elif character_data.undershirt_texture:
					undershirt_texture = load(character_data.undershirt_texture)
				
				if undershirt_texture:
					sprite_system.set_undershirt(undershirt_texture)
			
			# Apply clothing
			if "clothing_textures" in character_data and sprite_system.has_method("set_clothing"):
				sprite_system.set_clothing(character_data.clothing_textures)
			
			print("MultiplayerManager: Applied individual customization properties")
	else:
		print("MultiplayerManager: No sprite system found for character customization")

func spawn_player(peer_id: int, spawn_position: Vector2 = Vector2.ZERO, character_data: Dictionary = {}):
	if not is_multiplayer_host():
		return
	
	if spawn_position == Vector2.ZERO:
		spawn_position = get_default_spawn_position(peer_id)
	
	print("MultiplayerManager: Host spawning player ", peer_id, " with character data")
	spawn_player_for_peer.rpc(peer_id, spawn_position, character_data)

func get_default_spawn_position(peer_id: int) -> Vector2:
	var spawn_x = 100 + (peer_id * 64)
	var spawn_y = 100
	return Vector2(spawn_x, spawn_y)

func despawn_player(peer_id: int):
	if not is_multiplayer_host():
		return
	
	despawn_player_for_peer.rpc(peer_id)

@rpc("authority", "call_local", "reliable")
func despawn_player_for_peer(peer_id: int):
	if peer_id in spawned_players:
		var player_instance = spawned_players[peer_id]
		if is_instance_valid(player_instance):
			player_instance.queue_free()
		spawned_players.erase(peer_id)

func get_player_instance(peer_id: int) -> Node:
	return spawned_players.get(peer_id, null)

func get_local_player() -> Node:
	if not is_multiplayer_active():
		return null
	return get_player_instance(multiplayer.get_unique_id())

func get_all_players() -> Array:
	var players = []
	for peer_id in spawned_players:
		var player = spawned_players[peer_id]
		if is_instance_valid(player):
			players.append(player)
	return players

# Update character customization for existing player
@rpc("any_peer", "call_local", "reliable")
func update_player_customization(peer_id: int, character_data: Dictionary):
	print("MultiplayerManager: Updating customization for peer ", peer_id)
	
	if peer_id in spawned_players:
		var player_instance = spawned_players[peer_id]
		if is_instance_valid(player_instance):
			apply_character_customization(player_instance, character_data)

func sync_player_customization(peer_id: int, character_data: Dictionary):
	"""Public method to sync a player's customization across all clients"""
	if is_multiplayer_host():
		update_player_customization.rpc(peer_id, character_data)

# Signal handlers
func _on_peer_connected(peer_id: int):
	connected_peers.append(peer_id)
	
	# Don't auto-spawn here - let GameManager handle spawning
	# This gives GameManager a chance to sync character data first
	
	emit_signal("player_connected", peer_id)

func _on_peer_disconnected(peer_id: int):
	if connected_peers.has(peer_id):
		connected_peers.erase(peer_id)
	
	if is_multiplayer_host():
		despawn_player(peer_id)
	
	emit_signal("player_disconnected", peer_id)

func _on_connected_to_server():
	local_player_id = multiplayer.get_unique_id()
	connection_in_progress = false

func _on_connection_failed():
	multiplayer.multiplayer_peer = null
	connection_in_progress = false
	is_hosting = false
	is_client = false
	emit_signal("connection_failed")

func _on_server_disconnected():
	for peer_id in spawned_players:
		var player_instance = spawned_players[peer_id]
		if is_instance_valid(player_instance):
			player_instance.queue_free()
	spawned_players.clear()
	
	multiplayer.multiplayer_peer = null
	connection_in_progress = false
	is_hosting = false
	is_client = false
	emit_signal("server_disconnected")
