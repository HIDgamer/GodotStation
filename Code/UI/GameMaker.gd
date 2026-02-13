extends Control

var UIAnimationHelperScript = load("uid://dop12m7xxcnmg")

@onready var parallax_layers: Array = [
	get_node("Background/Parallax2D/Parallax_2"),
	get_node("Background/Parallax2D/Parallax_3"),
	get_node("Background/Parallax2D/Parallax_4"),
	get_node("Background/Parallax2D/Parallax_5")
]
@onready var map_option: OptionButton = get_node("GameMakerUI/MapOption")
@onready var player_limit_spin: SpinBox = get_node("GameMakerUI/PlayerLimitSpin")
@onready var port_spin: SpinBox = get_node("GameMakerUI/PortSpin")
@onready var gamemode_option: OptionButton = get_node("GameMakerUI/GamemodeOption")
@onready var create_button: Button = get_node("GameMakerUI/CreateButton")
@onready var join_button: Button = get_node("GameMakerUI/JoinButton")
@onready var server_name_input: LineEdit
@onready var server_desc_input: LineEdit
@onready var password_check: CheckBox

var time: float = 0.0
var mouse_influence: float = 0.5
const MIN_PORT: int = 1024
const MAX_PORT: int = 65535

var map_uids: Dictionary = {
	"DDome": "uid://dible6m71p44g",
	"Hadley's_Hope": "uid://bfswxq626edux"
}

func _ready() -> void:
	map_option.add_item("DDome", 0)
	map_option.add_item("Hadley's_Hope", 1)

	gamemode_option.add_item("PVP-DistressSignal", 0)
	gamemode_option.add_item("PVE-DeathMatch", 1)

	create_button.pressed.connect(_on_create_pressed)
	join_button.pressed.connect(_on_join_pressed)
	
	server_name_input = get_node_or_null("GameMakerUI/ServerNameInput")
	server_desc_input = get_node_or_null("GameMakerUI/ServerDescInput")
	password_check = get_node_or_null("GameMakerUI/PasswordCheck")
	
	_setup_ui_animations()

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

func _on_create_pressed() -> void:
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager == null:
		push_error("GameManager not found!")
		return
	var selected_map_name: String = map_option.get_item_text(map_option.selected)
	var player_limit: int = int(player_limit_spin.value)
	var port: int = int(port_spin.value)
	if port < MIN_PORT or port > MAX_PORT:
		_show_error("Invalid port. Expected %d-%d." % [MIN_PORT, MAX_PORT])
		return
	var selected_gamemode: String = gamemode_option.get_item_text(gamemode_option.selected)

	game_manager.MaxPlayers = player_limit
	game_manager.Gamemode = selected_gamemode
	
	game_manager.CurrentMap = selected_map_name
	
	if server_name_input != null:
		game_manager.ServerName = server_name_input.text if server_name_input.text != "" else "GodotStation Server"
	if server_desc_input != null:
		game_manager.ServerDescription = server_desc_input.text
	if password_check != null:
		game_manager.PasswordProtected = password_check.button_pressed

	print("[GameMakerUI] Creating server: ", game_manager.ServerName)
	print("[GameMakerUI] Map: ", selected_map_name)
	print("[GameMakerUI] Gamemode: ", selected_gamemode)
	print("[GameMakerUI] Players: ", player_limit)
	print("[GameMakerUI] Port: ", port)

	game_manager.HostGame(port)
	get_tree().change_scene_to_file("uid://bjnqqapnkk8uq")

func _on_join_pressed() -> void:
	get_tree().change_scene_to_file("uid://bdsmamrkk7h1i")

func _setup_ui_animations() -> void:
	UIAnimationHelperScript.setup_button_animations(create_button)
	UIAnimationHelperScript.setup_button_animations(join_button)

	map_option.mouse_entered.connect(func(): UIAnimationHelperScript.animate_option_button_pulse(map_option))
	gamemode_option.mouse_entered.connect(func(): UIAnimationHelperScript.animate_option_button_pulse(gamemode_option))

func _show_error(message: String) -> void:
	var error_label := Label.new()
	error_label.text = message
	error_label.modulate = Color.RED
	get_node("GameMakerUI").add_child(error_label)
	await get_tree().create_timer(3.0).timeout
	error_label.queue_free()
