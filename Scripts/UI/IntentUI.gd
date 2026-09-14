extends Control

# Intent button row - a sibling of PlayerInterface.gd under PUI, wired
# independently since it owns its own buttons. Connection rebuild: routes
# clicks through PlayerMob.HudRequestSetIntent instead of the dead
# IntentSystem node, and mirrors the highlight from the authoritative
# HudIntentChanged signal instead of assuming the click succeeded. No more
# local _input keyboard handling - PlayerMob already reads
# intent_help/disarm/grab/harm itself (ReadLocalInput), so handling them
# here too would just be a redundant second path to the same result.

const HUD_SHEET := "res://Icons/mob/hud/screen1.png"

var current_intent: int = 0
var intent_buttons: Array = []
var active_tween: Tween = null
var player: Node = null

func _ready() -> void:
	player = get_parent().get_parent().get_parent()
	if not player or player.OwnerPeerId != multiplayer.get_unique_id():
		return

	intent_buttons = [
		get_node_or_null("../RightBar/LowerRow/IntentContainer/Help"),
		get_node_or_null("../RightBar/LowerRow/IntentContainer/Disarm"),
		get_node_or_null("../RightBar/LowerRow/IntentContainer/Grab"),
		get_node_or_null("../RightBar/LowerRow/IntentContainer/Harm"),
	]

	# Real ucfss13 icon states from screen1.png (confirmed against its
	# .icon.json, 2026-09-14) - these buttons had layout but no texture at
	# all, same gap as PlayerInterface.gd's hand/limb chrome.
	var intent_states = ["intent_help", "intent_disarm", "intent_grab", "intent_hurt"]
	for i in range(intent_buttons.size()):
		if intent_buttons[i]:
			intent_buttons[i].texture_normal = IconBridge.GetFrame(HUD_SHEET, intent_states[i])
			intent_buttons[i].pressed.connect(_on_intent_pressed.bind(i))

	player.HudIntentChanged.connect(_on_hud_intent_changed)
	update_intent_highlight()

func _on_intent_pressed(intent_index: int) -> void:
	if player:
		player.HudRequestSetIntent(intent_index)

func _on_hud_intent_changed(intent: int) -> void:
	current_intent = intent
	update_intent_highlight()

func update_intent_highlight() -> void:
	if active_tween:
		active_tween.kill()

	for i in range(intent_buttons.size()):
		if not intent_buttons[i]:
			continue
		if i == current_intent:
			active_tween = create_tween()
			active_tween.tween_property(intent_buttons[i], "modulate", Color(1.5, 1.5, 1.5), 0.1)
			active_tween.tween_property(intent_buttons[i], "modulate", Color(1, 1, 1), 0.2)
		else:
			intent_buttons[i].modulate = Color(0.7, 0.7, 0.7)
