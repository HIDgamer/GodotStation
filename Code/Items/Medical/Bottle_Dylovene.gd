extends MedicalItem

@onready var regant: AnimatedSprite2D = $Regant

func _ready():
	super._ready()
	
	# Item properties
	item_name = "Bottle (Dylovene)"
	description = "A small bottle of Dylovene, an anti-toxin medication that helps remove toxins from the bloodstream."
	
	# Medical properties
	medical_type = MedicalItemType.MEDICINE_TOXIN
	heal_toxin = 20.0
	use_time = 1.5
	use_self_time = 1.5
	
	# Sound setup
	use_sound = preload("res://Sound/items/drink.ogg")
	
	# Reagent properties
	has_reagents = true
	reagent_volume = 30.0
	reagent_max_volume = 30.0
	reagents = {"dylovene": 30.0}

func should_be_consumed() -> bool:
	return false

func use_on(user, target, targeted_limb = ""):
	# Check if we have reagents left
	if reagent_volume <= 0:
		if user and user.has_method("display_message"):
			user.display_message("The bottle is empty!")
		return false
	
	var result = await super.use_on(user, target, targeted_limb)
	
	if result:
		# Consume some reagents
		reagent_volume -= 5.0  # Each use consumes 5 units
		if reagent_volume < 0:
			reagent_volume = 0
		
		# Update visual animation based on current reagent volume
		var ratio = reagent_volume / reagent_max_volume
		if reagent_volume <= 0:
			regant.hide()
			if user and user.has_method("display_message"):
				user.display_message("The bottle is now empty.")
		else:
			regant.show()
			if ratio > 0.8:
				regant.play("1")  # 25–30
			elif ratio > 0.6:
				regant.play("2")  # 19–24
			elif ratio > 0.4:
				regant.play("3")  # 13–18
			elif ratio > 0.2:
				regant.play("4")  # 7–12
			else:
				regant.play("5")  # 1–6
		
		# Apply specific antitoxin effects
		var health_system = target.get_node_or_null("HealthSystem")
		if health_system:
			# Remove poisoned status effect if present
			if "status_effects" in health_system and "poisoned" in health_system.status_effects:
				health_system.remove_status_effect("poisoned")
	
	return result
