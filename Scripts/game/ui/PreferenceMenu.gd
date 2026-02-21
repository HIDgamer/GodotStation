extends Window

@onready var preference_manager: Node = $/root/PreferenceManager
@onready var sprite_system: Node2D = $PreviewBackground/CharacterBackground/SpriteSystem
@onready var audio_manager: Node = $/root/AudioManager

@onready var name_edit: LineEdit = $TabHuman/CharacterInfo/Name/Picker
@onready var randomize_name_check: CheckButton = $TabHuman/CharacterInfo/Name/RandName/RandomName
@onready var randomize_appearance_check: CheckButton = $TabHuman/CharacterInfo/Name/RandApperance/RandomApperance
@onready var age_spin: SpinBox = $TabHuman/CharacterInfo/Physical_Information/Age/Picker
@onready var gender_option: OptionButton = $TabHuman/CharacterInfo/Physical_Information/Gender/OptionButton
@onready var race_option: OptionButton = $TabHuman/CharacterInfo/Physical_Information/Race/OptionButton
@onready var religion_menu: MenuButton = $TabHuman/CharacterStyle/BackgroundInfo/Religion/MenuButton
@onready var origin_menu: MenuButton = $TabHuman/CharacterStyle/BackgroundInfo/Origin/MenuButton
@onready var relations_menu: MenuButton = $TabHuman/CharacterStyle/BackgroundInfo/Relations/MenuButton
@onready var pref_squad_menu: MenuButton = $TabHuman/CharacterStyle/BackgroundInfo/PrefSquad/MenuButton
@onready var role_button: Button = $TabHuman/CharacterInfo/Occupation_Choices/Role
@onready var assign_role_button: Button = $TabHuman/CharacterInfo/Occupation_Choices/AssignRole
@onready var hair_button: Button = $TabHuman/CharacterStyle/HairEyesContainer/Picker
@onready var hair_base_color_button: ColorPickerButton = $TabHuman/CharacterStyle/HairEyesContainer/Picker2
@onready var eye_color_button: ColorPickerButton = $TabHuman/CharacterStyle/HairEyesContainer/EyeColor
@onready var facial_hair_button: Button = $TabHuman/CharacterStyle/HairEyesContainer/FacialHairPicker
@onready var underwear_button: Button = $TabHuman/CharacterStyle/Gear/Underwear
@onready var undershirt_button: Button = $TabHuman/CharacterStyle/Gear/UnderShirt
@onready var cycle_bg_button: Button = $TabHuman/CharacterStyle/Gear/CycleBackground
@onready var character_background: TextureRect = $PreviewBackground/CharacterBackground
@onready var left_rotate_button: Button = $PreviewBackground/HBoxContainer/Left
@onready var right_rotate_button: Button = $PreviewBackground/HBoxContainer/Right
@onready var save_slot_button: Button = $VBoxContainer/Slot/Save
@onready var load_slot_button: Button = $VBoxContainer/Slot/Load
@onready var reload_slot_button: Button = $VBoxContainer/Slot/Reload
@onready var role_pref_popup: PopupPanel = load("uid://cfdlfe58u2v0g").instantiate()
@onready var slot_popup: PopupPanel = load("uid://1ab6tkrbm5u").instantiate()
@onready var item_popup: PopupPanel = load("uid://c0hf2y7li5hu4").instantiate()

var backgrounds: Array = []
var current_bg: int = 0

func _ready() -> void:
	load_backgrounds()
	add_child(role_pref_popup)
	add_child(slot_popup)
	add_child(item_popup)
	populate_races()
	load_character_data()

	if sprite_system == null:
		push_error("PreferenceMenu: sprite_system is null! Path: $PreviewBackground/CharacterBackground/SpriteSystem")
		sprite_system = find_child("SpriteSystem", true, false)
		if sprite_system != null:
			print("PreferenceMenu: Found sprite_system via find_child")
		else:
			print("PreferenceMenu: Could not find sprite_system")
	else:
		print("PreferenceMenu: sprite_system found at initialization")

	close_requested.connect(_on_close_requested)
	name_edit.text_changed.connect(_on_name_changed)
	randomize_name_check.toggled.connect(_on_randomize_name_toggled)
	randomize_appearance_check.toggled.connect(_on_randomize_appearance_toggled)
	age_spin.value_changed.connect(_on_age_changed)
	gender_option.item_selected.connect(_on_gender_selected)
	race_option.item_selected.connect(_on_race_selected)
	religion_menu.get_popup().id_pressed.connect(_on_religion_selected)
	origin_menu.get_popup().id_pressed.connect(_on_origin_selected)
	relations_menu.get_popup().id_pressed.connect(_on_relations_selected)
	pref_squad_menu.get_popup().id_pressed.connect(_on_pref_squad_selected)
	role_button.pressed.connect(_on_role_button_pressed)
	assign_role_button.pressed.connect(_on_assign_role_button_pressed)
	if hair_button:
		hair_button.pressed.connect(_on_hair_button_pressed)
	if hair_base_color_button:
		hair_base_color_button.color_changed.connect(_on_hair_base_color_changed)
	if eye_color_button:
		eye_color_button.color_changed.connect(_on_eye_color_changed)
	if facial_hair_button:
		facial_hair_button.pressed.connect(_on_facial_hair_button_pressed)
	if underwear_button:
		underwear_button.pressed.connect(_on_underwear_button_pressed)
	if undershirt_button:
		undershirt_button.pressed.connect(_on_undershirt_button_pressed)
	left_rotate_button.pressed.connect(_on_left_rotate_pressed)
	right_rotate_button.pressed.connect(_on_right_rotate_pressed)
	cycle_bg_button.pressed.connect(_on_cycle_bg_pressed)
	save_slot_button.pressed.connect(_on_save_slot_pressed)
	load_slot_button.pressed.connect(_on_load_slot_pressed)
	reload_slot_button.pressed.connect(_on_reload_slot_pressed)
	
	# Add hover sounds to buttons.
	add_hover_sounds()

func add_hover_sounds() -> void:
	if audio_manager:
		if role_button:
			role_button.mouse_entered.connect(_on_button_hover)
		if assign_role_button:
			assign_role_button.mouse_entered.connect(_on_button_hover)
		if hair_button:
			hair_button.mouse_entered.connect(_on_button_hover)
		if facial_hair_button:
			facial_hair_button.mouse_entered.connect(_on_button_hover)
		if underwear_button:
			underwear_button.mouse_entered.connect(_on_button_hover)
		if undershirt_button:
			undershirt_button.mouse_entered.connect(_on_button_hover)
		if left_rotate_button:
			left_rotate_button.mouse_entered.connect(_on_button_hover)
		if right_rotate_button:
			right_rotate_button.mouse_entered.connect(_on_button_hover)
		if cycle_bg_button:
			cycle_bg_button.mouse_entered.connect(_on_button_hover)
		if save_slot_button:
			save_slot_button.mouse_entered.connect(_on_button_hover)
		if load_slot_button:
			load_slot_button.mouse_entered.connect(_on_button_hover)
		if reload_slot_button:
			reload_slot_button.mouse_entered.connect(_on_button_hover)

func populate_races() -> void:
	race_option.clear()
	var dir: DirAccess = DirAccess.open("res://Assets/Human/Race/")
	if dir:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			if dir.current_is_dir() and not file_name.begins_with("."):
				race_option.add_item(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()

func load_character_data() -> void:
	var data: Dictionary = preference_manager.get_character_data()
	name_edit.text = data.get("name", "")
	randomize_name_check.button_pressed = data.get("randomize_name", false)
	randomize_appearance_check.button_pressed = data.get("randomize_appearance", false)
	age_spin.value = data.get("age", 18)
	var gender: String = data.get("gender", "Male")
	gender_option.selected = 0 if gender == "Female" else 1
	var race: String = data.get("race", "Western")
	
	var race_found = false
	for i in range(race_option.get_item_count()):
		if race_option.get_item_text(i) == race:
			race_option.selected = i
			race_found = true
			break
	
	if not race_found and race_option.get_item_count() > 0:
		race = race_option.get_item_text(0)
		preference_manager.update_character_field("race", race)
		race_option.selected = 0
		print("Warning: Race '", data.get("race", "Unknown"), "' not found, using: ", race)
	
	religion_menu.text = data.get("religion", "")
	origin_menu.text = data.get("origin", "")
	relations_menu.text = data.get("relations", "")
	pref_squad_menu.text = data.get("pref_squad", "")
	if hair_button:
		var hair_style = data.get("hair_style", "")
		hair_button.text = hair_style if hair_style != "" else "None"
	if facial_hair_button:
		var facial_style = data.get("facial_hair_style", "")
		facial_hair_button.text = facial_style if facial_style != "" else "None"
	if underwear_button:
		var underwear_style = data.get("underwear_style", "")
		if underwear_style == "":
			underwear_style = "1"
			preference_manager.update_character_field("underwear_style", underwear_style)
		underwear_button.text = underwear_style
	if undershirt_button:
		var undershirt_style = data.get("undershirt_style", "")
		if undershirt_style == "" and gender == "Female":
			undershirt_style = "1"
			preference_manager.update_character_field("undershirt_style", undershirt_style)
		undershirt_button.text = undershirt_style if undershirt_style != "" else "None"
	if hair_base_color_button:
		hair_base_color_button.color = Color(data.get("hair_base_color", "#000000"))
	if eye_color_button:
		eye_color_button.color = Color(data.get("eye_color", "#0000FF"))
	_update_color_labels()

	update_sprite_preview()

func update_sprite_preview() -> void:
	var data: Dictionary = preference_manager.get_character_data()
	var gender: String = data.get("gender", "Male")
	var race: String = data.get("race", "Western")

	if sprite_system:
		sprite_system.call("SetGender", gender)
		sprite_system.call("SetEthnicity", race)
		sprite_system.call("SetEyeColor", data.get("eye_color", "#000000"))
		sprite_system.call("SetHairBaseColor", data.get("hair_base_color", "#000000"))
		sprite_system.call("ReloadAppearance")

	update_button_states(gender)

	print("PreferenceMenu: Updated sprite preview - Gender: ", gender, ", Race: ", race)

func update_button_states(gender: String) -> void:
	if underwear_button:
		underwear_button.disabled = false
	if hair_button:
		hair_button.disabled = false
	if facial_hair_button:
		facial_hair_button.disabled = (gender == "Female")
	if undershirt_button:
		undershirt_button.disabled = false

func _on_name_changed(new_text: String) -> void:
	preference_manager.update_character_field("name", new_text)

func _on_randomize_name_toggled(toggled_on: bool) -> void:
	preference_manager.update_character_field("randomize_name", toggled_on)

func _on_randomize_appearance_toggled(toggled_on: bool) -> void:
	preference_manager.update_character_field("randomize_appearance", toggled_on)

func _on_age_changed(value: float) -> void:
	preference_manager.update_character_field("age", int(value))

func _on_gender_selected(index: int) -> void:
	var gender: String = "Female" if index == 0 else "Male"
	preference_manager.update_character_field("gender", gender)
	if gender == "Female":
		preference_manager.update_character_field("facial_hair_style", "")
	update_sprite_preview()

func _on_race_selected(index: int) -> void:
	var race: String = race_option.get_item_text(index)
	preference_manager.update_character_field("race", race)
	print("PreferenceMenu: Race changed to: ", race)
	update_sprite_preview()

func _on_religion_selected(id: int) -> void:
	var text: String = religion_menu.get_popup().get_item_text(id)
	religion_menu.text = text
	preference_manager.update_character_field("religion", text)

func _on_origin_selected(id: int) -> void:
	var text: String = origin_menu.get_popup().get_item_text(id)
	origin_menu.text = text
	preference_manager.update_character_field("origin", text)

func _on_relations_selected(id: int) -> void:
	var text: String = relations_menu.get_popup().get_item_text(id)
	relations_menu.text = text
	preference_manager.update_character_field("relations", text)

func _on_pref_squad_selected(id: int) -> void:
	var text: String = pref_squad_menu.get_popup().get_item_text(id)
	pref_squad_menu.text = text
	preference_manager.update_character_field("pref_squad", text)

func _on_role_button_pressed() -> void:
	if audio_manager:
		audio_manager.play_ui_click()
	role_pref_popup.popup_centered()

func _on_assign_role_button_pressed() -> void:
	if audio_manager:
		audio_manager.play_ui_click()
	preference_manager.assign_character_to_role("Assistant")
	print("Assigned current character to Assistant")

func _on_hair_button_pressed() -> void:
	print("PreferenceMenu._on_hair_button_pressed called")
	if audio_manager:
		audio_manager.play_ui_click()
	item_popup.set_type("hair", hair_button)
	item_popup.populate_items()
	item_popup.popup_centered()

func _on_facial_hair_button_pressed() -> void:
	if audio_manager:
		audio_manager.play_ui_click()
	item_popup.set_type("facial_hair", facial_hair_button)
	item_popup.populate_items()
	item_popup.popup_centered()

func _on_underwear_button_pressed() -> void:
	if audio_manager:
		audio_manager.play_ui_click()
	item_popup.set_type("underwear", underwear_button)
	item_popup.populate_items()
	item_popup.popup_centered()

func _on_undershirt_button_pressed() -> void:
	if audio_manager:
		audio_manager.play_ui_click()
	item_popup.set_type("undershirt", undershirt_button)
	item_popup.populate_items()
	item_popup.popup_centered()

func _on_left_rotate_pressed() -> void:
	if audio_manager:
		audio_manager.play_ui_menu_selection()
	var current_dir: int = sprite_system.GetDirection()
	var new_dir: int = (current_dir - 1 + 4) % 4
	sprite_system.call("SetDirection", new_dir)

func _on_right_rotate_pressed() -> void:
	if audio_manager:
		audio_manager.play_ui_menu_selection()
	var current_dir: int = sprite_system.GetDirection()
	var new_dir: int = (current_dir + 1) % 4
	sprite_system.call("SetDirection", new_dir)

func _on_save_slot_pressed() -> void:
	if audio_manager:
		audio_manager.play_ui_click()
	slot_popup.set_action_mode("save")
	slot_popup.populate_slots()
	slot_popup.popup_centered()

func _on_load_slot_pressed() -> void:
	if audio_manager:
		audio_manager.play_ui_click()
	slot_popup.set_action_mode("load")
	slot_popup.populate_slots()
	slot_popup.popup_centered()

func _on_reload_slot_pressed() -> void:
	load_character_data()
	if audio_manager:
		audio_manager.play_ui_saved()

func load_backgrounds() -> void:
	backgrounds = []
	var dir: DirAccess = DirAccess.open("res://Assets/Background/PreferenceMenu/")
	if dir:
		dir.list_dir_begin()
		var file: String = dir.get_next()
		while file:
			if not dir.current_is_dir() and file.ends_with(".png"):
				backgrounds.append("res://Assets/Background/PreferenceMenu/" + file)
			file = dir.get_next()
		dir.list_dir_end()
	if backgrounds.size() > 0:
		character_background.texture = load(backgrounds[0])

func _on_cycle_bg_pressed() -> void:
	if backgrounds.size() > 0:
		current_bg = (current_bg + 1) % backgrounds.size()
		character_background.texture = load(backgrounds[current_bg])
	if audio_manager:
		audio_manager.play_ui_menu_selection()

func _on_hair_base_color_changed(color: Color) -> void:
	preference_manager.update_character_field("hair_base_color", color.to_html())
	_update_color_labels()
	update_sprite_preview()

func _on_hair_gradient_color_changed(color: Color) -> void:
	preference_manager.update_character_field("hair_gradient_color", color.to_html())
	update_sprite_preview()

func _on_eye_color_changed(color: Color) -> void:
	preference_manager.update_character_field("eye_color", color.to_html())
	_update_color_labels()
	update_sprite_preview()

func _update_color_labels() -> void:
	if hair_base_color_button:
		hair_base_color_button.text = "Hair Color: " + hair_base_color_button.color.to_html(false).to_upper()
	if eye_color_button:
		eye_color_button.text = "Eye Color: " + eye_color_button.color.to_html(false).to_upper()

func _on_close_requested() -> void:
	if audio_manager:
		audio_manager.play_ui_close_menu()
	hide()

func _on_button_hover() -> void:
	if audio_manager:
		audio_manager.play_ui_hover()
