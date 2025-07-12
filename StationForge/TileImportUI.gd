extends Control
class_name TileImportUI

# References
var editor_ref = null
var import_system = null
var tile_palette = null

# UI Elements
@onready var import_dialog = $ImportDialog
@onready var category_selector = $ImportDialog/VBoxContainer/CategorySelector
@onready var slice_checkbox = $ImportDialog/VBoxContainer/SliceOptions/SliceCheckbox
@onready var slice_width = $ImportDialog/VBoxContainer/SliceOptions/SizeContainer/WidthSpinBox
@onready var slice_height = $ImportDialog/VBoxContainer/SliceOptions/SizeContainer/HeightSpinBox
@onready var autotile_checkbox = $ImportDialog/VBoxContainer/AutotileOptions/AutotileCheckbox
@onready var autotile_type = $ImportDialog/VBoxContainer/AutotileOptions/TypeSelector
@onready var preview_container = $ImportDialog/VBoxContainer/PreviewContainer
@onready var file_button = $ImportDialog/VBoxContainer/FileSelectButton
@onready var import_button = $ImportDialog/VBoxContainer/ButtonContainer/ImportButton
@onready var cancel_button = $ImportDialog/VBoxContainer/ButtonContainer/CancelButton
@onready var status_label = $ImportDialog/VBoxContainer/StatusLabel

# File selection
var selected_files = []
var current_preview_image = null

func _ready():
	print("TileImportUI: Ready")
	
	# Connect signals
	if file_button:
		file_button.pressed.connect(Callable(self, "_on_file_button_pressed"))
	
	if import_button:
		import_button.pressed.connect(Callable(self, "_on_import_button_pressed"))
	
	if cancel_button:
		cancel_button.pressed.connect(Callable(self, "_on_cancel_button_pressed"))
	
	if slice_checkbox:
		slice_checkbox.toggled.connect(Callable(self, "_on_slice_checkbox_toggled"))
	
	if autotile_checkbox:
		autotile_checkbox.toggled.connect(Callable(self, "_on_autotile_checkbox_toggled"))
	
	# Set up category selector
	_setup_category_selector()
	
	# Set up autotile type selector
	_setup_autotile_selector()
	
	# Initialize UI state
	_update_ui_state()
	
	# Hide status label initially
	if status_label:
		status_label.hide()

func initialize(p_editor_ref, p_import_system, p_tile_palette):
	editor_ref = p_editor_ref
	import_system = p_import_system
	tile_palette = p_tile_palette
	
	print("TileImportUI: Initialized with references - editor:", editor_ref != null, 
		  " import_system:", import_system != null, " tile_palette:", tile_palette != null)
	
	# Connect import system signals
	if import_system:
		import_system.connect("tile_import_completed", Callable(self, "_on_tile_import_completed"))
		import_system.connect("import_failed", Callable(self, "_on_import_failed"))

func show_dialog():
	if not import_dialog:
		push_error("TileImportUI: Import dialog not found")
		return
		
	print("TileImportUI: Showing import dialog")
	
	# Reset selected files
	selected_files.clear()
	file_button.text = "Select Files..."
	
	# Reset preview
	_clear_preview()
	
	# Update UI state
	_update_ui_state()
	
	# Hide status message
	if status_label:
		status_label.hide()
	
	import_dialog.popup_centered(Vector2i(800, 600))

func _setup_category_selector():
	if not category_selector:
		push_error("TileImportUI: Category selector not found")
		return
		
	category_selector.clear()
	
	# Add tile categories
	category_selector.add_item("Floor Tiles", 0)
	category_selector.add_item("Wall Tiles", 1)
	category_selector.add_item("Object Tiles", 2)
	category_selector.add_item("Zone Tiles", 3)
	
	# Set default
	category_selector.selected = 0

func _setup_autotile_selector():
	if not autotile_type:
		push_error("TileImportUI: Autotile type selector not found")
		return
		
	autotile_type.clear()
	
	# Add autotile types
	autotile_type.add_item("None", 0)
	autotile_type.add_item("Wang 2x2 (Simple Corner Match)", 1)
	autotile_type.add_item("Wang 3x3 (Classic Autotile)", 2)
	autotile_type.add_item("Corner Match (16-Tile)", 3)
	autotile_type.add_item("47-bit Terrain", 4)
	
	# Set default
	autotile_type.selected = 2  # Default to 3x3 as it's most common

func _update_ui_state():
	# Update based on current options
	if slice_checkbox:
		var slice_enabled = slice_checkbox.button_pressed

		if slice_width:
			slice_width.editable = slice_enabled
		
		if slice_height:
			slice_height.editable = slice_enabled
	
	if autotile_checkbox:
		var autotile_enabled = autotile_checkbox.button_pressed

		if autotile_type:
			autotile_type.disabled = not autotile_enabled
	
	# Update import button state
	if import_button:
		import_button.disabled = selected_files.size() == 0

func _on_file_button_pressed():
	print("TileImportUI: File button pressed")
	
	# Show file dialog
	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Image Files", "*.json ; Metadata Files"])
	file_dialog.title = "Select Files to Import"
	
	# Position it in the center of the window
	var viewport_size = get_viewport().get_visible_rect().size
	file_dialog.position = Vector2i(viewport_size.x / 2 - 400, viewport_size.y / 2 - 300)
	file_dialog.size = Vector2i(800, 600)
	
	file_dialog.connect("files_selected", Callable(self, "_on_files_selected"))
	
	# Add to UI and show
	add_child(file_dialog)
	file_dialog.popup()
	
	# Make sure dialog is freed after use
	file_dialog.connect("close_requested", Callable(file_dialog, "queue_free"))
	file_dialog.connect("canceled", Callable(file_dialog, "queue_free"))

func _on_files_selected(paths):
	print("TileImportUI: Files selected: ", paths)
	selected_files = paths
	
	# Update file button text
	if file_button:
		if selected_files.size() == 1:
			file_button.text = selected_files[0].get_file()
		else:
			file_button.text = str(selected_files.size()) + " files selected"
	
	# Show preview of first image if possible
	_update_preview()
	
	# Update UI state
	_update_ui_state()
	
	# Check if we have the image processor
	if import_system and import_system.image_processor:
		# Try to auto-detect sizes
		if selected_files.size() > 0 and selected_files[0].get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
			var first_file = selected_files[0]
			var image = import_system.image_processor.process_image(first_file)
			if image:
				var detected_size = import_system.image_processor.detect_tile_size(image)
				if detected_size.x > 0 and detected_size.y > 0:
					print("TileImportUI: Auto-detected tile size: ", detected_size)
					slice_width.value = detected_size.x
					slice_height.value = detected_size.y
					
					# Enable slicing if multiple tiles detected
					var cols = image.get_width() / detected_size.x
					var rows = image.get_height() / detected_size.y
					if cols > 1 or rows > 1:
						slice_checkbox.button_pressed = true
						_on_slice_checkbox_toggled(true)
					else:
						slice_checkbox.button_pressed = false
						_on_slice_checkbox_toggled(false)

func _update_preview():
	# Clear current preview
	_clear_preview()
	
	if selected_files.size() == 0:
		return
	
	# Get first file
	var first_file = selected_files[0]
	var ext = first_file.get_extension().to_lower()
	
	if ext in ["png", "jpg", "jpeg", "webp"]:
		# Load and show image preview
		var image = Image.new()
		var err = image.load(first_file)
		
		if err == OK:
			var texture = ImageTexture.create_from_image(image)
			
			# Create texture rect
			var texture_rect = TextureRect.new()
			texture_rect.texture = texture
			texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			texture_rect.custom_minimum_size = Vector2(300, 200)
			
			# Add to preview container
			preview_container.add_child(texture_rect)
			
			current_preview_image = image
			
			# Try to detect if this is a sprite sheet
			if slice_checkbox and slice_width and slice_height:
				var auto_detect_size = _detect_tile_size(image)
				
				if auto_detect_size != Vector2i.ZERO:
					slice_checkbox.button_pressed = true
					slice_width.value = auto_detect_size.x
					slice_height.value = auto_detect_size.y
					
					# Show slice preview
					_show_slice_preview(image, auto_detect_size)

func _clear_preview():
	current_preview_image = null
	
	# Remove all children from preview container
	for child in preview_container.get_children():
		preview_container.remove_child(child)
		child.queue_free()

func _detect_tile_size(image) -> Vector2i:
	# Use image processor if available
	if import_system and import_system.image_processor and import_system.image_processor.has_method("detect_tile_size"):
		return import_system.image_processor.detect_tile_size(image)
	
	# Fallback if no image processor
	# Try to detect tile size from image
	var width = image.get_width()
	var height = image.get_height()
	
	# Check if image dimensions are divisible by common tile sizes
	var possible_sizes = [16, 24, 32, 48, 64, 96, 128]
	
	for size in possible_sizes:
		if width % size == 0 and height % size == 0:
			# Check if the image has multiple tiles
			if width > size or height > size:
				return Vector2i(size, size)
	
	return Vector2i.ZERO

func _show_slice_preview(image, tile_size: Vector2i):
	# Create a grid overlay instance
	var grid_container = GridOverlay.new()
	grid_container.custom_minimum_size = Vector2(200, 200)
	grid_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Set properties
	grid_container.image_size = Vector2(image.get_width(), image.get_height())
	grid_container.tile_size = Vector2(tile_size)
	
	# Add to preview container
	preview_container.add_child(grid_container)
	
	# Add label with information
	var info_label = Label.new()
	var cols = image.get_width() / tile_size.x
	var rows = image.get_height() / tile_size.y
	info_label.text = "Grid: " + str(cols) + "x" + str(rows) + " tiles"
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_container.add_child(info_label)

func _on_slice_checkbox_toggled(button_pressed):
	_update_ui_state()
	
	# Update preview if needed
	if button_pressed and current_preview_image:
		var tile_size = Vector2i(slice_width.value, slice_height.value)
		_show_slice_preview(current_preview_image, tile_size)
	else:
		# Update preview without grid
		_update_preview()

func _on_autotile_checkbox_toggled(button_pressed):
	_update_ui_state()

func _on_import_button_pressed():
	if not import_system:
		_show_status("Error: Import system not available", true)
		return
	
	print("TileImportUI: Import button pressed")
	
	# Disable import button during import
	import_button.disabled = true
	
	# Show status message
	_show_status("Importing files...", false)
	
	# Get options
	var options = {
		"category": _get_category_from_selector(),
		"auto_slice": slice_checkbox.button_pressed,
		"slice_size": Vector2i(slice_width.value, slice_height.value),
		"generate_autotile": autotile_checkbox.button_pressed,
		"autotile_type": _get_autotile_type_from_selector()
	}
	
	print("TileImportUI: Import options: ", options)
	
	# Import each file
	var success_count = 0
	
	for file_path in selected_files:
		var result = import_system.import_tileset_from_file(file_path, options)
		if result:
			success_count += 1
	
	# Update status
	if success_count > 0:
		_show_status("Imported " + str(success_count) + " of " + str(selected_files.size()) + " files successfully.", false)
	else:
		_show_status("No files were imported successfully.", true)
	
	# Re-enable import button
	import_button.disabled = false
	
	# Update tile palette
	if tile_palette and tile_palette.has_method("refresh"):
		tile_palette.refresh()
		print("TileImportUI: Refreshed tile palette")

func _on_cancel_button_pressed():
	import_dialog.hide()

func _get_category_from_selector() -> String:
	if category_selector:
		match category_selector.selected:
			0: return "floor"
			1: return "wall"
			2: return "object"
			3: return "zone"
	
	return "floor"

func _get_autotile_type_from_selector() -> String:
	if autotile_type:
		match autotile_type.selected:
			1: return "wang_2x2"
			2: return "wang_3x3"
			3: return "corner_match"
			4: return "47_bit"
	
	return "none"

func _on_tile_import_completed(tile_type: String, tile_count: int):
	print("TileImportUI: Import completed - type: ", tile_type, ", count: ", tile_count)
	_show_status("Import completed: Added " + str(tile_count) + " " + tile_type + " tiles.", false)
	
	# Update palette
	if tile_palette and tile_palette.has_method("refresh"):
		tile_palette.refresh()

func _on_import_failed(error_message: String):
	print("TileImportUI: Import failed - ", error_message)
	_show_status("Import failed: " + error_message, true)

func _show_status(message: String, is_error: bool = false):
	if not status_label:
		return
	
	status_label.text = message
	status_label.add_theme_color_override("font_color", Color.RED if is_error else Color.GREEN)
	status_label.show()
