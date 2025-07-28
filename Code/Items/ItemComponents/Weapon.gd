extends Item
class_name Weapon

signal weapon_fired(target, user)
signal weapon_reloaded(user)
signal weapon_safety_toggled(enabled, user)
signal weapon_mode_changed(new_mode, user)

enum WeaponType {
	MELEE,
	RANGED,
	THROWN
}

enum SafetyState {
	OFF,
	ON,
	LOCKED
}

# Basic weapon properties
@export var weapon_type: WeaponType = WeaponType.MELEE
@export var weapon_damage: float = 10.0
@export var weapon_accuracy: float = 85.0
@export var weapon_range: float = 1.0
@export var weapon_sound: AudioStream
@export var safety_enabled: bool = true
@export var current_safety_state: SafetyState = SafetyState.ON
@export var requires_wielding: bool = false

# Weapon condition
@export var max_durability: float = 100.0
@export var current_durability: float = 100.0
@export var jam_chance: float = 0.0
@export var maintenance_required: bool = false

# Usage tracking
var last_used_time: float = 0.0
var total_uses: int = 0
var user_skill_bonus: float = 0.0

# Combat flags
var is_jammed: bool = false
var is_overheating: bool = false
var cooldown_timer: float = 0.0

func _ready():
	super._ready()
	entity_type = "weapon"
	
	# Set weapon-specific item properties
	if weapon_type == WeaponType.RANGED:
		w_class = 3  # Medium size for most guns
	elif weapon_type == WeaponType.MELEE:
		w_class = 2  # Small to medium for melee weapons
	
	# Add to weapon group
	add_to_group("weapons")
	
	# Initialize weapon state
	update_weapon_condition()

func _process(delta):
	# Handle cooldowns
	if cooldown_timer > 0:
		cooldown_timer -= delta
	
	# Handle overheating recovery
	if is_overheating:
		update_heat_state(delta)

func can_use_weapon(user) -> bool:
	"""Check if the weapon can be used by the given user"""
	if not user:
		return false
	
	# Check if weapon is jammed
	if is_jammed:
		return false
	
	# Check if weapon needs wielding
	if requires_wielding and not is_wielded():
		return false
	
	# Check if weapon is on cooldown
	if cooldown_timer > 0:
		return false
	
	# Check safety
	if current_safety_state == SafetyState.ON:
		return false
	
	# Check durability
	if current_durability <= 0:
		return false
	
	return true

func is_wielded() -> bool:
	"""Check if the weapon is currently wielded with both hands"""
	if not inventory_owner:
		return false
	
	# Check if user has both hands on this weapon
	# This would need to be implemented based on your inventory system
	var inventory_system = inventory_owner.get_node_or_null("InventorySystem")
	if not inventory_system:
		return false
	
	var left_item = inventory_system.get_item_in_slot(inventory_system.EquipSlot.LEFT_HAND)
	var right_item = inventory_system.get_item_in_slot(inventory_system.EquipSlot.RIGHT_HAND)
	
	# For now, just check if it's in one hand (basic implementation)
	return left_item == self or right_item == self

func use_weapon(user, target = null) -> bool:
	"""Primary weapon use function"""
	if not can_use_weapon(user):
		handle_use_failure(user)
		return false
	
	var success = perform_weapon_action(user, target)
	
	if success:
		post_use_processing(user, target)
		emit_signal("weapon_fired", target, user)
	
	return success

func perform_weapon_action(user, target) -> bool:
	"""Override this in subclasses for specific weapon behavior"""
	play_weapon_sound()
	apply_durability_loss()
	return true

func post_use_processing(user, target):
	"""Handle post-use effects"""
	last_used_time = Time.get_ticks_msec() / 1000.0
	total_uses += 1
	cooldown_timer = 1.0 / attack_speed
	
	# Check for jamming
	if randf() < jam_chance:
		jam_weapon(user)

func handle_use_failure(user):
	"""Handle what happens when weapon use fails"""
	if is_jammed:
		show_message_to_user(user, "The " + item_name + " is jammed!")
		play_jam_sound()
	elif current_safety_state == SafetyState.ON:
		show_message_to_user(user, "The safety is on!")
		play_safety_sound()
	elif cooldown_timer > 0:
		show_message_to_user(user, "The " + item_name + " is still cooling down!")
	elif requires_wielding and not is_wielded():
		show_message_to_user(user, "You need to wield the " + item_name + " with both hands!")

func toggle_safety(user) -> bool:
	"""Toggle weapon safety on/off"""
	if current_safety_state == SafetyState.LOCKED:
		show_message_to_user(user, "The safety is locked!")
		return false
	
	if current_safety_state == SafetyState.ON:
		current_safety_state = SafetyState.OFF
		show_message_to_user(user, "You turn the safety off.")
	else:
		current_safety_state = SafetyState.ON
		show_message_to_user(user, "You turn the safety on.")
	
	play_safety_sound()
	emit_signal("weapon_safety_toggled", current_safety_state == SafetyState.ON, user)
	return true

func jam_weapon(user):
	"""Jam the weapon"""
	is_jammed = true
	if user:
		show_message_to_user(user, "The " + item_name + " jams!")
	play_jam_sound()

func unjam_weapon(user) -> bool:
	"""Attempt to unjam the weapon"""
	if not is_jammed:
		return false
	
	# This could be enhanced with skill checks
	var unjam_chance = 70.0 + user_skill_bonus
	
	if randf() * 100.0 < unjam_chance:
		is_jammed = false
		show_message_to_user(user, "You successfully unjam the " + item_name + ".")
		return true
	else:
		show_message_to_user(user, "You fail to unjam the " + item_name + ".")
		return false

func apply_durability_loss(amount: float = 1.0):
	"""Reduce weapon durability"""
	current_durability = max(0, current_durability - amount)
	update_weapon_condition()

func repair_weapon(amount: float):
	"""Repair weapon durability"""
	current_durability = min(max_durability, current_durability + amount)
	update_weapon_condition()
	
	# Clear maintenance flag if fully repaired
	if current_durability >= max_durability * 0.9:
		maintenance_required = false

func update_weapon_condition():
	"""Update weapon condition based on durability"""
	var condition_percent = current_durability / max_durability
	
	if condition_percent < 0.2:
		jam_chance = 0.15
		maintenance_required = true
	elif condition_percent < 0.5:
		jam_chance = 0.05
		maintenance_required = true
	else:
		jam_chance = 0.01
		maintenance_required = false

func update_heat_state(delta: float):
	"""Handle weapon overheating recovery - override in subclasses"""
	pass

func play_weapon_sound():
	"""Play the weapon's primary sound effect"""
	if weapon_sound and inventory_owner:
		play_audio(weapon_sound, -5)

func play_safety_sound():
	"""Play safety toggle sound"""
	if inventory_owner:
		play_audio(preload("res://Sound/machines/Click_standard.wav"), -10)

func play_jam_sound():
	"""Play jam sound"""
	if inventory_owner:
		play_audio(preload("res://Sound/weapons/gun_empty.ogg"), -5)

func show_message_to_user(user, message: String):
	"""Show a message to the user"""
	if user and user.has_method("show_message"):
		user.show_message(message)
	elif user:
		print(user.entity_name + ": " + message)

# Interaction overrides
func interact(user) -> bool:
	"""Handle basic interaction with weapon"""
	if current_safety_state == SafetyState.ON:
		toggle_safety(user)
		return true
	
	return super.interact(user)

func attack_self(user):
	"""Handle self-interaction (like safety toggle)"""
	toggle_safety(user)
	return true

func examine(user) -> String:
	"""Provide detailed weapon examination"""
	var text = super.examine(user)
	
	text += "\nWeapon Condition: "
	var condition_percent = current_durability / max_durability * 100
	
	if condition_percent >= 90:
		text += "Excellent"
	elif condition_percent >= 70:
		text += "Good"
	elif condition_percent >= 50:
		text += "Fair"
	elif condition_percent >= 30:
		text += "Poor"
	else:
		text += "Terrible"
	
	text += "\nSafety: " + ("ON" if current_safety_state == SafetyState.ON else "OFF")
	
	if is_jammed:
		text += "\nThe weapon appears to be jammed."
	
	if maintenance_required:
		text += "\nThis weapon needs maintenance."
	
	return text

# Serialization
func serialize() -> Dictionary:
	var data = super.serialize()
	data.merge({
		"weapon_type": weapon_type,
		"weapon_damage": weapon_damage,
		"weapon_accuracy": weapon_accuracy,
		"weapon_range": weapon_range,
		"current_safety_state": current_safety_state,
		"current_durability": current_durability,
		"is_jammed": is_jammed,
		"maintenance_required": maintenance_required,
		"total_uses": total_uses
	})
	return data

func deserialize(data: Dictionary):
	super.deserialize(data)
	if "weapon_type" in data: weapon_type = data.weapon_type
	if "weapon_damage" in data: weapon_damage = data.weapon_damage
	if "weapon_accuracy" in data: weapon_accuracy = data.weapon_accuracy
	if "weapon_range" in data: weapon_range = data.weapon_range
	if "current_safety_state" in data: current_safety_state = data.current_safety_state
	if "current_durability" in data: current_durability = data.current_durability
	if "is_jammed" in data: is_jammed = data.is_jammed
	if "maintenance_required" in data: maintenance_required = data.maintenance_required
	if "total_uses" in data: total_uses = data.total_uses
	
	update_weapon_condition()
