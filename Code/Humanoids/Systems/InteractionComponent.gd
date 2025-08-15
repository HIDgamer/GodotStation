extends Node
class_name InteractionComponent

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

enum CurrentIntent {
	HELP = 0,
	DISARM = 1,
	GRAB = 2,
	HARM = 3
}
#endregion

#region SIGNALS
signal interaction_started(entity: Node)
signal interaction_completed(entity: Node, success: bool)
signal interaction_requested(target: Node)
signal examine_result(target: Node, text: String)
signal tile_interaction(tile_coords: Vector2i, interaction_type: String)
#endregion

#region EXPORTS
@export_group("Interaction Settings")
@export var interaction_cooldown: float = INTERACTION_COOLDOWN
@export var examine_range: float = EXAMINE_RANGE
@export var interaction_range: float = DEFAULT_INTERACTION_RANGE

@export_group("Combat Configuration")
@export var base_unarmed_damage: float = 3.0
@export var base_attack_chance: float = 75.0
@export var lying_attack_bonus: float = 20.0
@export var stunned_attack_bonus: float = 40.0

@export_group("Safety Features")
@export var help_intent_safety: bool = false
@export var allow_self_harm: bool = false
@export var show_safety_warnings: bool = true

@export_group("Skill Modifiers")
@export var cqc_accuracy_bonus_per_level: float = 8.0
@export var melee_accuracy_bonus_per_level: float = 5.0
@export var dexterity_defense_multiplier: float = 0.7

@export_group("Audio Settings")
@export var examine_sound: String = "examine"
@export var punch_sound: String = "punch"
@export var disarm_sound: String = "disarm"
@export var interaction_volume: float = 0.3
#endregion

#region PROPERTIES
var controller: Node = null
var sensory_system: Node = null
var audio_system: Node = null
var inventory_system: Node = null
var skill_component: Node = null
var world: Node = null
var tile_occupancy_system: Node = null

# Interaction state
var current_interaction_flags: int = InteractionFlags.NONE
var current_intent: int = CurrentIntent.HELP
var last_interaction_time: float = 0.0

# Cached values for performance
var _cached_target_resistances: Dictionary = {}
var _resistance_cache_time: float = 0.0
var _resistance_cache_lifetime: float = 1.0
#endregion

#region INITIALIZATION
func initialize(init_data: Dictionary):
	controller = init_data.get("controller")
	sensory_system = init_data.get("sensory_system")
	audio_system = init_data.get("audio_system")
	inventory_system = init_data.get("inventory_system")
	skill_component = init_data.get("skill_component")
	world = init_data.get("world")
	tile_occupancy_system = init_data.get("tile_occupancy_system")
	
	if not tile_occupancy_system and world:
		tile_occupancy_system = world.get_node_or_null("TileOccupancySystem")
#endregion

#region MAIN INTERACTION PROCESSING
func process_interaction(target: Node, button_index: int = MOUSE_BUTTON_LEFT, shift_pressed: bool = false, ctrl_pressed: bool = false, alt_pressed: bool = false) -> bool:
	if not target or not is_multiplayer_authority():
		return false
	
	if shift_pressed and not ctrl_pressed and not alt_pressed:
		return handle_examine_interaction(target)
	
	if not _check_interaction_cooldown() or not _can_interact_with(target):
		return false
	
	_face_entity(target)
	
	var result = await _execute_interaction(target, button_index, shift_pressed, ctrl_pressed, alt_pressed)
	
	if result:
		_sync_interaction_to_network(target, button_index, shift_pressed, ctrl_pressed, alt_pressed)
		last_interaction_time = Time.get_ticks_msec() / 1000.0
		emit_signal("interaction_completed", target, true)
	
	return result

func _execute_interaction(target: Node, button_index: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool) -> bool:
	if target is Door:
		return _handle_door_interaction(target, button_index, shift_pressed, ctrl_pressed, alt_pressed)
	
	if ctrl_pressed and not shift_pressed and not alt_pressed:
		return _handle_ctrl_interaction(target)
	elif alt_pressed and not shift_pressed and not ctrl_pressed:
		return _handle_alt_interaction(target)
	elif button_index == MOUSE_BUTTON_MIDDLE:
		return _handle_middle_interaction(target)
	else:
		return await _handle_intent_interaction(target)
#endregion

#region TILE INTERACTIONS
func handle_tile_click(tile_coords: Vector2i, mouse_button: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	if not is_multiplayer_authority():
		return
	
	var world_pos = _tile_to_world(tile_coords)
	_face_entity(world_pos)
	
	var door = _find_door_at_position(tile_coords)
	if door:
		_handle_door_interaction(door, mouse_button, shift_pressed, ctrl_pressed, alt_pressed)
		return
	
	match mouse_button:
		MOUSE_BUTTON_LEFT:
			_handle_left_tile_click(tile_coords, shift_pressed, ctrl_pressed, alt_pressed)
		MOUSE_BUTTON_RIGHT:
			pass
		MOUSE_BUTTON_MIDDLE:
			_handle_middle_tile_click(tile_coords, shift_pressed)

func _handle_left_tile_click(tile_coords: Vector2i, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	if shift_pressed:
		_examine_tile(tile_coords)
		sync_tile_action.rpc(tile_coords, "examine", _get_entity_name(controller))
	elif alt_pressed:
		_handle_alt_tile_action(tile_coords)
		sync_tile_action.rpc(tile_coords, "alt_action", _get_entity_name(controller))
	else:
		_handle_standard_tile_click(tile_coords)

func _handle_standard_tile_click(tile_coords: Vector2i):
	if controller.has_node("ItemInteractionComponent"):
		var item_interaction = controller.get_node("ItemInteractionComponent")
		if item_interaction.is_throw_mode_active:
			item_interaction.throw_at_tile(tile_coords)
			return
	
	var entity = _get_entity_on_tile(tile_coords)
	if entity and _is_adjacent_to_tile(tile_coords):
		await process_interaction(entity)

func _handle_middle_tile_click(tile_coords: Vector2i, shift_pressed: bool):
	if shift_pressed:
		var world_pos = _tile_to_world(tile_coords)
		_point_to(world_pos)
		sync_tile_action.rpc(tile_coords, "point", _get_entity_name(controller))
#endregion

#region DOOR INTERACTIONS
func _handle_door_interaction(door: Door, button_index: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool) -> bool:
	if not door or not is_instance_valid(door):
		return false
	
	if shift_pressed and not ctrl_pressed and not alt_pressed:
		return handle_examine_interaction(door)
	
	if alt_pressed and not shift_pressed and not ctrl_pressed:
		return _handle_door_alt_click(door)
	
	if ctrl_pressed and not shift_pressed and not alt_pressed:
		return _handle_door_ctrl_click(door)
	
	return door.interact(controller)

func _handle_door_alt_click(door: Door) -> bool:
	return door.interact(controller)

func _handle_door_ctrl_click(door: Door) -> bool:
	if _has_emergency_access():
		if door.locked:
			door.set_locked(false)
			show_message("You force the door lock!")
			return true
		else:
			door.emergency_open()
			return true
	
	return door.interact(controller)

func _find_door_at_position(tile_pos: Vector2i) -> Door:
	if not tile_occupancy_system:
		return null
	
	var z_level = controller.current_z_level if controller else 0
	var entities = tile_occupancy_system.get_entities_at(tile_pos, z_level)
	for entity in entities:
		if entity is Door:
			return entity
	
	return null
#endregion

#region EXAMINATION
func handle_examine_interaction(target: Node) -> bool:
	if not _can_interact_with(target, examine_range):
		show_message("That's too far to examine.")
		return false
	
	_face_entity(target)
	
	var examine_text = _get_examine_text(target)
	
	if sensory_system:
		sensory_system.display_message("[color=#AAAAAA]" + examine_text + "[/color]")
	
	emit_signal("examine_result", target, examine_text)
	
	if audio_system:
		audio_system.play_positioned_sound(examine_sound, controller.position, interaction_volume)
	
	return true

func _get_examine_text(target: Node) -> String:
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
#endregion

#region INTENT-BASED INTERACTIONS
func _handle_intent_interaction(target: Node) -> bool:
	current_interaction_flags = InteractionFlags.ADJACENT
	
	if target == controller:
		current_interaction_flags |= InteractionFlags.SELF
	
	var active_item = _get_active_item()
	if active_item:
		current_interaction_flags |= InteractionFlags.WITH_ITEM
	
	_trigger_interaction_thrust(target, current_intent)
	
	match current_intent:
		CurrentIntent.HELP:
			return await _handle_help_interaction(target, active_item)
		CurrentIntent.DISARM:
			return _handle_disarm_interaction(target, active_item)
		CurrentIntent.GRAB:
			return _handle_grab_interaction(target, active_item)
		CurrentIntent.HARM:
			return _handle_harm_interaction(target, active_item)
		_:
			return await _handle_help_interaction(target, active_item)

func _handle_help_interaction(target: Node, active_item: Node) -> bool:
	if current_interaction_flags & InteractionFlags.SELF:
		return await _handle_help_self_interaction(active_item)
	
	if active_item:
		if _is_medical_item(active_item) and skill_component and not skill_component.can_use_medical_items():
			show_message("You don't know how to use medical equipment properly!")
			return false
		
		if help_intent_safety and _is_item_harmful(active_item) and not _is_medical_item(active_item):
			show_message("You don't want to hurt " + _get_target_name(target) + " with that!")
			return false
		
		return await _use_item_on_target(active_item, target)
	
	if _can_fireman_carry_target(target):
		if controller.grab_pull_component and controller.grab_pull_component.grab_state == controller.grab_pull_component.GrabState.AGGRESSIVE:
			return await controller.grab_pull_component.initiate_fireman_carry_sequence(target)
		else:
			return _attempt_fireman_carry(target)
	
	return _handle_friendly_interaction(target)

func _handle_disarm_interaction(target: Node, active_item: Node) -> bool:
	if _is_item_entity(target):
		return _handle_item_pickup(target)
	
	if current_interaction_flags & InteractionFlags.SELF:
		show_message("You can't disarm yourself!")
		return false
	
	if active_item:
		show_message("You need empty hands to disarm!")
		return false
	
	var skill_bonus = _get_cqc_skill_bonus()
	
	if target.has_method("get_active_item"):
		var target_item = target.get_active_item()
		if target_item:
			return _attempt_disarm(target, target_item, skill_bonus)
		else:
			return _attempt_push_shove(target, skill_bonus)
	else:
		return _attempt_push_shove(target, skill_bonus)

func _handle_grab_interaction(target: Node, active_item: Node) -> bool:
	if _is_item_entity(target):
		return _handle_item_pickup(target)
	
	if current_interaction_flags & InteractionFlags.SELF:
		show_message("You can't grab yourself!")
		return false
	
	if controller.has_node("GrabPullComponent"):
		var grab_component = controller.get_node("GrabPullComponent")
		if grab_component.grabbing_entity == target:
			return grab_component.upgrade_grab()
		elif grab_component.grabbing_entity != null:
			var grabbed_name = _get_target_name(grab_component.grabbing_entity)
			show_message("You're already grabbing " + grabbed_name + "!")
			return false
	
	if active_item and not _is_grab_compatible_item(active_item):
		show_message("You need a free hand to grab!")
		return false
	
	if controller.has_node("GrabPullComponent"):
		var grab_component = controller.get_node("GrabPullComponent")
		return grab_component.grab_entity(target, 0)
	
	return false

func _handle_harm_interaction(target: Node, active_item: Node) -> bool:
	if _is_item_entity(target):
		return _handle_item_pickup(target)
	
	if current_interaction_flags & InteractionFlags.SELF:
		if not allow_self_harm:
			show_message("You have the discipline not to hurt yourself.")
			return false
		
		return _handle_self_harm(active_item)
	
	var result = false
	var damage_dealt = 0.0
	var damage_type = "brute"
	var weapon_name = ""
	
	if active_item:
		result = _attack_with_item(active_item, target)
		weapon_name = _get_item_name(active_item)
		if "force" in active_item:
			damage_dealt = active_item.force
	else:
		result = _attack_unarmed(target)
		damage_dealt = base_unarmed_damage
	
	if result:
		_sync_combat_result(target, damage_dealt, damage_type, weapon_name)
	
	return result
#endregion

#region COMBAT MECHANICS
func _attack_with_item(item: Node, target: Node) -> bool:
	var weapon_damage = _get_weapon_damage(item)
	var attack_chance = _calculate_attack_chance(target, true)
	
	if randf() * 100.0 < attack_chance:
		_execute_successful_attack(target, weapon_damage, 1, _get_item_name(item))
		
		if audio_system:
			var hit_sound = _get_weapon_hit_sound(item)
			audio_system.play_positioned_sound(hit_sound, controller.position, 0.6)
		
		if item.has_method("on_hit"):
			item.on_hit(target, controller)
		
		return true
	else:
		show_message("You swing " + _get_item_name(item) + " at " + _get_target_name(target) + " but miss!")
		
		if audio_system:
			audio_system.play_positioned_sound("swing", controller.position, 0.4)
		
		return false

func _attack_unarmed(target: Node) -> bool:
	var punch_damage = _calculate_unarmed_damage(target)
	var attack_chance = _calculate_attack_chance(target, false)
	
	if randf() * 100.0 < attack_chance:
		var target_zone = _get_selected_target_zone()
		_execute_successful_attack(target, punch_damage, 1, "")
		
		var attack_verb = _get_unarmed_attack_verb(target_zone)
		show_message("You " + attack_verb + " " + _get_target_name(target) + "!")
		
		if audio_system:
			audio_system.play_positioned_sound(punch_sound, controller.position, 0.5)
		
		_handle_unarmed_special_effects(target, target_zone)
		return true
	else:
		show_message("You throw a punch at " + _get_target_name(target) + " but miss!")
		
		if audio_system:
			audio_system.play_positioned_sound("swing", controller.position, 0.3)
		
		return false

func _calculate_attack_chance(target: Node, with_weapon: bool) -> float:
	var base_chance = base_attack_chance if with_weapon else base_attack_chance - 5.0
	var skill_bonus = 0.0
	
	if skill_component:
		if with_weapon:
			var melee_skill = skill_component.get_skill_level(skill_component.SKILL_MELEE_WEAPONS)
			skill_bonus = melee_skill * melee_accuracy_bonus_per_level
		else:
			var cqc_skill = skill_component.get_skill_level(skill_component.SKILL_CQC)
			skill_bonus = cqc_skill * cqc_accuracy_bonus_per_level
	
	var attack_chance = base_chance + skill_bonus
	
	var target_resistance = _get_cached_target_resistance(target)
	attack_chance -= target_resistance * dexterity_defense_multiplier
	
	if "is_lying" in target and target.is_lying:
		attack_chance += lying_attack_bonus
	
	if "is_stunned" in target and target.is_stunned:
		attack_chance += stunned_attack_bonus
	
	return clamp(attack_chance, 10.0, 95.0)

func _calculate_unarmed_damage(target: Node) -> float:
	var punch_damage = base_unarmed_damage
	
	if skill_component:
		var cqc_skill = skill_component.get_skill_level(skill_component.SKILL_CQC)
		punch_damage += cqc_skill * 1.0
	
	if "is_lying" in target and target.is_lying:
		punch_damage += 1.0
	
	if "is_stunned" in target and target.is_stunned:
		punch_damage += 2.0
	
	return punch_damage

func _execute_successful_attack(target: Node, damage: float, damage_type: int, weapon_name: String):
	_apply_damage_to_target(target, damage, damage_type)
	
	var target_zone = _get_selected_target_zone()
	if target.has_method("take_damage_to_zone"):
		target.take_damage_to_zone(damage, damage_type, target_zone)
	
	var attack_message = "You hit " + _get_target_name(target)
	if weapon_name != "":
		attack_message += " with " + weapon_name
	attack_message += "!"
	show_message(attack_message)

func _handle_unarmed_special_effects(target: Node, target_zone: String):
	if target_zone == "head" and randf() < 0.1:
		if target.has_method("stun"):
			target.stun(1.0)
			show_message(_get_target_name(target) + " staggers from the blow!")

func _get_weapon_damage(item: Node) -> float:
	var base_damage = 5.0
	if "force" in item and item.force > 0:
		base_damage = item.force
	
	if skill_component:
		var modifier = skill_component.get_melee_skill_modifier()
		base_damage *= modifier
	
	return base_damage

func _get_weapon_hit_sound(item: Node) -> String:
	if "hitsound" in item:
		return item.hitsound
	return "weapon_hit"

func _get_selected_target_zone() -> String:
	if controller.has_node("BodyTargetingComponent"):
		var body_targeting = controller.get_node("BodyTargetingComponent")
		return body_targeting.get_selected_zone()
	return "chest"

func _get_unarmed_attack_verb(zone: String) -> String:
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
#endregion

#region DISARM AND PUSH MECHANICS
func _attempt_disarm(target: Node, target_item: Node, skill_bonus: float = 0.0) -> bool:
	var base_chance = 25.0 + skill_bonus
	var user_skill = 10.0
	var target_resistance = _get_cached_target_resistance(target)
	var item_grip = _get_item_grip_strength(target_item)
	
	var disarm_chance = base_chance + user_skill - target_resistance - item_grip
	disarm_chance = clamp(disarm_chance, 5.0, 95.0)
	
	if randf() * 100.0 < disarm_chance:
		_execute_successful_disarm(target, target_item)
		return true
	else:
		show_message("You fail to disarm " + _get_target_name(target) + ".")
		return false

func _execute_successful_disarm(target: Node, target_item: Node):
	if target.has_method("drop_item"):
		target.drop_item(target_item)
	elif target.has_method("drop_active_item"):
		target.drop_active_item()
	
	if target.has_method("toggle_lying"):
		target.toggle_lying()
	
	if target.has_method("stun"):
		target.stun(2.0)
	
	show_message("You disarm " + _get_target_name(target) + ", knocking them down!")
	
	if audio_system:
		audio_system.play_positioned_sound(disarm_sound, controller.position, 0.5)

func _attempt_push_shove(target: Node, skill_bonus: float = 0.0) -> bool:
	var base_chance = 30.0 + skill_bonus
	var user_strength = 20.0
	var target_resistance = _get_cached_target_resistance(target)
	
	if "is_lying" in target and target.is_lying:
		base_chance += 20.0
	
	if "is_stunned" in target and target.is_stunned:
		base_chance += 30.0
	
	var push_chance = base_chance + user_strength - target_resistance
	push_chance = clamp(push_chance, 10.0, 80.0)
	
	if randf() * 100.0 < push_chance:
		_execute_successful_push(target)
		return true
	else:
		show_message("You try to shove " + _get_target_name(target) + " but they resist!")
		return false

func _execute_successful_push(target: Node):
	show_message("You shove " + _get_target_name(target) + "!")
	
	if target.has_method("apply_knockback"):
		var push_dir = (_get_entity_position(target) - controller.position).normalized()
		target.apply_knockback(push_dir, 15.0)
	
	if target.has_method("stun"):
		target.stun(0.5)
	
	if target.has_method("toggle_lying"):
		target.toggle_lying()
#endregion

#region SPECIAL INTERACTIONS
func _handle_ctrl_interaction(target: Node) -> bool:
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

func _handle_alt_interaction(target: Node) -> bool:
	_face_entity(target)
	
	if target.has_method("alt_click"):
		return target.alt_click(controller)
	
	if target.has_method("toggle"):
		return target.toggle(controller)
	
	return false

func _handle_middle_interaction(target: Node) -> bool:
	var target_pos = _get_entity_position(target)
	if target_pos != Vector2.ZERO:
		_point_to(target_pos)
		return true
	
	return false

func _handle_help_self_interaction(active_item: Node) -> bool:
	if active_item:
		if active_item.has_method("use_on_self"):
			return active_item.use_on_self(controller)
		elif active_item.has_method("use_on") and active_item.has_method("use"):
			return await active_item.use(controller)
		elif active_item.has_method("attack_self"):
			return active_item.attack_self(controller)
	
	show_message("You pat yourself down.")
	return true

func _handle_friendly_interaction(target: Node) -> bool:
	if _is_item_entity(target):
		return _handle_item_pickup(target)
	
	if target.has_method("interact"):
		return target.interact(controller)
	
	if target.has_method("attack_hand"):
		target.attack_hand(controller)
		return true
	
	if target.has_method("use"):
		return target.use(controller)
	
	show_message("You poke " + _get_target_name(target))
	return true

func _handle_item_pickup(item: Node) -> bool:
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

func _handle_self_harm(active_item: Node) -> bool:
	if active_item:
		var damage = 5.0
		if "force" in active_item:
			damage = active_item.force
		
		controller.take_damage(damage, "brute")
		show_message("You hurt yourself with " + _get_item_name(active_item) + "!")
	else:
		controller.take_damage(base_unarmed_damage, "brute")
		show_message("You punch yourself!")
	
	return true

func _use_item_on_target(item: Node, target: Node) -> bool:
	var result = false
	
	if target.has_method("attackby"):
		result = await target.attackby(item, controller)
	
	if not result and item.has_method("use_on"):
		result = await item.use_on(controller, target)
	
	if not result and item.has_method("attack"):
		result = item.attack(target, controller)
	
	if not result and item.has_method("afterattack"):
		result = item.afterattack(target, controller, true)
	
	if not result and target.has_method("attack_hand"):
		target.attack_hand(controller)
		result = true
	
	if not result:
		var item_name = _get_item_name(item)
		show_message("You use " + item_name + " on " + _get_target_name(target) + ".")
		result = true
	
	return result
#endregion

#region FIREMAN CARRY
func _can_fireman_carry_target(target: Node) -> bool:
	if not target or target == controller:
		return false
	
	if not ("is_lying" in target and target.is_lying):
		return false
	if not ("is_unconscious" in target and target.is_unconscious):
		if not ("health" in target and "max_health" in target):
			return false
		if target.health / target.max_health > 0.3:
			return false
	
	if not skill_component or not skill_component.can_fireman_carry():
		return false
	
	if "mass" in target and "mass" in controller:
		if target.mass > controller.mass * 1.5:
			return false
	
	return true

func _attempt_fireman_carry(target: Node) -> bool:
	if not _can_fireman_carry_target(target):
		return false
	
	if controller.has_node("GrabPullComponent"):
		var grab_component = controller.get_node("GrabPullComponent")
		if grab_component.grabbing_entity or grab_component.pulling_entity:
			show_message("You're already carrying someone!")
			return false
	
	var skill_level = skill_component.get_skill_level(skill_component.SKILL_FIREMAN) if skill_component else 0
	var base_chance = 60.0 + (skill_level * 15.0)
	
	if "mass" in target and "mass" in controller:
		var mass_ratio = target.mass / controller.mass
		base_chance -= (mass_ratio - 1.0) * 30.0
	
	base_chance = clamp(base_chance, 10.0, 95.0)
	
	if randf() * 100.0 < base_chance:
		if _start_fireman_carry(target):
			show_message("You lift " + _get_target_name(target) + " onto your shoulders!")
			return true
	
	show_message("You fail to lift " + _get_target_name(target) + " properly.")
	return false

func _start_fireman_carry(target: Node) -> bool:
	if controller.has_node("GrabPullComponent"):
		var grab_component = controller.get_node("GrabPullComponent")
		var success = grab_component.grab_entity(target, grab_component.GrabState.PASSIVE)
		
		if success:
			target.set_meta("being_carried", true)
			controller.set_meta("carrying_someone", true)
			
			if controller.has_method("apply_movement_modifier"):
				controller.apply_movement_modifier(0.7)
			
			return true
	
	return false
#endregion

#region UTILITY FUNCTIONS
func _check_interaction_cooldown() -> bool:
	var current_time = Time.get_ticks_msec() / 1000.0
	return current_time >= last_interaction_time + interaction_cooldown

func _can_interact_with(target: Node, max_range: float = -1.0) -> bool:
	if not target:
		return false
	
	if target == controller or target == controller.get_parent():
		return true
	
	var range_to_use = max_range if max_range > 0 else interaction_range
	
	if not _is_adjacent_to(target):
		var distance = _get_distance_to(target)
		
		var active_item = _get_active_item()
		if active_item and "max_range" in active_item:
			return distance <= active_item.max_range
		
		if controller.has_node("ItemInteractionComponent"):
			var item_interaction = controller.get_node("ItemInteractionComponent")
			if item_interaction.is_throw_mode_active:
				return distance <= 10.0
		
		if current_intent == CurrentIntent.HELP:
			return distance <= examine_range
		
		return false
	
	return true

func _is_adjacent_to(target: Node) -> bool:
	if not controller.has_method("is_adjacent_to"):
		return false
	
	return controller.is_adjacent_to(target)

func _is_adjacent_to_tile(tile_coords: Vector2i) -> bool:
	if not controller.has_method("get_current_tile_position"):
		return false
	
	var my_pos = controller.get_current_tile_position()
	var diff_x = abs(my_pos.x - tile_coords.x)
	var diff_y = abs(my_pos.y - tile_coords.y)
	
	return (diff_x <= 1 and diff_y <= 1) and not (diff_x == 0 and diff_y == 0)

func _get_distance_to(target: Node) -> float:
	if not controller.has_method("get_current_tile_position"):
		return 999.0
	
	var my_pos = Vector2(controller.get_current_tile_position())
	var target_pos_int = _get_entity_tile_position(target)
	var target_pos = Vector2(target_pos_int.x, target_pos_int.y)
	
	return my_pos.distance_to(target_pos)

func _get_cached_target_resistance(target: Node) -> float:
	var current_time = Time.get_ticks_msec() * 0.001
	var target_id = str(target.get_instance_id())
	
	if current_time - _resistance_cache_time > _resistance_cache_lifetime:
		_cached_target_resistances.clear()
		_resistance_cache_time = current_time
	
	if not _cached_target_resistances.has(target_id):
		var resistance = 0.0
		if "dexterity" in target:
			resistance = target.dexterity
		_cached_target_resistances[target_id] = resistance
	
	return _cached_target_resistances[target_id]

func _get_cqc_skill_bonus() -> float:
	if not skill_component:
		return 0.0
	
	var cqc_level = skill_component.get_skill_level(skill_component.SKILL_CQC)
	return cqc_level * 10.0

func _get_item_grip_strength(item: Node) -> float:
	if "grip_strength" in item:
		return item.grip_strength
	elif "w_class" in item:
		return item.w_class * 5.0
	return 0.0

func _apply_damage_to_target(target: Node, damage: float, damage_type: int):
	if target.has_method("take_damage"):
		target.take_damage(damage, damage_type)
	elif target.has_method("apply_damage"):
		target.apply_damage(damage, damage_type)
#endregion

#region ITEM CLASSIFICATION
func _is_item_entity(entity: Node) -> bool:
	return entity.has_method("get_script") and entity.get_script() and "Item" in str(entity.get_script().get_path())

func _is_item_harmful(item: Node) -> bool:
	if "force" in item and item.force > 5:
		return true
	if "tool_behaviour" in item and item.tool_behaviour == "weapon":
		return true
	if "harmful" in item and item.harmful:
		return true
	return false

func _is_grab_compatible_item(item: Node) -> bool:
	if "w_class" in item:
		return item.w_class <= 2
	if "allows_grabbing" in item:
		return item.allows_grabbing
	return false

func _is_medical_item(item: Node) -> bool:
	if not item:
		return false
	
	if item.get_script():
		var script_path = str(item.get_script().get_path())
		if "MedicalItem" in script_path or "HealthAnalyzer" in script_path:
			return true
	
	if "item_type" in item and item.item_type == "medical":
		return true
	if "medical_item" in item and item.medical_item:
		return true
	if "requires_medical_skill" in item and item.requires_medical_skill:
		return true
	
	var item_name = _get_item_name(item).to_lower()
	var medical_keywords = ["bandage", "splint", "syringe", "autoinjector", "pill", "medical", "trauma", "burn", "analyzer", "scanner"]
	return medical_keywords.any(func(keyword): return keyword in item_name)
#endregion

#region POSITION AND NAVIGATION
func _get_entity_position(entity: Node) -> Vector2:
	if "global_position" in entity:
		return entity.global_position
	elif "position" in entity:
		return entity.position
	return Vector2.ZERO

func _get_entity_tile_position(entity: Node) -> Vector2i:
	if not entity:
		return Vector2i.ZERO
	
	if "current_tile_position" in entity:
		return entity.current_tile_position
	elif entity.has_method("get_current_tile_position"):
		return entity.get_current_tile_position()
	elif controller.has_method("get_entity_tile_position"):
		return controller.get_entity_tile_position(entity)
	
	return Vector2i.ZERO

func _get_entity_on_tile(tile_coords: Vector2i) -> Node:
	if world and "tile_occupancy_system" in world and world.tile_occupancy_system:
		var z_level = controller.current_z_level if controller else 0
		var entities = world.tile_occupancy_system.get_entities_at(tile_coords, z_level)
		if entities and entities.size() > 0:
			return entities[0]
	return null

func _tile_to_world(tile_pos: Vector2i) -> Vector2:
	return Vector2((tile_pos.x * 32) + 16, (tile_pos.y * 32) + 16)

func _face_entity(target):
	if not controller.has_method("face_entity"):
		return
	controller.face_entity(target)

func _point_to(position: Vector2):
	var direction = (position - controller.position).normalized()
	var dir_text = _get_direction_text(direction)
	
	show_message(controller.entity_name + " points to the " + dir_text + ".")
	
	if world and world.has_method("spawn_visual_effect"):
		world.spawn_visual_effect("point", position, 1.0)

func _get_direction_text(direction: Vector2) -> String:
	var angle = rad_to_deg(atan2(direction.y, direction.x))
	
	var direction_ranges = [
		{"min": -22.5, "max": 22.5, "name": "east"},
		{"min": 22.5, "max": 67.5, "name": "southeast"},
		{"min": 67.5, "max": 112.5, "name": "south"},
		{"min": 112.5, "max": 157.5, "name": "southwest"},
		{"min": -157.5, "max": -112.5, "name": "northwest"},
		{"min": -112.5, "max": -67.5, "name": "north"},
		{"min": -67.5, "max": -22.5, "name": "northeast"}
	]
	
	for range_data in direction_ranges:
		if angle > range_data.min and angle <= range_data.max:
			return range_data.name
	
	if angle > 157.5 or angle <= -157.5:
		return "west"
	
	return "somewhere"
#endregion

#region VISUAL EFFECTS
func _trigger_interaction_thrust(target: Node, intent: int):
	if controller.has_node("SpriteSystem"):
		var sprite_system = controller.get_node("SpriteSystem")
		if sprite_system.has_method("show_interaction_thrust"):
			var direction_to_target = _get_direction_to_target(target)
			sprite_system.show_interaction_thrust(direction_to_target, intent)

func _get_direction_to_target(target: Node) -> Vector2:
	var target_pos = _get_entity_position(target)
	if target_pos == Vector2.ZERO:
		return Vector2.ZERO
	
	var my_pos = controller.position
	return (target_pos - my_pos).normalized()

#endregion

#region TILE EXAMINATION
func _examine_tile(tile_position: Vector2i):
	if not world:
		return
	
	var z_level = controller.current_z_level if controller else 0
	var tile_data = world.get_tile_data(tile_position, z_level) if world.has_method("get_tile_data") else null
	if not tile_data:
		return
	
	var description = _generate_tile_description(tile_data)
	
	emit_signal("examine_result", {"tile_position": tile_position}, description)
	
	if sensory_system:
		sensory_system.display_message("[color=#AAAAAA]" + description + "[/color]")

func _generate_tile_description(tile_data: Dictionary) -> String:
	if "door" in tile_data:
		return _generate_door_description(tile_data.door)
	elif "window" in tile_data:
		return _generate_window_description(tile_data.window)
	elif "floor" in tile_data:
		return "A " + tile_data.floor.type + " floor."
	elif "wall" in tile_data:
		return "A solid wall made of " + tile_data.wall.material + "."
	else:
		return "You see nothing special."

func _generate_door_description(door_data: Dictionary) -> String:
	var description = "A door. It appears to be " + ("closed" if door_data.closed else "open") + "."
	
	if "locked" in door_data and door_data.locked:
		description += " It seems to be locked."
	
	if "broken" in door_data and door_data.broken:
		description += " It looks broken."
	
	return description

func _generate_window_description(window_data: Dictionary) -> String:
	var description = "A window made of glass."
	
	if "reinforced" in window_data and window_data.reinforced:
		description += " It appears to be reinforced."
	
	if "health" in window_data and window_data.health < window_data.max_health:
		description += " It has some cracks."
	
	return description

func _handle_alt_tile_action(tile_coords: Vector2i):
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

#endregion

#region NAME UTILITIES
func _get_target_name(target: Node) -> String:
	if "entity_name" in target and target.entity_name != "":
		return target.entity_name
	elif "name" in target:
		return target.name
	else:
		return "that"

func _get_entity_name(entity: Node) -> String:
	if "entity_name" in entity and entity.entity_name != "":
		return entity.entity_name
	elif "name" in entity:
		return entity.name
	else:
		return "someone"

func _get_item_name(item: Node) -> String:
	if "item_name" in item:
		return item.item_name
	elif "name" in item:
		return item.name
	else:
		return "something"

func _get_active_item() -> Node:
	if inventory_system and inventory_system.has_method("get_active_item"):
		return inventory_system.get_active_item()
	return null

func show_message(text: String):
	if sensory_system:
		sensory_system.display_message(text)

func _has_emergency_access() -> bool:
	return controller.has_method("has_emergency_access") and controller.has_emergency_access()
#endregion

#region EVENT HANDLERS
func _on_intent_changed(new_intent: int):
	current_intent = new_intent
#endregion

#region NETWORK SYNCHRONIZATION
func _sync_interaction_to_network(target: Node, button_index: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	var action_data = {
		"target_id": _get_target_network_id(target),
		"ctrl": ctrl_pressed,
		"alt": alt_pressed,
		"middle": (button_index == MOUSE_BUTTON_MIDDLE),
		"intent": current_intent,
		"performer": _get_entity_name(controller)
	}
	sync_interaction.rpc(action_data)

func _sync_combat_result(target: Node, damage: float, damage_type: String, weapon_name: String):
	var result_data = {
		"damage": damage,
		"damage_type": damage_type,
		"weapon": weapon_name,
		"attacker": _get_entity_name(controller),
		"hit": true
	}
	sync_combat_result_rpc.rpc(_get_target_network_id(target), result_data)

func _get_target_network_id(target: Node) -> String:
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

@rpc("any_peer", "call_local", "reliable")
func sync_interaction(action_data: Dictionary):
	if multiplayer.get_remote_sender_id() == 0:
		return
	
	var target = _find_target_by_id(action_data.get("target_id", ""))
	if not target:
		return
	
	var performer_name = action_data.get("performer", "Someone")
	_show_interaction_visual(target, _get_action_type(action_data), performer_name)

@rpc("any_peer", "call_local", "reliable")
func sync_tile_action(tile_coords: Vector2i, action_type: String, performer_name: String):
	if multiplayer.get_remote_sender_id() == 0:
		return
	
	match action_type:
		"examine":
			_show_tile_visual_effect(tile_coords, "examine")
		"alt_action":
			_show_tile_visual_effect(tile_coords, "alt_action")
		"point":
			var world_pos = _tile_to_world(tile_coords)
			_show_point_visual(world_pos, performer_name)

@rpc("any_peer", "call_local", "reliable")
func sync_combat_result_rpc(target_id: String, result_data: Dictionary):
	if multiplayer.get_remote_sender_id() == 0:
		return
	
	var target = _find_target_by_id(target_id)
	if not target:
		return
	
	_show_combat_effect(target, result_data)

func _find_target_by_id(target_id: String) -> Node:
	if target_id == "":
		return null
	
	if target_id.begins_with("player_"):
		var peer_id = target_id.split("_")[1].to_int()
		return _find_player_by_peer_id(peer_id)
	
	if target_id.begins_with("/"):
		return get_node_or_null(target_id)
	
	var entities = get_tree().get_nodes_in_group("networkable")
	for entity in entities:
		if entity.has_meta("network_id") and str(entity.get_meta("network_id")) == target_id:
			return entity
		if entity.has_method("get_network_id") and entity.get_network_id() == target_id:
			return entity
	
	return null

func _find_player_by_peer_id(peer_id: int) -> Node:
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player.has_meta("peer_id") and player.get_meta("peer_id") == peer_id:
			return player
		if "peer_id" in player and player.peer_id == peer_id:
			return player
	
	return null

func _get_action_type(action_data: Dictionary) -> String:
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

func _show_interaction_visual(target: Node, action_type: String, performer_name: String):
	match action_type:
		"pull":
			_trigger_interaction_thrust(target, -1)
		"alt":
			_trigger_interaction_thrust(target, -2)
		"point":
			_show_point_visual(_get_entity_position(target), performer_name)
		"help":
			_trigger_interaction_thrust(target, 0)
		"disarm":
			_trigger_interaction_thrust(target, 1)
		"grab":
			_trigger_interaction_thrust(target, 2)
		"harm":
			_trigger_interaction_thrust(target, 3)

func _show_tile_visual_effect(tile_coords: Vector2i, effect_type: String):
	if world and world.has_method("spawn_visual_effect"):
		var world_pos = _tile_to_world(tile_coords)
		world.spawn_visual_effect(effect_type, world_pos, 0.5)

func _show_point_visual(position: Vector2, performer_name: String):
	var direction = (position - controller.position).normalized()
	var dir_text = _get_direction_text(direction)
	
	show_message(performer_name + " points to the " + dir_text + ".")
	
	if world and world.has_method("spawn_visual_effect"):
		world.spawn_visual_effect("point", position, 1.0)

func _show_combat_effect(target: Node, result_data: Dictionary):
	if world and world.has_method("spawn_damage_number"):
		world.spawn_damage_number(_get_entity_position(target), result_data.get("damage", 0), result_data.get("damage_type", "brute"))
	
	if audio_system:
		var hit_sound = "weapon_hit" if result_data.get("weapon", "") != "" else punch_sound
		audio_system.play_positioned_sound(hit_sound, _get_entity_position(target), 0.6)
#endregion
