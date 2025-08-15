extends Item
class_name Clothing

# =============================================================================
# SIGNALS
# =============================================================================

signal clothing_equipped(user, slot)
signal clothing_unequipped(user, slot)
signal accessory_attached(accessory)
signal accessory_removed(accessory)
signal traits_applied(user, traits)
signal traits_removed(user, traits)
signal storage_opened(user, storage_item)
signal storage_closed(user, storage_item)
signal storage_item_added(item, storage_item)
signal storage_item_removed(item, storage_item)

# =============================================================================
# ENUMS AND CONSTANTS
# =============================================================================

enum EyeProtection {
	NONE = 0,
	FLASH = 1,
	WELDING = 2,
	FULL = 3
}

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

enum ItemSlotFlags {
	ITEM_SLOT_OCLOTHING = 1,
	ITEM_SLOT_ICLOTHING = 2,
	ITEM_SLOT_GLOVES = 4,
	ITEM_SLOT_EYES = 8,
	ITEM_SLOT_EARS = 16,
	ITEM_SLOT_MASK = 32,
	ITEM_SLOT_HEAD = 64,
	ITEM_SLOT_FEET = 128,
	ITEM_SLOT_ID = 256,
	ITEM_SLOT_BELT = 512,
	ITEM_SLOT_BACK = 1024,
	ITEM_SLOT_R_POCKET = 2048,
	ITEM_SLOT_L_POCKET = 4096,
	ITEM_SLOT_SUITSTORE = 8192,
	ITEM_SLOT_HANDCUFF = 16384,
	ITEM_SLOT_L_HAND = 32768,
	ITEM_SLOT_R_HAND = 65536
}

enum StorageType {
	NONE = 0,
	SIZE_BASED = 1,
	SLOT_BASED = 2
}

# =============================================================================
# EXPORT PROPERTIES
# =============================================================================

@export_group("Clothing Properties")
@export var primary_slot: Slots = Slots.NONE
@export var eye_protection: EyeProtection = EyeProtection.NONE
@export var movement_compensation: float = 0.0
@export var drag_unequip: bool = false
@export var blood_overlay_type: String = ""
@export var fire_resist: float = 100.0
@export var siemens_coefficient: float = 1.0

@export_group("Armor Properties")
@export var armor_melee: int = 0
@export var armor_bullet: int = 0
@export var armor_laser: int = 0
@export var armor_energy: int = 0
@export var armor_bomb: int = 0
@export var armor_bio: int = 0
@export var armor_rad: int = 0
@export var armor_internal_damage: int = 0

@export_group("Clothing Traits")
@export var clothing_traits: Array[String] = []
@export var clothing_traits_active: bool = true

@export_group("Accessory System")
@export var valid_accessory_slots: int = 0
@export var can_become_accessory: bool = false
@export var worn_accessory_slot: AccessorySlot = AccessorySlot.DEFAULT
@export var accessory_path: String = "res://scripts/items/clothing/Accessory.gd"
@export var worn_accessory_limit: int = 1

@export_group("Equipment Restrictions")
@export var suit_restricted: Array = []
@export var under_restricted: Array = []

@export_group("Storage System")
@export var storage_type: StorageType = StorageType.NONE
@export var storage_max_size: int = 20
@export var storage_slots: int = 0
@export var max_storage_space: int = 0
@export var can_hold_items: Array = []
@export var storage_w_class_multiplier: float = 1.0
@export var has_open_close_animation: bool = false
@export var open_animation: String = "open"
@export var close_animation: String = "close"
@export var default_animation: String = "default"

@export_group("Visual Properties")
@export var hide_prints: bool = false
@export var clothing_texture_path: String = ""
@export var clothing_sprite_frames: int = 4

@export_group("Audio Properties")
@export var equip_sounds: Array[AudioStream] = []
@export var unequip_sounds: Array[AudioStream] = []

# =============================================================================
# PROPERTIES
# =============================================================================

var equipped_user = null
var equipped_slot: int = Slots.NONE
var valid_slots: Array = []
var accessories: Array = []
var internal_storage = null
var clothing_blood_amt: float = 0.0

var storage_items: Array = []
var storage_is_open: bool = false
var storage_current_size: int = 0
var storage_users: Array = []

# =============================================================================
# SLOT CONFIGURATION
# =============================================================================

var slot_to_sprite_mapping: Dictionary = {
	Slots.HEAD: 0,
	Slots.GLASSES: 1,
	Slots.WEAR_MASK: 2,
	Slots.EARS: 3,
	Slots.WEAR_SUIT: 5,
	Slots.W_UNIFORM: 6,
	Slots.GLOVES: 8,
	Slots.BELT: 9,
	Slots.SHOES: 10,
	Slots.BACK: 11,
	Slots.WEAR_ID: 12,
	Slots.LEFT_HAND: 13,
	Slots.RIGHT_HAND: 14,
	Slots.L_STORE: 15,
	Slots.R_STORE: 16,
	Slots.S_STORE: 17
}

var slot_to_flag_mapping: Dictionary = {
	Slots.WEAR_SUIT: ItemSlotFlags.ITEM_SLOT_OCLOTHING,
	Slots.W_UNIFORM: ItemSlotFlags.ITEM_SLOT_ICLOTHING,
	Slots.GLOVES: ItemSlotFlags.ITEM_SLOT_GLOVES,
	Slots.GLASSES: ItemSlotFlags.ITEM_SLOT_EYES,
	Slots.EARS: ItemSlotFlags.ITEM_SLOT_EARS,
	Slots.WEAR_MASK: ItemSlotFlags.ITEM_SLOT_MASK,
	Slots.HEAD: ItemSlotFlags.ITEM_SLOT_HEAD,
	Slots.SHOES: ItemSlotFlags.ITEM_SLOT_FEET,
	Slots.WEAR_ID: ItemSlotFlags.ITEM_SLOT_ID,
	Slots.BELT: ItemSlotFlags.ITEM_SLOT_BELT,
	Slots.BACK: ItemSlotFlags.ITEM_SLOT_BACK,
	Slots.R_STORE: ItemSlotFlags.ITEM_SLOT_R_POCKET,
	Slots.L_STORE: ItemSlotFlags.ITEM_SLOT_L_POCKET,
	Slots.S_STORE: ItemSlotFlags.ITEM_SLOT_SUITSTORE,
	Slots.HANDCUFFED: ItemSlotFlags.ITEM_SLOT_HANDCUFF,
	Slots.LEFT_HAND: ItemSlotFlags.ITEM_SLOT_L_HAND,
	Slots.RIGHT_HAND: ItemSlotFlags.ITEM_SLOT_R_HAND
}

var slot_texture_paths: Dictionary = {
	Slots.HEAD: "head",
	Slots.GLASSES: "eyes",
	Slots.WEAR_MASK: "mask",
	Slots.EARS: "ears",
	Slots.WEAR_SUIT: "suits",
	Slots.W_UNIFORM: "uniforms",
	Slots.GLOVES: "gloves",
	Slots.BELT: "belts",
	Slots.SHOES: "shoes",
	Slots.BACK: "back",
	Slots.WEAR_ID: "id",
	Slots.L_STORE: "pockets",
	Slots.R_STORE: "pockets",
	Slots.S_STORE: "pockets"
}

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init():
	super._init()
	entity_type = "clothing"
	pickupable = true
	
	setup_valid_slots()
	update_armor_values()
	
	if storage_type != StorageType.NONE:
		setup_storage_system()

func _ready():
	super._ready()
	
	if not is_in_group("clothing"):
		add_to_group("clothing")
	
	if storage_type != StorageType.NONE:
		add_to_group("storage_items")
		print("Clothing item ", obj_name, " initialized as storage type: ", storage_type)
		print("Storage max size: ", storage_max_size)
		print("Storage slots: ", storage_slots)
	
	setup_clothing_visuals()
	setup_texture_path()

func setup_valid_slots():
	if not valid_slots:
		valid_slots = []
	
	if primary_slot != Slots.NONE and primary_slot not in valid_slots:
		valid_slots.append(primary_slot)
	
	if primary_slot != Slots.NONE:
		equip_slot_flags = get_slot_flag_for_slot(primary_slot)

func setup_texture_path():
	if clothing_texture_path == "" and obj_name != "":
		var base_path = "res://Graphics/clothing/"
		var slot_name = get_slot_texture_folder(primary_slot)
		if slot_name != "":
			clothing_texture_path = base_path + slot_name + "/" + obj_name.to_lower().replace(" ", "_") + ".png"

func setup_storage_system():
	storage_items = []
	storage_is_open = false
	storage_current_size = 0
	storage_users = []
	
	if storage_type == StorageType.SIZE_BASED:
		max_storage_space = storage_max_size
	elif storage_type == StorageType.SLOT_BASED:
		max_storage_space = storage_slots

func setup_clothing_visuals():
	if blood_overlay_type != "":
		add_to_group("bloodied_clothing")

func update_armor_values():
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

# =============================================================================
# EQUIPMENT SYSTEM
# =============================================================================

func equipped(user, slot: int):
	_equipped_internal(user, slot)
	
	if multiplayer.has_multiplayer_peer():
		sync_clothing_equipped.rpc(get_user_network_id(user), slot)

func _equipped_internal(user, slot: int):
	equipped_user = user
	equipped_slot = slot
	
	if clothing_traits_active and clothing_traits.size() > 0:
		_apply_clothing_traits_internal(user)
	
	apply_armor_to_user(user)
	play_equip_sound()
	
	if movement_compensation != 0.0:
		apply_movement_modification(user, -movement_compensation)
	
	handle_equip_effects(user, slot)
	update_sprite_system_visual(user, slot, true)
	
	emit_signal("clothing_equipped", user, slot)

func unequipped(user, slot: int):
	_unequipped_internal(user, slot)
	
	if multiplayer.has_multiplayer_peer():
		sync_clothing_unequipped.rpc(get_user_network_id(user), slot)

func _unequipped_internal(user, slot: int):
	if clothing_traits_active and clothing_traits.size() > 0:
		_remove_clothing_traits_internal(user)
	
	remove_armor_from_user(user)
	play_unequip_sound()
	
	if movement_compensation != 0.0:
		apply_movement_modification(user, movement_compensation)
	
	handle_unequip_effects(user, slot)
	update_sprite_system_visual(user, slot, false)
	
	if storage_is_open:
		close_storage(user)
	
	equipped_user = null
	equipped_slot = Slots.NONE
	
	emit_signal("clothing_unequipped", user, slot)

func handle_equip_effects(user, slot: int):
	match slot:
		Slots.WEAR_MASK:
			if user.has_method("update_breathing"):
				user.update_breathing()
		Slots.GLASSES:
			if user.has_method("update_vision"):
				user.update_vision()
		Slots.HEAD:
			if user.has_method("update_head_protection"):
				user.update_head_protection()
		Slots.EARS:
			if user.has_method("update_hearing"):
				user.update_hearing()
		Slots.L_STORE, Slots.R_STORE, Slots.S_STORE:
			if user.has_method("update_storage_capacity"):
				user.update_storage_capacity()

func handle_unequip_effects(user, slot: int):
	match slot:
		Slots.WEAR_MASK:
			if user.has_method("update_breathing"):
				user.update_breathing()
		Slots.GLASSES:
			if user.has_method("update_vision"):
				user.update_vision()
		Slots.HEAD:
			if user.has_method("update_head_protection"):
				user.update_head_protection()
		Slots.EARS:
			if user.has_method("update_hearing"):
				user.update_hearing()
		Slots.L_STORE, Slots.R_STORE, Slots.S_STORE:
			if user.has_method("update_storage_capacity"):
				user.update_storage_capacity()

# =============================================================================
# STORAGE SYSTEM
# =============================================================================

func interact(user) -> bool:
	print("Clothing interact called on: ", obj_name)
	print("Storage type: ", storage_type)
	
	if storage_type != StorageType.NONE and can_access_storage(user):
		print("This is a storage item, toggling storage")
		toggle_storage(user)
		return true
	
	print("Not a storage item or cannot access, calling super")
	return super.interact(user)

func can_access_storage(user) -> bool:
	print("Checking can_access_storage for user: ", user.name if user else "null")
	print("Storage type: ", storage_type)
	
	if storage_type == StorageType.NONE:
		print("Storage type is NONE")
		return false
	
	if equipped_user and equipped_user != user:
		print("Storage equipped by different user")
		return false
	
	if equipped_user == user:
		print("Storage equipped by same user - access granted")
		return true
	
	var distance = global_position.distance_to(user.global_position)
	print("Distance to storage: ", distance)
	var can_access = distance <= 64.0
	print("Can access (distance check): ", can_access)
	return can_access

func toggle_storage(user):
	print("Clothing toggle_storage called, current state: ", storage_is_open)
	if storage_is_open:
		close_storage(user)
	else:
		open_storage(user)

func open_storage(user):
	print("Clothing open_storage called")
	if not can_access_storage(user):
		print("Cannot access storage")
		return false
	
	print("Opening storage for user: ", user.name)
	storage_is_open = true
	if user not in storage_users:
		storage_users.append(user)
	
	update_storage_animation(true)
	print("Emitting storage_opened signal")
	emit_signal("storage_opened", user, self)
	
	if multiplayer and multiplayer.has_multiplayer_peer():
		sync_storage_state.rpc(get_user_network_id(user), true)
	
	return true

func close_storage(user):
	print("Clothing close_storage called")
	storage_is_open = false
	if user in storage_users:
		storage_users.erase(user)
	
	update_storage_animation(false)
	print("Emitting storage_closed signal")
	emit_signal("storage_closed", user, self)
	
	if multiplayer and multiplayer.has_multiplayer_peer():
		sync_storage_state.rpc(get_user_network_id(user), false)

func add_item_to_storage(item: Node, user = null) -> bool:
	if not can_store_item(item):
		return false
	
	var item_size = get_item_storage_size(item)
	
	if storage_type == StorageType.SIZE_BASED:
		if storage_current_size + item_size > storage_max_size:
			return false
	elif storage_type == StorageType.SLOT_BASED:
		if storage_items.size() >= storage_slots:
			return false
		
		if can_hold_items.size() > 0:
			var item_type = item.get("entity_type")
			if item_type not in can_hold_items:
				return false
	
	if item.get_parent():
		item.get_parent().remove_child(item)
	add_child(item)
	
	item.position = Vector2.ZERO
	item.visible = false
	
	storage_items.append(item)
	storage_current_size += item_size
	
	if item.has_method("set_flag") and "ItemFlags" in item:
		item.set_flag("item_flags", item.ItemFlags.IN_INVENTORY, true)
	
	emit_signal("storage_item_added", item, self)
	
	if multiplayer.has_multiplayer_peer():
		sync_storage_item_action.rpc("add", get_item_network_id(item), get_user_network_id(user))
	
	return true

func remove_item_from_storage(item: Node, user = null) -> bool:
	if item not in storage_items:
		return false
	
	var item_size = get_item_storage_size(item)
	
	storage_items.erase(item)
	storage_current_size -= item_size
	
	if item.has_method("set_flag") and "ItemFlags" in item:
		item.set_flag("item_flags", item.ItemFlags.IN_INVENTORY, false)
	# The inventory system will handle where it goes
	if item.get_parent() == self:
		remove_child(item)
	
	emit_signal("storage_item_removed", item, self)
	
	if multiplayer and multiplayer.has_multiplayer_peer():
		sync_storage_item_action.rpc("remove", get_item_network_id(item), get_user_network_id(user))
	
	print("Successfully removed item from storage: ", item.obj_name if "obj_name" in item else item.name)
	return true

func can_store_item(item: Node) -> bool:
	if not item or storage_type == StorageType.NONE:
		return false
	
	if item.get("pickupable") == false:
		return false
	
	return true

func get_item_storage_size(item: Node) -> int:
	if storage_type == StorageType.SLOT_BASED:
		return 1
	
	var w_class = item.get("w_class")
	if w_class == null:
		# Fallback if item doesn't have w_class
		return 1
	
	return max(1, int(float(w_class) * storage_w_class_multiplier))

func get_storage_space_remaining() -> int:
	if storage_type == StorageType.SIZE_BASED:
		return storage_max_size - storage_current_size
	elif storage_type == StorageType.SLOT_BASED:
		return storage_slots - storage_items.size()
	return 0

func update_storage_animation(is_opening: bool):
	if not has_open_close_animation:
		return
	
	var icon_node = get_node_or_null("Icon")
	if not icon_node:
		return
	
	if icon_node is AnimatedSprite2D:
		var sprite = icon_node as AnimatedSprite2D
		if sprite.sprite_frames:
			var target_animation = open_animation if is_opening else close_animation
			if sprite.sprite_frames.has_animation(target_animation):
				sprite.animation = target_animation
				sprite.play()
	
	if equipped_user:
		update_sprite_system_visual(equipped_user, equipped_slot, true)

func _process(delta):
	# Only check storage access occasionally to avoid spam
	if storage_is_open and storage_users.size() > 0:
		# Use a timer to avoid checking every frame
		var time_now = Time.get_ticks_msec() / 1000.0
		if not has_meta("last_storage_check") or time_now - get_meta("last_storage_check") > 1.0:
			set_meta("last_storage_check", time_now)
			
			for user in storage_users.duplicate():
				if not can_access_storage(user):
					close_storage(user)

# =============================================================================
# SPRITE SYSTEM INTEGRATION
# =============================================================================

func update_sprite_system_visual(user, inventory_slot: int, is_equipping: bool):
	var sprite_system = get_sprite_system(user)
	if not sprite_system:
		return
	
	var sprite_slot = convert_inventory_slot_to_sprite_slot(inventory_slot)
	if sprite_slot == -1:
		return
	
	if is_equipping:
		if sprite_system.has_method("equip_item"):
			sprite_system.equip_item(self, sprite_slot)
	else:
		if sprite_system.has_method("unequip_item"):
			sprite_system.unequip_item(sprite_slot)
	
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		sync_visual_update.rpc(get_user_network_id(user), inventory_slot, is_equipping)

func get_sprite_system(user) -> Node:
	if not user:
		return null
	
	var sprite_system = user.get_node_or_null("HumanSpriteSystem")
	if sprite_system:
		return sprite_system
	
	sprite_system = user.get_node_or_null("SpriteSystem")
	if sprite_system:
		return sprite_system
	
	for child in user.get_children():
		if child.has_method("equip_item") and child.has_method("unequip_item"):
			return child
	
	return null

func convert_inventory_slot_to_sprite_slot(inventory_slot: int) -> int:
	return slot_to_sprite_mapping.get(inventory_slot, -1)

func get_slot_flag_for_slot(slot: Slots) -> int:
	return slot_to_flag_mapping.get(slot, 0)

func get_slot_texture_folder(slot: Slots) -> String:
	return slot_texture_paths.get(slot, "misc")

# =============================================================================
# TEXTURE MANAGEMENT
# =============================================================================

func get_clothing_texture() -> Texture2D:
	var icon_node = get_node_or_null("Sprite")
	if icon_node and icon_node.texture:
		return icon_node.texture
	
	return create_fallback_texture()

func create_fallback_texture() -> Texture2D:
	var image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.7, 0.7, 0.7, 1.0))
	return ImageTexture.create_from_image(image)

func get_texture() -> Texture2D:
	return get_clothing_texture()

func get_clothing_texture_path() -> String:
	return clothing_texture_path

func set_clothing_texture_path(path: String):
	clothing_texture_path = path
	
	if equipped_user and equipped_slot != Slots.NONE:
		update_sprite_system_visual(equipped_user, equipped_slot, true)

# =============================================================================
# TRAITS SYSTEM
# =============================================================================

func apply_clothing_traits(user):
	_apply_clothing_traits_internal(user)
	
	if multiplayer.has_multiplayer_peer():
		sync_clothing_traits.rpc(get_user_network_id(user), true)

func _apply_clothing_traits_internal(user):
	if not user.has_method("add_clothing_trait"):
		return
	
	for traits in clothing_traits:
		user.add_clothing_trait(traits, self)
	
	emit_signal("traits_applied", user, clothing_traits)

func remove_clothing_traits(user):
	_remove_clothing_traits_internal(user)
	
	if multiplayer.has_multiplayer_peer():
		sync_clothing_traits.rpc(get_user_network_id(user), false)

func _remove_clothing_traits_internal(user):
	if not user.has_method("remove_clothing_trait"):
		return
	
	for traits in clothing_traits:
		user.remove_clothing_trait(traits, self)
	
	emit_signal("traits_removed", user, clothing_traits)

func get_trait(trait_name: String) -> bool:
	return trait_name in clothing_traits

# =============================================================================
# ACCESSORY SYSTEM
# =============================================================================

func attach_accessory(accessory, user = null) -> bool:
	var result = _attach_accessory_internal(accessory, user)
	
	if result and multiplayer.has_multiplayer_peer():
		var user_id = get_user_network_id(user) if user else ""
		sync_accessory_attached.rpc(get_item_network_id(accessory), user_id)
	
	return result

func _attach_accessory_internal(accessory, user = null) -> bool:
	if not can_attach_accessory(accessory):
		return false
	
	accessories.append(accessory)
	accessory.attached_to = self
	
	if accessory.get_parent():
		accessory.get_parent().remove_child(accessory)
	add_child(accessory)
	
	accessory.visible = false
	
	if user and user.has_method("show_message"):
		user.show_message("You attach " + str(accessory.obj_name) + " to " + str(obj_name) + ".")
	
	emit_signal("accessory_attached", accessory)
	update_appearance()
	return true

func remove_accessory(accessory, user = null) -> bool:
	var result = _remove_accessory_internal(accessory, user)
	
	if result and multiplayer.has_multiplayer_peer():
		var user_id = get_user_network_id(user) if user else ""
		sync_accessory_removed.rpc(get_item_network_id(accessory), user_id)
	
	return result

func _remove_accessory_internal(accessory, user = null) -> bool:
	if accessory not in accessories:
		return false
	
	accessories.erase(accessory)
	accessory.attached_to = null
	
	remove_child(accessory)
	
	if user:
		var inventory = user.get_node_or_null("InventorySystem")
		if inventory and inventory.has_method("pick_up_item"):
			if inventory.pick_up_item(accessory):
				if user.has_method("show_message"):
					user.show_message("You remove " + str(accessory.obj_name) + " from " + str(obj_name) + ".")
			else:
				var world = user.get_parent()
				world.add_child(accessory)
				accessory.global_position = user.global_position
				accessory.visible = true
		else:
			accessory.visible = true
	else:
		accessory.visible = true
	
	emit_signal("accessory_removed", accessory)
	update_appearance()
	return true

func can_attach_accessory(accessory) -> bool:
	if not accessory.has_method("get_accessory_slot"):
		return false
	
	var accessory_slot = accessory.get_accessory_slot()
	
	if (valid_accessory_slots & accessory_slot) == 0:
		return false
	
	var current_count = 0
	for acc in accessories:
		if acc.get_accessory_slot() == accessory_slot:
			current_count += 1
	
	return current_count < worn_accessory_limit

# =============================================================================
# ARMOR SYSTEM
# =============================================================================

func apply_armor_to_user(user):
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
	if user.has_method("remove_armor_bonus"):
		user.remove_armor_bonus(self)

func get_total_armor(armor_type: String) -> int:
	var total = get("armor_" + armor_type)
	
	for accessory in accessories:
		if accessory.has_method("get_armor_bonus"):
			total += accessory.get_armor_bonus(armor_type)
	
	return total

# =============================================================================
# MOVEMENT SYSTEM
# =============================================================================

func apply_movement_modification(user, modifier: float):
	if user.has_method("modify_movement_speed"):
		user.modify_movement_speed(modifier, self)

# =============================================================================
# AUDIO SYSTEM
# =============================================================================

func play_equip_sound():
	if equip_sounds.size() > 0:
		var sound = equip_sounds[randi() % equip_sounds.size()]
		if has_method("play_audio"):
			play_audio(sound, -5.0)

func play_unequip_sound():
	if unequip_sounds.size() > 0:
		var sound = unequip_sounds[randi() % unequip_sounds.size()]
		if has_method("play_audio"):
			play_audio(sound, -5.0)

# =============================================================================
# VISUAL UPDATES
# =============================================================================

func update_appearance():
	if super.has_method("update_appearance"):
		super.update_appearance()
	
	for accessory in accessories:
		if accessory.has_method("update_overlay"):
			accessory.update_overlay()

func force_visual_update():
	if equipped_user and equipped_slot != Slots.NONE:
		update_sprite_system_visual(equipped_user, equipped_slot, true)
		print("Clothing: Forced visual update for ", obj_name)

# =============================================================================
# MULTIPLAYER SYNCHRONIZATION
# =============================================================================

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

@rpc("any_peer", "call_local", "reliable")
func sync_storage_state(user_network_id: String, is_open: bool):
	var user = find_user_by_network_id(user_network_id)
	if user:
		if is_open:
			storage_is_open = true
			if user not in storage_users:
				storage_users.append(user)
			update_storage_animation(true)
		else:
			storage_is_open = false
			if user in storage_users:
				storage_users.erase(user)
			update_storage_animation(false)

@rpc("any_peer", "call_local", "reliable")
func sync_storage_item_action(action: String, item_network_id: String, user_network_id: String):
	var item = find_item_by_network_id(item_network_id)
	var user = find_user_by_network_id(user_network_id) if user_network_id != "" else null
	
	if item:
		match action:
			"add":
				if item not in storage_items:
					if item.get_parent():
						item.get_parent().remove_child(item)
					add_child(item)
					
					item.position = Vector2.ZERO
					item.visible = false
					
					storage_items.append(item)
					storage_current_size += get_item_storage_size(item)
					
					if item.has_method("set_flag") and "ItemFlags" in item:
						item.set_flag("item_flags", item.ItemFlags.IN_INVENTORY, true)
			"remove":
				if item in storage_items:
					storage_items.erase(item)
					storage_current_size -= get_item_storage_size(item)
					
					if item.has_method("set_flag") and "ItemFlags" in item:
						item.set_flag("item_flags", item.ItemFlags.IN_INVENTORY, false)

# =============================================================================
# NETWORK UTILITIES
# =============================================================================

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
	
	if network_id.begins_with("player_"):
		var peer_id_str = network_id.split("_")[1]
		var peer_id_val = peer_id_str.to_int()
		return find_player_by_peer_id(peer_id_val)
	
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
	
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		world = get_tree().current_scene
	
	if world and world.has_method("get_item_by_network_id"):
		var item = world.get_item_by_network_id(network_id)
		if item:
			return item
	
	var all_items = get_tree().get_nodes_in_group("items")
	for item in all_items:
		if get_item_network_id(item) == network_id:
			return item
	
	return null

func get_network_id() -> String:
	if has_method("get_instance_id"):
		return str(get_instance_id())
	return ""

# =============================================================================
# DEBUG AND TESTING
# =============================================================================

func test_sprite_integration(user = null):
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
	print("Clothing: Slot flag: ", get_slot_flag_for_slot(primary_slot))
	
	if equipped_slot != Slots.NONE:
		print("Clothing: Currently equipped in slot: ", equipped_slot)
		update_sprite_system_visual(user, equipped_slot, true)
	else:
		print("Clothing: Not currently equipped")

func debug_slot_mappings():
	print("=== Clothing Slot Debug Info ===")
	print("Primary slot: ", primary_slot)
	print("Sprite slot: ", convert_inventory_slot_to_sprite_slot(primary_slot))
	print("Slot flag: ", get_slot_flag_for_slot(primary_slot))
	print("Texture folder: ", get_slot_texture_folder(primary_slot))
	print("Valid slots: ", valid_slots)
	print("Equip slot flags: ", equip_slot_flags)
	
	print("\n=== All Slot Mappings ===")
	for slot in Slots.values():
		if slot == Slots.NONE:
			continue
		print("Slot ", slot, ": sprite=", slot_to_sprite_mapping.get(slot, "NONE"), 
			  ", flag=", slot_to_flag_mapping.get(slot, "NONE"),
			  ", folder=", slot_texture_paths.get(slot, "NONE"))
