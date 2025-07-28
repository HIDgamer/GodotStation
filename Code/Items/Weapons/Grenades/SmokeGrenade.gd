extends Grenade
class_name SmokeGrenade

@export_group("Smoke Properties")
@export var smoke_type: String = "normal"
@export var smoke_color: Color = Color(0.7, 0.7, 0.7, 0.8)

@export_group("Performance Settings")
@export var max_particles: int = 40
@export var particle_lifetime: float = 3.0
@export var emission_radius_multiplier: float = 1.0

@export_group("Effect Settings")
@export var vision_modifier: float = 0.5
@export var effect_update_interval: float = 1.0

# Multiplayer integration with InventorySystem
var inventory_sync_enabled: bool = true
var smoke_pending: bool = false

# Active smoke area for cleanup
var active_smoke_area: Area2D = null
var entities_in_smoke: Array = []

# Preloaded resources
static var smoke_particle_scene: PackedScene

# Smoke type configurations
var smoke_effects = {
	"normal": {
		"vision_modifier": 0.5,
		"duration": 9.0,
		"color": Color(0.7, 0.7, 0.7, 0.8)
	},
	"cloak": {
		"vision_modifier": 0.3,
		"duration": 11.0,
		"cloaking": true,
		"color": Color(0.2, 0.3, 0.25, 0.9)
	},
	"acid": {
		"vision_modifier": 0.5,
		"duration": 9.0,
		"acid_damage": 5,
		"color": Color(0.7, 0.9, 0.2, 0.8)
	}
}

func _init():
	super._init()
	obj_name = "M40 HSDP smoke grenade"
	obj_desc = "The M40 HSDP is a small, but powerful smoke grenade. Based off the same platform as the M40 HEDP. It is set to detonate in 2 seconds."
	grenade_type = GrenadeType.SMOKE
	det_time = 2.0
	dangerous = false
	
	if not smoke_particle_scene:
		smoke_particle_scene = preload("res://Scenes/Effects/Smoke.tscn")
	
	_update_smoke_properties()

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
		sync_grenade_equipped_state.rpc(active, smoke_pending, get_item_network_id(self))

func unequipped(user, slot: int):
	super.unequipped(user, slot)
	visible = true
	
	if inventory_sync_enabled and multiplayer.has_multiplayer_peer():
		sync_grenade_unequipped_state.rpc(active, smoke_pending, get_item_network_id(self))

func picked_up(user):
	super.picked_up(user)
	
	if get_parent() != user:
		if get_parent():
			get_parent().remove_child(self)
		user.add_child(self)
	
	position = Vector2.ZERO
	visible = false
	
	if inventory_sync_enabled and multiplayer.has_multiplayer_peer():
		sync_grenade_pickup_state.rpc(active, smoke_pending, det_time, get_item_network_id(self))

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
		sync_grenade_drop_state.rpc(active, smoke_pending, global_position, get_item_network_id(self))

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
		sync_grenade_throw_state.rpc(active, smoke_pending, global_position, get_item_network_id(self))
	
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
func sync_grenade_equipped_state(is_active: bool, pending_smoke: bool, item_id: String):
	active = is_active
	smoke_pending = pending_smoke
	
	var user = find_item_owner(item_id)
	if user and get_parent() != user:
		if get_parent():
			get_parent().remove_child(self)
		user.add_child(self)
		position = Vector2.ZERO
		visible = false

@rpc("any_peer", "call_local", "reliable")
func sync_grenade_unequipped_state(is_active: bool, pending_smoke: bool, item_id: String):
	active = is_active
	smoke_pending = pending_smoke
	visible = true

@rpc("any_peer", "call_local", "reliable")
func sync_grenade_pickup_state(is_active: bool, pending_smoke: bool, current_det_time: float, item_id: String):
	active = is_active
	smoke_pending = pending_smoke
	det_time = current_det_time
	
	var user = find_item_owner(item_id)
	if user and get_parent() != user:
		if get_parent():
			get_parent().remove_child(self)
		user.add_child(self)
		position = Vector2.ZERO
		visible = false

@rpc("any_peer", "call_local", "reliable")
func sync_grenade_drop_state(is_active: bool, pending_smoke: bool, drop_pos: Vector2, item_id: String):
	active = is_active
	smoke_pending = pending_smoke
	global_position = drop_pos
	visible = true
	
	var world = get_tree().current_scene
	if get_parent() != world:
		if get_parent():
			get_parent().remove_child(self)
		world.add_child(self)

@rpc("any_peer", "call_local", "reliable")
func sync_grenade_throw_state(is_active: bool, pending_smoke: bool, throw_pos: Vector2, item_id: String):
	active = is_active
	smoke_pending = pending_smoke
	global_position = throw_pos
	visible = true
	
	var world = get_tree().current_scene
	if get_parent() != world:
		if get_parent():
			get_parent().remove_child(self)
		world.add_child(self)

@rpc("any_peer", "call_local", "reliable")
func sync_smoke_deployment(deployment_pos: Vector2, smoke_data: Dictionary):
	execute_smoke_deployment_local(deployment_pos, smoke_data)

@rpc("any_peer", "call_local", "reliable")
func sync_smoke_effect(pos: Vector2, effect_data: Dictionary):
	create_smoke_effect_local(pos, effect_data)

@rpc("any_peer", "call_local", "reliable")
func sync_entity_smoke_interaction(entity_id: String, interaction_type: String):
	handle_entity_smoke_interaction_local(entity_id, interaction_type)

@rpc("any_peer", "call_local", "reliable")
func sync_war_crime_record(user_id: String):
	record_war_crime_for_user(user_id)
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

func _update_smoke_properties():
	var current_type = smoke_effects.get(smoke_type, smoke_effects["normal"])
	smoke_color = current_type.get("color", Color(0.7, 0.7, 0.7, 0.8))
	smoke_duration = current_type.get("duration", 9.0)
	vision_modifier = current_type.get("vision_modifier", 0.5)

func explode() -> void:
	if not active:
		return
	
	var explosion_pos = global_position
	smoke_pending = true
	
	super.explode()
	
	var smoke_data = {
		"smoke_type": smoke_type,
		"smoke_color": {"r": smoke_color.r, "g": smoke_color.g, "b": smoke_color.b, "a": smoke_color.a},
		"smoke_radius": smoke_radius,
		"smoke_duration": smoke_duration,
		"vision_modifier": vision_modifier,
		"max_particles": max_particles,
		"particle_lifetime": particle_lifetime
	}
	
	if multiplayer.has_multiplayer_peer():
		sync_smoke_deployment.rpc(explosion_pos, smoke_data)
	else:
		execute_smoke_deployment_local(explosion_pos, smoke_data)

func execute_smoke_deployment_local(explosion_pos: Vector2, smoke_data: Dictionary):
	smoke_type = smoke_data.get("smoke_type", smoke_type)
	if "smoke_color" in smoke_data:
		var color_data = smoke_data.smoke_color
		smoke_color = Color(color_data.r, color_data.g, color_data.b, color_data.a)
	smoke_radius = smoke_data.get("smoke_radius", smoke_radius)
	smoke_duration = smoke_data.get("smoke_duration", smoke_duration)
	vision_modifier = smoke_data.get("vision_modifier", vision_modifier)
	max_particles = smoke_data.get("max_particles", max_particles)
	particle_lifetime = smoke_data.get("particle_lifetime", particle_lifetime)
	
	var effect_data = {
		"max_particles": max_particles,
		"particle_lifetime": particle_lifetime,
		"color": smoke_color
	}
	create_smoke_effect_local(explosion_pos, effect_data)
	
	create_smoke_area(explosion_pos)
	smoke_pending = false
	_destroy_item_local()

func create_smoke_effect_local(pos: Vector2, effect_data: Dictionary) -> void:
	if not smoke_particle_scene:
		return
	
	var smoke = smoke_particle_scene.instantiate()
	if smoke:
		get_tree().current_scene.add_child(smoke)
		smoke.global_position = pos
		
		configure_smoke_particles(smoke, effect_data)
		
		if "emitting" in smoke:
			smoke.emitting = true
		
		create_cleanup_timer(smoke, smoke_duration + 2.0)
	
	var activation_sound = load("res://Sound/effects/thud.ogg")
	play_cached_sound(activation_sound)

func configure_smoke_particles(smoke: Node, effect_data: Dictionary) -> void:
	if "process_material" in smoke and smoke.process_material:
		if "color" in smoke.process_material:
			smoke.process_material.color = effect_data.get("color", smoke_color)
		if "emission_sphere_radius" in smoke.process_material:
			smoke.process_material.emission_sphere_radius = smoke_radius * 16 * emission_radius_multiplier
	
	if "lifetime" in smoke:
		smoke.lifetime = effect_data.get("particle_lifetime", particle_lifetime)
	
	if "amount" in smoke:
		smoke.amount = effect_data.get("max_particles", max_particles)

func create_smoke_area(pos: Vector2) -> void:
	var current_type = smoke_effects.get(smoke_type, smoke_effects["normal"])
	var effect_duration = current_type.get("duration", 9.0)
	
	active_smoke_area = Area2D.new()
	active_smoke_area.name = "SmokeArea_" + smoke_type
	get_tree().current_scene.add_child(active_smoke_area)
	active_smoke_area.global_position = pos
	
	var collision = CollisionShape2D.new()
	var circle_shape = CircleShape2D.new()
	circle_shape.radius = smoke_radius * 32
	collision.shape = circle_shape
	active_smoke_area.add_child(collision)
	
	active_smoke_area.connect("body_entered", _on_smoke_entered)
	active_smoke_area.connect("body_exited", _on_smoke_exited)
	
	var effect_timer = Timer.new()
	effect_timer.wait_time = effect_update_interval
	effect_timer.autostart = true
	active_smoke_area.add_child(effect_timer)
	effect_timer.connect("timeout", apply_periodic_effects)
	
	var duration_timer = Timer.new()
	duration_timer.wait_time = effect_duration
	duration_timer.one_shot = true
	duration_timer.autostart = true
	active_smoke_area.add_child(duration_timer)
	duration_timer.connect("timeout", cleanup_smoke_area)

func _on_smoke_entered(body: Node) -> void:
	if body.is_in_group("entities") and not body in entities_in_smoke:
		entities_in_smoke.append(body)
		
		if multiplayer.has_multiplayer_peer():
			sync_entity_smoke_interaction.rpc(get_entity_id(body), "entered")
		else:
			handle_entity_smoke_interaction_local(get_entity_id(body), "entered")

func _on_smoke_exited(body: Node) -> void:
	if body in entities_in_smoke:
		entities_in_smoke.erase(body)
		
		if multiplayer.has_multiplayer_peer():
			sync_entity_smoke_interaction.rpc(get_entity_id(body), "exited")
		else:
			handle_entity_smoke_interaction_local(get_entity_id(body), "exited")

func handle_entity_smoke_interaction_local(entity_id: String, interaction_type: String):
	var entity = find_entity_by_id(entity_id)
	if not entity:
		return
	
	match interaction_type:
		"entered":
			apply_entry_effects_local(entity)
		"exited":
			clear_entity_effects_local(entity)

func apply_entry_effects_local(entity: Node) -> void:
	var current_type = smoke_effects.get(smoke_type, smoke_effects["normal"])
	
	if "acid_damage" in current_type and entity.has_method("apply_acid"):
		entity.apply_acid(current_type["acid_damage"] * 2)
	
	if "effects" in current_type:
		for effect_name in current_type["effects"]:
			if entity.has_method("apply_effects"):
				var effect_strength = current_type["effects"][effect_name]
				entity.apply_effects(effect_name, effect_strength)

func apply_periodic_effects() -> void:
	entities_in_smoke = entities_in_smoke.filter(func(entity): return is_instance_valid(entity))
	
	var current_type = smoke_effects.get(smoke_type, smoke_effects["normal"])
	
	for entity in entities_in_smoke:
		apply_periodic_effects_local(entity, current_type)

func apply_periodic_effects_local(entity: Node, current_type: Dictionary):
	if entity.has_method("add_vision_modifier"):
		var duration = effect_update_interval + 0.5
		entity.add_vision_modifier("smoke", vision_modifier, duration)
	
	if current_type.get("cloaking", false) and entity.has_method("add_effect"):
		var duration = effect_update_interval + 0.5
		entity.add_effect("cloaked", duration)
	
	if "acid_damage" in current_type and entity.has_method("apply_acid"):
		entity.apply_acid(current_type["acid_damage"])

func clear_entity_effects_local(entity: Node) -> void:
	if not is_instance_valid(entity):
		return
	
	if entity.has_method("remove_vision_modifier"):
		entity.remove_vision_modifier("smoke")
	
	var current_type = smoke_effects.get(smoke_type, smoke_effects["normal"])
	if current_type.get("cloaking", false) and entity.has_method("remove_effect"):
		entity.remove_effect("cloaked")

func cleanup_smoke_area() -> void:
	for entity in entities_in_smoke:
		if is_instance_valid(entity):
			clear_entity_effects_local(entity)
	
	entities_in_smoke.clear()
	
	if active_smoke_area and is_instance_valid(active_smoke_area):
		var tween = active_smoke_area.create_tween()
		var collision = active_smoke_area.get_node("CollisionShape2D")
		if collision:
			tween.tween_property(collision, "scale", Vector2.ZERO, 1.0)
		tween.tween_callback(func(): 
			if is_instance_valid(active_smoke_area):
				active_smoke_area.queue_free()
		)
	
	active_smoke_area = null

func throw_impact(hit_atom, speed: float = 5) -> bool:
	var result = super.throw_impact(hit_atom, speed)
	
	if smoke_type in ["acid", "neuro", "satrapine"] and inventory_owner:
		var user_id = get_entity_id(inventory_owner)
		
		if multiplayer.has_multiplayer_peer():
			sync_war_crime_record.rpc(user_id)
		else:
			record_war_crime_for_user(user_id)
	
	return result

func activate(user = null) -> bool:
	var result = super.activate(user)
	
	if result and smoke_type in ["acid", "neuro", "satrapine"] and user:
		var user_id = get_entity_id(user)
		
		if multiplayer.has_multiplayer_peer():
			sync_war_crime_record.rpc(user_id)
		else:
			record_war_crime_for_user(user_id)
	
	return result

func record_war_crime_for_user(user_id: String):
	var user = find_entity_by_id(user_id)
	if user and user.has_method("record_war_crime"):
		user.record_war_crime()

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

func serialize() -> Dictionary:
	var data = super.serialize()
	data["smoke_type"] = smoke_type
	data["smoke_radius"] = smoke_radius
	data["smoke_duration"] = smoke_duration
	data["max_particles"] = max_particles
	data["smoke_pending"] = smoke_pending
	return data

func deserialize(data: Dictionary):
	super.deserialize(data)
	
	if "smoke_type" in data: 
		smoke_type = data.smoke_type
		_update_smoke_properties()
	if "smoke_radius" in data: smoke_radius = data.smoke_radius
	if "smoke_duration" in data: smoke_duration = data.smoke_duration
	if "max_particles" in data: max_particles = data.max_particles
	if "smoke_pending" in data: smoke_pending = data.smoke_pending

func _exit_tree():
	if active_smoke_area and is_instance_valid(active_smoke_area):
		active_smoke_area.queue_free()
		active_smoke_area = null
