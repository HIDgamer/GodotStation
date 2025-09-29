extends Node
class_name SkillComponent

const SKILL_CQC = "cqc"
const SKILL_MELEE_WEAPONS = "melee_weapons" 
const SKILL_FIREARMS = "firearms"
const SKILL_SPEC_WEAPONS = "spec_weapons"
const SKILL_ENDURANCE = "endurance"
const SKILL_ENGINEER = "engineer"
const SKILL_CONSTRUCTION = "construction"
const SKILL_LEADERSHIP = "leadership"
const SKILL_OVERWATCH = "overwatch"
const SKILL_MEDICAL = "medical"
const SKILL_SURGERY = "surgery"
const SKILL_RESEARCH = "research"
const SKILL_ANTAG = "antag"
const SKILL_PILOT = "pilot"
const SKILL_NAVIGATIONS = "navigations"
const SKILL_POLICE = "police"
const SKILL_POWERLOADER = "powerloader"
const SKILL_VEHICLES = "vehicles"
const SKILL_JTAC = "jtac"
const SKILL_EXECUTION = "execution"
const SKILL_INTEL = "intel"
const SKILL_DOMESTIC = "domestic"
const SKILL_FIREMAN = "fireman"

const SKILL_LEVEL_NONE = 0
const SKILL_LEVEL_NOVICE = 1
const SKILL_LEVEL_TRAINED = 2
const SKILL_LEVEL_SKILLED = 3
const SKILL_LEVEL_EXPERT = 4
const SKILL_LEVEL_MASTER = 5

const SKILL_DEFAULTS = {
	SKILL_CQC: SKILL_LEVEL_NOVICE,
	SKILL_MELEE_WEAPONS: SKILL_LEVEL_NOVICE,
	SKILL_FIREARMS: SKILL_LEVEL_TRAINED,
	SKILL_SPEC_WEAPONS: SKILL_LEVEL_NONE,
	SKILL_ENDURANCE: SKILL_LEVEL_NOVICE,
	SKILL_ENGINEER: SKILL_LEVEL_NONE,
	SKILL_CONSTRUCTION: SKILL_LEVEL_NONE,
	SKILL_LEADERSHIP: SKILL_LEVEL_NOVICE,
	SKILL_OVERWATCH: SKILL_LEVEL_NONE,
	SKILL_MEDICAL: SKILL_LEVEL_NONE,
	SKILL_SURGERY: SKILL_LEVEL_NONE,
	SKILL_RESEARCH: SKILL_LEVEL_NONE,
	SKILL_ANTAG: SKILL_LEVEL_NONE,
	SKILL_PILOT: SKILL_LEVEL_NONE,
	SKILL_NAVIGATIONS: SKILL_LEVEL_NONE,
	SKILL_POLICE: SKILL_LEVEL_NONE,
	SKILL_POWERLOADER: SKILL_LEVEL_NONE,
	SKILL_VEHICLES: SKILL_LEVEL_NONE,
	SKILL_JTAC: SKILL_LEVEL_NOVICE,
	SKILL_EXECUTION: SKILL_LEVEL_NONE,
	SKILL_INTEL: SKILL_LEVEL_NOVICE,
	SKILL_DOMESTIC: SKILL_LEVEL_NONE,
	SKILL_FIREMAN: SKILL_LEVEL_NONE
}

const SKILL_MAX_LEVELS = {
	SKILL_CQC: 4,
	SKILL_MELEE_WEAPONS: 4,
	SKILL_FIREARMS: 5,
	SKILL_SPEC_WEAPONS: 4,
	SKILL_ENDURANCE: 3,
	SKILL_ENGINEER: 4,
	SKILL_CONSTRUCTION: 4,
	SKILL_LEADERSHIP: 4,
	SKILL_OVERWATCH: 3,
	SKILL_MEDICAL: 4,
	SKILL_SURGERY: 4,
	SKILL_RESEARCH: 3,
	SKILL_ANTAG: 3,
	SKILL_PILOT: 3,
	SKILL_NAVIGATIONS: 3,
	SKILL_POLICE: 3,
	SKILL_POWERLOADER: 3,
	SKILL_VEHICLES: 3,
	SKILL_JTAC: 3,
	SKILL_EXECUTION: 3,
	SKILL_INTEL: 3,
	SKILL_DOMESTIC: 3,
	SKILL_FIREMAN: 3
}

const SKILL_NAMES = {
	SKILL_CQC: "CQC",
	SKILL_MELEE_WEAPONS: "Melee Weapons",
	SKILL_FIREARMS: "Firearms",
	SKILL_SPEC_WEAPONS: "Specialist Weapons", 
	SKILL_ENDURANCE: "Endurance",
	SKILL_ENGINEER: "Engineering",
	SKILL_CONSTRUCTION: "Construction",
	SKILL_LEADERSHIP: "Leadership",
	SKILL_OVERWATCH: "Overwatch",
	SKILL_MEDICAL: "Medical",
	SKILL_SURGERY: "Surgery",
	SKILL_RESEARCH: "Research",
	SKILL_ANTAG: "Illegal Technology",
	SKILL_PILOT: "Pilot",
	SKILL_NAVIGATIONS: "Navigation",
	SKILL_POLICE: "Police",
	SKILL_POWERLOADER: "Powerloader",
	SKILL_VEHICLES: "Vehicles",
	SKILL_JTAC: "JTAC",
	SKILL_EXECUTION: "Execution",
	SKILL_INTEL: "Intel",
	SKILL_DOMESTIC: "Domestic",
	SKILL_FIREMAN: "Fireman Carrying"
}

const SKILLSET_CIVILIAN = {
	SKILL_CQC: SKILL_LEVEL_NONE,
	SKILL_MELEE_WEAPONS: SKILL_LEVEL_NOVICE,
	SKILL_FIREARMS: SKILL_LEVEL_NOVICE,
	SKILL_SPEC_WEAPONS: SKILL_LEVEL_NONE,
	SKILL_ENDURANCE: SKILL_LEVEL_NOVICE,
	SKILL_ENGINEER: SKILL_LEVEL_NONE,
	SKILL_CONSTRUCTION: SKILL_LEVEL_NOVICE,
	SKILL_LEADERSHIP: SKILL_LEVEL_NONE,
	SKILL_OVERWATCH: SKILL_LEVEL_NONE,
	SKILL_MEDICAL: SKILL_LEVEL_NOVICE,
	SKILL_SURGERY: SKILL_LEVEL_NONE,
	SKILL_RESEARCH: SKILL_LEVEL_NONE,
	SKILL_ANTAG: SKILL_LEVEL_NONE,
	SKILL_PILOT: SKILL_LEVEL_NONE,
	SKILL_NAVIGATIONS: SKILL_LEVEL_NONE,
	SKILL_POLICE: SKILL_LEVEL_NONE,
	SKILL_POWERLOADER: SKILL_LEVEL_NONE,
	SKILL_VEHICLES: SKILL_LEVEL_NONE,
	SKILL_JTAC: SKILL_LEVEL_NONE,
	SKILL_EXECUTION: SKILL_LEVEL_NONE,
	SKILL_INTEL: SKILL_LEVEL_NONE,
	SKILL_DOMESTIC: SKILL_LEVEL_TRAINED,
	SKILL_FIREMAN: SKILL_LEVEL_NONE
}

const SKILLSET_MARINE = {
	SKILL_CQC: SKILL_LEVEL_TRAINED,
	SKILL_MELEE_WEAPONS: SKILL_LEVEL_TRAINED,
	SKILL_FIREARMS: SKILL_LEVEL_SKILLED,
	SKILL_SPEC_WEAPONS: SKILL_LEVEL_NOVICE,
	SKILL_ENDURANCE: SKILL_LEVEL_TRAINED,
	SKILL_ENGINEER: SKILL_LEVEL_NOVICE,
	SKILL_CONSTRUCTION: SKILL_LEVEL_NOVICE,
	SKILL_LEADERSHIP: SKILL_LEVEL_NOVICE,
	SKILL_MEDICAL: SKILL_LEVEL_NOVICE,
	SKILL_FIREMAN: SKILL_LEVEL_TRAINED,
	SKILL_JTAC: SKILL_LEVEL_NOVICE
}

const SKILLSET_ENGINEER = {
	SKILL_CQC: SKILL_LEVEL_NOVICE,
	SKILL_FIREARMS: SKILL_LEVEL_TRAINED,
	SKILL_ENDURANCE: SKILL_LEVEL_TRAINED,
	SKILL_ENGINEER: SKILL_LEVEL_EXPERT,
	SKILL_CONSTRUCTION: SKILL_LEVEL_EXPERT,
	SKILL_POWERLOADER: SKILL_LEVEL_TRAINED,
	SKILL_VEHICLES: SKILL_LEVEL_TRAINED
}

const SKILLSET_MEDIC = {
	SKILL_CQC: SKILL_LEVEL_NOVICE,
	SKILL_FIREARMS: SKILL_LEVEL_TRAINED,
	SKILL_ENDURANCE: SKILL_LEVEL_TRAINED,
	SKILL_MEDICAL: SKILL_LEVEL_EXPERT,
	SKILL_SURGERY: SKILL_LEVEL_SKILLED,
	SKILL_FIREMAN: SKILL_LEVEL_SKILLED
}

const SKILLSET_OFFICER = {
	SKILL_CQC: SKILL_LEVEL_SKILLED,
	SKILL_MELEE_WEAPONS: SKILL_LEVEL_SKILLED,
	SKILL_FIREARMS: SKILL_LEVEL_EXPERT,
	SKILL_ENDURANCE: SKILL_LEVEL_SKILLED,
	SKILL_LEADERSHIP: SKILL_LEVEL_EXPERT,
	SKILL_OVERWATCH: SKILL_LEVEL_TRAINED,
	SKILL_JTAC: SKILL_LEVEL_TRAINED,
	SKILL_INTEL: SKILL_LEVEL_TRAINED
}

signal skill_changed(skill_name: String, old_level: int, new_level: int)
signal skillset_changed(skillset_name: String)
signal skill_check_failed(skill_name: String, required_level: int, current_level: int)
signal skill_check_passed(skill_name: String, required_level: int, current_level: int)

var controller: Node = null
var sensory_system: Node = null

@export var skills: Dictionary = {}
@export var skillset_name: String = "civilian"
@export var allow_skill_gain: bool = true
@export var allow_skill_loss: bool = false

var is_local_player: bool = false
var peer_id: int = 1

func initialize(init_data: Dictionary):
	controller = init_data.get("controller")
	sensory_system = init_data.get("sensory_system")
	is_local_player = init_data.get("is_local_player", false)
	peer_id = init_data.get("peer_id", 1)
	
	set_multiplayer_authority(peer_id)
	
	if skills.is_empty():
		apply_skillset(skillset_name)

func get_skill_level(skill_name: String) -> int:
	if not skills.has(skill_name):
		return SKILL_DEFAULTS.get(skill_name, SKILL_LEVEL_NONE)
	return skills[skill_name]

func set_skill_level(skill_name: String, new_level: int, force: bool = false) -> bool:
	if not is_multiplayer_authority() and not force:
		return false
	
	if not is_valid_skill(skill_name):
		return false
	
	var old_level = get_skill_level(skill_name)
	var max_level = SKILL_MAX_LEVELS.get(skill_name, SKILL_LEVEL_MASTER)
	
	new_level = clamp(new_level, SKILL_LEVEL_NONE, max_level)
	
	if not force:
		if new_level > old_level and not allow_skill_gain:
			return false
		if new_level < old_level and not allow_skill_loss:
			return false
	
	if old_level == new_level:
		return true
	
	skills[skill_name] = new_level
	
	_handle_skill_change_effects(skill_name, old_level, new_level)
	
	emit_signal("skill_changed", skill_name, old_level, new_level)
	
	if is_multiplayer_authority():
		sync_skill_change.rpc(skill_name, new_level)
	
	return true

func increment_skill(skill_name: String, increment: int = 1, cap: int = -1) -> bool:
	if not allow_skill_gain or not is_multiplayer_authority():
		return false
	
	var current_level = get_skill_level(skill_name)
	var max_level = SKILL_MAX_LEVELS.get(skill_name, SKILL_LEVEL_MASTER)
	
	if cap > 0:
		max_level = min(max_level, cap)
	
	if current_level >= max_level:
		return false
	
	var new_level = min(current_level + increment, max_level)
	return set_skill_level(skill_name, new_level)

func decrement_skill(skill_name: String, decrement: int = 1) -> bool:
	if not allow_skill_loss or not is_multiplayer_authority():
		return false
	
	var current_level = get_skill_level(skill_name)
	var new_level = max(current_level - decrement, SKILL_LEVEL_NONE)
	return set_skill_level(skill_name, new_level)

func is_skilled(skill_name: String, required_level: int, is_explicit: bool = false) -> bool:
	var current_level = get_skill_level(skill_name)
	
	var result = false
	if is_explicit:
		result = (current_level == required_level)
	else:
		result = (current_level >= required_level)
	
	if result:
		emit_signal("skill_check_passed", skill_name, required_level, current_level)
	else:
		emit_signal("skill_check_failed", skill_name, required_level, current_level)
	
	return result

func skillcheck(skill_name: String, required_level: int, show_message: bool = true) -> bool:
	var result = is_skilled(skill_name, required_level)
	
	if not result and show_message:
		var skill_display_name = SKILL_NAMES.get(skill_name, skill_name)
		var level_name = get_skill_level_name(required_level)
		show_skill_message("You need " + level_name + " " + skill_display_name + " to do that.")
	
	return result

func skillcheck_positive(skill_name: String, required_level: int, success_message: String = "") -> bool:
	var result = skillcheck(skill_name, required_level, true)
	
	if result and success_message != "":
		show_skill_message(success_message)
	
	return result

func apply_skillset(skillset_name_or_data, force: bool = false):
	if not is_multiplayer_authority() and not force:
		return false
	
	var skillset_data: Dictionary
	
	if skillset_name_or_data is String:
		skillset_data = get_predefined_skillset(skillset_name_or_data)
		skillset_name = skillset_name_or_data
	elif skillset_name_or_data is Dictionary:
		skillset_data = skillset_name_or_data
		skillset_name = "custom"
	else:
		return false
	
	if skillset_data.is_empty():
		return false
	
	for skill_name in skillset_data:
		set_skill_level(skill_name, skillset_data[skill_name], force)
	
	for skill_name in SKILL_DEFAULTS:
		if not skills.has(skill_name):
			set_skill_level(skill_name, SKILL_DEFAULTS[skill_name], force)
	
	emit_signal("skillset_changed", skillset_name)
	
	if is_multiplayer_authority():
		sync_skillset_change.rpc(skillset_name, skills)
	
	return true

func get_predefined_skillset(skillset_name: String) -> Dictionary:
	match skillset_name.to_lower():
		"civilian":
			return SKILLSET_CIVILIAN
		"marine":
			return SKILLSET_MARINE.duplicate().merged(SKILLSET_CIVILIAN)
		"engineer":
			return SKILLSET_ENGINEER.duplicate().merged(SKILLSET_MARINE).merged(SKILLSET_CIVILIAN)
		"medic":
			return SKILLSET_MEDIC.duplicate().merged(SKILLSET_MARINE).merged(SKILLSET_CIVILIAN)
		"officer":
			return SKILLSET_OFFICER.duplicate().merged(SKILLSET_MARINE).merged(SKILLSET_CIVILIAN)
		_:
			return SKILLSET_CIVILIAN

func get_skillset_display_name(skillset_name: String) -> String:
	match skillset_name.to_lower():
		"civilian":
			return "Civilian"
		"marine":
			return "Marine"
		"engineer":
			return "Combat Engineer"
		"medic":
			return "Combat Medic"
		"officer":
			return "Officer"
		_:
			return skillset_name.capitalize()

func can_use_medical_items() -> bool:
	return is_skilled(SKILL_MEDICAL, SKILL_LEVEL_NOVICE)

func can_perform_surgery() -> bool:
	return is_skilled(SKILL_SURGERY, SKILL_LEVEL_NOVICE)

func can_use_advanced_medical() -> bool:
	return is_skilled(SKILL_MEDICAL, SKILL_LEVEL_TRAINED)

func can_fireman_carry() -> bool:
	return is_skilled(SKILL_FIREMAN, SKILL_LEVEL_NOVICE)

func can_use_firearms() -> bool:
	return is_skilled(SKILL_FIREARMS, SKILL_LEVEL_TRAINED)

func can_use_specialist_weapons() -> bool:
	return is_skilled(SKILL_SPEC_WEAPONS, SKILL_LEVEL_NOVICE)

func can_pilot_vehicles() -> bool:
	return is_skilled(SKILL_PILOT, SKILL_LEVEL_NOVICE)

func can_operate_powerloader() -> bool:
	return is_skilled(SKILL_POWERLOADER, SKILL_LEVEL_NOVICE)

func can_do_engineering() -> bool:
	return is_skilled(SKILL_ENGINEER, SKILL_LEVEL_NOVICE)

func can_do_construction() -> bool:
	return is_skilled(SKILL_CONSTRUCTION, SKILL_LEVEL_NOVICE)

func can_lead_others() -> bool:
	return is_skilled(SKILL_LEADERSHIP, SKILL_LEVEL_TRAINED)

func get_melee_skill_modifier() -> float:
	var skill_level = get_skill_level(SKILL_MELEE_WEAPONS)
	return 1.0 + (skill_level * 0.15)

func get_firearms_skill_modifier() -> float:
	var skill_level = get_skill_level(SKILL_FIREARMS)
	return 1.0 + (skill_level * 0.1)

func get_medical_speed_modifier() -> float:
	var skill_level = get_skill_level(SKILL_MEDICAL)
	return 1.0 + (skill_level * 0.2)

func get_construction_speed_modifier() -> float:
	var skill_level = get_skill_level(SKILL_CONSTRUCTION)
	return 1.0 + (skill_level * 0.25)

@rpc("any_peer", "call_local", "reliable")
func sync_skill_change(skill_name: String, new_level: int):
	if is_multiplayer_authority():
		return
	
	var old_level = get_skill_level(skill_name)
	skills[skill_name] = new_level
	_handle_skill_change_effects(skill_name, old_level, new_level)
	emit_signal("skill_changed", skill_name, old_level, new_level)

@rpc("any_peer", "call_local", "reliable")  
func sync_skillset_change(new_skillset_name: String, new_skills: Dictionary):
	if is_multiplayer_authority():
		return
	
	skillset_name = new_skillset_name
	skills = new_skills.duplicate()
	emit_signal("skillset_changed", skillset_name)

@rpc("authority", "call_local", "reliable")
func request_skill_sync():
	if is_multiplayer_authority():
		var requester_id = multiplayer.get_remote_sender_id()
		sync_full_skills.rpc_id(requester_id, skills, skillset_name)

@rpc("any_peer", "call_local", "reliable")
func sync_full_skills(skill_data: Dictionary, skillset: String):
	if is_multiplayer_authority():
		return
	
	skills = skill_data.duplicate()
	skillset_name = skillset

func is_valid_skill(skill_name: String) -> bool:
	return SKILL_DEFAULTS.has(skill_name)

func get_skill_level_name(level: int) -> String:
	match level:
		SKILL_LEVEL_NONE:
			return "No"
		SKILL_LEVEL_NOVICE:
			return "Novice"
		SKILL_LEVEL_TRAINED:
			return "Trained"
		SKILL_LEVEL_SKILLED:
			return "Skilled"
		SKILL_LEVEL_EXPERT:
			return "Expert"
		SKILL_LEVEL_MASTER:
			return "Master"
		_:
			return "Unknown"

func get_skill_display_name(skill_name: String) -> String:
	return SKILL_NAMES.get(skill_name, skill_name.capitalize())

func get_all_skills() -> Dictionary:
	var all_skills = {}
	for skill_name in SKILL_DEFAULTS:
		all_skills[skill_name] = get_skill_level(skill_name)
	return all_skills

func get_skills_above_level(min_level: int) -> Array:
	var skilled_skills = []
	for skill_name in SKILL_DEFAULTS:
		if get_skill_level(skill_name) >= min_level:
			skilled_skills.append(skill_name)
	return skilled_skills

func show_skill_message(message: String):
	if sensory_system and is_local_player:
		if sensory_system.has_method("display_message"):
			sensory_system.display_message("[color=#FFAA00]" + message + "[/color]")
		elif sensory_system.has_method("add_message"):
			sensory_system.add_message(message)

func _handle_skill_change_effects(skill_name: String, old_level: int, new_level: int):
	match skill_name:
		SKILL_LEADERSHIP:
			_handle_leadership_change(old_level, new_level)
		SKILL_SURGERY:
			_handle_surgery_change(old_level, new_level)

func _handle_leadership_change(old_level: int, new_level: int):
	if not controller:
		return
	
	var can_lead_now = new_level >= SKILL_LEVEL_TRAINED
	var could_lead_before = old_level >= SKILL_LEVEL_TRAINED
	
	if can_lead_now and not could_lead_before:
		if controller.has_method("add_trait"):
			controller.add_trait("TRAIT_LEADERSHIP")
		show_skill_message("You feel more confident in your leadership abilities.")
	elif not can_lead_now and could_lead_before:
		if controller.has_method("remove_trait"):
			controller.remove_trait("TRAIT_LEADERSHIP")
		show_skill_message("You feel less confident about leading others.")

func _handle_surgery_change(old_level: int, new_level: int):
	if not controller:
		return
	
	var can_surgery_now = new_level >= SKILL_LEVEL_NOVICE
	var could_surgery_before = old_level >= SKILL_LEVEL_NOVICE
	
	if can_surgery_now and not could_surgery_before:
		show_skill_message("You feel competent enough to attempt basic surgical procedures.")
	elif not can_surgery_now and could_surgery_before:
		show_skill_message("You no longer feel confident about performing surgery.")
