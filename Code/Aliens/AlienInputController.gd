extends InputController
class_name AlienInputController

# Alien-specific input actions
const ALIEN_INPUT_ACTIONS = {
	# Movement
	"move_up": "up",
	"move_down": "down", 
	"move_left": "left",
	"move_right": "right",
	"sprint": "modifier_shift",
	"move_z_up": "move_up",
	"move_z_down": "move_down",
	
	# Alien combat actions
	"primary_attack": "left_click",
	"secondary_attack": "right_click",
	"pounce": "chamber",
	"tail_attack": "tail_whip",
	"acid_spit": "acid_spit",
	
	# Alien abilities
	"rest": "rest",
	"life_sense": "life_sense",
	"climb_walls": "climb",
	"hide": "stealth",
	"grab_prey": "grab",
	
	# Basic interactions
	"examine": "examine_mode",
	"use": "interact",
	"drop": "drop_item",
	
	# UI
	"toggle_pause": "esc"
}

signal primary_attack_requested()
signal secondary_attack_requested()
signal pounce_requested()
signal tail_attack_requested()
signal acid_spit_requested()
signal life_sense_requested()
signal climb_walls_requested()
signal hide_requested()
signal grab_prey_requested()
signal carry_prey_requested()
signal drop_requested()

var is_alien_entity: bool = true
var life_sense_component: Node = null
var grab_component: Node = null

func _ready():
	super._ready()
	is_alien_entity = true
	check_alien_input_actions()

func check_alien_input_actions():
	var undefined_actions = []
	
	for action_type in ALIEN_INPUT_ACTIONS:
		var action_name = ALIEN_INPUT_ACTIONS[action_type]
		if not InputMap.has_action(action_name):
			undefined_actions.append(action_name)
	
	if undefined_actions.size() > 0:
		push_warning("AlienInputController: Missing input actions: " + str(undefined_actions))
		print_alien_input_setup_guide()

func print_alien_input_setup_guide():
	print("\n=== Alien Input Setup Guide ===")
	print("Define these input actions in Project Settings > Input Map:")
	
	for action_type in ALIEN_INPUT_ACTIONS:
		var action_name = ALIEN_INPUT_ACTIONS[action_type]
		print("- " + action_name + " (for " + action_type + ")")
	
	print("\nAlien-specific bindings:")
	print("- pounce: Space (pounce attack)")
	print("- tail_whip: T (tail attack)")
	print("- acid_spit: R (ranged acid attack)")
	print("- life_sense: F (detect life forms)")
	print("- climb: C (wall climbing)")
	print("- stealth: Ctrl+C (hide)")
	print("- grab: G (grab prey)")
	print("- carry: Shift+G (carry prey)")
	print("===============================\n")

func process_action_input():
	# UI toggles
	if pause_handling_enabled and Input.is_action_just_pressed(ALIEN_INPUT_ACTIONS["toggle_pause"]):
		_handle_pause_toggle()
	
	# Alien combat actions
	if Input.is_action_just_pressed(ALIEN_INPUT_ACTIONS["primary_attack"]):
		emit_signal("primary_attack_requested")
	
	if Input.is_action_just_pressed(ALIEN_INPUT_ACTIONS["secondary_attack"]):
		emit_signal("secondary_attack_requested")
	
	if Input.is_action_just_pressed(ALIEN_INPUT_ACTIONS["pounce"]):
		emit_signal("pounce_requested")
	
	if Input.is_action_just_pressed(ALIEN_INPUT_ACTIONS["tail_attack"]):
		emit_signal("tail_attack_requested")
	
	if Input.is_action_just_pressed(ALIEN_INPUT_ACTIONS["acid_spit"]):
		emit_signal("acid_spit_requested")
	
	# Alien abilities
	if Input.is_action_just_pressed(ALIEN_INPUT_ACTIONS["rest"]):
		emit_signal("toggle_rest_requested")
	
	if Input.is_action_just_pressed(ALIEN_INPUT_ACTIONS["life_sense"]):
		emit_signal("life_sense_requested")
	
	if Input.is_action_just_pressed(ALIEN_INPUT_ACTIONS["climb_walls"]):
		emit_signal("climb_walls_requested")
	
	if Input.is_action_just_pressed(ALIEN_INPUT_ACTIONS["hide"]):
		emit_signal("hide_requested")
	
	if Input.is_action_just_pressed(ALIEN_INPUT_ACTIONS["grab_prey"]):
		emit_signal("grab_prey_requested")
	
	# Basic interactions
	if Input.is_action_just_pressed(ALIEN_INPUT_ACTIONS["examine"]):
		emit_signal("examine_mode_requested")
	
	if Input.is_action_just_pressed(ALIEN_INPUT_ACTIONS["use"]):
		emit_signal("use_requested")
	
	if Input.is_action_just_pressed(ALIEN_INPUT_ACTIONS["drop"]):
		emit_signal("drop_requested")
	
	# Z-level movement
	if Input.is_action_just_pressed(ALIEN_INPUT_ACTIONS["move_z_up"]):
		emit_signal("move_up_requested")
	
	if Input.is_action_just_pressed(ALIEN_INPUT_ACTIONS["move_z_down"]):
		emit_signal("move_down_requested")

func connect_to_entity(target_entity: Node):
	entity = target_entity
	
	if entity == null:
		print("AlienInputController: Entity is null")
		return
	
	print("AlienInputController: Connecting to alien entity: ", entity.name)
	
	# Find alien-specific components
	life_sense_component = entity.get_node_or_null("AlienVisionComponent")
	grab_component = entity.get_node_or_null("GrabPullComponent")
	
	# Movement connections (same as humans)
	connect_to_component("move_requested", "handle_move_input", "MovementComponent")
	connect_to_component("toggle_run_requested", "toggle_run", "MovementComponent")
	
	# Alien combat connections
	connect_to_alien_method("primary_attack_requested", "handle_primary_attack")
	connect_to_alien_method("secondary_attack_requested", "handle_secondary_attack")
	connect_to_alien_method("pounce_requested", "handle_pounce_attack")
	connect_to_alien_method("tail_attack_requested", "handle_tail_attack")
	connect_to_alien_method("acid_spit_requested", "handle_acid_spit")
	
	# Alien ability connections
	connect_to_component("toggle_rest_requested", "handle_rest_toggle", "AlienPostureComponent")
	connect_to_alien_method("life_sense_requested", "handle_life_sense")
	connect_to_alien_method("climb_walls_requested", "handle_wall_climb")
	connect_to_alien_method("hide_requested", "handle_stealth")
	
	# Grab/carry connections
	connect_to_component("grab_prey_requested", "handle_grab_prey", "GrabPullComponent")
	connect_to_component("drop_requested", "release_grab", "GrabPullComponent")
	
	# Basic interactions
	connect_to_alien_method("examine_mode_requested", "set_examine_mode")
	connect_to_alien_method("use_requested", "handle_alien_use")
	
	# Z-level movement
	connect_to_component("move_up_requested", "move_up", "ZLevelMovementComponent")
	connect_to_component("move_down_requested", "move_down", "ZLevelMovementComponent")
	
	print("AlienInputController: Successfully connected to alien entity")

func connect_to_alien_method(signal_name: String, method_name: String):
	if entity == null:
		return
	
	if entity.has_method(method_name):
		if is_connected(signal_name, Callable(entity, method_name)):
			disconnect(signal_name, Callable(entity, method_name))
		
		connect(signal_name, Callable(entity, method_name))
		print("AlienInputController: Connected ", signal_name, " to alien.", method_name)
	else:
		print("AlienInputController: Method not found: ", method_name)

func connect_to_component(signal_name: String, method_name: String, component_name: String):
	if entity == null:
		return
	
	var component = entity.get_node_or_null(component_name)
	if component and component.has_method(method_name):
		if is_connected(signal_name, Callable(component, method_name)):
			disconnect(signal_name, Callable(component, method_name))
		
		connect(signal_name, Callable(component, method_name))
		print("AlienInputController: Connected ", signal_name, " to ", component_name, ".", method_name)
	else:
		# Try connecting to entity method as fallback
		connect_to_alien_method(signal_name, method_name)

func disable_for_alien_npc():
	set_active(false)
	entity = null
	print("AlienInputController: Disabled for alien NPC")
