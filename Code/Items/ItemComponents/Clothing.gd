extends Item
class_name Clothing

signal clothing_equipped(user, slot)
signal clothing_unequipped(user, slot)
signal accessory_attached(accessory)
signal accessory_removed(accessory)
signal traits_applied(user, traits)
signal traits_removed(user, traits)

enum EquipSlot {
	NONE = 0,
	HEAD = 1,
	GLASSES = 2,
	BACK = 3,
	WEAR_MASK = 4,
	HANDCUFFED = 5,
	W_UNIFORM = 6,
	WEAR_SUIT = 7,
	EARS = 8,
	GLOVES = 9,
	SHOES = 10,
	WEAR_ID = 12,
	LEFT_HAND = 13,
	RIGHT_HAND = 14,
	BELT = 15,
	L_STORE = 16,
	R_STORE = 17,
	S_STORE = 18,
	ACCESSORY = 19,
	IN_BOOT = 20,
	IN_BACKPACK = 21,
	IN_SUIT = 22,
	IN_BELT = 23,
	IN_HEAD = 24,
	IN_ACCESSORY = 25,
	IN_HOLSTER = 26,
	IN_S_HOLSTER = 27,
	IN_B_HOLSTER = 28,
	IN_STORAGE = 29,
	IN_L_POUCH = 30,
	IN_R_POUCH = 31
}

# Eye protection levels
enum EyeProtection {
	NONE = 0,
	FLASH = 1,
	WELDING = 2,
	FULL = 3
}

# Accessory slots
enum AccessorySlot {
	NONE = 0,
	MEDAL = 1,
	RANK = 2,
	DECOR = 4,
	PONCHO = 8,
	MASK_ACCESSORY = 16,
	ARMBAND = 32,
	ARMOR_A = 64,
	ARMOR_L = 128,
	ARMOR_S = 256,
	ARMOR_M = 512,
	UTILITY = 1024,
	PATCH = 2048,
	WRIST_L = 4096,
	WRIST_R = 8192,
	DEFAULT = 16384
}

# Core clothing properties
@export var primary_slot: EquipSlot = EquipSlot.NONE
@export var eye_protection: EyeProtection = EyeProtection.NONE
@export var movement_compensation: float = 0.0
@export var drag_unequip: bool = false
@export var blood_overlay_type: String = ""
@export var fire_resist: float = 100.0
@export var siemens_coefficient: float = 1.0

# Enhanced armor system
@export var armor_melee: int = 0
@export var armor_bullet: int = 0
@export var armor_laser: int = 0
@export var armor_energy: int = 0
@export var armor_bomb: int = 0
@export var armor_bio: int = 0
@export var armor_rad: int = 0
@export var armor_internal_damage: int = 0

# Clothing traits - applied when worn
@export var clothing_traits: Array[String] = []
@export var clothing_traits_active: bool = true

# Accessory system
var accessories: Array = []
@export var valid_accessory_slots: int = 0
@export var can_become_accessory: bool = false
@export var worn_accessory_slot: AccessorySlot = AccessorySlot.DEFAULT
@export var accessory_path: String = "res://scripts/items/clothing/Accessory.gd"
@export var worn_accessory_limit: int = 1

# Equipment restrictions
@export var suit_restricted: Array = [] # Suits that can be worn with this item
@export var under_restricted: Array = [] # Underwear items that can be worn with this item

# Storage capability (for items like suits with pockets)
var internal_storage = null
@export var storage_slots: int = 0
@export var max_storage_space: int = 0
@export var can_hold_items: Array = []

# Visual properties
@export var hide_prints: bool = false
var clothing_blood_amt: float = 0.0

# Equipment sounds
@export var equip_sounds: Array[AudioStream] = []
@export var unequip_sounds: Array[AudioStream] = []

# Currently equipped user and slot (for tracking)
var equipped_user = null
var equipped_slot: int = EquipSlot.NONE
var valid_slots = []

# Enhanced texture path support for clothing
@export var clothing_texture_path: String = ""
@export var clothing_sprite_frames: int = 4  # Number of directional frames

func _init():
	super._init()
	entity_type = "clothing"
	pickupable = true
	
	# Set up valid slots based on primary slot
	setup_valid_slots()
	
	# Override armor values from inherited soft_armor
	update_armor_values()
	
	# Initialize internal storage if specified
	if storage_slots > 0:
		setup_internal_storage()

func _ready():
	super._ready()
	
	# Ensure we're in the clothing group
	if not is_in_group("clothing"):
		add_to_group("clothing")
	
	# Set up visual components
	setup_clothing_visuals()

func setup_valid_slots():
	"""Set up valid equipment slots based on primary slot"""
	if not valid_slots:
		valid_slots = []
	
	# Add primary slot to valid slots if not already there
	if primary_slot != EquipSlot.NONE and primary_slot not in valid_slots:
		valid_slots.append(primary_slot)
	
	# Set equip_slot_flags for inventory system compatibility
	if primary_slot != EquipSlot.NONE:
		equip_slot_flags = get_slot_flag_for_slot(primary_slot)
	
	# Ensure we have a texture path set up
	if clothing_texture_path == "" and obj_name != "":
		# Try to auto-generate texture path based on item name and type
		var base_path = "res://Graphics/clothing/"
		var slot_name = get_slot_name_for_path(primary_slot)
		if slot_name != "":
			clothing_texture_path = base_path + slot_name + "/" + obj_name.to_lower().replace(" ", "_") + ".png"

func get_slot_name_for_path(slot: EquipSlot) -> String:
	"""Get folder name for texture path based on slot"""
	match slot:
		EquipSlot.HEAD:
			return "head"
		EquipSlot.GLASSES:
			return "eyes"
		EquipSlot.WEAR_MASK:
			return "mask"
		EquipSlot.EARS:
			return "ears"
		EquipSlot.WEAR_SUIT:
			return "suits"
		EquipSlot.W_UNIFORM:
			return "uniforms"
		EquipSlot.GLOVES:
			return "gloves"
		EquipSlot.BELT:
			return "belts"
		EquipSlot.SHOES:
			return "shoes"
		EquipSlot.BACK:
			return "back"
		EquipSlot.WEAR_ID:
			return "id"
		_:
			return "misc"

# MULTIPLAYER SYNCHRONIZATION FOR CLOTHING
@rpc("any_peer", "call_local", "reliable")
func sync_clothing_equipped(user_network_id: String, slot: int):
	var user = find_user_by_network_id(user_network_id)
	if user:
		_equipped_internal(user, slot)

@rpc("any_peer", "call_local", "reliable")
func sync_clothing_unequipped(user_network_id: String, slot: int):
	var user = find_user_by_network_id(user_network_id)
	if user:
		_unequipped_internal(user, slot)

@rpc("any_peer", "call_local", "reliable")
func sync_accessory_attached(accessory_network_id: String, user_network_id: String):
	var accessory = find_item_by_network_id(accessory_network_id)
	var user = find_user_by_network_id(user_network_id) if user_network_id != "" else null
	if accessory:
		_attach_accessory_internal(accessory, user)

@rpc("any_peer", "call_local", "reliable")
func sync_accessory_removed(accessory_network_id: String, user_network_id: String):
	var accessory = find_item_by_network_id(accessory_network_id)
	var user = find_user_by_network_id(user_network_id) if user_network_id != "" else null
	if accessory:
		_remove_accessory_internal(accessory, user)

@rpc("any_peer", "call_local", "reliable")
func sync_visual_update(user_network_id: String, slot: int, is_equipping: bool):
	var user = find_user_by_network_id(user_network_id)
	if user:
		update_sprite_system_visual(user, slot, is_equipping)

@rpc("any_peer", "call_local", "reliable")
func sync_clothing_traits(user_network_id: String, apply: bool):
	var user = find_user_by_network_id(user_network_id)
	if user:
		if apply:
			_apply_clothing_traits_internal(user)
		else:
			_remove_clothing_traits_internal(user)

# Override equipped method for inventory system compatibility with multiplayer sync
func equipped(user, slot: int):
	"""Called by inventory system when item is equipped"""
	_equipped_internal(user, slot)
	
	# Sync across network
	if multiplayer.has_multiplayer_peer():
		sync_clothing_equipped.rpc(get_user_network_id(user), slot)

func _equipped_internal(user, slot: int):
	"""Internal method for equipping - handles the actual logic"""
	equipped_user = user
	equipped_slot = slot
	
	# Apply clothing traits
	if clothing_traits_active and clothing_traits.size() > 0:
		_apply_clothing_traits_internal(user)
	
	# Apply armor bonuses
	apply_armor_to_user(user)
	
	# Play equip sound
	play_equip_sound()
	
	# Update user's movement speed if applicable
	if movement_compensation != 0.0:
		apply_movement_modification(user, -movement_compensation)
	
	# Handle specific clothing effects
	handle_equip_effects(user, slot)
	
	# Update visual appearance through sprite system
	update_sprite_system_visual(user, slot, true)
	
	emit_signal("clothing_equipped", user, slot)

# Override unequipped method for inventory system compatibility with multiplayer sync
func unequipped(user, slot: int):
	"""Called by inventory system when item is unequipped"""
	_unequipped_internal(user, slot)
	
	# Sync across network
	if multiplayer.has_multiplayer_peer():
		sync_clothing_unequipped.rpc(get_user_network_id(user), slot)

func _unequipped_internal(user, slot: int):
	"""Internal method for unequipping - handles the actual logic"""
	# Remove clothing traits
	if clothing_traits_active and clothing_traits.size() > 0:
		_remove_clothing_traits_internal(user)
	
	# Remove armor bonuses
	remove_armor_from_user(user)
	
	# Play unequip sound
	play_unequip_sound()
	
	# Restore movement speed
	if movement_compensation != 0.0:
		apply_movement_modification(user, movement_compensation)
	
	# Handle specific clothing removal effects
	handle_unequip_effects(user, slot)
	
	# Update visual appearance through sprite system
	update_sprite_system_visual(user, slot, false)
	
	equipped_user = null
	equipped_slot = EquipSlot.NONE
	
	emit_signal("clothing_unequipped", user, slot)

func handle_equip_effects(user, slot: int):
	"""Handle slot-specific equip effects"""
	match slot:
		EquipSlot.WEAR_MASK:
			if user.has_method("update_breathing"):
				user.update_breathing()
		EquipSlot.GLASSES:
			if user.has_method("update_vision"):
				user.update_vision()
		EquipSlot.HEAD:
			if user.has_method("update_head_protection"):
				user.update_head_protection()

func handle_unequip_effects(user, slot: int):
	"""Handle slot-specific unequip effects"""
	match slot:
		EquipSlot.WEAR_MASK:
			if user.has_method("update_breathing"):
				user.update_breathing()
		EquipSlot.GLASSES:
			if user.has_method("update_vision"):
				user.update_vision()
		EquipSlot.HEAD:
			if user.has_method("update_head_protection"):
				user.update_head_protection()

func update_sprite_system_visual(user, inventory_slot: int, is_equipping: bool):
	"""Update the visual representation through the sprite system"""
	var sprite_system = get_sprite_system(user)
	if not sprite_system:
		return
	
	# Convert inventory slot to sprite system slot
	var sprite_slot = convert_inventory_slot_to_sprite_slot(inventory_slot)
	if sprite_slot == -1:
		return
	
	if is_equipping:
		# Equip the item visually
		if sprite_system.has_method("equip_item"):
			sprite_system.equip_item(self, sprite_slot)
	else:
		# Unequip the item visually
		if sprite_system.has_method("unequip_item"):
			sprite_system.unequip_item(sprite_slot)
	
	# Sync visual update across network if not already syncing
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		sync_visual_update.rpc(get_user_network_id(user), inventory_slot, is_equipping)

func get_sprite_system(user) -> Node:
	"""Find the sprite system on the user entity"""
	if not user:
		return null
	
	# Try different possible paths for the sprite system
	var sprite_system = user.get_node_or_null("HumanSpriteSystem")
	if sprite_system:
		return sprite_system
	
	sprite_system = user.get_node_or_null("SpriteSystem")
	if sprite_system:
		return sprite_system
	
	# Try finding it in children
	for child in user.get_children():
		if child.has_method("equip_item") and child.has_method("unequip_item"):
			return child
	
	return null

func convert_inventory_slot_to_sprite_slot(inventory_slot: int) -> int:
	"""Convert InventorySystem slot to HumanSpriteSystem slot"""
	# Mapping from InventorySystem EquipSlot to HumanSpriteSystem EquipSlot
	match inventory_slot:
		EquipSlot.HEAD:
			return 0  # HumanSpriteSystem.EquipSlot.HEAD
		EquipSlot.GLASSES:
			return 1  # HumanSpriteSystem.EquipSlot.EYES
		EquipSlot.WEAR_MASK:
			return 2  # HumanSpriteSystem.EquipSlot.MASK
		EquipSlot.EARS:
			return 3  # HumanSpriteSystem.EquipSlot.EARS
		EquipSlot.WEAR_SUIT:
			return 5  # HumanSpriteSystem.EquipSlot.OUTER
		EquipSlot.W_UNIFORM:
			return 6  # HumanSpriteSystem.EquipSlot.UNIFORM
		EquipSlot.GLOVES:
			return 8  # HumanSpriteSystem.EquipSlot.GLOVES
		EquipSlot.BELT:
			return 9  # HumanSpriteSystem.EquipSlot.BELT
		EquipSlot.SHOES:
			return 10  # HumanSpriteSystem.EquipSlot.SHOES
		EquipSlot.BACK:
			return 11  # HumanSpriteSystem.EquipSlot.BACK
		EquipSlot.WEAR_ID:
			return 12  # HumanSpriteSystem.EquipSlot.ID
		EquipSlot.LEFT_HAND:
			return 13  # HumanSpriteSystem.EquipSlot.LEFT_HAND
		EquipSlot.RIGHT_HAND:
			return 14  # HumanSpriteSystem.EquipSlot.RIGHT_HAND
		_:
			return -1  # No mapping available

func get_clothing_texture() -> Texture2D:
	"""Get the texture for this clothing item"""
	# Try different ways to get the texture
	var icon_node = get_node_or_null("Icon")
	if icon_node and icon_node.texture:
		return icon_node.texture
	
	return create_fallback_texture()

func create_fallback_texture() -> Texture2D:
	"""Create a fallback texture for clothing items without sprites"""
	var image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.7, 0.7, 0.7, 1.0))  # Gray color
	return ImageTexture.create_from_image(image)

# Override get_texture method for sprite system compatibility
func get_texture() -> Texture2D:
	"""Get the texture for this clothing item - used by sprite systems"""
	return get_clothing_texture()

func get_clothing_texture_path() -> String:
	"""Get the texture path for this clothing item"""
	if clothing_texture_path != "":
		return clothing_texture_path
	
	return ""

func set_clothing_texture_path(path: String):
	"""Set the texture path for this clothing item"""
	clothing_texture_path = path
	
	# Update visual if currently equipped
	if equipped_user and equipped_slot != EquipSlot.NONE:
		update_sprite_system_visual(equipped_user, equipped_slot, true)

func apply_clothing_traits(user):
	"""Apply clothing traits to the user"""
	_apply_clothing_traits_internal(user)
	
	# Sync across network
	if multiplayer.has_multiplayer_peer():
		sync_clothing_traits.rpc(get_user_network_id(user), true)

func _apply_clothing_traits_internal(user):
	"""Internal method for applying clothing traits"""
	if not user.has_method("add_clothing_trait"):
		return
	
	for traits in clothing_traits:
		user.add_clothing_trait(traits, self)
	
	emit_signal("traits_applied", user, clothing_traits)

func remove_clothing_traits(user):
	"""Remove clothing traits from the user"""
	_remove_clothing_traits_internal(user)
	
	# Sync across network
	if multiplayer.has_multiplayer_peer():
		sync_clothing_traits.rpc(get_user_network_id(user), false)

func _remove_clothing_traits_internal(user):
	"""Internal method for removing clothing traits"""
	if not user.has_method("remove_clothing_trait"):
		return
	
	for traits in clothing_traits:
		user.remove_clothing_trait(traits, self)
	
	emit_signal("traits_removed", user, clothing_traits)

# Accessory system with multiplayer support
func attach_accessory(accessory, user = null) -> bool:
	"""Attach an accessory to this clothing item"""
	var result = _attach_accessory_internal(accessory, user)
	
	if result and multiplayer.has_multiplayer_peer():
		var user_id = get_user_network_id(user) if user else ""
		sync_accessory_attached.rpc(get_item_network_id(accessory), user_id)
	
	return result

func _attach_accessory_internal(accessory, user = null) -> bool:
	"""Internal method for attaching accessories"""
	if not can_attach_accessory(accessory):
		return false
	
	accessories.append(accessory)
	accessory.attached_to = self
	
	# Move accessory to be a child of this clothing item
	if accessory.get_parent():
		accessory.get_parent().remove_child(accessory)
	add_child(accessory)
	
	accessory.visible = false # Accessories are represented through overlays
	
	if user and user.has_method("show_message"):
		user.show_message("You attach " + str(accessory.obj_name) + " to " + str(obj_name) + ".")
	
	emit_signal("accessory_attached", accessory)
	update_appearance()
	return true

func remove_accessory(accessory, user = null) -> bool:
	"""Remove an accessory from this clothing item"""
	var result = _remove_accessory_internal(accessory, user)
	
	if result and multiplayer.has_multiplayer_peer():
		var user_id = get_user_network_id(user) if user else ""
		sync_accessory_removed.rpc(get_item_network_id(accessory), user_id)
	
	return result

func _remove_accessory_internal(accessory, user = null) -> bool:
	"""Internal method for removing accessories"""
	if accessory not in accessories:
		return false
	
	accessories.erase(accessory)
	accessory.attached_to = null
	
	# Move accessory back to world or user's inventory
	remove_child(accessory)
	
	if user:
		# Try to put in user's hands first
		var inventory = user.get_node_or_null("InventorySystem")
		if inventory and inventory.has_method("pick_up_item"):
			if inventory.pick_up_item(accessory):
				if user.has_method("show_message"):
					user.show_message("You remove " + str(accessory.obj_name) + " from " + str(obj_name) + ".")
			else:
				# Drop to ground if hands are full
				var world = user.get_parent()
				world.add_child(accessory)
				accessory.global_position = user.global_position
				accessory.visible = true
		else:
			# Just make visible again
			accessory.visible = true
	else:
		# Just make visible again
		accessory.visible = true
	
	emit_signal("accessory_removed", accessory)
	update_appearance()
	return true

func can_attach_accessory(accessory) -> bool:
	"""Check if an accessory can be attached to this clothing"""
	if not accessory.has_method("get_accessory_slot"):
		return false
	
	var accessory_slot = accessory.get_accessory_slot()
	
	# Check if this clothing supports the accessory slot
	if (valid_accessory_slots & accessory_slot) == 0:
		return false
	
	# Check attachment limits
	var current_count = 0
	for acc in accessories:
		if acc.get_accessory_slot() == accessory_slot:
			current_count += 1
	
	return current_count < worn_accessory_limit

# Helper functions for multiplayer (same as Item class)
func get_user_network_id(user: Node) -> String:
	if not user:
		return ""
	
	if user.has_method("get_network_id"):
		return user.get_network_id()
	elif "peer_id" in user:
		return "player_" + str(user.peer_id)
	elif user.has_meta("network_id"):
		return user.get_meta("network_id")
	else:
		return user.get_path()

func find_user_by_network_id(network_id: String) -> Node:
	if network_id == "":
		return null
	
	# Handle player targets
	if network_id.begins_with("player_"):
		var peer_id_str = network_id.split("_")[1]
		var peer_id_val = peer_id_str.to_int()
		return find_player_by_peer_id(peer_id_val)
	
	# Handle path-based targets
	if network_id.begins_with("/"):
		return get_node_or_null(network_id)
	
	return null

func find_player_by_peer_id(peer_id_val: int) -> Node:
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player.has_meta("peer_id") and player.get_meta("peer_id") == peer_id_val:
			return player
		if "peer_id" in player and player.peer_id == peer_id_val:
			return player
	
	return null

func get_item_network_id(item) -> String:
	if not item:
		return ""
	
	if item.has_method("get_network_id"):
		return item.get_network_id()
	elif "network_id" in item and item.network_id != "":
		return str(item.network_id)
	elif item.has_meta("network_id"):
		return str(item.get_meta("network_id"))
	else:
		var new_id = str(item.get_instance_id()) + "_" + str(Time.get_ticks_msec())
		item.set_meta("network_id", new_id)
		return new_id

func find_item_by_network_id(network_id: String):
	if network_id == "":
		return null
	
	# Check world items
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		world = get_tree().current_scene
	
	if world and world.has_method("get_item_by_network_id"):
		var item = world.get_item_by_network_id(network_id)
		if item:
			return item
	
	# Check all items in scene
	var all_items = get_tree().get_nodes_in_group("items")
	for item in all_items:
		if get_item_network_id(item) == network_id:
			return item
	
	return null

# Remaining methods from original (unchanged but important for functionality)
func get_slot_flag_for_slot(slot: EquipSlot) -> int:
	"""Convert EquipSlot to ItemSlotFlags for inventory system"""
	match slot:
		EquipSlot.WEAR_SUIT:
			return 1  # ITEM_SLOT_OCLOTHING
		EquipSlot.W_UNIFORM:
			return 2  # ITEM_SLOT_ICLOTHING
		EquipSlot.GLOVES:
			return 4  # ITEM_SLOT_GLOVES
		EquipSlot.GLASSES:
			return 8  # ITEM_SLOT_EYES
		EquipSlot.EARS:
			return 16  # ITEM_SLOT_EARS
		EquipSlot.WEAR_MASK:
			return 32  # ITEM_SLOT_MASK
		EquipSlot.HEAD:
			return 64  # ITEM_SLOT_HEAD
		EquipSlot.SHOES:
			return 128  # ITEM_SLOT_FEET
		EquipSlot.WEAR_ID:
			return 256  # ITEM_SLOT_ID
		EquipSlot.BELT:
			return 512  # ITEM_SLOT_BELT
		EquipSlot.BACK:
			return 1024  # ITEM_SLOT_BACK
		EquipSlot.R_STORE:
			return 2048  # ITEM_SLOT_R_POCKET
		EquipSlot.L_STORE:
			return 4096  # ITEM_SLOT_L_POCKET
		EquipSlot.S_STORE:
			return 8192  # ITEM_SLOT_SUITSTORE
		EquipSlot.HANDCUFFED:
			return 16384  # ITEM_SLOT_HANDCUFF
		EquipSlot.LEFT_HAND:
			return 32768  # ITEM_SLOT_L_HAND
		EquipSlot.RIGHT_HAND:
			return 65536  # ITEM_SLOT_R_HAND
		_:
			return 0

func update_armor_values():
	"""Update the inherited armor dictionaries with clothing-specific values"""
	if not soft_armor:
		soft_armor = {}
	
	soft_armor["melee"] = armor_melee
	soft_armor["bullet"] = armor_bullet
	soft_armor["laser"] = armor_laser
	soft_armor["energy"] = armor_energy
	soft_armor["bomb"] = armor_bomb
	soft_armor["bio"] = armor_bio
	soft_armor["rad"] = armor_rad
	soft_armor["acid"] = armor_internal_damage

func setup_internal_storage():
	"""Set up internal storage for clothing items like suits with pockets"""
	if storage_slots <= 0:
		return
	
	# Create a simple storage container
	internal_storage = {
		"items": [],
		"max_slots": storage_slots,
		"max_space": max_storage_space,
		"allowed_types": can_hold_items
	}

func setup_clothing_visuals():
	"""Set up clothing-specific visual elements"""
	# Add blood overlay capability
	if blood_overlay_type != "":
		add_to_group("bloodied_clothing")

func apply_armor_to_user(user):
	"""Apply armor bonuses to the user"""
	if not user.has_method("add_armor_bonus"):
		return
	
	var armor_bonus = {
		"melee": armor_melee,
		"bullet": armor_bullet,
		"laser": armor_laser,
		"energy": armor_energy,
		"bomb": armor_bomb,
		"bio": armor_bio,
		"rad": armor_rad,
		"internal": armor_internal_damage
	}
	
	user.add_armor_bonus(self, armor_bonus)

func remove_armor_from_user(user):
	"""Remove armor bonuses from the user"""
	if user.has_method("remove_armor_bonus"):
		user.remove_armor_bonus(self)

func apply_movement_modification(user, modifier: float):
	"""Apply movement speed modification to user"""
	if user.has_method("modify_movement_speed"):
		user.modify_movement_speed(modifier, self)

func play_equip_sound():
	"""Play equipment sound"""
	if equip_sounds.size() > 0:
		var sound = equip_sounds[randi() % equip_sounds.size()]
		if has_method("play_audio"):
			play_audio(sound, -5.0)

func play_unequip_sound():
	"""Play unequipment sound"""
	if unequip_sounds.size() > 0:
		var sound = unequip_sounds[randi() % unequip_sounds.size()]
		if has_method("play_audio"):
			play_audio(sound, -5.0)

func update_appearance():
	"""Update visual appearance including accessories"""
	if super.has_method("update_appearance"):
		super.update_appearance()
	
	# Update accessory overlays
	for accessory in accessories:
		if accessory.has_method("update_overlay"):
			accessory.update_overlay()

# Debug and testing methods
func test_sprite_integration(user = null):
	"""Test method to verify sprite system integration"""
	if not user:
		user = equipped_user
	
	if not user:
		print("Clothing: No user available for sprite integration test")
		return
	
	var sprite_system = get_sprite_system(user)
	if not sprite_system:
		print("Clothing: No sprite system found on user")
		return
	
	print("Clothing: Found sprite system: ", sprite_system.name)
	print("Clothing: Primary slot: ", primary_slot)
	print("Clothing: Sprite slot: ", convert_inventory_slot_to_sprite_slot(primary_slot))
	print("Clothing: Texture path: ", get_clothing_texture_path())
	print("Clothing: Has texture: ", get_clothing_texture() != null)
	
	if equipped_slot != EquipSlot.NONE:
		print("Clothing: Currently equipped in slot: ", equipped_slot)
		update_sprite_system_visual(user, equipped_slot, true)
	else:
		print("Clothing: Not currently equipped")

func force_visual_update():
	"""Force update the visual representation"""
	if equipped_user and equipped_slot != EquipSlot.NONE:
		update_sprite_system_visual(equipped_user, equipped_slot, true)
		print("Clothing: Forced visual update for ", obj_name)

# Utility functions
func get_total_armor(armor_type: String) -> int:
	"""Get total armor including accessories"""
	var total = get("armor_" + armor_type)
	
	for accessory in accessories:
		if accessory.has_method("get_armor_bonus"):
			total += accessory.get_armor_bonus(armor_type)
	
	return total

func get_trait(trait_name: String) -> bool:
	"""Check if clothing has a specific trait"""
	return trait_name in clothing_traits

func get_network_id() -> String:
	"""Get network ID for synchronization"""
	if has_method("get_instance_id"):
		return str(get_instance_id())
	return ""
