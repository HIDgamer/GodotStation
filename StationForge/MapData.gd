extends Resource
class_name MapData

# Map metadata
@export var map_name: String = "New Map"
@export var author: String = ""
@export var description: String = ""
@export var creation_date: String = ""
@export var last_modified_date: String = ""

# Map dimensions
@export var width: int = 100
@export var height: int = 100
@export var z_levels: int = 3

# Tile and object data storage
# Format: {z_level: {Vector2i: {layer: data}}}
var tile_data = {}

# Object data storage
# Format: {z_level: {unique_id: {type, position, properties}}}
var object_data = {}

# Initialize a new map
func initialize(new_width: int, new_height: int, new_z_levels: int = 3):
	# Set dimensions
	width = new_width
	height = new_height
	z_levels = new_z_levels
	
	# Set creation date
	var datetime = Time.get_datetime_dict_from_system()
	creation_date = "%04d-%02d-%02d %02d:%02d:%02d" % [
		datetime.year, datetime.month, datetime.day,
		datetime.hour, datetime.minute, datetime.second
	]
	last_modified_date = creation_date
	
	# Clear existing data
	tile_data.clear()
	object_data.clear()
	
	# Initialize data dictionaries for each z-level
	for z in range(z_levels):
		tile_data[z] = {}
		object_data[z] = {}

# Set tile data at a specific position
func set_tile(pos: Vector2i, layer: int, data: Dictionary, z_level: int = 0):
	# Ensure z_level exists
	if not z_level in tile_data:
		tile_data[z_level] = {}
	
	# Ensure position exists
	if not pos in tile_data[z_level]:
		tile_data[z_level][pos] = {}
	
	# Set the data for this layer
	tile_data[z_level][pos][layer] = data
	
	# Update modification date
	_update_modification_date()

# Get tile data at a specific position
func get_tile(pos: Vector2i, layer: int, z_level: int = 0) -> Dictionary:
	# Check if data exists
	if z_level in tile_data and pos in tile_data[z_level] and layer in tile_data[z_level][pos]:
		return tile_data[z_level][pos][layer]
	
	# Return empty dictionary if no data
	return {}

# Remove tile data at a specific position
func remove_tile(pos: Vector2i, layer: int, z_level: int = 0) -> bool:
	# Check if data exists
	if z_level in tile_data and pos in tile_data[z_level] and layer in tile_data[z_level][pos]:
		# Remove the data
		tile_data[z_level][pos].erase(layer)
		
		# Remove the position entry if empty
		if tile_data[z_level][pos].is_empty():
			tile_data[z_level].erase(pos)
		
		# Update modification date
		_update_modification_date()
		
		return true
	
	return false

# Add an object
func add_object(object_id: String, type: String, pos: Vector2i, properties: Dictionary, z_level: int = 0):
	# Ensure z_level exists
	if not z_level in object_data:
		object_data[z_level] = {}
	
	# Add object data
	object_data[z_level][object_id] = {
		"type": type,
		"position": pos,
		"properties": properties
	}
	
	# Update modification date
	_update_modification_date()

# Get an object
func get_object(object_id: String, z_level: int = 0) -> Dictionary:
	# Check if object exists
	if z_level in object_data and object_id in object_data[z_level]:
		return object_data[z_level][object_id]
	
	# Return empty dictionary if no data
	return {}

# Remove an object
func remove_object(object_id: String, z_level: int = 0) -> bool:
	# Check if object exists
	if z_level in object_data and object_id in object_data[z_level]:
		# Remove the object
		object_data[z_level].erase(object_id)
		
		# Update modification date
		_update_modification_date()
		
		return true
	
	return false

# Update object properties
func update_object_properties(object_id: String, properties: Dictionary, z_level: int = 0) -> bool:
	# Check if object exists
	if z_level in object_data and object_id in object_data[z_level]:
		# Update properties
		object_data[z_level][object_id].properties = properties
		
		# Update modification date
		_update_modification_date()
		
		return true
	
	return false

# Get all tiles at a z-level
func get_all_tiles(z_level: int = 0) -> Dictionary:
	if z_level in tile_data:
		return tile_data[z_level]
	return {}

# Get all objects at a z-level
func get_all_objects(z_level: int = 0) -> Dictionary:
	if z_level in object_data:
		return object_data[z_level]
	return {}

# Apply tile data to TileMap
func apply_to_tilemaps(floor_map: TileMap, wall_map: TileMap, obj_map: TileMap, zone_map: TileMap, z_level: int = 0):
	# Clear existing tiles
	floor_map.clear()
	wall_map.clear()
	obj_map.clear()
	zone_map.clear()
	
	# Skip if z-level doesn't exist
	if not z_level in tile_data:
		return
	
	# Apply tiles from map data
	for pos in tile_data[z_level]:
		var pos_data = tile_data[z_level][pos]
		
		# Apply floor tiles
		if 0 in pos_data: # TileLayer.FLOOR
			var floor_data = pos_data[0]
			if "source_id" in floor_data and "atlas_coords" in floor_data:
				floor_map.set_cell(0, pos, floor_data.source_id, floor_data.atlas_coords)
		
		# Apply wall tiles
		if 1 in pos_data: # TileLayer.WALL
			var wall_data = pos_data[1]
			if "source_id" in wall_data and "atlas_coords" in wall_data:
				wall_map.set_cell(0, pos, wall_data.source_id, wall_data.atlas_coords)
		
		# Apply object tiles
		if 2 in pos_data: # Objects layer
			var obj_data = pos_data[2]
			if "source_id" in obj_data and "atlas_coords" in obj_data:
				obj_map.set_cell(0, pos, obj_data.source_id, obj_data.atlas_coords)
		
		# Apply zone tiles
		if 4 in pos_data: # Zone layer (using atmosphere layer index)
			var zone_data = pos_data[4]
			if "source_id" in zone_data and "atlas_coords" in zone_data:
				zone_map.set_cell(0, pos, zone_data.source_id, zone_data.atlas_coords)

# Create tile data from TileMap
func create_from_tilemaps(floor_map: TileMap, wall_map: TileMap, obj_map: TileMap, zone_map: TileMap, z_level: int = 0):
	# Initialize or clear z_level data
	if not z_level in tile_data:
		tile_data[z_level] = {}
	else:
		tile_data[z_level].clear()
	
	# Process floor tiles
	for pos in floor_map.get_used_cells(0):
		var source_id = floor_map.get_cell_source_id(0, pos)
		var atlas_coords = floor_map.get_cell_atlas_coords(0, pos)
		
		# Create position entry if needed
		if not pos in tile_data[z_level]:
			tile_data[z_level][pos] = {}
		
		# Store floor tile data
		tile_data[z_level][pos][0] = { # TileLayer.FLOOR
			"source_id": source_id,
			"atlas_coords": atlas_coords,
			"type": "floor" # Default type
		}
	
	# Process wall tiles
	for pos in wall_map.get_used_cells(0):
		var source_id = wall_map.get_cell_source_id(0, pos)
		var atlas_coords = wall_map.get_cell_atlas_coords(0, pos)
		
		# Create position entry if needed
		if not pos in tile_data[z_level]:
			tile_data[z_level][pos] = {}
		
		# Store wall tile data
		tile_data[z_level][pos][1] = { # TileLayer.WALL
			"source_id": source_id,
			"atlas_coords": atlas_coords,
			"type": "wall" # Default type
		}
	
	# Process object tiles
	for pos in obj_map.get_used_cells(0):
		var source_id = obj_map.get_cell_source_id(0, pos)
		var atlas_coords = obj_map.get_cell_atlas_coords(0, pos)
		
		# Create position entry if needed
		if not pos in tile_data[z_level]:
			tile_data[z_level][pos] = {}
		
		# Store object tile data
		tile_data[z_level][pos][2] = { # Objects layer
			"source_id": source_id,
			"atlas_coords": atlas_coords,
			"type": "object" # Default type
		}
	
	# Process zone tiles
	for pos in zone_map.get_used_cells(0):
		var source_id = zone_map.get_cell_source_id(0, pos)
		var atlas_coords = zone_map.get_cell_atlas_coords(0, pos)
		
		# Create position entry if needed
		if not pos in tile_data[z_level]:
			tile_data[z_level][pos] = {}
		
		# Store zone tile data
		tile_data[z_level][pos][4] = { # Using Atmosphere layer index
			"source_id": source_id,
			"atlas_coords": atlas_coords,
			"has_gravity": true, # Default
			"has_atmosphere": true # Default
		}
	
	# Update modification date
	_update_modification_date()

# Update the last modified date
func _update_modification_date():
	var datetime = Time.get_datetime_dict_from_system()
	last_modified_date = "%04d-%02d-%02d %02d:%02d:%02d" % [
		datetime.year, datetime.month, datetime.day,
		datetime.hour, datetime.minute, datetime.second
	]

# Save map to file
func save_to_file(path: String) -> Error:
	return ResourceSaver.save(self, path)

# Load map from file
static func load_from_file(path: String) -> MapData:
	if FileAccess.file_exists(path):
		var resource = ResourceLoader.load(path)
		if resource is MapData:
			return resource
	return null

# Export to game format
func export_to_game_format(path: String) -> Error:
	# Create a JSON representation compatible with your game
	var game_data = {
		"map_name": map_name,
		"author": author,
		"description": description,
		"creation_date": creation_date,
		"last_modified_date": last_modified_date,
		"width": width,
		"height": height,
		"z_levels": z_levels,
		"tile_data": {},
		"object_data": {}
	}
	
	# Convert tile data to game format
	for z in tile_data:
		game_data.tile_data[str(z)] = {}
		for pos_key in tile_data[z]:
			var pos_str = str(pos_key.x) + "_" + str(pos_key.y)
			game_data.tile_data[str(z)][pos_str] = tile_data[z][pos_key]
	
	# Convert object data to game format
	for z in object_data:
		game_data.object_data[str(z)] = object_data[z]
	
	# Convert to JSON
	var json_string = JSON.stringify(game_data, "  ")
	
	# Save to file
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		return OK
	
	return ERR_CANT_CREATE
