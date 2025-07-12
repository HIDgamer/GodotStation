extends Node
class_name HealthConnector

# === SIGNALS ===
signal health_state_changed(new_state)
signal bleeding_started
signal bleeding_stopped
signal damage_taken(amount, type)

# === REFERENCES ===
var entity = null
var health_system = null

# === MEMBER VARIABLES ===
var original_methods = {}
var debug_mode = false

func _ready():
	entity = get_parent()
	health_system = get_node("HealthSystem")
	
	# Make sure health system exists
	if not health_system:
		health_system = get_parent().get_node_or_null("HealthSystem")
		if not health_system:
			push_error("HealthConnector: No HealthSystem found. This component won't function properly.")
			return
	
	# Connect signals from health system
	connect_health_system()
	
	# Hook into entity methods
	install_hooks()
	
	if debug_mode:
		print("HealthConnector: Successfully initialized and connected to HealthSystem")

func connect_health_system():
	if not health_system:
		return
		
	# Connect to health system signals
	health_system.health_changed.connect(_on_health_changed)
	health_system.damage_taken.connect(_on_damage_taken)
	health_system.status_effect_added.connect(_on_status_effect_added)
	health_system.status_effect_removed.connect(_on_status_effect_removed)
	health_system.died.connect(_on_entity_died)
	health_system.revived.connect(_on_entity_revived)
	health_system.entered_critical.connect(_on_entered_critical)
	health_system.exited_critical.connect(_on_exited_critical)
	health_system.blood_level_changed.connect(_on_blood_level_changed)

func install_hooks():
	# Save original methods for later reference
	backup_original_methods()
	
	# Install hooks to redirect methods to the health system
	install_method_hook("apply_damage", "_hook_apply_damage")
	install_method_hook("take_damage", "_hook_take_damage")
	install_method_hook("heal_limb_damage", "_hook_heal_limb_damage")
	install_method_hook("take_limb_damage", "_hook_take_limb_damage")
	install_method_hook("adjustBruteLoss", "_hook_adjust_brute_loss")
	install_method_hook("adjustFireLoss", "_hook_adjust_fire_loss")
	install_method_hook("set_bleeding", "_hook_set_bleeding")
	install_method_hook("stun", "_hook_stun")
	install_method_hook("get_health", "_hook_get_health")

func backup_original_methods():
	var methods_to_backup = [
		"apply_damage", "take_damage", "heal_limb_damage", 
		"take_limb_damage", "adjustBruteLoss", "adjustFireLoss",
		"set_bleeding", "stun", "get_health"
	]
	
	for method in methods_to_backup:
		if entity.has_method(method):
			original_methods[method] = true

# === METHOD HOOKS ===
func install_method_hook(original_method: String, hook_method: String):
	# We can't actually replace methods in GDScript like we can in other languages,
	# so this is more of a logical replacement - we handle the connection through signals
	
	# Instead, we're going to check if the method exists and mark it in our registry
	if entity.has_method(original_method):
		if debug_mode:
			print("HealthConnector: Installed hook for " + original_method)
	else:
		# Method doesn't exist, we'll just add it through our hook system
		if debug_mode:
			print("HealthConnector: Added new method " + original_method)
	
	# The actual "hooking" happens when the entity calls these methods,
	# and we'll have to handle them in our signal connections

# Method hooks that act as redirects to the health system
func _hook_apply_damage(amount, damage_type, zone = null, armor_type = null, updating_health = true):
	if not health_system:
		return 0
	
	var type_mapping = {
		"brute": health_system.DamageType.BRUTE,
		"burn": health_system.DamageType.BURN,
		"tox": health_system.DamageType.TOXIN,
		"toxin": health_system.DamageType.TOXIN,
		"oxy": health_system.DamageType.OXYGEN,
		"oxygen": health_system.DamageType.OXYGEN,
		"clone": health_system.DamageType.CLONE,
		"brain": health_system.DamageType.BRAIN,
		"stamina": health_system.DamageType.STAMINA
	}
	
	var damage_type_enum = type_mapping.get(str(damage_type).to_lower(), health_system.DamageType.BRUTE)
	return health_system.apply_damage(amount, damage_type_enum, 0, zone)

func _hook_take_damage(amount, damage_type = "brute", zone = null):
	return _hook_apply_damage(amount, damage_type, zone)

func _hook_heal_limb_damage(limb, brute_amount, burn_amount, update_health = true):
	if not health_system:
		return 0
	
	return health_system.heal_limb_damage(limb, brute_amount, burn_amount)

func _hook_take_limb_damage(limb, brute_amount, burn_amount, update_health = true):
	if not health_system:
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
	
	health_system.adjustBruteLoss(amount, update_health)

func _hook_adjust_fire_loss(amount, update_health = true):
	if not health_system:
		return
	
	health_system.adjustFireLoss(amount, update_health)

func _hook_set_bleeding(enabled, intensity = 1.0):
	if not health_system:
		return
	
	if enabled:
		health_system.set_bleeding_rate(intensity)
	else:
		health_system.set_bleeding_rate(0)

func _hook_stun(duration):
	if not health_system:
		return
	
	health_system.add_status_effect("stunned", duration)

func _hook_get_health():
	if not health_system:
		return 100.0
	
	return health_system.health

# === HANDLER METHODS FOR EXTERNAL CALLS ===
# These methods allow other scripts to call the health system through the entity

# General API for the entity to access health system functionality
func external_call(method_name: String, args = []):
	if not health_system:
		push_warning("HealthConnector: No health system available for external call: " + method_name)
		return null
	
	if not health_system.has_method(method_name):
		push_warning("HealthConnector: Health system doesn't have method: " + method_name)
		return null
	
	# Call the method with the provided arguments
	if args is Array:
		match args.size():
			0: return health_system.call(method_name)
			1: return health_system.call(method_name, args[0])
			2: return health_system.call(method_name, args[0], args[1])
			3: return health_system.call(method_name, args[0], args[1], args[2])
			4: return health_system.call(method_name, args[0], args[1], args[2], args[3])
			_: return health_system.callv(method_name, args)
	else:
		# Single argument that's not an array
		return health_system.call(method_name, args)

# === SIGNAL HANDLERS ===
func _on_health_changed(new_health, max_health):
	# Update any UI elements that display health
	if entity.get_node_or_null("SensorySystem"):
		var health_percent = (new_health / max_health) * 100
		entity.get_node("SensorySystem").update_health_display(health_percent)
	
	# Update sprite system if health is critically low
	if new_health < max_health * 0.25 and entity.get_node_or_null("SpriteSystem"):
		if entity.get_node("SpriteSystem").has_method("set_critical_condition"):
			entity.get_node("SpriteSystem").set_critical_condition(true)

func _on_damage_taken(amount, type):
	# Forward the signal
	damage_taken.emit(amount, type)
	
	# Play appropriate sound
	if entity.get_node_or_null("AudioSystem"):
		var sound_name = "hit"
		match type:
			health_system.DamageType.BURN: sound_name = "burn"
			health_system.DamageType.TOXIN: sound_name = "tox"
			health_system.DamageType.OXYGEN: sound_name = "gasp"
		
		entity.get_node("AudioSystem").play_positioned_sound(sound_name, entity.position, 0.4)
	
	# Display damage message
	if entity.get_node_or_null("SensorySystem"):
		var type_name = "damage"
		match type:
			health_system.DamageType.BRUTE: type_name = "brute"
			health_system.DamageType.BURN: type_name = "burn"
			health_system.DamageType.TOXIN: type_name = "toxic"
			health_system.DamageType.OXYGEN: type_name = "oxygen"
			health_system.DamageType.CLONE: type_name = "cellular"
			health_system.DamageType.BRAIN: type_name = "brain"
			health_system.DamageType.STAMINA: type_name = "stamina"
		
		entity.get_node("SensorySystem").display_message("You take " + str(round(amount)) + " " + type_name + " damage!")
	
	# Apply visual effects for major damage
	if amount > 20 and entity.get_node_or_null("SpriteSystem"):
		if entity.get_node("SpriteSystem").has_method("flash_damage"):
			entity.get_node("SpriteSystem").flash_damage()

func _on_status_effect_added(effect_name, duration):
	# Pass effect to entity's status system
	if entity.has_method("add_status_effect"):
		entity.add_status_effect(effect_name, duration)
	
	# Handle special effects
	match effect_name:
		"stunned":
			if entity.has_method("stun"):
				entity.stun(duration)
		"bleeding":
			bleeding_started.emit()
			if entity.get_node_or_null("SpriteSystem") and entity.get_node("SpriteSystem").has_method("start_bleeding_effect"):
				entity.get_node("SpriteSystem").start_bleeding_effect()
		"unconscious":
			if entity.has_method("set_state"):
				entity.set_state(entity.MovementState.STUNNED)
			
			if entity.has_method("set_resting"):
				entity.set_resting(true)
		"slowed":
			if entity.has_method("add_movement_modifier"):
				entity.add_movement_modifier("health_slowed", 0.5)

func _on_status_effect_removed(effect_name):
	# Remove effect from entity's status system
	if entity.has_method("remove_status_effect"):
		entity.remove_status_effect(effect_name)
	
	# Handle special effects
	match effect_name:
		"stunned":
			if entity.has_method("set_state") and entity.current_state == entity.MovementState.STUNNED:
				entity.set_state(entity.MovementState.IDLE)
		"bleeding":
			bleeding_stopped.emit()
			if entity.get_node_or_null("SpriteSystem") and entity.get_node("SpriteSystem").has_method("stop_bleeding_effect"):
				entity.get_node("SpriteSystem").stop_bleeding_effect()
		"unconscious":
			if health_system.current_state == health_system.HealthState.ALIVE:
				if entity.has_method("set_state"):
					entity.set_state(entity.MovementState.IDLE)
		"slowed":
			if entity.has_method("remove_movement_modifier"):
				entity.remove_movement_modifier("health_slowed")

func _on_entity_died(cause_of_death):
	# Update state in entity
	if entity.has_method("set_state"):
		entity.set_state(entity.MovementState.STUNNED)
	
	# Update sprite system for death
	if entity.get_node_or_null("SpriteSystem") and entity.get_node("SpriteSystem").has_method("update_death_state"):
		entity.get_node("SpriteSystem").update_death_state(true)
	
	# Drop all items
	if entity.get_node_or_null("InventorySystem") and entity.get_node("InventorySystem").has_method("drop_all_items"):
		entity.get_node("InventorySystem").drop_all_items()
	
	# Display death message
	if entity.get_node_or_null("SensorySystem"):
		entity.get_node("SensorySystem").display_message("You have died from " + cause_of_death + ".", "red")
	
	# Emit state change signal
	health_state_changed.emit("dead")

func _on_entity_revived():
	# Update state in entity
	if entity.has_method("set_state"):
		entity.set_state(entity.MovementState.IDLE)
	
	# Update sprite system for revival
	if entity.get_node_or_null("SpriteSystem") and entity.get_node("SpriteSystem").has_method("update_death_state"):
		entity.get_node("SpriteSystem").update_death_state(false)
	
	# Display revival message
	if entity.get_node_or_null("SensorySystem"):
		entity.get_node("SensorySystem").display_message("You have been revived!", "green")
	
	# Emit state change signal
	health_state_changed.emit("alive")

func _on_entered_critical():
	# Update state in entity
	if entity.has_method("set_state"):
		entity.set_state(entity.MovementState.STUNNED)
	
	# Update sprite system for critical state
	if entity.get_node_or_null("SpriteSystem") and entity.get_node("SpriteSystem").has_method("set_critical_condition"):
		entity.get_node("SpriteSystem").set_critical_condition(true)
	
	# Display critical message
	if entity.get_node_or_null("SensorySystem"):
		entity.get_node("SensorySystem").display_message("You are critically injured and need medical attention!", "red")
	
	# Emit state change signal
	health_state_changed.emit("critical")

func _on_exited_critical():
	# Update state in entity if not stunned
	if entity.has_method("set_state") and not health_system.status_effects.has("stunned"):
		entity.set_state(entity.MovementState.IDLE)
	
	# Update sprite system for normal state
	if entity.get_node_or_null("SpriteSystem") and entity.get_node("SpriteSystem").has_method("set_critical_condition"):
		entity.get_node("SpriteSystem").set_critical_condition(false)
	
	# Display recovery message
	if entity.get_node_or_null("SensorySystem"):
		entity.get_node("SensorySystem").display_message("Your condition has stabilized.", "green")
	
	# Emit state change signal
	health_state_changed.emit("alive")

func _on_blood_level_changed(new_amount, max_amount):
	# Update blood level visuals
	if new_amount < health_system.BLOOD_VOLUME_SAFE and entity.get_node_or_null("SpriteSystem"):
		if entity.get_node("SpriteSystem").has_method("set_pallor"):
			var pallor_amount = 1.0 - (new_amount / max_amount)
			entity.get_node("SpriteSystem").set_pallor(pallor_amount)
	
	# Display relevant messages for severe blood loss
	if entity.get_node_or_null("SensorySystem"):
		if new_amount < health_system.BLOOD_VOLUME_BAD and new_amount > health_system.BLOOD_VOLUME_SURVIVE:
			entity.get_node("SensorySystem").display_message("You feel weak from blood loss.", "red")
		elif new_amount <= health_system.BLOOD_VOLUME_SURVIVE:
			entity.get_node("SensorySystem").display_message("You are critically low on blood!", "red")

# === PUBLIC API ===
# Methods that can be called from the entity or other scripts

# Apply damage to the character
func apply_damage(amount, damage_type, limb = null):
	return _hook_apply_damage(amount, damage_type, limb)

# Heal the character
func heal_damage(amount, damage_type = "brute"):
	if not health_system:
		return 0
	
	var type_mapping = {
		"brute": health_system.DamageType.BRUTE,
		"burn": health_system.DamageType.BURN,
		"tox": health_system.DamageType.TOXIN,
		"toxin": health_system.DamageType.TOXIN,
		"oxy": health_system.DamageType.OXYGEN,
		"oxygen": health_system.DamageType.OXYGEN
	}
	
	var damage_type_enum = type_mapping.get(str(damage_type).to_lower(), health_system.DamageType.BRUTE)
	
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
	
	return amount

# Set bleeding state
func set_bleeding(enabled, intensity = 1.0):
	return _hook_set_bleeding(enabled, intensity)

# Apply stun effect
func stun(duration):
	return _hook_stun(duration)

# Get current health
func get_health():
	return _hook_get_health()

# Get current health percentage
func get_health_percent():
	if not health_system:
		return 1.0
	
	return health_system.get_health_percent()

# Check if character is dead
func is_dead():
	if not health_system:
		return false
	
	return health_system.current_state == health_system.HealthState.DEAD

# Check if character is in critical condition
func is_critical():
	if not health_system:
		return false
	
	return health_system.current_state == health_system.HealthState.CRITICAL

# Heal all damage (full heal)
func full_heal():
	if not health_system:
		return false
	
	return health_system.full_heal()

# Revive character
func revive():
	if not health_system:
		return false
	
	return health_system.revive()

# Toggle god mode
func toggle_godmode(enabled = null):
	if not health_system:
		return false
	
	return health_system.toggle_godmode(enabled)

# Get full status report
func get_status_report():
	if not health_system:
		return {}
	
	return health_system.get_status_report()
