extends Node
class_name FillTool

# References
var editor_ref = null

# Fill settings
@export var max_fill_tiles: int = 1000  # Limit to prevent infinite fills
@export var preview_color: Color = Color(1, 1, 0, 0.3)

# Fill state
var processed_tiles: Array[Vector2i] = []
var fill_target_type: int = -1

func _init():
	# Try to get editor reference
	if Engine.has_singleton("Editor"):
		editor_ref = Engine.get_singleton("Editor")

func fill_area(tilemap: TileMap, start_pos: Vector2i, fill_tile_id: int, atlas_coords: Vector2i) -> Array[Vector2i]:
	# Reset state
	processed_tiles.clear()
	
	# Get the current tile at the starting position
	fill_target_type = tilemap.get_cell_source_id(0, start_pos)
	
	# Don't fill if we're already at the target tile type
	if fill_target_type == fill_tile_id:
		return processed_tiles
	
	# Start flood fill
	_flood_fill(tilemap, start_pos, fill_tile_id, atlas_coords)
	
	# Return the filled tiles
	return processed_tiles

func _flood_fill(tilemap: TileMap, pos: Vector2i, fill_tile_id: int, atlas_coords: Vector2i):
	# Check if we've processed too many tiles (safety measure)
	if processed_tiles.size() >= max_fill_tiles:
		return
	
	# Skip if already processed
	if pos in processed_tiles:
		return
	
	# Skip if outside map bounds (depends on your game)
	# This is a simple check - adjust based on your game's map limits
	if pos.x < -1000 or pos.x > 1000 or pos.y < -1000 or pos.y > 1000:
		return
	
	# Check if this tile matches our target type
	var current_tile_type = tilemap.get_cell_source_id(0, pos)
	if current_tile_type != fill_target_type:
		return
	
	# Process this tile
	tilemap.set_cell(0, pos, fill_tile_id, atlas_coords)
	processed_tiles.append(pos)
	
	# Process neighbors
	_flood_fill(tilemap, Vector2i(pos.x + 1, pos.y), fill_tile_id, atlas_coords)
	_flood_fill(tilemap, Vector2i(pos.x - 1, pos.y), fill_tile_id, atlas_coords)
	_flood_fill(tilemap, Vector2i(pos.x, pos.y + 1), fill_tile_id, atlas_coords)
	_flood_fill(tilemap, Vector2i(pos.x, pos.y - 1), fill_tile_id, atlas_coords)

func fill_area_with_empty(tilemap: TileMap, start_pos: Vector2i) -> Array[Vector2i]:
	# Reset state
	processed_tiles.clear()
	
	# Get the current tile at the starting position
	fill_target_type = tilemap.get_cell_source_id(0, start_pos)
	
	# Don't fill if the target is already empty
	if fill_target_type == -1:
		return processed_tiles
	
	# Start flood fill with empty tile
	_flood_fill_with_empty(tilemap, start_pos)
	
	# Return the filled tiles
	return processed_tiles

func _flood_fill_with_empty(tilemap: TileMap, pos: Vector2i):
	# Check if we've processed too many tiles (safety measure)
	if processed_tiles.size() >= max_fill_tiles:
		return
	
	# Skip if already processed
	if pos in processed_tiles:
		return
	
	# Skip if outside map bounds
	if pos.x < -1000 or pos.x > 1000 or pos.y < -1000 or pos.y > 1000:
		return
	
	# Check if this tile matches our target type
	var current_tile_type = tilemap.get_cell_source_id(0, pos)
	if current_tile_type != fill_target_type:
		return
	
	# Process this tile (set to empty)
	tilemap.set_cell(0, pos, -1)
	processed_tiles.append(pos)
	
	# Process neighbors
	_flood_fill_with_empty(tilemap, Vector2i(pos.x + 1, pos.y))
	_flood_fill_with_empty(tilemap, Vector2i(pos.x - 1, pos.y))
	_flood_fill_with_empty(tilemap, Vector2i(pos.x, pos.y + 1))
	_flood_fill_with_empty(tilemap, Vector2i(pos.x, pos.y - 1))

func is_same_tile(tilemap: TileMap, pos: Vector2i, target_id: int) -> bool:
	return tilemap.get_cell_source_id(0, pos) == target_id
