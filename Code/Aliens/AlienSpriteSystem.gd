extends Node2D
class_name AlienSpriteSystem

enum Direction {
	SOUTH = 0,
	NORTH = 1,
	EAST = 2,
	WEST = 3
}

signal animation_changed(new_animation: String)
signal thrust_completed()

@export var alien_type: String = "drone"

var controller: Node = null
var animated_sprite: AnimatedSprite2D = null
var movement_component: Node = null
var health_system: Node = null

var current_direction: int = Direction.SOUTH
var current_animation: String = ""
var is_dead: bool = false
var is_moving: bool = false

var animation_update_timer: float = 0.0
var animation_update_interval: float = 0.05

func _ready():
	controller = get_parent()
	setup_animated_sprite()
	connect_signals()
	update_animation()

func setup_animated_sprite():
	animated_sprite = get_node_or_null("AnimatedSprite2D")
	
	if not animated_sprite:
		print("ERROR: AnimatedSprite2D not found!")
		return
	
	animated_sprite.visible = true
	animated_sprite.z_index = 1
	animated_sprite.play()

func connect_signals():
	if controller:
		movement_component = controller.get_node_or_null("MovementComponent")
		health_system = controller.get_node_or_null("AlienHealthSystem")
		
		if movement_component:
			if movement_component.has_signal("state_changed"):
				movement_component.state_changed.connect(_on_movement_state_changed)
			if movement_component.has_signal("direction_changed"):
				movement_component.direction_changed.connect(_on_direction_changed)
			if movement_component.has_signal("movement_started"):
				movement_component.movement_started.connect(_on_movement_started)
			if movement_component.has_signal("movement_completed"):
				movement_component.movement_completed.connect(_on_movement_completed)
		
		if health_system:
			if health_system.has_signal("died"):
				health_system.died.connect(_on_entity_died)
			if health_system.has_signal("revived"):
				health_system.revived.connect(_on_entity_revived)

func _process(delta: float):
	animation_update_timer += delta
	
	if animation_update_timer >= animation_update_interval:
		update_animation()
		animation_update_timer = 0.0

func update_animation():
	if not animated_sprite or not animated_sprite.sprite_frames:
		return
	
	var new_animation = determine_animation()
	
	if new_animation != current_animation:
		play_animation(new_animation)

func determine_animation() -> String:
	if is_dead:
		return "dead"
	
	check_movement_state()
	
	var direction_suffix = get_direction_suffix(current_direction)
	
	if is_moving:
		return "moving_" + direction_suffix
	else:
		return "idle_" + direction_suffix

func check_movement_state():
	if movement_component:
		if "is_moving" in movement_component:
			is_moving = movement_component.is_moving
		elif movement_component.has_method("is_moving"):
			is_moving = movement_component.is_moving()
		elif "current_state" in movement_component:
			is_moving = movement_component.current_state >= 1 and movement_component.current_state <= 4

func get_direction_suffix(direction: int) -> String:
	match direction:
		Direction.SOUTH:
			return "south"
		Direction.NORTH:
			return "north"
		Direction.EAST:
			return "east"
		Direction.WEST:
			return "west"
		_:
			return "south"

func play_animation(animation_name: String):
	if not animated_sprite or not animated_sprite.sprite_frames:
		return
	
	if not animated_sprite.sprite_frames.has_animation(animation_name):
		if animated_sprite.sprite_frames.has_animation("idle_south"):
			animation_name = "idle_south"
		else:
			return
	
	animated_sprite.play(animation_name)
	current_animation = animation_name
	emit_signal("animation_changed", animation_name)

func set_direction(new_direction: int):
	if current_direction != new_direction:
		current_direction = new_direction
		force_animation_update()

func set_dead_state(dead: bool):
	if is_dead != dead:
		is_dead = dead
		force_animation_update()

func _on_movement_state_changed(old_state: int, new_state: int):
	force_animation_update()

func _on_direction_changed(new_direction: int):
	set_direction(new_direction)

func _on_movement_started():
	is_moving = true
	force_animation_update()

func _on_movement_completed():
	is_moving = false
	force_animation_update()

func _on_entity_died(cause_of_death: String, death_time: float):
	set_dead_state(true)

func _on_entity_revived(method: String):
	set_dead_state(false)

func show_interaction_thrust(direction_to_target: Vector2, intent: int):
	if not animated_sprite:
		return
	
	var original_pos = animated_sprite.position
	var thrust_distance = 8.0
	var thrust_duration = 0.3
	
	var tween = create_tween()
	var target_pos = original_pos + (direction_to_target.normalized() * thrust_distance)
	
	tween.tween_property(animated_sprite, "position", target_pos, thrust_duration * 0.5)
	tween.tween_property(animated_sprite, "position", original_pos, thrust_duration * 0.5)
	
	await tween.finished
	emit_signal("thrust_completed")

func initialize(init_data: Dictionary):
	controller = init_data.get("controller")
	if init_data.has("alien_type"):
		alien_type = init_data.get("alien_type", "drone")

func clear_rotation():
	if animated_sprite:
		animated_sprite.rotation = 0.0

func get_current_animation() -> String:
	return current_animation

func is_animation_playing(animation_name: String) -> bool:
	if not animated_sprite:
		return false
	return current_animation == animation_name and animated_sprite.is_playing()

func set_alien_type(new_type: String):
	alien_type = new_type

func get_alien_type() -> String:
	return alien_type

func force_animation_update():
	animation_update_timer = animation_update_interval
	update_animation()

func play_specific_animation(animation_name: String):
	play_animation(animation_name)

func stop_all_animations():
	if animated_sprite:
		animated_sprite.stop()
		current_animation = ""
