extends Node
class_name ThreadManager

# Core thread configuration
var MAX_WORKER_THREADS = 4
var TASK_QUEUE_LIMIT = 100  # Prevent queue flooding
var FRAME_BUDGET_MS = 8.0   # Milliseconds per frame for main thread tasks

# Task priorities determine execution order
enum TaskPriority {
	CRITICAL,    # Execute immediately on main thread
	HIGH,        # Execute within 1-2 frames
	MEDIUM,      # Execute within 5 frames
	LOW,         # Execute when convenient
	BACKGROUND   # Execute during idle time only
}

# Only operations that benefit from threading and are thread-safe
enum TaskType {
	# Data processing (thread-safe)
	ATMOSPHERE_CALCULATION,
	ROOM_DETECTION,
	PATHFINDING_CALCULATION,
	INVENTORY_SORTING,
	ASSET_METADATA_EXTRACTION,
	
	# Main thread only operations
	SCENE_INSTANTIATION,
	ENTITY_SPAWNING,
	CLEANUP
}

# Worker thread management
var worker_threads = []
var task_queue = []
var completed_tasks = []
var active_tasks = {}
var thread_mutex = Mutex.new()
var result_mutex = Mutex.new()

# Scene management (main thread only)
var scene_pools = {}
var scene_cache = {}
var pooled_scene_limits = {
	"Characters": 20,
	"Effects": 50,
	"Items": 100,
	"UI": 10
}

# Performance tracking
var task_performance = {}
var queue_warnings_sent = 0
var last_performance_report = 0

# World data access
var world_ref = null
var thread_safe_world_data = {}
var world_data_mutex = Mutex.new()

# Signals for communication with GameManager
signal task_completed(task_id, result)
signal scene_pool_ready(category, pool_size)
signal entity_batch_processed(batch_id, results)
signal performance_warning(task_type, execution_time)

func _ready():
	print("ThreadManager: Starting thread system with ", MAX_WORKER_THREADS, " workers")
	initialize_worker_threads()
	initialize_scene_pools()
	setup_performance_tracking()

func _process(delta):
	process_completed_tasks()
	process_main_thread_tasks()
	monitor_queue_health()
	
	# Performance reporting every 5 seconds
	var current_time = Time.get_ticks_msec()
	if current_time - last_performance_report > 5000:
		report_performance()
		last_performance_report = current_time

func _exit_tree():
	shutdown_all_threads()

# Worker thread initialization
func initialize_worker_threads():
	for i in range(MAX_WORKER_THREADS):
		var worker = WorkerThread.new()
		worker.thread_id = i
		worker.task_queue = task_queue
		worker.completed_tasks = completed_tasks
		worker.thread_mutex = thread_mutex
		worker.result_mutex = result_mutex
		worker.manager = self
		
		worker_threads.append(worker)
		worker.start()

# Scene pool initialization on main thread
func initialize_scene_pools():
	for category in pooled_scene_limits.keys():
		scene_pools[category] = []

# Set up performance monitoring
func setup_performance_tracking():
	for task_type in TaskType.values():
		task_performance[task_type] = {
			"total_time": 0.0,
			"count": 0,
			"avg_time": 0.0,
			"max_time": 0.0
		}

# Public API: Queue atmosphere processing for coordinates
func queue_atmosphere_processing(coordinates: Array, priority: TaskPriority = TaskPriority.MEDIUM) -> String:
	var task_data = {
		"coordinates": coordinates,
		"world_data": get_thread_safe_world_snapshot()
	}
	
	return submit_task(TaskType.ATMOSPHERE_CALCULATION, priority, task_data)

# Public API: Queue room detection for a Z-level
func queue_room_detection(z_level: int, priority: TaskPriority = TaskPriority.MEDIUM) -> String:
	var task_data = {
		"z_level": z_level,
		"world_data": get_thread_safe_world_snapshot(z_level)
	}
	
	return submit_task(TaskType.ROOM_DETECTION, priority, task_data)

# Public API: Queue inventory sorting
func queue_inventory_operations(inventory_data: Array, priority: TaskPriority = TaskPriority.LOW) -> String:
	var task_data = {
		"inventories": inventory_data
	}
	
	return submit_task(TaskType.INVENTORY_SORTING, priority, task_data)

# Public API: Get a pooled scene (main thread only)
func get_pooled_scene(category: String) -> Node:
	if not scene_pools.has(category):
		return null
	
	if scene_pools[category].is_empty():
		# Pool is empty, try to create more
		create_pooled_scenes(category, 5)
		return null
	
	return scene_pools[category].pop_front()

# Public API: Return scene to pool (main thread only)
func return_scene_to_pool(scene: Node, category: String):
	if not scene or not is_instance_valid(scene):
		return
	
	if not scene_pools.has(category):
		scene_pools[category] = []
	
	# Reset the scene state
	reset_scene_for_pooling(scene)
	
	# Check pool limit
	var limit = pooled_scene_limits.get(category, 20)
	if scene_pools[category].size() < limit:
		scene_pools[category].append(scene)
	else:
		# Pool is full, cleanup the scene
		scene.queue_free()

# Core task submission
func submit_task(task_type: TaskType, priority: TaskPriority, task_data: Dictionary, callback: Callable = Callable()) -> String:
	# Check queue limits to prevent flooding
	if task_queue.size() >= TASK_QUEUE_LIMIT:
		if queue_warnings_sent < 5:  # Limit warning spam
			print("ThreadManager: Task queue at limit, dropping task")
			queue_warnings_sent += 1
		return ""
	
	var task_id = generate_task_id()
	
	var task = {
		"id": task_id,
		"type": task_type,
		"priority": priority,
		"data": task_data,
		"callback": callback,
		"submitted_time": Time.get_ticks_msec()
	}
	
	# Critical tasks execute immediately on main thread
	if priority == TaskPriority.CRITICAL:
		var result = execute_task_on_main_thread(task)
		if callback.is_valid():
			callback.call(task_id, result)
		return task_id
	
	# Queue task for worker threads
	thread_mutex.lock()
	task_queue.append(task)
	# Sort by priority (lower enum value = higher priority)
	task_queue.sort_custom(func(a, b): return a.priority < b.priority)
	thread_mutex.unlock()
	
	active_tasks[task_id] = task
	return task_id

# Process completed tasks from worker threads
func process_completed_tasks():
	result_mutex.lock()
	var tasks_to_process = completed_tasks.duplicate()
	completed_tasks.clear()
	result_mutex.unlock()
	
	for task_result in tasks_to_process:
		var task_id = task_result.id
		var result = task_result.result
		var execution_time = task_result.execution_time
		
		# Update performance tracking
		update_task_performance(task_result.type, execution_time)
		
		# Emit signal
		task_completed.emit(task_id, result)
		
		# Call callback if provided
		if task_result.has("callback") and task_result.callback.is_valid():
			task_result.callback.call(task_id, result)
		
		# Remove from active tasks
		if task_id in active_tasks:
			active_tasks.erase(task_id)

# Process main thread tasks within frame budget
func process_main_thread_tasks():
	var frame_start = Time.get_ticks_msec()
	var budget_remaining = FRAME_BUDGET_MS
	
	# Process scene instantiation requests
	process_pending_scene_creations(budget_remaining * 0.5)
	
	# Process entity spawning requests
	process_pending_entity_spawns(budget_remaining * 0.3)
	
	# Process cleanup tasks
	process_pending_cleanup(budget_remaining * 0.2)

# Task execution for different types
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
			print("ThreadManager: Unknown main thread task type: ", task.type)
	
	var execution_time = Time.get_ticks_msec() - start_time
	update_task_performance(task.type, execution_time)
	
	return result

# Worker thread task execution (thread-safe operations only)
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
		_:
			print("ThreadManager: Unknown worker task type: ", task.type)
			return null

# Atmosphere calculation (thread-safe)
func calculate_atmosphere_data(task_data: Dictionary) -> Dictionary:
	var coordinates = task_data.get("coordinates", [])
	var world_data = task_data.get("world_data", {})
	var results = []
	
	for coord in coordinates:
		# Simulate atmosphere calculations
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

# Room detection (thread-safe)
func detect_rooms(task_data: Dictionary) -> Dictionary:
	var z_level = task_data.get("z_level", 0)
	var world_data = task_data.get("world_data", {})
	
	var rooms = {}
	var visited = {}
	var room_id = 0
	
	# Find all floor tiles and group them into rooms
	for coord in world_data.keys():
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
	
	return {"rooms": rooms, "z_level": z_level}

# Inventory sorting (thread-safe)
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

# Scene management (main thread only)
func create_pooled_scenes(category: String, count: int):
	var scenes_created = 0
	var start_time = Time.get_ticks_msec()
	
	# Don't exceed frame budget
	while scenes_created < count and (Time.get_ticks_msec() - start_time) < FRAME_BUDGET_MS:
		var scene = create_scene_for_category(category)
		if scene:
			scene_pools[category].append(scene)
			scenes_created += 1
		else:
			break
	
	if scenes_created > 0:
		scene_pool_ready.emit(category, scene_pools[category].size())

func create_scene_for_category(category: String) -> Node:
	# This would integrate with your asset system
	# For now, just return null to indicate no scene available
	return null

# Scene state reset for pooling
func reset_scene_for_pooling(scene: Node):
	# Reset position
	if scene.has_method("set_position"):
		scene.set_position(Vector2.ZERO)
	
	# Reset visibility
	if scene.has_method("set_visible"):
		scene.set_visible(true)
	
	# Call custom reset method if available
	if scene.has_method("reset_for_pool"):
		scene.reset_for_pool()

# World data management
func set_world_reference(world):
	world_ref = world
	update_thread_safe_world_data()

func update_thread_safe_world_data():
	if not world_ref:
		return
	
	world_data_mutex.lock()
	# Create thread-safe copy of world data
	if world_ref.has_method("get_thread_safe_data"):
		thread_safe_world_data = world_ref.get_thread_safe_data()
	world_data_mutex.unlock()

func get_thread_safe_world_snapshot(z_level: int = -1) -> Dictionary:
	world_data_mutex.lock()
	var data = {}
	if z_level >= 0 and z_level in thread_safe_world_data:
		data = thread_safe_world_data[z_level].duplicate(true)
	else:
		data = thread_safe_world_data.duplicate(true)
	world_data_mutex.unlock()
	return data

# Performance monitoring
func update_task_performance(task_type: TaskType, execution_time: float):
	if task_type in task_performance:
		var perf = task_performance[task_type]
		perf.total_time += execution_time
		perf.count += 1
		perf.avg_time = perf.total_time / perf.count
		perf.max_time = max(perf.max_time, execution_time)
		
		# Warn about slow tasks
		if execution_time > 50:  # More than 50ms is concerning
			performance_warning.emit(task_type, execution_time)

func monitor_queue_health():
	var queue_size = task_queue.size()
	var active_count = active_tasks.size()
	
	# Reset warning counter periodically
	if Time.get_ticks_msec() % 10000 == 0:  # Every 10 seconds
		queue_warnings_sent = 0
	
	# Warn about queue size
	if queue_size > 50 and queue_warnings_sent < 3:
		print("ThreadManager: Task queue size: ", queue_size, ", active: ", active_count)
		queue_warnings_sent += 1

func report_performance():
	var total_tasks = 0
	var total_time = 0.0
	
	for task_type in task_performance:
		var perf = task_performance[task_type]
		total_tasks += perf.count
		total_time += perf.total_time
	
	if total_tasks > 0:
		print("ThreadManager: Processed ", total_tasks, " tasks, avg time: ", total_time / total_tasks, "ms")

# Utility functions
func generate_task_id() -> String:
	return "task_" + str(Time.get_ticks_msec()) + "_" + str(randi())

func shutdown_all_threads():
	print("ThreadManager: Shutting down worker threads")
	
	for worker in worker_threads:
		worker.shutdown()
	
	worker_threads.clear()
	task_queue.clear()
	active_tasks.clear()

# Helper functions for calculations (placeholders - implement as needed)
func calculate_pressure_at_coordinate(coord: Vector2i, world_data: Dictionary) -> float:
	# Placeholder atmosphere calculation
	return 101.3 + randf_range(-5.0, 5.0)

func calculate_temperature_at_coordinate(coord: Vector2i, world_data: Dictionary) -> float:
	# Placeholder temperature calculation
	return 293.0 + randf_range(-10.0, 10.0)

func calculate_gas_mixture(coord: Vector2i, world_data: Dictionary) -> Dictionary:
	# Placeholder gas mixture calculation
	return {"oxygen": 0.21, "nitrogen": 0.78, "other": 0.01}

func flood_fill_room(start_coord: Vector2i, world_data: Dictionary, visited: Dictionary) -> Array:
	var room_tiles = []
	var to_check = [start_coord]
	
	while to_check.size() > 0:
		var coord = to_check.pop_front()
		
		if coord in visited or coord not in world_data:
			continue
		
		visited[coord] = true
		room_tiles.append(coord)
		
		# Check adjacent tiles
		var adjacent = [
			Vector2i(coord.x + 1, coord.y),
			Vector2i(coord.x - 1, coord.y),
			Vector2i(coord.x, coord.y + 1),
			Vector2i(coord.x, coord.y - 1)
		]
		
		for adj_coord in adjacent:
			if adj_coord not in visited and adj_coord in world_data:
				# Check if there's a wall between tiles
				if not is_wall_between(coord, adj_coord, world_data):
					to_check.append(adj_coord)
	
	return room_tiles

func is_wall_between(coord1: Vector2i, coord2: Vector2i, world_data: Dictionary) -> bool:
	# Placeholder wall detection
	return false

func sort_items_by_category(items: Array) -> Array:
	# Simple category-based sorting
	items.sort_custom(func(a, b): 
		var cat_a = a.get("category", "unknown")
		var cat_b = b.get("category", "unknown")
		return cat_a < cat_b
	)
	return items

func calculate_pathfinding(task_data: Dictionary) -> Dictionary:
	# Placeholder pathfinding
	return {"path": [], "cost": 0}

func extract_asset_metadata(task_data: Dictionary) -> Dictionary:
	# Placeholder metadata extraction
	return {"metadata": {}}

func instantiate_scene(task_data: Dictionary) -> Dictionary:
	# Placeholder scene instantiation
	return {"scene_created": true}

func spawn_entity(task_data: Dictionary) -> Dictionary:
	# Placeholder entity spawning
	return {"entity_spawned": true}

func perform_cleanup(task_data: Dictionary) -> Dictionary:
	# Placeholder cleanup
	return {"cleanup_completed": true}

func process_pending_scene_creations(budget_ms: float):
	# Process scene creation requests within budget
	pass

func process_pending_entity_spawns(budget_ms: float):
	# Process entity spawning within budget
	pass

func process_pending_cleanup(budget_ms: float):
	# Process cleanup tasks within budget
	pass

# Worker Thread Class
class WorkerThread:
	var thread: Thread
	var thread_id: int
	var is_running: bool = false
	var should_exit: bool = false
	
	var task_queue: Array
	var completed_tasks: Array
	var thread_mutex: Mutex
	var result_mutex: Mutex
	var manager: ThreadManager
	
	func start():
		thread = Thread.new()
		is_running = true
		thread.start(_thread_function)
	
	func shutdown():
		should_exit = true
		if thread and thread.is_started():
			thread.wait_to_finish()
		is_running = false
	
	func _thread_function():
		while not should_exit:
			var task = get_next_task()
			
			if task:
				var start_time = Time.get_ticks_msec()
				var result = manager.execute_worker_task(task)
				var execution_time = Time.get_ticks_msec() - start_time
				
				var task_result = {
					"id": task.id,
					"type": task.type,
					"result": result,
					"execution_time": execution_time,
					"callback": task.get("callback", Callable())
				}
				
				result_mutex.lock()
				completed_tasks.append(task_result)
				result_mutex.unlock()
			else:
				# No tasks available, sleep briefly
				OS.delay_msec(10)
	
	func get_next_task():
		thread_mutex.lock()
		var task = null
		
		if task_queue.size() > 0:
			# Get highest priority task
			task = task_queue.pop_front()
		
		thread_mutex.unlock()
		return task
