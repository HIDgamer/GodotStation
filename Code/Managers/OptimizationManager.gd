extends Node

const DEFAULT_TARGET_FPS = 60
const MIN_ACCEPTABLE_FPS = 30
const MEASUREMENT_INTERVAL = 1.0
const ADJUSTMENT_INTERVAL = 3.0
const DISTANCE_MULTIPLIER = 32

# World detection
var world_check_interval = 1.0
var world_check_timer = 0.0
var world_found = false
var systems_initialized = false

# Core optimization settings
var settings = {
	"quality_tier": 2,
	"auto_optimize": true,
	"target_fps": DEFAULT_TARGET_FPS,
	
	# Lighting system
	"max_lights": 32,
	"light_quality": 3,
	"shadows_enabled": true,
	"shadow_quality": 2,
	"global_illumination": true,
	"light_flicker_enabled": true,
	
	# World rendering
	"chunk_load_distance": 3,
	"chunk_size": 16,
	"entity_cull_distance": 20,
	"occlusion_culling": true,
	
	# Effects and particles
	"particle_quality": 2,
	"max_particles": 1000,
	"fire_quality": 2,
	"atmosphere_quality": 2,
	
	# Physics and simulation
	"physics_tick_rate": 60,
	"simulation_distance": 15
}

var culling_settings = {
	"chunk_culling_enabled": true,
	"chunk_visibility_margin": 1.5,
	"tile_culling_method": 1,
	"light_LOD_enabled": true,
	"entity_culling_enabled": true,
	"update_frequency": 0.2
}

# Performance monitoring
var fps_samples = []
var sample_count = 10
var measurement_timer = 0.0
var adjustment_timer = 0.0

# System references
var world = null
var thread_manager = null
var atmosphere_system = null
var spatial_manager = null
var tile_occupancy_system = null

# Performance tracking
var frame_time_samples = []
var memory_samples = []
var last_performance_check = 0.0

signal settings_changed(setting_name, new_value)
signal quality_tier_changed(new_tier)
signal performance_measured(fps, frame_time, memory_usage)

func _ready():
	print("OptimizationManager: Initializing")
	load_settings()
	
	# Initialize FPS tracking
	if settings.auto_optimize:
		for i in range(sample_count):
			fps_samples.append(Engine.get_frames_per_second())
	
	# Set initial physics rate
	Engine.physics_ticks_per_second = settings.physics_tick_rate
	
	# Connect to scene changes
	get_tree().connect("tree_changed", Callable(self, "_on_scene_changed"))
	
	print("OptimizationManager: Ready, searching for world")

func _process(delta):
	if not world_found:
		world_check_timer += delta
		if world_check_timer >= world_check_interval:
			world_check_timer = 0.0
			_find_world_and_systems()
	
	if not settings.auto_optimize or not world_found:
		return
	
	measurement_timer += delta
	adjustment_timer += delta
	
	# Performance measurement
	if measurement_timer >= MEASUREMENT_INTERVAL:
		measurement_timer = 0.0
		_measure_performance()
	
	# Performance adjustment
	if adjustment_timer >= ADJUSTMENT_INTERVAL:
		adjustment_timer = 0.0
		_adjust_settings_for_performance()

func _find_world_and_systems():
	if not world:
		var world_nodes = get_tree().get_nodes_in_group("world")
		if world_nodes.size() > 0:
			world = world_nodes[0]
	
	if world:
		world_found = true
		_connect_to_world_systems()
		if not systems_initialized:
			call_deferred("_initialize_optimization_systems")
			systems_initialized = true
		print("OptimizationManager: World found - ", world.name)

func _connect_to_world_systems():
	# Get system references from world
	thread_manager = world.get_node_or_null("ThreadManager")
	atmosphere_system = world.get_node_or_null("AtmosphereSystem")
	spatial_manager = world.get_node_or_null("SpatialManager")
	tile_occupancy_system = world.get_node_or_null("TileOccupancySystem")
	
	# Connect to world signals
	if world.has_signal("player_changed_position"):
		if not world.is_connected("player_changed_position", Callable(self, "_on_player_position_changed")):
			world.connect("player_changed_position", _on_player_position_changed)

func _initialize_optimization_systems():
	await get_tree().process_frame
	
	apply_all_settings()
	_setup_threading_optimization()
	_setup_culling_systems()
	
	print("OptimizationManager: Systems initialized")

func _setup_threading_optimization():
	if not thread_manager:
		return
	
	# Configure thread manager based on system capabilities
	var cpu_count = OS.get_processor_count()
	if cpu_count >= 8:
		thread_manager.MAX_WORKER_THREADS = 4
	elif cpu_count >= 4:
		thread_manager.MAX_WORKER_THREADS = 2
	else:
		thread_manager.MAX_WORKER_THREADS = 1
	
	# Adjust task timeouts based on quality tier
	match settings.quality_tier:
		0, 1:  # Low quality - faster timeouts
			thread_manager.TASK_TIMEOUT_MS = 1500
			thread_manager.FRAME_BUDGET_MS = 2.0
		2, 3:  # Medium/High quality
			thread_manager.TASK_TIMEOUT_MS = 3000
			thread_manager.FRAME_BUDGET_MS = 3.0
		4:     # Ultra quality - longer timeouts
			thread_manager.TASK_TIMEOUT_MS = 5000
			thread_manager.FRAME_BUDGET_MS = 4.0

func _setup_culling_systems():
	# Configure chunk culling if available
	var culling_system = world.get_node_or_null("ChunkCullingSystem")
	if culling_system:
		culling_system.occlusion_enabled = settings.occlusion_culling
		culling_system.update_interval = culling_settings.update_frequency
		culling_system.visibility_margin = culling_settings.chunk_visibility_margin
	
	# Configure spatial manager culling
	if spatial_manager:
		if spatial_manager.has_method("set_entity_cull_distance"):
			spatial_manager.set_entity_cull_distance(settings.entity_cull_distance * DISTANCE_MULTIPLIER)

func apply_quality_preset(tier: int):
	var old_tier = settings.quality_tier
	settings.quality_tier = tier
	
	match tier:
		0:  # Ultra Low
			_apply_ultra_low_settings()
		1:  # Low
			_apply_low_settings()
		2:  # Medium
			_apply_medium_settings()
		3:  # High
			_apply_high_settings()
		4:  # Ultra
			_apply_ultra_settings()
	
	apply_all_settings()
	
	if old_tier != tier:
		emit_signal("quality_tier_changed", tier)

func _apply_ultra_low_settings():
	settings.light_quality = 0
	settings.shadows_enabled = false
	settings.global_illumination = false
	settings.max_lights = 8
	settings.chunk_load_distance = 2
	settings.entity_cull_distance = 10
	settings.particle_quality = 0
	settings.max_particles = 100
	settings.fire_quality = 0
	settings.atmosphere_quality = 0
	settings.physics_tick_rate = 30
	settings.simulation_distance = 8
	culling_settings.chunk_visibility_margin = 1.0
	culling_settings.update_frequency = 0.3

func _apply_low_settings():
	settings.light_quality = 1
	settings.shadows_enabled = false
	settings.global_illumination = false
	settings.max_lights = 16
	settings.chunk_load_distance = 2
	settings.entity_cull_distance = 15
	settings.particle_quality = 1
	settings.max_particles = 300
	settings.fire_quality = 1
	settings.atmosphere_quality = 1
	settings.physics_tick_rate = 45
	settings.simulation_distance = 10
	culling_settings.chunk_visibility_margin = 1.2
	culling_settings.update_frequency = 0.25

func _apply_medium_settings():
	settings.light_quality = 2
	settings.shadows_enabled = true
	settings.shadow_quality = 1
	settings.global_illumination = false
	settings.max_lights = 24
	settings.chunk_load_distance = 3
	settings.entity_cull_distance = 20
	settings.particle_quality = 2
	settings.max_particles = 500
	settings.fire_quality = 2
	settings.atmosphere_quality = 2
	settings.physics_tick_rate = 60
	settings.simulation_distance = 15
	culling_settings.chunk_visibility_margin = 1.5
	culling_settings.update_frequency = 0.2

func _apply_high_settings():
	settings.light_quality = 3
	settings.shadows_enabled = true
	settings.shadow_quality = 2
	settings.global_illumination = true
	settings.max_lights = 32
	settings.chunk_load_distance = 4
	settings.entity_cull_distance = 25
	settings.particle_quality = 2
	settings.max_particles = 1000
	settings.fire_quality = 2
	settings.atmosphere_quality = 2
	settings.physics_tick_rate = 60
	settings.simulation_distance = 20
	culling_settings.chunk_visibility_margin = 2.0
	culling_settings.update_frequency = 0.15

func _apply_ultra_settings():
	settings.light_quality = 4
	settings.shadows_enabled = true
	settings.shadow_quality = 3
	settings.global_illumination = true
	settings.max_lights = 64
	settings.chunk_load_distance = 5
	settings.entity_cull_distance = 30
	settings.particle_quality = 3
	settings.max_particles = 2000
	settings.fire_quality = 3
	settings.atmosphere_quality = 3
	settings.physics_tick_rate = 60
	settings.simulation_distance = 25
	culling_settings.chunk_visibility_margin = 3.0
	culling_settings.update_frequency = 0.1

func apply_all_settings():
	if not world_found:
		return
	
	_apply_lighting_settings()
	_apply_world_settings()
	_apply_effects_settings()
	_apply_physics_settings()
	_apply_threading_settings()

func _apply_lighting_settings():
	var light_nodes = get_tree().get_nodes_in_group("lights")
	var active_light_count = 0
	
	for light in light_nodes:
		active_light_count += 1
		
		# Disable excess lights
		if active_light_count > settings.max_lights:
			light.visible = false
			continue
		
		light.visible = true
		
		# Configure light properties based on quality
		if light is PointLight2D:
			light.shadow_enabled = settings.shadows_enabled and settings.shadow_quality > 0
			
			if light.shadow_enabled:
				light.shadow_filter_smooth = [0, 0, 1.0, 2.0, 3.0][settings.shadow_quality]
			
			# Adjust light energy based on quality
			var energy_multiplier = [0.5, 0.7, 1.0, 1.2, 1.5][settings.light_quality]
			if light.has_method("set_energy"):
				var base_energy = light.get("default_energy") if "default_energy" in light else 1.0
				light.set_energy(base_energy * energy_multiplier)
		
		# Update light flicker if supported
		if "flicker_enabled" in light:
			light.flicker_enabled = settings.light_flicker_enabled

func _apply_world_settings():
	if not world:
		return
	
	# Update entity culling distance
	if spatial_manager and spatial_manager.has_method("set_entity_cull_distance"):
		spatial_manager.set_entity_cull_distance(settings.entity_cull_distance * DISTANCE_MULTIPLIER)
	elif spatial_manager and "entity_cull_distance" in spatial_manager:
		spatial_manager.entity_cull_distance = settings.entity_cull_distance * DISTANCE_MULTIPLIER
	
	# Update occlusion culling
	var culling_system = world.get_node_or_null("ChunkCullingSystem")
	if culling_system:
		if "occlusion_enabled" in culling_system:
			culling_system.occlusion_enabled = settings.occlusion_culling
		if "update_interval" in culling_system:
			culling_system.update_interval = culling_settings.update_frequency
	
	# Update simulation distance
	if "simulation_distance" in world:
		world.simulation_distance = settings.simulation_distance

func _apply_effects_settings():
	# Configure particle systems
	var particle_nodes = get_tree().get_nodes_in_group("particles")
	for particle in particle_nodes:
		if particle is CPUParticles2D or particle is GPUParticles2D:
			var amount_scale = [0.1, 0.3, 0.7, 1.0][settings.particle_quality]
			
			if "amount" in particle:
				var base_amount = particle.get_meta("base_amount", particle.amount)
				particle.set_meta("base_amount", base_amount)
				particle.amount = int(base_amount * amount_scale)
			
			particle.emitting = settings.particle_quality > 0
	
	# Configure fire effects
	var fire_nodes = get_tree().get_nodes_in_group("fire")
	for fire in fire_nodes:
		if fire.has_method("set_quality"):
			fire.set_quality(settings.fire_quality)
	
	# Configure atmosphere system
	if atmosphere_system:
		_configure_atmosphere_quality()

func _configure_atmosphere_quality():
	if not atmosphere_system.has_method("set_quality"):
		# Manual configuration for atmosphere quality
		match settings.atmosphere_quality:
			0:  # Simple
				if "update_interval" in atmosphere_system:
					atmosphere_system.update_interval = 1.0
				if "max_cells_per_tick" in atmosphere_system:
					atmosphere_system.max_cells_per_tick = 50
			1:  # Medium
				if "update_interval" in atmosphere_system:
					atmosphere_system.update_interval = 0.5
				if "max_cells_per_tick" in atmosphere_system:
					atmosphere_system.max_cells_per_tick = 100
			2, 3:  # High/Ultra
				if "update_interval" in atmosphere_system:
					atmosphere_system.update_interval = 0.2
				if "max_cells_per_tick" in atmosphere_system:
					atmosphere_system.max_cells_per_tick = 200
	else:
		atmosphere_system.set_quality(settings.atmosphere_quality)

func _apply_physics_settings():
	Engine.physics_ticks_per_second = settings.physics_tick_rate
	
	if world and "simulation_distance" in world:
		world.simulation_distance = settings.simulation_distance
	
	if tile_occupancy_system and "simulation_range" in tile_occupancy_system:
		tile_occupancy_system.simulation_range = settings.simulation_distance

func _apply_threading_settings():
	if not thread_manager:
		return
	
	# Queue threading optimization tasks based on current settings
	if settings.atmosphere_quality > 0 and atmosphere_system:
		_queue_atmosphere_optimization()
	
	if settings.quality_tier >= 2:
		_queue_visibility_optimization()

func _queue_atmosphere_optimization():
	if not thread_manager or not world:
		return
	
	# Get player reference from world
	var player = world.local_player if world.local_player else world.player
	if not player:
		return
	
	var player_tile = world.get_tile_at(player.position, world.current_z_level)
	var nearby_coords = _get_nearby_coordinates(player_tile, 10)
	
	thread_manager.queue_atmosphere_processing(nearby_coords, thread_manager.TaskPriority.MEDIUM)

func _queue_visibility_optimization():
	if not thread_manager or not world:
		return
	
	# Queue room detection for current z-level
	thread_manager.queue_room_detection(world.current_z_level, thread_manager.TaskPriority.LOW)

func _get_nearby_coordinates(center: Vector2i, radius: int) -> Array:
	var coords = []
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			coords.append(Vector2i(center.x + x, center.y + y))
	return coords

func _measure_performance():
	var current_fps = Engine.get_frames_per_second()
	var frame_time = 1000.0 / max(current_fps, 1.0)  # Frame time in milliseconds
	var memory_usage = OS.get_static_memory_usage()
	
	# Update FPS samples
	fps_samples.push_back(current_fps)
	if fps_samples.size() > sample_count:
		fps_samples.remove_at(0)
	
	# Update frame time samples
	frame_time_samples.push_back(frame_time)
	if frame_time_samples.size() > sample_count:
		frame_time_samples.remove_at(0)
	
	# Update memory samples
	memory_samples.push_back(memory_usage)
	if memory_samples.size() > sample_count:
		memory_samples.remove_at(0)
	
	emit_signal("performance_measured", current_fps, frame_time, memory_usage)

func get_average_fps() -> float:
	if fps_samples.is_empty():
		return Engine.get_frames_per_second()
	
	var sum = 0.0
	for sample in fps_samples:
		sum += sample
	return sum / fps_samples.size()

func get_average_frame_time() -> float:
	if frame_time_samples.is_empty():
		return 16.67  # 60 FPS baseline
	
	var sum = 0.0
	for sample in frame_time_samples:
		sum += sample
	return sum / frame_time_samples.size()

func _adjust_settings_for_performance():
	var avg_fps = get_average_fps()
	var target = settings.target_fps
	var performance_ratio = avg_fps / target
	
	# Prevent adjustments at quality extremes
	if (settings.quality_tier == 0 and avg_fps < target) or \
	   (settings.quality_tier == 4 and avg_fps > target):
		return
	
	# Significant performance issues - drop quality tier
	if avg_fps < MIN_ACCEPTABLE_FPS and settings.quality_tier > 0:
		var new_tier = settings.quality_tier - 1
		print("OptimizationManager: Performance critical (", avg_fps, " FPS), reducing to tier ", new_tier)
		apply_quality_preset(new_tier)
		return
	
	# Excellent performance - increase quality tier
	if performance_ratio > 1.3 and settings.quality_tier < 4:
		var new_tier = settings.quality_tier + 1
		print("OptimizationManager: Performance excellent (", avg_fps, " FPS), increasing to tier ", new_tier)
		apply_quality_preset(new_tier)
		return
	
	# Fine-tune within current tier
	if performance_ratio < 0.9:
		_reduce_performance_impact()
	elif performance_ratio > 1.1:
		_increase_visual_quality()

func _reduce_performance_impact():
	# Reduce particle count
	if settings.max_particles > 100:
		settings.max_particles = max(settings.max_particles * 0.8, 100)
		_apply_effects_settings()
	
	# Disable light flicker
	if settings.light_flicker_enabled:
		settings.light_flicker_enabled = false
		_apply_lighting_settings()
	
	# Increase culling update frequency
	if culling_settings.update_frequency < 0.5:
		culling_settings.update_frequency += 0.05
		_apply_world_settings()

func _increase_visual_quality():
	# Increase particle count
	if settings.max_particles < 2000:
		settings.max_particles = min(settings.max_particles * 1.1, 2000)
		_apply_effects_settings()
	
	# Enable light flicker
	if not settings.light_flicker_enabled:
		settings.light_flicker_enabled = true
		_apply_lighting_settings()
	
	# Decrease culling update frequency for better quality
	if culling_settings.update_frequency > 0.1:
		culling_settings.update_frequency = max(culling_settings.update_frequency - 0.02, 0.1)
		_apply_world_settings()

func get_setting(name: String):
	return settings.get(name)

func set_setting(name: String, value):
	if not name in settings:
		return false
	
	var old_value = settings[name]
	settings[name] = value
	
	if old_value != value:
		_apply_setting_change(name)
		emit_signal("settings_changed", name, value)
		return true
	
	return false

func _apply_setting_change(setting_name: String):
	match setting_name:
		"quality_tier":
			apply_quality_preset(settings[setting_name])
		"auto_optimize", "target_fps":
			pass  # No immediate action needed
		"max_lights", "light_quality", "shadows_enabled", "shadow_quality", "global_illumination", "light_flicker_enabled":
			_apply_lighting_settings()
		"chunk_load_distance", "entity_cull_distance", "occlusion_culling":
			_apply_world_settings()
		"particle_quality", "max_particles", "fire_quality", "atmosphere_quality":
			_apply_effects_settings()
		"physics_tick_rate", "simulation_distance":
			_apply_physics_settings()

func save_settings() -> bool:
	var config = ConfigFile.new()
	
	for key in settings.keys():
		config.set_value("optimization", key, settings[key])
	
	for key in culling_settings.keys():
		config.set_value("culling", key, culling_settings[key])
	
	var err = config.save("user://optimization_settings.cfg")
	if err != OK:
		print("OptimizationManager: Failed to save settings: ", err)
		return false
	
	return true

func load_settings() -> bool:
	var config = ConfigFile.new()
	var err = config.load("user://optimization_settings.cfg")
	
	if err != OK:
		print("OptimizationManager: Using default settings")
		return false
	
	var loaded_count = 0
	
	for key in settings.keys():
		if config.has_section_key("optimization", key):
			settings[key] = config.get_value("optimization", key)
			loaded_count += 1
	
	for key in culling_settings.keys():
		if config.has_section_key("culling", key):
			culling_settings[key] = config.get_value("culling", key)
			loaded_count += 1
	
	print("OptimizationManager: Loaded ", loaded_count, " settings")
	return true

func estimate_system_capabilities() -> int:
	var cpu_count = OS.get_processor_count()
	var memory_usage = OS.get_static_memory_usage()
	
	# Determine recommended quality tier based on hardware
	if cpu_count >= 12 and memory_usage < 2000000000:
		return 4  # Ultra
	elif cpu_count >= 8 and memory_usage < 3000000000:
		return 3  # High
	elif cpu_count >= 4 and memory_usage < 4000000000:
		return 2  # Medium
	elif cpu_count >= 2:
		return 1  # Low
	else:
		return 0  # Ultra Low

func get_performance_info() -> Dictionary:
	return {
		"average_fps": get_average_fps(),
		"average_frame_time": get_average_frame_time(),
		"quality_tier": settings.quality_tier,
		"thread_manager_active": thread_manager != null,
		"world_connected": world_found,
		"auto_optimize": settings.auto_optimize
	}

func _on_scene_changed():
	world_found = false
	systems_initialized = false
	world = null
	thread_manager = null
	atmosphere_system = null
	spatial_manager = null
	tile_occupancy_system = null
	world_check_timer = 0.0

func _on_player_position_changed(position: Vector2, z_level: int):
	# Update chunk loading around player
	if world and world.has_method("load_chunks_around"):
		world.load_chunks_around(position, z_level, settings.chunk_load_distance)
	
	# Queue optimization tasks for new area
	if thread_manager:
		call_deferred("_queue_area_optimization", position, z_level)

func _queue_area_optimization(position: Vector2, z_level: int):
	if not thread_manager or not world:
		return
	
	var player_tile = world.get_tile_at(position, z_level)
	var nearby_coords = _get_nearby_coordinates(player_tile, 8)
	
	# Queue atmosphere processing for new area
	thread_manager.queue_atmosphere_processing(nearby_coords, thread_manager.TaskPriority.MEDIUM)
	
	# Queue vision calculation if needed
	if settings.quality_tier >= 2:
		var vision_radius = min(10, settings.entity_cull_distance)
		var world_data = world.get_thread_safe_world_snapshot(z_level)
		thread_manager.queue_vision_calculation(
			player_tile, z_level, vision_radius, true, world_data, thread_manager.TaskPriority.HIGH
		)

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		save_settings()
