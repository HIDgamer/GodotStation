extends Control

# Constants
const UPDATE_INTERVAL = 0.5  # Update frequency in seconds
const HISTORY_LENGTH = 60    # Number of samples to keep for graphs

# References
@onready var fps_label = $VBoxContainer/FPSDisplay
@onready var memory_label = $VBoxContainer/MemoryDisplay
@onready var fps_graph = $VBoxContainer/FPSGraph
@onready var quality_label = $VBoxContainer/QualityDisplay
@onready var entities_label = $VBoxContainer/EntitiesDisplay
@onready var lights_label = $VBoxContainer/LightsDisplay

# Monitoring variables
var update_timer = 0.0
var fps_history = []
var memory_history = []
var entity_count = 0
var light_count = 0
var quality_tier = 2  # Medium default
var opt_manager = null

func _ready():
	# Initialize with empty data
	for i in range(HISTORY_LENGTH):
		fps_history.append(0)
		memory_history.append(0)
	
	# Add to performance_display group for easy finding
	add_to_group("performance_display")
	
	# Find OptimizationManager reference
	await get_tree().process_frame
	opt_manager = get_node_or_null("/root/OptimizationManager")
	
	if opt_manager:
		# Connect to optimization manager signals
		opt_manager.connect("performance_measured", _on_performance_measured)
		opt_manager.connect("quality_tier_changed", _on_quality_tier_changed)
		
		# Get initial quality tier
		quality_tier = opt_manager.get_setting("quality_tier")
		update_quality_display()
	else:
		print("PerformanceMonitor: OptimizationManager not found")

func _process(delta):
	update_timer += delta
	
	if update_timer >= UPDATE_INTERVAL:
		update_timer = 0
		update_display()

func update_display():
	# Get current FPS
	var fps = Engine.get_frames_per_second()
	
	# Format FPS with color based on performance
	var fps_text = str(fps) + " FPS"
	var fps_color = Color.WHITE
	
	if fps >= 55:
		fps_color = Color.GREEN
	elif fps >= 30:
		fps_color = Color.YELLOW
	else:
		fps_color = Color.RED
	
	if fps_label:
		fps_label.text = fps_text
		fps_label.add_theme_color_override("font_color", fps_color)
	
	# Get memory usage
	var memory = OS.get_static_memory_usage()
	var memory_text = String.humanize_size(memory)
	
	if memory_label:
		memory_label.text = memory_text
	
	# Update history arrays
	fps_history.push_back(fps)
	if fps_history.size() > HISTORY_LENGTH:
		fps_history.remove_at(0)
	
	memory_history.push_back(memory / 1048576.0)  # Convert to MB
	if memory_history.size() > HISTORY_LENGTH:
		memory_history.remove_at(0)
	
	# Update FPS graph if available
	if fps_graph and fps_graph.has_method("update_values"):
		fps_graph.update_values(fps_history)
	
	# Count entities and lights
	var entity_nodes = get_tree().get_nodes_in_group("entity")
	var light_nodes = get_tree().get_nodes_in_group("lights")
	
	entity_count = entity_nodes.size()
	light_count = light_nodes.size()
	
	# Update entity and light counts
	if entities_label:
		entities_label.text = "Entities: " + str(entity_count)
	
	if lights_label:
		lights_label.text = "Lights: " + str(light_count)

func update_quality_display():
	if quality_label:
		var quality_names = ["Ultra Low", "Low", "Medium", "High", "Ultra"]
		var quality_text = quality_names[quality_tier]
		quality_label.text = "Quality: " + quality_text

func _on_performance_measured(fps, memory):
	# This will be called by the OptimizationManager
	# We already update in _process, so no need to do anything here
	pass

func _on_quality_tier_changed(new_tier):
	quality_tier = new_tier
	update_quality_display()

# Custom function to set text (for compatibility with OptimizationManager)
func set_text(text):
	if fps_label:
		fps_label.text = text
