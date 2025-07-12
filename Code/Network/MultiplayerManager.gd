extends Node

signal player_connected(peer_id)
signal player_disconnected(peer_id)
signal connection_failed()
signal server_disconnected()
signal host_ready()

# Configuration
const DEFAULT_PORT = 7777
const MAX_PLAYERS = 16

# Player scene to spawn
@export var player_scene: PackedScene

# Internal state
var is_host: bool = false
var connected_peers = []
var local_player_id = 1
var connection_in_progress = false

# Get singleton access
static func get_instance() -> MultiplayerManager:
	return Engine.get_singleton("MultiplayerManager")

func _ready():
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host_game(port: int = DEFAULT_PORT, use_upnp: bool = true) -> bool:
	print("Attempting to host on port ", port)
	
	# Create the server peer
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	
	if error != OK:
		print("Failed to create server: ", error)
		return false
	
	# Configure UPNP if enabled
	if use_upnp:
		setup_upnp(port)
	
	# Set as multiplayer peer
	multiplayer.multiplayer_peer = peer
	is_host = true
	local_player_id = 1  # Host always gets ID 1
	connected_peers = [1]  # Host is always peer 1
	
	# Host ready
	call_deferred("emit_signal", "host_ready")
	
	print("Server started successfully on port ", port)
	return true

func join_game(address: String, port: int = DEFAULT_PORT) -> bool:
	print("Attempting to join ", address, ":", port)
	
	if connection_in_progress:
		return false
	
	connection_in_progress = true
	
	# Create the client peer
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	
	if error != OK:
		print("Failed to create client: ", error)
		connection_in_progress = false
		return false
	
	# Set as multiplayer peer
	multiplayer.multiplayer_peer = peer
	is_host = false
	
	print("Client attempting to connect to ", address, ":", port)
	return true

func disconnect_from_game():
	# Clean up the multiplayer peer
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	
	# Reset state
	is_host = false
	connected_peers = []
	connection_in_progress = false
	
	print("Disconnected from game")

func get_local_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_unique_id()

func get_connected_peers() -> Array:
	if multiplayer.multiplayer_peer == null:
		return []
	
	var peers = multiplayer.get_peers()
	peers.append(1)  # Add server (ID 1)
	return peers

func setup_upnp(port: int) -> bool:
	var upnp = UPNP.new()
	var discover_result = upnp.discover()
	
	if discover_result != UPNP.UPNP_RESULT_SUCCESS:
		print("UPNP discover failed: ", discover_result)
		return false
	
	if upnp.get_gateway() and upnp.get_gateway().is_valid_gateway():
		# Try to map both UDP and TCP
		var map_result_udp = upnp.add_port_mapping(port, port, "Multiplayer Game UDP", "UDP", 0)
		var map_result_tcp = upnp.add_port_mapping(port, port, "Multiplayer Game TCP", "TCP", 0)
		
		if map_result_udp != UPNP.UPNP_RESULT_SUCCESS or map_result_tcp != UPNP.UPNP_RESULT_SUCCESS:
			print("UPNP port mapping failed")
			return false
		
		print("UPNP port mapping successful")
		print("External IP: ", upnp.query_external_address())
		return true
	
	print("UPNP no valid gateway found")
	return false

func spawn_player(peer_id: int):
	if !is_host:
		# Only the host can spawn players
		return
		
	# Create player instance
	var player_instance = player_scene.instantiate()
	
	# Set unique name based on peer ID
	player_instance.name = str(peer_id)
	
	# Add player to the world
	var world = get_tree().get_root().get_node_or_null("Main/World")
	if world:
		world.add_child(player_instance)
		
		# Initialize player
		if player_instance.has_method("setup_multiplayer"):
			player_instance.setup_multiplayer(peer_id)
		
		print("Spawned player for peer ", peer_id)
	else:
		print("Error: World node not found!")
		player_instance.queue_free()

func _on_peer_connected(peer_id: int):
	print("Peer connected: ", peer_id)
	connected_peers.append(peer_id)
	
	# Host spawns a player for the new peer
	if is_host:
		spawn_player(peer_id)
	
	emit_signal("player_connected", peer_id)

func _on_peer_disconnected(peer_id: int):
	print("Peer disconnected: ", peer_id)
	
	# Remove peer from list
	if connected_peers.has(peer_id):
		connected_peers.erase(peer_id)
	
	# Remove player node associated with this peer
	var player_node = get_tree().get_root().get_node_or_null("Main/World/" + str(peer_id))
	if player_node:
		player_node.queue_free()
	
	emit_signal("player_disconnected", peer_id)

func _on_connected_to_server():
	print("Successfully connected to server")
	local_player_id = multiplayer.get_unique_id()
	connection_in_progress = false

func _on_connection_failed():
	print("Failed to connect to server")
	multiplayer.multiplayer_peer = null
	connection_in_progress = false
	emit_signal("connection_failed")

func _on_server_disconnected():
	print("Disconnected from server")
	multiplayer.multiplayer_peer = null
	connection_in_progress = false
	emit_signal("server_disconnected")
