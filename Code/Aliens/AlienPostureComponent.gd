extends PostureComponent
class_name AlienPostureComponent

# Aliens use different lying mechanics
var is_alien_entity: bool = true

func initialize(init_data: Dictionary):
	super.initialize(init_data)
	
	# Aliens cannot crawl
	can_crawl = false

func lie_down(forced: bool = false) -> bool:
	if not is_multiplayer_authority() and not forced:
		return false
		
	print("Alien attempting to rest")
	
	if not forced:
		if controller.movement_component and controller.movement_component.is_moving:
			print("Can't rest while moving")
			return false
		
		if controller.movement_component and controller.movement_component.is_stunned:
			print("Can't rest while stunned")
			return false
		
		if controller.movement_component and controller.movement_component.is_flying:
			print("Can't rest while flying")
			return false
	
	if is_lying:
		print("Already resting")
		return false
	
	is_lying = true
	last_lying_state_change = Time.get_ticks_msec() * 0.001
	
	if forced:
		forced_lying = true
	
	if controller.movement_component:
		if controller.movement_component.is_moving:
			controller.movement_component.is_moving = false
			controller.movement_component.move_progress = 0.0
			controller.position = controller.movement_component.tile_to_world(
				controller.movement_component.current_tile_position
			)
	
	sync_lying_state.rpc(is_lying, 0.0)
	
	# Use alien sprite system instead of human sprite rotation
	var alien_sprite_system = controller.get_node_or_null("AlienSpriteSystem")
	if alien_sprite_system and alien_sprite_system.has_method("set_lying_state"):
		alien_sprite_system.set_lying_state(true, _get_current_direction())
		print("Alien sprite system updated to resting state")
	
	sync_posture_action.rpc("lie_down", true, "The creature settles down to rest.")
	
	print("Alien successfully resting")
	return true

func get_up(forced: bool = false) -> bool:
	if not is_multiplayer_authority() and not forced:
		return false
		
	print("Alien attempting to get up")
	
	if not forced:
		if controller.movement_component and controller.movement_component.is_moving:
			print("Can't get up while moving")
			return false
		
		if controller.movement_component and controller.movement_component.is_stunned:
			print("Can't get up while stunned")
			return false
		
		if controller.movement_component and controller.movement_component.is_flying:
			print("Can't get up while flying")
			return false
		
		if health_forced_lying and not forced:
			print("Cannot get up due to health conditions")
			return false
	
	if not is_lying:
		print("Not resting")
		return false
	
	if not can_alien_stand_up() and not forced:
		_handle_failed_standup()
		return false
	
	is_lying = false
	last_lying_state_change = Time.get_ticks_msec() * 0.001
	stand_up_attempts = 0
	forced_lying = false
	health_forced_lying = false
	
	if controller.movement_component:
		if controller.movement_component.is_moving:
			controller.movement_component.is_moving = false
			controller.movement_component.move_progress = 0.0
			controller.position = controller.movement_component.tile_to_world(
				controller.movement_component.current_tile_position
			)
	
	sync_lying_state.rpc(is_lying, 0.0)
	
	# Use alien sprite system
	var alien_sprite_system = controller.get_node_or_null("AlienSpriteSystem")
	if alien_sprite_system and alien_sprite_system.has_method("set_lying_state"):
		alien_sprite_system.set_lying_state(false, _get_current_direction())
		print("Alien sprite system updated to standing state")
	
	sync_posture_action.rpc("get_up", true, "The creature rises back up.")
	
	print("Alien successfully got up")
	return true

func can_alien_stand_up() -> bool:
	# Aliens have different standing requirements than humans
	if health_system:
		if health_system.health < (health_system.max_health * 0.05):
			return false
		
		if health_system.status_effects.has("unconscious"):
			return false
		
		if health_system.status_effects.has("stunned"):
			return false
		
		# Aliens are more resilient to pain
		if health_system.pain_level > 95:
			return false
		
		# Check for critical limb damage
		var critical_damage = 0
		for limb_name in ["chest", "head"]:
			if health_system.limbs.has(limb_name):
				var limb = health_system.limbs[limb_name]
				if not limb.attached or limb.brute_damage + limb.burn_damage > limb.max_damage * 0.8:
					critical_damage += 1
		
		if critical_damage >= 1:
			return false
	
	return true

# Override crawling methods since aliens can't crawl
func can_crawl_in_direction(direction: Vector2i) -> bool:
	return false

func start_crawling():
	# Aliens don't crawl
	return

func stop_crawling():
	# Aliens don't crawl
	return

func get_crawl_speed_modifier() -> float:
	return 1.0

# Override stamina bonus since aliens rest differently
func get_stamina_recovery_bonus() -> float:
	if is_lying:
		return 2.0  # Aliens recover faster when resting
	return 1.0

func apply_lying_visual_effects():
	# Don't use sprite rotation for aliens
	var alien_sprite_system = controller.get_node_or_null("AlienSpriteSystem")
	if alien_sprite_system and alien_sprite_system.has_method("set_lying_state"):
		alien_sprite_system.set_lying_state(is_lying, _get_current_direction())
	
	# Adjust z-index for proper layering
	if controller.get_parent():
		var parent = controller.get_parent()
		if "z_index" in parent:
			parent.z_index = -1 if is_lying else 0

func remove_lying_effects():
	# Reset z-index
	if controller.get_parent():
		var parent = controller.get_parent()
		if "z_index" in parent:
			parent.z_index = 0

# Override human-specific lying angle functionality
func set_lying_angle(angle: float):
	# Aliens don't use lying angles
	return

func get_lying_angle() -> float:
	return 0.0

# Methods for alien-specific resting behavior
func force_rest():
	if not is_lying:
		health_forced_lying = true
		lie_down(true)

func can_rest() -> bool:
	return can_alien_stand_up()

func is_resting() -> bool:
	return is_lying

@rpc("any_peer", "reliable", "call_local")
func sync_posture_action(action: String, success: bool, message: String = ""):
	match action:
		"lie_down":
			if success:
				if audio_system:
					audio_system.play_positioned_sound("alien_rest", controller.position, 0.4)
				if message != "" and is_local_player:
					show_message(message)
		"get_up":
			if success:
				if audio_system:
					audio_system.play_positioned_sound("alien_rise", controller.position, 0.4)
				if message != "" and is_local_player:
					show_message(message)
			emit_signal("stand_up_attempted", success)
		"failed_standup":
			if message != "" and is_local_player:
				show_message(message)
			emit_signal("stand_up_attempted", false)
