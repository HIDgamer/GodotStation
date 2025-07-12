extends ReagentItem

@onready var icon: AnimatedSprite2D = $Icon

func _ready():
	super._ready()
	
	icon.play("Closed")
	
	# Item properties
	item_name = "Pill Bottle (Kelotane)"
	description = "A small bottle containing Kelotane pills that treat burn injuries."
	
	# Medical properties
	medical_type = MedicalItemType.CONTAINER
	heal_burn = 10.0
	use_time = 1.0
	use_self_time = 1.0
	# Sound setup
	use_sound = preload("res://Sound/effects/pillbottle.ogg")
	
	# Container properties
	is_container = true
	max_contents = 10
	init_contents()

func use(user):
	super.use(user)
	icon.play("Open")

func should_be_consumed() -> bool:
	return false

func init_contents():
	# Initialize with 10 pills
	contents = []
	for i in range(10):
		contents.append({
			"name": "Kelotane Pill",
			"heal_burn": 10.0,
			"description": "A pill that heals burn injuries."
		})

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
	if health_system:
		# Apply healing
		health_system.adjustFireLoss(-pill.heal_burn)
		
		# Help regulate body temperature
		if "body_temperature" in health_system and health_system.body_temperature > 310.15:
			health_system.body_temperature = max(310.15, health_system.body_temperature - 3)
	
	# Play sound
	if use_sound:
		play_audio(use_sound)
	
	# Show messages
	if user == target:
		if user and user.has_method("display_message"):
			user.display_message("You swallow a Kelotane pill. [%d remaining]" % contents.size())
	else:
		if user and user.has_method("display_message"):
			user.display_message("You feed a Kelotane pill to %s. [%d remaining]" % [target.name, contents.size()])
		if target and target.has_method("display_message"):
			target.display_message("%s feeds you a Kelotane pill." % user.name)
	
	# Don't call super.use_on as we handle everything here
	return true
