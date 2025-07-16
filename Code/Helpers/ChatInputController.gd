extends Node
class_name ChatInputController

# References to systems
var player_controller = null
var input_controller = null
var chat_ui = null

func _ready():
	# Connect to the chat UI
	chat_ui = get_parent()
	
	if chat_ui:
		# Connect to chat state changed signal
		if chat_ui.has_signal("chat_state_changed"):
			chat_ui.connect("chat_state_changed", _on_chat_state_changed)
	
	# Find the player controller
	find_player_controller()

# Find the player controller in the scene
func find_player_controller():
	var players = get_tree().get_nodes_in_group("player_controller")
	if players.size() > 0:
		player_controller = players[0]
		
		# Get the input controller reference
		input_controller = player_controller.get_node_or_null("InputController")
		
		print("ChatInputController: Found player controller and input controller")
	else:
		# Retry after a short delay
		print("ChatInputController: Player controller not found, will retry later")
		await get_tree().create_timer(0.5).timeout
		find_player_controller()

# Handle chat state change
func _on_chat_state_changed(is_active):
	if player_controller == null:
		find_player_controller()
		return
	
	if is_active:
		# Disable player input
		disable_player_input()
	else:
		# Enable player input
		enable_player_input()

# Disable player input when chat is active
func disable_player_input():
	if player_controller:
		# Disable input processing in the player controller
		player_controller.set_process_input(false)
		player_controller.set_process_unhandled_input(false)
		
		# Disable input controller if available
		if input_controller:
			input_controller.set_process_input(false)
			input_controller.set_process_unhandled_input(false)
		
		print("ChatInputController: Player input disabled")

# Enable player input when chat is closed
func enable_player_input():
	if player_controller:
		# Re-enable input processing in the player controller
		player_controller.set_process_input(true)
		player_controller.set_process_unhandled_input(true)
		
		# Re-enable input controller if available
		if input_controller:
			input_controller.set_process_input(true)
			input_controller.set_process_unhandled_input(true)
		
		print("ChatInputController: Player input enabled")
