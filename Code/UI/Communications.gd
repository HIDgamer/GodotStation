# Communications.gd
# Handles UI panels, tabs, chat, viewport switching, and lobby/game coordination.
# Manages the transition from lobby (video/music display) to active gameplay.

extends Control

@onready var tabview: TextureRect = $HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview
@onready var wip_label: Label = $HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/WorkInProgressLabel
@onready var chat_vbox: VBoxContainer = $HSplitContainer/CommunicationsPanel/VSplitContainer/Chat/VBoxContainer
@onready var tab_scroll: ScrollContainer = $HSplitContainer/CommunicationsPanel/VBoxContainer/TabsContainer/TabScroll
@onready var left_arrow: Button = $HSplitContainer/CommunicationsPanel/VBoxContainer/TabsContainer/LeftArrow
@onready var right_arrow: Button = $HSplitContainer/CommunicationsPanel/VBoxContainer/TabsContainer/RightArrow
@onready var info_scroll: ScrollContainer = $HSplitContainer/CommunicationsPanel/VBoxContainer/InfoContainer/InfoScroll
@onready var info_left_arrow: Button = $HSplitContainer/CommunicationsPanel/VBoxContainer/InfoContainer/InfoLeftArrow
@onready var info_right_arrow: Button = $HSplitContainer/CommunicationsPanel/VBoxContainer/InfoContainer/InfoRightArrow
@onready var player_interface: Control = get_node_or_null("HSplitContainer/SubViewportContainer/SubViewport/DDome/Human/UILayer/Player_Interface")
@onready var lobby_timer: Timer = $LobbyTimer
@onready var game_subviewport: SubViewportContainer = $HSplitContainer/SubViewportContainer
@onready var lobby_subviewport: SubViewportContainer = $HSplitContainer/SubViewportContainer2
@onready var admin_buttons: VBoxContainer = $HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/AdminButtons
@onready var status_info: VBoxContainer = $HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/StatusInfo
@onready var server_buttons: VBoxContainer = $HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/ServerButtons
@onready var preferences_buttons: VBoxContainer = $HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/PreferencesButtons
@onready var day_night_toggle: CheckButton = $HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/PreferencesButtons/DayNightToggle
@onready var shadow_quality_label: Label = $HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/PreferencesButtons/ShadowQualityLabel
@onready var map_label: Label = $HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/StatusInfo/MapLabel
@onready var gamemode_label: Label = $HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/StatusInfo/GamemodeLabel
@onready var players_label: Label = $HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/StatusInfo/PlayersLabel
@onready var timer_label: Label = $HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/StatusInfo/TimerLabel
@onready var music_label: Label = $HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/StatusInfo/MusicLabel
@onready var real_time_label: Label = $HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/StatusInfo/RealTimeLabel
@onready var ingame_time_label: Label = $HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/StatusInfo/IngameTimeLabel
@onready var media_popup: PopupPanel = $MediaPopup
@onready var music_options_popup: PopupPanel = $MusicOptionsPopup
@onready var admin_spawn_popup: Window = $AdminSpawnPopup
var text_input_instance = null
var music_loops: int = 1
var music_volume: float = 0.5
var current_music_name: String = "None"
var ingame_time: float = 0.0
var game_started: bool = false

var current_tab: String = ""

func _ready() -> void:
	_load_world_map()
	
	var text_input_scene = load("uid://2oufqaxsmbt8")
	if text_input_scene:
		text_input_instance = text_input_scene.instantiate()
		add_child(text_input_instance)
		text_input_instance.message_sent.connect(_on_message_sent)

	print("[Communications] Connecting to GameManager signals")
	if GameManager.has_signal("lobby_timeout"):
		GameManager.lobby_timeout.connect(_on_lobby_timer_timeout)
		print("[Communications] Connected to lobby_timeout")
	if GameManager.has_signal("GameStarted"):
		GameManager.GameStarted.connect(_on_game_started)
		print("[Communications] Connected to GameStarted")
	if GameManager.has_signal("ChatMessageReceived"):
		GameManager.ChatMessageReceived.connect(_on_chat_message_received)
		print("[Communications] Connected to ChatMessageReceived")
	else:
		print("[Communications] ERROR: ChatMessageReceived signal not found!")
	
	if GameManager.has_signal("MediaSyncReceived"):
		GameManager.MediaSyncReceived.connect(_on_media_sync_received)
		print("[Communications] Connected to MediaSyncReceived")

	var status_timer = Timer.new()
	status_timer.wait_time = 1.0
	status_timer.autostart = true
	status_timer.timeout.connect(_on_status_timer_timeout)
	add_child(status_timer)

	var ingame_timer = Timer.new()
	ingame_timer.name = "IngameTimer"
	ingame_timer.wait_time = 1.0
	ingame_timer.autostart = false
	ingame_timer.timeout.connect(_on_ingame_timer_timeout)
	add_child(ingame_timer)

	_setup_tab_buttons()
	_setup_admin_buttons()
	_setup_info_buttons()
	_setup_popup_connections()
	_setup_button_hover_effects()
	_setup_ui_animations()
	_restrict_admin_visibility()

	if GameManager.has_signal("players_updated"):
		GameManager.players_updated.connect(update_status_info)
	_on_tab_pressed("Status")

func _setup_tab_buttons() -> void:
	var tab_container: HBoxContainer = $HSplitContainer/CommunicationsPanel/VBoxContainer/TabsContainer/TabScroll/TabHBox
	for button in tab_container.get_children():
		button.connect("pressed", Callable(self, "_on_tab_pressed").bind(button.name))
		if not multiplayer.is_server() and (button.name == "Admin" or button.name == "Server" or button.name == "Tickets"):
			button.visible = false
	left_arrow.connect("pressed", Callable(self, "_on_left_arrow_pressed"))
	right_arrow.connect("pressed", Callable(self, "_on_right_arrow_pressed"))

func _restrict_admin_visibility() -> void:
	if admin_buttons:
		admin_buttons.visible = multiplayer.is_server()
	if server_buttons:
		server_buttons.visible = multiplayer.is_server()

func _setup_info_buttons() -> void:
	for button in $HSplitContainer/CommunicationsPanel/VBoxContainer/InfoContainer/InfoScroll/InfoHBox.get_children():
		button.connect("pressed", Callable(self, "_on_info_pressed").bind(button.name))

	info_left_arrow.connect("pressed", Callable(self, "_on_info_left_arrow_pressed"))
	info_right_arrow.connect("pressed", Callable(self, "_on_info_right_arrow_pressed"))

func _setup_admin_buttons() -> void:
	$HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/AdminButtons/AdminMusic.connect("pressed", Callable(self, "_on_admin_music_pressed"))
	$HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/AdminButtons/AdminVideo.connect("pressed", Callable(self, "_on_admin_video_pressed"))
	$HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/AdminButtons/AdminArt.connect("pressed", Callable(self, "_on_admin_art_pressed"))
	$HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/ServerButtons/DelayButton.connect("pressed", Callable(self, "_on_delay_pressed"))
	$HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/ServerButtons/StartButton.connect("pressed", Callable(self, "_on_start_pressed"))
	$HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/PreferencesButtons/Preference.connect("pressed", Callable(self, "_on_preference_pressed"))

func _setup_popup_connections() -> void:
	media_popup.media_selected.connect(_on_media_selected)
	music_options_popup.options_selected.connect(_on_music_options_selected)

func _setup_button_hover_effects() -> void:
	for container in [$HSplitContainer/CommunicationsPanel/VBoxContainer/InfoContainer/InfoScroll/InfoHBox, $HSplitContainer/CommunicationsPanel/VBoxContainer/TabsContainer/TabScroll/TabHBox]:
		for button in container.get_children():
			if button is Button:
				button.mouse_entered.connect(func(): _animate_ui_button_hover(button, true))
				button.mouse_exited.connect(func(): _animate_ui_button_hover(button, false))

func _animate_ui_button_hover(button: Button, is_hovering: bool) -> void:
	var tween: Tween = button.create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	if is_hovering:
		tween.parallel().tween_property(button, "scale", Vector2(1.08, 1.08), 0.15)
		tween.parallel().tween_property(button, "modulate", Color(0.2, 1, 1, 1), 0.15)
	else:
		tween.parallel().tween_property(button, "scale", Vector2(1.0, 1.0), 0.15)
		tween.parallel().tween_property(button, "modulate", Color(1, 1, 1, 1), 0.15)

func _setup_ui_animations() -> void:
	UIAnimationHelper.setup_button_animations($HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/AdminButtons/AdminMusic)
	UIAnimationHelper.setup_button_animations($HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/AdminButtons/AdminVideo)
	UIAnimationHelper.setup_button_animations($HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/AdminButtons/AdminArt)
	UIAnimationHelper.setup_button_animations($HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/ServerButtons/DelayButton)
	UIAnimationHelper.setup_button_animations($HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/ServerButtons/StartButton)
	media_popup.mouse_entered.connect(func(): _animate_panel_pulse(media_popup))
	music_options_popup.mouse_entered.connect(func(): _animate_panel_pulse(music_options_popup))

func _animate_panel_pulse(panel: PopupPanel) -> void:
	var tween = panel.create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(panel, "modulate", Color(1.1, 1.1, 1.1, 1), 0.2)
	tween.tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.2)

func _show_text_input() -> void:
	text_input_instance.show_input()

func _on_tab_pressed(tab_name: String) -> void:
	current_tab = tab_name
	wip_label.visible = true
	admin_buttons.visible = false
	status_info.visible = false
	server_buttons.visible = false
	preferences_buttons.visible = false
	if tab_name == "Admin" and multiplayer.is_server():
		wip_label.visible = false
		admin_buttons.visible = true
	elif tab_name == "Status":
		wip_label.visible = false
		status_info.visible = true
		update_status_info()
	elif tab_name == "Server" and multiplayer.is_server():
		wip_label.visible = false
		server_buttons.visible = true
	elif tab_name == "Preferences":
		wip_label.visible = false
		preferences_buttons.visible = true
	else:
		wip_label.text = "Work in progress - " + tab_name

func _on_info_pressed(info_name: String) -> void:
	wip_label.text = "Work in progress - " + info_name

func _on_button_hover(button: Button, entered: bool) -> void:
	var tween: Tween = create_tween()
	if entered:
		tween.tween_property(button, "modulate", Color(1.2, 1.2, 1.2, 1), 0.2)
	else:
		tween.tween_property(button, "modulate", Color(1, 1, 1, 1), 0.2)

func _load_world_map() -> void:
	if game_subviewport:
		game_subviewport.visible = false
		game_subviewport.set_process(false)
		game_subviewport.set_physics_process(false)
	
	var subviewport: SubViewport = game_subviewport.get_node_or_null("SubViewport") as SubViewport
	if not subviewport:
		push_error("Communications: Game SubViewport not found")
		return
	
	subviewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	
	var world: Node = subviewport.get_child(0) if subviewport.get_child_count() > 0 else null
	if world:
		world.add_to_group("World")
		world.set_process(false)
		world.set_physics_process(false)
	else:
		push_error("Communications: No world child found in SubViewport")

func _on_status_timer_timeout() -> void:
	if current_tab == "Status" and status_info.visible:
		update_status_info()

func update_lobby_timer() -> void:
	if lobby_timer:
		lobby_timer.wait_time = GameManager.LobbyTimeLeft
		lobby_timer.paused = GameManager.LobbyTimerPaused

func _on_ingame_timer_timeout() -> void:
	if not multiplayer or not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.is_server():
		GameManager.IngameTime += 1.0
		GameManager.rpc("SyncIngameTime", GameManager.IngameTime)
	ingame_time = GameManager.IngameTime
	if current_tab == "Status" and status_info.visible:
		var minutes: int = int(ingame_time / 60.0)
		var seconds: int = int(ingame_time) % 60
		ingame_time_label.text = "In-game time: %02d:%02d" % [minutes, seconds]

func update_status_info() -> void:
	var uid_to_name = {
		"uid://dible6m71p44g": "DDome",
		"uid://bfswxq626edux": "Hadley's_Hope"
	}
	var map_name = uid_to_name.get(GameManager.CurrentMap, "Unknown")
	map_label.text = "Map: " + map_name

	gamemode_label.text = "Gamemode: " + GameManager.Gamemode

	players_label.text = "Players: " + str(GameManager.PlayerCount) + "/" + str(GameManager.MaxPlayers)

	if not game_started:
		var time_left = GameManager.LobbyTimeLeft
		var lobby_minutes = int(time_left / 60)
		var lobby_seconds = int(time_left) % 60
		timer_label.text = "Time remaining: %02d:%02d" % [lobby_minutes, lobby_seconds]
	else:
		timer_label.text = ""

	music_label.text = "Now playing: " + current_music_name

	var real_time = Time.get_datetime_string_from_system()
	real_time_label.text = "Real time: " + real_time

	var ig_minutes: int = int(GameManager.IngameTime / 60.0)
	var ig_seconds: int = int(GameManager.IngameTime) % 60
	ingame_time_label.text = "In-game time: %02d:%02d" % [ig_minutes, ig_seconds]

func _on_left_arrow_pressed() -> void:
	var current_scroll = tab_scroll.scroll_horizontal
	var scroll_amount = 100
	tab_scroll.scroll_horizontal = max(0, current_scroll - scroll_amount)

func _on_right_arrow_pressed() -> void:
	var current_scroll = tab_scroll.scroll_horizontal
	var scroll_amount = 100
	var max_scroll = tab_scroll.get_h_scroll_bar().max_value
	tab_scroll.scroll_horizontal = min(max_scroll, current_scroll + scroll_amount)

func _on_info_left_arrow_pressed() -> void:
	var current_scroll = info_scroll.scroll_horizontal
	var scroll_amount = 100
	info_scroll.scroll_horizontal = max(0, current_scroll - scroll_amount)

func _on_info_right_arrow_pressed() -> void:
	var current_scroll = info_scroll.scroll_horizontal
	var scroll_amount = 100
	var max_scroll = info_scroll.get_h_scroll_bar().max_value
	info_scroll.scroll_horizontal = min(max_scroll, current_scroll + scroll_amount)

func _on_lobby_timer_timeout() -> void:
	if multiplayer.is_server():
		GameManager.StartGame()
		_transition_to_game()

func _transition_to_game() -> void:
	print("[Communications] _transition_to_game called")
	lobby_subviewport.visible = false
	lobby_subviewport.set_process(false)
	
	game_subviewport.visible = true
	game_subviewport.set_process(true)
	game_subviewport.set_physics_process(true)
	print("[Communications] Game viewport set to visible")
	
	var subviewport: SubViewport = game_subviewport.get_node_or_null("SubViewport") as SubViewport
	if subviewport and subviewport.get_child_count() > 0:
		var world: Node = subviewport.get_child(0)
		world.set_process(true)
		world.set_physics_process(true)
	else:
		push_error("Communications: Game world not found in SubViewport")
	
	game_started = true
	timer_label.text = ""
	var ingame_timer: Timer = get_node_or_null("IngameTimer") as Timer
	if ingame_timer:
		ingame_timer.start()

func _on_admin_music_pressed() -> void:
	music_options_popup.popup_centered()

func _on_music_options_selected(loops: int, volume: float) -> void:
	music_loops = loops
	music_volume = volume
	var lobby = lobby_subviewport.get_node("SubViewport/Lobby")
	if lobby:
		lobby.music_loops = loops
		lobby.music_volume = volume
	media_popup.open_for_type("music")

func _on_admin_video_pressed() -> void:
	media_popup.open_for_type("video")

func _on_admin_art_pressed() -> void:
	media_popup.open_for_type("art")

func _on_delay_pressed() -> void:
	if multiplayer.is_server():
		GameManager.LobbyTimerPaused = !GameManager.LobbyTimerPaused
		var timer = GameManager.get_node_or_null("LobbyTimer")
		if timer:
			timer.paused = GameManager.LobbyTimerPaused
		GameManager.rpc("SyncLobbyStateToAll", GameManager.LobbyTimeLeft, GameManager.LobbyTimerPaused, GameManager.CurrentVideoUid)

func _on_start_pressed() -> void:
	_on_lobby_timer_timeout()

func _on_preference_pressed() -> void:
	var pref_scene = preload("uid://cqwq1gi0y8mph")
	if pref_scene:
		var pref = pref_scene.instantiate()
		get_tree().root.add_child(pref)
		pref.popup_centered()

func _on_media_selected(type: String, path: String) -> void:
	if not multiplayer.is_server():
		return
	
	var lobby_viewport: SubViewport = lobby_subviewport.get_node_or_null("SubViewport") as SubViewport
	if lobby_viewport and lobby_viewport.get_child_count() > 0:
		var lobby: Node = lobby_viewport.get_child(0)
		if "load_media" in lobby:
			if type == "music":
				lobby.load_media(type, path, music_loops, music_volume)
			else:
				lobby.load_media(type, path)
			if type == "music":
				var path_parts = path.split("/")
				current_music_name = path_parts[-1] if path_parts.size() > 0 else "Unknown"
	
	if GameManager.has_signal("media_sync_received"):
		GameManager.emit_signal("media_sync_received", type, path, music_loops if type == "music" else 0, music_volume if type == "music" else 0.5)
	
	if type == "video":
		_sync_video_to_all_peers.rpc(path)

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("text") and text_input_instance:
		if text_input_instance.visible:
			text_input_instance.hide()
		else:
			_show_text_input()
		get_viewport().set_input_as_handled()
	
	if event.is_action_pressed("Adminspawn") and multiplayer.is_server():
		if admin_spawn_popup:
			admin_spawn_popup.visible = !admin_spawn_popup.visible
		get_viewport().set_input_as_handled()
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if admin_spawn_popup and admin_spawn_popup.spawn_mode:
			var subviewport = game_subviewport.get_node_or_null("SubViewport")
			if subviewport and subviewport.get_child_count() > 0:
				var world = subviewport.get_child(0)
				var player = null
				for child in world.get_children():
					if child.name.is_valid_int():
						player = child
						break
				
				if player:
					var cam = player.get_node_or_null("PlayerCameraSetup")
					if cam:
						var mouse_world_pos = cam.get_screen_center_position() + (event.position - get_viewport().get_visible_rect().size / 2) / cam.zoom
						admin_spawn_popup.try_spawn_at_position(mouse_world_pos)
						get_viewport().set_input_as_handled()

func _get_player_name(peer_id: int) -> String:
	# Try to get the name from PreferenceManager
	
	# Fallback to PreferenceManager
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		var char_data = game_manager.call("GetPeerCharacterData", peer_id)
		if char_data and char_data.has("name"):
			return char_data["name"]
	
	var pref_manager = get_node_or_null("/root/PreferenceManager")
	if pref_manager:
		var char_data2 = pref_manager.get_peer_character_data(peer_id)
		if char_data2 and char_data2.has("name"):
			return char_data2["name"]
	
	# Fallback to default name
	return "Player " + str(peer_id)

func _on_message_sent(message: String, mode: String) -> void:
	print("[Communications] _on_message_sent called: ", message, " mode: ", mode)
	var peer_id: int = multiplayer.get_unique_id()
	var peer_name: String = _get_player_name(peer_id)
	print("[Communications] Sending as peer ", peer_id, " name: ", peer_name)
	if multiplayer.is_server():
		GameManager.call("SendChatMessage", peer_id, peer_name, message, mode)
	else:
		GameManager.rpc_id(1, "SendChatMessage", peer_id, peer_name, message, mode)

func _on_chat_message_received(sender_peer_id: int, sender_name: String, message: String, mode: String = "IC") -> void:
	print("[Communications] _on_chat_message_received: ", sender_name, " said: ", message, " mode: ", mode)
	_add_chat_message(sender_name, message, mode)

func _add_chat_message(sender: String, message: String, mode: String = "IC") -> void:
	print("[Communications] _add_chat_message: ", sender, " - ", message, " mode: ", mode)
	if not chat_vbox:
		push_error("Communications: Chat VBoxContainer not found")
		return

	if chat_vbox.get_child_count() >= 100:
		var first = chat_vbox.get_child(0)
		chat_vbox.remove_child(first)
		first.queue_free()

	var label: RichTextLabel = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 300
	label.scroll_active = false
	
	var formatted_text: String = ""
	match mode:
		"OOC":
			formatted_text = "[color=#4DA6FF][OOC] %s: %s[/color]" % [sender, message]
		"LOOC":
			formatted_text = "[color=#FFB6C1][LOOC] %s: %s[/color]" % [sender, message]
		"ME":
			formatted_text = "[i]*%s %s*[/i]" % [sender, message]
		_:
			formatted_text = "[%s]: %s" % [sender, message]
	
	label.text = formatted_text
	print("[Communications] Adding label with text: ", formatted_text)
	chat_vbox.add_child(label)

	var scroll_container: ScrollContainer = chat_vbox.get_parent() as ScrollContainer
	if scroll_container:
		await get_tree().process_frame
		scroll_container.scroll_vertical = int(scroll_container.get_v_scroll_bar().max_value)

# Public method for other systems to add chat messages
func AddChatMessage(message: String, mode: String = "IC", sender: String = "") -> void:
	print("[Communications] AddChatMessage called: ", message, " mode: ", mode, " sender: ", sender)
	_add_chat_message(sender, message, mode)

func _show_chat_bubble_for_player(peer_id: int, message: String) -> void:
	if not game_started:
		return
	
	var subviewport = game_subviewport.get_node_or_null("SubViewport")
	if not subviewport or subviewport.get_child_count() == 0:
		return
	
	var world = subviewport.get_child(0)
	var player = world.get_node_or_null(str(peer_id))
	
	if player and player.has_method("ShowChatBubble"):
		player.call("ShowChatBubble", message)

func broadcast_status_to_peers() -> void:
	if multiplayer.is_server():
		GameManager.rpc("SyncStatusInfo", GameManager.CurrentMap, GameManager.Gamemode, GameManager.PlayerCount)

func sync_player_position_and_rotation(player_id: int, pos: Vector2, rot: float) -> void:
	if not multiplayer.is_server():
		GameManager.rpc_id(1, "SyncPlayerTransform", player_id, pos, rot)
	else:
		GameManager.rpc("SyncPlayerTransform", player_id, pos, rot)

func _on_game_started() -> void:
	print("[Communications] _on_game_started called on peer ", multiplayer.get_unique_id())
	_transition_to_game()

func _on_media_sync_received(type: String, path: String, _loops: int, _volume: float) -> void:
	var lobby_viewport: SubViewport = lobby_subviewport.get_node_or_null("SubViewport") as SubViewport
	if not lobby_viewport:
		return
	
	if lobby_viewport.get_child_count() == 0:
		return
	
	var lobby: Node = lobby_viewport.get_child(0)
	if not lobby:
		return
	
	if "load_media" in lobby:
		lobby.load_media(type, path)
		if type == "music":
			var path_parts = path.split("/")
			current_music_name = path_parts[-1] if path_parts.size() > 0 else "Unknown"

@rpc("authority", "call_local", "reliable")
func _sync_video_to_all_peers(path: String) -> void:
	var lobby_viewport: SubViewport = lobby_subviewport.get_node_or_null("SubViewport") as SubViewport
	if lobby_viewport and lobby_viewport.get_child_count() > 0:
		var lobby: Node = lobby_viewport.get_child(0)
		if "load_media" in lobby:
			lobby.load_media("video", path)
