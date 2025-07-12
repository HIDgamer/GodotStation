extends MedicalItem

func _ready():
	super._ready()
	
	# Item properties
	item_name = "Health Analyzer"
	description = "A hand-held body scanner capable of determining a patient's health status."
	
	# Medical properties
	medical_type = MedicalItemType.TOOL
	use_time = 1.0
	use_self_time = 1.0
	
	# Visual setup
	$Icon.texture = preload("res://Assets/Icons/Items/Medical/HealthAnalyzer.png")
	
	# Sound setup
	use_sound = preload("res://Sound/items/healthanalyzer.ogg")

func should_be_consumed() -> bool:
	return false

func use_on(user, target, targeted_limb = ""):
	# Play scan sound
	if use_sound:
		play_audio(use_sound)
	
	# Get health data
	var health_system = target.get_node_or_null("HealthSystem")
	if not health_system:
		if user and user.has_method("display_message"):
			user.display_message("No health data available.")
		return false
	
	# Get status report
	var status = health_system.get_status_report()
	
	# Display health info to user
	if user and user.has_method("display_message"):
		var message = "Health scan results for %s:\n" % target.name
		message += "Overall Health: %.1f%%\n" % (status.health / status.max_health * 100)
		message += "Brute Damage: %.1f | Burn Damage: %.1f\n" % [status.damage.brute, status.damage.burn]
		message += "Toxin Damage: %.1f | Oxygen Deprivation: %.1f\n" % [status.damage.toxin, status.damage.oxygen]
		message += "Pulse: %d BPM\n" % status.vital_signs.pulse
		
		# Show bleeding status
		if status.blood.bleeding_rate > 0:
			message += "ALERT: Subject is bleeding!"
		
		# Show status effects
		if not status.status_effects.is_empty():
			message += "\nDetected conditions: " + ", ".join(status.status_effects)
		
		user.display_message(message)
	
	# Don't call super.use_on() as we handle everything here
	return true
