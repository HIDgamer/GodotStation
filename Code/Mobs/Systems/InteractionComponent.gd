extends Node
class_name InteractionComponent

## Handles all interaction logic including click handling, intent-based actions, and entity interactions

#region CONSTANTS
const INTERACTION_COOLDOWN: float = 0.01
const EXAMINE_RANGE: float = 5.0
const DEFAULT_INTERACTION_RANGE: float = 1.5
#endregion

#region ENUMS
enum InteractionFlags {
	NONE = 0,
	ADJACENT = 1,
	RANGED = 2,
	SELF = 4,
	WITH_ITEM = 8,
	HELP_INTENT = 16,
	COMBAT_MODE = 32
}
#endregion

#region SIGNALS
signal interaction_started(entity: Node)
signal interaction_completed(entity: Node, success: bool)
signal interaction_requested(target: Node)
signal examine_result(target: Node, text: String)
signal tile_interaction(tile_coords: Vector2i, interaction_type: String)
#endregion

#region PROPERTIES
# Core references
var controller: Node = null
var sensory_system = null
var audio_system = null
var inventory_system = null
var world = null

# Interaction state
var is_local_player: bool = false
var current_interaction_flags: int = InteractionFlags.NONE
var last_interaction_time: float = 0.0
var interaction_range: float = DEFAULT_INTERACTION_RANGE

# Safety preferences
var help_intent_safety: bool = false
var allow_self_harm: bool = false
#endregion

func initialize(init_data: Dictionary):
	"""Initialize the interaction component"""
	controller = init_data.get("controller")
	sensory_system = init_data.get("sensory_system")
	audio_system = init_data.get("audio_system")
	inventory_system = init_data.get("inventory_system")
	world = init_data.get("world")
	is_local_player = init_data.get("is_local_player", false)

#region MAIN INTERACTION PROCESSING
func process_interaction(target: Node, button_index: int = MOUSE_BUTTON_LEFT, shift_pressed: bool = false, ctrl_pressed: bool = false, alt_pressed: bool = false) -> bool:
	"""Main interaction handler"""
	if not target:
		return false
	
	print("InteractionComponent: Processing interaction with ", target.name)
	
	# Handle examine first (no cooldown)
	if shift_pressed and not ctrl_pressed and not alt_pressed:
		return handle_examine_interaction(target)
	
	# Check cooldown
	var current_time = Time.get_ticks_msec() / 500.0
	if current_time < last_interaction_time + INTERACTION_COOLDOWN:
		return false
	
	# Check range
	if not can_interact_with(target):
		show_message("That's too far away.")
		return false
	
	# Face target
	face_entity(target)
	
	# Determine interaction type
	var result = false
	
	if ctrl_pressed and not shift_pressed and not alt_pressed:
		result = handle_ctrl_interaction(target)
	elif alt_pressed and not shift_pressed and not ctrl_pressed:
		result = handle_alt_interaction(target)
	elif button_index == MOUSE_BUTTON_RIGHT:
		result = handle_context_interaction(target)
	elif button_index == MOUSE_BUTTON_MIDDLE:
		result = handle_middle_interaction(target)
	else:
		result = await handle_intent_interaction(target)
	
	# Update cooldown if successful
	if result:
		last_interaction_time = current_time
		emit_signal("interaction_completed", target, true)
	
	return result

func handle_tile_click(tile_coords: Vector2i, mouse_button: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	"""Handle clicks on tiles"""
	# Face the clicked tile
	var world_pos = tile_to_world(tile_coords)
	face_entity(world_pos)
	
	match mouse_button:
		MOUSE_BUTTON_LEFT:
			if shift_pressed:
				examine_tile(tile_coords)
			elif alt_pressed:
				handle_alt_tile_action(tile_coords)
			else:
				# Check for throw mode
				if controller.item_interaction_component and controller.item_interaction_component.is_throw_mode_active:
					controller.item_interaction_component.throw_at_tile(tile_coords)
				else:
					# Try to interact with tile contents
					var entity = get_entity_on_tile(tile_coords)
					if entity and is_adjacent_to_tile(tile_coords):
						await process_interaction(entity)
		
		MOUSE_BUTTON_RIGHT:
			handle_tile_context_menu(tile_coords)
		
		MOUSE_BUTTON_MIDDLE:
			if shift_pressed:
				point_to(world_pos)
#endregion

#region INTERACTION TYPES
func handle_examine_interaction(target: Node) -> bool:
	"""Handle examine (shift+click)"""
	if not can_interact_with(target, EXAMINE_RANGE):
		show_message("That's too far to examine.")
		return false
	
	face_entity(target)
	
	# Get examine text
	var examine_text = get_examine_text(target)
	
	# Display text
	if sensory_system:
		sensory_system.display_message("[color=#AAAAAA]" + examine_text + "[/color]")
	
	emit_signal("examine_result", target, examine_text)
	
	# Play sound
	if audio_system:
		audio_system.play_positioned_sound("examine", controller.position, 0.2)
	
	return true

func handle_ctrl_interaction(target: Node) -> bool:
	"""Handle ctrl+click (pull/drag)"""
	if target == controller or target == controller.get_parent():
		show_message("You can't pull yourself!")
		return false
	
	if "can_be_pulled" in target and not target.can_be_pulled:
		show_message("You can't pull that!")
		return false
	
	# Delegate to grab/pull component
	if controller.grab_pull_component:
		return controller.grab_pull_component.pull_entity(target)
	
	return false

func handle_alt_interaction(target: Node) -> bool:
	"""Handle alt+click (special actions)"""
	face_entity(target)
	
	if target.has_method("alt_click"):
		return target.alt_click(controller)
	
	if target.has_method("toggle"):
		return target.toggle(controller)
	
	return false

func handle_context_interaction(target: Node) -> bool:
	"""Handle right-click (context menu)"""
	var click_system = controller.click_system
	if click_system and click_system.has_method("show_radial_menu"):
		var mouse_pos = controller.get_viewport().get_mouse_position()
		click_system.show_radial_menu(target, mouse_pos)
		return true
	
	return false

func handle_middle_interaction(target: Node) -> bool:
	"""Handle middle-click (point)"""
	var target_pos = get_entity_position(target)
	if target_pos != Vector2.ZERO:
		point_to(target_pos)
		return true
	
	return false

func handle_intent_interaction(target: Node) -> bool:
	"""Handle intent-based interaction"""
	# Setup flags
	current_interaction_flags = InteractionFlags.ADJACENT
	
	if target == controller or target == controller.get_parent():
		current_interaction_flags |= InteractionFlags.SELF
	
	var active_item = get_active_item()
	if active_item:
		current_interaction_flags |= InteractionFlags.WITH_ITEM
	
	var intent = controller.intent_component.intent if controller.intent_component else 0
	if intent == 0: # HELP
		current_interaction_flags |= InteractionFlags.HELP_INTENT
	
	# Trigger visual effect
	trigger_interaction_thrust(target, intent)
	
	# Route based on intent
	var result = false
	match intent:
		0: # HELP
			result = await handle_help_interaction(target, active_item)
		1: # DISARM
			result = handle_disarm_interaction(target, active_item)
		2: # GRAB
			result = handle_grab_interaction(target, active_item)
		3: # HARM
			result = handle_harm_interaction(target, active_item)
		_:
			result = await handle_help_interaction(target, active_item)
	
	return result
#endregion

#region INTENT HANDLERS
func handle_help_interaction(target: Node, active_item) -> bool:
	"""Handle help intent interactions"""
	# Self-interaction
	if current_interaction_flags & InteractionFlags.SELF:
		return handle_help_self_interaction(active_item)
	
	# With item
	if active_item:
		# Safety check
		if help_intent_safety and is_item_harmful(active_item):
			show_message("You don't want to hurt " + get_target_name(target) + " with that!")
			play_safety_sound()
			return false
		
		return await use_item_on_target(active_item, target)
	
	# No item - friendly interaction or pickup
	return handle_friendly_interaction(target)

func handle_disarm_interaction(target: Node, active_item) -> bool:
	"""Handle disarm intent interactions"""
	if current_interaction_flags & InteractionFlags.SELF:
		show_message("You can't disarm yourself!")
		return false
	
	if active_item:
		show_message("You need empty hands to disarm!")
		return false
	
	# Try to disarm
	if target.has_method("get_active_item"):
		var target_item = target.get_active_item()
		if target_item:
			return attempt_disarm(target, target_item)
		else:
			return attempt_push_shove(target)
	else:
		return attempt_push_shove(target)

func handle_grab_interaction(target: Node, active_item) -> bool:
	"""Handle grab intent interactions"""
	if "entity_type" in target and target.entity_type == "item":
		return false
	
	if current_interaction_flags & InteractionFlags.SELF:
		show_message("You can't grab yourself!")
		return false
	
	# Check if already grabbing
	if controller.grab_pull_component:
		if controller.grab_pull_component.grabbing_entity == target:
			return controller.grab_pull_component.upgrade_grab()
		elif controller.grab_pull_component.grabbing_entity != null:
			var grabbed_name = get_target_name(controller.grab_pull_component.grabbing_entity)
			show_message("You're already grabbing " + grabbed_name + "!")
			return false
	
	# Need free hand
	if active_item and not is_grab_compatible_item(active_item):
		show_message("You need a free hand to grab!")
		return false
	
	# Delegate to grab component
	if controller.grab_pull_component:
		return controller.grab_pull_component.grab_entity(target, 0) # PASSIVE
	
	return false

func handle_harm_interaction(target: Node, active_item) -> bool:
	"""Handle harm intent interactions"""
	# Self-harm check
	if current_interaction_flags & InteractionFlags.SELF:
		if not allow_self_harm:
			show_message("You have the discipline not to hurt yourself.")
			play_safety_sound()
			return false
		
		return handle_self_harm(active_item)
	
	# Attack target
	if active_item:
		return attack_with_item(active_item, target)
	else:
		return attack_unarmed(target)
#endregion

#region SPECIFIC INTERACTIONS
func handle_help_self_interaction(active_item) -> bool:
	"""Handle using item on self with help intent"""
	if active_item:
		if active_item.has_method("use_on_self"):
			return active_item.use_on_self(controller)
		elif active_item.has_method("attack_self"):
			return active_item.attack_self(controller)
	
	show_message("You pat yourself down.")
	return true

func handle_friendly_interaction(target: Node) -> bool:
	"""Handle friendly interaction without item"""
	# Check if it's an item to pick up
	if "entity_type" in target and target.entity_type == "item":
		if "pickupable" in target and target.pickupable:
			if controller.item_interaction_component:
				return controller.item_interaction_component.try_pick_up_item(target)
	
	# Try interaction methods
	if target.has_method("attack_hand"):
		target.attack_hand(controller)
		return true
	
	if target.has_method("interact"):
		return target.interact(controller)
	
	if target.has_method("use"):
		return target.use(controller)
	
	# Default poke
	show_message("You poke " + get_target_name(target))
	return true

func handle_self_harm(active_item) -> bool:
	"""Handle harming self"""
	if active_item:
		var damage = 5.0
		if "force" in active_item:
			damage = active_item.force
		
		controller.take_damage(damage, "brute")
		show_message("You hurt yourself with " + get_item_name(active_item) + "!")
	else:
		controller.take_damage(3.0, "brute")
		show_message("You punch yourself!")
	
	return true

func use_item_on_target(item: Node, target: Node) -> bool:
	"""Use an item on a target"""
	print("InteractionComponent: Using item ", item.name, " on ", target.name)
	
	# Try target's attackby method first
	if target.has_method("attackby"):
		var result = await target.attackby(item, controller)
		if result:
			return result
	
	# Try item methods
	if item.has_method("use_on"):
		return await item.use_on(target, controller)
	
	if item.has_method("attack"):
		return item.attack(target, controller)
	
	if item.has_method("afterattack"):
		return item.afterattack(target, controller, true)
	
	# Generic use
	if target.has_method("attack_hand"):
		target.attack_hand(controller)
		return true
	
	# Default message
	show_message("You use " + get_item_name(item) + " on " + get_target_name(target) + ".")
	return true
#endregion

#region COMBAT INTERACTIONS
func attempt_disarm(target: Node, target_item: Node) -> bool:
	"""Attempt to disarm a target"""
	var base_chance = 25.0
	var user_skill = 10.0 # Default dexterity
	var target_resistance = 0.0
	
	if "dexterity" in target:
		target_resistance = target.dexterity * 1.0
	
	var item_grip = 0.0
	if "grip_strength" in target_item:
		item_grip = target_item.grip_strength
	elif "w_class" in target_item:
		item_grip = target_item.w_class * 5.0
	
	var disarm_chance = base_chance + user_skill - target_resistance - item_grip
	disarm_chance = clamp(disarm_chance, 5.0, 95.0)
	
	# Roll
	if randf() * 100.0 < disarm_chance:
		# Success
		if target.has_method("drop_item"):
			target.drop_item(target_item)
		elif target.has_method("drop_active_item"):
			target.drop_active_item()
		
		# Make target lie down
		if target.has_method("toggle_lying"):
			target.toggle_lying()
		
		# Stun
		if target.has_method("stun"):
			target.stun(2.0)
		
		show_message("You disarm " + get_target_name(target) + ", knocking them down!")
		
		if audio_system:
			audio_system.play_positioned_sound("disarm", controller.position, 0.5)
		
		return true
	else:
		# Failed
		show_message("You fail to disarm " + get_target_name(target) + ".")
		return false

func attempt_push_shove(target: Node) -> bool:
	"""Attempt to push/shove a target"""
	if "entity_type" in target and target.entity_type == "item":
		return false
	
	var base_chance = 30.0
	var user_strength = 20.0 # Default strength
	var target_resistance = 0.0
	
	if "dexterity" in target:
		target_resistance = target.dexterity * 1.5
	
	# Modifiers
	if "is_lying" in target and target.is_lying:
		base_chance += 20.0
	
	if "is_stunned" in target and target.is_stunned:
		base_chance += 30.0
	
	var push_chance = base_chance + user_strength - target_resistance
	push_chance = clamp(push_chance, 10.0, 80.0)
	
	if randf() * 100.0 < push_chance:
		# Success
		show_message("You shove " + get_target_name(target) + "!")
		
		if target.has_method("apply_knockback"):
			var push_dir = (get_entity_position(target) - controller.position).normalized()
			target.apply_knockback(push_dir, 15.0)
		
		if target.has_method("stun"):
			target.stun(0.5)
		
		if target.has_method("toggle_lying"):
			target.toggle_lying()
		
		if audio_system:
			audio_system.play_positioned_sound("punch", controller.position, 0.3)
		
		return true
	else:
		show_message("You try to shove " + get_target_name(target) + " but they resist!")
		return false

func attack_with_item(item: Node, target: Node) -> bool:
	"""Attack target with item"""
	var is_weapon = false
	var weapon_damage = 5.0
	var damage_type = "brute"
	
	if "tool_behaviour" in item and item.tool_behaviour == "weapon":
		is_weapon = true
		weapon_damage = item.get("force")
		damage_type = item.get("brute")
	elif "force" in item and item.force > 0:
		is_weapon = true
		weapon_damage = item.force
		damage_type = item.get("brute")
	else:
		weapon_damage = max(1.0, item.get("force"))
	
	# Calculate hit chance
	var attack_chance = 75.0
	attack_chance += 10.0 # Base dexterity bonus
	
	if "dexterity" in target:
		attack_chance -= target.dexterity * 0.5
	
	if "is_lying" in target and target.is_lying:
		attack_chance += 20.0
	
	if "is_stunned" in target and target.is_stunned:
		attack_chance += 40.0
	
	attack_chance = clamp(attack_chance, 10.0, 95.0)
	
	# Roll to hit
	if randf() * 100.0 < attack_chance:
		# Hit!
		apply_damage_to_target(target, weapon_damage, damage_type)
		
		var target_zone = controller.body_targeting_component.get_selected_zone() if controller.body_targeting_component else "chest"
		if target.has_method("take_damage_to_zone"):
			target.take_damage_to_zone(weapon_damage, damage_type, target_zone)
		
		show_message("You hit " + get_target_name(target) + " with " + get_item_name(item) + "!")
		
		if target.has_method("show_interaction_message"):
			target.show_interaction_message(controller.entity_name + " hits you with " + get_item_name(item) + "!")
		
		# Play sound
		var hit_sound = "hit"
		if "hitsound" in item:
			hit_sound = item.hitsound
		elif is_weapon:
			hit_sound = "weapon_hit"
		
		if audio_system:
			audio_system.play_positioned_sound(hit_sound, controller.position, 0.6)
		
		# Item effects
		if item.has_method("on_hit"):
			item.on_hit(target, controller)
		
		return true
	else:
		# Miss
		show_message("You swing " + get_item_name(item) + " at " + get_target_name(target) + " but miss!")
		
		if audio_system:
			audio_system.play_positioned_sound("swing", controller.position, 0.4)
		
		return false

func attack_unarmed(target: Node) -> bool:
	"""Attack target with bare hands"""
	var punch_damage = 3.0
	punch_damage += 3.0 # Base strength bonus
	
	var attack_chance = 70.0
	attack_chance += 12.0 # Base dexterity bonus
	
	if "dexterity" in target:
		attack_chance -= target.dexterity * 0.7
	
	if "is_lying" in target and target.is_lying:
		attack_chance += 25.0
		punch_damage += 1.0
	
	if "is_stunned" in target and target.is_stunned:
		attack_chance += 35.0
		punch_damage += 2.0
	
	attack_chance = clamp(attack_chance, 15.0, 90.0)
	
	if randf() * 100.0 < attack_chance:
		# Hit
		apply_damage_to_target(target, punch_damage, "brute")
		
		var target_zone = controller.body_targeting_component.get_selected_zone() if controller.body_targeting_component else "chest"
		if target.has_method("take_damage_to_zone"):
			target.take_damage_to_zone(punch_damage, "brute", target_zone)
		
		var attack_verb = get_unarmed_attack_verb(target_zone)
		show_message("You " + attack_verb + " " + get_target_name(target) + "!")
		
		if target.has_method("show_interaction_message"):
			target.show_interaction_message(controller.entity_name + " " + attack_verb + "s you!")
		
		if audio_system:
			audio_system.play_positioned_sound("punch", controller.position, 0.5)
		
		# Chance to stun on head hits
		if target_zone == "head" and randf() < 0.1:
			if target.has_method("stun"):
				target.stun(1.0)
				show_message(get_target_name(target) + " staggers from the blow!")
		
		return true
	else:
		# Miss
		show_message("You throw a punch at " + get_target_name(target) + " but miss!")
		
		if audio_system:
			audio_system.play_positioned_sound("swing", controller.position, 0.3)
		
		return false
#endregion

#region TILE INTERACTIONS
func examine_tile(tile_position: Vector2i):
	"""Examine a tile"""
	if not world:
		return
	
	var z_level = controller.current_z_level if controller else 0
	var tile_data = world.get_tile_data(tile_position, z_level)
	if not tile_data:
		return
	
	var description = "You see nothing special."
	
	# Generate description
	if "door" in tile_data:
		description = "A door. It appears to be " + ("closed" if tile_data.door.closed else "open") + "."
		if "locked" in tile_data.door and tile_data.door.locked:
			description += " It seems to be locked."
		if "broken" in tile_data.door and tile_data.door.broken:
			description += " It looks broken."
	elif "window" in tile_data:
		description = "A window made of glass."
		if "reinforced" in tile_data.window and tile_data.window.reinforced:
			description += " It appears to be reinforced."
		if "health" in tile_data.window and tile_data.window.health < tile_data.window.max_health:
			description += " It has some cracks."
	elif "floor" in tile_data:
		description = "A " + tile_data.floor.type + " floor."
	elif "wall" in tile_data:
		description = "A solid wall made of " + tile_data.wall.material + "."
	
	emit_signal("examine_result", {"tile_position": tile_position}, description)
	
	if sensory_system:
		sensory_system.display_message("[color=#AAAAAA]" + description + "[/color]")

func handle_alt_tile_action(tile_coords: Vector2i):
	"""Handle alt+click on tile"""
	var z_level = controller.current_z_level if controller else 0
	var tile_data = world.get_tile_data(tile_coords, z_level) if world else null
	if not tile_data:
		return
	
	# Alt-click on door to toggle
	if "door" in tile_data:
		if world and world.has_method("toggle_door"):
			world.toggle_door(tile_coords, z_level)
			emit_signal("tile_interaction", tile_coords, "door_toggle")
		return
	
	# Alt-click on window to knock
	if "window" in tile_data:
		if world and world.has_method("knock_window"):
			world.knock_window(tile_coords, z_level)
			emit_signal("tile_interaction", tile_coords, "window_knock")
		return

func handle_tile_context_menu(tile_coords: Vector2i):
	"""Create context menu for tile"""
	var options = []
	
	# Add examine option
	options.append({
		"name": "Examine Tile",
		"icon": "examine",
		"action": "examine_tile",
		"params": {"position": tile_coords}
	})
	
	# Check for special tile features
	var z_level = controller.current_z_level if controller else 0
	var tile_data = world.get_tile_data(tile_coords, z_level) if world else null
	
	if tile_data:
		if "door" in tile_data:
			var door = tile_data.door
			if door.closed:
				options.append({
					"name": "Open Door",
					"icon": "door_open",
					"action": "toggle_door",
					"params": {"position": tile_coords}
				})
			else:
				options.append({
					"name": "Close Door",
					"icon": "door_close",
					"action": "toggle_door",
					"params": {"position": tile_coords}
				})
	
	# Show menu
	if world and "context_interaction_system" in world:
		world.context_interaction_system.show_context_menu(options, controller.get_viewport().get_mouse_position())

func point_to(position: Vector2):
	"""Point to a location"""
	var direction = (position - controller.position).normalized()
	var dir_text = get_direction_text(direction)
	
	show_message(controller.entity_name + " points to the " + dir_text + ".")
	
	# Visual effect
	if world and world.has_method("spawn_visual_effect"):
		world.spawn_visual_effect("point", position, 1.0)
#endregion

#region HELPER FUNCTIONS
func can_interact_with(target: Node, max_range: float = DEFAULT_INTERACTION_RANGE) -> bool:
	"""Check if can interact with target"""
	if not target:
		return false
	
	# Self-interaction always allowed
	if target == controller or target == controller.get_parent():
		return true
	
	# Check adjacency for most interactions
	if not is_adjacent_to(target):
		# Check for ranged interactions
		var distance = get_distance_to(target)
		
		# Weapon range
		var active_item = get_active_item()
		if active_item and "max_range" in active_item:
			return distance <= active_item.max_range
		
		# Throw range
		if controller.item_interaction_component and controller.item_interaction_component.is_throw_mode_active:
			return distance <= 10.0
		
		# Examine range
		if controller.intent_component and controller.intent_component.intent == 0:
			return distance <= EXAMINE_RANGE
		
		return false
	
	return true

func is_adjacent_to(target: Node) -> bool:
	"""Check if adjacent to target"""
	if not controller.movement_component:
		return false
	
	return controller.movement_component.is_adjacent_to(target)

func is_adjacent_to_tile(tile_coords: Vector2i) -> bool:
	"""Check if adjacent to tile"""
	if not controller.movement_component:
		return false
	
	var my_pos = controller.movement_component.current_tile_position
	var diff_x = abs(my_pos.x - tile_coords.x)
	var diff_y = abs(my_pos.y - tile_coords.y)
	
	return (diff_x <= 1 and diff_y <= 1) and not (diff_x == 0 and diff_y == 0)

func get_distance_to(target: Node) -> float:
	"""Get distance to target in tiles"""
	if not controller.movement_component:
		return 999.0
	
	var my_pos = Vector2(controller.movement_component.current_tile_position)
	var target_pos_int = get_entity_tile_position(target)
	var target_pos = Vector2(target_pos_int.x, target_pos_int.y)
	
	return my_pos.distance_to(target_pos)

func get_entity_tile_position(entity: Node) -> Vector2i:
	"""Get tile position of entity"""
	if not entity:
		return Vector2i.ZERO
	
	if "current_tile_position" in entity:
		return entity.current_tile_position
	elif entity.has_node("GridMovementController"):
		var grid_controller = entity.get_node("GridMovementController")
		return grid_controller.get_current_tile_position()
	elif controller.movement_component:
		return controller.movement_component.get_entity_tile_position(entity)
	
	return Vector2i.ZERO

func get_entity_position(entity: Node) -> Vector2:
	"""Get world position of entity"""
	if "global_position" in entity:
		return entity.global_position
	elif "position" in entity:
		return entity.position
	
	return Vector2.ZERO

func get_entity_on_tile(tile_coords: Vector2i) -> Node:
	"""Get entity on a specific tile"""
	if world and "tile_occupancy_system" in world and world.tile_occupancy_system:
		var z_level = controller.current_z_level if controller else 0
		var entities = world.tile_occupancy_system.get_entities_at(tile_coords, z_level)
		if entities and entities.size() > 0:
			return entities[0]
	return null

func face_entity(target):
	"""Make entity face a target"""
	if not controller.movement_component:
		return
	
	var target_position = Vector2.ZERO
	
	if typeof(target) == TYPE_VECTOR2:
		target_position = target
	elif target.has_method("global_position"):
		target_position = target.global_position
	elif "position" in target:
		target_position = target.position
	else:
		return
	
	var direction_vector = target_position - controller.position
	if direction_vector == Vector2.ZERO:
		return
	
	direction_vector = direction_vector.normalized()
	
	var grid_direction = Vector2i(
		round(direction_vector.x),
		round(direction_vector.y)
	)
	
	if grid_direction.x != 0 and grid_direction.y != 0:
		grid_direction.x = sign(grid_direction.x)
		grid_direction.y = sign(grid_direction.y)
	elif grid_direction == Vector2i.ZERO:
		if abs(direction_vector.x) > abs(direction_vector.y):
			grid_direction.x = sign(direction_vector.x)
		else:
			grid_direction.y = sign(direction_vector.y)
	
	controller.movement_component.update_facing_from_movement(grid_direction)

func trigger_interaction_thrust(target: Node, intent: int):
	"""Trigger visual thrust effect"""
	if controller.sprite_system and controller.sprite_system.has_method("show_interaction_thrust"):
		var direction_to_target = get_direction_to_target(target)
		controller.sprite_system.show_interaction_thrust(direction_to_target, intent)

func get_direction_to_target(target: Node) -> Vector2:
	"""Get direction vector to target"""
	var target_pos = get_entity_position(target)
	if target_pos == Vector2.ZERO:
		return Vector2.ZERO
	
	var my_pos = controller.position
	return (target_pos - my_pos).normalized()

func get_direction_text(direction: Vector2) -> String:
	"""Convert direction to text"""
	var angle = rad_to_deg(atan2(direction.y, direction.x))
	
	if angle > -22.5 and angle <= 22.5:
		return "east"
	elif angle > 22.5 and angle <= 67.5:
		return "southeast"
	elif angle > 67.5 and angle <= 112.5:
		return "south"
	elif angle > 112.5 and angle <= 157.5:
		return "southwest"
	elif angle > 157.5 or angle <= -157.5:
		return "west"
	elif angle > -157.5 and angle <= -112.5:
		return "northwest"
	elif angle > -112.5 and angle <= -67.5:
		return "north"
	elif angle > -67.5 and angle <= -22.5:
		return "northeast"
	
	return "somewhere"

func tile_to_world(tile_pos: Vector2i) -> Vector2:
	"""Convert tile to world position"""
	return Vector2((tile_pos.x * 32) + 16, (tile_pos.y * 32) + 16)

func get_active_item():
	"""Get currently held item"""
	if inventory_system and inventory_system.has_method("get_active_item"):
		return inventory_system.get_active_item()
	
	return null

func get_examine_text(target: Node) -> String:
	"""Get examine text for target"""
	if target.has_method("examine"):
		return target.examine(controller)
	elif target.has_method("get_examine_text"):
		return target.get_examine_text(controller)
	elif "description" in target:
		return target.description
	elif "examine_desc" in target:
		return target.examine_desc
	else:
		var name = target.name if "name" in target else "something"
		return "This is " + name + "."

func get_target_name(target: Node) -> String:
	"""Get proper name for target"""
	if "entity_name" in target and target.entity_name != "":
		return target.entity_name
	elif "name" in target:
		return target.name
	else:
		return "that"

func get_item_name(item: Node) -> String:
	"""Get proper name for item"""
	if "item_name" in item:
		return item.item_name
	elif "name" in item:
		return item.name
	else:
		return "something"

func get_unarmed_attack_verb(zone: String) -> String:
	"""Get attack verb for unarmed attack on zone"""
	match zone:
		"head", "eyes", "mouth":
			return "punch"
		"chest":
			return "punch"
		"groin":
			return "knee"
		"l_leg", "r_leg", "l_foot", "r_foot":
			return "kick"
		_:
			return "hit"

func is_item_harmful(item: Node) -> bool:
	"""Check if item is harmful"""
	if "force" in item and item.force > 0:
		return true
	if "tool_behaviour" in item and item.tool_behaviour == "weapon":
		return true
	if "harmful" in item and item.harmful:
		return true
	return false

func is_grab_compatible_item(item: Node) -> bool:
	"""Check if item allows grabbing"""
	if "w_class" in item:
		return item.w_class <= 2
	if "allows_grabbing" in item:
		return item.allows_grabbing
	return false

func apply_damage_to_target(target: Node, damage: float, damage_type: String):
	"""Apply damage to target"""
	if target.has_method("take_damage"):
		target.take_damage(damage, damage_type)
	elif target.has_method("apply_damage"):
		target.apply_damage(damage, damage_type)

func show_message(text: String):
	"""Display message to player"""
	if sensory_system:
		sensory_system.display_message(text)
	else:
		print("Interaction: " + text)

func play_safety_sound():
	"""Play safety buzz sound"""
	if audio_system:
		audio_system.play_positioned_sound("buzz", controller.position, 0.3)

func _on_intent_changed(new_intent: int):
	"""Handle intent changes"""
	# Update help intent safety based on new intent
	if new_intent == 0: # HELP
		current_interaction_flags |= InteractionFlags.HELP_INTENT
	else:
		current_interaction_flags &= ~InteractionFlags.HELP_INTENT
#endregion
