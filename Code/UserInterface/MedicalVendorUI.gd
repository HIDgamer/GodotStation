extends Control
class_name MedicalVendorUI

# References
var vendor = null
var user = null

# Dragging variables
var dragging = false
var drag_start_position = Vector2.ZERO

# UI elements
var tab_container
var close_button
var reagent_bar
var reagent_label
var title_label
var status_label

# Item buttons dictionary for quick reference
var item_buttons = {}

func _ready():
	# Set up dragging
	var panel = get_node_or_null("PanelContainer")
	if panel:
		panel.gui_input.connect(_on_panel_gui_input)
	
	# Get UI references
	tab_container = get_node_or_null("PanelContainer/VBoxContainer/TabContainer")
	close_button = get_node_or_null("PanelContainer/VBoxContainer/HeaderBar/CloseButton")
	reagent_bar = get_node_or_null("PanelContainer/VBoxContainer/FooterBar/ReagentBar")
	reagent_label = get_node_or_null("PanelContainer/VBoxContainer/FooterBar/ReagentLabel")
	title_label = get_node_or_null("PanelContainer/VBoxContainer/HeaderBar/TitleLabel")
	status_label = get_node_or_null("PanelContainer/VBoxContainer/StatusLabel")
	
	# Connect close button
	if close_button:
		close_button.pressed.connect(_on_close_button_pressed)

func _on_panel_gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Start dragging
				dragging = true
				drag_start_position = get_global_mouse_position() - global_position
			else:
				# Stop dragging
				dragging = false
	
	elif event is InputEventMouseMotion and dragging:
		# Move window while dragging
		global_position = get_global_mouse_position() - drag_start_position

func setup_ui(vendor_ref, user_ref):
	vendor = vendor_ref
	user = user_ref
	
	print("UI Setup starting")
	print("TabContainer exists: ", has_node("PanelContainer/VBoxContainer/TabContainer"))
	
	# Set maximum size to 80% of viewport
	var viewport_size = get_viewport().size
	var max_width = viewport_size.x * 0.8
	var max_height = viewport_size.y * 0.8
	
	# Get the main container (assuming PanelContainer exists)
	var panel = get_node_or_null("PanelContainer")
	if panel:
		# Set maximum size
		panel.custom_minimum_size = Vector2(
			min(panel.custom_minimum_size.x, max_width),
			min(panel.custom_minimum_size.y, max_height)
		)
	
	# Set the title
	if title_label:
		title_label.text = vendor.vendor_name
	
	# Clear previous tabs
	if tab_container:
		for child in tab_container.get_children():
			child.queue_free()
		
		# Reset item buttons dictionary
		item_buttons.clear()
		
		# Get vendor product categories
		var categories = vendor.get_current_product_categories()
		
		# Create tabs for each category
		for category in categories:
			var tab = create_category_tab(category)
			tab_container.add_child(tab)
			# Ensure tab title is set correctly
			tab_container.set_tab_title(tab_container.get_child_count() - 1, category)
	
	# Update reagent display if applicable
	update_reagent_display()
	
	# Update status label
	update_status_label()

func create_category_tab(category_name: String) -> Control:
	# Create a scroll container for the tab
	var scroll = ScrollContainer.new()
	scroll.name = category_name
	scroll.custom_minimum_size = Vector2(400, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	
	# Set explicit meta tag for tab name
	scroll.set_meta("_tab_name", category_name)
	
	# Create a VBox to hold items
	var vbox = VBoxContainer.new()
	vbox.name = "ItemList"
	vbox.size_flags_horizontal = Control.SIZE_FILL
	vbox.size_flags_vertical = Control.SIZE_FILL
	vbox.add_theme_constant_override("separation", 4)
	
	# Add the VBox to the scroll container
	scroll.add_child(vbox)
	
	# Get products in this category
	var products = vendor.get_products_in_category(category_name)
	
	# Add each product to the list
	for product in products:
		var item_button = create_item_button(product)
		vbox.add_child(item_button)
		
		# Store reference for quick updates
		item_buttons[product.name] = item_button
	
	return scroll

func normalize_path(path: String) -> String:
	# Handle null or empty paths
	if path == null or path.is_empty():
		return ""
		
	# First try the path as-is
	if ResourceLoader.exists(path):
		return path
		
	# Try converting first letter of each component to uppercase
	var components = path.split("/")
	for i in range(components.size()):
		if components[i].length() > 0:
			# Capitalize first letter of each component
			components[i] = components[i][0].to_upper() + components[i].substr(1)
	
	var capitalized_path = "/".join(components)
	if ResourceLoader.exists(capitalized_path):
		return capitalized_path
		
	# Try all lowercase
	var lowercase_path = path.to_lower()
	if ResourceLoader.exists(lowercase_path):
		return lowercase_path
	
	# Return original as fallback
	return path

func create_item_button(product) -> Control:
	# Debug the product
	print("Creating button for product: ", product)
	
	# Create a horizontal container for the item
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_FILL
	
	# Item icon
	var icon = TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	# Access product data safely with fallbacks
	var item_name = product.name if "name" in product else "Unknown Item"
	var item_count = product.count if "count" in product else 0
	var item_path = product.path if "path" in product else ""
	
	# Normalize path for consistent capitalization
	item_path = normalize_path(item_path)
	
	# Try to load item texture - handle file paths properly
	var item_texture = load_item_icon(item_path)
	if item_texture:
		icon.texture = item_texture
	
	# Item name and description
	var label = Label.new()
	label.name = "Label"
	label.text = str(item_name)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	# Count label
	var count_label = Label.new()
	count_label.name = "CountLabel"
	count_label.text = str(item_count) + "x"
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.custom_minimum_size = Vector2(50, 0)
	
	# Purchase button 
	var button = Button.new()
	button.name = "PurchaseButton"
	button.text = "Vend"
	# Safe comparison
	button.disabled = int(item_count) <= 0
	button.custom_minimum_size = Vector2(60, 0)
	
	# Connect button with properly normalized path
	button.pressed.connect(_on_purchase_button_pressed.bind(item_path))
	
	# Add elements to the container
	hbox.add_child(icon)
	hbox.add_child(label)
	hbox.add_child(count_label)
	hbox.add_child(button)
	
	return hbox

func popup_centered():
	# Get viewport size
	var viewport_size = get_viewport().size
	
	# Calculate center position
	var centered_pos = Vector2(
		viewport_size.x / 2 - size.x / 2,
		viewport_size.y / 2 - size.y / 2
	)
	
	# Set position and show
	global_position = centered_pos
	show()
	
	# Make sure we're on top
	move_to_front()

func load_item_icon(item_path: String) -> Texture2D:
	# Check for null or empty path
	if item_path == null or item_path.is_empty():
		print("Using fallback icon - empty path")
		return preload("res://Assets/Icons/Items/Medical/Medkit.png")
	
	# Try to get icon for item type
	var icon_path = item_path.replace(".tscn", "_icon.png")
	
	# Debug icon path attempt
	print("Attempting to load icon from: ", icon_path)
	
	# Load the texture
	var texture = null
	if ResourceLoader.exists(icon_path):
		texture = load(icon_path)
	
	# Fallback to a default icon
	if texture == null:
		print("Using fallback icon")
		texture = preload("res://Assets/Icons/Items/Medical/Medkit.png")
	
	return texture

func update_item_count(item_name: String, new_count: int):
	if item_buttons.has(item_name):
		var item_button = item_buttons[item_name]
		
		# Update count label
		var count_label = item_button.get_node_or_null("CountLabel")
		if count_label:
			count_label.text = str(new_count) + "x"
		
		# Enable/disable purchase button
		var purchase_button = item_button.get_node_or_null("PurchaseButton")
		if purchase_button:
			purchase_button.disabled = new_count <= 0

func update_reagent_display():
	if vendor == null:
		return
		
	if vendor.vendor_type == vendor.VendorType.CHEMISTRY or vendor.vendor_type == vendor.VendorType.MEDICAL:
		if reagent_bar and reagent_label:
			# Show reagent UI
			reagent_bar.visible = true
			reagent_label.visible = true
			
			# Update values
			var percentage = vendor.chem_refill_volume / vendor.chem_refill_volume_max
			reagent_bar.value = percentage * 100
			reagent_label.text = "Reagents: " + str(int(vendor.chem_refill_volume)) + " / " + str(int(vendor.chem_refill_volume_max))
			
			# Color the bar based on level
			if percentage > 0.75:
				reagent_bar.modulate = Color(0, 1, 0.3)  # Green
			elif percentage > 0.25:
				reagent_bar.modulate = Color(1, 1, 0)    # Yellow
			else:
				reagent_bar.modulate = Color(1, 0.3, 0)  # Red
	else:
		# Hide reagent UI for vendors that don't use reagents
		if reagent_bar and reagent_label:
			reagent_bar.visible = false
			reagent_label.visible = false

func update_reagent_level(current: float, maximum: float):
	if reagent_bar and reagent_label:
		var percentage = current / maximum
		reagent_bar.value = percentage * 100
		reagent_label.text = "Reagents: " + str(int(current)) + " / " + str(int(maximum))
		
		# Color the bar based on level
		if percentage > 0.75:
			reagent_bar.modulate = Color(0, 1, 0.3)  # Green
		elif percentage > 0.25:
			reagent_bar.modulate = Color(1, 1, 0)    # Yellow
		else:
			reagent_bar.modulate = Color(1, 0.3, 0)  # Red

func update_status_label():
	if status_label and vendor != null:
		var status_text = ""
		
		# Show if supply link is connected
		if vendor.supply_link_connected:
			status_text += "[Supply Link Connected] "
		
		# Show if hacked
		if vendor.hacked:
			status_text += "[HACKED] "
		
		# Show if broken
		if vendor.broken:
			status_text += "[OUT OF ORDER] "
		
		# Set the text
		status_label.text = status_text
		status_label.visible = !status_text.is_empty()

func _on_purchase_button_pressed(item_path):
	if vendor and user:
		# Normalize path before passing to vendor
		item_path = normalize_path(item_path)
		vendor.purchase_item(item_path, user)

func _on_close_button_pressed():
	if vendor:
		vendor.close_vendor_ui()
	else:
		hide()
