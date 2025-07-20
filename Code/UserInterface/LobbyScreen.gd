extends Control

# Core system references
var game_manager = null
var network_manager = null
var chat_manager = null

# Player data and state management
var local_player_data = {}
var online_players = {}
var squadron_members = {}
var selected_server = null
var current_view_mode = "server_browser"

# UI references - Top Bar
@onready var back_button = $TopBar/TopBarContainer/LeftSection/BackButton
@onready var search_input = $TopBar/TopBarContainer/CenterSection/SearchContainer/SearchInput
@onready var search_button = $TopBar/TopBarContainer/CenterSection/SearchContainer/SearchButton
@onready var player_name_label = $TopBar/TopBarContainer/RightSection/PlayerInfo/PlayerName
@onready var player_status_label = $TopBar/TopBarContainer/RightSection/PlayerInfo/PlayerStatus
@onready var notification_button = $TopBar/TopBarContainer/RightSection/NotificationButton

# UI references - Left Sidebar
@onready var server_browser_btn = $MainContainer/LeftSidebar/LeftSidebarContent/NavigationButtons/ServerBrowserBtn
@onready var quick_match_btn = $MainContainer/LeftSidebar/LeftSidebarContent/NavigationButtons/QuickMatchBtn
@onready var create_room_btn = $MainContainer/LeftSidebar/LeftSidebarContent/NavigationButtons/CreateRoomBtn
@onready var friends_list_btn = $MainContainer/LeftSidebar/LeftSidebarContent/NavigationButtons/FriendsListBtn
@onready var online_players_label = $MainContainer/LeftSidebar/LeftSidebarContent/QuickStats/OnlinePlayersLabel
@onready var active_servers_label = $MainContainer/LeftSidebar/LeftSidebarContent/QuickStats/ActiveServersLabel
@onready var active_games_label = $MainContainer/LeftSidebar/LeftSidebarContent/QuickStats/ActiveGamesLabel
@onready var region_dropdown = $MainContainer/LeftSidebar/LeftSidebarContent/RegionSelector/RegionDropdown

# UI references - Center Area
@onready var content_title = $MainContainer/CenterArea/CenterContent/ContentHeader/ContentTitle
@onready var game_mode_filter = $MainContainer/CenterArea/CenterContent/ContentHeader/FilterContainer/GameModeFilter
@onready var ping_filter = $MainContainer/CenterArea/CenterContent/ContentHeader/FilterContainer/PingFilter
@onready var refresh_button = $MainContainer/CenterArea/CenterContent/ContentHeader/FilterContainer/RefreshButton
@onready var server_list = $MainContainer/CenterArea/CenterContent/ServerListContainer/ServerScrollContainer/ServerList

# UI references - Right Sidebar (Chat)
@onready var tab_container = $MainContainer/RightSidebar/RightSidebarContent/TabContainer
@onready var global_chat_btn = $MainContainer/RightSidebar/RightSidebarContent/TabContainer/CHAT/ChatContainer/ChatChannels/GlobalChatBtn
@onready var squadron_chat_btn = $MainContainer/RightSidebar/RightSidebarContent/TabContainer/CHAT/ChatContainer/ChatChannels/SquadronChatBtn
@onready var local_chat_btn = $MainContainer/RightSidebar/RightSidebarContent/TabContainer/CHAT/ChatContainer/ChatChannels/LocalChatBtn
@onready var chat_messages = $MainContainer/RightSidebar/RightSidebarContent/TabContainer/CHAT/ChatContainer/ChatDisplay/ChatScrollContainer/ChatMessages
@onready var chat_input = $MainContainer/RightSidebar/RightSidebarContent/TabContainer/CHAT/ChatContainer/ChatInputContainer/ChatInput
@onready var chat_send_btn = $MainContainer/RightSidebar/RightSidebarContent/TabContainer/CHAT/ChatContainer/ChatInputContainer/ChatSendBtn

# UI references - Right Sidebar (Players)
@onready var player_search = $MainContainer/RightSidebar/RightSidebarContent/TabContainer/PLAYERS/PlayerSearchContainer/PlayerSearch
@onready var player_list = $MainContainer/RightSidebar/RightSidebarContent/TabContainer/PLAYERS/PlayerListContainer/PlayerScrollContainer/PlayerList

# UI references - Right Sidebar (Squadron)
@onready var squadron_list = $MainContainer/RightSidebar/RightSidebarContent/TabContainer/SQUADRON/SquadronListContainer/SquadronScrollContainer/SquadronList
@onready var invite_btn = $MainContainer/RightSidebar/RightSidebarContent/TabContainer/SQUADRON/SquadronHeader/InviteBtn

# UI references - Bottom Bar
@onready var connection_status = $BottomBar/BottomBarContainer/StatusSection/ConnectionStatus
@onready var selected_server_info = $BottomBar/BottomBarContainer/StatusSection/SelectedServerInfo
@onready var ready_toggle = $BottomBar/BottomBarContainer/ActionSection/ReadyToggle
@onready var deploy_button = $BottomBar/BottomBarContainer/ActionSection/DeployButton
@onready var network_info = $BottomBar/BottomBarContainer/InfoSection/NetworkInfo
@onready var system_info = $BottomBar/BottomBarContainer/InfoSection/SystemInfo

# Server browser data
var server_list_data = []
var filtered_servers = []
var current_filters = {
	"game_mode": "all",
	"ping": "all",
	"region": "global"
}

# Chat system data
var current_chat_channel = "global"
var chat_history = {
	"global": [],
	"squadron": [],
	"local": []
}
var max_chat_messages = 100

# Animation and timing constants
const REFRESH_INTERVAL = 5.0
const STATS_UPDATE_INTERVAL = 10.0
const CHAT_FADE_DURATION = 0.3
const SERVER_ITEM_HEIGHT = 50

# Events and signals
signal server_selected(server_data)
signal deploy_requested(server_data)
signal back_pressed()

func _ready():
	initialize_lobby_system()
	setup_ui_connections()
	setup_initial_state()
	start_periodic_updates()

func initialize_lobby_system():
	"""Initialize the lobby system with proper integrations"""
	print("Lobby: Initializing advanced lobby system")
	
	# Get system references
	game_manager = get_node_or_null("/root/GameManager")
	network_manager = get_node_or_null("/root/NetworkManager")
	chat_manager = get_node_or_null("/root/ChatManager")
	
	# Initialize player data
	setup_local_player_data()
	
	# Setup animations
	animate_interface_entrance()

func setup_local_player_data():
	"""Initialize local player information"""
	if game_manager:
		local_player_data = {
			"name": game_manager.get_player_name(),
			"id": game_manager.get_local_peer_id(),
			"rank": "Captain",
			"status": "Active",
			"squadron": "Phoenix Squadron",
			"ready": false
		}
	else:
		local_player_data = {
			"name": "COMMANDER ALPHA",
			"id": 1,
			"rank": "Captain", 
			"status": "Active",
			"squadron": "Phoenix Squadron",
			"ready": false
		}
	
	update_player_display()

func setup_ui_connections():
	"""Connect all UI element signals"""
	# Top bar connections
	back_button.pressed.connect(_on_back_pressed)
	search_button.pressed.connect(_on_search_requested)
	search_input.text_submitted.connect(_on_search_submitted)
	notification_button.pressed.connect(_on_notifications_requested)
	
	# Left sidebar navigation
	server_browser_btn.pressed.connect(_on_view_mode_changed.bind("server_browser"))
	quick_match_btn.pressed.connect(_on_quick_match_requested)
	create_room_btn.pressed.connect(_on_create_room_requested)
	friends_list_btn.pressed.connect(_on_view_mode_changed.bind("friends_list"))
	region_dropdown.item_selected.connect(_on_region_changed)
	
	# Center area controls
	game_mode_filter.item_selected.connect(_on_game_mode_filter_changed)
	ping_filter.item_selected.connect(_on_ping_filter_changed)
	refresh_button.pressed.connect(_on_refresh_requested)
	
	# Chat system connections
	global_chat_btn.pressed.connect(_on_chat_channel_changed.bind("global"))
	squadron_chat_btn.pressed.connect(_on_chat_channel_changed.bind("squadron"))
	local_chat_btn.pressed.connect(_on_chat_channel_changed.bind("local"))
	chat_send_btn.pressed.connect(_on_chat_message_sent)
	chat_input.text_submitted.connect(_on_chat_message_submitted)
	
	# Player list connections
	player_search.text_changed.connect(_on_player_search_changed)
	invite_btn.pressed.connect(_on_squadron_invite_requested)
	
	# Bottom bar connections
	ready_toggle.pressed.connect(_on_ready_toggled)
	deploy_button.pressed.connect(_on_deploy_requested)

func setup_initial_state():
	"""Setup the initial state of the lobby interface"""
	update_navigation_state()
	populate_sample_servers()
	populate_sample_players()
	populate_sample_chat()
	update_statistics_display()
	
	# Set initial view
	_on_view_mode_changed("server_browser")

func start_periodic_updates():
	"""Start periodic update timers"""
	# Server list refresh
	var refresh_timer = Timer.new()
	refresh_timer.wait_time = REFRESH_INTERVAL
	refresh_timer.timeout.connect(_on_periodic_refresh)
	refresh_timer.autostart = true
	add_child(refresh_timer)
	
	# Statistics update
	var stats_timer = Timer.new()
	stats_timer.wait_time = STATS_UPDATE_INTERVAL
	stats_timer.timeout.connect(_on_statistics_update)
	stats_timer.autostart = true
	add_child(stats_timer)

func animate_interface_entrance():
	"""Animate the lobby interface entrance"""
	modulate.a = 0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.8)

func update_player_display():
	"""Update the player information display"""
	player_name_label.text = local_player_data.name
	player_status_label.text = "Status: " + local_player_data.status + " • Rank: " + local_player_data.rank

func update_navigation_state():
	"""Update the navigation button states"""
	# Reset all buttons
	server_browser_btn.button_pressed = false
	friends_list_btn.button_pressed = false
	
	# Set active button based on current view
	match current_view_mode:
		"server_browser":
			server_browser_btn.button_pressed = true
		"friends_list":
			friends_list_btn.button_pressed = true

# Server Browser System
func populate_sample_servers():
	"""Populate the server list with sample data"""
	server_list_data = [
		{
			"name": "NEXUS PRIME - Official Server #1",
			"players": "847/1000",
			"ping": 23,
			"mode": "Standard",
			"region": "Alpha Sector",
			"map": "Station Omega",
			"status": "Active"
		},
		{
			"name": "VOID RUNNERS - PvP Arena",
			"players": "156/200",
			"ping": 45,
			"mode": "PvP Arena",
			"region": "Beta Sector", 
			"map": "Asteroid Field",
			"status": "Active"
		},
		{
			"name": "DEEP SPACE EXPLORATION",
			"players": "89/150",
			"ping": 67,
			"mode": "Cooperative",
			"region": "Gamma Sector",
			"map": "Research Station",
			"status": "Active"
		},
		{
			"name": "SURVIVAL PROTOCOL ALPHA",
			"players": "234/300",
			"ping": 34,
			"mode": "Survival", 
			"region": "Alpha Sector",
			"map": "Derelict Ship",
			"status": "Active"
		},
		{
			"name": "ROOKIE TRAINING GROUNDS",
			"players": "445/500",
			"ping": 28,
			"mode": "Training",
			"region": "Alpha Sector",
			"map": "Training Facility",
			"status": "Active"
		}
	]
	
	apply_server_filters()

func apply_server_filters():
	"""Apply current filters to the server list"""
	filtered_servers = server_list_data.duplicate()
	
	# Apply game mode filter
	if current_filters.game_mode != "all":
		filtered_servers = filtered_servers.filter(func(server): 
			return server.mode.to_lower() == current_filters.game_mode.to_lower()
		)
	
	# Apply ping filter
	match current_filters.ping:
		"< 50ms":
			filtered_servers = filtered_servers.filter(func(server): return server.ping < 50)
		"< 100ms":
			filtered_servers = filtered_servers.filter(func(server): return server.ping < 100)
		"< 200ms":
			filtered_servers = filtered_servers.filter(func(server): return server.ping < 200)
	
	refresh_server_display()

func refresh_server_display():
	"""Refresh the visual server list display"""
	# Clear existing server items
	for child in server_list.get_children():
		child.queue_free()
	
	# Create new server items
	for server_data in filtered_servers:
		create_server_item(server_data)

func create_server_item(server_data: Dictionary):
	"""Create a visual server item"""
	var server_item = create_server_item_container()
	
	# Server name
	var name_label = Label.new()
	name_label.text = server_data.name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_stretch_ratio = 3.0
	name_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1, 1))
	server_item.add_child(name_label)
	
	# Player count
	var players_label = Label.new()
	players_label.text = server_data.players
	players_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	players_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7, 1))
	server_item.add_child(players_label)
	
	# Ping
	var ping_label = Label.new()
	ping_label.text = str(server_data.ping) + "ms"
	ping_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ping_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ping_color = get_ping_color(server_data.ping)
	ping_label.add_theme_color_override("font_color", ping_color)
	server_item.add_child(ping_label)
	
	# Game mode
	var mode_label = Label.new()
	mode_label.text = server_data.mode
	mode_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_label.size_flags_stretch_ratio = 1.5
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1, 1))
	server_item.add_child(mode_label)
	
	# Join button
	var join_button = Button.new()
	join_button.text = "JOIN"
	join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_button.custom_minimum_size.x = 80
	join_button.add_theme_color_override("font_color", Color(0.4, 1, 0.4, 1))
	join_button.pressed.connect(_on_server_join_requested.bind(server_data))
	server_item.add_child(join_button)
	
	server_list.add_child(server_item)

func create_server_item_container() -> HBoxContainer:
	"""Create a container for a server list item"""
	var container = HBoxContainer.new()
	container.custom_minimum_size.y = SERVER_ITEM_HEIGHT
	container.theme_override_constants["separation"] = 10
	
	# Add hover effect
	container.mouse_entered.connect(_on_server_item_hover.bind(container, true))
	container.mouse_exited.connect(_on_server_item_hover.bind(container, false))
	
	return container

func get_ping_color(ping: int) -> Color:
	"""Get color based on ping value"""
	if ping < 50:
		return Color(0.4, 1, 0.4, 1)  # Green
	elif ping < 100:
		return Color(1, 1, 0.4, 1)    # Yellow
	else:
		return Color(1, 0.4, 0.4, 1)  # Red

# Chat System
func populate_sample_chat():
	"""Populate chat with sample messages"""
	add_chat_message("global", "SYSTEM", "Welcome to Nexus Station Command Center", Color.CYAN)
	add_chat_message("global", "Admiral_Vega", "New mission available in Sector 7", Color.WHITE)
	add_chat_message("global", "Pilot_Nova", "Looking for squadron members!", Color.WHITE)
	add_chat_message("squadron", "Commander_X", "Ready for deployment", Color(0.4, 1, 0.4))
	add_chat_message("squadron", "Echo_Leader", "Confirmed, standing by", Color(0.4, 1, 0.4))

func add_chat_message(channel: String, sender: String, message: String, color: Color = Color.WHITE):
	"""Add a message to the specified chat channel"""
	if not chat_history.has(channel):
		chat_history[channel] = []
	
	var chat_data = {
		"sender": sender,
		"message": message,
		"color": color,
		"timestamp": Time.get_datetime_string_from_system()
	}
	
	chat_history[channel].append(chat_data)
	
	# Limit message history
	if chat_history[channel].size() > max_chat_messages:
		chat_history[channel].pop_front()
	
	# Update display if this is the current channel
	if channel == current_chat_channel:
		refresh_chat_display()

func refresh_chat_display():
	"""Refresh the chat message display"""
	# Clear existing messages
	for child in chat_messages.get_children():
		child.queue_free()
	
	# Add messages from current channel
	if chat_history.has(current_chat_channel):
		for msg_data in chat_history[current_chat_channel]:
			create_chat_message_display(msg_data)

func create_chat_message_display(msg_data: Dictionary):
	"""Create a visual chat message"""
	var message_container = HBoxContainer.new()
	message_container.theme_override_constants["separation"] = 8
	
	# Timestamp
	var time_label = Label.new()
	time_label.text = "[" + msg_data.timestamp.split(" ")[1].substr(0, 5) + "]"
	time_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.8))
	time_label.add_theme_font_size_override("font_size", 10)
	time_label.custom_minimum_size.x = 50
	message_container.add_child(time_label)
	
	# Sender
	var sender_label = Label.new()
	sender_label.text = msg_data.sender + ":"
	sender_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1, 1))
	sender_label.add_theme_font_size_override("font_size", 12)
	sender_label.custom_minimum_size.x = 100
	message_container.add_child(sender_label)
	
	# Message
	var message_label = Label.new()
	message_label.text = msg_data.message
	message_label.add_theme_color_override("font_color", msg_data.color)
	message_label.add_theme_font_size_override("font_size", 12)
	message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_container.add_child(message_label)
	
	chat_messages.add_child(message_container)
	
	# Auto-scroll to bottom
	await get_tree().process_frame
	var scroll_container = chat_messages.get_parent()
	scroll_container.scroll_vertical = scroll_container.get_v_scroll_bar().max_value

# Player Management System
func populate_sample_players():
	"""Populate the player list with sample data"""
	online_players = {
		"1": {"name": "Admiral_Vega", "status": "In Mission", "rank": "Admiral"},
		"2": {"name": "Pilot_Nova", "status": "In Lobby", "rank": "Lieutenant"},
		"3": {"name": "Commander_X", "status": "Ready", "rank": "Commander"},
		"4": {"name": "Echo_Leader", "status": "In Mission", "rank": "Captain"},
		"5": {"name": "Ghost_Rider", "status": "Away", "rank": "Major"}
	}
	
	squadron_members = {
		"3": online_players["3"],
		"4": online_players["4"]
	}
	
	refresh_player_displays()

func refresh_player_displays():
	"""Refresh all player list displays"""
	refresh_online_players_display()
	refresh_squadron_display()

func refresh_online_players_display():
	"""Refresh the online players list"""
	# Clear existing items
	for child in player_list.get_children():
		child.queue_free()
	
	# Add players
	for player_id in online_players.keys():
		var player_data = online_players[player_id]
		create_player_item(player_data, player_list)

func refresh_squadron_display():
	"""Refresh the squadron members list"""
	# Clear existing items
	for child in squadron_list.get_children():
		child.queue_free()
	
	# Add squadron members
	for player_id in squadron_members.keys():
		var player_data = squadron_members[player_id]
		create_player_item(player_data, squadron_list, true)

func create_player_item(player_data: Dictionary, parent_container: Node, is_squadron: bool = false):
	"""Create a visual player list item"""
	var player_container = HBoxContainer.new()
	player_container.theme_override_constants["separation"] = 10
	
	# Player name
	var name_label = Label.new()
	name_label.text = player_data.name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1, 1))
	name_label.add_theme_font_size_override("font_size", 12)
	player_container.add_child(name_label)
	
	# Status indicator
	var status_indicator = Label.new()
	status_indicator.text = get_status_indicator(player_data.status)
	status_indicator.add_theme_color_override("font_color", get_status_color(player_data.status))
	status_indicator.add_theme_font_size_override("font_size", 10)
	player_container.add_child(status_indicator)
	
	# Add interaction button for squadron
	if is_squadron:
		var action_button = Button.new()
		action_button.text = "MSG"
		action_button.custom_minimum_size.x = 40
		action_button.add_theme_font_size_override("font_size", 10)
		action_button.pressed.connect(_on_player_message_requested.bind(player_data))
		player_container.add_child(action_button)
	
	parent_container.add_child(player_container)

func get_status_indicator(status: String) -> String:
	"""Get status indicator symbol"""
	match status:
		"Ready": return "●"
		"In Mission": return "▲"
		"In Lobby": return "○"
		"Away": return "◐"
		_: return "○"

func get_status_color(status: String) -> Color:
	"""Get status color"""
	match status:
		"Ready": return Color(0.4, 1, 0.4)
		"In Mission": return Color(1, 0.6, 0.2)
		"In Lobby": return Color(0.4, 0.8, 1)
		"Away": return Color(0.8, 0.8, 0.8)
		_: return Color(0.6, 0.6, 0.6)

func update_statistics_display():
	"""Update the statistics display"""
	online_players_label.text = "Online Pilots: " + str(online_players.size() + randi_range(2800, 3200))
	active_servers_label.text = "Active Servers: " + str(randi_range(120, 150))
	active_games_label.text = "Active Missions: " + str(randi_range(80, 100))

# Event Handlers
func _on_back_pressed():
	"""Handle back button press"""
	print("Lobby: Disconnecting from station")
	emit_signal("back_pressed")

func _on_search_requested():
	"""Handle search button press"""
	var search_term = search_input.text
	if search_term.length() > 0:
		perform_search(search_term)

func _on_search_submitted(text: String):
	"""Handle search input submission"""
	if text.length() > 0:
		perform_search(text)

func perform_search(search_term: String):
	"""Perform search across servers and players"""
	print("Lobby: Searching for: ", search_term)
	# Implement search logic here

func _on_notifications_requested():
	"""Handle notification button press"""
	print("Lobby: Opening notifications panel")
	# Implement notifications panel

func _on_view_mode_changed(mode: String):
	"""Handle view mode changes"""
	current_view_mode = mode
	update_navigation_state()
	
	match mode:
		"server_browser":
			content_title.text = "SERVER BROWSER"
			# Show server browser content
		"friends_list":
			content_title.text = "SQUADRON ROSTER"
			# Show friends list content

func _on_quick_match_requested():
	"""Handle quick match request"""
	print("Lobby: Requesting quick match deployment")
	# Implement quick match logic

func _on_create_room_requested():
	"""Handle create room request"""
	print("Lobby: Opening mission creation interface")
	# Implement room creation

func _on_region_changed(index: int):
	"""Handle region selection change"""
	var region_name = region_dropdown.get_item_text(index)
	print("Lobby: Region changed to: ", region_name)
	current_filters.region = region_name.to_lower()
	apply_server_filters()

func _on_game_mode_filter_changed(index: int):
	"""Handle game mode filter change"""
	var mode = game_mode_filter.get_item_text(index).to_lower().replace(" ", "_")
	current_filters.game_mode = mode
	apply_server_filters()

func _on_ping_filter_changed(index: int):
	"""Handle ping filter change"""
	var ping_setting = ping_filter.get_item_text(index)
	current_filters.ping = ping_setting
	apply_server_filters()

func _on_refresh_requested():
	"""Handle manual refresh request"""
	print("Lobby: Refreshing server list")
	# Animate refresh button
	var tween = create_tween()
	tween.tween_property(refresh_button, "rotation", PI * 2, 0.5)
	tween.tween_callback(func(): refresh_button.rotation = 0)
	
	populate_sample_servers()

func _on_server_join_requested(server_data: Dictionary):
	"""Handle server join request"""
	selected_server = server_data
	selected_server_info.text = "Selected: " + server_data.name
	deploy_button.disabled = false
	
	print("Lobby: Server selected: ", server_data.name)
	emit_signal("server_selected", server_data)

func _on_server_item_hover(container: Control, is_hovering: bool):
	"""Handle server item hover effects"""
	var tween = create_tween()
	var target_modulate = Color(1.1, 1.1, 1.1) if is_hovering else Color.WHITE
	tween.tween_property(container, "modulate", target_modulate, 0.2)

func _on_chat_channel_changed(channel: String):
	"""Handle chat channel change"""
	current_chat_channel = channel
	
	# Update button states
	global_chat_btn.button_pressed = (channel == "global")
	squadron_chat_btn.button_pressed = (channel == "squadron")
	local_chat_btn.button_pressed = (channel == "local")
	
	# Refresh chat display
	refresh_chat_display()

func _on_chat_message_sent():
	"""Handle chat send button press"""
	send_chat_message()

func _on_chat_message_submitted(text: String):
	"""Handle chat input submission"""
	send_chat_message()

func send_chat_message():
	"""Send a chat message"""
	var message = chat_input.text.strip_edges()
	if message.length() > 0:
		add_chat_message(current_chat_channel, local_player_data.name, message, Color.WHITE)
		chat_input.text = ""

func _on_player_search_changed(text: String):
	"""Handle player search text change"""
	# Implement player search filtering
	print("Lobby: Searching players for: ", text)

func _on_squadron_invite_requested():
	"""Handle squadron invite request"""
	print("Lobby: Opening squadron invite interface")

func _on_player_message_requested(player_data: Dictionary):
	"""Handle player message request"""
	print("Lobby: Opening message to: ", player_data.name)

func _on_ready_toggled():
	"""Handle ready status toggle"""
	local_player_data.ready = ready_toggle.button_pressed
	ready_toggle.text = "READY" if local_player_data.ready else "STANDBY"
	
	var color = Color(0.4, 1, 0.4) if local_player_data.ready else Color(1, 0.8, 0.4)
	ready_toggle.add_theme_color_override("font_color", color)

func _on_deploy_requested():
	"""Handle deploy button press"""
	if selected_server and local_player_data.ready:
		print("Lobby: Deploying to mission: ", selected_server.name)
		emit_signal("deploy_requested", selected_server)
	else:
		print("Lobby: Cannot deploy - not ready or no server selected")

func _on_periodic_refresh():
	"""Handle periodic refresh timer"""
	if current_view_mode == "server_browser":
		# Simulate server list updates
		update_server_player_counts()

func _on_statistics_update():
	"""Handle statistics update timer"""
	update_statistics_display()

func update_server_player_counts():
	"""Simulate dynamic server player count updates"""
	for server in server_list_data:
		var current_players = int(server.players.split("/")[0])
		var max_players = int(server.players.split("/")[1])
		var change = randi_range(-5, 10)
		current_players = clamp(current_players + change, 0, max_players)
		server.players = str(current_players) + "/" + str(max_players)
	
	apply_server_filters()
