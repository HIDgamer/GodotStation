extends Node
class_name AdvancedObjectPlacer

# Signals
signal object_placed(object_instance, position)
signal object_removed(object_instance, position)
signal object_selected(object_instance)
signal network_updated(network_id, network_type)

# Object types
enum ObjectType {
	SIMPLE,       # Single tile objects
	MULTI_TILE,   # Objects spanning multiple tiles
	NETWORKED     # Objects that connect to networks (pipes, wires, etc.)
}

# Network types
enum NetworkType {
	POWER,        # Electrical power network
	DATA,         # Data network
	PIPE,         # Fluid pipe network
	ATMOSPHERIC   # Atmospheric system network
}

# Placement modes
enum PlacementMode {
	NORMAL,       # Standard placement
	NETWORKED     # Network drawing mode
}

# Node references
var editor_ref = null
var object_container: Node2D = null
var preview_container: Node2D = null

# Current selection
var current_object_type: String = ""
var current_object_data: Dictionary = {}
var current_object_scene: PackedScene = null
var current_preview: Node2D = null
var current_placement_mode: int = PlacementMode.NORMAL
var current_network_type: int = NetworkType.POWER
var current_rotation: int = 0  # 0-3 for N, E, S, W directions

# Selection tracking
var selected_object: Node2D = null
var is_dragging: bool = false
var drag_start_position: Vector2i = Vector2i.ZERO

# Network tracking
var networks: Dictionary = {}  # Key: network_id, Value: {type, nodes, connections}
var next_network_id: int = 1

# Multi-tile placement tracking
var multi_tile_start: Vector2i = Vector2i.ZERO
var is_multi_tile_placing: bool = false

# Temp work variables
var last_mouse_grid_position: Vector2i = Vector2i.ZERO

func _init(p_editor_ref, p_object_container: Node2D, p_preview_container: Node2D):
	editor_ref = p_editor_ref
	object_container = p_object_container
	preview_container = p_preview_container
	
	print("AdvancedObjectPlacer: Initialized with references - editor:", editor_ref != null, 
		  " object_container:", object_container != null, " preview_container:", preview_container != null)
	
	# Create preview container if not provided
	if not preview_container:
		preview_container = Node2D.new()
		preview_container.name = "ObjectPreviews"
		if object_container:
			object_container.get_parent().add_child(preview_container)

func _process(delta):
	# Update preview position if needed
	if current_preview != null and editor_ref and "mouse_grid_position" in editor_ref:
		var mouse_pos = editor_ref.mouse_grid_position
		
		# Don't update if position hasn't changed
		if mouse_pos != last_mouse_grid_position:
			last_mouse_grid_position = mouse_pos
			update_preview_position(mouse_pos)
			
			# Update multi-tile preview if in multi-tile placement mode
			if is_multi_tile_placing:
				update_multi_tile_preview(multi_tile_start, mouse_pos)
			
			# Update network preview if in network placement mode
			if current_placement_mode == PlacementMode.NETWORKED:
				update_network_preview(mouse_pos)

# Set current object type for placement
func set_object_type(type: String) -> bool:
	print("AdvancedObjectPlacer: Setting object type to ", type)
	
	if type == "":
		# Clear current object
		current_object_type = ""
		current_object_data = {}
		current_object_scene = null
		
		# Remove preview
		if current_preview:
			current_preview.queue_free()
			current_preview = null
		
		return true
	
	# Get object data
	if type in TileDefinitions.PLACEABLE_OBJECTS:
		current_object_type = type
		current_object_data = TileDefinitions.PLACEABLE_OBJECTS[type]
		
		print("AdvancedObjectPlacer: Object data found: ", current_object_data)
		
		# Try to load scene
		if "scene_path" in current_object_data:
			var scene_path = current_object_data.scene_path
			if ResourceLoader.exists(scene_path):
				current_object_scene = ResourceLoader.load(scene_path)
				print("AdvancedObjectPlacer: Loaded scene: ", scene_path)
			else:
				printerr("Could not load object scene: ", scene_path)
				return false
		else:
			printerr("No scene path in object data")
			return false
		
		# Create preview
		var preview_result = _create_preview()
		if not preview_result:
			printerr("Failed to create preview")
		
		return preview_result
	else:
		printerr("Object type not found in TileDefinitions: ", type)
	
	return false

# Set network mode
func set_network_mode(network_type: int) -> bool:
	current_placement_mode = PlacementMode.NETWORKED
	current_network_type = network_type
	
	# Create network preview
	_create_network_preview()
	
	return true

# Set normal placement mode
func set_normal_mode() -> bool:
	current_placement_mode = PlacementMode.NORMAL
	
	# Remove network preview if exists
	if current_preview and current_preview.get_meta("preview_type", "") == "network":
		current_preview.queue_free()
		current_preview = null
		
		# Recreate object preview if we have a selected object
		if current_object_type != "":
			_create_preview()
	
	return true

# Create preview for current object
func _create_preview() -> bool:
	# Remove any existing preview
	if current_preview:
		current_preview.queue_free()
		current_preview = null
	
	# Create new preview based on object type
	if current_object_scene:
		# Instance the scene
		current_preview = current_object_scene.instantiate()
		
		# Set as preview
		current_preview.modulate.a = 0.5
		current_preview.set_meta("preview", true)
		current_preview.set_meta("preview_type", "object")
		
		# Add to preview container
		preview_container.add_child(current_preview)
		
		# Update rotation if object supports it
		if current_preview.has_method("set_rotation_direction"):
			current_preview.set_rotation_direction(current_rotation)
		
		return true
	
	return false

# Create network preview
func _create_network_preview() -> bool:
	# Remove any existing preview
	if current_preview:
		current_preview.queue_free()
		current_preview = null
	
	# Create network preview node using our NetworkPreview class
	current_preview = NetworkPreview.new()
	current_preview.set_meta("preview", true)
	current_preview.set_meta("preview_type", "network")
	
	# Set network type
	current_preview.network_type = current_network_type
	current_preview.cell_size = editor_ref.get_cell_size() if editor_ref else 32
	
	# Add to preview container
	preview_container.add_child(current_preview)
	
	return true

# Create visual connection between network points
func _create_network_connection(start_pos: Vector2i, end_pos: Vector2i, network_id: int, network_type: int, z_level: int = 0) -> Node2D:
	# Create a network connection node using our NetworkConnection class
	var connection = NetworkConnection.new()
	connection.name = "NetworkConnection_" + str(network_id) + "_" + str(start_pos.x) + "_" + str(start_pos.y) + "_" + str(end_pos.x) + "_" + str(end_pos.y)
	
	# Set properties
	connection.set_meta("network_id", network_id)
	connection.set_meta("network_type", network_type)
	connection.set_meta("start_pos", start_pos)
	connection.set_meta("end_pos", end_pos)
	connection.set_meta("z_level", z_level)
	
	# Set initial values
	connection.start_pos = start_pos
	connection.end_pos = end_pos
	connection.network_type = network_type
	connection.cell_size = editor_ref.get_cell_size() if editor_ref else 32
	
	# Add to object container
	object_container.add_child(connection)
	
	# Add to network
	if network_id in networks:
		networks[network_id].connections.append(connection)
	
	return connection

# Update preview position
func update_preview_position(grid_position: Vector2i):
	if current_preview:
		if current_preview.get_meta("preview_type", "") == "object":
			# Convert to world position
			var world_position = Vector2(grid_position.x * 32, grid_position.y * 32)
			current_preview.position = world_position
			
			# Update rotation if object supports it
			if current_preview.has_method("set_rotation_direction"):
				current_preview.set_rotation_direction(current_rotation)
			
		elif current_preview.get_meta("preview_type", "") == "network":
			# Update network end point
			current_preview.end_point = grid_position
			current_preview.queue_redraw()

# Update multi-tile preview
func update_multi_tile_preview(start_pos: Vector2i, end_pos: Vector2i):
	# Only if we're in multi-tile placement mode
	if not is_multi_tile_placing or not current_preview:
		return
	
	# Update preview size and position based on the multi-tile rectangle
	if current_preview.has_method("update_multi_tile_preview"):
		current_preview.update_multi_tile_preview(start_pos, end_pos)
	else:
		# Default handling if object doesn't support native multi-tile
		var min_x = min(start_pos.x, end_pos.x)
		var min_y = min(start_pos.y, end_pos.y)
		var width = abs(end_pos.x - start_pos.x) + 1
		var height = abs(end_pos.y - start_pos.y) + 1
		
		# Update object position to top-left corner
		current_preview.position = Vector2(min_x * 32, min_y * 32)
		
		# Store size in meta data
		current_preview.set_meta("multi_tile_width", width)
		current_preview.set_meta("multi_tile_height", height)
		
		# Adjust scale if the object supports it
		if current_preview.has_method("set_size"):
			current_preview.set_size(Vector2(width, height))
		else:
			current_preview.scale = Vector2(width, height)

# Update network preview
func update_network_preview(end_pos: Vector2i):
	if current_placement_mode != PlacementMode.NETWORKED or not current_preview:
		return
	
	# Update preview
	current_preview.end_point = end_pos
	current_preview.queue_redraw()

# Start multi-tile placement
func start_multi_tile_placement(start_pos: Vector2i) -> bool:
	multi_tile_start = start_pos
	is_multi_tile_placing = true
	
	# Update preview to show initial position
	update_preview_position(start_pos)
	
	return true

# End multi-tile placement
func end_multi_tile_placement(end_pos: Vector2i) -> bool:
	if not is_multi_tile_placing:
		return false
	
	# Create actual multi-tile object
	var result = place_multi_tile_object(multi_tile_start, end_pos)
	
	# Reset multi-tile state
	is_multi_tile_placing = false
	
	return result

# Start network placement
func start_network_placement(start_pos: Vector2i) -> bool:
	if current_placement_mode != PlacementMode.NETWORKED:
		set_network_mode(current_network_type)
	
	# Set network start point
	if current_preview and current_preview.get_meta("preview_type", "") == "network":
		current_preview.start_point = start_pos
		current_preview.end_point = start_pos
		current_preview.queue_redraw()
		
		return true
	
	return false

# End network placement
func end_network_placement(end_pos: Vector2i) -> bool:
	if current_placement_mode != PlacementMode.NETWORKED or not current_preview:
		return false
	
	# Create actual network connection
	var result = place_network_connection(
		current_preview.start_point, 
		end_pos, 
		current_network_type
	)
	
	# Reset for next placement
	current_preview.start_point = end_pos
	current_preview.end_point = end_pos
	current_preview.queue_redraw()
	
	return result

# Place object at grid position
func place_object(position: Vector2i, z_level: int = 0) -> Node2D:
	print("AdvancedObjectPlacer: Attempting to place object at ", position, ", z_level: ", z_level)
	print("  current_object_type: ", current_object_type)
	print("  current_object_scene: ", current_object_scene)
	
	if current_object_type == "" or not current_object_scene:
		print("AdvancedObjectPlacer: No object type or scene selected")
		return null
	
	# Check if position is already occupied
	if _is_position_occupied(position, z_level):
		print("AdvancedObjectPlacer: Position is already occupied")
		return null
	
	# Instance the object
	var object_instance = current_object_scene.instantiate()
	
	# Set position
	var world_position = Vector2(position.x * 32, position.y * 32)
	object_instance.position = world_position
	
	# Set rotation
	if object_instance.has_method("set_rotation_direction"):
		object_instance.set_rotation_direction(current_rotation)
	
	# Set properties
	object_instance.set_meta("object_type", current_object_type)
	object_instance.set_meta("grid_position", position)
	object_instance.set_meta("z_level", z_level)
	
	# Add to object container
	object_container.add_child(object_instance)
	
	print("AdvancedObjectPlacer: Object placed successfully")
	
	# Emit signal
	emit_signal("object_placed", object_instance, position)
	
	return object_instance

# Place multi-tile object
func place_multi_tile_object(start_pos: Vector2i, end_pos: Vector2i, z_level: int = 0) -> Node2D:
	if current_object_type == "" or not current_object_scene:
		return null
	
	# Calculate multi-tile properties
	var min_x = min(start_pos.x, end_pos.x)
	var min_y = min(start_pos.y, end_pos.y)
	var width = abs(end_pos.x - start_pos.x) + 1
	var height = abs(end_pos.y - start_pos.y) + 1
	
	# Check if any position in the rectangle is occupied
	for y in range(min_y, min_y + height):
		for x in range(min_x, min_x + width):
			if _is_position_occupied(Vector2i(x, y), z_level):
				return null
	
	# Instance the object
	var object_instance = current_object_scene.instantiate()
	
	# Set position to top-left corner
	var world_position = Vector2(min_x * 32, min_y * 32)
	object_instance.position = world_position
	
	# Set properties
	object_instance.set_meta("object_type", current_object_type)
	object_instance.set_meta("grid_position", Vector2i(min_x, min_y))
	object_instance.set_meta("z_level", z_level)
	object_instance.set_meta("multi_tile", true)
	object_instance.set_meta("multi_tile_width", width)
	object_instance.set_meta("multi_tile_height", height)
	
	# If the object supports multi-tile natively
	if object_instance.has_method("set_multi_tile_size"):
		object_instance.set_multi_tile_size(width, height)
	else:
		# Default handling
		if object_instance.has_method("set_size"):
			object_instance.set_size(Vector2(width, height))
		else:
			object_instance.scale = Vector2(width, height)
	
	# Add to object container
	object_container.add_child(object_instance)
	
	# Register all occupied tiles
	for y in range(min_y, min_y + height):
		for x in range(min_x, min_x + width):
			if x != min_x or y != min_y:  # Skip main position
				_register_occupied_tile(Vector2i(x, y), object_instance)
	
	# Emit signal
	emit_signal("object_placed", object_instance, Vector2i(min_x, min_y))
	
	return object_instance

# Place network connection
func place_network_connection(start_pos: Vector2i, end_pos: Vector2i, network_type: int, z_level: int = 0) -> bool:
	# Find or create network at start position
	var start_network_id = _get_network_at_position(start_pos, network_type)
	
	if start_network_id == -1:
		# No existing network, find objects that could be networked
		var start_object = object_at_position(start_pos)
		
		if start_object and _can_connect_to_network(start_object, network_type):
			# Create new network
			start_network_id = _create_network(network_type)
			
			# Add object to network
			_add_object_to_network(start_object, start_network_id)
		else:
			# Can't start a network here
			return false
	
	# Find or create network at end position
	var end_network_id = _get_network_at_position(end_pos, network_type)
	
	if end_network_id == -1:
		# Check if there's an object that can be networked
		var end_object = object_at_position(end_pos)
		
		if end_object and _can_connect_to_network(end_object, network_type):
			# If starting a new network, add to the existing one
			if start_network_id != -1:
				_add_object_to_network(end_object, start_network_id)
			else:
				# Create new network
				end_network_id = _create_network(network_type)
				
				# Add object to network
				_add_object_to_network(end_object, end_network_id)
		else:
			# If not connecting to an object, end point must be empty
			if _is_position_occupied(end_pos, z_level):
				return false
	
	# If both ends have different networks, merge them
	if start_network_id != -1 and end_network_id != -1 and start_network_id != end_network_id:
		_merge_networks(start_network_id, end_network_id)
		
		# Use start_network_id from now on
		end_network_id = start_network_id
	
	# Determine which network ID to use
	var network_id = start_network_id if start_network_id != -1 else end_network_id
	
	# If no network was created, create one now
	if network_id == -1:
		network_id = _create_network(network_type)
	
	# Create visual connection between points
	_create_network_connection(start_pos, end_pos, network_id, network_type, z_level)
	
	# Emit signal
	emit_signal("network_updated", network_id, network_type)
	
	return true

# Remove object at grid position
func remove_object(position: Vector2i, z_level: int = 0) -> bool:
	var object_instance = object_at_position(position, z_level)
	
	if object_instance:
		# Check if it's a multi-tile object
		if object_instance.get_meta("multi_tile", false):
			# Remove all occupied tile references
			var base_pos = object_instance.get_meta("grid_position", Vector2i.ZERO)
			var width = object_instance.get_meta("multi_tile_width", 1)
			var height = object_instance.get_meta("multi_tile_height", 1)
			
			for y in range(base_pos.y, base_pos.y + height):
				for x in range(base_pos.x, base_pos.x + width):
					_unregister_occupied_tile(Vector2i(x, y))
		
		# If it's part of a network, handle network removal
		var network_id = object_instance.get_meta("network_id", -1)
		if network_id != -1:
			_remove_from_network(object_instance, network_id)
		
		# Emit signal before removing
		emit_signal("object_removed", object_instance, position)
		
		# Remove object
		object_instance.queue_free()
		
		return true
	
	# Check if there's a network connection to remove
	var connection = _network_connection_at_position(position, z_level)
	if connection:
		_remove_network_connection(connection)
		return true
	
	return false

# Select object at grid position
func select_object_at(position: Vector2i, z_level: int = 0) -> Node2D:
	# Deselect previous object
	if selected_object:
		if selected_object.has_method("set_selected"):
			selected_object.set_selected(false)
		selected_object = null
	
	# Find object at position
	var object_instance = object_at_position(position, z_level)
	
	if object_instance:
		# Set as selected
		selected_object = object_instance
		
		if selected_object.has_method("set_selected"):
			selected_object.set_selected(true)
		
		# Emit signal
		emit_signal("object_selected", selected_object)
		
		return selected_object
	
	return null

# Start dragging selected object
func start_drag(position: Vector2i):
	if selected_object:
		is_dragging = true
		drag_start_position = position

# End dragging selected object
func end_drag(position: Vector2i) -> bool:
	if not is_dragging or not selected_object:
		is_dragging = false
		return false
	
	# Calculate movement
	var delta_pos = position - drag_start_position
	
	if delta_pos.x == 0 and delta_pos.y == 0:
		# No movement
		is_dragging = false
		return false
	
	# Get current position
	var current_pos = selected_object.get_meta("grid_position", Vector2i.ZERO)
	var z_level = selected_object.get_meta("z_level", 0)
	
	# Calculate new position
	var new_pos = current_pos + delta_pos
	
	# Check if multi-tile
	if selected_object.get_meta("multi_tile", false):
		var width = selected_object.get_meta("multi_tile_width", 1)
		var height = selected_object.get_meta("multi_tile_height", 1)
		
		# Check if target area is free
		for y in range(new_pos.y, new_pos.y + height):
			for x in range(new_pos.x, new_pos.x + width):
				var check_pos = Vector2i(x, y)
				
				# Skip positions occupied by this object
				var current_obj = object_at_position(check_pos, z_level)
				if current_obj and current_obj == selected_object:
					continue
				
				if _is_position_occupied(check_pos, z_level):
					is_dragging = false
					return false
		
		# Remove old occupied tile registrations
		for y in range(current_pos.y, current_pos.y + height):
			for x in range(current_pos.x, current_pos.x + width):
				_unregister_occupied_tile(Vector2i(x, y))
		
		# Register new occupied tiles
		for y in range(new_pos.y, new_pos.y + height):
			for x in range(new_pos.x, new_pos.x + width):
				if x != new_pos.x or y != new_pos.y:  # Skip main position
					_register_occupied_tile(Vector2i(x, y), selected_object)
	else:
		# Check if target position is free
		if _is_position_occupied(new_pos, z_level):
			is_dragging = false
			return false
	
	# Update object position
	selected_object.position = Vector2(new_pos.x * 32, new_pos.y * 32)
	selected_object.set_meta("grid_position", new_pos)
	
	# If part of a network, update connections
	var network_id = selected_object.get_meta("network_id", -1)
	if network_id != -1:
		_update_network_connections(network_id)
	
	is_dragging = false
	return true

# Rotate selected object
func rotate_selected_object() -> bool:
	if selected_object:
		# Increment rotation
		current_rotation = (current_rotation + 1) % 4
		
		# Apply to object
		if selected_object.has_method("set_rotation_direction"):
			selected_object.set_rotation_direction(current_rotation)
			return true
	
	return false

# Get object at position
func object_at_position(position: Vector2i, z_level: int = 0) -> Node2D:
	# Search for object at exact position
	for obj in object_container.get_children():
		if obj.get_meta("grid_position", Vector2i.ZERO) == position and obj.get_meta("z_level", 0) == z_level:
			return obj
		
		# Check if position is within a multi-tile object
		if obj.get_meta("multi_tile", false):
			var base_pos = obj.get_meta("grid_position", Vector2i.ZERO)
			var width = obj.get_meta("multi_tile_width", 1)
			var height = obj.get_meta("multi_tile_height", 1)
			
			if position.x >= base_pos.x and position.x < base_pos.x + width and \
			   position.y >= base_pos.y and position.y < base_pos.y + height and \
			   obj.get_meta("z_level", 0) == z_level:
				return obj
	
	return null

# Check if position is occupied
func _is_position_occupied(position: Vector2i, z_level: int = 0) -> bool:
	return object_at_position(position, z_level) != null or _network_connection_at_position(position, z_level) != null

# Register an occupied tile for a multi-tile object
func _register_occupied_tile(position: Vector2i, object_instance: Node2D):
	object_instance.set_meta("occupies_" + str(position.x) + "_" + str(position.y), true)

# Unregister an occupied tile
func _unregister_occupied_tile(position: Vector2i):
	# No specific action needed with our implementation
	pass

# Create a new network
func _create_network(network_type: int) -> int:
	var network_id = next_network_id
	next_network_id += 1
	
	networks[network_id] = {
		"type": network_type,
		"nodes": [],  # Objects in network
		"connections": []  # Visual connections
	}
	
	return network_id

# Add object to network
func _add_object_to_network(object_instance: Node2D, network_id: int) -> bool:
	if network_id in networks:
		# Set object network ID
		object_instance.set_meta("network_id", network_id)
		
		# Add to network
		if not object_instance in networks[network_id].nodes:
			networks[network_id].nodes.append(object_instance)
			
			# If object has network connectivity method, call it
			if object_instance.has_method("connect_to_network"):
				object_instance.connect_to_network(network_id, networks[network_id].type)
			
			return true
	
	return false

# Remove object from network
func _remove_from_network(object_instance: Node2D, network_id: int) -> bool:
	if network_id in networks:
		# Remove object from network
		networks[network_id].nodes.erase(object_instance)
		
		# Remove network ID from object
		object_instance.set_meta("network_id", -1)
		
		# If object has disconnect method, call it
		if object_instance.has_method("disconnect_from_network"):
			object_instance.disconnect_from_network()
		
		# If network is now empty, remove it
		if networks[network_id].nodes.size() == 0 and networks[network_id].connections.size() == 0:
			networks.erase(network_id)
		else:
			# Check if network is now split into disconnected parts
			_check_network_connectivity(network_id)
		
		return true
	
	return false

# Merge two networks
func _merge_networks(network_id1: int, network_id2: int) -> bool:
	if network_id1 in networks and network_id2 in networks:
		# Move all nodes from network2 to network1
		for node in networks[network_id2].nodes:
			_add_object_to_network(node, network_id1)
		
		# Move all connections from network2 to network1
		for connection in networks[network_id2].connections:
			connection.set_meta("network_id", network_id1)
			networks[network_id1].connections.append(connection)
		
		# Remove network2
		networks.erase(network_id2)
		
		return true
	
	return false

# Remove network connection
func _remove_network_connection(connection: Node2D) -> bool:
	var network_id = connection.get_meta("network_id", -1)
	
	if network_id != -1 and network_id in networks:
		# Remove from network
		networks[network_id].connections.erase(connection)
		
		# Remove connection
		connection.queue_free()
		
		# If network is now empty, remove it
		if networks[network_id].nodes.size() == 0 and networks[network_id].connections.size() == 0:
			networks.erase(network_id)
		else:
			# Check if network is now split into disconnected parts
			_check_network_connectivity(network_id)
		
		return true
	
	return false

# Get network connection at position
func _network_connection_at_position(position: Vector2i, z_level: int = 0) -> Node2D:
	# Check all networks
	for network_id in networks.keys():
		for connection in networks[network_id].connections:
			if connection.get_meta("z_level", 0) != z_level:
				continue
				
			var start_pos = connection.get_meta("start_pos", Vector2i.ZERO)
			var end_pos = connection.get_meta("end_pos", Vector2i.ZERO)
			
			# Check if this is a horizontal connection
			if start_pos.y == end_pos.y and position.y == start_pos.y:
				var min_x = min(start_pos.x, end_pos.x)
				var max_x = max(start_pos.x, end_pos.x)
				
				if position.x >= min_x and position.x <= max_x:
					return connection
			
			# Check if this is a vertical connection
			if start_pos.x == end_pos.x and position.x == start_pos.x:
				var min_y = min(start_pos.y, end_pos.y)
				var max_y = max(start_pos.y, end_pos.y)
				
				if position.y >= min_y and position.y <= max_y:
					return connection
	
	return null

# Get network at position
func _get_network_at_position(position: Vector2i, network_type: int) -> int:
	# Check if there's an object with network
	var obj = object_at_position(position)
	
	if obj:
		var network_id = obj.get_meta("network_id", -1)
		
		if network_id != -1 and network_id in networks:
			# Check if network type matches
			if networks[network_id].type == network_type:
				return network_id
	
	# Check if there's a network connection
	var connection = _network_connection_at_position(position)
	
	if connection:
		var network_id = connection.get_meta("network_id", -1)
		
		if network_id != -1 and network_id in networks:
			# Check if network type matches
			if networks[network_id].type == network_type:
				return network_id
	
	return -1

# Check if object can connect to network
func _can_connect_to_network(object_instance: Node2D, network_type: int) -> bool:
	if not object_instance:
		return false
	
	# Check if object supports network connection
	if object_instance.has_method("can_connect_to_network"):
		return object_instance.can_connect_to_network(network_type)
	
	# Check based on object type
	var obj_type = object_instance.get_meta("object_type", "")
	
	# Default check based on object properties
	if obj_type in TileDefinitions.PLACEABLE_OBJECTS:
		var obj_data = TileDefinitions.PLACEABLE_OBJECTS[obj_type]
		
		if "properties" in obj_data:
			var props = obj_data.properties
			
			# Check network connectivity based on type
			match network_type:
				NetworkType.POWER:
					return props.get("has_power_connection", false)
				NetworkType.DATA:
					return props.get("has_data_connection", false)
				NetworkType.PIPE:
					return props.get("has_pipe_connection", false)
				NetworkType.ATMOSPHERIC:
					return props.get("has_atmos_connection", false)
	
	return false

# Update network connections
func _update_network_connections(network_id: int) -> bool:
	if network_id in networks:
		# Force redraw all connections
		for connection in networks[network_id].connections:
			connection.queue_redraw()
		
		return true
	
	return false

# Check if network is still fully connected
func _check_network_connectivity(network_id: int) -> bool:
	if not network_id in networks:
		return false
	
	var network = networks[network_id]
	
	# If no nodes or just one, network is connected
	if network.nodes.size() <= 1:
		return true
	
	# Build connectivity graph
	var graph = {}
	
	# Add all nodes as isolated vertices
	for node in network.nodes:
		var pos = node.get_meta("grid_position", Vector2i.ZERO)
		var pos_str = str(pos.x) + "_" + str(pos.y)
		graph[pos_str] = []
	
	# Add edges from connections
	for connection in network.connections:
		var start_pos = connection.get_meta("start_pos", Vector2i.ZERO)
		var end_pos = connection.get_meta("end_pos", Vector2i.ZERO)
		
		var start_str = str(start_pos.x) + "_" + str(start_pos.y)
		var end_str = str(end_pos.x) + "_" + str(end_pos.y)
		
		# Find nodes at these positions
		var start_node_pos = ""
		var end_node_pos = ""
		
		for node in network.nodes:
			var pos = node.get_meta("grid_position", Vector2i.ZERO)
			var pos_str = str(pos.x) + "_" + str(pos.y)
			
			if _positions_are_adjacent(pos, start_pos):
				start_node_pos = pos_str
			
			if _positions_are_adjacent(pos, end_pos):
				end_node_pos = pos_str
		
		# Add edge if we found both endpoints
		if start_node_pos != "" and end_node_pos != "":
			if not end_node_pos in graph[start_node_pos]:
				graph[start_node_pos].append(end_node_pos)
			
			if not start_node_pos in graph[end_node_pos]:
				graph[end_node_pos].append(start_node_pos)
	
	# Perform BFS to check connectivity
	var visited = {}
	var queue = []
	
	# Start from first node
	var start_key = graph.keys()[0]
	visited[start_key] = true
	queue.append(start_key)
	
	while queue.size() > 0:
		var current = queue.pop_front()
		
		for neighbor in graph[current]:
			if not neighbor in visited:
				visited[neighbor] = true
				queue.append(neighbor)
	
	# Check if all nodes were visited
	for key in graph:
		if not key in visited:
			# Network is not fully connected, should split
			_split_network(network_id, graph, visited)
			return false
	
	return true

# Split disconnected network into separate networks
func _split_network(network_id: int, graph: Dictionary, visited: Dictionary) -> bool:
	if not network_id in networks:
		return false
	
	var old_network = networks[network_id]
	var old_type = old_network.type
	
	# Create a new network for disconnected components
	var new_network_id = _create_network(old_type)
	
	# Move disconnected nodes to new network
	for node in old_network.nodes.duplicate():
		var pos = node.get_meta("grid_position", Vector2i.ZERO)
		var pos_str = str(pos.x) + "_" + str(pos.y)
		
		if not pos_str in visited:
			# Move to new network
			_remove_from_network(node, network_id)
			_add_object_to_network(node, new_network_id)
	
	# Move disconnected connections to new network
	for connection in old_network.connections.duplicate():
		var start_pos = connection.get_meta("start_pos", Vector2i.ZERO)
		var end_pos = connection.get_meta("end_pos", Vector2i.ZERO)
		
		var start_str = str(start_pos.x) + "_" + str(start_pos.y)
		var end_str = str(end_pos.x) + "_" + str(end_pos.y)
		
		# If both endpoints are not in the visited set, move to new network
		if (not start_str in visited) and (not end_str in visited):
			old_network.connections.erase(connection)
			networks[new_network_id].connections.append(connection)
			connection.set_meta("network_id", new_network_id)
	
	# Emit signal for both networks
	emit_signal("network_updated", network_id, old_type)
	emit_signal("network_updated", new_network_id, old_type)
	
	return true

# Check if two positions are adjacent
func _positions_are_adjacent(pos1: Vector2i, pos2: Vector2i) -> bool:
	return (abs(pos1.x - pos2.x) == 1 and pos1.y == pos2.y) or (abs(pos1.y - pos2.y) == 1 and pos1.x == pos2.x)

# Save object data to map file
func save_objects_data() -> Dictionary:
	var data = {
		"objects": [],
		"networks": {}
	}
	
	# Save placed objects
	for obj in object_container.get_children():
		# Skip network connections
		if obj.name.begins_with("NetworkConnection_"):
			continue
		
		var obj_data = {
			"type": obj.get_meta("object_type", ""),
			"position": {
				"x": obj.get_meta("grid_position", Vector2i.ZERO).x,
				"y": obj.get_meta("grid_position", Vector2i.ZERO).y
			},
			"z_level": obj.get_meta("z_level", 0),
			"rotation": current_rotation
		}
		
		# Add multi-tile data if applicable
		if obj.get_meta("multi_tile", false):
			obj_data["multi_tile"] = true
			obj_data["width"] = obj.get_meta("multi_tile_width", 1)
			obj_data["height"] = obj.get_meta("multi_tile_height", 1)
		
		# Add network data if applicable
		var network_id = obj.get_meta("network_id", -1)
		if network_id != -1:
			obj_data["network_id"] = network_id
		
		# Add custom properties
		if obj.has_method("get_properties"):
			obj_data["properties"] = obj.get_properties()
		
		data.objects.append(obj_data)
	
	# Save networks
	for network_id in networks:
		var network = networks[network_id]
		
		var connections = []
		for connection in network.connections:
			connections.append({
				"start": {
					"x": connection.get_meta("start_pos", Vector2i.ZERO).x,
					"y": connection.get_meta("start_pos", Vector2i.ZERO).y
				},
				"end": {
					"x": connection.get_meta("end_pos", Vector2i.ZERO).x,
					"y": connection.get_meta("end_pos", Vector2i.ZERO).y
				},
				"z_level": connection.get_meta("z_level", 0)
			})
		
		data.networks[network_id] = {
			"type": network.type,
			"connections": connections
		}
	
	# Save next network ID
	data["next_network_id"] = next_network_id
	
	return data

# Load object data from map file
func load_objects_data(data: Dictionary) -> bool:
	# Clear existing objects
	for child in object_container.get_children():
		child.queue_free()
	
	# Clear networks
	networks.clear()
	
	# Load networks first
	if "networks" in data:
		for network_id_str in data.networks:
			var network_id = int(network_id_str)
			var network_data = data.networks[network_id_str]
			
			# Create network
			networks[network_id] = {
				"type": network_data.type,
				"nodes": [],
				"connections": []
			}
	
	# Set next network ID
	if "next_network_id" in data:
		next_network_id = data.next_network_id
	else:
		# Find highest network ID and add 1
		next_network_id = 1
		for network_id in networks:
			next_network_id = max(next_network_id, network_id + 1)
	
	# Load objects
	if "objects" in data:
		for obj_data in data.objects:
			# Get object type
			var obj_type = obj_data.type
			
			# Load object scene
			if obj_type in TileDefinitions.PLACEABLE_OBJECTS:
				var scene_path = TileDefinitions.PLACEABLE_OBJECTS[obj_type].scene_path
				
				if ResourceLoader.exists(scene_path):
					var scene = ResourceLoader.load(scene_path)
					
					# Create position
					var pos = Vector2i(obj_data.position.x, obj_data.position.y)
					var z_level = obj_data.z_level
					
					# Create object
					var obj_instance = scene.instantiate()
					
					# Set position
					obj_instance.position = Vector2(pos.x * 32, pos.y * 32)
					
					# Set metadata
					obj_instance.set_meta("object_type", obj_type)
					obj_instance.set_meta("grid_position", pos)
					obj_instance.set_meta("z_level", z_level)
					
					# Set rotation
					var rotation = obj_data.get("rotation", 0)
					if obj_instance.has_method("set_rotation_direction"):
						obj_instance.set_rotation_direction(rotation)
					
					# Set multi-tile properties if applicable
					if obj_data.get("multi_tile", false):
						obj_instance.set_meta("multi_tile", true)
						obj_instance.set_meta("multi_tile_width", obj_data.width)
						obj_instance.set_meta("multi_tile_height", obj_data.height)
						
						# Apply multi-tile
						if obj_instance.has_method("set_multi_tile_size"):
							obj_instance.set_multi_tile_size(obj_data.width, obj_data.height)
						else:
							if obj_instance.has_method("set_size"):
								obj_instance.set_size(Vector2(obj_data.width, obj_data.height))
							else:
								obj_instance.scale = Vector2(obj_data.width, obj_data.height)
						
						# Register occupied tiles
						for y in range(pos.y, pos.y + obj_data.height):
							for x in range(pos.x, pos.x + obj_data.width):
								if x != pos.x or y != pos.y:  # Skip main position
									_register_occupied_tile(Vector2i(x, y), obj_instance)
					
					# Set custom properties
					if "properties" in obj_data and obj_instance.has_method("set_properties"):
						obj_instance.set_properties(obj_data.properties)
					
					# Add to container
					object_container.add_child(obj_instance)
					
					# Add to network if applicable
					if "network_id" in obj_data:
						var network_id = obj_data.network_id
						if network_id in networks:
							_add_object_to_network(obj_instance, network_id)
	
	# Create network connections
	if "networks" in data:
		for network_id_str in data.networks:
			var network_id = int(network_id_str)
			var network_data = data.networks[network_id_str]
			
			for conn_data in network_data.connections:
				var start_pos = Vector2i(conn_data.start.x, conn_data.start.y)
				var end_pos = Vector2i(conn_data.end.x, conn_data.end.y)
				var z_level = conn_data.get("z_level", 0)
				
				_create_network_connection(start_pos, end_pos, network_id, network_data.type, z_level)
	
	return true
