# ItemSelectorPopup - Dynamic selector for hair, facial hair, underwear.
extends PopupPanel

@onready var title_label: Label = $VBoxContainer/Title
@onready var grid: GridContainer = $VBoxContainer/ScrollContainer/GridContainer
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
	
	var dir: DirAccess = DirAccess.open(full_folder)
	if dir:
		dir.list_dir_begin()
		var file: String = dir.get_next()
		while file:
			if not dir.current_is_dir() and file.begins_with(prefix) and file.ends_with(".png"):
				# Exclude normal and specular maps
				if file.contains("_n") or file.contains("_s"):
					file = dir.get_next()
					continue
				# Gender restrictions
				if item_type == "facial_hair" and gender == "Female":
					file = dir.get_next()
					continue
				if item_type == "underwear" and gender == "Male" and file.to_lower().contains("bra"):
					file = dir.get_next()
					continue
				var btn: TextureButton = TextureButton.new()
				var res_path = full_folder + file
				var uid = ResourceLoader.get_resource_uid(res_path)
				var load_path = ResourceUID.id_to_text(uid) if uid != ResourceUID.INVALID_ID else res_path
				var tex: Texture2D = load(load_path)
				if tex:
					var atlas = AtlasTexture.new()
					atlas.atlas = tex
					atlas.region = Rect2(0, 0, 32, 32)
					btn.texture_normal = atlas
					btn.custom_minimum_size = Vector2(64, 64)
					btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
					var style_name: String
					if item_type == "hair" or item_type == "facial_hair":
						style_name = file.replace(prefix, "").replace(".png", "")
					else:
						style_name = file.replace(prefix + "_", "").replace(".png", "")
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

func _on_close_pressed() -> void:
	hide()
