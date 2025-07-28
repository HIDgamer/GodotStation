extends Node
class_name WeaponHandlingComponent

# Signals for weapon events
signal weapon_wielded(weapon: Node, hand_slot: int)
signal weapon_unwielded(weapon: Node, hand_slot: int)
signal weapon_fired(weapon: Node, target_position: Vector2)
signal weapon_reloaded(weapon: Node, magazine: Node)
signal magazine_ejected(weapon: Node, magazine: Node)
signal firing_mode_changed(weapon: Node, new_mode: int)
signal weapon_jammed(weapon: Node)
signal weapon_out_of_ammo(weapon: Node)
signal both_hands_occupied_changed(is_occupied: bool)

# Component references
var controller: Node = null
var inventory_system: Node = null
var click_component: Node = null
var item_interaction_component: Node = null
var sensory_system: Node = null
var audio_system: Node = null
var world: Node = null
var player_ui: Node = null

# Wielding state
var wielded_weapon: Node = null
var wielding_hand: int = -1
var is_both_hands_occupied: bool = false
var can_switch_hands: bool = true

# Firing state
var is_firing: bool = false
var auto_fire_timer: Timer = null
var last_fire_time: float = 0.0
var is_mouse_held: bool = false

# Input mapping
const INPUT_ACTIONS = {
	"eject_magazine": "eject_mag",
	"chamber_round": "chamber",
	"toggle_safety": "safety",
	"quick_reload": "quick_reload"
}

func initialize(init_data: Dictionary):
	controller = init_data.get("controller")
	inventory_system = init_data.get("inventory_system")
	sensory_system = init_data.get("sensory_system")
	audio_system = init_data.get("audio_system")
	world = init_data.get("world")
	player_ui = init_data.get("player_ui")
	
	# Get component references
	if controller:
		click_component = controller.get_node_or_null("ClickComponent")
		item_interaction_component = controller.get_node_or_null("ItemInteractionComponent")
	
	setup_auto_fire_timer()
	connect_inventory_signals()

func _ready():
	# Verify input actions are defined
	check_input_actions()
	
	# Ensure initial state is correct
	is_both_hands_occupied = false
	can_switch_hands = true
	print("WeaponHandlingComponent: Ready - initial state: hands occupied = false")

func setup_auto_fire_timer():
	auto_fire_timer = Timer.new()
	auto_fire_timer.wait_time = 0.1
	auto_fire_timer.one_shot = true
	auto_fire_timer.timeout.connect(_on_auto_fire_timer_timeout)
	add_child(auto_fire_timer)

func check_input_actions():
	var undefined_actions = []
	
	for action_type in INPUT_ACTIONS:
		var action_name = INPUT_ACTIONS[action_type]
		if not InputMap.has_action(action_name):
			undefined_actions.append(action_name)
	
	if undefined_actions.size() > 0:
		print("WeaponHandlingComponent: Missing input actions: " + str(undefined_actions))

func connect_inventory_signals():
	if inventory_system:
		if inventory_system.has_signal("item_equipped"):
			if not inventory_system.item_equipped.is_connected(_on_item_equipped):
				inventory_system.item_equipped.connect(_on_item_equipped)
		
		if inventory_system.has_signal("item_unequipped"):
			if not inventory_system.item_unequipped.is_connected(_on_item_unequipped):
				inventory_system.item_unequipped.connect(_on_item_unequipped)

func _input(event: InputEvent):
	if not controller or not controller.is_local_player:
		return
	
	if event is InputEventKey and event.pressed:
		handle_weapon_input(event)
	elif event is InputEventMouseButton:
		handle_mouse_input(event)

func handle_weapon_input(event: InputEventKey):
	if not wielded_weapon:
		return
	
	match event.keycode:
		KEY_R when Input.is_action_pressed(INPUT_ACTIONS["eject_magazine"]):
			eject_magazine_to_floor(wielded_weapon)
		KEY_C when Input.is_action_pressed(INPUT_ACTIONS["chamber_round"]):
			chamber_round(wielded_weapon)
		KEY_V when Input.is_action_pressed(INPUT_ACTIONS["toggle_safety"]):
			toggle_weapon_safety(wielded_weapon)

func handle_mouse_input(event: InputEventMouseButton):
	if not wielded_weapon:
		return
	
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_mouse_held = true
				start_firing()
			else:
				is_mouse_held = false
				stop_firing()

# Core weapon wielding system
func try_wield_weapon(weapon: Node) -> bool:
	if not weapon or not is_weapon(weapon):
		return false
	
	if wielded_weapon:
		unwield_weapon()
	
	var weapon_hand = get_weapon_hand_slot(weapon)
	if weapon_hand == -1:
		return false
	
	wielded_weapon = weapon
	wielding_hand = weapon_hand
	is_both_hands_occupied = true
	can_switch_hands = false
	
	print("WeaponHandlingComponent: Wielding weapon, hands occupied = true")
	
	# Update weapon state
	if weapon.has_method("set_wielded"):
		weapon.set_wielded(true)
	
	# Play wielding sound
	if audio_system:
		audio_system.play_positioned_sound("weapon_wield", controller.position, 0.4)
	
	# Update UI
	emit_signal("weapon_wielded", weapon, weapon_hand)
	emit_signal("both_hands_occupied_changed", true)
	
	var weapon_name = get_weapon_name(weapon)
	show_message("You wield the " + weapon_name + " with both hands.")
	
	return true

func unwield_weapon() -> bool:
	if not wielded_weapon:
		return false
	
	var weapon = wielded_weapon
	var hand = wielding_hand
	
	# Stop any ongoing firing
	stop_firing()
	
	# Update weapon state
	if weapon.has_method("set_wielded"):
		weapon.set_wielded(false)
	
	# Reset wielding state
	wielded_weapon = null
	wielding_hand = -1
	is_both_hands_occupied = false
	can_switch_hands = true
	
	print("WeaponHandlingComponent: Unwielding weapon, hands occupied = false")
	
	# Play unwielding sound
	if audio_system:
		audio_system.play_positioned_sound("weapon_unwield", controller.position, 0.3)
	
	# Update UI
	emit_signal("weapon_unwielded", weapon, hand)
	emit_signal("both_hands_occupied_changed", false)
	
	var weapon_name = get_weapon_name(weapon)
	show_message("You lower the " + weapon_name + ".")
	
	return true

# Firing system
func start_firing():
	if not wielded_weapon or not can_fire_weapon(wielded_weapon):
		return
	
	# Fire first shot immediately
	fire_weapon_at_cursor()
	
	# Set up auto fire if weapon supports it
	if is_automatic_weapon(wielded_weapon):
		is_firing = true
		schedule_next_auto_fire()

func stop_firing():
	is_firing = false
	if auto_fire_timer:
		auto_fire_timer.stop()

func fire_weapon_at_cursor():
	if not wielded_weapon:
		return false
	
	var current_time = Time.get_ticks_msec() / 1000.0
	var fire_delay = get_weapon_fire_delay(wielded_weapon)
	
	if current_time - last_fire_time < fire_delay:
		return false
	
	var mouse_world_pos = controller.get_global_mouse_position()
	var success = fire_weapon_at_position(wielded_weapon, mouse_world_pos)
	
	if success:
		last_fire_time = current_time
		emit_signal("weapon_fired", wielded_weapon, mouse_world_pos)
	
	return success

func fire_weapon_at_position(weapon: Node, target_position: Vector2) -> bool:
	if not weapon or not can_fire_weapon(weapon):
		return false
	
	# Check if weapon has ammo
	if not weapon_has_ammo(weapon):
		play_empty_click_sound()
		show_message("*Click* - The weapon is empty!")
		emit_signal("weapon_out_of_ammo", weapon)
		return false
	
	# Check if weapon is jammed
	if is_weapon_jammed(weapon):
		show_message("The weapon is jammed!")
		emit_signal("weapon_jammed", weapon)
		return false
	
	# Fire the weapon
	var success = false
	if weapon.has_method("fire_at_position"):
		success = weapon.fire_at_position(controller, target_position)
	elif weapon.has_method("fire_gun"):
		success = weapon.fire_gun(controller, target_position)
	elif weapon.has_method("use_weapon"):
		success = weapon.use_weapon(controller, target_position)
	
	if success:
		# Update ammo count in UI
		update_ammo_display(weapon)
		
		# Face towards target
		if controller.has_method("face_entity"):
			controller.face_entity(target_position)
	
	return success

func schedule_next_auto_fire():
	if not is_firing or not wielded_weapon or not is_mouse_held:
		return
	
	var fire_delay = get_weapon_fire_delay(wielded_weapon)
	auto_fire_timer.wait_time = fire_delay
	auto_fire_timer.start()

func _on_auto_fire_timer_timeout():
	if is_firing and is_mouse_held and wielded_weapon:
		fire_weapon_at_cursor()
		schedule_next_auto_fire()

# Magazine and reloading system
func try_reload_weapon(weapon: Node, magazine: Node) -> bool:
	if not weapon or not magazine or not is_weapon(weapon):
		return false
	
	if not is_magazine_compatible(weapon, magazine):
		show_message("That magazine doesn't fit this weapon!")
		return false
	
	# Remove current magazine if present
	var old_magazine = extract_magazine(weapon)
	var user = get_parent()
	
	# Insert new magazine
	if weapon.has_method("insert_magazine"):
		var success = weapon.insert_magazine(magazine, user)
		if success:
			# Remove magazine from inventory
			var mag_slot = inventory_system.find_slot_with_item(magazine)
			if mag_slot != inventory_system.EquipSlot.NONE:
				inventory_system.unequip_item(mag_slot)
			
			# Play reload sound
			if audio_system:
				audio_system.play_positioned_sound("weapon_reload", controller.position, 0.5)
			
			var weapon_name = get_weapon_name(weapon)
			show_message("You reload the " + weapon_name + ".")
			inventory_system.hide_item_icon(magazine)
			emit_signal("weapon_reloaded", weapon, magazine)
			update_ammo_display(weapon)
			
			return true
	
	# Restore old magazine if reload failed
	if old_magazine and weapon.has_method("insert_magazine"):
		weapon.insert_magazine(old_magazine)
	
	return false

func extract_magazine(weapon: Node):
	if not weapon or not is_weapon(weapon):
		return null
	
	var user = get_parent()
	var magazine = null
	if weapon.has_method("eject_magazine"):
		magazine = weapon.eject_magazine(user)
	
	return magazine

func eject_magazine_to_hand(weapon: Node) -> bool:
	if not weapon or not inventory_system:
		return false
	
	var magazine = extract_magazine(weapon)
	if not magazine:
		show_message("No magazine to eject!")
		return false
	
	# Try to put magazine in active hand
	var active_hand = inventory_system.active_hand
	var active_item = inventory_system.get_active_item()
	
	if active_item:
		show_message("Your hands are full!")
		# Put magazine back
		if weapon.has_method("insert_magazine"):
			weapon.insert_magazine(magazine)
		return false
	
	# Equip magazine to active hand
	if inventory_system.equip_item(magazine, active_hand):
		# Play eject sound
		if audio_system:
			audio_system.play_positioned_sound("magazine_eject", controller.position, 0.4)
		
		var weapon_name = get_weapon_name(weapon)
		show_message("You eject the magazine from the " + weapon_name + ".")
		
		emit_signal("magazine_ejected", weapon, magazine)
		update_ammo_display(weapon)
		
		return true
	
	return false

func eject_magazine_to_floor(weapon: Node) -> bool:
	if not weapon:
		return false
	
	var magazine = extract_magazine(weapon)
	if not magazine:
		show_message("No magazine to eject!")
		return false
	
	# Drop magazine at player's feet
	var drop_position = controller.global_position + Vector2(0, 16)
	
	# Add magazine to world
	var world_node = controller.get_parent()
	if world_node:
		world_node.add_child(magazine)
		magazine.global_position = drop_position
	
	# Play eject sound
	if audio_system:
		audio_system.play_positioned_sound("magazine_eject", controller.position, 0.4)
	
	var weapon_name = get_weapon_name(weapon)
	show_message("You eject the magazine from the " + weapon_name + " onto the floor.")
	
	emit_signal("magazine_ejected", weapon, magazine)
	update_ammo_display(weapon)
	
	return true

func chamber_round(weapon: Node) -> bool:
	if not weapon or not is_weapon(weapon):
		return false
	
	if weapon.has_method("chamber_next_round"):
		var success = weapon.chamber_next_round()
		if success:
			# Play chambering sound
			if audio_system:
				audio_system.play_positioned_sound("weapon_chamber", controller.position, 0.4)
			
			var weapon_name = get_weapon_name(weapon)
			show_message("You chamber a round in the " + weapon_name + ".")
			
			update_ammo_display(weapon)
			return true
		else:
			show_message("No rounds to chamber!")
	
	return false

# Weapon mode switching
func cycle_firing_mode(weapon: Node) -> bool:
	if not weapon or not is_weapon(weapon):
		return false
	
	if weapon.has_method("cycle_fire_mode"):
		var old_mode = get_weapon_fire_mode(weapon)
		var success = weapon.cycle_fire_mode()
		
		if success:
			var new_mode = get_weapon_fire_mode(weapon)
			var mode_name = get_fire_mode_name(new_mode)
			
			# Play mode switch sound
			if audio_system:
				audio_system.play_positioned_sound("weapon_mode", controller.position, 0.3)
			
			var weapon_name = get_weapon_name(weapon)
			show_message("You switch the " + weapon_name + " to " + mode_name + " mode.")
			
			emit_signal("firing_mode_changed", weapon, new_mode)
			return true
	
	return false

func toggle_weapon_safety(weapon: Node) -> bool:
	if not weapon or not is_weapon(weapon):
		return false
	
	if weapon.has_method("toggle_safety"):
		var success = weapon.toggle_safety()
		if success:
			var safety_state = get_weapon_safety_state(weapon)
			var state_text = "on" if safety_state else "off"
			
			# Play safety sound
			if audio_system:
				audio_system.play_positioned_sound("weapon_safety", controller.position, 0.3)
			
			var weapon_name = get_weapon_name(weapon)
			show_message("You turn the safety " + state_text + " on the " + weapon_name + ".")
			
			return true
	
	return false

# UI interaction handlers
func handle_weapon_alt_click(weapon: Node) -> bool:
	if not is_weapon(weapon):
		return false
	
	# Alt-click to cycle firing mode
	return cycle_firing_mode(weapon)

func handle_weapon_ctrl_click(weapon: Node) -> bool:
	if not is_weapon(weapon):
		return false
	
	# Ctrl-click to eject magazine to floor
	return eject_magazine_to_floor(weapon)

func handle_weapon_click_with_magazine(weapon: Node, magazine: Node) -> bool:
	if not is_weapon(weapon) or not magazine:
		return false
	
	# Click weapon with magazine to reload
	return try_reload_weapon(weapon, magazine)

func handle_weapon_click_with_empty_hand(weapon: Node) -> bool:
	if not is_weapon(weapon):
		return false
	
	# Click weapon with empty hand to extract magazine
	return eject_magazine_to_hand(weapon)

func handle_weapon_use(weapon: Node) -> bool:
	if not is_weapon(weapon):
		return false
	
	# Using weapon toggles wielding
	if wielded_weapon == weapon:
		return unwield_weapon()
	else:
		return try_wield_weapon(weapon)

# State checking functions
func can_fire_weapon(weapon: Node) -> bool:
	if not weapon or not is_weapon(weapon):
		return false
	
	if get_weapon_safety_state(weapon):
		return false
	
	if not weapon_has_ammo(weapon):
		return false
	
	if is_weapon_jammed(weapon):
		return false
	
	return true

func weapon_has_ammo(weapon: Node) -> bool:
	if not weapon:
		return false
	
	if weapon.has_method("has_ammo"):
		return weapon.has_ammo()
	elif weapon.has_method("get_current_ammo_count"):
		return weapon.get_current_ammo_count() > 0
	elif "chambered_bullet" in weapon and weapon.chambered_bullet:
		return true
	
	return false

func is_weapon_jammed(weapon: Node) -> bool:
	if not weapon:
		return false
	
	if weapon.has_method("is_jammed"):
		return weapon.is_jammed()
	elif "is_jammed" in weapon:
		return weapon.is_jammed
	
	return false

func get_weapon_safety_state(weapon: Node) -> bool:
	if not weapon:
		return true
	
	if weapon.has_method("get_safety_state"):
		return weapon.get_safety_state()
	elif "safety_state" in weapon:
		return weapon.safety_state
	elif "current_safety_state" in weapon:
		return weapon.current_safety_state == weapon.SafetyState.ON if "SafetyState" in weapon else false
	
	return false

func is_automatic_weapon(weapon: Node) -> bool:
	if not weapon:
		return false
	
	var fire_mode = get_weapon_fire_mode(weapon)
	if weapon.has_method("get_script") and weapon.get_script():
		var script = weapon.get_script()
		if "FireMode" in weapon and "FULLAUTO" in weapon.FireMode:
			return fire_mode == weapon.FireMode.FULLAUTO
	
	return false

func get_weapon_fire_mode(weapon: Node) -> int:
	if not weapon:
		return 0
	
	if weapon.has_method("get_fire_mode"):
		return weapon.get_fire_mode()
	elif "current_fire_mode" in weapon:
		return weapon.current_fire_mode
	elif "fire_mode" in weapon:
		return weapon.fire_mode
	
	return 0

func get_weapon_fire_delay(weapon: Node) -> float:
	if not weapon:
		return 0.5
	
	if weapon.has_method("get_fire_delay"):
		return weapon.get_fire_delay()
	elif "fire_delay" in weapon:
		return weapon.fire_delay
	elif "fire_rate" in weapon and weapon.fire_rate > 0:
		return 1.0 / weapon.fire_rate
	
	return 0.5

func is_weapon(item: Node) -> bool:
	if not item:
		return false
	
	# Check entity type
	if item.entity_type == "gun":
		return true
	
	return false

func is_magazine_compatible(weapon: Node, magazine: Node) -> bool:
	if not weapon or not magazine:
		return false
	
	if weapon.has_method("can_accept_magazine"):
		return weapon.can_accept_magazine(magazine)
	elif weapon.has_method("is_magazine_compatible"):
		return weapon.is_magazine_compatible(magazine)
	
	# Basic compatibility check
	if "accepted_ammo_types" in weapon and "ammo_type" in magazine:
		return magazine.ammo_type in weapon.accepted_ammo_types
	
	return true

func get_weapon_hand_slot(weapon: Node) -> int:
	if not inventory_system:
		return -1
	
	var left_hand_slot = inventory_system.EquipSlot.LEFT_HAND
	var right_hand_slot = inventory_system.EquipSlot.RIGHT_HAND
	
	# Check if weapon is in either hand
	if inventory_system.get_item_in_slot(left_hand_slot) == weapon:
		return left_hand_slot
	elif inventory_system.get_item_in_slot(right_hand_slot) == weapon:
		return right_hand_slot
	
	return -1

# Utility functions
func get_weapon_name(weapon: Node) -> String:
	if not weapon:
		return "weapon"
	
	if "item_name" in weapon and weapon.item_name != "":
		return weapon.item_name
	elif "obj_name" in weapon and weapon.obj_name != "":
		return weapon.obj_name
	elif "name" in weapon:
		return weapon.name
	
	return "weapon"

func get_fire_mode_name(mode: int) -> String:
	# This would need to be adapted based on the weapon's FireMode enum
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

func play_empty_click_sound():
	if audio_system:
		audio_system.play_positioned_sound("weapon_empty", controller.position, 0.4)

func update_ammo_display(weapon: Node):
	# Signal UI to update ammo count
	if weapon.has_method("get_current_ammo_count") and weapon.has_method("get_max_ammo_count"):
		var current = weapon.get_current_ammo_count()
		var max_ammo = weapon.get_max_ammo_count()
		# UI would need to listen for this signal
		emit_signal("ammo_count_updated", weapon, current, max_ammo)

func show_message(text: String):
	if sensory_system:
		if sensory_system.has_method("display_message"):
			sensory_system.display_message(text)
		elif sensory_system.has_method("add_message"):
			sensory_system.add_message(text)

# Signal handlers
func _on_item_equipped(item: Node, slot: int):
	# Check if a weapon was equipped and auto-wield if appropriate
	if is_weapon(item) and is_hand_slot(slot):
		# Could auto-wield here if desired
		pass

func _on_item_unequipped(item: Node, slot: int):
	# If wielded weapon was unequipped, unwield it
	if item == wielded_weapon:
		unwield_weapon()

func is_hand_slot(slot: int) -> bool:
	if not inventory_system:
		return false
	
	return slot == inventory_system.EquipSlot.LEFT_HAND or slot == inventory_system.EquipSlot.RIGHT_HAND

# Input controller wrapper methods
func handle_reload_request():
	"""Handle reload request from input controller"""
	if not wielded_weapon:
		# Try to reload active item if it's a weapon
		var active_item = inventory_system.get_active_item() if inventory_system else null
		if active_item and is_weapon(active_item):
			handle_weapon_reload_interaction(active_item)
		return
	
	handle_weapon_reload_interaction(wielded_weapon)

func handle_weapon_reload_interaction(weapon: Node):
	"""Handle reload interaction for a specific weapon"""
	if not weapon or not inventory_system:
		return
	
	# Try quick reload with available magazines
	var magazines = find_compatible_magazines(weapon)
	if magazines.size() > 0:
		try_reload_weapon(weapon, magazines[0])
	else:
		show_message("No compatible magazines found!")

func handle_firing_mode_toggle():
	"""Handle firing mode toggle from input controller"""
	if wielded_weapon:
		cycle_firing_mode(wielded_weapon)
	else:
		var active_item = inventory_system.get_active_item() if inventory_system else null
		if active_item and is_weapon(active_item):
			cycle_firing_mode(active_item)

func handle_safety_toggle():
	"""Handle safety toggle from input controller"""
	if wielded_weapon:
		toggle_weapon_safety(wielded_weapon)
	else:
		var active_item = inventory_system.get_active_item() if inventory_system else null
		if active_item and is_weapon(active_item):
			toggle_weapon_safety(active_item)

func handle_unload_request():
	"""Handle unload request from input controller"""
	if wielded_weapon:
		eject_magazine_to_hand(wielded_weapon)
	else:
		var active_item = inventory_system.get_active_item() if inventory_system else null
		if active_item and is_weapon(active_item):
			eject_magazine_to_hand(active_item)

func handle_wielding_toggle():
	"""Handle wielding toggle from input controller"""
	var active_item = inventory_system.get_active_item() if inventory_system else null
	if active_item and is_weapon(active_item):
		handle_weapon_use(active_item)

func handle_eject_magazine():
	"""Handle magazine ejection from input controller"""
	if wielded_weapon:
		eject_magazine_to_floor(wielded_weapon)
	else:
		var active_item = inventory_system.get_active_item() if inventory_system else null
		if active_item and is_weapon(active_item):
			eject_magazine_to_floor(active_item)

func handle_chamber_round():
	"""Handle chamber round from input controller"""
	if wielded_weapon:
		chamber_round(wielded_weapon)
	else:
		var active_item = inventory_system.get_active_item() if inventory_system else null
		if active_item and is_weapon(active_item):
			chamber_round(active_item)

func handle_quick_reload():
	"""Handle quick reload from input controller"""
	if wielded_weapon:
		handle_weapon_reload_interaction(wielded_weapon)
	else:
		var active_item = inventory_system.get_active_item() if inventory_system else null
		if active_item and is_weapon(active_item):
			handle_weapon_reload_interaction(active_item)

func find_compatible_magazines(weapon: Node) -> Array:
	"""Find all compatible magazines in inventory"""
	var compatible_mags = []
	
	if not inventory_system:
		return compatible_mags
	
	# Check all equipped items for magazines
	for slot in inventory_system.equipped_items:
		var item = inventory_system.equipped_items[slot]
		if item and is_magazine_compatible(weapon, item):
			compatible_mags.append(item)
	
	return compatible_mags

# Public interface for other components
func is_wielding_weapon() -> bool:
	return wielded_weapon != null

func get_wielded_weapon() -> Node:
	return wielded_weapon

func is_hands_occupied() -> bool:
	return is_both_hands_occupied

func can_switch_hands_currently() -> bool:
	return can_switch_hands

func force_unwield():
	"""Force unwield weapon (for emergency situations)"""
	if wielded_weapon:
		unwield_weapon()
