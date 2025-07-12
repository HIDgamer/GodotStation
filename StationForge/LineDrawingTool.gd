extends Node
class_name LineDrawingTool

# References
var editor_ref = null

# Line drawing states
var is_drawing: bool = false
var start_position: Vector2i = Vector2i(-1, -1)
var end_position: Vector2i = Vector2i(-1, -1)
var preview_line: Array = []
var current_layer: int = 0
var current_tile_id: int = -1
var current_tile_atlas_coords: Vector2i = Vector2i(0, 0)

# Tool settings
@export var show_preview: bool = true
@export var preview_color: Color = Color(1, 1, 1, 0.5)

func _init():
	# Try to get editor reference
	if Engine.has_singleton("Editor"):
		editor_ref = Engine.get_singleton("Editor")

func start_line(start_pos: Vector2i, tile_id: int, atlas_coords: Vector2i, layer: int):
	is_drawing = true
	start_position = start_pos
	end_position = start_pos
	current_tile_id = tile_id
	current_tile_atlas_coords = atlas_coords
	current_layer = layer
	preview_line = [start_pos]

func update_line(current_pos: Vector2i):
	if is_drawing:
		end_position = current_pos
		preview_line = get_line_points(start_position, end_position)

func complete_line() -> Array[Vector2i]:
	is_drawing = false
	var line_points = preview_line.duplicate()
	preview_line.clear()
	return line_points

func cancel_line():
	is_drawing = false
	preview_line.clear()
	start_position = Vector2i(-1, -1)
	end_position = Vector2i(-1, -1)

func get_line_points(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	
	# Bresenham's line algorithm
	var x0 = start.x
	var y0 = start.y
	var x1 = end.x
	var y1 = end.y
	
	var dx = abs(x1 - x0)
	var dy = abs(y1 - y0)
	var sx = 1 if x0 < x1 else -1
	var sy = 1 if y0 < y1 else -1
	var err = dx - dy
	
	while true:
		points.append(Vector2i(x0, y0))
		
		if x0 == x1 and y0 == y1:
			break
		
		var e2 = 2 * err
		if e2 > -dy:
			if x0 == x1:
				break
			err -= dy
			x0 += sx
		
		if e2 < dx:
			if y0 == y1:
				break
			err += dx
			y0 += sy
	
	return points

func _draw_preview(canvas_item: RID):
	if not is_drawing or not show_preview:
		return
	
	# Draw line preview
	for point in preview_line:
		var world_pos = Vector2(point.x * 32, point.y * 32)
		var rect = Rect2(world_pos, Vector2(32, 32))
		RenderingServer.canvas_item_add_rect(canvas_item, rect, preview_color)

func apply_to_tilemap(tilemap: TileMap) -> void:
	if not is_drawing:
		return
	
	# Apply tiles along the line
	for point in preview_line:
		tilemap.set_cell(0, point, current_tile_id, current_tile_atlas_coords)
