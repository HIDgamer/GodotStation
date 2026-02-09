# PlayerCameraSetup.gd
# Handles per-player camera setup ensuring each player sees their own world
# Attach to the Camera2D node in your player scene

extends Camera2D

@export var follow_player: bool = true
@export var zoom_level: float = 3
@export var smoothing_enabled: bool = true

var _parent_player: Node = null
var _is_local_player: bool = false

func _ready() -> void:
	_parent_player = get_parent()
	
	_is_local_player = is_multiplayer_authority()
	
	if _is_local_player:
		enabled = true
		zoom = Vector2(zoom_level, zoom_level)
		print("PlayerCameraSetup: Camera enabled for local player ", _parent_player.name)
	else:
		enabled = false
		print("PlayerCameraSetup: Camera disabled for remote player ", _parent_player.name)

func _process(_delta: float) -> void:
	if not _is_local_player:
		return
	
	if follow_player and _parent_player and "global_position" in _parent_player:
		global_position = _parent_player.global_position
