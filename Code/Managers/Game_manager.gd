extends Node

const MAIN_MENU_SCENE = "res://Scenes/UI/Menus/Main_menu.tscn"
const SETTINGS_SCENE = "res://Scenes/UI/Menus/Settings.tscn"
const NETWORK_UI_SCENE = "res://Scenes/UI/Menus/network_ui.tscn"
const LOBBY_SCENE = "res://Scenes/UI/Menus/lobby_ui.tscn"
const CHARACTER_CREATION_SCENE = "res://Scenes/UI/Menus/character_creation.tscn"
const WORLD_SCENE = "res://Scenes/Maps/Hub.tscn" 
const PLAYER_SCENE_PATH = "res://Scenes/Characters/human.tscn"
const PAUSE_MENU_SCENE = "res://Scenes/UI/Player/pause_menu.tscn"
const ADMIN_SPAWNER_SCENE = "res://Scenes/UI/Ingame/AdminSpawner.tscn"
const ALIEN_SCENE_PATH = "res://Scenes/Characters/alien.tscn"
const DEFAULT_PORT = 7777
const MAX_PLAYERS = 16

enum GameState {MAIN_MENU, NETWORK_SETUP, LOBBY, PLAYING, GAME_OVER, SETTINGS, CHARACTER_CREATION}
enum GameMode {SINGLE_PLAYER, MULTIPLAYER_HOST, MULTIPLAYER_CLIENT}

var current_state = GameState.MAIN_MENU
var previous_state = GameState.MAIN_MENU
var current_game_mode = GameMode.SINGLE_PLAYER

var navigation_stack: Array = []
var current_scene_instance = null
var settings_caller_state = GameState.MAIN_MENU

var players = {}
var local_player_id = 1
var local_player_instance = null
var debug_spawn_as_alien: bool = false

var current_map = "Station"
var current_game_mode_setting = "Standard"
var map_paths = {
	"Station": "res://Scenes/Maps/Hub.tscn",
	"Outpost": "res://Scenes/Maps/Outpost.tscn",
	"Research": "res://Scenes/Maps/Research.tscn"
}

var character_data = {}

var player_scene = null
var connected_peers = []
var network_peer = null
var connection_in_progress = false
var spawn_points = []
var next_spawn_index = 0

var world_ref = null
var tile_occupancy_system = null
var spatial_manager = null
var sensory_system = null
var atmosphere_system = null
var audio_manager = null
var interaction_system = null

var thread_manager: ThreadManager
var threading_initialized = false

var last_atmosphere_update = 0
var atmosphere_update_interval = 5000

var player_ui_states = {}

var npcs = {}

var initialization_step = 0
var initialization_complete = false
var initialization_timer = 0.0

signal game_state_changed(old_state, new_state)
signal player_registered(player_id, player_name)
signal player_unregistered(player_id)
signal player_ready_status_changed(player_id, is_ready)
signal world_loaded()
signal character_data_updated(data)
signal host_ready()
signal player_connected(peer_id)
signal player_disconnected(peer_id)
signal connection_failed()
signal server_disconnected()
signal systems_initialized()

func _ready():
	get_tree().paused = false
	set_process(true)
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	call_deferred("begin_staged_initialization")

func begin_staged_initialization():
	initialization_step = 0
	initialization_timer = 0.0

func _process(delta):
	if not initialization_complete:
		initialization_timer += delta
		if initialization_timer >= 0.1:
			process_initialization_step()
			initialization_timer = 0.0
		return
	
	if threading_initialized and is_in_game():
		update_background_processing()

func process_initialization_step():
	match initialization_step:
		0:
			load_character_data()
			initialization_step += 1
		1:
			change_state(GameState.MAIN_MENU)
			initialization_step += 1
		2:
			if should_initialize_threading():
				call_deferred("initialize_threading_system")
			initialization_step += 1
		3:
			initialization_complete = true

func should_initialize_threading() -> bool:
	return current_state == GameState.PLAYING or current_state == GameState.LOBBY

func initialize_threading_system():
	if threading_initialized:
		return
	
	thread_manager = preload("res://Code/Threading/ThreadManager.gd").new()
	thread_manager.name = "ThreadManager"
	add_child(thread_manager)
	
	await get_tree().process_frame
	
	thread_manager.task_completed.connect(_on_threading_task_completed)
	thread_manager.performance_warning.connect(_on_threading_performance_warning)
	
	threading_initialized = true

func get_player_ui_state(player_id) -> Dictionary:
	if not player_id in player_ui_states:
		player_ui_states[player_id] = {
			"pause_menu_open": false,
			"admin_spawner_open": false,
			"pause_menu_instance": null,
			"admin_spawner_instance": null
		}
	return player_ui_states[player_id]

func toggle_pause_menu(player_id):
	if current_state != GameState.PLAYING:
		return
	
	if is_multiplayer() and player_id != get_local_peer_id():
		return
	
	var ui_state = get_player_ui_state(player_id)
	
	if ui_state.pause_menu_open:
		hide_pause_menu(player_id)
	else:
		show_pause_menu(player_id)
	
	if is_multiplayer():
		sync_ui_state.rpc(player_id, "pause_menu", ui_state.pause_menu_open)

func show_pause_menu(player):
	var ui_state = get_player_ui_state(player)
	
	if ui_state.pause_menu_instance != null and is_instance_valid(ui_state.pause_menu_instance):
		ui_state.pause_menu_instance.show_pause_menu()
		ui_state.pause_menu_open = true
		return
	
	var pause_menu_scene = load(PAUSE_MENU_SCENE)
	if not pause_menu_scene:
		return
		
	ui_state.pause_menu_instance = pause_menu_scene.instantiate()
	
	var ui_layer = player.get_node_or_null("PlayerUI")
	
	ui_layer.add_child(ui_state.pause_menu_instance)
	ui_state.pause_menu_instance.show_pause_menu()
	ui_state.pause_menu_open = true
	
	if ui_state.pause_menu_instance.has_signal("pause_menu_closed"):
		ui_state.pause_menu_instance.pause_menu_closed.connect(
			func(): _on_pause_menu_closed(player)
		)

func hide_pause_menu(player_id):
	var ui_state = get_player_ui_state(player_id)
	
	if ui_state.pause_menu_instance and is_instance_valid(ui_state.pause_menu_instance):
		ui_state.pause_menu_instance.hide_pause_menu()
		ui_state.pause_menu_open = false

func _on_pause_menu_closed(player_id):
	var ui_state = get_player_ui_state(player_id)
	ui_state.pause_menu_open = false
	
	if ui_state.pause_menu_instance and is_instance_valid(ui_state.pause_menu_instance):
		ui_state.pause_menu_instance.queue_free()
		ui_state.pause_menu_instance = null

func toggle_admin_spawner(player_id):
	if current_state != GameState.PLAYING:
		return
	
	if is_multiplayer() and player_id != get_local_peer_id():
		return
	
	var ui_state = get_player_ui_state(player_id)
	
	if ui_state.admin_spawner_open:
		hide_admin_spawner(player_id)
	else:
		show_admin_spawner(player_id)
	
	if is_multiplayer():
		sync_ui_state.rpc(player_id, "admin_spawner", ui_state.admin_spawner_open)

func show_admin_spawner(player):
	var ui_state = get_player_ui_state(player)
	
	if ui_state.admin_spawner_instance != null and is_instance_valid(ui_state.admin_spawner_instance):
		ui_state.admin_spawner_instance.show_spawner()
		ui_state.admin_spawner_open = true
		return
	
	var spawner_scene = load(ADMIN_SPAWNER_SCENE)
	if not spawner_scene:
		return
		
	ui_state.admin_spawner_instance = spawner_scene.instantiate()
	
	var ui_layer = player.get_tree().get_first_node_in_group("ui_elements")
	
	ui_layer.add_child(ui_state.admin_spawner_instance)
	ui_state.admin_spawner_instance.show_spawner()
	ui_state.admin_spawner_open = true
	
	if ui_state.admin_spawner_instance.has_signal("spawner_closed"):
		ui_state.admin_spawner_instance.spawner_closed.connect(
			func(): _on_admin_spawner_closed(player)
		)

func hide_admin_spawner(player_id):
	var ui_state = get_player_ui_state(player_id)
	
	if ui_state.admin_spawner_instance and is_instance_valid(ui_state.admin_spawner_instance):
		ui_state.admin_spawner_instance.close_spawner()
		ui_state.admin_spawner_open = false

func _on_admin_spawner_closed(player_id):
	var ui_state = get_player_ui_state(player_id)
	ui_state.admin_spawner_open = false
	
	if ui_state.admin_spawner_instance and is_instance_valid(ui_state.admin_spawner_instance):
		ui_state.admin_spawner_instance.queue_free()
		ui_state.admin_spawner_instance = null

@rpc("any_peer", "call_local", "reliable")
func sync_ui_state(player_id, ui_type: String, is_open: bool):
	var ui_state = get_player_ui_state(player_id)
	
	match ui_type:
		"pause_menu":
			ui_state.pause_menu_open = is_open
		"admin_spawner":
			ui_state.admin_spawner_open = is_open

func transition_to_scene(scene_path: String, new_state: GameState):
	if not ResourceLoader.exists(scene_path):
		push_error("GameManager: Scene not found: " + scene_path)
		return
	
	get_tree().change_scene_to_file(scene_path)
	
	await get_tree().process_frame
	current_scene_instance = get_tree().current_scene
	
	change_state(new_state)
	setup_scene_connections()

func load_world(map_path = WORLD_SCENE):
	if not threading_initialized:
		call_deferred("initialize_threading_system")
		await get_tree().create_timer(0.5).timeout
	
	get_tree().change_scene_to_file(map_path)
	await get_tree().process_frame
	await get_tree().process_frame
	
	current_scene_instance = get_tree().current_scene
	world_ref = current_scene_instance
	
	if thread_manager:
		thread_manager.set_world_reference(world_ref)
	
	await get_tree().create_timer(0.1).timeout
	find_world_systems()
	find_spawn_points()
	await get_tree().create_timer(0.2).timeout
	
	match current_game_mode:
		GameMode.SINGLE_PLAYER:
			setup_singleplayer()
		GameMode.MULTIPLAYER_HOST:
			await get_tree().create_timer(0.3).timeout
			spawn_player(1)
			for peer_id in connected_peers:
				if peer_id != 1:
					spawn_player(peer_id)
		GameMode.MULTIPLAYER_CLIENT:
			pass
	
	change_state(GameState.PLAYING)
	
	if threading_initialized and thread_manager:
		call_deferred("start_background_world_processing")
	
	emit_signal("world_loaded")

func start_background_world_processing():
	if not thread_manager or not world_ref:
		return
	
	await get_tree().create_timer(1.0).timeout
	
	var atmosphere_coords = get_initial_atmosphere_coordinates()
	if atmosphere_coords.size() > 0 and atmosphere_coords.size() < 500:
		thread_manager.queue_atmosphere_processing(
			atmosphere_coords,
			thread_manager.TaskPriority.LOW
		)
	
	await get_tree().create_timer(0.5).timeout
	
	thread_manager.queue_room_detection(
		0,
		thread_manager.TaskPriority.MEDIUM
	)

func get_initial_atmosphere_coordinates() -> Array:
	var coords = []
	
	for spawn_point in spawn_points:
		for x in range(int(spawn_point.x) - 5, int(spawn_point.x) + 6):
			for y in range(int(spawn_point.y) - 5, int(spawn_point.y) + 6):
				coords.append(Vector2i(x, y))
	
	if coords.is_empty():
		for x in range(-5, 6):
			for y in range(-5, 6):
				coords.append(Vector2i(x, y))
	
	return coords

func setup_singleplayer():
	current_game_mode = GameMode.SINGLE_PLAYER
	setup_singleplayer_peer()
	setup_local_player()

func spawn_npc_at_tile(tile_pos: Vector2i, z_level: int = 0, npc_name: String = "") -> Node:
	if not world_ref or not is_instance_valid(world_ref):
		return null
	
	if player_scene == null:
		var scene_path = ALIEN_SCENE_PATH if debug_spawn_as_alien else PLAYER_SCENE_PATH
		player_scene = load(scene_path)
		if player_scene == null:
			return null
	
	var npc_instance = player_scene.instantiate()
	
	if npc_name == "":
		npc_name = "NPC_" + str(Time.get_ticks_msec())
	
	npc_instance.name = npc_name
	
	npc_instance.set_meta("is_player", false)
	npc_instance.set_meta("is_npc", true)
	npc_instance.set_meta("peer_id", -1)
	
	if "is_npc" in npc_instance:
		npc_instance.is_npc = true
	if "can_be_interacted_with" in npc_instance:
		npc_instance.can_be_interacted_with = true
	
	var world_pos = Vector2(tile_pos.x * 32, tile_pos.y * 32)
	npc_instance.position = world_pos
	
	world_ref.add_child(npc_instance)
	
	await get_tree().process_frame
	
	if npc_instance.has_method("setup_npc"):
		npc_instance.setup_npc()
	
	register_npc(npc_instance)
	
	return npc_instance

func spawn_npc_from_scene(scene_path: String, tile_pos: Vector2i, z_level: int = 0, npc_name: String = "") -> Node:
	if not world_ref or not is_instance_valid(world_ref):
		return null
	
	if not ResourceLoader.exists(scene_path):
		return null
	
	var npc_scene = load(scene_path)
	if not npc_scene:
		return null
	
	var npc_instance = npc_scene.instantiate()
	
	if npc_name == "":
		npc_name = scene_path.get_file().get_basename() + "_" + str(Time.get_ticks_msec())
	
	npc_instance.name = npc_name
	
	npc_instance.set_meta("is_player", false)
	npc_instance.set_meta("is_npc", true)
	npc_instance.set_meta("peer_id", -1)
	
	var world_pos = Vector2(tile_pos.x * 32, tile_pos.y * 32)
	npc_instance.position = world_pos
	
	world_ref.add_child(npc_instance)
	
	await get_tree().process_frame
	
	if npc_instance.has_method("setup_npc"):
		npc_instance.setup_npc()
	
	return npc_instance

func get_spawn_position_from_tile(tile_pos: Vector2i) -> Vector2:
	return Vector2(tile_pos.x * 32, tile_pos.y * 32)

func register_npc(npc_instance: Node):
	var npc_id = "npc_" + str(npc_instance.get_instance_id())
	
	if not "npcs" in self:
		npcs = {}
	
	npcs[npc_id] = {
		"instance": npc_instance,
		"name": npc_instance.name,
		"spawn_time": Time.get_ticks_msec()
	}

func unregister_npc(npc_instance: Node):
	if not "npcs" in self:
		return
	
	var npc_id = "npc_" + str(npc_instance.get_instance_id())
	if npc_id in npcs:
		npcs.erase(npc_id)

func get_all_npcs() -> Array:
	if not "npcs" in self:
		return []
	
	var npc_instances = []
	for npc_data in npcs.values():
		if npc_data.instance and is_instance_valid(npc_data.instance):
			npc_instances.append(npc_data.instance)
	
	return npc_instances

func spawn_player(peer_id: int):
	if is_multiplayer() and not is_multiplayer_host():
		return
		
	if is_single_player():
		if peer_id == local_player_id:
			setup_local_player()
	else:
		if MultiplayerManager:
			var spawn_pos = get_spawn_position(peer_id)
			var customization = get_player_customization(peer_id)
			MultiplayerManager.spawn_player(peer_id, spawn_pos, customization)
		else:
			spawn_player_on_network.rpc(peer_id, get_spawn_position(peer_id))

func setup_local_player():
	if multiplayer.multiplayer_peer == null:
		setup_singleplayer_peer()
	
	local_player_id = multiplayer.get_unique_id()
	
	if player_scene == null:
		var scene_path = ALIEN_SCENE_PATH if debug_spawn_as_alien else PLAYER_SCENE_PATH
		player_scene = load(scene_path)
		if player_scene == null:
			return
	
	var player_instance = player_scene.instantiate()
	player_instance.name = "LocalPlayer"
	
	player_instance.set_meta("is_player", true)
	player_instance.set_meta("is_npc", false)
	player_instance.set_meta("peer_id", local_player_id)
	player_instance.set_multiplayer_authority(local_player_id)
	
	var spawn_pos = get_spawn_position(local_player_id)
	player_instance.position = spawn_pos
	
	players[local_player_id] = {
		"id": local_player_id,
		"name": get_player_name(),
		"ready": true,
		"instance": player_instance,
		"customization": character_data.duplicate()
	}
	
	apply_character_customization_to_player(player_instance, character_data)
	
	current_scene_instance.add_child(player_instance)
	local_player_instance = player_instance
	
	setup_player_camera(player_instance, local_player_id)
	setup_player_controller(player_instance, local_player_id, true)
	
	await get_tree().process_frame
	
	apply_player_loadout(player_instance, character_data)
	
	notify_systems_of_entity_spawn(player_instance, false)

func apply_player_loadout(player_instance: Node, char_data: Dictionary):
	if not char_data.get("loadout_enabled", true):
		return
	
	if not "occupation" in char_data:
		return
	
	var asset_manager = get_node_or_null("/root/CharacterAssetManager")
	if not asset_manager:
		return
	
	var occupation_index = char_data.occupation
	if occupation_index >= asset_manager.occupations.size():
		return
	
	var occupation_name = asset_manager.occupations[occupation_index]
	
	await get_tree().process_frame
	await get_tree().process_frame
	
	var inventory_system = player_instance.get_node_or_null("InventorySystem")
	if not inventory_system:
		return
	
	if not inventory_system.entity:
		inventory_system.entity = player_instance
	
	var loadout = asset_manager.get_occupation_loadout(occupation_name)
	if loadout.is_empty():
		return
	
	var applied_items = {}
	var failed_items = []
	
	var clothing = loadout.get("clothing", {})
	
	for slot_name in clothing:
		var item_name = clothing[slot_name]
		if item_name and item_name != "":
			var success = _equip_loadout_item(asset_manager, inventory_system, item_name, slot_name, applied_items)
			if not success:
				failed_items.append({"item": item_name, "slot": slot_name, "type": "clothing"})
	
	var inventory = loadout.get("inventory", {})
	
	for slot_name in inventory:
		var item_name = inventory[slot_name]
		if item_name and item_name != "":
			var success = _equip_loadout_item(asset_manager, inventory_system, item_name, slot_name, applied_items)
			if not success:
				failed_items.append({"item": item_name, "slot": slot_name, "type": "inventory"})
	
	await get_tree().process_frame
	
	var storage_contents = loadout.get("storage_contents", {})
	
	for storage_item_name in storage_contents:
		var items_to_add = storage_contents[storage_item_name]
		
		var storage_item = _find_item_by_name(applied_items, storage_item_name)
		
		if storage_item and items_to_add is Array:
			for item_name in items_to_add:
				if item_name and item_name != "":
					var item = asset_manager.create_item_from_name(item_name)
					if item:
						if _add_item_to_storage(storage_item, item):
							pass
						else:
							failed_items.append({"item": item_name, "slot": storage_item_name, "type": "storage"})
							item.queue_free()
					else:
						failed_items.append({"item": item_name, "slot": storage_item_name, "type": "storage"})
		else:
			if not storage_item:
				pass
			if not (items_to_add is Array):
				pass
	
	var sprite_system = get_sprite_system(player_instance)
	if sprite_system and sprite_system.has_method("refresh_all_equipment"):
		sprite_system.refresh_all_equipment()
	
	if inventory_system.has_signal("inventory_updated"):
		inventory_system.emit_signal("inventory_updated")

func _equip_loadout_item(asset_manager: Node, inventory_system: Node, item_name: String, slot_name: String, applied_items: Dictionary) -> bool:
	var item = asset_manager.create_item_from_name(item_name)
	if not item:
		return false
	
	var slot_id = asset_manager._get_slot_id_from_loadout_name(slot_name)
	if slot_id == -1:
		item.queue_free()
		return false
	
	if inventory_system.equip_item(item, slot_id):
		applied_items[slot_id] = item
		return true
	else:
		item.queue_free()
		return false

func _find_item_by_name(applied_items: Dictionary, item_name: String) -> Node:
	for slot_id in applied_items:
		var item = applied_items[slot_id]
		if item:
			var obj_name = ""
			if "obj_name" in item:
				obj_name = item.obj_name
			elif item.has_meta("obj_name"):
				obj_name = item.get_meta("obj_name")
			
			if obj_name == item_name:
				return item
	return null

func _add_item_to_storage(storage_item: Node, item: Node) -> bool:
	if not storage_item or not item:
		return false
	
	var storage_type = 0
	if "storage_type" in storage_item:
		storage_type = storage_item.storage_type
	elif storage_item.has_meta("storage_type"):
		storage_type = storage_item.get_meta("storage_type")
	
	if storage_type == 0:
		return false
	
	if storage_item.has_method("add_item_to_storage"):
		return storage_item.add_item_to_storage(item, storage_item.get_parent())
	
	var storage_items = []
	if "storage_items" in storage_item:
		storage_items = storage_item.storage_items
	elif storage_item.has_meta("storage_items"):
		storage_items = storage_item.get_meta("storage_items")
	
	var max_size = 10
	if "storage_max_size" in storage_item:
		max_size = storage_item.storage_max_size
	elif storage_item.has_meta("storage_max_size"):
		max_size = storage_item.get_meta("storage_max_size")
	
	var current_size = 0
	if "storage_current_size" in storage_item:
		current_size = storage_item.storage_current_size
	elif storage_item.has_meta("storage_current_size"):
		current_size = storage_item.get_meta("storage_current_size")
	
	var item_size = 1
	if "w_class" in item:
		item_size = item.w_class
	elif item.has_meta("w_class"):
		item_size = item.get_meta("w_class")
	
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

func update_background_processing():
	var current_time = Time.get_ticks_msec()
	
	if current_time - last_atmosphere_update > atmosphere_update_interval:
		if thread_manager and atmosphere_system:
			queue_atmosphere_update()
		last_atmosphere_update = current_time

func queue_atmosphere_update():
	var coords = []
	
	for player_id in players.keys():
		if players[player_id].instance and is_instance_valid(players[player_id].instance):
			var player_pos = players[player_id].instance.position
			var center = Vector2i(int(player_pos.x), int(player_pos.y))
			
			for x in range(center.x - 3, center.x + 4):
				for y in range(center.y - 3, center.y + 4):
					var coord = Vector2i(x, y)
					if not coords.has(coord):
						coords.append(coord)
	
	if coords.size() > 0 and coords.size() < 200:
		thread_manager.queue_atmosphere_processing(
			coords,
			thread_manager.TaskPriority.BACKGROUND
		)

func _on_threading_task_completed(task_id: String, result):
	if result is Dictionary:
		if "atmosphere_updates" in result:
			apply_atmosphere_updates(result.atmosphere_updates)
		elif "rooms" in result:
			apply_room_detection_results(result)

func _on_threading_performance_warning(task_type, execution_time: float):
	pass

func apply_atmosphere_updates(atmosphere_updates: Array):
	if not atmosphere_system:
		return
	
	for update in atmosphere_updates:
		var coord = update.get("coordinate", Vector2i.ZERO)
		var pressure = update.get("pressure", 101.3)
		var temperature = update.get("temperature", 293.0)
		var gas_mix = update.get("gas_mix", {})
		
		if atmosphere_system.has_method("update_tile_atmosphere"):
			atmosphere_system.update_tile_atmosphere(coord, {
				"pressure": pressure,
				"temperature": temperature,
				"gas_mix": gas_mix
			})

func apply_room_detection_results(room_data: Dictionary):
	if not world_ref:
		return
	
	var rooms = room_data.get("rooms", {})
	var z_level = room_data.get("z_level", 0)
	
	if atmosphere_system and atmosphere_system.has_method("update_rooms"):
		atmosphere_system.update_rooms(z_level, rooms)

func queue_inventory_optimization():
	if not thread_manager:
		return
	
	var inventory_data = []
	
	for player_id in players.keys():
		if players[player_id].instance and is_instance_valid(players[player_id].instance):
			var inventory_system = players[player_id].instance.get_node_or_null("InventorySystem")
			if inventory_system and inventory_system.has_method("get_inventory_data"):
				inventory_data.append({
					"id": player_id,
					"items": inventory_system.get_inventory_data()
				})
	
	if inventory_data.size() > 0:
		thread_manager.queue_inventory_operations(
			inventory_data,
			thread_manager.TaskPriority.LOW
		)

func get_pooled_scene(category: String) -> Node:
	if thread_manager:
		return thread_manager.get_pooled_scene(category)
	return null

func return_scene_to_pool(scene: Node, category: String):
	if thread_manager:
		thread_manager.return_scene_to_pool(scene, category)

func cleanup_threading_system():
	if thread_manager:
		thread_manager.shutdown_all_threads()
		thread_manager.queue_free()
		thread_manager = null
	
	threading_initialized = false

func _exit_tree():
	cleanup_threading_system()

func change_state(new_state: GameState):
	previous_state = current_state
	current_state = new_state
	emit_signal("game_state_changed", previous_state, new_state)

func push_navigation_state(state: GameState):
	navigation_stack.push_back(state)

func pop_navigation_state() -> GameState:
	if navigation_stack.size() > 0:
		return navigation_stack.pop_back()
	return GameState.MAIN_MENU

func clear_navigation_stack():
	navigation_stack.clear()

func is_single_player() -> bool:
	return current_game_mode == GameMode.SINGLE_PLAYER

func is_multiplayer_host() -> bool:
	return current_game_mode == GameMode.MULTIPLAYER_HOST

func is_multiplayer_client() -> bool:
	return current_game_mode == GameMode.MULTIPLAYER_CLIENT

func is_multiplayer() -> bool:
	return current_game_mode == GameMode.MULTIPLAYER_HOST or current_game_mode == GameMode.MULTIPLAYER_CLIENT

func is_in_game() -> bool:
	return current_state == GameState.PLAYING

func is_in_menu() -> bool:
	return current_state != GameState.PLAYING

func show_main_menu():
	clear_navigation_stack()
	transition_to_scene(MAIN_MENU_SCENE, GameState.MAIN_MENU)

func show_character_creation():
	push_navigation_state(current_state)
	transition_to_scene(CHARACTER_CREATION_SCENE, GameState.CHARACTER_CREATION)

func show_network_ui():
	push_navigation_state(current_state)
	transition_to_scene(NETWORK_UI_SCENE, GameState.NETWORK_SETUP)

func show_lobby():
	push_navigation_state(current_state)
	transition_to_scene(LOBBY_SCENE, GameState.LOBBY)

func show_settings():
	settings_caller_state = current_state
	push_navigation_state(current_state)
	transition_to_scene(SETTINGS_SCENE, GameState.SETTINGS)

func show_settings_from_pause():
	settings_caller_state = GameState.PLAYING
	push_navigation_state(current_state)
	transition_to_scene(SETTINGS_SCENE, GameState.SETTINGS)

func return_from_settings():
	var return_state = pop_navigation_state()
	
	match return_state:
		GameState.MAIN_MENU:
			show_main_menu()
		GameState.PLAYING:
			return_to_game()
		GameState.NETWORK_SETUP:
			show_network_ui()
		GameState.LOBBY:
			show_lobby()
		GameState.CHARACTER_CREATION:
			show_character_creation()
		_:
			show_main_menu()

func return_to_game():
	if world_ref and is_instance_valid(world_ref):
		get_tree().current_scene = world_ref
		change_state(GameState.PLAYING)
		get_tree().paused = false
	else:
		show_main_menu()

func return_to_main_menu():
	disconnect_from_game()
	players.clear()
	clear_navigation_stack()
	show_main_menu()

func find_world_systems():
	if current_scene_instance == null:
		return
	
	tile_occupancy_system = current_scene_instance.get_node_or_null("TileOccupancySystem")
	spatial_manager = current_scene_instance.get_node_or_null("SpatialManager")
	sensory_system = current_scene_instance.get_node_or_null("SensorySystem")
	atmosphere_system = current_scene_instance.get_node_or_null("AtmosphereSystem")
	audio_manager = current_scene_instance.get_node_or_null("AudioManager")
	
	var interaction_systems = get_tree().get_nodes_in_group("interaction_system")
	if interaction_systems.size() > 0:
		interaction_system = interaction_systems[0]
	else:
		interaction_system = current_scene_instance.get_node_or_null("InteractionSystem")

func find_spawn_points():
	spawn_points = []
	next_spawn_index = 0
	
	if current_scene_instance:
		var spawn_points_node = current_scene_instance.get_node_or_null("SpawnPoints")
		if spawn_points_node:
			for child in spawn_points_node.get_children():
				spawn_points.append(child.global_position)
		
		if spawn_points.size() == 0:
			for child in current_scene_instance.get_children():
				if child.name.begins_with("SpawnPoint"):
					spawn_points.append(child.global_position)
		
		if spawn_points.size() == 0:
			spawn_points = [Vector2(100, 100), Vector2(200, 100), Vector2(100, 200), Vector2(200, 200)]

func get_spawn_position(peer_id: int) -> Vector2:
	if spawn_points.size() == 0:
		find_spawn_points()
	
	if peer_id <= spawn_points.size():
		return spawn_points[peer_id - 1]
	
	var pos = spawn_points[next_spawn_index]
	next_spawn_index = (next_spawn_index + 1) % spawn_points.size()
	return pos

func setup_scene_connections():
	if not current_scene_instance:
		return
	
	match current_state:
		GameState.LOBBY:
			if current_scene_instance.has_signal("back_pressed"):
				if not current_scene_instance.is_connected("back_pressed", Callable(self, "_on_lobby_back")):
					current_scene_instance.back_pressed.connect(_on_lobby_back)
			
			if current_scene_instance.has_signal("start_game"):
				if not current_scene_instance.is_connected("start_game", Callable(self, "start_game")):
					current_scene_instance.start_game.connect(start_game)
			
			if current_scene_instance.has_method("initialize_from_game_manager"):
				current_scene_instance.initialize_from_game_manager(self)
		
		GameState.NETWORK_SETUP:
			if current_scene_instance.has_signal("back_pressed"):
				if not current_scene_instance.is_connected("back_pressed", Callable(self, "_on_network_back")):
					current_scene_instance.back_pressed.connect(_on_network_back)
		
		GameState.SETTINGS:
			if current_scene_instance.has_signal("settings_closed"):
				if not current_scene_instance.is_connected("settings_closed", Callable(self, "return_from_settings")):
					current_scene_instance.settings_closed.connect(return_from_settings)

func setup_singleplayer_peer():
	var peer = OfflineMultiplayerPeer.new()
	multiplayer.multiplayer_peer = peer
	local_player_id = 1
	connected_peers = [1]

func setup_player_camera(player_instance: Node, peer_id: int):
	var camera = player_instance.get_node_or_null("Camera2D")
	if not camera:
		camera = player_instance.get_node_or_null("PlayerCamera")
		if not camera:
			camera = player_instance.get_node_or_null("Camera")
	
	if camera:
		var is_local_player = false
		
		if is_single_player():
			is_local_player = true
		else:
			var local_id = multiplayer.get_unique_id()
			is_local_player = (peer_id == local_id)
		
		camera.enabled = is_local_player
		
		if is_local_player:
			camera.make_current()

func setup_player_controller(player_instance: Node, peer_id: int, is_local: bool):
	var movement_controller = get_movement_controller(player_instance)
	
	if movement_controller:
		if "peer_id" in movement_controller:
			movement_controller.peer_id = peer_id
		if "is_local_player" in movement_controller:
			movement_controller.is_local_player = is_local
		
		movement_controller.set_multiplayer_authority(peer_id)
		
		if is_single_player():
			if movement_controller.has_method("setup_singleplayer"):
				movement_controller.setup_singleplayer()
			elif movement_controller.has_method("initialize"):
				var init_data = create_init_data(player_instance, peer_id, is_local)
				movement_controller.initialize(init_data)
		else:
			if movement_controller.has_method("setup_multiplayer"):
				movement_controller.setup_multiplayer(peer_id)
			elif movement_controller.has_method("initialize"):
				var init_data = create_init_data(player_instance, peer_id, is_local)
				movement_controller.initialize(init_data)
		
		setup_interaction_components(player_instance, peer_id, is_local)

func setup_interaction_components(player_instance: Node, peer_id: int, is_local: bool):
	var interaction_component = player_instance.get_node_or_null("ItemInteractionComponent")
	if interaction_component:
		interaction_component.set_multiplayer_authority(peer_id)
		
		if interaction_component.has_method("initialize"):
			var init_data = create_init_data(player_instance, peer_id, is_local)
			interaction_component.initialize(init_data)
	
	var inventory_system = player_instance.get_node_or_null("InventorySystem")
	if inventory_system:
		inventory_system.set_multiplayer_authority(peer_id)

func get_movement_controller(player_instance: Node) -> Node:
	var movement_controller = player_instance.get_node_or_null("MovementComponent")
	if not movement_controller:
		movement_controller = player_instance.get_node_or_null("GridMovementController")
	if not movement_controller:
		movement_controller = player_instance
	return movement_controller

func create_init_data(player_instance: Node, peer_id: int, is_local: bool) -> Dictionary:
	return {
		"controller": player_instance,
		"world": current_scene_instance,
		"tile_occupancy_system": tile_occupancy_system,
		"sensory_system": sensory_system,
		"audio_system": audio_manager,
		"sprite_system": get_sprite_system(player_instance),
		"inventory_system": player_instance.get_node_or_null("InventorySystem"),
		"peer_id": peer_id,
		"is_local_player": is_local
	}

func notify_systems_of_entity_spawn(entity_controller, is_npc: bool = false):
	if tile_occupancy_system and tile_occupancy_system.has_method("register_entity_at_tile"):
		var pos = entity_controller.get_current_tile_position() if entity_controller.has_method("get_current_tile_position") else Vector2i.ZERO
		var z_level = entity_controller.current_z_level if "current_z_level" in entity_controller else 0
		tile_occupancy_system.register_entity_at_tile(entity_controller, pos, z_level)
	
	if spatial_manager and spatial_manager.has_method("register_entity"):
		spatial_manager.register_entity(entity_controller)
	
	if not is_npc:
		if interaction_system and interaction_system.has_method("register_player"):
			interaction_system.register_player(entity_controller, true)
		
		var click_handlers = get_tree().get_nodes_in_group("click_system")
		for handler in click_handlers:
			if handler.has_method("set_player_reference"):
				handler.set_player_reference(entity_controller)
		
		var player_systems = get_tree().get_nodes_in_group("player_aware_system")
		for system in player_systems:
			if system.has_method("register_player"):
				system.register_player(entity_controller)
	
	emit_signal("systems_initialized")

func get_sprite_system(player_instance: Node) -> Node:
	var sprite_system = null
	
	var possible_paths = [
		"SpriteSystem",
		"sprite_system", 
		"Sprite",
		"CharacterSprite",
		"Visuals/SpriteSystem",
		"HumanSpriteSystem"
	]
	
	for path in possible_paths:
		sprite_system = player_instance.get_node_or_null(path)
		if sprite_system:
			break
	
	return sprite_system

func apply_character_customization_to_player(player_instance: Node, customization: Dictionary):
	if customization.size() == 0:
		return
	
	var sprite_system = get_sprite_system(player_instance)
	
	if sprite_system:
		if sprite_system.has_method("apply_character_data"):
			sprite_system.apply_character_data(customization)

func set_character_data(data):
	character_data = data.duplicate()
	save_character_data()
	
	var player_id = get_local_peer_id()
	if player_id == 0:
		player_id = 1
	
	if player_id in players:
		players[player_id].customization = character_data.duplicate()
		if "name" in character_data:
			players[player_id].name = character_data.name
	else:
		players[player_id] = {
			"id": player_id,
			"name": get_player_name(),
			"ready": false,
			"instance": null,
			"customization": character_data.duplicate()
		}
	
	if is_multiplayer():
		sync_character_data.rpc(player_id, character_data.duplicate())
	
	if local_player_instance and is_instance_valid(local_player_instance):
		apply_character_customization_to_player(local_player_instance, character_data)
	
	emit_signal("character_data_updated", character_data)

func get_character_data():
	return character_data.duplicate()

func save_character_data():
	var file = FileAccess.open("user://character_data.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(character_data))
		file.close()

func load_character_data():
	if not FileAccess.file_exists("user://character_data.json"):
		return false
	
	var file = FileAccess.open("user://character_data.json", FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()
		
		var json_result = JSON.parse_string(json_string)
		
		if json_result:
			character_data = json_result
			return true
	
	return false

func get_player_name():
	if "name" in character_data:
		return character_data.name
	return "Player"

func get_player_customization(player_id):
	if player_id in players and "customization" in players[player_id] and players[player_id].customization.size() > 0:
		return players[player_id].customization
	
	if character_data.size() > 0:
		return character_data
	
	return {}

func get_local_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 1
	return multiplayer.get_unique_id()

func register_player(player_id, player_name):
	if not player_id in players:
		players[player_id] = {
			"id": player_id,
			"name": player_name,
			"ready": false,
			"instance": null,
			"customization": character_data.duplicate() if character_data.size() > 0 else {}
		}
		
		if is_multiplayer():
			var player_info = {
				"name": player_name,
				"customization": character_data.duplicate() if character_data.size() > 0 else {}
			}
			network_register_player.rpc(player_id, player_info)
		
		emit_signal("player_registered", player_id, player_name)
		update_lobby_ui()

func unregister_player(player_id):
	if player_id in players:
		players.erase(player_id)
		emit_signal("player_unregistered", player_id)
		update_lobby_ui()

func set_player_ready(player_id, is_ready):
	if player_id in players:
		players[player_id].ready = is_ready
		
		if is_multiplayer():
			network_set_player_ready.rpc(player_id, is_ready)
		
		emit_signal("player_ready_status_changed", player_id, is_ready)
		update_lobby_ui()

func check_all_players_ready() -> bool:
	for player_id in players:
		if !players[player_id].ready:
			return false
	return true

func get_players():
	return players

func get_player_data(player_id):
	if player_id in players:
		return players[player_id]
	return null

func update_lobby_ui():
	if current_state == GameState.LOBBY and current_scene_instance and is_instance_valid(current_scene_instance):
		if current_scene_instance.has_method("update_player_list"):
			current_scene_instance.update_player_list()

@rpc("any_peer", "call_local", "reliable")
func sync_character_data(peer_id: int, character_customization: Dictionary):
	if peer_id in players:
		players[peer_id].customization = character_customization.duplicate()
		
		if "name" in character_customization:
			players[peer_id].name = character_customization.name
		
		if "instance" in players[peer_id] and players[peer_id].instance:
			var player_instance = players[peer_id].instance
			if is_instance_valid(player_instance):
				apply_character_customization_to_player(player_instance, character_customization)
	
	update_lobby_ui()

@rpc("any_peer", "call_local", "reliable")
func sync_game_settings(map_name: String, game_mode: String):
	current_map = map_name
	current_game_mode_setting = game_mode
	
	if current_scene_instance and is_instance_valid(current_scene_instance):
		if current_scene_instance.has_method("update_game_settings"):
			current_scene_instance.update_game_settings(map_name, game_mode)

@rpc("any_peer", "call_local", "reliable")
func request_character_data(requesting_peer_id: int):
	if is_multiplayer_host():
		for player_id in players:
			if "customization" in players[player_id]:
				sync_character_data.rpc_id(requesting_peer_id, player_id, players[player_id].customization)

@rpc("any_peer", "call_local", "reliable")
func network_register_player(player_id, player_info):
	var player_name = player_info.name if "name" in player_info else "Player" + str(player_id)
	var customization = player_info.customization if "customization" in player_info else {}
	
	if not player_id in players:
		players[player_id] = {
			"id": player_id,
			"name": player_name,
			"ready": false,
			"instance": null,
			"customization": customization
		}
		
		emit_signal("player_registered", player_id, player_name)
		update_lobby_ui()

@rpc("any_peer", "call_local", "reliable")
func network_set_player_ready(player_id, is_ready):
	if player_id in players:
		players[player_id].ready = is_ready
		emit_signal("player_ready_status_changed", player_id, is_ready)
		update_lobby_ui()

@rpc("authority", "call_local", "reliable")
func spawn_player_on_network(peer_id: int, spawn_position: Vector2):
	if MultiplayerManager:
		var character_data = get_player_customization(peer_id)
		MultiplayerManager._spawn_player_for_peer.rpc(peer_id, spawn_position, character_data)
	else:
		spawn_player_legacy(peer_id, spawn_position)

func spawn_player_legacy(peer_id: int, spawn_position: Vector2):
	if player_scene == null:
		var scene_path = ALIEN_SCENE_PATH if debug_spawn_as_alien else PLAYER_SCENE_PATH
		player_scene = load(scene_path)
		if player_scene == null:
			return
	
	var player_instance = player_scene.instantiate()
	player_instance.name = str(peer_id)
	
	player_instance.set_meta("is_player", true)
	player_instance.set_meta("is_npc", false)
	player_instance.set_meta("peer_id", peer_id)
	player_instance.set_multiplayer_authority(peer_id)
	player_instance.position = spawn_position
	
	var customization = get_player_customization(peer_id)
	
	apply_character_customization_to_player(player_instance, customization)
	
	var world = get_tree().current_scene
	if is_instance_valid(world):
		world.add_child(player_instance)
		
		setup_player_camera(player_instance, peer_id)
		
		var is_local = (peer_id == multiplayer.get_unique_id())
		setup_player_controller(player_instance, peer_id, is_local)
		
		if peer_id in players:
			players[peer_id].instance = player_instance
		
		apply_player_loadout(player_instance, customization)
		
		notify_systems_of_entity_spawn(get_movement_controller(player_instance), false)
	else:
		player_instance.queue_free()

func host_game(port: int = DEFAULT_PORT, use_upnp: bool = true) -> bool:
	current_game_mode = GameMode.MULTIPLAYER_HOST
	
	if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer = null
	
	if MultiplayerManager:
		var success = MultiplayerManager.host_game(port, use_upnp)
		if success:
			network_peer = multiplayer.multiplayer_peer
			local_player_id = 1
			connected_peers = [1]
			
			register_player(local_player_id, get_player_name())
			
			call_deferred("emit_signal", "host_ready")
			call_deferred("show_lobby")
			
			return true
		else:
			current_game_mode = GameMode.SINGLE_PLAYER
			return false
	else:
		return host_game_manual(port, use_upnp)

func host_game_manual(port: int = DEFAULT_PORT, use_upnp: bool = true) -> bool:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	
	if error != OK:
		current_game_mode = GameMode.SINGLE_PLAYER
		return false
	
	if use_upnp:
		setup_upnp(port)
	
	multiplayer.multiplayer_peer = peer
	network_peer = peer
	local_player_id = 1
	connected_peers = [1]
	
	register_player(local_player_id, get_player_name())
	
	call_deferred("emit_signal", "host_ready")
	call_deferred("show_lobby")
	
	return true

func join_game(address: String, port: int = DEFAULT_PORT) -> bool:
	if connection_in_progress:
		return false
	
	current_game_mode = GameMode.MULTIPLAYER_CLIENT
	
	if MultiplayerManager:
		var success = MultiplayerManager.join_game(address, port)
		if success:
			network_peer = multiplayer.multiplayer_peer
			connection_in_progress = true
			return true
		else:
			current_game_mode = GameMode.SINGLE_PLAYER
			return false
	else:
		return join_game_manual(address, port)

func join_game_manual(address: String, port: int = DEFAULT_PORT) -> bool:
	connection_in_progress = true
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	
	if error != OK:
		connection_in_progress = false
		current_game_mode = GameMode.SINGLE_PLAYER
		return false
	
	multiplayer.multiplayer_peer = peer
	network_peer = peer
	
	return true

func disconnect_from_game():
	if MultiplayerManager:
		MultiplayerManager.disconnect_from_game()
	
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
		network_peer = null
	
	current_game_mode = GameMode.SINGLE_PLAYER
	connected_peers = []
	connection_in_progress = false
	players.clear()

func setup_upnp(port: int) -> bool:
	var upnp = UPNP.new()
	var discover_result = upnp.discover()
	
	if discover_result != UPNP.UPNP_RESULT_SUCCESS:
		return false
	
	if upnp.get_gateway() and upnp.get_gateway().is_valid_gateway():
		var map_result_udp = upnp.add_port_mapping(port, port, "Multiplayer Game UDP", "UDP", 0)
		var map_result_tcp = upnp.add_port_mapping(port, port, "Multiplayer Game TCP", "TCP", 0)
		
		if map_result_udp != UPNP.UPNP_RESULT_SUCCESS or map_result_tcp != UPNP.UPNP_RESULT_SUCCESS:
			return false
		
		return true
	
	return false

func _on_peer_connected(peer_id: int):
	connected_peers.append(peer_id)
	
	if is_multiplayer_host():
		for pid in players:
			var player_info = {
				"name": players[pid].name,
				"customization": players[pid].customization if "customization" in players[pid] else {}
			}
			network_register_player.rpc_id(peer_id, pid, player_info)
		
		if current_state == GameState.PLAYING:
			await get_tree().create_timer(1.0).timeout
			
			for existing_peer_id in connected_peers:
				if existing_peer_id != peer_id:
					spawn_player_for_peer(existing_peer_id, peer_id)
			
			spawn_player(peer_id)
	
	emit_signal("player_connected", peer_id)

func _on_peer_disconnected(peer_id: int):
	if connected_peers.has(peer_id):
		connected_peers.erase(peer_id)
	
	if MultiplayerManager:
		MultiplayerManager.despawn_player(peer_id)
	else:
		remove_player_instance(peer_id)
	
	unregister_player(peer_id)
	emit_signal("player_disconnected", peer_id)

func _on_connected_to_server():
	local_player_id = multiplayer.get_unique_id()
	connection_in_progress = false
	
	var player_info = {
		"name": get_player_name(),
		"customization": character_data.duplicate()
	}
	network_register_player.rpc(local_player_id, player_info)
	
	request_character_data.rpc(local_player_id)
	
	call_deferred("show_lobby")

func _on_connection_failed():
	multiplayer.multiplayer_peer = null
	network_peer = null
	connection_in_progress = false
	current_game_mode = GameMode.SINGLE_PLAYER
	emit_signal("connection_failed")

func _on_server_disconnected():
	multiplayer.multiplayer_peer = null
	network_peer = null
	connection_in_progress = false
	current_game_mode = GameMode.SINGLE_PLAYER
	players.clear()
	emit_signal("server_disconnected")
	call_deferred("return_to_main_menu")

func spawn_player_for_peer(existing_peer_id: int, new_peer_id: int):
	if MultiplayerManager:
		var spawn_pos = get_spawn_position(existing_peer_id)
		var customization = get_player_customization(existing_peer_id)
		MultiplayerManager._spawn_player_for_peer.rpc_id(new_peer_id, existing_peer_id, spawn_pos, customization)

func remove_player_instance(peer_id: int):
	var world = get_tree().current_scene
	if is_instance_valid(world):
		var player_node = world.get_node_or_null(str(peer_id))
		if player_node:
			player_node.queue_free()
	
	if peer_id in players:
		players[peer_id].instance = null

func start_game(map_name = "", game_mode = ""):
	if map_name == "":
		map_name = current_map
	
	if game_mode == "":
		game_mode = current_game_mode_setting
	
	var map_path = map_paths.get(map_name, WORLD_SCENE)
	
	if is_multiplayer() and is_multiplayer_host():
		network_start_game_countdown.rpc()
		await get_tree().create_timer(5.0).timeout
		network_start_game.rpc(map_name)
	elif is_single_player():
		load_world(map_path)

func update_game_settings(map_name: String, game_mode: String):
	current_map = map_name
	current_game_mode_setting = game_mode
	
	if is_multiplayer() and is_multiplayer_host():
		sync_game_settings.rpc(map_name, game_mode)
	
	update_lobby_ui()

@rpc("authority", "call_local", "reliable")
func network_start_game_countdown():
	if current_state == GameState.LOBBY and current_scene_instance and is_instance_valid(current_scene_instance):
		if current_scene_instance.has_method("start_countdown"):
			current_scene_instance.start_countdown()

@rpc("authority", "call_local", "reliable")
func network_start_game(map_name):
	var map_path = map_paths.get(map_name, WORLD_SCENE)
	load_world(map_path)

func _on_lobby_back():
	var return_state = pop_navigation_state()
	match return_state:
		GameState.NETWORK_SETUP:
			show_network_ui()
		GameState.MAIN_MENU:
			show_main_menu()
		_:
			show_main_menu()

func _on_network_back():
	var return_state = pop_navigation_state()
	match return_state:
		GameState.MAIN_MENU:
			show_main_menu()
		GameState.CHARACTER_CREATION:
			show_character_creation()
		_:
			show_main_menu()

func handle_main_menu_play():
	current_game_mode = GameMode.SINGLE_PLAYER
	show_character_creation()

func handle_main_menu_multiplayer():
	current_game_mode = GameMode.MULTIPLAYER_CLIENT
	show_character_creation()

func handle_character_creation_confirm():
	var return_state = pop_navigation_state()
	
	match current_game_mode:
		GameMode.SINGLE_PLAYER:
			var map_path = map_paths.get(current_map, WORLD_SCENE)
			load_world(map_path)
		GameMode.MULTIPLAYER_CLIENT, GameMode.MULTIPLAYER_HOST:
			show_network_ui()
		_:
			show_main_menu()

func handle_character_creation_cancel():
	var return_state = pop_navigation_state()
	match return_state:
		GameState.MAIN_MENU:
			show_main_menu()
		_:
			show_main_menu()

func get_available_maps() -> Array:
	return map_paths.keys()

func get_map_path(map_name: String) -> String:
	return map_paths.get(map_name, WORLD_SCENE)

func get_current_state_name() -> String:
	match current_state:
		GameState.MAIN_MENU:
			return "Main Menu"
		GameState.NETWORK_SETUP:
			return "Network Setup"
		GameState.LOBBY:
			return "Lobby"
		GameState.PLAYING:
			return "Playing"
		GameState.GAME_OVER:
			return "Game Over"
		GameState.SETTINGS:
			return "Settings"
		GameState.CHARACTER_CREATION:
			return "Character Creation"
		_:
			return "Unknown"

func cleanup_multiplayer_session():
	if network_peer:
		network_peer.close()
		network_peer = null
	
	multiplayer.multiplayer_peer = null
	connected_peers.clear()
	players.clear()
	connection_in_progress = false
	current_game_mode = GameMode.SINGLE_PLAYER

func force_return_to_main_menu():
	cleanup_multiplayer_session()
	clear_navigation_stack()
	get_tree().paused = false
	show_main_menu()

func emergency_exit():
	cleanup_multiplayer_session()
	cleanup_threading_system()
	get_tree().quit()

func debug_print_state():
	var info = get_debug_info()
	for key in info:
		pass

func get_debug_info() -> Dictionary:
	return {
		"current_state": get_current_state_name(),
		"game_mode": current_game_mode,
		"players_count": players.size(),
		"connected_peers_count": connected_peers.size(),
		"threading_initialized": threading_initialized,
		"task_queue_size": thread_manager.task_queue.size() if thread_manager else 0,
		"local_player_id": local_player_id
	}
