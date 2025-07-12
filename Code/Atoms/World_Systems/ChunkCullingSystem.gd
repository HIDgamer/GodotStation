extends Node
class_name ChunkCullingSystem

# Constants
const TILE_SIZE = 32  # Size in pixels of each tile
const CHUNK_SIZE = 16  # Number of tiles per chunk (matches World.CHUNK_SIZE)
const CHUNK_PIXEL_SIZE = CHUNK_SIZE * TILE_SIZE  # Pixel size of a chunk

# Camera settings
var visibility_margin = 1.5  # Extra visibility margin in chunks

# Reference nodes
var world = null
var camera = null
var floor_tilemap = null
var wall_tilemap = null
var objects_tilemap = null
var spatial_manager = null

# Tracking
var active_chunks = {}  # Dictionary of active chunk notifiers
var current_z_level = 0
var debug_mode = true
var last_camera_pos = Vector2.ZERO

# Optimization settings
@export var occlusion_enabled = true
@export var cull_lights = true
@export var cull_entities = true
@export var update_interval = 0.2  # Seconds between culling updates
var update_timer = 0.0

# Signals
signal chunk_visibility_changed(chunk_pos, z_level, is_visible)

func _ready():
	# Find world reference
	world = get_node_or_null("/root/World")
	if not world:
		world = get_tree().get_root().get_node_or_null("World")
	
	# Connect to world signals if available
	if world:
		if world.has_signal("chunks_loaded"):
			world.connect("chunks_loaded", Callable(self, "_on_chunks_loaded"))
		
		# Get references to important nodes
		floor_tilemap = world.get_node_or_null("VisualTileMap/FloorTileMap")
		wall_tilemap = world.get_node_or_null("VisualTileMap/WallTileMap")
		objects_tilemap = world.get_node_or_null("VisualTileMap/ObjectsTileMap")
		spatial_manager = world.get_node_or_null("SpatialManager")
		
		current_z_level = world.current_z_level
		
		print("ChunkCullingSystem: Initialized with world reference")
	else:
		print("ChunkCullingSystem: No world reference found!")
	
	# Find the player's camera
	find_camera()
	
	# Wait briefly then do initial setup
	await get_tree().create_timer(0.5).timeout
	setup_initial_chunks()

# Main update loop
func _process(delta):
	update_timer += delta
	
	# Only update at fixed intervals for performance
	if update_timer < update_interval:
		return
	
	update_timer = 0.0
	
	# Make sure we have a camera reference
	if not camera:
		find_camera()
		if not camera:
			return
	
	# Skip if camera hasn't moved much
	if camera.global_position.distance_to(last_camera_pos) < TILE_SIZE:
		return
	
	last_camera_pos = camera.global_position
		
	# Update chunk visibility
	update_all_chunk_visibility()

# Set up initial chunks
func setup_initial_chunks():
	# Skip if no world reference
	if not world:
		return
	
	# Find all chunk positions that are loaded
	var loaded_chunks = world.loaded_chunks.keys()
	
	for chunk_key in loaded_chunks:
		var parts = chunk_key.split("_")
		if parts.size() >= 3:
			var chunk_x = int(parts[0])
			var chunk_y = int(parts[1])
			var chunk_z = int(parts[2])
			
			# Only handle chunks on current z-level for now
			if chunk_z == current_z_level:
				create_chunk_notifier(Vector2i(chunk_x, chunk_y), chunk_z)
	
	# Do initial visibility pass
	update_all_chunk_visibility()
	print("ChunkCullingSystem: Set up " + str(active_chunks.size()) + " initial chunks")

# Find the player camera
func find_camera():
	# Try finding through player
	if world:
		var player = world.local_player
		if player:
			camera = player.get_node_or_null("Camera2D")
			if camera:
				print("ChunkCullingSystem: Found camera through player")
				return
	
	# Otherwise look for any Camera2D in the scene
	var cameras = get_tree().get_nodes_in_group("PlayerCamera")
	if cameras.size() > 0:
		camera = cameras[0]
		print("ChunkCullingSystem: Found camera through group")
	else:
		# Fallback to any camera
		var all_cameras = get_tree().get_nodes_in_group("Camera2D")
		if all_cameras.size() > 0:
			camera = all_cameras[0]
			print("ChunkCullingSystem: Found camera as fallback")

# Create a notifier for a specific chunk
func create_chunk_notifier(chunk_pos: Vector2i, z_level: int):
	# Create a unique key for this chunk
	var chunk_key = str(chunk_pos.x) + "_" + str(chunk_pos.y) + "_" + str(z_level)
	
	# Skip if already exists
	if chunk_key in active_chunks:
		return active_chunks[chunk_key]
	
	# Create a new chunk notifier
	var notifier = VisibleOnScreenNotifier2D.new()
	
	# Calculate world position of chunk center
	var chunk_center_x = (chunk_pos.x * CHUNK_SIZE + CHUNK_SIZE / 2) * TILE_SIZE
	var chunk_center_y = (chunk_pos.y * CHUNK_SIZE + CHUNK_SIZE / 2) * TILE_SIZE
	notifier.position = Vector2(chunk_center_x, chunk_center_y)
	
	# Set rect size to match chunk bounds
	notifier.rect = Rect2(
		-CHUNK_PIXEL_SIZE / 2, 
		-CHUNK_PIXEL_SIZE / 2, 
		CHUNK_PIXEL_SIZE, 
		CHUNK_PIXEL_SIZE
	)
	
	# Connect signals
	notifier.connect("screen_entered", Callable(self, "_on_chunk_entered").bind(chunk_pos, z_level))
	notifier.connect("screen_exited", Callable(self, "_on_chunk_exited").bind(chunk_pos, z_level))
	
	# Add to tree
	add_child(notifier)
	
	# Store tracking info
	active_chunks[chunk_key] = {
		"notifier": notifier,
		"position": chunk_pos,
		"z_level": z_level,
		"visible": false
	}
	
	return active_chunks[chunk_key]

# Remove a chunk notifier
func remove_chunk_notifier(chunk_pos: Vector2i, z_level: int):
	var chunk_key = str(chunk_pos.x) + "_" + str(chunk_pos.y) + "_" + str(z_level)
	
	if chunk_key in active_chunks:
		var notifier = active_chunks[chunk_key].notifier
		
		# Ensure chunk is visible before removal (cleanup)
		show_chunk(chunk_pos, z_level)
		
		# Remove notifier
		if notifier and is_instance_valid(notifier):
			notifier.queue_free()
		
		# Remove from tracking
		active_chunks.erase(chunk_key)
		return true
	
	return false

# Called when a chunk enters the screen
func _on_chunk_entered(chunk_pos, z_level):
	show_chunk(chunk_pos, z_level)

# Called when a chunk exits the screen
func _on_chunk_exited(chunk_pos, z_level):
	hide_chunk(chunk_pos, z_level)

# Show a specific chunk
func show_chunk(chunk_pos: Vector2i, z_level: int):
	# Skip if not on current z-level
	if z_level != current_z_level:
		return
	
	var chunk_key = str(chunk_pos.x) + "_" + str(chunk_pos.y) + "_" + str(z_level)
	if not chunk_key in active_chunks:
		return
	
	# Skip if already visible
	if active_chunks[chunk_key].visible:
		return
	
	# Mark as visible
	active_chunks[chunk_key].visible = true
	
	# Show tiles in this chunk
	var start_tile_x = chunk_pos.x * CHUNK_SIZE
	var start_tile_y = chunk_pos.y * CHUNK_SIZE
	var end_tile_x = start_tile_x + CHUNK_SIZE - 1
	var end_tile_y = start_tile_y + CHUNK_SIZE - 1
	
	# Show tiles in tilemaps
	set_tilemap_chunk_visibility(floor_tilemap, start_tile_x, start_tile_y, end_tile_x, end_tile_y, true)
	set_tilemap_chunk_visibility(wall_tilemap, start_tile_x, start_tile_y, end_tile_x, end_tile_y, true)
	set_tilemap_chunk_visibility(objects_tilemap, start_tile_x, start_tile_y, end_tile_x, end_tile_y, true)
	
	# Show lights in this chunk
	if cull_lights:
		set_lights_in_chunk_visible(chunk_pos, z_level, true)
	
	# Show entities in this chunk
	if cull_entities and spatial_manager:
		set_entities_in_chunk_visible(chunk_pos, z_level, true)
	
	# Emit signal
	emit_signal("chunk_visibility_changed", chunk_pos, z_level, true)
	
	if debug_mode:
		print("ChunkCullingSystem: Showing chunk ", chunk_pos)

# Hide a specific chunk
func hide_chunk(chunk_pos: Vector2i, z_level: int):
	# Skip if not on current z-level
	if z_level != current_z_level:
		return
	
	var chunk_key = str(chunk_pos.x) + "_" + str(chunk_pos.y) + "_" + str(z_level)
	if not chunk_key in active_chunks:
		return
	
	# Skip if already hidden
	if not active_chunks[chunk_key].visible:
		return
	
	# Mark as hidden
	active_chunks[chunk_key].visible = false
	
	# Hide tiles in this chunk
	var start_tile_x = chunk_pos.x * CHUNK_SIZE
	var start_tile_y = chunk_pos.y * CHUNK_SIZE
	var end_tile_x = start_tile_x + CHUNK_SIZE - 1
	var end_tile_y = start_tile_y + CHUNK_SIZE - 1
	
	# Hide tiles in tilemaps
	set_tilemap_chunk_visibility(floor_tilemap, start_tile_x, start_tile_y, end_tile_x, end_tile_y, false)
	set_tilemap_chunk_visibility(wall_tilemap, start_tile_x, start_tile_y, end_tile_x, end_tile_y, false)
	set_tilemap_chunk_visibility(objects_tilemap, start_tile_x, start_tile_y, end_tile_x, end_tile_y, false)
	
	# Hide lights in this chunk
	if cull_lights:
		set_lights_in_chunk_visible(chunk_pos, z_level, false)
	
	# Hide entities in this chunk
	if cull_entities and spatial_manager:
		set_entities_in_chunk_visible(chunk_pos, z_level, false)
	
	# Emit signal
	emit_signal("chunk_visibility_changed", chunk_pos, z_level, false)
	
	if debug_mode:
		print("ChunkCullingSystem: Hiding chunk ", chunk_pos)

# Set visibility for a range of tiles in a tilemap
func set_tilemap_chunk_visibility(tilemap, start_x, start_y, end_x, end_y, is_visible):
	if not tilemap:
		return
	
	# Create or get an occluder for this chunk
	var cells_to_process = []
	
	# Collect all cells to process
	for x in range(start_x, end_x + 1):
		for y in range(start_y, end_y + 1):
			var cell_pos = Vector2i(x, y)
			
			# Check if there's a tile here
			var atlas_coords = tilemap.get_cell_atlas_coords(0, cell_pos)
			if atlas_coords != Vector2i(-1, -1):
				cells_to_process.append(cell_pos)
	
	# Apply occlusion
	if not is_visible:
		# Hide by setting cells to empty (-1)
		if occlusion_enabled:
			for cell_pos in cells_to_process:
				# Store the original source ID and atlas coords for restoration
				var source_id = tilemap.get_cell_source_id(0, cell_pos)
				var atlas_coords = tilemap.get_cell_atlas_coords(0, cell_pos)
				
				# Create metadata key
				var meta_key = "hidden_tile_" + str(cell_pos.x) + "_" + str(cell_pos.y)
				
				# Store original tile data as metadata
				tilemap.set_meta(meta_key, {
					"source_id": source_id,
					"atlas_coords": atlas_coords
				})
				
				# Hide the tile
				tilemap.set_cell(0, cell_pos, -1)
	else:
		# Restore hidden cells
		if occlusion_enabled:
			for cell_pos in cells_to_process:
				# Create metadata key
				var meta_key = "hidden_tile_" + str(cell_pos.x) + "_" + str(cell_pos.y)
				
				# Check if this tile was hidden
				if tilemap.has_meta(meta_key):
					var tile_data = tilemap.get_meta(meta_key)
					
					# Restore the original tile
					tilemap.set_cell(0, cell_pos, tile_data.source_id, tile_data.atlas_coords)
					
					# Remove the metadata
					tilemap.remove_meta(meta_key)

# Set visibility for lights in a chunk
func set_lights_in_chunk_visible(chunk_pos, z_level, is_visible):
	# Calculate chunk bounds in pixel coordinates
	var start_x = chunk_pos.x * CHUNK_SIZE * TILE_SIZE
	var start_y = chunk_pos.y * CHUNK_SIZE * TILE_SIZE
	var end_x = start_x + CHUNK_SIZE * TILE_SIZE
	var end_y = start_y + CHUNK_SIZE * TILE_SIZE
	var chunk_rect = Rect2(start_x, start_y, end_x - start_x, end_y - start_y)
	
	# Find all lights in the scene
	var lights = get_tree().get_nodes_in_group("lights")
	
	# Filter to only lights in this chunk
	for light in lights:
		if light is Node2D:
			# Check if the light is in this chunk
			if chunk_rect.has_point(light.global_position):
				# Set visibility
				light.visible = is_visible
				
				# For more advanced light optimization
				if is_visible and light.has_method("_set_light_quality"):
					# When showing, apply optimized settings based on distance
					if camera:
						var distance = light.global_position.distance_to(camera.global_position)
						var normalized_distance = clamp(distance / (CHUNK_PIXEL_SIZE * 3), 0, 1)
						
						# Further lights get lower quality
						var target_quality = int(80 - normalized_distance * 40) # 80 to 40 quality
						light._set_light_quality(target_quality)

# Set visibility for entities in a chunk
func set_entities_in_chunk_visible(chunk_pos, z_level, is_visible):
	if not spatial_manager:
		return
	
	# Calculate chunk bounds in tile coordinates
	var start_x = chunk_pos.x * CHUNK_SIZE
	var start_y = chunk_pos.y * CHUNK_SIZE
	var end_x = start_x + CHUNK_SIZE - 1
	var end_y = start_y + CHUNK_SIZE - 1
	
	# Get entities from spatial manager
	for x in range(start_x, end_x + 1):
		for y in range(start_y, end_y + 1):
			var tile_pos = Vector2i(x, y)
			var entities = world.get_entities_at_tile(tile_pos, z_level)
			
			for entity in entities:
				# Don't hide the player
				if entity and "type" in entity and entity.type != "player":
					entity.visible = is_visible

# Update visibility for all chunks
func update_all_chunk_visibility():
	if not camera:
		return
	
	# Get current visible rect in world coordinates
	var viewport_rect = camera.get_viewport_rect()
	var camera_center = camera.global_position
	var zoom = camera.zoom
	
	# Calculate visible area with margin
	var visible_width = viewport_rect.size.x / zoom.x * visibility_margin
	var visible_height = viewport_rect.size.y / zoom.y * visibility_margin
	
	var visible_rect = Rect2(
		camera_center.x - visible_width / 2,
		camera_center.y - visible_height / 2,
		visible_width,
		visible_height
	)
	
	# Convert to chunk coordinates
	var min_chunk_x = int(floor(visible_rect.position.x / (CHUNK_SIZE * TILE_SIZE)))
	var min_chunk_y = int(floor(visible_rect.position.y / (CHUNK_SIZE * TILE_SIZE)))
	var max_chunk_x = int(ceil((visible_rect.position.x + visible_rect.size.x) / (CHUNK_SIZE * TILE_SIZE)))
	var max_chunk_y = int(ceil((visible_rect.position.y + visible_rect.size.y) / (CHUNK_SIZE * TILE_SIZE)))
	
	# Update each chunk's visibility
	for chunk_key in active_chunks.keys():
		var chunk = active_chunks[chunk_key]
		var chunk_pos = chunk.position
		
		# Skip if not on current z-level
		if chunk.z_level != current_z_level:
			continue
		
		# Calculate chunk center in world coordinates
		var chunk_center_x = (chunk_pos.x * CHUNK_SIZE + CHUNK_SIZE / 2) * TILE_SIZE
		var chunk_center_y = (chunk_pos.y * CHUNK_SIZE + CHUNK_SIZE / 2) * TILE_SIZE
		
		# Determine if chunk should be visible based on camera view
		var should_be_visible = (
			chunk_pos.x >= min_chunk_x and chunk_pos.x <= max_chunk_x and
			chunk_pos.y >= min_chunk_y and chunk_pos.y <= max_chunk_y
		)
		
		# Update chunk visibility
		if should_be_visible and not chunk.visible:
			show_chunk(chunk_pos, chunk.z_level)
		elif not should_be_visible and chunk.visible:
			hide_chunk(chunk_pos, chunk.z_level)

# Handle new chunks being loaded
func _on_chunks_loaded(chunk_positions, z_level):
	if z_level != current_z_level:
		return
	
	for chunk_pos in chunk_positions:
		create_chunk_notifier(chunk_pos, z_level)
	
	# Update visibility for all chunks
	update_all_chunk_visibility()

# Set current z-level
func set_z_level(z_level):
	if current_z_level == z_level:
		return
	
	var old_z_level = current_z_level
	current_z_level = z_level
	
	# Hide all chunks from old z-level
	for chunk_key in active_chunks.keys():
		var chunk = active_chunks[chunk_key]
		if chunk.z_level == old_z_level and chunk.visible:
			hide_chunk(chunk.position, chunk.z_level)
	
	# Update visibility for new z-level
	update_all_chunk_visibility()

# Enable/disable debug mode
func set_debug_mode(enabled):
	debug_mode = enabled
	
	# Optionally visualize chunk bounds when debugging
	if enabled:
		for chunk_key in active_chunks.keys():
			var chunk = active_chunks[chunk_key]
			var notifier = chunk.notifier
			
			# Add visual indicator for debug
			if notifier and not notifier.has_node("DebugRect"):
				var debug_rect = ColorRect.new()
				debug_rect.name = "DebugRect"
				debug_rect.size = Vector2(CHUNK_PIXEL_SIZE, CHUNK_PIXEL_SIZE)
				debug_rect.position = Vector2(-CHUNK_PIXEL_SIZE/2, -CHUNK_PIXEL_SIZE/2)
				debug_rect.color = Color(1, 0, 0, 0.1)
				notifier.add_child(debug_rect)
	else:
		# Remove debug visuals
		for chunk_key in active_chunks.keys():
			var chunk = active_chunks[chunk_key]
			var notifier = chunk.notifier
			
			if notifier and notifier.has_node("DebugRect"):
				notifier.get_node("DebugRect").queue_free()

# Set occlusion settings
func set_occlusion_enabled(enabled):
	# Only apply if changing
	if occlusion_enabled != enabled:
		occlusion_enabled = enabled
		
		# Force update all chunks when changing occlusion mode
		for chunk_key in active_chunks.keys():
			var chunk = active_chunks[chunk_key]
			if chunk.z_level == current_z_level:
				if chunk.visible:
					# Refresh visibility
					hide_chunk(chunk.position, chunk.z_level)
					show_chunk(chunk.position, chunk.z_level)
