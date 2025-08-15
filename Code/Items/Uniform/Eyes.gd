extends Clothing
class_name Eyes

@export var vision_enhancement: String = ""
@export var see_in_dark: bool = false
@export var welding_protection: bool = false

func _init():
	super._init()
	primary_slot = Slots.GLASSES
	valid_slots = [Slots.GLASSES]
	w_class = 1  # SIZE_TINY

func update_clothing_icon():
	if inventory_owner:
		if inventory_owner.has_method("update_inv_eyes"):
			inventory_owner.update_inv_eyes()

func apply_vision_effects(user):
	"""Apply vision-related effects to the user"""
	if not user.has_method("add_vision_modifier"):
		return
	
	if see_in_dark:
		user.add_vision_modifier("night_vision", self)
	
	if welding_protection:
		user.add_vision_modifier("welding_protection", self)
	
	if vision_enhancement != "":
		user.add_vision_modifier(vision_enhancement, self)

func remove_vision_effects(user):
	"""Remove vision-related effects from the user"""
	if user.has_method("remove_vision_modifier"):
		user.remove_vision_modifier(self)

func equipped(user, slot: int):
	super.equipped(user, slot)
	apply_vision_effects(user)

func unequipped(user, slot: int):
	remove_vision_effects(user)
	super.unequipped(user, slot)
