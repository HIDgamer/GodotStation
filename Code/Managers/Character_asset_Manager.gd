extends Node

# Categories - Dynamic lists filled by scanning directories
var hair_styles = []
var facial_hair_styles = []
var clothing_options = []
var underwear_options = []
var undershirt_options = []
var background_textures = []
var races = []
var occupations = []
var normal_maps = {}
var specular_maps = {}

# Directory paths for asset scanning
const BASE_HUMAN_PATH = "res://Assets/Human/"
const HAIR_STYLES_PATH = "res://Assets/Human/Hair/"
const FACIAL_HAIR_PATH = "res://Assets/Human/FacialHair/"
const CLOTHING_PATH = "res://Assets/Human/Clothing/"
const UNDERWEAR_PATH = "res://Assets/Human/UnderWear/"
const UNDERSHIRT_PATH = "res://Assets/Human/UnderShirt/"
const BACKGROUNDS_PATH = "res://Assets/Backgrounds/"
const MAPS_PATH = "res://Assets/Human/Maps/"

# Constants for config file
const ASSET_CONFIG_PATH = "res://Config/character_assets.json"

# Cache loaded resources to avoid reloading the same assets
var _resource_cache = {}

func _init():
	print("CharacterAssetManager: Initializing...")
	
	# Load default values first (fallback)
	_load_defaults()
	
	# Always scan directories
	_scan_directories()
	
	# Scan for maps - add this new line
	_scan_maps()
	
	# Try to load from config file (will override scanned assets if file exists)
	_load_config_file()
	
	# Verify assets are loaded
	_verify_assets()
	
	# Preload essential assets into cache
	_preload_essential_assets()
	
	print("CharacterAssetManager: Initialization complete")
	print("CharacterAssetManager: Loaded", hair_styles.size(), "hair styles")
	print("CharacterAssetManager: Loaded", facial_hair_styles.size(), "facial hair styles")
	print("CharacterAssetManager: Loaded", clothing_options.size(), "clothing options")
	print("CharacterAssetManager: Loaded", underwear_options.size(), "underwear options")
	print("CharacterAssetManager: Loaded", undershirt_options.size(), "undershirt options")
	print("CharacterAssetManager: Loaded", background_textures.size(), "backgrounds")

# Load default values in case config file isn't available and no assets are found
func _load_defaults():
	print("CharacterAssetManager: Loading default values...")
	
	# Races - empty by default, will be populated by scanning
	races = []
	
	# Occupations - basic defaults that will be expanded by scanning
	occupations = ["Engineer", "Security", "Medical", "Science", "Command", "Cargo"]
	
	# These will be populated by directory scanning, but we'll keep defaults as fallback
	hair_styles = [
		{"name": "None", "texture": null, "normal_map": null, "specular_map": null, "sex": -1}  # -1 means works for all
	]
	
	facial_hair_styles = [
		{"name": "None", "texture": null, "normal_map": null, "specular_map": null, "sex": 0}  # 0 means male-only
	]
	
	clothing_options = [
		{"name": "None", "textures": {}, "normal_maps": {}, "specular_maps": {}, "sex": -1}
	]
	
	underwear_options = [
		{"name": "White Briefs", "texture": "res://Assets/Human/UnderWear/white_briefs.png", "normal_map": null, "specular_map": null, "sex": 0},
		{"name": "White Panties", "texture": "res://Assets/Human/UnderWear/white_panties.png", "normal_map": null, "specular_map": null, "sex": 1}
	]
	
	undershirt_options = [
		{"name": "None", "texture": null, "normal_map": null, "specular_map": null, "sex": 0},  # Males can have no top
		{"name": "White Bra", "texture": "res://Assets/Human/UnderShirt/white_bra.png", "normal_map": null, "specular_map": null, "sex": 1},
		{"name": "White Undershirt", "texture": "res://Assets/Human/UnderShirt/white_shirt.png", "normal_map": null, "specular_map": null, "sex": -1}
	]
	
	background_textures = [
		{"name": "Space", "texture": "res://Assets/Backgrounds/Space.png"}
	]

func _scan_maps():
	print("CharacterAssetManager: Scanning for normal and specular maps")
	
	var dir = DirAccess.open(MAPS_PATH)
	if not dir:
		print("CharacterAssetManager: Maps directory doesn't exist:", MAPS_PATH)
		return
		
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	var normal_maps = {}
	var specular_maps = {}
	
	while file_name != "":
		if !dir.current_is_dir() and file_name.ends_with(".png"):
			var map_path = MAPS_PATH + file_name
			
			# Check if this is a normal map (_n)
			if file_name.ends_with("_n.png"):
				var base_name = file_name.substr(0, file_name.length() - 6)  # Remove _n.png
				normal_maps[base_name] = map_path
				print("CharacterAssetManager: Found normal map for:", base_name)
			
			# Check if this is a specular map (_s)
			elif file_name.ends_with("_s.png"):
				var base_name = file_name.substr(0, file_name.length() - 6)  # Remove _s.png
				specular_maps[base_name] = map_path
				print("CharacterAssetManager: Found specular map for:", base_name)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	
	# Store maps in global variables for later use
	self.normal_maps = normal_maps
	self.specular_maps = specular_maps
	
	print("CharacterAssetManager: Found", normal_maps.size(), "normal maps and", specular_maps.size(), "specular maps")

# Preload essential assets for performance
func _preload_essential_assets():
	print("CharacterAssetManager: Preloading essential assets...")
	
	# Create a list of essential directories to scan for base body parts
	var essential_dirs = [
		"res://Assets/Human/",
	]
	
	# Scan all base race directories for body parts
	for race in races:
		var race_dir = BASE_HUMAN_PATH + race + "/"
		if DirAccess.dir_exists_absolute(race_dir):
			essential_dirs.append(race_dir)
	
	# Look for body parts in all essential directories
	for dir_path in essential_dirs:
		_preload_directory(dir_path)
	
	# Also preload mandatory items (underwear/undershirts)
	for item in underwear_options:
		if item.texture and ResourceLoader.exists(item.texture):
			_resource_cache[item.texture] = load(item.texture)
			print("CharacterAssetManager: Preloaded underwear:", item.texture)
	
	for item in undershirt_options:
		if item.texture and ResourceLoader.exists(item.texture):
			_resource_cache[item.texture] = load(item.texture)
			print("CharacterAssetManager: Preloaded undershirt:", item.texture)

# Preload all assets in a directory
func _preload_directory(dir_path):
	if not DirAccess.dir_exists_absolute(dir_path):
		print("CharacterAssetManager: Directory doesn't exist:", dir_path)
		return
		
	var dir = DirAccess.open(dir_path)
	if not dir:
		print("CharacterAssetManager: Cannot open directory:", dir_path)
		return
		
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".png"):
			var full_path = dir_path.path_join(file_name)
			if ResourceLoader.exists(full_path):
				_resource_cache[full_path] = load(full_path)
				print("CharacterAssetManager: Preloaded:", full_path)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()

# Get a cached resource or load it if not cached yet
func get_resource(path):
	if path == null or path.is_empty():
		return null
		
	# Return cached version if available
	if _resource_cache.has(path):
		return _resource_cache[path]
	
	# Check if resource exists
	if ResourceLoader.exists(path):
		var resource = load(path)
		_resource_cache[path] = resource
		return resource
	
	# Resource doesn't exist
	print("CharacterAssetManager: ERROR - Failed to load resource:", path)
	return null

# Scan all asset directories to dynamically load available assets
func _scan_directories():
	print("CharacterAssetManager: Scanning asset directories...")
	
	# Scan for races first (this affects what body parts we can load)
	_scan_races()
	
	# Now scan for assets
	_scan_hair_styles()
	_scan_facial_hair()
	_scan_clothing()
	_scan_underwear()
	_scan_undershirts()
	_scan_backgrounds()
	_scan_occupations()

# Scan for available races by checking directories
func _scan_races():
	print("CharacterAssetManager: Scanning for races")
	
	# Clear existing races - we want to be fully dynamic
	races = []
	
	# Check if base Human directory exists and has assets
	if _check_if_race_has_assets("res://Assets/Human/"):
		races.append("Human")
		print("CharacterAssetManager: Found base race: Human")
	
	# Look for specific human variants (White, Black, Latin, etc.)
	var variant_dir = DirAccess.open("res://Assets/Human/")
	if variant_dir:
		variant_dir.list_dir_begin()
		var variant_name = variant_dir.get_next()
		
		while variant_name != "":
			if variant_dir.current_is_dir() and !variant_name.begins_with("."):
				# Skip asset directories that aren't races
				if not variant_name in ["Hair", "FacialHair", "Clothing", "UnderWear", "UnderShirt"]:
					# Check if this variant directory has assets
					var variant_path = "res://Assets/Human/" + variant_name + "/"
					if _check_if_race_has_assets(variant_path):
						races.append(variant_name)
						print("CharacterAssetManager: Found race:", variant_name)
			
			variant_name = variant_dir.get_next()
	
	# Safety check - if no races were found, add Human as a fallback
	if races.size() == 0:
		races.append("Human")
		print("CharacterAssetManager: No races found, added Human as fallback")
	
	print("CharacterAssetManager: Found", races.size(), "total races")

# function to check if a race directory has usable assets
func _check_if_race_has_assets(directory_path: String) -> bool:
	var dir = DirAccess.open(directory_path)
	if !dir:
		return false
		
	var has_assets = false
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if !dir.current_is_dir() and file_name.ends_with(".png"):
			# Check if it's a body part (simple check for common body parts)
			if file_name.begins_with("Body") or file_name.begins_with("Head"):
				has_assets = true
				break
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	return has_assets

# Scan for human variant subdirectories (Black, Latin, White, etc.)
func _scan_human_variants():
	print("CharacterAssetManager: Scanning for human variants")
	
	var human_dir_path = BASE_HUMAN_PATH + "Human"
	var dir = DirAccess.open(human_dir_path)
	
	if dir:
		dir.list_dir_begin()
		var variant_name = dir.get_next()
		
		while variant_name != "":
			if dir.current_is_dir() and !variant_name.begins_with("."):
				# Add "Human_VariantName" to races list (e.g., "Human_Black")
				var race_name = "Human_" + variant_name
				races.append(race_name)
				print("CharacterAssetManager: Found human variant:", race_name)
			
			variant_name = dir.get_next()
		
		print("CharacterAssetManager: Found", races.size() - 1, "human variants")

# Scan for race variants by looking for numbered body parts
func _scan_race_variants():
	print("CharacterAssetManager: Scanning for race variants")
	
	var dir = DirAccess.open(BASE_HUMAN_PATH)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		var variant_numbers = {}
		
		while file_name != "":
			if !dir.current_is_dir() and file_name.ends_with(".png") and !file_name.begins_with("."):
				# Look for variant patterns like Body_2.png or Body_Female_2.png
				var variant_match = file_name.match("*_[0-9].png") or file_name.match("*_*_[0-9].png") 
				
				if variant_match:
					# Extract variant number
					var parts = file_name.get_basename().split("_")
					var variant_num = parts[parts.size() - 1].to_int()
					
					if variant_num > 0:
						variant_numbers[variant_num] = true
						print("CharacterAssetManager: Found race variant:", variant_num)
			
			file_name = dir.get_next()
		
		# Add human variants to races list
		for variant in variant_numbers.keys():
			races.append("Human_" + str(variant))
			
		print("CharacterAssetManager: Found", variant_numbers.size(), "human variants")

# Scan for hair styles in the hair directory
func _scan_hair_styles():
	var dir = DirAccess.open(HAIR_STYLES_PATH)
	if dir:
		print("CharacterAssetManager: Scanning for hair styles in", HAIR_STYLES_PATH)
		
		# Keep the "None" option at index 0
		if hair_styles.size() > 0 and hair_styles[0].name == "None":
			var none_option = hair_styles[0]
			hair_styles.clear()
			hair_styles.append(none_option)
		else:
			hair_styles.clear()
			hair_styles.append({"name": "None", "texture": null, "normal_map": null, "specular_map": null, "sex": -1})
		
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if !dir.current_is_dir() and file_name.ends_with(".png") and !file_name.begins_with(".") and !file_name.ends_with("_n.png") and !file_name.ends_with("_s.png"):
				# Normalize file name for display
				var style_name = file_name.get_basename()
				
				# Clean up the name - replace underscores with spaces and capitalize words
				style_name = style_name.replace("_", " ")
				style_name = style_name.capitalize()
				
				# Determine if this is a sex-specific hairstyle
				var sex = -1 # Default to unisex
				if file_name.to_lower().contains("_male"):
					sex = 0 # Male
				elif file_name.to_lower().contains("_female"):
					sex = 1 # Female
					
				# Remove sex identifier from displayed name if present
				style_name = style_name.replace(" Male", "").replace(" Female", "")
				
				var texture_path = HAIR_STYLES_PATH + file_name
				
				# Get the base name without extension for map lookup
				var base_name = file_name.get_basename()
				
				# Look for normal and specular maps
				var normal_map_path = null
				var specular_map_path = null
				
				# Check for maps in the hair directory first
				if ResourceLoader.exists(HAIR_STYLES_PATH + base_name + "_n.png"):
					normal_map_path = HAIR_STYLES_PATH + base_name + "_n.png"
				elif normal_maps.has(base_name):
					normal_map_path = normal_maps[base_name]
				
				if ResourceLoader.exists(HAIR_STYLES_PATH + base_name + "_s.png"):
					specular_map_path = HAIR_STYLES_PATH + base_name + "_s.png"
				elif specular_maps.has(base_name):
					specular_map_path = specular_maps[base_name]
				
				# Check if the file actually exists
				if ResourceLoader.exists(texture_path):
					hair_styles.append({
						"name": style_name,
						"texture": texture_path,
						"normal_map": normal_map_path,
						"specular_map": specular_map_path,
						"sex": sex
					})
					print("CharacterAssetManager: Found hair style:", style_name, "(Sex:", sex, ")")
					if normal_map_path:
						print("CharacterAssetManager: Found normal map for hair style:", style_name)
					if specular_map_path:
						print("CharacterAssetManager: Found specular map for hair style:", style_name)
			
			file_name = dir.get_next()
		
		print("CharacterAssetManager: Found", hair_styles.size() - 1, "hair styles")

# Scan for facial hair styles
func _scan_facial_hair():
	print("CharacterAssetManager: Scanning for facial hair styles")
	
	var dir = DirAccess.open(FACIAL_HAIR_PATH)
	if !dir:
		# Try the hair directory as fallback (where facial hair might be stored)
		print("CharacterAssetManager: Facial hair directory not found, trying hair directory as fallback")
		dir = DirAccess.open(HAIR_STYLES_PATH)
	
	if dir:
		# Keep the "None" option at index 0
		if facial_hair_styles.size() > 0 and facial_hair_styles[0].name == "None":
			var none_option = facial_hair_styles[0]
			facial_hair_styles.clear()
			facial_hair_styles.append(none_option)
		else:
			facial_hair_styles.clear()
			facial_hair_styles.append({"name": "None", "texture": null, "normal_map": null, "specular_map": null, "sex": 0})
		
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if !dir.current_is_dir() and file_name.ends_with(".png") and !file_name.begins_with(".") and !file_name.ends_with("_n.png") and !file_name.ends_with("_s.png"):
				# Check if it's a facial hair style by naming convention
				if file_name.contains("Facial_") or file_name.begins_with("Beard") or file_name.begins_with("Mustache") or file_name.contains("facial"):
					var style_name = file_name.get_basename()
					
					# Clean up the name - replace underscores with spaces and capitalize words
					style_name = style_name.replace("_", " ")
					style_name = style_name.replace("Facial ", "")
					style_name = style_name.capitalize()
					
					var file_path = dir.get_current_dir().path_join(file_name)
					
					# Get the base name without extension for map lookup
					var base_name = file_name.get_basename()
					
					# Look for normal and specular maps
					var normal_map_path = null
					var specular_map_path = null
					
					# Check for maps in the same directory first
					if ResourceLoader.exists(dir.get_current_dir().path_join(base_name + "_n.png")):
						normal_map_path = dir.get_current_dir().path_join(base_name + "_n.png")
					elif normal_maps.has(base_name):
						normal_map_path = normal_maps[base_name]
					
					if ResourceLoader.exists(dir.get_current_dir().path_join(base_name + "_s.png")):
						specular_map_path = dir.get_current_dir().path_join(base_name + "_s.png")
					elif specular_maps.has(base_name):
						specular_map_path = specular_maps[base_name]
					
					# Check if the file actually exists (for exports)
					if ResourceLoader.exists(file_path):
						facial_hair_styles.append({
							"name": style_name,
							"texture": file_path,
							"normal_map": normal_map_path,
							"specular_map": specular_map_path,
							"sex": 0  # Facial hair is male-only
						})
						print("CharacterAssetManager: Found facial hair style:", style_name)
						if normal_map_path:
							print("CharacterAssetManager: Found normal map for facial hair style:", style_name)
						if specular_map_path:
							print("CharacterAssetManager: Found specular map for facial hair style:", style_name)
			
			file_name = dir.get_next()
		
		print("CharacterAssetManager: Found", facial_hair_styles.size() - 1, "facial hair styles")

# Scan for clothing options
func _scan_clothing():
	print("CharacterAssetManager: Scanning for clothing options")
	
	var dir = DirAccess.open(CLOTHING_PATH)
	if dir:
		# Keep the "None" option at index 0
		if clothing_options.size() > 0 and clothing_options[0].name == "None":
			var none_option = clothing_options[0]
			clothing_options.clear()
			clothing_options.append(none_option)
		else:
			clothing_options.clear()
			clothing_options.append({
				"name": "None", 
				"textures": {}, 
				"normal_maps": {}, 
				"specular_maps": {}, 
				"sex": -1
			})
		
		# Extract all clothing sets and organize them
		var clothing_sets = _scan_clothing_sets(dir)
		
		# Convert to the expected format
		for set_name in clothing_sets:
			var sex = -1 # Default to unisex
			
			# Check if this is a sex-specific clothing set
			if set_name.to_lower().contains("_male"):
				sex = 0
			elif set_name.to_lower().contains("_female"):
				sex = 1
			
			# Clean up the display name
			var display_name = set_name.replace("_Male", "").replace("_Female", "")
			display_name = display_name.replace("_", " ").capitalize()
			
			clothing_options.append({
				"name": display_name,
				"textures": clothing_sets[set_name]["textures"],
				"normal_maps": clothing_sets[set_name]["normal_maps"],
				"specular_maps": clothing_sets[set_name]["specular_maps"],
				"sex": sex
			})
			print("CharacterAssetManager: Added clothing set:", display_name, "(Sex:", sex, ")")
		
		print("CharacterAssetManager: Found", clothing_options.size() - 1, "clothing sets")

# Helper function to scan for clothing sets with maps support
func _scan_clothing_sets(dir):
	var clothing_sets = {}
	
	# First pass: collect individual clothing files
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if !dir.current_is_dir() and file_name.ends_with(".png") and !file_name.begins_with(".") and !file_name.ends_with("_n.png") and !file_name.ends_with("_s.png"):
			# Try to detect the clothing set and part from filename
			var parts = file_name.get_basename().split("_")
			
			if parts.size() >= 2:
				# Get the set name (everything before the last part)
				var set_name = ""
				for i in range(parts.size() - 1):
					if i > 0:
						set_name += "_"
					set_name += parts[i]
				
				# Get the part name (last part)
				var part_name = parts[parts.size() - 1]
				
				# Make sure the set exists in our dictionary
				if !clothing_sets.has(set_name):
					clothing_sets[set_name] = {
						"textures": {},
						"normal_maps": {},
						"specular_maps": {}
					}
				
				# Add the part to the set
				var texture_path = dir.get_current_dir().path_join(file_name)
				clothing_sets[set_name]["textures"][part_name] = texture_path
				
				# Look for corresponding maps
				var base_name = file_name.get_basename()
				
				# Check for maps in the same directory
				if ResourceLoader.exists(dir.get_current_dir().path_join(base_name + "_n.png")):
					clothing_sets[set_name]["normal_maps"][part_name] = dir.get_current_dir().path_join(base_name + "_n.png")
				elif normal_maps.has(part_name):
					clothing_sets[set_name]["normal_maps"][part_name] = normal_maps[part_name]
				
				if ResourceLoader.exists(dir.get_current_dir().path_join(base_name + "_s.png")):
					clothing_sets[set_name]["specular_maps"][part_name] = dir.get_current_dir().path_join(base_name + "_s.png")
				elif specular_maps.has(part_name):
					clothing_sets[set_name]["specular_maps"][part_name] = specular_maps[part_name]
				
				print("CharacterAssetManager: Found clothing part:", set_name, part_name)
		
		file_name = dir.get_next()
	
	# Second pass: look for subdirectories that might contain clothing sets
	dir.list_dir_begin()
	file_name = dir.get_next()
	
	while file_name != "":
		if dir.current_is_dir() and !file_name.begins_with("."):
			var set_name = file_name
			var set_dir = DirAccess.open(dir.get_current_dir().path_join(file_name))
			
			if set_dir:
				if !clothing_sets.has(set_name):
					clothing_sets[set_name] = {
						"textures": {},
						"normal_maps": {},
						"specular_maps": {}
					}
				
				set_dir.list_dir_begin()
				var part_file = set_dir.get_next()
				
				while part_file != "":
					if !set_dir.current_is_dir() and part_file.ends_with(".png") and !part_file.ends_with("_n.png") and !part_file.ends_with("_s.png"):
						var part_name = part_file.get_basename()
						var texture_path = set_dir.get_current_dir().path_join(part_file)
						
						clothing_sets[set_name]["textures"][part_name] = texture_path
						
						# Look for corresponding maps
						var base_name = part_file.get_basename()
						
						# Check for maps in the same directory
						if ResourceLoader.exists(set_dir.get_current_dir().path_join(base_name + "_n.png")):
							clothing_sets[set_name]["normal_maps"][part_name] = set_dir.get_current_dir().path_join(base_name + "_n.png")
						elif normal_maps.has(part_name):
							clothing_sets[set_name]["normal_maps"][part_name] = normal_maps[part_name]
						
						if ResourceLoader.exists(set_dir.get_current_dir().path_join(base_name + "_s.png")):
							clothing_sets[set_name]["specular_maps"][part_name] = set_dir.get_current_dir().path_join(base_name + "_s.png")
						elif specular_maps.has(part_name):
							clothing_sets[set_name]["specular_maps"][part_name] = specular_maps[part_name]
						
						print("CharacterAssetManager: Found clothing part in subdirectory:", set_name, part_name)
					
					part_file = set_dir.get_next()
			else:
				print("CharacterAssetManager: Could not open clothing set directory:", set_name)
		
		file_name = dir.get_next()
	
	return clothing_sets

# Scan for underwear options
func _scan_underwear():
	print("CharacterAssetManager: Scanning for underwear options")
	
	var dir = DirAccess.open(UNDERWEAR_PATH)
	if dir:
		# Keep any default options (we need at least one male and one female option)
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
			if !dir.current_is_dir() and file_name.ends_with(".png") and !file_name.begins_with(".") and !file_name.ends_with("_n.png") and !file_name.ends_with("_s.png"):
				var item_name = file_name.get_basename()
				
				# Clean up the name - replace underscores with spaces and capitalize words
				item_name = item_name.replace("_", " ")
				item_name = item_name.capitalize()
				
				# Determine if this is a sex-specific item
				var sex = -1 # Default to unisex
				if file_name.to_lower().contains("_male") or file_name.to_lower().contains("boxers") or file_name.to_lower().contains("briefs"):
					sex = 0 # Male
					has_male = true
				elif file_name.to_lower().contains("_female") or file_name.to_lower().contains("panties"):
					sex = 1 # Female
					has_female = true
					
				# Remove sex identifier from displayed name if present
				item_name = item_name.replace(" Male", "").replace(" Female", "")
				
				var texture_path = UNDERWEAR_PATH + file_name
				
				# Get the base name for map lookup
				var base_name = file_name.get_basename()
				
				# Look for corresponding maps
				var normal_map_path = null
				var specular_map_path = null
				
				# Check for maps in the same directory
				if ResourceLoader.exists(UNDERWEAR_PATH + base_name + "_n.png"):
					normal_map_path = UNDERWEAR_PATH + base_name + "_n.png"
				elif normal_maps.has(base_name):
					normal_map_path = normal_maps[base_name]
				
				if ResourceLoader.exists(UNDERWEAR_PATH + base_name + "_s.png"):
					specular_map_path = UNDERWEAR_PATH + base_name + "_s.png"
				elif specular_maps.has(base_name):
					specular_map_path = specular_maps[base_name]
				
				# Check if the file actually exists
				if ResourceLoader.exists(texture_path):
					underwear_options.append({
						"name": item_name,
						"texture": texture_path,
						"normal_map": normal_map_path,
						"specular_map": specular_map_path,
						"sex": sex
					})
					print("CharacterAssetManager: Found underwear:", item_name, "(Sex:", sex, ")")
			
			file_name = dir.get_next()
		
		# If we didn't find any male or female options, add back the defaults
		if !has_male or !has_female:
			for item in defaults:
				if (item.sex == 0 and !has_male) or (item.sex == 1 and !has_female):
					# Update the item to include map fields if they don't exist
					if not "normal_map" in item:
						item["normal_map"] = null
					if not "specular_map" in item:
						item["specular_map"] = null
						
					underwear_options.append(item)
					print("CharacterAssetManager: Added default underwear for sex", item.sex)
					if item.sex == 0:
						has_male = true
					elif item.sex == 1:
						has_female = true
		
		# Make sure we have at least one option for each sex
		if !has_male:
			underwear_options.append({
				"name": "White Briefs",
				"texture": "res://Assets/Human/UnderWear/white_briefs.png",
				"normal_map": normal_maps.get("white_briefs", null),
				"specular_map": specular_maps.get("white_briefs", null),
				"sex": 0
			})
			print("CharacterAssetManager: Added emergency default male underwear")
		
		if !has_female:
			underwear_options.append({
				"name": "White Panties",
				"texture": "res://Assets/Human/UnderWear/white_panties.png",
				"normal_map": normal_maps.get("white_panties", null),
				"specular_map": specular_maps.get("white_panties", null),
				"sex": 1
			})
			print("CharacterAssetManager: Added emergency default female underwear")
		
		print("CharacterAssetManager: Found", underwear_options.size(), "underwear options")

# Scan for undershirt options
func _scan_undershirts():
	print("CharacterAssetManager: Scanning for undershirt options")
	
	var dir = DirAccess.open(UNDERSHIRT_PATH)
	if dir:
		# Keep default options (we need the "None" option for males and at least one female option)
		var has_female_top = false
		var defaults = []
		
		for item in undershirt_options:
			if item.sex == 1 and item.texture != null:
				has_female_top = true
			defaults.append(item)
		
		undershirt_options.clear()
		
		# Add "None" option for males first
		undershirt_options.append({
			"name": "None", 
			"texture": null,
			"normal_map": null,
			"specular_map": null,
			"sex": 0  # Males can have no top
		})
		
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if !dir.current_is_dir() and file_name.ends_with(".png") and !file_name.begins_with(".") and !file_name.ends_with("_n.png") and !file_name.ends_with("_s.png"):
				var item_name = file_name.get_basename()
				
				# Clean up the name - replace underscores with spaces and capitalize words
				item_name = item_name.replace("_", " ")
				item_name = item_name.capitalize()
				
				# Determine if this is a sex-specific item
				var sex = -1 # Default to unisex
				if file_name.to_lower().contains("_male"):
					sex = 0 # Male
				elif file_name.to_lower().contains("_female") or file_name.to_lower().contains("bra"):
					sex = 1 # Female
					has_female_top = true
					
				# Remove sex identifier from displayed name if present
				item_name = item_name.replace(" Male", "").replace(" Female", "")
				
				var texture_path = UNDERSHIRT_PATH + file_name
				
				# Get the base name for map lookup
				var base_name = file_name.get_basename()
				
				# Look for corresponding maps
				var normal_map_path = null
				var specular_map_path = null
				
				# Check for maps in the same directory
				if ResourceLoader.exists(UNDERSHIRT_PATH + base_name + "_n.png"):
					normal_map_path = UNDERSHIRT_PATH + base_name + "_n.png"
				elif normal_maps.has(base_name):
					normal_map_path = normal_maps[base_name]
				
				if ResourceLoader.exists(UNDERSHIRT_PATH + base_name + "_s.png"):
					specular_map_path = UNDERSHIRT_PATH + base_name + "_s.png"
				elif specular_maps.has(base_name):
					specular_map_path = specular_maps[base_name]
				
				# Check if the file actually exists
				if ResourceLoader.exists(texture_path):
					undershirt_options.append({
						"name": item_name,
						"texture": texture_path,
						"normal_map": normal_map_path,
						"specular_map": specular_map_path,
						"sex": sex
					})
					print("CharacterAssetManager: Found undershirt:", item_name, "(Sex:", sex, ")")
			
			file_name = dir.get_next()
		
		# If we didn't find any female-specific tops, add the default one
		if !has_female_top:
			for item in defaults:
				if item.sex == 1 and item.texture != null:
					# Update the item to include map fields if they don't exist
					if not "normal_map" in item:
						item["normal_map"] = null
					if not "specular_map" in item:
						item["specular_map"] = null
						
					undershirt_options.append(item)
					print("CharacterAssetManager: Added default female top")
					has_female_top = true
					break
		
		# Emergency default for female tops
		if !has_female_top:
			undershirt_options.append({
				"name": "White Bra",
				"texture": "res://Assets/Human/UnderShirt/white_bra.png",
				"normal_map": normal_maps.get("white_bra", null),
				"specular_map": specular_maps.get("white_bra", null),
				"sex": 1
			})
			print("CharacterAssetManager: Added emergency default female top")
		
		print("CharacterAssetManager: Found", undershirt_options.size(), "undershirt options")

# Scan for background textures
func _scan_backgrounds():
	print("CharacterAssetManager: Scanning for background textures")
	
	var dir = DirAccess.open(BACKGROUNDS_PATH)
	if dir:
		background_textures.clear()
		
		# Add the default space background
		if ResourceLoader.exists("res://Assets/Backgrounds/Space.png"):
			background_textures.append({
				"name": "Space", 
				"texture": "res://Assets/Backgrounds/Space.png"
			})
			print("CharacterAssetManager: Added default space background")
		
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if !dir.current_is_dir() and (file_name.ends_with(".png") or file_name.ends_with(".jpg")) and !file_name.begins_with("."):
				var bg_name = file_name.get_basename()
				bg_name = bg_name.replace("_", " ")
				bg_name = bg_name.capitalize()
				
				var texture_path = BACKGROUNDS_PATH + file_name
				
				# Check if the file actually exists (for exports)
				if ResourceLoader.exists(texture_path):
					# Skip if we already added this (avoid duplicates)
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
						print("CharacterAssetManager: Found background:", bg_name)
			
			file_name = dir.get_next()
		
		print("CharacterAssetManager: Found", background_textures.size(), "background textures")

# Scan for occupations by looking at clothing names
func _scan_occupations():
	print("CharacterAssetManager: Determining occupations from clothing sets")
	
	# Start with basic defaults
	var occupation_list = ["Engineer", "Security", "Medical", "Science", "Command", "Cargo"]
	
	# Add any clothing names that might represent occupations
	for clothing in clothing_options:
		if clothing.name != "None":
			# Clean up name
			var occupation = clothing.name.replace("Uniform", "").strip_edges()
			
			# Only add if not already in the list
			if not occupation in occupation_list:
				occupation_list.append(occupation)
				print("CharacterAssetManager: Found occupation from clothing:", occupation)
	
	# Update the occupations list
	occupations = occupation_list
	print("CharacterAssetManager: Identified", occupations.size(), "occupations")

# Load configuration from the config file if it exists
func _load_config_file():
	print("CharacterAssetManager: Checking for config file:", ASSET_CONFIG_PATH)
	
	if ResourceLoader.exists(ASSET_CONFIG_PATH):
		print("CharacterAssetManager: Config file found, loading")
		
		var file = FileAccess.open(ASSET_CONFIG_PATH, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			var json_result = JSON.parse_string(json_string)
			
			if json_result:
				print("CharacterAssetManager: Successfully parsed config file")
				
				# Override defaults with loaded values
				if json_result.has("races"):
					races = json_result.races
					print("CharacterAssetManager: Loaded", races.size(), "races from config")
				
				if json_result.has("occupations"):
					occupations = json_result.occupations
					print("CharacterAssetManager: Loaded", occupations.size(), "occupations from config")
					
				if json_result.has("hair_styles"):
					hair_styles = json_result.hair_styles
					print("CharacterAssetManager: Loaded", hair_styles.size(), "hair styles from config")
					
				if json_result.has("facial_hair_styles"):
					facial_hair_styles = json_result.facial_hair_styles
					print("CharacterAssetManager: Loaded", facial_hair_styles.size(), "facial hair styles from config")
					
				if json_result.has("clothing_options"):
					clothing_options = json_result.clothing_options
					print("CharacterAssetManager: Loaded", clothing_options.size(), "clothing options from config")
					
				if json_result.has("underwear_options"):
					underwear_options = json_result.underwear_options
					print("CharacterAssetManager: Loaded", underwear_options.size(), "underwear options from config")
					
				if json_result.has("undershirt_options"):
					undershirt_options = json_result.undershirt_options
					print("CharacterAssetManager: Loaded", undershirt_options.size(), "undershirt options from config")
					
				if json_result.has("background_textures"):
					background_textures = json_result.background_textures
					print("CharacterAssetManager: Loaded", background_textures.size(), "background textures from config")
			else:
				print("CharacterAssetManager: ERROR - Failed to parse config file JSON")
		else:
			print("CharacterAssetManager: ERROR - Failed to open config file")
	else:
		print("CharacterAssetManager: Config file not found, using scanned assets")

# Verify all assets actually exist and are accessible
func _verify_assets():
	print("CharacterAssetManager: Verifying assets...")
	
	# Verify hair styles
	var valid_hair_styles = []
	for hair in hair_styles:
		if hair.texture == null or ResourceLoader.exists(hair.texture):
			valid_hair_styles.append(hair)
		else:
			print("CharacterAssetManager: WARNING - Hair style texture not found:", hair.texture)
	
	hair_styles = valid_hair_styles
	
	# Verify facial hair styles
	var valid_facial_hair = []
	for style in facial_hair_styles:
		if style.texture == null or ResourceLoader.exists(style.texture):
			valid_facial_hair.append(style)
		else:
			print("CharacterAssetManager: WARNING - Facial hair texture not found:", style.texture)
	
	facial_hair_styles = valid_facial_hair
	
	# Verify clothing options
	var valid_clothing = []
	for clothing in clothing_options:
		var all_valid = true
		
		for part in clothing.textures:
			var path = clothing.textures[part]
			if not ResourceLoader.exists(path):
				all_valid = false
				print("CharacterAssetManager: WARNING - Clothing texture not found:", path)
		
		if all_valid or clothing.name == "None":
			valid_clothing.append(clothing)
	
	clothing_options = valid_clothing
	
	# Verify underwear options
	var valid_underwear = []
	for underwear in underwear_options:
		if underwear.texture == null or ResourceLoader.exists(underwear.texture):
			valid_underwear.append(underwear)
		else:
			print("CharacterAssetManager: WARNING - Underwear texture not found:", underwear.texture)
	
	underwear_options = valid_underwear
	
	# Verify undershirt options
	var valid_undershirts = []
	for shirt in undershirt_options:
		if shirt.texture == null or ResourceLoader.exists(shirt.texture):
			valid_undershirts.append(shirt)
		else:
			print("CharacterAssetManager: WARNING - Undershirt texture not found:", shirt.texture)
	
	undershirt_options = valid_undershirts
	
	# Verify backgrounds
	var valid_backgrounds = []
	for bg in background_textures:
		if bg.texture == null or ResourceLoader.exists(bg.texture):
			valid_backgrounds.append(bg)
		else:
			print("CharacterAssetManager: WARNING - Background texture not found:", bg.texture)
	
	background_textures = valid_backgrounds
	
	# Make sure we have at least minimal options in each category
	_ensure_minimal_options()
	
	print("CharacterAssetManager: Asset verification complete")

# Ensure we have at least the minimal required options
func _ensure_minimal_options():
	# Make sure we have at least one race
	if races.size() == 0:
		races.append("Human")
		print("CharacterAssetManager: No races found, added Human as fallback")
	
	# Hair styles - ensure we have "None"
	if hair_styles.size() == 0 or hair_styles[0].name != "None":
		hair_styles.insert(0, {"name": "None", "texture": null, "sex": -1})
		print("CharacterAssetManager: Added 'None' hair style")
	
	# Facial hair - ensure we have "None"
	if facial_hair_styles.size() == 0 or facial_hair_styles[0].name != "None":
		facial_hair_styles.insert(0, {"name": "None", "texture": null, "sex": 0})
		print("CharacterAssetManager: Added 'None' facial hair style")
	
	# Clothing - ensure we have "None"
	if clothing_options.size() == 0 or clothing_options[0].name != "None":
		clothing_options.insert(0, {"name": "None", "textures": {}, "sex": -1})
		print("CharacterAssetManager: Added 'None' clothing option")
	
	# Underwear - ensure we have at least one option for each sex
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
			"texture": "res://Assets/Human/UnderWear/white_briefs.png", 
			"sex": 0
		})
		print("CharacterAssetManager: Added default male underwear")
	
	if !has_female:
		underwear_options.append({
			"name": "White Panties", 
			"texture": "res://Assets/Human/UnderWear/white_panties.png", 
			"sex": 1
		})
		print("CharacterAssetManager: Added default female underwear")
	
	# Undershirts - ensure we have "None" for males and at least one female option
	var has_none_top = false
	var has_female_top = false
	
	for item in undershirt_options:
		if item.name == "None" and item.sex == 0:
			has_none_top = true
		if item.sex == 1 and item.texture != null:
			has_female_top = true
	
	if !has_none_top:
		undershirt_options.insert(0, {"name": "None", "texture": null, "sex": 0})
		print("CharacterAssetManager: Added 'None' undershirt option for males")
	
	if !has_female_top:
		undershirt_options.append({
			"name": "White Bra", 
			"texture": "res://Assets/Human/UnderShirt/white_bra.png", 
			"sex": 1
		})
		print("CharacterAssetManager: Added default female top")
	
	# Backgrounds - ensure we have at least one
	if background_textures.size() == 0:
		background_textures.append({
			"name": "Space", 
			"texture": "res://Assets/Backgrounds/Space.png"
		})
		print("CharacterAssetManager: Added default space background")

# Get path for a race's sprite set with sex-specific sprites
func get_race_sprites(race_index: int, sex: int = 0) -> Dictionary:
	print("CharacterAssetManager: Getting race sprites for race index", race_index, "sex", sex)
	
	if race_index < 0 or race_index >= races.size():
		print("CharacterAssetManager: Invalid race index:", race_index)
		race_index = 0  # Default to first race
	
	var race_name = races[race_index]
	var sprite_paths = {}
	
	# Determine the sex suffix for filenames
	var sex_suffix = "_Female" if sex == 1 else ""
	
	# Define the base path for sprites
	var race_path = "res://Assets/Human/"
	
	# If not the generic "Human" race, use the race-specific directory
	if race_name != "Human":
		race_path = "res://Assets/Human/" + race_name + "/"
	
	# Core body parts to look for
	var body_parts = {
		"body": "Body",
		"head": "Head",
		"left_arm": "Left_arm",
		"right_arm": "Right_arm", 
		"left_leg": "Left_leg",
		"right_leg": "Right_leg",
		"left_hand": "Left_hand",
		"right_hand": "Right_hand",
		"left_foot": "Left_foot",
		"right_foot": "Right_foot"
	}
	
	# Try to find each body part
	for sprite_key in body_parts:
		var part_name = body_parts[sprite_key]
		var found = false
		
		# Try different path combinations in order of priority
		var paths_to_try = [
			# 1. Race directory with sex
			race_path + part_name + sex_suffix + ".png",
			# 2. Race directory with base part
			race_path + part_name + ".png",
			# 3. Generic Human directory with sex as fallback
			"res://Assets/Human/" + part_name + sex_suffix + ".png",
			# 4. Generic Human directory, base part as final fallback
			"res://Assets/Human/" + part_name + ".png"
		]
		
		# Try each path in order
		for path in paths_to_try:
			if ResourceLoader.exists(path):
				sprite_paths[sprite_key] = {
					"texture": path,
					"normal_map": null,
					"specular_map": null
				}
				
				# Look for corresponding maps
				var base_name = part_name
				
				# Try to find normal and specular maps for this body part
				if normal_maps.has(base_name):
					sprite_paths[sprite_key]["normal_map"] = normal_maps[base_name]
					print("CharacterAssetManager: Found normal map for", sprite_key, ":", normal_maps[base_name])
				
				if specular_maps.has(base_name):
					sprite_paths[sprite_key]["specular_map"] = specular_maps[base_name]
					print("CharacterAssetManager: Found specular map for", sprite_key, ":", specular_maps[base_name])
				
				print("CharacterAssetManager: Found sprite for", sprite_key, ":", path)
				found = true
				break
		
		if not found:
			print("CharacterAssetManager: WARNING - Could not find sprite for", sprite_key)
	
	return sprite_paths

# Get all available hair styles for a given sex
func get_hair_styles_for_sex(sex: int = 0) -> Array:
	print("CharacterAssetManager: Getting hair styles for sex", sex)
	
	var result = []
	
	# Always include "None" option
	result.append({"name": "None", "texture": null, "sex": -1})
	
	# Add styles that work for this sex
	for style in hair_styles:
		if style.name == "None":
			continue
			
		# Include if it matches the sex or is unisex
		if style.sex == sex or style.sex == -1:
			result.append(style)
			print("CharacterAssetManager: Added hair style for sex", sex, ":", style.name)
	
	# If we found no styles specific to this sex, just return all styles
	if result.size() <= 1:
		print("CharacterAssetManager: No matching hair styles found, returning all styles")
		return hair_styles
		
	print("CharacterAssetManager: Found", result.size() - 1, "hair styles for sex", sex)
	return result

# Get all facial hair styles (mainly for males)
func get_facial_hair_for_sex(sex: int = 0) -> Array:
	print("CharacterAssetManager: Getting facial hair for sex", sex)
	
	var result = []
	
	# Always include "None" option
	result.append({"name": "None", "texture": null, "sex": 0})
	
	# Only include other options for males
	if sex == 0:
		for style in facial_hair_styles:
			if style.name == "None":
				continue
				
			result.append(style)
			print("CharacterAssetManager: Added facial hair style:", style.name)
	
	print("CharacterAssetManager: Found", result.size() - 1, "facial hair styles for sex", sex)
	return result

# Get all clothing options that are compatible with a given sex
func get_clothing_for_sex(sex: int = 0) -> Array:
	print("CharacterAssetManager: Getting clothing for sex", sex)
	
	var result = []
	
	# Always include "None" option
	result.append({"name": "None", "textures": {}, "sex": -1})
	
	# Add clothing that works for this sex
	for clothing in clothing_options:
		if clothing.name == "None":
			continue
			
		# Include if it matches the sex or is unisex
		if clothing.sex == sex or clothing.sex == -1:
			result.append(clothing)
			print("CharacterAssetManager: Added clothing for sex", sex, ":", clothing.name)
	
	# If we found no clothing compatible with this sex, just return all options
	if result.size() <= 1:
		print("CharacterAssetManager: No sex-specific clothing found, returning all clothing")
		return clothing_options
		
	print("CharacterAssetManager: Found", result.size() - 1, "clothing options for sex", sex)
	return result

# Get all underwear options for a given sex
func get_underwear_for_sex(sex: int = 0) -> Array:
	print("CharacterAssetManager: Getting underwear for sex", sex)
	
	var result = []
	
	# Add underwear that works for this sex
	for item in underwear_options:
		# Include if it matches the sex or is unisex
		if item.sex == sex or item.sex == -1:
			result.append(item)
			print("CharacterAssetManager: Added underwear for sex", sex, ":", item.name)
	
	# Make sure we have at least one option
	if result.size() == 0:
		print("CharacterAssetManager: No matching underwear found, using default")
		if sex == 0:
			result.append({
				"name": "White Briefs", 
				"texture": "res://Assets/Human/UnderWear/white_briefs.png", 
				"sex": 0
			})
		else:
			result.append({
				"name": "White Panties", 
				"texture": "res://Assets/Human/UnderWear/white_panties.png", 
				"sex": 1
			})
	
	print("CharacterAssetManager: Found", result.size(), "underwear options for sex", sex)
	return result

# Get all undershirt options for a given sex
func get_undershirts_for_sex(sex: int = 0) -> Array:
	print("CharacterAssetManager: Getting undershirts for sex", sex)
	
	var result = []
	
	# Add "None" option for males only
	if sex == 0:
		result.append({"name": "None", "texture": null, "sex": 0})
	
	# Add undershirts that work for this sex
	for item in undershirt_options:
		if item.name == "None" and sex == 1:
			continue  # Skip "None" option for females
			
		# Include if it matches the sex or is unisex
		if item.sex == sex or item.sex == -1:
			result.append(item)
			print("CharacterAssetManager: Added undershirt for sex", sex, ":", item.name)
	
	# Make sure females have at least one option
	if sex == 1 and result.size() == 0:
		print("CharacterAssetManager: No matching undershirt found for female, using default")
		result.append({
			"name": "White Bra", 
			"texture": "res://Assets/Human/UnderShirt/white_bra.png", 
			"sex": 1
		})
	
	print("CharacterAssetManager: Found", result.size(), "undershirt options for sex", sex)
	return result

# Save current configuration to file
func save_config():
	print("CharacterAssetManager: Saving configuration to file:", ASSET_CONFIG_PATH)
	
	var config = {
		"races": races,
		"occupations": occupations,
		"hair_styles": hair_styles,
		"facial_hair_styles": facial_hair_styles,
		"clothing_options": clothing_options,
		"underwear_options": underwear_options,
		"undershirt_options": undershirt_options,
		"background_textures": background_textures
	}
	
	# Create directory if it doesn't exist
	var directory = DirAccess.open("res://")
	if not directory.dir_exists("res://Config"):
		directory.make_dir("Config")
		print("CharacterAssetManager: Created Config directory")
	
	# Save file
	var file = FileAccess.open(ASSET_CONFIG_PATH, FileAccess.WRITE)
	if file:
		file.store_line(JSON.stringify(config, "  "))
		print("CharacterAssetManager: Configuration saved successfully")
	else:
		print("CharacterAssetManager: ERROR - Failed to save configuration file")

# Add a new hair style
func add_hair_style(name: String, texture_path: String, sex: int = -1) -> void:
	print("CharacterAssetManager: Adding hair style:", name, texture_path)
	
	hair_styles.append({
		"name": name,
		"texture": texture_path,
		"sex": sex
	})
	save_config()

# Add a new facial hair style
func add_facial_hair_style(name: String, texture_path: String) -> void:
	print("CharacterAssetManager: Adding facial hair style:", name, texture_path)
	
	facial_hair_styles.append({
		"name": name,
		"texture": texture_path,
		"sex": 0  # Always male-only
	})
	save_config()

# Add a new clothing option
func add_clothing_option(name: String, textures: Dictionary, sex: int = -1) -> void:
	print("CharacterAssetManager: Adding clothing option:", name)
	
	clothing_options.append({
		"name": name,
		"textures": textures,
		"sex": sex
	})
	save_config()

# Add a new underwear option
func add_underwear_option(name: String, texture_path: String, sex: int = -1) -> void:
	print("CharacterAssetManager: Adding underwear option:", name, texture_path)
	
	underwear_options.append({
		"name": name,
		"texture": texture_path,
		"sex": sex
	})
	save_config()

# Add a new undershirt option
func add_undershirt_option(name: String, texture_path: String, sex: int = -1) -> void:
	print("CharacterAssetManager: Adding undershirt option:", name, texture_path)
	
	undershirt_options.append({
		"name": name,
		"texture": texture_path,
		"sex": sex
	})
	save_config()

# Add a new race
func add_race(name: String) -> void:
	print("CharacterAssetManager: Adding race:", name)
	
	races.append(name)
	save_config()

# Add a new occupation
func add_occupation(name: String) -> void:
	print("CharacterAssetManager: Adding occupation:", name)
	
	occupations.append(name)
	save_config()

# Add a new background texture
func add_background(name: String, texture_path: String) -> void:
	print("CharacterAssetManager: Adding background:", name, texture_path)
	
	background_textures.append({
		"name": name,
		"texture": texture_path
	})
	save_config()

# Refresh all assets by rescanning directories
func refresh_assets() -> void:
	print("CharacterAssetManager: Refreshing assets")
	_scan_directories()
	_verify_assets()
	save_config()
