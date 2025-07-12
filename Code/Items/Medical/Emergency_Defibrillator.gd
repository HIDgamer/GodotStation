extends MedicalItem

var charges = 3
var max_charges = 3
var charge_time = 2.0  # Time to charge up
var is_charging = false
@onready var icon: AnimatedSprite2D = $Icon

func _ready():
	super._ready()
	
	icon.play("Idle")
	
	# Item properties
	item_name = "Emergency Defibrillator"
	description = "A device used to revive patients who have gone into cardiac arrest, or to regulate an abnormal heartbeat."
	
	# Medical properties
	medical_type = MedicalItemType.TOOL
	use_time = 3.0  # Longer use time for defibrillation
	use_self_time = 0.0  # Can't use on yourself
	
	# Sound setup
	use_sound = preload("res://Sound/items/defib_charge.ogg")

func use(user):
	super.use(user)
	icon.play("Ready")

func should_be_consumed() -> bool:
	return false

func use_on(user, target, targeted_limb = ""):
	# Can't use on yourself
	if user == target:
		if user.has_method("display_message"):
			user.display_message("You can't defibrillate yourself!")
		return false
	
	# Check if we have charges
	if charges <= 0:
		if user.has_method("display_message"):
			user.display_message("The defibrillator is out of charges!")
		return false
	
	# Check if target is wearing something that would block the defib
	var inventory_system = target.get_node_or_null("InventorySystem")
	if inventory_system:
		var chest_item = inventory_system.get_item_in_slot(Slots.WEAR_SUIT)
		if chest_item and "is_space_suit" in chest_item and chest_item.is_space_suit:
			if user.has_method("display_message"):
				user.display_message("You need to remove %s's suit first!" % target.name)
			return false
	
	# Start charging
	if !is_charging:
		is_charging = true
		
		# Play charge sound
		if use_sound:
			play_audio(use_sound)
		
		if user.has_method("display_message"):
			user.display_message("You begin charging the defibrillator...")
		
		# Wait for charge time
		await get_tree().create_timer(charge_time).timeout
		
		# Play ready sound
		play_audio(preload("res://Sound/items/defib_ready.ogg"))
		
		if user.has_method("display_message"):
			user.display_message("The defibrillator is charged and ready!")
	
	# Apply defibrillation
	var health_system = target.get_node_or_null("HealthSystem")
	if !health_system:
		is_charging = false
		return false
	
	# Check target state
	if "current_state" in health_system:
		if health_system.current_state == health_system.HealthState.DEAD:
			# Try to revive
			if health_system.has_method("revive") and health_system.death_time < 300:  # Less than 5 minutes dead
				if user.has_method("display_message"):
					user.display_message("You apply the defibrillator to %s..." % target.name)
				
				# Play defib sound
				play_audio(preload("res://Sound/items/defib_release.ogg"))
				
				# Use a charge
				charges -= 1
				
				# Attempt to revive
				var success = health_system.revive(false)
				if success:
					if user.has_method("display_message"):
						user.display_message("%s's heart starts beating again!" % target.name)
				else:
					if user.has_method("display_message"):
						user.display_message("The defibrillator buzzes: 'Resuscitation failed - try again or seek advanced medical care.'")
			else:
				if user.has_method("display_message"):
					user.display_message("%s has been dead for too long to be revived with a defibrillator." % target.name)
		
		elif "in_cardiac_arrest" in health_system and health_system.in_cardiac_arrest:
			# Try to restart heart
			if health_system.has_method("exit_cardiac_arrest"):
				if user.has_method("display_message"):
					user.display_message("You apply the defibrillator to %s..." % target.name)
				
				# Play defib sound
				play_audio(preload("res://Sound/items/defib_release.ogg"))
				
				# Use a charge
				charges -= 1
				
				# Restart heart
				health_system.exit_cardiac_arrest()
				
				if user.has_method("display_message"):
					user.display_message("%s's heart rhythm is restored!" % target.name)
		else:
			if user.has_method("display_message"):
				user.display_message("%s doesn't need defibrillation." % target.name)
	
	# Reset charging state
	is_charging = false
	
	# Don't call super.use_on as we handle everything here
	return true

func examine(user):
	var examine_text = "An emergency defibrillator with [%d/%d] charges remaining." % [charges, max_charges]
	
	if charges <= 0:
		examine_text += " It needs to be recharged."
	elif charges < max_charges / 2:
		examine_text += " It's running low on charges."
	
	if is_charging:
		examine_text += " It's currently charging up."
	
	return examine_text
