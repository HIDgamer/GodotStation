extends Node

## Constants
const DEFAULT_TARGET_FPS = 60
const MIN_ACCEPTABLE_FPS = 30
const MEASUREMENT_INTERVAL = 1.0  # How often to check performance (seconds)
const ADJUSTMENT_INTERVAL = 3.0   # How often to adjust settings (seconds)
const DISTANCE_MULTIPLIER = 32    # Size of a tile in pixels

## World finding
var world_check_interval = 1.0  # Seconds between world finding attempts
var world_check_timer = 0.0
var world_found = false
var settings_applied = false

## Optimization Settings (default values)
var settings = {
	# Quality Tiers: 0=Ultra Low, 1=Low, 2=Medium, 3=High, 4=Ultra
	"quality_tier": 2,
	
	# Automated optimization
	"auto_optimize": true,
	"target_fps": DEFAULT_TARGET_FPS,
	
	# Lighting
	"max_lights": 32,
	"light_quality": 3,  # 0=Disabled, 1=Low, 2=Med, 3=High, 4=Ultra
	"shadows_enabled": true,
	"shadow_quality": 2,  # 0=Disabled, 1=Low, 2=Med, 3=High
	"global_illumination": true,
	"light_flicker_enabled": true,
	
	# Map & Visibility
	"chunk_load_distance": 3,  # Number of chunks to load in each direction
	"chunk_size": 16,          # Size of each chunk in tiles
	"entity_cull_distance": 20, # Distance in tiles for entity culling
	"occlusion_culling": true,  # Use occlusion culling
	
	# Effects
	"particle_quality": 2,     # 0=None, 1=Low, 2=Med, 3=High
	"max_particles": 1000,
	"fire_quality": 2,         # 0=Simple, 1=Med, 2=High
	"atmosphere_quality": 2,   # 0=Simple, 1=Med, 2=Complex
	
	# Physics & Simulation
	"physics_tick_rate": 60,   # Physics FPS
	"simulation_distance": 15  # Distance in tiles to simulate entities
}

var culling_settings = {
	"chunk_culling_enabled": true,
	"chunk_visibility_margin": 1.5,  # Chunks outside screen to keep visible
	"tile_culling_method": 1,       # 0=None, 1=Hide, 2=Unload
	"light_LOD_enabled": true,      # Lower quality for distant lights
	"entity_culling_enabled": true,  # Hide entities in culled chunks
	"update_frequency": 0.2         # Updates per second
}

## Performance monitoring
var fps_samples = []
var sample_count = 10
var measurement_timer = 0.0
var adjustment_timer = 0.0

## System references
var world = null
var viewport = null
var performance_label = null

## Tracking for resource cleanup
var tracked_resources = []

## Signals
signal settings_changed(setting_name, new_value)
signal quality_tier_changed(new_tier)
signal performance_measured(fps, mem_usage)

func _ready():
	print("OptimizationManager: Initializing")
	
	# Initialize settings from config if available
	load_settings()
	
	# Get viewport for rendering stats
	viewport = get_viewport()
	
	# Initialize FPS counter
	if settings.auto_optimize:
		for i in range(sample_count):
			fps_samples.append(Engine.get_frames_per_second())
	
	# Set up physics tick rate
	Engine.physics_ticks_per_second = settings.physics_tick_rate
	
	# Connect to the scene_changed signal from SceneTree
	get_tree().connect("tree_changed", Callable(self, "_on_scene_changed"))
	
	print("OptimizationManager: Initialization complete, will find world when available")

func _process(delta):
	# Check for world reference periodically until found
	if not world_found:
		world_check_timer += delta
		if world_check_timer >= world_check_interval:
			world_check_timer = 0.0
			find_world_reference()
			
			# If world is found, apply settings
			if world and !settings_applied:
				print("OptimizationManager: World found, applying settings")
				apply_all_settings()
				settings_applied = true
				world_found = true
	
	# Skip optimization if not using auto-optimization
	if not settings.auto_optimize:
		return
	
	# Update measurement timer
	measurement_timer += delta
	adjustment_timer += delta
	
	# Take performance measurements
	if measurement_timer >= MEASUREMENT_INTERVAL:
		measurement_timer = 0.0
		measure_performance()
	
	# Adjust settings based on performance
	if adjustment_timer >= ADJUSTMENT_INTERVAL:
		adjustment_timer = 0.0
		adjust_settings_for_performance()
	
	# Update performance display if available
	update_performance_display()

func _exit_tree():
	# Cleanup any remaining resources when the node is removed
	clean_resources()

func find_world_reference():
	# Try different ways to find the world node
	world = get_node_or_null("World")
	
	if not world:
		# Try to find by type
		var nodes = get_tree().get_nodes_in_group("world")
		if nodes.size() > 0:
			world = nodes[0]
			print("OptimizationManager: Found world via group")
	
	if not world:
		# Try to find the current scene
		var current_scene = get_tree().current_scene
		if current_scene and (current_scene.name == "World" or (current_scene.has_method("get_tile_data") if current_scene else false)):
			world = current_scene
			print("OptimizationManager: Found world as current scene")
	
	if world:
		print("OptimizationManager: World reference found - " + world.name)
		world_found = true
		connect_world_signals()
		return true
	else:
		# Only print this message occasionally to avoid spam
		if world_check_timer < 0.1:  # Only on the first check or after resets
			print("OptimizationManager: World reference not found, will keep checking")
		return false

func _on_scene_changed():
	# Reset flags when scene changes
	world_found = false
	settings_applied = false
	world = null
	world_check_timer = 0.0  # Reset timer to check immediately

func connect_world_signals():
	# Connect to world signals if available
	if world:
		# Connect to world_loaded signal if available
		if world.has_signal("world_loaded"):
			if not world.is_connected("world_loaded", Callable(self, "_on_world_loaded")):
				world.connect("world_loaded", _on_world_loaded)
		
		# Connect to player_changed_position if available
		if world.has_signal("player_changed_position"):
			if not world.is_connected("player_changed_position", Callable(self, "_on_player_position_changed")):
				world.connect("player_changed_position", _on_player_position_changed)

# Apply culling-specific settings
func apply_culling_settings():
	if not world:
		return
		
	var culling_system = world.get_node_or_null("ChunkCullingSystem")
	if not culling_system:
		return
	
	print("OptimizationManager: Applying chunk culling settings")
	
	# Update culling settings
	culling_system.occlusion_enabled = settings.occlusion_culling
	culling_system.update_interval = culling_settings.update_frequency
	culling_system.visibility_margin = culling_settings.chunk_visibility_margin
	culling_system.cull_lights = culling_settings.light_LOD_enabled
	culling_system.cull_entities = culling_settings.entity_culling_enabled

func apply_all_settings():
	# Apply lighting settings
	apply_light_settings()
	
	# Apply map and chunk settings
	apply_map_settings()
	
	# Apply effect settings
	apply_effects_settings()
	
	# Apply physics settings
	apply_physics_settings()
	
	# Add culling settings
	apply_culling_settings()

func apply_quality_preset(tier):
	settings.quality_tier = tier
	
	# Update all settings based on the tier
	match tier:
		0:  # Ultra Low
			settings.light_quality = 0
			settings.shadows_enabled = false
			settings.shadow_quality = 0
			settings.global_illumination = false
			settings.light_flicker_enabled = false
			settings.max_lights = 8
			settings.chunk_load_distance = 2
			settings.entity_cull_distance = 10
			settings.occlusion_culling = true
			settings.particle_quality = 0
			settings.max_particles = 100
			settings.fire_quality = 0
			settings.atmosphere_quality = 0
			settings.physics_tick_rate = 30
			settings.simulation_distance = 8
			culling_settings.chunk_visibility_margin = 1.0
			culling_settings.tile_culling_method = 2
			culling_settings.light_LOD_enabled = true
			culling_settings.entity_culling_enabled = true
			culling_settings.update_frequency = 0.3
			
		1:  # Low
			settings.light_quality = 1
			settings.shadows_enabled = false
			settings.shadow_quality = 0
			settings.global_illumination = false
			settings.light_flicker_enabled = false
			settings.max_lights = 16
			settings.chunk_load_distance = 2
			settings.entity_cull_distance = 15
			settings.occlusion_culling = true
			settings.particle_quality = 1
			settings.max_particles = 300
			settings.fire_quality = 1
			settings.atmosphere_quality = 1
			settings.physics_tick_rate = 45
			settings.simulation_distance = 10
			culling_settings.chunk_visibility_margin = 1.2
			culling_settings.tile_culling_method = 1
			culling_settings.light_LOD_enabled = true
			culling_settings.entity_culling_enabled = true
			culling_settings.update_frequency = 0.25
			
		2:  # Medium (Default)
			settings.light_quality = 2
			settings.shadows_enabled = true
			settings.shadow_quality = 1
			settings.global_illumination = false
			settings.light_flicker_enabled = true
			settings.max_lights = 24
			settings.chunk_load_distance = 3
			settings.entity_cull_distance = 20
			settings.occlusion_culling = true
			settings.particle_quality = 2
			settings.max_particles = 500
			settings.fire_quality = 2
			settings.atmosphere_quality = 2
			settings.physics_tick_rate = 60
			settings.simulation_distance = 15
			culling_settings.chunk_visibility_margin = 1.5
			culling_settings.tile_culling_method = 1
			culling_settings.light_LOD_enabled = true
			culling_settings.entity_culling_enabled = true
			culling_settings.update_frequency = 0.2
			
		3:  # High
			settings.light_quality = 3
			settings.shadows_enabled = true
			settings.shadow_quality = 2
			settings.global_illumination = true
			settings.light_flicker_enabled = true
			settings.max_lights = 32
			settings.chunk_load_distance = 4
			settings.entity_cull_distance = 25
			settings.occlusion_culling = true
			settings.particle_quality = 2
			settings.max_particles = 1000
			settings.fire_quality = 2
			settings.atmosphere_quality = 2
			settings.physics_tick_rate = 60
			settings.simulation_distance = 20
			culling_settings.chunk_visibility_margin = 2.0
			culling_settings.tile_culling_method = 1
			culling_settings.light_LOD_enabled = true
			culling_settings.entity_culling_enabled = true
			culling_settings.update_frequency = 0.15
			
		4:  # Ultra
			settings.light_quality = 4
			settings.shadows_enabled = true
			settings.shadow_quality = 3
			settings.global_illumination = true
			settings.light_flicker_enabled = true
			settings.max_lights = 64
			settings.chunk_load_distance = 5
			settings.entity_cull_distance = 30
			settings.occlusion_culling = true
			settings.particle_quality = 3
			settings.max_particles = 2000
			settings.fire_quality = 3
			settings.atmosphere_quality = 3
			settings.physics_tick_rate = 60
			settings.simulation_distance = 25
			culling_settings.chunk_visibility_margin = 3.0
			culling_settings.tile_culling_method = 0
			culling_settings.light_LOD_enabled = false
			culling_settings.entity_culling_enabled = false
			culling_settings.update_frequency = 0.1
			
	# Apply all the updated settings
	apply_all_settings()
	
	# Apply culling settings
	apply_culling_settings()
	
	# Emit signal for UI updates
	emit_signal("quality_tier_changed", tier)
	
	# Emit signal for UI updates
	emit_signal("quality_tier_changed", tier)

#region LIGHTING SETTINGS
func apply_light_settings():
	# Find lighting nodes in the scene
	var light_nodes = get_tree().get_nodes_in_group("lights")
	print("OptimizationManager: Configuring " + str(light_nodes.size()) + " light sources")
	
	# Configure light quality
	var light_distance_multiplier = [0.5, 0.7, 1.0, 1.3, 1.5][settings.light_quality]
	var shadow_distance = [0, 100, 250, 500, 1000][settings.shadow_quality if settings.shadows_enabled else 0]
	
	# Configure global lighting
	var world_environment = get_tree().get_first_node_in_group("world_environment")
	if world_environment and world_environment.has_node("WorldEnvironment"):
		var env = world_environment.get_node("WorldEnvironment").environment
		if env:
			# Configure environment lighting
			env.ssao_enabled = settings.light_quality >= 3
			env.ssil_enabled = settings.light_quality >= 4
			env.sdfgi_enabled = settings.global_illumination && settings.light_quality >= 3
			env.glow_enabled = settings.light_quality >= 2
			env.volumetric_fog_enabled = settings.light_quality >= 3
	
	# Apply to all lights
	var active_light_count = 0
	for light in light_nodes:
		# Skip if we've reached the max light limit
		active_light_count += 1
		if active_light_count > settings.max_lights:
			light.visible = false
			continue
			
		# Activate the light
		light.visible = true
		
		# Apply correct scale based on quality
		if light.has_method("set_energy"):
			light.set_energy(light.default_energy if settings.light_quality > 0 else light.default_energy * 0.5)
		
		# Configure shadows and quality
		if light is PointLight2D:
			# Set light quality parameters
			if light.has_method("_set_light_quality"):
				light._set_light_quality(settings.light_quality * 20) # Convert 0-4 to 0-80
			
			# Light range adjustment
			if "light_range" in light:
				light.texture_scale = light.light_range * light_distance_multiplier
			
			# Shadow configuration
			light.shadow_enabled = settings.shadows_enabled && settings.shadow_quality > 0
			if light.shadow_enabled:
				light.shadow_filter_smooth = [0, 0, 1.0, 2.0, 3.0][settings.shadow_quality]
			
			# Enable/disable flicker effects
			if "flicker_enabled" in light:
				light.flicker_enabled = settings.light_flicker_enabled
		
		# Light manager script if available
		if light.has_method("update_quality"):
			light.update_quality(settings.light_quality)

#endregion

#region MAP AND CHUNK SETTINGS
func apply_map_settings():
	if world:
		# Set chunk loading distance
		if "loaded_chunks" in world:
			# Get player position
			var player = world.get_node_or_null("Player")
			if player:
				# Load chunks around player
				var position = player.position
				var z_level = player.current_z_level if "current_z_level" in player else 0
				
				if world.has_method("load_chunks_around"):
					world.load_chunks_around(position, z_level, settings.chunk_load_distance)
		
		# Set entity culling distance
		if "SpatialManager" in world and world.spatial_manager:
			if world.spatial_manager.has_method("set_entity_cull_distance"):
				world.spatial_manager.set_entity_cull_distance(settings.entity_cull_distance * DISTANCE_MULTIPLIER)
			elif "entity_cull_distance" in world.spatial_manager:
				world.spatial_manager.entity_cull_distance = settings.entity_cull_distance * DISTANCE_MULTIPLIER
		
		# Set occlusion culling
		if "occlusion_culling" in world:
			world.occlusion_culling = settings.occlusion_culling

#endregion

#region EFFECTS SETTINGS
func apply_effects_settings():
	# Configure particle systems
	var particle_nodes = get_tree().get_nodes_in_group("particles")
	for particle in particle_nodes:
		if particle is CPUParticles2D or particle is GPUParticles2D:
			# Scale particle amount based on quality
			var amount_scale = [0.1, 0.3, 0.7, 1.0][settings.particle_quality]
			
			if "amount" in particle:
				var base_amount = particle.amount
				if particle.has_meta("base_amount"):
					base_amount = particle.get_meta("base_amount")
				else:
					particle.set_meta("base_amount", base_amount)
				
				particle.amount = int(base_amount * amount_scale)
			
			# Disable particles entirely at lowest quality
			particle.emitting = settings.particle_quality > 0
	
	# Configure fire effects
	var fire_nodes = get_tree().get_nodes_in_group("fire")
	for fire in fire_nodes:
		if fire is Node2D and fire.has_method("set_quality"):
			fire.set_quality(settings.fire_quality)
		
		# If it's a FireTile, configure directly
		if "frame_width" in fire:
			match settings.fire_quality:
				0: # Simple
					fire.total_frames = 24  # Fewer animation frames
					fire.animation_fps = 30.0
					fire.smoke_particle_amount = 5
				1: # Medium
					fire.total_frames = 48
					fire.animation_fps = 45.0
					fire.smoke_particle_amount = 10
				2: # High
					fire.total_frames = 72
					fire.animation_fps = 60.0
					fire.smoke_particle_amount = 20
				3: # Ultra
					fire.total_frames = 72
					fire.animation_fps = 60.0
					fire.smoke_particle_amount = 30
	
	# Configure atmosphere system (if found)
	if world and "atmosphere_system" in world and world.atmosphere_system:
		var atmos = world.atmosphere_system
		
		if atmos.has_method("set_quality"):
			atmos.set_quality(settings.atmosphere_quality)
		else:
			# Try to set up common atmosphere parameters
			match settings.atmosphere_quality:
				0: # Simple
					if "update_interval" in atmos:
						atmos.update_interval = 1.0
					if "max_cells_per_tick" in atmos:
						atmos.max_cells_per_tick = 50
				1: # Medium
					if "update_interval" in atmos:
						atmos.update_interval = 0.5
					if "max_cells_per_tick" in atmos:
						atmos.max_cells_per_tick = 100
				2: # Complex
					if "update_interval" in atmos:
						atmos.update_interval = 0.2
					if "max_cells_per_tick" in atmos:
						atmos.max_cells_per_tick = 200  # Default value
				3: # Ultra
					if "update_interval" in atmos:
						atmos.update_interval = 0.1
					if "max_cells_per_tick" in atmos:
						atmos.max_cells_per_tick = 400

#endregion

#region PHYSICS AND SIMULATION
func apply_physics_settings():
	# Set physics tick rate
	Engine.physics_ticks_per_second = settings.physics_tick_rate
	
	# Apply simulation distance
	if world:
		# Set simulation distance in world
		if "simulation_distance" in world:
			world.simulation_distance = settings.simulation_distance
			
		# If we have a tile occupancy system, update it
		if "tile_occupancy_system" in world and world.tile_occupancy_system:
			if "simulation_range" in world.tile_occupancy_system:
				world.tile_occupancy_system.simulation_range = settings.simulation_distance

#endregion

#region PERFORMANCE MONITORING
func measure_performance():
	# Get current FPS
	var current_fps = Engine.get_frames_per_second()
	
	# Update samples (circular buffer)
	fps_samples.push_back(current_fps)
	if fps_samples.size() > sample_count:
		fps_samples.remove_at(0)
	
	# Get memory usage
	var mem_info = OS.get_static_memory_usage()
	
	# Emit signal with current performance data
	emit_signal("performance_measured", current_fps, mem_info)

func get_average_fps():
	var sum = 0.0
	for sample in fps_samples:
		sum += sample
	return sum / fps_samples.size()

func adjust_settings_for_performance():
	var avg_fps = get_average_fps()
	var target = settings.target_fps
	
	# Skip adjustment if we're already at the min or max quality
	if (settings.quality_tier == 0 and avg_fps < target) or \
	   (settings.quality_tier == 4 and avg_fps > target):
		return
	
	# Calculate performance margin
	var performance_margin = (avg_fps - target) / target
	
	# Significant underperformance - drop quality tier
	if avg_fps < MIN_ACCEPTABLE_FPS and settings.quality_tier > 0:
		var new_tier = settings.quality_tier - 1
		print("OptimizationManager: Performance too low (", avg_fps, " FPS), dropping to quality tier ", new_tier)
		apply_quality_preset(new_tier)
		return
	
	# Significant overperformance - increase quality tier if not at max
	if performance_margin > 0.3 and settings.quality_tier < 4:
		var new_tier = settings.quality_tier + 1
		print("OptimizationManager: Performance good (", avg_fps, " FPS), increasing to quality tier ", new_tier)
		apply_quality_preset(new_tier)
		return
	
	# Fine-grained adjustments within current quality tier
	if performance_margin < -0.1:
		# Too slow - make modest adjustments to improve performance
		if world and "ThreadingSystem" in world and world.has_node("ThreadingSystem"):
			# Try enabling thread manager if available
			var thread_system = world.get_node("ThreadingSystem")
			thread_system.enabled = true
		
		# Reduce particle count
		if settings.max_particles > 100:
			settings.max_particles = max(settings.max_particles * 0.8, 100)
			apply_effects_settings()
		
		# Reduce light flickering
		if settings.light_flicker_enabled:
			settings.light_flicker_enabled = false
			apply_light_settings()
	
	elif performance_margin > 0.1:
		# Performance good - can add some effects back
		if not settings.light_flicker_enabled:
			settings.light_flicker_enabled = true
			apply_light_settings()
			
		# Increase particle count to enhance visuals
		if settings.max_particles < 2000:
			settings.max_particles = min(settings.max_particles * 1.2, 2000)
			apply_effects_settings()

func update_performance_display():
	# If we have a performance display label, update it
	if performance_label == null:
		performance_label = get_tree().get_first_node_in_group("performance_display")
	
	if performance_label and performance_label.has_method("set_text"):
		var fps = Engine.get_frames_per_second()
		var mem = String.humanize_size(OS.get_static_memory_usage())
		var display_txt = "FPS: " + str(fps) + "\nMEM: " + mem + "\nQuality: " + str(settings.quality_tier)
		performance_label.set_text(display_txt)

#endregion

#region SETTINGS MANAGEMENT
func get_setting(name):
	if name in settings:
		return settings[name]
	return null

func set_setting(name, value):
	if name in settings:
		# Store old value for comparison
		var old_value = settings[name]
		
		# Update setting
		settings[name] = value
		
		# Apply changes if value actually changed
		if old_value != value:
			match name:
				"quality_tier": 
					apply_quality_preset(value)
				"auto_optimize", "target_fps":
					# No immediate action needed
					pass
				"max_lights", "light_quality", "shadows_enabled", "shadow_quality", "global_illumination", "light_flicker_enabled":
					apply_light_settings()
				"chunk_load_distance", "entity_cull_distance", "occlusion_culling":
					apply_map_settings()
				"particle_quality", "max_particles", "fire_quality", "atmosphere_quality":
					apply_effects_settings()
				"physics_tick_rate", "simulation_distance":
					apply_physics_settings()
			
			# Emit signal for UI updates
			emit_signal("settings_changed", name, value)
			
			return true
	
	return false

func save_settings():
	var config = ConfigFile.new()
	
	# Store all settings
	for key in settings.keys():
		config.set_value("optimization", key, settings[key])
	
	# Store culling settings
	for key in culling_settings.keys():
		config.set_value("culling", key, culling_settings[key])
	
	# Save to file
	var err = config.save("user://optimization_settings.cfg")
	if err != OK:
		print("OptimizationManager: Error saving settings: ", err)
		return false
	
	print("OptimizationManager: Settings saved successfully")
	return true

func load_settings():
	var config = ConfigFile.new()
	var err = config.load("user://optimization_settings.cfg")
	
	if err != OK:
		print("OptimizationManager: No settings file found, using defaults")
		return false
	
	# Load all settings
	var loaded_count = 0
	for key in settings.keys():
		if config.has_section_key("optimization", key):
			settings[key] = config.get_value("optimization", key)
			loaded_count += 1
	
	# Load culling settings
	for key in culling_settings.keys():
		if config.has_section_key("culling", key):
			culling_settings[key] = config.get_value("culling", key)
			loaded_count += 1
	
	print("OptimizationManager: Loaded " + str(loaded_count) + " settings")
	
	# Clean up the config object
	config = null
	
	return true

#endregion

#region SIGNAL HANDLERS
func _on_world_loaded():
	print("OptimizationManager: World loaded, applying settings")
	
	# First clean up any resources from the previous world
	clean_resources()
	
	# Reconnect to world
	find_world_reference()
	
	# Mark as not applied so we'll reapply settings
	settings_applied = false
	
	# Apply all settings to the newly loaded world
	call_deferred("apply_all_settings")

func _on_player_position_changed(position, z_level):
	# Update chunk loading around the new player position
	if world and world.has_method("load_chunks_around"):
		world.load_chunks_around(position, z_level, settings.chunk_load_distance)
	
	# Update entity culling based on new position
	if world and world.spatial_manager and world.spatial_manager.has_method("update_entity_visibility"):
		world.spatial_manager.update_entity_visibility(position, settings.entity_cull_distance * DISTANCE_MULTIPLIER)

#endregion

#region MEMORY MANAGEMENT AND UTILITIES
func track_resource(resource):
	# Add resource to tracked list if it's not already there
	if resource and not tracked_resources.has(resource):
		tracked_resources.append(resource)

func clean_resources():
	# Free all tracked resources
	for resource in tracked_resources:
		if resource is Node and is_instance_valid(resource) and not resource.is_queued_for_deletion():
			resource.queue_free()
		elif resource is Resource and resource.get_reference_count() <= 1:
			# Only the OptimizationManager is referencing this resource
			resource.unreference()
	
	# Clear the tracked resources list
	tracked_resources.clear()
	
	# Force memory cleanup for non-node resources
	force_gc()

func force_gc():
	# In Godot 4, we should use manual memory management
	print("OptimizationManager: Running manual memory cleanup")
	
	# Free unneeded cached nodes
	if performance_label != null and !is_instance_valid(performance_label):
		performance_label = null
	print("OptimizationManager: Memory cleanup completed")

func estimate_system_capabilities():
	# Determine initial quality tier based on system capabilities
	var cpu_count = OS.get_processor_count()
	var total_memory = OS.get_static_memory_usage()
	
	# Set quality tier based on system specs
	var recommended_tier = 2  # Default to medium
	
	if cpu_count >= 8 and total_memory < 2000000000:  # >8 cores, <2GB usage
		recommended_tier = 3  # High
	elif cpu_count >= 12:  # 12+ cores
		recommended_tier = 4  # Ultra
	elif cpu_count <= 2 or total_memory > 3500000000:  # <=2 cores or >3.5GB usage
		recommended_tier = 1  # Low
	elif cpu_count <= 1 or total_memory > 4000000000:  # 1 core or >4GB usage
		recommended_tier = 0  # Ultra Low
	
	return recommended_tier

func create_dynamic_resource():
	# Example of proper resource creation and tracking
	var resource = Resource.new()
	track_resource(resource)
	return resource

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		# This is called when the node is about to be deleted
		# Clean up any resources before the node is freed
		clean_resources()
#endregion
