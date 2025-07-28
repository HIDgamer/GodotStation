extends Weapon
class_name Gun

signal ammo_changed(current_ammo, max_ammo)
signal magazine_inserted(magazine)
signal magazine_ejected(magazine)
signal fire_mode_changed(new_mode)
signal gun_jammed()
signal gun_overheated()

enum FireMode {
	SEMIAUTO,
	BURST,
	AUTOMATIC
}

enum AmmoType {
	PISTOL,
	RIFLE,
	SHOTGUN,
	SNIPER,
	SPECIAL
}

# Gun-specific properties
@export var accepted_ammo_types: Array[AmmoType] = [AmmoType.PISTOL]
@export var fire_delay: float = 0.3  # Time between shots in seconds
@export var burst_amount: int = 3
@export var burst_delay: float = 0.1  # Time between burst shots
@export var auto_fire_rate: float = 10.0  # Rounds per second for full auto
@export var recoil_amount: float = 1.0
@export var scatter_amount: float = 2.0
@export var effective_range: float = 15.0
@export var max_range: float = 30.0
@export var muzzle_flash_enabled: bool = true
@export var auto_eject_magazine: bool = false

# Fire modes
@export var available_fire_modes: Array[FireMode] = [FireMode.SEMIAUTO]
var current_fire_mode: FireMode = FireMode.SEMIAUTO

# Ammo system
var current_magazine = null
var chambered_bullet = null
var rounds_in_chamber: int = 0

# Internal magazine properties
@export var internal_magazine: bool = false
@export var max_internal_rounds: int = 6
var internal_rounds: Array = []

# Firing state
var last_fired_time: float = 0.0
var burst_shots_fired: int = 0
var is_burst_firing: bool = false
var is_auto_firing: bool = false
var heat_level: float = 0.0
var max_heat: float = 100.0

# Ballistics
@export var bullet_speed: float = 50.0
@export var bullet_drop: bool = false
@export var projectile_scene: PackedScene

# Casing system
@export var eject_casings: bool = true
@export var casing_scene: PackedScene
@export var casing_eject_force: float = 150.0
@export var casing_eject_angle_offset: float = 45.0  # degrees

# Sound effects
@export var fire_sound: AudioStream
@export var empty_sound: AudioStream
@export var reload_sound: AudioStream
@export var cock_sound: AudioStream

func _ready():
	super._ready()
	weapon_type = WeaponType.RANGED
	requires_wielding = true  # Most guns require wielding
	entity_type = "gun"
	# Set default fire mode
	if available_fire_modes.size() > 0:
		current_fire_mode = available_fire_modes[0]
	
	# Initialize ammo system
	if internal_magazine:
		initialize_internal_magazine()
	
	# Load default casing scene if not set
	if not casing_scene and ResourceLoader.exists("res://Scenes/Effects/bulletcasings.tscn"):
		casing_scene = preload("res://Scenes/Effects/bulletcasings.tscn")
	
	add_to_group("guns")

func _process(delta):
	super._process(delta)
	
	# Handle heat dissipation
	if heat_level > 0:
		heat_level = max(0, heat_level - 50.0 * delta)  # Heat dissipates at 50/sec
		
		if is_overheating and heat_level < max_heat * 0.7:
			is_overheating = false

func initialize_internal_magazine():
	"""Initialize internal magazine for revolvers, etc."""
	internal_rounds.clear()
	for i in range(max_internal_rounds):
		internal_rounds.append(null)

func perform_weapon_action(user, target) -> bool:
	"""Override to handle gun firing"""
	if not can_fire():
		handle_fire_failure(user)
		return false
	
	return fire_gun(user, target)

func can_fire() -> bool:
	"""Check if the gun can fire"""
	if not super.can_use_weapon(get_user()):
		return false
	
	# Check if we have ammo
	if not has_ammo():
		return false
	
	# Check fire delay
	var time_since_last_shot = (Time.get_ticks_msec() / 1000.0) - last_fired_time
	if time_since_last_shot < fire_delay:
		return false
	
	# Check overheating
	if is_overheating:
		return false
	
	return true

func has_ammo() -> bool:
	"""Check if gun has ammunition"""
	if internal_magazine:
		for bullet in internal_rounds:
			if bullet != null:
				return true
		return false
	else:
		return chambered_bullet != null or (current_magazine and current_magazine.current_rounds > 0)

func get_current_ammo_count() -> int:
	"""Get current ammunition count"""
	if internal_magazine:
		var count = 0
		for bullet in internal_rounds:
			if bullet != null:
				count += 1
		return count
	else:
		var count = 0
		if chambered_bullet:
			count += 1
		if current_magazine:
			count += current_magazine.current_rounds
		return count

func get_max_ammo_count() -> int:
	"""Get maximum ammunition capacity"""
	if internal_magazine:
		return max_internal_rounds
	else:
		var max_count = 1  # Chamber
		if current_magazine:
			max_count += current_magazine.max_rounds
		return max_count

func fire_gun(user, target) -> bool:
	"""Main firing function"""
	var bullet = get_next_bullet()
	if not bullet:
		play_empty_sound()
		return false
	
	# Create and fire projectile
	var success = create_and_fire_projectile(user, target, bullet)
	
	if success:
		# Handle post-fire effects
		last_fired_time = Time.get_ticks_msec() / 1000.0
		add_heat(10.0)  # Add heat per shot
		
		# Handle fire modes
		match current_fire_mode:
			FireMode.BURST:
				handle_burst_fire(user, target)
			FireMode.AUTOMATIC:
				handle_auto_fire(user, target)
		
		# Eject casing
		eject_casing(user)
		
		# Chamber next round
		chamber_next_round()
		
		# Check for empty magazine auto-eject
		if auto_eject_magazine and current_magazine and current_magazine.current_rounds <= 0:
			eject_magazine(user)
		
		emit_signal("ammo_changed", get_current_ammo_count(), get_max_ammo_count())
	
	return success

func get_next_bullet():
	"""Get the next bullet to fire"""
	# First check chamber
	if chambered_bullet:
		var bullet = chambered_bullet
		chambered_bullet = null
		return bullet
	
	# Then check magazine/internal storage
	if internal_magazine:
		for i in range(internal_rounds.size()):
			if internal_rounds[i] != null:
				var bullet = internal_rounds[i]
				internal_rounds[i] = null
				return bullet
	elif current_magazine and current_magazine.current_rounds > 0:
		return current_magazine.extract_bullet()
	
	return null

func chamber_next_round():
	"""Chamber the next round if available"""
	if chambered_bullet:
		return  # Already chambered
	
	if internal_magazine:
		# For revolvers, the next round is already "chambered"
		return
	elif current_magazine and current_magazine.current_rounds > 0:
		chambered_bullet = current_magazine.extract_bullet()

func create_and_fire_projectile(user, target, bullet) -> bool:
	"""Create and fire a projectile"""
	if not projectile_scene:
		print("Warning: No projectile scene assigned to gun!")
		return false
	
	var projectile = projectile_scene.instantiate()
	if not projectile:
		return false
	
	# Set up projectile
	var world = user.get_parent()
	if not world:
		return false
	
	world.add_child(projectile)
	projectile.global_position = user.global_position
	
	# Calculate target position
	var target_pos: Vector2
	if target:
		target_pos = user.get_global_mouse_position()
	
	# Apply scatter
	target_pos += Vector2(
		randf_range(-scatter_amount, scatter_amount),
		randf_range(-scatter_amount, scatter_amount)
	)
	
	# Fire projectile
	if projectile.has_method("fire_at"):
		projectile.fire_at(target_pos, user, self)
	elif projectile.has_method("set_target"):
		projectile.set_target(target_pos)
	
	# Play effects
	play_fire_effects(user)
	
	return true

func handle_burst_fire(user, target):
	"""Handle burst fire mode"""
	if not is_burst_firing:
		is_burst_firing = true
		burst_shots_fired = 1
		
		# Schedule remaining burst shots
		for i in range(burst_amount - 1):
			var delay = burst_delay * (i + 1)
			get_tree().create_timer(delay).timeout.connect(func(): fire_burst_shot(user, target))

func fire_burst_shot(user, target):
	"""Fire a single shot in a burst"""
	if burst_shots_fired >= burst_amount:
		is_burst_firing = false
		burst_shots_fired = 0
		return
	
	if can_fire():
		fire_gun(user, target)
	
	burst_shots_fired += 1
	if burst_shots_fired >= burst_amount:
		is_burst_firing = false
		burst_shots_fired = 0

func handle_auto_fire(user, target):
	"""Handle automatic fire mode"""
	if not is_auto_firing:
		is_auto_firing = true
		start_auto_fire(user, target)

func start_auto_fire(user, target):
	"""Start automatic firing"""
	var auto_delay = 1.0 / auto_fire_rate
	
	while is_auto_firing and can_fire() and has_ammo():
		await get_tree().create_timer(auto_delay).timeout
		if is_auto_firing:
			fire_gun(user, target)

func stop_auto_fire():
	"""Stop automatic firing"""
	is_auto_firing = false

func handle_fire_failure(user):
	"""Handle firing failure"""
	if not has_ammo():
		play_empty_sound()
		show_message_to_user(user, "The " + item_name + " is empty!")
	else:
		super.handle_use_failure(user)

func add_heat(amount: float):
	"""Add heat to the gun"""
	heat_level = min(max_heat, heat_level + amount)
	
	if heat_level >= max_heat and not is_overheating:
		is_overheating = true
		emit_signal("gun_overheated")

func eject_casing(user):
	"""Eject a spent casing"""
	if not eject_casings or not casing_scene:
		return
	
	# Create casing
	var casing = casing_scene.instantiate()
	if not casing:
		return
	
	# Add to world
	var world = user.get_parent()
	if not world:
		return
	
	world.add_child(casing)
	
	# Position casing at gun/user location with slight randomness
	casing.global_position = user.global_position + Vector2(randf_range(-8, 8), randf_range(-8, 8))
	
	# Calculate eject direction (perpendicular to firing direction)
	var firing_direction = get_firing_direction(user)
	var eject_direction = firing_direction.rotated(deg_to_rad(casing_eject_angle_offset))
	
	# Add some randomness to eject direction
	eject_direction = eject_direction.rotated(deg_to_rad(randf_range(-15, 15)))
	
	# Start the casing animation
	if casing.has_method("eject_with_animation"):
		casing.eject_with_animation(eject_direction, casing_eject_force)

func get_firing_direction(user) -> Vector2:
	"""Get the direction the gun is firing"""
	if user and user.has_method("get_global_mouse_position"):
		return (user.get_global_mouse_position() - user.global_position).normalized()
	elif user and user.has_method("get_current_direction"):
		var direction_index = user.get_current_direction()
		var directions = [
			Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0),
			Vector2(1, -1).normalized(), Vector2(1, 1).normalized(),
			Vector2(-1, 1).normalized(), Vector2(-1, -1).normalized()
		]
		if direction_index < directions.size():
			return directions[direction_index]
	
	return Vector2.RIGHT  # Default direction

func play_fire_effects(user):
	"""Play firing sound and visual effects"""
	# Sound
	if fire_sound:
		play_audio(fire_sound, 0)
	
	# Muzzle flash
	if muzzle_flash_enabled:
		show_muzzle_flash(user)
	
	# Screen shake for user
	if user and user.has_method("add_screen_shake"):
		user.add_screen_shake(recoil_amount)

func show_muzzle_flash(user):
	"""Display muzzle flash effect"""
	# Create a brief light effect or sprite animation
	var flash = preload("res://Scenes/Effects/MuzzleFlash.tscn").instantiate() if ResourceLoader.exists("res://effects/MuzzleFlash.tscn") else null
	if flash and get_parent():
		get_parent().add_child(flash)
		flash.global_position = global_position
		flash.show_flash()

func play_empty_sound():
	"""Play empty gun sound"""
	if empty_sound:
		play_audio(empty_sound, -5)

# Magazine system
func can_accept_magazine(magazine) -> bool:
	"""Check if a magazine can be accepted"""
	if internal_magazine:
		return false
	
	if not magazine or not magazine.has_method("get_ammo_type"):
		return false
	
	return magazine.get_ammo_type() in accepted_ammo_types

func insert_magazine(magazine, user) -> bool:
	"""Insert a magazine into the gun"""
	if internal_magazine:
		show_message_to_user(user, "This gun doesn't use magazines!")
		return false
	
	if current_magazine:
		show_message_to_user(user, "There's already a magazine loaded!")
		return false
	
	if not can_accept_magazine(magazine):
		show_message_to_user(user, "This magazine doesn't fit!")
		return false
	
	current_magazine = magazine
	
	chamber_next_round()
	
	if reload_sound:
		play_audio(reload_sound, -5)
	
	show_message_to_user(user, "You load the magazine into " + item_name + ".")
	emit_signal("magazine_inserted", magazine)
	emit_signal("ammo_changed", get_current_ammo_count(), get_max_ammo_count())
	
	return true

func eject_magazine(user) -> bool:
	"""Eject the current magazine"""
	if internal_magazine:
		show_message_to_user(user, "This gun doesn't use magazines!")
		return false
	
	if not current_magazine:
		show_message_to_user(user, "There's no magazine to eject!")
		return false
	
	var ejected_mag = current_magazine
	current_magazine = null
	
	# Drop magazine or put in user's hand
	if user and user.has_method("try_put_in_hands"):
		if not user.try_put_in_hands(ejected_mag):
			drop_magazine_at_feet(user, ejected_mag)
	else:
		drop_magazine_at_feet(user, ejected_mag)
	
	show_message_to_user(user, "You eject the magazine from " + item_name + ".")
	emit_signal("magazine_ejected", ejected_mag)
	emit_signal("ammo_changed", get_current_ammo_count(), get_max_ammo_count())
	
	return true

func drop_magazine_at_feet(user, magazine):
	"""Drop magazine at user's feet"""
	var world = user.get_parent()
	if world and magazine.get_parent() != world:
		if magazine.get_parent():
			magazine.get_parent().remove_child(magazine)
		world.add_child(magazine)
	
	magazine.global_position = user.global_position + Vector2(0, 32)

# Fire mode management
func cycle_fire_mode(user) -> bool:
	"""Cycle through available fire modes"""
	if available_fire_modes.size() <= 1:
		return false
	
	var current_index = available_fire_modes.find(current_fire_mode)
	var next_index = (current_index + 1) % available_fire_modes.size()
	current_fire_mode = available_fire_modes[next_index]
	
	var mode_name = get_fire_mode_name(current_fire_mode)
	show_message_to_user(user, "Fire mode: " + mode_name)
	
	emit_signal("fire_mode_changed", current_fire_mode)
	return true

func get_fire_mode_name(mode: FireMode) -> String:
	"""Get display name for fire mode"""
	match mode:
		FireMode.SEMIAUTO:
			return "Semi-Auto"
		FireMode.BURST:
			return "Burst (" + str(burst_amount) + ")"
		FireMode.AUTOMATIC:
			return "Full Auto"
		_:
			return "Unknown"

func get_user():
	"""Get the current user of the gun"""
	return inventory_owner

# Interaction overrides
func interact(user) -> bool:
	"""Handle interaction - try to eject magazine"""
	if current_magazine:
		return eject_magazine(user)
	return super.interact(user)

func attack_self(user):
	"""Handle self-interaction - cycle fire mode or toggle safety"""
	if Input.is_key_pressed(KEY_SHIFT):
		cycle_fire_mode(user)
	else:
		toggle_safety(user)

# Helper functions
func show_message_to_user(user, message: String):
	"""Show message to user"""
	if user and user.has_method("show_message"):
		user.show_message(message)
	else:
		print(message)

# Serialization
func serialize() -> Dictionary:
	var data = super.serialize()
	data.merge({
		"current_fire_mode": current_fire_mode,
		"heat_level": heat_level,
		"has_chambered_bullet": chambered_bullet != null,
		"internal_rounds_count": internal_rounds.size() if internal_magazine else 0
	})
	return data

func deserialize(data: Dictionary):
	super.deserialize(data)
	if "current_fire_mode" in data: current_fire_mode = data.current_fire_mode
	if "heat_level" in data: heat_level = data.heat_level
	if "has_chambered_bullet" in data and data.has_chambered_bullet:
		# You'd need to recreate the actual bullet object here
		pass
