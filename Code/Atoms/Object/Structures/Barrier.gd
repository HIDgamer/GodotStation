extends BaseObject
class_name Barrier

# Barrier-specific properties
@export_group("Barrier Settings")
@export var barrier_type: String = "fence"
@export var can_climb_over: bool = true
@export var climb_difficulty: float = 1.0
@export var blocks_movement: bool = true
@export var can_cut_through: bool = true
@export var electrified: bool = false
@export var electrification_damage: float = 15.0

# State tracking
var is_cut: bool = false
var is_open: bool = false  # For curtains and doors
var climb_delay_modifier: float = 1.0

# Visual effects
@export var cut_texture: Texture2D = null
@export var open_texture: Texture2D = null
@export var closed_texture: Texture2D = null

# Signals
signal barrier_cut(user, tool)
signal barrier_climbed(user)
signal barrier_opened(user)
signal barrier_closed(user)
signal electrification_triggered(victim)

@export_group("Interaction Settings")
@export var accepts_entity_drops: bool = false
@export var accepts_item_drops: bool = false
@export var can_hang_items: bool = false
@export var max_hanging_items: int = 3

var hanging_items: Array = []
var entities_against_barrier: Array = []
var is_drop_target_highlighted: bool = false

# Drag-drop detection
var drop_area: Area2D = null

# Signals
signal item_hung_on_barrier(item, user)
signal entity_placed_against_barrier(entity, user)

func _ready():
	super()
	entity_type = "barrier"
	
	setup_collision_properties()
	add_to_group("barriers")
	
	if accepts_item_drops or can_hang_items:
		add_to_group("item_drop_targets")
	
	if accepts_entity_drops:
		add_to_group("entity_drop_targets")
	
	setup_barrier_actions()
	setup_drop_detection()

func setup_drop_detection():
	"""Set up drop detection for barrier interactions"""
	drop_area = Area2D.new()
	drop_area.name = "BarrierDropArea"
	add_child(drop_area)
	
	var drop_shape = CollisionShape2D.new()
	var rect_shape = RectangleShape2D.new()
	rect_shape.size = Vector2(40, 40)
	drop_shape.shape = rect_shape
	drop_area.add_child(drop_shape)
	
	drop_area.area_entered.connect(_on_drop_area_entered)
	drop_area.area_exited.connect(_on_drop_area_exited)

# ENHANCED DRAG-DROP METHODS
func handle_item_drop_on_surface(item: Node, user: Node) -> bool:
	"""Handle dropping an item on the barrier"""
	if can_hang_items and hanging_items.size() < max_hanging_items:
		return hang_item_on_barrier(item, user)
	elif accepts_item_drops:
		return place_item_at_barrier(item, user)
	
	show_user_message(user, "You can't put that there!")
	return false

func handle_entity_drop_on_surface(entity: Node, user: Node) -> bool:
	"""Handle dropping an entity on the barrier"""
	if not accepts_entity_drops:
		return false
	
	# Place entity against the barrier (for cover, hiding, etc.)
	return place_entity_against_barrier(entity, user)

func hang_item_on_barrier(item: Node, user: Node) -> bool:
	"""Hang an item on the barrier (like clothes on a fence)"""
	if hanging_items.size() >= max_hanging_items:
		show_user_message(user, "There's no more room to hang anything!")
		return false
	
	hanging_items.append(item)
	
	# Position item hanging on barrier
	var hang_position = get_hanging_position(hanging_items.size() - 1)
	item.global_position = global_position + hang_position
	
	# Set hanging visual state
	if item.has_method("set_hanging"):
		item.set_hanging(true)
	
	show_user_message(user, "You hang " + get_entity_name(item) + " on " + get_entity_name(self) + ".")
	emit_signal("item_hung_on_barrier", item, user)
	
	return true

func place_item_at_barrier(item: Node, user: Node) -> bool:
	"""Place an item at the base of the barrier"""
	# Simple placement near barrier
	var placement_offset = Vector2(randf_range(-24, 24), randf_range(-24, 24))
	item.global_position = global_position + placement_offset
	
	show_user_message(user, "You place " + get_entity_name(item) + " by " + get_entity_name(self) + ".")
	return true

func place_entity_against_barrier(entity: Node, user: Node) -> bool:
	"""Place an entity against the barrier for cover or concealment"""
	entities_against_barrier.append(entity)
	
	# Position entity against barrier
	entity.global_position = global_position + Vector2(0, 24)  # Slightly offset
	
	# Set entity state for being against barrier
	if entity.has_method("set_against_cover"):
		entity.set_against_cover(self)
	
	show_user_message(user, "You place " + get_entity_name(entity) + " against " + get_entity_name(self) + ".")
	emit_signal("entity_placed_against_barrier", entity, user)
	
	return true

func get_hanging_position(index: int) -> Vector2:
	"""Get position for hanging an item at given index"""
	var spacing = 16.0
	var start_offset = -(hanging_items.size() - 1) * spacing / 2.0
	return Vector2(start_offset + index * spacing, -12.0)

func remove_hanging_item(item: Node, user: Node):
	"""Remove an item that's hanging on the barrier"""
	if item in hanging_items:
		hanging_items.erase(item)
		
		if item.has_method("set_hanging"):
			item.set_hanging(false)
		
		# Try to give to user or drop nearby
		if user and user.item_interaction_component:
			if not user.item_interaction_component.try_pick_up_item(item):
				item.global_position = global_position + Vector2(randf_range(-32, 32), 32)

func highlight_as_drop_target(highlight: bool):
	"""Highlight barrier as valid drop target"""
	if highlight == is_drop_target_highlighted:
		return
	
	is_drop_target_highlighted = highlight
	
	var sprite = get_node_or_null("Icon")
	if sprite:
		if highlight:
			sprite.modulate = Color(1.2, 1.2, 0.8)  # Yellow tint for barriers
		else:
			sprite.modulate = Color.WHITE

# DROP AREA EVENT HANDLERS
func _on_drop_area_entered(area: Area2D):
	var entity = area.get_parent()
	if is_valid_drop_target(entity):
		highlight_as_drop_target(true)

func _on_drop_area_exited(area: Area2D):
	var entity = area.get_parent()
	if is_valid_drop_target(entity):
		highlight_as_drop_target(false)

func is_valid_drop_target(entity: Node) -> bool:
	if not entity or entity == self:
		return false
	
	if not ("is_being_dragged" in entity and entity.is_being_dragged):
		return false
	
	if can_hang_items and "entity_type" in entity and entity.entity_type == "item":
		# Check if item can be hung (clothes, tools, etc.)
		return can_hang_item(entity)
	
	if accepts_item_drops and "entity_type" in entity and entity.entity_type == "item":
		return true
	
	if accepts_entity_drops and "entity_type" in entity and entity.entity_type in ["character", "mob"]:
		return true
	
	return false

func can_hang_item(item: Node) -> bool:
	"""Check if item can be hung on barrier"""
	if hanging_items.size() >= max_hanging_items:
		return false
	
	# Only certain items can be hung
	if "w_class" in item and item.w_class > 3:  # Too big to hang
		return false
	
	var item_name = get_entity_name(item).to_lower()
	var hangable_items = ["clothing", "uniform", "coat", "jacket", "shirt", "pants", "tool", "rope", "chain"]
	
	for hangable in hangable_items:
		if hangable in item_name:
			return true
	
	return item.is_in_group("hangable_items") if item.is_in_group else false

# EXISTING BARRIER FUNCTIONALITY (abbreviated)
func setup_collision_properties():
	if is_cut or is_open:
		can_block_movement = false
	else:
		can_block_movement = blocks_movement

func setup_barrier_actions():
	if can_climb_over:
		actions.append({"name": "Climb Over", "icon": "climb", "method": "climb_barrier"})
	
	if can_hang_items:
		actions.append({"name": "Hang Item", "icon": "hang", "method": "hang_active_item"})

func hang_active_item(user) -> bool:
	"""Hang user's active item on the barrier"""
	if not can_hang_items:
		return false
	
	var active_item = null
	if user.item_interaction_component:
		active_item = user.item_interaction_component.get_active_item()
	
	if not active_item:
		show_user_message(user, "You have nothing to hang!")
		return false
	
	return hang_item_on_barrier(active_item, user)

func get_entity_name(entity: Node) -> String:
	if "entity_name" in entity and entity.entity_name != "":
		return entity.entity_name
	return entity.name if entity else "something"

func show_user_message(user, message: String):
	if user and user.sensory_system:
		user.sensory_system.display_message(message)

# MULTIPLAYER SYNCHRONIZATION
@rpc("any_peer", "call_local", "reliable")
func sync_barrier_state(cut: bool, opened: bool, user_network_id: String):
	var user = find_user_by_network_id(user_network_id)
	is_cut = cut
	is_open = opened
	_update_barrier_state_internal(user)

@rpc("any_peer", "call_local", "reliable")
func sync_climbed(user_network_id: String):
	var user = find_user_by_network_id(user_network_id)
	if user:
		emit_signal("barrier_climbed", user)

@rpc("any_peer", "call_local", "reliable")
func sync_electrification_triggered(victim_network_id: String):
	var victim = find_user_by_network_id(victim_network_id)
	if victim:
		_electrify_victim_internal(victim)

# CLIMBING SYSTEM
func climb_barrier(user) -> bool:
	"""Climb over the barrier"""
	if not can_climb_over or is_cut or is_open:
		show_user_message(user, "You don't need to climb over that!")
		return false
	
	if not can_interact(user):
		return false
	
	# Check for electrification
	if electrified and not is_cut:
		if randf() < 0.8:  # 80% chance to get shocked
			electrify_user(user)
			return false
	
	# Calculate climb time based on difficulty and user stats
	var base_climb_time = 2.0 * climb_difficulty * climb_delay_modifier
	var actual_climb_time = base_climb_time
	
	# Reduce time based on user's agility/fitness
	if user.has_method("get_skill_level"):
		var agility = user.get_skill_level("agility")
		actual_climb_time *= (1.0 - (agility * 0.1))
	
	show_user_message(user, "You start climbing over " + get_entity_name(self) + "...")
	
	# Animate climbing
	var start_pos = user.global_position
	var end_pos = calculate_climb_end_position(user)
	
	# Simple climb animation
	var tween = create_tween()
	tween.tween_property(user, "global_position", end_pos, actual_climb_time)
	
	await tween.finished
	
	show_user_message(user, "You climb over " + get_entity_name(self) + ".")
	emit_signal("barrier_climbed", user)
	
	# Sync across network
	if multiplayer.has_multiplayer_peer():
		sync_climbed.rpc(get_user_network_id(user))
	
	return true

func calculate_climb_end_position(user) -> Vector2:
	"""Calculate where user should end up after climbing"""
	var barrier_direction = Vector2.UP  # Default
	
	# Determine which side of barrier user is on
	var user_to_barrier = (global_position - user.global_position).normalized()
	var climb_direction = -user_to_barrier
	
	return global_position + (climb_direction * 48.0)  # Land on other side

# CUTTING SYSTEM
func cut_barrier(user, tool = null) -> bool:
	"""Cut through the barrier"""
	if not can_cut_through or is_cut:
		return false
	
	# Get cutting tool from user if not provided
	if not tool and user.has_method("get_active_item"):
		tool = user.get_active_item()
	
	if not tool or not can_cut_with_tool(tool):
		show_user_message(user, "You need a cutting tool to cut through " + get_entity_name(self) + "!")
		return false
	
	if not can_interact(user):
		return false
	
	# Check for electrification
	if electrified:
		electrify_user(user)
		return false
	
	# Calculate cutting time based on tool and barrier material
	var cutting_time = get_cutting_time(tool)
	
	show_user_message(user, "You start cutting through " + get_entity_name(self) + " with " + get_entity_name(tool) + "...")
	
	# Play cutting sound
	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager:
		audio_manager.play_positioned_sound("cutting", global_position, 0.6)
	
	# Simulate cutting work
	await get_tree().create_timer(cutting_time).timeout
	
	# Cut the barrier
	is_cut = true
	_update_barrier_state()
	
	show_user_message(user, "You cut through " + get_entity_name(self) + ".")
	emit_signal("barrier_cut", user, tool)
	
	# Sync across network
	if multiplayer.has_multiplayer_peer():
		sync_barrier_state.rpc(is_cut, is_open, get_user_network_id(user))
	
	return true

func can_cut_with_tool(tool) -> bool:
	"""Check if a tool can cut this barrier"""
	if not tool:
		return false
	
	# Check for cutting tools
	if tool.tool_behaviour in ["wirecutters", "saw", "plasma_cutter"]:
		return true
	
	# Check for sharp weapons
	if tool.has_method("get") and tool.get("sharp", false):
		return true
	
	# Check for specific item types
	if tool.is_in_group("cutting_tools"):
		return true
	
	return false

func get_cutting_time(tool) -> float:
	"""Get time required to cut with this tool"""
	var base_time = 5.0
	
	if not tool:
		return base_time
	
	# Faster cutting with better tools
	match tool.tool_behaviour:
		"plasma_cutter":
			return base_time * 0.3
		"saw":
			return base_time * 0.5
		"wirecutters":
			return base_time * 0.7
		_:
			return base_time

# CURTAIN SYSTEM (for curtain-type barriers)
func toggle_curtain(user = null) -> bool:
	"""Toggle curtain open/closed state"""
	if barrier_type != "curtain":
		return false
	
	if is_open:
		return close_curtain(user)
	else:
		return open_curtain(user)

func open_curtain(user = null) -> bool:
	"""Open the curtain"""
	if is_open or barrier_type != "curtain":
		return false
	
	is_open = true
	_update_barrier_state()
	
	show_user_message(user, "You open " + get_entity_name(self) + ".")
	emit_signal("barrier_opened", user)
	
	# Sync across network
	if multiplayer.has_multiplayer_peer():
		sync_barrier_state.rpc(is_cut, is_open, get_user_network_id(user))
	
	return true

func close_curtain(user = null) -> bool:
	"""Close the curtain"""
	if not is_open or barrier_type != "curtain":
		return false
	
	is_open = false
	_update_barrier_state()
	
	show_user_message(user, "You close " + get_entity_name(self) + ".")
	emit_signal("barrier_closed", user)
	
	# Sync across network
	if multiplayer.has_multiplayer_peer():
		sync_barrier_state.rpc(is_cut, is_open, get_user_network_id(user))
	
	return true

# ELECTRIFICATION SYSTEM
func electrify_user(user) -> bool:
	"""Electrify a user who touches the barrier"""
	if not electrified:
		return false
	
	_electrify_victim_internal(user)
	
	# Sync across network
	if multiplayer.has_multiplayer_peer():
		sync_electrification_triggered.rpc(get_user_network_id(user))
	
	return true

func _electrify_victim_internal(victim):
	"""Internal electrification logic"""
	if victim.has_method("take_damage"):
		victim.take_damage(electrification_damage, "energy", "electrical")
	
	if victim.has_method("apply_stun"):
		victim.apply_stun(2.0)
	
	# Visual and audio effects
	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager:
		audio_manager.play_positioned_sound("electric_shock", global_position, 0.8)
	
	# Screen flash for victim
	if victim.has_method("apply_screen_flash"):
		victim.apply_screen_flash(Color.CYAN, 0.5)
	
	show_interaction_message(get_entity_name(victim) + " gets electrocuted by " + get_entity_name(self) + "!")
	emit_signal("electrification_triggered", victim)

func set_electrified(enabled: bool, damage: float = 15.0):
	"""Set electrification state"""
	electrified = enabled
	electrification_damage = damage
	
	if electrified:
		add_to_group("electrified_barriers")
	else:
		remove_from_group("electrified_barriers")
	
	update_appearance()

# STATE MANAGEMENT
func _update_barrier_state(user = null):
	"""Update barrier state after changes"""
	_update_barrier_state_internal(user)

func _update_barrier_state_internal(user = null):
	"""Internal barrier state update"""
	setup_collision_properties()
	update_appearance()

func update_appearance():
	"""Update visual appearance based on state"""
	super.update_appearance()
	
	var sprite = get_node_or_null("Icon")
	if not sprite:
		return
	
	# Update texture based on state
	if is_cut and cut_texture:
		sprite.texture = cut_texture
	elif is_open and open_texture:
		sprite.texture = open_texture
	elif closed_texture:
		sprite.texture = closed_texture
	
	# Update opacity for curtains
	if barrier_type == "curtain":
		if is_open:
			sprite.modulate.a = 0.3
			set_opacity(0)  # Remove vision blocking when open
		else:
			sprite.modulate.a = 1.0
			if blocks_vision:
				set_opacity(1)

# INTERACTION OVERRIDES
func attack_hand(user, params = null) -> bool:
	"""Handle hand interactions"""
	var intent = get_user_intent(user)
	
	match intent:
		0: # HELP
			if barrier_type == "curtain":
				return toggle_curtain(user)
			elif can_climb_over:
				return await climb_barrier(user)
		3: # HARM
			if electrified and not is_cut:
				electrify_user(user)
				return true
	
	return super.attack_hand(user, params)

func attackby(item, user, params = null) -> bool:
	"""Handle item interactions"""
	if not item or not user:
		return false
	
	# Handle cutting
	if can_cut_with_tool(item):
		return await cut_barrier(user, item)
	
	# Handle repair for cut barriers
	if is_cut and item.has_method("can_repair_barrier"):
		return await repair_barrier(user, item)
	
	return super.attackby(item, user, params)

func repair_barrier(user, repair_tool) -> bool:
	"""Repair a cut barrier"""
	if not is_cut:
		return false
	
	show_user_message(user, "You start repairing " + get_entity_name(self) + " with " + get_entity_name(repair_tool) + "...")
	
	await get_tree().create_timer(8.0).timeout
	
	is_cut = false
	_update_barrier_state()
	
	show_user_message(user, "You repair " + get_entity_name(self) + ".")
	
	# Sync across network
	if multiplayer.has_multiplayer_peer():
		sync_barrier_state.rpc(is_cut, is_open, get_user_network_id(user))
	
	return true

# UTILITY METHODS
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
