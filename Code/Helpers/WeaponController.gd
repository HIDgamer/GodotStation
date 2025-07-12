extends Node
class_name WeaponController

# Signals
signal weapon_state_changed(weapon, is_active)
signal ammo_changed(current_ammo, max_ammo)
signal firing_mode_changed(new_mode)
signal weapon_fired(target_position)
signal weapon_safety_toggled(is_safe)
signal weapon_wielded(is_wielded)
signal weapon_overheat(is_overheated)
signal weapon_reload_started()
signal weapon_reload_completed()

# References
var player = null
var click_system = null
var input_controller = null
var inventory_system = null

# Current weapon state
var active_weapon = null
var is_targeting = false
var is_targeting_locked = false
var target_zone = "chest"

# Initialize controller
func _ready():
	player = get_parent()
	
	# Find click system in the scene
	click_system = find_click_system()
	
	# Connect to player's input controller if available
	if player.has_node("InputController"):
		input_controller = player.get_node("InputController")
	
	# Connect to player's inventory system if available
	if player.has_node("InventorySystem"):
		inventory_system = player.get_node("InventorySystem")
		
		# Connect to inventory system signals if available
		if inventory_system.has_signal("active_item_changed"):
			inventory_system.connect("active_item_changed", Callable(self, "_on_active_item_changed"))
	
	print("WeaponController: Initialized for player ", player.name)

# Find the click system in the scene
func find_click_system():
	# Look for nodes in the "click_system" group
	var systems = get_tree().get_nodes_in_group("click_system")
	if systems.size() > 0:
		return systems[0]
	
	# Try direct path
	var click_system = get_node_or_null("/root/World/ClickSystem")
	if click_system:
		return click_system
	
	# Try another common path
	click_system = get_node_or_null("/root/ClickSystem")
	
	return click_system

# Check if the current active item is a weapon
func is_active_item_weapon() -> bool:
	var active_item = get_active_item()
	if !active_item:
		return false
	
	# Check if item is a weapon (either by tool_behaviour or by class)
	return ("tool_behaviour" in active_item and active_item.tool_behaviour == "weapon") or active_item is WeaponComponent

# Get the active weapon (if any)
func get_active_weapon():
	if is_active_item_weapon():
		return get_active_item()
	return null

# Get active item from inventory system
func get_active_item():
	if inventory_system and inventory_system.has_method("get_active_item"):
		return inventory_system.get_active_item()
	return null

# Handle weapon reload
func handle_weapon_reload():
	var weapon = get_active_weapon()
	if weapon and weapon.has_method("start_reload"):
		weapon.start_reload()
		return true
	return false

# Toggle weapon firing mode
func toggle_weapon_firing_mode():
	var weapon = get_active_weapon()
	if weapon and weapon.has_method("toggle_firing_mode"):
		weapon.toggle_firing_mode()
		return true
	return false

# Toggle weapon safety
func toggle_weapon_safety():
	var weapon = get_active_weapon()
	if weapon and weapon.has_method("toggle_safety"):
		weapon.toggle_safety()
		return true
	return false

# Unload weapon
func unload_weapon():
	var weapon = get_active_weapon()
	if weapon and weapon.has_method("start_unload"):
		weapon.start_unload()
		return true
	return false

# Toggle weapon wielding
func toggle_weapon_wielding():
	var weapon = get_active_weapon()
	if weapon and weapon.has_method("toggle_wielding"):
		weapon.toggle_wielding(player)
		return true
	return false

# Start targeting with weapon
func start_targeting():
	var weapon = get_active_weapon()
	if !weapon or is_targeting:
		return false
	
	# Start targeting mode in click system
	if click_system and click_system.has_method("begin_weapon_targeting"):
		is_targeting = click_system.begin_weapon_targeting(weapon)
		emit_signal("weapon_state_changed", weapon, is_targeting)
		return is_targeting
	
	return false

# Stop targeting with weapon
func stop_targeting():
	if !is_targeting:
		return false
	
	# Stop targeting mode in click system
	if click_system and click_system.has_method("end_weapon_targeting"):
		click_system.end_weapon_targeting()
		is_targeting = false
		emit_signal("weapon_state_changed", active_weapon, false)
		active_weapon = null
		return true
	
	return false

# Toggle weapon targeting
func toggle_targeting():
	if is_targeting:
		return stop_targeting()
	else:
		return start_targeting()

# Process weapon targeting in combat mode
func process_weapon_targeting(delta):
	# Update targeting based on active weapon and combat mode
	var weapon = get_active_weapon()
	
	# Check if we're in combat mode via click system
	var in_combat_mode = false
	if click_system and click_system.has_method("is_combat_mode_active"):
		in_combat_mode = click_system.is_combat_mode_active()
	
	# Auto-engage targeting when in combat mode with a weapon
	if in_combat_mode and weapon and !is_targeting and !is_targeting_locked:
		start_targeting()
	
	# Disengage targeting when no weapon or combat mode off
	elif (is_targeting and (!weapon or !in_combat_mode)) and !is_targeting_locked:
		stop_targeting()

# Connect to weapon signals
func connect_weapon_signals(weapon):
	if !weapon:
		return
		
	# Connect to weapon signals if they exist
	if weapon.has_signal("weapon_fired") and !weapon.is_connected("weapon_fired", Callable(self, "_on_weapon_fired")):
		weapon.connect("weapon_fired", Callable(self, "_on_weapon_fired"))
	
	if weapon.has_signal("mode_changed") and !weapon.is_connected("mode_changed", Callable(self, "_on_firing_mode_changed")):
		weapon.connect("mode_changed", Callable(self, "_on_firing_mode_changed"))
	
	if weapon.has_signal("safety_toggled") and !weapon.is_connected("safety_toggled", Callable(self, "_on_safety_toggled")):
		weapon.connect("safety_toggled", Callable(self, "_on_safety_toggled"))
	
	if weapon.has_signal("ammo_changed") and !weapon.is_connected("ammo_changed", Callable(self, "_on_ammo_changed")):
		weapon.connect("ammo_changed", Callable(self, "_on_ammo_changed"))
	
	if weapon.has_signal("weapon_wielded") and !weapon.is_connected("weapon_wielded", Callable(self, "_on_weapon_wielded")):
		weapon.connect("weapon_wielded", Callable(self, "_on_weapon_wielded"))
	
	if weapon.has_signal("overheated") and !weapon.is_connected("overheated", Callable(self, "_on_weapon_overheated")):
		weapon.connect("overheated", Callable(self, "_on_weapon_overheated"))
	
	if weapon.has_signal("reload_started") and !weapon.is_connected("reload_started", Callable(self, "_on_reload_started")):
		weapon.connect("reload_started", Callable(self, "_on_reload_started"))
	
	if weapon.has_signal("reload_completed") and !weapon.is_connected("reload_completed", Callable(self, "_on_reload_completed")):
		weapon.connect("reload_completed", Callable(self, "_on_reload_completed"))

# Disconnect from weapon signals
func disconnect_weapon_signals(weapon):
	if !weapon:
		return
		
	# Disconnect from weapon signals
	if weapon.has_signal("weapon_fired") and weapon.is_connected("weapon_fired", Callable(self, "_on_weapon_fired")):
		weapon.disconnect("weapon_fired", Callable(self, "_on_weapon_fired"))
	
	if weapon.has_signal("mode_changed") and weapon.is_connected("mode_changed", Callable(self, "_on_firing_mode_changed")):
		weapon.disconnect("mode_changed", Callable(self, "_on_firing_mode_changed"))
	
	if weapon.has_signal("safety_toggled") and weapon.is_connected("safety_toggled", Callable(self, "_on_safety_toggled")):
		weapon.disconnect("safety_toggled", Callable(self, "_on_safety_toggled"))
	
	if weapon.has_signal("ammo_changed") and weapon.is_connected("ammo_changed", Callable(self, "_on_ammo_changed")):
		weapon.disconnect("ammo_changed", Callable(self, "_on_ammo_changed"))
	
	if weapon.has_signal("weapon_wielded") and weapon.is_connected("weapon_wielded", Callable(self, "_on_weapon_wielded")):
		weapon.disconnect("weapon_wielded", Callable(self, "_on_weapon_wielded"))
	
	if weapon.has_signal("overheated") and weapon.is_connected("overheated", Callable(self, "_on_weapon_overheated")):
		weapon.disconnect("overheated", Callable(self, "_on_weapon_overheated"))
	
	if weapon.has_signal("reload_started") and weapon.is_connected("reload_started", Callable(self, "_on_reload_started")):
		weapon.disconnect("reload_started", Callable(self, "_on_reload_started"))
	
	if weapon.has_signal("reload_completed") and weapon.is_connected("reload_completed", Callable(self, "_on_reload_completed")):
		weapon.disconnect("reload_completed", Callable(self, "_on_reload_completed"))

# Set target zone for weapon
func set_target_zone(zone: String):
	target_zone = zone
	# This could be used to modify weapon damage or effects based on target zone

# Signal handlers
func _on_active_item_changed(new_item, old_item):
	# Disconnect from old weapon if it exists
	if old_item and (("tool_behaviour" in old_item and old_item.tool_behaviour == "weapon") or old_item is WeaponComponent):
		disconnect_weapon_signals(old_item)
	
	# Connect to new weapon if it exists
	if new_item and (("tool_behaviour" in new_item and new_item.tool_behaviour == "weapon") or new_item is WeaponComponent):
		connect_weapon_signals(new_item)
		
		# Update active weapon if targeting
		if is_targeting:
			active_weapon = new_item
			emit_signal("weapon_state_changed", active_weapon, true)

# Weapon signal handlers
func _on_weapon_fired(target_position):
	emit_signal("weapon_fired", target_position)

func _on_firing_mode_changed(new_mode):
	emit_signal("firing_mode_changed", new_mode)

func _on_safety_toggled(is_safe):
	emit_signal("weapon_safety_toggled", is_safe)

func _on_ammo_changed(current_ammo, max_ammo):
	emit_signal("ammo_changed", current_ammo, max_ammo)

func _on_weapon_wielded(is_wielded):
	emit_signal("weapon_wielded", is_wielded)

func _on_weapon_overheated(is_overheated):
	emit_signal("weapon_overheat", is_overheated)

func _on_reload_started():
	emit_signal("weapon_reload_started")

func _on_reload_completed():
	emit_signal("weapon_reload_completed")
