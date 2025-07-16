extends Control

# Reference to the asset manager singleton
@onready var asset_manager = get_node("/root/CharacterAssetManager")

# Paths to look for the UpdatedHumanSpriteSystem script
var sprite_system_script_paths = [
	"res://Code/Mobs/Systems/human_sprite_system.gd"
]

# Paths to look for the UpdatedHumanSpriteSystem scene
var sprite_system_scene_paths = [
	"res://Scenes/Sprites/human_sprite_system.tscn"
]

# Character attributes
var character_data = {
	"name": "John Doe",
	"age": 30,
	"race": 0,  # Index of race in dropdown
	"sex": 0,   # 0 = Male, 1 = Female
	"hair_style": 0,
	"hair_color": Color(0.337255, 0.211765, 0.117647),
	"facial_hair": 0,
	"facial_hair_color": Color(0.337255, 0.211765, 0.117647),
	"occupation": 0,
	"clothing": 0,
	"underwear": 0,  # Index of underwear option
	"undershirt": 0,  # Index of undershirt option
	"background_text": "",
	"medical_text": "",
	"preview_background": 0
}

# Character preview components
var preview_sprites = {}

# Current available options (filtered by sex)
var available_hair_styles = []
var available_facial_hair = []
var available_clothing = []
var available_underwear = []
var available_undershirts = []

# Hair materials for coloring
var hair_material = null
var facial_hair_material = null

# Preview direction/rotation
enum Direction {SOUTH, NORTH, EAST, WEST}
var preview_direction = Direction.SOUTH
var direction_names = ["South", "North", "East", "West"]

func _ready():
	# Load assets dynamically
	_load_assets()
	
	# Setup UI elements
	_setup_ui()
	
	# Fix preview lighting
	_fix_preview_lighting()
	
	# Initialize character preview
	_initialize_character_preview()
	
	# Update preview with default values
	_update_character_preview()
	
	# Update direction label
	_update_direction_label()

func _update_character_preview():
	print("Character Creation: Updating preview with settings:", 
		  "Sex:", character_data.sex, 
		  "Race:", character_data.race, 
		  "Hair:", character_data.hair_style, 
		  "Facial hair:", character_data.facial_hair)
	
	if !preview_sprites.has("sprite_system") or !preview_sprites["sprite_system"]:
		print("ERROR: Sprite system not initialized!")
		return
	
	var sprite_system = preview_sprites["sprite_system"]
	
	# Set sex (must be first as it affects other sprites)
	if sprite_system.has_method("set_sex"):
		sprite_system.set_sex(character_data.sex)
		print("Character Creation: Set sprite system sex to", character_data.sex)
	
	# Set race (must be done after sex but before other attributes)
	if sprite_system.has_method("set_race"):
		sprite_system.set_race(character_data.race)
		print("Character Creation: Set sprite system race to", character_data.race)
	
	# Set underwear (mandatory, always should be set)
	if sprite_system.has_method("set_underwear"):
		if character_data.underwear < available_underwear.size():
			var underwear_texture = available_underwear[character_data.underwear].texture
			if underwear_texture and ResourceLoader.exists(underwear_texture):
				sprite_system.set_underwear(underwear_texture)
				print("Character Creation: Set underwear:", available_underwear[character_data.underwear].name)
	
	# Set undershirt (mandatory for females, optional for males)
	if sprite_system.has_method("set_undershirt"):
		if character_data.undershirt < available_undershirts.size():
			var undershirt_texture = available_undershirts[character_data.undershirt].texture
			if undershirt_texture and ResourceLoader.exists(undershirt_texture):
				sprite_system.set_undershirt(undershirt_texture)
				print("Character Creation: Set undershirt:", available_undershirts[character_data.undershirt].name)
			else:
				sprite_system.set_undershirt("")  # Clear undershirt if none
				print("Character Creation: Cleared undershirt (None)")
	
		# Set hair style and color
	if sprite_system.has_method("set_hair") and character_data.hair_style < available_hair_styles.size():
		var hair_texture_path = available_hair_styles[character_data.hair_style].texture
		if hair_texture_path and ResourceLoader.exists(hair_texture_path):
			sprite_system.set_hair(hair_texture_path, character_data.hair_color)
			print("Character Creation: Set hair style:", available_hair_styles[character_data.hair_style].name)
		else:
			sprite_system.set_hair("", character_data.hair_color)  # Clear hair if "None"
			print("Character Creation: Cleared hair (None)")
	
	# Set facial hair style and color (only for male characters)
	if sprite_system.has_method("set_facial_hair") and character_data.sex == 0:
		if character_data.facial_hair < available_facial_hair.size():
			var facial_hair_texture_path = available_facial_hair[character_data.facial_hair].texture
			if facial_hair_texture_path and ResourceLoader.exists(facial_hair_texture_path):
				sprite_system.set_facial_hair(facial_hair_texture_path, character_data.facial_hair_color)
				print("Character Creation: Set facial hair style:", available_facial_hair[character_data.facial_hair].name)
			else:
				sprite_system.set_facial_hair("", character_data.facial_hair_color)  # Clear facial hair if "None"
				print("Character Creation: Cleared facial hair (None)")
	
	# Set clothing
	if sprite_system.has_method("set_clothing") and character_data.clothing < available_clothing.size():
		var clothing = available_clothing[character_data.clothing]
		sprite_system.set_clothing(clothing.textures)
		print("Character Creation: Set clothing:", clothing.name)
	
	# Update sprite direction to match current preview direction
	if sprite_system.has_method("set_direction"):
		# Convert from preview_direction to sprite system direction
		sprite_system.set_direction(preview_direction)
		print("Character Creation: Set sprite direction to", Direction.keys()[preview_direction])
	
	# Apply race-specific appearance (modulate instead of materials)
	if sprite_system.limb_sprites:
		match character_data.race:
			0:  # Human
				# Standard human appearance
				for sprite in sprite_system.limb_sprites.values():
					sprite.modulate = Color(1, 1, 1, 1)
			1:  # Synthetic or other race
				# Check race name to apply appropriate appearance
				var race_name = asset_manager.races[character_data.race]
				if race_name == "Synthetic":
					# Synthetic appearance (metallic or plastic-like)
					for sprite in sprite_system.limb_sprites.values():
						sprite.modulate = Color(0.8, 0.8, 0.9, 1)
				else:
					# Default appearance for other races
					for sprite in sprite_system.limb_sprites.values():
						sprite.modulate = Color(1, 1, 1, 1)
	
	print("Character Creation: Preview update complete")

func _initialize_character_preview():
	print("Character Creation: Initializing character preview with UpdatedHumanSpriteSystem")
	var preview_node = %CharacterPreview
	
	# Clear any existing children
	for child in preview_node.get_children():
		child.queue_free()
	
	# Make sure the preview node is properly lit
	preview_node.modulate = Color(1, 1, 1, 1)
	
	# Create the updated sprite system
	var sprite_system = null
	
	# First check if we can load the sprite system scene
	var scene_path = find_sprite_system_scene()
	if scene_path:
		sprite_system = ResourceLoader.load(scene_path).instantiate()
		print("Character Creation: Loaded UpdatedHumanSpriteSystem scene from: " + scene_path)
	else:
		# Try to create from script
		var script_path = find_sprite_system_script()
		if script_path:
			sprite_system = Node2D.new()
			sprite_system.set_script(load(script_path))
			sprite_system.name = "HumanSpriteSystem"
			print("Character Creation: Created UpdatedHumanSpriteSystem from script: " + script_path)
		else:
			# Fallback to original preview method
			print("Character Creation: Could not find UpdatedHumanSpriteSystem, using legacy preview system")
			_initialize_legacy_character_preview()
			return
	
	# Add the sprite system to the preview
	preview_node.add_child(sprite_system)
	
	# Store a reference for easier access
	preview_sprites["sprite_system"] = sprite_system
	
	# Initialize the sprite system with the preview node as the 'Entity'
	if sprite_system.has_method("initialize"):
		sprite_system.initialize(preview_node)
		print("Character Creation: Initialized sprite system with preview node")
	
	print("Character Creation: Character preview initialization complete")

func _initialize_legacy_character_preview():
	print("Character Creation: Using legacy preview system")
	var preview_node = %CharacterPreview
	
	# Create basic sprites
	var sprite_data = {
		"body": {"path": "res://Assets/Human/Body.png", "z_index": 0},
		"head": {"path": "res://Assets/Human/Head.png", "z_index": 1},
		"left_arm": {"path": "res://Assets/Human/Left_arm.png", "z_index": 1},
		"right_arm": {"path": "res://Assets/Human/Right_arm.png", "z_index": 1},
		"left_leg": {"path": "res://Assets/Human/Left_leg.png", "z_index": 1},
		"right_hand": {"path": "res://Assets/Human/Right_hand.png", "z_index": 1},
		"left_hand": {"path": "res://Assets/Human/Left_hand.png", "z_index": 1},
		"right_leg": {"path": "res://Assets/Human/Right_leg.png", "z_index": 1},
		"left_foot": {"path": "res://Assets/Human/Left_foot.png", "z_index": 1},
		"right_foot": {"path": "res://Assets/Human/Right_foot.png", "z_index": 1},
		"underwear": {"path": null, "z_index": 2},  # Added underwear
		"undershirt": {"path": null, "z_index": 2}, # Added undershirt
		"hair": {"path": null, "z_index": 3},
		"facial_hair": {"path": null, "z_index": 3},
		"body_clothing": {"path": null, "z_index": 4},
		"legs_clothing": {"path": null, "z_index": 4}
	}
	
	# Check asset manager existence
	if not asset_manager:
		push_error("Asset manager not found - character preview will be incomplete")
	else:
		# Try to get race and sex specific sprites
		var race_sprites = asset_manager.get_race_sprites(character_data.race, character_data.sex)
		if !race_sprites.is_empty():
			# Override default sprites with race/sex-specific ones
			for key in race_sprites:
				if sprite_data.has(key):
					sprite_data[key].path = race_sprites[key]
					
		# Set underwear
		if character_data.underwear < available_underwear.size():
			sprite_data.underwear.path = available_underwear[character_data.underwear].texture
		
		# Set undershirt
		if character_data.undershirt < available_undershirts.size():
			sprite_data.undershirt.path = available_undershirts[character_data.undershirt].texture
		
	# Create and setup each sprite
	for key in sprite_data:
		var sprite = Sprite2D.new()
		sprite.centered = true
		sprite.z_index = sprite_data[key].z_index
		
		# Add region for animation frames
		sprite.region_enabled = true
		sprite.region_rect = Rect2(0, 0, 32, 32)  # Assuming 32x32 sprites
		
		# Try to load texture if it exists
		if sprite_data[key].path:
			if ResourceLoader.exists(sprite_data[key].path):
				sprite.texture = load(sprite_data[key].path)
		
		preview_node.add_child(sprite)
		preview_sprites[key] = sprite
		
	# Update sprite frames for current direction
	_update_sprite_frames()

# Update the preview background
func _update_preview_background():
	var bg_texture = %PreviewBackground
	var bg_data = asset_manager.background_textures[character_data.preview_background]
	
	# Ensure the background is properly lit
	bg_texture.modulate = Color(1, 1, 1, 1)
	
	if bg_data.texture and ResourceLoader.exists(bg_data.texture):
		bg_texture.texture = load(bg_data.texture)
	else:
		# Set a default solid color as fallback - use a lighter color
		bg_texture.texture = null
		bg_texture.modulate = Color(0.3, 0.3, 0.4, 1)

# Load all assets required for character creation from the asset manager
func _load_assets():
	# Add resource preloading to ensure critical assets are available
	_preload_critical_assets()
	
	# Get sex-specific assets
	available_hair_styles = asset_manager.get_hair_styles_for_sex(character_data.sex)
	available_facial_hair = asset_manager.get_facial_hair_for_sex(character_data.sex)
	available_clothing = asset_manager.get_clothing_for_sex(character_data.sex)
	available_underwear = asset_manager.get_underwear_for_sex(character_data.sex)
	available_undershirts = asset_manager.get_undershirts_for_sex(character_data.sex)

# Preload critical assets for character creation
func _preload_critical_assets():
	print("Character Creation: Preloading critical assets")
	
	# Ensure asset manager is loaded
	if not asset_manager:
		push_error("Asset manager not found")
		return

# Setup UI elements with values
func _setup_ui():
	# Setup race dropdown
	var race_option = %RaceOption
	race_option.clear()
	for race in asset_manager.races:
		race_option.add_item(race)
	race_option.select(character_data.race)
	
	# Setup sex dropdown
	var sex_option = %SexOption
	sex_option.clear()
	sex_option.add_item("Male")
	sex_option.add_item("Female")
	sex_option.select(character_data.sex)
	
	# Setup occupation dropdown
	var occupation_option = %OccupationOption
	occupation_option.clear()
	for occupation in asset_manager.occupations:
		occupation_option.add_item(occupation)
	occupation_option.select(character_data.occupation)
	
	# Set default values
	%NameInput.text = character_data.name
	%AgeSpinBox.value = character_data.age
	
	# Hair style - ensure index is valid for available styles
	if character_data.hair_style >= available_hair_styles.size():
		character_data.hair_style = 0
	%HairLabel.text = available_hair_styles[character_data.hair_style].name
	
	%HairColorPicker.color = character_data.hair_color
	
	# Facial hair - only for males
	if character_data.sex == 0:
		if character_data.facial_hair >= available_facial_hair.size():
			character_data.facial_hair = 0
		%FacialHairLabel.text = available_facial_hair[character_data.facial_hair].name
	else:
		character_data.facial_hair = 0
		%FacialHairLabel.text = "None"
	
	%FacialHairColorPicker.color = character_data.facial_hair_color
	
	# Clothing - ensure index is valid for available clothing
	if character_data.clothing >= available_clothing.size():
		character_data.clothing = 0
	%ClothingLabel.text = available_clothing[character_data.clothing].name
	
	# Underwear - ensure index is valid
	if character_data.underwear >= available_underwear.size():
		character_data.underwear = 0
	%UnderwearLabel.text = available_underwear[character_data.underwear].name
	
	# Undershirt - ensure index is valid
	if character_data.undershirt >= available_undershirts.size():
		character_data.undershirt = 0
	%UndershirtLabel.text = available_undershirts[character_data.undershirt].name
	
	%BackgroundLabel.text = asset_manager.background_textures[character_data.preview_background].name
	
	# Update character info label
	_update_info_label()
	
	# Set preview background
	_update_preview_background()

# Update sprite frames based on current direction
func _update_sprite_frames():
	# Skip if we're using the UpdatedHumanSpriteSystem
	if preview_sprites.has("sprite_system"):
		return
		
	# Legacy frame update logic
	for key in preview_sprites:
		var sprite = preview_sprites[key]
		if sprite and sprite.texture and sprite.region_enabled:
			# Calculate frame position in sprite sheet based on current direction
			var frame_x = preview_direction * 32  # assuming 32x32 frames
			
			# Update region rect to show correct direction
			sprite.region_rect = Rect2(frame_x, 0, 32, 32)

# Update the direction label
func _update_direction_label():
	if preview_sprites.has("sprite_system") and preview_sprites["sprite_system"]:
		var sprite_system = preview_sprites["sprite_system"]
		# Get the current direction from the sprite system
		if sprite_system.has_method("get_direction_name"):
			%DirectionLabel.text = sprite_system.get_direction_name()
		else:
			# Fallback to local direction
			%DirectionLabel.text = direction_names[preview_direction]
	else:
		# Use local direction names
		%DirectionLabel.text = direction_names[preview_direction]

# Update the information label in the preview panel
func _update_info_label():
	var info_text = "Name: %s\nAge: %s\nRace: %s\nOccupation: %s" % [
		character_data.name,
		character_data.age,
		asset_manager.races[character_data.race],
		asset_manager.occupations[character_data.occupation]
	]
	
	%CharacterInfo.text = info_text

# Fix preview lighting
func _fix_preview_lighting():
	# Fix the main background color to be less dark
	if has_node("BackgroundColor"):
		var bg_color = get_node("BackgroundColor")
		bg_color.color = Color(0.15, 0.17, 0.20, 0.7)  # Lighter and more transparent
	
	# Ensure the preview container is properly lit
	var preview_container = %PreviewBackground.get_parent()
	if preview_container:
		preview_container.modulate = Color(1, 1, 1, 1)
	
	# Make sure the character preview is properly lit
	%CharacterPreview.modulate = Color(1, 1, 1, 1)
	%PreviewBackground.modulate = Color(1, 1, 1, 1)

# Create and return a character data dictionary
func get_character_data():
	# Create a complete character data structure
	var data = character_data.duplicate()
	
	print("Preparing character data to save:")
	
	# Convert indexes to actual values
	data.race_name = asset_manager.races[data.race]
	data.occupation_name = asset_manager.occupations[data.occupation]
	data.sex_name = "Male" if data.sex == 0 else "Female"
	
	print("Basic data: Name: ", data.name, " Race: ", data.race_name, " Sex: ", data.sex_name)
	
	# Store actual texture paths for hair, facial hair, and clothing
	# HAIR STYLE
	if data.hair_style < available_hair_styles.size():
		data.hair_texture = available_hair_styles[data.hair_style].texture
		data.hair_style_name = available_hair_styles[data.hair_style].name
		
		# Verify the texture path exists
		if data.hair_texture and ResourceLoader.exists(data.hair_texture):
			print("Hair texture valid: ", data.hair_texture)
		else:
			print("WARNING: Hair texture doesn't exist: ", data.hair_texture)
	else:
		data.hair_texture = null
		data.hair_style_name = "None"
		print("No hair style selected")
	
	# FACIAL HAIR
	if data.sex == 0 and data.facial_hair < available_facial_hair.size():
		data.facial_hair_texture = available_facial_hair[data.facial_hair].texture
		data.facial_hair_name = available_facial_hair[data.facial_hair].name
		
		# Verify the texture path exists
		if data.facial_hair_texture and ResourceLoader.exists(data.facial_hair_texture):
			print("Facial hair texture valid: ", data.facial_hair_texture)
		else:
			print("WARNING: Facial hair texture doesn't exist: ", data.facial_hair_texture)
	else:
		data.facial_hair_texture = null
		data.facial_hair_name = "None"
		print("No facial hair style selected")
	
	# CLOTHING
	if data.clothing < available_clothing.size():
		data.clothing_textures = available_clothing[data.clothing].textures.duplicate()
		data.clothing_name = available_clothing[data.clothing].name
		
		# Verify all texture paths exist
		for key in data.clothing_textures:
			var path = data.clothing_textures[key]
			if path and ResourceLoader.exists(path):
				print("Clothing texture valid - ", key, ": ", path)
			else:
				print("WARNING: Clothing texture doesn't exist - ", key, ": ", path)
	else:
		data.clothing_textures = {}
		data.clothing_name = "None"
		print("No clothing selected")
	
	# UNDERWEAR (always required)
	if data.underwear < available_underwear.size():
		data.underwear_texture = available_underwear[data.underwear].texture
		data.underwear_name = available_underwear[data.underwear].name
		
		# Verify the texture path exists
		if data.underwear_texture and ResourceLoader.exists(data.underwear_texture):
			print("Underwear texture valid: ", data.underwear_texture)
		else:
			print("WARNING: Underwear texture doesn't exist: ", data.underwear_texture)
	else:
		# Should never happen - use first available underwear for this sex
		var default_underwear = asset_manager.get_underwear_for_sex(data.sex)[0]
		data.underwear_texture = default_underwear.texture
		data.underwear_name = default_underwear.name
		print("Using default underwear: ", data.underwear_name)
	
	# UNDERSHIRT (required for females, optional for males)
	if data.undershirt < available_undershirts.size():
		data.undershirt_texture = available_undershirts[data.undershirt].texture
		data.undershirt_name = available_undershirts[data.undershirt].name
		
		# Verify the texture path exists
		if data.undershirt_texture and ResourceLoader.exists(data.undershirt_texture):
			print("Undershirt texture valid: ", data.undershirt_texture)
		elif data.undershirt_texture != null:
			print("WARNING: Undershirt texture doesn't exist: ", data.undershirt_texture)
	else:
		# For females, use a default. For males, it can be null
		if data.sex == 1:
			var default_tops = asset_manager.get_undershirts_for_sex(1)
			if default_tops.size() > 0:
				data.undershirt_texture = default_tops[0].texture
				data.undershirt_name = default_tops[0].name
				print("Using default female top: ", data.undershirt_name)
		else:
			data.undershirt_texture = null
			data.undershirt_name = "None"
			print("No undershirt selected for male")
	
	print("Character data preparation complete!")
	return data

# Find the sprite system script
func find_sprite_system_script():
	for path in sprite_system_script_paths:
		if ResourceLoader.exists(path):
			print("Found sprite system script at: " + path)
			return path
	
	print("WARNING: Could not find UpdatedHumanSpriteSystem script!")
	return ""

# Function to find the sprite system scene
func find_sprite_system_scene():
	for path in sprite_system_scene_paths:
		if ResourceLoader.exists(path):
			print("Found sprite system scene at: " + path)
			return path
	
	print("WARNING: Could not find UpdatedHumanSpriteSystem scene!")
	return ""

# SIGNAL HANDLERS

func _on_name_input_text_changed(new_text):
	character_data.name = new_text
	_update_info_label()

func _on_age_spin_box_value_changed(value):
	character_data.age = value
	_update_info_label()

func _on_race_option_item_selected(index):
	character_data.race = index
	_update_character_preview()
	_update_info_label()

func _on_sex_option_item_selected(index):
	character_data.sex = index
	
	# Update sex-specific assets
	available_hair_styles = asset_manager.get_hair_styles_for_sex(index)
	available_facial_hair = asset_manager.get_facial_hair_for_sex(index)
	available_clothing = asset_manager.get_clothing_for_sex(index)
	available_underwear = asset_manager.get_underwear_for_sex(index)
	available_undershirts = asset_manager.get_undershirts_for_sex(index)
	
	# Reset all to valid indexes for this sex
	character_data.hair_style = 0
	character_data.facial_hair = 0
	character_data.clothing = 0
	character_data.underwear = 0
	character_data.undershirt = 0
	
	# For females, ensure they have a top (can't select "None")
	if index == 1 and available_undershirts.size() > 0:
		# Find first non-"None" option
		for i in range(available_undershirts.size()):
			if available_undershirts[i].name != "None":
				character_data.undershirt = i
				break
	
	# Update UI labels
	%HairLabel.text = available_hair_styles[character_data.hair_style].name
	%FacialHairLabel.text = available_facial_hair[character_data.facial_hair].name
	%ClothingLabel.text = available_clothing[character_data.clothing].name
	%UnderwearLabel.text = available_underwear[character_data.underwear].name
	%UndershirtLabel.text = available_undershirts[character_data.undershirt].name
	
	# Update name if it's still the default
	if character_data.name == "John Doe" and index == 1:
		character_data.name = "Jane Doe"
		%NameInput.text = character_data.name
		_update_info_label()
	elif character_data.name == "Jane Doe" and index == 0:
		character_data.name = "John Doe"
		%NameInput.text = character_data.name
		_update_info_label()
	
	_update_character_preview()

func _on_prev_hair_pressed():
	character_data.hair_style = (character_data.hair_style - 1) % available_hair_styles.size()
	if character_data.hair_style < 0:
		character_data.hair_style = available_hair_styles.size() - 1
	
	%HairLabel.text = available_hair_styles[character_data.hair_style].name
	_update_character_preview()

func _on_next_hair_pressed():
	character_data.hair_style = (character_data.hair_style + 1) % available_hair_styles.size()
	%HairLabel.text = available_hair_styles[character_data.hair_style].name
	_update_character_preview()

func _on_hair_color_picker_color_changed(color):
	character_data.hair_color = color
	
	# Update hair material
	hair_material.set_shader_parameter("hair_color", color)
	
	_update_character_preview()

func _on_prev_facial_hair_pressed():
	# Only cycle if character is male
	if character_data.sex == 0:
		character_data.facial_hair = (character_data.facial_hair - 1) % available_facial_hair.size()
		if character_data.facial_hair < 0:
			character_data.facial_hair = available_facial_hair.size() - 1
		
		%FacialHairLabel.text = available_facial_hair[character_data.facial_hair].name
		_update_character_preview()

func _on_next_facial_hair_pressed():
	# Only cycle if character is male
	if character_data.sex == 0:
		character_data.facial_hair = (character_data.facial_hair + 1) % available_facial_hair.size()
		%FacialHairLabel.text = available_facial_hair[character_data.facial_hair].name
		_update_character_preview()

func _on_facial_hair_color_picker_color_changed(color):
	character_data.facial_hair_color = color
	
	# Update facial hair material
	facial_hair_material.set_shader_parameter("hair_color", color)
	
	_update_character_preview()

func _on_occupation_option_item_selected(index):
	character_data.occupation = index
	_update_info_label()
	
	# Optionally, change clothing based on occupation
	var matching_clothing_idx = -1
	var occupation_name = asset_manager.occupations[index]
	
	# Find matching clothing if any
	for i in range(available_clothing.size()):
		if available_clothing[i].name.to_lower() == occupation_name.to_lower():
			matching_clothing_idx = i
			break
	
	# Set matching clothing if found
	if matching_clothing_idx != -1:
		character_data.clothing = matching_clothing_idx
		%ClothingLabel.text = available_clothing[matching_clothing_idx].name
		_update_character_preview()

func _on_prev_clothing_pressed():
	character_data.clothing = (character_data.clothing - 1) % available_clothing.size()
	if character_data.clothing < 0:
		character_data.clothing = available_clothing.size() - 1
	
	%ClothingLabel.text = available_clothing[character_data.clothing].name
	_update_character_preview()

func _on_next_clothing_pressed():
	character_data.clothing = (character_data.clothing + 1) % available_clothing.size()
	%ClothingLabel.text = available_clothing[character_data.clothing].name
	_update_character_preview()

func _on_prev_underwear_pressed():
	character_data.underwear = (character_data.underwear - 1) % available_underwear.size()
	if character_data.underwear < 0:
		character_data.underwear = available_underwear.size() - 1
	
	%UnderwearLabel.text = available_underwear[character_data.underwear].name
	_update_character_preview()

func _on_next_underwear_pressed():
	character_data.underwear = (character_data.underwear + 1) % available_underwear.size()
	%UnderwearLabel.text = available_underwear[character_data.underwear].name
	_update_character_preview()

func _on_prev_undershirt_pressed():
	# For females, skip the "None" option
	if character_data.sex == 1:
		var original_index = character_data.undershirt
		
		# Skip until we find a non-"None" option
		while true:
			character_data.undershirt = (character_data.undershirt - 1) % available_undershirts.size()
			if character_data.undershirt < 0:
				character_data.undershirt = available_undershirts.size() - 1
				
			# If we found a valid option or went full circle, break
			if available_undershirts[character_data.undershirt].name != "None" or character_data.undershirt == original_index:
				break
	else:
		# Males can have no top
		character_data.undershirt = (character_data.undershirt - 1) % available_undershirts.size()
		if character_data.undershirt < 0:
			character_data.undershirt = available_undershirts.size() - 1
	
	%UndershirtLabel.text = available_undershirts[character_data.undershirt].name
	_update_character_preview()

func _on_next_undershirt_pressed():
	# For females, skip the "None" option
	if character_data.sex == 1:
		var original_index = character_data.undershirt
		
		# Skip until we find a non-"None" option
		while true:
			character_data.undershirt = (character_data.undershirt + 1) % available_undershirts.size()
				
			# If we found a valid option or went full circle, break
			if available_undershirts[character_data.undershirt].name != "None" or character_data.undershirt == original_index:
				break
	else:
		# Males can have no top
		character_data.undershirt = (character_data.undershirt + 1) % available_undershirts.size()
	
	%UndershirtLabel.text = available_undershirts[character_data.undershirt].name
	_update_character_preview()

func _on_background_text_text_changed():
	character_data.background_text = %BackgroundText.text

func _on_medical_text_text_changed():
	character_data.medical_text = %MedicalText.text

func _on_prev_background_pressed():
	character_data.preview_background = (character_data.preview_background - 1) % asset_manager.background_textures.size()
	if character_data.preview_background < 0:
		character_data.preview_background = asset_manager.background_textures.size() - 1
	
	%BackgroundLabel.text = asset_manager.background_textures[character_data.preview_background].name
	_update_preview_background()

func _on_next_background_pressed():
	character_data.preview_background = (character_data.preview_background + 1) % asset_manager.background_textures.size()
	%BackgroundLabel.text = asset_manager.background_textures[character_data.preview_background].name
	_update_preview_background()

func _on_randomize_button_pressed():
	# Randomize the character attributes
	randomize()
	
	# Randomize sex first since it affects other options
	character_data.sex = randi() % 2
	
	# Update available options based on sex
	available_hair_styles = asset_manager.get_hair_styles_for_sex(character_data.sex)
	available_facial_hair = asset_manager.get_facial_hair_for_sex(character_data.sex)
	available_clothing = asset_manager.get_clothing_for_sex(character_data.sex)
	available_underwear = asset_manager.get_underwear_for_sex(character_data.sex)
	available_undershirts = asset_manager.get_undershirts_for_sex(character_data.sex)
	
	character_data.name = _generate_random_name()
	character_data.age = randi() % 63 + 18  # 18-80
	character_data.race = randi() % asset_manager.races.size()
	character_data.hair_style = randi() % available_hair_styles.size()
	character_data.hair_color = Color(randf(), randf(), randf())
	
	# Only assign facial hair for male characters
	if character_data.sex == 0:
		character_data.facial_hair = randi() % available_facial_hair.size()
	else:
		character_data.facial_hair = 0
	
	character_data.facial_hair_color = character_data.hair_color
	character_data.occupation = randi() % asset_manager.occupations.size()
	character_data.clothing = randi() % available_clothing.size()
	character_data.underwear = randi() % available_underwear.size()
	
	# For females, ensure they have a top (can't select "None")
	if character_data.sex == 1:
		# Find valid tops (not "None")
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
	
	character_data.preview_background = randi() % asset_manager.background_textures.size()
	
	# Update UI
	_setup_ui()
	_update_character_preview()

func _generate_random_name() -> String:
	# More flexible random name generation
	var first_names_male = ["James", "John", "Robert", "Michael", "William", "David", "Richard", "Joseph", "Thomas", "Charles"]
	var first_names_female = ["Mary", "Patricia", "Jennifer", "Linda", "Elizabeth", "Barbara", "Susan", "Jessica", "Sarah", "Karen"]
	var last_names = ["Smith", "Johnson", "Williams", "Jones", "Brown", "Davis", "Miller", "Wilson", "Moore", "Taylor"]
	
	# Use the current character sex for name selection
	var first_names = first_names_male if character_data.sex == 0 else first_names_female
	var first_name = first_names[randi() % first_names.size()]
	var last_name = last_names[randi() % last_names.size()]
	
	return first_name + " " + last_name

func _on_rotate_left_button_pressed():
	if preview_sprites.has("sprite_system"):
		var sprite_system = preview_sprites["sprite_system"]
		if sprite_system.has_method("rotate_left"):
			sprite_system.rotate_left()
			preview_direction = sprite_system.current_direction
			_update_direction_label()
		else:
			# Fallback to old method if rotate_left isn't available
			preview_direction = (preview_direction - 1) % Direction.size()
			if preview_direction < 0:
				preview_direction = Direction.size() - 1
			_update_sprite_frames()
			_update_direction_label()

func _on_rotate_right_button_pressed():
	if preview_sprites.has("sprite_system"):
		var sprite_system = preview_sprites["sprite_system"]
		if sprite_system.has_method("rotate_right"):
			sprite_system.rotate_right()
			preview_direction = sprite_system.current_direction
			_update_direction_label()
		else:
			# Fallback to old method if rotate_right isn't available
			preview_direction = (preview_direction + 1) % Direction.size()
			_update_sprite_frames()
			_update_direction_label()

func _on_confirm_button_pressed():
	# Save the character data to be used in the game
	var complete_data = get_character_data()
	
	# Save to GameManager if available
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		print("Saving character data to GameManager")
		game_manager.set_character_data(complete_data)
		
		# Check if we're coming from multiplayer menu
		if game_manager.current_state == game_manager.GameState.NETWORK_SETUP:
			# Create fade-out transition to network UI
			var tween = create_tween()
			tween.tween_property(self, "modulate:a", 0.0, 0.3)
			tween.tween_callback(func():
				print("Character Creation: Going to network UI")
				game_manager.show_network_ui()
			)
		else:
			# Singleplayer path - go directly to game
			var next_scene = "res://Scenes/Maps/Zypharion.tscn"
			
			# Validate the scene path exists
			if ResourceLoader.exists(next_scene):
				# Create fade-out transition
				var tween = create_tween()
				tween.tween_property(self, "modulate:a", 0.0, 0.3)
				tween.tween_callback(func():
					print("Character Creation: Starting singleplayer game")
					# Load the world directly
					game_manager.load_world(next_scene)
					# Change state to PLAYING
					game_manager.change_state(game_manager.GameState.PLAYING)
				)
			else:
				print("ERROR: Scene path doesn't exist: ", next_scene)
				# Alert the user
				OS.alert("Scene path not found: " + next_scene, "Error")
				# Go back to main menu
				get_tree().change_scene_to_file("res://Scenes/UI/Menus/Main_menu.tscn")
	else:
		print("WARNING: GameManager not found, saving locally")
		var save_path = "user://character_data.json"
		var file = FileAccess.open(save_path, FileAccess.WRITE)
		if file:
			file.store_line(JSON.stringify(complete_data))
			file.close()
			print("Character data saved to: ", save_path)
		
		# Go back to main menu
		get_tree().change_scene_to_file("res://Scenes/UI/Menus/Main_menu.tscn")

func _on_cancel_button_pressed():
	# Get GameManager to determine where to go back to
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		# Create fade-out transition
		var tween = create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 0.3)
		tween.tween_callback(func():
			# Check where we came from based on the GameManager state
			if game_manager.current_state == game_manager.GameState.NETWORK_SETUP:
				# We came from network setup, go back to main menu
				game_manager.show_main_menu()
			else:
				# Default to main menu
				game_manager.show_main_menu()
		)
	else:
		# Fallback to direct scene change
		get_tree().change_scene_to_file("res://Scenes/UI/Menus/Main_menu.tscn")
