extends Node
class_name AlienSpriteSystem

@export_group("Animation Configuration")
@export var alien_type: String = "basic_hunter"
@export var animation_speed_multiplier: float = 1.0
@export var auto_play_animations: bool = true
@export var loop_idle_animations: bool = true
@export var smooth_transitions: bool = true

@export_group("Appearance Settings")
@export var sprite_scale: Vector2 = Vector2(1, 1)
@export var sprite_offset: Vector2 = Vector2.ZERO
@export var base_modulate: Color = Color.WHITE
@export var stun_modulate: Color = Color(1, 1, 0.7, 0.9)

@export_group("Animation Timing")
@export var idle_animation_delay: float = 3.0
@export var movement_animation_speed: float = 1.2
@export var idle_animation_speed: float = 0.8
@export var death_animation_speed: float = 0.6
@export var stun_animation_speed: float = 0.5

@export_group("Visual Effects")
@export var enable_damage_flash: bool = true
@export var damage_flash_duration: float = 0.2
@export var damage_flash_color: Color = Color.RED
@export var enable_stealth_transparency: bool = true
@export var stealth_alpha: float = 0.3
@export var status_effect_overlays: bool = true

@export_group("Performance")
@export var update_frequency: float = 0.1
@export var animation_culling_enabled: bool = true
@export var culling_distance: float = 800.0
@export var reduce_animations_when_distant: bool = true

enum AnimationState {
	IDLE,
	MOVING,
	STUNNED,
	DEAD,
	RESTING,
	ATTACKING,
	SPECIAL,
	GIBBED
}

enum Direction {
	SOUTH = 0,
	NORTH = 1,
	EAST = 2,
	WEST = 3
}

const ANIMATION_NAMES = {
	"Drone": {
		"idle_south": "idle_south",
		"idle_north": "idle_north", 
		"idle_east": "idle_east",
		"idle_west": "idle_west",
		"move_south": "walk_south",
		"move_north": "walk_north",
		"move_east": "walk_east", 
		"move_west": "walk_west",
		"stunned": "stunned",
		"dead": "dead",
		"rest": "rest",
		"attack": "attack",
		"gib": "gib"
	},
	"stealth_hunter": {
		"idle_south": "stealth_idle_south",
		"idle_north": "stealth_idle_north",
		"idle_east": "stealth_idle_east", 
		"idle_west": "stealth_idle_west",
		"move_south": "stealth_walk_south",
		"move_north": "stealth_walk_north",
		"move_east": "stealth_walk_east",
		"move_west": "stealth_walk_west",
		"stunned": "stealth_stunned",
		"dead": "stealth_dead",
		"rest": "stealth_rest",
		"attack": "stealth_attack",
		"gib": "stealth_gib"
	}
}

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
var backup_animated_sprite: AnimatedSprite2D = null

var controller: Node = null
var movement_component: Node = null
var health_system: Node = null

var current_animation_state: AnimationState = AnimationState.IDLE
var current_direction: Direction = Direction.SOUTH
var current_animation_name: String = ""
var is_dead: bool = false
var is_stunned: bool = false
var is_resting: bool = false
var is_moving: bool = false

var idle_timer: float = 0.0
var last_movement_time: float = 0.0
var animation_queue: Array[String] = []
var is_playing_special_animation: bool = false

var damage_flash_timer: float = 0.0
var original_modulate: Color = Color.WHITE
var is_stealthed: bool = false
var current_alpha: float = 1.0

var update_timer: float = 0.0
var is_visible_on_screen: bool = true
var distance_to_camera: float = 0.0

func initialize(init_data: Dictionary):
	controller = init_data.get("controller")
	movement_component = init_data.get("movement_component")
	
	alien_type = init_data.get("alien_type", alien_type)
	
	_find_sprite_nodes()
	_setup_sprite_properties()
	_setup_signal_connections()
	_set_initial_animation()

func _find_sprite_nodes():
	animated_sprite = get_node_or_null("AnimatedSprite2D")
	
	if not animated_sprite and controller:
		animated_sprite = controller.get_node_or_null("AnimatedSprite2D")
	
	if not animated_sprite:
		animated_sprite = get_parent().get_node_or_null("AnimatedSprite2D")
		
		if not animated_sprite:
			_create_animated_sprite()

func _create_animated_sprite():
	animated_sprite = AnimatedSprite2D.new()
	animated_sprite.name = "AnimatedSprite2D"
	
	if controller:
		controller.add_child(animated_sprite)
	else:
		add_child(animated_sprite)

func _setup_sprite_properties():
	if not animated_sprite:
		return
	
	animated_sprite.scale = sprite_scale
	animated_sprite.offset = sprite_offset
	animated_sprite.modulate = base_modulate
	
	original_modulate = base_modulate

func _setup_signal_connections():
	if movement_component:
		if movement_component.has_signal("direction_changed") and not movement_component.direction_changed.is_connected(_on_direction_changed):
			movement_component.direction_changed.connect(_on_direction_changed)
		
		if movement_component.has_signal("state_changed") and not movement_component.state_changed.is_connected(_on_movement_state_changed):
			movement_component.state_changed.connect(_on_movement_state_changed)
	
	if controller:
		if controller.has_signal("ai_state_changed") and not controller.ai_state_changed.is_connected(_on_ai_state_changed):
			controller.ai_state_changed.connect(_on_ai_state_changed)
		
		if controller.has_signal("stealth_mode_changed") and not controller.stealth_mode_changed.is_connected(_on_stealth_mode_changed):
			controller.stealth_mode_changed.connect(_on_stealth_mode_changed)

func _set_initial_animation():
	current_direction = Direction.SOUTH
	current_animation_state = AnimationState.IDLE
	_update_animation()

func _process(delta: float):
	if is_dead:
		return
	
	update_timer += delta
	
	if update_timer >= update_frequency:
		_update_visual_effects(delta)
		_update_performance_tracking()
		_process_animation_queue()
		update_timer = 0.0
	
	_update_timers(delta)

func _update_timers(delta: float):
	if is_dead:
		return
	
	if current_animation_state == AnimationState.IDLE:
		idle_timer += delta
	else:
		idle_timer = 0.0
	
	if damage_flash_timer > 0:
		damage_flash_timer -= delta
		if damage_flash_timer <= 0:
			_end_damage_flash()
	
	if is_moving:
		last_movement_time = Time.get_ticks_msec() / 1000.0

func _update_visual_effects(delta: float):
	if not animated_sprite or is_dead:
		return
	
	if is_stealthed and enable_stealth_transparency:
		current_alpha = lerp(current_alpha, stealth_alpha, delta * 3.0)
	else:
		current_alpha = lerp(current_alpha, 1.0, delta * 3.0)
	
	if abs(animated_sprite.modulate.a - current_alpha) > 0.01:
		var current_modulate = animated_sprite.modulate
		current_modulate.a = current_alpha
		animated_sprite.modulate = current_modulate

func _update_performance_tracking():
	if not animation_culling_enabled:
		return
	
	var camera = get_viewport().get_camera_2d()
	if camera and controller:
		distance_to_camera = camera.global_position.distance_to(controller.global_position)
		is_visible_on_screen = distance_to_camera <= culling_distance
		
		if reduce_animations_when_distant and distance_to_camera > culling_distance * 0.7:
			_set_reduced_animations()

func _set_reduced_animations():
	if animated_sprite and animated_sprite.is_playing() and not is_dead:
		animated_sprite.speed_scale = 0.5

func _process_animation_queue():
	if animation_queue.is_empty() or is_playing_special_animation or is_dead:
		return
	
	var next_animation = animation_queue.pop_front()
	_play_animation_immediate(next_animation)

func set_direction(direction: int):
	if is_dead:
		return
	
	var new_direction = _convert_direction(direction)
	
	if new_direction != current_direction:
		current_direction = new_direction
		_update_animation()

func set_animation_state(state_name: String):
	if is_dead:
		return
	
	var new_state = _get_animation_state_from_name(state_name)
	
	if new_state != current_animation_state:
		current_animation_state = new_state
		_update_animation()

func _convert_direction(movement_direction: int) -> Direction:
	match movement_direction:
		0: return Direction.NORTH
		1: return Direction.EAST
		2: return Direction.SOUTH
		3: return Direction.WEST
		_: return Direction.SOUTH

func _get_animation_state_from_name(state_name: String) -> AnimationState:
	match state_name.to_lower():
		"idle": return AnimationState.IDLE
		"moving": return AnimationState.MOVING
		"stunned": return AnimationState.STUNNED
		"dead": return AnimationState.DEAD
		"resting", "rest": return AnimationState.RESTING
		"attacking", "attack": return AnimationState.ATTACKING
		_: return AnimationState.IDLE

func _update_animation():
	if not animated_sprite or not is_visible_on_screen or is_dead:
		return
	
	var animation_name = _get_animation_name()
	
	if animation_name != current_animation_name:
		_play_animation(animation_name)

func _get_animation_name() -> String:
	var direction_suffix = _get_direction_suffix(current_direction)
	var animation_key = ""
	
	match current_animation_state:
		AnimationState.IDLE:
			animation_key = "idle_" + direction_suffix
		AnimationState.MOVING:
			animation_key = "move_" + direction_suffix
		AnimationState.STUNNED:
			animation_key = "stunned"
		AnimationState.DEAD:
			animation_key = "dead"
		AnimationState.GIBBED:
			animation_key = "gib"
		AnimationState.RESTING:
			animation_key = "rest"
		AnimationState.ATTACKING:
			animation_key = "attack"
		_:
			animation_key = "idle_" + direction_suffix
	
	return _get_mapped_animation_name(animation_key)

func _get_direction_suffix(direction: Direction) -> String:
	match direction:
		Direction.NORTH: return "north"
		Direction.SOUTH: return "south"
		Direction.EAST: return "east"
		Direction.WEST: return "west"
		_: return "south"

func _get_mapped_animation_name(animation_key: String) -> String:
	if ANIMATION_NAMES.has(alien_type) and ANIMATION_NAMES[alien_type].has(animation_key):
		return ANIMATION_NAMES[alien_type][animation_key]
	
	if ANIMATION_NAMES["Drone"].has(animation_key):
		return ANIMATION_NAMES["Drone"][animation_key]
	
	return animation_key

func _play_animation(animation_name: String):
	if not animated_sprite or not animated_sprite.sprite_frames or is_dead:
		return
	
	if not animated_sprite.sprite_frames.has_animation(animation_name):
		return
	
	current_animation_name = animation_name
	animated_sprite.play(animation_name)
	
	_set_animation_speed()

func _play_animation_immediate(animation_name: String):
	if not animated_sprite or is_dead:
		return
	
	is_playing_special_animation = true
	animated_sprite.play(animation_name)
	
	if animated_sprite.animation_finished.is_connected(_on_special_animation_finished):
		animated_sprite.animation_finished.disconnect(_on_special_animation_finished)
	
	animated_sprite.animation_finished.connect(_on_special_animation_finished, CONNECT_ONE_SHOT)

func _set_animation_speed():
	if not animated_sprite or is_dead:
		return
	
	var speed_multiplier = animation_speed_multiplier
	
	match current_animation_state:
		AnimationState.IDLE:
			speed_multiplier *= idle_animation_speed
		AnimationState.MOVING:
			speed_multiplier *= movement_animation_speed
		AnimationState.DEAD:
			speed_multiplier *= death_animation_speed
		AnimationState.STUNNED:
			speed_multiplier *= stun_animation_speed
		AnimationState.GIBBED:
			speed_multiplier *= death_animation_speed
	
	animated_sprite.speed_scale = speed_multiplier

func handle_death(should_gib: bool = true):
	is_dead = true
	
	_stop_all_animations()
	
	if should_gib and has_animation("gib"):
		_execute_gib_death()
	else:
		_execute_normal_death()

func _stop_all_animations():
	animation_queue.clear()
	is_playing_special_animation = false
	
	if animated_sprite:
		animated_sprite.stop()

func _execute_gib_death():
	current_animation_state = AnimationState.GIBBED
	
	var gib_animation = _get_mapped_animation_name("gib")
	if has_animation(gib_animation):
		current_animation_name = gib_animation
		animated_sprite.play(gib_animation)
		animated_sprite.speed_scale = death_animation_speed * animation_speed_multiplier
		if not animated_sprite.animation_finished.is_connected(_on_gib_animation_finished):
			animated_sprite.animation_finished.connect(_on_gib_animation_finished, CONNECT_ONE_SHOT)
	else:
		_execute_normal_death()

func _execute_normal_death():
	current_animation_state = AnimationState.DEAD
	
	var death_animation = _get_mapped_animation_name("dead")
	if has_animation(death_animation):
		current_animation_name = death_animation
		animated_sprite.play(death_animation)
		animated_sprite.speed_scale = death_animation_speed * animation_speed_multiplier
		if not animated_sprite.animation_finished.is_connected(_on_death_animation_finished):
			animated_sprite.animation_finished.connect(_on_death_animation_finished, CONNECT_ONE_SHOT)

func _on_gib_animation_finished():
	if animated_sprite:
		animated_sprite.stop()
		animated_sprite.visible = false

func _on_death_animation_finished():
	if animated_sprite:
		animated_sprite.pause()

func flash_damage():
	if not enable_damage_flash or not animated_sprite or is_dead:
		return
	
	damage_flash_timer = damage_flash_duration
	animated_sprite.modulate = damage_flash_color

func _end_damage_flash():
	if animated_sprite and not is_dead:
		animated_sprite.modulate = original_modulate

func set_stealth_mode(enabled: bool):
	if is_dead:
		return
	is_stealthed = enabled

func set_modulate_color(color: Color):
	original_modulate = color
	if animated_sprite and damage_flash_timer <= 0:
		animated_sprite.modulate = color

func set_stun_state(is_stunned_state: bool):
	if is_dead:
		return
	
	is_stunned = is_stunned_state
	
	if is_stunned:
		current_animation_state = AnimationState.STUNNED
		set_modulate_color(stun_modulate)
	else:
		current_animation_state = AnimationState.IDLE
		set_modulate_color(base_modulate)
	
	_update_animation()

func set_resting_state(is_resting_state: bool):
	if is_dead:
		return
	
	is_resting = is_resting_state
	
	if is_resting:
		current_animation_state = AnimationState.RESTING
	else:
		current_animation_state = AnimationState.IDLE
	
	_update_animation()

func play_attack_animation():
	if is_dead:
		return
	
	if current_animation_state != AnimationState.DEAD:
		animation_queue.append(_get_mapped_animation_name("attack"))

func play_special_animation(animation_name: String, return_to_idle: bool = true):
	if not animated_sprite or not animated_sprite.sprite_frames or is_dead:
		return
	
	if animated_sprite.sprite_frames.has_animation(animation_name):
		_play_animation_immediate(animation_name)
		
		if return_to_idle:
			call_deferred("_queue_return_to_idle")

func _queue_return_to_idle():
	if not is_dead:
		animation_queue.append(_get_animation_name())

func set_sprite_scale(new_scale: Vector2):
	sprite_scale = new_scale
	if animated_sprite:
		animated_sprite.scale = sprite_scale

func set_sprite_offset(new_offset: Vector2):
	sprite_offset = new_offset
	if animated_sprite:
		animated_sprite.offset = sprite_offset

func _set_rotation(rotation_rad: float):
	if animated_sprite:
		animated_sprite.rotation = rotation_rad

func clear_rotation():
	_set_rotation(0.0)

func is_playing_animation(animation_name: String) -> bool:
	return animated_sprite and animated_sprite.animation == animation_name and animated_sprite.is_playing()

func get_current_animation() -> String:
	return current_animation_name

func get_animation_progress() -> float:
	if not animated_sprite or not animated_sprite.is_playing():
		return 0.0
	
	var current_frame = animated_sprite.frame
	var total_frames = animated_sprite.sprite_frames.get_frame_count(animated_sprite.animation)
	
	return float(current_frame) / float(max(1, total_frames))

func initialize_for_alien(alien_controller: Node):
	controller = alien_controller
	
	if "alien_type" in controller:
		alien_type = controller.alien_type
	
	movement_component = controller.get_node_or_null("MovementComponent")
	
	health_system = controller.get_node_or_null("HealthSystem")
	if not health_system:
		health_system = controller.get_parent().get_node_or_null("HealthSystem")
	
	_setup_signal_connections()
	_set_initial_animation()

func _on_direction_changed(new_direction: int):
	set_direction(new_direction)

func _on_movement_state_changed(old_state: int, new_state: int):
	if is_dead:
		return
	
	match new_state:
		0:
			is_moving = false
			if not is_stunned and not is_resting:
				current_animation_state = AnimationState.IDLE
		1, 2:
			is_moving = true
			if not is_stunned and not is_resting:
				current_animation_state = AnimationState.MOVING
		3:
			is_moving = false
			is_stunned = true
			current_animation_state = AnimationState.STUNNED
		4:
			is_moving = true
			if not is_stunned:
				current_animation_state = AnimationState.MOVING
	
	_update_animation()

func _on_ai_state_changed(old_state: int, new_state: int):
	if is_dead:
		return
	
	match new_state:
		5:
			play_attack_animation()
		7:
			if not is_moving:
				current_animation_state = AnimationState.IDLE

func _on_stealth_mode_changed(enabled: bool):
	set_stealth_mode(enabled)

func _on_special_animation_finished():
	is_playing_special_animation = false

func load_alien_animations(animation_resource_path: String):
	if not animated_sprite:
		return false
	
	var sprite_frames = load(animation_resource_path)
	if sprite_frames is SpriteFrames:
		animated_sprite.sprite_frames = sprite_frames
		return true
	
	return false

func has_animation(animation_name: String) -> bool:
	return animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(animation_name)

func get_available_animations() -> Array:
	if not animated_sprite or not animated_sprite.sprite_frames:
		return []
	
	return animated_sprite.sprite_frames.get_animation_names()

func set_visible(visible: bool):
	if animated_sprite:
		animated_sprite.visible = visible

func pause_animations():
	if animated_sprite and not is_dead:
		animated_sprite.pause()

func resume_animations():
	if animated_sprite and not is_dead:
		animated_sprite.play()

func get_debug_info() -> Dictionary:
	return {
		"alien_type": alien_type,
		"current_animation_state": AnimationState.keys()[current_animation_state],
		"current_direction": Direction.keys()[current_direction],
		"current_animation_name": current_animation_name,
		"is_dead": is_dead,
		"is_stunned": is_stunned,
		"is_resting": is_resting,
		"is_moving": is_moving,
		"is_stealthed": is_stealthed,
		"distance_to_camera": distance_to_camera,
		"is_visible_on_screen": is_visible_on_screen,
		"animation_queue_size": animation_queue.size()
	}

func _exit_tree():
	damage_flash_timer = 0.0
	is_playing_special_animation = false
	animation_queue.clear()
