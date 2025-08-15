extends Node
class_name ChunkCullingSystem

# =============================================================================
# CONSTANTS
# =============================================================================

const TILE_SIZE = 32
const CHUNK_SIZE = 16
const CHUNK_PIXEL_SIZE = CHUNK_SIZE * TILE_SIZE

# =============================================================================
# EXPORTS
# =============================================================================

@export_group("Culling Settings")
@export var visibility_margin: float = 1.5
@export var occlusion_enabled: bool = true
@export var cull_lights: bool = true
@export var cull_entities: bool = true

@export_group("Performance Settings")
@export var update_interval: float = 0.2
@export var camera_movement_threshold: float = 32.0
@export var max_chunks_per_frame: int = 10
@export var enable_distance_culling: bool = true

@export_group("Quality Settings")
@export var light_quality_scaling: bool = true
@export var min_light_quality: int = 40
@export var max_light_quality: int = 80
@export var entity_lod_enabled: bool = true

@export_group("Debug Settings")
@export var debug_mode: bool = true
@export var log_chunk_operations: bool = false
@export var show_chunk_bounds: bool = false
@export var performance_monitoring: bool = false

# =============================================================================
# SIGNALS
# =============================================================================

signal chunk_visibility_changed(chunk_pos, z_level, is_visible)
signal culling_stats_updated(visible_chunks, hidden_chunks, culled_entities)
signal camera_reference_changed(new_camera)

# =============================================================================
# PRIVATE VARIABLES
# =============================================================================

# System references
var world = null
var camera = null
var floor_tilemap = null
var wall_tilemap = null
var objects_tilemap = null
var spatial_manager = null

# Chunk tracking
var active_chunks = {}
var current_z_level = 0
var last_camera_pos = Vector2.ZERO
var update_timer = 0.0

# Performance tracking
var performance_stats = {}
var chunks_processed_this_frame = 0

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready():
	_find_world_reference()
	_setup_initial_state()
	_setup_performance_monitoring()
	
	await get_tree().create_timer(0.5).timeout
	_setup_initial_chunks()

func _process(delta):
	_update_culling_system(delta)

# =============================================================================
# INITIALIZATION
# =============================================================================

func _find_world_reference():
	world = get_parent()
	
	if world:
		_connect_world_signals()
		_get_system_references()
		_setup_z_level_tracking()
		
		if debug_mode:
			print("ChunkCullingSystem: Initialized with world reference")
	else:
		push_error("ChunkCullingSystem: No world reference found!")

func _connect_world_signals():
	if world.has_signal("chunks_loaded"):
		world.connect("chunks_loaded", Callable(self, "_on_chunks_loaded"))

func _get_system_references():
	floor_tilemap = world.get_node_or_null("VisualTileMap/FloorTileMap")
	wall_tilemap = world.get_node_or_null("VisualTileMap/WallTileMap")
	objects_tilemap = world.get_node_or_null("VisualTileMap/ObjectsTileMap")
	spatial_manager = world.get_node_or_null("SpatialManager")

func _setup_z_level_tracking():
	current_z_level = world.current_z_level

func _setup_initial_state():
	_find_camera()
	performance_stats = {
		"visible_chunks": 0,
		"hidden_chunks": 0,
		"culled_entities": 0,
		"culled_lights": 0,
		"frame_time": 0.0
	}

func _setup_performance_monitoring():
	if performance_monitoring:
		set_process_mode(Node.PROCESS_MODE_ALWAYS)

func _find_camera():
	if world:
		var player = world.local_player
		if player:
			camera = player.get_node_or_null("Camera2D")
			if camera:
				emit_signal("camera_reference_changed", camera)
				if debug_mode:
					print("ChunkCullingSystem: Found camera through player")
				return
	
	var cameras = get_tree().get_nodes_in_group("PlayerCamera")
	if cameras.size() > 0:
		camera = cameras[0]
		emit_signal("camera_reference_changed", camera)
		if debug_mode:
			print("ChunkCullingSystem: Found camera through group")
	else:
		var all_cameras = get_tree().get_nodes_in_group("Camera2D")
		if all_cameras.size() > 0:
			camera = all_cameras[0]
			emit_signal("camera_reference_changed", camera)
			if debug_mode:
				print("ChunkCullingSystem: Found camera as fallback")

func _setup_initial_chunks():
	if not world:
		return
	
	var loaded_chunks = world.loaded_chunks.keys()
	
	for chunk_key in loaded_chunks:
		var parts = chunk_key.split("_")
		if parts.size() >= 3:
			var chunk_x = int(parts[0])
			var chunk_y = int(parts[1])
			var chunk_z = int(parts[2])
			
			if chunk_z == current_z_level:
				_create_chunk_notifier(Vector2i(chunk_x, chunk_y), chunk_z)
	
	_update_all_chunk_visibility()
	
	if debug_mode:
		print("ChunkCullingSystem: Set up ", active_chunks.size(), " initial chunks")

# =============================================================================
# CULLING UPDATE SYSTEM
# =============================================================================

func _update_culling_system(delta):
	var start_time = Time.get_ticks_usec()
	
	update_timer += delta
	
	if update_timer < update_interval:
		return
	
	update_timer = 0.0
	
	if not camera:
		_find_camera()
		if not camera:
			return
	
	if _should_skip_update():
		return
	
	last_camera_pos = camera.global_position
	chunks_processed_this_frame = 0
	
	_update_all_chunk_visibility()
	
	if performance_monitoring:
		performance_stats.frame_time = (Time.get_ticks_usec() - start_time) / 1000.0

func _should_skip_update() -> bool:
	return camera.global_position.distance_to(last_camera_pos) < camera_movement_threshold

# =============================================================================
# CHUNK NOTIFIER MANAGEMENT
# =============================================================================

func _create_chunk_notifier(chunk_pos: Vector2i, z_level: int):
	var chunk_key = _get_chunk_key(chunk_pos, z_level)
	
	if chunk_key in active_chunks:
		return active_chunks[chunk_key]
	
	var notifier = VisibleOnScreenNotifier2D.new()
	
	var chunk_center_x = (chunk_pos.x * CHUNK_SIZE + CHUNK_SIZE / 2) * TILE_SIZE
	var chunk_center_y = (chunk_pos.y * CHUNK_SIZE + CHUNK_SIZE / 2) * TILE_SIZE
	notifier.position = Vector2(chunk_center_x, chunk_center_y)
	
	notifier.rect = Rect2(
		-CHUNK_PIXEL_SIZE / 2, 
		-CHUNK_PIXEL_SIZE / 2, 
		CHUNK_PIXEL_SIZE, 
		CHUNK_PIXEL_SIZE
	)
	
	notifier.connect("screen_entered", Callable(self, "_on_chunk_entered").bind(chunk_pos, z_level))
	notifier.connect("screen_exited", Callable(self, "_on_chunk_exited").bind(chunk_pos, z_level))
	
	add_child(notifier)
	
	active_chunks[chunk_key] = {
		"notifier": notifier,
		"position": chunk_pos,
		"z_level": z_level,
		"visible": false,
		"last_update": Time.get_ticks_msec()
	}
	
	if show_chunk_bounds:
		_add_debug_visualization(notifier)
	
	return active_chunks[chunk_key]

func _remove_chunk_notifier(chunk_pos: Vector2i, z_level: int):
	var chunk_key = _get_chunk_key(chunk_pos, z_level)
	
	if chunk_key in active_chunks:
		var notifier = active_chunks[chunk_key].notifier
		
		_show_chunk(chunk_pos, z_level)
		
		if notifier and is_instance_valid(notifier):
			notifier.queue_free()
		
		active_chunks.erase(chunk_key)
		return true
	
	return false

func _add_debug_visualization(notifier: VisibleOnScreenNotifier2D):
	if not show_chunk_bounds:
		return
		
	var debug_rect = ColorRect.new()
	debug_rect.name = "DebugRect"
	debug_rect.size = Vector2(CHUNK_PIXEL_SIZE, CHUNK_PIXEL_SIZE)
	debug_rect.position = Vector2(-CHUNK_PIXEL_SIZE/2, -CHUNK_PIXEL_SIZE/2)
	debug_rect.color = Color(1, 0, 0, 0.1)
	notifier.add_child(debug_rect)

# =============================================================================
# CHUNK VISIBILITY MANAGEMENT
# =============================================================================

func _update_all_chunk_visibility():
	if not camera:
		return
	
	var visible_rect = _calculate_visible_rect()
	var chunk_bounds = _calculate_chunk_bounds(visible_rect)
	
	var visible_count = 0
	var hidden_count = 0
	
	for chunk_key in active_chunks.keys():
		var chunk = active_chunks[chunk_key]
		var chunk_pos = chunk.position
		
		if chunk.z_level != current_z_level:
			continue
		
		var should_be_visible = _is_chunk_in_bounds(chunk_pos, chunk_bounds)
		
		if enable_distance_culling:
			should_be_visible = should_be_visible and _is_chunk_within_distance(chunk_pos)
		
		if should_be_visible and not chunk.visible:
			_show_chunk(chunk_pos, chunk.z_level)
			visible_count += 1
		elif not should_be_visible and chunk.visible:
			_hide_chunk(chunk_pos, chunk.z_level)
			hidden_count += 1
		
		chunks_processed_this_frame += 1
		if chunks_processed_this_frame >= max_chunks_per_frame:
			break
	
	if performance_monitoring:
		performance_stats.visible_chunks = visible_count
		performance_stats.hidden_chunks = hidden_count
		emit_signal("culling_stats_updated", visible_count, hidden_count, performance_stats.culled_entities)

func _calculate_visible_rect() -> Rect2:
	var viewport_rect = camera.get_viewport_rect()
	var camera_center = camera.global_position
	var zoom = camera.zoom
	
	var visible_width = viewport_rect.size.x / zoom.x * visibility_margin
	var visible_height = viewport_rect.size.y / zoom.y * visibility_margin
	
	return Rect2(
		camera_center.x - visible_width / 2,
		camera_center.y - visible_height / 2,
		visible_width,
		visible_height
	)

func _calculate_chunk_bounds(visible_rect: Rect2) -> Dictionary:
	return {
		"min_chunk_x": int(floor(visible_rect.position.x / (CHUNK_SIZE * TILE_SIZE))),
		"min_chunk_y": int(floor(visible_rect.position.y / (CHUNK_SIZE * TILE_SIZE))),
		"max_chunk_x": int(ceil((visible_rect.position.x + visible_rect.size.x) / (CHUNK_SIZE * TILE_SIZE))),
		"max_chunk_y": int(ceil((visible_rect.position.y + visible_rect.size.y) / (CHUNK_SIZE * TILE_SIZE)))
	}

func _is_chunk_in_bounds(chunk_pos: Vector2i, bounds: Dictionary) -> bool:
	return (chunk_pos.x >= bounds.min_chunk_x and chunk_pos.x <= bounds.max_chunk_x and
			chunk_pos.y >= bounds.min_chunk_y and chunk_pos.y <= bounds.max_chunk_y)

func _is_chunk_within_distance(chunk_pos: Vector2i) -> bool:
	if not enable_distance_culling:
		return true
		
	var chunk_center_x = (chunk_pos.x * CHUNK_SIZE + CHUNK_SIZE / 2) * TILE_SIZE
	var chunk_center_y = (chunk_pos.y * CHUNK_SIZE + CHUNK_SIZE / 2) * TILE_SIZE
	var chunk_center = Vector2(chunk_center_x, chunk_center_y)
	
	var distance = camera.global_position.distance_to(chunk_center)
	var max_distance = visibility_margin * CHUNK_PIXEL_SIZE * 3
	
	return distance <= max_distance

func _show_chunk(chunk_pos: Vector2i, z_level: int):
	if z_level != current_z_level:
		return
	
	var chunk_key = _get_chunk_key(chunk_pos, z_level)
	if not chunk_key in active_chunks:
		return
	
	if active_chunks[chunk_key].visible:
		return
	
	active_chunks[chunk_key].visible = true
	active_chunks[chunk_key].last_update = Time.get_ticks_msec()
	
	var tile_bounds = _calculate_tile_bounds(chunk_pos)
	
	_set_tilemap_chunk_visibility(floor_tilemap, tile_bounds, true)
	_set_tilemap_chunk_visibility(wall_tilemap, tile_bounds, true)
	_set_tilemap_chunk_visibility(objects_tilemap, tile_bounds, true)
	
	if cull_lights:
		_set_lights_in_chunk_visible(chunk_pos, z_level, true)
	
	if cull_entities and spatial_manager:
		_set_entities_in_chunk_visible(chunk_pos, z_level, true)
	
	emit_signal("chunk_visibility_changed", chunk_pos, z_level, true)
	
	if log_chunk_operations:
		print("ChunkCullingSystem: Showing chunk ", chunk_pos)

func _hide_chunk(chunk_pos: Vector2i, z_level: int):
	if z_level != current_z_level:
		return
	
	var chunk_key = _get_chunk_key(chunk_pos, z_level)
	if not chunk_key in active_chunks:
		return
	
	if not active_chunks[chunk_key].visible:
		return
	
	active_chunks[chunk_key].visible = false
	active_chunks[chunk_key].last_update = Time.get_ticks_msec()
	
	var tile_bounds = _calculate_tile_bounds(chunk_pos)
	
	_set_tilemap_chunk_visibility(floor_tilemap, tile_bounds, false)
	_set_tilemap_chunk_visibility(wall_tilemap, tile_bounds, false)
	_set_tilemap_chunk_visibility(objects_tilemap, tile_bounds, false)
	
	if cull_lights:
		_set_lights_in_chunk_visible(chunk_pos, z_level, false)
	
	if cull_entities and spatial_manager:
		_set_entities_in_chunk_visible(chunk_pos, z_level, false)
	
	emit_signal("chunk_visibility_changed", chunk_pos, z_level, false)
	
	if log_chunk_operations:
		print("ChunkCullingSystem: Hiding chunk ", chunk_pos)

# =============================================================================
# TILEMAP CULLING
# =============================================================================

func _set_tilemap_chunk_visibility(tilemap, tile_bounds: Dictionary, is_visible: bool):
	if not tilemap:
		return
	
	var cells_to_process = []
	
	for x in range(tile_bounds.start_x, tile_bounds.end_x + 1):
		for y in range(tile_bounds.start_y, tile_bounds.end_y + 1):
			var cell_pos = Vector2i(x, y)
			
			var atlas_coords = tilemap.get_cell_atlas_coords(0, cell_pos)
			if atlas_coords != Vector2i(-1, -1):
				cells_to_process.append(cell_pos)
	
	if not is_visible:
		_hide_tilemap_cells(tilemap, cells_to_process)
	else:
		_show_tilemap_cells(tilemap, cells_to_process)

func _hide_tilemap_cells(tilemap: TileMap, cells: Array):
	if not occlusion_enabled:
		return
		
	for cell_pos in cells:
		var source_id = tilemap.get_cell_source_id(0, cell_pos)
		var atlas_coords = tilemap.get_cell_atlas_coords(0, cell_pos)
		
		var meta_key = "hidden_tile_" + str(cell_pos.x) + "_" + str(cell_pos.y)
		
		tilemap.set_meta(meta_key, {
			"source_id": source_id,
			"atlas_coords": atlas_coords
		})
		
		tilemap.set_cell(0, cell_pos, -1)

func _show_tilemap_cells(tilemap: TileMap, cells: Array):
	if not occlusion_enabled:
		return
		
	for cell_pos in cells:
		var meta_key = "hidden_tile_" + str(cell_pos.x) + "_" + str(cell_pos.y)
		
		if tilemap.has_meta(meta_key):
			var tile_data = tilemap.get_meta(meta_key)
			
			tilemap.set_cell(0, cell_pos, tile_data.source_id, tile_data.atlas_coords)
			tilemap.remove_meta(meta_key)

# =============================================================================
# LIGHT CULLING
# =============================================================================

func _set_lights_in_chunk_visible(chunk_pos: Vector2i, z_level: int, is_visible: bool):
	var chunk_rect = _calculate_chunk_world_rect(chunk_pos)
	var lights = get_tree().get_nodes_in_group("Lights")
	var culled_lights = 0
	
	for light in lights:
		if light is Node2D:
			if chunk_rect.has_point(light.global_position):
				light.visible = is_visible
				
				if light_quality_scaling and is_visible:
					_apply_light_quality_scaling(light)
				
				if not is_visible:
					culled_lights += 1
	
	if performance_monitoring:
		performance_stats.culled_lights = culled_lights

func _apply_light_quality_scaling(light):
	if not light.has_method("_set_light_quality"):
		return
		
	if not camera:
		return
		
	var distance = light.global_position.distance_to(camera.global_position)
	var normalized_distance = clamp(distance / (CHUNK_PIXEL_SIZE * 3), 0, 1)
	
	var target_quality = int(max_light_quality - normalized_distance * (max_light_quality - min_light_quality))
	light._set_light_quality(target_quality)

# =============================================================================
# ENTITY CULLING
# =============================================================================

func _set_entities_in_chunk_visible(chunk_pos: Vector2i, z_level: int, is_visible: bool):
	if not spatial_manager:
		return
	
	var tile_bounds = _calculate_tile_bounds(chunk_pos)
	var culled_entities = 0
	
	for x in range(tile_bounds.start_x, tile_bounds.end_x + 1):
		for y in range(tile_bounds.start_y, tile_bounds.end_y + 1):
			var tile_pos = Vector2i(x, y)
			var entities = world.get_entities_at_tile(tile_pos, z_level)
			
			for entity in entities:
				if entity and _should_cull_entity(entity):
					entity.visible = is_visible
					
					if entity_lod_enabled and is_visible:
						_apply_entity_lod(entity)
					
					if not is_visible:
						culled_entities += 1
	
	if performance_monitoring:
		performance_stats.culled_entities = culled_entities

func _should_cull_entity(entity: Node) -> bool:
	if not entity or not "type" in entity:
		return false
		
	return entity.type != "player"

func _apply_entity_lod(entity: Node):
	if not camera:
		return
		
	var distance = entity.global_position.distance_to(camera.global_position)
	var max_distance = visibility_margin * CHUNK_PIXEL_SIZE * 2
	
	if distance > max_distance * 0.8:
		if entity.has_method("set_lod_level"):
			entity.set_lod_level(2)  # Low detail
	elif distance > max_distance * 0.5:
		if entity.has_method("set_lod_level"):
			entity.set_lod_level(1)  # Medium detail
	else:
		if entity.has_method("set_lod_level"):
			entity.set_lod_level(0)  # High detail

# =============================================================================
# UTILITY METHODS
# =============================================================================

func _get_chunk_key(chunk_pos: Vector2i, z_level: int) -> String:
	return str(chunk_pos.x) + "_" + str(chunk_pos.y) + "_" + str(z_level)

func _calculate_tile_bounds(chunk_pos: Vector2i) -> Dictionary:
	return {
		"start_x": chunk_pos.x * CHUNK_SIZE,
		"start_y": chunk_pos.y * CHUNK_SIZE,
		"end_x": chunk_pos.x * CHUNK_SIZE + CHUNK_SIZE - 1,
		"end_y": chunk_pos.y * CHUNK_SIZE + CHUNK_SIZE - 1
	}

func _calculate_chunk_world_rect(chunk_pos: Vector2i) -> Rect2:
	var start_x = chunk_pos.x * CHUNK_SIZE * TILE_SIZE
	var start_y = chunk_pos.y * CHUNK_SIZE * TILE_SIZE
	
	return Rect2(start_x, start_y, CHUNK_PIXEL_SIZE, CHUNK_PIXEL_SIZE)

# =============================================================================
# PUBLIC API
# =============================================================================

func set_z_level(z_level: int):
	if current_z_level == z_level:
		return
	
	var old_z_level = current_z_level
	current_z_level = z_level
	
	for chunk_key in active_chunks.keys():
		var chunk = active_chunks[chunk_key]
		if chunk.z_level == old_z_level and chunk.visible:
			_hide_chunk(chunk.position, chunk.z_level)
	
	_update_all_chunk_visibility()

func set_debug_mode(enabled: bool):
	debug_mode = enabled
	
	if enabled:
		_add_debug_visualizations()
	else:
		_remove_debug_visualizations()

func _add_debug_visualizations():
	for chunk_key in active_chunks.keys():
		var chunk = active_chunks[chunk_key]
		var notifier = chunk.notifier
		
		if notifier and not notifier.has_node("DebugRect"):
			_add_debug_visualization(notifier)

func _remove_debug_visualizations():
	for chunk_key in active_chunks.keys():
		var chunk = active_chunks[chunk_key]
		var notifier = chunk.notifier
		
		if notifier and notifier.has_node("DebugRect"):
			notifier.get_node("DebugRect").queue_free()

func set_occlusion_enabled(enabled: bool):
	if occlusion_enabled != enabled:
		occlusion_enabled = enabled
		
		for chunk_key in active_chunks.keys():
			var chunk = active_chunks[chunk_key]
			if chunk.z_level == current_z_level:
				if chunk.visible:
					_hide_chunk(chunk.position, chunk.z_level)
					_show_chunk(chunk.position, chunk.z_level)

func get_performance_stats() -> Dictionary:
	return performance_stats.duplicate()

func get_chunk_count() -> Dictionary:
	var visible = 0
	var hidden = 0
	
	for chunk_key in active_chunks.keys():
		var chunk = active_chunks[chunk_key]
		if chunk.z_level == current_z_level:
			if chunk.visible:
				visible += 1
			else:
				hidden += 1
	
	return {
		"visible": visible,
		"hidden": hidden,
		"total": active_chunks.size()
	}

func force_update_all_chunks():
	_update_all_chunk_visibility()

func set_visibility_margin(margin: float):
	visibility_margin = clamp(margin, 0.5, 5.0)
	_update_all_chunk_visibility()

func set_update_interval(interval: float):
	update_interval = clamp(interval, 0.05, 1.0)

# =============================================================================
# SIGNAL HANDLERS
# =============================================================================

func _on_chunk_entered(chunk_pos: Vector2i, z_level: int):
	_show_chunk(chunk_pos, z_level)

func _on_chunk_exited(chunk_pos: Vector2i, z_level: int):
	_hide_chunk(chunk_pos, z_level)

func _on_chunks_loaded(chunk_positions: Array, z_level: int):
	if z_level != current_z_level:
		return
	
	for chunk_pos in chunk_positions:
		_create_chunk_notifier(chunk_pos, z_level)
	
	_update_all_chunk_visibility()

# =============================================================================
# CLEANUP
# =============================================================================

func _exit_tree():
	for chunk_key in active_chunks.keys():
		var chunk = active_chunks[chunk_key]
		if chunk.visible:
			_show_chunk(chunk.position, chunk.z_level)
	
	active_chunks.clear()
