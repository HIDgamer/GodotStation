extends Node
class_name InputController

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
signal toggle_pause_menu_requested()
signal reload_weapon_requested()
signal examine_mode_requested()
signal toggle_rest_requested()
signal use_requested()

# Weapon system signals
signal toggle_firing_mode_requested()
signal toggle_weapon_safety_requested()
signal unload_weapon_requested()
signal toggle_weapon_wielding_requested()

# The entity controlled by this input controller
var entity
var pause_handling_enabled: bool = true

# Input mapping (action names that should be defined in project settings)
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
	"reload_weapon": "reload",
	"use": "interact",
	"examine_mode": "examine_mode",
	
	# Weapon controls
	"toggle_firing_mode": "fire_mode",
	"toggle_weapon_safety": "weapon_safety",
	"unload_weapon": "unload",
	"toggle_weapon_wielding": "interact",
	
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
	"toggle_rest": "rest"
}

# Deadzone for analog stick movement
const ANALOG_DEADZONE = 0.2

# For toggled states
var running: bool = false
var initialized: bool = false

var connection_attempts: int = 0
var max_connection_attempts: int = 10
var pending_connections: bool = false
var deferred_connection_timer: Timer = null

func _ready():
	# Verify that required inputs are defined in project settings
	check_input_actions()
	
	# Try to connect to entity if we're a child of one
	var parent = get_parent()
	if parent and (parent.has_node("MovementComponent") or parent.name == "GridMovementController"):
		call_deferred("connect_to_entity", parent)
	
	initialized = true

# Check if all needed input actions are defined
func check_input_actions():
	var undefined_actions = []
	
	for action_type in INPUT_ACTIONS:
		var action_name = INPUT_ACTIONS[action_type]
		if not InputMap.has_action(action_name):
			undefined_actions.append(action_name)
	
	if undefined_actions.size() > 0:
		push_warning("InputController: The following input actions are not defined in the project settings: " + str(undefined_actions))
		print_input_setup_guide()

# Print a guide for setting up inputs
func print_input_setup_guide():
	print("\n=== InputController Setup Guide ===")
	print("You need to define the following input actions in Project Settings > Input Map:")
	
	for action_type in INPUT_ACTIONS:
		var action_name = INPUT_ACTIONS[action_type]
		print("- " + action_name + " (for " + action_type + ")")
	
	print("\nExample key bindings:")
	print("- up, down, left, right: W, S, A, D or Arrow keys")
	print("- modifier_shift: Shift (for running)")
	print("- move_up: E (for moving up z-level)")
	print("- move_down: Q (for moving down z-level)")
	print("- swap_hand: X (switch hands)")
	print("- drop_item: Q (drop held item)")
	print("- pickup: G (pick up items)")
	print("- attack_self: Z (use item on self)")
	print("- toggle_throw: R (toggle throw mode)")
	print("- reload: R (reload weapon)")
	print("- examine_mode: Alt (examine mode)")
	print("- fire_mode: F (toggle weapon firing mode)")
	print("- weapon_safety: V (toggle weapon safety)")
	print("- unload: U (unload weapon)")
	print("- wield_weapon: T (toggle two-handed wielding)")
	print("- target_* keys: Numpad 1-9 (for targeting body parts)")
	print("- cycle_intent: Tab (cycle through intents)")
	print("- intent_* keys: 1-4 (for direct intent selection)")
	print("=================================\n")

func _process(delta):
	if !initialized:
		return
		
	process_movement_input()
	process_action_input()

# Process directional movement input
func process_movement_input():
	var input_dir = Vector2.ZERO
	
	# Keyboard movement
	if Input.is_action_pressed(INPUT_ACTIONS["move_right"]):
		input_dir.x += 1
	if Input.is_action_pressed(INPUT_ACTIONS["move_left"]):
		input_dir.x -= 1
	if Input.is_action_pressed(INPUT_ACTIONS["move_down"]):
		input_dir.y += 1
	if Input.is_action_pressed(INPUT_ACTIONS["move_up"]):
		input_dir.y -= 1
	
	# Normalize for consistent speed in all directions
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()
	
	# Only emit signal if there's movement input
	if input_dir != Vector2.ZERO:
		# DON'T change this emit statement - we WANT continuous input for smooth movement
		emit_signal("move_requested", input_dir)
	
	# Process run toggling
	check_run_toggle()
	
	# Process Z-level movement
	if Input.is_action_just_pressed(INPUT_ACTIONS["move_z_up"]):
		emit_signal("move_up_requested")
	
	if Input.is_action_just_pressed(INPUT_ACTIONS["move_z_down"]):
		emit_signal("move_down_requested")

# Process non-movement action inputs
func process_action_input():
	# Pause menu toggle - only if enabled
	if pause_handling_enabled and Input.is_action_just_pressed(INPUT_ACTIONS["toggle_pause"]):
		print("InputController: ESC key pressed, toggling pause menu")
		emit_signal("toggle_pause_menu_requested")
	
	# Item manipulation
	if Input.is_action_just_pressed(INPUT_ACTIONS["swap_hand"]):
		emit_signal("swap_hand_requested")
	
	if Input.is_action_just_pressed(INPUT_ACTIONS["cancel"]):
		emit_signal("cancel_action_requested")
	
	if Input.is_action_just_pressed(INPUT_ACTIONS["use"]):
		emit_signal("use_requested")
	
	if Input.is_action_just_pressed(INPUT_ACTIONS["drop_item"]):
		emit_signal("drop_item_requested")
	
	if Input.is_action_just_pressed(INPUT_ACTIONS["pickup_item"]):
		emit_signal("pickup_requested")
	
	if Input.is_action_just_pressed(INPUT_ACTIONS["attack_self"]):
		emit_signal("attack_self_requested")
		
	if Input.is_action_just_pressed(INPUT_ACTIONS["toggle_throw"]):
		emit_signal("toggle_throw_requested")
	
	# Weapon management
	if Input.is_action_just_pressed(INPUT_ACTIONS["reload_weapon"]):
		emit_signal("reload_weapon_requested")
	
	if Input.is_action_just_pressed(INPUT_ACTIONS["toggle_firing_mode"]):
		emit_signal("toggle_firing_mode_requested")
	
	if Input.is_action_just_pressed(INPUT_ACTIONS["toggle_weapon_safety"]):
		emit_signal("toggle_weapon_safety_requested")
	
	if Input.is_action_just_pressed(INPUT_ACTIONS["unload_weapon"]):
		emit_signal("unload_weapon_requested")
	
	if Input.is_action_just_pressed(INPUT_ACTIONS["toggle_weapon_wielding"]):
		emit_signal("toggle_weapon_wielding_requested")
	
	if Input.is_action_just_pressed(INPUT_ACTIONS["examine_mode"]):
		emit_signal("examine_mode_requested")
	
	# Intent controls
	if Input.is_action_just_pressed(INPUT_ACTIONS["cycle_intent"]):
		emit_signal("cycle_intent_requested")
	
	# Direct intent selection
	if Input.is_action_just_pressed(INPUT_ACTIONS["intent_help"]):
		emit_signal("set_intent_requested", 0) # HELP
	
	if Input.is_action_just_pressed(INPUT_ACTIONS["intent_disarm"]):
		emit_signal("set_intent_requested", 1) # DISARM
	
	if Input.is_action_just_pressed(INPUT_ACTIONS["intent_grab"]):
		emit_signal("set_intent_requested", 2) # GRAB
	
	if Input.is_action_just_pressed(INPUT_ACTIONS["intent_harm"]):
		emit_signal("set_intent_requested", 3) # HARM
	
	# Combat mode
	if Input.is_action_just_pressed(INPUT_ACTIONS["toggle_combat"]):
		emit_signal("toggle_combat_mode_requested")
	
	# Body part targeting
	if Input.is_action_just_pressed(INPUT_ACTIONS["target_head"]):
		emit_signal("body_part_selected", "head")
	
	if Input.is_action_just_pressed(INPUT_ACTIONS["target_chest"]):
		emit_signal("body_part_selected", "chest")
	
	if Input.is_action_just_pressed(INPUT_ACTIONS["target_groin"]):
		emit_signal("body_part_selected", "groin")
	
	if Input.is_action_just_pressed(INPUT_ACTIONS["target_r_arm"]):
		emit_signal("body_part_selected", "r_arm")
	
	if Input.is_action_just_pressed(INPUT_ACTIONS["target_l_arm"]):
		emit_signal("body_part_selected", "l_arm")
	
	if Input.is_action_just_pressed(INPUT_ACTIONS["target_r_leg"]):
		emit_signal("body_part_selected", "r_leg")
	
	if Input.is_action_just_pressed(INPUT_ACTIONS["target_l_leg"]):
		emit_signal("body_part_selected", "l_leg")
	
	# Other actions
	if Input.is_action_just_pressed(INPUT_ACTIONS["toggle_point"]):
		emit_signal("toggle_point_mode_requested")
	
	if Input.is_action_just_pressed(INPUT_ACTIONS["toggle_pull"]):
		emit_signal("toggle_pull_requested")
	
	if Input.is_action_just_pressed(INPUT_ACTIONS["toggle_rest"]):
		emit_signal("toggle_rest_requested")

# Handle run toggling with shift
func check_run_toggle():
	var run_key_pressed = Input.is_action_pressed(INPUT_ACTIONS["sprint"])
	
	if run_key_pressed != running:
		running = run_key_pressed
		emit_signal("toggle_run_requested", running)

# Connect this input controller to a GridMovementController
func connect_to_entity(target_entity: Node):
	# If entity is null, setup a deferred connection
	if target_entity == null:
		print("InputController: Entity is null, setting up deferred connection")
		pending_connections = true
		
		# Set up a timer for retry if not already created
		if deferred_connection_timer == null:
			deferred_connection_timer = Timer.new()
			deferred_connection_timer.wait_time = 0.5  # Check every half second
			deferred_connection_timer.one_shot = false
			deferred_connection_timer.timeout.connect(attempt_deferred_connection)
			add_child(deferred_connection_timer)
			deferred_connection_timer.start()
		
		# Store the reference anyway (it's null for now)
		entity = target_entity
		return
	
	# Otherwise, proceed with normal connection
	entity = target_entity
	connection_attempts = 0
	pending_connections = false
	
	# Try to find the GameManager in the scene tree
	var game_manager = get_node_or_null("/root/GameManager")
	
	if game_manager:
		if game_manager.has_method("toggle_pause_menu"):
			# Disconnect first to avoid duplicate connections
			if is_connected("toggle_pause_menu_requested", Callable(game_manager, "toggle_pause_menu")):
				disconnect("toggle_pause_menu_requested", Callable(game_manager, "toggle_pause_menu"))
				
			# Connect the signal
			connect("toggle_pause_menu_requested", Callable(game_manager, "toggle_pause_menu"))
			print("InputController: Connected pause menu toggle signal")
		else:
			print("InputController: GameManager does not have toggle_pause_menu method")
	else:
		print("InputController: Could not find GameManager at /root/GameManager")
	
	# Movement - handled by MovementComponent through GridMovementController
	connect_if_available_to_component("move_requested", "handle_move_input", "MovementComponent")
	connect_if_available_to_component("toggle_run_requested", "toggle_run", "MovementComponent")
	
	# Item interaction - handled by ItemInteractionComponent
	connect_if_available_to_component("swap_hand_requested", "swap_active_hand", "ItemInteractionComponent")
	connect_if_available_to_component("drop_item_requested", "drop_active_item", "ItemInteractionComponent")
	connect_if_available_to_component("pickup_requested", "try_pickup_nearest_item", "ItemInteractionComponent")
	connect_if_available_to_component("toggle_throw_requested", "toggle_throw_mode", "ItemInteractionComponent")
	
	# Grab/Pull - handled by GrabPullComponent
	connect_if_available_to_component("cancel_action_requested", "release_grab", "GrabPullComponent")
	connect_if_available_to_component("use_requested", "upgrade_grab", "GrabPullComponent")
	
	# Intent - handled by IntentComponent
	connect_if_available_to_component("cycle_intent_requested", "cycle_intent", "InteractionComponent")
	connect_if_available_to_component("set_intent_requested", "set_intent", "InteractionComponent")
	
	# Body targeting - handled by BodyTargetingComponent
	connect_if_available_to_component("body_part_selected", "handle_body_part_selection", "BodyTargetingComponent")
	
	# Z-level movement - handled by ZLevelMovementComponent
	connect_if_available_to_component("move_up_requested", "move_up", "ZLevelMovementComponent")
	connect_if_available_to_component("move_down_requested", "move_down", "ZLevelMovementComponent")
	
	# Posture - handled by PostureComponent
	connect_if_available_to_component("toggle_rest_requested", "handle_rest_toggle", "PostureComponent")
	
	# Direct controller methods
	connect_if_available("attack_self_requested", "attack_self")
	connect_if_available("toggle_combat_mode_requested", "toggle_combat_mode")
	connect_if_available("toggle_point_mode_requested", "toggle_point_mode")
	connect_if_available("toggle_pull_requested", "toggle_pull")
	connect_if_available("reload_weapon_requested", "handle_weapon_reload")
	connect_if_available("examine_mode_requested", "set_examine_mode")
	
	# Weapon system methods
	connect_if_available("toggle_firing_mode_requested", "toggle_weapon_firing_mode")
	connect_if_available("toggle_weapon_safety_requested", "toggle_weapon_safety")
	connect_if_available("unload_weapon_requested", "unload_weapon")
	connect_if_available("toggle_weapon_wielding_requested", "toggle_weapon_wielding")
	
	# Stop the timer if it was running
	if deferred_connection_timer != null and deferred_connection_timer.is_inside_tree():
		deferred_connection_timer.stop()
	
	print("InputController: Successfully connected to entity: ", entity.name if entity else "NULL")

func attempt_deferred_connection():
	# Increment connection attempts counter
	connection_attempts += 1
	
	# Check if we should continue attempting to connect
	if !pending_connections or connection_attempts >= max_connection_attempts:
		if connection_attempts >= max_connection_attempts:
			print("InputController: Max connection attempts reached, giving up")
		
		# Stop the timer
		if deferred_connection_timer:
			deferred_connection_timer.stop()
		return
	
	print("InputController: Attempting deferred connection (attempt " + str(connection_attempts) + ")")
	
	# Try to find the entity
	var potential_entity = null
	
	# Check if we're a child of an entity already
	var parent = get_parent()
	if parent:
		potential_entity = parent
	
	# If we found an entity, connect to it
	if potential_entity:
		print("InputController: Found potential entity: " + potential_entity.name)
		connect_to_entity(potential_entity)
	else:
		print("InputController: No potential entity found, will retry")

# Connect to a specific component's method through the GridMovementController
func connect_if_available_to_component(signal_name: String, method_name: String, component_name: String) -> bool:
	if entity == null:
		print("InputController: Cannot connect signal " + signal_name + " - entity is null")
		return false
	
	# Get the component from the entity
	var component = entity.get_node_or_null(component_name)
	if component:
		if is_connected(signal_name, Callable(component, method_name)):
			disconnect(signal_name, Callable(component, method_name))
		
		connect(signal_name, Callable(component, method_name))
		print("InputController: Connected signal " + signal_name + " to " + component_name + "." + method_name)
		return true
	else:
		# Try direct method on entity as fallback
		return connect_if_available(signal_name, method_name)

# Utility method to connect signals if the target method exists
func connect_if_available(signal_name: String, method_name: String) -> bool:
	# Safety check - make sure entity is valid
	if entity == null:
		print("InputController: Cannot connect signal " + signal_name + " - entity is null")
		return false
	
	# Try direct methods on the entity
	if entity.has_method(method_name):
		if is_connected(signal_name, Callable(entity, method_name)):
			disconnect(signal_name, Callable(entity, method_name))
		
		connect(signal_name, Callable(entity, method_name))
		print("InputController: Connected signal " + signal_name + " to method " + method_name)
		return true
	
	print("InputController: Method " + method_name + " not found in entity")
	return false

func set_active(active: bool):
	set_process(active)

func disable_for_npc():
	set_active(false)
	entity = null  # Clear entity reference
	print("InputController: Disabled for NPC")

func _exit_tree():
	# Clean up timer
	if deferred_connection_timer and deferred_connection_timer.is_inside_tree():
		deferred_connection_timer.stop()
		deferred_connection_timer.queue_free()
