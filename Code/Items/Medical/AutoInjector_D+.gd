extends MedicalItem

@onready var regant: AnimatedSprite2D = $Regant

func _ready():
	super._ready()
	
	# Item properties
	item_name = "Autoinjector (Dexalin+)"
	description = "A rapid-use autoinjector containing Dexalin Plus, an advanced oxygen supplement that quickly reverses hypoxia."
	
	# Medical properties
	medical_type = MedicalItemType.INJECTOR
	heal_oxygen = 25.0
	use_time = 0.5
	use_self_time = 0.5
	
	# Sound setup
	use_sound = preload("res://Sound/items/hypospray.ogg")
	
	# Reagent properties
	has_reagents = true
	reagent_volume = 10.0
	reagent_max_volume = 10.0
	reagents = {"dexalinp": 10.0}

func use_on(user, target, targeted_limb = ""):
	var result = await super.use_on(user, target, targeted_limb)
	
	if result:
		# Apply additional oxygen effects
		var health_system = target.get_node_or_null("HealthSystem")
		if health_system:
			# Remove suffocating status effect if present
			if "status_effects" in health_system and "suffocating" in health_system.status_effects:
				health_system.remove_status_effect("suffocating")
			regant.visible = false
		# Consume the autoinjector after use
		queue_free()
	
	return result
