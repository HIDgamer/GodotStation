extends Item
class_name Magazine

signal rounds_changed(current_rounds, max_rounds)
signal magazine_empty()
signal magazine_full()

# Magazine properties
@export var max_rounds: int = 15
@export var current_rounds: int = 15
@export var compatible_ammo_type: Gun.AmmoType = Gun.AmmoType.PISTOL
@export var reload_time: float = 2.0
@export var bullet_type: String = "PistolBullet"

# Visual properties
@export var full_texture: Texture2D
@export var empty_texture: Texture2D
@export var magazine_name: String = "magazine"

# Bullet storage
var stored_bullets: Array = []

func _init():
	super._init()
	item_name = magazine_name
	w_class = 1  # Small item
	entity_type = "ammo"

func _ready():
	super._ready()
	
	# Initialize with bullets if needed
	if current_rounds > stored_bullets.size():
		fill_with_default_bullets()
	
	update_appearance()
	add_to_group("magazines")

func fill_with_default_bullets():
	"""Fill magazine with default bullet type"""
	stored_bullets.clear()
	
	# Create bullet instances based on bullet_type
	var bullet_class = load("res://items/bullets/" + bullet_type + ".gd")
	if not bullet_class:
		print("Warning: Could not load bullet type: " + bullet_type)
		return
	
	for i in range(current_rounds):
		var bullet = bullet_class.new()
		stored_bullets.append(bullet)

func can_add_bullet(bullet) -> bool:
	"""Check if a bullet can be added to this magazine"""
	if current_rounds >= max_rounds:
		return false
	
	# Check if bullet is compatible
	if bullet.has_method("get_bullet_type"):
		var bullet_ammo_type = bullet.get_bullet_type()
		return bullet_ammo_type == compatible_ammo_type
	
	return true

func add_bullet(bullet) -> bool:
	"""Add a bullet to the magazine"""
	if not can_add_bullet(bullet):
		return false
	
	stored_bullets.append(bullet)
	current_rounds += 1
	update_appearance()
	emit_signal("rounds_changed", current_rounds, max_rounds)
	
	if current_rounds >= max_rounds:
		emit_signal("magazine_full")
	
	return true

func extract_bullet():
	"""Extract a bullet from the magazine"""
	if current_rounds <= 0 or stored_bullets.is_empty():
		return null
	
	var bullet = stored_bullets.pop_back()
	current_rounds -= 1
	update_appearance()
	emit_signal("rounds_changed", current_rounds, max_rounds)
	
	if current_rounds <= 0:
		emit_signal("magazine_empty")
	
	return bullet

func peek_bullet():
	"""Look at the next bullet without removing it"""
	if stored_bullets.is_empty():
		return null
	return stored_bullets[-1]

func is_empty() -> bool:
	"""Check if magazine is empty"""
	return current_rounds <= 0

func is_full() -> bool:
	"""Check if magazine is full"""
	return current_rounds >= max_rounds

func get_ammo_type() -> Gun.AmmoType:
	"""Get the ammo type this magazine accepts"""
	return compatible_ammo_type

func get_ammo_percentage() -> float:
	"""Get ammunition as percentage"""
	if max_rounds <= 0:
		return 0.0
	return float(current_rounds) / float(max_rounds) * 100.0

func update_appearance():
	"""Update magazine appearance based on ammo level"""
	var icon_node = get_node_or_null("Icon")
	if not icon_node:
		return
	
	# Update texture based on ammo level
	if is_empty() and empty_texture:
		if icon_node is Sprite2D:
			icon_node.texture = empty_texture
	elif full_texture:
		if icon_node is Sprite2D:
			icon_node.texture = full_texture
	
	# Update name to show round count
	if current_rounds > 0:
		item_name = magazine_name + " (" + str(current_rounds) + "/" + str(max_rounds) + ")"
	else:
		item_name = "empty " + magazine_name

# Transfer bullets between magazines or loose bullets
func transfer_bullets_to(other_magazine: Magazine, amount: int = -1) -> int:
	"""Transfer bullets to another magazine"""
	if not other_magazine:
		return 0
	
	if amount < 0:
		amount = current_rounds
	
	var transferred = 0
	
	for i in range(min(amount, current_rounds)):
		if other_magazine.is_full():
			break
		
		var bullet = extract_bullet()
		if bullet and other_magazine.add_bullet(bullet):
			transferred += 1
		else:
			# Put bullet back if transfer failed
			add_bullet(bullet)
			break
	
	return transferred

func interact(user) -> bool:
	"""Handle interaction with magazine"""
	# Check if user is trying to load bullets into magazine
	var active_item = get_active_item_from_user(user)
	
	if active_item and active_item.has_method("get_bullet_type"):
		# User is holding a bullet
		if add_bullet(active_item):
			remove_item_from_user(user, active_item)
			show_message_to_user(user, "You load a bullet into the " + item_name + ".")
			return true
		else:
			show_message_to_user(user, "The " + item_name + " is full or incompatible.")
			return false
	
	return super.interact(user)

func attackby(item, user, params = null) -> bool:
	"""Handle being attacked/used with an item"""
	# Check if item is a compatible bullet
	if item.has_method("get_bullet_type"):
		return interact(user)
	
	return super.attackby(item, user)

func examine(user) -> String:
	"""Provide detailed magazine examination"""
	var text = super.examine(user)
	
	text += "\n" + item_name + " contains " + str(current_rounds) + " out of " + str(max_rounds) + " rounds."
	
	var ammo_percent = get_ammo_percentage()
	if ammo_percent >= 90:
		text += "\nIt's completely full."
	elif ammo_percent >= 70:
		text += "\nIt's mostly full."
	elif ammo_percent >= 50:
		text += "\nIt's about half full."
	elif ammo_percent >= 25:
		text += "\nIt's running low."
	elif ammo_percent > 0:
		text += "\nIt's nearly empty."
	else:
		text += "\nIt's completely empty."
	
	text += "\nCompatible with: " + get_ammo_type_name(compatible_ammo_type)
	
	return text

func get_ammo_type_name(ammo_type: Gun.AmmoType) -> String:
	"""Get display name for ammo type"""
	match ammo_type:
		Gun.AmmoType.PISTOL:
			return "Pistol ammunition"
		Gun.AmmoType.RIFLE:
			return "Rifle ammunition"
		Gun.AmmoType.SHOTGUN:
			return "Shotgun shells"
		Gun.AmmoType.SNIPER:
			return "Sniper rounds"
		Gun.AmmoType.SPECIAL:
			return "Special ammunition"
		_:
			return "Unknown ammunition"

func get_active_item_from_user(user):
	"""Get the active item from user's inventory"""
	if not user:
		return null
	
	var inventory_system = user.get_node_or_null("InventorySystem")
	if inventory_system and inventory_system.has_method("get_active_item"):
		return inventory_system.get_active_item()
	
	return null

func remove_item_from_user(user, item):
	"""Remove an item from user's inventory"""
	if not user or not item:
		return
	
	var inventory_system = user.get_node_or_null("InventorySystem")
	if inventory_system and inventory_system.has_method("unequip_item"):
		var slot = inventory_system.find_slot_with_item(item)
		if slot != inventory_system.EquipSlot.NONE:
			inventory_system.unequip_item(slot)

func show_message_to_user(user, message: String):
	"""Show a message to the user"""
	if user and user.has_method("show_message"):
		user.show_message(message)

# Serialization
func serialize() -> Dictionary:
	var data = super.serialize()
	data.merge({
		"max_rounds": max_rounds,
		"current_rounds": current_rounds,
		"compatible_ammo_type": compatible_ammo_type,
		"bullet_type": bullet_type,
		"stored_bullets_count": stored_bullets.size()
	})
	return data

func deserialize(data: Dictionary):
	super.deserialize(data)
	if "max_rounds" in data: max_rounds = data.max_rounds
	if "current_rounds" in data: current_rounds = data.current_rounds
	if "compatible_ammo_type" in data: compatible_ammo_type = data.compatible_ammo_type
	if "bullet_type" in data: bullet_type = data.bullet_type
	
	# Recreate bullets based on count
	if "stored_bullets_count" in data:
		fill_with_default_bullets()
	
	update_appearance()
