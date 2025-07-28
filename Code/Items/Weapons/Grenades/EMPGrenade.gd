extends Grenade
class_name EMPGrenade

var devastate_range: int = 0
var heavy_range: int = 2
var light_range: int = 5
var weak_range: int = 5

var devastate_duration: float = 40.0
var heavy_duration: float = 30.0
var light_duration: float = 20.0
var weak_duration: float = 10.0

# Multiplayer integration with InventorySystem
var inventory_sync_enabled: bool = true
var emp_pending: bool = false

# Preloaded resources
static var emp_particle_scene: PackedScene
static var emp_pulse_scene: PackedScene

func _init():
	super._init()
	obj_name = "EMP grenade"
	obj_desc = "A compact device that releases a strong electromagnetic pulse on activation. Is capable of damaging or degrading various electronic system. Capable of being loaded in the any grenade launcher, or thrown by hand."
	grenade_type = GrenadeType.EMP
	det_time = 4.0
	dangerous = false
	
	if not emp_particle_scene:
		emp_particle_scene = preload("res://Scenes/Effects/EMP.tscn")
	if not emp_pulse_scene:
		emp_pulse_scene = preload("res://Scenes/Effects/EMP.tscn")

func _ready():
	super._ready()

# Override Item multiplayer methods to integrate with InventorySystem
func equipped(user, slot: int):
	super.equipped(user, slot)
	
	if get_parent() != user:
		if get_parent():
			get_parent().remove_child(self)
		user.add_child(self)
	
	position = Vector2.ZERO
	visible = false
	
	if inventory_sync_enabled and multiplayer.has_multiplayer_peer():
		sync_grenade_equipped_state.rpc(active, emp_pending, get_item_network_id(self))

func unequipped(user, slot: int):
	super.unequipped(user, slot)
	visible = true
	
	if inventory_sync_enabled and multiplayer.has_multiplayer_peer():
		sync_grenade_unequipped_state.rpc(active, emp_pending, get_item_network_id(self))

func picked_up(user):
	super.picked_up(user)
	
	if get_parent() != user:
		if get_parent():
			get_parent().remove_child(self)
		user.add_child(self)
	
	position = Vector2.ZERO
	visible = false
	
	if inventory_sync_enabled and multiplayer.has_multiplayer_peer():
		sync_grenade_pickup_state.rpc(active, emp_pending, det_time, get_item_network_id(self))

func handle_drop(user):
	super.handle_drop(user)
	
	var world = user.get_parent()
	if get_parent() != world:
		if get_parent():
			get_parent().remove_child(self)
		world.add_child(self)
	
	global_position = user.global_position + Vector2(randf_range(-16, 16), randf_range(-16, 16))
	visible = true
	
	if inventory_sync_enabled and multiplayer.has_multiplayer_peer():
		sync_grenade_drop_state.rpc(active, emp_pending, global_position, get_item_network_id(self))

func throw_to_position(thrower, target_position: Vector2) -> bool:
	var world = thrower.get_parent()
	if get_parent() != world:
		if get_parent():
			get_parent().remove_child(self)
		world.add_child(self)
	
	global_position = thrower.global_position
	visible = true
	
	var result = await super.throw_to_position(thrower, target_position)
	
	if inventory_sync_enabled and multiplayer.has_multiplayer_peer():
		sync_grenade_throw_state.rpc(active, emp_pending, global_position, get_item_network_id(self))
	
	return result

func use(user):
	var result = super.use(user)
	
	if not active:
		result = activate()
	
	return result

func get_item_network_id(item) -> String:
	if item.has_method("get_network_id"):
		return item.get_network_id()
	elif "network_id" in item and item.network_id != "":
		return str(item.network_id)
	elif item.has_meta("network_id"):
		return str(item.get_meta("network_id"))
	else:
		var new_id = str(item.get_instance_id()) + "_" + str(Time.get_ticks_msec())
		item.set_meta("network_id", new_id)
		return new_id

#region INVENTORY SYSTEM INTEGRATION RPCS
@rpc("any_peer", "call_local", "reliable")
func sync_grenade_equipped_state(is_active: bool, pending_emp: bool, item_id: String):
	active = is_active
	emp_pending = pending_emp
	
	var user = find_item_owner(item_id)
	if user and get_parent() != user:
		if get_parent():
			get_parent().remove_child(self)
		user.add_child(self)
		position = Vector2.ZERO
		visible = false

@rpc("any_peer", "call_local", "reliable")
func sync_grenade_unequipped_state(is_active: bool, pending_emp: bool, item_id: String):
	active = is_active
	emp_pending = pending_emp
	visible = true

@rpc("any_peer", "call_local", "reliable")
func sync_grenade_pickup_state(is_active: bool, pending_emp: bool, current_det_time: float, item_id: String):
	active = is_active
	emp_pending = pending_emp
	det_time = current_det_time
	
	var user = find_item_owner(item_id)
	if user and get_parent() != user:
		if get_parent():
			get_parent().remove_child(self)
		user.add_child(self)
		position = Vector2.ZERO
		visible = false

@rpc("any_peer", "call_local", "reliable")
func sync_grenade_drop_state(is_active: bool, pending_emp: bool, drop_pos: Vector2, item_id: String):
	active = is_active
	emp_pending = pending_emp
	global_position = drop_pos
	visible = true
	
	var world = get_tree().current_scene
	if get_parent() != world:
		if get_parent():
			get_parent().remove_child(self)
		world.add_child(self)

@rpc("any_peer", "call_local", "reliable")
func sync_grenade_throw_state(is_active: bool, pending_emp: bool, throw_pos: Vector2, item_id: String):
	active = is_active
	emp_pending = pending_emp
	global_position = throw_pos
	visible = true
	
	var world = get_tree().current_scene
	if get_parent() != world:
		if get_parent():
			get_parent().remove_child(self)
		world.add_child(self)

@rpc("any_peer", "call_local", "reliable")
func sync_emp_explosion(explosion_pos: Vector2, emp_data: Dictionary):
	execute_emp_explosion_local(explosion_pos, emp_data)

@rpc("any_peer", "call_local", "reliable")
func sync_emp_effects(targets_data: Array):
	apply_emp_effects_local(targets_data)

@rpc("any_peer", "call_local", "reliable")
func sync_emp_visual_effect(pos: Vector2, effect_data: Dictionary):
	create_emp_effect_local(pos, effect_data)

@rpc("any_peer", "call_local", "reliable")
func sync_emp_pulse_visual(pos: Vector2, max_range: float):
	create_pulse_visual_local(pos, max_range)

@rpc("any_peer", "call_local", "reliable")
func sync_camera_shake(intensity: float):
	create_camera_shake_local(intensity)
#endregion

func find_item_owner(item_id: String) -> Node:
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		var inventory = player.get_node_or_null("InventorySystem")
		if inventory and "equipped_items" in inventory:
			for slot in inventory.equipped_items:
				var item = inventory.equipped_items[slot]
				if item and get_item_network_id(item) == item_id:
					return player
	return null

func explode() -> void:
	if not active:
		return
	
	var explosion_pos = global_position
	emp_pending = true
	
	super.explode()
	
	var emp_data = {
		"devastate_range": devastate_range,
		"heavy_range": heavy_range,
		"light_range": light_range,
		"weak_range": weak_range,
		"devastate_duration": devastate_duration,
		"heavy_duration": heavy_duration,
		"light_duration": light_duration,
		"weak_duration": weak_duration
	}
	
	if multiplayer.has_multiplayer_peer():
		sync_emp_explosion.rpc(explosion_pos, emp_data)
	else:
		execute_emp_explosion_local(explosion_pos, emp_data)

func execute_emp_explosion_local(explosion_pos: Vector2, emp_data: Dictionary):
	devastate_range = emp_data.get("devastate_range", devastate_range)
	heavy_range = emp_data.get("heavy_range", heavy_range)
	light_range = emp_data.get("light_range", light_range)
	weak_range = emp_data.get("weak_range", weak_range)
	devastate_duration = emp_data.get("devastate_duration", devastate_duration)
	heavy_duration = emp_data.get("heavy_duration", heavy_duration)
	light_duration = emp_data.get("light_duration", light_duration)
	weak_duration = emp_data.get("weak_duration", weak_duration)
	
	var effect_data = {
		"particle_count": 60
	}
	create_emp_effect_local(explosion_pos, effect_data)
	
	apply_emp_pulse(explosion_pos)
	
	create_camera_shake_local(0.5)
	
	emp_pending = false
	_destroy_item_local()

func create_emp_effect_local(pos: Vector2, effect_data: Dictionary) -> void:
	if emp_particle_scene:
		var emp = emp_particle_scene.instantiate()
		if emp:
			get_tree().current_scene.add_child(emp)
			emp.global_position = pos
			
			configure_emp_particles(emp, effect_data)
			create_cleanup_timer(emp, 5.0)
	
	var emp_sound = load("res://Sound/Grenades/EMP.wav")
	play_cached_sound(emp_sound)

func configure_emp_particles(emp: Node, effect_data: Dictionary) -> void:
	var particle_count = effect_data.get("particle_count", 60)
	
	if "amount" in emp:
		emp.amount = particle_count
	
	if "emitting" in emp:
		emp.emitting = true

func apply_emp_pulse(pos: Vector2) -> void:
	var tile_size = 32
	var max_range = max(devastate_range, heavy_range, light_range, weak_range) * tile_size
	
	print_debug("EMP pulse with ranges (", devastate_range, ", ", heavy_range, ", ", light_range, ", ", weak_range, ") at ", pos)
	
	create_pulse_visual_local(pos, max_range)
	
	var electronics = get_tree().get_nodes_in_group("electronics")
	var objects = get_tree().get_nodes_in_group("objects")
	var entities = get_tree().get_nodes_in_group("entities")
	
	var all_targets = electronics + objects + entities
	var targets_data = []
	
	for target in all_targets:
		var target_data = process_emp_target_for_sync(target, pos)
		if target_data.size() > 0:
			targets_data.append(target_data)
	
	if multiplayer.has_multiplayer_peer():
		sync_emp_effects.rpc(targets_data)
	else:
		apply_emp_effects_local(targets_data)

func create_pulse_visual_local(pos: Vector2, max_range: float) -> void:
	if not emp_pulse_scene:
		return
	
	var pulse = emp_pulse_scene.instantiate()
	if pulse:
		get_tree().current_scene.add_child(pulse)
		pulse.global_position = pos
		
		var scale_factor = max_range / 160.0
		pulse.scale = Vector2(scale_factor, scale_factor)
		
		create_cleanup_timer(pulse, 3.0)

func process_emp_target_for_sync(target: Node, pos: Vector2) -> Dictionary:
	if not target is Node2D:
		return {}
	
	var distance = target.global_position.distance_to(pos)
	var tile_size = 32
	
	var severity = 0
	var duration = 0.0
	
	if distance <= devastate_range * tile_size:
		severity = 1
		duration = devastate_duration
	elif distance <= heavy_range * tile_size:
		severity = 2
		duration = heavy_duration
	elif distance <= light_range * tile_size:
		severity = 3
		duration = light_duration
	elif distance <= weak_range * tile_size:
		severity = 4
		duration = weak_duration
	
	if severity > 0:
		var device_type = "generic"
		if "device_type" in target:
			device_type = target.device_type
		
		return {
			"target_id": get_entity_id(target),
			"severity": severity,
			"duration": duration,
			"device_type": device_type,
			"uses_power": target.get("uses_power")
		}
	
	return {}

func apply_emp_effects_local(targets_data: Array) -> void:
	for target_data in targets_data:
		var target_id = target_data.get("target_id", "")
		var severity = target_data.get("severity", 0)
		var duration = target_data.get("duration", 0.0)
		var device_type = target_data.get("device_type", "generic")
		
		apply_target_emp_effect_local(target_id, severity, duration, device_type)

func apply_target_emp_effect_local(target_id: String, severity: int, duration: float, device_type: String) -> void:
	var target = find_entity_by_id(target_id)
	if not target:
		return
	
	if target.has_method("emp_act"):
		target.emp_act(severity)
	
	apply_power_effects_local(target, duration)
	apply_device_specific_effects_local(target, severity, duration, device_type)
	apply_component_effects_local(target, severity)
	create_emp_visual_effect_local(target)

func apply_power_effects_local(target: Node, duration: float) -> void:
	if "uses_power" in target and target.uses_power:
		if target.has_method("power_failure"):
			target.power_failure(duration)

func apply_device_specific_effects_local(target: Node, severity: int, duration: float, device_type: String) -> void:
	match device_type:
		"camera":
			if target.has_method("emp_disable"):
				target.emp_disable(duration)
		"door":
			apply_door_emp_effects_local(target)
		"turret":
			apply_turret_emp_effects_local(target, duration)
		"robot":
			apply_robot_emp_effects_local(target, severity, duration)
		"computer":
			apply_computer_emp_effects_local(target, severity, duration)

func apply_door_emp_effects_local(target: Node) -> void:
	if target.has_method("emp_effect"):
		target.emp_effect()
	elif target.has_method("open") and randf() < 0.7:
		target.open()

func apply_turret_emp_effects_local(target: Node, duration: float) -> void:
	if target.has_method("emp_disable"):
		target.emp_disable(duration)
	elif target.has_method("toggle_active"):
		target.toggle_active(false)

func apply_robot_emp_effects_local(target: Node, severity: int, duration: float) -> void:
	if target.has_method("emp_act"):
		target.emp_act(severity)
	elif target.has_method("stunned"):
		target.stunned(duration)

func apply_computer_emp_effects_local(target: Node, severity: int, duration: float) -> void:
	if target.has_method("emp_act"):
		target.emp_act(severity)
	elif target.has_method("shutdown"):
		var shutdown_duration = duration * (1.0 - (severity * 0.2))
		target.shutdown(shutdown_duration)

func apply_component_effects_local(target: Node, severity: int) -> void:
	if target.has_node("PowerSystem"):
		var power_system = target.get_node("PowerSystem")
		if power_system.has_method("emp_act"):
			power_system.emp_act(severity)
	
	if target.has_node("ElectronicSystem"):
		var electronic_system = target.get_node("ElectronicSystem")
		if electronic_system.has_method("emp_act"):
			electronic_system.emp_act(severity)

func create_emp_visual_effect_local(target: Node) -> void:
	if target.has_node("EMPEffect"):
		return
	
	var emp_effect = Sprite2D.new()
	emp_effect.name = "EMPEffect"
	
	var texture = load("res://Assets/Effects/Particles/EMP.png")
	if texture:
		emp_effect.texture = texture
	else:
		emp_effect.scale = Vector2(0.5, 0.5)
		emp_effect.modulate = Color(0.4, 0.6, 1.0, 0.7)
	
	target.add_child(emp_effect)
	
	var tween = target.create_tween()
	tween.tween_property(emp_effect, "modulate:a", 0.0, 1.0)
	tween.tween_callback(emp_effect.queue_free)

func create_camera_shake_local(intensity: float):
	create_camera_shake(intensity)

# Helper functions
func get_entity_id(entity: Node) -> String:
	if not entity:
		return ""
	
	if entity.has_method("get_network_id"):
		return entity.get_network_id()
	elif "peer_id" in entity:
		return "player_" + str(entity.peer_id)
	elif entity.has_meta("network_id"):
		return entity.get_meta("network_id")
	else:
		return entity.get_path()

func find_entity_by_id(entity_id: String) -> Node:
	if entity_id == "":
		return null
	
	if entity_id.begins_with("player_"):
		var peer_id_str = entity_id.split("_")[1]
		var peer_id_val = peer_id_str.to_int()
		return find_player_by_peer_id(peer_id_val)
	
	if entity_id.begins_with("/"):
		return get_node_or_null(entity_id)
	
	var entities = get_tree().get_nodes_in_group("networkable")
	for entity in entities:
		if entity.has_meta("network_id") and entity.get_meta("network_id") == entity_id:
			return entity
		if entity.has_method("get_network_id") and entity.get_network_id() == entity_id:
			return entity
	
	return null

func find_player_by_peer_id(peer_id_val: int) -> Node:
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player.has_meta("peer_id") and player.get_meta("peer_id") == peer_id_val:
			return player
		if "peer_id" in player and player.peer_id == peer_id_val:
			return player
	return null

func create_cleanup_timer(node: Node, duration: float):
	var timer = Timer.new()
	timer.wait_time = duration
	timer.one_shot = true
	timer.timeout.connect(func(): 
		if is_instance_valid(node):
			node.queue_free()
	)
	node.add_child(timer)
	timer.start()

func play_cached_sound(sound: AudioStream, volume: float = 0.0):
	if not sound:
		return
	
	var audio_player = AudioStreamPlayer2D.new()
	audio_player.stream = sound
	audio_player.volume_db = volume
	audio_player.autoplay = true
	audio_player.finished.connect(audio_player.queue_free)
	get_tree().current_scene.add_child(audio_player)
	audio_player.global_position = global_position

func create_camera_shake(intensity: float = 1.0):
	var camera = get_viewport().get_camera_2d()
	if not camera:
		return
	
	var shake_tween = create_tween()
	var original_pos = camera.global_position
	
	for i in range(8):
		var shake_offset = Vector2(
			randf_range(-intensity * 10, intensity * 10),
			randf_range(-intensity * 10, intensity * 10)
		)
		shake_tween.tween_property(camera, "global_position", original_pos + shake_offset, 0.05)
	
	shake_tween.tween_property(camera, "global_position", original_pos, 0.1)

func serialize() -> Dictionary:
	var data = super.serialize()
	
	data["devastate_range"] = devastate_range
	data["heavy_range"] = heavy_range
	data["light_range"] = light_range
	data["weak_range"] = weak_range
	data["devastate_duration"] = devastate_duration
	data["heavy_duration"] = heavy_duration
	data["light_duration"] = light_duration
	data["weak_duration"] = weak_duration
	data["emp_pending"] = emp_pending
	
	return data

func deserialize(data: Dictionary):
	super.deserialize(data)
	
	if "devastate_range" in data: devastate_range = data.devastate_range
	if "heavy_range" in data: heavy_range = data.heavy_range
	if "light_range" in data: light_range = data.light_range
	if "weak_range" in data: weak_range = data.weak_range
	if "devastate_duration" in data: devastate_duration = data.devastate_duration
	if "heavy_duration" in data: heavy_duration = data.heavy_duration
	if "light_duration" in data: light_duration = data.light_duration
	if "weak_duration" in data: weak_duration = data.weak_duration
	if "emp_pending" in data: emp_pending = data.emp_pending
