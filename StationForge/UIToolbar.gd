extends HBoxContainer

signal tool_selected(tool_name)
signal layer_selected(layer_id)

# References to editor 
var editor_ref = null

# References to tool buttons
var place_button: Button
var erase_button: Button
var select_button: Button 
var fill_button: Button

# References to layer buttons
var floor_button: Button
var wall_button: Button
var objects_button: Button
var zone_button: Button

# Current selections
var current_tool: String = "place"
var current_layer: int = 0 # Floor layer

func _ready():
	# Try to get editor reference
	editor_ref = get_node_or_null("/root/Editor")
	
	# Initialize tool buttons
	place_button = $HBoxContainer/ToolsSection/PlaceButton
	erase_button = $HBoxContainer/ToolsSection/EraseButton
	select_button = $HBoxContainer/ToolsSection/SelectButton
	fill_button = $HBoxContainer/ToolsSection/FillButton
	
	# Initialize layer buttons
	floor_button = $HBoxContainer/LayersSection/FloorButton
	wall_button = $HBoxContainer/LayersSection/WallButton
	objects_button = $HBoxContainer/LayersSection/ObjectsButton
	zone_button = $HBoxContainer/LayersSection/ZoneButton
	
	# Connect button signals
	place_button.connect("pressed", Callable(self, "_on_place_button_pressed"))
	erase_button.connect("pressed", Callable(self, "_on_erase_button_pressed"))
	select_button.connect("pressed", Callable(self, "_on_select_button_pressed"))
	fill_button.connect("pressed", Callable(self, "_on_fill_button_pressed"))
	
	floor_button.connect("pressed", Callable(self, "_on_floor_button_pressed"))
	wall_button.connect("pressed", Callable(self, "_on_wall_button_pressed"))
	objects_button.connect("pressed", Callable(self, "_on_objects_button_pressed"))
	zone_button.connect("pressed", Callable(self, "_on_zone_button_pressed"))
	
	# Set initial states
	update_tool_buttons()
	update_layer_buttons()

# Tool button handlers
func _on_place_button_pressed():
	set_current_tool("place")

func _on_erase_button_pressed():
	set_current_tool("erase")

func _on_select_button_pressed():
	set_current_tool("select")

func _on_fill_button_pressed():
	set_current_tool("fill")

# Layer button handlers
func _on_floor_button_pressed():
	set_current_layer(0) # Floor layer

func _on_wall_button_pressed():
	set_current_layer(1) # Wall layer

func _on_objects_button_pressed():
	set_current_layer(2) # Objects layer

func _on_zone_button_pressed():
	set_current_layer(4) # Zone layer (using Atmosphere layer id)

# Set current tool
func set_current_tool(tool_name: String):
	current_tool = tool_name
	update_tool_buttons()
	
	# Notify editor
	emit_signal("tool_selected", tool_name)
	if editor_ref and editor_ref.has_method("set_current_tool"):
		editor_ref.set_current_tool(tool_name)

# Set current layer
func set_current_layer(layer_id: int):
	current_layer = layer_id
	update_layer_buttons()
	
	# Notify editor
	emit_signal("layer_selected", layer_id)
	if editor_ref and editor_ref.has_method("set_active_layer"):
		editor_ref.set_active_layer(layer_id)

# Update tool button states
func update_tool_buttons():
	place_button.button_pressed = (current_tool == "place")
	erase_button.button_pressed = (current_tool == "erase")
	select_button.button_pressed = (current_tool == "select")
	fill_button.button_pressed = (current_tool == "fill")

# Update layer button states
func update_layer_buttons():
	floor_button.button_pressed = (current_layer == 0)
	wall_button.button_pressed = (current_layer == 1)
	objects_button.button_pressed = (current_layer == 2)
	zone_button.button_pressed = (current_layer == 4)
