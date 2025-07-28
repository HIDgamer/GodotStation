extends Clothing
class_name Mask

@export var anti_hug: bool = false
@export var allows_internals: bool = false
@export var allows_rebreath: bool = false
@export var filters_air: bool = false
@export var breath_temperature: float = 293.15  # T20C

func _init():
	super._init()
	equipped_slot = EquipSlot.MASK
	equip_slot_flags = Slots.WEAR_MASK
	blood_overlay_type = "mask"

func update_clothing_icon():
	if inventory_owner:
		if inventory_owner.has_method("update_inv_wear_mask"):
			inventory_owner.update_inv_wear_mask()

func toggle_internals(user):
	"""Toggle internal air supply"""
	if not allows_internals:
		show_user_message(user, "This mask doesn't support internals.")
		return false
	
	if not user.has_method("get_internal_air") or not user.has_method("set_internal_air"):
		return false
	
	var current_internal = user.get_internal_air()
	
	if current_internal:
		user.set_internal_air(null)
		show_user_message(user, "No longer running on internals.")
		return true
	else:
		# Find best tank
		var best_tank = find_best_air_tank(user)
		if best_tank:
			user.set_internal_air(best_tank)
			show_user_message(user, "You are now running on internals from " + get_entity_name(best_tank) + ".")
			return true
		else:
			show_user_message(user, "You don't have a suitable air tank.")
			return false

func find_best_air_tank(user):
	"""Find the best air tank for internals"""
	var check_slots = ["suit_storage", "back", "belt", "r_hand", "l_hand", "l_pocket", "r_pocket"]
	var best_tank = null
	var best_pressure = 0.0
	
	for slot_name in check_slots:
		if not user.has_method("get_equipped_item"):
			continue
			
		var item = user.get_equipped_item(slot_name)
		if item and item.has_method("get_gas_type") and item.has_method("get_pressure"):
			var pressure = item.get_pressure()
			if pressure >= 20.0 and pressure > best_pressure:
				# Check if it's a suitable gas type
				var gas_type = item.get_gas_type()
				if gas_type in ["oxygen", "air", "nitrogen", "n2o"]:
					best_tank = item
					best_pressure = pressure
	
	return best_tank

func filter_air(air_info: Dictionary) -> Dictionary:
	"""Filter incoming air if this mask has filtering capability"""
	if not filters_air:
		return air_info
	
	# Modify air composition/temperature
	if allows_rebreath:
		air_info["temperature"] = breath_temperature
	
	# Override this in specific mask types for custom filtering
	return air_info
