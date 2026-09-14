extends Window

signal message_sent(text: String, mode: String)

@onready var line_edit: LineEdit = $Container/HBoxContainer/LineEdit
@onready var send_button: Button = $Container/HBoxContainer/SendButton
@onready var mode_button: Button = $Container/HBoxContainer/ModeButton

enum ChatMode { IC, OOC, LOOC, ME }
var current_mode: ChatMode = ChatMode.IC
var selected: bool = false
var mob: Node = null
var _pending_send_lock: bool = false

func _ready() -> void:
	add_to_group("TextInput")
	exclusive = false
	send_button.connect("pressed", Callable(self, "_on_send"))
	line_edit.connect("text_submitted", Callable(self, "_on_send"))
	mode_button.connect("pressed", Callable(self, "_on_mode_button_pressed"))
	connect("close_requested", Callable(self, "_on_close_requested"))
	connect("visibility_changed", Callable(self, "_on_visibility_changed"))
	_update_mode_button()
	deselect()

func _on_send(new_text: String = "") -> void:
	if _pending_send_lock:
		return
	var text: String = new_text if new_text != "" else line_edit.text.strip_edges()
	if text == "" or text.length() > 200:
		line_edit.text = ""
		return

	var mode_str: String = _get_mode_string()
	if _is_lobby_phase() and (mode_str == "IC" or mode_str == "LOOC"):
		line_edit.text = ""
		return

	message_sent.emit(text, mode_str)
	line_edit.text = ""
	_pending_send_lock = true
	hide()

func _get_mode_string() -> String:
	match current_mode:
		ChatMode.OOC: return "OOC"
		ChatMode.LOOC: return "LOOC"
		ChatMode.ME: return "ME"
		_: return "IC"

func _on_mode_button_pressed() -> void:
	current_mode = ((current_mode + 1) % 4) as ChatMode
	_update_mode_button()

func _update_mode_button() -> void:
	if not mode_button:
		return
	match current_mode:
		ChatMode.IC:
			mode_button.text = "IC"
		ChatMode.OOC:
			mode_button.text = "OOC"
		ChatMode.LOOC:
			mode_button.text = "LOOC"
		ChatMode.ME:
			mode_button.text = "ME"

func _on_close_requested() -> void:
	hide()
	deselect()
	line_edit.text = ""

func _on_visibility_changed() -> void:
	if visible:
		select()
	else:
		deselect()
		line_edit.text = ""

func select() -> void:
	selected = true
	line_edit.editable = true
	send_button.disabled = false
	line_edit.grab_focus()

func deselect() -> void:
	selected = false
	line_edit.editable = false
	send_button.disabled = true
	line_edit.release_focus()
	_pending_send_lock = false

# Pre-round text chat (IC/LOOC) is suppressed until the round actually
# starts - OOC/ME still work in the lobby. Communications.gd sets
# `round_playing` on this node when it learns the round state changed
# (there's no GDScript-visible round-state signal to query directly here,
# see TickerSubsystem.StateChanged's header comment).
var round_playing: bool = false

func _is_lobby_phase() -> bool:
	return not round_playing

# Set directly by Communications.gd from its own local-mob reference
# (GameRoot.LocalPlayerSpawned) rather than searched for here - there's no
# reliable node-path/group heuristic left that matches the current mob
# naming ("Player_<peerId>") and class hierarchy (Mob, not CharacterBody2D).
func get_player_name() -> String:
	if mob and "AtomName" in mob and mob.AtomName != "":
		return mob.AtomName
	return "Unknown"

func show_input() -> void:
	popup_centered()
	show()
	call_deferred("_focus_line_edit")

func _focus_line_edit() -> void:
	if line_edit:
		line_edit.grab_focus()
