extends Node
class_name ZLevelMovementComponent

#region CONSTANTS
const LYING_ANGLE: float = 90.0
#endregion

#region ENUMS
enum ZMoveFlags {
	NONE = 0,
	IGNORE_CHECKS = 1,
	FORCED = 2,
	CAN_FLY_CHECKS = 4,
	FEEDBACK = 8,
	FLIGHT_FLAGS = 12
}
#endregion

#region SIGNALS
signal z_level_changed(old_z: int, new_z: int, position: Vector2i)
signal z_move_attempted(direction: int, success: bool)
signal ladder_used(ladder: Node, going_up: bool)
#endregion

#region EXPORTS
@export_group("Z-Movement Configuration")
@export var movement_animation_duration: float = 1.0
@export var ladder_climb_duration: float = 1.2
@export var enable_flight_movement: bool = true
@export var enable_ladder_movement: bool = true

@export_group("Audio Settings")
@export var ladder_climb_sound: String = "ladder_climb"
@export var movement_sound: String = "z_movement"
@export var default_volume: float = 0.5

@export_group("Visual Effects")
@export var show_movement_messages: bool = true
@export var show_obstruction_messages: bool = true
@export var movement_message_color: Color = Color.CYAN
#endregion

#region PROPERTIES
# Core references
var controller: Node = null
var world = null
var tile_occupancy_system = null
var sensory_system = null
var audio_system = null

# State
var current_z_level: int = 0
var parent_container = null

# Cached ladder lookups for performance
var _ladder_cache: Dictionary = {}
var _cache_clear_timer: float = 0.0
var _cache_lifetime: float = 5.0
#endregion

#region INITIALIZATION
func initialize(init_data: Dictionary):
	controller = init_data.get("controller")
	world = init_data.get("world")
	tile_occupancy_system = init_data.get("tile_occupancy_system")
	sensory_system = init_data.get("sensory_system")
	audio_system = init_data.get("audio_system")
	current_z_level = controller.current_z_level if controller else 0

func _process(delta: float):
	_cache_clear_timer += delta
	if _cache_clear_timer >= _cache_lifetime:
		_ladder_cache.clear()
		_cache_clear_timer = 0.0
#endregion

#region PUBLIC INTERFACE
func move_up() -> bool:
	if not _can_initiate_movement():
		return false
	
	var current_pos = _get_current_tile_position()
	var ladder = _get_ladder_at(current_pos)
	
	if enable_ladder_movement and ladder and ladder.has_method("top_z") and ladder.top_z > current_z_level:
		await use_ladder(ladder, true)
		return true
	
	if not can_z_move(1, current_pos, ZMoveFlags.CAN_FLY_CHECKS | ZMoveFlags.FEEDBACK):
		return false
	
	if show_movement_messages:
		_show_message("Moving up...")
	
	var timer = controller.get_tree().create_timer(movement_animation_duration)
	await timer.timeout
	
	return z_move(1, ZMoveFlags.FLIGHT_FLAGS | ZMoveFlags.FEEDBACK)

func move_down() -> bool:
	if not _can_initiate_movement():
		return false
	
	var current_pos = _get_current_tile_position()
	var ladder = _get_ladder_at(current_pos)
	
	if enable_ladder_movement and ladder and ladder.has_method("bottom_z") and ladder.bottom_z < current_z_level:
		await use_ladder(ladder, false)
		return true
	
	if not can_z_move(-1, current_pos, ZMoveFlags.CAN_FLY_CHECKS | ZMoveFlags.FEEDBACK):
		return false
	
	if show_movement_messages:
		_show_message("Moving down...")
	
	var timer = controller.get_tree().create_timer(movement_animation_duration)
	await timer.timeout
	
	return z_move(-1, ZMoveFlags.FLIGHT_FLAGS | ZMoveFlags.FEEDBACK)
#endregion

#region Z-MOVEMENT CHECKS
func can_z_move(direction: int, current_turf: Vector2i, flags: int) -> bool:
	if parent_container != null:
		if parent_container.has_method("handle_z_move"):
			return parent_container.handle_z_move(controller, direction)
		return false
	
	if flags & ZMoveFlags.IGNORE_CHECKS:
		return true
	
	var target_z = current_z_level + direction
	
	if not _is_valid_z_level(target_z, flags):
		return false
	
	if direction > 0 and not _can_move_up(current_turf, flags):
		return false
	
	if direction < 0 and not _can_move_down(current_turf, flags):
		return false
	
	if flags & ZMoveFlags.CAN_FLY_CHECKS and not _can_fly_or_float():
		if flags & ZMoveFlags.FEEDBACK and show_obstruction_messages:
			_show_message("You can't fly!")
		return false
	
	if not _is_valid_destination(current_turf, target_z, flags):
		return false
	
	return true

func _is_valid_z_level(target_z: int, flags: int) -> bool:
	if world and not world.has_z_level(target_z):
		if flags & ZMoveFlags.FEEDBACK and show_obstruction_messages:
			_show_message("There's nothing in that direction!")
		return false
	return true

func _can_move_up(current_turf: Vector2i, flags: int) -> bool:
	if world and world.has_ceiling_at(current_turf, current_z_level):
		if flags & ZMoveFlags.FEEDBACK and show_obstruction_messages:
			_show_message("There's a ceiling in the way!")
		return false
	return true

func _can_move_down(current_turf: Vector2i, flags: int) -> bool:
	if world and world.has_solid_floor_at(current_turf, current_z_level):
		if flags & ZMoveFlags.FEEDBACK and show_obstruction_messages:
			_show_message("The floor is in the way!")
		return false
	return true

func _can_fly_or_float() -> bool:
	return can_fly() or is_floating()

func _is_valid_destination(current_turf: Vector2i, target_z: int, flags: int) -> bool:
	if not _is_valid_tile(current_turf, target_z):
		if flags & ZMoveFlags.FEEDBACK and show_obstruction_messages:
			_show_message("There's nothing there to land on!")
		return false
	return true

func z_move(direction: int, flags: int = ZMoveFlags.NONE) -> bool:
	var current_pos = _get_current_tile_position()
	
	if not can_z_move(direction, current_pos, flags):
		emit_signal("z_move_attempted", direction, false)
		return false
	
	var target_z = current_z_level + direction
	var old_z = current_z_level
	
	_update_z_level(old_z, target_z, current_pos)
	_show_movement_feedback(direction, flags)
	_check_new_environment()
	
	emit_signal("z_move_attempted", direction, true)
	return true

func _update_z_level(old_z: int, target_z: int, position: Vector2i):
	current_z_level = target_z
	
	if controller:
		controller.current_z_level = target_z
	
	if tile_occupancy_system:
		tile_occupancy_system.move_entity_z(controller, position, position, old_z, target_z)
	
	emit_signal("z_level_changed", old_z, target_z, position)

func _show_movement_feedback(direction: int, flags: int):
	if flags & ZMoveFlags.FEEDBACK and show_movement_messages:
		var message = "You move upward." if direction > 0 else "You move downward."
		_show_message(message)

func _check_new_environment():
	if controller.movement_component:
		controller.movement_component.check_tile_environment()
#endregion

#region LADDER HANDLING
func use_ladder(ladder: Node, going_up: bool = true):
	if not enable_ladder_movement or not ladder:
		return
	
	var target_z = current_z_level
	var target_pos = _get_current_tile_position()
	
	if going_up and ladder.has_method("top_z"):
		target_z = ladder.top_z
		if ladder.has_method("top_position"):
			target_pos = ladder.top_position
	elif not going_up and ladder.has_method("bottom_z"):
		target_z = ladder.bottom_z
		if ladder.has_method("bottom_position"):
			target_pos = ladder.bottom_position
	
	_play_ladder_audio()
	_show_ladder_message(going_up)
	
	var timer = controller.get_tree().create_timer(ladder_climb_duration)
	await timer.timeout
	
	_perform_ladder_movement(target_z, target_pos)
	emit_signal("ladder_used", ladder, going_up)

func _play_ladder_audio():
	if audio_system:
		audio_system.play_positioned_sound(ladder_climb_sound, controller.position, default_volume)

func _show_ladder_message(going_up: bool):
	if show_movement_messages:
		var message = "You climb up the ladder." if going_up else "You climb down the ladder."
		_show_message(message)

func _perform_ladder_movement(target_z: int, target_pos: Vector2i):
	var old_z = current_z_level
	var old_pos = _get_current_tile_position()
	
	current_z_level = target_z
	
	if controller:
		controller.current_z_level = target_z
	
	_update_controller_position(target_pos)
	_update_tile_occupancy(old_pos, target_pos, old_z, target_z)
	
	emit_signal("z_level_changed", old_z, target_z, target_pos)
	_check_new_environment()

func _update_controller_position(target_pos: Vector2i):
	if controller.movement_component:
		controller.movement_component.current_tile_position = target_pos
		controller.movement_component.previous_tile_position = target_pos
		controller.position = _tile_to_world(target_pos)

func _update_tile_occupancy(old_pos: Vector2i, target_pos: Vector2i, old_z: int, target_z: int):
	if tile_occupancy_system:
		tile_occupancy_system.move_entity_z(controller, old_pos, target_pos, old_z, target_z)

func _get_ladder_at(position: Vector2i) -> Node:
	var cache_key = str(position) + "_" + str(current_z_level)
	
	if _ladder_cache.has(cache_key):
		var cached_ladder = _ladder_cache[cache_key]
		if is_instance_valid(cached_ladder):
			return cached_ladder
		else:
			_ladder_cache.erase(cache_key)
	
	var ladder = null
	if world and world.has_method("get_ladder_at"):
		ladder = world.get_ladder_at(position, current_z_level)
	
	if ladder:
		_ladder_cache[cache_key] = ladder
	
	return ladder
#endregion

#region FLIGHT CAPABILITIES
func can_fly() -> bool:
	if not enable_flight_movement:
		return false
	
	if controller.status_effect_component:
		if controller.status_effect_component.has_effect("flying"):
			return true
	
	return _check_equipment_flight_capability()

func is_floating() -> bool:
	if controller.movement_component:
		return controller.movement_component.is_floating
	return false

func _check_equipment_flight_capability() -> bool:
	# This would interface with equipment system
	# For now, return false as a placeholder
	return false
#endregion

#region VALIDATION FUNCTIONS
func _can_initiate_movement() -> bool:
	if controller.movement_component and controller.movement_component.is_moving:
		return false
	return true

func _is_valid_tile(tile_pos: Vector2i, z_level: int) -> bool:
	if not world:
		return false
	
	if world.has_method("is_in_zone"):
		return world.is_in_zone(tile_pos, z_level)
	
	var tile = world.get_tile_data(tile_pos, z_level)
	return tile != null
#endregion

#region UTILITY FUNCTIONS
func _get_current_tile_position() -> Vector2i:
	if controller.movement_component:
		return controller.movement_component.current_tile_position
	return Vector2i.ZERO

func _tile_to_world(tile_pos: Vector2i) -> Vector2:
	return Vector2((tile_pos.x * 32) + 16, (tile_pos.y * 32) + 16)

func _show_message(text: String):
	if not show_movement_messages:
		return
		
	if sensory_system:
		var formatted_message = "[color=" + movement_message_color.to_html() + "]" + text + "[/color]"
		sensory_system.display_message(formatted_message)

func get_current_z_level() -> int:
	return current_z_level

func set_parent_container(container: Node):
	parent_container = container
#endregion
