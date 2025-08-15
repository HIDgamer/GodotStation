extends Clothing
class_name Armor

@export var suit_storage_items: Array = [] # Items that can be stored in suit
@export var suit_storage_slots: int = 2

func _init():
	super._init()
	primary_slot = Slots.WEAR_SUIT
	
	blood_overlay_type = "uniform"
	
	valid_slots = [Slots.WEAR_SUIT]
	w_class = 3  # SIZE_MEDIUM
	siemens_coefficient = 0.9
	fire_resist = 373.15  # T0C+100
	
	# Default allowed items for suit storage
	can_hold_items = [
		"res://scripts/items/tools/Flashlight.gd",
		"res://scripts/items/medical/HealthAnalyzer.gd",
		"res://scripts/items/devices/Radio.gd",
		"res://scripts/items/tools/Crowbar.gd",
		"res://scripts/items/tools/Pen.gd"
	]
	
	# Set up suit storage
	storage_slots = suit_storage_slots
	max_storage_space = suit_storage_slots * 2
	
	# Set up accessory slots for suits
	valid_accessory_slots = (
		AccessorySlot.MEDAL | AccessorySlot.RANK | AccessorySlot.DECOR | 
		AccessorySlot.PONCHO | AccessorySlot.MASK_ACCESSORY | AccessorySlot.ARMBAND |
		AccessorySlot.ARMOR_A | AccessorySlot.ARMOR_L | AccessorySlot.ARMOR_S | 
		AccessorySlot.ARMOR_M | AccessorySlot.UTILITY | AccessorySlot.PATCH
	)

func update_clothing_icon():
	if inventory_owner:
		if inventory_owner.has_method("update_inv_wear_suit"):
			inventory_owner.update_inv_wear_suit()

func can_equip(user, slot: int) -> bool:
	if not super.can_equip(user, slot):
		return false
	
	# Check for uniform restrictions
	if user.has_method("get_equipped_item"):
		var uniform = user.get_equipped_item("under")
		if uniform and "suit_restricted" in uniform and uniform.suit_restricted.size() > 0:
			var my_script = get_script()
			if my_script not in uniform.suit_restricted:
				show_user_message(user, get_entity_name(self) + " can't be worn with " + get_entity_name(uniform) + ".")
				return false
	
	return true
