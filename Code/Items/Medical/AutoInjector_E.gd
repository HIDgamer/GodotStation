extends MedicalItem

@onready var regant: AnimatedSprite2D = $Regant

func _ready():
	super._ready()
	
	# Item properties
	item_name = "Autoinjector (Epinephrine)"
	description = "A rapid-use autoinjector containing epinephrine, used to stabilize patients in critical condition and restart failed hearts."
	
	# Medical properties
	medical_type = MedicalItemType.INJECTOR
	heal_oxygen = 10.0
	reduce_pain = 10.0
	use_time = 0.5
	use_self_time = 0.5
	
	# Sound setup
	use_sound = preload("res://Sound/items/hypospray.ogg")
	
	# Reagent properties
	has_reagents = true
	reagent_volume = 10.0
	reagent_max_volume = 10.0
	reagents = {"epinephrine": 10.0}

func use_on(user, target, targeted_limb = ""):
	var result = await super.use_on(user, target, targeted_limb)
	
	if result:
		# Critical stabilization effects
		var health_system = target.get_node_or_null("HealthSystem")
		if health_system:
			# Chance to restart heart if in cardiac arrest
			if "in_cardiac_arrest" in health_system and health_system.in_cardiac_arrest:
				if randf() < 0.5:  # 50% chance
					health_system.exit_cardiac_arrest()
			
			# Help with critical condition
			if "current_state" in health_system and health_system.current_state == health_system.HealthState.CRITICAL:
				health_system.adjustOxyLoss(-15.0)  # Extra oxygen help
				
				# Reduce shock
				if "shock_stage" in health_system:
					health_system.shock_stage = max(0, health_system.shock_stage - 20)
			regant.visible = false
		# Consume the autoinjector after use
		queue_free()
	
	return result
