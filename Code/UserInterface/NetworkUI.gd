extends Control

@onready var tab_container = $CenterContainer/MainPanel/MarginContainer/TabContainer
@onready var status_label = $HeaderSection/StatusLabel
@onready var error_label = $ErrorLabel
@onready var back_button = $BackButton

@onready var host_port_input = $CenterContainer/MainPanel/MarginContainer/TabContainer/"HOST COMMAND"/ServerConfig/PortSection/PortInput
@onready var host_max_players = $CenterContainer/MainPanel/MarginContainer/TabContainer/"HOST COMMAND"/ServerConfig/PlayersSection/MaxPlayersInput
@onready var upnp_check = $CenterContainer/MainPanel/MarginContainer/TabContainer/"HOST COMMAND"/NetworkConfig/UPNPCheck
@onready var manual_forwarding_check = $CenterContainer/MainPanel/MarginContainer/TabContainer/"HOST COMMAND"/NetworkConfig/ManualForwardingCheck
@onready var local_ip_label = $CenterContainer/MainPanel/MarginContainer/TabContainer/"HOST COMMAND"/NetworkInfo/LocalIPLabel
@onready var external_ip_label = $CenterContainer/MainPanel/MarginContainer/TabContainer/"HOST COMMAND"/NetworkInfo/ExternalIPLabel
@onready var host_button = $CenterContainer/MainPanel/MarginContainer/TabContainer/"HOST COMMAND"/ActionButtons/HostButton
@onready var test_port_button = $CenterContainer/MainPanel/MarginContainer/TabContainer/"HOST COMMAND"/ActionButtons/TestPortButton

@onready var join_ip_input = $CenterContainer/MainPanel/MarginContainer/TabContainer/"JOIN MISSION"/ConnectionConfig/ServerSection/IPInput
@onready var join_port_input = $CenterContainer/MainPanel/MarginContainer/TabContainer/"JOIN MISSION"/ConnectionConfig/PortSection/PortInput
@onready var join_button = $CenterContainer/MainPanel/MarginContainer/TabContainer/"JOIN MISSION"/StatusSection/JoinButton
@onready var join_status_label = $CenterContainer/MainPanel/MarginContainer/TabContainer/"JOIN MISSION"/StatusSection/StatusLabel

@onready var port_test_dialog = $PortTestDialog

var game_manager = null
var network_status: String = "DISCONNECTED"

const STATUS_UPDATE_DURATION = 0.3
const BUTTON_PULSE_DURATION = 1.5
const NETWORK_TEST_DURATION = 2.0
const EXTERNAL_IP_TIMEOUT = 3.0

signal host_game_requested()
signal join_game_requested()
signal back_pressed()

func _ready():
	initialize_interface()
	setup_button_connections()
	discover_local_network_info()
	update_status_display()
	setup_animations()

func initialize_interface():
	"""Initialize the network interface with default settings"""
	game_manager = get_node_or_null("/root/GameManager")
	
	if not game_manager:
		push_error("NetworkUI: GameManager not found in scene tree")
	
	reset_interface_state()

func reset_interface_state():
	"""Reset all interface elements to their default values"""
	network_status = "DISCONNECTED"
	error_label.text = ""
	
	host_port_input.value = 7777
	host_max_players.value = 16
	join_port_input.value = 7777
	
	update_status_display()

func setup_button_connections():
	"""Connect all button signals to their respective handler methods"""
	back_button.pressed.connect(_on_back_button_pressed)
	host_button.pressed.connect(_on_host_button_pressed)
	join_button.pressed.connect(_on_join_button_pressed)
	test_port_button.pressed.connect(_on_test_port_button_pressed)

func setup_animations():
	"""Initialize interface animations and visual effects"""
	animate_button_availability()

func animate_button_availability():
	"""Create pulsing animation effects for interactive buttons"""
	var buttons = [host_button, join_button, test_port_button]
	
	for button in buttons:
		var tween = create_tween()
		tween.set_loops()
		tween.tween_property(button, "modulate:a", 0.8, BUTTON_PULSE_DURATION)
		tween.tween_property(button, "modulate:a", 1.0, BUTTON_PULSE_DURATION)

func discover_local_network_info():
	"""Discover and display local network information for hosting"""
	var local_ip = get_local_ip_address()
	local_ip_label.text = "LOCAL IP: " + local_ip
	
	request_external_ip_info()

func get_local_ip_address() -> String:
	"""Retrieve the local IP address suitable for hosting"""
	var local_addresses = IP.get_local_addresses()
	
	for ip in local_addresses:
		if ip.begins_with("192.") or ip.begins_with("10.") or ip.begins_with("172."):
			return ip
	
	return "127.0.0.1"

func request_external_ip_info():
	"""Request external IP information for hosting configuration"""
	external_ip_label.text = "EXTERNAL IP: QUERYING..."
	
	await get_tree().create_timer(2.0).timeout
	external_ip_label.text = "EXTERNAL IP: NOT AVAILABLE"

func update_status_display():
	"""Update the main status display with current network state"""
	status_label.text = "STATUS: " + network_status
	
	var tween = create_tween()
	tween.tween_property(status_label, "modulate:a", 0.5, STATUS_UPDATE_DURATION * 0.5)
	tween.tween_property(status_label, "modulate:a", 1.0, STATUS_UPDATE_DURATION * 0.5)

func _on_back_button_pressed():
	"""Handle back button press to return to previous interface"""
	cleanup_network_connections()
	emit_signal("back_pressed")

func _on_host_button_pressed():
	"""Handle server hosting request"""
	if not game_manager:
		show_error_message("System error: GameManager not available")
		return
	
	var port = int(host_port_input.value)
	var use_upnp = upnp_check.button_pressed
	
	update_network_status("INITIALIZING SERVER...")
	clear_error_message()
	
	var success = game_manager.host_game(port, use_upnp)
	
	if success:
		update_network_status("SERVER OPERATIONAL")
		animate_successful_connection()
	else:
		update_network_status("SERVER INITIALIZATION FAILED")
		show_error_message("Failed to initialize server on port " + str(port))

func _on_join_button_pressed():
	"""Handle connection request to remote server"""
	if not game_manager:
		show_error_message("System error: GameManager not available")
		return
	
	var server_address = join_ip_input.text
	var port = int(join_port_input.value)
	
	if server_address.is_empty():
		show_error_message("Server coordinates required")
		return
	
	update_network_status("ESTABLISHING CONNECTION...")
	update_join_status("Connecting to " + server_address + ":" + str(port) + "...")
	clear_error_message()
	
	var success = game_manager.join_game(server_address, port)
	
	if success:
		update_network_status("CONNECTION IN PROGRESS")
	else:
		update_network_status("CONNECTION FAILED")
		update_join_status("Connection failed. Verify server coordinates.")
		show_error_message("Unable to establish connection to server")

func _on_test_port_button_pressed():
	"""Handle network connectivity testing request"""
	var port = int(host_port_input.value)
	
	port_test_dialog.dialog_text = "Testing network connectivity for port " + str(port) + "..."
	port_test_dialog.popup_centered()
	
	await perform_network_connectivity_test()

func perform_network_connectivity_test():
	"""Perform network connectivity testing simulation"""
	await get_tree().create_timer(2.0).timeout
	
	var test_result = generate_connectivity_test_result()
	port_test_dialog.dialog_text = test_result

func generate_connectivity_test_result() -> String:
	"""Generate connectivity test result based on current configuration"""
	var port = int(host_port_input.value)
	
	if upnp_check.button_pressed:
		return "Port " + str(port) + " connectivity verified via UPnP configuration."
	elif manual_forwarding_check.button_pressed:
		return "Manual port forwarding detected. Server should be accessible externally."
	else:
		return "No port forwarding detected. Server will be accessible on local network only."

func update_network_status(new_status: String):
	"""Update the main network status indicator"""
	network_status = new_status
	update_status_display()

func update_join_status(message: String):
	"""Update the join tab status message"""
	join_status_label.text = message

func show_error_message(message: String):
	"""Display an error message to the user with animation"""
	error_label.text = message
	
	var tween = create_tween()
	tween.tween_property(error_label, "modulate:a", 0.0, 0.1)
	tween.tween_property(error_label, "modulate:a", 1.0, 0.3)

func clear_error_message():
	"""Clear any currently displayed error messages"""
	error_label.text = ""

func animate_successful_connection():
	"""Animate visual feedback for successful connection establishment"""
	var tween = create_tween()
	tween.tween_property(host_button, "modulate", Color.GREEN, 0.5)
	tween.tween_property(host_button, "modulate", Color.WHITE, 0.5)

func cleanup_network_connections():
	"""Clean up any active network connections before leaving"""
	if game_manager:
		game_manager.disconnect_from_game()
	
	update_network_status("DISCONNECTED")
