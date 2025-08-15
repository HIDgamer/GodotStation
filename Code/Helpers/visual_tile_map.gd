extends Node2D
class_name TileMapVisualizer

# Tilemap references
@onready var floor_tilemap: TileMap = $FloorTileMap
@onready var wall_tilemap: TileMap = $WallTileMap
@onready var objects_tilemap: TileMap = $ObjectsTileMap

# System references
@onready var world: Node2D = $".."
@onready var sensory_system = $"../SensorySystem"
@onready var audio_manager = $"../AudioManager"
@onready var lighting_system: Node = $"../LightingSystem"

# Configuration
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

# Layer constants
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
	await get_tree().create_timer(update_delay).timeout
	_initialize_system()

# Initialization functions
func _initialize_system():
	_validate_tilemaps()
	_connect_world_signals()
	_setup_ambient_emitters()
	
	if auto_visualize_on_ready and not preserve_existing_tiles:
		await get_tree().create_timer(0.5).timeout
		visualize_current_level()
	
	print("TileMapVisualizer: Initialization complete")

func _validate_tilemaps() -> bool:
	var all_valid = true
	
	if not floor_tilemap:
		print("TileMapVisualizer: FloorTileMap not found, creating...")
		floor_tilemap = _create_tilemap("FloorTileMap")
		all_valid = false
	
	if not wall_tilemap:
		print("TileMapVisualizer: WallTileMap not found, creating...")
		wall_tilemap = _create_tilemap("WallTileMap")
		all_valid = false
	
	if not objects_tilemap:
		print("TileMapVisualizer: ObjectsTileMap not found, creating...")
		objects_tilemap = _create_tilemap("ObjectsTileMap")
		all_valid = false
	
	return all_valid

func _create_tilemap(tilemap_name: String) -> TileMap:
	var tilemap = TileMap.new()
	tilemap.name = tilemap_name
	tilemap.cell_quadrant_size = 32
	
	var tileset = TileSet.new()
	tileset.tile_size = Vector2i(32, 32)
	
	var source = TileSetAtlasSource.new()
	tileset.add_source(source)
	
	tilemap.tile_set = tileset
	add_child(tilemap)
	
	return tilemap

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

# Main processing loop
func _process(delta):
	_update_ambient_emitters(delta)
	
	# Debug visualization refresh
	if debug_enabled and Input.is_action_just_pressed("ui_home"):
		print("TileMapVisualizer: Force re-visualizing level")
		visualize_current_level()

# Visualization functions
func visualize_current_level():
	if not world:
		print("TileMapVisualizer: Cannot visualize - world reference missing")
		return
	
	if preserve_existing_tiles:
		print("TileMapVisualizer: Preserving existing tiles from editor")
		return
	
	var z_level = _get_current_z_level()
	print("TileMapVisualizer: Visualizing z-level ", z_level)
	
	_clear_all_tilemaps()
	
	var tiles_visualized = 0
	var world_data = _get_world_data_for_level(z_level)
	
	if world_data:
		for coords in world_data.keys():
			_update_tile_visual(coords, z_level)
			tiles_visualized += 1
	
	print("TileMapVisualizer: Visualized ", tiles_visualized, " tiles")

func _update_tile_visual(coords: Vector2, z_level):
	if not world or not _validate_tilemaps():
		return
	
	var tile_data = world.get_tile_data(coords, z_level)
	if not tile_data:
		return
	
	var coords_i = Vector2i(coords.x, coords.y)
	
	# Place floor tile
	_place_floor_tile(coords_i, tile_data)
	
	# Place wall tile if needed
	_place_wall_tile(coords_i, tile_data)
	
	# Update atmospheric effects
	_update_atmosphere_visual(coords, z_level, tile_data)

func _place_floor_tile(coords_i: Vector2i, tile_data: Dictionary):
	if not floor_tilemap:
		return
	
	var floor_type = "floor"
	if world.TileLayer.FLOOR in tile_data and "type" in tile_data[world.TileLayer.FLOOR]:
		floor_type = tile_data[world.TileLayer.FLOOR].type
	
	if floor_type in floor_terrain_mapping:
		var terrain_info = floor_terrain_mapping[floor_type]
		_set_terrain(floor_tilemap, FLOOR_LAYER, coords_i, terrain_info.terrain_set, terrain_info.terrain)

func _place_wall_tile(coords_i: Vector2i, tile_data: Dictionary):
	if not wall_tilemap or not (world.TileLayer.WALL in tile_data) or not tile_data[world.TileLayer.WALL]:
		return
	
	var wall_material = "metal"
	if "wall_material" in tile_data:
		wall_material = tile_data.wall_material
	
	if wall_material in wall_terrain_mapping:
		var terrain_info = wall_terrain_mapping[wall_material]
		_set_terrain(wall_tilemap, WALL_LAYER, coords_i, terrain_info.terrain_set, terrain_info.terrain)

func _update_atmosphere_visual(coords: Vector2, z_level: int, tile_data: Dictionary):
	if not objects_tilemap or not (world.TileLayer.ATMOSPHERE in tile_data):
		return
	
	var atmo = tile_data[world.TileLayer.ATMOSPHERE]
	var coords_i = Vector2i(coords.x, coords.y)
	
	# Show ice texture for very cold tiles
	if atmo.temperature < 260:
		_try_set_cell(objects_tilemap, OBJECTS_LAYER, coords_i, 0, object_tile_mapping["ice"])
	# Show fire texture for very hot tiles or if on_fire flag is set
	elif atmo.temperature > 360 or ("on_fire" in tile_data and tile_data.on_fire):
		_try_set_cell(objects_tilemap, OBJECTS_LAYER, coords_i, 0, object_tile_mapping["fire"])

# Tilemap utility functions
func _set_terrain(tilemap: TileMap, layer: int, coords: Vector2i, terrain_set: int, terrain: int) -> bool:
	if not tilemap or not tilemap.tile_set:
		return false
	
	tilemap.set_cells_terrain_connect(layer, [coords], terrain_set, terrain)
	return true

func _try_set_cell(tilemap: TileMap, layer: int, coords: Vector2i, source_id: int, atlas_coords: Vector2i) -> bool:
	if not tilemap:
		return false
	
	var source = tilemap.tile_set.get_source(source_id) if tilemap.tile_set else null
	if not source or not source is TileSetAtlasSource:
		if debug_enabled:
			print("TileMapVisualizer: Invalid tile source: ", source_id)
		return false
	
	if not source.has_tile(atlas_coords):
		if debug_enabled:
			print("TileMapVisualizer: Invalid atlas coords: ", atlas_coords, " for source ", source_id)
		return false
	
	tilemap.set_cell(layer, coords, source_id, atlas_coords)
	return true

func _clear_all_tilemaps():
	if floor_tilemap:
		floor_tilemap.clear()
	if wall_tilemap:
		wall_tilemap.clear()
	if objects_tilemap:
		objects_tilemap.clear()

# Signal handlers
func _on_tile_changed(tile_coords, z_level, old_data = null, new_data = null):
	if not new_data and world:
		new_data = world.get_tile_data(tile_coords, z_level)
	
	if not old_data or not new_data:
		return
	
	# Update visual if on current z-level
	if z_level == _get_current_z_level():
		_update_tile_visual(tile_coords, z_level)
	
	# Update lighting system
	if update_lighting_on_changes and lighting_system:
		lighting_system._update_area_lighting(tile_coords, z_level)
	
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
	
	# Wall construction/destruction
	var had_wall = world.TileLayer.WALL in old_data and old_data[world.TileLayer.WALL] != null
	var has_wall = world.TileLayer.WALL in new_data and new_data[world.TileLayer.WALL] != null
	
	if had_wall != has_wall:
		var volume = construction_volume if has_wall else destruction_volume
		sensory_system.emit_sound(world_pos, _get_current_z_level(), "thud", volume)
	
	# Floor changes
	elif world.TileLayer.FLOOR in old_data and world.TileLayer.FLOOR in new_data:
		var old_floor = old_data[world.TileLayer.FLOOR]
		var new_floor = new_data[world.TileLayer.FLOOR]
		
		if old_floor.type != new_floor.type:
			sensory_system.emit_sound(world_pos, _get_current_z_level(), "thud", 0.4)

# Ambient sound system
func _setup_ambient_emitters():
	if not world:
		print("TileMapVisualizer: Cannot setup ambient emitters - world reference missing")
		return
	
	ambient_emitters.clear()
	print("TileMapVisualizer: Setting up ambient emitters")
	
	var emitter_count = 0
	
	# Scan each z-level for potential sound emitters
	for z in range(world.z_levels):
		var float_z = _normalize_z_level(z)
		var world_data = _get_world_data_for_level(float_z)
		
		if world_data:
			for tile_coords in world_data.keys():
				var tile_data = world.get_tile_data(tile_coords, float_z)
				if _check_ambient_emitter_for_tile(tile_coords, float_z, tile_data):
					emitter_count += 1
	
	print("TileMapVisualizer: Set up ", emitter_count, " ambient emitters")

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
	
	# Check for powered devices
	elif "device" in tile_data and "powered" in tile_data.device and tile_data.device.powered:
		if not emitter_key in ambient_emitters:
			ambient_emitters[emitter_key] = _create_ambient_emitter("machinery", tile_coords, z_level, 0.4, randf_range(5.0, 12.0))
			emitter_added = true
	
	# Check for flowing pipes
	elif world.TileLayer.PIPE in tile_data and tile_data[world.TileLayer.PIPE].content_type != "none":
		if not emitter_key in ambient_emitters:
			ambient_emitters[emitter_key] = _create_ambient_emitter("machinery", tile_coords, z_level, 0.3, randf_range(6.0, 15.0))
			emitter_added = true
	
	# Check for water
	elif world.TileLayer.FLOOR in tile_data and tile_data[world.TileLayer.FLOOR].type == "water":
		if not emitter_key in ambient_emitters:
			ambient_emitters[emitter_key] = _create_ambient_emitter("water", tile_coords, z_level, 0.2, randf_range(10.0, 20.0))
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
	
	for key in ambient_emitters.keys():
		var emitter = ambient_emitters[key]
		
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

func _normalize_z_level(z):
	if typeof(z) == TYPE_FLOAT:
		return z
	return float(z)

# Footstep system
func get_footstep_type_for_tile(tile_coords, z_level) -> String:
	if not world:
		return "default"
	
	var tile_data = world.get_tile_data(tile_coords, z_level)
	if not tile_data or not world.TileLayer.FLOOR in tile_data:
		return "default"
	
	var floor_data = tile_data[world.TileLayer.FLOOR]
	var floor_type = floor_data.type if "type" in floor_data else "floor"
	
	if floor_type in floor_terrain_mapping:
		return floor_type
	
	return "default"

func play_sound_at_tile(tile_coords, z_level, sound_type, volume = 1.0):
	if not world or not sensory_system:
		return
	
	var world_pos = world.tile_to_world(tile_coords)
	sensory_system.emit_sound(world_pos, z_level, sound_type, volume)

# Visibility system (for FOV integration)
func set_tile_visibility(tile_coords: Vector2i, z_level: int, is_visible: bool):
	if z_level != _get_current_z_level():
		return
	
	var modulation = Color(1, 1, 1, 1) if is_visible else Color(0.3, 0.3, 0.3, 1)
	_apply_modulation_to_tile(tile_coords, modulation)

func _apply_modulation_to_tile(tile_coords: Vector2i, modulation: Color):
	# Apply color modulation to all tilemaps at the given coordinates
	if floor_tilemap:
		var tile_data = floor_tilemap.get_cell_tile_data(0, tile_coords)
		if tile_data:
			var cell_alternative = floor_tilemap.get_cell_alternative_tile(0, tile_coords)
			floor_tilemap.set_cell(0, tile_coords, 
								 floor_tilemap.get_cell_source_id(0, tile_coords),
								 floor_tilemap.get_cell_atlas_coords(0, tile_coords),
								 cell_alternative)

# Public interface functions
func refresh_visualization():
	print("TileMapVisualizer: Manual refresh requested")
	visualize_current_level()

func clear_ambient_emitters():
	ambient_emitters.clear()

func get_ambient_emitter_count() -> int:
	return ambient_emitters.size()

func toggle_debug_mode():
	debug_enabled = not debug_enabled
	print("TileMapVisualizer: Debug mode ", "enabled" if debug_enabled else "disabled")
