extends Control

# Communications - the old prototype's full game shell (its own original
# code): a permanent side panel (chat, tab bar, lobby timer) wrapped around
# two SubViewports that swap between a lobby screensaver and the live game.
# Restored per the user's explicit "exactly as it was" call, rewired onto
# the current architecture rather than the old GameManager god-object:
#  - GameManager doesn't exist here at all (never ported - its
#    responsibilities split into TickerSubsystem/NetworkManager/
#    ChatManager/JobManager earlier this session). Every GameManager.* call
#    site below maps onto one of those instead, or onto locally-derivable
#    state where nothing server-authoritative is needed.
#  - The game SubViewport holds a GameRoot.tscn instance (not the old
#    hardcoded DDome map - old maps are dropped per the user's call; new
#    maps get built fresh or DMM-imported later). GameRoot.cs's own node
#    lookups are relative to itself, so embedding it works unmodified.
#  - Round transition (lobby -> game) uses GameRoot.LocalPlayerSpawned
#    (already proven by the old LobbyScreen.gd) instead of a GameStarted
#    signal - it fires uniformly for both "round just started" and
#    "joined after the round already started," so there's no separate
#    late-join transition path needed here anymore.
#  - Chat routes through ChatManager.SendLocalMessage/MessageReceived
#    (mode-aware now - see ChatManager.cs) instead of
#    GameManager.SendChatFromPlayer/ChatMessageReceived. No character-data/
#    Discord-tag name resolution exists yet, so chat just uses the sender
#    name ChatManager already provides.
#  - The lobby countdown reuses the scene's own $LobbyTimer node directly
#    (Godot's Timer already does countdown/pause natively) instead of
#    GameManager.LobbyTimeLeft/LobbyTimerPaused - the server periodically
#    RPCs its time_left/paused to keep other peers' displays in sync.
#  - Admin/Server tools that already have real restored scenes (Music/
#    Media/AdminSpawner popups) stay real; EntitySpawner/BuildMode/
#    Preferences reference scripts that weren't restored this pass -
#    guarded to fall back to the WIP label instead of hard-erroring.
#  - Everything that was ALREADY a stub in the original (info-bar links,
#    Debug/IC/OOC/Object/Tickets/Options tabs, DayNightToggle/
#    ShadowQualitySlider, BackToLobby's get_tree().quit()) is untouched -
#    leaving them exactly as inert as they already were IS "exactly as it
#    was," not a gap to fill.

@onready var tabview: TextureRect = $HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview
@onready var wip_label: Label = $HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/WorkInProgressLabel
@onready var chat_vbox: VBoxContainer = $HSplitContainer/CommunicationsPanel/VSplitContainer/Chat/VBoxContainer
@onready var tab_scroll: ScrollContainer = $HSplitContainer/CommunicationsPanel/VBoxContainer/TabsContainer/TabScroll
@onready var left_arrow: Button = $HSplitContainer/CommunicationsPanel/VBoxContainer/TabsContainer/LeftArrow
@onready var right_arrow: Button = $HSplitContainer/CommunicationsPanel/VBoxContainer/TabsContainer/RightArrow
@onready var info_scroll: ScrollContainer = $HSplitContainer/CommunicationsPanel/VBoxContainer/InfoContainer/InfoScroll
@onready var info_left_arrow: Button = $HSplitContainer/CommunicationsPanel/VBoxContainer/InfoContainer/InfoLeftArrow
@onready var info_right_arrow: Button = $HSplitContainer/CommunicationsPanel/VBoxContainer/InfoContainer/InfoRightArrow
@onready var lobby_timer: Timer = $LobbyTimer
@onready var game_subviewport: SubViewportContainer = $HSplitContainer/SubViewportContainer
@onready var lobby_subviewport: SubViewportContainer = $HSplitContainer/SubViewportContainer2
@onready var admin_buttons: VBoxContainer = $HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/AdminButtons
@onready var status_info: VBoxContainer = $HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/StatusInfo
@onready var server_buttons: VBoxContainer = $HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/ServerButtons
@onready var preferences_buttons: VBoxContainer = $HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/PreferencesButtons
@onready var back_to_lobby_button: Button = $HSplitContainer/CommunicationsPanel/VSplitContainer/Tabview/PreferencesButtons/BackToLobby
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
@onready var audio_manager: Node = get_node_or_null("/root/AudioManager")
@onready var late_join_ui: Control = $LateJoinLobbyUI

var text_input_instance = null
var music_loops: int = 1
var music_volume: float = 0.5
var current_music_name: String = "None"
var game_started: bool = false
var current_tab: String = ""

var embedded_game_root: Node = null
var local_mob: Node = null

func _ready() -> void:
	set_process_input(true)
	set_process_unhandled_input(true)

	_load_world_map()

	var text_input_scene = load("uid://2oufqaxsmbt8")
	if text_input_scene == null:
		text_input_scene = load("res://Scenes/UI/TextInput.tscn")
	if text_input_scene:
		text_input_instance = text_input_scene.instantiate()
		add_child(text_input_instance)
		text_input_instance.message_sent.connect(_on_message_sent)

	ChatManager.MessageReceived.connect(_on_chat_message_received)
	if embedded_game_root and embedded_game_root.has_signal("LocalPlayerSpawned"):
		embedded_game_root.LocalPlayerSpawned.connect(_on_local_player_spawned)

	var status_timer = Timer.new()
	status_timer.wait_time = 1.0
	status_timer.autostart = true
	status_timer.timeout.connect(_on_status_timer_timeout)
	add_child(status_timer)

	_setup_tab_buttons()
	_setup_admin_buttons()
	_setup_info_buttons()
	_setup_popup_connections()
	_setup_button_hover_effects()
	_setup_ui_animations()
	_refresh_admin_visibility()

	_on_tab_pressed("Status")
	update_lobby_timer()

func show_late_join_ui() -> void:
	if late_join_ui:
		late_join_ui.visible = true
		late_join_ui.mouse_filter = Control.MOUSE_FILTER_STOP

func send_system_message(message: String) -> void:
	_add_chat_message("System", message, "System")

func _setup_tab_buttons() -> void:
	var tab_container: HBoxContainer = $HSplitContainer/CommunicationsPanel/VBoxContainer/TabsContainer/TabScroll/TabHBox
	for button in tab_container.get_children():
		button.connect("pressed", Callable(self, "_on_tab_pressed").bind(button.name))
	left_arrow.connect("pressed", Callable(self, "_on_left_arrow_pressed"))
	right_arrow.connect("pressed", Callable(self, "_on_right_arrow_pressed"))
	_refresh_admin_visibility()

func _local_has_admin_privileges() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()

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

# Embeds a fresh GameRoot.tscn (not the old hardcoded DDome map - see
# header) into the game SubViewport, frozen/hidden until round start.
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

	embedded_game_root = subviewport.get_child(0) if subviewport.get_child_count() > 0 else null
	if embedded_game_root:
		embedded_game_root.set_process(false)
		embedded_game_root.set_physics_process(false)
	else:
		push_error("Communications: No GameRoot child found in SubViewport")

func _on_status_timer_timeout() -> void:
	if not is_inside_tree():
		return
	_refresh_admin_visibility()
	if current_tab == "Status" and status_info.visible:
		update_status_info()
	if multiplayer.is_server() and _is_network_ready_for_rpc() and lobby_timer and not game_started:
		_sync_lobby_timer_to_peers.rpc(lobby_timer.time_left, lobby_timer.paused)

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
		lobby_timer.timeout.connect(_on_lobby_timer_timeout)
		lobby_timer.start()

@rpc("authority", "call_remote", "unreliable")
func _sync_lobby_timer_to_peers(time_left: float, paused: bool) -> void:
	if lobby_timer and not game_started:
		lobby_timer.start(time_left)
		lobby_timer.paused = paused

func update_status_info() -> void:
	map_label.text = "Map: Test Map"
	gamemode_label.text = "Gamemode: N/A"

	var player_count := 1
	if multiplayer.has_multiplayer_peer():
		player_count = multiplayer.get_peers().size() + 1
	players_label.text = "Players: " + str(player_count)

	if not game_started and lobby_timer:
		var time_left = lobby_timer.time_left
		var lobby_minutes = int(time_left / 60)
		var lobby_seconds = int(time_left) % 60
		timer_label.text = "Time remaining: %02d:%02d" % [lobby_minutes, lobby_seconds]
	else:
		timer_label.text = ""

	music_label.text = "Now playing: " + current_music_name

	var real_time = Time.get_datetime_string_from_system()
	real_time_label.text = "Real time: " + real_time

	# No round-elapsed clock exposed to GDScript yet (TickerSubsystem's
	# RoundElapsedSeconds is a C#-only property) - left blank rather than
	# faked.
	ingame_time_label.text = ""

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
	if multiplayer.is_server() and embedded_game_root and embedded_game_root.has_method("ServerStartRound"):
		embedded_game_root.ServerStartRound()

# Fires for this peer's own mob both on round start AND on a late join -
# GameRoot.LocalPlayerSpawned already covers both cases (see header), so
# there's no separate late-join transition path to maintain here.
func _on_local_player_spawned(mob: Node) -> void:
	local_mob = mob
	if text_input_instance:
		text_input_instance.mob = mob
	if late_join_ui:
		late_join_ui.visible = false
	_transition_to_game()

func _transition_to_game() -> void:
	if not lobby_subviewport or not game_subviewport:
		return

	lobby_subviewport.visible = false
	lobby_subviewport.set_process(false)
	lobby_subviewport.set_physics_process(false)

	game_subviewport.visible = true
	game_subviewport.set_process(true)
	game_subviewport.set_physics_process(true)

	if embedded_game_root:
		embedded_game_root.set_process(true)
		embedded_game_root.set_physics_process(true)

	var subviewport: SubViewport = game_subviewport.get_node_or_null("SubViewport") as SubViewport
	if subviewport:
		subviewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE

	game_started = true
	timer_label.text = ""
	_hide_server_round_controls()
	if text_input_instance:
		text_input_instance.round_playing = true

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
	var lobby = lobby_subviewport.get_node_or_null("SubViewport/LobbyScreen")
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
	_try_open_admin_tool("uid://65fg0lmyurrp", "Entity Spawner")

func _on_build_mode_pressed() -> void:
	if audio_manager:
		audio_manager.play_ui_click()
	_try_open_admin_tool("uid://d5qqddm1cxen", "Build Mode")

func _on_preference_pressed() -> void:
	if audio_manager:
		audio_manager.play_ui_click()
	_try_open_admin_tool("uid://cqwq1gi0y8mph", "Preferences")

# EntitySpawner/BuildMode/Preferences popup scripts weren't restored this
# pass - guard so clicking one falls back to the WIP label instead of
# hard-erroring on a missing script.
func _try_open_admin_tool(uid: String, label: String) -> void:
	if not ResourceLoader.exists(uid):
		wip_label.visible = true
		wip_label.text = "Work in progress - " + label
		return
	var scene: PackedScene = load(uid)
	var instance = scene.instantiate()
	get_tree().root.add_child(instance)
	instance.show()

func _on_delay_pressed() -> void:
	if not is_inside_tree():
		return
	if audio_manager:
		audio_manager.play_ui_click()
	if _is_network_ready_for_rpc() and multiplayer.is_server() and lobby_timer:
		lobby_timer.paused = not lobby_timer.paused

func _on_start_pressed() -> void:
	if not is_inside_tree():
		return
	if audio_manager:
		audio_manager.play_ui_click()
	if _is_network_ready_for_rpc() and multiplayer.is_server() and embedded_game_root and embedded_game_root.has_method("ServerStartRound"):
		embedded_game_root.ServerStartRound()

func _on_back_to_lobby_pressed() -> void:
	if audio_manager:
		audio_manager.play_ui_click()
	get_tree().quit()

func _on_media_selected(type: String, path: String) -> void:
	var synced_path := _normalize_media_path_for_sync(path)
	if synced_path == "":
		music_label.text = "Media sync failed: invalid file path."
		return

	# Local-only: applies to this peer's own lobby view. No server-side
	# media relay exists yet to broadcast the choice to other peers.
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

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("text"):
		_toggle_text_input()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("text"):
		_toggle_text_input()

func _on_chat_message_received(speaker_name: String, message: String, mode: String) -> void:
	if audio_manager:
		audio_manager.play_chat_message()
	_add_chat_message(speaker_name, message, mode)

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

func _on_message_sent(message: String, mode: String) -> void:
	if not _is_network_ready_for_rpc():
		return
	ChatManager.SendLocalMessage(message, mode)

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
