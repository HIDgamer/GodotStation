extends BaseVendor
class_name ManualVendor

# Manual item configuration
@export_group("Manual Items")
@export var manual_items: Array[ManualVendorItem] = []

# Resource for manual vendor items
@export var auto_populate_on_ready: bool = true

func initialize_vendor():
	"""Initialize the manual vendor with configured items"""
	super.initialize_vendor()
	
	if auto_populate_on_ready:
		populate_from_manual_items()

func populate_from_manual_items():
	"""Populate vendor from the manual items array"""
	available_items.clear()
	
	for manual_item in manual_items:
		if manual_item and not manual_item.item_path.is_empty():
			add_manual_item(manual_item)

func add_manual_item(manual_item: ManualVendorItem):
	"""Add a manual item to the vendor"""
	
	# Validate item path
	if not ResourceLoader.exists(manual_item.item_path):
		print("Warning: Item path does not exist: ", manual_item.item_path)
		return
	
	# Use custom name or extract from item
	var item_name = manual_item.display_name
	if item_name.is_empty():
		item_name = extract_item_name(manual_item.item_path)
	
	# Add item to vendor
	add_item_to_vendor(
		manual_item.item_path,
		item_name,
		manual_item.initial_stock,
		manual_item.max_stock,
		manual_item.price
	)

func extract_item_name(item_path: String) -> String:
	"""Extract item name from the scene file"""
	if not ResourceLoader.exists(item_path):
		return "Unknown Item"
	
	var item_scene = load(item_path)
	if not item_scene:
		return "Unknown Item"
	
	var temp_item = item_scene.instantiate()
	var item_name = "Unknown Item"
	
	# Try to get name from obj_name property (from BaseObject)
	if temp_item.has_property("obj_name"):
		item_name = temp_item.obj_name
	
	# Fallback to scene filename
	if item_name == "Unknown Item" or item_name.is_empty():
		item_name = item_path.get_file().get_basename().capitalize()
	
	temp_item.queue_free()
	return item_name

func add_item_runtime(item_path: String, display_name: String = "", stock: int = 1, max_stock: int = -1, price: int = 0):
	"""Add an item at runtime"""
	
	# Validate path
	if not ResourceLoader.exists(item_path):
		print("Error: Cannot add item, path does not exist: ", item_path)
		return false
	
	# Create manual item
	var manual_item = ManualVendorItem.new()
	manual_item.item_path = item_path
	manual_item.display_name = display_name if not display_name.is_empty() else extract_item_name(item_path)
	manual_item.initial_stock = stock
	manual_item.max_stock = max_stock if max_stock != -1 else int(stock * max_stock_multiplier)
	manual_item.price = price
	
	# Add to manual items array
	manual_items.append(manual_item)
	
	# Add to vendor
	add_manual_item(manual_item)
	
	# Update UI
	if ui_instance and is_ui_open:
		ui_instance.refresh_items()
	
	return true

func remove_item_runtime(item_path: String):
	"""Remove an item at runtime"""
	
	# Remove from available items
	for i in range(available_items.size() - 1, -1, -1):
		if available_items[i].path == item_path:
			available_items.remove_at(i)
			break
	
	# Remove from manual items
	for i in range(manual_items.size() - 1, -1, -1):
		if manual_items[i].item_path == item_path:
			manual_items.remove_at(i)
			break
	
	# Update UI
	if ui_instance and is_ui_open:
		ui_instance.refresh_items()

func set_item_stock(item_path: String, new_stock: int):
	"""Set stock for a specific item"""
	
	# Find and update in available items
	for item in available_items:
		if item.path == item_path:
			item.stock = max(0, new_stock)
			stock_updated.emit(item_path, item.stock)
			break
	
	# Find and update in manual items
	for manual_item in manual_items:
		if manual_item.item_path == item_path:
			manual_item.initial_stock = max(0, new_stock)
			break
	
	# Update UI
	if ui_instance and is_ui_open:
		ui_instance.refresh_stock_display()

func get_item_stock(item_path: String) -> int:
	"""Get current stock for an item"""
	for item in available_items:
		if item.path == item_path:
			return item.stock
	return 0

func restock_item(item_path: String, amount: int = 1):
	"""Restock a specific item"""
	for item in available_items:
		if item.path == item_path:
			item.stock = min(item.stock + amount, item.max_stock)
			stock_updated.emit(item_path, item.stock)
			
			# Update UI
			if ui_instance and is_ui_open:
				ui_instance.refresh_stock_display()
			return

func restock_all_items():
	"""Restock all items to maximum"""
	for item in available_items:
		if item.stock < item.max_stock:
			item.stock = item.max_stock
			stock_updated.emit(item.path, item.stock)
	
	# Update UI
	if ui_instance and is_ui_open:
		ui_instance.refresh_stock_display()

func clear_all_items():
	"""Clear all items from vendor"""
	available_items.clear()
	manual_items.clear()
	
	# Update UI
	if ui_instance and is_ui_open:
		ui_instance.refresh_items()

func get_manual_items() -> Array[ManualVendorItem]:
	"""Get the manual items configuration"""
	return manual_items

func export_configuration() -> Dictionary:
	"""Export vendor configuration for saving/loading"""
	var config = {
		"vendor_type": "manual",
		"vendor_name": vendor_name,
		"vendor_description": vendor_description,
		"vendor_theme": vendor_theme,
		"requires_access": requires_access,
		"required_access_flags": required_access_flags,
		"uses_currency": uses_currency,
		"currency_type": currency_type,
		"free_dispense": free_dispense,
		"unlimited_stock": unlimited_stock,
		"items": []
	}
	
	for item in available_items:
		config.items.append({
			"path": item.path,
			"name": item.name,
			"stock": item.stock,
			"max_stock": item.max_stock,
			"price": item.price
		})
	
	return config

func import_configuration(config: Dictionary):
	"""Import vendor configuration"""
	if config.get("vendor_type") != "manual":
		print("Error: Configuration is not for manual vendor")
		return false
	
	# Apply settings
	vendor_name = config.get("vendor_name", vendor_name)
	vendor_description = config.get("vendor_description", vendor_description)
	vendor_theme = config.get("vendor_theme", vendor_theme)
	requires_access = config.get("requires_access", requires_access)
	required_access_flags = config.get("required_access_flags", required_access_flags)
	uses_currency = config.get("uses_currency", uses_currency)
	currency_type = config.get("currency_type", currency_type)
	free_dispense = config.get("free_dispense", free_dispense)
	unlimited_stock = config.get("unlimited_stock", unlimited_stock)
	
	# Clear existing items
	clear_all_items()
	
	# Add items from config
	var items = config.get("items", [])
	for item_config in items:
		add_item_runtime(
			item_config.get("path", ""),
			item_config.get("name", ""),
			item_config.get("stock", 0),
			item_config.get("max_stock", -1),
			item_config.get("price", 0)
		)
	
	return true
