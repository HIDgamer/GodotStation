extends Panel

# Graph properties
@export var graph_color: Color = Color(0.2, 0.8, 0.2, 0.7)  # Default to green
@export var graph_width: int = 2
@export var background_color: Color = Color(0.1, 0.1, 0.1, 0.7)
@export var grid_color: Color = Color(0.3, 0.3, 0.3, 0.5)
@export var target_line_color: Color = Color(0.8, 0.8, 0.2, 0.5)
@export var show_grid: bool = true
@export var max_value: float = 120.0  # Max expected FPS
@export var min_value: float = 0.0
@export var show_target_line: bool = true
@export var target_value: float = 60.0  # Target FPS

# Data
var values = []

func _ready():
	# Initialize with empty data
	for i in range(60):
		values.append(0)

func _draw():
	var rect = get_rect()
	
	# Draw background
	draw_rect(rect, background_color)
	
	# Draw grid if enabled
	if show_grid:
		draw_grid(rect)
	
	# Draw target line if enabled
	if show_target_line:
		draw_target_line(rect)
	
	# Draw the graph
	draw_graph(rect)

func draw_grid(rect):
	# Draw horizontal grid lines (25%, 50%, 75%, 100%)
	for i in range(1, 5):
		var y = rect.size.y - (rect.size.y * (i / 4.0))
		draw_line(Vector2(0, y), Vector2(rect.size.x, y), grid_color)
	
	# Draw vertical grid lines (every 10 values)
	for i in range(1, 6):
		var x = rect.size.x * (i / 6.0)
		draw_line(Vector2(x, 0), Vector2(x, rect.size.y), grid_color)

func draw_target_line(rect):
	var normalized_target = (target_value - min_value) / (max_value - min_value)
	var y = rect.size.y - (rect.size.y * normalized_target)
	draw_line(Vector2(0, y), Vector2(rect.size.x, y), target_line_color, 1, true)

func draw_graph(rect):
	if values.size() < 2:
		return
	
	var points = []
	var value_count = values.size()
	
	# Create points from values
	for i in range(value_count):
		var normalized_value = clamp((values[i] - min_value) / (max_value - min_value), 0.0, 1.0)
		var x = rect.size.x * (float(i) / (value_count - 1))
		var y = rect.size.y - (rect.size.y * normalized_value)
		points.append(Vector2(x, y))
	
	# Draw line segments
	if points.size() >= 2:
		for i in range(1, points.size()):
			draw_line(points[i-1], points[i], graph_color, graph_width, true)

func update_values(new_values):
	values = new_values.duplicate()
	queue_redraw()  # Request redraw with new values
