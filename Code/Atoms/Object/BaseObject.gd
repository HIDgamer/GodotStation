extends Node2D
class_name BaseObject

# Object behavior flags
enum ObjectFlags {
	IN_USE = 1,
	CAN_BE_HIT = 2,
	PROJ_IGNORE_DENSITY = 4,
	LIGHT_CAN_BE_SHUT = 8,
	BLOCKS_CONSTRUCTION = 16,
	IGNORE_DENSITY = 32
}

# Resistance flags
enum ResistanceFlags {
	INDESTRUCTIBLE = 1,
	UNACIDABLE = 2,
	ON_FIRE = 4,
	XENO_DAMAGEABLE = 8,
	CRUSHER_IMMUNE = 16,
	PLASMACUTTER_IMMUNE = 32,
	PROJECTILE_IMMUNE = 64
}

# Core properties
var obj_name: String = "object"
var obj_desc: String = "An object."
var obj_flags: int = ObjectFlags.CAN_BE_HIT
var resistance_flags: int = 0
var obj_integrity: float = 100.0
var max_integrity: float = 100.0
var integrity_failure: float = 0.0
var anchored: bool = false
var throwforce: int = 1
var throw_speed: int = 3
var throw_range: int = 7
var hit_sound: AudioStream = null
var destroy_sound: AudioStream = null
var layer_z: int = 0
var allow_pass_flags: int = 0
var last_thrower = null

# Entity properties
@export var entity_type: String = "object"
@export var entity_dense: bool = true
@export var entity_name: String = ""
@export var description: String = ""
@export var pickupable: bool = false
@export var no_pull: bool = false
@export var grabbed_by = null
@export var is_lying: bool = false
@export var is_stunned: bool = false
@export var health: float = 100.0
@export var max_health: float = 100.0
@export var active_equipment: Dictionary = {}

# Armor values
var soft_armor = {
	"melee": 0, "bullet": 0, "laser": 0, "energy": 0, "bomb": 0,
	"bio": 100, "rad": 0, "fire": 0, "acid": 0
}

var hard_armor = {
	"melee": 0, "bullet": 0, "laser": 0, "energy": 0, "bomb": 0,
	"bio": 0, "rad": 0, "fire": 0, "acid": 0
}

# Physics properties
var velocity: Vector2 = Vector2.ZERO
var angular_velocity: float = 0.0
var gravity_scale: float = 1.0
var bounce_factor: float = 0.3
var friction: float = 0.1
var air_resistance: float = 0.01
var is_physically_simulated: bool = false
var landed: bool = true

# Signals
signal integrity_changed(old_value, new_value)
signal destroyed(disassembled)
signal anchored_changed(new_anchored_state)
signal interacted_with(user)
signal landed_after_throw(position)
signal object_hit(hit_by, force)

func _init():
	if obj_integrity == null:
		obj_integrity = max_integrity
	
	if entity_name == "":
		entity_name = obj_name

func _ready():
	add_to_group("clickable_entities")
	add_to_group("entities")
	
	if has_flag(resistance_flags, ResistanceFlags.INDESTRUCTIBLE):
		add_to_group("indestructible")
	
	if has_flag(resistance_flags, ResistanceFlags.XENO_DAMAGEABLE):
		add_to_group("xeno_damageable")
	
	if is_physically_simulated and not has_node("CollisionShape2D"):
		setup_collision()

func _physics_process(delta):
	if not is_physically_simulated or landed:
		return
	
	# Apply gravity and air resistance
	velocity.y += 9.8 * gravity_scale * delta
	velocity = velocity.lerp(Vector2.ZERO, air_resistance * delta)
	
	# Move with collision detection
	var collision = move_and_collide(velocity * delta)
	
	# Handle rotation
	if angular_velocity != 0:
		rotation_degrees += angular_velocity * delta
		angular_velocity = lerp(angular_velocity, 0.0, friction * delta * 2)
	
	# Handle collision
	if collision:
		velocity = velocity.bounce(collision.get_normal()) * bounce_factor
		angular_velocity *= bounce_factor
		
		if velocity.length() < 20.0 and abs(angular_velocity) < 10.0:
			land()
	
	# Land if moving slowly
	if velocity.length() < 10.0 and abs(angular_velocity) < 5.0:
		land()

func has_flag(flags: int, flag: int) -> bool:
	return (flags & flag) != 0

func set_flag(flags_var: String, flag: int, enabled: bool = true) -> void:
	if enabled:
		set(flags_var, get(flags_var) | flag)
	else:
		set(flags_var, get(flags_var) & ~flag)

func modify_by_armor(damage: float, armor_type: String, penetration: float = 0) -> float:
	var armor_value = soft_armor.get(armor_type, 0)
	armor_value = max(0, armor_value - penetration)
	var damage_reduction = min(armor_value / 100.0, 0.9)
	return damage * (1 - damage_reduction)

func repair_damage(repair_amount: float, repairer = null) -> void:
	if obj_integrity >= max_integrity:
		return
	
	var old_integrity = obj_integrity
	repair_amount = min(repair_amount, max_integrity - obj_integrity)
	obj_integrity += repair_amount
	
	emit_signal("integrity_changed", old_integrity, obj_integrity)
	update_appearance()

func obj_break(damage_flag: String = "") -> void:
	pass

func obj_destruction(damage_amount: float, damage_type: String, damage_flag: String, attacker = null) -> void:
	if destroy_sound:
		play_audio(destroy_sound)
	
	emit_signal("destroyed", false)
	queue_free()

func deconstruct(disassembled: bool = true, disassembler = null) -> void:
	emit_signal("destroyed", disassembled)
	queue_free()

func set_anchored(anchor_value: bool) -> void:
	if anchored == anchor_value:
		return
	
	anchored = anchor_value
	emit_signal("anchored_changed", anchored)

func ex_act(severity: int) -> void:
	if has_flag(resistance_flags, ResistanceFlags.INDESTRUCTIBLE):
		return
	
	var damage_values = [1000, randf_range(100, 250), randf_range(10, 90), randf_range(5, 45)]
	if severity >= 1 and severity <= 4:
		take_damage(damage_values[severity - 1], "bomb")

func hitby(thrown_item, speed: float = 5) -> void:
	var tforce = thrown_item.throwforce if "throwforce" in thrown_item else 0
	take_damage(tforce, "brute", "melee", true, 0.0)
	emit_signal("object_hit", thrown_item, tforce)

func attackby(item, user, params = null) -> bool:
	"""Handle item interactions"""
	if not item or not user:
		return false
	
	# Let item handle interaction first
	if item.has_method("attack"):
		return item.attack(self, user)
	
	# Handle based on item properties
	if "tool_behaviour" in item:
		return handle_tool_interaction(item, user)
	elif "item_type" in item:
		return handle_item_type_interaction(item, user)
	else:
		return handle_generic_interaction(item, user)

func attack_hand(user, params = null) -> bool:
	"""Handle hand interactions"""
	if not user:
		return false
	
	var user_intent = get_user_intent(user)
	
	match user_intent:
		0: return handle_help_interaction(user)
		1: return handle_disarm_interaction(user)
		2: return handle_grab_interaction(user)
		3: return handle_harm_interaction(user)
		_: return handle_help_interaction(user)

func get_user_intent(user) -> int:
	if "intent" in user:
		return user.intent
	elif user.has_method("get_intent"):
		return user.get_intent()
	else:
		return 0

func handle_tool_interaction(tool, user) -> bool:
	"""Handle tool-based interactions"""
	match tool.tool_behaviour:
		"weapon":
			if get_user_intent(user) == 3:  # HARM
				return handle_weapon_attack(tool, user)
			else:
				return handle_tool_usage(tool, user)
		"medical":
			return handle_medical_treatment(tool, user)
		_:
			return handle_tool_usage(tool, user)

func handle_item_type_interaction(item, user) -> bool:
	"""Handle interactions based on item type"""
	match item.item_type:
		"food":
			return handle_food_interaction(item, user)
		"drink":
			return handle_drink_interaction(item, user)
		"chemical":
			return handle_chemical_interaction(item, user)
		_:
			return handle_generic_interaction(item, user)

func handle_weapon_attack(weapon, attacker) -> bool:
	"""Handle weapon attacks"""
	var damage = weapon.get("force", 5.0)
	take_damage(damage, "brute")
	
	var weapon_name = get_entity_name(weapon)
	var attacker_name = get_entity_name(attacker)
	
	show_interaction_message(attacker_name + " hits " + get_entity_name(self) + " with " + weapon_name + "!")
	play_hit_sound()
	
	return true

func handle_medical_treatment(medical_item, user) -> bool:
	"""Handle medical item usage"""
	if medical_item.has_method("treat_patient"):
		return medical_item.treat_patient(self, user)
	
	if entity_type in ["character", "mob"]:
		var health_system = get_node_or_null("HealthSystem")
		if health_system and health_system.has_method("apply_healing"):
			health_system.apply_healing(10.0, "medical")
			show_interaction_message("Medical treatment applied.")
			return true
	
	show_user_message(user, "You can't use that medically on " + get_entity_name(self) + ".")
	return false

func handle_tool_usage(tool, user) -> bool:
	"""Handle general tool usage"""
	var tool_name = get_entity_name(tool)
	show_user_message(user, "You use " + tool_name + " on " + get_entity_name(self) + ".")
	return true

func handle_food_interaction(food_item, user) -> bool:
	"""Handle food items"""
	if entity_type not in ["character", "mob"]:
		show_user_message(user, "You can't feed that!")
		return false
	
	var can_feed = (user == self) or is_stunned or is_lying
	if not can_feed:
		show_user_message(user, "They won't let you feed them!")
		return false
	
	if food_item.has_method("feed_to"):
		return food_item.feed_to(self, user)
	
	show_user_message(user, "You feed " + get_entity_name(self) + " the " + get_entity_name(food_item) + ".")
	return true

func handle_drink_interaction(drink_item, user) -> bool:
	"""Handle drink items"""
	if entity_type not in ["character", "mob"]:
		show_user_message(user, "You can't give that a drink!")
		return false
	
	var can_drink = (user == self) or is_stunned
	if not can_drink:
		show_user_message(user, "They won't let you give them a drink!")
		return false
	
	if drink_item.has_method("give_drink_to"):
		return drink_item.give_drink_to(self, user)
	
	show_user_message(user, "You give " + get_entity_name(self) + " the " + get_entity_name(drink_item) + ".")
	return true

func handle_chemical_interaction(chemical_item, user) -> bool:
	"""Handle chemical items"""
	if chemical_item.has_method("apply_chemical_to"):
		return chemical_item.apply_chemical_to(self, user)
	
	show_user_message(user, "You apply " + get_entity_name(chemical_item) + " to " + get_entity_name(self) + ".")
	return true

func handle_generic_interaction(item, user) -> bool:
	"""Handle generic item interactions"""
	var item_name = get_entity_name(item)
	show_user_message(user, "You use " + item_name + " on " + get_entity_name(self) + ".")
	return true

func handle_help_interaction(user) -> bool:
	"""Handle help intent interactions"""
	if entity_type == "item" and pickupable:
		if user.has_method("try_pick_up_item"):
			return user.try_pick_up_item(self)
	
	if has_method("friendly_interact"):
		return friendly_interact(user)
	
	var user_name = get_entity_name(user)
	show_interaction_message(user_name + " touches " + get_entity_name(self) + " gently.")
	return true

func handle_disarm_interaction(user) -> bool:
	"""Handle disarm intent interactions"""
	if entity_type in ["character", "mob"] and has_method("get_active_item"):
		var active_item = get_active_item()
		if active_item:
			return false  # Let user handle disarm attempt
	
	if has_method("apply_knockback"):
		var push_dir = (global_position - user.global_position).normalized()
		apply_knockback(push_dir, 10.0)
		
		var user_name = get_entity_name(user)
		show_interaction_message(user_name + " pushes " + get_entity_name(self) + "!")
		return true
	
	show_user_message(user, "You can't push that!")
	return false

func handle_grab_interaction(user) -> bool:
	"""Handle grab intent interactions"""
	if no_pull:
		show_user_message(user, "You can't grab that!")
		return false
	
	if grabbed_by != null:
		show_user_message(user, "Someone else is already grabbing that!")
		return false
	
	return false  # Let user handle grab

func handle_harm_interaction(user) -> bool:
	"""Handle harm intent interactions"""
	return false  # Let user handle attack

func examine(examiner) -> String:
	"""Return examination text"""
	var examine_text = description if description != "" else "This is " + get_entity_name(self) + "."
	
	# Add health status for living entities
	if entity_type in ["character", "mob"]:
		var health_system = get_node_or_null("HealthSystem")
		var current_health = health_system.health if health_system and "health" in health_system else health
		var maximum_health = health_system.max_health if health_system and "max_health" in health_system else max_health
		
		if current_health < maximum_health:
			var health_percent = (current_health / maximum_health) * 100.0
			if health_percent < 25:
				examine_text += " They look severely injured."
			elif health_percent < 50:
				examine_text += " They look hurt."
			elif health_percent < 75:
				examine_text += " They look slightly injured."
		else:
			examine_text += " They look healthy."
		
		# Status effects
		if is_lying:
			examine_text += " They are lying down."
		if is_stunned:
			examine_text += " They appear to be stunned."
		
		# Active item
		if has_method("get_active_item"):
			var active_item = get_active_item()
			if active_item:
				examine_text += " They are holding " + get_entity_name(active_item) + "."
	
	return examine_text

func take_damage(damage_amount: float, damage_type: String = "brute", armor_type: String = "", 
				effects: bool = true, armour_penetration: float = 0.0, attacker = null):
	if damage_amount <= 0:
		return
	
	# Apply armor
	if armor_type != "":
		damage_amount = modify_by_armor(damage_amount, armor_type, armour_penetration)
	
	# Apply to integrity
	var old_integrity = obj_integrity
	obj_integrity = max(0, obj_integrity - damage_amount)
	
	if old_integrity != obj_integrity:
		emit_signal("integrity_changed", old_integrity, obj_integrity)
	
	# Play damage sound
	play_damage_sound(damage_type, damage_amount)
	
	# Brief stun for high damage on characters
	if damage_amount > 15 and entity_type in ["character", "mob"] and not is_stunned:
		if has_method("stun"):
			stun(0.5)
	
	# Handle health system
	var health_system = get_node_or_null("HealthSystem")
	if health_system and health_system.has_method("take_damage"):
		health_system.take_damage(damage_amount, damage_type)
	elif entity_type in ["character", "mob"]:
		health = max(0, health - damage_amount)
		if health <= 0 and has_method("die"):
			die()
	
	# Check for destruction
	if obj_integrity <= 0:
		obj_destruction(damage_amount, damage_type, "", attacker)

func play_damage_sound(damage_type: String, damage_amount: float):
	"""Play appropriate damage sound"""
	var audio_manager = get_node_or_null("/root/AudioManager")
	if not audio_manager:
		return
	
	var sound_name = "hit"
	match damage_type:
		"burn": sound_name = "burn"
		"toxin": sound_name = "poison"
		"oxygen": sound_name = "gasp"
	
	var volume = min(0.3 + (damage_amount / 20.0), 0.9)
	audio_manager.play_positioned_sound(sound_name, global_position, volume)

func play_hit_sound():
	"""Play hit sound effect"""
	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager:
		audio_manager.play_positioned_sound("hit", global_position, 0.5)

# Interaction support methods
func interact(user) -> bool:
	emit_signal("interacted_with", user)
	show_user_message(user, "You interact with " + get_entity_name(self) + ".")
	return true

func friendly_interact(user) -> bool:
	var user_name = get_entity_name(user)
	show_interaction_message(user_name + " interacts with " + get_entity_name(self) + " in a friendly manner.")
	emit_signal("interacted_with", user)
	return true

# Stub methods for characters
func get_active_item():
	return null

func apply_knockback(direction: Vector2, force: float):
	global_position += direction * force * 0.1

func stun(duration: float):
	if entity_type in ["character", "mob"]:
		is_stunned = true
		var timer = get_tree().create_timer(duration)
		timer.timeout.connect(func(): is_stunned = false)

func die():
	if entity_type in ["character", "mob"]:
		print(get_entity_name(self), " has died!")

# Utility methods
func get_entity_name(entity) -> String:
	if "entity_name" in entity and entity.entity_name != "":
		return entity.entity_name
	elif "name" in entity:
		return entity.name
	else:
		return "something"

func show_interaction_message(message: String):
	"""Display message to nearby entities"""
	print(message)
	
	var sensory_system = get_node_or_null("/root/SensorySystem")
	if sensory_system and sensory_system.has_method("display_message_to_nearby"):
		sensory_system.display_message_to_nearby(global_position, message)

func show_user_message(user, message: String):
	"""Display message to specific user"""
	if user.has_method("show_interaction_message"):
		user.show_interaction_message(message)
	elif "sensory_system" in user and user.sensory_system:
		user.sensory_system.display_message(message)
	else:
		print(get_entity_name(user), " message: ", message)

func can_interact(user) -> bool:
	return is_user_in_range(user) and (not user.has_method("can_interact") or user.can_interact())

func is_user_in_range(user, interaction_range: float = 1.5) -> bool:
	if not "global_position" in user:
		return false
	
	var distance = global_position.distance_to(user.global_position)
	return distance <= interaction_range * 32

func update_appearance() -> void:
	pass

func attack_generic(attacker, damage_amount: float = 0, damage_type: String = "brute", 
				   armor_type: String = "melee", effects: bool = true, armor_penetration: float = 0) -> float:
	take_damage(damage_amount, damage_type, armor_type, effects, armor_penetration, attacker)
	return damage_amount

# Physics methods
func setup_collision():
	var collision_shape = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	
	var sprite = get_node_or_null("Sprite2D")
	if sprite and sprite.texture:
		shape.size = Vector2(sprite.texture.get_width(), sprite.texture.get_height())
	else:
		shape.size = Vector2(32, 32)
	
	collision_shape.shape = shape
	add_child(collision_shape)

func disable_physics_simulation():
	is_physically_simulated = false
	velocity = Vector2.ZERO
	angular_velocity = 0.0
	landed = true
	set_physics_process(false)

func land():
	landed = true
	velocity = Vector2.ZERO
	angular_velocity = 0.0
	emit_signal("landed_after_throw", global_position)
	set_physics_process(false)

func apply_throw_force(direction: Vector2, speed: float, thrower = null):
	last_thrower = thrower
	velocity = direction.normalized() * speed
	angular_velocity = randf_range(-180, 180)
	is_physically_simulated = true
	landed = false
	set_physics_process(true)

func apply_drop_force(direction: Vector2 = Vector2.DOWN, initial_speed: float = 30.0):
	velocity = direction * initial_speed
	angular_velocity = randf_range(-30, 30)
	is_physically_simulated = true
	landed = false
	set_physics_process(true)

func move_and_collide(delta_movement: Vector2):
	var new_position = global_position + delta_movement
	
	var world = get_node_or_null("/root/World")
	if world and world.has_method("check_collision"):
		var collision = world.check_collision(global_position, new_position)
		if collision:
			return collision
	
	global_position = new_position
	return null

func play_audio(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream:
		var audio_player = AudioStreamPlayer2D.new()
		add_child(audio_player)
		audio_player.stream = stream
		audio_player.volume_db = volume_db
		audio_player.play()
		await audio_player.finished
		audio_player.queue_free()

func get_direction_to(other_node) -> Vector2:
	if "global_position" in other_node:
		return (other_node.global_position - global_position).normalized()
	else:
		return Vector2.ZERO
