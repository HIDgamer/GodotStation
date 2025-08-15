extends Node
class_name InventorySystem

#region EXPORTS AND CONFIGURATION
@export_group("Inventory Settings")
@export var default_active_hand: EquipSlot = EquipSlot.RIGHT_HAND
@export var network_sync_enabled: bool = true
@export var auto_cleanup_destroyed_items: bool = true
@export var cleanup_interval: float = 1.0

@export_group("Visual Settings")
@export var hide_equipped_icons: bool = true
@export var update_sprite_system: bool = true
@export var show_drop_animations: bool = true

@export_group("Gameplay Features")
@export var enable_item_sorting: bool = true
@export var enable_quick_actions: bool = true
@export var validate_equip_constraints: bool = true
@export var auto_stack_items: bool = false

@export_group("Debug")
@export var debug_mode: bool = false
@export var log_inventory_changes: bool = false
#endregion

#region CONSTANTS
const HIDEFACE = 1
const HIDEALLHAIR = 2
const HIDETOPHAIR = 4
const HIDELOWHAIR = 8
const HIDEEARS = 16
const HIDEEYES = 32
const HIDEJUMPSUIT = 64
const HIDESHOES = 128
const HIDE_EXCESS_HAIR = 256

const ITEM_UNEQUIP_FAIL = 0
const ITEM_UNEQUIP_DROPPED = 1
const ITEM_UNEQUIP_UNEQUIPPED = 2
#endregion

#region ENUMS
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
#endregion

#region SIGNALS
signal inventory_updated()
signal item_equipped(item, slot)
signal item_unequipped(item, slot)
signal active_hand_changed(new_hand)
signal item_pickup_attempted(item, success)
signal item_drop_attempted(item, success)
signal weapon_wielded(weapon, hands_used)
signal weapon_unwielded(weapon)
signal storage_interaction_attempted(storage_item, item, success)
signal storage_opened(storage_item)
signal storage_closed(storage_item)
#endregion

#region PROPERTIES
var entity = null
var equipped_items: Dictionary = {}
var active_hand: int
var hidden_items: Array = []

var weapon_handling_component: Node = null

var wielded_scene_instance = null
var wielded_weapon: Node = null

var gun_list: Array = []
var melee_list: Array = []
var ammo_list: Array = []
var medical_list: Array = []
var grenade_list: Array = []
var engineering_list: Array = []
var food_list: Array = []
var brute_list: Array = []
var burn_list: Array = []
var tox_list: Array = []
var oxy_list: Array = []
var clone_list: Array = []
var pain_list: Array = []

var cleanup_timer: Timer = null
#endregion

#region INITIALIZATION
func _init(owner_entity = null):
	entity = owner_entity
	active_hand = default_active_hand
	
	for slot in EquipSlot.values():
		equipped_items[slot] = null

func _ready():
	if entity == null:
		entity = get_parent()
	
	if entity and entity.get_meta("is_npc", false):
		network_sync_enabled = false
	
	if entity:
		weapon_handling_component = entity.get_node_or_null("WeaponHandlingComponent")
		if weapon_handling_component:
			_connect_weapon_handling_signals()
	
	if auto_cleanup_destroyed_items:
		_setup_cleanup_timer()
	
	if entity.has_signal("position_changed"):
		entity.position_changed.connect(_update_carried_items_position)
	
	if debug_mode:
		print("InventorySystem: Initialized for ", entity.name if entity else "unknown entity")

func _setup_cleanup_timer():
	cleanup_timer = Timer.new()
	cleanup_timer.wait_time = cleanup_interval
	cleanup_timer.autostart = true
	cleanup_timer.timeout.connect(_clean_destroyed_items)
	add_child(cleanup_timer)

func _connect_weapon_handling_signals():
	if not weapon_handling_component:
		return
	
	var signal_connections = [
		["weapon_wielded", "_on_weapon_wielded"],
		["weapon_unwielded", "_on_weapon_unwielded"]
	]
	
	for connection in signal_connections:
		var signal_name = connection[0]
		var method_name = connection[1]
		
		if weapon_handling_component.has_signal(signal_name):
			if not weapon_handling_component.is_connected(signal_name, Callable(self, method_name)):
				weapon_handling_component.connect(signal_name, Callable(self, method_name))
#endregion

#region ITEM PICKUP AND EQUIPPING
func pick_up_item(item):
	if not item or not item.get("pickupable"):
		emit_signal("item_pickup_attempted", item, false)
		return false
	
	if item.is_in_group("depleted_items"):
		emit_signal("item_pickup_attempted", item, false)
		return false
	
	var active_item = equipped_items[active_hand]
	if active_item != null:
		emit_signal("item_pickup_attempted", item, false)
		return false
	
	var world = item.get_parent()
	if world and world != entity:
		world.remove_child(item)
		entity.add_child(item)
	
	item.position = Vector2.ZERO
	
	if item.has_method("picked_up"):
		item.picked_up(entity)
	
	var success = equip_item(item, active_hand)
	
	if success and network_sync_enabled:
		_sync_inventory_action.rpc("pick_up", _get_item_network_id(item), active_hand, Vector2.ZERO)
	
	emit_signal("item_pickup_attempted", item, success)
	return success

func equip_item(item, slot):
	if not item or not _can_equip_to_slot(item, slot):
		return false
	
	var existing_item = equipped_items[slot]
	if existing_item:
		unequip_item(slot)
	
	if item.get_parent() != entity:
		if item.get_parent():
			item.get_parent().remove_child(item)
		entity.add_child(item)
	
	item.position = Vector2.ZERO
	equipped_items[slot] = item
	
	if hide_equipped_icons:
		_hide_item_icon(item)
	
	if enable_item_sorting:
		_sort_item(item)
	
	# Connect to storage signals if this is a storage item
	if "storage_type" in item and item.storage_type != 0:
		connect_to_storage_item(item)
		print("Equipped storage item: ", item.name)
	
	if item.has_method("equipped"):
		item.equipped(entity, slot)
	
	if update_sprite_system:
		_update_slot_visuals(slot)
	
	emit_signal("item_equipped", item, slot)
	emit_signal("inventory_updated")
	
	if network_sync_enabled:
		_sync_inventory_action.rpc("equip", _get_item_network_id(item), slot, Vector2.ZERO)
	
	if log_inventory_changes:
		print("InventorySystem: Equipped ", item.get("obj_name", "item"), " to slot ", slot)
	
	return true

func equip_item_to_hand(item, hand_slot: int):
	if hand_slot != EquipSlot.LEFT_HAND and hand_slot != EquipSlot.RIGHT_HAND:
		return false
	
	if not item or not _can_equip_to_slot(item, hand_slot):
		return false
	
	if wielded_weapon and equipped_items[hand_slot] == wielded_weapon:
		return false
	
	return equip_item(item, hand_slot)
#endregion

#region ITEM UNEQUIPPING AND DROPPING
func unequip_item(slot, force = false):
	var item = equipped_items[slot]
	if not item:
		return ITEM_UNEQUIP_FAIL
	
	if not force and item == wielded_weapon:
		if weapon_handling_component:
			weapon_handling_component.force_unwield()
		return ITEM_UNEQUIP_FAIL
	
	if item.get("trait_nodrop") and not force:
		return ITEM_UNEQUIP_FAIL
	
	if item.has_method("unequipped"):
		item.unequipped(entity, slot)
	
	if hide_equipped_icons:
		_show_item_icon(item)
	
	if enable_item_sorting:
		_remove_from_lists(item)
	
	equipped_items[slot] = null
	
	if update_sprite_system:
		_update_slot_visuals(slot)
	
	emit_signal("item_unequipped", item, slot)
	emit_signal("inventory_updated")
	
	if network_sync_enabled:
		_sync_inventory_action.rpc("unequip", _get_item_network_id(item), slot, Vector2.ZERO)
	
	if log_inventory_changes:
		print("InventorySystem: Unequipped ", item.get("obj_name", "item"), " from slot ", slot)
	
	return ITEM_UNEQUIP_UNEQUIPPED

func drop_item(slot_or_item, direction = Vector2.DOWN, force = false):
	var slot = EquipSlot.NONE
	var item = null
	
	if typeof(slot_or_item) == TYPE_INT:
		slot = slot_or_item
		item = equipped_items[slot]
	else:
		item = slot_or_item
		slot = _find_slot_with_item(item)
	
	if not item or slot == EquipSlot.NONE:
		emit_signal("item_drop_attempted", item, false)
		return ITEM_UNEQUIP_FAIL
	
	var result = unequip_item(slot, force)
	if result != ITEM_UNEQUIP_UNEQUIPPED:
		emit_signal("item_drop_attempted", item, false)
		return result
	
	var drop_pos = _calculate_drop_position(direction)
	_move_item_to_world(item, drop_pos)
	
	if item.has_method("handle_drop"):
		item.handle_drop(entity)
	
	if network_sync_enabled:
		_sync_inventory_action.rpc("drop", _get_item_network_id(item), slot, drop_pos)
	
	emit_signal("item_drop_attempted", item, true)
	return ITEM_UNEQUIP_DROPPED

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
#endregion

#region STORAGE INTERACTION SYSTEM
func interact_with_storage_item(storage_item: Node, held_item: Node = null):
	print("InventorySystem: interact_with_storage_item called")
	print("Storage item: ", storage_item.name if storage_item else "null")
	print("Held item: ", held_item.name if held_item else "null")
	
	if not storage_item or not storage_item.has_method("can_access_storage"):
		print("ERROR: Storage item invalid or missing can_access_storage method")
		return false
	
	if not storage_item.can_access_storage(entity):
		print("ERROR: Cannot access storage")
		emit_signal("storage_interaction_attempted", storage_item, held_item, false)
		return false
	
	if held_item:
		print("Attempting to store item")
		return try_store_item_in_storage(storage_item, held_item)
	else:
		print("Attempting to toggle storage")
		storage_item.toggle_storage(entity)
		return true

func try_store_item_in_storage(storage_item: Node, item: Node) -> bool:
	print("InventorySystem: try_store_item_in_storage")
	if not storage_item.has_method("add_item_to_storage"):
		print("ERROR: Storage item missing add_item_to_storage method")
		emit_signal("storage_interaction_attempted", storage_item, item, false)
		return false
	
	var item_slot = _find_slot_with_item(item)
	if item_slot == EquipSlot.NONE:
		print("ERROR: Item not found in inventory")
		emit_signal("storage_interaction_attempted", storage_item, item, false)
		return false
	
	print("Unequipping item from slot: ", item_slot)
	var unequip_result = unequip_item(item_slot)
	if unequip_result != ITEM_UNEQUIP_UNEQUIPPED:
		print("ERROR: Failed to unequip item")
		emit_signal("storage_interaction_attempted", storage_item, item, false)
		return false
	
	print("Adding item to storage")
	if storage_item.add_item_to_storage(item, entity):
		print("SUCCESS: Item added to storage")
		emit_signal("storage_interaction_attempted", storage_item, item, true)
		return true
	else:
		print("ERROR: Failed to add item to storage, re-equipping")
		equip_item(item, item_slot)
		emit_signal("storage_interaction_attempted", storage_item, item, false)
		return false

func try_retrieve_item_from_storage(storage_item: Node, item: Node) -> bool:
	if not storage_item.has_method("remove_item_from_storage"):
		return false
	
	if not storage_item.remove_item_from_storage(item, entity):
		return false
	
	var target_hand = active_hand
	var current_item = equipped_items[target_hand]
	
	if current_item:
		target_hand = EquipSlot.LEFT_HAND if active_hand == EquipSlot.RIGHT_HAND else EquipSlot.RIGHT_HAND
		current_item = equipped_items[target_hand]
		
		if current_item:
			var drop_pos = _calculate_drop_position(Vector2.DOWN)
			_move_item_to_world(item, drop_pos)
			if item.has_method("handle_drop"):
				item.handle_drop(entity)
			return true
	
	return equip_item(item, target_hand)

func connect_to_storage_item(storage_item: Node):
	print("InventorySystem: Connecting to storage item signals")
	if storage_item.has_signal("storage_opened"):
		if not storage_item.is_connected("storage_opened", _on_storage_item_opened):
			storage_item.connect("storage_opened", _on_storage_item_opened)
			print("Connected to storage_opened signal")
	
	if storage_item.has_signal("storage_closed"):
		if not storage_item.is_connected("storage_closed", _on_storage_item_closed):
			storage_item.connect("storage_closed", _on_storage_item_closed)
			print("Connected to storage_closed signal")

func _on_storage_item_opened(user: Node, storage_item: Node):
	print("InventorySystem: Storage item opened - ", storage_item.name if storage_item else "null")
	emit_signal("storage_opened", storage_item)

func _on_storage_item_closed(user: Node, storage_item: Node):
	print("InventorySystem: Storage item closed - ", storage_item.name if storage_item else "null")
	emit_signal("storage_closed", storage_item)

func get_storage_items_for_slot(slot: int) -> Array:
	var storage_items = []
	var item = equipped_items[slot]
	
	if item and "storage_type" in item and item.storage_type != 0:
		if "storage_items" in item:
			storage_items = item.storage_items.duplicate()
	
	return storage_items

func find_storage_items() -> Array:
	var storage_items = []
	
	for slot in equipped_items:
		var item = equipped_items[slot]
		if item and "storage_type" in item and item.storage_type != 0:
			storage_items.append(item)
	
	return storage_items
#endregion

#region ITEM THROWING
func throw_item_to_position(slot, target_position: Vector2):
	var item = equipped_items[slot]
	if not item:
		return false
	
	var result = unequip_item(slot)
	if result != ITEM_UNEQUIP_UNEQUIPPED:
		return false
	
	var landing_pos = _calculate_throw_landing(item, target_position)
	
	_move_item_to_world(item, entity.global_position)
	
	if item.has_method("throw_to_position"):
		await item.throw_to_position(entity, landing_pos)
	else:
		_animate_throw(item, landing_pos)
	
	if network_sync_enabled:
		_sync_inventory_action.rpc("throw", _get_item_network_id(item), slot, landing_pos)
	
	return true

func _animate_throw(item, target_position: Vector2):
	if not show_drop_animations:
		item.global_position = target_position
		return
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	tween.tween_property(item, "global_position", target_position, 0.3)
	tween.tween_property(item, "rotation", item.rotation + randf_range(-PI/2, PI/2), 0.3)
	
	tween.tween_callback(func(): 
		if item.has_method("on_throw_complete"):
			item.on_throw_complete()
	)

func _calculate_throw_landing(item, target_position: Vector2) -> Vector2:
	var weight_class = item.get("w_class")
	var accuracy = 1.0 / (1.0 + (weight_class - 1) * 0.2)
	var max_offset = 32.0 * (1.0 - accuracy)
	
	var offset = Vector2(
		randf_range(-max_offset, max_offset),
		randf_range(-max_offset, max_offset)
	)
	
	return target_position + offset
#endregion

#region ITEM USAGE AND INTERACTION
func use_active_item():
	var item = get_active_item()
	if not item:
		return false
	
	if not is_instance_valid(item):
		equipped_items[active_hand] = null
		emit_signal("inventory_updated")
		return false
	
	var used = false
	
	if _is_weapon(item) and weapon_handling_component:
		used = weapon_handling_component.handle_weapon_use(item)
	else:
		if item.has_method("use"):
			used = await item.use(entity)
		elif item.has_method("interact"):
			used = await item.interact(entity)
		elif item.has_method("attack_self"):
			used = await item.attack_self(entity)
	
	if used and equipped_items[active_hand] == item:
		if not is_instance_valid(item) or item.is_in_group("depleted_items"):
			equipped_items[active_hand] = null
			if enable_item_sorting:
				_remove_from_lists(item)
			if update_sprite_system:
				_update_slot_visuals(active_hand)
	
	if used and network_sync_enabled:
		_sync_inventory_action.rpc("use", _get_item_network_id(item), 0, Vector2.ZERO)
	
	emit_signal("inventory_updated")
	return used

func switch_active_hand():
	if wielded_weapon:
		return active_hand
	
	var old_hand = active_hand
	var new_hand = EquipSlot.LEFT_HAND if active_hand == EquipSlot.RIGHT_HAND else EquipSlot.RIGHT_HAND
	active_hand = new_hand
	
	emit_signal("active_hand_changed", active_hand)
	
	if network_sync_enabled:
		_sync_inventory_action.rpc("switch_hand", "", active_hand, Vector2.ZERO)
	
	if log_inventory_changes:
		print("InventorySystem: Switched active hand to ", _get_hand_name(active_hand))
	
	return active_hand

func _get_hand_name(hand_slot: int) -> String:
	match hand_slot:
		EquipSlot.LEFT_HAND:
			return "left"
		EquipSlot.RIGHT_HAND:
			return "right"
		_:
			return "unknown"
#endregion

#region WEAPON WIELDING
func _on_weapon_wielded(weapon: Node, hand_slot: int):
	wielded_weapon = weapon
	
	var wielded_scene = preload("res://Scenes/Effects/wielded.tscn")
	if wielded_scene:
		wielded_scene_instance = wielded_scene.instantiate()
		
		var other_hand = EquipSlot.LEFT_HAND if active_hand == EquipSlot.RIGHT_HAND else EquipSlot.RIGHT_HAND
		
		var other_hand_item = equipped_items[other_hand]
		if other_hand_item and other_hand_item != wielded_scene_instance:
			equipped_items[other_hand] = null
			equipped_items[active_hand] = other_hand_item
		
		entity.add_child(wielded_scene_instance)
		wielded_scene_instance.position = Vector2.ZERO
		equipped_items[other_hand] = wielded_scene_instance
		
		if hide_equipped_icons:
			_hide_item_icon(wielded_scene_instance)
		
		if update_sprite_system:
			_update_slot_visuals(other_hand)
	
	emit_signal("weapon_wielded", weapon, 2)
	emit_signal("inventory_updated")

func _on_weapon_unwielded(weapon: Node, hand_slot: int):
	wielded_weapon = null
	
	if wielded_scene_instance and is_instance_valid(wielded_scene_instance):
		for slot in [EquipSlot.LEFT_HAND, EquipSlot.RIGHT_HAND]:
			if equipped_items[slot] == wielded_scene_instance:
				equipped_items[slot] = null
				if update_sprite_system:
					_update_slot_visuals(slot)
				break
		
		if wielded_scene_instance.get_parent() == entity:
			entity.remove_child(wielded_scene_instance)
		wielded_scene_instance.queue_free()
		wielded_scene_instance = null
	
	emit_signal("weapon_unwielded", weapon)
	emit_signal("inventory_updated")
#endregion

#region ITEM VALIDATION
func _can_equip_to_slot(item, slot):
	if not item or not is_instance_valid(item):
		return false
	
	if validate_equip_constraints:
		if entity.has_method("has_limb_for_slot"):
			if not entity.has_limb_for_slot(slot):
				return false
	
	if (slot == EquipSlot.LEFT_HAND or slot == EquipSlot.RIGHT_HAND):
		return item.get("pickupable")
	
	if "valid_slots" in item and item.valid_slots is Array:
		return slot in item.valid_slots
	
	if "equip_slot_flags" in item and item.equip_slot_flags != 0:
		return _check_item_slot_compatibility(item, slot)
	
	return false

func _check_item_slot_compatibility(item, slot):
	var item_flags = item.equip_slot_flags
	
	match slot:
		EquipSlot.LEFT_HAND:
			return (item_flags & 1) != 0
		EquipSlot.RIGHT_HAND:
			return (item_flags & 2) != 0
		EquipSlot.BELT:
			return (item_flags & 8) != 0
		EquipSlot.L_STORE, EquipSlot.R_STORE:
			return (item_flags & 16) != 0
		EquipSlot.W_UNIFORM:
			return (item_flags & 32) != 0
		EquipSlot.WEAR_SUIT:
			return (item_flags & 48) != 0
		EquipSlot.WEAR_MASK:
			return (item_flags & 64) != 0
		EquipSlot.HEAD:
			return (item_flags & 128) != 0
		EquipSlot.SHOES:
			return (item_flags & 256) != 0
		EquipSlot.GLOVES:
			return (item_flags & 512) != 0
		EquipSlot.EARS:
			return (item_flags & 1024) != 0
		EquipSlot.GLASSES:
			return (item_flags & 2048) != 0
		EquipSlot.WEAR_ID:
			return (item_flags & 4096) != 0
		EquipSlot.BACK:
			return (item_flags & 4) != 0
	
	return false

func _is_weapon(item: Node) -> bool:
	if not item:
		return false
	
	if item.get("entity_type") == "gun":
		return true
	
	return false
#endregion

#region VISUAL MANAGEMENT
func _hide_item_icon(item):
	if not item:
		return
	
	if item not in hidden_items:
		hidden_items.append(item)
	
	var icon_node = item.get_node_or_null("Icon")
	if icon_node:
		icon_node.visible = false
	
	item.position = Vector2.ZERO
	
	if item.has_method("set_flag") and "ItemFlags" in item:
		item.set_flag("item_flags", item.ItemFlags.IN_INVENTORY, true)

func _show_item_icon(item):
	if not item:
		return
	
	if item in hidden_items:
		hidden_items.erase(item)
	
	var icon_node = item.get_node_or_null("Icon")
	if icon_node:
		icon_node.visible = true
	
	if item.has_method("set_flag") and "ItemFlags" in item:
		item.set_flag("item_flags", item.ItemFlags.IN_INVENTORY, false)
	
	if item.has_method("show_item"):
		item.show_item()

func _update_slot_visuals(slot):
	if not entity or not update_sprite_system:
		return
	
	match slot:
		EquipSlot.BACK:
			if entity.has_method("update_inv_back"):
				entity.update_inv_back()
		EquipSlot.WEAR_MASK:
			if entity.has_method("update_inv_wear_mask"):
				entity.update_inv_wear_mask()
			_wear_mask_update()
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

func _wear_mask_update():
	if not entity:
		return
	
	var item = equipped_items[EquipSlot.WEAR_MASK]
	if item:
		var hide_flags = item.get("inv_hide_flags", 0)
		
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

func _update_carried_items_position():
	for slot in equipped_items:
		var item = equipped_items[slot]
		if item and is_instance_valid(item):
			item.position = Vector2.ZERO
#endregion

#region ITEM SORTING AND CATEGORIZATION
func _sort_item(item):
	if not item or not enable_item_sorting:
		return
	
	var item_type = item.get("entity_type")
	
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
			_sort_medical_item(item)
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

func _sort_medical_item(item):
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

func _remove_from_lists(item):
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
#endregion

#region NETWORK SYNCHRONIZATION
@rpc("any_peer", "call_local", "reliable")
func _sync_inventory_action(action: String, item_id: String, slot_or_hand: int, position: Vector2):
	var item = _find_item_by_network_id(item_id) if item_id != "" else null
	
	match action:
		"pick_up":
			if item:
				_handle_networked_pickup(item, slot_or_hand)
		"equip":
			if item:
				_handle_networked_equip(item, slot_or_hand)
		"unequip":
			if item:
				_handle_networked_unequip(item, slot_or_hand)
		"drop":
			if item:
				_handle_networked_drop(item, position)
		"throw":
			if item:
				_handle_networked_throw(item, position)
		"use":
			if item and item.has_method("show_use_effect"):
				item.show_use_effect()
		"switch_hand":
			if not wielded_weapon:
				active_hand = slot_or_hand
				emit_signal("active_hand_changed", active_hand)
	
	emit_signal("inventory_updated")

func _handle_networked_pickup(item, slot):
	if item.get_parent() != entity:
		var world = item.get_parent()
		if world:
			world.remove_child(item)
		entity.add_child(item)
	item.position = Vector2.ZERO
	equipped_items[slot] = item
	if hide_equipped_icons:
		_hide_item_icon(item)
	if enable_item_sorting:
		_sort_item(item)
	if update_sprite_system:
		_update_slot_visuals(slot)

func _handle_networked_equip(item, slot):
	if item.get_parent() != entity:
		if item.get_parent():
			item.get_parent().remove_child(item)
		entity.add_child(item)
	item.position = Vector2.ZERO
	equipped_items[slot] = item
	if hide_equipped_icons:
		_hide_item_icon(item)
	if enable_item_sorting:
		_sort_item(item)
	if update_sprite_system:
		_update_slot_visuals(slot)

func _handle_networked_unequip(item, slot):
	if hide_equipped_icons:
		_show_item_icon(item)
	if enable_item_sorting:
		_remove_from_lists(item)
	equipped_items[slot] = null
	if update_sprite_system:
		_update_slot_visuals(slot)

func _handle_networked_drop(item, position):
	_move_item_to_world(item, position)
	if item.has_method("handle_drop"):
		item.handle_drop(entity)

func _handle_networked_throw(item, position):
	_move_item_to_world(item, entity.global_position)
	if item.has_method("throw_to_position"):
		item.throw_to_position(entity, position)
	else:
		_animate_throw(item, position)
#endregion

#region UTILITY FUNCTIONS
func get_active_item():
	return equipped_items[active_hand]

func get_inactive_item():
	var inactive_hand = EquipSlot.LEFT_HAND if active_hand == EquipSlot.RIGHT_HAND else EquipSlot.RIGHT_HAND
	return equipped_items[inactive_hand]

func get_item_in_slot(slot):
	return equipped_items.get(slot)

func _find_slot_with_item(item):
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

func _calculate_drop_position(direction: Vector2) -> Vector2:
	var entity_pos = entity.global_position
	var drop_offset = direction * 32.0
	drop_offset += Vector2(randf_range(-8, 8), randf_range(-8, 8))
	return entity_pos + drop_offset

func _move_item_to_world(item, world_position: Vector2):
	var world = entity.get_parent()
	
	if item.get_parent() == entity:
		entity.remove_child(item)
	
	if world and item.get_parent() != world:
		world.add_child(item)
	
	item.global_position = world_position
	if hide_equipped_icons:
		_show_item_icon(item)

func _get_item_network_id(item) -> String:
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

func _find_item_by_network_id(network_id: String):
	if network_id == "":
		return null
	
	for slot in equipped_items:
		var item = equipped_items[slot]
		if item and _get_item_network_id(item) == network_id:
			return item
	
	for item in hidden_items:
		if item and _get_item_network_id(item) == network_id:
			return item
	
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		world = get_tree().current_scene
	
	if world and world.has_method("get_item_by_network_id"):
		var item = world.get_item_by_network_id(network_id)
		if item:
			return item
	
	var all_items = get_tree().get_nodes_in_group("items")
	for item in all_items:
		if _get_item_network_id(item) == network_id:
			return item
	
	return null

func can_switch_hands() -> bool:
	return wielded_weapon == null

func is_wielding_weapon() -> bool:
	return wielded_weapon != null

func get_wielded_weapon() -> Node:
	return wielded_weapon

func get_inventory_state() -> Dictionary:
	var state = {}
	for slot in equipped_items:
		var item = equipped_items[slot]
		if item:
			state[slot] = {
				"item_id": _get_item_network_id(item),
				"item_name": item.get("obj_name", "Unknown"),
				"position": item.position
			}
		else:
			state[slot] = null
	return state

func get_item_lists() -> Dictionary:
	return {
		"guns": gun_list.duplicate(),
		"melee": melee_list.duplicate(),
		"ammo": ammo_list.duplicate(),
		"medical": medical_list.duplicate(),
		"grenades": grenade_list.duplicate(),
		"engineering": engineering_list.duplicate(),
		"food": food_list.duplicate(),
		"brute_healing": brute_list.duplicate(),
		"burn_healing": burn_list.duplicate(),
		"toxin_healing": tox_list.duplicate(),
		"oxygen_healing": oxy_list.duplicate(),
		"clone_healing": clone_list.duplicate(),
		"pain_healing": pain_list.duplicate()
	}
#endregion

#region MAINTENANCE
func _clean_destroyed_items():
	var items_removed = false
	
	for slot in equipped_items:
		var item = equipped_items[slot]
		if item:
			if not is_instance_valid(item) or item.is_in_group("depleted_items"):
				equipped_items[slot] = null
				if is_instance_valid(item) and enable_item_sorting:
					_remove_from_lists(item)
				if update_sprite_system:
					_update_slot_visuals(slot)
				items_removed = true
			else:
				if item.position != Vector2.ZERO:
					item.position = Vector2.ZERO
	
	for i in range(hidden_items.size() - 1, -1, -1):
		var item = hidden_items[i]
		if not is_instance_valid(item):
			hidden_items.remove_at(i)
		elif item in hidden_items:
			if hide_equipped_icons:
				_hide_item_icon(item)
			if item.position != Vector2.ZERO:
				item.position = Vector2.ZERO
	
	if items_removed:
		emit_signal("inventory_updated")

func validate_inventory_state():
	for slot in equipped_items:
		var item = equipped_items[slot]
		if item:
			if not is_instance_valid(item):
				equipped_items[slot] = null
				if update_sprite_system:
					_update_slot_visuals(slot)
				emit_signal("inventory_updated")
				continue
			
			if item.is_in_group("depleted_items"):
				equipped_items[slot] = null
				if enable_item_sorting:
					_remove_from_lists(item)
				if update_sprite_system:
					_update_slot_visuals(slot)
				emit_signal("inventory_updated")
				continue
			
			if item.get_parent() != entity:
				if item.get_parent():
					item.get_parent().remove_child(item)
				entity.add_child(item)
			
			if hide_equipped_icons:
				var icon_node = item.get_node_or_null("Icon")
				if icon_node and icon_node.visible:
					icon_node.visible = false
			
			if item.position != Vector2.ZERO:
				item.position = Vector2.ZERO
	
	for i in range(hidden_items.size() - 1, -1, -1):
		var item = hidden_items[i]
		if not is_instance_valid(item):
			hidden_items.remove_at(i)
#endregion
