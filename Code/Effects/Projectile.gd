extends Node2D
class_name Projectile

signal projectile_hit(target, damage)
signal projectile_missed()

@export var damage: float = 20.0
@export var speed: float = 400.0
@export var lifetime: float = 3.0
@export var pierce_count: int = 0

@export_group("Debug Settings")
@export var debug_enabled: bool = false
@export var debug_movement: bool = false
@export var debug_collision: bool = false
@export var debug_targeting: bool = false

var target_position: Vector2
var firer_player = null
var firer_peer_id: int = -1
var source_weapon = null

var movement_direction: Vector2
var travel_distance: float = 0.0
var pierced_targets: Array = []

var direct_target_entity = null
var is_direct_target_shot: bool = false
var guaranteed_hit: bool = false

var sprite: Sprite2D
var current_z_level: int = 0

var creation_time: float = 0.0
var firer_starting_position: Vector2

var world_ref = null
var tile_occupancy_system = null
var game_manager = null

var debug_id: String = ""

func _ready():
	debug_id = "PROJ_" + str(get_instance_id())
	creation_time = Time.get_ticks_msec() / 1000.0
	
	debug_log("LIFECYCLE", "Projectile created", {
		"damage": damage,
		"speed": speed,
		"lifetime": lifetime
	})
	
	setup_visuals()
	find_systems()
	
	get_tree().create_timer(lifetime).timeout.connect(destroy_projectile.bind("lifetime_expired"))
	add_to_group("projectiles")

func setup_visuals():
	sprite = Sprite2D.new()
	sprite.name = "ProjectileSprite"
	add_child(sprite)
	
	if ResourceLoader.exists("res://Assets/Icons/Items/Guns/Particals/Bullet.png"):
		sprite.texture = preload("res://Assets/Icons/Items/Guns/Particals/Bullet.png")
	else:
		var image = Image.create(6, 12, false, Image.FORMAT_RGBA8)
		image.fill(Color.YELLOW)
		var texture = ImageTexture.new()
		texture.set_image(image)
		sprite.texture = texture
	
	if sprite.texture:
		sprite.offset.y = -sprite.texture.get_height() / 2.0

func find_systems():
	game_manager = get_node_or_null("/root/GameManager")
	
	world_ref = get_tree().get_first_node_in_group("world")
	if not world_ref and game_manager:
		world_ref = game_manager.world_ref
	
	if world_ref:
		tile_occupancy_system = world_ref.get_node_or_null("TileOccupancySystem")
	
	if not tile_occupancy_system:
		tile_occupancy_system = get_tree().get_first_node_in_group("tile_occupancy_system")
	
	debug_log("LIFECYCLE", "Systems found", {
		"game_manager": game_manager != null,
		"world_ref": world_ref != null,
		"tile_system": tile_occupancy_system != null
	})

func set_targeting_info(target_entity, is_direct_click: bool):
	direct_target_entity = target_entity
	is_direct_target_shot = is_direct_click
	guaranteed_hit = is_direct_click
	
	debug_log("TARGETING", "Targeting info set", {
		"has_target": target_entity != null,
		"is_direct": is_direct_click,
		"guaranteed": guaranteed_hit
	})

func fire_at(target_pos: Vector2, firing_entity, weapon = null):
	debug_log("LIFECYCLE", "=== FIRING PROJECTILE ===", {
		"target_pos": target_pos,
		"firer": firing_entity.name if firing_entity else "null"
	})
	
	if not firing_entity or not is_instance_valid(firing_entity):
		debug_log("LIFECYCLE", "Invalid firing entity")
		destroy_projectile("invalid_firer")
		return
	
	firer_player = firing_entity
	source_weapon = weapon
	target_position = target_pos
	firer_starting_position = firing_entity.global_position
	
	if game_manager and game_manager.has_method("get_local_peer_id"):
		firer_peer_id = game_manager.get_local_peer_id()
	elif "peer_id" in firing_entity:
		firer_peer_id = firing_entity.peer_id
	elif firing_entity.has_meta("peer_id"):
		firer_peer_id = firing_entity.get_meta("peer_id")
	else:
		firer_peer_id = 1
	
	if "current_z_level" in firing_entity:
		current_z_level = firing_entity.current_z_level
	
	global_position = firer_starting_position
	movement_direction = (target_pos - firer_starting_position).normalized()
	
	debug_log("TARGETING", "Fire setup complete", {
		"firer_peer_id": firer_peer_id,
		"start_pos": firer_starting_position,
		"direction": movement_direction,
		"z_level": current_z_level
	})
	
	rotate_sprite_to_target()
	set_process(true)

func rotate_sprite_to_target():
	if movement_direction != Vector2.ZERO:
		var angle = movement_direction.angle()
		sprite.rotation = angle + PI/2

func _process(delta):
	var movement_this_frame = movement_direction * speed * delta
	global_position += movement_this_frame
	travel_distance += movement_this_frame.length()
	
	debug_log("MOVEMENT", "Position update", {
		"position": global_position,
		"distance": travel_distance
	})
	
	check_collisions()
	
	var distance_to_target = global_position.distance_to(target_position)
	if distance_to_target < 16.0:
		if is_direct_target_shot and direct_target_entity:
			check_direct_target_hit()
		else:
			destroy_projectile("reached_target")

func check_collisions():
	var current_tile = world_to_tile(global_position)
	
	if should_ignore_collisions():
		return
	
	debug_log("COLLISION", "Checking collisions", {
		"tile": current_tile,
		"z_level": current_z_level
	})
	
	if check_wall_collision(current_tile):
		return
	
	check_entity_collisions(current_tile)

func should_ignore_collisions() -> bool:
	var age = (Time.get_ticks_msec() / 1000.0) - creation_time
	var distance_from_start = global_position.distance_to(firer_starting_position)
	
	return age < 0.1 and distance_from_start < 24.0

func check_wall_collision(tile_pos: Vector2i) -> bool:
	if world_ref and world_ref.has_method("is_wall_at"):
		if world_ref.is_wall_at(tile_pos, current_z_level):
			debug_log("COLLISION", "Hit wall", {"tile": tile_pos})
			hit_wall()
			return true
	return false

func check_entity_collisions(tile_pos: Vector2i):
	var entities = get_entities_at_tile(tile_pos)
	
	for entity in entities:
		if not is_instance_valid(entity):
			continue
		
		if should_ignore_entity(entity):
			continue
		
		if pierced_targets.has(entity):
			continue
		
		if is_valid_target(entity):
			hit_entity(entity)
			return

func get_entities_at_tile(tile_pos: Vector2i) -> Array:
	if tile_occupancy_system and tile_occupancy_system.has_method("get_entities_at"):
		return tile_occupancy_system.get_entities_at(tile_pos, current_z_level)
	return []

func should_ignore_entity(entity) -> bool:
	if not is_instance_valid(entity):
		return true
	
	if is_same_player(entity):
		debug_log("COLLISION", "Ignoring same player", {
			"entity": entity.name if "name" in entity else str(entity)
		})
		return true
	
	if entity is Projectile:
		return true
	
	return false

func is_same_player(entity) -> bool:
	if not firer_player or not is_instance_valid(firer_player):
		return false
	
	if entity == firer_player:
		return true
	
	if game_manager and game_manager.has_method("get_players"):
		var players = game_manager.get_players()
		
		var entity_peer_id = get_entity_peer_id(entity)
		var firer_peer_id_check = get_entity_peer_id(firer_player)
		
		if entity_peer_id != -1 and firer_peer_id_check != -1 and entity_peer_id == firer_peer_id_check:
			return true
		
		for player_id in players:
			var player_data = players[player_id]
			if "instance" in player_data and player_data.instance:
				if player_data.instance == entity and player_data.instance == firer_player:
					return true
				if player_id == firer_peer_id and player_data.instance == entity:
					return true
	
	if "entity_id" in entity and "entity_id" in firer_player:
		if entity.entity_id != "" and firer_player.entity_id != "" and entity.entity_id == firer_player.entity_id:
			return true
	
	return false

func get_entity_peer_id(entity) -> int:
	if "peer_id" in entity:
		return entity.peer_id
	elif entity.has_meta("peer_id"):
		return entity.get_meta("peer_id")
	elif entity.has_method("get_multiplayer_authority"):
		return entity.get_multiplayer_authority()
	return -1

func is_valid_target(entity) -> bool:
	if not is_instance_valid(entity):
		return false
	
	if is_same_player(entity):
		return false
	
	if entity is Projectile:
		return false
	
	if guaranteed_hit and entity == direct_target_entity:
		return true
	
	return is_entity_solid(entity)

func is_entity_solid(entity) -> bool:
	var checks = [
		"entity_dense" in entity and entity.entity_dense,
		"dense" in entity and entity.dense,
		"blocks_projectiles" in entity and entity.blocks_projectiles,
		entity.has_method("take_damage"),
		entity.has_method("apply_damage"),
		"health" in entity
	]
	
	for check in checks:
		if check:
			return true
	
	return false

func check_direct_target_hit():
	debug_log("TARGETING", "Checking direct target hit")
	
	if not direct_target_entity or not is_instance_valid(direct_target_entity):
		destroy_projectile("invalid_direct_target")
		return
	
	if should_ignore_entity(direct_target_entity):
		destroy_projectile("ignored_direct_target")
		return
	
	if guaranteed_hit or is_valid_target(direct_target_entity):
		hit_entity(direct_target_entity)
	else:
		destroy_projectile("direct_target_miss")

func hit_wall():
	debug_log("COLLISION", "Hit wall")
	play_hit_sound("wall")
	destroy_projectile("wall_hit")

func hit_entity(entity):
	debug_log("COLLISION", "=== HIT ENTITY ===", {
		"entity": entity.name if "name" in entity else str(entity)
	})
	
	if not is_instance_valid(entity):
		return
	
	if should_ignore_entity(entity):
		return
	
	var final_damage = calculate_damage(entity)
	
	if final_damage > 0:
		apply_damage_to_entity(entity, final_damage)
		play_hit_sound("entity")
		emit_signal("projectile_hit", entity, final_damage)
	
	pierced_targets.append(entity)
	
	if pierce_count <= 0 or pierced_targets.size() > pierce_count:
		destroy_projectile("entity_hit")

func calculate_damage(entity) -> float:
	var final_damage = damage
	
	if entity.has_method("get_armor_value"):
		var armor = entity.get_armor_value("ballistic")
		final_damage = apply_armor_reduction(final_damage, armor)
	
	return final_damage

func apply_armor_reduction(damage_value: float, armor_value: float) -> float:
	var reduction = armor_value / (armor_value + 50.0)
	return damage_value * (1.0 - reduction)

func apply_damage_to_entity(target, damage_amount: float):
	debug_log("COLLISION", "Applying damage", {
		"target": target.name if "name" in target else str(target),
		"damage": damage_amount
	})
	
	if not is_instance_valid(target):
		return
	
	if damage_amount <= 0:
		return
	
	var health_system = target.get_node_or_null("HealthSystem")
	if not health_system and target.get_parent():
		health_system = target.get_parent().get_node_or_null("HealthSystem")
	
	if health_system and health_system.has_method("apply_damage"):
		var damage_type = health_system.DamageType.BRUTE if "DamageType" in health_system else 0
		health_system.apply_damage(damage_amount, damage_type, 0, "", firer_player)
	elif target.has_method("take_damage"):
		target.take_damage(damage_amount, 1, "projectile", true, 0, firer_player)
	elif target.has_method("apply_damage"):
		target.apply_damage(damage_amount, 1)
	elif target.has_method("damage"):
		target.damage(damage_amount)
	elif "health" in target:
		target.health -= damage_amount
		if target.health <= 0 and target.has_method("die"):
			target.die()

func play_hit_sound(hit_type: String):
	var sound_name = "bullet_hit"
	
	match hit_type:
		"wall":
			sound_name = "bullet_hit_metal"
		"entity":
			sound_name = "bullet_hit_flesh"
	
	var audio_manager = get_node_or_null("/root/AudioManager")
	if not audio_manager and game_manager:
		audio_manager = game_manager.audio_manager
	
	if audio_manager and audio_manager.has_method("play_positioned_sound"):
		audio_manager.play_positioned_sound(sound_name, global_position, 0.6)

func world_to_tile(world_pos: Vector2) -> Vector2i:
	if tile_occupancy_system and tile_occupancy_system.has_method("world_to_tile"):
		return tile_occupancy_system.world_to_tile(world_pos)
	elif world_ref and world_ref.has_method("get_tile_at"):
		return world_ref.get_tile_at(world_pos)
	else:
		var tile_size = 32
		return Vector2i(int(world_pos.x / tile_size), int(world_pos.y / tile_size))

func destroy_projectile(reason: String = "unknown"):
	var lifetime_elapsed = (Time.get_ticks_msec() / 1000.0) - creation_time
	
	debug_log("LIFECYCLE", "=== DESTROYING PROJECTILE ===", {
		"reason": reason,
		"lifetime": lifetime_elapsed,
		"distance": travel_distance,
		"targets_hit": pierced_targets.size()
	})
	
	emit_signal("projectile_missed")
	queue_free()

func get_damage() -> float:
	return damage

func get_firer():
	return firer_player

func get_source_weapon():
	return source_weapon

func set_damage(new_damage: float):
	damage = new_damage

func set_speed(new_speed: float):
	speed = new_speed

@rpc("any_peer", "call_local", "reliable")
func sync_projectile_fired(start_pos: Vector2, target_pos: Vector2, firer_id: String):
	global_position = start_pos
	var found_firer = get_node_by_id(firer_id)
	if found_firer:
		fire_at(target_pos, found_firer)

@rpc("any_peer", "call_local", "reliable") 
func sync_projectile_hit(hit_pos: Vector2, target_id: String, damage_dealt: float):
	play_hit_sound("entity")

func get_node_by_id(node_id: String):
	if game_manager and game_manager.has_method("get_players"):
		var players = game_manager.get_players()
		for player_id in players:
			var player_data = players[player_id]
			if "instance" in player_data and player_data.instance:
				if str(player_data.instance.get_instance_id()) == node_id:
					return player_data.instance
	
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if str(player.get_instance_id()) == node_id:
			return player
	return null

func debug_log(category: String, message: String, data: Dictionary = {}):
	if not debug_enabled:
		return
	
	var should_log = false
	match category:
		"MOVEMENT":
			should_log = debug_movement
		"COLLISION":
			should_log = debug_collision
		"TARGETING":
			should_log = debug_targeting
		_:
			should_log = true
	
	if not should_log:
		return
	
	var prefix = "[%s] [%s] %s:" % [debug_id, category, message]
	
	if data.size() > 0:
		print(prefix, " ", data)
	else:
		print(prefix)
