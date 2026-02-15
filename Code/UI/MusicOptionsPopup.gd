extends PopupPanel

signal options_selected(loops: int, volume: float)

@onready var loop_spin: SpinBox = $VBoxContainer/LoopSpin
@onready var volume_slider: HSlider = $VBoxContainer/VolumeSlider
@onready var ok_button: Button = $VBoxContainer/OKButton

func _ready() -> void:
	loop_spin.value = 1
	ok_button.pressed.connect(_on_ok_pressed)

func _on_ok_pressed() -> void:
	var loops: int = int(loop_spin.value)
	var volume: float = volume_slider.value / 100.0
	options_selected.emit(loops, volume)
	hide()
