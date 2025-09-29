extends Node
class_name PostureComponent

#region CONSTANTS
const LYING_ANGLE: float = 90.0
#endregion

#region SIGNALS
signal lying_state_changed(is_lying: bool)
signal stand_up_attempted(success: bool)
signal crawl_state_changed(is_crawling: bool)
signal rest_toggled()
#endregion

#region EXPORTS
@export_group("Posture Configuration")
@export var lying_state_change_cooldown: float = 0.8
@export var lying_stamina_recovery_bonus: float = 1.5
@export var crawl_speed_multiplier: float = 0.5
@export var can_crawl: bool = true

@export_group("Health Restrictions")
@export var min_health_percentage_to_stand: float = 0.1
@export var max_stamina_loss_to_stand: float = 90.0
@export var max_pain_level_to_stand: float = 80.0
@export var max_leg_fractures_to_stand: int = 1

@export_group("Audio Settings")
@export var body_fall_sound: String = "body_fall"
@export var rustle_sound: String = "rustle"
@export var crawl_sound: String = "crawl"
@export var struggle_sound: String = "struggle"
@export var fall_sound_volume: float = 0.4
@export var rustle_sound_volume: float = 0.4
#endregion

#region PROPERTIES
var controller: Node = null
var sensory_system = null
var audio_system = null
var sprite_system = null
var health_system = null
var limb_system = null
var status_effect_manager = null
var skill_component: Node = null
var do_after_component: Node = null

var is_lying: bool = false : set = _set_is_lying
var lying_angle: float = LYING_ANGLE : set = _set_lying_angle

# State tracking
var last_lying_state_change: float = 0.0
var stand_up_attempts: int = 0
var crawl_cooldown: float = 0.0
var forced_lying: bool = false
var health_forced_lying: bool = false
var is_crawling: bool = false

# Network state
var is_local_player: bool = false
var peer_id: int = 1
#endregion

#region INITIALIZATION
func initialize(init_data: Dictionary):
	controller = init_data.get("controller")
	sensory_system = init_data.get("sensory_system")
	audio_system = init_data.get("audio_system")
	sprite_system = init_data.get("sprite_system")
	skill_component = init_data.get("skill_component")
	do_after_component = init_data.get("do_after_component")
	is_local_player = init_data.get("is_local_player", false)
	peer_id = init_data.get("peer_id", 1)
	
	_connect_to_systems()
	
	if not do_after_component and controller:
		do_after_component = controller.get_node_or_null("DoAfterComponent")

func _connect_to_systems():
	var parent = controller.get_parent() if controller else null
	if parent:
		health_system = parent.get_node_or_null("HealthSystem")
		limb_system = parent.get_node_or_null("LimbSystem")
		status_effect_manager = parent.get_node_or_null("StatusEffectManager")

func _process(delta: float):
	if crawl_cooldown > 0:
		crawl_cooldown -= delta

func setup_singleplayer():
	is_local_player = true
	peer_id = 1

func setup_multiplayer(player_peer_id: int):
	peer_id = player_peer_id
	is_local_player = (peer_id == multiplayer.get_unique_id())
#endregion

#region PROPERTY SETTERS
func _set_is_lying(value: bool):
	var old_lying = is_lying
	is_lying = value
	
	if old_lying != is_lying:
		emit_signal("lying_state_changed", is_lying)
		_apply_lying_visual_effects()

func _set_lying_angle(value: float):
	lying_angle = value
	
	if is_lying and sprite_system and sprite_system.has_method("set_lying_angle"):
		sprite_system.set_lying_angle(lying_angle)
#endregion

#region POSTURE CONTROL
func toggle_lying() -> bool:
	if not is_multiplayer_authority():
		return false
		
	if Time.get_ticks_msec() * 0.001 - last_lying_state_change < lying_state_change_cooldown:
		return false
	
	if do_after_component and do_after_component.is_performing_action():
		show_message("You're busy doing something else!")
		return false
	
	if is_lying:
		return get_up()
	else:
		return await lie_down()

func lie_down(forced: bool = false) -> bool:
	if not is_multiplayer_authority() and not forced:
		return false
	
	if not _can_change_posture(forced) or is_lying:
		return false
	
	# Check if lying down should use do_after
	if _should_use_do_after_for_lie_down():
		if not do_after_component:
			return _execute_lie_down(forced)
		
		var callback = Callable(self, "_execute_lie_down")
		var config_override = {
			"base_duration": _get_lie_down_duration(),
			"display_name": "lying down"
		}
		return do_after_component.start_posture_action("lie_down", callback.bind(forced))
	else:
		return _execute_lie_down(forced)

func _execute_lie_down(forced: bool = false) -> bool:
	if not _can_change_posture(forced) or is_lying:
		return false
	
	_perform_lie_down(forced)
	return true

func get_up(forced: bool = false) -> bool:
	if not is_multiplayer_authority() and not forced:
		return false
	
	if not _can_change_posture(forced) or not is_lying:
		return false
	
	if do_after_component and do_after_component.is_performing_action():
		show_message("You're busy doing something else!")
		return false
	
	if not can_stand_up() and not forced:
		return _attempt_struggle_to_stand()
	
	# Check if getting up should use do_after
	if _should_use_do_after_for_get_up():
		if not do_after_component:
			return _execute_get_up(forced)
		
		var callback = Callable(self, "_execute_get_up")
		var config_override = {
			"base_duration": _get_get_up_duration(),
			"display_name": "getting up"
		}
		return do_after_component.start_posture_action("get_up_injured", callback.bind(forced))
	else:
		return _execute_get_up(forced)

func _execute_get_up(forced: bool = false) -> bool:
	if not _can_change_posture(forced) or not is_lying:
		return false
	
	if not can_stand_up() and not forced:
		_handle_failed_standup()
		return false
	
	_perform_get_up(forced)
	return true

func _attempt_struggle_to_stand() -> bool:
	if not do_after_component:
		_handle_failed_standup()
		return false
	
	var callback = Callable(self, "_execute_struggle_standup")
	var config_override = {
		"base_duration": _get_struggle_duration(),
		"display_name": "struggling to get up",
		"can_be_interrupted_by_movement": false,
		"can_be_interrupted_by_damage": true
	}
	return do_after_component.start_action("struggle_standup", config_override, callback)

func _execute_struggle_standup() -> bool:
	if not is_lying:
		return false
	
	stand_up_attempts += 1
	
	var success_chance = _calculate_struggle_success_chance()
	
	if randf() * 100.0 < success_chance:
		show_message("You manage to struggle to your feet!")
		_perform_get_up(true)
		return true
	else:
		_handle_failed_standup()
		return false

func _calculate_struggle_success_chance() -> float:
	var base_chance = 20.0
	
	# Reduce chance based on health
	if health_system and "health" in health_system and "max_health" in health_system:
		var health_percent = health_system.health / health_system.max_health
		base_chance *= health_percent
	
	# Skill bonuses
	if skill_component:
		var endurance_level = skill_component.get_skill_level(skill_component.SKILL_ENDURANCE)
		base_chance += endurance_level * 10.0
	
	# Reduce chance with each attempt
	base_chance *= pow(0.7, stand_up_attempts)
	
	return clamp(base_chance, 5.0, 60.0)

func _should_use_do_after_for_lie_down() -> bool:
	# Use do_after when health is low or when in pain
	if health_system:
		if "health" in health_system and "max_health" in health_system:
			var health_percent = health_system.health / health_system.max_health
			if health_percent < 0.5:
				return true
		
		if "pain_level" in health_system and health_system.pain_level > 30:
			return true
	
	return false

func _should_use_do_after_for_get_up() -> bool:
	# Use do_after when injured, weak, or has limited mobility
	if not can_stand_up():
		return true
	
	if health_system:
		if "health" in health_system and "max_health" in health_system:
			var health_percent = health_system.health / health_system.max_health
			if health_percent < 0.7:
				return true
		
		if "staminaloss" in health_system and health_system.staminaloss > 50:
			return true
		
		if "pain_level" in health_system and health_system.pain_level > 40:
			return true
	
	# Check for leg injuries
	if _count_leg_fractures() > 0:
		return true
	
	return false

func _get_lie_down_duration() -> float:
	var base_duration = 1.5
	
	if health_system:
		if "pain_level" in health_system:
			base_duration += health_system.pain_level * 0.02
		
		if "health" in health_system and "max_health" in health_system:
			var health_percent = health_system.health / health_system.max_health
			if health_percent < 0.3:
				base_duration += 1.0
	
	return base_duration

func _get_get_up_duration() -> float:
	var base_duration = 2.0
	
	if health_system:
		if "health" in health_system and "max_health" in health_system:
			var health_percent = health_system.health / health_system.max_health
			base_duration += (1.0 - health_percent) * 3.0
		
		if "staminaloss" in health_system:
			base_duration += health_system.staminaloss * 0.03
		
		if "pain_level" in health_system:
			base_duration += health_system.pain_level * 0.04
	
	# Add time for leg injuries
	var leg_fractures = _count_leg_fractures()
	base_duration += leg_fractures * 2.0
	
	return base_duration

func _get_struggle_duration() -> float:
	var base_duration = 3.0 + (stand_up_attempts * 1.0)
	
	if health_system:
		if "health" in health_system and "max_health" in health_system:
			var health_percent = health_system.health / health_system.max_health
			base_duration += (1.0 - health_percent) * 4.0
	
	return base_duration

func force_stand_up():
	if is_lying:
		get_up(true)

func force_lie_down():
	if not is_lying:
		health_forced_lying = true
		lie_down(true)

func attempt_recovery_standup():
	if is_lying and health_forced_lying and can_stand_up():
		health_forced_lying = false
		get_up(true)
#endregion

#region CRAWLING MECHANICS
func can_crawl_in_direction(direction: Vector2i) -> bool:
	if not is_lying or not can_crawl or crawl_cooldown > 0:
		return false
	return true

func start_crawling_move(direction: Vector2i) -> bool:
	if not can_crawl_in_direction(direction):
		return false
	
	if do_after_component and do_after_component.is_performing_action():
		show_message("You're busy doing something else!")
		return false
	
	# Check if crawling should use do_after
	if _should_use_do_after_for_crawl():
		if not do_after_component:
			return _execute_crawl_move(direction)
		
		var callback = Callable(self, "_execute_crawl_move")
		var config_override = {
			"base_duration": _get_crawl_duration(),
			"display_name": "crawling",
			"prevent_movement": false,
			"can_be_interrupted_by_movement": false,
			"can_be_interrupted_by_damage": true
		}
		return do_after_component.start_action("crawling", config_override, callback.bind(direction))
	else:
		return _execute_crawl_move(direction)

func _execute_crawl_move(direction: Vector2i) -> bool:
	if not can_crawl_in_direction(direction):
		return false
	
	if controller.movement_component:
		var success = controller.movement_component.attempt_move(direction)
		if success:
			_handle_successful_crawl()
			return true
	
	return false

func _should_use_do_after_for_crawl() -> bool:
	# Use do_after when injured or in pain
	if health_system:
		if "health" in health_system and "max_health" in health_system:
			var health_percent = health_system.health / health_system.max_health
			if health_percent < 0.5:
				return true
		
		if "pain_level" in health_system and health_system.pain_level > 30:
			return true
	
	# Use do_after if arms are injured
	if _has_arm_injuries():
		return true
	
	return false

func _get_crawl_duration() -> float:
	var base_duration = 1.0
	
	if health_system:
		if "health" in health_system and "max_health" in health_system:
			var health_percent = health_system.health / health_system.max_health
			base_duration += (1.0 - health_percent) * 1.5
		
		if "pain_level" in health_system:
			base_duration += health_system.pain_level * 0.02
	
	# Arm injuries slow down crawling
	if _has_arm_injuries():
		base_duration += 0.5
	
	return base_duration

func _has_arm_injuries() -> bool:
	if not health_system:
		return false
	
	var arm_injuries = 0
	for limb_name in ["l_arm", "r_arm"]:
		if health_system.limbs.has(limb_name):
			var limb = health_system.limbs[limb_name]
			if limb.is_fractured or not limb.attached:
				arm_injuries += 1
	
	return arm_injuries > 0

func _handle_successful_crawl():
	crawl_cooldown = 1.0 / crawl_speed_multiplier
	
	if audio_system:
		audio_system.play_positioned_sound(crawl_sound, controller.position, 0.3)
	
	show_message("You crawl across the ground.")
	
	# Grant endurance experience
	if skill_component and skill_component.allow_skill_gain and randf() < 0.1:
		skill_component.increment_skill(skill_component.SKILL_ENDURANCE, 1, 2)

func start_crawling():
	if is_multiplayer_authority() and is_lying:
		is_crawling = true
		sync_crawl_state.rpc(true)

func stop_crawling():
	if is_multiplayer_authority():
		is_crawling = false
		sync_crawl_state.rpc(false)

func get_crawl_speed_modifier() -> float:
	return crawl_speed_multiplier if is_lying else 1.0
#endregion

#region STANDING ABILITY CHECKS
func can_stand_up() -> bool:
	return _check_health_requirements() and _check_limb_requirements() and _check_status_requirements()

func _check_health_requirements() -> bool:
	if not health_system:
		return true
	
	if health_system.health < (health_system.max_health * min_health_percentage_to_stand):
		return false
	
	if health_system.staminaloss > max_stamina_loss_to_stand:
		return false
	
	if health_system.pain_level > max_pain_level_to_stand:
		return false
	
	return true

func _check_limb_requirements() -> bool:
	if health_system:
		var leg_fractures = _count_leg_fractures()
		if leg_fractures > max_leg_fractures_to_stand:
			return false
	
	if limb_system:
		var has_leg = false
		if limb_system.has_method("has_limb"):
			has_leg = limb_system.has_limb("l_leg") or limb_system.has_limb("r_leg")
		if not has_leg:
			return false
	
	return true

func _check_status_requirements() -> bool:
	if not status_effect_manager:
		return true
	
	var restricting_effects = ["unconscious", "stunned"]
	for effect in restricting_effects:
		if health_system and health_system.status_effects.has(effect):
			return false
	
	if status_effect_manager.has_method("has_effect_flag"):
		return not status_effect_manager.has_effect_flag("movement_restricting")
	
	return true

func _count_leg_fractures() -> int:
	if not health_system:
		return 0
	
	var leg_fractures = 0
	for limb_name in ["l_leg", "r_leg"]:
		if health_system.limbs.has(limb_name):
			var limb = health_system.limbs[limb_name]
			if limb.is_fractured and not limb.is_splinted:
				leg_fractures += 1
			if not limb.attached:
				leg_fractures += 2
	
	return leg_fractures
#endregion

#region INTERNAL POSTURE OPERATIONS
func _can_change_posture(forced: bool) -> bool:
	if not forced and controller.movement_component:
		var movement = controller.movement_component
		if movement.is_moving or movement.is_stunned or movement.is_flying:
			return false
	
	if health_forced_lying and not forced:
		return false
	
	return true

func _perform_lie_down(forced: bool):
	is_lying = true
	last_lying_state_change = Time.get_ticks_msec() * 0.001
	
	if forced:
		forced_lying = true
	
	_stop_movement_if_needed()
	sync_lying_state.rpc(is_lying, lying_angle)
	_update_sprite_state(true)
	
	await _wait_for_animation()
	sync_posture_action.rpc("lie_down", true, "You lie down.")

func _perform_get_up(forced: bool):
	is_lying = false
	last_lying_state_change = Time.get_ticks_msec() * 0.001
	stand_up_attempts = 0
	forced_lying = false
	health_forced_lying = false
	
	_stop_movement_if_needed()
	sync_lying_state.rpc(is_lying, lying_angle)
	_update_sprite_state(false)
	sync_posture_action.rpc("get_up", true, "You get back up.")

func _stop_movement_if_needed():
	if controller.movement_component and controller.movement_component.is_moving:
		controller.movement_component.is_moving = false
		controller.movement_component.move_progress = 0.0
		controller.position = controller.movement_component.tile_to_world(
			controller.movement_component.current_tile_position
		)

func _update_sprite_state(lying: bool):
	if sprite_system:
		sprite_system.set_lying_state(lying, _get_current_direction())
		sprite_system._update_all_sprite_elements()

func _wait_for_animation():
	await controller.get_tree().create_timer(0.1).timeout

func _handle_failed_standup():
	if not is_multiplayer_authority():
		return
	
	stand_up_attempts += 1
	
	var messages = _get_standup_failure_messages()
	var message = messages[stand_up_attempts % messages.size()]
	
	if health_system and health_system.has_method("adjustStaminaLoss"):
		health_system.adjustStaminaLoss(5.0 * stand_up_attempts)
	
	if audio_system:
		audio_system.play_positioned_sound(struggle_sound, controller.position, 0.4)
	
	sync_posture_action.rpc("failed_standup", false, message)

func _get_standup_failure_messages() -> Array:
	if stand_up_attempts >= 3:
		return [
			"You're too weak to get up!",
			"Your body refuses to cooperate!",
			"You need help getting up!"
		]
	else:
		return [
			"You struggle to get up...",
			"You try to push yourself up, but fail.",
			"You can't seem to get up right now."
		]
#endregion

#region UTILITY FUNCTIONS
func get_stamina_recovery_bonus() -> float:
	return lying_stamina_recovery_bonus if is_lying else 1.0

func is_character_lying() -> bool:
	return is_lying

func get_lying_angle() -> float:
	return lying_angle

func handle_rest_toggle():
	if is_multiplayer_authority():
		emit_signal("rest_toggled")
		toggle_lying()

func set_lying_angle(angle: float):
	if is_multiplayer_authority():
		lying_angle = angle
		sync_lying_state.rpc(is_lying, lying_angle)

func _get_current_direction() -> int:
	if controller.movement_component:
		return controller.movement_component.current_direction
	return 2

func show_message(text: String):
	if sensory_system and is_local_player:
		sensory_system.display_message(text)
	elif is_local_player:
		print("PostureComponent: " + text)
#endregion

#region VISUAL EFFECTS
func _apply_lying_visual_effects():
	_update_sprite_state(is_lying)
	_update_z_index()
	
	if is_lying:
		_clear_sprite_rotation()

func _update_z_index():
	if controller.get_parent() and "z_index" in controller.get_parent():
		controller.get_parent().z_index = -1 if is_lying else 0

func _clear_sprite_rotation():
	if sprite_system and sprite_system.has_method("clear_rotation"):
		sprite_system.clear_rotation()

func apply_lying_effects():
	_apply_lying_visual_effects()

func remove_lying_effects():
	_update_z_index()
	
	if controller.movement_component and controller.movement_component.is_drifting:
		var movement_comp = controller.movement_component
		if sprite_system:
			sprite_system._set_rotation(movement_comp.spin_rotation)
#endregion

#region NETWORK SYNCHRONIZATION
@rpc("any_peer", "reliable", "call_local")
func sync_lying_state(lying: bool, angle: float):
	if not is_multiplayer_authority():
		is_lying = lying
		lying_angle = angle
		_apply_lying_visual_effects()

@rpc("any_peer", "reliable", "call_local")
func sync_posture_action(action: String, success: bool, message: String = ""):
	match action:
		"lie_down":
			if success:
				_play_posture_sound(body_fall_sound, fall_sound_volume)
				_show_posture_message(message)
		"get_up":
			if success:
				_play_posture_sound(rustle_sound, rustle_sound_volume)
				_show_posture_message(message)
			emit_signal("stand_up_attempted", success)
		"failed_standup":
			_show_posture_message(message)
			emit_signal("stand_up_attempted", false)

@rpc("any_peer", "reliable", "call_local")
func sync_crawl_state(crawling: bool):
	is_crawling = crawling
	emit_signal("crawl_state_changed", crawling)

func _play_posture_sound(sound_name: String, volume: float):
	if audio_system:
		audio_system.play_positioned_sound(sound_name, controller.position, volume)

func _show_posture_message(message: String):
	if message != "" and is_local_player:
		show_message(message)
#endregion
