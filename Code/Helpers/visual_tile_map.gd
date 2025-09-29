extends Node2D
class_name TileMapVisualizer

# Z-level container management
var z_level_containers: Dictionary = {}
var z_level_tilemaps: Dictionary = {}

# System references
@onready var world: Node2D = $".."
@onready var sensory_system = $"../SensorySystem"
@onready var audio_manager = $"../AudioManager"

# Configuration
@export_group("Z-Level Settings")
@export var max_z_levels: int = 10
@export var auto_create_missing_levels: bool = true

@export_group("Visualization Settings")
@export var preserve_existing_tiles: bool = true
@export var debug_enabled: bool = true
@export var auto_visualize_on_ready: bool = false
@export var update_lighting_on_changes: bool = true

@export_group("Performance Settings")
@export var batch_update_size: int = 50
@export var update_delay: float = 0.2
@export var ambient_update_interval: float = 1.0

@export_group("Audio Settings")
@export var enable_construction_sounds: bool = true
@export var construction_volume: float = 0.7
@export var destruction_volume: float = 0.9

# Layer constants for each Z-level
const FLOOR_LAYER = 0
const WALL_LAYER = 1
const OBJECTS_LAYER = 2

# Terrain mapping configurations
var floor_terrain_mapping = {
	"floor": {"terrain_set": 0, "terrain": 2},
	"metal": {"terrain_set": 0, "terrain": 0},
	"carpet": {"terrain_set": 0, "terrain": 1},
	"wood": {"terrain_set": 0, "terrain": 3}
}

var wall_terrain_mapping = {
	"metal": {"terrain_set": 0, "terrain": 1},
	"insulated": {"terrain_set": 0, "terrain": 0},
	"glass": {"terrain_set": 0, "terrain": 0}
}

var object_tile_mapping = {
	"ice": Vector2i(0, 2),
	"fire": Vector2i(1, 2)
}

# Sound mapping for interactions
var interaction_sounds = {
	"button": "button",
	"lever": "lever", 
	"console": "console",
	"chest": "chest"
}

# Ambient sound management
var ambient_emitters: Dictionary = {}
var ambient_update_timer: float = 0.0

func _ready():
	add_to_group("tilemap_visualizer")
	await get_tree().create_timer(update_delay).timeout
	_initialize_system()

func _initialize_system():
	_discover_z_level_containers()
	
	if auto_create_missing_levels:
		_create_missing_z_levels()
	
	_validate_z_level_structure()
	_connect_world_signals()
	_setup_ambient_emitters()
	
	# Register collision methods with world
	_register_collision_methods()
	
	if auto_visualize_on_ready and not preserve_existing_tiles:
		await get_tree().create_timer(0.5).timeout
		visualize_all_z_levels()
	
	print("TileMapVisualizer: Initialized with ", z_level_containers.size(), " Z-levels")

func _discover_z_level_containers():
	z_level_containers.clear()
	z_level_tilemaps.clear()
	
	for child in get_children():
		if child.name.begins_with("Z_Level_"):
			var z_level_str = child.name.replace("Z_Level_", "")
			var z_level = z_level_str.to_int()
			
			z_level_containers[z_level] = child
			z_level_tilemaps[z_level] = _get_tilemaps_from_container(child)
			
			if debug_enabled:
				print("Discovered Z-Level ", z_level, " with ", z_level_tilemaps[z_level].size(), " tilemaps")

func _get_tilemaps_from_container(container: Node) -> Dictionary:
	var tilemaps = {}
	
	for child in container.get_children():
		if child is TileMap:
			match child.name:
				"FloorTileMap":
					tilemaps["floor"] = child
				"WallTileMap":
					tilemaps["wall"] = child
				"ObjectsTileMap":
					tilemaps["objects"] = child
	
	return tilemaps

func _create_missing_z_levels():
	for z in range(max_z_levels):
		if not z in z_level_containers:
			_create_z_level_container(z)
			if debug_enabled:
				print("Created missing Z-Level container: ", z)

func _create_z_level_container(z_level: int) -> Node2D:
	var container = Node2D.new()
	container.name = "Z_Level_" + str(z_level)
	add_child(container)
	
	var tilemaps = _create_tilemaps_for_container(container)
	
	z_level_containers[z_level] = container
	z_level_tilemaps[z_level] = tilemaps
	
	return container

func _create_tilemaps_for_container(container: Node2D) -> Dictionary:
	var tilemaps = {}
	
	var floor_tilemap = _create_tilemap("FloorTileMap")
	var wall_tilemap = _create_tilemap("WallTileMap")
	var objects_tilemap = _create_tilemap("ObjectsTileMap")
	
	container.add_child(floor_tilemap)
	container.add_child(wall_tilemap)
	container.add_child(objects_tilemap)
	
	tilemaps["floor"] = floor_tilemap
	tilemaps["wall"] = wall_tilemap
	tilemaps["objects"] = objects_tilemap
	
	return tilemaps

func _create_tilemap(tilemap_name: String) -> TileMap:
	var tilemap = TileMap.new()
	tilemap.name = tilemap_name
	tilemap.cell_quadrant_size = 32
	
	# Create a basic tileset if none exists
	if not tilemap.tile_set:
		var tileset = TileSet.new()
		tileset.tile_size = Vector2i(32, 32)
		
		var source = TileSetAtlasSource.new()
		source.texture = _create_default_texture()
		source.texture_region_size = Vector2i(32, 32)
		tileset.add_source(source)
		
		tilemap.tile_set = tileset
	
	return tilemap

func _create_default_texture() -> ImageTexture:
	var image = Image.create(32, 32, false, Image.FORMAT_RGB8)
	image.fill(Color.WHITE)
	var texture = ImageTexture.new()
	texture.create_from_image(image)
	return texture

func _validate_z_level_structure():
	for z_level in z_level_containers.keys():
		var container = z_level_containers[z_level]
		var tilemaps = z_level_tilemaps[z_level]
		
		if tilemaps.is_empty():
			print("Warning: Z-Level ", z_level, " has no tilemaps")
		
		if not "floor" in tilemaps:
			print("Warning: Z-Level ", z_level, " missing FloorTileMap")
		
		if not "wall" in tilemaps:
			print("Warning: Z-Level ", z_level, " missing WallTileMap")

func _connect_world_signals():
	if not world:
		print("TileMapVisualizer: No world reference found")
		return
	
	if world.has_signal("tile_changed"):
		world.connect("tile_changed", Callable(self, "_on_tile_changed"))
		print("TileMapVisualizer: Connected to tile_changed signal")
	
	if world.has_signal("object_interacted"):
		world.connect("object_interacted", Callable(self, "_on_object_interacted"))
		print("TileMapVisualizer: Connected to object_interacted signal")

func _register_collision_methods():
	if not world:
		return
	
	if world.has_method("set_tilemap_visualizer"):
		world.set_tilemap_visualizer(self)
	elif "tilemap_visualizer" in world:
		world.tilemap_visualizer = self
	
	print("TileMapVisualizer: Registered with World for Z-level collision detection")

# Z-level specific collision detection
func is_wall_at_z_level(tile_coords: Vector2i, z_level: int) -> bool:
	if not z_level in z_level_tilemaps:
		return false
	
	var tilemaps = z_level_tilemaps[z_level]
	if "wall" in tilemaps:
		var wall_tilemap = tilemaps["wall"]
		if wall_tilemap and wall_tilemap.get_cell_source_id(0, tile_coords) != -1:
			return true
	
	if world and world.has_method("get_tile_data"):
		var tile_data = world.get_tile_data(tile_coords, z_level)
		if tile_data is Dictionary and world.TileLayer.WALL in tile_data:
			return tile_data[world.TileLayer.WALL] != null
	
	return false

func is_valid_tile_at_z_level(tile_coords: Vector2i, z_level: int) -> bool:
	if not z_level in z_level_tilemaps:
		return false
	
	var tilemaps = z_level_tilemaps[z_level]
	
	if "floor" in tilemaps:
		var floor_tilemap = tilemaps["floor"]
		if floor_tilemap and floor_tilemap.get_cell_source_id(0, tile_coords) != -1:
			return true
	
	if "wall" in tilemaps:
		var wall_tilemap = tilemaps["wall"]
		if wall_tilemap and wall_tilemap.get_cell_source_id(0, tile_coords) != -1:
			return true
	
	if world and world.has_method("get_tile_data"):
		var tile_data = world.get_tile_data(tile_coords, z_level)
		if tile_data != null:
			return true
	
	return false

# Main processing loop
func _process(delta):
	_update_ambient_emitters(delta)
	
	# Debug visualization refresh
	if debug_enabled and Input.is_action_just_pressed("ui_home"):
		print("TileMapVisualizer: Force re-visualizing all levels")
		visualize_all_z_levels()

# Visualization functions
func visualize_all_z_levels():
	for z_level in z_level_containers.keys():
		visualize_z_level(z_level)

func visualize_z_level(z_level: int):
	if not z_level in z_level_containers:
		print("TileMapVisualizer: Z-Level ", z_level, " not found")
		return
	
	if not world:
		print("TileMapVisualizer: Cannot visualize - world reference missing")
		return
	
	if preserve_existing_tiles:
		print("TileMapVisualizer: Preserving existing tiles for Z-Level ", z_level)
		return
	
	print("TileMapVisualizer: Visualizing z-level ", z_level)
	
	_clear_z_level_tilemaps(z_level)
	
	var tiles_visualized = 0
	var world_data = _get_world_data_for_level(z_level)
	
	if world_data:
		for coords in world_data.keys():
			_update_tile_visual(coords, z_level)
			tiles_visualized += 1
	
	print("TileMapVisualizer: Visualized ", tiles_visualized, " tiles on Z-Level ", z_level)

func _update_tile_visual(coords: Vector2, z_level: int):
	if not z_level in z_level_tilemaps:
		return
	
	var tile_data = world.get_tile_data(coords, z_level)
	if not tile_data:
		return
	
	var coords_i = Vector2i(coords.x, coords.y)
	var tilemaps = z_level_tilemaps[z_level]
	
	# Place floor tile
	_place_floor_tile(coords_i, tile_data, tilemaps)
	
	# Place wall tile if needed
	_place_wall_tile(coords_i, tile_data, tilemaps)
	
	# Update atmospheric effects
	_update_atmosphere_visual(coords, z_level, tile_data, tilemaps)

func _place_floor_tile(coords_i: Vector2i, tile_data: Dictionary, tilemaps: Dictionary):
	if not "floor" in tilemaps:
		return
	
	var floor_tilemap = tilemaps["floor"]
	
	var floor_type = "floor"
	if world.TileLayer.FLOOR in tile_data and "type" in tile_data[world.TileLayer.FLOOR]:
		floor_type = tile_data[world.TileLayer.FLOOR].type
	
	# Place a basic floor tile
	floor_tilemap.set_cell(FLOOR_LAYER, coords_i, 0, Vector2i(0, 0))

func _place_wall_tile(coords_i: Vector2i, tile_data: Dictionary, tilemaps: Dictionary):
	if not "wall" in tilemaps:
		return
	
	var wall_tilemap = tilemaps["wall"]
	
	if not (world.TileLayer.WALL in tile_data) or not tile_data[world.TileLayer.WALL]:
		return
	
	# Place a basic wall tile
	wall_tilemap.set_cell(WALL_LAYER, coords_i, 0, Vector2i(0, 0))

func _update_atmosphere_visual(coords: Vector2, z_level: int, tile_data: Dictionary, tilemaps: Dictionary):
	if not "objects" in tilemaps:
		return
	
	var objects_tilemap = tilemaps["objects"]
	
	if not (world.TileLayer.ATMOSPHERE in tile_data):
		return
	
	var atmo = tile_data[world.TileLayer.ATMOSPHERE]
	var coords_i = Vector2i(coords.x, coords.y)
	
	# Show ice texture for very cold tiles
	if atmo.temperature < 260:
		objects_tilemap.set_cell(OBJECTS_LAYER, coords_i, 0, Vector2i(0, 1))
	# Show fire texture for very hot tiles or if on_fire flag is set
	elif atmo.temperature > 360 or ("on_fire" in tile_data and tile_data.on_fire):
		objects_tilemap.set_cell(OBJECTS_LAYER, coords_i, 0, Vector2i(1, 1))

func _clear_z_level_tilemaps(z_level: int):
	if not z_level in z_level_tilemaps:
		return
	
	var tilemaps = z_level_tilemaps[z_level]
	
	for tilemap_type in tilemaps:
		var tilemap = tilemaps[tilemap_type]
		if tilemap:
			tilemap.clear()

# Z-Level specific tilemap access
func get_tilemap(z_level: int, tilemap_type: String) -> TileMap:
	if not z_level in z_level_tilemaps:
		return null
	
	var tilemaps = z_level_tilemaps[z_level]
	return tilemaps.get(tilemap_type, null)

func get_floor_tilemap(z_level: int) -> TileMap:
	return get_tilemap(z_level, "floor")

func get_wall_tilemap(z_level: int) -> TileMap:
	return get_tilemap(z_level, "wall")

func get_objects_tilemap(z_level: int) -> TileMap:
	return get_tilemap(z_level, "objects")

func get_z_level_container(z_level: int) -> Node2D:
	return z_level_containers.get(z_level, null)

func has_z_level(z_level: int) -> bool:
	return z_level in z_level_containers

func get_available_z_levels() -> Array:
	return z_level_containers.keys()

func is_tile_blocked_by_tilemap(tile_coords: Vector2i, z_level: int) -> bool:
	return is_wall_at_z_level(tile_coords, z_level)

# Signal handlers
func _on_tile_changed(tile_coords, z_level, old_data = null, new_data = null):
	if not new_data and world:
		new_data = world.get_tile_data(tile_coords, z_level)
	
	if not old_data or not new_data:
		return
	
	# Update visual for the specific Z-level
	if z_level in z_level_containers:
		_update_tile_visual(tile_coords, z_level)
	
	# Handle construction/destruction sounds
	_handle_construction_sounds(tile_coords, old_data, new_data)
	
	# Update ambient emitters
	_check_ambient_emitter_for_tile(tile_coords, z_level, new_data)

func _on_object_interacted(tile_coords, z_level, object_type, action):
	if not world or not enable_construction_sounds:
		return
	
	if object_type in interaction_sounds:
		var world_pos = world.tile_to_world(tile_coords)
		if sensory_system:
			sensory_system.emit_sound(world_pos, z_level, interaction_sounds[object_type], 0.5)

# Construction sound handling
func _handle_construction_sounds(tile_coords, old_data: Dictionary, new_data: Dictionary):
	if not enable_construction_sounds or not sensory_system:
		return
	
	var world_pos = world.tile_to_world(tile_coords)
	var z_level = _get_current_z_level()
	
	# Wall construction/destruction
	var had_wall = world.TileLayer.WALL in old_data and old_data[world.TileLayer.WALL] != null
	var has_wall = world.TileLayer.WALL in new_data and new_data[world.TileLayer.WALL] != null
	
	if had_wall != has_wall:
		var volume = construction_volume if has_wall else destruction_volume
		sensory_system.emit_sound(world_pos, z_level, "thud", volume)
	
	# Floor changes
	elif world.TileLayer.FLOOR in old_data and world.TileLayer.FLOOR in new_data:
		var old_floor = old_data[world.TileLayer.FLOOR]
		var new_floor = new_data[world.TileLayer.FLOOR]
		
		if old_floor.type != new_floor.type:
			sensory_system.emit_sound(world_pos, z_level, "thud", 0.4)

# Ambient sound system
func _setup_ambient_emitters():
	if not world:
		print("TileMapVisualizer: Cannot setup ambient emitters - world reference missing")
		return
	
	ambient_emitters.clear()
	print("TileMapVisualizer: Setting up ambient emitters")
	
	var emitter_count = 0
	
	# Scan each z-level for potential sound emitters
	for z in z_level_containers.keys():
		emitter_count += _setup_ambient_emitters_for_z_level(z)
	
	print("TileMapVisualizer: Set up ", emitter_count, " ambient emitters")

func _setup_ambient_emitters_for_z_level(z_level: int) -> int:
	var emitter_count = 0
	var world_data = _get_world_data_for_level(z_level)
	
	if world_data:
		for tile_coords in world_data.keys():
			var tile_data = world.get_tile_data(tile_coords, z_level)
			if _check_ambient_emitter_for_tile(tile_coords, z_level, tile_data):
				emitter_count += 1
	
	return emitter_count

func _check_ambient_emitter_for_tile(tile_coords, z_level, tile_data) -> bool:
	if not world or not tile_data:
		return false
	
	var emitter_key = str(tile_coords.x) + "_" + str(tile_coords.y) + "_" + str(z_level)
	var emitter_added = false
	
	# Check for active machinery
	if "machinery" in tile_data and "active" in tile_data.machinery and tile_data.machinery.active:
		if not emitter_key in ambient_emitters:
			ambient_emitters[emitter_key] = _create_ambient_emitter("machinery", tile_coords, z_level, 0.6, randf_range(4.0, 8.0))
			emitter_added = true
	
	# Remove emitter if conditions no longer met
	elif emitter_key in ambient_emitters:
		ambient_emitters.erase(emitter_key)
	
	return emitter_added

func _create_ambient_emitter(emitter_type: String, tile_coords, z_level, volume: float, interval: float) -> Dictionary:
	return {
		"type": emitter_type,
		"position": world.tile_to_world(tile_coords),
		"z_level": z_level,
		"volume": volume,
		"interval": interval,
		"timer": 0.0
	}

func _update_ambient_emitters(delta):
	if not sensory_system:
		return
	
	ambient_update_timer += delta
	
	if ambient_update_timer < ambient_update_interval:
		return
	
	ambient_update_timer = 0.0
	var current_z = _get_current_z_level()
	
	for key in ambient_emitters.keys():
		var emitter = ambient_emitters[key]
		
		# Only process emitters on the current Z-level
		if emitter.z_level != current_z:
			continue
		
		emitter.timer += delta
		
		if emitter.timer >= emitter.interval:
			# Reset timer with randomness
			emitter.timer = 0.0
			emitter.interval = randf_range(emitter.interval * 0.8, emitter.interval * 1.2)
			
			sensory_system.emit_sound(
				emitter.position,
				emitter.z_level,
				emitter.type,
				emitter.volume * randf_range(0.8, 1.2)
			)

# Utility functions
func _get_current_z_level():
	var z_manager = world.get_node_or_null("ZLevelManager")
	if z_manager:
		var players = get_tree().get_nodes_in_group("player_controller")
		if players.size() > 0:
			return z_manager.get_entity_z_level(players[0])
	
	if world and "current_z_level" in world:
		return world.current_z_level
	return 0

func _get_world_data_for_level(z_level):
	if not world or not world.world_data:
		return null
	
	# Handle both integer and float z-level formats
	if z_level in world.world_data:
		return world.world_data[z_level]
	elif float(z_level) in world.world_data:
		return world.world_data[float(z_level)]
	
	return null

# Public interface functions
func refresh_visualization():
	print("TileMapVisualizer: Manual refresh requested")
	visualize_all_z_levels()

func refresh_z_level(z_level: int):
	print("TileMapVisualizer: Refreshing Z-Level ", z_level)
	visualize_z_level(z_level)

func toggle_debug_mode():
	debug_enabled = not debug_enabled
	print("TileMapVisualizer: Debug mode ", "enabled" if debug_enabled else "disabled")

func get_z_level_info() -> Dictionary:
	var info = {}
	for z_level in z_level_containers.keys():
		var container = z_level_containers[z_level]
		var tilemaps = z_level_tilemaps[z_level]
		
		info[z_level] = {
			"container_name": container.name,
			"visible": container.visible,
			"tilemap_count": tilemaps.size(),
			"tilemaps": tilemaps.keys()
		}
	
	return info

# Additional helper methods for World integration
func get_floor_at_z_level(tile_coords: Vector2i, z_level: int) -> bool:
	if not z_level in z_level_tilemaps:
		return false
	
	var tilemaps = z_level_tilemaps[z_level]
	if "floor" in tilemaps:
		var floor_tilemap = tilemaps["floor"]
		return floor_tilemap and floor_tilemap.get_cell_source_id(0, tile_coords) != -1
	
	return false

func get_objects_at_z_level(tile_coords: Vector2i, z_level: int) -> bool:
	if not z_level in z_level_tilemaps:
		return false
	
	var tilemaps = z_level_tilemaps[z_level]
	if "objects" in tilemaps:
		var objects_tilemap = tilemaps["objects"]
		return objects_tilemap and objects_tilemap.get_cell_source_id(0, tile_coords) != -1
	
	return false

# Support for space detection
func is_space_tile(tile_coords: Vector2i, z_level: int) -> bool:
	if not z_level in z_level_tilemaps:
		return true
	
	var tilemaps = z_level_tilemaps[z_level]
	
	if "floor" in tilemaps:
		var floor_tilemap = tilemaps["floor"]
		if floor_tilemap and floor_tilemap.get_cell_source_id(0, tile_coords) != -1:
			return false
	
	if "wall" in tilemaps:
		var wall_tilemap = tilemaps["wall"]
		if wall_tilemap and wall_tilemap.get_cell_source_id(0, tile_coords) != -1:
			return false
	
	if "objects" in tilemaps:
		var objects_tilemap = tilemaps["objects"]
		if objects_tilemap and objects_tilemap.get_cell_source_id(0, tile_coords) != -1:
			return false
	
	if world and world.has_method("get_tile_data"):
		var tile_data = world.get_tile_data(tile_coords, z_level)
		if tile_data and "is_space" in tile_data:
			return tile_data.is_space
	
	return true
