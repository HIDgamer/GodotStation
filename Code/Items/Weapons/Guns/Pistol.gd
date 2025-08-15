extends Gun
class_name Pistol

func _init():
	super._init()
	
	item_name = "pistol"
	obj_name = "pistol"
	description = "A reliable sidearm. Standard issue for security and military personnel."
	
	weapon_damage = 35.0
	weapon_accuracy = 95.0
	weapon_range = 12.0
	force = 8
	
	accepted_ammo_types = [Gun.AmmoType.PISTOL]
	fire_delay = 0.4
	recoil_amount = 1.5
	scatter_amount = 0.5
	effective_range = 5.0
	max_range = 30.0
	bullet_speed = 1000.0
	accurate_range_tiles = 10
	drift_chance = 0.03
	
	available_fire_modes = [Gun.FireMode.SEMIAUTO]
	current_fire_mode = Gun.FireMode.SEMIAUTO
	
	max_heat = 80.0
	
	eject_casings = true
	casing_eject_force = 120.0
	casing_eject_angle_offset = 45.0
	
	w_class = 2
	requires_wielding = false
	
	equip_slot_flags = Slots.LEFT_HAND | Slots.RIGHT_HAND | Slots.BELT | Slots.IN_L_POUCH | Slots.IN_R_POUCH | Slots.IN_SUIT
	
	var pistol_fire_sound = preload("res://Sound/weapons/Shot.wav") if ResourceLoader.exists("res://Sound/weapons/gunshot_pistol.wav") else null
	var pistol_empty_sound = preload("res://Sound/weapons/gun_pistol_cocked.ogg") if ResourceLoader.exists("res://Sound/weapons/gun_empty.ogg") else null
	var pistol_reload_sound = preload("res://Sound/weapons/Reload.wav") if ResourceLoader.exists("res://Sound/weapons/pistol_reload.wav") else null
	
	if pistol_fire_sound:
		fire_sound = pistol_fire_sound
	if pistol_empty_sound:
		empty_sound = pistol_empty_sound
	if pistol_reload_sound:
		reload_sound = pistol_reload_sound

func _ready():
	super._ready()
	
	if ResourceLoader.exists("res://Scenes/Effects/Projectile.tscn"):
		projectile_scene = preload("res://Scenes/Effects/Projectile.tscn")
	
	if ResourceLoader.exists("res://Scenes/Effects/bulletcasings.tscn"):
		casing_scene = preload("res://Scenes/Effects/bulletcasings.tscn")
	
	attack_verb = ["shoots", "fires at", "blasts"]
	attack_speed = 1.2

func remove_magazine():
	var ejected_mag = super.remove_magazine()
	return ejected_mag

func eject_magazine_raw():
	var ejected_mag = super.eject_magazine_raw()
	return ejected_mag

func can_use_weapon(user) -> bool:
	if not user:
		return false
	
	var original_wielding_requirement = requires_wielding
	requires_wielding = false
	var result = super.can_use_weapon(user)
	requires_wielding = original_wielding_requirement
	
	return result

func create_and_fire_projectile(user, target, bullet) -> bool:
	if not super.create_and_fire_projectile(user, target, bullet):
		return false
	
	show_muzzle_flash(user)
	add_recoil_effect(user)
	
	if multiplayer.has_multiplayer_peer():
		var user_id = get_user_network_id(user)
		var target_pos = get_target_position(user, target)
		var direction = get_user_facing_direction(user)
		sync_pistol_fired.rpc(user_id, target_pos, true, direction)
	
	return true

func show_muzzle_flash(user):
	var icon_node = get_node_or_null("Icon")
	if not icon_node or not icon_node is AnimatedSprite2D:
		return
	
	var animated_sprite = icon_node as AnimatedSprite2D
	
	if not animated_sprite.sprite_frames or not animated_sprite.sprite_frames.has_animation("Flash"):
		push_warning("Pistol: 'Flash' animation not found in Icon node")
		return
	
	var user_direction = get_user_facing_direction(user)
	
	animated_sprite.rotation_degrees = convert_direction_to_rotation(user_direction)
	
	animated_sprite.play("Flash")
	
	var timer = Timer.new()
	add_child(timer)
	timer.wait_time = 0.2
	timer.one_shot = true
	timer.timeout.connect(func(): 
		animated_sprite.stop()
		timer.queue_free()
	)
	timer.start()

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

func convert_direction_to_rotation(direction: int) -> float:
	match direction:
		0:
			return 0.0
		1:
			return 90.0
		2:
			return 180.0
		3:
			return 270.0
		4:
			return 45.0
		5:
			return 135.0
		6:
			return 225.0
		7:
			return 315.0
		_:
			return 180.0

func add_recoil_effect(user):
	if not user:
		return
	
	var actual_recoil = recoil_amount
	
	if not is_wielded():
		actual_recoil *= 1.1
	else:
		if is_wielded():
			actual_recoil *= 0.7
	
	if user.has_method("add_screen_shake"):
		user.add_screen_shake(actual_recoil * 0.5)

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

func eject_magazine(user) -> bool:
	if internal_magazine:
		show_message_to_user(user, "This gun doesn't use magazines!")
		return false
	
	if not current_magazine:
		show_message_to_user(user, "There's no magazine to eject!")
		return false
	
	var ejected_mag = current_magazine
	current_magazine = null
	
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
	
	var damage = force
	var attack_verb = "pistol-whips"
	
	var health_system = null
	if target.has_node("HealthSystem"):
		health_system = target.get_node("HealthSystem")
	elif target.get_parent() and target.get_parent().has_node("HealthSystem"):
		health_system = target.get_parent().get_node("HealthSystem")
	
	if health_system and health_system.has_method("apply_damage"):
		var damage_type = health_system.DamageType.BRUTE if "DamageType" in health_system else 0
		health_system.apply_damage(damage, damage_type, 0, "head", user)
	elif target.has_method("take_damage"):
		target.take_damage(damage, 1, "melee", user)
	
	if user.has_method("visible_message"):
		user.visible_message(
			user.name + " " + attack_verb + " " + target.name + " with " + item_name + "!",
			"You " + attack_verb + " " + target.name + " with " + item_name + "!"
		)
	
	var hit_sound = preload("res://Sound/weapons/genhit1.ogg") if ResourceLoader.exists("res://Sound/weapons/genhit1.ogg") else null
	if hit_sound:
		play_audio(hit_sound, -5)
	
	apply_durability_loss(0.5)
	
	return true

func afterattack(target, user, proximity: bool, params: Dictionary = {}):
	if proximity:
		return use_weapon(user, target)
	else:
		if user:
			show_message_to_user(user, "That's too far away for a pistol shot.")
		return false

func examine(user) -> String:
	var text = super.examine(user)
	
	text += "\nThis is a standard-issue sidearm designed for close to medium range combat."
	text += "\nIt's lightweight and can be fired effectively with one hand."
	
	if current_magazine:
		text += "\nA magazine is loaded."
	else:
		text += "\nNo magazine is loaded."
	
	if chambered_bullet:
		text += " There's a round in the chamber."
	else:
		text += " The chamber is empty."
	
	var condition_percent = current_durability / max_durability
	if condition_percent < 0.3:
		text += "\nThe pistol looks worn and might jam soon."
	elif condition_percent < 0.6:
		text += "\nThe pistol shows some wear but seems functional."
	else:
		text += "\nThe pistol is in good condition."
	
	return text

func use_on(target, user) -> bool:
	if not target or not user:
		return false
	
	var distance = user.global_position.distance_to(target.global_position)
	if distance > effective_range * 32:
		show_message_to_user(user, "That target is too far for an effective pistol shot.")
		return false
	
	return use_weapon(user, target)

@rpc("any_peer", "call_local", "reliable")
func sync_pistol_fired(shooter_id: String, target_pos: Vector2, hit: bool, direction: int):
	var shooter = find_user_by_id(shooter_id)
	if not shooter:
		return
	
	play_fire_effects(shooter)
	show_muzzle_flash_networked(direction)

func show_muzzle_flash_networked(direction: int):
	var icon_node = get_node_or_null("Icon")
	if not icon_node or not icon_node is AnimatedSprite2D:
		return
	
	var animated_sprite = icon_node as AnimatedSprite2D
	
	if not animated_sprite.sprite_frames or not animated_sprite.sprite_frames.has_animation("Flash"):
		return
	
	animated_sprite.rotation_degrees = convert_direction_to_rotation(direction)
	
	animated_sprite.play("Flash")
	
	var timer = Timer.new()
	add_child(timer)
	timer.wait_time = 0.2
	timer.one_shot = true
	timer.timeout.connect(func(): 
		animated_sprite.stop()
		timer.queue_free()
	)
	timer.start()

func apply_one_handed_gun_effects(user):
	add_heat(2.0)

func perform_field_strip(user) -> bool:
	if not user:
		return false
	
	if current_magazine:
		show_message_to_user(user, "You need to remove the magazine first!")
		return false
	
	if chambered_bullet:
		show_message_to_user(user, "You need to clear the chamber first!")
		return false
	
	show_message_to_user(user, "You field strip the " + item_name + " and clean its components.")
	repair_weapon(20.0)
	
	var maintenance_sound = preload("res://Sound/effects/toolbox.ogg") if ResourceLoader.exists("res://Sound/effects/toolbox.ogg") else null
	if maintenance_sound:
		play_audio(maintenance_sound, -10)
	
	return true

func get_display_name() -> String:
	var base_name = super.get_display_name()
	
	if maintenance_required:
		base_name += " (needs maintenance)"
	elif is_jammed:
		base_name += " (jammed)"
	elif current_safety_state == SafetyState.ON:
		base_name += " (safety on)"
	
	return base_name

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
		"pistol_type": "generic",
		"has_magazine": current_magazine != null,
		"magazine_data": current_magazine.serialize() if current_magazine else {}
	})
	return data

func deserialize(data: Dictionary):
	super.deserialize(data)
	
	if "has_magazine" in data and data.has_magazine and "magazine_data" in data:
		pass
