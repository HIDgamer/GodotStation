extends Resource
class_name StairData

@export var from_z_level: int = 0
@export var to_z_level: int = 1
@export var tile_positions: Array[Vector2i] = []
@export var bidirectional: bool = true
@export var stair_name: String = "Unnamed Stair"

func _init(from_z: int = 0, to_z: int = 1, positions: Array[Vector2i] = [], is_bidirectional: bool = true, name: String = ""):
	from_z_level = from_z
	to_z_level = to_z
	tile_positions = positions
	bidirectional = is_bidirectional
	if name.is_empty():
		stair_name = "Stair " + str(from_z) + " to " + str(to_z)
	else:
		stair_name = name

func add_tile_position(pos: Vector2i):
	if pos not in tile_positions:
		tile_positions.append(pos)

func remove_tile_position(pos: Vector2i):
	tile_positions.erase(pos)

func has_tile_position(pos: Vector2i) -> bool:
	return pos in tile_positions

func get_target_z_for_source(source_z: int) -> int:
	if source_z == from_z_level:
		return to_z_level
	elif bidirectional and source_z == to_z_level:
		return from_z_level
	return -1

func is_valid() -> bool:
	return tile_positions.size() > 0 and from_z_level != to_z_level
