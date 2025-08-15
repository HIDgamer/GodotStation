extends BaseObject
class_name Machinery

# === MACHINERY CORE PROPERTIES ===
@export_group("Machinery Settings")
@export var machinery_type: String = "generic"
@export var machinery_id: String = ""
@export var use_cooldown: float = 0.0
@export var auto_activate: bool = false
@export var can_be_bumped: bool = true

# === POWER SYSTEM ===
@export_subgroup("Power")
@export var requires_power: bool = true
@export var power_usage: float = 1.0
@export var power_draw_per_tick: float = 0.01
@export var emergency_power_compatible: bool = false
@export var power_priority: int = 1  # 1=low, 5=critical

# === STATE MANAGEMENT ===
@export_subgroup("State")
@export var persistent_state: bool = true
@export var save_state_on_change: bool = true

# === INTERNAL STATE ===
var is_powered: bool = true
var is_active: bool = false
var current_user = null
var machinery_state: String = "inactive"
var cooldown_timer: float = 0.0
var power_network_id: int = -1
var last_power_check: float = 0.0

# === SIGNALS ===
signal powered_on()
signal powered_off()
signal machinery_activated(user)
signal machinery_deactivated(user)
signal machinery_state_changed(old_state, new_state)
signal power_draw_changed(new_draw)
signal emergency_power_activated()
signal machinery_malfunction()

# === POWER NETWORK REFERENCE ===
var power_network = null

func _ready():
	super()
	
	# Set default properties if not already set
	if obj_name == "object":
		obj_name = machinery_type
	
	if obj_desc == "An object.":
		obj_desc = "A piece of %s machinery." % machinery_type
	
	# Generate unique ID if not set
	if machinery_id.is_empty():
		machinery_id = machinery_type + "_" + str(get_instance_id())
	
	# Add to groups
	add_to_group("machinery")
	add_to_group("clickable_entities")
	add_to_group(machinery_type + "_machinery")
	
	# Initialize power system
	_initialize_power_system()
	
	# Auto-activate if specified
	if auto_activate and can_activate():
		call_deferred("activate")

func _process(delta):
	# Handle cooldown
	if cooldown_timer > 0:
		cooldown_timer -= delta
		if cooldown_timer <= 0:
			cooldown_timer = 0
			_on_cooldown_finished()
	
	# Handle power consumption
	if is_active and requires_power:
		_consume_power(delta)

func _initialize_power_system():
	"""Initialize connection to power network"""
	if not requires_power:
		return
	
	# Find power network
	var world = get_node_or_null("/root/World")
	if world:
		power_network = world.get_node_or_null("PowerNetwork")
		if power_network and power_network.has_method("register_consumer"):
			power_network.register_consumer(self)

func _consume_power(delta: float):
	"""Handle power consumption per frame"""
	if not requires_power or not is_powered:
		return
	
	var power_needed = power_draw_per_tick * delta
	
	if power_network and power_network.has_method("request_power"):
		var power_received = power_network.request_power(self, power_needed)
		
		if power_received < power_needed * 0.8:  # 80% threshold
			_handle_power_shortage()
	else:
		# Fallback: assume power is available
		pass

func _handle_power_shortage():
	"""Handle insufficient power"""
	if is_active:
		print("Machinery %s: Power shortage, deactivating" % machinery_id)
		deactivate()
		machinery_malfunction.emit()

# === POWER MANAGEMENT ===
func set_powered(powered: bool, reason: String = ""):
	"""Set power state with reason"""
	if is_powered == powered:
		return
	
	var old_state = is_powered
	is_powered = powered
	
	if powered:
		print("Machinery %s: Power restored" % machinery_id + (" (%s)" % reason if reason else ""))
		powered_on.emit()
		_on_power_restored()
	else:
		print("Machinery %s: Power lost" % machinery_id + (" (%s)" % reason if reason else ""))
		if is_active:
			deactivate()
		powered_off.emit()
		_on_power_lost()

func toggle_power() -> bool:
	"""Toggle power state manually"""
	set_powered(not is_powered, "manual toggle")
	return is_powered

func get_power_consumption() -> float:
	"""Get current power consumption"""
	if not requires_power or not is_active:
		return 0.0
	return power_usage

func get_power_priority() -> int:
	"""Get power priority for load balancing"""
	return power_priority

# === ACTIVATION SYSTEM ===
func can_activate(user = null) -> bool:
	"""Check if machinery can be activated"""
	# Cooldown check
	if cooldown_timer > 0:
		return false
	
	# Already active check
	if is_active:
		return false
	
	# Power check
	if requires_power and not is_powered:
		return false
	
	# Integrity check
	if obj_integrity <= integrity_failure:
		return false
	
	# User interaction check
	if user and not can_interact(user):
		return false
	
	# Custom activation checks
	return _can_activate_custom(user)

func _can_activate_custom(user = null) -> bool:
	"""Override this for custom activation conditions"""
	return true

func activate(user = null) -> bool:
	"""Activate the machinery"""
	if not can_activate(user):
		return false
	
	var old_state = machinery_state
	is_active = true
	current_user = user
	machinery_state = "active"
	cooldown_timer = use_cooldown
	
	print("Machinery %s: Activated" % machinery_id + (" by %s" % str(user) if user else ""))
	
	# Custom activation logic
	_on_activated(user)
	
	# Emit signals
	machinery_activated.emit(user)
	machinery_state_changed.emit(old_state, machinery_state)
	
	if save_state_on_change:
		_save_state()
	
	return true

func _on_activated(user = null):
	"""Override this for custom activation behavior"""
	pass

func deactivate(user = null, reason: String = "") -> bool:
	"""Deactivate the machinery"""
	if not is_active:
		return false
	
	var old_state = machinery_state
	is_active = false
	current_user = null
	machinery_state = "inactive"
	
	print("Machinery %s: Deactivated" % machinery_id + (" by %s" % str(user) if user else "") + (" (%s)" % reason if reason else ""))
	
	# Custom deactivation logic
	_on_deactivated(user, reason)
	
	# Emit signals
	machinery_deactivated.emit(user)
	machinery_state_changed.emit(old_state, machinery_state)
	
	if save_state_on_change:
		_save_state()
	
	return true

func _on_deactivated(user = null, reason: String = ""):
	"""Override this for custom deactivation behavior"""
	pass

func force_deactivate(reason: String = "forced"):
	"""Force deactivation regardless of conditions"""
	if is_active:
		deactivate(null, reason)

# === STATE MANAGEMENT ===
func set_machinery_state(new_state: String):
	"""Set machinery state with proper signaling"""
	if machinery_state == new_state:
		return
	
	var old_state = machinery_state
	machinery_state = new_state
	
	machinery_state_changed.emit(old_state, new_state)
	
	if save_state_on_change:
		_save_state()

func get_state_data() -> Dictionary:
	"""Get complete state data for saving/loading"""
	var state = {}
	
	state.merge({
		"machinery_type": machinery_type,
		"machinery_id": machinery_id,
		"is_powered": is_powered,
		"is_active": is_active,
		"machinery_state": machinery_state,
		"cooldown_timer": cooldown_timer,
		"power_network_id": power_network_id
	})
	
	return state

func load_state_data(state: Dictionary):
	"""Load state data"""
	
	if "machinery_type" in state:
		machinery_type = state.machinery_type
	if "machinery_id" in state:
		machinery_id = state.machinery_id
	if "is_powered" in state:
		is_powered = state.is_powered
	if "is_active" in state:
		is_active = state.is_active
	if "machinery_state" in state:
		machinery_state = state.machinery_state
	if "cooldown_timer" in state:
		cooldown_timer = state.cooldown_timer
	if "power_network_id" in state:
		power_network_id = state.power_network_id

func _save_state():
	"""Save current state to world"""
	if not persistent_state:
		return
	
	var world = get_node_or_null("/root/World")
	if world and world.has_method("save_machinery_state"):
		world.save_machinery_state(machinery_id, get_state_data())

# === EVENT HANDLERS ===
func _on_power_restored():
	"""Called when power is restored"""
	# Override in subclasses
	pass

func _on_power_lost():
	"""Called when power is lost"""
	# Override in subclasses
	pass

func _on_cooldown_finished():
	"""Called when cooldown timer reaches zero"""
	# Override in subclasses
	pass

# === INTERACTION OVERRIDES ===
func on_bump(bumper) -> bool:
	"""Handle entity bumping into machinery"""
	if not can_be_bumped:
		return true  # Block movement
	
	# Custom bump behavior
	return _handle_bump(bumper)

func _handle_bump(bumper) -> bool:
	"""Override this for custom bump behavior"""
	return false  # Allow movement by default

func ClickOn(clicker) -> bool:
	"""Handle click interaction"""
	return interact(clicker)

func interact(user) -> bool:
	"""Handle interaction with machinery"""
	if not can_interact(user):
		return false
	
	# Try to activate/deactivate
	if is_active:
		return deactivate(user, "user interaction")
	else:
		return activate(user)

# === DAMAGE AND DESTRUCTION ===
func obj_break(damage_flag: String = "") -> void:
	"""Handle machinery breaking"""
	super.obj_break(damage_flag)
	
	# Force deactivation when broken
	if is_active:
		force_deactivate("machinery broken")
	
	# Disconnect from power network
	if power_network and power_network.has_method("unregister_consumer"):
		power_network.unregister_consumer(self)
	
	update_appearance()

func update_appearance():
	"""Update visual appearance based on state"""
	# Override in subclasses
	pass

# === EXAMINATION ===
func examine(examiner) -> String:
	"""Provide detailed examination text"""
	var examine_text = super.examine(examiner)
	
	# Power status
	if requires_power:
		if is_powered:
			examine_text += "\nThe power indicator shows green."
		else:
			examine_text += "\nThe power indicator is dark."
	
	# Active status
	if is_active:
		examine_text += "\nIt is currently running."
	elif machinery_state != "inactive":
		examine_text += ("\nIt is %s." % machinery_state)
	
	# Cooldown status
	if cooldown_timer > 0:
		examine_text += ("\nIt will be ready in %.1f seconds." % cooldown_timer)
	
	# Custom examination details
	var custom_details = _get_examination_details(examiner)
	if not custom_details.is_empty():
		examine_text += "\n" + custom_details
	
	return examine_text

func _get_examination_details(examiner) -> String:
	"""Override this to add custom examination details"""
	return ""

# === CLEANUP ===
func _exit_tree():
	"""Clean up when removed from scene"""
	if power_network and power_network.has_method("unregister_consumer"):
		power_network.unregister_consumer(self)
