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

@export var accepted_ammo_types: Array[AmmoType] = [AmmoType.PISTOL]
@export var fire_delay: float = 0.3
@export var burst_amount: int = 3
@export var burst_delay: float = 0.1
@export var auto_fire_rate: float = 10.0
@export var recoil_amount: float = 1.0
@export var scatter_amount: float = 0.2
@export var effective_range: float = 15.0
@export var max_range: float = 30.0
@export var muzzle_flash_enabled: bool = false
@export var auto_eject_magazine: bool = false
@export var accurate_range_tiles: int = 5
@export var drift_chance: float = 0.05

@export var available_fire_modes: Array[FireMode] = [FireMode.SEMIAUTO]
var current_fire_mode: FireMode = FireMode.SEMIAUTO

var current_magazine = null
var chambered_bullet = null
var rounds_in_chamber: int = 0
var temporary_scatter_bonus: float = 0.0

@export var internal_magazine: bool = false
@export var max_internal_rounds: int = 6
var internal_rounds: Array = []

var last_fired_time: float = 0.0
var burst_shots_fired: int = 0
var is_burst_firing: bool = false
var is_auto_firing: bool = false
var heat_level: float = 0.0
var max_heat: float = 100.0

@export var bullet_speed: float = 50.0
@export var bullet_drop: bool = false
@export var projectile_scene: PackedScene

@export var eject_casings: bool = true
@export var casing_scene: PackedScene
@export var casing_eject_force: float = 150.0
@export var casing_eject_angle_offset: float = 45.0

@export var fire_sound: AudioStream
@export var empty_sound: AudioStream
@export var reload_sound: AudioStream
@export var cock_sound: AudioStream

func _ready():
	super._ready()
	weapon_type = WeaponType.RANGED
	requires_wielding = true
	entity_type = "gun"
	
	if available_fire_modes.size() > 0:
		current_fire_mode = available_fire_modes[0]
	
	if internal_magazine:
		initialize_internal_magazine()
	
	if not casing_scene and ResourceLoader.exists("res://Scenes/Effects/bulletcasings.tscn"):
		casing_scene = preload("res://Scenes/Effects/bulletcasings.tscn")
	
	add_to_group("guns")

func _process(delta):
	super._process(delta)
	
	if heat_level > 0:
		heat_level = max(0, heat_level - 50.0 * delta)
		
		if is_overheating and heat_level < max_heat * 0.7:
			is_overheating = false

func initialize_internal_magazine():
	internal_rounds.clear()
	for i in range(max_internal_rounds):
		internal_rounds.append(null)

func perform_weapon_action(user, target) -> bool:
	if not can_fire():
		handle_fire_failure(user)
		return false
	
	return fire_gun(user, target)

func can_use_weapon(user) -> bool:
	if not user:
		return false
	
	if requires_wielding and not is_wielded():
		return true
	
	return super.can_use_weapon(user)

func add_scatter(amount: float):
	temporary_scatter_bonus += amount
	
	get_tree().create_timer(2.0).timeout.connect(func(): reduce_scatter_penalty())

func reduce_scatter_penalty():
	temporary_scatter_bonus = max(0.0, temporary_scatter_bonus - 0.1)

func can_fire() -> bool:
	if not super.can_use_weapon(get_user()):
		return false
	
	if not has_ammo():
		return false
	
	var time_since_last_shot = (Time.get_ticks_msec() / 1000.0) - last_fired_time
	if time_since_last_shot < fire_delay:
		return false
	
	if is_overheating:
		return false
	
	return true

func has_ammo() -> bool:
	if internal_magazine:
		for bullet in internal_rounds:
			if bullet != null:
				return true
		return false
	else:
		return chambered_bullet != null or (current_magazine and current_magazine.current_rounds > 0)

func get_current_ammo_count() -> int:
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
	if internal_magazine:
		return max_internal_rounds
	else:
		var max_count = 1
		if current_magazine:
			max_count += current_magazine.max_rounds
		return max_count

func fire_gun(user, target) -> bool:
	var bullet = get_next_bullet()
	if not bullet:
		play_empty_sound()
		return false
	
	var success = create_and_fire_projectile(user, target, bullet)
	
	if success:
		last_fired_time = Time.get_ticks_msec() / 1000.0
		add_heat(10.0)
		
		sync_gun_fired(user, target)
		
		match current_fire_mode:
			FireMode.BURST:
				handle_burst_fire(user, target)
			FireMode.AUTOMATIC:
				handle_auto_fire(user, target)
		
		eject_casing(user)
		chamber_next_round()
		
		if auto_eject_magazine and current_magazine and current_magazine.current_rounds <= 0:
			eject_magazine(user)
		
		emit_signal("ammo_changed", get_current_ammo_count(), get_max_ammo_count())
	
	return success

func sync_gun_fired(user, target):
	if multiplayer.has_multiplayer_peer():
		var user_id = get_user_network_id(user)
		var target_pos = get_target_position(user, target)
		network_gun_fired.rpc(user_id, target_pos, weapon_damage)

func get_user_network_id(user) -> String:
	if user.has_method("get_network_id"):
		return user.get_network_id()
	elif user.has_meta("peer_id"):
		return str(user.get_meta("peer_id"))
	else:
		return str(user.get_instance_id())

func get_target_position(user, target) -> Vector2:
	if target is Node2D:
		return target.global_position
	elif target is Vector2:
		return target
	elif user and user.has_method("get_global_mouse_position"):
		return user.get_global_mouse_position()
	else:
		return user.global_position + Vector2(100, 0)

@rpc("any_peer", "call_local", "reliable")
func network_gun_fired(user_id: String, target_pos: Vector2, damage_amount: float):
	var user = find_user_by_id(user_id)
	if user:
		play_fire_effects(user)

func find_user_by_id(user_id: String):
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if get_user_network_id(player) == user_id:
			return player
	return null

func apply_one_handed_gun_effects(user):
	add_heat(5.0)
	
	if "current_durability" in self:
		apply_durability_loss(0.2)
	
	if user and user.has_node("WeaponHandlingComponent"):
		var weapon_handler = user.get_node("WeaponHandlingComponent")
		if weapon_handler.has_method("apply_one_handed_firing_effects"):
			weapon_handler.apply_one_handed_firing_effects(self)

func is_wielded() -> bool:
	if "wielded" in self:
		return wielded
	
	if inventory_owner and inventory_owner.has_node("WeaponHandlingComponent"):
		var weapon_handler = inventory_owner.get_node("WeaponHandlingComponent")
		if weapon_handler.has_method("is_wielded_weapon"):
			return weapon_handler.is_wielded_weapon(self)
	
	return false

func get_primary_ammo_type() -> AmmoType:
	if accepted_ammo_types.size() > 0:
		return accepted_ammo_types[0]
	return AmmoType.PISTOL

func get_next_bullet():
	if chambered_bullet:
		var bullet = chambered_bullet
		chambered_bullet = null
		return bullet
	
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
	if chambered_bullet:
		return
	
	if internal_magazine:
		return
	elif current_magazine and current_magazine.has_method("extract_bullet"):
		var bullet = current_magazine.extract_bullet()
		if bullet:
			chambered_bullet = bullet
	elif current_magazine and "current_rounds" in current_magazine and current_magazine.current_rounds > 0:
		chambered_bullet = true
		current_magazine.current_rounds -= 1

func create_and_fire_projectile(user, target, bullet) -> bool:
	if not projectile_scene:
		print("Warning: No projectile scene assigned to gun!")
		return false
	
	var projectile = projectile_scene.instantiate()
	if not projectile:
		return false
	
	var world = user.get_parent()
	if not world:
		return false
	
	var target_pos: Vector2
	if target is Node2D:
		target_pos = target.global_position
	elif target is Vector2:
		target_pos = target
	else:
		target_pos = user.get_global_mouse_position()
	
	var firing_direction = (target_pos - user.global_position).normalized()
	var spawn_position = user.global_position + firing_direction * 40.0
	
	world.add_child(projectile)
	projectile.global_position = spawn_position
	
	var final_target_pos = calculate_accurate_target_position(user, target_pos)
	
	if projectile.has_method("set_damage"):
		projectile.set_damage(weapon_damage)
	
	if projectile.has_method("set_speed"):
		projectile.set_speed(bullet_speed)
	
	if projectile.has_method("set_accuracy"):
		projectile.set_accuracy(weapon_accuracy)
	
	if projectile.has_method("fire_at"):
		projectile.fire_at(final_target_pos, user, self)
	elif projectile.has_method("set_target"):
		projectile.set_target(final_target_pos)
	
	play_fire_effects(user)
	
	return true

func calculate_accurate_target_position(user, target_pos: Vector2) -> Vector2:
	var distance_to_target = user.global_position.distance_to(target_pos)
	var tile_size = 32.0
	var accurate_range_pixels = accurate_range_tiles * tile_size
	
	var total_scatter = scatter_amount + temporary_scatter_bonus
	
	if distance_to_target <= accurate_range_pixels:
		var final_pos = target_pos
		if randf() < drift_chance:
			final_pos += Vector2(
				randf_range(-total_scatter, total_scatter),
				randf_range(-total_scatter, total_scatter)
			)
		return final_pos
	else:
		var direction = (target_pos - user.global_position).normalized()
		var travel_distance = min(distance_to_target, max_range * tile_size)
		var final_pos = user.global_position + direction * travel_distance
		
		if randf() < drift_chance:
			final_pos += Vector2(
				randf_range(-total_scatter, total_scatter),
				randf_range(-total_scatter, total_scatter)
			)
		return final_pos

func handle_burst_fire(user, target):
	if not is_burst_firing:
		is_burst_firing = true
		burst_shots_fired = 1
		
		for i in range(burst_amount - 1):
			var delay = burst_delay * (i + 1)
			get_tree().create_timer(delay).timeout.connect(func(): fire_burst_shot(user, target))

func fire_burst_shot(user, target):
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
	if not is_auto_firing:
		is_auto_firing = true
		start_auto_fire(user, target)

func start_auto_fire(user, target):
	var auto_delay = 1.0 / auto_fire_rate
	
	while is_auto_firing and can_fire() and has_ammo():
		await get_tree().create_timer(auto_delay).timeout
		if is_auto_firing:
			fire_gun(user, target)

func stop_auto_fire():
	is_auto_firing = false

func handle_fire_failure(user):
	if not has_ammo():
		play_empty_sound()
		show_message_to_user(user, "The " + item_name + " is empty!")
	else:
		super.handle_use_failure(user)

func add_heat(amount: float):
	heat_level = min(max_heat, heat_level + amount)
	
	if heat_level >= max_heat and not is_overheating:
		is_overheating = true
		emit_signal("gun_overheated")

func eject_casing(user):
	if not eject_casings or not casing_scene:
		return
	
	var casing = casing_scene.instantiate()
	if not casing:
		return
	
	var world = user.get_parent()
	if not world:
		return
	
	world.add_child(casing)
	
	casing.global_position = user.global_position + Vector2(randf_range(-8, 8), randf_range(-8, 8))
	
	var firing_direction = get_firing_direction(user)
	var eject_direction = firing_direction.rotated(deg_to_rad(casing_eject_angle_offset))
	
	eject_direction = eject_direction.rotated(deg_to_rad(randf_range(-15, 15)))
	
	if casing.has_method("eject_with_animation"):
		casing.eject_with_animation(eject_direction, casing_eject_force)

func get_firing_direction(user) -> Vector2:
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
	
	return Vector2.RIGHT

func play_fire_effects(user):
	if fire_sound:
		play_audio(fire_sound, 0)
	
	if muzzle_flash_enabled:
		show_muzzle_flash(user)
	
	if user and user.has_method("add_screen_shake"):
		user.add_screen_shake(recoil_amount)

func show_muzzle_flash(user):
	var flash = preload("res://Scenes/Effects/MuzzleFlash.tscn").instantiate() if ResourceLoader.exists("res://effects/MuzzleFlash.tscn") else null
	if flash and get_parent():
		get_parent().add_child(flash)
		flash.global_position = global_position
		flash.show_flash()

func play_empty_sound():
	if empty_sound:
		play_audio(empty_sound, -5)

func can_accept_magazine(magazine) -> bool:
	if internal_magazine:
		return false
	
	if not magazine or not magazine.has_method("get_ammo_type"):
		return false
	
	return magazine.get_ammo_type() in accepted_ammo_types

func insert_magazine(magazine, user) -> bool:
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

func get_magazine():
	return current_magazine

func remove_magazine():
	if not current_magazine:
		return null
	
	var ejected_mag = current_magazine
	current_magazine = null
	
	emit_signal("magazine_ejected", ejected_mag)
	emit_signal("ammo_changed", get_current_ammo_count(), get_max_ammo_count())
	
	return ejected_mag

func eject_magazine_raw():
	if internal_magazine:
		return null
	
	if not current_magazine:
		return null
	
	var ejected_mag = current_magazine
	current_magazine = null
	
	emit_signal("magazine_ejected", ejected_mag)
	emit_signal("ammo_changed", get_current_ammo_count(), get_max_ammo_count())
	
	return ejected_mag

func eject_magazine(user):
	if internal_magazine:
		show_message_to_user(user, "This gun doesn't use magazines!")
		return null
	
	if not current_magazine:
		show_message_to_user(user, "There's no magazine to eject!")
		return null
	
	var ejected_mag = current_magazine
	current_magazine = null
	
	if user and user.has_method("try_put_in_hands"):
		if not user.try_put_in_hands(ejected_mag):
			drop_magazine_at_feet(user, ejected_mag)
	else:
		drop_magazine_at_feet(user, ejected_mag)
	
	show_message_to_user(user, "You eject the magazine from " + item_name + ".")
	emit_signal("magazine_ejected", ejected_mag)
	emit_signal("ammo_changed", get_current_ammo_count(), get_max_ammo_count())
	
	return ejected_mag

func drop_magazine_at_feet(user, magazine):
	var world = user.get_parent()
	if world and magazine.get_parent() != world:
		if magazine.get_parent():
			magazine.get_parent().remove_child(magazine)
		world.add_child(magazine)
	
	magazine.global_position = user.global_position + Vector2(0, 32)

func cycle_fire_mode(user) -> bool:
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
	return inventory_owner

func interact(user) -> bool:
	if current_magazine:
		return eject_magazine(user)
	return super.interact(user)

func attack_self(user):
	if Input.is_key_pressed(KEY_SHIFT):
		cycle_fire_mode(user)
	else:
		toggle_safety(user)

func show_message_to_user(user, message: String):
	if user and user.has_method("show_message"):
		user.show_message(message)
	else:
		print(message)

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
		pass
