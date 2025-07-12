# TileMapVisualizer.gd
extends Node2D

@onready var floor_tilemap: TileMap = $FloorTileMap
@onready var wall_tilemap: TileMap = $WallTileMap
@onready var objects_tilemap: TileMap = $ObjectsTileMap
@onready var world: Node2D = $".."
@onready var sensory_system = $"../SensorySystem"
@onready var audio_manager = $"../AudioManager"

# Layer constants to match your TileMap
const FLOOR_LAYER = 0
const WALL_LAYER = 1
const OBJECTS_LAYER = 2

# Tile types to atlas coordinates mapping
var floor_terrain_mapping = {
	"floor": {
		"terrain_set": 0,  # ID of the terrain set in the TileSet resource
		"terrain": 2       # ID of the specific terrain within that set
	},
	"metal": {
		"terrain_set": 0,
		"terrain": 0
	},
	"carpet": {
		"terrain_set": 0,  # Different terrain set for carpet
		"terrain": 1
	},
	"wood": {
		"terrain_set": 0,
		"terrain": 3
	},
	# Add more floor types as needed
}

var wall_terrain_mapping = {
	"metal": {
		"terrain_set": 0,
		"terrain": 1
	},
	"insulated": {
		"terrain_set": 0, 
		"terrain": 0
	},
	"glass": {
		"terrain_set": 0,  # Different set for transparent walls
		"terrain": 0
	},
	# Add more wall types
}

# For special cases that aren't terrain-based (like doors)
var object_tile_mapping = {
	"door_closed": Vector2i(0, 1),
	"door_open": Vector2i(1, 1),
	"ice": Vector2i(0, 2),
	"fire": Vector2i(1, 2)
}

# Door sounds
var door_open_volume = 0.7
var door_close_volume = 0.8

# Interactive object sounds
var interaction_sounds = {
	"button": "button",
	"lever": "lever",
	"console": "console",
	"chest": "chest"
}

# Environmental ambient sounds
var ambient_emitters = {}

# Debug flag
var debug_enabled = true
var preserve_existing_tiles = true  # Keep existing tiles placed in the editor

func _ready():
	# Add a small delay to ensure the world is properly initialized
	await get_tree().create_timer(0.2).timeout
	
	# Verify TileMap nodes exist
	check_tilemaps()
	
	print("TileMapVisualizer: Initializing...")
	
	# Connect signals
	if world and world.has_signal("tile_changed"):
		world.connect("tile_changed", Callable(self, "_on_tile_changed"))
		print("TileMapVisualizer: Connected to tile_changed signal")
	else:
		print("TileMapVisualizer: WARNING - Could not connect to tile_changed signal")
	
	if world and world.has_signal("door_toggled"):
		world.connect("door_toggled", Callable(self, "_on_door_toggled"))
		print("TileMapVisualizer: Connected to door_toggled signal")
	
	if world and world.has_signal("object_interacted"):
		world.connect("object_interacted", Callable(self, "_on_object_interacted"))
		print("TileMapVisualizer: Connected to object_interacted signal")
	
	# Initialize ambient sounds
	setup_ambient_emitters()
	
	# With preserve_existing_tiles = true, we skip initial visualization
	if !preserve_existing_tiles:
		await get_tree().create_timer(0.5).timeout
		visualize_current_level()
	
	print("TileMapVisualizer: Initialization complete")

func check_tilemaps():
	var tilemaps_exist = true
	
	if !floor_tilemap:
		print("TileMapVisualizer: ERROR - FloorTileMap not found!")
		tilemaps_exist = false
		
		# Try to create it if needed
		floor_tilemap = create_tilemap("FloorTileMap")
	
	if !wall_tilemap:
		print("TileMapVisualizer: ERROR - WallTileMap not found!")
		tilemaps_exist = false
		
		# Try to create it if needed
		wall_tilemap = create_tilemap("WallTileMap")
	
	if !objects_tilemap:
		print("TileMapVisualizer: ERROR - ObjectsTileMap not found!")
		tilemaps_exist = false
		
		# Try to create it if needed
		objects_tilemap = create_tilemap("ObjectsTileMap")
	
	return tilemaps_exist

func create_tilemap(name: String) -> TileMap:
	print("TileMapVisualizer: Attempting to create " + name)
	
	var tilemap = TileMap.new()
	tilemap.name = name
	
	# Basic setup - you'll need to properly configure the tileset
	tilemap.cell_quadrant_size = 32
	
	# Create a basic tileset - Note: This is a very basic setup and may need further configuration
	var tileset = TileSet.new()
	tileset.tile_size = Vector2i(32, 32)
	
	# You'll need to add sources and tiles based on your specific needs
	# This is just a placeholder for emergency creation
	var source = TileSetAtlasSource.new()
	# Setup atlas source properties here
	tileset.add_source(source)
	
	tilemap.tile_set = tileset
	
	add_child(tilemap)
	return tilemap

func _process(delta):
	# Update ambient sound emitters
	update_ambient_emitters(delta)
	
	# Debug key to force re-visualization
	if debug_enabled and Input.is_action_just_pressed("ui_home"):  # Home key
		print("TileMapVisualizer: Force re-visualizing level")
		visualize_current_level()

func visualize_current_level():
	if !world:
		print("TileMapVisualizer: Cannot visualize - world reference missing")
		return
		
	if preserve_existing_tiles:
		print("TileMapVisualizer: Preserving existing tiles from editor")
		# Skip clearing the tilemaps to preserve editor-placed tiles
		return
		
	# The rest of your original function
	# This will only run if preserve_existing_tiles is false
	var z_level = int(world.current_z_level)  # Convert to integer
	
	print("TileMapVisualizer: Visualizing z-level " + str(z_level))
	
	# Clear existing tiles
	if floor_tilemap: floor_tilemap.clear()
	if wall_tilemap: wall_tilemap.clear() 
	if objects_tilemap: objects_tilemap.clear()
	
	# Count tiles visualized
	var tiles_visualized = 0
	
	# Try both formats for backward compatibility during transition
	if z_level in world.world_data:
		for coords in world.world_data[z_level].keys():
			update_tile_visual(coords, z_level)
			tiles_visualized += 1
	elif float(z_level) in world.world_data:
		for coords in world.world_data[float(z_level)].keys():
			update_tile_visual(coords, float(z_level))
			tiles_visualized += 1
	
	print("TileMapVisualizer: Visualized " + str(tiles_visualized) + " tiles")

func update_tile_visual(coords: Vector2, z_level: int):
	if !world or !check_tilemaps():
		return
	
	var tile_data = world.get_tile_data(coords, z_level)
	if not tile_data:
		return
	
	var coords_i = Vector2i(coords.x, coords.y)
	
	# Place floor tile for all tiles
	if floor_tilemap:
		var floor_type = "floor"
		if world.TileLayer.FLOOR in tile_data and "type" in tile_data[world.TileLayer.FLOOR]:
			floor_type = tile_data[world.TileLayer.FLOOR].type
			
		if floor_type in floor_terrain_mapping:
			var terrain_info = floor_terrain_mapping[floor_type]
			set_terrain(floor_tilemap, FLOOR_LAYER, coords_i, terrain_info.terrain_set, terrain_info.terrain)
	
	# Place wall tile only if it's a wall
	if world.TileLayer.WALL in tile_data and tile_data[world.TileLayer.WALL] and wall_tilemap:
		# If it's a wall, show it
		var wall_material = "metal"  # Default wall material
		if "wall_material" in tile_data:
			wall_material = tile_data.wall_material
			
		if wall_material in wall_terrain_mapping:
			var terrain_info = wall_terrain_mapping[wall_material]
			set_terrain(wall_tilemap, WALL_LAYER, coords_i, terrain_info.terrain_set, terrain_info.terrain)

func set_terrain(tilemap: TileMap, layer: int, coords: Vector2i, terrain_set: int, terrain: int):
	if !tilemap or !tilemap.tile_set:
		return false
	
	# Set the terrain for the specified cell
	tilemap.set_cells_terrain_connect(layer, [coords], terrain_set, terrain)
	return true

# Safely try to set a cell in a tilemap
func try_set_cell(tilemap: TileMap, layer: int, coords: Vector2i, source_id: int, atlas_coords: Vector2i):
	if !tilemap:
		return false
		
	# Check if atlas coords are valid for this tilemap
	var source = tilemap.tile_set.get_source(source_id) if tilemap.tile_set else null
	if !source or !source is TileSetAtlasSource:
		if debug_enabled:
			print("TileMapVisualizer: Invalid tile source: " + str(source_id))
		return false
	
	# Check if the atlas coordinates are valid
	if !source.has_tile(atlas_coords):
		if debug_enabled:
			print("TileMapVisualizer: Invalid atlas coords: " + str(atlas_coords) + " for source " + str(source_id))
		return false
	
	# Set the cell
	tilemap.set_cell(layer, coords, source_id, atlas_coords)
	return true

func update_atmosphere_visual(coords: Vector2, z_level: int, tile_data: Dictionary):
	if !objects_tilemap:
		return
		
	# Optional: Add visual effects for extreme atmospheres
	if world.TileLayer.ATMOSPHERE in tile_data:
		var atmo = tile_data[world.TileLayer.ATMOSPHERE]
		var coords_i = Vector2i(coords.x, coords.y)
		
		# Example: Show ice texture for very cold tiles
		if atmo.temperature < 260:
			try_set_cell(objects_tilemap, OBJECTS_LAYER, coords_i, 0, object_tile_mapping["ice"])
		
		# Example: Show fire texture for very hot tiles or if on_fire flag is set
		elif atmo.temperature > 360 or ("on_fire" in tile_data and tile_data.on_fire):
			try_set_cell(objects_tilemap, OBJECTS_LAYER, coords_i, 0, object_tile_mapping["fire"])

func _on_tile_changed(tile_coords, z_level, old_data = null, new_data = null):
	# Handle sound effects for tile changes
	if not new_data:
		if !world:
			return
		new_data = world.get_tile_data(tile_coords, z_level)
	
	if not old_data or not new_data:
		return
	
	# Update visual if on current z-level
	if z_level == world.current_z_level:
		update_tile_visual(tile_coords, z_level)
	
	# Check for major changes that would produce sounds
	
	# Walls being built or destroyed
	if ((world.TileLayer.WALL in old_data) != (world.TileLayer.WALL in new_data)) or \
	   (world.TileLayer.WALL in old_data and world.TileLayer.WALL in new_data and \
	   old_data[world.TileLayer.WALL] != new_data[world.TileLayer.WALL]):
		
		var world_pos = world.tile_to_world(tile_coords)
		if world.TileLayer.WALL in new_data and new_data[world.TileLayer.WALL] != null:
			# Wall built
			if sensory_system:
				sensory_system.emit_sound(world_pos, z_level, "thud", 0.7)
		else:
			# Wall destroyed
			if sensory_system:
				sensory_system.emit_sound(world_pos, z_level, "thud", 0.9)
	
	# Floor changes
	if world.TileLayer.FLOOR in old_data and world.TileLayer.FLOOR in new_data and \
	   old_data[world.TileLayer.FLOOR].type != new_data[world.TileLayer.FLOOR].type:
		var world_pos = world.tile_to_world(tile_coords)
		if sensory_system:
			sensory_system.emit_sound(world_pos, z_level, "thud", 0.4)
	
	# Environmental changes that might affect ambient sounds
	check_ambient_emitter_for_tile(tile_coords, z_level, new_data)

func _on_door_toggled(tile_coords, z_level, is_open):
	# Play door open/close sound
	if !world:
		return
		
	var world_pos = world.tile_to_world(tile_coords)
	
	if sensory_system:
		var volume = door_open_volume if is_open else door_close_volume
		sensory_system.emit_sound(world_pos, z_level, "door", volume)
	
	# Direct audio if available
	if audio_manager:
		audio_manager.play_door_sound(is_open, world_pos, door_open_volume if is_open else door_close_volume)
	
	# Update the door's visual
	if z_level == world.current_z_level:
		var tile_data = world.get_tile_data(tile_coords, z_level)
		if tile_data:
			update_tile_visual(tile_coords, z_level)

func _on_object_interacted(tile_coords, z_level, object_type, action):
	# Play appropriate interaction sound
	if !world or not object_type in interaction_sounds:
		return
	
	var world_pos = world.tile_to_world(tile_coords)
	
	if sensory_system:
		sensory_system.emit_sound(world_pos, z_level, interaction_sounds[object_type], 0.5)

func setup_ambient_emitters():
	# Scan the world for ambient sound emitters
	if !world:
		print("TileMapVisualizer: Cannot setup ambient emitters - world reference missing")
		return
		
	# Clear existing emitters
	ambient_emitters.clear()
	
	print("TileMapVisualizer: Setting up ambient emitters")
	var emitter_count = 0
	
	# Scan each z-level for potential sound emitters
	for z in range(world.z_levels):
		# Try both integer and float formats
		var float_z = normalize_z_level(z)
		
		if float_z in world.world_data:
			for tile_coords in world.world_data[float_z].keys():
				var tile_data = world.get_tile_data(tile_coords, float_z)
				if check_ambient_emitter_for_tile(tile_coords, float_z, tile_data):
					emitter_count += 1
	
	print("TileMapVisualizer: Set up " + str(emitter_count) + " ambient emitters")

func check_ambient_emitter_for_tile(tile_coords, z_level, tile_data):
	# Check if this tile should emit ambient sounds
	if !world or not tile_data:
		return false
		
	var emitter_key = str(tile_coords.x) + "_" + str(tile_coords.y) + "_" + str(z_level)
	var emitter_added = false
	
	# Check for machinery
	if "machinery" in tile_data and "active" in tile_data.machinery and tile_data.machinery.active:
		# Create or update emitter
		if not emitter_key in ambient_emitters:
			ambient_emitters[emitter_key] = {
				"type": "machinery",
				"position": world.tile_to_world(tile_coords),
				"z_level": z_level,
				"volume": 0.6,
				"interval": randf_range(4.0, 8.0),  # Random interval between sounds
				"timer": 0.0
			}
			emitter_added = true
	
	# Check for electric appliances/devices
	elif "device" in tile_data and "powered" in tile_data.device and tile_data.device.powered:
		if not emitter_key in ambient_emitters:
			ambient_emitters[emitter_key] = {
				"type": "machinery",
				"position": world.tile_to_world(tile_coords),
				"z_level": z_level,
				"volume": 0.4,
				"interval": randf_range(5.0, 12.0),
				"timer": 0.0
			}
			emitter_added = true
	
	# Check for vents/pipes with flowing gases
	elif world.TileLayer.PIPE in tile_data and tile_data[world.TileLayer.PIPE].content_type != "none":
		if not emitter_key in ambient_emitters:
			ambient_emitters[emitter_key] = {
				"type": "machinery",
				"position": world.tile_to_world(tile_coords),
				"z_level": z_level,
				"volume": 0.3,
				"interval": randf_range(6.0, 15.0),
				"timer": 0.0
			}
			emitter_added = true
	
	# Check for water
	elif world.TileLayer.FLOOR in tile_data and tile_data[world.TileLayer.FLOOR].type == "water":
		if not emitter_key in ambient_emitters:
			ambient_emitters[emitter_key] = {
				"type": "water",
				"position": world.tile_to_world(tile_coords),
				"z_level": z_level,
				"volume": 0.2,
				"interval": randf_range(10.0, 20.0),
				"timer": 0.0
			}
			emitter_added = true
	
	# If none of the above conditions are met but we have an emitter stored, remove it
	elif emitter_key in ambient_emitters:
		ambient_emitters.erase(emitter_key)
	
	return emitter_added

func update_ambient_emitters(delta):
	# Process ambient sound emitters
	if !sensory_system:
		return
		
	for key in ambient_emitters.keys():
		var emitter = ambient_emitters[key]
		
		# Update timer
		emitter.timer += delta
		
		# Check if it's time to emit a sound
		if emitter.timer >= emitter.interval:
			# Reset timer with some randomness
			emitter.timer = 0.0
			emitter.interval = randf_range(emitter.interval * 0.8, emitter.interval * 1.2)
			
			# Emit the sound
			sensory_system.emit_sound(
				emitter.position,
				emitter.z_level,
				emitter.type,
				emitter.volume * randf_range(0.8, 1.2)  # Add slight volume variation
			)

# Handle player footsteps on different tile types
func get_footstep_type_for_tile(tile_coords, z_level):
	if !world:
		return "default"
	
	var tile_data = world.get_tile_data(tile_coords, z_level)
	if not tile_data or not world.TileLayer.FLOOR in tile_data:
		return "default"
	
	var floor_data = tile_data[world.TileLayer.FLOOR]
	var floor_type = floor_data.type if "type" in floor_data else "floor"
	
	# Map floor type to sound type
	if floor_type in floor_terrain_mapping:
		return floor_terrain_mapping[floor_type]
	
	return "default"

# Utility function to play sound at a tile
func play_sound_at_tile(tile_coords, z_level, sound_type, volume = 1.0):
	if !world or !sensory_system:
		return
		
	var world_pos = world.tile_to_world(tile_coords)
	sensory_system.emit_sound(world_pos, z_level, sound_type, volume)

# Public function to force refresh visualization
func refresh_visualization():
	print("TileMapVisualizer: Manual refresh requested")
	visualize_current_level()

func normalize_z_level(z):
	# Convert any z value to the format used in world_data
	if typeof(z) == TYPE_FLOAT:
		return z  # Already float
	return float(z)  # Convert to float

func set_tile_visibility(tile_coords: Vector2i, z_level: int, is_visible: bool):
	"""Set a tile's visibility state when using FOV."""
	
	# If we're not handling the current z-level, skip
	if z_level != world.current_z_level:
		return
	
	# Get modulation based on visibility
	var modulation = Color(1, 1, 1, 1) if is_visible else Color(0.3, 0.3, 0.3, 1)
	
	# Apply modulation to tilemap cells
	apply_modulation_to_tile(tile_coords, modulation)

func apply_modulation_to_tile(tile_coords: Vector2i, modulation: Color):
	"""Apply color modulation to all tilemaps at the given coordinates."""
	
	# Apply to floor tilemap
	if floor_tilemap:
		var tile_data = floor_tilemap.get_cell_tile_data(0, tile_coords)
		if tile_data:
			# Set modulation (this approach varies by Godot version)
			# For 4.0+: Create a custom data layer for modulation
			# For simpler approach: Use CanvasItem's modulate property
			var cell_alternative = floor_tilemap.get_cell_alternative_tile(0, tile_coords)
			floor_tilemap.set_cell(0, tile_coords, 
								 floor_tilemap.get_cell_source_id(0, tile_coords),
								 floor_tilemap.get_cell_atlas_coords(0, tile_coords),
								 cell_alternative)
