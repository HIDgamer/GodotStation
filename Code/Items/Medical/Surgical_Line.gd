extends MedicalItem

func _ready():
	super._ready()
	
	# Item properties
	item_name = "Surgical Line"
	description = "A sterile package of surgical sutures used to close incisions and wounds."
	
	# Medical properties
	medical_type = MedicalItemType.TOOL
	requires_target_limb = true
	allowed_limbs = ["head", "chest", "l_arm", "r_arm", "l_leg", "r_leg", "groin"]
	use_time = 5.0
	use_self_time = 7.0  # Harder to suture yourself
	
	# Visual setup
	$Icon.texture = preload("res://Assets/Icons/Items/Medical/Surgical_Lining.png")
	
	# Requires medical skill
	requires_medical_skill = true
	minimum_skill_level = 2

func should_be_consumed() -> bool:
	# Only consume after several uses
	if randf() < 0.2:  # 20% chance to be used up
		return true
	return false

func use_on(user, target, targeted_limb = ""):
	if targeted_limb.is_empty():
		if user and user.has_method("display_message"):
			user.display_message("You need to target a specific limb to apply surgical line.")
		return false
	
	# Check if target has open wounds
	var health_system = target.get_node_or_null("HealthSystem")
	if !health_system or !("limbs" in health_system) or !health_system.limbs.has(targeted_limb):
		return false
	
	var limb = health_system.limbs[targeted_limb]
	
	# Check for wounds to suture
	if limb.brute_damage < 20:
		if user and user.has_method("display_message"):
			user.display_message("%s's %s doesn't need suturing." % [target.name, targeted_limb])
		return false
	
	# Check for open incisions
	if "get_incision_depth" in limb and limb.get_incision_depth() > 0:
		# Stitch closed incision
		var result = await super.use_on(user, target, targeted_limb)
		
		if result:
			# Close the incision
			if limb.has_method("close_incision"):
				limb.close_incision()
				
				if user and user.has_method("display_message"):
					user.display_message("You carefully suture the incision in %s's %s closed." % [target.name, targeted_limb])
			return true
	else:
		# Suture wounds
		var result = await super.use_on(user, target, targeted_limb)
		
		if result:
			# Heal brute damage and stop bleeding
			health_system.heal_limb_damage(targeted_limb, 15, 0)
			
			# Reduce bleeding
			if health_system.has_method("set_bleeding_rate"):
				var current_rate = health_system.bleeding_rate
				health_system.set_bleeding_rate(max(0, current_rate - 2.0))
				
			if user and user.has_method("display_message"):
				user.display_message("You carefully suture the wounds on %s's %s." % [target.name, targeted_limb])
			return true
	
	return false
