extends Node
class_name HealthConnector

#region EXPORTS AND CONFIGURATION
@export_group("Health Integration")
@export var debug_mode: bool = false
@export var auto_connect_health_system: bool = true
@export var enable_visual_feedback: bool = true
@export var enable_audio_feedback: bool = true
@export var enable_movement_penalties: bool = true

@export_group("Damage Thresholds")
@export var critical_health_threshold: float = 0.25
@export var severe_damage_threshold: float = 20.0
@export var blood_loss_warning_threshold: float = 0.7
@export var blood_loss_critical_threshold: float = 0.4

@export_group("Feedback Settings")
@export var damage_flash_intensity: float = 0.5
@export var pain_feedback_chance: float = 0.1
@export var status_message_duration: float = 3.0
#endregion

#region SIGNALS
signal health_state_changed(new_state)
signal bleeding_started
signal bleeding_stopped
signal damage_taken(amount, type)
signal cpr_started(performer)
signal cpr_completed(performer, success)
signal limb_fractured(limb_name)
signal limb_splinted(limb_name)
signal movement_impaired(penalty_factor)
signal organ_failure(organ_name)
#endregion

#region PROPERTIES
var entity = null
var health_system = null

var original_methods: Dictionary = {}
var last_movement_penalty: float = 1.0

# Multiplayer properties
var peer_id: int = 1
var is_multiplayer_game: bool = false

# Damage type mappings
var damage_type_mapping: Dictionary = {}
#endregion

#region INITIALIZATION
func _ready():
	entity = get_parent()
	
	if auto_connect_health_system:
		health_system = get_node_or_null("HealthSystem")
		if not health_system:
			health_system = get_parent().get_node_or_null("HealthSystem")
	
	if not health_system:
		push_error("HealthConnector: No HealthSystem found. This component won't function properly.")
		return
	
	_setup_multiplayer()
	_setup_damage_type_mapping()
	_connect_health_system()
	_install_hooks()
	
	if debug_mode:
		print("HealthConnector: Successfully initialized and connected to HealthSystem")

func _setup_multiplayer():
	"""Configure multiplayer settings"""
	is_multiplayer_game = multiplayer.has_multiplayer_peer()
	
	if entity and entity.has_meta("peer_id"):
		peer_id = entity.get_meta("peer_id")
	elif is_multiplayer_game:
		peer_id = multiplayer.get_remote_sender_id()
		if peer_id == 0:
			peer_id = multiplayer.get_unique_id()
	
	if is_multiplayer_game:
		set_multiplayer_authority(peer_id)

func _setup_damage_type_mapping():
	"""Configure damage type string to enum mappings"""
	if not health_system:
		return
	
	damage_type_mapping = {
		"brute": health_system.DamageType.BRUTE,
		"burn": health_system.DamageType.BURN,
		"tox": health_system.DamageType.TOXIN,
		"toxin": health_system.DamageType.TOXIN,
		"oxy": health_system.DamageType.OXYGEN,
		"oxygen": health_system.DamageType.OXYGEN,
		"clone": health_system.DamageType.CLONE,
		"brain": health_system.DamageType.BRAIN,
		"stamina": health_system.DamageType.STAMINA,
		"cellular": health_system.DamageType.CELLULAR,
		"genetic": health_system.DamageType.GENETIC,
		"radiation": health_system.DamageType.RADIATION
	}

func _connect_health_system():
	"""Connect to health system signals"""
	if not health_system:
		return
	
	var signal_connections = [
		["health_changed", "_on_health_changed"],
		["damage_taken", "_on_damage_taken"],
		["status_effect_added", "_on_status_effect_added"],
		["status_effect_removed", "_on_status_effect_removed"],
		["died", "_on_entity_died"],
		["revived", "_on_entity_revived"],
		["entered_critical", "_on_entered_critical"],
		["exited_critical", "_on_exited_critical"],
		["blood_level_changed", "_on_blood_level_changed"],
		["pulse_changed", "_on_pulse_changed"],
		["temperature_changed", "_on_temperature_changed"],
		["consciousness_changed", "_on_consciousness_changed"],
		["pain_level_changed", "_on_pain_level_changed"],
		["breathing_status_changed", "_on_breathing_status_changed"],
		["limb_fractured", "_on_limb_fractured"],
		["limb_splinted", "_on_limb_splinted"],
		["organ_damaged", "_on_organ_damaged"],
		["organ_healed", "_on_organ_healed"],
		["limb_damaged", "_on_limb_damaged"],
		["limb_healed", "_on_limb_healed"],
		["cpr_started", "_on_cpr_started"],
		["cpr_completed", "_on_cpr_completed"]
	]
	
	for connection in signal_connections:
		var signal_name = connection[0]
		var method_name = connection[1]
		
		if health_system.has_signal(signal_name):
			if not health_system.is_connected(signal_name, Callable(self, method_name)):
				health_system.connect(signal_name, Callable(self, method_name))

func _install_hooks():
	"""Install method hooks for backward compatibility"""
	_backup_original_methods()
	
	var hook_methods = [
		["apply_damage", "_hook_apply_damage"],
		["take_damage", "_hook_take_damage"],
		["heal_limb_damage", "_hook_heal_limb_damage"],
		["take_limb_damage", "_hook_take_limb_damage"],
		["adjustBruteLoss", "_hook_adjust_brute_loss"],
		["adjustFireLoss", "_hook_adjust_fire_loss"],
		["set_bleeding", "_hook_set_bleeding"],
		["stun", "_hook_stun"],
		["get_health", "_hook_get_health"],
		["start_cpr", "_hook_start_cpr"],
		["fracture_limb", "_hook_fracture_limb"],
		["splint_limb", "_hook_splint_limb"],
		["apply_organ_damage", "_hook_apply_organ_damage"],
		["get_movement_speed_modifier", "_hook_get_movement_speed_modifier"]
	]
	
	for hook in hook_methods:
		var method_name = hook[0]
		var hook_method = hook[1]
		_install_method_hook(method_name, hook_method)

func _backup_original_methods():
	"""Backup original entity methods before hooking"""
	var methods_to_backup = [
		"apply_damage", "take_damage", "heal_limb_damage", 
		"take_limb_damage", "adjustBruteLoss", "adjustFireLoss",
		"set_bleeding", "stun", "get_health", "start_cpr",
		"fracture_limb", "splint_limb", "apply_organ_damage", 
		"get_movement_speed_modifier"
	]
	
	for method in methods_to_backup:
		if entity.has_method(method):
			original_methods[method] = true

func _install_method_hook(original_method: String, hook_method: String):
	"""Install a method hook on the entity"""
	if entity.has_method(original_method):
		if debug_mode:
			print("HealthConnector: Installed hook for " + original_method)
	else:
		if debug_mode:
			print("HealthConnector: Added new method " + original_method)
#endregion

#region MULTIPLAYER FUNCTIONS
func _is_authority() -> bool:
	"""Check if this instance has authority"""
	if not is_multiplayer_game:
		return true
	return is_multiplayer_authority()

func _get_player_by_id(player_id: int) -> Node:
	"""Get player node by ID for multiplayer"""
	if not is_multiplayer_game:
		return entity
	
	var world = get_tree().current_scene
	if world:
		var player_node = world.get_node_or_null(str(player_id))
		return player_node
	
	return null
#endregion

#region RPC FUNCTIONS
@rpc("any_peer", "call_local", "reliable")
func rpc_apply_damage(amount: float, damage_type: int, zone: String = "", penetration: float = 0.0):
	if not _is_authority():
		return
	
	if health_system:
		health_system.apply_damage(amount, damage_type, penetration, zone)

@rpc("any_peer", "call_local", "reliable")
func rpc_heal_damage(amount: float, damage_type: String):
	if not _is_authority():
		return
	
	heal_damage(amount, damage_type)

@rpc("any_peer", "call_local", "reliable")
func rpc_set_bleeding(enabled: bool, intensity: float = 1.0):
	if not _is_authority():
		return
	
	_hook_set_bleeding(enabled, intensity)

@rpc("any_peer", "call_local", "reliable")
func rpc_stun(duration: float):
	if not _is_authority():
		return
	
	_hook_stun(duration)

@rpc("any_peer", "call_local", "reliable")
func rpc_start_cpr(performer_id: int):
	if not _is_authority():
		return
	
	var performer = _get_player_by_id(performer_id)
	if performer:
		_hook_start_cpr(performer)

@rpc("any_peer", "call_local", "reliable")
func rpc_fracture_limb(limb_name: String, severity: int = 1):
	if not _is_authority():
		return
	
	_hook_fracture_limb(limb_name, severity)

@rpc("any_peer", "call_local", "reliable")
func rpc_splint_limb(limb_name: String):
	if not _is_authority():
		return
	
	_hook_splint_limb(limb_name)

@rpc("any_peer", "call_local", "reliable")
func rpc_apply_organ_damage(organ_name: String, amount: float):
	if not _is_authority():
		return
	
	_hook_apply_organ_damage(organ_name, amount)

@rpc("any_peer", "call_local", "reliable")
func rpc_full_heal():
	if not _is_authority():
		return
	
	full_heal()

@rpc("any_peer", "call_local", "reliable")
func rpc_revive(method: String = "unknown"):
	if not _is_authority():
		return
	
	revive(method)

@rpc("any_peer", "call_local", "reliable")
func rpc_toggle_godmode(enabled = null):
	if not _is_authority():
		return
	
	toggle_godmode(enabled)
#endregion

#region HOOK IMPLEMENTATIONS
func _hook_apply_damage(amount, damage_type, zone = null, armor_type = null, updating_health = true):
	if not health_system:
		return 0
	
	if is_multiplayer_game and not _is_authority():
		rpc_apply_damage.rpc_id(1, amount, damage_type, zone if zone else "", 0.0)
		return amount
	
	var damage_type_enum = damage_type_mapping.get(str(damage_type).to_lower(), health_system.DamageType.BRUTE)
	return health_system.apply_damage(amount, damage_type_enum, 0, zone)

func _hook_take_damage(amount, damage_type = "brute", zone = null):
	return _hook_apply_damage(amount, damage_type, zone)

func _hook_heal_limb_damage(limb, brute_amount, burn_amount, update_health = true):
	if not health_system:
		return 0
	
	if is_multiplayer_game and not _is_authority():
		return 0
	
	return health_system.heal_limb_damage(limb, brute_amount, burn_amount)

func _hook_take_limb_damage(limb, brute_amount, burn_amount, update_health = true):
	if not health_system:
		return 0
	
	if is_multiplayer_game and not _is_authority():
		return 0
	
	var total_damage = 0
	if brute_amount > 0:
		total_damage += health_system.apply_damage(brute_amount, health_system.DamageType.BRUTE, 0, limb)
	if burn_amount > 0:
		total_damage += health_system.apply_damage(burn_amount, health_system.DamageType.BURN, 0, limb)
	return total_damage

func _hook_adjust_brute_loss(amount, update_health = true):
	if not health_system:
		return
	
	if is_multiplayer_game and not _is_authority():
		return
	
	health_system.adjustBruteLoss(amount, update_health)

func _hook_adjust_fire_loss(amount, update_health = true):
	if not health_system:
		return
	
	if is_multiplayer_game and not _is_authority():
		return
	
	health_system.adjustFireLoss(amount, update_health)

func _hook_set_bleeding(enabled, intensity = 1.0):
	if not health_system:
		return
	
	if is_multiplayer_game and not _is_authority():
		rpc_set_bleeding.rpc_id(1, enabled, intensity)
		return
	
	if enabled:
		health_system.set_bleeding_rate(intensity)
	else:
		health_system.set_bleeding_rate(0)

func _hook_stun(duration):
	if not health_system:
		return
	
	if is_multiplayer_game and not _is_authority():
		rpc_stun.rpc_id(1, duration)
		return
	
	health_system.add_status_effect("stunned", duration)

func _hook_get_health():
	if not health_system:
		return 100.0
	
	return health_system.health

func _hook_start_cpr(performer):
	if not health_system:
		return false
	
	if is_multiplayer_game and not _is_authority():
		var performer_id = 1
		if performer and performer.has_meta("peer_id"):
			performer_id = performer.get_meta("peer_id")
		rpc_start_cpr.rpc_id(1, performer_id)
		return false
	
	return health_system.start_cpr(performer)

func _hook_fracture_limb(limb_name, severity = 1):
	if not health_system:
		return false
	
	if is_multiplayer_game and not _is_authority():
		rpc_fracture_limb.rpc_id(1, limb_name, severity)
		return false
	
	return health_system._fracture_limb(limb_name, severity)

func _hook_splint_limb(limb_name):
	if not health_system:
		return false
	
	if is_multiplayer_game and not _is_authority():
		rpc_splint_limb.rpc_id(1, limb_name)
		return false
	
	return health_system.splint_limb(limb_name)

func _hook_apply_organ_damage(organ_name, amount):
	if not health_system:
		return 0.0
	
	if is_multiplayer_game and not _is_authority():
		rpc_apply_organ_damage.rpc_id(1, organ_name, amount)
		return 0.0
	
	return health_system.apply_organ_damage(organ_name, amount)

func _hook_get_movement_speed_modifier():
	if not health_system:
		return 1.0
	
	return health_system.get_movement_speed_modifier()
#endregion

#region EXTERNAL API
func external_call(method_name: String, args = []):
	"""Call methods on health system externally"""
	if not health_system:
		push_warning("HealthConnector: No health system available for external call: " + method_name)
		return null
	
	if not health_system.has_method(method_name):
		push_warning("HealthConnector: Health system doesn't have method: " + method_name)
		return null
	
	if args is Array:
		match args.size():
			0: return health_system.call(method_name)
			1: return health_system.call(method_name, args[0])
			2: return health_system.call(method_name, args[0], args[1])
			3: return health_system.call(method_name, args[0], args[1], args[2])
			4: return health_system.call(method_name, args[0], args[1], args[2], args[3])
			_: return health_system.callv(method_name, args)
	else:
		return health_system.call(method_name, args)

func apply_damage(amount, damage_type, limb = null):
	return _hook_apply_damage(amount, damage_type, limb)

func heal_damage(amount, damage_type = "brute"):
	if not health_system:
		return 0
	
	if is_multiplayer_game and not _is_authority():
		rpc_heal_damage.rpc_id(1, amount, damage_type)
		return amount
	
	var damage_type_enum = damage_type_mapping.get(str(damage_type).to_lower(), health_system.DamageType.BRUTE)
	
	match damage_type_enum:
		health_system.DamageType.BRUTE:
			health_system.adjustBruteLoss(-amount)
		health_system.DamageType.BURN:
			health_system.adjustFireLoss(-amount)
		health_system.DamageType.TOXIN:
			health_system.adjustToxLoss(-amount)
		health_system.DamageType.OXYGEN:
			health_system.adjustOxyLoss(-amount)
		health_system.DamageType.CLONE:
			health_system.adjustCloneLoss(-amount)
		health_system.DamageType.BRAIN:
			health_system.adjustBrainLoss(-amount)
		health_system.DamageType.STAMINA:
			health_system.adjustStaminaLoss(-amount)
	
	return amount

func set_bleeding(enabled, intensity = 1.0):
	return _hook_set_bleeding(enabled, intensity)

func stun(duration):
	return _hook_stun(duration)

func get_health():
	return _hook_get_health()

func get_health_percent():
	if not health_system:
		return 1.0
	
	return health_system.get_health_percent()

func is_dead():
	if not health_system:
		return false
	
	return health_system.current_state == health_system.HealthState.DEAD

func is_critical():
	if not health_system:
		return false
	
	return health_system.current_state == health_system.HealthState.CRITICAL

func is_unconscious():
	if not health_system:
		return false
	
	return health_system.is_unconscious

func is_bleeding():
	if not health_system:
		return false
	
	return health_system.is_bleeding()

func get_total_damage():
	if not health_system:
		return 0.0
	
	return health_system.get_total_damage()

func get_death_time_remaining():
	if not health_system:
		return 0.0
	
	return health_system.get_death_time_remaining()

func is_cpr_in_progress():
	if not health_system:
		return false
	
	return health_system.is_cpr_in_progress()

func start_cpr(performer):
	return _hook_start_cpr(performer)

func fracture_limb(limb_name, severity = 1):
	return _hook_fracture_limb(limb_name, severity)

func splint_limb(limb_name):
	return _hook_splint_limb(limb_name)

func apply_organ_damage(organ_name, amount):
	return _hook_apply_organ_damage(organ_name, amount)

func get_movement_speed_modifier():
	return _hook_get_movement_speed_modifier()

func get_pain_level():
	if not health_system:
		return 0.0
	
	return health_system.pain_level

func get_consciousness_level():
	if not health_system:
		return 100.0
	
	return health_system.consciousness_level

func full_heal():
	if not health_system:
		return false
	
	if is_multiplayer_game and not _is_authority():
		rpc_full_heal.rpc_id(1)
		return false
	
	return health_system.full_heal()

func revive(method = "unknown"):
	if not health_system:
		return false
	
	if is_multiplayer_game and not _is_authority():
		rpc_revive.rpc_id(1, method)
		return false
	
	return health_system.revive(method)

func toggle_godmode(enabled = null):
	if not health_system:
		return false
	
	if is_multiplayer_game and not _is_authority():
		rpc_toggle_godmode.rpc_id(1, enabled)
		return false
	
	return health_system.toggle_godmode(enabled)

func get_status_report():
	if not health_system:
		return {}
	
	return health_system.get_status_report()

func get_limb_status(limb_name: String):
	if not health_system or not health_system.limbs.has(limb_name):
		return {}
	
	return health_system.limbs[limb_name].duplicate()

func get_organ_status(organ_name: String):
	if not health_system or not health_system.organs.has(organ_name):
		return {}
	
	return health_system.organs[organ_name].duplicate()

func is_limb_fractured(limb_name: String):
	if not health_system or not health_system.limbs.has(limb_name):
		return false
	
	return health_system.limbs[limb_name].is_fractured

func is_limb_splinted(limb_name: String):
	if not health_system or not health_system.limbs.has(limb_name):
		return false
	
	return health_system.limbs[limb_name].is_splinted

func is_organ_failing(organ_name: String):
	if not health_system or not health_system.organs.has(organ_name):
		return false
	
	return health_system.organs[organ_name].is_failing

func get_blood_percentage():
	if not health_system:
		return 1.0
	
	return health_system.blood_volume / health_system.blood_volume_maximum

func get_pulse():
	if not health_system:
		return 70
	
	return health_system.get_pulse()

func get_breathing_rate():
	if not health_system:
		return 16
	
	return health_system.get_respiratory_rate()

func get_body_temperature():
	if not health_system:
		return 37.0
	
	return health_system.get_body_temperature()
#endregion

#region EVENT HANDLERS
func _on_health_changed(new_health, max_health, health_percent):
	"""Handle health changes and update connected systems"""
	if entity.get_node_or_null("SensorySystem"):
		entity.get_node("SensorySystem").update_health_display(health_percent)
	
	if new_health < max_health * critical_health_threshold and entity.get_node_or_null("HumanSpriteSystem"):
		if entity.get_node("HumanSpriteSystem").has_method("set_critical_condition"):
			entity.get_node("HumanSpriteSystem").set_critical_condition(true)
	
	if enable_movement_penalties:
		_update_movement_penalties()

func _on_damage_taken(amount, type, zone, source):
	"""Handle damage taken events"""
	damage_taken.emit(amount, type)
	
	if enable_audio_feedback and entity.get_node_or_null("AudioSystem"):
		var sound_name = "hit"
		match type:
			health_system.DamageType.BURN: sound_name = "burn"
			health_system.DamageType.TOXIN: sound_name = "poison"
			health_system.DamageType.OXYGEN: sound_name = "gasp"
			health_system.DamageType.BRAIN: sound_name = "brain_damage"
		
		entity.get_node("AudioSystem").play_positioned_sound(sound_name, entity.position, 0.4)
	
	if entity.get_node_or_null("SensorySystem"):
		var type_name = "damage"
		var zone_text = " to your " + zone if zone != "" else ""
		
		match type:
			health_system.DamageType.BRUTE: type_name = "brute"
			health_system.DamageType.BURN: type_name = "burn"
			health_system.DamageType.TOXIN: type_name = "toxic"
			health_system.DamageType.OXYGEN: type_name = "oxygen"
			health_system.DamageType.CLONE: type_name = "cellular"
			health_system.DamageType.BRAIN: type_name = "brain"
			health_system.DamageType.STAMINA: type_name = "stamina"
			health_system.DamageType.CELLULAR: type_name = "cellular"
			health_system.DamageType.GENETIC: type_name = "genetic"
			health_system.DamageType.RADIATION: type_name = "radiation"
		
		entity.get_node("SensorySystem").display_message("You take " + str(round(amount)) + " " + type_name + " damage" + zone_text + "!")
	
	if enable_visual_feedback and amount > severe_damage_threshold and entity.get_node_or_null("HumanSpriteSystem"):
		if entity.get_node("HumanSpriteSystem").has_method("flash_damage"):
			entity.get_node("HumanSpriteSystem").flash_damage()

func _on_status_effect_added(effect_name, duration, intensity):
	"""Handle status effect additions"""
	if entity.has_method("add_status_effect"):
		entity.add_status_effect(effect_name, duration)
	
	match effect_name:
		"stunned":
			if entity.has_method("stun"):
				entity.stun(duration)
		"bleeding":
			bleeding_started.emit()
			if enable_visual_feedback and entity.get_node_or_null("HumanSpriteSystem") and entity.get_node("HumanSpriteSystem").has_method("start_bleeding_effect"):
				entity.get_node("HumanSpriteSystem").start_bleeding_effect()
		"unconscious":
			if entity.has_method("set_state"):
				entity.set_state(entity.MovementState.STUNNED)
			if entity.has_method("set_resting"):
				entity.set_resting(true)
		"slowed":
			if entity.has_method("add_movement_modifier"):
				entity.add_movement_modifier("health_slowed", 0.5)
		"confused":
			if entity.get_node_or_null("SensorySystem"):
				entity.get_node("SensorySystem").display_message("You feel confused and disoriented...")
		"exhausted":
			if entity.has_method("add_movement_modifier"):
				entity.add_movement_modifier("exhausted", 0.3)
		"pale":
			if enable_visual_feedback and entity.get_node_or_null("HumanSpriteSystem") and entity.get_node("HumanSpriteSystem").has_method("set_pallor"):
				entity.get_node("HumanSpriteSystem").set_pallor(0.3)
		"dizzy":
			if entity.get_node_or_null("SensorySystem"):
				entity.get_node("SensorySystem").display_message("You feel dizzy from blood loss...")
		"weak":
			if entity.has_method("add_movement_modifier"):
				entity.add_movement_modifier("weakness", 0.7)
		"cardiac_arrest":
			if entity.get_node_or_null("SensorySystem"):
				entity.get_node("SensorySystem").display_message("Your heart stops beating!", "red")

func _on_status_effect_removed(effect_name):
	"""Handle status effect removals"""
	if entity.has_method("remove_status_effect"):
		entity.remove_status_effect(effect_name)
	
	match effect_name:
		"stunned":
			if entity.has_method("set_state") and entity.current_state == entity.MovementState.STUNNED:
				entity.set_state(entity.MovementState.IDLE)
		"bleeding":
			bleeding_stopped.emit()
			if enable_visual_feedback and entity.get_node_or_null("HumanSpriteSystem") and entity.get_node("HumanSpriteSystem").has_method("stop_bleeding_effect"):
				entity.get_node("HumanSpriteSystem").stop_bleeding_effect()
		"unconscious":
			if health_system.current_state == health_system.HealthState.ALIVE:
				if entity.has_method("set_state"):
					entity.set_state(entity.MovementState.IDLE)
		"slowed":
			if entity.has_method("remove_movement_modifier"):
				entity.remove_movement_modifier("health_slowed")
		"exhausted":
			if entity.has_method("remove_movement_modifier"):
				entity.remove_movement_modifier("exhausted")
		"pale":
			if enable_visual_feedback and entity.get_node_or_null("HumanSpriteSystem") and entity.get_node("HumanSpriteSystem").has_method("set_pallor"):
				entity.get_node("HumanSpriteSystem").set_pallor(0.0)
		"weak":
			if entity.has_method("remove_movement_modifier"):
				entity.remove_movement_modifier("weakness")

func _on_entity_died(cause_of_death, death_time):
	"""Handle entity death"""
	if entity.has_method("set_state"):
		entity.set_state(entity.MovementState.STUNNED)
	
	if enable_visual_feedback and entity.get_node_or_null("HumanSpriteSystem") and entity.get_node("HumanSpriteSystem").has_method("update_death_state"):
		entity.get_node("HumanSpriteSystem").update_death_state(true)
	
	if entity.get_node_or_null("InventorySystem") and entity.get_node("InventorySystem").has_method("drop_all_items"):
		entity.get_node("InventorySystem").drop_all_items()
	
	if entity.get_node_or_null("SensorySystem"):
		var time_remaining = health_system.get_death_time_remaining()
		var time_text = str(int(time_remaining / 60)) + ":" + str(int(time_remaining) % 60).pad_zeros(2)
		entity.get_node("SensorySystem").display_message("You have died from " + cause_of_death + ". Revival possible for " + time_text + ".", "red")
	
	if entity.has_method("clear_all_movement_modifiers"):
		entity.clear_all_movement_modifiers()
	
	health_state_changed.emit("dead")

func _on_entity_revived(revival_method):
	"""Handle entity revival"""
	if entity.has_method("set_state"):
		entity.set_state(entity.MovementState.IDLE)
	
	if enable_visual_feedback and entity.get_node_or_null("HumanSpriteSystem") and entity.get_node("HumanSpriteSystem").has_method("update_death_state"):
		entity.get_node("HumanSpriteSystem").update_death_state(false)
	
	if entity.get_node_or_null("SensorySystem"):
		entity.get_node("SensorySystem").display_message("You have been revived via " + revival_method + "!", "green")
	
	health_state_changed.emit("alive")

func _on_entered_critical(health_percent):
	"""Handle entering critical state"""
	if entity.has_method("set_state"):
		entity.set_state(entity.MovementState.STUNNED)
	
	if enable_visual_feedback and entity.get_node_or_null("HumanSpriteSystem") and entity.get_node("HumanSpriteSystem").has_method("set_critical_condition"):
		entity.get_node("HumanSpriteSystem").set_critical_condition(true)
	
	if entity.get_node_or_null("SensorySystem"):
		entity.get_node("SensorySystem").display_message("You are critically injured and need medical attention!", "red")
	
	health_state_changed.emit("critical")

func _on_exited_critical(new_state):
	"""Handle exiting critical state"""
	if entity.has_method("set_state") and not health_system.status_effects.has("stunned"):
		entity.set_state(entity.MovementState.IDLE)
	
	if enable_visual_feedback and entity.get_node_or_null("HumanSpriteSystem") and entity.get_node("HumanSpriteSystem").has_method("set_critical_condition"):
		entity.get_node("HumanSpriteSystem").set_critical_condition(false)
	
	if entity.get_node_or_null("SensorySystem"):
		entity.get_node("SensorySystem").display_message("Your condition has stabilized.", "green")
	
	health_state_changed.emit("alive")

func _on_blood_level_changed(new_amount, max_amount, blood_percent, status):
	"""Handle blood level changes"""
	if new_amount < health_system.blood_volume_normal and enable_visual_feedback and entity.get_node_or_null("HumanSpriteSystem"):
		if entity.get_node("HumanSpriteSystem").has_method("set_pallor"):
			var pallor_amount = 1.0 - blood_percent
			entity.get_node("HumanSpriteSystem").set_pallor(pallor_amount)
	
	if entity.get_node_or_null("SensorySystem"):
		match status:
			health_system.BloodStatus.LOW:
				if blood_percent < blood_loss_warning_threshold:
					entity.get_node("SensorySystem").display_message("You feel weak from blood loss.", "orange")
			health_system.BloodStatus.CRITICALLY_LOW:
				if blood_percent < blood_loss_critical_threshold:
					entity.get_node("SensorySystem").display_message("You are critically low on blood!", "red")
			health_system.BloodStatus.FATAL:
				entity.get_node("SensorySystem").display_message("You are dying from blood loss!", "red")

func _on_pulse_changed(new_pulse, pulse_status):
	"""Handle pulse changes"""
	if pulse_status == health_system.PulseStatus.NO_PULSE:
		if entity.get_node_or_null("SensorySystem"):
			entity.get_node("SensorySystem").display_message("Your heart has stopped!", "red")

func _on_temperature_changed(new_temp, temp_status):
	"""Handle temperature changes"""
	if entity.get_node_or_null("SensorySystem"):
		match temp_status:
			health_system.TemperatureStatus.HYPOTHERMIC:
				entity.get_node("SensorySystem").display_message("You are dangerously cold!", "blue")
			health_system.TemperatureStatus.HYPERTHERMIC:
				entity.get_node("SensorySystem").display_message("You are dangerously hot!", "red")
			health_system.TemperatureStatus.CRITICAL:
				entity.get_node("SensorySystem").display_message("Your body temperature is critical!", "red")

func _on_consciousness_changed(is_conscious, reason):
	"""Handle consciousness changes"""
	if not is_conscious and entity.get_node_or_null("SensorySystem"):
		match reason:
			"health_loss":
				entity.get_node("SensorySystem").display_message("You lose consciousness from your injuries...", "red")
			"blood_loss":
				entity.get_node("SensorySystem").display_message("You pass out from blood loss...", "red")
			"pain":
				entity.get_node("SensorySystem").display_message("The pain overwhelms you...", "red")
			"death":
				pass

func _on_pain_level_changed(pain_level, pain_status):
	"""Handle pain level changes"""
	if enable_movement_penalties:
		_update_movement_penalties()
	
	if entity.get_node_or_null("SensorySystem"):
		match pain_status:
			health_system.PainLevel.SEVERE:
				if randf() < pain_feedback_chance * 1.0:
					entity.get_node("SensorySystem").display_message("The pain is severe!", "red")
			health_system.PainLevel.EXTREME:
				if randf() < pain_feedback_chance * 2.0:
					entity.get_node("SensorySystem").display_message("You are in agony!", "red")
			health_system.PainLevel.UNBEARABLE:
				if randf() < pain_feedback_chance * 3.0:
					entity.get_node("SensorySystem").display_message("The pain is unbearable!", "red")

func _on_breathing_status_changed(breathing_rate, status):
	"""Handle breathing status changes"""
	if entity.get_node_or_null("SensorySystem"):
		match status:
			"not_breathing":
				entity.get_node("SensorySystem").display_message("You have stopped breathing!", "red")
			"hyperventilating":
				entity.get_node("SensorySystem").display_message("You are hyperventilating!", "orange")

func _on_limb_fractured(limb_name):
	"""Handle limb fractures"""
	limb_fractured.emit(limb_name)
	
	if entity.get_node_or_null("SensorySystem"):
		var limb_display = limb_name.replace("_", " ")
		entity.get_node("SensorySystem").display_message("Your " + limb_display + " is fractured!", "red")
	
	if enable_movement_penalties:
		_update_movement_penalties()

func _on_limb_splinted(limb_name):
	"""Handle limb splinting"""
	limb_splinted.emit(limb_name)
	
	if entity.get_node_or_null("SensorySystem"):
		var limb_display = limb_name.replace("_", " ")
		entity.get_node("SensorySystem").display_message("Your " + limb_display + " has been splinted.", "green")
	
	if enable_movement_penalties:
		_update_movement_penalties()

func _on_organ_damaged(organ_name, damage_amount, total_damage):
	"""Handle organ damage"""
	if entity.get_node_or_null("SensorySystem"):
		if damage_amount > 10:
			entity.get_node("SensorySystem").display_message("Your " + organ_name + " is damaged!", "red")
	
	if health_system.organs.has(organ_name):
		var organ = health_system.organs[organ_name]
		if organ.is_failing:
			organ_failure.emit(organ_name)
			if entity.get_node_or_null("SensorySystem"):
				entity.get_node("SensorySystem").display_message("Your " + organ_name + " is failing!", "red")

func _on_organ_healed(organ_name, heal_amount, remaining_damage):
	"""Handle organ healing"""
	if entity.get_node_or_null("SensorySystem"):
		if heal_amount > 5:
			entity.get_node("SensorySystem").display_message("Your " + organ_name + " feels better.", "green")

func _on_limb_damaged(limb_name, damage_amount, damage_type):
	"""Handle limb damage"""
	if entity.get_node_or_null("SensorySystem") and damage_amount > 15:
		var limb_display = limb_name.replace("_", " ")
		var damage_type_text = "damage"
		
		match damage_type:
			health_system.DamageType.BRUTE:
				damage_type_text = "trauma"
			health_system.DamageType.BURN:
				damage_type_text = "burns"
		
		entity.get_node("SensorySystem").display_message("Your " + limb_display + " suffers " + damage_type_text + "!", "red")

func _on_limb_healed(limb_name, heal_amount, damage_type):
	"""Handle limb healing"""
	if entity.get_node_or_null("SensorySystem") and heal_amount > 10:
		var limb_display = limb_name.replace("_", " ")
		entity.get_node("SensorySystem").display_message("Your " + limb_display + " feels better.", "green")

func _on_cpr_started(performer):
	"""Handle CPR start"""
	cpr_started.emit(performer)
	
	if entity.get_node_or_null("SensorySystem"):
		var performer_name = performer.entity_name if "entity_name" in performer else "Someone"
		entity.get_node("SensorySystem").display_message(performer_name + " begins performing CPR on you...", "cyan")

func _on_cpr_completed(performer, success):
	"""Handle CPR completion"""
	cpr_completed.emit(performer, success)
	
	if entity.get_node_or_null("SensorySystem"):
		var performer_name = performer.entity_name if "entity_name" in performer else "Someone"
		if success:
			entity.get_node("SensorySystem").display_message(performer_name + " successfully performs CPR - you feel slightly better!", "green")
		else:
			entity.get_node("SensorySystem").display_message(performer_name + " completes CPR, but you still need more help...", "orange")
#endregion

#region UTILITY FUNCTIONS
func _update_movement_penalties():
	"""Update movement penalties based on health status"""
	if not health_system:
		return
	
	var current_penalty = health_system.get_movement_speed_modifier()
	
	if abs(current_penalty - last_movement_penalty) > 0.05:
		movement_impaired.emit(current_penalty)
		last_movement_penalty = current_penalty
		
		if entity.has_method("set_movement_speed_modifier"):
			entity.set_movement_speed_modifier("health_penalty", current_penalty)
#endregion
