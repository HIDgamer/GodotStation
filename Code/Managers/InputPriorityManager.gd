extends Node

# Singleton pattern
static var instance: InputPriorityManager = null

# Systems registered for input handling
var ui_systems = []
var world_systems = []

# Whether UI is currently handling input (blocks world interaction)
var ui_active = false

func _init():
	instance = self

func _ready():
	process_priority = -100  # Ensure this runs before other systems

# Register UI system (like PlayerUI)
func register_ui_system(system):
	if not system in ui_systems:
		ui_systems.append(system)
		print("InputPriorityManager: Registered UI system: ", system.name)

# Register world system (like ClickSystem)
func register_world_system(system):
	if not system in world_systems:
		world_systems.append(system)
		print("InputPriorityManager: Registered world system: ", system.name)

# Check if a position is over any UI element
func is_over_ui(position: Vector2) -> bool:
	for system in ui_systems:
		if system.has_method("is_position_in_ui_element"):
			if system.is_position_in_ui_element(position):
				return true
	return false

# Clear UI active state
func clear_ui_active():
	ui_active = false

# Set UI active state
func set_ui_active():
	ui_active = true

# Check if UI is currently handling input
func is_ui_active() -> bool:
	return ui_active
