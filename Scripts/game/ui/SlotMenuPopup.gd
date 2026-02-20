# SlotMenuPopup - Handles save/load slot selection.
extends PopupPanel

@onready var preference_manager: Node = $/root/PreferenceManager
@onready var container: VBoxContainer = $VBoxContainer/ScrollContainer/VBoxContainer2

var action_mode: String = "load"  # "save" or "load"

func _ready() -> void:
	populate_slots()

func set_action_mode(new_mode: String) -> void:
	action_mode = new_mode
	$VBoxContainer/Label.text = "Select Slot to " + action_mode.capitalize()

func populate_slots() -> void:
	if not container:
		return
	for child in container.get_children():
		child.queue_free()
	
	var game_manager = get_node_or_null("/root/GameManager")
	if not game_manager:
		return
	
	var names: Array = game_manager.call("GetSlotNames")
	for i in range(names.size()):
		var btn: Button = Button.new()
		btn.text = names[i]
		btn.connect("pressed", Callable(self, "_on_slot_selected").bind(i))
		container.add_child(btn)

func _on_slot_selected(slot: int) -> void:
	if action_mode == "save":
		preference_manager.save_to_slot(slot)
		populate_slots()  # Refresh names if saved
	elif action_mode == "load":
		preference_manager.load_from_slot(slot)
		# Emit signal or notify menu to reload ui.
		get_parent().load_character_data()
	hide()

func _on_close_pressed() -> void:
	hide()
