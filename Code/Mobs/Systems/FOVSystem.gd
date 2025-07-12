extends Node

class_name FOVController

# Configuration
@export var fov_angle_degrees: float = 90.0
@export var fov_range_pixels: float = 320.0
@export var peripheral_vision: float = 0.2
@export var blur_strength: float = 3.0
@export var darkness: float = 0.7

# References
var grid_controller = null
var character = null
var shader_rect = null

# Direction mapping for grid movement
var direction_angles = {
	0: -PI/2,    # NORTH = -90 degrees (UP)
	1: 0,        # EAST = 0 degrees (RIGHT)
	2: PI/2,     # SOUTH = 90 degrees (DOWN)
	3: PI,       # WEST = 180 degrees (LEFT)
	4: -PI/4,    # NORTHEAST = -45 degrees
	5: PI/4,     # SOUTHEAST = 45 degrees
	6: 3*PI/4,   # SOUTHWEST = 135 degrees
	7: -3*PI/4   # NORTHWEST = -135 degrees
}

func _ready():
	# Find essential nodes
	character = get_parent()
	grid_controller = character
	if grid_controller == null:
		grid_controller = character
	
	# Find the shader rect
	shader_rect = $CanvasLayer/FOVShaderRect
	
	# Initial shader parameters update
	update_shader_parameters()
	
	# Connect to the grid controller direction change signal
	if grid_controller and grid_controller.has_signal("direction_changed"):
		grid_controller.connect("direction_changed", Callable(self, "_on_direction_changed"))

func _process(delta):
	# Update shader parameters every frame to track camera movement and player position
	update_shader_parameters()

func update_shader_parameters():
	if shader_rect == null or character == null:
		return
	
	# Get viewport and camera
	var viewport = get_viewport()
	var canvas_transform = viewport.get_canvas_transform()
	var viewport_size = viewport.get_visible_rect().size
	
	# Convert player position from world space to screen space
	var screen_position = canvas_transform * character.position
	
	# Now convert to normalized coordinates (0-1)
	var normalized_pos = Vector2(
		(screen_position.x / viewport_size.x),
		(screen_position.y / viewport_size.y)
	)
	
	# Update player position in shader
	shader_rect.material.set_shader_parameter("player_position", normalized_pos)
	
	# Get player direction
	var direction_angle = 0.0
	if grid_controller != null and "current_direction" in grid_controller:
		var dir_index = grid_controller.current_direction
		if direction_angles.has(dir_index):
			direction_angle = direction_angles[dir_index]
			# Debug print to verify angle
			# print("Direction: ", dir_index, " Angle: ", rad_to_deg(direction_angle))
	
	# Update direction in shader
	shader_rect.material.set_shader_parameter("player_direction", direction_angle)
	
	# Update FOV parameters based on player state
	if grid_controller != null and "current_state" in grid_controller:
		var state = grid_controller.current_state
		
		# Adjust FOV based on movement state
		match state:
			1: # RUNNING
				# Narrower FOV while running (tunnel vision)
				set_fov_parameters(fov_angle_degrees * 0.8, fov_range_pixels * 1.2, 
								  peripheral_vision * 0.7, blur_strength, darkness)
			4: # CRAWLING
				# Wider but shorter FOV when crawling
				set_fov_parameters(fov_angle_degrees * 1.3, fov_range_pixels * 0.6, 
								  peripheral_vision * 1.2, blur_strength, darkness)
			5: # FLOATING
				# Wider FOV in zero-G
				set_fov_parameters(270.0, fov_range_pixels * 0.8, 
								  peripheral_vision * 1.5, blur_strength * 0.7, darkness * 0.7)
			_: # DEFAULT/IDLE/MOVING
				# Normal FOV
				set_fov_parameters(fov_angle_degrees, fov_range_pixels, 
								  peripheral_vision, blur_strength, darkness)

func world_to_viewport(world_pos: Vector2) -> Vector2:
	var viewport = get_viewport()
	var canvas_transform = viewport.get_canvas_transform()
	return canvas_transform * world_pos

func _on_direction_changed(old_direction, new_direction):
	update_shader_parameters()

func set_fov_parameters(angle: float, range_pixels: float, peripheral: float, blur: float, dark: float):
	if shader_rect == null:
		return
	
	# Get viewport size for normalization
	var viewport_size = get_viewport().get_visible_rect().size
	var screen_diagonal = sqrt(viewport_size.x * viewport_size.x + viewport_size.y * viewport_size.y)
	var normalized_range = range_pixels / screen_diagonal
	
	# Update shader parameters
	shader_rect.material.set_shader_parameter("fov_angle", deg_to_rad(angle))
	shader_rect.material.set_shader_parameter("fov_range", normalized_range)
	shader_rect.material.set_shader_parameter("peripheral_vision", peripheral)
	shader_rect.material.set_shader_parameter("blur_strength", blur)
	shader_rect.material.set_shader_parameter("darkness", dark)

# Public methods for game code to adjust FOV
func set_fov_angle(degrees: float):
	fov_angle_degrees = degrees
	update_shader_parameters()

func set_fov_range(pixels: float):
	fov_range_pixels = pixels
	update_shader_parameters()

func set_night_vision(enabled: bool):
	if enabled:
		# Night vision: less darkness, more peripheral vision
		darkness = 0.3
		peripheral_vision = 0.4
	else:
		# Normal vision
		darkness = 0.7
		peripheral_vision = 0.2
	
	update_shader_parameters()
