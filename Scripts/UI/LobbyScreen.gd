## LobbyScreen.gd — restored from the old prototype's Lobby.gd (media/
## screensaver lobby: video backdrop, synced music, art display, entrance
## fade). Connection rebuild:
##  - The old screensaver video uids pointed at the deleted ScreenSavers
##    assets; the backdrop art is now the ucfss13 USCM lobby emblem pulled
##    through the DMI pipeline (IconBridge) instead. The video player and
##    the full external-media loaders (ogg/wav/mp3) are kept intact - the
##    media-sync round-trip re-attaches when a server-side media relay
##    exists, and load_media() is already the entry point for it.
##  - Purely decorative/passive - matches the true original Lobby.tscn's
##    scope exactly (no Start Round button/status label of its own). This
##    scene is now embedded inside Communications.gd's lobby SubViewport,
##    which already owns the real interactive round controls (Server tab's
##    Start/Delay buttons) - adding a second, redundant control here would
##    also have no reliable way to reach the embedded GameRoot instance
##    from this deep in Communications' node tree (get_tree().current_scene
##    resolves to Communications itself, not GameRoot, once nested).
extends Control

const LOBBY_EMBLEM_SHEET := "res://Icons/lobby/icon.png"
const LOBBY_EMBLEM_STATE := "uscm"

@onready var video_player: VideoStreamPlayer = $VideoStreamPlayer
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer
@onready var texture_rect: TextureRect = $TextureRect

var music_loops: int = 1
var music_volume: float = 0.5
var current_loops: int = 0

func _ready() -> void:
	_setup_emblem()
	audio_player.finished.connect(_on_audio_finished)
	_animate_lobby_entrance()

# Backdrop art from the DMI pipeline - replaces the deleted screensaver
# videos as the default lobby visual. load_video()/load_media() still accept
# real streams whenever media sync returns.
func _setup_emblem() -> void:
	texture_rect.texture = IconBridge.GetFrame(LOBBY_EMBLEM_SHEET, LOBBY_EMBLEM_STATE)
	texture_rect.modulate = Color(1, 1, 1, 0.9)

func _on_audio_finished() -> void:
	if current_loops < music_loops:
		current_loops += 1
		audio_player.play()
	else:
		current_loops = 0

# ── Media engine (kept from the old prototype - future media-sync entry
#    points; everything below is asset-independent) ─────────────────────────
func load_media(type: String, path: String, loops: int = 0, volume: float = 0.5) -> void:
	match type:
		"music":
			_load_music(path, loops, volume)
		"video":
			load_video(path)
		"art":
			_load_art(path)

func load_video(path: String) -> void:
	if video_player.is_playing():
		video_player.stop()
	var stream = load(path)
	if stream == null and path.get_extension().to_lower() == "ogv":
		var ogv_stream := VideoStreamTheora.new()
		ogv_stream.file = path
		stream = ogv_stream
	video_player.stream = stream
	video_player.loop = true
	video_player.play()

func _load_music(path: String, loops: int = 1, volume: float = 0.5) -> void:
	if audio_player.playing:
		audio_player.stop()

	var stream: AudioStream = null
	if path.begins_with("res://"):
		stream = load(path)
	else:
		stream = load_audio_external(path)

	if stream == null:
		push_error("Could not load music: " + path)
		return

	audio_player.stream = stream
	audio_player.volume_db = linear_to_db(volume)
	music_loops = loops
	current_loops = 0
	audio_player.play()

func load_audio_external(path: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		push_error("External file does not exist: " + path)
		return null

	match path.get_extension().to_lower():
		"ogg":
			return _load_ogg_stream(path)
		"wav":
			return _load_wav_stream(path)
		"mp3":
			return _load_mp3_stream(path)
		_:
			push_error("Unsupported audio format: " + path.get_extension())
			return null

func _load_ogg_stream(path: String) -> AudioStreamOggVorbis:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_error("Failed to read OGG file: " + path)
		return null
	var stream := AudioStreamOggVorbis.new()
	stream.data = bytes
	return stream

func _load_wav_stream(path: String) -> AudioStreamWAV:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open WAV file: " + path)
		return null
	var stream := AudioStreamWAV.new()
	stream.load_wav(file)
	return stream

func _load_mp3_stream(path: String) -> AudioStreamMP3:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_error("Failed to read MP3 file: " + path)
		return null
	var stream := AudioStreamMP3.new()
	stream.data = bytes
	return stream

func _load_art(path: String) -> void:
	var image = Image.new()
	if image.load(path) == OK:
		var texture = ImageTexture.create_from_image(image)
		texture_rect.texture = texture
		var img_size = image.get_size()
		var viewport_scale = min(get_viewport_rect().size.x / img_size.x, get_viewport_rect().size.y / img_size.y) * 0.8
		texture_rect.scale = Vector2(viewport_scale, viewport_scale)
		texture_rect.position = (get_viewport_rect().size - img_size * viewport_scale) / 2

func _animate_lobby_entrance() -> void:
	modulate.a = 0.0
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 1.5)
