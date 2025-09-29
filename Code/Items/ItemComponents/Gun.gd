extends Weapon
class_name Gun

signal ammo_changed(current_ammo, max_ammo)
signal magazine_inserted(magazine)
signal magazine_ejected(magazine)
signal fire_mode_changed(new_mode)

enum FireMode {
	SEMIAUTO,
	BURST,
	AUTOMATIC
}

enum AmmoType {
	PISTOL,
	RIFLE,
	SHOTGUN,
	SNIPER,
	SPECIAL
}

@export var accepted_ammo_types: Array[AmmoType] = [AmmoType.PISTOL]
@export var fire_delay: float = 0.3
@export var burst_amount: int = 3
@export var burst_delay: float = 0.1
@export var auto_fire_rate: float = 10.0
@export var max_range: float = 30.0
@export var close_range_tiles: int = 3
@export var optimal_range_tiles: int = 7
@export var available_fire_modes: Array[FireMode] = [FireMode.SEMIAUTO]

var current_fire_mode: FireMode = FireMode.SEMIAUTO
var current_magazine = null
var chambered_bullet = null

@export var internal_magazine: bool = false
@export var max_internal_rounds: int = 6
var internal_rounds: Array = []

var last_fired_time: float = 0.0
var burst_shots_fired: int = 0
var is_burst_firing: bool = false
var is_auto_firing: bool = false

@export var bullet_speed: float = 50.0
@export var projectile_scene: PackedScene
@export var eject_casings: bool = true
@export var casing_scene: PackedScene
@export var casing_eject_force: float = 150.0
@export var casing_eject_angle_offset: float = 45.0
@export var fire_sound: AudioStream
@export var empty_sound: AudioStream
@export var reload_sound: AudioStream

var tile_occupancy_system: Node = null
var world: Node = null
var last_target_entity = null
var last_target_position: Vector2
var is_direct_target_click: bool = false

# Enhanced debugging system
@export_group("Debug Settings")
@export var debug_enabled: bool = true
@export var debug_firing: bool = true
@export var debug_ammo: bool = true
@export var debug_targeting: bool = true
@export var debug_damage: bool = true
@export var debug_magazine: bool = true
@export var debug_fire_modes: bool = true
@export var debug_projectile: bool = true
@export var debug_network: bool = true

# Debug tracking variables
var debug_id: String = ""
var shots_fired_total: int = 0
var magazines_inserted: int = 0
var magazines_ejected: int = 0
var fire_mode_changes: int = 0
var debug_start_time: float = 0.0

func _ready():
	debug_start_time = Time.get_ticks_msec() / 1000.0
	debug_id = "GUN_" + str(get_instance_id())
	
	debug_log("LIFECYCLE", "Gun initialization started", {
		"gun_name": item_name if "item_name" in self else "Unknown Gun",
		"accepted_ammo_types": accepted_ammo_types,
		"fire_delay": fire_delay,
		"max_range": max_range
	})
	
	super._ready()
	weapon_type = WeaponType.RANGED
	requires_wielding = true
	entity_type = "gun"
	
	if available_fire_modes.size() > 0:
		current_fire_mode = available_fire_modes[0]

		var available_modes := []
		for mode in available_fire_modes:
			available_modes.append(get_fire_mode_name(mode))
		debug_log("FIRE_MODES", "Initial fire mode set", {
			"fire_mode": get_fire_mode_name(current_fire_mode),
			"available_modes": available_modes
		})
	
		if internal_magazine:
			initialize_internal_magazine()
	
		if not casing_scene and ResourceLoader.exists("res://Scenes/Effects/bulletcasings.tscn"):
			casing_scene = preload("res://Scenes/Effects/bulletcasings.tscn")
			debug_log("LIFECYCLE", "Casing scene loaded from resources")
	
	_find_systems()
	add_to_group("guns")
	
	debug_log("LIFECYCLE", "Gun initialization complete", {
		"systems_found": tile_occupancy_system != null and world != null,
		"projectile_scene_loaded": projectile_scene != null,
		"casing_scene_loaded": casing_scene != null
	})

func _find_systems():
	debug_log("LIFECYCLE", "Finding game systems")
	
	world = get_tree().get_first_node_in_group("world")
	if world:
		tile_occupancy_system = world.get_node_or_null("TileOccupancySystem")
		debug_log("LIFECYCLE", "Found world and tile occupancy system", {
			"world_name": world.name,
			"tile_system_found": tile_occupancy_system != null
		})
	
	if not tile_occupancy_system:
		tile_occupancy_system = get_tree().get_first_node_in_group("tile_occupancy_system")
		debug_log("LIFECYCLE", "Searched for tile system in groups", {
			"found": tile_occupancy_system != null
		})

func initialize_internal_magazine():
	debug_log("AMMO", "Initializing internal magazine", {
		"max_rounds": max_internal_rounds
	})
	
	internal_rounds.clear()
	for i in range(max_internal_rounds):
		internal_rounds.append(null)
	
	debug_log("AMMO", "Internal magazine initialized", {
		"slots_created": internal_rounds.size()
	})

func perform_weapon_action(user, target) -> bool:
	debug_log("FIRING", "=== WEAPON ACTION REQUESTED ===", {
		"user": user.name if user and "name" in user else "Unknown User",
		"target_type": typeof(target),
		"target_value": str(target)
	})
	
	if not can_fire():
		debug_log("FIRING", "Cannot fire - handling failure")
		handle_fire_failure(user)
		return false
	
	analyze_target(user, target)
	var success = fire_gun(user, target)
	
	debug_log("FIRING", "Weapon action complete", {
		"success": success
	})
	
	return success

func analyze_target(user, target):
	debug_log("TARGETING", "=== ANALYZING TARGET ===")
	
	last_target_entity = null
	is_direct_target_click = false
	
	if target is Vector2:
		last_target_position = target
		var clicked_entity = get_entity_at_position(target)
		if clicked_entity and clicked_entity != user:
			last_target_entity = clicked_entity
			is_direct_target_click = true
		
		debug_log("TARGETING", "Vector2 target analysis", {
			"target_position": target,
			"clicked_entity": clicked_entity.name if clicked_entity and "name" in clicked_entity else "None",
			"is_direct_click": is_direct_target_click
		})
		
	elif target is Node2D:
		last_target_entity = target
		last_target_position = target.global_position
		is_direct_target_click = true
		
		debug_log("TARGETING", "Node2D target analysis", {
			"target_entity": target.name if "name" in target else str(target),
			"target_position": target.global_position,
			"is_direct_click": is_direct_target_click
		})
		
	else:
		last_target_position = user.get_global_mouse_position()
		debug_log("TARGETING", "Fallback target analysis", {
			"target_position": last_target_position,
			"method": "mouse_position"
		})

func get_entity_at_position(world_pos: Vector2):
	debug_log("TARGETING", "Searching for entity at position", {
		"world_pos": world_pos
	})
	
	if not tile_occupancy_system:
		debug_log("TARGETING", "No tile occupancy system - cannot search for entities")
		return null
	
	var tile_pos = tile_occupancy_system.world_to_tile(world_pos)
	var entities = tile_occupancy_system.get_entities_at(tile_pos, 0)

	var entity_names := []
	for entity in entities:
		if entity and "name" in entity:
			entity_names.append(entity.name)
		else:
			entity_names.append(str(entity))
	
	debug_log("TARGETING", "Entity search results", {
		"tile_pos": tile_pos,
		"entities_found": entities.size(),
		"entity_names": entity_names
	})
	
	for entity in entities:
		if entity and is_instance_valid(entity) and entity.has_method("take_damage"):
			debug_log("TARGETING", "Found valid damage target", {
				"entity": entity.name if "name" in entity else str(entity)
			})
			return entity
	
	debug_log("TARGETING", "No valid damage targets found")
	return null

func can_use_weapon(user) -> bool:
	var base_can_use = super.can_use_weapon(user)
	
	debug_log("FIRING", "Weapon use permission check", {
		"user": user.name if user and "name" in user else "No user",
		"base_can_use": base_can_use,
		"user_exists": user != null
	})
	
	if not user:
		return false
	
	return base_can_use

func can_fire() -> bool:
	var base_can_use = super.can_use_weapon(get_user())
	var has_ammunition = has_ammo()
	var time_since_last_shot = (Time.get_ticks_msec() / 1000.0) - last_fired_time
	var fire_delay_satisfied = time_since_last_shot >= fire_delay
	
	var can_fire_result = base_can_use and has_ammunition and fire_delay_satisfied
	
	debug_log("FIRING", "Fire permission check", {
		"base_can_use": base_can_use,
		"has_ammo": has_ammunition,
		"time_since_last_shot": time_since_last_shot,
		"fire_delay": fire_delay,
		"fire_delay_satisfied": fire_delay_satisfied,
		"can_fire": can_fire_result
	})
	
	return can_fire_result

func has_ammo() -> bool:
	var has_ammunition = false
	
	if internal_magazine:
		for bullet in internal_rounds:
			if bullet != null:
				has_ammunition = true
				break
		
		var rounds := []
		for bullet in internal_rounds:
			rounds.append(bullet != null)
		
		debug_log("AMMO", "Internal magazine ammo check", {
			"has_ammo": has_ammunition,
			"rounds": rounds
		})
	else:
		has_ammunition = chambered_bullet != null or (current_magazine and current_magazine.current_rounds > 0)
		
		debug_log("AMMO", "External magazine ammo check", {
			"has_chambered": chambered_bullet != null,
			"has_magazine": current_magazine != null,
			"magazine_rounds": current_magazine.current_rounds if current_magazine else 0,
			"has_ammo": has_ammunition
		})
	
	return has_ammunition

func get_current_ammo_count() -> int:
	var count = 0
	
	if internal_magazine:
		for bullet in internal_rounds:
			if bullet != null:
				count += 1
	else:
		if chambered_bullet:
			count += 1
		if current_magazine:
			count += current_magazine.current_rounds
	
	debug_log("AMMO", "Ammo count calculated", {
		"internal_magazine": internal_magazine,
		"count": count,
		"chambered": chambered_bullet != null,
		"magazine_rounds": current_magazine.current_rounds if current_magazine else 0
	})
	
	return count

func get_max_ammo_count() -> int:
	var max_count = 0
	
	if internal_magazine:
		max_count = max_internal_rounds
	else:
		max_count = 1  # Chambered round
		if current_magazine:
			max_count += current_magazine.max_rounds
	
	debug_log("AMMO", "Max ammo count calculated", {
		"internal_magazine": internal_magazine,
		"max_count": max_count
	})
	
	return max_count

func fire_gun(user, target) -> bool:
	debug_log("FIRING", "=== FIRING GUN ===", {
		"user": user.name if user and "name" in user else "Unknown",
		"fire_mode": get_fire_mode_name(current_fire_mode)
	})
	
	if not user or not is_instance_valid(user):
		debug_log("FIRING", "Invalid user - cannot fire")
		return false
	
	var bullet = get_next_bullet()
	if not bullet:
		debug_log("FIRING", "No bullet available")
		play_empty_sound()
		return false
	
	debug_log("AMMO", "Bullet acquired for firing", {
		"bullet_type": typeof(bullet),
		"bullet_value": str(bullet)
	})
	
	var success = create_and_fire_projectile(user, target, bullet)
	
	if success:
		shots_fired_total += 1
		last_fired_time = Time.get_ticks_msec() / 1000.0
		
		debug_log("FIRING", "Projectile fired successfully", {
			"shots_fired_total": shots_fired_total,
			"fire_time": last_fired_time
		})
		
		sync_gun_fired(user, target)
		
		match current_fire_mode:
			FireMode.BURST:
				handle_burst_fire(user, target)
			FireMode.AUTOMATIC:
				handle_auto_fire(user, target)
		
		eject_casing(user)
		chamber_next_round()
		
		var current_ammo = get_current_ammo_count()
		var max_ammo = get_max_ammo_count()
		emit_signal("ammo_changed", current_ammo, max_ammo)
		
		debug_log("AMMO", "Post-fire ammo update", {
			"current_ammo": current_ammo,
			"max_ammo": max_ammo
		})
	else:
		debug_log("FIRING", "Projectile creation failed")
	
	return success

func sync_gun_fired(user, target):
	if not multiplayer.has_multiplayer_peer():
		debug_log("NETWORK", "No multiplayer peer - skipping network sync")
		return
	
	var user_id = get_user_network_id(user)
	var target_pos = get_target_position(user, target)
	
	debug_log("NETWORK", "Syncing gun fired", {
		"user_id": user_id,
		"target_pos": target_pos,
		"damage": weapon_damage
	})
	
	network_gun_fired.rpc(user_id, target_pos, weapon_damage)

func get_user_network_id(user) -> String:
	var network_id = ""
	
	if user.has_method("get_network_id"):
		network_id = user.get_network_id()
	elif user.has_meta("peer_id"):
		network_id = str(user.get_meta("peer_id"))
	else:
		network_id = str(user.get_instance_id())
	
	debug_log("NETWORK", "User network ID retrieved", {
		"user": user.name if "name" in user else str(user),
		"network_id": network_id,
		"method_used": "get_network_id" if user.has_method("get_network_id") else ("peer_id" if user.has_meta("peer_id") else "instance_id")
	})
	
	return network_id

func get_target_position(user, target) -> Vector2:
	var target_pos: Vector2
	
	if target is Node2D:
		target_pos = target.global_position
	elif target is Vector2:
		target_pos = target
	elif user and user.has_method("get_global_mouse_position"):
		target_pos = user.get_global_mouse_position()
	else:
		target_pos = user.global_position + Vector2(100, 0)
	
	debug_log("TARGETING", "Target position resolved", {
		"target_type": typeof(target),
		"target_pos": target_pos,
		"method_used": "node_position" if target is Node2D else ("vector" if target is Vector2 else ("mouse" if user and user.has_method("get_global_mouse_position") else "fallback"))
	})
	
	return target_pos

@rpc("any_peer", "call_local", "reliable")
func network_gun_fired(user_id: String, target_pos: Vector2, damage_amount: float):
	debug_log("NETWORK", "Network gun fired received", {
		"user_id": user_id,
		"target_pos": target_pos,
		"damage_amount": damage_amount
	})
	
	var user = find_user_by_id(user_id)
	if user:
		play_fire_effects(user)
	else:
		debug_log("NETWORK", "User not found for network fire", {
			"user_id": user_id
		})

func find_user_by_id(user_id: String):
	var players = get_tree().get_nodes_in_group("players")
	debug_log("NETWORK", "Searching for user by ID", {
		"user_id": user_id,
		"total_players": players.size()
	})
	
	for player in players:
		if get_user_network_id(player) == user_id:
			debug_log("NETWORK", "User found", {
				"player": player.name if "name" in player else str(player)
			})
			return player
	
	debug_log("NETWORK", "User not found")
	return null

func is_wielded() -> bool:
	var wielded = false
	
	if "wielded" in self:
		wielded = self.wielded
	elif inventory_owner and inventory_owner.has_node("WeaponHandlingComponent"):
		var weapon_handler = inventory_owner.get_node("WeaponHandlingComponent")
		if weapon_handler.has_method("is_wielded_weapon"):
			wielded = weapon_handler.is_wielded_weapon(self)
	
	debug_log("FIRING", "Wield status check", {
		"wielded": wielded,
		"has_wielded_property": "wielded" in self,
		"has_weapon_handler": inventory_owner and inventory_owner.has_node("WeaponHandlingComponent")
	})
	
	return wielded

func get_primary_ammo_type() -> AmmoType:
	var primary_type = AmmoType.PISTOL
	if accepted_ammo_types.size() > 0:
		primary_type = accepted_ammo_types[0]
	
	debug_log("AMMO", "Primary ammo type", {
		"primary_type": primary_type,
		"accepted_types": accepted_ammo_types
	})
	
	return primary_type

func get_next_bullet():
	var bullet = null
	
	if chambered_bullet:
		bullet = chambered_bullet
		chambered_bullet = null
		debug_log("AMMO", "Retrieved chambered bullet")
	elif internal_magazine:
		for i in range(internal_rounds.size()):
			if internal_rounds[i] != null:
				bullet = internal_rounds[i]
				internal_rounds[i] = null
				debug_log("AMMO", "Retrieved bullet from internal magazine", {
					"slot": i
				})
				break
	elif current_magazine and current_magazine.current_rounds > 0:
		bullet = current_magazine.extract_bullet()
		debug_log("AMMO", "Retrieved bullet from magazine", {
			"remaining_rounds": current_magazine.current_rounds
		})
	
	debug_log("AMMO", "Get next bullet result", {
		"bullet_found": bullet != null,
		"bullet_type": typeof(bullet) if bullet else "null"
	})
	
	return bullet

func chamber_next_round():
	if chambered_bullet:
		debug_log("AMMO", "Round already chambered - no action needed")
		return
	
	if internal_magazine:
		debug_log("AMMO", "Internal magazine - no chambering needed")
		return
	elif current_magazine and current_magazine.has_method("extract_bullet"):
		var bullet = current_magazine.extract_bullet()
		if bullet:
			chambered_bullet = bullet
			debug_log("AMMO", "Chambered round from magazine", {
				"magazine_rounds_remaining": current_magazine.current_rounds
			})
	elif current_magazine and "current_rounds" in current_magazine and current_magazine.current_rounds > 0:
		chambered_bullet = true
		current_magazine.current_rounds -= 1
		debug_log("AMMO", "Chambered round (simple method)", {
			"magazine_rounds_remaining": current_magazine.current_rounds
		})

func create_and_fire_projectile(user, target, bullet) -> bool:
	debug_log("PROJECTILE", "=== CREATING PROJECTILE ===")
	
	if not projectile_scene or not user or not is_instance_valid(user):
		debug_log("PROJECTILE", "Cannot create projectile - missing requirements", {
			"has_projectile_scene": projectile_scene != null,
			"has_user": user != null,
			"user_valid": is_instance_valid(user) if user else false
		})
		return false
	
	var projectile = projectile_scene.instantiate()
	if not projectile or not world:
		debug_log("PROJECTILE", "Projectile instantiation failed", {
			"projectile_created": projectile != null,
			"world_exists": world != null
		})
		return false
	
	var target_pos: Vector2
	if target is Node2D:
		target_pos = target.global_position
	elif target is Vector2:
		target_pos = target
	else:
		target_pos = user.get_global_mouse_position()
	
	var firing_direction = (target_pos - user.global_position).normalized()
	var spawn_position = user.global_position + firing_direction * 16.0
	
	var user_z_level = 0
	if "current_z_level" in user:
		user_z_level = user.current_z_level
	
	debug_log("PROJECTILE", "Projectile positioning", {
		"user_position": user.global_position,
		"target_position": target_pos,
		"firing_direction": firing_direction,
		"spawn_position": spawn_position,
		"z_level": user_z_level
	})
	
	world.add_child(projectile)
	projectile.global_position = spawn_position
	
	if "current_z_level" in projectile:
		projectile.current_z_level = user_z_level
	
	var final_target_pos = calculate_target_position(user, target_pos)
	var calculated_damage = calculate_distance_damage(user, target_pos)
	
	debug_log("DAMAGE", "Damage calculation", {
		"base_damage": weapon_damage,
		"calculated_damage": calculated_damage,
		"distance": user.global_position.distance_to(target_pos)
	})
	
	if projectile.has_method("set_damage"):
		projectile.set_damage(calculated_damage)
	
	if projectile.has_method("set_speed"):
		projectile.set_speed(bullet_speed)
	
	if projectile.has_method("set_targeting_info"):
		projectile.set_targeting_info(last_target_entity, is_direct_target_click)
		debug_log("PROJECTILE", "Targeting info set on projectile", {
			"target_entity": last_target_entity.name if last_target_entity and "name" in last_target_entity else "None",
			"is_direct_click": is_direct_target_click
		})
	
	if projectile.has_method("fire_at"):
		projectile.fire_at(final_target_pos, user, self)
		debug_log("PROJECTILE", "Projectile fired at target", {
			"final_target_pos": final_target_pos
		})
	
	play_fire_effects(user)
	return true

func calculate_target_position(user, target_pos: Vector2) -> Vector2:
	# Direct target clicks always hit exactly where clicked
	if is_direct_target_click and last_target_entity:
		debug_log("TARGETING", "Direct target click - using exact position", {
			"target_pos": target_pos
		})
		return target_pos
	
	var distance_to_target = user.global_position.distance_to(target_pos)
	var tile_size = 32.0
	var max_travel = max_range * tile_size
	
	var final_pos = target_pos
	
	# Limit projectile travel distance
	if distance_to_target > max_travel:
		var direction = (target_pos - user.global_position).normalized()
		final_pos = user.global_position + direction * max_travel
		debug_log("TARGETING", "Target position limited by max range", {
			"original_pos": target_pos,
			"distance": distance_to_target,
			"max_travel": max_travel,
			"final_pos": final_pos
		})
	
	return final_pos

func calculate_distance_damage(user, target_pos: Vector2) -> float:
	var base_damage = weapon_damage
	var distance = user.global_position.distance_to(target_pos)
	var tile_size = 32.0
	var distance_in_tiles = distance / tile_size
	
	var final_damage = base_damage
	var damage_modifier = 1.0
	var range_category = ""
	
	# Close range bonus (within 3 tiles)
	if distance_in_tiles <= close_range_tiles:
		var proximity_bonus = 1.0 + (close_range_tiles - distance_in_tiles) / close_range_tiles * 0.5
		final_damage = base_damage * proximity_bonus
		damage_modifier = proximity_bonus
		range_category = "close"
	# Optimal range (4-7 tiles) - full damage
	elif distance_in_tiles <= optimal_range_tiles:
		final_damage = base_damage
		damage_modifier = 1.0
		range_category = "optimal"
	# Long range falloff (beyond 7 tiles)
	else:
		var falloff_start = optimal_range_tiles
		var falloff_end = max_range
		var falloff_progress = (distance_in_tiles - falloff_start) / (falloff_end - falloff_start)
		damage_modifier = 1.0 - (falloff_progress * 0.4)  # Max 40% damage reduction
		final_damage = base_damage * max(0.6, damage_modifier)
		range_category = "long"
	
	debug_log("DAMAGE", "Distance damage calculation", {
		"base_damage": base_damage,
		"distance": distance,
		"distance_in_tiles": distance_in_tiles,
		"range_category": range_category,
		"damage_modifier": damage_modifier,
		"final_damage": final_damage
	})
	
	return final_damage

func handle_burst_fire(user, target):
	if not is_burst_firing:
		is_burst_firing = true
		burst_shots_fired = 1
		
		debug_log("FIRE_MODES", "Starting burst fire", {
			"burst_amount": burst_amount,
			"burst_delay": burst_delay,
			"initial_shot": 1
		})
		
		for i in range(burst_amount - 1):
			var delay = burst_delay * (i + 1)
			get_tree().create_timer(delay).timeout.connect(func(): fire_burst_shot(user, target))

func fire_burst_shot(user, target):
	debug_log("FIRE_MODES", "Firing burst shot", {
		"burst_shots_fired": burst_shots_fired,
		"burst_amount": burst_amount
	})
	
	if burst_shots_fired >= burst_amount:
		is_burst_firing = false
		burst_shots_fired = 0
		debug_log("FIRE_MODES", "Burst fire complete")
		return
	
	if can_fire():
		fire_gun(user, target)
	else:
		debug_log("FIRE_MODES", "Cannot fire burst shot", {
			"burst_shots_fired": burst_shots_fired
		})
	
	burst_shots_fired += 1
	if burst_shots_fired >= burst_amount:
		is_burst_firing = false
		burst_shots_fired = 0
		debug_log("FIRE_MODES", "Burst fire sequence complete")

func handle_auto_fire(user, target):
	if not is_auto_firing:
		is_auto_firing = true
		debug_log("FIRE_MODES", "Starting automatic fire", {
			"auto_fire_rate": auto_fire_rate
		})
		start_auto_fire(user, target)

func start_auto_fire(user, target):
	var auto_delay = 1.0 / auto_fire_rate
	var shots_in_burst = 0
	
	debug_log("FIRE_MODES", "Auto fire loop starting", {
		"auto_delay": auto_delay
	})
	
	while is_auto_firing and can_fire() and has_ammo():
		await get_tree().create_timer(auto_delay).timeout
		if is_auto_firing:
			shots_in_burst += 1
			debug_log("FIRE_MODES", "Auto fire shot", {
				"shot_number": shots_in_burst
			})
			fire_gun(user, target)
	
	debug_log("FIRE_MODES", "Auto fire ended", {
		"shots_fired": shots_in_burst,
		"is_auto_firing": is_auto_firing,
		"can_fire": can_fire(),
		"has_ammo": has_ammo()
	})

func stop_auto_fire():
	debug_log("FIRE_MODES", "Stopping automatic fire")
	is_auto_firing = false

func handle_fire_failure(user):
	if not has_ammo():
		debug_log("FIRING", "Fire failure: no ammo")
		play_empty_sound()
		show_message_to_user(user, "The " + item_name + " is empty!")
	else:
		debug_log("FIRING", "Fire failure: other reason")
		super.handle_use_failure(user)

func eject_casing(user):
	if not eject_casings or not casing_scene:
		debug_log("FIRING", "Casing ejection skipped", {
			"eject_casings": eject_casings,
			"has_casing_scene": casing_scene != null
		})
		return
	
	debug_log("FIRING", "Ejecting casing")
	
	var casing = casing_scene.instantiate()
	if not casing:
		debug_log("FIRING", "Failed to instantiate casing")
		return
	
	var world = user.get_parent()
	if not world:
		debug_log("FIRING", "No world parent for casing ejection")
		return
	
	world.add_child(casing)
	
	casing.global_position = user.global_position + Vector2(randf_range(-8, 8), randf_range(-8, 8))
	
	var firing_direction = get_firing_direction(user)
	var eject_direction = firing_direction.rotated(deg_to_rad(casing_eject_angle_offset))
	
	eject_direction = eject_direction.rotated(deg_to_rad(randf_range(-15, 15)))
	
	debug_log("FIRING", "Casing ejected", {
		"position": casing.global_position,
		"direction": eject_direction,
		"force": casing_eject_force
	})
	
	if casing.has_method("eject_with_animation"):
		casing.eject_with_animation(eject_direction, casing_eject_force)

func get_firing_direction(user) -> Vector2:
	var direction = Vector2.RIGHT
	
	if user and user.has_method("get_global_mouse_position"):
		direction = (user.get_global_mouse_position() - user.global_position).normalized()
	elif user and user.has_method("get_current_direction"):
		var direction_index = user.get_current_direction()
		var directions = [
			Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0),
			Vector2(1, -1).normalized(), Vector2(1, 1).normalized(),
			Vector2(-1, 1).normalized(), Vector2(-1, -1).normalized()
		]
		if direction_index < directions.size():
			direction = directions[direction_index]
	
	debug_log("FIRING", "Firing direction calculated", {
		"direction": direction,
		"method": "mouse_position" if user and user.has_method("get_global_mouse_position") else ("direction_index" if user and user.has_method("get_current_direction") else "fallback")
	})
	
	return direction

func play_fire_effects(user):
	debug_log("FIRING", "Playing fire effects")
	if fire_sound:
		play_audio(fire_sound, -10)

func play_empty_sound():
	debug_log("FIRING", "Playing empty sound")
	if empty_sound:
		play_audio(empty_sound, -5)

func can_accept_magazine(magazine) -> bool:
	if internal_magazine:
		debug_log("MAGAZINE", "Cannot accept magazine - internal magazine gun")
		return false
	
	if not magazine or not magazine.has_method("get_ammo_type"):
		debug_log("MAGAZINE", "Cannot accept magazine - invalid magazine", {
			"magazine_exists": magazine != null,
			"has_ammo_type_method": magazine.has_method("get_ammo_type") if magazine else false
		})
		return false
	
	var can_accept = magazine.get_ammo_type() in accepted_ammo_types
	debug_log("MAGAZINE", "Magazine acceptance check", {
		"magazine_ammo_type": magazine.get_ammo_type(),
		"accepted_types": accepted_ammo_types,
		"can_accept": can_accept
	})
	
	return can_accept

func insert_magazine(magazine, user) -> bool:
	debug_log("MAGAZINE", "=== INSERTING MAGAZINE ===", {
		"user": user.name if user and "name" in user else "Unknown"
	})
	
	if internal_magazine:
		show_message_to_user(user, "This gun doesn't use magazines!")
		debug_log("MAGAZINE", "Insert failed - internal magazine gun")
		return false
	
	if current_magazine:
		show_message_to_user(user, "There's already a magazine loaded!")
		debug_log("MAGAZINE", "Insert failed - magazine already loaded")
		return false
	
	if not can_accept_magazine(magazine):
		show_message_to_user(user, "This magazine doesn't fit!")
		debug_log("MAGAZINE", "Insert failed - incompatible magazine")
		return false
	
	current_magazine = magazine
	magazines_inserted += 1
	chamber_next_round()
	
	if reload_sound:
		play_audio(reload_sound, -5)
	
	show_message_to_user(user, "You load the magazine into " + item_name + ".")
	emit_signal("magazine_inserted", magazine)
	emit_signal("ammo_changed", get_current_ammo_count(), get_max_ammo_count())
	
	debug_log("MAGAZINE", "Magazine inserted successfully", {
		"magazine": magazine.name if "name" in magazine else str(magazine),
		"magazines_inserted_total": magazines_inserted,
		"new_ammo_count": get_current_ammo_count()
	})
	
	return true

func get_magazine():
	return current_magazine

func remove_magazine():
	if not current_magazine:
		debug_log("MAGAZINE", "No magazine to remove")
		return null
	
	var ejected_mag = current_magazine
	current_magazine = null
	magazines_ejected += 1
	
	emit_signal("magazine_ejected", ejected_mag)
	emit_signal("ammo_changed", get_current_ammo_count(), get_max_ammo_count())
	
	debug_log("MAGAZINE", "Magazine removed", {
		"magazine": ejected_mag.name if "name" in ejected_mag else str(ejected_mag),
		"magazines_ejected_total": magazines_ejected
	})
	
	return ejected_mag

func eject_magazine_raw():
	if internal_magazine:
		debug_log("MAGAZINE", "Cannot eject - internal magazine gun")
		return null
	
	if not current_magazine:
		debug_log("MAGAZINE", "No magazine to eject")
		return null
	
	var ejected_mag = current_magazine
	current_magazine = null
	magazines_ejected += 1
	
	emit_signal("magazine_ejected", ejected_mag)
	emit_signal("ammo_changed", get_current_ammo_count(), get_max_ammo_count())
	
	debug_log("MAGAZINE", "Magazine ejected (raw)", {
		"magazine": ejected_mag.name if "name" in ejected_mag else str(ejected_mag),
		"magazines_ejected_total": magazines_ejected
	})
	
	return ejected_mag

func eject_magazine(user):
	debug_log("MAGAZINE", "=== EJECTING MAGAZINE ===", {
		"user": user.name if user and "name" in user else "Unknown"
	})
	
	if internal_magazine:
		show_message_to_user(user, "This gun doesn't use magazines!")
		debug_log("MAGAZINE", "Eject failed - internal magazine gun")
		return null
	
	if not current_magazine:
		show_message_to_user(user, "There's no magazine to eject!")
		debug_log("MAGAZINE", "Eject failed - no magazine loaded")
		return null
	
	var ejected_mag = current_magazine
	current_magazine = null
	magazines_ejected += 1
	
	if user and user.has_method("try_put_in_hands"):
		var put_in_hands = user.try_put_in_hands(ejected_mag)
		debug_log("MAGAZINE", "Trying to put ejected magazine in hands", {
			"success": put_in_hands
		})
		if not put_in_hands:
			drop_magazine_at_feet(user, ejected_mag)
	else:
		drop_magazine_at_feet(user, ejected_mag)
	
	show_message_to_user(user, "You eject the magazine from " + item_name + ".")
	emit_signal("magazine_ejected", ejected_mag)
	emit_signal("ammo_changed", get_current_ammo_count(), get_max_ammo_count())
	
	debug_log("MAGAZINE", "Magazine ejected successfully", {
		"magazine": ejected_mag.name if "name" in ejected_mag else str(ejected_mag),
		"magazines_ejected_total": magazines_ejected
	})
	
	return ejected_mag

func drop_magazine_at_feet(user, magazine):
	var world = user.get_parent()
	if world and magazine.get_parent() != world:
		if magazine.get_parent():
			magazine.get_parent().remove_child(magazine)
		world.add_child(magazine)
	
	magazine.global_position = user.global_position + Vector2(0, 32)
	
	debug_log("MAGAZINE", "Magazine dropped at feet", {
		"position": magazine.global_position
	})

func cycle_fire_mode(user) -> bool:
	if available_fire_modes.size() <= 1:
		debug_log("FIRE_MODES", "Cannot cycle fire mode - only one mode available")
		return false
	
	var current_index = available_fire_modes.find(current_fire_mode)
	var next_index = (current_index + 1) % available_fire_modes.size()
	var old_mode = current_fire_mode
	current_fire_mode = available_fire_modes[next_index]
	fire_mode_changes += 1
	
	var mode_name = get_fire_mode_name(current_fire_mode)
	show_message_to_user(user, "Fire mode: " + mode_name)
	
	emit_signal("fire_mode_changed", current_fire_mode)
	
	debug_log("FIRE_MODES", "Fire mode cycled", {
		"old_mode": get_fire_mode_name(old_mode),
		"new_mode": mode_name,
		"fire_mode_changes_total": fire_mode_changes
	})
	
	return true

func get_fire_mode_name(mode: FireMode) -> String:
	match mode:
		FireMode.SEMIAUTO:
			return "Semi-Auto"
		FireMode.BURST:
			return "Burst (" + str(burst_amount) + ")"
		FireMode.AUTOMATIC:
			return "Full Auto"
		_:
			return "Unknown"

func get_user():
	return inventory_owner

func interact(user) -> bool:
	debug_log("MAGAZINE", "Gun interaction", {
		"user": user.name if user and "name" in user else "Unknown",
		"has_magazine": current_magazine != null
	})
	
	if current_magazine:
		return eject_magazine(user)
	return super.interact(user)

func attack_self(user):
	debug_log("FIRE_MODES", "Attack self interaction", {
		"shift_pressed": Input.is_key_pressed(KEY_SHIFT)
	})
	
	if Input.is_key_pressed(KEY_SHIFT):
		cycle_fire_mode(user)
	else:
		toggle_safety(user)

func show_message_to_user(user, message: String):
	if user and user.has_method("show_message"):
		user.show_message(message)
	else:
		print(message)

func serialize() -> Dictionary:
	var data = super.serialize()
	data.merge({
		"current_fire_mode": current_fire_mode,
		"has_chambered_bullet": chambered_bullet != null,
		"internal_rounds_count": internal_rounds.size() if internal_magazine else 0
	})
	
	debug_log("LIFECYCLE", "Gun serialized", {
		"fire_mode": get_fire_mode_name(current_fire_mode),
		"has_chambered": chambered_bullet != null,
		"internal_rounds": internal_rounds.size() if internal_magazine else 0
	})
	
	return data

func deserialize(data: Dictionary):
	super.deserialize(data)
	if "current_fire_mode" in data: 
		current_fire_mode = data.current_fire_mode
	if "has_chambered_bullet" in data and data.has_chambered_bullet:
		pass
	
	debug_log("LIFECYCLE", "Gun deserialized", {
		"data_keys": data.keys()
	})

# Debug logging function
func debug_log(category: String, message: String, data: Dictionary = {}):
	if not debug_enabled:
		return
	
	var should_log = false
	match category:
		"LIFECYCLE":
			should_log = true
		"FIRING":
			should_log = debug_firing
		"AMMO":
			should_log = debug_ammo
		"TARGETING":
			should_log = debug_targeting
		"DAMAGE":
			should_log = debug_damage
		"MAGAZINE":
			should_log = debug_magazine
		"FIRE_MODES":
			should_log = debug_fire_modes
		"PROJECTILE":
			should_log = debug_projectile
		"NETWORK":
			should_log = debug_network
		_:
			should_log = true
	
	if not should_log:
		return
	
	var timestamp = Time.get_ticks_msec() / 1000.0 - debug_start_time
	var prefix = "[%s] [%.3f] [%s] %s:" % [debug_id, timestamp, category, message]
	
	if data.size() > 0:
		print(prefix, " ", data)
	else:
		print(prefix)
