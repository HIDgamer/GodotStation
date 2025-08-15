extends Node
class_name HealthSystem

# Configuration
@export_group("Health Settings")
@export var max_health: float = 100.0
@export var health: float = 100.0
@export var godmode: bool = false
@export var no_pain: bool = false
@export var is_synthetic: bool = false
@export var in_stasis: bool = false

@export_group("Damage Settings")
@export var max_damage_threshold: float = 500.0
@export var health_threshold_crit: float = 0
@export var health_threshold_dead: float = -100
@export var health_threshold_gibbed: float = -200
@export var health_threshold_unconscious: float = 20

@export_group("Damage Types")
@export var bruteloss: float = 0.0
@export var fireloss: float = 0.0
@export var toxloss: float = 0.0
@export var oxyloss: float = 0.0
@export var cloneloss: float = 0.0
@export var staminaloss: float = 0.0
@export var brainloss: float = 0.0
@export var max_stamina: float = 100.0

@export_group("Blood System")
@export var blood_type: String = "O+"
@export var blood_volume_normal: float = 560
@export var blood_regen_rate: float = 0.1

@export_group("Body Temperature")
@export var body_temp_normal: float = 310.15
@export var body_temp_cold_damage: float = 280.15
@export var body_temp_heat_damage: float = 343.15
@export var body_temp_critical_low: float = 270.15
@export var body_temp_critical_high: float = 373.15

@export_group("Pain System")
@export var pain_slowdown_threshold: float = 25.0
@export var pain_stun_threshold: float = 60.0
@export var pain_unconscious_threshold: float = 85.0
@export var burn_pain_multiplier: float = 2.0
@export var brute_pain_multiplier: float = 1.0

@export_group("CPR Settings")
@export var cpr_duration: float = 5.0
@export var cpr_cooldown: float = 7.0
@export var cpr_incorrect_damage: float = 10.0
@export var max_death_time: float = 300.0

# Enumerations
enum HealthState { ALIVE, UNCONSCIOUS, CRITICAL, DEAD, GIBBED }
enum DamageType { BRUTE, BURN, TOXIN, OXYGEN, CLONE, STAMINA, BRAIN, CELLULAR, GENETIC, RADIATION }
enum PainLevel { NONE, MILD, MODERATE, SEVERE, EXTREME, UNBEARABLE }
enum BloodStatus { NORMAL, SLIGHTLY_LOW, LOW, CRITICALLY_LOW, FATAL }
enum PulseStatus { NO_PULSE, VERY_WEAK, WEAK, NORMAL, ELEVATED, RAPID, DANGEROUS }
enum TemperatureStatus { HYPOTHERMIC, COLD, NORMAL, WARM, HYPERTHERMIC, CRITICAL }

# Health system signals
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
signal limb_fractured(limb_name)
signal limb_splinted(limb_name)
signal cpr_started(performer)
signal cpr_completed(performer, success)

# State variables
var current_state = HealthState.ALIVE
var previous_state = HealthState.ALIVE
var is_dead: bool = false
var is_unconscious: bool = false

# Vital signs
var blood_volume: float = 0.0
var blood_volume_maximum: float = 0.0
var bleeding_rate: float = 0.0
var pulse: int = 70
var body_temperature: float = 0.0
var breathing_rate: int = 16
var blood_pressure_systolic: int = 120
var blood_pressure_diastolic: int = 80

# System data
var organs: Dictionary = {}
var limbs: Dictionary = {}
var prosthetics: Dictionary = {}
var status_effects: Dictionary = {}

# Pain and consciousness
var pain_level: float = 0.0
var shock_level: float = 0.0
var consciousness_level: float = 100.0

# Armor and resistances
@export var armor: Dictionary = {
	"melee": 0, "bullet": 0, "laser": 0, "energy": 0,
	"bomb": 0, "bio": 0, "rad": 0, "fire": 0, "acid": 0
}

@export var damage_resistances: Dictionary = {
	DamageType.BRUTE: 1.0, DamageType.BURN: 1.0, DamageType.TOXIN: 1.0,
	DamageType.OXYGEN: 1.0, DamageType.CLONE: 1.0, DamageType.BRAIN: 1.0, DamageType.STAMINA: 1.0
}

# Medical data
var death_time: float = 0.0
var revival_count: int = 0
var cause_of_death: String = ""
var medical_notes: Array = []
var diseases: Array = []
var allergies: Array = []
var medications: Array = []

# CPR system
var cpr_performer: Node = null
var cpr_start_time: float = 0.0
var last_cpr_time: float = 0.0
var cpr_in_progress: bool = false
var death_timer_paused: bool = false

# Movement penalties
var movement_speed_penalty: float = 1.0
var item_drop_timer: float = 0.0

# System references
var entity = null
var health_connector = null
var inventory_system = null
var sprite_system = null
var audio_system = null
var ui_system = null
var effect_system = null
var reagent_system = null
var posture_component = null

# Performance tracking
var update_timer: float = 0.0
var ui_update_timer: float = 0.0
var last_health_update: float = 0.0
var damage_sound_cooldown: float = 0.0
var pain_effect_timer: float = 0.0
var recovery_check_timer: float = 0.0

# Multiplayer
var peer_id: int = 1
var is_multiplayer_game: bool = false

# Organ and limb constants
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

const LIMBS = {
	"head": {"vital": true, "max_damage": 100, "dismemberable": false, "can_fracture": false},
	"chest": {"vital": true, "max_damage": 120, "dismemberable": false, "can_fracture": true},
	"groin": {"vital": false, "max_damage": 100, "dismemberable": false, "can_fracture": false},
	"l_arm": {"vital": false, "max_damage": 80, "dismemberable": true, "can_fracture": true},
	"r_arm": {"vital": false, "max_damage": 80, "dismemberable": true, "can_fracture": true},
	"l_leg": {"vital": false, "max_damage": 80, "dismemberable": true, "can_fracture": true},
	"r_leg": {"vital": false, "max_damage": 80, "dismemberable": true, "can_fracture": true},
	"l_hand": {"vital": false, "max_damage": 60, "dismemberable": true, "can_fracture": true},
	"r_hand": {"vital": false, "max_damage": 60, "dismemberable": true, "can_fracture": true},
	"l_foot": {"vital": false, "max_damage": 60, "dismemberable": true, "can_fracture": true},
	"r_foot": {"vital": false, "max_damage": 60, "dismemberable": true, "can_fracture": true}
}

# Fracture constants
const LEG_FRACTURE_SPEED_PENALTY = 0.3
const ARM_FRACTURE_DROP_CHANCE = 0.15
const RIB_FRACTURE_MOVEMENT_DAMAGE = 2.0
const SKULL_FRACTURE_MOVEMENT_DAMAGE = 3.0

func _ready():
	_initialize_health_system()

# Initialization system
func _initialize_health_system():
	entity = get_parent()
	health_connector = entity.get_node_or_null("HealthConnector")
	
	_setup_multiplayer()
	_find_and_connect_systems()
	_initialize_organs()
	_initialize_limbs()
	_initialize_vital_signs()
	_setup_update_timers()
	
	if blood_type == "O+":
		_generate_blood_type()
	
	blood_volume = blood_volume_normal
	blood_volume_maximum = blood_volume_normal
	body_temperature = body_temp_normal
	
	updatehealth()
	print("HealthSystem: Initialized successfully")

func _setup_multiplayer():
	is_multiplayer_game = multiplayer.has_multiplayer_peer()
	
	if entity and entity.has_meta("peer_id"):
		peer_id = entity.get_meta("peer_id")
	elif is_multiplayer_game:
		peer_id = multiplayer.get_remote_sender_id()
		if peer_id == 0:
			peer_id = multiplayer.get_unique_id()
	
	if is_multiplayer_game:
		set_multiplayer_authority(peer_id)

func _find_and_connect_systems():
	if entity:
		inventory_system = entity.get_node_or_null("InventorySystem")
		sprite_system = entity.get_node_or_null("UpdatedHumanSpriteSystem")
		if not sprite_system:
			sprite_system = entity.get_node_or_null("HumanSpriteSystem")
		audio_system = entity.get_node_or_null("AudioSystem")
		ui_system = entity.get_node_or_null("UISystem")
		effect_system = entity.get_node_or_null("Effect")
		reagent_system = entity.get_node_or_null("ReagentSystem")
		posture_component = entity.get_node_or_null("PostureComponent")
	
	_connect_health_connector_signals()

func _connect_health_connector_signals():
	if health_connector:
		health_changed.connect(health_connector._on_health_changed)
		damage_taken.connect(health_connector._on_damage_taken)
		status_effect_added.connect(health_connector._on_status_effect_added)
		status_effect_removed.connect(health_connector._on_status_effect_removed)
		died.connect(health_connector._on_entity_died)
		revived.connect(health_connector._on_entity_revived)
		entered_critical.connect(health_connector._on_entered_critical)
		exited_critical.connect(health_connector._on_exited_critical)
		blood_level_changed.connect(health_connector._on_blood_level_changed)
		cpr_started.connect(health_connector._on_cpr_started)
		cpr_completed.connect(health_connector._on_cpr_completed)

func _initialize_organs():
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
			"can_fracture": limb_data.can_fracture,
			"attached": true,
			"is_bleeding": false,
			"is_bandaged": false,
			"is_splinted": false,
			"is_infected": false,
			"is_fractured": false,
			"fracture_severity": 0,
			"wounds": [],
			"scars": []
		}

func _initialize_vital_signs():
	pulse = 70 + randi() % 20
	breathing_rate = 14 + randi() % 6
	blood_pressure_systolic = 110 + randi() % 20
	blood_pressure_diastolic = 70 + randi() % 20
	body_temperature = body_temp_normal + randf_range(-1.0, 1.0)

func _generate_blood_type():
	var types = ["O+", "O-", "A+", "A-", "B+", "B-", "AB+", "AB-"]
	var probabilities = [38, 7, 34, 6, 9, 2, 3, 1]
	
	var roll = randi() % 100
	var cumulative = 0
	
	for i in range(types.size()):
		cumulative += probabilities[i]
		if roll < cumulative:
			blood_type = types[i]
			break

func _setup_update_timers():
	var main_timer = Timer.new()
	main_timer.wait_time = 1.0
	main_timer.autostart = true
	main_timer.timeout.connect(_on_main_update_tick)
	add_child(main_timer)
	
	var fast_timer = Timer.new()
	fast_timer.wait_time = 0.1
	fast_timer.autostart = true
	fast_timer.timeout.connect(_on_fast_update_tick)
	add_child(fast_timer)

# Main processing loop
func _process(delta):
	if not entity or not _is_authority():
		return
	
	_update_timers(delta)
	_process_status_effects(delta)
	_process_cpr_system(delta)
	_process_death_timer(delta)
	
	if bleeding_rate > 0 and current_state != HealthState.DEAD:
		_process_bleeding(delta)
	
	if update_timer >= 0.5:
		_process_temperature_effects(delta)
	
	_process_organ_effects(delta)
	_process_pain_and_shock(delta)
	_process_fracture_effects(delta)
	
	if pain_effect_timer >= 1.0:
		_process_pain_effects()
		pain_effect_timer = 0.0
	
	if recovery_check_timer >= 2.0:
		_check_recovery_conditions()
		recovery_check_timer = 0.0
	
	if update_timer >= 1.0:
		update_timer = 0.0

func _update_timers(delta: float):
	update_timer += delta
	ui_update_timer += delta
	pain_effect_timer += delta
	recovery_check_timer += delta
	item_drop_timer += delta
	
	if damage_sound_cooldown > 0:
		damage_sound_cooldown -= delta

func _on_main_update_tick():
	if not _is_authority():
		return
	
	if current_state == HealthState.DEAD:
		_process_death_effects()
		return
	
	_process_natural_healing()
	_update_vital_signs()
	_process_organ_maintenance()
	_process_reagent_metabolism()
	
	if ui_update_timer >= 1.0:
		_update_health_ui()
		ui_update_timer = 0.0

func _on_fast_update_tick():
	if not _is_authority():
		return
	
	if current_state == HealthState.CRITICAL:
		_process_critical_condition()
	
	if _is_in_cardiac_arrest():
		_process_cardiac_arrest()

# Damage system
func apply_damage(amount: float, damage_type: int, penetration: float = 0, zone: String = "", source = null) -> float:
	if not _is_authority():
		return 0.0
	
	if godmode or amount <= 0:
		return 0.0
	
	if current_state == HealthState.DEAD:
		var total_damage = get_total_damage()
		if total_damage >= max_damage_threshold:
			return 0.0
	
	var actual_damage = _calculate_final_damage(amount, damage_type, penetration, zone)
	
	if actual_damage <= 0:
		return 0.0
	
	var total_damage = get_total_damage()
	if total_damage + actual_damage > max_damage_threshold:
		actual_damage = max_damage_threshold - total_damage
		if actual_damage <= 0:
			return 0.0
	
	if zone != "" and limbs.has(zone):
		_apply_limb_damage(zone, actual_damage, damage_type)
	else:
		_apply_general_damage(actual_damage, damage_type)
	
	_process_damage_effects(actual_damage, damage_type, zone, source)
	updatehealth()
	
	emit_signal("damage_taken", actual_damage, damage_type, zone, source)
	_play_damage_sound(damage_type, actual_damage)
	_sync_damage_taken(actual_damage, damage_type, zone, source)
	
	return actual_damage

func _calculate_final_damage(amount: float, damage_type: int, penetration: float, zone: String) -> float:
	var modified_damage = amount
	
	if damage_resistances.has(damage_type):
		modified_damage *= damage_resistances[damage_type]
	
	var armor_reduction = _calculate_armor_reduction(damage_type, penetration)
	modified_damage *= (1.0 - armor_reduction)
	
	if zone != "":
		modified_damage *= _get_zone_damage_multiplier(zone)
	
	if is_synthetic:
		match damage_type:
			DamageType.TOXIN:
				modified_damage *= 0.5
			DamageType.OXYGEN:
				modified_damage = 0
	
	return max(0, modified_damage)

func _calculate_armor_reduction(damage_type: int, penetration: float) -> float:
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
	
	return min(0.9, effective_armor * 0.01)

func _get_zone_damage_multiplier(zone: String) -> float:
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
			_apply_general_damage(amount, damage_type)
			return
	
	_update_limb_status(zone)
	_sync_limb_state(zone)
	
	var general_damage = applied_damage * 0.4
	if damage_type == DamageType.BRUTE:
		adjustBruteLoss(general_damage)
	else:
		adjustFireLoss(general_damage)
	
	if applied_damage > 15 and not limb.is_bleeding:
		_start_limb_bleeding(zone, applied_damage)
	
	if applied_damage > 25 and limb.can_fracture and not limb.is_fractured:
		_check_fracture(zone, applied_damage, damage_type)
	
	if limb.dismemberable:
		_check_dismemberment(zone, applied_damage, damage_type)
	
	emit_signal("limb_damaged", zone, applied_damage, damage_type)

# Damage adjustment functions
func adjustBruteLoss(amount: float, update_health: bool = true):
	if not _is_authority():
		return
	
	if godmode and amount > 0:
		return
	
	bruteloss = max(0, bruteloss + amount)
	
	if update_health:
		updatehealth()

func adjustFireLoss(amount: float, update_health: bool = true):
	if not _is_authority():
		return
	
	if godmode and amount > 0:
		return
	
	fireloss = max(0, fireloss + amount)
	
	if update_health:
		updatehealth()

func adjustToxLoss(amount: float, update_health: bool = true):
	if not _is_authority():
		return
	
	if godmode and amount > 0:
		return
	
	toxloss = max(0, toxloss + amount)
	
	if update_health:
		updatehealth()

func adjustOxyLoss(amount: float, update_health: bool = true):
	if not _is_authority():
		return
	
	if godmode and amount > 0:
		return
	
	var multiplier = 1.0
	if organs.has("lungs") and organs["lungs"].is_failing:
		multiplier += 0.5
	if organs.has("heart") and organs["heart"].is_failing:
		multiplier += 0.3
	
	oxyloss = max(0, oxyloss + (amount * multiplier))
	
	if update_health:
		updatehealth()

func adjustCloneLoss(amount: float, update_health: bool = true):
	if not _is_authority():
		return
	
	if godmode and amount > 0:
		return
	
	cloneloss = max(0, cloneloss + amount)
	
	if update_health:
		updatehealth()

func adjustBrainLoss(amount: float, update_health: bool = true):
	if not _is_authority():
		return
	
	if godmode and amount > 0:
		return
	
	brainloss = max(0, brainloss + amount)
	
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
	if not _is_authority():
		return
	
	if godmode and amount > 0:
		return
	
	staminaloss = clamp(staminaloss + amount, 0, max_stamina)
	
	if staminaloss >= max_stamina * 0.9:
		add_status_effect("exhausted", 5.0, 2.0)
	
	if update_health:
		updatehealth()

func adjust_blood_volume(amount: float):
	if not _is_authority():
		return
	
	var old_volume = blood_volume
	blood_volume = clamp(blood_volume + amount, 0, blood_volume_maximum)
	
	var blood_percent = blood_volume / blood_volume_maximum
	var status = _get_blood_status()
	
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
	
	emit_signal("blood_level_changed", blood_volume, blood_volume_maximum, blood_percent, status)
	_sync_blood_volume()

# Health state management
func updatehealth():
	if not _is_authority():
		return
	
	if godmode:
		health = max_health
		return
	
	var old_health = health
	var old_state = current_state
	
	health = max_health - bruteloss - fireloss - toxloss - oxyloss - cloneloss
	
	_check_health_state_transitions()
	_update_consciousness()
	
	if abs(old_health - health) > 1.0 or old_state != current_state:
		_update_health_ui()
		_sync_health_state()

func _check_health_state_transitions():
	var new_state = current_state
	
	if health <= health_threshold_dead and current_state != HealthState.DEAD:
		die("damage")
		return
	
	if health <= health_threshold_crit and current_state == HealthState.ALIVE:
		new_state = HealthState.CRITICAL
	elif health > health_threshold_crit and current_state == HealthState.CRITICAL:
		new_state = HealthState.ALIVE
	
	if health <= health_threshold_unconscious and current_state == HealthState.ALIVE:
		new_state = HealthState.UNCONSCIOUS
	elif consciousness_level <= 0 and current_state != HealthState.DEAD:
		new_state = HealthState.UNCONSCIOUS
	elif consciousness_level > 30 and current_state == HealthState.UNCONSCIOUS:
		new_state = HealthState.ALIVE
	
	if new_state != current_state:
		_change_health_state(new_state)

func _change_health_state(new_state: int):
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
			pass

func _update_consciousness():
	if current_state == HealthState.DEAD:
		consciousness_level = 0
		return
	
	var target_consciousness = 100.0
	
	var health_factor = health / max_health
	target_consciousness *= max(0.1, health_factor)
	
	var blood_factor = blood_volume / blood_volume_maximum
	target_consciousness *= max(0.1, blood_factor)
	
	if brainloss > 0:
		target_consciousness *= max(0.1, 1.0 - (brainloss / 100.0))
	
	if oxyloss > 30:
		target_consciousness *= max(0.1, 1.0 - ((oxyloss - 30) / 70.0))
	
	consciousness_level = lerp(consciousness_level, target_consciousness, 0.1)

# Status effect system
func add_status_effect(effect_name: String, duration: float, intensity: float = 1.0):
	if not _is_authority():
		return
	
	if godmode and effect_name in ["poisoned", "burning", "bleeding"]:
		return
	
	var was_new = not status_effects.has(effect_name)
	var old_duration = 0.0
	
	if not was_new:
		old_duration = status_effects[effect_name].duration
	
	status_effects[effect_name] = {
		"duration": max(duration, old_duration),
		"intensity": max(intensity, status_effects.get(effect_name, {}).get("intensity", 0)),
		"start_time": Time.get_ticks_msec() / 1000.0
	}
	
	_apply_status_effect_start(effect_name, intensity)
	
	if was_new:
		emit_signal("status_effect_added", effect_name, duration, intensity)
		_sync_status_effect_added(effect_name, duration, intensity)

func remove_status_effect(effect_name: String):
	if not _is_authority():
		return
	
	if not status_effects.has(effect_name):
		return
	
	_apply_status_effect_end(effect_name)
	status_effects.erase(effect_name)
	emit_signal("status_effect_removed", effect_name)
	_sync_status_effect_removed(effect_name)

func _apply_status_effect_start(effect_name: String, intensity: float):
	match effect_name:
		"bleeding":
			set_bleeding_rate(max(bleeding_rate, intensity))
		"unconscious":
			consciousness_level = 0
			if posture_component:
				posture_component.force_lie_down()
		"confused":
			if entity and entity.has_method("add_status_effect"):
				entity.add_status_effect(effect_name, 0, intensity)
		"stunned":
			if entity and entity.has_method("stun"):
				entity.stun(intensity)

func _apply_status_effect_end(effect_name: String):
	match effect_name:
		"bleeding":
			set_bleeding_rate(0)
		"unconscious":
			if current_state == HealthState.ALIVE:
				consciousness_level = 50.0
		"confused":
			if entity and entity.has_method("remove_status_effect"):
				entity.remove_status_effect(effect_name)

func _process_status_effects(delta):
	var effects_to_remove = []
	
	for effect_name in status_effects:
		var effect = status_effects[effect_name]
		var old_duration = effect.duration
		effect.duration -= delta
		
		_process_individual_effect(effect_name, effect, delta)
		
		if abs(old_duration - effect.duration) > 0.1:
			emit_signal("status_effect_updated", effect_name, effect.duration)
		
		if effect.duration <= 0:
			effects_to_remove.append(effect_name)
	
	for effect_name in effects_to_remove:
		remove_status_effect(effect_name)

func _process_individual_effect(effect_name: String, effect: Dictionary, delta: float):
	match effect_name:
		"bleeding":
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
			body_temperature = max(body_temperature - delta * effect.intensity, body_temp_critical_low)
		"hyperthermic":
			body_temperature = min(body_temperature + delta * effect.intensity, body_temp_critical_high)
		"confused":
			pass
		"stunned":
			pass
		"unconscious":
			consciousness_level = max(0, consciousness_level - delta * 10)

# Bleeding system
func _process_bleeding(delta):
	if bleeding_rate <= 0:
		return
	
	var blood_loss = bleeding_rate * delta
	adjust_blood_volume(-blood_loss)
	
	if not status_effects.has("anticoagulant"):
		bleeding_rate = max(0, bleeding_rate - delta * 0.1)
		
		if bleeding_rate <= 0.1:
			set_bleeding_rate(0)

func set_bleeding_rate(rate: float):
	if not _is_authority():
		return
	
	bleeding_rate = max(0, rate)
	
	if bleeding_rate > 0:
		if not status_effects.has("bleeding"):
			add_status_effect("bleeding", 60.0, bleeding_rate)
		
		for limb_name in limbs:
			var limb = limbs[limb_name]
			if limb.is_bleeding and bleeding_rate == 0:
				limb.is_bleeding = false
	else:
		if status_effects.has("bleeding"):
			status_effects.erase("bleeding")
			emit_signal("status_effect_removed", "bleeding")
	
	_sync_bleeding_state()

func _start_limb_bleeding(limb_name: String, damage_amount: float):
	if not limbs.has(limb_name):
		return
	
	var limb = limbs[limb_name]
	limb.is_bleeding = true
	
	var bleed_rate = damage_amount * 0.1
	set_bleeding_rate(bleeding_rate + bleed_rate)
	
	add_status_effect("bleeding", 60.0, bleed_rate)

# Organ system
func apply_organ_damage(organ_name: String, amount: float) -> float:
	if not _is_authority():
		return 0.0
	
	if not organs.has(organ_name) or amount <= 0:
		return 0.0
	
	var organ = organs[organ_name]
	var old_damage = organ.damage
	
	organ.damage = min(organ.max_damage, organ.damage + amount)
	var actual_damage = organ.damage - old_damage
	
	_update_organ_status(organ_name)
	_sync_organ_state(organ_name)
	
	if organ.is_vital and organ.is_failing and current_state != HealthState.DEAD:
		die(organ_name + " failure")
	
	emit_signal("organ_damaged", organ_name, actual_damage, organ.damage)
	
	return actual_damage

func heal_organ_damage(organ_name: String, amount: float) -> float:
	if not _is_authority():
		return 0.0
	
	if not organs.has(organ_name) or amount <= 0:
		return 0.0
	
	var organ = organs[organ_name]
	var old_damage = organ.damage
	
	organ.damage = max(0, organ.damage - amount)
	var healed_amount = old_damage - organ.damage
	
	_update_organ_status(organ_name)
	_sync_organ_state(organ_name)
	
	emit_signal("organ_healed", organ_name, healed_amount, organ.damage)
	
	return healed_amount

func _update_organ_status(organ_name: String):
	var organ = organs[organ_name]
	
	var damage_percent = organ.damage / organ.max_damage
	
	organ.is_damaged = damage_percent > 0.3
	organ.is_failing = damage_percent > 0.8
	organ.efficiency = max(0.1, 1.0 - damage_percent)

func _process_organ_effects(delta):
	for organ_name in organs:
		var organ = organs[organ_name]
		
		if current_state == HealthState.DEAD:
			continue
			
		if organ.is_failing:
			_process_failing_organ(organ_name, organ, delta)
		elif organ.is_damaged:
			_process_damaged_organ(organ_name, organ, delta)

func _process_failing_organ(organ_name: String, organ: Dictionary, delta: float):
	match organ_name:
		"heart":
			if randf() < 0.1:
				_trigger_cardiac_event()
			pulse = max(0, pulse - delta * 10)
		"lungs":
			adjustOxyLoss(delta * 5.0)
			breathing_rate = max(0, breathing_rate - delta * 2)
		"liver":
			adjustToxLoss(delta * 2.0)
		"kidneys":
			adjustToxLoss(delta * 1.0)
		"brain":
			adjustBrainLoss(delta * 1.0)
			consciousness_level = max(0, consciousness_level - delta * 5)
			if consciousness_level <= 0 and current_state != HealthState.DEAD:
				die("brain death")

func _process_damaged_organ(organ_name: String, organ: Dictionary, delta: float):
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

func _process_organ_maintenance():
	for organ_name in organs:
		var organ = organs[organ_name]
		
		if organ.damage > organ.max_damage * 0.8:
			organ.is_failing = true
		elif organ.damage > organ.max_damage * 0.3:
			organ.is_damaged = true
		else:
			organ.is_damaged = false
			organ.is_failing = false

# Limb and fracture system
func heal_limb_damage(limb_name: String, brute_amount: float = 0, burn_amount: float = 0) -> float:
	if not _is_authority():
		return 0.0
	
	if not limbs.has(limb_name):
		return 0.0
	
	var limb = limbs[limb_name]
	
	if limb.is_fractured:
		return 0.0
	
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
	
	_update_limb_status(limb_name)
	_sync_limb_state(limb_name)
	
	return healed_total

func _update_limb_status(limb_name: String):
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
	
	if sprite_system and sprite_system.has_method("update_limb_damage"):
		sprite_system.update_limb_damage(limb_name, limb.status, limb.brute_damage, limb.burn_damage)

func _check_fracture(limb_name: String, damage_amount: float, damage_type: int):
	var limb = limbs[limb_name]
	var fracture_chance = 0.0
	
	if damage_amount > 30:
		fracture_chance = 0.3
	elif damage_amount > 40:
		fracture_chance = 0.5
	elif damage_amount > 50:
		fracture_chance = 0.7
	
	if randf() < fracture_chance:
		_fracture_limb(limb_name, 1)

func _fracture_limb(limb_name: String, severity: int):
	if not limbs.has(limb_name):
		return
	
	var limb = limbs[limb_name]
	if limb.is_fractured:
		limb.fracture_severity = min(3, limb.fracture_severity + severity)
	else:
		limb.is_fractured = true
		limb.fracture_severity = severity
	
	emit_signal("limb_fractured", limb_name)
	_sync_limb_fracture(limb_name)
	
	if audio_system:
		audio_system.play_sound("bone_break", 0.6)

func splint_limb(limb_name: String) -> bool:
	if not _is_authority():
		return false
	
	if not limbs.has(limb_name):
		return false
	
	var limb = limbs[limb_name]
	if not limb.is_fractured:
		return false
	
	limb.is_splinted = true
	emit_signal("limb_splinted", limb_name)
	_sync_limb_splint(limb_name)
	
	return true

func reduce_limb_pain(limb_name: String, amount: float):
	if not limbs.has(limb_name):
		return
	
	var limb = limbs[limb_name]
	if limb.is_fractured and limb.is_splinted:
		pain_level = max(0, pain_level - amount)

func _check_dismemberment(limb_name: String, damage_amount: float, damage_type: int):
	var limb = limbs[limb_name]
	var total_damage = limb.brute_damage + limb.burn_damage
	
	if damage_amount > 60 and randf() < 0.4:
		_dismember_limb(limb_name)
		return
	
	if total_damage > limb.max_damage * 0.9:
		var chance = (total_damage - limb.max_damage * 0.9) / (limb.max_damage * 0.1)
		if randf() < chance * 0.3:
			_dismember_limb(limb_name)

func _dismember_limb(limb_name: String):
	if not limbs.has(limb_name):
		return
	
	var limb = limbs[limb_name]
	limb.attached = false
	limb.status = "missing"
	
	adjustBruteLoss(25.0)
	set_bleeding_rate(bleeding_rate + 8.0)
	add_status_effect("bleeding", 120.0, 8.0)
	
	if not no_pain:
		pain_level = min(100, pain_level + 40)
		shock_level = min(100, shock_level + 30)
	
	if sprite_system and sprite_system.has_method("update_dismemberment"):
		sprite_system.update_dismemberment(limb_name)
	
	if audio_system:
		audio_system.play_sound("dismember", 0.8)
	
	emit_signal("limb_damaged", limb_name, 100.0, DamageType.BRUTE)
	_sync_limb_state(limb_name)

# Pain and shock system
func _process_pain_and_shock(delta):
	var brute_pain = bruteloss * brute_pain_multiplier * 0.5
	var burn_pain = fireloss * burn_pain_multiplier * 0.5
	var damage_pain = brute_pain + burn_pain
	
	var limb_pain = 0.0
	
	for limb_name in limbs:
		var limb = limbs[limb_name]
		var limb_brute_pain = limb.brute_damage * brute_pain_multiplier * 0.3
		var limb_burn_pain = limb.burn_damage * burn_pain_multiplier * 0.3
		
		if limb.is_fractured and not limb.is_splinted:
			limb_burn_pain += limb.fracture_severity * 5.0
		
		limb_pain += limb_brute_pain + limb_burn_pain
	
	var target_pain = damage_pain + limb_pain
	
	if no_pain:
		target_pain = 0
	
	pain_level = lerp(pain_level, target_pain, delta * 2.0)
	
	if pain_level > 30:
		shock_level = min(100, shock_level + delta * (pain_level - 30))
	else:
		shock_level = max(0, shock_level - delta * 10)
	
	if shock_level > 50:
		if randf() < 0.1:
			add_status_effect("stunned", 2.0, shock_level / 50)
	
	if shock_level > 80:
		adjustOxyLoss(delta * 2.0)
		if randf() < 0.05:
			_trigger_cardiac_event()
	
	var pain_status = _get_pain_status()
	emit_signal("pain_level_changed", pain_level, pain_status)

func _process_fracture_effects(delta):
	_calculate_movement_penalties()
	_process_item_dropping(delta)
	_process_fracture_movement_damage(delta)

func _calculate_movement_penalties():
	movement_speed_penalty = 1.0
	
	var leg_fractures = 0
	for limb_name in ["l_leg", "r_leg"]:
		if limbs.has(limb_name):
			var limb = limbs[limb_name]
			if limb.is_fractured and not limb.is_splinted:
				leg_fractures += 1
	
	if leg_fractures > 0:
		movement_speed_penalty = 1.0 - (leg_fractures * LEG_FRACTURE_SPEED_PENALTY)
		movement_speed_penalty = max(0.2, movement_speed_penalty)
	
	if entity and entity.has_method("set_movement_speed_modifier"):
		entity.set_movement_speed_modifier("fracture_penalty", movement_speed_penalty)

func _process_item_dropping(delta: float):
	if item_drop_timer <= 0:
		return
	
	var has_arm_fracture = false
	for limb_name in ["l_arm", "r_arm", "l_hand", "r_hand"]:
		if limbs.has(limb_name):
			var limb = limbs[limb_name]
			if limb.is_fractured and not limb.is_splinted:
				has_arm_fracture = true
				break
	
	if has_arm_fracture and randf() < ARM_FRACTURE_DROP_CHANCE * delta:
		_force_item_drop()
	
	item_drop_timer = 0.0

func _force_item_drop():
	if inventory_system and inventory_system.has_method("drop_active_item"):
		var dropped_item = inventory_system.drop_active_item()
		if dropped_item:
			if entity and entity.has_method("display_message"):
				entity.display_message("Pain causes you to drop " + dropped_item.name + "!")

func _process_fracture_movement_damage(delta: float):
	if not entity or not entity.has_method("is_moving"):
		return
	
	if not entity.is_moving():
		return
	
	var has_rib_fracture = false
	var has_skull_fracture = false
	
	if limbs.has("chest"):
		var chest = limbs["chest"]
		if chest.is_fractured and not chest.is_splinted:
			has_rib_fracture = true
	
	if limbs.has("head"):
		var head = limbs["head"]
		if head.is_fractured and not head.is_splinted:
			has_skull_fracture = true
	
	if has_rib_fracture:
		var damage_types = ["heart", "lungs"]
		for damage_type in damage_types:
			if randf() < 0.05 and organs.has(damage_type):
				apply_organ_damage(damage_type, RIB_FRACTURE_MOVEMENT_DAMAGE * delta)
	
	if has_skull_fracture:
		var damage_types = ["brain", "eyes"]
		for damage_type in damage_types:
			if randf() < 0.05 and organs.has(damage_type):
				apply_organ_damage(damage_type, SKULL_FRACTURE_MOVEMENT_DAMAGE * delta)

func _process_pain_effects():
	if no_pain or pain_level <= 0:
		return
	
	item_drop_timer = 1.0
	
	if pain_level >= pain_unconscious_threshold:
		if randf() < 0.15:
			add_status_effect("unconscious", 10.0, pain_level / 100)
			_force_lie_down_from_pain()
	elif pain_level >= pain_stun_threshold:
		if randf() < 0.1:
			add_status_effect("stunned", 3.0, pain_level / 100)
			_force_lie_down_from_pain()
	elif pain_level >= pain_slowdown_threshold:
		_apply_pain_slowdown()

func _apply_pain_slowdown():
	if entity and entity.has_method("add_movement_modifier"):
		var slowdown_factor = 1.0 - (pain_level / 100.0) * 0.5
		slowdown_factor = max(0.3, slowdown_factor)
		entity.add_movement_modifier("pain_slowdown", slowdown_factor)

func _force_lie_down_from_pain():
	if posture_component and not posture_component.is_lying:
		posture_component.force_lie_down()

# Temperature effects
func _process_temperature_effects(delta: float):
	var normal_temp = body_temp_normal
	var temp_diff = body_temperature - normal_temp
	var regulation_rate = 0.5 * delta
	
	if abs(temp_diff) > 1.0:
		body_temperature = lerp(body_temperature, normal_temp, regulation_rate)
	
	if body_temperature <= body_temp_cold_damage:
		var damage = (body_temp_cold_damage - body_temperature) * delta * 0.1
		apply_damage(damage, DamageType.BURN, 0, "chest")
		if not status_effects.has("hypothermic"):
			add_status_effect("hypothermic", 10.0, abs(temp_diff))
	elif body_temperature >= body_temp_heat_damage:
		var damage = (body_temperature - body_temp_heat_damage) * delta * 0.1
		apply_damage(damage, DamageType.BURN, 0, "chest")
		if not status_effects.has("hyperthermic"):
			add_status_effect("hyperthermic", 10.0, temp_diff)
	
	var temp_status = _get_temperature_status()
	emit_signal("temperature_changed", body_temperature, temp_status)

# Vital signs and recovery
func _update_vital_signs():
	var base_pulse = 70
	var health_factor = 1.0 - (health / max_health)
	var blood_factor = 1.0 - (blood_volume / blood_volume_maximum)
	
	pulse = int(base_pulse + (health_factor * 30) + (blood_factor * 40))
	pulse = clamp(pulse, 0, 200)
	
	var base_breathing = 16
	breathing_rate = int(base_breathing + (oxyloss * 0.2))
	breathing_rate = clamp(breathing_rate, 0, 40)
	
	blood_pressure_systolic = int(120 - (blood_volume / blood_volume_maximum) * 40)
	blood_pressure_diastolic = int(80 - (blood_volume / blood_volume_maximum) * 20)
	
	var pulse_status = _get_pulse_status()
	emit_signal("pulse_changed", pulse, pulse_status)
	
	var breathing_status = _get_breathing_status()
	emit_signal("breathing_status_changed", breathing_rate, breathing_status)

func _process_natural_healing():
	if current_state != HealthState.ALIVE:
		return
	
	if bruteloss > 0 and bruteloss < 20:
		adjustBruteLoss(-0.1)
	
	if fireloss > 0 and fireloss < 20:
		adjustFireLoss(-0.1)
	
	if blood_volume < blood_volume_maximum:
		adjust_blood_volume(blood_regen_rate)
	
	if staminaloss > 0:
		var regen_rate = 2.0
		if posture_component and posture_component.is_lying:
			regen_rate *= 2.0
		adjustStaminaLoss(-regen_rate)

func _check_recovery_conditions():
	if current_state == HealthState.UNCONSCIOUS or status_effects.has("stunned"):
		if _can_recover():
			_attempt_recovery()

func _can_recover() -> bool:
	if current_state == HealthState.DEAD:
		return false
	
	if consciousness_level < 30:
		return false
	
	if status_effects.has("stunned") and status_effects["stunned"].duration > 0:
		return false
	
	if pain_level >= pain_unconscious_threshold:
		return false
	
	return true

func _attempt_recovery():
	if status_effects.has("unconscious"):
		remove_status_effect("unconscious")
	
	if status_effects.has("stunned"):
		remove_status_effect("stunned")
	
	if posture_component and posture_component.is_lying and not posture_component.is_character_lying():
		if randf() < 0.7:
			posture_component.get_up()

func _process_critical_condition():
	if randf() < 0.1:
		adjustOxyLoss(0.5)
	
	if randf() < 0.05:
		_trigger_cardiac_event()

func _process_cardiac_arrest():
	pulse = 0
	adjustOxyLoss(2.0)
	consciousness_level = max(0, consciousness_level - 5.0)

func _process_death_effects():
	pass

func _process_reagent_metabolism():
	if reagent_system and reagent_system.has_method("_process_metabolism"):
		reagent_system._process_metabolism(1.0)

# Death and revival system
func die(cause: String = "unknown"):
	if not _is_authority():
		return
	
	if current_state == HealthState.DEAD or godmode:
		return
	
	print("HealthSystem: Entity died. Cause: " + cause)
	
	previous_state = current_state
	current_state = HealthState.DEAD
	is_dead = true
	cause_of_death = cause
	death_time = 0.0
	death_timer_paused = false
	
	pulse = 0
	breathing_rate = 0
	consciousness_level = 0
	
	add_status_effect("unconscious", 999999)
	
	if posture_component:
		posture_component.force_lie_down()
	
	_drop_all_items()
	
	if sprite_system and sprite_system.has_method("update_death_state"):
		sprite_system.update_death_state(true)
	
	if audio_system:
		audio_system.play_sound("death", 0.8)
	
	emit_signal("died", cause_of_death, death_time)
	emit_signal("consciousness_changed", false, "death")
	_sync_death_state()
	
	_update_health_ui()

func revive(method: String = "unknown") -> bool:
	if not _is_authority():
		return false
	
	if current_state != HealthState.DEAD:
		return false
	
	if death_time > max_death_time and method != "admin":
		return false
	
	revival_count += 1
	
	match method:
		"admin":
			full_heal(true)
		"defibrillation":
			_partial_revival_heal()
		"advanced_medical":
			_advanced_revival_heal()
		_:
			_basic_revival_heal()
	
	current_state = HealthState.CRITICAL
	is_dead = false
	death_time = 0.0
	cause_of_death = ""
	death_timer_paused = false
	
	pulse = 40
	breathing_rate = 10
	consciousness_level = 20
	
	remove_status_effect("unconscious")
	
	if sprite_system and sprite_system.has_method("update_death_state"):
		sprite_system.update_death_state(false)
	
	if audio_system:
		audio_system.play_sound("revive", 0.6)
	
	updatehealth()
	
	emit_signal("revived", method)
	emit_signal("consciousness_changed", true, "revived")
	_sync_revival(method)
	
	print("HealthSystem: Entity revived via " + method)
	
	return true

func _partial_revival_heal():
	oxyloss = max(0, oxyloss - 40)
	bruteloss = max(0, bruteloss - 20)
	fireloss = max(0, fireloss - 20)
	blood_volume = max(blood_volume, 336)

func _advanced_revival_heal():
	oxyloss = 0
	bruteloss = max(0, bruteloss - 40)
	fireloss = max(0, fireloss - 40)
	toxloss = max(0, toxloss - 30)
	blood_volume = max(blood_volume, 475)

func _basic_revival_heal():
	oxyloss = max(0, oxyloss - 30)
	bruteloss = max(0, bruteloss - 10)
	blood_volume = max(blood_volume, 224)

func _process_cpr_system(delta):
	if cpr_in_progress:
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time >= cpr_start_time + cpr_duration:
			_complete_cpr()

func _process_death_timer(delta):
	if current_state == HealthState.DEAD and not death_timer_paused:
		death_time += delta
		
		if death_time >= max_death_time:
			_handle_permanent_death()

func _handle_permanent_death():
	current_state = HealthState.GIBBED
	if entity and entity.has_method("display_message"):
		entity.display_message("The body begins to decay beyond revival...")

# CPR system
func start_cpr(performer: Node) -> bool:
	if not _is_authority():
		return false
	
	if current_state != HealthState.DEAD:
		return false
	
	if not performer:
		return false
	
	if organs.has("lungs") and organs["lungs"].is_failing:
		if performer.has_method("display_message"):
			performer.display_message("CPR is not possible - the patient's lungs have failed!")
		return false
	
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time < last_cpr_time + cpr_cooldown:
		var remaining_time = (last_cpr_time + cpr_cooldown) - current_time
		if performer.has_method("display_message"):
			performer.display_message("You must wait " + str(int(remaining_time)) + " more seconds to perform effective CPR!")
		
		apply_damage(cpr_incorrect_damage, DamageType.BRUTE)
		death_time += cpr_incorrect_damage * 0.5
		return false
	
	cpr_performer = performer
	cpr_in_progress = true
	cpr_start_time = current_time
	death_timer_paused = true
	
	emit_signal("cpr_started", performer)
	_sync_cpr_state(true, performer)
	
	if performer.has_method("display_message"):
		performer.display_message("You begin performing CPR...")
	
	return true

func _complete_cpr():
	if not cpr_performer or not cpr_in_progress:
		return
	
	cpr_in_progress = false
	death_timer_paused = false
	last_cpr_time = Time.get_ticks_msec() / 1000.0
	
	adjustOxyLoss(-15.0)
	
	var success = oxyloss < 50.0
	
	emit_signal("cpr_completed", cpr_performer, success)
	_sync_cpr_state(false, cpr_performer, success)
	
	if cpr_performer.has_method("display_message"):
		if success:
			cpr_performer.display_message("CPR completed successfully - the patient's condition improves!")
		else:
			cpr_performer.display_message("CPR completed, but the patient needs more help...")
	
	cpr_performer = null

# Cardiac events
func _is_in_cardiac_arrest() -> bool:
	return pulse == 0 and current_state != HealthState.DEAD

func _trigger_cardiac_event():
	pulse = 0
	add_status_effect("cardiac_arrest", 60.0, 1.0)
	
	if audio_system:
		audio_system.play_sound("heart_stop", 0.6)

func apply_cpr(effectiveness: float = 1.0) -> bool:
	if current_state == HealthState.DEAD:
		return false
	
	adjustOxyLoss(-3.0 * effectiveness)
	
	if _is_in_cardiac_arrest():
		if randf() < 0.15 * effectiveness:
			pulse = 40
			remove_status_effect("cardiac_arrest")
			return true
	
	return false

func apply_defibrillation(power: float = 1.0) -> bool:
	if not _is_authority():
		return false
	
	if current_state == HealthState.DEAD and death_time > 300:
		return false
	
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

# Healing and recovery
func full_heal(admin_heal: bool = false):
	if not _is_authority():
		return
	
	bruteloss = 0.0
	fireloss = 0.0
	toxloss = 0.0
	oxyloss = 0.0
	cloneloss = 0.0
	brainloss = 0.0
	staminaloss = 0.0
	
	blood_volume = blood_volume_maximum
	pulse = 70
	breathing_rate = 16
	body_temperature = body_temp_normal
	consciousness_level = 100.0
	pain_level = 0.0
	shock_level = 0.0
	
	var effects_to_remove = status_effects.keys()
	for effect in effects_to_remove:
		remove_status_effect(effect)
	
	for organ_name in organs:
		organs[organ_name].damage = 0.0
		organs[organ_name].is_damaged = false
		organs[organ_name].is_failing = false
		organs[organ_name].efficiency = 1.0
	
	for limb_name in limbs:
		limbs[limb_name].brute_damage = 0.0
		limbs[limb_name].burn_damage = 0.0
		limbs[limb_name].status = "healthy"
		limbs[limb_name].is_bleeding = false
		limbs[limb_name].attached = true
		limbs[limb_name].is_fractured = false
		limbs[limb_name].is_splinted = false
		limbs[limb_name].fracture_severity = 0
		_update_limb_status(limb_name)
	
	if current_state == HealthState.DEAD and admin_heal:
		current_state = HealthState.ALIVE
		is_dead = false
		death_time = 0.0
		cause_of_death = ""
		death_timer_paused = false
	
	updatehealth()
	
	if audio_system:
		audio_system.play_sound("heal", 0.5)

func toggle_godmode(enabled: bool = false) -> bool:
	if not _is_authority():
		return godmode
	
	if enabled != null:
		godmode = enabled
	else:
		godmode = not godmode
	
	if godmode:
		full_heal(true)
	
	return godmode

# Status getters
func get_health_percent() -> float:
	return (health / max_health) * 100.0

func get_total_damage() -> float:
	return bruteloss + fireloss + toxloss + oxyloss + cloneloss + brainloss

func is_bleeding() -> bool:
	return bleeding_rate > 0

func get_pulse() -> int:
	return pulse

func get_body_temperature() -> float:
	return body_temperature - 273.15

func get_blood_pressure() -> String:
	return str(blood_pressure_systolic) + "/" + str(blood_pressure_diastolic)

func get_respiratory_rate() -> int:
	return breathing_rate

func get_movement_speed_modifier() -> float:
	return movement_speed_penalty

func is_cpr_in_progress() -> bool:
	return cpr_in_progress

func get_death_time_remaining() -> float:
	if current_state != HealthState.DEAD:
		return 0.0
	return max(0.0, max_death_time - death_time)

# Status assessment functions
func _get_blood_status() -> int:
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

# Utility functions
func _drop_all_items():
	if inventory_system and inventory_system.has_method("drop_all_items"):
		inventory_system.drop_all_items()

func _process_damage_effects(amount: float, damage_type: int, zone: String, source):
	if damage_type == DamageType.BRUTE and amount > 10:
		_create_blood_splatter(amount)
	
	if damage_type in [DamageType.BRUTE, DamageType.BURN] and not no_pain:
		var pain_multiplier = burn_pain_multiplier if damage_type == DamageType.BURN else brute_pain_multiplier
		var pain_amount = amount * 0.8 * pain_multiplier
		pain_level = min(100, pain_level + pain_amount)
	
	if amount > 50:
		_check_massive_damage_effects(amount, damage_type)

func _check_massive_damage_effects(amount: float, damage_type: int):
	shock_level = min(100, shock_level + amount)
	
	if amount > 60 and randf() < 0.3:
		add_status_effect("unconscious", 5.0, amount / 20)
	
	if amount > 80 and randf() < 0.2:
		_trigger_cardiac_event()

func _create_blood_splatter(damage_amount: float):
	if blood_volume <= 0:
		return
	
	var splatter_chance = min(80, damage_amount * 2)
	
	if randf() * 100 < splatter_chance:
		if sprite_system and sprite_system.has_method("create_blood_splatter"):
			sprite_system.create_blood_splatter()
		
		adjust_blood_volume(-0.5)

func _update_health_ui():
	if ui_system and ui_system.has_method("update_health_display"):
		ui_system.update_health_display(health, max_health)

func _play_damage_sound(damage_type: int, amount: float):
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
	damage_sound_cooldown = 0.2

# Authority check for multiplayer
func _is_authority() -> bool:
	if not is_multiplayer_game:
		return true
	return is_multiplayer_authority()

# Network synchronization RPCs (simplified)
@rpc("any_peer", "call_local", "reliable")
func _sync_health_state():
	pass

@rpc("any_peer", "call_local", "reliable")
func _sync_status_effect_added(effect_name: String, duration: float, intensity: float):
	pass

@rpc("any_peer", "call_local", "reliable")
func _sync_status_effect_removed(effect_name: String):
	pass

@rpc("any_peer", "call_local", "reliable")
func _sync_damage_taken(amount: float, damage_type: int, zone: String, source):
	pass

@rpc("any_peer", "call_local", "reliable")
func _sync_death_state():
	pass

@rpc("any_peer", "call_local", "reliable")
func _sync_revival(method: String):
	pass

@rpc("any_peer", "call_local", "reliable")
func _sync_organ_state(organ_name: String):
	pass

@rpc("any_peer", "call_local", "reliable")
func _sync_limb_state(limb_name: String):
	pass

@rpc("any_peer", "call_local", "reliable")
func _sync_limb_fracture(limb_name: String):
	pass

@rpc("any_peer", "call_local", "reliable")
func _sync_limb_splint(limb_name: String):
	pass

@rpc("any_peer", "call_local", "reliable")
func _sync_bleeding_state():
	pass

@rpc("any_peer", "call_local", "reliable")
func _sync_cpr_state(in_progress: bool, performer = null, success: bool = false):
	pass

@rpc("any_peer", "call_local", "reliable")
func _sync_blood_volume():
	pass
