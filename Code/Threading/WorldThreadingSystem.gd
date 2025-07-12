# WorldThreadingSystem.gd
# Extension class for World.gd that implements multithreaded operations
class_name WorldThreadingSystem
extends Node

# Parent world reference
var world: Node = null

# Thread manager
var thread_manager: ThreadManager = null

# Configuration
var thread_atmosphere: bool = true
var thread_room_detection: bool = true
var thread_entity_processing: bool = true
var thread_pathfinding: bool = true
var thread_chunk_size: int = 16  # Size of tile chunks for processing

# Optimization flags
var use_adaptive_chunking: bool = true
var min_entities_for_threading: int = 5

# Thread task tracking
var pending_task_groups: Dictionary = {}
var pending_tasks: Dictionary = {}

# Performance monitoring
var system_timings: Dictionary = {}

func _init(parent_world):
	self.world = parent_world
	
	name = "WorldThreadingSystem"
	
	# Create ThreadManager if it doesn't exist
	thread_manager = ThreadManager.new()
	thread_manager.name = "ThreadManager"
	add_child(thread_manager)
	
	# Set world reference
	thread_manager.set_world_reference(world)
	
	# Connect signals
	thread_manager.connect("task_completed", Callable(self, "_on_task_completed"))
	thread_manager.connect("all_tasks_completed", Callable(self, "_on_task_group_completed"))
	thread_manager.connect("thread_error", Callable(self, "_on_thread_error"))
	
	print("[WorldThreadingSystem] Initialized with parent world: ", world.name)

func _ready():
	await get_tree().process_frame  # Wait one frame to ensure all systems are ready
	
	# Register this system with the world's system manager if it exists
	if world.has_node("SystemManager"):
		var system_manager = world.get_node("SystemManager")
		system_manager.register_system(self, "threading")
		
		print("[WorldThreadingSystem] Registered with SystemManager")

# --- Atmosphere Processing ---

func process_atmosphere_step_threaded() -> int:
	if not thread_atmosphere:
		# Just call the regular atmosphere processing if threading is disabled
		if world.atmosphere_system:
			world.atmosphere_system.process_atmosphere_step()
		return -1
	
	# Measure start time
	var start_time = Time.get_ticks_msec()
	
	# Use the ThreadManager to process atmosphere in chunks
	var group_id = thread_manager.process_atmosphere_in_chunks(thread_chunk_size)
	
	if group_id >= 0:
		# Track this task group
		pending_task_groups[group_id] = {
			"type": "atmosphere",
			"start_time": start_time
		}
	
	return group_id

# --- Room Detection ---

func detect_rooms_threaded() -> int:
	if not thread_room_detection:
		# Fallback to regular room detection
		world.detect_rooms()
		return -1
	
	# Measure start time
	var start_time = Time.get_ticks_msec()
	
	# Use ThreadManager for room detection
	var group_id = thread_manager.detect_rooms_parallel()
	
	if group_id >= 0:
		pending_task_groups[group_id] = {
			"type": "room_detection",
			"start_time": start_time
		}
	
	return group_id

# --- Entity Processing ---

func process_entities_threaded(method_name: String = "process") -> int:
	if not thread_entity_processing:
		return -1
	
	# Get all entities
	var all_entities = []
	
	# First try to get from SpatialManager
	if world.has_node("SpatialManager"):
		var spatial_manager = world.get_node("SpatialManager")
		if "all_entities" in spatial_manager:
			all_entities = spatial_manager.all_entities
	
	# Fallback to TileOccupancySystem
	if all_entities.size() == 0 and world.has_node("TileOccupancySystem"):
		var tile_occupancy = world.get_node("TileOccupancySystem")
		all_entities = tile_occupancy.get_all_entities()
	
	# Check if we have enough entities to warrant threading
	if all_entities.size() < min_entities_for_threading:
		# Process on main thread if too few entities
		for entity in all_entities:
			if entity and entity.has_method(method_name):
				entity.call(method_name)
		return -1
	
	# Measure start time
	var start_time = Time.get_ticks_msec()
	
	# Use ThreadManager to process entities
	var group_id = thread_manager.process_entities_parallel(all_entities, method_name)
	
	if group_id >= 0:
		pending_task_groups[group_id] = {
			"type": "entity_processing",
			"start_time": start_time,
			"method": method_name
		}
	
	return group_id

# --- Pathfinding ---

func calculate_paths_threaded(path_requests: Array) -> int:
	if not thread_pathfinding or path_requests.size() == 0:
		return -1
	
	# Define pathfinding callable
	var pathfinder_callable = func(request):
		# Extract request data
		var start_pos = request.start
		var end_pos = request.end
		var z_level = request.z_level if "z_level" in request else world.current_z_level
		var entity = request.entity if "entity" in request else null
		
		# Find path using A* algorithm
		var path = astar_pathfinding(start_pos, end_pos, z_level, entity)
		
		return {
			"id": request.id if "id" in request else 0,
			"path": path,
			"start": start_pos,
			"end": end_pos,
			"entity": entity
		}
	
	# Measure start time
	var start_time = Time.get_ticks_msec()
	
	# Submit path requests as a task group
	var group_id = thread_manager.submit_task_group(
		pathfinder_callable,
		path_requests,
		ThreadManager.SystemType.PATHFINDING
	)
	
	if group_id >= 0:
		pending_task_groups[group_id] = {
			"type": "pathfinding",
			"start_time": start_time
		}
	
	return group_id

# A* pathfinding implementation
func astar_pathfinding(start_pos: Vector2, end_pos: Vector2, z_level: int, entity = null) -> Array:
	# Simple A* implementation for threading example
	var open_set = [{"pos": start_pos, "f": heuristic(start_pos, end_pos), "g": 0, "parent": null}]
	var closed_set = {}
	var max_iterations = 1000  # Prevent infinite loops
	var iterations = 0
	
	while not open_set.is_empty() and iterations < max_iterations:
		iterations += 1
		
		# Find node with lowest f cost
		var current_index = 0
		for i in range(1, open_set.size()):
			if open_set[i].f < open_set[current_index].f:
				current_index = i
		
		var current = open_set[current_index]
		
		# Check if reached goal
		if current.pos.distance_to(end_pos) < 1.0:
			# Reconstruct path
			var path = []
			var node = current
			
			while node.parent != null:
				path.push_front(node.pos)
				node = node.parent
			
			path.push_front(start_pos)  # Add start position
			return path
		
		# Remove current from open set
		open_set.remove_at(current_index)
		
		# Add to closed set
		var pos_key = Vector3(current.pos.x, current.pos.y, z_level)
		closed_set[pos_key] = true
		
		# Check neighbors
		var directions = [
			Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
			Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)
		]
		
		for dir in directions:
			var neighbor_pos = current.pos + dir
			var neighbor_key = Vector3(neighbor_pos.x, neighbor_pos.y, z_level)
			
			# Skip if in closed set
			if neighbor_key in closed_set:
				continue
			
			# Skip if blocked
			if world.is_tile_blocked(neighbor_pos, z_level):
				continue
			
			# Calculate costs
			var g_cost = current.g + dir.length()
			var h_cost = heuristic(neighbor_pos, end_pos)
			var f_cost = g_cost + h_cost
			
			# Check if already in open set with better path
			var in_open_set = false
			for i in range(open_set.size()):
				if open_set[i].pos.is_equal_approx(neighbor_pos):
					in_open_set = true
					if g_cost < open_set[i].g:
						# Found better path, update
						open_set[i].g = g_cost
						open_set[i].f = f_cost
						open_set[i].parent = current
					break
			
			# Add to open set if not already there
			if not in_open_set:
				open_set.append({
					"pos": neighbor_pos,
					"f": f_cost,
					"g": g_cost,
					"parent": current
				})
	
	# No path found
	return []

func heuristic(a: Vector2, b: Vector2) -> float:
	# Manhattan distance heuristic
	return abs(a.x - b.x) + abs(a.y - b.y)

# --- Threading Utility Functions ---

func thread_spatial_query(center: Vector2, radius: float, z_level: int) -> int:
	# Create a callable for the spatial query
	var spatial_query = func(query_data):
		var center_pos = query_data.center
		var query_radius = query_data.radius
		var query_z = query_data.z_level
		
		# Get tiles in radius
		var tiles = world.get_nearby_tiles(center_pos, query_radius, query_z)
		
		# Get entities in radius (using direct method to avoid circular reference)
		var entities = []
		var tile_radius = ceil(query_radius / world.TILE_SIZE)
		
		for x in range(-tile_radius, tile_radius + 1):
			for y in range(-tile_radius, tile_radius + 1):
				var tile_center = world.get_tile_at(center_pos)
				var check_tile = Vector2i(tile_center.x + x, tile_center.y + y)
				
				# Get entities at this tile
				if world.tile_occupancy_system:
					var tile_entities = world.tile_occupancy_system.get_entities_at(check_tile, query_z)
					for entity in tile_entities:
						# Only include entities within actual radius
						if "position" in entity:
							var distance = center_pos.distance_to(entity.position)
							if distance <= query_radius and not entity in entities:
								entities.append(entity)
		
		return {
			"tiles": tiles,
			"entities": entities,
			"center": center_pos,
			"radius": query_radius,
			"z_level": query_z
		}
	
	# Set up query data
	var query_data = {
		"center": center,
		"radius": radius,
		"z_level": z_level
	}
	
	# Submit task
	var task_id = thread_manager.submit_task(
		spatial_query,
		query_data,
		ThreadManager.SystemType.SPATIAL
	)
	
	if task_id >= 0:
		pending_tasks[task_id] = {
			"type": "spatial_query",
			"start_time": Time.get_ticks_msec()
		}
	
	return task_id

# --- Signal Handlers ---

func _on_task_completed(task_id, result):
	# Handle individual task completion
	if task_id in pending_tasks:
		var task_info = pending_tasks[task_id]
		var duration = Time.get_ticks_msec() - task_info.start_time
		
		# Update timing stats
		if not task_info.type in system_timings:
			system_timings[task_info.type] = {
				"count": 0,
				"total_time": 0,
				"avg_time": 0
			}
		
		system_timings[task_info.type].count += 1
		system_timings[task_info.type].total_time += duration
		system_timings[task_info.type].avg_time = system_timings[task_info.type].total_time / system_timings[task_info.type].count
		
		# Handle specific task types
		match task_info.type:
			"spatial_query":
				if world.spatial_manager and world.spatial_manager.has_signal("spatial_query_completed"):
					world.spatial_manager.emit_signal("spatial_query_completed", result)
			
			# Add more specific task handlers here
		
		# Remove from pending tasks
		pending_tasks.erase(task_id)

func _on_task_group_completed(group_id):
	if group_id in pending_task_groups:
		var group_info = pending_task_groups[group_id]
		var duration = Time.get_ticks_msec() - group_info.start_time
		
		# Update timing stats
		if not group_info.type in system_timings:
			system_timings[group_info.type] = {
				"count": 0,
				"total_time": 0,
				"avg_time": 0
			}
		
		system_timings[group_info.type].count += 1
		system_timings[group_info.type].total_time += duration
		system_timings[group_info.type].avg_time = system_timings[group_info.type].total_time / system_timings[group_info.type].count
		
		# Handle specific group types
		match group_info.type:
			"atmosphere":
				# The atmosphere has been updated in chunks, notify the world
				if world.atmosphere_system:
					world.atmosphere_system.emit_signal("atmosphere_step_completed")
			
			"room_detection":
				# Apply the new room data
				apply_room_detection_results(thread_manager.task_groups[group_id].results)
				
				# Notify world that rooms have been detected
				world.emit_signal("rooms_detected")
			
			"entity_processing":
				# Entities have been processed
				if "method" in group_info:
					var method = group_info.method
					world.emit_signal("entities_processed", method)
			
			"pathfinding":
				# Paths have been calculated
				var paths = thread_manager.task_groups[group_id].results
				if world.has_signal("paths_calculated"):
					world.emit_signal("paths_calculated", paths)
				
				# Also notify individual entities
				for path_result in paths:
					if "entity" in path_result and path_result.entity and path_result.entity.has_method("on_path_calculated"):
						path_result.entity.on_path_calculated(path_result.path)
		
		# Remove from pending groups
		pending_task_groups.erase(group_id)

func _on_thread_error(thread_id, error):
	push_error("[WorldThreadingSystem] Thread %d encountered error: %s" % [thread_id, error])

# --- Result Application Methods ---

func apply_room_detection_results(results: Array):
	# Clear existing rooms
	world.rooms.clear()
	world.tile_to_room.clear()
	
	var room_id = 0
	
	# Process results from each z-level
	for z_level_result in results:
		var z_level = z_level_result.z_level
		var rooms = z_level_result.rooms
		
		for room in rooms:
			world.rooms[room_id] = {
				"tiles": room.tiles,
				"z_level": z_level,
				"volume": room.volume,
				"atmosphere": world.calculate_room_atmosphere(room.tiles, z_level),
				"connections": room.connections,
				"needs_equalization": false
			}
			
			# Map tiles to room
			for tile in room.tiles:
				world.tile_to_room[Vector3(tile.x, tile.y, z_level)] = room_id
			
			room_id += 1

# --- Performance Reporting ---

func get_performance_report() -> Dictionary:
	var report = {
		"thread_manager": thread_manager.get_performance_report(),
		"system_timings": system_timings.duplicate(true),
		"pending_tasks": pending_tasks.size(),
		"pending_groups": pending_task_groups.size()
	}
	
	return report

# --- Threading Settings ---

func set_threading_enabled(enabled: bool):
	thread_atmosphere = enabled
	thread_room_detection = enabled
	thread_entity_processing = enabled
	thread_pathfinding = enabled
	
	print("[WorldThreadingSystem] Threading %s" % ("enabled" if enabled else "disabled"))

func set_chunk_size(size: int):
	thread_chunk_size = max(1, size)
	print("[WorldThreadingSystem] Chunk size set to %d" % thread_chunk_size)

# --- Cleanup ---

func _exit_tree():
	# Make sure threads are cleaned up
	if thread_manager:
		thread_manager.cleanup_threads()
