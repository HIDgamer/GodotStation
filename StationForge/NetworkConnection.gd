extends Node2D
class_name NetworkConnection

var start_pos = Vector2i.ZERO
var end_pos = Vector2i.ZERO
var network_type = 0
var cell_size = 32

func _ready():
	# Get properties from meta
	start_pos = get_meta("start_pos", Vector2i.ZERO)
	end_pos = get_meta("end_pos", Vector2i.ZERO)
	network_type = get_meta("network_type", 0)
	
	# Set position to handle visibility
	position = Vector2(min(start_pos.x, end_pos.x) * cell_size, min(start_pos.y, end_pos.y) * cell_size)

func _draw():
	# Draw network line
	var color = _get_network_color()
	
	# Calculate positions in local space
	var local_start = Vector2(start_pos.x - position.x / cell_size, start_pos.y - position.y / cell_size) * cell_size + Vector2(cell_size/2, cell_size/2)
	var local_end = Vector2(end_pos.x - position.x / cell_size, end_pos.y - position.y / cell_size) * cell_size + Vector2(cell_size/2, cell_size/2)
	
	# Draw line
	draw_line(local_start, local_end, color, 3.0)
	
	# Draw connectors
	draw_circle(local_start, 4.0, color)
	draw_circle(local_end, 4.0, color)

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
