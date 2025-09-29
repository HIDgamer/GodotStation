extends Node
class_name BodyTargetingComponent

#region EXPORTS AND CONFIGURATION
@export_group("Targeting Settings")
@export var default_zone: String = "chest"
@export var enable_precise_targeting: bool = true
@export var highlight_targeted_zones: bool = true

@export_group("Damage Modifiers")
@export var head_damage_multiplier: float = 1.5
@export var eyes_damage_multiplier: float = 2.0
@export var mouth_damage_multiplier: float = 1.3
@export var chest_damage_multiplier: float = 1.0
@export var groin_damage_multiplier: float = 1.8
@export var arm_damage_multiplier: float = 0.8
@export var hand_damage_multiplier: float = 0.6
@export var leg_damage_multiplier: float = 0.9
@export var foot_damage_multiplier: float = 0.7

@export_group("Hit Chance Modifiers")
@export var precise_zone_hit_modifier: float = 0.6
@export var general_zone_hit_modifier: float = 1.0

@export_group("Stun Chances")
@export var head_stun_chance: float = 0.3
@export var eyes_stun_chance: float = 0.5
@export var mouth_stun_chance: float = 0.2
@export var groin_stun_chance: float = 0.4
#endregion

#region CONSTANTS
# Body zones
const BODY_ZONE_HEAD = "head"
const BODY_ZONE_CHEST = "chest"
const BODY_ZONE_L_ARM = "l_arm"
const BODY_ZONE_R_ARM = "r_arm"
const BODY_ZONE_L_LEG = "l_leg"
const BODY_ZONE_R_LEG = "r_leg"
const BODY_ZONE_PRECISE_EYES = "eyes"
const BODY_ZONE_PRECISE_MOUTH = "mouth"
const BODY_ZONE_PRECISE_GROIN = "groin"
const BODY_ZONE_PRECISE_L_HAND = "l_hand"
const BODY_ZONE_PRECISE_R_HAND = "r_hand"
const BODY_ZONE_PRECISE_L_FOOT = "l_foot"
const BODY_ZONE_PRECISE_R_FOOT = "r_foot"
#endregion

#region SIGNALS
signal zone_selected_changed(new_zone: String)
signal target_zone_cycled(zone: String)
#endregion

#region PROPERTIES
# Core references
var controller: Node = null
var sprite_system = null

# Current selection
var zone_selected: String

# Zone groups for cycling
var body_zones_head: Array[String] = []
var body_zones_r_arm: Array[String] = []
var body_zones_l_arm: Array[String] = []
var body_zones_r_leg: Array[String] = []
var body_zones_l_leg: Array[String] = []
var body_zones_chest: Array[String] = []
var body_zones_groin: Array[String] = []

# All valid zones
var all_valid_zones: Array[String] = []

# Display name mapping
var zone_display_names: Dictionary = {}
var zone_icons: Dictionary = {}
#endregion

#region INITIALIZATION
func initialize(init_data: Dictionary):
	"""Initialize the body targeting component"""
	controller = init_data.get("controller")
	sprite_system = init_data.get("sprite_system")
	
	_setup_zone_groups()
	_setup_display_names()
	_setup_zone_icons()
	
	# Set default zone
	zone_selected = default_zone if default_zone in all_valid_zones else BODY_ZONE_CHEST

func _setup_zone_groups():
	"""Configure zone groups for cycling"""
	body_zones_head = [BODY_ZONE_HEAD]
	body_zones_chest = [BODY_ZONE_CHEST]
	body_zones_groin = [BODY_ZONE_PRECISE_GROIN]
	body_zones_r_arm = [BODY_ZONE_R_ARM]
	body_zones_l_arm = [BODY_ZONE_L_ARM]
	body_zones_r_leg = [BODY_ZONE_R_LEG]
	body_zones_l_leg = [BODY_ZONE_L_LEG]
	
	# Add precise targeting if enabled
	if enable_precise_targeting:
		body_zones_head.append_array([BODY_ZONE_PRECISE_EYES, BODY_ZONE_PRECISE_MOUTH])
		body_zones_r_arm.append(BODY_ZONE_PRECISE_R_HAND)
		body_zones_l_arm.append(BODY_ZONE_PRECISE_L_HAND)
		body_zones_r_leg.append(BODY_ZONE_PRECISE_R_FOOT)
		body_zones_l_leg.append(BODY_ZONE_PRECISE_L_FOOT)
	
	# Compile all valid zones
	all_valid_zones.clear()
	for zone_group in [body_zones_head, body_zones_chest, body_zones_groin,
					   body_zones_r_arm, body_zones_l_arm, 
					   body_zones_r_leg, body_zones_l_leg]:
		all_valid_zones.append_array(zone_group)

func _setup_display_names():
	"""Configure display names for zones"""
	zone_display_names = {
		BODY_ZONE_HEAD: "Head",
		BODY_ZONE_CHEST: "Chest",
		BODY_ZONE_L_ARM: "Left Arm",
		BODY_ZONE_R_ARM: "Right Arm",
		BODY_ZONE_L_LEG: "Left Leg",
		BODY_ZONE_R_LEG: "Right Leg",
		BODY_ZONE_PRECISE_EYES: "Eyes",
		BODY_ZONE_PRECISE_MOUTH: "Mouth",
		BODY_ZONE_PRECISE_GROIN: "Groin",
		BODY_ZONE_PRECISE_L_HAND: "Left Hand",
		BODY_ZONE_PRECISE_R_HAND: "Right Hand",
		BODY_ZONE_PRECISE_L_FOOT: "Left Foot",
		BODY_ZONE_PRECISE_R_FOOT: "Right Foot"
	}

func _setup_zone_icons():
	"""Configure icon mappings for zones"""
	zone_icons = {
		BODY_ZONE_HEAD: "zone_head",
		BODY_ZONE_PRECISE_EYES: "zone_head",
		BODY_ZONE_PRECISE_MOUTH: "zone_head",
		BODY_ZONE_CHEST: "zone_chest",
		BODY_ZONE_L_ARM: "zone_l_arm",
		BODY_ZONE_PRECISE_L_HAND: "zone_l_arm",
		BODY_ZONE_R_ARM: "zone_r_arm",
		BODY_ZONE_PRECISE_R_HAND: "zone_r_arm",
		BODY_ZONE_L_LEG: "zone_l_leg",
		BODY_ZONE_PRECISE_L_FOOT: "zone_l_leg",
		BODY_ZONE_R_LEG: "zone_r_leg",
		BODY_ZONE_PRECISE_R_FOOT: "zone_r_leg",
		BODY_ZONE_PRECISE_GROIN: "zone_groin"
	}
#endregion

#region PUBLIC INTERFACE
func handle_body_part_selection(part: String):
	"""Handle body part selection input"""
	match part:
		"head":
			toggle_head_zone()
		"chest":
			select_chest_zone()
		"groin":
			select_groin_zone()
		"r_arm":
			toggle_r_arm_zone()
		"l_arm":
			toggle_l_arm_zone()
		"r_leg":
			toggle_r_leg_zone()
		"l_leg":
			toggle_l_leg_zone()

func set_selected_zone(new_zone: String) -> bool:
	"""Set the selected body zone"""
	if not is_valid_body_zone(new_zone):
		return false
	
	zone_selected = new_zone
	emit_signal("zone_selected_changed", new_zone)
	
	# Update sprite system
	if highlight_targeted_zones and sprite_system and sprite_system.has_method("highlight_body_part"):
		sprite_system.highlight_body_part(new_zone)
	
	# Update weapon controller if it exists
	var weapon_controller = controller.get_node_or_null("WeaponController")
	if weapon_controller and weapon_controller.has_method("set_target_zone"):
		weapon_controller.set_target_zone(new_zone)
	
	return true

func get_selected_zone() -> String:
	"""Get the currently selected zone"""
	return zone_selected

func get_zone_display_name(zone: String = "") -> String:
	"""Get display name for a zone"""
	var target_zone = zone if zone != "" else zone_selected
	return zone_display_names.get(target_zone, "Unknown")

func get_zone_icon(zone: String = "") -> String:
	"""Get icon for a zone"""
	var target_zone = zone if zone != "" else zone_selected
	return zone_icons.get(target_zone, "zone_unknown")
#endregion

#region ZONE SELECTION
func toggle_head_zone():
	"""Cycle through head zones"""
	_cycle_through_zones(body_zones_head)

func toggle_r_arm_zone():
	"""Cycle through right arm zones"""
	_cycle_through_zones(body_zones_r_arm)

func toggle_l_arm_zone():
	"""Cycle through left arm zones"""
	_cycle_through_zones(body_zones_l_arm)

func toggle_r_leg_zone():
	"""Cycle through right leg zones"""
	_cycle_through_zones(body_zones_r_leg)

func toggle_l_leg_zone():
	"""Cycle through left leg zones"""
	_cycle_through_zones(body_zones_l_leg)

func select_chest_zone():
	"""Select chest zone"""
	set_selected_zone(BODY_ZONE_CHEST)

func select_groin_zone():
	"""Select groin zone"""
	set_selected_zone(BODY_ZONE_PRECISE_GROIN)

func _cycle_through_zones(zone_group: Array[String]):
	"""Cycle through a group of zones"""
	var current_index = zone_group.find(zone_selected)
	var next_index = 0
	
	if current_index != -1:
		next_index = (current_index + 1) % zone_group.size()
	
	set_selected_zone(zone_group[next_index])
	emit_signal("target_zone_cycled", zone_group[next_index])
#endregion

#region VALIDATION
func is_valid_body_zone(zone: String) -> bool:
	"""Check if zone is valid"""
	return zone in all_valid_zones

func get_zone_group(zone: String) -> Array[String]:
	"""Get the group a zone belongs to"""
	if zone in body_zones_head:
		return body_zones_head
	elif zone in body_zones_r_arm:
		return body_zones_r_arm
	elif zone in body_zones_l_arm:
		return body_zones_l_arm
	elif zone in body_zones_r_leg:
		return body_zones_r_leg
	elif zone in body_zones_l_leg:
		return body_zones_l_leg
	elif zone in body_zones_chest:
		return body_zones_chest
	elif zone in body_zones_groin:
		return body_zones_groin
	else:
		return []

func is_precise_zone(zone: String) -> bool:
	"""Check if zone is a precise target"""
	return zone.begins_with("precise_") or zone in [
		BODY_ZONE_PRECISE_EYES,
		BODY_ZONE_PRECISE_MOUTH,
		BODY_ZONE_PRECISE_GROIN,
		BODY_ZONE_PRECISE_L_HAND,
		BODY_ZONE_PRECISE_R_HAND,
		BODY_ZONE_PRECISE_L_FOOT,
		BODY_ZONE_PRECISE_R_FOOT
	]

func get_base_zone(precise_zone: String) -> String:
	"""Get base zone from precise zone"""
	match precise_zone:
		BODY_ZONE_PRECISE_EYES, BODY_ZONE_PRECISE_MOUTH:
			return BODY_ZONE_HEAD
		BODY_ZONE_PRECISE_L_HAND:
			return BODY_ZONE_L_ARM
		BODY_ZONE_PRECISE_R_HAND:
			return BODY_ZONE_R_ARM
		BODY_ZONE_PRECISE_L_FOOT:
			return BODY_ZONE_L_LEG
		BODY_ZONE_PRECISE_R_FOOT:
			return BODY_ZONE_R_LEG
		BODY_ZONE_PRECISE_GROIN:
			return BODY_ZONE_CHEST
		_:
			return precise_zone
#endregion

#region DAMAGE CALCULATION
func get_zone_damage_modifier(zone: String = "") -> float:
	"""Get damage modifier for zone"""
	var target_zone = zone if zone != "" else zone_selected
	
	match target_zone:
		BODY_ZONE_HEAD:
			return head_damage_multiplier
		BODY_ZONE_PRECISE_EYES:
			return eyes_damage_multiplier
		BODY_ZONE_PRECISE_MOUTH:
			return mouth_damage_multiplier
		BODY_ZONE_CHEST:
			return chest_damage_multiplier
		BODY_ZONE_PRECISE_GROIN:
			return groin_damage_multiplier
		BODY_ZONE_L_ARM, BODY_ZONE_R_ARM:
			return arm_damage_multiplier
		BODY_ZONE_PRECISE_L_HAND, BODY_ZONE_PRECISE_R_HAND:
			return hand_damage_multiplier
		BODY_ZONE_L_LEG, BODY_ZONE_R_LEG:
			return leg_damage_multiplier
		BODY_ZONE_PRECISE_L_FOOT, BODY_ZONE_PRECISE_R_FOOT:
			return foot_damage_multiplier
		_:
			return 1.0

func get_zone_hit_chance_modifier(zone: String = "") -> float:
	"""Get hit chance modifier for zone"""
	var target_zone = zone if zone != "" else zone_selected
	
	if is_precise_zone(target_zone):
		return precise_zone_hit_modifier
	else:
		return general_zone_hit_modifier

func get_zone_stun_chance(zone: String = "") -> float:
	"""Get stun chance for hitting zone"""
	var target_zone = zone if zone != "" else zone_selected
	
	match target_zone:
		BODY_ZONE_HEAD:
			return head_stun_chance
		BODY_ZONE_PRECISE_EYES:
			return eyes_stun_chance
		BODY_ZONE_PRECISE_MOUTH:
			return mouth_stun_chance
		BODY_ZONE_PRECISE_GROIN:
			return groin_stun_chance
		_:
			return 0.0
#endregion

#region UTILITY FUNCTIONS
func get_all_zones() -> Array[String]:
	"""Get all valid zones"""
	return all_valid_zones.duplicate()

func get_zones_for_limb(limb: String) -> Array[String]:
	"""Get all zones associated with a limb"""
	match limb.to_lower():
		"head":
			return body_zones_head.duplicate()
		"chest", "torso":
			return body_zones_chest.duplicate()
		"groin":
			return body_zones_groin.duplicate()
		"left_arm", "l_arm":
			return body_zones_l_arm.duplicate()
		"right_arm", "r_arm":
			return body_zones_r_arm.duplicate()
		"left_leg", "l_leg":
			return body_zones_l_leg.duplicate()
		"right_leg", "r_leg":
			return body_zones_r_leg.duplicate()
		_:
			return []

func get_random_zone() -> String:
	"""Get a random valid zone"""
	if all_valid_zones.is_empty():
		return BODY_ZONE_CHEST
	
	return all_valid_zones[randi() % all_valid_zones.size()]

func get_random_zone_for_limb(limb: String) -> String:
	"""Get a random zone for a specific limb"""
	var limb_zones = get_zones_for_limb(limb)
	if limb_zones.is_empty():
		return get_random_zone()
	
	return limb_zones[randi() % limb_zones.size()]
#endregion

#region SAVE/LOAD
func save_state() -> Dictionary:
	"""Save targeting state"""
	return {
		"zone_selected": zone_selected,
		"enable_precise_targeting": enable_precise_targeting,
		"highlight_targeted_zones": highlight_targeted_zones
	}

func load_state(data: Dictionary):
	"""Load targeting state"""
	if "zone_selected" in data and is_valid_body_zone(data.zone_selected):
		zone_selected = data.zone_selected
	
	if "enable_precise_targeting" in data:
		enable_precise_targeting = data.enable_precise_targeting
		_setup_zone_groups()  # Rebuild zone groups with new settings
	
	if "highlight_targeted_zones" in data:
		highlight_targeted_zones = data.highlight_targeted_zones
	
	# Update systems with current selection
	emit_signal("zone_selected_changed", zone_selected)
#endregion
