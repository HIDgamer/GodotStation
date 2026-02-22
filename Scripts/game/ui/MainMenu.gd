extends Control

# ─── Scene paths ─────────────────────────────────────────────────────────────
# Update these to match your actual scene paths if they differ.
const COMMUNICATIONS_SCENE = "res://Scenes/game/ui/Communications.tscn"
const FALLBACK_MAP          = "uid://dible6m71p44g"

# ─── UI node references ──────────────────────────────────────────────────────
@onready var _status_label   : Label       = $VBox/StatusLabel
@onready var _menu_panel     : Control     = $VBox/MenuPanel
@onready var _host_panel     : Control     = $VBox/HostPanel
@onready var _join_panel     : Control     = $VBox/JoinPanel

# Host panel fields
@onready var _host_port_spin : SpinBox     = $VBox/HostPanel/PortSpin
@onready var _host_name_edit : LineEdit    = $VBox/HostPanel/NameEdit
@onready var _host_max_spin  : SpinBox     = $VBox/HostPanel/MaxSpin

# Join panel fields
@onready var _join_ip_edit   : LineEdit    = $VBox/JoinPanel/IpEdit
@onready var _join_port_spin : SpinBox     = $VBox/JoinPanel/PortSpin

var _game_manager : Node = null

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_game_manager = get_node_or_null("/root/GameManager")

	if _game_manager == null:
		_set_status("ERROR: GameManager autoload not found.", true)
		return

	# Wire GameManager signals so we react to connection results.
	if _game_manager.has_signal("ConnectionFailed"):
		_game_manager.connect("ConnectionFailed", _on_connection_failed)

	# Read hub arguments.  If --join-server was passed, GameManager's
	# ParseHubArguments() already deferred the join — just show a status
	# label and wait.  Otherwise show the menu.
	var args := OS.get_cmdline_args()
	var auto_join_target := ""
	for i in range(args.size()):
		if args[i] == "--join-server" and i + 1 < args.size():
			auto_join_target = args[i + 1]
			break

	if auto_join_target != "":
		_show_panel(null)   # hide everything
		_set_status("Connecting to %s…" % auto_join_target)
	else:
		_show_panel(_menu_panel)
		_set_status("")


# ─── Panel helpers ────────────────────────────────────────────────────────────
func _show_panel(panel : Control) -> void:
	for p in [_menu_panel, _host_panel, _join_panel]:
		if p != null:
			p.visible = (p == panel)


func _set_status(msg : String, is_error : bool = false) -> void:
	if _status_label == null:
		return
	_status_label.text = msg
	_status_label.add_theme_color_override(
		"font_color",
		Color.RED if is_error else Color(0.7, 0.9, 1.0)
	)


# ─── Menu buttons ─────────────────────────────────────────────────────────────
func _on_btn_host_pressed() -> void:
	_show_panel(_host_panel)
	_set_status("")


func _on_btn_join_pressed() -> void:
	_show_panel(_join_panel)
	_set_status("")


func _on_btn_back_from_host_pressed() -> void:
	_show_panel(_menu_panel)
	_set_status("")


func _on_btn_back_from_join_pressed() -> void:
	_show_panel(_menu_panel)
	_set_status("")


# ─── Host ─────────────────────────────────────────────────────────────────────
func _on_btn_start_host_pressed() -> void:
	if _game_manager == null:
		return

	var port := int(_host_port_spin.value) if _host_port_spin else 7777
	var name := _host_name_edit.text.strip_edges() if _host_name_edit else "My Server"
	var max_p := int(_host_max_spin.value) if _host_max_spin else 4

	if name == "":
		name = "My Server"

	_game_manager.ServerName = name
	_game_manager.MaxPlayers = max_p

	_set_status("Starting host on port %d…" % port)
	_game_manager.HostGame(port)
	# HostGame() calls GetTree().change_scene_to_file(COMMUNICATIONS_SCENE)
	# so the scene will transition automatically on success.


# ─── Join ─────────────────────────────────────────────────────────────────────
func _on_btn_start_join_pressed() -> void:
	if _game_manager == null:
		return

	var ip   := _join_ip_edit.text.strip_edges() if _join_ip_edit else "127.0.0.1"
	var port := int(_join_port_spin.value) if _join_port_spin else 7777

	if ip == "":
		_set_status("Enter a server IP address.", true)
		return

	_set_status("Connecting to %s:%d…" % [ip, port])
	_game_manager.JoinGame(ip, port)
	# OnConnectedToServer() in GameManager defers ChangeSceneToFile(COMMUNICATIONS_SCENE).


# ─── GameManager signal handlers ─────────────────────────────────────────────
func _on_connection_failed() -> void:
	_show_panel(_join_panel)
	_set_status("Connection failed. Check the IP / port and try again.", true)
