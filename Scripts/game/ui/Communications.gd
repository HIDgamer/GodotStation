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
@onready var back_to_lobby_button: Button = $HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/PreferencesButtons/BackToLobby
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
@onready var audio_manager: Node = $/root/AudioManager
@onready var late_join_ui: Control = $LateJoinLobbyUI
var text_input_instance = null
var music_loops: int = 1
var music_volume: float = 0.5
var current_music_name: String = "None"
var ingame_time: float = 0.0
var game_started: bool = false
var late_joiner_detected: bool = false

var current_tab: String = ""

func _ready() -> void:
	add_to_group("Communications")
	set_process_input(true)
	set_process_unhandled_input(true)
	print("[Communications] _ready() called at ", Time.get_ticks_msec())
	print("[Communications] multiplayer.is_server() = ", multiplayer.is_server())
	print("[Communications] multiplayer.get_unique_id() = ", multiplayer.get_unique_id())
	
	_load_world_map()
	
	var text_input_scene = load("uid://2oufqaxsmbt8")
	if text_input_scene == null:
		text_input_scene = load("res://Scenes/game/ui/TextInput.tscn")
	if text_input_scene:
		text_input_instance = text_input_scene.instantiate()
		add_child(text_input_instance)
		text_input_instance.message_sent.connect(_on_message_sent)

	_connect_gm_signal(["LobbyTimeout", "lobby_timeout"], Callable(self, "_on_lobby_timer_timeout"))
	_connect_gm_signal(["GameStarted", "game_started"], Callable(self, "_on_game_started"))
	_connect_gm_signal(["ChatMessageReceived", "chat_message_received"], Callable(self, "_on_chat_message_received"))
	_connect_gm_signal(["MediaSyncReceived", "media_sync_received"], Callable(self, "_on_media_sync_received"))
	_connect_gm_signal(["LobbyStateSynced", "lobby_state_synced"], Callable(self, "_on_lobby_state_synced"))
	_connect_gm_signal(["LateJoinerTransitioned", "late_joiner_transitioned"], Callable(self, "_on_late_joiner_transitioned"))

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

	var debug_timer = Timer.new()
	debug_timer.name = "DebugTimer"
	debug_timer.wait_time = 2.0
	debug_timer.autostart = true
	debug_timer.timeout.connect(_on_debug_timer_timeout)
	add_child(debug_timer)

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
	update_lobby_timer()
	
	print("[Communications] At end of _ready:")
	
	if GameManager == null:
		print("  - ERROR: GameManager is NULL!")
	else:
		var is_running = GameManager.call("IsGameRunning") if GameManager.has_method("IsGameRunning") else "METHOD NOT FOUND"
		print("  - GameManager exists: YES")
		print("  - GameManager.IsGameRunning() = ", is_running)
	
	print("  - game_started = ", game_started)
	
	if lobby_subviewport:
		print("  - lobby_subviewport exists: YES, visible = ", lobby_subviewport.visible)
	else:
		print("  - lobby_subviewport exists: NO")
	
	if game_subviewport:
		print("  - game_subviewport exists: YES, visible = ", game_subviewport.visible)
	else:
		print("  - game_subviewport exists: NO")

func _on_late_joiner_transitioned(peer_id: int) -> void:
	print("[Communications] Late joiner ", peer_id, " has spawned into the game")
	
	if peer_id == multiplayer.get_unique_id():
		print("[Communications] This is me! Finalizing late join transition")
		_finalize_late_join_transition()

func _finalize_late_join_transition() -> void:
	print("[Communications] Finalizing late join transition")
	
	if late_join_ui:
		late_join_ui.visible = false
	
	if lobby_subviewport:
		lobby_subviewport.visible = false
		lobby_subviewport.set_process(false)
		lobby_subviewport.set_physics_process(false)
		print("[Communications] Lobby viewport hidden")
	
	if game_subviewport:
		game_subviewport.visible = true
		game_subviewport.set_process(true)
		game_subviewport.set_physics_process(true)
		print("[Communications] Game viewport shown")
	
	await get_tree().process_frame
	
	var subviewport: SubViewport = game_subviewport.get_node_or_null("SubViewport") as SubViewport
	if subviewport and subviewport.get_child_count() > 0:
		var world: Node = subviewport.get_child(0)
		world.set_process(true)
		world.set_physics_process(true)
		subviewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		print("[Communications] World enabled for late join")
	
	game_started = true
	timer_label.text = ""
	_hide_server_round_controls()
	
	var ingame_timer = get_node_or_null("IngameTimer")
	if ingame_timer:
		if ingame_timer.is_stopped():
			ingame_timer.start()
		print("[Communications] Ingame timer started")
	
	print("[Communications] Late join transition finalized")

func show_late_join_ui() -> void:
	if late_join_ui:
		late_join_ui.visible = true
		late_join_ui.mouse_filter = Control.MOUSE_FILTER_STOP
		late_joiner_detected = true
		print("[Communications] Late join UI shown")
	else:
		print("[Communications] ERROR: late_join_ui node not found at $LateJoinLobbyUI")

func send_system_message(message: String) -> void:
	if has_method("AddChatMessage"):
		AddChatMessage(message, "System", "System")

func _connect_gm_signal(signal_names: Array, target_callable: Callable) -> bool:
	for signal_name in signal_names:
		if GameManager.has_signal(signal_name):
			GameManager.connect(signal_name, target_callable)
			return true
	return false

func _setup_tab_buttons() -> void:
	var tab_container: HBoxContainer = $HSplitContainer/CommunicationsPanel/VBoxContainer/TabsContainer/TabScroll/TabHBox
	for button in tab_container.get_children():
		button.connect("pressed", Callable(self, "_on_tab_pressed").bind(button.name))
	left_arrow.connect("pressed", Callable(self, "_on_left_arrow_pressed"))
	right_arrow.connect("pressed", Callable(self, "_on_right_arrow_pressed"))
	_refresh_admin_visibility()

func _restrict_admin_visibility() -> void:
	_refresh_admin_visibility()

func _local_has_admin_privileges() -> bool:
	# If there is no active multiplayer peer yet (e.g. still connecting, or
	# connection failed and peer was cleared) calling get_unique_id() in C# will
	# throw a C++ error. Bail out early so we don't crash every timer tick.
	if not multiplayer.has_multiplayer_peer():
		return false
	if multiplayer.is_server():
		return true
	if GameManager == null:
		return false
	if GameManager.has_method("LocalPlayerCanStartGame"):
		return bool(GameManager.call("LocalPlayerCanStartGame"))
	if GameManager.has_method("GetPeerRole"):
		var role = int(GameManager.call("GetPeerRole", multiplayer.get_unique_id()))
		return role >= 2
	return false

func _refresh_admin_visibility() -> void:
	var can_admin := _local_has_admin_privileges()

	var tab_container: HBoxContainer = $HSplitContainer/CommunicationsPanel/VBoxContainer/TabsContainer/TabScroll/TabHBox
	for button in tab_container.get_children():
		if button.name == "Admin" or button.name == "Server" or button.name == "Tickets":
			button.visible = can_admin

	if admin_buttons:
		admin_buttons.visible = can_admin and current_tab == "Admin"
	if server_buttons:
		server_buttons.visible = can_admin and current_tab == "Server"

func _setup_info_buttons() -> void:
	for button in $HSplitContainer/CommunicationsPanel/VBoxContainer/InfoContainer/InfoScroll/InfoHBox.get_children():
		button.connect("pressed", Callable(self, "_on_info_pressed").bind(button.name))

	info_left_arrow.connect("pressed", Callable(self, "_on_info_left_arrow_pressed"))
	info_right_arrow.connect("pressed", Callable(self, "_on_info_right_arrow_pressed"))

func _setup_admin_buttons() -> void:
	$HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/AdminButtons/AdminMusic.connect("pressed", Callable(self, "_on_admin_music_pressed"))
	$HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/AdminButtons/AdminVideo.connect("pressed", Callable(self, "_on_admin_video_pressed"))
	$HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/AdminButtons/AdminArt.connect("pressed", Callable(self, "_on_admin_art_pressed"))
	$HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/AdminButtons/AdminSpawner.connect("pressed", Callable(self, "_on_admin_spawner_pressed"))
	$HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/AdminButtons/EntitySpawner.connect("pressed", Callable(self, "_on_entity_spawner_pressed"))
	$HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/AdminButtons/BuildMode.connect("pressed", Callable(self, "_on_build_mode_pressed"))
	$HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/ServerButtons/DelayButton.connect("pressed", Callable(self, "_on_delay_pressed"))
	$HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/ServerButtons/StartButton.connect("pressed", Callable(self, "_on_start_pressed"))
	$HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/PreferencesButtons/Preference.connect("pressed", Callable(self, "_on_preference_pressed"))
	back_to_lobby_button.connect("pressed", Callable(self, "_on_back_to_lobby_pressed"))

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
	UIAnimationHelper.setup_button_animations(back_to_lobby_button)

func _show_text_input() -> void:
	if text_input_instance == null:
		return
	if text_input_instance.has_method("show_input"):
		text_input_instance.call_deferred("show_input")
	else:
		text_input_instance.visible = true

func _toggle_text_input() -> void:
	if text_input_instance == null:
		return
	if text_input_instance.visible:
		text_input_instance.hide()
	else:
		_show_text_input()
	get_viewport().set_input_as_handled()

func _on_tab_pressed(tab_name: String) -> void:
	if audio_manager:
		audio_manager.play_ui_click()
	current_tab = tab_name
	wip_label.visible = true
	admin_buttons.visible = false
	status_info.visible = false
	server_buttons.visible = false
	preferences_buttons.visible = false
	if tab_name == "Admin" and _local_has_admin_privileges():
		wip_label.visible = false
		admin_buttons.visible = true
	elif tab_name == "Status":
		wip_label.visible = false
		status_info.visible = true
		update_status_info()
	elif tab_name == "Server" and _local_has_admin_privileges():
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
	
	subviewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	
	var world: Node = subviewport.get_child(0) if subviewport.get_child_count() > 0 else null
	if world:
		world.add_to_group("World")
		world.set_process(false)
		world.set_physics_process(false)
	else:
		push_error("Communications: No world child found in SubViewport")

func _on_status_timer_timeout() -> void:
	if not is_inside_tree():
		return
	_refresh_admin_visibility()
	if current_tab == "Status" and status_info.visible:
		update_status_info()
	if multiplayer.is_server() and _is_network_ready_for_rpc():
		broadcast_status_to_peers()

func _is_network_ready_for_rpc() -> bool:
	if not is_inside_tree():
		return false
	if not multiplayer or not multiplayer.has_multiplayer_peer():
		return false
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null:
		return false
	if not (peer is ENetMultiplayerPeer):
		return false
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func update_lobby_timer() -> void:
	if lobby_timer:
		lobby_timer.start(GameManager.LobbyTimeLeft)
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
	if GameManager.has_method("get"):
		var gm_music: String = str(GameManager.CurrentMusicName)
		if gm_music != "":
			current_music_name = gm_music
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
		GameManager.ForceStartFromLobby()

func _on_game_started() -> void:
	print("[Communications] _on_game_started() called at ", Time.get_ticks_msec())
	print("  - game_started before: ", game_started)
	print("  - GameManager.IsGameRunning(): ", GameManager.IsGameRunning())
	
	var is_late_joiner = false
	if GameManager.has_method("IsLateJoiner"):
		is_late_joiner = GameManager.call("IsLateJoiner", multiplayer.get_unique_id())
		print("  - Is late joiner: ", is_late_joiner)
	
	if is_late_joiner:
		print("[Communications] This peer is a late joiner, UI will be shown separately")
		return
	
	_transition_to_game()
	print("  - game_started after: ", game_started)

func _transition_to_game() -> void:
	print("[Communications] _transition_to_game() called at ", Time.get_ticks_msec())
	
	if not lobby_subviewport:
		push_error("[Communications] lobby_subviewport is NULL! Path: $HSplitContainer/SubViewportContainer2")
		print("  - ERROR: lobby_subviewport node not found!")
		return
	
	if not game_subviewport:
		push_error("[Communications] game_subviewport is NULL! Path: $HSplitContainer/SubViewportContainer")
		print("  - ERROR: game_subviewport node not found!")
		return
	
	print("  - BEFORE: lobby_subviewport.visible = ", lobby_subviewport.visible)
	print("  - BEFORE: game_subviewport.visible = ", game_subviewport.visible)
	print("  - BEFORE: game_started = ", game_started)
	
	lobby_subviewport.visible = false
	lobby_subviewport.set_process(false)
	lobby_subviewport.set_physics_process(false)
	
	game_subviewport.visible = true
	game_subviewport.set_process(true)
	game_subviewport.set_physics_process(true)
	
	await get_tree().process_frame
	
	print("  - AFTER setting visibility: lobby visible = ", lobby_subviewport.visible)
	print("  - AFTER setting visibility: game visible = ", game_subviewport.visible)
	
	var subviewport: SubViewport = game_subviewport.get_node_or_null("SubViewport") as SubViewport
	if subviewport and subviewport.get_child_count() > 0:
		var world: Node = subviewport.get_child(0)
		world.set_process(true)
		world.set_physics_process(true)
		subviewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		print("  - World found and enabled: ", world.name)
	else:
		push_error("Communications: Game world not found in SubViewport")
		print("  - ERROR: No world found in game SubViewport!")
		if subviewport:
			print("  - SubViewport exists but child count = ", subviewport.get_child_count())
	
	game_started = true
	timer_label.text = ""
	_hide_server_round_controls()
	var ingame_timer: Timer = get_node_or_null("IngameTimer") as Timer
	if ingame_timer:
		ingame_timer.start()
		print("  - Ingame timer started")
	
	print("  - FINAL: game_started = ", game_started)
	print("  - FINAL: lobby visible = ", lobby_subviewport.visible)
	print("  - FINAL: game visible = ", game_subviewport.visible)

func _on_lobby_state_synced(time_left: float, paused: bool, _video_uid: String) -> void:
	if lobby_timer:
		lobby_timer.start(time_left)
		lobby_timer.paused = paused
	update_status_info()

func _hide_server_round_controls() -> void:
	var start_btn: Button = $HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/ServerButtons/StartButton
	var delay_btn: Button = $HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/ServerButtons/DelayButton
	if start_btn:
		start_btn.visible = false
		start_btn.disabled = true
	if delay_btn:
		delay_btn.visible = false
		delay_btn.disabled = true

func _on_admin_music_pressed() -> void:
	if audio_manager:
		audio_manager.play_ui_click()
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
	if audio_manager:
		audio_manager.play_ui_click()
	media_popup.open_for_type("video")

func _on_admin_art_pressed() -> void:
	if audio_manager:
		audio_manager.play_ui_click()
	media_popup.open_for_type("art")

func _on_admin_spawner_pressed() -> void:
	if audio_manager:
		audio_manager.play_ui_click()
	if admin_spawn_popup:
		admin_spawn_popup.visible = !admin_spawn_popup.visible

func _on_entity_spawner_pressed() -> void:
	if audio_manager:
		audio_manager.play_ui_click()
	var entity_spawner_scene = load("uid://65fg0lmyurrp")
	if entity_spawner_scene:
		var entity_spawner = entity_spawner_scene.instantiate()
		get_tree().root.add_child(entity_spawner)
		entity_spawner.show()

func _on_build_mode_pressed() -> void:
	if audio_manager:
		audio_manager.play_ui_click()
	var build_mode_scene = load("uid://d5qqddm1cxen")
	if build_mode_scene:
		var build_mode = build_mode_scene.instantiate()
		get_tree().root.add_child(build_mode)
		build_mode.show()

func _on_delay_pressed() -> void:
	if not is_inside_tree():
		return
	if audio_manager:
		audio_manager.play_ui_click()
	if _is_network_ready_for_rpc():
		GameManager.ToggleLobbyPause()

func _on_start_pressed() -> void:
	if not is_inside_tree():
		return
	if audio_manager:
		audio_manager.play_ui_click()
	if _is_network_ready_for_rpc():
		GameManager.ForceStartFromLobby()

func _on_preference_pressed() -> void:
	if audio_manager:
		audio_manager.play_ui_click()
	var pref_scene = preload("uid://cqwq1gi0y8mph")
	if pref_scene:
		var pref = pref_scene.instantiate()
		get_tree().root.add_child(pref)
		pref.popup_centered()

func _on_back_to_lobby_pressed() -> void:
	if audio_manager:
		audio_manager.play_ui_click()
	get_tree().quit()

func _on_media_selected(type: String, path: String) -> void:
	if not _is_network_ready_for_rpc():
		return

	var synced_path := _normalize_media_path_for_sync(path)
	if synced_path == "":
		music_label.text = "Media sync failed: invalid file path."
		return
	
	var lobby_viewport: SubViewport = lobby_subviewport.get_node_or_null("SubViewport") as SubViewport
	if lobby_viewport and lobby_viewport.get_child_count() > 0:
		var lobby: Node = lobby_viewport.get_child(0)
		if "load_media" in lobby:
			if type == "music":
				lobby.load_media(type, synced_path, music_loops, music_volume)
			else:
				lobby.load_media(type, synced_path)
			if type == "music":
				var path_parts = synced_path.split("/")
				current_music_name = path_parts[-1] if path_parts.size() > 0 else "Unknown"

	var loops := music_loops if type == "music" else 0
	var volume := music_volume if type == "music" else 0.5
	if GameManager.has_method("RequestMediaSyncFromClient"):
		GameManager.call("RequestMediaSyncFromClient", type, synced_path, loops, volume)
	else:
		GameManager.SyncMedia(type, synced_path, loops, volume)

func _on_media_sync_received(type: String, path: String, loops: int, volume: float) -> void:
	if path == "":
		return

	var lobby_viewport: SubViewport = lobby_subviewport.get_node_or_null("SubViewport") as SubViewport
	if not lobby_viewport:
		return
	
	if lobby_viewport.get_child_count() == 0:
		return
	
	var lobby: Node = lobby_viewport.get_child(0)
	if not lobby:
		return
	
	if "load_media" in lobby:
		if type == "music":
			lobby.load_media(type, path, loops, volume)
		else:
			lobby.load_media(type, path)
		if type == "music":
			var path_parts = path.split("/")
			current_music_name = path_parts[-1] if path_parts.size() > 0 else "Unknown"

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("text"):
		_toggle_text_input()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("text"):
		_toggle_text_input()

func _get_player_name(peer_id: int) -> String:
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
	return "Player " + str(peer_id)

func _get_discord_tag(peer_id: int, fallback: String = "") -> String:
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("GetDiscordTagForPeer"):
		var tag = str(game_manager.call("GetDiscordTagForPeer", peer_id))
		if tag != "":
			return tag
	return fallback

func _format_sender_for_mode(sender_peer_id: int, sender_name: String, mode: String) -> String:
	var ic_name: String = _get_player_name(sender_peer_id)
	if ic_name == "":
		ic_name = sender_name if sender_name != "" else "Player " + str(sender_peer_id)
	var tag: String = _get_discord_tag(sender_peer_id, sender_name)

	match mode:
		"OOC":
			return tag if tag != "" else ic_name
		"LOOC":
			if ic_name != "" and tag != "" and ic_name != tag:
				return "%s[%s]" % [ic_name, tag]
			return ic_name if ic_name != "" else tag
		_:
			return ic_name

func _on_message_sent(message: String, mode: String) -> void:
	if not _is_network_ready_for_rpc():
		return
	var peer_id: int = multiplayer.get_unique_id()
	GameManager.SendChatFromPlayer(peer_id, message, mode)

func _on_chat_message_received(sender_peer_id: int, sender_name: String, message: String, mode: String = "IC") -> void:
	if audio_manager:
		audio_manager.play_chat_message()
	var formatted_sender = _format_sender_for_mode(sender_peer_id, sender_name, mode)
	_add_chat_message(formatted_sender, message, mode)
	_show_chat_bubble_for_player(sender_peer_id, message, mode)

func _add_chat_message(sender: String, message: String, mode: String = "IC") -> void:
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
			formatted_text = "[color=#FFB6C1][LOOC] %s says: %s[/color]" % [sender, message]
		"ME":
			formatted_text = "[i]*%s %s*[/i]" % [sender, message]
		"System":
			formatted_text = "[color=#00FF00]> SYSTEM: %s[/color]" % [message]
		_:
			formatted_text = "%s says: %s" % [sender, message]
	
	label.text = formatted_text
	chat_vbox.add_child(label)

	var scroll_container: ScrollContainer = chat_vbox.get_parent() as ScrollContainer
	if scroll_container:
		await get_tree().process_frame
		scroll_container.scroll_vertical = int(scroll_container.get_v_scroll_bar().max_value)

func AddChatMessage(message: String, mode: String = "IC", sender: String = "") -> void:
	_add_chat_message(sender, message, mode)

func _show_chat_bubble_for_player(peer_id: int, message: String, mode: String = "IC") -> void:
	if message.strip_edges() == "":
		return
	if mode == "OOC":
		return

	var world: Node = get_tree().get_first_node_in_group("World")
	if not world:
		var subviewport = game_subviewport.get_node_or_null("SubViewport")
		if subviewport and subviewport.get_child_count() > 0:
			world = subviewport.get_child(0)
	if not world and lobby_subviewport:
		var lobby_viewport = lobby_subviewport.get_node_or_null("SubViewport")
		if lobby_viewport and lobby_viewport.get_child_count() > 0:
			world = lobby_viewport.get_child(0)
	if not world:
		return

	var player = world.get_node_or_null(str(peer_id))
	
	if player and player.has_method("ShowChatBubble"):
		player.call("ShowChatBubble", message, mode, false)

func broadcast_status_to_peers() -> void:
	if multiplayer.is_server() and _is_network_ready_for_rpc():
		GameManager.rpc("SyncStatusInfo", GameManager.CurrentMap, GameManager.Gamemode, GameManager.PlayerCount, current_music_name, GameManager.LobbyTimeLeft, GameManager.LobbyTimerPaused)

func sync_player_position_and_rotation(player_id: int, pos: Vector2, rot: float) -> void:
	if not multiplayer.is_server():
		GameManager.rpc_id(1, "SyncPlayerTransform", player_id, pos, rot)
	else:
		GameManager.rpc("SyncPlayerTransform", player_id, pos, rot)

func _on_debug_timer_timeout() -> void:
	var gm_is_running = false
	var current_game_state = "Unknown"
	
	if GameManager != null and GameManager.has_method("IsGameRunning"):
		gm_is_running = GameManager.call("IsGameRunning")
	
	if GameManager != null and GameManager.has_method("GetCurrentGameState"):
		var state_int = GameManager.call("GetCurrentGameState")
		match state_int:
			0: current_game_state = "Menu"
			1: current_game_state = "Lobby" 
			2: current_game_state = "Playing"
			3: current_game_state = "Hosting"
			_: current_game_state = "Unknown (%s)" % state_int
	
	var ui_state = "Lobby" if not game_started else "Game"
	var game_state = "Lobby" if not gm_is_running else "Running"
	var timestamp = Time.get_time_string_from_system()
	
	print("[Communications] Game Status Debug - UI State: %s (%s), Game State: %s (%s), Manager State: %s - Time: %s" % [
		ui_state, game_started,
		game_state, gm_is_running, 
		current_game_state,
		timestamp
	])

@rpc("authority", "call_local", "reliable")
func _sync_video_to_all_peers(path: String) -> void:
	var lobby_viewport: SubViewport = lobby_subviewport.get_node_or_null("SubViewport") as SubViewport
	if lobby_viewport and lobby_viewport.get_child_count() > 0:
		var lobby: Node = lobby_viewport.get_child(0)
		if "load_media" in lobby:
			lobby.load_media("video", path)

func _normalize_media_path_for_sync(path: String) -> String:
	if path == "":
		return ""

	if path.begins_with("uid://") or path.begins_with("res://"):
		return path
	if path.begins_with("user://"):
		return path

	var normalized: String = path.replace("\\", "/")
	if normalized.begins_with("file://"):
		normalized = normalized.trim_prefix("file://")

	var project_root: String = ProjectSettings.globalize_path("res://").replace("\\", "/")
	if not project_root.ends_with("/"):
		project_root += "/"

	if normalized.begins_with(project_root):
		return "res://" + normalized.substr(project_root.length())

	# Allow absolute local paths. These are valid for same-machine dedicated setups.
	if normalized.contains(":/") or normalized.begins_with("/"):
		return normalized

	return ""
