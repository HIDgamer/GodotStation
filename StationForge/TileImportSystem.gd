extends Node
class_name TileImportSystem

# Signals
signal tile_import_completed(tile_type, tile_count)
signal tileset_import_completed(tileset_name)
signal import_failed(error_message)
signal tile_library_updated()

# References
var editor_ref = null
var tileset_manager = null

# Constants
const TILE_SIZE = 32

# Import settings
var import_settings = {
	"source_dir": "res://",
	"output_dir": "res://Assets/Tilesets/",
	"auto_slice": true,
	"slice_size": Vector2i(TILE_SIZE, TILE_SIZE),
	"generate_autotile": true,
	"default_terrain_type": "match_corners",
	"process_normal_maps": false,
	"import_metadata_file": true
}

# Tile library - stores all available tiles
var tile_library = {
	"floor": {},
	"wall": {},
	"object": {},
	"zone": {}
}

# Default metadata template
var default_tile_metadata = {
	"name": "New Tile",
	"category": "floor",
	"subcategory": "metal",
	"properties": {
		"collision": false,
		"health": 100,
		"material": "metal"
	},
	"variants": [],
	"autotile_info": {
		"type": "none",
		"terrain_set": 0,
		"terrain_id": 0
	}
}

# File utilities
var file_dialog = null
var image_processor = null

func _ready():
	# Initialize file utilities
	_initialize_file_dialog()
	
	# Create image processor
	image_processor = ImageProcessor.new()
	add_child(image_processor)
	image_processor.connect("processing_failed", Callable(self, "_on_processing_failed"))
	
	# Ensure output directories exist
	_ensure_output_directories()
	
	# Load existing tile library
	load_tile_library()
	
	print("TileImportSystem: Initialized")

func initialize(p_editor_ref, p_tileset_manager):
	editor_ref = p_editor_ref
	tileset_manager = p_tileset_manager
	print("TileImportSystem: References set - editor:", editor_ref != null, " tileset_manager:", tileset_manager != null)

func _initialize_file_dialog():
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Image Files", "*.json ; Metadata Files"])
	file_dialog.title = "Import Tiles"
	file_dialog.connect("files_selected", Callable(self, "_on_files_selected"))
	
	# Add to the editor UI
	if editor_ref:
		var ui_layer = editor_ref.get_node_or_null("UI")
		if ui_layer:
			ui_layer.add_child(file_dialog)

func _ensure_output_directories():
	var dir = DirAccess.open("res://")
	if not dir:
		print("TileImportSystem: Failed to open base directory")
		return
	
	# Create main output directory
	var output_dir = import_settings.output_dir
	if not DirAccess.dir_exists_absolute(output_dir):
		dir.make_dir_recursive(output_dir)
	
	# Create textures subdirectory
	var textures_dir = output_dir + "textures/"
	if not DirAccess.dir_exists_absolute(textures_dir):
		dir.make_dir_recursive(textures_dir)
	
	# Create category subdirectories
	for category in ["floor", "wall", "object", "zone"]:
		var category_dir = textures_dir + category + "/"
		if not DirAccess.dir_exists_absolute(category_dir):
			dir.make_dir_recursive(category_dir)

func _on_processing_failed(error_message):
	print("TileImportSystem: Processing failed - ", error_message)
	emit_signal("import_failed", error_message)

# Public Methods

func show_import_dialog():
	if file_dialog:
		file_dialog.popup_centered(Vector2i(800, 600))
	else:
		push_error("TileImportSystem: File dialog not initialized")

func import_tileset_from_file(path: String, options: Dictionary = {}):
	print("TileImportSystem: Importing from file ", path)
	
	# Validate file exists
	if not FileAccess.file_exists(path):
		emit_signal("import_failed", "File not found: " + path)
		return false
	
	# Get file extension
	var ext = path.get_extension().to_lower()
	
	if ext in ["png", "jpg", "jpeg", "webp"]:
		return _import_image_tileset(path, options)
	elif ext == "json":
		return _import_tileset_metadata(path)
	else:
		emit_signal("import_failed", "Unsupported file type: " + ext)
		return false

func import_tile(image_path: String, metadata: Dictionary = {}):
	print("TileImportSystem: Importing single tile from ", image_path)
	
	# Load image
	var image = image_processor.process_image(image_path)
	if not image:
		return false
	
	# Create texture
	var texture = ImageTexture.create_from_image(image)
	
	# Process metadata
	var tile_data = default_tile_metadata.duplicate(true)
	for key in metadata:
		tile_data[key] = metadata[key]
	
	# Generate unique ID if not provided
	if not "id" in tile_data:
		tile_data["id"] = _generate_unique_tile_id(tile_data.category)
	
	# Store in tile library
	var category = tile_data.category
	if not category in tile_library:
		tile_library[category] = {}
	
	tile_library[category][tile_data.id] = {
		"data": tile_data,
		"texture": texture
	}
	
	# Save changes to tile library
	save_tile_library()
	
	# Emit signal
	emit_signal("tile_import_completed", tile_data.category, 1)
	emit_signal("tile_library_updated")
	
	return true

func get_tile_data(category: String, tile_id: String) -> Dictionary:
	if category in tile_library and tile_id in tile_library[category]:
		return tile_library[category][tile_id].data.duplicate(true)
	
	return {}

func get_tile_texture(category: String, tile_id: String):
	if category in tile_library and tile_id in tile_library[category]:
		return tile_library[category][tile_id].texture
	
	return null

func get_tiles_by_category(category: String) -> Array:
	var result = []
	
	if category in tile_library:
		for tile_id in tile_library[category]:
			result.append({
				"id": tile_id,
				"data": tile_library[category][tile_id].data
			})
	
	print("TileImportSystem: Found ", result.size(), " tiles in category ", category)
	return result

func load_tile_library() -> bool:
	var library_path = import_settings.output_dir + "tile_library.json"
	
	if not FileAccess.file_exists(library_path):
		print("TileImportSystem: No library file found at ", library_path)
		# No library file yet, create default
		return false
	
	var file = FileAccess.open(library_path, FileAccess.READ)
	if not file:
		push_error("TileImportSystem: Failed to open library file")
		return false
	
	var json_string = file.get_as_text()
	
	var json = JSON.new()
	var err = json.parse(json_string)
	if err != OK:
		push_error("Failed to parse tile library JSON: ", json.get_error_message())
		return false
	
	var library_data = json.get_data()
	
	# Process library data
	for category in library_data:
		if not category in tile_library:
			tile_library[category] = {}
		
		for tile_id in library_data[category]:
			var tile_info = library_data[category][tile_id]
			
			# Load texture
			var texture_path = tile_info.texture_path
			var texture = null
			
			if FileAccess.file_exists(texture_path):
				var img = Image.new()
				var err2 = img.load(texture_path)
				if err2 == OK:
					texture = ImageTexture.create_from_image(img)
			
			# Store in library
			tile_library[category][tile_id] = {
				"data": tile_info.data,
				"texture": texture,
				"texture_path": texture_path
			}
	
	print("TileImportSystem: Loaded tile library with categories: ", tile_library.keys())
	
	# Emit signal
	emit_signal("tile_library_updated")
	
	return true

func save_tile_library() -> bool:
	var library_path = import_settings.output_dir + "tile_library.json"
	
	# Ensure directory exists
	var dir = DirAccess.open("res://")
	if not dir:
		push_error("TileImportSystem: Failed to open base directory for saving")
		return false
	
	var dir_path = library_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		dir.make_dir_recursive(dir_path)
	
	# Prepare data for saving
	var library_data = {}
	
	for category in tile_library:
		library_data[category] = {}
		
		for tile_id in tile_library[category]:
			var tile_info = tile_library[category][tile_id]
			
			# Save texture to file if needed
			var texture_path = import_settings.output_dir + "textures/" + category + "/" + tile_id + ".png"
			
			if "texture_path" not in tile_info:
				# Save texture
				if tile_info.texture:
					var img = tile_info.texture.get_image()
					
					# Ensure directory exists
					var tex_dir = texture_path.get_base_dir()
					if not DirAccess.dir_exists_absolute(tex_dir):
						dir.make_dir_recursive(tex_dir)
					
					# Save image
					img.save_png(texture_path)
					
					# Update path
					tile_info["texture_path"] = texture_path
			
			# Store data without texture
			library_data[category][tile_id] = {
				"data": tile_info.data,
				"texture_path": tile_info.texture_path
			}
	
	# Convert to JSON
	var json_string = JSON.stringify(library_data)
	
	# Save to file
	var file = FileAccess.open(library_path, FileAccess.WRITE)
	if not file:
		push_error("TileImportSystem: Failed to open library file for writing")
		return false
	
	file.store_string(json_string)
	print("TileImportSystem: Saved tile library to ", library_path)
	
	return true

# Private Methods

func _on_files_selected(paths):
	print("TileImportSystem: Files selected: ", paths)
	# Process each selected file
	for path in paths:
		import_tileset_from_file(path)

func _import_image_tileset(path: String, options: Dictionary = {}) -> bool:
	print("TileImportSystem: Importing image tileset from ", path)
	
	# Load image
	var image = image_processor.process_image(path)
	if not image:
		push_error("TileImportSystem: Failed to process image")
		return false
	
	var import_options = import_settings.duplicate()
	for key in options:
		import_options[key] = options[key]
	
	# Determine category from path or options
	var category = "floor"
	if "category" in options:
		category = options.category
	
	# Process based on options
	if import_options.auto_slice:
		# Auto-detect tile size if not specified
		if import_options.slice_size.x <= 0 or import_options.slice_size.y <= 0:
			import_options.slice_size = Vector2i(TILE_SIZE, TILE_SIZE)
			if image_processor and image_processor.has_method("detect_tile_size"):
				var detected_size = image_processor.detect_tile_size(image)
				if detected_size.x > 0 and detected_size.y > 0:
					import_options.slice_size = detected_size
					print("TileImportSystem: Auto-detected tile size: ", detected_size)
		
		# Slice the spritesheet
		var tiles = []
		if image_processor and image_processor.has_method("slice_spritesheet"):
			tiles = image_processor.slice_spritesheet(image, import_options.slice_size)
		else:
			# Fallback slicing if image processor isn't available
			tiles = _slice_spritesheet_fallback(image, import_options.slice_size)
		
		print("TileImportSystem: Sliced into ", tiles.size(), " tiles")
		
		# Detect autotile pattern if enabled
		var pattern_type = "none"
		if import_options.generate_autotile and image_processor and image_processor.has_method("detect_autotile_pattern"):
			pattern_type = image_processor.detect_autotile_pattern(tiles)
			print("TileImportSystem: Detected pattern: ", pattern_type)
		
		# Import each tile
		var imported_count = 0
		
		for tile_data in tiles:
			var tile_image = tile_data.image
			var position = tile_data.position
			
			# Create metadata
			var metadata = default_tile_metadata.duplicate(true)
			metadata.category = category
			metadata.name = "Tile_" + str(position.x) + "_" + str(position.y)
			metadata.atlas_coords = position
			
			if pattern_type != "none":
				metadata.autotile_info.type = pattern_type
				
				# Generate terrain bits for this tile
				if image_processor and image_processor.has_method("generate_terrain_bits"):
					var terrain_bits = image_processor.generate_terrain_bits(position, pattern_type, 0)
					if not terrain_bits.is_empty():
						metadata.autotile_info.terrain_bits = terrain_bits
			
			# Generate unique ID
			var tile_id = _generate_unique_tile_id(category)
			metadata.id = tile_id
			
			# Create texture
			var texture = ImageTexture.create_from_image(tile_image)
			
			# Save texture to file
			var texture_path = import_options.output_dir + "textures/" + category + "/" + tile_id + ".png"
			
			# Ensure directory exists
			var dir = DirAccess.open("res://")
			if dir:
				var tex_dir = texture_path.get_base_dir()
				if not DirAccess.dir_exists_absolute(tex_dir):
					dir.make_dir_recursive(tex_dir)
				
				# Save image
				tile_image.save_png(texture_path)
			
			# Store in library
			if not category in tile_library:
				tile_library[category] = {}
			
			tile_library[category][tile_id] = {
				"data": metadata,
				"texture": texture,
				"texture_path": texture_path
			}
			
			imported_count += 1
		
		# Save changes
		save_tile_library()
		
		# Update tileset if needed
		if tileset_manager and tileset_manager.has_method("update_tileset_from_library"):
			tileset_manager.update_tileset_from_library(category)
		
		# Emit signal
		emit_signal("tile_import_completed", category, imported_count)
		emit_signal("tile_library_updated")
		
		print("TileImportSystem: Imported ", imported_count, " tiles")
		return true
	else:
		# Import as single tile
		var metadata = default_tile_metadata.duplicate(true)
		metadata.category = category
		metadata.name = path.get_file().get_basename()
		
		# Generate unique ID
		var tile_id = _generate_unique_tile_id(category)
		metadata.id = tile_id
		
		# Create texture
		var texture = ImageTexture.create_from_image(image)
		
		# Save texture to file
		var texture_path = import_options.output_dir + "textures/" + category + "/" + tile_id + ".png"
		
		# Ensure directory exists
		var dir = DirAccess.open("res://")
		if dir:
			var tex_dir = texture_path.get_base_dir()
			if not DirAccess.dir_exists_absolute(tex_dir):
				dir.make_dir_recursive(tex_dir)
			
			# Save image
			image.save_png(texture_path)
		
		# Store in library
		if not category in tile_library:
			tile_library[category] = {}
		
		tile_library[category][tile_id] = {
			"data": metadata,
			"texture": texture,
			"texture_path": texture_path
		}
		
		# Save changes
		save_tile_library()
		
		# Update tileset if needed
		if tileset_manager and tileset_manager.has_method("update_tileset_from_library"):
			tileset_manager.update_tileset_from_library(category)
		
		# Emit signal
		emit_signal("tile_import_completed", category, 1)
		emit_signal("tile_library_updated")
		
		print("TileImportSystem: Imported single tile")
		return true

# Fallback slicing if image processor isn't available
func _slice_spritesheet_fallback(image: Image, slice_size: Vector2i) -> Array:
	var tiles = []
	var cols = image.get_width() / slice_size.x
	var rows = image.get_height() / slice_size.y
	
	for y in range(rows):
		for x in range(cols):
			var rect = Rect2i(x * slice_size.x, y * slice_size.y, slice_size.x, slice_size.y)
			var tile_image = Image.create(slice_size.x, slice_size.y, false, Image.FORMAT_RGBA8)
			
			# Copy region to new image
			tile_image.blit_rect(image, rect, Vector2i.ZERO)
			
			# Skip completely transparent tiles
			if _is_tile_empty(tile_image):
				continue
			
			# Store tile info
			tiles.append({
				"image": tile_image,
				"position": Vector2i(x, y)
			})
	
	return tiles

# Check if a tile is completely empty (transparent)
func _is_tile_empty(image: Image) -> bool:
	if not image:
		return true
	
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel = image.get_pixel(x, y)
			if pixel.a > 0.01:  # Not completely transparent
				return false
	
	return true

func _import_tileset_metadata(path: String) -> bool:
	print("TileImportSystem: Importing tileset metadata from ", path)
	
	# Load JSON file
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		emit_signal("import_failed", "Could not open file: " + path)
		return false
	
	var json_string = file.get_as_text()
	
	var json = JSON.new()
	var err = json.parse(json_string)
	if err != OK:
		emit_signal("import_failed", "Failed to parse JSON: " + json.get_error_message())
		return false
	
	var tileset_data = json.get_data()
	
	# Process tileset data
	if not "tiles" in tileset_data:
		emit_signal("import_failed", "Invalid tileset metadata: missing 'tiles' key")
		return false
	
	var category = tileset_data.get("category", "floor")
	var tiles = tileset_data.tiles
	
	# Import each tile
	var imported_count = 0
	for tile_id in tiles:
		var tile_info = tiles[tile_id]
		
		# Check for required data
		if not "texture_path" in tile_info:
			continue
		
		var texture_path = tile_info.texture_path
		
		# Resolve relative paths
		if not texture_path.begins_with("res://") and not texture_path.begins_with("/"):
			texture_path = path.get_base_dir().path_join(texture_path)
		
		# Load texture
		var texture = null
		
		if FileAccess.file_exists(texture_path):
			var img = Image.new()
			var err2 = img.load(texture_path)
			if err2 == OK:
				texture = ImageTexture.create_from_image(img)
		
		if not texture:
			continue
		
		# Process metadata
		var metadata = default_tile_metadata.duplicate(true)
		
		for key in tile_info:
			if key != "texture_path":
				metadata[key] = tile_info[key]
		
		metadata.category = category
		
		if not "id" in metadata:
			metadata.id = tile_id
		
		# Copy texture to our asset directory
		var new_texture_path = import_settings.output_dir + "textures/" + category + "/" + tile_id + ".png"
		
		# Ensure directory exists
		var dir = DirAccess.open("res://")
		if dir:
			var tex_dir = new_texture_path.get_base_dir()
			if not DirAccess.dir_exists_absolute(tex_dir):
				dir.make_dir_recursive(tex_dir)
			
			# Copy image if not already in our directory
			if texture_path != new_texture_path:
				var img = texture.get_image()
				img.save_png(new_texture_path)
		
		# Store in library
		if not category in tile_library:
			tile_library[category] = {}
		
		tile_library[category][tile_id] = {
			"data": metadata,
			"texture": texture,
			"texture_path": new_texture_path
		}
		
		imported_count += 1
	
	# Save changes
	save_tile_library()
	
	# Update tileset if needed
	if tileset_manager and tileset_manager.has_method("update_tileset_from_library"):
		tileset_manager.update_tileset_from_library(category)
	
	# Emit signal
	emit_signal("tileset_import_completed", path.get_file().get_basename())
	emit_signal("tile_library_updated")
	
	print("TileImportSystem: Imported ", imported_count, " tiles from metadata")
	return true

func _generate_unique_tile_id(category: String) -> String:
	if not category in tile_library:
		return category + "_001"
	
	var highest_id = 0
	
	for tile_id in tile_library[category]:
		if tile_id.begins_with(category + "_"):
			var id_part = tile_id.substr(category.length() + 1)
			if id_part.is_valid_int():
				var id_num = int(id_part)
				highest_id = max(highest_id, id_num)
	
	return category + "_" + str(highest_id + 1).pad_zeros(3)
