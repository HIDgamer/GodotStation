extends Machinery
class_name BaseVendor

# Vendor configuration
@export_group("Vendor Settings")
@export var vendor_name: String = "Universal Vendor"
@export var vendor_description: String = "A high-tech dispensing unit"
@export var vendor_theme: String = "industrial" # industrial, military, corporate, medical
@export var max_simultaneous_purchases: int = 1
@export var purchase_cooldown: float = 0.5

# Access control
@export_group("Access Control")
@export var requires_access: bool = false
@export var required_access_flags: Array[String] = []
@export var allow_hack_bypass: bool = true

# Economy
@export_group("Economy") 
@export var uses_currency: bool = false
@export var currency_type: String = "credits"
@export var free_dispense: bool = true

# Stock management
@export_group("Stock")
@export var unlimited_stock: bool = false
@export var restock_rate: float = 0.0 # Items per second
@export var max_stock_multiplier: float = 2.0

# Internal state
var current_stock: Dictionary = {}
var purchase_history: Array = []
var ui_instance = null
var is_ui_open: bool = false
var purchase_queue: Array = []
var last_purchase_time: float = 0.0
var hacked: bool = false

# Item structure: {"path": String, "name": String, "icon": Texture2D, "stock": int, "max_stock": int, "price": int}
var available_items: Array = []

# Signals
signal item_purchased(item_path: String, user, remaining_stock: int)
signal item_dispensed(item: Node, user)
signal stock_updated(item_path: String, new_stock: int)
signal vendor_accessed(user)
signal vendor_hacked(hacker)

func _ready():
	super()
	
	# Set vendor-specific properties
	if obj_name == "object":
		obj_name = vendor_name
	
	if obj_desc == "An object.":
		obj_desc = vendor_description
	
	# Add to vendor groups
	add_to_group("vendors")
	add_to_group("interactable_vendors")
	
	# Initialize vendor
	initialize_vendor()
	
	# Start restocking process if enabled
	if restock_rate > 0.0:
		var restock_timer = Timer.new()
		restock_timer.wait_time = 1.0 / restock_rate
		restock_timer.timeout.connect(_on_restock_tick)
		restock_timer.autostart = true
		add_child(restock_timer)

func initialize_vendor():
	"""Override this in subclasses to set up specific vendor types"""
	pass

func _process(delta):
	super(delta)
	
	# Process purchase queue
	if purchase_queue.size() > 0 and Time.get_ticks_msec() / 1000.0 - last_purchase_time >= purchase_cooldown:
		process_purchase_queue()

func interact(user) -> bool:
	if not super.interact(user):
		return false
	
	# Check if vendor is operational
	if not is_operational():
		show_message(user, "Vendor is currently offline.")
		return false
	
	# Check access permissions
	if not check_access(user):
		show_message(user, "Access denied. Insufficient clearance.")
		play_vendor_audio("res://Sound/machines/buzz-two.ogg")
		return false
	
	# Open vendor UI
	open_vendor_ui(user)
	vendor_accessed.emit(user)
	return true

func is_operational() -> bool:
	"""Check if vendor can be used"""
	if not is_powered:
		return false
	
	if obj_integrity <= integrity_failure:
		return false
	
	return machinery_state != "broken"

func check_access(user) -> bool:
	"""Check if user has required access"""
	if not requires_access:
		return true
	
	if hacked and allow_hack_bypass:
		return true
	
	if user and user.has_method("has_access"):
		for access_flag in required_access_flags:
			if user.has_access(access_flag):
				return true
	
	return false

func open_vendor_ui(user):
	"""Open the vendor UI for the user"""
	if is_ui_open:
		return
	
	# Create UI instance
	if ui_instance == null:
		ui_instance = preload("res://Scenes/UI/Ingame/VendorUI.tscn").instantiate()
		ui_instance.vendor = self
		
		# Find appropriate UI parent
		var ui_parent = find_ui_parent(user)
		if ui_parent:
			ui_parent.add_child(ui_instance)
		else:
			get_tree().root.add_child(ui_instance)
	
	# Setup and show UI
	ui_instance.setup_vendor(self, user)
	ui_instance.show_ui()
	is_ui_open = true
	
	play_vendor_audio("res://Sound/machines/keyboard_click.ogg")

func close_vendor_ui():
	"""Close the vendor UI"""
	if ui_instance and is_ui_open:
		ui_instance.hide_ui()
		is_ui_open = false
		play_vendor_audio("res://Sound/machines/terminal_off.ogg")

func find_ui_parent(user):
	"""Find the best parent for the UI"""
	if user and user.has_node("PlayerUI"):
		return user.get_node("PlayerUI")
	
	var ui_layers = get_tree().get_nodes_in_group("ui_elements")
	if ui_layers.size() > 0:
		return ui_layers[0]
	
	return null

func purchase_item(item_path: String, user, quantity: int = 1) -> bool:
	"""Attempt to purchase an item"""
	
	# Find item in available items
	var item_data = find_item_by_path(item_path)
	if not item_data:
		show_message(user, "Item not found.")
		return false
	
	# Check stock
	if not unlimited_stock and item_data.stock < quantity:
		show_message(user, "Insufficient stock.")
		play_vendor_audio("res://Sound/machines/buzz-two.ogg")
		return false
	
	# Check currency (if enabled)
	if uses_currency and not free_dispense:
		var total_cost = item_data.get("price", 0) * quantity
		if not check_user_currency(user, total_cost):
			show_message(user, "Insufficient " + currency_type + ".")
			play_vendor_audio("res://Sound/machines/buzz-two.ogg")
			return false
	
	# Add to purchase queue
	purchase_queue.append({
		"item_path": item_path,
		"user": user,
		"quantity": quantity,
		"item_data": item_data
	})
	
	return true

func process_purchase_queue():
	"""Process queued purchases"""
	if purchase_queue.is_empty():
		return
	
	var purchase = purchase_queue.pop_front()
	var item_path = purchase.item_path
	var user = purchase.user
	var quantity = purchase.quantity
	var item_data = purchase.item_data
	
	# Deduct stock
	if not unlimited_stock:
		item_data.stock -= quantity
		stock_updated.emit(item_path, item_data.stock)
	
	# Deduct currency
	if uses_currency and not free_dispense:
		var total_cost = item_data.get("price", 0) * quantity
		deduct_user_currency(user, total_cost)
	
	# Dispense items
	for i in range(quantity):
		var item = create_item_instance(item_path)
		if item:
			dispense_item(item, user)
	
	# Update UI
	if ui_instance and is_ui_open:
		ui_instance.refresh_stock_display()
	
	# Record purchase
	purchase_history.append({
		"item_path": item_path,
		"user_id": get_user_id(user),
		"quantity": quantity,
		"timestamp": Time.get_unix_time_from_system()
	})
	
	# Emit signals
	item_purchased.emit(item_path, user, item_data.stock)
	
	# Play success sound
	play_vendor_audio("res://Sound/machines/vending_drop.ogg")
	
	last_purchase_time = Time.get_ticks_msec() / 1000.0

func create_item_instance(item_path: String) -> Node:
	"""Create an instance of the item"""
	if not ResourceLoader.exists(item_path):
		print("Error: Item scene not found: ", item_path)
		return null
	
	var item_scene = load(item_path)
	if not item_scene:
		print("Error: Failed to load item scene: ", item_path)
		return null
	
	return item_scene.instantiate()

func dispense_item(item: Node, user):
	"""Handle item dispensing to user"""
	if not item or not user:
		return
	
	# Try to add to user inventory first
	if user.has_method("add_item_to_inventory") and user.add_item_to_inventory(item):
		item_dispensed.emit(item, user)
		return
	
	# Fallback: drop item near vendor
	item.global_position = global_position + Vector2(32, 32)
	get_parent().add_child(item)
	item_dispensed.emit(item, user)

func find_item_by_path(item_path: String) -> Dictionary:
	"""Find item data by path"""
	for item in available_items:
		if item.path == item_path:
			return item
	return {}

func get_available_items() -> Array:
	"""Get all available items"""
	return available_items

func add_item_to_vendor(item_path: String, name: String, stock: int, max_stock: int = -1, price: int = 0):
	"""Add an item to the vendor's inventory"""
	
	# Extract icon from item
	var icon = extract_item_icon(item_path)
	
	# Set default max stock
	if max_stock == -1:
		max_stock = int(stock * max_stock_multiplier)
	
	var item_data = {
		"path": item_path,
		"name": name,
		"icon": icon,
		"stock": stock,
		"max_stock": max_stock,
		"price": price
	}
	
	available_items.append(item_data)
	stock_updated.emit(item_path, stock)

func extract_item_icon(item_path: String) -> Texture2D:
	"""Extract icon from item scene"""
	if not ResourceLoader.exists(item_path):
		return null
	
	var item_scene = load(item_path)
	if not item_scene:
		return null
	
	var temp_item = item_scene.instantiate()
	var icon_texture = null
	
	# Look for Icon node
	var icon_node = temp_item.get_node_or_null("Icon")
	if icon_node:
		if icon_node is Sprite2D:
			icon_texture = icon_node.texture
		elif icon_node is AnimatedSprite2D:
			if icon_node.sprite_frames:
				icon_texture = icon_node.sprite_frames.get_frame_texture("default", 0)
	
	temp_item.queue_free()
	return icon_texture

func check_user_currency(user, amount: int) -> bool:
	"""Check if user has enough currency"""
	if user.has_method("get_currency"):
		return user.get_currency(currency_type) >= amount
	return true

func deduct_user_currency(user, amount: int):
	"""Deduct currency from user"""
	if user.has_method("deduct_currency"):
		user.deduct_currency(currency_type, amount)

func get_user_id(user) -> String:
	"""Get unique identifier for user"""
	if user.has_method("get_unique_id"):
		return user.get_unique_id()
	return str(user.get_instance_id())

func show_message(user, message: String):
	"""Show a message to the user"""
	if user and user.has_method("display_message"):
		user.display_message(message)

func _on_restock_tick():
	"""Handle automatic restocking"""
	for item in available_items:
		if item.stock < item.max_stock:
			item.stock = min(item.stock + 1, item.max_stock)
			stock_updated.emit(item.path, item.stock)
	
	# Update UI if open
	if ui_instance and is_ui_open:
		ui_instance.refresh_stock_display()

func hack_vendor(hacker):
	"""Handle vendor hacking"""
	if not allow_hack_bypass:
		return false
	
	hacked = true
	vendor_hacked.emit(hacker)
	
	# Show hack notification in UI
	if ui_instance and is_ui_open:
		ui_instance.show_hack_status()
	
	play_vendor_audio("res://Sound/machines/terminal_success.ogg")
	return true

func reset_hack():
	"""Reset hack status"""
	hacked = false
	
	if ui_instance and is_ui_open:
		ui_instance.hide_hack_status()

# Override power management
func _on_power_lost():
	super()
	if is_ui_open:
		close_vendor_ui()

func _on_power_restored():
	super()
	# Vendor back online

# Override breaking
func obj_break(damage_flag: String = ""):
	super.obj_break(damage_flag)
	if is_ui_open:
		close_vendor_ui()

func play_vendor_audio(sound_path: String, volume_db: float = 0.0):
	"""Play audio feedback"""
	if not ResourceLoader.exists(sound_path):
		return
	
	var audio_player = get_node_or_null("AudioStreamPlayer2D")
	if not audio_player:
		audio_player = AudioStreamPlayer2D.new()
		add_child(audio_player)
	
	audio_player.stream = load(sound_path)
	audio_player.volume_db = volume_db
	audio_player.play()
