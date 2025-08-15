extends Clothing
class_name Head

func _init():
	super._init()
	primary_slot = Slots.HEAD
	valid_slots = [Slots.HEAD]
	blood_overlay_type = "head"
	
	# Head items often provide accessories
	valid_accessory_slots = AccessorySlot.PATCH | AccessorySlot.DECOR

func update_clothing_icon():
	if inventory_owner:
		if inventory_owner.has_method("update_inv_head"):
			inventory_owner.update_inv_head()
