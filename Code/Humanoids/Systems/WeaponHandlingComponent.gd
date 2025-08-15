extends Node
class_name WeaponHandlingComponent

#region SIGNALS
signal weapon_wielded(weapon: Node, hand_slot: int)
signal weapon_unwielded(weapon: Node, hand_slot: int)
signal weapon_fired(weapon: Node, target_position: Vector2)
signal weapon_reloaded(weapon: Node, magazine: Node)
signal magazine_ejected(weapon: Node, magazine: Node)
signal firing_mode_changed(weapon: Node, new_mode: int)
signal weapon_jammed(weapon: Node)
signal weapon_out_of_ammo(weapon: Node)
signal both_hands_occupied_changed(is_occupied: bool)
#endregion

#region EXPORTS
@export_group("Weapon Configuration")
@export var allow_one_handed_firing: bool = true
@export var auto_fire_enabled: bool = true
@export var require_skill_checks: bool = true

@export_group("Firing Mechanics")
@export var base_fire_delay: float = 0.5
@export var auto_fire_interval: float = 0.1
@export var max_firing_range: float = 50.0

@export_group("Accuracy Modifiers")
@export var one_handed_accuracy_penalties: Dictionary = {
	"pistol": 0.9,
	"rifle": 0.4,
	"shotgun": 0.5,
	"sniper": 0.2,
	"special": 0.6
}

@export_group("Skill Experience")
@export var firearms_experience_chance: float = 0.2
@export var specialist_experience_chance: float = 0.3
@export var reload_experience_chance: float = 0.15

@export_group("Audio Settings")
@export var wield_sound: String = "weapon_wield"
@export var unwield_sound: String = "weapon_unwield"
@export var empty_sound: String = "weapon_empty"
@export var chamber_sound: String = "weapon_chamber"
@export var default_volume: float = 0.4

@export_group("Input Actions")
@export var eject_magazine_action: String = "eject_mag"
@export var chamber_round_action: String = "chamber"
@export var toggle_safety_action: String = "safety"
#endregion

#region PROPERTIES
var controller: Node = null
var inventory_system: Node = null
var click_component: Node = null
var item_interaction_component: Node = null
var skill_component: Node = null
var sensory_system: Node = null
var audio_system: Node = null
var world: Node = null
var player_ui: Node = null

# Weapon state
var wielded_weapon: Node = null
var wielding_hand: int = -1
var is_both_hands_occupied: bool = false
var can_switch_hands: bool = true

# Firing state
var is_firing: bool = false
var auto_fire_timer: Timer = null
var last_fire_time: float = 0.0
var is_mouse_held: bool = false

# Cached values for performance
var _compatible_magazines_cache: Dictionary = {}
var _cache_clear_timer: float = 0.0
var _cache_lifetime: float = 3.0
#endregion

#region INITIALIZATION
func initialize(init_data: Dictionary):
	controller = init_data.get("controller")
	inventory_system = init_data.get("inventory_system")
	sensory_system = init_data.get("sensory_system")
	audio_system = init_data.get("audio_system")
	skill_component = init_data.get("skill_component")
	world = init_data.get("world")
	player_ui = init_data.get("player_ui")
	
	_connect_components()
	_setup_auto_fire_timer()
	_connect_inventory_signals()

func _ready():
	_check_input_actions()
	_reset_hand_state()

func _connect_components():
	if controller:
		click_component = controller.get_node_or_null("ClickComponent")
		item_interaction_component = controller.get_node_or_null("ItemInteractionComponent")

func _setup_auto_fire_timer():
	auto_fire_timer = Timer.new()
	auto_fire_timer.wait_time = auto_fire_interval
	auto_fire_timer.one_shot = true
	auto_fire_timer.timeout.connect(_on_auto_fire_timer_timeout)
	add_child(auto_fire_timer)

func _connect_inventory_signals():
	if inventory_system:
		if inventory_system.has_signal("item_equipped"):
			if not inventory_system.item_equipped.is_connected(_on_item_equipped):
				inventory_system.item_equipped.connect(_on_item_equipped)
		
		if inventory_system.has_signal("item_unequipped"):
			if not inventory_system.item_unequipped.is_connected(_on_item_unequipped):
				inventory_system.item_unequipped.connect(_on_item_unequipped)

func _reset_hand_state():
	is_both_hands_occupied = false
	can_switch_hands = true

func _check_input_actions():
	var undefined_actions = []
	var actions = [eject_magazine_action, chamber_round_action, toggle_safety_action]
	
	for action_name in actions:
		if not InputMap.has_action(action_name):
			undefined_actions.append(action_name)
	
	if undefined_actions.size() > 0:
		print("WeaponHandlingComponent: Missing input actions: " + str(undefined_actions))

func _process(delta: float):
	_cache_clear_timer += delta
	if _cache_clear_timer >= _cache_lifetime:
		_compatible_magazines_cache.clear()
		_cache_clear_timer = 0.0
#endregion

#region INPUT HANDLING
func _input(event: InputEvent):
	if not controller or not controller.is_local_player or controller.get_meta("is_npc", false):
		return
	
	if event is InputEventKey and event.pressed:
		_handle_weapon_input(event)
	elif event is InputEventMouseButton:
		_handle_mouse_input(event)

func _handle_weapon_input(event: InputEventKey):
	if not wielded_weapon:
		return
	
	match event.keycode:
		KEY_R when Input.is_action_pressed(eject_magazine_action):
			eject_magazine_to_floor(wielded_weapon)
		KEY_C when Input.is_action_pressed(chamber_round_action):
			chamber_round(wielded_weapon)
		KEY_V when Input.is_action_pressed(toggle_safety_action):
			toggle_weapon_safety(wielded_weapon)

func _handle_mouse_input(event: InputEventMouseButton):
	if _should_ui_handle_event(event):
		return
	
	var active_weapon = wielded_weapon
	if not active_weapon and inventory_system:
		active_weapon = inventory_system.get_active_item()
		if not _is_weapon(active_weapon):
			active_weapon = null
	
	if not active_weapon:
		return
	
	if event.shift_pressed or event.ctrl_pressed or event.alt_pressed:
		return
	
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_mouse_held = true
				_start_firing()
			else:
				is_mouse_held = false
				_stop_firing()

func _should_ui_handle_event(event: InputEvent) -> bool:
	if not event is InputEventMouseButton:
		return false
	
	var mouse_pos = event.position
	
	if player_ui and player_ui.has_method("is_position_in_ui_element"):
		return player_ui.is_position_in_ui_element(mouse_pos)
	
	var ui_groups = ["ui_elements", "ui_buttons", "hud_elements", "interface", "menu"]
	for group_name in ui_groups:
		var nodes = get_tree().get_nodes_in_group(group_name)
		for node in nodes:
			if node is Control and node.visible and node.mouse_filter != Control.MOUSE_FILTER_IGNORE:
				if node.get_global_rect().has_point(mouse_pos):
					return true
	
	return false
#endregion

#region WEAPON WIELDING
func try_wield_weapon(weapon: Node) -> bool:
	if not weapon or not _is_weapon(weapon):
		return false
	
	if require_skill_checks and not _check_weapon_skill_requirements(weapon):
		return false
	
	if wielded_weapon:
		unwield_weapon()
	
	var weapon_hand = _get_weapon_hand_slot(weapon)
	if weapon_hand == -1:
		return false
	
	wielded_weapon = weapon
	wielding_hand = weapon_hand
	is_both_hands_occupied = true
	can_switch_hands = false
	
	if weapon.has_method("set_wielded"):
		weapon.set_wielded(true)
	
	_play_wield_audio()
	
	emit_signal("weapon_wielded", weapon, weapon_hand)
	emit_signal("both_hands_occupied_changed", true)
	
	var weapon_name = _get_weapon_name(weapon)
	_show_message("You wield the " + weapon_name + " with both hands.")
	
	return true

func unwield_weapon() -> bool:
	if not wielded_weapon:
		return false
	
	var weapon = wielded_weapon
	var hand = wielding_hand
	
	_stop_firing()
	
	if weapon.has_method("set_wielded"):
		weapon.set_wielded(false)
	
	wielded_weapon = null
	wielding_hand = -1
	is_both_hands_occupied = false
	can_switch_hands = true
	
	_play_unwield_audio()
	
	emit_signal("weapon_unwielded", weapon, hand)
	emit_signal("both_hands_occupied_changed", false)
	
	var weapon_name = _get_weapon_name(weapon)
	_show_message("You lower the " + weapon_name + ".")
	
	return true

func _check_weapon_skill_requirements(weapon: Node) -> bool:
	if not weapon or not skill_component:
		return true
	
	if "required_skills" in weapon:
		for skill_req in weapon.required_skills:
			var skill_name = skill_req.get("skill", "")
			var required_level = skill_req.get("level", 0)
			
			if not skill_component.skillcheck(skill_name, required_level, false):
				_show_message("You lack the required " + skill_name + " skill to use this weapon!")
				return false
	
	var weapon_type = _get_weapon_type(weapon)
	
	match weapon_type:
		"firearm":
			if not skill_component.can_use_firearms():
				_show_message("You don't know how to properly handle firearms!")
				return false
		"specialist":
			if not skill_component.can_use_specialist_weapons():
				_show_message("This weapon is too complex for you to use!")
				return false
		"heavy":
			if not skill_component.is_skilled(skill_component.SKILL_SPEC_WEAPONS, skill_component.SKILL_LEVEL_TRAINED):
				_show_message("You need specialist weapons training to use heavy weapons!")
				return false
	
	return true

func _get_weapon_type(weapon: Node):
	if not weapon:
		return "basic"
	
	if "weapon_type" in weapon:
		return weapon.weapon_type
	
	if "is_specialist_weapon" in weapon and weapon.is_specialist_weapon:
		return "specialist"
	
	if "is_heavy_weapon" in weapon and weapon.is_heavy_weapon:
		return "heavy"
	
	if weapon.entity_type == "gun":
		return "firearm"
	
	return "basic"
#endregion

#region FIRING MECHANICS
func _start_firing():
	var weapon_to_fire = wielded_weapon
	if not weapon_to_fire and inventory_system:
		weapon_to_fire = inventory_system.get_active_item()
		if not _is_weapon(weapon_to_fire):
			return
	
	if not weapon_to_fire or not _can_fire_weapon(weapon_to_fire):
		return
	
	_fire_weapon_at_cursor()
	
	if auto_fire_enabled and _is_automatic_weapon(weapon_to_fire):
		is_firing = true
		_schedule_next_auto_fire()

func _stop_firing():
	is_firing = false
	if auto_fire_timer:
		auto_fire_timer.stop()

func _fire_weapon_at_cursor():
	var weapon_to_fire = wielded_weapon
	if not weapon_to_fire and inventory_system:
		weapon_to_fire = inventory_system.get_active_item()
		if not _is_weapon(weapon_to_fire):
			return false
	
	var current_time = Time.get_ticks_msec() / 1000.0
	var fire_delay = _get_weapon_fire_delay(weapon_to_fire)
	
	if current_time - last_fire_time < fire_delay:
		return false
	
	var mouse_world_pos = controller.get_global_mouse_position()
	var success = fire_weapon_at_position(weapon_to_fire, mouse_world_pos)
	
	if success:
		last_fire_time = current_time
		emit_signal("weapon_fired", weapon_to_fire, mouse_world_pos)
	
	return success

func fire_weapon_at_position(weapon: Node, target_position: Vector2) -> bool:
	if not weapon or not _can_fire_weapon(weapon):
		return false
	
	if not _weapon_has_ammo(weapon):
		_play_empty_click_sound()
		_show_message("*Click* - The weapon is empty!")
		emit_signal("weapon_out_of_ammo", weapon)
		return false
	
	if _is_weapon_jammed(weapon):
		_show_message("The weapon is jammed!")
		emit_signal("weapon_jammed", weapon)
		return false
	
	var is_wielded = _is_wielded_weapon(weapon)
	var accuracy_modifier = _get_firearms_accuracy_modifier()
	
	if not is_wielded and allow_one_handed_firing:
		accuracy_modifier *= _get_one_handed_accuracy_modifier(weapon)
		_handle_one_handed_firing_requirements(weapon)
	
	var success = _execute_weapon_firing(weapon, target_position)
	
	if success:
		_handle_successful_firing(weapon, is_wielded)
		_update_ammo_display(weapon)
		
		if controller.has_method("face_entity"):
			controller.face_entity(target_position)
	
	return success

func _execute_weapon_firing(weapon: Node, target_position: Vector2) -> bool:
	var success = false
	
	if weapon.has_method("fire_at_position"):
		success = weapon.fire_at_position(controller, target_position)
	elif weapon.has_method("fire_gun"):
		success = weapon.fire_gun(controller, target_position)
	elif weapon.has_method("use_weapon"):
		success = weapon.use_weapon(controller, target_position)
	
	return success

func _handle_one_handed_firing_requirements(weapon: Node):
	var original_wielding_requirement = false
	if "requires_wielding" in weapon:
		original_wielding_requirement = weapon.requires_wielding
		weapon.requires_wielding = false
	
	# Note: In a real implementation, you'd want to restore this after firing
	# This is a simplified version for demonstration

func _handle_successful_firing(weapon: Node, is_wielded: bool):
	if is_wielded:
		_grant_shooting_experience(weapon)
	else:
		_grant_one_handed_shooting_experience(weapon)
		_apply_one_handed_firing_effects(weapon)

func _apply_one_handed_firing_effects(weapon: Node):
	_apply_one_handed_camera_shake(weapon)
	_apply_one_handed_accuracy_penalty(weapon)
	_show_one_handed_recoil_message(weapon)

func _apply_one_handed_camera_shake(weapon: Node):
	var ammo_type = _get_weapon_ammo_type(weapon)
	var base_recoil = _get_weapon_recoil_amount(weapon)
	
	var shake_multipliers = {
		0: 0.5,  # PISTOL
		1: 4.0,  # RIFLE
		2: 3.5,  # SHOTGUN
		3: 5.0,  # SNIPER
		4: 3.0   # SPECIAL
	}
	
	var shake_multiplier = shake_multipliers.get(ammo_type, 2.0)
	var final_shake_intensity = base_recoil * shake_multiplier
	
	var camera = _find_player_camera()
	if camera and camera.has_method("add_trauma"):
		camera.add_trauma(final_shake_intensity * 0.3)
		
		if ammo_type in [1, 3]:  # RIFLE, SNIPER
			camera.shake_camera(final_shake_intensity * 0.2, 0.8)

func _apply_one_handed_accuracy_penalty(weapon: Node):
	if not weapon.has_method("add_scatter"):
		return
	
	var ammo_type = _get_weapon_ammo_type(weapon)
	var scatter_penalties = {
		0: 0.1,  # PISTOL
		1: 0.8,  # RIFLE
		2: 0.6,  # SHOTGUN
		3: 1.2,  # SNIPER
		4: 0.5   # SPECIAL
	}
	
	var scatter_penalty = scatter_penalties.get(ammo_type, 0.4)
	weapon.add_scatter(scatter_penalty)

func _show_one_handed_recoil_message(weapon: Node):
	var weapon_name = _get_weapon_name(weapon)
	var ammo_type = _get_weapon_ammo_type(weapon)
	
	var messages = {
		0: "The " + weapon_name + " jumps slightly in your hand.",     # PISTOL
		1: "The " + weapon_name + " kicks violently in your grip!",    # RIFLE
		2: "The " + weapon_name + " bucks hard against your hand!",    # SHOTGUN
		3: "The " + weapon_name + "'s massive recoil nearly tears it from your grip!", # SNIPER
		4: "The " + weapon_name + " recoils heavily in your hand!"     # SPECIAL
	}
	
	var message = messages.get(ammo_type, "The " + weapon_name + " kicks back in your hand.")
	_show_message(message)

func _schedule_next_auto_fire():
	if not is_firing or not wielded_weapon or not is_mouse_held:
		return
	
	var fire_delay = _get_weapon_fire_delay(wielded_weapon)
	auto_fire_timer.wait_time = fire_delay
	auto_fire_timer.start()

func _on_auto_fire_timer_timeout():
	if is_firing and is_mouse_held and wielded_weapon:
		_fire_weapon_at_cursor()
		_schedule_next_auto_fire()
#endregion

#region RELOADING MECHANICS
func try_reload_weapon(weapon: Node, magazine: Node) -> bool:
	if not weapon or not magazine or not _is_weapon(weapon):
		return false
	
	if not _is_magazine_compatible(weapon, magazine):
		_show_message("That magazine doesn't fit this weapon!")
		return false
	
	if require_skill_checks and not _check_reload_skill_requirements(weapon):
		return false
	
	var old_magazine = _extract_magazine(weapon)
	var user = get_parent()
	
	var reload_speed = _get_reload_speed_modifier()
	
	if weapon.has_method("insert_magazine"):
		var success = weapon.insert_magazine(magazine, user)
		if success:
			_handle_successful_reload(weapon, magazine, old_magazine)
			return true
	
	if old_magazine and weapon.has_method("insert_magazine"):
		weapon.insert_magazine(old_magazine)
	
	return false

func _handle_successful_reload(weapon: Node, magazine: Node, old_magazine: Node):
	var mag_slot = inventory_system._find_slot_with_item(magazine)
	if mag_slot != inventory_system.EquipSlot.NONE:
		inventory_system.unequip_item(mag_slot)
	
	var weapon_name = _get_weapon_name(weapon)
	_show_message("You reload the " + weapon_name + ".")
	inventory_system._hide_item_icon(magazine)
	emit_signal("weapon_reloaded", weapon, magazine)
	_update_ammo_display(weapon)
	
	_grant_reload_experience(weapon)

func _check_reload_skill_requirements(weapon: Node) -> bool:
	if not skill_component:
		return true
	
	var weapon_type = _get_weapon_type(weapon)
	
	match weapon_type:
		"specialist", "heavy":
			if not skill_component.is_skilled(skill_component.SKILL_SPEC_WEAPONS, skill_component.SKILL_LEVEL_NOVICE):
				_show_message("This weapon is too complex for you to reload!")
				return false
	
	return true

func eject_magazine_to_hand(weapon: Node) -> bool:
	if not weapon or not inventory_system:
		return false
	
	if not _is_weapon_in_inventory(weapon):
		return false
	
	var magazine = _extract_magazine(weapon)
	if not magazine or not is_instance_valid(magazine):
		_show_message("No magazine to eject!")
		return false
	
	var weapon_slot = inventory_system._find_slot_with_item(weapon)
	var target_hand = inventory_system.active_hand
	
	if weapon_slot == target_hand:
		target_hand = inventory_system.EquipSlot.LEFT_HAND if target_hand == inventory_system.EquipSlot.RIGHT_HAND else inventory_system.EquipSlot.RIGHT_HAND
	
	var target_item = inventory_system.get_item_in_slot(target_hand)
	
	if target_item:
		_show_message("Your hands are full!")
		_reinsert_magazine(weapon, magazine)
		return false
	
	if inventory_system.equip_item(magazine, target_hand):
		_handle_successful_magazine_ejection(weapon, magazine)
		return true
	else:
		_reinsert_magazine(weapon, magazine)
		_show_message("Failed to take the magazine!")
		return false

func eject_magazine_to_floor(weapon: Node) -> bool:
	if not weapon or not _is_weapon_in_inventory(weapon):
		return false
	
	var magazine = _extract_magazine(weapon)
	if not magazine or not is_instance_valid(magazine):
		_show_message("No magazine to eject!")
		return false
	
	_drop_magazine_to_floor(magazine)
	_handle_successful_magazine_ejection(weapon, magazine)
	
	return true

func _drop_magazine_to_floor(magazine: Node):
	var drop_position = controller.global_position + Vector2(0, 32)
	var world_node = controller.get_parent()
	if not world_node:
		world_node = get_tree().current_scene
	
	if magazine.get_parent():
		magazine.get_parent().remove_child(magazine)
	
	if world_node:
		world_node.add_child(magazine)
		magazine.global_position = drop_position
		
		if inventory_system and inventory_system.has_method("_show_item_icon"):
			inventory_system._show_item_icon(magazine)
		
		var icon_node = magazine.get_node_or_null("Icon")
		if icon_node:
			icon_node.visible = true

func _handle_successful_magazine_ejection(weapon: Node, magazine: Node):
	if audio_system:
		audio_system.play_positioned_sound("magazine_eject", controller.position, default_volume)
	
	var weapon_name = _get_weapon_name(weapon)
	var location = "onto the floor" if magazine.get_parent() != inventory_system else ""
	_show_message("You eject the magazine from the " + weapon_name + " " + location + ".")
	
	emit_signal("magazine_ejected", weapon, magazine)
	_update_ammo_display(weapon)

func _reinsert_magazine(weapon: Node, magazine: Node):
	if weapon.has_method("insert_magazine"):
		weapon.insert_magazine(magazine, controller)
	else:
		weapon.current_magazine = magazine
		if weapon.has_method("update_icon_state"):
			weapon.update_icon_state()

func _extract_magazine(weapon: Node) -> Node:
	if not weapon or not _is_weapon(weapon):
		return null
	
	var magazine = null
	
	if "current_magazine" in weapon and weapon.current_magazine:
		magazine = weapon.current_magazine
		weapon.current_magazine = null
		
		if weapon.has_method("update_icon_state"):
			weapon.update_icon_state()
		
		if weapon.has_signal("magazine_ejected"):
			weapon.emit_signal("magazine_ejected", magazine)
		if weapon.has_signal("ammo_changed"):
			weapon.emit_signal("ammo_changed", weapon.get_current_ammo_count(), weapon.get_max_ammo_count())
	
	return magazine
#endregion

#region WEAPON OPERATIONS
func chamber_round(weapon: Node) -> bool:
	if not weapon or not _is_weapon(weapon) or not _is_weapon_in_inventory(weapon):
		return false
	
	var weapon_type = _get_weapon_type(weapon)
	if weapon_type in ["specialist", "heavy"]:
		if not skill_component or not skill_component.is_skilled(skill_component.SKILL_SPEC_WEAPONS, skill_component.SKILL_LEVEL_NOVICE):
			_show_message("You don't know how to properly chamber rounds in this weapon!")
			return false
	
	if weapon.has_method("chamber_next_round"):
		var success = weapon.chamber_next_round()
		if success:
			_play_chamber_audio()
			
			var weapon_name = _get_weapon_name(weapon)
			_show_message("You chamber a round in the " + weapon_name + ".")
			
			_update_ammo_display(weapon)
			
			if skill_component and randf() < 0.05:
				skill_component.increment_skill(skill_component.SKILL_FIREARMS, 1, 4)
			
			return true
		else:
			_show_message("No rounds to chamber!")
	
	return false

func cycle_firing_mode(weapon: Node) -> bool:
	if not weapon or not _is_weapon(weapon):
		return false
	
	if weapon.has_method("cycle_fire_mode"):
		var old_mode = _get_weapon_fire_mode(weapon)
		var user = get_parent()
		var success = weapon.cycle_fire_mode(user)
		
		if success:
			var new_mode = _get_weapon_fire_mode(weapon)
			var mode_name = _get_fire_mode_name(new_mode)
			
			if audio_system:
				audio_system.play_positioned_sound("weapon_mode", controller.position, 0.3)
			
			var weapon_name = _get_weapon_name(weapon)
			_show_message("You switch the " + weapon_name + " to " + mode_name + " mode.")
			
			emit_signal("firing_mode_changed", weapon, new_mode)
			return true
	
	return false

func toggle_weapon_safety(weapon: Node) -> bool:
	if not weapon or not _is_weapon(weapon):
		return false
	
	if weapon.has_method("toggle_safety"):
		var user = get_parent()
		var success = weapon.toggle_safety(user)
		if success:
			var safety_state = _get_weapon_safety_state(weapon)
			var state_text = "on" if safety_state else "off"
			
			if audio_system:
				audio_system.play_positioned_sound("weapon_safety", controller.position, 0.3)
			
			var weapon_name = _get_weapon_name(weapon)
			_show_message("You turn the safety " + state_text + " on the " + weapon_name + ".")
			
			return true
	
	return false
#endregion

#region WEAPON VALIDATION
func _can_fire_weapon(weapon: Node) -> bool:
	if not weapon or not _is_weapon(weapon):
		return false
	
	if _get_weapon_safety_state(weapon):
		return false
	
	if not _weapon_has_ammo(weapon):
		return false
	
	if _is_weapon_jammed(weapon):
		return false
	
	if not _is_wielded_weapon(weapon) and not _can_fire_one_handed(weapon):
		return false
	
	return true

func _can_fire_one_handed(weapon: Node) -> bool:
	if not weapon or not allow_one_handed_firing:
		return false
	
	if "w_class" in weapon and weapon.w_class > 5:
		return false
	
	return true

func _is_wielded_weapon(weapon: Node) -> bool:
	return wielded_weapon == weapon

func _weapon_has_ammo(weapon: Node) -> bool:
	if not weapon:
		return false
	
	if weapon.has_method("has_ammo"):
		return weapon.has_ammo()
	elif weapon.has_method("get_current_ammo_count"):
		return weapon.get_current_ammo_count() > 0
	elif "chambered_bullet" in weapon and weapon.chambered_bullet:
		return true
	
	return false

func _is_weapon_jammed(weapon: Node) -> bool:
	if not weapon:
		return false
	
	if weapon.has_method("is_jammed"):
		return weapon.is_jammed()
	elif "is_jammed" in weapon:
		return weapon.is_jammed
	
	if skill_component and weapon.has_method("get_jam_chance"):
		var base_jam_chance = weapon.get_jam_chance()
		var skill_level = skill_component.get_skill_level(skill_component.SKILL_FIREARMS)
		var skill_modifier = max(0.1, 1.0 - (skill_level * 0.15))
		
		var final_jam_chance = base_jam_chance * skill_modifier
		if randf() < final_jam_chance:
			if weapon.has_method("set_jammed"):
				weapon.set_jammed(true)
			elif "is_jammed" in weapon:
				weapon.is_jammed = true
			return true
	
	return false

func _is_weapon_in_inventory(weapon: Node) -> bool:
	if not weapon or not inventory_system:
		return false
	
	var slot = inventory_system._find_slot_with_item(weapon)
	return slot != inventory_system.EquipSlot.NONE
#endregion

#region WEAPON PROPERTIES
func _get_weapon_safety_state(weapon: Node) -> bool:
	if not weapon:
		return true
	
	if weapon.has_method("get_safety_state"):
		return weapon.get_safety_state()
	elif "safety_state" in weapon:
		return weapon.safety_state
	elif "current_safety_state" in weapon:
		return weapon.current_safety_state == weapon.SafetyState.ON if "SafetyState" in weapon else false
	
	return false

func _is_automatic_weapon(weapon: Node) -> bool:
	if not weapon:
		return false
	
	var fire_mode = _get_weapon_fire_mode(weapon)
	if weapon.has_method("get_script") and weapon.get_script():
		var script = weapon.get_script()
		if "FireMode" in weapon and "AUTOMATIC" in weapon.FireMode:
			return fire_mode == weapon.FireMode.AUTOMATIC
	
	return false

func _get_weapon_fire_mode(weapon: Node) -> int:
	if not weapon:
		return 0
	
	if weapon.has_method("get_fire_mode"):
		return weapon.get_fire_mode()
	elif "current_fire_mode" in weapon:
		return weapon.current_fire_mode
	elif "fire_mode" in weapon:
		return weapon.fire_mode
	
	return 0

func _get_weapon_fire_delay(weapon: Node) -> float:
	if not weapon:
		return base_fire_delay
	
	var delay = base_fire_delay
	if weapon.has_method("get_fire_delay"):
		delay = weapon.get_fire_delay()
	elif "fire_delay" in weapon:
		delay = weapon.fire_delay
	elif "fire_rate" in weapon and weapon.fire_rate > 0:
		delay = 1.0 / weapon.fire_rate
	
	if skill_component:
		var skill_level = skill_component.get_skill_level(skill_component.SKILL_FIREARMS)
		var speed_modifier = 1.0 + (skill_level * 0.1)
		delay /= speed_modifier
	
	return delay

func _get_weapon_ammo_type(weapon: Node) -> int:
	if not weapon:
		return 0  # Default to pistol ammo
	
	if "accepted_ammo_types" in weapon and weapon.accepted_ammo_types.size() > 0:
		return weapon.accepted_ammo_types[0]
	
	var weapon_name = _get_weapon_name(weapon).to_lower()
	if "rifle" in weapon_name or "assault" in weapon_name:
		return 1  # RIFLE
	elif "shotgun" in weapon_name:
		return 2  # SHOTGUN
	elif "sniper" in weapon_name:
		return 3  # SNIPER
	else:
		return 0  # PISTOL

func _get_weapon_recoil_amount(weapon: Node) -> float:
	if not weapon:
		return 1.0
	
	if "recoil_amount" in weapon:
		return weapon.recoil_amount
	elif "force" in weapon:
		return weapon.force * 0.1
	
	return 1.0

func _get_one_handed_accuracy_modifier(weapon: Node) -> float:
	if not weapon:
		return 1.0
	
	var ammo_type = _get_weapon_ammo_type(weapon)
	var ammo_type_names = ["pistol", "rifle", "shotgun", "sniper", "special"]
	var type_name = ammo_type_names[ammo_type] if ammo_type < ammo_type_names.size() else "pistol"
	
	return one_handed_accuracy_penalties.get(type_name, 0.7)

func _get_fire_mode_name(mode: int) -> String:
	match mode:
		0:
			return "single-shot"
		1:
			return "semi-automatic"
		2:
			return "burst"
		3:
			return "full-automatic"
		_:
			return "unknown"
#endregion

#region MAGAZINE COMPATIBILITY
func _is_magazine_compatible(weapon: Node, magazine: Node) -> bool:
	if not weapon or not magazine:
		return false
	
	var cache_key = str(weapon.get_instance_id()) + "_" + str(magazine.get_instance_id())
	if _compatible_magazines_cache.has(cache_key):
		return _compatible_magazines_cache[cache_key]
	
	var compatible = false
	
	if weapon.has_method("can_accept_magazine"):
		compatible = weapon.can_accept_magazine(magazine)
	elif weapon.has_method("is_magazine_compatible"):
		compatible = weapon.is_magazine_compatible(magazine)
	elif "accepted_ammo_types" in weapon and "ammo_type" in magazine:
		compatible = magazine.ammo_type in weapon.accepted_ammo_types
	else:
		compatible = true
	
	_compatible_magazines_cache[cache_key] = compatible
	return compatible

func find_compatible_magazines(weapon: Node) -> Array:
	var compatible_mags = []
	
	if not inventory_system:
		return compatible_mags
	
	for slot in inventory_system.equipped_items:
		var item = inventory_system.equipped_items[slot]
		if item and _is_magazine_compatible(weapon, item):
			compatible_mags.append(item)
	
	return compatible_mags
#endregion

#region EXPERIENCE GRANTING
func _get_firearms_accuracy_modifier() -> float:
	if not skill_component:
		return 1.0
	
	return skill_component.get_firearms_skill_modifier()

func _grant_shooting_experience(weapon: Node):
	if not skill_component or not skill_component.allow_skill_gain:
		return
	
	var weapon_type = _get_weapon_type(weapon)
	
	match weapon_type:
		"firearm":
			if randf() < firearms_experience_chance:
				skill_component.increment_skill(skill_component.SKILL_FIREARMS, 1, 4)
		"specialist", "heavy":
			if randf() < specialist_experience_chance:
				skill_component.increment_skill(skill_component.SKILL_SPEC_WEAPONS, 1, 3)
			if randf() < 0.1:
				skill_component.increment_skill(skill_component.SKILL_FIREARMS, 1, 4)

func _grant_one_handed_shooting_experience(weapon: Node):
	if not skill_component or not skill_component.allow_skill_gain:
		return
	
	var weapon_type = _get_weapon_type(weapon)
	
	match weapon_type:
		"firearm":
			if randf() < firearms_experience_chance * 0.5:
				skill_component.increment_skill(skill_component.SKILL_FIREARMS, 1, 2)
		"specialist", "heavy":
			if randf() < specialist_experience_chance * 0.5:
				skill_component.increment_skill(skill_component.SKILL_SPEC_WEAPONS, 1, 1)

func _grant_reload_experience(weapon: Node):
	if not skill_component or not skill_component.allow_skill_gain:
		return
	
	var weapon_type = _get_weapon_type(weapon)
	
	match weapon_type:
		"firearm":
			if randf() < reload_experience_chance:
				skill_component.increment_skill(skill_component.SKILL_FIREARMS, 1, 4)
		"specialist", "heavy":
			if randf() < reload_experience_chance * 1.5:
				skill_component.increment_skill(skill_component.SKILL_SPEC_WEAPONS, 1, 3)

func _get_reload_speed_modifier() -> float:
	if not skill_component:
		return 1.0
	
	var firearms_level = skill_component.get_skill_level(skill_component.SKILL_FIREARMS)
	return 1.0 + (firearms_level * 0.15)
#endregion

#region UTILITY FUNCTIONS
func _is_weapon(item: Node) -> bool:
	return item and item.entity_type == "gun"

func _get_weapon_hand_slot(weapon: Node) -> int:
	if not inventory_system:
		return -1
	
	var left_hand_slot = inventory_system.EquipSlot.LEFT_HAND
	var right_hand_slot = inventory_system.EquipSlot.RIGHT_HAND
	
	if inventory_system.get_item_in_slot(left_hand_slot) == weapon:
		return left_hand_slot
	elif inventory_system.get_item_in_slot(right_hand_slot) == weapon:
		return right_hand_slot
	
	return -1

func _get_weapon_name(weapon: Node) -> String:
	if not weapon:
		return "weapon"
	
	if "item_name" in weapon and weapon.item_name != "":
		return weapon.item_name
	elif "obj_name" in weapon and weapon.obj_name != "":
		return weapon.obj_name
	elif "name" in weapon:
		return weapon.name
	
	return "weapon"

func _find_player_camera():
	if controller and controller.has_method("get_camera"):
		return controller.get_camera()
	
	if controller:
		var camera = controller.get_node_or_null("Camera2D")
		if camera:
			return camera
		
		camera = controller.get_node_or_null("PlayerCamera")
		if camera:
			return camera
	
	if controller and controller.get_parent():
		var camera = controller.get_parent().get_node_or_null("Camera2D")
		if camera:
			return camera
		
		camera = controller.get_parent().get_node_or_null("PlayerCamera")
		if camera:
			return camera
	
	var cameras = controller.get_tree().get_nodes_in_group("player_camera")
	if cameras.size() > 0:
		return cameras[0]
	
	return null

func _show_message(text: String):
	if sensory_system:
		if sensory_system.has_method("display_message"):
			sensory_system.display_message(text)
		elif sensory_system.has_method("add_message"):
			sensory_system.add_message(text)

func _update_ammo_display(weapon: Node):
	if weapon.has_method("get_current_ammo_count") and weapon.has_method("get_max_ammo_count"):
		var current = weapon.get_current_ammo_count()
		var max_ammo = weapon.get_max_ammo_count()
		emit_signal("ammo_count_updated", weapon, current, max_ammo)

func _play_wield_audio():
	if audio_system:
		audio_system.play_positioned_sound(wield_sound, controller.position, default_volume)

func _play_unwield_audio():
	if audio_system:
		audio_system.play_positioned_sound(unwield_sound, controller.position, 0.3)

func _play_empty_click_sound():
	if audio_system:
		audio_system.play_positioned_sound(empty_sound, controller.position, default_volume)

func _play_chamber_audio():
	if audio_system:
		audio_system.play_positioned_sound(chamber_sound, controller.position, default_volume)
#endregion

#region PUBLIC INTERFACE
func handle_weapon_alt_click(weapon: Node) -> bool:
	if not _is_weapon(weapon):
		return false
	
	return cycle_firing_mode(weapon)

func handle_weapon_ctrl_click(weapon: Node) -> bool:
	if not _is_weapon(weapon):
		return false
	
	return eject_magazine_to_floor(weapon)

func handle_weapon_click_with_magazine(weapon: Node, magazine: Node) -> bool:
	if not _is_weapon(weapon) or not magazine:
		return false
	
	return try_reload_weapon(weapon, magazine)

func handle_weapon_click_with_empty_hand(weapon: Node) -> bool:
	if not _is_weapon(weapon):
		return false
	
	return eject_magazine_to_hand(weapon)

func handle_weapon_use(weapon: Node) -> bool:
	if not _is_weapon(weapon):
		return false
	
	if wielded_weapon == weapon:
		return unwield_weapon()
	else:
		return try_wield_weapon(weapon)

func is_wielding_weapon() -> bool:
	return wielded_weapon != null

func get_wielded_weapon() -> Node:
	return wielded_weapon

func is_hands_occupied() -> bool:
	return is_both_hands_occupied

func can_switch_hands_currently() -> bool:
	return can_switch_hands

func force_unwield():
	if wielded_weapon:
		unwield_weapon()
#endregion

#region EVENT HANDLERS
func _on_item_equipped(item: Node, slot: int):
	if _is_weapon(item) and _is_hand_slot(slot):
		pass

func _on_item_unequipped(item: Node, slot: int):
	if item == wielded_weapon:
		unwield_weapon()

func _is_hand_slot(slot: int) -> bool:
	if not inventory_system:
		return false
	
	return slot == inventory_system.EquipSlot.LEFT_HAND or slot == inventory_system.EquipSlot.RIGHT_HAND
#endregion
