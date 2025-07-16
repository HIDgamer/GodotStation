extends Node
class_name ZLevelMovementComponent

## Handles movement between Z-levels (up/down floors)

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
#endregion

func initialize(init_data: Dictionary):
	"""Initialize the Z-level movement component"""
	controller = init_data.get("controller")
	world = init_data.get("world")
	tile_occupancy_system = init_data.get("tile_occupancy_system")
	sensory_system = init_data.get("sensory_system")
	audio_system = init_data.get("audio_system")
	current_z_level = controller.current_z_level if controller else 0

#region PUBLIC INTERFACE
func move_up() -> bool:
	"""Attempt to move up one Z-level"""
	# Check if moving
	if controller.movement_component and controller.movement_component.is_moving:
		return false
	
	# Check for ladders
	var current_pos = get_current_tile_position()
	var ladder = get_ladder_at(current_pos)
	
	if ladder and ladder.has_method("top_z") and ladder.top_z > current_z_level:
		await use_ladder(ladder, true)
		return true
	
	# Check if can z-move
	if not can_z_move(1, current_pos, ZMoveFlags.CAN_FLY_CHECKS | ZMoveFlags.FEEDBACK):
		return false
	
	# Show effect
	if sensory_system:
		sensory_system.display_message("Moving up...")
	
	# Wait for animation
	var timer = controller.get_tree().create_timer(1.0)
	await timer.timeout
	
	# Perform move
	return z_move(1, ZMoveFlags.FLIGHT_FLAGS | ZMoveFlags.FEEDBACK)

func move_down() -> bool:
	"""Attempt to move down one Z-level"""
	# Check if moving
	if controller.movement_component and controller.movement_component.is_moving:
		return false
	
	# Check for ladders
	var current_pos = get_current_tile_position()
	var ladder = get_ladder_at(current_pos)
	
	if ladder and ladder.has_method("bottom_z") and ladder.bottom_z < current_z_level:
		await use_ladder(ladder, false)
		return true
	
	# Check if can z-move
	if not can_z_move(-1, current_pos, ZMoveFlags.CAN_FLY_CHECKS | ZMoveFlags.FEEDBACK):
		return false
	
	# Show effect
	if sensory_system:
		sensory_system.display_message("Moving down...")
	
	# Wait for animation
	var timer = controller.get_tree().create_timer(1.0)
	await timer.timeout
	
	# Perform move
	return z_move(-1, ZMoveFlags.FLIGHT_FLAGS | ZMoveFlags.FEEDBACK)
#endregion

#region Z-MOVEMENT CHECKS
func can_z_move(direction: int, current_turf: Vector2i, flags: int) -> bool:
	"""Check if Z-movement is possible"""
	# Handle special containers
	if parent_container != null:
		if parent_container.has_method("handle_z_move"):
			return parent_container.handle_z_move(controller, direction)
		return false
	
	# Skip checks if forced
	if flags & ZMoveFlags.IGNORE_CHECKS:
		return true
	
	# Calculate target
	var target_z = current_z_level + direction
	
	# Check if level exists
	if world and not world.has_z_level(target_z):
		if flags & ZMoveFlags.FEEDBACK:
			show_message("There's nothing in that direction!")
		return false
	
	# Check upward movement
	if direction > 0:
		if world and world.has_ceiling_at(current_turf, current_z_level):
			if flags & ZMoveFlags.FEEDBACK:
				show_message("There's a ceiling in the way!")
			return false
	
	# Check downward movement
	if direction < 0:
		if world and world.has_solid_floor_at(current_turf, current_z_level):
			if flags & ZMoveFlags.FEEDBACK:
				show_message("The floor is in the way!")
			return false
	
	# Check flying ability
	if flags & ZMoveFlags.CAN_FLY_CHECKS:
		if not can_fly() and not is_floating():
			if flags & ZMoveFlags.FEEDBACK:
				show_message("You can't fly!")
			return false
	
	# Check destination
	if not is_valid_tile(current_turf, target_z):
		if flags & ZMoveFlags.FEEDBACK:
			show_message("There's nothing there to land on!")
		return false
	
	return true

func z_move(direction: int, flags: int = ZMoveFlags.NONE) -> bool:
	"""Perform Z-level movement"""
	var current_pos = get_current_tile_position()
	
	# Final check
	if not can_z_move(direction, current_pos, flags):
		emit_signal("z_move_attempted", direction, false)
		return false
	
	# Calculate target
	var target_z = current_z_level + direction
	
	# Update position
	var old_z = current_z_level
	current_z_level = target_z
	
	# Update controller z-level
	if controller:
		controller.current_z_level = target_z
	
	# Update occupancy
	if tile_occupancy_system:
		tile_occupancy_system.move_entity_z(
			controller,
			current_pos,
			current_pos,
			old_z,
			target_z
		)
	
	# Emit signal
	emit_signal("z_level_changed", old_z, target_z, current_pos)
	emit_signal("z_move_attempted", direction, true)
	
	# Display message
	if flags & ZMoveFlags.FEEDBACK and sensory_system:
		if direction > 0:
			sensory_system.display_message("You move upward.")
		else:
			sensory_system.display_message("You move downward.")
	
	# Check new environment
	if controller.movement_component:
		controller.movement_component.check_tile_environment()
	
	return true
#endregion

#region LADDER HANDLING
func use_ladder(ladder: Node, going_up: bool = true):
	"""Use a ladder to change Z-levels"""
	var target_z = current_z_level
	var target_pos = get_current_tile_position()
	
	if going_up and ladder.has_method("top_z"):
		target_z = ladder.top_z
		if ladder.has_method("top_position"):
			target_pos = ladder.top_position
	elif not going_up and ladder.has_method("bottom_z"):
		target_z = ladder.bottom_z
		if ladder.has_method("bottom_position"):
			target_pos = ladder.bottom_position
	
	# Play sound
	if audio_system:
		audio_system.play_positioned_sound("ladder_climb", controller.position, 0.5)
	
	# Show message
	if sensory_system:
		if going_up:
			sensory_system.display_message("You climb up the ladder.")
		else:
			sensory_system.display_message("You climb down the ladder.")
	
	# Wait for animation
	var timer = controller.get_tree().create_timer(1.2)
	await timer.timeout
	
	# Update position
	var old_z = current_z_level
	current_z_level = target_z
	
	if controller:
		controller.current_z_level = target_z
	
	var old_pos = get_current_tile_position()
	
	# Update movement component position
	if controller.movement_component:
		controller.movement_component.current_tile_position = target_pos
		controller.movement_component.previous_tile_position = target_pos
		controller.position = tile_to_world(target_pos)
	
	# Update occupancy
	if tile_occupancy_system:
		tile_occupancy_system.move_entity_z(controller, old_pos, target_pos, old_z, target_z)
	
	# Emit signals
	emit_signal("z_level_changed", old_z, target_z, target_pos)
	emit_signal("ladder_used", ladder, going_up)
	
	# Check environment
	if controller.movement_component:
		controller.movement_component.check_tile_environment()

func get_ladder_at(position: Vector2i) -> Node:
	"""Get ladder at position"""
	if world and world.has_method("get_ladder_at"):
		return world.get_ladder_at(position, current_z_level)
	return null
#endregion

#region HELPER FUNCTIONS
func can_fly() -> bool:
	"""Check if entity can fly"""
	# Check status effects
	if controller.status_effect_component:
		if controller.status_effect_component.has_effect("flying"):
			return true
	
	# Check equipment (jetpack, etc)
	# This would need to interface with equipment system
	
	return false

func is_floating() -> bool:
	"""Check if currently floating"""
	if controller.movement_component:
		return controller.movement_component.is_floating
	return false

func is_valid_tile(tile_pos: Vector2i, z_level: int) -> bool:
	"""Check if tile is valid"""
	if not world:
		return false
	
	if world.has_method("is_in_zone"):
		return world.is_in_zone(tile_pos, z_level)
	
	var tile = world.get_tile_data(tile_pos, z_level)
	return tile != null

func get_current_tile_position() -> Vector2i:
	"""Get current tile position"""
	if controller.movement_component:
		return controller.movement_component.current_tile_position
	return Vector2i.ZERO

func tile_to_world(tile_pos: Vector2i) -> Vector2:
	"""Convert tile to world position"""
	return Vector2((tile_pos.x * 32) + 16, (tile_pos.y * 32) + 16)

func show_message(text: String):
	"""Display message"""
	if sensory_system:
		sensory_system.display_message(text)

func get_current_z_level() -> int:
	"""Get current Z-level"""
	return current_z_level

func set_parent_container(container: Node):
	"""Set parent container (for special handling)"""
	parent_container = container
#endregion
