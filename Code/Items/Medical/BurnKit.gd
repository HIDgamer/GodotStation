extends MedicalItem

func _ready():
	super._ready()
	
	# Item properties
	item_name = "Burn Kit"
	description = "A treatment kit for severe burns."
	
	# Medical properties
	medical_type = MedicalItemType.MEDICINE_BURN
	heal_burn = 12.0
	use_time = 2.5
	use_self_time = 2.0
	
	# Visual setup
	$Icon.texture = preload("res://Assets/Icons/Items/Medical/BurnKit.png")
	
	# Sound setup
	use_sound = preload("res://Sound/handling/ointment_spreading.ogg")
	
	# Other properties
	requires_medical_skill = true
	minimum_skill_level = 1
