extends Window

var item_scenes = [
	"uid://t33x522pii0b",  # Banana
	"uid://bafal7piiq62r",  # Marine_CM_Uniform
	"uid://cmekjlejs76dx",  # Medical_Scrubs
	"uid://dokjyi8xbqq3f",  # MA_Light_Armor
	"uid://vcq5pgy5hx6q",  # MA_Medium_Armor
	"uid://bivuy3j7hqmiy",  # MA_Heavy_Armor
	"uid://cm766a6sb2g85",  # Marine_Boots
	"uid://3u2w8gvxgm1l",  # Combat_Boots
	"uid://eafyncq222qn",  # Marine_Gloves
	"uid://bcijgf8bgu24c",  # Armored_Gloves
	"uid://dobrb07ygedgq",
	"uid://bykqwbg1pqfju",
]

var player = null
var selected_item_uid: String = ""
var spawn_mode: bool = false
var _game_manager: Node = null

func _ready() -> void:
	close_requested.connect(_on_close)
	_populate_items()
	
	# Get GameManager for multiplayer functionality
	_game_manager = get_node_or_null("/root/GameManager")
	if _game_manager == null:
		print("[AdminSpawnPopup] Could not find GameManager")

func _on_close() -> void:
	visible = false
	spawn_mode = false

func _populate_items() -> void:
	var grid = $VBoxContainer/ScrollContainer/ItemGrid
	
	for child in grid.get_children():
		child.queue_free()
	
	for item_uid in item_scenes:
		var scene = load(item_uid)
		if scene:
			var hbox = HBoxContainer.new()
			
			var btn = Button.new()
			btn.text = scene.resource_path.get_file().get_basename()
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.pressed.connect(_select_item.bind(item_uid))
			hbox.add_child(btn)
			
			var quick_btn = Button.new()
			quick_btn.text = "Quick"
			quick_btn.custom_minimum_size = Vector2(60, 0)
			quick_btn.pressed.connect(_quick_spawn.bind(item_uid))
			hbox.add_child(quick_btn)
			
			grid.add_child(hbox)

func _select_item(item_uid: String) -> void:
	selected_item_uid = item_uid
	spawn_mode = true
	visible = false
	$VBoxContainer/Label.text = "Click a tile to spawn " + load(item_uid).resource_path.get_file().get_basename()

func _quick_spawn(item_uid: String) -> void:
	print("[AdminSpawn] Quick spawn called for: ", item_uid)
	
	if not player:
		_find_player()
	
	if not player:
		print("[AdminSpawn] No player found")
		return
	
	var scene = load(item_uid)
	if scene:
		var grid_x = floor(player.global_position.x / 32) * 32 + 16
		var grid_y = floor(player.global_position.y / 32) * 32 + 16
		var spawn_pos = Vector2(grid_x, grid_y)
		print("[AdminSpawn] Spawning at: ", spawn_pos)
		
		if _game_manager:
			if multiplayer.is_server():
				_game_manager.call("RequestSpawnItem", scene.resource_path, spawn_pos, 1)
			else:
				_game_manager.rpc_id(1, "RequestSpawnItem", scene.resource_path, spawn_pos, 1)
		else:
			print("[AdminSpawn] GameManager not available")
	else:
		print("[AdminSpawn] Failed to load scene")

func _find_player() -> void:
	var world = get_tree().get_first_node_in_group("World")
	if world:
		for child in world.get_children():
			if child.name.is_valid_int():
				player = child
				print("[AdminSpawn] Found player: ", player.name)
				break

func try_spawn_at_position(world_pos: Vector2) -> void:
	print("[AdminSpawn] try_spawn_at_position called, spawn_mode: ", spawn_mode, ", selected: ", selected_item_uid)
	
	if not spawn_mode or selected_item_uid == "":
		print("[AdminSpawn] Not in spawn mode or no item selected")
		return
	
	var scene = load(selected_item_uid)
	if scene:
		var grid_x = floor(world_pos.x / 32) * 32 + 16
		var grid_y = floor(world_pos.y / 32) * 32 + 16
		var spawn_pos = Vector2(grid_x, grid_y)
		
		print("[AdminSpawn] Spawning at grid: ", spawn_pos)
		
		if _game_manager:
			if multiplayer.is_server():
				_game_manager.call("RequestSpawnItem", scene.resource_path, spawn_pos, 1)
			else:
				_game_manager.rpc_id(1, "RequestSpawnItem", scene.resource_path, spawn_pos, 1)
		else:
			print("[AdminSpawn] GameManager not available")
	else:
		print("[AdminSpawn] Failed to load scene")
	
	spawn_mode = false
	selected_item_uid = ""
	$VBoxContainer/Label.text = "Spawn Item"
