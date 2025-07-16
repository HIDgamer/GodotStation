extends Node
class_name PostureComponent

## Handles lying down, standing up, and crawling mechanics

#region CONSTANTS
const LYING_STATE_CHANGE_COOLDOWN: float = 0.8
const LYING_ANGLE: float = 90.0
const LYING_STAMINA_RECOVERY_BONUS: float = 1.5
#endregion

#region SIGNALS
signal lying_state_changed(is_lying: bool)
signal stand_up_attempted(success: bool)
signal crawl_state_changed(is_crawling: bool)
signal rest_toggled()
#endregion

#region PROPERTIES
# Core references
var controller: Node = null
var sensory_system = null
var audio_system = null
var sprite_system = null
var health_system = null
var limb_system = null
var status_effect_manager = null

# Lying state
var is_lying: bool = false
var lying_angle: float = LYING_ANGLE
var last_lying_state_change: float = 0.0
var stand_up_attempts: int = 0

# Crawling
var can_crawl: bool = true
var crawl_cooldown: float = 0.0
var crawl_speed_multiplier: float = 0.5
#endregion

func initialize(init_data: Dictionary):
	"""Initialize the posture component"""
	controller = init_data.get("controller")
	sensory_system = init_data.get("sensory_system")
	audio_system = init_data.get("audio_system")
	sprite_system = init_data.get("sprite_system")
	
	# Find additional systems
	var parent = controller.get_parent() if controller else null
	if parent:
		health_system = parent.get_node_or_null("HealthSystem")
		limb_system = parent.get_node_or_null("LimbSystem")
		status_effect_manager = parent.get_node_or_null("StatusEffectManager")

func _process(delta: float):
	"""Update crawl cooldown"""
	if crawl_cooldown > 0:
		crawl_cooldown -= delta

#region PUBLIC INTERFACE
func toggle_lying() -> bool:
	"""Toggle between lying and standing"""
	if Time.get_ticks_msec() * 0.001 - last_lying_state_change < LYING_STATE_CHANGE_COOLDOWN:
		return false
	
	if is_lying:
		return get_up()
	else:
		return await lie_down()

func lie_down(forced: bool = false) -> bool:
	"""Make the character lie down"""
	print("PostureComponent: Attempting to lie down")
	
	# Check if can lie down
	if not forced:
		if controller.movement_component and controller.movement_component.is_moving:
			print("PostureComponent: Can't lie down while moving")
			return false
		
		if controller.movement_component and controller.movement_component.is_stunned:
			print("PostureComponent: Can't lie down while stunned")
			return false
	
	if is_lying:
		print("PostureComponent: Already lying down")
		return false
	
	# Update state
	is_lying = true
	last_lying_state_change = Time.get_ticks_msec() * 0.001
	
	# Cancel movement
	if controller.movement_component:
		if controller.movement_component.is_moving:
			controller.movement_component.is_moving = false
			controller.movement_component.move_progress = 0.0
			controller.position = controller.movement_component.tile_to_world(
				controller.movement_component.current_tile_position
			)
	
	# Update sprite first
	var sprites_updated = false
	if sprite_system and sprite_system.has_method("set_lying_state"):
		sprite_system.set_lying_state(true, get_current_direction())
		sprites_updated = true
		print("PostureComponent: Sprite system updated to lying state")
	
	# Wait for sprite update
	if sprites_updated:
		await controller.get_tree().create_timer(0.1).timeout
	
	# Emit signal
	emit_signal("lying_state_changed", true)
	
	# Play sound
	if audio_system:
		audio_system.play_positioned_sound("body_fall", controller.position, 0.4)
	
	# Display message
	show_message("You lie down.")
	
	print("PostureComponent: Successfully lying down")
	return true

func get_up(forced: bool = false) -> bool:
	"""Attempt to stand up"""
	print("PostureComponent: Attempting to get up")
	
	# Check if can get up
	if not forced:
		if controller.movement_component and controller.movement_component.is_moving:
			print("PostureComponent: Can't get up while moving")
			return false
		
		if controller.movement_component and controller.movement_component.is_stunned:
			print("PostureComponent: Can't get up while stunned")
			return false
	
	if not is_lying:
		print("PostureComponent: Not lying down")
		return false
	
	# Check health/stamina requirements
	if not can_stand_up() and not forced:
		handle_failed_standup()
		return false
	
	# Update state
	is_lying = false
	last_lying_state_change = Time.get_ticks_msec() * 0.001
	stand_up_attempts = 0
	
	# Cancel movement
	if controller.movement_component:
		if controller.movement_component.is_moving:
			controller.movement_component.is_moving = false
			controller.movement_component.move_progress = 0.0
			controller.position = controller.movement_component.tile_to_world(
				controller.movement_component.current_tile_position
			)
	
	# Emit signal first
	emit_signal("lying_state_changed", false)
	
	# Update sprite
	if sprite_system and sprite_system.has_method("set_lying_state"):
		sprite_system.set_lying_state(false, get_current_direction())
		print("PostureComponent: Sprite system updated to standing state")
	
	# Play sound
	if audio_system:
		audio_system.play_positioned_sound("rustle", controller.position, 0.4)
	
	# Display message
	show_message("You get back up.")
	
	print("PostureComponent: Successfully got up")
	emit_signal("stand_up_attempted", true)
	return true

func handle_rest_toggle():
	"""Handle the rest key being pressed"""
	emit_signal("rest_toggled")
	toggle_lying()

func set_lying_angle(angle: float):
	"""Set the lying angle for visual representation"""
	lying_angle = angle
	
	if is_lying and sprite_system:
		if sprite_system.has_method("set_lying_angle"):
			sprite_system.set_lying_angle(angle)

func force_stand_up():
	"""Force the character to stand up (used by other systems)"""
	if is_lying:
		get_up(true)

func force_lie_down():
	"""Force the character to lie down (used by other systems)"""
	if not is_lying:
		lie_down(true)
#endregion

#region CRAWLING
func can_crawl_in_direction(direction: Vector2i) -> bool:
	"""Check if can crawl in a direction"""
	if not is_lying:
		return true  # Not lying, normal movement
	
	if not can_crawl:
		return false
	
	if crawl_cooldown > 0:
		return false
	
	# Additional checks could go here (stamina, injuries, etc)
	return true

func start_crawling():
	"""Start crawling movement"""
	if not is_lying:
		return
	
	emit_signal("crawl_state_changed", true)

func stop_crawling():
	"""Stop crawling movement"""
	emit_signal("crawl_state_changed", false)

func get_crawl_speed_modifier() -> float:
	"""Get the speed modifier when crawling"""
	if not is_lying:
		return 1.0
	
	return crawl_speed_multiplier
#endregion

#region CHECKS
func can_stand_up() -> bool:
	"""Check if the character can stand up"""
	# Check health
	if health_system:
		# Too injured (below 10% health)
		if health_system.health < (health_system.max_health * 0.1):
			return false
		
		# Too exhausted
		if health_system.staminaloss > 90:
			return false
	
	# Check limbs
	if limb_system:
		# Need at least one leg
		var has_leg = false
		if limb_system.has_method("has_limb"):
			has_leg = limb_system.has_limb("l_leg") or limb_system.has_limb("r_leg")
		
		if not has_leg:
			return false
	
	# Check status effects
	if status_effect_manager:
		if status_effect_manager.has_effect_flag("movement_restricting"):
			return false
	
	return true

func handle_failed_standup():
	"""Handle when standing up fails"""
	stand_up_attempts += 1
	
	# Show appropriate message
	var messages = [
		"You struggle to get up...",
		"You try to push yourself up, but fail.",
		"You can't seem to get up right now."
	]
	
	# More severe messages after multiple attempts
	if stand_up_attempts >= 3:
		messages = [
			"You're too weak to get up!",
			"Your body refuses to cooperate!",
			"You need help getting up!"
		]
	
	show_message(messages[stand_up_attempts % messages.size()])
	
	# Apply stamina loss
	if health_system and health_system.has_method("adjustStaminaLoss"):
		health_system.adjustStaminaLoss(5.0 * stand_up_attempts)
	
	emit_signal("stand_up_attempted", false)

func get_stamina_recovery_bonus() -> float:
	"""Get stamina recovery bonus when lying down"""
	if is_lying:
		return LYING_STAMINA_RECOVERY_BONUS
	return 1.0

func is_character_lying() -> bool:
	"""Check if character is lying down"""
	return is_lying

func get_lying_angle() -> float:
	"""Get current lying angle"""
	return lying_angle
#endregion

#region HELPERS
func get_current_direction() -> int:
	"""Get current facing direction"""
	if controller.movement_component:
		return controller.movement_component.current_direction
	return 2  # Default SOUTH

func show_message(text: String):
	"""Display message"""
	if sensory_system:
		sensory_system.display_message(text)
	else:
		print("PostureComponent: " + text)
#endregion

#region INTEGRATION
func apply_lying_effects():
	"""Apply effects of lying down"""
	# Movement speed handled by movement component
	
	# Visual effects
	if sprite_system:
		# Z-index changes for proper layering
		if controller.get_parent():
			var parent = controller.get_parent()
			if "z_index" in parent:
				parent.z_index = -1 if is_lying else 0
	
	# Collision changes
	# This would be handled by the physics/collision system

func remove_lying_effects():
	"""Remove effects of lying down"""
	# Reset z-index
	if controller.get_parent():
		var parent = controller.get_parent()
		if "z_index" in parent:
			parent.z_index = 0
#endregion
