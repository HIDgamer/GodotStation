# ThreadManager.gd
extends Node

class_name ThreadManager

signal task_completed(task_id, result)
signal all_tasks_completed(task_group_id)
signal thread_error(thread_id, error)

# Thread configuration
var max_threads: int = 0  # Will be set based on CPU count
var active_threads: Array = []
var thread_pool: Array = []
var thread_status: Dictionary = {}  # Maps thread ID to status (idle, working, completed)
var thread_tasks: Dictionary = {}   # Maps thread ID to current task
var thread_data: Dictionary = {}    # Maps thread ID to data for mutex operations

# Task management
var task_queue: Array = []
var task_results: Dictionary = {}
var task_groups: Dictionary = {}    # Groups related tasks
var task_counter: int = 0
var task_group_counter: int = 0

# Synchronization
var task_mutex: Mutex = Mutex.new()
var result_mutex: Mutex = Mutex.new()
var wait_semaphore: Semaphore = Semaphore.new()

# System references
var world_ref: WeakRef = null
var system_priority: Dictionary = {}

# Performance tracking
var performance_stats: Dictionary = {}
var thread_timings: Dictionary = {}

# Configuration
var enable_threading: bool = true
var debug_mode: bool = false
var adaptive_threading: bool = true
var min_work_size: int = 10  # Minimum work size before threading is used

# Thread workload balancing
enum BalancingStrategy {
	EQUAL_DIVISION,
	WORK_STEALING,
	ADAPTIVE
}
var balancing_strategy: int = BalancingStrategy.ADAPTIVE

# Constants for systems
enum SystemType {
	ATMOSPHERE,
	SPATIAL,
	ENTITY,
	PATHFINDING,
	PHYSICS,
	ROOM_DETECTION,
	SENSORY,
	GENERAL
}

func _init():
	# Determine optimal thread count based on CPU cores
	# Usually good to leave 1-2 cores for the main thread and OS
	var processor_count = OS.get_processor_count()
	max_threads = max(1, processor_count - 2)
	
	if debug_mode:
		print("[ThreadManager] System has %d processors, using %d threads" % [processor_count, max_threads])
	
	# Set system priorities (higher = more thread allocation)
	system_priority[SystemType.ATMOSPHERE] = 5
	system_priority[SystemType.SPATIAL] = 4
	system_priority[SystemType.ENTITY] = 3
	system_priority[SystemType.PATHFINDING] = 4
	system_priority[SystemType.PHYSICS] = 5
	system_priority[SystemType.ROOM_DETECTION] = 2
	system_priority[SystemType.SENSORY] = 1
	system_priority[SystemType.GENERAL] = 1

func _ready():
	initialize_thread_pool()
	
	# Wait for a frame to ensure all systems are ready
	await get_tree().process_frame
	
	print("[ThreadManager] Ready with %d threads in pool" % thread_pool.size())

func _process(_delta):
	# Check for completed tasks
	process_completed_tasks()
	
	# If adaptive threading is enabled, adjust thread count based on workload
	if adaptive_threading and Engine.get_frames_drawn() % 300 == 0:  # Every ~5 seconds
		adjust_thread_count()

func initialize_thread_pool():
	# Create the initial thread pool
	for i in range(max_threads):
		var thread = Thread.new()
		thread_pool.append(thread)
		thread_status[thread.get_id()] = "idle"
		thread_data[thread.get_id()] = {}
		
		if debug_mode:
			print("[ThreadManager] Created thread %d" % thread.get_id())

func set_world_reference(world_node: Node):
	world_ref = weakref(world_node)
	
	if debug_mode:
		print("[ThreadManager] Set world reference: %s" % world_node.name)

# --- Task Submission Methods ---

func submit_task(callable_obj: Callable, task_data = null, system_type: int = SystemType.GENERAL) -> int:
	if not enable_threading:
		# Execute on main thread if threading disabled
		var result = callable_obj.call(task_data)
		return -1  # No task ID since it was executed immediately
	
	task_mutex.lock()
	var task_id = task_counter
	task_counter += 1
	
	task_queue.append({
		"id": task_id,
		"callable": callable_obj,
		"data": task_data,
		"system_type": system_type,
		"priority": system_priority.get(system_type, 1),
		"submitted_time": Time.get_ticks_msec()
	})
	
	# Sort queue by priority (higher first)
	task_queue.sort_custom(Callable(self, "_sort_by_priority"))
	task_mutex.unlock()
	
	# Try to start a thread immediately if available
	_assign_tasks_to_threads()
	
	return task_id

func submit_task_group(callable_obj: Callable, data_array: Array, system_type: int = SystemType.GENERAL) -> int:
	# For data that can be split across multiple threads
	if not enable_threading or data_array.size() < min_work_size:
		# Execute on main thread if threading disabled or task too small
		var results = []
		for data in data_array:
			results.append(callable_obj.call(data))
		
		# Signal completion immediately
		emit_signal("all_tasks_completed", -1)
		return -1
	
	task_mutex.lock()
	var group_id = task_group_counter
	task_group_counter += 1
	
	# Create a task group entry to track completion
	task_groups[group_id] = {
		"total_tasks": data_array.size(),
		"completed_tasks": 0,
		"results": [],
		"system_type": system_type
	}
	
	# Determine how to split the work
	var chunks = _split_workload(data_array, system_type)
	
	for chunk in chunks:
		var task_id = task_counter
		task_counter += 1
		
		task_queue.append({
			"id": task_id,
			"callable": callable_obj,
			"data": chunk,
			"system_type": system_type,
			"priority": system_priority.get(system_type, 1),
			"group_id": group_id,
			"submitted_time": Time.get_ticks_msec()
		})
	
	# Sort queue by priority
	task_queue.sort_custom(Callable(self, "_sort_by_priority"))
	task_mutex.unlock()
	
	# Try to start threads immediately
	_assign_tasks_to_threads()
	
	return group_id

# Special method for atmosphere processing - optimized for tile chunks
func process_atmosphere_in_chunks(chunk_size: int = 16) -> int:
	if not is_world_valid():
		return -1
	
	var world = world_ref.get_ref()
	var atmos_system = world.atmosphere_system
	
	if not atmos_system:
		return -1
	
	var all_z_levels = world.world_data.keys()
	var task_data_array = []
	
	# Create workload chunks for each z-level
	for z_level in all_z_levels:
		var tiles = world.world_data[z_level].keys()
		var chunks = []
		
		# Split tiles into chunks
		var current_chunk = []
		for i in range(tiles.size()):
			current_chunk.append(tiles[i])
			
			if current_chunk.size() >= chunk_size or i == tiles.size() - 1:
				chunks.append({
					"z_level": z_level,
					"tiles": current_chunk.duplicate()
				})
				current_chunk.clear()
		
		# Add chunks to work array
		task_data_array.append_array(chunks)
	
	# Submit the chunked work
	return submit_task_group(
		Callable(atmos_system, "process_atmosphere_chunk"), 
		task_data_array,
		SystemType.ATMOSPHERE
	)

# Process entities in parallel
func process_entities_parallel(entities: Array, method_name: String) -> int:
	if entities.size() < min_work_size:
		# Process on main thread if too few entities
		for entity in entities:
			if entity.has_method(method_name):
				entity.call(method_name)
		return -1
	
	# Create a callable that will call the specified method on each entity
	var entity_processor = func(entity_chunk):
		var results = []
		for entity in entity_chunk:
			if entity and entity.has_method(method_name):
				results.append(entity.call(method_name))
		return results
	
	# Split entities into chunks and process
	return submit_task_group(entity_processor, _chunk_array(entities), SystemType.ENTITY)

# Process room detection in parallel
func detect_rooms_parallel() -> int:
	if not is_world_valid():
		return -1
	
	var world = world_ref.get_ref()
	var all_z_levels = world.world_data.keys()
	
	# Create a callable for processing room detection on a z-level
	var room_detector = func(z_level_data):
		var z_level = z_level_data
		var visited = {}
		var rooms = []
		
		# Get all tiles for this z-level
		var tiles = world.world_data[z_level].keys()
		
		# Flood fill to find rooms
		for coords in tiles:
			if coords in visited:
				continue
			
			var room_tiles = flood_fill_room(coords, z_level, visited, world)
			if room_tiles.size() > 0:
				rooms.append({
					"tiles": room_tiles,
					"z_level": z_level,
					"volume": room_tiles.size(),
					"connections": detect_room_connections(room_tiles, z_level, world)
				})
		
		return {
			"z_level": z_level,
			"rooms": rooms
		}
	
	# Submit a task group with one task per z-level
	return submit_task_group(room_detector, all_z_levels, SystemType.ROOM_DETECTION)

# --- Helper methods for parallel operations ---

func flood_fill_room(start_coords, z_level, visited, world):
	var room_tiles = []
	var to_visit = [start_coords]
	
	while to_visit.size() > 0:
		var current = to_visit.pop_front()
		
		if current in visited:
			continue
			
		visited[current] = true
		room_tiles.append(current)
		
		# Check neighbors
		for neighbor in get_adjacent_tiles(current, world):
			if neighbor in visited:
				continue
				
			# Skip walls and solid barriers
			if is_airtight_barrier(current, neighbor, z_level, world):
				continue
				
			to_visit.append(neighbor)
	
	return room_tiles

func get_adjacent_tiles(coords, world):
	# Return coordinates of adjacent tiles (north, south, east, west)
	var adjacents = [
		Vector2(coords.x + 1, coords.y),
		Vector2(coords.x - 1, coords.y),
		Vector2(coords.x, coords.y + 1),
		Vector2(coords.x, coords.y - 1)
	]
	
	# Filter out invalid tiles
	var valid_adjacents = []
	for adj in adjacents:
		if world.get_tile_data(adj, world.current_z_level) != null:
			valid_adjacents.append(adj)
	
	return valid_adjacents

func is_airtight_barrier(tile1_coords, tile2_coords, z_level, world):
	# Check if there's an airtight barrier between tiles
	var tile1 = world.get_tile_data(tile1_coords, z_level)
	var tile2 = world.get_tile_data(tile2_coords, z_level)
	
	if tile1 == null or tile2 == null:
		return true  # Consider out of bounds as airtight
	
	# Check for walls
	if world.TileLayer.WALL in tile1:
		return true  # Wall blocks air
	
	if world.TileLayer.WALL in tile2:
		return true  # Wall blocks air
	
	# Check for doors
	if "door" in tile1 and "closed" in tile1.door and tile1.door.closed:
		return true  # Closed door blocks air
	
	if "door" in tile2 and "closed" in tile2.door and tile2.door.closed:
		return true  # Closed door blocks air
	
	return false

func detect_room_connections(room_tiles, z_level, world):
	var connections = []

	for tile_coords in room_tiles:
		var tile = world.get_tile_data(tile_coords, z_level)
		if tile == null:
			continue

		# Check for doors
		if "door" in tile:
			var door = tile.door
			if door != null and "closed" in door:
				connections.append({
					"type": "door",
					"tile": tile_coords,
					"state": "closed" if door.closed else "open"
				})

		# Check for z-level connections
		if "z_connection" in tile:
			var z_conn = tile.z_connection
			if z_conn != null and "type" in z_conn and "target" in z_conn:
				connections.append({
					"type": z_conn.type,
					"tile": tile_coords,
					"target": z_conn.target,
					"direction": z_conn.direction
				})

	return connections

# --- Thread Management ---

func _thread_function(task_data):
	var thread_id = OS.get_thread_caller_id()
	var task = task_data
	
	# Record start time for performance tracking
	var start_time = Time.get_ticks_msec()
	
	# Execute the task
	var result
	var error = null
	
	thread_status[thread_id] = "working"
	
	# Try to execute the task
	result = task.callable.call(task.data)
	
	# Update performance stats
	var end_time = Time.get_ticks_msec()
	var duration = end_time - start_time
	
	result_mutex.lock()
	thread_timings[task.id] = {
		"thread_id": thread_id,
		"system_type": task.system_type,
		"duration_ms": duration,
		"submitted_time": task.submitted_time,
		"start_time": start_time,
		"end_time": end_time
	}
	
	# Store the result
	task_results[task.id] = {
		"result": result,
		"error": error,
		"task": task
	}
	
	# Update group completion if part of a group
	if "group_id" in task and task.group_id in task_groups:
		task_groups[task.group_id].completed_tasks += 1
		task_groups[task.group_id].results.append(result)
	
	thread_status[thread_id] = "completed"
	result_mutex.unlock()
	
	# Signal that a task is complete
	wait_semaphore.post()
	
	return result

func process_completed_tasks():
	var completed_task_ids = []
	var completed_groups = []
	
	result_mutex.lock()
	
	# Check all task results
	for task_id in task_results.keys():
		if not task_id in completed_task_ids:
			var task_result = task_results[task_id]
			
			# Signal task completion
			emit_signal("task_completed", task_id, task_result.result)
			
			# Check if this is an error
			if task_result.error != null:
				emit_signal("thread_error", 
							thread_timings[task_id].thread_id if task_id in thread_timings else -1, 
							task_result.error)
			
			completed_task_ids.append(task_id)
			
			# Update performance stats
			if task_id in thread_timings:
				var system_type = thread_timings[task_id].system_type
				if not system_type in performance_stats:
					performance_stats[system_type] = {
						"count": 0,
						"total_duration": 0,
						"max_duration": 0
					}
				
				performance_stats[system_type].count += 1
				performance_stats[system_type].total_duration += thread_timings[task_id].duration_ms
				performance_stats[system_type].max_duration = max(
					performance_stats[system_type].max_duration,
					thread_timings[task_id].duration_ms
				)
	
	# Check for completed groups
	for group_id in task_groups.keys():
		var group = task_groups[group_id]
		if group.completed_tasks >= group.total_tasks and not group_id in completed_groups:
			emit_signal("all_tasks_completed", group_id)
			completed_groups.append(group_id)
	
	# Clean up completed tasks and groups
	for task_id in completed_task_ids:
		task_results.erase(task_id)
		thread_timings.erase(task_id)
	
	for group_id in completed_groups:
		task_groups.erase(group_id)
	
	result_mutex.unlock()
	
	# Reclaim threads that have completed
	reclaim_threads()

func reclaim_threads():
	var threads_to_reclaim = []
	
	# Find threads marked as completed
	for thread in active_threads:
		var thread_id = thread.get_id()
		if thread_status[thread_id] == "completed":
			threads_to_reclaim.append(thread)
	
	# Reclaim threads
	for thread in threads_to_reclaim:
		var thread_id = thread.get_id()
		
		# Wait for thread to complete (should be instant since it's already marked as completed)
		if thread.is_alive():
			var result = thread.wait_to_finish()
		
		# Return thread to the pool
		thread_status[thread_id] = "idle"
		active_threads.erase(thread)
		thread_pool.append(thread)
		
		if debug_mode:
			print("[ThreadManager] Reclaimed thread %d" % thread_id)
	
	# Try to assign new tasks to reclaimed threads
	if threads_to_reclaim.size() > 0:
		_assign_tasks_to_threads()

func _assign_tasks_to_threads():
	task_mutex.lock()
	
	# Only proceed if we have tasks and available threads
	if task_queue.size() == 0 or thread_pool.size() == 0:
		task_mutex.unlock()
		return
	
	# Prioritize tasks based on system_type and submitted time
	while task_queue.size() > 0 and thread_pool.size() > 0:
		var task = task_queue[0]
		task_queue.remove_at(0)
		
		var thread = thread_pool[0]
		thread_pool.remove_at(0)
		
		# Store task reference
		thread_tasks[thread.get_id()] = task
		
		# Start thread with task
		thread_status[thread.get_id()] = "starting"
		thread.start(Callable(self, "_thread_function").bind(task))
		
		# Move to active threads
		active_threads.append(thread)
		
		if debug_mode:
			print("[ThreadManager] Started thread %d with task %d (system: %d)" % 
				  [thread.get_id(), task.id, task.system_type])
	
	task_mutex.unlock()

func wait_for_task(task_id: int, timeout_ms: int = 5000) -> Dictionary:
	var start_time = Time.get_ticks_msec()
	
	while Time.get_ticks_msec() - start_time < timeout_ms:
		result_mutex.lock()
		if task_id in task_results:
			var result = task_results[task_id].duplicate()
			result_mutex.unlock()
			return result
		result_mutex.unlock()
		
		# Wait for a task to complete
		if wait_semaphore.try_wait():
			# A task completed, check if it's the one we want
			continue
		
		# Yield to avoid freezing
		await get_tree().process_frame
	
	# Timeout
	return {"error": "Timeout waiting for task %d" % task_id}

func wait_for_group(group_id: int, timeout_ms: int = 10000) -> Array:
	var start_time = Time.get_ticks_msec()
	
	while Time.get_ticks_msec() - start_time < timeout_ms:
		result_mutex.lock()
		
		if group_id in task_groups and task_groups[group_id].completed_tasks >= task_groups[group_id].total_tasks:
			var results = task_groups[group_id].results.duplicate()
			result_mutex.unlock()
			return results
		
		result_mutex.unlock()
		
		# Wait for a task to complete
		if wait_semaphore.try_wait():
			# A task completed, check if group is complete
			continue
		
		# Yield to avoid freezing
		await get_tree().process_frame
	
	# Timeout
	return [{"error": "Timeout waiting for task group %d" % group_id}]

# --- Utility Methods ---

func _sort_by_priority(a, b):
	# Higher priority first
	if a.priority != b.priority:
		return a.priority > b.priority
	
	# Then by submission time (older first)
	return a.submitted_time < b.submitted_time

func _split_workload(data_array: Array, system_type: int) -> Array:
	# Get the number of threads to use for this system type
	var thread_count = _get_thread_allocation(system_type)
	
	# Limit to available data size
	thread_count = min(thread_count, data_array.size())
	
	match balancing_strategy:
		BalancingStrategy.EQUAL_DIVISION:
			return _chunk_array(data_array, thread_count)
			
		BalancingStrategy.WORK_STEALING:
			# For work stealing, create smaller chunks
			var chunk_size = max(1, data_array.size() / (thread_count * 2))
			return _chunk_array_by_size(data_array, chunk_size)
			
		BalancingStrategy.ADAPTIVE:
			# Look at past performance to determine optimal chunk size
			if system_type in performance_stats and performance_stats[system_type].count > 0:
				var avg_time = performance_stats[system_type].total_duration / performance_stats[system_type].count
				
				# If tasks are very fast, use fewer but larger chunks
				if avg_time < 5:  # Less than 5ms per task
					return _chunk_array(data_array, max(1, thread_count / 2))
				# If tasks are very slow, use smaller chunks
				elif avg_time > 50:  # More than 50ms per task
					var chunk_size = max(1, data_array.size() / (thread_count * 3))
					return _chunk_array_by_size(data_array, chunk_size)
			
			# Default to equal division
			return _chunk_array(data_array, thread_count)
	
	# Fallback to simple equal division
	return _chunk_array(data_array, thread_count)

func _chunk_array(array: Array, chunk_count: int = 4) -> Array:
	if array.size() == 0:
		return []
	
	var chunks = []
	var items_per_chunk = max(1, array.size() / chunk_count)
	
	var current_chunk = []
	for i in range(array.size()):
		current_chunk.append(array[i])
		
		if current_chunk.size() >= items_per_chunk or i == array.size() - 1:
			chunks.append(current_chunk.duplicate())
			current_chunk.clear()
	
	return chunks

func _chunk_array_by_size(array: Array, chunk_size: int) -> Array:
	if array.size() == 0:
		return []
	
	var chunks = []
	var current_chunk = []
	
	for i in range(array.size()):
		current_chunk.append(array[i])
		
		if current_chunk.size() >= chunk_size or i == array.size() - 1:
			chunks.append(current_chunk.duplicate())
			current_chunk.clear()
	
	return chunks

func _get_thread_allocation(system_type: int) -> int:
	# Allocate threads based on system priority
	var priority = system_priority.get(system_type, 1)
	var total_priority = 0
	
	for s_type in system_priority.keys():
		total_priority += system_priority[s_type]
	
	# Calculate thread allocation (at least 1)
	return max(1, int(ceil((priority / float(total_priority)) * max_threads)))

func adjust_thread_count():
	# Check CPU usage and adjust thread count if necessary
	var usage = Performance.get_monitor(Performance.TIME_PROCESS)
	
	# If we're using too much CPU time per frame, reduce threads
	if usage > 1.0/60.0 * 0.8:  # Using more than 80% of frame time
		max_threads = max(1, max_threads - 1)
		if debug_mode:
			print("[ThreadManager] High CPU usage detected, reducing threads to %d" % max_threads)
	
	# If we have room to grow and tasks are queuing up
	elif usage < 1.0/60.0 * 0.5 and task_queue.size() > max_threads:
		max_threads = min(OS.get_processor_count() - 1, max_threads + 1)
		if debug_mode:
			print("[ThreadManager] Low CPU usage with pending tasks, increasing threads to %d" % max_threads)

# --- Cleanup ---

func is_world_valid() -> bool:
	return world_ref != null and world_ref.get_ref() != null

func cleanup_threads():
	# Wait for all active threads to complete
	for thread in active_threads:
		if thread.is_alive():
			var result = thread.wait_to_finish()
	
	active_threads.clear()
	
	# Clear thread pool
	thread_pool.clear()
	
	# Reset counters and status
	thread_status.clear()
	thread_tasks.clear()
	task_results.clear()
	task_groups.clear()
	
	if debug_mode:
		print("[ThreadManager] All threads cleaned up")

func _exit_tree():
	# Ensure all threads are properly terminated
	cleanup_threads()

func get_performance_report() -> Dictionary:
	var report = {
		"thread_count": max_threads,
		"active_threads": active_threads.size(),
		"idle_threads": thread_pool.size(),
		"pending_tasks": task_queue.size(),
		"system_stats": performance_stats.duplicate(true)
	}
	print(report)
	for system_type in report.system_stats.keys():
		var stats = report.system_stats[system_type]
		if stats.count > 0:
			stats["avg_duration"] = stats.total_duration / stats.count
	
	return report
