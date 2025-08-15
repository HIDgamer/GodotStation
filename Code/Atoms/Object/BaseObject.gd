extends Node2D
class_name BaseObject

# =============================================================================
# CONSTANTS AND ENUMS
# =============================================================================

enum ObjectFlags {
	IN_USE = 1,
	CAN_BE_HIT = 2,
	PROJ_IGNORE_DENSITY = 4,
	LIGHT_CAN_BE_SHUT = 8,
	BLOCKS_CONSTRUCTION = 16,
	IGNORE_DENSITY = 32
}

enum ResistanceFlags {
	INDESTRUCTIBLE = 1,
	UNACIDABLE = 2,
	ON_FIRE = 4,
	XENO_DAMAGEABLE = 8,
	CRUSHER_IMMUNE = 16,
	PLASMACUTTER_IMMUNE = 32,
	PROJECTILE_IMMUNE = 64
}

enum PassFlags {
	PASS_OVER = 1,
	PASS_AROUND = 2,
	PASS_UNDER = 4,
	PASS_THROUGH = 8,
	PASS_HIGH_OVER_ONLY = 16,
	PASS_TYPE_CRAWLER = 32,
	PASS_CRUSHER_CHARGE = 64,
	PASS_MOB_THRU = 128,
	PASS_OVER_THROW_MOB = 256
}

const CLIMB_DELAY_SHORT = 0.2
const CLIMB_DELAY_MEDIUM = 1.0
const CLIMB_DELAY_LONG = 2.0

# =============================================================================
# EXPORT PROPERTIES
# =============================================================================

@export_group("Core Object Properties")
@export var obj_name: String = "object"
@export var obj_desc: String = "An object."
@export var obj_integrity: float = 100.0
@export var max_integrity: float = 100.0
@export var integrity_failure: float = 0.0

@export_group("Entity Configuration")
@export var entity_type: String = "object"
@export var entity_dense: bool = true
@export var entity_name: String = ""
@export var description: String = ""
@export var pickupable: bool = false
@export var no_pull: bool = false

@export_group("Physics Properties")
@export var throwforce: int = 1
@export var throw_speed: int = 3
@export var throw_range: int = 7
@export var anchored: bool = false
@export var gravity_scale: float = 1.0
@export var bounce_factor: float = 0.3
@export var friction: float = 0.1
@export var air_resistance: float = 0.01

@export_group("Health and Status")
@export var is_lying: bool = false
@export var is_stunned: bool = false
@export var health: float = 100.0
@export var max_health: float = 100.0

@export_group("Visual Properties")
@export var opacity: float = 1.0
@export var blocks_vision: bool = false
@export var layer_z: int = 0

@export_group("Audio Configuration")
@export var hit_sound: AudioStream = null
@export var destroy_sound: AudioStream = null
@export var default_audio_volume: float = 0.5

@export_group("Climbing System")
@export var climbable: bool = false
@export var climb_delay: float = CLIMB_DELAY_LONG
@export var climb_obstacle: bool = false

@export_group("Movement and Blocking")
@export var can_block_movement: bool = true
@export var projectile_coverage: int = 20

# =============================================================================
# CORE PROPERTIES
# =============================================================================

var obj_flags: int = ObjectFlags.CAN_BE_HIT
var resistance_flags: int = 0
var allow_pass_flags: int = 0
var flags_can_pass_all_temp: int = 0

var grabbed_by = null
var last_thrower = null
var active_equipment: Dictionary = {}

var actions: Array = []
var network_id: String = ""

# Physics state
var velocity: Vector2 = Vector2.ZERO
var angular_velocity: float = 0.0
var is_physically_simulated: bool = false
var landed: bool = true

# Armor values
var soft_armor = {
	"melee": 0, "bullet": 0, "laser": 0, "energy": 0, "bomb": 0,
	"bio": 100, "rad": 0, "fire": 0, "acid": 0
}

var hard_armor = {
	"melee": 0, "bullet": 0, "laser": 0, "energy": 0, "bomb": 0,
	"bio": 0, "rad": 0, "fire": 0, "acid": 0
}

# =============================================================================
# SIGNALS
# =============================================================================

signal integrity_changed(old_value, new_value)
signal destroyed(disassembled)
signal anchored_changed(new_anchored_state)
signal interacted_with(user)
signal landed_after_throw(position)
signal object_hit(hit_by, force)

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init():
	if obj_integrity == null:
		obj_integrity = max_integrity
	
	if entity_name == "":
		entity_name = obj_name
	
	network_id = str(randi()) + "_" + str(Time.get_unix_time_from_system())

func _ready():
	_initialize_groups()
	_initialize_collision()
	_register_with_systems()

func _initialize_groups():
	add_to_group("clickable_entities")
	add_to_group("entities")
	
	if has_flag(resistance_flags, ResistanceFlags.INDESTRUCTIBLE):
		add_to_group("indestructible")
	
	if has_flag(resistance_flags, ResistanceFlags.XENO_DAMAGEABLE):
		add_to_group("xeno_damageable")

func _initialize_collision():
	if is_physically_simulated and not has_node("CollisionShape2D"):
		setup_collision()

func _register_with_systems():
	# Register with spatial manager
	var world = get_parent()
	var spatial_manager = world.get_node_or_null("SpatialManager")
	if spatial_manager and spatial_manager.has_method("register_entity"):
		spatial_manager.register_entity(self)
	
	# Register with tile occupancy system
	if world and "tile_occupancy_system" in world and world.tile_occupancy_system:
		var tile_system = world.tile_occupancy_system
		if tile_system.has_method("register_entity"):
			tile_system.register_entity(self)

# =============================================================================
# PHYSICS AND MOVEMENT
# =============================================================================

func _physics_process(delta):
	if not is_physically_simulated or landed:
		return
	
	_process_physics_simulation(delta)
	_check_landing_conditions()

func _process_physics_simulation(delta):
	velocity.y += 9.8 * gravity_scale * delta
	velocity = velocity.lerp(Vector2.ZERO, air_resistance * delta)
	
	var old_position = global_position
	var new_position = old_position + velocity * delta
	
	# Check for collisions using the tile occupancy system
	var collision_result = _check_physics_collision(old_position, new_position)
	
	if angular_velocity != 0:
		rotation_degrees += angular_velocity * delta
		angular_velocity = lerp(angular_velocity, 0.0, friction * delta * 2)
	
	if collision_result.has_collision:
		# Bounce off collision
		velocity = velocity.bounce(collision_result.normal) * bounce_factor
		angular_velocity *= bounce_factor
		# Don't move to the collision position
		global_position = collision_result.safe_position
	else:
		global_position = new_position

func _check_physics_collision(old_pos: Vector2, new_pos: Vector2) -> Dictionary:
	var result = {
		"has_collision": false,
		"normal": Vector2.UP,
		"safe_position": old_pos
	}
	
	# Get world reference for collision checking
	var world = get_parent()
	if not world:
		return result
	
	# Convert to tile coordinates
	var tile_size = 32
	if "TILE_SIZE" in world:
		tile_size = world.TILE_SIZE
	
	var new_tile = Vector2i(int(new_pos.x / tile_size), int(new_pos.y / tile_size))
	var current_z = 0
	if "layer_z" in self:
		current_z = layer_z
	
	# Check for wall collision
	if world.has_method("is_wall_at") and world.is_wall_at(new_tile, current_z):
		result.has_collision = true
		result.normal = (old_pos - new_pos).normalized()
		result.safe_position = old_pos
		return result
	
	# Check for dense entity collision using tile occupancy system
	if "tile_occupancy_system" in world and world.tile_occupancy_system:
		var tile_system = world.tile_occupancy_system
		if tile_system.has_method("has_dense_entity_at"):
			if tile_system.has_dense_entity_at(new_tile, current_z, self):
				result.has_collision = true
				result.normal = (old_pos - new_pos).normalized()
				result.safe_position = old_pos
				return result
	
	return result

func _check_landing_conditions():
	if velocity.length() < 10.0 and abs(angular_velocity) < 5.0:
		land()

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

func land():
	landed = true
	velocity = Vector2.ZERO
	angular_velocity = 0.0
	emit_signal("landed_after_throw", global_position)
	set_physics_process(false)

func disable_physics_simulation():
	is_physically_simulated = false
	velocity = Vector2.ZERO
	angular_velocity = 0.0
	landed = true
	set_physics_process(false)

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

# =============================================================================
# DAMAGE AND HEALTH SYSTEM
# =============================================================================

func take_damage(damage_amount: float, damage_type: int, armor_type: String = "", effects: bool = true, armour_penetration: float = 0.0, attacker = null):
	if damage_amount <= 0:
		return
	
	if has_flag(resistance_flags, ResistanceFlags.INDESTRUCTIBLE):
		return
	
	if armor_type != "":
		damage_amount = modify_by_armor(damage_amount, armor_type, armour_penetration)
	
	var old_integrity = obj_integrity
	obj_integrity = max(0, obj_integrity - damage_amount)
	
	if old_integrity != obj_integrity:
		emit_signal("integrity_changed", old_integrity, obj_integrity)
	
	_apply_damage_effects(damage_amount, damage_type, attacker)
	
	if obj_integrity <= 0:
		obj_destruction(damage_amount, damage_type, "", attacker)

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

func _apply_damage_effects(damage_amount: float, damage_type: int, attacker):
	if damage_amount > 15 and entity_type in ["character", "mob"] and not is_stunned:
		if has_method("stun"):
			stun(0.5)
	
	var health_system = get_node_or_null("HealthSystem")
	if health_system and health_system.has_method("apply_damage"):
		health_system.apply_damage(damage_amount, damage_type)
	elif entity_type in ["character", "mob"]:
		health = max(0, health - damage_amount)
		if health <= 0 and has_method("die"):
			die()

func obj_break(damage_flag: String = "") -> void:
	pass

func obj_destruction(damage_amount: float, damage_type: int, damage_flag: String, attacker = null) -> void:
	if destroy_sound:
		play_audio(destroy_sound)
	
	emit_signal("destroyed", false)
	queue_free()

func deconstruct(disassembled: bool = true, disassembler = null) -> void:
	emit_signal("destroyed", disassembled)
	queue_free()

# =============================================================================
# INTERACTION SYSTEM
# =============================================================================

func attackby(item, user, params = null) -> bool:
	if not item or not user:
		return false
	
	if item.has_method("attack"):
		return item.attack(self, user)
	
	if "tool_behaviour" in item:
		return handle_tool_interaction(item, user)
	elif "item_type" in item:
		return handle_item_type_interaction(item, user)
	else:
		return handle_generic_interaction(item, user)

func attack_hand(user, params = null) -> bool:
	if not user:
		return false
	
	var user_intent = get_user_intent(user)
	
	match user_intent:
		0: return handle_help_interaction(user)
		1: return handle_disarm_interaction(user)
		2: return handle_grab_interaction(user)
		3: return handle_harm_interaction(user)
		_: return handle_help_interaction(user)

func interact(user) -> bool:
	emit_signal("interacted_with", user)
	show_user_message(user, "You interact with " + get_entity_name(self) + ".")
	return true

func examine(examiner) -> String:
	var examine_text = description if description != "" else "This is " + get_entity_name(self) + "."
	
	if entity_type in ["character", "mob"]:
		examine_text += _get_health_examination(examiner)
		examine_text += _get_status_examination()
		examine_text += _get_equipment_examination()
	
	return examine_text

func _get_health_examination(examiner) -> String:
	var health_system = get_node_or_null("HealthSystem")
	var current_health = health_system.health if health_system and "health" in health_system else health
	var maximum_health = health_system.max_health if health_system and "max_health" in health_system else max_health
	
	if current_health < maximum_health:
		var health_percent = (current_health / maximum_health) * 100.0
		if health_percent < 25:
			return " They look severely injured."
		elif health_percent < 50:
			return " They look hurt."
		elif health_percent < 75:
			return " They look slightly injured."
	
	return " They look healthy."

func _get_status_examination() -> String:
	var status_text = ""
	
	if is_lying:
		status_text += " They are lying down."
	if is_stunned:
		status_text += " They appear to be stunned."
	
	return status_text

func _get_equipment_examination() -> String:
	if has_method("get_active_item"):
		var active_item = get_active_item()
		if active_item:
			return " They are holding " + get_entity_name(active_item) + "."
	
	return ""

# =============================================================================
# INTERACTION HANDLERS
# =============================================================================

func handle_tool_interaction(tool, user) -> bool:
	match tool.tool_behaviour:
		"weapon":
			if get_user_intent(user) == 3:
				return handle_weapon_attack(tool, user)
			else:
				return handle_tool_usage(tool, user)
		"medical":
			return handle_medical_treatment(tool, user)
		_:
			return handle_tool_usage(tool, user)

func handle_item_type_interaction(item, user) -> bool:
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
	var damage = weapon.get("force", 5.0)
	take_damage(damage, 1)
	
	var weapon_name = get_entity_name(weapon)
	var attacker_name = get_entity_name(attacker)
	
	show_interaction_message(attacker_name + " hits " + get_entity_name(self) + " with " + weapon_name + "!")
	play_hit_sound()
	
	return true

func handle_medical_treatment(medical_item, user) -> bool:
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
	var tool_name = get_entity_name(tool)
	show_user_message(user, "You use " + tool_name + " on " + get_entity_name(self) + ".")
	return true

func handle_food_interaction(food_item, user) -> bool:
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
	if chemical_item.has_method("apply_chemical_to"):
		return chemical_item.apply_chemical_to(self, user)
	
	show_user_message(user, "You apply " + get_entity_name(chemical_item) + " to " + get_entity_name(self) + ".")
	return true

func handle_generic_interaction(item, user) -> bool:
	var item_name = get_entity_name(item)
	show_user_message(user, "You use " + item_name + " on " + get_entity_name(self) + ".")
	return true

func handle_help_interaction(user) -> bool:
	if entity_type == "item" and pickupable:
		if user.has_method("try_pick_up_item"):
			return user.try_pick_up_item(self)
	
	if has_method("friendly_interact"):
		return friendly_interact(user)
	
	var user_name = get_entity_name(user)
	show_interaction_message(user_name + " touches " + get_entity_name(self) + " gently.")
	return true

func handle_disarm_interaction(user) -> bool:
	if entity_type in ["character", "mob"] and has_method("get_active_item"):
		var active_item = get_active_item()
		if active_item:
			return false
	
	if has_method("apply_knockback"):
		var push_dir = (global_position - user.global_position).normalized()
		apply_knockback(push_dir, 10.0)
		
		var user_name = get_entity_name(user)
		show_interaction_message(user_name + " pushes " + get_entity_name(self) + "!")
		return true
	
	show_user_message(user, "You can't push that!")
	return false

func handle_grab_interaction(user) -> bool:
	if no_pull:
		show_user_message(user, "You can't grab that!")
		return false
	
	if grabbed_by != null:
		show_user_message(user, "Someone else is already grabbing that!")
		return false
	
	return false

func handle_harm_interaction(user) -> bool:
	return false

func friendly_interact(user) -> bool:
	var user_name = get_entity_name(user)
	show_interaction_message(user_name + " interacts with " + get_entity_name(self) + " in a friendly manner.")
	emit_signal("interacted_with", user)
	return true

# =============================================================================
# COLLISION AND DETECTION
# =============================================================================

func hitby(thrown_item, speed: float = 5) -> void:
	var tforce = thrown_item.throwforce if "throwforce" in thrown_item else 0
	take_damage(tforce, 1, "melee", true, 0.0)
	emit_signal("object_hit", thrown_item, tforce)

func ex_act(severity: int) -> void:
	if has_flag(resistance_flags, ResistanceFlags.INDESTRUCTIBLE):
		return
	
	var damage_values = [1000, randf_range(100, 250), randf_range(10, 90), randf_range(5, 45)]
	if severity >= 1 and severity <= 4:
		take_damage(damage_values[severity - 1], 1)

func attack_generic(attacker, damage_amount: float = 0, damage_type: int = 1, armor_type: String = "melee", effects: bool = true, armor_penetration: float = 0) -> float:
	take_damage(damage_amount, damage_type, armor_type, effects, armor_penetration, attacker)
	return damage_amount

func can_interact(user) -> bool:
	return is_user_in_range(user)

func is_user_in_range(user, interaction_range: float = 1.5) -> bool:
	if not "global_position" in user:
		return false
	
	var distance = global_position.distance_to(user.global_position)
	return distance <= interaction_range * 32

# =============================================================================
# ANCHORING SYSTEM
# =============================================================================

func set_anchored(anchor_value: bool) -> void:
	if anchored == anchor_value:
		return
	
	anchored = anchor_value
	emit_signal("anchored_changed", anchored)

# =============================================================================
# AUDIO AND VISUAL
# =============================================================================

func play_audio(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream:
		var audio_player = AudioStreamPlayer2D.new()
		add_child(audio_player)
		audio_player.stream = stream
		audio_player.volume_db = volume_db
		audio_player.play()
		await audio_player.finished
		audio_player.queue_free()

func play_hit_sound():
	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager:
		audio_manager.play_positioned_sound("hit", global_position, default_audio_volume)

func set_opacity(new_opacity: float):
	opacity = clamp(new_opacity, 0.0, 1.0)
	blocks_vision = opacity >= 0.5
	
	var sprite = get_node_or_null("Icon")
	if sprite:
		sprite.modulate.a = opacity

func update_appearance() -> void:
	pass

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

func has_flag(flags: int, flag: int) -> bool:
	return (flags & flag) != 0

func set_flag(flags_var: String, flag: int, enabled: bool = true) -> void:
	if enabled:
		set(flags_var, get(flags_var) | flag)
	else:
		set(flags_var, get(flags_var) & ~flag)

func get_user_intent(user) -> int:
	if "intent" in user:
		return user.intent
	elif user.has_method("get_intent"):
		return user.get_intent()
	else:
		return 0

func get_entity_name(entity) -> String:
	if "entity_name" in entity and entity.entity_name != "":
		return entity.entity_name
	elif "name" in entity:
		return entity.name
	else:
		return "something"

func show_interaction_message(message: String):
	print(message)
	
	var sensory_system = get_node_or_null("/root/SensorySystem")
	if sensory_system and sensory_system.has_method("display_message_to_nearby"):
		sensory_system.display_message_to_nearby(global_position, message)

func show_user_message(user, message: String):
	if user.has_method("show_interaction_message"):
		user.show_interaction_message(message)
	elif "sensory_system" in user and user.sensory_system:
		user.sensory_system.display_message(message)
	else:
		print(get_entity_name(user), " message: ", message)

func get_direction_to(other_node) -> Vector2:
	if "global_position" in other_node:
		return (other_node.global_position - global_position).normalized()
	else:
		return Vector2.ZERO

func get_network_id() -> String:
	return network_id

# =============================================================================
# CHARACTER STUB METHODS
# =============================================================================

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

# =============================================================================
# STUB METHODS FOR EXTENSION
# =============================================================================

func _unfold_internal(user):
	pass

func get_acid_applying_time():
	return 4.0
