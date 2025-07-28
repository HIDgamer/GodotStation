extends Clothing
class_name Ears

func _init():
	super._init()
	equipped_slot = EquipSlot.EARS
	w_class = 1  # SIZE_TINY
	throwforce = 2
	equip_slot_flags = Slots.EARS
	blood_overlay_type = "ears"

func update_clothing_icon():
	if inventory_owner:
		if inventory_owner.has_method("update_inv_ears"):
			inventory_owner.update_inv_ears()
