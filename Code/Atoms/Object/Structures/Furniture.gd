extends BaseObject
class_name Furniture

# Furniture-specific properties
@export_group("Furniture Settings")
@export var furniture_type: String = "generic"
@export var can_buckle: bool = false
@export var buckle_lying: int = 0  # 0 = sitting, 90 = lying
@export var comfort_value: int = 0
@export var max_buckled_mobs: int = 1
@export var stacking_limit: int = 1
@export var can_rotate: bool = true
@export var foldable: bool = false
@export var folded_item_scene: PackedScene = null

# State tracking
var buckled_mobs: Array = []
var stacked_items: Array = []
var current_stack_size: int = 1
var is_folded: bool = false

# Signals
signal mob_buckled(mob)
signal mob_unbuckled(mob)
signal furniture_rotated(new_direction)
signal furniture_folded(user)
signal furniture_unfolded(user)
signal furniture_stacked(item)
signal furniture_unstacked(item)

func _ready():
	super()
	entity_type = "furniture"
	
	if can_buckle:
		add_to_group("buckle_furniture")
	
	if foldable:
		add_to_group("foldable_furniture")
	
	setup_furniture_interactions()

func setup_furniture_interactions():
	"""Set up furniture-specific interactions"""
	if can_rotate:
		var rotate_action = {
			"name": "Rotate",
			"icon": "rotate",
			"method": "rotate_furniture"
		}
		actions.append(rotate_action)
	
	if foldable:
		var fold_action = {
			"name": "Fold",
			"icon": "fold", 
			"method": "fold_furniture"
		}
		actions.append(fold_action)

# MULTIPLAYER SYNCHRONIZATION
@rpc("any_peer", "call_local", "reliable")
func sync_buckle_mob(mob_network_id: String, buckle: bool):
	var mob = find_mob_by_network_id(mob_network_id)
	if mob:
		if buckle:
			_buckle_mob_internal(mob)
		else:
			_unbuckle_mob_internal(mob)

@rpc("any_peer", "call_local", "reliable")
func sync_furniture_rotated(new_dir: int):
	_rotate_internal(new_dir)

@rpc("any_peer", "call_local", "reliable")
func sync_furniture_folded(user_network_id: String, fold: bool):
	var user = find_user_by_network_id(user_network_id)
	if user:
		if fold:
			_fold_internal(user)
		else:
			_unfold_internal(user)

# BUCKLE SYSTEM
func buckle_mob(mob, user = null) -> bool:
	"""Buckle a mob to this furniture"""
	if not can_buckle or buckled_mobs.size() >= max_buckled_mobs:
		return false
	
	if mob in buckled_mobs:
		return false
	
	if not can_interact(user if user else mob):
		return false
	
	_buckle_mob_internal(mob)
	
	# Sync across network
	if multiplayer.has_multiplayer_peer():
		sync_buckle_mob.rpc(get_mob_network_id(mob), true)
	
	return true

func _buckle_mob_internal(mob):
	"""Internal buckle logic"""
	buckled_mobs.append(mob)
	
	# Position mob on furniture
	if mob.get_parent() != get_parent():
		var old_parent = mob.get_parent()
		old_parent.remove_child(mob)
		get_parent().add_child(mob)
	
	mob.global_position = global_position
	
	# Set mob orientation
	if buckle_lying > 0:
		mob.set_lying(true)
	else:
		mob.set_lying(false)
	
	# Apply furniture effects
	if mob.has_method("set_buckled"):
		mob.set_buckled(self)
	
	if comfort_value > 0 and mob.has_method("add_comfort"):
		mob.add_comfort(comfort_value)
	
	emit_signal("mob_buckled", mob)
	
	var mob_name = get_entity_name(mob)
	var user_name = get_entity_name(mob)
	show_interaction_message(user_name + " sits on " + get_entity_name(self) + ".")

func unbuckle_mob(mob, user = null) -> bool:
	"""Unbuckle a mob from this furniture"""
	if mob not in buckled_mobs:
		return false
	
	_unbuckle_mob_internal(mob)
	
	# Sync across network
	if multiplayer.has_multiplayer_peer():
		sync_buckle_mob.rpc(get_mob_network_id(mob), false)
	
	return true

func _unbuckle_mob_internal(mob):
	"""Internal unbuckle logic"""
	buckled_mobs.erase(mob)
	
	# Remove furniture effects
	if mob.has_method("set_buckled"):
		mob.set_buckled(null)
	
	if comfort_value > 0 and mob.has_method("remove_comfort"):
		mob.remove_comfort(comfort_value)
	
	# Reset mob position slightly
	var offset = Vector2(randf_range(-16, 16), randf_range(-16, 16))
	mob.global_position += offset
	
	emit_signal("mob_unbuckled", mob)
	
	var mob_name = get_entity_name(mob)
	show_interaction_message(mob_name + " gets up from " + get_entity_name(self) + ".")

func unbuckle_all_mobs():
	"""Unbuckle all mobs from this furniture"""
	var mobs_to_unbuckle = buckled_mobs.duplicate()
	for mob in mobs_to_unbuckle:
		unbuckle_mob(mob)

# ROTATION SYSTEM
func _rotate_internal(new_dir: int):
	"""Internal rotation logic"""
	rotation_degrees = new_dir
	
	# Rotate buckled mobs with furniture
	for mob in buckled_mobs:
		if mob.has_method("set_dir"):
			mob.set_dir(new_dir)
	
	emit_signal("furniture_rotated", new_dir)

# FOLDING SYSTEM
func fold_furniture(user) -> bool:
	"""Fold the furniture into an item"""
	if not foldable or is_folded or not folded_item_scene:
		return false
	
	if buckled_mobs.size() > 0:
		show_user_message(user, "You can't fold " + get_entity_name(self) + " while someone is using it!")
		return false
	
	_fold_internal(user)
	
	# Sync across network
	if multiplayer.has_multiplayer_peer():
		sync_furniture_folded.rpc(get_user_network_id(user), true)
	
	return true

func _fold_internal(user):
	"""Internal folding logic"""
	is_folded = true
	
	# Create folded item
	var folded_item = folded_item_scene.instantiate()
	get_parent().add_child(folded_item)
	folded_item.global_position = global_position
	
	# Set up folded item properties
	if folded_item.has_method("set_source_furniture"):
		folded_item.set_source_furniture(get_scene_file_path())
	
	# Try to give to user
	if user and user.has_method("try_pick_up_item"):
		user.try_pick_up_item(folded_item)
	
	emit_signal("furniture_folded", user)
	show_user_message(user, "You fold up " + get_entity_name(self) + ".")
	
	# Remove self
	queue_free()

# STACKING SYSTEM (for chairs, etc.)
func stack_item(item, user = null) -> bool:
	"""Stack a similar item on this furniture"""
	if stacked_items.size() >= stacking_limit - 1:
		return false
	
	if not can_stack_item(item):
		return false
	
	stacked_items.append(item)
	current_stack_size += 1
	
	# Move item to be child of this furniture
	if item.get_parent():
		item.get_parent().remove_child(item)
	add_child(item)
	item.position = Vector2(0, -8 * stacked_items.size())
	item.visible = true
	
	emit_signal("furniture_stacked", item)
	update_appearance()
	
	if user:
		show_user_message(user, "You stack " + get_entity_name(item) + " on " + get_entity_name(self) + ".")
	
	return true

func unstack_item(user = null):
	"""Remove top item from stack"""
	if stacked_items.size() == 0:
		return null
	
	var item = stacked_items.pop_back()
	current_stack_size -= 1
	
	# Move item back to world
	remove_child(item)
	get_parent().add_child(item)
	item.global_position = global_position + Vector2(randf_range(-16, 16), randf_range(-16, 16))
	
	# Try to give to user
	if user and user.has_method("try_pick_up_item"):
		user.try_pick_up_item(item)
	
	emit_signal("furniture_unstacked", item)
	update_appearance()
	
	if user:
		show_user_message(user, "You take " + get_entity_name(item) + " from the stack.")
	
	return item

func can_stack_item(item) -> bool:
	"""Check if item can be stacked on this furniture"""
	if not item.has_method("get_furniture_type"):
		return false
	
	return item.get_furniture_type() == furniture_type

# INTERACTION OVERRIDES
func attack_hand(user, params = null) -> bool:
	"""Handle hand interactions"""
	var intent = get_user_intent(user)
	
	match intent:
		0: # HELP
			if can_buckle and buckled_mobs.size() == 0:
				return buckle_mob(user, user)
			elif buckled_mobs.size() > 0 and user in buckled_mobs:
				return unbuckle_mob(user, user)
			elif stacked_items.size() > 0:
				unstack_item(user)
				return true
		1: # DISARM
			if buckled_mobs.size() > 0:
				var first_mob = buckled_mobs[0]
				if first_mob != user:
					return unbuckle_mob(first_mob, user)
		2: # GRAB
			if foldable and buckled_mobs.size() == 0:
				return fold_furniture(user)
		3: # HARM
			return super.attack_hand(user, params)
	
	return super.attack_hand(user, params)

func attackby(item, user, params = null) -> bool:
	"""Handle item interactions"""
	if not item or not user:
		return false
	
	# Handle stacking
	if can_stack_item(item) and user.has_method("drop_held_item"):
		if stack_item(item, user):
			user.drop_held_item()
			return true
	
	return super.attackby(item, user, params)

# DESTRUCTION HANDLING
func obj_destruction(damage_amount: float, damage_type: int, damage_flag: String, attacker = null):
	"""Handle furniture destruction"""
	# Unbuckle all mobs first
	unbuckle_all_mobs()
	
	# Drop stacked items
	while stacked_items.size() > 0:
		unstack_item()
	
	super.obj_destruction(damage_amount, damage_type, damage_flag, attacker)

func update_appearance():
	"""Update visual appearance based on state"""
	super.update_appearance()
	
	# Update stack appearance
	if current_stack_size > 1:
		# Could add visual indicators for stacked items
		pass

# UTILITY METHODS
func get_furniture_type() -> String:
	return furniture_type

func is_occupied() -> bool:
	return buckled_mobs.size() > 0

func get_mob_network_id(mob) -> String:
	"""Get network ID for mob synchronization"""
	if not mob:
		return ""
	
	if mob.has_method("get_network_id"):
		return mob.get_network_id()
	elif "peer_id" in mob:
		return "mob_" + str(mob.peer_id)
	else:
		return mob.get_path()

func find_mob_by_network_id(network_id: String):
	"""Find mob by network ID"""
	if network_id == "":
		return null
	
	if network_id.begins_with("mob_"):
		var peer_id_str = network_id.split("_")[1]
		var peer_id_val = peer_id_str.to_int()
		return find_mob_by_peer_id(peer_id_val)
	
	if network_id.begins_with("/"):
		return get_node_or_null(network_id)
	
	return null

func find_mob_by_peer_id(peer_id_val: int):
	"""Find mob by peer ID"""
	var mobs = get_tree().get_nodes_in_group("characters")
	for mob in mobs:
		if mob.has_meta("peer_id") and mob.get_meta("peer_id") == peer_id_val:
			return mob
		if "peer_id" in mob and mob.peer_id == peer_id_val:
			return mob
	
	return null

func get_user_network_id(user) -> String:
	"""Get network ID for user"""
	return get_mob_network_id(user)

func find_user_by_network_id(network_id: String):
	"""Find user by network ID"""
	return find_mob_by_network_id(network_id)
