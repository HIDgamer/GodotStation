extends MedicalItem

func _ready():
	super._ready()
	
	# Item properties
	item_name = "Ointment"
	description = "Used to treat burns, infected wounds, and relieve itching in unusual places."
	
	# Medical properties
	medical_type = MedicalItemType.MEDICINE_BURN
	heal_burn = 5.0
	use_time = 1.0
	use_self_time = 0.8
	
	# Visual setup
	$Icon.texture = preload("res://Assets/Icons/Items/Medical/Ointment.png")
	
	# Sound setup
	use_sound = preload("res://Sound/handling/ointment_spreading.ogg")
