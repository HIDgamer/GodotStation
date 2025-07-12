extends Node
class_name EnhancedTilesetManager

# Constants
const TILE_SIZE = 32

# Terrain patterns
enum TerrainPattern {
	NONE,
	MATCH_CORNERS,    # 16-bit pattern (corners and edges)
	MATCH_SIDES,      # 47-bit pattern (for more complex terrain)
	WANG_TILES        # For Wang tile patterns
}

# Tileset configuration for each type
var tileset_configs = {
	"floor": {
		"path": "res://Assets/Tilesets/Floor/Tiles.png",
		"tile_size": Vector2i(TILE_SIZE, TILE_SIZE),
		"terrain_pattern": TerrainPattern.MATCH_CORNERS,
		"regions": []  # Will contain atlas regions info
	},
	"wall": {
		"path": "res://Assets/Tilesets/Walls/Walls.tres",
		"tile_size": Vector2i(TILE_SIZE, TILE_SIZE),
		"terrain_pattern": TerrainPattern.MATCH_CORNERS,
		"regions": []
	},
	"object": {
		"path": "res://assets/tilesets/object_tiles.png", 
		"tile_size": Vector2i(TILE_SIZE, TILE_SIZE),
		"terrain_pattern": TerrainPattern.NONE,
		"regions": []
	},
	"zone": {
		"path": "res://Assets/Tilesets/Zone/Zone.png",
		"tile_size": Vector2i(TILE_SIZE, TILE_SIZE),
		"terrain_pattern": TerrainPattern.NONE,
		"regions": []
	}
}

# Cache for loaded tilesets
var _loaded_tilesets = {}

# Terrain and tile property data
var terrain_data = {}
var tile_properties = {}

func _ready():
	# Initialize regions and terrain data
	_initialize_tileset_regions()
	_initialize_terrain_data()

# Create or get tileset by type
func get_tileset(type: String) -> TileSet:
	# Check if already loaded
	if type in _loaded_tilesets:
		return _loaded_tilesets[type]
	
	# Check if configuration exists
	if not type in tileset_configs:
		push_error("Tileset type not found: " + type)
		return create_placeholder_tileset()
	
	# Create the tileset
	var tileset = _create_tileset_for_type(type)
	
	# Cache it
	_loaded_tilesets[type] = tileset
	
	return tileset

# Create a tileset for a specific type
func _create_tileset_for_type(type: String) -> TileSet:
	var config = tileset_configs[type]
	var tileset = TileSet.new()
	
	# Set basic properties
	tileset.tile_size = config.tile_size
	
	# Check if resource path exists
	var texture = null
	if ResourceLoader.exists(config.path):
		if config.path.ends_with(".tres") or config.path.ends_with(".res"):
			# It's a resource, load it directly
			var res = ResourceLoader.load(config.path)
			if res is TileSet:
				# We can use this tileset directly, but we'll still apply our configuration
				tileset = res
			elif res is Texture2D:
				texture = res
		else:
			# Load texture
			texture = ResourceLoader.load(config.path)
	
	# If no sources, create an empty source ID 0 for imported tiles
	if tileset.get_source_count() == 0:
		var source_id = 0
		var source = TileSetAtlasSource.new()
		source.texture_region_size = config.tile_size
		tileset.add_source(source, source_id)
		
		# Create an empty source for imported tiles
		var import_source_id = 100
		var import_source = TileSetAtlasSource.new()
		import_source.texture_region_size = config.tile_size
		import_source.set_meta("import_source", true)
		tileset.add_source(import_source, import_source_id)
	
	# Save tileset for future use
	_save_tileset(tileset, type)
	
	return tileset

# Configure terrain for a tileset
func _configure_terrain_for_tileset(tileset: TileSet, type: String):
	# Skip if no terrain pattern or data
	if not type in terrain_data:
		return
	
	# Get terrain configuration
	var pattern = tileset_configs[type].terrain_pattern
	
	# Create terrain set if it doesn't exist
	var terrain_set_id = 0
	if tileset.get_terrain_sets_count() == 0:
		tileset.add_terrain_set(terrain_set_id)
		
		# Set terrain mode based on pattern
		match pattern:
			TerrainPattern.MATCH_CORNERS:
				tileset.set_terrain_set_mode(terrain_set_id, TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES)
			TerrainPattern.MATCH_SIDES:
				tileset.set_terrain_set_mode(terrain_set_id, TileSet.TERRAIN_MODE_MATCH_SIDES)
			TerrainPattern.WANG_TILES:
				tileset.set_terrain_set_mode(terrain_set_id, TileSet.TERRAIN_MODE_MATCH_CORNERS)
	
	# Add terrains for this type
	var terrains = terrain_data[type].get("terrains", [])
	for i in range(terrains.size()):
		var terrain_info = terrains[i]
		
		# Check if terrain already exists
		if i < tileset.get_terrains_count(terrain_set_id):
			continue
		
		# Add terrain
		tileset.add_terrain(terrain_set_id, i)
		tileset.set_terrain_name(terrain_set_id, i, terrain_info.name)
		tileset.set_terrain_color(terrain_set_id, i, terrain_info.color)
	
	# Configure terrain data for each tile in all sources
	for source_id in range(tileset.get_source_count()):
		var source = tileset.get_source(tileset.get_source_id(source_id))
		if not source is TileSetAtlasSource:
			continue
		
		var atlas_source = source as TileSetAtlasSource
		
		# Process each tile in the source
		for tile_pos in atlas_source.get_tiles_count():
			var coords = atlas_source.get_tile_id(tile_pos)
			
			# Find terrain data for this tile
			var tile_info = _find_terrain_data_for_tile(type, coords)
			if tile_info.is_empty():
				continue
			
			var terrain_id = tile_info.get("terrain_id", 0)
			var terrain_bits = tile_info.get("terrain_bits", {})
			
			# Get tile data
			var tile_data = atlas_source.get_tile_data(coords, 0)
			if not tile_data:
				continue
			
			# Set terrain set
			tile_data.terrain_set = terrain_set_id
			
			# Set peering bits
			for bit_index_str in terrain_bits:
				var bit_index = int(bit_index_str)
				var bit_terrain = terrain_bits[bit_index_str]
				
				# In Godot 4.4, we directly set the terrain for each peering bit
				tile_data.set_terrain_peering_bit(bit_index, bit_terrain)

# Find terrain data for a specific tile
func _find_terrain_data_for_tile(type: String, coords: Vector2i) -> Dictionary:
	if not type in terrain_data:
		return {}
	
	var tiles = terrain_data[type].get("tiles", {})
	
	# Search for matching tile data
	for tile_id in tiles:
		var tile_info = tiles[tile_id]
		var atlas_coords = tile_info.get("atlas_coords", Vector2i(-1, -1))
		
		if atlas_coords == coords:
			return {
				"terrain_id": tile_info.get("terrain_id", 0),
				"terrain_bits": tile_info.get("terrain_bits", {})
			}
	
	return {}

# Create a placeholder tileset
func create_placeholder_tileset() -> TileSet:
	var tileset = TileSet.new()
	
	# Set basic properties
	tileset.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	
	# Create a source with placeholder texture
	var source_id = 0
	
	# Create a placeholder texture
	var image = Image.create(TILE_SIZE * 2, TILE_SIZE * 2, false, Image.FORMAT_RGBA8)
	
	# Draw some patterns to differentiate tiles
	for y in range(2):
		for x in range(2):
			var color = Color(
				randf_range(0.2, 0.8), 
				randf_range(0.2, 0.8), 
				randf_range(0.2, 0.8),
				1.0
			)
			
			# Fill base color
			for py in range(TILE_SIZE):
				for px in range(TILE_SIZE):
					image.set_pixel(x * TILE_SIZE + px, y * TILE_SIZE + py, color)
			
			# Draw a pattern
			var pattern_color = Color(1, 1, 1, 0.7)
			for i in range(TILE_SIZE):
				image.set_pixel(x * TILE_SIZE + i, y * TILE_SIZE + i, pattern_color)
				image.set_pixel(x * TILE_SIZE + i, y * TILE_SIZE + TILE_SIZE - 1 - i, pattern_color)
	
	# Create ImageTexture from Image
	var placeholder_texture = ImageTexture.create_from_image(image)
	
	# Create tile set source from texture
	var source = TileSetAtlasSource.new()
	source.texture = placeholder_texture
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	
	# Add tiles
	for y in range(2):
		for x in range(2):
			source.create_tile(Vector2i(x, y))
	
	# Add source to tileset
	tileset.add_source(source, source_id)
	
	return tileset

# Save tileset to file
func _save_tileset(tileset: TileSet, type: String) -> bool:
	var save_path = "res://assets/tilesets/" + type + "_tileset.tres"
	
	var save_dir = save_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(save_dir):
		DirAccess.make_dir_recursive_absolute(save_dir)
	
	return ResourceSaver.save(tileset, save_path) == OK

# Initialize regions for each tileset
func _initialize_tileset_regions():
	# Floor tileset regions
	tileset_configs.floor.regions = [
		{
			"name": "basic_floors",
			"region_size": Vector2i(4, 4),
			"x_offset": 0,
			"y_offset": 0,
			"terrain_name": "basic_floors"
		},
		{
			"name": "carpet_floors",
			"region_size": Vector2i(4, 4),
			"x_offset": 0,
			"y_offset": 4,
			"terrain_name": "carpet_floors"
		}
	]
	
	# Wall tileset regions
	tileset_configs.wall.regions = [
		{
			"name": "metal_walls",
			"region_size": Vector2i(5, 5),
			"x_offset": 0,
			"y_offset": 0,
			"terrain_name": "metal_walls"
		},
		{
			"name": "glass_walls",
			"region_size": Vector2i(5, 5),
			"x_offset": 5,
			"y_offset": 0,
			"terrain_name": "glass_walls"
		}
	]
	
	# Object tileset regions
	tileset_configs.object.regions = [
		{
			"name": "doors",
			"region_size": Vector2i(4, 2),
			"x_offset": 0,
			"y_offset": 0
		},
		{
			"name": "furniture",
			"region_size": Vector2i(4, 4),
			"x_offset": 0,
			"y_offset": 2
		}
	]
	
	# Zone tileset regions
	tileset_configs.zone.regions = [
		{
			"name": "zones",
			"region_size": Vector2i(3, 1),
			"x_offset": 0,
			"y_offset": 0
		}
	]

# Initialize terrain data for auto-tiling
func _initialize_terrain_data():
	# Floor terrain data
	terrain_data.floor = {
		"terrains": [
			{"name": "Metal Floor", "color": Color(0.7, 0.7, 0.7)},
			{"name": "Carpet", "color": Color(0.5, 0.2, 0.2)}
		],
		"tiles": {
			# Basic metal floor bitmask tiles
			"metal_center": {
				"atlas_coords": Vector2i(1, 1),  # Center tile
				"terrain_id": 0,
				"terrain_bits": {
					TileSet.CELL_NEIGHBOR_RIGHT_SIDE: 0,
					TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: 0,
					TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: 0,
					TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: 0,
					TileSet.CELL_NEIGHBOR_LEFT_SIDE: 0,
					TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: 0,
					TileSet.CELL_NEIGHBOR_TOP_SIDE: 0,
					TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: 0
				}
			},
			"metal_corner_tl": {
				"atlas_coords": Vector2i(0, 0),  # Top-left corner
				"terrain_id": 0,
				"terrain_bits": {
					TileSet.CELL_NEIGHBOR_RIGHT_SIDE: 0,
					TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: 0,
					TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: 0,
					TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: 0,
					TileSet.CELL_NEIGHBOR_LEFT_SIDE: -1,
					TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_TOP_SIDE: -1,
					TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: -1
				}
			},
			"metal_edge_top": {
				"atlas_coords": Vector2i(1, 0),  # Top edge
				"terrain_id": 0,
				"terrain_bits": {
					TileSet.CELL_NEIGHBOR_RIGHT_SIDE: 0,
					TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: 0,
					TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: 0,
					TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: 0,
					TileSet.CELL_NEIGHBOR_LEFT_SIDE: 0,
					TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_TOP_SIDE: -1,
					TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: -1
				}
			},
			"metal_corner_tr": {
				"atlas_coords": Vector2i(2, 0),  # Top-right corner
				"terrain_id": 0,
				"terrain_bits": {
					TileSet.CELL_NEIGHBOR_RIGHT_SIDE: -1,
					TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: 0,
					TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: 0,
					TileSet.CELL_NEIGHBOR_LEFT_SIDE: 0,
					TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_TOP_SIDE: -1,
					TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: -1
				}
			},
			"metal_edge_left": {
				"atlas_coords": Vector2i(0, 1),  # Left edge
				"terrain_id": 0,
				"terrain_bits": {
					TileSet.CELL_NEIGHBOR_RIGHT_SIDE: 0,
					TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: 0,
					TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: 0,
					TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_LEFT_SIDE: -1,
					TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_TOP_SIDE: 0,
					TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: 0
				}
			},
			"metal_edge_right": {
				"atlas_coords": Vector2i(2, 1),  # Right edge
				"terrain_id": 0,
				"terrain_bits": {
					TileSet.CELL_NEIGHBOR_RIGHT_SIDE: -1,
					TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: 0,
					TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: 0,
					TileSet.CELL_NEIGHBOR_LEFT_SIDE: 0,
					TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: 0,
					TileSet.CELL_NEIGHBOR_TOP_SIDE: 0,
					TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: -1
				}
			},
			"metal_corner_bl": {
				"atlas_coords": Vector2i(0, 2),  # Bottom-left corner
				"terrain_id": 0,
				"terrain_bits": {
					TileSet.CELL_NEIGHBOR_RIGHT_SIDE: 0,
					TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: -1,
					TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_LEFT_SIDE: -1,
					TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_TOP_SIDE: 0,
					TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: 0
				}
			},
			"metal_edge_bottom": {
				"atlas_coords": Vector2i(1, 2),  # Bottom edge
				"terrain_id": 0,
				"terrain_bits": {
					TileSet.CELL_NEIGHBOR_RIGHT_SIDE: 0,
					TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: -1,
					TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_LEFT_SIDE: 0,
					TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: 0,
					TileSet.CELL_NEIGHBOR_TOP_SIDE: 0,
					TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: 0
				}
			},
			"metal_corner_br": {
				"atlas_coords": Vector2i(2, 2),  # Bottom-right corner
				"terrain_id": 0,
				"terrain_bits": {
					TileSet.CELL_NEIGHBOR_RIGHT_SIDE: -1,
					TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: -1,
					TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_LEFT_SIDE: 0,
					TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: 0,
					TileSet.CELL_NEIGHBOR_TOP_SIDE: 0,
					TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: 0
				}
			},
			
			# Carpet floor tiles
			"carpet_center": {
				"atlas_coords": Vector2i(1, 5),  # Center carpet tile
				"terrain_id": 1,
				"terrain_bits": {
					TileSet.CELL_NEIGHBOR_RIGHT_SIDE: 1,
					TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: 1,
					TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: 1,
					TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: 1,
					TileSet.CELL_NEIGHBOR_LEFT_SIDE: 1,
					TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: 1,
					TileSet.CELL_NEIGHBOR_TOP_SIDE: 1,
					TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: 1
				}
			}
		}
	}
	
	# Wall terrain data
	terrain_data.wall = {
		"terrains": [
			{"name": "Metal Wall", "color": Color(0.4, 0.4, 0.5)},
			{"name": "Glass Wall", "color": Color(0.7, 0.8, 0.9)}
		],
		"tiles": {
			# Metal wall bitmask tiles
			"metal_center": {
				"atlas_coords": Vector2i(2, 2),  # Center wall tile
				"terrain_id": 0,
				"terrain_bits": {
					TileSet.CELL_NEIGHBOR_RIGHT_SIDE: 0,
					TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: 0,
					TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: 0,
					TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: 0,
					TileSet.CELL_NEIGHBOR_LEFT_SIDE: 0,
					TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: 0,
					TileSet.CELL_NEIGHBOR_TOP_SIDE: 0,
					TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: 0
				}
			},
			"metal_horizontal": {
				"atlas_coords": Vector2i(2, 1),  # Horizontal wall
				"terrain_id": 0,
				"terrain_bits": {
					TileSet.CELL_NEIGHBOR_RIGHT_SIDE: 0,
					TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: -1,
					TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_LEFT_SIDE: 0,
					TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_TOP_SIDE: -1,
					TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: -1
				}
			},
			"metal_vertical": {
				"atlas_coords": Vector2i(1, 2),  # Vertical wall
				"terrain_id": 0,
				"terrain_bits": {
					TileSet.CELL_NEIGHBOR_RIGHT_SIDE: -1,
					TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: 0,
					TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_LEFT_SIDE: -1,
					TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_TOP_SIDE: 0,
					TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: -1
				}
			},
			"metal_corner_tl": {
				"atlas_coords": Vector2i(1, 1),  # Top-left corner
				"terrain_id": 0,
				"terrain_bits": {
					TileSet.CELL_NEIGHBOR_RIGHT_SIDE: 0,
					TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: 0,
					TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: 0,
					TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_LEFT_SIDE: -1,
					TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_TOP_SIDE: -1,
					TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: -1
				}
			},
			"metal_corner_tr": {
				"atlas_coords": Vector2i(3, 1),  # Top-right corner
				"terrain_id": 0,
				"terrain_bits": {
					TileSet.CELL_NEIGHBOR_RIGHT_SIDE: -1,
					TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: 0,
					TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: 0,
					TileSet.CELL_NEIGHBOR_LEFT_SIDE: 0,
					TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_TOP_SIDE: -1,
					TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: -1
				}
			},
			"metal_corner_bl": {
				"atlas_coords": Vector2i(1, 3),  # Bottom-left corner
				"terrain_id": 0,
				"terrain_bits": {
					TileSet.CELL_NEIGHBOR_RIGHT_SIDE: 0,
					TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: -1,
					TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_LEFT_SIDE: -1,
					TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_TOP_SIDE: 0,
					TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: 0
				}
			},
			"metal_corner_br": {
				"atlas_coords": Vector2i(3, 3),  # Bottom-right corner
				"terrain_id": 0,
				"terrain_bits": {
					TileSet.CELL_NEIGHBOR_RIGHT_SIDE: -1,
					TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: -1,
					TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: -1,
					TileSet.CELL_NEIGHBOR_LEFT_SIDE: 0,
					TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: 0,
					TileSet.CELL_NEIGHBOR_TOP_SIDE: 0,
					TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: -1
				}
			},
			
			# Glass wall
			"glass_center": {
				"atlas_coords": Vector2i(7, 2),  # Center glass wall
				"terrain_id": 1,
				"terrain_bits": {
					TileSet.CELL_NEIGHBOR_RIGHT_SIDE: 1,
					TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: 1,
					TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: 1,
					TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: 1,
					TileSet.CELL_NEIGHBOR_LEFT_SIDE: 1,
					TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: 1,
					TileSet.CELL_NEIGHBOR_TOP_SIDE: 1,
					TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: 1
				}
			}
		}
	}

# Apply tilesets to tilemaps
func apply_tilesets_to_tilemaps(floor_map: TileMap, wall_map: TileMap, objects_map: TileMap, zone_map: TileMap):
	floor_map.tile_set = get_tileset("floor")
	wall_map.tile_set = get_tileset("wall")
	objects_map.tile_set = get_tileset("object")
	zone_map.tile_set = get_tileset("zone")

# Get terrain info for a tile
func get_terrain_info(tile_type: String, coords: Vector2i) -> Dictionary:
	if not tile_type in terrain_data:
		return {}
	
	var tiles = terrain_data[tile_type].get("tiles", {})
	
	# Find the tile with matching coords
	for tile_id in tiles:
		var tile = tiles[tile_id]
		if tile.get("atlas_coords", Vector2i(-1, -1)) == coords:
			return {
				"terrain_id": tile.get("terrain_id", -1),
				"terrain_bits": tile.get("terrain_bits", {})
			}
	
	return {}

# Auto-connect terrain for intelligent placement
func auto_connect_terrain(tilemap: TileMap, position: Vector2i, tile_type: String, source_id: int, atlas_coords: Vector2i) -> Vector2i:
	# Skip if no terrain data
	if not tile_type in terrain_data:
		return atlas_coords
	
	# Get terrain info for this tile
	var terrain_info = _find_terrain_data_for_tile(tile_type, atlas_coords)
	if terrain_info.is_empty():
		return atlas_coords
	
	var terrain_id = terrain_info.get("terrain_id", -1)
	if terrain_id < 0:
		return atlas_coords
	
	# Find best matching tile based on neighboring tiles
	var best_tile = _find_best_matching_tile(tilemap, position, tile_type, terrain_id)
	if best_tile != Vector2i(-1, -1):
		return best_tile
	
	return atlas_coords

# Find the best matching tile based on neighboring terrain
func _find_best_matching_tile(tilemap: TileMap, position: Vector2i, tile_type: String, terrain_id: int) -> Vector2i:
	if not tile_type in terrain_data:
		return Vector2i(-1, -1)
	
	var tiles = terrain_data[tile_type].get("tiles", {})
	var best_match_score = -1
	var best_match_coords = Vector2i(-1, -1)
	
	# Check surrounding tiles to determine terrain connections
	var neighbor_terrains = _get_neighbor_terrains(tilemap, position)
	
	# Check each tile with the same terrain ID for how well it matches neighbors
	for tile_id in tiles:
		var tile = tiles[tile_id]
		if tile.get("terrain_id", -1) != terrain_id:
			continue
		
		var terrain_bits = tile.get("terrain_bits", {})
		var match_score = 0
		
		# Calculate match score - how well does this tile match the surrounding terrain?
		for bit_dir in neighbor_terrains:
			var neighbor_terrain = neighbor_terrains[bit_dir]
			var tile_bit_terrain = -1
			
			# Convert from string key to int if needed
			var bit_key = bit_dir
			if terrain_bits.has(str(bit_dir)):
				bit_key = str(bit_dir)
			
			if terrain_bits.has(bit_key):
				tile_bit_terrain = terrain_bits[bit_key]
			
			if neighbor_terrain == tile_bit_terrain:
				match_score += 1
		
		# Update best match if this tile scores higher
		if match_score > best_match_score:
			best_match_score = match_score
			best_match_coords = tile.get("atlas_coords", Vector2i(-1, -1))
	
	return best_match_coords

# Get terrain types of neighboring tiles
func _get_neighbor_terrains(tilemap: TileMap, position: Vector2i) -> Dictionary:
	var neighbors = {}
	var tileset = tilemap.tile_set
	
	if not tileset:
		return neighbors
	
	# Define neighbor directions to check
	var neighbor_dirs = [
		TileSet.CELL_NEIGHBOR_RIGHT_SIDE,
		TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
		TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
		TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
		TileSet.CELL_NEIGHBOR_LEFT_SIDE,
		TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
		TileSet.CELL_NEIGHBOR_TOP_SIDE,
		TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER
	]
	
	# Get terrain set
	var terrain_set = 0  # Assuming we use terrain set 0 for everything
	
	# Check each neighbor direction
	for dir in neighbor_dirs:
		var neighbor_pos = tilemap.get_neighbor_cell(position, dir)
		var source_id = tilemap.get_cell_source_id(0, neighbor_pos)
		
		if source_id >= 0:
			var atlas_coords = tilemap.get_cell_atlas_coords(0, neighbor_pos)
			var alt_id = tilemap.get_cell_alternative_tile(0, neighbor_pos)
			
			# Get tile data
			var tile_data = null
			var source = tileset.get_source(source_id)
			
			if source is TileSetAtlasSource:
				if source.has_tile(atlas_coords):
					tile_data = source.get_tile_data(atlas_coords, alt_id)
			
			if tile_data:
				# Check terrain
				if tile_data.terrain_set == terrain_set:
					neighbors[dir] = tile_data.get_terrain_peering_bit(dir)
				else:
					neighbors[dir] = -1
			else:
				neighbors[dir] = -1
		else:
			# No tile
			neighbors[dir] = -1
	
	return neighbors

# Update surrounding tiles when a new tile is placed
func update_surrounding_tiles(tilemap: TileMap, position: Vector2i, tile_type: String):
	# Skip if no terrain data
	if not tile_type in terrain_data:
		return
	
	var tileset = tilemap.tile_set
	if not tileset:
		return
	
	# Define neighbor directions
	var neighbor_dirs = [
		TileSet.CELL_NEIGHBOR_RIGHT_SIDE,
		TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
		TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
		TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
		TileSet.CELL_NEIGHBOR_LEFT_SIDE,
		TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
		TileSet.CELL_NEIGHBOR_TOP_SIDE,
		TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER
	]
	
	# Update each neighbor
	for dir in neighbor_dirs:
		var neighbor_pos = tilemap.get_neighbor_cell(position, dir)
		var source_id = tilemap.get_cell_source_id(0, neighbor_pos)
		
		if source_id >= 0:
			var atlas_coords = tilemap.get_cell_atlas_coords(0, neighbor_pos)
			
			# Get terrain info for this tile
			var terrain_info = _find_terrain_data_for_tile(tile_type, atlas_coords)
			if terrain_info.is_empty():
				continue
			
			var terrain_id = terrain_info.get("terrain_id", -1)
			if terrain_id < 0:
				continue
			
			# Find best matching tile for this neighbor
			var new_coords = _find_best_matching_tile(tilemap, neighbor_pos, tile_type, terrain_id)
			if new_coords != Vector2i(-1, -1) and new_coords != atlas_coords:
				tilemap.set_cell(0, neighbor_pos, source_id, new_coords)

# Find or create a special source for imported tiles
func find_or_create_import_source(tileset: TileSet, type: String) -> int:
	# Look for existing import source
	for source_idx in range(tileset.get_source_count()):
		var source_id = tileset.get_source_id(source_idx)
		var source = tileset.get_source(source_id)
		
		if source is TileSetAtlasSource and source.get_meta("import_source", false):
			return source_id
	
	# Create new source
	var source_id = 100  # Use consistent ID for imported sources
	
	# Skip if already exists
	if tileset.has_source(source_id):
		return source_id
	
	# Create atlas source
	var source = TileSetAtlasSource.new()
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	source.set_meta("import_source", true)
	source.set_meta("type", type)
	
	# Add to tileset
	tileset.add_source(source, source_id)
	
	return source_id

# Import a texture as a new tile
func import_texture_as_tile(texture: Texture2D, category: String, tile_data: Dictionary) -> Dictionary:
	# Ensure category exists
	if not category in tileset_configs:
		push_error("Unknown tile category: " + category)
		return {}
	
	# Get tileset
	var tileset = get_tileset(category)
	if not tileset:
		return {}
	
	# Find or create a source for imported tiles
	var source_id = find_or_create_import_source(tileset, category)
	
	# Get source
	var source = tileset.get_source(source_id) as TileSetAtlasSource
	if not source:
		return {}
	
	# Update texture if provided
	if texture and source.texture != texture:
		source.texture = texture
	
	# Find next available atlas coordinates if not specified
	var atlas_coords = tile_data.get("atlas_coords", _find_next_available_coords(source))
	
	# Create the tile
	if not source.has_tile(atlas_coords):
		source.create_tile(atlas_coords)
	
	# Set up auto-tiling if needed
	if "autotile_info" in tile_data and tile_data.autotile_info.type != "none":
		_setup_autotile_for_imported_tile(tileset, source, atlas_coords, tile_data)
	
	# Store custom properties
	_store_tile_properties(category, source_id, atlas_coords, tile_data)
	
	# Return tile info
	return {
		"source_id": source_id,
		"atlas_coords": atlas_coords,
		"category": category
	}

# Set up autotile terrain for an imported tile
func _setup_autotile_for_imported_tile(tileset: TileSet, source: TileSetAtlasSource, atlas_coords: Vector2i, tile_data: Dictionary):
	# Get autotile info
	var autotile_info = tile_data.autotile_info
	var autotile_type = autotile_info.type
	
	# Get or create terrain set
	var terrain_set = autotile_info.get("terrain_set", 0)
	if terrain_set >= tileset.get_terrain_sets_count():
		tileset.add_terrain_set(terrain_set)
		
		# Set terrain mode
		var terrain_mode = TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES
		match autotile_type:
			"wang_2x2":
				terrain_mode = TileSet.TERRAIN_MODE_MATCH_CORNERS
			"wang_3x3":
				terrain_mode = TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES
			"47_bit":
				terrain_mode = TileSet.TERRAIN_MODE_MATCH_SIDES
				
		tileset.set_terrain_set_mode(terrain_set, terrain_mode)
	
	# Get or create terrain
	var terrain_id = autotile_info.get("terrain_id", 0)
	if terrain_id >= tileset.get_terrains_count(terrain_set):
		tileset.add_terrain(terrain_set, terrain_id)
		
		# Set terrain properties
		var terrain_name = tile_data.get("subcategory", "terrain") + "_" + str(terrain_id)
		tileset.set_terrain_name(terrain_set, terrain_id, terrain_name)
		
		# Generate a color based on the terrain name for visual distinction
		var color = Color(
			randf_range(0.3, 0.7),
			randf_range(0.3, 0.7),
			randf_range(0.3, 0.7)
		)
		tileset.set_terrain_color(terrain_set, terrain_id, color)
	
	# Get tile data
	var tile_data_obj = source.get_tile_data(atlas_coords, 0)
	if not tile_data_obj:
		return
	
	# Set terrain set
	tile_data_obj.terrain_set = terrain_set
	
	# Set terrain bits if specified
	if "terrain_bits" in autotile_info:
		for bit_index_str in autotile_info.terrain_bits:
			var bit_index = int(bit_index_str)
			var bit_terrain = autotile_info.terrain_bits[bit_index_str]
			
			tile_data_obj.set_terrain_peering_bit(bit_index, bit_terrain)
	else:
		# Default to full terrain connectivity
		for bit_index in [
			TileSet.CELL_NEIGHBOR_RIGHT_SIDE,
			TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
			TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
			TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
			TileSet.CELL_NEIGHBOR_LEFT_SIDE,
			TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
			TileSet.CELL_NEIGHBOR_TOP_SIDE,
			TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER
		]:
			tile_data_obj.set_terrain_peering_bit(bit_index, terrain_id)

# Find next available coordinates in a source
func _find_next_available_coords(source: TileSetAtlasSource) -> Vector2i:
	var max_x = 0
	var max_y = 0
	
	# Find the highest used coordinates
	for i in range(source.get_tiles_count()):
		var coords = source.get_tile_id(i)
		max_x = max(max_x, coords.x)
		max_y = max(max_y, coords.y)
	
	# If we have tiles in this row, add to end of row
	if source.get_tiles_count() > 0:
		return Vector2i(max_x + 1, max_y)
	
	# Otherwise start a new row
	return Vector2i(0, 0)

# Store custom properties for a tile
func _store_tile_properties(category: String, source_id: int, atlas_coords: Vector2i, tile_data: Dictionary):
	# Create category if needed
	if not category in tile_properties:
		tile_properties[category] = {}
	
	# Create source entry if needed
	var source_key = str(source_id)
	if not source_key in tile_properties[category]:
		tile_properties[category][source_key] = {}
	
	# Create coords entry
	var coords_key = str(atlas_coords.x) + "," + str(atlas_coords.y)
	
	# Store properties
	tile_properties[category][source_key][coords_key] = {
		"name": tile_data.get("name", "Unnamed Tile"),
		"id": tile_data.get("id", ""),
		"properties": tile_data.get("properties", {}).duplicate(),
		"subcategory": tile_data.get("subcategory", "")
	}

# Get tile properties from stored data
func get_tile_properties(category: String, source_id: int, atlas_coords: Vector2i) -> Dictionary:
	if not category in tile_properties:
		return {}
	
	var source_key = str(source_id)
	if not source_key in tile_properties[category]:
		return {}
	
	var coords_key = str(atlas_coords.x) + "," + str(atlas_coords.y)
	if not coords_key in tile_properties[category][source_key]:
		return {}
	
	return tile_properties[category][source_key][coords_key].get("properties", {}).duplicate()
