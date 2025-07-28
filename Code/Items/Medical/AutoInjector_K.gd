extends MedicalItem

@onready var regant: AnimatedSprite2D = $Regant

func _ready():
	super._ready()
	
	# Item properties
	item_name = "Autoinjector (Kelotane)"
	description = "A rapid-use autoinjector containing Kelotane, a medication used to treat burn injuries."
	
	# Medical properties
	medical_type = MedicalItemType.MEDICINE_BURN
	heal_burn = 15.0
	use_time = 0.5
	use_self_time = 0.5
	
	# Sound setup
	use_sound = preload("res://Sound/items/hypospray.ogg")
	
	# Reagent properties
	has_reagents = true
	reagent_volume = 10.0
	reagent_max_volume = 10.0
	reagents = {"kelotane": 10.0}

func use_on(user, target, targeted_limb = ""):
	var result = await super.use_on(user, target, targeted_limb)
	
	if result:
		# Apply additional thermal regulation effects
		var health_system = target.get_node_or_null("HealthSystem")
		if health_system:
			# Help regulate body temperature
			if "body_temperature" in health_system and health_system.body_temperature > 310.15:
				health_system.body_temperature = max(310.15, health_system.body_temperature - 5)
			
			# Remove burn status effects
			if "status_effects" in health_system and "burned" in health_system.status_effects:
				health_system.remove_status_effect("burned")
		regant.visible = false
		# Consume the autoinjector after use
		queue_free()
	
	return result
