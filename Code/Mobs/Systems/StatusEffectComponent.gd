extends Node
class_name StatusEffectComponent

## Handles status effects like stun, confusion, blindness, etc.

#region SIGNALS
signal effect_added(effect_name: String)
signal effect_removed(effect_name: String)
signal effect_updated(effect_name: String, remaining_time: float)
signal movement_speed_changed(modifier: float)
signal stunned(duration: float)
signal stun_ended()
#endregion

#region PROPERTIES
# Core references
var controller: Node = null
var sensory_system = null

# Active effects dictionary
var status_effects: Dictionary = {}

# Effect timers
var effect_timers: Dictionary = {}
#endregion

func initialize(init_data: Dictionary):
	"""Initialize the status effect component"""
	controller = init_data.get("controller")
	sensory_system = init_data.get("sensory_system")

func _process(delta: float):
	"""Update all active status effects"""
	update_status_effects(delta)

#region PUBLIC INTERFACE
func apply_effect(effect_name: String, duration: float, intensity: float = 1.0, data: Dictionary = {}) -> Dictionary:
	"""Apply a status effect"""
	var effect_data = {
		"duration": duration,
		"intensity": intensity,
		"start_time": Time.get_ticks_msec() / 1000.0,
		"data": data
	}
	
	# Check if effect already exists
	var is_new = not has_effect(effect_name)
	
	status_effects[effect_name] = effect_data
	
	# Apply immediate effects
	apply_immediate_effects(effect_name, intensity, data)
	
	# Emit signal
	if is_new:
		emit_signal("effect_added", effect_name)
	else:
		emit_signal("effect_updated", effect_name, duration)
	
	return effect_data

func remove_effect(effect_name: String):
	"""Remove a status effect"""
	if not has_effect(effect_name):
		return
	
	# Clean up the effect
	cleanup_effect(effect_name)
	
	# Remove from dictionary
	status_effects.erase(effect_name)
	
	# Remove timer if exists
	if effect_name in effect_timers:
		effect_timers[effect_name].queue_free()
		effect_timers.erase(effect_name)
	
	emit_signal("effect_removed", effect_name)

func has_effect(effect_name: String) -> bool:
	"""Check if an effect is active"""
	return effect_name in status_effects

func get_effect_intensity(effect_name: String) -> float:
	"""Get intensity of an effect"""
	if has_effect(effect_name):
		return status_effects[effect_name].intensity
	return 0.0

func get_effect_remaining_time(effect_name: String) -> float:
	"""Get remaining time for an effect"""
	if has_effect(effect_name):
		var effect = status_effects[effect_name]
		var current_time = Time.get_ticks_msec() / 1000.0
		var elapsed = current_time - effect.start_time
		return max(0.0, effect.duration - elapsed)
	return 0.0

func has_effect_flag(flag: String) -> bool:
	"""Check if any effect has a specific flag"""
	for effect_name in status_effects:
		var effect_data = get_effect_definition(effect_name)
		if "flags" in effect_data and flag in effect_data.flags:
			return true
	return false

func clear_all_effects():
	"""Remove all status effects"""
	for effect_name in status_effects.keys():
		remove_effect(effect_name)
#endregion

#region SPECIFIC EFFECTS
func apply_stun(duration: float):
	"""Apply stun effect"""
	apply_effect("stunned", duration, 1.0)
	
	# Cancel movement
	if controller.movement_component:
		controller.movement_component.is_stunned = true
		controller.movement_component.stun_remaining = duration
		
		# Cancel any active movement
		if controller.movement_component.is_moving:
			controller.movement_component.is_moving = false
			controller.movement_component.move_progress = 0.0
	
	emit_signal("stunned", duration)

func apply_confusion(duration: float, intensity: float = 1.0):
	"""Apply confusion effect"""
	apply_effect("confused", duration, intensity)
	
	if controller.movement_component:
		controller.movement_component.set_confusion(intensity * 100.0)

func apply_blindness(duration: float):
	"""Apply blindness effect"""
	apply_effect("blinded", duration, 1.0)

func apply_slowness(duration: float, intensity: float = 0.5):
	"""Apply slowness effect"""
	apply_effect("slowed", duration, intensity)

func apply_mute(duration: float):
	"""Apply mute effect"""
	apply_effect("muted", duration, 1.0)

func apply_paralysis(duration: float):
	"""Apply paralysis effect"""
	apply_effect("paralyzed", duration, 1.0)

func apply_weakness(duration: float, intensity: float = 0.5):
	"""Apply weakness effect"""
	apply_effect("weakened", duration, intensity)
#endregion

#region EFFECT PROCESSING
func update_status_effects(delta: float):
	"""Update all active effects"""
	var current_time = Time.get_ticks_msec() / 1000.0
	var effects_to_remove = []
	
	for effect_name in status_effects:
		var effect = status_effects[effect_name]
		var elapsed = current_time - effect.start_time
		
		# Check if expired
		if elapsed >= effect.duration:
			effects_to_remove.append(effect_name)
			continue
		
		# Process ongoing effects
		process_ongoing_effect(effect_name, effect, delta)
		
		# Update UI/feedback
		emit_signal("effect_updated", effect_name, effect.duration - elapsed)
	
	# Remove expired effects
	for effect_name in effects_to_remove:
		remove_effect(effect_name)

func process_ongoing_effect(effect_name: String, effect: Dictionary, delta: float):
	"""Process ongoing effect updates"""
	match effect_name:
		"confused":
			# Confusion is handled by movement component
			pass
		"blinded":
			# Blindness could affect vision system
			pass
		"slowed":
			# Slowness is applied on start
			pass
		"stunned":
			# Stun is handled by movement component
			pass
		"paralyzed":
			# Prevent all actions
			pass
		"weakened":
			# Reduce damage output
			pass
		"poisoned":
			# Damage over time
			if fmod(Time.get_ticks_msec() / 1000.0, 2.0) < delta:
				if controller.has_method("take_damage"):
					controller.take_damage(1.0, "toxin")
#endregion

#region EFFECT DEFINITIONS
func get_effect_definition(effect_name: String) -> Dictionary:
	"""Get definition for an effect"""
	match effect_name:
		"stunned":
			return {
				"name": "Stunned",
				"description": "Unable to act",
				"icon": "effect_stun",
				"flags": ["movement_restricting", "action_restricting"]
			}
		"confused":
			return {
				"name": "Confused",
				"description": "Movement is erratic",
				"icon": "effect_confusion",
				"flags": ["movement_affecting"]
			}
		"blinded":
			return {
				"name": "Blinded",
				"description": "Cannot see",
				"icon": "effect_blind",
				"flags": ["vision_affecting"]
			}
		"slowed":
			return {
				"name": "Slowed",
				"description": "Movement speed reduced",
				"icon": "effect_slow",
				"flags": ["movement_affecting"]
			}
		"muted":
			return {
				"name": "Muted",
				"description": "Cannot speak",
				"icon": "effect_mute",
				"flags": ["speech_affecting"]
			}
		"paralyzed":
			return {
				"name": "Paralyzed",
				"description": "Cannot move or act",
				"icon": "effect_paralyze",
				"flags": ["movement_restricting", "action_restricting"]
			}
		"weakened":
			return {
				"name": "Weakened",
				"description": "Reduced strength",
				"icon": "effect_weak",
				"flags": ["combat_affecting"]
			}
		"poisoned":
			return {
				"name": "Poisoned",
				"description": "Taking damage over time",
				"icon": "effect_poison",
				"flags": ["damage_over_time"]
			}
		"restrained":
			return {
				"name": "Restrained",
				"description": "Movement restricted",
				"icon": "effect_restrain",
				"flags": ["movement_restricting"]
			}
		"buckled":
			return {
				"name": "Buckled",
				"description": "Secured to an object",
				"icon": "effect_buckle",
				"flags": ["movement_restricting"]
			}
		"flying":
			return {
				"name": "Flying",
				"description": "Can move through air",
				"icon": "effect_fly",
				"flags": ["movement_enhancing"]
			}
		"magboots":
			return {
				"name": "Magboots Active",
				"description": "Magnetic boots prevent slipping",
				"icon": "effect_magboot",
				"flags": ["slip_immunity"]
			}
		_:
			return {
				"name": effect_name.capitalize(),
				"description": "Unknown effect",
				"icon": "effect_unknown",
				"flags": []
			}
#endregion

#region IMMEDIATE EFFECTS
func apply_immediate_effects(effect_name: String, intensity: float, data: Dictionary):
	"""Apply immediate effects when status is added"""
	match effect_name:
		"confused":
			if sensory_system:
				sensory_system.display_message("You feel confused!")
		
		"blinded":
			if sensory_system:
				sensory_system.display_message("You can't see!")
		
		"slowed":
			if controller.movement_component:
				controller.movement_component.set_movement_modifier(1.0 - intensity)
			emit_signal("movement_speed_changed", 1.0 - intensity)
			if sensory_system:
				sensory_system.display_message("You feel sluggish!")
		
		"muted":
			if sensory_system:
				sensory_system.display_message("You can't speak!")
		
		"paralyzed":
			if sensory_system:
				sensory_system.display_message("You can't move!")
			# Apply movement restriction
			if controller.movement_component:
				controller.movement_component.set_movement_modifier(0.0)
		
		"weakened":
			if sensory_system:
				sensory_system.display_message("You feel weak!")
		
		"poisoned":
			if sensory_system:
				sensory_system.display_message("You feel sick!")
		
		"restrained":
			if sensory_system:
				sensory_system.display_message("You're restrained and can't move!")

func cleanup_effect(effect_name: String):
	"""Clean up when removing an effect"""
	match effect_name:
		"slowed":
			if controller.movement_component:
				controller.movement_component.set_movement_modifier(1.0)
			emit_signal("movement_speed_changed", 1.0)
		
		"confused":
			if controller.movement_component:
				controller.movement_component.set_confusion(0.0)
			if sensory_system:
				sensory_system.display_message("Your mind clears.")
		
		"blinded":
			if sensory_system:
				sensory_system.display_message("You can see again!")
		
		"stunned":
			if controller.movement_component:
				controller.movement_component.is_stunned = false
			emit_signal("stun_ended")
		
		"paralyzed":
			if controller.movement_component:
				controller.movement_component.set_movement_modifier(1.0)
			if sensory_system:
				sensory_system.display_message("You can move again!")
#endregion

#region HELPERS
func get_all_active_effects() -> Array:
	"""Get list of all active effects"""
	var effects = []
	for effect_name in status_effects:
		var effect_def = get_effect_definition(effect_name)
		effect_def["remaining_time"] = get_effect_remaining_time(effect_name)
		effect_def["intensity"] = get_effect_intensity(effect_name)
		effects.append(effect_def)
	return effects

func get_movement_modifier() -> float:
	"""Get total movement speed modifier from effects"""
	var modifier = 1.0
	
	if has_effect("slowed"):
		modifier *= (1.0 - get_effect_intensity("slowed"))
	
	if has_effect("paralyzed"):
		modifier = 0.0
	
	return modifier

func can_act() -> bool:
	"""Check if can perform actions"""
	return not has_effect("stunned") and not has_effect("paralyzed")

func can_move() -> bool:
	"""Check if can move"""
	return not has_effect("stunned") and not has_effect("paralyzed") and not has_effect("restrained") and not has_effect("buckled")

func can_speak() -> bool:
	"""Check if can speak"""
	return not has_effect("muted")
#endregion
