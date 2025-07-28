extends Node
class_name GrabPullComponent

## Handles grabbing and pulling mechanics for entities with full multiplayer synchronization

#region CONSTANTS
const GRAB_UPGRADE_MIN_TIME: float = 1.0
const RESIST_CHECK_INTERVAL: float = 0.5
const GRAB_DAMAGE_INTERVAL: float = 1.0
#endregion

#region ENUMS
enum GrabState {
	NONE,
	PASSIVE,
	AGGRESSIVE,
	NECK,
	KILL
}
#endregion

#region SIGNALS
signal grab_state_changed(new_state: int, grabbed_entity: Node)
signal pulling_changed(pulled_entity: Node)
signal being_pulled_changed(pulling_entity: Node)
signal movement_modifier_changed(modifier: float)
signal grab_released(entity: Node)
signal pull_released(entity: Node)
signal grab_resisted(entity: Node)
signal grab_broken(entity: Node)
#endregion

#region PROPERTIES
# Core references
var controller: Node = null
var sensory_system = null
var audio_system = null
var tile_occupancy_system = null
var world = null

# Grab state - Synced properties
@export var grab_state: int = GrabState.NONE : set = _set_grab_state
@export var grabbing_entity: Node = null : set = _set_grabbing_entity
@export var grabbed_by: Node = null : set = _set_grabbed_by
@export var pulling_entity: Node = null : set = _set_pulling_entity
@export var pulled_by_entity: Node = null : set = _set_pulled_by_entity

# Non-synced local properties
var grab_time: float = 0.0
var grab_resist_progress: float = 0.0
var original_move_time: float = 0.0
var is_dragging_entity: bool = false

# Pull configuration
var has_pull_flag: bool = true
var pull_speed_modifier: float = 0.7
var drag_slowdown_modifier: float = 0.6

# Entity stats
var dexterity: float = 10.0
var mass: float = 70.0

# Multiplayer properties
var is_local_player: bool = false
var peer_id: int = 1
#endregion

#region MULTIPLAYER SETTERS
func _set_grab_state(value: int):
	var old_state = grab_state
	grab_state = value
	if old_state != grab_state:
		emit_signal("grab_state_changed", grab_state, grabbing_entity)

func _set_grabbing_entity(value: Node):
	grabbing_entity = value

func _set_grabbed_by(value: Node):
	grabbed_by = value

func _set_pulling_entity(value: Node):
	var old_entity = pulling_entity
	pulling_entity = value
	if old_entity != pulling_entity:
		emit_signal("pulling_changed", pulling_entity)

func _set_pulled_by_entity(value: Node):
	var old_entity = pulled_by_entity
	pulled_by_entity = value
	if old_entity != pulled_by_entity:
		emit_signal("being_pulled_changed", pulled_by_entity)
#endregion

func initialize(init_data: Dictionary):
	"""Initialize the grab/pull component"""
	controller = init_data.get("controller")
	world = init_data.get("world")
	sensory_system = init_data.get("sensory_system")
	audio_system = init_data.get("audio_system")
	tile_occupancy_system = init_data.get("tile_occupancy_system")
	is_local_player = init_data.get("is_local_player", false)
	peer_id = init_data.get("peer_id", 1)

func _physics_process(delta: float):
	"""Process grab and pull effects"""
	if grabbing_entity:
		process_grab_effects(delta)
	
	if pulled_by_entity:
		process_being_pulled(delta)
	
	if pulling_entity:
		process_pulling(delta)

#region MULTIPLAYER SYNC METHODS
@rpc("any_peer", "call_local", "reliable")
func sync_grab_start(target_network_id: String, initial_state: int):
	"""Sync grab start across all clients"""
	if not is_multiplayer_authority():
		var target = find_entity_by_network_id(target_network_id)
		if target:
			_apply_grab_start(target, initial_state)

@rpc("any_peer", "call_local", "reliable")
func sync_grab_upgrade(new_state: int):
	"""Sync grab upgrade across all clients"""
	if not is_multiplayer_authority():
		_apply_grab_upgrade(new_state)

@rpc("any_peer", "call_local", "reliable")
func sync_grab_release():
	"""Sync grab release across all clients"""
	if not is_multiplayer_authority():
		_apply_grab_release()

@rpc("any_peer", "call_local", "reliable")
func sync_pull_start(target_network_id: String):
	"""Sync pull start across all clients"""
	if not is_multiplayer_authority():
		var target = find_entity_by_network_id(target_network_id)
		if target:
			_apply_pull_start(target)

@rpc("any_peer", "call_local", "reliable")
func sync_pull_stop():
	"""Sync pull stop across all clients"""
	if not is_multiplayer_authority():
		_apply_pull_stop()

@rpc("any_peer", "call_local", "reliable")
func sync_grab_effects(effect_type: String, target_network_id: String, additional_data: Dictionary = {}):
	"""Sync grab effects (audio, visual, damage) across all clients"""
	var target = find_entity_by_network_id(target_network_id)
	if not target:
		return
	
	match effect_type:
		"grab_sound":
			if audio_system:
				audio_system.play_positioned_sound("grab", controller.position, 0.3)
		"tighten_sound":
			if audio_system:
				var volume = 0.3 + (0.1 * additional_data.get("state", 1))
				audio_system.play_positioned_sound("grab_tighten", controller.position, volume)
		"choke_sound":
			if audio_system:
				audio_system.play_positioned_sound("choke", controller.position, 0.5)
		"release_sound":
			if audio_system:
				audio_system.play_positioned_sound("release", controller.position, 0.2)
		"resistance_break":
			var target_name = get_entity_name(target)
			show_message(target_name + " breaks free from " + get_entity_name(controller) + "'s grab!")

@rpc("any_peer", "call_local", "reliable")
func sync_grabbed_entity_position(target_network_id: String, new_position: Vector2i, move_time: float):
	"""Sync grabbed entity position across all clients"""
	var target = find_entity_by_network_id(target_network_id)
	if not target:
		return
	
	var target_controller = get_entity_controller(target)
	if not target_controller or not target_controller.movement_component:
		return
	
	# Apply synchronized movement
	var movement_comp = target_controller.movement_component
	movement_comp.current_move_time = move_time
	movement_comp.start_external_move_to(new_position)
#endregion

#region GRAB MECHANICS
func grab_entity(target: Node, initial_state: int = GrabState.PASSIVE) -> bool:
	"""Start grabbing an entity - Authority only"""
	if not is_multiplayer_authority():
		return false
	
	if not can_grab_entity(target):
		return false
	
	if grabbing_entity != null:
		if grabbing_entity == target:
			return upgrade_grab()
		else:
			show_message("You're already grabbing " + get_entity_name(grabbing_entity) + "!")
			return false
	
	# Perform grab locally
	_apply_grab_start(target, initial_state)
	
	# Sync to all clients
	var target_id = get_entity_network_id(target)
	if target_id != "":
		sync_grab_start.rpc(target_id, initial_state)
		sync_grab_effects.rpc("grab_sound", target_id)
	
	return true

func _apply_grab_start(target: Node, initial_state: int):
	"""Apply grab start effects (called on all clients)"""
	grabbing_entity = target
	grab_state = initial_state
	grab_time = 0.0
	grab_resist_progress = 0.0
	
	apply_drag_slowdown(true)
	
	# Notify target
	var target_controller = get_entity_controller(target)
	if target_controller and target_controller.grab_pull_component:
		target_controller.grab_pull_component.set_grabbed_by(controller, grab_state)
	
	# Connect signals for authority
	if is_multiplayer_authority() and target.has_signal("movement_attempt"):
		if not target.is_connected("movement_attempt", _on_grabbed_movement_attempt):
			target.movement_attempt.connect(_on_grabbed_movement_attempt)
	
	# Start pulling for passive grabs
	if grab_state == GrabState.PASSIVE:
		if is_multiplayer_authority():
			pull_entity(target)
	
	# Messages
	var target_name = get_entity_name(target)
	match grab_state:
		GrabState.PASSIVE:
			show_message("You grab " + target_name + " passively.")
		GrabState.AGGRESSIVE:
			show_message("You grab " + target_name + " aggressively!")
		GrabState.NECK:
			show_message("You grab " + target_name + " by the neck!")
		GrabState.KILL:
			show_message("You start strangling " + target_name + "!")

func upgrade_grab() -> bool:
	"""Upgrade grab to next state - Authority only"""
	if not is_multiplayer_authority():
		return false
	
	if not grabbing_entity:
		return false
	
	if grab_state >= GrabState.KILL:
		show_message("You can't tighten your grip any further!")
		return false
	
	if grab_time < GRAB_UPGRADE_MIN_TIME:
		show_message("You need to hold your grip longer before tightening it!")
		return false
	
	# Calculate success chance
	var base_chance = 60.0
	var user_skill = dexterity * 2.0
	var target_resistance = 0.0
	
	if "dexterity" in grabbing_entity:
		target_resistance = grabbing_entity.dexterity * 1.5
	
	# Modifiers
	if "health" in grabbing_entity and "max_health" in grabbing_entity:
		var health_percent = grabbing_entity.health / grabbing_entity.max_health
		target_resistance *= health_percent
	
	if "is_stunned" in grabbing_entity and grabbing_entity.is_stunned:
		target_resistance *= 0.5
	
	if "is_lying" in grabbing_entity and grabbing_entity.is_lying:
		target_resistance *= 0.7
	
	var upgrade_chance = base_chance + user_skill - target_resistance
	upgrade_chance = clamp(upgrade_chance, 10.0, 90.0)
	
	# Roll for success
	if randf() * 100.0 < upgrade_chance:
		var new_state = grab_state + 1
		
		# Apply locally
		_apply_grab_upgrade(new_state)
		
		# Sync to all clients
		sync_grab_upgrade.rpc(new_state)
		
		# Sync appropriate sound effect
		var target_id = get_entity_network_id(grabbing_entity)
		if target_id != "":
			var sound_effect = "choke_sound" if new_state == GrabState.KILL else "tighten_sound"
			sync_grab_effects.rpc(sound_effect, target_id, {"state": new_state})
		
		return true
	else:
		# Failed - chance to fumble
		if randf() * 100.0 < 25.0:
			show_message("You fumble and lose your grip on " + get_entity_name(grabbing_entity) + "!")
			release_grab()
		else:
			show_message("You fail to tighten your grip.")
		
		return false

func _apply_grab_upgrade(new_state: int):
	"""Apply grab upgrade effects (called on all clients)"""
	var old_state = grab_state
	grab_state = new_state
	
	# Stop pulling if upgrading from passive
	if old_state == GrabState.PASSIVE and pulling_entity == grabbing_entity:
		if is_multiplayer_authority():
			stop_pulling()
	
	grab_time = 0.0
	grab_resist_progress = 0.0
	
	# Notify target
	var target_controller = get_entity_controller(grabbing_entity)
	if target_controller and target_controller.grab_pull_component:
		target_controller.grab_pull_component.set_grabbed_by(controller, grab_state)
	
	# Messages
	var target_name = get_entity_name(grabbing_entity)
	match grab_state:
		GrabState.AGGRESSIVE:
			show_message("You tighten your grip on " + target_name + "!")
		GrabState.NECK:
			show_message("You grab " + target_name + " by the neck!")
		GrabState.KILL:
			show_message("You start strangling " + target_name + "!")
	
	apply_grab_escalation_effects(old_state, grab_state)

func release_grab() -> bool:
	"""Release current grab - Authority only"""
	if not is_multiplayer_authority():
		return false
	
	if not grabbing_entity:
		return false
	
	# Apply locally
	_apply_grab_release()
	
	# Sync to all clients
	sync_grab_release.rpc()
	
	# Sync sound effect
	var target_id = get_entity_network_id(grabbing_entity)
	if target_id != "":
		sync_grab_effects.rpc("release_sound", target_id)
	
	return true

func _apply_grab_release():
	"""Apply grab release effects (called on all clients)"""
	if not grabbing_entity:
		return
	
	apply_drag_slowdown(false)
	
	# Stop pulling if we were
	if pulling_entity == grabbing_entity:
		if is_multiplayer_authority():
			stop_pulling()
	
	# Clean up grabbed entity state
	var grabbed_controller = get_entity_controller(grabbing_entity)
	if grabbed_controller:
		if "is_moving" in grabbed_controller:
			grabbed_controller.is_moving = false
		if "move_progress" in grabbed_controller:
			grabbed_controller.move_progress = 0.0
		if grabbed_controller.movement_component:
			grabbed_controller.position = tile_to_world(grabbed_controller.movement_component.get_current_tile_position())
	
	# Disconnect signals (authority only)
	if is_multiplayer_authority() and grabbing_entity.has_signal("movement_attempt"):
		if grabbing_entity.is_connected("movement_attempt", _on_grabbed_movement_attempt):
			grabbing_entity.disconnect("movement_attempt", _on_grabbed_movement_attempt)
	
	# Notify target
	var target_controller = get_entity_controller(grabbing_entity)
	if target_controller and target_controller.grab_pull_component:
		target_controller.grab_pull_component.set_grabbed_by(null, GrabState.NONE)
	
	# Message
	var target_name = get_entity_name(grabbing_entity)
	show_message("You release your grab on " + target_name + ".")
	
	# Reset state
	var old_entity = grabbing_entity
	grab_state = GrabState.NONE
	grabbing_entity = null
	grab_time = 0.0
	grab_resist_progress = 0.0
	
	emit_signal("grab_released", old_entity)

func process_grab_effects(delta: float):
	"""Process ongoing grab effects - Authority only for damage/effects"""
	if not grabbing_entity or not is_instance_valid(grabbing_entity):
		if is_multiplayer_authority():
			release_grab()
		return
	
	grab_time += delta
	
	# Check if still adjacent (authority only)
	if is_multiplayer_authority() and not is_adjacent_to(grabbing_entity):
		release_grab()
		return
	
	# Apply effects based on state (authority only for damage)
	if is_multiplayer_authority():
		match grab_state:
			GrabState.PASSIVE:
				# No negative effects
				pass
				
			GrabState.AGGRESSIVE:
				# Movement restriction
				if grabbing_entity.has_method("apply_movement_modifier"):
					grabbing_entity.apply_movement_modifier(0.8)
				
			GrabState.NECK:
				# Breathing difficulty
				if grabbing_entity.has_method("add_stamina_loss"):
					grabbing_entity.add_stamina_loss(15 * delta)
				
				if grabbing_entity.has_method("set_muffled"):
					grabbing_entity.set_muffled(true, 1.5)
				
				if grabbing_entity.has_method("apply_movement_modifier"):
					grabbing_entity.apply_movement_modifier(0.5)
				
			GrabState.KILL:
				# Damage over time
				if fmod(grab_time, GRAB_DAMAGE_INTERVAL) < delta:
					if grabbing_entity.has_method("take_damage"):
						grabbing_entity.take_damage(3.0, "asphyxiation")
					
					if audio_system:
						audio_system.play_positioned_sound("choking", controller.position, 0.4)
				
				if grabbing_entity.has_method("set_muffled"):
					grabbing_entity.set_muffled(true, 3.0)
				
				if grabbing_entity.has_method("reduce_oxygen"):
					grabbing_entity.reduce_oxygen(30 * delta)
				
				if grabbing_entity.has_method("apply_movement_modifier"):
					grabbing_entity.apply_movement_modifier(0.2)
		
		# Process resistance
		var target_controller = get_entity_controller(grabbing_entity)
		if target_controller and target_controller.has_method("is_resisting") and target_controller.is_resisting():
			process_grab_resistance(delta)

func process_grab_resistance(delta: float):
	"""Process grab resistance attempts - Authority only"""
	grab_resist_progress += delta
	
	# Calculate threshold
	var resist_threshold = 2.0 + (grab_state * 1.5)
	
	if "dexterity" in controller:
		resist_threshold += controller.dexterity * 0.2
	
	if "dexterity" in grabbing_entity:
		grab_resist_progress += (grabbing_entity.dexterity * 0.1) * delta
	
	# Check if broken free
	if grab_resist_progress >= resist_threshold:
		# Sync resistance break to all clients
		var target_id = get_entity_network_id(grabbing_entity)
		if target_id != "":
			sync_grab_effects.rpc("resistance_break", target_id)
		
		emit_signal("grab_broken", grabbing_entity)
		release_grab()
	else:
		# Progress message
		if fmod(grab_resist_progress, 0.5) < delta:
			emit_signal("grab_resisted", grabbing_entity)
#endregion

#region PULL MECHANICS
func pull_entity(target: Node) -> bool:
	"""Start pulling an entity - Authority only"""
	if not is_multiplayer_authority():
		return false
	
	if not has_pull_flag or not can_pull_entity(target):
		return false
	
	if pulling_entity != null:
		stop_pulling()
	
	# Apply locally
	_apply_pull_start(target)
	
	# Sync to all clients
	var target_id = get_entity_network_id(target)
	if target_id != "":
		sync_pull_start.rpc(target_id)
	
	return true

func _apply_pull_start(target: Node):
	"""Apply pull start effects (called on all clients)"""
	pulling_entity = target
	
	# Notify target
	var target_controller = get_entity_controller(target)
	if target_controller and target_controller.grab_pull_component:
		target_controller.grab_pull_component.set_pulled_by(controller)
	
	show_message("You start pulling " + get_entity_name(target) + ".")
	update_pull_movespeed()

func stop_pulling():
	"""Stop pulling current entity - Authority only"""
	if not is_multiplayer_authority():
		return
	
	if not pulling_entity:
		return
	
	# Apply locally
	_apply_pull_stop()
	
	# Sync to all clients
	sync_pull_stop.rpc()

func _apply_pull_stop():
	"""Apply pull stop effects (called on all clients)"""
	if not pulling_entity:
		return
	
	# Notify target
	var target_controller = get_entity_controller(pulling_entity)
	if target_controller and target_controller.grab_pull_component:
		target_controller.grab_pull_component.set_pulled_by(null)
	
	var old_entity = pulling_entity
	pulling_entity = null
	
	update_pull_movespeed()
	
	show_message("You stop pulling " + get_entity_name(old_entity) + ".")
	emit_signal("pull_released", old_entity)

func start_synchronized_follow(grabber_previous_position: Vector2i, grabber_move_time: float):
	"""Start synchronized movement for grabbed entity - Authority only"""
	if not is_multiplayer_authority():
		return
	
	if not grabbing_entity or not is_instance_valid(grabbing_entity):
		return
	
	var grabbed_controller = get_entity_controller(grabbing_entity)
	if not grabbed_controller or not grabbed_controller.movement_component:
		return
	
	var grabbed_current_pos = get_entity_tile_position(grabbing_entity)
	
	# Don't move if already at target position
	if grabbed_current_pos == grabber_previous_position:
		return
	
	# If grabbed entity is currently moving, complete their movement first
	if grabbed_controller.movement_component.is_moving:
		grabbed_controller.movement_component.complete_movement()
	
	# Validate target position
	var target_position = grabber_previous_position
	if not is_valid_target_position(target_position):
		target_position = find_closest_valid_position(target_position, grabbed_current_pos)
		if target_position == Vector2i(-9999, -9999):
			show_message("Lost grip due to obstruction!")
			release_grab()
			return
	
	# Sync grabbed entity movement to all clients
	var target_id = get_entity_network_id(grabbing_entity)
	if target_id != "":
		sync_grabbed_entity_position.rpc(target_id, target_position, grabber_move_time)
	
	# Apply locally
	_apply_grabbed_entity_movement(grabbing_entity, target_position, grabber_move_time)

func _apply_grabbed_entity_movement(target: Node, target_position: Vector2i, move_time: float):
	"""Apply grabbed entity movement (called on all clients)"""
	var target_controller = get_entity_controller(target)
	if not target_controller or not target_controller.movement_component:
		return
	
	var movement_comp = target_controller.movement_component
	
	# Set the exact same movement timing
	movement_comp.current_move_time = move_time
	movement_comp.start_external_move_to(target_position)
	
	# Visual feedback (reduced frequency)
	if is_multiplayer_authority() and sensory_system and randf() < 0.2:
		var grabber_name = controller.entity_name if "entity_name" in controller else controller.name
		var target_sensory = target_controller.get_node_or_null("SensorySystem")
		if target_sensory:
			target_sensory.display_message("You are dragged by " + grabber_name + "!")
#endregion

#region HELPER FUNCTIONS
func find_entity_by_network_id(network_id: String) -> Node:
	"""Find entity by network ID"""
	if network_id == "":
		return null
	
	# Handle player targets
	if network_id.begins_with("player_"):
		var peer_id = network_id.split("_")[1].to_int()
		return find_player_by_peer_id(peer_id)
	
	# Handle path-based targets
	if network_id.begins_with("/"):
		return get_node_or_null(network_id)
	
	# Try to find by network_id meta
	var entities = get_tree().get_nodes_in_group("networkable")
	for entity in entities:
		if entity.has_meta("network_id") and entity.get_meta("network_id") == network_id:
			return entity
		if entity.has_method("get_network_id") and entity.get_network_id() == network_id:
			return entity
	
	return null

func find_player_by_peer_id(peer_id: int) -> Node:
	"""Find player by peer ID"""
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player.has_meta("peer_id") and player.get_meta("peer_id") == peer_id:
			return player
		if "peer_id" in player and player.peer_id == peer_id:
			return player
	
	return null

func get_entity_network_id(entity: Node) -> String:
	"""Get network ID for entity"""
	if not entity:
		return ""
	
	# Try to get a unique identifier for the entity
	if entity.has_method("get_network_id"):
		return entity.get_network_id()
	elif "peer_id" in entity:
		return "player_" + str(entity.peer_id)
	elif entity.has_meta("network_id"):
		return entity.get_meta("network_id")
	else:
		return entity.get_path()

func tile_to_world(tile_pos: Vector2i) -> Vector2:
	"""Convert tile coordinates to world position"""
	return Vector2((tile_pos.x * 32) + 16, (tile_pos.y * 32) + 16)

func can_grab_entity(target: Node) -> bool:
	"""Check if can grab target"""
	if not target:
		return false
	
	# Check entity type
	if "entity_type" in target:
		if target.entity_type != "character" and target.entity_type != "mob":
			if target.entity_type == "item":
				if "w_class" in target and target.w_class > 3:
					show_message("That's too big to grab!")
					return false
			else:
				return false
	
	# Check flags
	if "no_grab" in target and target.no_grab:
		show_message("You can't grab that!")
		return false
	
	if "grabbed_by" in target and target.grabbed_by != null and target.grabbed_by != controller:
		show_message("Someone else is already grabbing them!")
		return false
	
	if not is_adjacent_to(target):
		show_message("You need to be closer to grab that!")
		return false
	
	if "mass" in target and target.mass > mass * 2:
		show_message("They're too heavy for you to grab!")
		return false
	
	return true

func can_pull_entity(target: Node) -> bool:
	"""Check if can pull target"""
	if not target or target == controller:
		return false
	
	if "no_pull" in target and target.no_pull:
		return false
	
	if not is_adjacent_to(target):
		show_message("You need to be closer to pull that!")
		return false
	
	return true

func is_adjacent_to(target: Node) -> bool:
	"""Check if adjacent to target"""
	if controller.movement_component:
		return controller.movement_component.is_adjacent_to(target)
	return false

func is_entity_grabbed_by_me(entity: Node) -> bool:
	"""Check if entity is grabbed by this controller"""
	if grabbing_entity == entity:
		return true
	
	if "grabbed_by" in entity and entity.grabbed_by == controller:
		return true
	
	var entity_controller = get_entity_controller(entity)
	if entity_controller and "grabbed_by" in entity_controller and entity_controller.grabbed_by == controller:
		return true
	
	return false

func get_entity_controller(entity: Node) -> Node:
	"""Get movement controller for entity"""
	if entity.has_method("get_current_tile_position"):
		return entity
	elif entity.has_node("GridMovementController"):
		return entity.get_node("GridMovementController")
	return null

func get_entity_tile_position(entity: Node) -> Vector2i:
	"""Get tile position of entity"""
	if controller.movement_component:
		return controller.movement_component.get_entity_tile_position(entity)
	return Vector2i.ZERO

func is_valid_target_position(position: Vector2i) -> bool:
	"""Check if the target position is valid for the grabbed entity to move to"""
	if not world:
		return false
	
	var z_level = controller.current_z_level if controller else 0
	
	# Check if it's a valid tile
	if world.has_method("is_valid_tile") and not world.is_valid_tile(position, z_level):
		return false
	
	# Check for walls
	if world.has_method("is_wall_at") and world.is_wall_at(position, z_level):
		return false
	
	# Check for closed doors
	if world.has_method("is_closed_door_at") and world.is_closed_door_at(position, z_level):
		return false
	
	# Check for other dense entities (except the grabber)
	if tile_occupancy_system and tile_occupancy_system.has_method("has_dense_entity_at"):
		if tile_occupancy_system.has_dense_entity_at(position, z_level, grabbing_entity):
			var entity_at_pos = tile_occupancy_system.get_entity_at(position, z_level)
			# Allow if the entity at position is the grabber
			if entity_at_pos != controller:
				return false
	
	return true

func find_closest_valid_position(target_pos: Vector2i, current_pos: Vector2i) -> Vector2i:
	"""Find the closest valid position to the target"""
	var offsets = [
		Vector2i(0, 0),   # Target position itself
		Vector2i(0, -1),  # North
		Vector2i(1, 0),   # East  
		Vector2i(0, 1),   # South
		Vector2i(-1, 0),  # West
		Vector2i(1, -1),  # Northeast
		Vector2i(1, 1),   # Southeast
		Vector2i(-1, 1),  # Southwest
		Vector2i(-1, -1)  # Northwest
	]
	
	# Sort by distance from current position
	offsets.sort_custom(func(a, b): 
		var pos_a = target_pos + a
		var pos_b = target_pos + b
		var dist_a = (pos_a - current_pos).length_squared()
		var dist_b = (pos_b - current_pos).length_squared()
		return dist_a < dist_b
	)
	
	for offset in offsets:
		var test_pos = target_pos + offset
		if is_valid_target_position(test_pos):
			return test_pos
	
	return Vector2i(-9999, -9999)  # Invalid position marker

func apply_drag_slowdown(enable: bool):
	"""Apply or remove drag slowdown"""
	if enable and not is_dragging_entity:
		is_dragging_entity = true
		emit_signal("movement_modifier_changed", drag_slowdown_modifier)
		show_message("You slow down while dragging " + get_entity_name(grabbing_entity) + ".")
	elif not enable and is_dragging_entity:
		is_dragging_entity = false
		emit_signal("movement_modifier_changed", 1.0)
		show_message("You move normally again.")

func apply_grab_escalation_effects(old_state: int, new_state: int):
	"""Apply effects when grab escalates"""
	if not grabbing_entity or not is_instance_valid(grabbing_entity):
		return
	
	match new_state:
		GrabState.AGGRESSIVE:
			if grabbing_entity.has_method("toggle_lying"):
				grabbing_entity.toggle_lying()
			elif "is_lying" in grabbing_entity:
				grabbing_entity.is_lying = true
			
		GrabState.NECK:
			if grabbing_entity.has_method("lie_down"):
				grabbing_entity.lie_down(true)
			elif "is_lying" in grabbing_entity:
				grabbing_entity.is_lying = true
			
		GrabState.KILL:
			if grabbing_entity.has_method("lie_down"):
				grabbing_entity.lie_down(true)
			elif "is_lying" in grabbing_entity:
				grabbing_entity.is_lying = true
			
			# Move to same tile
			if controller.movement_component:
				var my_pos = controller.movement_component.current_tile_position
				move_entity_to_position(grabbing_entity, my_pos)
			
			# Layer on top
			if "z_index" in grabbing_entity:
				grabbing_entity.z_index = controller.z_index + 1

func move_entity_to_position(entity: Node, position: Vector2i, animated: bool = true) -> bool:
	"""Move entity to position - uses standard movement system for grabbed entities"""
	if not entity or not is_instance_valid(entity):
		return false
	
	# Use standard movement methods for consistency
	if entity.has_method("move_externally"):
		return entity.move_externally(position, animated, true)
	
	var entity_controller = get_entity_controller(entity)
	if entity_controller and entity_controller.movement_component:
		if entity_controller.movement_component.has_method("move_externally"):
			return entity_controller.movement_component.move_externally(position, animated, true)
	
	return false

func update_pull_movespeed():
	"""Update movement speed based on pulling"""
	if pulling_entity:
		emit_signal("movement_modifier_changed", pull_speed_modifier)
	else:
		emit_signal("movement_modifier_changed", 1.0)

func set_pulled_by(puller: Node):
	"""Set who is pulling this entity"""
	pulled_by_entity = puller

func set_grabbed_by(grabber: Node, state: int):
	"""Set who is grabbing this entity"""
	grabbed_by = grabber
	grab_state = state

func get_entity_name(entity: Node) -> String:
	"""Get display name for entity"""
	if "entity_name" in entity and entity.entity_name != "":
		return entity.entity_name
	elif "name" in entity:
		return entity.name
	else:
		return "that"

func show_message(text: String):
	"""Display message"""
	if sensory_system:
		sensory_system.display_message(text)

func cleanup():
	"""Cleanup when removed"""
	if grabbing_entity:
		release_grab()
	if pulling_entity:
		stop_pulling()

func process_pulling(delta: float):
	"""Process pulling mechanics"""
	if not pulling_entity:
		return
	
	# Check distance
	var pulled_pos = get_entity_tile_position(pulling_entity)
	var my_pos = controller.movement_component.current_tile_position if controller.movement_component else Vector2i.ZERO
	
	var distance = (pulled_pos - my_pos).length()
	
	if distance > 2.0:
		if is_multiplayer_authority():
			stop_pulling()

func process_being_pulled(delta: float):
	"""Process being pulled by someone"""
	if not pulled_by_entity:
		return
	
	var puller_pos = get_entity_tile_position(pulled_by_entity)
	var my_pos = controller.movement_component.get_current_tile_position()
	
	var distance = (puller_pos - my_pos).length()
	
	if distance > 1.5:
		# Try to catch up
		var dir_to_puller = (puller_pos - my_pos).normalized()
		var move_dir = Vector2i(round(dir_to_puller.x), round(dir_to_puller.y))
		
		if controller.movement_component and not controller.movement_component.is_moving and not controller.movement_component.is_stunned:
			controller.movement_component.move_externally(move_dir)

func _on_grabbed_movement_attempt(direction: Vector2i):
	"""Handle when grabbed entity tries to move"""
	if not grabbing_entity:
		return
	
	# Only restrict for aggressive+ grabs
	if grab_state >= GrabState.AGGRESSIVE:
		var restrict_chance = 30 + (grab_state * 20)
		
		if randf() * 100 < restrict_chance:
			if grabbing_entity:
				grabbing_entity.movement_component.complete_movement()
			
			if fmod(grab_time, 1.0) < 0.1:
				var messages = ["holds you in place!", "restricts your movement!", "prevents you from moving!"]
				var msg_index = min(grab_state - 1, messages.size() - 1)
				
				if grabbing_entity:
					grabbing_entity.show_interaction_message(controller.entity_name + " " + messages[msg_index])
#endregion
