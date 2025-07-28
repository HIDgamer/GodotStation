@tool
extends EditorScript

# Asset Registry Generator Tool for Godot 4.4.1
# Scans project directories and creates an asset registry with performance optimizations

# Configuration
const SCAN_DIRECTORIES = [
	"res://Assets/",
	"res://Scenes/",
	"res://Sound/",
]

const EXCLUDED_EXTENSIONS = [
	".import", ".tmp", ".autosave", ".backup"
]

const REGISTRY_SCRIPT_PATH = "res://AssetRegistry.gd"
const REGISTRY_AUTOLOAD_NAME = "AssetRegistry"
const CACHE_FILE_PATH = "res://.asset_registry_cache.dat"

# Performance settings
const MAX_PRELOAD_BATCH_SIZE = 25
const SCAN_YIELD_INTERVAL = 100

# Asset type categories
const ASSET_TYPES = {
	"textures": [".png", ".jpg", ".jpeg", ".bmp", ".tga", ".webp", ".svg", ".exr", ".hdr"],
	"audio": [".mp3", ".wav", ".ogg", ".flac", ".aac"],
	"models": [".glb", ".gltf", ".fbx", ".obj", ".dae", ".blend"],
	"scenes": [".tscn", ".scn"],
	"scripts": [".gd", ".cs"],
	"materials": [".tres", ".res"],
	"fonts": [".ttf", ".otf", ".woff", ".woff2"],
	"shaders": [".gdshader", ".tres"],
	"other": []
}

# Asset types that should be preloaded immediately for better performance
const PRIORITY_PRELOAD_TYPES = ["scenes", "materials", "shaders"]

func _run():
	print("Starting Asset Registry Generation...")
	
	var start_time = Time.get_ticks_msec()
	var asset_registry = {}
	var total_assets = 0
	var cache_data = load_cache()
	
	# Check if we can use cached data
	if should_use_cache(cache_data):
		print("Using cached asset registry data")
		asset_registry = cache_data.registry
		total_assets = cache_data.total_assets
	else:
		print("Scanning directories for assets...")
		# Scan all specified directories
		for directory in SCAN_DIRECTORIES:
			if DirAccess.dir_exists_absolute(directory):
				print("Scanning directory: ", directory)
				var assets = scan_directory_recursive(directory)
				if assets.size() > 0:
					asset_registry[directory] = assets
					total_assets += count_assets_recursive(assets)
			else:
				print("Directory not found, skipping: ", directory)
		
		# Save cache for next time
		save_cache(asset_registry, total_assets)
	
	# Generate the optimized registry script
	generate_registry_script(asset_registry, total_assets)
	
	# Add to autoload if not already present
	setup_autoload()
	
	var elapsed_time = Time.get_ticks_msec() - start_time
	print("Asset Registry Generation Complete!")
	print("Total assets found: ", total_assets)
	print("Generation time: ", elapsed_time, "ms")
	print("Registry script created at: ", REGISTRY_SCRIPT_PATH)

func should_use_cache(cache_data) -> bool:
	if cache_data == null:
		return false
	
	# Check if any monitored directories have been modified since cache was created
	for directory in SCAN_DIRECTORIES:
		if DirAccess.dir_exists_absolute(directory):
			var dir_mod_time = get_directory_modification_time(directory)
			if dir_mod_time > cache_data.cache_time:
				return false
	
	return true

func get_directory_modification_time(path: String) -> int:
	# Get the most recent modification time in the directory tree
	var latest_time = 0
	var dir = DirAccess.open(path)
	if dir == null:
		return 0
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		var full_path = path + "/" + file_name
		if dir.current_is_dir() and not file_name.begins_with("."):
			var subdir_time = get_directory_modification_time(full_path)
			latest_time = max(latest_time, subdir_time)
		else:
			var file_time = FileAccess.get_modified_time(full_path)
			latest_time = max(latest_time, file_time)
		file_name = dir.get_next()
	
	return latest_time

func load_cache():
	if not FileAccess.file_exists(CACHE_FILE_PATH):
		return null
	
	var file = FileAccess.open(CACHE_FILE_PATH, FileAccess.READ)
	if file == null:
		return null
	
	var cache_data = file.get_var()
	file.close()
	return cache_data

func save_cache(registry: Dictionary, total_assets: int):
	var cache_data = {
		"registry": registry,
		"total_assets": total_assets,
		"cache_time": Time.get_unix_time_from_system()
	}
	
	var file = FileAccess.open(CACHE_FILE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_var(cache_data)
		file.close()

func count_assets_recursive(data) -> int:
	var count = 0
	if data is Array:
		return data.size()
	elif data is Dictionary:
		for key in data:
			count += count_assets_recursive(data[key])
	return count

func scan_directory_recursive(path: String) -> Dictionary:
	var assets = {}
	var dir = DirAccess.open(path)
	
	if dir == null:
		print("Failed to open directory: ", path)
		return assets
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		var full_path = path + "/" + file_name
		
		if dir.current_is_dir() and not file_name.begins_with("."):
			# Recursively scan subdirectories
			var sub_assets = scan_directory_recursive(full_path)
			if sub_assets.size() > 0:
				assets[file_name] = sub_assets
		else:
			# Check if it's a valid asset file
			if is_valid_asset(file_name):
				var asset_type = get_asset_type(file_name)
				if not assets.has(asset_type):
					assets[asset_type] = []
				assets[asset_type].append(full_path)
		
		file_name = dir.get_next()
	
	return assets

func is_valid_asset(filename: String) -> bool:
	# Skip hidden files and excluded extensions
	if filename.begins_with("."):
		return false
	
	for excluded_ext in EXCLUDED_EXTENSIONS:
		if filename.ends_with(excluded_ext):
			return false
	
	return true

func get_asset_type(filename: String) -> String:
	var extension = "." + filename.get_extension().to_lower()
	
	for type_name in ASSET_TYPES:
		if extension in ASSET_TYPES[type_name]:
			return type_name
	
	return "other"

func generate_registry_script(asset_registry: Dictionary, total_count: int):
	var script_content = generate_script_content(asset_registry, total_count)
	
	var file = FileAccess.open(REGISTRY_SCRIPT_PATH, FileAccess.WRITE)
	if file == null:
		print("ERROR: Failed to create registry script file!")
		return
	
	file.store_string(script_content)
	file.close()
	
	print("Registry script written successfully")

func generate_script_content(asset_registry: Dictionary, total_count: int) -> String:
	var content = ""
	content += "# Auto-generated Asset Registry for Godot Export\n"
	content += "# Generated on: " + Time.get_datetime_string_from_system() + "\n"
	content += "# Total assets: " + str(total_count) + "\n\n"
	content += "extends Node\n\n"
	content += "# Performance configuration\n"
	content += "const MAX_PRELOAD_BATCH_SIZE = 25\n"
	content += "const PRIORITY_TYPES = " + str(PRIORITY_PRELOAD_TYPES) + "\n\n"
	content += "var asset_registry = {}\n"
	content += "var preloaded_assets = {}\n"
	content += "var background_load_queue = []\n"
	content += "var is_background_loading = false\n"
	content += "var loading_progress = 0.0\n\n"
	content += "signal loading_complete(loaded_count: int)\n"
	content += "signal loading_progress_updated(progress: float)\n\n"
	content += "func _ready():\n"
	content += "\tprint('Asset Registry initializing with ', get_total_asset_count(), ' assets')\n"
	content += "\tload_asset_registry()\n"
	content += "\t# Start with priority assets only for faster startup\n"
	content += "\tpreload_priority_assets()\n"
	content += "\t# Queue remaining assets for background loading\n"
	content += "\tqueue_background_loading()\n\n"
	content += "func load_asset_registry():\n"
	content += "\tasset_registry = " + var_to_str(asset_registry) + "\n\n"
	content += "func preload_priority_assets():\n"
	content += "\tvar priority_assets = []\n"
	content += "\tfor asset_type in PRIORITY_TYPES:\n"
	content += "\t\tpriority_assets.append_array(get_assets_by_type(asset_type))\n\n"
	content += "\tprint('Preloading ', priority_assets.size(), ' priority assets...')\n"
	content += "\tvar loaded_count = 0\n\n"
	content += "\tfor i in range(priority_assets.size()):\n"
	content += "\t\tvar asset_path = priority_assets[i]\n"
	content += "\t\tif ResourceLoader.exists(asset_path):\n"
	content += "\t\t\tvar resource = load(asset_path)\n"
	content += "\t\t\tif resource != null:\n"
	content += "\t\t\t\tpreloaded_assets[asset_path] = resource\n"
	content += "\t\t\t\tloaded_count += 1\n\n"
	content += "\tprint('Priority assets loaded: ', loaded_count)\n\n"
	content += "func queue_background_loading():\n"
	content += "\tvar all_assets = get_all_assets()\n"
	content += "\tfor asset_path in all_assets:\n"
	content += "\t\tif not preloaded_assets.has(asset_path):\n"
	content += "\t\t\tbackground_load_queue.append(asset_path)\n\n"
	content += "\tif background_load_queue.size() > 0:\n"
	content += "\t\tprint('Queued ', background_load_queue.size(), ' assets for background loading')\n"
	content += "\t\tstart_background_loading()\n\n"
	content += "func start_background_loading():\n"
	content += "\tif is_background_loading:\n"
	content += "\t\treturn\n\n"
	content += "\tis_background_loading = true\n"
	content += "\t# Use a timer to process assets in chunks without blocking\n"
	content += "\tvar timer = Timer.new()\n"
	content += "\tadd_child(timer)\n"
	content += "\ttimer.wait_time = 0.016  # ~60fps\n"
	content += "\ttimer.timeout.connect(_process_background_batch)\n"
	content += "\ttimer.start()\n\n"
	content += "func _process_background_batch():\n"
	content += "\tvar total_to_load = background_load_queue.size() + preloaded_assets.size()\n"
	content += "\tvar batch_processed = 0\n\n"
	content += "\t# Process a batch of assets\n"
	content += "\twhile background_load_queue.size() > 0 and batch_processed < MAX_PRELOAD_BATCH_SIZE:\n"
	content += "\t\tvar asset_path = background_load_queue.pop_front()\n"
	content += "\t\tif ResourceLoader.exists(asset_path) and not preloaded_assets.has(asset_path):\n"
	content += "\t\t\tvar resource = load(asset_path)\n"
	content += "\t\t\tif resource != null:\n"
	content += "\t\t\t\tpreloaded_assets[asset_path] = resource\n"
	content += "\t\tbatch_processed += 1\n\n"
	content += "\t# Update progress\n"
	content += "\tvar loaded_count = preloaded_assets.size()\n"
	content += "\tloading_progress = float(loaded_count) / float(total_to_load)\n"
	content += "\tloading_progress_updated.emit(loading_progress)\n\n"
	content += "\t# Check if loading is complete\n"
	content += "\tif background_load_queue.is_empty():\n"
	content += "\t\tis_background_loading = false\n"
	content += "\t\t# Stop and remove the timer\n"
	content += "\t\tfor child in get_children():\n"
	content += "\t\t\tif child is Timer:\n"
	content += "\t\t\t\tchild.queue_free()\n"
	content += "\t\t\t\tbreak\n"
	content += "\t\tloading_complete.emit(loaded_count)\n"
	content += "\t\tprint('Background loading complete. Total loaded: ', loaded_count)\n\n"
	content += "func get_assets_by_type(asset_type: String) -> Array:\n"
	content += "\tvar result = []\n"
	content += "\tfor directory in asset_registry:\n"
	content += "\t\t_collect_assets_by_type_recursive(asset_registry[directory], asset_type, result)\n"
	content += "\treturn result\n\n"
	content += "func _collect_assets_by_type_recursive(data, asset_type: String, result: Array):\n"
	content += "\tif data is Dictionary:\n"
	content += "\t\tif data.has(asset_type) and data[asset_type] is Array:\n"
	content += "\t\t\tresult.append_array(data[asset_type])\n"
	content += "\t\tfor key in data:\n"
	content += "\t\t\tif data[key] is Dictionary:\n"
	content += "\t\t\t\t_collect_assets_by_type_recursive(data[key], asset_type, result)\n\n"
	content += "func get_all_assets() -> Array:\n"
	content += "\tvar all_assets = []\n"
	content += "\tfor directory in asset_registry:\n"
	content += "\t\t_collect_assets_recursive(asset_registry[directory], all_assets)\n"
	content += "\treturn all_assets\n\n"
	content += "func _collect_assets_recursive(data, all_assets: Array):\n"
	content += "\tif data is Array:\n"
	content += "\t\tall_assets.append_array(data)\n"
	content += "\telif data is Dictionary:\n"
	content += "\t\tfor key in data:\n"
	content += "\t\t\t_collect_assets_recursive(data[key], all_assets)\n\n"
	content += "func get_total_asset_count() -> int:\n"
	content += "\treturn get_all_assets().size()\n\n"
	content += "func asset_exists(path: String) -> bool:\n"
	content += "\treturn ResourceLoader.exists(path)\n\n"
	content += "func load_asset(path: String) -> Resource:\n"
	content += "\t# Try preloaded cache first\n"
	content += "\tif preloaded_assets.has(path):\n"
	content += "\t\treturn preloaded_assets[path]\n"
	content += "\t# Load on demand if not cached\n"
	content += "\tif asset_exists(path):\n"
	content += "\t\tvar resource = load(path)\n"
	content += "\t\t# Cache for future use\n"
	content += "\t\tif resource != null:\n"
	content += "\t\t\tpreloaded_assets[path] = resource\n"
	content += "\t\treturn resource\n"
	content += "\treturn null\n\n"
	content += "func get_assets_in_directory(directory: String) -> Dictionary:\n"
	content += "\tif asset_registry.has(directory):\n"
	content += "\t\treturn asset_registry[directory]\n"
	content += "\treturn {}\n\n"
	content += "func get_preloaded_asset(path: String) -> Resource:\n"
	content += "\tif preloaded_assets.has(path):\n"
	content += "\t\treturn preloaded_assets[path]\n"
	content += "\treturn null\n\n"
	content += "func is_asset_preloaded(path: String) -> bool:\n"
	content += "\treturn preloaded_assets.has(path)\n\n"
	content += "func get_preloaded_count() -> int:\n"
	content += "\treturn preloaded_assets.size()\n\n"
	content += "func get_loading_progress() -> float:\n"
	content += "\treturn loading_progress\n\n"
	content += "func is_loading_complete() -> bool:\n"
	content += "\treturn not is_background_loading and background_load_queue.is_empty()\n\n"
	content += "# Force all assets to be loaded immediately (use sparingly)\n"
	content += "func force_load_all_assets():\n"
	content += "\tif is_background_loading:\n"
	content += "\t\tprint('Stopping background loading to force immediate load')\n"
	content += "\t\tis_background_loading = false\n\n"
	content += "\tvar remaining = get_all_assets().size() - preloaded_assets.size()\n"
	content += "\tif remaining > 0:\n"
	content += "\t\tprint('Force loading ', remaining, ' remaining assets...')\n"
	content += "\t\tfor asset_path in get_all_assets():\n"
	content += "\t\t\tif not preloaded_assets.has(asset_path):\n"
	content += "\t\t\t\tload_asset(asset_path)\n"
	
	return content

func setup_autoload():
	var project_settings = ProjectSettings
	var autoload_path = "autoload/" + REGISTRY_AUTOLOAD_NAME
	
	if not project_settings.has_setting(autoload_path):
		project_settings.set_setting(autoload_path, REGISTRY_SCRIPT_PATH)
		var error = project_settings.save()
		if error == OK:
			print("Added AssetRegistry to autoload successfully")
		else:
			print("Failed to save project settings. You may need to add the autoload manually.")
			print("Go to Project Settings > Autoload and add:")
			print("Name: ", REGISTRY_AUTOLOAD_NAME)
			print("Path: ", REGISTRY_SCRIPT_PATH)
	else:
		print("AssetRegistry autoload already exists")

func print_asset_summary(asset_registry: Dictionary):
	print("\n=== ASSET REGISTRY SUMMARY ===")
	for directory in asset_registry:
		print("Directory: ", directory)
		print_assets_recursive(asset_registry[directory], "  ")
	print("==============================\n")

func print_assets_recursive(data, indent: String):
	if data is Dictionary:
		for key in data:
			if data[key] is Array:
				var count = data[key].size()
				print(indent, key, ": ", count, " files")
			elif data[key] is Dictionary:
				print(indent, key, "/ (subdirectory)")
				print_assets_recursive(data[key], indent + "  ")

func export_asset_list_to_file(asset_registry: Dictionary):
	var export_path = "res://asset_list.txt"
	var file = FileAccess.open(export_path, FileAccess.WRITE)
	
	if file == null:
		print("Failed to create asset list file")
		return
	
	file.store_line("COMPLETE ASSET LIST")
	file.store_line("Generated: " + Time.get_datetime_string_from_system())
	file.store_line("==================================================")
	
	for directory in asset_registry:
		file.store_line("\nDIRECTORY: " + directory)
		export_assets_recursive(file, asset_registry[directory], "  ")
	
	file.close()
	print("Asset list exported to: ", export_path)

func export_assets_recursive(file: FileAccess, data, indent: String):
	if data is Dictionary:
		for key in data:
			if data[key] is Array:
				file.store_line(indent + key.to_upper() + ":")
				for asset_path in data[key]:
					file.store_line(indent + "  " + asset_path)
			elif data[key] is Dictionary:
				file.store_line(indent + key + "/ (subdirectory)")
				export_assets_recursive(file, data[key], indent + "  ")
