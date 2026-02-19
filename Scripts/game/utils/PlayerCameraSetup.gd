extends Camera2D

@export var follow_player: bool = true
@export var zoom_level: float = 3
@export var smoothing_enabled: bool = true

var _parent_player: Node = null
var _is_local_player: bool = false

func _ready() -> void:
	_parent_player = get_parent()
	_refresh_local_state()

func _process(_delta: float) -> void:
	_refresh_local_state()

	if not _is_local_player:
		return
	
	if not is_current():
		make_current()

	if follow_player and _parent_player is Node2D:
		global_position = (_parent_player as Node2D).global_position

func _refresh_local_state() -> void:
	if _parent_player == null:
		_parent_player = get_parent()

	var should_be_local := _parent_player != null and _parent_player.is_multiplayer_authority()
	_is_local_player = should_be_local
	enabled = _is_local_player
	position_smoothing_enabled = smoothing_enabled
	if _is_local_player:
		zoom = Vector2(zoom_level, zoom_level)
