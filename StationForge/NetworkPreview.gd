extends Node2D
class_name NetworkPreview

var network_type = 0
var start_point = Vector2.ZERO
var end_point = Vector2.ZERO
var cell_size = 32

func _draw():
	# Draw network line
	var color = _get_network_color()
	
	# For preview, just draw a straight line
	draw_line(start_point * cell_size + Vector2(cell_size/2, cell_size/2), 
			end_point * cell_size + Vector2(cell_size/2, cell_size/2), 
			color, 3.0)
	
	# Draw start point indicator
	draw_circle(start_point * cell_size + Vector2(cell_size/2, cell_size/2), 5.0, color)
	
	# Draw end point indicator
	draw_circle(end_point * cell_size + Vector2(cell_size/2, cell_size/2), 5.0, color)

func _get_network_color() -> Color:
	match network_type:
		0:  # POWER
			return Color(1.0, 0.8, 0.0, 0.8)  # Yellow
		1:  # DATA
			return Color(0.0, 0.5, 1.0, 0.8)  # Blue
		2:  # PIPE
			return Color(0.0, 0.8, 0.5, 0.8)  # Cyan
		3:  # ATMOSPHERIC
			return Color(0.6, 0.8, 1.0, 0.8)  # Light blue
		_:
			return Color(1.0, 1.0, 1.0, 0.8)  # White
