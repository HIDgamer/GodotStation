extends Node
class_name UIAnimationHelper

const BUTTON_HOVER_DURATION: float = 0.2
const BUTTON_PRESS_DURATION: float = 0.1
const PANEL_SLIDE_DURATION: float = 0.4
const FADE_DURATION: float = 0.3

static func animate_button_hover(button: Control, is_hovering: bool) -> void:
	var tween = button.create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	
	if is_hovering:
		tween.tween_property(button, "scale", Vector2(1.05, 1.05), BUTTON_HOVER_DURATION)
	else:
		tween.tween_property(button, "scale", Vector2(1.0, 1.0), BUTTON_HOVER_DURATION)

static func animate_button_press(button: Control) -> void:
	var tween = button.create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2(0.95, 0.95), BUTTON_PRESS_DURATION)
	tween.tween_property(button, "scale", Vector2(1.0, 1.0), BUTTON_PRESS_DURATION)

static func animate_panel_slide_in(panel: Control, from_position: Vector2, to_position: Vector2) -> void:
	panel.position = from_position
	var tween = panel.create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "position", to_position, PANEL_SLIDE_DURATION)

static func animate_panel_fade(panel: Control, fade_in: bool) -> void:
	var tween = panel.create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	
	if fade_in:
		panel.modulate.a = 0.0
		tween.tween_property(panel, "modulate:a", 1.0, FADE_DURATION)
	else:
		tween.tween_property(panel, "modulate:a", 0.0, FADE_DURATION)

static func animate_option_button_pulse(button: OptionButton) -> void:
	var tween = button.create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(button, "scale", Vector2(1.02, 1.02), 0.15)
	tween.tween_property(button, "scale", Vector2(1.0, 1.0), 0.15)

static func animate_spin_box_change(spinbox: SpinBox) -> void:
	var tween = spinbox.create_tween()
	tween.set_trans(Tween.TRANS_BOUNCE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(spinbox, "scale", Vector2(1.08, 1.08), 0.2)
	tween.tween_property(spinbox, "scale", Vector2(1.0, 1.0), 0.15)

static func animate_label_glow(label: Label, duration: float = 0.8) -> void:
	var tween = label.create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(label, "modulate:a", 0.6, duration / 2)
	tween.tween_property(label, "modulate:a", 1.0, duration / 2)

static func setup_button_animations(button: BaseButton) -> void:
	button.mouse_entered.connect(func(): UIAnimationHelper.animate_button_hover(button, true))
	button.mouse_exited.connect(func(): UIAnimationHelper.animate_button_hover(button, false))
	button.pressed.connect(func(): UIAnimationHelper.animate_button_press(button))
