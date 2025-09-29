extends Node2D
class_name ZLevelVisualManager

signal z_level_changed(old_z: int, new_z: int)

@export_group("Z-Level Settings")
@export var show_levels_below: bool = true
@export var max_background_levels: int = 3
@export var background_opacity: float = 0.6
@export var background_scale: float = 0.85
@export var parallax_strength: float = 0.3
@export var blur_strength: float = 2.0
@export var depth_fade_rate: float = 0.25
@export var debug_mode: bool = true

var current_z_level: int = 0
var z_level_containers: Dictionary = {}
var z_level_effects: Dictionary = {}
var camera_ref: Camera2D = null
var last_camera_position: Vector2 = Vector2.ZERO

var tilemap_visualizer: Node = null
var z_level_manager: Node = null
var stair_manager: Node = null

func _ready():
	add_to_group("z_level_visual_manager")
	if debug_mode:
		print("ZLevelVisualManager: Starting up...")
	call_deferred("_initialize_system")

func _process(_delta):
	if camera_ref and show_levels_below:
		_update_parallax_effects()

func _initialize_system():
	_find_system_references()
	_find_camera()
	_discover_z_levels()
	_setup_blur_effects()
	_setup_initial_state()

func _find_system_references():
	var world = get_tree().get_first_node_in_group("world")
	if world:
		tilemap_visualizer = world.get_node_or_null("VisualTileMap")
		z_level_manager = world.get_node_or_null("ZLevelManager")
		stair_manager = world.get_node_or_null("StairManager")
	
	if not tilemap_visualizer:
		tilemap_visualizer = get_node_or_null("../VisualTileMap")
	if not tilemap_visualizer:
		tilemap_visualizer = get_tree().get_first_node_in_group("tilemap_visualizer")
	
	if not z_level_manager:
		z_level_manager = get_tree().get_first_node_in_group("z_level_manager")
	
	if not stair_manager:
		stair_manager = get_tree().get_first_node_in_group("stair_manager")
	
	if debug_mode:
		print("ZLevelVisualManager: Found tilemap_visualizer: ", tilemap_visualizer != null)
		print("ZLevelVisualManager: Found z_level_manager: ", z_level_manager != null)
		print("ZLevelVisualManager: Found stair_manager: ", stair_manager != null)
	
	if z_level_manager:
		if z_level_manager.has_signal("z_level_changed"):
			z_level_manager.connect("z_level_changed", _on_entity_z_level_changed)
			if debug_mode:
				print("ZLevelVisualManager: Connected to ZLevelManager.z_level_changed")
		
		if z_level_manager.has_signal("entity_moved_z_level"):
			z_level_manager.connect("entity_moved_z_level", _on_entity_moved_z_level)
			if debug_mode:
				print("ZLevelVisualManager: Connected to ZLevelManager.entity_moved_z_level")
	
	if stair_manager and stair_manager.has_signal("player_z_level_changed"):
		stair_manager.connect("player_z_level_changed", _on_stair_player_z_changed)
		if debug_mode:
			print("ZLevelVisualManager: Connected to StairManager.player_z_level_changed")

func _find_camera():
	camera_ref = get_viewport().get_camera_2d()
	if not camera_ref:
		var player = get_tree().get_first_node_in_group("player_controller")
		if player:
			camera_ref = player.get_node_or_null("Camera2D")
	
	if camera_ref:
		last_camera_position = camera_ref.global_position
		if debug_mode:
			print("ZLevelVisualManager: Found camera: ", camera_ref.name)

func _discover_z_levels():
	z_level_containers.clear()
	z_level_effects.clear()
	
	if not tilemap_visualizer:
		print("ZLevelVisualManager: ERROR - No tilemap visualizer found!")
		print("ZLevelVisualManager: Make sure you have a 'VisualTileMap' node in your scene")
		return
	
	if debug_mode:
		print("ZLevelVisualManager: Searching for Z-levels in: ", tilemap_visualizer.name)
		print("ZLevelVisualManager: Children found: ")
		for child in tilemap_visualizer.get_children():
			print("  - ", child.name, " (", child.get_class(), ")")
	
	for child in tilemap_visualizer.get_children():
		var container_name = child.name
		var z_level = -1
		
		if container_name.begins_with("Z_Level_"):
			var z_str = container_name.replace("Z_Level_", "")
			z_level = z_str.to_int()
		elif container_name.begins_with("Floor_Z"):
			var z_str = container_name.replace("Floor_Z", "")
			z_level = z_str.to_int()
		elif container_name.begins_with("Level_"):
			var z_str = container_name.replace("Level_", "")
			z_level = z_str.to_int()
		
		if z_level >= 0:
			z_level_containers[z_level] = child
			z_level_effects[z_level] = {
				"original_position": child.position,
				"blur_material": null,
				"depth_offset": Vector2.ZERO
			}
			if debug_mode:
				print("ZLevelVisualManager: Found Z-Level ", z_level, " -> ", container_name)
	
	if z_level_containers.size() == 0:
		print("ZLevelVisualManager: WARNING - No Z-level containers found!")
		print("ZLevelVisualManager: Expected naming: Z_Level_0, Z_Level_1, etc.")
	else:
		print("ZLevelVisualManager: Discovered ", z_level_containers.size(), " Z-levels: ", z_level_containers.keys())

func _setup_blur_effects():
	for z_level in z_level_containers.keys():
		var container = z_level_containers[z_level]
		
		var blur_material = ShaderMaterial.new()
		var blur_shader = Shader.new()
		blur_shader.code = """
shader_type canvas_item;

uniform float blur_amount : hint_range(0.0, 10.0) = 2.0;
uniform float brightness : hint_range(0.0, 2.0) = 0.8;

void fragment() {
	vec2 blur_offset = blur_amount / 512.0;
	vec4 color = vec4(0.0);
	
	for(int x = -2; x <= 2; x++) {
		for(int y = -2; y <= 2; y++) {
			color += texture(TEXTURE, UV + vec2(float(x), float(y)) * blur_offset);
		}
	}
	
	color /= 25.0;
	color.rgb *= brightness;
	COLOR = color;
}
"""
		
		blur_material.shader = blur_shader
		blur_material.set_shader_parameter("blur_amount", 0.0)
		blur_material.set_shader_parameter("brightness", 1.0)
		
		if container is CanvasLayer:
			for child in container.get_children():
				if child is Node2D:
					child.material = blur_material
		else:
			container.material = blur_material
		
		z_level_effects[z_level]["blur_material"] = blur_material

func _setup_initial_state():
	var start_z = 0
	var z_sources = []
	
	if z_level_manager:
		var players = get_tree().get_nodes_in_group("player_controller")
		if players.size() > 0:
			var player_z = z_level_manager.get_entity_z_level(players[0])
			z_sources.append("ZLevelManager: " + str(player_z))
			if player_z >= 0:
				start_z = player_z
	
	if stair_manager:
		var stair_z = stair_manager.get_player_z_level()
		z_sources.append("StairManager: " + str(stair_z))
		if stair_z >= 0 and (z_level_manager == null or stair_z == start_z):
			start_z = stair_z
	
	var players = get_tree().get_nodes_in_group("player_controller")
	if players.size() > 0:
		var player = players[0]
		if "current_z_level" in player:
			z_sources.append("Player.current_z_level: " + str(player.current_z_level))
			if start_z == 0 and player.current_z_level >= 0:
				start_z = player.current_z_level
	
	if debug_mode:
		print("ZLevelVisualManager: Z-level sources found: ", z_sources)
		print("ZLevelVisualManager: Setting initial Z-level to ", start_z)
		print("ZLevelVisualManager: Available Z-levels: ", z_level_containers.keys())
	
	if start_z not in z_level_containers:
		print("ZLevelVisualManager: WARNING - Start Z-level ", start_z, " not found in containers!")
		if z_level_containers.has(0):
			start_z = 0
			print("ZLevelVisualManager: Defaulting to Z-level 0")
		else:
			var available = z_level_containers.keys()
			if available.size() > 0:
				available.sort()
				start_z = available[0]
				print("ZLevelVisualManager: Using first available Z-level: ", start_z)
	
	current_z_level = start_z
	
	_ensure_all_systems_synced(start_z)
	_hide_all_except_current()
	_show_current_level()
	
	if show_levels_below:
		_show_background_levels()

func _hide_all_except_current():
	for z_level in z_level_containers.keys():
		if z_level == current_z_level:
			continue
			
		var container = z_level_containers[z_level]
		var effects = z_level_effects[z_level]
		
		container.visible = false
		container.modulate = Color.WHITE
		container.scale = Vector2.ONE
		container.z_index = 0
		container.position = effects["original_position"]
		
		if effects["blur_material"]:
			effects["blur_material"].set_shader_parameter("blur_amount", 0.0)
			effects["blur_material"].set_shader_parameter("brightness", 1.0)
	
	if debug_mode:
		print("ZLevelVisualManager: Hidden all levels except current (", current_z_level, ")")

func set_active_z_level(new_z: int):
	if new_z == current_z_level:
		if debug_mode:
			print("ZLevelVisualManager: Already at Z-level ", new_z, " - skipping")
		return
	
	var old_z = current_z_level
	current_z_level = new_z
	
	if debug_mode:
		print("ZLevelVisualManager: Switching from Z", old_z, " to Z", new_z)
	
	_hide_all_except_current()
	_show_current_level()
	
	if show_levels_below:
		_show_background_levels()
	
	emit_signal("z_level_changed", old_z, new_z)
	
	if debug_mode:
		print("ZLevelVisualManager: Z-level switch complete")

func _ensure_all_systems_synced(target_z: int):
	if debug_mode:
		print("ZLevelVisualManager: Syncing all systems to Z-level ", target_z)
	
	var players = get_tree().get_nodes_in_group("player_controller")
	if players.size() > 0:
		var player = players[0]
		
		if "current_z_level" in player and player.current_z_level != target_z:
			if debug_mode:
				print("ZLevelVisualManager: Updating player.current_z_level from ", player.current_z_level, " to ", target_z)
			player.current_z_level = target_z
		
		if z_level_manager:
			var manager_z = z_level_manager.get_entity_z_level(player)
			if manager_z != target_z:
				if debug_mode:
					print("ZLevelVisualManager: Updating ZLevelManager from ", manager_z, " to ", target_z)
				z_level_manager.register_entity(player, target_z)
		
		if stair_manager:
			var stair_z = stair_manager.get_player_z_level()
			if stair_z != target_z:
				if debug_mode:
					print("ZLevelVisualManager: StairManager Z-level mismatch - Stair: ", stair_z, ", Target: ", target_z)

func _show_current_level():
	if current_z_level not in z_level_containers:
		print("ZLevelVisualManager: ERROR - Z-level ", current_z_level, " not found!")
		print("ZLevelVisualManager: Available Z-levels: ", z_level_containers.keys())
		return
	
	var container = z_level_containers[current_z_level]
	var effects = z_level_effects[current_z_level]
	
	container.visible = true
	container.modulate = Color.WHITE
	container.scale = Vector2.ONE
	container.z_index = 0
	container.position = effects["original_position"]
	effects["depth_offset"] = Vector2.ZERO
	
	if effects["blur_material"]:
		effects["blur_material"].set_shader_parameter("blur_amount", 0.0)
		effects["blur_material"].set_shader_parameter("brightness", 1.0)
	
	if debug_mode:
		print("ZLevelVisualManager: Showing current Z-level ", current_z_level, " with z_index 1000")

func _show_background_levels():
	for depth in range(1, max_background_levels + 1):
		var bg_z = current_z_level - depth
		
		if bg_z < 0 or bg_z not in z_level_containers:
			continue
		
		var container = z_level_containers[bg_z]
		var effects = z_level_effects[bg_z]
		
		container.visible = true
		
		var depth_factor = float(depth)
		var opacity = background_opacity * pow(1.0 - depth_fade_rate, depth_factor)
		var scale = background_scale - (depth_factor - 1.0) * 0.05
		var blur_amount = blur_strength * depth_factor
		var brightness = 1.0 - (depth_factor * 0.15)
		
		container.modulate = Color(1, 1, 1, opacity)
		container.scale = Vector2(scale, scale)
		container.z_index = -depth
		
		if effects["blur_material"]:
			effects["blur_material"].set_shader_parameter("blur_amount", blur_amount)
			effects["blur_material"].set_shader_parameter("brightness", brightness)
		
		if debug_mode:
			print("ZLevelVisualManager: Showing background Z-level ", bg_z, 
				  " (depth ", depth, ", opacity ", opacity, ", blur ", blur_amount, ")")

func _update_parallax_effects():
	if not camera_ref:
		return
	
	var camera_delta = camera_ref.global_position - last_camera_position
	last_camera_position = camera_ref.global_position
	
	for depth in range(1, max_background_levels + 1):
		var bg_z = current_z_level - depth
		
		if bg_z < 0 or bg_z not in z_level_containers:
			continue
		
		var container = z_level_containers[bg_z]
		var effects = z_level_effects[bg_z]
		
		if not container.visible:
			continue
		
		var parallax_factor = parallax_strength * depth * 0.5
		effects["depth_offset"] += camera_delta * parallax_factor
		
		var max_offset = 50.0 * depth
		effects["depth_offset"] = effects["depth_offset"].limit_length(max_offset)
		
		container.position = effects["original_position"] + effects["depth_offset"]

func _on_entity_z_level_changed(entity: Node, old_z: int, new_z: int):
	if debug_mode:
		print("ZLevelVisualManager: Entity Z-level changed signal - Entity: ", entity.name if entity else "null", ", Old Z: ", old_z, ", New Z: ", new_z)
	
	if entity and entity.is_in_group("player_controller"):
		if debug_mode:
			print("ZLevelVisualManager: Player moved from Z", old_z, " to Z", new_z)
		set_active_z_level(new_z)

func _on_entity_moved_z_level(entity: Node, old_z: int, new_z: int, position: Vector2i):
	if debug_mode:
		print("ZLevelVisualManager: Entity moved Z-level signal - Entity: ", entity.name if entity else "null", ", Old Z: ", old_z, ", New Z: ", new_z, ", Pos: ", position)
	
	if entity and entity.is_in_group("player_controller"):
		if debug_mode:
			print("ZLevelVisualManager: Player moved from Z", old_z, " to Z", new_z, " at position ", position)
		set_active_z_level(new_z)

func _on_stair_player_z_changed(new_z_level: int):
	if debug_mode:
		print("ZLevelVisualManager: Stair manager reports player Z-level changed to ", new_z_level)
	set_active_z_level(new_z_level)

func get_current_z_level() -> int:
	return current_z_level

func get_available_z_levels() -> Array:
	return z_level_containers.keys()

func toggle_background_levels():
	show_levels_below = !show_levels_below
	set_active_z_level(current_z_level)

func set_background_opacity(opacity: float):
	background_opacity = clamp(opacity, 0.0, 1.0)
	if show_levels_below:
		_show_background_levels()

func set_parallax_strength(strength: float):
	parallax_strength = clamp(strength, 0.0, 1.0)

func set_blur_strength(strength: float):
	blur_strength = clamp(strength, 0.0, 10.0)
	if show_levels_below:
		_show_background_levels()

func debug_force_z_level(z: int):
	if debug_mode:
		print("ZLevelVisualManager: DEBUG - Forcing Z-level to ", z)
	set_active_z_level(z)

func debug_print_status():
	print("=== Z-Level Visual Manager Status ===")
	print("Current Z-level: ", current_z_level)
	print("Available Z-levels: ", z_level_containers.keys())
	print("Show levels below: ", show_levels_below)
	print("Background opacity: ", background_opacity)
	print("Parallax strength: ", parallax_strength)
	print("Blur strength: ", blur_strength)
	print("System connections:")
	print("  Z-Level Manager: ", z_level_manager != null)
	print("  Stair Manager: ", stair_manager != null)
	print("  Tilemap Visualizer: ", tilemap_visualizer != null)
	
	for z_level in z_level_containers.keys():
		var container = z_level_containers[z_level]
		var effects = z_level_effects[z_level]
		print("Z", z_level, ": visible=", container.visible, 
			  ", modulate=", container.modulate, 
			  ", scale=", container.scale,
			  ", offset=", effects["depth_offset"])
	
	if z_level_manager:
		var players = get_tree().get_nodes_in_group("player_controller")
		if players.size() > 0:
			var player_z = z_level_manager.get_entity_z_level(players[0])
			print("Player Z-level from manager: ", player_z)
	
	if stair_manager:
		var stair_z = stair_manager.get_player_z_level()
		print("Player Z-level from stairs: ", stair_z)
	
	print("====================================")

func test_z_level_switching():
	print("ZLevelVisualManager: Starting Z-level test...")
	
	for z in z_level_containers.keys():
		print("Testing Z-level ", z)
		set_active_z_level(z)
		await get_tree().create_timer(2.0).timeout
	
	print("ZLevelVisualManager: Test complete!")

func force_refresh():
	if debug_mode:
		print("ZLevelVisualManager: Force refreshing display...")
	
	var temp_z = current_z_level
	current_z_level = -999
	set_active_z_level(temp_z)
