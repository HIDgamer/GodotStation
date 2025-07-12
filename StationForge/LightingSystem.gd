extends Node2D
class_name LightingSystem

# Lighting constants
const AMBIENT_LIGHT_MIN = 0.05  # Minimum ambient light (complete darkness)
const AMBIENT_LIGHT_MAX = 0.8   # Maximum ambient light (daylight)
const AMBIENT_LIGHT_EXTERIOR = 0.2  # Ambient light in exterior spaces
const LIGHT_ATTENUATION = 1.5   # How quickly light fades with distance
const DARKNESS_LAYER_Z = 100    # Z-index for darkness layer

# References
var editor_ref = null
var floor_tilemap: TileMap = null
var wall_tilemap: TileMap = null
var objects_tilemap: TileMap = null
var object_container: Node2D = null
var zone_manager = null
var lights_container: Node2D = null
var darkness_container: Node2D = null

# View properties
var cell_size: int = 32
var view_rect: Rect2
var darkness_visible: bool = true
var ambient_light_level: float = AMBIENT_LIGHT_MIN
var show_lighting_preview: bool = false

# Cached light data
var light_sources = []  # Array of light source objects/positions

func _init(p_editor_ref, p_lights_container = null, p_darkness_container = null):
	editor_ref = p_editor_ref
	
	# Get references
	if editor_ref:
		floor_tilemap = editor_ref.floor_tilemap
		wall_tilemap = editor_ref.wall_tilemap
		objects_tilemap = editor_ref.objects_tilemap
		
		# Get cell size
		cell_size = editor_ref.get_cell_size() if editor_ref.has_method("get_cell_size") else 32
		
		# Try to get object container
		object_container = editor_ref.get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport/PlacedObjects")
		
		# Try to get zone manager
		if "zone_manager" in editor_ref:
			zone_manager = editor_ref.zone_manager
	
	# Create or use provided containers
	if p_lights_container:
		lights_container = p_lights_container
	else:
		lights_container = Node2D.new()
		lights_container.name = "LightSources"
		if editor_ref and editor_ref.has_node("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport"):
			editor_ref.get_node("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport").add_child(lights_container)
	
	if p_darkness_container:
		darkness_container = p_darkness_container
	else:
		darkness_container = Node2D.new()
		darkness_container.name = "DarknessLayer"
		darkness_container.z_index = DARKNESS_LAYER_Z
		if editor_ref and editor_ref.has_node("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport"):
			editor_ref.get_node("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport").add_child(darkness_container)

func _process(delta):
	# Update lighting view
	update_light_view()
	
	# Only draw when visible
	if not darkness_visible:
		return
	
	# Handle camera updates
	if editor_ref and editor_ref.editor_camera:
		update_view_rect()
		
		# Check if darkness container is clear
		if darkness_container and darkness_container.get_child_count() == 0:
			_generate_darkness()
		else:
			# Update darkness position
			_update_darkness_position()

# Set up the lighting system
func setup():
	# Update ambient light
	set_ambient_light(ambient_light_level)
	
	# Generate initial darkness
	update_view_rect()
	_generate_darkness()
	
	# Find all light sources
	find_light_sources()

# Update the view rectangle based on camera
func update_view_rect():
	if editor_ref and editor_ref.editor_camera:
		var camera = editor_ref.editor_camera
		var viewport_size = get_viewport_rect().size
		var camera_pos = camera.position
		var camera_zoom = camera.zoom
		
		var view_size = viewport_size / camera_zoom
		var top_left = camera_pos - view_size / 2
		
		view_rect = Rect2(top_left, view_size)
	else:
		# Default to a large area if no camera
		view_rect = Rect2(-1000, -1000, 2000, 2000)

# Generate darkness overlay
func _generate_darkness():
	if not darkness_container:
		return
	
	# Clear previous darkness
	for child in darkness_container.get_children():
		child.queue_free()
	
	# Create a fullscreen ColorRect for darkness
	var dark_rect = ColorRect.new()
	dark_rect.color = Color(0, 0, 0, 1.0 - ambient_light_level)
	
	# Size to viewport
	if editor_ref and editor_ref.editor_viewport:
		var viewport_rect = editor_ref.editor_viewport.get_global_rect()
		dark_rect.size = viewport_rect.size
	else:
		dark_rect.size = get_viewport_rect().size
	
	# Position at top-left of screen
	dark_rect.position = Vector2.ZERO
	
	# Add to container
	darkness_container.add_child(dark_rect)
	
	# Generate lighting mask
	_generate_light_mask()

# Update darkness position with camera
func _update_darkness_position():
	if not darkness_container or darkness_container.get_child_count() == 0:
		return
	
	# Update position of darkness (typically not needed as it's screen-space)
	# But update mask positions to follow camera
	_update_light_mask_positions()

# Generate mask for lights
func _generate_light_mask():
	if not darkness_container or darkness_container.get_child_count() == 0:
		return
	
	# First find all lights
	if light_sources.size() == 0:
		find_light_sources()
	
	# Create CanvasItem for lights
	for light_source in light_sources:
		# Create light circle
		var light_circle = _create_light_circle(light_source)
		
		# Add to container
		if light_circle:
			darkness_container.add_child(light_circle)

# Update light mask positions
func _update_light_mask_positions():
	# The first child is the darkness rect, start from index 1
	if not darkness_container or darkness_container.get_child_count() <= 1:
		return
	
	# Update each light position - masks should be children 1 and beyond
	var light_index = 0
	for i in range(1, darkness_container.get_child_count()):
		var mask = darkness_container.get_child(i)
		if light_index < light_sources.size():
			var light = light_sources[light_index]
			
			# Update position
			if "position" in light:
				mask.position = light.position
			elif "grid_position" in light:
				mask.position = Vector2(light.grid_position.x * cell_size + cell_size/2, 
									   light.grid_position.y * cell_size + cell_size/2)
		
		light_index += 1

# Create a light circle for masking
func _create_light_circle(light_source) -> Node2D:
	# Extract light properties
	var position = Vector2.ZERO
	var radius = 100.0
	var color = Color(1, 1, 0.8, 0.8)
	var intensity = 1.0
	
	if "position" in light_source:
		position = light_source.position
	elif "grid_position" in light_source:
		position = Vector2(light_source.grid_position.x * cell_size + cell_size/2, 
						  light_source.grid_position.y * cell_size + cell_size/2)
	
	if "light_radius" in light_source:
		radius = light_source.light_radius
	
	if "light_color" in light_source:
		color = light_source.light_color
	
	if "light_intensity" in light_source:
		intensity = light_source.light_intensity
	
	# Create node
	var light_node = Node2D.new()
	light_node.position = position
	
	# Set up script
	var script = GDScript.new()
	script.source_code = """
	extends Node2D
	
	var radius = 100.0
	var color = Color(1, 1, 0.8, 0.8)
	var intensity = 1.0
	
	func _draw():
		# Draw light circle with gradient
		var max_alpha = 0.95 * intensity
		
		# Draw several circles with decreasing alpha for soft glow
		for i in range(10):
			var t = float(i) / 10.0
			var current_radius = radius * (1.0 - t * 0.5)
			var current_alpha = max_alpha * (1.0 - t)
			
			var current_color = color
			current_color.a = current_alpha
			
			draw_circle(Vector2.ZERO, current_radius, current_color)
	"""
	
	script.reload()
	light_node.set_script(script)
	
	# Set light properties
	light_node.radius = radius
	light_node.color = color
	light_node.intensity = intensity
	
	# Position at light location
	light_node.position = position
	
	return light_node

# Find all light sources in the map
func find_light_sources():
	light_sources.clear()
	
	# Check for object lights
	if object_container:
		for obj in object_container.get_children():
			if obj.name.begins_with("NetworkConnection_"):
				continue  # Skip network connections
			
			# Check if object is a light source
			var obj_type = obj.get_meta("object_type", "")
			
			if "light" in obj_type.to_lower() or obj.has_meta("light_source") or \
			   (obj.has_method("is_light_source") and obj.is_light_source()):
				# Extract light properties
				var light_data = {
					"grid_position": obj.get_meta("grid_position", Vector2i.ZERO),
					"light_radius": 150.0,  # Default radius
					"light_color": Color(1, 1, 0.8, 0.8),  # Default warm light
					"light_intensity": 1.0  # Default intensity
				}
				
				# Try to get actual light properties
				if obj.has_method("get_light_properties"):
					var props = obj.get_light_properties()
					
					if "radius" in props:
						light_data.light_radius = props.radius
					
					if "color" in props:
						light_data.light_color = props.color
					
					if "intensity" in props:
						light_data.light_intensity = props.intensity
				
				# Add to light sources
				light_sources.append(light_data)
	
	# Add any lights from lights_container
	if lights_container:
		for light in lights_container.get_children():
			if light.visible:
				var light_data = {
					"position": light.position,
					"light_radius": 150.0,  # Default
					"light_color": Color(1, 1, 0.8, 0.8),  # Default
					"light_intensity": 1.0  # Default
				}
				
				# Try to get actual light properties
				if "radius" in light:
					light_data.light_radius = light.radius
				
				if "color" in light:
					light_data.light_color = light.color
				
				if "intensity" in light:
					light_data.light_intensity = light.intensity
				
				# Add to light sources
				light_sources.append(light_data)

# Set ambient light level (0.0 = dark, 1.0 = fully lit)
func set_ambient_light(level: float):
	ambient_light_level = clamp(level, AMBIENT_LIGHT_MIN, AMBIENT_LIGHT_MAX)
	
	# Update darkness overlay
	if darkness_container and darkness_container.get_child_count() > 0:
		var dark_rect = darkness_container.get_child(0)
		if dark_rect is ColorRect:
			dark_rect.color.a = 1.0 - ambient_light_level

# Toggle darkness visibility
func toggle_darkness(visible: bool):
	darkness_visible = visible
	
	if darkness_container:
		darkness_container.visible = visible

# Show lighting preview
func show_preview(show: bool):
	show_lighting_preview = show
	
	# Set very dark when previewing
	if show:
		# Save current ambient light
		set_ambient_light(AMBIENT_LIGHT_MIN)
	else:
		# Restore normal light
		set_ambient_light(AMBIENT_LIGHT_MAX)
	
	# Make sure darkness is visible when previewing
	if darkness_container:
		darkness_container.visible = show

# Update lighting state based on zone
func update_light_for_zone(zone_id: int):
	if not zone_manager or not zone_id in zone_manager.zones:
		return
	
	var zone = zone_manager.zones[zone_id]
	
	# Adjust ambient light based on zone type
	match zone.type:
		ZoneManager.ZoneType.INTERIOR:
			set_ambient_light(AMBIENT_LIGHT_MAX)
		ZoneManager.ZoneType.MAINTENANCE:
			set_ambient_light(AMBIENT_LIGHT_MAX * 0.7)  # Dimmer in maintenance areas
		ZoneManager.ZoneType.EXTERIOR:
			set_ambient_light(AMBIENT_LIGHT_EXTERIOR)  # Dark in space

# Update lighting view
func update_light_view():
	if not show_lighting_preview:
		return
	
	# Check if we have any lights that need updating
	if light_sources.size() == 0:
		find_light_sources()
	
	# If we have lights, update their visibility based on view rect
	if darkness_container and darkness_container.get_child_count() > 1:
		_update_light_mask_positions()

# Create a light source at position
func create_light(position: Vector2i, radius: float = 150.0, color: Color = Color(1, 1, 0.8, 0.8), intensity: float = 1.0) -> Node2D:
	if not lights_container:
		return null
	
	# Create light node
	var light = Node2D.new()
	light.position = Vector2(position.x * cell_size + cell_size/2, position.y * cell_size + cell_size/2)
	light.name = "Light_%d_%d" % [position.x, position.y]
	
	# Store light properties
	light.set("radius", radius)
	light.set("color", color)
	light.set("intensity", intensity)
	
	# Set up script for drawing
	var script = GDScript.new()
	script.source_code = """
	extends Node2D
	
	var radius = 100.0
	var color = Color(1, 1, 0.8, 0.8)
	var intensity = 1.0
	
	func _draw():
		# Draw light indicator
		var indicator_radius = 8.0
		
		# Main light circle
		draw_circle(Vector2.ZERO, indicator_radius, Color(1, 1, 0, 1))
		
		# Glow
		for i in range(5):
			var t = float(i) / 5.0
			var current_radius = indicator_radius * (1.0 + t)
			var current_alpha = 0.5 * (1.0 - t)
			
			var current_color = color
			current_color.a = current_alpha
			
			draw_circle(Vector2.ZERO, current_radius, current_color)
		
		# When showing preview, also show light radius
		if get_parent().get_parent().has_method("is_light_preview_active") and \
		   get_parent().get_parent().is_light_preview_active():
			# Draw radius indicator
			draw_arc(Vector2.ZERO, radius, 0, TAU, 32, Color(1, 1, 0, 0.3), 2.0)
	"""
	
	script.reload()
	light.set_script(script)
	
	# Add to container
	lights_container.add_child(light)
	
	# Add to light sources
	light_sources.append({
		"position": light.position,
		"light_radius": radius,
		"light_color": color,
		"light_intensity": intensity
	})
	
	# Regenerate light mask
	_generate_light_mask()
	
	return light

# Remove light at position
func remove_light(position: Vector2i) -> bool:
	if not lights_container:
		return false
	
	# Find light at position
	for light in lights_container.get_children():
		var light_pos = Vector2i(int(light.position.x / cell_size), int(light.position.y / cell_size))
		
		if light_pos == position:
			# Remove from container
			lights_container.remove_child(light)
			light.queue_free()
			
			# Remove from light sources
			for i in range(light_sources.size()):
				if "position" in light_sources[i]:
					var source_pos = Vector2i(int(light_sources[i].position.x / cell_size), 
											int(light_sources[i].position.y / cell_size))
					
					if source_pos == position:
						light_sources.remove_at(i)
						break
			
			# Regenerate light mask
			_generate_light_mask()
			
			return true
	
	return false

# Check if light preview is active
func is_light_preview_active() -> bool:
	return show_lighting_preview

func save_to_map_data(map_data: MapData):
	if not lights_container:
		return
	
	var lights_data = []
	
	# Save each light
	for light in lights_container.get_children():
		var grid_pos = Vector2i(int(light.position.x / cell_size), int(light.position.y / cell_size))

		var radius = light.has_method("get_radius") and light.get("radius") or 150.0
		var color = light.has_method("get_color") and light.get("color") or Color(1, 1, 0.8, 0.8)
		var intensity = light.has_method("get_intensity") and light.get("intensity") or 1.0
		
		lights_data.append({
			"position": {
				"x": grid_pos.x,
				"y": grid_pos.y
			},
			"radius": radius,
			"color": {
				"r": color.r,
				"g": color.g,
				"b": color.b,
				"a": color.a
			},
			"intensity": intensity
		})
	
	# Add to map metadata
	map_data.metadata["lighting"] = {
		"ambient_level": ambient_light_level,
		"lights": lights_data
	}

# Load lighting data from map file
func load_from_map_data(map_data: MapData):
	if not lights_container:
		return
	
	# Clear existing lights
	for child in lights_container.get_children():
		child.queue_free()
	
	light_sources.clear()
	
	# Check if lighting data exists
	if "lighting" in map_data.metadata:
		var lighting_data = map_data.metadata.lighting
		
		# Set ambient light
		if "ambient_level" in lighting_data:
			set_ambient_light(lighting_data.ambient_level)
		
		# Create lights
		if "lights" in lighting_data:
			for light_data in lighting_data.lights:
				var position = Vector2i(light_data.position.x, light_data.position.y)
				var radius = light_data.get("radius", 150.0)
				
				var color = Color(1, 1, 0.8, 0.8)
				if "color" in light_data:
					color = Color(
						light_data.color.get("r", 1.0),
						light_data.color.get("g", 1.0),
						light_data.color.get("b", 0.8),
						light_data.color.get("a", 0.8)
					)
				
				var intensity = light_data.get("intensity", 1.0)
				
				create_light(position, radius, color, intensity)
	
	# Regenerate light mask
	_generate_light_mask()
