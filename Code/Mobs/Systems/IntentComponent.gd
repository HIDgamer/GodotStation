extends Node
class_name IntentComponent

## Handles the intent system (help, disarm, grab, harm)

#region ENUMS
enum Intent {
	HELP = 0,
	DISARM = 1,
	GRAB = 2,
	HARM = 3
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

# Intent state
var intent: int = Intent.HELP
var previous_intent: int = Intent.HELP

# Intent names and colors
const INTENT_NAMES = ["HELP", "DISARM", "GRAB", "HARM"]
const INTENT_COLORS = ["#00FF00", "#FFFF00", "#FFA500", "#FF0000"]
const INTENT_ICONS = ["intent_help", "intent_disarm", "intent_grab", "intent_harm"]
#endregion

func initialize(init_data: Dictionary):
	"""Initialize the intent component"""
	controller = init_data.get("controller")
	sensory_system = init_data.get("sensory_system")
	audio_system = init_data.get("audio_system")
	
	# Set default intent
	intent = Intent.HELP

#region PUBLIC INTERFACE
func set_intent(new_intent: int) -> bool:
	"""Set the current intent"""
	if new_intent < 0 or new_intent > 3:
		print("IntentComponent: Invalid intent value: ", new_intent)
		return false
	
	if new_intent == intent:
		return true  # Already set
	
	previous_intent = intent
	intent = new_intent
	
	# Update combat mode
	var is_combat = (intent == Intent.HARM)
	update_combat_mode(is_combat)
	
	# Visual/audio feedback
	provide_feedback()
	
	# Emit signal
	emit_signal("intent_changed", intent)
	
	return true

func cycle_intent() -> int:
	"""Cycle through intents"""
	var new_intent = (intent + 1) % 4
	set_intent(new_intent)
	return new_intent

func get_intent() -> int:
	"""Get current intent"""
	return intent

func get_intent_name(intent_value: int = -1) -> String:
	"""Get name of intent"""
	if intent_value == -1:
		intent_value = intent
	
	if intent_value >= 0 and intent_value < INTENT_NAMES.size():
		return INTENT_NAMES[intent_value]
	
	return "UNKNOWN"

func get_intent_color(intent_value: int = -1) -> String:
	"""Get color code for intent"""
	if intent_value == -1:
		intent_value = intent
	
	if intent_value >= 0 and intent_value < INTENT_COLORS.size():
		return INTENT_COLORS[intent_value]
	
	return "#FFFFFF"

func get_intent_icon(intent_value: int = -1) -> String:
	"""Get icon name for intent"""
	if intent_value == -1:
		intent_value = intent
	
	if intent_value >= 0 and intent_value < INTENT_ICONS.size():
		return INTENT_ICONS[intent_value]
	
	return "intent_unknown"

func is_combat_mode() -> bool:
	"""Check if in combat mode (harm intent)"""
	return intent == Intent.HARM

func is_help_intent() -> bool:
	"""Check if in help intent"""
	return intent == Intent.HELP

func allows_harm() -> bool:
	"""Check if current intent allows harmful actions"""
	return intent == Intent.HARM

func get_intent_description(intent_value: int = -1) -> String:
	"""Get description of what an intent does"""
	if intent_value == -1:
		intent_value = intent
	
	match intent_value:
		Intent.HELP:
			return "Help intent - Peaceful interactions, pick up items, help others up"
		Intent.DISARM:
			return "Disarm intent - Attempt to disarm or push targets"
		Intent.GRAB:
			return "Grab intent - Grab and restrain targets"
		Intent.HARM:
			return "Harm intent - Attack and damage targets"
		_:
			return "Unknown intent"

func handle_input():
	"""Handle intent-related input"""
	# This is called from the main controller's input processing
	if Input.is_action_just_pressed("mode_help"):
		set_intent(Intent.HELP)
	elif Input.is_action_just_pressed("mode_disarm"):
		set_intent(Intent.DISARM)
	elif Input.is_action_just_pressed("mode_grab"):
		set_intent(Intent.GRAB)
	elif Input.is_action_just_pressed("mode_harm"):
		set_intent(Intent.HARM)
	elif Input.is_action_just_pressed("cycle_intent"):
		cycle_intent()
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

func get_intent_action_verb() -> String:
	"""Get action verb for current intent"""
	match intent:
		Intent.HELP:
			return "help"
		Intent.DISARM:
			return "disarm"
		Intent.GRAB:
			return "grab"
		Intent.HARM:
			return "attack"
		_:
			return "interact with"

func get_push_behavior() -> String:
	"""Get push behavior based on intent"""
	match intent:
		Intent.HELP:
			return "swap"  # Swap places
		Intent.DISARM:
			return "push"  # Push away
		Intent.GRAB:
			return "pull"  # Try to pull
		Intent.HARM:
			return "shove" # Aggressive shove
		_:
			return "push"
#endregion

#region PRIVATE HELPERS
func update_combat_mode(enabled: bool):
	"""Update combat mode in connected systems"""
	# Update click system
	var click_system = controller.get_tree().get_first_node_in_group("click_system")
	if not click_system:
		click_system = controller.get_node_or_null("/root/World/ClickSystem")
	
	if click_system and click_system.has_method("set_combat_mode"):
		click_system.set_combat_mode(enabled)
	
	emit_signal("combat_mode_changed", enabled)

func provide_feedback():
	"""Provide visual and audio feedback for intent change"""
	# Audio feedback
	if audio_system:
		audio_system.play_global_sound("intent_change", 0.3)
	
	# Visual feedback message
	if sensory_system:
		var message = "[color=%s]Intent: %s[/color]" % [INTENT_COLORS[intent], INTENT_NAMES[intent]]
		sensory_system.display_message(message)
	
	# Additional feedback for specific intents
	match intent:
		Intent.HELP:
			if previous_intent == Intent.HARM and sensory_system:
				sensory_system.display_message("You lower your guard.")
		Intent.HARM:
			if previous_intent == Intent.HELP and sensory_system:
				sensory_system.display_message("You raise your fists!")
#endregion

#region SAVE/LOAD
func save_state() -> Dictionary:
	"""Save intent state"""
	return {
		"intent": intent,
		"previous_intent": previous_intent
	}

func load_state(data: Dictionary):
	"""Load intent state"""
	if "intent" in data:
		intent = data["intent"]
	if "previous_intent" in data:
		previous_intent = data["previous_intent"]
	
	# Update systems
	update_combat_mode(intent == Intent.HARM)
#endregion
