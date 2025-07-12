extends Node
class_name PreviewMode

# Signals
signal preview_started
signal preview_stopped
signal player_moved(position)

# Player properties
const PLAYER_MOVE_SPEED = 5.0
var player_position = Vector2i(0, 0)
var player_direction = 0 # 0=North, 1=East, 2=South, 3=West
var player_sprite: Sprite2D = null

# Map references
var editor_ref = null
var floor_tilemap: TileMap = null
var wall_tilemap: TileMap = null
var objects_tilemap: TileMap = null
var object_container: Node2D = null
var zone_manager = null
var atmosphere_visualizer = null

# Preview state
var is_preview_active = false
var preview_container: Node2D = null
var debug_overlay: Control = null
var doors_state = {} # Tracks door open/close states

# Pathfinding
var astar = AStar2D.new()
var walkable_cells = []

func _init(p_editor_ref, p_preview_container = null):
	editor_ref = p_editor_ref
	
	# Get references
	if editor_ref:
		floor_tilemap = editor_ref.floor_tilemap
		wall_tilemap = editor_ref.wall_tilemap
		objects_tilemap = editor_ref.objects_tilemap
		
		# Try to get object container
		object_container = editor_ref.get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport/PlacedObjects")
		
		# Try to get zone manager
		if "zone_manager" in editor_ref:
			zone_manager = editor_ref.zone_manager
			
		# Try to get atmosphere visualizer
		if "atmosphere_visualizer" in editor_ref:
			atmosphere_visualizer = editor_ref.atmosphere_visualizer
	
	# Create or use preview container
	if p_preview_container:
		preview_container = p_preview_container
	else:
		preview_container = Node2D.new()
		preview_container.name = "PreviewContainer"
		preview_container.visible = false
		if editor_ref and editor_ref.has_node("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport"):
			editor_ref.get_node("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport").add_child(preview_container)
	
	# Set up input processing
	set_process_input(false)

func _process(delta):
	if is_preview_active and player_sprite:
		# Update interface with current info
		_update_debug_overlay()
		
		# Check for player interactions
		_check_interactions()

func _input(event):
	if not is_preview_active:
		return
		
	# Handle movement input
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_UP, KEY_W:
				_move_player(Vector2i(0, -1))
				player_direction = 0 # North
			KEY_RIGHT, KEY_D:
				_move_player(Vector2i(1, 0))
				player_direction = 1 # East
			KEY_DOWN, KEY_S:
				_move_player(Vector2i(0, 1))
				player_direction = 2 # South
			KEY_LEFT, KEY_A:
				_move_player(Vector2i(-1, 0))
				player_direction = 3 # West
			KEY_SPACE, KEY_E:
				_interact()
			KEY_ESCAPE:
				stop_preview()

# Start preview mode
func start_preview(start_position = null):
	if is_preview_active:
		return
	
	# Show preview container
	preview_container.visible = true
	
	# Build navigation grid
	_build_navigation()
	
	# Create debug overlay
	_create_debug_overlay()
	
	# Create player sprite
	_create_player()
	
	# Set player position
	if start_position:
		player_position = start_position
	else:
		player_position = _find_valid_start_position()
	
	# Position player sprite
	_update_player_position()
	
	# Record door states
	_record_door_states()
	
	# Enable input
	set_process_input(true)
	set_process(true)
	
	# Flag as active
	is_preview_active = true
	
	# Emit signal
	emit_signal("preview_started")

# Stop preview mode
func stop_preview():
	if not is_preview_active:
		return
	
	# Hide preview container
	preview_container.visible = false
	
	# Clean up player
	if player_sprite:
		player_sprite.queue_free()
		player_sprite = null
	
	# Clean up debug overlay
	if debug_overlay:
		debug_overlay.queue_free()
		debug_overlay = null
	
	# Reset door states
	_restore_door_states()
	
	# Disable input
	set_process_input(false)
	set_process(false)
	
	# Clear navigation
	astar.clear()
	walkable_cells.clear()
	
	# Flag as inactive
	is_preview_active = false
	
	# Emit signal
	emit_signal("preview_stopped")

# Create player sprite
func _create_player():
	player_sprite = Sprite2D.new()
	player_sprite.name = "PlayerSprite"
	
	# Create simple player texture
	var image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	
	# Draw player body
	for y in range(6, 26):
		for x in range(6, 26):
			var color = Color(0.2, 0.6, 1.0, 1.0)
			image.set_pixel(x, y, color)
	
	# Draw direction indicator
	for i in range(8):
		image.set_pixel(16 + i, 10, Color(1, 1, 1, 1))
		image.set_pixel(16 - i, 10, Color(1, 1, 1, 1))
	for i in range(6):
		image.set_pixel(16, 10 - i, Color(1, 1, 1, 1))
	
	# Create texture
	var texture = ImageTexture.create_from_image(image)
	player_sprite.texture = texture
	
	# Set center offset
	player_sprite.position = Vector2(16, 16)
	
	# Add to preview container
	preview_container.add_child(player_sprite)

# Create debug overlay
func _create_debug_overlay():
	debug_overlay = Control.new()
	debug_overlay.name = "DebugOverlay"
	debug_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Position at top-right
	debug_overlay.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	debug_overlay.position = Vector2(0, 10)
	
	# Create panel
	var panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_overlay.add_child(panel)
	
	# Add info container
	var vbox = VBoxContainer.new()
	panel.add_child(vbox)
	
	# Add labels
	var position_label = Label.new()
	position_label.name = "PositionLabel"
	position_label.text = "Position: (0, 0)"
	vbox.add_child(position_label)
	
	var zone_label = Label.new()
	zone_label.name = "ZoneLabel"
	zone_label.text = "Zone: None"
	vbox.add_child(zone_label)
	
	var atmos_label = Label.new()
	atmos_label.name = "AtmosLabel"
	atmos_label.text = "Atmos: None"
	vbox.add_child(atmos_label)
	
	var objects_label = Label.new()
	objects_label.name = "ObjectsLabel"
	objects_label.text = "Objects: None"
	vbox.add_child(objects_label)
	
	var help_label = Label.new()
	help_label.name = "HelpLabel"
	help_label.text = "WASD/Arrows: Move   E/Space: Interact   ESC: Exit"
	vbox.add_child(help_label)
	
	# Add to editor viewport
	if editor_ref and editor_ref.has_node("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport"):
		editor_ref.get_node("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport").add_child(debug_overlay)

# Update debug overlay information
func _update_debug_overlay():
	if not debug_overlay:
		return
	
	# Update position
	var pos_label = debug_overlay.get_node_or_null("PanelContainer/VBoxContainer/PositionLabel")
	if pos_label:
		pos_label.text = "Position: (%d, %d)" % [player_position.x, player_position.y]
	
	# Update zone
	var zone_label = debug_overlay.get_node_or_null("PanelContainer/VBoxContainer/ZoneLabel")
	if zone_label and zone_manager:
		var zone_id = zone_manager.get_zone_at_position(player_position)
		if zone_id != -1:
			var zone = zone_manager.zones[zone_id]
			zone_label.text = "Zone: %s" % zone.name
		else:
			zone_label.text = "Zone: None"
	
	# Update atmosphere
	var atmos_label = debug_overlay.get_node_or_null("PanelContainer/VBoxContainer/AtmosLabel")
	if atmos_label and zone_manager:
		var zone_id = zone_manager.get_zone_at_position(player_position)
		if zone_id != -1:
			var zone = zone_manager.zones[zone_id]
			atmos_label.text = "Atmos: %d%% (%d°C)" % [zone.pressure, zone.temperature]
		else:
			atmos_label.text = "Atmos: None"
	
	# Update objects
	var objects_label = debug_overlay.get_node_or_null("PanelContainer/VBoxContainer/ObjectsLabel")
	if objects_label:
		var obj_names = _get_objects_at_position(player_position)
		if obj_names.size() > 0:
			objects_label.text = "Objects: %s" % ", ".join(obj_names)
		else:
			objects_label.text = "Objects: None"

# Build navigation grid
func _build_navigation():
	astar.clear()
	walkable_cells.clear()
	
	if not floor_tilemap or not wall_tilemap or not objects_tilemap:
		return
	
	# Get all floor cells
	var floor_cells = floor_tilemap.get_used_cells(0)
	
	# Check each floor cell for walls and objects
	for cell in floor_cells:
		var wall_id = wall_tilemap.get_cell_source_id(0, cell)
		var obj_id = objects_tilemap.get_cell_source_id(0, cell)
		
		# Check if there's a blocking wall or object
		var is_blocked = (wall_id != -1)
		
		# Check objects if unblocked by walls
		if not is_blocked and obj_id != -1:
			# Check if it's a door (doors are special - they can be passed through)
			var is_door = false
			var atlas_coords = objects_tilemap.get_cell_atlas_coords(0, cell)
			
			for type_id in TileDefinitions.OBJECT_TYPES:
				if "door" in type_id.to_lower():
					var data = TileDefinitions.OBJECT_TYPES[type_id]
					if data.atlas_coords == atlas_coords:
						is_door = true
						break
			
			# Block if not a door
			if not is_door:
				is_blocked = true
		
		# Check for placed objects that block movement
		if not is_blocked and object_container:
			for obj in object_container.get_children():
				if obj.name.begins_with("NetworkConnection_"):
					continue  # Skip network connections
				
				if _object_blocks_position(obj, cell):
					is_blocked = true
					break
		
		# If not blocked, add to walkable cells
		if not is_blocked:
			walkable_cells.append(cell)
			var id = _point_id(cell)
			astar.add_point(id, Vector2(cell.x, cell.y))
	
	# Connect adjacent walkable cells
	for cell in walkable_cells:
		var id = _point_id(cell)
		
		# Connect to adjacent cells
		var neighbors = [
			Vector2i(cell.x + 1, cell.y),
			Vector2i(cell.x - 1, cell.y),
			Vector2i(cell.x, cell.y + 1),
			Vector2i(cell.x, cell.y - 1)
		]
		
		for neighbor in neighbors:
			if neighbor in walkable_cells:
				var neighbor_id = _point_id(neighbor)
				if not astar.are_points_connected(id, neighbor_id):
					astar.connect_points(id, neighbor_id)

# Check if object blocks movement at position
func _object_blocks_position(obj: Node, position: Vector2i) -> bool:
	# Skip non-blocking objects
	if obj.get_meta("preview_non_blocking", false):
		return false
	
	# Get object grid position
	var obj_pos = obj.get_meta("grid_position", Vector2i.ZERO)
	
	# Check if it's a multi-tile object
	if obj.get_meta("multi_tile", false):
		var width = obj.get_meta("multi_tile_width", 1)
		var height = obj.get_meta("multi_tile_height", 1)
		
		# Check if position is within object bounds
		if position.x >= obj_pos.x and position.x < obj_pos.x + width and \
		   position.y >= obj_pos.y and position.y < obj_pos.y + height:
			return true
	else:
		# Single-tile object
		return position == obj_pos
	
	return false

# Get unique ID for a grid position
func _point_id(point: Vector2i) -> int:
	# Convert 2D position to unique 1D ID
	return point.y * 100000 + point.x

# Find a valid starting position
func _find_valid_start_position() -> Vector2i:
	if walkable_cells.size() > 0:
		# Start at the first walkable cell
		return walkable_cells[0]
	
	# Fallback
	return Vector2i(0, 0)

# Move player in direction
func _move_player(direction: Vector2i):
	# Calculate target position
	var target = player_position + direction
	
	# Check if target is walkable
	if target in walkable_cells:
		# Update position
		player_position = target
		_update_player_position()
		
		# Emit signal
		emit_signal("player_moved", player_position)
		return true
	
	# Check if target is a door that can be opened
	if _is_door_at(target):
		# Try to open door
		if _toggle_door_at(target, true):  # True = open
			# Door opened, now we can move
			player_position = target
			_update_player_position()
			
			# Emit signal
			emit_signal("player_moved", player_position)
			return true
	
	return false

# Update player sprite position
func _update_player_position():
	if player_sprite:
		# Convert grid position to world position (center of cell)
		var world_pos = Vector2(player_position.x * 32 + 16, player_position.y * 32 + 16)
		player_sprite.global_position = world_pos
		
		# Update rotation based on direction
		player_sprite.rotation = PI/2 * player_direction

# Interact with objects
func _interact():
	# Check what's at current position
	var objects = _get_interactable_objects_at(player_position)
	
	if objects.size() > 0:
		# Interact with first object
		var obj = objects[0]
		
		# Check object type
		var obj_type = obj.get_meta("object_type", "")
		
		# Handle different object types
		if "door" in obj_type.to_lower():
			# Toggle door state
			_toggle_door(obj)
			return true
		elif "computer" in obj_type.to_lower():
			# Show computer interface
			_show_computer_interface(obj)
			return true
		elif "switch" in obj_type.to_lower():
			# Toggle switch
			_toggle_switch(obj)
			return true
		elif obj.has_method("interact"):
			# Call custom interact method
			obj.interact()
			return true
	
	# Check adjacent tiles
	var adjacent = [
		Vector2i(player_position.x + 1, player_position.y),
		Vector2i(player_position.x - 1, player_position.y),
		Vector2i(player_position.x, player_position.y + 1),
		Vector2i(player_position.x, player_position.y - 1)
	]
	
	for pos in adjacent:
		objects = _get_interactable_objects_at(pos)
		
		if objects.size() > 0:
			# Interact with first object
			var obj = objects[0]
			
			# Check object type
			var obj_type = obj.get_meta("object_type", "")
			
			# Handle different object types
			if "door" in obj_type.to_lower():
				# Toggle door state
				_toggle_door(obj)
				return true
			elif obj.has_method("interact_from_adjacent"):
				# Call custom interact from adjacent method
				obj.interact_from_adjacent(player_position)
				return true
	
	return false

# Check for continual interactions
func _check_interactions():
	# Check for objects at player position that have continual effects
	var objects = _get_interactable_objects_at(player_position)
	
	for obj in objects:
		# Get object type
		var obj_type = obj.get_meta("object_type", "")
		
		# Check for objects with continual effects
		if "atmos" in obj_type.to_lower() and obj.has_method("continuous_interact"):
			obj.continuous_interact()

# Get objects at position
func _get_objects_at_position(position: Vector2i) -> Array:
	var result = []
	
	# Check tilemap objects
	if objects_tilemap:
		var obj_id = objects_tilemap.get_cell_source_id(0, position)
		if obj_id != -1:
			var atlas_coords = objects_tilemap.get_cell_atlas_coords(0, position)
			
			# Check object type based on atlas coords
			for type_id in TileDefinitions.OBJECT_TYPES:
				var data = TileDefinitions.OBJECT_TYPES[type_id]
				if data.atlas_coords == atlas_coords:
					result.append(type_id)
					break
	
	# Check placed objects
	if object_container:
		for obj in object_container.get_children():
			if obj.name.begins_with("NetworkConnection_"):
				continue  # Skip network connections
			
			# Get object position
			var obj_pos = obj.get_meta("grid_position", Vector2i.ZERO)
			
			# Check if it's a multi-tile object
			if obj.get_meta("multi_tile", false):
				var width = obj.get_meta("multi_tile_width", 1)
				var height = obj.get_meta("multi_tile_height", 1)
				
				# Check if position is within object bounds
				if position.x >= obj_pos.x and position.x < obj_pos.x + width and \
				   position.y >= obj_pos.y and position.y < obj_pos.y + height:
					result.append(obj.get_meta("object_type", "unknown"))
			else:
				# Single-tile object
				if position == obj_pos:
					result.append(obj.get_meta("object_type", "unknown"))
	
	return result

# Get interactable objects at position
func _get_interactable_objects_at(position: Vector2i) -> Array:
	var result = []
	
	# Check placed objects
	if object_container:
		for obj in object_container.get_children():
			if obj.name.begins_with("NetworkConnection_"):
				continue  # Skip network connections
			
			# Get object position
			var obj_pos = obj.get_meta("grid_position", Vector2i.ZERO)
			
			# Check if it's a multi-tile object
			if obj.get_meta("multi_tile", false):
				var width = obj.get_meta("multi_tile_width", 1)
				var height = obj.get_meta("multi_tile_height", 1)
				
				# Check if position is within object bounds
				if position.x >= obj_pos.x and position.x < obj_pos.x + width and \
				   position.y >= obj_pos.y and position.y < obj_pos.y + height:
					result.append(obj)
			else:
				# Single-tile object
				if position == obj_pos:
					result.append(obj)
	
	return result

# Check if there's a door at position
func _is_door_at(position: Vector2i) -> bool:
	# Check tilemap objects
	if objects_tilemap:
		var obj_id = objects_tilemap.get_cell_source_id(0, position)
		if obj_id != -1:
			var atlas_coords = objects_tilemap.get_cell_atlas_coords(0, position)
			
			# Check if it's a door based on atlas coords
			for type_id in TileDefinitions.OBJECT_TYPES:
				if "door" in type_id.to_lower():
					var data = TileDefinitions.OBJECT_TYPES[type_id]
					if data.atlas_coords == atlas_coords:
						return true
	
	# Check placed objects
	var objects = _get_interactable_objects_at(position)
	for obj in objects:
		var obj_type = obj.get_meta("object_type", "")
		if "door" in obj_type.to_lower():
			return true
	
	return false

# Toggle door state at position
func _toggle_door_at(position: Vector2i, open: bool) -> bool:
	# Check tilemap objects first
	if objects_tilemap:
		var obj_id = objects_tilemap.get_cell_source_id(0, position)
		if obj_id != -1:
			var atlas_coords = objects_tilemap.get_cell_atlas_coords(0, position)
			
			# Find the door type
			var door_closed_coords = null
			var door_open_coords = null
			
			for type_id in TileDefinitions.OBJECT_TYPES:
				if type_id == "door_closed":
					door_closed_coords = TileDefinitions.OBJECT_TYPES[type_id].atlas_coords
				elif type_id == "door_open":
					door_open_coords = TileDefinitions.OBJECT_TYPES[type_id].atlas_coords
			
			# If we found door coordinates
			if door_closed_coords != null and door_open_coords != null:
				# Toggle door state
				if open and atlas_coords == door_closed_coords:
					# Open door
					objects_tilemap.set_cell(0, position, obj_id, door_open_coords)
					
					# Update door state
					var door_key = "tilemap_door_%d_%d" % [position.x, position.y]
					doors_state[door_key] = {
						"position": position,
						"open": true,
						"tilemap": true
					}
					
					# Update navigation
					if not position in walkable_cells:
						walkable_cells.append(position)
						var id = _point_id(position)
						astar.add_point(id, Vector2(position.x, position.y))
						
						# Connect to adjacent walkable cells
						var neighbors = [
							Vector2i(position.x + 1, position.y),
							Vector2i(position.x - 1, position.y),
							Vector2i(position.x, position.y + 1),
							Vector2i(position.x, position.y - 1)
						]
						
						for neighbor in neighbors:
							if neighbor in walkable_cells:
								var neighbor_id = _point_id(neighbor)
								if not astar.are_points_connected(id, neighbor_id):
									astar.connect_points(id, neighbor_id)
					
					return true
				elif not open and atlas_coords == door_open_coords:
					# Close door
					objects_tilemap.set_cell(0, position, obj_id, door_closed_coords)
					
					# Update door state
					var door_key = "tilemap_door_%d_%d" % [position.x, position.y]
					doors_state[door_key] = {
						"position": position,
						"open": false,
						"tilemap": true
					}
					
					# Update navigation
					if position in walkable_cells:
						walkable_cells.erase(position)
						var id = _point_id(position)
						astar.remove_point(id)
					
					return true
	
	# Check placed objects
	var objects = _get_interactable_objects_at(position)
	for obj in objects:
		var obj_type = obj.get_meta("object_type", "")
		if "door" in obj_type.to_lower():
			# Handle door object
			if obj.has_method("set_open"):
				obj.set_open(open)
				
				# Update door state
				var door_key = "object_door_%s" % obj.name
				doors_state[door_key] = {
					"object": obj,
					"open": open,
					"tilemap": false
				}
				
				# Update navigation
				if open and not position in walkable_cells:
					walkable_cells.append(position)
					var id = _point_id(position)
					astar.add_point(id, Vector2(position.x, position.y))
					
					# Connect to adjacent walkable cells
					var neighbors = [
						Vector2i(position.x + 1, position.y),
						Vector2i(position.x - 1, position.y),
						Vector2i(position.x, position.y + 1),
						Vector2i(position.x, position.y - 1)
					]
					
					for neighbor in neighbors:
						if neighbor in walkable_cells:
							var neighbor_id = _point_id(neighbor)
							if not astar.are_points_connected(id, neighbor_id):
								astar.connect_points(id, neighbor_id)
				elif not open and position in walkable_cells:
					walkable_cells.erase(position)
					var id = _point_id(position)
					astar.remove_point(id)
				
				return true
	
	return false

# Toggle door object
func _toggle_door(door_obj):
	if door_obj.has_method("toggle"):
		# Toggle door state
		door_obj.toggle()
		
		# Update door state
		var door_key = "object_door_%s" % door_obj.name
		var is_open = door_obj.get_meta("is_open", false)
		doors_state[door_key] = {
			"object": door_obj,
			"open": is_open,
			"tilemap": false
		}
		
		# Update navigation
		var position = door_obj.get_meta("grid_position", Vector2i.ZERO)
		
		if is_open and not position in walkable_cells:
			walkable_cells.append(position)
			var id = _point_id(position)
			astar.add_point(id, Vector2(position.x, position.y))
			
			# Connect to adjacent walkable cells
			var neighbors = [
				Vector2i(position.x + 1, position.y),
				Vector2i(position.x - 1, position.y),
				Vector2i(position.x, position.y + 1),
				Vector2i(position.x, position.y - 1)
			]
			
			for neighbor in neighbors:
				if neighbor in walkable_cells:
					var neighbor_id = _point_id(neighbor)
					if not astar.are_points_connected(id, neighbor_id):
						astar.connect_points(id, neighbor_id)
		elif not is_open and position in walkable_cells:
			walkable_cells.erase(position)
			var id = _point_id(position)
			astar.remove_point(id)
		
		return true
	
	return false

# Toggle switch
func _toggle_switch(switch_obj):
	if switch_obj.has_method("toggle"):
		switch_obj.toggle()
		return true
	
	return false

# Show computer interface
func _show_computer_interface(computer_obj):
	if computer_obj.has_method("show_interface"):
		computer_obj.show_interface()
		return true
	
	return false

# Record current door states
func _record_door_states():
	doors_state.clear()
	
	# Record tilemap doors
	if objects_tilemap:
		for cell in objects_tilemap.get_used_cells(0):
			var obj_id = objects_tilemap.get_cell_source_id(0, cell)
			if obj_id != -1:
				var atlas_coords = objects_tilemap.get_cell_atlas_coords(0, cell)
				
				# Check if it's a door
				var is_door = false
				var is_open = false
				
				for type_id in TileDefinitions.OBJECT_TYPES:
					if type_id == "door_closed":
						if atlas_coords == TileDefinitions.OBJECT_TYPES[type_id].atlas_coords:
							is_door = true
							is_open = false
							break
					elif type_id == "door_open":
						if atlas_coords == TileDefinitions.OBJECT_TYPES[type_id].atlas_coords:
							is_door = true
							is_open = true
							break
				
				if is_door:
					var door_key = "tilemap_door_%d_%d" % [cell.x, cell.y]
					doors_state[door_key] = {
						"position": cell,
						"open": is_open,
						"tilemap": true,
						"original_state": is_open
					}
	
	# Record object doors
	if object_container:
		for obj in object_container.get_children():
			if obj.name.begins_with("NetworkConnection_"):
				continue  # Skip network connections
			
			var obj_type = obj.get_meta("object_type", "")
			if "door" in obj_type.to_lower():
				var is_open = obj.get_meta("is_open", false)
				
				var door_key = "object_door_%s" % obj.name
				doors_state[door_key] = {
					"object": obj,
					"open": is_open,
					"tilemap": false,
					"original_state": is_open
				}

# Restore original door states
func _restore_door_states():
	# Restore each door to its original state
	for door_key in doors_state:
		var data = doors_state[door_key]
		
		# Only restore if we have original state
		if "original_state" in data:
			if data.tilemap:
				# Restore tilemap door
				var position = data.position
				var open = data.original_state
				
				# Find door atlas coords
				var door_closed_coords = null
				var door_open_coords = null
				var obj_id = objects_tilemap.get_cell_source_id(0, position)
				
				for type_id in TileDefinitions.OBJECT_TYPES:
					if type_id == "door_closed":
						door_closed_coords = TileDefinitions.OBJECT_TYPES[type_id].atlas_coords
					elif type_id == "door_open":
						door_open_coords = TileDefinitions.OBJECT_TYPES[type_id].atlas_coords
				
				# Set appropriate door state
				if door_closed_coords != null and door_open_coords != null and obj_id != -1:
					var coords = door_open_coords if open else door_closed_coords
					objects_tilemap.set_cell(0, position, obj_id, coords)
			else:
				# Restore object door
				var obj = data.object
				var open = data.original_state
				
				if is_instance_valid(obj) and obj.has_method("set_open"):
					obj.set_open(open)
	
	# Clear door states
	doors_state.clear()
