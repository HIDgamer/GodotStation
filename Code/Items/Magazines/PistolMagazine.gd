extends Magazine
class_name PistolMagazine

func _init():
	super._init()
	
	# Pistol magazine properties
	magazine_name = "pistol magazine"
	item_name = "pistol magazine"
	max_rounds = 15
	current_rounds = 15
	compatible_ammo_type = Gun.AmmoType.PISTOL
	bullet_type = "PistolBullet"
	reload_time = 1.5
	
	# Physical properties
	w_class = 1  # Small item
	force = 2    # Can be used as improvised weapon
	
	# Description
	description = "A standard 15-round magazine for pistol ammunition. Lightweight and reliable."

func _ready():
	super._ready()
	
	# Set visual properties
	setup_magazine_visuals()
	
	# Set valid equipment slots (can go in belt, pockets, hands)
	equip_slot_flags = Slots.LEFT_HAND | Slots.RIGHT_HAND | Slots.BELT | Slots.IN_L_POUCH | Slots.IN_R_POUCH | Slots.S_STORE

func setup_magazine_visuals():
	"""Set up magazine appearance using AnimatedSprite2D"""
	# Update initial appearance
	update_appearance()

func update_appearance():
	"""Update magazine appearance based on ammo count"""
	var icon_node = get_node_or_null("Icon")
	if not icon_node or not icon_node is AnimatedSprite2D:
		push_error("PistolMagazine: Icon node not found or not an AnimatedSprite2D")
		return
	
	var animated_sprite = icon_node as AnimatedSprite2D
	
	# Play appropriate animation based on ammo count
	if current_rounds <= 0:
		if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("Empty"):
			animated_sprite.play("Empty")
		else:
			push_warning("PistolMagazine: 'Empty' animation not found in Icon node")
	else:
		if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("Full"):
			animated_sprite.play("Full")
		else:
			push_warning("PistolMagazine: 'Full' animation not found in Icon node")

func fill_with_default_bullets():
	"""Fill magazine with pistol bullets"""
	stored_bullets.clear()
	
	for i in range(current_rounds):
		var bullet = PistolBullet.new()
		stored_bullets.append(bullet)
	
	# Update appearance after filling
	update_appearance()

func can_add_bullet(bullet) -> bool:
	"""Check if bullet is compatible with pistol magazine"""
	if not super.can_add_bullet(bullet):
		return false
	
	# Ensure it's a pistol bullet
	if bullet.has_method("get_bullet_type"):
		return bullet.get_bullet_type() == "pistol"
	elif "bullet_type" in bullet:
		return bullet.bullet_type == "pistol"
	
	return false

func add_bullet(bullet) -> bool:
	"""Override to update appearance when adding bullets"""
	var result = super.add_bullet(bullet)
	if result:
		update_appearance()
	return result

func extract_bullet():
	"""Override to update appearance when extracting bullets"""
	var bullet = super.extract_bullet()
	if bullet:
		update_appearance()
	return bullet

func examine(user) -> String:
	"""Provide detailed examination of pistol magazine"""
	var text = super.examine(user)
	
	# Add pistol-specific information
	text += "\nThis magazine is designed for standard pistol ammunition."
	text += "\nIt feeds reliably and is easy to reload quickly."
	
	# Weight information
	var weight_desc = ""
	if current_rounds == max_rounds:
		weight_desc = "It feels full and heavy."
	elif current_rounds > max_rounds * 0.7:
		weight_desc = "It feels mostly full."
	elif current_rounds > max_rounds * 0.3:
		weight_desc = "It feels about half full."
	elif current_rounds > 0:
		weight_desc = "It feels light."
	else:
		weight_desc = "It feels empty."
	
	text += "\n" + weight_desc
	
	return text

func attack(target, user):
	"""Use magazine as improvised weapon"""
	if not target or not user:
		return false
	
	var damage = force + (current_rounds * 0.2)  # Heavier when full
	var verb = "strikes"
	
	if target.has_method("take_damage"):
		target.take_damage(damage, "brute", "melee", true, 0, user)
	
	if user.has_method("visible_message"):
		user.visible_message(
			user.name + " " + verb + " " + target.name + " with the " + item_name + "!",
			"You " + verb + " " + target.name + " with the " + item_name + "!"
		)
	
	# Play hit sound
	var hit_sound = preload("res://Sound/weapons/genhit1.ogg") if ResourceLoader.exists("res://Sound/weapons/genhit1.ogg") else null
	if hit_sound:
		play_audio(hit_sound, -10)
	
	return true

func thrown_impact(target, speed: float):
	"""Handle magazine being thrown"""
	if not target:
		return
	
	var impact_damage = force * (speed / 100.0)  # Scale with throw speed
	
	if target.has_method("take_damage"):
		target.take_damage(impact_damage, "brute", "thrown", true)
	
	# Play impact sound
	var impact_sound = preload("res://Sound/handling/ammobox_drop.ogg") if ResourceLoader.exists("res://Sound/handling/ammobox_drop.ogg") else null
	if impact_sound:
		play_audio(impact_sound, -5)
	
	# Small chance to spill bullets on hard impact
	if speed > 200 and randf() < 0.1:
		spill_some_bullets()

func spill_some_bullets():
	"""Spill some bullets when magazine is damaged"""
	var bullets_to_spill = min(3, current_rounds)
	
	for i in range(bullets_to_spill):
		if current_rounds > 0:
			var bullet = extract_bullet()
			if bullet:
				# Create bullet object in world
				create_loose_bullet(bullet)

func create_loose_bullet(bullet):
	"""Create a loose bullet object in the world"""
	pass

# Special interaction for tactical reload
func tactical_reload_with(other_magazine: PistolMagazine, user) -> bool:
	"""Perform tactical reload by swapping magazines quickly"""
	if not other_magazine or not user:
		return false
	
	if other_magazine.current_rounds <= current_rounds:
		show_message_to_user(user, "The other magazine isn't fuller!")
		return false
	
	# Quick swap
	var my_rounds = current_rounds
	var their_rounds = other_magazine.current_rounds
	
	current_rounds = their_rounds
	other_magazine.current_rounds = my_rounds
	
	# Transfer actual bullet objects
	var temp_bullets = stored_bullets.duplicate()
	stored_bullets = other_magazine.stored_bullets.duplicate()
	other_magazine.stored_bullets = temp_bullets
	
	# Update appearances for both magazines
	update_appearance()
	other_magazine.update_appearance()
	
	show_message_to_user(user, "You quickly swap magazines!")
	
	# Play tactical reload sound
	var reload_sound = preload("res://Sound/weapons/Reload.wav") if ResourceLoader.exists("res://Sound/weapons/Reload.wav") else null
	if reload_sound:
		play_audio(reload_sound, -5)
	
	return true

# Network synchronization
@rpc("any_peer", "call_local", "reliable")
func sync_magazine_state(rounds: int, max_capacity: int):
	"""Synchronize magazine state across network"""
	current_rounds = rounds
	max_rounds = max_capacity
	update_appearance()
	emit_signal("rounds_changed", current_rounds, max_rounds)

func serialize() -> Dictionary:
	"""Serialize pistol magazine data"""
	var data = super.serialize()
	data.merge({
		"magazine_type": "pistol",
		"bullets_data": []
	})
	
	# Serialize individual bullets if needed
	for bullet in stored_bullets:
		if bullet and bullet.has_method("serialize"):
			data.bullets_data.append(bullet.serialize())
	
	return data

func deserialize(data: Dictionary):
	"""Deserialize pistol magazine data"""
	super.deserialize(data)
	
	# Restore bullets from data
	if "bullets_data" in data:
		stored_bullets.clear()
		for bullet_data in data.bullets_data:
			var bullet = PistolBullet.new()
			if bullet.has_method("deserialize"):
				bullet.deserialize(bullet_data)
			stored_bullets.append(bullet)
	
	# Update appearance after deserializing
	update_appearance()
