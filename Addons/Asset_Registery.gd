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
const EXTENSIONS = [".tscn", ".tres", ".png", ".ogg", ".wav", ".mp3", ".json", ".gd"]

func _run():
	var registry_file = FileAccess.open(REGISTRY_PATH, FileAccess.WRITE)
	if registry_file == null:
		printerr("Failed to open registry file for writing at: ", REGISTRY_PATH)
		return

	# Write file header
	registry_file.store_string("# Auto-generated Asset Registry - DO NOT EDIT MANUALLY\n")
	registry_file.store_string("# Generated on " + Time.get_datetime_string_from_system() + "\n\n")
	registry_file.store_string("extends Node\n\n")
	registry_file.store_string("# This dictionary forces Godot to include all assets in the export\n")
	registry_file.store_string("var force_include = {\n")

	var total_assets = 0

	# Scan each directory
	for dir_info in DIRECTORIES:
		var dir_path = dir_info.path
		var key_prefix = dir_info.prefix

		registry_file.store_string("\n\t# Assets from " + dir_path + "\n")
		var dir_assets = scan_directory(dir_path, key_prefix, registry_file)
		total_assets += dir_assets

	registry_file.store_string("}\n\n")

	# Add utility functions
	registry_file.store_string("# You can still use dynamic loading in your game code\n")
	registry_file.store_string("func get_resource(path):\n")
	registry_file.store_string("\treturn load(path)\n\n")

	registry_file.store_string("# Get a list of all preloaded resources by type prefix\n")
	registry_file.store_string("func get_resources_by_prefix(prefix):\n")
	registry_file.store_string("\tvar result = []\n")
	registry_file.store_string("\tfor key in force_include.keys():\n")
	registry_file.store_string("\t\tif key.begins_with(prefix):\n")
	registry_file.store_string("\t\t\tresult.append(key)\n")
	registry_file.store_string("\treturn result\n")

	registry_file.close()

	print("Asset Registry generated with " + str(total_assets) + " resources")

func scan_directory(path: String, key_prefix: String, file: FileAccess) -> int:
	var asset_count = 0
	var dir = DirAccess.open(path)
	if dir == null:
		print("Warning: Could not open directory: " + path)
		return asset_count

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		var full_path = path + "/" + file_name

		if dir.current_is_dir():
			# Recursively scan subdirectories
			var subdir_assets = scan_directory(full_path, key_prefix + file_name + "_", file)
			asset_count += subdir_assets
		else:
			# Check if file has a relevant extension
			for ext in EXTENSIONS:
				if file_name.ends_with(ext):
					var resource_name = file_name.get_basename()
					var resource_key = key_prefix + resource_name
					resource_key = resource_key.replace(" ", "_").to_lower()
					file.store_string("\t\"" + resource_key + "\": preload(\"" + full_path + "\"),\n")
					asset_count += 1
					break

		file_name = dir.get_next()

	dir.list_dir_end()
	return asset_count
