extends Node
class_name ItemInteractionComponent

#region CONSTANTS
const MIN_THROW_DISTANCE: float = 1.0
const DROP_DISTANCE: float = 0.5
#endregion

#region SIGNALS
signal item_picked_up(item: Node)
signal item_dropped(item: Node)
signal item_thrown(item: Node, target_position: Vector2)
signal throw_mode_changed(enabled: bool)
signal throw_trajectory_updated(trajectory: Array)
signal active_hand_changed(hand_index: int, item: Node)
#endregion

#region EXPORTS
@export_group("Interaction Configuration")
@export var pickup_range: float = 1.5
@export var throw_range_base: float = 10.0
@export var throw_cooldown_duration: float = 0.5

@export_group("Throwing Physics")
@export var trajectory_segments: int = 20
@export var arc_height_multiplier: float = 0.2
@export var max_arc_height: float = 32.0

@export_group("Experience Settings")
@export var medical_experience_chance: float = 0.3
@export var advanced_medical_experience_chance: float = 0.4
@export var surgery_experience_chance: float = 0.2
@export var engineering_experience_chance: float = 0.25
@export var construction_experience_chance: float = 0.25

@export_group("Skill Penalties")
@export var one_handed_accuracy_penalties: Dictionary = {
	"pistol": 0.9,
	"rifle": 0.4,
	"shotgun": 0.5,
	"sniper": 0.2,
	"special": 0.6
}

@export_group("Audio Settings")
@export var pickup_sound: String = "pickup"
@export var drop_sound: String = "drop"
@export var throw_sound: String = "throw"
@export var default_audio_volume: float = 0.3
#endregion

#region PROPERTIES
# Component references
var controller: Node = null
var inventory_system: Node = null
var weapon_handling_component: Node = null
var skill_component: Node = null
var sensory_system: Node = null
var audio_system: Node = null
var world: Node = null
var tile_occupancy_system: Node = null
var do_after_component: Node = null
var player_ui = null

# Throw mode state
var throw_mode: bool = false : set = _set_throw_mode
var is_throw_mode_active: bool = false : set = _set_throw_mode_active
var throw_target_item_id: String = "" : set = _set_throw_target_item_id
var active_hand_index: int = 0 : set = _set_active_hand_index

# Operation state
var throw_trajectory: Array = []
var throw_power: float = 1.0
var throw_toggle_cooldown: float = 0.0
var cached_throw_target_item: Node = null

# Cached values for performance
var _nearby_items_cache: Array = []
var _cache_update_time: float = 0.0
var _cache_lifetime: float = 0.5
#endregion

#region INITIALIZATION
func initialize(init_data: Dictionary):
	controller = init_data.get("controller")
	inventory_system = init_data.get("inventory_system")
	sensory_system = init_data.get("sensory_system")
	audio_system = init_data.get("audio_system")
	skill_component = init_data.get("skill_component")
	world = init_data.get("world")
	tile_occupancy_system = init_data.get("tile_occupancy_system")
	do_after_component = init_data.get("do_after_component")
	
	_connect_weapon_handling()
	
	if not do_after_component and controller:
		do_after_component = controller.get_node_or_null("DoAfterComponent")

func _ready() -> void:
	player_ui = get_parent().get_node_or_null("PlayerUI")

func _connect_weapon_handling():
	if controller:
		weapon_handling_component = controller.get_node_or_null("WeaponHandlingComponent")

func _process(delta: float):
	_update_cooldowns(delta)
	_update_throw_mode(delta)

func _update_cooldowns(delta: float):
	if throw_toggle_cooldown > 0:
		throw_toggle_cooldown -= delta

func _update_throw_mode(delta: float):
	if is_throw_mode_active and get_throw_target_item():
		update_throw_trajectory()
#endregion

#region PROPERTY SETTERS
func _set_throw_mode(value: bool):
	if throw_mode != value:
		throw_mode = value
		emit_signal("throw_mode_changed", throw_mode)

func _set_throw_mode_active(value: bool):
	if is_throw_mode_active != value:
		is_throw_mode_active = value
		emit_signal("throw_mode_changed", is_throw_mode_active)

func _set_throw_target_item_id(value: String):
	if throw_target_item_id != value:
		throw_target_item_id = value
		cached_throw_target_item = null

func _set_active_hand_index(value: int):
	if active_hand_index != value:
		active_hand_index = value
		var item = get_active_item()
		emit_signal("active_hand_changed", active_hand_index, item)

func get_throw_target_item() -> Node:
	if not cached_throw_target_item and throw_target_item_id != "":
		cached_throw_target_item = get_item_by_network_id(throw_target_item_id)
	return cached_throw_target_item
#endregion

#region ITEM PICKUP
func try_pick_up_item(item: Node) -> bool:
	if not item or not _validate_pickup_basic(item):
		return false
	
	if not _check_pickup_skills(item) or not _check_pickup_distance(item):
		return false
	
	if do_after_component and do_after_component.is_performing_action():
		show_message("You're busy doing something else!")
		return false
	
	_face_towards_item(item)
	
	# Check if this should use do_after
	if _should_use_do_after_for_pickup(item):
		if not do_after_component:
			return _execute_pickup(item)
		
		var callback = Callable(self, "_execute_pickup")
		var config_override = {
			"base_duration": _get_pickup_duration(item),
			"display_name": "picking up " + get_item_name(item)
		}
		return do_after_component.start_action("pickup_item", config_override, callback, item)
	else:
		return _execute_pickup(item)

func _execute_pickup(item: Node) -> bool:
	if not item or not is_instance_valid(item):
		return false
	
	if not _check_pickup_distance(item):
		show_message("You need to be closer to pick that up!")
		return false
	
	if inventory_system.pick_up_item(item):
		_handle_successful_pickup(item)
		return true
	
	return false

func _should_use_do_after_for_pickup(item: Node) -> bool:
	if not item:
		return false
	
	# Heavy items should use do_after
	if "mass" in item and item.mass > 15:
		return true
	
	# Large items should use do_after
	if "w_class" in item and item.w_class > 4:
		return true
	
	# Items that are stuck or need effort
	if "pickup_time" in item and item.pickup_time > 0:
		return true
	
	if "embedded" in item and item.embedded:
		return true
	
	return false

func _get_pickup_duration(item: Node) -> float:
	var base_time = 1.0
	
	if "pickup_time" in item:
		base_time = item.pickup_time
	elif "mass" in item:
		base_time = max(0.5, item.mass * 0.1)
	elif "w_class" in item:
		base_time = max(0.5, item.w_class * 0.3)
	
	return base_time

func try_pickup_nearest_item() -> bool:
	var nearest_item = find_nearest_pickupable_item()
	
	if nearest_item:
		return try_pick_up_item(nearest_item)
	else:
		show_message("There's nothing nearby to pick up.")
		return false

func find_nearest_pickupable_item() -> Node:
	_update_nearby_items_cache()
	
	var nearest_item = null
	var nearest_distance = pickup_range * 32
	
	for item in _nearby_items_cache:
		if not _is_item_pickupable(item):
			continue
		
		var distance = controller.position.distance_to(item.position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_item = item
	
	return nearest_item

func _validate_pickup_basic(item: Node) -> bool:
	if not _find_inventory_system():
		show_message("ERROR: No inventory system found!")
		return false
	
	if not _is_item_pickupable(item):
		show_message("You can't pick that up.")
		return false
	
	return true

func _check_pickup_skills(item: Node) -> bool:
	if not skill_component:
		return true
	
	return _check_mass_requirement(item) and _check_restriction_requirement(item) and _check_technical_requirement(item)

func _check_mass_requirement(item: Node) -> bool:
	if "mass" in item and item.mass > 20:
		if not skill_component.is_skilled(skill_component.SKILL_ENDURANCE, skill_component.SKILL_LEVEL_NOVICE):
			show_message("That's too heavy for you to lift!")
			return false
	return true

func _check_restriction_requirement(item: Node) -> bool:
	if "restricted" in item and item.restricted:
		if not skill_component.is_skilled(skill_component.SKILL_ANTAG, skill_component.SKILL_LEVEL_NOVICE):
			show_message("You don't know how to handle illegal equipment!")
			return false
	return true

func _check_technical_requirement(item: Node) -> bool:
	if "technical_item" in item and item.technical_item:
		if not skill_component.can_do_engineering():
			show_message("This equipment is too complex for you!")
			return false
	return true

func _check_pickup_distance(item: Node) -> bool:
	var distance = controller.position.distance_to(item.position)
	if distance > pickup_range * 32:
		show_message("That's too far away.")
		return false
	return true

func _handle_successful_pickup(item: Node):
	_play_pickup_audio()
	_show_pickup_message(item)
	emit_signal("item_picked_up", item)
	_force_ui_refresh()
	_sync_pickup_to_network(item)

func _play_pickup_audio():
	if audio_system:
		audio_system.play_positioned_sound(pickup_sound, controller.position, default_audio_volume)

func _show_pickup_message(item: Node):
	var item_name = get_item_name(item)
	var picker_name = get_entity_name(controller)
	show_message(picker_name + " picks up " + item_name + ".")

func _sync_pickup_to_network(item: Node):
	var item_id = get_item_network_id(item)
	if item_id != "":
		var picker_name = get_entity_name(controller)
		sync_pickup_item.rpc(item_id, picker_name)
#endregion

#region ITEM DROPPING
func drop_active_item(throw_force: float = 0.0) -> bool:
	if not _find_inventory_system():
		return false
	
	var active_item = inventory_system.get_active_item()
	if not active_item:
		show_message("You have nothing to drop!")
		return false
	
	if do_after_component and do_after_component.is_performing_action():
		show_message("You're busy doing something else!")
		return false
	
	var drop_dir = _get_drop_direction()
	var item_name = get_item_name(active_item)
	var dropper_name = get_entity_name(controller)
	
	var success = false
	if throw_force > 0.0:
		success = _execute_throw_drop(active_item, drop_dir, throw_force, item_name, dropper_name)
	else:
		success = _execute_normal_drop(active_item, drop_dir, item_name, dropper_name)
	
	if success:
		_force_ui_refresh()
	
	return success

func _execute_throw_drop(item: Node, drop_dir: Vector2, throw_force: float, item_name: String, dropper_name: String) -> bool:
	var success = inventory_system.throw_item(inventory_system.active_hand, drop_dir, throw_force)
	
	if success:
		_play_throw_audio()
		show_message(dropper_name + " throws " + item_name + "!")
		emit_signal("item_dropped", item)
		sync_drop_item.rpc(dropper_name, item_name, "throws")
	
	return success

func _execute_normal_drop(item: Node, drop_dir: Vector2, item_name: String, dropper_name: String) -> bool:
	var result = inventory_system.drop_item(inventory_system.active_hand, drop_dir, false)
	
	if result == inventory_system.ITEM_UNEQUIP_DROPPED:
		_play_drop_audio()
		show_message(dropper_name + " drops " + item_name + ".")
		emit_signal("item_dropped", item)
		sync_drop_item.rpc(dropper_name, item_name, "drops")
		return true
	
	return false

func _get_drop_direction() -> Vector2:
	if not controller.has_method("get_current_direction"):
		return Vector2.DOWN
	
	var current_direction = controller.get_current_direction()
	
	var direction_map = {
		0: Vector2(0, -1),
		1: Vector2(1, 0),
		2: Vector2(0, 1),
		3: Vector2(-1, 0),
		4: Vector2(1, -1).normalized(),
		5: Vector2(1, 1).normalized(),
		6: Vector2(-1, 1).normalized(),
		7: Vector2(-1, -1).normalized()
	}
	
	return direction_map.get(current_direction, Vector2.DOWN)

func _play_drop_audio():
	if audio_system:
		audio_system.play_positioned_sound(drop_sound, controller.position, default_audio_volume)

func _play_throw_audio():
	if audio_system:
		audio_system.play_positioned_sound(throw_sound, controller.position, 0.4)
#endregion

#region ITEM USAGE
func use_active_item():
	if not _find_inventory_system():
		return false
	
	var active_item = inventory_system.get_active_item()
	if not active_item:
		return false
	
	if not _check_item_skill_requirements(active_item):
		return false
	
	if do_after_component and do_after_component.is_performing_action():
		show_message("You're busy doing something else!")
		return false
	
	if _is_weapon(active_item) and weapon_handling_component:
		return weapon_handling_component.handle_weapon_use(active_item)
	
	# Check if this should use do_after
	if _should_use_do_after_for_item_use(active_item):
		if not do_after_component:
			return await _execute_item_use(active_item)
		
		var callback = Callable(self, "_execute_item_use")
		return do_after_component.start_item_action("use_complex_item", active_item, callback)
	else:
		return await _execute_item_use(active_item)

func _execute_item_use(item: Node):
	if not item or not is_instance_valid(item):
		return false
	
	var item_name = get_item_name(item)
	var user_name = get_entity_name(controller)
	
	var success = await inventory_system.use_active_item()
	
	if success:
		_handle_successful_use(user_name, item_name)
		_grant_skill_experience_for_item_use(item)
	
	return success

func use_item_in_slot(slot: int) -> bool:
	if not _find_inventory_system():
		return false
	
	var item = inventory_system.get_item_in_slot(slot)
	if not item:
		return false
	
	if do_after_component and do_after_component.is_performing_action():
		show_message("You're busy doing something else!")
		return false
	
	if _is_weapon(item) and weapon_handling_component:
		return weapon_handling_component.handle_weapon_use(item)
	
	# Check if this should use do_after
	if _should_use_do_after_for_item_use(item):
		if not do_after_component:
			return await _try_use_item_methods(item)
		
		var callback = Callable(self, "_try_use_item_methods")
		return do_after_component.start_item_action("use_complex_item", item, callback)
	else:
		return await _try_use_item_methods(item)

func _should_use_do_after_for_item_use(item: Node) -> bool:
	if not item:
		return false
	
	# Medical items should use do_after
	if _is_medical_item(item):
		return true
	
	# Engineering tools should use do_after
	if _is_engineering_tool(item):
		return true
	
	# Construction tools should use do_after
	if _is_construction_tool(item):
		return true
	
	# Complex items should use do_after
	if "complex_item" in item and item.complex_item:
		return true
	
	# Items with use_time should use do_after
	if "use_time" in item and item.use_time > 0:
		return true
	
	# Advanced medical items always use do_after
	if _is_advanced_medical_item(item):
		return true
	
	return false

func _check_item_skill_requirements(item: Node) -> bool:
	if not skill_component or not item:
		return true
	
	return _check_explicit_requirements(item) and _check_type_requirements(item)

func _check_explicit_requirements(item: Node) -> bool:
	if "required_skills" in item:
		for skill_req in item.required_skills:
			var skill_name = skill_req.get("skill", "")
			var required_level = skill_req.get("level", 0)
			
			if not skill_component.skillcheck(skill_name, required_level, true):
				return false
	return true

func _check_type_requirements(item: Node) -> bool:
	var checks = [
		_check_medical_requirements,
		_check_advanced_medical_requirements,
		_check_engineering_requirements,
		_check_construction_requirements
	]
	
	for check in checks:
		if not check.call(item):
			return false
	
	return true

func _check_medical_requirements(item: Node) -> bool:
	if _is_medical_item(item) and not skill_component.can_use_medical_items():
		show_message("You don't know how to use medical equipment!")
		return false
	return true

func _check_advanced_medical_requirements(item: Node) -> bool:
	if _is_advanced_medical_item(item) and not skill_component.can_use_advanced_medical():
		show_message("This medical equipment is too complex for you!")
		return false
	return true

func _check_engineering_requirements(item: Node) -> bool:
	if _is_engineering_tool(item) and not skill_component.can_do_engineering():
		show_message("You don't know how to use engineering tools!")
		return false
	return true

func _check_construction_requirements(item: Node) -> bool:
	if _is_construction_tool(item) and not skill_component.can_do_construction():
		show_message("You don't know how to use construction tools!")
		return false
	return true

func _try_use_item_methods(item: Node) -> bool:
	var methods = ["use", "interact", "attack_self"]
	
	for method in methods:
		if item.has_method(method):
			return await item.call(method, controller)
	
	return false

func _handle_successful_use(user_name: String, item_name: String):
	_force_ui_refresh()
	show_message(user_name + " uses " + item_name + ".")
	
	var use_data = {
		"user_name": user_name,
		"item_name": item_name
	}
	sync_use_item.rpc(use_data)

func _grant_skill_experience_for_item_use(item: Node):
	if not skill_component or not skill_component.allow_skill_gain:
		return
	
	var experience_grants = [
		{
			"condition": _is_medical_item(item),
			"skill": skill_component.SKILL_MEDICAL,
			"chance": medical_experience_chance,
			"cap": 2
		},
		{
			"condition": _is_advanced_medical_item(item),
			"skill": skill_component.SKILL_MEDICAL,
			"chance": advanced_medical_experience_chance,
			"cap": 3
		},
		{
			"condition": _is_advanced_medical_item(item),
			"skill": skill_component.SKILL_SURGERY,
			"chance": surgery_experience_chance,
			"cap": 2
		},
		{
			"condition": _is_engineering_tool(item),
			"skill": skill_component.SKILL_ENGINEER,
			"chance": engineering_experience_chance,
			"cap": 2
		},
		{
			"condition": _is_construction_tool(item),
			"skill": skill_component.SKILL_CONSTRUCTION,
			"chance": construction_experience_chance,
			"cap": 2
		}
	]
	
	for grant in experience_grants:
		if grant.condition and randf() < grant.chance:
			skill_component.increment_skill(grant.skill, 1, grant.cap)
#endregion

#region THROWING SYSTEM
func toggle_throw_mode() -> bool:
	if throw_toggle_cooldown > 0 or not _find_inventory_system():
		return false
	
	if do_after_component and do_after_component.is_performing_action():
		show_message("You're busy doing something else!")
		return false
	
	var new_throw_mode = not throw_mode
	var active_item = inventory_system.get_active_item()
	var user_name = get_entity_name(controller)
	
	if weapon_handling_component and weapon_handling_component.is_wielding_weapon():
		show_message("You can't throw while wielding a weapon!")
		return false
	
	if new_throw_mode:
		return _activate_throw_mode(active_item, user_name)
	else:
		_deactivate_throw_mode(user_name)
		return true

func _activate_throw_mode(active_item: Node, user_name: String) -> bool:
	if not active_item:
		show_message("You have nothing to throw!")
		return false
	
	throw_mode = true
	is_throw_mode_active = true
	throw_target_item_id = get_item_network_id(active_item)
	cached_throw_target_item = active_item
	
	var item_name = get_item_name(active_item)
	show_message(user_name + " prepares to throw " + item_name + ".")
	
	_setup_throw_mode_visuals(active_item)
	player_ui.toggle_throw_indicator("on")
	throw_toggle_cooldown = throw_cooldown_duration
	
	sync_throw_mode_toggle.rpc({
		"enable": true,
		"user_name": user_name,
		"item_name": item_name
	})
	
	return true

func _deactivate_throw_mode(user_name: String):
	_exit_throw_mode()
	
	sync_throw_mode_toggle.rpc({
		"enable": false,
		"user_name": user_name,
		"item_name": ""
	})

func _setup_throw_mode_visuals(active_item: Node):
	update_throw_trajectory()
	
	var cursor_controller = controller.get_parent().get_node_or_null("CursorController")
	if cursor_controller and cursor_controller.has_method("set_cursor_mode"):
		cursor_controller.set_cursor_mode("throw")
	
	if active_item and active_item.has_method("set_highlighted"):
		active_item.set_highlighted(true)

func _exit_throw_mode():
	if not is_throw_mode_active:
		return
	
	is_throw_mode_active = false
	throw_mode = false
	
	_cleanup_throw_mode_visuals()
	
	throw_target_item_id = ""
	cached_throw_target_item = null
	
	emit_signal("throw_trajectory_updated", [])
	show_message("You relax your throwing arm.")
	player_ui.toggle_throw_indicator("off")

func _cleanup_throw_mode_visuals():
	var target_item = get_throw_target_item()
	if target_item and is_instance_valid(target_item):
		if target_item.has_method("set_highlighted"):
			target_item.set_highlighted(false)
	
	var cursor_controller = controller.get_parent().get_node_or_null("CursorController")
	if cursor_controller and cursor_controller.has_method("set_cursor_mode"):
		cursor_controller.set_cursor_mode("default")

func update_throw_trajectory():
	if not is_throw_mode_active:
		return
	
	var mouse_world_pos = controller.get_global_mouse_position()
	var max_throw_dist = _calculate_max_throw_distance()
	
	var direction = (mouse_world_pos - controller.position).normalized()
	var distance = controller.position.distance_to(mouse_world_pos)
	
	if distance > max_throw_dist:
		mouse_world_pos = controller.position + direction * max_throw_dist
	
	var final_position = _check_throw_path(controller.position, mouse_world_pos)
	var trajectory = _calculate_trajectory_points(controller.position, final_position)
	
	emit_signal("throw_trajectory_updated", trajectory)
	
	sync_throw_trajectory.rpc({
		"trajectory": trajectory,
		"player_id": get_entity_name(controller),
		"start_pos": controller.position,
		"end_pos": final_position
	})

func throw_at_tile(tile_coords: Vector2i) -> bool:
	if not is_throw_mode_active:
		return false
	
	var world_position = _tile_to_world(tile_coords)
	return throw_item_at_position(world_position)

func throw_item_at_position(world_position: Vector2) -> bool:
	if not is_throw_mode_active or not _find_inventory_system():
		return false
	
	var active_item = inventory_system.get_active_item()
	if not active_item:
		return false
	
	var item_name = get_item_name(active_item)
	var thrower_name = get_entity_name(controller)
	
	_face_towards_position(world_position)
	
	var success = inventory_system.throw_item_to_position(inventory_system.active_hand, world_position)
	
	if success:
		_handle_successful_throw(thrower_name, item_name, world_position, active_item)
		return true
	
	return false

func _handle_successful_throw(thrower_name: String, item_name: String, world_position: Vector2, item: Node):
	_play_throw_audio()
	show_message(thrower_name + " throws " + item_name + "!")
	
	_exit_throw_mode()
	
	emit_signal("item_thrown", item, world_position)
	_force_ui_refresh()
	
	sync_throw_item.rpc(thrower_name, item_name, world_position)

func _calculate_max_throw_distance() -> float:
	var max_dist = throw_range_base * 32
	
	var strength_modifier = _get_strength_modifier()
	max_dist *= max(strength_modifier, 0.5)
	
	if skill_component:
		var endurance_level = skill_component.get_skill_level(skill_component.SKILL_ENDURANCE)
		var endurance_bonus = 1.0 + (endurance_level * 0.1)
		max_dist *= endurance_bonus
	
	var active_item = get_active_item()
	if active_item:
		max_dist = _apply_item_throw_modifiers(max_dist, active_item)
	
	return max_dist

func _apply_item_throw_modifiers(max_dist: float, item: Node) -> float:
	if "mass" in item and item.mass > 0:
		var mass_penalty = clamp(1.0 - (item.mass - 1.0) * 0.05, 0.2, 1.0)
		max_dist *= mass_penalty
	
	if "throw_range_multiplier" in item:
		max_dist *= item.throw_range_multiplier
	
	if "throw_range" in item and item.throw_range > 0:
		var item_max = item.throw_range * 32
		max_dist = min(max_dist, item_max)
	
	return max_dist

func _check_throw_path(start_pos: Vector2, end_pos: Vector2) -> Vector2:
	if not controller.has_method("get_current_tile_position"):
		return end_pos
	
	var start_tile = _world_to_tile(start_pos)
	var end_tile = _world_to_tile(end_pos)
	
	var path_tiles = _get_line_tiles(start_tile, end_tile)
	
	if path_tiles.size() > 1:
		path_tiles.remove_at(0)
	
	for tile_pos in path_tiles:
		if _is_tile_blocking_throw(tile_pos):
			var index = path_tiles.find(tile_pos)
			if index > 0:
				var landing_tile = path_tiles[index - 1]
				return _tile_to_world(landing_tile)
			else:
				return start_pos
	
	return end_pos

func _is_tile_blocking_throw(tile_pos: Vector2i) -> bool:
	var z_level = controller.current_z_level if "current_z_level" in controller else 0
	
	var blocking_checks = [
		world.has_method("is_wall_at") and world.is_wall_at(tile_pos, z_level),
		world.has_method("is_closed_door_at") and world.is_closed_door_at(tile_pos, z_level),
		world.has_method("is_window_at") and world.is_window_at(tile_pos, z_level)
	]
	
	for check in blocking_checks:
		if check:
			return true
	
	if tile_occupancy_system and tile_occupancy_system.has_method("has_dense_entity_at"):
		if tile_occupancy_system.has_dense_entity_at(tile_pos, z_level, controller):
			return true
	
	return false

func _calculate_trajectory_points(start_pos: Vector2, end_pos: Vector2) -> Array:
	var trajectory = []
	var distance = start_pos.distance_to(end_pos)
	var arc_height = min(distance * arc_height_multiplier, max_arc_height)
	
	for i in range(trajectory_segments + 1):
		var t = float(i) / trajectory_segments
		
		var x = lerp(start_pos.x, end_pos.x, t)
		var y = lerp(start_pos.y, end_pos.y, t)
		
		var height_offset = 4.0 * arc_height * t * (1.0 - t)
		y += -height_offset
		
		trajectory.append(Vector2(x, y))
	
	return trajectory

func _get_line_tiles(start: Vector2i, end: Vector2i) -> Array:
	var tiles = []
	
	var x0 = start.x
	var y0 = start.y
	var x1 = end.x
	var y1 = end.y
	
	var dx = abs(x1 - x0)
	var dy = abs(y1 - y0)
	var sx = 1 if x0 < x1 else -1
	var sy = 1 if y0 < y1 else -1
	var err = dx - dy
	
	tiles.append(Vector2i(x0, y0))
	
	while x0 != x1 or y0 != y1:
		var e2 = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy
		
		tiles.append(Vector2i(x0, y0))
	
	return tiles
#endregion

#region HAND MANAGEMENT
func swap_active_hand() -> int:
	if not _find_inventory_system():
		return 0
	
	if weapon_handling_component and weapon_handling_component.is_hands_occupied():
		show_message("You can't switch hands while wielding a weapon!")
		return active_hand_index
	
	var new_hand = inventory_system.switch_active_hand()
	var new_hand_index = 0 if new_hand == inventory_system.EquipSlot.RIGHT_HAND else 1
	active_hand_index = new_hand_index
	
	var active_item = inventory_system.get_active_item()
	
	emit_signal("active_hand_changed", active_hand_index, active_item)
	
	_handle_hand_swap_feedback(new_hand_index, active_item)
	
	return active_hand_index

func _handle_hand_swap_feedback(hand_index: int, active_item: Node):
	var hand_name = "right" if hand_index == 0 else "left"
	var item_name = ""
	var user_name = get_entity_name(controller)
	
	if active_item:
		item_name = get_item_name(active_item)
		show_message(user_name + " switches to their " + hand_name + " hand (" + item_name + ").")
	else:
		show_message(user_name + " switches to their " + hand_name + " hand.")
	
	_force_ui_refresh()
	sync_hand_swap.rpc(user_name, hand_name, item_name)

func get_active_item() -> Node:
	if not _find_inventory_system():
		return null
	
	return inventory_system.get_active_item()

func get_item_in_hand(hand_index: int) -> Node:
	if not _find_inventory_system():
		return null
	
	var slot = inventory_system.EquipSlot.RIGHT_HAND if hand_index == 0 else inventory_system.EquipSlot.LEFT_HAND
	return inventory_system.get_item_in_slot(slot)
#endregion

#region WEAPON DELEGATION
func handle_weapon_interaction_with_item(weapon: Node, target_item: Node) -> bool:
	if not weapon_handling_component:
		return false
	
	if _is_magazine(target_item):
		return weapon_handling_component.handle_weapon_click_with_magazine(weapon, target_item)
	
	return false

func handle_weapon_empty_hand_click(weapon: Node) -> bool:
	if not weapon_handling_component:
		return false
	
	return weapon_handling_component.handle_weapon_click_with_empty_hand(weapon)

func handle_weapon_alt_click(weapon: Node) -> bool:
	if not weapon_handling_component:
		return false
	
	return weapon_handling_component.handle_weapon_alt_click(weapon)

func handle_weapon_ctrl_click(weapon: Node) -> bool:
	if not weapon_handling_component:
		return false
	
	return weapon_handling_component.handle_weapon_ctrl_click(weapon)
#endregion

#region ITEM TYPE CLASSIFICATION
func _is_medical_item(item: Node) -> bool:
	if not item:
		return false
	
	if "item_type" in item and item.item_type == "medical":
		return true
	if "medical_item" in item and item.medical_item:
		return true
	
	var item_name = get_item_name(item).to_lower()
	var basic_medical = ["bandage", "ointment", "pill", "autoinjector", "splint"]
	return basic_medical.any(func(keyword): return keyword in item_name)

func _is_advanced_medical_item(item: Node) -> bool:
	if not item:
		return false
	
	if "advanced_medical" in item and item.advanced_medical:
		return true
	
	var item_name = get_item_name(item).to_lower()
	var advanced_medical = ["defibrillator", "surgery", "scalpel", "hemostat", "scanner", "analyzer"]
	return advanced_medical.any(func(keyword): return keyword in item_name)

func _is_engineering_tool(item: Node) -> bool:
	if not item:
		return false
	
	if "tool_type" in item and item.tool_type == "engineering":
		return true
	if "engineering_tool" in item and item.engineering_tool:
		return true
	
	var item_name = get_item_name(item).to_lower()
	var engineering_tools = ["wrench", "screwdriver", "wirecutters", "multitool", "analyzer", "welder"]
	return engineering_tools.any(func(keyword): return keyword in item_name)

func _is_construction_tool(item: Node) -> bool:
	if not item:
		return false
	
	if "tool_type" in item and item.tool_type == "construction":
		return true
	if "construction_tool" in item and item.construction_tool:
		return true
	
	var item_name = get_item_name(item).to_lower()
	var construction_tools = ["hammer", "drill", "saw", "nails", "plank", "girder", "plasteel"]
	return construction_tools.any(func(keyword): return keyword in item_name)

func _is_weapon(item: Node) -> bool:
	return item and item.entity_type == "gun"

func _is_magazine(item: Node) -> bool:
	if not item:
		return false
	
	if item.get_script():
		var script_path = str(item.get_script().get_path())
		if "Magazine" in script_path:
			return true
	
	if "ammo_type" in item and "current_ammo" in item:
		return true
	
	if "entity_type" in item and item.entity_type == "magazine":
		return true
	
	return false

func _is_item_pickupable(item: Node) -> bool:
	return item and "pickupable" in item and item.pickupable
#endregion

#region UTILITY FUNCTIONS
func _update_nearby_items_cache():
	var current_time = Time.get_ticks_msec() * 0.001
	if current_time - _cache_update_time < _cache_lifetime:
		return
	
	_nearby_items_cache = _get_items_in_radius(controller.position, pickup_range * 32)
	_cache_update_time = current_time

func _get_items_in_radius(center: Vector2, radius: float) -> Array:
	var items = []
	
	if world and world.has_method("get_entities_in_radius"):
		var z_level = controller.current_z_level if "current_z_level" in controller else 0
		var entities = world.get_entities_in_radius(center, radius, z_level)
		
		for entity in entities:
			if _is_item_entity(entity):
				items.append(entity)
	else:
		var all_items = controller.get_tree().get_nodes_in_group("items")
		for item in all_items:
			if item.global_position.distance_to(center) <= radius:
				items.append(item)
	
	return items

func _is_item_entity(entity: Node) -> bool:
	if entity.has_method("get_script") and entity.get_script():
		var script = entity.get_script()
		return script and "Item" in str(script.get_path())
	return false

func _get_strength_modifier() -> float:
	var stats_system = controller.get_parent().get_node_or_null("StatsSystem")
	if stats_system and stats_system.has_method("get_throw_strength_multiplier"):
		return stats_system.get_throw_strength_multiplier()
	return 1.0

func _face_towards_item(item: Node):
	if controller.has_method("face_entity"):
		controller.face_entity(item)
	elif controller.interaction_component and controller.interaction_component.has_method("face_entity"):
		controller.interaction_component.face_entity(item)

func _face_towards_position(position: Vector2):
	if controller.has_method("face_entity"):
		controller.face_entity(position)
	elif controller.interaction_component and controller.interaction_component.has_method("face_entity"):
		controller.interaction_component.face_entity(position)

func _find_inventory_system() -> bool:
	if inventory_system:
		return true
	
	var search_locations = [
		controller.get_node_or_null("InventorySystem"),
		controller.get_parent().get_node_or_null("InventorySystem")
	]
	
	for location in search_locations:
		if location:
			inventory_system = location
			return true
	
	if controller.get_parent().has_method("get_inventory_system"):
		inventory_system = controller.get_parent().get_inventory_system()
		if inventory_system:
			return true
	
	for child in controller.get_children():
		if child.has_method("get_script") and child.get_script() and "InventorySystem" in str(child.get_script().get_path()):
			inventory_system = child
			return true
	
	return false

func _force_ui_refresh():
	var ui = controller.get_node_or_null("PlayerUI")
	if ui:
		if ui.has_method("force_ui_refresh"):
			ui.force_ui_refresh()
		elif ui.has_method("update_all_slots"):
			ui.update_all_slots()
			if ui.has_method("update_active_hand"):
				ui.update_active_hand()

func _tile_to_world(tile_pos: Vector2i) -> Vector2:
	return Vector2((tile_pos.x * 32) + 16, (tile_pos.y * 32) + 16)

func _world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x / 32), int(world_pos.y / 32))
#endregion

#region NETWORK ID MANAGEMENT
func get_item_network_id(item: Node) -> String:
	if not item:
		return ""
	
	if inventory_system and inventory_system.has_method("get_item_network_id"):
		return inventory_system.get_item_network_id(item)
	
	if item.has_method("get_network_id"):
		return item.get_network_id()
	elif "network_id" in item:
		return str(item.network_id)
	elif item.has_meta("network_id"):
		return str(item.get_meta("network_id"))
	
	var new_id = str(item.get_instance_id()) + "_" + str(Time.get_ticks_msec())
	item.set_meta("network_id", new_id)
	return new_id

func get_item_by_network_id(network_id: String) -> Node:
	if network_id == "":
		return null
	
	if inventory_system and inventory_system.has_method("find_item_by_network_id"):
		return inventory_system.find_item_by_network_id(network_id)
	
	if world and world.has_method("get_item_by_network_id"):
		return world.get_item_by_network_id(network_id)
	
	var all_items = get_tree().get_nodes_in_group("items")
	for item in all_items:
		if get_item_network_id(item) == network_id:
			return item
	
	return null

func get_entity_name(entity: Node) -> String:
	if "entity_name" in entity and entity.entity_name != "":
		return entity.entity_name
	elif "name" in entity:
		return entity.name
	else:
		return "someone"

func get_item_name(item: Node) -> String:
	if not item:
		return "nothing"
	
	if "item_name" in item:
		return item.item_name
	elif "name" in item:
		return item.name
	else:
		return "something"

func show_message(text: String):
	if sensory_system:
		if sensory_system.has_method("display_message"):
			sensory_system.display_message(text)
		elif sensory_system.has_method("add_message"):
			sensory_system.add_message(text)
#endregion

#region NETWORK SYNCHRONIZATION
@rpc("any_peer", "call_local", "reliable")
func sync_pickup_item(item_network_id: String, picker_name: String):
	var item = get_item_by_network_id(item_network_id)
	if not item:
		return
	
	_play_pickup_audio()
	var item_name = get_item_name(item)
	show_message(picker_name + " picks up " + item_name + ".")

@rpc("any_peer", "call_local", "reliable")
func sync_drop_item(dropper_name: String, item_name: String, action: String):
	show_message(dropper_name + " " + action + " " + item_name + ".")

@rpc("any_peer", "call_local", "reliable")
func sync_use_item(use_data: Dictionary):
	var user_name = use_data.get("user_name", "Someone")
	var item_name = use_data.get("item_name", "something")
	show_message(user_name + " uses " + item_name + ".")

@rpc("any_peer", "call_local", "reliable")
func sync_throw_mode_toggle(toggle_data: Dictionary):
	var enable = toggle_data.get("enable", false)
	var user_name = toggle_data.get("user_name", "Someone")
	var item_name = toggle_data.get("item_name", "")
	
	if enable and item_name != "":
		show_message(user_name + " prepares to throw " + item_name + ".")
	else:
		show_message(user_name + " relaxes their throwing arm.")

@rpc("any_peer", "call_local", "reliable")
func sync_throw_trajectory(trajectory_data: Dictionary):
	var trajectory = trajectory_data.get("trajectory", [])
	var player_id = trajectory_data.get("player_id", "")
	
	if player_id != get_entity_name(controller):
		emit_signal("throw_trajectory_updated", trajectory)

@rpc("any_peer", "call_local", "reliable")
func sync_throw_item(thrower_name: String, item_name: String, world_position: Vector2):
	show_message(thrower_name + " throws " + item_name + "!")

@rpc("any_peer", "call_local", "reliable")
func sync_hand_swap(user_name: String, hand_name: String, item_name: String):
	if item_name != "":
		show_message(user_name + " switches to their " + hand_name + " hand (" + item_name + ").")
	else:
		show_message(user_name + " switches to their " + hand_name + " hand.")
#endregion
