extends ScrollContainer

signal object_selected(object_type)

# References
@onready var object_container = $VBoxContainer
var editor_ref = null

# Button properties
@export var button_min_height: int = 50
@export var button_padding: int = 5
@export var show_descriptions: bool = true

# Current selection
var current_object_type: String = ""

func _ready():
	# Try to get editor reference
	editor_ref = get_node_or_null("/root/Editor")
	
	# Initialize list
	populate_object_list()

func populate_object_list():
	# Clear existing buttons
	for child in object_container.get_children():
		object_container.remove_child(child)
		child.queue_free()
	
	# Get object types from TileDefinitions
	var placeable_objects = TileDefinitions.PLACEABLE_OBJECTS
	
	# Create a button for each object type
	for object_type in placeable_objects:
		var object_data = placeable_objects[object_type]
		
		# Create object button
		var button = create_object_button(
			object_type,
			object_data.name,
			object_data.preview_icon,
			object_data.scene_path
		)
		
		# Add to container
		object_container.add_child(button)

func create_object_button(object_type: String, display_name: String, icon_path: String, scene_path: String) -> Button:
	# Create button
	var button = Button.new()
	
	# Set size
	button.custom_minimum_size = Vector2(0, button_min_height)
	
	# Set appearance
	button.flat = false
	button.toggle_mode = true
	button.alignment = Button.PRESET_CENTER_LEFT
	button.text = display_name
	
	# Try to load icon
	if ResourceLoader.exists(icon_path):
		var texture = load(icon_path)
		button.icon = texture
		button.expand_icon = true
	
	# Store object data
	button.set_meta("object_type", object_type)
	button.set_meta("scene_path", scene_path)
	
	# Set tooltip with description if available
	var description = ""
	if object_type in TileDefinitions.PLACEABLE_OBJECTS and "description" in TileDefinitions.PLACEABLE_OBJECTS[object_type]:
		description = TileDefinitions.PLACEABLE_OBJECTS[object_type].description
	
	if description != "":
		button.tooltip_text = description
	else:
		button.tooltip_text = display_name
	
	# Connect pressed signal
	button.connect("pressed", Callable(self, "_on_object_button_pressed").bind(button))
	
	return button

func _on_object_button_pressed(button: Button):
	# Unpress other buttons
	for child in object_container.get_children():
		if child != button and child is Button and child.button_pressed:
			child.button_pressed = false
	
	# Update current selection
	var object_type = button.get_meta("object_type")
	
	if current_object_type == object_type:
		# Deselect if already selected
		current_object_type = ""
		button.button_pressed = false
	else:
		# Select new object type
		current_object_type = object_type
	
	# Emit signal
	emit_signal("object_selected", current_object_type)
	
	# Update editor
	if editor_ref and editor_ref.has_method("set_current_object"):
		editor_ref.set_current_object(current_object_type)

func select_object_type(object_type: String):
	# Find and select the button for this object type
	for child in object_container.get_children():
		if child is Button and child.get_meta("object_type") == object_type:
			# Unpress other buttons
			for other_child in object_container.get_children():
				if other_child != child and other_child is Button:
					other_child.button_pressed = false
			
			# Press this button
			child.button_pressed = true
			current_object_type = object_type
			
			# Update editor
			if editor_ref and editor_ref.has_method("set_current_object"):
				editor_ref.set_current_object(current_object_type)
			
			break

func clear_selection():
	# Unpress all buttons
	for child in object_container.get_children():
		if child is Button and child.button_pressed:
			child.button_pressed = false
	
	# Clear current selection
	current_object_type = ""
	
	# Update editor
	if editor_ref and editor_ref.has_method("set_current_object"):
		editor_ref.set_current_object("")
