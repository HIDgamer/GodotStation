extends ReagentItem

@onready var icon: AnimatedSprite2D = $Icon

func _ready():
	super._ready()
	
	icon.play("Closed")
	
	# Item properties
	item_name = "Pill Bottle (Tramadol)"
	description = "A small bottle containing Tramadol pills that relieve pain."
	
	# Medical properties
	medical_type = MedicalItemType.MEDICINE_PAIN
	reduce_pain = 25.0
	use_time = 1.0
	use_self_time = 1.0
	
	# Side effects
	side_effects = {
		"drowsiness": 0.2,  # 20% chance
		"dizziness": 0.1    # 10% chance
	}
	# Sound setup
	use_sound = preload("res://Sound/effects/pillbottle.ogg")
	
	# Container properties
	is_container = true
	max_contents = 10
	init_contents()

func should_be_consumed() -> bool:
	return false

func init_contents():
	# Initialize with 10 pills
	contents = []
	for i in range(10):
		contents.append({
			"name": "Tramadol Pill",
			"reduce_pain": 25.0,
			"description": "A pill that relieves pain."
		})

func use(user):
	super.use(user)
	icon.play("Open")

func use_on(user, target, targeted_limb = ""):
	# Check if we have pills left
	if contents.size() <= 0:
		if user and user.has_method("display_message"):
			user.display_message("The pill bottle is empty!")
		return false
	
	# Remove a pill
	var pill = contents.pop_back()
	
	# Apply pill effects
	var health_system = target.get_node_or_null("HealthSystem")
	if health_system and "traumatic_shock" in health_system:
		# Apply pain reduction
		health_system.traumatic_shock = max(0, health_system.traumatic_shock - pill.reduce_pain)
		
		# Reduce shock stage
		if "shock_stage" in health_system:
			health_system.shock_stage = max(0, health_system.shock_stage - 10)
			
		# Apply side effects
		for effect in side_effects:
			if randf() < side_effects[effect]:
				health_system.add_status_effect(effect, 30.0, 1.0)
	
	# Play sound
	if use_sound:
		play_audio(use_sound)
	
	# Show messages
	if user == target:
		if user and user.has_method("display_message"):
			user.display_message("You swallow a Tramadol pill. [%d remaining]" % contents.size())
	else:
		if user and user.has_method("display_message"):
			user.display_message("You feed a Tramadol pill to %s. [%d remaining]" % [target.name, contents.size()])
		if target and target.has_method("display_message"):
			target.display_message("%s feeds you a Tramadol pill." % user.name)
	
	# Don't call super.use_on as we handle everything here
	return true
