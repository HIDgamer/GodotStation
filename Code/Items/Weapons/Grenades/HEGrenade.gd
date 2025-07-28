extends Grenade
class_name HEGrenade

# Exported explosion damage ranges in tiles for easy tuning
@export_group("Explosion Ranges")
@export var light_impact_range: float = 2.5
@export var medium_impact_range: float = 1.5
@export var heavy_impact_range: float = 0.7
@export var explosion_damage: int = 60

@export_group("Shrapnel Properties")
@export var shrapnel_count: int = 6  # Increased from 4 for better spread
@export var shrapnel_damage: int = 15
@export var shrapnel_speed: float = 500.0
@export var shrapnel_spread_angle: float = 360.0  # Full circle

@export_group("Performance Settings")
@export var max_explosion_particles: int = 80  # Reduced from 100
@export var explosion_scale: float = 1.0
@export var camera_shake_intensity: float = 1.0

@export_group("Effect Configuration")
@export var explosion_variant: int = 0  # 0 = default, 1 = large, 2 = small
@export var knockback_multiplier: float = 1.0
@export var stun_duration_multiplier: float = 1.0

# Multiplayer integration with InventorySystem
var inventory_sync_enabled: bool = true
var explosion_pending: bool = false

# Preloaded resources
static var explosion_scene: PackedScene
static var shrapnel_scene: PackedScene

func _init():
	super._init()
	obj_name = "M40_HEDP_grenade"
	obj_desc = "A small, but deceptively strong high explosive grenade that has been phasing out the M15 fragmentation grenades. Capable of being loaded in any grenade launcher, or thrown by hand."
	grenade_type = GrenadeType.EXPLOSIVE
	det_time = 4.0
	dangerous = true
	explosion_range = 3
	
	# Set throwforce for impact damage
	throwforce = 10
	
	# Load shared resources
	if not explosion_scene:
		explosion_scene = preload("res://Scenes/Effects/Explosion.tscn")
	if not shrapnel_scene:
		shrapnel_scene = preload("res://Scenes/Effects/Shrapnel.tscn")

func _ready():
	super._ready()

# Override Item multiplayer methods to integrate with InventorySystem
func equipped(user, slot: int):
	super.equipped(user, slot)
	
	# Make item follow the user and become invisible
	if get_parent() != user:
		if get_parent():
			get_parent().remove_child(self)
		user.add_child(self)
	
	# Set position relative to user
	position = Vector2.ZERO
	visible = false
	
	# Sync grenade state when equipped
	if inventory_sync_enabled and multiplayer.has_multiplayer_peer():
		sync_grenade_equipped_state.rpc(active, explosion_pending, get_item_network_id(self))

func unequipped(user, slot: int):
	super.unequipped(user, slot)
	
	# Make item visible again but keep following user until dropped
	visible = true
	
	# Sync grenade state when unequipped
	if inventory_sync_enabled and multiplayer.has_multiplayer_peer():
		sync_grenade_unequipped_state.rpc(active, explosion_pending, get_item_network_id(self))

func picked_up(user):
	super.picked_up(user)
	
	# Ensure item follows the user
	if get_parent() != user:
		if get_parent():
			get_parent().remove_child(self)
		user.add_child(self)
	
	# Set position relative to user and make invisible
	position = Vector2.ZERO
	visible = false
	
	# Sync grenade state when picked up
	if inventory_sync_enabled and multiplayer.has_multiplayer_peer():
		sync_grenade_pickup_state.rpc(active, explosion_pending, det_time, get_item_network_id(self))

func handle_drop(user):
	super.handle_drop(user)
	
	# Move to world and make visible
	var world = user.get_parent()
	if get_parent() != world:
		if get_parent():
			get_parent().remove_child(self)
		world.add_child(self)
	
	# Set world position and make visible
	global_position = user.global_position + Vector2(randf_range(-16, 16), randf_range(-16, 16))
	visible = true
	
	# Sync drop state through inventory system
	if inventory_sync_enabled and multiplayer.has_multiplayer_peer():
		sync_grenade_drop_state.rpc(active, explosion_pending, global_position, get_item_network_id(self))

func throw_to_position(thrower, target_position: Vector2) -> bool:
	# Move to world first
	var world = thrower.get_parent()
	if get_parent() != world:
		if get_parent():
			get_parent().remove_child(self)
		world.add_child(self)
	
	# Set initial position and make visible
	global_position = thrower.global_position
	visible = true
	
	# Use parent throw logic
	var result = await super.throw_to_position(thrower, target_position)
	
	# Sync throw state through inventory system
	if inventory_sync_enabled and multiplayer.has_multiplayer_peer():
		sync_grenade_throw_state.rpc(active, explosion_pending, global_position, get_item_network_id(self))
	
	return result

# Integration with InventorySystem's use functionality
func use(user):
	var result = super.use(user)
	
	# Activate grenade when used (allow any client to use)
	if not active:
		result = activate()
	
	return result

# Get network ID for syncing
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
func sync_grenade_equipped_state(is_active: bool, pending_explosion: bool, item_id: String):
	active = is_active
	explosion_pending = pending_explosion
	
	# Find the user who equipped this item
	var user = find_item_owner(item_id)
	if user and get_parent() != user:
		if get_parent():
			get_parent().remove_child(self)
		user.add_child(self)
		position = Vector2.ZERO
		visible = false

@rpc("any_peer", "call_local", "reliable")
func sync_grenade_unequipped_state(is_active: bool, pending_explosion: bool, item_id: String):
	active = is_active
	explosion_pending = pending_explosion
	visible = true

@rpc("any_peer", "call_local", "reliable")  
func sync_grenade_pickup_state(is_active: bool, pending_explosion: bool, current_det_time: float, item_id: String):
	active = is_active
	explosion_pending = pending_explosion
	det_time = current_det_time
	
	# Find the user who picked up this item
	var user = find_item_owner(item_id)
	if user and get_parent() != user:
		if get_parent():
			get_parent().remove_child(self)
		user.add_child(self)
		position = Vector2.ZERO
		visible = false

@rpc("any_peer", "call_local", "reliable")
func sync_grenade_drop_state(is_active: bool, pending_explosion: bool, drop_pos: Vector2, item_id: String):
	active = is_active
	explosion_pending = pending_explosion
	global_position = drop_pos
	visible = true
	
	# Move to world
	var world = get_tree().current_scene
	if get_parent() != world:
		if get_parent():
			get_parent().remove_child(self)
		world.add_child(self)

@rpc("any_peer", "call_local", "reliable")
func sync_grenade_throw_state(is_active: bool, pending_explosion: bool, throw_pos: Vector2, item_id: String):
	active = is_active
	explosion_pending = pending_explosion
	global_position = throw_pos
	visible = true
	
	# Move to world
	var world = get_tree().current_scene
	if get_parent() != world:
		if get_parent():
			get_parent().remove_child(self)
		world.add_child(self)

@rpc("any_peer", "call_local", "reliable")
func sync_explosion(explosion_pos: Vector2, explosion_data: Dictionary):
	execute_explosion_local(explosion_pos, explosion_data)

@rpc("any_peer", "call_local", "reliable")
func sync_damage_result(target_id: String, damage: float, damage_type: String, knockback_data: Dictionary):
	apply_damage_result_local(target_id, damage, damage_type, knockback_data)

@rpc("any_peer", "call_local", "reliable")
func sync_shrapnel_creation(pos: Vector2, shrapnel_data: Array):
	create_shrapnel_local(pos, shrapnel_data)

@rpc("any_peer", "call_local", "reliable")
func sync_explosion_effect(pos: Vector2, effect_data: Dictionary):
	create_explosion_effect_local(pos, effect_data)

@rpc("any_peer", "call_local", "reliable")
func sync_camera_shake(intensity: float, epicenter: Vector2):
	create_camera_shake_local(intensity, epicenter)

@rpc("any_peer", "call_local", "reliable")
func sync_impact_detonation(impact_pos: Vector2, impact_data: Dictionary):
	handle_impact_detonation_local(impact_pos, impact_data)
#endregion

# Find the owner of an item by network ID
func find_item_owner(item_id: String) -> Node:
	# Look through all players' inventory systems
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
	"""Handle HE grenade explosion with blast and shrapnel"""
	if not active:
		return
	
	# Allow any client to trigger explosion, but sync the result
	# Store explosion position before calling super
	var explosion_pos = global_position
	explosion_pending = true
	
	# Call parent explosion logic
	super.explode()
	
	# Prepare explosion data
	var explosion_data = {
		"light_impact_range": light_impact_range,
		"medium_impact_range": medium_impact_range,
		"heavy_impact_range": heavy_impact_range,
		"explosion_damage": explosion_damage,
		"explosion_variant": explosion_variant,
		"knockback_multiplier": knockback_multiplier,
		"stun_duration_multiplier": stun_duration_multiplier
	}
	
	# Sync explosion across network
	if multiplayer.has_multiplayer_peer():
		sync_explosion.rpc(explosion_pos, explosion_data)
	else:
		execute_explosion_local(explosion_pos, explosion_data)

func execute_explosion_local(explosion_pos: Vector2, explosion_data: Dictionary):
	"""Execute explosion effects locally"""
	# Apply explosion data
	light_impact_range = explosion_data.get("light_impact_range", light_impact_range)
	medium_impact_range = explosion_data.get("medium_impact_range", medium_impact_range)
	heavy_impact_range = explosion_data.get("heavy_impact_range", heavy_impact_range)
	explosion_damage = explosion_data.get("explosion_damage", explosion_damage)
	explosion_variant = explosion_data.get("explosion_variant", explosion_variant)
	knockback_multiplier = explosion_data.get("knockback_multiplier", knockback_multiplier)
	stun_duration_multiplier = explosion_data.get("stun_duration_multiplier", stun_duration_multiplier)
	
	# Create visual effects
	var effect_data = {
		"explosion_variant": explosion_variant,
		"explosion_scale": explosion_scale,
		"max_explosion_particles": max_explosion_particles
	}
	create_explosion_effect_local(explosion_pos, effect_data)
	
	# Apply damage (authority clients can apply damage too for responsiveness)
	apply_explosion_damage(explosion_pos)
	
	# Create shrapnel
	create_shrapnel_with_sync(explosion_pos)
	
	# Create camera shake for all clients
	create_camera_shake_local(camera_shake_intensity, explosion_pos)
	
	explosion_pending = false
	
	# Destroy the grenade after explosion - sync across all clients
	_destroy_item_local()

func create_explosion_effect_local(pos: Vector2, effect_data: Dictionary):
	"""Create visual explosion effect locally"""
	if not explosion_scene:
		return
	
	var explosion = explosion_scene.instantiate()
	if explosion:
		get_tree().current_scene.add_child(explosion)
		explosion.global_position = pos
		
		# Apply effect data
		var variant = effect_data.get("explosion_variant", 0)
		var scale = effect_data.get("explosion_scale", 1.0)
		var particles = effect_data.get("max_explosion_particles", 80)
		
		# Configure explosion intensity based on variant
		configure_explosion_intensity(explosion, variant, scale, particles)
		
		# Auto cleanup after effect duration
		create_cleanup_timer(explosion, 3.0)

func configure_explosion_intensity(explosion: Node, variant: int, scale_mult: float, particle_count: int) -> void:
	"""Configure explosion visual intensity"""
	var intensity_multiplier = 1.0
	var scale_multiplier = scale_mult
	
	match variant:
		0:  # Default
			intensity_multiplier = 1.0
		1:  # Large
			intensity_multiplier = 1.3
			scale_multiplier *= 1.2
		2:  # Small
			intensity_multiplier = 0.7
			scale_multiplier *= 0.8
	
	# Apply configuration if explosion supports it
	if explosion.has_method("configure"):
		explosion.configure(scale_multiplier, intensity_multiplier)
	elif explosion.has_method("set_intensity"):
		explosion.set_intensity(intensity_multiplier)
	
	# Optimize particle count
	if "amount" in explosion:
		explosion.amount = particle_count
	
	# Adjust scale manually if no configuration methods available
	explosion.scale = Vector2(scale_multiplier, scale_multiplier)

func apply_explosion_damage(pos: Vector2) -> void:
	"""Apply damage to entities based on distance from explosion"""
	var tile_size = 32
	var max_range = light_impact_range * tile_size
	
	var entities = get_entities_in_radius(pos, max_range)
	
	for entity in entities:
		var distance_tiles = entity.global_position.distance_to(pos) / tile_size
		
		# Calculate damage based on distance
		var damage_multiplier = calculate_damage_falloff(distance_tiles)
		var final_damage = explosion_damage * damage_multiplier
		
		# Apply damage locally
		apply_damage_to_entity(entity, final_damage, "explosive")
		
		# Prepare knockback data
		var knockback_data = {
			"direction": (entity.global_position - pos).normalized(),
			"strength": calculate_knockback_strength(distance_tiles),
			"distance_tiles": distance_tiles
		}
		
		# Sync damage result across network (but don't double-apply)
		if multiplayer.has_multiplayer_peer():
			sync_damage_result.rpc(get_entity_id(entity), final_damage, "explosive", knockback_data)
		else:
			apply_damage_result_local(get_entity_id(entity), final_damage, "explosive", knockback_data)

func calculate_knockback_strength(distance_tiles: float) -> float:
	"""Calculate knockback strength based on distance"""
	var max_knockback = 350.0 * knockback_multiplier
	return max_knockback * (1.0 - pow(distance_tiles / light_impact_range, 0.7))

func apply_damage_result_local(target_id: String, damage: float, damage_type: String, knockback_data: Dictionary):
	"""Apply damage result locally (visual effects, etc.)"""
	var entity = find_entity_by_id(target_id)
	if not entity:
		return
	
	# Apply knockback effect
	if entity.has_method("apply_knockback") and knockback_data.size() > 0:
		var direction = Vector2(knockback_data.direction.x, knockback_data.direction.y)
		var strength = knockback_data.get("strength", 0.0)
		entity.apply_knockback(direction, strength)
	
	# Apply status effects for close range
	var distance_tiles = knockback_data.get("distance_tiles", 999.0)
	if distance_tiles <= heavy_impact_range:
		apply_status_effects(entity, distance_tiles)
	
	# Send feedback message to players
	send_explosion_feedback(entity, damage / explosion_damage)

func calculate_damage_falloff(distance_tiles: float) -> float:
	"""Calculate damage reduction based on distance"""
	if distance_tiles <= heavy_impact_range:
		# Exponential falloff for heavy impact
		return 1.5 * (1.0 - (distance_tiles / heavy_impact_range) * 0.2)
	elif distance_tiles <= medium_impact_range:
		# Linear falloff in medium range
		var falloff = (distance_tiles - heavy_impact_range) / (medium_impact_range - heavy_impact_range)
		return 1.0 * (1.0 - falloff * 0.3)
	else:
		# Quadratic falloff in light range
		var falloff = (distance_tiles - medium_impact_range) / (light_impact_range - medium_impact_range)
		return 0.7 * (1.0 - falloff * falloff)

func apply_status_effects(entity: Node, distance_tiles: float) -> void:
	"""Apply stun and other status effects for close explosions"""
	if not entity.has_method("apply_effects"):
		return
	
	var stun_duration = (1.0 - pow(distance_tiles / light_impact_range, 0.6)) * 5.0 * stun_duration_multiplier
	entity.apply_effects("stun", stun_duration)

func send_explosion_feedback(entity: Node, damage_multiplier: float) -> void:
	"""Send appropriate feedback message to players"""
	if not entity.is_in_group("players") and not "is_local_player" in entity:
		return
	
	var sensory_system = get_entity_sensory_system(entity)
	if not sensory_system or not sensory_system.has_method("display_message"):
		return
	
	var message = "You're hit by an explosion!"
	var color = "orange"
	
	if damage_multiplier > 1.0:
		message = "You're hit by a powerful explosion!"
		color = "red"
	elif damage_multiplier < 0.5:
		message = "You're hit by the edge of an explosion!"
		color = "yellow"
	
	sensory_system.display_message(message, color)

func get_entity_sensory_system(entity: Node) -> Node:
	"""Get the sensory system for an entity"""
	if "sensory_system" in entity and entity.sensory_system:
		return entity.sensory_system
	elif entity.has_node("SensorySystem"):
		return entity.get_node("SensorySystem")
	elif entity.get_parent() and entity.get_parent().has_node("SensorySystem"):
		return entity.get_parent().get_node("SensorySystem")
	return null

func create_shrapnel_with_sync(pos: Vector2) -> void:
	"""Create shrapnel and sync across network"""
	if not shrapnel_scene:
		print_debug("Shrapnel scene not loaded!")
		return
	
	# Prepare shrapnel data
	var shrapnel_data = []
	var angle_step = shrapnel_spread_angle / shrapnel_count
	var base_angle = randf() * TAU  # Random starting angle
	
	for i in range(shrapnel_count):
		var angle = base_angle + (angle_step * i) + randf_range(-0.2, 0.2)
		var direction = Vector2(cos(angle), sin(angle))
		var velocity_modifier = randf_range(0.8, 1.2)
		
		shrapnel_data.append({
			"direction": {"x": direction.x, "y": direction.y},
			"velocity_modifier": velocity_modifier,
			"damage": shrapnel_damage * velocity_modifier
		})
	
	# Sync shrapnel creation
	if multiplayer.has_multiplayer_peer():
		sync_shrapnel_creation.rpc(pos, shrapnel_data)
	else:
		create_shrapnel_local(pos, shrapnel_data)

func create_shrapnel_local(pos: Vector2, shrapnel_data: Array) -> void:
	"""Create shrapnel projectiles locally"""
	if not shrapnel_scene:
		return
	
	print_debug("Creating ", shrapnel_data.size(), " shrapnel pieces")
	
	# Create shrapnel projectiles
	for data in shrapnel_data:
		var direction = Vector2(data.direction.x, data.direction.y)
		var velocity_modifier = data.get("velocity_modifier", 1.0)
		var damage = data.get("damage", shrapnel_damage)
		
		create_shrapnel_projectile(pos, direction, velocity_modifier, damage)

func create_shrapnel_projectile(pos: Vector2, direction: Vector2, velocity_modifier: float, damage: float) -> void:
	"""Create a single shrapnel projectile"""
	var shrapnel = shrapnel_scene.instantiate()
	if not shrapnel:
		print_debug("Failed to instantiate shrapnel")
		return
	
	get_tree().current_scene.add_child(shrapnel)
	shrapnel.global_position = pos
	
	print_debug("Created shrapnel at ", pos, " with direction ", direction)
	
	# Configure shrapnel properties
	var velocity = direction * shrapnel_speed * velocity_modifier
	
	# Set velocity using different possible methods
	if "velocity" in shrapnel:
		shrapnel.velocity = velocity
	elif "linear_velocity" in shrapnel:
		shrapnel.linear_velocity = velocity
	elif shrapnel.has_method("set_velocity"):
		shrapnel.set_velocity(velocity)
	elif shrapnel.has_method("launch"):
		shrapnel.launch(direction, shrapnel_speed * velocity_modifier)
	
	# Set damage properties
	if "damage" in shrapnel:
		shrapnel.damage = damage
	elif shrapnel.has_method("set_damage"):
		shrapnel.set_damage(damage)
	
	# Set penetration if available
	if "penetration" in shrapnel:
		shrapnel.penetration = 20
	
	# Set range
	if "max_range" in shrapnel:
		shrapnel.max_range = shrapnel_range * 32
	elif "range" in shrapnel:
		shrapnel.range = shrapnel_range * 32
	
	# Set projectile properties
	if "projectile_name" in shrapnel:
		shrapnel.projectile_name = "shrapnel"
	if "projectile_type" in shrapnel:
		shrapnel.projectile_type = "shrapnel"
	
	# Enable physics if it's a RigidBody2D
	if shrapnel is RigidBody2D:
		shrapnel.linear_velocity = velocity
		shrapnel.gravity_scale = 0.3  # Some gravity for realistic arc
	
	# Enable visual trail if supported
	if "has_trail" in shrapnel:
		shrapnel.has_trail = true
	elif shrapnel.has_method("enable_trail"):
		shrapnel.enable_trail()
	
	# Set up auto cleanup timer
	create_cleanup_timer(shrapnel, 5.0)

func create_camera_shake_local(intensity: float, epicenter: Vector2):
	"""Create camera shake effect locally"""
	create_camera_shake(intensity)

func throw_impact(hit_atom, speed: float = 5) -> bool:
	"""Handle impact when thrown - chance to detonate on hard surfaces"""
	# Call parent impact handling
	var result = super.throw_impact(hit_atom, speed)
	
	# Allow any client to trigger impact detonation
	# Check for impact detonation if launched
	if launched and hit_atom and hit_atom.get("density") == true:
		var detonation_chance = 0.25 + (speed / 20.0) * 0.25  # Up to 50% at high speeds
		if not active and randf() < detonation_chance:
			print_debug("Impact detonation triggered")
			
			var impact_data = {
				"hit_atom_id": get_entity_id(hit_atom),
				"speed": speed,
				"detonation_chance": detonation_chance
			}
			
			# Sync impact detonation
			if multiplayer.has_multiplayer_peer():
				sync_impact_detonation.rpc(global_position, impact_data)
			else:
				handle_impact_detonation_local(global_position, impact_data)
			
			activate()
	
	return result

func handle_impact_detonation_local(impact_pos: Vector2, impact_data: Dictionary):
	"""Handle impact detonation visual effects locally"""
	# Show impact spark effect
	if impact_pos != Vector2.ZERO:
		create_impact_spark_effect(impact_pos)

func create_impact_spark_effect(pos: Vector2):
	"""Create spark effect at impact location"""
	# Simple spark effect - you can replace with actual spark particle scene
	var spark = Sprite2D.new()
	spark.modulate = Color(1.0, 0.8, 0.2, 1.0)
	spark.scale = Vector2(0.5, 0.5)
	
	get_tree().current_scene.add_child(spark)
	spark.global_position = pos
	
	# Fade out quickly
	var tween = create_tween()
	tween.tween_property(spark, "modulate:a", 0.0, 0.3)
	tween.tween_callback(spark.queue_free)

func create_cleanup_timer(node: Node, duration: float):
	"""Create a cleanup timer for temporary nodes"""
	var timer = Timer.new()
	timer.wait_time = duration
	timer.one_shot = true
	timer.timeout.connect(func(): 
		if is_instance_valid(node):
			node.queue_free()
		if is_instance_valid(timer):
			timer.queue_free()
	)
	node.add_child(timer)
	timer.start()

func create_camera_shake(intensity: float = 1.0):
	"""Create camera shake effect"""
	# Find camera or viewport
	var camera = get_viewport().get_camera_2d()
	if not camera:
		return
	
	# Simple camera shake implementation
	var shake_tween = create_tween()
	var original_pos = camera.global_position
	
	for i in range(8):  # 8 shake iterations
		var shake_offset = Vector2(
			randf_range(-intensity * 10, intensity * 10),
			randf_range(-intensity * 10, intensity * 10)
		)
		shake_tween.tween_property(camera, "global_position", original_pos + shake_offset, 0.05)
	
	# Return to original position
	shake_tween.tween_property(camera, "global_position", original_pos, 0.1)

# Helper functions for multiplayer integration
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
	
	# Handle player targets
	if entity_id.begins_with("player_"):
		var peer_id_str = entity_id.split("_")[1]
		var peer_id_val = peer_id_str.to_int()
		return find_player_by_peer_id(peer_id_val)
	
	# Handle path-based targets
	if entity_id.begins_with("/"):
		return get_node_or_null(entity_id)
	
	# Try to find by network_id meta
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
	"""Get all entities within explosion radius"""
	var entities = []
	
	# Check different entity groups
	var groups_to_check = ["players", "entities", "mobs", "characters"]
	
	for group_name in groups_to_check:
		var group_entities = get_tree().get_nodes_in_group(group_name)
		for entity in group_entities:
			if entity.global_position.distance_to(center) <= radius:
				if not entities.has(entity):  # Avoid duplicates
					entities.append(entity)
	
	return entities

func apply_damage_to_entity(entity: Node, damage: float, damage_type: String = "explosive"):
	"""Apply damage to an entity"""
	if entity.has_method("take_damage"):
		entity.take_damage(damage, damage_type, "explosive", true)
	elif entity.has_method("damage"):
		entity.damage(damage, damage_type)
	elif "health" in entity:
		entity.health -= damage

func create_large_variant() -> HEGrenade:
	"""Create a large variant with increased properties"""
	var large_he = HEGrenade.new()
	large_he.obj_name = "M40 HEDP-L grenade"
	large_he.obj_desc = "A large variant of the M40 HEDP with increased explosive yield."
	
	# Increase properties
	large_he.explosion_variant = 1
	large_he.explosion_damage = 80
	large_he.light_impact_range = 3.0
	large_he.medium_impact_range = 2.0
	large_he.heavy_impact_range = 1.0
	large_he.shrapnel_count = 8
	large_he.camera_shake_intensity = 1.5
	
	return large_he

func create_small_variant() -> HEGrenade:
	"""Create a small variant with decreased properties"""
	var small_he = HEGrenade.new()
	small_he.obj_name = "M40 HEDP-S grenade"
	small_he.obj_desc = "A compact variant of the M40 HEDP with reduced explosive yield."
	
	# Decrease properties
	small_he.explosion_variant = 2
	small_he.explosion_damage = 40
	small_he.light_impact_range = 2.0
	small_he.medium_impact_range = 1.0
	small_he.heavy_impact_range = 0.5
	small_he.shrapnel_count = 4
	small_he.camera_shake_intensity = 0.7
	
	return small_he

func serialize() -> Dictionary:
	"""Save HE grenade specific properties"""
	var data = super.serialize()
	
	data["light_impact_range"] = light_impact_range
	data["medium_impact_range"] = medium_impact_range
	data["heavy_impact_range"] = heavy_impact_range
	data["explosion_damage"] = explosion_damage
	data["shrapnel_count"] = shrapnel_count
	data["shrapnel_damage"] = shrapnel_damage
	data["shrapnel_speed"] = shrapnel_speed
	data["shrapnel_range"] = shrapnel_range
	data["explosion_variant"] = explosion_variant
	data["camera_shake_intensity"] = camera_shake_intensity
	data["max_explosion_particles"] = max_explosion_particles
	data["explosion_pending"] = explosion_pending
	
	return data

func deserialize(data: Dictionary):
	"""Restore HE grenade specific properties"""
	super.deserialize(data)
	
	if "light_impact_range" in data: light_impact_range = data.light_impact_range
	if "medium_impact_range" in data: medium_impact_range = data.medium_impact_range
	if "heavy_impact_range" in data: heavy_impact_range = data.heavy_impact_range
	if "explosion_damage" in data: explosion_damage = data.explosion_damage
	if "shrapnel_count" in data: shrapnel_count = data.shrapnel_count
	if "shrapnel_damage" in data: shrapnel_damage = data.shrapnel_damage
	if "shrapnel_speed" in data: shrapnel_speed = data.shrapnel_speed
	if "shrapnel_range" in data: shrapnel_range = data.shrapnel_range
	if "explosion_variant" in data: explosion_variant = data.explosion_variant
	if "camera_shake_intensity" in data: camera_shake_intensity = data.camera_shake_intensity
	if "max_explosion_particles" in data: max_explosion_particles = data.max_explosion_particles
	if "explosion_pending" in data: explosion_pending = data.explosion_pending
