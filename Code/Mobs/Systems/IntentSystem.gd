extends Node
class_name IntentSystem

# === SIGNALS ===
signal intent_changed(new_intent, old_intent)
signal grab_state_changed(new_state, grabbed_entity)
signal grab_upgraded(entity, new_state)
signal grab_downgraded(entity, new_state)
signal grab_released(entity)
signal disarm_attempted(target, success)
signal help_attempted(target, success)
signal harm_attempted(target, damage, zone)

# === CONSTANTS ===
# Intent constants
enum Intent {
	HELP = 0,
	DISARM = 1,
	GRAB = 2,
	HARM = 3
}

# Grab states
enum GrabState {
	NONE = 0,
	PASSIVE = 1,  # Just pulling
	AGGRESSIVE = 2,  # Restrains movement somewhat
	NECK = 3,  # Restrains movement significantly
	KILL = 4  # Strangling
}

# Interaction range
const MAX_INTERACTION_RANGE = 1.5  # Tiles
const GRAB_COOLDOWN = 2.0  # Seconds between grab upgrades
const DISARM_BASE_CHANCE = 60.0  # Base disarm chance

# === MEMBER VARIABLES ===
# Current intent
var current_intent: int = Intent.HELP
var previous_intent: int = Intent.HELP

# Grab-related variables
var grab_state: int = GrabState.NONE
var grabbed_entity = null
var last_grab_upgrade_time: float = 0.0
var grab_time: float = 0.0  # Time the grab has been active
var grab_resist_progress: float = 0.0
var strangulation_damage: float = 0.0  # Damage applied per second during KILL grab

# References
var entity = null  # The parent entity
var controller = null  # GridMovementController
var health_system = null
var limb_system = null
var audio_system = null
var sensory_system = null

# === INITIALIZATION ===
func _ready():
	# Get parent entity
	entity = get_parent()
	
	# Find the controller
	controller = entity.get_node_or_null("GridMovementController")
	if !controller:
		push_error("IntentSystem: Failed to find GridMovementController")
	
	# Find other systems
	health_system = entity.get_node_or_null("HealthSystem")
	limb_system = entity.get_node_or_null("LimbSystem")
	audio_system = entity.get_node_or_null("AudioSystem")
	sensory_system = entity.get_node_or_null("SensorySystem")
	
	# Connect signals
	if controller:
		if !controller.is_connected("intent_changed", Callable(self, "_on_intent_changed")):
			controller.connect("intent_changed", Callable(self, "_on_intent_changed"))
	
	print("IntentSystem: Initialized")

# === PROCESS ===
func _process(delta):
	# Process grab effects if we have a grabbed entity
	if grabbed_entity and grab_state > GrabState.NONE:
		process_grab_effects(delta)

# === INTENT MANAGEMENT ===
# Set current intent
func set_intent(new_intent: int):
	if new_intent < 0 or new_intent > 3:
		return false
		
	if new_intent == current_intent:
		return true
		
	previous_intent = current_intent
	current_intent = new_intent
	
	# Update controller if it exists
	if controller and controller.has_method("set_intent"):
		controller.set_intent(new_intent)
	
	# Emit signal
	intent_changed.emit(current_intent, previous_intent)
	
	# If we were grabbing someone and switched away from GRAB intent, consider releasing
	if previous_intent == Intent.GRAB and current_intent != Intent.GRAB:
		if grab_state <= GrabState.PASSIVE:  # Only auto-release for passive grabs
			release_grab()
	
	return true

# Cycle intents
func cycle_intent():
	var new_intent = (current_intent + 1) % 4
	return set_intent(new_intent)

# Get intent name
func get_intent_name(intent_value = -1):
	if intent_value == -1:
		intent_value = current_intent
		
	match intent_value:
		Intent.HELP: return "help"
		Intent.DISARM: return "disarm"
		Intent.GRAB: return "grab"
		Intent.HARM: return "harm"
		_: return "unknown"

# === HELP INTENT ===
# Process help intent on target
func handle_help(target):
	if !is_valid_target(target):
		return false
	
	# Check what type of entity this is
	if "entity_type" in target:
		match target.entity_type:
			"item":
				return pick_up_item(target)
			"character":
				return help_character(target)
			"door":
				return open_door(target)
			"machine":
				return use_machine(target)
	
	# Generic help interaction
	if target.has_method("interact"):
		target.interact(entity)
		return true
		
	# If we have an active item, try to use it on the target
	var active_item = get_active_item()
	if active_item:
		if target.has_method("use_item_on"):
			return target.use_item_on(active_item, entity)
	
	return false

# Try to pick up an item
func pick_up_item(item):
	if !controller:
		return false
		
	if controller.has_method("try_pick_up_item"):
		return controller.try_pick_up_item(item)
	
	return false

# Help a character (heal, revive, etc.)
func help_character(character):
	# If we have a medical item in our active hand, use it on them
	var active_item = get_active_item()
	if active_item:
		if "is_medical" in active_item and active_item.is_medical:
			if character.has_method("apply_medical_item"):
				return character.apply_medical_item(active_item, entity)
	
	# Check if they're down and need revival
	if character.has_method("is_down") and character.is_down():
		return attempt_revival(character)
	
	# Default interaction if still alive and well
	if sensory_system:
		sensory_system.display_message("You gently pat " + character.entity_name + ".")
		
	# Play interaction sound
	if audio_system:
		audio_system.play_positioned_sound("interact", entity.position, 0.3)
	
	return true

# Attempt to revive a downed character
func attempt_revival(character):
	if !health_system or !character.has_method("revive"):
		return false
		
	# CPR attempt
	if sensory_system:
		sensory_system.display_message("You attempt to revive " + character.entity_name + "...")
		
	# Play CPR sound
	if audio_system:
		audio_system.play_positioned_sound("cpr", entity.position, 0.5)
	
	# Simple success check
	var success_chance = 30.0  # Base chance
	
	# Medical skill would improve this
	if "skills" in entity and entity.skills.has_method("get_skill_level"):
		var medical_skill = entity.skills.get_skill_level("medical")
		success_chance += medical_skill * 10
	
	if randf() * 100 < success_chance:
		# Successful CPR
		if character.has_method("apply_cpr_effect"):
			character.apply_cpr_effect(entity)
			
		if sensory_system:
			sensory_system.display_message(character.entity_name + " gasps!")
		
		help_attempted.emit(character, true)
		return true
	else:
		if sensory_system:
			sensory_system.display_message("Your attempt has no effect.")
		
		help_attempted.emit(character, false)
		return false

# Open a door
func open_door(door):
	if door.has_method("toggle"):
		door.toggle(entity)
		return true
	
	return false

# Use a machine
func use_machine(machine):
	if machine.has_method("interact"):
		machine.interact(entity)
		return true
	
	return false

# === DISARM INTENT ===
# Process disarm intent on target
func handle_disarm(target):
	if !is_valid_target(target):
		return false
	
	# Can only disarm characters
	if !("entity_type" in target) or target.entity_type != "character":
		if sensory_system:
			sensory_system.display_message("You can't disarm that!")
		return false
	
	# Check if target is in grab range
	if !is_in_range(target, MAX_INTERACTION_RANGE):
		if sensory_system:
			sensory_system.display_message("You're too far away to disarm " + target.entity_name + "!")
		return false
	
	# Calculate disarm chance
	var disarm_chance = DISARM_BASE_CHANCE
	
	# Apply dexterity bonus
	if "dexterity" in entity:
		disarm_chance += entity.dexterity * 2
	
	# Target size affects difficulty
	if "mob_size" in target:
		disarm_chance -= (target.mob_size - entity.mob_size) * 10
	
	# Apply target's skill modifier if they have one
	if target.has_method("get_disarm_resist"):
		disarm_chance -= target.get_disarm_resist()
	
	# Roll for success
	var success = randf() * 100 < disarm_chance
	
	# Apply disarm effects
	if success:
		disarm_success(target)
	else:
		disarm_failure(target)
	
	# Emit signal
	disarm_attempted.emit(target, success)
	
	return success

# Handle successful disarm
func disarm_success(target):
	# Show message
	if sensory_system:
		sensory_system.display_message("You disarm " + target.entity_name + "!")
	
	# Play sound
	if audio_system:
		audio_system.play_positioned_sound("disarm", entity.position, 0.5)
	
	# Get active item from target
	var dropped_item = null
	if target.has_method("get_active_item"):
		dropped_item = target.get_active_item()
	
	# Make them drop it
	if dropped_item:
		if target.has_method("drop_active_item"):
			target.drop_active_item()
		elif target.has_method("drop_item"):
			target.drop_item(dropped_item)
	
	# Chance to stun or knockdown
	var knock_chance = 20.0
	
	# Skill would improve chance
	if "skills" in entity and entity.skills.has_method("get_skill_level"):
		var combat_skill = entity.skills.get_skill_level("cqc")
		knock_chance += combat_skill * 5
	
	if randf() * 100 < knock_chance:
		# Apply stun to target
		if target.has_method("apply_effect"):
			target.apply_effect("stun", 2.0)
			
			if sensory_system:
				sensory_system.display_message(target.entity_name + " staggers!")

# Handle failed disarm
func disarm_failure(target):
	# Show message
	if sensory_system:
		sensory_system.display_message("You try to disarm " + target.entity_name + " but fail!")
	
	# Play sound
	if audio_system:
		audio_system.play_positioned_sound("miss", entity.position, 0.3)
	
	# Chance for target to counter
	var counter_chance = 15.0
	
	if target.has_method("get_counter_chance"):
		counter_chance = target.get_counter_chance()
	
	if randf() * 100 < counter_chance:
		# Target counters!
		if sensory_system:
			sensory_system.display_message(target.entity_name + " counters your disarm attempt!")
		
		# They might grab or strike back
		if target.has_method("handle_counter"):
			target.handle_counter(entity, "disarm")

# === GRAB INTENT ===
# Process grab intent on target
func handle_grab(target):
	if !is_valid_target(target):
		return false
	
	# Already grabbing someone else?
	if grabbed_entity and grabbed_entity != target:
		release_grab()
	
	# Already grabbing this target? Try to upgrade
	if grabbed_entity == target:
		return upgrade_grab()
	
	# Check if we can grab this target
	if !can_grab_entity(target):
		return false
	
	# Start new grab
	return grab_entity(target)

# Check if an entity can be grabbed
func can_grab_entity(target):
	# Check if valid target
	if !is_valid_target(target):
		return false
	
	# Check if target is in grab range
	if !is_in_range(target, MAX_INTERACTION_RANGE):
		if sensory_system:
			sensory_system.display_message("You're too far away to grab " + target.entity_name + "!")
		return false
	
	# Can't grab yourself
	if target == entity:
		return false
	
	# Check if the entity is too big
	if "mob_size" in target and "mob_size" in entity:
		if target.mob_size > entity.mob_size + 1:
			if sensory_system:
				sensory_system.display_message(target.entity_name + " is too big to grab!")
			return false
	
	# Check for no_grab flag
	if "no_grab" in target and target.no_grab:
		if sensory_system:
			sensory_system.display_message("You can't grab " + target.entity_name + "!")
		return false
	
	return true

# Grab an entity
func grab_entity(target, initial_state: int = GrabState.PASSIVE):
	# Safety checks
	if !can_grab_entity(target):
		return false
	
	# Set grab state and grabbed entity
	grab_state = initial_state
	grabbed_entity = target
	grab_time = 0.0
	last_grab_upgrade_time = Time.get_ticks_msec() / 1000.0
	
	# Tell the target they've been grabbed
	if grabbed_entity.has_method("set_grabbed_by"):
		grabbed_entity.set_grabbed_by(entity, grab_state)
	
	# Start pulling automatically for passive grabs
	if grab_state == GrabState.PASSIVE and controller and controller.has_method("pull_entity"):
		controller.pull_entity(target)
	
	# Play grab sound
	if audio_system:
		audio_system.play_positioned_sound("grab", entity.position, 0.3)
	
	# Show message
	if sensory_system:
		match grab_state:
			GrabState.PASSIVE:
				sensory_system.display_message("You passively grab " + target.entity_name + ".")
			GrabState.AGGRESSIVE:
				sensory_system.display_message("You aggressively grab " + target.entity_name + "!")
	
	# Emit signal
	grab_state_changed.emit(grab_state, target)
	
	return true

# Upgrade grab to next level
func upgrade_grab():
	# Check if we have a grabbed entity
	if !grabbed_entity:
		return false
	
	# Check cooldown
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_grab_upgrade_time < GRAB_COOLDOWN:
		if sensory_system:
			sensory_system.display_message("You need to wait before upgrading your grab!")
		return false
	
	# Can't upgrade beyond kill
	if grab_state >= GrabState.KILL:
		return false
	
	# Update cooldown time
	last_grab_upgrade_time = current_time
	
	# Calculate upgrade success chance
	var upgrade_chance = 70.0
	
	# Apply strength/dexterity bonus
	if "strength" in entity:
		upgrade_chance += entity.strength * 1.5
	
	if "dexterity" in entity:
		upgrade_chance += entity.dexterity * 1.5
	
	# Size difference affects upgrade chance
	if "mob_size" in grabbed_entity and "mob_size" in entity:
		upgrade_chance -= (grabbed_entity.mob_size - entity.mob_size) * 15
	
	# Roll for success
	if randf() * 100 < upgrade_chance:
		# Success - upgrade grab
		var old_state = grab_state
		grab_state += 1
		grab_time = 0.0  # Reset grab time
		
		# If upgrading from passive, stop pulling
		if old_state == GrabState.PASSIVE and controller and controller.has_method("stop_pulling"):
			controller.stop_pulling()
		
		# Tell the grabbed entity grab was upgraded
		if grabbed_entity.has_method("set_grabbed_by"):
			grabbed_entity.set_grabbed_by(entity, grab_state)
		
		# Play sound based on new grab state
		if audio_system:
			match grab_state:
				GrabState.AGGRESSIVE:
					audio_system.play_positioned_sound("grab_tighten", entity.position, 0.4)
				GrabState.NECK:
					audio_system.play_positioned_sound("grab_neck", entity.position, 0.5)
				GrabState.KILL:
					audio_system.play_positioned_sound("choke", entity.position, 0.6)
		
		# Show message
		if sensory_system:
			match grab_state:
				GrabState.AGGRESSIVE:
					sensory_system.display_message("Your grip tightens!")
				GrabState.NECK:
					sensory_system.display_message("You grab the neck!")
				GrabState.KILL:
					sensory_system.display_message("You start to strangle!")
		
		# Emit signal
		grab_upgraded.emit(grabbed_entity, grab_state)
		grab_state_changed.emit(grab_state, grabbed_entity)
		
		return true
	else:
		# Failed to upgrade - release grab entirely
		if sensory_system:
			sensory_system.display_message("You fumble and release your grab!")
		
		release_grab()
		return false

# Downgrade grab to previous level
func downgrade_grab():
	# Check if we have a grabbed entity
	if !grabbed_entity:
		return false
	
	# Can't downgrade below passive
	if grab_state <= GrabState.PASSIVE:
		return false
	
	# Downgrade grab state
	var old_state = grab_state
	grab_state -= 1
	
	# If downgrading to passive, start pulling again
	if grab_state == GrabState.PASSIVE and controller and controller.has_method("pull_entity"):
		controller.pull_entity(grabbed_entity)
	
	# Tell the grabbed entity grab was downgraded
	if grabbed_entity.has_method("set_grabbed_by"):
		grabbed_entity.set_grabbed_by(entity, grab_state)
	
	# Show message
	if sensory_system:
		sensory_system.display_message("You loosen your grip.")
	
	# Emit signal
	grab_downgraded.emit(grabbed_entity, grab_state)
	grab_state_changed.emit(grab_state, grabbed_entity)
	
	return true

# Release the current grab
func release_grab():
	# Check if we have a grabbed entity
	if !grabbed_entity:
		return false
	
	# Stop pulling if we were
	if controller and controller.has_method("stop_pulling"):
		controller.stop_pulling()
	
	# Tell the grabbed entity they're no longer grabbed
	if grabbed_entity.has_method("set_grabbed_by"):
		grabbed_entity.set_grabbed_by(null, GrabState.NONE)
	
	# Play release sound
	if audio_system:
		audio_system.play_positioned_sound("release", entity.position, 0.3)
	
	# Emit signal before clearing
	grab_released.emit(grabbed_entity)
	
	# Clear grab variables
	var old_entity = grabbed_entity
	grabbed_entity = null
	grab_state = GrabState.NONE
	grab_time = 0.0
	grab_resist_progress = 0.0
	
	# Show message
	if sensory_system:
		sensory_system.display_message("You release your grab.")
	
	# Emit signal
	grab_state_changed.emit(GrabState.NONE, null)
	
	return true

# Process grab effects during physics update
func process_grab_effects(delta):
	if !grabbed_entity:
		return
	
	# Increment grab time
	grab_time += delta
	
	# Process effects based on grab state
	match grab_state:
		GrabState.NECK:
			# Slow stun buildup for neck grab
			if grabbed_entity.has_method("apply_effect"):
				grabbed_entity.apply_effect("muffled", 2.0)
				
			# Make it harder to speak
			if grabbed_entity.has_method("set_muffled"):
				grabbed_entity.set_muffled(true)
		
		GrabState.KILL:
			# Apply damage every second
			strangulation_damage += delta * 2.0  # Damage builds up over time
			
			if strangulation_damage >= 1.0:
				# Apply damage in 1-point increments
				if grabbed_entity.has_method("apply_damage"):
					grabbed_entity.apply_damage(1.0, "asphyxiation")
					strangulation_damage -= 1.0
				
				# Play choking sound
				if audio_system and fmod(grab_time, 2.0) < delta:
					audio_system.play_positioned_sound("choking", entity.position, 0.4)
			
			# Prevent speaking entirely
			if grabbed_entity.has_method("set_muffled"):
				grabbed_entity.set_muffled(true, 2.0)  # Completely muffled
			
			# Apply oxygen loss
			if grabbed_entity.has_method("adjustOxyLoss"):
				grabbed_entity.adjustOxyLoss(3.0 * delta)

# === HARM INTENT ===
# Process harm intent on target
func handle_harm(target):
	if !is_valid_target(target):
		return false
	
	# Check range
	if !is_in_range(target, MAX_INTERACTION_RANGE):
		if sensory_system:
			sensory_system.display_message("You're too far away to attack " + target.entity_name + "!")
		return false
	
	# Get active item
	var active_item = get_active_item()
	
	# Get target zone
	var target_zone = "chest"  # Default
	if controller and controller.has_method("get_target_zone"):
		target_zone = controller.get_target_zone()
	
	# Attack with weapon if we have one
	if active_item and active_item.has_method("attack"):
		return attack_with_weapon(target, active_item, target_zone)
	else:
		# Unarmed attack
		return attack_unarmed(target, target_zone)

# Attack with a weapon
func attack_with_weapon(target, weapon, zone):
	# Calculate weapon damage
	var damage = 0.0
	var damage_type = "brute"
	
	if "damage" in weapon:
		damage = weapon.damage
	
	if "damage_type" in weapon:
		damage_type = weapon.damage_type
	
	# Apply damage
	if target.has_method("apply_zone_damage"):
		target.apply_zone_damage(zone, damage, damage_type, entity)
	elif target.has_method("apply_damage"):
		target.apply_damage(damage, damage_type)
	
	# Play attack sound
	if weapon.has_method("get_attack_sound"):
		var sound = weapon.get_attack_sound()
		if audio_system:
			audio_system.play_positioned_sound(sound, entity.position, 0.5)
	elif audio_system:
		audio_system.play_positioned_sound("weapon_hit", entity.position, 0.5)
	
	# Show message
	if sensory_system:
		sensory_system.display_message("You attack " + target.entity_name + " with " + weapon.item_name + "!")
	
	# Emit signal
	harm_attempted.emit(target, damage, zone)
	
	return true

# Unarmed attack
func attack_unarmed(target, zone):
	# Base unarmed damage
	var damage = 5.0
	
	# Adjust damage based on strength
	if "strength" in entity:
		damage += (entity.strength - 10) * 0.2  # +/- 20% per strength point from baseline
	
	# Get zone modifiers
	var zone_mult = 1.0
	if controller and controller.has_method("get_zone_effects"):
		var effects = controller.get_zone_effects(zone)
		if effects.has("damage_multiplier"):
			zone_mult = effects.damage_multiplier
	
	# Apply zone multiplier
	damage *= zone_mult
	
	# Apply damage
	if target.has_method("apply_zone_damage"):
		target.apply_zone_damage(zone, damage, "brute", entity)
	elif target.has_method("apply_damage"):
		target.apply_damage(damage, "brute")
	
	# Play punch sound
	if audio_system:
		audio_system.play_positioned_sound("punch", entity.position, 0.5)
	
	# Show message
	if sensory_system:
		sensory_system.display_message("You punch " + target.entity_name + " in the " + zone + "!")
	
	# Apply additional zone effects
	if controller and controller.has_method("apply_zone_effects"):
		controller.apply_zone_effects(target, damage, zone)
	
	# Emit signal
	harm_attempted.emit(target, damage, zone)
	
	return true

# === UTILITY FUNCTIONS ===
# Get the entity's active item
func get_active_item():
	if controller and controller.has_method("get_active_item"):
		return controller.get_active_item()
	
	return null

# Check if entity is in range
func is_in_range(target, max_range):
	if !target:
		return false
	
	var distance = 0.0
	
	if "position" in target and "position" in entity:
		distance = entity.position.distance_to(target.position) / 32.0  # Convert pixels to tiles
	elif controller and controller.has_method("is_adjacent_to"):
		return controller.is_adjacent_to(target)
	
	return distance <= max_range

# Check if target is valid for interaction
func is_valid_target(target):
	if !target:
		return false
	
	# Check if target is destroyed or invalid
	if target.has_method("is_queued_for_deletion") and target.is_queued_for_deletion():
		return false
	
	return true

# Receive signal from controller when intent changes
func _on_intent_changed(new_intent):
	previous_intent = current_intent
	current_intent = new_intent
	
	# Emit our own signal
	intent_changed.emit(current_intent, previous_intent)

# Process interaction based on current intent
func process_interaction(target):
	if !is_valid_target(target):
		return false
	
	# Perform action based on current intent
	match current_intent:
		Intent.HELP:
			return handle_help(target)
		Intent.DISARM:
			return handle_disarm(target)
		Intent.GRAB:
			return handle_grab(target)
		Intent.HARM:
			return handle_harm(target)
	
	return false
