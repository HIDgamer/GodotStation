extends Control

@onready var video_player: VideoStreamPlayer = $VideoStreamPlayer
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer
@onready var texture_rect: TextureRect = $TextureRect

var music_loops: int = 1
var music_volume: float = 0.5
var current_loops: int = 0
var music_stop_timer: Timer = null

var _default_screensavers: Array[String] = [
	"uid://m44b5scm3sf2",
	"uid://baddbapvxhyjw",
	"uid://s331mwi01abw",
	"uid://bttyceok81cxh",
	"uid://cs4b47j652yok",
	"uid://c2kq5gljee3h0"
]

func _ready() -> void:
	if not multiplayer.has_multiplayer_peer():
		push_error("Lobby loaded without valid connection")
		get_tree().change_scene_to_file("uid://dek0evng00wqt")
		return
	
	if not multiplayer.is_server() and multiplayer.get_unique_id() <= 1:
		push_error("Lobby loaded without valid peer ID")
		get_tree().change_scene_to_file("uid://dek0evng00wqt")
		return
	
	if GameManager.CurrentVideoUid != "":
		load_video(GameManager.CurrentVideoUid)
	else:
		if multiplayer.is_server():
			var random_screensaver = _default_screensavers.pick_random()
			GameManager.CurrentVideoUid = random_screensaver

			load_video(random_screensaver)

			GameManager.SyncMedia("video", random_screensaver, 0, 0.5)
		else:
			GameManager.rpc_id(1, "RequestCurrentVideo")

	audio_player.finished.connect(_on_audio_finished)
	GameManager.MediaSyncReceived.connect(load_media)
	GameManager.RequestVideoSync.connect(_on_request_video_sync)
	GameManager.GameStarted.connect(_on_game_started)
	
	if GameManager.has_signal("LobbyStateSynced"):
		GameManager.LobbyStateSynced.connect(_on_lobby_state_synced)

	_animate_lobby_entrance()

func _on_audio_finished() -> void:
	if current_loops < music_loops:
		current_loops += 1
		audio_player.play()
	else:
		current_loops = 0

func load_video(path: String) -> void:
	if video_player.is_playing():
		video_player.stop()
	video_player.stream = load(path)
	video_player.loop = true
	video_player.play()
	if not video_player.is_playing():
		video_player.play()


func load_media(type: String, path: String, loops: int = 0, volume: float = 0.5) -> void:
	match type:
		"music":
			_load_music(path, loops, volume)
		"video":
			load_video(path)
		"art":
			_load_art(path)

func _load_music(path: String, loops: int = 1, volume: float = 0.5) -> void:
	if audio_player.playing:
		audio_player.stop()

	var stream = null
	if path.begins_with("res://"):
		stream = load(path)
		if stream:
			stream.loop = false
	else:
		stream = AudioStreamOggVorbis.load_from_file(path)
		if stream:
			stream.loop = true
			var length = stream.get_length()
			var total_time = length * loops
			if total_time > 0:
				if music_stop_timer:
					music_stop_timer.queue_free()
				music_stop_timer = Timer.new()
				music_stop_timer.wait_time = total_time
				music_stop_timer.one_shot = true
				music_stop_timer.timeout.connect(_on_music_stop_timer_timeout)
				add_child(music_stop_timer)
				music_stop_timer.start()
		else:
			print("Failed to load external music file: ", path)

	audio_player.stream = stream
	audio_player.volume_db = linear_to_db(volume)
	music_loops = loops
	current_loops = 0
	audio_player.play()

func _load_art(path: String) -> void:
	var image = Image.new()
	if image.load(path) == OK:
		var texture = ImageTexture.create_from_image(image)
		texture_rect.texture = texture
		
		var img_size = image.get_size()
		var viewport_scale = min(get_viewport_rect().size.x / img_size.x, get_viewport_rect().size.y / img_size.y) * 0.8
		texture_rect.scale = Vector2(viewport_scale, viewport_scale)
		texture_rect.position = (get_viewport_rect().size - img_size * viewport_scale) / 2

func _on_music_stop_timer_timeout() -> void:
	audio_player.stop()

func _on_game_started() -> void:
	if video_player.is_playing():
		video_player.stop()

func _on_request_video_sync(video_uid: String, requester_id: int) -> void:
	if multiplayer.is_server() and video_player.is_playing():
		var pos = video_player.stream_position
		GameManager.rpc_id(requester_id, "ReceiveVideoSync", video_uid, pos)

func _animate_lobby_entrance() -> void:
	video_player.modulate.a = 0.0
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(video_player, "modulate:a", 1.0, 1.5)

func _on_lobby_state_synced(time_left: float, paused: bool, video_uid: String) -> void:
	var lobby_timer = get_node_or_null(NodePath("LobbyTimer"))
	if lobby_timer:
		lobby_timer.paused = paused
		lobby_timer.wait_time = time_left
	if video_uid != "" and GameManager.CurrentVideoUid != video_uid:
		GameManager.CurrentVideoUid = video_uid
		load_video(video_uid)
