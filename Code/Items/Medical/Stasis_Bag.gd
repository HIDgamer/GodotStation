extends MedicalItem

var is_active = false
var occupied = false
var patient = null
@onready var icon: AnimatedSprite2D = $Icon

func _ready():
	super._ready()
	
	icon.play("Item")
	
	# Item properties
	item_name = "Stasis Bag"
	description = "A folded, reusable stasis bag designed to slow down metabolism and preserve life of critically injured patients."
	
	# Medical properties
	medical_type = MedicalItemType.TOOL
	use_time = 3.0
	use_self_time = 0.0  # Can't use on yourself
	# Sound setup
	use_sound = preload("res://Sound/items/zip.ogg")

func should_be_consumed() -> bool:
	return false

func use_on(user, target, targeted_limb = ""):
	# Can't use on yourself
	if user == target:
		if user.has_method("display_message"):
			user.display_message("You can't put yourself in a stasis bag!")
		return false
	
	# Check if bag is already occupied
	if occupied:
		if user.has_method("display_message"):
			user.display_message("This stasis bag is already in use!")
		return false
	
	# Check if target can be put in stasis
	var health_system = target.get_node_or_null("HealthSystem")
	if !health_system:
		return false
		
	# Check if target is in critical condition
	if "current_state" in health_system and health_system.current_state == health_system.HealthState.CRITICAL:
		var result = await super.use_on(user, target, targeted_limb)
		
		if result:
			# Put target in stasis
			occupied = true
			patient = target
			is_active = true
			
			if user.has_method("display_message"):
				user.display_message("You carefully place %s in the stasis bag and activate it." % target.name)
			
			# Apply stasis effect
			if health_system.has_method("toggle_stasis"):
				health_system.toggle_stasis(true)
			else:
				# Fallback method
				health_system.in_stasis = true
			
			# Add glow effect
			var light = PointLight2D.new()
			light.name = "StasisLight"
			light.color = Color(0.0, 0.8, 1.0, 0.7)
			light.energy = 0.7
			light.texture = preload("res://Assets/Effects/Light/light_64.png")
			add_child(light)
			
			# Handle patient visually
			handle_patient_visual(target, true)
			
			# Start monitoring patient
			set_process(true)
			
			return true
	else:
		if user.has_method("display_message"):
			user.display_message("%s is not in critical condition and doesn't need a stasis bag." % target.name)
	
	return false

func _process(delta):
	# Only process if active and occupied
	if !is_active or !occupied or !patient:
		return
	
	# Check if patient is still valid
	if !is_instance_valid(patient):
		deactivate()
		return
	
	# Check if patient health system is still valid
	var health_system = patient.get_node_or_null("HealthSystem")
	if !health_system:
		deactivate()
		return
	
	# Check if patient is dead
	if "current_state" in health_system and health_system.current_state == health_system.HealthState.DEAD:
		# Stasis doesn't help dead patients
		deactivate()
		return
	
	# Check if patient is still in critical condition
	if "current_state" in health_system and health_system.current_state != health_system.HealthState.CRITICAL:
		# Patient is stable, no longer needs stasis
		deactivate()
		return

func deactivate():
	if !is_active:
		return
	
	# Turn off stasis
	is_active = false
	
	if occupied and is_instance_valid(patient):
		# Remove stasis effect
		var health_system = patient.get_node_or_null("HealthSystem")
		if health_system:
			if health_system.has_method("toggle_stasis"):
				health_system.toggle_stasis(false)
			else:
				# Fallback method
				health_system.in_stasis = false
		
		# Handle patient visually
		handle_patient_visual(patient, false)
		
		# Clear patient reference
		patient = null
	
	# Reset occupied flag
	occupied = false
	
	# Remove glow effect
	var light = get_node_or_null("StasisLight")
	if light:
		light.queue_free()
	
	# Stop processing
	set_process(false)

func handle_patient_visual(target, entering_stasis):
	# This function would handle making the patient invisible and creating
	# a visual representation within the bag, or vice versa when removing
	
	if entering_stasis:
		# Hide the patient
		target.visible = false
		
		# Disable patient collision
		if target.has_method("set_collision_layer"):
			target.set_collision_layer(0)
			target.set_collision_mask(0)
		
		# Position patient at bag's location
		target.global_position = global_position
	else:
		# Show the patient
		target.visible = true
		
		# Re-enable patient collision
		if target.has_method("set_collision_layer"):
			target.set_collision_layer(1)
			target.set_collision_mask(1)
		
		# Offset position slightly to avoid overlap
		target.global_position = global_position + Vector2(32, 0)

func interact(user):
	# If active, check if the user wants to deactivate
	if is_active and occupied:
		if user.has_method("display_message"):
			user.display_message("You deactivate the stasis bag and carefully remove the patient.")
		
		deactivate()
		return true
	
	# Otherwise, handle normally
	return super.interact(user)
