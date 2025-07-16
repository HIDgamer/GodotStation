extends MedicalItem
class_name HealthAnalyzer

var health_analyzer_ui_scene = preload("res://Scenes/UI/Ingame/HealthAnalyzerUI.tscn")
var current_ui_instance = null

func _ready():
	super._ready()
	
	# Item properties
	item_name = "Health Analyzer"
	description = "A hand-held body scanner capable of determining a patient's health status."
	
	# Medical properties
	medical_type = MedicalItemType.TOOL
	use_time = 2.0
	use_self_time = 1.5
	
	# Sound setup
	use_sound = preload("res://Sound/items/healthanalyzer.ogg")

func should_be_consumed() -> bool:
	return false

func use_on(user, target, targeted_limb = ""):
	print("HealthAnalyzer: Attempting to scan ", target.name if target else "unknown target")
	
	# Validate target
	if not target:
		show_message_to_user(user, "No valid target to scan.")
		return false
	
	# Check if target has health system
	var health_system = get_target_health_system(target)
	if not health_system:
		show_message_to_user(user, "Unable to detect biological signatures.")
		play_error_sound()
		return false
	
	# Check range (if user has position)
	if user and target and both_have_position(user, target):
		var distance = user.global_position.distance_to(target.global_position)
		if distance > 64: # 2 tiles in pixels
			show_message_to_user(user, "Target is too far away for accurate scanning.")
			return false
	
	# Play scan sound
	if use_sound:
		play_audio(use_sound)
	
	# Show scanning message
	show_message_to_user(user, "Scanning " + get_target_name(target) + "...")
	
	# Create and show UI
	if current_ui_instance:
		current_ui_instance.queue_free()
	
	current_ui_instance = health_analyzer_ui_scene.instantiate()
	
	# FIXED: Add to proper UI layer instead of world scene
	_add_ui_to_viewport(current_ui_instance, user)
	
	# Connect close signal
	current_ui_instance.ui_closed.connect(_on_ui_closed)
	
	# Determine detail level based on user skills
	var detail_level = HealthScanData.DetailLevel.STANDARD
	if user and user.has_method("get_skill_level"):
		var medical_skill = user.get_skill_level("medical")
		if medical_skill >= 3:
			detail_level = HealthScanData.DetailLevel.MEDICAL
		elif medical_skill >= 2:
			detail_level = HealthScanData.DetailLevel.FULL
	
	# Show scan results
	current_ui_instance.show_scan_results(target, detail_level)
	
	# Show usage message
	var scanner_message = "Health analysis complete."
	if targeted_limb and targeted_limb != "":
		scanner_message += " Focused scan on " + targeted_limb + "."
	
	show_message_to_user(user, scanner_message)
	
	return true

func _add_ui_to_viewport(ui_instance, user):
	"""Add UI to the proper viewport layer"""
	
	# Method 1: Try to add to user's UI layer (best for multiplayer)
	if user and _try_add_to_user_ui_layer(ui_instance, user):
		print("HealthAnalyzer: UI added to user's UI layer")
		return
	
	# Method 2: Try to add to a CanvasLayer in the scene
	if _try_add_to_canvas_layer(ui_instance):
		print("HealthAnalyzer: UI added to CanvasLayer")
		return
	
	# Method 3: Create our own CanvasLayer
	if _create_canvas_layer_for_ui(ui_instance):
		print("HealthAnalyzer: UI added to new CanvasLayer")
		return
	
	# Method 4: Fallback - add directly to viewport (last resort)
	var viewport = get_viewport()
	if viewport:
		viewport.add_child(ui_instance)
		print("HealthAnalyzer: UI added directly to viewport")
	else:
		print("HealthAnalyzer: ERROR - Could not add UI to viewport!")

func _try_add_to_user_ui_layer(ui_instance, user) -> bool:
	"""Try to add UI to user's dedicated UI layer"""
	
	# Look for PlayerUI or UILayer in the user entity
	var ui_targets = ["PlayerUI", "UILayer", "Interface", "HUD"]
	
	for target_name in ui_targets:
		var ui_node = user.get_node_or_null(target_name)
		if ui_node:
			ui_node.add_child(ui_instance)
			return true
	
	# Look for CanvasLayer in user
	var canvas_layer = user.get_node_or_null("CanvasLayer")
	if canvas_layer:
		canvas_layer.add_child(ui_instance)
		return true
	
	# Look for UI-related nodes in user's parent
	if user.get_parent():
		for target_name in ui_targets:
			var ui_node = user.get_parent().get_node_or_null(target_name)
			if ui_node:
				ui_node.add_child(ui_instance)
				return true
	
	return false

func _try_add_to_canvas_layer(ui_instance) -> bool:
	"""Try to add UI to existing CanvasLayer in scene"""
	
	var scene_root = get_tree().current_scene
	if not scene_root:
		return false
	
	# Look for existing CanvasLayers
	var canvas_layers = []
	_find_canvas_layers_recursive(scene_root, canvas_layers)
	
	# Prefer CanvasLayers with UI-related names
	var preferred_names = ["UI", "Interface", "HUD", "Overlay"]
	
	for layer in canvas_layers:
		for preferred in preferred_names:
			if preferred.to_lower() in layer.name.to_lower():
				layer.add_child(ui_instance)
				return true
	
	# Use any CanvasLayer if available
	if canvas_layers.size() > 0:
		canvas_layers[0].add_child(ui_instance)
		return true
	
	return false

func _find_canvas_layers_recursive(node: Node, canvas_layers: Array):
	"""Recursively find all CanvasLayers in the scene"""
	if node is CanvasLayer:
		canvas_layers.append(node)
	
	for child in node.get_children():
		_find_canvas_layers_recursive(child, canvas_layers)

func _create_canvas_layer_for_ui(ui_instance) -> bool:
	"""Create a new CanvasLayer for the UI"""
	var scene_root = get_tree().current_scene
	if not scene_root:
		return false
	
	# Create a new CanvasLayer
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "HealthAnalyzerUI_Layer"
	canvas_layer.layer = 100  # High layer to ensure it's on top
	
	# Add CanvasLayer to scene
	scene_root.add_child(canvas_layer)
	
	# Add UI to CanvasLayer
	canvas_layer.add_child(ui_instance)
	
	return true

func use_on_self(user):
	print("HealthAnalyzer: Self-scan by ", user.name if user else "unknown user")
	return use_on(user, user)

func get_target_health_system(target):
	if not target:
		return null
	
	# Try multiple ways to get health system
	var health_system = target.get_node_or_null("HealthSystem")
	if health_system:
		return health_system
	
	# Try through HealthConnector
	var health_connector = target.get_node_or_null("HealthConnector")
	if health_connector and health_connector.health_system:
		return health_connector.health_system
	
	# Try as direct property
	if "health_system" in target:
		return target.health_system
	
	# Try through GridMovementController (legacy support)
	var grid_controller = target.get_node_or_null("GridMovementController")
	if grid_controller and grid_controller.health_system:
		return grid_controller.health_system
	
	return null

func get_target_name(target) -> String:
	if "entity_name" in target and target.entity_name != "":
		return target.entity_name
	elif "name" in target:
		return target.name
	else:
		return "Unknown Subject"

func both_have_position(obj1, obj2) -> bool:
	var obj1_has_pos = obj1.has_method("global_position") or "global_position" in obj1
	var obj2_has_pos = obj2.has_method("global_position") or "global_position" in obj2
	return obj1_has_pos and obj2_has_pos

func show_message_to_user(user, message: String):
	if not user:
		print("HealthAnalyzer: " + message)
		return
	
	# Try multiple ways to show message
	if user.has_method("display_message"):
		user.display_message(message)
	elif user.has_method("show_message"):
		user.show_message(message)
	elif user.get_node_or_null("SensorySystem"):
		user.get_node("SensorySystem").display_message(message)
	else:
		print("HealthAnalyzer message for ", user.name, ": ", message)

func play_error_sound():
	var error_sound = preload("res://Sound/machines/Error.wav")
	if error_sound:
		play_audio(error_sound)
	else:
		# Fallback to generic error sound
		play_audio(preload("res://Sound/machines/buzz-sigh.ogg"))

func _on_ui_closed():
	if current_ui_instance:
		# Clean up the CanvasLayer if we created one
		var parent = current_ui_instance.get_parent()
		if parent and parent.name == "HealthAnalyzerUI_Layer":
			parent.queue_free()  # This will also free the UI
		else:
			current_ui_instance.queue_free()
		
		current_ui_instance = null

func _exit_tree():
	if current_ui_instance:
		# Clean up properly
		var parent = current_ui_instance.get_parent()
		if parent and parent.name == "HealthAnalyzerUI_Layer":
			parent.queue_free()
		else:
			current_ui_instance.queue_free()
		current_ui_instance = null
