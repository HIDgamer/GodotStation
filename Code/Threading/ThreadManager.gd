extends Node
class_name ThreadManager

var MAX_WORKER_THREADS = 2
var TASK_QUEUE_LIMIT = 30
var FRAME_BUDGET_MS = 3.0
var THREAD_SHUTDOWN_TIMEOUT_MS = 500
var TASK_TIMEOUT_MS = 3000

enum TaskPriority {
	CRITICAL,
	HIGH,
	MEDIUM,
	LOW,
	BACKGROUND
}

enum TaskType {
	ATMOSPHERE_CALCULATION,
	ROOM_DETECTION,
	PATHFINDING_CALCULATION,
	INVENTORY_SORTING,
	ASSET_METADATA_EXTRACTION,
	VISION_CALCULATION,
	VISIBILITY_UPDATE,
	SCENE_INSTANTIATION,
	ENTITY_SPAWNING,
	CLEANUP
}

var worker_threads = []
var task_queue = []
var completed_tasks = []
var active_tasks = {}
var thread_mutex = Mutex.new()
var result_mutex = Mutex.new()
var world_data_mutex = Mutex.new()

var scene_pools = {}
var scene_cache = {}
var pooled_scene_limits = {
	"Characters": 3,
	"Effects": 8,
	"Items": 10,
	"UI": 2
}

var task_performance = {}
var world_ref = null
var thread_safe_world_data = {}

var is_shutting_down = false
var is_initialized = false
var threads_created = false
var last_task_time = 0
var idle_thread_shutdown_delay = 8000
var performance_check_interval = 15000
var last_performance_check = 0

signal task_completed(task_id, result)
signal performance_warning(task_type, execution_time)
signal thread_error(thread_id, error_message)

func _init():
	name = "ThreadManager"
	add_to_group("thread_manager")

func _ready():
	set_process(false)
	is_initialized = true

func _process(delta):
	if is_shutting_down or not is_initialized:
		return
	
	var frame_start = Time.get_ticks_msec()
	var budget_remaining = FRAME_BUDGET_MS
	
	if has_pending_work():
		if not threads_created:
			create_worker_threads_if_needed()
			budget_remaining -= (Time.get_ticks_msec() - frame_start)
			if budget_remaining <= 0:
				return
		
		process_completed_tasks()
		budget_remaining -= (Time.get_ticks_msec() - frame_start)
		if budget_remaining <= 1:
			return
		
		process_main_thread_tasks(budget_remaining)
	else:
		check_idle_thread_shutdown()
	
	var current_time = Time.get_ticks_msec()
	if current_time - last_performance_check > performance_check_interval:
		cleanup_old_performance_data()
		last_performance_check = current_time

func has_pending_work() -> bool:
	return task_queue.size() > 0 or completed_tasks.size() > 0 or active_tasks.size() > 0

func create_worker_threads_if_needed():
	if threads_created or is_shutting_down:
		return
	
	for i in range(MAX_WORKER_THREADS):
		var worker = WorkerThread.new()
		worker.thread_id = i
		worker.task_queue = task_queue
		worker.completed_tasks = completed_tasks
		worker.thread_mutex = thread_mutex
		worker.result_mutex = result_mutex
		worker.manager = self
		
		if worker.start():
			worker_threads.append(worker)
		else:
			worker.cleanup()
	
	threads_created = true
	set_process(true)

func check_idle_thread_shutdown():
	var current_time = Time.get_ticks_msec()
	
	if current_time - last_task_time > idle_thread_shutdown_delay and threads_created:
		shutdown_idle_threads()

func shutdown_idle_threads():
	for worker in worker_threads:
		if worker and is_instance_valid(worker):
			worker.request_shutdown()
	
	worker_threads.clear()
	threads_created = false
	set_process(false)

func submit_task(task_type: TaskType, priority: TaskPriority, task_data: Dictionary, callback: Callable = Callable()) -> String:
	if is_shutting_down or not is_initialized:
		return ""
	
	if task_queue.size() >= TASK_QUEUE_LIMIT:
		return ""
	
	var task_id = generate_task_id()
	last_task_time = Time.get_ticks_msec()
	
	var task = {
		"id": task_id,
		"type": task_type,
		"priority": priority,
		"data": task_data,
		"callback": callback,
		"submitted_time": last_task_time,
		"timeout": last_task_time + TASK_TIMEOUT_MS
	}
	
	if priority == TaskPriority.CRITICAL:
		var result = execute_task_on_main_thread(task)
		if callback.is_valid():
			callback.call(task_id, result)
		return task_id
	
	thread_mutex.lock()
	task_queue.append(task)
	if task_queue.size() > 1:
		task_queue.sort_custom(func(a, b): return a.priority < b.priority)
	thread_mutex.unlock()
	
	active_tasks[task_id] = task
	
	if not is_processing():
		set_process(true)
	
	return task_id

func process_completed_tasks():
	result_mutex.lock()
	var tasks_to_process = completed_tasks.duplicate()
	completed_tasks.clear()
	result_mutex.unlock()
	
	for task_result in tasks_to_process:
		var task_id = task_result.id
		var result = task_result.result
		var execution_time = task_result.execution_time
		var success = task_result.get("success", true)
		
		update_task_performance(task_result.type, execution_time, not success)
		
		task_completed.emit(task_id, result)
		
		if task_result.has("callback") and task_result.callback.is_valid():
			task_result.callback.call(task_id, result)
		
		if task_id in active_tasks:
			active_tasks.erase(task_id)

func process_main_thread_tasks(budget_ms: float):
	var budget_per_task = budget_ms / 2.0
	
	process_pending_scene_creations(budget_per_task)
	process_pending_cleanup(budget_per_task)

func execute_task_on_main_thread(task: Dictionary):
	var start_time = Time.get_ticks_msec()
	var result = null
	
	match task.type:
		TaskType.SCENE_INSTANTIATION:
			result = instantiate_scene(task.data)
		TaskType.ENTITY_SPAWNING:
			result = spawn_entity(task.data)
		TaskType.CLEANUP:
			result = perform_cleanup(task.data)
		_:
			result = {"error": "Unknown task type"}
	
	var execution_time = Time.get_ticks_msec() - start_time
	update_task_performance(task.type, execution_time, false)
	
	return result

func execute_worker_task(task: Dictionary):
	match task.type:
		TaskType.ATMOSPHERE_CALCULATION:
			return calculate_atmosphere_data(task.data)
		TaskType.ROOM_DETECTION:
			return detect_rooms(task.data)
		TaskType.PATHFINDING_CALCULATION:
			return calculate_pathfinding(task.data)
		TaskType.INVENTORY_SORTING:
			return sort_inventory_data(task.data)
		TaskType.ASSET_METADATA_EXTRACTION:
			return extract_asset_metadata(task.data)
		TaskType.VISION_CALCULATION:
			return calculate_vision_threaded(task.data)
		TaskType.VISIBILITY_UPDATE:
			return process_visibility_update_threaded(task.data)
		_:
			return {"error": "Unknown worker task type"}

func queue_atmosphere_processing(coordinates: Array, priority: TaskPriority = TaskPriority.MEDIUM) -> String:
	if coordinates.size() > 50:
		coordinates = coordinates.slice(0, 50)
	
	var task_data = {
		"coordinates": coordinates,
		"world_data": get_thread_safe_world_snapshot()
	}
	return submit_task(TaskType.ATMOSPHERE_CALCULATION, priority, task_data)

func queue_room_detection(z_level: int, priority: TaskPriority = TaskPriority.MEDIUM) -> String:
	var task_data = {
		"z_level": z_level,
		"world_data": get_thread_safe_world_snapshot(z_level)
	}
	return submit_task(TaskType.ROOM_DETECTION, priority, task_data)

func queue_vision_calculation(entity_pos: Vector2i, z_level: int, vision_radius: int, vision_blocked_by_doors: bool, world_data: Dictionary, priority: TaskPriority = TaskPriority.HIGH) -> String:
	var task_data = {
		"entity_pos": entity_pos,
		"z_level": z_level,
		"vision_radius": min(vision_radius, 10),
		"vision_blocked_by_doors": vision_blocked_by_doors,
		"world_data": world_data
	}
	return submit_task(TaskType.VISION_CALCULATION, priority, task_data)

func queue_visibility_update(tile_updates: Dictionary, visible_tiles: Dictionary, hidden_tiles: Dictionary, explored_tiles: Dictionary, enable_fog_of_war: bool) -> String:
	var task_data = {
		"pending_tile_updates": tile_updates,
		"global_visible_tiles": visible_tiles,
		"global_hidden_tiles": hidden_tiles,
		"explored_tiles": explored_tiles,
		"enable_fog_of_war": enable_fog_of_war
	}
	return submit_task(TaskType.VISIBILITY_UPDATE, TaskPriority.HIGH, task_data)

func queue_inventory_operations(inventory_data: Array, priority: TaskPriority = TaskPriority.LOW) -> String:
	if inventory_data.size() > 5:
		inventory_data = inventory_data.slice(0, 5)
	
	var task_data = {
		"inventories": inventory_data
	}
	return submit_task(TaskType.INVENTORY_SORTING, priority, task_data)

func calculate_vision_threaded(task_data: Dictionary) -> Dictionary:
	var entity_pos = task_data.get("entity_pos", Vector2i.ZERO)
	var z_level = task_data.get("z_level", 0)
	var vision_radius = task_data.get("vision_radius", 8)
	var vision_blocked_by_doors = task_data.get("vision_blocked_by_doors", false)
	var world_data = task_data.get("world_data", {})
	
	return calculate_shadowcast_vision_threaded(entity_pos, z_level, vision_radius, vision_blocked_by_doors, world_data)

func calculate_shadowcast_vision_threaded(center_pos: Vector2i, z_level: int, vision_radius: int, vision_blocked_by_doors: bool, world_data: Dictionary) -> Dictionary:
	var visible_tiles: Array[Vector2i] = []
	var hidden_tiles: Array[Vector2i] = []
	var visible_set: Dictionary = {}
	
	visible_tiles.append(center_pos)
	visible_set[center_pos] = true
	
	var shadowcast_multipliers = [
		[1, 0, 0, -1, -1, 0, 0, 1],
		[0, 1, -1, 0, 0, -1, 1, 0],
		[0, 1, 1, 0, 0, -1, -1, 0],
		[1, 0, 0, 1, -1, 0, 0, -1]
	]
	
	for octant in range(8):
		cast_light_threaded(center_pos, 1, 1.0, 0.0, vision_radius,
						  shadowcast_multipliers[0][octant], shadowcast_multipliers[1][octant],
						  shadowcast_multipliers[2][octant], shadowcast_multipliers[3][octant],
						  visible_set, z_level, vision_blocked_by_doors, world_data)
	
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

func cast_light_threaded(center: Vector2i, row: int, start_slope: float, end_slope: float,
						radius: int, xx: int, xy: int, yx: int, yy: int,
						visible_set: Dictionary, z_level: int, vision_blocked_by_doors: bool, world_data: Dictionary):
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
				if is_vision_blocking_tile_threaded(tile_pos, z_level, vision_blocked_by_doors, world_data):
					next_start_slope = r_slope
					continue
				else:
					blocked = false
					start_slope = next_start_slope
			else:
				if is_vision_blocking_tile_threaded(tile_pos, z_level, vision_blocked_by_doors, world_data) and i < radius:
					blocked = true
					cast_light_threaded(center, i + 1, start_slope, l_slope, radius,
									   xx, xy, yx, yy, visible_set, z_level, vision_blocked_by_doors, world_data)
					next_start_slope = r_slope
		
		if blocked:
			break

func is_vision_blocking_tile_threaded(tile_pos: Vector2i, z_level: int, vision_blocked_by_doors: bool, world_data: Dictionary) -> bool:
	if tile_pos in world_data:
		var tile_data = world_data[tile_pos]
		return tile_data.get("blocks_vision", false)
	return false

func process_visibility_update_threaded(task_data: Dictionary) -> Dictionary:
	var pending_tile_updates = task_data.get("pending_tile_updates", {})
	var global_visible_tiles = task_data.get("global_visible_tiles", {})
	var global_hidden_tiles = task_data.get("global_hidden_tiles", {})
	var explored_tiles = task_data.get("explored_tiles", {})
	var enable_fog_of_war = task_data.get("enable_fog_of_war", false)
	
	var tile_updates = {}
	var fog_updates = {}
	
	for tile_pos in pending_tile_updates.keys():
		var tile_pos_str = str(tile_pos.x) + "_" + str(tile_pos.y)
		var is_visible = tile_pos in global_visible_tiles and global_visible_tiles[tile_pos] > 0
		tile_updates[tile_pos_str] = is_visible
		
		if enable_fog_of_war:
			var is_explored = tile_pos in explored_tiles
			var show_fog = is_explored and not is_visible
			fog_updates[tile_pos_str] = show_fog
	
	return {
		"tile_updates": tile_updates,
		"fog_updates": fog_updates
	}

func calculate_atmosphere_data(task_data: Dictionary) -> Dictionary:
	var coordinates = task_data.get("coordinates", [])
	var world_data = task_data.get("world_data", {})
	var results = []
	
	for i in range(min(coordinates.size(), 25)):
		var coord = coordinates[i]
		var pressure = calculate_pressure_at_coordinate(coord, world_data)
		var temperature = calculate_temperature_at_coordinate(coord, world_data)
		var gas_mix = calculate_gas_mixture(coord, world_data)
		
		results.append({
			"coordinate": coord,
			"pressure": pressure,
			"temperature": temperature,
			"gas_mix": gas_mix
		})
	
	return {"atmosphere_updates": results}

func detect_rooms(task_data: Dictionary) -> Dictionary:
	var z_level = task_data.get("z_level", 0)
	var world_data = task_data.get("world_data", {})
	
	var rooms = {}
	var visited = {}
	var room_id = 0
	var processed_coords = 0
	var max_coords = 100
	
	for coord in world_data.keys():
		if processed_coords >= max_coords:
			break
		
		if coord in visited:
			continue
		
		var room_tiles = flood_fill_room(coord, world_data, visited)
		if room_tiles.size() > 0:
			rooms[room_id] = {
				"id": room_id,
				"tiles": room_tiles,
				"z_level": z_level,
				"area": room_tiles.size()
			}
			room_id += 1
		
		processed_coords += 1
	
	return {"rooms": rooms, "z_level": z_level}

func sort_inventory_data(task_data: Dictionary) -> Dictionary:
	var inventories = task_data.get("inventories", [])
	var sorted_inventories = []
	
	for inventory in inventories:
		var items = inventory.get("items", [])
		var sorted_items = sort_items_by_category(items)
		
		sorted_inventories.append({
			"inventory_id": inventory.get("id", "unknown"),
			"sorted_items": sorted_items,
			"item_count": sorted_items.size()
		})
	
	return {"sorted_inventories": sorted_inventories}

func get_pooled_scene(category: String) -> Node:
	if not scene_pools.has(category) or scene_pools[category].is_empty():
		return null
	
	return scene_pools[category].pop_front()

func return_scene_to_pool(scene: Node, category: String):
	if not scene or not is_instance_valid(scene):
		return
	
	if not scene_pools.has(category):
		scene_pools[category] = []
	
	reset_scene_for_pooling(scene)
	
	var limit = pooled_scene_limits.get(category, 8)
	if scene_pools[category].size() < limit:
		scene_pools[category].append(scene)
	else:
		scene.queue_free()

func reset_scene_for_pooling(scene: Node):
	if scene.has_method("set_position"):
		scene.set_position(Vector2.ZERO)
	
	if scene.has_method("set_visible"):
		scene.set_visible(true)
	
	if scene.has_method("reset_for_pool"):
		scene.reset_for_pool()

func set_world_reference(world):
	world_ref = world

func get_thread_safe_world_snapshot(z_level: int = -1) -> Dictionary:
	if not world_ref:
		return {}
	
	world_data_mutex.lock()
	var data = {}
	
	if world_ref.has_method("get_thread_safe_data"):
		var full_data = world_ref.get_thread_safe_data()
		if z_level >= 0 and z_level in full_data:
			data = full_data[z_level].duplicate(true)
		else:
			data = full_data.duplicate(true)
	elif world_ref.has_method("get_tile_data"):
		data = _extract_basic_world_data(z_level)
	
	world_data_mutex.unlock()
	return data

func _extract_basic_world_data(z_level: int) -> Dictionary:
	var data = {}
	
	if z_level >= 0:
		for x in range(-25, 26):
			for y in range(-25, 26):
				var tile_pos = Vector2i(x, y)
				var tile_data = world_ref.get_tile_data(tile_pos, z_level)
				if tile_data:
					data[tile_pos] = {"blocks_vision": tile_data.get("is_walkable", true) == false}
	
	return data

func update_task_performance(task_type: TaskType, execution_time: float, is_failure: bool):
	if not task_performance.has(task_type):
		task_performance[task_type] = {
			"total_time": 0.0,
			"count": 0,
			"avg_time": 0.0,
			"max_time": 0.0,
			"failures": 0
		}
	
	var perf = task_performance[task_type]
	perf.total_time += execution_time
	perf.count += 1
	perf.avg_time = perf.total_time / perf.count
	perf.max_time = max(perf.max_time, execution_time)
	
	if is_failure:
		perf.failures += 1
	
	if execution_time > 50:
		performance_warning.emit(task_type, execution_time)

func cleanup_old_performance_data():
	for task_type in task_performance:
		var perf = task_performance[task_type]
		if perf.count > 1000:
			perf.total_time *= 0.8
			perf.count = int(perf.count * 0.8)
			perf.avg_time = perf.total_time / perf.count

func generate_task_id() -> String:
	return "task_" + str(Time.get_ticks_msec()) + "_" + str(randi() % 1000)

func shutdown_all_threads():
	if is_shutting_down:
		return
	
	is_shutting_down = true
	set_process(false)
	
	for worker in worker_threads:
		if worker and is_instance_valid(worker):
			worker.request_shutdown()
	
	var shutdown_start = Time.get_ticks_msec()
	
	while worker_threads.size() > 0 and (Time.get_ticks_msec() - shutdown_start) < THREAD_SHUTDOWN_TIMEOUT_MS:
		for i in range(worker_threads.size() - 1, -1, -1):
			var worker = worker_threads[i]
			if not worker or not is_instance_valid(worker) or worker.is_shutdown():
				worker_threads.remove_at(i)
		
		if worker_threads.size() > 0:
			await get_tree().process_frame
	
	for worker in worker_threads:
		if worker and is_instance_valid(worker):
			worker.force_shutdown()
	
	worker_threads.clear()
	task_queue.clear()
	active_tasks.clear()

func calculate_pressure_at_coordinate(coord: Vector2i, world_data: Dictionary) -> float:
	return 101.3 + randf_range(-1.0, 1.0)

func calculate_temperature_at_coordinate(coord: Vector2i, world_data: Dictionary) -> float:
	return 293.0 + randf_range(-3.0, 3.0)

func calculate_gas_mixture(coord: Vector2i, world_data: Dictionary) -> Dictionary:
	return {"oxygen": 0.21, "nitrogen": 0.78, "other": 0.01}

func flood_fill_room(start_coord: Vector2i, world_data: Dictionary, visited: Dictionary) -> Array:
	var room_tiles = []
	var to_check = [start_coord]
	var max_tiles = 30
	
	while to_check.size() > 0 and room_tiles.size() < max_tiles:
		var coord = to_check.pop_front()
		
		if coord in visited or coord not in world_data:
			continue
		
		visited[coord] = true
		room_tiles.append(coord)
		
		var adjacent = [
			Vector2i(coord.x + 1, coord.y),
			Vector2i(coord.x - 1, coord.y),
			Vector2i(coord.x, coord.y + 1),
			Vector2i(coord.x, coord.y - 1)
		]
		
		for adj_coord in adjacent:
			if adj_coord not in visited and adj_coord in world_data:
				if not is_wall_between(coord, adj_coord, world_data):
					to_check.append(adj_coord)
	
	return room_tiles

func is_wall_between(coord1: Vector2i, coord2: Vector2i, world_data: Dictionary) -> bool:
	return false

func sort_items_by_category(items: Array) -> Array:
	if items.size() > 50:
		items = items.slice(0, 50)
	
	items.sort_custom(func(a, b):
		var cat_a = a.get("category", "unknown")
		var cat_b = b.get("category", "unknown")
		return cat_a < cat_b
	)
	return items

func calculate_pathfinding(task_data: Dictionary) -> Dictionary:
	return {"path": [], "cost": 0}

func extract_asset_metadata(task_data: Dictionary) -> Dictionary:
	return {"metadata": {}}

func instantiate_scene(task_data: Dictionary) -> Dictionary:
	return {"scene_created": true}

func spawn_entity(task_data: Dictionary) -> Dictionary:
	return {"entity_spawned": true}

func perform_cleanup(task_data: Dictionary) -> Dictionary:
	return {"cleanup_completed": true}

func process_pending_scene_creations(budget_ms: float):
	pass

func process_pending_cleanup(budget_ms: float):
	pass

class WorkerThread:
	var thread: Thread
	var thread_id: int
	var is_running: bool = false
	var should_exit: bool = false
	var shutdown_requested: bool = false
	var last_activity: int = 0
	var health_check_interval: int = 1000
	
	var task_queue: Array
	var completed_tasks: Array
	var thread_mutex: Mutex
	var result_mutex: Mutex
	var manager: ThreadManager
	
	func start() -> bool:
		if thread and thread.is_started():
			return false
		
		thread = Thread.new()
		is_running = true
		last_activity = Time.get_ticks_msec()
		
		var error = thread.start(_thread_function)
		if error != OK:
			cleanup()
			return false
		
		return true
	
	func request_shutdown():
		shutdown_requested = true
		should_exit = true
	
	func force_shutdown():
		should_exit = true
		shutdown_requested = true
		
		if thread and thread.is_started():
			var wait_start = Time.get_ticks_msec()
			while thread.is_alive() and (Time.get_ticks_msec() - wait_start) < 250:
				OS.delay_msec(5)
		
		cleanup()
	
	func is_shutdown() -> bool:
		return not is_running and (not thread or not thread.is_started() or not thread.is_alive())
	
	func is_healthy() -> bool:
		if not is_running or should_exit:
			return false
		
		var current_time = Time.get_ticks_msec()
		return (current_time - last_activity) < (health_check_interval * 2)
	
	func cleanup():
		is_running = false
		if thread and thread.is_started():
			thread.wait_to_finish()
		thread = null
	
	func _thread_function():
		var idle_count = 0
		var max_idle_cycles = 80
		
		while not should_exit and manager and is_instance_valid(manager):
			var task = get_next_task()
			
			if task:
				last_activity = Time.get_ticks_msec()
				process_task(task)
				idle_count = 0
			else:
				idle_count += 1
				if idle_count >= max_idle_cycles:
					should_exit = true
					break
				
				OS.delay_msec(15)
				
				var current_time = Time.get_ticks_msec()
				if (current_time - last_activity) > health_check_interval:
					last_activity = current_time
		
		is_running = false
	
	func get_next_task():
		if not thread_mutex:
			return null
		
		thread_mutex.lock()
		var task = null
		
		if task_queue.size() > 0:
			task = task_queue.pop_front()
		
		thread_mutex.unlock()
		return task
	
	func process_task(task: Dictionary):
		var start_time = Time.get_ticks_msec()
		var result = null
		var success = true
		var error_message = ""
		
		if manager and is_instance_valid(manager):
			result = manager.execute_worker_task(task)
			if result == null or (result is Dictionary and result.has("error")):
				success = false
				error_message = result.get("error", "Task failed") if result else "Task returned null"
		else:
			success = false
			error_message = "Manager reference lost"
		
		var execution_time = Time.get_ticks_msec() - start_time
		
		var task_result = {
			"id": task.id,
			"type": task.type,
			"result": result,
			"execution_time": execution_time,
			"success": success,
			"error": error_message,
			"callback": task.get("callback", Callable())
		}
		
		if result_mutex:
			result_mutex.lock()
			if completed_tasks != null:
				completed_tasks.append(task_result)
			result_mutex.unlock()
