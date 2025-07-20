@tool
extends EditorScript

# Path to save the registry script
const REGISTRY_PATH = "res://AssetRegistry.gd"

# Directories to scan (add all your asset directories here)
const DIRECTORIES = [
	{"path": "res://Scenes/", "prefix": "level_"},
	{"path": "res://Assets/", "prefix": "asset_"},
	{"path": "res://Code/", "prefix": "code_"},
	{"path": "res://Sound/", "prefix": "audio_"},
]

# Extensions to include (add all relevant extensions)
const EXTENSIONS = [".tscn", ".png", ".ogg", ".wav", ".mp3", ".json", ".gd"]

# Maximum assets per dictionary (to avoid Godot limitations)
const MAX_ASSETS_PER_DICT = 1000

func _run():
	print("=== Starting Asset Registry Generation ===")
	
	var registry_file = FileAccess.open(REGISTRY_PATH, FileAccess.WRITE)
	if registry_file == null:
		printerr("Failed to open registry file for writing at: ", REGISTRY_PATH)
		return
	
	# Write file header
	registry_file.store_string("# Auto-generated Asset Registry - DO NOT EDIT MANUALLY\n")
	registry_file.store_string("# Generated on " + Time.get_datetime_string_from_system() + "\n")
	registry_file.store_string("# Generated with Godot " + Engine.get_version_info().string + "\n\n")
	registry_file.store_string("extends Node\n\n")
	registry_file.store_string("# Asset registry to force inclusion in exports\n")
	
	var total_assets = 0
	var current_dict = 0
	var assets_in_current_dict = 0
	
	# Start first dictionary
	registry_file.store_string("var assets_" + str(current_dict) + " = {\n")
	
	# Scan each directory
	for dir_info in DIRECTORIES:
		var dir_path = dir_info.path
		var key_prefix = dir_info.prefix
		
		print("Scanning directory: ", dir_path)
		registry_file.store_string("\n\t# Assets from " + dir_path + "\n")
		
		var dir_result = scan_directory(dir_path, key_prefix, registry_file, assets_in_current_dict, current_dict)
		total_assets += dir_result.assets
		assets_in_current_dict = dir_result.current_count
		current_dict = dir_result.current_dict
		
		# Check if we need to start a new dictionary
		if assets_in_current_dict >= MAX_ASSETS_PER_DICT:
			registry_file.store_string("}\n\n")
			current_dict += 1
			assets_in_current_dict = 0
			registry_file.store_string("var assets_" + str(current_dict) + " = {\n")
	
	# Close the last dictionary
	registry_file.store_string("}\n\n")
	
	# Create combined assets dictionary
	registry_file.store_string("# Combined asset access\n")
	registry_file.store_string("var all_assets = {}\n\n")
	
	registry_file.store_string("func _ready():\n")
	registry_file.store_string("\tprint(\"AssetRegistry: Loading with \" + str(" + str(total_assets) + ") + \" assets\")\n")
	registry_file.store_string("\t# Combine all asset dictionaries\n")
	
	for i in range(current_dict + 1):
		registry_file.store_string("\tall_assets.merge(assets_" + str(i) + ")\n")
	
	registry_file.store_string("\tprint(\"AssetRegistry: Ready with \" + str(all_assets.size()) + \" assets loaded\")\n\n")
	
	# Add utility functions
	add_utility_functions(registry_file)
	
	registry_file.close()
	
	print("=== Asset Registry Generation Complete ===")
	print("Total assets registered: ", total_assets)
	print("Registry saved to: ", REGISTRY_PATH)
	print("Next steps:")
	print("1. Add AssetRegistry.gd as an AutoLoad in Project Settings")
	print("2. Export your project - all assets will be included")

func scan_directory(path: String, key_prefix: String, file: FileAccess, current_count: int, dict_index: int) -> Dictionary:
	var asset_count = 0
	var assets_in_dict = current_count
	var current_dict = dict_index
	
	var dir = DirAccess.open(path)
	if dir == null:
		print("Warning: Could not open directory: " + path)
		return {"assets": asset_count, "current_count": assets_in_dict, "current_dict": current_dict}
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		# Skip hidden files and directories
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue
		
		# Use path_join for proper cross-platform path handling
		var full_path = path.path_join(file_name)
		
		if dir.current_is_dir():
			# Recursively scan subdirectories
			var subdir_result = scan_directory(full_path, key_prefix + sanitize_name(file_name) + "_", file, assets_in_dict, current_dict)
			asset_count += subdir_result.assets
			assets_in_dict = subdir_result.current_count
			current_dict = subdir_result.current_dict
		else:
			# Check if file has a relevant extension
			var has_valid_extension = false
			for ext in EXTENSIONS:
				if file_name.to_lower().ends_with(ext.to_lower()):
					has_valid_extension = true
					break
			
			if has_valid_extension:
				# Check if we need to start a new dictionary
				if assets_in_dict >= MAX_ASSETS_PER_DICT:
					file.store_string("}\n\n")
					current_dict += 1
					assets_in_dict = 0
					file.store_string("var assets_" + str(current_dict) + " = {\n")
				
				var resource_name = file_name.get_basename()
				var resource_key = key_prefix + sanitize_name(resource_name)
				
				# Ensure the path is properly formatted
				var clean_path = full_path.replace("\\", "/")  # Normalize path separators
				
				# Write the preload statement with proper escaping
				file.store_string("\t\"" + escape_string(resource_key) + "\": preload(\"" + escape_string(clean_path) + "\"),\n")
				asset_count += 1
				assets_in_dict += 1
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	return {"assets": asset_count, "current_count": assets_in_dict, "current_dict": current_dict}

func sanitize_name(name: String) -> String:
	# Convert to lowercase and replace problematic characters
	var result = name.to_lower()
	result = result.replace(" ", "_")
	result = result.replace("-", "_")
	result = result.replace(".", "_")
	result = result.replace("(", "_")
	result = result.replace(")", "_")
	result = result.replace("[", "_")
	result = result.replace("]", "_")
	result = result.replace("{", "_")
	result = result.replace("}", "_")
	result = result.replace("@", "_")
	result = result.replace("#", "_")
	result = result.replace("$", "_")
	result = result.replace("%", "_")
	result = result.replace("^", "_")
	result = result.replace("&", "_")
	result = result.replace("*", "_")
	result = result.replace("+", "_")
	result = result.replace("=", "_")
	
	# Remove multiple consecutive underscores
	while result.contains("__"):
		result = result.replace("__", "_")
	
	# Remove leading/trailing underscores
	result = result.strip_edges(true, true)
	if result.begins_with("_"):
		result = result.substr(1)
	if result.ends_with("_"):
		result = result.substr(0, result.length() - 1)
	
	# Ensure it doesn't start with a number
	if result.length() > 0 and result[0].is_valid_int():
		result = "asset_" + result
	
	# Ensure we have a valid identifier
	if result.is_empty():
		result = "unknown_asset"
	
	return result

func escape_string(text: String) -> String:
	# Escape special characters in strings
	var result = text
	result = result.replace("\\", "\\\\")  # Escape backslashes first
	result = result.replace("\"", "\\\"")  # Escape quotes
	result = result.replace("\n", "\\n")   # Escape newlines
	result = result.replace("\t", "\\t")   # Escape tabs
	return result

func add_utility_functions(file: FileAccess):
	file.store_string("# Utility functions for accessing assets\n\n")
	
	file.store_string("# Get a resource by its registry key\n")
	file.store_string("func get_asset(key: String):\n")
	file.store_string("\tif all_assets.has(key):\n")
	file.store_string("\t\treturn all_assets[key]\n")
	file.store_string("\telse:\n")
	file.store_string("\t\tprint(\"AssetRegistry: Warning - Asset not found: \", key)\n")
	file.store_string("\t\treturn null\n\n")
	
	file.store_string("# Get a resource by partial key match\n")
	file.store_string("func find_asset(partial_key: String):\n")
	file.store_string("\tfor key in all_assets.keys():\n")
	file.store_string("\t\tif key.contains(partial_key):\n")
	file.store_string("\t\t\treturn all_assets[key]\n")
	file.store_string("\treturn null\n\n")
	
	file.store_string("# Get all assets with a specific prefix\n")
	file.store_string("func get_assets_by_prefix(prefix: String) -> Array:\n")
	file.store_string("\tvar result = []\n")
	file.store_string("\tfor key in all_assets.keys():\n")
	file.store_string("\t\tif key.begins_with(prefix):\n")
	file.store_string("\t\t\tresult.append({\"key\": key, \"resource\": all_assets[key]})\n")
	file.store_string("\treturn result\n\n")
	
	file.store_string("# Get all available asset keys\n")
	file.store_string("func get_all_keys() -> Array:\n")
	file.store_string("\treturn all_assets.keys()\n\n")
	
	file.store_string("# Check if an asset exists\n")
	file.store_string("func has_asset(key: String) -> bool:\n")
	file.store_string("\treturn all_assets.has(key)\n\n")
	
	file.store_string("# Get asset count\n")
	file.store_string("func get_asset_count() -> int:\n")
	file.store_string("\treturn all_assets.size()\n\n")
	
	file.store_string("# You can still use dynamic loading if needed (though not recommended for exports)\n")
	file.store_string("func load_dynamic(path: String):\n")
	file.store_string("\tif ResourceLoader.exists(path):\n")
	file.store_string("\t\treturn load(path)\n")
	file.store_string("\telse:\n")
	file.store_string("\t\tprint(\"AssetRegistry: Dynamic load failed - path not found: \", path)\n")
	file.store_string("\t\treturn null\n")
