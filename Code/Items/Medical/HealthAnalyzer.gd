extends MedicalItem
class_name HealthAnalyzer

var health_analyzer_ui_scene = preload("res://Scenes/UI/Ingame/HealthAnalyzerUI.tscn")
var current_ui_instance = null
var peer_id: int = 1

func _ready():
	super._ready()
	
	item_name = "Health Analyzer"
	description = "A hand-held body scanner capable of determining a patient's health status."
	use_time = 2.0
	use_sound = preload("res://Sound/items/healthanalyzer.ogg")
	
	if get_parent() and get_parent().has_meta("peer_id"):
		peer_id = get_parent().get_meta("peer_id")
		set_multiplayer_authority(peer_id)

func should_be_consumed() -> bool:
	return false

func use(user):
	var target = get_target_for_use(user)
	if target:
		return use_on(user, target)
	return false

func get_target_for_use(user):
	if user.has_method("get_current_target"):
		var target = user.get_current_target()
		if target and get_target_health_system(target):
			return target
	
	var nearby_targets = get_nearby_medical_targets(user)
	if nearby_targets.size() > 0:
		return nearby_targets[0]
	
	return user

func get_nearby_medical_targets(user) -> Array:
	var targets = []
	var world = user.get_parent()
	if not world:
		return targets
	
	for child in world.get_children():
		if child == user:
			continue
		if not get_target_health_system(child):
			continue
		if user.global_position.distance_to(child.global_position) <= 64:
			targets.append(child)
	
	targets.sort_custom(func(a, b): return user.global_position.distance_to(a.global_position) < user.global_position.distance_to(b.global_position))
	return targets

func use_on(user, target, targeted_limb = ""):
	if not target:
		show_message_to_user(user, "No valid target to scan.")
		return false
	
	var health_system = get_target_health_system(target)
	if not health_system:
		show_message_to_user(user, "Unable to detect biological signatures.")
		play_error_sound()
		return false
	
	if user and target and both_have_position(user, target):
		var distance = user.global_position.distance_to(target.global_position)
		if distance > 64:
			show_message_to_user(user, "Target is too far away for accurate scanning.")
			return false
	
	if use_sound:
		play_audio(use_sound)
	
	show_message_to_user(user, "Scanning " + get_target_name(target) + "...")
	
	var detail_level = determine_detail_level(user)
	var scan_data = generate_scan_data(target, detail_level, targeted_limb)
	
	sync_scan_usage.rpc(user.get_path(), target.get_path(), targeted_limb, scan_data)
	_show_scan_results_for_user(user, scan_data, targeted_limb)
	
	return true

func determine_detail_level(user) -> String:
	if not user or not user.has_method("get_skill_level"):
		return "standard"
	
	var medical_skill = user.get_skill_level("medical")
	if medical_skill >= 3:
		return "medical"
	elif medical_skill >= 2:
		return "full"
	else:
		return "standard"

func generate_scan_data(target, detail_level: String, targeted_limb: String = "") -> Dictionary:
	var health_system = get_target_health_system(target)
	var reagent_system = get_target_reagent_system(target)
	
	var scan_data = {
		"patient_name": get_target_name(target),
		"dead": health_system.is_dead,
		"health": health_system.health,
		"max_health": health_system.max_health,
		"vital_signs": get_vital_signs_data(health_system),
		"damage": get_damage_data(health_system),
		"blood": get_blood_data(health_system),
		"limbs": get_limb_data(health_system, detail_level, targeted_limb),
		"chemicals": get_chemical_data(reagent_system, health_system, detail_level),
		"pain": get_pain_data(health_system, detail_level),
		"advice": generate_medical_advice(health_system, reagent_system),
		"detail_level": detail_level
	}
	
	return scan_data

func get_vital_signs_data(health_system) -> Dictionary:
	return {
		"pulse": health_system.pulse,
		"temperature": health_system.get_body_temperature(),
		"blood_pressure": health_system.get_blood_pressure(),
		"breathing_rate": health_system.breathing_rate,
		"consciousness": health_system.consciousness_level
	}

func get_damage_data(health_system) -> Dictionary:
	return {
		"brute": health_system.bruteloss,
		"burn": health_system.fireloss,
		"toxin": health_system.toxloss,
		"oxygen": health_system.oxyloss,
		"brain": health_system.brainloss,
		"clone": health_system.cloneloss,
		"stamina": health_system.staminaloss
	}

func get_blood_data(health_system) -> Dictionary:
	return {
		"volume": health_system.blood_volume,
		"max_volume": health_system.blood_volume_maximum,
		"type": health_system.blood_type,
		"bleeding": health_system.bleeding_rate > 0,
		"bleeding_rate": health_system.bleeding_rate
	}

func get_limb_data(health_system, detail_level: String, targeted_limb: String = "") -> Array:
	var limb_data = []
	var limbs_to_scan = []
	
	if targeted_limb != "" and health_system.limbs.has(targeted_limb):
		limbs_to_scan = [targeted_limb]
	else:
		limbs_to_scan = health_system.limbs.keys()
	
	for limb_name in limbs_to_scan:
		var limb = health_system.limbs[limb_name]
		var limb_info = {
			"name": limb_name.replace("_", " ").capitalize(),
			"internal_name": limb_name,
			"attached": limb.attached,
			"brute": limb.brute_damage,
			"burn": limb.burn_damage,
			"bleeding": limb.is_bleeding,
			"bandaged": limb.is_bandaged,
			"fractured": limb.is_fractured,
			"fracture_severity": limb.fracture_severity if limb.is_fractured else 0,
			"splinted": limb.is_splinted,
			"infected": limb.is_infected,
			"status": limb.status,
			"wounds": limb.wounds.size() if "wounds" in limb else 0
		}
		
		if detail_level == "medical":
			limb_info["detailed_wounds"] = limb.wounds if "wounds" in limb else []
			limb_info["scars"] = limb.scars if "scars" in limb else []
		
		limb_data.append(limb_info)
	
	return limb_data

func get_chemical_data(reagent_system, health_system, detail_level: String) -> Dictionary:
	var chemical_data = {
		"has_chemicals": false,
		"reagents": [],
		"total_volume": 0.0,
		"dangerous_detected": false
	}
	
	if not reagent_system:
		return chemical_data
	
	var reagent_container = reagent_system.reagent_container
	if not reagent_container or reagent_container.total_volume <= 0:
		return chemical_data
	
	chemical_data.has_chemicals = true
	chemical_data.total_volume = reagent_container.total_volume
	
	for reagent in reagent_container.reagent_list:
		var reagent_info = {
			"name": reagent.name,
			"amount": reagent.volume,
			"overdose": reagent.overdose_threshold > 0 and reagent.volume > reagent.overdose_threshold,
			"dangerous": reagent.is_harmful(),
			"beneficial": reagent.is_beneficial(),
			"color": reagent.get_color_string()
		}
		
		if detail_level == "medical":
			reagent_info["overdose_threshold"] = reagent.overdose_threshold
			reagent_info["description"] = reagent.description
			reagent_info["effects"] = reagent.effects.keys()
		
		if reagent_info.dangerous:
			chemical_data.dangerous_detected = true
		
		chemical_data.reagents.append(reagent_info)
	
	chemical_data.reagents.sort_custom(func(a, b): return a.amount > b.amount)
	return chemical_data

func get_pain_data(health_system, detail_level: String) -> Dictionary:
	var pain_data = {
		"level": health_system.pain_level,
		"shock": health_system.shock_level,
		"status": get_pain_status_text(health_system.pain_level)
	}
	
	if detail_level == "medical":
		pain_data["pain_effects"] = get_pain_effects(health_system.pain_level)
		pain_data["consciousness_level"] = health_system.consciousness_level
	
	return pain_data

func get_pain_status_text(pain_level: float) -> String:
	if pain_level <= 0:
		return "None"
	elif pain_level <= 15:
		return "Mild"
	elif pain_level <= 35:
		return "Moderate"
	elif pain_level <= 60:
		return "Severe"
	elif pain_level <= 85:
		return "Extreme"
	else:
		return "Unbearable"

func get_pain_effects(pain_level: float) -> Array:
	var effects = []
	
	if pain_level >= 25:
		effects.append("Movement impaired")
	if pain_level >= 60:
		effects.append("Risk of stunning")
	if pain_level >= 85:
		effects.append("Risk of unconsciousness")
	
	return effects

func generate_medical_advice(health_system, reagent_system) -> Array:
	var advice = []
	
	if health_system.is_dead:
		advice.append({
			"text": "Patient is deceased. Consider defibrillation or advanced revival techniques.",
			"color": "red",
			"icon": "warning",
			"priority": 10
		})
	elif health_system.current_state == health_system.HealthState.CRITICAL:
		advice.append({
			"text": "Patient in critical condition. Immediate medical attention required.",
			"color": "red",
			"icon": "warning",
			"priority": 9
		})
	
	var blood_percent = (health_system.blood_volume / health_system.blood_volume_maximum) * 100.0
	if blood_percent < 60:
		advice.append({
			"text": "Severe blood loss detected. Blood transfusion recommended.",
			"color": "red",
			"icon": "blood",
			"priority": 8
		})
	elif blood_percent < 80:
		advice.append({
			"text": "Moderate blood loss. Monitor and consider iron supplements.",
			"color": "orange",
			"icon": "blood",
			"priority": 5
		})
	
	if health_system.bleeding_rate > 0:
		advice.append({
			"text": "Active bleeding detected. Apply bandages or sutures immediately.",
			"color": "red",
			"icon": "bleeding",
			"priority": 7
		})
	
	if health_system.pain_level > 60:
		advice.append({
			"text": "Severe pain levels. Administer painkillers to prevent shock.",
			"color": "orange",
			"icon": "warning",
			"priority": 6
		})
	
	var fractured_limbs = []
	for limb_name in health_system.limbs:
		var limb = health_system.limbs[limb_name]
		if limb.is_fractured and not limb.is_splinted:
			fractured_limbs.append(limb_name.replace("_", " ").capitalize())
	
	if fractured_limbs.size() > 0:
		advice.append({
			"text": "Fractures detected in: " + ", ".join(fractured_limbs) + ". Apply splints immediately.",
			"color": "orange",
			"icon": "bandage",
			"priority": 6
		})
	
	if health_system.bruteloss > 30:
		advice.append({
			"text": "Significant trauma damage. Treat with bicaridine or kelotane.",
			"color": "yellow",
			"icon": "bandage",
			"priority": 4
		})
	
	if health_system.fireloss > 30:
		advice.append({
			"text": "Severe burn damage detected. Apply kelotane and burn treatment.",
			"color": "orange",
			"icon": "fire",
			"priority": 4
		})
	
	if health_system.toxloss > 20:
		advice.append({
			"text": "Toxin contamination present. Administer anti-toxin immediately.",
			"color": "yellow",
			"icon": "poison",
			"priority": 5
		})
	
	if health_system.oxyloss > 20:
		advice.append({
			"text": "Oxygen deprivation detected. Provide ventilation or dexalin.",
			"color": "blue",
			"icon": "oxygen",
			"priority": 5
		})
	
	if reagent_system and reagent_system.reagent_container:
		var container = reagent_system.reagent_container
		var dangerous_chemicals = []
		var overdosed_chemicals = []
		
		for reagent in container.reagent_list:
			if reagent.is_harmful():
				dangerous_chemicals.append(reagent.name)
			if reagent.overdose_threshold > 0 and reagent.volume > reagent.overdose_threshold:
				overdosed_chemicals.append(reagent.name)
		
		if overdosed_chemicals.size() > 0:
			advice.append({
				"text": "Overdose detected: " + ", ".join(overdosed_chemicals) + ". Consider dialysis or purging agents.",
				"color": "red",
				"icon": "poison",
				"priority": 7
			})
		
		if dangerous_chemicals.size() > 0 and overdosed_chemicals.size() == 0:
			advice.append({
				"text": "Dangerous chemicals detected: " + ", ".join(dangerous_chemicals) + ". Monitor closely.",
				"color": "yellow",
				"icon": "poison",
				"priority": 3
			})
	
	var damaged_organs = []
	for organ_name in health_system.organs:
		var organ = health_system.organs[organ_name]
		if organ.is_failing:
			damaged_organs.append(organ_name)
	
	if damaged_organs.size() > 0:
		advice.append({
			"text": "Organ failure detected: " + ", ".join(damaged_organs) + ". Surgical intervention may be required.",
			"color": "red",
			"icon": "warning",
			"priority": 8
		})
	
	advice.sort_custom(func(a, b): return a.priority > b.priority)
	return advice

func _show_scan_results_for_user(user, scan_data: Dictionary, targeted_limb: String):
	if not user.has_meta("is_player") or not user.get_meta("is_player"):
		return
	
	var user_peer_id = user.get_meta("peer_id", 1)
	if user_peer_id != multiplayer.get_unique_id():
		return
	
	if current_ui_instance:
		current_ui_instance.queue_free()
	
	current_ui_instance = health_analyzer_ui_scene.instantiate()
	_add_ui_to_viewport(current_ui_instance, user)
	current_ui_instance.ui_closed.connect(_on_ui_closed)
	current_ui_instance.show_scan_results(scan_data)
	
	var scanner_message = "Health analysis complete."
	if targeted_limb and targeted_limb != "":
		scanner_message += " Focused scan on " + targeted_limb.replace("_", " ").capitalize() + "."
	
	show_message_to_user(user, scanner_message)

@rpc("any_peer", "call_local", "reliable")
func sync_scan_usage(user_path: String, target_path: String, targeted_limb: String, scan_data: Dictionary):
	var user = get_node_or_null(user_path)
	var target = get_node_or_null(target_path)
	
	if not user or not target:
		return
	
	if user.has_meta("is_player") and user.get_meta("is_player"):
		var user_peer_id = user.get_meta("peer_id", 1)
		if user_peer_id == multiplayer.get_unique_id():
			_show_scan_results_for_user(user, scan_data, targeted_limb)

func get_target_reagent_system(target):
	if not target:
		return null
	
	var reagent_system = target.get_node_or_null("ReagentSystem")
	if reagent_system:
		return reagent_system
	
	var bloodstream_reagents = target.get_node_or_null("BloodstreamReagents")
	if bloodstream_reagents:
		return bloodstream_reagents
	
	var body_chemistry = target.get_node_or_null("BodyChemicalSystem")
	if body_chemistry:
		return body_chemistry
	
	if "reagent_system" in target:
		return target.reagent_system
	
	return null

func _add_ui_to_viewport(ui_instance, user):
	if user and _try_add_to_user_ui_layer(ui_instance, user):
		return
	
	if _try_add_to_canvas_layer(ui_instance):
		return
	
	if _create_canvas_layer_for_ui(ui_instance):
		return
	
	var viewport = get_viewport()
	if viewport:
		viewport.add_child(ui_instance)

func _try_add_to_user_ui_layer(ui_instance, user) -> bool:
	var ui_targets = ["PlayerUI", "UILayer", "Interface", "HUD"]
	
	for target_name in ui_targets:
		var ui_node = user.get_node_or_null(target_name)
		if ui_node:
			ui_node.add_child(ui_instance)
			return true
	
	var canvas_layer = user.get_node_or_null("CanvasLayer")
	if canvas_layer:
		canvas_layer.add_child(ui_instance)
		return true
	
	if user.get_parent():
		for target_name in ui_targets:
			var ui_node = user.get_parent().get_node_or_null(target_name)
			if ui_node:
				ui_node.add_child(ui_instance)
				return true
	
	return false

func _try_add_to_canvas_layer(ui_instance) -> bool:
	var scene_root = get_tree().current_scene
	if not scene_root:
		return false
	
	var canvas_layers = []
	_find_canvas_layers_recursive(scene_root, canvas_layers)
	
	var preferred_names = ["UI", "Interface", "HUD", "Overlay"]
	
	for layer in canvas_layers:
		for preferred in preferred_names:
			if preferred.to_lower() in layer.name.to_lower():
				layer.add_child(ui_instance)
				return true
	
	if canvas_layers.size() > 0:
		canvas_layers[0].add_child(ui_instance)
		return true
	
	return false

func _find_canvas_layers_recursive(node: Node, canvas_layers: Array):
	if node is CanvasLayer:
		canvas_layers.append(node)
	
	for child in node.get_children():
		_find_canvas_layers_recursive(child, canvas_layers)

func _create_canvas_layer_for_ui(ui_instance) -> bool:
	var scene_root = get_tree().current_scene
	if not scene_root:
		return false
	
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "HealthAnalyzerUI_Layer"
	canvas_layer.layer = 100
	
	scene_root.add_child(canvas_layer)
	canvas_layer.add_child(ui_instance)
	return true

func use_on_self(user):
	return use_on(user, user)

func get_target_health_system(target):
	if not target:
		return null
	
	var health_system = target.get_node_or_null("HealthSystem")
	if health_system:
		return health_system
	
	var health_connector = target.get_node_or_null("HealthConnector")
	if health_connector and health_connector.health_system:
		return health_connector.health_system
	
	if "health_system" in target:
		return target.health_system
	
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
		return
	
	if user.has_method("display_message"):
		user.display_message(message)
	elif user.has_method("show_message"):
		user.show_message(message)
	elif user.get_node_or_null("SensorySystem"):
		user.get_node("SensorySystem").display_message(message)

func play_error_sound():
	var error_sound = preload("res://Sound/machines/Error.wav")
	if error_sound:
		play_audio(error_sound)
	else:
		play_audio(preload("res://Sound/machines/buzz-sigh.ogg"))

func _on_ui_closed():
	if current_ui_instance:
		var parent = current_ui_instance.get_parent()
		if parent and parent.name == "HealthAnalyzerUI_Layer":
			parent.queue_free()
		else:
			current_ui_instance.queue_free()
		current_ui_instance = null

func _exit_tree():
	if current_ui_instance:
		var parent = current_ui_instance.get_parent()
		if parent and parent.name == "HealthAnalyzerUI_Layer":
			parent.queue_free()
		else:
			current_ui_instance.queue_free()
		current_ui_instance = null
