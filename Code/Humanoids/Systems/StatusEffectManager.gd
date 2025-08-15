extends Node
class_name StatusEffectManager

# === SIGNALS ===
signal status_effect_added(effect_id, effect_name, duration, intensity)
signal status_effect_removed(effect_id, effect_name)
signal status_effect_refreshed(effect_id, effect_name, new_duration, new_intensity)
signal status_effect_stack_changed(effect_id, effect_name, new_stack_count)
signal status_effect_intensity_changed(effect_id, effect_name, new_intensity)

# === CONSTANTS AND ENUMS ===
enum EffectType {
	POSITIVE,  # Buffs
	NEUTRAL,   # Neither good nor bad
	NEGATIVE   # Debuffs
}

enum EffectStackingType {
	REPLACE,         # New effect replaces old one entirely
	REFRESH_DURATION, # Keep intensity, refresh duration
	REFRESH_INTENSITY, # Keep duration, refresh intensity
	REFRESH_BOTH,     # Refresh both duration and intensity
	ADD_DURATION,     # Add duration to existing effect
	ADD_INTENSITY,    # Add intensity to existing effect
	STACK_SEPARATE,   # Track as separate stacks
	HIGHEST_WINS      # Keep the strongest effect only
}

# === EFFECT DEFINITIONS ===
const EFFECT_DEFINITIONS = {
	"stunned": {
		"name": "Stunned",
		"description": "Unable to move or act",
		"type": EffectType.NEGATIVE,
		"stacking_type": EffectStackingType.REFRESH_DURATION,
		"max_stacks": 1,
		"max_intensity": 3.0,
		"icon": "stun_icon",
		"effect_flags": ["movement_restricting", "action_restricting"],
		"apply_function": "_apply_stunned",
		"remove_function": "_remove_stunned",
		"update_function": "_update_stunned"
	},
	"poisoned": {
		"name": "Poisoned",
		"description": "Taking toxin damage over time",
		"type": EffectType.NEGATIVE,
		"stacking_type": EffectStackingType.HIGHEST_WINS,
		"max_stacks": 1,
		"max_intensity": 5.0,
		"icon": "poison_icon",
		"effect_flags": [],
		"apply_function": "_apply_poisoned",
		"remove_function": "_remove_poisoned",
		"update_function": "_update_poisoned"
	},
	"bleeding": {
		"name": "Bleeding",
		"description": "Losing blood over time",
		"type": EffectType.NEGATIVE,
		"stacking_type": EffectStackingType.HIGHEST_WINS,
		"max_stacks": 1,
		"max_intensity": 10.0,
		"icon": "bleed_icon",
		"effect_flags": [],
		"apply_function": "_apply_bleeding",
		"remove_function": "_remove_bleeding",
		"update_function": "_update_bleeding"
	},
	"burned": {
		"name": "Burned",
		"description": "Suffering from burns",
		"type": EffectType.NEGATIVE,
		"stacking_type": EffectStackingType.HIGHEST_WINS,
		"max_stacks": 1,
		"max_intensity": 5.0,
		"icon": "burn_icon",
		"effect_flags": [],
		"apply_function": "_apply_burned",
		"remove_function": "_remove_burned",
		"update_function": "_update_burned"
	},
	"irradiated": {
		"name": "Irradiated",
		"description": "Suffering from radiation poisoning",
		"type": EffectType.NEGATIVE,
		"stacking_type": EffectStackingType.ADD_INTENSITY,
		"max_stacks": 1,
		"max_intensity": 10.0,
		"icon": "radiation_icon",
		"effect_flags": [],
		"apply_function": "_apply_irradiated",
		"remove_function": "_remove_irradiated",
		"update_function": "_update_irradiated"
	},
	"confused": {
		"name": "Confused",
		"description": "Movement direction is randomized",
		"type": EffectType.NEGATIVE,
		"stacking_type": EffectStackingType.REFRESH_BOTH,
		"max_stacks": 1,
		"max_intensity": 5.0,
		"icon": "confusion_icon",
		"effect_flags": ["mental"],
		"apply_function": "_apply_confused",
		"remove_function": "_remove_confused",
		"update_function": "_update_confused"
	},
	"slowed": {
		"name": "Slowed",
		"description": "Movement speed reduced",
		"type": EffectType.NEGATIVE,
		"stacking_type": EffectStackingType.HIGHEST_WINS,
		"max_stacks": 1,
		"max_intensity": 5.0,
		"icon": "slow_icon",
		"effect_flags": ["movement_impairing"],
		"apply_function": "_apply_slowed",
		"remove_function": "_remove_slowed",
		"update_function": "_update_slowed"
	},
	"weakened": {
		"name": "Weakened",
		"description": "Strength and damage reduced",
		"type": EffectType.NEGATIVE,
		"stacking_type": EffectStackingType.HIGHEST_WINS,
		"max_stacks": 1,
		"max_intensity": 5.0,
		"icon": "weak_icon",
		"effect_flags": ["combat_impairing"],
		"apply_function": "_apply_weakened",
		"remove_function": "_remove_weakened",
		"update_function": "_update_weakened"
	},
	"dizzy": {
		"name": "Dizzy",
		"description": "Vision swirls, affects aim",
		"type": EffectType.NEGATIVE,
		"stacking_type": EffectStackingType.REFRESH_BOTH,
		"max_stacks": 1,
		"max_intensity": 3.0,
		"icon": "dizzy_icon",
		"effect_flags": ["mental", "vision_impairing"],
		"apply_function": "_apply_dizzy",
		"remove_function": "_remove_dizzy",
		"update_function": "_update_dizzy"
	},
	"blurred_vision": {
		"name": "Blurred Vision",
		"description": "Vision is unclear",
		"type": EffectType.NEGATIVE,
		"stacking_type": EffectStackingType.HIGHEST_WINS,
		"max_stacks": 1,
		"max_intensity": 5.0,
		"icon": "blur_icon",
		"effect_flags": ["vision_impairing"],
		"apply_function": "_apply_blurred_vision",
		"remove_function": "_remove_blurred_vision",
		"update_function": "_update_blurred_vision"
	},
	"unconscious": {
		"name": "Unconscious",
		"description": "Knocked out and helpless",
		"type": EffectType.NEGATIVE,
		"stacking_type": EffectStackingType.REFRESH_DURATION,
		"max_stacks": 1,
		"max_intensity": 1.0,
		"icon": "unconscious_icon",
		"effect_flags": ["movement_restricting", "action_restricting", "unconsciousness"],
		"apply_function": "_apply_unconscious",
		"remove_function": "_remove_unconscious",
		"update_function": "_update_unconscious"
	},
	"suffocating": {
		"name": "Suffocating",
		"description": "Unable to breathe",
		"type": EffectType.NEGATIVE,
		"stacking_type": EffectStackingType.REFRESH_BOTH,
		"max_stacks": 1,
		"max_intensity": 3.0,
		"icon": "suffocate_icon",
		"effect_flags": [],
		"apply_function": "_apply_suffocating",
		"remove_function": "_remove_suffocating",
		"update_function": "_update_suffocating"
	},
	"slurred_speech": {
		"name": "Slurred Speech",
		"description": "Difficulty speaking clearly",
		"type": EffectType.NEGATIVE,
		"stacking_type": EffectStackingType.HIGHEST_WINS,
		"max_stacks": 1,
		"max_intensity": 3.0,
		"icon": "slur_icon",
		"effect_flags": ["communication_impairing"],
		"apply_function": "_apply_slurred_speech",
		"remove_function": "_remove_slurred_speech",
		"update_function": "_update_slurred_speech"
	},
	"paralyzed": {
		"name": "Paralyzed",
		"description": "Unable to move",
		"type": EffectType.NEGATIVE,
		"stacking_type": EffectStackingType.REFRESH_DURATION,
		"max_stacks": 1,
		"max_intensity": 2.0,
		"icon": "paralyze_icon",
		"effect_flags": ["movement_restricting"],
		"apply_function": "_apply_paralyzed",
		"remove_function": "_remove_paralyzed",
		"update_function": "_update_paralyzed"
	},
	"exhausted": {
		"name": "Exhausted",
		"description": "Stamina recovery reduced",
		"type": EffectType.NEGATIVE,
		"stacking_type": EffectStackingType.REFRESH_DURATION,
		"max_stacks": 1,
		"max_intensity": 3.0,
		"icon": "exhausted_icon",
		"effect_flags": ["stamina_impairing"],
		"apply_function": "_apply_exhausted",
		"remove_function": "_remove_exhausted",
		"update_function": "_update_exhausted"
	},
	"pain": {
		"name": "Pain",
		"description": "Suffering from physical pain",
		"type": EffectType.NEGATIVE,
		"stacking_type": EffectStackingType.HIGHEST_WINS,
		"max_stacks": 1,
		"max_intensity": 10.0,
		"icon": "pain_icon",
		"effect_flags": ["mental"],
		"apply_function": "_apply_pain",
		"remove_function": "_remove_pain",
		"update_function": "_update_pain"
	},
	"regenerating": {
		"name": "Regenerating",
		"description": "Recovering health over time",
		"type": EffectType.POSITIVE,
		"stacking_type": EffectStackingType.REFRESH_BOTH,
		"max_stacks": 1,
		"max_intensity": 5.0,
		"icon": "regen_icon",
		"effect_flags": [],
		"apply_function": "_apply_regenerating",
		"remove_function": "_remove_regenerating",
		"update_function": "_update_regenerating"
	},
	"strength_buff": {
		"name": "Strength Buff",
		"description": "Increased strength and damage",
		"type": EffectType.POSITIVE,
		"stacking_type": EffectStackingType.HIGHEST_WINS,
		"max_stacks": 1,
		"max_intensity": 5.0,
		"icon": "strength_icon",
		"effect_flags": [],
		"apply_function": "_apply_strength_buff",
		"remove_function": "_remove_strength_buff",
		"update_function": "_update_strength_buff"
	},
	"speed_buff": {
		"name": "Speed Buff",
		"description": "Increased movement speed",
		"type": EffectType.POSITIVE,
		"stacking_type": EffectStackingType.HIGHEST_WINS,
		"max_stacks": 1,
		"max_intensity": 3.0,
		"icon": "speed_icon",
		"effect_flags": [],
		"apply_function": "_apply_speed_buff",
		"remove_function": "_remove_speed_buff",
		"update_function": "_update_speed_buff"
	},
	"painkiller": {
		"name": "Painkiller",
		"description": "Reduced pain and damage effects",
		"type": EffectType.POSITIVE,
		"stacking_type": EffectStackingType.HIGHEST_WINS,
		"max_stacks": 1,
		"max_intensity": 5.0,
		"icon": "painkiller_icon",
		"effect_flags": [],
		"apply_function": "_apply_painkiller",
		"remove_function": "_remove_painkiller",
		"update_function": "_update_painkiller"
	},
	"adrenaline": {
		"name": "Adrenaline",
		"description": "Reduced pain and increased strength/speed",
		"type": EffectType.POSITIVE,
		"stacking_type": EffectStackingType.REFRESH_BOTH,
		"max_stacks": 1,
		"max_intensity": 3.0,
		"icon": "adrenaline_icon",
		"effect_flags": [],
		"apply_function": "_apply_adrenaline",
		"remove_function": "_remove_adrenaline",
		"update_function": "_update_adrenaline"
	},
	"stealth": {
		"name": "Stealth",
		"description": "Harder to detect",
		"type": EffectType.POSITIVE,
		"stacking_type": EffectStackingType.REFRESH_DURATION,
		"max_stacks": 1,
		"max_intensity": 3.0,
		"icon": "stealth_icon",
		"effect_flags": [],
		"apply_function": "_apply_stealth",
		"remove_function": "_remove_stealth",
		"update_function": "_update_stealth"
	},
	"lying": {
		"name": "Lying Down",
		"description": "You are lying on the ground",
		"type": EffectType.NEUTRAL,
		"stacking_type": EffectStackingType.REFRESH_DURATION,
		"max_stacks": 1,
		"max_intensity": 1.0,
		"icon": "lying_icon",
		"effect_flags": ["movement_impairing"],
		"apply_function": "_apply_lying",
		"remove_function": "_remove_lying",
		"update_function": "_update_lying"
	}
}

# === MEMBER VARIABLES ===
var active_effects = {}  # Dictionary of active effects
var effect_id_counter = 0  # For creating unique effect IDs
var status_resistance = 0.0  # Resistance to negative effects (0-1)
var status_duration_mult = 1.0  # Multiplier for effect durations
var effect_processing_paused = false  # For pausing effect processing

# References to other systems
var entity = null  # The parent entity
var health_system = null
var blood_system = null
var organ_system = null
var limb_system = null
var audio_system = null
var sprite_system = null

# === INITIALIZATION ===
func _ready():
	entity = get_parent()
	_find_systems()
	
	# Set up update timer for effect processing
	var timer = Timer.new()
	timer.wait_time = 0.5  # Process effects twice per second
	timer.autostart = true
	timer.timeout.connect(_on_effect_tick)
	add_child(timer)

func _find_systems():
	# Try to find other systems
	health_system = entity.get_node_or_null("HealthSystem")
	blood_system = entity.get_node_or_null("BloodSystem")
	organ_system = entity.get_node_or_null("OrganSystem")
	limb_system = entity.get_node_or_null("LimbSystem")
	audio_system = entity.get_node_or_null("AudioSystem")
	sprite_system = entity.get_node_or_null("SpriteSystem")
	
	print("StatusEffectManager: Connected to systems")
	print("  - Health: ", "Found" if health_system else "Not found")
	print("  - Blood: ", "Found" if blood_system else "Not found")
	print("  - Organ: ", "Found" if organ_system else "Not found")
	print("  - Limb: ", "Found" if limb_system else "Not found")
	print("  - Audio: ", "Found" if audio_system else "Not found")
	print("  - Sprite: ", "Found" if sprite_system else "Not found")

# === PROCESS FUNCTIONS ===
func _process(delta):
	# Auto-process any effects that need continuous updates
	if !effect_processing_paused:
		for effect_id in active_effects:
			var effect = active_effects[effect_id]
			var effect_def = EFFECT_DEFINITIONS[effect.effect_name]
			
			# Call update function if defined
			if effect_def.has("update_function") and has_method(effect_def.update_function):
				call(effect_def.update_function, effect, delta)

func _on_effect_tick():
	if effect_processing_paused:
		return
	
	var effects_to_remove = []
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Process duration and expirations
	for effect_id in active_effects:
		var effect = active_effects[effect_id]
		
		# Skip infinite duration effects
		if effect.duration <= 0:
			continue
		
		# Calculate time elapsed
		var elapsed = current_time - effect.start_time
		
		# Check if expired
		if elapsed >= effect.duration:
			effects_to_remove.append(effect_id)
	
	# Remove expired effects
	for effect_id in effects_to_remove:
		remove_effect(effect_id)

# === EFFECT MANAGEMENT ===
# Add a new status effect
func add_effect(effect_name, duration = 5.0, intensity = 1.0, source = "generic"):
	# Validate effect name
	if !EFFECT_DEFINITIONS.has(effect_name):
		push_error("StatusEffectManager: Attempted to add unknown effect: " + effect_name)
		return null
	
	# Get effect definition
	var effect_def = EFFECT_DEFINITIONS[effect_name]
	
	# Check if effect already exists and handle stacking
	var existing_id = find_effect_by_name(effect_name)
	
	if existing_id != null:
		# Handle based on stacking type
		match effect_def.stacking_type:
			EffectStackingType.REPLACE:
				# Remove existing and add new
				remove_effect(existing_id)
				# Continue to add new effect
			
			EffectStackingType.REFRESH_DURATION:
				# Keep intensity, update duration
				var effect = active_effects[existing_id]
				effect.duration = duration * status_duration_mult
				effect.start_time = Time.get_ticks_msec() / 1000.0
				status_effect_refreshed.emit(existing_id, effect_name, effect.duration, effect.intensity)
				return existing_id
			
			EffectStackingType.REFRESH_INTENSITY:
				# Keep duration, update intensity
				var effect = active_effects[existing_id]
				effect.intensity = min(effect_def.max_intensity, intensity)
				status_effect_intensity_changed.emit(existing_id, effect_name, effect.intensity)
				return existing_id
			
			EffectStackingType.REFRESH_BOTH:
				# Update both duration and intensity
				var effect = active_effects[existing_id]
				effect.duration = duration * status_duration_mult
				effect.intensity = min(effect_def.max_intensity, intensity)
				effect.start_time = Time.get_ticks_msec() / 1000.0
				status_effect_refreshed.emit(existing_id, effect_name, effect.duration, effect.intensity)
				return existing_id
			
			EffectStackingType.ADD_DURATION:
				# Add to existing duration
				var effect = active_effects[existing_id]
				effect.duration += duration * status_duration_mult
				status_effect_refreshed.emit(existing_id, effect_name, effect.duration, effect.intensity)
				return existing_id
			
			EffectStackingType.ADD_INTENSITY:
				# Add to existing intensity
				var effect = active_effects[existing_id]
				effect.intensity = min(effect_def.max_intensity, effect.intensity + intensity)
				status_effect_intensity_changed.emit(existing_id, effect_name, effect.intensity)
				return existing_id
			
			EffectStackingType.HIGHEST_WINS:
				# Keep the stronger effect
				var effect = active_effects[existing_id]
				if intensity > effect.intensity:
					effect.intensity = intensity
					status_effect_intensity_changed.emit(existing_id, effect_name, effect.intensity)
				if duration > effect.duration:
					effect.duration = duration * status_duration_mult
					effect.start_time = Time.get_ticks_msec() / 1000.0
					status_effect_refreshed.emit(existing_id, effect_name, effect.duration, effect.intensity)
				return existing_id
			
			EffectStackingType.STACK_SEPARATE:
				# Continue to add a new stack
				pass
	
	# Apply resistance for negative effects
	if effect_def.type == EffectType.NEGATIVE and status_resistance > 0:
		# Reduce duration and intensity based on resistance
		duration *= (1.0 - status_resistance)
		intensity *= (1.0 - status_resistance)
		
		# If completely resisted, don't add effect
		if duration <= 0 or intensity <= 0:
			return null
	
	# Apply duration multiplier
	duration *= status_duration_mult
	
	# Cap intensity at max
	intensity = min(intensity, effect_def.max_intensity)
	
	# Create unique ID for the effect
	effect_id_counter += 1
	var effect_id = effect_id_counter
	
	# Create effect data
	var effect_data = {
		"id": effect_id,
		"effect_name": effect_name,
		"duration": duration,
		"intensity": intensity,
		"source": source,
		"start_time": Time.get_ticks_msec() / 1000.0,
		"stack_count": 1
	}
	
	# Add to active effects
	active_effects[effect_id] = effect_data
	
	# Call specific apply function if defined
	if effect_def.has("apply_function") and has_method(effect_def.apply_function):
		call(effect_def.apply_function, effect_data)
	
	# Emit signal
	status_effect_added.emit(effect_id, effect_name, duration, intensity)
	
	# Play effect sound if available
	if audio_system:
		var sound_name = "effect_" + effect_name
		audio_system.play_sound(sound_name, 0.5)
	
	return effect_id

# Remove a status effect by ID
func remove_effect(effect_id):
	if !active_effects.has(effect_id):
		return false
	
	var effect = active_effects[effect_id]
	var effect_name = effect.effect_name
	var effect_def = EFFECT_DEFINITIONS[effect_name]
	
	# Call specific remove function if defined
	if effect_def.has("remove_function") and has_method(effect_def.remove_function):
		call(effect_def.remove_function, effect)
	
	# Remove from active effects
	active_effects.erase(effect_id)
	
	# Emit signal
	status_effect_removed.emit(effect_id, effect_name)
	
	return true

# Remove all effects of a specified name
func remove_effects_by_name(effect_name):
	var ids_to_remove = []
	
	for effect_id in active_effects:
		if active_effects[effect_id].effect_name == effect_name:
			ids_to_remove.append(effect_id)
	
	for id in ids_to_remove:
		remove_effect(id)
	
	return ids_to_remove.size()

# Remove all status effects
func remove_all_effects():
	var ids_to_remove = active_effects.keys()
	
	for id in ids_to_remove:
		remove_effect(id)
	
	return ids_to_remove.size()

# Find an effect by name (returns first match ID or null)
func find_effect_by_name(effect_name):
	for effect_id in active_effects:
		if active_effects[effect_id].effect_name == effect_name:
			return effect_id
	
	return null

# Check if an effect is active by name
func has_effect(effect_name):
	return find_effect_by_name(effect_name) != null

# Get the intensity of an effect by name
func get_effect_intensity(effect_name):
	var effect_id = find_effect_by_name(effect_name)
	if effect_id != null:
		return active_effects[effect_id].intensity
	
	return 0.0

# Get the duration of an effect by name
func get_effect_duration(effect_name):
	var effect_id = find_effect_by_name(effect_name)
	if effect_id != null:
		return active_effects[effect_id].duration
	
	return 0.0

# Get the remaining time of an effect by name
func get_effect_remaining_time(effect_name):
	var effect_id = find_effect_by_name(effect_name)
	if effect_id != null:
		var effect = active_effects[effect_id]
		var elapsed = Time.get_ticks_msec() / 1000.0 - effect.start_time
		return max(0, effect.duration - elapsed)
	
	return 0.0

# Get the stack count of an effect by name
func get_effect_stack_count(effect_name):
	var count = 0
	
	for effect_id in active_effects:
		if active_effects[effect_id].effect_name == effect_name:
			count += active_effects[effect_id].stack_count
	
	return count

# Get all active effects
func get_all_active_effects():
	var effects = []
	
	for effect_id in active_effects:
		var effect = active_effects[effect_id]
		var effect_def = EFFECT_DEFINITIONS[effect.effect_name]
		
		# Calculate remaining time
		var remaining_time = 0
		if effect.duration > 0:
			var elapsed = Time.get_ticks_msec() / 1000.0 - effect.start_time
			remaining_time = max(0, effect.duration - elapsed)
		
		# Build effect info
		effects.append({
			"id": effect.id,
			"name": effect_def.name,
			"effect_name": effect.effect_name,
			"description": effect_def.description,
			"type": effect_def.type,
			"duration": effect.duration,
			"remaining_time": remaining_time,
			"intensity": effect.intensity,
			"stack_count": effect.stack_count,
			"source": effect.source,
			"icon": effect_def.icon,
			"flags": effect_def.effect_flags
		})
	
	return effects

# Get all effects by type
func get_effects_by_type(effect_type):
	var effects = []
	
	for effect_id in active_effects:
		var effect = active_effects[effect_id]
		var effect_def = EFFECT_DEFINITIONS[effect.effect_name]
		
		if effect_def.type == effect_type:
			effects.append(effect.id)
	
	return effects

# Check if entity has any effects with a specific flag
func has_effect_flag(flag):
	for effect_id in active_effects:
		var effect = active_effects[effect_id]
		var effect_def = EFFECT_DEFINITIONS[effect.effect_name]
		
		if flag in effect_def.effect_flags:
			return true
	
	return false

# === EFFECT IMPLEMENTATION FUNCTIONS ===
# These functions are called when effects are applied/removed
# Stunned effect
func _apply_stunned(effect):
	# Apply immobilization effects
	if entity.has_method("set_can_move"):
		entity.set_can_move(false)
	
	# Apply visual effects
	if sprite_system:
		sprite_system.show_stun_effect(true)
	
	# Apply status to health system if available
	if health_system:
		health_system.add_status_effect("stunned", effect.duration, effect.intensity)

func _remove_stunned(effect):
	# Remove immobilization effects
	if entity.has_method("set_can_move"):
		entity.set_can_move(true)
	
	# Remove visual effects
	if sprite_system:
		sprite_system.show_stun_effect(false)
	
	# Remove status from health system if available
	if health_system:
		health_system.remove_status_effect("stunned")

func _update_stunned(effect, delta):
	# Add additional stun effects here if needed
	pass

# Poisoned effect
func _apply_poisoned(effect):
	# Apply visual effects
	if sprite_system:
		sprite_system.show_poison_effect(true)
	
	# Apply to health system if available
	if health_system:
		health_system.add_status_effect("poisoned", effect.duration, effect.intensity)

func _remove_poisoned(effect):
	# Remove visual effects
	if sprite_system:
		sprite_system.show_poison_effect(false)
	
	# Remove status from health system if available
	if health_system:
		health_system.remove_status_effect("poisoned")

func _update_poisoned(effect, delta):
	# Apply toxin damage over time
	if health_system:
		health_system.adjustToxLoss(effect.intensity * delta * 0.5)

# Bleeding effect
func _apply_bleeding(effect):
	# Apply visual effects
	if sprite_system:
		sprite_system.show_bleeding_effect(true)
	
	# Set bleeding rate in blood system
	if blood_system:
		blood_system.set_bleeding_rate(effect.intensity)
	
	# Apply to health system if available
	if health_system:
		health_system.add_status_effect("bleeding", effect.duration, effect.intensity)

func _remove_bleeding(effect):
	# Remove visual effects
	if sprite_system:
		sprite_system.show_bleeding_effect(false)
	
	# Stop bleeding in blood system
	if blood_system:
		blood_system.set_bleeding_rate(0)
	
	# Remove status from health system if available
	if health_system:
		health_system.remove_status_effect("bleeding")

func _update_bleeding(effect, delta):
	# Bleeding is handled by the blood system
	pass

# Burned effect
func _apply_burned(effect):
	# Apply visual effects
	if sprite_system and sprite_system.has_method("show_burn_effect"):
		sprite_system.show_burn_effect(true, effect.intensity)
	
	# Apply to health system if available
	if health_system:
		health_system.add_status_effect("burned", effect.duration, effect.intensity)

func _remove_burned(effect):
	# Remove visual effects
	if sprite_system and sprite_system.has_method("show_burn_effect"):
		sprite_system.show_burn_effect(false)
	
	# Remove status from health system if available
	if health_system:
		health_system.remove_status_effect("burned")

func _update_burned(effect, delta):
	# Apply burn damage over time
	if health_system:
		health_system.adjustFireLoss(effect.intensity * delta * 0.2)

# Irradiated effect
func _apply_irradiated(effect):
	# Apply visual effects
	if sprite_system and sprite_system.has_method("show_radiation_effect"):
		sprite_system.show_radiation_effect(true, effect.intensity)
	
	# Apply to health system if available
	if health_system:
		health_system.add_status_effect("irradiated", effect.duration, effect.intensity)

func _remove_irradiated(effect):
	# Remove visual effects
	if sprite_system and sprite_system.has_method("show_radiation_effect"):
		sprite_system.show_radiation_effect(false)
	
	# Remove status from health system if available
	if health_system:
		health_system.remove_status_effect("irradiated")

func _update_irradiated(effect, delta):
	# Apply radiation effects
	if health_system:
		health_system.adjustToxLoss(effect.intensity * delta * 0.1)
		
		# Small chance for mutations or cellular damage
		if randf() < delta * 0.01 * effect.intensity:
			health_system.adjustCloneLoss(0.5)

# Confused effect
func _apply_confused(effect):
	# Apply visual effects
	if sprite_system and sprite_system.has_method("show_confusion_effect"):
		sprite_system.show_confusion_effect(true)
	
	# Apply confusion to entity if it has the method
	if entity.has_method("set_confusion"):
		entity.set_confusion(effect.intensity)
	
	# Apply to health system if available
	if health_system:
		health_system.add_status_effect("confused", effect.duration, effect.intensity)

func _remove_confused(effect):
	# Remove visual effects
	if sprite_system and sprite_system.has_method("show_confusion_effect"):
		sprite_system.show_confusion_effect(false)
	
	# Remove confusion from entity if it has the method
	if entity.has_method("set_confusion"):
		entity.set_confusion(0)
	
	# Remove status from health system if available
	if health_system:
		health_system.remove_status_effect("confused")

func _update_confused(effect, delta):
	# Confusion effects on movement handled by the movement controller
	pass

# Slowed effect
func _apply_slowed(effect):
	# Apply movement speed reduction
	if entity.has_method("add_movement_modifier"):
		var slow_factor = 1.0 - min(0.8, effect.intensity * 0.2)  # Cap at 80% slowdown
		entity.add_movement_modifier("status_slowed", slow_factor)
	
	# Apply visual effects
	if sprite_system and sprite_system.has_method("show_slow_effect"):
		sprite_system.show_slow_effect(true)
	
	# Apply to health system if available
	if health_system:
		health_system.add_status_effect("slowed", effect.duration, effect.intensity)

func _remove_slowed(effect):
	# Remove movement speed reduction
	if entity.has_method("remove_movement_modifier"):
		entity.remove_movement_modifier("status_slowed")
	
	# Remove visual effects
	if sprite_system and sprite_system.has_method("show_slow_effect"):
		sprite_system.show_slow_effect(false)
	
	# Remove status from health system if available
	if health_system:
		health_system.remove_status_effect("slowed")

func _update_slowed(effect, delta):
	# Slow effects on movement handled by the movement controller
	pass

# Weakened effect
func _apply_weakened(effect):
	# Apply damage reduction
	if entity.has_method("add_damage_modifier"):
		var damage_factor = 1.0 - min(0.7, effect.intensity * 0.15)  # Cap at 70% damage reduction
		entity.add_damage_modifier("status_weakened", damage_factor)
	
	# Apply visual effects
	if sprite_system and sprite_system.has_method("show_weak_effect"):
		sprite_system.show_weak_effect(true)
	
	# Apply to health system if available
	if health_system:
		health_system.add_status_effect("weakened", effect.duration, effect.intensity)

func _remove_weakened(effect):
	# Remove damage reduction
	if entity.has_method("remove_damage_modifier"):
		entity.remove_damage_modifier("status_weakened")
	
	# Remove visual effects
	if sprite_system and sprite_system.has_method("show_weak_effect"):
		sprite_system.show_weak_effect(false)
	
	# Remove status from health system if available
	if health_system:
		health_system.remove_status_effect("weakened")

func _update_weakened(effect, delta):
	# Weakness effects handled by the damage modifier system
	pass

# Dizzy effect
func _apply_dizzy(effect):
	# Apply visual effects - screen wobble
	if entity.has_method("set_screen_wobble"):
		entity.set_screen_wobble(effect.intensity)
	
	# Apply accuracy reduction
	if entity.has_method("add_accuracy_modifier"):
		var accuracy_factor = 1.0 - min(0.5, effect.intensity * 0.2)  # Cap at 50% accuracy reduction
		entity.add_accuracy_modifier("status_dizzy", accuracy_factor)
	
	# Apply to health system if available
	if health_system:
		health_system.add_status_effect("dizzy", effect.duration, effect.intensity)

func _remove_dizzy(effect):
	# Remove visual effects
	if entity.has_method("set_screen_wobble"):
		entity.set_screen_wobble(0)
	
	# Remove accuracy reduction
	if entity.has_method("remove_accuracy_modifier"):
		entity.remove_accuracy_modifier("status_dizzy")
	
	# Remove status from health system if available
	if health_system:
		health_system.remove_status_effect("dizzy")

func _update_dizzy(effect, delta):
	# Visual wobble is handled by the camera controller
	pass

# Blurred Vision effect
func _apply_blurred_vision(effect):
	# Apply visual effects
	if entity.has_method("set_blur_effect"):
		entity.set_blur_effect(effect.intensity)
	
	# Apply accuracy reduction
	if entity.has_method("add_accuracy_modifier"):
		var accuracy_factor = 1.0 - min(0.6, effect.intensity * 0.15)  # Cap at 60% accuracy reduction
		entity.add_accuracy_modifier("status_blur", accuracy_factor)
	
	# Apply to health system if available
	if health_system:
		health_system.add_status_effect("blurred_vision", effect.duration, effect.intensity)

func _remove_blurred_vision(effect):
	# Remove visual effects
	if entity.has_method("set_blur_effect"):
		entity.set_blur_effect(0)
	
	# Remove accuracy reduction
	if entity.has_method("remove_accuracy_modifier"):
		entity.remove_accuracy_modifier("status_blur")
	
	# Remove status from health system if available
	if health_system:
		health_system.remove_status_effect("blurred_vision")

func _update_blurred_vision(effect, delta):
	# Blur effects handled by the camera controller
	pass

# Unconscious effect
func _apply_unconscious(effect):
	# Apply immobilization effects
	if entity.has_method("set_can_move"):
		entity.set_can_move(false)
	
	# Apply visual effects
	if sprite_system and sprite_system.has_method("play_unconscious_animation"):
		sprite_system.play_unconscious_animation(true)
	
	# Make entity lie down
	if entity.has_method("set_resting"):
		entity.set_resting(true)
	
	# Apply to health system if available
	if health_system:
		health_system.add_status_effect("unconscious", effect.duration, effect.intensity)

func _remove_unconscious(effect):
	# Remove immobilization effects
	if entity.has_method("set_can_move"):
		entity.set_can_move(true)
	
	# Remove visual effects
	if sprite_system and sprite_system.has_method("play_unconscious_animation"):
		sprite_system.play_unconscious_animation(false)
	
	# Remove status from health system if available
	if health_system:
		health_system.remove_status_effect("unconscious")

func _update_unconscious(effect, delta):
	# Unconsciousness is mostly handled through the immobilization
	pass

# Suffocating effect
func _apply_suffocating(effect):
	# Apply visual effects
	if sprite_system and sprite_system.has_method("show_suffocating_effect"):
		sprite_system.show_suffocating_effect(true)
	
	# Apply to health system if available
	if health_system:
		health_system.add_status_effect("suffocating", effect.duration, effect.intensity)

func _remove_suffocating(effect):
	# Remove visual effects
	if sprite_system and sprite_system.has_method("show_suffocating_effect"):
		sprite_system.show_suffocating_effect(false)
	
	# Remove status from health system if available
	if health_system:
		health_system.remove_status_effect("suffocating")

func _update_suffocating(effect, delta):
	# Apply oxygen loss
	if health_system:
		health_system.adjustOxyLoss(effect.intensity * delta * 2.0)

# Slurred Speech effect
func _apply_slurred_speech(effect):
	# Apply message modification system
	if entity.has_method("set_speech_modifier"):
		entity.set_speech_modifier("slurred", effect.intensity)
	
	# Apply to health system if available
	if health_system:
		health_system.add_status_effect("slurred_speech", effect.duration, effect.intensity)

func _remove_slurred_speech(effect):
	# Remove message modification
	if entity.has_method("remove_speech_modifier"):
		entity.remove_speech_modifier("slurred")
	
	# Remove status from health system if available
	if health_system:
		health_system.remove_status_effect("slurred_speech")

func _update_slurred_speech(effect, delta):
	# Speech effects handled by the speech system
	pass

# Paralyzed effect
func _apply_paralyzed(effect):
	# Apply immobilization effects
	if entity.has_method("set_can_move"):
		entity.set_can_move(false)
	
	# Apply visual effects
	if sprite_system and sprite_system.has_method("show_paralyzed_effect"):
		sprite_system.show_paralyzed_effect(true)
	
	# Apply to health system if available
	if health_system:
		health_system.add_status_effect("paralyzed", effect.duration, effect.intensity)

func _remove_paralyzed(effect):
	# Remove immobilization effects
	if entity.has_method("set_can_move"):
		entity.set_can_move(true)
	
	# Remove visual effects
	if sprite_system and sprite_system.has_method("show_paralyzed_effect"):
		sprite_system.show_paralyzed_effect(false)
	
	# Remove status from health system if available
	if health_system:
		health_system.remove_status_effect("paralyzed")

func _update_paralyzed(effect, delta):
	# Paralysis is mostly handled through the immobilization
	pass

# Exhausted effect
func _apply_exhausted(effect):
	# Apply stamina recovery reduction
	if entity.has_method("add_stamina_recovery_modifier"):
		var recovery_factor = 1.0 - min(0.9, effect.intensity * 0.3)  # Cap at 90% reduction
		entity.add_stamina_recovery_modifier("status_exhausted", recovery_factor)
	
	# Apply visual effects
	if sprite_system and sprite_system.has_method("show_exhausted_effect"):
		sprite_system.show_exhausted_effect(true)
	
	# Apply to health system if available
	if health_system:
		health_system.add_status_effect("exhausted", effect.duration, effect.intensity)

func _remove_exhausted(effect):
	# Remove stamina recovery reduction
	if entity.has_method("remove_stamina_recovery_modifier"):
		entity.remove_stamina_recovery_modifier("status_exhausted")
	
	# Remove visual effects
	if sprite_system and sprite_system.has_method("show_exhausted_effect"):
		sprite_system.show_exhausted_effect(false)
	
	# Remove status from health system if available
	if health_system:
		health_system.remove_status_effect("exhausted")

func _update_exhausted(effect, delta):
	# Exhaustion effects handled by the stamina system
	pass

# Pain effect
func _apply_pain(effect):
	# Apply screen effects
	if entity.has_method("set_pain_effect"):
		entity.set_pain_effect(effect.intensity)
	
	# Apply movement and action penalties based on intensity
	if effect.intensity >= 5.0:
		# Severe pain - affects movement and accuracy
		if entity.has_method("add_movement_modifier"):
			entity.add_movement_modifier("status_pain", 0.8)
		
		if entity.has_method("add_accuracy_modifier"):
			entity.add_accuracy_modifier("status_pain", 0.75)
			
		# Chance to cause involuntary sounds
		if randf() < 0.1 and entity.has_method("play_pain_sound"):
			entity.play_pain_sound()
	
	elif effect.intensity >= 3.0:
		# Moderate pain - minor movement penalty
		if entity.has_method("add_movement_modifier"):
			entity.add_movement_modifier("status_pain", 0.9)
		
		if entity.has_method("add_accuracy_modifier"):
			entity.add_accuracy_modifier("status_pain", 0.85)
	
	# Apply to health system if available
	if health_system:
		health_system.add_status_effect("pain", effect.duration, effect.intensity)

func _remove_pain(effect):
	# Remove screen effects
	if entity.has_method("set_pain_effect"):
		entity.set_pain_effect(0)
	
	# Remove movement and accuracy penalties
	if entity.has_method("remove_movement_modifier"):
		entity.remove_movement_modifier("status_pain")
	
	if entity.has_method("remove_accuracy_modifier"):
		entity.remove_accuracy_modifier("status_pain")
	
	# Remove status from health system if available
	if health_system:
		health_system.remove_status_effect("pain")

func _update_pain(effect, delta):
	# Beyond screen effects, pain is handled by movement and accuracy modifiers
	pass

# Regenerating effect
func _apply_regenerating(effect):
	# Apply visual effects
	if sprite_system and sprite_system.has_method("show_regen_effect"):
		sprite_system.show_regen_effect(true)
	
	# Apply to health system if available
	if health_system:
		health_system.add_status_effect("regenerating", effect.duration, effect.intensity)

func _remove_regenerating(effect):
	# Remove visual effects
	if sprite_system and sprite_system.has_method("show_regen_effect"):
		sprite_system.show_regen_effect(false)
	
	# Remove status from health system if available
	if health_system:
		health_system.remove_status_effect("regenerating")

func _update_regenerating(effect, delta):
	# Apply healing over time
	if health_system:
		# Heal both brute and burn damage
		health_system.adjustBruteLoss(-effect.intensity * delta)
		health_system.adjustFireLoss(-effect.intensity * delta * 0.5)

# Strength Buff effect
func _apply_strength_buff(effect):
	# Apply damage buff
	if entity.has_method("add_damage_modifier"):
		var damage_factor = 1.0 + min(1.0, effect.intensity * 0.2)  # Cap at 100% damage increase
		entity.add_damage_modifier("status_strength", damage_factor)
	
	# Apply visual effects
	if sprite_system and sprite_system.has_method("show_strength_effect"):
		sprite_system.show_strength_effect(true)
	
	# Apply to health system if available
	if health_system:
		health_system.add_status_effect("strength_buff", effect.duration, effect.intensity)

func _remove_strength_buff(effect):
	# Remove damage buff
	if entity.has_method("remove_damage_modifier"):
		entity.remove_damage_modifier("status_strength")
	
	# Remove visual effects
	if sprite_system and sprite_system.has_method("show_strength_effect"):
		sprite_system.show_strength_effect(false)
	
	# Remove status from health system if available
	if health_system:
		health_system.remove_status_effect("strength_buff")

func _update_strength_buff(effect, delta):
	# Strength effects handled by the damage modifier system
	pass

# Speed Buff effect
func _apply_speed_buff(effect):
	# Apply movement speed increase
	if entity.has_method("add_movement_modifier"):
		var speed_factor = 1.0 + min(1.0, effect.intensity * 0.25)  # Cap at 100% speed increase
		entity.add_movement_modifier("status_speed", speed_factor)
	
	# Apply visual effects
	if sprite_system and sprite_system.has_method("show_speed_effect"):
		sprite_system.show_speed_effect(true)
	
	# Apply to health system if available
	if health_system:
		health_system.add_status_effect("speed_buff", effect.duration, effect.intensity)

func _remove_speed_buff(effect):
	# Remove movement speed increase
	if entity.has_method("remove_movement_modifier"):
		entity.remove_movement_modifier("status_speed")
	
	# Remove visual effects
	if sprite_system and sprite_system.has_method("show_speed_effect"):
		sprite_system.show_speed_effect(false)
	
	# Remove status from health system if available
	if health_system:
		health_system.remove_status_effect("speed_buff")

func _update_speed_buff(effect, delta):
	# Speed effects handled by the movement controller
	pass

# Painkiller effect
func _apply_painkiller(effect):
	# Apply pain reduction
	if entity.has_method("set_pain_resistance"):
		var resistance = min(0.9, effect.intensity * 0.2)  # Cap at 90% pain resistance
		entity.set_pain_resistance(resistance)
	
	# Also remove or reduce existing pain
	if has_effect("pain"):
		var pain_id = find_effect_by_name("pain")
		var pain_effect = active_effects[pain_id]
		
		var new_pain = max(0, pain_effect.intensity - effect.intensity)
		if new_pain <= 0:
			remove_effect(pain_id)
		else:
			pain_effect.intensity = new_pain
			status_effect_intensity_changed.emit(pain_id, "pain", new_pain)
	
	# Apply to health system if available
	if health_system:
		health_system.add_status_effect("painkiller", effect.duration, effect.intensity)

func _remove_painkiller(effect):
	# Remove pain resistance
	if entity.has_method("set_pain_resistance"):
		entity.set_pain_resistance(0)
	
	# Remove status from health system if available
	if health_system:
		health_system.remove_status_effect("painkiller")

func _update_painkiller(effect, delta):
	# Painkiller effects handled by the pain resistance system
	pass

# Adrenaline effect
func _apply_adrenaline(effect):
	# Apply multiple effects - pain reduction, speed increase, stamina regen
	if entity.has_method("set_pain_resistance"):
		var resistance = min(0.7, effect.intensity * 0.25)  # Cap at 70% pain resistance
		entity.set_pain_resistance(resistance)
	
	if entity.has_method("add_movement_modifier"):
		var speed_factor = 1.0 + min(0.5, effect.intensity * 0.2)  # Cap at 50% speed increase
		entity.add_movement_modifier("status_adrenaline", speed_factor)
	
	if entity.has_method("add_stamina_recovery_modifier"):
		var stamina_factor = 1.0 + min(1.0, effect.intensity * 0.3)  # Cap at 100% stamina regen increase
		entity.add_stamina_recovery_modifier("status_adrenaline", stamina_factor)
	
	# Apply visual effects
	if sprite_system and sprite_system.has_method("show_adrenaline_effect"):
		sprite_system.show_adrenaline_effect(true)
	
	# Apply to health system if available
	if health_system:
		health_system.add_status_effect("adrenaline", effect.duration, effect.intensity)

func _remove_adrenaline(effect):
	# Remove all adrenaline effects
	if entity.has_method("set_pain_resistance"):
		entity.set_pain_resistance(0)
	
	if entity.has_method("remove_movement_modifier"):
		entity.remove_movement_modifier("status_adrenaline")
	
	if entity.has_method("remove_stamina_recovery_modifier"):
		entity.remove_stamina_recovery_modifier("status_adrenaline")
	
	# Remove visual effects
	if sprite_system and sprite_system.has_method("show_adrenaline_effect"):
		sprite_system.show_adrenaline_effect(false)
	
	# Remove status from health system if available
	if health_system:
		health_system.remove_status_effect("adrenaline")

func _update_adrenaline(effect, delta):
	# Adrenaline effects handled by other systems
	pass

# Stealth effect
func _apply_stealth(effect):
	# Apply visibility reduction
	if entity.has_method("set_visibility"):
		var visibility = max(0.2, 1.0 - effect.intensity * 0.2)  # Cap at 80% invisibility
		entity.set_visibility(visibility)
	
	# Apply visual effects
	if sprite_system and sprite_system.has_method("show_stealth_effect"):
		sprite_system.show_stealth_effect(true, effect.intensity)
	
	# Apply to health system if available
	if health_system:
		health_system.add_status_effect("stealth", effect.duration, effect.intensity)

func _remove_stealth(effect):
	# Remove visibility reduction
	if entity.has_method("set_visibility"):
		entity.set_visibility(1.0)
	
	# Remove visual effects
	if sprite_system and sprite_system.has_method("show_stealth_effect"):
		sprite_system.show_stealth_effect(false)
	
	# Remove status from health system if available
	if health_system:
		health_system.remove_status_effect("stealth")

func _update_stealth(effect, delta):
	# Stealth effects handled by the visibility system
	pass

# === PUBLIC API ===
# Set status resistance value
func set_status_resistance(value):
	status_resistance = clamp(value, 0.0, 1.0)
	return status_resistance

# Set status duration multiplier
func set_status_duration_multiplier(value):
	status_duration_mult = max(0.1, value)
	return status_duration_mult

# Pause/unpause effect processing
func set_effect_processing_paused(paused):
	effect_processing_paused = paused
	return effect_processing_paused

# Extend an existing effect's duration
func extend_effect_duration(effect_name, additional_duration):
	var effect_id = find_effect_by_name(effect_name)
	if effect_id == null:
		return 0
	
	var effect = active_effects[effect_id]
	effect.duration += additional_duration * status_duration_mult
	
	status_effect_refreshed.emit(effect_id, effect_name, effect.duration, effect.intensity)
	
	return effect.duration

# Change an existing effect's intensity
func change_effect_intensity(effect_name, new_intensity):
	var effect_id = find_effect_by_name(effect_name)
	if effect_id == null:
		return 0
	
	var effect = active_effects[effect_id]
	var effect_def = EFFECT_DEFINITIONS[effect_name]
	
	effect.intensity = clamp(new_intensity, 0, effect_def.max_intensity)
	
	status_effect_intensity_changed.emit(effect_id, effect_name, effect.intensity)
	
	return effect.intensity

# Get a summary of status effects for display
func get_status_summary():
	var summary = []
	
	for effect_id in active_effects:
		var effect = active_effects[effect_id]
		var effect_def = EFFECT_DEFINITIONS[effect.effect_name]
		
		# Calculate remaining time
		var remaining = effect.duration
		if effect.duration > 0:
			var elapsed = Time.get_ticks_msec() / 1000.0 - effect.start_time
			remaining = max(0, effect.duration - elapsed)
		
		summary.append({
			"name": effect_def.name,
			"duration": remaining,
			"intensity": effect.intensity,
			"type": effect_def.type
		})
	
	return summary

# Cure all negative effects
func cure_all_negative_effects():
	var removed_count = 0
	var ids_to_remove = []
	
	for effect_id in active_effects:
		var effect = active_effects[effect_id]
		var effect_def = EFFECT_DEFINITIONS[effect.effect_name]
		
		if effect_def.type == EffectType.NEGATIVE:
			ids_to_remove.append(effect_id)
	
	for id in ids_to_remove:
		remove_effect(id)
		removed_count += 1
	
	return removed_count

func _apply_lying(effect):
	# Apply movement speed reduction
	if entity.has_method("add_movement_modifier"):
		entity.add_movement_modifier("status_lying", 0.4)  # 60% slowdown
	
	# Apply visual effects if needed
	if sprite_system and sprite_system.has_method("set_lying_state"):
		sprite_system.set_lying_state(true)
	
	# Apply to health system if available - faster stamina recovery
	if health_system and health_system.has_method("add_stamina_recovery_modifier"):
		health_system.add_stamina_recovery_modifier("lying", 1.5)  # 50% faster recovery

func _remove_lying(effect):
	# Remove movement speed reduction
	if entity.has_method("remove_movement_modifier"):
		entity.remove_movement_modifier("status_lying")
	
	# Remove visual effects if needed
	if sprite_system and sprite_system.has_method("set_lying_state"):
		sprite_system.set_lying_state(false)
	
	# Remove from health system if available
	if health_system and health_system.has_method("remove_stamina_recovery_modifier"):
		health_system.remove_stamina_recovery_modifier("lying")

func _update_lying(effect, delta):
	# Lying effects handled elsewhere
	pass
