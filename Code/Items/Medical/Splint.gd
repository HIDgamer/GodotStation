extends MedicalItem

func _ready():
	super._ready()
	
	# Item properties
	item_name = "Medical Splints"
	description = "A collection of different splints and securing gauze. What, did you think we only broke legs out here?"
	
	# Medical properties
	medical_type = MedicalItemType.TOOL
	requires_target_limb = true
	allowed_limbs = ["l_arm", "r_arm", "l_leg", "r_leg", "l_hand", "r_hand", "l_foot", "r_foot"]
	use_time = 3.0
	use_self_time = 4.5  # Harder to splint yourself
	
	# Visual setup
	$Icon.texture = preload("res://Assets/Icons/Items/Medical/Splint.png")
	
	# Sound setup
	use_sound = preload("res://Sound/handling/splint1.ogg")

func use_on(user, target, targeted_limb = ""):
	if targeted_limb.is_empty():
		if user and user.has_method("display_message"):
			user.display_message("You need to target a specific limb to apply a splint.")
		return false
		
	var result = await super.use_on(user, target, targeted_limb)
	
	if result:
		# Apply splint to limb
		var health_system = target.get_node_or_null("HealthSystem")
		if health_system and "limbs" in health_system and health_system.limbs.has(targeted_limb):
			# Add splint status to limb
			health_system.limbs[targeted_limb].is_splinted = true
			
			# Reduce pain from that limb
			if health_system.has_method("reduce_limb_pain"):
				health_system.reduce_limb_pain(targeted_limb, 20)
	
	return result
