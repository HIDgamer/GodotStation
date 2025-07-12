extends VBoxContainer

signal property_changed(object, property_name, new_value)

# References
var editor_ref = null

# Current object
var current_object = null
var properties_container = null
var property_controls = {}

func _ready():
	# Try to get editor reference
	editor_ref = get_node_or_null("/root/Editor")
	
	# Initialize container
	properties_container = $PropertiesContainer
	
	# Create title label
	var title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "Object Properties"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title_label, true)
	move_child(title_label, 0)
	
	# Add properties container if it doesn't exist
	if not properties_container:
		properties_container = VBoxContainer.new()
		properties_container.name = "PropertiesContainer"
		add_child(properties_container)
	
	# Clear properties initially
	clear_properties()

func set_object(object_instance):
	# Clear previous properties
	clear_properties()
	
	# Update current object
	current_object = object_instance
	
	if not current_object:
		return
	
	# Create properties UI based on object type
	var object_type = current_object.get_meta("object_type", "")
	
	# Update title
	var title_label = get_node("TitleLabel")
	if title_label and object_type != "":
		if object_type in TileDefinitions.PLACEABLE_OBJECTS:
			title_label.text = TileDefinitions.PLACEABLE_OBJECTS[object_type].name + " Properties"
		else:
			title_label.text = "Object Properties"
	
	# Create common property controls
	create_position_controls()
	create_direction_control()
	
	# Create object-specific controls
	if object_type == "light":
		create_light_controls()
	elif object_type == "switch":
		create_switch_controls()
	
	# Make the panel visible
	visible = true

func clear_properties():
	# Clear all property controls
	for child in properties_container.get_children():
		properties_container.remove_child(child)
		child.queue_free()
	
	# Clear current object reference
	current_object = null
	property_controls.clear()
	
	# Hide the panel
	visible = false

func create_position_controls():
	# Add position group
	var position_group = create_property_group("Position")
	properties_container.add_child(position_group)
	
	# Get grid position
	var grid_pos = current_object.get_meta("grid_position", Vector2i(0, 0))
	var z_level = current_object.get_meta("z_level", 0)
	
	# Create X spinner
	var x_hbox = HBoxContainer.new()
	x_hbox.name = "XPosition"
	
	var x_label = Label.new()
	x_label.text = "X:"
	x_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var x_spin = SpinBox.new()
	x_spin.name = "XSpinBox"
	x_spin.min_value = -1000
	x_spin.max_value = 1000
	x_spin.value = grid_pos.x
	x_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	x_spin.connect("value_changed", Callable(self, "_on_position_changed").bind("x"))
	
	x_hbox.add_child(x_label)
	x_hbox.add_child(x_spin)
	position_group.add_child(x_hbox)
	
	# Create Y spinner
	var y_hbox = HBoxContainer.new()
	y_hbox.name = "YPosition"
	
	var y_label = Label.new()
	y_label.text = "Y:"
	y_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var y_spin = SpinBox.new()
	y_spin.name = "YSpinBox"
	y_spin.min_value = -1000
	y_spin.max_value = 1000
	y_spin.value = grid_pos.y
	y_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	y_spin.connect("value_changed", Callable(self, "_on_position_changed").bind("y"))
	
	y_hbox.add_child(y_label)
	y_hbox.add_child(y_spin)
	position_group.add_child(y_hbox)
	
	# Create Z spinner
	var z_hbox = HBoxContainer.new()
	z_hbox.name = "ZPosition"
	
	var z_label = Label.new()
	z_label.text = "Z:"
	z_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var z_spin = SpinBox.new()
	z_spin.name = "ZSpinBox"
	z_spin.min_value = 0
	z_spin.max_value = 10
	z_spin.value = z_level
	z_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	z_spin.connect("value_changed", Callable(self, "_on_position_changed").bind("z"))
	
	z_hbox.add_child(z_label)
	z_hbox.add_child(z_spin)
	position_group.add_child(z_hbox)
	
	# Store references to controls
	property_controls["x_position"] = x_spin
	property_controls["y_position"] = y_spin
	property_controls["z_position"] = z_spin

func create_direction_control():
	# Skip if object doesn't have a direction property
	if not "facing_direction" in current_object:
		return
	
	# Add direction group
	var direction_group = create_property_group("Direction")
	properties_container.add_child(direction_group)
	
	# Create direction option button
	var dir_hbox = HBoxContainer.new()
	dir_hbox.name = "DirectionControl"
	
	var dir_label = Label.new()
	dir_label.text = "Facing:"
	dir_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var dir_option = OptionButton.new()
	dir_option.name = "DirectionOption"
	dir_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Add direction options
	dir_option.add_item("North", TileDefinitions.Direction.NORTH)
	dir_option.add_item("South", TileDefinitions.Direction.SOUTH)
	dir_option.add_item("East", TileDefinitions.Direction.EAST)
	dir_option.add_item("West", TileDefinitions.Direction.WEST)
	
	# Set current direction
	dir_option.selected = current_object.facing_direction
	
	# Connect signal
	dir_option.connect("item_selected", Callable(self, "_on_direction_changed"))
	
	dir_hbox.add_child(dir_label)
	dir_hbox.add_child(dir_option)
	direction_group.add_child(dir_hbox)
	
	# Store reference to control
	property_controls["direction"] = dir_option

func create_light_controls():
	# Skip if not a light
	if not "is_active" in current_object:
		return
	
	# Add light group
	var light_group = create_property_group("Light Settings")
	properties_container.add_child(light_group)
	
	# Create is_active checkbox
	var active_hbox = HBoxContainer.new()
	active_hbox.name = "ActiveControl"
	
	var active_label = Label.new()
	active_label.text = "Active:"
	active_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var active_check = CheckBox.new()
	active_check.name = "ActiveCheckBox"
	active_check.button_pressed = current_object.is_active
	active_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	active_check.connect("toggled", Callable(self, "_on_active_toggled"))
	
	active_hbox.add_child(active_label)
	active_hbox.add_child(active_check)
	light_group.add_child(active_hbox)
	
	# Store reference to control
	property_controls["is_active"] = active_check

func create_switch_controls():
	# Add switch group
	var switch_group = create_property_group("Switch Settings")
	properties_container.add_child(switch_group)
	
	# Create is_on checkbox
	var on_hbox = HBoxContainer.new()
	on_hbox.name = "OnControl"
	
	var on_label = Label.new()
	on_label.text = "On:"
	on_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var on_check = CheckBox.new()
	on_check.name = "OnCheckBox"
	on_check.button_pressed = current_object.is_active if "is_active" in current_object else false
	on_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	on_check.connect("toggled", Callable(self, "_on_active_toggled"))
	
	on_hbox.add_child(on_label)
	on_hbox.add_child(on_check)
	switch_group.add_child(on_hbox)
	
	# Store reference to control
	property_controls["is_active"] = on_check

func create_property_group(title: String) -> VBoxContainer:
	var group = VBoxContainer.new()
	group.name = title.replace(" ", "") + "Group"
	
	var title_label = Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	# Add a separator
	var separator = HSeparator.new()
	
	group.add_child(title_label)
	group.add_child(separator)
	
	return group

func _on_position_changed(value, axis: String):
	if not current_object:
		return
	
	# Update position
	var grid_pos = current_object.get_meta("grid_position", Vector2i(0, 0))
	var z_level = current_object.get_meta("z_level", 0)
	
	match axis:
		"x":
			grid_pos.x = int(value)
		"y":
			grid_pos.y = int(value)
		"z":
			z_level = int(value)
	
	# Update metadata
	current_object.set_meta("grid_position", grid_pos)
	current_object.set_meta("z_level", z_level)
	
	# Update actual position
	current_object.position = Vector2(
		grid_pos.x * 32 + 16,  # Center in tile
		grid_pos.y * 32 + 16   # Center in tile
	)
	
	# Emit signal
	emit_signal("property_changed", current_object, "position", {
		"grid_position": grid_pos,
		"z_level": z_level
	})

func _on_direction_changed(index: int):
	if not current_object or not "facing_direction" in current_object:
		return
	
	# Update direction
	current_object.facing_direction = index
	
	# Call function if available
	if current_object.has_method("_set_sprite_animation"):
		current_object._set_sprite_animation()
	
	# Emit signal
	emit_signal("property_changed", current_object, "direction", index)

func _on_active_toggled(button_pressed: bool):
	if not current_object:
		return
	
	# Update active state
	if "is_active" in current_object:
		current_object.is_active = button_pressed
		
		# Update visuals
		if button_pressed:
			if current_object.has_method("turn_on"):
				current_object.turn_on()
		else:
			if current_object.has_method("turn_off"):
				current_object.turn_off()
	
	# Emit signal
	emit_signal("property_changed", current_object, "is_active", button_pressed)

func update_from_object():
	# Update all controls from current object
	if not current_object:
		return
	
	# Position controls
	var grid_pos = current_object.get_meta("grid_position", Vector2i(0, 0))
	var z_level = current_object.get_meta("z_level", 0)
	
	if "x_position" in property_controls:
		property_controls["x_position"].value = grid_pos.x
	
	if "y_position" in property_controls:
		property_controls["y_position"].value = grid_pos.y
	
	if "z_position" in property_controls:
		property_controls["z_position"].value = z_level
	
	# Direction control
	if "direction" in property_controls and "facing_direction" in current_object:
		property_controls["direction"].selected = current_object.facing_direction
	
	# Active control
	if "is_active" in property_controls and "is_active" in current_object:
		property_controls["is_active"].button_pressed = current_object.is_active
