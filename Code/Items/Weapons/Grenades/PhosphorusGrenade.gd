extends Grenade
class_name PhosphorusGrenade

@export_group("Phosphorus Properties")
@export var fire_radius: int = 4
@export var inner_fire_radius: int = 1
@export var burn_intensity: int = 75
@export var burn_duration: float = 45.0
@export var burn_damage: float = 15.0
@export var fire_stacks: int = 75

@export_group("Smoke Properties")
@export var smoke_damage_interval: float = 1.0
@export var smoke_damage_per_tick: float = 3.0

@export_group("Performance Settings")
@export var max_fire_particles: int = 80
@export var max_smoke_particles: int = 120
@export var max_fire_tiles: int = 25
@export var effect_cleanup_delay: float = 2.0

@export_group("Visual Settings")
@export var phosphorus_color: Color = Color(1.0, 1.0, 1.0, 0.9)
@export var smoke_color: Color = Color(0.9, 0.9, 0.9, 0.9)
@export var camera_shake_intensity: float = 1.0

# Multiplayer integration with InventorySystem
var inventory_sync_enabled: bool = true
var phosphorus_pending: bool = false

# Active effects for cleanup
var active_fires: Array = []
var active_smoke_area: Area2D = null
var entities_in_smoke: Array = []

# Preloaded resources
static var fire_particle_scene: PackedScene
static var smoke_particle_scene: PackedScene
static var fire_area_scene: PackedScene

func _init():
	super._init()
	obj_name = "M40 HPDP grenade"
	obj_desc = "The M40 HPDP is a small, but powerful phosphorus grenade. It is set to detonate in 2 seconds."
	grenade_type = GrenadeType.PHOSPHORUS
	det_time = 2.0
	dangerous = true
	
	if not fire_particle_scene:
		fire_particle_scene = preload("res://Scenes/Effects/Fire.tscn")
	if not smoke_particle_scene:
		smoke_particle_scene = preload("res://Scenes/Effects/Smoke.tscn")
	if not fire_area_scene:
		fire_area_scene = preload("res://Scenes/Effects/Fire_tile.tscn")

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
		sync_grenade_equipped_state.rpc(active, phosphorus_pending, get_item_network_id(self))

func unequipped(user, slot: int):
	super.unequipped(user, slot)
	visible = true
	
	if inventory_sync_enabled and multiplayer.has_multiplayer_peer():
		sync_grenade_unequipped_state.rpc(active, phosphorus_pending, get_item_network_id(self))

func picked_up(user):
	super.picked_up(user)
	
	if get_parent() != user:
		if get_parent():
			get_parent().remove_child(self)
		user.add_child(self)
	
	position = Vector2.ZERO
	visible = false
	
	if inventory_sync_enabled and multiplayer.has_multiplayer_peer():
		sync_grenade_pickup_state.rpc(active, phosphorus_pending, det_time, get_item_network_id(self))

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
		sync_grenade_drop_state.rpc(active, phosphorus_pending, global_position, get_item_network_id(self))

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
		sync_grenade_throw_state.rpc(active, phosphorus_pending, global_position, get_item_network_id(self))
	
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
func sync_grenade_equipped_state(is_active: bool, pending_phosphorus: bool, item_id: String):
	active = is_active
	phosphorus_pending = pending_phosphorus
	
	var user = find_item_owner(item_id)
	if user and get_parent() != user:
		if get_parent():
			get_parent().remove_child(self)
		user.add_child(self)
		position = Vector2.ZERO
		visible = false

@rpc("any_peer", "call_local", "reliable")
func sync_grenade_unequipped_state(is_active: bool, pending_phosphorus: bool, item_id: String):
	active = is_active
	phosphorus_pending = pending_phosphorus
	visible = true

@rpc("any_peer", "call_local", "reliable")
func sync_grenade_pickup_state(is_active: bool, pending_phosphorus: bool, current_det_time: float, item_id: String):
	active = is_active
	phosphorus_pending = pending_phosphorus
	det_time = current_det_time
	
	var user = find_item_owner(item_id)
	if user and get_parent() != user:
		if get_parent():
			get_parent().remove_child(self)
		user.add_child(self)
		position = Vector2.ZERO
		visible = false

@rpc("any_peer", "call_local", "reliable")
func sync_grenade_drop_state(is_active: bool, pending_phosphorus: bool, drop_pos: Vector2, item_id: String):
	active = is_active
	phosphorus_pending = pending_phosphorus
	global_position = drop_pos
	visible = true
	
	var world = get_tree().current_scene
	if get_parent() != world:
		if get_parent():
			get_parent().remove_child(self)
		world.add_child(self)

@rpc("any_peer", "call_local", "reliable")
func sync_grenade_throw_state(is_active: bool, pending_phosphorus: bool, throw_pos: Vector2, item_id: String):
	active = is_active
	phosphorus_pending = pending_phosphorus
	global_position = throw_pos
	visible = true
	
	var world = get_tree().current_scene
	if get_parent() != world:
		if get_parent():
			get_parent().remove_child(self)
		world.add_child(self)

@rpc("any_peer", "call_local", "reliable")
func sync_phosphorus_explosion(explosion_pos: Vector2, phosphorus_data: Dictionary):
	execute_phosphorus_explosion_local(explosion_pos, phosphorus_data)

@rpc("any_peer", "call_local", "reliable")
func sync_phosphorus_effects(effects_data: Dictionary):
	apply_phosphorus_effects_local(effects_data)

@rpc("any_peer", "call_local", "reliable")
func sync_fire_tile_creation(fire_tiles_data: Array):
	create_fire_tiles_local(fire_tiles_data)

@rpc("any_peer", "call_local", "reliable")
func sync_smoke_hazard_creation(pos: Vector2, smoke_data: Dictionary):
	create_smoke_hazard_local(pos, smoke_data)

@rpc("any_peer", "call_local", "reliable")
func sync_entity_smoke_interaction(entity_id: String, interaction_type: String):
	handle_entity_smoke_interaction_local(entity_id, interaction_type)

@rpc("any_peer", "call_local", "reliable")
func sync_entity_damage(entity_id: String, damage: float, damage_type: String):
	apply_entity_damage_local(entity_id, damage, damage_type)

@rpc("any_peer", "call_local", "reliable")
func sync_visual_effects(pos: Vector2, effect_type: String, effect_data: Dictionary):
	create_visual_effect_local(pos, effect_type, effect_data)

@rpc("any_peer", "call_local", "reliable")
func sync_camera_shake(intensity: float):
	create_camera_shake_local(intensity)

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

func explode() -> void:
	if not active:
		return
	
	var explosion_pos = global_position
	phosphorus_pending = true
	
	super.explode()
	
	var phosphorus_data = {
		"fire_radius": fire_radius,
		"inner_fire_radius": inner_fire_radius,
		"burn_intensity": burn_intensity,
		"burn_duration": burn_duration,
		"burn_damage": burn_damage,
		"fire_stacks": fire_stacks,
		"smoke_damage_interval": smoke_damage_interval,
		"smoke_damage_per_tick": smoke_damage_per_tick,
		"max_fire_particles": max_fire_particles,
		"max_smoke_particles": max_smoke_particles,
		"max_fire_tiles": max_fire_tiles,
		"phosphorus_color": {"r": phosphorus_color.r, "g": phosphorus_color.g, "b": phosphorus_color.b, "a": phosphorus_color.a},
		"smoke_color": {"r": smoke_color.r, "g": smoke_color.g, "b": smoke_color.b, "a": smoke_color.a},
		"camera_shake_intensity": camera_shake_intensity
	}
	
	if multiplayer.has_multiplayer_peer():
		sync_phosphorus_explosion.rpc(explosion_pos, phosphorus_data)
	else:
		execute_phosphorus_explosion_local(explosion_pos, phosphorus_data)

func execute_phosphorus_explosion_local(explosion_pos: Vector2, phosphorus_data: Dictionary):
	fire_radius = phosphorus_data.get("fire_radius", fire_radius)
	inner_fire_radius = phosphorus_data.get("inner_fire_radius", inner_fire_radius)
	burn_intensity = phosphorus_data.get("burn_intensity", burn_intensity)
	burn_duration = phosphorus_data.get("burn_duration", burn_duration)
	burn_damage = phosphorus_data.get("burn_damage", burn_damage)
	fire_stacks = phosphorus_data.get("fire_stacks", fire_stacks)
	smoke_damage_interval = phosphorus_data.get("smoke_damage_interval", smoke_damage_interval)
	smoke_damage_per_tick = phosphorus_data.get("smoke_damage_per_tick", smoke_damage_per_tick)
	max_fire_particles = phosphorus_data.get("max_fire_particles", max_fire_particles)
	max_smoke_particles = phosphorus_data.get("max_smoke_particles", max_smoke_particles)
	max_fire_tiles = phosphorus_data.get("max_fire_tiles", max_fire_tiles)
	camera_shake_intensity = phosphorus_data.get("camera_shake_intensity", camera_shake_intensity)
	
	if "phosphorus_color" in phosphorus_data:
		var color_data = phosphorus_data.phosphorus_color
		phosphorus_color = Color(color_data.r, color_data.g, color_data.b, color_data.a)
	
	if "smoke_color" in phosphorus_data:
		var color_data = phosphorus_data.smoke_color
		smoke_color = Color(color_data.r, color_data.g, color_data.b, color_data.a)
	
	create_phosphorus_effect_local(explosion_pos)
	apply_phosphorus_effects(explosion_pos)
	create_camera_shake_local(camera_shake_intensity)
	
	phosphorus_pending = false
	_destroy_item_local()

func create_phosphorus_effect_local(pos: Vector2) -> void:
	var explosion_sound = load("res://Sound/Explosions/explosion.wav")
	play_cached_sound(explosion_sound)
	
	var smoke_effect_data = {
		"max_particles": max_smoke_particles,
		"color": smoke_color
	}
	create_visual_effect_local(pos, "smoke", smoke_effect_data)
	
	var fire_effect_data = {
		"max_particles": max_fire_particles,
		"color": phosphorus_color
	}
	create_visual_effect_local(pos, "fire", fire_effect_data)

func create_visual_effect_local(pos: Vector2, effect_type: String, effect_data: Dictionary):
	match effect_type:
		"smoke":
			create_phosphorus_smoke_local(pos, effect_data)
		"fire":
			create_phosphorus_fire_local(pos, effect_data)

func create_phosphorus_smoke_local(pos: Vector2, effect_data: Dictionary) -> void:
	if not smoke_particle_scene:
		return
	
	var smoke = smoke_particle_scene.instantiate()
	if smoke:
		get_tree().current_scene.add_child(smoke)
		smoke.global_position = pos
		
		configure_phosphorus_smoke_local(smoke, effect_data)
		
		if "emitting" in smoke:
			smoke.emitting = true
		
		create_cleanup_timer(smoke, smoke_duration + effect_cleanup_delay)

func configure_phosphorus_smoke_local(smoke: Node, effect_data: Dictionary) -> void:
	var max_particles = effect_data.get("max_particles", max_smoke_particles)
	var color = effect_data.get("color", smoke_color)
	
	if "amount" in smoke:
		smoke.amount = max_particles
	
	if "lifetime" in smoke:
		smoke.lifetime = smoke_duration * 0.8
	
	if "process_material" in smoke and smoke.process_material:
		if "color" in smoke.process_material:
			smoke.process_material.color = color
		if "emission_sphere_radius" in smoke.process_material:
			smoke.process_material.emission_sphere_radius = smoke_radius * 16

func create_phosphorus_fire_local(pos: Vector2, effect_data: Dictionary) -> void:
	if not fire_particle_scene:
		return
	
	var phosphorus_fire = fire_particle_scene.instantiate()
	if phosphorus_fire:
		get_tree().current_scene.add_child(phosphorus_fire)
		phosphorus_fire.global_position = pos
		
		configure_phosphorus_fire_local(phosphorus_fire, effect_data)
		create_cleanup_timer(phosphorus_fire, 3.0)

func configure_phosphorus_fire_local(fire: Node, effect_data: Dictionary) -> void:
	var max_particles = effect_data.get("max_particles", max_fire_particles)
	var color = effect_data.get("color", phosphorus_color)
	
	fire.modulate = color
	
	if "amount" in fire:
		fire.amount = max_particles
	
	if "emitting" in fire:
		fire.emitting = true
	
	if "lifetime" in fire:
		fire.lifetime = 2.5

func create_camera_shake_local(intensity: float):
	create_camera_shake(intensity)

func apply_phosphorus_effects(pos: Vector2) -> void:
	ignite_phosphorus_area(pos)
	create_smoke_hazard(pos)
	apply_immediate_phosphorus_damage(pos)

func ignite_phosphorus_area(pos: Vector2) -> void:
	var tile_size = 32
	var center_tile = Vector2i(int(pos.x / tile_size), int(pos.y / tile_size))
	
	var fire_tiles = get_fire_tiles(center_tile, fire_radius)
	
	if fire_tiles.size() > max_fire_tiles:
		fire_tiles.shuffle()
		fire_tiles = fire_tiles.slice(0, max_fire_tiles)
	
	print_debug("Creating ", fire_tiles.size(), " phosphorus fire tiles")
	
	var fire_tiles_data = []
	for tile_pos in fire_tiles:
		var pixel_pos = Vector2(tile_pos.x * tile_size + tile_size/2, tile_pos.y * tile_size + tile_size/2)
		var distance = pixel_pos.distance_to(pos)
		var in_inner_radius = distance <= inner_fire_radius * 32
		
		fire_tiles_data.append({
			"pixel_pos": pixel_pos,
			"explosion_center": pos,
			"in_inner_radius": in_inner_radius,
			"burn_damage": burn_damage,
			"fire_stacks": fire_stacks,
			"burn_duration": burn_duration,
			"burn_intensity": burn_intensity,
			"phosphorus_color": {"r": phosphorus_color.r, "g": phosphorus_color.g, "b": phosphorus_color.b, "a": phosphorus_color.a}
		})
	
	# FIXED: Always sync fire tile creation to ALL clients (including host)
	if multiplayer.has_multiplayer_peer():
		sync_fire_tile_creation.rpc(fire_tiles_data)
	# ALWAYS create locally too (this was the bug - host wasn't creating fire tiles)
	create_fire_tiles_local(fire_tiles_data)

func get_fire_tiles(center_tile: Vector2i, radius: int) -> Array:
	var tiles = []
	
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			if x*x + y*y <= radius*radius:
				tiles.append(Vector2i(center_tile.x + x, center_tile.y + y))
	
	return tiles

func create_fire_tiles_local(fire_tiles_data: Array) -> void:
	for i in range(fire_tiles_data.size()):
		var tile_data = fire_tiles_data[i]
		
		if i > 0 and i % 5 == 0:
			await get_tree().process_frame
		
		create_phosphorus_fire_tile_local(tile_data)

func create_phosphorus_fire_tile_local(tile_data: Dictionary) -> void:
	if not fire_area_scene:
		print_debug("Fire area scene not loaded!")
		return
	
	var fire = fire_area_scene.instantiate()
	if not fire:
		print_debug("Failed to instantiate phosphorus fire tile")
		return
	
	var pixel_pos = tile_data.get("pixel_pos", Vector2.ZERO)
	
	get_tree().current_scene.add_child(fire)
	fire.global_position = pixel_pos
	
	print_debug("Created phosphorus fire tile at ", pixel_pos)
	
	configure_phosphorus_fire_tile_local(fire, tile_data)
	
	active_fires.append(fire)
	
	var duration = tile_data.get("burn_duration", burn_duration)
	create_cleanup_timer(fire, duration)

func configure_phosphorus_fire_tile_local(fire: Node, tile_data: Dictionary) -> void:
	var in_inner_radius = tile_data.get("in_inner_radius", false)
	var burn_damage_val = tile_data.get("burn_damage", burn_damage)
	var fire_stacks_val = tile_data.get("fire_stacks", fire_stacks)
	var burn_duration_val = tile_data.get("burn_duration", burn_duration)
	var burn_intensity_val = tile_data.get("burn_intensity", burn_intensity)
	
	if "burn_damage" in fire:
		fire.burn_damage = burn_damage_val / 5.0
		if in_inner_radius:
			fire.burn_damage *= 1.5
	
	if "burn_stacks" in fire:
		fire.burn_stacks = fire_stacks_val
	
	if "duration" in fire:
		fire.duration = burn_duration_val
	
	if "heat" in fire:
		fire.heat = burn_intensity_val * 10
	
	if "intensity" in fire:
		fire.intensity = 1.5 if in_inner_radius else 1.0
	
	var scale_factor = 1.2 if in_inner_radius else 1.0
	fire.scale = Vector2(scale_factor, scale_factor)
	
	if "phosphorus_color" in tile_data:
		var color_data = tile_data.phosphorus_color
		var color = Color(color_data.r, color_data.g, color_data.b, color_data.a)
		fire.modulate = color
		
		for child in fire.get_children():
			if child is PointLight2D:
				child.color = color
				if in_inner_radius:
					child.energy = 1.5
			if "modulate" in child:
				child.modulate = color

func create_smoke_hazard(pos: Vector2) -> void:
	var smoke_data = {
		"smoke_radius": smoke_radius,
		"smoke_duration": smoke_duration,
		"smoke_damage_interval": smoke_damage_interval,
		"smoke_damage_per_tick": smoke_damage_per_tick
	}
	
	# FIXED: Always sync AND create locally
	if multiplayer.has_multiplayer_peer():
		sync_smoke_hazard_creation.rpc(pos, smoke_data)
	create_smoke_hazard_local(pos, smoke_data)

func create_smoke_hazard_local(pos: Vector2, smoke_data: Dictionary) -> void:
	var radius = smoke_data.get("smoke_radius", smoke_radius)
	var duration = smoke_data.get("smoke_duration", smoke_duration)
	var damage_interval = smoke_data.get("smoke_damage_interval", smoke_damage_interval)
	
	active_smoke_area = Area2D.new()
	active_smoke_area.name = "PhosphorusSmokeArea"
	get_tree().current_scene.add_child(active_smoke_area)
	active_smoke_area.global_position = pos
	
	var collision = CollisionShape2D.new()
	var circle_shape = CircleShape2D.new()
	circle_shape.radius = radius * 32
	collision.shape = circle_shape
	active_smoke_area.add_child(collision)
	
	# Only host handles smoke interactions
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		active_smoke_area.connect("body_entered", _on_smoke_entered)
		active_smoke_area.connect("body_exited", _on_smoke_exited)
		
		var damage_timer = Timer.new()
		damage_timer.wait_time = damage_interval
		damage_timer.autostart = true
		active_smoke_area.add_child(damage_timer)
		damage_timer.connect("timeout", apply_smoke_damage)
	
	var cleanup_timer = Timer.new()
	cleanup_timer.wait_time = duration
	cleanup_timer.one_shot = true
	cleanup_timer.autostart = true
	active_smoke_area.add_child(cleanup_timer)
	cleanup_timer.connect("timeout", cleanup_smoke_area)

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
			if entity.has_method("apply_chemical_effect"):
				entity.apply_chemical_effect("phosphorus_burns", 5.0)
		"exited":
			pass

func apply_smoke_damage() -> void:
	entities_in_smoke = entities_in_smoke.filter(func(entity): return is_instance_valid(entity))
	
	for entity in entities_in_smoke:
		var entity_id = get_entity_id(entity)
		
		if multiplayer.has_multiplayer_peer():
			sync_entity_damage.rpc(entity_id, smoke_damage_per_tick, "chemical")
		else:
			apply_entity_damage_local(entity_id, smoke_damage_per_tick, "chemical")

func apply_entity_damage_local(entity_id: String, damage: float, damage_type: String):
	var entity = find_entity_by_id(entity_id)
	if not entity:
		return
	
	apply_damage_to_entity(entity, damage, damage_type)
	
	if entity.has_method("apply_chemical_effect"):
		entity.apply_chemical_effect("phosphorus_burns", 3.0)

func cleanup_smoke_area() -> void:
	entities_in_smoke.clear()
	
	if active_smoke_area and is_instance_valid(active_smoke_area):
		var tween = active_smoke_area.create_tween()
		var collision = active_smoke_area.get_node("CollisionShape2D")
		if collision:
			tween.tween_property(collision, "scale", Vector2.ZERO, effect_cleanup_delay)
		tween.tween_callback(func():
			if is_instance_valid(active_smoke_area):
				active_smoke_area.queue_free()
		)
	
	active_smoke_area = null

func apply_immediate_phosphorus_damage(pos: Vector2) -> void:
	var tile_size = 32
	var max_distance = fire_radius * tile_size
	
	var entities = get_entities_in_radius(pos, max_distance)
	var effects_data = {
		"inner_effects": [],
		"outer_effects": []
	}
	
	for entity in entities:
		var distance_tiles = entity.global_position.distance_to(pos) / tile_size
		var entity_id = get_entity_id(entity)
		
		if distance_tiles <= inner_fire_radius:
			effects_data["inner_effects"].append({
				"entity_id": entity_id,
				"fire_stacks": fire_stacks * 1.5,
				"damage": burn_damage * 2.0
			})
		elif distance_tiles <= fire_radius:
			var damage_multiplier = 1.0 - (distance_tiles / fire_radius)
			effects_data["outer_effects"].append({
				"entity_id": entity_id,
				"fire_stacks": fire_stacks,
				"damage": burn_damage * damage_multiplier,
				"distance_tiles": distance_tiles
			})
	
	# FIXED: Always sync AND apply locally
	if multiplayer.has_multiplayer_peer():
		sync_phosphorus_effects.rpc(effects_data)
	apply_phosphorus_effects_local(effects_data)

func apply_phosphorus_effects_local(effects_data: Dictionary):
	for effect_data in effects_data.get("inner_effects", []):
		var entity_id = effect_data.get("entity_id", "")
		var entity = find_entity_by_id(entity_id)
		if entity:
			apply_inner_phosphorus_effects_local(entity, effect_data)
	
	for effect_data in effects_data.get("outer_effects", []):
		var entity_id = effect_data.get("entity_id", "")
		var entity = find_entity_by_id(entity_id)
		if entity:
			apply_outer_phosphorus_effects_local(entity, effect_data)

func apply_inner_phosphorus_effects_local(entity: Node, effect_data: Dictionary) -> void:
	var fire_stacks_val = effect_data.get("fire_stacks", fire_stacks * 1.5)
	var damage = effect_data.get("damage", burn_damage * 2.0)
	
	apply_fire_stacks_local(entity, fire_stacks_val)
	apply_damage_to_entity(entity, damage, "fire")
	
	if entity.has_method("apply_chemical_effect"):
		entity.apply_chemical_effect("phosphorus_burns", 10.0)

func apply_outer_phosphorus_effects_local(entity: Node, effect_data: Dictionary) -> void:
	var fire_stacks_val = effect_data.get("fire_stacks", fire_stacks)
	var damage = effect_data.get("damage", burn_damage)
	
	apply_fire_stacks_local(entity, fire_stacks_val)
	apply_damage_to_entity(entity, damage, "fire")
	
	if entity.has_method("apply_chemical_effect"):
		entity.apply_chemical_effect("phosphorus_burns", 5.0)

func apply_fire_stacks_local(entity: Node, stacks: int) -> void:
	if entity.has_method("ignite"):
		entity.ignite(stacks)
	elif entity.has_method("add_fire_stacks"):
		entity.add_fire_stacks(stacks)
	elif entity.has_method("apply_status_effect"):
		entity.apply_status_effect("burning", 10.0, stacks / 10.0)

func activate(user = null) -> bool:
	var result = super.activate(user)
	
	if result and user:
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

func cleanup_all_effects() -> void:
	for fire in active_fires:
		if is_instance_valid(fire):
			fire.queue_free()
	active_fires.clear()
	
	if active_smoke_area and is_instance_valid(active_smoke_area):
		active_smoke_area.queue_free()
		active_smoke_area = null

func _exit_tree():
	cleanup_all_effects()

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

func get_entities_in_radius(center: Vector2, radius: float) -> Array:
	var entities = []
	var all_entities = get_tree().get_nodes_in_group("entities")
	
	for entity in all_entities:
		if entity is Node2D and entity.global_position.distance_to(center) <= radius:
			entities.append(entity)
	
	return entities

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

func apply_damage_to_entity(entity: Node, damage: float, damage_type: String = "fire"):
	if entity.has_method("take_damage"):
		entity.take_damage(damage, damage_type, "grenade", true)
	elif entity.has_method("damage"):
		entity.damage(damage, damage_type)
	elif "health" in entity:
		entity.health -= damage

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
	
	data["fire_radius"] = fire_radius
	data["inner_fire_radius"] = inner_fire_radius
	data["burn_intensity"] = burn_intensity
	data["burn_duration"] = burn_duration
	data["burn_damage"] = burn_damage
	data["fire_stacks"] = fire_stacks
	data["smoke_damage_interval"] = smoke_damage_interval
	data["smoke_damage_per_tick"] = smoke_damage_per_tick
	data["max_fire_particles"] = max_fire_particles
	data["max_smoke_particles"] = max_smoke_particles
	data["max_fire_tiles"] = max_fire_tiles
	data["effect_cleanup_delay"] = effect_cleanup_delay
	data["camera_shake_intensity"] = camera_shake_intensity
	data["phosphorus_pending"] = phosphorus_pending
	
	return data

func deserialize(data: Dictionary):
	super.deserialize(data)
	
	if "fire_radius" in data: fire_radius = data.fire_radius
	if "inner_fire_radius" in data: inner_fire_radius = data.inner_fire_radius
	if "burn_intensity" in data: burn_intensity = data.burn_intensity
	if "burn_duration" in data: burn_duration = data.burn_duration
	if "burn_damage" in data: burn_damage = data.burn_damage
	if "fire_stacks" in data: fire_stacks = data.fire_stacks
	if "smoke_damage_interval" in data: smoke_damage_interval = data.smoke_damage_interval
	if "smoke_damage_per_tick" in data: smoke_damage_per_tick = data.smoke_damage_per_tick
	if "max_fire_particles" in data: max_fire_particles = data.max_fire_particles
	if "max_smoke_particles" in data: max_smoke_particles = data.max_smoke_particles
	if "max_fire_tiles" in data: max_fire_tiles = data.max_fire_tiles
	if "effect_cleanup_delay" in data: effect_cleanup_delay = data.effect_cleanup_delay
	if "camera_shake_intensity" in data: camera_shake_intensity = data.camera_shake_intensity
	if "phosphorus_pending" in data: phosphorus_pending = data.phosphorus_pending
