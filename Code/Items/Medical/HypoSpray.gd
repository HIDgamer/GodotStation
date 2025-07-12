extends MedicalItem

func _ready():
	super._ready()
	
	# Item properties
	item_name = "Hypospray"
	description = "A sterile hypospray loaded with tricordrazine, a general-purpose healing chemical."
	
	# Medical properties
	medical_type = MedicalItemType.INJECTOR
	heal_brute = 10.0
	heal_burn = 10.0
	heal_toxin = 5.0
	heal_oxygen = 5.0
	use_time = 0.7
	use_self_time = 0.7
	
	# Sound setup
	use_sound = preload("res://Sound/items/hypospray.ogg")
	
	# Reagent properties
	has_reagents = true
	reagent_volume = 30.0
	reagent_max_volume = 30.0
	reagents = {"tricordrazine": 30.0}

func should_be_consumed() -> bool:
	return false

func use_on(user, target, targeted_limb = ""):
	# Check if we have reagents
	if reagent_volume <= 0:
		if user and user.has_method("display_message"):
			user.display_message("The hypospray is empty!")
		return false
	
	var result = await super.use_on(user, target, targeted_limb)
	
	if result:
		# Consume reagents
		reagent_volume -= 5.0  # Each use consumes 5 units
		if reagent_volume <= 0:
			reagent_volume = 0
			
			if user and user.has_method("display_message"):
				user.display_message("The hypospray is now empty.")
	
	return result
