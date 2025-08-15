extends Node

var hair_styles = []
var facial_hair_styles = []
var clothing_options = []
var underwear_options = []
var undershirt_options = []
var background_textures = []
var races = []
var occupations = []
var occupation_loadouts = {}
var inhand_sprites = {}
var item_database = {}

const BASE_HUMAN_PATH = "res://Assets/Human/"
const HAIR_STYLES_PATH = "res://Assets/Human/Hair/"
const FACIAL_HAIR_PATH = "res://Assets/Human/FacialHair/"
const CLOTHING_PATH = "res://Assets/Human/Clothing/"
const UNDERWEAR_PATH = "res://Assets/Human/UnderWear/"
const UNDERSHIRT_PATH = "res://Assets/Human/UnderShirt/"
const BACKGROUNDS_PATH = "res://Assets/Backgrounds/"
const INHAND_PATH = "res://Graphics/inhand/"
const ASSET_CONFIG_PATH = "res://Config/character_assets.json"
const OCCUPATION_LOADOUTS_PATH = "res://Config/occupation_loadouts.json"
const ITEMS_DATABASE_PATH = "res://Config/items_database.json"

var _resource_cache = {}

func _init():
	call_deferred("_initialize_after_registry")

func _initialize_after_registry():
	if not has_node("/root/AssetRegistry"):
		print("Warning: AssetRegistry not found, using fallback mode")
	
	_load_defaults()
	_load_item_database()
	_scan_assets_from_registry()
	_load_config_file()
	_load_occupation_loadouts()
	_verify_assets()
	print("Asset Manager initialized with ", _get_total_asset_count(), " assets")
	print("In-hand sprites loaded: ", inhand_sprites.size())
	print("Occupation loadouts loaded: ", occupation_loadouts.size())
	print("Items in database: ", item_database.size())

func _load_item_database():
	if FileAccess.file_exists(ITEMS_DATABASE_PATH):
		var file = FileAccess.open(ITEMS_DATABASE_PATH, FileAccess.READ)
		if file:
			var json_text = file.get_as_text()
			file.close()
			
			var json_result = JSON.parse_string(json_text)
			if json_result and json_result is Dictionary:
				item_database = json_result
	else:
		_create_default_item_database()

func _create_default_item_database():
	item_database = {
		"Synthetic_Jumpsuit": {
			"scene_path": "res://Scenes/Items/Clothing/Synthetic_Jumpsuit.tscn",
			"equip_slot": 6,
			"storage_type": 0
		},
		"leather_boots": {
			"scene_path": "res://Scenes/Items/Clothing/leather_boots.tscn",
			"equip_slot": 10,
			"storage_type": 0
		},
		"Utility_Belt": {
			"scene_path": "res://Scenes/Items/Clothing/Utility_Belt.tscn",
			"equip_slot": 15,
			"storage_type": 1,
			"storage_max_size": 12
		},
		"Health_Hud": {
			"scene_path": "res://Scenes/Items/Clothing/Health_Hud.tscn",
			"equip_slot": 2,
			"storage_type": 0
		},
		"Engineering_Beret": {
			"scene_path": "res://Scenes/Items/Clothing/Engineering_Beret.tscn",
			"equip_slot": 1,
			"storage_type": 0
		},
		"Smart_Pack": {
			"scene_path": "res://Scenes/Items/Clothing/Smart_Pack.tscn",
			"equip_slot": 3,
			"storage_type": 1,
			"storage_max_size": 20
		},
		"Medical_Pouch": {
			"scene_path": "res://Scenes/Items/Clothing/Medical_Pouch.tscn",
			"equip_slot": 16,
			"storage_type": 1,
			"storage_max_size": 6
		},
		"Utility_Pouch": {
			"scene_path": "res://Scenes/Items/Clothing/Utility_Pouch.tscn",
			"equip_slot": 17,
			"storage_type": 1,
			"storage_max_size": 4
		},
		"Wrench": {
			"scene_path": "res://Objects/Tools/Wrench.tscn",
			"equip_slot": 14,
			"storage_type": 0
		},
		"Screwdriver": {
			"scene_path": "res://Objects/Tools/Screwdriver.tscn",
			"equip_slot": 17,
			"storage_type": 0
		},
		"Flashlight": {
			"scene_path": "res://Objects/Tools/Flashlight.tscn",
			"equip_slot": 16,
			"storage_type": 0
		},
		"Wire_Coil": {
			"scene_path": "res://Objects/Materials/WireCoil.tscn",
			"equip_slot": -1,
			"storage_type": 0
		},
		"Metal_Sheets": {
			"scene_path": "res://Objects/Materials/MetalSheets.tscn",
			"equip_slot": -1,
			"storage_type": 0
		},
		"Multitool": {
			"scene_path": "res://Objects/Tools/Multitool.tscn",
			"equip_slot": -1,
			"storage_type": 0
		},
		"Crowbar": {
			"scene_path": "res://Objects/Tools/Crowbar.tscn",
			"equip_slot": -1,
			"storage_type": 0
		},
		"Wire_Cutters": {
			"scene_path": "res://Objects/Tools/WireCutters.tscn",
			"equip_slot": -1,
			"storage_type": 0
		},
		"Cable_Coil": {
			"scene_path": "res://Objects/Materials/CableCoil.tscn",
			"equip_slot": -1,
			"storage_type": 0
		}
	}
	_save_item_database()

func _save_item_database():
	var directory = DirAccess.open("res://")
	if not directory.dir_exists("res://Config"):
		directory.make_dir("Config")
	
	var file = FileAccess.open(ITEMS_DATABASE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(item_database, "  "))
		file.close()

func create_item_from_name(item_name: String) -> Node:
	print("AssetManager: Creating item: ", item_name)
	
	# First check the existing database
	if item_database.has(item_name):
		var item_data = item_database[item_name]
		var scene_path = item_data.get("scene_path", "")
		
		if scene_path != "" and ResourceLoader.exists(scene_path):
			var scene = load(scene_path)
			if scene:
				var item = scene.instantiate()
				if item:
					_configure_item(item, item_name, item_data)
					print("AssetManager: Created item from database: ", item_name)
					return item
	
	# If not in database, try to find dynamically
	print("AssetManager: Item not in database, searching dynamically: ", item_name)
	return _create_item_dynamically(item_name)

func _create_item_dynamically(item_name: String) -> Node:
	var scene_path = _find_item_scene_path(item_name)
	
	if scene_path != "":
		print("AssetManager: Found scene at: ", scene_path)
		var scene = load(scene_path)
		if scene:
			var item = scene.instantiate()
			if item:
				# Auto-configure the item with reasonable defaults
				_auto_configure_item(item, item_name, scene_path)
				print("AssetManager: Successfully created dynamic item: ", item_name)
				return item
		else:
			print("AssetManager: Failed to load scene: ", scene_path)
	
	# Fallback to placeholder
	print("AssetManager: Could not find scene for item: ", item_name, ", creating placeholder")
	return _create_placeholder_item(item_name, {})

func _find_item_scene_path(item_name: String) -> String:
	# Common paths to search for items
	var search_paths = [
		"res://Scenes/" + item_name + ".tscn",
		"res://Scenes/Items/" + item_name + ".tscn", 
		"res://Scenes/Items/Armor/" + item_name + ".tscn",
		"res://Scenes/Items/Uniform/" + item_name + ".tscn",
		"res://Scenes/Items/Backpacks/" + item_name + ".tscn",
		"res://Scenes/Items/Belts/" + item_name + ".tscn",
		"res://Scenes/Items/Boots/" + item_name + ".tscn",
		"res://Scenes/Items/Gloves/" + item_name + ".tscn",
		"res://Scenes/Items/Engineering/" + item_name + ".tscn",
		"res://Scenes/Items/Grenades/" + item_name + ".tscn",
		"res://Scenes/Items/Guns/" + item_name + ".tscn",
		"res://Scenes/Items/Hats/" + item_name + ".tscn",
		"res://Scenes/Items/Medical/" + item_name + ".tscn",
		"res://Scenes/Items/Melee/" + item_name + ".tscn",
		"res://Scenes/Items/Misc/" + item_name + ".tscn",
		"res://Scenes/Items/Pouches/" + item_name + ".tscn",
		"res://Scenes/Items/Huds/" + item_name + ".tscn",
		"res://Scenes/Items/Masks/" + item_name + ".tscn"
	]
	
	# Check common paths first
	for path in search_paths:
		if ResourceLoader.exists(path):
			print("AssetManager: Found item at common path: ", path)
			return path
	
	# If we have asset registry, search through all scenes
	if has_node("/root/AssetRegistry"):
		var asset_registry = get_node("/root/AssetRegistry")
		if asset_registry.has_method("get_assets_by_type"):
			var all_scenes = asset_registry.get_assets_by_type("scenes")
			
			for scene_path in all_scenes:
				var file_name = scene_path.get_file().get_basename()
				if file_name == item_name:
					print("AssetManager: Found item in asset registry: ", scene_path)
					return scene_path
	
	# Fallback: search through all .tscn files recursively in Objects directory
	var found_path = _recursive_scene_search(item_name, "res://Objects")
	if found_path != "":
		return found_path
	
	# Last resort: search entire project
	return _recursive_scene_search(item_name, "res://")

func _recursive_scene_search(item_name: String, directory: String) -> String:
	var dir = DirAccess.open(directory)
	if not dir:
		return ""
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		var full_path = directory + "/" + file_name
		
		if dir.current_is_dir() and not file_name.begins_with("."):
			# Skip some common directories that won't have items
			if file_name in ["addons", ".godot", ".git", ".import"]:
				file_name = dir.get_next()
				continue
				
			var result = _recursive_scene_search(item_name, full_path)
			if result != "":
				return result
		elif file_name.ends_with(".tscn"):
			var base_name = file_name.get_basename()
			if base_name == item_name:
				print("AssetManager: Found item via recursive search: ", full_path)
				return full_path
		
		file_name = dir.get_next()
	
	return ""

func _auto_configure_item(item: Node, item_name: String, scene_path: String):
	print("AssetManager: Auto-configuring item: ", item_name)
	
	# Set basic properties
	if "obj_name" in item:
		item.obj_name = item_name
	else:
		item.set_meta("obj_name", item_name)
	
	if "pickupable" in item:
		item.pickupable = true
	else:
		item.set_meta("pickupable", true)
	
	# Try to infer equip slot from path and name
	var equip_slot = _infer_equip_slot(item_name, scene_path)
	if equip_slot != -1:
		print("AssetManager: Inferred equip slot ", equip_slot, " for ", item_name)
		if "valid_slots" in item:
			if not item.valid_slots.has(equip_slot):
				item.valid_slots.append(equip_slot)
		else:
			item.set_meta("valid_slots", [equip_slot])
	
	# Try to infer storage properties
	if _is_storage_item_name(item_name):
		var storage_info = _infer_storage_properties(item_name)
		print("AssetManager: Configuring storage for ", item_name, ": ", storage_info)
		
		if "storage_type" in item:
			item.storage_type = storage_info.storage_type
		else:
			item.set_meta("storage_type", storage_info.storage_type)
		
		if storage_info.storage_type > 0:
			if "storage_items" in item:
				if not item.storage_items:
					item.storage_items = []
			else:
				item.set_meta("storage_items", [])
			
			if "storage_max_size" in item:
				item.storage_max_size = storage_info.max_size
			else:
				item.set_meta("storage_max_size", storage_info.max_size)
			
			if "storage_current_size" in item:
				item.storage_current_size = 0
			else:
				item.set_meta("storage_current_size", 0)

func _infer_equip_slot(item_name: String, scene_path: String) -> int:
	var name_lower = item_name.to_lower()
	var path_lower = scene_path.to_lower()
	
	# Head items
	if "hat" in name_lower or "helmet" in name_lower or "beret" in name_lower or "cap" in name_lower:
		return 1  # HEAD
	if "head" in path_lower:
		return 1
	
	# Eye items  
	if "glasses" in name_lower or "goggles" in name_lower or "hud" in name_lower:
		return 2  # GLASSES
	if "eyes" in path_lower:
		return 2
	
	# Back items
	if "pack" in name_lower or "backpack" in name_lower:
		return 3  # BACK
	if "back" in path_lower:
		return 3
	
	# Mask items
	if "mask" in name_lower:
		return 4  # WEAR_MASK
	if "mask" in path_lower:
		return 4
	
	# Uniform items
	if "jumpsuit" in name_lower or "uniform" in name_lower:
		return 6  # W_UNIFORM
	if "uniform" in path_lower:
		return 6
	
	# Suit items
	if "suit" in name_lower and "jumpsuit" not in name_lower:
		return 7  # WEAR_SUIT
	if "suit" in path_lower:
		return 7
	
	# Gloves
	if "gloves" in name_lower:
		return 9  # GLOVES
	if "gloves" in path_lower:
		return 9
	
	# Shoes
	if "boots" in name_lower or "shoes" in name_lower:
		return 10  # SHOES
	if "shoes" in path_lower:
		return 10
	
	# ID
	if "id" in name_lower:
		return 12  # WEAR_ID
	
	# Belt
	if "belt" in name_lower:
		return 15  # BELT
	if "belt" in path_lower:
		return 15
	
	# Tools and handheld items
	if ("tool" in path_lower or "equipment" in path_lower or 
		"wrench" in name_lower or "screwdriver" in name_lower or 
		"flashlight" in name_lower or "multitool" in name_lower or
		"crowbar" in name_lower or "cutters" in name_lower):
		return 14  # RIGHT_HAND (tools usually go in right hand)
	
	return -1  # No specific slot

func _is_storage_item_name(item_name: String) -> bool:
	var name_lower = item_name.to_lower()
	return ("belt" in name_lower or "pack" in name_lower or "bag" in name_lower or 
			"pouch" in name_lower or "container" in name_lower or "box" in name_lower)

func _infer_storage_properties(item_name: String) -> Dictionary:
	var name_lower = item_name.to_lower()
	
	if "utility_belt" in name_lower or "tool_belt" in name_lower:
		return {"storage_type": 1, "max_size": 12}
	elif "belt" in name_lower:
		return {"storage_type": 1, "max_size": 8}
	elif "smart_pack" in name_lower or "engineering_pack" in name_lower:
		return {"storage_type": 1, "max_size": 20}
	elif "backpack" in name_lower or "pack" in name_lower:
		return {"storage_type": 1, "max_size": 15}
	elif "medical_pouch" in name_lower:
		return {"storage_type": 1, "max_size": 6}
	elif "utility_pouch" in name_lower:
		return {"storage_type": 1, "max_size": 4}
	elif "pouch" in name_lower:
		return {"storage_type": 1, "max_size": 5}
	elif "bag" in name_lower:
		return {"storage_type": 1, "max_size": 10}
	else:
		return {"storage_type": 1, "max_size": 8}

func _create_placeholder_item(item_name: String, item_data: Dictionary) -> Node:
	var item = Node2D.new()
	item.name = item_name
	item.set_meta("obj_name", item_name)
	item.set_meta("pickupable", true)
	item.set_meta("equip_slot", item_data.get("equip_slot", -1))
	item.set_meta("storage_type", item_data.get("storage_type", 0))
	
	var icon = Sprite2D.new()
	icon.name = "Icon"
	var image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.5, 0.5, 0.5, 1.0))
	icon.texture = ImageTexture.create_from_image(image)
	item.add_child(icon)
	
	if item_data.get("storage_type", 0) > 0:
		item.set_meta("storage_items", [])
		item.set_meta("storage_max_size", item_data.get("storage_max_size", 10))
		item.set_meta("storage_current_size", 0)
	
	return item

func _configure_item(item: Node, item_name: String, item_data: Dictionary):
	if "obj_name" in item:
		item.obj_name = item_name
	else:
		item.set_meta("obj_name", item_name)
	
	if "pickupable" in item:
		item.pickupable = true
	else:
		item.set_meta("pickupable", true)
	
	var equip_slot = item_data.get("equip_slot", -1)
	if equip_slot != -1:
		if "valid_slots" in item:
			if not item.valid_slots.has(equip_slot):
				item.valid_slots.append(equip_slot)
		else:
			item.set_meta("valid_slots", [equip_slot])
	
	var storage_type = item_data.get("storage_type", 0)
	if storage_type > 0:
		if "storage_type" in item:
			item.storage_type = storage_type
		else:
			item.set_meta("storage_type", storage_type)
		
		if "storage_items" in item:
			if not item.storage_items:
				item.storage_items = []
		else:
			item.set_meta("storage_items", [])
		
		var max_size = item_data.get("storage_max_size", 10)
		if "storage_max_size" in item:
			item.storage_max_size = max_size
		else:
			item.set_meta("storage_max_size", max_size)
		
		if "storage_current_size" in item:
			item.storage_current_size = 0
		else:
			item.set_meta("storage_current_size", 0)

func apply_occupation_loadout(entity: Node, occupation_name: String) -> bool:
	if not entity:
		print("No entity provided for loadout application")
		return false
	
	var inventory_system = entity.get_node_or_null("InventorySystem")
	if not inventory_system:
		print("Entity has no InventorySystem")
		return false
	
	var loadout = get_occupation_loadout(occupation_name)
	if loadout.is_empty():
		print("No loadout found for occupation: ", occupation_name)
		return false
	
	print("Applying loadout for occupation: ", occupation_name)
	
	var applied_items = {}
	
	var clothing = loadout.get("clothing", {})
	for slot_name in clothing:
		var item_name = clothing[slot_name]
		if item_name and item_name != "":
			var slot_id = _get_slot_id_from_loadout_name(slot_name)
			if slot_id != -1:
				var item = create_item_from_name(item_name)
				if item:
					if inventory_system.equip_item(item, slot_id):
						applied_items[slot_id] = item
						print("Equipped ", item_name, " to slot ", slot_id)
					else:
						print("Failed to equip ", item_name, " to slot ", slot_id)
						item.queue_free()
	
	var inventory = loadout.get("inventory", {})
	for slot_name in inventory:
		var item_name = inventory[slot_name]
		if item_name and item_name != "":
			var slot_id = _get_slot_id_from_loadout_name(slot_name)
			if slot_id != -1:
				var item = create_item_from_name(item_name)
				if item:
					if inventory_system.equip_item(item, slot_id):
						applied_items[slot_id] = item
						print("Equipped ", item_name, " to slot ", slot_id)
					else:
						print("Failed to equip ", item_name, " to slot ", slot_id)
						item.queue_free()
	
	var storage_contents = loadout.get("storage_contents", {})
	for storage_item_name in storage_contents:
		var items_to_add = storage_contents[storage_item_name]
		var storage_item = _find_item_by_name(applied_items, storage_item_name)
		
		if storage_item and items_to_add is Array:
			for item_name in items_to_add:
				if item_name and item_name != "":
					var item = create_item_from_name(item_name)
					if item:
						if _add_item_to_storage(storage_item, item):
							print("Added ", item_name, " to storage ", storage_item_name)
						else:
							print("Failed to add ", item_name, " to storage ", storage_item_name)
							item.queue_free()
	
	print("Loadout application completed for ", occupation_name)
	return true

func _find_item_by_name(applied_items: Dictionary, item_name: String) -> Node:
	for slot_id in applied_items:
		var item = applied_items[slot_id]
		if item:
			var obj_name = item.get("obj_name", "") if "obj_name" in item else item.get_meta("obj_name", "")
			if obj_name == item_name:
				return item
	return null

func _add_item_to_storage(storage_item: Node, item: Node) -> bool:
	if not storage_item or not item:
		return false
	
	var storage_type = storage_item.get("storage_type") if "storage_type" in storage_item else storage_item.get_meta("storage_type", 0)
	if storage_type == 0:
		return false
	
	var storage_items = storage_item.get("storage_items") if "storage_items" in storage_item else storage_item.get_meta("storage_items", [])
	var max_size = storage_item.get("storage_max_size") if "storage_max_size" in storage_item else storage_item.get_meta("storage_max_size", 10)
	var current_size = storage_item.get("storage_current_size") if "storage_current_size" in storage_item else storage_item.get_meta("storage_current_size", 0)
	
	var item_size = item.get("w_class") if "w_class" in item else item.get_meta("w_class", 1)
	
	if current_size + item_size > max_size:
		return false
	
	if item.get_parent():
		item.get_parent().remove_child(item)
	
	storage_item.add_child(item)
	item.position = Vector2.ZERO
	item.visible = false
	
	storage_items.append(item)
	current_size += item_size
	
	if "storage_items" in storage_item:
		storage_item.storage_items = storage_items
	else:
		storage_item.set_meta("storage_items", storage_items)
	
	if "storage_current_size" in storage_item:
		storage_item.storage_current_size = current_size
	else:
		storage_item.set_meta("storage_current_size", current_size)
	
	return true

func _get_slot_id_from_loadout_name(slot_name: String) -> int:
	match slot_name:
		"HEAD": return 1
		"GLASSES", "EYES": return 2
		"BACK": return 3
		"WEAR_MASK", "MASK": return 4
		"W_UNIFORM", "UNIFORM": return 6
		"WEAR_SUIT", "SUIT": return 7
		"EARS": return 8
		"GLOVES": return 9
		"SHOES": return 10
		"WEAR_ID", "ID": return 12
		"LEFT_HAND": return 13
		"RIGHT_HAND": return 14
		"BELT": return 15
		"L_STORE": return 16
		"R_STORE": return 17
		"S_STORE": return 18
		_: return -1

func _load_defaults():
	races = []
	occupations = ["Engineer", "Security", "Medical", "Science", "Command", "Cargo"]
	occupation_loadouts = {}
	inhand_sprites = {}
	
	hair_styles = [{"name": "None", "texture": null, "sex": -1}]
	facial_hair_styles = [{"name": "None", "texture": null, "sex": 0}]
	clothing_options = [{"name": "None", "textures": {}, "sex": -1}]
	
	underwear_options = [
		{"name": "Trunks", "texture": "res://Assets/Human/UnderWear/Underwear_1.png", "sex": 0},
		{"name": "Panties", "texture": "res://Assets/Human/UnderWear/Underwear_4.png", "sex": 1}
	]
	
	undershirt_options = [
		{"name": "None", "texture": null, "sex": 0},
		{"name": "SportsBra", "texture": "res://Assets/Human/UnderShirt/UnderShirt_5.png", "sex": 1},
	]
	
	background_textures = [{"name": "Space", "texture": "res://Assets/Backgrounds/Space.png"}]
	
	_setup_default_loadouts()

func _setup_default_loadouts():
	occupation_loadouts = {
		"Synthetic": {
			"display_name": "Synthetic",
			"description": "Medical and Engineering assistance unit",
			"clothing": {
				"W_UNIFORM": "Synthetic_Jumpsuit",
				"SHOES": "leather_boots",
				"GLOVES": "leather_gloves",
				"BELT": "Utility_Belt",
				"EYES": "Health_Hud",
				"MASK": null,
				"HEAD": "Black_Beret"
			},
			"inventory": {
				"LEFT_HAND": null,
				"RIGHT_HAND": "telebaton",
				"BACK": "Smart_Pack",
				"L_STORE": "Medical_Pouch",
				"R_STORE": "Utility_Pouch"
			},
			"storage_contents": {
				"Smart_Pack": ["Wire_Coil", "Metal_Sheets", "Multitool"],
				"Utility_Belt": ["Crowbar", "Wire_Cutters", "Cable_Coil"]
			}
		},
		"Engineer": {
			"display_name": "Engineer",
			"description": "Station maintenance and repair specialist",
			"clothing": {
				"W_UNIFORM": "Engineer Jumpsuit",
				"SHOES": "Work Boots",
				"BELT": "Tool Belt",
				"HEAD": "Hard Hat"
			},
			"inventory": {
				"LEFT_HAND": null,
				"RIGHT_HAND": "Wrench",
				"BACK": "Engineering Backpack",
				"L_STORE": "Flashlight",
				"R_STORE": "Screwdriver"
			},
			"storage_contents": {
				"Engineering Backpack": ["Wire Coil", "Metal Sheets", "Multitool"],
				"Tool Belt": ["Crowbar", "Wire Cutters", "Cable Coil"]
			}
		},
		"Security": {
			"display_name": "Security Officer",
			"description": "Station law enforcement and protection",
			"clothing": {
				"W_UNIFORM": "Security Jumpsuit",
				"SHOES": "Combat Boots",
				"BELT": "Security Belt",
				"HEAD": "Security Helmet",
				"GLOVES": "Combat Gloves"
			},
			"inventory": {
				"LEFT_HAND": null,
				"RIGHT_HAND": "Stun Baton",
				"BACK": "Security Backpack",
				"L_STORE": "Flash",
				"R_STORE": "Handcuffs"
			},
			"storage_contents": {
				"Security Backpack": ["Taser", "Pepper Spray", "Evidence Bag"],
				"Security Belt": ["Handcuffs", "Flash", "Security Radio"]
			}
		},
		"Medical": {
			"display_name": "Medical Doctor",
			"description": "Station healthcare and emergency response",
			"clothing": {
				"W_UNIFORM": "Medical Scrubs",
				"SHOES": "Medical Shoes",
				"BELT": "Medical Belt",
				"HEAD": "Surgical Cap",
				"GLOVES": "Latex Gloves"
			},
			"inventory": {
				"LEFT_HAND": null,
				"RIGHT_HAND": "Medical Scanner",
				"BACK": "Medical Backpack",
				"L_STORE": "Syringe",
				"R_STORE": "Pill Bottle"
			},
			"storage_contents": {
				"Medical Backpack": ["Bandages", "Surgery Tools", "Medicine Kit"],
				"Medical Belt": ["Syringe", "Pill Bottle", "Medical Tricorder"]
			}
		},
		"Science": {
			"display_name": "Scientist",
			"description": "Research and development specialist",
			"clothing": {
				"W_UNIFORM": "Science Jumpsuit",
				"SHOES": "Lab Shoes",
				"BELT": "Science Belt",
				"GLASSES": "Science Goggles",
				"GLOVES": "Lab Gloves"
			},
			"inventory": {
				"LEFT_HAND": null,
				"RIGHT_HAND": "Scanner",
				"BACK": "Science Backpack",
				"L_STORE": "Test Tube",
				"R_STORE": "Data Pad"
			},
			"storage_contents": {
				"Science Backpack": ["Research Materials", "Lab Equipment", "Computer Disk"],
				"Science Belt": ["Sample Container", "Analyzer", "Research Notes"]
			}
		},
		"Command": {
			"display_name": "Command Officer",
			"description": "Station leadership and coordination",
			"clothing": {
				"W_UNIFORM": "Command Jumpsuit",
				"SHOES": "Officer Boots",
				"BELT": "Command Belt",
				"HEAD": "Command Cap",
				"WEAR_ID": "Command ID"
			},
			"inventory": {
				"LEFT_HAND": null,
				"RIGHT_HAND": "Command Tablet",
				"BACK": "Command Backpack",
				"L_STORE": "Command Radio",
				"R_STORE": "Access Card"
			},
			"storage_contents": {
				"Command Backpack": ["Station Maps", "Command Codes", "Emergency Kit"],
				"Command Belt": ["Access Cards", "Command Radio", "Authorization Device"]
			}
		},
		"Cargo": {
			"display_name": "Cargo Technician",
			"description": "Supply management and logistics",
			"clothing": {
				"W_UNIFORM": "Cargo Jumpsuit",
				"SHOES": "Work Boots",
				"BELT": "Cargo Belt",
				"GLOVES": "Work Gloves"
			},
			"inventory": {
				"LEFT_HAND": null,
				"RIGHT_HAND": "Cargo Scanner",
				"BACK": "Cargo Backpack",
				"L_STORE": "Manifest",
				"R_STORE": "Label Printer"
			},
			"storage_contents": {
				"Cargo Backpack": ["Shipping Labels", "Cargo Manifest", "Inventory Scanner"],
				"Cargo Belt": ["Tape", "Markers", "Inventory Device"]
			}
		}
	}

func get_resource(path):
	if path == null or path.is_empty():
		return null
	
	if _resource_cache.has(path):
		return _resource_cache[path]
	
	if has_node("/root/AssetRegistry"):
		var asset_registry = get_node("/root/AssetRegistry")
		var resource = asset_registry.get_preloaded_asset(path)
		if resource != null:
			_resource_cache[path] = resource
			return resource
	
	if ResourceLoader.exists(path):
		var resource = load(path)
		_resource_cache[path] = resource
		return resource
	
	return null

func get_inhand_texture(item_name: String, hand: String) -> Texture2D:
	var texture_key = item_name + "_" + hand
	
	if inhand_sprites.has(texture_key):
		var texture_path = inhand_sprites[texture_key]
		return get_resource(texture_path)
	
	return null

func has_inhand_sprites(item_name: String) -> bool:
	var left_key = item_name + "_left"
	var right_key = item_name + "_right"
	
	return inhand_sprites.has(left_key) or inhand_sprites.has(right_key)

func get_inhand_item_names() -> Array:
	var item_names = []
	
	for sprite_key in inhand_sprites.keys():
		if sprite_key.ends_with("_left") or sprite_key.ends_with("_right"):
			var item_name = sprite_key.replace("_left", "").replace("_right", "")
			if item_name not in item_names:
				item_names.append(item_name)
	
	return item_names

func get_occupation_loadout(occupation_name: String) -> Dictionary:
	return occupation_loadouts.get(occupation_name, {})

func get_occupation_display_name(occupation_name: String) -> String:
	var loadout = get_occupation_loadout(occupation_name)
	if loadout.has("display_name"):
		return loadout.display_name
	return occupation_name

func get_occupation_description(occupation_name: String) -> String:
	var loadout = get_occupation_loadout(occupation_name)
	return loadout.get("description", "No description available")

func get_occupation_clothing(occupation_name: String) -> Dictionary:
	var loadout = get_occupation_loadout(occupation_name)
	return loadout.get("clothing", {})

func get_occupation_inventory(occupation_name: String) -> Dictionary:
	var loadout = get_occupation_loadout(occupation_name)
	return loadout.get("inventory", {})

func get_occupation_storage_contents(occupation_name: String) -> Dictionary:
	var loadout = get_occupation_loadout(occupation_name)
	return loadout.get("storage_contents", {})

func add_occupation_loadout(occupation_name: String, loadout_data: Dictionary):
	occupation_loadouts[occupation_name] = loadout_data
	if occupation_name not in occupations:
		occupations.append(occupation_name)
	_save_occupation_loadouts()

func remove_occupation_loadout(occupation_name: String):
	if occupation_loadouts.has(occupation_name):
		occupation_loadouts.erase(occupation_name)
		occupations.erase(occupation_name)
		_save_occupation_loadouts()

func add_item_to_database(item_name: String, item_data: Dictionary):
	item_database[item_name] = item_data
	_save_item_database()

func remove_item_from_database(item_name: String):
	if item_database.has(item_name):
		item_database.erase(item_name)
		_save_item_database()

func _load_occupation_loadouts():
	if FileAccess.file_exists(OCCUPATION_LOADOUTS_PATH):
		var file = FileAccess.open(OCCUPATION_LOADOUTS_PATH, FileAccess.READ)
		if file:
			var json_text = file.get_as_text()
			file.close()
			
			var json_result = JSON.parse_string(json_text)
			if json_result and json_result is Dictionary:
				for occupation_name in json_result:
					occupation_loadouts[occupation_name] = json_result[occupation_name]
					if occupation_name not in occupations:
						occupations.append(occupation_name)

func _save_occupation_loadouts():
	var directory = DirAccess.open("res://")
	if not directory.dir_exists("res://Config"):
		directory.make_dir("Config")
	
	var file = FileAccess.open(OCCUPATION_LOADOUTS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(occupation_loadouts, "  "))
		file.close()

func _get_total_asset_count() -> int:
	var count = 0
	count += hair_styles.size()
	count += facial_hair_styles.size()
	count += clothing_options.size()
	count += underwear_options.size()
	count += undershirt_options.size()
	count += background_textures.size()
	count += inhand_sprites.size()
	count += occupation_loadouts.size()
	return count

func _scan_assets_from_registry():
	if not has_node("/root/AssetRegistry"):
		print("AssetRegistry not available, using fallback scanning")
		_scan_directories_fallback()
		return
	
	var asset_registry = get_node("/root/AssetRegistry")
	print("Scanning assets from AssetRegistry...")
	
	_scan_races_from_registry(asset_registry)
	_scan_hair_styles_from_registry(asset_registry)
	_scan_facial_hair_from_registry(asset_registry)
	_scan_clothing_from_registry(asset_registry)
	_scan_underwear_from_registry(asset_registry)
	_scan_undershirts_from_registry(asset_registry)
	_scan_backgrounds_from_registry(asset_registry)
	_scan_inhand_sprites_from_registry(asset_registry)
	_scan_occupations()

func _scan_races_from_registry(asset_registry):
	races = []
	var all_assets = asset_registry.get_all_assets()
	var race_dirs = {}
	
	for asset_path in all_assets:
		if asset_path.contains("/Human/") and (asset_path.contains("Body") or asset_path.contains("Head")):
			var path_parts = asset_path.split("/")
			var human_index = -1
			
			for i in range(path_parts.size()):
				if path_parts[i] == "Human":
					human_index = i
					break
			
			if human_index >= 0:
				if human_index + 1 < path_parts.size():
					var potential_race = path_parts[human_index + 1]
					if potential_race.ends_with(".png"):
						race_dirs["Human"] = true
					elif not potential_race in ["Hair", "FacialHair", "Clothing", "UnderWear", "UnderShirt"]:
						race_dirs[potential_race] = true
	
	for race_name in race_dirs.keys():
		races.append(race_name)
	
	if races.size() == 0:
		races.append("Human")
	
	print("Found races: ", races)

func _scan_hair_styles_from_registry(asset_registry):
	var hair_assets = asset_registry.get_assets_by_type("textures")
	
	if hair_styles.size() > 0 and hair_styles[0].name == "None":
		var none_option = hair_styles[0]
		hair_styles.clear()
		hair_styles.append(none_option)
	else:
		hair_styles.clear()
		hair_styles.append({"name": "None", "texture": null, "sex": -1})
	
	for asset_path in hair_assets:
		if asset_path.contains("/Hair/") and asset_path.ends_with(".png"):
			var file_name = asset_path.get_file()
			var style_name = file_name.get_basename()
			style_name = style_name.replace("_", " ").capitalize()
			
			var sex = -1
			if file_name.to_lower().contains("_male"):
				sex = 0
			elif file_name.to_lower().contains("_female"):
				sex = 1
			
			style_name = style_name.replace(" Male", "").replace(" Female", "")
			
			hair_styles.append({
				"name": style_name,
				"texture": asset_path,
				"sex": sex
			})
	
	print("Found hair styles: ", hair_styles.size() - 1)

func _scan_facial_hair_from_registry(asset_registry):
	var texture_assets = asset_registry.get_assets_by_type("textures")
	
	if facial_hair_styles.size() > 0 and facial_hair_styles[0].name == "None":
		var none_option = facial_hair_styles[0]
		facial_hair_styles.clear()
		facial_hair_styles.append(none_option)
	else:
		facial_hair_styles.clear()
		facial_hair_styles.append({"name": "None", "texture": null, "sex": 0})
	
	for asset_path in texture_assets:
		var file_name = asset_path.get_file()
		if (asset_path.contains("/FacialHair/") or asset_path.contains("/Hair/")) and asset_path.ends_with(".png"):
			if file_name.contains("Facial_") or file_name.begins_with("Beard") or file_name.begins_with("Mustache") or file_name.contains("facial"):
				var style_name = file_name.get_basename()
				style_name = style_name.replace("_", " ").replace("Facial ", "").capitalize()
				
				facial_hair_styles.append({
					"name": style_name,
					"texture": asset_path,
					"sex": 0
				})
	
	print("Found facial hair styles: ", facial_hair_styles.size() - 1)

func _scan_clothing_from_registry(asset_registry):
	var texture_assets = asset_registry.get_assets_by_type("textures")
	
	if clothing_options.size() > 0 and clothing_options[0].name == "None":
		var none_option = clothing_options[0]
		clothing_options.clear()
		clothing_options.append(none_option)
	else:
		clothing_options.clear()
		clothing_options.append({"name": "None", "textures": {}, "sex": -1})
	
	var clothing_sets = {}
	
	for asset_path in texture_assets:
		if asset_path.contains("/Clothing/") and asset_path.ends_with(".png"):
			var file_name = asset_path.get_file().get_basename()
			var parts = file_name.split("_")
			
			if parts.size() >= 2:
				var set_name = ""
				for i in range(parts.size() - 1):
					if i > 0:
						set_name += "_"
					set_name += parts[i]
				
				var part_name = parts[parts.size() - 1]
				
				if not clothing_sets.has(set_name):
					clothing_sets[set_name] = {"textures": {}}
				
				clothing_sets[set_name]["textures"][part_name] = asset_path
	
	for set_name in clothing_sets:
		var sex = -1
		
		if set_name.to_lower().contains("_male"):
			sex = 0
		elif set_name.to_lower().contains("_female"):
			sex = 1
		
		var display_name = set_name.replace("_Male", "").replace("_Female", "")
		display_name = display_name.replace("_", " ").capitalize()
		
		clothing_options.append({
			"name": display_name,
			"textures": clothing_sets[set_name]["textures"],
			"sex": sex
		})
	
	print("Found clothing sets: ", clothing_options.size() - 1)

func _scan_underwear_from_registry(asset_registry):
	var texture_assets = asset_registry.get_assets_by_type("textures")
	
	var has_male = false
	var has_female = false
	var defaults = []
	
	for item in underwear_options:
		if item.sex == 0:
			has_male = true
		elif item.sex == 1:
			has_female = true
		defaults.append(item)
	
	underwear_options.clear()
	
	for asset_path in texture_assets:
		if asset_path.contains("/UnderWear/") and asset_path.ends_with(".png"):
			var file_name = asset_path.get_file()
			var item_name = file_name.get_basename()
			item_name = item_name.replace("_", " ").capitalize()
			
			var sex = -1
			if file_name.to_lower().contains("_male") or file_name.to_lower().contains("boxers") or file_name.to_lower().contains("briefs"):
				sex = 0
				has_male = true
			elif file_name.to_lower().contains("_female") or file_name.to_lower().contains("panties"):
				sex = 1
				has_female = true
			
			item_name = item_name.replace(" Male", "").replace(" Female", "")
			
			underwear_options.append({
				"name": item_name,
				"texture": asset_path,
				"sex": sex
			})
	
	if not has_male or not has_female:
		for item in defaults:
			if (item.sex == 0 and not has_male) or (item.sex == 1 and not has_female):
				underwear_options.append(item)
				if item.sex == 0:
					has_male = true
				elif item.sex == 1:
					has_female = true
	
	print("Found underwear options: ", underwear_options.size())

func _scan_undershirts_from_registry(asset_registry):
	var texture_assets = asset_registry.get_assets_by_type("textures")
	
	var has_female_top = false
	var defaults = []
	
	for item in undershirt_options:
		if item.sex == 1 and item.texture != null:
			has_female_top = true
		defaults.append(item)
	
	undershirt_options.clear()
	undershirt_options.append({"name": "None", "texture": null, "sex": 0})
	
	for asset_path in texture_assets:
		if asset_path.contains("/UnderShirt/") and asset_path.ends_with(".png"):
			var file_name = asset_path.get_file()
			var item_name = file_name.get_basename()
			item_name = item_name.replace("_", " ").capitalize()
			
			var sex = -1
			if file_name.to_lower().contains("_male"):
				sex = 0
			elif file_name.to_lower().contains("_female") or file_name.to_lower().contains("bra"):
				sex = 1
				has_female_top = true
			
			item_name = item_name.replace(" Male", "").replace(" Female", "")
			
			undershirt_options.append({
				"name": item_name,
				"texture": asset_path,
				"sex": sex
			})
	
	if not has_female_top:
		for item in defaults:
			if item.sex == 1 and item.texture != null:
				undershirt_options.append(item)
				has_female_top = true
				break
	
	print("Found undershirt options: ", undershirt_options.size())

func _scan_backgrounds_from_registry(asset_registry):
	var texture_assets = asset_registry.get_assets_by_type("textures")
	
	background_textures.clear()
	
	for asset_path in texture_assets:
		if asset_path.contains("/Backgrounds/") and (asset_path.ends_with(".png") or asset_path.ends_with(".jpg")):
			var file_name = asset_path.get_file()
			var bg_name = file_name.get_basename()
			bg_name = bg_name.replace("_", " ").capitalize()
			
			var already_added = false
			for bg in background_textures:
				if bg.texture == asset_path:
					already_added = true
					break
			
			if not already_added:
				background_textures.append({
					"name": bg_name,
					"texture": asset_path
				})
	
	if background_textures.size() == 0:
		background_textures.append({
			"name": "Space", 
			"texture": "res://Assets/Backgrounds/Space.png"
		})
	
	print("Found backgrounds: ", background_textures.size())

func _scan_inhand_sprites_from_registry(asset_registry):
	var texture_assets = asset_registry.get_assets_by_type("textures")
	
	inhand_sprites.clear()
	
	var inhand_paths = ["/inhand/", "/items/inhand/", "/sprites/inhand/", "/Graphics/inhand/"]
	
	for asset_path in texture_assets:
		var is_inhand = false
		for inhand_path in inhand_paths:
			if asset_path.contains(inhand_path):
				is_inhand = true
				break
		
		if is_inhand and asset_path.ends_with(".png"):
			var file_name = asset_path.get_file().get_basename()
			
			if file_name.ends_with("_left") or file_name.ends_with("_right"):
				inhand_sprites[file_name] = asset_path
				print("Found in-hand sprite: ", file_name, " -> ", asset_path)
	
	print("Total in-hand sprites found: ", inhand_sprites.size())

func _scan_occupations():
	var occupation_list = []
	
	for occupation_name in occupation_loadouts.keys():
		if occupation_name not in occupation_list:
			occupation_list.append(occupation_name)
	
	for occupation_name in ["Engineer", "Security", "Medical", "Science", "Command", "Cargo", "Synthetic"]:
		if occupation_name not in occupation_list:
			occupation_list.append(occupation_name)
	
	occupations = occupation_list

func _scan_directories_fallback():
	print("Using fallback directory scanning...")
	_scan_races()
	_scan_hair_styles()
	_scan_facial_hair()
	_scan_clothing()
	_scan_underwear()
	_scan_undershirts()
	_scan_backgrounds()
	_scan_inhand_sprites_fallback()
	_scan_occupations()

func _scan_inhand_sprites_fallback():
	inhand_sprites.clear()
	
	var inhand_directories = [
		"res://Graphics/inhand/",
		"res://Graphics/items/inhand/",
		"res://Graphics/sprites/inhand/",
		"res://Assets/inhand/"
	]
	
	for dir_path in inhand_directories:
		var dir = DirAccess.open(dir_path)
		if dir:
			print("Scanning in-hand directory: ", dir_path)
			
			dir.list_dir_begin()
			var file_name = dir.get_next()
			
			while file_name != "":
				if not dir.current_is_dir() and file_name.ends_with(".png") and not file_name.begins_with("."):
					var base_name = file_name.get_basename()
					
					if base_name.ends_with("_left") or base_name.ends_with("_right"):
						var texture_path = dir_path + file_name
						if ResourceLoader.exists(texture_path):
							inhand_sprites[base_name] = texture_path
							print("Found in-hand sprite: ", base_name, " -> ", texture_path)
				
				file_name = dir.get_next()
			
			dir.list_dir_end()
	
	print("Total in-hand sprites found (fallback): ", inhand_sprites.size())

func _scan_races():
	races = []
	
	if _check_if_race_has_assets("res://Assets/Human/"):
		races.append("Human")
	
	var variant_dir = DirAccess.open("res://Assets/Human/")
	if variant_dir:
		variant_dir.list_dir_begin()
		var variant_name = variant_dir.get_next()
		
		while variant_name != "":
			if variant_dir.current_is_dir() and !variant_name.begins_with("."):
				if not variant_name in ["Hair", "FacialHair", "Clothing", "UnderWear", "UnderShirt"]:
					var variant_path = "res://Assets/Human/" + variant_name + "/"
					if _check_if_race_has_assets(variant_path):
						races.append(variant_name)
			
			variant_name = variant_dir.get_next()
	
	if races.size() == 0:
		races.append("Human")

func _check_if_race_has_assets(directory_path: String) -> bool:
	var dir = DirAccess.open(directory_path)
	if !dir:
		return false
		
	var has_assets = false
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if !dir.current_is_dir() and file_name.ends_with(".png"):
			if file_name.begins_with("Body") or file_name.begins_with("Head"):
				has_assets = true
				break
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	return has_assets

func _scan_hair_styles():
	var dir = DirAccess.open(HAIR_STYLES_PATH)
	if dir:
		if hair_styles.size() > 0 and hair_styles[0].name == "None":
			var none_option = hair_styles[0]
			hair_styles.clear()
			hair_styles.append(none_option)
		else:
			hair_styles.clear()
			hair_styles.append({"name": "None", "texture": null, "sex": -1})
		
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if !dir.current_is_dir() and file_name.ends_with(".png") and !file_name.begins_with("."):
				var style_name = file_name.get_basename()
				style_name = style_name.replace("_", " ").capitalize()
				
				var sex = -1
				if file_name.to_lower().contains("_male"):
					sex = 0
				elif file_name.to_lower().contains("_female"):
					sex = 1
					
				style_name = style_name.replace(" Male", "").replace(" Female", "")
				var texture_path = HAIR_STYLES_PATH + file_name
				
				if ResourceLoader.exists(texture_path):
					hair_styles.append({
						"name": style_name,
						"texture": texture_path,
						"sex": sex
					})
			
			file_name = dir.get_next()

func _scan_facial_hair():
	var dir = DirAccess.open(FACIAL_HAIR_PATH)
	if !dir:
		dir = DirAccess.open(HAIR_STYLES_PATH)
	
	if dir:
		if facial_hair_styles.size() > 0 and facial_hair_styles[0].name == "None":
			var none_option = facial_hair_styles[0]
			facial_hair_styles.clear()
			facial_hair_styles.append(none_option)
		else:
			facial_hair_styles.clear()
			facial_hair_styles.append({"name": "None", "texture": null, "sex": 0})
		
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if !dir.current_is_dir() and file_name.ends_with(".png") and !file_name.begins_with("."):
				if file_name.contains("Facial_") or file_name.begins_with("Beard") or file_name.begins_with("Mustache") or file_name.contains("facial"):
					var style_name = file_name.get_basename()
					style_name = style_name.replace("_", " ").replace("Facial ", "").capitalize()
					
					var file_path = dir.get_current_dir().path_join(file_name)
					
					if ResourceLoader.exists(file_path):
						facial_hair_styles.append({
							"name": style_name,
							"texture": file_path,
							"sex": 0
						})
			
			file_name = dir.get_next()

func _scan_clothing():
	var dir = DirAccess.open(CLOTHING_PATH)
	if dir:
		if clothing_options.size() > 0 and clothing_options[0].name == "None":
			var none_option = clothing_options[0]
			clothing_options.clear()
			clothing_options.append(none_option)
		else:
			clothing_options.clear()
			clothing_options.append({"name": "None", "textures": {}, "sex": -1})
		
		var clothing_sets = _scan_clothing_sets(dir)
		
		for set_name in clothing_sets:
			var sex = -1
			
			if set_name.to_lower().contains("_male"):
				sex = 0
			elif set_name.to_lower().contains("_female"):
				sex = 1
			
			var display_name = set_name.replace("_Male", "").replace("_Female", "")
			display_name = display_name.replace("_", " ").capitalize()
			
			clothing_options.append({
				"name": display_name,
				"textures": clothing_sets[set_name]["textures"],
				"sex": sex
			})

func _scan_clothing_sets(dir):
	var clothing_sets = {}
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if !dir.current_is_dir() and file_name.ends_with(".png") and !file_name.begins_with("."):
			var parts = file_name.get_basename().split("_")
			
			if parts.size() >= 2:
				var set_name = ""
				for i in range(parts.size() - 1):
					if i > 0:
						set_name += "_"
					set_name += parts[i]
				
				var part_name = parts[parts.size() - 1]
				
				if !clothing_sets.has(set_name):
					clothing_sets[set_name] = {"textures": {}}
				
				var texture_path = dir.get_current_dir().path_join(file_name)
				clothing_sets[set_name]["textures"][part_name] = texture_path
		
		file_name = dir.get_next()
	
	dir.list_dir_begin()
	file_name = dir.get_next()
	
	while file_name != "":
		if dir.current_is_dir() and !file_name.begins_with("."):
			var set_name = file_name
			var set_dir = DirAccess.open(dir.get_current_dir().path_join(file_name))
			
			if set_dir:
				if !clothing_sets.has(set_name):
					clothing_sets[set_name] = {"textures": {}}
				
				set_dir.list_dir_begin()
				var part_file = set_dir.get_next()
				
				while part_file != "":
					if !set_dir.current_is_dir() and part_file.ends_with(".png"):
						var part_name = part_file.get_basename()
						var texture_path = set_dir.get_current_dir().path_join(part_file)
						clothing_sets[set_name]["textures"][part_name] = texture_path
					
					part_file = set_dir.get_next()
		
		file_name = dir.get_next()
	
	return clothing_sets

func _scan_underwear():
	var dir = DirAccess.open(UNDERWEAR_PATH)
	if dir:
		var has_male = false
		var has_female = false
		var defaults = []
		
		for item in underwear_options:
			if item.sex == 0:
				has_male = true
			elif item.sex == 1:
				has_female = true
			defaults.append(item)
		
		underwear_options.clear()
		
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if !dir.current_is_dir() and file_name.ends_with(".png") and !file_name.begins_with("."):
				var item_name = file_name.get_basename()
				item_name = item_name.replace("_", " ").capitalize()
				
				var sex = -1
				if file_name.to_lower().contains("_male") or file_name.to_lower().contains("boxers") or file_name.to_lower().contains("briefs"):
					sex = 0
					has_male = true
				elif file_name.to_lower().contains("_female") or file_name.to_lower().contains("panties"):
					sex = 1
					has_female = true
					
				item_name = item_name.replace(" Male", "").replace(" Female", "")
				var texture_path = UNDERWEAR_PATH + file_name
				
				if ResourceLoader.exists(texture_path):
					underwear_options.append({
						"name": item_name,
						"texture": texture_path,
						"sex": sex
					})
			
			file_name = dir.get_next()
		
		if !has_male or !has_female:
			for item in defaults:
				if (item.sex == 0 and !has_male) or (item.sex == 1 and !has_female):
					underwear_options.append(item)
					if item.sex == 0:
						has_male = true
					elif item.sex == 1:
						has_female = true
		
		if !has_male:
			underwear_options.append({
				"name": "White Briefs",
				"texture": "res://Assets/Human/UnderWear/Trunks.png",
				"sex": 0
			})
		
		if !has_female:
			underwear_options.append({
				"name": "White Panties",
				"texture": "res://Assets/Human/UnderWear/Panties.png",
				"sex": 1
			})

func _scan_undershirts():
	var dir = DirAccess.open(UNDERSHIRT_PATH)
	if dir:
		var has_female_top = false
		var defaults = []
		
		for item in undershirt_options:
			if item.sex == 1 and item.texture != null:
				has_female_top = true
			defaults.append(item)
		
		undershirt_options.clear()
		undershirt_options.append({"name": "None", "texture": null, "sex": 0})
		
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if !dir.current_is_dir() and file_name.ends_with(".png") and !file_name.begins_with("."):
				var item_name = file_name.get_basename()
				item_name = item_name.replace("_", " ").capitalize()
				
				var sex = -1
				if file_name.to_lower().contains("_male"):
					sex = 0
				elif file_name.to_lower().contains("_female") or file_name.to_lower().contains("bra"):
					sex = 1
					has_female_top = true
					
				item_name = item_name.replace(" Male", "").replace(" Female", "")
				var texture_path = UNDERSHIRT_PATH + file_name
				
				if ResourceLoader.exists(texture_path):
					undershirt_options.append({
						"name": item_name,
						"texture": texture_path,
						"sex": sex
					})
			
			file_name = dir.get_next()
		
		if !has_female_top:
			for item in defaults:
				if item.sex == 1 and item.texture != null:
					undershirt_options.append(item)
					has_female_top = true
					break
		
		if !has_female_top:
			undershirt_options.append({
				"name": "White Bra",
				"texture": "res://Assets/Human/UnderShirt/white_bra.png",
				"sex": 1
			})

func _scan_backgrounds():
	var dir = DirAccess.open(BACKGROUNDS_PATH)
	if dir:
		background_textures.clear()
		
		if ResourceLoader.exists("res://Assets/Backgrounds/Space.png"):
			background_textures.append({
				"name": "Space", 
				"texture": "res://Assets/Backgrounds/Space.png"
			})
		
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if !dir.current_is_dir() and (file_name.ends_with(".png") or file_name.ends_with(".jpg")) and !file_name.begins_with("."):
				var bg_name = file_name.get_basename()
				bg_name = bg_name.replace("_", " ").capitalize()
				
				var texture_path = BACKGROUNDS_PATH + file_name
				
				if ResourceLoader.exists(texture_path):
					var already_added = false
					for bg in background_textures:
						if bg.texture == texture_path:
							already_added = true
							break
							
					if not already_added:
						background_textures.append({
							"name": bg_name,
							"texture": texture_path
						})
			
			file_name = dir.get_next()

func _load_config_file():
	if ResourceLoader.exists(ASSET_CONFIG_PATH):
		var file = FileAccess.open(ASSET_CONFIG_PATH, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			var json_result = JSON.parse_string(json_string)
			
			if json_result:
				if json_result.has("races"):
					races = json_result.races
				if json_result.has("occupations"):
					occupations = json_result.occupations
				if json_result.has("hair_styles"):
					hair_styles = json_result.hair_styles
				if json_result.has("facial_hair_styles"):
					facial_hair_styles = json_result.facial_hair_styles
				if json_result.has("clothing_options"):
					clothing_options = json_result.clothing_options
				if json_result.has("underwear_options"):
					underwear_options = json_result.underwear_options
				if json_result.has("undershirt_options"):
					undershirt_options = json_result.undershirt_options
				if json_result.has("background_textures"):
					background_textures = json_result.background_textures
				if json_result.has("inhand_sprites"):
					inhand_sprites = json_result.inhand_sprites

func _verify_assets():
	var valid_hair_styles = []
	for hair in hair_styles:
		if hair.texture == null or ResourceLoader.exists(hair.texture):
			valid_hair_styles.append(hair)
	hair_styles = valid_hair_styles
	
	var valid_facial_hair = []
	for style in facial_hair_styles:
		if style.texture == null or ResourceLoader.exists(style.texture):
			valid_facial_hair.append(style)
	facial_hair_styles = valid_facial_hair
	
	var valid_clothing = []
	for clothing in clothing_options:
		var all_valid = true
		
		for part in clothing.textures:
			var path = clothing.textures[part]
			if not ResourceLoader.exists(path):
				all_valid = false
		
		if all_valid or clothing.name == "None":
			valid_clothing.append(clothing)
	clothing_options = valid_clothing
	
	var valid_underwear = []
	for underwear in underwear_options:
		if underwear.texture == null or ResourceLoader.exists(underwear.texture):
			valid_underwear.append(underwear)
	underwear_options = valid_underwear
	
	var valid_undershirts = []
	for shirt in undershirt_options:
		if shirt.texture == null or ResourceLoader.exists(shirt.texture):
			valid_undershirts.append(shirt)
	undershirt_options = valid_undershirts
	
	var valid_backgrounds = []
	for bg in background_textures:
		if bg.texture == null or ResourceLoader.exists(bg.texture):
			valid_backgrounds.append(bg)
	background_textures = valid_backgrounds
	
	var valid_inhand_sprites = {}
	for sprite_key in inhand_sprites:
		var sprite_path = inhand_sprites[sprite_key]
		if ResourceLoader.exists(sprite_path):
			valid_inhand_sprites[sprite_key] = sprite_path
	inhand_sprites = valid_inhand_sprites
	
	_ensure_minimal_options()

func _ensure_minimal_options():
	if races.size() == 0:
		races.append("Human")
	
	if hair_styles.size() == 0 or hair_styles[0].name != "None":
		hair_styles.insert(0, {"name": "None", "texture": null, "sex": -1})
	
	if facial_hair_styles.size() == 0 or facial_hair_styles[0].name != "None":
		facial_hair_styles.insert(0, {"name": "None", "texture": null, "sex": 0})
	
	if clothing_options.size() == 0 or clothing_options[0].name != "None":
		clothing_options.insert(0, {"name": "None", "textures": {}, "sex": -1})
	
	var has_male = false
	var has_female = false
	
	for item in underwear_options:
		if item.sex == 0:
			has_male = true
		elif item.sex == 1:
			has_female = true
	
	if !has_male:
		underwear_options.append({
			"name": "White Briefs", 
			"texture": "res://Assets/Human/UnderWear/Trunks.png", 
			"sex": 0
		})
	
	if !has_female:
		underwear_options.append({
			"name": "White Panties", 
			"texture": "res://Assets/Human/UnderWear/Panties.png", 
			"sex": 1
		})
	
	var has_none_top = false
	var has_female_top = false
	
	for item in undershirt_options:
		if item.name == "None" and item.sex == 0:
			has_none_top = true
		if item.sex == 1 and item.texture != null:
			has_female_top = true
	
	if !has_none_top:
		undershirt_options.insert(0, {"name": "None", "texture": null, "sex": 0})
	
	if !has_female_top:
		undershirt_options.append({
			"name": "White Bra", 
			"texture": "res://Assets/Human/UnderShirt/white_bra.png", 
			"sex": 1
		})
	
	if background_textures.size() == 0:
		background_textures.append({
			"name": "Space", 
			"texture": "res://Assets/Backgrounds/Space.png"
		})

func get_race_sprites(race_index: int, sex: int = 0) -> Dictionary:
	if race_index < 0 or race_index >= races.size():
		race_index = 0
	
	var race_name = races[race_index]
	var sprite_paths = {}
	var sex_suffix = "_Female" if sex == 1 else ""
	
	var race_path = "res://Assets/Human/"
	if race_name != "Human":
		race_path = "res://Assets/Human/" + race_name + "/"
	
	var body_parts = {
		"body": "Body", "head": "Head", "left_arm": "Left_arm", "right_arm": "Right_arm", 
		"left_leg": "Left_leg", "right_leg": "Right_leg", "left_hand": "Left_hand",
		"right_hand": "Right_hand", "left_foot": "Left_foot", "right_foot": "Right_foot"
	}
	
	for sprite_key in body_parts:
		var part_name = body_parts[sprite_key]
		
		var paths_to_try = [
			race_path + part_name + sex_suffix + ".png",
			race_path + part_name + ".png",
			"res://Assets/Human/" + part_name + sex_suffix + ".png",
			"res://Assets/Human/" + part_name + ".png"
		]
		
		for path in paths_to_try:
			if ResourceLoader.exists(path):
				sprite_paths[sprite_key] = {"texture": path}
				break
	
	return sprite_paths

func get_hair_styles_for_sex(sex: int = 0) -> Array:
	var result = [{"name": "None", "texture": null, "sex": -1}]
	
	for style in hair_styles:
		if style.name == "None":
			continue
			
		if style.sex == sex or style.sex == -1:
			result.append(style)
	
	if result.size() <= 1:
		return hair_styles
		
	return result

func get_facial_hair_for_sex(sex: int = 0) -> Array:
	var result = [{"name": "None", "texture": null, "sex": 0}]
	
	if sex == 0:
		for style in facial_hair_styles:
			if style.name == "None":
				continue
			result.append(style)
	
	return result

func get_clothing_for_sex(sex: int = 0) -> Array:
	var result = [{"name": "None", "textures": {}, "sex": -1}]
	
	for clothing in clothing_options:
		if clothing.name == "None":
			continue
			
		if clothing.sex == sex or clothing.sex == -1:
			result.append(clothing)
	
	if result.size() <= 1:
		return clothing_options
		
	return result

func get_underwear_for_sex(sex: int = 0) -> Array:
	var result = []
	
	for item in underwear_options:
		if item.sex == sex or item.sex == -1:
			result.append(item)
	
	if result.size() == 0:
		if sex == 0:
			result.append({
				"name": "White Briefs", 
				"texture": "res://Assets/Human/UnderWear/Trunks.png", 
				"sex": 0
			})
		else:
			result.append({
				"name": "White Panties", 
				"texture": "res://Assets/Human/UnderWear/Panties.png", 
				"sex": 1
			})
	
	return result

func get_undershirts_for_sex(sex: int = 0) -> Array:
	var result = []
	
	if sex == 0:
		result.append({"name": "None", "texture": null, "sex": 0})
	
	for item in undershirt_options:
		if item.name == "None" and sex == 1:
			continue
			
		if item.sex == sex or item.sex == -1:
			result.append(item)
	
	if sex == 1 and result.size() == 0:
		result.append({
			"name": "White Bra", 
			"texture": "res://Assets/Human/UnderShirt/white_bra.png", 
			"sex": 1
		})
	
	return result

func save_config():
	var config = {
		"races": races, "occupations": occupations, "hair_styles": hair_styles,
		"facial_hair_styles": facial_hair_styles, "clothing_options": clothing_options,
		"underwear_options": underwear_options, "undershirt_options": undershirt_options,
		"background_textures": background_textures, "inhand_sprites": inhand_sprites
	}
	
	var directory = DirAccess.open("res://")
	if not directory.dir_exists("res://Config"):
		directory.make_dir("Config")
	
	var file = FileAccess.open(ASSET_CONFIG_PATH, FileAccess.WRITE)
	if file:
		file.store_line(JSON.stringify(config, "  "))

func add_hair_style(name: String, texture_path: String, sex: int = -1) -> void:
	hair_styles.append({"name": name, "texture": texture_path, "sex": sex})
	save_config()

func add_facial_hair_style(name: String, texture_path: String) -> void:
	facial_hair_styles.append({"name": name, "texture": texture_path, "sex": 0})
	save_config()

func add_clothing_option(name: String, textures: Dictionary, sex: int = -1) -> void:
	clothing_options.append({"name": name, "textures": textures, "sex": sex})
	save_config()

func add_underwear_option(name: String, texture_path: String, sex: int = -1) -> void:
	underwear_options.append({"name": name, "texture": texture_path, "sex": sex})
	save_config()

func add_undershirt_option(name: String, texture_path: String, sex: int = -1) -> void:
	undershirt_options.append({"name": name, "texture": texture_path, "sex": sex})
	save_config()

func add_race(name: String) -> void:
	races.append(name)
	save_config()

func add_occupation(name: String) -> void:
	occupations.append(name)
	save_config()

func add_background(name: String, texture_path: String) -> void:
	background_textures.append({"name": name, "texture": texture_path})
	save_config()

func add_inhand_sprite(item_name: String, hand: String, texture_path: String) -> void:
	var sprite_key = item_name + "_" + hand
	inhand_sprites[sprite_key] = texture_path
	save_config()

func remove_inhand_sprite(item_name: String, hand: String) -> void:
	var sprite_key = item_name + "_" + hand
	if inhand_sprites.has(sprite_key):
		inhand_sprites.erase(sprite_key)
		save_config()

func get_inhand_sprite_path(item_name: String, hand: String) -> String:
	var sprite_key = item_name + "_" + hand
	if inhand_sprites.has(sprite_key):
		return inhand_sprites[sprite_key]
	return ""

func refresh_assets() -> void:
	_scan_assets_from_registry()
	_verify_assets()
	save_config()

func is_asset_registry_available() -> bool:
	return has_node("/root/AssetRegistry")

func get_asset_registry():
	if has_node("/root/AssetRegistry"):
		return get_node("/root/AssetRegistry")
	return null
