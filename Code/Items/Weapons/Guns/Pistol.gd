extends Gun
class_name Pistol

func _init():
	super._init()
	
	# Basic pistol properties
	item_name = "pistol"
	obj_name = "pistol"
	description = "A reliable sidearm. Standard issue for security and military personnel."
	
	# Weapon properties
	weapon_damage = 35.0
	weapon_accuracy = 75.0
	weapon_range = 12.0
	force = 8  # Melee damage when used as blunt weapon
	
	# Gun-specific properties
	accepted_ammo_types = [Gun.AmmoType.PISTOL]
	fire_delay = 0.4  # 2.5 rounds per second
	recoil_amount = 1.5
	scatter_amount = 3.0
	effective_range = 8.0
	max_range = 16.0
	bullet_speed = 40.0
	
	# Pistol fire modes (semi-auto only)
	available_fire_modes = [Gun.FireMode.SEMIAUTO]
	current_fire_mode = Gun.FireMode.SEMIAUTO
	
	# Heat management (pistols heat up faster but cool down faster)
	max_heat = 80.0
	
	# Casing ejection settings
	eject_casings = true
	casing_eject_force = 120.0
	casing_eject_angle_offset = 45.0  # Eject to the right
	
	# Physical properties
	w_class = 2  # Medium-small size
	requires_wielding = false  # Pistols can be fired one-handed
	
	# Set valid equipment slots
	equip_slot_flags = Slots.LEFT_HAND | Slots.RIGHT_HAND | Slots.BELT
	
	# Sounds
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
	
	# Load projectile scene for pistol bullets
	if ResourceLoader.exists("res://Scenes/Effects/PistolProjectile.tscn"):
		projectile_scene = preload("res://Scenes/Effects/PistolProjectile.tscn")
	
	# Load pistol casing scene
	if ResourceLoader.exists("res://Scenes/Effects/bulletcasings.tscn"):
		casing_scene = preload("res://Scenes/Effects/bulletcasings.tscn")
	
	# Set weapon-specific properties
	attack_verb = ["shoots", "fires at", "blasts"]
	attack_speed = 1.2
	
	# Create default magazine if specified
	create_default_magazine()

func create_default_magazine():
	"""Create a default magazine for the pistol"""
	if ResourceLoader.exists("res://items/magazines/PistolMagazine.tscn"):
		var default_mag = preload("res://Scenes/Items/Guns/Magazines/PistolMagazine.tscn").instantiate()
		if default_mag:
			current_magazine = default_mag
			chamber_next_round()
			emit_signal("ammo_changed", get_current_ammo_count(), get_max_ammo_count())

func can_use_weapon(user) -> bool:
	"""Override to allow single-handed use"""
	if not user:
		return false
	
	# Pistols don't require wielding
	var original_wielding_requirement = requires_wielding
	requires_wielding = false
	var result = super.can_use_weapon(user)
	requires_wielding = original_wielding_requirement
	
	return result

func create_and_fire_projectile(user, target, bullet) -> bool:
	"""Override to handle pistol-specific ballistics and muzzle flash"""
	if not super.create_and_fire_projectile(user, target, bullet):
		return false
	
	# Show muzzle flash
	show_muzzle_flash(user)
	
	# Pistol-specific effects
	add_recoil_effect(user)
	return true

func show_muzzle_flash(user):
	"""Show muzzle flash effect with proper rotation"""
	var icon_node = get_node_or_null("Icon")
	if not icon_node or not icon_node is AnimatedSprite2D:
		return
	
	var animated_sprite = icon_node as AnimatedSprite2D
	
	# Check if Flash animation exists
	if not animated_sprite.sprite_frames or not animated_sprite.sprite_frames.has_animation("Flash"):
		push_warning("Pistol: 'Flash' animation not found in Icon node")
		return
	
	# Get user's facing direction
	var user_direction = get_user_facing_direction(user)
	
	# Set rotation based on direction (muzzle flash faces north by default)
	animated_sprite.rotation_degrees = convert_direction_to_rotation(user_direction)
	
	# Play the flash animation
	animated_sprite.play("Flash")
	
	# Stop the animation after it completes (assuming 2 frames)
	# We'll use a timer to stop it after one cycle
	var timer = Timer.new()
	add_child(timer)
	timer.wait_time = 0.2  # Adjust based on your animation speed
	timer.one_shot = true
	timer.timeout.connect(func(): 
		animated_sprite.stop()
		timer.queue_free()
	)
	timer.start()

func get_user_facing_direction(user) -> int:
	"""Get the user's current facing direction"""
	if not user:
		return 2  # Default to SOUTH
	
	# Try to get direction from movement component
	if user.has_method("get_current_direction"):
		return user.get_current_direction()
	elif "movement_component" in user and user.movement_component:
		if user.movement_component.has_method("get_current_direction"):
			return user.movement_component.get_current_direction()
		elif "current_direction" in user.movement_component:
			return user.movement_component.current_direction
	elif "current_direction" in user:
		return user.current_direction
	
	return 2  # Default to SOUTH

func convert_direction_to_rotation(direction: int) -> float:
	"""Convert direction enum to rotation degrees for muzzle flash"""
	# Muzzle flash faces north (0 degrees) by default
	match direction:
		0: # NORTH
			return 0.0
		1: # EAST
			return 90.0
		2: # SOUTH
			return 180.0
		3: # WEST
			return 270.0
		4: # NORTHEAST
			return 45.0
		5: # SOUTHEAST
			return 135.0
		6: # SOUTHWEST
			return 225.0
		7: # NORTHWEST
			return 315.0
		_: # Default/NONE
			return 180.0  # Default to south

func add_recoil_effect(user):
	"""Add pistol recoil effect"""
	if not user:
		return
	
	# Reduce recoil if wielded with both hands
	var actual_recoil = recoil_amount
	if is_wielded():
		actual_recoil *= 0.7  # 30% recoil reduction when wielded
	
	# Apply screen shake
	if user.has_method("add_screen_shake"):
		user.add_screen_shake(actual_recoil * 0.5)

func insert_magazine(magazine, user) -> bool:
	"""Insert a magazine into the pistol with proper hiding"""
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

# Magazine ejection with proper showing
func eject_magazine(user) -> bool:
	"""Eject the current magazine with proper visibility restoration"""
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
			inventory.show_item_icon(ejected_mag)
	
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

func attack(target, user):
	"""Handle melee attack with pistol (pistol whipping)"""
	if not target or not user:
		return false
	
	# Use as improvised weapon
	var damage = force
	var attack_verb = "pistol-whips"
	
	if target.has_method("take_damage"):
		target.take_damage(damage, "brute", "melee", true, 0, user)
	
	if user.has_method("visible_message"):
		user.visible_message(
			user.name + " " + attack_verb + " " + target.name + " with " + item_name + "!",
			"You " + attack_verb + " " + target.name + " with " + item_name + "!"
		)
	
	# Play hit sound
	var hit_sound = preload("res://Sound/weapons/genhit1.ogg") if ResourceLoader.exists("res://Sound/weapons/genhit1.ogg") else null
	if hit_sound:
		play_audio(hit_sound, -5)
	
	# Apply small durability loss
	apply_durability_loss(0.5)
	
	return true

func afterattack(target, user, proximity: bool, params: Dictionary = {}):
	"""Handle shooting at target"""
	if proximity:
		# Close range - try to shoot
		return use_weapon(user, target)
	else:
		# Long range - probably out of effective range
		if user:
			show_message_to_user(user, "That's too far away for a pistol shot.")
		return false

func examine(user) -> String:
	"""Provide detailed pistol examination"""
	var text = super.examine(user)
	
	# Add pistol-specific information
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
	
	# Condition-specific descriptions
	var condition_percent = current_durability / max_durability
	if condition_percent < 0.3:
		text += "\nThe pistol looks worn and might jam soon."
	elif condition_percent < 0.6:
		text += "\nThe pistol shows some wear but seems functional."
	else:
		text += "\nThe pistol is in good condition."
	
	return text

# Interaction with ItemInteractionComponent
func use_on(target, user) -> bool:
	"""Handle using pistol on target (shooting)"""
	if not target or not user:
		return false
	
	# Check if we can shoot at the target
	var distance = user.global_position.distance_to(target.global_position)
	if distance > effective_range * 32:  # Convert tiles to pixels
		show_message_to_user(user, "That target is too far for an effective pistol shot.")
		return false
	
	return use_weapon(user, target)

# Network synchronization
@rpc("any_peer", "call_local", "reliable")
func sync_pistol_fired(shooter_id: String, target_pos: Vector2, hit: bool, direction: int):
	"""Synchronize pistol firing across network"""
	var shooter = find_player_by_id(shooter_id)
	if not shooter:
		return
	
	# Play effects for other players
	play_fire_effects(shooter)
	show_muzzle_flash_networked(direction)
	
	if hit:
		# Show hit effect at target position
		show_hit_effect_at_position(target_pos)

func show_muzzle_flash_networked(direction: int):
	"""Show muzzle flash for networked players"""
	var icon_node = get_node_or_null("Icon")
	if not icon_node or not icon_node is AnimatedSprite2D:
		return
	
	var animated_sprite = icon_node as AnimatedSprite2D
	
	# Check if Flash animation exists
	if not animated_sprite.sprite_frames or not animated_sprite.sprite_frames.has_animation("Flash"):
		return
	
	# Set rotation based on direction
	animated_sprite.rotation_degrees = convert_direction_to_rotation(direction)
	
	# Play the flash animation
	animated_sprite.play("Flash")
	
	# Stop the animation after it completes
	var timer = Timer.new()
	add_child(timer)
	timer.wait_time = 0.2
	timer.one_shot = true
	timer.timeout.connect(func(): 
		animated_sprite.stop()
		timer.queue_free()
	)
	timer.start()

func find_player_by_id(player_id: String):
	"""Find player by network ID"""
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player.has_method("get_network_id") and player.get_network_id() == player_id:
			return player
	return null

func show_hit_effect_at_position(pos: Vector2):
	"""Show hit effect at position"""
	# Create hit effect
	var hit_effect = preload("res://Scenes/Effects/BulletHit.tscn").instantiate() if ResourceLoader.exists("res://Scenes/Effects/BulletHit.tscn") else null
	if hit_effect and get_tree().current_scene:
		get_tree().current_scene.add_child(hit_effect)
		hit_effect.global_position = pos
		hit_effect.play_effect()

# Override fire_gun to add network sync with direction
func fire_gun(user, target) -> bool:
	"""Override to add network synchronization with direction"""
	var result = super.fire_gun(user, target)
	var icon_node = get_node_or_null("Icon")
	
	if result and multiplayer.has_multiplayer_peer():
		var target_pos = user.get_global_mouse_position()
		var user_id = user.get_network_id() if user.has_method("get_network_id") else str(user.get_instance_id())
		var user_direction = get_user_facing_direction(user)
		sync_pistol_fired.rpc(user_id, target_pos, true, user_direction)
	
	return result

# Pistol-specific maintenance
func perform_field_strip(user) -> bool:
	"""Perform field stripping for maintenance"""
	if not user:
		return false
	
	if current_magazine:
		show_message_to_user(user, "You need to remove the magazine first!")
		return false
	
	if chambered_bullet:
		show_message_to_user(user, "You need to clear the chamber first!")
		return false
	
	# Perform maintenance
	show_message_to_user(user, "You field strip the " + item_name + " and clean its components.")
	repair_weapon(20.0)  # Restore some durability
	
	# Play maintenance sound
	var maintenance_sound = preload("res://Sound/effects/toolbox.ogg") if ResourceLoader.exists("res://Sound/effects/toolbox.ogg") else null
	if maintenance_sound:
		play_audio(maintenance_sound, -10)
	
	return true

func get_display_name() -> String:
	"""Get display name including condition"""
	var base_name = super.get_display_name()
	
	if maintenance_required:
		base_name += " (needs maintenance)"
	elif is_jammed:
		base_name += " (jammed)"
	elif current_safety_state == SafetyState.ON:
		base_name += " (safety on)"
	
	return base_name

# Helper function override
func show_message_to_user(user, message: String):
	"""Show message to user"""
	if user and user.has_method("show_message"):
		user.show_message(message)
	elif user and user.has_method("visible_message"):
		user.visible_message(message, message)
	else:
		print(message)

# Serialization
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
	
	# Restore magazine if present
	if "has_magazine" in data and data.has_magazine and "magazine_data" in data:
		# You would need to recreate the magazine here
		pass
