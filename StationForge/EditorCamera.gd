extends Camera2D

@export var pan_speed: float = 10.0
@export var zoom_min: float = 0.1
@export var zoom_max: float = 10.0
@export var zoom_speed: float = 0.1
@export var grid_snap: bool = false

var is_panning: bool = false
var last_mouse_pos: Vector2 = Vector2.ZERO

func _ready():
	# Set initial zoom level
	zoom = Vector2(1, 1)
	
	# Start centered
	position = Vector2.ZERO

func _input(event):
	# Handle mouse wheel for zooming
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera(1 + zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(1 - zoom_speed)
		
		# Middle mouse button for panning
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			is_panning = event.pressed
			if is_panning:
				last_mouse_pos = event.position
	
	# Handle mouse movement for panning
	if event is InputEventMouseMotion and is_panning:
		var delta = (event.position - last_mouse_pos) / zoom
		position -= delta
		
		# Snap to grid if enabled
		if grid_snap:
			position = Vector2(
				round(position.x / 32) * 32,
				round(position.y / 32) * 32
			)
		
		last_mouse_pos = event.position

func _zoom_camera(zoom_factor):
	# Calculate new zoom
	var new_zoom = zoom * zoom_factor
	
	# Clamp zoom to min/max values
	new_zoom.x = clamp(new_zoom.x, zoom_min, zoom_max)
	new_zoom.y = clamp(new_zoom.y, zoom_min, zoom_max)
	
	# Apply zoom
	zoom = new_zoom

func get_screen_to_world(screen_position: Vector2) -> Vector2:
	# Convert screen position to world position
	return screen_position / zoom + position - get_viewport_rect().size / 2 / zoom

func center_on_position(world_position: Vector2):
	# Center the camera on a specific world position
	position = world_position

func reset_view():
	# Reset zoom and position
	zoom = Vector2(1, 1)
	position = Vector2.ZERO
