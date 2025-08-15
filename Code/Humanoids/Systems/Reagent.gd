extends Resource
class_name Reagent

# === ENUMS ===
enum ReagentState {
	SOLID,
	LIQUID,
	GAS,
	PLASMA
}

enum ChemClass {
	NONE = 0,
	BASIC = 1,      # Dispensable chemicals (iron, oxygen)
	COMMON = 2,     # Simple recipes (bicaridine, ammonia) 
	UNCOMMON = 3,   # Complex recipes (space drugs)
	RARE = 4,       # Hard to obtain components
	SPECIAL = 5,    # Unique/unobtainable normally
	ULTRA = 6       # Extremely rare
}

# === CORE PROPERTIES ===
@export var id: String = ""
@export var name: String = "Unknown Chemical"
@export var description: String = "A chemical substance."
@export var volume: float = 0.0
@export var color: Color = Color.WHITE
@export var reagent_state: ReagentState = ReagentState.LIQUID

# === CHEMICAL PROPERTIES ===
@export var custom_metabolism: float = 0.4  # Units metabolized per second
@export var overdose_threshold: float = 0.0  # Volume that causes overdose
@export var critical_overdose_threshold: float = 0.0  # Volume that causes critical overdose
@export var nutriment_factor: float = 0.0  # Nutritional value
@export var chem_class: ChemClass = ChemClass.NONE

# === EFFECTS AND PROPERTIES ===
@export var effects: Dictionary = {}  # effect_name -> intensity
@export var addiction_chance: float = 0.0
@export var addiction_threshold: float = 0.0
@export var purge_rate: float = 0.0  # Rate at which this reagent purges others

# === DAMAGE AND HEALING ===
@export var brute_heal: float = 0.0
@export var burn_heal: float = 0.0
@export var toxin_heal: float = 0.0
@export var oxygen_heal: float = 0.0
@export var clone_heal: float = 0.0
@export var brain_heal: float = 0.0
@export var stamina_heal: float = 0.0

@export var brute_damage: float = 0.0
@export var burn_damage: float = 0.0
@export var toxin_damage: float = 0.0
@export var oxygen_damage: float = 0.0
@export var clone_damage: float = 0.0
@export var brain_damage: float = 0.0
@export var stamina_damage: float = 0.0

# === TEMPERATURE EFFECTS ===
@export var adjust_temp: float = 0.0  # Temperature adjustment per cycle
@export var target_temp: float = 310.15  # Target temperature in Kelvin

# === SPECIAL PROPERTIES ===
@export var is_explosive: bool = false
@export var explosive_power: float = 0.0
@export var explosive_falloff: float = 0.0

@export var creates_fire: bool = false
@export var fire_intensity: float = 0.0
@export var fire_duration: float = 0.0
@export var fire_radius: float = 0.0

@export var is_toxic: bool = false
@export var is_addictive: bool = false
@export var is_medical: bool = false
@export var is_food: bool = false

# === FLAGS ===
@export var flags: int = 0

# Flag constants
const FLAG_NO_OVERDOSE = 1
const FLAG_NO_METABOLISM = 2
const FLAG_NO_EFFECTS_IN_DEAD = 4
const FLAG_SYNTHETIC_ONLY = 8
const FLAG_ORGANIC_ONLY = 16

# === DATA ===
var data: Dictionary = {}  # Custom data for special reagents
var source_mob_ref: WeakRef = null  # Reference to source mob

func _init(reagent_id: String = "", initial_volume: float = 0.0):
	if reagent_id != "":
		id = reagent_id
	volume = initial_volume

# === CORE METHODS ===
func duplicate_reagent() -> Reagent:
	"""Create a duplicate of this reagent"""
	var new_reagent = Reagent.new(id, volume)
	
	# Copy all properties
	new_reagent.name = name
	new_reagent.description = description
	new_reagent.color = color
	new_reagent.reagent_state = reagent_state
	new_reagent.custom_metabolism = custom_metabolism
	new_reagent.overdose_threshold = overdose_threshold
	new_reagent.critical_overdose_threshold = critical_overdose_threshold
	new_reagent.nutriment_factor = nutriment_factor
	new_reagent.chem_class = chem_class
	
	# Copy effects
	new_reagent.effects = effects.duplicate()
	new_reagent.addiction_chance = addiction_chance
	new_reagent.addiction_threshold = addiction_threshold
	new_reagent.purge_rate = purge_rate
	
	# Copy healing/damage values
	new_reagent.brute_heal = brute_heal
	new_reagent.burn_heal = burn_heal
	new_reagent.toxin_heal = toxin_heal
	new_reagent.oxygen_heal = oxygen_heal
	new_reagent.clone_heal = clone_heal
	new_reagent.brain_heal = brain_heal
	new_reagent.stamina_heal = stamina_heal
	
	new_reagent.brute_damage = brute_damage
	new_reagent.burn_damage = burn_damage
	new_reagent.toxin_damage = toxin_damage
	new_reagent.oxygen_damage = oxygen_damage
	new_reagent.clone_damage = clone_damage
	new_reagent.brain_damage = brain_damage
	new_reagent.stamina_damage = stamina_damage
	
	# Copy temperature effects
	new_reagent.adjust_temp = adjust_temp
	new_reagent.target_temp = target_temp
	
	# Copy special properties
	new_reagent.is_explosive = is_explosive
	new_reagent.explosive_power = explosive_power
	new_reagent.explosive_falloff = explosive_falloff
	
	new_reagent.creates_fire = creates_fire
	new_reagent.fire_intensity = fire_intensity
	new_reagent.fire_duration = fire_duration
	new_reagent.fire_radius = fire_radius
	
	new_reagent.is_toxic = is_toxic
	new_reagent.is_addictive = is_addictive
	new_reagent.is_medical = is_medical
	new_reagent.is_food = is_food
	
	new_reagent.flags = flags
	new_reagent.data = data.duplicate()
	new_reagent.source_mob_ref = source_mob_ref
	
	return new_reagent

func add_volume(amount: float):
	"""Add volume to this reagent"""
	volume = max(0.0, volume + amount)

func remove_volume(amount: float) -> float:
	"""Remove volume from this reagent, returns actual amount removed"""
	var removed = min(volume, amount)
	volume = max(0.0, volume - amount)
	return removed

func get_total_healing() -> float:
	"""Get total healing potential"""
	return brute_heal + burn_heal + toxin_heal + oxygen_heal + clone_heal + brain_heal + stamina_heal

func get_total_damage() -> float:
	"""Get total damage potential"""
	return brute_damage + burn_damage + toxin_damage + oxygen_damage + clone_damage + brain_damage + stamina_damage

func is_harmful() -> bool:
	"""Check if this reagent is harmful"""
	return get_total_damage() > 0 or is_toxic or (overdose_threshold > 0 and volume > overdose_threshold)

func is_beneficial() -> bool:
	"""Check if this reagent is beneficial"""
	return get_total_healing() > 0 or effects.size() > 0 and not is_harmful()

func has_flag(flag: int) -> bool:
	"""Check if reagent has specific flag"""
	return (flags & flag) != 0

func set_flag(flag: int, enabled: bool = true):
	"""Set or unset a flag"""
	if enabled:
		flags |= flag
	else:
		flags &= ~flag

# === EFFECT PROCESSING ===
func process_effects(target, delta_time: float, reagent_container):
	"""Process reagent effects on a target over time"""
	if volume <= 0:
		return
	
	# Check if effects should be applied
	if target.has_method("is_dead") and target.is_dead() and has_flag(FLAG_NO_EFFECTS_IN_DEAD):
		return
	
	# Check organism compatibility
	var is_synthetic = target.has_method("is_synthetic") and target.is_synthetic()
	if is_synthetic and has_flag(FLAG_ORGANIC_ONLY):
		return
	if not is_synthetic and has_flag(FLAG_SYNTHETIC_ONLY):
		return
	
	# Get health system
	var health_system = target.get_node_or_null("HealthSystem")
	if not health_system:
		return
	
	# Calculate effect intensity based on volume
	var effect_multiplier = min(volume / 5.0, 2.0)  # Cap at 2x effect
	
	# Apply healing effects
	if brute_heal > 0:
		health_system.adjustBruteLoss(-brute_heal * effect_multiplier * delta_time, false)
	if burn_heal > 0:
		health_system.adjustFireLoss(-burn_heal * effect_multiplier * delta_time, false)
	if toxin_heal > 0:
		health_system.adjustToxLoss(-toxin_heal * effect_multiplier * delta_time, false)
	if oxygen_heal > 0:
		health_system.adjustOxyLoss(-oxygen_heal * effect_multiplier * delta_time, false)
	if clone_heal > 0:
		health_system.adjustCloneLoss(-clone_heal * effect_multiplier * delta_time, false)
	if brain_heal > 0:
		health_system.adjustBrainLoss(-brain_heal * effect_multiplier * delta_time, false)
	if stamina_heal > 0:
		health_system.adjustStaminaLoss(-stamina_heal * effect_multiplier * delta_time, false)
	
	# Apply damage effects
	if brute_damage > 0:
		health_system.adjustBruteLoss(brute_damage * effect_multiplier * delta_time, false)
	if burn_damage > 0:
		health_system.adjustFireLoss(burn_damage * effect_multiplier * delta_time, false)
	if toxin_damage > 0:
		health_system.adjustToxLoss(toxin_damage * effect_multiplier * delta_time, false)
	if oxygen_damage > 0:
		health_system.adjustOxyLoss(oxygen_damage * effect_multiplier * delta_time, false)
	if clone_damage > 0:
		health_system.adjustCloneLoss(clone_damage * effect_multiplier * delta_time, false)
	if brain_damage > 0:
		health_system.adjustBrainLoss(brain_damage * effect_multiplier * delta_time, false)
	if stamina_damage > 0:
		health_system.adjustStaminaLoss(stamina_damage * effect_multiplier * delta_time, false)
	
	# Temperature effects
	if adjust_temp != 0 and health_system.has_method("adjust_body_temperature"):
		health_system.adjust_body_temperature(adjust_temp * effect_multiplier * delta_time, target_temp)
	
	# Process special effects
	_process_special_effects(target, health_system, effect_multiplier, delta_time)
	
	# Check for overdose
	_check_overdose_effects(target, health_system, reagent_container)
	
	# Process addiction
	if is_addictive and volume > addiction_threshold:
		_process_addiction(target, delta_time)

func _process_special_effects(target, health_system, multiplier: float, delta_time: float):
	"""Process special reagent effects"""
	for effect_name in effects:
		var intensity = effects[effect_name] * multiplier
		
		match effect_name:
			"painkiller":
				if health_system.has_method("reduce_pain"):
					health_system.reduce_pain(intensity * delta_time * 10)
			"stimulant":
				if health_system.has_method("add_status_effect"):
					health_system.add_status_effect("stimulated", 5.0, intensity)
			"hallucinogen":
				if randf() < intensity * delta_time * 0.1:
					health_system.add_status_effect("hallucinating", 10.0, intensity)
			"antibiotic":
				if health_system.has_method("fight_infection"):
					health_system.fight_infection(intensity * delta_time)
			"sedative":
				if health_system.has_method("add_status_effect"):
					health_system.add_status_effect("drowsy", 3.0, intensity)
			"anti_toxin":
				health_system.adjustToxLoss(-intensity * delta_time * 2, false)
			"blood_thinner":
				if health_system.has_method("set_bleeding_rate"):
					var current_bleeding = health_system.bleeding_rate
					health_system.set_bleeding_rate(current_bleeding + intensity * 0.1)
			"coagulant":
				if health_system.has_method("set_bleeding_rate"):
					var current_bleeding = health_system.bleeding_rate
					health_system.set_bleeding_rate(max(0, current_bleeding - intensity * 0.2))

func _check_overdose_effects(target, health_system, reagent_container):
	"""Check and apply overdose effects"""
	if overdose_threshold <= 0 or has_flag(FLAG_NO_OVERDOSE):
		return
	
	if volume > overdose_threshold:
		# Regular overdose
		var overdose_severity = (volume - overdose_threshold) / overdose_threshold
		
		# Apply overdose damage
		health_system.adjustToxLoss(overdose_severity * 2.0, false)
		
		# Possible side effects
		if randf() < overdose_severity * 0.1:
			health_system.add_status_effect("nauseous", 5.0, overdose_severity)
		
		# Critical overdose
		if critical_overdose_threshold > 0 and volume > critical_overdose_threshold:
			var critical_severity = (volume - critical_overdose_threshold) / critical_overdose_threshold
			
			# Severe effects
			health_system.adjustToxLoss(critical_severity * 5.0, false)
			health_system.adjustBrainLoss(critical_severity * 1.0, false)
			
			# Possible cardiac arrest
			if randf() < critical_severity * 0.05:
				if health_system.has_method("_trigger_cardiac_event"):
					health_system._trigger_cardiac_event()

func _process_addiction(target, delta_time: float):
	"""Process addiction effects"""
	if randf() < addiction_chance * delta_time:
		var health_system = target.get_node_or_null("HealthSystem")
		if health_system and health_system.has_method("add_status_effect"):
			health_system.add_status_effect("addicted_" + id, 3600.0, 1.0)  # 1 hour addiction

# === REACTION METHODS ===
func can_react_with(other_reagent: Reagent) -> bool:
	"""Check if this reagent can react with another"""
	# Basic compatibility check
	if reagent_state == ReagentState.SOLID and other_reagent.reagent_state == ReagentState.GAS:
		return false
	
	# Check for specific incompatibilities
	if id == "water" and other_reagent.id == "oil":
		return false
	
	return true

func get_reaction_products(other_reagent: Reagent) -> Array:
	"""Get products from reacting with another reagent"""
	# This will be expanded by the chemical reaction system
	return []

# === UTILITY METHODS ===
func get_description_with_effects() -> String:
	"""Get description including current effects"""
	var desc = description
	
	if volume > 0:
		desc += "\nVolume: " + str(volume) + " units"
		
		if is_harmful():
			desc += "\n[color=red]Warning: This substance may be harmful![/color]"
		
		if overdose_threshold > 0:
			desc += "\nOverdose threshold: " + str(overdose_threshold) + " units"
	
	return desc

func get_color_string() -> String:
	"""Get color as hex string"""
	return "#" + color.to_html(false)

func get_state_string() -> String:
	"""Get reagent state as string"""
	match reagent_state:
		ReagentState.SOLID:
			return "solid"
		ReagentState.LIQUID:
			return "liquid"
		ReagentState.GAS:
			return "gas"
		ReagentState.PLASMA:
			return "plasma"
		_:
			return "unknown"

func to_dict() -> Dictionary:
	"""Convert reagent to dictionary for saving/loading"""
	return {
		"id": id,
		"name": name,
		"volume": volume,
		"color": get_color_string(),
		"data": data
	}

func from_dict(dict: Dictionary):
	"""Load reagent from dictionary"""
	if dict.has("id"):
		id = dict.id
	if dict.has("name"):
		name = dict.name
	if dict.has("volume"):
		volume = dict.volume
	if dict.has("color"):
		color = Color(dict.color)
	if dict.has("data"):
		data = dict.data.duplicate()
