extends Control
class_name VendorUI

# References
var vendor: BaseVendor = null
var user = null

# UI Node references
@onready var main_panel: Panel = $MainPanel
@onready var header_bar: Control = $MainPanel/VBoxContainer/HeaderBar
@onready var title_label: Label = $MainPanel/VBoxContainer/HeaderBar/HBoxContainer/TitleLabel
@onready var status_label: Label = $MainPanel/VBoxContainer/HeaderBar/HBoxContainer/StatusLabel
@onready var close_button: Button = $MainPanel/VBoxContainer/HeaderBar/HBoxContainer/CloseButton
@onready var category_tabs: TabContainer = $MainPanel/VBoxContainer/ContentArea/CategoryTabs
@onready var item_scroll: ScrollContainer = $MainPanel/VBoxContainer/ContentArea/ItemScroll
@onready var item_grid: GridContainer = $MainPanel/VBoxContainer/ContentArea/ItemScroll/ItemGrid
@onready var footer_bar: Control = $MainPanel/VBoxContainer/FooterBar
@onready var info_label: Label = $MainPanel/VBoxContainer/FooterBar/InfoLabel
@onready var hack_indicator: Control = $MainPanel/VBoxContainer/FooterBar/HackIndicator

# Dragging
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO

# Item organization
var categories: Dictionary = {}
var current_category: String = "All"
var item_buttons: Dictionary = {}

# Visual settings
var item_button_size: Vector2 = Vector2(300, 80)
var grid_columns: int = 2
var animation_speed: float = 0.3

# Audio
var hover_sound: AudioStream = preload("res://Sound/machines/keyboard2.ogg")
var purchase_sound: AudioStream = preload("res://Sound/machines/vending_drop.ogg")
var error_sound: AudioStream = preload("res://Sound/machines/buzz-two.ogg")

# Signals
signal ui_closed()
signal item_purchased(item_path: String)

func _ready():
	# Connect signals
	close_button.pressed.connect(_on_close_button_pressed)
	main_panel.gui_input.connect(_on_main_panel_gui_input)
	
	# Setup grid
	item_grid.columns = grid_columns
	
	# Setup theme
	apply_industrial_theme()
	
	# Hide initially
	hide()

func apply_industrial_theme():
	"""Apply the high-tech industrial theme"""
	
	# Main panel styling - dark blue-gray with glowing edges
	if main_panel:
		var panel_style = StyleBoxFlat.new()
		panel_style.bg_color = Color(0.1, 0.12, 0.15, 0.95)  # Dark blue-gray
		panel_style.border_width_left = 2
		panel_style.border_width_right = 2
		panel_style.border_width_top = 2
		panel_style.border_width_bottom = 2
		panel_style.border_color = Color(0.2, 0.6, 1.0, 0.8)  # Cyan glow
		panel_style.corner_radius_top_left = 8
		panel_style.corner_radius_top_right = 8
		panel_style.corner_radius_bottom_left = 8
		panel_style.corner_radius_bottom_right = 8
		main_panel.add_theme_stylebox_override("panel", panel_style)
	
	# Header bar styling
	if header_bar:
		var header_style = StyleBoxFlat.new()
		header_style.bg_color = Color(0.05, 0.08, 0.12, 1.0)
		header_style.border_width_bottom = 1
		header_style.border_color = Color(0.2, 0.6, 1.0, 0.6)
		header_bar.add_theme_stylebox_override("panel", header_style)
	
	# Title label styling
	if title_label:
		title_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
		title_label.add_theme_font_size_override("font_size", 18)
	
	# Status label styling
	if status_label:
		status_label.add_theme_color_override("font_color", Color(0.2, 0.8, 1.0))
		status_label.add_theme_font_size_override("font_size", 12)
	
	# Close button styling
	if close_button:
		var button_normal = StyleBoxFlat.new()
		button_normal.bg_color = Color(0.8, 0.2, 0.2, 0.8)
		button_normal.corner_radius_top_left = 4
		button_normal.corner_radius_top_right = 4
		button_normal.corner_radius_bottom_left = 4
		button_normal.corner_radius_bottom_right = 4
		
		var button_hover = StyleBoxFlat.new()
		button_hover.bg_color = Color(1.0, 0.3, 0.3, 1.0)
		button_hover.corner_radius_top_left = 4
		button_hover.corner_radius_top_right = 4
		button_hover.corner_radius_bottom_left = 4
		button_hover.corner_radius_bottom_right = 4
		
		close_button.add_theme_stylebox_override("normal", button_normal)
		close_button.add_theme_stylebox_override("hover", button_hover)
		close_button.add_theme_color_override("font_color", Color.WHITE)

func setup_vendor(vendor_ref: BaseVendor, user_ref):
	"""Setup the UI for a specific vendor and user"""
	vendor = vendor_ref
	user = user_ref
	
	# Connect vendor signals
	if vendor:
		if not vendor.stock_updated.is_connected(_on_stock_updated):
			vendor.stock_updated.connect(_on_stock_updated)
		if not vendor.item_purchased.is_connected(_on_item_purchased):
			vendor.item_purchased.connect(_on_item_purchased)
	
	# Update UI content
	refresh_ui()

func refresh_ui():
	"""Refresh the entire UI"""
	update_header()
	refresh_items()
	update_footer()

func update_header():
	"""Update the header information"""
	if not vendor:
		return
	
	# Set title
	if title_label:
		title_label.text = vendor.vendor_name
	
	# Set status
	if status_label:
		var status_text = ""
		
		if vendor.hacked:
			status_text = "[COMPROMISED]"
			status_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.0))
		elif not vendor.is_powered:
			status_text = "[OFFLINE]"
			status_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2))
		elif vendor.unlimited_stock:
			status_text = "[UNLIMITED]"
			status_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
		else:
			status_text = "[OPERATIONAL]"
			status_label.add_theme_color_override("font_color", Color(0.2, 0.8, 1.0))
		
		status_label.text = status_text

func refresh_items():
	"""Refresh the item display"""
	if not vendor:
		return
	
	# Clear existing items
	clear_item_display()
	
	# Get items from vendor
	var items = vendor.get_available_items()
	
	# Organize items by category if vendor supports it
	organize_items_by_category(items)
	
	# Create item buttons
	create_item_buttons(items)

func organize_items_by_category(items: Array):
	"""Organize items into categories"""
	categories.clear()
	categories["All"] = items
	
	# Group by category if items have category info
	for item in items:
		var category = item.get("category", "General")
		if not categories.has(category):
			categories[category] = []
		categories[category].append(item)
	
	# Update category tabs if more than one category
	if categories.size() > 2:  # More than just "All" and one other
		setup_category_tabs()
	else:
		hide_category_tabs()

func setup_category_tabs():
	"""Setup category tabs"""
	if not category_tabs:
		return
	
	# Clear existing tabs
	for child in category_tabs.get_children():
		child.queue_free()
	
	# Create tabs for each category
	for category_name in categories.keys():
		if category_name == "All":
			continue
			
		var tab = Control.new()
		tab.name = category_name
		category_tabs.add_child(tab)
	
	# Show tabs
	category_tabs.visible = true
	item_scroll.visible = false
	
	# Connect tab changed signal
	if not category_tabs.tab_changed.is_connected(_on_category_changed):
		category_tabs.tab_changed.connect(_on_category_changed)

func hide_category_tabs():
	"""Hide category tabs and use simple scroll view"""
	if category_tabs:
		category_tabs.visible = false
	if item_scroll:
		item_scroll.visible = true

func create_item_buttons(items: Array):
	"""Create buttons for all items"""
	item_buttons.clear()
	
	for item in items:
		var button = create_item_button(item)
		if button:
			item_grid.add_child(button)
			item_buttons[item.path] = button

func create_item_button(item: Dictionary) -> Control:
	"""Create a single item button"""
	
	# Main container
	var button_container = Control.new()
	button_container.custom_minimum_size = item_button_size
	button_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Background panel
	var background = Panel.new()
	background.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	background.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Style the background
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.15, 0.18, 0.22, 0.9)
	bg_style.border_width_left = 1
	bg_style.border_width_right = 1
	bg_style.border_width_top = 1
	bg_style.border_width_bottom = 1
	bg_style.border_color = Color(0.3, 0.4, 0.5, 0.8)
	bg_style.corner_radius_top_left = 4
	bg_style.corner_radius_top_right = 4
	bg_style.corner_radius_bottom_left = 4
	bg_style.corner_radius_bottom_right = 4
	background.add_theme_stylebox_override("panel", bg_style)
	
	button_container.add_child(background)
	
	# Main horizontal layout
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 8)
	button_container.add_child(hbox)
	
	# Icon container
	var icon_container = Control.new()
	icon_container.custom_minimum_size = Vector2(64, 64)
	hbox.add_child(icon_container)
	
	# Item icon
	var icon = TextureRect.new()
	icon.texture = item.get("icon", null)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon_container.add_child(icon)
	
	# Info container
	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)
	
	# Item name
	var name_label = Label.new()
	name_label.text = item.get("name", "Unknown Item")
	name_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_vbox.add_child(name_label)
	
	# Stock info
	var stock_label = Label.new()
	var stock_text = "Stock: " + str(item.get("stock", 0))
	if vendor.unlimited_stock:
		stock_text = "Stock: Unlimited"
	stock_label.text = stock_text
	stock_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	stock_label.add_theme_font_size_override("font_size", 10)
	info_vbox.add_child(stock_label)
	
	# Price info (if applicable)
	if vendor.uses_currency and not vendor.free_dispense:
		var price_label = Label.new()
		price_label.text = "Price: " + str(item.get("price", 0)) + " " + vendor.currency_type
		price_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
		price_label.add_theme_font_size_override("font_size", 10)
		info_vbox.add_child(price_label)
	
	# Purchase button
	var purchase_button = Button.new()
	purchase_button.text = "DISPENSE"
	purchase_button.custom_minimum_size = Vector2(80, 40)
	
	# Style purchase button
	var btn_normal = StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.2, 0.6, 1.0, 0.8)
	btn_normal.corner_radius_top_left = 4
	btn_normal.corner_radius_top_right = 4
	btn_normal.corner_radius_bottom_left = 4
	btn_normal.corner_radius_bottom_right = 4
	
	var btn_hover = StyleBoxFlat.new()
	btn_hover.bg_color = Color(0.3, 0.7, 1.0, 1.0)
	btn_hover.corner_radius_top_left = 4
	btn_hover.corner_radius_top_right = 4
	btn_hover.corner_radius_bottom_left = 4
	btn_hover.corner_radius_bottom_right = 4
	
	var btn_disabled = StyleBoxFlat.new()
	btn_disabled.bg_color = Color(0.3, 0.3, 0.3, 0.5)
	btn_disabled.corner_radius_top_left = 4
	btn_disabled.corner_radius_top_right = 4
	btn_disabled.corner_radius_bottom_left = 4
	btn_disabled.corner_radius_bottom_right = 4
	
	purchase_button.add_theme_stylebox_override("normal", btn_normal)
	purchase_button.add_theme_stylebox_override("hover", btn_hover)
	purchase_button.add_theme_stylebox_override("disabled", btn_disabled)
	purchase_button.add_theme_color_override("font_color", Color.WHITE)
	
	# Check if item is available
	var stock = item.get("stock", 0)
	if not vendor.unlimited_stock and stock <= 0:
		purchase_button.disabled = true
		purchase_button.text = "OUT OF STOCK"
	
	# Connect purchase button
	purchase_button.pressed.connect(_on_purchase_button_pressed.bind(item.path))
	purchase_button.mouse_entered.connect(_on_button_hover)
	
	hbox.add_child(purchase_button)
	
	# Add hover effect to container
	var hover_detector = Control.new()
	hover_detector.mouse_filter = Control.MOUSE_FILTER_PASS
	hover_detector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hover_detector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hover_detector.mouse_entered.connect(_on_item_hover.bind(background, true))
	hover_detector.mouse_exited.connect(_on_item_hover.bind(background, false))
	button_container.add_child(hover_detector)
	
	return button_container

func clear_item_display():
	"""Clear the current item display"""
	for child in item_grid.get_children():
		child.queue_free()
	item_buttons.clear()

func update_footer():
	"""Update footer information"""
	if not vendor or not info_label:
		return
	
	var info_text = ""
	
	# Show total items
	var total_items = vendor.get_available_items().size()
	info_text += "Items Available: " + str(total_items)
	
	# Show currency info if applicable
	if vendor.uses_currency and not vendor.free_dispense:
		info_text += " | Currency: " + vendor.currency_type
	
	# Show vendor type
	if vendor is ManualVendor:
		info_text += " | Type: Manual"
	elif vendor is DynamicVendor:
		info_text += " | Type: Dynamic"
	
	info_label.text = info_text

func show_ui():
	"""Show the UI with animation"""
	visible = true
	modulate = Color(1, 1, 1, 0)
	
	# Center on screen
	var viewport_size = get_viewport().size
	global_position = Vector2(
		viewport_size.x / 2 - size.x / 2,
		viewport_size.y / 2 - size.y / 2
	)
	
	# Fade in animation
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, animation_speed)
	
	play_ui_sound("res://Sound/machines/terminal_on.ogg")

func hide_ui():
	"""Hide the UI with animation"""
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), animation_speed)
	tween.tween_callback(func(): visible = false)
	
	ui_closed.emit()
	play_ui_sound("res://Sound/machines/terminal_off.ogg")

func refresh_stock_display():
	"""Update only the stock displays"""
	if not vendor:
		return
	
	var items = vendor.get_available_items()
	
	for item in items:
		var button = item_buttons.get(item.path)
		if button:
			update_item_button_stock(button, item)

func update_item_button_stock(button: Control, item: Dictionary):
	"""Update the stock display for a specific button"""
	# Find stock label
	var hbox = button.get_child(1) as HBoxContainer  # Skip background panel
	var info_vbox = hbox.get_child(1) as VBoxContainer  # Skip icon container
	var stock_label = info_vbox.get_child(1) as Label  # Stock label is second child
	
	# Update stock text
	var stock_text = "Stock: " + str(item.get("stock", 0))
	if vendor.unlimited_stock:
		stock_text = "Stock: Unlimited"
	stock_label.text = stock_text
	
	# Update purchase button
	var purchase_button = hbox.get_child(2) as Button  # Purchase button is last child
	var stock = item.get("stock", 0)
	
	if not vendor.unlimited_stock and stock <= 0:
		purchase_button.disabled = true
		purchase_button.text = "OUT OF STOCK"
	else:
		purchase_button.disabled = false
		purchase_button.text = "DISPENSE"

func show_hack_status():
	"""Show hack indicator"""
	if hack_indicator:
		hack_indicator.visible = true

func hide_hack_status():
	"""Hide hack indicator"""
	if hack_indicator:
		hack_indicator.visible = false

# Event handlers
func _on_close_button_pressed():
	"""Handle close button press"""
	if vendor:
		vendor.close_vendor_ui()
	else:
		hide_ui()

func _on_purchase_button_pressed(item_path: String):
	"""Handle purchase button press"""
	if vendor and user:
		var success = vendor.purchase_item(item_path, user)
		if success:
			play_ui_sound(purchase_sound)
			item_purchased.emit(item_path)
		else:
			play_ui_sound(error_sound)

func _on_button_hover():
	"""Handle button hover"""
	play_ui_sound(hover_sound, -10.0)

func _on_item_hover(background: Panel, is_hovering: bool):
	"""Handle item hover effect"""
	if not background:
		return
	
	var style = background.get_theme_stylebox("panel") as StyleBoxFlat
	if not style:
		return
	
	var new_style = style.duplicate()
	if is_hovering:
		new_style.border_color = Color(0.4, 0.8, 1.0, 1.0)
		new_style.bg_color = Color(0.2, 0.25, 0.3, 0.9)
	else:
		new_style.border_color = Color(0.3, 0.4, 0.5, 0.8)
		new_style.bg_color = Color(0.15, 0.18, 0.22, 0.9)
	
	background.add_theme_stylebox_override("panel", new_style)

func _on_category_changed(tab_index: int):
	"""Handle category tab change"""
	if not category_tabs:
		return
	
	var tab_name = category_tabs.get_tab_title(tab_index)
	current_category = tab_name
	
	# Filter items by category
	if categories.has(tab_name):
		clear_item_display()
		create_item_buttons(categories[tab_name])

func _on_stock_updated(item_path: String, new_stock: int):
	"""Handle stock update from vendor"""
	refresh_stock_display()

func _on_item_purchased(item_path: String, user_ref, remaining_stock: int):
	"""Handle item purchase notification"""
	refresh_stock_display()

func _on_main_panel_gui_input(event: InputEvent):
	"""Handle main panel input for dragging"""
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_dragging = true
				drag_offset = global_position - get_global_mouse_position()
			else:
				is_dragging = false
	
	elif event is InputEventMouseMotion and is_dragging:
		global_position = get_global_mouse_position() + drag_offset

func play_ui_sound(sound_source, volume_db: float = 0.0):
	"""Play UI sound effect"""
	var sound_stream = null
	
	if sound_source is String:
		if ResourceLoader.exists(sound_source):
			sound_stream = load(sound_source)
	else:
		sound_stream = sound_source
	
	if sound_stream:
		var audio_player = AudioStreamPlayer.new()
		add_child(audio_player)
		audio_player.stream = sound_stream
		audio_player.volume_db = volume_db
		audio_player.play()
		await audio_player.finished
		audio_player.queue_free()
