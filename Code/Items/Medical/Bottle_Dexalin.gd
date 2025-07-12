extends ReagentItem

@onready var regant: AnimatedSprite2D = $Regant

func _ready():
	super._ready()
	
	# Item properties
	item_name = "Bottle (Dexalin)"
	description = "A small bottle of Dexalin, a medication that prevents and treats oxygen deprivation."
	
	# Medical properties
	medical_type = MedicalItemType.MEDICINE_OXYGEN
	heal_oxygen = 15.0
	use_time = 1.5
	use_self_time = 1.5
	
	# Sound setup
	use_sound = preload("res://Sound/items/drink.ogg")
	
	# Reagent properties
	has_reagents = true
	reagent_volume = 30.0
	reagent_max_volume = 30.0
	reagents = {"dexalin": 30.0}

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
		
		# Apply oxygen treatment effects
		var health_system = target.get_node_or_null("HealthSystem")
		if health_system:
			# Improve oxygen efficiency
			if "current_state" in health_system and health_system.current_state != health_system.HealthState.DEAD:
				# Extra oxygen healing
				health_system.adjustOxyLoss(-5.0)
				
				# Reduced oxygen consumption for a while
				# This would need a custom status effect in the health system
				if health_system.has_method("add_status_effect"):
					health_system.add_status_effect("oxygen_efficiency", 30.0, 1.0)
	
	return result
