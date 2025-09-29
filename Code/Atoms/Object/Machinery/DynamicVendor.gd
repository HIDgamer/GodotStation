extends BaseVendor
class_name DynamicVendor

# Dynamic population settings
@export_group("Dynamic Population")
@export var asset_folder_path: String = "res://Scenes/Items/"
@export var recursive_scan: bool = true
@export var auto_populate_on_ready: bool = true
@export var refresh_interval: float = 0.0  # 0 = no auto refresh

# Stock settings for dynamic items
@export_group("Dynamic Stock Settings")
@export var default_stock: int = 5
@export var default_max_stock: int = 10
@export var default_price: int = 0
@export var stock_variance: float = 0.2  # Random variance in stock amounts

# Filtering
@export_group("Item Filtering")
@export var included_categories: Array[String] = []  # Empty = include all
@export var excluded_categories: Array[String] = []
@export var name_filter_patterns: Array[String] = []  # Regex patterns
@export var exclude_name_patterns: Array[String] = []

# Category mapping
@export_group("Category Settings")
@export var auto_detect_categories: bool = true
@export var default_category: String = "General"
@export var category_keywords: Dictionary = {
	"Medical": ["med", "health", "heal", "bandage", "syringe"],
	"Weapons": ["gun", "rifle", "pistol", "weapon", "ammo"],
	"Tools": ["tool", "wrench", "scanner", "device"],
	"Food": ["food", "drink", "meal", "snack"],
	"Electronics": ["electronic", "device", "computer", "tablet"]
}

# Debug settings
@export_group("Debug")
@export var enable_debug: bool = true

# Internal state
var last_scan_time: float = 0.0
var scan_cache: Dictionary = {}
var refresh_timer: Timer

func _ready():
	print("*** DynamicVendor _ready() called ***")
	super()
	
	# Setup refresh timer if enabled
	if refresh_interval > 0.0:
		refresh_timer = Timer.new()
		refresh_timer.wait_time = refresh_interval
		refresh_timer.timeout.connect(_on_refresh_timer_timeout)
		refresh_timer.autostart = true
		add_child(refresh_timer)
	
	print("*** Auto populate on ready: %s ***" % auto_populate_on_ready)

func initialize_vendor():
	"""Initialize the dynamic vendor"""
	print("*** initialize_vendor() called ***")
	super.initialize_vendor()
	
	if auto_populate_on_ready:
		print("*** Calling populate_from_asset_registry from initialize_vendor ***")
		populate_from_asset_registry()

func populate_from_asset_registry():
	"""Populate vendor items from the asset registry"""
	print("*** POPULATE START - STEP 1 ***")
	
	# Use a simple direct file scan approach
	try_direct_file_scan()
	
	print("*** POPULATE END - FINAL STEP ***")

func try_direct_file_scan():
	"""Simple, direct file scanning method"""
	print("*** DIRECT FILE SCAN START ***")
	print("*** Scanning folder: %s ***" % asset_folder_path)
	
	# Clear existing items
	if available_items == null:
		available_items = []
	
	var initial_count = available_items.size()
	print("*** Initial items count: %d ***" % initial_count)
	available_items.clear()
	print("*** Cleared items, new count: %d ***" % available_items.size())
	
	# Check if the folder exists
	print("*** Checking if folder exists ***")
	var dir = DirAccess.open("res://")
	if not dir:
		print("*** ERROR: Cannot open res:// ***")
		return
	
	# Clean up the path
	var clean_path = asset_folder_path.replace("res://", "").strip_edges()
	if clean_path.ends_with("/"):
		clean_path = clean_path.substr(0, clean_path.length() - 1)
	
	print("*** Clean path: '%s' ***" % clean_path)
	
	if not dir.dir_exists(clean_path):
		print("*** ERROR: Directory doesn't exist: %s ***" % clean_path)
		return
	
	print("*** Directory exists! ***")
	
	# Get all .tscn files
	var tscn_files = []
	find_tscn_files(clean_path, tscn_files)
	
	print("*** Found %d .tscn files ***" % tscn_files.size())
	
	# Add each file as an item
	for file_path in tscn_files:
		print("*** Processing: %s ***" % file_path)
		add_simple_item(file_path)
	
	print("*** Final items count: %d ***" % available_items.size())
	print("*** Items array contents: %s ***" % str(available_items))
	
	# Force UI refresh if available
	if ui_instance:
		print("*** Refreshing UI ***")
		ui_instance.refresh_items()
	else:
		print("*** No UI instance available ***")

func find_tscn_files(folder_path: String, files_array: Array):
	"""Find all .tscn files in folder"""
	print("*** Searching in folder: %s ***" % folder_path)
	
	var dir = DirAccess.open("res://" + folder_path)
	if not dir:
		print("*** Cannot open folder: %s ***" % folder_path)
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		print("*** Found: %s (is_dir: %s) ***" % [file_name, dir.current_is_dir()])
		
		if dir.current_is_dir() and not file_name.begins_with(".") and recursive_scan:
			# Recursive scan
			var subfolder = folder_path + "/" + file_name
			find_tscn_files(subfolder, files_array)
		elif file_name.ends_with(".tscn"):
			var full_path = "res://" + folder_path + "/" + file_name
			files_array.append(full_path)
			print("*** Added .tscn: %s ***" % full_path)
		
		file_name = dir.get_next()

func add_simple_item(file_path: String):
	"""Add an item in the simplest way possible"""
	print("*** Adding item: %s ***" % file_path)
	
	# Create a simple item dictionary
	var item_name = file_path.get_file().get_basename().capitalize().replace("_", " ")
	
	var item_dict = {
		"path": file_path,
		"name": item_name,
		"stock": default_stock,
		"max_stock": default_max_stock,
		"price": default_price,
		"category": default_category
	}
	
	available_items.append(item_dict)
	print("*** Item added. New count: %d ***" % available_items.size())

# Simple test function
func force_scan():
	"""Force a scan for testing"""
	print("*** FORCE SCAN TRIGGERED ***")
	populate_from_asset_registry()

func _on_refresh_timer_timeout():
	"""Handle automatic refresh timer"""
	populate_from_asset_registry()

# Keep the rest of the original methods for compatibility
func refresh_from_registry():
	"""Refresh items from the asset registry"""
	populate_from_asset_registry()

func set_folder_path(new_path: String):
	"""Change the folder path and refresh"""
	asset_folder_path = new_path
	populate_from_asset_registry()

func get_scan_statistics() -> Dictionary:
	"""Get statistics about the last scan"""
	return {
		"total_items": available_items.size(),
		"last_scan_time": last_scan_time,
		"folder_path": asset_folder_path,
		"recursive_scan": recursive_scan,
		"cache_size": scan_cache.size()
	}

func export_configuration() -> Dictionary:
	"""Export dynamic vendor configuration"""
	var config = {
		"vendor_type": "dynamic",
		"vendor_name": vendor_name,
		"vendor_description": vendor_description,
		"asset_folder_path": asset_folder_path,
		"recursive_scan": recursive_scan,
		"default_stock": default_stock,
		"default_max_stock": default_max_stock,
		"default_price": default_price,
		"stock_variance": stock_variance,
		"included_categories": included_categories,
		"excluded_categories": excluded_categories,
		"name_filter_patterns": name_filter_patterns,
		"exclude_name_patterns": exclude_name_patterns,
		"category_keywords": category_keywords,
		"refresh_interval": refresh_interval
	}
	
	return config

func import_configuration(config: Dictionary):
	"""Import dynamic vendor configuration"""
	if config.get("vendor_type") != "dynamic":
		print("Error: Configuration is not for dynamic vendor")
		return false
	
	# Apply settings
	asset_folder_path = config.get("asset_folder_path", asset_folder_path)
	recursive_scan = config.get("recursive_scan", recursive_scan)
	default_stock = config.get("default_stock", default_stock)
	default_max_stock = config.get("default_max_stock", default_max_stock)
	default_price = config.get("default_price", default_price)
	stock_variance = config.get("stock_variance", stock_variance)
	included_categories = config.get("included_categories", included_categories)
	excluded_categories = config.get("excluded_categories", excluded_categories)
	name_filter_patterns = config.get("name_filter_patterns", name_filter_patterns)
	exclude_name_patterns = config.get("exclude_name_patterns", exclude_name_patterns)
	category_keywords = config.get("category_keywords", category_keywords)
	refresh_interval = config.get("refresh_interval", refresh_interval)
	
	# Refresh with new settings
	populate_from_asset_registry()
	
	return true
