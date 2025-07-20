extends Node
class_name HealthSystem

# === SIGNALS ===
signal health_changed(new_health, max_health, health_percent)
signal damage_taken(amount, type, zone, source)
signal status_effect_added(effect_name, duration, intensity)
signal status_effect_removed(effect_name)
signal status_effect_updated(effect_name, remaining_time)
signal died(cause_of_death, death_time)
signal revived(revival_method)
signal entered_critical(health_percent)
signal exited_critical(new_state)
signal organ_damaged(organ_name, damage_amount, total_damage)
signal organ_healed(organ_name, heal_amount, remaining_damage)
signal limb_damaged(limb_name, damage_amount, damage_type)
signal limb_healed(limb_name, heal_amount, damage_type)
signal blood_level_changed(new_amount, max_amount, blood_percent, status)
signal pulse_changed(new_pulse, pulse_status)
signal temperature_changed(new_temp, temp_status)
signal consciousness_changed(is_conscious, reason)
signal pain_level_changed(pain_level, pain_status)
signal breathing_status_changed(breathing_rate, status)

# === CONSTANTS ===
# Health states
enum HealthState {
	ALIVE,
	UNCONSCIOUS,
	CRITICAL,
	DEAD,
	GIBBED
}

# Damage types
enum DamageType {
	BRUTE,
	BURN,
	TOXIN,
	OXYGEN,
	CLONE,
	STAMINA,
	BRAIN,
	CELLULAR,
	GENETIC,
	RADIATION
}

# Pain levels
enum PainLevel {
	NONE,
	MILD,
	MODERATE,
	SEVERE,
	EXTREME,
	UNBEARABLE
}

# Blood status
enum BloodStatus {
	NORMAL,
	SLIGHTLY_LOW,
	LOW,
	CRITICALLY_LOW,
	FATAL
}

# Pulse status
enum PulseStatus {
	NO_PULSE,
	VERY_WEAK,
	WEAK,
	NORMAL,
	ELEVATED,
	RAPID,
	DANGEROUS
}

# Temperature status
enum TemperatureStatus {
	HYPOTHERMIC,
	COLD,
	NORMAL,
	WARM,
	HYPERTHERMIC,
	CRITICAL
}

# Critical thresholds
const HEALTH_THRESHOLD_CRIT = 0
const HEALTH_THRESHOLD_DEAD = -100
const HEALTH_THRESHOLD_GIBBED = -200
const HEALTH_THRESHOLD_UNCONSCIOUS = 20

# Blood constants
const BLOOD_VOLUME_NORMAL = 560
const BLOOD_VOLUME_SAFE = 475
const BLOOD_VOLUME_OKAY = 336
const BLOOD_VOLUME_BAD = 224
const BLOOD_VOLUME_SURVIVE = 122
const BLOOD_REGEN_RATE = 0.1

# Temperature constants (in Kelvin)
const BODY_TEMP_NORMAL = 310.15  # 37°C
const BODY_TEMP_COLD_DAMAGE = 280.15  # 7°C
const BODY_TEMP_HEAT_DAMAGE = 343.15  # 70°C
const BODY_TEMP_CRITICAL_LOW = 270.15  # -3°C
const BODY_TEMP_CRITICAL_HIGH = 373.15  # 100°C

# Organ definitions
const ORGANS = {
	"heart": {"vital": true, "max_damage": 100, "affects": ["pulse", "circulation"]},
	"lungs": {"vital": true, "max_damage": 100, "affects": ["breathing", "oxygen"]},
	"liver": {"vital": false, "max_damage": 100, "affects": ["toxin_processing"]},
	"kidneys": {"vital": false, "max_damage": 100, "affects": ["toxin_filtering"]},
	"brain": {"vital": true, "max_damage": 100, "affects": ["consciousness", "motor"]},
	"eyes": {"vital": false, "max_damage": 80, "affects": ["vision"]},
	"stomach": {"vital": false, "max_damage": 80, "affects": ["digestion"]},
	"intestines": {"vital": false, "max_damage": 80, "affects": ["nutrition_processing"]}
}

# Limb definitions
const LIMBS = {
	"head": {"vital": true, "max_damage": 100, "dismemberable": false},
	"chest": {"vital": true, "max_damage": 120, "dismemberable": false},
	"groin": {"vital": false, "max_damage": 100, "dismemberable": false},
	"l_arm": {"vital": false, "max_damage": 80, "dismemberable": true},
	"r_arm": {"vital": false, "max_damage": 80, "dismemberable": true},
	"l_leg": {"vital": false, "max_damage": 80, "dismemberable": true},
	"r_leg": {"vital": false, "max_damage": 80, "dismemberable": true},
	"l_hand": {"vital": false, "max_damage": 60, "dismemberable": true},
	"r_hand": {"vital": false, "max_damage": 60, "dismemberable": true},
	"l_foot": {"vital": false, "max_damage": 60, "dismemberable": true},
	"r_foot": {"vital": false, "max_damage": 60, "dismemberable": true}
}

# === CORE HEALTH VARIABLES ===
var max_health: float = 100.0
var health: float = 100.0
var current_state = HealthState.ALIVE
var previous_state = HealthState.ALIVE

# Status flags
var godmode: bool = false
var in_stasis: bool = false
var no_pain: bool = false
var is_synthetic: bool = false
var is_dead: bool = false
var is_unconscious: bool = false

# === DAMAGE VARIABLES ===
var bruteloss: float = 0.0
var fireloss: float = 0.0
var toxloss: float = 0.0
var oxyloss: float = 0.0
var cloneloss: float = 0.0
var staminaloss: float = 0.0
var brainloss: float = 0.0
var max_stamina: float = 100.0

# === VITAL SIGNS ===
var blood_type: String = "O+"
var blood_volume: float = BLOOD_VOLUME_NORMAL
var blood_volume_maximum: float = BLOOD_VOLUME_NORMAL
var bleeding_rate: float = 0.0
var pulse: int = 70
var body_temperature: float = BODY_TEMP_NORMAL
var breathing_rate: int = 16
var blood_pressure_systolic: int = 120
var blood_pressure_diastolic: int = 80

# === ORGAN AND LIMB SYSTEMS ===
var organs: Dictionary = {}
var limbs: Dictionary = {}
var prosthetics: Dictionary = {}

# === STATUS EFFECTS ===
var status_effects: Dictionary = {}
var pain_level: float = 0.0
var shock_level: float = 0.0
var consciousness_level: float = 100.0

# === ARMOR AND RESISTANCES ===
var armor: Dictionary = {
	"melee": 0, "bullet": 0, "laser": 0, "energy": 0,
	"bomb": 0, "bio": 0, "rad": 0, "fire": 0, "acid": 0
}

var damage_resistances: Dictionary = {
	DamageType.BRUTE: 1.0,
	DamageType.BURN: 1.0,
	DamageType.TOXIN: 1.0,
	DamageType.OXYGEN: 1.0,
	DamageType.CLONE: 1.0,
	DamageType.BRAIN: 1.0,
	DamageType.STAMINA: 1.0
}

# === MEDICAL HISTORY ===
var death_time: int = 0
var revival_count: int = 0
var cause_of_death: String = ""
var medical_notes: Array = []
var diseases: Array = []
var allergies: Array = []
var medications: Array = []

# === SYSTEM REFERENCES ===
var entity = null
var health_connector = null
var inventory_system = null
var sprite_system = null
var audio_system = null
var ui_system = null
var effect_system = null

# === PERFORMANCE OPTIMIZATION ===
var update_timer: float = 0.0
var ui_update_timer: float = 0.0
var last_health_update: float = 0.0
var damage_sound_cooldown: float = 0.0

# === INITIALIZATION ===
func _ready():
	# Find parent entity and connector
	entity = get_parent()
	health_connector = get_node_or_null("../HealthConnector")
	
	# Initialize systems
	_find_and_connect_systems()
	
	# Initialize health components
	_initialize_organs()
	_initialize_limbs()
	_initialize_vital_signs()
	
	# Set up timers
	_setup_update_timers()
	
	# Generate random blood type if not set
	if blood_type == "O+":
		_generate_blood_type()
	
	# Initial health calculation
	updatehealth()
	
	print("HealthSystem: Initialized successfully")

func _find_and_connect_systems():
	"""Find and connect to other entity systems"""
	# Try to find systems in parent entity
	if entity:
		inventory_system = entity.get_node_or_null("InventorySystem")
		sprite_system = entity.get_node_or_null("UpdatedHumanSpriteSystem")
		if not sprite_system:
			sprite_system = entity.get_node_or_null("HumanSpriteSystem")
		audio_system = entity.get_node_or_null("AudioSystem")
		ui_system = entity.get_node_or_null("UISystem")
		effect_system = entity.get_node_or_null("Effect")
	
	# Connect to health connector if available
	if health_connector:
		# Connect relevant signals
		health_changed.connect(health_connector._on_health_changed)
		damage_taken.connect(health_connector._on_damage_taken)
		status_effect_added.connect(health_connector._on_status_effect_added)
		status_effect_removed.connect(health_connector._on_status_effect_removed)
		died.connect(health_connector._on_entity_died)
		revived.connect(health_connector._on_entity_revived)
		entered_critical.connect(health_connector._on_entered_critical)
		exited_critical.connect(health_connector._on_exited_critical)
		blood_level_changed.connect(health_connector._on_blood_level_changed)
	
	print("HealthSystem: System connections established")

func _initialize_organs():
	"""Initialize organ system"""
	for organ_name in ORGANS:
		var organ_data = ORGANS[organ_name]
		organs[organ_name] = {
			"name": organ_name,
			"max_damage": organ_data.max_damage,
			"damage": 0.0,
			"is_vital": organ_data.vital,
			"is_damaged": false,
			"is_failing": false,
			"is_infected": false,
			"affects": organ_data.affects,
			"efficiency": 1.0
		}

func _initialize_limbs():
	"""Initialize limb system"""
	for limb_name in LIMBS:
		var limb_data = LIMBS[limb_name]
		limbs[limb_name] = {
			"name": limb_name,
			"max_damage": limb_data.max_damage,
			"brute_damage": 0.0,
			"burn_damage": 0.0,
			"status": "healthy",
			"is_vital": limb_data.vital,
			"dismemberable": limb_data.dismemberable,
			"attached": true,
			"is_bleeding": false,
			"is_bandaged": false,
			"is_splinted": false,
			"is_infected": false,
			"wounds": [],
			"scars": []
		}

func _initialize_vital_signs():
	"""Initialize vital signs to normal ranges"""
	pulse = 70 + randi() % 20  # 70-90 BPM
	breathing_rate = 14 + randi() % 6  # 14-20 RPM
	blood_pressure_systolic = 110 + randi() % 20  # 110-130
	blood_pressure_diastolic = 70 + randi() % 20  # 70-90
	body_temperature = BODY_TEMP_NORMAL + randf_range(-1.0, 1.0)  # Slight variation

func _generate_blood_type():
	"""Generate a random blood type"""
	var types = ["O+", "O-", "A+", "A-", "B+", "B-", "AB+", "AB-"]
	var probabilities = [38, 7, 34, 6, 9, 2, 3, 1]  # Real-world distribution
	
	var roll = randi() % 100
	var cumulative = 0
	
	for i in range(types.size()):
		cumulative += probabilities[i]
		if roll < cumulative:
			blood_type = types[i]
			break

func _setup_update_timers():
	"""Set up various update timers for performance"""
	var main_timer = Timer.new()
	main_timer.wait_time = 1.0  # Main update every second
	main_timer.autostart = true
	main_timer.timeout.connect(_on_main_update_tick)
	add_child(main_timer)
	
	var fast_timer = Timer.new()
	fast_timer.wait_time = 0.1  # Fast updates for critical systems
	fast_timer.autostart = true
	fast_timer.timeout.connect(_on_fast_update_tick)
	add_child(fast_timer)

# === PROCESS FUNCTIONS ===
func _process(delta):
	"""Main process function - handles time-sensitive updates"""
	update_timer += delta
	ui_update_timer += delta
	
	# Update sound cooldowns
	if damage_sound_cooldown > 0:
		damage_sound_cooldown -= delta
	
	# Process status effects
	_process_status_effects(delta)
	
	# Process bleeding
	if bleeding_rate > 0:
		_process_bleeding(delta)
	
	# Process temperature effects
	if update_timer >= 0.5:  # Every half second
		_process_temperature_effects(delta)
	
	# Process organ effects
	_process_organ_effects(delta)
	
	# Process pain and shock
	_process_pain_and_shock(delta)
	
	# Reset update timer
	if update_timer >= 1.0:
		update_timer = 0.0

func _on_main_update_tick():
	"""Main update tick - runs every second"""
	if current_state == HealthState.DEAD:
		_process_death_effects()
		return
	
	# Natural healing and regeneration
	_process_natural_healing()
	
	# Vital sign updates
	_update_vital_signs()
	
	# Organ maintenance
	_process_organ_maintenance()
	
	# Update UI if needed
	if ui_update_timer >= 1.0:
		_update_health_ui()
		ui_update_timer = 0.0

func _on_fast_update_tick():
	"""Fast update tick - runs every 0.1 seconds for critical systems"""
	# Only process critical updates here
	if current_state == HealthState.CRITICAL:
		_process_critical_condition()
	
	# Process cardiac arrest
	if _is_in_cardiac_arrest():
		_process_cardiac_arrest()

func _process_status_effects(delta):
	"""Process all active status effects"""
	var effects_to_remove = []
	
	for effect_name in status_effects:
		var effect = status_effects[effect_name]
		var old_duration = effect.duration
		effect.duration -= delta
		
		# Process effect-specific logic
		_process_individual_effect(effect_name, effect, delta)
		
		# Emit update signal if duration changed significantly
		if abs(old_duration - effect.duration) > 0.1:
			emit_signal("status_effect_updated", effect_name, effect.duration)
		
		# Mark for removal if expired
		if effect.duration <= 0:
			effects_to_remove.append(effect_name)
	
	# Remove expired effects
	for effect_name in effects_to_remove:
		remove_status_effect(effect_name)

func _process_individual_effect(effect_name: String, effect: Dictionary, delta: float):
	"""Process a specific status effect"""
	match effect_name:
		"bleeding":
			# Handled separately in _process_bleeding
			pass
		"poisoned":
			adjustToxLoss(effect.intensity * delta * 2.0)
		"burning":
			adjustFireLoss(effect.intensity * delta * 0.5)
		"irradiated":
			adjustToxLoss(effect.intensity * delta * 0.3)
			if randf() < 0.01 * effect.intensity:
				adjustCloneLoss(1.0)
		"infected":
			if randf() < 0.1:
				adjustToxLoss(effect.intensity * 0.5)
				body_temperature += effect.intensity * 0.1
		"hypothermic":
			body_temperature = max(body_temperature - delta * effect.intensity, BODY_TEMP_CRITICAL_LOW)
		"hyperthermic":
			body_temperature = min(body_temperature + delta * effect.intensity, BODY_TEMP_CRITICAL_HIGH)
		"confused":
			# Handled by movement system
			pass
		"stunned":
			# Handled by movement system
			pass
		"unconscious":
			consciousness_level = max(0, consciousness_level - delta * 10)

func _process_bleeding(delta):
	"""Process bleeding effects"""
	if bleeding_rate <= 0:
		return
	
	var blood_loss = bleeding_rate * delta
	adjust_blood_volume(-blood_loss)
	
	# Natural clotting reduces bleeding over time
	if not status_effects.has("anticoagulant"):
		bleeding_rate = max(0, bleeding_rate - delta * 0.1)
		
		if bleeding_rate <= 0.1:
			set_bleeding_rate(0)

func _process_temperature_effects(delta):
	"""Process body temperature effects"""
	var normal_temp = BODY_TEMP_NORMAL
	
	# Temperature regulation towards normal
	var temp_diff = body_temperature - normal_temp
	var regulation_rate = 0.5 * delta
	
	if abs(temp_diff) > 1.0:
		body_temperature = lerp(body_temperature, normal_temp, regulation_rate)
	
	# Temperature damage
	if body_temperature <= BODY_TEMP_COLD_DAMAGE:
		var damage = (BODY_TEMP_COLD_DAMAGE - body_temperature) * delta * 0.1
		apply_damage(damage, DamageType.BURN, 0, "chest")
		if not status_effects.has("hypothermic"):
			add_status_effect("hypothermic", 10.0, abs(temp_diff))
	elif body_temperature >= BODY_TEMP_HEAT_DAMAGE:
		var damage = (body_temperature - BODY_TEMP_HEAT_DAMAGE) * delta * 0.1
		apply_damage(damage, DamageType.BURN, 0, "chest")
		if not status_effects.has("hyperthermic"):
			add_status_effect("hyperthermic", 10.0, temp_diff)
	
	# Emit temperature change signal
	var temp_status = _get_temperature_status()
	emit_signal("temperature_changed", body_temperature, temp_status)

func _process_organ_effects(delta):
	"""Process organ-specific effects"""
	for organ_name in organs:
		var organ = organs[organ_name]
		
		if organ.is_failing:
			_process_failing_organ(organ_name, organ, delta)
		elif organ.is_damaged:
			_process_damaged_organ(organ_name, organ, delta)

func _process_failing_organ(organ_name: String, organ: Dictionary, delta: float):
	"""Process effects of a failing organ"""
	match organ_name:
		"heart":
			# Cardiac issues
			if randf() < 0.1:
				_trigger_cardiac_event()
			pulse = max(0, pulse - delta * 10)
		
		"lungs":
			# Respiratory failure
			adjustOxyLoss(delta * 5.0)
			breathing_rate = max(0, breathing_rate - delta * 2)
		
		"liver":
			# Toxin processing failure
			adjustToxLoss(delta * 2.0)
		
		"kidneys":
			# Toxin buildup
			adjustToxLoss(delta * 1.0)
		
		"brain":
			# Neurological failure
			adjustBrainLoss(delta * 1.0)
			consciousness_level = max(0, consciousness_level - delta * 5)
			if consciousness_level <= 0 and current_state != HealthState.DEAD:
				die("brain death")

func _process_damaged_organ(organ_name: String, organ: Dictionary, delta: float):
	"""Process effects of a damaged but not failing organ"""
	var efficiency_loss = organ.damage / organ.max_damage
	organ.efficiency = max(0.1, 1.0 - efficiency_loss)
	
	match organ_name:
		"heart":
			pulse = int(pulse * organ.efficiency)
		"lungs":
			breathing_rate = int(breathing_rate * organ.efficiency)
		"liver":
			if randf() < 0.05 * efficiency_loss:
				adjustToxLoss(0.5)

func _process_pain_and_shock(delta):
	"""Process pain and shock effects"""
	# Calculate pain from damage
	var damage_pain = (bruteloss + fireloss) * 0.5
	var limb_pain = 0.0
	
	for limb_name in limbs:
		var limb = limbs[limb_name]
		limb_pain += (limb.brute_damage + limb.burn_damage) * 0.3
	
	var target_pain = damage_pain + limb_pain
	
	# Apply pain resistance
	if no_pain:
		target_pain = 0
	
	# Smooth pain changes
	pain_level = lerp(pain_level, target_pain, delta * 2.0)
	
	# Calculate shock from severe pain
	if pain_level > 30:
		shock_level = min(100, shock_level + delta * (pain_level - 30))
	else:
		shock_level = max(0, shock_level - delta * 10)
	
	# Apply shock effects
	if shock_level > 50:
		if randf() < 0.1:
			add_status_effect("stunned", 2.0, shock_level / 50)
	
	if shock_level > 80:
		adjustOxyLoss(delta * 2.0)
		if randf() < 0.05:
			_trigger_cardiac_event()
	
	# Emit pain signal
	var pain_status = _get_pain_status()
	emit_signal("pain_level_changed", pain_level, pain_status)

func _process_natural_healing():
	"""Process natural healing and regeneration"""
	if current_state != HealthState.ALIVE:
		return
	
	# Slow natural healing for minor damage
	if bruteloss > 0 and bruteloss < 20:
		adjustBruteLoss(-0.1)
	
	if fireloss > 0 and fireloss < 20:
		adjustFireLoss(-0.1)
	
	# Blood regeneration
	if blood_volume < blood_volume_maximum:
		adjust_blood_volume(BLOOD_REGEN_RATE)
	
	# Stamina regeneration (faster when resting)
	if staminaloss > 0:
		var regen_rate = 2.0
		if entity and "is_lying" in entity and entity.is_lying:
			regen_rate *= 2.0
		adjustStaminaLoss(-regen_rate)

func _update_vital_signs():
	"""Update vital signs based on current health state"""
	# Calculate pulse based on health and blood loss
	var base_pulse = 70
	var health_factor = 1.0 - (health / max_health)
	var blood_factor = 1.0 - (blood_volume / blood_volume_maximum)
	
	pulse = int(base_pulse + (health_factor * 30) + (blood_factor * 40))
	pulse = clamp(pulse, 0, 200)
	
	# Breathing rate
	var base_breathing = 16
	breathing_rate = int(base_breathing + (oxyloss * 0.2))
	breathing_rate = clamp(breathing_rate, 0, 40)
	
	# Blood pressure
	blood_pressure_systolic = int(120 - (blood_volume / blood_volume_maximum) * 40)
	blood_pressure_diastolic = int(80 - (blood_volume / blood_volume_maximum) * 20)
	
	# Emit vital sign signals
	var pulse_status = _get_pulse_status()
	emit_signal("pulse_changed", pulse, pulse_status)
	
	var breathing_status = _get_breathing_status()
	emit_signal("breathing_status_changed", breathing_rate, breathing_status)

func _process_critical_condition():
	"""Process effects while in critical condition"""
	# Random damage accumulation
	if randf() < 0.1:
		adjustOxyLoss(0.5)
	
	# Possible cardiac arrest
	if randf() < 0.05:
		_trigger_cardiac_event()

func _process_cardiac_arrest():
	"""Process cardiac arrest effects"""
	pulse = 0
	adjustOxyLoss(2.0)
	consciousness_level = max(0, consciousness_level - 5.0)

func _process_death_effects():
	"""Process effects while dead"""
	death_time += 1
	
	# Body decay after extended time
	if death_time > 1800:  # 30 minutes
		if randf() < 0.01:
			adjustCloneLoss(0.1)

func _process_organ_maintenance():
	"""Maintain organ health and status"""
	for organ_name in organs:
		var organ = organs[organ_name]
		
		# Update organ status based on damage
		if organ.damage > organ.max_damage * 0.8:
			organ.is_failing = true
		elif organ.damage > organ.max_damage * 0.3:
			organ.is_damaged = true
		else:
			organ.is_damaged = false
			organ.is_failing = false

# === DAMAGE FUNCTIONS ===
func apply_damage(amount: float, damage_type: int, penetration: float = 0, zone: String = "", source = null) -> float:
	"""Apply damage with comprehensive calculation"""
	if godmode or amount <= 0:
		return 0.0
	
	# Don't apply damage to already dead entities unless forced
	if current_state == HealthState.DEAD and zone == "":
		return 0.0
	
	# Calculate actual damage after resistances and armor
	var actual_damage = _calculate_final_damage(amount, damage_type, penetration, zone)
	
	if actual_damage <= 0:
		return 0.0
	
	# Apply damage to specific zone or general health
	if zone != "" and limbs.has(zone):
		_apply_limb_damage(zone, actual_damage, damage_type)
	else:
		_apply_general_damage(actual_damage, damage_type)
	
	# Special damage effects
	_process_damage_effects(actual_damage, damage_type, zone, source)
	
	# Update health and check thresholds
	updatehealth()
	
	# Emit signals
	emit_signal("damage_taken", actual_damage, damage_type, zone, source)
	
	# Play damage sounds
	_play_damage_sound(damage_type, actual_damage)
	
	return actual_damage

func _calculate_final_damage(amount: float, damage_type: int, penetration: float, zone: String) -> float:
	"""Calculate final damage after all modifiers"""
	var modified_damage = amount
	
	# Apply damage resistance
	if damage_resistances.has(damage_type):
		modified_damage *= damage_resistances[damage_type]
	
	# Apply armor if applicable
	var armor_reduction = _calculate_armor_reduction(damage_type, penetration)
	modified_damage *= (1.0 - armor_reduction)
	
	# Zone-specific multipliers
	if zone != "":
		modified_damage *= _get_zone_damage_multiplier(zone)
	
	# Synthetic resistance
	if is_synthetic:
		match damage_type:
			DamageType.TOXIN:
				modified_damage *= 0.5  # Synthetics resist toxins
			DamageType.OXYGEN:
				modified_damage = 0  # Synthetics don't need oxygen
	
	return max(0, modified_damage)

func _calculate_armor_reduction(damage_type: int, penetration: float) -> float:
	"""Calculate armor damage reduction"""
	var armor_type = ""
	
	match damage_type:
		DamageType.BRUTE:
			armor_type = "melee"
		DamageType.BURN:
			armor_type = "fire"
		DamageType.TOXIN:
			armor_type = "bio"
		_:
			return 0.0
	
	if not armor.has(armor_type):
		return 0.0
	
	var armor_value = armor[armor_type]
	var effective_armor = max(0, armor_value - penetration)
	
	# Convert armor value to percentage reduction (cap at 90%)
	return min(0.9, effective_armor * 0.01)

func _get_zone_damage_multiplier(zone: String) -> float:
	"""Get damage multiplier for specific body zone"""
	match zone:
		"head":
			return 1.5
		"chest":
			return 1.2
		"groin":
			return 1.1
		_:
			return 1.0

func _apply_general_damage(amount: float, damage_type: int):
	"""Apply damage to general health pools"""
	match damage_type:
		DamageType.BRUTE:
			adjustBruteLoss(amount)
		DamageType.BURN:
			adjustFireLoss(amount)
		DamageType.TOXIN:
			adjustToxLoss(amount)
		DamageType.OXYGEN:
			adjustOxyLoss(amount)
		DamageType.CLONE:
			adjustCloneLoss(amount)
		DamageType.BRAIN:
			adjustBrainLoss(amount)
		DamageType.STAMINA:
			adjustStaminaLoss(amount)

func _apply_limb_damage(zone: String, amount: float, damage_type: int):
	"""Apply damage to a specific limb"""
	if not limbs.has(zone):
		return
	
	var limb = limbs[zone]
	var applied_damage = 0.0
	
	match damage_type:
		DamageType.BRUTE:
			limb.brute_damage += amount
			applied_damage = amount
		DamageType.BURN:
			limb.burn_damage += amount
			applied_damage = amount
		_:
			# Non-physical damage goes to general pools
			_apply_general_damage(amount, damage_type)
			return
	
	# Update limb status
	_update_limb_status(zone)
	
	# Apply portion of limb damage to general health
	var general_damage = applied_damage * 0.4
	if damage_type == DamageType.BRUTE:
		adjustBruteLoss(general_damage)
	else:
		adjustFireLoss(general_damage)
	
	# Check for bleeding
	if applied_damage > 15 and not limb.is_bleeding:
		_start_limb_bleeding(zone, applied_damage)
	
	# Check for dismemberment
	if limb.dismemberable:
		_check_dismemberment(zone, applied_damage, damage_type)
	
	emit_signal("limb_damaged", zone, applied_damage, damage_type)

func _process_damage_effects(amount: float, damage_type: int, zone: String, source):
	"""Process special effects from damage"""
	# Blood splatter for brute damage
	if damage_type == DamageType.BRUTE and amount > 10:
		_create_blood_splatter(amount)
	
	# Pain from physical damage
	if damage_type in [DamageType.BRUTE, DamageType.BURN] and not no_pain:
		var pain_amount = amount * 0.8
		pain_level = min(100, pain_level + pain_amount)
	
	# Check for massive damage effects
	if amount > 50:
		_check_massive_damage_effects(amount, damage_type)

func _check_massive_damage_effects(amount: float, damage_type: int):
	"""Check for effects from massive damage"""
	# Shock from massive damage
	shock_level = min(100, shock_level + amount)
	
	# Possible unconsciousness
	if amount > 60 and randf() < 0.3:
		add_status_effect("unconscious", 5.0, amount / 20)
	
	# Possible cardiac arrest from severe trauma
	if amount > 80 and randf() < 0.2:
		_trigger_cardiac_event()

# === ADJUSTMENT FUNCTIONS ===
func adjustBruteLoss(amount: float, update_health: bool = true):
	"""Adjust brute damage"""
	if godmode and amount > 0:
		return
	
	bruteloss = max(0, bruteloss + amount)
	
	if update_health:
		updatehealth()

func adjustFireLoss(amount: float, update_health: bool = true):
	"""Adjust burn damage"""
	if godmode and amount > 0:
		return
	
	fireloss = max(0, fireloss + amount)
	
	if update_health:
		updatehealth()

func adjustToxLoss(amount: float, update_health: bool = true):
	"""Adjust toxin damage"""
	if godmode and amount > 0:
		return
	
	toxloss = max(0, toxloss + amount)
	
	if update_health:
		updatehealth()

func adjustOxyLoss(amount: float, update_health: bool = true):
	"""Adjust oxygen damage"""
	if godmode and amount > 0:
		return
	
	oxyloss = max(0, oxyloss + amount)
	
	if update_health:
		updatehealth()

func adjustCloneLoss(amount: float, update_health: bool = true):
	"""Adjust clone damage"""
	if godmode and amount > 0:
		return
	
	cloneloss = max(0, cloneloss + amount)
	
	if update_health:
		updatehealth()

func adjustBrainLoss(amount: float, update_health: bool = true):
	"""Adjust brain damage with neurological effects"""
	if godmode and amount > 0:
		return
	
	brainloss = max(0, brainloss + amount)
	
	# Apply brain damage effects
	if brainloss > 20:
		add_status_effect("confused", 10.0, brainloss / 50)
	
	if brainloss > 40:
		consciousness_level = max(0, consciousness_level - amount)
	
	if brainloss > 80:
		if organs.has("brain"):
			organs["brain"].is_failing = true
	
	if update_health:
		updatehealth()

func adjustStaminaLoss(amount: float, update_health: bool = true):
	"""Adjust stamina damage"""
	if godmode and amount > 0:
		return
	
	staminaloss = clamp(staminaloss + amount, 0, max_stamina)
	
	# Apply exhaustion effects
	if staminaloss >= max_stamina * 0.9:
		add_status_effect("exhausted", 5.0, 2.0)
	
	if update_health:
		updatehealth()

func adjust_blood_volume(amount: float):
	"""Adjust blood volume with status effects"""
	var old_volume = blood_volume
	blood_volume = clamp(blood_volume + amount, 0, blood_volume_maximum)
	
	# Calculate blood status
	var blood_percent = blood_volume / blood_volume_maximum
	var status = _get_blood_status()
	
	# Apply blood loss effects
	if blood_percent < 0.8 and blood_percent >= 0.6:
		if not status_effects.has("pale"):
			add_status_effect("pale", 30.0, 1.0)
	elif blood_percent < 0.6 and blood_percent >= 0.4:
		add_status_effect("dizzy", 10.0, 2.0)
		adjustOxyLoss(0.5)
	elif blood_percent < 0.4:
		add_status_effect("weak", 10.0, 3.0)
		adjustOxyLoss(1.0)
		
		if blood_percent < 0.2 and current_state != HealthState.DEAD:
			die("blood loss")
	
	# Emit signal
	emit_signal("blood_level_changed", blood_volume, blood_volume_maximum, blood_percent, status)

# === HEALTH UPDATE FUNCTIONS ===
func updatehealth():
	"""Update overall health and check state transitions"""
	if godmode:
		health = max_health
		return
	
	var old_health = health
	var old_state = current_state
	
	# Calculate health
	health = max_health - bruteloss - fireloss - toxloss - oxyloss - cloneloss
	
	# Check for state transitions
	_check_health_state_transitions()
	
	# Update consciousness based on health and other factors
	_update_consciousness()
	
	# Update UI if health changed significantly
	if abs(old_health - health) > 1.0 or old_state != current_state:
		_update_health_ui()

func _check_health_state_transitions():
	"""Check and handle health state transitions"""
	var new_state = current_state
	
	# Death threshold
	if health <= HEALTH_THRESHOLD_DEAD and current_state != HealthState.DEAD:
		die("damage")
		return
	
	# Critical threshold
	if health <= HEALTH_THRESHOLD_CRIT and current_state == HealthState.ALIVE:
		new_state = HealthState.CRITICAL
	elif health > HEALTH_THRESHOLD_CRIT and current_state == HealthState.CRITICAL:
		new_state = HealthState.ALIVE
	
	# Unconsciousness threshold
	if health <= HEALTH_THRESHOLD_UNCONSCIOUS and current_state == HealthState.ALIVE:
		new_state = HealthState.UNCONSCIOUS
	elif consciousness_level <= 0 and current_state != HealthState.DEAD:
		new_state = HealthState.UNCONSCIOUS
	elif consciousness_level > 30 and current_state == HealthState.UNCONSCIOUS:
		new_state = HealthState.ALIVE
	
	# Handle state changes
	if new_state != current_state:
		_change_health_state(new_state)

func _change_health_state(new_state: int):
	"""Change health state with appropriate effects"""
	var old_state = current_state
	previous_state = current_state
	current_state = new_state
	
	match new_state:
		HealthState.ALIVE:
			is_unconscious = false
			if old_state == HealthState.CRITICAL:
				emit_signal("exited_critical", new_state)
			elif old_state == HealthState.UNCONSCIOUS:
				emit_signal("consciousness_changed", true, "recovered")
		
		HealthState.UNCONSCIOUS:
			is_unconscious = true
			add_status_effect("unconscious", 999999)
			emit_signal("consciousness_changed", false, "health_loss")
		
		HealthState.CRITICAL:
			add_status_effect("unconscious", 999999)
			emit_signal("entered_critical", health / max_health)
		
		HealthState.DEAD:
			# Handled by die() function
			pass

func _update_consciousness():
	"""Update consciousness level based on various factors"""
	if current_state == HealthState.DEAD:
		consciousness_level = 0
		return
	
	var target_consciousness = 100.0
	
	# Health factor
	var health_factor = health / max_health
	target_consciousness *= max(0.1, health_factor)
	
	# Blood loss factor
	var blood_factor = blood_volume / blood_volume_maximum
	target_consciousness *= max(0.1, blood_factor)
	
	# Brain damage factor
	if brainloss > 0:
		target_consciousness *= max(0.1, 1.0 - (brainloss / 100.0))
	
	# Oxygen deprivation factor
	if oxyloss > 30:
		target_consciousness *= max(0.1, 1.0 - ((oxyloss - 30) / 70.0))
	
	# Apply changes smoothly
	consciousness_level = lerp(consciousness_level, target_consciousness, 0.1)

# === STATUS EFFECT FUNCTIONS ===
func add_status_effect(effect_name: String, duration: float, intensity: float = 1.0):
	"""Add or update a status effect"""
	if godmode and effect_name in ["poisoned", "burning", "bleeding"]:
		return
	
	var was_new = not status_effects.has(effect_name)
	var old_duration = 0.0
	
	if not was_new:
		old_duration = status_effects[effect_name].duration
	
	# Add or update effect
	status_effects[effect_name] = {
		"duration": max(duration, old_duration),  # Take longer duration
		"intensity": max(intensity, status_effects.get(effect_name, {}).get("intensity", 0)),
		"start_time": Time.get_ticks_msec() / 1000.0
	}
	
	# Apply immediate effects
	_apply_status_effect_start(effect_name, intensity)
	
	# Emit signal
	if was_new:
		emit_signal("status_effect_added", effect_name, duration, intensity)

func remove_status_effect(effect_name: String):
	"""Remove a status effect"""
	if not status_effects.has(effect_name):
		return
	
	# Apply removal effects
	_apply_status_effect_end(effect_name)
	
	# Remove from dictionary
	status_effects.erase(effect_name)
	
	# Emit signal
	emit_signal("status_effect_removed", effect_name)

func _apply_status_effect_start(effect_name: String, intensity: float):
	"""Apply effects when status effect starts"""
	match effect_name:
		"bleeding":
			set_bleeding_rate(max(bleeding_rate, intensity))
		"unconscious":
			consciousness_level = 0
			if entity and entity.has_method("lie_down"):
				entity.lie_down(true)
		"confused":
			if entity and entity.has_method("add_status_effect"):
				entity.add_status_effect(effect_name, 0, intensity)
		"stunned":
			if entity and entity.has_method("stun"):
				entity.stun(intensity)

func _apply_status_effect_end(effect_name: String):
	"""Apply effects when status effect ends"""
	match effect_name:
		"bleeding":
			set_bleeding_rate(0)
		"unconscious":
			if current_state == HealthState.ALIVE:
				consciousness_level = 50.0
		"confused":
			if entity and entity.has_method("remove_status_effect"):
				entity.remove_status_effect(effect_name)

# === ORGAN AND LIMB FUNCTIONS ===
func apply_organ_damage(organ_name: String, amount: float) -> float:
	"""Apply damage to a specific organ"""
	if not organs.has(organ_name) or amount <= 0:
		return 0.0
	
	var organ = organs[organ_name]
	var old_damage = organ.damage
	
	organ.damage = min(organ.max_damage, organ.damage + amount)
	var actual_damage = organ.damage - old_damage
	
	# Update organ status
	_update_organ_status(organ_name)
	
	# Check for organ failure
	if organ.is_vital and organ.is_failing and current_state != HealthState.DEAD:
		die(organ_name + " failure")
	
	emit_signal("organ_damaged", organ_name, actual_damage, organ.damage)
	
	return actual_damage

func heal_organ_damage(organ_name: String, amount: float) -> float:
	"""Heal damage to a specific organ"""
	if not organs.has(organ_name) or amount <= 0:
		return 0.0
	
	var organ = organs[organ_name]
	var old_damage = organ.damage
	
	organ.damage = max(0, organ.damage - amount)
	var healed_amount = old_damage - organ.damage
	
	# Update organ status
	_update_organ_status(organ_name)
	
	emit_signal("organ_healed", organ_name, healed_amount, organ.damage)
	
	return healed_amount

func _update_organ_status(organ_name: String):
	"""Update organ status based on damage"""
	var organ = organs[organ_name]
	
	var damage_percent = organ.damage / organ.max_damage
	
	organ.is_damaged = damage_percent > 0.3
	organ.is_failing = damage_percent > 0.8
	organ.efficiency = max(0.1, 1.0 - damage_percent)

func heal_limb_damage(limb_name: String, brute_amount: float = 0, burn_amount: float = 0) -> float:
	"""Heal damage to a specific limb"""
	if not limbs.has(limb_name):
		return 0.0
	
	var limb = limbs[limb_name]
	var healed_total = 0.0
	
	if brute_amount > 0:
		var healed = min(limb.brute_damage, brute_amount)
		limb.brute_damage -= healed
		healed_total += healed
		
		if healed > 0:
			emit_signal("limb_healed", limb_name, healed, DamageType.BRUTE)
	
	if burn_amount > 0:
		var healed = min(limb.burn_damage, burn_amount)
		limb.burn_damage -= healed
		healed_total += healed
		
		if healed > 0:
			emit_signal("limb_healed", limb_name, healed, DamageType.BURN)
	
	# Update limb status
	_update_limb_status(limb_name)
	
	return healed_total

func _update_limb_status(limb_name: String):
	"""Update limb status based on damage"""
	var limb = limbs[limb_name]
	var total_damage = limb.brute_damage + limb.burn_damage
	
	if total_damage < 20:
		limb.status = "healthy"
	elif total_damage < 40:
		limb.status = "bruised"
	elif total_damage < 60:
		limb.status = "wounded"
	elif total_damage < 80:
		limb.status = "mangled"
	else:
		limb.status = "critical"
	
	# Update sprite system if available
	if sprite_system and sprite_system.has_method("update_limb_damage"):
		sprite_system.update_limb_damage(limb_name, limb.status, limb.brute_damage, limb.burn_damage)

func _start_limb_bleeding(limb_name: String, damage_amount: float):
	"""Start bleeding from a limb"""
	if not limbs.has(limb_name):
		return
	
	var limb = limbs[limb_name]
	limb.is_bleeding = true
	
	# Calculate bleeding rate based on damage
	var bleed_rate = damage_amount * 0.1
	set_bleeding_rate(bleeding_rate + bleed_rate)
	
	add_status_effect("bleeding", 60.0, bleed_rate)

func _check_dismemberment(limb_name: String, damage_amount: float, damage_type: int):
	"""Check if limb should be dismembered"""
	var limb = limbs[limb_name]
	var total_damage = limb.brute_damage + limb.burn_damage
	
	# High chance with massive damage
	if damage_amount > 60 and randf() < 0.4:
		_dismember_limb(limb_name)
		return
	
	# Gradual chance with accumulated damage
	if total_damage > limb.max_damage * 0.9:
		var chance = (total_damage - limb.max_damage * 0.9) / (limb.max_damage * 0.1)
		if randf() < chance * 0.3:
			_dismember_limb(limb_name)

func _dismember_limb(limb_name: String):
	"""Dismember a limb"""
	if not limbs.has(limb_name):
		return
	
	var limb = limbs[limb_name]
	limb.attached = false
	limb.status = "missing"
	
	# Apply massive bleeding and damage
	adjustBruteLoss(25.0)
	set_bleeding_rate(bleeding_rate + 8.0)
	add_status_effect("bleeding", 120.0, 8.0)
	
	# Pain and shock
	if not no_pain:
		pain_level = min(100, pain_level + 40)
		shock_level = min(100, shock_level + 30)
	
	# Update visuals
	if sprite_system and sprite_system.has_method("update_dismemberment"):
		sprite_system.update_dismemberment(limb_name)
	
	# Play sound
	if audio_system:
		audio_system.play_sound("dismember", 0.8)
	
	emit_signal("limb_damaged", limb_name, 100.0, DamageType.BRUTE)

# === BLOOD AND CIRCULATION ===
func set_bleeding_rate(rate: float):
	"""Set bleeding rate with effects"""
	bleeding_rate = max(0, rate)
	
	if bleeding_rate > 0:
		if not status_effects.has("bleeding"):
			add_status_effect("bleeding", 60.0, bleeding_rate)
		
		# Update any bleeding limbs
		for limb_name in limbs:
			var limb = limbs[limb_name]
			if limb.is_bleeding and bleeding_rate == 0:
				limb.is_bleeding = false
	else:
		remove_status_effect("bleeding")

func _create_blood_splatter(damage_amount: float):
	"""Create blood splatter effects"""
	if blood_volume <= 0:
		return
	
	var splatter_chance = min(80, damage_amount * 2)
	
	if randf() * 100 < splatter_chance:
		# Create visual blood effect
		if sprite_system and sprite_system.has_method("create_blood_splatter"):
			sprite_system.create_blood_splatter()
		
		# Reduce blood volume slightly
		adjust_blood_volume(-0.5)

# === CARDIAC FUNCTIONS ===
func _is_in_cardiac_arrest() -> bool:
	"""Check if in cardiac arrest"""
	return pulse == 0 and current_state != HealthState.DEAD

func _trigger_cardiac_event():
	"""Trigger a cardiac event"""
	pulse = 0
	add_status_effect("cardiac_arrest", 60.0, 1.0)
	
	if audio_system:
		audio_system.play_sound("heart_stop", 0.6)

func apply_cpr(effectiveness: float = 1.0) -> bool:
	"""Apply CPR with variable effectiveness"""
	if current_state == HealthState.DEAD:
		return false
	
	# Provide oxygen
	adjustOxyLoss(-3.0 * effectiveness)
	
	# Chance to restart heart if in cardiac arrest
	if _is_in_cardiac_arrest():
		if randf() < 0.15 * effectiveness:
			pulse = 40  # Weak pulse from CPR
			remove_status_effect("cardiac_arrest")
			return true
	
	return false

func apply_defibrillation(power: float = 1.0) -> bool:
	"""Apply defibrillation"""
	if current_state == HealthState.DEAD and death_time > 300:
		return false  # Too late
	
	# Higher chance to restart heart
	if _is_in_cardiac_arrest() or current_state == HealthState.DEAD:
		if randf() < 0.7 * power:
			pulse = 60
			remove_status_effect("cardiac_arrest")
			
			if current_state == HealthState.DEAD:
				revive("defibrillation")
			
			if audio_system:
				audio_system.play_sound("heart_start", 0.6)
			
			return true
	
	return false

# === DEATH AND REVIVAL ===
func die(cause: String = "unknown"):
	"""Handle death with comprehensive effects"""
	if current_state == HealthState.DEAD or godmode:
		return
	
	print("HealthSystem: Entity died. Cause: " + cause)
	
	# Update state
	previous_state = current_state
	current_state = HealthState.DEAD
	is_dead = true
	cause_of_death = cause
	death_time = 0
	
	# Reset vital signs
	pulse = 0
	breathing_rate = 0
	consciousness_level = 0
	
	# Add death status effects
	add_status_effect("unconscious", 999999)
	
	# Stop bleeding (blood pressure = 0)
	set_bleeding_rate(0)
	
	# Force lying down
	if entity and entity.has_method("lie_down"):
		entity.lie_down(true)
	
	# Drop items
	_drop_all_items()
	
	# Update visuals
	if sprite_system and sprite_system.has_method("update_death_state"):
		sprite_system.update_death_state(true)
	
	# Play death sound
	if audio_system:
		audio_system.play_sound("death", 0.8)
	
	# Emit signal
	emit_signal("died", cause_of_death, death_time)
	emit_signal("consciousness_changed", false, "death")
	
	# Update UI
	_update_health_ui()

func revive(method: String = "unknown") -> bool:
	"""Revive the entity"""
	if current_state != HealthState.DEAD:
		return false
	
	# Check if revival is possible
	if death_time > 1800 and method != "admin":  # 30 minutes
		return false
	
	revival_count += 1
	
	# Partial healing based on method
	match method:
		"admin":
			full_heal(true)
		"defibrillation":
			_partial_revival_heal()
		"advanced_medical":
			_advanced_revival_heal()
		_:
			_basic_revival_heal()
	
	# Reset death state
	current_state = HealthState.CRITICAL  # Start in critical
	is_dead = false
	death_time = 0
	cause_of_death = ""
	
	# Restore basic vital signs
	pulse = 40  # Weak pulse initially
	breathing_rate = 10
	consciousness_level = 20
	
	# Remove death effects
	remove_status_effect("unconscious")
	
	# Update visuals
	if sprite_system and sprite_system.has_method("update_death_state"):
		sprite_system.update_death_state(false)
	
	# Play revival sound
	if audio_system:
		audio_system.play_sound("revive", 0.6)
	
	# Update health
	updatehealth()
	
	# Emit signals
	emit_signal("revived", method)
	emit_signal("consciousness_changed", true, "revived")
	
	print("HealthSystem: Entity revived via " + method)
	
	return true

func _partial_revival_heal():
	"""Healing for basic revival methods"""
	oxyloss = max(0, oxyloss - 40)
	bruteloss = max(0, bruteloss - 20)
	fireloss = max(0, fireloss - 20)
	blood_volume = max(blood_volume, BLOOD_VOLUME_OKAY)

func _advanced_revival_heal():
	"""Healing for advanced revival methods"""
	oxyloss = 0
	bruteloss = max(0, bruteloss - 40)
	fireloss = max(0, fireloss - 40)
	toxloss = max(0, toxloss - 30)
	blood_volume = max(blood_volume, BLOOD_VOLUME_SAFE)

func _basic_revival_heal():
	"""Minimal healing for basic revival"""
	oxyloss = max(0, oxyloss - 30)
	bruteloss = max(0, bruteloss - 10)
	blood_volume = max(blood_volume, BLOOD_VOLUME_BAD)

# === STATUS HELPER FUNCTIONS ===
func _get_blood_status() -> int:
	"""Get blood status enum"""
	var blood_percent = blood_volume / blood_volume_maximum
	
	if blood_percent >= 0.8:
		return BloodStatus.NORMAL
	elif blood_percent >= 0.6:
		return BloodStatus.SLIGHTLY_LOW
	elif blood_percent >= 0.4:
		return BloodStatus.LOW
	elif blood_percent >= 0.2:
		return BloodStatus.CRITICALLY_LOW
	else:
		return BloodStatus.FATAL

func _get_pulse_status() -> int:
	"""Get pulse status enum"""
	if pulse == 0:
		return PulseStatus.NO_PULSE
	elif pulse < 40:
		return PulseStatus.VERY_WEAK
	elif pulse < 60:
		return PulseStatus.WEAK
	elif pulse <= 100:
		return PulseStatus.NORMAL
	elif pulse <= 120:
		return PulseStatus.ELEVATED
	elif pulse <= 150:
		return PulseStatus.RAPID
	else:
		return PulseStatus.DANGEROUS

func _get_temperature_status() -> int:
	"""Get temperature status enum"""
	var temp_c = body_temperature - 273.15
	
	if temp_c < 30:
		return TemperatureStatus.HYPOTHERMIC
	elif temp_c < 35:
		return TemperatureStatus.COLD
	elif temp_c <= 39:
		return TemperatureStatus.NORMAL
	elif temp_c <= 41:
		return TemperatureStatus.WARM
	elif temp_c <= 43:
		return TemperatureStatus.HYPERTHERMIC
	else:
		return TemperatureStatus.CRITICAL

func _get_pain_status() -> int:
	"""Get pain status enum"""
	if pain_level <= 0:
		return PainLevel.NONE
	elif pain_level <= 15:
		return PainLevel.MILD
	elif pain_level <= 35:
		return PainLevel.MODERATE
	elif pain_level <= 60:
		return PainLevel.SEVERE
	elif pain_level <= 85:
		return PainLevel.EXTREME
	else:
		return PainLevel.UNBEARABLE

func _get_breathing_status() -> String:
	"""Get breathing status description"""
	if breathing_rate == 0:
		return "not_breathing"
	elif breathing_rate < 10:
		return "slow"
	elif breathing_rate <= 20:
		return "normal"
	elif breathing_rate <= 30:
		return "rapid"
	else:
		return "hyperventilating"

# === UTILITY FUNCTIONS ===
func full_heal(admin_heal: bool = false):
	"""Completely heal the entity"""
	# Reset all damage
	bruteloss = 0.0
	fireloss = 0.0
	toxloss = 0.0
	oxyloss = 0.0
	cloneloss = 0.0
	brainloss = 0.0
	staminaloss = 0.0
	
	# Reset vital signs
	blood_volume = blood_volume_maximum
	pulse = 70
	breathing_rate = 16
	body_temperature = BODY_TEMP_NORMAL
	consciousness_level = 100.0
	pain_level = 0.0
	shock_level = 0.0
	
	# Clear all status effects
	var effects_to_remove = status_effects.keys()
	for effect in effects_to_remove:
		remove_status_effect(effect)
	
	# Heal all organs
	for organ_name in organs:
		organs[organ_name].damage = 0.0
		organs[organ_name].is_damaged = false
		organs[organ_name].is_failing = false
		organs[organ_name].efficiency = 1.0
	
	# Heal all limbs
	for limb_name in limbs:
		limbs[limb_name].brute_damage = 0.0
		limbs[limb_name].burn_damage = 0.0
		limbs[limb_name].status = "healthy"
		limbs[limb_name].is_bleeding = false
		limbs[limb_name].attached = true
		_update_limb_status(limb_name)
	
	# Revive if dead
	if current_state == HealthState.DEAD and admin_heal:
		current_state = HealthState.ALIVE
		is_dead = false
		death_time = 0
		cause_of_death = ""
	
	# Update health
	updatehealth()
	
	# Play healing sound
	if audio_system:
		audio_system.play_sound("heal", 0.5)

func toggle_godmode(enabled: bool = false) -> bool:
	"""Toggle godmode"""
	if enabled != null:
		godmode = enabled
	else:
		godmode = not godmode
	
	if godmode:
		full_heal(true)
	
	return godmode

func get_health_percent() -> float:
	"""Get health as percentage"""
	return (health / max_health) * 100.0

func is_bleeding() -> bool:
	"""Check if currently bleeding"""
	return bleeding_rate > 0

func get_pulse() -> int:
	"""Get current pulse"""
	return pulse

func get_body_temperature() -> float:
	"""Get body temperature in Celsius"""
	return body_temperature - 273.15

func get_blood_pressure() -> String:
	"""Get blood pressure as string"""
	return str(blood_pressure_systolic) + "/" + str(blood_pressure_diastolic)

func get_respiratory_rate() -> int:
	"""Get breathing rate"""
	return breathing_rate

# === DATA ACCESS FUNCTIONS ===
func get_status_report() -> Dictionary:
	"""Get comprehensive status report for health analyzer"""
	var report = {
		"health": health,
		"max_health": max_health,
		"health_percent": get_health_percent(),
		"state": _get_state_string(),
		"is_dead": is_dead,
		"is_unconscious": is_unconscious,
		
		"damage": {
			"brute": bruteloss,
			"burn": fireloss,
			"toxin": toxloss,
			"oxygen": oxyloss,
			"clone": cloneloss,
			"brain": brainloss,
			"stamina": staminaloss
		},
		
		"vital_signs": {
			"pulse": pulse,
			"pulse_status": _get_pulse_status(),
			"breathing_rate": breathing_rate,
			"breathing_status": _get_breathing_status(),
			"body_temperature": get_body_temperature(),
			"temperature_status": _get_temperature_status(),
			"blood_pressure": get_blood_pressure(),
			"consciousness": consciousness_level,
			"pain_level": pain_level,
			"pain_status": _get_pain_status()
		},
		
		"blood": {
			"volume": blood_volume,
			"max_volume": blood_volume_maximum,
			"type": blood_type,
			"bleeding_rate": bleeding_rate,
			"is_bleeding": is_bleeding(),
			"blood_percent": (blood_volume / blood_volume_maximum) * 100.0,
			"blood_status": _get_blood_status()
		},
		
		"organs": _get_organ_report(),
		"limbs": _get_limb_report(),
		"status_effects": _get_status_effects_list(),
		"diseases": diseases.duplicate(),
		"medications": medications.duplicate(),
		
		"medical_history": {
			"cause_of_death": cause_of_death,
			"death_time": death_time,
			"revival_count": revival_count,
			"medical_notes": medical_notes.duplicate()
		}
	}
	
	return report

func _get_state_string() -> String:
	"""Get health state as string"""
	match current_state:
		HealthState.ALIVE:
			return "alive"
		HealthState.UNCONSCIOUS:
			return "unconscious"
		HealthState.CRITICAL:
			return "critical"
		HealthState.DEAD:
			return "dead"
		HealthState.GIBBED:
			return "gibbed"
		_:
			return "unknown"

func _get_organ_report() -> Dictionary:
	"""Get detailed organ report"""
	var report = {}
	
	for organ_name in organs:
		var organ = organs[organ_name]
		report[organ_name] = {
			"damage": organ.damage,
			"max_damage": organ.max_damage,
			"damage_percent": (organ.damage / organ.max_damage) * 100.0,
			"is_damaged": organ.is_damaged,
			"is_failing": organ.is_failing,
			"efficiency": organ.efficiency,
			"status": _get_organ_status_string(organ)
		}
	
	return report

func _get_limb_report() -> Dictionary:
	"""Get detailed limb report"""
	var report = {}
	
	for limb_name in limbs:
		var limb = limbs[limb_name]
		var total_damage = limb.brute_damage + limb.burn_damage
		
		report[limb_name] = {
			"brute_damage": limb.brute_damage,
			"burn_damage": limb.burn_damage,
			"total_damage": total_damage,
			"max_damage": limb.max_damage,
			"status": limb.status,
			"attached": limb.attached,
			"is_bleeding": limb.is_bleeding,
			"is_bandaged": limb.is_bandaged,
			"is_splinted": limb.is_splinted
		}
	
	return report

func _get_status_effects_list() -> Array:
	"""Get list of active status effects"""
	var effects_list = []
	
	for effect_name in status_effects:
		var effect = status_effects[effect_name]
		effects_list.append({
			"name": effect_name,
			"duration": effect.duration,
			"intensity": effect.intensity
		})
	
	return effects_list

func _get_organ_status_string(organ: Dictionary) -> String:
	"""Get organ status as string"""
	if organ.is_failing:
		return "failing"
	elif organ.is_damaged:
		return "damaged"
	else:
		return "healthy"

func get_reagents() -> Array:
	"""Get list of chemicals/reagents in bloodstream"""
	# This would integrate with a chemistry system
	# For now, return medications as placeholder
	var reagents = []
	
	for med in medications:
		reagents.append({
			"name": med.name,
			"amount": med.amount,
			"overdose": med.get("overdose", false),
			"dangerous": med.get("dangerous", false),
			"color": med.get("color", "#FFFFFF")
		})
	
	return reagents

func get_limb_data() -> Dictionary:
	"""Get limb data for external systems"""
	return limbs.duplicate(true)

func get_diseases() -> Array:
	"""Get list of diseases"""
	return diseases.duplicate()

# === UI AND AUDIO FUNCTIONS ===
func _update_health_ui():
	"""Update health-related UI elements"""
	if ui_system and ui_system.has_method("update_health_display"):
		ui_system.update_health_display(health, max_health)

func _play_damage_sound(damage_type: int, amount: float):
	"""Play appropriate damage sound"""
	if not audio_system or damage_sound_cooldown > 0:
		return
	
	var sound_name = ""
	var volume = clamp(0.2 + (amount / 50.0), 0.2, 0.8)
	
	match damage_type:
		DamageType.BRUTE:
			sound_name = "hit"
		DamageType.BURN:
			sound_name = "burn"
		DamageType.TOXIN:
			sound_name = "poison"
		DamageType.OXYGEN:
			sound_name = "gasp"
		_:
			sound_name = "damage"
	
	audio_system.play_sound(sound_name, volume)
	damage_sound_cooldown = 0.2  # Prevent sound spam

func _drop_all_items():
	"""Drop all items when dying"""
	if inventory_system and inventory_system.has_method("drop_all_items"):
		inventory_system.drop_all_items()
