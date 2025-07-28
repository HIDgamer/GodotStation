extends MedicalItem

@onready var regant: AnimatedSprite2D = $Regant

func _ready():
	super._ready()
	
	regant.play("1")
	
	# Item properties
	item_name = "Bottle (Peridaxon)"
	description = "A small bottle of Peridaxon, a powerful medication that regenerates damaged internal organs."
	
	# Medical properties
	medical_type = MedicalItemType.MEDICINE_MULTIPURPOSE
	use_time = 1.5
	use_self_time = 1.5
	
	# Sound setup
	use_sound = preload("res://Sound/items/drink.ogg")
	
	# Reagent properties
	has_reagents = true
	reagent_volume = 30.0
	reagent_max_volume = 30.0
	reagents = {"peridaxon": 30.0}

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

		# Apply organ repair effects
		var health_system = target.get_node_or_null("HealthSystem")
		if health_system and "organs" in health_system:
			# Heal all damaged organs
			for organ_name in health_system.organs:
				var organ = health_system.organs[organ_name]
				if organ.damage > 0:
					# Heal the organ damage
					health_system.heal_organ_damage(organ_name, 10.0)
					
					# If it was a vital failing organ, let the user know
					if organ.is_vital and organ.is_failing:
						if user and user.has_method("display_message"):
							user.display_message("The Peridaxon is working to repair %s's damaged %s." % [target.name, organ_name])
					
					# Only heal one organ per dose for balance
					break
	
	return result
