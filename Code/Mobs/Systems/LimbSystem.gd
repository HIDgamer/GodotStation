extends Node
class_name LimbSystem

# === SIGNALS ===
signal limb_damaged(limb_name, damage_type, amount)
signal limb_healed(limb_name, amount)
signal limb_status_changed(limb_name, new_status)
signal limb_dismembered(limb_name)
signal limb_attached(limb_name, is_prosthetic)

# === CONSTANTS AND ENUMS ===
enum LimbStatus {
	NORMAL,
	WOUNDED,
	MANGLED,
	DISMEMBERED
}

enum WoundType {
	BRUISE,
	CUT,
	BURN,
	PUNCTURE,
	FRACTURE
}

# Wound size categories
enum WoundSize {
	SMALL,
	MEDIUM,
	LARGE,
	CRITICAL
}

# Limb definitions with their connection hierarchy
const LIMB_DATA = {
	"head": {
		"name": "Head",
		"parent": "chest",
		"vital": true,
		"max_damage": 100.0,
		"max_wounds": 4,
		"dismemberment_threshold": 85,  # % of damage before dismemberment is possible
		"damage_multiplier": 1.5,
		"children": [],
		"contains_organs": ["brain", "eyes"]
	},
	"chest": {
		"name": "Chest",
		"parent": null,  # No parent, this is the core
		"vital": true,
		"max_damage": 150.0,
		"max_wounds": 6,
		"dismemberment_threshold": 100,  # Cannot be dismembered
		"damage_multiplier": 1.0,
		"children": ["head", "l_arm", "r_arm", "groin"],
		"contains_organs": ["heart", "lungs", "liver"]
	},
	"groin": {
		"name": "Groin",
		"parent": "chest",
		"vital": false,
		"max_damage": 100.0,
		"max_wounds": 4,
		"dismemberment_threshold": 85,
		"damage_multiplier": 1.0,
		"children": ["l_leg", "r_leg"],
		"contains_organs": ["kidneys", "intestines"]
	},
	"l_arm": {
		"name": "Left Arm",
		"parent": "chest",
		"vital": false,
		"max_damage": 75.0,
		"max_wounds": 3,
		"dismemberment_threshold": 70,
		"damage_multiplier": 0.8,
		"children": ["l_hand"],
		"contains_organs": []
	},
	"r_arm": {
		"name": "Right Arm",
		"parent": "chest",
		"vital": false,
		"max_damage": 75.0,
		"max_wounds": 3,
		"dismemberment_threshold": 70,
		"damage_multiplier": 0.8,
		"children": ["r_hand"],
		"contains_organs": []
	},
	"l_hand": {
		"name": "Left Hand",
		"parent": "l_arm",
		"vital": false,
		"max_damage": 50.0,
		"max_wounds": 2,
		"dismemberment_threshold": 65,
		"damage_multiplier": 0.7,
		"children": [],
		"contains_organs": []
	},
	"r_hand": {
		"name": "Right Hand",
		"parent": "r_arm",
		"vital": false,
		"max_damage": 50.0,
		"max_wounds": 2,
		"dismemberment_threshold": 65,
		"damage_multiplier": 0.7,
		"children": [],
		"contains_organs": []
	},
	"l_leg": {
		"name": "Left Leg",
		"parent": "groin",
		"vital": false,
		"max_damage": 75.0,
		"max_wounds": 3,
		"dismemberment_threshold": 70,
		"damage_multiplier": 0.8,
		"children": ["l_foot"],
		"contains_organs": []
	},
	"r_leg": {
		"name": "Right Leg",
		"parent": "groin",
		"vital": false,
		"max_damage": 75.0,
		"max_wounds": 3,
		"dismemberment_threshold": 70,
		"damage_multiplier": 0.8,
		"children": ["r_foot"],
		"contains_organs": []
	},
	"l_foot": {
		"name": "Left Foot",
		"parent": "l_leg",
		"vital": false,
		"max_damage": 50.0,
		"max_wounds": 2,
		"dismemberment_threshold": 65,
		"damage_multiplier": 0.7,
		"children": [],
		"contains_organs": []
	},
	"r_foot": {
		"name": "Right Foot",
		"parent": "r_leg",
		"vital": false,
		"max_damage": 50.0,
		"max_wounds": 2,
		"dismemberment_threshold": 65,
		"damage_multiplier": 0.7,
		"children": [],
		"contains_organs": []
	}
}

# === MEMBER VARIABLES ===
var limbs = {}  # Current limbs and their state
var dismembered_limbs = {}  # Tracking which limbs have been dismembered
var attached_prosthetics = {}  # Tracking which limbs have prosthetics
var wounds = {}  # Detailed wounds on each limb
var wound_counter = 0  # For assigning unique IDs to wounds
var limb_movement_penalties = {}  # Movement penalties for damaged limbs
var natural_healing_rate = 0.02  # Base healing per second

# References to other systems
var entity = null  # The parent entity
var health_system = null
var blood_system = null
var organ_system = null
var audio_system = null
var sprite_system = null

# === INITIALIZATION ===
func _ready():
	entity = get_parent()
	_find_systems()
	_initialize_limbs()
	
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
	
	# Try to find organ system
	organ_system = entity.get_node_or_null("OrganSystem")
	
	# Try to find audio system
	audio_system = entity.get_node_or_null("AudioSystem")
	
	# Try to find sprite system
	sprite_system = entity.get_node_or_null("SpriteSystem")
	
	print("LimbSystem: Connected to systems")
	print("  - Health: ", "Found" if health_system else "Not found")
	print("  - Blood: ", "Found" if blood_system else "Not found")
	print("  - Organ: ", "Found" if organ_system else "Not found")
	print("  - Audio: ", "Found" if audio_system else "Not found")
	print("  - Sprite: ", "Found" if sprite_system else "Not found")

func _initialize_limbs():
	# Create standard limbs
	for limb_name in LIMB_DATA:
		limbs[limb_name] = {
			"name": LIMB_DATA[limb_name].name,
			"brute_damage": 0.0,
			"burn_damage": 0.0,
			"max_damage": LIMB_DATA[limb_name].max_damage,
			"status": LimbStatus.NORMAL,
			"is_vital": LIMB_DATA[limb_name].vital,
			"is_prosthetic": false,
			"is_splinted": false,
			"is_bleeding": false,
			"bleeding_rate": 0.0,
			"wound_count": 0,
			"attached": true
		}
		
		# Initialize wounds container
		wounds[limb_name] = []

# === PROCESS FUNCTIONS ===
func _process(delta):
	# Process limb healing
	process_limb_healing(delta)
	
	# Process bleeding from wounded limbs
	process_limb_bleeding(delta)
	
	# Process movement penalties
	process_movement_penalties()

func _on_update_tick():
	# Process wound effects
	process_wound_effects()

# Natural limb healing over time
func process_limb_healing(delta):
	for limb_name in limbs:
		var limb = limbs[limb_name]
		
		# Skip if not damaged or dismembered
		if (limb.brute_damage <= 0 and limb.burn_damage <= 0) or !limb.attached:
			continue
		
		# Calculate healing amount based on overall health
		var heal_rate = natural_healing_rate
		if health_system:
			var health_percent = health_system.health / health_system.max_health
			heal_rate *= max(0.2, health_percent) # Heal slower when overall health is bad
		
		# Prosthetic limbs heal differently
		if limb.is_prosthetic:
			# Prosthetics don't heal naturally unless entity has auto-repair
			if organ_system and organ_system.has_auto_repair():
				heal_limb_damage(limb_name, heal_rate * 2 * delta, 0)  # Faster brute repair
				heal_limb_damage(limb_name, 0, heal_rate * delta)  # Slower burn repair
		else:
			# Organic limbs heal naturally
			heal_limb_damage(limb_name, heal_rate * delta, heal_rate * 0.5 * delta)
			
			# Healing wounds (small chance to heal a wound per tick)
			if limb.wound_count > 0 and randf() < heal_rate * 10 * delta:
				heal_random_wound(limb_name)

# Process bleeding from wounded limbs
func process_limb_bleeding(delta):
	if !blood_system:
		return
	
	var total_bleeding = 0.0
	
	for limb_name in limbs:
		var limb = limbs[limb_name]
		
		# Skip if not bleeding or dismembered
		if !limb.is_bleeding or !limb.attached:
			continue
		
		# Add to total bleeding
		total_bleeding += limb.bleeding_rate
		
		# Chance for blood splatter based on bleeding rate
		if randf() < limb.bleeding_rate * 0.2 * delta:
			blood_system.create_blood_splatter(1)
	
	# Apply total bleeding to blood system
	if total_bleeding > 0:
		blood_system.set_bleeding_rate(total_bleeding)
	else:
		blood_system.set_bleeding_rate(0)

# Process wound special effects
func process_wound_effects():
	for limb_name in wounds:
		for wound in wounds[limb_name]:
			match wound.type:
				WoundType.BURN:
					# Burns can cause pain and infection
					if wound.size >= WoundSize.MEDIUM and randf() < 0.1:
						if health_system:
							health_system.add_status_effect("pain", 5.0, wound.size * 0.5)
				
				WoundType.FRACTURE:
					# Fractures cause pain on movement
					if wound.size >= WoundSize.MEDIUM and randf() < 0.2:
						if health_system:
							health_system.add_status_effect("pain", 3.0, wound.size * 0.7)
							
						# Chance to worsen if not splinted
						if !limbs[limb_name].is_splinted and randf() < 0.05:
							increase_wound_severity(limb_name, wound.id)
				
				WoundType.CUT:
					# Cuts have a chance to reopen and bleed
					if wound.size >= WoundSize.MEDIUM and randf() < 0.05:
						increase_limb_bleeding(limb_name, 0.1 * wound.size)
						
						if entity.get_node_or_null("SensorySystem"):
							entity.get_node("SensorySystem").display_message("The wound on your " + limbs[limb_name].name + " reopens!")

# Update movement penalties based on limb status
func process_movement_penalties():
	var total_penalty = 0.0
	
	# Check leg and foot damage
	for limb_name in ["l_leg", "r_leg", "l_foot", "r_foot"]:
		if !limbs.has(limb_name) or !limbs[limb_name].attached:
			# Missing limb is a severe penalty
			total_penalty += 0.5
			continue
			
		var limb = limbs[limb_name]
		var damage_percent = (limb.brute_damage + limb.burn_damage) / limb.max_damage
		
		# Apply penalty based on damage percentage
		if damage_percent > 0.8:
			total_penalty += 0.4  # Severely damaged
		elif damage_percent > 0.5:
			total_penalty += 0.2  # Moderately damaged
		elif damage_percent > 0.2:
			total_penalty += 0.1  # Lightly damaged
			
		# Additional penalty for fractures
		for wound in wounds[limb_name]:
			if wound.type == WoundType.FRACTURE:
				total_penalty += 0.1 * wound.size
				
				# Reduced penalty if splinted
				if limb.is_splinted:
					total_penalty -= 0.05 * wound.size

	# Limit to reasonable range
	total_penalty = clamp(total_penalty, 0.0, 0.9)
	
	# Apply movement penalty to entity if supported
	if total_penalty > 0 and entity.has_method("set_movement_penalty"):
		entity.set_movement_penalty("limb_damage", total_penalty)
	elif total_penalty <= 0 and entity.has_method("remove_movement_penalty"):
		entity.remove_movement_penalty("limb_damage")

# === LIMB DAMAGE FUNCTIONS ===
# Apply damage to a limb
func apply_limb_damage(limb_name, brute_amount, burn_amount, source = "generic"):
	if !limbs.has(limb_name) or (!limbs[limb_name].attached) or (brute_amount <= 0 and burn_amount <= 0):
		return 0
	
	var limb = limbs[limb_name]
	var old_status = limb.status
	var total_applied_damage = 0
	
	# Calculate damage reduction for prosthetic limbs
	if limb.is_prosthetic:
		brute_amount *= 0.7  # Prosthetics take less brute damage
		burn_amount *= 1.2   # But more burn damage (electronics)
	
	# Apply brute damage
	if brute_amount > 0:
		limb.brute_damage = min(limb.max_damage, limb.brute_damage + brute_amount)
		total_applied_damage += brute_amount
		
		# Create wounds based on brute damage
		if brute_amount >= 10:
			create_wound(limb_name, WoundType.BRUISE, get_wound_size(brute_amount))
		
		if brute_amount >= 15 and randf() < 0.7:
			create_wound(limb_name, WoundType.CUT, get_wound_size(brute_amount))
		
		if brute_amount >= 25 and randf() < 0.5:
			create_wound(limb_name, WoundType.PUNCTURE, get_wound_size(brute_amount))
		
		if brute_amount >= 20 and randf() < 0.3:
			create_wound(limb_name, WoundType.FRACTURE, get_wound_size(brute_amount))
		
		# Trigger bleeding based on brute damage
		if !limb.is_prosthetic and brute_amount >= 5:
			increase_limb_bleeding(limb_name, brute_amount * 0.05)
		
		# Emit damage signal
		limb_damaged.emit(limb_name, "brute", brute_amount)
	
	# Apply burn damage
	if burn_amount > 0:
		limb.burn_damage = min(limb.max_damage, limb.burn_damage + burn_amount)
		total_applied_damage += burn_amount
		
		# Create wounds based on burn damage
		if burn_amount >= 5:
			create_wound(limb_name, WoundType.BURN, get_wound_size(burn_amount))
		
		# Burns can cauterize bleeding
		if burn_amount >= 15 and limb.is_bleeding:
			decrease_limb_bleeding(limb_name, burn_amount * 0.1)
		
		# Emit damage signal
		limb_damaged.emit(limb_name, "burn", burn_amount)
	
	# Update limb status
	update_limb_status(limb_name)
	
	# Check for dismemberment
	if limb.status == LimbStatus.MANGLED:
		check_for_dismemberment(limb_name, brute_amount + burn_amount)
	
	# Apply damage to connected organs if applicable
	if organ_system and brute_amount > 10 and LIMB_DATA[limb_name].contains_organs.size() > 0:
		for organ in LIMB_DATA[limb_name].contains_organs:
			organ_system.apply_organ_damage(organ, brute_amount * 0.1)
	
	# Apply damage to connected organs for burn damage
	if organ_system and burn_amount > 10 and LIMB_DATA[limb_name].contains_organs.size() > 0:
		for organ in LIMB_DATA[limb_name].contains_organs:
			organ_system.apply_organ_damage(organ, burn_amount * 0.05)
	
	# Apply a portion of damage to overall health
	if health_system:
		health_system.adjustBruteLoss(brute_amount * 0.2)
		health_system.adjustFireLoss(burn_amount * 0.2)
	
	return total_applied_damage

# Heal limb damage
func heal_limb_damage(limb_name, brute_amount, burn_amount):
	if !limbs.has(limb_name) or !limbs[limb_name].attached or (brute_amount <= 0 and burn_amount <= 0):
		return 0
	
	var limb = limbs[limb_name]
	var old_status = limb.status
	var total_healed = 0
	
	# Apply brute healing
	if brute_amount > 0 and limb.brute_damage > 0:
		var actual_brute_heal = min(limb.brute_damage, brute_amount)
		limb.brute_damage -= actual_brute_heal
		total_healed += actual_brute_heal
	
	# Apply burn healing
	if burn_amount > 0 and limb.burn_damage > 0:
		var actual_burn_heal = min(limb.burn_damage, burn_amount)
		limb.burn_damage -= actual_burn_heal
		total_healed += actual_burn_heal
	
	# Update limb status
	update_limb_status(limb_name)
	
	# Reduce bleeding as limb heals
	if limb.is_bleeding and total_healed > 0:
		decrease_limb_bleeding(limb_name, total_healed * 0.1)
	
	# Emit healed signal
	if total_healed > 0:
		limb_healed.emit(limb_name, total_healed)
	
	return total_healed

# Set limb damage directly
func set_limb_damage(limb_name, brute_amount, burn_amount):
	if !limbs.has(limb_name) or !limbs[limb_name].attached:
		return false
	
	var limb = limbs[limb_name]
	var old_brute = limb.brute_damage
	var old_burn = limb.burn_damage
	
	# Set damage values with clamping
	limb.brute_damage = clamp(brute_amount, 0, limb.max_damage)
	limb.burn_damage = clamp(burn_amount, 0, limb.max_damage)
	
	# Update limb status
	update_limb_status(limb_name)
	
	# Emit signals for significant changes
	if limb.brute_damage > old_brute:
		limb_damaged.emit(limb_name, "brute", limb.brute_damage - old_brute)
	elif limb.brute_damage < old_brute:
		limb_healed.emit(limb_name, old_brute - limb.brute_damage)
	
	if limb.burn_damage > old_burn:
		limb_damaged.emit(limb_name, "burn", limb.burn_damage - old_burn)
	elif limb.burn_damage < old_burn:
		limb_healed.emit(limb_name, old_burn - limb.burn_damage)
	
	return true

# Update limb status based on current damage
func update_limb_status(limb_name):
	if !limbs.has(limb_name) or !limbs[limb_name].attached:
		return
	
	var limb = limbs[limb_name]
	var old_status = limb.status
	
	# Calculate total damage percentage
	var total_damage = limb.brute_damage + limb.burn_damage
	var damage_percent = (total_damage / limb.max_damage) * 100
	
	# Determine new status
	var new_status
	if damage_percent >= 70:
		new_status = LimbStatus.MANGLED
	elif damage_percent >= 30:
		new_status = LimbStatus.WOUNDED
	else:
		new_status = LimbStatus.NORMAL
	
	# Update status if changed
	if new_status != old_status:
		limb.status = new_status
		limb_status_changed.emit(limb_name, new_status)
		
		# Update sprite
		if sprite_system and sprite_system.has_method("update_limb_status"):
			sprite_system.update_limb_status(limb_name, new_status, limb.is_prosthetic)

# Check for dismemberment of a limb
func check_for_dismemberment(limb_name, damage_amount):
	if !limbs.has(limb_name) or !limbs[limb_name].attached:
		return false
	
	var limb = limbs[limb_name]
	
	# Don't check vital limbs unless they're damaged beyond threshold
	if limb.is_vital and (limb.brute_damage + limb.burn_damage) < limb.max_damage * 0.9:
		return false
	
	# Calculate dismemberment chance
	var total_damage_percent = ((limb.brute_damage + limb.burn_damage) / limb.max_damage) * 100
	var dismemberment_threshold = LIMB_DATA[limb_name].dismemberment_threshold
	
	if total_damage_percent < dismemberment_threshold:
		return false
	
	# Base chance increases as damage exceeds threshold
	var base_chance = (total_damage_percent - dismemberment_threshold) * 0.2
	
	# Adjust chance based on damage type (sharp weapons would increase this)
	var adjusted_chance = base_chance * (damage_amount / 20.0)
	
	# Roll for dismemberment
	if randf() * 100 < adjusted_chance:
		dismember_limb(limb_name)
		return true
	
	return false

# Dismember a limb
func dismember_limb(limb_name):
	if !limbs.has(limb_name) or !limbs[limb_name].attached:
		return false
	
	var limb = limbs[limb_name]
	
	# Don't dismember vital limbs unless already destroyed
	if limb.is_vital and limb.brute_damage + limb.burn_damage < limb.max_damage * 0.9:
		return false
	
	# Mark limb as dismembered
	limb.attached = false
	limb.status = LimbStatus.DISMEMBERED
	dismembered_limbs[limb_name] = true
	
	# Also dismember all child limbs
	for child_limb in LIMB_DATA[limb_name].children:
		if limbs.has(child_limb) and limbs[child_limb].attached:
			dismember_limb(child_limb)
	
	# Massive bleeding from dismemberment
	if !limb.is_prosthetic and blood_system:
		blood_system.adjust_blood_volume(-20)  # Immediate blood loss
		blood_system.add_bleeding(5.0)  # Massive bleeding
	
	# Apply significant damage to overall health
	if health_system:
		health_system.apply_damage(30, health_system.DamageType.BRUTE)
	
	# Apply trauma effect
	if health_system:
		health_system.add_status_effect("pain", 15.0, 5.0)
		health_system.add_status_effect("shocked", 10.0, 3.0)
	
	# Handle vital limb dismemberment
	if limb.is_vital and health_system:
		health_system.die("dismemberment of " + limb.name)
	
	# Emit dismemberment signal
	limb_dismembered.emit(limb_name)
	
	# Update sprite
	if sprite_system and sprite_system.has_method("update_dismemberment"):
		sprite_system.update_dismemberment(limb_name, true)
	
	# Play sound effect
	if audio_system:
		audio_system.play_sound("dismember", 0.8)
	
	# Spawn the dismembered limb in the world if possible
	# This would be handled by an entity spawning system
	
	return true

# Attach a prosthetic limb
func attach_prosthetic(limb_name, quality = 1.0):
	if !limbs.has(limb_name) or limbs[limb_name].attached:
		return false
	
	# Only attach if parent limb exists
	var parent_limb = LIMB_DATA[limb_name].parent
	if parent_limb and (!limbs.has(parent_limb) or !limbs[parent_limb].attached):
		return false
	
	# Create the prosthetic limb
	limbs[limb_name] = {
		"name": LIMB_DATA[limb_name].name,
		"brute_damage": 0.0,
		"burn_damage": 0.0,
		"max_damage": LIMB_DATA[limb_name].max_damage * quality,
		"status": LimbStatus.NORMAL,
		"is_vital": LIMB_DATA[limb_name].vital,
		"is_prosthetic": true,
		"is_splinted": false,
		"is_bleeding": false,
		"bleeding_rate": 0.0,
		"wound_count": 0,
		"attached": true
	}
	
	# Mark as prosthetic
	attached_prosthetics[limb_name] = true
	
	# Clear existing wounds
	wounds[limb_name] = []
	
	# Emit signal
	limb_attached.emit(limb_name, true)
	
	# Update sprite
	if sprite_system and sprite_system.has_method("update_limb"):
		sprite_system.update_limb(limb_name, LimbStatus.NORMAL, true)
	
	# Play sound effect
	if audio_system:
		audio_system.play_sound("mechanical", 0.5)
	
	return true

# Reattach a severed organic limb
func reattach_limb(limb_name):
	if !limbs.has(limb_name) or limbs[limb_name].attached:
		return false
	
	# Only attach if parent limb exists
	var parent_limb = LIMB_DATA[limb_name].parent
	if parent_limb and (!limbs.has(parent_limb) or !limbs[parent_limb].attached):
		return false
	
	# Reattach the limb with some damage
	limbs[limb_name].attached = true
	limbs[limb_name].brute_damage = limbs[limb_name].max_damage * 0.7
	limbs[limb_name].status = LimbStatus.WOUNDED
	
	# Start some bleeding on reattached limb
	if !limbs[limb_name].is_prosthetic:
		increase_limb_bleeding(limb_name, 0.5)
	
	# Remove from dismembered list
	dismembered_limbs.erase(limb_name)
	
	# Emit signal
	limb_attached.emit(limb_name, false)
	
	# Update sprite
	if sprite_system and sprite_system.has_method("update_limb"):
		sprite_system.update_limb(limb_name, LimbStatus.WOUNDED, false)
	
	# Play sound effect
	if audio_system:
		audio_system.play_sound("surgery", 0.5)
	
	return true

# === WOUND MANAGEMENT ===
# Create a new wound on a limb
func create_wound(limb_name, wound_type, wound_size, wound_info = {}):
	if !limbs.has(limb_name) or !limbs[limb_name].attached:
		return null
	
	var limb = limbs[limb_name]
	
	# Don't create wounds on prosthetics (except for burn damage to electronics)
	if limb.is_prosthetic and wound_type != WoundType.BURN:
		return null
	
	# Don't exceed max wounds per limb
	if limb.wound_count >= LIMB_DATA[limb_name].max_wounds:
		# Instead, increase severity of a random existing wound
		return worsen_random_wound(limb_name)
	
	# Create the wound
	wound_counter += 1
	var wound = {
		"id": wound_counter,
		"type": wound_type,
		"size": wound_size,
		"time": 0,  # Time the wound has existed
		"treated": false,
		"infected": false,
		"description": get_wound_description(wound_type, wound_size)
	}
	
	# Add any additional info
	for key in wound_info:
		wound[key] = wound_info[key]
	
	# Add to wounds
	wounds[limb_name].append(wound)
	limb.wound_count += 1
	
	# Apply bleeding for certain wound types
	if !limb.is_prosthetic and (wound_type == WoundType.CUT or wound_type == WoundType.PUNCTURE):
		increase_limb_bleeding(limb_name, 0.2 * wound_size)
	
	return wound

# Determine wound size based on damage amount
func get_wound_size(damage_amount):
	if damage_amount >= 30:
		return WoundSize.CRITICAL
	elif damage_amount >= 20:
		return WoundSize.LARGE
	elif damage_amount >= 10:
		return WoundSize.MEDIUM
	else:
		return WoundSize.SMALL

# Get description of a wound based on type and severity
func get_wound_description(wound_type, wound_size):
	var size_text = ""
	match wound_size:
		WoundSize.SMALL: size_text = "small"
		WoundSize.MEDIUM: size_text = "moderate"
		WoundSize.LARGE: size_text = "severe"
		WoundSize.CRITICAL: size_text = "critical"
	
	match wound_type:
		WoundType.BRUISE: 
			return "A " + size_text + " bruise"
		WoundType.CUT: 
			return "A " + size_text + " cut"
		WoundType.BURN: 
			return "A " + size_text + " burn"
		WoundType.PUNCTURE: 
			return "A " + size_text + " puncture wound"
		WoundType.FRACTURE: 
			return "A " + size_text + " fracture"
	
	return "An unidentified wound"

# Increase severity of a random wound on limb
func worsen_random_wound(limb_name):
	if !limbs.has(limb_name) or !limbs[limb_name].attached or wounds[limb_name].size() == 0:
		return null
	
	# Select random wound
	var wound_index = randi() % wounds[limb_name].size()
	var wound = wounds[limb_name][wound_index]
	
	# Increase severity
	return increase_wound_severity(limb_name, wound.id)

# Increase severity of a specific wound
func increase_wound_severity(limb_name, wound_id):
	if !limbs.has(limb_name) or !limbs[limb_name].attached:
		return null
	
	# Find the wound
	var wound_index = -1
	for i in range(wounds[limb_name].size()):
		if wounds[limb_name][i].id == wound_id:
			wound_index = i
			break
	
	if wound_index == -1:
		return null
	
	var wound = wounds[limb_name][wound_index]
	
	# Cap at critical
	if wound.size >= WoundSize.CRITICAL:
		return wound
	
	# Increase size
	wound.size += 1
	
	# Update description
	wound.description = get_wound_description(wound.type, wound.size)
	
	# More bleeding for more severe wounds
	if !limbs[limb_name].is_prosthetic and (wound.type == WoundType.CUT or wound.type == WoundType.PUNCTURE):
		increase_limb_bleeding(limb_name, 0.2)
	
	return wound

# Treat a specific wound
func treat_wound(limb_name, wound_id):
	if !limbs.has(limb_name) or !limbs[limb_name].attached:
		return false
	
	# Find the wound
	var wound_index = -1
	for i in range(wounds[limb_name].size()):
		if wounds[limb_name][i].id == wound_id:
			wound_index = i
			break
	
	if wound_index == -1:
		return false
	
	var wound = wounds[limb_name][wound_index]
	
	# Mark as treated
	wound.treated = true
	
	# Reduce bleeding if applicable
	if wound.type == WoundType.CUT or wound.type == WoundType.PUNCTURE:
		decrease_limb_bleeding(limb_name, 0.2 * wound.size)
	
	return true

# Heal a random wound on the limb
func heal_random_wound(limb_name):
	if !limbs.has(limb_name) or !limbs[limb_name].attached or wounds[limb_name].size() == 0:
		return false
	
	# Select random wound
	var wound_index = randi() % wounds[limb_name].size()
	
	# Treated wounds heal first
	var has_treated_wounds = false
	for wound in wounds[limb_name]:
		if wound.treated:
			has_treated_wounds = true
			break
	
	if has_treated_wounds:
		# Find a treated wound to heal
		var found_treated = false
		for i in range(wounds[limb_name].size()):
			if wounds[limb_name][i].treated:
				wound_index = i
				found_treated = true
				break
		
		if !found_treated:
			wound_index = randi() % wounds[limb_name].size()
	
	# Get the wound
	var wound = wounds[limb_name][wound_index]
	
	# Decrease severity or remove
	if wound.size > WoundSize.SMALL:
		# Decrease severity
		wound.size -= 1
		wound.description = get_wound_description(wound.type, wound.size)
		return true
	else:
		# Remove wound
		wounds[limb_name].remove_at(wound_index)
		limbs[limb_name].wound_count -= 1
		
		# If no more wounds, stop bleeding
		if limbs[limb_name].wound_count == 0 and limbs[limb_name].is_bleeding:
			limbs[limb_name].is_bleeding = false
			limbs[limb_name].bleeding_rate = 0.0
		
		return true

# === BLEEDING MANAGEMENT ===
# Increase bleeding on a limb
func increase_limb_bleeding(limb_name, amount):
	if !limbs.has(limb_name) or !limbs[limb_name].attached or limbs[limb_name].is_prosthetic:
		return 0
	
	var limb = limbs[limb_name]
	
	# Don't add bleeding to prosthetics
	if limb.is_prosthetic:
		return 0
	
	# Update bleeding values
	limb.is_bleeding = true
	limb.bleeding_rate += amount
	
	return limb.bleeding_rate

# Decrease bleeding on a limb
func decrease_limb_bleeding(limb_name, amount):
	if !limbs.has(limb_name) or !limbs[limb_name].attached or !limbs[limb_name].is_bleeding:
		return 0
	
	var limb = limbs[limb_name]
	
	# Reduce bleeding rate
	limb.bleeding_rate = max(0, limb.bleeding_rate - amount)
	
	# Stop bleeding if rate is 0
	if limb.bleeding_rate <= 0:
		limb.is_bleeding = false
		limb.bleeding_rate = 0
	
	return limb.bleeding_rate

# Stop bleeding on a limb entirely
func stop_limb_bleeding(limb_name):
	if !limbs.has(limb_name) or !limbs[limb_name].attached:
		return false
	
	var limb = limbs[limb_name]
	
	limb.is_bleeding = false
	limb.bleeding_rate = 0
	
	return true

# Stop bleeding on all limbs
func stop_all_bleeding():
	for limb_name in limbs:
		stop_limb_bleeding(limb_name)
	
	return true

# === TREATMENT FUNCTIONS ===
# Apply bandage to a limb
func apply_bandage(limb_name, quality = 1.0):
	if !limbs.has(limb_name) or !limbs[limb_name].attached or limbs[limb_name].is_prosthetic:
		return 0
	
	var limb = limbs[limb_name]
	
	# Bandages mainly stop bleeding
	var bleeding_reduced = 0
	if limb.is_bleeding:
		bleeding_reduced = limb.bleeding_rate * (0.8 * quality)
		decrease_limb_bleeding(limb_name, bleeding_reduced)
	
	# Mark wounds as treated
	for wound in wounds[limb_name]:
		if wound.type == WoundType.CUT or wound.type == WoundType.PUNCTURE or wound.type == WoundType.BRUISE:
			wound.treated = true
	
	# Small healing effect
	heal_limb_damage(limb_name, 2.0 * quality, 0)
	
	# Play sound effect
	if audio_system:
		audio_system.play_sound("bandage", 0.5)
	
	return bleeding_reduced

# Apply burn salve to a limb
func apply_burn_treatment(limb_name, quality = 1.0):
	if !limbs.has(limb_name) or !limbs[limb_name].attached:
		return 0
	
	var limb = limbs[limb_name]
	
	# Burn treatments heal burn damage
	var burn_healed = min(limb.burn_damage, 5.0 * quality)
	heal_limb_damage(limb_name, 0, burn_healed)
	
	# Mark burns as treated
	for wound in wounds[limb_name]:
		if wound.type == WoundType.BURN:
			wound.treated = true
	
	# Play sound effect
	if audio_system:
		audio_system.play_sound("salve", 0.4)
	
	return burn_healed

# Apply splint to a fractured limb
func apply_splint(limb_name, quality = 1.0):
	if !limbs.has(limb_name) or !limbs[limb_name].attached or limbs[limb_name].is_splinted:
		return false
	
	var limb = limbs[limb_name]
	
	# Check if limb has fractures
	var has_fracture = false
	for wound in wounds[limb_name]:
		if wound.type == WoundType.FRACTURE:
			has_fracture = true
			wound.treated = true
	
	# Mark as splinted
	limb.is_splinted = true
	
	# Play sound effect
	if audio_system:
		audio_system.play_sound("splint", 0.5)
	
	return true

# Suture wounds on a limb
func apply_sutures(limb_name, quality = 1.0):
	if !limbs.has(limb_name) or !limbs[limb_name].attached or limbs[limb_name].is_prosthetic:
		return 0
	
	var limb = limbs[limb_name]
	
	# Completely stop bleeding
	var bleeding_stopped = limb.bleeding_rate
	stop_limb_bleeding(limb_name)
	
	# Heal some brute damage
	var brute_healed = min(limb.brute_damage, 10.0 * quality)
	heal_limb_damage(limb_name, brute_healed, 0)
	
	# Treat cuts and punctures
	var wounds_treated = 0
	for wound in wounds[limb_name]:
		if wound.type == WoundType.CUT or wound.type == WoundType.PUNCTURE:
			wound.treated = true
			wounds_treated += 1
			
			# Reduce severity of wound
			if wound.size > WoundSize.SMALL and randf() < quality * 0.5:
				wound.size -= 1
				wound.description = get_wound_description(wound.type, wound.size)
	
	# Play sound effect
	if audio_system:
		audio_system.play_sound("suture", 0.5)
	
	return wounds_treated

# Apply repairs to a prosthetic limb
func repair_prosthetic(limb_name, quality = 1.0):
	if !limbs.has(limb_name) or !limbs[limb_name].attached or !limbs[limb_name].is_prosthetic:
		return 0
	
	var limb = limbs[limb_name]
	
	# Repair both brute and burn damage
	var brute_repaired = min(limb.brute_damage, 15.0 * quality)
	var burn_repaired = min(limb.burn_damage, 10.0 * quality)
	
	heal_limb_damage(limb_name, brute_repaired, burn_repaired)
	
	# Clear "wounds" on robotic parts
	wounds[limb_name].clear()
	limb.wound_count = 0
	
	# Play sound effect
	if audio_system:
		audio_system.play_sound("mechanical", 0.5)
	
	return brute_repaired + burn_repaired

# === UTILITY FUNCTIONS ===
# Get limb status for medical scanners
func get_limb_status(limb_name):
	if !limbs.has(limb_name):
		return null
	
	var limb = limbs[limb_name]
	
	var status_text = "missing"
	if limb.attached:
		match limb.status:
			LimbStatus.NORMAL: status_text = "healthy"
			LimbStatus.WOUNDED: status_text = "wounded"
			LimbStatus.MANGLED: status_text = "severely damaged"
			LimbStatus.DISMEMBERED: status_text = "dismembered"
		
		if limb.is_prosthetic:
			status_text += " (prosthetic)"
	
	return {
		"name": limb.name,
		"brute_damage": limb.brute_damage,
		"burn_damage": limb.burn_damage,
		"total_damage": limb.brute_damage + limb.burn_damage,
		"max_damage": limb.max_damage,
		"damage_percent": ((limb.brute_damage + limb.burn_damage) / limb.max_damage) * 100,
		"status": status_text,
		"status_code": limb.status,
		"is_prosthetic": limb.is_prosthetic,
		"is_vital": limb.is_vital,
		"is_bleeding": limb.is_bleeding,
		"bleeding_rate": limb.bleeding_rate,
		"wounds": get_wounds_for_limb(limb_name),
		"wound_count": limb.wound_count,
		"is_splinted": limb.is_splinted,
		"attached": limb.attached
	}

# Get all limb statuses for medical display
func get_all_limb_statuses():
	var statuses = {}
	
	for limb_name in limbs:
		statuses[limb_name] = get_limb_status(limb_name)
	
	return statuses

# Get wounds on a limb
func get_wounds_for_limb(limb_name):
	if !limbs.has(limb_name) or !wounds.has(limb_name):
		return []
	
	var wound_list = []
	
	for wound in wounds[limb_name]:
		wound_list.append({
			"id": wound.id,
			"description": wound.description,
			"type": wound.type,
			"size": wound.size,
			"treated": wound.treated,
			"infected": wound.infected if "infected" in wound else false
		})
	
	return wound_list

# For revival and healing
func restore_all_limbs():
	for limb_name in limbs:
		if limbs[limb_name].attached:
			set_limb_damage(limb_name, 0, 0)
		else:
			# For dismembered limbs, we don't auto-restore
			pass
	
	return true

func can_stand() -> bool:
	# Need at least one leg to stand
	var has_leg = false
	
	if limbs.has("l_leg") and limbs["l_leg"].attached and limbs.has("l_foot") and limbs["l_foot"].attached:
		has_leg = true
	
	if limbs.has("r_leg") and limbs["r_leg"].attached and limbs.has("r_foot") and limbs["r_foot"].attached:
		has_leg = true
	
	return has_leg
