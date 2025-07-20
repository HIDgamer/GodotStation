extends Node2D
class_name BaseObject

# Object behavior flags
enum ObjectFlags {
	IN_USE = 1,               # Object is currently being used by someone
	CAN_BE_HIT = 2,           # Can be hit by items
	PROJ_IGNORE_DENSITY = 4,  # If non-dense objects can still get hit by projectiles
	LIGHT_CAN_BE_SHUT = 8,    # Is sensible to nightfall ability
	BLOCKS_CONSTRUCTION = 16, # Prevents things from being built on it
	IGNORE_DENSITY = 32       # Can ignore density when building
}

# Resistance flags
enum ResistanceFlags {
	INDESTRUCTIBLE = 1,      # Doesn't take damage
	UNACIDABLE = 2,          # Immune to acid
	ON_FIRE = 4,             # Currently on fire
	XENO_DAMAGEABLE = 8,     # Can be damaged by xenomorphs
	CRUSHER_IMMUNE = 16,     # Immune to crusher's charge
	PLASMACUTTER_IMMUNE = 32,# Immune to plasma cutter
	PROJECTILE_IMMUNE = 64   # Cannot be hit by projectiles
}

# Core Properties (always present)
var obj_name: String = "object"
var obj_desc: String = "An object."
var obj_flags: int = ObjectFlags.CAN_BE_HIT
var resistance_flags: int = 0
var obj_integrity: float = 100.0
var max_integrity: float = 100.0
var integrity_failure: float = 0.0  # Threshold where the object starts behaving differently
var anchored: bool = false          # Whether the object is anchored to the ground
var throwforce: int = 1
var throw_speed: int = 3
var throw_range: int = 7
var hit_sound: AudioStream = null   # Sound when hit
var destroy_sound: AudioStream = null # Sound when destroyed
var layer_z: int = 0                # Z-layer ordering
var allow_pass_flags: int = 0       # Flags for what types of things can pass through
var last_thrower = null             # Reference to who last threw this object

@export var entity_type: String = "object"  # Type of entity (object, item, character, etc.)
@export var entity_dense: bool = true
@export var entity_name: String = ""        # Display name
@export var description: String = ""        # Examine description
@export var pickupable: bool = false        # Can be picked up
@export var no_pull: bool = false          # Cannot be grabbed
@export var grabbed_by = null              # Who is grabbing this object
@export var is_lying: bool = false         # Is lying down (for characters)
@export var is_stunned: bool = false       # Is stunned (for characters)
@export var health: float = 100.0          # Health (for living things)
@export var max_health: float = 100.0      # Maximum health
@export var active_equipment: Dictionary = {} # Equipment worn (for characters)

# Armor values
var soft_armor = {
	"melee": 0,
	"bullet": 0,
	"laser": 0,
	"energy": 0,
	"bomb": 0,
	"bio": 100,  # Default bio armor 100 as in the original code
	"rad": 0,
	"fire": 0,
	"acid": 0
}

var hard_armor = {
	"melee": 0,
	"bullet": 0,
	"laser": 0,
	"energy": 0,
	"bomb": 0,
	"bio": 0,
	"rad": 0,
	"fire": 0,
	"acid": 0
}

# Physics-related properties for better drops/throws
var velocity: Vector2 = Vector2.ZERO      # Current velocity for physics-based movement
var angular_velocity: float = 0.0         # Rotation speed when thrown
var gravity_scale: float = 1.0            # How much gravity affects this object
var physical_collision_layer: int = 1     # Default physics layer
var physical_collision_mask: int = 1      # Default collision mask
var bounce_factor: float = 0.3            # How much bounce when hitting surfaces
var friction: float = 0.1                 # Friction when sliding
var air_resistance: float = 0.01          # Air resistance to slow throws
var is_physically_simulated: bool = false # Whether this object uses physics simulation
var landed: bool = true                   # Whether the object has landed after being thrown

# Signals
signal integrity_changed(old_value, new_value)
signal destroyed(disassembled)
signal anchored_changed(new_anchored_state)
signal interacted_with(user)
signal landed_after_throw(position)
signal object_hit(hit_by, force)
signal physically_stepped_on(by_who)

func _init():
	# Initialize obj_integrity if it's null
	if obj_integrity == null:
		obj_integrity = max_integrity
	
	# Set default entity_name if empty
	if entity_name == "":
		entity_name = obj_name

func _ready():
	# Add to appropriate groups
	add_to_group("clickable_entities")
	add_to_group("entities")
	
	# Add to specific groups based on flags
	if has_flag(resistance_flags, ResistanceFlags.INDESTRUCTIBLE):
		add_to_group("indestructible")
	
	if has_flag(resistance_flags, ResistanceFlags.XENO_DAMAGEABLE):
		add_to_group("xeno_damageable")
	
	# Set up collision shape if needed for physics interactions
	if is_physically_simulated and not has_node("CollisionShape2D"):
		setup_collision()

func _physics_process(delta):
	# Handle physics-based movement for throws and drops
	if is_physically_simulated and not landed:
		# Apply gravity
		velocity.y += 9.8 * gravity_scale * delta
		
		# Apply air resistance
		velocity = velocity.lerp(Vector2.ZERO, air_resistance * delta)
		
		# Move the object
		var collision = move_and_collide(velocity * delta)
		
		# Rotate if spinning
		if angular_velocity != 0:
			rotation_degrees += angular_velocity * delta
			# Gradually reduce angular velocity
			angular_velocity = lerp(angular_velocity, 0.0, friction * delta * 2)
		
		# Handle collision
		if collision:
			# Bounce off surfaces
			velocity = velocity.bounce(collision.get_normal()) * bounce_factor
			
			# Reduce angular velocity on collision
			angular_velocity *= bounce_factor
			
			# Check if nearly stopped
			if velocity.length() < 20.0 and abs(angular_velocity) < 10.0:
				land()
				
		# Land if very slow
		if velocity.length() < 10.0 and abs(angular_velocity) < 5.0:
			land()

# Check if a flag is set
func has_flag(flags: int, flag: int) -> bool:
	return (flags & flag) != 0

# Set a flag
func set_flag(flags_var: String, flag: int, enabled: bool = true) -> void:
	if enabled:
		set(flags_var, get(flags_var) | flag)
	else:
		set(flags_var, get(flags_var) & ~flag)

# Apply armor to reduce damage
func modify_by_armor(damage: float, armor_type: String, penetration: float = 0) -> float:
	var armor_value = soft_armor[armor_type] if armor_type in soft_armor else 0
	
	# Apply penetration
	armor_value = max(0, armor_value - penetration)
	
	# Calculate damage reduction
	var damage_reduction = min(armor_value / 100.0, 0.9)  # Cap at 90% reduction
	
	return damage * (1 - damage_reduction)

# Repair damage
func repair_damage(repair_amount: float, repairer = null) -> void:
	if obj_integrity >= max_integrity:
		return
	
	var old_integrity = obj_integrity
	repair_amount = min(repair_amount, max_integrity - obj_integrity)
	obj_integrity += repair_amount
	
	emit_signal("integrity_changed", old_integrity, obj_integrity)
	update_appearance()

# Handle what happens when the object breaks
func obj_break(damage_flag: String = "") -> void:
	# To be overridden by child classes
	pass

# Handle destruction of the object
func obj_destruction(damage_amount: float, damage_type: String, damage_flag: String, attacker = null) -> void:
	# Play destroy sound if it exists
	if destroy_sound:
		play_audio(destroy_sound)
	
	emit_signal("destroyed", false)  # false = not disassembled
	
	# By default, queue for deletion
	queue_free()

# Deconstruct the object (cleaner disassembly)
func deconstruct(disassembled: bool = true, disassembler = null) -> void:
	emit_signal("destroyed", disassembled)
	queue_free()

# Set whether the object is anchored
func set_anchored(anchor_value: bool) -> void:
	if anchored == anchor_value:
		return
	
	anchored = anchor_value
	emit_signal("anchored_changed", anchored)

# Handle explosions hitting the object
func ex_act(severity: int) -> void:
	if has_flag(resistance_flags, ResistanceFlags.INDESTRUCTIBLE):
		return
	
	match severity:
		1:  # EXPLODE_DEVASTATE
			take_damage(1000, "bomb")  # Effectively destroy it
		2:  # EXPLODE_HEAVY
			take_damage(randf_range(100, 250), "bomb")
		3:  # EXPLODE_LIGHT
			take_damage(randf_range(10, 90), "bomb")
		4:  # EXPLODE_WEAK
			take_damage(randf_range(5, 45), "bomb")

# Handle being hit by thrown objects
func hitby(thrown_item, speed: float = 5) -> void:
	var tforce = thrown_item.throwforce if "throwforce" in thrown_item else 0
	# Direction is now handled separately, not in take_damage
	take_damage(tforce, "brute", "melee", true, 0.0)
	
	# Signal that we were hit
	emit_signal("object_hit", thrown_item, tforce)

# Main interaction method - called when someone uses an item on this object
func attackby(item, user, params = null) -> bool:
	"""Called when someone uses an item on this entity"""
	print(name, ": attackby called with item ", item.name if "name" in item else "unknown", " by user ", user.name if "name" in user else "unknown")
	
	if !item or !user:
		return false
	
	# Let the item handle the interaction first
	if item.has_method("attack"):
		return item.attack(self, user)
	
	# Handle based on item type/tool behaviour
	if "tool_behaviour" in item:
		match item.tool_behaviour:
			"weapon":
				# Being attacked with a weapon
				if user.has_method("get") and user.get("intent") == user.get("Intent").HARM:
					return handle_being_attacked(item, user)
				else:
					# Not harm intent - maybe they're trying to use it for something else
					return handle_tool_usage(item, user)
			"medical":
				# Medical treatment
				return handle_medical_treatment(item, user)
			"tool":
				# Being worked on with a tool
				return handle_tool_usage(item, user)
			_:
				# Unknown tool type
				return handle_generic_item_usage(item, user)
	
	# Check for specific item interactions
	if "item_type" in item:
		match item.item_type:
			"food":
				return handle_food_usage(item, user)
			"drink":
				return handle_drink_usage(item, user)
			"chemical":
				return handle_chemical_usage(item, user)
			_:
				return handle_generic_item_usage(item, user)
	
	# Generic item usage
	return handle_generic_item_usage(item, user)

# Main hand interaction method - called when someone interacts without an item
func attack_hand(user, params = null) -> bool:
	"""Called when someone interacts with this entity without an item"""
	print(name, ": attack_hand called by user ", user.name if "name" in user else "unknown")
	
	if !user:
		return false
	
	# Check user's intent if they have one
	var user_intent = get_user_intent(user)
	
	# Handle based on user's intent
	match user_intent:
		0:  # HELP
			return handle_help_interaction_received(user)
		1:  # DISARM
			return handle_disarm_interaction_received(user)
		2:  # GRAB
			return handle_grab_interaction_received(user)
		3:  # HARM
			return handle_harm_interaction_received(user)
		_:
			return handle_help_interaction_received(user)

# Get user's intent safely
func get_user_intent(user) -> int:
	if "intent" in user:
		return user.intent
	elif user.has_method("get_intent"):
		return user.get_intent()
	else:
		return 0  # Default to HELP

# Handle being attacked with a weapon
func handle_being_attacked(weapon, attacker) -> bool:
	"""Handle when someone attacks us with a weapon"""
	var damage = 5.0
	if "force" in weapon:
		damage = weapon.force
	
	# Apply damage
	take_damage(damage, "brute")
	
	# Show combat message
	var weapon_name = weapon.name if "name" in weapon else "something"
	var attacker_name = get_entity_name(attacker)
	
	show_interaction_message(attacker_name + " hits " + get_entity_name(self) + " with " + weapon_name + "!")
	
	# Play hit sound
	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager:
		audio_manager.play_positioned_sound("hit", global_position, 0.5)
	
	return true

# Handle medical treatment
func handle_medical_treatment(medical_item, user) -> bool:
	"""Handle medical items being used on us"""
	if medical_item.has_method("treat_patient"):
		return medical_item.treat_patient(self, user)
	
	# Default medical treatment - only if this is a living entity
	if entity_type == "character" or entity_type == "mob":
		var health_system = get_node_or_null("HealthSystem")
		if health_system and health_system.has_method("apply_healing"):
			health_system.apply_healing(10.0, "medical")
			
			var item_name = medical_item.name if "name" in medical_item else "medical item"
			show_interaction_message("The " + item_name + " helps heal the damage.")
			
			return true
	
	# Not a valid target for medical treatment
	var user_name = get_entity_name(user)
	var item_name = medical_item.name if "name" in medical_item else "medical item"
	show_user_message(user, "You can't use " + item_name + " on " + get_entity_name(self) + ".")
	
	return false

# Handle tool usage
func handle_tool_usage(tool, user) -> bool:
	"""Handle tools being used on us"""
	var tool_name = tool.name if "name" in tool else "tool"
	var user_name = get_entity_name(user)
	
	show_user_message(user, "You use " + tool_name + " on " + get_entity_name(self) + ".")
	
	return true

# Handle generic item usage
func handle_generic_item_usage(item, user) -> bool:
	"""Default handler for items being used on us"""
	var item_name = item.name if "name" in item else "something"
	var user_name = get_entity_name(user)
	
	show_user_message(user, "You use " + item_name + " on " + get_entity_name(self) + ".")
	
	return true

# Handle food being used
func handle_food_usage(food_item, user) -> bool:
	"""Handle food items being used on us"""
	# Only living entities can be fed
	if entity_type != "character" and entity_type != "mob":
		show_user_message(user, "You can't feed that!")
		return false
	
	# Only allow feeding if we're the same entity as the user (feeding self)
	# or if we're incapacitated
	var can_be_fed = (user == self or user == get_parent())
	
	if is_stunned or is_lying:
		can_be_fed = true
	
	if not can_be_fed:
		show_user_message(user, "They won't let you feed them!")
		return false
	
	# Feed logic here
	if food_item.has_method("feed_to"):
		return food_item.feed_to(self, user)
	
	show_user_message(user, "You feed " + get_entity_name(self) + " the " + food_item.name + ".")
	return true

# Handle drink being used
func handle_drink_usage(drink_item, user) -> bool:
	"""Handle drink items being used on us"""
	# Only living entities can drink
	if entity_type != "character" and entity_type != "mob":
		show_user_message(user, "You can't give that a drink!")
		return false
	
	# Similar logic to food
	var can_be_given_drink = (user == self or user == get_parent())
	
	if is_stunned:
		can_be_given_drink = true
	
	if not can_be_given_drink:
		show_user_message(user, "They won't let you give them a drink!")
		return false
	
	if drink_item.has_method("give_drink_to"):
		return drink_item.give_drink_to(self, user)
	
	show_user_message(user, "You give " + get_entity_name(self) + " the " + drink_item.name + " to drink.")
	return true

# Handle chemical usage
func handle_chemical_usage(chemical_item, user) -> bool:
	"""Handle chemical items being used on us"""
	# Chemicals can be applied to most things
	if chemical_item.has_method("apply_chemical_to"):
		return chemical_item.apply_chemical_to(self, user)
	
	show_user_message(user, "You apply " + chemical_item.name + " to " + get_entity_name(self) + ".")
	return true

# Handle help intent interaction received
func handle_help_interaction_received(user) -> bool:
	"""Handle when someone interacts with us using help intent"""
	# Check if this is an item that can be picked up
	if entity_type == "item" and pickupable:
		# Let the user try to pick us up
		if user.has_method("try_pick_up_item"):
			return user.try_pick_up_item(self)
	
	# Check if we have a specific friendly interaction
	if has_method("friendly_interact"):
		return friendly_interact(user)
	
	# Default: just show a message
	var user_name = get_entity_name(user)
	show_interaction_message(user_name + " touches " + get_entity_name(self) + " gently.")
	show_user_message(user, "You touch " + get_entity_name(self) + " gently.")
	
	return true

# Handle disarm intent interaction received
func handle_disarm_interaction_received(user) -> bool:
	"""Handle when someone tries to disarm us"""
	# Only characters can be disarmed
	if entity_type == "character" or entity_type == "mob":
		# Check if we have items - use safe method access
		if has_method("get_active_item"):
			var active_item = get_active_item()
			if active_item:
				# User is trying to disarm us - this is handled in the user's disarm logic
				return false  # Let the user handle the disarm attempt
	
	# If we're not holding anything or not a character, they're just pushing us
	if has_method("apply_knockback"):
		var push_dir = (global_position - user.global_position).normalized()
		apply_knockback(push_dir, 10.0)
		
		var user_name = get_entity_name(user)
		show_interaction_message(user_name + " pushes " + get_entity_name(self) + "!")
		
		return true
	
	# Can't be pushed
	show_user_message(user, "You can't push that!")
	return false

# Handle grab intent interaction received  
func handle_grab_interaction_received(user) -> bool:
	"""Handle when someone tries to grab us"""
	# Check if we can be grabbed
	if no_pull:
		show_user_message(user, "You can't grab that!")
		return false
	
	# Check if we're already being grabbed
	if grabbed_by != null:
		show_user_message(user, "Someone else is already grabbing that!")
		return false
	
	# Allow the grab - this is handled by the user's grab logic
	return false  # Let the user handle the grab attempt

# Handle harm intent interaction received
func handle_harm_interaction_received(user) -> bool:
	"""Handle when someone attacks us with harm intent"""
	# This is handled by the user's attack logic
	# We just need to be able to receive damage
	return false  # Let the user handle the attack

# examine method with safe property access
func examine(examiner) -> String:
	"""Return examine text for this entity"""
	var examine_text = ""
	
	# Basic description
	if description != "":
		examine_text = description
	elif entity_name != "":
		examine_text = "This is " + entity_name + "."
	else:
		examine_text = "This is " + name + "."
	
	# Add health status if this is a character
	if entity_type == "character" or entity_type == "mob":
		var health_system = get_node_or_null("HealthSystem")
		if health_system and "health" in health_system and "max_health" in health_system:
			var health_percent = (health_system.health / health_system.max_health) * 100.0
			if health_percent < 25:
				examine_text += " They look severely injured."
			elif health_percent < 50:
				examine_text += " They look hurt."
			elif health_percent < 75:
				examine_text += " They look slightly injured."
			else:
				examine_text += " They look healthy."
		elif health < max_health:
			var health_percent = (health / max_health) * 100.0
			if health_percent < 25:
				examine_text += " It looks severely damaged."
			elif health_percent < 50:
				examine_text += " It looks damaged."
			elif health_percent < 75:
				examine_text += " It looks slightly damaged."
	
	# Status effects (only for characters)
	if entity_type == "character" or entity_type == "mob":
		if is_lying:
			examine_text += " They are lying down."
		
		if is_stunned:
			examine_text += " They appear to be stunned."
		
		# Held items
		if has_method("get_active_item"):
			var active_item = get_active_item()
			if active_item:
				var item_name = active_item.name if "name" in active_item else "something"
				examine_text += " They are holding " + item_name + "."
		
		# Equipment if visible
		if active_equipment.size() > 0:
			examine_text += " They are wearing some equipment."
	
	return examine_text

# Take damage with safe method calls
func take_damage(damage_amount: float, damage_type: String = "brute", armor_type: String = "", effects: bool = true, armour_penetration: float = 0.0, attacker = null):
	if damage_amount <= 0:
		return
	
	print(name, " taking ", damage_amount, " ", damage_type, " damage")
	
	# Apply armor if we have it
	if armor_type != "":
		damage_amount = modify_by_armor(damage_amount, armor_type, armour_penetration)
	
	# Apply to object integrity
	var old_integrity = obj_integrity
	obj_integrity = max(0, obj_integrity - damage_amount)
	
	if old_integrity != obj_integrity:
		emit_signal("integrity_changed", old_integrity, obj_integrity)
	
	# Play damage sound
	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager:
		var sound_name = "hit"
		match damage_type:
			"burn":
				sound_name = "burn"
			"toxin":
				sound_name = "poison"
			"oxygen":
				sound_name = "gasp"
			_:
				sound_name = "hit"
		
		audio_manager.play_positioned_sound(sound_name, global_position, min(0.3 + (damage_amount / 20.0), 0.9))
	
	# Stun briefly for high damage (only for characters)
	if damage_amount > 15 and (entity_type == "character" or entity_type == "mob"):
		if has_method("stun") and not is_stunned:
			stun(0.5)
	
	# Handle health system if available
	var health_system = get_node_or_null("HealthSystem")
	if health_system and health_system.has_method("take_damage"):
		health_system.take_damage(damage_amount, damage_type)
	elif entity_type == "character" or entity_type == "mob":
		# Fallback health handling
		health = max(0, health - damage_amount)
		
		# Die if health reaches 0
		if health <= 0 and has_method("die"):
			die()
	
	# Check for object destruction
	if obj_integrity <= 0:
		obj_destruction(damage_amount, damage_type, "", attacker)

# STUB METHODS - Override these in child classes as needed

# Basic interaction method - override in child classes
func interact(user) -> bool:
	emit_signal("interacted_with", user)
	# Default friendly interaction without recursion
	show_user_message(user, "You interact with " + get_entity_name(self) + ".")
	return true

# Friendly interaction stub - override in child classes for specific behavior
func friendly_interact(user) -> bool:
	# Default friendly interaction without calling attack_hand to avoid recursion
	var user_name = get_entity_name(user)
	show_interaction_message(user_name + " interacts with " + get_entity_name(self) + " in a friendly manner.")
	show_user_message(user, "You interact with " + get_entity_name(self) + " in a friendly way.")
	emit_signal("interacted_with", user)
	return true

# Get active item stub (for characters)
func get_active_item():
	return null

# Apply knockback stub (for physics objects)
func apply_knockback(direction: Vector2, force: float):
	# Default implementation - just move slightly
	global_position += direction * force * 0.1

# Stun method stub (for characters)
func stun(duration: float):
	if entity_type == "character" or entity_type == "mob":
		is_stunned = true
		# Create a timer to remove stun
		var timer = get_tree().create_timer(duration)
		timer.timeout.connect(func(): is_stunned = false)

# Die method stub (for living things)
func die():
	if entity_type == "character" or entity_type == "mob":
		print(get_entity_name(self), " has died!")
		# Override in child classes for specific death behavior

# UTILITY METHODS

# Safe way to get entity name
func get_entity_name(entity) -> String:
	if "entity_name" in entity and entity.entity_name != "":
		return entity.entity_name
	elif "name" in entity:
		return entity.name
	else:
		return "something"

# Show interaction message helper
func show_interaction_message(message: String):
	"""Display a message visible to nearby entities"""
	print(message)  # Always print for debugging
	
	# Try to use sensory system if available
	var sensory_system = get_node_or_null("/root/SensorySystem")
	if sensory_system and sensory_system.has_method("display_message_to_nearby"):
		sensory_system.display_message_to_nearby(global_position, message)

# Show message to specific user
func show_user_message(user, message: String):
	"""Display a message to a specific user"""
	if user.has_method("show_interaction_message"):
		user.show_interaction_message(message)
	elif "sensory_system" in user and user.sensory_system:
		user.sensory_system.display_message(message)
	else:
		print(get_entity_name(user), " message: ", message)

# Check if a user can interact with this object
func can_interact(user) -> bool:
	# Check if user is close enough
	if not is_user_in_range(user):
		return false
	
	# Check if user is able to interact (not incapacitated)
	if user.has_method("can_interact") and not user.can_interact():
		return false
		
	return true

# Check if a user is in range to interact
func is_user_in_range(user, interaction_range: float = 1.5) -> bool:
	if not "global_position" in user:
		return false
	
	var distance = global_position.distance_to(user.global_position)
	return distance <= interaction_range * 32  # Convert tiles to pixels

# Update visual appearance
func update_appearance() -> void:
	# To be overridden by child classes
	pass

# Handle generic attack
func attack_generic(attacker, damage_amount: float = 0, damage_type: String = "brute", 
				   armor_type: String = "melee", effects: bool = true, armor_penetration: float = 0) -> float:
	take_damage(damage_amount, damage_type, armor_type, effects, armor_penetration, attacker)
	return damage_amount

# PHYSICS METHODS (unchanged)

# Setup physical collision for throws
func setup_collision():
	var collision_shape = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	
	# Try to determine size from sprite
	var sprite = get_node_or_null("Sprite2D")
	if sprite and sprite.texture:
		shape.size = Vector2(sprite.texture.get_width(), sprite.texture.get_height())
	else:
		# Default size
		shape.size = Vector2(32, 32)
	
	collision_shape.shape = shape
	add_child(collision_shape)

# Disable physics simulation
func disable_physics_simulation():
	is_physically_simulated = false
	velocity = Vector2.ZERO
	angular_velocity = 0.0
	landed = true
	
	# Disable physics processing to save resources
	set_physics_process(false)

# Handle when object lands after being thrown/dropped
func land():
	landed = true
	velocity = Vector2.ZERO
	angular_velocity = 0.0
	
	# Emit landed signal with final position
	emit_signal("landed_after_throw", global_position)
	
	# Disable physics to save processing
	set_physics_process(false)

# Apply throwing physics
func apply_throw_force(direction: Vector2, speed: float, thrower = null):
	# Store thrower reference
	last_thrower = thrower
	
	# Set velocity based on direction and speed
	velocity = direction.normalized() * speed
	
	# Apply random angular velocity for spin
	angular_velocity = randf_range(-180, 180)
	
	# Enable physics simulation
	is_physically_simulated = true
	landed = false
	set_physics_process(true)

# Apply force when dropped
func apply_drop_force(direction: Vector2 = Vector2.DOWN, initial_speed: float = 30.0):
	# Dropped items have lower initial velocity, mostly downward
	velocity = direction * initial_speed
	
	# Slight random spin
	angular_velocity = randf_range(-30, 30)
	
	# Enable physics simulation
	is_physically_simulated = true
	landed = false
	set_physics_process(true)

# Move and collide wrapper for physics-based movement
func move_and_collide(delta_movement: Vector2):
	# This is a simple implementation
	var new_position = global_position + delta_movement
	
	# Check for collisions with world first
	var world = get_node_or_null("/root/World")
	if world and world.has_method("check_collision"):
		var collision = world.check_collision(global_position, new_position)
		if collision:
			return collision
	
	# If no collision, move to new position
	global_position = new_position
	return null

# Helper function to play audio
func play_audio(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream:
		var audio_player = AudioStreamPlayer2D.new()
		add_child(audio_player)
		audio_player.stream = stream
		audio_player.volume_db = volume_db
		audio_player.play()
		await audio_player.finished
		audio_player.queue_free()

# Get direction to another node
func get_direction_to(other_node) -> Vector2:
	if "global_position" in other_node:
		return (other_node.global_position - global_position).normalized()
	else:
		return Vector2.ZERO
