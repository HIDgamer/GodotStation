extends Control
class_name GridOverlay

var image_size = Vector2(0, 0)
var tile_size = Vector2(32, 32)

func _draw():
	var scale_factor = min(size.x / image_size.x, size.y / image_size.y)
	if scale_factor == 0:
		return
		
	var scaled_image_size = image_size * scale_factor
	var pos_offset = (size - scaled_image_size) / 2
	
	# Draw image outline
	var rect = Rect2(pos_offset, scaled_image_size)
	draw_rect(rect, Color(0.5, 0.5, 0.5, 0.5), false)
	
	# Draw grid
	var scaled_tile_size = tile_size * scale_factor
	
	# Draw horizontal lines
	for y in range(1, int(image_size.y / tile_size.y)):
		var start = Vector2(pos_offset.x, pos_offset.y + y * scaled_tile_size.y)
		var end = Vector2(pos_offset.x + scaled_image_size.x, pos_offset.y + y * scaled_tile_size.y)
		draw_line(start, end, Color(1, 1, 0, 0.5), 1.0)
	
	# Draw vertical lines
	for x in range(1, int(image_size.x / tile_size.x)):
		var start = Vector2(pos_offset.x + x * scaled_tile_size.x, pos_offset.y)
		var end = Vector2(pos_offset.x + x * scaled_tile_size.x, pos_offset.y + scaled_image_size.y)
		draw_line(start, end, Color(1, 1, 0, 0.5), 1.0)
