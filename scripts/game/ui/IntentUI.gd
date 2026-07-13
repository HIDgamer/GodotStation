extends Control

var current_intent = 0
var intent_buttons = []
var active_tween = null

func _ready():
	intent_buttons = [
		get_node_or_null("../HBoxContainer/IntentContainer/Help"),
		get_node_or_null("../HBoxContainer/IntentContainer/Disarm"),
		get_node_or_null("../HBoxContainer/IntentContainer/Grab"),
		get_node_or_null("../HBoxContainer/IntentContainer/Harm")
	]
	
	for i in range(intent_buttons.size()):
		if intent_buttons[i]:
			intent_buttons[i].pressed.connect(_on_intent_pressed.bind(i))
	
	update_intent_highlight()

func _on_intent_pressed(intent_index):
	current_intent = intent_index
	update_intent_highlight()
	
	var player = get_tree().get_first_node_in_group("Player")
	if player:
		var intent_system = player.get_node_or_null("IntentSystem")
		if intent_system:
			intent_system.SetIntent(intent_index)

func update_intent_highlight():
	if active_tween:
		active_tween.kill()
	
	for i in range(intent_buttons.size()):
		if intent_buttons[i]:
			if i == current_intent:
				active_tween = create_tween()
				active_tween.tween_property(intent_buttons[i], "modulate", Color(1.5, 1.5, 1.5), 0.1)
				active_tween.tween_property(intent_buttons[i], "modulate", Color(1, 1, 1), 0.2)
			else:
				intent_buttons[i].modulate = Color(0.7, 0.7, 0.7)

func _input(event):
	if event.is_action_pressed("intent_help"):
		_on_intent_pressed(0)
	elif event.is_action_pressed("intent_disarm"):
		_on_intent_pressed(1)
	elif event.is_action_pressed("intent_grab"):
		_on_intent_pressed(2)
	elif event.is_action_pressed("intent_harm"):
		_on_intent_pressed(3)
