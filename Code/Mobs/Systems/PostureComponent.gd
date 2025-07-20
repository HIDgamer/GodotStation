extends Node
class_name PostureComponent

## Handles lying down, standing up, and crawling mechanics with multiplayer sync

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

# Synced lying state
@export var is_lying: bool = false : set = _set_is_lying
@export var lying_angle: float = LYING_ANGLE : set = _set_lying_angle
@export var can_crawl: bool = true

# Local state (not synced)
var last_lying_state_change: float = 0.0
var stand_up_attempts: int = 0
var crawl_cooldown: float = 0.0
var crawl_speed_multiplier: float = 0.5

# Multiplayer properties
var is_local_player: bool = false
var peer_id: int = 1
#endregion

#region MULTIPLAYER SETTERS
func _set_is_lying(value: bool):
	var old_lying = is_lying
	is_lying = value
	
	# Only emit signal if value actually changed
	if old_lying != is_lying:
		emit_signal("lying_state_changed", is_lying)
		
		# Apply visual effects when state changes
		apply_lying_visual_effects()

func _set_lying_angle(value: float):
	lying_angle = value
	
	# Update sprite angle if lying
	if is_lying and sprite_system and sprite_system.has_method("set_lying_angle"):
		sprite_system.set_lying_angle(lying_angle)
#endregion

func initialize(init_data: Dictionary):
	"""Initialize the posture component"""
	controller = init_data.get("controller")
	sensory_system = init_data.get("sensory_system")
	audio_system = init_data.get("audio_system")
	sprite_system = init_data.get("sprite_system")
	is_local_player = init_data.get("is_local_player", false)
	peer_id = init_data.get("peer_id", 1)
	
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

#region AUTHORITY HELPERS
func setup_singleplayer():
	"""Setup for single-player mode"""
	is_local_player = true
	peer_id = 1

func setup_multiplayer(player_peer_id: int):
	"""Setup for multiplayer mode"""
	peer_id = player_peer_id
	is_local_player = (peer_id == multiplayer.get_unique_id())
#endregion

#region MULTIPLAYER SYNC METHODS
@rpc("any_peer", "reliable", "call_local")
func sync_lying_state(lying: bool, angle: float):
	"""Sync lying state across all clients"""
	if not is_multiplayer_authority():
		is_lying = lying
		lying_angle = angle
		
		# Apply visual effects on all clients
		apply_lying_visual_effects()

@rpc("any_peer", "reliable", "call_local")
func sync_posture_action(action: String, success: bool, message: String = ""):
	"""Sync posture actions (lying down, getting up) across all clients"""
	# Play audio and show messages on all clients
	match action:
		"lie_down":
			if success:
				if audio_system:
					audio_system.play_positioned_sound("body_fall", controller.position, 0.4)
				if message != "" and is_local_player:
					show_message(message)
		"get_up":
			if success:
				if audio_system:
					audio_system.play_positioned_sound("rustle", controller.position, 0.4)
				if message != "" and is_local_player:
					show_message(message)
			# Emit signal on all clients
			emit_signal("stand_up_attempted", success)
		"failed_standup":
			if message != "" and is_local_player:
				show_message(message)
			emit_signal("stand_up_attempted", false)

@rpc("any_peer", "reliable", "call_local")
func sync_crawl_state(crawling: bool):
	"""Sync crawling state across all clients"""
	emit_signal("crawl_state_changed", crawling)
#endregion

#region PUBLIC INTERFACE
func toggle_lying() -> bool:
	"""Toggle between lying and standing - only on authority"""
	if not is_multiplayer_authority():
		return false
		
	if Time.get_ticks_msec() * 0.001 - last_lying_state_change < LYING_STATE_CHANGE_COOLDOWN:
		return false
	
	if is_lying:
		return get_up()
	else:
		return await lie_down()

func lie_down(forced: bool = false) -> bool:
	"""Make the character lie down - only on authority"""
	if not is_multiplayer_authority() and not forced:
		return false
		
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
	
	# Sync the lying state to all clients
	sync_lying_state.rpc(is_lying, lying_angle)
	
	# Update sprite first (this happens on all clients via the setter)
	var sprites_updated = false
	if sprite_system and sprite_system.has_method("set_lying_state"):
		sprite_system.set_lying_state(true, get_current_direction())
		sprites_updated = true
		print("PostureComponent: Sprite system updated to lying state")
	
	# Wait for sprite update
	if sprites_updated:
		await controller.get_tree().create_timer(0.1).timeout
	
	# Sync audio and message to all clients
	sync_posture_action.rpc("lie_down", true, "You lie down.")
	
	print("PostureComponent: Successfully lying down")
	return true

func get_up(forced: bool = false) -> bool:
	"""Attempt to stand up - only on authority"""
	if not is_multiplayer_authority() and not forced:
		return false
		
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
	
	# Sync the lying state to all clients
	sync_lying_state.rpc(is_lying, lying_angle)
	
	# Update sprite (happens on all clients via the setter)
	if sprite_system and sprite_system.has_method("set_lying_state"):
		sprite_system.set_lying_state(false, get_current_direction())
		print("PostureComponent: Sprite system updated to standing state")
	
	# Sync audio and message to all clients
	sync_posture_action.rpc("get_up", true, "You get back up.")
	
	print("PostureComponent: Successfully got up")
	return true

func handle_rest_toggle():
	"""Handle the rest key being pressed - only on authority"""
	if not is_multiplayer_authority():
		return
		
	emit_signal("rest_toggled")
	toggle_lying()

func set_lying_angle(angle: float):
	"""Set the lying angle for visual representation"""
	if not is_multiplayer_authority():
		return
		
	lying_angle = angle
	
	# Sync the angle change
	sync_lying_state.rpc(is_lying, lying_angle)

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
	"""Start crawling movement - only on authority"""
	if not is_multiplayer_authority():
		return
		
	if not is_lying:
		return
	
	# Sync crawling state to all clients
	sync_crawl_state.rpc(true)

func stop_crawling():
	"""Stop crawling movement - only on authority"""
	if not is_multiplayer_authority():
		return
		
	# Sync crawling state to all clients
	sync_crawl_state.rpc(false)

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
	"""Handle when standing up fails - only on authority"""
	if not is_multiplayer_authority():
		return
		
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
	
	var message = messages[stand_up_attempts % messages.size()]
	
	# Apply stamina loss
	if health_system and health_system.has_method("adjustStaminaLoss"):
		health_system.adjustStaminaLoss(5.0 * stand_up_attempts)
	
	# Sync failed standup to all clients
	sync_posture_action.rpc("failed_standup", false, message)

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
	"""Display message - only for local player"""
	if sensory_system and is_local_player:
		sensory_system.display_message(text)
	elif is_local_player:
		print("PostureComponent: " + text)

func apply_lying_visual_effects():
	"""Apply visual effects of lying state"""
	# Update sprite system
	if sprite_system and sprite_system.has_method("set_lying_state"):
		sprite_system.set_lying_state(is_lying, get_current_direction())
	
	# Z-index changes for proper layering
	if controller.get_parent():
		var parent = controller.get_parent()
		if "z_index" in parent:
			parent.z_index = -1 if is_lying else 0
#endregion

#region INTEGRATION
func apply_lying_effects():
	"""Apply effects of lying down"""
	apply_lying_visual_effects()

func remove_lying_effects():
	"""Remove effects of lying down"""
	# Reset z-index
	if controller.get_parent():
		var parent = controller.get_parent()
		if "z_index" in parent:
			parent.z_index = 0
#endregion
