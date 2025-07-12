extends Node
class_name ObjectPlacer

# Signals
signal object_placed(object_instance, position)
signal object_removed(object_instance, position)
signal object_selected(object_instance)

# References
var editor_ref = null
var objects_container = null

# Current object
var current_object_type: String = ""
var current_object_scene: PackedScene = null
var preview_instance = null
var preview_color: Color = Color(1, 1, 1, 0.5)

# Object tracking
var placed_objects = {}  # Format: { Vector3i(x, y, z): [objects] }

func _init():
	# Try to get editor reference
	if Engine.has_singleton("Editor"):
		editor_ref = Engine.get_singleton("Editor")

func _ready():
	# Create a container for objects if needed
	if not objects_container:
		objects_container = Node2D.new()
		objects_container.name = "PlacedObjects"
		add_child(objects_container)

func set_object_type(object_type: String):
	# Clear current type
	if current_object_type != "" and preview_instance:
		preview_instance.queue_free()
		preview_instance = null
	
	current_object_type = object_type
	
	# Load scene for this object type
	if object_type == "":
		current_object_scene = null
		return
		
	# Get scene path from TileDefinitions
	if object_type in TileDefinitions.PLACEABLE_OBJECTS:
		var scene_path = TileDefinitions.PLACEABLE_OBJECTS[object_type].scene_path
		current_object_scene = load(scene_path)
		
		# Create preview instance
		create_preview_instance()

func create_preview_instance():
	if current_object_scene == null:
		return
		
	# Create instance for preview
	preview_instance = current_object_scene.instantiate()
	
	# Apply preview modifications
	preview_instance.modulate.a = 0.5
	
	# Don't add to scene yet - we'll do that in the editor
	return preview_instance

func update_preview_position(grid_position: Vector2i, snap_to_grid: bool = true):
	if not preview_instance:
		return
		
	if not preview_instance.get_parent():
		# Add to scene first time
		get_tree().get_root().add_child(preview_instance)
	
	# Update position
	if snap_to_grid:
		preview_instance.position = Vector2(
			grid_position.x * 32 + 16,  # Center in tile
			grid_position.y * 32 + 16   # Center in tile
		)
	else:
		# Non-grid-aligned position (for mouse follow)
		preview_instance.position = Vector2(
			grid_position.x,
			grid_position.y
		)

func update_preview_rotation(direction_index: int):
	if not preview_instance:
		return
		
	# Skip if object doesn't have direction property
	if not "facing_direction" in preview_instance:
		return
		
	# Update direction
	preview_instance.facing_direction = direction_index
	
	# Call function if available
	if preview_instance.has_method("_set_sprite_animation"):
		preview_instance._set_sprite_animation()

func place_object(grid_position: Vector2i, z_level: int, direction: int = 0) -> Node2D:
	if current_object_scene == null:
		return null
		
	# Create the object instance
	var object_instance = current_object_scene.instantiate()
	
	# Set position (centered in tile)
	object_instance.position = Vector2(
		grid_position.x * 32 + 16,  # Center in tile
		grid_position.y * 32 + 16   # Center in tile
	)
	
	# Set direction if applicable
	if "facing_direction" in object_instance:
		object_instance.facing_direction = direction
		
		# Call function if available
		if object_instance.has_method("_set_sprite_animation"):
			object_instance._set_sprite_animation()
	
	# Add to container
	objects_container.add_child(object_instance)
	
	# Track the object
	var pos_key = Vector3i(grid_position.x, grid_position.y, z_level)
	if not pos_key in placed_objects:
		placed_objects[pos_key] = []
	
	placed_objects[pos_key].append(object_instance)
	
	# Set metadata
	object_instance.set_meta("grid_position", grid_position)
	object_instance.set_meta("z_level", z_level)
	object_instance.set_meta("object_type", current_object_type)
	
	# Emit signal
	emit_signal("object_placed", object_instance, grid_position)
	
	return object_instance

func remove_object(grid_position: Vector2i, z_level: int) -> bool:
	var pos_key = Vector3i(grid_position.x, grid_position.y, z_level)
	
	# Check if there are objects at this position
	if not pos_key in placed_objects or placed_objects[pos_key].size() == 0:
		return false
	
	# Get objects at this position
	var objects = placed_objects[pos_key]
	
	# Remove all objects at this position
	for object in objects:
		if is_instance_valid(object):
			# Emit signal
			emit_signal("object_removed", object, grid_position)
			
			# Remove from scene
			object.queue_free()
	
	# Clear list
	placed_objects[pos_key].clear()
	
	return true

func get_objects_at(grid_position: Vector2i, z_level: int) -> Array:
	var pos_key = Vector3i(grid_position.x, grid_position.y, z_level)
	
	# Check if there are objects at this position
	if not pos_key in placed_objects:
		return []
	
	# Filter out invalid objects
	var valid_objects = []
	for object in placed_objects[pos_key]:
		if is_instance_valid(object):
			valid_objects.append(object)
	
	# Update the list
	placed_objects[pos_key] = valid_objects
	
	return valid_objects

func select_object_at(grid_position: Vector2i, z_level: int) -> Node:
	var objects = get_objects_at(grid_position, z_level)
	if objects.size() == 0:
		return null
	
	# Select the first object
	var selected_object = objects[0]
	
	# Emit signal
	emit_signal("object_selected", selected_object)
	
	return selected_object

func rotate_object(object_instance: Node):
	# Check if object has direction property
	if not "facing_direction" in object_instance:
		return
		
	# Rotate to next direction
	object_instance.facing_direction = (object_instance.facing_direction + 1) % 4
	
	# Call function if available
	if object_instance.has_method("_set_sprite_animation"):
		object_instance._set_sprite_animation()

func hide_preview():
	if preview_instance:
		preview_instance.visible = false

func show_preview():
	if preview_instance:
		preview_instance.visible = true

func clear_preview():
	if preview_instance:
		preview_instance.queue_free()
		preview_instance = null
		
	current_object_type = ""
	current_object_scene = null

func save_objects_data() -> Dictionary:
	var data = {}
	
	# Loop through all tracked objects
	for pos_key in placed_objects.keys():
		var objects_at_pos = placed_objects[pos_key]
		if objects_at_pos.size() == 0:
			continue
			
		# Create data array for this position
		data[str(pos_key)] = []
		
		# Add data for each object
		for object in objects_at_pos:
			if not is_instance_valid(object):
				continue
				
			var object_data = {
				"type": object.get_meta("object_type"),
				"position": {
					"x": pos_key.x,
					"y": pos_key.y,
					"z": pos_key.z
				}
			}
			
			# Add direction if applicable
			if "facing_direction" in object:
				object_data["direction"] = object.facing_direction
			
			# Add other properties
			if "is_active" in object:
				object_data["is_active"] = object.is_active
			
			# Add to data array
			data[str(pos_key)].append(object_data)
	
	return data

func load_objects_data(data: Dictionary):
	# Clear existing objects
	clear_all_objects()
	
	# Load objects from data
	for pos_key_str in data.keys():
		var objects_data = data[pos_key_str]
		
		# Parse position key
		var parts = pos_key_str.trim_prefix("(").trim_suffix(")").split(", ")
		if parts.size() < 3:
			continue
			
		var grid_position = Vector2i(int(parts[0]), int(parts[1]))
		var z_level = int(parts[2])
		
		# Create each object
		for object_data in objects_data:
			# Set current object type
			set_object_type(object_data.type)
			
			# Get direction
			var direction = 0
			if "direction" in object_data:
				direction = object_data.direction
			
			# Place object
			var object = place_object(grid_position, z_level, direction)
			
			# Apply additional properties
			if object and "is_active" in object_data:
				object.is_active = object_data.is_active
				
				# Call appropriate method based on state
				if object.is_active:
					if object.has_method("turn_on"):
						object.turn_on()
				else:
					if object.has_method("turn_off"):
						object.turn_off()

func clear_all_objects():
	# Remove all objects
	for pos_key in placed_objects.keys():
		for object in placed_objects[pos_key]:
			if is_instance_valid(object):
				object.queue_free()
	
	# Clear tracking
	placed_objects.clear()
