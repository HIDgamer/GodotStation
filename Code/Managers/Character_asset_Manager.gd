extends Node

# Asset categories
var hair_styles = []
var facial_hair_styles = []
var clothing_options = []
var underwear_options = []
var undershirt_options = []
var background_textures = []
var races = []
var occupations = []

# Directory paths
const BASE_HUMAN_PATH = "res://Assets/Human/"
const HAIR_STYLES_PATH = "res://Assets/Human/Hair/"
const FACIAL_HAIR_PATH = "res://Assets/Human/FacialHair/"
const CLOTHING_PATH = "res://Assets/Human/Clothing/"
const UNDERWEAR_PATH = "res://Assets/Human/UnderWear/"
const UNDERSHIRT_PATH = "res://Assets/Human/UnderShirt/"
const BACKGROUNDS_PATH = "res://Assets/Backgrounds/"
const ASSET_CONFIG_PATH = "res://Config/character_assets.json"

# Resource cache
var _resource_cache = {}

func _init():
	_load_defaults()
	_scan_directories()
	_load_config_file()
	_verify_assets()
	_preload_essential_assets()

# Load default fallback values
func _load_defaults():
	races = []
	occupations = ["Engineer", "Security", "Medical", "Science", "Command", "Cargo"]
	
	hair_styles = [{"name": "None", "texture": null, "sex": -1}]
	facial_hair_styles = [{"name": "None", "texture": null, "sex": 0}]
	clothing_options = [{"name": "None", "textures": {}, "sex": -1}]
	
	underwear_options = [
		{"name": "White Briefs", "texture": "res://Assets/Human/UnderWear/Trunks.png", "sex": 0},
		{"name": "White Panties", "texture": "res://Assets/Human/UnderWear/Panties.png", "sex": 1}
	]
	
	undershirt_options = [
		{"name": "None", "texture": null, "sex": 0},
		{"name": "White Bra", "texture": "res://Assets/Human/UnderShirt/white_bra.png", "sex": 1},
		{"name": "White Undershirt", "texture": "res://Assets/Human/UnderShirt/white_shirt.png", "sex": -1}
	]
	
	background_textures = [{"name": "Space", "texture": "res://Assets/Backgrounds/Space.png"}]

# Preload essential assets for performance
func _preload_essential_assets():
	var essential_dirs = ["res://Assets/Human/"]
	
	for race in races:
		var race_dir = BASE_HUMAN_PATH + race + "/"
		if DirAccess.dir_exists_absolute(race_dir):
			essential_dirs.append(race_dir)
	
	for dir_path in essential_dirs:
		_preload_directory(dir_path)
	
	# Preload mandatory items
	for item in underwear_options:
		if item.texture and ResourceLoader.exists(item.texture):
			_resource_cache[item.texture] = load(item.texture)
	
	for item in undershirt_options:
		if item.texture and ResourceLoader.exists(item.texture):
			_resource_cache[item.texture] = load(item.texture)

func _preload_directory(dir_path):
	if not DirAccess.dir_exists_absolute(dir_path):
		return
		
	var dir = DirAccess.open(dir_path)
	if not dir:
		return
		
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".png"):
			var full_path = dir_path.path_join(file_name)
			if ResourceLoader.exists(full_path):
				_resource_cache[full_path] = load(full_path)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()

# Get cached resource or load it
func get_resource(path):
	if path == null or path.is_empty():
		return null
		
	if _resource_cache.has(path):
		return _resource_cache[path]
	
	if ResourceLoader.exists(path):
		var resource = load(path)
		_resource_cache[path] = resource
		return resource
	
	return null

# Scan all asset directories
func _scan_directories():
	_scan_races()
	_scan_hair_styles()
	_scan_facial_hair()
	_scan_clothing()
	_scan_underwear()
	_scan_undershirts()
	_scan_backgrounds()
	_scan_occupations()

func _scan_races():
	races = []
	
	if _check_if_race_has_assets("res://Assets/Human/"):
		races.append("Human")
	
	var variant_dir = DirAccess.open("res://Assets/Human/")
	if variant_dir:
		variant_dir.list_dir_begin()
		var variant_name = variant_dir.get_next()
		
		while variant_name != "":
			if variant_dir.current_is_dir() and !variant_name.begins_with("."):
				if not variant_name in ["Hair", "FacialHair", "Clothing", "UnderWear", "UnderShirt"]:
					var variant_path = "res://Assets/Human/" + variant_name + "/"
					if _check_if_race_has_assets(variant_path):
						races.append(variant_name)
			
			variant_name = variant_dir.get_next()
	
	if races.size() == 0:
		races.append("Human")

func _check_if_race_has_assets(directory_path: String) -> bool:
	var dir = DirAccess.open(directory_path)
	if !dir:
		return false
		
	var has_assets = false
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if !dir.current_is_dir() and file_name.ends_with(".png"):
			if file_name.begins_with("Body") or file_name.begins_with("Head"):
				has_assets = true
				break
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	return has_assets

func _scan_hair_styles():
	var dir = DirAccess.open(HAIR_STYLES_PATH)
	if dir:
		if hair_styles.size() > 0 and hair_styles[0].name == "None":
			var none_option = hair_styles[0]
			hair_styles.clear()
			hair_styles.append(none_option)
		else:
			hair_styles.clear()
			hair_styles.append({"name": "None", "texture": null, "sex": -1})
		
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if !dir.current_is_dir() and file_name.ends_with(".png") and !file_name.begins_with("."):
				var style_name = file_name.get_basename()
				style_name = style_name.replace("_", " ").capitalize()
				
				var sex = -1
				if file_name.to_lower().contains("_male"):
					sex = 0
				elif file_name.to_lower().contains("_female"):
					sex = 1
					
				style_name = style_name.replace(" Male", "").replace(" Female", "")
				var texture_path = HAIR_STYLES_PATH + file_name
				
				if ResourceLoader.exists(texture_path):
					hair_styles.append({
						"name": style_name,
						"texture": texture_path,
						"sex": sex
					})
			
			file_name = dir.get_next()

func _scan_facial_hair():
	var dir = DirAccess.open(FACIAL_HAIR_PATH)
	if !dir:
		dir = DirAccess.open(HAIR_STYLES_PATH)
	
	if dir:
		if facial_hair_styles.size() > 0 and facial_hair_styles[0].name == "None":
			var none_option = facial_hair_styles[0]
			facial_hair_styles.clear()
			facial_hair_styles.append(none_option)
		else:
			facial_hair_styles.clear()
			facial_hair_styles.append({"name": "None", "texture": null, "sex": 0})
		
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if !dir.current_is_dir() and file_name.ends_with(".png") and !file_name.begins_with("."):
				if file_name.contains("Facial_") or file_name.begins_with("Beard") or file_name.begins_with("Mustache") or file_name.contains("facial"):
					var style_name = file_name.get_basename()
					style_name = style_name.replace("_", " ").replace("Facial ", "").capitalize()
					
					var file_path = dir.get_current_dir().path_join(file_name)
					
					if ResourceLoader.exists(file_path):
						facial_hair_styles.append({
							"name": style_name,
							"texture": file_path,
							"sex": 0
						})
			
			file_name = dir.get_next()

func _scan_clothing():
	var dir = DirAccess.open(CLOTHING_PATH)
	if dir:
		if clothing_options.size() > 0 and clothing_options[0].name == "None":
			var none_option = clothing_options[0]
			clothing_options.clear()
			clothing_options.append(none_option)
		else:
			clothing_options.clear()
			clothing_options.append({"name": "None", "textures": {}, "sex": -1})
		
		var clothing_sets = _scan_clothing_sets(dir)
		
		for set_name in clothing_sets:
			var sex = -1
			
			if set_name.to_lower().contains("_male"):
				sex = 0
			elif set_name.to_lower().contains("_female"):
				sex = 1
			
			var display_name = set_name.replace("_Male", "").replace("_Female", "")
			display_name = display_name.replace("_", " ").capitalize()
			
			clothing_options.append({
				"name": display_name,
				"textures": clothing_sets[set_name]["textures"],
				"sex": sex
			})

func _scan_clothing_sets(dir):
	var clothing_sets = {}
	
	# Scan files
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if !dir.current_is_dir() and file_name.ends_with(".png") and !file_name.begins_with("."):
			var parts = file_name.get_basename().split("_")
			
			if parts.size() >= 2:
				var set_name = ""
				for i in range(parts.size() - 1):
					if i > 0:
						set_name += "_"
					set_name += parts[i]
				
				var part_name = parts[parts.size() - 1]
				
				if !clothing_sets.has(set_name):
					clothing_sets[set_name] = {"textures": {}}
				
				var texture_path = dir.get_current_dir().path_join(file_name)
				clothing_sets[set_name]["textures"][part_name] = texture_path
		
		file_name = dir.get_next()
	
	# Scan subdirectories
	dir.list_dir_begin()
	file_name = dir.get_next()
	
	while file_name != "":
		if dir.current_is_dir() and !file_name.begins_with("."):
			var set_name = file_name
			var set_dir = DirAccess.open(dir.get_current_dir().path_join(file_name))
			
			if set_dir:
				if !clothing_sets.has(set_name):
					clothing_sets[set_name] = {"textures": {}}
				
				set_dir.list_dir_begin()
				var part_file = set_dir.get_next()
				
				while part_file != "":
					if !set_dir.current_is_dir() and part_file.ends_with(".png"):
						var part_name = part_file.get_basename()
						var texture_path = set_dir.get_current_dir().path_join(part_file)
						clothing_sets[set_name]["textures"][part_name] = texture_path
					
					part_file = set_dir.get_next()
		
		file_name = dir.get_next()
	
	return clothing_sets

func _scan_underwear():
	var dir = DirAccess.open(UNDERWEAR_PATH)
	if dir:
		var has_male = false
		var has_female = false
		var defaults = []
		
		for item in underwear_options:
			if item.sex == 0:
				has_male = true
			elif item.sex == 1:
				has_female = true
			defaults.append(item)
		
		underwear_options.clear()
		
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if !dir.current_is_dir() and file_name.ends_with(".png") and !file_name.begins_with("."):
				var item_name = file_name.get_basename()
				item_name = item_name.replace("_", " ").capitalize()
				
				var sex = -1
				if file_name.to_lower().contains("_male") or file_name.to_lower().contains("boxers") or file_name.to_lower().contains("briefs"):
					sex = 0
					has_male = true
				elif file_name.to_lower().contains("_female") or file_name.to_lower().contains("panties"):
					sex = 1
					has_female = true
					
				item_name = item_name.replace(" Male", "").replace(" Female", "")
				var texture_path = UNDERWEAR_PATH + file_name
				
				if ResourceLoader.exists(texture_path):
					underwear_options.append({
						"name": item_name,
						"texture": texture_path,
						"sex": sex
					})
			
			file_name = dir.get_next()
		
		# Add defaults if needed
		if !has_male or !has_female:
			for item in defaults:
				if (item.sex == 0 and !has_male) or (item.sex == 1 and !has_female):
					underwear_options.append(item)
					if item.sex == 0:
						has_male = true
					elif item.sex == 1:
						has_female = true
		
		# Emergency defaults
		if !has_male:
			underwear_options.append({
				"name": "White Briefs",
				"texture": "res://Assets/Human/UnderWear/Trunks.png",
				"sex": 0
			})
		
		if !has_female:
			underwear_options.append({
				"name": "White Panties",
				"texture": "res://Assets/Human/UnderWear/Panties.png",
				"sex": 1
			})

func _scan_undershirts():
	var dir = DirAccess.open(UNDERSHIRT_PATH)
	if dir:
		var has_female_top = false
		var defaults = []
		
		for item in undershirt_options:
			if item.sex == 1 and item.texture != null:
				has_female_top = true
			defaults.append(item)
		
		undershirt_options.clear()
		undershirt_options.append({"name": "None", "texture": null, "sex": 0})
		
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if !dir.current_is_dir() and file_name.ends_with(".png") and !file_name.begins_with("."):
				var item_name = file_name.get_basename()
				item_name = item_name.replace("_", " ").capitalize()
				
				var sex = -1
				if file_name.to_lower().contains("_male"):
					sex = 0
				elif file_name.to_lower().contains("_female") or file_name.to_lower().contains("bra"):
					sex = 1
					has_female_top = true
					
				item_name = item_name.replace(" Male", "").replace(" Female", "")
				var texture_path = UNDERSHIRT_PATH + file_name
				
				if ResourceLoader.exists(texture_path):
					undershirt_options.append({
						"name": item_name,
						"texture": texture_path,
						"sex": sex
					})
			
			file_name = dir.get_next()
		
		# Add defaults if needed
		if !has_female_top:
			for item in defaults:
				if item.sex == 1 and item.texture != null:
					undershirt_options.append(item)
					has_female_top = true
					break
		
		# Emergency default
		if !has_female_top:
			undershirt_options.append({
				"name": "White Bra",
				"texture": "res://Assets/Human/UnderShirt/white_bra.png",
				"sex": 1
			})

func _scan_backgrounds():
	var dir = DirAccess.open(BACKGROUNDS_PATH)
	if dir:
		background_textures.clear()
		
		if ResourceLoader.exists("res://Assets/Backgrounds/Space.png"):
			background_textures.append({
				"name": "Space", 
				"texture": "res://Assets/Backgrounds/Space.png"
			})
		
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if !dir.current_is_dir() and (file_name.ends_with(".png") or file_name.ends_with(".jpg")) and !file_name.begins_with("."):
				var bg_name = file_name.get_basename()
				bg_name = bg_name.replace("_", " ").capitalize()
				
				var texture_path = BACKGROUNDS_PATH + file_name
				
				if ResourceLoader.exists(texture_path):
					var already_added = false
					for bg in background_textures:
						if bg.texture == texture_path:
							already_added = true
							break
							
					if not already_added:
						background_textures.append({
							"name": bg_name,
							"texture": texture_path
						})
			
			file_name = dir.get_next()

func _scan_occupations():
	var occupation_list = ["Engineer", "Security", "Medical", "Science", "Command", "Cargo"]
	
	for clothing in clothing_options:
		if clothing.name != "None":
			var occupation = clothing.name.replace("Uniform", "").strip_edges()
			
			if not occupation in occupation_list:
				occupation_list.append(occupation)
	
	occupations = occupation_list

func _load_config_file():
	if ResourceLoader.exists(ASSET_CONFIG_PATH):
		var file = FileAccess.open(ASSET_CONFIG_PATH, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			var json_result = JSON.parse_string(json_string)
			
			if json_result:
				if json_result.has("races"):
					races = json_result.races
				if json_result.has("occupations"):
					occupations = json_result.occupations
				if json_result.has("hair_styles"):
					hair_styles = json_result.hair_styles
				if json_result.has("facial_hair_styles"):
					facial_hair_styles = json_result.facial_hair_styles
				if json_result.has("clothing_options"):
					clothing_options = json_result.clothing_options
				if json_result.has("underwear_options"):
					underwear_options = json_result.underwear_options
				if json_result.has("undershirt_options"):
					undershirt_options = json_result.undershirt_options
				if json_result.has("background_textures"):
					background_textures = json_result.background_textures

func _verify_assets():
	# Verify hair styles
	var valid_hair_styles = []
	for hair in hair_styles:
		if hair.texture == null or ResourceLoader.exists(hair.texture):
			valid_hair_styles.append(hair)
	hair_styles = valid_hair_styles
	
	# Verify facial hair styles
	var valid_facial_hair = []
	for style in facial_hair_styles:
		if style.texture == null or ResourceLoader.exists(style.texture):
			valid_facial_hair.append(style)
	facial_hair_styles = valid_facial_hair
	
	# Verify clothing options
	var valid_clothing = []
	for clothing in clothing_options:
		var all_valid = true
		
		for part in clothing.textures:
			var path = clothing.textures[part]
			if not ResourceLoader.exists(path):
				all_valid = false
		
		if all_valid or clothing.name == "None":
			valid_clothing.append(clothing)
	clothing_options = valid_clothing
	
	# Verify underwear options
	var valid_underwear = []
	for underwear in underwear_options:
		if underwear.texture == null or ResourceLoader.exists(underwear.texture):
			valid_underwear.append(underwear)
	underwear_options = valid_underwear
	
	# Verify undershirt options
	var valid_undershirts = []
	for shirt in undershirt_options:
		if shirt.texture == null or ResourceLoader.exists(shirt.texture):
			valid_undershirts.append(shirt)
	undershirt_options = valid_undershirts
	
	# Verify backgrounds
	var valid_backgrounds = []
	for bg in background_textures:
		if bg.texture == null or ResourceLoader.exists(bg.texture):
			valid_backgrounds.append(bg)
	background_textures = valid_backgrounds
	
	_ensure_minimal_options()

func _ensure_minimal_options():
	# Ensure minimum options exist
	if races.size() == 0:
		races.append("Human")
	
	if hair_styles.size() == 0 or hair_styles[0].name != "None":
		hair_styles.insert(0, {"name": "None", "texture": null, "sex": -1})
	
	if facial_hair_styles.size() == 0 or facial_hair_styles[0].name != "None":
		facial_hair_styles.insert(0, {"name": "None", "texture": null, "sex": 0})
	
	if clothing_options.size() == 0 or clothing_options[0].name != "None":
		clothing_options.insert(0, {"name": "None", "textures": {}, "sex": -1})
	
	# Ensure underwear for both sexes
	var has_male = false
	var has_female = false
	
	for item in underwear_options:
		if item.sex == 0:
			has_male = true
		elif item.sex == 1:
			has_female = true
	
	if !has_male:
		underwear_options.append({
			"name": "White Briefs", 
			"texture": "res://Assets/Human/UnderWear/Trunks.png", 
			"sex": 0
		})
	
	if !has_female:
		underwear_options.append({
			"name": "White Panties", 
			"texture": "res://Assets/Human/UnderWear/Panties.png", 
			"sex": 1
		})
	
	# Ensure undershirts
	var has_none_top = false
	var has_female_top = false
	
	for item in undershirt_options:
		if item.name == "None" and item.sex == 0:
			has_none_top = true
		if item.sex == 1 and item.texture != null:
			has_female_top = true
	
	if !has_none_top:
		undershirt_options.insert(0, {"name": "None", "texture": null, "sex": 0})
	
	if !has_female_top:
		undershirt_options.append({
			"name": "White Bra", 
			"texture": "res://Assets/Human/UnderShirt/white_bra.png", 
			"sex": 1
		})
	
	if background_textures.size() == 0:
		background_textures.append({
			"name": "Space", 
			"texture": "res://Assets/Backgrounds/Space.png"
		})

# Get race sprites for character
func get_race_sprites(race_index: int, sex: int = 0) -> Dictionary:
	if race_index < 0 or race_index >= races.size():
		race_index = 0
	
	var race_name = races[race_index]
	var sprite_paths = {}
	var sex_suffix = "_Female" if sex == 1 else ""
	
	var race_path = "res://Assets/Human/"
	if race_name != "Human":
		race_path = "res://Assets/Human/" + race_name + "/"
	
	var body_parts = {
		"body": "Body", "head": "Head", "left_arm": "Left_arm", "right_arm": "Right_arm", 
		"left_leg": "Left_leg", "right_leg": "Right_leg", "left_hand": "Left_hand",
		"right_hand": "Right_hand", "left_foot": "Left_foot", "right_foot": "Right_foot"
	}
	
	for sprite_key in body_parts:
		var part_name = body_parts[sprite_key]
		
		var paths_to_try = [
			race_path + part_name + sex_suffix + ".png",
			race_path + part_name + ".png",
			"res://Assets/Human/" + part_name + sex_suffix + ".png",
			"res://Assets/Human/" + part_name + ".png"
		]
		
		for path in paths_to_try:
			if ResourceLoader.exists(path):
				sprite_paths[sprite_key] = {"texture": path}
				break
	
	return sprite_paths

# Asset getters for specific sex
func get_hair_styles_for_sex(sex: int = 0) -> Array:
	var result = [{"name": "None", "texture": null, "sex": -1}]
	
	for style in hair_styles:
		if style.name == "None":
			continue
			
		if style.sex == sex or style.sex == -1:
			result.append(style)
	
	if result.size() <= 1:
		return hair_styles
		
	return result

func get_facial_hair_for_sex(sex: int = 0) -> Array:
	var result = [{"name": "None", "texture": null, "sex": 0}]
	
	if sex == 0:
		for style in facial_hair_styles:
			if style.name == "None":
				continue
			result.append(style)
	
	return result

func get_clothing_for_sex(sex: int = 0) -> Array:
	var result = [{"name": "None", "textures": {}, "sex": -1}]
	
	for clothing in clothing_options:
		if clothing.name == "None":
			continue
			
		if clothing.sex == sex or clothing.sex == -1:
			result.append(clothing)
	
	if result.size() <= 1:
		return clothing_options
		
	return result

func get_underwear_for_sex(sex: int = 0) -> Array:
	var result = []
	
	for item in underwear_options:
		if item.sex == sex or item.sex == -1:
			result.append(item)
	
	if result.size() == 0:
		if sex == 0:
			result.append({
				"name": "White Briefs", 
				"texture": "res://Assets/Human/UnderWear/Trunks.png", 
				"sex": 0
			})
		else:
			result.append({
				"name": "White Panties", 
				"texture": "res://Assets/Human/UnderWear/Panties.png", 
				"sex": 1
			})
	
	return result

func get_undershirts_for_sex(sex: int = 0) -> Array:
	var result = []
	
	if sex == 0:
		result.append({"name": "None", "texture": null, "sex": 0})
	
	for item in undershirt_options:
		if item.name == "None" and sex == 1:
			continue
			
		if item.sex == sex or item.sex == -1:
			result.append(item)
	
	if sex == 1 and result.size() == 0:
		result.append({
			"name": "White Bra", 
			"texture": "res://Assets/Human/UnderShirt/white_bra.png", 
			"sex": 1
		})
	
	return result

# Config management
func save_config():
	var config = {
		"races": races, "occupations": occupations, "hair_styles": hair_styles,
		"facial_hair_styles": facial_hair_styles, "clothing_options": clothing_options,
		"underwear_options": underwear_options, "undershirt_options": undershirt_options,
		"background_textures": background_textures
	}
	
	var directory = DirAccess.open("res://")
	if not directory.dir_exists("res://Config"):
		directory.make_dir("Config")
	
	var file = FileAccess.open(ASSET_CONFIG_PATH, FileAccess.WRITE)
	if file:
		file.store_line(JSON.stringify(config, "  "))

# Asset management functions
func add_hair_style(name: String, texture_path: String, sex: int = -1) -> void:
	hair_styles.append({"name": name, "texture": texture_path, "sex": sex})
	save_config()

func add_facial_hair_style(name: String, texture_path: String) -> void:
	facial_hair_styles.append({"name": name, "texture": texture_path, "sex": 0})
	save_config()

func add_clothing_option(name: String, textures: Dictionary, sex: int = -1) -> void:
	clothing_options.append({"name": name, "textures": textures, "sex": sex})
	save_config()

func add_underwear_option(name: String, texture_path: String, sex: int = -1) -> void:
	underwear_options.append({"name": name, "texture": texture_path, "sex": sex})
	save_config()

func add_undershirt_option(name: String, texture_path: String, sex: int = -1) -> void:
	undershirt_options.append({"name": name, "texture": texture_path, "sex": sex})
	save_config()

func add_race(name: String) -> void:
	races.append(name)
	save_config()

func add_occupation(name: String) -> void:
	occupations.append(name)
	save_config()

func add_background(name: String, texture_path: String) -> void:
	background_textures.append({"name": name, "texture": texture_path})
	save_config()

func refresh_assets() -> void:
	_scan_directories()
	_verify_assets()
	save_config()
