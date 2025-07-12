# ThreadingConfig.gd
class_name ThreadingConfig
extends Resource

# A configuration resource for the threading system
# Create an instance of this resource and save it to your project
# to easily configure threading options across game restarts

@export_category("Core Settings")
@export var enable_threading: bool = true
@export var debug_mode: bool = false
@export var max_threads: int = 0  # 0 means auto-configure

@export_category("System Threading")
@export var thread_atmosphere: bool = true
@export var thread_room_detection: bool = true
@export var thread_entity_processing: bool = true
@export var thread_pathfinding: bool = true
@export var thread_spatial_queries: bool = true

@export_category("Performance Tuning")
@export var adaptive_threading: bool = true
@export var adaptive_chunking: bool = true
@export_enum("Equal Division", "Work Stealing", "Adaptive") var balancing_strategy: int = 2
@export var chunk_size: int = 16
@export var min_entities_for_threading: int = 5

@export_category("System Priorities (1-10)")
@export_range(1, 10) var atmosphere_priority: int = 5
@export_range(1, 10) var spatial_priority: int = 4
@export_range(1, 10) var entity_priority: int = 3
@export_range(1, 10) var pathfinding_priority: int = 4
@export_range(1, 10) var physics_priority: int = 5
@export_range(1, 10) var room_detection_priority: int = 2

# Save the configuration to a file
func save_config(path: String = "user://threading_config.tres") -> bool:
	return ResourceSaver.save(self, path)

# Load configuration from a file
static func load_config(path: String = "user://threading_config.tres") -> ThreadingConfig:
	if ResourceLoader.exists(path):
		var config = ResourceLoader.load(path)
		if config is ThreadingConfig:
			return config
	
	# Return a default config if none exists
	return ThreadingConfig.new()

# Apply configuration to a ThreadManager
func apply_to_thread_manager(manager: ThreadManager) -> void:
	if not manager:
		push_error("Cannot apply configuration to null ThreadManager")
		return
	
	# Apply core settings
	manager.enable_threading = enable_threading
	manager.debug_mode = debug_mode
	
	if max_threads > 0:
		manager.max_threads = max_threads
	
	manager.adaptive_threading = adaptive_threading
	manager.balancing_strategy = balancing_strategy
	
	# Apply system priorities
	manager.system_priority[ThreadManager.SystemType.ATMOSPHERE] = atmosphere_priority
	manager.system_priority[ThreadManager.SystemType.SPATIAL] = spatial_priority
	manager.system_priority[ThreadManager.SystemType.ENTITY] = entity_priority
	manager.system_priority[ThreadManager.SystemType.PATHFINDING] = pathfinding_priority
	manager.system_priority[ThreadManager.SystemType.PHYSICS] = physics_priority
	manager.system_priority[ThreadManager.SystemType.ROOM_DETECTION] = room_detection_priority

# Apply configuration to a WorldThreadingSystem
func apply_to_threading_system(system: WorldThreadingSystem) -> void:
	if not system:
		push_error("Cannot apply configuration to null WorldThreadingSystem")
		return
	
	# Apply system-specific settings
	system.thread_atmosphere = thread_atmosphere
	system.thread_room_detection = thread_room_detection
	system.thread_entity_processing = thread_entity_processing
	system.thread_pathfinding = thread_pathfinding
	system.thread_chunk_size = chunk_size
	system.use_adaptive_chunking = adaptive_chunking
	system.min_entities_for_threading = min_entities_for_threading
	
	# Apply to the thread manager as well
	if system.thread_manager:
		apply_to_thread_manager(system.thread_manager)

# Get recommended settings based on system capabilities
static func get_recommended_settings() -> ThreadingConfig:
	var config = ThreadingConfig.new()
	
	# Determine settings based on system
	var processor_count = OS.get_processor_count()
	
	# More conservative with fewer cores
	if processor_count <= 2:
		config.enable_threading = false
	elif processor_count <= 4:
		config.max_threads = 2
		config.chunk_size = 32
		config.thread_entity_processing = false  # Less critical system
	else:
		# Powerful system with many cores
		config.max_threads = processor_count - 2
		config.chunk_size = 16
	
	# Set adaptive options
	config.adaptive_threading = processor_count > 4
	
	return config
