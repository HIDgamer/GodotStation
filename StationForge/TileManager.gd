extends Node
class_name TilesetManager

# Default tile sizes
const TILE_SIZE = 32

# Paths to tileset resources
const FLOOR_TILESET_PATH = "res://Assets/Tilesets/Floor/Tiles.tres"
const WALL_TILESET_PATH = "res://Assets/Tilesets/Walls/Walls.tres"
const OBJECT_TILESET_PATH = "res://assets/tilesets/object_tileset.tres"
const ZONE_TILESET_PATH = "res://assets/tilesets/zone_tileset.tres"

# Paths to tileset textures
const FLOOR_TEXTURE_PATH = "res://assets/tilesets/floor_tiles.png"
const WALL_TEXTURE_PATH = "res://assets/tilesets/wall_tiles.png" 
const OBJECT_TEXTURE_PATH = "res://assets/tilesets/object_tiles.png"
const ZONE_TEXTURE_PATH = "res://Assets/Tilesets/Zone/Zone.png"

# Cache for loaded tilesets
var _loaded_tilesets = {}

# Create or load floor tileset
static func get_floor_tileset() -> TileSet:
	# Check if the tileset already exists
	if ResourceLoader.exists(FLOOR_TILESET_PATH):
		return ResourceLoader.load(FLOOR_TILESET_PATH)
	
	# Create a new tileset
	return create_floor_tileset()

# Create or load wall tileset
static func get_wall_tileset() -> TileSet:
	# Check if the tileset already exists
	if ResourceLoader.exists(WALL_TILESET_PATH):
		return ResourceLoader.load(WALL_TILESET_PATH)
	
	# Create a new tileset
	return create_wall_tileset()

# Create or load object tileset
static func get_object_tileset() -> TileSet:
	# Check if the tileset already exists
	if ResourceLoader.exists(OBJECT_TILESET_PATH):
		return ResourceLoader.load(OBJECT_TILESET_PATH)
	
	# Create a new tileset
	return create_object_tileset()

# Create or load zone tileset
static func get_zone_tileset() -> TileSet:
	# Check if the tileset already exists
	if ResourceLoader.exists(ZONE_TILESET_PATH):
		return ResourceLoader.load(ZONE_TILESET_PATH)
	
	# Create a new tileset
	return create_zone_tileset()

# Create a new floor tileset
static func create_floor_tileset() -> TileSet:
	var tileset = TileSet.new()
	
	# Set basic properties
	tileset.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	
	# Create a source
	var source_id = 0
	
	# Check if texture exists
	if not ResourceLoader.exists(FLOOR_TEXTURE_PATH):
		# Create a placeholder texture
		return create_placeholder_tileset()
	
	# Load texture
	var texture = ResourceLoader.load(FLOOR_TEXTURE_PATH)
	
	# Create tile set source from texture
	var source = TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	
	# Calculate how many tiles in the texture
	var cols = texture.get_width() / TILE_SIZE
	var rows = texture.get_height() / TILE_SIZE
	
	# Add tiles from texture
	for y in range(rows):
		for x in range(cols):
			source.create_tile(Vector2i(x, y))
	
	# Add source to tileset
	tileset.add_source(source, source_id)
	
	# Save tileset for future use
	var save_dir = FLOOR_TILESET_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(save_dir):
		DirAccess.make_dir_recursive_absolute(save_dir)
	
	ResourceSaver.save(tileset, FLOOR_TILESET_PATH)
	
	return tileset

# Create a new wall tileset
static func create_wall_tileset() -> TileSet:
	var tileset = TileSet.new()
	
	# Set basic properties
	tileset.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	
	# Create a source
	var source_id = 0
	
	# Check if texture exists
	if not ResourceLoader.exists(WALL_TEXTURE_PATH):
		# Create a placeholder texture
		return create_placeholder_tileset()
	
	# Load texture
	var texture = ResourceLoader.load(WALL_TEXTURE_PATH)
	
	# Create tile set source from texture
	var source = TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	
	# Calculate how many tiles in the texture
	var cols = texture.get_width() / TILE_SIZE
	var rows = texture.get_height() / TILE_SIZE
	
	# Add tiles from texture
	for y in range(rows):
		for x in range(cols):
			source.create_tile(Vector2i(x, y))
	
	# Add source to tileset
	tileset.add_source(source, source_id)
	
	# Save tileset for future use
	var save_dir = WALL_TILESET_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(save_dir):
		DirAccess.make_dir_recursive_absolute(save_dir)
	
	ResourceSaver.save(tileset, WALL_TILESET_PATH)
	
	return tileset

# Create a new object tileset
static func create_object_tileset() -> TileSet:
	var tileset = TileSet.new()
	
	# Set basic properties
	tileset.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	
	# Create a source
	var source_id = 0
	
	# Check if texture exists
	if not ResourceLoader.exists(OBJECT_TEXTURE_PATH):
		# Create a placeholder texture
		return create_placeholder_tileset()
	
	# Load texture
	var texture = ResourceLoader.load(OBJECT_TEXTURE_PATH)
	
	# Create tile set source from texture
	var source = TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	
	# Calculate how many tiles in the texture
	var cols = texture.get_width() / TILE_SIZE
	var rows = texture.get_height() / TILE_SIZE
	
	# Add tiles from texture
	for y in range(rows):
		for x in range(cols):
			source.create_tile(Vector2i(x, y))
	
	# Add source to tileset
	tileset.add_source(source, source_id)
	
	# Save tileset for future use
	var save_dir = OBJECT_TILESET_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(save_dir):
		DirAccess.make_dir_recursive_absolute(save_dir)
	
	ResourceSaver.save(tileset, OBJECT_TILESET_PATH)
	
	return tileset

# Create a new zone tileset
static func create_zone_tileset() -> TileSet:
	var tileset = TileSet.new()
	
	# Set basic properties
	tileset.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	
	# Create a source
	var source_id = 0
	
	# Check if texture exists
	if not ResourceLoader.exists(ZONE_TEXTURE_PATH):
		# Create a placeholder texture
		return create_placeholder_tileset()
	
	# Load texture
	var texture = ResourceLoader.load(ZONE_TEXTURE_PATH)
	
	# Create tile set source from texture
	var source = TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	
	# Calculate how many tiles in the texture
	var cols = texture.get_width() / TILE_SIZE
	var rows = texture.get_height() / TILE_SIZE
	
	# Add tiles from texture
	for y in range(rows):
		for x in range(cols):
			source.create_tile(Vector2i(x, y))
	
	# Add source to tileset
	tileset.add_source(source, source_id)
	
	# Save tileset for future use
	var save_dir = ZONE_TILESET_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(save_dir):
		DirAccess.make_dir_recursive_absolute(save_dir)
	
	ResourceSaver.save(tileset, ZONE_TILESET_PATH)
	
	return tileset

# Create a placeholder tileset for when textures aren't available
static func create_placeholder_tileset() -> TileSet:
	var tileset = TileSet.new()
	
	# Set basic properties
	tileset.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	
	# Create a source
	var source_id = 0
	
	# Create a placeholder texture
	var placeholder_image = Image.create(TILE_SIZE * 2, TILE_SIZE * 2, false, Image.FORMAT_RGBA8)
	
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
					placeholder_image.set_pixel(x * TILE_SIZE + px, y * TILE_SIZE + py, color)
			
			# Draw a pattern
			var pattern_color = Color(1, 1, 1, 0.7)
			for i in range(TILE_SIZE):
				placeholder_image.set_pixel(x * TILE_SIZE + i, y * TILE_SIZE + i, pattern_color)
				placeholder_image.set_pixel(x * TILE_SIZE + i, y * TILE_SIZE + TILE_SIZE - 1 - i, pattern_color)
	
	# Create ImageTexture from Image
	var placeholder_texture = ImageTexture.create_from_image(placeholder_image)
	
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

# Apply the appropriate tilesets to the tilemaps
static func apply_tilesets_to_tilemaps(floor_map: TileMap, wall_map: TileMap, objects_map: TileMap, zone_map: TileMap):
	floor_map.tile_set = get_floor_tileset()
	wall_map.tile_set = get_wall_tileset()
	objects_map.tile_set = get_object_tileset()
	zone_map.tile_set = get_zone_tileset()
