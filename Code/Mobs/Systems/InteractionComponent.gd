extends Node
class_name InteractionComponent

# Interaction range constants
const INTERACTION_COOLDOWN: float = 0.01
const EXAMINE_RANGE: float = 5.0
const DEFAULT_INTERACTION_RANGE: float = 1.5

# Interaction behavior flags
enum InteractionFlags {
	NONE = 0,
	ADJACENT = 1,
	RANGED = 2,
	SELF = 4,
	WITH_ITEM = 8,
	HELP_INTENT = 16,
	COMBAT_MODE = 32
}

# Intent types for interactions
enum CurrentIntent {
	HELP = 0,
	DISARM = 1,
	GRAB = 2,
	HARM = 3
}

# Signals for interaction events
signal interaction_started(entity: Node)
signal interaction_completed(entity: Node, success: bool)
signal interaction_requested(target: Node)
signal examine_result(target: Node, text: String)
signal tile_interaction(tile_coords: Vector2i, interaction_type: String)

# Component references
var controller: Node = null
var sensory_system: Node = null
var audio_system: Node = null
var inventory_system: Node = null
var world: Node = null

# Interaction state
var current_interaction_flags: int = InteractionFlags.NONE
var current_intent: int = CurrentIntent.HELP
var last_interaction_time: float = 0.0
var interaction_range: float = DEFAULT_INTERACTION_RANGE

# Safety settings
var help_intent_safety: bool = false
var allow_self_harm: bool = false

func initialize(init_data: Dictionary):
	controller = init_data.get("controller")
	sensory_system = init_data.get("sensory_system")
	audio_system = init_data.get("audio_system")
	inventory_system = init_data.get("inventory_system")
	world = init_data.get("world")

# Processes interaction with target entity
func process_interaction(target: Node, button_index: int = MOUSE_BUTTON_LEFT, shift_pressed: bool = false, ctrl_pressed: bool = false, alt_pressed: bool = false) -> bool:
	if not target or not is_multiplayer_authority():
		return false
	
	if shift_pressed and not ctrl_pressed and not alt_pressed:
		return handle_examine_interaction(target)
	
	if not check_interaction_cooldown():
		return false
	
	if not can_interact_with(target):
		show_message("That's too far away.")
		return false
	
	face_entity(target)
	
	var result = await execute_interaction(target, button_index, shift_pressed, ctrl_pressed, alt_pressed)
	
	if result:
		sync_interaction_to_network(target, button_index, shift_pressed, ctrl_pressed, alt_pressed)
		last_interaction_time = Time.get_ticks_msec() / 1000.0
		emit_signal("interaction_completed", target, true)
	
	return result

# Executes the appropriate interaction based on input
func execute_interaction(target: Node, button_index: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool) -> bool:
	if ctrl_pressed and not shift_pressed and not alt_pressed:
		return handle_ctrl_interaction(target)
	elif alt_pressed and not shift_pressed and not ctrl_pressed:
		return handle_alt_interaction(target)
	elif button_index == MOUSE_BUTTON_MIDDLE:
		return handle_middle_interaction(target)
	else:
		return await handle_intent_interaction(target)

# Handles tile clicks for world interaction
func handle_tile_click(tile_coords: Vector2i, mouse_button: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	if not is_multiplayer_authority():
		return
	
	var world_pos = tile_to_world(tile_coords)
	face_entity(world_pos)
	
	match mouse_button:
		MOUSE_BUTTON_LEFT:
			handle_left_tile_click(tile_coords, shift_pressed, ctrl_pressed, alt_pressed)
		MOUSE_BUTTON_RIGHT:
			handle_tile_context_menu(tile_coords)
		MOUSE_BUTTON_MIDDLE:
			handle_middle_tile_click(tile_coords, shift_pressed)

# Handles left clicks on tiles
func handle_left_tile_click(tile_coords: Vector2i, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	if shift_pressed:
		examine_tile(tile_coords)
		sync_tile_action.rpc(tile_coords, "examine", get_entity_name(controller))
	elif alt_pressed:
		handle_alt_tile_action(tile_coords)
		sync_tile_action.rpc(tile_coords, "alt_action", get_entity_name(controller))
	else:
		handle_standard_tile_click(tile_coords)

# Handles standard tile interactions
func handle_standard_tile_click(tile_coords: Vector2i):
	if controller.has_node("ItemInteractionComponent"):
		var item_interaction = controller.get_node("ItemInteractionComponent")
		if item_interaction.is_throw_mode_active:
			item_interaction.throw_at_tile(tile_coords)
			return
	
	var entity = get_entity_on_tile(tile_coords)
	if entity and is_adjacent_to_tile(tile_coords):
		await process_interaction(entity)

# Handles middle clicks on tiles
func handle_middle_tile_click(tile_coords: Vector2i, shift_pressed: bool):
	if shift_pressed:
		var world_pos = tile_to_world(tile_coords)
		point_to(world_pos)
		sync_tile_action.rpc(tile_coords, "point", get_entity_name(controller))

# Synchronizes interaction data across network
@rpc("any_peer", "call_local", "reliable")
func sync_interaction(action_data: Dictionary):
	if multiplayer.get_remote_sender_id() == 0:
		return
	
	var target = find_target_by_id(action_data.get("target_id", ""))
	if not target:
		return
	
	var performer_name = action_data.get("performer", "Someone")
	show_interaction_visual(target, get_action_type(action_data), performer_name)

# Synchronizes tile actions across network
@rpc("any_peer", "call_local", "reliable")
func sync_tile_action(tile_coords: Vector2i, action_type: String, performer_name: String):
	if multiplayer.get_remote_sender_id() == 0:
		return
	
	match action_type:
		"examine":
			show_tile_visual_effect(tile_coords, "examine")
		"alt_action":
			show_tile_visual_effect(tile_coords, "alt_action")
		"point":
			var world_pos = tile_to_world(tile_coords)
			show_point_visual(world_pos, performer_name)

# Handles examine interactions with entities
func handle_examine_interaction(target: Node) -> bool:
	if not can_interact_with(target, EXAMINE_RANGE):
		show_message("That's too far to examine.")
		return false
	
	face_entity(target)
	
	var examine_text = get_examine_text(target)
	
	if sensory_system:
		sensory_system.display_message("[color=#AAAAAA]" + examine_text + "[/color]")
	
	emit_signal("examine_result", target, examine_text)
	
	if audio_system:
		audio_system.play_positioned_sound("examine", controller.position, 0.2)
	
	return true

# Handles ctrl+click interactions (pull/grab)
func handle_ctrl_interaction(target: Node) -> bool:
	if target == controller or target == controller.get_parent():
		show_message("You can't pull yourself!")
		return false
	
	if "can_be_pulled" in target and not target.can_be_pulled:
		show_message("You can't pull that!")
		return false
	
	if controller.has_node("GrabPullComponent"):
		var grab_component = controller.get_node("GrabPullComponent")
		return grab_component.pull_entity(target)
	
	return false

# Handles alt+click interactions (toggle/activate)
func handle_alt_interaction(target: Node) -> bool:
	face_entity(target)
	
	if target.has_method("alt_click"):
		return target.alt_click(controller)
	
	if target.has_method("toggle"):
		return target.toggle(controller)
	
	return false

# Handles middle click interactions (point)
func handle_middle_interaction(target: Node) -> bool:
	var target_pos = get_entity_position(target)
	if target_pos != Vector2.ZERO:
		point_to(target_pos)
		return true
	
	return false

# Handles intent-based interactions
func handle_intent_interaction(target: Node) -> bool:
	current_interaction_flags = InteractionFlags.ADJACENT
	
	if target == controller:
		current_interaction_flags |= InteractionFlags.SELF
	
	var active_item = get_active_item()
	if active_item:
		current_interaction_flags |= InteractionFlags.WITH_ITEM
	
	trigger_interaction_thrust(target, current_intent)
	
	match current_intent:
		CurrentIntent.HELP:
			return await handle_help_interaction(target, active_item)
		CurrentIntent.DISARM:
			return handle_disarm_interaction(target, active_item)
		CurrentIntent.GRAB:
			return handle_grab_interaction(target, active_item)
		CurrentIntent.HARM:
			return handle_harm_interaction(target, active_item)
		_:
			return await handle_help_interaction(target, active_item)

# Handles help intent interactions
func handle_help_interaction(target: Node, active_item: Node) -> bool:
	if current_interaction_flags & InteractionFlags.SELF:
		return handle_help_self_interaction(active_item)
	
	if active_item:
		if help_intent_safety and is_item_harmful(active_item):
			show_message("You don't want to hurt " + get_target_name(target) + " with that!")
			play_safety_sound()
			return false
		
		return await use_item_on_target(active_item, target)
	
	return handle_friendly_interaction(target)

# Handles disarm intent interactions
func handle_disarm_interaction(target: Node, active_item: Node) -> bool:
	if is_item_entity(target):
		return handle_item_pickup(target)
	
	if current_interaction_flags & InteractionFlags.SELF:
		show_message("You can't disarm yourself!")
		return false
	
	if active_item:
		show_message("You need empty hands to disarm!")
		return false
	
	if target.has_method("get_active_item"):
		var target_item = target.get_active_item()
		if target_item:
			return attempt_disarm(target, target_item)
		else:
			return attempt_push_shove(target)
	else:
		return attempt_push_shove(target)

# Handles grab intent interactions
func handle_grab_interaction(target: Node, active_item: Node) -> bool:
	if is_item_entity(target):
		return handle_item_pickup(target)
	
	if current_interaction_flags & InteractionFlags.SELF:
		show_message("You can't grab yourself!")
		return false
	
	if controller.has_node("GrabPullComponent"):
		var grab_component = controller.get_node("GrabPullComponent")
		if grab_component.grabbing_entity == target:
			return grab_component.upgrade_grab()
		elif grab_component.grabbing_entity != null:
			var grabbed_name = get_target_name(grab_component.grabbing_entity)
			show_message("You're already grabbing " + grabbed_name + "!")
			return false
	
	if active_item and not is_grab_compatible_item(active_item):
		show_message("You need a free hand to grab!")
		return false
	
	if controller.has_node("GrabPullComponent"):
		var grab_component = controller.get_node("GrabPullComponent")
		return grab_component.grab_entity(target, 0)
	
	return false

# Handles harm intent interactions
func handle_harm_interaction(target: Node, active_item: Node) -> bool:
	if is_item_entity(target):
		return handle_item_pickup(target)
	
	if current_interaction_flags & InteractionFlags.SELF:
		if not allow_self_harm:
			show_message("You have the discipline not to hurt yourself.")
			play_safety_sound()
			return false
		
		return handle_self_harm(active_item)
	
	var result = false
	var damage_dealt = 0.0
	var damage_type = "brute"
	var weapon_name = ""
	
	if active_item:
		result = attack_with_item(active_item, target)
		weapon_name = get_item_name(active_item)
		if "force" in active_item:
			damage_dealt = active_item.force
	else:
		result = attack_unarmed(target)
		damage_dealt = 3.0
	
	if result:
		sync_combat_result(target, damage_dealt, damage_type, weapon_name)
	
	return result

# Handles self-help interactions
func handle_help_self_interaction(active_item: Node) -> bool:
	if active_item:
		if active_item.has_method("use_on_self"):
			return active_item.use_on_self(controller)
		elif active_item.has_method("attack_self"):
			return active_item.attack_self(controller)
	
	show_message("You pat yourself down.")
	return true

# Handles friendly interactions with entities
func handle_friendly_interaction(target: Node) -> bool:
	if is_item_entity(target):
		return handle_item_pickup(target)
	
	if target.has_method("interact"):
		return target.interact(controller)
	
	if target.has_method("attack_hand"):
		target.attack_hand(controller)
		return true
	
	if target.has_method("use"):
		return target.use(controller)
	
	show_message("You poke " + get_target_name(target))
	return true

# Handles item pickup interactions
func handle_item_pickup(item: Node) -> bool:
	if "pickupable" in item and item.pickupable:
		if controller.has_node("ItemInteractionComponent"):
			var item_interaction = controller.get_node("ItemInteractionComponent")
			if item_interaction.has_method("try_pick_up_item"):
				return item_interaction.try_pick_up_item(item)
		
		var inventory_system = controller.get_node_or_null("InventorySystem")
		if inventory_system and inventory_system.has_method("pick_up_item"):
			return inventory_system.pick_up_item(item)
		
		if item.has_method("interact"):
			return item.interact(controller)
	
	return false

# Handles self-harm interactions
func handle_self_harm(active_item: Node) -> bool:
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

# Uses item on target entity
func use_item_on_target(item: Node, target: Node) -> bool:
	var result = false
	
	if target.has_method("attackby"):
		result = await target.attackby(item, controller)
	
	if not result and item.has_method("use_on"):
		result = await item.use_on(target, controller)
	
	if not result and item.has_method("attack"):
		result = item.attack(target, controller)
	
	if not result and item.has_method("afterattack"):
		result = item.afterattack(target, controller, true)
	
	if not result and target.has_method("attack_hand"):
		target.attack_hand(controller)
		result = true
	
	if not result:
		var item_name = get_item_name(item)
		show_message("You use " + item_name + " on " + get_target_name(target) + ".")
		result = true
	
	return result

# Attempts to disarm target entity
func attempt_disarm(target: Node, target_item: Node) -> bool:
	var base_chance = 25.0
	var user_skill = 10.0
	var target_resistance = get_target_resistance(target)
	var item_grip = get_item_grip_strength(target_item)
	
	var disarm_chance = base_chance + user_skill - target_resistance - item_grip
	disarm_chance = clamp(disarm_chance, 5.0, 95.0)
	
	if randf() * 100.0 < disarm_chance:
		execute_successful_disarm(target, target_item)
		return true
	else:
		show_message("You fail to disarm " + get_target_name(target) + ".")
		return false

# Executes successful disarm effects
func execute_successful_disarm(target: Node, target_item: Node):
	if target.has_method("drop_item"):
		target.drop_item(target_item)
	elif target.has_method("drop_active_item"):
		target.drop_active_item()
	
	if target.has_method("toggle_lying"):
		target.toggle_lying()
	
	if target.has_method("stun"):
		target.stun(2.0)
	
	show_message("You disarm " + get_target_name(target) + ", knocking them down!")
	
	if audio_system:
		audio_system.play_positioned_sound("disarm", controller.position, 0.5)

# Attempts to push or shove target
func attempt_push_shove(target: Node) -> bool:
	var base_chance = 30.0
	var user_strength = 20.0
	var target_resistance = get_target_resistance(target)
	
	if "is_lying" in target and target.is_lying:
		base_chance += 20.0
	
	if "is_stunned" in target and target.is_stunned:
		base_chance += 30.0
	
	var push_chance = base_chance + user_strength - target_resistance
	push_chance = clamp(push_chance, 10.0, 80.0)
	
	if randf() * 100.0 < push_chance:
		execute_successful_push(target)
		return true
	else:
		show_message("You try to shove " + get_target_name(target) + " but they resist!")
		return false

# Executes successful push effects
func execute_successful_push(target: Node):
	show_message("You shove " + get_target_name(target) + "!")
	
	if target.has_method("apply_knockback"):
		var push_dir = (get_entity_position(target) - controller.position).normalized()
		target.apply_knockback(push_dir, 15.0)
	
	if target.has_method("stun"):
		target.stun(0.5)
	
	if target.has_method("toggle_lying"):
		target.toggle_lying()

# Attacks target with equipped item
func attack_with_item(item: Node, target: Node) -> bool:
	var weapon_damage = get_weapon_damage(item)
	var attack_chance = calculate_attack_chance(target, true)
	
	if randf() * 100.0 < attack_chance:
		execute_successful_attack(target, weapon_damage, "brute", get_item_name(item))
		
		if audio_system:
			var hit_sound = get_weapon_hit_sound(item)
			audio_system.play_positioned_sound(hit_sound, controller.position, 0.6)
		
		if item.has_method("on_hit"):
			item.on_hit(target, controller)
		
		return true
	else:
		show_message("You swing " + get_item_name(item) + " at " + get_target_name(target) + " but miss!")
		
		if audio_system:
			audio_system.play_positioned_sound("swing", controller.position, 0.4)
		
		return false

# Attacks target with bare hands
func attack_unarmed(target: Node) -> bool:
	var punch_damage = calculate_unarmed_damage(target)
	var attack_chance = calculate_attack_chance(target, false)
	
	if randf() * 100.0 < attack_chance:
		var target_zone = get_selected_target_zone()
		execute_successful_attack(target, punch_damage, "brute", "")
		
		var attack_verb = get_unarmed_attack_verb(target_zone)
		show_message("You " + attack_verb + " " + get_target_name(target) + "!")
		
		if audio_system:
			audio_system.play_positioned_sound("punch", controller.position, 0.5)
		
		handle_unarmed_special_effects(target, target_zone)
		return true
	else:
		show_message("You throw a punch at " + get_target_name(target) + " but miss!")
		
		if audio_system:
			audio_system.play_positioned_sound("swing", controller.position, 0.3)
		
		return false

# Executes successful attack effects
func execute_successful_attack(target: Node, damage: float, damage_type: String, weapon_name: String):
	apply_damage_to_target(target, damage, damage_type)
	
	var target_zone = get_selected_target_zone()
	if target.has_method("take_damage_to_zone"):
		target.take_damage_to_zone(damage, damage_type, target_zone)
	
	var attack_message = "You hit " + get_target_name(target)
	if weapon_name != "":
		attack_message += " with " + weapon_name
	attack_message += "!"
	show_message(attack_message)

# Handles special effects for unarmed attacks
func handle_unarmed_special_effects(target: Node, target_zone: String):
	if target_zone == "head" and randf() < 0.1:
		if target.has_method("stun"):
			target.stun(1.0)
			show_message(get_target_name(target) + " staggers from the blow!")

# Synchronizes combat results across network
func sync_combat_result(target: Node, damage: float, damage_type: String, weapon_name: String):
	var result_data = {
		"damage": damage,
		"damage_type": damage_type,
		"weapon": weapon_name,
		"attacker": get_entity_name(controller),
		"hit": true
	}
	sync_combat_result_rpc.rpc(get_target_network_id(target), result_data)

# RPC for combat result synchronization
@rpc("any_peer", "call_local", "reliable")
func sync_combat_result_rpc(target_id: String, result_data: Dictionary):
	if multiplayer.get_remote_sender_id() == 0:
		return
	
	var target = find_target_by_id(target_id)
	if not target:
		return
	
	show_combat_effect(target, result_data)

# Synchronizes interaction data to network
func sync_interaction_to_network(target: Node, button_index: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	var action_data = {
		"target_id": get_target_network_id(target),
		"ctrl": ctrl_pressed,
		"alt": alt_pressed,
		"middle": (button_index == MOUSE_BUTTON_MIDDLE),
		"intent": current_intent,
		"performer": get_entity_name(controller)
	}
	sync_interaction.rpc(action_data)

# Checks if interaction cooldown allows new interaction
func check_interaction_cooldown() -> bool:
	var current_time = Time.get_ticks_msec() / 1000.0
	return current_time >= last_interaction_time + INTERACTION_COOLDOWN

# Checks if entity can interact with target
func can_interact_with(target: Node, max_range: float = DEFAULT_INTERACTION_RANGE) -> bool:
	if not target:
		return false
	
	if target == controller or target == controller.get_parent():
		return true
	
	if not is_adjacent_to(target):
		var distance = get_distance_to(target)
		
		var active_item = get_active_item()
		if active_item and "max_range" in active_item:
			return distance <= active_item.max_range
		
		if controller.has_node("ItemInteractionComponent"):
			var item_interaction = controller.get_node("ItemInteractionComponent")
			if item_interaction.is_throw_mode_active:
				return distance <= 10.0
		
		if current_intent == CurrentIntent.HELP:
			return distance <= EXAMINE_RANGE
		
		return false
	
	return true

# Checks if entity is adjacent to target
func is_adjacent_to(target: Node) -> bool:
	if not controller.has_method("is_adjacent_to"):
		return false
	
	return controller.is_adjacent_to(target)

# Checks if entity is adjacent to tile
func is_adjacent_to_tile(tile_coords: Vector2i) -> bool:
	if not controller.has_method("get_current_tile_position"):
		return false
	
	var my_pos = controller.get_current_tile_position()
	var diff_x = abs(my_pos.x - tile_coords.x)
	var diff_y = abs(my_pos.y - tile_coords.y)
	
	return (diff_x <= 1 and diff_y <= 1) and not (diff_x == 0 and diff_y == 0)

# Calculates distance to target entity
func get_distance_to(target: Node) -> float:
	if not controller.has_method("get_current_tile_position"):
		return 999.0
	
	var my_pos = Vector2(controller.get_current_tile_position())
	var target_pos_int = get_entity_tile_position(target)
	var target_pos = Vector2(target_pos_int.x, target_pos_int.y)
	
	return my_pos.distance_to(target_pos)

# Helper functions for entity and item checking
func is_item_entity(entity: Node) -> bool:
	return entity.has_method("get_script") and entity.get_script() and "Item" in str(entity.get_script().get_path())

func is_item_harmful(item: Node) -> bool:
	if "force" in item and item.force > 0:
		return true
	if "tool_behaviour" in item and item.tool_behaviour == "weapon":
		return true
	if "harmful" in item and item.harmful:
		return true
	return false

func is_grab_compatible_item(item: Node) -> bool:
	if "w_class" in item:
		return item.w_class <= 2
	if "allows_grabbing" in item:
		return item.allows_grabbing
	return false

# Combat calculation helper functions
func get_target_resistance(target: Node) -> float:
	if "dexterity" in target:
		return target.dexterity * 1.0
	return 0.0

func get_item_grip_strength(item: Node) -> float:
	if "grip_strength" in item:
		return item.grip_strength
	elif "w_class" in item:
		return item.w_class * 5.0
	return 0.0

func get_weapon_damage(item: Node) -> float:
	if "force" in item and item.force > 0:
		return item.force
	return 5.0

func get_weapon_hit_sound(item: Node) -> String:
	if "hitsound" in item:
		return item.hitsound
	return "weapon_hit"

func calculate_attack_chance(target: Node, with_weapon: bool) -> float:
	var base_chance = 75.0 if with_weapon else 70.0
	var skill_bonus = 10.0 if with_weapon else 12.0
	
	var attack_chance = base_chance + skill_bonus
	
	if "dexterity" in target:
		attack_chance -= target.dexterity * (0.5 if with_weapon else 0.7)
	
	if "is_lying" in target and target.is_lying:
		attack_chance += 20.0 if with_weapon else 25.0
	
	if "is_stunned" in target and target.is_stunned:
		attack_chance += 40.0 if with_weapon else 35.0
	
	return clamp(attack_chance, 10.0, 95.0)

func calculate_unarmed_damage(target: Node) -> float:
	var punch_damage = 3.0 + 3.0
	
	if "is_lying" in target and target.is_lying:
		punch_damage += 1.0
	
	if "is_stunned" in target and target.is_stunned:
		punch_damage += 2.0
	
	return punch_damage

func get_selected_target_zone() -> String:
	if controller.has_node("BodyTargetingComponent"):
		var body_targeting = controller.get_node("BodyTargetingComponent")
		return body_targeting.get_selected_zone()
	return "chest"

func get_unarmed_attack_verb(zone: String) -> String:
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

# Utility and helper functions
func get_active_item() -> Node:
	if inventory_system and inventory_system.has_method("get_active_item"):
		return inventory_system.get_active_item()
	return null

func get_examine_text(target: Node) -> String:
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

func get_entity_position(entity: Node) -> Vector2:
	if "global_position" in entity:
		return entity.global_position
	elif "position" in entity:
		return entity.position
	return Vector2.ZERO

func get_entity_tile_position(entity: Node) -> Vector2i:
	if not entity:
		return Vector2i.ZERO
	
	if "current_tile_position" in entity:
		return entity.current_tile_position
	elif entity.has_method("get_current_tile_position"):
		return entity.get_current_tile_position()
	elif controller.has_method("get_entity_tile_position"):
		return controller.get_entity_tile_position(entity)
	
	return Vector2i.ZERO

func get_entity_on_tile(tile_coords: Vector2i) -> Node:
	if world and "tile_occupancy_system" in world and world.tile_occupancy_system:
		var z_level = controller.current_z_level if controller else 0
		var entities = world.tile_occupancy_system.get_entities_at(tile_coords, z_level)
		if entities and entities.size() > 0:
			return entities[0]
	return null

func tile_to_world(tile_pos: Vector2i) -> Vector2:
	return Vector2((tile_pos.x * 32) + 16, (tile_pos.y * 32) + 16)

func get_target_name(target: Node) -> String:
	if "entity_name" in target and target.entity_name != "":
		return target.entity_name
	elif "name" in target:
		return target.name
	else:
		return "that"

func get_entity_name(entity: Node) -> String:
	if "entity_name" in entity and entity.entity_name != "":
		return entity.entity_name
	elif "name" in entity:
		return entity.name
	else:
		return "someone"

func get_item_name(item: Node) -> String:
	if "item_name" in item:
		return item.item_name
	elif "name" in item:
		return item.name
	else:
		return "something"

func apply_damage_to_target(target: Node, damage: float, damage_type: String):
	if target.has_method("take_damage"):
		target.take_damage(damage, damage_type)
	elif target.has_method("apply_damage"):
		target.apply_damage(damage, damage_type)

func show_message(text: String):
	if sensory_system:
		sensory_system.display_message(text)

func play_safety_sound():
	if audio_system:
		audio_system.play_positioned_sound("buzz", controller.position, 0.3)

func face_entity(target):
	if not controller.has_method("face_entity"):
		return
	controller.face_entity(target)

func point_to(position: Vector2):
	var direction = (position - controller.position).normalized()
	var dir_text = get_direction_text(direction)
	
	show_message(controller.entity_name + " points to the " + dir_text + ".")
	
	if world and world.has_method("spawn_visual_effect"):
		world.spawn_visual_effect("point", position, 1.0)

func get_direction_text(direction: Vector2) -> String:
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

# Visual effect and feedback functions
func trigger_interaction_thrust(target: Node, intent: int):
	if controller.has_node("SpriteSystem"):
		var sprite_system = controller.get_node("SpriteSystem")
		if sprite_system.has_method("show_interaction_thrust"):
			var direction_to_target = get_direction_to_target(target)
			sprite_system.show_interaction_thrust(direction_to_target, intent)

func get_direction_to_target(target: Node) -> Vector2:
	var target_pos = get_entity_position(target)
	if target_pos == Vector2.ZERO:
		return Vector2.ZERO
	
	var my_pos = controller.position
	return (target_pos - my_pos).normalized()

func show_interaction_visual(target: Node, action_type: String, performer_name: String):
	match action_type:
		"pull":
			trigger_interaction_thrust(target, -1)
		"alt":
			trigger_interaction_thrust(target, -2)
		"point":
			show_point_visual(get_entity_position(target), performer_name)
		"help":
			trigger_interaction_thrust(target, 0)
		"disarm":
			trigger_interaction_thrust(target, 1)
		"grab":
			trigger_interaction_thrust(target, 2)
		"harm":
			trigger_interaction_thrust(target, 3)

func show_tile_visual_effect(tile_coords: Vector2i, effect_type: String):
	if world and world.has_method("spawn_visual_effect"):
		var world_pos = tile_to_world(tile_coords)
		world.spawn_visual_effect(effect_type, world_pos, 0.5)

func show_point_visual(position: Vector2, performer_name: String):
	var direction = (position - controller.position).normalized()
	var dir_text = get_direction_text(direction)
	
	show_message(performer_name + " points to the " + dir_text + ".")
	
	if world and world.has_method("spawn_visual_effect"):
		world.spawn_visual_effect("point", position, 1.0)

func show_combat_effect(target: Node, result_data: Dictionary):
	if world and world.has_method("spawn_damage_number"):
		world.spawn_damage_number(get_entity_position(target), result_data.get("damage", 0), result_data.get("damage_type", "brute"))
	
	if audio_system:
		var hit_sound = "weapon_hit" if result_data.get("weapon", "") != "" else "punch"
		audio_system.play_positioned_sound(hit_sound, get_entity_position(target), 0.6)

# Network utility functions
func get_target_network_id(target: Node) -> String:
	if not target:
		return ""
	
	if target.has_method("get_network_id"):
		return target.get_network_id()
	elif "peer_id" in target:
		return "player_" + str(target.peer_id)
	elif target.has_meta("network_id"):
		return str(target.get_meta("network_id"))
	else:
		return target.get_path()

func find_target_by_id(target_id: String) -> Node:
	if target_id == "":
		return null
	
	if target_id.begins_with("player_"):
		var peer_id = target_id.split("_")[1].to_int()
		return find_player_by_peer_id(peer_id)
	
	if target_id.begins_with("/"):
		return get_node_or_null(target_id)
	
	var entities = get_tree().get_nodes_in_group("networkable")
	for entity in entities:
		if entity.has_meta("network_id") and str(entity.get_meta("network_id")) == target_id:
			return entity
		if entity.has_method("get_network_id") and entity.get_network_id() == target_id:
			return entity
	
	return null

func find_player_by_peer_id(peer_id: int) -> Node:
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player.has_meta("peer_id") and player.get_meta("peer_id") == peer_id:
			return player
		if "peer_id" in player and player.peer_id == peer_id:
			return player
	
	return null

func get_action_type(action_data: Dictionary) -> String:
	if action_data.get("ctrl", false):
		return "pull"
	elif action_data.get("alt", false):
		return "alt"
	elif action_data.get("middle", false):
		return "point"
	else:
		var intent = action_data.get("intent", 0)
		match intent:
			0: return "help"
			1: return "disarm"
			2: return "grab"
			3: return "harm"
			_: return "help"

# Tile-specific interaction functions
func examine_tile(tile_position: Vector2i):
	if not world:
		return
	
	var z_level = controller.current_z_level if controller else 0
	var tile_data = world.get_tile_data(tile_position, z_level) if world.has_method("get_tile_data") else null
	if not tile_data:
		return
	
	var description = generate_tile_description(tile_data)
	
	emit_signal("examine_result", {"tile_position": tile_position}, description)
	
	if sensory_system:
		sensory_system.display_message("[color=#AAAAAA]" + description + "[/color]")

func generate_tile_description(tile_data: Dictionary) -> String:
	if "door" in tile_data:
		return generate_door_description(tile_data.door)
	elif "window" in tile_data:
		return generate_window_description(tile_data.window)
	elif "floor" in tile_data:
		return "A " + tile_data.floor.type + " floor."
	elif "wall" in tile_data:
		return "A solid wall made of " + tile_data.wall.material + "."
	else:
		return "You see nothing special."

func generate_door_description(door_data: Dictionary) -> String:
	var description = "A door. It appears to be " + ("closed" if door_data.closed else "open") + "."
	
	if "locked" in door_data and door_data.locked:
		description += " It seems to be locked."
	
	if "broken" in door_data and door_data.broken:
		description += " It looks broken."
	
	return description

func generate_window_description(window_data: Dictionary) -> String:
	var description = "A window made of glass."
	
	if "reinforced" in window_data and window_data.reinforced:
		description += " It appears to be reinforced."
	
	if "health" in window_data and window_data.health < window_data.max_health:
		description += " It has some cracks."
	
	return description

func handle_alt_tile_action(tile_coords: Vector2i):
	var z_level = controller.current_z_level if controller else 0
	var tile_data = world.get_tile_data(tile_coords, z_level) if world and world.has_method("get_tile_data") else null
	if not tile_data:
		return
	
	if "door" in tile_data:
		if world and world.has_method("toggle_door"):
			world.toggle_door(tile_coords, z_level)
			emit_signal("tile_interaction", tile_coords, "door_toggle")
		return
	
	if "window" in tile_data:
		if world and world.has_method("knock_window"):
			world.knock_window(tile_coords, z_level)
			emit_signal("tile_interaction", tile_coords, "window_knock")
		return

func handle_tile_context_menu(tile_coords: Vector2i):
	var options = []
	
	options.append({
		"name": "Examine Tile",
		"icon": "examine",
		"action": "examine_tile",
		"params": {"position": tile_coords}
	})
	
	var z_level = controller.current_z_level if controller else 0
	var tile_data = world.get_tile_data(tile_coords, z_level) if world and world.has_method("get_tile_data") else null
	
	if tile_data and "door" in tile_data:
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
	
	if world and "context_interaction_system" in world:
		world.context_interaction_system.show_context_menu(options, controller.get_viewport().get_mouse_position())

# Signal handler for intent changes
func _on_intent_changed(new_intent: int):
	current_intent = new_intent
