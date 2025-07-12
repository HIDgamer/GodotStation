extends Node

class_name CharacterCreationHelper

# Function to load a character from saved data
static func load_character(file_path: String = "user://character_data.json") -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {}
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		var json_result = JSON.parse_string(json_string)
		if json_result != null:
			return json_result
	
	return {}

# Function to save a character to a file
static func save_character(character_data: Dictionary, file_path: String = "user://character_data.json") -> bool:
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_line(JSON.stringify(character_data))
		return true
	
	return false

# Function to apply character appearance to an entity
static func apply_character_to_entity(entity, character_data: Dictionary) -> void:
	if entity.has_node("HumanSpriteSystem"):
		var sprite_system = entity.get_node("HumanSpriteSystem")
		
		# Apply sex-specific base sprites if the system supports it
		if sprite_system.has_method("set_sex") and character_data.has("sex"):
			sprite_system.set_sex(character_data.sex)
		
		# Apply race-specific sprites if the system supports it
		if sprite_system.has_method("set_race") and character_data.has("race"):
			sprite_system.set_race(character_data.race)
		
		# Apply hair using direct texture path if available
		if sprite_system.has_method("set_hair"):
			var hair_texture = null
			var hair_color = Color(1, 1, 1)
			
			if character_data.has("hair_texture") and character_data.hair_texture:
				hair_texture = character_data.hair_texture
			elif character_data.has("hair_style") and character_data.hair_style > 0:
				# Legacy: Try to get hair style from asset manager
				var asset_manager = Engine.get_singleton("CharacterAssetManager")
				if asset_manager:
					var hair_styles = asset_manager.get_hair_styles_for_sex(character_data.sex)
					if character_data.hair_style < hair_styles.size():
						hair_texture = hair_styles[character_data.hair_style].texture
			
			if character_data.has("hair_color"):
				hair_color = character_data.hair_color
				
			if hair_texture:
				sprite_system.set_hair(hair_texture, hair_color)
		
		# Apply facial hair if entity has a method for it and character is male
		if sprite_system.has_method("set_facial_hair"):
			var facial_hair_texture = null
			var facial_hair_color = Color(1, 1, 1)
			
			if character_data.sex == 0:  # Male only
				if character_data.has("facial_hair_texture") and character_data.facial_hair_texture:
					facial_hair_texture = character_data.facial_hair_texture
				elif character_data.has("facial_hair") and character_data.facial_hair > 0:
					# Legacy: Try to get facial hair style from asset manager
					var asset_manager = Engine.get_singleton("CharacterAssetManager")
					if asset_manager and character_data.facial_hair < asset_manager.facial_hair_styles.size():
						facial_hair_texture = asset_manager.facial_hair_styles[character_data.facial_hair].texture
				
				if character_data.has("facial_hair_color"):
					facial_hair_color = character_data.facial_hair_color
			
			if facial_hair_texture:
				sprite_system.set_facial_hair(facial_hair_texture, facial_hair_color)
			else:
				# Clear facial hair if none specified
				sprite_system.set_facial_hair(null, Color(0, 0, 0, 0))
		
		# Apply clothing using direct textures if available
		if sprite_system.has_method("set_clothing"):
			var clothing_textures = {}
			
			if character_data.has("clothing_textures") and !character_data.clothing_textures.is_empty():
				clothing_textures = character_data.clothing_textures
			elif character_data.has("clothing") and character_data.clothing > 0:
				# Legacy: Try to get clothing from asset manager
				var asset_manager = Engine.get_singleton("CharacterAssetManager")
				if asset_manager:
					var available_clothing = asset_manager.get_clothing_for_sex(character_data.sex)
					if character_data.clothing < available_clothing.size():
						clothing_textures = available_clothing[character_data.clothing].textures
			
			if !clothing_textures.is_empty():
				sprite_system.set_clothing(clothing_textures)
	
	# Set basic properties if entity has them
	if entity.has_method("set_name") and character_data.has("name"):
		entity.set_name(character_data.name)
	
	# If entity has a blood_type property, set it
	if entity.get("blood_type") != null and character_data.has("blood_type"):
		entity.blood_type = character_data.blood_type
	
	# If entity has an age property, set it
	if entity.get("age") != null and character_data.has("age"):
		entity.age = character_data.age
	
	# If entity has a sex property, set it
	if entity.get("sex") != null and character_data.has("sex"):
		entity.sex = character_data.sex

# Generate a random character data set
static func generate_random_character() -> Dictionary:
	randomize()
	
	var asset_manager = Engine.get_singleton("CharacterAssetManager")
	if not asset_manager:
		return {}
	
	# Generate random sex
	var sex = randi() % 2  # 0 = Male, 1 = Female
	
	# Get sex-specific options
	var available_hair_styles = asset_manager.get_hair_styles_for_sex(sex)
	var available_clothing = asset_manager.get_clothing_for_sex(sex)
	
	# Generate random name based on sex
	var first_names_male = ["James", "John", "Robert", "Michael", "William", "David", "Richard", "Joseph", "Thomas", "Charles"]
	var first_names_female = ["Mary", "Patricia", "Jennifer", "Linda", "Elizabeth", "Barbara", "Susan", "Jessica", "Sarah", "Karen"]
	var last_names = ["Smith", "Johnson", "Williams", "Jones", "Brown", "Davis", "Miller", "Wilson", "Moore", "Taylor"]
	
	var first_names = first_names_male if sex == 0 else first_names_female
	var first_name = first_names[randi() % first_names.size()]
	var last_name = last_names[randi() % last_names.size()]
	var name = first_name + " " + last_name
	
	# Generate random blood type
	var blood_types = ["O+", "O-", "A+", "A-", "B+", "B-", "AB+", "AB-"]
	var blood_type = blood_types[randi() % blood_types.size()]
	
	# Generate random age between 18 and 80
	var age = randi() % 63 + 18
	
	# Generate random race
	var race = randi() % asset_manager.races.size()
	
	# Generate random hair style and color
	var hair_style = randi() % available_hair_styles.size()
	var hair_color = Color(randf(), randf(), randf())
	
	# Generate random facial hair (only for males)
	var facial_hair = 0
	if sex == 0:  # Male
		facial_hair = randi() % asset_manager.facial_hair_styles.size()
	
	var facial_hair_color = hair_color  # Match facial hair to hair color
	
	# Generate random occupation
	var occupation = randi() % asset_manager.occupations.size()
	
	# Generate random clothing
	var clothing = randi() % available_clothing.size()
	
	# Prepare character data
	var character_data = {
		"name": name,
		"age": age,
		"blood_type": blood_type,
		"race": race,
		"race_name": asset_manager.races[race],
		"sex": sex,
		"sex_name": "Male" if sex == 0 else "Female",
		"hair_style": hair_style,
		"hair_color": hair_color,
		"facial_hair": facial_hair,
		"facial_hair_color": facial_hair_color,
		"occupation": occupation,
		"occupation_name": asset_manager.occupations[occupation],
		"clothing": clothing,
		"background_text": "",
		"medical_text": ""
	}
	
	# Add the actual texture paths for advanced usage
	if hair_style > 0 and hair_style < available_hair_styles.size():
		character_data.hair_texture = available_hair_styles[hair_style].texture
		character_data.hair_style_name = available_hair_styles[hair_style].name
	else:
		character_data.hair_texture = null
		character_data.hair_style_name = "None"
	
	if facial_hair > 0 and facial_hair < asset_manager.facial_hair_styles.size():
		character_data.facial_hair_texture = asset_manager.facial_hair_styles[facial_hair].texture
		character_data.facial_hair_name = asset_manager.facial_hair_styles[facial_hair].name
	else:
		character_data.facial_hair_texture = null
		character_data.facial_hair_name = "None"
	
	if clothing > 0 and clothing < available_clothing.size():
		character_data.clothing_textures = available_clothing[clothing].textures
		character_data.clothing_name = available_clothing[clothing].name
	else:
		character_data.clothing_textures = {}
		character_data.clothing_name = "None"
	
	return character_data
