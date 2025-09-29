extends Node
class_name GrabPullComponent

#region CONSTANTS
const GRAB_DAMAGE_INTERVAL: float = 1.0
const RESIST_CHECK_INTERVAL: float = 0.5
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

#region EXPORTS
@export_group("Grab Configuration")
@export var grab_upgrade_min_time: float = 1.0
@export var base_grab_chance: float = 60.0
@export var fumble_chance: float = 25.0

@export_group("Skill Bonuses")
@export var cqc_accuracy_bonus: float = 15.0
@export var endurance_grip_bonus: float = 5.0
@export var skill_fumble_reduction: float = 5.0

@export_group("Pull Settings")
@export var pull_speed_modifier: float = 0.7
@export var drag_slowdown_modifier: float = 0.6
@export var max_pull_distance: float = 2.0

@export_group("Resistance Thresholds")
@export var base_resistance_threshold: float = 2.0
@export var resistance_per_grab_level: float = 1.5
@export var cqc_resistance_bonus: float = 0.5
@export var endurance_resistance_bonus: float = 0.3

@export_group("Mass Limits")
@export var max_grab_mass_ratio: float = 2.0
@export var max_pull_mass_ratio: float = 1.5
@export var fireman_carry_mass_ratio: float = 1.5

@export_group("Audio Settings")
@export var grab_sound: String = "grab"
@export var tighten_sound: String = "grab_tighten"
@export var choke_sound: String = "choke"
@export var release_sound: String = "release"
@export var default_volume: float = 0.3
#endregion

#region PROPERTIES
# Component references
var controller: Node = null
var sensory_system = null
var audio_system = null
var tile_occupancy_system = null
var skill_component: Node = null
var world = null
var do_after_component: Node = null

# Grab state
var grab_state: int = GrabState.NONE : set = _set_grab_state
var grabbing_entity: Node = null : set = _set_grabbing_entity
var grabbed_by: Node = null : set = _set_grabbed_by
var pulling_entity: Node = null : set = _set_pulling_entity
var pulled_by_entity: Node = null : set = _set_pulled_by_entity

# Operation state
var grab_time: float = 0.0
var grab_resist_progress: float = 0.0
var original_move_time: float = 0.0
var is_dragging_entity: bool = false

# Entity properties
var has_pull_flag: bool = true
var dexterity: float = 10.0
var mass: float = 70.0

# Network state
var is_local_player: bool = false
var peer_id: int = 1

# Cached calculations for performance
var _cached_movement_modifiers: Dictionary = {}
var _modifier_cache_dirty: bool = true
#endregion

#region INITIALIZATION
func initialize(init_data: Dictionary):
	controller = init_data.get("controller")
	world = init_data.get("world")
	sensory_system = init_data.get("sensory_system")
	audio_system = init_data.get("audio_system")
	tile_occupancy_system = init_data.get("tile_occupancy_system")
	skill_component = init_data.get("skill_component")
	do_after_component = init_data.get("do_after_component")
	is_local_player = init_data.get("is_local_player", false)
	peer_id = init_data.get("peer_id", 1)
	
	if not do_after_component and controller:
		do_after_component = controller.get_node_or_null("DoAfterComponent")

func _physics_process(delta: float):
	if grabbing_entity:
		_process_grab_effects(delta)
	
	if pulled_by_entity:
		_process_being_pulled(delta)
	
	if pulling_entity:
		_process_pulling(delta)
#endregion

#region PROPERTY SETTERS
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

#region GRABBING MECHANICS
func grab_entity(target: Node, initial_state: int = GrabState.PASSIVE) -> bool:
	if not is_multiplayer_authority():
		return false
	
	if not _can_grab_entity(target):
		return false
	
	if grabbing_entity != null:
		if grabbing_entity == target:
			return upgrade_grab()
		else:
			show_message("You're already grabbing " + _get_entity_name(grabbing_entity) + "!")
			return false
	
	if not _check_grab_skill_requirements(target, initial_state):
		return false
	
	_apply_grab_start(target, initial_state)
	
	var target_id = _get_entity_network_id(target)
	if target_id != "":
		sync_grab_start.rpc(target_id, initial_state)
		sync_grab_effects.rpc("grab_sound", target_id)
	
	return true

func upgrade_grab() -> bool:
	if not is_multiplayer_authority() or not grabbing_entity:
		return false
	
	if grab_state >= GrabState.KILL:
		return false
	
	if grab_time < grab_upgrade_min_time:
		return false
	
	if do_after_component and do_after_component.is_performing_action():
		show_message("You're busy doing something else!")
		return false
	
	var new_state = grab_state + 1
	
	if not _check_grab_skill_requirements(grabbing_entity, new_state):
		return false
	
	# Use do_after for grab upgrades
	if do_after_component and new_state >= GrabState.AGGRESSIVE:
		var callback = Callable(self, "_execute_grab_upgrade")
		return do_after_component.start_grab_upgrade_action(callback.bind(new_state))
	else:
		return _execute_grab_upgrade(new_state)

func _execute_grab_upgrade(new_state: int) -> bool:
	if not grabbing_entity or not is_instance_valid(grabbing_entity):
		return false
	
	var upgrade_chance = _calculate_grab_upgrade_chance()
	
	if randf() * 100.0 < upgrade_chance:
		_apply_grab_upgrade(new_state)
		sync_grab_upgrade.rpc(new_state)
		_grant_grab_experience(new_state)
		
		var target_id = _get_entity_network_id(grabbing_entity)
		if target_id != "":
			var sound_effect = choke_sound if new_state == GrabState.KILL else tighten_sound
			sync_grab_effects.rpc(sound_effect, target_id, {"state": new_state})
		
		return true
	else:
		if _should_fumble_grab():
			show_message("You fumble and lose your grip on " + _get_entity_name(grabbing_entity) + "!")
			release_grab()
		else:
			show_message("You fail to tighten your grip.")
		
		return false

func release_grab() -> bool:
	if not is_multiplayer_authority() or not grabbing_entity:
		return false
	
	_apply_grab_release()
	sync_grab_release.rpc()
	
	var target_id = _get_entity_network_id(grabbing_entity)
	if target_id != "":
		sync_grab_effects.rpc("release_sound", target_id)
	
	return true

func _calculate_grab_upgrade_chance() -> float:
	var chance = base_grab_chance
	var user_skill = 0.0
	var target_resistance = 0.0
	
	if skill_component:
		var cqc_level = skill_component.get_skill_level(skill_component.SKILL_CQC)
		user_skill += cqc_level * cqc_accuracy_bonus
		
		var endurance_level = skill_component.get_skill_level(skill_component.SKILL_ENDURANCE)
		user_skill += endurance_level * endurance_grip_bonus
	
	if "dexterity" in grabbing_entity:
		target_resistance = grabbing_entity.dexterity * 1.5
	
	if "health" in grabbing_entity and "max_health" in grabbing_entity:
		var health_percent = grabbing_entity.health / grabbing_entity.max_health
		target_resistance *= health_percent
	
	target_resistance *= _get_target_condition_multiplier()
	
	var final_chance = chance + user_skill - target_resistance
	return clamp(final_chance, 10.0, 90.0)

func _get_target_condition_multiplier() -> float:
	var multiplier = 1.0
	
	if "is_stunned" in grabbing_entity and grabbing_entity.is_stunned:
		multiplier *= 0.5
	
	if "is_lying" in grabbing_entity and grabbing_entity.is_lying:
		multiplier *= 0.7
	
	return multiplier

func _should_fumble_grab() -> bool:
	var fumble_chance_modified = fumble_chance
	
	if skill_component:
		var cqc_level = skill_component.get_skill_level(skill_component.SKILL_CQC)
		fumble_chance_modified = max(5.0, fumble_chance_modified - (cqc_level * skill_fumble_reduction))
	
	return randf() * 100.0 < fumble_chance_modified

func _check_grab_skill_requirements(target: Node, grab_state: int) -> bool:
	if not skill_component:
		return true
	
	match grab_state:
		GrabState.PASSIVE:
			return true
		GrabState.AGGRESSIVE:
			if not skill_component.is_skilled(skill_component.SKILL_CQC, skill_component.SKILL_LEVEL_NOVICE):
				show_message("You don't know how to restrain people effectively!")
				return false
		GrabState.NECK:
			if not skill_component.is_skilled(skill_component.SKILL_CQC, skill_component.SKILL_LEVEL_TRAINED):
				show_message("You don't have the training to perform neck restraints!")
				return false
		GrabState.KILL:
			var has_cqc = skill_component.is_skilled(skill_component.SKILL_CQC, skill_component.SKILL_LEVEL_SKILLED)
			var has_execution = skill_component.is_skilled(skill_component.SKILL_EXECUTION, skill_component.SKILL_LEVEL_NOVICE)
			
			if not has_cqc and not has_execution:
				show_message("You don't have the training to perform lethal restraints!")
				return false
	
	return true
#endregion

#region PULLING MECHANICS
func pull_entity(target: Node) -> bool:
	if not is_multiplayer_authority():
		return false
	
	if not has_pull_flag or not _can_pull_entity(target):
		return false
	
	if pulling_entity != null:
		stop_pulling()
	
	if skill_component and "mass" in target:
		var endurance_level = skill_component.get_skill_level(skill_component.SKILL_ENDURANCE)
		var max_pull_mass = 50.0 + (endurance_level * 25.0)
		
		if target.mass > max_pull_mass:
			show_message("You're not strong enough to pull something that heavy!")
			return false
	
	_apply_pull_start(target)
	
	var target_id = _get_entity_network_id(target)
	if target_id != "":
		sync_pull_start.rpc(target_id)
	
	return true

func stop_pulling():
	if not is_multiplayer_authority() or not pulling_entity:
		return
	
	_apply_pull_stop()
	sync_pull_stop.rpc()

func _apply_pull_start(target: Node):
	pulling_entity = target
	
	var target_controller = _get_entity_controller(target)
	if target_controller and target_controller.grab_pull_component:
		target_controller.grab_pull_component.set_pulled_by(controller)
	
	show_message("You start pulling " + _get_entity_name(target) + ".")
	_update_pull_movespeed()

func _apply_pull_stop():
	if not pulling_entity:
		return
	
	var target_controller = _get_entity_controller(pulling_entity)
	if target_controller and target_controller.grab_pull_component:
		target_controller.grab_pull_component.set_pulled_by(null)
	
	var old_entity = pulling_entity
	pulling_entity = null
	
	_update_pull_movespeed()
	
	show_message("You stop pulling " + _get_entity_name(old_entity) + ".")
	emit_signal("pull_released", old_entity)
#endregion

#region FIREMAN CARRY
func initiate_fireman_carry_sequence(target: Node) -> bool:
	if not target or target == controller:
		return false
	
	if not _can_fireman_carry_target(target):
		return false
	
	if grab_state != GrabState.AGGRESSIVE:
		show_message("You need to grab them more aggressively first!")
		return false
	
	if do_after_component and do_after_component.is_performing_action():
		show_message("You're busy doing something else!")
		return false
	
	# Use do_after for fireman carry
	if do_after_component:
		var callback = Callable(self, "_execute_fireman_carry")
		return do_after_component.start_fireman_carry_action(target, callback)
	else:
		return _execute_fireman_carry(target)

func _execute_fireman_carry(target: Node) -> bool:
	if not target or not is_instance_valid(target):
		return false
	
	if not grabbing_entity or grabbing_entity != target:
		show_message("You're no longer grabbing them!")
		return false
	
	controller.set_meta("carrying_someone", true)
	target.set_meta("being_carried", true)
	
	if controller.movement_component:
		var skill_level = skill_component.get_skill_level(skill_component.SKILL_FIREMAN) if skill_component else 0
		var carry_penalty = 0.6 + (skill_level * 0.05)
		controller.movement_component.set_movement_modifier(carry_penalty)
	
	_handle_fireman_carry_positioning()
	
	show_message("You successfully lift " + _get_entity_name(target) + " into a fireman's carry!")
	
	if skill_component and randf() < 0.3:
		skill_component.increment_skill(skill_component.SKILL_FIREMAN, 1, 3)
	
	return true

func start_fireman_carry(target: Node) -> bool:
	if not skill_component or not skill_component.can_fireman_carry():
		show_message("You don't know how to properly carry someone!")
		return false
	
	if not _can_fireman_carry_target(target):
		return false
	
	if grabbing_entity or pulling_entity:
		show_message("You're already carrying someone!")
		return false
	
	if do_after_component and do_after_component.is_performing_action():
		show_message("You're busy doing something else!")
		return false
	
	# Use do_after for stand-alone fireman carry attempts
	if do_after_component:
		var callback = Callable(self, "_execute_standalone_fireman_carry")
		var config_override = {
			"base_duration": 3.0,
			"display_name": "lifting " + _get_entity_name(target) + " into a fireman's carry"
		}
		return do_after_component.start_action("fireman_carry", config_override, callback, target)
	else:
		return _execute_standalone_fireman_carry(target)

func _execute_standalone_fireman_carry(target: Node) -> bool:
	if not target or not is_instance_valid(target):
		return false
	
	if not _can_fireman_carry_target(target):
		return false
	
	var skill_level = skill_component.get_skill_level(skill_component.SKILL_FIREMAN)
	var base_chance = 40.0 + (skill_level * 20.0)
	
	if "mass" in target and "mass" in controller:
		var mass_ratio = target.mass / max(controller.mass, 1.0)
		base_chance -= (mass_ratio - 1.0) * 40.0
	
	if skill_component:
		var endurance_level = skill_component.get_skill_level(skill_component.SKILL_ENDURANCE)
		base_chance += endurance_level * 10.0
	
	base_chance = clamp(base_chance, 5.0, 95.0)
	
	if randf() * 100.0 < base_chance:
		var success = grab_entity(target, GrabState.PASSIVE)
		if success:
			target.set_meta("being_carried", true)
			controller.set_meta("carrying_someone", true)
			
			var movement_penalty = 0.5 + (skill_level * 0.1)
			if controller.has_method("apply_movement_modifier"):
				controller.apply_movement_modifier(movement_penalty)
			
			show_message("You lift " + _get_entity_name(target) + " into a fireman's carry!")
			_grant_fireman_carry_experience()
			
			return true
	
	show_message("You fail to lift " + _get_entity_name(target) + " properly.")
	return false

func _can_fireman_carry_target(target: Node) -> bool:
	if not target or target == controller:
		return false
	
	var is_incapacitated = false
	
	if "is_unconscious" in target and target.is_unconscious:
		is_incapacitated = true
	elif "is_lying" in target and target.is_lying:
		if "health" in target and "max_health" in target:
			if target.health / target.max_health < 0.4:
				is_incapacitated = true
	
	if not is_incapacitated:
		show_message("They need to be unconscious or badly hurt to carry them!")
		return false
	
	if "mass" in target and "mass" in controller:
		if target.mass > controller.mass * fireman_carry_mass_ratio:
			show_message("They're too heavy for you to carry!")
			return false
	
	return true

func _handle_fireman_carry_positioning():
	if not grabbing_entity or not controller:
		return
	
	var my_pos = controller.movement_component.current_tile_position
	if __get_entity_tile_position(grabbing_entity) != my_pos:
		_move_entity_to_position(grabbing_entity, my_pos)
	
	if "z_index" in grabbing_entity:
		grabbing_entity.z_index = controller.z_index + 1
	
	if grabbing_entity.has_method("set_carried_state"):
		grabbing_entity.set_carried_state(true)

func _handle_choking_positioning():
	if not grabbing_entity or not controller:
		return
	
	var my_pos = controller.movement_component.current_tile_position
	if __get_entity_tile_position(grabbing_entity) != my_pos:
		_move_entity_to_position(grabbing_entity, my_pos)
	
	if "z_index" in grabbing_entity:
		grabbing_entity.z_index = controller.z_index + 1
#endregion

#region GRAB STATE MANAGEMENT
func _apply_grab_start(target: Node, initial_state: int):
	grabbing_entity = target
	grab_state = initial_state
	grab_time = 0.0
	grab_resist_progress = 0.0
	
	_apply_drag_slowdown(true)
	
	var target_controller = _get_entity_controller(target)
	if target_controller and target_controller.grab_pull_component:
		target_controller.grab_pull_component.set_grabbed_by(controller, grab_state)
	
	if is_multiplayer_authority() and target.has_signal("movement_attempt"):
		if not target.is_connected("movement_attempt", _on_grabbed_movement_attempt):
			target.movement_attempt.connect(_on_grabbed_movement_attempt)
	
	if grab_state == GrabState.PASSIVE:
		if is_multiplayer_authority():
			pull_entity(target)
	
	_show_grab_message(target, grab_state)

func _apply_grab_upgrade(new_state: int):
	var old_state = grab_state
	grab_state = new_state
	
	if old_state == GrabState.PASSIVE and pulling_entity == grabbing_entity:
		if is_multiplayer_authority():
			stop_pulling()
	
	grab_time = 0.0
	grab_resist_progress = 0.0
	
	var target_controller = _get_entity_controller(grabbing_entity)
	if target_controller and target_controller.grab_pull_component:
		target_controller.grab_pull_component.set_grabbed_by(controller, grab_state)
	
	_show_grab_upgrade_message(grabbing_entity, grab_state)
	_apply_grab_escalation_effects(old_state, grab_state)

func _apply_grab_release():
	if not grabbing_entity:
		return
	
	_apply_drag_slowdown(false)
	
	if pulling_entity == grabbing_entity:
		if is_multiplayer_authority():
			stop_pulling()
	
	_cleanup_grabbed_entity_state()
	
	if is_multiplayer_authority() and grabbing_entity.has_signal("movement_attempt"):
		if grabbing_entity.is_connected("movement_attempt", _on_grabbed_movement_attempt):
			grabbing_entity.disconnect("movement_attempt", _on_grabbed_movement_attempt)
	
	var target_controller = _get_entity_controller(grabbing_entity)
	if target_controller and target_controller.grab_pull_component:
		target_controller.grab_pull_component.set_grabbed_by(null, GrabState.NONE)
	
	var target_name = _get_entity_name(grabbing_entity)
	show_message("You release your grab on " + target_name + ".")
	
	var old_entity = grabbing_entity
	grab_state = GrabState.NONE
	grabbing_entity = null
	grab_time = 0.0
	grab_resist_progress = 0.0
	
	emit_signal("grab_released", old_entity)

func _cleanup_grabbed_entity_state():
	var grabbed_controller = _get_entity_controller(grabbing_entity)
	if grabbed_controller:
		if "is_moving" in grabbed_controller:
			grabbed_controller.is_moving = false
		if "move_progress" in grabbed_controller:
			grabbed_controller.move_progress = 0.0
		if grabbed_controller.movement_component:
			grabbed_controller.position = _tile_to_world(grabbed_controller.movement_component.get_current_tile_position())

func _show_grab_message(target: Node, state: int):
	var target_name = _get_entity_name(target)
	match state:
		GrabState.PASSIVE:
			show_message("You grab " + target_name + " passively.")
		GrabState.AGGRESSIVE:
			show_message("You grab " + target_name + " aggressively!")
		GrabState.NECK:
			show_message("You grab " + target_name + " by the neck!")
		GrabState.KILL:
			show_message("You start strangling " + target_name + "!")

func _show_grab_upgrade_message(target: Node, state: int):
	var target_name = _get_entity_name(target)
	match state:
		GrabState.AGGRESSIVE:
			show_message("You tighten your grip on " + target_name + "!")
		GrabState.NECK:
			show_message("You grab " + target_name + " by the neck!")
		GrabState.KILL:
			show_message("You start strangling " + target_name + "!")
			_handle_choking_positioning()
#endregion

#region GRAB EFFECTS PROCESSING
func _process_grab_effects(delta: float):
	if not grabbing_entity or not is_instance_valid(grabbing_entity):
		if is_multiplayer_authority():
			release_grab()
		return
	
	grab_time += delta
	
	if is_multiplayer_authority() and not _is_adjacent_to(grabbing_entity):
		release_grab()
		return
	
	if is_multiplayer_authority():
		_apply_grab_state_effects(delta)
		
		var target_controller = _get_entity_controller(grabbing_entity)
		if target_controller and target_controller.has_method("is_resisting") and target_controller.is_resisting():
			_process_grab_resistance(delta)

func _apply_grab_state_effects(delta: float):
	match grab_state:
		GrabState.PASSIVE:
			pass
		GrabState.AGGRESSIVE:
			if grabbing_entity.has_method("apply_movement_modifier"):
				grabbing_entity.apply_movement_modifier(0.8)
		GrabState.NECK:
			_apply_neck_grab_effects(delta)
		GrabState.KILL:
			_apply_kill_grab_effects(delta)

func _apply_neck_grab_effects(delta: float):
	if grabbing_entity.has_method("add_stamina_loss"):
		grabbing_entity.add_stamina_loss(15 * delta)
	
	if grabbing_entity.has_method("set_muffled"):
		grabbing_entity.set_muffled(true, 1.5)
	
	if grabbing_entity.has_method("apply_movement_modifier"):
		grabbing_entity.apply_movement_modifier(0.5)

func _apply_kill_grab_effects(delta: float):
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

func _process_grab_resistance(delta: float):
	grab_resist_progress += delta
	
	var resist_threshold = _calculate_resistance_threshold()
	
	if "dexterity" in grabbing_entity:
		grab_resist_progress += (grabbing_entity.dexterity * 0.1) * delta
	
	if grab_resist_progress >= resist_threshold:
		var target_id = _get_entity_network_id(grabbing_entity)
		if target_id != "":
			sync_grab_effects.rpc("resistance_break", target_id)
		
		emit_signal("grab_broken", grabbing_entity)
		release_grab()
	else:
		if fmod(grab_resist_progress, 0.5) < delta:
			emit_signal("grab_resisted", grabbing_entity)

func _calculate_resistance_threshold() -> float:
	var threshold = base_resistance_threshold + (grab_state * resistance_per_grab_level)
	
	if skill_component:
		var cqc_level = skill_component.get_skill_level(skill_component.SKILL_CQC)
		threshold += cqc_level * cqc_resistance_bonus
		
		var endurance_level = skill_component.get_skill_level(skill_component.SKILL_ENDURANCE)
		threshold += endurance_level * endurance_resistance_bonus
	
	return threshold
#endregion

#region MOVEMENT SYNCHRONIZATION
func start_synchronized_follow(grabber_previous_position: Vector2i, grabber_move_time: float):
	if not is_multiplayer_authority() or not grabbing_entity or not is_instance_valid(grabbing_entity):
		return
	
	var grabbed_controller = _get_entity_controller(grabbing_entity)
	if not grabbed_controller or not grabbed_controller.movement_component:
		return
	
	var grabbed_current_pos = __get_entity_tile_position(grabbing_entity)
	
	if grabbed_current_pos == grabber_previous_position:
		return
	
	var movement_comp = grabbed_controller.movement_component
	
	if movement_comp.is_moving:
		movement_comp.complete_movement()
	
	var target_position = grabber_previous_position
	if not _is_valid_target_position(target_position):
		target_position = _find_closest_valid_position(target_position, grabbed_current_pos)
		if target_position == Vector2i(-9999, -9999):
			show_message("Lost grip due to obstruction!")
			release_grab()
			return
	
	movement_comp.current_move_time = grabber_move_time
	movement_comp.is_moving = true
	movement_comp.move_progress = 0.0
	movement_comp.current_tile_position = grabbed_current_pos
	movement_comp.target_tile_position = target_position
	
	if grab_state == GrabState.KILL:
		_handle_choking_positioning()
	elif controller.get_meta("carrying_someone", false):
		_handle_fireman_carry_positioning()
	
	var target_id = _get_entity_network_id(grabbing_entity)
	if target_id != "":
		sync_grabbed_entity_position.rpc(target_id, target_position, grabber_move_time)
	
	_apply_grabbed_entity_movement(grabbing_entity, target_position, grabber_move_time)

func _apply_grabbed_entity_movement(target: Node, target_position: Vector2i, move_time: float):
	var target_controller = _get_entity_controller(target)
	if not target_controller or not target_controller.movement_component:
		return
	
	var movement_comp = target_controller.movement_component
	
	movement_comp.current_move_time = move_time
	movement_comp.start_external_move_to(target_position)
	
	if is_multiplayer_authority() and sensory_system and randf() < 0.2:
		var grabber_name = controller.entity_name if "entity_name" in controller else controller.name
		var target_sensory = target_controller.get_node_or_null("SensorySystem")
		if target_sensory:
			target_sensory.display_message("You are dragged by " + grabber_name + "!")
#endregion

#region PULL PROCESSING
func _process_pulling(delta: float):
	if not pulling_entity:
		return
	
	var pulled_pos = __get_entity_tile_position(pulling_entity)
	var my_pos = controller.movement_component.current_tile_position if controller.movement_component else Vector2i.ZERO
	
	var distance = (pulled_pos - my_pos).length()
	
	if distance > max_pull_distance:
		if is_multiplayer_authority():
			stop_pulling()

func _process_being_pulled(delta: float):
	if not pulled_by_entity:
		return
	
	var puller_pos = __get_entity_tile_position(pulled_by_entity)
	var my_pos = controller.movement_component.get_current_tile_position()
	
	var distance = (Vector2(puller_pos) - Vector2(my_pos)).length()
	
	if distance > 1.5:
		var dir_to_puller = (Vector2(puller_pos) - Vector2(my_pos)).normalized()
		var move_dir = Vector2i(round(dir_to_puller.x), round(dir_to_puller.y))
		
		if controller.movement_component and not controller.movement_component.is_moving and not controller.movement_component.is_stunned:
			controller.movement_component.move_externally(move_dir)
#endregion

#region MOVEMENT MODIFIERS
func _update_pull_movespeed():
	if pulling_entity:
		var base_modifier = pull_speed_modifier
		
		if skill_component:
			var endurance_level = skill_component.get_skill_level(skill_component.SKILL_ENDURANCE)
			var endurance_bonus = endurance_level * 0.1
			base_modifier = min(1.0, base_modifier + endurance_bonus)
		
		emit_signal("movement_modifier_changed", base_modifier)
	else:
		emit_signal("movement_modifier_changed", 1.0)

func _apply_drag_slowdown(enable: bool):
	if enable and not is_dragging_entity:
		is_dragging_entity = true
		
		var base_modifier = drag_slowdown_modifier
		
		if skill_component:
			var endurance_level = skill_component.get_skill_level(skill_component.SKILL_ENDURANCE)
			var fireman_level = skill_component.get_skill_level(skill_component.SKILL_FIREMAN)
			
			var skill_bonus = (endurance_level * 0.05) + (fireman_level * 0.1)
			base_modifier = min(1.0, base_modifier + skill_bonus)
		
		emit_signal("movement_modifier_changed", base_modifier)
		show_message("You slow down while dragging " + _get_entity_name(grabbing_entity) + ".")
	elif not enable and is_dragging_entity:
		is_dragging_entity = false
		emit_signal("movement_modifier_changed", 1.0)
		show_message("You move normally again.")

func _apply_grab_escalation_effects(old_state: int, new_state: int):
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
			
			if controller.movement_component:
				var my_pos = controller.movement_component.current_tile_position
				_move_entity_to_position(grabbing_entity, my_pos)
			
			if "z_index" in grabbing_entity:
				grabbing_entity.z_index = controller.z_index + 1
#endregion

#region VALIDATION FUNCTIONS
func _can_grab_entity(target: Node) -> bool:
	if not target:
		return false
	
	if "entity_type" in target:
		if target.entity_type != "character" and target.entity_type != "mob":
			if target.entity_type == "item":
				if "w_class" in target and target.w_class > 3:
					show_message("That's too big to grab!")
					return false
			else:
				return false
	
	if "no_grab" in target and target.no_grab:
		show_message("You can't grab that!")
		return false
	
	if "grabbed_by" in target and target.grabbed_by != null and target.grabbed_by != controller:
		show_message("Someone else is already grabbing them!")
		return false
	
	if not _is_adjacent_to(target):
		show_message("You need to be closer to grab that!")
		return false
	
	if "mass" in target and target.mass > mass * max_grab_mass_ratio:
		show_message("They're too heavy for you to grab!")
		return false
	
	return true

func _can_pull_entity(target: Node) -> bool:
	if not target or target == controller:
		return false
	
	if "no_pull" in target and target.no_pull:
		return false
	
	if not _is_adjacent_to(target):
		show_message("You need to be closer to pull that!")
		return false
	
	return true

func _is_adjacent_to(target: Node) -> bool:
	if controller.movement_component:
		return controller.movement_component.is_adjacent_to(target)
	return false

func _is_valid_target_position(position: Vector2i) -> bool:
	if not world:
		return false
	
	var z_level = controller.current_z_level if controller else 0
	
	if world.has_method("is_valid_tile") and not world.is_valid_tile(position, z_level):
		return false
	
	if world.has_method("is_wall_at") and world.is_wall_at(position, z_level):
		return false
	
	if world.has_method("is_closed_door_at") and world.is_closed_door_at(position, z_level):
		return false
	
	if tile_occupancy_system and tile_occupancy_system.has_method("has_dense_entity_at"):
		if tile_occupancy_system.has_dense_entity_at(position, z_level, grabbing_entity):
			var entity_at_pos = tile_occupancy_system.get_entity_at(position, z_level)
			if entity_at_pos != controller:
				return false
	
	return true

func _find_closest_valid_position(target_pos: Vector2i, current_pos: Vector2i) -> Vector2i:
	var offsets = [
		Vector2i(0, 0), Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
		Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1)
	]
	
	offsets.sort_custom(func(a, b): 
		var pos_a = target_pos + a
		var pos_b = target_pos + b
		var dist_a = (pos_a - current_pos).length_squared()
		var dist_b = (pos_b - current_pos).length_squared()
		return dist_a < dist_b
	)
	
	for offset in offsets:
		var test_pos = target_pos + offset
		if _is_valid_target_position(test_pos):
			return test_pos
	
	return Vector2i(-9999, -9999)

func _move_entity_to_position(entity: Node, position: Vector2i, animated: bool = true) -> bool:
	if not entity or not is_instance_valid(entity):
		return false
	
	if entity.has_method("move_externally"):
		return entity.move_externally(position, animated, true)
	
	var entity_controller = _get_entity_controller(entity)
	if entity_controller and entity_controller.movement_component:
		if entity_controller.movement_component.has_method("move_externally"):
			return entity_controller.movement_component.move_externally(position, animated, true)
	
	return false
#endregion

#region EXPERIENCE GRANTING
func _grant_grab_experience(grab_state: int):
	if not skill_component or not skill_component.allow_skill_gain:
		return
	
	var experience_chance = 0.0
	
	match grab_state:
		GrabState.AGGRESSIVE:
			experience_chance = 0.15
		GrabState.NECK:
			experience_chance = 0.25
		GrabState.KILL:
			experience_chance = 0.35
	
	if randf() < experience_chance:
		skill_component.increment_skill(skill_component.SKILL_CQC, 1, 4)

func _grant_fireman_carry_experience():
	if not skill_component or not skill_component.allow_skill_gain:
		return
	
	if randf() < 0.3:
		skill_component.increment_skill(skill_component.SKILL_FIREMAN, 1, 3)
	
	if randf() < 0.2:
		skill_component.increment_skill(skill_component.SKILL_ENDURANCE, 1, 3)
#endregion

#region UTILITY FUNCTIONS
func is_grabbing() -> bool:
	return grabbing_entity != null

func is_entity_grabbed_by_me(entity: Node) -> bool:
	if grabbing_entity == entity:
		return true
	
	if "grabbed_by" in entity:
		return true
	
	var entity_controller = _get_entity_controller(entity)
	if entity_controller and "grabbed_by" in entity_controller and entity_controller.grabbed_by == controller:
		return true
	
	return false

func set_pulled_by(puller: Node):
	pulled_by_entity = puller

func set_grabbed_by(grabber: Node, state: int):
	grabbed_by = grabber
	grab_state = state

func cleanup():
	if grabbing_entity:
		release_grab()
	if pulling_entity:
		stop_pulling()

func _on_grabbed_movement_attempt(direction: Vector2i):
	if not grabbing_entity:
		return
	
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

func _get_entity_controller(entity: Node) -> Node:
	if entity.has_method("get_current_tile_position"):
		return entity
	elif entity.has_node("GridMovementController"):
		return entity.get_node("GridMovementController")
	return null

func __get_entity_tile_position(entity: Node) -> Vector2i:
	if controller.movement_component:
		return controller.movement_component._get_entity_tile_position(entity)
	return Vector2i.ZERO

func _tile_to_world(tile_pos: Vector2i) -> Vector2:
	return Vector2((tile_pos.x * 32) + 16, (tile_pos.y * 32) + 16)

func _get_entity_name(entity: Node) -> String:
	if "entity_name" in entity and entity.entity_name != "":
		return entity.entity_name
	elif "name" in entity:
		return entity.name
	else:
		return "that"

func show_message(text: String):
	if sensory_system:
		sensory_system.display_message(text)
#endregion

#region NETWORK SYNCHRONIZATION
func _get_entity_network_id(entity: Node) -> String:
	if not entity:
		return ""
	
	if entity.has_method("get_network_id"):
		return entity.get_network_id()
	elif "peer_id" in entity:
		return "player_" + str(entity.peer_id)
	elif entity.has_meta("network_id"):
		return entity.get_meta("network_id")
	else:
		return entity.get_path()

@rpc("any_peer", "call_local", "reliable")
func sync_grab_start(target_network_id: String, initial_state: int):
	if not is_multiplayer_authority():
		var target = _find_entity_by_network_id(target_network_id)
		if target:
			_apply_grab_start(target, initial_state)

@rpc("any_peer", "call_local", "reliable")
func sync_grab_upgrade(new_state: int):
	if not is_multiplayer_authority():
		_apply_grab_upgrade(new_state)

@rpc("any_peer", "call_local", "reliable")
func sync_grab_release():
	if not is_multiplayer_authority():
		_apply_grab_release()

@rpc("any_peer", "call_local", "reliable")
func sync_pull_start(target_network_id: String):
	if not is_multiplayer_authority():
		var target = _find_entity_by_network_id(target_network_id)
		if target:
			_apply_pull_start(target)

@rpc("any_peer", "call_local", "reliable")
func sync_pull_stop():
	if not is_multiplayer_authority():
		_apply_pull_stop()

@rpc("any_peer", "call_local", "reliable")
func sync_grab_effects(effect_type: String, target_network_id: String, additional_data: Dictionary = {}):
	var target = _find_entity_by_network_id(target_network_id)
	if not target:
		return
	
	match effect_type:
		"grab_sound":
			if audio_system:
				audio_system.play_positioned_sound(grab_sound, controller.position, default_volume)
		"tighten_sound":
			if audio_system:
				var volume = default_volume + (0.1 * additional_data.get("state", 1))
				audio_system.play_positioned_sound(tighten_sound, controller.position, volume)
		"choke_sound":
			if audio_system:
				audio_system.play_positioned_sound(choke_sound, controller.position, 0.5)
		"release_sound":
			if audio_system:
				audio_system.play_positioned_sound(release_sound, controller.position, default_volume)
		"resistance_break":
			var target_name = _get_entity_name(target)
			show_message(target_name + " breaks free from " + _get_entity_name(controller) + "'s grab!")

@rpc("any_peer", "call_local", "reliable")
func sync_grabbed_entity_position(target_network_id: String, new_position: Vector2i, move_time: float):
	var target = _find_entity_by_network_id(target_network_id)
	if not target:
		return
	
	var target_controller = _get_entity_controller(target)
	if not target_controller or not target_controller.movement_component:
		return
	
	var movement_comp = target_controller.movement_component
	movement_comp.current_move_time = move_time
	movement_comp.start_external_move_to(new_position)

func _find_entity_by_network_id(network_id: String) -> Node:
	if network_id == "":
		return null
	
	if network_id.begins_with("player_"):
		var peer_id = network_id.split("_")[1].to_int()
		return _find_player_by_peer_id(peer_id)
	
	if network_id.begins_with("/"):
		return get_node_or_null(network_id)
	
	var entities = get_tree().get_nodes_in_group("networkable")
	for entity in entities:
		if entity.has_meta("network_id") and entity.get_meta("network_id") == network_id:
			return entity
		if entity.has_method("get_network_id") and entity.get_network_id() == network_id:
			return entity
	
	return null

func _find_player_by_peer_id(peer_id: int) -> Node:
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player.has_meta("peer_id") and player.get_meta("peer_id") == peer_id:
			return player
		if "peer_id" in player and player.peer_id == peer_id:
			return player
	
	return null
#endregion
