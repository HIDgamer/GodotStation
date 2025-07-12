extends Node
class_name ImageProcessor

signal processing_failed(error_message)

# Image processing settings
var contrast_threshold = 0.1
var edge_detection_sensitivity = 0.5
var min_tile_size = 16
var max_tile_size = 64
var texture_format = Image.FORMAT_RGBA8

func process_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		emit_signal("processing_failed", "File not found: " + path)
		return null
	
	# Load image
	var img = Image.new()
	var err = img.load(path)
	
	if err != OK:
		emit_signal("processing_failed", "Failed to load image: " + path)
		return null
	
	# Return loaded image
	return img

# Slice a spritesheet into separate tiles
func slice_spritesheet(image: Image, slice_size: Vector2i) -> Array:
	if not image:
		emit_signal("processing_failed", "Invalid image provided")
		return []
	
	var tiles = []
	var cols = image.get_width() / slice_size.x
	var rows = image.get_height() / slice_size.y
	
	# Slice the image
	for y in range(rows):
		for x in range(cols):
			var rect = Rect2i(x * slice_size.x, y * slice_size.y, slice_size.x, slice_size.y)
			var tile_image = Image.create(slice_size.x, slice_size.y, false, texture_format)
			
			# Copy region to new image
			tile_image.blit_rect(image, rect, Vector2i.ZERO)
			
			# Skip completely transparent tiles
			if is_tile_empty(tile_image):
				continue
			
			# Store tile info
			tiles.append({
				"image": tile_image,
				"position": Vector2i(x, y)
			})
	
	return tiles

# Check if a tile is completely empty (transparent)
func is_tile_empty(image: Image) -> bool:
	if not image:
		return true
	
	
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel = image.get_pixel(x, y)
			if pixel.a > 0.01:  # Not completely transparent
				return false
	
	return true

# Detect what kind of autotile pattern the tiles form
func detect_autotile_pattern(tiles: Array) -> String:
	if tiles.size() == 0:
		return "none"
	
	# Count tiles
	var tiles_count = tiles.size()
	
	# Check for common autotile patterns
	if tiles_count == 4:
		return "wang_2x2"
	elif tiles_count >= 8 and tiles_count <= 12:
		return "wang_3x3"
	elif tiles_count >= 16 and tiles_count <= 20:
		return "corner_match"
	elif tiles_count >= 47:
		return "47_bit"
	
	# Try to detect based on grid arrangement
	var grid_size = get_grid_size(tiles)
	if grid_size.x == 3 and grid_size.y == 3:
		return "wang_3x3"
	elif grid_size.x == 4 and grid_size.y == 4:
		return "corner_match"
	elif grid_size.x >= 7 or grid_size.y >= 7:
		return "47_bit"
	
	# Default to 3x3 if we couldn't determine
	return "wang_3x3"

# Get the grid size from a collection of tiles
func get_grid_size(tiles: Array) -> Vector2i:
	var max_x = 0
	var max_y = 0
	
	for tile in tiles:
		max_x = max(max_x, tile.position.x)
		max_y = max(max_y, tile.position.y)
	
	return Vector2i(max_x + 1, max_y + 1)

# Automatically detect tile size from an image
func detect_tile_size(image: Image) -> Vector2i:
	if not image:
		return Vector2i.ZERO
	
	var possible_sizes = [16, 24, 32, 48, 64, 96, 128]
	
	# Try to find a tile size that divides the image evenly
	for size in possible_sizes:
		if image.get_width() % size == 0 and image.get_height() % size == 0:
			# Check if this is likely a valid tile size by looking for repeated patterns
			if is_valid_tile_size(image, size):
				return Vector2i(size, size)
	
	# If no standard size works, try to detect edges
	return detect_tile_boundaries(image)

# Check if a tile size is valid by looking for repeating patterns
func is_valid_tile_size(image: Image, size: int) -> bool:
	var cols = image.get_width() / size
	var rows = image.get_height() / size
	
	# If the image has only one tile, return true
	if cols * rows <= 1:
		return true
	
	# Check if we have some variation between tiles
	var variations = 0
	var first_tile_hash = get_region_hash(image, Rect2i(0, 0, size, size))
	
	for y in range(rows):
		for x in range(cols):
			if x == 0 and y == 0:
				continue
				
			var tile_hash = get_region_hash(image, Rect2i(x * size, y * size, size, size))
			if tile_hash != first_tile_hash:
				variations += 1
	
	# If we have at least some variation (not all tiles identical), this seems like a valid size
	return variations > 0

# Get a simple hash of an image region
func get_region_hash(image: Image, rect: Rect2i) -> int:
	var hash_value = 0
	
	# Sample pixels at fixed positions
	var sample_positions = [
		Vector2i(0, 0),
		Vector2i(rect.size.x / 2, rect.size.y / 2),
		Vector2i(rect.size.x - 1, rect.size.y - 1)
	]
	
	for pos in sample_positions:
		var pixel = image.get_pixel(rect.position.x + pos.x, rect.position.y + pos.y)
		hash_value = hash_value ^ hash(pixel)
	
	return hash_value

# Detect tile boundaries by looking for repeating patterns
func detect_tile_boundaries(image: Image) -> Vector2i:
	# If all else fails, use a default size
	var default_size = Vector2i(32, 32)
	
	# Try to find horizontal and vertical edges
	var horizontal_edges = find_repeating_edges(image, true)
	var vertical_edges = find_repeating_edges(image, false)
	
	if horizontal_edges.size() > 1 and vertical_edges.size() > 1:
		# Calculate median distances
		var h_distances = []
		var v_distances = []
		
		for i in range(1, horizontal_edges.size()):
			h_distances.append(horizontal_edges[i] - horizontal_edges[i-1])
		
		for i in range(1, vertical_edges.size()):
			v_distances.append(vertical_edges[i] - vertical_edges[i-1])
		
		# Sort distances
		h_distances.sort()
		v_distances.sort()
		
		# Get median
		var h_median = h_distances[h_distances.size() / 2]
		var v_median = v_distances[v_distances.size() / 2]
		
		if h_median >= min_tile_size and h_median <= max_tile_size and v_median >= min_tile_size and v_median <= max_tile_size:
			return Vector2i(h_median, v_median)
	
	# If edge detection failed, try to find the size by dividing image dimensions
	for size in [32, 16, 64, 24, 48]:
		if image.get_width() % size == 0 and image.get_height() % size == 0:
			return Vector2i(size, size)
	
	return default_size

# Find repeating edges in an image
func find_repeating_edges(image: Image, horizontal: bool) -> Array:
	var edges = []
	var size = image.get_height() if horizontal else image.get_width()
	var dimension = image.get_width() if horizontal else image.get_height()
	
	
	# For each row/column
	for i in range(1, dimension):
		var edge_score = 0.0
		
		# Check a row/column for edge properties
		for j in range(size):
			var pos1 = Vector2i(i-1, j) if horizontal else Vector2i(j, i-1)
			var pos2 = Vector2i(i, j) if horizontal else Vector2i(j, i)
			
			var pixel1 = image.get_pixel(pos1.x, pos1.y)
			var pixel2 = image.get_pixel(pos2.x, pos2.y)
			
			# Calculate difference between adjacent pixels
			var diff = abs(pixel1.r - pixel2.r) + abs(pixel1.g - pixel2.g) + abs(pixel1.b - pixel2.b) + abs(pixel1.a - pixel2.a)
			edge_score += diff
		
		# Normalize score
		edge_score /= size
		
		# If significant edge, add to list
		if edge_score > edge_detection_sensitivity:
			edges.append(i)
	
	return edges

# Generate terrain bits for a tile based on its position in the atlas
func generate_terrain_bits(atlas_pos: Vector2i, pattern_type: String, terrain_id: int) -> Dictionary:
	var terrain_bits = {}
	
	match pattern_type:
		"wang_3x3":
			_generate_wang_3x3_bits(atlas_pos, terrain_id, terrain_bits)
		"corner_match":
			_generate_corner_match_bits(atlas_pos, terrain_id, terrain_bits)
		"wang_2x2":
			_generate_wang_2x2_bits(atlas_pos, terrain_id, terrain_bits)
		"47_bit":
			_generate_47_bit_bits(atlas_pos, terrain_id, terrain_bits)
	
	return terrain_bits

# Generate bits for 3x3 Wang tiles (classic autotile)
func _generate_wang_3x3_bits(atlas_pos: Vector2i, terrain_id: int, terrain_bits: Dictionary):
	var x = atlas_pos.x % 3
	var y = atlas_pos.y % 3
	
	# Simplified bit mapping for 3x3 autotile
	match Vector2i(x, y):
		Vector2i(0, 0):  # Top-left corner
			terrain_bits[str(TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER)] = -1
			terrain_bits[str(TileSet.CELL_NEIGHBOR_TOP_SIDE)] = -1
			terrain_bits[str(TileSet.CELL_NEIGHBOR_LEFT_SIDE)] = -1
		Vector2i(1, 0):  # Top edge
			terrain_bits[str(TileSet.CELL_NEIGHBOR_TOP_SIDE)] = -1
		Vector2i(2, 0):  # Top-right corner
			terrain_bits[str(TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER)] = -1
			terrain_bits[str(TileSet.CELL_NEIGHBOR_TOP_SIDE)] = -1
			terrain_bits[str(TileSet.CELL_NEIGHBOR_RIGHT_SIDE)] = -1
		Vector2i(0, 1):  # Left edge
			terrain_bits[str(TileSet.CELL_NEIGHBOR_LEFT_SIDE)] = -1
		Vector2i(1, 1):  # Center/fill
			# All connections are terrain_id (default)
			pass
		Vector2i(2, 1):  # Right edge
			terrain_bits[str(TileSet.CELL_NEIGHBOR_RIGHT_SIDE)] = -1
		Vector2i(0, 2):  # Bottom-left corner
			terrain_bits[str(TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER)] = -1
			terrain_bits[str(TileSet.CELL_NEIGHBOR_BOTTOM_SIDE)] = -1
			terrain_bits[str(TileSet.CELL_NEIGHBOR_LEFT_SIDE)] = -1
		Vector2i(1, 2):  # Bottom edge
			terrain_bits[str(TileSet.CELL_NEIGHBOR_BOTTOM_SIDE)] = -1
		Vector2i(2, 2):  # Bottom-right corner
			terrain_bits[str(TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER)] = -1
			terrain_bits[str(TileSet.CELL_NEIGHBOR_BOTTOM_SIDE)] = -1
			terrain_bits[str(TileSet.CELL_NEIGHBOR_RIGHT_SIDE)] = -1

# Generate bits for corner-match autotiles (16-tile format)
func _generate_corner_match_bits(atlas_pos: Vector2i, terrain_id: int, terrain_bits: Dictionary):
	var x = atlas_pos.x % 4
	var y = atlas_pos.y % 4
	
	# Corner match format uses 16 tiles with all combinations of corner bits
	# We can use binary encoding: each corner can be on/off
	var bottom_right = (x & 1) != 0
	var bottom_left = (x & 2) != 0
	var top_right = (y & 1) != 0
	var top_left = (y & 2) != 0
	
	if not top_left:
		terrain_bits[str(TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER)] = -1
	if not top_right:
		terrain_bits[str(TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER)] = -1
	if not bottom_left:
		terrain_bits[str(TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER)] = -1
	if not bottom_right:
		terrain_bits[str(TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER)] = -1
	
	# Determine side connections based on corners
	if not top_left or not top_right:
		terrain_bits[str(TileSet.CELL_NEIGHBOR_TOP_SIDE)] = -1
	if not bottom_left or not bottom_right:
		terrain_bits[str(TileSet.CELL_NEIGHBOR_BOTTOM_SIDE)] = -1
	if not top_left or not bottom_left:
		terrain_bits[str(TileSet.CELL_NEIGHBOR_LEFT_SIDE)] = -1
	if not top_right or not bottom_right:
		terrain_bits[str(TileSet.CELL_NEIGHBOR_RIGHT_SIDE)] = -1

# Generate bits for 2x2 Wang tiles
func _generate_wang_2x2_bits(atlas_pos: Vector2i, terrain_id: int, terrain_bits: Dictionary):
	var x = atlas_pos.x % 2
	var y = atlas_pos.y % 2
	
	# 2x2 Wang tiles for simple corner matching
	# Each tile corresponds to a unique corner
	match Vector2i(x, y):
		Vector2i(0, 0):  # Bottom-left corner
			terrain_bits[str(TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER)] = terrain_id
			# All other corners are -1
			terrain_bits[str(TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER)] = -1
			terrain_bits[str(TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER)] = -1
			terrain_bits[str(TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER)] = -1
		Vector2i(1, 0):  # Bottom-right corner
			terrain_bits[str(TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER)] = terrain_id
			# All other corners are -1
			terrain_bits[str(TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER)] = -1
			terrain_bits[str(TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER)] = -1
			terrain_bits[str(TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER)] = -1
		Vector2i(0, 1):  # Top-left corner
			terrain_bits[str(TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER)] = terrain_id
			# All other corners are -1
			terrain_bits[str(TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER)] = -1
			terrain_bits[str(TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER)] = -1
			terrain_bits[str(TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER)] = -1
		Vector2i(1, 1):  # Top-right corner
			terrain_bits[str(TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER)] = terrain_id
			# All other corners are -1
			terrain_bits[str(TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER)] = -1
			terrain_bits[str(TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER)] = -1
			terrain_bits[str(TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER)] = -1

# Generate bits for 47-bit full terrain tiles
func _generate_47_bit_bits(atlas_pos: Vector2i, terrain_id: int, terrain_bits: Dictionary):
	# For 47-bit, we need to calculate the tile's position in the pattern
	# This is a simplified implementation
	var relative_x = atlas_pos.x % 7
	var relative_y = atlas_pos.y % 7
	
	if relative_x == 3 and relative_y == 3:
		# Center tile - all connections are terrain_id
		return
	
	# Handle edge tiles
	if relative_x < 3 and relative_y < 3:
		# Top-left quadrant
		terrain_bits[str(TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER)] = -1
	elif relative_x > 3 and relative_y < 3:
		# Top-right quadrant
		terrain_bits[str(TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER)] = -1
	elif relative_x < 3 and relative_y > 3:
		# Bottom-left quadrant
		terrain_bits[str(TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER)] = -1
	elif relative_x > 3 and relative_y > 3:
		# Bottom-right quadrant
		terrain_bits[str(TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER)] = -1
	
	# Handle side tiles
	if relative_y == 0:
		terrain_bits[str(TileSet.CELL_NEIGHBOR_TOP_SIDE)] = -1
	if relative_y == 6:
		terrain_bits[str(TileSet.CELL_NEIGHBOR_BOTTOM_SIDE)] = -1
	if relative_x == 0:
		terrain_bits[str(TileSet.CELL_NEIGHBOR_LEFT_SIDE)] = -1
	if relative_x == 6:
		terrain_bits[str(TileSet.CELL_NEIGHBOR_RIGHT_SIDE)] = -1
