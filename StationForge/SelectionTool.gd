extends Node
class_name SelectionTool

signal selection_changed(selected_tiles, selected_objects)
signal selection_finished(selected_tiles, selected_objects)

# Selection state
var is_selecting: bool = false
var start_position: Vector2i = Vector2i.ZERO
var end_position: Vector2i = Vector2i.ZERO
var selected_tiles: Array[Vector2i] = []
var selected_objects: Array = []
var current_layer: int = 0
var current_z_level: int = 0

# References
var editor_ref = null
var object_placer = null

# Selection appearance
var selection_color: Color = Color(0.3, 0.7, 1.0, 0.3)
var selection_border_color: Color = Color(0.3, 0.7, 1.0, 0.8)

func _init():
	# Try to get editor reference
	if Engine.has_singleton("Editor"):
		editor_ref = Engine.get_singleton("Editor")

func start_selection(start_pos: Vector2i, layer: int, z_level: int):
	is_selecting = true
	start_position = start_pos
	end_position = start_pos
	current_layer = layer
	current_z_level = z_level
	selected_tiles.clear()
	selected_objects.clear()
	
	# Add initial tile to selection
	selected_tiles.append(start_pos)
	
	# Get object placer reference
	if editor_ref and "object_placer" in editor_ref:
		object_placer = editor_ref.object_placer
	
	emit_signal("selection_changed", selected_tiles, selected_objects)

func update_selection(current_pos: Vector2i):
	if not is_selecting:
		return
	
	end_position = current_pos
	
	# Calculate selection rectangle
	var min_x = min(start_position.x, end_position.x)
	var min_y = min(start_position.y, end_position.y)
	var max_x = max(start_position.x, end_position.x)
	var max_y = max(start_position.y, end_position.y)
	
	# Create list of selected tiles
	selected_tiles.clear()
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			selected_tiles.append(Vector2i(x, y))
	
	# Get selected objects
	if object_placer:
		selected_objects.clear()
		for tile_pos in selected_tiles:
			var objects = object_placer.get_objects_at(tile_pos, current_z_level)
			for obj in objects:
				if not obj in selected_objects:
					selected_objects.append(obj)
	
	emit_signal("selection_changed", selected_tiles, selected_objects)

func finish_selection() -> Dictionary:
	if not is_selecting:
		return {"tiles": [], "objects": []}
	
	is_selecting = false
	
	var result = {
		"tiles": selected_tiles.duplicate(),
		"objects": selected_objects.duplicate()
	}
	
	emit_signal("selection_finished", selected_tiles, selected_objects)
	
	return result

func cancel_selection():
	if not is_selecting:
		return
	
	is_selecting = false
	selected_tiles.clear()
	selected_objects.clear()
	
	emit_signal("selection_changed", selected_tiles, selected_objects)

func draw_selection(canvas_item):
	if not is_selecting and selected_tiles.size() == 0:
		return
	
	# Draw filled rectangle for each selected tile
	for tile_pos in selected_tiles:
		var rect = Rect2(
			tile_pos.x * 32,
			tile_pos.y * 32,
			32, 32
		)
		
		# Draw fill
		RenderingServer.canvas_item_add_rect(canvas_item, rect, selection_color)
		
		# Draw border
		RenderingServer.canvas_item_add_line(canvas_item, Vector2(rect.position.x, rect.position.y), Vector2(rect.position.x + rect.size.x, rect.position.y), selection_border_color, 2.0)
		RenderingServer.canvas_item_add_line(canvas_item, Vector2(rect.position.x + rect.size.x, rect.position.y), Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y), selection_border_color, 2.0)
		RenderingServer.canvas_item_add_line(canvas_item, Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y), Vector2(rect.position.x, rect.position.y + rect.size.y), selection_border_color, 2.0)
		RenderingServer.canvas_item_add_line(canvas_item, Vector2(rect.position.x, rect.position.y + rect.size.y), Vector2(rect.position.x, rect.position.y), selection_border_color, 2.0)

func copy_selection() -> Dictionary:
	var copy_data = {
		"tiles": {},
		"objects": []
	}
	
	# Get tilemap references
	var target_tilemap = null
	if editor_ref:
		match current_layer:
			0: # Floor
				target_tilemap = editor_ref.floor_tilemap
			1: # Wall 
				target_tilemap = editor_ref.wall_tilemap
			2: # Objects
				target_tilemap = editor_ref.objects_tilemap
			4: # Zone
				target_tilemap = editor_ref.zone_tilemap
	
	# Copy tile data
	if target_tilemap:
		for tile_pos in selected_tiles:
			var source_id = target_tilemap.get_cell_source_id(0, tile_pos)
			if source_id != -1:
				var atlas_coords = target_tilemap.get_cell_atlas_coords(0, tile_pos)
				var relative_pos = tile_pos - selected_tiles[0]  # Make position relative to first tile
				
				copy_data.tiles[relative_pos] = {
					"source_id": source_id,
					"atlas_coords": atlas_coords
				}
	
	# Copy object data
	for obj in selected_objects:
		if not is_instance_valid(obj):
			continue
		
		var obj_data = {
			"type": obj.get_meta("object_type"),
			"grid_position": obj.get_meta("grid_position") - selected_tiles[0],  # Relative position
			"z_level": obj.get_meta("z_level")
		}
		
		# Add direction if applicable
		if "facing_direction" in obj:
			obj_data["direction"] = obj.facing_direction
		
		# Add other properties
		if "is_active" in obj:
			obj_data["is_active"] = obj.is_active
		
		copy_data.objects.append(obj_data)
	
	return copy_data

func paste_selection(paste_data: Dictionary, target_pos: Vector2i):
	# Get tilemap references
	var target_tilemap = null
	if editor_ref:
		match current_layer:
			0: # Floor
				target_tilemap = editor_ref.floor_tilemap
			1: # Wall 
				target_tilemap = editor_ref.wall_tilemap
			2: # Objects
				target_tilemap = editor_ref.objects_tilemap
			4: # Zone
				target_tilemap = editor_ref.zone_tilemap
	
	# Paste tile data
	if target_tilemap and "tiles" in paste_data:
		for relative_pos_str in paste_data.tiles:
			var relative_pos = string_to_vector2i(relative_pos_str)
			var tile_data = paste_data.tiles[relative_pos_str]
			
			var paste_pos = target_pos + relative_pos
			target_tilemap.set_cell(0, paste_pos, tile_data.source_id, tile_data.atlas_coords)
	
	# Paste object data
	if object_placer and "objects" in paste_data:
		for obj_data in paste_data.objects:
			var paste_pos = target_pos + obj_data.grid_position
			
			# Set current object type
			object_placer.set_object_type(obj_data.type)
			
			# Place object
			var direction = obj_data.direction if "direction" in obj_data else 0
			var obj = object_placer.place_object(paste_pos, current_z_level, direction)
			
			# Apply additional properties
			if obj and "is_active" in obj_data:
				obj.is_active = obj_data.is_active
				
				# Call appropriate method based on state
				if obj.is_active:
					if obj.has_method("turn_on"):
						obj.turn_on()
				else:
					if obj.has_method("turn_off"):
						obj.turn_off()

func delete_selection():
	# Get tilemap references
	var target_tilemap = null
	if editor_ref:
		match current_layer:
			0: # Floor
				target_tilemap = editor_ref.floor_tilemap
			1: # Wall 
				target_tilemap = editor_ref.wall_tilemap
			2: # Objects
				target_tilemap = editor_ref.objects_tilemap
			4: # Zone
				target_tilemap = editor_ref.zone_tilemap
	
	# Delete tiles
	if target_tilemap:
		for tile_pos in selected_tiles:
			target_tilemap.set_cell(0, tile_pos, -1)  # Clear tile
	
	# Delete objects
	if object_placer:
		for obj in selected_objects:
			if is_instance_valid(obj):
				var grid_pos = obj.get_meta("grid_position")
				object_placer.remove_object(grid_pos, current_z_level)
	
	# Clear selection
	selected_tiles.clear()
	selected_objects.clear()
	
	emit_signal("selection_changed", selected_tiles, selected_objects)

func string_to_vector2i(vector_str: String) -> Vector2i:
	# Convert a string like "(1, 2)" to Vector2i
	var parts = vector_str.trim_prefix("(").trim_suffix(")").split(", ")
	if parts.size() >= 2:
		return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i.ZERO
