extends MedicalItem

func _ready():
	super._ready()
	
	# Item properties
	item_name = "Synth-Graft"
	description = "A synthetic skin graft used to treat severe burns."
	
	# Medical properties
	medical_type = MedicalItemType.MEDICINE_BURN
	heal_burn = 30.0
	requires_target_limb = true
	allowed_limbs = ["head", "chest", "l_arm", "r_arm", "l_leg", "r_leg", "groin"]
	use_time = 4.0
	use_self_time = 6.0  # Harder to apply to yourself
	
	# Visual setup
	$Icon.texture = preload("res://Assets/Icons/Items/Medical/Synth_Graft.png")
	
	# Requires medical skill
	requires_medical_skill = true
	minimum_skill_level = 1

func use_on(user, target, targeted_limb = ""):
	if targeted_limb.is_empty():
		if user and user.has_method("display_message"):
			user.display_message("You need to target a specific limb to apply synth-graft.")
		return false
	
	# Check if target has burn damage
	var health_system = target.get_node_or_null("HealthSystem")
	if !health_system or !("limbs" in health_system) or !health_system.limbs.has(targeted_limb):
		return false
	
	var limb = health_system.limbs[targeted_limb]
	
	# Check for burn wounds to treat
	if limb.burn_damage < 15:
		if user and user.has_method("display_message"):
			user.display_message("%s's %s doesn't need skin grafting." % [target.name, targeted_limb])
		return false
	
	# Apply graft
	var result = await super.use_on(user, target, targeted_limb)
	
	if result:
		# Heal significant burn damage
		health_system.heal_limb_damage(targeted_limb, 0, 30)
		
		# Add grafted status to limb
		limb.has_graft = true
		
		# Permanent slight healing bonus (for recurring burn damage)
		if health_system.has_method("add_status_effect"):
			health_system.add_status_effect("skin_grafted", 600.0, 1.0)  # 10 minute effect
		
		if user and user.has_method("display_message"):
			user.display_message("You carefully apply synthetic skin graft to %s's %s." % [target.name, targeted_limb])
	
	return result
