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
var co_weapons_database = {}
var synthetic_wardrobe_database = {}
var status_equipment_database = {}
var generation_features = {}

const BASE_HUMAN_PATH = "res://Assets/Human/"
const HAIR_STYLES_PATH = "res://Assets/Human/Hair/"
const FACIAL_HAIR_PATH = "res://Assets/Human/FacialHair/"
const CLOTHING_PATH = "res://Assets/Human/Clothing/"
const UNDERWEAR_PATH = "res://Assets/Human/UnderWear/"
const UNDERSHIRT_PATH = "res://Assets/Human/UnderShirt/"
const BACKGROUNDS_PATH = "res://Assets/Backgrounds/"
const INHAND_PATH = "res://Assets/Icons/Items/In_hand/"
const ASSET_CONFIG_PATH = "res://Config/character_assets.json"
const OCCUPATION_LOADOUTS_PATH = "res://Config/occupation_loadouts.json"
const ITEMS_DATABASE_PATH = "res://Config/items_database.json"
const CO_WEAPONS_PATH = "res://Config/co_weapons_database.json"
const SYNTHETIC_WARDROBE_PATH = "res://Config/synthetic_wardrobe.json"
const STATUS_EQUIPMENT_PATH = "res://Config/status_equipment.json"
const GENERATION_FEATURES_PATH = "res://Config/generation_features.json"

var _resource_cache = {}
var _asset_registry = null
var _scene_path_cache = {}
var _initialization_complete = false

func _init():
	call_deferred("_initialize_after_registry")

func _initialize_after_registry():
	_asset_registry = get_node_or_null("/root/AssetRegistry")
	
	_load_defaults()
	_load_item_database()
	_load_occupation_loadouts()
	_load_co_weapons_database()
	_load_synthetic_wardrobe_database()
	_load_status_equipment_database()
	_load_generation_features()
	
	if _asset_registry:
		_build_fast_lookups_from_registry()
	else:
		print("Warning: AssetRegistry not found, using fallback mode")
		_scan_directories()
	
	_load_config_file()
	_verify_assets()
	_initialization_complete = true
	
	print("Asset Manager initialized with ", _get_total_asset_count(), " assets")
	print("In-hand sprites loaded: ", inhand_sprites.size())
	print("Occupation loadouts loaded: ", occupation_loadouts.size())
	print("Items in database: ", item_database.size())
	print("CO weapons loaded: ", co_weapons_database.size())
	print("Synthetic wardrobe items: ", synthetic_wardrobe_database.size())

func _build_fast_lookups_from_registry():
	if not _asset_registry:
		return
	
	var start_time = Time.get_ticks_msec()
	
	if _asset_registry.has_method("get_assets_by_type"):
		var all_scenes = _asset_registry.get_assets_by_type("scenes")
		for scene_path in all_scenes:
			var file_name = scene_path.get_file().get_basename()
			_scene_path_cache[file_name] = scene_path
	
	_build_hair_styles_from_registry()
	_build_facial_hair_from_registry()
	_build_clothing_from_registry()
	_build_underwear_from_registry()
	_build_undershirts_from_registry()
	_build_backgrounds_from_registry()
	_build_inhand_sprites_from_registry()
	_build_races_from_registry()
	_scan_occupations()
	
	var elapsed = Time.get_ticks_msec() - start_time
	print("Fast registry lookup build completed in ", elapsed, "ms")

func _build_hair_styles_from_registry():
	if hair_styles.size() > 0 and hair_styles[0].name == "None":
		var none_option = hair_styles[0]
		hair_styles.clear()
		hair_styles.append(none_option)
	else:
		hair_styles.clear()
		hair_styles.append({"name": "None", "texture": null, "sex": -1})
	
	var texture_assets = _asset_registry.get_assets_by_type("textures")
	
	for asset_path in texture_assets:
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

func _build_facial_hair_from_registry():
	if facial_hair_styles.size() > 0 and facial_hair_styles[0].name == "None":
		var none_option = facial_hair_styles[0]
		facial_hair_styles.clear()
		facial_hair_styles.append(none_option)
	else:
		facial_hair_styles.clear()
		facial_hair_styles.append({"name": "None", "texture": null, "sex": 0})
	
	var texture_assets = _asset_registry.get_assets_by_type("textures")
	
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

func _build_clothing_from_registry():
	if clothing_options.size() > 0 and clothing_options[0].name == "None":
		var none_option = clothing_options[0]
		clothing_options.clear()
		clothing_options.append(none_option)
	else:
		clothing_options.clear()
		clothing_options.append({"name": "None", "textures": {}, "sex": -1})
	
	var texture_assets = _asset_registry.get_assets_by_type("textures")
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

func _build_underwear_from_registry():
	var texture_assets = _asset_registry.get_assets_by_type("textures")
	
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

func _build_undershirts_from_registry():
	var texture_assets = _asset_registry.get_assets_by_type("textures")
	
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

func _build_backgrounds_from_registry():
	var texture_assets = _asset_registry.get_assets_by_type("textures")
	
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

func _build_inhand_sprites_from_registry():
	if not _asset_registry:
		print("Warning: AssetRegistry not available for in-hand sprites")
		return
	
	inhand_sprites.clear()
	
	# Get all texture assets from the registry
	var texture_assets = _asset_registry.get_assets_by_type("textures")
	
	print("Scanning ", texture_assets.size(), " texture assets for in-hand sprites...")
	
	for asset_path in texture_assets:
		# Check if this is an in-hand texture by path
		if _is_inhand_texture_path(asset_path):
			var file_name = asset_path.get_file().get_basename()
			
			# Validate the naming convention (must end with _left or _right)
			if file_name.ends_with("_left") or file_name.ends_with("_right"):
				inhand_sprites[file_name] = asset_path
				print("Found in-hand sprite: ", file_name, " -> ", asset_path)
	
	print("Total in-hand sprites loaded: ", inhand_sprites.size())

func _is_inhand_texture_path(path: String) -> bool:
	return (path.contains("/In_hand/") or 
			path.contains("/In-hand/") or 
			path.contains("/InHand/") or
			path.contains("/Inhand/")) and path.ends_with(".png")

func _build_races_from_registry():
	races = []
	var texture_assets = _asset_registry.get_assets_by_type("textures")
	var race_dirs = {}
	
	for asset_path in texture_assets:
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

func _load_co_weapons_database():
	if FileAccess.file_exists(CO_WEAPONS_PATH):
		var file = FileAccess.open(CO_WEAPONS_PATH, FileAccess.READ)
		if file:
			var json_text = file.get_as_text()
			file.close()
			
			var json_result = JSON.parse_string(json_text)
			if json_result and json_result is Dictionary:
				co_weapons_database = json_result
	else:
		_create_default_co_weapons_database()

func _create_default_co_weapons_database():
	co_weapons_database = {
		"Combat_Knife": {
			"display_name": "Combat Knife",
			"scene_path": "res://Objects/Weapons/Combat_Knife.tscn",
			"damage": 25,
			"weapon_type": "melee",
			"rarity": "common",
			"clearance_level": 1
		},
		"Pulse_Rifle": {
			"display_name": "M41A Pulse Rifle",
			"scene_path": "res://Objects/Weapons/Pulse_Rifle.tscn",
			"damage": 45,
			"weapon_type": "rifle",
			"rarity": "standard",
			"clearance_level": 3
		},
		"Shotgun": {
			"display_name": "M37A2 Shotgun",
			"scene_path": "res://Objects/Weapons/Shotgun.tscn",
			"damage": 65,
			"weapon_type": "shotgun",
			"rarity": "uncommon",
			"clearance_level": 3
		},
		"Sidearm": {
			"display_name": "M4A3 Service Pistol",
			"scene_path": "res://Objects/Weapons/Sidearm.tscn",
			"damage": 30,
			"weapon_type": "pistol",
			"rarity": "standard",
			"clearance_level": 2
		},
		"Plasma_Caster": {
			"display_name": "Plasma Caster",
			"scene_path": "res://Objects/Weapons/Plasma_Caster.tscn",
			"damage": 80,
			"weapon_type": "energy",
			"rarity": "rare",
			"clearance_level": 4
		},
		"Sniper_Rifle": {
			"display_name": "M42A Sniper Rifle",
			"scene_path": "res://Objects/Weapons/Sniper_Rifle.tscn",
			"damage": 90,
			"weapon_type": "sniper",
			"rarity": "rare",
			"clearance_level": 4
		},
		"Grenade_Launcher": {
			"display_name": "M92 Grenade Launcher",
			"scene_path": "res://Objects/Weapons/Grenade_Launcher.tscn",
			"damage": 100,
			"weapon_type": "explosive",
			"rarity": "epic",
			"clearance_level": 5
		},
		"Energy_Sword": {
			"display_name": "Type-1 Energy Sword",
			"scene_path": "res://Objects/Weapons/Energy_Sword.tscn",
			"damage": 75,
			"weapon_type": "energy_melee",
			"rarity": "legendary",
			"clearance_level": 5
		},
		"Rail_Gun": {
			"display_name": "Experimental Rail Gun",
			"scene_path": "res://Objects/Weapons/Rail_Gun.tscn",
			"damage": 120,
			"weapon_type": "experimental",
			"rarity": "legendary",
			"clearance_level": 6
		}
	}
	_save_co_weapons_database()

func _save_co_weapons_database():
	var directory = DirAccess.open("res://")
	if not directory.dir_exists("res://Config"):
		directory.make_dir("Config")
	
	var file = FileAccess.open(CO_WEAPONS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(co_weapons_database, "  "))
		file.close()

func _load_synthetic_wardrobe_database():
	if FileAccess.file_exists(SYNTHETIC_WARDROBE_PATH):
		var file = FileAccess.open(SYNTHETIC_WARDROBE_PATH, FileAccess.READ)
		if file:
			var json_text = file.get_as_text()
			file.close()
			
			var json_result = JSON.parse_string(json_text)
			if json_result and json_result is Dictionary:
				synthetic_wardrobe_database = json_result
	else:
		_create_default_synthetic_wardrobe_database()

func _create_default_synthetic_wardrobe_database():
	synthetic_wardrobe_database = {
		"HEAD": {
			"Engineering_Beret": {
				"display_name": "Engineering Beret",
				"scene_path": "res://Scenes/Items/Clothing/Engineering_Beret.tscn",
				"generation_compatibility": ["gen1", "gen2", "gen3"]
			},
			"Medical_Cap": {
				"display_name": "Medical Cap",
				"scene_path": "res://Scenes/Items/Clothing/Medical_Cap.tscn",
				"generation_compatibility": ["gen2", "gen3"]
			},
			"Security_Helmet": {
				"display_name": "Security Helmet",
				"scene_path": "res://Scenes/Items/Clothing/Security_Helmet.tscn",
				"generation_compatibility": ["gen1", "gen2", "gen3"]
			},
			"Command_Cap": {
				"display_name": "Command Cap",
				"scene_path": "res://Scenes/Items/Clothing/Command_Cap.tscn",
				"generation_compatibility": ["gen3"]
			},
			"Mechanical_Beret": {
				"display_name": "Mechanical Beret",
				"scene_path": "res://Scenes/Items/Clothing/Mechanical_Beret.tscn",
				"generation_compatibility": ["gen1", "gen2", "gen3"]
			}
		},
		"GLASSES": {
			"Health_Hud": {
				"display_name": "Health HUD",
				"scene_path": "res://Scenes/Items/Clothing/Health_Hud.tscn",
				"generation_compatibility": ["gen1", "gen2", "gen3"]
			},
			"Green_Goggles": {
				"display_name": "Green Goggles",
				"scene_path": "res://Scenes/Items/Clothing/Green_Goggles.tscn",
				"generation_compatibility": ["gen1", "gen2"]
			},
			"Security_Goggles": {
				"display_name": "Security Goggles",
				"scene_path": "res://Scenes/Items/Clothing/Security_Goggles.tscn",
				"generation_compatibility": ["gen2", "gen3"]
			},
			"Welding_Goggles": {
				"display_name": "Welding Goggles",
				"scene_path": "res://Scenes/Items/Clothing/Welding_Goggles.tscn",
				"generation_compatibility": ["gen1", "gen2", "gen3"]
			}
		},
		"BACK": {
			"Smart_Pack": {
				"display_name": "Smart Pack",
				"scene_path": "res://Scenes/Items/Clothing/Smart_Pack.tscn",
				"generation_compatibility": ["gen1", "gen2", "gen3"]
			},
			"Synthetic_Backpack": {
				"display_name": "Synthetic Backpack",
				"scene_path": "res://Scenes/Items/Clothing/Synthetic_Backpack.tscn",
				"generation_compatibility": ["gen1", "gen2", "gen3"]
			},
			"Engineering_Backpack": {
				"display_name": "Engineering Backpack",
				"scene_path": "res://Scenes/Items/Clothing/Engineering_Backpack.tscn",
				"generation_compatibility": ["gen2", "gen3"]
			},
			"Medical_Backpack": {
				"display_name": "Medical Backpack",
				"scene_path": "res://Scenes/Items/Clothing/Medical_Backpack.tscn",
				"generation_compatibility": ["gen2", "gen3"]
			}
		},
		"W_UNIFORM": {
			"SyntheticCouncilor": {
				"display_name": "Synthetic Councilor Uniform",
				"scene_path": "res://Scenes/Items/Clothing/SyntheticCouncilor.tscn",
				"generation_compatibility": ["gen1", "gen2", "gen3"]
			},
			"Engineer_Jumpsuit": {
				"display_name": "Engineer Jumpsuit",
				"scene_path": "res://Scenes/Items/Clothing/Engineer_Jumpsuit.tscn",
				"generation_compatibility": ["gen1", "gen2", "gen3"]
			},
			"Security_Jumpsuit": {
				"display_name": "Security Jumpsuit",
				"scene_path": "res://Scenes/Items/Clothing/Security_Jumpsuit.tscn",
				"generation_compatibility": ["gen2", "gen3"]
			},
			"Medical_Scrubs": {
				"display_name": "Medical Scrubs",
				"scene_path": "res://Scenes/Items/Clothing/Medical_Scrubs.tscn",
				"generation_compatibility": ["gen2", "gen3"]
			}
		},
		"WEAR_SUIT": {
			"Jacket_Black": {
				"display_name": "Black Jacket",
				"scene_path": "res://Scenes/Items/Clothing/Jacket_Black.tscn",
				"generation_compatibility": ["gen1", "gen2", "gen3"]
			},
			"Lab_Coat": {
				"display_name": "Lab Coat",
				"scene_path": "res://Scenes/Items/Clothing/Lab_Coat.tscn",
				"generation_compatibility": ["gen2", "gen3"]
			},
			"Security_Armor": {
				"display_name": "Security Armor",
				"scene_path": "res://Scenes/Items/Clothing/Security_Armor.tscn",
				"generation_compatibility": ["gen2", "gen3"]
			},
			"Command_Coat": {
				"display_name": "Command Coat",
				"scene_path": "res://Scenes/Items/Clothing/Command_Coat.tscn",
				"generation_compatibility": ["gen3"]
			}
		},
		"GLOVES": {
			"InsulatedGloves": {
				"display_name": "Insulated Gloves",
				"scene_path": "res://Scenes/Items/Clothing/InsulatedGloves.tscn",
				"generation_compatibility": ["gen1", "gen2", "gen3"]
			},
			"Medical_Gloves": {
				"display_name": "Medical Gloves",
				"scene_path": "res://Scenes/Items/Clothing/Medical_Gloves.tscn",
				"generation_compatibility": ["gen2", "gen3"]
			},
			"Security_Gloves": {
				"display_name": "Security Gloves",
				"scene_path": "res://Scenes/Items/Clothing/Security_Gloves.tscn",
				"generation_compatibility": ["gen2", "gen3"]
			},
			"Work_Gloves": {
				"display_name": "Work Gloves",
				"scene_path": "res://Scenes/Items/Clothing/Work_Gloves.tscn",
				"generation_compatibility": ["gen1", "gen2", "gen3"]
			}
		},
		"SHOES": {
			"MarineBoots": {
				"display_name": "Marine Boots",
				"scene_path": "res://Scenes/Items/Clothing/MarineBoots.tscn",
				"generation_compatibility": ["gen1", "gen2", "gen3"]
			},
			"Medical_Shoes": {
				"display_name": "Medical Shoes",
				"scene_path": "res://Scenes/Items/Clothing/Medical_Shoes.tscn",
				"generation_compatibility": ["gen2", "gen3"]
			},
			"Security_Boots": {
				"display_name": "Security Boots",
				"scene_path": "res://Scenes/Items/Clothing/Security_Boots.tscn",
				"generation_compatibility": ["gen2", "gen3"]
			},
			"Work_Boots": {
				"display_name": "Work Boots",
				"scene_path": "res://Scenes/Items/Clothing/Work_Boots.tscn",
				"generation_compatibility": ["gen1", "gen2", "gen3"]
			}
		},
		"BELT": {
			"LifeSaver": {
				"display_name": "Life Saver Belt",
				"scene_path": "res://Scenes/Items/Clothing/LifeSaver.tscn",
				"generation_compatibility": ["gen1", "gen2", "gen3"]
			},
			"Tool_Belt": {
				"display_name": "Tool Belt",
				"scene_path": "res://Scenes/Items/Clothing/Tool_Belt.tscn",
				"generation_compatibility": ["gen1", "gen2", "gen3"]
			},
			"Security_Belt": {
				"display_name": "Security Belt",
				"scene_path": "res://Scenes/Items/Clothing/Security_Belt.tscn",
				"generation_compatibility": ["gen2", "gen3"]
			},
			"Medical_Belt": {
				"display_name": "Medical Belt",
				"scene_path": "res://Scenes/Items/Clothing/Medical_Belt.tscn",
				"generation_compatibility": ["gen2", "gen3"]
			}
		}
	}
	_save_synthetic_wardrobe_database()

func _save_synthetic_wardrobe_database():
	var directory = DirAccess.open("res://")
	if not directory.dir_exists("res://Config"):
		directory.make_dir("Config")
	
	var file = FileAccess.open(SYNTHETIC_WARDROBE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(synthetic_wardrobe_database, "  "))
		file.close()

func _load_status_equipment_database():
	if FileAccess.file_exists(STATUS_EQUIPMENT_PATH):
		var file = FileAccess.open(STATUS_EQUIPMENT_PATH, FileAccess.READ)
		if file:
			var json_text = file.get_as_text()
			file.close()
			
			var json_result = JSON.parse_string(json_text)
			if json_result and json_result is Dictionary:
				status_equipment_database = json_result
	else:
		_create_default_status_equipment_database()

func _create_default_status_equipment_database():
	status_equipment_database = {
		"councilor": {
			"additional_items": [
				{
					"item_name": "Councilor_Badge",
					"scene_path": "res://Objects/Items/Councilor_Badge.tscn",
					"slot": "WEAR_ID"
				},
				{
					"item_name": "Access_Card_Gold",
					"scene_path": "res://Objects/Items/Access_Card_Gold.tscn",
					"slot": "L_STORE"
				}
			],
			"equipment_modifiers": {
				"clearance_level": 4,
				"access_permissions": ["command", "bridge", "councilor_quarters"]
			}
		},
		"senate": {
			"additional_items": [
				{
					"item_name": "Senate_Badge",
					"scene_path": "res://Objects/Items/Senate_Badge.tscn",
					"slot": "WEAR_ID"
				},
				{
					"item_name": "Master_Access_Card",
					"scene_path": "res://Objects/Items/Master_Access_Card.tscn",
					"slot": "L_STORE"
				},
				{
					"item_name": "Senate_Communicator",
					"scene_path": "res://Objects/Items/Senate_Communicator.tscn",
					"slot": "R_STORE"
				}
			],
			"equipment_modifiers": {
				"clearance_level": 6,
				"access_permissions": ["all_areas", "senate_chamber", "classified_archives"]
			}
		}
	}
	_save_status_equipment_database()

func _save_status_equipment_database():
	var directory = DirAccess.open("res://")
	if not directory.dir_exists("res://Config"):
		directory.make_dir("Config")
	
	var file = FileAccess.open(STATUS_EQUIPMENT_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(status_equipment_database, "  "))
		file.close()

func _load_generation_features():
	if FileAccess.file_exists(GENERATION_FEATURES_PATH):
		var file = FileAccess.open(GENERATION_FEATURES_PATH, FileAccess.READ)
		if file:
			var json_text = file.get_as_text()
			file.close()
			
			var json_result = JSON.parse_string(json_text)
			if json_result and json_result is Dictionary:
				generation_features = json_result
	else:
		_create_default_generation_features()

func _create_default_generation_features():
	generation_features = {
		"gen1": {
			"display_name": "Generation 1",
			"description": "First generation synthetic units with basic AI capabilities",
			"features": [
				"Basic Medical Knowledge",
				"Engineering Proficiency",
				"Standard Motor Functions"
			],
			"restrictions": [
				"Limited Combat Programming",
				"Basic Social Protocols"
			],
			"special_equipment": [],
			"ai_capabilities": {
				"learning_rate": 0.6,
				"emotional_simulation": 0.3,
				"combat_proficiency": 0.4
			}
		},
		"gen2": {
			"display_name": "Generation 2",
			"description": "Second generation synthetic units with enhanced AI and emotional simulation",
			"features": [
				"Advanced Medical Knowledge",
				"Enhanced Engineering Skills",
				"Improved Social Protocols",
				"Basic Emotional Responses"
			],
			"restrictions": [
				"Moderate Combat Limitations"
			],
			"special_equipment": [
				"Neural_Interface_Module"
			],
			"ai_capabilities": {
				"learning_rate": 0.8,
				"emotional_simulation": 0.7,
				"combat_proficiency": 0.6
			}
		},
		"gen3": {
			"display_name": "Generation 3",
			"description": "Third generation synthetic units with advanced AI and full emotional simulation",
			"features": [
				"Expert Medical Knowledge",
				"Master Engineering Skills",
				"Advanced Social Protocols",
				"Full Emotional Simulation",
				"Advanced Combat Programming",
				"Command Authority"
			],
			"restrictions": [],
			"special_equipment": [
				"Advanced_Neural_Interface",
				"Quantum_Processing_Unit"
			],
			"ai_capabilities": {
				"learning_rate": 1.0,
				"emotional_simulation": 1.0,
				"combat_proficiency": 0.9
			}
		}
	}
	_save_generation_features()

func _save_generation_features():
	var directory = DirAccess.open("res://")
	if not directory.dir_exists("res://Config"):
		directory.make_dir("Config")
	
	var file = FileAccess.open(GENERATION_FEATURES_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(generation_features, "  "))
		file.close()

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

func create_item_from_name(item_name: String):
	if not _initialization_complete:
		print("AssetManager: Not ready, cannot create item: ", item_name)
		return null
	
	if item_database.has(item_name):
		var item_data = item_database[item_name]
		var scene_path = item_data.get("scene_path", "")
		
		if scene_path != "" and ResourceLoader.exists(scene_path):
			var scene = get_resource(scene_path)
			if scene:
				var item = scene.instantiate()
				if item:
					_configure_item(item, item_name, item_data)
					return item
	
	var scene_path = _scene_path_cache.get(item_name, "")
	
	if scene_path != "":
		var scene = get_resource(scene_path)
		if scene:
			var item = scene.instantiate()
			if item:
				_auto_configure_item(item, item_name, scene_path)
				return item

func create_co_weapon_from_name(weapon_name: String):
	if not co_weapons_database.has(weapon_name):
		print("CO weapon not found: ", weapon_name)
		return null
	
	var weapon_data = co_weapons_database[weapon_name]
	var scene_path = weapon_data.get("scene_path", "")
	
	if scene_path != "" and ResourceLoader.exists(scene_path):
		var scene = get_resource(scene_path)
		if scene:
			var weapon = scene.instantiate()
			if weapon:
				_configure_co_weapon(weapon, weapon_name, weapon_data)
				return weapon
	
	return null

func _configure_co_weapon(weapon: Node, weapon_name: String, weapon_data: Dictionary):
	if "obj_name" in weapon:
		weapon.obj_name = weapon_name
	else:
		weapon.set_meta("obj_name", weapon_name)
	
	if "damage" in weapon_data:
		if "damage" in weapon:
			weapon.damage = weapon_data.damage
		else:
			weapon.set_meta("damage", weapon_data.damage)
	
	if "weapon_type" in weapon_data:
		if "weapon_type" in weapon:
			weapon.weapon_type = weapon_data.weapon_type
		else:
			weapon.set_meta("weapon_type", weapon_data.weapon_type)
	
	if "clearance_level" in weapon_data:
		if "clearance_level" in weapon:
			weapon.clearance_level = weapon_data.clearance_level
		else:
			weapon.set_meta("clearance_level", weapon_data.clearance_level)

func apply_synthetic_wardrobe(entity: Node, wardrobe_config: Dictionary, generation: String = "gen1") -> bool:
	if not entity:
		print("No entity provided for synthetic wardrobe application")
		return false
	
	var inventory_system = entity.get_node_or_null("InventorySystem")
	if not inventory_system:
		print("Entity has no InventorySystem")
		return false
	
	print("Applying synthetic wardrobe for generation: ", generation)
	
	var applied_items = {}
	
	for slot in wardrobe_config:
		var item_name = wardrobe_config[slot]
		if item_name and item_name != "":
			if is_item_compatible_with_generation(slot, item_name, generation):
				var slot_id = _get_slot_id_from_loadout_name(slot)
				if slot_id != -1:
					var item = create_synthetic_wardrobe_item(slot, item_name)
					if item:
						if inventory_system.equip_item(item, slot_id):
							applied_items[slot_id] = item
							print("Equipped synthetic item ", item_name, " to slot ", slot_id)
						else:
							print("Failed to equip synthetic item ", item_name, " to slot ", slot_id)
							item.queue_free()
	
	return true

func create_synthetic_wardrobe_item(slot: String, item_name: String):
	if not synthetic_wardrobe_database.has(slot):
		return create_item_from_name(item_name)
	
	var slot_items = synthetic_wardrobe_database[slot]
	if not slot_items.has(item_name):
		return create_item_from_name(item_name)
	
	var item_data = slot_items[item_name]
	var scene_path = item_data.get("scene_path", "")
	
	if scene_path != "" and ResourceLoader.exists(scene_path):
		var scene = get_resource(scene_path)
		if scene:
			var item = scene.instantiate()
			if item:
				_configure_synthetic_item(item, item_name, item_data)
				return item
	
	return create_item_from_name(item_name)

func _configure_synthetic_item(item: Node, item_name: String, item_data: Dictionary):
	if "obj_name" in item:
		item.obj_name = item_name
	else:
		item.set_meta("obj_name", item_name)
	
	if "pickupable" in item:
		item.pickupable = true
	else:
		item.set_meta("pickupable", true)
	
	if "synthetic_item" in item:
		item.synthetic_item = true
	else:
		item.set_meta("synthetic_item", true)
	
	var generation_compatibility = item_data.get("generation_compatibility", [])
	if generation_compatibility.size() > 0:
		if "generation_compatibility" in item:
			item.generation_compatibility = generation_compatibility
		else:
			item.set_meta("generation_compatibility", generation_compatibility)

func is_item_compatible_with_generation(slot: String, item_name: String, generation: String) -> bool:
	if not synthetic_wardrobe_database.has(slot):
		return true
	
	var slot_items = synthetic_wardrobe_database[slot]
	if not slot_items.has(item_name):
		return true
	
	var item_data = slot_items[item_name]
	var compatibility = item_data.get("generation_compatibility", [])
	
	if compatibility.size() == 0:
		return true
	
	return generation in compatibility

func apply_status_equipment(entity: Node, status: String) -> bool:
	if status == "normal" or not status_equipment_database.has(status):
		return true
	
	var inventory_system = entity.get_node_or_null("InventorySystem")
	if not inventory_system:
		print("Entity has no InventorySystem for status equipment")
		return false
	
	var status_data = status_equipment_database[status]
	var additional_items = status_data.get("additional_items", [])
	
	for item_config in additional_items:
		var item_name = item_config.get("item_name", "")
		var slot_name = item_config.get("slot", "")
		
		if item_name != "" and slot_name != "":
			var slot_id = _get_slot_id_from_loadout_name(slot_name)
			if slot_id != -1:
				var item = create_status_equipment_item(item_config)
				if item:
					if inventory_system.equip_item(item, slot_id):
						print("Equipped status item ", item_name, " to slot ", slot_id)
					else:
						print("Failed to equip status item ", item_name, " to slot ", slot_id)
						item.queue_free()
	
	return true

func create_status_equipment_item(item_config: Dictionary):
	var scene_path = item_config.get("scene_path", "")
	var item_name = item_config.get("item_name", "")
	
	if scene_path != "" and ResourceLoader.exists(scene_path):
		var scene = get_resource(scene_path)
		if scene:
			var item = scene.instantiate()
			if item:
				_configure_status_item(item, item_name, item_config)
				return item
	
	return create_item_from_name(item_name)

func _configure_status_item(item: Node, item_name: String, item_config: Dictionary):
	if "obj_name" in item:
		item.obj_name = item_name
	else:
		item.set_meta("obj_name", item_name)
	
	if "pickupable" in item:
		item.pickupable = true
	else:
		item.set_meta("pickupable", true)
	
	if "status_item" in item:
		item.status_item = true
	else:
		item.set_meta("status_item", true)

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

func apply_commanding_officer_loadout(entity: Node, weapon_choice: String, status: String = "normal") -> bool:
	if not entity:
		print("No entity provided for CO loadout application")
		return false
	
	var inventory_system = entity.get_node_or_null("InventorySystem")
	if not inventory_system:
		print("Entity has no InventorySystem")
		return false
	
	var base_loadout = get_occupation_loadout("Command")
	if not base_loadout.is_empty():
		apply_occupation_loadout(entity, "Command")
	
	if weapon_choice != "" and co_weapons_database.has(weapon_choice):
		var weapon = create_co_weapon_from_name(weapon_choice)
		if weapon:
			if inventory_system.equip_item(weapon, 14):
				print("Equipped CO weapon: ", weapon_choice)
			else:
				print("Failed to equip CO weapon: ", weapon_choice)
				weapon.queue_free()
	
	if status != "normal":
		apply_status_equipment(entity, status)
	
	return true

func get_available_co_weapons() -> Array:
	var weapons = []
	for weapon_name in co_weapons_database:
		var weapon_data = co_weapons_database[weapon_name]
		weapons.append({
			"name": weapon_name,
			"display_name": weapon_data.get("display_name", weapon_name),
			"weapon_type": weapon_data.get("weapon_type", "unknown"),
			"damage": weapon_data.get("damage", 0),
			"rarity": weapon_data.get("rarity", "common"),
			"clearance_level": weapon_data.get("clearance_level", 1)
		})
	return weapons

func get_available_synthetic_wardrobe_items(slot: String, generation: String = "gen1") -> Array:
	if not synthetic_wardrobe_database.has(slot):
		return []
	
	var items = []
	var slot_items = synthetic_wardrobe_database[slot]
	
	for item_name in slot_items:
		var item_data = slot_items[item_name]
		if is_item_compatible_with_generation(slot, item_name, generation):
			items.append({
				"name": item_name,
				"display_name": item_data.get("display_name", item_name),
				"generation_compatibility": item_data.get("generation_compatibility", [])
			})
	
	return items

func get_generation_info(generation: String) -> Dictionary:
	return generation_features.get(generation, {})

func get_all_generations() -> Array:
	var gens = []
	for gen_name in generation_features:
		var gen_data = generation_features[gen_name]
		gens.append({
			"name": gen_name,
			"display_name": gen_data.get("display_name", gen_name),
			"description": gen_data.get("description", ""),
			"features": gen_data.get("features", []),
			"restrictions": gen_data.get("restrictions", [])
		})
	return gens

func get_status_equipment_info(status: String) -> Dictionary:
	return status_equipment_database.get(status, {})

func _auto_configure_item(item: Node, item_name: String, scene_path: String):
	if "obj_name" in item:
		item.obj_name = item_name
	else:
		item.set_meta("obj_name", item_name)
	
	if "pickupable" in item:
		item.pickupable = true
	else:
		item.set_meta("pickupable", true)
	
	var equip_slot = _infer_equip_slot(item_name, scene_path)
	if equip_slot != -1:
		if "valid_slots" in item:
			if not item.valid_slots.has(equip_slot):
				item.valid_slots.append(equip_slot)
		else:
			item.set_meta("valid_slots", [equip_slot])
	
	if _is_storage_item_name(item_name):
		var storage_info = _infer_storage_properties(item_name)
		
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
	
	if "hat" in name_lower or "helmet" in name_lower or "beret" in name_lower or "cap" in name_lower:
		return 1
	if "head" in path_lower:
		return 1
	
	if "glasses" in name_lower or "goggles" in name_lower or "hud" in name_lower:
		return 2
	if "eyes" in path_lower:
		return 2
	
	if "pack" in name_lower or "backpack" in name_lower:
		return 3
	if "back" in path_lower:
		return 3
	
	if "mask" in name_lower:
		return 4
	if "mask" in path_lower:
		return 4
	
	if "jumpsuit" in name_lower or "uniform" in name_lower:
		return 6
	if "uniform" in path_lower:
		return 6
	
	if "suit" in name_lower and "jumpsuit" not in name_lower:
		return 7
	if "suit" in path_lower:
		return 7
	
	if "gloves" in name_lower:
		return 9
	if "gloves" in path_lower:
		return 9
	
	if "boots" in name_lower or "shoes" in name_lower:
		return 10
	if "shoes" in path_lower:
		return 10
	
	if "id" in name_lower:
		return 12
	
	if "belt" in name_lower:
		return 15
	if "belt" in path_lower:
		return 15
	
	if ("tool" in path_lower or "equipment" in path_lower or 
		"wrench" in name_lower or "screwdriver" in name_lower or 
		"flashlight" in name_lower or "multitool" in name_lower or
		"crowbar" in name_lower or "cutters" in name_lower):
		return 14
	
	return -1

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

func _find_item_by_name(applied_items: Dictionary, item_name: String) -> Node:
	for slot_id in applied_items:
		var item = applied_items[slot_id]
		if item:
			var obj_name = item.get("obj_name") if "obj_name" in item else item.get_meta("obj_name")
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
		"Sam": {
			"display_name": "Sam",
			"description": "I need your clothes your boots and your motorcycle",
			"clothing": {
				"W_UNIFORM": "Sam_Uniform",
				"WEAR_SUIT": "Sam_Coat",
				"SHOES": "Sam_Boots",
				"GLOVES": "Sam_Gloves",
				"BELT": "ShotgunBelt",
				"EYES": "Security_Hud",
				"MASK": null,
				"HEAD": "Sam_Beret"
			},
			"inventory": {
				"LEFT_HAND": null,
				"RIGHT_HAND": "MSA_51",
				"BACK": "Synthetic_Backpack_Black",
				"L_STORE": "Medical_Pouch",
				"R_STORE": "Tools_Pouch"
			},
			"storage_contents": {
				"Synthetic_Backpack_Black": ["HEgrenade", "HEgrenade", "HEgrenade", "HEgrenade"],
				"ShotgunBelt": ["STAMAG_6mm", "STAMAG_6mm", "STAMAG_6mm", "STAMAG_6mm", "STAMAG_6mm"],
				"Medical_Pouch": [null, null],
				"Tools_Pouch": [null, null]
			}
		},
		"Engineer": {
			"display_name": "Engineer",
			"description": "Station maintenance and repair specialist",
			"clothing": {
				"W_UNIFORM": "Engineer_Jumpsuit",
				"SHOES": "Work_Boots",
				"BELT": "Tool_Belt",
				"HEAD": "Hard_Hat"
			},
			"inventory": {
				"LEFT_HAND": null,
				"RIGHT_HAND": "Wrench",
				"BACK": "Engineering_Backpack",
				"L_STORE": "Flashlight",
				"R_STORE": "Screwdriver"
			},
			"storage_contents": {
				"Engineering_Backpack": ["Wire_Coil", "Metal_Sheets", "Multitool"],
				"Tool_Belt": ["Crowbar", "Wire_Cutters", "Cable_Coil"]
			}
		},
		"Security": {
			"display_name": "Security Officer",
			"description": "Station law enforcement and protection",
			"clothing": {
				"W_UNIFORM": "Security_Jumpsuit",
				"SHOES": "Combat_Boots",
				"BELT": "Security_Belt",
				"HEAD": "Security_Helmet",
				"GLOVES": "Combat_Gloves"
			},
			"inventory": {
				"LEFT_HAND": null,
				"RIGHT_HAND": "Stun_Baton",
				"BACK": "Security_Backpack",
				"L_STORE": "Flash",
				"R_STORE": "Handcuffs"
			},
			"storage_contents": {
				"Security_Backpack": ["Taser", "Pepper_Spray", "Evidence_Bag"],
				"Security_Belt": ["Handcuffs", "Flash", "Security_Radio"]
			}
		},
		"Medical": {
			"display_name": "Medical Doctor",
			"description": "Station healthcare and emergency response",
			"clothing": {
				"W_UNIFORM": "Medical_Scrubs",
				"SHOES": "Medical_Shoes",
				"BELT": "Medical_Belt",
				"HEAD": "Surgical_Cap",
				"GLOVES": "Latex_Gloves"
			},
			"inventory": {
				"LEFT_HAND": null,
				"RIGHT_HAND": "Medical_Scanner",
				"BACK": "Medical_Backpack",
				"L_STORE": "Syringe",
				"R_STORE": "Pill_Bottle"
			},
			"storage_contents": {
				"Medical_Backpack": ["Bandages", "Surgery_Tools", "Medicine_Kit"],
				"Medical_Belt": ["Syringe", "Pill_Bottle", "Medical_Tricorder"]
			}
		},
		"Science": {
			"display_name": "Scientist",
			"description": "Research and development specialist",
			"clothing": {
				"W_UNIFORM": "Science_Jumpsuit",
				"SHOES": "Lab_Shoes",
				"BELT": "Science_Belt",
				"GLASSES": "Science_Goggles",
				"GLOVES": "Lab_Gloves"
			},
			"inventory": {
				"LEFT_HAND": null,
				"RIGHT_HAND": "Scanner",
				"BACK": "Science_Backpack",
				"L_STORE": "Test_Tube",
				"R_STORE": "Data_Pad"
			},
			"storage_contents": {
				"Science_Backpack": ["Research_Materials", "Lab_Equipment", "Computer_Disk"],
				"Science_Belt": ["Sample_Container", "Analyzer", "Research_Notes"]
			}
		},
		"Command": {
			"display_name": "Command Officer",
			"description": "Station leadership and coordination",
			"clothing": {
				"W_UNIFORM": "Command_Jumpsuit",
				"SHOES": "Officer_Boots",
				"BELT": "Command_Belt",
				"HEAD": "Command_Cap",
				"WEAR_ID": "Command_ID"
			},
			"inventory": {
				"LEFT_HAND": null,
				"RIGHT_HAND": "Command_Tablet",
				"BACK": "Command_Backpack",
				"L_STORE": "Command_Radio",
				"R_STORE": "Access_Card"
			},
			"storage_contents": {
				"Command_Backpack": ["Station_Maps", "Command_Codes", "Emergency_Kit"],
				"Command_Belt": ["Access_Cards", "Command_Radio", "Authorization_Device"]
			}
		},
		"Cargo": {
			"display_name": "Cargo Technician",
			"description": "Supply management and logistics",
			"clothing": {
				"W_UNIFORM": "Cargo_Jumpsuit",
				"SHOES": "Work_Boots",
				"BELT": "Cargo_Belt",
				"GLOVES": "Work_Gloves"
			},
			"inventory": {
				"LEFT_HAND": null,
				"RIGHT_HAND": "Cargo_Scanner",
				"BACK": "Cargo_Backpack",
				"L_STORE": "Manifest",
				"R_STORE": "Label_Printer"
			},
			"storage_contents": {
				"Cargo_Backpack": ["Shipping_Labels", "Cargo_Manifest", "Inventory_Scanner"],
				"Cargo_Belt": ["Tape", "Markers", "Inventory_Device"]
			}
		}
	}

func get_resource(path):
	if path == null or path.is_empty():
		return null
	
	# Check cache first
	if _resource_cache.has(path):
		return _resource_cache[path]
	
	var resource = null
	
	if _asset_registry and _asset_registry.has_method("get_preloaded_asset"):
		resource = _asset_registry.get_preloaded_asset(path)
		
	if not resource and _asset_registry and _asset_registry.has_method("load_asset"):
		resource = _asset_registry.load_asset(path)
	
	# Fallback to direct loading
	if not resource and ResourceLoader.exists(path):
		resource = load(path)
	
	# Cache the result
	if resource:
		_resource_cache[path] = resource
	
	return resource

func get_inhand_texture(item_name: String, hand: String) -> Texture2D:
	var texture_key = item_name + "_" + hand
	
	if inhand_sprites.has(texture_key):
		var texture_path = inhand_sprites[texture_key]
		return get_resource(texture_path)
	
	var name_variations = _generate_item_name_variations(item_name)
	
	for variation in name_variations:
		var variant_key = variation + "_" + hand
		if inhand_sprites.has(variant_key):
			var texture_path = inhand_sprites[variant_key]
			return get_resource(texture_path)
	
	return null

func _generate_item_name_variations(item_name: String) -> Array:
	var variations = []
	
	# Original name
	variations.append(item_name)
	
	# Lowercase
	variations.append(item_name.to_lower())
	
	# Replace spaces with underscores
	variations.append(item_name.replace(" ", "_"))
	variations.append(item_name.to_lower().replace(" ", "_"))
	
	# Remove spaces entirely
	variations.append(item_name.replace(" ", ""))
	variations.append(item_name.to_lower().replace(" ", ""))
	
	# Convert from CamelCase to snake_case
	var snake_case = _convert_to_snake_case(item_name)
	if snake_case != item_name:
		variations.append(snake_case)
	
	return variations

func _convert_to_snake_case(input: String) -> String:
	var result = ""
	for i in range(input.length()):
		var char = input[i]
		if char.to_upper() == char and char.to_lower() != char and i > 0:
			result += "_"
		result += char.to_lower()
	return result

func has_inhand_sprites(item_name: String) -> bool:
	var name_variations = _generate_item_name_variations(item_name)
	
	for variation in name_variations:
		var left_key = variation + "_left"
		var right_key = variation + "_right"
		
		if inhand_sprites.has(left_key) or inhand_sprites.has(right_key):
			return true
	
	return false

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

func add_co_weapon(weapon_name: String, weapon_data: Dictionary):
	co_weapons_database[weapon_name] = weapon_data
	_save_co_weapons_database()

func remove_co_weapon(weapon_name: String):
	if co_weapons_database.has(weapon_name):
		co_weapons_database.erase(weapon_name)
		_save_co_weapons_database()

func add_synthetic_wardrobe_item(slot: String, item_name: String, item_data: Dictionary):
	if not synthetic_wardrobe_database.has(slot):
		synthetic_wardrobe_database[slot] = {}
	
	synthetic_wardrobe_database[slot][item_name] = item_data
	_save_synthetic_wardrobe_database()

func remove_synthetic_wardrobe_item(slot: String, item_name: String):
	if synthetic_wardrobe_database.has(slot) and synthetic_wardrobe_database[slot].has(item_name):
		synthetic_wardrobe_database[slot].erase(item_name)
		_save_synthetic_wardrobe_database()

func add_status_equipment(status: String, equipment_data: Dictionary):
	status_equipment_database[status] = equipment_data
	_save_status_equipment_database()

func remove_status_equipment(status: String):
	if status_equipment_database.has(status):
		status_equipment_database.erase(status)
		_save_status_equipment_database()

func update_generation_features(generation: String, features_data: Dictionary):
	generation_features[generation] = features_data
	_save_generation_features()

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
	count += co_weapons_database.size()
	count += synthetic_wardrobe_database.size()
	return count

func _scan_occupations():
	var occupation_list = []
	
	for occupation_name in occupation_loadouts.keys():
		if occupation_name not in occupation_list:
			occupation_list.append(occupation_name)
	
	for occupation_name in ["Engineer", "Security", "Medical", "Science", "Command", "Cargo", "Synthetic"]:
		if occupation_name not in occupation_list:
			occupation_list.append(occupation_name)
	
	occupations = occupation_list

func _scan_directories():
	print("Using fallback directory scanning...")
	_scan_races()
	_scan_hair_styles()
	_scan_facial_hair()
	_scan_clothing()
	_scan_underwear()
	_scan_undershirts()
	_scan_backgrounds()
	_scan_inhand_sprites()
	_scan_occupations()

func _scan_inhand_sprites():
	print("Fallback: Scanning in-hand directory directly")
	inhand_sprites.clear()
	
	var search_paths = [
		"res://Assets/Icons/Items/In_hand/",
		"res://Assets/Icons/Items/In-hand/", 
		"res://Assets/Icons/Items/InHand/",
		"res://Assets/Icons/Items/Inhand/",
		INHAND_PATH
	]
	
	for search_path in search_paths:
		_scan_single_inhand_directory(search_path)
	
	print("Fallback scan found ", inhand_sprites.size(), " in-hand sprites")

func _scan_single_inhand_directory(directory_path: String):
	var dir = DirAccess.open(directory_path)
	if not dir:
		return
	
	print("Scanning directory: ", directory_path)
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".png") and not file_name.begins_with("."):
			var base_name = file_name.get_basename()
			
			if base_name.ends_with("_left") or base_name.ends_with("_right"):
				var texture_path = directory_path + file_name
				if ResourceLoader.exists(texture_path):
					inhand_sprites[base_name] = texture_path
					print("Found in-hand sprite: ", base_name, " -> ", texture_path)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()

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
	if _asset_registry:
		_build_fast_lookups_from_registry()
	else:
		_scan_directories()
	_verify_assets()
	save_config()

func is_asset_registry_available() -> bool:
	return _asset_registry != null

func get_asset_registry():
	return _asset_registry
