extends Node
class_name DoAfterComponent

#region EXPORTS AND CONFIGURATION
@export_group("Animation Settings")
@export var default_spritesheet: Texture2D = null
@export var default_frame_count: int = 4
@export var animation_fps: float = 8.0
@export var show_visual_indicator: bool = true
@export var indicator_offset: Vector2 = Vector2(0, -32)
@export var indicator_scale: Vector2 = Vector2(1.0, 1.0)

@export_group("Timing Settings")
@export var base_duration: float = 3.0
@export var skill_modifier_strength: float = 0.2
@export var allow_skill_modifiers: bool = true
@export var minimum_duration: float = 0.1
@export var maximum_duration: float = 15.0

@export_group("Interruption Settings")
@export var can_be_interrupted_by_movement: bool = true
@export var can_be_interrupted_by_damage: bool = true
@export var can_be_interrupted_by_manual_cancel: bool = true
@export var movement_interruption_threshold: float = 0.1

@export_group("Skill Integration")
@export var use_cqc_for_combat_actions: bool = true
@export var use_medical_for_healing_actions: bool = true
@export var use_engineering_for_tech_actions: bool = true
@export var use_endurance_for_physical_actions: bool = true
@export var use_fireman_for_carry_actions: bool = true

@export_group("Movement Integration")
@export var prevent_movement_during_action: bool = true
@export var allow_facing_changes: bool = false
@export var interrupt_on_external_movement: bool = true

@export_group("Audio Settings")
@export var play_start_sound: bool = true
@export var play_progress_sounds: bool = false
@export var play_completion_sound: bool = true
@export var default_sound_volume: float = 0.3
#endregion

#region SIGNALS
signal do_after_started(action_name: String, duration: float)
signal do_after_progress(action_name: String, progress: float, remaining_time: float)
signal do_after_completed(action_name: String, success: bool)
signal do_after_cancelled(action_name: String, reason: String)
signal action_interrupted(action_name: String, interruption_source: String)
#endregion

#region PROPERTIES
# Current action state
var current_action: String = ""
var action_duration: float = 0.0
var action_progress: float = 0.0
var action_elapsed_time: float = 0.0
var is_active: bool = false
var action_data: Dictionary = {}

# Component references
var controller: Node = null
var skill_component: Node = null
var movement_component: Node = null
var grab_pull_component: Node = null
var item_interaction_component: Node = null
var interaction_component: Node = null
var weapon_handling_component: Node = null
var posture_component: Node = null
var health_system: Node = null
var sensory_system = null
var audio_system = null

# Visual feedback
var sprite_node: Sprite2D = null
var animation_texture: Texture2D = null
var frame_count: int = 0
var current_frame: int = 0
var frame_timer: float = 0.0
var frame_duration: float = 0.0

# Interruption tracking
var initial_position: Vector2i = Vector2i.ZERO
var movement_blocked: bool = false
var original_movement_state: bool = false
var action_callback: Callable
var action_target: Node = null

# Network state
var is_local_player: bool = false
var peer_id: int = 1

# Action configuration registry
var action_configs: Dictionary = {}
#endregion

#region INITIALIZATION
func initialize(init_data: Dictionary):
	controller = init_data.get("controller")
	skill_component = init_data.get("skill_component")
	sensory_system = init_data.get("sensory_system")
	audio_system = init_data.get("audio_system")
	health_system = init_data.get("health_system")
	is_local_player = init_data.get("is_local_player", false)
	peer_id = init_data.get("peer_id", 1)
	
	_connect_components()
	_setup_visual_indicator()
	_connect_component_signals()
	_register_default_action_configs()

func _connect_components():
	if controller:
		movement_component = controller.get_node_or_null("MovementComponent")
		grab_pull_component = controller.get_node_or_null("GrabPullComponent")
		item_interaction_component = controller.get_node_or_null("ItemInteractionComponent")
		interaction_component = controller.get_node_or_null("InteractionComponent")
		weapon_handling_component = controller.get_node_or_null("WeaponHandlingComponent")
		posture_component = controller.get_node_or_null("PostureComponent")

func _setup_visual_indicator():
	if not show_visual_indicator:
		return
	
	sprite_node = Sprite2D.new()
	sprite_node.name = "DoAfterIndicator"
	sprite_node.visible = false
	sprite_node.scale = indicator_scale
	
	if controller:
		controller.add_child(sprite_node)
	else:
		add_child(sprite_node)

func _connect_component_signals():
	if movement_component and can_be_interrupted_by_movement:
		if movement_component.has_signal("movement_attempt"):
			if not movement_component.movement_attempt.is_connected(_on_movement_attempt):
				movement_component.movement_attempt.connect(_on_movement_attempt)
		
		if movement_component.has_signal("tile_changed"):
			if not movement_component.tile_changed.is_connected(_on_tile_changed):
				movement_component.tile_changed.connect(_on_tile_changed)
	
	if health_system and can_be_interrupted_by_damage:
		if health_system.has_signal("took_damage"):
			if not health_system.took_damage.is_connected(_on_took_damage):
				health_system.took_damage.connect(_on_took_damage)
	
	if grab_pull_component:
		if grab_pull_component.has_signal("grab_released"):
			if not grab_pull_component.grab_released.is_connected(_on_grab_released):
				grab_pull_component.grab_released.connect(_on_grab_released)

func _register_default_action_configs():
	# Medical actions
	register_action_config("cpr", {
		"base_duration": 8.0,
		"skill_name": "medical",
		"spritesheet": default_spritesheet,
		"frame_count": default_frame_count,
		"prevent_movement": true,
		"can_be_interrupted_by_movement": true,
		"can_be_interrupted_by_damage": true,
		"sound_start": "medical_start",
		"sound_complete": "medical_complete"
	})
	
	register_action_config("surgery", {
		"base_duration": 15.0,
		"skill_name": "surgery",
		"spritesheet": default_spritesheet,
		"frame_count": default_frame_count,
		"prevent_movement": true,
		"can_be_interrupted_by_movement": true,
		"can_be_interrupted_by_damage": true,
		"sound_start": "surgery_start",
		"sound_complete": "surgery_complete"
	})
	
	register_action_config("apply_bandage", {
		"base_duration": 3.0,
		"skill_name": "medical",
		"spritesheet": default_spritesheet,
		"frame_count": default_frame_count,
		"prevent_movement": false,
		"sound_start": "bandage_start",
		"sound_complete": "bandage_complete"
	})
	
	# Physical actions
	register_action_config("fireman_carry", {
		"base_duration": 4.0,
		"skill_name": "fireman",
		"spritesheet": default_spritesheet,
		"frame_count": default_frame_count,
		"prevent_movement": true,
		"can_be_interrupted_by_movement": true,
		"can_be_interrupted_by_damage": true,
		"sound_start": "lift_start",
		"sound_complete": "lift_complete"
	})
	
	register_action_config("climb_table", {
		"base_duration": 2.5,
		"skill_name": "endurance",
		"spritesheet": default_spritesheet,
		"frame_count": default_frame_count,
		"prevent_movement": true,
		"sound_start": "climb_start",
		"sound_complete": "climb_complete"
	})
	
	register_action_config("crawling", {
		"base_duration": 1.0,
		"skill_name": "endurance",
		"spritesheet": default_spritesheet,
		"frame_count": default_frame_count,
		"prevent_movement": false,
		"can_be_interrupted_by_damage": true,
		"sound_start": "crawl_start",
		"sound_complete": "crawl_complete"
	})
	
	# Combat actions
	register_action_config("grab_upgrade", {
		"base_duration": 2.0,
		"skill_name": "cqc",
		"spritesheet": default_spritesheet,
		"frame_count": default_frame_count,
		"prevent_movement": false,
		"can_be_interrupted_by_movement": false,
		"can_be_interrupted_by_damage": true,
		"sound_start": "grab_tighten",
		"sound_complete": "grab_success"
	})
	
	register_action_config("disarm_attempt", {
		"base_duration": 1.5,
		"skill_name": "cqc",
		"spritesheet": default_spritesheet,
		"frame_count": default_frame_count,
		"prevent_movement": false,
		"can_be_interrupted_by_movement": true,
		"can_be_interrupted_by_damage": true,
		"sound_start": "disarm_start",
		"sound_complete": "disarm_complete"
	})
	
	# Engineering actions
	register_action_config("welding", {
		"base_duration": 5.0,
		"skill_name": "engineer",
		"spritesheet": default_spritesheet,
		"frame_count": default_frame_count,
		"prevent_movement": true,
		"can_be_interrupted_by_movement": true,
		"can_be_interrupted_by_damage": true,
		"sound_start": "weld_start",
		"sound_complete": "weld_complete"
	})
	
	register_action_config("construct", {
		"base_duration": 6.0,
		"skill_name": "construction",
		"spritesheet": default_spritesheet,
		"frame_count": default_frame_count,
		"prevent_movement": true,
		"can_be_interrupted_by_movement": true,
		"can_be_interrupted_by_damage": true,
		"sound_start": "construct_start",
		"sound_complete": "construct_complete"
	})
	
	# Weapon actions
	register_action_config("reload_weapon", {
		"base_duration": 2.0,
		"skill_name": "firearms",
		"spritesheet": default_spritesheet,
		"frame_count": default_frame_count,
		"prevent_movement": false,
		"can_be_interrupted_by_movement": true,
		"can_be_interrupted_by_damage": true,
		"sound_start": "reload_start",
		"sound_complete": "reload_complete"
	})
	
	register_action_config("chamber_round", {
		"base_duration": 1.0,
		"skill_name": "firearms",
		"spritesheet": default_spritesheet,
		"frame_count": default_frame_count,
		"prevent_movement": false,
		"sound_start": "chamber_start",
		"sound_complete": "chamber_complete"
	})
	
	# Item usage actions
	register_action_config("use_complex_item", {
		"base_duration": 3.0,
		"skill_name": "",
		"spritesheet": default_spritesheet,
		"frame_count": default_frame_count,
		"prevent_movement": false,
		"can_be_interrupted_by_movement": true,
		"can_be_interrupted_by_damage": true,
		"sound_start": "item_use_start",
		"sound_complete": "item_use_complete"
	})
	
	# Posture actions
	register_action_config("get_up_injured", {
		"base_duration": 3.0,
		"skill_name": "endurance",
		"spritesheet": default_spritesheet,
		"frame_count": default_frame_count,
		"prevent_movement": true,
		"can_be_interrupted_by_damage": true,
		"sound_start": "struggle_start",
		"sound_complete": "struggle_complete"
	})
#endregion

#region ACTION MANAGEMENT
func start_action(action_name: String, config_override: Dictionary = {}, callback: Callable = Callable(), target: Node = null) -> bool:
	if is_active:
		show_message("You're already busy doing something!")
		return false
	
	if not action_configs.has(action_name):
		push_warning("DoAfterComponent: No configuration found for action: " + action_name)
		return false
	
	var config = action_configs[action_name].duplicate()
	
	# Apply any override configuration
	for key in config_override:
		config[key] = config_override[key]
	
	# Calculate duration with skill modifiers
	var duration = _calculate_action_duration(action_name, config)
	
	if duration <= 0:
		return false
	
	action_callback = callback
	action_target = target
	
	_begin_action(action_name, duration, config)
	return true

func start_instant_action(action_name: String, callback: Callable = Callable(), target: Node = null) -> bool:
	if callback.is_valid():
		callback.call()
	return true

func cancel_action(reason: String = "manual") -> bool:
	if not is_active:
		return false
	
	_end_action(false, reason)
	return true

func force_complete_action() -> bool:
	if not is_active:
		return false
	
	_end_action(true)
	return true

func _begin_action(action_name: String, duration: float, config: Dictionary):
	current_action = action_name
	action_duration = duration
	action_progress = 0.0
	action_elapsed_time = 0.0
	is_active = true
	action_data = config
	
	# Store initial state for interruption detection
	if movement_component:
		initial_position = movement_component.current_tile_position
	
	# Block movement if required
	if config.get("prevent_movement", prevent_movement_during_action):
		_block_movement()
	
	# Setup visual indicator
	_setup_action_visual(config)
	
	# Play start sound
	if play_start_sound and config.has("sound_start"):
		_play_action_sound(config["sound_start"])
	
	# Show start message
	var action_display = config.get("display_name", action_name.replace("_", " "))
	show_message("You begin " + action_display + "...")
	
	emit_signal("do_after_started", action_name, duration)
	
	if multiplayer.is_server():
		sync_action_start.rpc(action_name, duration, config)

func _end_action(success: bool, reason: String = ""):
	if not is_active:
		return
	
	var completed_action = current_action
	var was_cancelled = not success
	var callback = action_callback
	var target = action_target
	
	# Cleanup visual indicator
	_cleanup_action_visual()
	
	# Restore movement
	if movement_blocked:
		_unblock_movement()
	
	# Play completion sound
	if success and play_completion_sound and action_data.has("sound_complete"):
		_play_action_sound(action_data["sound_complete"])
	
	# Show completion message
	if success:
		var action_display = action_data.get("display_name", completed_action.replace("_", " "))
		show_message("You finish " + action_display + ".")
	else:
		if reason != "":
			show_message("Your action was interrupted: " + reason)
		else:
			show_message("Your action was cancelled.")
	
	# Reset state
	current_action = ""
	action_duration = 0.0
	action_progress = 0.0
	action_elapsed_time = 0.0
	is_active = false
	action_data.clear()
	action_callback = Callable()
	action_target = null
	
	# Execute callback if successful
	if success and callback.is_valid():
		if target:
			callback.call(target)
		else:
			callback.call()
	
	# Emit completion signal
	if was_cancelled:
		emit_signal("do_after_cancelled", completed_action, reason)
	else:
		emit_signal("do_after_completed", completed_action, success)
	
	if multiplayer.is_server():
		sync_action_end.rpc(completed_action, success, reason)
#endregion

#region COMPONENT INTEGRATION METHODS
func start_medical_action(action_type: String, target: Node = null, callback: Callable = Callable()) -> bool:
	var config_override = {}
	if target:
		config_override["target"] = target
		config_override["display_name"] = action_type + " on " + _get_entity_name(target)
	
	return start_action(action_type, config_override, callback, target)

func start_combat_action(action_type: String, target: Node = null, callback: Callable = Callable()) -> bool:
	var config_override = {}
	if target:
		config_override["target"] = target
		config_override["display_name"] = action_type + " " + _get_entity_name(target)
	
	return start_action(action_type, config_override, callback, target)

func start_fireman_carry_action(target: Node, callback: Callable = Callable()) -> bool:
	if not target or not grab_pull_component:
		return false
	
	var config_override = {
		"target": target,
		"display_name": "fireman carry of " + _get_entity_name(target)
	}
	
	return start_action("fireman_carry", config_override, callback, target)

func start_grab_upgrade_action(callback: Callable = Callable()) -> bool:
	if not grab_pull_component or not grab_pull_component.grabbing_entity:
		return false
	
	var target = grab_pull_component.grabbing_entity
	var config_override = {
		"target": target,
		"display_name": "tightening grip on " + _get_entity_name(target)
	}
	
	return start_action("grab_upgrade", config_override, callback, target)

func start_posture_action(action_type: String, callback: Callable = Callable()) -> bool:
	if not posture_component:
		return false
	
	return start_action(action_type, {}, callback)

func start_weapon_action(action_type: String, weapon: Node, callback: Callable = Callable()) -> bool:
	if not weapon_handling_component or not weapon:
		return false
	
	var config_override = {
		"target": weapon,
		"display_name": action_type + " " + _get_weapon_name(weapon)
	}
	
	return start_action(action_type, config_override, callback, weapon)

func start_item_action(action_type: String, item: Node, callback: Callable = Callable()) -> bool:
	if not item_interaction_component or not item:
		return false
	
	var config_override = {
		"target": item,
		"display_name": "using " + _get_item_name(item)
	}
	
	return start_action(action_type, config_override, callback, item)

func start_engineering_action(action_type: String, target: Node = null, callback: Callable = Callable()) -> bool:
	var config_override = {}
	if target:
		config_override["target"] = target
		config_override["display_name"] = action_type + " " + _get_entity_name(target)
	
	return start_action(action_type, config_override, callback, target)
#endregion

#region DURATION CALCULATION
func _calculate_action_duration(action_name: String, config: Dictionary) -> float:
	var base_time = config.get("base_duration", base_duration)
	
	if not allow_skill_modifiers or not skill_component:
		return clamp(base_time, minimum_duration, maximum_duration)
	
	var skill_name = config.get("skill_name", "")
	if skill_name == "":
		skill_name = _determine_skill_for_action(action_name)
	
	if skill_name == "":
		return clamp(base_time, minimum_duration, maximum_duration)
	
	var skill_level = skill_component.get_skill_level(skill_name)
	var modifier = 1.0 - (skill_level * skill_modifier_strength)
	modifier = clamp(modifier, 0.1, 2.0)
	
	# Apply health/condition modifiers
	modifier *= _get_condition_modifier(action_name)
	
	var final_duration = base_time * modifier
	return clamp(final_duration, minimum_duration, maximum_duration)

func _determine_skill_for_action(action_name: String) -> String:
	var action_lower = action_name.to_lower()
	
	# Medical actions
	if use_medical_for_healing_actions and ("cpr" in action_lower or "heal" in action_lower or "medical" in action_lower or "bandage" in action_lower):
		return skill_component.SKILL_MEDICAL if skill_component else ""
	
	if "surgery" in action_lower:
		return skill_component.SKILL_SURGERY if skill_component else ""
	
	# Physical actions
	if use_fireman_for_carry_actions and ("carry" in action_lower or "fireman" in action_lower):
		return skill_component.SKILL_FIREMAN if skill_component else ""
	
	if use_endurance_for_physical_actions and ("climb" in action_lower or "crawl" in action_lower or "physical" in action_lower or "get_up" in action_lower):
		return skill_component.SKILL_ENDURANCE if skill_component else ""
	
	# Technical actions
	if use_engineering_for_tech_actions and ("weld" in action_lower or "repair" in action_lower or "construct" in action_lower or "engineer" in action_lower):
		return skill_component.SKILL_ENGINEER if skill_component else ""
	
	if "construct" in action_lower:
		return skill_component.SKILL_CONSTRUCTION if skill_component else ""
	
	# Combat actions
	if use_cqc_for_combat_actions and ("combat" in action_lower or "fight" in action_lower or "grab" in action_lower or "disarm" in action_lower):
		return skill_component.SKILL_CQC if skill_component else ""
	
	# Weapon actions
	if "reload" in action_lower or "chamber" in action_lower or "firearm" in action_lower:
		return skill_component.SKILL_FIREARMS if skill_component else ""
	
	return ""

func _get_condition_modifier(action_name: String) -> float:
	var modifier = 1.0
	
	if not health_system:
		return modifier
	
	# Health-based modifiers
	if "health" in health_system and "max_health" in health_system:
		var health_percent = health_system.health / health_system.max_health
		if health_percent < 0.5:
			modifier *= 1.0 + (1.0 - health_percent) * 0.5
	
	# Stamina loss modifier
	if "staminaloss" in health_system:
		var stamina_penalty = health_system.staminaloss / 100.0
		modifier *= 1.0 + stamina_penalty * 0.3
	
	# Pain modifier
	if "pain_level" in health_system:
		var pain_penalty = health_system.pain_level / 100.0
		modifier *= 1.0 + pain_penalty * 0.4
	
	# Lying state modifier for certain actions
	if posture_component and posture_component.is_lying:
		var action_lower = action_name.to_lower()
		if "medical" in action_lower or "use" in action_lower:
			modifier *= 1.2  # Slower when lying
		elif "crawl" in action_lower:
			modifier *= 0.8  # Faster crawling
	
	return modifier
#endregion

#region PROCESSING
func _process(delta: float):
	if not is_active:
		return
	
	action_elapsed_time += delta
	action_progress = action_elapsed_time / action_duration
	
	# Update visual animation
	_update_visual_animation(delta)
	
	# Emit progress signal
	var remaining_time = action_duration - action_elapsed_time
	emit_signal("do_after_progress", current_action, action_progress, remaining_time)
	
	# Check for completion
	if action_progress >= 1.0:
		_end_action(true)
		return
	
	# Check for interruptions
	_check_for_interruptions()

func _update_visual_animation(delta: float):
	if not sprite_node or not sprite_node.visible:
		return
	
	if frame_count <= 1:
		return
	
	frame_timer += delta
	
	if frame_timer >= frame_duration:
		frame_timer = 0.0
		current_frame = (current_frame + 1) % frame_count
		_update_sprite_frame()

func _check_for_interruptions():
	# Check action-specific interruption settings
	var can_interrupt_movement = action_data.get("can_be_interrupted_by_movement", can_be_interrupted_by_movement)
	var can_interrupt_damage = action_data.get("can_be_interrupted_by_damage", can_be_interrupted_by_damage)
	
	# Check for movement-based interruptions
	if can_interrupt_movement and movement_component:
		var current_pos = movement_component.current_tile_position
		if current_pos != initial_position:
			var distance = (Vector2(current_pos) - Vector2(initial_position)).length()
			if distance >= movement_interruption_threshold:
				_end_action(false, "movement")
				return
	
	# Check for target-based interruptions
	if action_target and not is_instance_valid(action_target):
		_end_action(false, "target lost")
		return
	
	# Check for grab-based action interruptions
	if grab_pull_component and current_action in ["grab_upgrade", "fireman_carry"]:
		if not grab_pull_component.grabbing_entity:
			_end_action(false, "grip lost")
			return
#endregion

#region VISUAL FEEDBACK
func _setup_action_visual(config: Dictionary):
	if not show_visual_indicator or not sprite_node:
		return
	
	# Set up spritesheet
	var spritesheet = config.get("spritesheet", default_spritesheet)
	var frames = config.get("frame_count", default_frame_count)
	
	if spritesheet:
		animation_texture = spritesheet
		frame_count = frames
		current_frame = 0
		frame_timer = 0.0
		frame_duration = 1.0 / animation_fps
		
		sprite_node.texture = animation_texture
		sprite_node.position = indicator_offset
		sprite_node.visible = true
		
		_update_sprite_frame()

func _update_sprite_frame():
	if not sprite_node or not animation_texture or frame_count <= 1:
		return
	
	var texture_width = animation_texture.get_width()
	var texture_height = animation_texture.get_height()
	var frame_width = texture_width / frame_count
	var frame_height = texture_height
	
	var frame_x = current_frame * frame_width
	var region = Rect2(frame_x, 0, frame_width, frame_height)
	
	# Create AtlasTexture for the current frame
	var atlas_texture = AtlasTexture.new()
	atlas_texture.atlas = animation_texture
	atlas_texture.region = region
	
	sprite_node.texture = atlas_texture

func _cleanup_action_visual():
	if sprite_node:
		sprite_node.visible = false
		sprite_node.texture = null
	
	animation_texture = null
	frame_count = 0
	current_frame = 0
	frame_timer = 0.0
#endregion

#region MOVEMENT INTEGRATION
func _block_movement():
	if not movement_component or movement_blocked:
		return
	
	movement_blocked = true
	
	# Store original state and disable movement
	if movement_component.has_method("set_movement_blocked"):
		movement_component.set_movement_blocked(true)
	elif "movement_blocked" in movement_component:
		original_movement_state = movement_component.movement_blocked
		movement_component.movement_blocked = true

func _unblock_movement():
	if not movement_component or not movement_blocked:
		return
	
	movement_blocked = false
	
	# Restore original movement state
	if movement_component.has_method("set_movement_blocked"):
		movement_component.set_movement_blocked(false)
	elif "movement_blocked" in movement_component:
		movement_component.movement_blocked = original_movement_state
#endregion

#region CONFIGURATION MANAGEMENT
func register_action_config(action_name: String, config: Dictionary):
	action_configs[action_name] = config

func get_action_config(action_name: String) -> Dictionary:
	return action_configs.get(action_name, {})

func has_action_config(action_name: String) -> bool:
	return action_configs.has(action_name)

func remove_action_config(action_name: String):
	action_configs.erase(action_name)

func update_action_config(action_name: String, new_config: Dictionary):
	if action_configs.has(action_name):
		action_configs[action_name].merge(new_config)
	else:
		action_configs[action_name] = new_config
#endregion

#region SIGNAL HANDLERS
func _on_movement_attempt(direction: Vector2i):
	if not is_active:
		return
	
	var can_interrupt = action_data.get("can_be_interrupted_by_movement", can_be_interrupted_by_movement)
	if not can_interrupt:
		return
	
	if interrupt_on_external_movement:
		_end_action(false, "attempted movement")

func _on_tile_changed(old_tile: Vector2i, new_tile: Vector2i):
	if not is_active:
		return
	
	# This is handled in _check_for_interruptions()

func _on_took_damage(damage_amount: float, damage_type: String):
	if not is_active:
		return
	
	var can_interrupt = action_data.get("can_be_interrupted_by_damage", can_be_interrupted_by_damage)
	if not can_interrupt:
		return
	
	_end_action(false, "took damage")

func _on_grab_released(entity: Node):
	if not is_active:
		return
	
	if current_action in ["grab_upgrade", "fireman_carry"] and action_target == entity:
		_end_action(false, "grip released")
#endregion

#region PUBLIC INTERFACE
func is_performing_action() -> bool:
	return is_active

func get_current_action() -> String:
	return current_action

func get_action_progress() -> float:
	return action_progress

func get_remaining_time() -> float:
	if not is_active:
		return 0.0
	return action_duration - action_elapsed_time

func get_action_duration() -> float:
	return action_duration

func can_start_new_action() -> bool:
	return not is_active

func get_action_target() -> Node:
	return action_target

func should_block_movement() -> bool:
	if not is_active:
		return false
	return action_data.get("prevent_movement", prevent_movement_during_action)

func should_block_interactions() -> bool:
	if not is_active:
		return false
	return action_data.get("block_interactions", false)
#endregion

#region UTILITY FUNCTIONS
func _get_entity_name(entity: Node) -> String:
	if "entity_name" in entity and entity.entity_name != "":
		return entity.entity_name
	elif "name" in entity:
		return entity.name
	else:
		return "something"

func _get_weapon_name(weapon: Node) -> String:
	if "item_name" in weapon and weapon.item_name != "":
		return weapon.item_name
	elif "name" in weapon:
		return weapon.name
	else:
		return "weapon"

func _get_item_name(item: Node) -> String:
	if "item_name" in item and item.item_name != "":
		return item.item_name
	elif "name" in item:
		return item.name
	else:
		return "item"

func _play_action_sound(sound_name: String):
	if audio_system and audio_system.has_method("play_positioned_sound"):
		var position = controller.position if controller else Vector2.ZERO
		audio_system.play_positioned_sound(sound_name, position, default_sound_volume)

func show_message(text: String):
	if sensory_system and sensory_system.has_method("display_message"):
		sensory_system.display_message(text)
#endregion

#region NETWORK SYNCHRONIZATION
@rpc("any_peer", "call_local", "reliable")
func sync_action_start(action_name: String, duration: float, config: Dictionary):
	if not multiplayer.is_server():
		_begin_action(action_name, duration, config)

@rpc("any_peer", "call_local", "reliable")
func sync_action_end(action_name: String, success: bool, reason: String):
	if not multiplayer.is_server():
		if is_active and current_action == action_name:
			_end_action(success, reason)

@rpc("any_peer", "call_local", "reliable")
func sync_action_progress(action_name: String, progress: float):
	if not multiplayer.is_server():
		if is_active and current_action == action_name:
			action_progress = progress
			action_elapsed_time = progress * action_duration
#endregion
