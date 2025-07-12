extends VBoxContainer

signal layer_visibility_changed(layer_id, visible)
signal layer_selected(layer_id)
signal layer_opacity_changed(layer_id, opacity)

# Layer references
var layer_controls = {}

# Current selection
var current_layer: int = 0

# References
var editor_ref = null

func _ready():
	# Try to get editor reference
	editor_ref = get_node_or_null("/root/Editor")
	
	# Initialize layers
	setup_layers()
	
	# Set default layer
	set_current_layer(0)  # Floor layer

func setup_layers():
	# Clear existing controls
	for child in get_children():
		remove_child(child)
		child.queue_free()
	
	layer_controls.clear()
	
	# Add title
	var title = Label.new()
	title.text = "Layers"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	
	# Add separator
	var separator = HSeparator.new()
	add_child(separator)
	
	# Add floor layer
	add_layer(0, "Floor", Color(0.5, 0.5, 1.0, 1.0))
	
	# Add wall layer
	add_layer(1, "Wall", Color(1.0, 0.5, 0.5, 1.0))
	
	# Add object layer
	add_layer(2, "Objects", Color(0.5, 1.0, 0.5, 1.0))
	
	# Add zone layer
	add_layer(4, "Zone", Color(1.0, 1.0, 0.5, 1.0))
	
	# Add entity layer
	add_layer(5, "Entities", Color(1.0, 0.5, 1.0, 1.0))

func add_layer(layer_id: int, layer_name: String, layer_color: Color):
	# Create layer panel
	var panel = PanelContainer.new()
	panel.name = layer_name + "Layer"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Add VBox inside panel
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	panel.add_child(vbox)
	
	# Add header with visibility toggle
	var header = HBoxContainer.new()
	header.name = "Header"
	
	var visibility_button = CheckBox.new()
	visibility_button.name = "VisibilityToggle"
	visibility_button.button_pressed = true
	visibility_button.tooltip_text = "Toggle layer visibility"
	visibility_button.connect("toggled", Callable(self, "_on_layer_visibility_toggled").bind(layer_id))
	
	var layer_button = Button.new()
	layer_button.name = "LayerButton"
	layer_button.text = layer_name
	layer_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layer_button.toggle_mode = true
	layer_button.connect("pressed", Callable(self, "_on_layer_selected").bind(layer_id))
	
	# Add color indicator
	var color_rect = ColorRect.new()
	color_rect.name = "ColorIndicator"
	color_rect.custom_minimum_size = Vector2(20, 20)
	color_rect.color = layer_color
	
	header.add_child(visibility_button)
	header.add_child(layer_button)
	header.add_child(color_rect)
	
	vbox.add_child(header)
	
	# Add opacity slider
	var opacity_hbox = HBoxContainer.new()
	opacity_hbox.name = "OpacityControl"
	
	var opacity_label = Label.new()
	opacity_label.text = "Opacity:"
	opacity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var opacity_slider = HSlider.new()
	opacity_slider.name = "OpacitySlider"
	opacity_slider.min_value = 0
	opacity_slider.max_value = 100
	opacity_slider.value = 100
	opacity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opacity_slider.connect("value_changed", Callable(self, "_on_layer_opacity_changed").bind(layer_id))
	
	opacity_hbox.add_child(opacity_label)
	opacity_hbox.add_child(opacity_slider)
	
	vbox.add_child(opacity_hbox)
	
	# Store references to controls
	layer_controls[layer_id] = {
		"panel": panel,
		"button": layer_button,
		"visibility": visibility_button,
		"opacity": opacity_slider,
		"color": color_rect
	}
	
	# Add to parent
	add_child(panel)

func set_current_layer(layer_id: int):
	current_layer = layer_id
	
	# Update button states
	for id in layer_controls:
		layer_controls[id].button.button_pressed = (id == layer_id)
	
	# Emit signal
	emit_signal("layer_selected", layer_id)
	
	# Update editor
	if editor_ref and editor_ref.has_method("set_active_layer"):
		editor_ref.set_active_layer(layer_id)

func _on_layer_selected(layer_id: int):
	set_current_layer(layer_id)

func _on_layer_visibility_toggled(visible: bool, layer_id: int):
	# Update controls
	if layer_id in layer_controls:
		layer_controls[layer_id].button.disabled = !visible
		layer_controls[layer_id].opacity.editable = visible
	
	# Emit signal
	emit_signal("layer_visibility_changed", layer_id, visible)
	
	# Update editor
	if editor_ref and editor_ref.has_method("set_layer_visibility"):
		editor_ref.set_layer_visibility(layer_id, visible)

func _on_layer_opacity_changed(value: float, layer_id: int):
	var opacity = value / 100.0
	
	# Emit signal
	emit_signal("layer_opacity_changed", layer_id, opacity)
	
	# Update editor
	if editor_ref and editor_ref.has_method("set_layer_opacity"):
		editor_ref.set_layer_opacity(layer_id, opacity)

func update_from_editor():
	# Update layer states based on editor state
	if not editor_ref:
		return
	
	# Update current layer
	if "current_layer" in editor_ref:
		current_layer = editor_ref.current_layer
		
		for id in layer_controls:
			layer_controls[id].button.button_pressed = (id == current_layer)
	
	# Update layer visibility
	if editor_ref.has_method("get_layer_visibility"):
		for id in layer_controls:
			var visible = editor_ref.get_layer_visibility(id)
			layer_controls[id].visibility.button_pressed = visible
			layer_controls[id].button.disabled = !visible
			layer_controls[id].opacity.editable = visible
	
	# Update layer opacity
	if editor_ref.has_method("get_layer_opacity"):
		for id in layer_controls:
			var opacity = editor_ref.get_layer_opacity(id)
			layer_controls[id].opacity.value = opacity * 100.0
