extends Node
class_name TilePlacementSystem

# References
var editor_ref = null
var tileset_manager = null

# Tile maps
var floor_tilemap = null
var wall_tilemap = null
var objects_tilemap = null
var zone_tilemap = null

# Current selection
var current_layer = 0
var current_tile_id = -1
var current_tile_type = ""
var current_atlas_coords = Vector2i(0, 0)
var current_terrain_id = -1

# Undo/redo system
var undo_stack = []
var redo_stack = []
var max_undo_steps = 100

# Initialize the system
func _ready():
	# This will be called when the node is added to the scene tree
	pass

# Initialize tilemaps from the editor
func initialize_tilemaps():
	if not editor_ref:
		push_error("TilePlacementSystem: No editor reference!")
		return
		
	floor_tilemap = editor_ref.get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport/FloorTileMap")
	wall_tilemap = editor_ref.get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport/WallTileMap")
	objects_tilemap = editor_ref.get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport/ObjectsTileMap")
	zone_tilemap = editor_ref.get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport/ZoneTileMap")
	
	if not floor_tilemap or not wall_tilemap or not objects_tilemap or not zone_tilemap:
		push_error("TilePlacementSystem: One or more tilemaps not found!")
		if not floor_tilemap: push_error("  - FloorTileMap missing")
		if not wall_tilemap: push_error("  - WallTileMap missing")
		if not objects_tilemap: push_error("  - ObjectsTileMap missing")
		if not zone_tilemap: push_error("  - ZoneTileMap missing")

# Set current layer
func set_current_layer(layer: int):
	current_layer = layer

# Set current tile
func set_current_tile(tile_id: int, tile_type: String, atlas_coords: Vector2i, terrain_id: int = -1):
	current_tile_id = tile_id
	current_tile_type = tile_type
	current_atlas_coords = atlas_coords
	current_terrain_id = terrain_id

# Place a tile at the given position - More debug output
func place_tile(position: Vector2i, z_level: int):
	print("TilePlacementSystem: Attempting to place tile at position ", position)
	print("  current_tile_id: ", current_tile_id)
	print("  current_tile_type: ", current_tile_type)
	print("  current_layer: ", current_layer)
	
	if current_tile_id == -1 or current_tile_type == "":
		print("TilePlacementSystem: No tile selected!")
		return false
	
	var tilemap = get_tilemap_for_layer(current_layer)
	if not tilemap:
		print("TilePlacementSystem: No tilemap found for layer ", current_layer)
		return false
	
	# Debug checks for the tilemap
	if not tilemap.tile_set:
		print("TilePlacementSystem: Tilemap has no tileset!")
		return false
	
	print("TilePlacementSystem: Placing tile with ID ", current_tile_id, " at ", position)
	
	# Remember old state for undo
	var old_source_id = tilemap.get_cell_source_id(0, position)
	var old_atlas_coords = tilemap.get_cell_atlas_coords(0, position)
	var old_alternative = tilemap.get_cell_alternative_tile(0, position)
	
	# Place the tile directly for now
	tilemap.set_cell(0, position, current_tile_id, current_atlas_coords)
	
	print("TilePlacementSystem: Tile placed successfully")
	
	# Add to undo stack
	add_to_undo_stack({
		"action": "place_tile",
		"layer": current_layer,
		"position": position,
		"z_level": z_level,
		"old_source_id": old_source_id,
		"old_atlas_coords": old_atlas_coords,
		"old_alternative": old_alternative,
		"new_source_id": current_tile_id,
		"new_atlas_coords": current_atlas_coords
	})
	
	return true

# Erase a tile at the given position
func erase_tile(position: Vector2i, z_level: int):
	var tilemap = get_tilemap_for_layer(current_layer)
	if not tilemap:
		return false
	
	# Remember old state for undo
	var old_source_id = tilemap.get_cell_source_id(0, position)
	var old_atlas_coords = tilemap.get_cell_atlas_coords(0, position)
	var old_alternative = tilemap.get_cell_alternative_tile(0, position)
	
	# Skip if already empty
	if old_source_id == -1:
		return false
	
	# Get the layer type for auto-tiling
	var layer_type = get_layer_type(current_layer)
	
	# Erase the tile
	tilemap.set_cell(0, position, -1)
	
	# If using terrain-based autotiling, update surrounding tiles
	if tileset_manager and layer_type != "":
		tileset_manager.update_surrounding_tiles(tilemap, position, layer_type)
	
	# Add to undo stack
	add_to_undo_stack({
		"action": "erase_tile",
		"layer": current_layer,
		"position": position,
		"z_level": z_level,
		"old_source_id": old_source_id,
		"old_atlas_coords": old_atlas_coords,
		"old_alternative": old_alternative
	})
	
	return true

# Fill an area with the current tile type
func fill_area(position: Vector2i, z_level: int):
	var tilemap = get_tilemap_for_layer(current_layer)
	if not tilemap or current_tile_id == -1 or current_tile_type == "":
		return false
	
	# Get target value to replace
	var target_source_id = tilemap.get_cell_source_id(0, position)
	var target_atlas_coords = Vector2i(-1, -1)
	if target_source_id != -1:
		target_atlas_coords = tilemap.get_cell_atlas_coords(0, position)
	
	# Don't fill if the target is already the current tile
	if target_source_id == current_tile_id and target_atlas_coords == current_atlas_coords:
		return false
	
	# Remember all changes for undo
	var changes = []
	
	# Fill similar tiles
	var fill_cells = []
	var check_cells = [position]
	var checked_cells = {}
	
	while check_cells.size() > 0:
		var pos = check_cells.pop_front()
		
		# Skip if already checked
		if pos in checked_cells:
			continue
		
		checked_cells[pos] = true
		
		# Check if cell matches what we're looking for
		var current_source_id = tilemap.get_cell_source_id(0, pos)
		
		var matches = false
		if current_source_id == target_source_id:
			if target_source_id == -1 or tilemap.get_cell_atlas_coords(0, pos) == target_atlas_coords:
				matches = true
		
		if matches:
			fill_cells.append(pos)
			
			# Remember old state for undo
			changes.append({
				"position": pos,
				"old_source_id": current_source_id,
				"old_atlas_coords": tilemap.get_cell_atlas_coords(0, pos),
				"old_alternative": tilemap.get_cell_alternative_tile(0, pos)
			})
			
			# Add neighbors to check
			check_cells.append(Vector2i(pos.x + 1, pos.y))
			check_cells.append(Vector2i(pos.x - 1, pos.y))
			check_cells.append(Vector2i(pos.x, pos.y + 1))
			check_cells.append(Vector2i(pos.x, pos.y - 1))
	
	# Get the layer type for auto-tiling
	var layer_type = get_layer_type(current_layer)
	
	# Fill all matching cells
	for pos in fill_cells:
		tilemap.set_cell(0, pos, current_tile_id, current_atlas_coords)
	
	# If using terrain-based autotiling, update all modified tiles
	if tileset_manager and layer_type != "":
		for pos in fill_cells:
			# Auto-connect the terrain
			var new_coords = tileset_manager.auto_connect_terrain(
				tilemap, pos, layer_type, current_tile_id, current_atlas_coords
			)
			
			# Update the tile with connected coordinates
			tilemap.set_cell(0, pos, current_tile_id, new_coords)
	
	# Add to undo stack
	if changes.size() > 0:
		add_to_undo_stack({
			"action": "fill_area",
			"layer": current_layer,
			"z_level": z_level,
			"changes": changes,
			"new_source_id": current_tile_id,
			"new_atlas_coords": current_atlas_coords
		})
	
	return true

# Draw a line of tiles from start to end
func draw_line(start: Vector2i, end: Vector2i, z_level: int):
	var tilemap = get_tilemap_for_layer(current_layer)
	if not tilemap or current_tile_id == -1 or current_tile_type == "":
		return false
	
	# Get the line points
	var line_points = get_line_points(start, end)
	
	# Remember all changes for undo
	var changes = []
	
	# Get the layer type for auto-tiling
	var layer_type = get_layer_type(current_layer)
	
	# Place tiles along the line
	for pos in line_points:
		# Remember old state for undo
		changes.append({
			"position": pos,
			"old_source_id": tilemap.get_cell_source_id(0, pos),
			"old_atlas_coords": tilemap.get_cell_atlas_coords(0, pos),
			"old_alternative": tilemap.get_cell_alternative_tile(0, pos)
		})
		
		# Set the tile
		tilemap.set_cell(0, pos, current_tile_id, current_atlas_coords)
	
	# If using terrain-based autotiling, update all modified tiles
	if tileset_manager and layer_type != "":
		for pos in line_points:
			# Auto-connect the terrain
			var new_coords = tileset_manager.auto_connect_terrain(
				tilemap, pos, layer_type, current_tile_id, current_atlas_coords
			)
			
			# Update the tile with connected coordinates
			tilemap.set_cell(0, pos, current_tile_id, new_coords)
	
	# Add to undo stack
	if changes.size() > 0:
		add_to_undo_stack({
			"action": "draw_line",
			"layer": current_layer,
			"z_level": z_level,
			"changes": changes,
			"new_source_id": current_tile_id,
			"new_atlas_coords": current_atlas_coords
		})
	
	return true

# Get the tilemap for the current layer
func get_tilemap_for_layer(layer: int):
	match layer:
		0: return floor_tilemap
		1: return wall_tilemap
		2: return objects_tilemap
		4: return zone_tilemap
	return null

# Get the layer type name for auto-tiling
func get_layer_type(layer: int) -> String:
	match layer:
		0: return "floor"
		1: return "wall"
		2: return "object"
		4: return "zone"
	return ""

# Add an action to the undo stack
func add_to_undo_stack(action):
	undo_stack.append(action)
	redo_stack.clear()
	
	# Limit undo stack size
	if undo_stack.size() > max_undo_steps:
		undo_stack.pop_front()

# Undo the last action
func undo():
	if undo_stack.size() == 0:
		return false
	
	var action = undo_stack.pop_back()
	redo_stack.append(action)
	
	match action.action:
		"place_tile", "erase_tile":
			var tilemap = get_tilemap_for_layer(action.layer)
			if tilemap:
				if action.old_source_id == -1:
					tilemap.set_cell(0, action.position, -1)
				else:
					tilemap.set_cell(0, action.position, action.old_source_id, action.old_atlas_coords, action.old_alternative)
				
				# If using terrain-based autotiling, update surrounding tiles
				var layer_type = get_layer_type(action.layer)
				if tileset_manager and layer_type != "":
					tileset_manager.update_surrounding_tiles(tilemap, action.position, layer_type)
		
		"fill_area", "draw_line":
			var tilemap = get_tilemap_for_layer(action.layer)
			if tilemap:
				for change in action.changes:
					if change.old_source_id == -1:
						tilemap.set_cell(0, change.position, -1)
					else:
						tilemap.set_cell(0, change.position, change.old_source_id, change.old_atlas_coords, change.old_alternative)
				
				# If using terrain-based autotiling, update all affected tiles
				var layer_type = get_layer_type(action.layer)
				if tileset_manager and layer_type != "":
					for change in action.changes:
						tileset_manager.update_surrounding_tiles(tilemap, change.position, layer_type)
	
	return true

# Redo the last undone action
func redo():
	if redo_stack.size() == 0:
		return false
	
	var action = redo_stack.pop_back()
	undo_stack.append(action)
	
	match action.action:
		"place_tile":
			var tilemap = get_tilemap_for_layer(action.layer)
			if tilemap:
				tilemap.set_cell(0, action.position, action.new_source_id, action.new_atlas_coords)
				
				# If using terrain-based autotiling, update surrounding tiles
				var layer_type = get_layer_type(action.layer)
				if tileset_manager and layer_type != "":
					tileset_manager.update_surrounding_tiles(tilemap, action.position, layer_type)
		
		"erase_tile":
			var tilemap = get_tilemap_for_layer(action.layer)
			if tilemap:
				tilemap.set_cell(0, action.position, -1)
				
				# If using terrain-based autotiling, update surrounding tiles
				var layer_type = get_layer_type(action.layer)
				if tileset_manager and layer_type != "":
					tileset_manager.update_surrounding_tiles(tilemap, action.position, layer_type)
		
		"fill_area", "draw_line":
			var tilemap = get_tilemap_for_layer(action.layer)
			if tilemap:
				for change in action.changes:
					tilemap.set_cell(0, change.position, action.new_source_id, action.new_atlas_coords)
				
				# If using terrain-based autotiling, update all affected tiles
				var layer_type = get_layer_type(action.layer)
				if tileset_manager and layer_type != "":
					for change in action.changes:
						# Auto-connect the terrain
						var new_coords = tileset_manager.auto_connect_terrain(
							tilemap, change.position, layer_type, action.new_source_id, action.new_atlas_coords
						)
						
						# Update the tile with connected coordinates
						tilemap.set_cell(0, change.position, action.new_source_id, new_coords)
	
	return true

# Get line points using Bresenham's algorithm
func get_line_points(start: Vector2i, end: Vector2i) -> Array:
	var points = []
	
	var x0 = start.x
	var y0 = start.y
	var x1 = end.x
	var y1 = end.y
	
	var dx = abs(x1 - x0)
	var dy = -abs(y1 - y0)
	var sx = 1 if x0 < x1 else -1
	var sy = 1 if y0 < y1 else -1
	var err = dx + dy
	
	while true:
		points.append(Vector2i(x0, y0))
		
		if x0 == x1 and y0 == y1:
			break
		
		var e2 = 2 * err
		if e2 >= dy:
			if x0 == x1:
				break
			err += dy
			x0 += sx
		
		if e2 <= dx:
			if y0 == y1:
				break
			err += dx
			y0 += sy
	
	return points
