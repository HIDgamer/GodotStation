extends Node2D

@export var cell_size: int = 32
@export var grid_color: Color = Color(0.5, 0.5, 0.5, 0.2)
@export var major_grid_color: Color = Color(0.5, 0.5, 0.5, 0.4)
@export var major_grid_interval: int = 5
@export var grid_extents: Vector2 = Vector2(100, 100)
@export var draw_grid: bool = true
@export var show_cursor: bool = true

var camera_ref: Camera2D = null
var editor_ref = null
var mouse_grid_position: Vector2i = Vector2i.ZERO

func _ready():
	# Try to get camera reference
	camera_ref = get_node_or_null("../EditorCamera")
	
	# Try to get editor reference
	editor_ref = get_node_or_null("/root/Editor")

func _process(_delta):
	# Update from editor if available
	if editor_ref and "mouse_grid_position" in editor_ref:
		mouse_grid_position = editor_ref.mouse_grid_position
	
	# Force redraw
	queue_redraw()

func _draw():
	if not draw_grid:
		return
		
	var view_rect = get_view_rect()
	_draw_grid(view_rect)
	
	if show_cursor:
		draw_cursor()

func get_view_rect() -> Rect2:
	# Get the visible rect based on camera position and zoom
	var view_size = get_viewport_rect().size
	
	if camera_ref:
		var top_left = camera_ref.position - (view_size / 2 / camera_ref.zoom)
		var size = view_size / camera_ref.zoom
		return Rect2(top_left, size)
	else:
		# Fallback to fixed area around origin
		return Rect2(-grid_extents * cell_size, grid_extents * 2 * cell_size)

func _draw_grid(view_rect: Rect2):
	# Calculate grid bounds based on view
	var start_x = floor(view_rect.position.x / cell_size) * cell_size
	var start_y = floor(view_rect.position.y / cell_size) * cell_size
	var end_x = ceil((view_rect.position.x + view_rect.size.x) / cell_size) * cell_size
	var end_y = ceil((view_rect.position.y + view_rect.size.y) / cell_size) * cell_size
	
	# Draw vertical lines
	for x in range(start_x, end_x + 1, cell_size):
		var is_major = (int(x / cell_size) % major_grid_interval) == 0
		var color = major_grid_color if is_major else grid_color
		var line_width = 2.0 if is_major else 1.0
		
		draw_line(
			Vector2(x, start_y),
			Vector2(x, end_y),
			color,
			line_width
		)
	
	# Draw horizontal lines
	for y in range(start_y, end_y + 1, cell_size):
		var is_major = (int(y / cell_size) % major_grid_interval) == 0
		var color = major_grid_color if is_major else grid_color
		var line_width = 2.0 if is_major else 1.0
		
		draw_line(
			Vector2(start_x, y),
			Vector2(end_x, y),
			color,
			line_width
		)

func draw_cursor():
	# Get grid-aligned position
	var cursor_pos = Vector2(
		mouse_grid_position.x * cell_size,
		mouse_grid_position.y * cell_size
	)
	
	# Draw rectangle at cursor position
	draw_rect(
		Rect2(cursor_pos, Vector2(cell_size, cell_size)),
		Color(1, 1, 1, 0.3),
		false,
		2.0
	)
	
	# Draw filled rectangle for better visibility
	draw_rect(
		Rect2(cursor_pos, Vector2(cell_size, cell_size)),
		Color(1, 1, 1, 0.1),
		true
	)
	
	# Draw coordinates
	var coord_text = str(mouse_grid_position.x) + "," + str(mouse_grid_position.y)
	var text_pos = cursor_pos + Vector2(2, cell_size - 5)
	
	draw_string(
		ThemeDB.fallback_font,
		text_pos,
		coord_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		Color(1, 1, 1, 0.8)
	)

func set_cell_size(size: int):
	cell_size = size
	queue_redraw()

func toggle_grid_visibility(visible: bool):
	draw_grid = visible
	queue_redraw()
