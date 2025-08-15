extends Node
class_name StatusEffectComponent

#region SIGNALS
signal effect_added(effect_name: String)
signal effect_removed(effect_name: String)
signal effect_updated(effect_name: String, remaining_time: float)
signal movement_speed_changed(modifier: float)
signal stunned(duration: float)
signal stun_ended()
#endregion

#region EXPORTS
@export_group("Effect Configuration")
@export var allow_effect_stacking: bool = false
@export var effect_update_interval: float = 0.1
@export var show_effect_messages: bool = true

@export_group("Duration Modifiers")
@export var stun_duration_multiplier: float = 1.0
@export var confusion_duration_multiplier: float = 1.0
@export var poison_damage_interval: float = 2.0

@export_group("Intensity Settings")
@export var default_confusion_intensity: float = 100.0
@export var default_slowness_intensity: float = 0.5
@export var default_weakness_intensity: float = 0.5

@export_group("Visual Settings")
@export var effect_message_color: Color = Color.ORANGE
@export var critical_effect_color: Color = Color.RED
@export var positive_effect_color: Color = Color.GREEN
#endregion

#region PROPERTIES
var controller: Node = null
var sensory_system = null

var status_effects: Dictionary = {}
var effect_timers: Dictionary = {}

# Cached calculations for performance
var _cached_movement_modifier: float = 1.0
var _modifier_cache_dirty: bool = true
var _last_effect_update: float = 0.0

# Network state
var peer_id: int = 1
var is_local_player: bool = false
#endregion

#region INITIALIZATION
func initialize(init_data: Dictionary):
	controller = init_data.get("controller")
	sensory_system = init_data.get("sensory_system")
	peer_id = init_data.get("peer_id", 1)
	is_local_player = init_data.get("is_local_player", false)
	
	set_multiplayer_authority(peer_id)

func _process(delta: float):
	if is_multiplayer_authority():
		_update_status_effects(delta)
#endregion

#region EFFECT MANAGEMENT
func apply_effect(effect_name: String, duration: float, intensity: float = 1.0, data: Dictionary = {}) -> Dictionary:
	if not is_multiplayer_authority():
		return {}
	
	var effect_data = _create_effect_data(duration, intensity, data)
	var is_new = not has_effect(effect_name)
	
	if not allow_effect_stacking and has_effect(effect_name):
		_update_existing_effect(effect_name, effect_data)
	else:
		status_effects[effect_name] = effect_data
	
	_apply_immediate_effects(effect_name, intensity, data)
	_invalidate_cache()
	
	sync_apply_effect.rpc(effect_name, duration, intensity, data)
	
	if is_new:
		emit_signal("effect_added", effect_name)
	else:
		emit_signal("effect_updated", effect_name, duration)
	
	return effect_data

func remove_effect(effect_name: String):
	if not is_multiplayer_authority():
		return
	
	if not has_effect(effect_name):
		return
	
	_cleanup_effect(effect_name)
	status_effects.erase(effect_name)
	
	if effect_name in effect_timers:
		effect_timers[effect_name].queue_free()
		effect_timers.erase(effect_name)
	
	_invalidate_cache()
	sync_remove_effect.rpc(effect_name)
	emit_signal("effect_removed", effect_name)

func clear_all_effects():
	if not is_multiplayer_authority():
		return
	
	for effect_name in status_effects.keys():
		remove_effect(effect_name)

func _create_effect_data(duration: float, intensity: float, data: Dictionary) -> Dictionary:
	return {
		"duration": duration,
		"intensity": intensity,
		"start_time": Time.get_ticks_msec() / 1000.0,
		"data": data
	}

func _update_existing_effect(effect_name: String, new_data: Dictionary):
	var existing = status_effects[effect_name]
	
	# Update with the stronger/longer effect
	if new_data.duration > get_effect_remaining_time(effect_name):
		existing.duration = new_data.duration
		existing.start_time = new_data.start_time
	
	if new_data.intensity > existing.intensity:
		existing.intensity = new_data.intensity

func _invalidate_cache():
	_modifier_cache_dirty = true
#endregion

#region EFFECT QUERIES
func has_effect(effect_name: String) -> bool:
	return effect_name in status_effects

func get_effect_intensity(effect_name: String) -> float:
	if has_effect(effect_name):
		return status_effects[effect_name].intensity
	return 0.0

func get_effect_remaining_time(effect_name: String) -> float:
	if has_effect(effect_name):
		var effect = status_effects[effect_name]
		var current_time = Time.get_ticks_msec() / 1000.0
		var elapsed = current_time - effect.start_time
		return max(0.0, effect.duration - elapsed)
	return 0.0

func has_effect_flag(flag: String) -> bool:
	for effect_name in status_effects:
		var effect_data = _get_effect_definition(effect_name)
		if "flags" in effect_data and flag in effect_data.flags:
			return true
	return false

func get_all_active_effects() -> Array:
	var effects = []
	for effect_name in status_effects:
		var effect_def = _get_effect_definition(effect_name)
		effect_def["remaining_time"] = get_effect_remaining_time(effect_name)
		effect_def["intensity"] = get_effect_intensity(effect_name)
		effects.append(effect_def)
	return effects
#endregion

#region SPECIFIC EFFECT APPLICATIONS
func apply_stun(duration: float):
	var modified_duration = duration * stun_duration_multiplier
	apply_effect("stunned", modified_duration, 1.0)
	
	if controller.movement_component:
		controller.movement_component.is_stunned = true
		controller.movement_component.stun_remaining = modified_duration
		
		if controller.movement_component.is_moving:
			controller.movement_component.is_moving = false
			controller.movement_component.move_progress = 0.0
	
	emit_signal("stunned", modified_duration)

func apply_confusion(duration: float, intensity: float = -1.0):
	var confusion_intensity = intensity if intensity >= 0 else default_confusion_intensity
	var modified_duration = duration * confusion_duration_multiplier
	apply_effect("confused", modified_duration, confusion_intensity)
	
	if controller.movement_component:
		controller.movement_component.set_confusion(confusion_intensity)

func apply_blindness(duration: float):
	apply_effect("blinded", duration, 1.0)

func apply_slowness(duration: float, intensity: float = -1.0):
	var slow_intensity = intensity if intensity >= 0 else default_slowness_intensity
	apply_effect("slowed", duration, slow_intensity)

func apply_mute(duration: float):
	apply_effect("muted", duration, 1.0)

func apply_paralysis(duration: float):
	apply_effect("paralyzed", duration, 1.0)

func apply_weakness(duration: float, intensity: float = -1.0):
	var weak_intensity = intensity if intensity >= 0 else default_weakness_intensity
	apply_effect("weakened", duration, weak_intensity)

func apply_poison(duration: float, intensity: float = 1.0):
	apply_effect("poisoned", duration, intensity)

func apply_bleeding(intensity: float = 1.0):
	apply_effect("bleeding", -1.0, intensity)  # -1.0 for indefinite duration

func apply_burning(duration: float, intensity: float = 1.0):
	apply_effect("burning", duration, intensity)
#endregion

#region EFFECT PROCESSING
func _update_status_effects(delta: float):
	var current_time = Time.get_ticks_msec() / 1000.0
	
	if current_time - _last_effect_update < effect_update_interval:
		return
	
	_last_effect_update = current_time
	
	var effects_to_remove = []
	
	for effect_name in status_effects:
		var effect = status_effects[effect_name]
		var elapsed = current_time - effect.start_time
		
		if effect.duration > 0 and elapsed >= effect.duration:
			effects_to_remove.append(effect_name)
			continue
		
		_process_ongoing_effect(effect_name, effect, delta)
		
		if effect.duration > 0:
			emit_signal("effect_updated", effect_name, effect.duration - elapsed)
	
	for effect_name in effects_to_remove:
		remove_effect(effect_name)

func _process_ongoing_effect(effect_name: String, effect: Dictionary, delta: float):
	match effect_name:
		"poisoned":
			_process_poison_effect(effect, delta)
		"bleeding":
			_process_bleeding_effect(effect, delta)
		"burning":
			_process_burning_effect(effect, delta)
		"confused":
			_process_confusion_effect(effect, delta)
		"slowed":
			_process_slowness_effect(effect, delta)
		"stunned":
			_process_stun_effect(effect, delta)
		"paralyzed":
			_process_paralysis_effect(effect, delta)
		"weakened":
			_process_weakness_effect(effect, delta)

func _process_poison_effect(effect: Dictionary, delta: float):
	var time_since_start = Time.get_ticks_msec() / 1000.0 - effect.start_time
	if fmod(time_since_start, poison_damage_interval) < delta:
		if controller.has_method("take_damage"):
			var damage = effect.intensity
			controller.take_damage(damage, "toxin")

func _process_bleeding_effect(effect: Dictionary, delta: float):
	if controller.has_method("apply_blood_loss"):
		var blood_loss = effect.intensity * delta * 10.0
		controller.apply_blood_loss(blood_loss)

func _process_burning_effect(effect: Dictionary, delta: float):
	if fmod(Time.get_ticks_msec() / 1000.0, 1.0) < delta:
		if controller.has_method("take_damage"):
			var damage = effect.intensity * 2.0
			controller.take_damage(damage, "burn")

func _process_confusion_effect(effect: Dictionary, delta: float):
	# Confusion is handled by movement component
	pass

func _process_slowness_effect(effect: Dictionary, delta: float):
	# Slowness is handled by movement modifier
	pass

func _process_stun_effect(effect: Dictionary, delta: float):
	# Stun is handled by movement component
	pass

func _process_paralysis_effect(effect: Dictionary, delta: float):
	# Paralysis is handled by movement modifier
	pass

func _process_weakness_effect(effect: Dictionary, delta: float):
	# Weakness affects combat damage (handled elsewhere)
	pass
#endregion

#region EFFECT DEFINITIONS
func _get_effect_definition(effect_name: String) -> Dictionary:
	match effect_name:
		"stunned":
			return {
				"name": "Stunned",
				"description": "Unable to act",
				"icon": "effect_stun",
				"flags": ["movement_restricting", "action_restricting"],
				"color": critical_effect_color
			}
		"confused":
			return {
				"name": "Confused",
				"description": "Movement is erratic",
				"icon": "effect_confusion",
				"flags": ["movement_affecting"],
				"color": effect_message_color
			}
		"blinded":
			return {
				"name": "Blinded",
				"description": "Cannot see",
				"icon": "effect_blind",
				"flags": ["vision_affecting"],
				"color": critical_effect_color
			}
		"slowed":
			return {
				"name": "Slowed",
				"description": "Movement speed reduced",
				"icon": "effect_slow",
				"flags": ["movement_affecting"],
				"color": effect_message_color
			}
		"muted":
			return {
				"name": "Muted",
				"description": "Cannot speak",
				"icon": "effect_mute",
				"flags": ["speech_affecting"],
				"color": effect_message_color
			}
		"paralyzed":
			return {
				"name": "Paralyzed",
				"description": "Cannot move or act",
				"icon": "effect_paralyze",
				"flags": ["movement_restricting", "action_restricting"],
				"color": critical_effect_color
			}
		"weakened":
			return {
				"name": "Weakened",
				"description": "Reduced strength",
				"icon": "effect_weak",
				"flags": ["combat_affecting"],
				"color": effect_message_color
			}
		"poisoned":
			return {
				"name": "Poisoned",
				"description": "Taking damage over time",
				"icon": "effect_poison",
				"flags": ["damage_over_time"],
				"color": critical_effect_color
			}
		"bleeding":
			return {
				"name": "Bleeding",
				"description": "Losing blood over time",
				"icon": "effect_bleeding",
				"flags": ["damage_over_time"],
				"color": critical_effect_color
			}
		"burning":
			return {
				"name": "Burning",
				"description": "Taking fire damage over time",
				"icon": "effect_fire",
				"flags": ["damage_over_time"],
				"color": critical_effect_color
			}
		"restrained":
			return {
				"name": "Restrained",
				"description": "Movement restricted",
				"icon": "effect_restrain",
				"flags": ["movement_restricting"],
				"color": effect_message_color
			}
		"buckled":
			return {
				"name": "Buckled",
				"description": "Secured to an object",
				"icon": "effect_buckle",
				"flags": ["movement_restricting"],
				"color": effect_message_color
			}
		"flying":
			return {
				"name": "Flying",
				"description": "Can move through air",
				"icon": "effect_fly",
				"flags": ["movement_enhancing"],
				"color": positive_effect_color
			}
		"magboots":
			return {
				"name": "Magboots Active",
				"description": "Magnetic boots prevent slipping",
				"icon": "effect_magboot",
				"flags": ["slip_immunity"],
				"color": positive_effect_color
			}
		_:
			return {
				"name": effect_name.capitalize(),
				"description": "Unknown effect",
				"icon": "effect_unknown",
				"flags": [],
				"color": effect_message_color
			}
#endregion

#region IMMEDIATE EFFECT HANDLING
func _apply_immediate_effects(effect_name: String, intensity: float, data: Dictionary):
	match effect_name:
		"confused":
			_show_effect_message("You feel confused!", effect_message_color)
		"blinded":
			_show_effect_message("You can't see!", critical_effect_color)
		"slowed":
			if controller.movement_component:
				controller.movement_component.set_movement_modifier(1.0 - intensity)
			emit_signal("movement_speed_changed", 1.0 - intensity)
			_show_effect_message("You feel sluggish!", effect_message_color)
		"muted":
			_show_effect_message("You can't speak!", effect_message_color)
		"paralyzed":
			_show_effect_message("You can't move!", critical_effect_color)
			if controller.movement_component:
				controller.movement_component.set_movement_modifier(0.0)
		"weakened":
			_show_effect_message("You feel weak!", effect_message_color)
		"poisoned":
			_show_effect_message("You feel sick!", critical_effect_color)
		"bleeding":
			_show_effect_message("You are bleeding!", critical_effect_color)
		"burning":
			_show_effect_message("You are on fire!", critical_effect_color)
		"restrained":
			_show_effect_message("You're restrained and can't move!", effect_message_color)
		"flying":
			_show_effect_message("You feel weightless!", positive_effect_color)

func _cleanup_effect(effect_name: String):
	match effect_name:
		"slowed":
			if controller.movement_component:
				controller.movement_component.set_movement_modifier(1.0)
			emit_signal("movement_speed_changed", 1.0)
		"confused":
			if controller.movement_component:
				controller.movement_component.set_confusion(0.0)
			_show_effect_message("Your mind clears.", positive_effect_color)
		"blinded":
			_show_effect_message("You can see again!", positive_effect_color)
		"stunned":
			if controller.movement_component:
				controller.movement_component.is_stunned = false
			emit_signal("stun_ended")
		"paralyzed":
			if controller.movement_component:
				controller.movement_component.set_movement_modifier(1.0)
			_show_effect_message("You can move again!", positive_effect_color)
		"muted":
			_show_effect_message("You can speak again!", positive_effect_color)
		"poisoned":
			_show_effect_message("You feel better.", positive_effect_color)
		"bleeding":
			_show_effect_message("The bleeding stops.", positive_effect_color)
		"burning":
			_show_effect_message("The fire goes out.", positive_effect_color)
#endregion

#region CAPABILITY CHECKS
func get_movement_modifier() -> float:
	if _modifier_cache_dirty:
		_update_movement_modifier_cache()
	return _cached_movement_modifier

func _update_movement_modifier_cache():
	var modifier = 1.0
	
	if has_effect("slowed"):
		modifier *= (1.0 - get_effect_intensity("slowed"))
	
	if has_effect("paralyzed"):
		modifier = 0.0
	
	if has_effect("weakened"):
		modifier *= (1.0 - (get_effect_intensity("weakened") * 0.3))
	
	_cached_movement_modifier = modifier
	_modifier_cache_dirty = false

func can_act() -> bool:
	return not has_effect("stunned") and not has_effect("paralyzed")

func can_move() -> bool:
	return not has_effect("stunned") and not has_effect("paralyzed") and not has_effect("restrained") and not has_effect("buckled")

func can_speak() -> bool:
	return not has_effect("muted")

func can_see() -> bool:
	return not has_effect("blinded")

func is_immune_to_slipping() -> bool:
	return has_effect("magboots")

func is_flying() -> bool:
	return has_effect("flying")
#endregion

#region UTILITY FUNCTIONS
func _show_effect_message(message: String, color: Color = effect_message_color):
	if not show_effect_messages or not sensory_system:
		return
		
	var formatted_message = "[color=" + color.to_html() + "]" + message + "[/color]"
	sensory_system.display_message(formatted_message)

func get_effect_data(effect_name: String) -> Dictionary:
	if has_effect(effect_name):
		return status_effects[effect_name].duplicate()
	return {}

func extend_effect_duration(effect_name: String, additional_time: float):
	if not has_effect(effect_name) or not is_multiplayer_authority():
		return
	
	status_effects[effect_name].duration += additional_time
	emit_signal("effect_updated", effect_name, get_effect_remaining_time(effect_name))

func modify_effect_intensity(effect_name: String, new_intensity: float):
	if not has_effect(effect_name) or not is_multiplayer_authority():
		return
	
	var old_intensity = status_effects[effect_name].intensity
	status_effects[effect_name].intensity = new_intensity
	
	# Reapply immediate effects if intensity changed significantly
	if abs(new_intensity - old_intensity) > 0.1:
		_apply_immediate_effects(effect_name, new_intensity, status_effects[effect_name].data)
	
	_invalidate_cache()
#endregion

#region NETWORK SYNCHRONIZATION
@rpc("any_peer", "call_local", "reliable")
func sync_apply_effect(effect_name: String, duration: float, intensity: float, data: Dictionary):
	if is_multiplayer_authority():
		return
	
	var effect_data = _create_effect_data(duration, intensity, data)
	var is_new = not has_effect(effect_name)
	
	status_effects[effect_name] = effect_data
	_apply_immediate_effects(effect_name, intensity, data)
	_invalidate_cache()
	
	if is_new:
		emit_signal("effect_added", effect_name)
	else:
		emit_signal("effect_updated", effect_name, duration)

@rpc("any_peer", "call_local", "reliable")
func sync_remove_effect(effect_name: String):
	if is_multiplayer_authority():
		return
	
	if not has_effect(effect_name):
		return
	
	_cleanup_effect(effect_name)
	status_effects.erase(effect_name)
	
	if effect_name in effect_timers:
		effect_timers[effect_name].queue_free()
		effect_timers.erase(effect_name)
	
	_invalidate_cache()
	emit_signal("effect_removed", effect_name)

@rpc("any_peer", "call_local", "reliable")
func sync_effect_state(effects_data: Dictionary):
	if is_multiplayer_authority():
		return
	
	status_effects = effects_data.duplicate()
	_invalidate_cache()
#endregion
