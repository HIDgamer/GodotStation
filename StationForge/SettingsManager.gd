extends Node
class_name SettingsManager

# Signals
signal settings_changed(setting_name, value)

# Current settings
var settings = {}

# Whether settings are fully loaded
var settings_loaded: bool = false

# Settings file path
var settings_file_path: String = "user://settings.cfg"

# Default settings
var default_settings = {
	# Display settings
	"display": {
		"show_grid": true,
		"grid_opacity": 0.3,
		"grid_major_lines": true,
		"grid_major_interval": 5,
		"grid_color": Color(0.5, 0.5, 0.5, 0.2),
		"grid_major_color": Color(0.5, 0.5, 0.5, 0.4),
		"snap_to_grid": true,
		"show_ruler": false,
		"show_coordinates": true
	},
	
	# Editor settings
	"editor": {
		"autosave_interval": 300,  # seconds (5 minutes)
		"autosave_enabled": true,
		"undo_history_size": 50,
		"layer_transparency": 0.3,
		"confirm_deletions": true,
		"auto_center_selection": true
	},
	
	# Map settings
	"map": {
		"default_width": 100,
		"default_height": 100,
		"default_z_levels": 3,
		"map_color_scheme": "default"
	},
	
	# Tool settings
	"tools": {
		"fill_similar_only": true,
		"fill_threshold": 0.1,
		"line_style": "straight",
		"selection_drag_threshold": 3,
		"multi_tile_mode": "rectangle"
	},
	
	# Zone & atmosphere settings
	"atmosphere": {
		"show_zone_overlay": false,
		"zone_overlay_opacity": 0.3,
		"zone_overlay_mode": "type",  # type, pressure, temperature, atmosphere, gravity
		"simulation_speed": 1.0,
		"auto_simulate": false
	},
	
	# Lighting settings
	"lighting": {
		"show_lights_preview": false,
		"ambient_light_level": 0.8,
		"light_attenuation": 1.5,
		"enable_shadows": true,
		"shadow_intensity": 0.7
	},
	
	# Preview mode settings
	"preview": {
		"player_move_speed": 5.0,
		"show_debug_overlay": true,
		"auto_open_doors": true,
		"simulate_atmosphere": true
	},
	
	# UI settings
	"ui": {
		"theme": "dark",
		"toolbar_position": "top",
		"sidebar_width": 250,
		"show_status_bar": true,
		"show_layer_bar": true,
		"show_tool_tooltips": true
	},
	
	# Files and paths
	"paths": {
		"last_save_directory": "user://maps/",
		"last_export_directory": "user://exports/",
		"custom_assets_directory": "user://assets/",
		"recent_files": []
	}
}

func _init():
	# Initialize settings with defaults
	settings = _deep_copy(default_settings)

# Load settings from file
func load_settings() -> bool:
	var config = ConfigFile.new()
	var err = config.load(settings_file_path)
	
	if err != OK:
		# File doesn't exist or can't be loaded
		# Save default settings
		save_settings()
		return false
	
	# Load each section
	for section in config.get_sections():
		if not section in settings:
			settings[section] = {}
		
		for key in config.get_section_keys(section):
			var value = config.get_value(section, key)
			
			# Handle special cases
			if section == "display" and (key == "grid_color" or key == "grid_major_color"):
				# Convert color string to Color
				if typeof(value) == TYPE_STRING:
					value = _string_to_color(value)
			
			# Store value
			settings[section][key] = value
	
	# Mark as loaded
	settings_loaded = true
	
	# Emit signal
	emit_signal("settings_loaded")
	
	return true

# Save settings to file
func save_settings() -> bool:
	var config = ConfigFile.new()
	
	# Save each section
	for section in settings:
		for key in settings[section]:
			var value = settings[section][key]
			
			# Handle special cases
			if section == "display" and (key == "grid_color" or key == "grid_major_color"):
				# Convert Color to string
				if value is Color:
					value = _color_to_string(value)
			
			# Store value
			config.set_value(section, key, value)
	
	# Save to file
	var err = config.save(settings_file_path)
	
	return err == OK

# Reset settings to default
func reset_to_default():
	settings = _deep_copy(default_settings)
	save_settings()
	
	# Emit signals for all settings
	for section in settings:
		for key in settings[section]:
			emit_signal("settings_changed", section + "/" + key, settings[section][key])
	
	emit_signal("settings_loaded")

# Get a setting value
func get_setting(path: String, default_value = null):
	var parts = path.split("/")
	
	if parts.size() != 2:
		return default_value
	
	var section = parts[0]
	var key = parts[1]
	
	if section in settings and key in settings[section]:
		return settings[section][key]
	
	return default_value

# Set a setting value
func set_setting(path: String, value) -> bool:
	var parts = path.split("/")
	
	if parts.size() != 2:
		return false
	
	var section = parts[0]
	var key = parts[1]
	
	if not section in settings:
		settings[section] = {}
	
	settings[section][key] = value
	
	# Emit signal
	emit_signal("settings_changed", path, value)
	
	return true

# Get an entire section of settings
func get_section(section: String) -> Dictionary:
	if section in settings:
		return settings[section]
	
	return {}

# Set multiple settings at once
func set_multiple_settings(settings_dict: Dictionary) -> bool:
	var success = true
	
	for path in settings_dict:
		var result = set_setting(path, settings_dict[path])
		success = success and result
	
	# Save settings
	save_settings()
	
	return success

# Export settings to a separate file
func export_settings(path: String) -> bool:
	var config = ConfigFile.new()
	
	# Save each section
	for section in settings:
		for key in settings[section]:
			var value = settings[section][key]
			
			# Handle special cases
			if section == "display" and (key == "grid_color" or key == "grid_major_color"):
				# Convert Color to string
				if value is Color:
					value = _color_to_string(value)
			
			# Store value
			config.set_value(section, key, value)
	
	# Save to file
	var err = config.save(path)
	
	return err == OK

# Import settings from a file
func import_settings(path: String) -> bool:
	var config = ConfigFile.new()
	var err = config.load(path)
	
	if err != OK:
		return false
	
	# Load each section
	for section in config.get_sections():
		if not section in settings:
			settings[section] = {}
		
		for key in config.get_section_keys(section):
			var value = config.get_value(section, key)
			
			# Handle special cases
			if section == "display" and (key == "grid_color" or key == "grid_major_color"):
				# Convert color string to Color
				if typeof(value) == TYPE_STRING:
					value = _string_to_color(value)
			
			# Store value
			settings[section][key] = value
			
			# Emit signal
			emit_signal("settings_changed", section + "/" + key, value)
	
	# Save settings
	save_settings()
	
	# Emit signal
	emit_signal("settings_loaded")
	
	return true

# Add a recent file to the list
func add_recent_file(path: String):
	if not "paths" in settings or not "recent_files" in settings.paths:
		return
	
	var recent_files = settings.paths.recent_files.duplicate()
	
	# Remove if already exists
	recent_files.erase(path)
	
	# Add to front
	recent_files.insert(0, path)
	
	# Limit to 10 recent files
	if recent_files.size() > 10:
		recent_files.resize(10)
	
	# Update setting
	settings.paths.recent_files = recent_files
	
	# Save settings
	save_settings()
	
	# Emit signal
	emit_signal("settings_changed", "paths/recent_files", recent_files)

# Clear recent files list
func clear_recent_files():
	settings.paths.recent_files = []
	
	# Save settings
	save_settings()
	
	# Emit signal
	emit_signal("settings_changed", "paths/recent_files", [])

# Helper to convert Color to string
func _color_to_string(color: Color) -> String:
	return "#%02X%02X%02X%02X" % [int(color.r * 255), int(color.g * 255), int(color.b * 255), int(color.a * 255)]

# Helper to convert string to Color
func _string_to_color(color_str: String) -> Color:
	if color_str.begins_with("#"):
		color_str = color_str.substr(1)
	
	var r = 0
	var g = 0
	var b = 0
	var a = 255
	
	if color_str.length() >= 6:
		r = ("0x" + color_str.substr(0, 2)).hex_to_int()
		g = ("0x" + color_str.substr(2, 2)).hex_to_int()
		b = ("0x" + color_str.substr(4, 2)).hex_to_int()
		
		if color_str.length() >= 8:
			a = ("0x" + color_str.substr(6, 2)).hex_to_int()
	
	return Color(r / 255.0, g / 255.0, b / 255.0, a / 255.0)

# Deep copy a dictionary
func _deep_copy(dict: Dictionary) -> Dictionary:
	var result = {}
	
	for key in dict:
		var value = dict[key]
		
		if typeof(value) == TYPE_DICTIONARY:
			result[key] = _deep_copy(value)
		elif typeof(value) == TYPE_ARRAY:
			result[key] = value.duplicate(true)
		else:
			result[key] = value
	
	return result
