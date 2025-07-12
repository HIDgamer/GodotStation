extends Node
class_name HealthSystem

# === SIGNALS ===
signal health_changed(new_health, max_health)
signal damage_taken(amount, type)
signal status_effect_added(effect_name, duration)
signal status_effect_removed(effect_name)
signal died(cause_of_death)
signal revived()
signal entered_critical()
signal exited_critical()
signal organ_damaged(organ_name, amount)
signal limb_damaged(limb_name, amount)
signal blood_level_changed(new_amount, max_amount)

# === CONSTANTS ===
# Health states
enum HealthState {
	ALIVE,
	CRITICAL,
	DEAD
}

# Damage types
enum DamageType {
	BRUTE,
	BURN,
	TOXIN,
	OXYGEN,
	CLONE,
	STAMINA,
	BRAIN
}

# Critical thresholds
const HEALTH_THRESHOLD_CRIT = 0
const HEALTH_THRESHOLD_DEAD = -100
const HEALTH_THRESHOLD_GIBBED = -200  # Added gibbing threshold
const BLOOD_VOLUME_NORMAL = 560
const BLOOD_VOLUME_SAFE = 475
const BLOOD_VOLUME_OKAY = 336
const BLOOD_VOLUME_BAD = 224
const BLOOD_VOLUME_SURVIVE = 122

# Organs
const ORGAN_SLOTS = ["heart", "lungs", "liver", "stomach", "eyes", "brain"]

# Limbs
const LIMBS = ["head", "chest", "l_arm", "r_arm", "l_leg", "r_leg", "groin"]

# === MEMBER VARIABLES ===
# Basic health
var max_health: float = 100.0
var health: float = 100.0
var current_state = HealthState.ALIVE

# Status flags
var godmode: bool = false
var in_stasis: bool = false
var no_pain: bool = false

# Damage variables
var bruteloss: float = 0.0
var fireloss: float = 0.0
var toxloss: float = 0.0
var oxyloss: float = 0.0
var cloneloss: float = 0.0
var staminaloss: float = 0.0
var brainloss: float = 0.0
var max_stamina: float = 100.0

# Blood system
var blood_type: String = "O+"
var blood_volume: float = BLOOD_VOLUME_NORMAL
var max_blood_volume: float = BLOOD_VOLUME_NORMAL
var bleeding_rate: float = 0.0
var in_cardiac_arrest: bool = false
var pulse: int = 60  # Heartbeats per minute

# Organ system
var organs: Dictionary = {}
var limbs: Dictionary = {}
var limb_damage_multipliers: Dictionary = {}

# Body temperature
var body_temperature: float = 310.15  # Kelvin (37°C/98.6°F)
var temp_resistance: float = 1.0

# Status effects and modifiers
var status_effects: Dictionary = {}
var incoming_damage_modifiers: Dictionary = {}

# Armor values
var soft_armor: Dictionary = {
	"melee": 0,
	"bullet": 0,
	"laser": 0,
	"energy": 0,
	"bomb": 0,
	"bio": 0,
	"rad": 0,
	"fire": 0,
	"acid": 0
}

var hard_armor: Dictionary = {
	"melee": 0,
	"bullet": 0,
	"laser": 0,
	"energy": 0,
	"bomb": 0,
	"bio": 0,
	"rad": 0,
	"fire": 0,
	"acid": 0
}

# Internal trackers
var death_time: int = 0
var can_be_revived: bool = true
var cause_of_death: String = ""
var traumatic_shock: float = 0.0  # Pain level
var shock_stage: int = 0  # Progressive shock
var damage_mute_counter: int = 0  # For preventing spam
var dead_threshold_passed: bool = false
var overheal: float = 0.0  # Buffer before damage is taken

# References to other systems
var entity = null  # The parent entity
var inventory_system = null  # The entity's inventory system
var sprite_system = null  # For visual damage updates
var audio_system = null  # For sound effects
var ui_system = null  # For UI updates
var effect = null

# === INITIALIZATION ===
func _ready():
	# Find parent entity
	entity = get_parent()
	effect = entity.get_node("Effect")
	
	# Set up connections to other systems
	_find_systems()
	
	# Initialize organ dictionary
	_initialize_organs()
	
	# Initialize limb dictionary
	_initialize_limbs()
	
	# Set up initial health
	health = max_health
	
	# Connect to timer for periodic updates
	var timer = Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_on_update_tick)
	add_child(timer)

func _find_systems():
	# Try to find inventory system
	inventory_system = entity.get_node_or_null("InventorySystem")
	
	# Try to find sprite system
	sprite_system = entity.get_node_or_null("SpriteSystem")
	
	# Try to find audio system
	audio_system = entity.get_node_or_null("AudioSystem")
	
	# Try to find UI system
	ui_system = entity.get_node_or_null("UISystem")
	
	print("HealthSystem: Connected to systems")
	print("  - Inventory: ", "Found" if inventory_system else "Not found")
	print("  - Sprite: ", "Found" if sprite_system else "Not found")
	print("  - Audio: ", "Found" if audio_system else "Not found")
	print("  - UI: ", "Found" if ui_system else "Not found")

func _initialize_organs():
	for organ_name in ORGAN_SLOTS:
		organs[organ_name] = {
			"name": organ_name,
			"max_damage": 100.0,
			"damage": 0.0,
			"is_vital": organ_name in ["heart", "brain"],
			"is_damaged": false,
			"is_failing": false
		}

func _initialize_limbs():
	for limb_name in LIMBS:
		limbs[limb_name] = {
			"name": limb_name,
			"max_damage": 100.0,
			"brute_damage": 0.0,
			"burn_damage": 0.0,
			"status": "normal",  # normal, wounded, mangled, missing
			"wounds": [],
			"attached": true
		}
		
	# Set up damage multipliers for limbs
	limb_damage_multipliers = {
		"head": 1.5,
		"chest": 1.0,
		"l_arm": 0.8,
		"r_arm": 0.8,
		"l_leg": 0.8,
		"r_leg": 0.8,
		"groin": 1.0
	}

# === PROCESS FUNCTIONS ===
func _process(delta):
	# Process status effects
	_process_status_effects(delta)
	
	# Process bleeding
	if bleeding_rate > 0:
		adjust_blood_volume(-bleeding_rate * delta)
	
	# Process temperature effects
	_process_temperature(delta)
	
	# Process organ effects
	_process_organs(delta)
	
	# Process shock
	_process_shock(delta)

func _on_update_tick():
	# Every second updates
	if current_state == HealthState.DEAD:
		_process_death_effects()
		return
	
	# Blood regeneration if alive
	if current_state == HealthState.ALIVE and blood_volume < BLOOD_VOLUME_NORMAL:
		adjust_blood_volume(0.1)  # Regenerate blood slowly
	
	# Natural healing
	if current_state == HealthState.ALIVE and bruteloss + fireloss < 30:
		adjustBruteLoss(-0.1)
		adjustFireLoss(-0.1)
	
	# Process organ slow damage for failing organs
	for organ_name in organs:
		var organ = organs[organ_name]
		if organ.is_failing:
			apply_organ_damage(organ_name, 0.2)

# Process status effects, removing expired ones
func _process_status_effects(delta):
	var effects_to_remove = []
	
	for effect_name in status_effects:
		var effect = status_effects[effect_name]
		effect.duration -= delta
		
		# Process effect-specific behaviors
		match effect_name:
			"poisoned":
				adjustToxLoss(effect.intensity * delta)
			"bleeding":
				# Already handled via bleeding_rate
				pass
			"burned":
				adjustFireLoss(effect.intensity * delta * 0.1)
			"irradiated":
				adjustToxLoss(effect.intensity * delta * 0.05)
				if randf() < 0.01 * effect.intensity:
					# Random mutations or cell damage
					adjustCloneLoss(1.0)
			"stunned":
				# Visual effects are handled by sprite system
				pass
			"confused":
				# Confusion effects handled by movement controller
				pass
			"slowed":
				# Slowdown handled by movement controller
				pass
		
		# Remove expired effects
		if effect.duration <= 0:
			effects_to_remove.append(effect_name)
	
	# Remove expired effects
	for effect_name in effects_to_remove:
		remove_status_effect(effect_name)

# Process temperature effects
func _process_temperature(delta):
	# Temperature regulation
	var normal_temp = 310.15  # 37°C in Kelvin
	
	if body_temperature > normal_temp + 30:  # Hyperthermia
		apply_damage(delta * (body_temperature - normal_temp - 30) * 0.1, DamageType.BURN)
		add_status_effect("hyperthermia", 2.0, (body_temperature - normal_temp) / 10)
	elif body_temperature < normal_temp - 30:  # Hypothermia
		apply_damage(delta * (normal_temp - 30 - body_temperature) * 0.1, DamageType.BURN)
		add_status_effect("hypothermia", 2.0, (normal_temp - body_temperature) / 10)
	else:
		# Move slowly toward normal temperature
		body_temperature = lerp(body_temperature, normal_temp, 0.01 * delta)

# Process organs
func _process_organs(delta):
	# Process heart
	if organs.has("heart"):
		var heart = organs["heart"]
		
		# Heart calculations
		if heart.is_failing or in_cardiac_arrest:
			pulse = 0
			# No heartbeat means oxygen deprivation
			adjustOxyLoss(1.0 * delta)
		else:
			# Normal pulse based on health
			var health_percent = health / max_health
			pulse = int(60 + (1.0 - health_percent) * 40)
	
	# Process lungs
	if organs.has("lungs"):
		var lungs = organs["lungs"]
		if lungs.is_failing:
			adjustOxyLoss(1.0 * delta)
	
	# Process liver
	if organs.has("liver"):
		var liver = organs["liver"]
		if liver.is_failing:
			adjustToxLoss(0.3 * delta)
	
	# Process brain
	if organs.has("brain"):
		var brain = organs["brain"]
		if brain.damage > 60:
			add_status_effect("confused", 1.0, brain.damage / 20)
		if brain.is_failing and current_state != HealthState.DEAD:
			# Brain death
			die("brain damage")

# Process shock from traumatic injury
func _process_shock(delta):
	# Skip if no pain
	if no_pain:
		return
		
	# Calculate shock value based on damage
	var damage_based_shock = (bruteloss + fireloss) * 0.5
	
	# Update traumatic shock value
	traumatic_shock = max(0, damage_based_shock)
	
	# Process shock stages
	if traumatic_shock > 30:
		shock_stage += delta
	else:
		shock_stage = max(0, shock_stage - (delta * 0.5))
	
	# Apply shock effects based on stages
	if shock_stage >= 10 and shock_stage < 30:
		if randf() < 0.05:
			add_status_effect("dizzy", 2.0)
	elif shock_stage >= 30 and shock_stage < 60:
		if randf() < 0.1:
			add_status_effect("stunned", 2.0)
	elif shock_stage >= 60 and shock_stage < 120:
		if randf() < 0.2:
			adjustOxyLoss(1.0)
	elif shock_stage >= 120:
		adjustOxyLoss(2.0 * delta)
		if randf() < 0.1:
			enter_cardiac_arrest()

# Process effects that happen while dead
func _process_death_effects():
	# Increment death time
	death_time += 1
	
	# After certain time, decay effects would begin
	if death_time > 600:  # 10 minutes
		# Start body decay
		if randf() < 0.05:
			# Corpse decay effects
			adjustCloneLoss(0.2)
	
	# Make revival harder over time
	if death_time > 1800:  # 30 minutes
		can_be_revived = false

# === DAMAGE FUNCTIONS ===
# Apply damage of specified type
func apply_damage(amount, damage_type, penetration = 0, limb = null, source = null):
	if godmode:
		return 0
	
	# Skip if dead unless the damage is being applied to a specific limb
	if current_state == HealthState.DEAD and limb == null:
		return 0
	
	# Calculate actual damage after modifiers
	var actual_damage = calculate_damage_with_modifiers(amount, damage_type, penetration)
	
	if actual_damage <= 0:
		return 0
	
	# Apply damage to specific limb if specified
	if limb != null and limbs.has(limb):
		return apply_limb_damage(limb, actual_damage, damage_type)
		
	# Otherwise apply to general health pool
	match damage_type:
		DamageType.BRUTE:
			adjustBruteLoss(actual_damage)
		DamageType.BURN:
			adjustFireLoss(actual_damage)
		DamageType.TOXIN:
			adjustToxLoss(actual_damage)
		DamageType.OXYGEN:
			adjustOxyLoss(actual_damage)
		DamageType.CLONE:
			adjustCloneLoss(actual_damage)
		DamageType.BRAIN:
			adjustBrainLoss(actual_damage)
		DamageType.STAMINA:
			adjustStaminaLoss(actual_damage)
	
	# Check for blood splatter for physical damage types
	if damage_type == DamageType.BRUTE and actual_damage > 10:
		check_blood_splatter(actual_damage)
	
	# Emit signal
	emit_signal("damage_taken", actual_damage, damage_type)
	
	# Update health after damage
	updatehealth()
	
	# Play damage sounds
	_play_damage_sound(damage_type, actual_damage)
	
	# Check for gibbing if massive damage taken at once
	if actual_damage > 75 and damage_type in [DamageType.BRUTE, DamageType.BURN]:
		check_for_gibbing(actual_damage, damage_type)
	
	return actual_damage

# Calculate damage after modifiers and armor
func calculate_damage_with_modifiers(amount, damage_type, penetration = 0):
	if amount <= 0:
		return 0
	
	var modified_amount = amount
	
	# Apply incoming damage modifiers from status effects
	for modifier in incoming_damage_modifiers:
		if incoming_damage_modifiers[modifier].damage_type == damage_type:
			modified_amount *= incoming_damage_modifiers[modifier].multiplier
	
	# Apply armor reduction if applicable
	var armor_type = ""
	match damage_type:
		DamageType.BRUTE:
			armor_type = "melee"
		DamageType.BURN:
			armor_type = "fire"
		DamageType.TOXIN:
			armor_type = "bio"
	
	if armor_type != "":
		# Apply soft armor (percentage reduction)
		var armor_value = soft_armor.get(armor_type, 0)
		var effective_penetration = max(0, penetration)
		
		# Calculate damage reduction from armor
		var reduction = (armor_value - effective_penetration) * 0.01
		reduction = clamp(reduction, 0, 0.9)  # Cap at 90% reduction
		modified_amount *= (1.0 - reduction)
		
		# Apply hard armor (flat reduction)
		var hard_armor_value = hard_armor.get(armor_type, 0)
		modified_amount = max(0, modified_amount - max(0, hard_armor_value - effective_penetration))
	
	# Apply overheal reduction if available
	if overheal > 0:
		var reduction = min(overheal, modified_amount)
		modified_amount -= reduction
		overheal -= reduction
	
	return modified_amount

# Apply damage to a specific limb
func apply_limb_damage(limb_name, amount, damage_type):
	if !limbs.has(limb_name) or amount <= 0:
		return 0
	
	var limb = limbs[limb_name]
	var damage_mult = limb_damage_multipliers.get(limb_name, 1.0)
	var applied_damage = amount * damage_mult
	
	# Apply damage based on type
	match damage_type:
		DamageType.BRUTE:
			limb.brute_damage += applied_damage
		DamageType.BURN:
			limb.burn_damage += applied_damage
		_:
			# For other damage types, distribute to general health
			apply_damage(applied_damage, damage_type)
			return applied_damage
	
	# Update limb status
	_update_limb_status(limb_name)
	
	# Emit signal
	emit_signal("limb_damaged", limb_name, applied_damage)
	
	# Check for blood splatter
	if damage_type == DamageType.BRUTE and applied_damage > 10:
		check_blood_splatter(applied_damage)
	
	# Apply a portion of limb damage to overall health pool
	var health_damage = applied_damage * 0.5
	
	if damage_type == DamageType.BRUTE:
		adjustBruteLoss(health_damage)
	else:
		adjustFireLoss(health_damage)
	
	# Check for limb loss/dismemberment
	check_for_dismemberment(limb_name, applied_damage, damage_type)
	
	# Update health
	updatehealth()
	
	return applied_damage

# Check for gibbing based on damage
func check_for_gibbing(damage_amount, damage_type):
	# Multiple conditions for gibbing:
	# 1. Massive single hit
	if damage_amount > 100:
		if randf() < 0.7:  # 70% chance
			gib("massive damage")
			return true
			
	# 2. Explosive damage
	if damage_type == DamageType.BRUTE and damage_amount > 75:
		if "bomb" in soft_armor and soft_armor["bomb"] < 50:  # Low bomb armor
			if randf() < 0.5:  # 50% chance
				gib("explosion")
				return true
				
	# 3. Already very damaged and took significant hit
	if health < -50 and damage_amount > 30:
		if randf() < 0.3:  # 30% chance
			gib("trauma")
			return true
			
	return false

# Check for dismemberment of a limb
func check_for_dismemberment(limb_name, damage_amount, damage_type):
	var limb = limbs[limb_name]
	var total_damage = limb.brute_damage + limb.burn_damage
	
	# Don't check for torso or head dismemberment
	if limb_name in ["head", "chest", "groin"]:
		return false
	
	# 1. High damage on already damaged limb
	if total_damage > 90 and damage_amount > 25:
		var chance = (total_damage - 90) * 0.2
		if randf() < chance:
			dismember_limb(limb_name)
			return true
			
	# 2. Sharp objects with high damage (would need to pass this from weapon)
	if damage_type == DamageType.BRUTE and damage_amount > 50:
		var sharp_factor = 0.3  # This would be higher for weapons flagged as sharp
		if randf() < sharp_factor:
			dismember_limb(limb_name)
			return true
			
	return false

# Dismember a limb
func dismember_limb(limb_name):
	if !limbs.has(limb_name):
		return false
		
	var limb = limbs[limb_name]
	
	# Apply massive damage to base health
	adjustBruteLoss(30)
	
	# Set limb as detached
	limb.attached = false
	
	# Mark limb as missing
	limb.status = "missing"
	
	# Cause massive bleeding
	set_bleeding_rate(bleeding_rate + 5.0)
	
	# Emit effects and signals
	emit_signal("limb_damaged", limb_name, 100.0)
	
	# Update sprite if possible
	if sprite_system and sprite_system.has_method("update_dismemberment"):
		sprite_system.update_dismemberment(limb_name)
		
	# Play sound effect
	if audio_system:
		audio_system.play_sound("dismember")
	
	# Create the dismembered limb as an object (would need entity spawning system)
	# spawn_dismembered_limb(limb_name)
	
	return true

# Apply damage to a specific organ
func apply_organ_damage(organ_name, amount):
	if !organs.has(organ_name) or amount <= 0:
		return 0
	
	var organ = organs[organ_name]
	organ.damage += amount
	
	# Cap at max damage
	organ.damage = min(organ.damage, organ.max_damage)
	
	# Update organ status
	_update_organ_status(organ_name)
	
	# Vital organ failure can cause death
	if organ.is_vital and organ.is_failing and current_state != HealthState.DEAD:
		die(organ_name + " failure")
	
	# Emit signal
	emit_signal("organ_damaged", organ_name, amount)
	
	return amount

# === ADJUSTMENT FUNCTIONS ===
# Adjust brute loss (physical damage)
func adjustBruteLoss(amount, update_health = true):
	if godmode and amount > 0:
		return
	
	# Handle overheal
	if overheal > 0 and amount > 0:
		var reduction = min(amount, overheal)
		amount -= reduction
		overheal -= reduction
	
	bruteloss = max(0, bruteloss + amount)
	
	if update_health:
		updatehealth()

# Adjust burn loss (fire/heat damage)
func adjustFireLoss(amount, update_health = true):
	if godmode and amount > 0:
		return
	
	# Handle overheal
	if overheal > 0 and amount > 0:
		var reduction = min(amount, overheal)
		amount -= reduction
		overheal -= reduction
	
	fireloss = max(0, fireloss + amount)
	
	if update_health:
		updatehealth()

# Adjust toxin loss (poison damage)
func adjustToxLoss(amount, update_health = true):
	if godmode and amount > 0:
		return
	
	# Handle overheal
	if overheal > 0 and amount > 0:
		var reduction = min(amount, overheal)
		amount -= reduction
		overheal -= reduction
	
	toxloss = max(0, toxloss + amount)
	
	if update_health:
		updatehealth()

# Adjust oxygen loss (suffocation damage)
func adjustOxyLoss(amount, update_health = true):
	if godmode and amount > 0:
		return
	
	# Handle overheal
	if overheal > 0 and amount > 0:
		var reduction = min(amount, overheal)
		amount -= reduction
		overheal -= reduction
	
	oxyloss = max(0, oxyloss + amount)
	
	if update_health:
		updatehealth()

# Adjust clone loss (cellular damage)
func adjustCloneLoss(amount, update_health = true):
	if godmode and amount > 0:
		return
	
	cloneloss = max(0, cloneloss + amount)
	
	if update_health:
		updatehealth()

# Adjust brain loss (neurological damage)
func adjustBrainLoss(amount, update_health = true):
	if godmode and amount > 0:
		return
	
	brainloss = max(0, brainloss + amount)
	
	# Higher brain damage means more severe effects
	if brainloss > 20:
		add_status_effect("confused", 5.0, brainloss / 20)
	
	if brainloss > 50:
		add_status_effect("slurred_speech", 5.0, brainloss / 20)
	
	if brainloss > 80 and organs.has("brain"):
		organs["brain"].is_failing = true
	
	if update_health:
		updatehealth()

# Adjust stamina loss (exhaustion)
func adjustStaminaLoss(amount, update_health = true):
	if godmode and amount > 0:
		return
	
	staminaloss = clamp(staminaloss + amount, 0, 100)
	
	# Apply exhaustion effects if stamina is depleted
	if staminaloss >= 100 and !status_effects.has("exhausted"):
		add_status_effect("exhausted", 5.0)
	
	if update_health:
		updatehealth()

# Adjust blood volume
func adjust_blood_volume(amount):
	blood_volume = clamp(blood_volume + amount, 0, max_blood_volume)
	
	# Handle effects based on blood level
	if blood_volume < BLOOD_VOLUME_SAFE and blood_volume >= BLOOD_VOLUME_OKAY:
		# Slight effects
		if !status_effects.has("pale"):
			add_status_effect("pale", 10.0)
	elif blood_volume < BLOOD_VOLUME_OKAY and blood_volume >= BLOOD_VOLUME_BAD:
		# Moderate effects
		add_status_effect("dizzy", 5.0, 1.0)
	elif blood_volume < BLOOD_VOLUME_BAD:
		# Severe effects
		adjustOxyLoss(0.5)
		add_status_effect("weak", 5.0, 2.0)
		
		if blood_volume < BLOOD_VOLUME_SURVIVE:
			# Fatal blood loss
			apply_damage(1.0, DamageType.OXYGEN)
			
			if current_state != HealthState.DEAD and blood_volume < BLOOD_VOLUME_SURVIVE / 2:
				die("blood loss")
	
	# Emit signal
	emit_signal("blood_level_changed", blood_volume, max_blood_volume)

# Set bleeding rate
func set_bleeding_rate(rate):
	bleeding_rate = max(0, rate)
	
	if bleeding_rate > 0 and !status_effects.has("bleeding"):
		add_status_effect("bleeding", 10.0, bleeding_rate)
	elif bleeding_rate == 0 and status_effects.has("bleeding"):
		remove_status_effect("bleeding")

# === HEALTH UPDATE FUNCTIONS ===
# Update overall health value
func updatehealth():
	if godmode:
		health = max_health
		return
	
	# Calculate health
	health = max_health - bruteloss - fireloss - toxloss - oxyloss - cloneloss
	
	# Check for gibbing threshold
	if health <= HEALTH_THRESHOLD_GIBBED and !dead_threshold_passed:
		gib("extreme damage")
		return
	
	# Check health thresholds
	if health <= HEALTH_THRESHOLD_DEAD and current_state != HealthState.DEAD:
		die("damage")
	elif health <= HEALTH_THRESHOLD_CRIT and current_state == HealthState.ALIVE:
		enter_critical()
	elif health > HEALTH_THRESHOLD_CRIT and current_state == HealthState.CRITICAL:
		exit_critical()
	
	# Force lying state when at critical health
	if health <= HEALTH_THRESHOLD_CRIT and entity.has_method("lie_down") and !entity.is_lying:
		entity.lie_down(true)  # Force lying down
	
	# Update UI
	_update_health_ui()
	
	# Emit signal
	emit_signal("health_changed", health, max_health)

# Start dying
func enter_critical():
	if current_state == HealthState.CRITICAL:
		return
	
	current_state = HealthState.CRITICAL
	
	# Apply critical effects
	add_status_effect("unconscious", 10.0)
	
	# Random damage when critical
	if randf() < 0.1:
		adjustOxyLoss(1.0)
	
	# Emit signal
	emit_signal("entered_critical")
	
	# Update UI
	_update_health_ui()
	
	# Play sound
	if audio_system:
		audio_system.play_sound("critical_condition")

# Exit critical condition
func exit_critical():
	if current_state != HealthState.CRITICAL:
		return
	
	current_state = HealthState.ALIVE
	
	# Remove critical effects
	remove_status_effect("unconscious")
	
	# Emit signal
	emit_signal("exited_critical")
	
	# Update UI
	_update_health_ui()

# === STATE CHANGE FUNCTIONS ===
# Handle death
func die(cause = "unknown"):
	if current_state == HealthState.DEAD or godmode:
		return
	
	current_state = HealthState.DEAD
	cause_of_death = cause
	death_time = 0
	
	# Log death
	print("HealthSystem: Character died. Cause: " + cause)
	
	# Apply death effects
	add_status_effect("unconscious", 999999)
	
	# Drop all items
	_drop_all_items()
	
	# Stop movement
	if entity.has_method("set_state"):
		entity.set_state(entity.MovementState.IDLE)
	
	# Update visuals
	if sprite_system and sprite_system.has_method("update_death_state"):
		sprite_system.update_death_state(true)
	
	# Emit signal
	emit_signal("died", cause_of_death)
	
	# Play death sound
	if audio_system:
		audio_system.play_sound("death")
	
	# Update UI
	_update_health_ui()
	
	# Reset pulse
	pulse = 0

# Gib the entity
func gib(cause = "unknown"):
	if godmode:
		return
		
	# If already dead, update cause of death
	if current_state == HealthState.DEAD:
		cause_of_death = "gibbed: " + cause
	else:
		# Kill first, then gib
		die("gibbed: " + cause)
	
	# Mark as gibbed
	dead_threshold_passed = true
	
	# Play sound effect
	if audio_system:
		audio_system.play_sound("gib")
	
	# Update sprite if available
	if sprite_system and sprite_system.has_method("update_gibbed_state"):
		sprite_system.update_gibbed_state(true)
	
	# Spawn gibs
	spawn_gibs()
	
	# Handle removal of the entity
	await get_tree().create_timer(0.5).timeout
	
	# Emit signal for gibbing
	emit_signal("died", cause_of_death)  # Re-emit for potential listeners
	
	# Queue the entity for removal
	entity.queue_free()

# Spawn gibs at current location
func spawn_gibs():
	effect.visible = true
	effect.play("Gib")
	
	print("HealthSystem: Spawning gibs at position ", entity.position)

# Handle revival
func revive(admin_revive = false):
	if current_state != HealthState.DEAD:
		return false
	
	if !can_be_revived and !admin_revive:
		return false
	
	# Reset damage
	if admin_revive:
		bruteloss = 0
		fireloss = 0
		toxloss = 0
		oxyloss = 0
		cloneloss = 0
		brainloss = 0
		staminaloss = 0
	else:
		# Partial healing for normal revival
		bruteloss = max(0, bruteloss - 30)
		fireloss = max(0, fireloss - 30)
		toxloss = max(0, toxloss - 20)
		oxyloss = 0
		
		# Restore blood
		blood_volume = max(blood_volume, BLOOD_VOLUME_OKAY)
	
	# Reset cardiac arrest
	in_cardiac_arrest = false
	
	# Heal organs
	for organ_name in organs:
		if admin_revive:
			organs[organ_name].damage = 0
			organs[organ_name].is_failing = false
		else:
			organs[organ_name].damage = max(0, organs[organ_name].damage - 30)
			_update_organ_status(organ_name)
	
	# Heal limbs
	for limb_name in limbs:
		if admin_revive:
			limbs[limb_name].brute_damage = 0
			limbs[limb_name].burn_damage = 0
			limbs[limb_name].status = "normal"
		else:
			limbs[limb_name].brute_damage = max(0, limbs[limb_name].brute_damage - 30)
			limbs[limb_name].burn_damage = max(0, limbs[limb_name].burn_damage - 30)
			_update_limb_status(limb_name)
	
	# Reset bleeding
	bleeding_rate = 0
	
	# Remove death status effects
	remove_status_effect("unconscious")
	
	# Update health
	current_state = HealthState.ALIVE
	updatehealth()
	
	# Update visuals
	if sprite_system and sprite_system.has_method("update_death_state"):
		sprite_system.update_death_state(false)
	
	# Reset death time
	death_time = 0
	cause_of_death = ""
	
	# Emit signal
	emit_signal("revived")
	
	# Play revival sound
	if audio_system:
		audio_system.play_sound("revive")
	
	return true

# Enter cardiac arrest
func enter_cardiac_arrest():
	if in_cardiac_arrest or current_state == HealthState.DEAD:
		return
	
	in_cardiac_arrest = true
	
	# Heart stops
	pulse = 0
	
	# Begin oxygen loss
	add_status_effect("suffocating", 999999, 1.0)
	
	# Play heart stop sound
	if audio_system:
		audio_system.play_sound("heart_stop")

# Exit cardiac arrest
func exit_cardiac_arrest():
	if !in_cardiac_arrest:
		return
	
	in_cardiac_arrest = false
	
	# Heart resumes
	pulse = 60
	
	# Stop suffocation
	remove_status_effect("suffocating")
	
	# Play heart start sound
	if audio_system:
		audio_system.play_sound("heart_start")

# Apply CPR
func apply_cpr(amount = 3):
	# CPR can help if in cardiac arrest
	if in_cardiac_arrest and current_state != HealthState.DEAD:
		# Chance to restart heart
		if randf() < 0.2:
			exit_cardiac_arrest()
		
		# Provide oxygen
		adjustOxyLoss(-amount)
		return true
	
	# If in critical, provide some oxygen
	if current_state == HealthState.CRITICAL:
		adjustOxyLoss(-amount * 0.5)
		return true
	
	return false

# Apply defibrillation
func apply_defibrillation():
	# Only works in cardiac arrest or recently dead
	if in_cardiac_arrest and current_state != HealthState.DEAD:
		# Good chance to restart heart
		if randf() < 0.7:
			exit_cardiac_arrest()
			return true
	elif current_state == HealthState.DEAD and death_time < 300 and cause_of_death == "cardiac arrest":
		# Can revive from cardiac arrest within 5 minutes
		exit_cardiac_arrest()
		revive()
		return true
	
	return false

# === STATUS EFFECT FUNCTIONS ===
# Add a status effect
func add_status_effect(effect_name, duration, intensity = 1.0):
	# Skip if in godmode
	if godmode:
		return
	
	var was_new = !status_effects.has(effect_name)
	
	# Add or update the effect
	status_effects[effect_name] = {
		"duration": duration,
		"intensity": intensity,
		"start_time": Time.get_ticks_msec() / 1000.0
	}
	
	# Apply effect-specific behaviors
	match effect_name:
		"bleeding":
			# Update bleeding rate based on intensity
			bleeding_rate = max(bleeding_rate, intensity)
		"poisoned":
			# Apply initial toxin damage
			adjustToxLoss(intensity)
		"unconscious":
			# Make character lie down
			if entity.has_method("set_resting"):
				entity.set_resting(true)
		"slowed":
			# Apply movement speed modifier
			if entity.has_method("add_movement_modifier"):
				entity.add_movement_modifier("slowed", 0.5)
		"confused":
			# Apply confusion effect
			if entity.has_method("add_confusion"):
				entity.add_confusion(intensity)
	
	# Add status effect to entity if it supports it
	if entity.has_method("add_status_effect"):
		entity.add_status_effect(effect_name, duration, intensity)
	
	# Emit signal if it's a new effect
	if was_new:
		emit_signal("status_effect_added", effect_name, duration)

# Remove a status effect
func remove_status_effect(effect_name):
	if !status_effects.has(effect_name):
		return
	
	# Remove the effect
	status_effects.erase(effect_name)
	
	# Apply effect-specific cleanup
	match effect_name:
		"bleeding":
			bleeding_rate = 0
		"unconscious":
			# Only wake up if alive
			if current_state == HealthState.ALIVE:
				if entity.has_method("set_resting"):
					entity.set_resting(false)
		"slowed":
			# Remove movement speed modifier
			if entity.has_method("remove_movement_modifier"):
				entity.remove_movement_modifier("slowed")
		"confused":
			# Remove confusion effect
			if entity.has_method("clear_confusion"):
				entity.clear_confusion()
	
	# Remove from entity if it supports it
	if entity.has_method("remove_status_effect"):
		entity.remove_status_effect(effect_name)
	
	# Emit signal
	emit_signal("status_effect_removed", effect_name)

# Add a damage modifier
func add_damage_modifier(modifier_name, damage_type, multiplier, duration = -1):
	incoming_damage_modifiers[modifier_name] = {
		"damage_type": damage_type,
		"multiplier": multiplier,
		"duration": duration,
		"start_time": Time.get_ticks_msec() / 1000.0
	}

# Remove a damage modifier
func remove_damage_modifier(modifier_name):
	if incoming_damage_modifiers.has(modifier_name):
		incoming_damage_modifiers.erase(modifier_name)

# === BLOOD EFFECTS ===
# Check for blood splatter
func check_blood_splatter(damage, damtype = "brute", chancemod = 0, radius = 1):
	if damage <= 0 or current_state == HealthState.DEAD or blood_volume <= 0:
		return
	
	var chance = 25 # base chance
	
	if damtype == "brute":
		chance += 5
	
	chance += chancemod + (damage * 0.33)
	
	# Add to base chance from blood loss
	if blood_volume < BLOOD_VOLUME_NORMAL:
		chance += 10
	
	if randf() * 100 < chance:
		# Create blood effect
		_create_blood_effect(radius)
		
		# Reduce blood level
		adjust_blood_volume(-0.1 * damage)

# Create visual blood effect
func _create_blood_effect(radius = 1):
	# Handle blood splatter visuals
	if sprite_system and sprite_system.has_method("create_blood_splatter"):
		sprite_system.create_blood_splatter(radius)
	elif entity.has_method("add_splatter_floor"):
		# Fallback to entity method
		entity.add_splatter_floor(entity.current_tile_position)

# === VISUAL AND UI UPDATE FUNCTIONS ===
# Update limb visual status
func _update_limb_status(limb_name):
	var limb = limbs[limb_name]
	var total_damage = limb.brute_damage + limb.burn_damage
	
	# Update status based on damage
	if total_damage < 30:
		limb.status = "normal"
	elif total_damage < 60:
		limb.status = "wounded"
	else:
		limb.status = "mangled"
	
	# Update sprite if we have a sprite system
	if sprite_system and sprite_system.has_method("update_limb_damage"):
		sprite_system.update_limb_damage(limb_name, limb.status, limb.brute_damage, limb.burn_damage)

# Update organ status
func _update_organ_status(organ_name):
	var organ = organs[organ_name]
	
	# Update damaged state
	organ.is_damaged = organ.damage > 0
	
	# Update failure state
	if organ.damage > organ.max_damage * 0.75:
		organ.is_failing = true
	else:
		organ.is_failing = false
	
	# Special organ effects
	if organ_name == "heart" and organ.is_failing:
		enter_cardiac_arrest()
	elif organ_name == "heart" and !organ.is_failing and in_cardiac_arrest:
		exit_cardiac_arrest()

# Update health UI
func _update_health_ui():
	if !ui_system:
		return
	
	# Update health display
	if ui_system.has_method("update_health_display"):
		ui_system.update_health_display(health, max_health)
	
	# Update damage display
	if ui_system.has_method("update_damage_display"):
		ui_system.update_damage_display(bruteloss, fireloss, toxloss, oxyloss)
	
	# Update blood level
	if ui_system.has_method("update_blood_display"):
		ui_system.update_blood_display(blood_volume, max_blood_volume)

# Play damage sounds
func _play_damage_sound(damage_type, amount):
	if !audio_system or damage_mute_counter > 0:
		return
	
	var sound_name = ""
	var volume = min(0.3 + (amount / 30.0), 0.7)
	
	match damage_type:
		DamageType.BRUTE:
			sound_name = "hit"
		DamageType.BURN:
			sound_name = "burn"
		DamageType.TOXIN:
			sound_name = "tox"
		DamageType.OXYGEN:
			sound_name = "gasp"
		DamageType.CLONE:
			sound_name = "clone"
		DamageType.BRAIN:
			sound_name = "brain"
	
	if sound_name != "":
		audio_system.play_sound(sound_name, volume)
		
		# Add small cooldown to prevent sound spam
		damage_mute_counter = 5
		await get_tree().create_timer(0.1).timeout
		damage_mute_counter = max(0, damage_mute_counter - 1)

# Drop all items on death
func _drop_all_items():
	if !inventory_system:
		return
	
	# Drop all equipped items
	if inventory_system.has_method("drop_all_items"):
		inventory_system.drop_all_items()
	else:
		# Fallback - try to drop individual items
		var active_item = entity.get_active_item()
		if active_item and entity.has_method("drop_active_item"):
			entity.drop_active_item()

# === PUBLIC API ===
# Set max health
func set_max_health(new_max_health):
	max_health = max(1, new_max_health)
	health = min(health, max_health)
	emit_signal("health_changed", health, max_health)

# Set current health directly
func set_health(new_health):
	if godmode:
		health = max_health
		return
	
	health = clamp(new_health, HEALTH_THRESHOLD_DEAD, max_health)
	
	# Recalculate damages to match new health
	var total_damage = max_health - health
	
	# Distribute damage proportionally
	var damage_sum = bruteloss + fireloss + toxloss + oxyloss + cloneloss
	if damage_sum > 0:
		var scale_factor = total_damage / damage_sum
		bruteloss *= scale_factor
		fireloss *= scale_factor
		toxloss *= scale_factor
		oxyloss *= scale_factor
		cloneloss *= scale_factor
	else:
		# If no damage, apply as brute
		bruteloss = total_damage
	
	# Update health state
	updatehealth()

# Get current health percentage
func get_health_percent():
	return health / max_health

# Heal limb damage
func heal_limb_damage(limb_name, brute_amount = 0, burn_amount = 0):
	if !limbs.has(limb_name):
		return 0
	
	var limb = limbs[limb_name]
	var healed_amount = 0
	
	# Apply healing
	if brute_amount > 0:
		var brute_healed = min(limb.brute_damage, brute_amount)
		limb.brute_damage -= brute_healed
		healed_amount += brute_healed
	
	if burn_amount > 0:
		var burn_healed = min(limb.burn_damage, burn_amount)
		limb.burn_damage -= burn_healed
		healed_amount += burn_healed
	
	# Update limb status
	_update_limb_status(limb_name)
	
	return healed_amount

# Heal organ damage
func heal_organ_damage(organ_name, amount = 0):
	if !organs.has(organ_name) or amount <= 0:
		return 0
	
	var organ = organs[organ_name]
	var healed_amount = min(organ.damage, amount)
	
	# Apply healing
	organ.damage -= healed_amount
	
	# Update organ status
	_update_organ_status(organ_name)
	
	return healed_amount

# Toggle godmode
func toggle_godmode(enable = null):
	if enable != null:
		godmode = enable
	else:
		godmode = !godmode
	
	if godmode:
		health = max_health
		updatehealth()
	
	return godmode

# Apply full healing
func full_heal(admin_heal = false):
	# Reset all damage
	bruteloss = 0
	fireloss = 0
	toxloss = 0
	oxyloss = 0
	cloneloss = 0
	brainloss = 0
	staminaloss = 0
	
	# Restore blood
	blood_volume = max_blood_volume
	bleeding_rate = 0
	
	# Clear all status effects
	for effect in status_effects.keys():
		remove_status_effect(effect)
	
	# Reset cardiac arrest
	in_cardiac_arrest = false
	
	# Heal all organs
	for organ_name in organs:
		organs[organ_name].damage = 0
		organs[organ_name].is_failing = false
	
	# Heal all limbs
	for limb_name in limbs:
		limbs[limb_name].brute_damage = 0
		limbs[limb_name].burn_damage = 0
		limbs[limb_name].status = "normal"
		_update_limb_status(limb_name)
	
	# Reset trauma and shock
	traumatic_shock = 0
	shock_stage = 0
	
	# Add temporary overheal buffer
	overheal = 15
	
	# Update health
	if current_state == HealthState.DEAD and admin_heal:
		revive(true)
	else:
		updatehealth()
		
		if current_state == HealthState.CRITICAL:
			exit_critical()
	
	# Play healing sound
	if audio_system:
		audio_system.play_sound("heal")
		
	return true

# Apply armor values
func apply_armor(soft_armor_values, hard_armor_values = null):
	# Apply soft armor
	for key in soft_armor_values:
		if soft_armor.has(key):
			soft_armor[key] = soft_armor_values[key]
	
	# Apply hard armor if provided
	if hard_armor_values:
		for key in hard_armor_values:
			if hard_armor.has(key):
				hard_armor[key] = hard_armor_values[key]

# Get current state
func get_state():
	return current_state

# Get full status report
func get_status_report():
	var report = {
		"health": health,
		"max_health": max_health,
		"state": ["alive", "critical", "dead"][current_state],
		"damage": {
			"brute": bruteloss,
			"burn": fireloss,
			"toxin": toxloss,
			"oxygen": oxyloss,
			"clone": cloneloss,
			"brain": brainloss,
			"stamina": staminaloss
		},
		"blood": {
			"volume": blood_volume,
			"max": max_blood_volume,
			"type": blood_type,
			"bleeding_rate": bleeding_rate
		},
		"vital_signs": {
			"pulse": pulse,
			"cardiac_arrest": in_cardiac_arrest,
			"body_temp": body_temperature,
			"shock_stage": shock_stage
		},
		"status_effects": status_effects.keys(),
		"cause_of_death": cause_of_death,
		"death_time": death_time
	}
	
	return report
