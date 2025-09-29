extends Node
class_name InputController

#region EXPORTS AND CONFIGURATION
@export_group("Input Settings")
@export var pause_handling_enabled: bool = true
@export var analog_deadzone: float = 0.2
@export var debug_mode: bool = false
@export var auto_connect_entity: bool = true

@export_group("Input Validation")
@export var validate_input_actions: bool = true
@export var show_setup_guide: bool = true
@export var require_all_actions: bool = false
#endregion

#region CONSTANTS
# Input mapping for project settings actions
const INPUT_ACTIONS = {
	# Movement
	"move_up": "up",
	"move_down": "down",
	"move_left": "left",
	"move_right": "right",
	"sprint": "modifier_shift",
	"move_z_up": "move_up",
	"move_z_down": "move_down",
	
	# Combat
	"attack_self": "interact",
	"toggle_throw": "throw_mode",
	"drop_item": "drop_item",
	"cancel": "drop_item",
	"pickup_item": "pickup",
	"swap_hand": "switch_hand",
	"intent_help": "mode_help",
	"intent_disarm": "mode_disarm",
	"intent_grab": "mode_grab",
	"intent_harm": "mode_harm",
	"cycle_intent": "cycle_intent",
	"toggle_combat": "mode_harm",
	"use": "interact",
	"examine_mode": "examine_mode",
	
	# Weapon controls
	"toggle_weapon_wielding": "interact",
	"eject_magazine": "eject_mag",
	"chamber_round": "chamber",
	
	# Body part targeting
	"target_head": "target_head",
	"target_chest": "target_chest",
	"target_l_arm": "target_l_arm",
	"target_r_arm": "target_r_arm",
	"target_l_leg": "target_l_leg",
	"target_r_leg": "target_r_leg",
	"target_groin": "target_groin",
	
	# Other
	"toggle_point": "point_mode",
	"toggle_pull": "toggle_pull",
	"toggle_pause": "esc",
	"toggle_spawner": "adminspawn",
	"toggle_rest": "rest"
}
#endregion

#region SIGNALS
# Movement and action signals
signal move_requested(direction)
signal toggle_run_requested(is_running)
signal toggle_throw_requested()
signal swap_hand_requested()
signal drop_item_requested()
signal cancel_action_requested()
signal pickup_requested()
signal attack_self_requested()
signal cycle_intent_requested()
signal set_intent_requested(intent_index)
signal body_part_selected(part)
signal move_up_requested()
signal move_down_requested()
signal toggle_combat_mode_requested()
signal use_active_item_self_requested()
signal toggle_point_mode_requested()
signal toggle_pull_requested()
signal toggle_crouch_requested()
signal reload_weapon_requested()
signal examine_mode_requested()
signal toggle_rest_requested()
signal use_requested()

# Weapon system signals
signal toggle_weapon_safety_requested()
signal unload_weapon_requested()
signal toggle_weapon_wielding_requested()
signal eject_magazine_requested()
signal chamber_round_requested()
signal quick_reload_requested()
#endregion

#region PROPERTIES
# The entity controlled by this input controller
var entity: Node
var initialized: bool = false
var running: bool = false

# Component connection tracking
var connected_components: Dictionary = {}
var failed_connections: Array[String] = []
#endregion

#region INITIALIZATION
func _ready():
	"""Initialize the input controller"""
	if validate_input_actions:
		_check_input_actions()
	
	if auto_connect_entity:
		# Connect to parent entity if available
		var parent = get_parent()
		if parent and (_has_movement_component(parent) or parent.name == "GridMovementController"):
			call_deferred("connect_to_entity", parent)
	
	initialized = true
	
	if debug_mode:
		print("InputController: Initialized successfully")

func _check_input_actions():
	"""Verify that required input actions are defined in project settings"""
	var undefined_actions = []
	
	for action_type in INPUT_ACTIONS:
		var action_name = INPUT_ACTIONS[action_type]
		if not InputMap.has_action(action_name):
			undefined_actions.append(action_name)
	
	if undefined_actions.size() > 0:
		if require_all_actions:
			push_error("InputController: Missing required input actions: " + str(undefined_actions))
		else:
			push_warning("InputController: Missing input actions: " + str(undefined_actions))
		
		if show_setup_guide:
			_print_input_setup_guide()

func _print_input_setup_guide():
	"""Print a guide for setting up input actions"""
	print("\n=== InputController Setup Guide ===")
	print("Define these input actions in Project Settings > Input Map:")
	
	for action_type in INPUT_ACTIONS:
		var action_name = INPUT_ACTIONS[action_type]
		print("- " + action_name + " (for " + action_type + ")")
	
	print("\nExample key bindings:")
	print("- up, down, left, right: WASD or Arrow keys")
	print("- modifier_shift: Shift (running)")
	print("- move_up/move_down: E/Q (z-level movement)")
	print("- switch_hand: X (swap hands)")
	print("- drop_item: Q (drop item)")
	print("- pickup: G (pickup items)")
	print("- interact: Z (use/interact)")
	print("- throw_mode: R (toggle throw)")
	print("- reload: R (reload weapon)")
	print("- examine_mode: Alt (examine)")
	print("- weapon_safety: V (weapon safety)")
	print("- unload: U (unload weapon)")
	print("- target_*: Numpad 1-9 (body targeting)")
	print("- cycle_intent: Tab (cycle intents)")
	print("- esc: ESC (pause menu)")
	print("=================================\n")

func _has_movement_component(node: Node) -> bool:
	"""Check if node has movement capabilities"""
	return node.has_node("MovementComponent") or node.has_method("handle_move_input")
#endregion

#region INPUT PROCESSING
func _process(delta):
	"""Process input each frame"""
	if not initialized:
		return
		
	_process_movement_input()
	_process_action_input()

func _process_movement_input():
	"""Handle directional movement input"""
	var input_dir = Vector2.ZERO
	
	# Keyboard movement
	if _is_action_available("move_right") and Input.is_action_pressed(INPUT_ACTIONS["move_right"]):
		input_dir.x += 1
	if _is_action_available("move_left") and Input.is_action_pressed(INPUT_ACTIONS["move_left"]):
		input_dir.x -= 1
	if _is_action_available("move_down") and Input.is_action_pressed(INPUT_ACTIONS["move_down"]):
		input_dir.y += 1
	if _is_action_available("move_up") and Input.is_action_pressed(INPUT_ACTIONS["move_up"]):
		input_dir.y -= 1
	
	# Normalize diagonal movement
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()
	
	# Emit movement signal for continuous movement
	if input_dir != Vector2.ZERO:
		emit_signal("move_requested", input_dir)
	
	# Handle run toggling
	_check_run_toggle()
	
	# Z-level movement
	if _is_action_available("move_z_up") and Input.is_action_just_pressed(INPUT_ACTIONS["move_z_up"]):
		emit_signal("move_up_requested")
	
	if _is_action_available("move_z_down") and Input.is_action_just_pressed(INPUT_ACTIONS["move_z_down"]):
		emit_signal("move_down_requested")

func _process_action_input():
	"""Handle action input (non-movement)"""
	# UI toggles
	if pause_handling_enabled and _is_action_available("toggle_pause") and Input.is_action_just_pressed(INPUT_ACTIONS["toggle_pause"]):
		_handle_pause_toggle()
	
	if _is_action_available("toggle_spawner") and Input.is_action_just_pressed(INPUT_ACTIONS["toggle_spawner"]):
		_handle_spawner_toggle()
	
	# Item interaction
	if _is_action_available("swap_hand") and Input.is_action_just_pressed(INPUT_ACTIONS["swap_hand"]):
		emit_signal("swap_hand_requested")
	
	if _is_action_available("cancel") and Input.is_action_just_pressed(INPUT_ACTIONS["cancel"]):
		emit_signal("cancel_action_requested")
	
	if _is_action_available("use") and Input.is_action_just_pressed(INPUT_ACTIONS["use"]):
		emit_signal("use_requested")
	
	if _is_action_available("drop_item") and Input.is_action_just_pressed(INPUT_ACTIONS["drop_item"]):
		emit_signal("drop_item_requested")
	
	if _is_action_available("pickup_item") and Input.is_action_just_pressed(INPUT_ACTIONS["pickup_item"]):
		emit_signal("pickup_requested")
	
	if _is_action_available("attack_self") and Input.is_action_just_pressed(INPUT_ACTIONS["attack_self"]):
		emit_signal("attack_self_requested")
		
	if _is_action_available("toggle_throw") and Input.is_action_just_pressed(INPUT_ACTIONS["toggle_throw"]):
		emit_signal("toggle_throw_requested")
	
	# Weapon controls
	if _is_action_available("toggle_weapon_wielding") and Input.is_action_just_pressed(INPUT_ACTIONS["toggle_weapon_wielding"]):
		emit_signal("toggle_weapon_wielding_requested")
	
	if _is_action_available("eject_magazine") and Input.is_action_just_pressed(INPUT_ACTIONS["eject_magazine"]):
		emit_signal("eject_magazine_requested")
	
	if _is_action_available("chamber_round") and Input.is_action_just_pressed(INPUT_ACTIONS["chamber_round"]):
		emit_signal("chamber_round_requested")
	
	if _is_action_available("examine_mode") and Input.is_action_just_pressed(INPUT_ACTIONS["examine_mode"]):
		emit_signal("examine_mode_requested")
	
	# Intent system
	if _is_action_available("cycle_intent") and Input.is_action_just_pressed(INPUT_ACTIONS["cycle_intent"]):
		emit_signal("cycle_intent_requested")
	
	# Direct intent selection
	if _is_action_available("intent_help") and Input.is_action_just_pressed(INPUT_ACTIONS["intent_help"]):
		emit_signal("set_intent_requested", 0)
	
	if _is_action_available("intent_disarm") and Input.is_action_just_pressed(INPUT_ACTIONS["intent_disarm"]):
		emit_signal("set_intent_requested", 1)
	
	if _is_action_available("intent_grab") and Input.is_action_just_pressed(INPUT_ACTIONS["intent_grab"]):
		emit_signal("set_intent_requested", 2)
	
	if _is_action_available("intent_harm") and Input.is_action_just_pressed(INPUT_ACTIONS["intent_harm"]):
		emit_signal("set_intent_requested", 3)
	
	# Combat mode
	if _is_action_available("toggle_combat") and Input.is_action_just_pressed(INPUT_ACTIONS["toggle_combat"]):
		emit_signal("toggle_combat_mode_requested")
	
	# Body part targeting
	_process_body_targeting_input()
	
	# Other actions
	if _is_action_available("toggle_point") and Input.is_action_just_pressed(INPUT_ACTIONS["toggle_point"]):
		emit_signal("toggle_point_mode_requested")
	
	if _is_action_available("toggle_pull") and Input.is_action_just_pressed(INPUT_ACTIONS["toggle_pull"]):
		emit_signal("toggle_pull_requested")
	
	if _is_action_available("toggle_rest") and Input.is_action_just_pressed(INPUT_ACTIONS["toggle_rest"]):
		emit_signal("toggle_rest_requested")

func _process_body_targeting_input():
	"""Handle body targeting input"""
	if _is_action_available("target_head") and Input.is_action_just_pressed(INPUT_ACTIONS["target_head"]):
		emit_signal("body_part_selected", "head")
	
	if _is_action_available("target_chest") and Input.is_action_just_pressed(INPUT_ACTIONS["target_chest"]):
		emit_signal("body_part_selected", "chest")
	
	if _is_action_available("target_groin") and Input.is_action_just_pressed(INPUT_ACTIONS["target_groin"]):
		emit_signal("body_part_selected", "groin")
	
	if _is_action_available("target_r_arm") and Input.is_action_just_pressed(INPUT_ACTIONS["target_r_arm"]):
		emit_signal("body_part_selected", "r_arm")
	
	if _is_action_available("target_l_arm") and Input.is_action_just_pressed(INPUT_ACTIONS["target_l_arm"]):
		emit_signal("body_part_selected", "l_arm")
	
	if _is_action_available("target_r_leg") and Input.is_action_just_pressed(INPUT_ACTIONS["target_r_leg"]):
		emit_signal("body_part_selected", "r_leg")
	
	if _is_action_available("target_l_leg") and Input.is_action_just_pressed(INPUT_ACTIONS["target_l_leg"]):
		emit_signal("body_part_selected", "l_leg")

func _check_run_toggle():
	"""Handle run key toggle logic"""
	if not _is_action_available("sprint"):
		return
		
	var run_key_pressed = Input.is_action_pressed(INPUT_ACTIONS["sprint"])
	
	if run_key_pressed != running:
		running = run_key_pressed
		emit_signal("toggle_run_requested", running)
#endregion

#region UI HANDLERS
func _handle_pause_toggle():
	"""Handle pause menu toggle"""
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("toggle_pause_menu"):
		var local_player = get_parent()
		game_manager.toggle_pause_menu(local_player)
	elif debug_mode:
		print("InputController: GameManager not found or missing toggle_pause_menu method")

func _handle_spawner_toggle():
	"""Handle admin spawner toggle"""
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("toggle_admin_spawner"):
		var local_player = get_parent()
		game_manager.toggle_admin_spawner(local_player)
	elif debug_mode:
		print("InputController: GameManager not found or missing toggle_admin_spawner method")
#endregion

#region ENTITY CONNECTION
func connect_to_entity(target_entity: Node):
	"""Connect this input controller to a player entity"""
	entity = target_entity
	
	if entity == null:
		if debug_mode:
			print("InputController: Entity is null")
		return
	
	if debug_mode:
		print("InputController: Connecting to entity: ", entity.name)
	
	connected_components.clear()
	failed_connections.clear()
	
	# Define component connections
	var component_connections = [
		# Movement connections
		["move_requested", "handle_move_input", "MovementComponent"],
		["toggle_run_requested", "toggle_run", "MovementComponent"],
		
		# Item interaction
		["swap_hand_requested", "swap_active_hand", "ItemInteractionComponent"],
		["drop_item_requested", "drop_active_item", "ItemInteractionComponent"],
		["pickup_requested", "try_pickup_nearest_item", "ItemInteractionComponent"],
		["toggle_throw_requested", "toggle_throw_mode", "ItemInteractionComponent"],
		["use_requested", "use_active_item", "ItemInteractionComponent"],
		
		# Weapon handling
		["toggle_weapon_wielding_requested", "handle_wielding_toggle", "WeaponHandlingComponent"],
		["eject_magazine_requested", "handle_eject_magazine", "WeaponHandlingComponent"],
		["chamber_round_requested", "handle_chamber_round", "WeaponHandlingComponent"],
		
		# Grab/Pull
		["cancel_action_requested", "release_grab", "GrabPullComponent"],
		
		# Intent
		["cycle_intent_requested", "cycle_intent", "InteractionComponent"],
		["set_intent_requested", "set_intent", "IntentComponent"],
		
		# Body targeting
		["body_part_selected", "handle_body_part_selection", "BodyTargetingComponent"],
		
		# Z-level movement
		["move_up_requested", "move_up", "ZLevelMovementComponent"],
		["move_down_requested", "move_down", "ZLevelMovementComponent"],
		
		# Posture
		["toggle_rest_requested", "handle_rest_toggle", "PostureComponent"]
	]
	
	# Connect to components
	for connection in component_connections:
		var signal_name = connection[0]
		var method_name = connection[1]
		var component_name = connection[2]
		_connect_to_component(signal_name, method_name, component_name)
	
	# Direct entity method connections
	var entity_connections = [
		["attack_self_requested", "attack_self"],
		["toggle_combat_mode_requested", "toggle_combat_mode"],
		["toggle_point_mode_requested", "toggle_point_mode"],
		["toggle_pull_requested", "toggle_pull"],
		["examine_mode_requested", "set_examine_mode"]
	]
	
	for connection in entity_connections:
		var signal_name = connection[0]
		var method_name = connection[1]
		_connect_to_entity_method(signal_name, method_name)
	
	if debug_mode:
		print("InputController: Connected ", connected_components.size(), " components")
		if failed_connections.size() > 0:
			print("InputController: Failed connections: ", failed_connections)

func _connect_to_component(signal_name: String, method_name: String, component_name: String):
	"""Connect a signal to a method in a specific component"""
	if entity == null:
		return
	
	var component = entity.get_node_or_null(component_name)
	if component and component.has_method(method_name):
		if is_connected(signal_name, Callable(component, method_name)):
			disconnect(signal_name, Callable(component, method_name))
		
		connect(signal_name, Callable(component, method_name))
		connected_components[component_name] = true
		
		if debug_mode:
			print("InputController: Connected ", signal_name, " to ", component_name, ".", method_name)
	else:
		# Try direct method on entity as fallback
		_connect_to_entity_method(signal_name, method_name)
		if component == null:
			failed_connections.append(component_name + " (not found)")
		else:
			failed_connections.append(component_name + "." + method_name + " (method not found)")

func _connect_to_entity_method(signal_name: String, method_name: String):
	"""Connect a signal to a method directly on the entity"""
	if entity == null:
		return
	
	if entity.has_method(method_name):
		if is_connected(signal_name, Callable(entity, method_name)):
			disconnect(signal_name, Callable(entity, method_name))
		
		connect(signal_name, Callable(entity, method_name))
		connected_components["entity." + method_name] = true
		
		if debug_mode:
			print("InputController: Connected ", signal_name, " to entity.", method_name)
	else:
		failed_connections.append("entity." + method_name + " (method not found)")
#endregion

#region UTILITY FUNCTIONS
func _is_action_available(action_key: String) -> bool:
	"""Check if an input action is available"""
	if not INPUT_ACTIONS.has(action_key):
		return false
	
	var action_name = INPUT_ACTIONS[action_key]
	return InputMap.has_action(action_name)

func set_active(active: bool):
	"""Enable or disable input processing"""
	set_process(active)
	
	if debug_mode:
		print("InputController: Set active to ", active)

func disable_for_npc():
	"""Disable input controller for NPC use"""
	set_active(false)
	entity = null
	connected_components.clear()
	
	if debug_mode:
		print("InputController: Disabled for NPC")

func get_connected_components() -> Dictionary:
	"""Get list of connected components"""
	return connected_components.duplicate()

func get_failed_connections() -> Array[String]:
	"""Get list of failed connection attempts"""
	return failed_connections.duplicate()

func is_entity_connected() -> bool:
	"""Check if an entity is connected"""
	return entity != null

func get_missing_actions() -> Array[String]:
	"""Get list of missing input actions"""
	var missing = []
	
	for action_type in INPUT_ACTIONS:
		var action_name = INPUT_ACTIONS[action_type]
		if not InputMap.has_action(action_name):
			missing.append(action_name)
	
	return missing

func reconnect_to_entity():
	"""Reconnect to the current entity (useful after component changes)"""
	if entity:
		var current_entity = entity
		entity = null
		connect_to_entity(current_entity)
#endregion

#region SAVE/LOAD
func save_state() -> Dictionary:
	"""Save input controller state"""
	return {
		"running": running,
		"pause_handling_enabled": pause_handling_enabled,
		"analog_deadzone": analog_deadzone,
		"entity_path": entity.get_path() if entity else "",
		"connected_components": connected_components
	}

func load_state(data: Dictionary):
	"""Load input controller state"""
	if "running" in data:
		running = data.running
	
	if "pause_handling_enabled" in data:
		pause_handling_enabled = data.pause_handling_enabled
	
	if "analog_deadzone" in data:
		analog_deadzone = data.analog_deadzone
	
	if "entity_path" in data and data.entity_path != "":
		var entity_node = get_node_or_null(data.entity_path)
		if entity_node:
			connect_to_entity(entity_node)
	
	if debug_mode:
		print("InputController: State loaded successfully")
#endregion
