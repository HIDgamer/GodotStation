extends Node
class_name BloodSystem

# === SIGNALS ===
signal blood_volume_changed(new_amount, max_amount)
signal bleeding_started(rate)
signal bleeding_stopped()
signal blood_type_changed(new_type)
signal blood_lost(amount, source)
signal blood_pulse_changed(new_pulse)

# === CONSTANTS ===
const BLOOD_VOLUME_NORMAL = 560
const BLOOD_VOLUME_SAFE = 475
const BLOOD_VOLUME_OKAY = 336
const BLOOD_VOLUME_BAD = 224
const BLOOD_VOLUME_SURVIVE = 122
const BLOOD_VOLUME_THRESHOLD_LOSS = 336

# Blood types and compatibility
const BLOOD_TYPES = ["O-", "O+", "A-", "A+", "B-", "B+", "AB-", "AB+"]
const BLOOD_COMPATIBILITY = {
	"O-": ["O-"],
	"O+": ["O-", "O+"],
	"A-": ["A-", "O-"],
	"A+": ["A-", "A+", "O-", "O+"],
	"B-": ["B-", "O-"],
	"B+": ["B-", "B+", "O-", "O+"],
	"AB-": ["A-", "B-", "O-", "AB-"],
	"AB+": ["A-", "A+", "B-", "B+", "O-", "O+", "AB-", "AB+"]
}

# Default blood colors by species
const BLOOD_COLORS = {
	"human": Color(0.8, 0, 0),  # Red
	"synthetic": Color(1, 1, 1),  # White
	"xeno": Color(0.7, 1, 0.1),  # Acid green
	"robot": Color(0.3, 0.3, 0.3)  # Gray/oil
}

# === MEMBER VARIABLES ===
var blood_type: String = "O+"
var blood_volume: float = BLOOD_VOLUME_NORMAL
var max_blood_volume: float = BLOOD_VOLUME_NORMAL
var bleeding_rate: float = 0.0
var pulse: int = 60  # Heartbeats per minute
var blood_color: Color = Color(0.8, 0, 0)  # Default human red
var blood_flow_multiplier: float = 1.0  # Modifier for bleeding rate
var in_cardiac_arrest: bool = false
var has_heartbeat: bool = true
var has_circulation: bool = true
var species_type: String = "human"

# === CONNECTIONS ===
var entity = null  # The parent entity
var health_system = null
var audio_system = null
var sprite_system = null
var inventory_system = null

# === INITIALIZATION ===
func _ready():
	entity = get_parent()
	_find_systems()
	
	# Connect to timer for periodic updates
	var timer = Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_on_update_tick)
	add_child(timer)
	
	# Randomize blood type if not set
	if blood_type == "O+":
		randomize()
		blood_type = BLOOD_TYPES[randi() % BLOOD_TYPES.size()]
		
	# Set blood color based on species
	if BLOOD_COLORS.has(species_type):
		blood_color = BLOOD_COLORS[species_type]

func _find_systems():
	# Try to find health system
	health_system = entity.get_node_or_null("HealthSystem")
	
	# Try to find audio system
	audio_system = entity.get_node_or_null("AudioSystem")
	
	# Try to find sprite system
	sprite_system = entity.get_node_or_null("SpriteSystem")
	
	# Try to find inventory system
	inventory_system = entity.get_node_or_null("InventorySystem")
	
	print("BloodSystem: Connected to systems")
	print("  - Health: ", "Found" if health_system else "Not found")
	print("  - Audio: ", "Found" if audio_system else "Not found")
	print("  - Sprite: ", "Found" if sprite_system else "Not found")

# === PROCESS FUNCTIONS ===
func _process(delta):
	# Process bleeding
	if bleeding_rate > 0:
		adjust_blood_volume(-bleeding_rate * delta)
		
		# Chance to leave blood decals on the ground
		if randf() < 0.1 * bleeding_rate * delta:
			create_blood_splatter(1)

func _on_update_tick():
	# Don't process if dead
	if health_system and health_system.current_state == health_system.HealthState.DEAD:
		return
		
	# Blood regeneration if not bleeding too badly
	if bleeding_rate < 0.5 and blood_volume < BLOOD_VOLUME_NORMAL:
		var regen_rate = 0.1  # Base regeneration
		
		# Reduce regeneration if low on blood
		if blood_volume < BLOOD_VOLUME_OKAY:
			regen_rate = 0.05
			
		# Better regeneration with food (would connect to a nutrition system)
		# if nutrition_system and nutrition_system.nutrition > NUTRITION_WELL_FED:
		#     regen_rate = 0.3
		
		adjust_blood_volume(regen_rate)
	
	# Update pulse based on cardiac status and blood volume
	update_pulse()
	
	# Process cardiac arrest effects
	if in_cardiac_arrest and has_heartbeat:
		process_cardiac_arrest()

# === BLOOD VOLUME FUNCTIONS ===
# Adjust blood volume with clamping and effects
func adjust_blood_volume(amount):
	var old_volume = blood_volume
	blood_volume = clamp(blood_volume + amount, 0, max_blood_volume)
	
	# If we lost blood, record it
	if amount < 0:
		blood_lost.emit(-amount, "bleeding")
	
	# Apply effects based on blood level transitions
	var effect_reported = false
	
	if old_volume >= BLOOD_VOLUME_SAFE and blood_volume < BLOOD_VOLUME_SAFE:
		report_blood_level_effect("You feel a bit lightheaded.", "pale")
		effect_reported = true
		
	if old_volume >= BLOOD_VOLUME_OKAY and blood_volume < BLOOD_VOLUME_OKAY:
		report_blood_level_effect("You feel dizzy and weak.", "dizzy")
		effect_reported = true
		
	if old_volume >= BLOOD_VOLUME_BAD and blood_volume < BLOOD_VOLUME_BAD:
		report_blood_level_effect("Your body feels very heavy and cold.", "weak")
		effect_reported = true
		
	if old_volume >= BLOOD_VOLUME_SURVIVE and blood_volume < BLOOD_VOLUME_SURVIVE:
		report_blood_level_effect("You feel your consciousness fading...", "unconscious")
		effect_reported = true
		
		# Apply oxygen damage from extreme blood loss
		if health_system:
			health_system.adjustOxyLoss(1.0)
		
		# Check for death from blood loss
		if blood_volume < BLOOD_VOLUME_SURVIVE / 2 and health_system:
			health_system.die("blood loss")
	
	# Emit signal for UI updates
	blood_volume_changed.emit(blood_volume, max_blood_volume)
	
	# If health system exists, inform it as well
	if health_system and health_system.has_method("on_blood_volume_changed"):
		health_system.on_blood_volume_changed(blood_volume, max_blood_volume)
	
	return blood_volume

# Set blood volume directly
func set_blood_volume(amount):
	var clamped_amount = clamp(amount, 0, max_blood_volume)
	blood_volume = clamped_amount
	blood_volume_changed.emit(blood_volume, max_blood_volume)
	return blood_volume

# Set max blood volume
func set_max_blood_volume(amount):
	max_blood_volume = max(0, amount)
	blood_volume = min(blood_volume, max_blood_volume)
	blood_volume_changed.emit(blood_volume, max_blood_volume)
	return max_blood_volume

# Set bleeding rate
func set_bleeding_rate(rate):
	var old_rate = bleeding_rate
	bleeding_rate = max(0, rate * blood_flow_multiplier)
	
	# Emit signals based on state change
	if bleeding_rate > 0 and old_rate == 0:
		bleeding_started.emit(bleeding_rate)
		
		# Update sprite system if available
		if sprite_system and sprite_system.has_method("start_bleeding_effect"):
			sprite_system.start_bleeding_effect()
			
		# Apply status effect if health system available
		if health_system:
			health_system.add_status_effect("bleeding", 10.0, bleeding_rate)
	
	elif bleeding_rate == 0 and old_rate > 0:
		bleeding_stopped.emit()
		
		# Update sprite system if available
		if sprite_system and sprite_system.has_method("stop_bleeding_effect"):
			sprite_system.stop_bleeding_effect()
			
		# Remove status effect if health system available
		if health_system:
			health_system.remove_status_effect("bleeding")
	
	return bleeding_rate

# Add to current bleeding rate
func add_bleeding(amount):
	return set_bleeding_rate(bleeding_rate + amount)

# Reduce current bleeding rate
func reduce_bleeding(amount):
	return set_bleeding_rate(bleeding_rate - amount)

# Stop bleeding entirely
func stop_bleeding():
	return set_bleeding_rate(0)

# Report blood level effect to player
func report_blood_level_effect(message, effect_name):
	# Display message if entity has a sensory system
	if entity.get_node_or_null("SensorySystem"):
		entity.get_node("SensorySystem").display_message(message)
	
	# Apply status effect if health system available
	if health_system:
		health_system.add_status_effect(effect_name, 10.0)

# === BLOOD CIRCULATION FUNCTIONS ===
# Update pulse based on health and blood status
func update_pulse():
	if !has_heartbeat:
		pulse = 0
		return pulse
	
	if in_cardiac_arrest:
		pulse = 0
		return pulse
	
	# Base pulse calculation
	var health_percent = 1.0
	if health_system:
		health_percent = health_system.health / health_system.max_health
	
	var new_pulse = int(60 + (1.0 - health_percent) * 40)
	
	# Adjust for blood volume
	if blood_volume < BLOOD_VOLUME_SAFE:
		new_pulse += int((BLOOD_VOLUME_SAFE - blood_volume) / 2.5)
	
	# Limit to reasonable range
	new_pulse = clamp(new_pulse, 0, 160)
	
	# Update if changed
	if new_pulse != pulse:
		pulse = new_pulse
		blood_pulse_changed.emit(pulse)
	
	return pulse

# Handle cardiac arrest
func process_cardiac_arrest():
	# In cardiac arrest, no blood is pumped
	if health_system:
		# Oxygen loss increases when heart isn't beating
		health_system.adjustOxyLoss(1.0)
		
		# Random chance to exit cardiac arrest naturally (very small)
		if randf() < 0.01:  # 1% chance per second
			exit_cardiac_arrest()

# Enter cardiac arrest state
func enter_cardiac_arrest():
	if in_cardiac_arrest:
		return
	
	in_cardiac_arrest = true
	
	# Heart stops
	pulse = 0
	blood_pulse_changed.emit(pulse)
	
	# Begin oxygen loss
	if health_system:
		health_system.add_status_effect("suffocating", 999999, 1.0)
	
	# Play heart stop sound
	if audio_system:
		audio_system.play_sound("heart_stop")

# Exit cardiac arrest state
func exit_cardiac_arrest():
	if !in_cardiac_arrest:
		return
	
	in_cardiac_arrest = false
	
	# Heart resumes
	update_pulse()
	
	# Stop suffocation
	if health_system:
		health_system.remove_status_effect("suffocating")
	
	# Play heart start sound
	if audio_system:
		audio_system.play_sound("heart_start")

# Apply CPR to patient
func apply_cpr(amount = 3):
	# CPR can help if in cardiac arrest
	if in_cardiac_arrest:
		# Chance to restart heart
		if randf() < 0.2:
			exit_cardiac_arrest()
		
		# Provide oxygen if health system exists
		if health_system:
			health_system.adjustOxyLoss(-amount)
		
		return true
	
	# CPR can help in critical state too
	if health_system and health_system.current_state == health_system.HealthState.CRITICAL:
		health_system.adjustOxyLoss(-amount * 0.5)
		return true
	
	return false

# Apply defibrillation to patient
func apply_defibrillation():
	# Only works in cardiac arrest or recently dead
	if in_cardiac_arrest and health_system and health_system.current_state != health_system.HealthState.DEAD:
		# Good chance to restart heart
		if randf() < 0.7:
			exit_cardiac_arrest()
			return true
	elif health_system and health_system.current_state == health_system.HealthState.DEAD and health_system.death_time < 300 and health_system.cause_of_death == "cardiac arrest":
		# Can revive from cardiac arrest within 5 minutes
		exit_cardiac_arrest()
		if health_system.has_method("revive"):
			health_system.revive()
		return true
	
	return false

# === BLOOD EFFECTS FUNCTIONS ===
# Create visual blood effect
func create_blood_splatter(radius = 1):
	# Handle blood splatter visuals
	if sprite_system and sprite_system.has_method("create_blood_splatter"):
		sprite_system.create_blood_splatter(radius, blood_color)
	elif entity.has_method("add_splatter_floor"):
		# Fallback to entity method
		entity.add_splatter_floor(entity.global_position, blood_color)
	
	# Could implement here an actual decal spawning system
	# Example:
	# var blood_decal = preload("res://scenes/effects/blood_splatter.tscn").instantiate()
	# blood_decal.position = entity.position
	# blood_decal.modulate = blood_color
	# get_tree().current_scene.add_child(blood_decal)

# Check for blood splatter based on damage
func check_blood_splatter(damage, damtype = "brute", chancemod = 0, radius = 1):
	if damage <= 0 or blood_volume <= 0:
		return
	
	if !has_circulation:
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
		create_blood_splatter(radius)
		
		# Reduce blood level
		adjust_blood_volume(-0.1 * damage)
		
		return true
	
	return false

# === BLOOD TRANSFUSION FUNCTIONS ===
# Check if a blood type is compatible for transfusion
func is_blood_compatible(donor_type):
	if !BLOOD_COMPATIBILITY.has(blood_type):
		return true  # Default to compatibility if unknown type
	
	return donor_type in BLOOD_COMPATIBILITY[blood_type]

# Add blood from a blood pack or donor
func add_blood(amount, donor_type = null):
	# If no donor type specified, assume universal donor
	if donor_type == null:
		donor_type = "O-"
	
	# Check compatibility
	if !is_blood_compatible(donor_type):
		# Blood type mismatch - causes toxin damage
		if health_system:
			health_system.adjustToxLoss(amount * 0.5)
			
		if entity.get_node_or_null("SensorySystem"):
			entity.get_node("SensorySystem").display_message("Your body rejects the transfusion!", "red")
			
		return false
	
	# Add blood volume
	adjust_blood_volume(amount)
	
	if entity.get_node_or_null("SensorySystem"):
		entity.get_node("SensorySystem").display_message("You feel the blood flow through your veins!", "green")
	
	return true

# Take blood for a blood pack or transfusion
func take_blood(amount):
	if blood_volume < amount + BLOOD_VOLUME_SAFE:
		# Not enough blood to safely take
		return 0
	
	# Remove blood
	adjust_blood_volume(-amount)
	
	# Return blood data for the taken amount
	return {
		"amount": amount,
		"type": blood_type,
		"color": blood_color
	}

# Set the entity's blood type
func set_blood_type(new_type):
	if new_type in BLOOD_TYPES:
		blood_type = new_type
		blood_type_changed.emit(new_type)
		return true
	return false

# === HELPER FUNCTIONS ===
# Get pulse description for medical readouts
func get_pulse_description():
	if pulse == 0:
		return "no pulse"
	elif pulse < 40:
		return "very weak pulse"
	elif pulse < 60:
		return "weak pulse"
	elif pulse < 90:
		return "normal pulse"
	elif pulse < 120:
		return "elevated pulse"
	else:
		return "extremely rapid pulse"

# Get blood level description for medical readouts
func get_blood_level_description():
	if blood_volume < BLOOD_VOLUME_SURVIVE:
		return "catastrophic blood loss"
	elif blood_volume < BLOOD_VOLUME_BAD:
		return "severe blood loss"
	elif blood_volume < BLOOD_VOLUME_OKAY:
		return "significant blood loss"
	elif blood_volume < BLOOD_VOLUME_SAFE:
		return "mild blood loss"
	else:
		return "normal blood level"

# Get bleeding description
func get_bleeding_description():
	if bleeding_rate == 0:
		return "not bleeding"
	elif bleeding_rate < 1.0:
		return "minor bleeding"
	elif bleeding_rate < 3.0:
		return "moderate bleeding"
	elif bleeding_rate < 6.0:
		return "severe bleeding"
	else:
		return "catastrophic bleeding"

# Set blood color
func set_blood_color(color):
	blood_color = color
	
	# Update any visual effects
	if sprite_system and sprite_system.has_method("update_blood_color"):
		sprite_system.update_blood_color(color)

# === WOUND AND BLEEDING TREATMENT ===
# Apply bandage to reduce bleeding
func apply_bandage(effectiveness = 1.0):
	# Standard bandage reduces bleeding by 1.0-2.0 depending on quality
	var reduction = min(bleeding_rate, 1.0 * effectiveness)
	
	# Reduce bleeding
	set_bleeding_rate(bleeding_rate - reduction)
	
	# Play sound if available
	if audio_system:
		audio_system.play_sound("bandage", 0.5)
	
	# Send message
	if entity.get_node_or_null("SensorySystem"):
		var message = "The bandage helps stop the bleeding."
		if bleeding_rate <= 0:
			message = "The bandage completely stops the bleeding."
		entity.get_node("SensorySystem").display_message(message)
	
	return reduction

# Apply quick-clotting agent
func apply_quickclot(effectiveness = 1.0):
	# Quick-clot is more effective, reducing bleeding by 3.0-6.0
	var reduction = min(bleeding_rate, 3.0 * effectiveness)
	
	# Reduce bleeding
	set_bleeding_rate(bleeding_rate - reduction)
	
	# Play sound if available
	if audio_system:
		audio_system.play_sound("spray_med", 0.4)
	
	# Send message
	if entity.get_node_or_null("SensorySystem"):
		var message = "The quick-clotting agent significantly reduces the bleeding."
		if bleeding_rate <= 0:
			message = "The quick-clotting agent completely stops the bleeding."
		entity.get_node("SensorySystem").display_message(message)
	
	return reduction

# Apply sutures or staples (more permanent bleeding solution)
func apply_sutures(effectiveness = 1.0):
	# Sutures can stop bleeding entirely with high effectiveness
	var reduction = min(bleeding_rate, 10.0 * effectiveness)
	
	# Reduce bleeding
	set_bleeding_rate(bleeding_rate - reduction)
	
	# Play sound if available
	if audio_system:
		audio_system.play_sound("suture", 0.5)
	
	# Send message
	if entity.get_node_or_null("SensorySystem"):
		entity.get_node("SensorySystem").display_message("The wounds are sutured closed, stopping the bleeding.")
	
	return reduction

# Apply blood-affecting drug
func apply_blood_drug(drug_type, potency = 1.0):
	match drug_type:
		"hemostat":
			# Reduce bleeding rate over time
			set_bleeding_rate(bleeding_rate * (1.0 - (0.3 * potency)))
			return true
			
		"blood_booster":
			# Temporarily increase blood regeneration
			blood_flow_multiplier = max(0.0, blood_flow_multiplier - (0.5 * potency))
			
			# Schedule return to normal
			await get_tree().create_timer(30.0 * potency).timeout
			blood_flow_multiplier = 1.0
			return true
			
		"anticoagulant":
			# Increase bleeding and prevent clotting
			blood_flow_multiplier = blood_flow_multiplier + (0.5 * potency)
			
			# Schedule return to normal
			await get_tree().create_timer(20.0 * potency).timeout
			blood_flow_multiplier = 1.0
			return true
			
		"synthblood":
			# Synthetic blood replacement (less effective than real blood)
			adjust_blood_volume(30.0 * potency)
			return true
	
	return false

# For revival functions
func restore_blood():
	blood_volume = BLOOD_VOLUME_NORMAL
	bleeding_rate = 0
	in_cardiac_arrest = false
	update_pulse()
	
	# Emit signals
	blood_volume_changed.emit(blood_volume, max_blood_volume)
	bleeding_stopped.emit()
	
	return true

# === DAMAGE HANDLING ===
# Handle physical damage that might cause bleeding
func handle_brute_damage(amount, zone = null):
	# Skip if no circulation
	if !has_circulation:
		return 0
	
	# Calculate bleeding chance based on damage
	var bleed_chance = amount * 5  # 5% per damage point
	
	# Adjust based on zone if provided (some areas bleed more)
	if zone:
		match zone:
			"head":
				bleed_chance *= 1.5  # Head wounds bleed a lot
			"chest":
				bleed_chance *= 1.2
			"groin":
				bleed_chance *= 1.3
	
	# Roll for bleeding
	if randf() * 100 < bleed_chance:
		# Calculate bleeding amount based on damage
		var bleed_amount = amount * 0.1  # 0.1 bleeding per damage point
		
		# Add to current bleeding rate
		add_bleeding(bleed_amount)
		
		# Create blood splatter
		create_blood_splatter()
		
		return bleed_amount
	
	return 0

# Handle burn damage, which can cauterize bleeding
func handle_burn_damage(amount, zone = null):
	# Skip if no circulation
	if !has_circulation:
		return 0
	
	# High burn damage can actually reduce bleeding (cauterize)
	if amount > 15 and bleeding_rate > 0:
		var cauterize_amount = min(bleeding_rate, amount * 0.1)
		reduce_bleeding(cauterize_amount)
		
		# Message
		if entity.get_node_or_null("SensorySystem"):
			entity.get_node("SensorySystem").display_message("The intense heat cauterizes the bleeding wounds!")
		
		return -cauterize_amount
	
	# Moderate burn can still cause some bleeding
	elif amount > 5 and bleeding_rate < 3.0:
		var bleed_amount = amount * 0.05
		add_bleeding(bleed_amount)
		return bleed_amount
	
	return 0

# Get detailed blood status for medical scanners
func get_blood_status():
	return {
		"blood_type": blood_type,
		"blood_volume": blood_volume,
		"max_blood_volume": max_blood_volume,
		"percent_volume": (blood_volume / max_blood_volume) * 100,
		"bleeding_rate": bleeding_rate,
		"pulse": pulse,
		"in_cardiac_arrest": in_cardiac_arrest,
		"status": get_blood_level_description(),
		"bleeding_status": get_bleeding_description(),
		"pulse_description": get_pulse_description()
	}
