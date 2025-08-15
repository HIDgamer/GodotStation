extends BaseObject
class_name StorageContainer

# Storage-specific properties
@export_group("Storage Settings")
@export var storage_type: String = "generic"
@export var storage_capacity: int = 30
@export var max_items: int = 50
@export var can_lock: bool = false
@export var welded: bool = false
@export var opened: bool = false
@export var secure_storage: bool = false
@export var required_access: Array[String] = []

# Sounds
@export var open_sound: AudioStream = null
@export var close_sound: AudioStream = null
@export var lock_sound: AudioStream = null
@export var unlock_sound: AudioStream = null

# Security
var locked: bool = false
var access_code: String = ""
var broken: bool = false
var security_level: int = 0

# Storage tracking
var stored_items: Array = []
var current_capacity: int = 0

# Signals
signal storage_opened(user)
signal storage_closed(user)
signal storage_locked(user)
signal storage_unlocked(user)
signal item_stored(item, user)
signal item_retrieved(item, user)
signal storage_welded(user)
signal storage_unwelded(user)

func _ready():
	super()
	entity_type = "storage"
	
	if secure_storage:
		add_to_group("secure_storage")
	
	if can_lock:
		add_to_group("lockable_storage")
	
	setup_storage_actions()

func setup_storage_actions():
	"""Set up storage-specific actions"""
	var open_action = {
		"name": "Open/Close",
		"icon": "storage",
		"method": "toggle_storage"
	}
	actions.append(open_action)
	
	if can_lock:
		var lock_action = {
			"name": "Lock/Unlock", 
			"icon": "lock",
			"method": "toggle_lock"
		}
		actions.append(lock_action)

# MULTIPLAYER SYNCHRONIZATION
@rpc("any_peer", "call_local", "reliable")
func sync_storage_state(is_opened: bool, is_locked: bool, is_welded: bool):
	opened = is_opened
	locked = is_locked
	welded = is_welded
	update_appearance()

@rpc("any_peer", "call_local", "reliable")
func sync_item_stored(item_network_id: String, user_network_id: String):
	var item = find_item_by_network_id(item_network_id)
	var user = find_user_by_network_id(user_network_id)
	if item:
		_store_item_internal(item, user)

@rpc("any_peer", "call_local", "reliable")
func sync_item_retrieved(item_network_id: String, user_network_id: String):
	var item = find_item_by_network_id(item_network_id)
	var user = find_user_by_network_id(user_network_id)
	if item:
		_retrieve_item_internal(item, user)

# CORE STORAGE FUNCTIONALITY
func toggle_storage(user = null) -> bool:
	"""Toggle storage open/closed state"""
	if welded:
		show_user_message(user, get_entity_name(self) + " is welded shut!")
		return false
	
	if locked and secure_storage:
		if not check_access(user):
			show_user_message(user, "Access denied.")
			return false
	
	if opened:
		return close_storage(user)
	else:
		return open_storage(user)

func open_storage(user = null) -> bool:
	"""Open the storage container"""
	if opened or welded:
		return false
	
	if locked and not check_access(user):
		return false
	
	opened = true
	
	if open_sound:
		play_audio(open_sound, -5)
	
	emit_signal("storage_opened", user)
	
	if user:
		show_user_message(user, "You open " + get_entity_name(self) + ".")
		show_storage_interface(user)
	
	sync_storage_state_network()
	update_appearance()
	return true

func close_storage(user = null) -> bool:
	"""Close the storage container"""
	if not opened:
		return false
	
	# Auto-store nearby items
	if storage_type in ["locker", "closet", "crate"]:
		auto_store_nearby_items()
	
	opened = false
	
	if close_sound:
		play_audio(close_sound, -5)
	
	emit_signal("storage_closed", user)
	
	if user:
		show_user_message(user, "You close " + get_entity_name(self) + ".")
		hide_storage_interface(user)
	
	sync_storage_state_network()
	update_appearance()
	return true

func auto_store_nearby_items():
	"""Automatically store items in the same tile"""
	var world = get_parent()
	if not world:
		return
	
	for child in world.get_children():
		if child == self or child.global_position.distance_to(global_position) > 32:
			continue
		
		if child.is_in_group("items") and child.pickupable:
			if can_store_item(child):
				store_item(child)

func store_item(item, user = null) -> bool:
	"""Store an item in the container"""
	if not can_store_item(item):
		return false
	
	_store_item_internal(item, user)
	
	# Sync across network
	if multiplayer.has_multiplayer_peer():
		sync_item_stored.rpc(get_item_network_id(item), get_user_network_id(user))
	
	return true

func _store_item_internal(item, user = null):
	"""Internal store item logic"""
	stored_items.append(item)
	current_capacity += item.w_class if "w_class" in item else 1
	
	# Move item to be child of storage
	if item.get_parent():
		item.get_parent().remove_child(item)
	add_child(item)
	item.position = Vector2.ZERO
	item.visible = false
	
	# Remove from inventory if equipped
	if item.has_method("_remove_from_inventory"):
		item._remove_from_inventory()
	
	emit_signal("item_stored", item, user)
	
	if user:
		show_user_message(user, "You put " + get_entity_name(item) + " in " + get_entity_name(self) + ".")

func retrieve_item(item, user = null) -> bool:
	"""Retrieve an item from the container"""
	if item not in stored_items:
		return false
	
	_retrieve_item_internal(item, user)
	
	# Sync across network
	if multiplayer.has_multiplayer_peer():
		sync_item_retrieved.rpc(get_item_network_id(item), get_user_network_id(user))
	
	return true

func _retrieve_item_internal(item, user = null):
	"""Internal retrieve item logic"""
	stored_items.erase(item)
	current_capacity -= item.w_class if "w_class" in item else 1
	
	# Move item back to world
	remove_child(item)
	get_parent().add_child(item)
	item.visible = true
	
	# Position near storage or give to user
	if user:
		if user.has_method("try_pick_up_item"):
			if not user.try_pick_up_item(item):
				item.global_position = global_position + Vector2(randf_range(-16, 16), randf_range(-16, 16))
		else:
			item.global_position = global_position + Vector2(randf_range(-16, 16), randf_range(-16, 16))
	else:
		item.global_position = global_position + Vector2(randf_range(-16, 16), randf_range(-16, 16))
	
	emit_signal("item_retrieved", item, user)
	
	if user:
		show_user_message(user, "You take " + get_entity_name(item) + " from " + get_entity_name(self) + ".")

func can_store_item(item) -> bool:
	"""Check if an item can be stored"""
	if not item or not item.pickupable:
		return false
	
	if not opened and storage_type != "auto":
		return false
	
	var item_size = item.w_class if "w_class" in item else 1
	if current_capacity + item_size > storage_capacity:
		return false
	
	if stored_items.size() >= max_items:
		return false
	
	return true

# SECURITY SYSTEM
func toggle_lock(user = null) -> bool:
	"""Toggle lock state"""
	if not can_lock or welded:
		return false
	
	if locked:
		return unlock_storage(user)
	else:
		return lock_storage(user)

func lock_storage(user = null) -> bool:
	"""Lock the storage container"""
	if locked or not can_lock:
		return false
	
	if not check_access(user):
		show_user_message(user, "Access denied.")
		return false
	
	locked = true
	
	if opened:
		close_storage(user)
	
	if lock_sound:
		play_audio(lock_sound, -5)
	
	emit_signal("storage_locked", user)
	
	if user:
		show_user_message(user, "You lock " + get_entity_name(self) + ".")
	
	sync_storage_state_network()
	update_appearance()
	return true

func unlock_storage(user = null) -> bool:
	"""Unlock the storage container"""
	if not locked:
		return false
	
	if not check_access(user):
		show_user_message(user, "Access denied.")
		return false
	
	locked = false
	
	if unlock_sound:
		play_audio(unlock_sound, -5)
	
	emit_signal("storage_unlocked", user)
	
	if user:
		show_user_message(user, "You unlock " + get_entity_name(self) + ".")
	
	sync_storage_state_network()
	update_appearance()
	return true

func check_access(user) -> bool:
	"""Check if user has access to this storage"""
	if not secure_storage or required_access.size() == 0:
		return true
	
	if not user:
		return false
	
	# Check user's access cards/permissions
	if user.has_method("check_access"):
		return user.check_access(required_access)
	
	# Fallback: check for ID card in user's inventory
	var inventory = user.get_node_or_null("InventorySystem")
	if inventory:
		var id_card = inventory.get_item_in_slot(inventory.EquipSlot.WEAR_ID)
		if id_card and id_card.has_method("check_access"):
			return id_card.check_access(required_access)
	
	return false

# WELDING SYSTEM
func weld_storage(user, welding_tool) -> bool:
	"""Weld the storage container shut"""
	if welded:
		return false
	
	if not welding_tool or not welding_tool.has_method("can_weld"):
		return false
	
	if opened:
		close_storage(user)
	
	welded = true
	
	emit_signal("storage_welded", user)
	
	if user:
		show_user_message(user, "You weld " + get_entity_name(self) + " shut.")
	
	sync_storage_state_network()
	update_appearance()
	return true

func unweld_storage(user, welding_tool) -> bool:
	"""Unweld the storage container"""
	if not welded:
		return false
	
	if not welding_tool or not welding_tool.has_method("can_weld"):
		return false
	
	welded = false
	
	emit_signal("storage_unwelded", user)
	
	if user:
		show_user_message(user, "You unweld " + get_entity_name(self) + ".")
	
	sync_storage_state_network()
	update_appearance()
	return true

# INTERFACE MANAGEMENT
func show_storage_interface(user):
	"""Show storage interface to user"""
	if not user.has_method("show_storage_ui"):
		return
	
	var interface_data = {
		"storage_id": get_instance_id(),
		"storage_name": get_entity_name(self),
		"items": get_item_list(),
		"capacity": current_capacity,
		"max_capacity": storage_capacity
	}
	
	user.show_storage_ui(interface_data)

func hide_storage_interface(user):
	"""Hide storage interface from user"""
	if user.has_method("hide_storage_ui"):
		user.hide_storage_ui(get_instance_id())

func get_item_list() -> Array:
	"""Get list of items for interface"""
	var item_list = []
	
	for item in stored_items:
		var item_data = {
			"id": get_item_network_id(item),
			"name": get_entity_name(item),
			"icon": item.get_texture() if item.has_method("get_texture") else null,
			"size": item.w_class if "w_class" in item else 1
		}
		item_list.append(item_data)
	
	return item_list

# INTERACTION OVERRIDES
func attack_hand(user, params = null) -> bool:
	"""Handle hand interactions"""
	return toggle_storage(user)

func attackby(item, user, params = null) -> bool:
	"""Handle item interactions"""
	if not item or not user:
		return false
	
	# Handle welding
	if item.has_method("can_weld") and item.tool_behaviour == "welder":
		if welded:
			return unweld_storage(user, item)
		else:
			return weld_storage(user, item)
	
	# Handle access cards for security
	if secure_storage and item.has_method("check_access"):
		if locked:
			return unlock_storage(user)
		else:
			return lock_storage(user)
	
	# Handle storage of items
	if opened and can_store_item(item):
		if user.has_method("drop_held_item"):
			user.drop_held_item()
			return store_item(item, user)
	
	return super.attackby(item, user, params)

# DESTRUCTION HANDLING
func obj_destruction(damage_amount: float, damage_type: String, damage_flag: String, attacker = null):
	"""Handle storage destruction"""
	# Dump all contents
	dump_contents()
	
	super.obj_destruction(damage_amount, damage_type, damage_flag, attacker)

func dump_contents():
	"""Dump all stored items"""
	var items_to_dump = stored_items.duplicate()
	
	for item in items_to_dump:
		retrieve_item(item)

func sync_storage_state_network():
	"""Sync storage state across network"""
	if multiplayer.has_multiplayer_peer():
		sync_storage_state.rpc(opened, locked, welded)

func update_appearance():
	"""Update visual appearance based on state"""
	super.update_appearance()
	
	# Update sprite based on storage state
	var sprite = get_node_or_null("Icon")
	if sprite:
		if opened:
			sprite.texture = load(get_opened_texture_path())
		else:
			sprite.texture = load(get_closed_texture_path())
		
		# Add overlay for locked/welded state
		if locked or welded:
			sprite.modulate = Color(0.8, 0.8, 1.0)
		else:
			sprite.modulate = Color.WHITE

func get_opened_texture_path() -> String:
	"""Get texture path for opened state"""
	return "res://Graphics/storage/" + storage_type + "_open.png"

func get_closed_texture_path() -> String:
	"""Get texture path for closed state"""
	return "res://Graphics/storage/" + storage_type + "_closed.png"

# UTILITY METHODS
func get_item_network_id(item) -> String:
	"""Get network ID for item"""
	if not item:
		return ""
	
	if item.has_method("get_network_id"):
		return item.get_network_id()
	elif "network_id" in item:
		return str(item.network_id)
	else:
		return item.get_path()

func find_item_by_network_id(network_id: String):
	"""Find item by network ID"""
	# Check stored items first
	for item in stored_items:
		if get_item_network_id(item) == network_id:
			return item
	
	# Check world items
	var items = get_tree().get_nodes_in_group("items")
	for item in items:
		if get_item_network_id(item) == network_id:
			return item
	
	return null

func get_user_network_id(user) -> String:
	"""Get network ID for user"""
	if not user:
		return ""
	
	if user.has_method("get_network_id"):
		return user.get_network_id()
	elif "peer_id" in user:
		return "player_" + str(user.peer_id)
	else:
		return user.get_path()

func find_user_by_network_id(network_id: String):
	"""Find user by network ID"""
	if network_id == "":
		return null
	
	if network_id.begins_with("player_"):
		var peer_id_str = network_id.split("_")[1]
		var peer_id_val = peer_id_str.to_int()
		var players = get_tree().get_nodes_in_group("players")
		for player in players:
			if "peer_id" in player and player.peer_id == peer_id_val:
				return player
	
	return get_node_or_null(network_id)
