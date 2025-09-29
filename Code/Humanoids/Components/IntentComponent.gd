extends Node
class_name IntentComponent

#region EXPORTS AND CONFIGURATION
@export_group("Intent Settings")
@export var default_intent: Intent = Intent.HELP
@export var allow_intent_cycling: bool = true
@export var enable_visual_feedback: bool = true
@export var enable_audio_feedback: bool = true

@export_group("Combat Integration")
@export var auto_combat_mode: bool = true
@export var combat_intent_threshold: Intent = Intent.HARM
@export var update_weapon_targeting: bool = true

@export_group("Multiplayer")
@export var sync_intent_changes: bool = true
@export var allow_remote_intent_change: bool = false
@export var authority_only_changes: bool = true
#endregion

#region ENUMS
enum Intent {
	HELP = 0,
	DISARM = 1,
	GRAB = 2,
	HARM = 3
}
#endregion

#region CONSTANTS
# Intent names and display data
const INTENT_NAMES = ["HELP", "DISARM", "GRAB", "HARM"]
const INTENT_COLORS = ["#00FF00", "#FFFF00", "#FFA500", "#FF0000"]
const INTENT_ICONS = ["intent_help", "intent_disarm", "intent_grab", "intent_harm"]

# Intent descriptions
const INTENT_DESCRIPTIONS = {
	Intent.HELP: "Help intent - Peaceful interactions, pick up items, help others up",
	Intent.DISARM: "Disarm intent - Attempt to disarm or push targets",
	Intent.GRAB: "Grab intent - Grab and restrain targets",
	Intent.HARM: "Harm intent - Attack and damage targets"
}

# Action verbs for intents
const INTENT_ACTION_VERBS = {
	Intent.HELP: "help",
	Intent.DISARM: "disarm",
	Intent.GRAB: "grab",
	Intent.HARM: "attack"
}

# Push behaviors for intents
const INTENT_PUSH_BEHAVIORS = {
	Intent.HELP: "swap",    # Swap places
	Intent.DISARM: "push",  # Push away
	Intent.GRAB: "pull",    # Try to pull
	Intent.HARM: "shove"    # Aggressive shove
}
#endregion

#region SIGNALS
signal intent_changed(new_intent: int)
signal combat_mode_changed(enabled: bool)
#endregion

#region PROPERTIES
# Core references
var controller: Node = null
var sensory_system = null
var audio_system = null

# Multiplayer properties
var peer_id: int = 1
var is_local_player: bool = false

# Intent state
var intent: int = Intent.HELP
var previous_intent: int = Intent.HELP

# State tracking
var is_initialized: bool = false
#endregion

#region INITIALIZATION
func _ready():
	"""Initialize intent component"""
	if controller:
		_setup_multiplayer()
	
	intent = default_intent
	previous_intent = default_intent

func initialize(init_data: Dictionary):
	"""Initialize the intent component with data"""
	controller = init_data.get("controller")
	sensory_system = init_data.get("sensory_system")
	audio_system = init_data.get("audio_system")
	peer_id = init_data.get("peer_id", 1)
	
	_setup_multiplayer()
	
	# Set default intent
	intent = default_intent
	previous_intent = default_intent
	
	is_initialized = true

func _setup_multiplayer():
	"""Configure multiplayer settings"""
	if controller:
		peer_id = controller.get_meta("peer_id", 1)
		set_multiplayer_authority(peer_id)
		is_local_player = (multiplayer.get_unique_id() == peer_id)
#endregion

#region NETWORK SYNCHRONIZATION
@rpc("authority", "call_local", "reliable")
func sync_intent_change(new_intent: int, prev_intent: int):
	"""Sync intent change across network"""
	previous_intent = prev_intent
	intent = new_intent
	
	# Update combat mode
	if auto_combat_mode:
		var is_combat = (intent >= combat_intent_threshold)
		_update_combat_mode(is_combat)
	
	# Visual/audio feedback (only for the player who changed it)
	if is_local_player and enable_visual_feedback:
		_provide_feedback()
	
	# Emit signal for all clients
	emit_signal("intent_changed", intent)

@rpc("any_peer", "call_local", "reliable")
func network_set_intent(new_intent: int):
	"""Network version of set intent"""
	# Check permissions
	if not _can_change_intent():
		return
	
	set_intent(new_intent)

@rpc("any_peer", "call_local", "reliable")
func network_cycle_intent():
	"""Network version of cycle intent"""
	# Check permissions
	if not _can_change_intent():
		return
	
	cycle_intent()

func _can_change_intent() -> bool:
	"""Check if intent can be changed via network"""
	if not sync_intent_changes:
		return false
	
	if authority_only_changes:
		return multiplayer.get_remote_sender_id() == peer_id or is_multiplayer_authority()
	
	return allow_remote_intent_change or multiplayer.get_remote_sender_id() == peer_id
#endregion

#region PUBLIC INTERFACE
func set_intent(new_intent: int) -> bool:
	"""Set the current intent"""
	if not _is_valid_intent(new_intent):
		push_warning("IntentComponent: Invalid intent value: " + str(new_intent))
		return false
	
	if new_intent == intent:
		return true  # Already set
	
	if not is_local_player and not is_multiplayer_authority():
		return false
	
	var old_intent = intent
	
	# Sync across network if in multiplayer
	if sync_intent_changes and multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		sync_intent_change.rpc(new_intent, intent)
	else:
		# Apply locally for singleplayer
		previous_intent = intent
		intent = new_intent
		
		# Update combat mode
		if auto_combat_mode:
			var is_combat = (intent >= combat_intent_threshold)
			_update_combat_mode(is_combat)
		
		# Visual/audio feedback
		if enable_visual_feedback:
			_provide_feedback()
		
		# Emit signal
		emit_signal("intent_changed", intent)
	
	return true

func cycle_intent() -> int:
	"""Cycle through intents"""
	if not allow_intent_cycling:
		return intent
	
	if not is_local_player:
		return intent
	
	var new_intent = (intent + 1) % 4
	set_intent(new_intent)
	return new_intent

func handle_intent_input():
	"""Handle intent cycling input (called by input system)"""
	if not is_local_player:
		return
	
	if sync_intent_changes and multiplayer.has_multiplayer_peer():
		network_cycle_intent.rpc()
	else:
		cycle_intent()

func get_intent() -> int:
	"""Get current intent"""
	return intent

func get_intent_name(intent_value: int = -1) -> String:
	"""Get name of intent"""
	var target_intent = intent_value if intent_value >= 0 else intent
	
	if target_intent >= 0 and target_intent < INTENT_NAMES.size():
		return INTENT_NAMES[target_intent]
	
	return "UNKNOWN"

func get_intent_color(intent_value: int = -1) -> String:
	"""Get color code for intent"""
	var target_intent = intent_value if intent_value >= 0 else intent
	
	if target_intent >= 0 and target_intent < INTENT_COLORS.size():
		return INTENT_COLORS[target_intent]
	
	return "#FFFFFF"

func get_intent_icon(intent_value: int = -1) -> String:
	"""Get icon name for intent"""
	var target_intent = intent_value if intent_value >= 0 else intent
	
	if target_intent >= 0 and target_intent < INTENT_ICONS.size():
		return INTENT_ICONS[target_intent]
	
	return "intent_unknown"

func get_intent_description(intent_value: int = -1) -> String:
	"""Get description of what an intent does"""
	var target_intent = intent_value if intent_value >= 0 else intent
	return INTENT_DESCRIPTIONS.get(target_intent, "Unknown intent")

func is_combat_mode() -> bool:
	"""Check if in combat mode"""
	return intent >= combat_intent_threshold

func is_help_intent() -> bool:
	"""Check if in help intent"""
	return intent == Intent.HELP

func allows_harm() -> bool:
	"""Check if current intent allows harmful actions"""
	return intent == Intent.HARM

func get_all_intent_names() -> Array[String]:
	"""Get all available intent names"""
	return INTENT_NAMES.duplicate()

func get_intent_count() -> int:
	"""Get total number of intents"""
	return INTENT_NAMES.size()
#endregion

#region INTENT BEHAVIOR
func get_interaction_type(target: Node) -> String:
	"""Get interaction type based on intent and target"""
	# Self-interaction
	if target == controller or target == controller.get_parent():
		if intent == Intent.HELP:
			return "help_self"
		elif intent == Intent.HARM:
			return "harm_self"
		else:
			return "self"
	
	# Target interactions
	match intent:
		Intent.HELP:
			return "help"
		Intent.DISARM:
			return "disarm"
		Intent.GRAB:
			return "grab"
		Intent.HARM:
			return "harm"
		_:
			return "help"

func should_show_threat_cursor() -> bool:
	"""Check if threat cursor should be shown"""
	return intent in [Intent.DISARM, Intent.GRAB, Intent.HARM]

func get_intent_action_verb(intent_value: int = -1) -> String:
	"""Get action verb for intent"""
	var target_intent = intent_value if intent_value >= 0 else intent
	return INTENT_ACTION_VERBS.get(target_intent, "interact with")

func get_push_behavior(intent_value: int = -1) -> String:
	"""Get push behavior based on intent"""
	var target_intent = intent_value if intent_value >= 0 else intent
	return INTENT_PUSH_BEHAVIORS.get(target_intent, "push")

func get_damage_modifier() -> float:
	"""Get damage modifier for current intent"""
	match intent:
		Intent.HELP:
			return 0.0  # No damage intended
		Intent.DISARM:
			return 0.5  # Reduced damage
		Intent.GRAB:
			return 0.3  # Minimal damage
		Intent.HARM:
			return 1.0  # Full damage
		_:
			return 1.0

func should_cause_aggression() -> bool:
	"""Check if current intent should cause aggression in targets"""
	return intent in [Intent.GRAB, Intent.HARM]

func get_interaction_success_modifier() -> float:
	"""Get success rate modifier for interactions"""
	match intent:
		Intent.HELP:
			return 1.2  # Bonus to helpful actions
		Intent.DISARM:
			return 1.0  # Normal success rate
		Intent.GRAB:
			return 0.9  # Slightly reduced
		Intent.HARM:
			return 0.8  # Reduced for aggressive actions
		_:
			return 1.0
#endregion

#region PRIVATE HELPERS
func _update_combat_mode(enabled: bool):
	"""Update combat mode in connected systems"""
	# Update click system
	var click_system = controller.get_tree().get_first_node_in_group("click_system")
	if not click_system:
		click_system = controller.get_node_or_null("/root/World/ClickSystem")
	
	if click_system and click_system.has_method("set_combat_mode"):
		click_system.set_combat_mode(enabled)
	
	# Update weapon targeting if enabled
	if update_weapon_targeting:
		var weapon_component = controller.get_node_or_null("WeaponHandlingComponent")
		if weapon_component and weapon_component.has_method("set_combat_mode"):
			weapon_component.set_combat_mode(enabled)
	
	emit_signal("combat_mode_changed", enabled)

func _provide_feedback():
	"""Provide visual and audio feedback for intent change"""
	# Audio feedback
	if enable_audio_feedback and audio_system:
		audio_system.play_global_sound("intent_change", 0.3)
	
	# Visual feedback message
	if sensory_system:
		var message = "[color=%s]Intent: %s[/color]" % [INTENT_COLORS[intent], INTENT_NAMES[intent]]
		sensory_system.display_message(message)
	
	# Additional feedback for specific intents
	if sensory_system:
		match intent:
			Intent.HELP:
				if previous_intent == Intent.HARM:
					sensory_system.display_message("You lower your guard.")
			Intent.HARM:
				if previous_intent == Intent.HELP:
					sensory_system.display_message("You raise your fists!")
			Intent.GRAB:
				if previous_intent != Intent.GRAB:
					sensory_system.display_message("You prepare to grab.")
			Intent.DISARM:
				if previous_intent != Intent.DISARM:
					sensory_system.display_message("You prepare to disarm.")

func _is_valid_intent(intent_value: int) -> bool:
	"""Check if intent value is valid"""
	return intent_value >= 0 and intent_value < INTENT_NAMES.size()
#endregion

#region UTILITY FUNCTIONS
func get_intent_from_string(intent_string: String) -> int:
	"""Convert intent string to enum value"""
	var upper_string = intent_string.to_upper()
	var index = INTENT_NAMES.find(upper_string)
	return index if index >= 0 else Intent.HELP

func is_aggressive_intent(intent_value: int = -1) -> bool:
	"""Check if intent is considered aggressive"""
	var target_intent = intent_value if intent_value >= 0 else intent
	return target_intent in [Intent.GRAB, Intent.HARM]

func is_peaceful_intent(intent_value: int = -1) -> bool:
	"""Check if intent is considered peaceful"""
	var target_intent = intent_value if intent_value >= 0 else intent
	return target_intent == Intent.HELP

func get_random_intent() -> int:
	"""Get a random intent"""
	return randi() % INTENT_NAMES.size()

func can_perform_action(action_name: String) -> bool:
	"""Check if current intent allows specific actions"""
	match action_name.to_lower():
		"heal", "help", "assist":
			return intent == Intent.HELP
		"disarm", "shove":
			return intent in [Intent.DISARM, Intent.HARM]
		"grab", "restrain":
			return intent in [Intent.GRAB, Intent.HARM]
		"attack", "harm", "damage":
			return intent == Intent.HARM
		_:
			return true  # Allow general actions
#endregion

#region SAVE/LOAD
func save_state() -> Dictionary:
	"""Save intent state"""
	return {
		"intent": intent,
		"previous_intent": previous_intent,
		"default_intent": default_intent,
		"allow_intent_cycling": allow_intent_cycling,
		"auto_combat_mode": auto_combat_mode,
		"peer_id": peer_id
	}

func load_state(data: Dictionary):
	"""Load intent state"""
	if "intent" in data and _is_valid_intent(data.intent):
		intent = data.intent
	
	if "previous_intent" in data and _is_valid_intent(data.previous_intent):
		previous_intent = data.previous_intent
	
	if "default_intent" in data and _is_valid_intent(data.default_intent):
		default_intent = data.default_intent
	
	if "allow_intent_cycling" in data:
		allow_intent_cycling = data.allow_intent_cycling
	
	if "auto_combat_mode" in data:
		auto_combat_mode = data.auto_combat_mode
	
	if "peer_id" in data:
		peer_id = data.peer_id
		set_multiplayer_authority(peer_id)
	
	# Update systems with current intent
	if auto_combat_mode:
		var is_combat = (intent >= combat_intent_threshold)
		_update_combat_mode(is_combat)
	
	emit_signal("intent_changed", intent)
#endregion
