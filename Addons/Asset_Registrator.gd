@tool
extends EditorScript

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

const MAX_PRELOAD_BATCH_SIZE = 3
const SCAN_YIELD_INTERVAL = 100

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

const PRIORITY_PRELOAD_TYPES = ["scenes", "materials", "shaders"]

func _run():
	print("Starting Asset Registry Generation...")
	
	var start_time = Time.get_ticks_msec()
	var asset_registry = {}
	var total_assets = 0
	var cache_data = load_cache()
	
	if should_use_cache(cache_data):
		print("Using cached asset registry data")
		asset_registry = cache_data.registry
		total_assets = cache_data.total_assets
	else:
		print("Scanning directories for assets...")
		for directory in SCAN_DIRECTORIES:
			if DirAccess.dir_exists_absolute(directory):
				print("Scanning directory: ", directory)
				var assets = scan_directory_recursive(directory)
				if assets.size() > 0:
					asset_registry[directory] = assets
					total_assets += count_assets_recursive(assets)
			else:
				print("Directory not found, skipping: ", directory)
		
		save_cache(asset_registry, total_assets)
	
	generate_registry_script(asset_registry, total_assets)
	setup_autoload()
	
	var elapsed_time = Time.get_ticks_msec() - start_time
	print("Asset Registry Generation Complete!")
	print("Total assets found: ", total_assets)
	print("Generation time: ", elapsed_time, "ms")
	print("Registry script created at: ", REGISTRY_SCRIPT_PATH)

func should_use_cache(cache_data) -> bool:
	if cache_data == null:
		return false
	
	for directory in SCAN_DIRECTORIES:
		if DirAccess.dir_exists_absolute(directory):
			var dir_mod_time = get_directory_modification_time(directory)
			if dir_mod_time > cache_data.cache_time:
				return false
	
	return true

func get_directory_modification_time(path: String) -> int:
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
			var sub_assets = scan_directory_recursive(full_path)
			if sub_assets.size() > 0:
				assets[file_name] = sub_assets
		else:
			if is_valid_asset(file_name):
				var asset_type = get_asset_type(file_name)
				if not assets.has(asset_type):
					assets[asset_type] = []
				assets[asset_type].append(full_path)
		
		file_name = dir.get_next()
	
	return assets

func is_valid_asset(filename: String) -> bool:
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
	content += "extends Node\n\n"
	content += "const MAX_FRAME_TIME_MS = 8.0\n"
	content += "const BATCH_SIZE = 2\n"
	content += "const PRIORITY_BATCH_SIZE = 1\n"
	content += "const LOADING_DELAY_MS = 32\n\n"
	content += "var asset_registry = {}\n"
	content += "var preloaded_assets = {}\n"
	content += "var loading_queue = []\n"
	content += "var priority_queue = []\n"
	content += "var threaded_loads = {}\n"
	content += "var is_loading = false\n"
	content += "var loading_progress = 0.0\n"
	content += "var frame_start_time = 0\n"
	content += "var last_load_time = 0\n\n"
	content += "signal loading_complete(loaded_count: int)\n"
	content += "signal loading_progress_updated(progress: float)\n"
	content += "signal asset_loaded(path: String)\n\n"
	content += "func _ready():\n"
	content += "\tload_asset_registry()\n"
	content += "\tsetup_loading_queues()\n"
	content += "\tset_process(false)\n"
	content += "\tcall_deferred(\"start_progressive_loading\")\n\n"
	content += "func load_asset_registry():\n"
	content += "\tasset_registry = " + var_to_str(asset_registry) + "\n\n"
	content += "func setup_loading_queues():\n"
	content += "\tvar priority_assets = []\n"
	content += "\tfor asset_type in [\"scenes\", \"materials\", \"shaders\"]:\n"
	content += "\t\tpriority_assets.append_array(get_assets_by_type(asset_type))\n\n"
	content += "\tpriority_queue = priority_assets.slice(0, min(priority_assets.size(), 15))\n\n"
	content += "\tvar all_assets = get_all_assets()\n"
	content += "\tfor asset_path in all_assets:\n"
	content += "\t\tif not asset_path in priority_queue:\n"
	content += "\t\t\tloading_queue.append(asset_path)\n\n"
	content += "func start_progressive_loading():\n"
	content += "\tif is_loading:\n"
	content += "\t\treturn\n\n"
	content += "\tis_loading = true\n"
	content += "\tlast_load_time = Time.get_ticks_msec()\n"
	content += "\tset_process(true)\n\n"
	content += "func _process(delta):\n"
	content += "\tif not is_loading:\n"
	content += "\t\tset_process(false)\n"
	content += "\t\treturn\n\n"
	content += "\tframe_start_time = Time.get_ticks_msec()\n"
	content += "\tvar current_time = frame_start_time\n\n"
	content += "\tif current_time - last_load_time < LOADING_DELAY_MS:\n"
	content += "\t\treturn\n\n"
	content += "\tprocess_threaded_loads()\n\n"
	content += "\tif get_frame_time_remaining() < 2.0:\n"
	content += "\t\treturn\n\n"
	content += "\tif priority_queue.size() > 0:\n"
	content += "\t\tprocess_priority_batch()\n"
	content += "\telif loading_queue.size() > 0:\n"
	content += "\t\tprocess_regular_batch()\n"
	content += "\telse:\n"
	content += "\t\tcomplete_loading()\n\n"
	content += "\tlast_load_time = Time.get_ticks_msec()\n\n"
	content += "func get_frame_time_remaining() -> float:\n"
	content += "\treturn MAX_FRAME_TIME_MS - (Time.get_ticks_msec() - frame_start_time)\n\n"
	content += "func process_threaded_loads():\n"
	content += "\tvar completed_paths = []\n"
	content += "\tfor path in threaded_loads.keys():\n"
	content += "\t\tvar status = ResourceLoader.load_threaded_get_status(path)\n"
	content += "\t\tif status == ResourceLoader.THREAD_LOAD_LOADED:\n"
	content += "\t\t\tvar resource = ResourceLoader.load_threaded_get(path)\n"
	content += "\t\t\tif resource:\n"
	content += "\t\t\t\tpreloaded_assets[path] = resource\n"
	content += "\t\t\t\tasset_loaded.emit(path)\n"
	content += "\t\t\tcompleted_paths.append(path)\n"
	content += "\t\telif status == ResourceLoader.THREAD_LOAD_FAILED:\n"
	content += "\t\t\tcompleted_paths.append(path)\n\n"
	content += "\tfor path in completed_paths:\n"
	content += "\t\tthreaded_loads.erase(path)\n\n"
	content += "\tupdate_loading_progress()\n\n"
	content += "func process_priority_batch():\n"
	content += "\tvar processed = 0\n"
	content += "\twhile priority_queue.size() > 0 and processed < PRIORITY_BATCH_SIZE and get_frame_time_remaining() > 1.0:\n"
	content += "\t\tvar path = priority_queue.pop_front()\n"
	content += "\t\tstart_threaded_load(path)\n"
	content += "\t\tprocessed += 1\n\n"
	content += "func process_regular_batch():\n"
	content += "\tvar processed = 0\n"
	content += "\twhile loading_queue.size() > 0 and processed < BATCH_SIZE and get_frame_time_remaining() > 1.0:\n"
	content += "\t\tvar path = loading_queue.pop_front()\n"
	content += "\t\tstart_threaded_load(path)\n"
	content += "\t\tprocessed += 1\n\n"
	content += "func start_threaded_load(path: String):\n"
	content += "\tif path in threaded_loads or path in preloaded_assets:\n"
	content += "\t\treturn\n\n"
	content += "\tif not ResourceLoader.exists(path):\n"
	content += "\t\treturn\n\n"
	content += "\tvar error = ResourceLoader.load_threaded_request(path)\n"
	content += "\tif error == OK:\n"
	content += "\t\tthreaded_loads[path] = true\n\n"
	content += "func update_loading_progress():\n"
	content += "\tvar total_assets = get_total_asset_count()\n"
	content += "\tvar loaded_count = preloaded_assets.size()\n"
	content += "\tloading_progress = float(loaded_count) / float(max(total_assets, 1))\n"
	content += "\tloading_progress_updated.emit(loading_progress)\n\n"
	content += "func complete_loading():\n"
	content += "\tis_loading = false\n"
	content += "\tset_process(false)\n"
	content += "\tloading_complete.emit(preloaded_assets.size())\n\n"
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
	content += "func load_asset(path: String) -> Resource:\n"
	content += "\tif preloaded_assets.has(path):\n"
	content += "\t\treturn preloaded_assets[path]\n\n"
	content += "\tif not ResourceLoader.exists(path):\n"
	content += "\t\treturn null\n\n"
	content += "\tvar resource = load(path)\n"
	content += "\tif resource:\n"
	content += "\t\tpreloaded_assets[path] = resource\n"
	content += "\treturn resource\n\n"
	content += "func load_asset_async(path: String, callback: Callable = Callable()):\n"
	content += "\tif preloaded_assets.has(path):\n"
	content += "\t\tif callback.is_valid():\n"
	content += "\t\t\tcallback.call(preloaded_assets[path])\n"
	content += "\t\treturn\n\n"
	content += "\tif not ResourceLoader.exists(path):\n"
	content += "\t\tif callback.is_valid():\n"
	content += "\t\t\tcallback.call(null)\n"
	content += "\t\treturn\n\n"
	content += "\tif path in threaded_loads:\n"
	content += "\t\tif callback.is_valid():\n"
	content += "\t\t\tasset_loaded.connect(func(loaded_path): \n"
	content += "\t\t\t\tif loaded_path == path: callback.call(preloaded_assets.get(path))\n"
	content += "\t\t\t, CONNECT_ONE_SHOT)\n"
	content += "\t\treturn\n\n"
	content += "\tstart_threaded_load(path)\n"
	content += "\tif callback.is_valid():\n"
	content += "\t\tasset_loaded.connect(func(loaded_path): \n"
	content += "\t\t\tif loaded_path == path: callback.call(preloaded_assets.get(path))\n"
	content += "\t\t, CONNECT_ONE_SHOT)\n\n"
	content += "func is_asset_loaded(path: String) -> bool:\n"
	content += "\treturn preloaded_assets.has(path)\n\n"
	content += "func is_asset_loading(path: String) -> bool:\n"
	content += "\treturn path in threaded_loads\n\n"
	content += "func get_loading_progress() -> float:\n"
	content += "\treturn loading_progress\n\n"
	content += "func get_loaded_count() -> int:\n"
	content += "\treturn preloaded_assets.size()\n\n"
	content += "func pause_loading():\n"
	content += "\tset_process(false)\n\n"
	content += "func resume_loading():\n"
	content += "\tif is_loading:\n"
	content += "\t\tset_process(true)\n\n"
	content += "func force_load_asset(path: String) -> Resource:\n"
	content += "\tif preloaded_assets.has(path):\n"
	content += "\t\treturn preloaded_assets[path]\n\n"
	content += "\tif path in threaded_loads:\n"
	content += "\t\tvar resource = ResourceLoader.load_threaded_get(path)\n"
	content += "\t\tif resource:\n"
	content += "\t\t\tpreloaded_assets[path] = resource\n"
	content += "\t\t\tthreaded_loads.erase(path)\n"
	content += "\t\t\treturn resource\n\n"
	content += "\treturn load_asset(path)\n\n"
	
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
