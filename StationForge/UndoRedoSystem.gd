extends Node
class_name UndoRedoSystem

signal state_changed(can_undo, can_redo)

# Constants
const MAX_HISTORY = 50

# Action types
enum ActionType {
	PLACE_TILE,
	ERASE_TILE,
	FILL_TILES,
	PLACE_LINE,
	PLACE_OBJECT,
	ERASE_OBJECT,
	MODIFY_OBJECT,
	DELETE_SELECTION,
	PASTE_SELECTION
}

# History stacks
var undo_stack = []
var redo_stack = []

var selection_tool = SelectionTool.new()

# References
var editor_ref = null

func _init():
	# Try to get editor reference
	if Engine.has_singleton("Editor"):
		editor_ref = Engine.get_singleton("Editor")

func _ready():
	# Connect to input events for keyboard shortcuts
	if editor_ref:
		editor_ref.connect("key_shortcut", Callable(self, "_on_key_shortcut"))

func _on_key_shortcut(shortcut: String):
	# Handle undo/redo shortcuts
	if shortcut == "undo":
		undo()
	elif shortcut == "redo":
		redo()

func register_tile_action(action_type: int, tile_positions: Array, layer: int, z_level: int, old_data: Array, new_data: Array):
	# Create action record
	var action = {
		"type": action_type,
		"target": "tile",
		"positions": tile_positions.duplicate(),
		"layer": layer,
		"z_level": z_level,
		"old_data": old_data.duplicate(),
		"new_data": new_data.duplicate()
	}
	
	# Add to undo stack
	_add_to_undo_stack(action)
	_notify_state()

func register_object_action(action_type: int, object_ids: Array, positions: Array, z_level: int, old_data: Array, new_data: Array):
	# Create action record
	var action = {
		"type": action_type,
		"target": "object",
		"object_ids": object_ids.duplicate(),
		"positions": positions.duplicate(),
		"z_level": z_level,
		"old_data": old_data.duplicate(),
		"new_data": new_data.duplicate()
	}
	
	# Add to undo stack
	_add_to_undo_stack(action)
	_notify_state()

func register_selection_action(action_type: int, selection_data: Dictionary, target_position: Vector2i = Vector2i.ZERO):
	# Create action record
	var action = {
		"type": action_type,
		"target": "selection",
		"selection_data": selection_data.duplicate(true),
		"target_position": target_position
	}
	
	# Add to undo stack
	_add_to_undo_stack(action)
	_notify_state()

func can_undo() -> bool:
	return undo_stack.size() > 0

func can_redo() -> bool:
	return redo_stack.size() > 0

func undo():
	if not can_undo():
		return
	
	var action = undo_stack.pop_back()
	_add_to_redo_stack(action)
	
	# Process action based on type
	match action.target:
		"tile":
			_undo_tile_action(action)
		"object":
			_undo_object_action(action)
		"selection":
			_undo_selection_action(action)
	
	_notify_state()

func redo():
	if not can_redo():
		return
	
	var action = redo_stack.pop_back()
	_add_to_undo_stack(action)
	
	# Process action based on type
	match action.target:
		"tile":
			_redo_tile_action(action)
		"object":
			_redo_object_action(action)
		"selection":
			_redo_selection_action(action)
	
	_notify_state()

func clear_history():
	undo_stack.clear()
	redo_stack.clear()
	_notify_state()

func _add_to_undo_stack(action):
	undo_stack.append(action)
	
	# Limit stack size
	if undo_stack.size() > MAX_HISTORY:
		undo_stack.pop_front()
	
	# Clear redo stack when a new action is registered
	redo_stack.clear()

func _add_to_redo_stack(action):
	redo_stack.append(action)
	
	# Limit stack size
	if redo_stack.size() > MAX_HISTORY:
		redo_stack.pop_front()

func _notify_state():
	emit_signal("state_changed", can_undo(), can_redo())

func _undo_tile_action(action):
	# Get the appropriate tilemap
	var tilemap = _get_tilemap_for_layer(action.layer)
	if not tilemap:
		return
	
	# Restore previous state
	for i in range(action.positions.size()):
		var pos = action.positions[i]
		var old_data = action.old_data[i]
		
		if old_data is Dictionary and "source_id" in old_data:
			# Restore tile
			tilemap.set_cell(0, pos, old_data.source_id, old_data.atlas_coords)
		else:
			# No tile before
			tilemap.set_cell(0, pos, -1)

func _redo_tile_action(action):
	# Get the appropriate tilemap
	var tilemap = _get_tilemap_for_layer(action.layer)
	if not tilemap:
		return
	
	# Apply the action again
	for i in range(action.positions.size()):
		var pos = action.positions[i]
		var new_data = action.new_data[i]
		
		if new_data is Dictionary and "source_id" in new_data:
			# Set tile
			tilemap.set_cell(0, pos, new_data.source_id, new_data.atlas_coords)
		else:
			# Erase tile
			tilemap.set_cell(0, pos, -1)

func _undo_object_action(action):
	# Get object placer
	var object_placer = _get_object_placer()
	if not object_placer:
		return
	
	match action.type:
		ActionType.PLACE_OBJECT:
			# Remove placed objects
			for i in range(action.positions.size()):
				var pos = action.positions[i]
				object_placer.remove_object(pos, action.z_level)
		
		ActionType.ERASE_OBJECT:
			# Restore erased objects
			for i in range(action.old_data.size()):
				var obj_data = action.old_data[i]
				
				# Create and place the object
				object_placer.set_object_type(obj_data.type)
				var pos = action.positions[i]
				var direction = obj_data.direction if "direction" in obj_data else 0
				var obj = object_placer.place_object(pos, action.z_level, direction)
				
				# Restore properties
				if obj and "is_active" in obj_data:
					obj.is_active = obj_data.is_active
					
					# Call appropriate method based on state
					if obj.is_active:
						if obj.has_method("turn_on"):
							obj.turn_on()
					else:
						if obj.has_method("turn_off"):
							obj.turn_off()
		
		ActionType.MODIFY_OBJECT:
			# Restore previous object state
			for i in range(action.object_ids.size()):
				var obj_id = action.object_ids[i]
				var old_data = action.old_data[i]
				
				# Find the object by ID (this depends on your object identification system)
				var obj = _find_object_by_id(obj_id)
				if not obj:
					continue
				
				# Restore properties
				if "facing_direction" in old_data and "facing_direction" in obj:
					obj.facing_direction = old_data.facing_direction
					
					# Update sprite animation
					if obj.has_method("_set_sprite_animation"):
						obj._set_sprite_animation()
				
				if "is_active" in old_data and "is_active" in obj:
					obj.is_active = old_data.is_active
					
					# Call appropriate method based on state
					if obj.is_active:
						if obj.has_method("turn_on"):
							obj.turn_on()
					else:
						if obj.has_method("turn_off"):
							obj.turn_off()
				
				# Update position if needed
				if "grid_position" in old_data:
					var grid_pos = old_data.grid_position
					var z_level = old_data.z_level if "z_level" in old_data else action.z_level
					
					obj.set_meta("grid_position", grid_pos)
					obj.set_meta("z_level", z_level)
					
					# Update actual position
					obj.position = Vector2(
						grid_pos.x * 32 + 16,  # Center in tile
						grid_pos.y * 32 + 16   # Center in tile
					)

func _redo_object_action(action):
	# Get object placer
	var object_placer = _get_object_placer()
	if not object_placer:
		return
	
	match action.type:
		ActionType.PLACE_OBJECT:
			# Restore placed objects
			for i in range(action.new_data.size()):
				var obj_data = action.new_data[i]
				
				# Create and place the object
				object_placer.set_object_type(obj_data.type)
				var pos = action.positions[i]
				var direction = obj_data.direction if "direction" in obj_data else 0
				var obj = object_placer.place_object(pos, action.z_level, direction)
				
				# Set properties
				if obj and "is_active" in obj_data:
					obj.is_active = obj_data.is_active
					
					# Call appropriate method based on state
					if obj.is_active:
						if obj.has_method("turn_on"):
							obj.turn_on()
					else:
						if obj.has_method("turn_off"):
							obj.turn_off()
		
		ActionType.ERASE_OBJECT:
			# Remove objects again
			for i in range(action.positions.size()):
				var pos = action.positions[i]
				object_placer.remove_object(pos, action.z_level)
		
		ActionType.MODIFY_OBJECT:
			# Apply new object state
			for i in range(action.object_ids.size()):
				var obj_id = action.object_ids[i]
				var new_data = action.new_data[i]
				
				# Find the object by ID
				var obj = _find_object_by_id(obj_id)
				if not obj:
					continue
				
				# Apply properties
				if "facing_direction" in new_data and "facing_direction" in obj:
					obj.facing_direction = new_data.facing_direction
					
					# Update sprite animation
					if obj.has_method("_set_sprite_animation"):
						obj._set_sprite_animation()
				
				if "is_active" in new_data and "is_active" in obj:
					obj.is_active = new_data.is_active
					
					# Call appropriate method based on state
					if obj.is_active:
						if obj.has_method("turn_on"):
							obj.turn_on()
					else:
						if obj.has_method("turn_off"):
							obj.turn_off()
				
				# Update position if needed
				if "grid_position" in new_data:
					var grid_pos = new_data.grid_position
					var z_level = new_data.z_level if "z_level" in new_data else action.z_level
					
					obj.set_meta("grid_position", grid_pos)
					obj.set_meta("z_level", z_level)
					
					# Update actual position
					obj.position = Vector2(
						grid_pos.x * 32 + 16,  # Center in tile
						grid_pos.y * 32 + 16   # Center in tile
					)

func _undo_selection_action(action):
	match action.type:
		ActionType.DELETE_SELECTION:
			# Restore deleted selection
			_restore_selection(action.selection_data)
		
		ActionType.PASTE_SELECTION:
			# Remove pasted items
			_delete_selection_at(action.selection_data, action.target_position)

func _redo_selection_action(action):
	match action.type:
		ActionType.DELETE_SELECTION:
			# Delete selection again
			_delete_selection_at(action.selection_data, Vector2i.ZERO)
		
		ActionType.PASTE_SELECTION:
			# Paste selection again
			_paste_selection(action.selection_data, action.target_position)

func _restore_selection(selection_data: Dictionary):
	# Get required references
	var selection_tool = _get_selection_tool()
	if not selection_tool:
		return
	
	# Paste the selection back to its original position
	_paste_selection(selection_data, Vector2i.ZERO)

func _delete_selection_at(selection_data: Dictionary, position: Vector2i):
	# Get tilemaps
	var floor_tilemap = _get_tilemap_for_layer(0)
	var wall_tilemap = _get_tilemap_for_layer(1)
	var objects_tilemap = _get_tilemap_for_layer(2)
	var zone_tilemap = _get_tilemap_for_layer(4)
	
	# Get object placer
	var object_placer = _get_object_placer()
	
	# Process tiles
	if "tiles" in selection_data:
		for layer in selection_data.tiles:
			var layer_num = int(layer)
			var tilemap = _get_tilemap_for_layer(layer_num)
			
			if not tilemap:
				continue
				
			for pos_str in selection_data.tiles[layer]:
				var relative_pos = selection_tool.string_to_vector2i(pos_str)
				var delete_pos = position + relative_pos
				
				# Erase the tile
				tilemap.set_cell(0, delete_pos, -1)
	
	# Process objects
	if "objects" in selection_data and object_placer:
		for obj_data in selection_data.objects:
			var delete_pos = position + obj_data.grid_position
			
			# Remove the object
			object_placer.remove_object(delete_pos, obj_data.z_level)

func _paste_selection(selection_data: Dictionary, position: Vector2i):
	# Get selection tool
	var selection_tool = _get_selection_tool()
	if not selection_tool:
		return
	
	# Use selection tool's paste method
	selection_tool.paste_selection(selection_data, position)

func _get_tilemap_for_layer(layer: int) -> TileMap:
	if not editor_ref:
		return null
	
	match layer:
		0: # Floor
			return editor_ref.floor_tilemap
		1: # Wall
			return editor_ref.wall_tilemap
		2: # Objects
			return editor_ref.objects_tilemap
		4: # Zone
			return editor_ref.zone_tilemap
		_:
			return null

func _get_object_placer():
	if not editor_ref or not "object_placer" in editor_ref:
		return null
	
	return editor_ref.object_placer

func _get_selection_tool():
	if not editor_ref or not "selection_tool" in editor_ref:
		return null
	
	return editor_ref.selection_tool

func _find_object_by_id(obj_id):
	# This function needs to be implemented based on how you track object IDs
	# For now, we'll use a simple approach
	
	var object_placer = _get_object_placer()
	if not object_placer:
		return null
	
	# Loop through all placed objects
	for pos_key in object_placer.placed_objects.keys():
		for obj in object_placer.placed_objects[pos_key]:
			if is_instance_valid(obj) and obj.get_instance_id() == obj_id:
				return obj
	
	return null
