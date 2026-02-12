extends Window

var item_scenes = [
	"res://Scenes/Items/Food/Banana.tscn",
	"res://Scenes/Items/Clothing/Uniforms/Marine_CM_Uniform.tscn",
	"res://Scenes/Items/Clothing/Uniforms/Medical_Scrubs.tscn",
	"res://Scenes/Items/Clothing/Armor/MA_Light_Armor.tscn",
	"res://Scenes/Items/Clothing/Armor/MA_Medium_Armor.tscn",
	"res://Scenes/Items/Clothing/Armor/MA_Heavy_Armor.tscn",
	"res://Scenes/Items/Clothing/Boots/Marine_Boots.tscn",
	"res://Scenes/Items/Clothing/Boots/Combat_Boots.tscn",
	"res://Scenes/Items/Clothing/Gloves/Marine_Gloves.tscn",
	"res://Scenes/Items/Clothing/Gloves/Armored_Gloves.tscn",
]

var player = null
var selected_item_uid: String = ""
var spawn_mode: bool = false
var _game_manager: Node = null

func _ready() -> void:
	close_requested.connect(_on_close)
	_populate_items()
	
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
	
	for item_path in item_scenes:
		if not ResourceLoader.exists(item_path):
			continue
		var scene = load(item_path)
		if scene:
			var hbox = HBoxContainer.new()
			
			var btn = Button.new()
			btn.text = scene.resource_path.get_file().get_basename()
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.pressed.connect(_select_item.bind(item_path))
			hbox.add_child(btn)
			
			var quick_btn = Button.new()
			quick_btn.text = "Quick"
			quick_btn.custom_minimum_size = Vector2(60, 0)
			quick_btn.pressed.connect(_quick_spawn.bind(item_path))
			hbox.add_child(quick_btn)
			
			grid.add_child(hbox)

func _select_item(item_path: String) -> void:
	selected_item_uid = item_path
	spawn_mode = true
	visible = false
	$VBoxContainer/Label.text = "Click a tile to spawn " + load(item_path).resource_path.get_file().get_basename()

func _quick_spawn(item_path: String) -> void:
	print("[AdminSpawn] Quick spawn called for: ", item_path)
	
	if not player:
		_find_player()
	
	if not player:
		print("[AdminSpawn] No player found")
		return
	
	var scene = load(item_path)
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
