extends Node
class_name ZoneManager

# Zone types
enum ZoneType {
	INTERIOR,
	MAINTENANCE,
	EXTERIOR
}

# Atmosphere properties
const FULL_PRESSURE = 100.0
const NO_PRESSURE = 0.0

# Temperature values
const NORMAL_TEMP = 20.0  # Celsius
const EXTERIOR_TEMP = -270.0  # Space temperature

# Structure for zone data
class ZoneData:
	var id: int
	var type: int = ZoneType.INTERIOR
	var name: String = "Zone"
	var has_gravity: bool = true
	var has_atmosphere: bool = true
	var pressure: float = FULL_PRESSURE
	var temperature: float = NORMAL_TEMP
	var tiles: Array = []  # Array of Vector2i positions
	var connected_zones: Array = []  # Array of zone IDs

	func _init(p_id: int, p_type: int, p_name: String = ""):
		id = p_id
		type = p_type
		name = p_name if p_name != "" else "Zone " + str(id)
		
		# Set defaults based on type
		match type:
			ZoneType.INTERIOR:
				has_gravity = true
				has_atmosphere = true
				pressure = FULL_PRESSURE
				temperature = NORMAL_TEMP
			ZoneType.MAINTENANCE:
				has_gravity = true
				has_atmosphere = true
				pressure = FULL_PRESSURE
				temperature = NORMAL_TEMP - 5.0
			ZoneType.EXTERIOR:
				has_gravity = false
				has_atmosphere = false
				pressure = NO_PRESSURE
				temperature = EXTERIOR_TEMP

# Stored zone data
var zones: Dictionary = {}  # Key: zone_id, Value: ZoneData
var next_zone_id: int = 1
var active_zone_id: int = -1
var active_zone_type: int = ZoneType.INTERIOR
var current_z_level: int = 0
var current_tool: String = "place"
var visualization_mode: int = -1  # -1 = off, 0 = type, 1 = pressure, etc.

# Reference to the editor and tilemaps
var editor_ref = null
var zone_tilemap: TileMap = null
var visualization_layer: CanvasLayer = null
var visualization_node: Node2D = null

# Atmosphere simulation
var atmosphere_simulation_active: bool = false
var simulation_tick: float = 0.0
var simulation_tick_rate: float = 0.5  # Seconds between simulation steps

func _init(p_editor_ref = null, p_zone_tilemap = null):
	editor_ref = p_editor_ref
	zone_tilemap = p_zone_tilemap

func _ready():
	# Create visualization layer if it doesn't exist
	if editor_ref:
		visualization_layer = editor_ref.get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport/VisualizationLayer")
		
		if not visualization_layer:
			visualization_layer = CanvasLayer.new()
			visualization_layer.name = "VisualizationLayer"
			visualization_layer.layer = 10  # Above normal content
			
			if editor_ref.has_node("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport"):
				editor_ref.get_node("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport").add_child(visualization_layer)
		
		# Create visualization node
		visualization_node = Node2D.new()
		visualization_node.name = "ZoneVisualization"
		visualization_node.visible = false
		visualization_layer.add_child(visualization_node)
		
		# Set up visualization script
		_setup_visualization_script()

func _process(delta: float):
	if atmosphere_simulation_active:
		simulation_tick += delta
		if simulation_tick >= simulation_tick_rate:
			simulation_tick = 0.0
			_simulate_atmosphere_step()

# Set up visualization script
func _setup_visualization_script():
	if not visualization_node:
		return
	
	var script = GDScript.new()
	script.source_code = """
	extends Node2D
	
	var zones = {}  # Reference to zone data
	var current_mode = 0
	var cell_size = 32
	var overlay_opacity = 0.3
	
	func _draw():
		if zones.size() == 0:
			return
		
		# Draw each zone based on visualization mode
		for zone_id in zones:
			var zone = zones[zone_id]
			var color = _get_zone_color(zone)
			
			# Draw each tile in the zone
			for pos in zone.tiles:
				var rect = Rect2(
					pos.x * cell_size, 
					pos.y * cell_size, 
					cell_size, 
					cell_size
				)
				draw_rect(rect, color, true)
				
				# Draw outline to make tiles more visible
				var outline_color = color
				outline_color.a = min(color.a + 0.1, 1.0)
				draw_rect(rect, outline_color, false)
	
	func _get_zone_color(zone) -> Color:
		var color = Color.WHITE
		
		match current_mode:
			0:  # Zone Type
				match zone.type:
					0:  # INTERIOR
						color = Color(0.0, 0.6, 1.0, overlay_opacity)  # Blue
					1:  # MAINTENANCE
						color = Color(1.0, 0.6, 0.0, overlay_opacity)  # Orange
					2:  # EXTERIOR
						color = Color(0.7, 0.0, 0.7, overlay_opacity)  # Purple
			
			1:  # Pressure
				var pressure_ratio = zone.pressure / FULL_PRESSURE
				color = Color(1.0 - pressure_ratio, pressure_ratio, 0.0, overlay_opacity)
			
			2:  # Temperature
				var temp_range = 50.0  # Range from -30 to 20
				var normalized_temp = (zone.temperature + 30.0) / temp_range
				normalized_temp = clamp(normalized_temp, 0.0, 1.0)
				color = Color(normalized_temp, 0.0, 1.0 - normalized_temp, overlay_opacity)
			
			3:  # Atmosphere
				if zone.has_atmosphere:
					color = Color(0.0, 0.8, 0.2, overlay_opacity)  # Green
				else:
					color = Color(0.8, 0.0, 0.2, overlay_opacity)  # Red
			
			4:  # Gravity
				if zone.has_gravity:
					color = Color(0.8, 0.8, 0.2, overlay_opacity)  # Yellow
				else:
					color = Color(0.2, 0.2, 0.8, overlay_opacity)  # Blue
		
		return color
	
	func update_visualization(p_zones: Dictionary, mode: int, p_cell_size: int, p_opacity: float):
		zones = p_zones
		current_mode = mode
		cell_size = p_cell_size
		overlay_opacity = p_opacity
		queue_redraw()
	"""
	
	script.reload()
	visualization_node.set_script(script)

# Create a new zone
func create_zone(type: int, name: String = "") -> int:
	var zone = ZoneData.new(next_zone_id, type, name)
	zones[next_zone_id] = zone
	var zone_id = next_zone_id
	next_zone_id += 1
	active_zone_id = zone_id
	
	# Update zone lists in the UI
	_update_zone_list_ui()
	
	return zone_id

# Delete a zone
func delete_zone(zone_id: int) -> bool:
	if zone_id in zones:
		# Clear all tiles in this zone
		var zone = zones[zone_id]
		for pos in zone.tiles:
			zone_tilemap.set_cell(0, pos, -1)
		
		# Remove connections to this zone
		for other_zone_id in zones:
			if other_zone_id != zone_id:
				var other_zone = zones[other_zone_id]
				other_zone.connected_zones.erase(zone_id)
		
		# Delete the zone
		zones.erase(zone_id)
		
		# Reset active zone if needed
		if active_zone_id == zone_id:
			active_zone_id = -1
			if zones.size() > 0:
				active_zone_id = zones.keys()[0]
		
		# Update zone lists in the UI
		_update_zone_list_ui()
		
		# Update visualization
		_update_visualization()
		
		return true
	return false

# Add a tile to a zone
func add_tile_to_zone(zone_id: int, position: Vector2i) -> bool:
	if zone_id in zones:
		var zone = zones[zone_id]
		
		# Check if tile is already in a zone
		for other_zone_id in zones:
			var other_zone = zones[other_zone_id]
			if position in other_zone.tiles and other_zone_id != zone_id:
				other_zone.tiles.erase(position)
				
				# Update other zone connections
				_update_zone_connections(other_zone_id)
		
		# Add to zone if not already there
		if not position in zone.tiles:
			zone.tiles.append(position)
			
			# Set the tile in the zone tilemap
			var atlas_coords = _get_atlas_coords_for_zone_type(zone.type)
			zone_tilemap.set_cell(0, position, 0, atlas_coords)
			
			# Update zone connections
			_update_zone_connections(zone_id)
			
			# Update visualization
			_update_visualization()
			
			return true
	return false

# Add a rectangle of tiles to a zone
func add_rect_to_zone(zone_id: int, start: Vector2i, end: Vector2i) -> bool:
	if zone_id in zones:
		var min_x = min(start.x, end.x)
		var max_x = max(start.x, end.x)
		var min_y = min(start.y, end.y)
		var max_y = max(start.y, end.y)
		
		for x in range(min_x, max_x + 1):
			for y in range(min_y, max_y + 1):
				add_tile_to_zone(zone_id, Vector2i(x, y))
				
		return true
	return false

# Fill an area with zone tiles
func fill_area(zone_id: int, position: Vector2i) -> bool:
	if zone_id in zones and zone_tilemap != null:
		var fill_positions = []
		var checked_positions = {}
		var queue = [position]
		
		# Get the target source_id and coords to replace
		var start_source_id = zone_tilemap.get_cell_source_id(0, position)
		var start_atlas_coords = Vector2i(-1, -1)
		if start_source_id != -1:
			start_atlas_coords = zone_tilemap.get_cell_atlas_coords(0, position)
		
		while not queue.is_empty():
			var current = queue.pop_front()
			
			# Skip if already checked
			if current in checked_positions:
				continue
				
			checked_positions[current] = true
			
			# Check if cell matches what we're replacing
			var current_source_id = zone_tilemap.get_cell_source_id(0, current)
			var matches = false
			
			if current_source_id == -1 and start_source_id == -1:
				matches = true
			elif current_source_id != -1 and start_source_id != -1:
				var current_atlas_coords = zone_tilemap.get_cell_atlas_coords(0, current)
				matches = current_atlas_coords == start_atlas_coords
			
			if matches:
				fill_positions.append(current)
				
				# Add neighbors to queue
				queue.append(Vector2i(current.x + 1, current.y))
				queue.append(Vector2i(current.x - 1, current.y))
				queue.append(Vector2i(current.x, current.y + 1))
				queue.append(Vector2i(current.x, current.y - 1))
		
		# Apply the zone to all matched positions
		for pos in fill_positions:
			add_tile_to_zone(zone_id, pos)
			
		return true
	return false

# Remove a tile from a zone
func remove_tile_from_zone(position: Vector2i) -> bool:
	for zone_id in zones:
		var zone = zones[zone_id]
		if position in zone.tiles:
			zone.tiles.erase(position)
			zone_tilemap.set_cell(0, position, -1)
			
			# Update zone connections
			_update_zone_connections(zone_id)
			
			# Update visualization
			_update_visualization()
			
			return true
	return false

# Update zone connections based on adjacency
func _update_zone_connections(zone_id: int):
	if not zone_id in zones:
		return
	
	var zone = zones[zone_id]
	
	# Clear existing connections
	zone.connected_zones.clear()
	
	# Check for adjacent zones
	for tile in zone.tiles:
		var adjacent_positions = [
			Vector2i(tile.x + 1, tile.y),
			Vector2i(tile.x - 1, tile.y),
			Vector2i(tile.x, tile.y + 1),
			Vector2i(tile.x, tile.y - 1)
		]
		
		for adj_pos in adjacent_positions:
			var adj_zone_id = get_zone_at_position(adj_pos)
			if adj_zone_id != -1 and adj_zone_id != zone_id:
				# Check if wall exists between zones
				var has_wall = false
				if editor_ref and editor_ref.wall_tilemap:
					var wall_source_id = editor_ref.wall_tilemap.get_cell_source_id(0, tile)
					has_wall = wall_source_id != -1
				
				# If no wall exists, zones are connected
				if not has_wall and not adj_zone_id in zone.connected_zones:
					zone.connected_zones.append(adj_zone_id)
					
					# Also connect the other zone to this one
					var adj_zone = zones[adj_zone_id]
					if not zone_id in adj_zone.connected_zones:
						adj_zone.connected_zones.append(zone_id)

# Connect two zones (for atmosphere flow)
func connect_zones(zone_id1: int, zone_id2: int) -> bool:
	if zone_id1 in zones and zone_id2 in zones and zone_id1 != zone_id2:
		var zone1 = zones[zone_id1]
		var zone2 = zones[zone_id2]
		
		if not zone_id2 in zone1.connected_zones:
			zone1.connected_zones.append(zone_id2)
		
		if not zone_id1 in zone2.connected_zones:
			zone2.connected_zones.append(zone_id1)
			
		return true
	return false

# Disconnect two zones
func disconnect_zones(zone_id1: int, zone_id2: int) -> bool:
	if zone_id1 in zones and zone_id2 in zones:
		var zone1 = zones[zone_id1]
		var zone2 = zones[zone_id2]
		
		zone1.connected_zones.erase(zone_id2)
		zone2.connected_zones.erase(zone_id1)
		
		return true
	return false

# Get zone at position
func get_zone_at_position(position: Vector2i) -> int:
	for zone_id in zones:
		var zone = zones[zone_id]
		if position in zone.tiles:
			return zone_id
	return -1

# Set active zone for editing
func set_active_zone(zone_id: int) -> bool:
	if zone_id in zones or zone_id == -1:
		active_zone_id = zone_id
		
		# Update UI
		_update_zone_ui()
		
		return true
	return false

# Get active zone
func get_active_zone() -> int:
	return active_zone_id

# Set active zone type
func set_active_zone_type(type: int):
	active_zone_type = type

# Set current tool
func set_current_tool(tool_name: String):
	current_tool = tool_name
	
	# Update tool UI
	_update_tool_ui()

# Set current z-level
func set_current_z_level(z_level: int):
	current_z_level = z_level

# Set visualization mode
func set_visualization_mode(mode: int):
	visualization_mode = mode
	
	# Update visualization
	if visualization_node:
		visualization_node.visible = (mode >= 0)
		
		if mode >= 0:
			_update_visualization()

# Get atlas coordinates for a zone type
func _get_atlas_coords_for_zone_type(type: int) -> Vector2i:
	match type:
		ZoneType.INTERIOR:
			return Vector2i(0, 0)
		ZoneType.MAINTENANCE:
			return Vector2i(1, 0)
		ZoneType.EXTERIOR:
			return Vector2i(2, 0)
		_:
			return Vector2i(0, 0)

# Start atmosphere simulation
func start_atmosphere_simulation():
	atmosphere_simulation_active = true
	simulation_tick = 0.0
	
	# Set initial conditions based on zone types
	for zone_id in zones:
		var zone = zones[zone_id]
		match zone.type:
			ZoneType.INTERIOR:
				zone.pressure = FULL_PRESSURE
				zone.temperature = NORMAL_TEMP
			ZoneType.MAINTENANCE:
				zone.pressure = FULL_PRESSURE
				zone.temperature = NORMAL_TEMP - 5.0
			ZoneType.EXTERIOR:
				zone.pressure = NO_PRESSURE
				zone.temperature = EXTERIOR_TEMP
	
	# Update visualization
	_update_visualization()

# Stop atmosphere simulation
func stop_atmosphere_simulation():
	atmosphere_simulation_active = false

# Simulate atmosphere flow step
func _simulate_atmosphere_step():
	# For each connected zone pair, equalize pressure
	var pressure_changes = {}
	var temperature_changes = {}
	
	# Initialize change maps
	for zone_id in zones:
		pressure_changes[zone_id] = 0.0
		temperature_changes[zone_id] = 0.0
	
	# Calculate pressure and temperature exchanges
	for zone_id in zones:
		var zone = zones[zone_id]
		
		for connected_id in zone.connected_zones:
			if connected_id in zones:
				var connected_zone = zones[connected_id]
				
				# Pressure flow proportional to difference
				var pressure_diff = zone.pressure - connected_zone.pressure
				var flow_amount = pressure_diff * 0.1  # 10% transfer per step
				
				pressure_changes[zone_id] -= flow_amount
				pressure_changes[connected_id] += flow_amount
				
				# Temperature exchange (only if there's atmosphere)
				if zone.pressure > 0 and connected_zone.pressure > 0:
					var temp_diff = zone.temperature - connected_zone.temperature
					var temp_flow = temp_diff * 0.05  # 5% transfer per step
					
					temperature_changes[zone_id] -= temp_flow
					temperature_changes[connected_id] += temp_flow
	
	# Apply the changes
	for zone_id in zones:
		var zone = zones[zone_id]
		
		zone.pressure += pressure_changes[zone_id]
		zone.temperature += temperature_changes[zone_id]
		
		# Clamp values to valid ranges
		zone.pressure = clamp(zone.pressure, NO_PRESSURE, FULL_PRESSURE)
		zone.temperature = clamp(zone.temperature, EXTERIOR_TEMP, NORMAL_TEMP + 30.0)  # Allow overheating
		
		# Update atmosphere status based on pressure
		zone.has_atmosphere = zone.pressure > 5.0  # Very low pressure = no atmosphere
	
	# Update visualization if active
	if visualization_mode >= 0:
		_update_visualization()

# Update visualization
func _update_visualization():
	if not visualization_node or visualization_mode < 0:
		return
	
	var cell_size = 32
	if editor_ref and editor_ref.has_method("get_cell_size"):
		cell_size = editor_ref.get_cell_size()
	
	var opacity = 0.3
	if editor_ref and editor_ref.settings_manager:
		opacity = editor_ref.settings_manager.get_setting("atmosphere/zone_overlay_opacity", 0.3)
	
	visualization_node.update_visualization(zones, visualization_mode, cell_size, opacity)

# Get visualization data for a position
func get_visualization_data(position: Vector2i) -> Dictionary:
	var zone_id = get_zone_at_position(position)
	
	if zone_id != -1 and zone_id in zones:
		var zone = zones[zone_id]
		return {
			"zone_id": zone_id,
			"zone_name": zone.name,
			"zone_type": zone.type,
			"has_gravity": zone.has_gravity,
			"has_atmosphere": zone.has_atmosphere,
			"pressure": zone.pressure,
			"temperature": zone.temperature
		}
	
	# Default values for unzoned areas
	return {
		"zone_id": -1,
		"zone_name": "Unzoned",
		"zone_type": -1,
		"has_gravity": false,
		"has_atmosphere": false,
		"pressure": NO_PRESSURE,
		"temperature": EXTERIOR_TEMP
	}

# Find breach points between zones
func find_breach_points() -> Array:
	var breach_points = []
	
	# For each zone, check its edges against other zones
	for zone_id in zones:
		var zone = zones[zone_id]
		
		# Skip exterior zones - they're supposed to be vacuum
		if zone.type == ZoneType.EXTERIOR:
			continue
			
		for pos in zone.tiles:
			# Check the 4 adjacent tiles
			var adjacents = [
				Vector2i(pos.x + 1, pos.y),
				Vector2i(pos.x - 1, pos.y),
				Vector2i(pos.x, pos.y + 1),
				Vector2i(pos.x, pos.y - 1)
			]
			
			for adj_pos in adjacents:
				var adj_zone_id = get_zone_at_position(adj_pos)
				
				# If adjacent tile is in a different zone
				if adj_zone_id != -1 and adj_zone_id != zone_id:
					var adj_zone = zones[adj_zone_id]
					
					# Check if zones have different atmosphere states
					if zone.has_atmosphere != adj_zone.has_atmosphere:
						# Check if there's a wall between them
						var has_wall = false
						if editor_ref and editor_ref.wall_tilemap:
							var wall_source_id = editor_ref.wall_tilemap.get_cell_source_id(0, pos)
							has_wall = wall_source_id != -1
							
						# If no wall and different atmospheres, it's a breach
						if not has_wall:
							breach_points.append({
								"position": pos,
								"from_zone": zone_id,
								"to_zone": adj_zone_id
							})
	
	return breach_points

# Update zone list in UI
func _update_zone_list_ui():
	if not editor_ref:
		return
	
	var zone_list = editor_ref.get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/SidePanel/ToolTabs/ZoneTab/ZoneList/ItemList")
	if not zone_list:
		return
	
	# Clear existing items
	zone_list.clear()
	
	# Add zones
	for zone_id in zones:
		var zone = zones[zone_id]
		var type_name = ""
		match zone.type:
			ZoneType.INTERIOR: type_name = "Interior"
			ZoneType.MAINTENANCE: type_name = "Maintenance"
			ZoneType.EXTERIOR: type_name = "Exterior"
		
		zone_list.add_item(zone.name + " (" + type_name + ")", null, false)
		zone_list.set_item_metadata(zone_list.get_item_count() - 1, zone_id)
	
	# Connect selection signal if not already connected
	if not zone_list.is_connected("item_selected", Callable(self, "_on_zone_list_item_selected")):
		zone_list.connect("item_selected", Callable(self, "_on_zone_list_item_selected"))
	
	# Connect UI buttons if not already connected
	var create_button = editor_ref.get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/SidePanel/ToolTabs/ZoneTab/ZoneList/ButtonContainer/CreateButton")
	var delete_button = editor_ref.get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/SidePanel/ToolTabs/ZoneTab/ZoneList/ButtonContainer/DeleteButton")
	
	if create_button and not create_button.is_connected("pressed", Callable(self, "_on_create_zone_pressed")):
		create_button.connect("pressed", Callable(self, "_on_create_zone_pressed"))
	
	if delete_button and not delete_button.is_connected("pressed", Callable(self, "_on_delete_zone_pressed")):
		delete_button.connect("pressed", Callable(self, "_on_delete_zone_pressed"))

# Update zone UI
func _update_zone_ui():
	if not editor_ref:
		return
	
	var zone_props = editor_ref.get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/SidePanel/ToolTabs/ZoneTab/ZoneProperties")
	if not zone_props:
		return
	
	var name_edit = zone_props.get_node_or_null("GridContainer/NameEdit")
	var type_select = zone_props.get_node_or_null("GridContainer/TypeSelect")
	var gravity_check = zone_props.get_node_or_null("GridContainer/GravityCheck")
	var atmosphere_check = zone_props.get_node_or_null("GridContainer/AtmosphereCheck")
	var pressure_slider = zone_props.get_node_or_null("GridContainer/PressureSlider")
	var temperature_box = zone_props.get_node_or_null("GridContainer/TemperatureSpinBox")
	
	if active_zone_id == -1 or not active_zone_id in zones:
		# Disable controls
		if name_edit: name_edit.editable = false
		if type_select: type_select.disabled = true
		if gravity_check: gravity_check.disabled = true
		if atmosphere_check: atmosphere_check.disabled = true
		if pressure_slider: pressure_slider.editable = false
		if temperature_box: temperature_box.editable = false
		return
	
	# Enable controls
	if name_edit: name_edit.editable = true
	if type_select: type_select.disabled = false
	if gravity_check: gravity_check.disabled = false
	if atmosphere_check: atmosphere_check.disabled = false
	if pressure_slider: pressure_slider.editable = true
	if temperature_box: temperature_box.editable = true
	
	# Set values from active zone
	var zone = zones[active_zone_id]
	
	if name_edit:
		name_edit.text = zone.name
		if not name_edit.is_connected("text_changed", Callable(self, "_on_zone_name_changed")):
			name_edit.connect("text_changed", Callable(self, "_on_zone_name_changed"))
	
	if type_select:
		type_select.selected = zone.type
		if not type_select.is_connected("item_selected", Callable(self, "_on_zone_type_changed")):
			type_select.connect("item_selected", Callable(self, "_on_zone_type_changed"))
	
	if gravity_check:
		gravity_check.button_pressed = zone.has_gravity
		if not gravity_check.is_connected("toggled", Callable(self, "_on_zone_gravity_toggled")):
			gravity_check.connect("toggled", Callable(self, "_on_zone_gravity_toggled"))
	
	if atmosphere_check:
		atmosphere_check.button_pressed = zone.has_atmosphere
		if not atmosphere_check.is_connected("toggled", Callable(self, "_on_zone_atmosphere_toggled")):
			atmosphere_check.connect("toggled", Callable(self, "_on_zone_atmosphere_toggled"))
	
	if pressure_slider:
		pressure_slider.value = zone.pressure
		if not pressure_slider.is_connected("value_changed", Callable(self, "_on_zone_pressure_changed")):
			pressure_slider.connect("value_changed", Callable(self, "_on_zone_pressure_changed"))
	
	if temperature_box:
		temperature_box.value = zone.temperature
		if not temperature_box.is_connected("value_changed", Callable(self, "_on_zone_temperature_changed")):
			temperature_box.connect("value_changed", Callable(self, "_on_zone_temperature_changed"))

# Update tool UI
func _update_tool_ui():
	if not editor_ref:
		return
	
	# Update zone toolbar buttons
	var place_button = editor_ref.get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/ZoneToolsSection/PlaceZoneButton")
	var fill_button = editor_ref.get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/ZoneToolsSection/FillZoneButton")
	var rect_button = editor_ref.get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/ZoneToolsSection/RectZoneButton")
	var erase_button = editor_ref.get_node_or_null("UI/MainPanel/VBoxContainer/ToolbarScroll/Toolbar/ZoneToolsSection/EraseZoneButton")
	
	if place_button: place_button.button_pressed = (current_tool == "place")
	if fill_button: fill_button.button_pressed = (current_tool == "fill")
	if rect_button: rect_button.button_pressed = (current_tool == "rect")
	if erase_button: erase_button.button_pressed = (current_tool == "erase")

# Zone list handlers
func _on_zone_list_item_selected(index: int):
	var zone_list = editor_ref.get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/SidePanel/ToolTabs/ZoneTab/ZoneList/ItemList")
	if zone_list:
		var zone_id = zone_list.get_item_metadata(index)
		set_active_zone(zone_id)

func _on_create_zone_pressed():
	# Use active zone type
	create_zone(active_zone_type, "New Zone")

func _on_delete_zone_pressed():
	if active_zone_id != -1:
		delete_zone(active_zone_id)

# Zone property handlers
func _on_zone_name_changed(new_text: String):
	if active_zone_id != -1 and active_zone_id in zones:
		zones[active_zone_id].name = new_text
		_update_zone_list_ui()

func _on_zone_type_changed(index: int):
	if active_zone_id != -1 and active_zone_id in zones:
		zones[active_zone_id].type = index
		
		# Update tiles for this zone
		var zone = zones[active_zone_id]
		var atlas_coords = _get_atlas_coords_for_zone_type(zone.type)
		
		for pos in zone.tiles:
			zone_tilemap.set_cell(0, pos, 0, atlas_coords)
		
		# Update defaults based on new type
		match index:
			ZoneType.INTERIOR:
				zones[active_zone_id].has_gravity = true
				zones[active_zone_id].has_atmosphere = true
				zones[active_zone_id].pressure = FULL_PRESSURE
				zones[active_zone_id].temperature = NORMAL_TEMP
			ZoneType.MAINTENANCE:
				zones[active_zone_id].has_gravity = true
				zones[active_zone_id].has_atmosphere = true
				zones[active_zone_id].pressure = FULL_PRESSURE
				zones[active_zone_id].temperature = NORMAL_TEMP - 5.0
			ZoneType.EXTERIOR:
				zones[active_zone_id].has_gravity = false
				zones[active_zone_id].has_atmosphere = false
				zones[active_zone_id].pressure = NO_PRESSURE
				zones[active_zone_id].temperature = EXTERIOR_TEMP
		
		# Update zone UI
		_update_zone_ui()
		
		# Update visualization
		_update_visualization()

func _on_zone_gravity_toggled(toggled: bool):
	if active_zone_id != -1 and active_zone_id in zones:
		zones[active_zone_id].has_gravity = toggled
		
		# Update visualization
		_update_visualization()

func _on_zone_atmosphere_toggled(toggled: bool):
	if active_zone_id != -1 and active_zone_id in zones:
		zones[active_zone_id].has_atmosphere = toggled
		
		# If turning atmosphere off, set pressure to zero
		if not toggled:
			zones[active_zone_id].pressure = NO_PRESSURE
			
			var pressure_slider = editor_ref.get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/SidePanel/ToolTabs/ZoneTab/ZoneProperties/GridContainer/PressureSlider")
			if pressure_slider:
				pressure_slider.value = NO_PRESSURE
		
		# Update visualization
		_update_visualization()

func _on_zone_pressure_changed(value: float):
	if active_zone_id != -1 and active_zone_id in zones:
		zones[active_zone_id].pressure = value
		
		# If pressure is zero, atmosphere is effectively off
		if value <= 0.1:
			zones[active_zone_id].has_atmosphere = false
			
			var atmosphere_check = editor_ref.get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/SidePanel/ToolTabs/ZoneTab/ZoneProperties/GridContainer/AtmosphereCheck")
			if atmosphere_check:
				atmosphere_check.button_pressed = false
		else:
			zones[active_zone_id].has_atmosphere = true
			
			var atmosphere_check = editor_ref.get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/SidePanel/ToolTabs/ZoneTab/ZoneProperties/GridContainer/AtmosphereCheck")
			if atmosphere_check:
				atmosphere_check.button_pressed = true
		
		# Update visualization
		_update_visualization()

func _on_zone_temperature_changed(value: float):
	if active_zone_id != -1 and active_zone_id in zones:
		zones[active_zone_id].temperature = value
		
		# Update visualization
		_update_visualization()

# Save zone data to a map file
func save_to_map_data(map_data: Dictionary):
	# Convert zone data to a serializable format
	var zone_data = {}
	
	for zone_id in zones:
		var zone = zones[zone_id]
		
		# Convert Vector2i positions to strings for JSON compatibility
		var tile_strings = []
		for pos in zone.tiles:
			tile_strings.append(str(pos.x) + "," + str(pos.y))
		
		zone_data[zone_id] = {
			"id": zone.id,
			"type": zone.type,
			"name": zone.name,
			"has_gravity": zone.has_gravity,
			"has_atmosphere": zone.has_atmosphere,
			"pressure": zone.pressure,
			"temperature": zone.temperature,
			"tiles": tile_strings,
			"connected_zones": zone.connected_zones.duplicate()
		}
	
	# Add to map data
	if not "metadata" in map_data:
		map_data["metadata"] = {}
	
	map_data.metadata["zones"] = zone_data
	map_data.metadata["next_zone_id"] = next_zone_id
	map_data.metadata["active_zone_id"] = active_zone_id

# Load zone data from map file
func load_from_map_data(map_data: Dictionary) -> bool:
	clear_zones()
	
	# Check if zone data exists
	if "metadata" in map_data and "zones" in map_data.metadata:
		var zone_data = map_data.metadata["zones"]
		
		for zone_id_str in zone_data:
			var zone_id = int(zone_id_str)
			var data = zone_data[zone_id_str]
			
			# Create zone
			var zone = ZoneData.new(zone_id, data.type, data.name)
			zone.has_gravity = data.has_gravity
			zone.has_atmosphere = data.has_atmosphere
			zone.pressure = data.pressure
			zone.temperature = data.temperature
			
			# Parse tile positions
			for pos_str in data.tiles:
				var parts = pos_str.split(",")
				if parts.size() == 2:
					var pos = Vector2i(int(parts[0]), int(parts[1]))
					zone.tiles.append(pos)
					
					# Update tilemap
					var atlas_coords = _get_atlas_coords_for_zone_type(zone.type)
					zone_tilemap.set_cell(0, pos, 0, atlas_coords)
			
			# Parse connected zones
			zone.connected_zones = data.connected_zones.duplicate()
			
			# Add to zones dictionary
			zones[zone_id] = zone
		
		# Set next zone ID
		if "next_zone_id" in map_data.metadata:
			next_zone_id = map_data.metadata["next_zone_id"]
		else:
			# Find the highest ID and add 1
			next_zone_id = 1
			for zone_id in zones:
				next_zone_id = max(next_zone_id, zone_id + 1)
		
		# Set active zone
		if "active_zone_id" in map_data.metadata:
			active_zone_id = map_data.metadata["active_zone_id"]
		elif zones.size() > 0:
			active_zone_id = zones.keys()[0]
		
		# Update UI
		_update_zone_list_ui()
		_update_zone_ui()
		
		# Update visualization
		_update_visualization()
		
		return true
	
	return false

# Clear all zones
func clear_zones():
	zones.clear()
	next_zone_id = 1
	active_zone_id = -1
	
	# Clear zone tilemap
	if zone_tilemap:
		zone_tilemap.clear()
	
	# Update UI
	_update_zone_list_ui()
	_update_zone_ui()
	
	# Update visualization
	_update_visualization()
