extends BaseObject
class_name MedicalVendor

# Vendor type constants
enum VendorType {
	MEDICAL,
	CHEMISTRY,
	BLOOD,
	WALL_MED
}

# Current vendor type
@export var vendor_type: VendorType = VendorType.MEDICAL
@export var vendor_name: String = "Wey-Med Plus"
@export var vendor_desc: String = "Medical pharmaceutical dispenser. Provided by Wey-Yu Pharmaceuticals Division(TM)."
@export var vendor_theme: String = "company" # company, uscm, colonial, upp, clf

# Access requirements
@export var requires_access: bool = false
@export var access_flags: Array[String] = ["ACCESS_MARINE_MEDBAY"]

# Flags and properties
@export var unacidable: bool = true
@export var unslashable: bool = false
@export var wrenchable: bool = true
@export var hackable: bool = true

# Health scanning
@export var healthscan: bool = true

# Chemical refill properties
@export var chem_refill_volume: float = 600.0
@export var chem_refill_volume_max: float = 600.0
@export var allow_supply_link_restock: bool = true

# Vendor state
var being_restocked: bool = false
var hacked: bool = false
var broken: bool = false
var powered: bool = true
var supply_link_connected: bool = false
var ui_open: bool = false
var active_tab: String = "Field Supplies"

# Product storage
var listed_products: Array = []
var dynamic_stock_multipliers: Dictionary = {}
var partial_product_stacks: Dictionary = {}

# UI Reference
var ui_instance = null

# Signals
signal item_purchased(item, user)
signal vendor_hacked(vendor)
signal vendor_broken(vendor)
signal vendor_fixed(vendor)
signal item_restocked(item_name, new_amount)

func _ready():
	# Setup base properties
	obj_name = vendor_name
	obj_desc = vendor_desc
	obj_integrity = max_integrity
	
	# Add to groups
	add_to_group("clickable_entities")
	add_to_group("vendors")
	add_to_group("interactable")
	
	# Initialize based on vendor type
	match vendor_type:
		VendorType.MEDICAL:
			populate_medical_products()
		VendorType.CHEMISTRY:
			populate_chemistry_products()
		VendorType.BLOOD:
			populate_blood_products()
		VendorType.WALL_MED:
			populate_wall_med_products()
	
	# Check for supply link on startup
	check_for_supply_link()
	
	# Start processing for automatic restock
	if allow_supply_link_restock:
		set_process(true)

func _process(delta):
	# Only process if we have a supply link and are anchored
	if supply_link_connected and anchored:
		# Restock supplies slowly over time
		if Engine.get_frames_drawn() % 600 == 0:  # Every ~10 seconds at 60fps
			restock_supplies(80)  # 20% chance to restock per item
			restock_reagents(5)   # Small amount of reagents

func interact(user) -> bool:
	# Parent interaction handling
	super.interact(user)
	
	if !powered:
		if user and user.has_method("display_message"):
			user.display_message("The [b]" + obj_name + "[/b] appears to be unpowered!")
		return false
	
	if broken:
		if user and user.has_method("display_message"):
			user.display_message("The [b]" + obj_name + "[/b] appears to be broken!")
		return false
	
	# Check access if required
	if requires_access and !hacked:
		var has_access = false
		
		# Check if user has any of the required access types
		if user and user.has_method("has_access"):
			for access in access_flags:
				if user.has_access(access):
					has_access = true
					break
		
		if !has_access:
			if user and user.has_method("display_message"):
				user.display_message("Access denied.")
			play_audio(preload("res://Sound/machines/buzz-two.ogg"))
			return false
	
	# Open the vendor UI
	open_vendor_ui(user)
	return true

func open_vendor_ui(user):
	# Create UI instance if it doesn't exist
	if ui_instance == null:
		print("Creating new UI instance")
		ui_instance = preload("res://Scenes/UI/Ingame/MedicalVendorUI.tscn").instantiate()
		ui_instance.vendor = self
		
		# Find the canvas layer or UI container
		var ui_layer = get_node_or_null("UILayer")
		var player_ui = null
		
		# Try to find player UI layer if direct UILayer not found
		if user and user.has_node("PlayerUI"):
			player_ui = user.get_node("PlayerUI")
		
		# Add UI to the appropriate parent
		if ui_layer:
			ui_layer.add_child(ui_instance)
			print("Added UI to vendor's UILayer")
		elif player_ui:
			# Add to player's UI instead
			player_ui.add_child(ui_instance)
			print("Added UI to player's UI")
		else:
			# Last resort - find a CanvasLayer
			var canvas_layers = get_tree().get_nodes_in_group("ui_layers")
			if canvas_layers.size() > 0:
				canvas_layers[0].add_child(ui_instance)
				print("Added UI to canvas layer")
			else:
				# Fallback to adding directly to the user
				if user:
					user.add_child(ui_instance)
					print("Added UI to user")
				else:
					# Absolute last resort
					get_tree().root.add_child(ui_instance)
					print("Added UI to root (not ideal)")
	
	# Setup UI and show it
	ui_instance.setup_ui(self, user)
	
	# Replace popup_centered with proper positioning
	if ui_instance.has_method("popup_centered"):
		ui_instance.popup_centered()
	else:
		# Get viewport size for manual centering
		var viewport_size = get_viewport().size
		ui_instance.global_position = Vector2(
			viewport_size.x / 2 - ui_instance.size.x / 2,
			viewport_size.y / 2 - ui_instance.size.y / 2
		)
		ui_instance.show()
		
	ui_open = true
	
	# Play sound
	play_audio(preload("res://Sound/machines/Success.wav"))

func close_vendor_ui():
	if ui_instance:
		ui_instance.hide()
		ui_open = false
		
		# Play sound
		play_audio(preload("res://Sound/Grenades/Pulse.wav"))

func purchase_item(item_path, user):
	if being_restocked:
		if user and user.has_method("display_message"):
			user.display_message("The vendor is currently being restocked!")
		return null
	
	# Try to normalize the path
	if item_path is String and !item_path.is_empty():
		if !ResourceLoader.exists(item_path):
			# Try capitalized version
			var components = item_path.split("/")
			for i in range(components.size()):
				if components[i].length() > 0:
					components[i] = components[i][0].to_upper() + components[i].substr(1)
			var capitalized_path = "/".join(components)
			
			if ResourceLoader.exists(capitalized_path):
				item_path = capitalized_path
	
	# Find the item in listed products
	for product in listed_products:
		if product.size() < 4:  # Skip category headers
			continue
			
		if product[3] == item_path or product[2] == item_path:
			# Check if in stock
			if product[1] <= 0:
				if user and user.has_method("display_message"):
					user.display_message("Out of stock: " + product[0])
				play_audio(preload("res://Sound/machines/buzz-two.ogg"))
				return null
			
			# Create the item - make sure we have a valid path
			var item_scene_path = product[2]
			if !ResourceLoader.exists(item_scene_path):
				print("Error: Cannot find item scene at path: ", item_scene_path)
				return null
				
			var item_instance = load(item_scene_path).instantiate()
			
			# Deduct from stock
			product[1] -= 1
			
			# Update UI if open
			if ui_instance and ui_open:
				ui_instance.update_item_count(product[0], product[1])
			
			# Emit signal
			emit_signal("item_purchased", item_instance, user)
			
			# Play vend sound
			play_audio(preload("res://Sound/machines/vending_drop.ogg"))
			
			# Add item to user's inventory if they have one
			if user and user.has_method("add_item_to_inventory"):
				user.add_item_to_inventory(item_instance)
				return item_instance
			
			# Otherwise, spawn at the user's feet
			elif user:
				item_instance.global_position = user.global_position
				get_parent().add_child(item_instance)
				return item_instance
			
			return item_instance
	
	print("Product not found in listed_products: ", item_path)
	return null

func check_for_supply_link():
	# Check if there's a supply link below us
	var potential_links = []
	
	# Get all objects at our position
	var world = get_node_or_null("/root/World")
	if world and world.has_method("get_objects_at"):
		potential_links = world.get_objects_at(global_position)
	else:
		# Fallback to searching among our siblings
		for node in get_parent().get_children():
			if node.global_position.distance_to(global_position) < 5 and node != self:
				potential_links.append(node)
	
	# Check if any are supply links
	for object in potential_links:
		if object is MedicalSupplyLink:
			if anchored and object.anchored:
				supply_link_connected = true
				return true
	
	supply_link_connected = false
	return false

func toggle_anchored(item, user):
	# Toggle anchored state
	anchored = !anchored
	
	# If anchoring, check for supply link
	if anchored:
		check_for_supply_link()
	else:
		supply_link_connected = false
	
	# Play sound
	if anchored:
		play_audio(preload("res://Sound/handling/Ratchet.ogg"))
	else:
		play_audio(preload("res://Sound/handling/Ratchet.ogg"))
	
	# Update the supply link visuals if there is one
	var supply_links = get_tree().get_nodes_in_group("medical_supply_links")
	for link in supply_links:
		if link.global_position.distance_to(global_position) < 5:
			link.update_visual_state()
	
	# Emit signal
	emit_signal("anchored_changed", anchored)
	
	return true

func handle_mousedrop(user, dropped_item):
	# Handle dropping item onto vendor for restocking
	if dropped_item is Item:
		stock(dropped_item, user)
	return true

func stock(item, user) -> bool:
	if !powered:
		return false
	
	if being_restocked:
		if user and user.has_method("display_message"):
			user.display_message("The vendor is currently being restocked!")
		return false
	
	# Get the item's scene path
	var item_path = item.get_scene_file_path()
	
	# Find the item in listed products
	for product in listed_products:
		if product.size() < 4:  # Skip category headers
			continue
			
		if product[3] == item_path or product[2] == item_path:
			# Try to stock this item
			if product[2] < get_max_stock(product[1]):
				product[2] += 1
				
				# Add to dynamic multipliers if not already tracked
				if !dynamic_stock_multipliers.has(product):
					dynamic_stock_multipliers[product] = [product[2], get_max_stock(product[1])]
				
				# Update UI if open
				if ui_instance and ui_open:
					ui_instance.update_item_count(product[1], product[2])
				
				# Remove item from user's inventory
				if user and user.has_method("remove_item_from_inventory"):
					user.remove_item_from_inventory(item)
					item.queue_free()
				elif item.get_parent():
					item.get_parent().remove_child(item)
					item.queue_free()
				
				# Play stocking sound
				play_audio(preload("res://Sound/machines/vending_drop.ogg"))
				
				# Emit signal
				emit_signal("item_restocked", product[1], product[2])
				
				return true
			else:
				if user and user.has_method("display_message"):
					user.display_message("This vendor is already fully stocked with " + product[1] + "!")
				return false
	
	# Check if it's a reagent container that needs refilling
	if "reagent_container" in item.name.to_lower():
		return try_deduct_chem(item, user)
			
	# Item not found in listed products
	if user and user.has_method("display_message"):
		user.display_message("This vendor doesn't stock this item!")
	return false

func try_deduct_chem(container, user) -> bool:
	# Check if the container needs refilling
	var missing_reagents = 0
	if "reagents" in container and "maximum_volume" in container.reagents:
		missing_reagents = container.reagents.maximum_volume - container.reagents.total_volume
	
	if missing_reagents <= 0:
		return true  # Already full
	
	# Check if we have enough reagents
	if chem_refill_volume < missing_reagents:
		var auto_refill = allow_supply_link_restock && supply_link_connected
		if user and user.has_method("display_message"):
			user.display_message("The vendor blinks red and makes a buzzing noise as it rejects " + container.name + ". Looks like it doesn't have enough reagents " + ("yet" if auto_refill else "left") + ".")
		play_audio(preload("res://Sound/machines/buzz-sigh.ogg"))
		return false
	
	# Deduct reagents
	chem_refill_volume -= missing_reagents
	
	# Play refill sound
	play_audio(preload("res://Sound/effects/refill.ogg"))
	
	# Tell the user
	if user and user.has_method("display_message"):
		user.display_message("The vendor makes a whirring noise as it refills your " + container.name + ".")
	
	# Create a new filled container
	var new_container = load(container.get_scene_file_path()).instantiate()
	
	# Set up the new container's reagents
	if "reagents" in new_container:
		new_container.reagents.maximum_volume = container.reagents.maximum_volume
		new_container.reagents.total_volume = container.reagents.maximum_volume
		
		# You would add the appropriate reagent here based on container type
		# For example: new_container.reagents.add_reagent("tricordrazine", container.reagents.maximum_volume)
	
	# Put the new container in the user's hands
	if user and user.has_method("add_item_to_inventory"):
		# Remove old container
		if user.has_method("remove_item_from_inventory"):
			user.remove_item_from_inventory(container)
		
		# Add new container
		user.add_item_to_inventory(new_container)
	
	# Destroy old container
	container.queue_free()
	
	return true

func cart_restock(cart, user):
	if cart.supplies_remaining <= 0:
		if user and user.has_method("display_message"):
			user.display_message(cart.name + " is empty!")
		return
		
	if being_restocked:
		if user and user.has_method("display_message"):
			user.display_message(obj_name + " is already being restocked!")
		return
	
	# Check if it's a reagent cart
	var restocking_reagents = "reagent" in cart.name.to_lower()
	
	# Start the restocking process
	being_restocked = true
	
	if user and user.has_method("display_message"):
		user.display_message("You start stocking " + cart.supply_descriptor + " into " + obj_name + ".")
	
	# Simulate the restocking process
	while cart.supplies_remaining > 0:
		# Wait a bit
		await get_tree().create_timer(0.5).timeout
		
		# Check if cart or user is still there
		if !is_instance_valid(cart) or (user && !is_instance_valid(user)) or user.global_position.distance_to(global_position) > 64:
			break
		
		if restocking_reagents:
			# Add reagents
			var reagent_added = restock_reagents(min(cart.supplies_remaining, 100))
			if reagent_added <= 0 or chem_refill_volume == chem_refill_volume_max:
				break
			cart.supplies_remaining -= reagent_added
		else:
			# Restock one random item
			if restock_supplies(0, false):
				cart.supplies_remaining -= 1
	
	# Finish restocking
	being_restocked = false
	
	if user and user.has_method("display_message"):
		user.display_message("You finish stocking " + obj_name + " with " + cart.supply_descriptor + ".")

func restock_supplies(prob_to_skip = 80, can_remove = true) -> bool:
	var added_any = false
	
	# Process each product
	for product in listed_products:
		if product.size() < 4:  # Skip category headers
			continue
		
		# Skip with probability prob_to_skip
		if randf() * 100 < prob_to_skip:
			continue
		
		# Get the max stock for this item
		var max_stock = get_max_stock(product[1])
		
		# Add item if below max
		if product[2] < max_stock:
			product[2] += 1
			added_any = true
			
			# Update UI if open
			if ui_instance and ui_open:
				ui_instance.update_item_count(product[1], product[2])
			
			# Emit signal
			emit_signal("item_restocked", product[1], product[2])
		elif product[2] > max_stock and can_remove:
			# Remove excess items
			product[2] -= 1
	
	return added_any

func restock_reagents(amount: float) -> float:
	if chem_refill_volume >= chem_refill_volume_max:
		return 0
	
	var old_value = chem_refill_volume
	chem_refill_volume = min(chem_refill_volume + amount, chem_refill_volume_max)
	
	# Update UI if open
	if ui_instance and ui_open:
		ui_instance.update_reagent_level(chem_refill_volume, chem_refill_volume_max)
	
	return chem_refill_volume - old_value

func get_max_stock(item_name: String) -> int:
	# This would be configured based on the item
	# For now, return a default max stock based on vendor type
	match vendor_type:
		VendorType.MEDICAL:
			return 10
		VendorType.CHEMISTRY:
			return 6
		VendorType.BLOOD:
			return 5
		VendorType.WALL_MED:
			return 4
	return 5

func populate_medical_products():
	listed_products = [
		# FIELD SUPPLIES
		["FIELD SUPPLIES", -1, null, null],
		["Burn Kit", 10, "res://Scenes/Items/Medical/BurnKit.tscn", "burn_kit"],
		["Trauma Kit", 10, "res://Scenes/Items/Medical/TraumaKit.tscn", "trauma_kit"],
		["Ointment", 10, "res://Scenes/Items/Medical/Ointment.tscn", "ointment"],
		["Roll of Gauze", 10, "res://Scenes/Items/Medical/Gauze.tscn", "gauze"],
		["Splints", 10, "res://Scenes/Items/Medical/Splint.tscn", "splint"],
		
		# AUTOINJECTORS
		["AUTOINJECTORS", -1, null, null],
		["Autoinjector (Bicaridine)", 5, "res://Scenes/Items/Medical/AutoInjector_B.tscn", "autoinjector_bicaridine"],
		["Autoinjector (Dexalin+)", 5, "res://Scenes/Items/Medical/AutoInjector_D+.tscn", "autoinjector_dexalinp"],
		["Autoinjector (Epinephrine)", 5, "res://Scenes/Items/Medical/AutoInjector_E.tscn", "autoinjector_adrenaline"],
		["Autoinjector (Kelotane)", 5, "res://Scenes/Items/Medical/AutoInjector_K.tscn", "autoinjector_kelotane"],
		["Autoinjector (Oxycodone)", 5, "res://Scenes/Items/Medical/AutoInjector_Oxycodone.tscn", "autoinjector_oxycodone"],
		["Autoinjector (Tramadol)", 5, "res://Scenes/Items/Medical/AutoInjector_T.tscn", "autoinjector_tramadol"],
		["Autoinjector (Tricord)", 5, "res://Scenes/Items/Medical/AutoInjector_Tricord.tscn", "autoinjector_tricord"],
		
		# LIQUID BOTTLES
		["LIQUID BOTTLES", -1, null, null],
		["Bottle (Bicaridine)", 3, "res://Scenes/Items/Medical/Bottle_Bicaridine.tscn", "bottle_bicaridine"],
		["Bottle (Dylovene)", 3, "res://Scenes/Items/Medical/BottleDylovene.tscn", "bottle_antitoxin"],
		["Bottle (Dexalin)", 3, "res://Scenes/Items/Medical/Bottle_Dexalin.tscn", "bottle_dexalin"],
		["Bottle (Inaprovaline)", 3, "res://Scenes/Items/Medical/Bottle_Inaprovaline.tscn", "bottle_inaprovaline"],
		["Bottle (Kelotane)", 3, "res://Scenes/Items/Medical/Bottle_Kelotane.tscn", "bottle_kelotane"],
		["Bottle (Oxycodone)", 3, "res://Scenes/Items/Medical/Bottle_Oxycodone.tscn", "bottle_oxycodone"],
		["Bottle (Peridaxon)", 3, "res://Scenes/Items/Medical/Bottle_Peridaxon.tscn", "bottle_peridaxon"],
		["Bottle (Tramadol)", 3, "res://Scenes/Items/Medical/Bottle_Tramadol.tscn", "bottle_tramadol"],
		
		# PILL BOTTLES
		["PILL BOTTLES", -1, null, null],
		["Pill Bottle (Bicaridine)", 4, "res://Scenes/Items/Medical/Pill_Bottle_Bicaridine.tscn", "pill_bottle_bicaridine"],
		["Pill Bottle (Dexalin)", 4, "res://Scenes/Items/Medical/Pill_Bottle_Dexalin.tscn", "pill_bottle_dexalin"],
		["Pill Bottle (Dylovene)", 4, "res://Scenes/Items/Medical/Pill_Bottle_D.tscn", "pill_bottle_antitox"],
		["Pill Bottle (Inaprovaline)", 4, "res://Scenes/Items/Medical/Pill_Bottle_Inaprovaline.tscn", "pill_bottle_inaprovaline"],
		["Pill Bottle (Kelotane)", 4, "res://Scenes/Items/Medical/Pill_Bottle_K.tscn", "pill_bottle_kelotane"],
		["Pill Bottle (Peridaxon)", 3, "res://Scenes/Items/Medical/Pill_Bottle_Peridaxon.tscn", "pill_bottle_peridaxon"],
		["Pill Bottle (Tramadol)", 4, "res://Scenes/Items/Medical/Pill_Bottle_T.tscn", "pill_bottle_tramadol"],
		
		# MEDICAL UTILITIES
		["MEDICAL UTILITIES", -1, null, null],
		["Emergency Defibrillator", 3, "res://Scenes/Items/Medical/Emergency_Defibrillator.tscn", "defibrillator"],
		["Surgical Line", 2, "res://Scenes/Items/Medical/Surgical_Line.tscn", "surgical_line"],
		["Synth-Graft", 2, "res://Scenes/Items/Medical/Synth_Graft.tscn", "synthgraft"],
		["Hypospray", 3, "res://Scenes/Items/Medical/Hypospray_Tricordrazine.tscn", "hypospray_tricordrazine"],
		["Health Analyzer", 5, "res://Scenes/Items/Medical/HealthAnalyzer.tscn", "healthanalyzer"],
		["M276 Pattern Medical Storage Rig", 2, "res://Scenes/Items/Medical/Medical_Belt.tscn", "medical_belt"],
		["Medical HUD Glasses", 3, "res://Scenes/Items/Medical/Medical_HUD.tscn", "medical_hud"],
		["Stasis Bag", 3, "res://Scenes/Items/Medical/Cryobag.tscn", "cryobag"],
		["Syringe", 7, "res://Scenes/Items/Medical/Syringe.tscn", "syringe"]
	]

func populate_chemistry_products():
	listed_products = [
		# LIQUID BOTTLES
		["LIQUID BOTTLES", -1, null, null],
		["Bicaridine Bottle", 6, "res://Scenes/Items/Medical/Bottle_Bicaridine.tscn", "bottle_bicaridine"],
		["Dylovene Bottle", 6, "res://Scenes/Items/Medical/Bottle_Antitoxin.tscn", "bottle_antitoxin"],
		["Dexalin Bottle", 6, "res://Scenes/Items/Medical/Bottle_Dexalin.tscn", "bottle_dexalin"],
		["Inaprovaline Bottle", 6, "res://Scenes/Items/Medical/Bottle_Inaprovaline.tscn", "bottle_inaprovaline"],
		["Kelotane Bottle", 6, "res://Scenes/Items/Medical/Bottle_Kelotane.tscn", "bottle_kelotane"],
		["Oxycodone Bottle", 6, "res://Scenes/Items/Medical/Bottle_Oxycodone.tscn", "bottle_oxycodone"],
		["Peridaxon Bottle", 6, "res://Scenes/Items/Medical/Bottle_Peridaxon.tscn", "bottle_peridaxon"],
		["Tramadol Bottle", 6, "res://Scenes/Items/Medical/Bottle_Tramadol.tscn", "bottle_tramadol"],
		
		# MISCELLANEOUS
		["MISCELLANEOUS", -1, null, null],
		["Beaker (60 Units)", 3, "res://Scenes/Items/Medical/Beaker.tscn", "beaker"],
		["Beaker, Large (120 Units)", 3, "res://Scenes/Items/Medical/Beaker_Large.tscn", "beaker_large"],
		["Box of Pill Bottles", 2, "res://Scenes/Items/Medical/Pill_Bottle_Box.tscn", "pill_bottle_box"],
		["Dropper", 3, "res://Scenes/Items/Medical/Dropper.tscn", "dropper"],
		["Syringe", 7, "res://Scenes/Items/Medical/Syringe.tscn", "syringe"]
	]

func populate_blood_products():
	listed_products = [
		# BLOOD PACKS
		["BLOOD PACKS", -1, null, null],
		["A+ Blood Pack", 5, "res://Scenes/Items/Medical/Blood_APlus.tscn", "blood_aplus"],
		["A- Blood Pack", 5, "res://Scenes/Items/Medical/Blood_AMinus.tscn", "blood_aminus"],
		["B+ Blood Pack", 5, "res://Scenes/Items/Medical/Blood_BPlus.tscn", "blood_bplus"],
		["B- Blood Pack", 5, "res://Scenes/Items/Medical/Blood_BMinus.tscn", "blood_bminus"],
		["O+ Blood Pack", 5, "res://Scenes/Items/Medical/Blood_OPlus.tscn", "blood_oplus"],
		["O- Blood Pack", 5, "res://Scenes/Items/Medical/Blood_OMinus.tscn", "blood_ominus"],
		
		# MISCELLANEOUS
		["MISCELLANEOUS", -1, null, null],
		["Empty Blood Pack", 5, "res://Scenes/Items/Medical/Blood_Empty.tscn", "blood_empty"]
	]

func populate_wall_med_products():
	listed_products = [
		# SUPPLIES
		["SUPPLIES", -1, null, null],
		["First-Aid Autoinjector", 2, "res://Scenes/Items/Medical/Autoinjector_Skillless.tscn", "autoinjector_skillless"],
		["Pain-Stop Autoinjector", 2, "res://Scenes/Items/Medical/Autoinjector_Skillless_Tramadol.tscn", "autoinjector_skillless_tramadol"],
		["Roll Of Gauze", 4, "res://Scenes/Items/Medical/Gauze.tscn", "gauze"],
		["Ointment", 4, "res://Scenes/Items/Medical/Ointment.tscn", "ointment"],
		["Medical Splints", 4, "res://Scenes/Items/Medical/Splint.tscn", "splint"],
		
		# UTILITY
		["UTILITY", -1, null, null],
		["HF2 Health Analyzer", 2, "res://Scenes/Items/Medical/HealthAnalyzer.tscn", "healthanalyzer"]
	]

func get_current_product_categories() -> Array:
	var categories = []
	
	for product in listed_products:
		# Category headers have -1 as their second element
		if product.size() >= 2 and product[1] == -1:
			categories.append(product[0])
	
	return categories

func get_products_in_category(category: String) -> Array:
	var result = []
	var in_category = false
	
	for product in listed_products:
		# Category headers have -1 as their second element
		if product.size() >= 2 and product[1] == -1:
			in_category = (product[0] == category)
			continue
		
		if in_category:
			# Create dictionary with proper keys for consistency
			var product_dict = {
				"name": product[0],  # Product name
				"count": product[1] if product[1] != null else 0,  # Count with null check
				"path": product[2] if product[2] != null else "",  # Scene path with null check
				"id": product[3] if product.size() > 3 and product[3] != null else 
					  (product[2].get_file().get_basename() if product[2] != null else "unknown")
			}
			
			result.append(product_dict)
	
	return result

func obj_break(damage_flag = ""):
	if broken:
		return
	
	broken = true
	
	# Play break sound
	play_audio(preload("res://Sound/effects/glassbreak2.ogg"))
	
	# Close UI if open
	if ui_open:
		close_vendor_ui()
	
	# Emit signal
	emit_signal("vendor_broken", self)

func fix():
	if !broken:
		return
	
	broken = false
	
	# Play fix sound
	play_audio(preload("res://Sound/items/Welder.ogg"))
	
	# Emit signal
	emit_signal("vendor_fixed", self)

func play_audio(sound_stream, volume_db = 0.0):
	var audio_player = get_node_or_null("AudioStreamPlayer2D")
	if audio_player:
		audio_player.stream = sound_stream
		audio_player.volume_db = volume_db
		audio_player.play()
