extends Node

@onready var tilemap: TileMap = get_parent().get_node("PropLayer")
@onready var light_container: Node2D = get_parent().get_node("LightContainer")
@export var wall_light_scene: PackedScene

func _ready():
	if not wall_light_scene:
		push_error("WallLight scene not assigned!")
		return
	replace_tiles()

func replace_tiles():
	var used_rect = tilemap.get_used_rect()
	for x in range(used_rect.position.x, used_rect.position.x + used_rect.size.x):
		for y in range(used_rect.position.y, used_rect.position.y + used_rect.size.y):
			var tile_pos = Vector2i(x, y)
			var source_id = tilemap.get_cell_source_id(0, tile_pos)
			if source_id != -1:
				var atlas_coords = tilemap.get_cell_atlas_coords(0, tile_pos)
				var direction = get_direction_from_coords(atlas_coords)
				if direction != -1:
					var wall_light = wall_light_scene.instantiate()
					wall_light.LightDirection = direction
					wall_light.position = tilemap.map_to_local(tile_pos)
					light_container.add_child(wall_light)
					tilemap.erase_cell(0, tile_pos)

func get_direction_from_coords(coords: Vector2i) -> int:
	if coords == Vector2i(0, 0):
		return 0
	elif coords == Vector2i(1, 0):
		return 1
	elif coords == Vector2i(2, 0):
		return 2
	elif coords == Vector2i(3, 0):
		return 3
	return -1
