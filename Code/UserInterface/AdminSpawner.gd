extends Control
class_name AdminSpawner

signal entity_spawned(occupation_name: String, position: Vector2)
signal spawner_closed

var world_node = null
var game_manager = null
var asset_manager = null
var asset_registry = null

@onready var main_panel = $MainPanel
@onready var close_button = $MainPanel/VBox/Header/TitleBar/CloseButton
@onready var status_label = $MainPanel/VBox/Header/StatusLabel
@onready var search_edit = $MainPanel/VBox/Controls/SearchBar/SearchEdit
@onready var category_option = $MainPanel/VBox/Controls/FilterBar/CategoryOption
@onready var items_list = $MainPanel/VBox/ItemsContainer/ItemsScroll/ItemsList
@onready var selected_info = $MainPanel/VBox/Footer/SelectedInfo
@onready var spawn_mode_button = $MainPanel/VBox/Footer/ButtonsContainer/SpawnModeButton
@onready var quick_spawn_button = $MainPanel/VBox/Footer/ButtonsContainer/QuickSpawnButton

var available_occupations: Array = []
var available_objects: Array = []
var filtered_items: Array = []
var selected_item = null
var spawn_mode: bool = false
var categories: Array = ["All", "Personnel", "Objects"]

var is_dragging: bool = false
var is_resizing: bool = false
var drag_offset: Vector2
var resize_edge: String = ""
var resize_threshold: float = 10.0
var min_size: Vector2 = Vector2(400, 300)
var max_size: Vector2 = Vector2(1200, 800)
var resize_start_pos: Vector2
var resize_start_size: Vector2

func _ready():
	main_panel.gui_input.connect(_on_panel_gui_input)
	
	find_world_systems()
	setup_ui()
	load_all_items()
	
	hide()

func find_world_systems():
	var search_methods = [
		func(): return get_tree().current_scene,
		func(): return get_node_or_null("/root/World"),
		func(): return get_node_or_null("../World"),
		func(): return get_node_or_null("../../World"),
		func(): return get_parent().get_node_or_null("World"),
		func(): return get_parent().get_parent().get_node_or_null("World")
	]
	
	for method in search_methods:
		var candidate = method.call()
		if candidate and (candidate.name == "World" or candidate.has_method("add_child")):
			world_node = candidate
			break
	
	if not world_node:
		var world_groups = ["world", "main_world", "game_world"]
		for group_name in world_groups:
			var nodes = get_tree().get_nodes_in_group(group_name)
			if nodes.size() > 0:
				world_node = nodes[0]
				break
	
	game_manager = get_node_or_null("/root/GameManager")
	if not game_manager:
		var managers = get_tree().get_nodes_in_group("game_manager")
		if managers.size() > 0:
			game_manager = managers[0]
	
	asset_manager = get_node_or_null("/root/CharacterAssetManager")
	asset_registry = get_node_or_null("/root/AssetRegistry")

func setup_ui():
	category_option.clear()
	for category in categories:
		category_option.add_item(category)
	
	close_button.pressed.connect(_on_close_pressed)
	search_edit.text_changed.connect(_on_search_changed)
	category_option.item_selected.connect(_on_category_changed)
	spawn_mode_button.pressed.connect(_on_spawn_mode_pressed)
	quick_spawn_button.pressed.connect(_on_quick_spawn_pressed)
	
	update_ui_state()

func load_all_items():
	available_occupations.clear()
	available_objects.clear()
	
	load_occupations()
	load_spawnable_objects()
	
	filter_and_display_items()

func load_occupations():
	if not asset_manager:
		return
	
	for occupation_name in asset_manager.occupations:
		var display_name = asset_manager.get_occupation_display_name(occupation_name)
		var description = asset_manager.get_occupation_description(occupation_name)
		
		available_occupations.append({
			"name": occupation_name,
			"display_name": display_name,
			"description": description,
			"category": "Personnel",
			"type": "occupation"
		})

func load_spawnable_objects():
	if not asset_registry:
		return
	
	var scene_assets = asset_registry.get_assets_by_type("scenes")
	var object_directories = [
		"res://Scenes/Objects/",
		"res://Scenes/Items/"
	]
	
	for scene_path in scene_assets:
		var should_include = false
		for dir_path in object_directories:
			if scene_path.begins_with(dir_path):
				should_include = true
				break
		
		if should_include and not is_character_scene(scene_path):
			var scene_name = scene_path.get_file().get_basename()
			var display_name = format_display_name(scene_name)
			
			available_objects.append({
				"name": scene_name,
				"display_name": display_name,
				"scene_path": scene_path,
				"category": "Objects",
				"type": "object"
			})

func is_character_scene(scene_path: String) -> bool:
	var character_indicators = ["human", "character", "mob", "npc", "person"]
	var path_lower = scene_path.to_lower()
	
	for indicator in character_indicators:
		if indicator in path_lower:
			return true
	
	return false

func format_display_name(name: String) -> String:
	return name.replace("_", " ").capitalize()

func filter_and_display_items():
	filtered_items.clear()
	
	var search_text = search_edit.text.to_lower()
	var selected_category = categories[category_option.selected] if category_option.selected >= 0 else "All"
	
	var all_items = []
	all_items.append_array(available_occupations)
	all_items.append_array(available_objects)
	
	for item in all_items:
		if selected_category != "All" and item.category != selected_category:
			continue
		
		if search_text != "" and not item.display_name.to_lower().contains(search_text):
			continue
		
		filtered_items.append(item)
	
	filtered_items.sort_custom(func(a, b): return a.display_name < b.display_name)
	
	update_items_display()

func update_items_display():
	for child in items_list.get_children():
		child.queue_free()
	
	await get_tree().process_frame
	
	for item in filtered_items:
		var item_button = create_item_button(item)
		items_list.add_child(item_button)

func create_item_button(item: Dictionary) -> Button:
	var button = Button.new()
	button.text = item.display_name
	
	var tooltip_text = ""
	if item.type == "occupation":
		tooltip_text = "Personnel: " + item.get("description", "No description")
	else:
		tooltip_text = "Object: " + item.get("scene_path", "Unknown path")
	
	button.tooltip_text = tooltip_text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 32
	
	if item.type == "occupation":
		button.modulate = Color(0.8, 1.0, 0.9)
	
	button.pressed.connect(_on_item_selected.bind(item))
	
	return button

func update_ui_state():
	if selected_item:
		var info_text = "Selected: " + selected_item.display_name
		if selected_item.type == "occupation":
			info_text += " (Personnel)"
		else:
			info_text += " (Object)"
		selected_info.text = info_text
	else:
		selected_info.text = "No item selected"
	
	if status_label:
		if spawn_mode:
			status_label.text = "🎯 SPAWN MODE ACTIVE - Click outside panel to spawn, ESC to cancel"
		else:
			status_label.text = ""
	
	var has_selection = selected_item != null
	spawn_mode_button.disabled = not has_selection
	quick_spawn_button.disabled = not has_selection
	
	if spawn_mode:
		spawn_mode_button.text = "🚫 Cancel Spawn Mode"
		spawn_mode_button.modulate = Color(1.0, 0.7, 0.7)
	else:
		spawn_mode_button.text = "🎯 Enter Spawn Mode"
		spawn_mode_button.modulate = Color.WHITE
	
	update_button_selection()

func update_button_selection():
	for child in items_list.get_children():
		if child is Button:
			if selected_item and child.text == selected_item.display_name:
				child.modulate = Color(0.8, 1.0, 0.8)
			else:
				if selected_item and selected_item.type == "occupation":
					child.modulate = Color(0.8, 1.0, 0.9)
				else:
					child.modulate = Color.WHITE

func _input(event):
	if not visible:
		return
	
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if spawn_mode:
			cancel_spawn_mode()
		else:
			close_spawner()
		get_viewport().set_input_as_handled()
	
	if spawn_mode and event is InputEventMouseButton and not is_dragging and not is_resizing:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var panel_rect = Rect2(main_panel.global_position, main_panel.size)
			if not panel_rect.has_point(event.global_position):
				handle_spawn_click(event.global_position)
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancel_spawn_mode()
			get_viewport().set_input_as_handled()

func handle_spawn_click(global_pos: Vector2):
	if not selected_item:
		cancel_spawn_mode()
		return
	
	var camera = get_viewport().get_camera_2d()
	var world_pos = global_pos
	if camera:
		world_pos = camera.get_global_mouse_position()
	
	var success = false
	
	if selected_item.type == "occupation":
		success = await spawn_personnel(world_pos)
	else:
		success = spawn_object(world_pos)
	
	if success:
		emit_signal("entity_spawned", selected_item.name, world_pos)
		cancel_spawn_mode()

func spawn_personnel(world_pos: Vector2) -> bool:
	if not game_manager:
		return false
	
	var tile_pos = world_pos_to_tile(world_pos)
	var z_level = get_current_z_level()
	
	var character_data = build_complete_character_data()
	character_data.occupation = asset_manager.occupations.find(selected_item.name)
	character_data.loadout_enabled = true
	
	var npc_name = selected_item.name + "_" + str(Time.get_ticks_msec())
	
	var npc_instance = await game_manager.spawn_npc_at_tile(tile_pos, z_level, npc_name)
	if npc_instance:
		await apply_complete_character_to_npc(npc_instance, character_data)
		await apply_occupation_loadout(npc_instance, character_data)
		return true
	
	return false

func build_complete_character_data() -> Dictionary:
	if not asset_manager:
		return {}
	
	randomize()
	
	var sex = randi() % 2
	var race = randi() % asset_manager.races.size()
	var hair_color = Color(randf_range(0.1, 0.9), randf_range(0.1, 0.8), randf_range(0.05, 0.6))
	
	var character_data = {
		"name": generate_random_name(sex),
		"age": randi() % 63 + 18,
		"race": race,
		"sex": sex,
		"hair_style": 0,
		"hair_color": hair_color,
		"facial_hair": 0,
		"facial_hair_color": hair_color,
		"occupation": 0,
		"clothing": 0,
		"underwear": 0,
		"undershirt": 0,
		"background_text": "",
		"medical_text": "",
		"preview_background": 0,
		"loadout_enabled": true,
		"custom_loadout": {},
		"character_created_version": "3.0",
		"creation_timestamp": Time.get_ticks_msec()
	}
	
	add_readable_names_to_character_data(character_data)
	add_texture_paths_to_character_data(character_data)
	add_color_data_to_character_data(character_data)
	
	return character_data

func add_readable_names_to_character_data(data: Dictionary):
	data.race_name = asset_manager.races[data.race] if data.race < asset_manager.races.size() else "Human"
	data.sex_name = "Male" if data.sex == 0 else "Female"

func add_texture_paths_to_character_data(data: Dictionary):
	var available_hair = asset_manager.get_hair_styles_for_sex(data.sex)
	if available_hair.size() > 1:
		data.hair_style = 1 + (randi() % (available_hair.size() - 1))
		var hair_data = available_hair[data.hair_style]
		data.hair_texture = hair_data.texture
		data.hair_style_name = hair_data.name
	else:
		data.hair_texture = null
		data.hair_style_name = "None"
	
	if data.sex == 0:
		var available_facial_hair = asset_manager.get_facial_hair_for_sex(0)
		if available_facial_hair.size() > 1:
			data.facial_hair = randi() % available_facial_hair.size()
			var facial_hair_data = available_facial_hair[data.facial_hair]
			data.facial_hair_texture = facial_hair_data.texture
			data.facial_hair_name = facial_hair_data.name
		else:
			data.facial_hair_texture = null
			data.facial_hair_name = "None"
	else:
		data.facial_hair_texture = null
		data.facial_hair_name = "None"
	
	var available_clothing = asset_manager.get_clothing_for_sex(data.sex)
	if available_clothing.size() > 1:
		data.clothing = 1 + (randi() % (available_clothing.size() - 1))
		var clothing_data = available_clothing[data.clothing]
		data.clothing_textures = clothing_data.textures.duplicate()
		data.clothing_name = clothing_data.name
	else:
		data.clothing_textures = {}
		data.clothing_name = "None"
	
	var available_underwear = asset_manager.get_underwear_for_sex(data.sex)
	if available_underwear.size() > 0:
		data.underwear = randi() % available_underwear.size()
		var underwear_data = available_underwear[data.underwear]
		data.underwear_texture = underwear_data.texture
		data.underwear_name = underwear_data.name
	
	var available_undershirts = asset_manager.get_undershirts_for_sex(data.sex)
	if available_undershirts.size() > 0:
		if data.sex == 1:
			var valid_tops = []
			for i in range(available_undershirts.size()):
				if available_undershirts[i].name != "None":
					valid_tops.append(i)
			if valid_tops.size() > 0:
				data.undershirt = valid_tops[randi() % valid_tops.size()]
				var undershirt_data = available_undershirts[data.undershirt]
				data.undershirt_texture = undershirt_data.texture
				data.undershirt_name = undershirt_data.name
			else:
				data.undershirt_texture = null
				data.undershirt_name = "None"
		else:
			data.undershirt = randi() % available_undershirts.size()
			var undershirt_data = available_undershirts[data.undershirt]
			data.undershirt_texture = undershirt_data.texture
			data.undershirt_name = undershirt_data.name

func add_color_data_to_character_data(data: Dictionary):
	data.hair_color_r = data.hair_color.r
	data.hair_color_g = data.hair_color.g
	data.hair_color_b = data.hair_color.b
	data.hair_color_a = data.hair_color.a
	
	data.facial_hair_color_r = data.facial_hair_color.r
	data.facial_hair_color_g = data.facial_hair_color.g
	data.facial_hair_color_b = data.facial_hair_color.b
	data.facial_hair_color_a = data.facial_hair_color.a

func generate_random_name(sex: int) -> String:
	var first_names_male = ["Marcus", "John", "David", "Michael", "James", "Robert", "William", "Richard", "Thomas", "Charles"]
	var first_names_female = ["Sarah", "Jennifer", "Lisa", "Karen", "Nancy", "Betty", "Helen", "Sandra", "Donna", "Carol"]
	var last_names = ["Anderson", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Rodriguez", "Martinez"]
	
	var first_names = first_names_male if sex == 0 else first_names_female
	var first_name = first_names[randi() % first_names.size()]
	var last_name = last_names[randi() % last_names.size()]
	
	return first_name + " " + last_name

func apply_complete_character_to_npc(npc_instance: Node, character_data: Dictionary):
	var sprite_system = get_sprite_system(npc_instance)
	if not sprite_system:
		return
	
	await get_tree().process_frame
	
	if sprite_system.has_method("apply_character_data"):
		sprite_system.apply_character_data(character_data)
	else:
		apply_character_data_manually(sprite_system, character_data)
	
	await get_tree().process_frame

func apply_character_data_manually(sprite_system: Node, character_data: Dictionary):
	if sprite_system.has_method("set_sex"):
		sprite_system.set_sex(character_data.sex)
	
	if sprite_system.has_method("set_race"):
		sprite_system.set_race(character_data.race)
	
	if sprite_system.has_method("set_underwear") and character_data.has("underwear_texture") and character_data.underwear_texture:
		if ResourceLoader.exists(character_data.underwear_texture):
			sprite_system.set_underwear(load(character_data.underwear_texture))
	
	if sprite_system.has_method("set_undershirt") and character_data.has("undershirt_texture") and character_data.undershirt_texture:
		if ResourceLoader.exists(character_data.undershirt_texture):
			sprite_system.set_undershirt(load(character_data.undershirt_texture))
	
	if sprite_system.has_method("set_clothing") and character_data.has("clothing_textures"):
		sprite_system.set_clothing(character_data.clothing_textures)
	
	if sprite_system.has_method("set_hair") and character_data.has("hair_texture") and character_data.hair_texture:
		if ResourceLoader.exists(character_data.hair_texture):
			sprite_system.set_hair(load(character_data.hair_texture), character_data.hair_color)
	
	if character_data.sex == 0 and sprite_system.has_method("set_facial_hair") and character_data.has("facial_hair_texture") and character_data.facial_hair_texture:
		if ResourceLoader.exists(character_data.facial_hair_texture):
			sprite_system.set_facial_hair(load(character_data.facial_hair_texture), character_data.facial_hair_color)

func apply_occupation_loadout(npc_instance: Node, character_data: Dictionary):
	if not asset_manager or not character_data.loadout_enabled:
		return
	
	await get_tree().process_frame
	
	var inventory_system = npc_instance.get_node_or_null("InventorySystem")
	if not inventory_system:
		return
	
	var occupation_index = character_data.occupation
	if occupation_index >= asset_manager.occupations.size():
		return
	
	var occupation_name = asset_manager.occupations[occupation_index]
	asset_manager.apply_occupation_loadout(npc_instance, occupation_name)

func get_sprite_system(entity: Node) -> Node:
	var possible_paths = [
		"SpriteSystem",
		"sprite_system",
		"Sprite",
		"CharacterSprite",
		"Visuals/SpriteSystem",
		"HumanSpriteSystem"
	]
	
	for path in possible_paths:
		var sprite_system = entity.get_node_or_null(path)
		if sprite_system:
			return sprite_system
	
	return null

func spawn_object(world_pos: Vector2) -> bool:
	if not selected_item.has("scene_path"):
		return false
	
	var scene_path = selected_item.scene_path
	
	if not asset_registry or not asset_registry.is_asset_loaded(scene_path):
		if not ResourceLoader.exists(scene_path):
			return false
		var scene = load(scene_path)
		if not scene:
			return false
		var instance = scene.instantiate()
		return place_object_instance(instance, world_pos)
	else:
		var scene = asset_registry.get_preloaded_asset(scene_path)
		if scene:
			var instance = scene.instantiate()
			return place_object_instance(instance, world_pos)
	
	return false

func place_object_instance(instance: Node, world_pos: Vector2) -> bool:
	if not instance:
		return false
	
	if instance.has_method("set_global_position"):
		instance.set_global_position(world_pos)
	elif "global_position" in instance:
		instance.global_position = world_pos
	elif "position" in instance:
		instance.position = world_pos
	
	var parent_node = find_spawn_parent()
	if parent_node:
		parent_node.add_child(instance)
		return true
	else:
		instance.queue_free()
		return false

func find_spawn_parent() -> Node:
	var candidates = []
	
	if world_node:
		candidates.append(world_node)
	
	candidates.append(get_tree().current_scene)
	candidates.append(get_tree().root)
	
	for candidate in candidates:
		if candidate and candidate.has_method("add_child"):
			return candidate
	
	return null

func world_pos_to_tile(world_pos: Vector2) -> Vector2i:
	var tile_size = 32
	return Vector2i(int(world_pos.x / tile_size), int(world_pos.y / tile_size))

func get_current_z_level() -> int:
	if world_node and "current_z_level" in world_node:
		return world_node.current_z_level
	return 0

func _on_close_pressed():
	close_spawner()

func _on_search_changed(new_text: String):
	filter_and_display_items()

func _on_category_changed(index: int):
	filter_and_display_items()

func _on_item_selected(item: Dictionary):
	selected_item = item
	update_ui_state()

func _on_spawn_mode_pressed():
	if spawn_mode:
		cancel_spawn_mode()
	else:
		enter_spawn_mode()

func _on_quick_spawn_pressed():
	if not selected_item:
		return
	
	var viewport_size = get_viewport().get_visible_rect().size
	var center_pos = viewport_size / 2
	
	var camera = get_viewport().get_camera_2d()
	if camera:
		center_pos = camera.get_screen_center_position()
	
	var success = false
	
	if selected_item.type == "occupation":
		success = await spawn_personnel(center_pos)
	else:
		success = spawn_object(center_pos)
	
	if success:
		emit_signal("entity_spawned", selected_item.name, center_pos)

func _on_panel_gui_input(event):
	if event is InputEventMouseMotion:
		if not is_dragging and not is_resizing:
			var edge = get_resize_edge(event.global_position)
			update_cursor(edge)
		
		if is_resizing:
			handle_resize(event)
		elif is_dragging:
			handle_drag(event)
	
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var edge = get_resize_edge(event.global_position)
				if edge != "":
					start_resize(event, edge)
				else:
					start_drag(event)
			else:
				stop_drag_resize()

func get_resize_edge(mouse_pos: Vector2) -> String:
	var panel_pos = main_panel.global_position
	var panel_size = main_panel.size
	
	var left = abs(mouse_pos.x - panel_pos.x) < resize_threshold
	var right = abs(mouse_pos.x - (panel_pos.x + panel_size.x)) < resize_threshold
	var top = abs(mouse_pos.y - panel_pos.y) < resize_threshold
	var bottom = abs(mouse_pos.y - (panel_pos.y + panel_size.y)) < resize_threshold
	
	if top and left: return "top_left"
	if top and right: return "top_right" 
	if bottom and left: return "bottom_left"
	if bottom and right: return "bottom_right"
	
	if left: return "left"
	if right: return "right"
	if top: return "top"
	if bottom: return "bottom"
	
	return ""

func update_cursor(edge: String):
	match edge:
		"left", "right":
			main_panel.mouse_default_cursor_shape = Control.CURSOR_HSIZE
		"top", "bottom":
			main_panel.mouse_default_cursor_shape = Control.CURSOR_VSIZE
		"top_left", "bottom_right":
			main_panel.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
		"top_right", "bottom_left":
			main_panel.mouse_default_cursor_shape = Control.CURSOR_BDIAGSIZE
		_:
			main_panel.mouse_default_cursor_shape = Control.CURSOR_ARROW

func start_drag(event):
	is_dragging = true
	drag_offset = main_panel.global_position - event.global_position

func start_resize(event, edge):
	is_resizing = true
	resize_edge = edge
	resize_start_pos = event.global_position
	resize_start_size = main_panel.size

func handle_drag(event):
	var new_pos = event.global_position + drag_offset
	
	var viewport = get_viewport()
	if viewport:
		var viewport_size = viewport.get_visible_rect().size
		var panel_size = main_panel.size
		
		new_pos.x = clamp(new_pos.x, 0, viewport_size.x - panel_size.x)
		new_pos.y = clamp(new_pos.y, 0, viewport_size.y - panel_size.y)
	
	main_panel.position = new_pos

func handle_resize(event):
	var delta = event.global_position - resize_start_pos
	var old_size = main_panel.size
	var old_pos = main_panel.position
	var new_size = resize_start_size
	var new_pos = old_pos
	
	match resize_edge:
		"left":
			new_size.x = resize_start_size.x - delta.x
		"right":
			new_size.x = resize_start_size.x + delta.x
		"top":
			new_size.y = resize_start_size.y - delta.y
		"bottom":
			new_size.y = resize_start_size.y + delta.y
		"top_left":
			new_size.x = resize_start_size.x - delta.x
			new_size.y = resize_start_size.y - delta.y
		"top_right":
			new_size.x = resize_start_size.x + delta.x
			new_size.y = resize_start_size.y - delta.y
		"bottom_left":
			new_size.x = resize_start_size.x - delta.x
			new_size.y = resize_start_size.y + delta.y
		"bottom_right":
			new_size.x = resize_start_size.x + delta.x
			new_size.y = resize_start_size.y + delta.y
	
	new_size.x = clamp(new_size.x, min_size.x, max_size.x)
	new_size.y = clamp(new_size.y, min_size.y, max_size.y)
	
	var size_diff = new_size - old_size
	
	match resize_edge:
		"left", "top_left", "bottom_left":
			new_pos.x = old_pos.x - size_diff.x
		"top", "top_left", "top_right":
			new_pos.y = old_pos.y - size_diff.y
	
	var viewport = get_viewport()
	if viewport:
		var viewport_size = viewport.get_visible_rect().size
		new_pos.x = clamp(new_pos.x, 0, viewport_size.x - new_size.x)
		new_pos.y = clamp(new_pos.y, 0, viewport_size.y - new_size.y)
	
	main_panel.size = new_size
	main_panel.position = new_pos

func stop_drag_resize():
	is_dragging = false
	is_resizing = false
	resize_edge = ""
	main_panel.mouse_default_cursor_shape = Control.CURSOR_ARROW

func show_spawner():
	show()

func close_spawner():
	if spawn_mode:
		cancel_spawn_mode()
	hide()
	emit_signal("spawner_closed")

func enter_spawn_mode():
	if not selected_item:
		return
	
	spawn_mode = true
	update_ui_state()

func cancel_spawn_mode():
	spawn_mode = false
	update_ui_state()

func reload_items():
	available_occupations.clear()
	available_objects.clear()
	load_all_items()
