extends Node2D
class_name VisionCullingSystem

# =============================================================================
# CONSTANTS
# =============================================================================

const SHADOW_TILE_SOURCE_ID: int = 0
const SHADOW_TILE_ATLAS_COORDS: Vector2i = Vector2i(0, 0)
const SHADOW_LAYER: int = 0
const UPDATE_BATCH_SIZE: int = 100
const VISIBILITY_UPDATE_INTERVAL: float = 0.02
const DIRTY_REGION_SIZE: int = 16

# =============================================================================
# EXPORTS
# =============================================================================

@export_group("Vision Settings")
@export var enable_fog_of_war: bool = true
@export var use_combined_vision: bool = true
@export var shadow_opacity: float = 0.8
@export var fog_opacity: float = 0.6

@export_group("Performance Settings")
@export var use_threading: bool = true
@export var dirty_region_tracking: bool = true
@export var update_batch_size: int = UPDATE_BATCH_SIZE
@export var visibility_update_interval: float = VISIBILITY_UPDATE_INTERVAL
@export var max_cached_tiles: int = 10000

@export_group("Visual Settings")
@export var shadow_color: Color = Color.BLACK
@export var fog_color: Color = Color(0.3, 0.3, 0.3, 0.6)
@export var shadow_z_index: int = 100
@export var fog_z_index: int = 99

@export_group("Debug Settings")
@export var debug_mode: bool = false
@export var log_vision_updates: bool = false
@export var show_performance_stats: bool = false

# =============================================================================
# SIGNALS
# =============================================================================

signal visibility_map_updated(visible_tiles: Array, hidden_tiles: Array)
signal vision_component_registered(component: VisionComponent)
signal vision_component_unregistered(component: VisionComponent)
signal fog_of_war_toggled(enabled: bool)
signal shadow_opacity_changed(new_opacity: float)

# =============================================================================
# PRIVATE VARIABLES
# =============================================================================

# System references
var world: Node = null
var shadow_tilemap: TileMap = null
var fog_of_war_tilemap: TileMap = null
var thread_manager: Node = null

# Vision management
var registered_components: Array[VisionComponent] = []
var global_visible_tiles: Dictionary = {}
var global_hidden_tiles: Dictionary = {}
var previously_visible_tiles: Dictionary = {}
var explored_tiles: Dictionary = {}

# Update management
var update_timer: float = 0.0
var pending_updates: Array = []
var tiles_to_update: Array[Vector2i] = []
var update_batch_index: int = 0
var is_processing_batch_update: bool = false

# Threading and optimization
var visibility_update_task: String = ""
var pending_tile_updates: Dictionary = {}
var dirty_regions: Dictionary = {}
var visibility_cache: Dictionary = {}

# State tracking
var current_z_level: int = 0
var is_fully_initialized: bool = false
var initial_update_pending: bool = true

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready():
	name = "VisionCullingSystem"
	_initialize_system()

func _process(delta: float):
	_update_timers(delta)
	_process_pending_updates()
	_process_batch_updates()
	_handle_initial_update()

# =============================================================================
# INITIALIZATION
# =============================================================================

func _initialize_system():
	_find_references()
	_setup_shadow_tilemap()
	_setup_fog_of_war_tilemap()
	_connect_world_signals()
	
	call_deferred("_mark_fully_initialized")
	
	if debug_mode:
		print("VisionCullingSystem: Initialized successfully")

func _mark_fully_initialized():
	is_fully_initialized = true
	if debug_mode:
		print("VisionCullingSystem: Fully initialized, ready for vision updates")

func _find_references():
	world = get_parent()
	if not world:
		push_error("VisionCullingSystem: No world found in scene")
		return
	
	thread_manager = get_tree().get_first_node_in_group("thread_manager")
	if not thread_manager:
		if debug_mode:
			push_warning("VisionCullingSystem: No ThreadManager found")
		use_threading = false
	
	var visual_tilemap = world.get_node_or_null("VisualTileMap")
	shadow_tilemap = visual_tilemap.get_node_or_null("VisionTileMap") if visual_tilemap else null

func _setup_shadow_tilemap():
	if not shadow_tilemap:
		_create_shadow_tilemap()
	
	if shadow_tilemap:
		_configure_shadow_tilemap()

func _create_shadow_tilemap():
	shadow_tilemap = TileMap.new()
	shadow_tilemap.name = "ShadowTileMap"
	
	var tileset = TileSet.new()
	tileset.tile_size = Vector2i(32, 32)
	
	var atlas_source = TileSetAtlasSource.new()
	atlas_source.texture_region_size = Vector2i(32, 32)
	
	tileset.add_source(atlas_source, SHADOW_TILE_SOURCE_ID)
	shadow_tilemap.tile_set = tileset
	
	var visual_tilemap = world.get_node_or_null("VisualTileMap")
	if visual_tilemap:
		visual_tilemap.add_child(shadow_tilemap)
	else:
		world.add_child(shadow_tilemap)
	
	if debug_mode:
		print("VisionCullingSystem: Created new shadow tilemap")

func _configure_shadow_tilemap():
	if not shadow_tilemap:
		return
	
	shadow_tilemap.modulate = Color(shadow_color.r, shadow_color.g, shadow_color.b, shadow_opacity)
	shadow_tilemap.z_index = shadow_z_index
	
	if world and world.has_method("get_world_bounds"):
		var bounds = world.get_world_bounds()
		_fill_shadow_area(bounds)
	else:
		_fill_shadow_area(Rect2i(-50, -50, 100, 100))
	
	if debug_mode:
		print("VisionCullingSystem: Configured shadow tilemap with initial shadows")

func _fill_shadow_area(area: Rect2i):
	if not shadow_tilemap or not shadow_tilemap.tile_set:
		return
	
	for x in range(area.position.x, area.position.x + area.size.x):
		for y in range(area.position.y, area.position.y + area.size.y):
			var tile_pos = Vector2i(x, y)
			if shadow_tilemap.tile_set.get_source_count() > 0:
				shadow_tilemap.set_cell(SHADOW_LAYER, tile_pos, SHADOW_TILE_SOURCE_ID, SHADOW_TILE_ATLAS_COORDS)

func _setup_fog_of_war_tilemap():
	if not enable_fog_of_war:
		return
	
	fog_of_war_tilemap = get_node_or_null("FogOfWarTileMap")
	if not fog_of_war_tilemap:
		_create_fog_of_war_tilemap()

func _create_fog_of_war_tilemap():
	fog_of_war_tilemap = TileMap.new()
	fog_of_war_tilemap.name = "FogOfWarTileMap"
	
	if shadow_tilemap and shadow_tilemap.tile_set:
		fog_of_war_tilemap.tile_set = shadow_tilemap.tile_set
	
	fog_of_war_tilemap.modulate = fog_color
	fog_of_war_tilemap.z_index = fog_z_index
	
	var visual_tilemap = world.get_node_or_null("VisualTileMap")
	if visual_tilemap:
		visual_tilemap.add_child(fog_of_war_tilemap)
	else:
		world.add_child(fog_of_war_tilemap)

func _connect_world_signals():
	if not world:
		return
	
	if world.has_signal("tile_changed"):
		if not world.tile_changed.is_connected(_on_world_tile_changed):
			world.tile_changed.connect(_on_world_tile_changed)
	
	if world.has_signal("player_changed_position"):
		if not world.player_changed_position.is_connected(_on_player_position_changed):
			world.player_changed_position.connect(_on_player_position_changed)
	
	if thread_manager and thread_manager.has_signal("task_completed"):
		if not thread_manager.task_completed.is_connected(_on_visibility_task_completed):
			thread_manager.task_completed.connect(_on_visibility_task_completed)

# =============================================================================
# VISION COMPONENT MANAGEMENT
# =============================================================================

func register_vision_component(component: VisionComponent):
	if component in registered_components:
		return
	
	registered_components.append(component)
	
	if not component.vision_changed.is_connected(_on_vision_changed):
		component.vision_changed.connect(_on_vision_changed.bind(component))
	
	if log_vision_updates:
		print("VisionCullingSystem: Registered vision component from ", component.controller.name if component.controller else "unknown entity")
	
	emit_signal("vision_component_registered", component)
	
	if is_fully_initialized and registered_components.size() == 1:
		call_deferred("_force_initial_vision_update")

func unregister_vision_component(component: VisionComponent):
	if not component in registered_components:
		return
	
	registered_components.erase(component)
	
	if component.vision_changed.is_connected(_on_vision_changed):
		component.vision_changed.disconnect(_on_vision_changed)
	
	_remove_component_vision(component)
	
	if log_vision_updates:
		print("VisionCullingSystem: Unregistered vision component")
	
	emit_signal("vision_component_unregistered", component)

# =============================================================================
# VISION PROCESSING
# =============================================================================

func _on_vision_changed(visible_tiles: Array, hidden_tiles: Array, component: VisionComponent):
	if not component in registered_components:
		return
	
	_update_global_vision(component, visible_tiles, hidden_tiles)
	_queue_visibility_update()

func _update_global_vision(component: VisionComponent, visible_tiles: Array, hidden_tiles: Array):
	_remove_component_vision(component)
	
	var changed_tiles: Dictionary = {}
	
	for tile_pos in visible_tiles:
		if tile_pos in global_visible_tiles:
			global_visible_tiles[tile_pos] += 1
		else:
			global_visible_tiles[tile_pos] = 1
		
		if tile_pos in global_hidden_tiles:
			global_hidden_tiles.erase(tile_pos)
		
		if enable_fog_of_war:
			explored_tiles[tile_pos] = true
		
		changed_tiles[tile_pos] = true
		
		if dirty_region_tracking:
			_mark_dirty_region(tile_pos)
	
	component.set_meta("last_visible_tiles", visible_tiles.duplicate())
	component.set_meta("last_hidden_tiles", hidden_tiles.duplicate())
	
	for tile_pos in changed_tiles.keys():
		pending_tile_updates[tile_pos] = true

func _remove_component_vision(component: VisionComponent):
	var last_visible = component.get_meta("last_visible_tiles", [])
	
	for tile_pos in last_visible:
		if tile_pos in global_visible_tiles:
			global_visible_tiles[tile_pos] -= 1
			if global_visible_tiles[tile_pos] <= 0:
				global_visible_tiles.erase(tile_pos)
				
				if not use_combined_vision or not _is_tile_visible_by_any_component(tile_pos):
					global_hidden_tiles[tile_pos] = true
				
				pending_tile_updates[tile_pos] = true
				
				if dirty_region_tracking:
					_mark_dirty_region(tile_pos)

func _is_tile_visible_by_any_component(tile_pos: Vector2i) -> bool:
	return tile_pos in global_visible_tiles and global_visible_tiles[tile_pos] > 0

# =============================================================================
# UPDATE PROCESSING
# =============================================================================

func _update_timers(delta: float):
	update_timer += delta

func _process_pending_updates():
	if update_timer < visibility_update_interval:
		return
		
	update_timer = 0.0
	
	if pending_updates.size() == 0:
		return
	
	if "visibility" in pending_updates:
		if use_threading and thread_manager and not visibility_update_task:
			_queue_threaded_visibility_update()
		else:
			_update_shadow_tilemap()
		pending_updates.erase("visibility")

func _process_batch_updates():
	if tiles_to_update.size() > 0 and not is_processing_batch_update:
		_process_tile_update_batch()

func _handle_initial_update():
	if initial_update_pending and is_fully_initialized and registered_components.size() > 0:
		initial_update_pending = false
		call_deferred("_force_initial_vision_update")

func _force_initial_vision_update():
	if debug_mode:
		print("VisionCullingSystem: Forcing initial vision update")
	
	for component in registered_components:
		if component and is_instance_valid(component):
			component.force_update()
	
	_queue_visibility_update()

func _queue_visibility_update():
	if not pending_updates.has("visibility"):
		pending_updates.append("visibility")

# =============================================================================
# SHADOW TILEMAP MANAGEMENT
# =============================================================================

func _update_shadow_tilemap():
	if not shadow_tilemap:
		return
	
	var all_tiles = _get_all_relevant_tiles()
	tiles_to_update = all_tiles
	update_batch_index = 0

func _get_all_relevant_tiles() -> Array[Vector2i]:
	var relevant_tiles: Array[Vector2i] = []
	var processed_tiles: Dictionary = {}
	
	for tile_pos in pending_tile_updates.keys():
		if not tile_pos in processed_tiles:
			relevant_tiles.append(tile_pos)
			processed_tiles[tile_pos] = true
	
	for tile_pos in global_visible_tiles.keys():
		if not tile_pos in processed_tiles:
			relevant_tiles.append(tile_pos)
			processed_tiles[tile_pos] = true
	
	for tile_pos in global_hidden_tiles.keys():
		if not tile_pos in processed_tiles:
			relevant_tiles.append(tile_pos)
			processed_tiles[tile_pos] = true
	
	for tile_pos in previously_visible_tiles.keys():
		if not tile_pos in processed_tiles:
			relevant_tiles.append(tile_pos)
			processed_tiles[tile_pos] = true
	
	return relevant_tiles

func _process_tile_update_batch():
	if tiles_to_update.size() == 0:
		return
	
	is_processing_batch_update = true
	var end_index = min(update_batch_index + update_batch_size, tiles_to_update.size())
	
	for i in range(update_batch_index, end_index):
		var tile_pos = tiles_to_update[i]
		_update_tile_visibility(tile_pos)
	
	update_batch_index = end_index
	
	if update_batch_index >= tiles_to_update.size():
		_finalize_batch_update()

func _finalize_batch_update():
	tiles_to_update.clear()
	update_batch_index = 0
	is_processing_batch_update = false
	
	if enable_fog_of_war:
		_update_fog_of_war()
	
	pending_tile_updates.clear()
	dirty_regions.clear()
	previously_visible_tiles = global_visible_tiles.duplicate()
	
	emit_signal("visibility_map_updated", global_visible_tiles.keys(), global_hidden_tiles.keys())

func _update_tile_visibility(tile_pos: Vector2i):
	if not shadow_tilemap:
		return
	
	var is_visible = _is_tile_visible_by_any_component(tile_pos)
	
	if is_visible:
		shadow_tilemap.set_cell(SHADOW_LAYER, tile_pos, -1)
	else:
		if shadow_tilemap.tile_set and shadow_tilemap.tile_set.get_source_count() > 0:
			shadow_tilemap.set_cell(SHADOW_LAYER, tile_pos, SHADOW_TILE_SOURCE_ID, SHADOW_TILE_ATLAS_COORDS)

func _update_fog_of_war():
	if not enable_fog_of_war or not fog_of_war_tilemap:
		return
	
	for tile_pos in explored_tiles.keys():
		if not _is_tile_visible_by_any_component(tile_pos):
			fog_of_war_tilemap.set_cell(SHADOW_LAYER, tile_pos, SHADOW_TILE_SOURCE_ID, SHADOW_TILE_ATLAS_COORDS)
		else:
			fog_of_war_tilemap.set_cell(SHADOW_LAYER, tile_pos, -1)

# =============================================================================
# THREADING SUPPORT
# =============================================================================

func _queue_threaded_visibility_update():
	if visibility_update_task:
		return
	
	var task_data = {
		"pending_tile_updates": pending_tile_updates.duplicate(),
		"global_visible_tiles": global_visible_tiles.duplicate(),
		"global_hidden_tiles": global_hidden_tiles.duplicate(),
		"explored_tiles": explored_tiles.duplicate() if enable_fog_of_war else {},
		"enable_fog_of_war": enable_fog_of_war
	}
	
	visibility_update_task = thread_manager.submit_task(
		thread_manager.TaskType.VISIBILITY_UPDATE,
		thread_manager.TaskPriority.HIGH,
		task_data
	)

func _on_visibility_task_completed(task_id: String, result):
	if task_id != visibility_update_task:
		return
	
	visibility_update_task = ""
	
	if result and "tile_updates" in result:
		_apply_threaded_visibility_result(result)

func _apply_threaded_visibility_result(result: Dictionary):
	var tile_updates = result.get("tile_updates", {})
	var fog_updates = result.get("fog_updates", {})
	
	if not shadow_tilemap:
		return
	
	for tile_pos_str in tile_updates.keys():
		var coords = tile_pos_str.split("_")
		var tile_pos = Vector2i(int(coords[0]), int(coords[1]))
		var is_visible = tile_updates[tile_pos_str]
		
		if is_visible:
			shadow_tilemap.set_cell(SHADOW_LAYER, tile_pos, -1)
		else:
			if shadow_tilemap.tile_set and shadow_tilemap.tile_set.get_source_count() > 0:
				shadow_tilemap.set_cell(SHADOW_LAYER, tile_pos, SHADOW_TILE_SOURCE_ID, SHADOW_TILE_ATLAS_COORDS)
	
	if enable_fog_of_war and fog_of_war_tilemap:
		for tile_pos_str in fog_updates.keys():
			var coords = tile_pos_str.split("_")
			var tile_pos = Vector2i(int(coords[0]), int(coords[1]))
			var show_fog = fog_updates[tile_pos_str]
			
			if show_fog:
				fog_of_war_tilemap.set_cell(SHADOW_LAYER, tile_pos, SHADOW_TILE_SOURCE_ID, SHADOW_TILE_ATLAS_COORDS)
			else:
				fog_of_war_tilemap.set_cell(SHADOW_LAYER, tile_pos, -1)
	
	pending_tile_updates.clear()
	dirty_regions.clear()
	previously_visible_tiles = global_visible_tiles.duplicate()
	
	emit_signal("visibility_map_updated", global_visible_tiles.keys(), global_hidden_tiles.keys())

# =============================================================================
# REGION MANAGEMENT
# =============================================================================

func _mark_dirty_region(tile_pos: Vector2i):
	if not dirty_region_tracking:
		return
		
	var region_x = tile_pos.x / DIRTY_REGION_SIZE
	var region_y = tile_pos.y / DIRTY_REGION_SIZE
	var region_key = Vector2i(region_x, region_y)
	dirty_regions[region_key] = true

# =============================================================================
# PUBLIC API
# =============================================================================

func set_z_level(new_z_level: int):
	if new_z_level != current_z_level:
		current_z_level = new_z_level
		refresh_all_vision()

func refresh_all_vision():
	for component in registered_components:
		if component and is_instance_valid(component):
			component.force_update()

func clear_all_vision():
	global_visible_tiles.clear()
	global_hidden_tiles.clear()
	previously_visible_tiles.clear()
	pending_tile_updates.clear()
	dirty_regions.clear()
	
	if shadow_tilemap:
		shadow_tilemap.clear()
	
	if fog_of_war_tilemap:
		fog_of_war_tilemap.clear()

func set_shadow_opacity(opacity: float):
	shadow_opacity = clamp(opacity, 0.0, 1.0)
	
	if shadow_tilemap:
		shadow_tilemap.modulate = Color(shadow_color.r, shadow_color.g, shadow_color.b, shadow_opacity)
	
	emit_signal("shadow_opacity_changed", shadow_opacity)

func set_fog_opacity(opacity: float):
	fog_opacity = clamp(opacity, 0.0, 1.0)
	
	if fog_of_war_tilemap:
		fog_of_war_tilemap.modulate = Color(fog_color.r, fog_color.g, fog_color.b, fog_opacity)

func toggle_fog_of_war(enabled: bool):
	enable_fog_of_war = enabled
	
	if fog_of_war_tilemap:
		fog_of_war_tilemap.visible = enabled
	
	if not enabled:
		explored_tiles.clear()
	
	emit_signal("fog_of_war_toggled", enabled)

func set_shadow_color(color: Color):
	shadow_color = color
	
	if shadow_tilemap:
		shadow_tilemap.modulate = Color(shadow_color.r, shadow_color.g, shadow_color.b, shadow_opacity)

func set_fog_color(color: Color):
	fog_color = color
	
	if fog_of_war_tilemap:
		fog_of_war_tilemap.modulate = Color(fog_color.r, fog_color.g, fog_color.b, fog_opacity)

func is_tile_visible(tile_pos: Vector2i) -> bool:
	return _is_tile_visible_by_any_component(tile_pos)

func is_tile_explored(tile_pos: Vector2i) -> bool:
	return tile_pos in explored_tiles

func reveal_area(center: Vector2i, radius: int):
	for x in range(center.x - radius, center.x + radius + 1):
		for y in range(center.y - radius, center.y + radius + 1):
			var tile_pos = Vector2i(x, y)
			var distance = center.distance_to(Vector2(tile_pos))
			
			if distance <= radius:
				global_visible_tiles[tile_pos] = 999
				if tile_pos in global_hidden_tiles:
					global_hidden_tiles.erase(tile_pos)
				
				if enable_fog_of_war:
					explored_tiles[tile_pos] = true
				
				pending_tile_updates[tile_pos] = true
	
	_queue_visibility_update()

func hide_area(center: Vector2i, radius: int):
	for x in range(center.x - radius, center.x + radius + 1):
		for y in range(center.y - radius, center.y + radius + 1):
			var tile_pos = Vector2i(x, y)
			var distance = center.distance_to(Vector2(tile_pos))
			
			if distance <= radius:
				if tile_pos in global_visible_tiles:
					global_visible_tiles.erase(tile_pos)
				global_hidden_tiles[tile_pos] = true
				pending_tile_updates[tile_pos] = true
	
	_queue_visibility_update()

func get_visibility_info() -> Dictionary:
	return {
		"visible_tiles_count": global_visible_tiles.size(),
		"hidden_tiles_count": global_hidden_tiles.size(),
		"explored_tiles_count": explored_tiles.size(),
		"registered_components": registered_components.size(),
		"current_z_level": current_z_level,
		"dirty_regions": dirty_regions.size(),
		"pending_updates": pending_tile_updates.size(),
		"is_fully_initialized": is_fully_initialized,
		"fog_of_war_enabled": enable_fog_of_war,
		"threading_enabled": use_threading,
		"performance_stats": _get_performance_stats() if show_performance_stats else {}
	}

func _get_performance_stats() -> Dictionary:
	return {
		"update_batch_size": update_batch_size,
		"visibility_update_interval": visibility_update_interval,
		"active_vision_components": registered_components.size(),
		"cache_size": visibility_cache.size()
	}

# =============================================================================
# SIGNAL HANDLERS
# =============================================================================

func _on_world_tile_changed(tile_coords: Vector2i, z_level: int, old_data, new_data):
	if z_level != current_z_level:
		return
	
	var was_blocking = false
	var is_blocking = false
	
	if old_data and world.has_method("is_wall_at"):
		was_blocking = world.is_wall_at(tile_coords, z_level)
	
	if new_data and world.has_method("is_wall_at"):
		is_blocking = world.is_wall_at(tile_coords, z_level)
	
	if was_blocking != is_blocking:
		_refresh_vision_around_tile(tile_coords)

func _refresh_vision_around_tile(tile_pos: Vector2i):
	for component in registered_components:
		if not component or not is_instance_valid(component):
			continue
		
		var entity_pos = component.get_entity_tile_position()
		var distance = entity_pos.distance_to(Vector2(tile_pos))
		
		if distance <= component.vision_radius + 1:
			component.force_update()

func _on_player_position_changed(position: Vector2, z_level: int):
	if z_level != current_z_level:
		set_z_level(z_level)

# =============================================================================
# CLEANUP
# =============================================================================

func _exit_tree():
	clear_all_vision()
	
	for component in registered_components:
		if component and is_instance_valid(component):
			if component.vision_changed.is_connected(_on_vision_changed):
				component.vision_changed.disconnect(_on_vision_changed)
	
	if thread_manager and thread_manager.task_completed.is_connected(_on_visibility_task_completed):
		thread_manager.task_completed.disconnect(_on_visibility_task_completed)
