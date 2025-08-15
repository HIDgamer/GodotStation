extends Control

@onready var asset_manager = get_node("/root/CharacterAssetManager")

var sprite_system_script_paths = ["res://Code/Mobs/Systems/human_sprite_system.gd"]
var sprite_system_scene_paths = ["res://Scenes/Sprites/human_sprite_system.tscn"]

@export var character_data = {
	"name": "Commander Alpha",
	"age": 30,
	"race": 0,
	"sex": 0,
	"hair_style": 0,
	"hair_color": Color(0.337255, 0.211765, 0.117647),
	"facial_hair": 0,
	"facial_hair_color": Color(0.337255, 0.211765, 0.117647),
	"occupation": 0,
	"clothing": 0,
	"underwear": 0,
	"undershirt": 0,
	"background_text": "",
	"medical_text": "",
	"preview_background": 0,
	"loadout_enabled": true,
	"custom_loadout": {}
}

var default_character_data = {}
var preview_sprites = {}
var available_hair_styles = []
var available_facial_hair = []
var available_clothing = []
var available_underwear = []
var available_undershirts = []
var preview_loadout_items = {}

enum Direction {SOUTH, NORTH, EAST, WEST}
var preview_direction = Direction.SOUTH
var direction_names = ["FRONT VIEW", "REAR VIEW", "RIGHT PROFILE", "LEFT PROFILE"]

var is_updating_preview = false
var presets_data = {}
var active_preset_name = ""

var current_tab = 0
var tab_names = ["Basic Info", "Appearance", "Assignment", "Equipment"]

const PRESETS_FILE_PATH = "user://character_presets.json"
const SETTINGS_FILE_PATH = "user://character_creation_settings.json"

var tween: Tween
var is_multiplayer_mode: bool = false
var local_peer_id: int = 1
var is_host: bool = false

@onready var back_button = $HeaderBar/HeaderContainer/LeftHeader/BackButton
@onready var notification_label = %NotificationLabel
@onready var active_preset_label = %ActivePresetLabel
@onready var preset_dropdown = %PresetDropdown
@onready var preset_name_input = %PresetNameInput
@onready var save_preset_button = %SavePresetButton
@onready var delete_preset_button = %DeletePresetButton

@onready var tab_container = %TabContainer
@onready var tab_buttons = %TabButtons

@onready var name_input = %NameInput
@onready var age_spinbox = %AgeSpinBox
@onready var race_option = %RaceOption
@onready var sex_option = %SexOption

@onready var prev_hair = %PrevHair
@onready var hair_label = %HairLabel
@onready var next_hair = %NextHair
@onready var hair_color_picker = %HairColorPicker
@onready var prev_facial_hair = %PrevFacialHair
@onready var facial_hair_label = %FacialHairLabel
@onready var next_facial_hair = %NextFacialHair
@onready var facial_hair_color_picker = %FacialHairColorPicker

@onready var occupation_option = %OccupationOption
@onready var occupation_search = %OccupationSearch
@onready var occupation_list = %OccupationList
@onready var occupation_description = %OccupationDescription
@onready var loadout_enabled_check = %LoadoutEnabledCheck

@onready var prev_underwear = %PrevUnderwear
@onready var underwear_label = %UnderwearLabel
@onready var next_underwear = %NextUnderwear
@onready var prev_undershirt = %PrevUndershirt
@onready var undershirt_label = %UndershirtLabel
@onready var next_undershirt = %NextUndershirt
@onready var prev_clothing = %PrevClothing
@onready var clothing_label = %ClothingLabel
@onready var next_clothing = %NextClothing

@onready var preview_background = %PreviewBackground
@onready var character_preview = %CharacterPreview
@onready var rotate_left_button = %RotateLeftButton
@onready var direction_label = %DirectionLabel
@onready var rotate_right_button = %RotateRightButton
@onready var prev_background = %PrevBackground
@onready var background_label = %BackgroundLabel
@onready var next_background = %NextBackground
@onready var character_info = %CharacterInfo

@onready var equipment_preview = %EquipmentPreview
@onready var loadout_preview_list = %LoadoutPreviewList

@onready var randomize_button = %RandomizeButton
@onready var cancel_button = %CancelButton
@onready var confirm_button = %ConfirmButton

@onready var background_text = %BackgroundText
@onready var medical_text = %MedicalText

var occupation_filter_text = ""
var filtered_occupations = []

func _ready():
	initialize_character_creator()
	setup_ui_connections()
	setup_initial_state()
	setup_tab_system()
	animate_interface_entrance()

func initialize_character_creator():
	default_character_data = character_data.duplicate(true)
	
	_check_multiplayer_mode()
	_load_settings()
	_load_presets()
	
	if not asset_manager:
		push_error("Asset manager not found!")
		return
	
	_reset_to_defaults()
	_load_existing_character_data()
	_load_assets()
	_setup_ui()
	_setup_preset_ui()
	_setup_occupation_ui()
	_initialize_character_preview()
	
	if active_preset_name != "" and presets_data.has(active_preset_name):
		_load_preset_data(presets_data[active_preset_name])
		preset_dropdown.text = active_preset_name
	
	_update_character_preview()
	_update_direction_label()
	_update_equipment_preview()

func setup_tab_system():
	for i in range(tab_names.size()):
		var tab_button = Button.new()
		tab_button.text = tab_names[i]
		tab_button.toggle_mode = true
		tab_button.button_group = ButtonGroup.new() if i == 0 else tab_buttons.get_child(0).button_group
		tab_button.pressed.connect(_on_tab_selected.bind(i))
		
		tab_button.custom_minimum_size = Vector2(60, 24)
		
		tab_buttons.add_child(tab_button)
		
		if i == 0:
			tab_button.button_pressed = true
	
	_show_tab(0)

func _on_tab_selected(tab_index: int):
	if current_tab != tab_index:
		current_tab = tab_index
		_show_tab(tab_index)

func _show_tab(tab_index: int):
	for child in tab_container.get_children():
		child.visible = false
	
	if tab_index < tab_container.get_child_count():
		tab_container.get_child(tab_index).visible = true

func _update_equipment_preview():
	if not loadout_preview_list:
		return
	
	loadout_preview_list.clear()
	
	if not character_data.loadout_enabled:
		loadout_preview_list.add_item("⚠️ Loadout Disabled")
		return
	
	if character_data.occupation >= asset_manager.occupations.size():
		loadout_preview_list.add_item("❌ No Valid Occupation")
		return
	
	var occupation_name = asset_manager.occupations[character_data.occupation]
	var loadout = asset_manager.get_occupation_loadout(occupation_name)
	
	if loadout.is_empty():
		loadout_preview_list.add_item("📦 No Loadout Data")
		return
	
	var clothing = loadout.get("clothing", {})
	if not clothing.is_empty():
		loadout_preview_list.add_item("=== 👕 CLOTHING ===")
		for slot in clothing:
			var item_name = clothing[slot]
			if item_name and item_name != "":
				var slot_name = _get_readable_slot_name(slot)
				loadout_preview_list.add_item("  " + slot_name + ": " + item_name)
	
	var inventory = loadout.get("inventory", {})
	if not inventory.is_empty():
		loadout_preview_list.add_item("=== ⚡ EQUIPMENT ===")
		for slot in inventory:
			var item_name = inventory[slot]
			if item_name and item_name != "":
				var slot_name = _get_readable_slot_name(slot)
				loadout_preview_list.add_item("  " + slot_name + ": " + item_name)
	
	var storage_contents = loadout.get("storage_contents", {})
	if not storage_contents.is_empty():
		loadout_preview_list.add_item("=== 🎒 STORAGE ===")
		for storage_item in storage_contents:
			loadout_preview_list.add_item("  " + storage_item + ":")
			var items = storage_contents[storage_item]
			if items is Array:
				for item in items:
					if item and item != "":
						loadout_preview_list.add_item("    - " + item)

func _apply_loadout_to_preview():
	if not character_data.loadout_enabled:
		_clear_loadout_preview()
		return
	
	if character_data.occupation >= asset_manager.occupations.size():
		return
	
	var occupation_name = asset_manager.occupations[character_data.occupation]
	var loadout = asset_manager.get_occupation_loadout(occupation_name)
	
	if loadout.is_empty():
		return
	
	var sprite_system = preview_sprites.get("sprite_system")
	if not sprite_system:
		return
	
	if sprite_system.has_method("clear_all_equipment"):
		sprite_system.clear_all_equipment()
	
	var clothing = loadout.get("clothing", {})
	for slot_name in clothing:
		var item_name = clothing[slot_name]
		if item_name and item_name != "":
			_apply_loadout_item_to_preview(sprite_system, item_name, slot_name)
	
	var inventory = loadout.get("inventory", {})
	for slot_name in inventory:
		var item_name = inventory[slot_name]
		if item_name and item_name != "":
			_apply_loadout_item_to_preview(sprite_system, item_name, slot_name)

func _apply_loadout_item_to_preview(sprite_system, item_name: String, slot_name: String):
	var temp_item = asset_manager.create_item_from_name(item_name)
	if not temp_item:
		print("Failed to create item: ", item_name)
		return
	
	var slot_id = _get_slot_id_from_loadout_name(slot_name)
	if slot_id != -1:
		if sprite_system.has_method("equip_item"):
			sprite_system.equip_item(temp_item, slot_id)
		elif sprite_system.has_method("_equip_item_internal"):
			sprite_system._equip_item_internal(temp_item, slot_id)

func _get_slot_id_from_loadout_name(slot_name: String) -> int:
	match slot_name:
		"HEAD": return 1
		"GLASSES", "EYES": return 2
		"BACK": return 3
		"WEAR_MASK", "MASK": return 4
		"W_UNIFORM", "UNIFORM": return 6
		"WEAR_SUIT", "SUIT": return 7
		"EARS": return 8
		"GLOVES": return 9
		"SHOES": return 10
		"WEAR_ID", "ID": return 12
		"LEFT_HAND": return 13
		"RIGHT_HAND": return 14
		"BELT": return 15
		"L_STORE": return 16
		"R_STORE": return 17
		"S_STORE": return 18
		_: return -1

func _clear_loadout_preview():
	preview_loadout_items.clear()
	var sprite_system = preview_sprites.get("sprite_system")
	if sprite_system and sprite_system.has_method("clear_all_equipment"):
		sprite_system.clear_all_equipment()

func _get_readable_slot_name(slot: String) -> String:
	match slot:
		"W_UNIFORM": return "Uniform"
		"WEAR_SUIT": return "Suit"
		"HEAD": return "Head"
		"GLASSES": return "Eyes"
		"WEAR_MASK": return "Mask"
		"EARS": return "Ears"
		"GLOVES": return "Gloves"
		"SHOES": return "Shoes"
		"BELT": return "Belt"
		"BACK": return "Backpack"
		"WEAR_ID": return "ID Card"
		"LEFT_HAND": return "Left Hand"
		"RIGHT_HAND": return "Right Hand"
		"L_STORE": return "Left Pocket"
		"R_STORE": return "Right Pocket"
		"S_STORE": return "Suit Storage"
		_: return slot.replace("_", " ").capitalize()

func _setup_occupation_ui():
	occupation_search.text_changed.connect(_on_occupation_search_changed)
	occupation_list.item_selected.connect(_on_occupation_list_selected)
	loadout_enabled_check.toggled.connect(_on_loadout_enabled_toggled)
	
	_update_occupation_list()
	
	if character_data.occupation < asset_manager.occupations.size():
		var occupation_name = asset_manager.occupations[character_data.occupation]
		_select_occupation_in_list(occupation_name)
		_update_occupation_details(occupation_name)

func _update_occupation_list():
	occupation_list.clear()
	filtered_occupations.clear()
	
	var filter = occupation_filter_text.to_lower()
	
	for occupation_name in asset_manager.occupations:
		if filter.is_empty() or occupation_name.to_lower().contains(filter):
			var display_name = asset_manager.get_occupation_display_name(occupation_name)
			occupation_list.add_item(display_name)
			filtered_occupations.append(occupation_name)

func _select_occupation_in_list(occupation_name: String):
	for i in range(filtered_occupations.size()):
		if filtered_occupations[i] == occupation_name:
			occupation_list.select(i)
			break

func _update_occupation_details(occupation_name: String):
	var description = asset_manager.get_occupation_description(occupation_name)
	occupation_description.text = description
	
	_update_equipment_preview()

func _on_occupation_search_changed(new_text: String):
	occupation_filter_text = new_text
	_update_occupation_list()

func _on_occupation_list_selected(index: int):
	if index >= 0 and index < filtered_occupations.size():
		var occupation_name = filtered_occupations[index]
		var occupation_index = asset_manager.occupations.find(occupation_name)
		
		if occupation_index >= 0:
			character_data.occupation = occupation_index
			_update_occupation_details(occupation_name)
			_update_info_label()
			
			auto_select_matching_uniform(occupation_index)
			_apply_loadout_to_preview()
			broadcast_character_change("occupation", character_data.occupation)

func _on_loadout_enabled_toggled(enabled: bool):
	character_data.loadout_enabled = enabled
	
	if enabled:
		_apply_loadout_to_preview()
	else:
		_clear_loadout_preview()
	
	_update_equipment_preview()
	broadcast_character_change("loadout_enabled", enabled)

func _reset_to_defaults():
	character_data = default_character_data.duplicate(true)

func _color_to_dict(color: Color) -> Dictionary:
	return {"r": color.r, "g": color.g, "b": color.b, "a": color.a}

func _dict_to_color(dict: Dictionary) -> Color:
	if dict.has("r") and dict.has("g") and dict.has("b") and dict.has("a"):
		return Color(dict.r, dict.g, dict.b, dict.a)
	else:
		return Color(0.337255, 0.211765, 0.117647)

func setup_ui_connections():
	name_input.text_changed.connect(_on_name_input_text_changed)
	age_spinbox.value_changed.connect(_on_age_spin_box_value_changed)
	race_option.item_selected.connect(_on_race_option_item_selected)
	sex_option.item_selected.connect(_on_sex_option_item_selected)
	
	prev_hair.pressed.connect(_on_prev_hair_pressed)
	next_hair.pressed.connect(_on_next_hair_pressed)
	hair_color_picker.color_changed.connect(_on_hair_color_picker_color_changed)
	prev_facial_hair.pressed.connect(_on_prev_facial_hair_pressed)
	next_facial_hair.pressed.connect(_on_next_facial_hair_pressed)
	facial_hair_color_picker.color_changed.connect(_on_facial_hair_color_picker_color_changed)
	
	prev_underwear.pressed.connect(_on_prev_underwear_pressed)
	next_underwear.pressed.connect(_on_next_underwear_pressed)
	prev_undershirt.pressed.connect(_on_prev_undershirt_pressed)
	next_undershirt.pressed.connect(_on_next_undershirt_pressed)
	prev_clothing.pressed.connect(_on_prev_clothing_pressed)
	next_clothing.pressed.connect(_on_next_clothing_pressed)
	
	background_text.text_changed.connect(_on_background_text_text_changed)
	medical_text.text_changed.connect(_on_medical_text_text_changed)
	
	rotate_left_button.pressed.connect(_on_rotate_left_button_pressed)
	rotate_right_button.pressed.connect(_on_rotate_right_button_pressed)
	prev_background.pressed.connect(_on_prev_background_pressed)
	next_background.pressed.connect(_on_next_background_pressed)
	
	randomize_button.pressed.connect(_on_randomize_button_pressed)
	cancel_button.pressed.connect(_on_cancel_button_pressed)
	confirm_button.pressed.connect(_on_confirm_button_pressed)

func setup_initial_state():
	animate_star_field()
	update_system_time()
	
	var timer = Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(update_system_time)
	timer.autostart = true
	add_child(timer)

func animate_interface_entrance():
	modulate.a = 0
	var entrance_tween = create_tween()
	entrance_tween.tween_property(self, "modulate:a", 1.0, 0.8)

func animate_star_field():
	var star_field = $Background/StarField
	for star in star_field.get_children():
		var star_tween = create_tween()
		star_tween.set_loops()
		var duration = randf_range(2.0, 4.0)
		star_tween.tween_property(star, "modulate:a", 0.2, duration)
		star_tween.tween_property(star, "modulate:a", 0.8, duration)

func update_system_time():
	var time_label = $HeaderBar/HeaderContainer/RightHeader/SystemTime
	if time_label:
		var stardate = "Stardate: " + str(Time.get_ticks_msec() / 100000.0).substr(0, 8)
		time_label.text = stardate

func _check_multiplayer_mode():
	var game_manager = get_node_or_null("/root/GameManager")
	
	if game_manager:
		is_multiplayer_mode = game_manager.is_multiplayer()
		is_host = game_manager.is_multiplayer_host()
		
		if multiplayer and multiplayer.has_multiplayer_peer():
			local_peer_id = multiplayer.get_unique_id()

func _load_existing_character_data():
	var game_manager = get_node_or_null("/root/GameManager")
	
	if game_manager and game_manager.has_method("get_character_data"):
		var existing_data = game_manager.get_character_data()
		if existing_data.size() > 0:
			apply_character_data(existing_data)
			return
	
	if FileAccess.file_exists("user://character_data.json"):
		load_character_data_from_file()

func apply_character_data(data: Dictionary):
	for key in data:
		if key in character_data:
			if key == "hair_color" or key == "facial_hair_color":
				if data[key] is Dictionary:
					character_data[key] = _dict_to_color(data[key])
				elif data[key] is Color:
					character_data[key] = data[key]
			else:
				character_data[key] = data[key]

func load_character_data_from_file():
	var file = FileAccess.open("user://character_data.json", FileAccess.READ)
	if file:
		var json_text = file.get_as_text()
		file.close()
		
		var json_result = JSON.parse_string(json_text)
		if json_result:
			apply_character_data(json_result)

func _load_assets():
	if not asset_manager:
		return
	
	available_hair_styles = asset_manager.get_hair_styles_for_sex(character_data.sex)
	available_facial_hair = asset_manager.get_facial_hair_for_sex(character_data.sex)
	available_clothing = asset_manager.get_clothing_for_sex(character_data.sex)
	available_underwear = asset_manager.get_underwear_for_sex(character_data.sex)
	available_undershirts = asset_manager.get_undershirts_for_sex(character_data.sex)

func _setup_ui():
	if not asset_manager:
		return
	
	setup_species_dropdown()
	setup_gender_dropdown()
	setup_assignment_dropdown()
	setup_initial_values()
	update_color_pickers()
	update_text_areas()
	_update_ui_labels()
	_update_info_label()
	_update_preview_background()

func setup_species_dropdown():
	race_option.clear()
	for race in asset_manager.races:
		race_option.add_item(race)
	race_option.select(character_data.race)

func setup_gender_dropdown():
	sex_option.clear()
	sex_option.add_item("Male")
	sex_option.add_item("Female")
	sex_option.select(character_data.sex)

func setup_assignment_dropdown():
	occupation_option.clear()
	for occupation in asset_manager.occupations:
		var display_name = asset_manager.get_occupation_display_name(occupation)
		occupation_option.add_item(display_name)
	
	if character_data.occupation < asset_manager.occupations.size():
		occupation_option.select(character_data.occupation)
	else:
		occupation_option.select(0)
		character_data.occupation = 0

func setup_initial_values():
	name_input.text = character_data.name
	age_spinbox.value = character_data.age
	
	if loadout_enabled_check:
		loadout_enabled_check.button_pressed = character_data.get("loadout_enabled", true)

func update_color_pickers():
	hair_color_picker.color = character_data.hair_color
	facial_hair_color_picker.color = character_data.facial_hair_color

func update_text_areas():
	background_text.text = character_data.background_text
	medical_text.text = character_data.medical_text

func _update_ui_labels():
	update_hair_label()
	update_facial_hair_label()
	update_clothing_labels()
	update_background_label()

func update_hair_label():
	if character_data.hair_style >= available_hair_styles.size():
		character_data.hair_style = 0
	if available_hair_styles.size() > 0:
		hair_label.text = available_hair_styles[character_data.hair_style].name

func update_facial_hair_label():
	if character_data.sex == 0:
		if character_data.facial_hair >= available_facial_hair.size():
			character_data.facial_hair = 0
		if available_facial_hair.size() > 0:
			facial_hair_label.text = available_facial_hair[character_data.facial_hair].name
	else:
		character_data.facial_hair = 0
		facial_hair_label.text = "None"

func update_clothing_labels():
	if character_data.clothing >= available_clothing.size():
		character_data.clothing = 0
	if available_clothing.size() > 0:
		clothing_label.text = available_clothing[character_data.clothing].name
	
	if character_data.underwear >= available_underwear.size():
		character_data.underwear = 0
	if available_underwear.size() > 0:
		underwear_label.text = available_underwear[character_data.underwear].name
	
	if character_data.undershirt >= available_undershirts.size():
		character_data.undershirt = 0
	if available_undershirts.size() > 0:
		undershirt_label.text = available_undershirts[character_data.undershirt].name

func update_background_label():
	if asset_manager.background_textures.size() > 0:
		background_label.text = asset_manager.background_textures[character_data.preview_background].name

func _update_info_label():
	if not asset_manager:
		return
	
	var species_name = asset_manager.races[character_data.race] if character_data.race < asset_manager.races.size() else "Unknown"
	var assignment_name = ""
	
	if character_data.occupation < asset_manager.occupations.size():
		var occupation_name = asset_manager.occupations[character_data.occupation]
		assignment_name = asset_manager.get_occupation_display_name(occupation_name)
	else:
		assignment_name = "Unassigned"
	
	var info_text = "Name: %s\nAge: %d Standard Years\nSpecies: %s\nAssignment: %s" % [
		character_data.name if character_data.name != "" else "[UNASSIGNED]",
		character_data.age,
		species_name,
		assignment_name
	]
	
	character_info.text = info_text

func _update_direction_label():
	direction_label.text = direction_names[preview_direction]

func _initialize_character_preview():
	var preview_node = character_preview
	
	for child in preview_node.get_children():
		child.queue_free()
	
	preview_node.modulate = Color(1, 1, 1, 1)
	
	var sprite_system = _create_sprite_system()
	
	if sprite_system:
		preview_node.add_child(sprite_system)
		preview_sprites["sprite_system"] = sprite_system
		
		if sprite_system.has_method("initialize"):
			sprite_system.initialize(preview_node)
	else:
		_initialize_legacy_character_preview()

func _create_sprite_system():
	var scene_path = find_sprite_system_scene()
	if scene_path:
		var scene = load(scene_path)
		if scene:
			return scene.instantiate()
	
	var script_path = find_sprite_system_script()
	if script_path:
		var script = load(script_path)
		if script:
			var sprite_system = Node2D.new()
			sprite_system.set_script(script)
			sprite_system.name = "HumanSpriteSystem"
			return sprite_system
	
	return null

func _initialize_legacy_character_preview():
	var preview_node = character_preview
	
	var sprite_data = {
		"body": {"path": "res://Assets/Human/Body.png", "z_index": 0},
		"head": {"path": "res://Assets/Human/Head.png", "z_index": 0},
		"hair": {"path": null, "z_index": 2},
		"facial_hair": {"path": null, "z_index": 2}
	}
	
	if asset_manager:
		var race_sprites = asset_manager.get_race_sprites(character_data.race, character_data.sex)
		for key in race_sprites:
			if sprite_data.has(key) and race_sprites[key].has("texture"):
				sprite_data[key].path = race_sprites[key].texture
	
	for key in sprite_data:
		var sprite = Sprite2D.new()
		sprite.name = key.capitalize()
		sprite.centered = true
		sprite.z_index = sprite_data[key].z_index
		sprite.region_enabled = true
		sprite.region_rect = Rect2(0, 0, 32, 32)
		
		if sprite_data[key].path and ResourceLoader.exists(sprite_data[key].path):
			sprite.texture = load(sprite_data[key].path)
		else:
			sprite.visible = false
		
		preview_node.add_child(sprite)
		preview_sprites[key] = sprite
	
	_update_sprite_frames()

func _update_character_preview():
	if is_updating_preview:
		return
		
	is_updating_preview = true
	
	if not preview_sprites.has("sprite_system") or not preview_sprites["sprite_system"]:
		_update_legacy_preview()
		is_updating_preview = false
		return
	
	var sprite_system = preview_sprites["sprite_system"]
	
	apply_character_settings_to_sprite_system(sprite_system)
	
	if character_data.loadout_enabled:
		_apply_loadout_to_preview()
	
	is_updating_preview = false

func apply_character_settings_to_sprite_system(sprite_system):
	if sprite_system.has_method("set_sex"):
		sprite_system.set_sex(character_data.sex)
	
	if sprite_system.has_method("set_race"):
		sprite_system.set_race(character_data.race)
	
	apply_clothing_to_sprite_system(sprite_system)
	apply_hair_to_sprite_system(sprite_system)
	apply_facial_hair_to_sprite_system(sprite_system)
	
	if sprite_system.has_method("set_direction"):
		sprite_system.set_direction(preview_direction)

func apply_clothing_to_sprite_system(sprite_system):
	if sprite_system.has_method("set_underwear") and character_data.underwear < available_underwear.size():
		var underwear_data = available_underwear[character_data.underwear]
		if underwear_data.texture:
			sprite_system.set_underwear(load(underwear_data.texture))
	
	if sprite_system.has_method("set_undershirt") and character_data.undershirt < available_undershirts.size():
		var undershirt_data = available_undershirts[character_data.undershirt]
		if undershirt_data.texture:
			sprite_system.set_undershirt(load(undershirt_data.texture))
	
	if sprite_system.has_method("set_clothing") and character_data.clothing < available_clothing.size():
		var clothing = available_clothing[character_data.clothing]
		sprite_system.set_clothing(clothing.textures)

func apply_hair_to_sprite_system(sprite_system):
	if sprite_system.has_method("set_hair") and character_data.hair_style < available_hair_styles.size():
		var hair_data = available_hair_styles[character_data.hair_style]
		if hair_data.texture:
			sprite_system.set_hair(load(hair_data.texture), character_data.hair_color)

func apply_facial_hair_to_sprite_system(sprite_system):
	if sprite_system.has_method("set_facial_hair") and character_data.sex == 0 and character_data.facial_hair < available_facial_hair.size():
		var facial_hair_data = available_facial_hair[character_data.facial_hair]
		if facial_hair_data.texture:
			sprite_system.set_facial_hair(load(facial_hair_data.texture), character_data.facial_hair_color)

func _update_legacy_preview():
	if preview_sprites.has("hair") and character_data.hair_style < available_hair_styles.size():
		var hair_sprite = preview_sprites["hair"]
		var hair_data = available_hair_styles[character_data.hair_style]
		if hair_data.texture and ResourceLoader.exists(hair_data.texture):
			hair_sprite.texture = load(hair_data.texture)
			hair_sprite.modulate = character_data.hair_color
			hair_sprite.visible = true
		else:
			hair_sprite.visible = false
	
	_update_sprite_frames()

func _update_sprite_frames():
	if preview_sprites.has("sprite_system"):
		return
		
	for key in preview_sprites:
		var sprite = preview_sprites[key]
		if sprite and sprite.texture and sprite.region_enabled:
			var frame_x = preview_direction * 32
			sprite.region_rect = Rect2(frame_x, 0, 32, 32)

func _update_preview_background():
	if character_data.preview_background < asset_manager.background_textures.size():
		var bg_data = asset_manager.background_textures[character_data.preview_background]
		preview_background.modulate = Color(1, 1, 1, 1)
		
		if bg_data.texture and ResourceLoader.exists(bg_data.texture):
			preview_background.texture = load(bg_data.texture)
		else:
			preview_background.texture = null
			preview_background.modulate = Color(0.1, 0.2, 0.3, 1)
	else:
		preview_background.texture = null
		preview_background.modulate = Color(0.1, 0.2, 0.3, 1)

func _setup_preset_ui():
	_update_preset_dropdown()
	
	if preset_dropdown:
		preset_dropdown.item_selected.connect(_on_preset_dropdown_item_selected)
	
	if save_preset_button:
		save_preset_button.pressed.connect(_on_save_preset_pressed)
	if delete_preset_button:
		delete_preset_button.pressed.connect(_on_delete_preset_pressed)

func _on_preset_dropdown_item_selected(index: int):
	if index == 0:
		return
	
	var selected_text = preset_dropdown.get_item_text(index)
	if presets_data.has(selected_text):
		_load_preset_data(presets_data[selected_text])
		active_preset_name = selected_text
		_save_settings()
		_show_notification("Loaded preset: " + selected_text, Color(0.4, 1, 0.4))

func _on_save_preset_pressed():
	var preset_name = preset_name_input.text.strip_edges()
	save_current_as_preset(preset_name)

func _on_delete_preset_pressed():
	delete_active_preset()

func save_current_as_preset(preset_name: String):
	if preset_name.strip_edges() == "":
		_show_notification("Please enter a preset name", Color(1, 0.4, 0.4))
		return
	
	var preset_data = _save_preset_data()
	presets_data[preset_name] = preset_data
	active_preset_name = preset_name
	_save_presets()
	_save_settings()
	_update_preset_dropdown()
	_show_notification("Preset saved: " + preset_name, Color(0.4, 1, 0.4))

func delete_active_preset():
	if active_preset_name == "":
		_show_notification("No active preset to delete", Color(1, 0.4, 0.4))
		return
	
	if presets_data.has(active_preset_name):
		presets_data.erase(active_preset_name)
		active_preset_name = ""
		_save_presets()
		_save_settings()
		_update_preset_dropdown()
		_show_notification("Preset deleted", Color(0.4, 1, 0.4))

func _update_preset_dropdown():
	preset_dropdown.clear()
	preset_dropdown.add_item("Select Template...")
	
	for preset_name in presets_data.keys():
		preset_dropdown.add_item(preset_name)
		if preset_name == active_preset_name:
			preset_dropdown.select(preset_dropdown.get_item_count() - 1)
	
	if active_preset_name != "":
		active_preset_label.text = "Active: " + active_preset_name
		active_preset_label.modulate = Color(0.4, 1, 0.4)
	else:
		active_preset_label.text = "Active: None"
		active_preset_label.modulate = Color(0.6, 0.8, 0.9, 0.8)

func _save_preset_data() -> Dictionary:
	var preset = character_data.duplicate(true)
	
	preset["hair_color"] = _color_to_dict(character_data.hair_color)
	preset["facial_hair_color"] = _color_to_dict(character_data.facial_hair_color)
	
	preset["timestamp"] = Time.get_datetime_string_from_system()
	return preset

func _load_preset_data(preset: Dictionary):
	for key in character_data.keys():
		if preset.has(key):
			if key == "hair_color" or key == "facial_hair_color":
				if preset[key] is Dictionary:
					character_data[key] = _dict_to_color(preset[key])
				elif preset[key] is Color:
					character_data[key] = preset[key]
			else:
				character_data[key] = preset[key]
	
	_load_assets()
	_setup_ui()
	_update_ui_labels()
	_update_character_preview()
	_update_info_label()
	
	if character_data.occupation < asset_manager.occupations.size():
		var occupation_name = asset_manager.occupations[character_data.occupation]
		_select_occupation_in_list(occupation_name)
		_update_occupation_details(occupation_name)
		if character_data.loadout_enabled:
			_apply_loadout_to_preview()

func _load_presets():
	if FileAccess.file_exists(PRESETS_FILE_PATH):
		var file = FileAccess.open(PRESETS_FILE_PATH, FileAccess.READ)
		if file:
			var json_text = file.get_as_text()
			file.close()
			
			var json = JSON.new()
			var parse_result = json.parse(json_text)
			if parse_result == OK:
				presets_data = json.data

func _save_presets():
	var file = FileAccess.open(PRESETS_FILE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(presets_data))
		file.close()

func _load_settings():
	if FileAccess.file_exists(SETTINGS_FILE_PATH):
		var file = FileAccess.open(SETTINGS_FILE_PATH, FileAccess.READ)
		if file:
			var json_text = file.get_as_text()
			file.close()
			
			var json = JSON.new()
			var parse_result = json.parse(json_text)
			if parse_result == OK and json.data.has("active_preset"):
				active_preset_name = json.data["active_preset"]

func _save_settings():
	var settings = {"active_preset": active_preset_name}
	var file = FileAccess.open(SETTINGS_FILE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(settings))
		file.close()

func _show_notification(text: String, color: Color):
	notification_label.text = text
	notification_label.modulate = color
	notification_label.modulate.a = 1.0
	
	if tween:
		tween.kill()
	
	tween = create_tween()
	tween.tween_interval(3.0)
	tween.tween_property(notification_label, "modulate:a", 0.0, 0.5)

func broadcast_character_change(data_key: String, value):
	if is_multiplayer_mode and multiplayer and multiplayer.has_multiplayer_peer():
		sync_character_update.rpc(local_peer_id, data_key, value)

func broadcast_final_character_data(complete_data: Dictionary):
	if is_multiplayer_mode and multiplayer and multiplayer.has_multiplayer_peer():
		sync_character_data.rpc(local_peer_id, complete_data)

@rpc("any_peer", "reliable", "call_local")
func sync_character_update(peer_id: int, data_key: String, value):
	if not is_multiplayer_mode or peer_id == local_peer_id:
		return

@rpc("any_peer", "reliable", "call_local") 
func sync_character_data(peer_id: int, complete_data: Dictionary):
	if not is_multiplayer_mode:
		return
		
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		if game_manager.has_method("sync_character_data"):
			game_manager.sync_character_data.rpc(peer_id, complete_data)
		elif game_manager.has_method("update_player_customization"):
			game_manager.update_player_customization(peer_id, complete_data)

func find_sprite_system_script():
	for path in sprite_system_script_paths:
		if ResourceLoader.exists(path):
			return path
	return ""

func find_sprite_system_scene():
	for path in sprite_system_scene_paths:
		if ResourceLoader.exists(path):
			return path
	return ""

func get_character_data():
	if not asset_manager:
		return {}
		
	var data = character_data.duplicate(true)
	
	data.hair_color = _color_to_dict(character_data.hair_color)
	data.facial_hair_color = _color_to_dict(character_data.facial_hair_color)
	
	add_readable_names_to_data(data)
	add_texture_paths_to_data(data)
	add_metadata_to_data(data)
	add_loadout_data(data)
	
	return data

func add_loadout_data(data: Dictionary):
	if data.get("loadout_enabled", true) and data.occupation < asset_manager.occupations.size():
		var occupation_name = asset_manager.occupations[data.occupation]
		var loadout = asset_manager.get_occupation_loadout(occupation_name)
		
		if not loadout.is_empty():
			data["occupation_loadout"] = loadout
			data["occupation_display_name"] = asset_manager.get_occupation_display_name(occupation_name)

func add_readable_names_to_data(data: Dictionary):
	data.race_name = asset_manager.races[data.race] if data.race < asset_manager.races.size() else "Human"
	data.sex_name = "Male" if data.sex == 0 else "Female"
	
	if data.occupation < asset_manager.occupations.size():
		var occupation_name = asset_manager.occupations[data.occupation]
		data.occupation_name = occupation_name
		data.occupation_display_name = asset_manager.get_occupation_display_name(occupation_name)
	else:
		data.occupation_name = "Engineer"
		data.occupation_display_name = "Engineer"

func add_texture_paths_to_data(data: Dictionary):
	if data.hair_style < available_hair_styles.size():
		var hair_data = available_hair_styles[data.hair_style]
		data.hair_texture = hair_data.texture
		data.hair_style_name = hair_data.name
		
		data.hair_color_r = character_data.hair_color.r
		data.hair_color_g = character_data.hair_color.g
		data.hair_color_b = character_data.hair_color.b
		data.hair_color_a = character_data.hair_color.a
	else:
		data.hair_texture = null
		data.hair_style_name = "Standard"
	
	add_facial_hair_data(data)
	add_clothing_data(data)

func add_facial_hair_data(data: Dictionary):
	if data.sex == 0 and data.facial_hair < available_facial_hair.size():
		var facial_hair_data = available_facial_hair[data.facial_hair]
		data.facial_hair_texture = facial_hair_data.texture
		data.facial_hair_name = facial_hair_data.name
		
		data.facial_hair_color_r = character_data.facial_hair_color.r
		data.facial_hair_color_g = character_data.facial_hair_color.g
		data.facial_hair_color_b = character_data.facial_hair_color.b
		data.facial_hair_color_a = character_data.facial_hair_color.a
	else:
		data.facial_hair_texture = null
		data.facial_hair_name = "None"

func add_clothing_data(data: Dictionary):
	if data.clothing < available_clothing.size():
		var clothing_data = available_clothing[data.clothing]
		data.clothing_textures = clothing_data.textures.duplicate()
		data.clothing_name = clothing_data.name
	else:
		data.clothing_textures = {}
		data.clothing_name = "Standard Issue"
	
	add_underwear_data(data)
	add_undershirt_data(data)

func add_underwear_data(data: Dictionary):
	if data.underwear < available_underwear.size():
		var underwear_data = available_underwear[data.underwear]
		data.underwear_texture = underwear_data.texture
		data.underwear_name = underwear_data.name
	else:
		var default_underwear = asset_manager.get_underwear_for_sex(data.sex)
		if default_underwear.size() > 0:
			data.underwear_texture = default_underwear[0].texture
			data.underwear_name = default_underwear[0].name

func add_undershirt_data(data: Dictionary):
	if data.undershirt < available_undershirts.size():
		var undershirt_data = available_undershirts[data.undershirt]
		data.undershirt_texture = undershirt_data.texture
		data.undershirt_name = undershirt_data.name
	else:
		if data.sex == 1:
			var default_tops = asset_manager.get_undershirts_for_sex(1)
			if default_tops.size() > 0:
				data.undershirt_texture = default_tops[0].texture
				data.undershirt_name = default_tops[0].name
		else:
			data.undershirt_texture = null
			data.undershirt_name = "None"

func add_metadata_to_data(data: Dictionary):
	data.character_created_version = "3.0"
	data.creation_timestamp = Time.get_ticks_msec()
	data.direction = preview_direction

func auto_select_matching_uniform(index: int):
	if asset_manager and index < asset_manager.occupations.size():
		var occupation_name = asset_manager.occupations[index]
		
		for i in range(available_clothing.size()):
			if available_clothing[i].name.to_lower() == occupation_name.to_lower():
				character_data.clothing = i
				clothing_label.text = available_clothing[i].name
				_update_character_preview()
				broadcast_character_change("clothing", character_data.clothing)
				break

func _generate_random_name() -> String:
	var first_names_male = ["Commander", "Captain", "Lieutenant", "Admiral", "Colonel", "Major", "Sergeant", "Pilot", "Chief", "Specialist"]
	var first_names_female = ["Commander", "Captain", "Lieutenant", "Admiral", "Colonel", "Major", "Sergeant", "Pilot", "Chief", "Specialist"]
	var last_names = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Theta", "Omega", "Nova", "Stellar", "Cosmic", "Vector", "Matrix", "Phoenix"]
	
	var first_names = first_names_male if character_data.sex == 0 else first_names_female
	var first_name = first_names[randi() % first_names.size()]
	var last_name = last_names[randi() % last_names.size()]
	
	return first_name + " " + last_name

func save_character_data_locally(complete_data: Dictionary):
	var save_path = "user://character_data.json"
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_line(JSON.stringify(complete_data))
		file.close()

func handle_character_creation_fallback():
	var next_scene = "res://Scenes/Maps/Hub.tscn"
	
	if ResourceLoader.exists(next_scene):
		_transition_to_scene(func(): get_tree().change_scene_to_file(next_scene))
	else:
		_transition_to_scene(func(): get_tree().change_scene_to_file("res://Scenes/UI/Menus/Main_menu.tscn"))

func _transition_to_scene(callback: Callable):
	var exit_tween = create_tween()
	exit_tween.tween_property(self, "modulate:a", 0.0, 0.4)
	exit_tween.tween_callback(callback)

func _on_name_input_text_changed(new_text):
	character_data.name = new_text
	_update_info_label()
	broadcast_character_change("name", new_text)

func _on_age_spin_box_value_changed(value):
	character_data.age = value
	_update_info_label()
	broadcast_character_change("age", value)

func _on_race_option_item_selected(index):
	character_data.race = index
	_update_character_preview()
	_update_info_label()
	broadcast_character_change("race", index)

func _on_sex_option_item_selected(index):
	character_data.sex = index
	_load_assets()
	
	reset_customization_for_gender()
	update_default_name_for_gender(index)
	
	_update_ui_labels()
	_update_character_preview()
	broadcast_character_change("sex", index)

func reset_customization_for_gender():
	character_data.hair_style = 0
	character_data.facial_hair = 0
	character_data.clothing = 0
	character_data.underwear = 0
	character_data.undershirt = 0
	
	if character_data.sex == 1 and available_undershirts.size() > 0:
		for i in range(available_undershirts.size()):
			if available_undershirts[i].name != "None":
				character_data.undershirt = i
				break

func update_default_name_for_gender(index: int):
	if character_data.name == "Commander Alpha" and index == 1:
		character_data.name = "Commander Beta"
		name_input.text = character_data.name
		_update_info_label()
	elif character_data.name == "Commander Beta" and index == 0:
		character_data.name = "Commander Alpha"
		name_input.text = character_data.name
		_update_info_label()

func _on_prev_hair_pressed():
	if available_hair_styles.size() == 0:
		return
		
	character_data.hair_style = (character_data.hair_style - 1) % available_hair_styles.size()
	if character_data.hair_style < 0:
		character_data.hair_style = available_hair_styles.size() - 1
	
	hair_label.text = available_hair_styles[character_data.hair_style].name
	_update_character_preview()
	broadcast_character_change("hair_style", character_data.hair_style)

func _on_next_hair_pressed():
	if available_hair_styles.size() == 0:
		return

	var index := int(character_data.hair_style)
	index = (index + 1) % available_hair_styles.size()
	character_data.hair_style = index

	hair_label.text = available_hair_styles[index].name
	_update_character_preview()
	broadcast_character_change("hair_style", character_data.hair_style)

func _on_hair_color_picker_color_changed(color):
	character_data.hair_color = color
	_update_character_preview()
	broadcast_character_change("hair_color", color)

func _on_prev_facial_hair_pressed():
	if character_data.sex == 0 and available_facial_hair.size() > 0:
		character_data.facial_hair = (character_data.facial_hair - 1) % available_facial_hair.size()
		if character_data.facial_hair < 0:
			character_data.facial_hair = available_facial_hair.size() - 1
		
		facial_hair_label.text = available_facial_hair[character_data.facial_hair].name
		_update_character_preview()
		broadcast_character_change("facial_hair", character_data.facial_hair)

func _on_next_facial_hair_pressed():
	if character_data.sex == 0 and available_facial_hair.size() > 0:
		character_data.facial_hair = (character_data.facial_hair + 1) % available_facial_hair.size()
		facial_hair_label.text = available_facial_hair[character_data.facial_hair].name
		_update_character_preview()
		broadcast_character_change("facial_hair", character_data.facial_hair)

func _on_facial_hair_color_picker_color_changed(color):
	character_data.facial_hair_color = color
	_update_character_preview()
	broadcast_character_change("facial_hair_color", color)

func _on_prev_underwear_pressed():
	if available_underwear.size() == 0:
		return
		
	character_data.underwear = (character_data.underwear - 1) % available_underwear.size()
	if character_data.underwear < 0:
		character_data.underwear = available_underwear.size() - 1
	
	underwear_label.text = available_underwear[character_data.underwear].name
	_update_character_preview()
	broadcast_character_change("underwear", character_data.underwear)

func _on_next_underwear_pressed():
	if available_underwear.size() == 0:
		return

	var index := int(character_data.underwear)
	index = (index + 1) % available_underwear.size()
	character_data.underwear = index

	underwear_label.text = available_underwear[index].name
	_update_character_preview()
	broadcast_character_change("underwear", character_data.underwear)

func _on_prev_undershirt_pressed():
	if available_undershirts.size() == 0:
		return
	
	if character_data.sex == 1:
		navigate_female_undershirt_previous()
	else:
		character_data.undershirt = (character_data.undershirt - 1) % available_undershirts.size()
		if character_data.undershirt < 0:
			character_data.undershirt = available_undershirts.size() - 1
	
	undershirt_label.text = available_undershirts[character_data.undershirt].name
	_update_character_preview()
	broadcast_character_change("undershirt", character_data.undershirt)

func navigate_female_undershirt_previous():
	var original_index = character_data.undershirt
	var attempts = 0
	
	while attempts < available_undershirts.size():
		character_data.undershirt = (character_data.undershirt - 1) % available_undershirts.size()
		if character_data.undershirt < 0:
			character_data.undershirt = available_undershirts.size() - 1
			
		if available_undershirts[character_data.undershirt].name != "None":
			break
			
		attempts += 1
		
	if attempts >= available_undershirts.size():
		character_data.undershirt = original_index

func _on_next_undershirt_pressed():
	if available_undershirts.size() == 0:
		return
	
	var total = available_undershirts.size()
	var index := int(character_data.undershirt)

	if character_data.sex == 1:
		index = navigate_female_undershirt_next(index, total)
	else:
		index = (index + 1) % total

	character_data.undershirt = index
	undershirt_label.text = available_undershirts[index].name
	_update_character_preview()
	broadcast_character_change("undershirt", character_data.undershirt)

func navigate_female_undershirt_next(current_index: int, total: int) -> int:
	var original_index = current_index
	var attempts = 0
	var index = current_index
	
	while attempts < total:
		index = (index + 1) % total
		if available_undershirts[index].name != "None":
			break
		attempts += 1
	
	if attempts >= total:
		return original_index
	
	return index

func _on_prev_clothing_pressed():
	if available_clothing.size() == 0:
		return
		
	character_data.clothing = (character_data.clothing - 1) % available_clothing.size()
	if character_data.clothing < 0:
		character_data.clothing = available_clothing.size() - 1
	
	clothing_label.text = available_clothing[character_data.clothing].name
	_update_character_preview()
	broadcast_character_change("clothing", character_data.clothing)

func _on_next_clothing_pressed():
	if available_clothing.size() == 0:
		return
		
	character_data.clothing = (character_data.clothing + 1) % available_clothing.size()
	clothing_label.text = available_clothing[character_data.clothing].name
	_update_character_preview()
	broadcast_character_change("clothing", character_data.clothing)

func _on_background_text_text_changed():
	character_data.background_text = background_text.text
	broadcast_character_change("background_text", character_data.background_text)

func _on_medical_text_text_changed():
	character_data.medical_text = medical_text.text
	broadcast_character_change("medical_text", character_data.medical_text)

func _on_rotate_left_button_pressed():
	if preview_sprites.has("sprite_system"):
		var sprite_system = preview_sprites["sprite_system"]
		if sprite_system.has_method("rotate_left"):
			sprite_system.rotate_left()
			if "current_direction" in sprite_system:
				preview_direction = sprite_system.current_direction
			_update_direction_label()
			return
	
	preview_direction = (preview_direction - 1) % Direction.size()
	if preview_direction < 0:
		preview_direction = Direction.size() - 1
	
	_update_sprite_frames()
	_update_direction_label()
	
	if preview_sprites.has("sprite_system"):
		var sprite_system = preview_sprites["sprite_system"]
		if sprite_system.has_method("set_direction"):
			sprite_system.set_direction(preview_direction)

func _on_rotate_right_button_pressed():
	if preview_sprites.has("sprite_system"):
		var sprite_system = preview_sprites["sprite_system"]
		if sprite_system.has_method("rotate_right"):
			sprite_system.rotate_right()
			if "current_direction" in sprite_system:
				preview_direction = sprite_system.current_direction
			_update_direction_label()
			return
	
	preview_direction = (preview_direction + 1) % Direction.size()
	
	_update_sprite_frames()
	_update_direction_label()
	
	if preview_sprites.has("sprite_system"):
		var sprite_system = preview_sprites["sprite_system"]
		if sprite_system.has_method("set_direction"):
			sprite_system.set_direction(preview_direction)

func _on_prev_background_pressed():
	if not asset_manager or asset_manager.background_textures.size() == 0:
		return

	var total = asset_manager.background_textures.size()
	var index = int(character_data.preview_background)
	index = (index - 1) % total
	if index < 0:
		index = total - 1

	character_data.preview_background = index
	background_label.text = asset_manager.background_textures[index].name
	_update_preview_background()
	broadcast_character_change("preview_background", character_data.preview_background)

func _on_next_background_pressed():
	if not asset_manager or asset_manager.background_textures.size() == 0:
		return

	var index := int(character_data.preview_background)
	index = (index + 1) % asset_manager.background_textures.size()
	character_data.preview_background = index

	background_label.text = asset_manager.background_textures[index].name
	_update_preview_background()
	broadcast_character_change("preview_background", character_data.preview_background)

func _on_randomize_button_pressed():
	if not asset_manager:
		return
	
	randomize()
	
	character_data.sex = randi() % 2
	_load_assets()
	
	character_data.name = _generate_random_name()
	character_data.age = randi() % 63 + 18
	character_data.race = randi() % asset_manager.races.size()
	character_data.hair_style = randi() % available_hair_styles.size()
	character_data.hair_color = Color(randf() * 0.8, randf() * 0.6, randf() * 0.4)
	
	if character_data.sex == 0:
		character_data.facial_hair = randi() % available_facial_hair.size()
	else:
		character_data.facial_hair = 0
	
	character_data.facial_hair_color = character_data.hair_color
	character_data.occupation = randi() % asset_manager.occupations.size()
	character_data.clothing = randi() % available_clothing.size()
	character_data.underwear = randi() % available_underwear.size()
	
	randomize_undershirt()
	
	character_data.preview_background = randi() % asset_manager.background_textures.size()
	
	_setup_ui()
	_update_character_preview()
	
	if character_data.occupation < asset_manager.occupations.size():
		var occupation_name = asset_manager.occupations[character_data.occupation]
		_select_occupation_in_list(occupation_name)
		_update_occupation_details(occupation_name)
		if character_data.loadout_enabled:
			_apply_loadout_to_preview()
	
	_show_notification("Random personnel generated", Color(0.4, 1, 0.4))
	
	if is_multiplayer_mode:
		broadcast_character_change("randomized", character_data)

func randomize_undershirt():
	if character_data.sex == 1:
		var valid_tops = []
		for i in range(available_undershirts.size()):
			if available_undershirts[i].name != "None":
				valid_tops.append(i)
		
		if valid_tops.size() > 0:
			character_data.undershirt = valid_tops[randi() % valid_tops.size()]
		else:
			character_data.undershirt = 0
	else:
		character_data.undershirt = randi() % available_undershirts.size()

func _on_cancel_button_pressed():
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("handle_character_creation_cancel"):
		game_manager.handle_character_creation_cancel()
	else:
		_transition_to_scene(func(): get_tree().change_scene_to_file("res://Scenes/UI/Menus/Main_menu.tscn"))

func _on_confirm_button_pressed():
	var complete_data = get_character_data()
	
	if complete_data.is_empty():
		_show_notification("ERROR: Failed to generate personnel data", Color(1, 0.4, 0.4))
		return
	
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		if game_manager.has_method("set_character_data"):
			game_manager.set_character_data(complete_data)
		
		if game_manager.has_method("handle_character_creation_confirm"):
			game_manager.handle_character_creation_confirm()
		else:
			handle_character_creation_fallback()
	else:
		save_character_data_locally(complete_data)
		handle_character_creation_fallback()
	
	broadcast_final_character_data(complete_data)
	
	_show_notification("Personnel registered successfully", Color(0.4, 1, 0.4))
