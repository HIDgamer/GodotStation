extends Control
## Minimal connect/host/start-round UI - the Phase 2 "lobby" surface.
## Deliberately plain-looking; the roadmap explicitly calls UI presentation
## open for a creative pass later, this just needs to work.

@onready var _address_edit: LineEdit = %AddressEdit
@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton
@onready var _start_round_button: Button = %StartRoundButton
@onready var _status_label: Label = %StatusLabel

func _ready() -> void:
	_start_round_button.visible = false
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_start_round_button.pressed.connect(_on_start_round_pressed)

	NetworkManager.ServerCreated.connect(_on_server_created)
	NetworkManager.ConnectedToServer.connect(_on_connected_to_server)
	NetworkManager.ConnectionFailed.connect(_on_connection_failed)

func _on_host_pressed() -> void:
	_status_label.text = "Hosting..."
	NetworkManager.Host()

func _on_join_pressed() -> void:
	var address := _address_edit.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	_status_label.text = "Connecting to %s..." % address
	NetworkManager.Join(address)

func _on_start_round_pressed() -> void:
	var game_root := get_tree().current_scene
	if game_root and game_root.has_method("ServerStartRound"):
		game_root.ServerStartRound()
	visible = false

func _on_server_created() -> void:
	_status_label.text = "Hosting."
	_start_round_button.visible = true

func _on_connected_to_server() -> void:
	_status_label.text = "Connected. Waiting for the host to start the round."

func _on_connection_failed() -> void:
	_status_label.text = "Connection failed."
