extends MedicalItem

@onready var icon: AnimatedSprite2D = $Icon

func _ready():
	super._ready()
	
	# Item properties
	item_name = "Autoinjector (Tramadol)"
	description = "A rapid-use autoinjector containing Tramadol, a synthetic opioid used to treat severe pain."
	
	# Medical properties
	medical_type = MedicalItemType.MEDICINE_PAIN
	reduce_pain = 30.0
	use_time = 0.5
	use_self_time = 0.5
	
	# Side effects
	side_effects = {
		"drowsiness": 0.3,  # 30% chance
		"dizziness": 0.2    # 20% chance
	}
	
	# Sound setup
	use_sound = preload("res://Sound/items/hypospray.ogg")
	
	# Reagent properties
	has_reagents = true
	reagent_volume = 10.0
	reagent_max_volume = 10.0
	reagents = {"tramadol": 10.0}

func use_on(user, target, targeted_limb = ""):
	var result = await super.use_on(user, target, targeted_limb)
	
	if result:
		# Apply pain reduction effects
		var health_system = target.get_node_or_null("HealthSystem")
		if health_system and "traumatic_shock" in health_system:
			# Significant pain reduction
			health_system.traumatic_shock = max(0, health_system.traumatic_shock - 50)
			
			# Reduce shock stage
			if "shock_stage" in health_system:
				health_system.shock_stage = max(0, health_system.shock_stage - 15)
				
			# Apply side effects (already handled in base class)
		icon.play("Used")
		# Consume the autoinjector after use
		queue_free()
	
	return result
