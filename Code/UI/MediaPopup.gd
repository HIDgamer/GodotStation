extends PopupPanel

# MediaPopup - File dialog for selecting media (music, video, art) to display in lobby.

signal media_selected(type: String, path: String)

@onready var file_dialog: FileDialog = $FileDialog
@onready var load_button: Button = $VBoxContainer/LoadButton
@onready var cancel_button: Button = $VBoxContainer/CancelButton

var media_type: String = ""

func _ready() -> void:
	file_dialog.file_selected.connect(_on_file_selected)
	load_button.pressed.connect(_on_load_pressed)
	cancel_button.pressed.connect(hide)

func open_for_type(type: String) -> void:
	media_type = type
	popup_centered()

func _on_load_pressed() -> void:
	file_dialog.popup_centered()

func _on_file_selected(path: String) -> void:
	# Emit the full file path for external media
	media_selected.emit(media_type, path)
	hide()
