extends Node
class_name OrganSystem

# === SIGNALS ===
signal organ_damaged(organ_name, amount)
signal organ_healed(organ_name, amount)
signal organ_failure_started(organ_name)
signal organ_failure_ended(organ_name)
signal organ_removed(organ_name)
signal organ_added(organ_name)

# === CONSTANTS ===
const ORGAN_DAMAGE_THRESHOLD = 75  # % of damage before organ starts failing
const ORGAN_FAILURE_INTERVAL = 1.0  # Seconds between organ failure damage ticks
const ORGAN_HEAL_RATE = 0.05  # Base healing rate per second for organs

# Organ definitions
const ORGAN_SLOTS = {
	"heart": {
		"name": "Heart",
		"vital": true,
		"max_damage": 100.0,
		"description": "Pumps blood through the body, providing oxygen and nutrients to cells."
	},
	"lungs": {
		"name": "Lungs",
		"vital": true,
		"max_damage": 100.0,
		"description": "Extracts oxygen from the air and expels carbon dioxide."
	},
	"liver": {
		"name": "Liver",
		"vital": false,
		"max_damage": 100.0,
		"description": "Filters toxins from the blood and produces vital proteins."
	},
	"kidneys": {
		"name": "Kidneys",
		"vital": false,
		"max_damage": 100.0,
		"description": "Filters waste from the blood and regulates fluid balance."
	},
	"stomach": {
		"name": "Stomach",
		"vital": false,
		"max_damage": 100.0,
		"description": "Digests food and absorbs nutrients."
	},
	"intestines": {
		"name": "Intestines",
		"vital": false,
		"max_damage": 100.0,
		"description": "Processes food and absorbs nutrients."
	},
	"pancreas": {
		"name": "Pancreas",
		"vital": false,
		"max_damage": 100.0,
		"description": "Produces insulin and digestive enzymes."
	},
	"spleen": {
		"name": "Spleen",
		"vital": false,
		"max_damage": 100.0,
		"description": "Filters blood and supports immune system function."
	},
	"brain": {
		"name": "Brain",
		"vital": true,
		"max_damage": 120.0,
		"description": "Controls all body functions and houses consciousness."
	},
	"eyes": {
		"name": "Eyes",
		"vital": false,
		"max_damage": 50.0,
		"description": "Provides vision."
	}
}

# === MEMBER VARIABLES ===
var organs = {}  # Current organs in the body
var failure_timers = {}  # Timers for organ failure effects
var healing_paused = false  # Flag to pause natural healing
var replaced_organs = {}  # Tracking which organs have been replaced with prosthetics
var organic_species = true  # False for robots/synthetic species

# References to other systems
var entity = null  # The parent entity
var health_system = null
var blood_system = null  # Optional connection to blood system
var audio_system = null
var sprite_system = null

# === INITIALIZATION ===
func _ready():
	entity = get_parent()
	_find_systems()
	_initialize_organs()
	
	# Set up update timer
	var timer = Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_on_update_tick)
	add_child(timer)

func _find_systems():
	# Try to find health system
	health_system = entity.get_node_or_null("HealthSystem")
	
	# Try to find blood system
	blood_system = entity.get_node_or_null("BloodSystem")
	
	# Try to find audio system
	audio_system = entity.get_node_or_null("AudioSystem")
	
	# Try to find sprite system
	sprite_system = entity.get_node_or_null("SpriteSystem")
	
	print("OrganSystem: Connected to systems")
	print("  - Health: ", "Found" if health_system else "Not found")
	print("  - Blood: ", "Found" if blood_system else "Not found")
	print("  - Audio: ", "Found" if audio_system else "Not found")
	print("  - Sprite: ", "Found" if sprite_system else "Not found")

func _initialize_organs():
	# Create all standard organs unless species doesn't have them
	for slot in ORGAN_SLOTS:
		organs[slot] = {
			"name": ORGAN_SLOTS[slot].name,
			"damage": 0.0,
			"max_damage": ORGAN_SLOTS[slot].max_damage,
			"is_vital": ORGAN_SLOTS[slot].vital,
			"is_damaged": false,
			"is_failing": false,
			"is_robotic": false,
			"effects_active": false
		}
	
	# If non-organic, mark all organs as robotic
	if !organic_species:
		for slot in organs:
			organs[slot].is_robotic = true

# === PROCESS FUNCTIONS ===
func _process(delta):
	# Natural organ healing over time
	if !healing_paused:
		for slot in organs:
			var organ = organs[slot]
			
			# Skip if not damaged or robotic without repair
			if organ.damage <= 0 or (organ.is_robotic and !has_auto_repair()):
				continue
				
			# Calculate healing amount based on general health
			var heal_rate = ORGAN_HEAL_RATE
			
			# Health system bonus
			if health_system:
				var health_percent = health_system.health / health_system.max_health
				heal_rate *= max(0.2, health_percent)  # Heal slower when overall health is bad
			
			# Heal the organ
			heal_organ_damage(slot, heal_rate * delta)

func _on_update_tick():
	# Check all organs for failure effects
	for slot in organs:
		var organ = organs[slot]
		
		# Skip if not failing or already being processed
		if !organ.is_failing or organ.effects_active:
			continue
		
		# Start failure effects
		organ.effects_active = true
		process_organ_failure(slot)

# Process effects of organ failure
func process_organ_failure(slot):
	var organ = organs[slot]
	
	# Different effects based on which organ is failing
	match slot:
		"heart":
			# Heart failure causes cardiac arrest
			if blood_system:
				blood_system.enter_cardiac_arrest()
			
			# Oxygen loss without blood circulation
			if health_system:
				health_system.adjustOxyLoss(1.0)
		
		"lungs":
			# Lung failure causes oxygen loss
			if health_system:
				health_system.adjustOxyLoss(0.8)
			
			# Add visual and audio cues
			if audio_system:
				audio_system.play_sound("wheeze", 0.3)
			if sprite_system and sprite_system.has_method("show_breath_effect"):
				sprite_system.show_breath_effect(false)  # Labored breathing
		
		"liver":
			# Liver failure causes toxin build-up
			if health_system:
				health_system.adjustToxLoss(0.3)
			
			# Jaundice visual effect
			if sprite_system and sprite_system.has_method("set_jaundice"):
				sprite_system.set_jaundice(true)
			
			# Impaired drug processing would be handled elsewhere
		
		"kidneys":
			# Kidney failure causes toxin build-up and fluid retention
			if health_system:
				health_system.adjustToxLoss(0.2)
			
			# Edema effect
			if sprite_system and sprite_system.has_method("set_edema"):
				sprite_system.set_edema(true)
		
		"stomach", "intestines", "pancreas":
			# Digestive system failures
			# Slower nutrition processing would be handled by a nutrition system
			if health_system:
				health_system.adjustToxLoss(0.1)
		
		"spleen":
			# Spleen failure weakens immune response
			# This would connect to an immune system if implemented
			pass
		
		"brain":
			# Brain failure causes neurological effects and eventual death
			if health_system:
				health_system.adjustBrainLoss(0.2)
				
				# Apply mental effects based on brain damage
				var brain_damage_percent = organ.damage / organ.max_damage * 100
				
				if brain_damage_percent > 30:
					health_system.add_status_effect("confused", 5.0, brain_damage_percent / 30)
				
				if brain_damage_percent > 50:
					health_system.add_status_effect("slurred_speech", 5.0, brain_damage_percent / 50)
				
				if brain_damage_percent > 80:
					# Brain death
					health_system.die("brain death")
					
		"eyes":
			# Eye damage causes vision impairment
			if health_system:
				var blur_intensity = (organ.damage / organ.max_damage) * 5
				health_system.add_status_effect("blurred_vision", 2.0, blur_intensity)
	
	# Continue failure timer for next tick
	await get_tree().create_timer(ORGAN_FAILURE_INTERVAL).timeout
	
	# Only continue if the organ is still failing and we exist
	if is_instance_valid(self) and slot in organs and organs[slot].is_failing:
		# Clear active flag so it can be reprocessed in the next tick
		organs[slot].effects_active = false

# === ORGAN DAMAGE FUNCTIONS ===
# Apply damage to an organ
func apply_organ_damage(organ_slot, amount, source = "generic"):
	if !organs.has(organ_slot) or amount <= 0:
		return 0
	
	var organ = organs[organ_slot]
	var old_damage = organ.damage
	var old_failing = organ.is_failing
	
	# Calculate damage reduction for robotic organs
	if organ.is_robotic:
		amount *= 0.7  # Robotic organs take less damage
	
	# Apply damage
	organ.damage = min(organ.max_damage, organ.damage + amount)
	
	# Update status flags
	organ.is_damaged = organ.damage > 0
	organ.is_failing = organ.damage >= (organ.max_damage * (ORGAN_DAMAGE_THRESHOLD / 100.0))
	
	# Emit damage signal
	organ_damaged.emit(organ_slot, amount)
	
	# Handle vital organ failure
	if organ.is_vital and organ.is_failing and !old_failing:
		organ_failure_started.emit(organ_slot)
		
		# Apply damage to overall health if health system exists
		if health_system and organ_slot == "brain":
			# Brain damage affects brain loss value directly
			health_system.adjustBrainLoss(amount * 0.5)
		
		# Special handling for heart failure
		if organ_slot == "heart" and blood_system:
			blood_system.enter_cardiac_arrest()
		
		# Death if brain fails completely
		if organ_slot == "brain" and organ.damage >= organ.max_damage:
			if health_system:
				health_system.die("brain death")
	
	# Immediately start failure effects
	if organ.is_failing and !old_failing:
		organ.effects_active = false  # Will be set to true when processed
	
	# End failure if no longer failing
	if !organ.is_failing and old_failing:
		organ_failure_ended.emit(organ_slot)
		
		# Special handling for heart recovery
		if organ_slot == "heart" and blood_system:
			blood_system.exit_cardiac_arrest()
	
	return amount

# Heal organ damage
func heal_organ_damage(organ_slot, amount):
	if !organs.has(organ_slot) or amount <= 0:
		return 0
	
	var organ = organs[organ_slot]
	var old_damage = organ.damage
	var old_failing = organ.is_failing
	
	# Apply healing
	organ.damage = max(0, organ.damage - amount)
	
	# Update status flags
	organ.is_damaged = organ.damage > 0
	organ.is_failing = organ.damage >= (organ.max_damage * (ORGAN_DAMAGE_THRESHOLD / 100.0))
	
	# Calculate actual amount healed
	var healed_amount = old_damage - organ.damage
	
	# Only emit signal if actually healed
	if healed_amount > 0:
		organ_healed.emit(organ_slot, healed_amount)
	
	# End failure state if relevant
	if old_failing and !organ.is_failing:
		organ_failure_ended.emit(organ_slot)
		
		# Special handling for heart recovery
		if organ_slot == "heart" and blood_system:
			blood_system.exit_cardiac_arrest()
	
	return healed_amount

# Set organ damage directly
func set_organ_damage(organ_slot, amount):
	if !organs.has(organ_slot):
		return false
	
	var organ = organs[organ_slot]
	var old_damage = organ.damage
	var old_failing = organ.is_failing
	
	# Set damage value with clamping
	organ.damage = clamp(amount, 0, organ.max_damage)
	
	# Update status flags
	organ.is_damaged = organ.damage > 0
	organ.is_failing = organ.damage >= (organ.max_damage * (ORGAN_DAMAGE_THRESHOLD / 100.0))
	
	# Emit signals for significant changes
	if organ.damage > old_damage:
		organ_damaged.emit(organ_slot, organ.damage - old_damage)
	elif organ.damage < old_damage:
		organ_healed.emit(organ_slot, old_damage - organ.damage)
	
	# Handle failure state changes
	if !old_failing and organ.is_failing:
		organ_failure_started.emit(organ_slot)
	elif old_failing and !organ.is_failing:
		organ_failure_ended.emit(organ_slot)
	
	return true

# === ORGAN OPERATIONS ===
# Remove an organ
func remove_organ(organ_slot):
	if !organs.has(organ_slot):
		return false
	
	var organ = organs[organ_slot]
	
	# Store the organ data before removing
	var removed_organ = organ.duplicate()
	
	# Handle vital organ removal
	if organ.is_vital and health_system:
		# Vital organ removal is probably lethal
		if organ_slot == "brain":
			health_system.die("brain removal")
		elif organ_slot == "heart":
			# Cardiac arrest when heart is removed
			if blood_system:
				blood_system.enter_cardiac_arrest()
	
	# Handle non-vital organ removal
	else:
		# Apply significant damage from losing an organ
		if health_system:
			health_system.apply_damage(20, health_system.DamageType.BRUTE) 
	
	# Emit organ removed signal
	organ_removed.emit(organ_slot)
	
	# Remove from organs list
	organs.erase(organ_slot)
	
	return removed_organ

# Install a new organ (organic or prosthetic)
func install_organ(organ_slot, is_robotic = false, quality = 1.0):
	# If slot already has an organ, remove it first
	if organs.has(organ_slot):
		remove_organ(organ_slot)
	
	# Create the new organ
	var new_organ = {
		"name": ORGAN_SLOTS[organ_slot].name if ORGAN_SLOTS.has(organ_slot) else "Unknown Organ",
		"damage": 0.0,
		"max_damage": ORGAN_SLOTS[organ_slot].max_damage * quality if ORGAN_SLOTS.has(organ_slot) else 100.0,
		"is_vital": ORGAN_SLOTS[organ_slot].vital if ORGAN_SLOTS.has(organ_slot) else false,
		"is_damaged": false,
		"is_failing": false,
		"is_robotic": is_robotic,
		"effects_active": false
	}
	
	# Add the organ
	organs[organ_slot] = new_organ
	
	# Track if an organ was replaced with a prosthetic
	if is_robotic:
		replaced_organs[organ_slot] = true
	
	# Emit organ added signal
	organ_added.emit(organ_slot)
	
	# Special handling for vital organs
	if organ_slot == "heart" and blood_system and blood_system.in_cardiac_arrest:
		# New heart should restart circulation
		blood_system.exit_cardiac_arrest()
	
	return true

# Repair robotic organ
func repair_organ(organ_slot, amount):
	if !organs.has(organ_slot):
		return 0
	
	var organ = organs[organ_slot]
	
	# Only robotic organs can be repaired
	if !organ.is_robotic:
		return 0
	
	# Use heal function but with special handling for robotic repairs
	return heal_organ_damage(organ_slot, amount)

# === UTILITY FUNCTIONS ===
# Check if entity has a functioning heart
func has_functioning_heart():
	return organs.has("heart") and !organs["heart"].is_failing

# Check if entity has a functioning brain
func has_functioning_brain():
	return organs.has("brain") and !organs["brain"].is_failing

# Check if entity has functioning lungs
func has_functioning_lungs():
	return organs.has("lungs") and !organs["lungs"].is_failing

# Check if entity has auto-repair capabilities
func has_auto_repair():
	# If species is synthetic or has enough robotic organs
	if !organic_species:
		return true
	
	# Count how many robotic organs we have
	var robotic_count = 0
	for slot in organs:
		if organs[slot].is_robotic:
			robotic_count += 1
	
	# If more than half are robotic, we have auto-repair
	return robotic_count >= organs.size() / 2

# Get organ status for medical scanners
func get_organ_status(organ_slot):
	if !organs.has(organ_slot):
		return null
	
	var organ = organs[organ_slot]
	
	return {
		"name": organ.name,
		"damage": organ.damage,
		"max_damage": organ.max_damage,
		"damage_percent": (organ.damage / organ.max_damage) * 100,
		"is_damaged": organ.is_damaged,
		"is_failing": organ.is_failing,
		"is_robotic": organ.is_robotic,
		"is_vital": organ.is_vital,
		"status": get_organ_status_description(organ_slot),
		"description": ORGAN_SLOTS[organ_slot].description if ORGAN_SLOTS.has(organ_slot) else ""
	}

# Get all organ statuses for medical display
func get_all_organ_statuses():
	var statuses = {}
	
	for slot in organs:
		statuses[slot] = get_organ_status(slot)
	
	return statuses

# Get text description of organ status
func get_organ_status_description(organ_slot):
	if !organs.has(organ_slot):
		return "missing"
	
	var organ = organs[organ_slot]
	var damage_percent = (organ.damage / organ.max_damage) * 100
	
	if damage_percent >= ORGAN_DAMAGE_THRESHOLD:
		return "failing" + (" (robotic)" if organ.is_robotic else "")
	elif damage_percent >= 50:
		return "severely damaged" + (" (robotic)" if organ.is_robotic else "")
	elif damage_percent >= 25:
		return "damaged" + (" (robotic)" if organ.is_robotic else "")
	elif damage_percent > 0:
		return "bruised" + (" (robotic)" if organ.is_robotic else "")
	else:
		return "healthy" + (" (robotic)" if organ.is_robotic else "")

# For revival and healing
func restore_all_organs():
	for slot in organs:
		set_organ_damage(slot, 0)
	
	return true

# Process specific damage types on organs
func process_toxin_damage(amount):
	# Liver takes the brunt of toxin damage
	if organs.has("liver"):
		apply_organ_damage("liver", amount * 0.5)
	
	# Kidneys also affected
	if organs.has("kidneys"):
		apply_organ_damage("kidneys", amount * 0.3)
	
	# Other organs take minor damage
	if organs.has("heart"):
		apply_organ_damage("heart", amount * 0.1)
	
	if organs.has("lungs"):
		apply_organ_damage("lungs", amount * 0.1)
