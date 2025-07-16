extends BaseObject
class_name Machinery

var entity_id: String = "machinery"

# === MACHINERY PROPERTIES ===
var is_powered: bool = true
var power_usage: float = 1.0
var power_draw_per_tick: float = 0.01
var requires_power: bool = true

# === ENTITY SYSTEM INTEGRATION ===
var can_be_bumped: bool = true  # Can be bumped into by characters

# === SIGNALS ===
signal powered_on()
signal powered_off()
signal machinery_activated(user)
signal machinery_deactivated(user)
signal machinery_state_changed(new_state)

# === STATE VARIABLES ===
var is_active: bool = false
var current_user = null
var machinery_state: String = "inactive"
var use_cooldown: float = 0.0
var cooldown_timer: float = 0.0

func _ready():
	# Call parent ready function
	super()
	
	# Set default object properties
	obj_name = "machinery"
	obj_desc = "A piece of machinery."
	
	# Add required groups
	add_to_group("machinery")
	add_to_group("clickable_entities")
	
	# Make sure the entity ID is set
	if entity_id == "machinery":
		entity_id = "machinery_" + str(get_instance_id())

func _process(delta):
	# Handle cooldown timer
	if cooldown_timer > 0:
		cooldown_timer -= delta
		if cooldown_timer < 0:
			cooldown_timer = 0
	
	# Handle power draw if active
	if is_active and requires_power:
		draw_power(power_draw_per_tick * delta)

# === POWER MANAGEMENT ===
func draw_power(amount: float) -> bool:
	# This would connect to your power system
	# For now, just check if powered
	if not is_powered:
		deactivate()
		return false
	return true

func toggle_power() -> bool:
	is_powered = !is_powered
	
	if is_powered:
		powered_on.emit()
	else:
		# If power is cut, deactivate machinery
		if is_active:
			deactivate()
		powered_off.emit()
	
	return is_powered

# === ACTIVATION ===
func try_activate(user = null) -> bool:
	# Check if machinery can be activated
	if not can_activate(user):
		return false
	
	return activate(user)

func can_activate(user = null) -> bool:
	# Check if on cooldown
	if cooldown_timer > 0:
		return false
	
	# Check if already active
	if is_active:
		return false
	
	# Check if powered
	if requires_power and not is_powered:
		return false
	
	# Check if broken
	if obj_integrity <= integrity_failure:
		return false
	
	# Check if user can interact
	if user and not can_interact(user):
		return false
	
	return true

func activate(user = null) -> bool:
	if not can_activate(user):
		return false
	
	is_active = true
	current_user = user
	machinery_state = "active"
	
	# Start cooldown
	cooldown_timer = use_cooldown
	
	# Emit signals
	machinery_activated.emit(user)
	machinery_state_changed.emit(machinery_state)
	
	return true

# === DEACTIVATION ===
func deactivate(user = null) -> bool:
	if not is_active:
		return false
	
	is_active = false
	current_user = null
	machinery_state = "inactive"
	
	# Emit signals
	machinery_deactivated.emit(user)
	machinery_state_changed.emit(machinery_state)
	
	return true

# === INTERACTION OVERRIDES ===
func interact(user) -> bool:
	# Call parent function
	super.interact(user)
	
	# Toggle activation
	if is_active:
		return deactivate(user)
	else:
		return try_activate(user)

# === BUMP HANDLING ===
func on_bump(bumper) -> bool:
	# Default machinery doesn't do anything on bump
	# Override in subclasses
	return false

# === CLICK HANDLER INTEGRATION ===
func ClickOn(clicker) -> bool:
	return interact(clicker)

# === DAMAGE HANDLING ===
func obj_break(damage_flag: String = "") -> void:
	super.obj_break(damage_flag)
	
	# Deactivate machinery when broken
	if is_active:
		deactivate()
	
	# Update appearance
	update_appearance()

# === CUSTOM EXAMINE ===
func examine(examiner) -> String:
	var examine_text = super.examine(examiner)
	
	# Add power status
	if requires_power:
		if is_powered:
			examine_text += "\nIt appears to be powered on."
		else:
			examine_text += "\nIt appears to be powered off."
	
	# Add active status
	if is_active:
		examine_text += "\nIt is currently active."
	
	return examine_text
