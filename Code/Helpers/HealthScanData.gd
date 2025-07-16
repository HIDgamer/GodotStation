extends RefCounted
class_name HealthScanData

enum DetailLevel {
	BASIC,
	STANDARD, 
	FULL,
	MEDICAL
}

enum UIMode {
	CLASSIC,
	MINIMAL
}

var target_entity = null
var detail_level = DetailLevel.FULL
var ui_mode = UIMode.CLASSIC
var scan_time: float = 0.0

func _init(target = null):
	target_entity = target
	scan_time = Time.get_ticks_msec() / 1000.0

func get_scan_data() -> Dictionary:
	if not target_entity:
		return {}
	
	var data = {
		"patient_name": get_patient_name(),
		"dead": is_dead(),
		"health": get_health_value(),
		"max_health": get_max_health(),
		"vital_signs": get_vital_signs(),
		"damage": get_damage_data(),
		"blood": get_blood_data(),
		"chemicals": get_chemical_data(),
		"limbs": get_limb_data(),
		"status_effects": get_status_effects(),
		"diseases": get_diseases(),
		"advice": get_medical_advice(),
		"detail_level": detail_level,
		"ui_mode": ui_mode,
		"scan_timestamp": scan_time
	}
	
	return data

func get_patient_name() -> String:
	if "entity_name" in target_entity:
		return target_entity.entity_name
	elif "name" in target_entity:
		return target_entity.name
	return "Unknown Subject"

func is_dead() -> bool:
	var health_system = get_health_system()
	if health_system:
		return health_system.current_state == health_system.HealthState.DEAD
	return false

func get_health_value() -> float:
	var health_system = get_health_system()
	if health_system:
		return health_system.health
	return 100.0

func get_max_health() -> float:
	var health_system = get_health_system()
	if health_system:
		return health_system.max_health
	return 100.0

func get_vital_signs() -> Dictionary:
	var health_system = get_health_system()
	var vitals = {
		"pulse": 70,
		"temperature": 37.0,
		"blood_pressure": "120/80",
		"respiratory_rate": 16
	}
	
	if health_system:
		vitals.pulse = health_system.get_pulse()
		vitals.temperature = health_system.get_body_temperature()
		vitals.blood_pressure = health_system.get_blood_pressure()
		vitals.respiratory_rate = health_system.get_respiratory_rate()
	
	return vitals

func get_damage_data() -> Dictionary:
	var health_system = get_health_system()
	var damage = {
		"brute": 0.0,
		"burn": 0.0,
		"toxin": 0.0,
		"oxygen": 0.0,
		"clone": 0.0,
		"brain": 0.0,
		"stamina": 0.0
	}
	
	if health_system:
		damage.brute = health_system.bruteloss
		damage.burn = health_system.fireloss
		damage.toxin = health_system.toxloss
		damage.oxygen = health_system.oxyloss
		damage.clone = health_system.cloneloss
		damage.brain = health_system.brainloss
		damage.stamina = health_system.staminaloss
	
	return damage

func get_blood_data() -> Dictionary:
	var health_system = get_health_system()
	var blood = {
		"volume": 500,
		"max_volume": 560,
		"type": "O+",
		"bleeding": false,
		"bleeding_rate": 0.0
	}
	
	if health_system:
		blood.volume = health_system.blood_volume
		blood.max_volume = health_system.blood_volume_maximum
		blood.type = health_system.blood_type
		blood.bleeding = health_system.is_bleeding()
		blood.bleeding_rate = health_system.bleeding_rate
	
	return blood

func get_chemical_data() -> Dictionary:
	var health_system = get_health_system()
	var chemicals = {
		"has_chemicals": false,
		"has_unknown": false,
		"reagents": []
	}
	
	if health_system and health_system.has_method("get_reagents"):
		var reagents = health_system.get_reagents()
		chemicals.has_chemicals = reagents.size() > 0
		
		for reagent in reagents:
			var reagent_data = {
				"name": reagent.get("name", "Unknown"),
				"amount": reagent.get("amount", 0.0),
				"overdose": reagent.get("overdose", false),
				"dangerous": reagent.get("dangerous", false),
				"color": reagent.get("color", "#FFFFFF")
			}
			chemicals.reagents.append(reagent_data)
	
	return chemicals

func get_limb_data() -> Array:
	var health_system = get_health_system()
	var limbs = []
	
	if health_system and health_system.has_method("get_limb_data"):
		var limb_data = health_system.get_limb_data()
		
		for limb_name in limb_data:
			var limb = limb_data[limb_name]
			var limb_info = {
				"name": limb.get("display_name", limb_name),
				"brute": limb.get("brute_damage", 0.0),
				"burn": limb.get("burn_damage", 0.0),
				"missing": limb.get("missing", false),
				"broken": limb.get("broken", false),
				"bleeding": limb.get("bleeding", false),
				"bandaged": limb.get("bandaged", false),
				"status": limb.get("status", "")
			}
			limbs.append(limb_info)
	
	return limbs

func get_status_effects() -> Array:
	var health_system = get_health_system()
	var effects = []
	
	if health_system and health_system.has_method("get_status_effects"):
		effects = health_system.get_status_effects()
	
	return effects

func get_diseases() -> Array:
	var health_system = get_health_system()
	var diseases = []
	
	if health_system and health_system.has_method("get_diseases"):
		diseases = health_system.get_diseases()
	
	return diseases

func get_medical_advice() -> Array:
	var advice = []
	var damage_data = get_damage_data()
	var blood_data = get_blood_data()
	var health_percent = (get_health_value() / get_max_health()) * 100.0
	
	# Critical health advice
	if health_percent < 25:
		advice.append({
			"text": "CRITICAL: Patient requires immediate medical attention!",
			"icon": "warning",
			"color": "red",
			"priority": 10
		})
	
	# Damage-specific advice
	if damage_data.brute > 30:
		advice.append({
			"text": "Apply trauma kits or surgical treatment for severe lacerations.",
			"icon": "bandage",
			"color": "orange",
			"priority": 8
		})
	
	if damage_data.burn > 30:
		advice.append({
			"text": "Apply burn kits or skin grafts for thermal damage.",
			"icon": "fire",
			"color": "orange", 
			"priority": 8
		})
	
	if damage_data.toxin > 20:
		advice.append({
			"text": "Administer anti-toxin medication immediately.",
			"icon": "poison",
			"color": "green",
			"priority": 7
		})
	
	if damage_data.oxygen > 40:
		advice.append({
			"text": "Patient requires oxygen supplementation.",
			"icon": "oxygen",
			"color": "blue",
			"priority": 9
		})
	
	# Blood loss advice
	if blood_data.volume < 400:
		advice.append({
			"text": "Severe blood loss detected. Administer blood transfusion.",
			"icon": "blood",
			"color": "red",
			"priority": 9
		})
	elif blood_data.bleeding:
		advice.append({
			"text": "Patient is bleeding. Apply pressure and bandages.",
			"icon": "bleeding",
			"color": "red",
			"priority": 8
		})
	
	# Sort by priority
	advice.sort_custom(func(a, b): return a.priority > b.priority)
	
	return advice

func get_health_system():
	if not target_entity:
		return null
	
	# Try multiple ways to get health system
	var health_system = target_entity.get_node_or_null("HealthSystem")
	if health_system:
		return health_system
	
	# Try through HealthConnector
	var health_connector = target_entity.get_node_or_null("HealthConnector")
	if health_connector and health_connector.health_system:
		return health_connector.health_system
	
	# Try as direct property
	if "health_system" in target_entity:
		return target_entity.health_system
	
	return null
