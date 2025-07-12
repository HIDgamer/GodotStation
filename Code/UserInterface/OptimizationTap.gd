extends VBoxContainer

# Optimization presets
const QUALITY_PRESETS = ["Ultra Low", "Low", "Medium", "High", "Ultra"]

# References to UI elements
var quality_option: OptionButton
var auto_optimize_check: CheckBox
var target_fps_slider: HSlider
var target_fps_value: Label

var light_quality_option: OptionButton
var shadow_quality_option: OptionButton
var chunk_distance_slider: HSlider
var chunk_distance_value: Label
var entity_distance_slider: HSlider
var entity_distance_value: Label
var particle_quality_option: OptionButton
var physics_rate_option: OptionButton

# Reference to optimization manager
var opt_manager = null

func _ready():
	# Get references to nodes
	quality_option = $ScrollContainer/OptionsContainer/QualitySection/QualityOption
	auto_optimize_check = $ScrollContainer/OptionsContainer/AutoSection/AutoCheck
	target_fps_slider = $ScrollContainer/OptionsContainer/FPSSection/TargetFPSSlider
	target_fps_value = $ScrollContainer/OptionsContainer/FPSSection/TargetFPSValue
	
	light_quality_option = $ScrollContainer/OptionsContainer/LightSection/LightQualityOption
	shadow_quality_option = $ScrollContainer/OptionsContainer/ShadowSection/ShadowQualityOption
	chunk_distance_slider = $ScrollContainer/OptionsContainer/ChunkSection/ChunkDistanceSlider
	chunk_distance_value = $ScrollContainer/OptionsContainer/ChunkSection/ChunkDistanceValue
	entity_distance_slider = $ScrollContainer/OptionsContainer/EntitySection/EntityDistanceSlider
	entity_distance_value = $ScrollContainer/OptionsContainer/EntitySection/EntityDistanceValue
	particle_quality_option = $ScrollContainer/OptionsContainer/ParticleSection/ParticleQualityOption
	physics_rate_option = $ScrollContainer/OptionsContainer/PhysicsSection/PhysicsRateOption
	
	# Setup quality presets dropdown
	quality_option.clear()
	for i in range(QUALITY_PRESETS.size()):
		quality_option.add_item(QUALITY_PRESETS[i], i)
	
	# Setup light quality dropdown
	light_quality_option.clear()
	light_quality_option.add_item("Disabled", 0)
	light_quality_option.add_item("Low", 1)
	light_quality_option.add_item("Medium", 2)
	light_quality_option.add_item("High", 3)
	light_quality_option.add_item("Ultra", 4)
	
	# Setup shadow quality dropdown
	shadow_quality_option.clear()
	shadow_quality_option.add_item("Disabled", 0)
	shadow_quality_option.add_item("Low", 1)
	shadow_quality_option.add_item("Medium", 2)
	shadow_quality_option.add_item("High", 3)
	
	# Setup particle quality dropdown
	particle_quality_option.clear()
	particle_quality_option.add_item("Disabled", 0)
	particle_quality_option.add_item("Low", 1)
	particle_quality_option.add_item("Medium", 2)
	particle_quality_option.add_item("High", 3)
	
	# Setup physics rate dropdown
	physics_rate_option.clear()
	physics_rate_option.add_item("30 Hz", 0)
	physics_rate_option.add_item("45 Hz", 1)
	physics_rate_option.add_item("60 Hz", 2)
	
	# Connect signals
	connect_signals()
	
	# Find OptimizationManager reference
	await get_tree().process_frame
	opt_manager = get_node_or_null("/root/OptimizationManager")
	
	if opt_manager:
		# Connect to optimization manager signals
		opt_manager.connect("quality_tier_changed", _on_quality_tier_changed)
		opt_manager.connect("settings_changed", _on_setting_changed)
		
		# Load initial values from optimization manager
		load_settings_from_manager()
	else:
		print("OptimizationSettingsTab: OptimizationManager not found")

func connect_signals():
	# Connect UI signals to handlers
	quality_option.item_selected.connect(_on_quality_preset_selected)
	auto_optimize_check.toggled.connect(_on_auto_optimize_toggled)
	target_fps_slider.value_changed.connect(_on_target_fps_changed)
	
	light_quality_option.item_selected.connect(_on_light_quality_selected)
	shadow_quality_option.item_selected.connect(_on_shadow_quality_selected)
	chunk_distance_slider.value_changed.connect(_on_chunk_distance_changed)
	entity_distance_slider.value_changed.connect(_on_entity_distance_changed)
	particle_quality_option.item_selected.connect(_on_particle_quality_selected)
	physics_rate_option.item_selected.connect(_on_physics_rate_selected)

func load_settings_from_manager():
	if !opt_manager:
		return
	
	# Get current settings
	var settings = opt_manager.settings
	
	# Update UI to match current settings
	quality_option.selected = settings.quality_tier
	auto_optimize_check.button_pressed = settings.auto_optimize
	target_fps_slider.value = settings.target_fps
	target_fps_value.text = str(settings.target_fps) + " FPS"
	
	light_quality_option.selected = settings.light_quality
	shadow_quality_option.selected = settings.shadow_quality
	chunk_distance_slider.value = settings.chunk_load_distance
	chunk_distance_value.text = str(settings.chunk_load_distance)
	entity_distance_slider.value = settings.entity_cull_distance
	entity_distance_value.text = str(settings.entity_cull_distance) + " tiles"
	particle_quality_option.selected = settings.particle_quality
	
	# Map physics rate to dropdown options
	var physics_index = 2  # Default to 60 Hz
	match settings.physics_tick_rate:
		30: physics_index = 0
		45: physics_index = 1
		60: physics_index = 2
	physics_rate_option.selected = physics_index

# Signal Handlers
func _on_quality_preset_selected(index):
	if opt_manager:
		opt_manager.apply_quality_preset(index)

func _on_auto_optimize_toggled(enabled):
	if opt_manager:
		opt_manager.set_setting("auto_optimize", enabled)
	
	# Enable/disable target FPS controls based on auto-optimize
	target_fps_slider.editable = enabled
	target_fps_value.modulate.a = 1.0 if enabled else 0.5

func _on_target_fps_changed(value):
	if opt_manager:
		opt_manager.set_setting("target_fps", value)
	
	# Update label
	target_fps_value.text = str(int(value)) + " FPS"

func _on_light_quality_selected(index):
	if opt_manager:
		opt_manager.set_setting("light_quality", index)
		
		# Enable/disable shadows based on light quality
		shadow_quality_option.editable = (index > 0)
		shadow_quality_option.modulate.a = 1.0 if index > 0 else 0.5

func _on_shadow_quality_selected(index):
	if opt_manager:
		opt_manager.set_setting("shadow_quality", index)
		opt_manager.set_setting("shadows_enabled", index > 0)

func _on_chunk_distance_changed(value):
	if opt_manager:
		opt_manager.set_setting("chunk_load_distance", int(value))
	
	# Update label
	chunk_distance_value.text = str(int(value))

func _on_entity_distance_changed(value):
	if opt_manager:
		opt_manager.set_setting("entity_cull_distance", int(value))
	
	# Update label
	entity_distance_value.text = str(int(value)) + " tiles"

func _on_particle_quality_selected(index):
	if opt_manager:
		opt_manager.set_setting("particle_quality", index)

func _on_physics_rate_selected(index):
	# Map dropdown index to actual physics rate
	var rate = 60
	match index:
		0: rate = 30
		1: rate = 45
		2: rate = 60
	
	if opt_manager:
		opt_manager.set_setting("physics_tick_rate", rate)

# Event handlers for changes from OptimizationManager
func _on_quality_tier_changed(new_tier):
	quality_option.select(new_tier)
	
	# Reload all settings since a quality change affects multiple settings
	load_settings_from_manager()

func _on_setting_changed(setting_name, new_value):
	# Update UI if a setting changes externally
	if !opt_manager:
		return
		
	match setting_name:
		"auto_optimize":
			auto_optimize_check.button_pressed = new_value
		"target_fps":
			target_fps_slider.value = new_value
			target_fps_value.text = str(int(new_value)) + " FPS"
		"light_quality":
			light_quality_option.selected = new_value
		"shadow_quality":
			shadow_quality_option.selected = new_value
		"chunk_load_distance":
			chunk_distance_slider.value = new_value
			chunk_distance_value.text = str(int(new_value))
		"entity_cull_distance":
			entity_distance_slider.value = new_value
			entity_distance_value.text = str(int(new_value)) + " tiles"
		"particle_quality":
			particle_quality_option.selected = new_value
