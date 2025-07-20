extends VBoxContainer

# Performance preset configurations
const PERFORMANCE_PRESETS = ["Ultra Low", "Low", "Medium", "High", "Ultra"]

# UI element references
var quality_preset_dropdown: OptionButton
var adaptive_performance_toggle: CheckBox
var target_framerate_slider: HSlider
var target_framerate_display: Label

var lighting_quality_dropdown: OptionButton
var shadow_quality_dropdown: OptionButton
var sector_distance_slider: HSlider
var sector_distance_display: Label
var entity_distance_slider: HSlider
var entity_distance_display: Label
var particle_quality_dropdown: OptionButton
var physics_rate_dropdown: OptionButton

# System integration
var optimization_system = null

# Animation constants
const SETTING_CHANGE_DURATION = 0.2

func _ready():
	initialize_optimization_interface()
	setup_ui_element_references()
	configure_dropdown_options()
	connect_interface_signals()
	await integrate_optimization_system()
	load_current_optimization_settings()

func initialize_optimization_interface():
	"""Initialize the optimization interface with proper setup"""
	print("OptimizationTab: Initializing performance optimization interface")

func setup_ui_element_references():
	"""Get references to all UI elements in the optimization interface"""
	quality_preset_dropdown = $ScrollContainer/OptionsContainer/QualitySection/QualityOption
	adaptive_performance_toggle = $ScrollContainer/OptionsContainer/AutoOptimizationSection/AutoOptimizeContainer/AutoCheck
	target_framerate_slider = $ScrollContainer/OptionsContainer/AutoOptimizationSection/TargetFPSContainer/TargetFPSSlider
	target_framerate_display = $ScrollContainer/OptionsContainer/AutoOptimizationSection/TargetFPSContainer/TargetFPSValue
	
	lighting_quality_dropdown = $ScrollContainer/OptionsContainer/LightingSection/LightQualityOption
	shadow_quality_dropdown = $ScrollContainer/OptionsContainer/ShadowSection/ShadowQualityOption
	sector_distance_slider = $ScrollContainer/OptionsContainer/ChunkSection/ChunkDistanceSlider
	sector_distance_display = $ScrollContainer/OptionsContainer/ChunkSection/ChunkDistanceValue
	entity_distance_slider = $ScrollContainer/OptionsContainer/EntitySection/EntityDistanceSlider
	entity_distance_display = $ScrollContainer/OptionsContainer/EntitySection/EntityDistanceValue
	particle_quality_dropdown = $ScrollContainer/OptionsContainer/ParticleSection/ParticleQualityOption
	physics_rate_dropdown = $ScrollContainer/OptionsContainer/PhysicsSection/PhysicsRateOption

func configure_dropdown_options():
	"""Configure all dropdown menu options"""
	setup_quality_preset_options()
	setup_lighting_options()
	setup_shadow_options()
	setup_particle_options()
	setup_physics_options()

func setup_quality_preset_options():
	"""Configure performance preset dropdown options"""
	quality_preset_dropdown.clear()
	for i in range(PERFORMANCE_PRESETS.size()):
		quality_preset_dropdown.add_item(PERFORMANCE_PRESETS[i], i)

func setup_lighting_options():
	"""Configure lighting quality dropdown options"""
	lighting_quality_dropdown.clear()
	var lighting_levels = ["Disabled", "Low", "Medium", "High", "Ultra"]
	for i in range(lighting_levels.size()):
		lighting_quality_dropdown.add_item(lighting_levels[i], i)

func setup_shadow_options():
	"""Configure shadow quality dropdown options"""
	shadow_quality_dropdown.clear()
	var shadow_levels = ["Disabled", "Low", "Medium", "High"]
	for i in range(shadow_levels.size()):
		shadow_quality_dropdown.add_item(shadow_levels[i], i)

func setup_particle_options():
	"""Configure particle system dropdown options"""
	particle_quality_dropdown.clear()
	var particle_levels = ["Disabled", "Low", "Medium", "High"]
	for i in range(particle_levels.size()):
		particle_quality_dropdown.add_item(particle_levels[i], i)

func setup_physics_options():
	"""Configure physics simulation dropdown options"""
	physics_rate_dropdown.clear()
	var physics_rates = ["30 Hz", "45 Hz", "60 Hz"]
	for i in range(physics_rates.size()):
		physics_rate_dropdown.add_item(physics_rates[i], i)

func connect_interface_signals():
	"""Connect all UI element signals to their respective handlers"""
	quality_preset_dropdown.item_selected.connect(_on_performance_preset_changed)
	adaptive_performance_toggle.toggled.connect(_on_adaptive_performance_toggled)
	target_framerate_slider.value_changed.connect(_on_target_framerate_changed)
	
	lighting_quality_dropdown.item_selected.connect(_on_lighting_quality_changed)
	shadow_quality_dropdown.item_selected.connect(_on_shadow_quality_changed)
	sector_distance_slider.value_changed.connect(_on_sector_distance_changed)
	entity_distance_slider.value_changed.connect(_on_entity_distance_changed)
	particle_quality_dropdown.item_selected.connect(_on_particle_quality_changed)
	physics_rate_dropdown.item_selected.connect(_on_physics_rate_changed)

func integrate_optimization_system():
	"""Integrate with the system-wide optimization manager"""
	await get_tree().process_frame
	optimization_system = get_node_or_null("/root/OptimizationManager")
	
	if optimization_system:
		print("OptimizationTab: Integration with optimization system established")
		
		# Connect to optimization system signals
		if optimization_system.has_signal("quality_tier_changed"):
			optimization_system.connect("quality_tier_changed", _on_system_quality_changed)
		if optimization_system.has_signal("settings_changed"):
			optimization_system.connect("settings_changed", _on_system_setting_changed)
	else:
		print("OptimizationTab: Operating in standalone mode - optimization system not available")

func load_current_optimization_settings():
	"""Load current optimization settings from the system"""
	if not optimization_system:
		load_default_optimization_settings()
		return
	
	var current_settings = optimization_system.settings
	update_interface_from_settings(current_settings)

func load_default_optimization_settings():
	"""Load default optimization settings when system is unavailable"""
	quality_preset_dropdown.selected = 2  # Medium
	adaptive_performance_toggle.button_pressed = true
	target_framerate_slider.value = 60
	target_framerate_display.text = "60 FPS"
	
	lighting_quality_dropdown.selected = 2  # Medium
	shadow_quality_dropdown.selected = 2   # Medium
	sector_distance_slider.value = 3
	sector_distance_display.text = "3"
	entity_distance_slider.value = 20
	entity_distance_display.text = "20 units"
	particle_quality_dropdown.selected = 2  # Medium
	physics_rate_dropdown.selected = 2     # 60 Hz

func update_interface_from_settings(settings: Dictionary):
	"""Update the interface to reflect current optimization settings"""
	if settings.has("quality_tier"):
		quality_preset_dropdown.selected = settings.quality_tier
	
	if settings.has("auto_optimize"):
		adaptive_performance_toggle.button_pressed = settings.auto_optimize
		update_adaptive_controls_availability(settings.auto_optimize)
	
	if settings.has("target_fps"):
		target_framerate_slider.value = settings.target_fps
		target_framerate_display.text = str(int(settings.target_fps)) + " FPS"
	
	if settings.has("light_quality"):
		lighting_quality_dropdown.selected = settings.light_quality
		update_lighting_dependent_controls(settings.light_quality)
	
	if settings.has("shadow_quality"):
		shadow_quality_dropdown.selected = settings.shadow_quality
	
	if settings.has("chunk_load_distance"):
		sector_distance_slider.value = settings.chunk_load_distance
		sector_distance_display.text = str(int(settings.chunk_load_distance))
	
	if settings.has("entity_cull_distance"):
		entity_distance_slider.value = settings.entity_cull_distance
		entity_distance_display.text = str(int(settings.entity_cull_distance)) + " units"
	
	if settings.has("particle_quality"):
		particle_quality_dropdown.selected = settings.particle_quality
	
	if settings.has("physics_tick_rate"):
		physics_rate_dropdown.selected = map_physics_rate_to_index(settings.physics_tick_rate)

func map_physics_rate_to_index(rate: int) -> int:
	"""Convert physics tick rate to dropdown index"""
	match rate:
		30: return 0
		45: return 1
		60: return 2
		_: return 2  # Default to 60 Hz

func update_adaptive_controls_availability(adaptive_enabled: bool):
	"""Update the availability of controls based on adaptive performance mode"""
	target_framerate_slider.editable = adaptive_enabled
	target_framerate_display.modulate.a = 1.0 if adaptive_enabled else 0.6

func update_lighting_dependent_controls(lighting_quality: int):
	"""Update controls that depend on lighting quality settings"""
	var shadows_available = lighting_quality > 0
	shadow_quality_dropdown.disabled = not shadows_available
	shadow_quality_dropdown.modulate.a = 1.0 if shadows_available else 0.6

# Signal handlers for UI interactions
func _on_performance_preset_changed(preset_index: int):
	"""Handle performance preset changes"""
	print("OptimizationTab: Performance preset changed to ", PERFORMANCE_PRESETS[preset_index])
	
	if optimization_system:
		optimization_system.apply_quality_preset(preset_index)
	
	animate_setting_change(quality_preset_dropdown)

func _on_adaptive_performance_toggled(enabled: bool):
	"""Handle adaptive performance mode toggle"""
	print("OptimizationTab: Adaptive performance mode ", "enabled" if enabled else "disabled")
	
	if optimization_system:
		optimization_system.set_setting("auto_optimize", enabled)
	
	update_adaptive_controls_availability(enabled)
	animate_setting_change(adaptive_performance_toggle)

func _on_target_framerate_changed(value: float):
	"""Handle target framerate slider changes"""
	var fps_target = int(value)
	target_framerate_display.text = str(fps_target) + " FPS"
	
	if optimization_system:
		optimization_system.set_setting("target_fps", fps_target)

func _on_lighting_quality_changed(quality_index: int):
	"""Handle lighting quality dropdown changes"""
	print("OptimizationTab: Lighting quality changed to level ", quality_index)
	
	if optimization_system:
		optimization_system.set_setting("light_quality", quality_index)
	
	update_lighting_dependent_controls(quality_index)
	animate_setting_change(lighting_quality_dropdown)

func _on_shadow_quality_changed(quality_index: int):
	"""Handle shadow quality dropdown changes"""
	print("OptimizationTab: Shadow quality changed to level ", quality_index)
	
	if optimization_system:
		optimization_system.set_setting("shadow_quality", quality_index)
		optimization_system.set_setting("shadows_enabled", quality_index > 0)
	
	animate_setting_change(shadow_quality_dropdown)

func _on_sector_distance_changed(distance: float):
	"""Handle sector loading distance slider changes"""
	var sector_distance = int(distance)
	sector_distance_display.text = str(sector_distance)
	
	if optimization_system:
		optimization_system.set_setting("chunk_load_distance", sector_distance)

func _on_entity_distance_changed(distance: float):
	"""Handle entity rendering distance slider changes"""
	var entity_distance = int(distance)
	entity_distance_display.text = str(entity_distance) + " units"
	
	if optimization_system:
		optimization_system.set_setting("entity_cull_distance", entity_distance)

func _on_particle_quality_changed(quality_index: int):
	"""Handle particle system quality dropdown changes"""
	print("OptimizationTab: Particle quality changed to level ", quality_index)
	
	if optimization_system:
		optimization_system.set_setting("particle_quality", quality_index)
	
	animate_setting_change(particle_quality_dropdown)

func _on_physics_rate_changed(rate_index: int):
	"""Handle physics simulation rate dropdown changes"""
	var physics_rates = [30, 45, 60]
	var selected_rate = physics_rates[rate_index]
	
	print("OptimizationTab: Physics rate changed to ", selected_rate, " Hz")
	
	if optimization_system:
		optimization_system.set_setting("physics_tick_rate", selected_rate)
	
	animate_setting_change(physics_rate_dropdown)

# System event handlers
func _on_system_quality_changed(new_quality_tier: int):
	"""Handle quality tier changes from the optimization system"""
	quality_preset_dropdown.select(new_quality_tier)
	load_current_optimization_settings()

func _on_system_setting_changed(setting_name: String, new_value):
	"""Handle individual setting changes from the optimization system"""
	if not optimization_system:
		return
	
	match setting_name:
		"auto_optimize":
			adaptive_performance_toggle.button_pressed = new_value
			update_adaptive_controls_availability(new_value)
		"target_fps":
			target_framerate_slider.value = new_value
			target_framerate_display.text = str(int(new_value)) + " FPS"
		"light_quality":
			lighting_quality_dropdown.selected = new_value
			update_lighting_dependent_controls(new_value)
		"shadow_quality":
			shadow_quality_dropdown.selected = new_value
		"chunk_load_distance":
			sector_distance_slider.value = new_value
			sector_distance_display.text = str(int(new_value))
		"entity_cull_distance":
			entity_distance_slider.value = new_value
			entity_distance_display.text = str(int(new_value)) + " units"
		"particle_quality":
			particle_quality_dropdown.selected = new_value
		"physics_tick_rate":
			physics_rate_dropdown.selected = map_physics_rate_to_index(new_value)

func animate_setting_change(control: Control):
	"""Animate visual feedback for setting changes"""
	var tween = create_tween()
	tween.tween_property(control, "modulate", Color(1.2, 1.2, 1.2), SETTING_CHANGE_DURATION * 0.5)
	tween.tween_property(control, "modulate", Color.WHITE, SETTING_CHANGE_DURATION * 0.5)
