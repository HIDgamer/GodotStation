extends PopupPanel

@onready var title_label: Label = $VBoxContainer/Title
@onready var grid: GridContainer = $VBoxContainer/ScrollContainer/CenterContainer/GridContainer
@onready var preference_manager: Node = $/root/PreferenceManager

var item_type: String = ""
var button_to_update: Button = null

func set_type(type: String, button: Button) -> void:
	item_type = type
	button_to_update = button
	title_label.text = "Select " + type.capitalize().replace("_", " ")
	populate_items()

func populate_items() -> void:
	if not grid:
		return
	for child in grid.get_children():
		child.queue_free()
	
	var data: Dictionary = preference_manager.get_character_data()
	var race: String = data.get("race", "Western")
	var gender: String = data.get("gender", "Male")
	var folder: String = "res://Assets/Human/Race/" + race + "/"
	var subfolder: String = ""
	if item_type == "hair":
		folder = "res://Assets/Human/BodyHair/"
		subfolder = "Hair/"
	elif item_type == "facial_hair":
		folder = "res://Assets/Human/BodyHair/"
		subfolder = "FacialHair/"
	elif item_type == "underwear":
		folder = "res://Assets/Human/Clothing/"
		subfolder = "UnderWear/"
	elif item_type == "undershirt":
		folder = "res://Assets/Human/Clothing/"
		subfolder = "UnderShirt/"
	var full_folder: String = folder + subfolder
	var prefix: String
	if item_type == "hair":
		prefix = "Hair"
	elif item_type == "facial_hair":
		prefix = "Facial"
	elif item_type == "undershirt":
		prefix = "UnderShirt"
	else:
		prefix = item_type.capitalize()
	
	if item_type == "hair":
		var none_btn: Button = Button.new()
		none_btn.text = "None"
		none_btn.custom_minimum_size = Vector2(64, 64)
		none_btn.tooltip_text = "No hair"
		none_btn.pressed.connect(_on_none_selected)
		grid.add_child(none_btn)
	
	if item_type == "facial_hair":
		var none_btn: Button = Button.new()
		none_btn.text = "None"
		none_btn.custom_minimum_size = Vector2(64, 64)
		none_btn.tooltip_text = "No facial hair"
		none_btn.pressed.connect(_on_none_selected)
		grid.add_child(none_btn)
	
	if item_type == "undershirt" and gender == "Male":
		var none_btn: Button = Button.new()
		none_btn.text = "None"
		none_btn.custom_minimum_size = Vector2(64, 64)
		none_btn.tooltip_text = "No undershirt"
		none_btn.pressed.connect(_on_none_selected)
		grid.add_child(none_btn)
	
	var dir: DirAccess = DirAccess.open(full_folder)
	if not dir:
		return
	
	dir.list_dir_begin()
	var file: String = dir.get_next()
	while file:
		var is_valid_file: bool = false
		var original_filename: String = file
		
		if file.ends_with(".png"):
			if file.begins_with(prefix):
				is_valid_file = true
		elif file.ends_with(".import"):
			var base_name: String = file.replace(".import", "")
			if base_name.begins_with(prefix):
				is_valid_file = true
				original_filename = base_name
		
		if is_valid_file:
			if file.contains("_n") or file.contains("_s"):
				file = dir.get_next()
				continue
			if item_type == "facial_hair" and gender == "Female":
				file = dir.get_next()
				continue
			if item_type == "underwear" and gender == "Male" and file.to_lower().contains("bra"):
				file = dir.get_next()
				continue
			var btn: TextureButton = TextureButton.new()
			var res_path = full_folder + original_filename
			var tex: Texture2D = load(res_path)
			if tex:
				var atlas = AtlasTexture.new()
				atlas.atlas = tex
				atlas.region = Rect2(0, 0, 32, 32)
				btn.texture_normal = atlas
				btn.custom_minimum_size = Vector2(64, 64)
				btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
				var style_name: String = original_filename.replace(".png", "").replace(".import", "")
				if item_type == "hair" or item_type == "facial_hair":
					style_name = style_name.replace(prefix, "")
				else:
					style_name = style_name.replace(prefix + "_", "")
				btn.tooltip_text = style_name
				btn.connect("pressed", Callable(self, "_on_item_selected").bind(style_name))
				grid.add_child(btn)
		file = dir.get_next()
	dir.list_dir_end()

func _on_item_selected(style: String) -> void:
	preference_manager.update_character_field(item_type + "_style", style)
	if button_to_update:
		button_to_update.text = style
	self.get_parent().update_sprite_preview()
	hide()

func _on_none_selected() -> void:
	preference_manager.update_character_field(item_type + "_style", "")
	if button_to_update:
		button_to_update.text = "None"
	self.get_parent().update_sprite_preview()
	hide()

func _on_close_pressed() -> void:
	hide()
