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
	"preview_background": 0
}

var default_character_data = {}

var preview_sprites = {}
var available_hair_styles = []
var available_facial_hair = []
var available_clothing = []
var available_underwear = []
var available_undershirts = []

enum Direction {SOUTH, NORTH, EAST, WEST}
var preview_direction = Direction.SOUTH
var direction_names = ["FRONT VIEW", "REAR VIEW", "RIGHT PROFILE", "LEFT PROFILE"]

var is_updating_preview = false
var presets_data = {}
var active_preset_name = ""

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
@onready var save_preset_button = %SavePresetButton
@onready var load_preset_button = %LoadPresetButton
@onready var set_active_button = %SetActiveButton
@onready var delete_preset_button = %DeletePresetButton

@onready var name_input = %NameInput
@onready var age_spinbox = %AgeSpinBox
@onready var race_option = %RaceOption
@onready var sex_option = %SexOption
@onready var occupation_option = %OccupationOption

@onready var prev_hair = %PrevHair
@onready var hair_label = %HairLabel
@onready var next_hair = %NextHair
@onready var hair_color_picker = %HairColorPicker
@onready var prev_facial_hair = %PrevFacialHair
@onready var facial_hair_label = %FacialHairLabel
@onready var next_facial_hair = %NextFacialHair
@onready var facial_hair_color_picker = %FacialHairColorPicker

@onready var prev_underwear = %PrevUnderwear
@onready var underwear_label = %UnderwearLabel
@onready var next_underwear = %NextUnderwear
@onready var prev_undershirt = %PrevUndershirt
@onready var undershirt_label = %UndershirtLabel
@onready var next_undershirt = %NextUndershirt
@onready var prev_clothing = %PrevClothing
@onready var clothing_label = %ClothingLabel
@onready var next_clothing = %NextClothing

@onready var background_text = %BackgroundText
@onready var medical_text = %MedicalText

@onready var preview_background = %PreviewBackground
@onready var character_preview = %CharacterPreview
@onready var rotate_left_button = %RotateLeftButton
@onready var direction_label = %DirectionLabel
@onready var rotate_right_button = %RotateRightButton
@onready var prev_background = %PrevBackground
@onready var background_label = %BackgroundLabel
@onready var next_background = %NextBackground
@onready var character_info = %CharacterInfo

@onready var randomize_button = $MainInterface/LeftTerminal/LeftMargin/LeftContent/ActionBar/RandomizeButton
@onready var cancel_button = $MainInterface/LeftTerminal/LeftMargin/LeftContent/ActionBar/CancelButton
@onready var confirm_button = $MainInterface/LeftTerminal/LeftMargin/LeftContent/ActionBar/ConfirmButton

func _ready():
	initialize_character_creator()
	setup_ui_connections()
	setup_initial_state()
	animate_interface_entrance()

func initialize_character_creator():
	"""Initialize the character creation system with all required components"""
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
	_initialize_character_preview()
	
	if active_preset_name != "" and presets_data.has(active_preset_name):
		_load_preset_data(presets_data[active_preset_name])
		preset_dropdown.text = active_preset_name
	
	_update_character_preview()
	_update_direction_label()

func _reset_to_defaults():
	"""Reset character data to default values"""
	character_data = default_character_data.duplicate(true)

func _color_to_dict(color: Color) -> Dictionary:
	"""Convert Color object to dictionary for JSON serialization"""
	return {
		"r": color.r,
		"g": color.g,
		"b": color.b,
		"a": color.a
	}

func _dict_to_color(dict: Dictionary) -> Color:
	"""Convert dictionary back to Color object"""
	if dict.has("r") and dict.has("g") and dict.has("b") and dict.has("a"):
		return Color(dict.r, dict.g, dict.b, dict.a)
	else:
		return Color(0.337255, 0.211765, 0.117647)

func setup_ui_connections():
	"""Connect all UI element signals to their respective handler methods"""
	save_preset_button.pressed.connect(_on_save_preset_pressed)
	load_preset_button.pressed.connect(_on_load_preset_pressed)
	delete_preset_button.pressed.connect(_on_delete_preset_pressed)
	set_active_button.pressed.connect(_on_set_active_preset_pressed)
	preset_dropdown.item_selected.connect(_on_preset_dropdown_selected)
	
	name_input.text_changed.connect(_on_name_input_text_changed)
	age_spinbox.value_changed.connect(_on_age_spin_box_value_changed)
	race_option.item_selected.connect(_on_race_option_item_selected)
	sex_option.item_selected.connect(_on_sex_option_item_selected)
	occupation_option.item_selected.connect(_on_occupation_option_item_selected)
	
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
	"""Setup the initial visual state of the interface"""
	animate_star_field()
	update_system_time()
	
	var timer = Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(update_system_time)
	timer.autostart = true
	add_child(timer)

func animate_interface_entrance():
	"""Perform fade-in animation when interface becomes visible"""
	modulate.a = 0
	var entrance_tween = create_tween()
	entrance_tween.tween_property(self, "modulate:a", 1.0, 0.8)

func animate_star_field():
	"""Create twinkling animations for background stars"""
	var star_field = $Background/StarField
	for star in star_field.get_children():
		var star_tween = create_tween()
		star_tween.set_loops()
		var duration = randf_range(2.0, 4.0)
		star_tween.tween_property(star, "modulate:a", 0.2, duration)
		star_tween.tween_property(star, "modulate:a", 0.8, duration)

func update_system_time():
	"""Update the system time display in the header"""
	var time_label = $HeaderBar/HeaderContainer/RightHeader/SystemTime
	var stardate = "Stardate: " + str(Time.get_ticks_msec() / 100000.0).substr(0, 8)
	time_label.text = stardate

func _check_multiplayer_mode():
	"""Check if the game is in multiplayer mode and configure accordingly"""
	var game_manager = get_node_or_null("/root/GameManager")
	
	if game_manager:
		is_multiplayer_mode = game_manager.is_multiplayer()
		is_host = game_manager.is_multiplayer_host()
		
		if multiplayer and multiplayer.has_multiplayer_peer():
			local_peer_id = multiplayer.get_unique_id()

func _load_existing_character_data():
	"""Load existing character data from GameManager or local storage"""
	var game_manager = get_node_or_null("/root/GameManager")
	
	if game_manager and game_manager.has_method("get_character_data"):
		var existing_data = game_manager.get_character_data()
		if existing_data.size() > 0:
			apply_character_data(existing_data)
			return
	
	if FileAccess.file_exists("user://character_data.json"):
		load_character_data_from_file()

func apply_character_data(data: Dictionary):
	"""Apply character data dictionary to current character configuration"""
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
	"""Load character data from local JSON file"""
	var file = FileAccess.open("user://character_data.json", FileAccess.READ)
	if file:
		var json_text = file.get_as_text()
		file.close()
		
		var json_result = JSON.parse_string(json_text)
		if json_result:
			apply_character_data(json_result)

func _load_assets():
	"""Load character customization assets from the asset manager"""
	if not asset_manager:
		return
	
	available_hair_styles = asset_manager.get_hair_styles_for_sex(character_data.sex)
	available_facial_hair = asset_manager.get_facial_hair_for_sex(character_data.sex)
	available_clothing = asset_manager.get_clothing_for_sex(character_data.sex)
	available_underwear = asset_manager.get_underwear_for_sex(character_data.sex)
	available_undershirts = asset_manager.get_undershirts_for_sex(character_data.sex)

func _setup_ui():
	"""Setup UI dropdown options and initial values"""
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
	"""Configure the species selection dropdown"""
	race_option.clear()
	for race in asset_manager.races:
		race_option.add_item(race)
	race_option.select(character_data.race)

func setup_gender_dropdown():
	"""Configure the gender selection dropdown"""
	sex_option.clear()
	sex_option.add_item("Male")
	sex_option.add_item("Female")
	sex_option.select(character_data.sex)

func setup_assignment_dropdown():
	"""Configure the assignment selection dropdown"""
	occupation_option.clear()
	for occupation in asset_manager.occupations:
		occupation_option.add_item(occupation)
	occupation_option.select(character_data.occupation)

func setup_initial_values():
	"""Set initial values for basic character information"""
	name_input.text = character_data.name
	age_spinbox.value = character_data.age

func update_color_pickers():
	"""Update color picker widgets with current character colors"""
	hair_color_picker.color = character_data.hair_color
	facial_hair_color_picker.color = character_data.facial_hair_color

func update_text_areas():
	"""Update text input areas with current character text data"""
	background_text.text = character_data.background_text
	medical_text.text = character_data.medical_text

func _update_ui_labels():
	"""Update all UI labels with current character configuration names"""
	update_hair_label()
	update_facial_hair_label()
	update_clothing_labels()
	update_background_label()

func update_hair_label():
	"""Update the hair style label with current selection"""
	if character_data.hair_style >= available_hair_styles.size():
		character_data.hair_style = 0
	if available_hair_styles.size() > 0:
		hair_label.text = available_hair_styles[character_data.hair_style].name

func update_facial_hair_label():
	"""Update the facial hair label based on gender and selection"""
	if character_data.sex == 0:
		if character_data.facial_hair >= available_facial_hair.size():
			character_data.facial_hair = 0
		if available_facial_hair.size() > 0:
			facial_hair_label.text = available_facial_hair[character_data.facial_hair].name
	else:
		character_data.facial_hair = 0
		facial_hair_label.text = "None"

func update_clothing_labels():
	"""Update all clothing-related labels with current selections"""
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
	"""Update the background environment label"""
	if asset_manager.background_textures.size() > 0:
		background_label.text = asset_manager.background_textures[character_data.preview_background].name

func _update_info_label():
	"""Update the character information summary display"""
	if not asset_manager:
		return
	
	var species_name = asset_manager.races[character_data.race] if character_data.race < asset_manager.races.size() else "Unknown"
	var assignment_name = asset_manager.occupations[character_data.occupation] if character_data.occupation < asset_manager.occupations.size() else "Unassigned"
	
	var info_text = "Name: %s\nAge: %d Standard Years\nSpecies: %s\nAssignment: %s" % [
		character_data.name if character_data.name != "" else "[UNASSIGNED]",
		character_data.age,
		species_name,
		assignment_name
	]
	
	character_info.text = info_text

func _update_direction_label():
	"""Update the character preview direction label"""
	direction_label.text = direction_names[preview_direction]

func _initialize_character_preview():
	"""Initialize the character preview system"""
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
	"""Create the character sprite system for preview rendering"""
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
	"""Initialize fallback character preview system"""
	var preview_node = character_preview
	
	var sprite_data = {
		"body": {"path": "res://Assets/Human/Body.png", "z_index": 0},
		"head": {"path": "res://Assets/Human/Head.png", "z_index": 1},
		"hair": {"path": null, "z_index": 3},
		"facial_hair": {"path": null, "z_index": 3}
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
	"""Update the character preview with current configuration settings"""
	if is_updating_preview:
		return
		
	is_updating_preview = true
	
	if not preview_sprites.has("sprite_system") or not preview_sprites["sprite_system"]:
		_update_legacy_preview()
		is_updating_preview = false
		return
	
	var sprite_system = preview_sprites["sprite_system"]
	
	apply_character_settings_to_sprite_system(sprite_system)
	
	is_updating_preview = false

func apply_character_settings_to_sprite_system(sprite_system):
	"""Apply current character settings to the sprite system"""
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
	"""Apply clothing configuration to sprite system"""
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
	"""Apply hair configuration to sprite system"""
	if sprite_system.has_method("set_hair") and character_data.hair_style < available_hair_styles.size():
		var hair_data = available_hair_styles[character_data.hair_style]
		if hair_data.texture:
			sprite_system.set_hair(load(hair_data.texture), character_data.hair_color)

func apply_facial_hair_to_sprite_system(sprite_system):
	"""Apply facial hair configuration to sprite system"""
	if sprite_system.has_method("set_facial_hair") and character_data.sex == 0 and character_data.facial_hair < available_facial_hair.size():
		var facial_hair_data = available_facial_hair[character_data.facial_hair]
		if facial_hair_data.texture:
			sprite_system.set_facial_hair(load(facial_hair_data.texture), character_data.facial_hair_color)

func _update_legacy_preview():
	"""Update fallback preview when sprite system is unavailable"""
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
	"""Update sprite frame regions for directional display"""
	if preview_sprites.has("sprite_system"):
		return
		
	for key in preview_sprites:
		var sprite = preview_sprites[key]
		if sprite and sprite.texture and sprite.region_enabled:
			var frame_x = preview_direction * 32
			sprite.region_rect = Rect2(frame_x, 0, 32, 32)

func _update_preview_background():
	"""Update the background environment for character preview"""
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
	"""Setup the character preset management interface"""
	save_preset_button.pressed.connect(_on_save_preset_pressed)
	load_preset_button.pressed.connect(_on_load_preset_pressed)
	delete_preset_button.pressed.connect(_on_delete_preset_pressed)
	set_active_button.pressed.connect(_on_set_active_preset_pressed)
	preset_dropdown.item_selected.connect(_on_preset_dropdown_selected)
	_update_preset_dropdown()

func _update_preset_dropdown():
	"""Update the preset dropdown menu with available presets"""
	preset_dropdown.clear()
	preset_dropdown.add_item("Select Template...")
	
	for preset_name in presets_data.keys():
		preset_dropdown.add_item(preset_name)
		if preset_name == active_preset_name:
			preset_dropdown.select(preset_dropdown.get_item_count() - 1)
	
	if active_preset_name != "":
		active_preset_label.text = "Active Template: " + active_preset_name
		active_preset_label.modulate = Color(0.4, 1, 0.4)
	else:
		active_preset_label.text = "Active Template: None"
		active_preset_label.modulate = Color(0.6, 0.8, 0.9, 0.8)

func _save_preset_data() -> Dictionary:
	"""Save current character configuration as preset data"""
	var preset = character_data.duplicate(true)
	
	preset["hair_color"] = _color_to_dict(character_data.hair_color)
	preset["facial_hair_color"] = _color_to_dict(character_data.facial_hair_color)
	
	preset["timestamp"] = Time.get_datetime_string_from_system()
	return preset

func _load_preset_data(preset: Dictionary):
	"""Load character configuration from preset data"""
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

func _load_presets():
	"""Load saved character presets from file"""
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
	"""Save character presets to file"""
	var file = FileAccess.open(PRESETS_FILE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(presets_data))
		file.close()

func _load_settings():
	"""Load character creation settings from file"""
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
	"""Save character creation settings to file"""
	var settings = {"active_preset": active_preset_name}
	var file = FileAccess.open(SETTINGS_FILE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(settings))
		file.close()

func _show_notification(text: String, color: Color):
	"""Display a temporary notification message to the user"""
	notification_label.text = text
	notification_label.modulate = color
	notification_label.modulate.a = 1.0
	
	if tween:
		tween.kill()
	
	tween = create_tween()
	tween.tween_interval(3.0)
	tween.tween_property(notification_label, "modulate:a", 0.0, 0.5)

func _preset_name_exists(name: String) -> bool:
	"""Check if a preset name already exists"""
	return presets_data.has(name)

@rpc("any_peer", "reliable", "call_local")
func sync_character_update(peer_id: int, data_key: String, value):
	"""Synchronize character updates in multiplayer mode"""
	if not is_multiplayer_mode or peer_id == local_peer_id:
		return

@rpc("any_peer", "reliable", "call_local") 
func sync_character_data(peer_id: int, complete_data: Dictionary):
	"""Synchronize complete character data in multiplayer mode"""
	if not is_multiplayer_mode:
		return
		
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		if game_manager.has_method("sync_character_data"):
			game_manager.sync_character_data.rpc(peer_id, complete_data)
		elif game_manager.has_method("update_player_customization"):
			game_manager.update_player_customization(peer_id, complete_data)

func broadcast_character_change(data_key: String, value):
	"""Broadcast character changes to other players in multiplayer"""
	if is_multiplayer_mode and multiplayer and multiplayer.has_multiplayer_peer():
		sync_character_update.rpc(local_peer_id, data_key, value)

func broadcast_final_character_data(complete_data: Dictionary):
	"""Broadcast final character data to all players in multiplayer"""
	if is_multiplayer_mode and multiplayer and multiplayer.has_multiplayer_peer():
		sync_character_data.rpc(local_peer_id, complete_data)

func find_sprite_system_script():
	"""Find the character sprite system script file"""
	for path in sprite_system_script_paths:
		if ResourceLoader.exists(path):
			return path
	return ""

func find_sprite_system_scene():
	"""Find the character sprite system scene file"""
	for path in sprite_system_scene_paths:
		if ResourceLoader.exists(path):
			return path
	return ""

func get_character_data():
	"""Generate complete character data for export to game systems"""
	if not asset_manager:
		return {}
		
	var data = character_data.duplicate(true)
	
	data.hair_color = _color_to_dict(character_data.hair_color)
	data.facial_hair_color = _color_to_dict(character_data.facial_hair_color)
	
	add_readable_names_to_data(data)
	add_texture_paths_to_data(data)
	add_metadata_to_data(data)
	
	return data

func add_readable_names_to_data(data: Dictionary):
	"""Add human-readable names to character data"""
	data.race_name = asset_manager.races[data.race] if data.race < asset_manager.races.size() else "Human"
	data.occupation_name = asset_manager.occupations[data.occupation] if data.occupation < asset_manager.occupations.size() else "Engineer"
	data.sex_name = "Male" if data.sex == 0 else "Female"

func add_texture_paths_to_data(data: Dictionary):
	"""Add texture paths and style names to character data"""
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
	"""Add facial hair data to character export data"""
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
	"""Add clothing data to character export data"""
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
	"""Add underwear data to character export data"""
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
	"""Add undershirt data to character export data"""
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
	"""Add metadata to character export data"""
	data.character_created_version = "3.0"
	data.creation_timestamp = Time.get_ticks_msec()
	data.direction = preview_direction

func _generate_random_name() -> String:
	"""Generate a random character name based on gender"""
	var first_names_male = ["Commander", "Captain", "Lieutenant", "Admiral", "Colonel", "Major", "Sergeant", "Pilot", "Chief", "Specialist"]
	var first_names_female = ["Commander", "Captain", "Lieutenant", "Admiral", "Colonel", "Major", "Sergeant", "Pilot", "Chief", "Specialist"]
	var last_names = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Theta", "Omega", "Nova", "Stellar", "Cosmic", "Vector", "Matrix", "Phoenix"]
	
	var first_names = first_names_male if character_data.sex == 0 else first_names_female
	var first_name = first_names[randi() % first_names.size()]
	var last_name = last_names[randi() % last_names.size()]
	
	return first_name + " " + last_name

func _on_save_preset_pressed():
	"""Handle save preset button press"""
	var dialog = AcceptDialog.new()
	var vbox = VBoxContainer.new()
	var label = Label.new()
	var line_edit = LineEdit.new()
	
	label.text = "Enter template name:"
	line_edit.placeholder_text = "Personnel Template"
	line_edit.text = character_data.name if character_data.name != "" else "New Template"
	
	vbox.add_child(label)
	vbox.add_child(line_edit)
	dialog.add_child(vbox)
	dialog.title = "Save Personnel Template"
	
	get_tree().current_scene.add_child(dialog)
	dialog.popup_centered()
	
	var result = await dialog.confirmed
	var preset_name = line_edit.text.strip_edges()
	
	dialog.queue_free()
	
	if preset_name != "":
		if _preset_name_exists(preset_name):
			var confirm_dialog = ConfirmationDialog.new()
			confirm_dialog.dialog_text = "A template named '" + preset_name + "' already exists. Do you want to overwrite it?"
			get_tree().current_scene.add_child(confirm_dialog)
			confirm_dialog.popup_centered()
			
			var overwrite_result = await confirm_dialog.confirmed
			confirm_dialog.queue_free()
			
			if not overwrite_result:
				_show_notification("Save cancelled", Color(1, 0.8, 0.4))
				return
		
		presets_data[preset_name] = _save_preset_data()
		_save_presets()
		_update_preset_dropdown()
		_show_notification("Template '" + preset_name + "' saved successfully", Color(0.4, 1, 0.4))

func _on_load_preset_pressed():
	"""Handle load preset button press"""
	var selected_index = preset_dropdown.selected
	if selected_index <= 0:
		_show_notification("Please select a template to load", Color(1, 0.8, 0.4))
		return
	
	var preset_name = preset_dropdown.get_item_text(selected_index)
	if presets_data.has(preset_name):
		_load_preset_data(presets_data[preset_name])
		_show_notification("Loaded template '" + preset_name + "'", Color(0.4, 1, 0.4))

func _on_delete_preset_pressed():
	"""Handle delete preset button press"""
	var selected_index = preset_dropdown.selected
	if selected_index <= 0:
		_show_notification("Please select a template to delete", Color(1, 0.8, 0.4))
		return
	
	var preset_name = preset_dropdown.get_item_text(selected_index)
	
	var dialog = ConfirmationDialog.new()
	dialog.dialog_text = "Delete template '" + preset_name + "'? This action cannot be undone."
	get_tree().current_scene.add_child(dialog)
	dialog.popup_centered()
	
	var result = await dialog.confirmed
	dialog.queue_free()
	
	if result and presets_data.has(preset_name):
		presets_data.erase(preset_name)
		if active_preset_name == preset_name:
			active_preset_name = ""
			_save_settings()
		_save_presets()
		_update_preset_dropdown()
		_show_notification("Template '" + preset_name + "' deleted", Color(1, 0.6, 0.6))

func _on_set_active_preset_pressed():
	"""Handle set active preset button press"""
	var selected_index = preset_dropdown.selected
	if selected_index <= 0:
		_show_notification("Please select a template to set as active", Color(1, 0.8, 0.4))
		return
	
	var preset_name = preset_dropdown.get_item_text(selected_index)
	active_preset_name = preset_name
	_save_settings()
	_update_preset_dropdown()
	_show_notification("Set '" + preset_name + "' as active template", Color(0.4, 0.8, 1))

func _on_preset_dropdown_selected(index: int):
	"""Handle preset dropdown selection change"""
	var is_valid = index > 0
	load_preset_button.disabled = not is_valid
	delete_preset_button.disabled = not is_valid
	set_active_button.disabled = not is_valid

func _on_name_input_text_changed(new_text):
	"""Handle character name input changes"""
	character_data.name = new_text
	_update_info_label()
	broadcast_character_change("name", new_text)

func _on_age_spin_box_value_changed(value):
	"""Handle character age input changes"""
	character_data.age = value
	_update_info_label()
	broadcast_character_change("age", value)

func _on_race_option_item_selected(index):
	"""Handle species selection changes"""
	character_data.race = index
	_update_character_preview()
	_update_info_label()
	broadcast_character_change("race", index)

func _on_sex_option_item_selected(index):
	"""Handle gender selection changes"""
	character_data.sex = index
	_load_assets()
	
	reset_customization_for_gender()
	update_default_name_for_gender(index)
	
	_update_ui_labels()
	_update_character_preview()
	broadcast_character_change("sex", index)

func reset_customization_for_gender():
	"""Reset customization options when gender changes"""
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
	"""Update default character name based on gender selection"""
	if character_data.name == "Commander Alpha" and index == 1:
		character_data.name = "Commander Beta"
		name_input.text = character_data.name
		_update_info_label()
	elif character_data.name == "Commander Beta" and index == 0:
		character_data.name = "Commander Alpha"
		name_input.text = character_data.name
		_update_info_label()

func _on_occupation_option_item_selected(index):
	"""Handle assignment selection changes"""
	character_data.occupation = index
	_update_info_label()
	broadcast_character_change("occupation", index)
	
	auto_select_matching_uniform(index)

func auto_select_matching_uniform(index: int):
	"""Automatically select uniform that matches the selected assignment"""
	if asset_manager and index < asset_manager.occupations.size():
		var occupation_name = asset_manager.occupations[index]
		
		for i in range(available_clothing.size()):
			if available_clothing[i].name.to_lower() == occupation_name.to_lower():
				character_data.clothing = i
				clothing_label.text = available_clothing[i].name
				_update_character_preview()
				broadcast_character_change("clothing", character_data.clothing)
				break

func _on_prev_hair_pressed():
	"""Handle previous hair style button press"""
	if available_hair_styles.size() == 0:
		return
		
	character_data.hair_style = (character_data.hair_style - 1) % available_hair_styles.size()
	if character_data.hair_style < 0:
		character_data.hair_style = available_hair_styles.size() - 1
	
	hair_label.text = available_hair_styles[character_data.hair_style].name
	_update_character_preview()
	broadcast_character_change("hair_style", character_data.hair_style)

func _on_next_hair_pressed():
	"""Handle next hair style button press"""
	if available_hair_styles.size() == 0:
		return

	var index := int(character_data.hair_style)
	index = (index + 1) % available_hair_styles.size()
	character_data.hair_style = index

	hair_label.text = available_hair_styles[index].name
	_update_character_preview()
	broadcast_character_change("hair_style", character_data.hair_style)

func _on_hair_color_picker_color_changed(color):
	"""Handle hair color selection changes"""
	character_data.hair_color = color
	_update_character_preview()
	broadcast_character_change("hair_color", color)

func _on_prev_facial_hair_pressed():
	"""Handle previous facial hair style button press"""
	if character_data.sex == 0 and available_facial_hair.size() > 0:
		character_data.facial_hair = (character_data.facial_hair - 1) % available_facial_hair.size()
		if character_data.facial_hair < 0:
			character_data.facial_hair = available_facial_hair.size() - 1
		
		facial_hair_label.text = available_facial_hair[character_data.facial_hair].name
		_update_character_preview()
		broadcast_character_change("facial_hair", character_data.facial_hair)

func _on_next_facial_hair_pressed():
	"""Handle next facial hair style button press"""
	if character_data.sex == 0 and available_facial_hair.size() > 0:
		character_data.facial_hair = (character_data.facial_hair + 1) % available_facial_hair.size()
		facial_hair_label.text = available_facial_hair[character_data.facial_hair].name
		_update_character_preview()
		broadcast_character_change("facial_hair", character_data.facial_hair)

func _on_facial_hair_color_picker_color_changed(color):
	"""Handle facial hair color selection changes"""
	character_data.facial_hair_color = color
	_update_character_preview()
	broadcast_character_change("facial_hair_color", color)

func _on_prev_underwear_pressed():
	"""Handle previous underwear selection button press"""
	if available_underwear.size() == 0:
		return
		
	character_data.underwear = (character_data.underwear - 1) % available_underwear.size()
	if character_data.underwear < 0:
		character_data.underwear = available_underwear.size() - 1
	
	underwear_label.text = available_underwear[character_data.underwear].name
	_update_character_preview()
	broadcast_character_change("underwear", character_data.underwear)

func _on_next_underwear_pressed():
	"""Handle next underwear selection button press"""
	if available_underwear.size() == 0:
		return

	var index := int(character_data.underwear)
	index = (index + 1) % available_underwear.size()
	character_data.underwear = index

	underwear_label.text = available_underwear[index].name
	_update_character_preview()
	broadcast_character_change("underwear", character_data.underwear)

func _on_prev_undershirt_pressed():
	"""Handle previous undershirt selection button press"""
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
	"""Navigate previous undershirt options for female characters, skipping 'None'"""
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
	"""Handle next undershirt selection button press"""
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
	"""Navigate next undershirt options for female characters, skipping 'None'"""
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
	"""Handle previous clothing selection button press"""
	if available_clothing.size() == 0:
		return
		
	character_data.clothing = (character_data.clothing - 1) % available_clothing.size()
	if character_data.clothing < 0:
		character_data.clothing = available_clothing.size() - 1
	
	clothing_label.text = available_clothing[character_data.clothing].name
	_update_character_preview()
	broadcast_character_change("clothing", character_data.clothing)

func _on_next_clothing_pressed():
	"""Handle next clothing selection button press"""
	if available_clothing.size() == 0:
		return
		
	character_data.clothing = (character_data.clothing + 1) % available_clothing.size()
	clothing_label.text = available_clothing[character_data.clothing].name
	_update_character_preview()
	broadcast_character_change("clothing", character_data.clothing)

func _on_background_text_text_changed():
	"""Handle background text input changes"""
	character_data.background_text = background_text.text
	broadcast_character_change("background_text", character_data.background_text)

func _on_medical_text_text_changed():
	"""Handle medical text input changes"""
	character_data.medical_text = medical_text.text
	broadcast_character_change("medical_text", character_data.medical_text)

func _on_rotate_left_button_pressed():
	"""Handle character preview rotation left button press"""
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
	"""Handle character preview rotation right button press"""
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
	"""Handle previous background environment button press"""
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
	"""Handle next background environment button press"""
	if not asset_manager or asset_manager.background_textures.size() == 0:
		return

	var index := int(character_data.preview_background)
	index = (index + 1) % asset_manager.background_textures.size()
	character_data.preview_background = index

	background_label.text = asset_manager.background_textures[index].name
	_update_preview_background()
	broadcast_character_change("preview_background", character_data.preview_background)

func _on_randomize_button_pressed():
	"""Handle randomize character button press"""
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
	
	_show_notification("Random personnel generated", Color(0.4, 1, 0.4))
	
	if is_multiplayer_mode:
		broadcast_character_change("randomized", character_data)

func randomize_undershirt():
	"""Randomize undershirt selection based on gender requirements"""
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
	"""Handle cancel button press to abort character creation"""
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("handle_character_creation_cancel"):
		game_manager.handle_character_creation_cancel()
	else:
		_transition_to_scene(func(): get_tree().change_scene_to_file("res://Scenes/UI/Menus/Main_menu.tscn"))

func _on_confirm_button_pressed():
	"""Handle confirm button press to finalize character creation"""
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

func save_character_data_locally(complete_data: Dictionary):
	"""Save character data to local storage when GameManager is unavailable"""
	var save_path = "user://character_data.json"
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_line(JSON.stringify(complete_data))
		file.close()

func handle_character_creation_fallback():
	"""Handle character creation completion when GameManager is unavailable"""
	var next_scene = "res://Scenes/Maps/Zypharion.tscn"
	
	if ResourceLoader.exists(next_scene):
		_transition_to_scene(func(): get_tree().change_scene_to_file(next_scene))
	else:
		_transition_to_scene(func(): get_tree().change_scene_to_file("res://Scenes/UI/Menus/Main_menu.tscn"))

func _transition_to_scene(callback: Callable):
	"""Perform fade-out transition before executing callback"""
	var exit_tween = create_tween()
	exit_tween.tween_property(self, "modulate:a", 0.0, 0.4)
	exit_tween.tween_callback(callback)
