# TextInput - Chat input window for sending messages during gameplay.
extends Window

signal message_sent(text: String, mode: String)

@onready var line_edit: LineEdit = $Container/HBoxContainer/LineEdit
@onready var send_button: Button = $Container/HBoxContainer/SendButton
@onready var mode_button: Button = $Container/HBoxContainer/ModeButton

enum ChatMode { IC, OOC, LOOC, ME }
var current_mode: ChatMode = ChatMode.IC
var selected: bool = false
var mob: Node = null

func _ready() -> void:
	add_to_group("TextInput")
	send_button.connect("pressed", Callable(self, "_on_send"))
	line_edit.connect("text_submitted", Callable(self, "_on_send"))
	mode_button.connect("pressed", Callable(self, "_on_mode_button_pressed"))
	connect("close_requested", Callable(self, "_on_close_requested"))
	connect("visibility_changed", Callable(self, "_on_visibility_changed"))
	_update_mode_button()
	deselect()

func _on_send(new_text: String = "") -> void:
	var text: String = new_text if new_text != "" else line_edit.text.strip_edges()
	if text == "" or text.length() > 200:
		line_edit.text = ""
		return
	
	var mode_str: String = _get_mode_string()
	message_sent.emit(text, mode_str)
	line_edit.text = ""
	hide()

func _get_mode_string() -> String:
	match current_mode:
		ChatMode.OOC: return "OOC"
		ChatMode.LOOC: return "LOOC"
		ChatMode.ME: return "ME"
		_: return "IC"

func _on_mode_button_pressed() -> void:
	current_mode = (current_mode + 1) % 4
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
	_find_and_disable_player_movement()
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		gm.call("SetChatInputActive", true)

func deselect() -> void:
	selected = false
	line_edit.editable = false
	send_button.disabled = true
	line_edit.release_focus()
	_restore_player_movement()
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		gm.call("SetChatInputActive", false)

func _find_and_disable_player_movement() -> void:
	if mob == null:
		mob = _get_player_node()

	if mob and mob.is_multiplayer_authority() and "DisableMovement" in mob:
		mob.DisableMovement = true

func _restore_player_movement() -> void:
	if mob and "DisableMovement" in mob:
		mob.DisableMovement = false

func _get_player_node() -> Node:
	# Try multiple approaches to find the player node
	var player_id = str(multiplayer.get_unique_id())

	var world = get_tree().get_first_node_in_group("World")
	if world:
		var world_player = world.get_node_or_null(player_id)
		if world_player:
			return world_player
	
	# Method 1: Check direct children of the current scene
	var current_scene = get_tree().current_scene
	if current_scene:
		for child in current_scene.get_children():
			if child is CharacterBody2D and child.name == player_id:
				return child
			elif child is Node2D and child.name == "DDome":
				for grandchild in child.get_children():
					if grandchild is CharacterBody2D and grandchild.name == player_id:
						return grandchild
	
	# Method 2: Check subviewport
	var subviewport = get_node_or_null("../HSplitContainer/SubViewportContainer/SubViewport")
	if subviewport:
		for child in subviewport.get_children():
			if child is CharacterBody2D and child.name == player_id:
				return child
			elif child is Node2D and child.name == "DDome":
				for grandchild in child.get_children():
					if grandchild is CharacterBody2D and grandchild.name == player_id:
						return grandchild
	
	# Method 3: Check all mobs in the scene
	var mobs = get_tree().get_nodes_in_group("Mob")
	for mob in mobs:
		if mob.name == player_id:
			return mob
	
	return null

func get_player_name() -> String:
	var player_node = _get_player_node()
	if player_node:
		return player_node.GetPlayerName()
	
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		var peer_data = game_manager.get_peer_character_data(multiplayer.get_unique_id())
		if peer_data and peer_data.has("name"):
			return peer_data["name"]
	
	var pref_manager = get_node_or_null("/root/PreferenceManager")
	if pref_manager:
		var char_data = pref_manager.get_character_data()
		if char_data and char_data.has("name"):
			return char_data["name"]
	
	return "Player " + str(multiplayer.get_unique_id())

func show_input() -> void:
	popup_centered()
