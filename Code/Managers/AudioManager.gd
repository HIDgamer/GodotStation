extends Node2D
class_name AudioManager

# Sound configuration
const MAX_SOUNDS = 32  # Maximum concurrent sounds
const MAX_DISTANCE = 15 * 32  # Maximum hearing distance in pixels (15 tiles)
const DISTANCE_MODEL = 1.8  # Higher values make sounds fade faster with distance
const SOUND_OCCLUSION = true  # Whether sounds are blocked by walls
const OCCLUSION_FACTOR = 0.6  # How much walls reduce sound (0-1)

# Sound player references
var sound_players = []
var active_sounds = {}
var sound_queue = []

# Sound banks by category
var sound_banks = {
	"footstep": {
		"floor": ["footstep_floor1", "footstep_floor2", "footstep_floor3"],
		"metal": ["footstep_metal1", "footstep_metal2", "footstep_metal3"],
		"catwalk": ["footstep_catwalk1", "footstep_catwalk2"],
		"plating": ["footstep_plating1", "footstep_plating2"],
		"wood": ["footstep_wood1", "footstep_wood2"],
		"carpet": ["footstep_carpet1", "footstep_carpet2"],
		"default": ["footstep_floor1", "footstep_floor2"]
	},
	"bump": ["bump1", "bump2"],
	"door_open": ["door_open1", "door_open2"],
	"door_close": ["door_close1", "door_close2"],
	"throw": ["throw1", "throw2"],
	"pickup": ["pickup1"],
	"drop": ["drop1", "drop2"],
	"punch": ["punch1", "punch2", "punch3"],
	"hit": ["hit1", "hit2", "hit3"],
	"slip": ["slip1"],
	"ladder_climb": ["ladder1", "ladder2"],
	"crawl": ["crawl1", "crawl2"],
	"rustle": ["rustle1", "rustle2"],
	"body_fall": ["body_fall1", "body_fall2"],
	"grab": ["grab1"],
	"grab_tighten": ["grab_tighten1"],
	"release": ["release1"],
	"choke": ["choke1", "choke2"],
	"disarm": ["disarm1"],
	"space_push": ["space_push1"],
	"space_bump": ["space_bump1"],
	"burn": ["burn1", "burn2"],
	"poison": ["poison1"],
	"gasp": ["gasp1", "gasp2"],
	"choking": ["choking1", "choking2"]
}

# World reference for occlusion checking
var world = null
var spatial_system = null

func _ready():
	# Set up audio player pool
	for i in range(MAX_SOUNDS):
		var player = AudioStreamPlayer2D.new()
		player.bus = "SFX"
		player.max_distance = MAX_DISTANCE
		player.attenuation = DISTANCE_MODEL
		player.finished.connect(_on_sound_finished.bind(player))
		add_child(player)
		sound_players.append(player)
	
	# Get world reference
	world = get_parent()
	if !world or !world.has_method("get_tile_data"):
		# Try to find by name instead
		var root = get_node_or_null("/root")
		if root:
			world = root.find_child("World", true, false)
	
	# Find spatial system
	spatial_system = get_node_or_null("../SpatialManager")
	
	# Load all sound resources
	_preload_sounds()
	
	print("AudioManager: Initialized with ", MAX_SOUNDS, " audio players")

func _preload_sounds():
	# Load all sounds to prevent lag when first played
	for category in sound_banks:
		var sounds = sound_banks[category]
		if sounds is Dictionary:
			for type in sounds:
				for sound_name in sounds[type]:
					var path = "res://Sound/" + sound_name + ".wav"
					if ResourceLoader.exists(path):
						var sound = load(path)
						# We don't need to store these, just preload them into memory
						#print("AudioManager: Preloaded sound ", sound_name)
		else:
			for sound_name in sounds:
				var path = "res://Sound/" + sound_name + ".ogg"
				if ResourceLoader.exists(path):
					var sound = load(path)

func _process(delta):
	# Process sound queue to avoid playing too many sounds at once
	_process_sound_queue()

func _process_sound_queue():
	# Process up to 3 queued sounds per frame
	for i in range(min(3, sound_queue.size())):
		if sound_queue.size() > 0:
			var sound_data = sound_queue.pop_front()
			_play_queued_sound(sound_data)

# Play a positioned sound in the world
func play_positioned_sound(sound_name: String, position: Vector2, volume: float = 1.0, subtype: String = "default"):
	# Structure sound data for queue
	var sound_data = {
		"name": sound_name,
		"position": position,
		"volume": volume,
		"subtype": subtype
	}
	
	# Queue the sound
	sound_queue.append(sound_data)

# Internal function to actually play the sound
func _play_queued_sound(sound_data):
	var sound_name = sound_data["name"]
	var position = sound_data["position"]
	var volume = sound_data["volume"]
	var subtype = sound_data["subtype"]
	
	# Get available player
	var player = _get_available_player()
	if !player:
		# No available players, just return
		return
	
	# Get actual sound file name
	var sound_file = _get_sound_name(sound_name, subtype)
	if sound_file.is_empty():
		print("AudioManager: Sound not found: ", sound_name, " (", subtype, ")")
		return
	
	# Load the sound resource
	var sound_path = "res://Sound/" + sound_file + ".wav"
	if !ResourceLoader.exists(sound_path):
		print("AudioManager: Sound file not found: ", sound_path)
		return
	
	var stream = load(sound_path)
	
	# Calculate final volume based on distance to listener
	var final_volume = _calculate_volume(position, volume)
	
	# Apply occlusion if enabled
	if SOUND_OCCLUSION and world:
		final_volume = _apply_occlusion(position, final_volume)
	
	# Configure player
	player.stream = stream
	player.volume_db = linear_to_db(final_volume)
	player.position = position
	player.pitch_scale = randf_range(0.95, 1.05)  # Slight variation
	
	# Play the sound
	player.play()
	
	# Remember the sound is playing
	active_sounds[player] = {
		"name": sound_name,
		"file": sound_file,
		"position": position,
		"volume": volume,
		"start_time": Time.get_ticks_msec() * 0.001
	}

# Calculate volume based on distance to listener
func _calculate_volume(sound_position: Vector2, base_volume: float) -> float:
	# Find the listener position (player)
	var listener_node = _get_listener_node()
	if !listener_node:
		return base_volume  # No listener, return base volume
	
	var listener_position = listener_node.global_position
	
	# Calculate distance
	var distance = sound_position.distance_to(listener_position)
	
	# Convert to tiles
	distance /= 32.0
	
	# Apply distance falloff
	var max_dist_tiles = MAX_DISTANCE / 32.0
	if distance > max_dist_tiles:
		return 0.0  # Too far away to hear
	
	# Inverse square falloff
	var distance_factor = 1.0 - pow(distance / max_dist_tiles, DISTANCE_MODEL)
	
	# Apply to base volume
	return base_volume * distance_factor

# Get player node (listener)
func _get_listener_node():
	# Try to find player in the scene
	var players = get_tree().get_nodes_in_group("player_controller")
	if players.size() > 0:
		return players[0]
	
	# Alternative: find camera
	var camera = get_viewport().get_camera_2d()
	if camera:
		return camera
	
	# Last resort - find nodes with "Player" in name
	var root = get_tree().root
	var player = root.find_child("*Player*", true, false)
	if player:
		return player
	
	return null

# Apply sound occlusion from walls
func _apply_occlusion(sound_position: Vector2, base_volume: float) -> float:
	var listener_node = _get_listener_node()
	if !listener_node or !world or !world.has_method("is_wall_at"):
		return base_volume  # No occlusion possible
	
	var listener_position = listener_node.global_position
	
	# Convert positions to tile coordinates
	var tile_size = 32  # Assumed tile size
	var sound_tile = Vector2i(int(sound_position.x / tile_size), int(sound_position.y / tile_size))
	var listener_tile = Vector2i(int(listener_position.x / tile_size), int(listener_position.y / tile_size))
	
	# Get z-level (from listener if possible)
	var z_level = 0
	if "current_z_level" in listener_node:
		z_level = listener_node.current_z_level
	
	# Count walls between sound and listener
	var walls_between = _count_walls_between(sound_tile, listener_tile, z_level)
	
	# Apply occlusion based on wall count
	var occlusion_multiplier = pow(OCCLUSION_FACTOR, walls_between)
	
	return base_volume * occlusion_multiplier

# Count walls between two tiles
func _count_walls_between(start_tile: Vector2i, end_tile: Vector2i, z_level: int) -> int:
	if !world or !world.has_method("is_wall_at"):
		return 0  # Can't check for walls
	
	var wall_count = 0
	
	# Use Bresenham's line algorithm to check tiles
	var tiles_in_line = _get_line_tiles(start_tile, end_tile)
	
	# Check each tile for a wall
	for tile in tiles_in_line:
		if world.is_wall_at(tile, z_level):
			wall_count += 1
	
	return wall_count

# Bresenham's line algorithm to get tiles along a line
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
		if tile != start and tile != end:  # Skip start and end tiles
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

# Get an available audio player
func _get_available_player():
	# First try to find an idle player
	for player in sound_players:
		if !player.playing:
			return player
	
	# If none are available, find the oldest one to replace
	var oldest_time = INF
	var oldest_player = null
	
	for player in active_sounds:
		var sound_data = active_sounds[player]
		if sound_data["start_time"] < oldest_time:
			oldest_time = sound_data["start_time"]
			oldest_player = player
	
	# Stop the oldest player and return it
	if oldest_player:
		oldest_player.stop()
	
	return oldest_player

# Get a specific sound file name
func _get_sound_name(sound_name: String, subtype: String = "default") -> String:
	# Check if this category exists
	if !sound_banks.has(sound_name):
		print("AudioManager: Unknown sound category: ", sound_name)
		return ""
	
	var sounds = sound_banks[sound_name]
	
	# Check if this is a category with subtypes
	if sounds is Dictionary:
		# Try to get the specific subtype
		if sounds.has(subtype):
			var options = sounds[subtype]
			return options[randi() % options.size()]
		# Fall back to default
		elif sounds.has("default"):
			var options = sounds["default"]
			return options[randi() % options.size()]
		# Just take the first subtype
		else:
			var first_type = sounds.keys()[0]
			var options = sounds[first_type]
			return options[randi() % options.size()]
	# Simple array of options
	else:
		return sounds[randi() % sounds.size()]

# Play a global (non-positioned) sound
func play_global_sound(sound_name: String, volume: float = 1.0):
	# Get actual sound file name
	var sound_file = _get_sound_name(sound_name)
	if sound_file.is_empty():
		return
	
	# Load the sound resource
	var sound_path = "res://Sound/" + sound_file + ".wav"
	if !ResourceLoader.exists(sound_path):
		return
	
	var player = _get_available_player()
	if !player:
		return
	
	var stream = load(sound_path)
	
	# Configure player for global sound
	player.stream = stream
	player.volume_db = linear_to_db(volume)
	player.position = Vector2.ZERO
	player.max_distance = 100000  # Effectively global
	
	# Play the sound
	player.play()
	
	# Return to default max distance when done
	player.max_distance = MAX_DISTANCE

# Callback when sound finishes playing
func _on_sound_finished(player):
	# Remove from active sounds
	if active_sounds.has(player):
		active_sounds.erase(player)
