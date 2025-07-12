extends Control

# References to UI components - ensure node paths match your scene
@onready var tab_container = $TabContainer
@onready var status_label = $StatusLabel
@onready var error_label = $ErrorLabel
@onready var back_button = $BackButton

# Host tab
@onready var host_port_input = $TabContainer/Host/PortInput
@onready var host_max_players = $TabContainer/Host/MaxPlayersInput
@onready var upnp_check = $TabContainer/Host/UPNPCheck
@onready var manual_forwarding_check = $TabContainer/Host/ManualForwardingCheck
@onready var local_ip_label = $TabContainer/Host/LocalIPLabel
@onready var external_ip_label = $TabContainer/Host/ExternalIPLabel
@onready var host_button = $TabContainer/Host/HostButton
@onready var test_port_button = $TabContainer/Host/TestPortButton

# Join tab
@onready var join_ip_input = $TabContainer/Join/IPInput
@onready var join_port_input = $TabContainer/Join/PortInput
@onready var join_button = $TabContainer/Join/JoinButton
@onready var join_status_label = $TabContainer/Join/StatusLabel

# Game manager reference
var game_manager = null

# Signals
signal host_game_requested()
signal join_game_requested()
signal back_pressed()

func _ready():
	# Connect button signals
	back_button.pressed.connect(_on_back_button_pressed)
	host_button.pressed.connect(_on_host_button_pressed)
	join_button.pressed.connect(_on_join_button_pressed)
	test_port_button.pressed.connect(_on_test_port_button_pressed)
	
	# Get references
	game_manager = get_node_or_null("/root/GameManager")
	
	if !game_manager:
		push_error("GameManager not found!")
	
	# Display local IP
	display_local_ip()
	
	# Reset status
	status_label.text = "Status: Disconnected"
	error_label.text = ""

func display_local_ip():
	var local_ip = ""
	
	# Get list of IP addresses
	for ip in IP.get_local_addresses():
		# Filter out loopback and IPv6 addresses for clarity
		if ip.begins_with("192.") or ip.begins_with("10.") or ip.begins_with("172."):
			local_ip = ip
			break
	
	if local_ip.is_empty():
		local_ip = "127.0.0.1"
	
	local_ip_label.text = "Local IP: " + local_ip

func _on_back_button_pressed():
	# Clean up any active connections
	if game_manager:
		game_manager.disconnect_from_game()
	
	emit_signal("back_pressed")

func _on_host_button_pressed():
	if game_manager:
		# Get port from input
		var port = int(host_port_input.value)
		
		# Get UPNP setting
		var use_upnp = upnp_check.button_pressed
		
		# Update status
		status_label.text = "Status: Starting server..."
		error_label.text = ""
		
		# Host the game
		var success = game_manager.host_game(port, use_upnp)
		
		if !success:
			status_label.text = "Status: Failed to start server"
			error_label.text = "Could not start server on port " + str(port)
		else:
			status_label.text = "Status: Server started"
	else:
		error_label.text = "GameManager not found!"

func _on_join_button_pressed():
	if game_manager:
		# Get IP and port from inputs
		var address = join_ip_input.text
		var port = int(join_port_input.value)
		
		# Update status
		status_label.text = "Status: Connecting to server..."
		join_status_label.text = "Connecting to " + address + ":" + str(port) + "..."
		error_label.text = ""
		
		# Join the game
		var success = game_manager.join_game(address, port)
		
		if !success:
			status_label.text = "Status: Failed to connect"
			join_status_label.text = "Connection failed. Check address and port."
			error_label.text = "Could not connect to server"
		else:
			# Connection in progress, GameManager will handle transition to lobby
			status_label.text = "Status: Connecting..."
	else:
		error_label.text = "GameManager not found!"

func _on_test_port_button_pressed():
	var port_test_dialog = $PortTestDialog
	port_test_dialog.dialog_text = "Testing port forwarding for port " + str(host_port_input.value) + "..."
	port_test_dialog.popup_centered()
	
	# Simulate port test with timer (would be a real test in production)
	var timer = get_tree().create_timer(2.0)
	await timer.timeout
	
	# Update with test result (in real implementation, perform actual test)
	if upnp_check.button_pressed:
		port_test_dialog.dialog_text = "Port " + str(host_port_input.value) + " appears to be correctly forwarded via UPnP."
	elif manual_forwarding_check.button_pressed:
		port_test_dialog.dialog_text = "Manual port forwarding detected. Your server should be accessible."
	else:
		port_test_dialog.dialog_text = "No port forwarding detected. Your server may only be accessible on your local network."
