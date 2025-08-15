extends Node2D
class_name AudioManager

# Audio system configuration
@export_group("Audio Settings")
@export var max_sounds: int = 32
@export var max_distance: float = 15 * 32
@export var distance_model: float = 1.8
@export var sound_occlusion_enabled: bool = true
@export var occlusion_factor: float = 0.6
@export var max_sounds_per_frame: int = 3
@export var audio_bus_name: String = "SFX"

# Performance settings
@export_group("Performance")
@export var distance_check_interval: float = 0.1
@export var occlusion_check_interval: float = 0.2
@export var cache_refresh_interval: float = 5.0
@export var sound_cooldown_time: float = 0.05
@export var max_queue_size: int = 100

# Debug settings
@export_group("Debug")
@export var debug_audio: bool = false
@export var log_sound_events: bool = false

# Audio player management
var sound_players: Array = []
var active_sounds: Dictionary = {}
var sound_queue: Array = []

# System references
var asset_registry = null
var world = null
var spatial_system = null

# Audio cache and optimization
var cached_audio_files: Dictionary = {}
var sound_cooldowns: Dictionary = {}
var distance_cache: Dictionary = {}
var occlusion_cache: Dictionary = {}

# Performance tracking
var distance_update_timer: float = 0.0
var occlusion_update_timer: float = 0.0
var cache_refresh_timer: float = 0.0
var sounds_played_this_frame: int = 0

# Sound categories for organization
var sound_categories: Dictionary = {
	"footsteps": ["step", "walk", "run"],
	"impacts": ["hit", "thud", "crash"],
	"machinery": ["machine", "engine", "motor"],
	"environment": ["wind", "water", "fire"],
	"ui": ["button", "click", "beep"],
	"combat": ["gunshot", "explosion", "sword"],
	"medical": ["heartbeat", "beep", "scan"]
}

func _ready():
	_initialize_audio_system()

# Initialization functions
func _initialize_audio_system():
	_setup_audio_players()
	_find_system_references()
	_cache_audio_files()
	_setup_performance_timers()
	
	print("AudioManager initialized with ", max_sounds, " players and ", cached_audio_files.size(), " cached files")

func _setup_audio_players():
	sound_players.clear()
	
	for i in range(max_sounds):
		var player = AudioStreamPlayer2D.new()
		player.bus = audio_bus_name
		player.max_distance = max_distance
		player.attenuation = distance_model
		player.finished.connect(_on_sound_finished.bind(player))
		add_child(player)
		sound_players.append(player)

func _find_system_references():
	var root = get_tree().root
	
	# Find asset registry
	asset_registry = root.find_child("AssetRegistry", true, false)
	if not asset_registry:
		var nodes = get_tree().get_nodes_in_group("asset_registry")
		if nodes.size() > 0:
			asset_registry = nodes[0]
	
	# Find world reference
	world = get_parent()
	if not world or not world.has_method("get_tile_data"):
		world = root.find_child("World", true, false)
	
	# Find spatial system
	spatial_system = get_node_or_null("../SpatialManager")

func _cache_audio_files():
	if not asset_registry:
		return
	
	cached_audio_files.clear()
	var all_assets = asset_registry.get_all_assets()
	
	for asset_path in all_assets:
		if _is_audio_file(asset_path):
			var file_name = asset_path.get_file().get_basename().to_lower()
			
			if not cached_audio_files.has(file_name):
				cached_audio_files[file_name] = []
			cached_audio_files[file_name].append(asset_path)
	
	if debug_audio:
		print("Cached ", cached_audio_files.size(), " audio file categories")

func _setup_performance_timers():
	distance_update_timer = 0.0
	occlusion_update_timer = 0.0
	cache_refresh_timer = 0.0

# Main processing loop
func _process(delta):
	_update_performance_timers(delta)
	_process_sound_queue()
	_clean_expired_cooldowns(delta)
	sounds_played_this_frame = 0

func _update_performance_timers(delta):
	distance_update_timer += delta
	occlusion_update_timer += delta
	cache_refresh_timer += delta
	
	if cache_refresh_timer >= cache_refresh_interval:
		_refresh_caches()
		cache_refresh_timer = 0.0

func _process_sound_queue():
	var sounds_to_process = min(max_sounds_per_frame - sounds_played_this_frame, sound_queue.size())
	
	for i in range(sounds_to_process):
		if sound_queue.size() > 0:
			var sound_data = sound_queue.pop_front()
			_play_queued_sound(sound_data)
			sounds_played_this_frame += 1

# Public sound playing interface
func play_positioned_sound(sound_name: String, position: Vector2, volume: float = 1.0, variant: String = ""):
	if not _can_play_sound(sound_name, position):
		return
	
	if sound_queue.size() >= max_queue_size:
		if debug_audio:
			print("Sound queue full, dropping sound: ", sound_name)
		return
	
	var sound_data = {
		"name": sound_name,
		"position": position,
		"volume": volume,
		"variant": variant,
		"timestamp": Time.get_ticks_msec()
	}
	
	sound_queue.append(sound_data)
	_apply_sound_cooldown(sound_name, position)

func play_global_sound(sound_name: String, volume: float = 1.0, variant: String = ""):
	if not _can_play_sound(sound_name, Vector2.ZERO):
		return
	
	var player = _get_available_player()
	if not player:
		return
	
	var sound_path = _find_best_sound_match(sound_name, variant)
	if sound_path.is_empty():
		return
	
	var stream = asset_registry.load_asset(sound_path)
	if not stream:
		return
	
	player.stream = stream
	player.volume_db = linear_to_db(volume)
	player.position = Vector2.ZERO
	player.max_distance = 100000
	player.pitch_scale = randf_range(0.95, 1.05)
	player.play()
	
	# Reset max distance after playing
	player.max_distance = max_distance
	
	_apply_sound_cooldown(sound_name, Vector2.ZERO)

func play_random_from_category(category: String, position: Vector2, volume: float = 1.0):
	var matching_sounds = _get_sounds_in_category(category)
	
	if matching_sounds.size() > 0:
		var random_sound = matching_sounds[randi() % matching_sounds.size()]
		play_positioned_sound(random_sound, position, volume)

# Sound processing and management
func _play_queued_sound(sound_data: Dictionary):
	var player = _get_available_player()
	if not player:
		return
	
	var sound_path = _find_best_sound_match(sound_data.name, sound_data.get("variant", ""))
	if sound_path.is_empty():
		return
	
	var stream = asset_registry.load_asset(sound_path)
	if not stream:
		return
	
	var final_volume = _calculate_volume(sound_data.position, sound_data.volume)
	
	if sound_occlusion_enabled and world:
		final_volume = _apply_occlusion(sound_data.position, final_volume)
	
	player.stream = stream
	player.volume_db = linear_to_db(final_volume)
	player.position = sound_data.position
	player.pitch_scale = randf_range(0.95, 1.05)
	player.play()
	
	active_sounds[player] = {
		"name": sound_data.name,
		"path": sound_path,
		"position": sound_data.position,
		"volume": sound_data.volume,
		"start_time": Time.get_ticks_msec() * 0.001
	}
	
	if log_sound_events:
		print("Playing sound: ", sound_data.name, " at ", sound_data.position)

func _get_available_player() -> AudioStreamPlayer2D:
	# First try to find a non-playing player
	for player in sound_players:
		if not player.playing:
			return player
	
	# If all are playing, find the oldest one
	var oldest_time = INF
	var oldest_player = null
	
	for player in active_sounds:
		var sound_data = active_sounds[player]
		if sound_data.start_time < oldest_time:
			oldest_time = sound_data.start_time
			oldest_player = player
	
	if oldest_player:
		oldest_player.stop()
		return oldest_player
	
	return null

# Sound matching and caching
func _find_best_sound_match(sound_name: String, variant: String = "") -> String:
	var clean_name = sound_name.to_lower()
	var search_terms = []
	
	# Build search terms with variant
	if not variant.is_empty():
		search_terms.append(clean_name + "_" + variant.to_lower())
		search_terms.append(variant.to_lower() + "_" + clean_name)
	
	search_terms.append(clean_name)
	
	# Try exact matches first
	for term in search_terms:
		if cached_audio_files.has(term):
			var options = cached_audio_files[term]
			return options[randi() % options.size()]
	
	# Try partial matches
	for cached_name in cached_audio_files.keys():
		if cached_name.contains(clean_name) or clean_name.contains(cached_name):
			var options = cached_audio_files[cached_name]
			return options[randi() % options.size()]
	
	# Try similarity matching (expensive, only as last resort)
	return _find_similar_sound(clean_name)

func _find_similar_sound(sound_name: String) -> String:
	var similarity_scores = {}
	var best_score = 0.3
	var best_match = ""
	
	for cached_name in cached_audio_files.keys():
		var score = _calculate_similarity(sound_name, cached_name)
		if score > best_score:
			best_score = score
			best_match = cached_name
	
	if not best_match.is_empty():
		var options = cached_audio_files[best_match]
		return options[randi() % options.size()]
	
	return ""

func _calculate_similarity(str1: String, str2: String) -> float:
	var len1 = str1.length()
	var len2 = str2.length()
	
	if len1 == 0 and len2 == 0:
		return 1.0
	if len1 == 0 or len2 == 0:
		return 0.0
	
	var max_len = max(len1, len2)
	var distance = _levenshtein_distance(str1, str2)
	
	return 1.0 - (float(distance) / float(max_len))

func _levenshtein_distance(str1: String, str2: String) -> int:
	var len1 = str1.length()
	var len2 = str2.length()
	
	var matrix = []
	for i in range(len1 + 1):
		matrix.append([])
		for j in range(len2 + 1):
			matrix[i].append(0)
	
	for i in range(len1 + 1):
		matrix[i][0] = i
	for j in range(len2 + 1):
		matrix[0][j] = j
	
	for i in range(1, len1 + 1):
		for j in range(1, len2 + 1):
			var cost = 0 if str1[i-1] == str2[j-1] else 1
			matrix[i][j] = min(
				matrix[i-1][j] + 1,
				matrix[i][j-1] + 1,
				matrix[i-1][j-1] + cost
			)
	
	return matrix[len1][len2]

# Volume and distance calculations
func _calculate_volume(sound_position: Vector2, base_volume: float) -> float:
	var listener_node = _get_listener_node()
	if not listener_node:
		return base_volume
	
	var listener_position = listener_node.global_position
	var distance_key = str(sound_position) + "_" + str(listener_position)
	
	# Use cached distance if available and recent
	if distance_update_timer < distance_check_interval and distance_cache.has(distance_key):
		var cached_data = distance_cache[distance_key]
		return base_volume * cached_data.factor
	
	var distance = sound_position.distance_to(listener_position) / 32.0
	var max_dist_tiles = max_distance / 32.0
	
	if distance > max_dist_tiles:
		distance_cache[distance_key] = {"factor": 0.0, "timestamp": Time.get_ticks_msec()}
		return 0.0
	
	var distance_factor = 1.0 - pow(distance / max_dist_tiles, distance_model)
	distance_cache[distance_key] = {"factor": distance_factor, "timestamp": Time.get_ticks_msec()}
	
	return base_volume * distance_factor

func _apply_occlusion(sound_position: Vector2, base_volume: float) -> float:
	var listener_node = _get_listener_node()
	if not listener_node or not world:
		return base_volume
	
	var listener_position = listener_node.global_position
	var occlusion_key = str(sound_position) + "_" + str(listener_position)
	
	# Use cached occlusion if available and recent
	if occlusion_update_timer < occlusion_check_interval and occlusion_cache.has(occlusion_key):
		var cached_data = occlusion_cache[occlusion_key]
		return base_volume * cached_data.multiplier
	
	var tile_size = 32
	var sound_tile = Vector2i(int(sound_position.x / tile_size), int(sound_position.y / tile_size))
	var listener_tile = Vector2i(int(listener_position.x / tile_size), int(listener_position.y / tile_size))
	
	var z_level = 0
	if "current_z_level" in listener_node:
		z_level = listener_node.current_z_level
	
	var walls_between = _count_walls_between(sound_tile, listener_tile, z_level)
	var occlusion_multiplier = pow(occlusion_factor, walls_between)
	
	occlusion_cache[occlusion_key] = {"multiplier": occlusion_multiplier, "timestamp": Time.get_ticks_msec()}
	
	return base_volume * occlusion_multiplier

func _get_listener_node():
	# Cache the listener node for performance
	var players = get_tree().get_nodes_in_group("player_controller")
	if players.size() > 0:
		return players[0]
	
	var camera = get_viewport().get_camera_2d()
	if camera:
		return camera
	
	return null

# Occlusion and wall detection
func _count_walls_between(start_tile: Vector2i, end_tile: Vector2i, z_level: int) -> int:
	if not world or not world.has_method("is_wall_at"):
		return 0
	
	var wall_count = 0
	var tiles_in_line = _get_line_tiles(start_tile, end_tile)
	
	for tile in tiles_in_line:
		if world.is_wall_at(tile, z_level):
			wall_count += 1
	
	return wall_count

func _get_line_tiles(start: Vector2i, end: Vector2i) -> Array:
	var tiles = []
	var x0 = start.x
	var y0 = start.y
	var x1 = end.x
	var y1 = end.y
	
	var dx = abs(x1 - x0)
	var dy = -abs(y1 - y0)
	var sx = 1 if x0 < x1 else -1
	var sy = 1 if y0 < y1 else -1
	var err = dx + dy
	
	while true:
		var tile = Vector2i(x0, y0)
		if tile != start and tile != end:
			tiles.append(tile)
		
		if x0 == x1 and y0 == y1:
			break
			
		var e2 = 2 * err
		if e2 >= dy:
			if x0 == x1:
				break
			err += dy
			x0 += sx
		
		if e2 <= dx:
			if y0 == y1:
				break
			err += dx
			y0 += sy
	
	return tiles

# Cooldown and performance management
func _can_play_sound(sound_name: String, position: Vector2) -> bool:
	var cooldown_key = sound_name + "_" + str(position)
	
	if sound_cooldowns.has(cooldown_key):
		var cooldown_data = sound_cooldowns[cooldown_key]
		var current_time = Time.get_ticks_msec() * 0.001
		
		if current_time < cooldown_data.expires:
			return false
	
	return true

func _apply_sound_cooldown(sound_name: String, position: Vector2):
	var cooldown_key = sound_name + "_" + str(position)
	var current_time = Time.get_ticks_msec() * 0.001
	
	sound_cooldowns[cooldown_key] = {
		"expires": current_time + sound_cooldown_time
	}

func _clean_expired_cooldowns(delta):
	var current_time = Time.get_ticks_msec() * 0.001
	var keys_to_remove = []
	
	for key in sound_cooldowns:
		if current_time > sound_cooldowns[key].expires:
			keys_to_remove.append(key)
	
	for key in keys_to_remove:
		sound_cooldowns.erase(key)

func _refresh_caches():
	var current_time = Time.get_ticks_msec()
	var cache_lifetime_ms = 5000  # 5 seconds
	
	# Clean old distance cache entries
	var distance_keys_to_remove = []
	for key in distance_cache:
		if current_time - distance_cache[key].timestamp > cache_lifetime_ms:
			distance_keys_to_remove.append(key)
	
	for key in distance_keys_to_remove:
		distance_cache.erase(key)
	
	# Clean old occlusion cache entries
	var occlusion_keys_to_remove = []
	for key in occlusion_cache:
		if current_time - occlusion_cache[key].timestamp > cache_lifetime_ms:
			occlusion_keys_to_remove.append(key)
	
	for key in occlusion_keys_to_remove:
		occlusion_cache.erase(key)

# Utility and helper functions
func _is_audio_file(file_path: String) -> bool:
	var extension = file_path.get_extension().to_lower()
	return extension in ["ogg", "wav", "mp3"]

func _get_sounds_in_category(category: String) -> Array:
	var matching_sounds = []
	var category_keywords = sound_categories.get(category.to_lower(), [])
	
	for sound_name in cached_audio_files.keys():
		for keyword in category_keywords:
			if sound_name.contains(keyword):
				matching_sounds.append(sound_name)
				break
	
	return matching_sounds

# Signal handlers
func _on_sound_finished(player):
	if active_sounds.has(player):
		active_sounds.erase(player)

# Public interface functions
func refresh_audio_cache():
	_cache_audio_files()

func get_available_sounds() -> Array:
	return cached_audio_files.keys()

func get_active_sound_count() -> int:
	return active_sounds.size()

func get_queue_size() -> int:
	return sound_queue.size()

func clear_sound_queue():
	sound_queue.clear()

func stop_all_sounds():
	for player in sound_players:
		if player.playing:
			player.stop()
	
	active_sounds.clear()

func set_master_volume(volume: float):
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(audio_bus_name), linear_to_db(volume))

func get_debug_info() -> Dictionary:
	return {
		"active_sounds": active_sounds.size(),
		"queued_sounds": sound_queue.size(),
		"cached_files": cached_audio_files.size(),
		"distance_cache_size": distance_cache.size(),
		"occlusion_cache_size": occlusion_cache.size(),
		"cooldown_entries": sound_cooldowns.size(),
		"sounds_this_frame": sounds_played_this_frame
	}
