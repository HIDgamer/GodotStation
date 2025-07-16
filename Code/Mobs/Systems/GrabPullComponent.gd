extends Node
class_name GrabPullComponent

## Handles grabbing and pulling mechanics for entities

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

# Grab state
var grab_state: int = GrabState.NONE
var grabbing_entity: Node = null
var grabbed_by: Node = null
var grab_time: float = 0.0
var grab_resist_progress: float = 0.0
var original_move_time: float = 0.0
var is_dragging_entity: bool = false

# Pull state
var pulling_entity: Node = null
var pulled_by_entity: Node = null
var has_pull_flag: bool = true
var pull_speed_modifier: float = 0.7
var drag_slowdown_modifier: float = 0.6

# Configuration
var dexterity: float = 10.0
var mass: float = 70.0
#endregion

func initialize(init_data: Dictionary):
	"""Initialize the grab/pull component"""
	controller = init_data.get("controller")
	sensory_system = init_data.get("sensory_system")
	audio_system = init_data.get("audio_system")
	tile_occupancy_system = init_data.get("tile_occupancy_system")

func _physics_process(delta: float):
	"""Process grab and pull effects"""
	if grabbing_entity:
		process_grab_effects(delta)
	
	if pulled_by_entity:
		process_being_pulled(delta)
	
	if pulling_entity:
		process_pulling(delta)

#region GRAB MECHANICS
func grab_entity(target: Node, initial_state: int = GrabState.PASSIVE) -> bool:
	"""Start grabbing an entity"""
	if not can_grab_entity(target):
		return false
	
	if grabbing_entity != null:
		if grabbing_entity == target:
			return upgrade_grab()
		else:
			show_message("You're already grabbing " + get_entity_name(grabbing_entity) + "!")
			return false
	
	# Set up grab
	grabbing_entity = target
	grab_state = initial_state
	grab_time = 0.0
	grab_resist_progress = 0.0
	
	apply_drag_slowdown(true)
	
	# Notify target
	if target.has_method("set_grabbed_by"):
		target.set_grabbed_by(controller, grab_state)
	elif "grabbed_by" in target:
		target.grabbed_by = controller
	
	# Connect signals
	if target.has_signal("movement_attempt"):
		if not target.is_connected("movement_attempt", _on_grabbed_movement_attempt):
			target.movement_attempt.connect(_on_grabbed_movement_attempt)
	
	# Start pulling for passive grabs
	if grab_state == GrabState.PASSIVE:
		pull_entity(target)
	
	# Effects
	if audio_system:
		audio_system.play_positioned_sound("grab", controller.position, 0.3)
	
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
	
	emit_signal("grab_state_changed", grab_state, target)
	
	return true

func upgrade_grab() -> bool:
	"""Upgrade grab to next state"""
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
		# Success
		var old_state = grab_state
		grab_state += 1
		
		# Stop pulling if upgrading from passive
		if old_state == GrabState.PASSIVE and pulling_entity == grabbing_entity:
			stop_pulling()
		
		grab_time = 0.0
		grab_resist_progress = 0.0
		
		# Notify target
		if grabbing_entity.has_method("set_grabbed_by"):
			grabbing_entity.set_grabbed_by(controller, grab_state)
		
		# Sound
		if audio_system:
			match grab_state:
				GrabState.KILL:
					audio_system.play_positioned_sound("choke", controller.position, 0.5)
				_:
					audio_system.play_positioned_sound("grab_tighten", controller.position, 0.3 + (0.1 * grab_state))
		
		# Messages
		var target_name = get_entity_name(grabbing_entity)
		match grab_state:
			GrabState.AGGRESSIVE:
				show_message("You tighten your grip on " + target_name + "!")
			GrabState.NECK:
				show_message("You grab " + target_name + " by the neck!")
			GrabState.KILL:
				show_message("You start strangling " + target_name + "!")
		
		emit_signal("grab_state_changed", grab_state, grabbing_entity)
		apply_grab_escalation_effects(old_state, grab_state)
		
		return true
	else:
		# Failed - chance to fumble
		if randf() * 100.0 < 25.0:
			show_message("You fumble and lose your grip on " + get_entity_name(grabbing_entity) + "!")
			release_grab()
		else:
			show_message("You fail to tighten your grip.")
		
		return false

func release_grab() -> bool:
	"""Release current grab"""
	if not grabbing_entity:
		return false
	
	apply_drag_slowdown(false)
	
	# Stop pulling if we were
	if pulling_entity == grabbing_entity:
		stop_pulling()
	
	# Clean up grabbed entity state
	var grabbed_controller = get_entity_controller(grabbing_entity)
	if grabbed_controller:
		if "is_moving" in grabbed_controller:
			grabbed_controller.is_moving = false
		if "move_progress" in grabbed_controller:
			grabbed_controller.move_progress = 0.0
		if "position" in grabbed_controller:
			grabbed_controller.position = grabbed_controller.tile_to_world(grabbed_controller.current_tile_position)
	
	# Disconnect signals
	if grabbing_entity.has_signal("movement_attempt"):
		if grabbing_entity.is_connected("movement_attempt", _on_grabbed_movement_attempt):
			grabbing_entity.disconnect("movement_attempt", _on_grabbed_movement_attempt)
	
	# Notify target
	if grabbing_entity.has_method("set_grabbed_by"):
		grabbing_entity.set_grabbed_by(null, GrabState.NONE)
	elif "grabbed_by" in grabbing_entity:
		grabbing_entity.grabbed_by = null
	
	# Sound
	if audio_system:
		audio_system.play_positioned_sound("release", controller.position, 0.2)
	
	# Message
	var target_name = get_entity_name(grabbing_entity)
	show_message("You release your grab on " + target_name + ".")
	
	# Reset state
	var old_entity = grabbing_entity
	grab_state = GrabState.NONE
	grabbing_entity = null
	grab_time = 0.0
	grab_resist_progress = 0.0
	
	emit_signal("grab_state_changed", GrabState.NONE, null)
	emit_signal("grab_released", old_entity)
	
	return true

func process_grab_effects(delta: float):
	"""Process ongoing grab effects"""
	if not grabbing_entity or not is_instance_valid(grabbing_entity):
		release_grab()
		return
	
	grab_time += delta
	
	# Check if still adjacent
	if not is_adjacent_to(grabbing_entity):
		release_grab()
		return
	
	# Apply effects based on state
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
	if grabbing_entity.has_method("is_resisting") and grabbing_entity.is_resisting():
		process_grab_resistance(delta)

func process_grab_resistance(delta: float):
	"""Process grab resistance attempts"""
	grab_resist_progress += delta
	
	# Calculate threshold
	var resist_threshold = 2.0 + (grab_state * 1.5)
	
	if "dexterity" in controller:
		resist_threshold += controller.dexterity * 0.2
	
	if "dexterity" in grabbing_entity:
		grab_resist_progress += (grabbing_entity.dexterity * 0.1) * delta
	
	# Check if broken free
	if grab_resist_progress >= resist_threshold:
		var target_name = get_entity_name(grabbing_entity)
		show_message(target_name + " breaks free from your grab!")
		
		emit_signal("grab_broken", grabbing_entity)
		release_grab()
	else:
		# Progress message
		if fmod(grab_resist_progress, 0.5) < delta:
			emit_signal("grab_resisted", grabbing_entity)

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

func handle_grabbed_entity_following(previous_position: Vector2i):
	"""Make grabbed entity follow when moving"""
	if not grabbing_entity or not is_instance_valid(grabbing_entity):
		return
	
	var grabbed_controller = get_entity_controller(grabbing_entity)
	if grabbed_controller and "is_moving" in grabbed_controller and grabbed_controller.is_moving:
		# Defer to next frame
		controller.get_tree().process_frame.connect(_deferred_grab_follow.bind(previous_position), CONNECT_ONE_SHOT)
		return
	
	# Move grabbed entity
	var success = move_entity_to_position(grabbing_entity, previous_position, true)
	if not success:
		release_grab()

func _deferred_grab_follow(target_position: Vector2i):
	"""Deferred grab following"""
	if not grabbing_entity or not is_instance_valid(grabbing_entity):
		return
	
	var success = move_entity_to_position(grabbing_entity, target_position, true)
	if not success:
		release_grab()

func _on_grabbed_movement_attempt(direction: Vector2i):
	"""Handle when grabbed entity tries to move"""
	if not grabbing_entity:
		return
	
	# Only restrict for aggressive+ grabs
	if grab_state >= GrabState.AGGRESSIVE:
		var restrict_chance = 30 + (grab_state * 20)
		
		if randf() * 100 < restrict_chance:
			if grabbing_entity.has_method("cancel_movement"):
				grabbing_entity.cancel_movement()
			
			if fmod(grab_time, 1.0) < 0.1:
				var messages = ["holds you in place!", "restricts your movement!", "prevents you from moving!"]
				var msg_index = min(grab_state - 1, messages.size() - 1)
				
				if grabbing_entity.has_method("show_interaction_message"):
					grabbing_entity.show_interaction_message(controller.entity_name + " " + messages[msg_index])
#endregion

#region PULL MECHANICS
func pull_entity(target: Node) -> bool:
	"""Start pulling an entity"""
	if not has_pull_flag:
		return false
	
	if not can_pull_entity(target):
		return false
	
	if pulling_entity != null:
		stop_pulling()
	
	pulling_entity = target
	
	# Notify target
	if target.has_method("set_pulled_by"):
		target.set_pulled_by(controller)
	elif "pulled_by" in target:
		target.pulled_by = controller
	
	show_message("You start pulling " + get_entity_name(target) + ".")
	
	emit_signal("pulling_changed", target)
	update_pull_movespeed()
	
	return true

func stop_pulling():
	"""Stop pulling current entity"""
	if not pulling_entity:
		return
	
	# Notify target
	if pulling_entity.has_method("set_pulled_by"):
		pulling_entity.set_pulled_by(null)
	elif "pulled_by" in pulling_entity:
		pulling_entity.pulled_by = null
	
	var old_entity = pulling_entity
	pulling_entity = null
	
	update_pull_movespeed()
	
	show_message("You stop pulling " + get_entity_name(old_entity) + ".")
	
	emit_signal("pulling_changed", null)
	emit_signal("pull_released", old_entity)

func process_pulling(delta: float):
	"""Process pulling mechanics"""
	if not pulling_entity:
		return
	
	# Check distance
	var pulled_pos = get_entity_tile_position(pulling_entity)
	var my_pos = controller.movement_component.current_tile_position if controller.movement_component else Vector2i.ZERO
	
	var distance = (pulled_pos - my_pos).length()
	
	if distance > 2.0:
		stop_pulling()

func process_being_pulled(delta: float):
	"""Process being pulled by someone"""
	if not pulled_by_entity:
		return
	
	var puller_pos = get_entity_tile_position(pulled_by_entity)
	var my_pos = controller.movement_component.current_tile_position if controller.movement_component else Vector2i.ZERO
	
	var distance = (puller_pos - my_pos).length()
	
	if distance > 1.5:
		# Try to catch up
		var dir_to_puller = (puller_pos - my_pos).normalized()
		var move_dir = Vector2i(round(dir_to_puller.x), round(dir_to_puller.y))
		
		if controller.movement_component and not controller.movement_component.is_moving and not controller.movement_component.is_stunned:
			controller.movement_component.attempt_move(move_dir)

func update_pull_movespeed():
	"""Update movement speed based on pulling"""
	if pulling_entity:
		emit_signal("movement_modifier_changed", pull_speed_modifier)
	else:
		emit_signal("movement_modifier_changed", 1.0)

func set_pulled_by(puller: Node):
	"""Set who is pulling this entity"""
	pulled_by_entity = puller
	emit_signal("being_pulled_changed", puller)

func set_grabbed_by(grabber: Node, state: int):
	"""Set who is grabbing this entity"""
	grabbed_by = grabber
	grab_state = state
#endregion

#region HELPER FUNCTIONS
func can_grab_entity(target: Node) -> bool:
	"""Check if can grab target"""
	if not target or target == controller or target == controller.get_parent():
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

func move_entity_to_position(entity: Node, position: Vector2i, animated: bool = true) -> bool:
	"""Move entity to position"""
	if not entity or not is_instance_valid(entity):
		return false
	
	if entity.has_method("move_externally"):
		return entity.move_externally(position, animated, true)
	
	var entity_controller = get_entity_controller(entity)
	if entity_controller and entity_controller.has_method("move_externally"):
		return entity_controller.move_externally(position, animated, true)
	
	return false

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
#endregion
