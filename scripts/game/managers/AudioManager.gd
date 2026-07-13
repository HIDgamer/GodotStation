@tool
extends Node

static var instance: AudioManager

# Audio buses for volume control.
const UI_BUS_INDEX: int = 1
const EFFECTS_BUS_INDEX: int = 2

# Sound effect resources.
@onready var ui_confirm: AudioStream = load("res://Sound/UI/SFX_UI_Confirm.ogg")
@onready var ui_cancel: AudioStream = load("res://Sound/UI/SFX_UI_Cancel.ogg")
@onready var ui_open_menu: AudioStream = load("res://Sound/UI/SFX_UI_OpenMenu.ogg")
@onready var ui_close_menu: AudioStream = load("res://Sound/UI/SFX_UI_CloseMenu.ogg")
@onready var ui_menu_selection: AudioStream = load("res://Sound/UI/SFX_UI_MenuSelections.ogg")
@onready var ui_equip: AudioStream = load("res://Sound/UI/SFX_UI_Equip.ogg")
@onready var ui_unequip: AudioStream = load("res://Sound/UI/SFX_UI_Unequip.ogg")
@onready var ui_saved: AudioStream = load("res://Sound/UI/SFX_UI_Saved.ogg")
@onready var ui_pause: AudioStream = load("res://Sound/UI/SFX_UI_Pause.ogg")
@onready var ui_resume: AudioStream = load("res://Sound/UI/SFX_UI_Resume.ogg")
@onready var ui_exit: AudioStream = load("res://Sound/UI/SFX_UI_Exit.ogg")
@onready var ui_shop: AudioStream = load("res://Sound/UI/SFX_UI_Shop.ogg")

# Hover sound (shorter, lighter sound).
@onready var ui_hover: AudioStream = load("res://Sound/UI/SFX_UI_Confirm.ogg")

# Audio players for different types of sounds.
@onready var ui_player: AudioStreamPlayer = get_node_or_null("UIPlayer")
@onready var hover_player: AudioStreamPlayer = get_node_or_null("HoverPlayer")
@onready var selection_player: AudioStreamPlayer = get_node_or_null("SelectionPlayer")

# Configuration.
var ui_volume_db: float = -10.0
var hover_volume_db: float = -20.0
var selection_volume_db: float = -15.0

# Cooldowns to prevent sound spam.
var last_hover_time: float = 0.0
var hover_cooldown: float = 0.1  # 100ms between hover sounds
var last_selection_time: float = 0.0
var selection_cooldown: float = 0.05  # 50ms between selection sounds

func _ready():
	# Initialize audio players.
	if not has_node("UIPlayer"):
		var ui_player_node = AudioStreamPlayer.new()
		ui_player_node.name = "UIPlayer"
		add_child(ui_player_node)
		ui_player = ui_player_node
	
	if not has_node("HoverPlayer"):
		var hover_player_node = AudioStreamPlayer.new()
		hover_player_node.name = "HoverPlayer"
		add_child(hover_player_node)
		hover_player = hover_player_node
	
	if not has_node("SelectionPlayer"):
		var selection_player_node = AudioStreamPlayer.new()
		selection_player_node.name = "SelectionPlayer"
		add_child(selection_player_node)
		selection_player = selection_player_node
	
	# Set up audio buses.
	ui_player.bus = "UI"
	hover_player.bus = "UI"
	selection_player.bus = "UI"
	
	# Set initial volumes.
	ui_player.volume_db = ui_volume_db
	hover_player.volume_db = hover_volume_db
	selection_player.volume_db = selection_volume_db

# Ui interaction sounds.
static func play_ui_click():
	if instance and instance.ui_player:
		instance.ui_player.stream = instance.ui_confirm
		instance.ui_player.play()

static func play_ui_cancel():
	if instance and instance.ui_player:
		instance.ui_player.stream = instance.ui_cancel
		instance.ui_player.play()

static func play_ui_open_menu():
	if instance and instance.ui_player:
		instance.ui_player.stream = instance.ui_open_menu
		instance.ui_player.play()

static func play_ui_close_menu():
	if instance and instance.ui_player:
		instance.ui_player.stream = instance.ui_close_menu
		instance.ui_player.play()

static func play_ui_menu_selection():
	if instance and instance.selection_player:
		var current_time = Time.get_unix_time_from_system()
		if current_time - instance.last_selection_time > instance.selection_cooldown:
			instance.selection_player.stream = instance.ui_menu_selection
			instance.selection_player.play()
			instance.last_selection_time = current_time

static func play_ui_hover():
	if instance and instance.hover_player:
		var current_time = Time.get_unix_time_from_system()
		if current_time - instance.last_hover_time > instance.hover_cooldown:
			instance.hover_player.stream = instance.ui_hover
			instance.hover_player.play()
			instance.last_hover_time = current_time

# Item management sounds.
static func play_ui_equip():
	if instance and instance.ui_player:
		instance.ui_player.stream = instance.ui_equip
		instance.ui_player.play()

static func play_ui_unequip():
	if instance and instance.ui_player:
		instance.ui_player.stream = instance.ui_unequip
		instance.ui_player.play()

static func play_ui_saved():
	if instance and instance.ui_player:
		instance.ui_player.stream = instance.ui_saved
		instance.ui_player.play()

static func play_chat_message():
	if instance and instance.ui_player:
		instance.ui_player.stream = instance.ui_confirm
		instance.ui_player.play()

# System Sounds.
static func play_ui_pause():
	if instance and instance.ui_player:
		instance.ui_player.stream = instance.ui_pause
		instance.ui_player.play()

static func play_ui_resume():
	if instance and instance.ui_player:
		instance.ui_player.stream = instance.ui_resume
		instance.ui_player.play()

static func play_ui_exit():
	if instance and instance.ui_player:
		instance.ui_player.stream = instance.ui_exit
		instance.ui_player.play()

static func play_ui_shop():
	if instance and instance.ui_player:
		instance.ui_player.stream = instance.ui_shop
		instance.ui_player.play()

# Volume control methods.
static func set_ui_volume(volume_db: float):
	if instance:
		instance.ui_volume_db = volume_db
		if instance.ui_player:
			instance.ui_player.volume_db = volume_db
		if instance.hover_player:
			instance.hover_player.volume_db = instance.hover_volume_db
		if instance.selection_player:
			instance.selection_player.volume_db = instance.selection_volume_db

static func get_ui_volume() -> float:
	if instance:
		return instance.ui_volume_db
	return -10.0

# Cleanup.
func _exit_tree():
	if instance == self:
		instance = null
