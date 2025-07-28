extends Node
class_name InventorySystem

const HIDEFACE = 1
const HIDEALLHAIR = 2
const HIDETOPHAIR = 4
const HIDELOWHAIR = 8
const HIDEEARS = 16
const HIDEEYES = 32
const HIDEJUMPSUIT = 64
const HIDESHOES = 128
const HIDE_EXCESS_HAIR = 256

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

const ITEM_UNEQUIP_FAIL = 0
const ITEM_UNEQUIP_DROPPED = 1
const ITEM_UNEQUIP_UNEQUIPPED = 2

signal inventory_updated()
signal item_equipped(item, slot)
signal item_unequipped(item, slot)
signal active_hand_changed(new_hand)

var entity = null
var equipped_items: Dictionary = {}
var active_hand: int = EquipSlot.RIGHT_HAND
var wielded_scene_instance = null

# Weapon handling integration
var weapon_handling_component: Node = null
var wielded_weapon: Node = null

# Hidden items tracking
var hidden_items: Array = []  # Track items that should remain hidden

var gun_list = []
var melee_list = []
var ammo_list = []
var medical_list = []
var grenade_list = []
var engineering_list = []
var food_list = []
var brute_list = []
var burn_list = []
var tox_list = []
var oxy_list = []
var clone_list = []
var pain_list = []

func _init(owner_entity = null):
	entity = owner_entity
	for slot in EquipSlot.values():
		equipped_items[slot] = null

func _ready():
	if entity == null:
		entity = get_parent()
	
	# Get weapon handling component reference
	if entity:
		weapon_handling_component = entity.get_node_or_null("WeaponHandlingComponent")
		if weapon_handling_component:
			connect_weapon_handling_signals()
	
	var cleanup_timer = Timer.new()
	cleanup_timer.wait_time = 1.0
	cleanup_timer.autostart = true
	cleanup_timer.timeout.connect(clean_destroyed_items)
	add_child(cleanup_timer)
	
	# Connect to entity position changes to update carried items
	if entity.has_signal("position_changed"):
		entity.position_changed.connect(update_carried_items_position)

func connect_weapon_handling_signals():
	if not weapon_handling_component:
		print("InventorySystem: No weapon handling component found")
		return
	
	print("InventorySystem: Connecting to weapon handling component")
	
	# Connect to weapon wielded/unwielded signals
	if weapon_handling_component.has_signal("weapon_wielded"):
		if not weapon_handling_component.weapon_wielded.is_connected(_on_weapon_wielded):
			weapon_handling_component.weapon_wielded.connect(_on_weapon_wielded)
	
	if weapon_handling_component.has_signal("weapon_unwielded"):
		if not weapon_handling_component.weapon_unwielded.is_connected(_on_weapon_unwielded):
			weapon_handling_component.weapon_unwielded.connect(_on_weapon_unwielded)

func _on_weapon_wielded(weapon: Node, hand_slot: int):
	"""Handle weapon being wielded - load wielded scene instead of moving weapon"""
	wielded_weapon = weapon
	
	# Load and instance the wielded scene
	var wielded_scene = preload("res://Scenes/Effects/wielded.tscn")
	if wielded_scene:
		wielded_scene_instance = wielded_scene.instantiate()
		
		# Determine which hand to place the wielded scene in
		var other_hand = EquipSlot.LEFT_HAND if active_hand == EquipSlot.RIGHT_HAND else EquipSlot.RIGHT_HAND
		
		# If there's already an item in the other hand, move it to the primary hand
		var other_hand_item = equipped_items[other_hand]
		if other_hand_item and other_hand_item != wielded_scene_instance:
			equipped_items[other_hand] = null
			equipped_items[active_hand] = other_hand_item
		
		# Add the wielded scene to the entity and equip it
		entity.add_child(wielded_scene_instance)
		wielded_scene_instance.position = Vector2.ZERO
		equipped_items[other_hand] = wielded_scene_instance
		
		hide_item_icon(wielded_scene_instance)
		update_slot_visuals(other_hand)
	
	emit_signal("inventory_updated")

func _on_weapon_unwielded(weapon: Node, hand_slot: int):
	"""Handle weapon being unwielded - free and remove wielded scene"""
	wielded_weapon = null
	
	# Remove and free the wielded scene instance
	if wielded_scene_instance and is_instance_valid(wielded_scene_instance):
		# Find which hand has the wielded scene and clear it
		for slot in [EquipSlot.LEFT_HAND, EquipSlot.RIGHT_HAND]:
			if equipped_items[slot] == wielded_scene_instance:
				equipped_items[slot] = null
				update_slot_visuals(slot)
				break
		
		# Remove from entity and free
		if wielded_scene_instance.get_parent() == entity:
			entity.remove_child(wielded_scene_instance)
		wielded_scene_instance.queue_free()
		wielded_scene_instance = null
	
	emit_signal("inventory_updated")

func update_carried_items_position():
	for slot in equipped_items:
		var item = equipped_items[slot]
		if item and is_instance_valid(item):
			# Ensure carried items stay at entity position with no offset
			item.position = Vector2.ZERO

func pick_up_item(item):
	if not item or not item.pickupable:
		return false
	
	if item.is_in_group("depleted_items"):
		return false
	
	var active_item = equipped_items[active_hand]
	if active_item != null:
		return false
	
	var world = item.get_parent()
	if world and world != entity:
		world.remove_child(item)
		entity.add_child(item)
	
	# Ensure no offset when carried
	item.position = Vector2.ZERO
	
	if item.has_method("picked_up"):
		item.picked_up(entity)
	
	var success = equip_item(item, active_hand)
	
	if success:
		sync_inventory_action.rpc("pick_up", get_item_network_id(item), active_hand, Vector2.ZERO)
	
	return success

func equip_item(item, slot):
	if not item or not can_equip_to_slot(item, slot):
		return false
	
	var existing_item = equipped_items[slot]
	if existing_item:
		unequip_item(slot)
	
	if item.get_parent() != entity:
		if item.get_parent():
			item.get_parent().remove_child(item)
		entity.add_child(item)
	
	# Ensure item follows entity position exactly with no offset
	item.position = Vector2.ZERO
	
	equipped_items[slot] = item
	hide_item_icon(item)
	sort_item(item)
	
	if item.has_method("equipped"):
		item.equipped(entity, slot)
	
	update_slot_visuals(slot)
	
	emit_signal("item_equipped", item, slot)
	emit_signal("inventory_updated")
	
	sync_inventory_action.rpc("equip", get_item_network_id(item), slot, Vector2.ZERO)
	
	return true

# Method to directly equip items to specific hands
func equip_item_to_hand(item, hand_slot: int):
	"""Directly equip an item to a specific hand slot"""
	if hand_slot != EquipSlot.LEFT_HAND and hand_slot != EquipSlot.RIGHT_HAND:
		return false
	
	if not item or not can_equip_to_slot(item, hand_slot):
		return false
	
	# Check if trying to equip to hand occupied by wielded weapon
	if wielded_weapon and equipped_items[hand_slot] == wielded_weapon:
		return false
	
	return equip_item(item, hand_slot)

func unequip_item(slot, force = false):
	var item = equipped_items[slot]
	if not item:
		return ITEM_UNEQUIP_FAIL
	
	# Check if this item is a wielded weapon - prevent unequipping unless forced
	if not force and item == wielded_weapon:
		if weapon_handling_component:
			weapon_handling_component.force_unwield()
		return ITEM_UNEQUIP_FAIL
	
	if item.get("trait_nodrop") and not force:
		return ITEM_UNEQUIP_FAIL
	
	if item.has_method("unequipped"):
		item.unequipped(entity, slot)
	
	show_item_icon(item)
	remove_from_lists(item)
	equipped_items[slot] = null
	update_slot_visuals(slot)
	
	emit_signal("item_unequipped", item, slot)
	emit_signal("inventory_updated")
	
	sync_inventory_action.rpc("unequip", get_item_network_id(item), slot, Vector2.ZERO)
	
	return ITEM_UNEQUIP_UNEQUIPPED

func drop_item(slot_or_item, direction = Vector2.DOWN, force = false):
	var slot = EquipSlot.NONE
	var item = null
	
	if typeof(slot_or_item) == TYPE_INT:
		slot = slot_or_item
		item = equipped_items[slot]
	else:
		item = slot_or_item
		slot = find_slot_with_item(item)
	
	if not item or slot == EquipSlot.NONE:
		return ITEM_UNEQUIP_FAIL
	
	# Check if trying to drop a wielded weapon
	if not force and item == wielded_weapon:
		return ITEM_UNEQUIP_FAIL
	
	var result = unequip_item(slot, force)
	if result != ITEM_UNEQUIP_UNEQUIPPED:
		return result
	
	var drop_pos = calculate_drop_position(direction)
	move_item_to_world(item, drop_pos)
	
	if item.has_method("handle_drop"):
		item.handle_drop(entity)
	
	sync_inventory_action.rpc("drop", get_item_network_id(item), slot, drop_pos)
	
	return ITEM_UNEQUIP_DROPPED

func calculate_drop_position(direction: Vector2) -> Vector2:
	var entity_pos = entity.global_position
	var drop_offset = direction * 32.0
	drop_offset += Vector2(randf_range(-8, 8), randf_range(-8, 8))
	return entity_pos + drop_offset

func move_item_to_world(item, world_position: Vector2):
	var world = entity.get_parent()
	
	if item.get_parent() == entity:
		entity.remove_child(item)
	
	if world and item.get_parent() != world:
		world.add_child(item)
	
	item.global_position = world_position
	show_item_icon(item)

func throw_item_to_position(slot, target_position: Vector2):
	var item = equipped_items[slot]
	if not item:
		return false
	
	# Check if trying to throw a wielded weapon
	if item == wielded_weapon:
		return false
	
	var result = unequip_item(slot)
	if result != ITEM_UNEQUIP_UNEQUIPPED:
		return false
	
	var landing_pos = calculate_throw_landing(item, target_position)
	
	move_item_to_world(item, entity.global_position)
	
	if item.has_method("throw_to_position"):
		await item.throw_to_position(entity, landing_pos)
	else:
		animate_throw(item, landing_pos)
	
	sync_inventory_action.rpc("throw", get_item_network_id(item), slot, landing_pos)
	
	return true

func animate_throw(item, target_position: Vector2):
	var tween = create_tween()
	tween.set_parallel(true)
	
	tween.tween_property(item, "global_position", target_position, 0.3)
	tween.tween_property(item, "rotation", item.rotation + randf_range(-PI/2, PI/2), 0.3)
	
	tween.tween_callback(func(): 
		if item.has_method("on_throw_complete"):
			item.on_throw_complete()
	)

func calculate_throw_landing(item, target_position: Vector2) -> Vector2:
	var weight_class = item.get("w_class")
	var accuracy = 1.0 / (1.0 + (weight_class - 1) * 0.2)
	var max_offset = 32.0 * (1.0 - accuracy)
	
	var offset = Vector2(
		randf_range(-max_offset, max_offset),
		randf_range(-max_offset, max_offset)
	)
	
	return target_position + offset

func use_active_item():
	var item = get_active_item()
	if not item:
		return false
	
	if not is_instance_valid(item):
		equipped_items[active_hand] = null
		emit_signal("inventory_updated")
		return false
	
	# Check if item is a weapon - delegate to weapon handling component
	if is_weapon(item) and weapon_handling_component:
		return weapon_handling_component.handle_weapon_use(item)
	
	var used = false
	
	if item.has_method("use"):
		used = await item.use(entity)
	elif item.has_method("interact"):
		used = await item.interact(entity)
	elif item.has_method("attack_self"):
		used = await item.attack_self(entity)
	
	# Check if item is still in inventory after use
	if used and equipped_items[active_hand] == item:
		# Item was used but still equipped, check if it should be removed
		if not is_instance_valid(item) or item.is_in_group("depleted_items"):
			equipped_items[active_hand] = null
			remove_from_lists(item)
			update_slot_visuals(active_hand)
	
	if used:
		sync_inventory_action.rpc("use", get_item_network_id(item), 0, Vector2.ZERO)
	
	emit_signal("inventory_updated")
	return used

func switch_active_hand():
	# Prevent hand switching when wielding a weapon
	if wielded_weapon:
		print("InventorySystem: Can't switch hands while wielding weapon")
		return active_hand
	
	var old_hand = active_hand
	var new_hand = EquipSlot.LEFT_HAND if active_hand == EquipSlot.RIGHT_HAND else EquipSlot.RIGHT_HAND
	active_hand = new_hand
	
	print("InventorySystem: Switched hands from ", old_hand, " to ", new_hand)
	
	emit_signal("active_hand_changed", active_hand)
	sync_inventory_action.rpc("switch_hand", "", active_hand, Vector2.ZERO)
	
	return active_hand

func drop_active_item():
	var drop_direction = Vector2.DOWN
	
	if entity.has_method("get_current_direction"):
		var direction_index = entity.get_current_direction()
		var directions = [
			Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0),
			Vector2(1, -1).normalized(), Vector2(1, 1).normalized(),
			Vector2(-1, 1).normalized(), Vector2(-1, -1).normalized()
		]
		if direction_index < directions.size():
			drop_direction = directions[direction_index]
	
	return drop_item(active_hand, drop_direction)

func can_equip_to_slot(item, slot):
	if not item or not is_instance_valid(item):
		return false
	
	if entity.has_method("has_limb_for_slot"):
		if not entity.has_limb_for_slot(slot):
			return false
	
	if (slot == EquipSlot.LEFT_HAND or slot == EquipSlot.RIGHT_HAND):
		# Check if item has pickupable property and if it's true
		if "pickupable" in item:
			return item.pickupable
		else:
			return false
	
	if "valid_slots" in item and item.valid_slots is Array:
		return slot in item.valid_slots
	
	if "equip_slot_flags" in item:
		var slot_bit = get_slot_bit(slot)
		if slot_bit != 0:
			return (item.equip_slot_flags & slot_bit) != 0
	
	return false

func hide_item_icon(item):
	if not item:
		return
	
	# Add to hidden items list
	if item not in hidden_items:
		hidden_items.append(item)
	
	# Hide all possible visual components
	var icon_node = item.get_node_or_null("Icon")
	if icon_node:
		icon_node.visible = false
	
	# Ensure position is zero
	item.position = Vector2.ZERO
	
	# Set item flag if available
	if item.has_method("set_flag") and "ItemFlags" in item:
		item.set_flag("item_flags", item.ItemFlags.IN_INVENTORY, true)
	
	# Call item's hide method if it exists
	if item.has_method("hide_item"):
		item.hide_item()

func show_item_icon(item):
	if not item:
		return
	
	# Remove from hidden items list
	if item in hidden_items:
		hidden_items.erase(item)
	
	# Show all possible visual components
	var icon_node = item.get_node_or_null("Icon")
	if icon_node:
		icon_node.visible = true
	
	# Unset item flag if available
	if item.has_method("set_flag") and "ItemFlags" in item:
		item.set_flag("item_flags", item.ItemFlags.IN_INVENTORY, false)
	
	# Call item's show method if it exists
	if item.has_method("show_item"):
		item.show_item()

# Force hide item for non-inventory situations (like magazines in guns)
func force_hide_item(item):
	"""Force hide an item even if it's not in inventory slots"""
	if not item:
		return
	
	# Add to hidden items list
	if item not in hidden_items:
		hidden_items.append(item)
	
	# Hide all visual components
	hide_item_icon(item)
	
	# Ensure it stays at zero position
	item.position = Vector2.ZERO
	
	# Parent it to the entity if not already
	if item.get_parent() != entity:
		if item.get_parent():
			item.get_parent().remove_child(item)
		entity.add_child(item)

# Force show item
func force_show_item(item):
	"""Force show an item"""
	if not item:
		return
	
	# Remove from hidden items list
	if item in hidden_items:
		hidden_items.erase(item)
	
	# Show all visual components
	show_item_icon(item)

func update_slot_visuals(slot):
	if not entity:
		return
	
	match slot:
		EquipSlot.BACK:
			if entity.has_method("update_inv_back"):
				entity.update_inv_back()
		EquipSlot.WEAR_MASK:
			if entity.has_method("update_inv_wear_mask"):
				entity.update_inv_wear_mask()
			wear_mask_update()
		EquipSlot.HANDCUFFED:
			if entity.has_method("update_inv_handcuffed"):
				entity.update_inv_handcuffed()
		EquipSlot.BELT:
			if entity.has_method("update_inv_belt"):
				entity.update_inv_belt()
		EquipSlot.WEAR_ID:
			if entity.has_method("update_inv_wear_id"):
				entity.update_inv_wear_id()
			if entity.has_method("get_visible_name"):
				entity.name = entity.get_visible_name()
		EquipSlot.EARS:
			if entity.has_method("update_inv_ears"):
				entity.update_inv_ears()
		EquipSlot.GLASSES:
			if entity.has_method("update_inv_glasses"):
				entity.update_inv_glasses()
		EquipSlot.GLOVES:
			if entity.has_method("update_inv_gloves"):
				entity.update_inv_gloves()
		EquipSlot.HEAD:
			if entity.has_method("update_inv_head"):
				entity.update_inv_head()
			var item = equipped_items[EquipSlot.HEAD]
			if item and item.get("inv_hide_flags") & HIDEFACE:
				if entity.has_method("get_visible_name"):
					entity.name = entity.get_visible_name()
		EquipSlot.SHOES:
			if entity.has_method("update_inv_shoes"):
				entity.update_inv_shoes()
		EquipSlot.WEAR_SUIT:
			if entity.has_method("update_inv_wear_suit"):
				entity.update_inv_wear_suit()
		EquipSlot.W_UNIFORM:
			if entity.has_method("update_inv_w_uniform"):
				entity.update_inv_w_uniform()
		EquipSlot.L_STORE, EquipSlot.R_STORE:
			if entity.has_method("update_inv_pockets"):
				entity.update_inv_pockets()
		EquipSlot.S_STORE:
			if entity.has_method("update_inv_s_store"):
				entity.update_inv_s_store()
		EquipSlot.LEFT_HAND:
			if entity.has_method("update_inv_l_hand"):
				entity.update_inv_l_hand()
		EquipSlot.RIGHT_HAND:
			if entity.has_method("update_inv_r_hand"):
				entity.update_inv_r_hand()

func wear_mask_update():
	if not entity:
		return
	
	var item = equipped_items[EquipSlot.WEAR_MASK]
	if item:
		var hide_flags = item.get("inv_hide_flags")
		
		if hide_flags & HIDEFACE:
			if entity.has_method("get_visible_name"):
				entity.name = entity.get_visible_name()
		
		if hide_flags & (HIDEALLHAIR|HIDETOPHAIR|HIDELOWHAIR):
			if entity.has_method("update_hair"):
				entity.update_hair()
		
		if hide_flags & HIDEEARS:
			if entity.has_method("update_inv_ears"):
				entity.update_inv_ears()
		
		if hide_flags & HIDEEYES:
			if entity.has_method("update_inv_glasses"):
				entity.update_inv_glasses()

func sort_item(item):
	if not item:
		return
	
	var item_type = item.entity_type
	
	match item_type:
		"gun":
			if not gun_list.has(item):
				gun_list.append(item)
		"melee":
			if not melee_list.has(item):
				melee_list.append(item)
		"ammo":
			if not ammo_list.has(item):
				ammo_list.append(item)
		"medical":
			if not medical_list.has(item):
				medical_list.append(item)
			sort_medical_item(item)
		"grenade":
			if not grenade_list.has(item):
				grenade_list.append(item)
		"engineering":
			if not engineering_list.has(item):
				engineering_list.append(item)
		"food":
			if not food_list.has(item):
				food_list.append(item)
	
	if item.get("force") > 0:
		if not melee_list.has(item):
			melee_list.append(item)

func sort_medical_item(item):
	if not "damage_types" in item:
		return
	
	for damage_type in item.damage_types:
		match damage_type:
			"brute":
				if not brute_list.has(item):
					brute_list.append(item)
			"burn":
				if not burn_list.has(item):
					burn_list.append(item)
			"tox":
				if not tox_list.has(item):
					tox_list.append(item)
			"oxy":
				if not oxy_list.has(item):
					oxy_list.append(item)
			"clone":
				if not clone_list.has(item):
					clone_list.append(item)
			"pain":
				if not pain_list.has(item):
					pain_list.append(item)

func remove_from_lists(item):
	if not item:
		return
	
	gun_list.erase(item)
	melee_list.erase(item)
	ammo_list.erase(item)
	medical_list.erase(item)
	grenade_list.erase(item)
	engineering_list.erase(item)
	food_list.erase(item)
	brute_list.erase(item)
	burn_list.erase(item)
	tox_list.erase(item)
	oxy_list.erase(item)
	clone_list.erase(item)
	pain_list.erase(item)

# Utility function to check if item is a weapon
func is_weapon(item: Node) -> bool:
	if not item:
		return false
	
	# Check entity type
	if item.entity_type == "gun":
		return true
	
	return false

@rpc("any_peer", "call_local", "reliable")
func sync_inventory_action(action: String, item_id: String, slot_or_hand: int, position: Vector2):
	var item = find_item_by_network_id(item_id) if item_id != "" else null
	
	match action:
		"pick_up":
			if item:
				if item.get_parent() != entity:
					var world = item.get_parent()
					if world:
						world.remove_child(item)
					entity.add_child(item)
				# Ensure no offset when carried
				item.position = Vector2.ZERO
				equipped_items[slot_or_hand] = item
				hide_item_icon(item)
				sort_item(item)
				update_slot_visuals(slot_or_hand)
		
		"equip":
			if item:
				if item.get_parent() != entity:
					if item.get_parent():
						item.get_parent().remove_child(item)
					entity.add_child(item)
				# Ensure no offset when carried
				item.position = Vector2.ZERO
				equipped_items[slot_or_hand] = item
				hide_item_icon(item)
				sort_item(item)
				update_slot_visuals(slot_or_hand)
		
		"unequip":
			if item:
				show_item_icon(item)
				remove_from_lists(item)
				equipped_items[slot_or_hand] = null
				update_slot_visuals(slot_or_hand)
		
		"drop":
			if item:
				move_item_to_world(item, position)
				if item.has_method("handle_drop"):
					item.handle_drop(entity)
		
		"throw":
			if item:
				move_item_to_world(item, entity.global_position)
				if item.has_method("throw_to_position"):
					item.throw_to_position(entity, position)
				else:
					animate_throw(item, position)
		
		"use":
			if item and item.has_method("show_use_effect"):
				item.show_use_effect()
		
		"switch_hand":
			# Only switch if not wielding weapon
			if not wielded_weapon:
				active_hand = slot_or_hand
				emit_signal("active_hand_changed", active_hand)
	
	emit_signal("inventory_updated")

func get_active_item():
	return equipped_items[active_hand]

func get_inactive_item():
	var inactive_hand = EquipSlot.LEFT_HAND if active_hand == EquipSlot.RIGHT_HAND else EquipSlot.RIGHT_HAND
	return equipped_items[inactive_hand]

func get_item_in_slot(slot):
	return equipped_items.get(slot)

func find_slot_with_item(item):
	for slot in equipped_items:
		if equipped_items[slot] == item:
			return slot
	return EquipSlot.NONE

func get_slot_bit(slot):
	match slot:
		EquipSlot.WEAR_SUIT:
			return ItemSlotFlags.ITEM_SLOT_OCLOTHING
		EquipSlot.W_UNIFORM:
			return ItemSlotFlags.ITEM_SLOT_ICLOTHING
		EquipSlot.GLOVES:
			return ItemSlotFlags.ITEM_SLOT_GLOVES
		EquipSlot.GLASSES:
			return ItemSlotFlags.ITEM_SLOT_EYES
		EquipSlot.EARS:
			return ItemSlotFlags.ITEM_SLOT_EARS
		EquipSlot.WEAR_MASK:
			return ItemSlotFlags.ITEM_SLOT_MASK
		EquipSlot.HEAD:
			return ItemSlotFlags.ITEM_SLOT_HEAD
		EquipSlot.SHOES:
			return ItemSlotFlags.ITEM_SLOT_FEET
		EquipSlot.WEAR_ID:
			return ItemSlotFlags.ITEM_SLOT_ID
		EquipSlot.BELT:
			return ItemSlotFlags.ITEM_SLOT_BELT
		EquipSlot.BACK:
			return ItemSlotFlags.ITEM_SLOT_BACK
		EquipSlot.R_STORE:
			return ItemSlotFlags.ITEM_SLOT_R_POCKET
		EquipSlot.L_STORE:
			return ItemSlotFlags.ITEM_SLOT_L_POCKET
		EquipSlot.S_STORE:
			return ItemSlotFlags.ITEM_SLOT_SUITSTORE
		EquipSlot.HANDCUFFED:
			return ItemSlotFlags.ITEM_SLOT_HANDCUFF
		EquipSlot.LEFT_HAND:
			return ItemSlotFlags.ITEM_SLOT_L_HAND
		EquipSlot.RIGHT_HAND:
			return ItemSlotFlags.ITEM_SLOT_R_HAND
	return 0

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
	
	# Check equipped items first
	for slot in equipped_items:
		var item = equipped_items[slot]
		if item and get_item_network_id(item) == network_id:
			return item
	
	# Check hidden items
	for item in hidden_items:
		if item and get_item_network_id(item) == network_id:
			return item
	
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

func get_inventory_state() -> Dictionary:
	var state = {}
	for slot in equipped_items:
		var item = equipped_items[slot]
		if item:
			state[slot] = {
				"item_id": get_item_network_id(item),
				"item_name": item.get("obj_name", "Unknown"),
				"position": item.position
			}
		else:
			state[slot] = null
	return state

func validate_inventory_state():
	for slot in equipped_items:
		var item = equipped_items[slot]
		if item:
			if not is_instance_valid(item):
				equipped_items[slot] = null
				update_slot_visuals(slot)
				emit_signal("inventory_updated")
				continue
			
			if item.is_in_group("depleted_items"):
				equipped_items[slot] = null
				remove_from_lists(item)
				update_slot_visuals(slot)
				emit_signal("inventory_updated")
				continue
			
			if item.get_parent() != entity:
				if item.get_parent():
					item.get_parent().remove_child(item)
				entity.add_child(item)
			
			# Check icon visibility instead of item visibility
			var icon_node = item.get_node_or_null("Icon")
			if icon_node and icon_node.visible:
				icon_node.visible = false
			
			if item.position != Vector2.ZERO:
				item.position = Vector2.ZERO
	
	# Also validate hidden items
	for i in range(hidden_items.size() - 1, -1, -1):
		var item = hidden_items[i]
		if not is_instance_valid(item):
			hidden_items.remove_at(i)

func clean_destroyed_items():
	var items_removed = false
	
	for slot in equipped_items:
		var item = equipped_items[slot]
		if item:
			if not is_instance_valid(item) or item.is_in_group("depleted_items"):
				equipped_items[slot] = null
				if is_instance_valid(item):
					remove_from_lists(item)
				update_slot_visuals(slot)
				items_removed = true
			else:
				# Ensure carried items maintain correct position relative to entity
				if item.position != Vector2.ZERO:
					item.position = Vector2.ZERO
	
	# Clean up hidden items list
	for i in range(hidden_items.size() - 1, -1, -1):
		var item = hidden_items[i]
		if not is_instance_valid(item):
			hidden_items.remove_at(i)
		elif item in hidden_items:
			# Ensure hidden items stay hidden and at correct position
			hide_item_icon(item)
			if item.position != Vector2.ZERO:
				item.position = Vector2.ZERO
	
	if items_removed:
		emit_signal("inventory_updated")

# Public getters for weapon handling
func can_switch_hands() -> bool:
	return wielded_weapon == null

func is_wielding_weapon() -> bool:
	return wielded_weapon != null

func get_wielded_weapon() -> Node:
	return wielded_weapon
