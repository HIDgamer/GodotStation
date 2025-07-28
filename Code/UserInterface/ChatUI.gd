extends CanvasLayer
class_name EnhancedChatUI

# Chat configuration
const MAX_MESSAGES = 200  # Maximum number of messages to keep in history
const MAX_HISTORY = 20    # Maximum command history to remember
const DEFAULT_CHAT_KEY = KEY_T  # Default key to open chat
const ANIMATION_DURATION = 0.3  # Duration for animations
const INACTIVE_TRANSPARENCY = 0.7  # Transparency when chat is inactive but visible
const MAX_MESSAGE_LENGTH = 500  # Maximum characters per message
const CHAT_RATE_LIMIT = 2.0  # Seconds between messages for rate limiting

# Signal when a message is sent - for multiplayer integration
signal message_sent(text, channel)
signal command_executed(command, args)

# Message categories and channels
var message_categories = {
	"default": {"color": Color(0.9, 0.9, 0.9), "prefix": ""},
	"system": {"color": Color(0.9, 0.9, 0.2), "prefix": "[SYSTEM] "},
	"radio": {"color": Color(0.2, 0.8, 0.2), "prefix": "[RADIO] "},
	"warning": {"color": Color(0.9, 0.5, 0.1), "prefix": "[WARNING] "},
	"alert": {"color": Color(0.9, 0.2, 0.2), "prefix": "[ALERT] "},
	"whisper": {"color": Color(0.7, 0.7, 0.9), "prefix": "[WHISPER] "},
	"emote": {"color": Color(0.8, 0.6, 0.8), "prefix": "* "},
	"ooc": {"color": Color(0.5, 0.8, 0.9), "prefix": "[OOC] "}
}

# Chat channels
var chat_channels = {
	"all": {"color": Color(0.9, 0.9, 0.9), "icon": "🌐", "filter": ""},
	"local": {"color": Color(0.8, 0.8, 0.8), "icon": "📢", "filter": ""},
	"radio": {"color": Color(0.2, 0.8, 0.2), "icon": "📻", "filter": "radio"},
	"ooc": {"color": Color(0.5, 0.8, 0.9), "icon": "💬", "filter": "ooc"},
	"admin": {"color": Color(0.9, 0.2, 0.2), "icon": "⚠️", "filter": "admin"}
}

# Chat state
var is_chat_open = false  # Is the chat window fully open
var is_chat_visible = false  # Is chat visible at all (even partially)
var is_chat_inactive = false  # Is chat in the inactive/transparent state
var active_channel = "all"  # Current active channel
var chat_key = DEFAULT_CHAT_KEY  # Key to open chat
var chat_history = []  # Full message history

# Input history
var input_history = []
var input_history_index = -1
var current_input = ""

# Multiplayer state
var local_peer_id = 1
var last_message_time = 0.0
var pending_messages = []
var is_admin = false

var connected_systems = []
var sensory_system = null

# Filtering
var filter_list = []
var filter_enabled = false
var show_timestamps = true

# Node references
@onready var chat_window = $Control/ChatWindow
@onready var chat_log = $Control/ChatWindow/ChatPanel/VBoxContainer/ChatLog/ChatMessages
@onready var chat_input = $Control/ChatWindow/InputPanel/HBoxContainer/ChatInput
@onready var channel_tabs = $Control/ChatWindow/ChatPanel/VBoxContainer/ChannelTabs
@onready var scroll_container = $Control/ChatWindow/ChatPanel/VBoxContainer/ChatLog
@onready var animation_player = $AnimationPlayer
@onready var typing_indicator = $Control/TypingIndicator
@onready var key_bind_indicator = $Control/KeyBindIndicator

# UI state transitions
enum ChatState {HIDDEN, VISIBLE, ACTIVE, INACTIVE}
var current_state = ChatState.HIDDEN

func _ready():
	# Initialize multiplayer
	setup_multiplayer()
	
	# Initialize window state
	chat_window.visible = false
	chat_window.modulate.a = 0
	typing_indicator.visible = true
	typing_indicator.modulate.a = 0.7
	
	# Connect signals
	chat_input.text_submitted.connect(_on_chat_submitted)
	chat_input.focus_exited.connect(_on_chat_input_focus_exited)
	$Control/ChatWindow/InputPanel/HBoxContainer/SendButton.pressed.connect(_on_send_button_pressed)
	$Control/ChatWindow/ChatPanel/VBoxContainer/Header/CloseButton.pressed.connect(close_chat)
	$Control/ChatWindow/ChatPanel/VBoxContainer/ChannelTabs.tab_changed.connect(_on_channel_changed)
	
	# Setup key binding for chat
	load_chat_key()
	update_key_binding_indicator()
	
	# Connect to sensory system if available
	find_and_connect_sensory_system()
	
	# Setup input map for chat actions
	setup_input_actions()
	
	# Initialize channel tabs
	setup_channel_tabs()
	
	# Add welcome message
	add_message("Welcome to A.R.E.S-1 Communication System", "system")
	add_message("Press T to open chat", "system")
	add_message("Type /help for available commands", "system")
	
	# Automatically hide if starting hidden
	if current_state == ChatState.HIDDEN:
		chat_window.visible = false
		chat_window.modulate.a = 0
	else:
		# Start partially visible if needed
		switch_to_state(current_state)

func setup_multiplayer():
	"""Initialize multiplayer settings"""
	if multiplayer.multiplayer_peer != null:
		local_peer_id = multiplayer.get_unique_id()
	else:
		local_peer_id = 1  # Singleplayer fallback
	
	# Check if player is admin (host or designated admin)
	is_admin = is_multiplayer_host() or check_admin_status()
	
	add_to_group("chat_systems")

func is_multiplayer_host() -> bool:
	"""Check if this client is the multiplayer host"""
	if multiplayer.multiplayer_peer == null:
		return true  # Singleplayer
	return multiplayer.is_server()

func check_admin_status() -> bool:
	"""Check if player has admin privileges"""
	# This could be expanded to check against a saved admin list
	return false

# ================== MULTIPLAYER RPCs ==================

@rpc("any_peer", "call_local", "reliable")
func network_send_message(sender_id: int, sender_name: String, message_text: String, category: String, channel: String, timestamp: float):
	"""Receive a message from another player"""
	if not validate_message(message_text, category, channel, sender_id):
		return
	
	# Add message locally
	var formatted_sender = sender_name if sender_name != "" else "Player" + str(sender_id)
	add_message_local(message_text, category, formatted_sender, channel, timestamp)

@rpc("any_peer", "call_local", "reliable")
func network_send_command(sender_id: int, sender_name: String, command: String, args: String, channel: String):
	"""Receive a command from another player"""
	if not validate_command(command, args, sender_id):
		return
	
	# Process command locally (most commands should be processed by sender only)
	match command:
		"me", "emote":
			if args:
				var formatted_sender = sender_name if sender_name != "" else "Player" + str(sender_id)
				add_message_local(args, "emote", "* " + formatted_sender, channel)
		"ooc":
			if args:
				var formatted_sender = sender_name if sender_name != "" else "Player" + str(sender_id)
				add_message_local(args, "ooc", formatted_sender, "ooc")
		"radio", "r":
			if args:
				var formatted_sender = sender_name if sender_name != "" else "Player" + str(sender_id)
				add_message_local(args, "radio", formatted_sender, "radio")

@rpc("authority", "call_local", "reliable")
func network_admin_message(message_text: String, category: String = "system"):
	"""Receive an admin message (host only can send)"""
	add_message_local(message_text, category, "", "")

@rpc("any_peer", "unreliable")
func network_typing_indicator(sender_id: int, is_typing: bool):
	"""Show/hide typing indicator for other players"""
	if sender_id == local_peer_id:
		return
	
	# This could be expanded to show specific player typing indicators
	if is_typing:
		show_message_notification()

@rpc("authority", "call_local", "reliable")
func sync_chat_history(history_data: Array):
	"""Sync chat history to a newly connected player"""
	chat_history.clear()
	for child in chat_log.get_children():
		chat_log.remove_child(child)
		child.queue_free()
	
	for message_data in history_data:
		add_message_local(
			message_data.text,
			message_data.category,
			message_data.sender,
			message_data.channel,
			message_data.timestamp
		)

# ================== VALIDATION ==================

func validate_message(message_text: String, category: String, channel: String, sender_id: int) -> bool:
	"""Validate incoming messages to prevent abuse"""
	# Check message length
	if message_text.length() > MAX_MESSAGE_LENGTH:
		return false
	
	# Check for valid category
	if not message_categories.has(category):
		return false
	
	# Check for valid channel
	if channel != "" and not chat_channels.has(channel):
		return false
	
	# Check for spam (basic rate limiting)
	var current_time = Time.get_time_dict_from_system()
	var message_key = str(sender_id) + ":" + str(current_time.hour) + ":" + str(current_time.minute)
	
	# Additional validation could be added here (profanity filter, etc.)
	
	return true

func validate_command(command: String, args: String, sender_id: int) -> bool:
	"""Validate incoming commands"""
	# Admin-only commands
	var admin_commands = ["kick", "ban", "admin", "broadcast"]
	if command in admin_commands:
		return is_sender_admin(sender_id)
	
	# Check command exists
	var valid_commands = ["help", "me", "emote", "ooc", "radio", "r", "whisper"]
	if not command in valid_commands:
		return false
	
	return true

func is_sender_admin(sender_id: int) -> bool:
	"""Check if sender has admin privileges"""
	if sender_id == 1:  # Host is always admin
		return true
	
	# Could check against admin list here
	return false

# ================== CORE CHAT FUNCTIONALITY ==================

func _input(event):
	# Handle chat toggle with configured key
	if event is InputEventKey and event.pressed and not event.echo:
		# Chat toggle key pressed
		if event.keycode == chat_key and current_state != ChatState.ACTIVE:
			open_chat()
			get_viewport().set_input_as_handled()
		
		# ESC pressed while chat is active
		elif event.keycode == KEY_ESCAPE and current_state == ChatState.ACTIVE:
			close_chat()
			get_viewport().set_input_as_handled()
		
		# Handle input history navigation (UP/DOWN arrows)
		elif current_state == ChatState.ACTIVE and chat_input.has_focus():
			if event.keycode == KEY_UP:
				navigate_history_up()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_DOWN:
				navigate_history_down()
				get_viewport().set_input_as_handled()

func _process(_delta):
	# Auto-scroll chat if we're near the bottom
	if is_chat_open and chat_log.get_child_count() > 0:
		var scrollbar = scroll_container.get_v_scroll_bar()
		if scrollbar and scrollbar.visible:
			if scroll_container.scroll_vertical >= scrollbar.max_value - scroll_container.size.y - 50:
				scroll_to_bottom()

# Change chat state with animation
func switch_to_state(new_state):
	var old_state = current_state
	current_state = new_state
	
	match new_state:
		ChatState.HIDDEN:
			animation_player.play("hide_chat")
			is_chat_open = false
			is_chat_visible = false
		
		ChatState.VISIBLE:
			if old_state == ChatState.HIDDEN:
				animation_player.play("show_chat")
			elif old_state == ChatState.ACTIVE:
				animation_player.play("deactivate_chat")
			
			is_chat_open = true
			is_chat_visible = true
			is_chat_inactive = false
		
		ChatState.ACTIVE:
			if old_state == ChatState.HIDDEN:
				animation_player.play("show_and_activate_chat")
			elif old_state == ChatState.VISIBLE or old_state == ChatState.INACTIVE:
				animation_player.play("activate_chat")
				
			is_chat_open = true
			is_chat_visible = true
			is_chat_inactive = false
			
			# Focus input after animation
			await animation_player.animation_finished
			chat_input.grab_focus()
		
		ChatState.INACTIVE:
			animation_player.play("fade_chat")
			is_chat_open = true
			is_chat_visible = true
			is_chat_inactive = true

# Open the chat window and activate it
func open_chat():
	switch_to_state(ChatState.ACTIVE)
	
	# Scroll to bottom after opening
	await get_tree().process_frame
	scroll_to_bottom()

# Close the chat window
func close_chat():
	if current_state == ChatState.ACTIVE:
		chat_input.release_focus()
		chat_input.text = ""
		input_history_index = -1
		
		# Send typing indicator stop
		if multiplayer.multiplayer_peer != null:
			network_typing_indicator.rpc(local_peer_id, false)
	
	switch_to_state(ChatState.HIDDEN)

# Make chat inactive but still visible
func make_chat_inactive():
	if current_state == ChatState.ACTIVE or current_state == ChatState.VISIBLE:
		switch_to_state(ChatState.INACTIVE)

# Toggle chat visibility
func toggle_chat():
	if current_state == ChatState.HIDDEN:
		open_chat()
	else:
		close_chat()

# Add a message to the chat (public function)
func add_message(text, category = "default", sender = "", channel = ""):
	var timestamp = Time.get_unix_time_from_system()
	add_message_local(text, category, sender, channel, timestamp)

# Add a message to the chat locally
func add_message_local(text, category = "default", sender = "", channel = "", timestamp = 0.0):
	# Skip filtered messages
	if filter_enabled and is_filtered(text):
		return
	
	if timestamp == 0.0:
		timestamp = Time.get_unix_time_from_system()
	
	# If no specific channel, use the active one
	if channel == "":
		channel = active_channel if active_channel != "all" else "local"
	
	# Create new message container
	var message_container = HBoxContainer.new()
	
	# Create timestamp if enabled
	if show_timestamps:
		var timestamp_label = Label.new()
		var time_dict = Time.get_time_dict_from_unix_time(timestamp)
		timestamp_label.text = "%02d:%02d" % [time_dict.hour, time_dict.minute]
		timestamp_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		timestamp_label.add_theme_font_size_override("font_size", 12)
		timestamp_label.custom_minimum_size.x = 40
		message_container.add_child(timestamp_label)
	
	# Create channel indicator if in "all" view
	if active_channel == "all" and channel in chat_channels:
		var channel_label = Label.new()
		channel_label.text = chat_channels[channel].icon
		channel_label.add_theme_color_override("font_color", chat_channels[channel].color)
		channel_label.add_theme_font_size_override("font_size", 14)
		channel_label.custom_minimum_size.x = 25
		message_container.add_child(channel_label)
	
	# Create message label
	var message = RichTextLabel.new()
	message.fit_content = true
	message.selection_enabled = true
	message.scroll_active = false
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message.custom_minimum_size.y = 20
	message.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Format message based on category and sender
	var prefix = message_categories.get(category, message_categories["default"]).prefix
	var message_color = message_categories.get(category, message_categories["default"]).color
	
	var formatted_text = ""
	if sender != "":
		formatted_text = "[color=#%s]%s%s: [/color]%s" % [
			message_color.to_html(false), 
			prefix, 
			sender, 
			text
		]
	else:
		formatted_text = "[color=#%s]%s%s[/color]" % [
			message_color.to_html(false),
			prefix,
			text
		]
	
	message.bbcode_enabled = true
	message.bbcode_text = formatted_text
	message_container.add_child(message)
	
	# Add message to chat log
	chat_log.add_child(message_container)
	
	# Store in history
	chat_history.append({
		"text": text,
		"category": category,
		"sender": sender,
		"channel": channel,
		"timestamp": timestamp
	})
	
	# Limit chat history
	if chat_log.get_child_count() > MAX_MESSAGES:
		var oldest_message = chat_log.get_child(0)
		chat_log.remove_child(oldest_message)
		oldest_message.queue_free()
		chat_history.pop_front()
	
	# Show notification if chat is closed
	if current_state == ChatState.HIDDEN:
		show_message_notification()
	else:
		# Auto-scroll if near bottom
		scroll_to_bottom()

# Scroll chat to bottom
func scroll_to_bottom():
	await get_tree().process_frame
	var scrollbar = scroll_container.get_v_scroll_bar()
	if scrollbar and scrollbar.visible:
		scroll_container.scroll_vertical = scrollbar.max_value

# Show notification that new message was received
func show_message_notification():
	typing_indicator.modulate.a = 1.0
	
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(typing_indicator, "modulate:a", 0.7, 1.5)

# Process chat message input
func _on_chat_submitted(text):
	if text.strip_edges() == "":
		return
	
	# Rate limiting check
	var current_time = Time.get_time_dict_from_system()
	var time_since_last = current_time.minute * 60 + current_time.second - last_message_time
	if time_since_last < CHAT_RATE_LIMIT and not is_admin:
		add_message("You are sending messages too quickly. Please wait a moment.", "warning")
		return
	
	last_message_time = current_time.minute * 60 + current_time.second
	
	# Truncate message if too long
	if text.length() > MAX_MESSAGE_LENGTH:
		text = text.substr(0, MAX_MESSAGE_LENGTH)
		add_message("Message truncated due to length limit.", "warning")
	
	# Add to input history
	if text != "" and (input_history.size() == 0 or input_history[0] != text):
		input_history.insert(0, text)
		if input_history.size() > MAX_HISTORY:
			input_history.pop_back()
	
	input_history_index = -1
	
	# Process commands
	if text.begins_with("/"):
		process_command(text)
	else:
		# Send regular message
		send_message_to_network(text)
	
	# Clear input
	chat_input.text = ""
	chat_input.grab_focus()

func send_message_to_network(message_text: String):
	"""Send a message to all players"""
	var sender_name = get_player_name()
	var channel = active_channel if active_channel != "all" else "local"
	var timestamp = Time.get_unix_time_from_system()
	
	# Send to network
	if multiplayer.multiplayer_peer != null:
		network_send_message.rpc(local_peer_id, sender_name, message_text, "default", channel, timestamp)
	else:
		# Singleplayer fallback
		add_message_local(message_text, "default", sender_name, channel, timestamp)

func get_player_name() -> String:
	"""Get the local player's name"""
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("get_player_name"):
		return game_manager.get_player_name()
	
	# Fallback
	return "Player" + str(local_peer_id)

# Send button pressed handler
func _on_send_button_pressed():
	_on_chat_submitted(chat_input.text)

# Handle input focus lost
func _on_chat_input_focus_exited():
	if current_state == ChatState.ACTIVE:
		switch_to_state(ChatState.VISIBLE)
		
		# Send typing indicator stop
		if multiplayer.multiplayer_peer != null:
			network_typing_indicator.rpc(local_peer_id, false)

# Process chat commands
func process_command(text):
	var command_parts = text.substr(1).split(" ", true, 1)
	var command = command_parts[0].to_lower()
	var args = ""
	if command_parts.size() > 1:
		args = command_parts[1]
	
	match command:
		"help":
			show_help()
		
		"clear":
			clear_chat()
		
		"me", "emote":
			if args:
				send_command_to_network(command, args)
		
		"whisper":
			handle_whisper_command(args)
		
		"radio", "r":
			if args:
				send_command_to_network(command, args)
		
		"ooc":
			if args:
				send_command_to_network(command, args)
		
		"timestamp":
			show_timestamps = !show_timestamps
			add_message("Timestamps " + ("enabled" if show_timestamps else "disabled"), "system")
		
		"filter":
			if args:
				add_filter(args)
				add_message("Added filter: " + args, "system")
		
		"unfilter":
			if args:
				remove_filter(args)
				add_message("Removed filter: " + args, "system")
		
		# Admin commands
		"kick", "ban", "admin":
			if is_admin:
				handle_admin_command(command, args)
			else:
				add_message("You don't have permission to use that command.", "warning")
		
		_:
			add_message("Unknown command: " + command, "system")
	
	# Emit command execution signal
	command_executed.emit(command, args)

func send_command_to_network(command: String, args: String):
	"""Send a command to all players"""
	var sender_name = get_player_name()
	var channel = active_channel if active_channel != "all" else "local"
	
	if multiplayer.multiplayer_peer != null:
		network_send_command.rpc(local_peer_id, sender_name, command, args, channel)
	else:
		# Singleplayer fallback
		match command:
			"me", "emote":
				add_message_local(args, "emote", "* " + sender_name, channel)
			"ooc":
				add_message_local(args, "ooc", sender_name, "ooc")
			"radio", "r":
				add_message_local(args, "radio", sender_name, "radio")

func show_help():
	add_message("Available commands:", "system")
	add_message("/help - Show this help", "system")
	add_message("/clear - Clear chat history", "system")
	add_message("/me <action> - Perform emote", "system")
	add_message("/ooc <message> - Out-of-character chat", "system")
	add_message("/whisper <player> <message> - Send private message", "system")
	add_message("/radio <message> - Send radio message", "system")
	add_message("/r <message> - Short for radio", "system")
	add_message("/timestamp - Toggle timestamps", "system")
	add_message("/filter <word> - Add word to filter", "system")
	add_message("/unfilter <word> - Remove word from filter", "system")
	
	if is_admin:
		add_message("Admin commands:", "system")
		add_message("/kick <player> - Kick player", "system")
		add_message("/ban <player> - Ban player", "system")

func handle_whisper_command(args: String):
	if args:
		var whisper_parts = args.split(" ", true, 1)
		if whisper_parts.size() > 1:
			var target = whisper_parts[0]
			var message = whisper_parts[1]
			# Whispers would need special handling to only send to target
			add_message(message, "whisper", "You → " + target)
		else:
			add_message("Usage: /whisper <player> <message>", "system")

func handle_admin_command(command: String, args: String):
	match command:
		"kick":
			if args:
				add_message("Kicked player: " + args, "system")
				# Implement actual kick logic
		"ban":
			if args:
				add_message("Banned player: " + args, "system")
				# Implement actual ban logic

# Clear chat history
func clear_chat():
	for child in chat_log.get_children():
		chat_log.remove_child(child)
		child.queue_free()
	
	chat_history.clear()
	add_message("Chat cleared", "system")

# Handle channel tab changes
func _on_channel_changed(tab_idx):
	var tab_name = channel_tabs.get_tab_title(tab_idx).to_lower()
	
	# Update active channel
	active_channel = tab_name
	
	# Filter messages for the selected channel
	filter_messages_by_channel(tab_name)

# Filter messages to display only selected channel
func filter_messages_by_channel(channel_name):
	# Remove existing messages
	for child in chat_log.get_children():
		chat_log.remove_child(child)
		child.queue_free()
	
	# If "all" channel, show all messages
	if channel_name == "all":
		for message in chat_history:
			add_message_local(
				message.text,
				message.category,
				message.sender,
				message.channel,
				message.timestamp
			)
		return
	
	# Otherwise, filter by channel
	for message in chat_history:
		if message.channel == channel_name:
			add_message_local(
				message.text,
				message.category,
				message.sender,
				message.channel,
				message.timestamp
			)

# Setup channel tabs
func setup_channel_tabs():
	channel_tabs.clear_tabs()
	
	# Add "All" tab
	channel_tabs.add_tab("All")
	
	# Add other channel tabs
	for channel_name in chat_channels.keys():
		if channel_name != "all":
			channel_tabs.add_tab(channel_name.capitalize())
	
	# Set initial active channel
	active_channel = "all"
	channel_tabs.current_tab = 0

# Navigate input history upward
func navigate_history_up():
	if input_history.size() == 0:
		return
	
	# Save current input if we're just starting to navigate
	if input_history_index == -1:
		current_input = chat_input.text
	
	input_history_index = min(input_history_index + 1, input_history.size() - 1)
	chat_input.text = input_history[input_history_index]
	chat_input.caret_column = chat_input.text.length()

# Navigate input history downward
func navigate_history_down():
	if input_history_index == -1:
		return
	
	input_history_index -= 1
	
	if input_history_index == -1:
		chat_input.text = current_input
	else:
		chat_input.text = input_history[input_history_index]
	
	chat_input.caret_column = chat_input.text.length()

# Setup input actions for chat
func setup_input_actions():
	# Chat toggle action
	if not InputMap.has_action("toggle_chat"):
		InputMap.add_action("toggle_chat")
		var event = InputEventKey.new()
		event.keycode = chat_key
		InputMap.action_add_event("toggle_chat", event)
	
	# Chat escape action
	if not InputMap.has_action("close_chat"):
		InputMap.add_action("close_chat")
		var event = InputEventKey.new()
		event.keycode = KEY_ESCAPE
		InputMap.action_add_event("close_chat", event)

# Update key binding indicator
func update_key_binding_indicator():
	var key_name = OS.get_keycode_string(chat_key)
	key_bind_indicator.text = "Press " + key_name + " to chat"
	typing_indicator.get_node("Label").text = key_name

# Save chat key binding
func save_chat_key():
	var config = ConfigFile.new()
	config.set_value("chat", "chat_key", chat_key)
	var err = config.save("user://chat_settings.cfg")
	if err != OK:
		print("Error saving chat key: ", err)

# Load chat key binding
func load_chat_key():
	var config = ConfigFile.new()
	var err = config.load("user://chat_settings.cfg")
	if err == OK:
		chat_key = config.get_value("chat", "chat_key", DEFAULT_CHAT_KEY)
	
	# Update input actions
	if InputMap.has_action("toggle_chat"):
		InputMap.action_erase_events("toggle_chat")
		var event = InputEventKey.new()
		event.keycode = chat_key
		InputMap.action_add_event("toggle_chat", event)

# Set a new chat key binding
func set_chat_key(new_key):
	chat_key = new_key
	
	# Update input map
	if InputMap.has_action("toggle_chat"):
		InputMap.action_erase_events("toggle_chat")
	else:
		InputMap.add_action("toggle_chat")
	
	var event = InputEventKey.new()
	event.keycode = chat_key
	InputMap.action_add_event("toggle_chat", event)
	
	# Update visuals
	update_key_binding_indicator()
	
	# Save the setting
	save_chat_key()
	
	# Confirm to user
	add_message("Chat key changed to: " + OS.get_keycode_string(chat_key), "system")

# Add a word to the filter list
func add_filter(word):
	if word.strip_edges() == "":
		return
	
	if not word in filter_list:
		filter_list.append(word)

# Remove a word from the filter list
func remove_filter(word):
	filter_list.erase(word)

# Toggle message filtering
func toggle_filtering(enabled):
	filter_enabled = enabled
	add_message("Message filtering " + ("enabled" if enabled else "disabled"), "system")

# Check if a message would be filtered
func is_filtered(message_text):
	if not filter_enabled or filter_list.is_empty():
		return false
	
	message_text = message_text.to_lower()
	for filter_word in filter_list:
		if message_text.contains(filter_word.to_lower()):
			return true
	
	return false

# Receive a chat message from another player (would be called by network code)
func receive_message(text, category, sender, channel = "local"):
	add_message_local(text, category, sender, channel)

func is_chat_active() -> bool:
	return current_state == ChatState.ACTIVE

func find_and_connect_sensory_system():
	# Try to find sensory system in player
	var player_nodes = get_tree().get_nodes_in_group("player")
	if player_nodes.size() > 0:
		var player = player_nodes[0]
		sensory_system = player.get_node_or_null("SensorySystem")
		
		if sensory_system:
			print("ChatUI: Connected to player's SensorySystem")
			connected_systems.append(sensory_system)
			add_to_group("chat_ui")  # Make it easier for SensorySystem to find us
			
			# Add a welcome message
			add_message("SensorySystem connected to chat", "system")
			return true
	
	# If not found, look in the entire scene
	var sensory_systems = get_tree().get_nodes_in_group("sensory_system")
	if sensory_systems.size() > 0:
		sensory_system = sensory_systems[0]
		print("ChatUI: Connected to SensorySystem via group")
		connected_systems.append(sensory_system)
		add_to_group("chat_ui")
		
		# Add a welcome message
		add_message("SensorySystem connected to chat", "system")
		return true
		
	return false

func receive_sensory_message(message, category = "default", sender = "System"):
	# Convert sensory categories to chat categories
	var chat_category = category
	match category:
		"info": chat_category = "default"
		"warning": chat_category = "warning"
		"danger": chat_category = "alert"
		"important": chat_category = "system"
	
	# Add the message to chat
	add_message(message, chat_category, sender)

# ================== MULTIPLAYER UTILITIES ==================

func request_chat_history_sync():
	"""Request chat history from host (for newly connected clients)"""
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		request_history_sync.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func request_history_sync():
	"""Handle request for chat history sync"""
	if multiplayer.is_server():
		var history_data = []
		for message in chat_history:
			history_data.append(message)
		
		var requester_id = multiplayer.get_remote_sender_id()
		sync_chat_history.rpc_id(requester_id, history_data)

func on_player_connected(peer_id: int):
	"""Called when a new player connects"""
	if multiplayer.is_server():
		# Send chat history to new player
		var history_data = []
		for message in chat_history:
			history_data.append(message)
		
		if history_data.size() > 0:
			sync_chat_history.rpc_id(peer_id, history_data)

func on_player_disconnected(peer_id: int):
	"""Called when a player disconnects"""
	# Could show disconnect message
	add_message("Player " + str(peer_id) + " disconnected", "system")
