extends Node

signal character_data_changed

var game_manager: Node = null
var current_character: Dictionary = {}
var peer_characters: Dictionary = {}
var profile_suffix: String = ""

var available_roles: Dictionary = {
	"Command": ["Commanding Officer", "Executive Officer", "Staff Officer", "Chief MP"],
	"Security / Military Police": ["Military Warden", "Military Police", "Auxiliary Support Officer", "Senior Enlisted Advisor (GySGT)", "Intelligence Officer"],
	"Auxiliary": ["Gunship Pilot", "Dropship Pilot", "Dropship Crew Chief", "Tank Crew"],
	"Synthetic": ["Synthetic", "Working Joe (JOE)"],
	"Support / Civilian": ["Corporate Liaison", "Combat Correspondent (Civ)", "Mess Technician", "Chef", "Chief Engineer", "Ordnance Technician", "Maintenance Technician"],
	"Requisition / Cargo": ["Quartermaster", "Cargo Technician"],
	"Medical": ["Chief Medical Officer", "Researcher", "Doctor (Doc)", "Field Doctor", "Nurse"],
	"Marines / Combat": ["Squad Leader", "Fireteam Leader", "Weapons Specialist", "Smartgunner", "Hospital Corpsman", "Combat Technician", "Rifleman"]
}

var current_slot: int = 0

const LAST_SLOT_FILE = "user://last_character_slot.save"

func _ready() -> void:
	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		if args[i] == "--profile" and i + 1 < args.size():
			profile_suffix = "_" + args[i + 1]
			print("[PreferenceManager] Using profile suffix: ", profile_suffix)
			break
	
	game_manager = get_node_or_null("/root/GameManager")
	if game_manager == null:
		push_error("PreferenceManager: GameManager not found!")
		return
	var last_slot = _load_last_slot()
	load_from_slot(last_slot)

func _load_last_slot() -> int:
	var file_path = LAST_SLOT_FILE.replace(".save", profile_suffix + ".save")
	if FileAccess.file_exists(file_path):
		var file = FileAccess.open(file_path, FileAccess.READ)
		if file:
			var slot = file.get_32()
			file.close()
			print("Loading last used slot: ", slot)
			return slot
	return 0

func _save_last_slot(slot: int) -> void:
	var file_path = LAST_SLOT_FILE.replace(".save", profile_suffix + ".save")
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_32(slot)
		file.close()

func save_to_slot(slot: int) -> void:
	if game_manager == null:
		push_error("PreferenceManager: GameManager is null")
		return
	game_manager.SaveSlot(slot, current_character)
	_save_last_slot(slot)
	load_from_slot(slot)

func load_from_slot(slot: int) -> void:
	if game_manager == null:
		push_error("PreferenceManager: GameManager is null")
		current_character = _get_default_character()
		return
	
	current_character = game_manager.LoadSlot(slot)
	if current_character.is_empty():
		current_character = _get_default_character()
	else:
		print("Loaded character from slot ", slot, ": ", current_character.get("name", "Unnamed"))

	var local_peer_id := multiplayer.get_unique_id()
	if local_peer_id <= 0:
		local_peer_id = 1
	peer_characters[local_peer_id] = current_character.duplicate()
	game_manager.SetPeerCharacterData(local_peer_id, current_character.duplicate())
	if game_manager.has_method("PushLocalAppearanceUpdate"):
		game_manager.PushLocalAppearanceUpdate()
	character_data_changed.emit()
	current_slot = slot
	_save_last_slot(slot)

func _get_default_character() -> Dictionary:
	return {
		"name": "",
		"age": 18,
		"religion": "",
		"clothing": "",
		"underwear": "1",
		"hair_style": "(1)",
		"facial_hair_style": "_1",
		"underwear_style": "1",
		"undershirt_style": "1",
		"hair_base_color": "#000000",
		"hair_gradient_color": "#000000",
		"eye_color": "#000000",
		"race": "Western",
		"gender": "Male",
		"traits": [],
		"role_priorities": {},
		"background": "",
		"randomize_name": false,
		"randomize_appearance": false,
		"origin": "",
		"relations": "",
		"pref_squad": "",
		"assigned_roles": {}
	}

func load_preferences() -> void:
	if game_manager == null:
		push_error("PreferenceManager: GameManager is null")
		current_character = _get_default_character()
		return
	current_character = game_manager.load_player_prefs()
	if current_character.is_empty():
		current_character = _get_default_character()

func save_preferences() -> void:
	if game_manager == null:
		push_error("PreferenceManager: GameManager is null")
		return
	game_manager.save_player_prefs(current_character)

func get_character_data() -> Dictionary:
	return current_character.duplicate()

func get_peer_character_data(peer_id: int) -> Dictionary:
	var data = peer_characters.get(peer_id, {}).duplicate()
	return data

func set_peer_character_data(peer_id: int, data: Dictionary) -> void:
	peer_characters[peer_id] = data.duplicate()

func set_character_data(data: Dictionary) -> void:
	current_character = data.duplicate()
	_persist_current_character()
	character_data_changed.emit()

func randomize_character() -> void:
	if current_character.is_empty():
		current_character = _get_default_character()
	
	if current_character.get("randomize_name", false):
		current_character["name"] = _generate_random_name()
	
	if current_character.get("randomize_appearance", false):
		current_character["hair_style"] = _generate_random_hair_style()
		current_character["facial_hair_style"] = _generate_random_facial_hair_style()
		current_character["hair_base_color"] = _generate_random_color()
		current_character["hair_gradient_color"] = _generate_random_color()
		current_character["eye_color"] = _generate_random_color()
		current_character["race"] = _generate_random_race()
		current_character["gender"] = _generate_random_gender()
		current_character["clothing"] = _generate_random_clothing()
	
	_persist_current_character()
	character_data_changed.emit()

func randomize_on_toggle() -> void:
	current_character["randomize_name"] = not current_character.get("randomize_name", false)
	current_character["randomize_appearance"] = not current_character.get("randomize_appearance", false)
	_persist_current_character()
	character_data_changed.emit()

func update_character_field(field: String, value) -> void:
	current_character[field] = value
	_persist_current_character()
	character_data_changed.emit()

func get_role_priorities() -> Dictionary:
	return current_character.get("role_priorities", {})

func set_role_priority(role: String, priority: String) -> bool:
	var priorities: Dictionary = get_role_priorities()
	for r in priorities:
		if priorities[r] == priority and r != role:
			return false
	if not priorities.has(role) and priorities.size() >= 3:
		return false
	priorities[role] = priority
	current_character["role_priorities"] = priorities
	_persist_current_character()
	character_data_changed.emit()
	return true

func remove_role_priority(role: String) -> void:
	var priorities: Dictionary = get_role_priorities()
	priorities.erase(role)
	current_character["role_priorities"] = priorities
	_persist_current_character()
	character_data_changed.emit()

func get_priority_count() -> int:
	return get_role_priorities().size()

func assign_character_to_role(role: String) -> void:
	current_character["assigned_roles"][role] = current_character.duplicate()
	_persist_current_character()
	character_data_changed.emit()

func get_assigned_character_for_role(role: String) -> Dictionary:
	return current_character.get("assigned_roles", {}).get(role, {})

func assign_role() -> String:
	var priorities: Dictionary = get_role_priorities()
	var high_priority: Array = []
	var med_priority: Array = []
	var low_priority: Array = []
	for role in priorities:
		match priorities[role]:
			"High":
				high_priority.append(role)
			"Medium":
				med_priority.append(role)
			"Low":
				low_priority.append(role)
	if high_priority.size() > 0:
		return high_priority[randi() % high_priority.size()]
	if med_priority.size() > 0:
		return med_priority[randi() % med_priority.size()]
	if low_priority.size() > 0:
		return low_priority[randi() % low_priority.size()]
	for category in available_roles:
		if available_roles[category].size() > 0:
			return available_roles[category][0]
	return "Assistant"

var _preferences: Dictionary = {}

func get_bool(key: String, default: bool = false) -> bool:
	return _preferences.get(key, default)

func set_bool(key: String, value: bool) -> void:
	_preferences[key] = value

func get_int(key: String, default: int = 0) -> int:
	return _preferences.get(key, default)

func set_int(key: String, value: int) -> void:
	_preferences[key] = value


func save_character_to_slot(slot: int) -> void:
	if game_manager == null:
		push_error("PreferenceManager: GameManager is null")
		return
	var data = current_character.duplicate()
	var nickname = data.get("name", "Unnamed")
	if nickname == "":
		nickname = "Unnamed"
	
	var first_letter = nickname.substr(0, 1).to_upper()
	if not first_letter.is_valid_identifier() or first_letter.length() == 0:
		first_letter = "Other"
	
	game_manager.SaveCharacter(first_letter, slot, data)
	current_slot = slot
	_save_last_slot(slot)
	
	print("Character saved to slot ", slot, " in folder ", first_letter)

func load_character_from_slot(slot: int) -> void:
	if game_manager == null:
		push_error("PreferenceManager: GameManager is null")
		return
	var data = game_manager.LoadSlot(slot)
	if not data.is_empty():
		set_character_data(data)
		current_slot = slot
		_save_last_slot(slot)
		print("Loaded character from slot ", slot, ": ", data.get("name", "Unnamed"))
	else:
		print("No character found in slot ", slot)

func get_all_characters_by_letter(letter: String) -> Array:
	if game_manager == null:
		return []
	var chars = []
	var folder_path = game_manager.CHARACTERS_DIR + letter + "/"
	if DirAccess.dir_exists_absolute(folder_path):
		var dir = DirAccess.open(folder_path)
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if file_name.ends_with(".json"):
					var file_path = folder_path + file_name
					var file = FileAccess.open(file_path, FileAccess.READ)
					if file:
						var json_string = file.get_as_text()
						file.close()
						var json = JSON.new()
						if json.parse(json_string) == OK:
							var char_data = json.data as Dictionary
							if not char_data.is_empty():
								chars.append(char_data)
				file_name = dir.get_next()
			dir.list_dir_end()
	chars.sort_custom(func(a, b): return a.get("_slot", 999) < b.get("_slot", 999))
	return chars

func get_all_characters() -> Array:
	var all_chars = []
	var letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".split()
	letters.append("Other")
	
	for letter in letters:
		var chars = get_all_characters_by_letter(letter)
		all_chars.extend(chars)
	
	all_chars.sort_custom(func(a, b): return a.get("_slot", 999) < b.get("_slot", 999))
	return all_chars

func get_slot_names() -> Array:
	if game_manager == null:
		return []
	var names = []
	var all_chars = get_all_characters()
	for i in range(game_manager.SLOT_COUNT):
		if i < all_chars.size():
			names.append(all_chars[i].get("name", "Slot " + str(i + 1)))
		else:
			names.append("Slot " + str(i + 1))
	return names

func delete_character(letter: String, slot: int) -> bool:
	if game_manager == null:
		return false
	var folder_path = game_manager.CHARACTERS_DIR + letter + "/"
	if DirAccess.dir_exists_absolute(folder_path):
		var dir = DirAccess.open(folder_path)
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if file_name.ends_with("_slot" + str(slot) + ".json"):
					var file_path = folder_path + file_name
					dir.list_dir_end()
					return DirAccess.remove_absolute(file_path)
				file_name = dir.get_next()
			dir.list_dir_end()
	return false

func _persist_current_character() -> void:
	if game_manager == null:
		return
	var local_peer_id := multiplayer.get_unique_id()
	if local_peer_id <= 0:
		local_peer_id = 1
	var local_data = current_character.duplicate()
	peer_characters[local_peer_id] = local_data
	game_manager.SetPeerCharacterData(local_peer_id, local_data)
	game_manager.SaveSlot(current_slot, current_character.duplicate())
	if game_manager.has_method("PushLocalAppearanceUpdate"):
		game_manager.PushLocalAppearanceUpdate()

func _generate_random_name() -> String:
	var first_names = ["John", "Jane", "Alex", "Chris", "Sam", "Taylor", "Jordan", "Morgan", "Casey", "Riley"]
	var last_names = ["Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Rodriguez", "Martinez"]
	return first_names[randi() % first_names.size()] + " " + last_names[randi() % last_names.size()]

func _generate_random_hair_style() -> String:
	var styles = ["(1)", "(2)", "(3)", "(4)", "(5)", "(6)", "(7)", "(8)", "(9)", "(10)"]
	return styles[randi() % styles.size()]

func _generate_random_facial_hair_style() -> String:
	var styles = ["_1", "_2", "_3", "_4", "_5", "_6", "_7", "_8", "_9", "_10"]
	return styles[randi() % styles.size()]

func _generate_random_color() -> String:
	var r = randi() % 256
	var g = randi() % 256
	var b = randi() % 256
	return "#" + r.to_hex() + g.to_hex() + b.to_hex()

func _generate_random_race() -> String:
	var races = ["Western", "Eastern", "African", "Asian", "Hispanic", "Mixed"]
	return races[randi() % races.size()]

func _generate_random_gender() -> String:
	var genders = ["Male", "Female", "Non-Binary"]
	return genders[randi() % genders.size()]

func _generate_random_clothing() -> String:
	var clothing = ["Marine Uniform", "Lab Coat", "Engineering Suit", "Medical Scrubs", "Security Uniform", "Standard Uniform"]
	return clothing[randi() % clothing.size()]
