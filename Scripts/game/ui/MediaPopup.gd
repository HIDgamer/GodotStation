extends PopupPanel

signal media_selected(type: String, path: String)

@onready var file_dialog: FileDialog = $FileDialog
@onready var load_button: Button = $VBoxContainer/LoadButton
@onready var cancel_button: Button = $VBoxContainer/CancelButton

var media_type: String = ""

func _ready() -> void:
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM  # Changed from ACCESS_RESOURCES
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.file_selected.connect(_on_file_selected)
	load_button.pressed.connect(_on_load_pressed)
	cancel_button.pressed.connect(hide)

func open_for_type(type: String) -> void:
	media_type = type
	
	match type:
		"music":
			file_dialog.filters = ["*.ogg, *.mp3, *.wav ; Audio Files"]
		"video":
			file_dialog.filters = ["*.ogv, *.webm ; Video Files"]
		"art":
			file_dialog.filters = ["*.png, *.jpg, *.jpeg, *.bmp ; Image Files"]
	
	popup_centered()

func _on_load_pressed() -> void:
	file_dialog.popup_centered()

func _on_file_selected(path: String) -> void:
	media_selected.emit(media_type, path)
	hide()
