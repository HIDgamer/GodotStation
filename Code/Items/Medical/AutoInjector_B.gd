extends ReagentItem

@onready var regant: AnimatedSprite2D = $Regant

func _ready():
	super._ready()
	
	# Item properties
	item_name = "Autoinjector (Bicaridine)"
	description = "A rapid-use autoinjector containing Bicaridine, used to treat physical trauma."
	
	# Medical properties
	medical_type = MedicalItemType.INJECTOR
	heal_brute = 15.0
	use_time = 0.5  # Very quick to use
	use_self_time = 0.5
	
	# Sound setup
	use_sound = preload("res://Sound/items/hypospray.ogg")
	
	# Reagent properties
	has_reagents = true
	reagent_volume = 10.0
	reagent_max_volume = 10.0
	reagents = {"bicaridine": 10.0}

func use_on(user, target, targeted_limb = ""):
	var result = await super.use_on(user, target, targeted_limb)
	
	# Consume the autoinjector after use
	if result:
		# Apply chemical effects
		var health_system = target.get_node_or_null("HealthSystem")
		if health_system:
			# Reduce blood loss as bicaridine helps with clotting
			if health_system.has_method("set_bleeding_rate"):
				var current_rate = health_system.bleeding_rate
				health_system.set_bleeding_rate(max(0, current_rate - 1.0))
			regant.visible = false
		# Queue for deletion
		queue_free()
	
	return result
