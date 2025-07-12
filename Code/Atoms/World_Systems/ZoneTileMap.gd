# ZoneTileMap.gd
extends TileMap

# This tilemap defines zones that are considered "inside" the station
# Yellow tinted in editor, invisible in-game
# Areas with zone tiles are considered valid for normal movement
# Areas without zone tiles are considered space/void for zero-g

func _ready():
	# Make invisible in-game but keep collision/functionality
	modulate = Color(1, 1, 0, 0)  # Fully transparent

func _enter_tree():
	# Make visible with yellow tint in editor
	if Engine.is_editor_hint():
		modulate = Color(1, 1, 0, 0.3)  # Yellow tint in editor

# Check if a world position is inside a zone
func is_position_in_zone(world_position: Vector2) -> bool:
	var map_position = local_to_map(to_local(world_position))
	return get_cell_source_id(0, map_position) != -1  # Returns true if tile exists

# Check if a tile position is inside a zone
func is_tile_in_zone(tile_position: Vector2i) -> bool:
	return get_cell_source_id(0, tile_position) != -1  # Returns true if tile exists
