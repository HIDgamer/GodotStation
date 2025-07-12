extends Node2D
class_name AtmosphereVisualizer

# Visualization options
enum VisualizationMode {
	NONE,
	ZONE_TYPES,
	PRESSURE,
	TEMPERATURE,
	ATMOSPHERE,
	GRAVITY
}

# Colors for different visualizations
const ZONE_COLORS = {
	ZoneManager.ZoneType.INTERIOR: Color(0.0, 0.5, 1.0, 0.3),
	ZoneManager.ZoneType.MAINTENANCE: Color(1.0, 0.5, 0.0, 0.3),
	ZoneManager.ZoneType.EXTERIOR: Color(0.2, 0.2, 0.3, 0.3)
}

const PRESSURE_GRADIENT = {
	0.0: Color(0.0, 0.0, 0.0, 0.5),  # Vacuum
	25.0: Color(0.5, 0.0, 0.0, 0.3),  # Low pressure
	50.0: Color(1.0, 0.5, 0.0, 0.3),  # Half pressure
	100.0: Color(0.0, 0.7, 0.0, 0.3)   # Full pressure
}

const TEMPERATURE_GRADIENT = {
	-270.0: Color(0.0, 0.0, 0.5, 0.5),  # Extremely cold
	-100.0: Color(0.0, 0.5, 1.0, 0.3),  # Very cold
	0.0: Color(0.5, 0.8, 1.0, 0.3),     # Freezing
	20.0: Color(0.0, 0.7, 0.0, 0.3),    # Normal
	30.0: Color(1.0, 0.7, 0.0, 0.3),    # Warm
	50.0: Color(1.0, 0.0, 0.0, 0.3)     # Hot
}

# References
var editor_ref = null
var zone_manager = null
var cell_size: int = 32

# Current visualization state
var current_mode: int = VisualizationMode.NONE
var visualization_overlay: ColorRect = null
var breach_indicators: Array = []

func _init(p_editor_ref, p_zone_manager):
	editor_ref = p_editor_ref
	zone_manager = p_zone_manager
	
	# Get cell size from editor
	if editor_ref and editor_ref.has_method("get_cell_size"):
		cell_size = editor_ref.get_cell_size()
	
	# Create visualization overlay
	_setup_visualization()

func _setup_visualization():
	# Create ColorRect for overlay
	visualization_overlay = ColorRect.new()
	visualization_overlay.color = Color(0, 0, 0, 0)  # Start transparent
	visualization_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Pass mouse events through
	
	# Size will be set when used
	add_child(visualization_overlay)
	
	# Make sure it's initially hidden
	visualization_overlay.visible = false

func _process(delta):
	if current_mode != VisualizationMode.NONE and visualization_overlay and visualization_overlay.visible:
		# Update visualization
		queue_redraw()

func _draw():
	if current_mode == VisualizationMode.NONE or not visualization_overlay:
		return
	
	# Clear existing visualization
	visualization_overlay.queue_redraw()
	
	# Get viewport size and update overlay size
	if editor_ref and editor_ref.editor_viewport:
		var viewport_rect = editor_ref.editor_viewport.get_global_rect()
		visualization_overlay.set_position(viewport_rect.position)
		visualization_overlay.set_size(viewport_rect.size)
	
	# Draw breach indicators if needed
	_update_breach_indicators()

# Set visualization mode
func set_visualization_mode(mode: int):
	current_mode = mode
	
	# Show/hide visualization based on mode
	if visualization_overlay:
		visualization_overlay.visible = (mode != VisualizationMode.NONE)
	
	# Clear breach indicators if turning off
	if mode == VisualizationMode.NONE:
		_clear_breach_indicators()
	else:
		# Update breach indicators
		_update_breach_indicators()

# Generate visualization texture
func generate_visualization_texture():
	if not zone_manager or not editor_ref:
		return
	
	# Get map size
	var map_size = editor_ref.get_map_size()
	var image = Image.create(map_size.x * cell_size, map_size.y * cell_size, false, Image.FORMAT_RGBA8)
	
	# Fill with transparent color
	image.fill(Color(0, 0, 0, 0))
	
	# Draw zones based on visualization mode
	for zone_id in zone_manager.zones:
		var zone = zone_manager.zones[zone_id]
		
		for pos in zone.tiles:
			var color = _get_visualization_color(zone)
			
			# Fill the tile with color
			for y in range(cell_size):
				for x in range(cell_size):
					var img_x = pos.x * cell_size + x
					var img_y = pos.y * cell_size + y
					
					# Check bounds
					if img_x >= 0 and img_x < image.get_width() and img_y >= 0 and img_y < image.get_height():
						image.set_pixel(img_x, img_y, color)
	
	# Create texture from image
	var texture = ImageTexture.create_from_image(image)
	
	# Set texture to overlay
	if visualization_overlay:
		visualization_overlay.texture = texture

# Get color for a zone based on current visualization mode
func _get_visualization_color(zone) -> Color:
	match current_mode:
		VisualizationMode.ZONE_TYPES:
			return ZONE_COLORS.get(zone.type, Color(0.5, 0.5, 0.5, 0.3))
			
		VisualizationMode.PRESSURE:
			return _get_gradient_color(PRESSURE_GRADIENT, zone.pressure)
			
		VisualizationMode.TEMPERATURE:
			return _get_gradient_color(TEMPERATURE_GRADIENT, zone.temperature)
			
		VisualizationMode.ATMOSPHERE:
			return Color(0.0, 0.7, 1.0, 0.3) if zone.has_atmosphere else Color(0.0, 0.0, 0.0, 0.5)
			
		VisualizationMode.GRAVITY:
			return Color(0.7, 0.0, 1.0, 0.3) if zone.has_gravity else Color(0.3, 0.3, 0.3, 0.3)
			
		_:
			return Color(0, 0, 0, 0)

# Get color from a gradient based on value
func _get_gradient_color(gradient: Dictionary, value: float) -> Color:
	# Find the two closest gradient keys
	var keys = gradient.keys()
	keys.sort()
	
	# If value is below or above range, return first or last color
	if value <= keys[0]:
		return gradient[keys[0]]
	if value >= keys[keys.size() - 1]:
		return gradient[keys[keys.size() - 1]]
	
	# Find the two keys that value falls between
	var lower_key = keys[0]
	var upper_key = keys[keys.size() - 1]
	
	for i in range(keys.size() - 1):
		if keys[i] <= value and value < keys[i + 1]:
			lower_key = keys[i]
			upper_key = keys[i + 1]
			break
	
	# Interpolate between the two colors
	var t = (value - lower_key) / (upper_key - lower_key)
	return gradient[lower_key].lerp(gradient[upper_key], t)

# Update breach indicators
func _update_breach_indicators():
	# Clear old indicators
	_clear_breach_indicators()
	
	# Only show breach indicators in certain visualization modes
	if current_mode not in [VisualizationMode.PRESSURE, VisualizationMode.ATMOSPHERE]:
		return
	
	# Find breach points
	var breach_points = zone_manager.find_breach_points()
	
	# Create indicators for each breach
	for breach in breach_points:
		var pos = breach.position
		var world_pos = Vector2(pos.x * cell_size + cell_size / 2, 
							   pos.y * cell_size + cell_size / 2)
		
		# Create indicator
		var indicator = _create_breach_indicator()
		indicator.position = world_pos
		
		# Store reference
		breach_indicators.append(indicator)
		
		# Add to scene
		if editor_ref and editor_ref.editor_viewport and editor_ref.editor_viewport.get_node_or_null("Viewport"):
			editor_ref.editor_viewport.get_node("Viewport").add_child(indicator)

# Create a breach indicator node
func _create_breach_indicator() -> Node2D:
	var node = Node2D.new()
	
	# Add script for animation
	var script = GDScript.new()
	script.source_code = """
	extends Node2D
	
	var time = 0.0
	var pulse_speed = 2.0
	
	func _process(delta):
		time += delta * pulse_speed
		queue_redraw()
	
	func _draw():
		var size = 10.0 + sin(time) * 3.0
		var alpha = 0.7 + sin(time) * 0.3
		
		# Draw warning indicator
		draw_circle(Vector2.ZERO, size, Color(1.0, 0.0, 0.0, alpha))
		draw_circle(Vector2.ZERO, size * 0.7, Color(1.0, 1.0, 0.0, alpha))
		
		# Draw warning symbol
		var points = []
		points.append(Vector2(0, -5))
		points.append(Vector2(5, 5))
		points.append(Vector2(-5, 5))
		
		draw_colored_polygon(points, Color(0.0, 0.0, 0.0, alpha))
		
		# Exclamation mark
		draw_rect(Rect2(-1, -3, 2, 4), Color(0.0, 0.0, 0.0, alpha))
		draw_rect(Rect2(-1, 2, 2, 2), Color(0.0, 0.0, 0.0, alpha))
	"""
	
	script.reload()
	node.set_script(script)
	
	return node

# Clear all breach indicators
func _clear_breach_indicators():
	for indicator in breach_indicators:
		if is_instance_valid(indicator):
			indicator.queue_free()
	
	breach_indicators.clear()

# Get info text about atmosphere at a position
func get_atmosphere_info(position: Vector2i) -> String:
	if not zone_manager:
		return "No atmosphere data available"
	
	var data = zone_manager.get_visualization_data(position)
	
	var info = "Zone: " + data.zone_name + "\n"
	
	# Add zone type
	match data.zone_type:
		ZoneManager.ZoneType.INTERIOR:
			info += "Type: Interior\n"
		ZoneManager.ZoneType.MAINTENANCE:
			info += "Type: Maintenance\n"
		ZoneManager.ZoneType.EXTERIOR:
			info += "Type: Exterior\n"
		_:
			info += "Type: Unknown\n"
	
	# Add atmosphere data
	info += "Pressure: " + str(int(data.pressure)) + "%\n"
	info += "Temperature: " + str(data.temperature) + "°C\n"
	info += "Atmosphere: " + ("Yes" if data.has_atmosphere else "No") + "\n"
	info += "Gravity: " + ("Yes" if data.has_gravity else "No")
	
	return info
