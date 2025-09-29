extends Clothing
class_name Jacket

func _init():
	super._init()
	
	primary_slot = Slots.WEAR_SUIT
	
	blood_overlay_type = "uniform"
	
	valid_slots = [Slots.WEAR_SUIT]
