extends Node
class_name VisionComponent

const DEFAULT_VISION_RADIUS: int = 8
const MAX_VISION_RADIUS: int = 20
const VISION_UPDATE_INTERVAL: float = 0.1
const SHADOWCAST_MULTIPLIERS = [
	[1, 0, 0, -1, -1, 0, 0, 1],
	[0, 1, -1, 0, 0, -1, 1, 0],
	[0, 1, 1, 0, 0, -1, -1, 0],
	[1, 0, 0, 1, -1, 0, 0, -1]
]

signal vision_changed(visible_tiles: Array, hidden_tiles: Array)
signal vision_radius_changed(new_radius: int)

@export var vision_radius: int = DEFAULT_VISION_RADIUS : set = set_vision_radius
@export var update_vision_on_move: bool = true
@export var continuous_updates: bool = false
@export var vision_blocked_by_doors: bool = false
@export var use_threading: bool = true

var controller: Node = null
var world: Node = null
var vision_culling_system: Node = null
var thread_manager: Node = null

var current_visible_tiles: Array[Vector2i] = []
var current_hidden_tiles: Array[Vector2i] = []
var last_position: Vector2i = Vector2i(-999, -999)
var last_z_level: int = -1

var update_timer: float = 0.0
var needs_update: bool = true
var is_processing_vision: bool = false
var pending_vision_task: String = ""

var vision_cache: Dictionary = {}
var cache_valid: bool = false
var cache_max_size: int = 50

var wall_tilemap: TileMap = null

var peer_id: int = 1
var is_local_player: bool = false

func _ready():
	await get_tree().process_frame
	initialize_vision_component()

func _process(delta: float):
	if not is_local_player:
		return
	
	update_timer += delta
	
	if continuous_updates and update_timer >= VISION_UPDATE_INTERVAL:
		update_timer = 0.0
		check_for_vision_update()
	elif needs_update and not is_processing_vision:
		update_vision()
		needs_update = false

func initialize_vision_component():
	find_references()
	connect_signals()
	register_with_vision_system()
	
	if controller and controller.has_meta("peer_id"):
		peer_id = controller.get_meta("peer_id")
		is_local_player = controller.get_meta("is_player", false)
		set_multiplayer_authority(peer_id)
	
	await get_tree().process_frame
	await get_tree().process_frame
	
	if is_local_player:
		update_vision()

func find_references():
	controller = get_parent()
	world = get_tree().get_first_node_in_group("world")
	vision_culling_system = world.get_node_or_null("VisionCullingSystem") if world else null
	thread_manager = get_tree().get_first_node_in_group("thread_manager")
	
	if world:
		var visual_tilemap = world.get_node_or_null("VisualTileMap")
		if visual_tilemap:
			wall_tilemap = visual_tilemap.get_node_or_null("WallTileMap")
		if not wall_tilemap:
			wall_tilemap = world.get_node_or_null("WallTileMap")
	
	if not controller:
		push_error("VisionComponent: No controller found as parent")
	if not world:
		push_error("VisionComponent: No world found in scene")
	if not vision_culling_system:
		push_warning("VisionComponent: No VisionCullingSystem found in world")
	if not thread_manager:
		push_warning("VisionComponent: No ThreadManager found, using main thread")
		use_threading = false
	if not wall_tilemap:
		push_warning("VisionComponent: No WallTileMap found, window detection will not work")

func connect_signals():
	if not controller:
		return
	
	if controller.has_signal("tile_changed"):
		if not controller.tile_changed.is_connected(_on_entity_moved):
			controller.tile_changed.connect(_on_entity_moved)
	
	var movement_component = controller.get_node_or_null("MovementComponent")
	if movement_component and movement_component.has_signal("tile_changed"):
		if not movement_component.tile_changed.is_connected(_on_entity_moved):
			movement_component.tile_changed.connect(_on_entity_moved)
	
	if thread_manager and thread_manager.has_signal("task_completed"):
		if not thread_manager.task_completed.is_connected(_on_vision_task_completed):
			thread_manager.task_completed.connect(_on_vision_task_completed)

func register_with_vision_system():
	if vision_culling_system and vision_culling_system.has_method("register_vision_component"):
		vision_culling_system.register_vision_component(self)

func set_vision_radius(new_radius: int):
	new_radius = clamp(new_radius, 1, MAX_VISION_RADIUS)
	if new_radius != vision_radius:
		vision_radius = new_radius
		clear_cache()
		needs_update = true
		emit_signal("vision_radius_changed", vision_radius)
		
		if is_multiplayer_authority():
			sync_vision_radius.rpc(vision_radius)

func check_for_vision_update():
	if not controller or is_processing_vision or not is_local_player:
		return
	
	var current_pos = get_entity_tile_position()
	var current_z = get_entity_z_level()
	
	if current_pos != last_position or current_z != last_z_level:
		update_vision()

func update_vision():
	if not controller or not world or is_processing_vision or not is_local_player:
		return
	
	var entity_pos = get_entity_tile_position()
	var z_level = get_entity_z_level()
	
	var cache_key = generate_cache_key(entity_pos, z_level, vision_radius)
	if cache_valid and cache_key in vision_cache:
		apply_cached_vision(vision_cache[cache_key])
		return
	
	if use_threading and thread_manager:
		queue_threaded_vision_calculation(entity_pos, z_level)
	else:
		var vision_result = calculate_shadowcast_vision(entity_pos, z_level)
		cache_and_apply_vision(cache_key, vision_result)
	
	last_position = entity_pos
	last_z_level = z_level

func queue_threaded_vision_calculation(entity_pos: Vector2i, z_level: int):
	if is_processing_vision:
		return
	
	is_processing_vision = true
	
	var task_data = {
		"entity_pos": entity_pos,
		"z_level": z_level,
		"vision_radius": vision_radius,
		"vision_blocked_by_doors": vision_blocked_by_doors,
		"world_data": get_vision_world_data(entity_pos, z_level)
	}
	
	pending_vision_task = thread_manager.submit_task(
		thread_manager.TaskType.VISION_CALCULATION,
		thread_manager.TaskPriority.HIGH,
		task_data
	)

func get_vision_world_data(center_pos: Vector2i, z_level: int) -> Dictionary:
	var world_data = {}
	var radius = vision_radius + 2
	
	for x in range(center_pos.x - radius, center_pos.x + radius + 1):
		for y in range(center_pos.y - radius, center_pos.y + radius + 1):
			var tile_pos = Vector2i(x, y)
			world_data[tile_pos] = {
				"is_wall": world.is_wall_at(tile_pos, z_level) if world.has_method("is_wall_at") else false,
				"blocks_vision": is_vision_blocking_tile(tile_pos, z_level)
			}
	
	return world_data

func calculate_shadowcast_vision(center_pos: Vector2i, z_level: int) -> Dictionary:
	var visible_tiles: Array[Vector2i] = []
	var hidden_tiles: Array[Vector2i] = []
	var visible_set: Dictionary = {}
	
	visible_tiles.append(center_pos)
	visible_set[center_pos] = true
	
	for octant in range(8):
		cast_light(center_pos, 1, 1.0, 0.0, vision_radius, 
				  SHADOWCAST_MULTIPLIERS[0][octant], SHADOWCAST_MULTIPLIERS[1][octant],
				  SHADOWCAST_MULTIPLIERS[2][octant], SHADOWCAST_MULTIPLIERS[3][octant],
				  visible_set, z_level)
	
	for tile_pos in visible_set.keys():
		visible_tiles.append(tile_pos)
	
	var min_x = center_pos.x - vision_radius
	var max_x = center_pos.x + vision_radius
	var min_y = center_pos.y - vision_radius
	var max_y = center_pos.y + vision_radius
	
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			var tile_pos = Vector2i(x, y)
			var distance = center_pos.distance_to(Vector2(tile_pos))
			
			if distance <= vision_radius and not tile_pos in visible_set:
				hidden_tiles.append(tile_pos)
	
	return {
		"visible": visible_tiles,
		"hidden": hidden_tiles
	}

func cast_light(center: Vector2i, row: int, start_slope: float, end_slope: float, 
			   radius: int, xx: int, xy: int, yx: int, yy: int, 
			   visible_set: Dictionary, z_level: int):
	if start_slope < end_slope:
		return
	
	var next_start_slope = start_slope
	
	for i in range(row, radius + 1):
		var blocked = false
		
		for dx in range(-i, i + 1):
			var dy = -i
			var l_slope = (dx - 0.5) / (dy + 0.5)
			var r_slope = (dx + 0.5) / (dy - 0.5)
			
			if start_slope < r_slope:
				continue
			elif end_slope > l_slope:
				break
			
			var sax = dx * xx + dy * xy
			var say = dx * yx + dy * yy
			var ax = center.x + sax
			var ay = center.y + say
			var tile_pos = Vector2i(ax, ay)
			
			if pow(sax, 2) + pow(say, 2) < pow(radius, 2):
				visible_set[tile_pos] = true
			
			if blocked:
				if is_vision_blocking_tile(tile_pos, z_level):
					next_start_slope = r_slope
					continue
				else:
					blocked = false
					start_slope = next_start_slope
			else:
				if is_vision_blocking_tile(tile_pos, z_level) and i < radius:
					blocked = true
					cast_light(center, i + 1, start_slope, l_slope, radius,
							  xx, xy, yx, yy, visible_set, z_level)
					next_start_slope = r_slope
		
		if blocked:
			break

func is_vision_blocking_tile(tile_pos: Vector2i, z_level: int) -> bool:
	if not world:
		return false
	
	if world.has_method("is_wall_at") and world.is_wall_at(tile_pos, z_level):
		if is_window_tile(tile_pos):
			return false
		return true
	
	if vision_blocked_by_doors:
		var tile_data = world.get_tile_data(tile_pos, z_level)
		if tile_data and "door" in tile_data and tile_data.door:
			if "closed" in tile_data.door and tile_data.door.closed:
				return true
	
	return has_vision_blocking_entity(tile_pos, z_level)

func is_window_tile(tile_pos: Vector2i) -> bool:
	if not wall_tilemap:
		return false
	
	var tile_data = wall_tilemap.get_cell_tile_data(0, tile_pos)
	if not tile_data:
		return false
	
	if tile_data.get_custom_data("is_window"):
		return true
	
	if tile_data.get_custom_data("transparent"):
		return true
	
	var window_type = tile_data.get_custom_data("window_type")
	if window_type and window_type != "":
		return true
	
	var blocks_vision = tile_data.get_custom_data("blocks_vision")
	if blocks_vision != null and not blocks_vision:
		return true
	
	return false

func has_vision_blocking_entity(tile_pos: Vector2i, z_level: int) -> bool:
	if not world or not world.tile_occupancy_system:
		return false
	
	var entities = world.tile_occupancy_system.get_entities_at(tile_pos, z_level)
	for entity in entities:
		if entity and "blocks_vision" in entity and entity.blocks_vision:
			return true
	
	return false

func _on_vision_task_completed(task_id: String, result):
	if task_id != pending_vision_task:
		return
	
	is_processing_vision = false
	pending_vision_task = ""
	
	if result and "visible" in result:
		var entity_pos = get_entity_tile_position()
		var z_level = get_entity_z_level()
		var cache_key = generate_cache_key(entity_pos, z_level, vision_radius)
		cache_and_apply_vision(cache_key, result)

func cache_and_apply_vision(cache_key: String, vision_result: Dictionary):
	manage_cache_size()
	vision_cache[cache_key] = vision_result
	cache_valid = true
	apply_vision_result(vision_result)

func apply_vision_result(vision_result: Dictionary):
	var new_visible = vision_result.visible
	var new_hidden = vision_result.hidden
	
	if not arrays_equal(current_visible_tiles, new_visible) or not arrays_equal(current_hidden_tiles, new_hidden):
		current_visible_tiles = new_visible.duplicate()
		current_hidden_tiles = new_hidden.duplicate()
		
		emit_signal("vision_changed", current_visible_tiles, current_hidden_tiles)

func apply_cached_vision(cached_result: Dictionary):
	apply_vision_result(cached_result)

func manage_cache_size():
	if vision_cache.size() >= cache_max_size:
		var keys_to_remove = vision_cache.keys().slice(0, cache_max_size / 4)
		for key in keys_to_remove:
			vision_cache.erase(key)

func generate_cache_key(pos: Vector2i, z_level: int, radius: int) -> String:
	return str(pos.x) + "_" + str(pos.y) + "_" + str(z_level) + "_" + str(radius)

func clear_cache():
	vision_cache.clear()
	cache_valid = false

func arrays_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	
	for i in range(a.size()):
		if a[i] != b[i]:
			return false
	
	return true

func get_entity_tile_position() -> Vector2i:
	if not controller:
		return Vector2i.ZERO
	
	if "current_tile_position" in controller:
		return controller.current_tile_position
	elif controller.has_method("get_current_tile_position"):
		return controller.get_current_tile_position()
	elif "movement_component" in controller and controller.movement_component:
		if "current_tile_position" in controller.movement_component:
			return controller.movement_component.current_tile_position
	elif "position" in controller and world:
		return world.get_tile_at(controller.position)
	
	return Vector2i.ZERO

func get_entity_z_level() -> int:
	if not controller:
		return 0
	
	if "current_z_level" in controller:
		return controller.current_z_level
	elif controller.has_method("get_current_z_level"):
		return controller.get_current_z_level()
	
	return 0

func get_visible_tiles() -> Array[Vector2i]:
	return current_visible_tiles.duplicate()

func get_hidden_tiles() -> Array[Vector2i]:
	return current_hidden_tiles.duplicate()

func is_tile_visible(tile_pos: Vector2i) -> bool:
	return tile_pos in current_visible_tiles

func force_update():
	if not is_local_player:
		return
	
	clear_cache()
	needs_update = true
	if not is_processing_vision:
		update_vision()

func set_continuous_updates(enabled: bool):
	if is_multiplayer_authority():
		continuous_updates = enabled
		if enabled:
			needs_update = true
		
		sync_continuous_updates.rpc(enabled)

func _on_entity_moved(old_tile: Vector2i, new_tile: Vector2i):
	if update_vision_on_move and is_local_player:
		needs_update = true

@rpc("any_peer", "call_local", "reliable")
func sync_vision_radius(new_radius: int):
	if is_multiplayer_authority():
		return
	
	if new_radius != vision_radius:
		vision_radius = new_radius
		clear_cache()
		needs_update = true
		emit_signal("vision_radius_changed", vision_radius)

@rpc("any_peer", "call_local", "reliable")
func sync_continuous_updates(enabled: bool):
	if is_multiplayer_authority():
		return
	
	continuous_updates = enabled
	if enabled:
		needs_update = true

@rpc("any_peer", "call_local", "reliable")
func sync_vision_settings(radius: int, blocks_doors: bool, threading: bool):
	if is_multiplayer_authority():
		return
	
	vision_radius = radius
	vision_blocked_by_doors = blocks_doors
	use_threading = threading
	clear_cache()
	needs_update = true

func sync_all_vision_settings():
	if is_multiplayer_authority():
		sync_vision_settings.rpc(vision_radius, vision_blocked_by_doors, use_threading)

func _exit_tree():
	if vision_culling_system and vision_culling_system.has_method("unregister_vision_component"):
		vision_culling_system.unregister_vision_component(self)
	
	if thread_manager and thread_manager.task_completed.is_connected(_on_vision_task_completed):
		thread_manager.task_completed.disconnect(_on_vision_task_completed)
