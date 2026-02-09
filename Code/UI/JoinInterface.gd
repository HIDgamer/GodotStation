extends Control

var UIAnimationHelperScript = load("uid://dop12m7xxcnmg")

@onready var parallax_layers: Array = [
	get_node("Background/Parallax2D/Parallax_2"),
	get_node("Background/Parallax2D/Parallax_3"),
	get_node("Background/Parallax2D/Parallax_4"),
	get_node("Background/Parallax2D/Parallax_5")
]

@onready var ip_line_edit: LineEdit = get_node("JoinUI/HBoxContainer/IPLineEdit")
@onready var port_line_edit: LineEdit = get_node("JoinUI/HBoxContainer/PortLineEdit")
@onready var join_button: Button = get_node("JoinUI/JoinButton")
@onready var server_list: ItemList
@onready var refresh_button: Button
@onready var direct_connect_button: Button

var time: float = 0.0
var mouse_influence: float = 0.5
var lobby_manager = null
var servers: Array = []

func _ready() -> void:
	join_button.pressed.connect(_on_join_pressed)
	UIAnimationHelperScript.setup_button_animations(join_button)
	
	lobby_manager = get_node_or_null("/root/LobbyManager")
	server_list = get_node_or_null("JoinUI/ServerList")
	refresh_button = get_node_or_null("JoinUI/RefreshButton")
	direct_connect_button = get_node_or_null("JoinUI/DirectConnectButton")
	
	if lobby_manager != null:
		lobby_manager.server_list_updated.connect(_on_server_list_updated)
		lobby_manager.GetServerList()
		
	if server_list != null:
		server_list.item_selected.connect(_on_server_selected)
		
	if refresh_button != null:
		refresh_button.pressed.connect(_on_refresh_pressed)
		UIAnimationHelperScript.setup_button_animations(refresh_button)
		
	if direct_connect_button != null:
		direct_connect_button.pressed.connect(_on_direct_connect_pressed)
		UIAnimationHelperScript.setup_button_animations(direct_connect_button)

func _process(delta: float) -> void:
	time += delta
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var center: Vector2 = get_viewport_rect().size / 2
	var mouse_dir: Vector2 = (mouse_pos - center).normalized() * mouse_influence

	for i in range(parallax_layers.size()):
		var layer: TextureRect = parallax_layers[i]
		var speed_factor: float = (i + 1) * 0.1
		var auto_offset: Vector2 = Vector2(cos(time * speed_factor), sin(time * speed_factor)) * 20
		var mouse_offset: Vector2 = mouse_dir * (i + 1) * 10
		layer.position = auto_offset + mouse_offset

func _on_join_pressed() -> void:
	if server_list != null and server_list.is_anything_selected():
		var selected_idx: int = server_list.get_selected_items()[0]
		if selected_idx >= 0 and selected_idx < servers.size():
			var server = servers[selected_idx]
			_join_server(server["ip_address"], int(server["port"]))
	else:
		_on_direct_connect_pressed()

func _on_direct_connect_pressed() -> void:
	var ip: String = ip_line_edit.text
	if ip == "":
		ip = "127.0.0.1"
	
	var port_text: String = port_line_edit.text
	var port: int = port_text.to_int() if port_text != "" else GameManager.DefaultPort
	
	_join_server(ip, port)

func _join_server(ip: String, port: int) -> void:
	join_button.disabled = true
	join_button.text = "Connecting..."
	
	multiplayer.connected_to_server.connect(_on_successfully_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	GameManager.JoinGame(ip, port)

func _on_successfully_connected() -> void:
	get_tree().change_scene_to_file("uid://bjnqqapnkk8uq")

func _on_connection_failed() -> void:
	join_button.disabled = false
	join_button.text = "Join Game"
	var error_label = Label.new()
	error_label.text = "Failed to connect: No server found"
	error_label.modulate = Color.RED
	get_node("JoinUI").add_child(error_label)
	await get_tree().create_timer(3.0).timeout
	error_label.queue_free()

func _on_refresh_pressed() -> void:
	if lobby_manager != null:
		lobby_manager.GetServerList()
		if refresh_button != null:
			refresh_button.disabled = true
			await get_tree().create_timer(1.0).timeout
			refresh_button.disabled = false

func _on_server_list_updated(server_array: Array) -> void:
	servers = server_array
	if server_list == null:
		return
		
	server_list.clear()
	for server in servers:
		var name: String = server["name"]
		var players: String = "%s/%s" % [server["current_players"], server["max_players"]]
		var map: String = server.get("map", "Unknown")
		var host: String = server["host_username"]
		var locked: String = "🔒 " if server["password_protected"] else ""
		
		server_list.add_item("%s%s - %s - %s - Host: %s" % [locked, name, players, map, host])

func _on_server_selected(index: int) -> void:
	if ip_line_edit != null and index >= 0 and index < servers.size():
		var server = servers[index]
		ip_line_edit.text = server["ip_address"]
		if port_line_edit != null:
			port_line_edit.text = str(server["port"])
