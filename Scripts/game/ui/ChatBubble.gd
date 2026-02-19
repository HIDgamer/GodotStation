extends Node2D

@onready var label: Label = $Label
var current_tween: Tween = null
var chat_mode: String = "IC"

func _ready() -> void:
	label.text = ""
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(120, 0)
	label.size = Vector2(120, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	
	if label.get("theme_override_font_sizes/font_size"):
		label.set("theme_override_font_sizes/font_size", 10)
	
	var font = label.get_theme_font("font")
	if font:
		font.antialiasing = TextServer.FONT_ANTIALIASING_LCD
	
	modulate.a = 0.0
	scale = Vector2(0.8, 0.8)

func _exit_tree() -> void:
	if current_tween != null:
		current_tween.kill()

func set_message(message: String, mode: String = "IC") -> void:
	chat_mode = mode

	if message.begins_with("hugs ") or message.begins_with("pats ") or message.begins_with("shoves ") or \
	   message.begins_with("tries to shove ") or message.begins_with("punches ") or message.begins_with("misses ") or \
	   message.begins_with("grabs ") or message.begins_with("aggressively grabs ") or message.begins_with("starts choking ") or \
	   message.begins_with("lifts ") or message.begins_with("lost grip on ") or message.begins_with("Too far away") or \
	   message.begins_with("Already grabbing them") or message.begins_with("Already grabbing someone else") or \
	   message.begins_with("Already being pulled") or message.begins_with("Hand is occupied") or \
	   message.begins_with("Too far for fireman carry") or message.begins_with("Stopped carrying") or \
	   message.begins_with("swapped places with") or message.begins_with("pushed") or message.begins_with("pulled"):
		queue_free()
		return
	
	match mode:
		"LOOC":
			label.text = message
			label.add_theme_color_override("font_color", Color(1.0, 0.71, 0.76))
		"ME":
			label.text = "*" + message
			label.add_theme_color_override("font_color", Color.WHITE)
		_:
			label.text = message
			label.add_theme_color_override("font_color", Color.WHITE)
	
	adjust_position()
	animate_in()

func update_message(message: String, mode: String = "IC") -> void:
	if current_tween != null:
		current_tween.kill()
	set_message(message, mode)

func adjust_position() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	position = Vector2(0, -15)

func animate_in() -> void:
	if current_tween != null:
		current_tween.kill()
	modulate.a = 0.0
	current_tween = create_tween()
	current_tween.tween_property(self, "modulate:a", 1.0, 0.5)
	current_tween.tween_interval(5.0)
	current_tween.tween_callback(animate_out)

func animate_out() -> void:
	if current_tween != null:
		current_tween.kill()
	current_tween = create_tween()
	current_tween.tween_property(self, "modulate:a", 0.0, 0.5)
	current_tween.tween_callback(queue_free)
