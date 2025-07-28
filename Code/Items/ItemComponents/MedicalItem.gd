extends Item
class_name MedicalItem

# Medical item types - improved with more specific categories
enum MedicalItemType {
	GENERIC,
	MEDICINE_BRUISE,    # Physical trauma treatment
	MEDICINE_BURN,      # Burn treatment
	MEDICINE_TOXIN,     # Toxin treatment
	MEDICINE_OXYGEN,    # Oxygen deprivation treatment
	MEDICINE_PAIN,      # Pain relief
	MEDICINE_MULTIPURPOSE,  # Treats multiple damage types
	MEDICINE_BLOOD,     # Blood restoration/clotting
	MEDICINE_ORGAN,     # Organ treatment
	MEDICINE_STIMULANT, # Stamina restoration
	MEDICINE_ANTIBIOTIC,# Infection treatment
	MEDICINE_RADIATION, # Radiation treatment
	TOOL,               # Medical tools like scalpels, health analyzers
	IMPLANT,            # Medical implants
	CONTAINER,          # Medicine containers like pill bottles
	INJECTOR            # Syringes, autoinjectors
}

# Core medical properties
@export var medical_type: MedicalItemType = MedicalItemType.GENERIC
@export var heal_brute: float = 0.0
@export var heal_burn: float = 0.0
@export var heal_toxin: float = 0.0
@export var heal_oxygen: float = 0.0
@export var heal_brain: float = 0.0
@export var heal_stamina: float = 0.0
@export var heal_clone: float = 0.0  # For cellular damage
@export var reduce_pain: float = 0.0
@export var purge_toxin: float = 0.0  # How much toxin to purge
@export var stop_bleeding: float = 0.0  # Bleeding reduction amount
@export var heal_organ: float = 0.0  # Organ healing amount

# Status effect application/removal
@export var status_effects_add: Dictionary = {}    # Status effects to add: name:duration
@export var status_effects_remove: Array = []      # Status effects to remove
@export var status_resistance: float = 0.0         # Temporary resistance to negative effects

# Usage properties
@export var use_time: float = 2.0  # Time it takes to use in seconds
@export var use_self_time: float = 1.5  # Time to use on self
@export var use_sound: AudioStream = null  # Sound when used
@export var use_message: String = "You apply the %s."  # Message when used
@export var target_message: String = "%s applies the %s to you."  # Message for target
@export var use_self_message: String = "You apply the %s to yourself."  # Message when used on self

# Blood system interaction
@export var blood_restore: float = 0.0  # Amount of blood to restore
@export var blood_type: String = ""     # Blood type (for transfusions)
@export var restore_pulse: bool = false # Whether item restores pulse
@export var blood_clotting: float = 0.0 # Blood clotting effectiveness

# Side effects and addiction
@export var side_effects: Dictionary = {}  # Dictionary of side effects and chances
@export var overdose_threshold: float = 0.0  # Amount that causes overdose
@export var addiction_threshold: float = 0.0  # Amount that might cause addiction
@export var addiction_chance: float = 0.0    # Chance of addiction (0-1)

# For container items
@export var is_container: bool = false
@export var max_contents: int = 0  # Number of items it can hold
@export var contents: Array = []  # Items inside container

# For reagent-based items
@export var has_reagents: bool = false
@export var reagent_volume: float = 0.0
@export var reagent_max_volume: float = 0.0
@export var reagents: Dictionary = {}  # Dictionary of reagent names and amounts
@export var absorption_method: String = "ingestion"  # ingestion, injection, topical, inhalation

# For limb targeting
@export var requires_target_limb: bool = false
@export var allowed_limbs: Array = []  # Which limbs this can be used on
@export var treat_wounds: bool = false      # If this can treat wounds
@export var close_wounds: bool = false      # If this can close wounds
@export var treat_fractures: bool = false   # If this can treat fractures
@export var treat_burns: bool = false       # If this can treat burns

# For skill-based items
@export var requires_medical_skill: bool = false
@export var minimum_skill_level: int = 0  # Minimum skill level to use effectively

# Signals
signal medical_item_used(item, user, target, effectiveness)
signal reagent_added(reagent_name, amount)
signal reagent_removed(reagent_name, amount)

# Reference to systems on target entity
var target_health_system = null
var target_blood_system = null
var target_limb_system = null
var target_status_system = null
var target_chem_system = null

func _ready():
	super._ready()
	
	# Set default item properties
	pickupable = true
	w_class = 2  # Small item by default
	throwable = true
	
	# Setup reagents if needed
	if has_reagents and reagents.is_empty() and reagent_max_volume > 0:
		initialize_reagents()

func initialize_reagents():
	# For containers with reagents, initialize the actual reagents
	# This would be specific to each medicine type
	pass

func use_on(user, target, targeted_limb = ""):
	# Cannot use if not allowed
	if requires_medical_skill and !has_medical_skill(user):
		if user and user.has_method("display_message"):
			user.display_message("You don't have the medical knowledge to use " + item_name + ".")
		return false
	
	# Check if we need a specific limb
	if requires_target_limb and targeted_limb.is_empty():
		if user and user.has_method("display_message"):
			user.display_message("You need to target a specific body part to use " + item_name + ".")
		return false
	
	# Check if the targeted limb is valid
	if requires_target_limb and !targeted_limb.is_empty() and !allowed_limbs.is_empty() and !allowed_limbs.has(targeted_limb):
		if user and user.has_method("display_message"):
			user.display_message("You can't use " + item_name + " on that body part.")
		return false
	
	# Find the target's health systems
	find_target_systems(target)
	
	# Get the appropriate use time
	var actual_use_time = use_self_time if user == target else use_time
	
	# Show "using" message
	if user and user.has_method("display_message"):
		user.display_message("You begin to apply " + item_name + "...")
	
	# Play use sound
	if use_sound:
		play_audio(use_sound)
	
	# Wait for use time
	await get_tree().create_timer(actual_use_time).timeout
	
	# Make sure user is still there and close enough
	if !is_instance_valid(user) or !is_instance_valid(target):
		return false
	
	# Check if user is still close enough to target
	if user != target:
		var distance = user.global_position.distance_to(target.global_position)
		if distance > 32:  # 1 tile
			if user.has_method("display_message"):
				user.display_message("You need to stay close to apply " + item_name + ".")
			return false
	
	# Apply healing effects
	apply_healing_effects(target, targeted_limb)
	
	# Show use messages
	if user and user.has_method("display_message"):
		if user == target:
			user.display_message(use_self_message % item_name)
		else:
			user.display_message(use_message % item_name)
	
	# Show message to target if different from user
	if target != user and target.has_method("display_message"):
		target.display_message(target_message % [user.entity_name, item_name])
	
	# Apply reagents to target's body chemistry system
	if has_reagents and target_chem_system:
		transfer_reagents_to_target(target)
	
	# Apply side effects
	apply_side_effects(target)
	
	# Emit signal
	var effectiveness = calculate_effectiveness(user)
	emit_signal("medical_item_used", self, user, target, effectiveness)
	
	# Consume item if it's supposed to be used up
	if should_be_consumed():
		consume_item(user)
	
	return true

# Find all relevant health systems on the target
func find_target_systems(target):
	target_health_system = target.get_node_or_null("HealthSystem")
	target_blood_system = target.get_node_or_null("BloodSystem")
	target_limb_system = target.get_node_or_null("LimbSystem")
	target_status_system = target.get_node_or_null("StatusEffectManager")
	target_chem_system = target.get_node_or_null("BodyChemicalSystem")
	
	# If systems aren't direct children, try to find connector
	if !target_health_system:
		var health_connector = target.get_node_or_null("HealthConnector")
		if health_connector:
			target_health_system = health_connector.health_system

func apply_healing_effects(target, targeted_limb = ""):
	# Calculate effectiveness based on skill
	var effectiveness = 1.0
	if is_instance_valid(last_thrower) and requires_medical_skill:
		effectiveness = calculate_effectiveness(last_thrower)
	
	# Apply limb-specific healing if a limb is targeted
	if !targeted_limb.is_empty() and target_limb_system:
		# Apply limb-specific healing
		apply_limb_healing(target, targeted_limb, effectiveness)
	else:
		# Apply general healing through health system
		apply_general_healing(target, effectiveness)
	
	# Apply blood system effects
	apply_blood_effects(target, effectiveness)
	
	# Apply status effects
	apply_status_effects(target, effectiveness)

# Apply healing to a specific limb
func apply_limb_healing(target, limb_name, effectiveness):
	if !target_limb_system:
		return
		
	# Heal limb damage
	if heal_brute > 0 or heal_burn > 0:
		target_limb_system.heal_limb_damage(limb_name, 
										  heal_brute * effectiveness, 
										  heal_burn * effectiveness)
	
	# Handle wound treatment
	if treat_wounds:
		# If this is a bandage or similar
		if blood_clotting > 0:
			target_limb_system.apply_bandage(limb_name, effectiveness)
		
		# If this is for burns
		if treat_burns:
			target_limb_system.apply_burn_treatment(limb_name, effectiveness)
		
		# If this is a suture or staple gun
		if close_wounds:
			target_limb_system.apply_sutures(limb_name, effectiveness)
		
		# If this is a splint
		if treat_fractures:
			target_limb_system.apply_splint(limb_name)
	
	# Apply pain reduction to target if available
	if reduce_pain > 0 and target_health_system:
		target_health_system.traumatic_shock = max(0, 
												target_health_system.traumatic_shock - 
												(reduce_pain * effectiveness))

# Apply general healing through the health system
func apply_general_healing(target, effectiveness):
	if !target_health_system:
		return
		
	# Apply overall health healing
	if heal_brute > 0:
		target_health_system.adjustBruteLoss(-heal_brute * effectiveness)
	
	if heal_burn > 0:
		target_health_system.adjustFireLoss(-heal_burn * effectiveness)
	
	if heal_toxin > 0:
		target_health_system.adjustToxLoss(-heal_toxin * effectiveness)
	
	if heal_oxygen > 0:
		target_health_system.adjustOxyLoss(-heal_oxygen * effectiveness)
	
	if heal_brain > 0:
		target_health_system.adjustBrainLoss(-heal_brain * effectiveness)
	
	if heal_stamina > 0:
		target_health_system.adjustStaminaLoss(-heal_stamina * effectiveness)
	
	if heal_clone > 0:
		target_health_system.adjustCloneLoss(-heal_clone * effectiveness)
	
	# Apply organ healing if applicable
	if heal_organ > 0 and target_health_system.organs:
		for organ_name in target_health_system.organs:
			var organ = target_health_system.organs[organ_name]
			if organ.is_damaged:
				target_health_system.heal_organ_damage(organ_name, heal_organ * effectiveness)
				break  # Just heal one damaged organ for now
	
	# Apply pain reduction
	if reduce_pain > 0:
		target_health_system.traumatic_shock = max(0, 
												target_health_system.traumatic_shock - 
												(reduce_pain * effectiveness))

# Apply effects to the blood system
func apply_blood_effects(target, effectiveness):
	if !target_blood_system:
		return
		
	# Restore blood if applicable
	if blood_restore > 0:
		# If it's a blood product, check compatibility
		if blood_type != "":
			if target_blood_system.is_blood_compatible(blood_type):
				target_blood_system.add_blood(blood_restore * effectiveness, blood_type)
		else:
			# Generic blood restoration (like iron supplements)
			target_blood_system.adjust_blood_volume(blood_restore * effectiveness)
	
	# Apply blood clotting to reduce bleeding
	if blood_clotting > 0 and target_blood_system.bleeding_rate > 0:
		var current_rate = target_blood_system.bleeding_rate
		var reduction = min(current_rate, blood_clotting * effectiveness)
		target_blood_system.set_bleeding_rate(current_rate - reduction)
	
	# Stop bleeding completely if strong enough
	if stop_bleeding > 0 and stop_bleeding * effectiveness >= target_blood_system.bleeding_rate:
		target_blood_system.stop_bleeding()
	
	# Restore pulse if applicable
	if restore_pulse and target_blood_system.in_cardiac_arrest:
		# Chance to restore pulse based on effectiveness
		if randf() < 0.3 * effectiveness:
			target_blood_system.exit_cardiac_arrest()

# Apply status effects
func apply_status_effects(target, effectiveness):
	if !target_status_system:
		return
		
	# Add new status effects
	for effect_name in status_effects_add:
		var duration = status_effects_add[effect_name]
		target_status_system.add_effect(effect_name, duration, effectiveness)
	
	# Remove status effects
	for effect_name in status_effects_remove:
		target_status_system.remove_effects_by_name(effect_name)
	
	# Apply temporary status resistance
	if status_resistance > 0:
		var current_resistance = target_status_system.status_resistance
		target_status_system.set_status_resistance(
			current_resistance + (status_resistance * effectiveness)
		)
		# Reset after some time
		await get_tree().create_timer(10.0 * effectiveness).timeout
		target_status_system.set_status_resistance(current_resistance)

# Transfer reagents to target's chemical system
func transfer_reagents_to_target(target):
	if !target_chem_system or !has_reagents or reagent_volume <= 0:
		return
	
	# Transfer all reagents to the target body chemistry system
	for reagent_name in reagents:
		var amount = reagents[reagent_name]
		if amount > 0:
			target_chem_system.add_reagent(reagent_name, amount, absorption_method)
			
			# Remove from this item
			reagents[reagent_name] = 0
	
	# Reset this item's reagent volume
	reagent_volume = 0

func apply_side_effects(target):
	# Process any side effects
	var health_system = target.get_node_or_null("HealthSystem")
	if !health_system:
		return
	
	# Check each side effect
	for effect_name in side_effects:
		var effect_chance = side_effects[effect_name]
		
		# Roll for side effect
		if randf() < effect_chance:
			match effect_name:
				"drowsiness":
					if target_status_system:
						target_status_system.add_effect("drowsy", 30.0, 1.0)
					else:
						health_system.add_status_effect("drowsy", 30.0, 1.0)
				"dizziness":
					if target_status_system:
						target_status_system.add_effect("dizzy", 20.0, 1.0)
					else:
						health_system.add_status_effect("dizzy", 20.0, 1.0)
				"nausea":
					if target_status_system:
						target_status_system.add_effect("nausea", 15.0, 1.0)
					else:
						health_system.add_status_effect("nausea", 15.0, 1.0)
				"confusion":
					if target_status_system:
						target_status_system.add_effect("confused", 10.0, 1.0)
					else:
						health_system.add_status_effect("confused", 10.0, 1.0)
				"hallucination":
					if target_status_system:
						target_status_system.add_effect("hallucinating", 30.0, 1.0)
					else:
						health_system.add_status_effect("hallucinating", 30.0, 1.0)
				"overdose":
					trigger_overdose(target)

func trigger_overdose(target):
	if !target_health_system:
		var health_system = target.get_node_or_null("HealthSystem")
		if !health_system:
			return
		target_health_system = health_system
	
	# Apply overdose effects
	target_health_system.adjustToxLoss(5.0)
	
	if target_status_system:
		target_status_system.add_effect("dizzy", 30.0, 2.0)
	else:
		target_health_system.add_status_effect("dizzy", 30.0, 2.0)
	
	# Inform target
	if target.has_method("display_message"):
		target.display_message("You feel very ill!")

func calculate_effectiveness(user) -> float:
	if !requires_medical_skill:
		return 1.0
	
	# Check user's medical skill
	var skill_level = 0
	if user.has_method("get_skill_level"):
		skill_level = user.get_skill_level("medical")
	
	# Calculate effectiveness based on skill vs required skill
	if skill_level < minimum_skill_level:
		return 0.5  # Half effectiveness if under required level
	elif skill_level == minimum_skill_level:
		return 1.0  # Normal effectiveness at required level
	else:
		# Bonus effectiveness for higher skill
		return 1.0 + min((skill_level - minimum_skill_level) * 0.1, 0.5)  # Up to 50% bonus

func has_medical_skill(user) -> bool:
	if !requires_medical_skill:
		return true
	
	# Check skill level
	var skill_level = 0
	if user.has_method("get_skill_level"):
		skill_level = user.get_skill_level("medical")
	
	return skill_level >= minimum_skill_level

func should_be_consumed() -> bool:
	# Override in child classes as needed
	# By default, most medical items are consumed on use
	return true

func consume_item(user):
	# If we're in an inventory
	if inventory_owner != null:
		# Remove from inventory
		if inventory_owner.has_method("remove_item_from_inventory"):
			inventory_owner.remove_item_from_inventory(self)
	
	# Remove from scene
	queue_free()

func add_reagent(reagent_name: String, amount: float) -> float:
	if !has_reagents:
		return 0.0
	
	# Check if we have space
	var current_volume = get_total_reagent_volume()
	var available_space = reagent_max_volume - current_volume
	
	if available_space <= 0:
		return 0.0
	
	# Add reagent
	var amount_to_add = min(amount, available_space)
	
	if !reagents.has(reagent_name):
		reagents[reagent_name] = amount_to_add
	else:
		reagents[reagent_name] += amount_to_add
	
	# Update total volume
	reagent_volume += amount_to_add
	
	# Emit signal
	emit_signal("reagent_added", reagent_name, amount_to_add)
	
	return amount_to_add

func remove_reagent(reagent_name: String, amount: float) -> float:
	if !has_reagents or !reagents.has(reagent_name):
		return 0.0
	
	var available = reagents[reagent_name]
	var amount_to_remove = min(amount, available)
	
	reagents[reagent_name] -= amount_to_remove
	
	# Update total volume
	reagent_volume -= amount_to_remove
	
	# Remove key if depleted
	if reagents[reagent_name] <= 0:
		reagents.erase(reagent_name)
	
	# Emit signal
	emit_signal("reagent_removed", reagent_name, amount_to_remove)
	
	return amount_to_remove

func get_total_reagent_volume() -> float:
	if !has_reagents:
		return 0.0
	
	var total = 0.0
	for reagent in reagents:
		total += reagents[reagent]
	
	return total

func get_examine_text() -> String:
	var examine_text = get_examine_text()
	
	# Add medical information
	examine_text += "\n\nThis is a medical item."
	
	# Add healing information if applicable
	var healing_info = get_healing_info()
	if healing_info != "":
		examine_text += "\n" + healing_info
	
	# Add reagent information if applicable
	if has_reagents:
		var current_volume = get_total_reagent_volume()
		examine_text += "\nIt contains " + str(current_volume) + "/" + str(reagent_max_volume) + " units of reagents."
		
		# List reagents if not empty
		if !reagents.is_empty():
			examine_text += "\nReagents:"
			for reagent in reagents:
				examine_text += "\n- " + reagent + ": " + str(reagents[reagent]) + " units"
	
	# Add container information if applicable
	if is_container:
		examine_text += "\nIt can hold up to " + str(max_contents) + " items."
		
		# List contents if not empty
		if !contents.is_empty():
			examine_text += "\nContents:"
			for item in contents:
				examine_text += "\n- " + item.item_name
	
	return examine_text

# Get a string describing what this item heals
func get_healing_info() -> String:
	var info = ""
	var healing_types = []
	
	if heal_brute > 0:
		healing_types.append("physical trauma (" + str(heal_brute) + ")")
	if heal_burn > 0:
		healing_types.append("burns (" + str(heal_burn) + ")")
	if heal_toxin > 0:
		healing_types.append("toxins (" + str(heal_toxin) + ")")
	if heal_oxygen > 0:
		healing_types.append("oxygen deprivation (" + str(heal_oxygen) + ")")
	if heal_brain > 0:
		healing_types.append("brain damage (" + str(heal_brain) + ")")
	if heal_stamina > 0:
		healing_types.append("exhaustion (" + str(heal_stamina) + ")")
	if reduce_pain > 0:
		healing_types.append("pain (" + str(reduce_pain) + ")")
	if blood_restore > 0:
		healing_types.append("blood loss (" + str(blood_restore) + ")")
	if blood_clotting > 0:
		healing_types.append("bleeding")
	
	if healing_types.size() > 0:
		info = "Treats: " + ", ".join(healing_types)
	
	return info
