# RolePreferencesPopup - Manages role priority selection.
extends PopupPanel

@onready var preference_manager: Node = $/root/PreferenceManager
@onready var container: VBoxContainer = $VBoxContainer/ScrollContainer/VBoxContainer2

func _ready() -> void:
	populate_roles()

func populate_roles() -> void:
	if not container:
		return
	for child in container.get_children():
		child.queue_free()
	
	var categories: Dictionary = preference_manager.available_roles
	for category in categories:
		var cat_label: Label = Label.new()
		cat_label.text = category
		container.add_child(cat_label)
		
		for role in categories[category]:
			var hbox: HBoxContainer = HBoxContainer.new()
			var role_label: Label = Label.new()
			role_label.text = role
			role_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hbox.add_child(role_label)
			
			var low_btn: Button = Button.new()
			low_btn.text = "Low"
			low_btn.connect("pressed", Callable(self, "_on_priority_pressed").bind(role, "Low"))
			hbox.add_child(low_btn)
			
			var med_btn: Button = Button.new()
			med_btn.text = "Med"
			med_btn.connect("pressed", Callable(self, "_on_priority_pressed").bind(role, "Medium"))
			hbox.add_child(med_btn)
			
			var high_btn: Button = Button.new()
			high_btn.text = "High"
			high_btn.connect("pressed", Callable(self, "_on_priority_pressed").bind(role, "High"))
			hbox.add_child(high_btn)
			
			container.add_child(hbox)
	
	update_buttons()

func update_buttons() -> void:
	if not container:
		return
	var priorities: Dictionary = preference_manager.get_role_priorities()
	for child in container.get_children():
		if child is HBoxContainer:
			var role: String = child.get_child(0).text
			var priority: String = priorities.get(role, "")
			for i in range(1, 4):
				var btn: Button = child.get_child(i)
				if btn.text.to_lower() == priority.to_lower():
					btn.modulate = Color.GREEN
				else:
					btn.modulate = Color.WHITE

func _on_priority_pressed(role: String, priority: String) -> void:
	var current = preference_manager.get_role_priorities().get(role, "")
	if current == priority:
		preference_manager.remove_role_priority(role)
	else:
		if preference_manager.set_role_priority(role, priority):
			pass
		else:
			print("Cannot set priority: duplicate level or max reached")
	update_buttons()

func _on_close_pressed() -> void:
	hide()
