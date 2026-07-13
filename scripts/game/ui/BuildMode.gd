extends Control

@onready var build_button: Button = $HBoxContainer/Build
@onready var destroy_button: Button = $HBoxContainer/Destroy
@onready var back_button: Button = $HBoxContainer/Back

var build_mode_tile_map: TileMap
var world_manager: Node
var collision_manager: Node
var wall_terrain: Dictionary = {}

enum Mode { NONE, BUILD, DESTROY }
var current_mode: Mode = Mode.NONE

func _ready() -> void:
	if _is_dedicated_runtime():
		visible = false
		set_process(false)
		set_process_input(false)
		return

	if not multiplayer.is_server():
		visible = false
		set_process_input(false)
	
	build_button.pressed.connect(func(): current_mode = Mode.BUILD)
	destroy_button.pressed.connect(func(): current_mode = Mode.DESTROY)
	back_button.pressed.connect(_on_back_pressed)
	
	_initialize_world_references()
	_setup_ui_animations()
	
	_connect_build_signal(["BuildActionReceived", "build_action_received"])
	
	visible = false

func _connect_build_signal(signal_names: Array) -> void:
	for signal_name in signal_names:
		if GameManager.has_signal(signal_name):
			GameManager.connect(signal_name, Callable(self, "_on_build_action_received"))
			return

func _setup_ui_animations() -> void:
	UIAnimationHelper.setup_button_animations(build_button)
	UIAnimationHelper.setup_button_animations(destroy_button)
	UIAnimationHelper.setup_button_animations(back_button)

func _initialize_world_references() -> void:
	var world = _find_world()
	if world:
		build_mode_tile_map = world.get_node_or_null("BuildMode")
		world_manager = world.get_node_or_null("WorldManager")
		collision_manager = world.get_node_or_null("CollisionManager")

func _is_dedicated_runtime() -> bool:
	if OS.has_feature("dedicated_server"):
		return true
	return DisplayServer.get_name().to_lower() == "headless"

func _find_world() -> Node:
	var world_from_group = get_tree().get_first_node_in_group("World")
	if world_from_group:
		return world_from_group

	var subviewport = get_node_or_null("/root/Communications/HSplitContainer/SubViewportContainer/SubViewport")
	if subviewport and subviewport.get_child_count() > 0:
		return subviewport.get_child(0)

	var scene = get_tree().current_scene
	if scene and scene.has_node("WorldManager") and scene.has_node("CollisionManager"):
		return scene

	return null

func _on_back_pressed() -> void:
	visible = false
	current_mode = Mode.NONE

func _get_world_mouse_position() -> Vector2:
	var container = get_node_or_null("/root/Communications/HSplitContainer/SubViewportContainer")
	if not container:
		return Vector2.ZERO

	var screen_pos = get_viewport().get_mouse_position()
	var local_pos = screen_pos - container.global_position
	
	if container.stretch:
		local_pos /= Vector2(container.stretch_shrink, container.stretch_shrink)
	
	var camera = container.get_child(0).get_viewport().get_camera_2d()
	return camera.get_canvas_transform().affine_inverse() * local_pos if camera else Vector2.ZERO

func _world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / 32.0), floori(world_pos.y / 32.0))

func _build_at(cell: Vector2i) -> void:
	if not build_mode_tile_map or not world_manager:
		return

	var grid = world_manager.GetGrid()
	if not grid:
		return

	var current_type = grid.get(cell, "")
	
	match current_type:
		"", "base":
			_place_floor(cell)
		"floor":
			if build_mode_tile_map.get_cell_source_id(0, cell) == 2:
				_place_wall(cell)
			else:
				_place_structure(cell)
		"wall":
			_upgrade_wall(cell)
		"structure":
			_place_wall(cell)

func _destroy_at(cell: Vector2i) -> void:
	if not build_mode_tile_map or not world_manager:
		return

	var source_id = build_mode_tile_map.get_cell_source_id(0, cell)
	if source_id != -1:
		_destroy_user_tile(cell)
	else:
		_destroy_static_tile(cell)

func _place_floor(cell: Vector2i) -> void:
	var pos = Vector2(cell.x * 32 + 16, cell.y * 32 + 16)
	_complete_build("floor", pos, cell, 1, Vector2i(0, 15))

func _place_structure(cell: Vector2i) -> void:
	var pos = Vector2(cell.x * 32 + 16, cell.y * 32 + 16)
	_complete_build("structure", pos, cell, 2, Vector2i(0, 0))

func _place_wall(cell: Vector2i) -> void:
	if build_mode_tile_map.get_cell_source_id(0, cell) == 2:
		_remove_structure_node(cell)
	
	var pos = Vector2(cell.x * 32 + 16, cell.y * 32 + 16)
	_complete_build("wall", pos, cell, 0, Vector2i(0, 0))
	wall_terrain[cell] = 0
	_update_wall_terrains(cell)

func _upgrade_wall(cell: Vector2i) -> void:
	if build_mode_tile_map.get_cell_source_id(0, cell) == 0 and wall_terrain.get(cell, -1) == 0:
		build_mode_tile_map.set_cells_terrain_connect(0, [cell], 1, 0)
		build_mode_tile_map.update_internals()
		wall_terrain[cell] = 1
		_update_wall_terrains(cell)

func _complete_build(type: String, pos: Vector2, cell: Vector2i, source_id: int, atlas_coords: Vector2i, broadcast: bool = true) -> void:
	build_mode_tile_map.set_cell(0, cell, source_id, atlas_coords)
	build_mode_tile_map.update_internals()
	
	world_manager.EnsureBase(cell)
	var grid = world_manager.GetGrid()
	grid[cell] = type
	world_manager.UpdateTileRpc(cell, type)
	collision_manager.UpdateWalkable(cell, type)
	
	if type == "structure":
		if not _has_structure_node_at(pos):
			var structure_scene = load("uid://bh4gsgvfy7isy")
			var structure = structure_scene.instantiate()
			structure.position = pos
			build_mode_tile_map.add_child(structure)

	if broadcast:
		_broadcast_build_action("complete_build", {"object_type": type, "position": pos})

func _destroy_user_tile(cell: Vector2i, broadcast: bool = true) -> void:
	build_mode_tile_map.set_cell(0, cell, -1)
	build_mode_tile_map.update_internals()
	wall_terrain.erase(cell)
	
	var grid = world_manager.GetGrid()
	var new_type = "base" if world_manager.BaseLayer.get_cell_source_id(0, cell) != -1 else ""
	
	if new_type:
		grid[cell] = new_type
	else:
		grid.erase(cell)
	
	world_manager.UpdateTileRpc(cell, new_type)
	collision_manager.UpdateWalkable(cell, new_type)
	_remove_structure_node(cell)
	if broadcast:
		_broadcast_build_action("destroy", {"position": Vector2(cell.x * 32 + 16, cell.y * 32 + 16)})

func _destroy_static_tile(cell: Vector2i, broadcast: bool = true) -> void:
	var tile_maps = get_node("/root").find_children("*", "TileMap", true, false)
	var removed = false
	
	for tm in tile_maps:
		if tm != build_mode_tile_map and not tm.is_in_group("Base"):
			for layer in range(tm.get_layers_count()):
				if tm.get_cell_source_id(layer, cell) != -1:
					tm.set_cell(layer, cell, -1)
					tm.update_internals()
					removed = true
	
	if removed:
		var grid = world_manager.GetGrid()
		var new_type = "base" if world_manager.BaseLayer.get_cell_source_id(0, cell) != -1 else ""
		
		if new_type:
			grid[cell] = new_type
		else:
			grid.erase(cell)
		
		world_manager.UpdateTileRpc(cell, new_type)
		collision_manager.UpdateWalkable(cell, new_type)
		if broadcast:
			_broadcast_build_action("destroy", {"position": Vector2(cell.x * 32 + 16, cell.y * 32 + 16)})

func _remove_structure_node(cell: Vector2i) -> void:
	var pos = Vector2(cell.x * 32 + 16, cell.y * 32 + 16)
	for child in build_mode_tile_map.get_children():
		if child is Node2D and child.position == pos:
			child.queue_free()
			break

func _update_wall_terrains(center: Vector2i) -> void:
	var cells = [center]
	var dirs = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	
	for dir in dirs:
		var neighbor = center + dir
		if build_mode_tile_map.get_cell_source_id(0, neighbor) == 0:
			cells.append(neighbor)
	
	for c in cells:
		var terrain = wall_terrain.get(c, 0)
		var terrain_set = 0 if terrain == 0 else 1
		build_mode_tile_map.set_cells_terrain_connect(0, [c], terrain_set, 0)

func _on_build_action_received(_peer_id: int, action: String, data: Dictionary) -> void:
	if _peer_id == multiplayer.get_unique_id():
		return

	if not build_mode_tile_map or not world_manager:
		_initialize_world_references()
		if not build_mode_tile_map or not world_manager:
			return

	match action:
		"complete_build":
			_sync_build(data)
		"destroy":
			_sync_destroy(data)

func _sync_build(data: Dictionary) -> void:
	var object_type = data.get("object_type", "")
	var pos_data = data.get("position", Vector2.ZERO)
	var cell = Vector2i(floori(pos_data.x / 32.0), floori(pos_data.y / 32.0))
	
	match object_type:
		"wall":
			_complete_build("wall", pos_data, cell, 0, Vector2i(0, 0), false)
			_update_wall_terrains(cell)
		"floor":
			_complete_build("floor", pos_data, cell, 1, Vector2i(0, 15), false)
		"structure":
			_complete_build("structure", pos_data, cell, 2, Vector2i(0, 0), false)

func _sync_destroy(data: Dictionary) -> void:
	var pos_data = data.get("position", Vector2.ZERO)
	var cell = Vector2i(floori(pos_data.x / 32.0), floori(pos_data.y / 32.0))
	
	if build_mode_tile_map.get_cell_source_id(0, cell) != -1:
		_destroy_user_tile(cell, false)
	else:
		_destroy_static_tile(cell, false)

func _broadcast_build_action(action: String, data: Dictionary) -> void:
	if multiplayer.is_server():
		GameManager.call("SendBuildAction", multiplayer.get_unique_id(), action, data)

func _has_structure_node_at(pos: Vector2) -> bool:
	if not build_mode_tile_map:
		return false
	for child in build_mode_tile_map.get_children():
		if child is Node2D and child.position == pos:
			return true
	return false
