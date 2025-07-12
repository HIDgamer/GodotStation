extends Node2D
class_name BaseObject

# Object behavior flags (similar to obj_flags in SS13)
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

# Properties
var obj_name: String = "object"
var obj_desc: String = "An object."
var obj_flags: int = ObjectFlags.CAN_BE_HIT
var resistance_flags: int = 0
var obj_integrity: float = 100.0
var max_integrity: float = 100.0
var integrity_failure: float = 0.0  # Threshold where the object starts behaving differently
var anchored: bool = false          # Whether the object is anchored to the ground
var density: bool = true            # Whether the object blocks movement
var throwforce: int = 1
var throw_speed: int = 3
var throw_range: int = 7
var hit_sound: AudioStream = null   # Sound when hit
var destroy_sound: AudioStream = null # Sound when destroyed
var layer_z: int = 0                # Z-layer ordering
var allow_pass_flags: int = 0       # Flags for what types of things can pass through
var last_thrower = null             # Reference to who last threw this object

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

func _ready():
	# Add to appropriate groups based on flags
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

# Handle taking damage
func take_damage(damage_amount: float, damage_type: String = "brute", armor_type: String = "", effects: bool = true, armour_penetration: float = 0.0, attacker = null) -> float:
	if damage_amount <= 0:
		return 0
		
	if has_flag(resistance_flags, ResistanceFlags.INDESTRUCTIBLE) or obj_integrity <= 0:
		return 0
	
	# Apply armor reduction if armor_type is specified
	if armor_type != "":
		damage_amount = modify_by_armor(damage_amount, armor_type, armour_penetration)
	
	if damage_amount < 0.1:  # Minimal damage threshold
		return 0
	
	var old_integrity = obj_integrity
	obj_integrity = max(obj_integrity - damage_amount, 0)
	
	emit_signal("integrity_changed", old_integrity, obj_integrity)
	
	# Check for breaking threshold
	if integrity_failure and obj_integrity <= integrity_failure and old_integrity > integrity_failure:
		obj_break(armor_type)
	
	# Check for destruction
	if obj_integrity <= 0:
		obj_destruction(damage_amount, damage_type, armor_type, attacker)
	
	update_appearance()
	return damage_amount

# Apply armor to reduce damage
func modify_by_armor(damage: float, armor_type: String, penetration: float = 0) -> float:
	var armor_value = soft_armor[armor_type] if armor_type in soft_armor else 0
	
	# Apply penetration
	armor_value = max(0, armor_value - penetration)
	
	# Calculate damage reduction (simplifying the formula used in SS13)
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

# Handle examination
func examine(examiner) -> String:
	var examine_text = obj_desc
	
	# Add integrity status
	if obj_integrity < max_integrity:
		var damage_percent = obj_integrity / max_integrity * 100
		if damage_percent < 25:
			examine_text += "\nIt looks severely damaged!"
		elif damage_percent < 50:
			examine_text += "\nIt looks badly damaged."
		elif damage_percent < 75:
			examine_text += "\nIt looks damaged."
		elif damage_percent < 95:
			examine_text += "\nIt has a few scratches."
	
	# Add resistance information
	if has_flag(resistance_flags, ResistanceFlags.INDESTRUCTIBLE):
		examine_text += "\nIt appears to be indestructible."
	
	return examine_text

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

# Handle generic attack
func attack_generic(attacker, damage_amount: float = 0, damage_type: String = "brute", 
				   armor_type: String = "melee", effects: bool = true, armor_penetration: float = 0) -> float:
	# Fixed parameter order to match take_damage function
	return take_damage(damage_amount, damage_type, armor_type, effects, armor_penetration, attacker)

# Interaction handling (to be overridden by derived classes)
func interact(user) -> bool:
	emit_signal("interacted_with", user)
	return true

# Check if a user can interact with this object
func can_interact(user) -> bool:
	# Check if user is close enough
	if not is_user_in_range(user):
		return false
	
	# Check if user is able to interact (not incapacitated)
	if "can_interact" in user and not user.can_interact():
		return false
		
	return true

# Check if a user is in range to interact
func is_user_in_range(user, interaction_range: float = 1.5) -> bool:
	var distance = global_position.distance_to(user.global_position)
	return distance <= interaction_range * 32  # Convert tiles to pixels

# Update visual appearance
func update_appearance() -> void:
	# To be overridden by child classes
	pass

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
	
	# Make sure we're not flagged as landed
	landed = false

# Apply force when dropped
func apply_drop_force(direction: Vector2 = Vector2.DOWN, initial_speed: float = 30.0):
	# Dropped items have lower initial velocity, mostly downward
	velocity = direction * initial_speed
	
	# Slight random spin
	angular_velocity = randf_range(-30, 30)
	
	# Not landed yet
	landed = false

# Move and collide wrapper for physics-based movement
func move_and_collide(delta_movement: Vector2):
	# This is a simple implementation - can be enhanced with an actual KinematicBody
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
	return (other_node.global_position - global_position).normalized()
