extends Gun
class_name AssaultRifle

func _init():
	super._init()
	
	item_name = "assault rifle"
	obj_name = "assault_rifle"
	description = "A military-grade automatic rifle. Effective at medium to long range with multiple fire modes."
	
	weapon_damage = 80.0
	weapon_accuracy = 100.0
	weapon_range = 25.0
	force = 12
	
	accepted_ammo_types = [Gun.AmmoType.RIFLE]
	fire_delay = 0.12
	burst_amount = 5
	burst_delay = 0.08
	auto_fire_rate = 8.0
	max_range = 50.0
	close_range_tiles = 5
	optimal_range_tiles = 10
	bullet_speed = 1600.0
	
	available_fire_modes = [Gun.FireMode.SEMIAUTO, Gun.FireMode.BURST, Gun.FireMode.AUTOMATIC]
	current_fire_mode = Gun.FireMode.SEMIAUTO
	
	eject_casings = true
	casing_eject_force = 180.0
	casing_eject_angle_offset = 90.0
	
	w_class = 4
	requires_wielding = true
	
	equip_slot_flags = Slots.LEFT_HAND | Slots.RIGHT_HAND | Slots.BACK | Slots.S_STORE
	
	var rifle_fire_sound = preload("res://Sound/weapons/gun_m16.ogg") if ResourceLoader.exists("res://Sound/weapons/gun_m16.ogg") else null
	var rifle_empty_sound = preload("res://Sound/weapons/handling/gun_m16_unload.ogg") if ResourceLoader.exists("res://Sound/weapons/handling/gun_m16_unload.ogg") else null
	var rifle_reload_sound = preload("res://Sound/weapons/handling/gun_m16_reload.ogg") if ResourceLoader.exists("res://Sound/weapons/handling/gun_m16_reload.ogg") else null
	
	if rifle_fire_sound:
		fire_sound = rifle_fire_sound
	if rifle_empty_sound:
		empty_sound = rifle_empty_sound
	if rifle_reload_sound:
		reload_sound = rifle_reload_sound

func _ready():
	super._ready()
	
	if ResourceLoader.exists("res://Scenes/Effects/Projectile.tscn"):
		projectile_scene = preload("res://Scenes/Effects/Projectile.tscn")
	
	if ResourceLoader.exists("res://Scenes/Effects/bulletcasings.tscn"):
		casing_scene = preload("res://Scenes/Effects/bulletcasings.tscn")
	
	attack_verb = ["shoots", "fires at", "blasts", "sprays"]
	attack_speed = 1.0
	
	update_icon_state()

func remove_magazine():
	var ejected_mag = super.remove_magazine()
	if ejected_mag:
		update_icon_state()
	return ejected_mag

func eject_magazine_raw():
	var ejected_mag = super.eject_magazine_raw()
	if ejected_mag:
		update_icon_state()
	return ejected_mag

func update_icon_state():
	var icon_node = get_node_or_null("Icon")
	if not icon_node or not icon_node is AnimatedSprite2D:
		return
	
	var animated_sprite = icon_node as AnimatedSprite2D
	
	if not animated_sprite.sprite_frames:
		return
	
	if current_magazine:
		if animated_sprite.sprite_frames.has_animation("Full"):
			animated_sprite.play("Full")
	else:
		if animated_sprite.sprite_frames.has_animation("Empty"):
			animated_sprite.play("Empty")

func create_and_fire_projectile(user, target, bullet) -> bool:
	if not user or not is_instance_valid(user):
		return false
	
	if not super.create_and_fire_projectile(user, target, bullet):
		return false
	
	create_firing_particles(user)
	
	if multiplayer.has_multiplayer_peer():
		var user_id = get_user_network_id(user)
		var target_pos = get_target_position(user, target)
		var direction = get_user_facing_direction(user)
		sync_rifle_fired.rpc(user_id, target_pos, true, direction, current_fire_mode)
	
	return true

func create_firing_particles(user):
	var particles_intensity = 1.0
	var particles_duration = 0.1
	
	match current_fire_mode:
		Gun.FireMode.SEMIAUTO:
			particles_intensity = 1.0
			particles_duration = 0.1
		Gun.FireMode.BURST:
			particles_intensity = 1.5
			particles_duration = 0.2
		Gun.FireMode.AUTOMATIC:
			particles_intensity = 2.0
			particles_duration = 0.3
	
	create_smoke_particles(user, particles_intensity, particles_duration)
	create_fire_particles(user, particles_intensity, particles_duration)

func create_smoke_particles(user, intensity: float, duration: float):
	var smoke_particles = GPUParticles2D.new()
	smoke_particles.name = "SmokeParticles"
	
	var material = ParticleProcessMaterial.new()
	material.direction = Vector3(0, -1, 0)
	material.spread = 15.0
	material.initial_velocity_min = 30.0 * intensity
	material.initial_velocity_max = 60.0 * intensity
	material.gravity = Vector3(0, -50, 0)
	material.scale_min = 0.3
	material.scale_max = 0.8 * intensity
	material.color = Color(0.7, 0.7, 0.7, 0.8)
	
	smoke_particles.amount = int(25 * intensity)
	smoke_particles.lifetime = duration * 5
	smoke_particles.emitting = true
	smoke_particles.process_material = material
	
	user.get_parent().add_child(smoke_particles)
	var user_stable_pos = get_user_stable_world_position(user)
	smoke_particles.global_position = user_stable_pos + get_barrel_offset(user)
	
	get_tree().create_timer(duration).timeout.connect(func(): 
		smoke_particles.emitting = false
		get_tree().create_timer(smoke_particles.lifetime).timeout.connect(func(): smoke_particles.queue_free())
	)

func create_fire_particles(user, intensity: float, duration: float):
	var fire_particles = GPUParticles2D.new()
	fire_particles.name = "FireParticles"
	
	var material = ParticleProcessMaterial.new()
	material.direction = Vector3(1, 0, 0)
	material.spread = 30.0
	material.initial_velocity_min = 80.0 * intensity
	material.initial_velocity_max = 120.0 * intensity
	material.scale_min = 0.1
	material.scale_max = 0.4 * intensity
	material.color = Color(1.0, 0.6, 0.2, 1.0)
	
	fire_particles.amount = int(15 * intensity)
	fire_particles.lifetime = duration * 2
	fire_particles.emitting = true
	fire_particles.process_material = material
	
	user.get_parent().add_child(fire_particles)
	var user_stable_pos = get_user_stable_world_position(user)
	fire_particles.global_position = user_stable_pos + get_barrel_offset(user)
	
	get_tree().create_timer(duration * 0.5).timeout.connect(func(): 
		fire_particles.emitting = false
		get_tree().create_timer(fire_particles.lifetime).timeout.connect(func(): fire_particles.queue_free())
	)

func get_user_stable_world_position(user) -> Vector2:
	if user.has_method("get_current_tile_position"):
		return tile_to_world(user.get_current_tile_position())
	elif user.has_node("MovementComponent"):
		var movement_comp = user.get_node("MovementComponent")
		if movement_comp.has_method("get_current_tile_position"):
			return tile_to_world(movement_comp.get_current_tile_position())
		elif "current_tile_position" in movement_comp:
			return tile_to_world(movement_comp.current_tile_position)
	
	return user.global_position

func get_barrel_offset(user) -> Vector2:
	var direction = get_user_facing_direction(user)
	match direction:
		0: return Vector2(0, -24)
		1: return Vector2(24, 0)
		2: return Vector2(0, 24)
		3: return Vector2(-24, 0)
		4: return Vector2(16, -16)
		5: return Vector2(16, 16)
		6: return Vector2(-16, 16)
		7: return Vector2(-16, -16)
		_: return Vector2(24, 0)

func get_user_facing_direction(user) -> int:
	if not user:
		return 2
	
	if user.has_method("get_current_direction"):
		return user.get_current_direction()
	elif "movement_component" in user and user.movement_component:
		if user.movement_component.has_method("get_current_direction"):
			return user.movement_component.get_current_direction()
		elif "current_direction" in user.movement_component:
			return user.movement_component.current_direction
	elif "current_direction" in user:
		return user.current_direction
	
	return 2

func can_use_weapon(user) -> bool:
	if not user:
		return false
	
	return super.can_use_weapon(user)

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
	update_icon_state()
	
	if reload_sound:
		play_audio(reload_sound, -3)
	
	show_message_to_user(user, "You load the magazine into " + item_name + ".")
	emit_signal("magazine_inserted", magazine)
	emit_signal("ammo_changed", get_current_ammo_count(), get_max_ammo_count())
	
	return true

func eject_magazine(user) -> bool:
	if internal_magazine:
		show_message_to_user(user, "This gun doesn't use magazines!")
		return false
	
	if not current_magazine:
		show_message_to_user(user, "There's no magazine to eject!")
		return false
	
	var ejected_mag = current_magazine
	current_magazine = null
	
	update_icon_state()
	
	if user and user.get_node("InventorySystem"):
		var inventory = user.get_node("InventorySystem")
		if inventory:
			inventory._show_item_icon(ejected_mag)
	
	if user and user.has_method("try_put_in_hands"):
		if not user.try_put_in_hands(ejected_mag):
			drop_magazine_at_feet(user, ejected_mag)
	else:
		drop_magazine_at_feet(user, ejected_mag)
	
	show_message_to_user(user, "You eject the magazine from " + item_name + ".")
	emit_signal("magazine_ejected", ejected_mag)
	emit_signal("ammo_changed", get_current_ammo_count(), get_max_ammo_count())
	
	return true

func attack(target, user):
	if not target or not user:
		return false
	
	var damage = force + 5
	var attack_verb = "rifle-butts"
	
	var health_system = null
	if target.has_node("HealthSystem"):
		health_system = target.get_node("HealthSystem")
	elif target.get_parent() and target.get_parent().has_node("HealthSystem"):
		health_system = target.get_parent().get_node("HealthSystem")
	
	if health_system and health_system.has_method("apply_damage"):
		var damage_type = health_system.DamageType.BRUTE if "DamageType" in health_system else 0
		health_system.apply_damage(damage, damage_type, 0, "head", user)
	elif target.has_method("take_damage"):
		target.take_damage(damage, "brute", "melee", true, 0, user)
	
	if user.has_method("visible_message"):
		user.visible_message(
			user.name + " " + attack_verb + " " + target.name + " with " + item_name + "!",
			"You " + attack_verb + " " + target.name + " with " + item_name + "!"
		)
	
	var hit_sound = preload("res://Sound/weapons/genhit1.ogg") if ResourceLoader.exists("res://Sound/weapons/genhit1.ogg") else null
	if hit_sound:
		play_audio(hit_sound, -3)
	
	return true

func afterattack(target, user, proximity: bool, params: Dictionary = {}):
	if proximity:
		return use_weapon(user, target)
	else:
		if user:
			var user_stable_pos = get_user_stable_world_position(user)
			var distance = user_stable_pos.distance_to(target.global_position if target is Node2D else target)
			if distance > max_range * 32:
				show_message_to_user(user, "That target is beyond the rifle's maximum range.")
			else:
				return use_weapon(user, target)
		return false

func examine(user) -> String:
	var text = super.examine(user)
	
	text += "\nThis is a military assault rifle designed for versatile combat operations."
	text += "\nIt supports multiple fire modes for different tactical situations."
	
	if current_magazine:
		text += "\nA magazine is loaded."
	else:
		text += "\nNo magazine is loaded."
	
	if chambered_bullet:
		text += " There's a round in the chamber."
	else:
		text += " The chamber is empty."
	
	text += "\nFire mode: " + get_fire_mode_name(current_fire_mode)
	
	return text

func use_on(target, user) -> bool:
	if not target or not user:
		return false
	
	var user_stable_pos = get_user_stable_world_position(user)
	var target_pos = target.global_position if target is Node2D else target
	var distance = user_stable_pos.distance_to(target_pos)
	
	if distance > max_range * 32:
		show_message_to_user(user, "That target is beyond the rifle's maximum range.")
		return false
	
	return use_weapon(user, target)

func cycle_fire_mode(user) -> bool:
	if not super.cycle_fire_mode(user):
		return false
	
	var mode_sound = preload("res://Sound/weapons/handling/gun_cmb_click1.ogg") if ResourceLoader.exists("res://Sound/weapons/handling/gun_cmb_click1.ogg") else null
	if mode_sound:
		play_audio(mode_sound, -8)
	
	return true

@rpc("any_peer", "call_local", "reliable")
func sync_rifle_fired(shooter_id: String, target_pos: Vector2, hit: bool, direction: int, fire_mode: int):
	var shooter = find_user_by_id(shooter_id)
	if not shooter:
		return
	
	play_fire_effects(shooter)

func show_message_to_user(user, message: String):
	if user and user.has_method("show_message"):
		user.show_message(message)
	elif user and user.has_method("visible_message"):
		user.visible_message(message, message)
	else:
		print(message)

func serialize() -> Dictionary:
	var data = super.serialize()
	data.merge({
		"rifle_type": "assault",
		"has_magazine": current_magazine != null,
		"magazine_data": current_magazine.serialize() if current_magazine else {}
	})
	return data

func deserialize(data: Dictionary):
	super.deserialize(data)
	
	if "has_magazine" in data and data.has_magazine and "magazine_data" in data:
		pass
	
	update_icon_state()
