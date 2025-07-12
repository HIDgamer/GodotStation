extends Node
class_name MapExporter

signal export_started(map_name)
signal export_completed(success, message)
signal export_progress(percent, status_message)

# Export settings
var game_export_path: String = "res://exports/"
var default_export_format: String = "json" # json, binary, tscn
var include_metadata: bool = true
var optimize_export: bool = true
var compress_export: bool = false

# References
var editor_ref = null

func _init():
	# Try to get editor reference
	if Engine.has_singleton("Editor"):
		editor_ref = Engine.get_singleton("Editor")

func export_map(map_data: MapData, export_path: String, format: String = default_export_format) -> Error:
	# Emit start signal
	emit_signal("export_started", map_data.map_name)
	
	# Create export directory if it doesn't exist
	var dir = DirAccess.open("res://")
	if not dir.dir_exists(export_path.get_base_dir()):
		dir.make_dir_recursive(export_path.get_base_dir())
	
	# Export based on format
	var result = OK
	
	match format:
		"json":
			result = export_to_json(map_data, export_path)
		"binary":
			result = export_to_binary(map_data, export_path)
		"tscn":
			result = export_to_scene(map_data, export_path)
		_:
			result = export_to_json(map_data, export_path)
	
	# Emit completion signal
	if result == OK:
		emit_signal("export_completed", true, "Map exported successfully to " + export_path)
	else:
		emit_signal("export_completed", false, "Error exporting map: " + str(result))
	
	return result

func export_to_json(map_data: MapData, export_path: String) -> Error:
	# Convert map data to JSON format
	emit_signal("export_progress", 10, "Converting map data to JSON...")
	
	var json_data = _convert_map_to_json_data(map_data)
	
	# Create JSON string
	emit_signal("export_progress", 50, "Creating JSON file...")
	var json_string = JSON.stringify(json_data, "  ")
	
	# Save to file
	emit_signal("export_progress", 80, "Saving JSON file...")
	var file = FileAccess.open(export_path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		
		emit_signal("export_progress", 100, "JSON export complete")
		return OK
	
	return ERR_CANT_CREATE

func export_to_binary(map_data: MapData, export_path: String) -> Error:
	# Save map data as binary resource
	emit_signal("export_progress", 30, "Creating binary resource...")
	
	# Prepare map data
	if optimize_export:
		optimize_map_data(map_data)
	
	# Save to file
	emit_signal("export_progress", 70, "Saving binary resource...")
	var result = ResourceSaver.save(map_data, export_path, ResourceSaver.FLAG_COMPRESS if compress_export else 0)
	
	emit_signal("export_progress", 100, "Binary export complete")
	return result

func export_to_scene(map_data: MapData, export_path: String) -> Error:
	# Create a new scene for the map
	emit_signal("export_progress", 10, "Creating scene...")
	
	var scene_root = Node2D.new()
	scene_root.name = "Map"
	
	# Add tilemaps
	emit_signal("export_progress", 20, "Adding tilemaps...")
	
	# Add floor tilemap
	var floor_tilemap = TileMap.new()
	floor_tilemap.name = "FloorTileMap"
	floor_tilemap.tile_set = TilesetManager.get_floor_tileset()
	scene_root.add_child(floor_tilemap)
	floor_tilemap.owner = scene_root
	
	# Add wall tilemap
	var wall_tilemap = TileMap.new()
	wall_tilemap.name = "WallTileMap"
	wall_tilemap.tile_set = TilesetManager.get_wall_tileset()
	scene_root.add_child(wall_tilemap)
	wall_tilemap.owner = scene_root
	
	# Add objects tilemap
	var objects_tilemap = TileMap.new()
	objects_tilemap.name = "ObjectsTileMap"
	objects_tilemap.tile_set = TilesetManager.get_object_tileset()
	scene_root.add_child(objects_tilemap)
	objects_tilemap.owner = scene_root
	
	# Add zone tilemap
	var zone_tilemap = TileMap.new()
	zone_tilemap.name = "ZoneTileMap"
	zone_tilemap.tile_set = TilesetManager.get_zone_tileset()
	zone_tilemap.modulate = Color(1, 1, 0, 0.3)  # Yellow tint
	scene_root.add_child(zone_tilemap)
	zone_tilemap.owner = scene_root
	
	# Add objects container
	var objects_container = Node2D.new()
	objects_container.name = "PlacedObjects"
	scene_root.add_child(objects_container)
	objects_container.owner = scene_root
	
	# Apply tile data
	emit_signal("export_progress", 40, "Adding tile data...")
	map_data.apply_to_tilemaps(floor_tilemap, wall_tilemap, objects_tilemap, zone_tilemap)
	
	# Add placed objects
	emit_signal("export_progress", 60, "Adding placed objects...")
	_add_objects_to_scene(map_data, objects_container, scene_root)
	
	# Add metadata
	if include_metadata:
		_add_metadata_to_scene(map_data, scene_root)
	
	# Pack the scene
	emit_signal("export_progress", 80, "Packing scene...")
	var packed_scene = PackedScene.new()
	var result = packed_scene.pack(scene_root)
	
	if result != OK:
		return result
	
	# Save to file
	emit_signal("export_progress", 90, "Saving scene...")
	result = ResourceSaver.save(packed_scene, export_path)
	
	emit_signal("export_progress", 100, "Scene export complete")
	return result

func optimize_map_data(map_data: MapData):
	# Optimize map data for export
	# - Remove empty positions
	# - Combine adjacent tiles with same properties
	
	# Optimize tile data
	for z in map_data.tile_data.keys():
		var z_level_data = map_data.tile_data[z]
		var positions_to_remove = []
		
		# Identify empty positions
		for pos in z_level_data.keys():
			if z_level_data[pos].is_empty():
				positions_to_remove.append(pos)
		
		# Remove empty positions
		for pos in positions_to_remove:
			z_level_data.erase(pos)
	
	# Optimize object data
	for z in map_data.object_data.keys():
		var z_level_data = map_data.object_data[z]
		var ids_to_remove = []
		
		# Identify objects with no data
		for obj_id in z_level_data.keys():
			if z_level_data[obj_id].is_empty():
				ids_to_remove.append(obj_id)
		
		# Remove empty entries
		for obj_id in ids_to_remove:
			z_level_data.erase(obj_id)

func _convert_map_to_json_data(map_data: MapData) -> Dictionary:
	# Convert MapData to serializable Dictionary
	var json_data = {
		"map_name": map_data.map_name,
		"author": map_data.author,
		"description": map_data.description,
		"creation_date": map_data.creation_date,
		"last_modified_date": map_data.last_modified_date,
		"width": map_data.width,
		"height": map_data.height,
		"z_levels": map_data.z_levels,
		"tile_data": {},
		"object_data": {}
	}
	
	# Convert tile data
	for z in map_data.tile_data:
		json_data.tile_data[str(z)] = {}
		
		for pos in map_data.tile_data[z]:
			# Convert Vector2i to string
			var pos_str = str(pos.x) + "," + str(pos.y)
			
			# Convert tile data
			json_data.tile_data[str(z)][pos_str] = map_data.tile_data[z][pos]
	
	# Convert object data
	json_data.object_data = map_data.object_data.duplicate(true)
	
	return json_data

func _add_objects_to_scene(map_data: MapData, objects_container: Node2D, scene_root: Node):
	# Add placed objects to scene
	if not "object_data" in map_data:
		return
	
	for z in map_data.object_data.keys():
		var z_level_objects = map_data.object_data[z]
		
		for obj_id in z_level_objects.keys():
			var obj_data = z_level_objects[obj_id]
			
			# Skip if missing required data
			if not "type" in obj_data or not "position" in obj_data:
				continue
			
			# Get object scene
			var object_type = obj_data.type
			if not object_type in TileDefinitions.PLACEABLE_OBJECTS:
				continue
				
			var scene_path = TileDefinitions.PLACEABLE_OBJECTS[object_type].scene_path
			var object_scene = load(scene_path)
			
			if not object_scene:
				continue
			
			# Instantiate object
			var object_instance = object_scene.instantiate()
			
			# Set position
			var pos = obj_data.position
			object_instance.position = Vector2(
				pos.x * 32 + 16,  # Center in tile
				pos.y * 32 + 16   # Center in tile
			)
			
			# Set metadata
			object_instance.set_meta("grid_position", Vector2i(pos.x, pos.y))
			object_instance.set_meta("z_level", int(z))
			object_instance.set_meta("object_type", object_type)
			
			# Set direction if applicable
			if "direction" in obj_data and "facing_direction" in object_instance:
				object_instance.facing_direction = obj_data.direction
				
				# Update sprite animation
				if object_instance.has_method("_set_sprite_animation"):
					object_instance._set_sprite_animation()
			
			# Set active state if applicable
			if "is_active" in obj_data and "is_active" in object_instance:
				object_instance.is_active = obj_data.is_active
				
				# Call appropriate method based on state
				if obj_data.is_active:
					if object_instance.has_method("turn_on"):
						object_instance.turn_on()
				else:
					if object_instance.has_method("turn_off"):
						object_instance.turn_off()
			
			# Add to container
			objects_container.add_child(object_instance)
			object_instance.owner = scene_root

func _add_metadata_to_scene(map_data: MapData, scene_root: Node):
	# Add metadata to scene
	var metadata = Node.new()
	metadata.name = "MapMetadata"
	scene_root.add_child(metadata)
	metadata.owner = scene_root
	
	# Add metadata properties
	metadata.set_meta("map_name", map_data.map_name)
	metadata.set_meta("author", map_data.author)
	metadata.set_meta("description", map_data.description)
	metadata.set_meta("creation_date", map_data.creation_date)
	metadata.set_meta("last_modified_date", map_data.last_modified_date)
	metadata.set_meta("width", map_data.width)
	metadata.set_meta("height", map_data.height)
	metadata.set_meta("z_levels", map_data.z_levels)

func import_map_from_game(game_path: String) -> MapData:
	# Import a map from the game
	var map_data = MapData.new()
	
	# Check file extension
	var extension = game_path.get_extension()
	
	match extension:
		"json":
			_import_from_json(map_data, game_path)
		"tres", "res":
			_import_from_binary(map_data, game_path)
		"tscn":
			_import_from_scene(map_data, game_path)
		_:
			return null
	
	return map_data

func _import_from_json(map_data: MapData, json_path: String) -> Error:
	# Import from JSON file
	if not FileAccess.file_exists(json_path):
		return ERR_FILE_NOT_FOUND
	
	# Read JSON file
	var file = FileAccess.open(json_path, FileAccess.READ)
	if not file:
		return ERR_CANT_OPEN
	
	var json_string = file.get_as_text()
	file.close()
	
	# Parse JSON
	var json = JSON.new()
	var result = json.parse(json_string)
	if result != OK:
		return result
	
	var data = json.get_data()
	
	# Import metadata
	if "map_name" in data:
		map_data.map_name = data.map_name
	if "author" in data:
		map_data.author = data.author
	if "description" in data:
		map_data.description = data.description
	if "creation_date" in data:
		map_data.creation_date = data.creation_date
	if "last_modified_date" in data:
		map_data.last_modified_date = data.last_modified_date
	if "width" in data:
		map_data.width = data.width
	if "height" in data:
		map_data.height = data.height
	if "z_levels" in data:
		map_data.z_levels = data.z_levels
	
	# Import tile data
	if "tile_data" in data:
		for z_str in data.tile_data:
			var z = int(z_str)
			map_data.tile_data[z] = {}
			
			for pos_str in data.tile_data[z_str]:
				var parts = pos_str.split(",")
				if parts.size() >= 2:
					var x = int(parts[0])
					var y = int(parts[1])
					var pos = Vector2i(x, y)
					
					map_data.tile_data[z][pos] = data.tile_data[z_str][pos_str]
	
	# Import object data
	if "object_data" in data:
		map_data.object_data = data.object_data.duplicate(true)
	
	return OK

func _import_from_binary(map_data: MapData, binary_path: String) -> Error:
	# Import from binary resource file
	if not ResourceLoader.exists(binary_path):
		return ERR_FILE_NOT_FOUND
	
	var loaded_map = ResourceLoader.load(binary_path)
	if not loaded_map is MapData:
		return ERR_INVALID_DATA
	
	# Copy data
	map_data.map_name = loaded_map.map_name
	map_data.author = loaded_map.author
	map_data.description = loaded_map.description
	map_data.creation_date = loaded_map.creation_date
	map_data.last_modified_date = loaded_map.last_modified_date
	map_data.width = loaded_map.width
	map_data.height = loaded_map.height
	map_data.z_levels = loaded_map.z_levels
	map_data.tile_data = loaded_map.tile_data.duplicate(true)
	
	if "object_data" in loaded_map:
		map_data.object_data = loaded_map.object_data.duplicate(true)
	
	return OK

func _import_from_scene(map_data: MapData, scene_path: String) -> Error:
	# Import from scene file
	if not ResourceLoader.exists(scene_path):
		return ERR_FILE_NOT_FOUND
	
	var scene = ResourceLoader.load(scene_path)
	if not scene is PackedScene:
		return ERR_INVALID_DATA
	
	# Instantiate scene to extract data
	var instance = scene.instantiate()
	
	# Get metadata if available
	var metadata_node = instance.get_node_or_null("MapMetadata")
	if metadata_node:
		map_data.map_name = metadata_node.get_meta("map_name", "Imported Map")
		map_data.author = metadata_node.get_meta("author", "")
		map_data.description = metadata_node.get_meta("description", "")
		map_data.creation_date = metadata_node.get_meta("creation_date", "")
		map_data.last_modified_date = metadata_node.get_meta("last_modified_date", "")
		map_data.width = metadata_node.get_meta("width", 100)
		map_data.height = metadata_node.get_meta("height", 100)
		map_data.z_levels = metadata_node.get_meta("z_levels", 3)
	
	# Get tile data from tilemaps
	var floor_tilemap = instance.get_node_or_null("FloorTileMap")
	var wall_tilemap = instance.get_node_or_null("WallTileMap")
	var objects_tilemap = instance.get_node_or_null("ObjectsTileMap")
	var zone_tilemap = instance.get_node_or_null("ZoneTileMap")
	
	# Extract tile data
	map_data.create_from_tilemaps(floor_tilemap, wall_tilemap, objects_tilemap, zone_tilemap)
	
	# Extract placed objects data
	var objects_container = instance.get_node_or_null("PlacedObjects")
	if objects_container:
		_extract_objects_data(map_data, objects_container)
	
	# Free the instance
	instance.queue_free()
	
	return OK

func _extract_objects_data(map_data: MapData, objects_container: Node):
	# Initialize object data
	map_data.object_data = {}
	
	# Process all object children
	for z in range(map_data.z_levels):
		map_data.object_data[z] = {}
	
	for obj in objects_container.get_children():
		# Skip if not a valid object
		if not "object_type" in obj.get_meta_list():
			continue
		
		var object_type = obj.get_meta("object_type")
		var grid_pos = obj.get_meta("grid_position", Vector2i.ZERO)
		var z_level = obj.get_meta("z_level", 0)
		
		# Create unique ID for object
		var obj_id = str(object_type) + "_" + str(grid_pos.x) + "_" + str(grid_pos.y) + "_" + str(z_level)
		
		# Create object data
		var obj_data = {
			"type": object_type,
			"position": {
				"x": grid_pos.x,
				"y": grid_pos.y
			}
		}
		
		# Add direction if applicable
		if "facing_direction" in obj:
			obj_data["direction"] = obj.facing_direction
		
		# Add active state if applicable
		if "is_active" in obj:
			obj_data["is_active"] = obj.is_active
		
		# Add to map data
		if not z_level in map_data.object_data:
			map_data.object_data[z_level] = {}
		
		map_data.object_data[z_level][obj_id] = obj_data
