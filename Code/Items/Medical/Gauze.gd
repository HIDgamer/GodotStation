extends MedicalItem

func _ready():
	super._ready()
	
	# Item properties
	item_name = "Roll of Gauze"
	description = "Some sterile gauze to wrap around bloody stumps and lacerations."
	
	# Medical properties
	medical_type = MedicalItemType.MEDICINE_BRUISE
	heal_brute = 5.0
	use_time = 1.0
	use_self_time = 0.8
	
	# Bleeding reduction
	set_bleeding_reduction(true)
	
	# Visual setup
	$Icon.texture = preload("res://Assets/Icons/Items/Medical/Gauze.png")
	
	# Sound setup
	use_sound = preload("res://Sound/handling/bandage.ogg")

func set_bleeding_reduction(enabled):
	# Custom function to handle bleeding reduction
	pass

func use_on(user, target, targeted_limb = ""):
	var result = await super.use_on(user, target, targeted_limb)
	
	if result:
		# Reduce bleeding if successful
		var health_system = target.get_node_or_null("HealthSystem")
		if health_system and health_system.has_method("set_bleeding_rate"):
			var current_rate = health_system.bleeding_rate
			health_system.set_bleeding_rate(max(0, current_rate - 2.0))
	
	return result
