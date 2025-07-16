extends Node
class_name BodyTargetingComponent

## Handles body part targeting for attacks and interactions

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
var zone_selected: String = BODY_ZONE_CHEST

# Zone groups for cycling
var body_zones_head = [BODY_ZONE_HEAD, BODY_ZONE_PRECISE_EYES, BODY_ZONE_PRECISE_MOUTH]
var body_zones_r_arm = [BODY_ZONE_R_ARM, BODY_ZONE_PRECISE_R_HAND]
var body_zones_l_arm = [BODY_ZONE_L_ARM, BODY_ZONE_PRECISE_L_HAND]
var body_zones_r_leg = [BODY_ZONE_R_LEG, BODY_ZONE_PRECISE_R_FOOT]
var body_zones_l_leg = [BODY_ZONE_L_LEG, BODY_ZONE_PRECISE_L_FOOT]
var body_zones_chest = [BODY_ZONE_CHEST]
var body_zones_groin = [BODY_ZONE_PRECISE_GROIN]

# All valid zones
var all_valid_zones = []
#endregion

func initialize(init_data: Dictionary):
	"""Initialize the body targeting component"""
	controller = init_data.get("controller")
	sprite_system = init_data.get("sprite_system")
	
	# Compile all valid zones
	all_valid_zones = []
	for zone_group in [body_zones_head, body_zones_chest, body_zones_groin,
					   body_zones_r_arm, body_zones_l_arm, 
					   body_zones_r_leg, body_zones_l_leg]:
		all_valid_zones.append_array(zone_group)

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
	if sprite_system and sprite_system.has_method("highlight_body_part"):
		sprite_system.highlight_body_part(new_zone)
	
	# Update weapon controller if it exists
	var weapon_controller = controller.get_node_or_null("WeaponController")
	if weapon_controller and weapon_controller.has_method("set_target_zone"):
		weapon_controller.set_target_zone(new_zone)
	
	return true

func get_selected_zone() -> String:
	"""Get the currently selected zone"""
	return zone_selected

func get_zone_display_name(zone: String) -> String:
	"""Get display name for a zone"""
	match zone:
		BODY_ZONE_HEAD:
			return "Head"
		BODY_ZONE_CHEST:
			return "Chest"
		BODY_ZONE_L_ARM:
			return "Left Arm"
		BODY_ZONE_R_ARM:
			return "Right Arm"
		BODY_ZONE_L_LEG:
			return "Left Leg"
		BODY_ZONE_R_LEG:
			return "Right Leg"
		BODY_ZONE_PRECISE_EYES:
			return "Eyes"
		BODY_ZONE_PRECISE_MOUTH:
			return "Mouth"
		BODY_ZONE_PRECISE_GROIN:
			return "Groin"
		BODY_ZONE_PRECISE_L_HAND:
			return "Left Hand"
		BODY_ZONE_PRECISE_R_HAND:
			return "Right Hand"
		BODY_ZONE_PRECISE_L_FOOT:
			return "Left Foot"
		BODY_ZONE_PRECISE_R_FOOT:
			return "Right Foot"
		_:
			return "Unknown"

func get_zone_icon(zone: String) -> String:
	"""Get icon for a zone"""
	match zone:
		BODY_ZONE_HEAD, BODY_ZONE_PRECISE_EYES, BODY_ZONE_PRECISE_MOUTH:
			return "zone_head"
		BODY_ZONE_CHEST:
			return "zone_chest"
		BODY_ZONE_L_ARM, BODY_ZONE_PRECISE_L_HAND:
			return "zone_l_arm"
		BODY_ZONE_R_ARM, BODY_ZONE_PRECISE_R_HAND:
			return "zone_r_arm"
		BODY_ZONE_L_LEG, BODY_ZONE_PRECISE_L_FOOT:
			return "zone_l_leg"
		BODY_ZONE_R_LEG, BODY_ZONE_PRECISE_R_FOOT:
			return "zone_r_leg"
		BODY_ZONE_PRECISE_GROIN:
			return "zone_groin"
		_:
			return "zone_unknown"
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

func _cycle_through_zones(zone_group: Array):
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

func get_zone_group(zone: String) -> Array:
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
func get_zone_damage_modifier(zone: String) -> float:
	"""Get damage modifier for zone"""
	match zone:
		BODY_ZONE_HEAD:
			return 1.5
		BODY_ZONE_PRECISE_EYES:
			return 2.0
		BODY_ZONE_PRECISE_MOUTH:
			return 1.3
		BODY_ZONE_CHEST:
			return 1.0
		BODY_ZONE_PRECISE_GROIN:
			return 1.8
		BODY_ZONE_L_ARM, BODY_ZONE_R_ARM:
			return 0.8
		BODY_ZONE_PRECISE_L_HAND, BODY_ZONE_PRECISE_R_HAND:
			return 0.6
		BODY_ZONE_L_LEG, BODY_ZONE_R_LEG:
			return 0.9
		BODY_ZONE_PRECISE_L_FOOT, BODY_ZONE_PRECISE_R_FOOT:
			return 0.7
		_:
			return 1.0

func get_zone_hit_chance_modifier(zone: String) -> float:
	"""Get hit chance modifier for zone"""
	if is_precise_zone(zone):
		return 0.6  # Harder to hit precise zones
	else:
		return 1.0  # Normal hit chance for general zones

func get_zone_stun_chance(zone: String) -> float:
	"""Get stun chance for hitting zone"""
	match zone:
		BODY_ZONE_HEAD:
			return 0.3
		BODY_ZONE_PRECISE_EYES:
			return 0.5
		BODY_ZONE_PRECISE_MOUTH:
			return 0.2
		BODY_ZONE_PRECISE_GROIN:
			return 0.4
		_:
			return 0.0
#endregion
