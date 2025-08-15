extends Grenade
class_name HEGrenade

# Import HealthSystem damage types
enum DamageType {
	BRUTE = 0,
	BURN = 1,
	TOXIN = 2,
	OXYGEN = 3,
	CLONE = 4,
	STAMINA = 5,
	BRAIN = 6,
	CELLULAR = 7,
	GENETIC = 8,
	RADIATION = 9
}

# Exported explosion damage ranges in tiles for easy tuning
@export_group("Explosion Ranges")
@export var light_impact_range: float = 2.5
@export var medium_impact_range: float = 1.5
@export var heavy_impact_range: float = 0.7
@export var explosion_damage: int = 60

@export_group("Shrapnel Properties")
@export var shrapnel_count: int = 6
@export var shrapnel_damage: int = 15
@export var shrapnel_speed: float = 500.0
@export var shrapnel_spread_angle: float = 360.0
@export var shrapnel_penetration: float = 20.0  # Armor penetration for shrapnel

@export_group("Explosive Properties")
@export var blast_penetration: float = 35.0  # High penetration for explosive damage
@export var concussion_range: float = 1.0   # Range for brain/stamina damage
@export var flash_duration: float = 8.0     # Duration of flash/stun effects
@export var deafness_duration: float = 15.0 # Duration of hearing damage

@export_group("Performance Settings")
@export var max_explosion_particles: int = 80
@export var explosion_scale: float = 1.0
@export var camera_shake_intensity: float = 1.0

@export_group("Effect Configuration")
@export var explosion_variant: int = 0
@export var knockback_multiplier: float = 1.0
@export var stun_duration_multiplier: float = 1.0

# Multiplayer integration with InventorySystem
var inventory_sync_enabled: bool = true
var explosion_pending: bool = false

# Preloaded resources
static var explosion_scene: PackedScene
static var shrapnel_scene: PackedScene

# Body zones for targeted damage
const BODY_ZONES = ["head", "chest", "groin", "l_arm", "r_arm", "l_leg", "r_leg"]
const VITAL_ZONES = ["head", "chest"]

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
	
	if get_parent() != user:
		if get_parent():
			get_parent().remove_child(self)
		user.add_child(self)
	
	position = Vector2.ZERO
	visible = false
	
	if inventory_sync_enabled and multiplayer.has_multiplayer_peer():
		sync_grenade_equipped_state.rpc(active, explosion_pending, get_item_network_id(self))

func unequipped(user, slot: int):
	super.unequipped(user, slot)
	visible = true
	
	if inventory_sync_enabled and multiplayer.has_multiplayer_peer():
		sync_grenade_unequipped_state.rpc(active, explosion_pending, get_item_network_id(self))

func picked_up(user):
	super.picked_up(user)
	
	if get_parent() != user:
		if get_parent():
			get_parent().remove_child(self)
		user.add_child(self)
	
	position = Vector2.ZERO
	visible = false
	
	if inventory_sync_enabled and multiplayer.has_multiplayer_peer():
		sync_grenade_pickup_state.rpc(active, explosion_pending, det_time, get_item_network_id(self))

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
		sync_grenade_drop_state.rpc(active, explosion_pending, global_position, get_item_network_id(self))

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
		sync_grenade_throw_state.rpc(active, explosion_pending, global_position, get_item_network_id(self))
	
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
func sync_grenade_equipped_state(is_active: bool, pending_explosion: bool, item_id: String):
	active = is_active
	explosion_pending = pending_explosion
	
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
	
	var world = get_tree().current_scene
	if get_parent() != world:
		if get_parent():
			get_parent().remove_child(self)
		world.add_child(self)

@rpc("any_peer", "call_local", "reliable")
func sync_explosion(explosion_pos: Vector2, explosion_data: Dictionary):
	execute_explosion_local(explosion_pos, explosion_data)

@rpc("any_peer", "call_local", "reliable")
func sync_damage_result(target_id: String, damage_data: Dictionary):
	apply_damage_result_local(target_id, damage_data)

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
	"""Handle HE grenade explosion with proper HealthSystem integration"""
	if not active:
		return
	
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
		"stun_duration_multiplier": stun_duration_multiplier,
		"blast_penetration": blast_penetration,
		"concussion_range": concussion_range,
		"flash_duration": flash_duration,
		"deafness_duration": deafness_duration
	}
	
	# Sync explosion across network
	if multiplayer.has_multiplayer_peer():
		sync_explosion.rpc(explosion_pos, explosion_data)
	else:
		execute_explosion_local(explosion_pos, explosion_data)

func execute_explosion_local(explosion_pos: Vector2, explosion_data: Dictionary):
	"""Execute explosion effects locally with proper HealthSystem integration"""
	# Apply explosion data
	light_impact_range = explosion_data.get("light_impact_range", light_impact_range)
	medium_impact_range = explosion_data.get("medium_impact_range", medium_impact_range)
	heavy_impact_range = explosion_data.get("heavy_impact_range", heavy_impact_range)
	explosion_damage = explosion_data.get("explosion_damage", explosion_damage)
	blast_penetration = explosion_data.get("blast_penetration", blast_penetration)
	concussion_range = explosion_data.get("concussion_range", concussion_range)
	flash_duration = explosion_data.get("flash_duration", flash_duration)
	deafness_duration = explosion_data.get("deafness_duration", deafness_duration)
	
	# Create visual effects
	var effect_data = {
		"explosion_variant": explosion_variant,
		"explosion_scale": explosion_scale,
		"max_explosion_particles": max_explosion_particles
	}
	create_explosion_effect_local(explosion_pos, effect_data)
	
	# Apply damage using proper HealthSystem integration
	apply_explosion_damage_advanced(explosion_pos)
	
	# Create shrapnel
	create_shrapnel_with_sync(explosion_pos)
	
	# Create camera shake for all clients
	create_camera_shake_local(camera_shake_intensity, explosion_pos)
	
	explosion_pending = false
	
	# Destroy the grenade after explosion
	_destroy_item_local()

func apply_explosion_damage_advanced(pos: Vector2) -> void:
	"""Apply damage using HealthSystem's advanced damage system"""
	var tile_size = 32
	var max_range = light_impact_range * tile_size
	
	var entities = get_entities_in_radius(pos, max_range)
	
	for entity in entities:
		var health_system = get_entity_health_system(entity)
		if not health_system:
			continue
		
		var distance_tiles = entity.global_position.distance_to(pos) / tile_size
		var damage_data = calculate_explosion_damage_data(distance_tiles, entity, pos)
		
		# Apply damage through HealthSystem
		apply_health_system_damage(health_system, damage_data, entity)
		
		# Sync damage result across network
		if multiplayer.has_multiplayer_peer():
			sync_damage_result.rpc(get_entity_id(entity), damage_data)
		else:
			apply_damage_result_local(get_entity_id(entity), damage_data)

func get_entity_health_system(entity: Node) -> Node:
	"""Get the HealthSystem component for an entity"""
	if "health_system" in entity and entity.health_system:
		return entity.health_system
	elif entity.has_node("HealthSystem"):
		return entity.get_node("HealthSystem")
	elif entity.get_parent() and entity.get_parent().has_node("HealthSystem"):
		return entity.get_parent().get_node("HealthSystem")
	return null

func calculate_explosion_damage_data(distance_tiles: float, entity: Node, explosion_pos: Vector2) -> Dictionary:
	"""Calculate comprehensive damage data for HealthSystem"""
	var damage_data = {}
	
	# Calculate base damage with falloff
	var base_damage_multiplier = calculate_damage_falloff(distance_tiles)
	var primary_damage = explosion_damage * base_damage_multiplier
	
	# Determine primary damage zone (closest body part to explosion)
	var primary_zone = determine_damage_zone(entity, explosion_pos)
	
	# Primary explosive damage (BRUTE with high penetration)
	damage_data["primary"] = {
		"amount": primary_damage,
		"type": DamageType.BRUTE,
		"penetration": blast_penetration,
		"zone": primary_zone,
		"source": self
	}
	
	# Secondary burn damage from heat
	if distance_tiles <= medium_impact_range:
		var burn_damage = primary_damage * 0.4
		damage_data["burn"] = {
			"amount": burn_damage,
			"type": DamageType.BURN,
			"penetration": blast_penetration * 0.6,
			"zone": primary_zone,
			"source": self
		}
	
	# Concussion effects for close range
	if distance_tiles <= concussion_range:
		var brain_damage = primary_damage * 0.3
		var stamina_damage = primary_damage * 0.8
		
		damage_data["concussion"] = {
			"amount": brain_damage,
			"type": DamageType.BRAIN,
			"penetration": 0,  # Concussion bypasses most armor
			"zone": "head",
			"source": self
		}
		
		damage_data["stamina"] = {
			"amount": stamina_damage,
			"type": DamageType.STAMINA,
			"penetration": 0,
			"zone": "chest",
			"source": self
		}
	
	# Calculate knockback
	damage_data["knockback"] = {
		"direction": (entity.global_position - explosion_pos).normalized(),
		"strength": calculate_knockback_strength(distance_tiles),
		"distance_tiles": distance_tiles
	}
	
	# Calculate status effects
	damage_data["status_effects"] = calculate_status_effects(distance_tiles, base_damage_multiplier)
	
	return damage_data

func determine_damage_zone(entity: Node, explosion_pos: Vector2) -> String:
	"""Determine which body zone is closest to the explosion"""
	var entity_pos = entity.global_position
	var direction = (explosion_pos - entity_pos).normalized()
	
	# Simple zone determination based on explosion direction
	var angle = direction.angle()
	var abs_angle = abs(angle)
	
	# Convert angle to determine hit zone
	if abs_angle < PI/6 or abs_angle > 5*PI/6:  # Front/back
		if direction.y < -0.3:  # Above entity
			return "head"
		elif direction.y > 0.3:   # Below entity
			return "l_leg" if randf() < 0.5 else "r_leg"
		else:  # Center mass
			return "chest"
	elif angle > 0:  # Right side
		return "r_arm"
	else:  # Left side
		return "l_arm"

func apply_health_system_damage(health_system: Node, damage_data: Dictionary, entity: Node):
	"""Apply damage through the HealthSystem with proper integration"""
	
	# Apply primary damage
	if damage_data.has("primary"):
		var primary = damage_data["primary"]
		health_system.apply_damage(
			primary.amount,
			primary.type,
			primary.penetration,
			primary.zone,
			primary.source
		)
	
	# Apply burn damage
	if damage_data.has("burn"):
		var burn = damage_data["burn"]
		health_system.apply_damage(
			burn.amount,
			burn.type,
			burn.penetration,
			burn.zone,
			burn.source
		)
	
	# Apply concussion damage
	if damage_data.has("concussion"):
		var concussion = damage_data["concussion"]
		health_system.apply_damage(
			concussion.amount,
			concussion.type,
			concussion.penetration,
			concussion.zone,
			concussion.source
		)
	
	# Apply stamina damage
	if damage_data.has("stamina"):
		var stamina = damage_data["stamina"]
		health_system.apply_damage(
			stamina.amount,
			stamina.type,
			stamina.penetration,
			stamina.zone,
			stamina.source
		)
	
	# Apply status effects
	if damage_data.has("status_effects"):
		for effect in damage_data["status_effects"]:
			health_system.add_status_effect(effect.name, effect.duration, effect.intensity)
	
	# Apply knockback
	if damage_data.has("knockback") and entity.has_method("apply_knockback"):
		var knockback = damage_data["knockback"]
		entity.apply_knockback(knockback.direction, knockback.strength)

func calculate_status_effects(distance_tiles: float, damage_multiplier: float) -> Array:
	"""Calculate status effects based on explosion proximity"""
	var effects = []
	
	# Stunning from concussion
	if distance_tiles <= heavy_impact_range:
		effects.append({
			"name": "stunned",
			"duration": 4.0 * stun_duration_multiplier * damage_multiplier,
			"intensity": 3.0
		})
	elif distance_tiles <= medium_impact_range:
		effects.append({
			"name": "stunned",
			"duration": 2.0 * stun_duration_multiplier * damage_multiplier,
			"intensity": 2.0
		})
	
	# Temporary deafness from blast
	if distance_tiles <= light_impact_range:
		effects.append({
			"name": "deaf",
			"duration": deafness_duration * damage_multiplier,
			"intensity": 1.0
		})
	
	# Confusion from head trauma
	if distance_tiles <= medium_impact_range:
		effects.append({
			"name": "confused",
			"duration": 8.0 * damage_multiplier,
			"intensity": 2.0
		})
	
	# Potential bleeding from shrapnel wounds
	if distance_tiles <= light_impact_range and randf() < 0.7:
		effects.append({
			"name": "bleeding",
			"duration": 30.0,
			"intensity": damage_multiplier * 2.0
		})
	
	return effects

func calculate_damage_falloff(distance_tiles: float) -> float:
	"""Calculate damage reduction based on distance with realistic falloff"""
	if distance_tiles <= heavy_impact_range:
		# Close range: maximum damage with slight falloff
		return 1.2 * (1.0 - (distance_tiles / heavy_impact_range) * 0.15)
	elif distance_tiles <= medium_impact_range:
		# Medium range: linear falloff
		var falloff = (distance_tiles - heavy_impact_range) / (medium_impact_range - heavy_impact_range)
		return 1.0 * (1.0 - falloff * 0.4)
	else:
		# Light range: exponential falloff
		var falloff = (distance_tiles - medium_impact_range) / (light_impact_range - medium_impact_range)
		return 0.6 * (1.0 - falloff * falloff)

func calculate_knockback_strength(distance_tiles: float) -> float:
	"""Calculate knockback strength based on distance"""
	var max_knockback = 400.0 * knockback_multiplier
	return max_knockback * (1.0 - pow(distance_tiles / light_impact_range, 0.6))

func apply_damage_result_local(target_id: String, damage_data: Dictionary):
	"""Apply damage result locally (visual effects, feedback)"""
	var entity = find_entity_by_id(target_id)
	if not entity:
		return
	
	# Apply knockback effect if entity supports it
	if entity.has_method("apply_knockback") and damage_data.has("knockback"):
		var knockback = damage_data["knockback"]
		var direction = Vector2(knockback.direction.x, knockback.direction.y)
		entity.apply_knockback(direction, knockback.strength)
	
	# Send feedback to players
	var distance_tiles = damage_data.get("knockback", {}).get("distance_tiles", 999.0)
	if distance_tiles <= light_impact_range:
		send_explosion_feedback(entity, distance_tiles)

func send_explosion_feedback(entity: Node, distance_tiles: float):
	"""Send appropriate feedback message to players"""
	if not entity.is_in_group("players"):
		return
	
	var sensory_system = get_entity_sensory_system(entity)
	if not sensory_system or not sensory_system.has_method("display_message"):
		return
	
	var message = ""
	var color = "orange"
	
	if distance_tiles <= heavy_impact_range:
		message = "You're caught in a devastating explosion!"
		color = "red"
	elif distance_tiles <= medium_impact_range:
		message = "You're hit by a powerful explosion!"
		color = "orange"
	else:
		message = "You're caught in the blast wave!"
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

func create_explosion_effect_local(pos: Vector2, effect_data: Dictionary):
	"""Create visual explosion effect locally"""
	if not explosion_scene:
		return
	
	var explosion = explosion_scene.instantiate()
	if explosion:
		get_tree().current_scene.add_child(explosion)
		explosion.global_position = pos
		
		var variant = effect_data.get("explosion_variant", 0)
		var scale = effect_data.get("explosion_scale", 1.0)
		var particles = effect_data.get("max_explosion_particles", 80)
		
		configure_explosion_intensity(explosion, variant, scale, particles)
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
	
	if explosion.has_method("configure"):
		explosion.configure(scale_multiplier, intensity_multiplier)
	elif explosion.has_method("set_intensity"):
		explosion.set_intensity(intensity_multiplier)
	
	if "amount" in explosion:
		explosion.amount = particle_count
	
	explosion.scale = Vector2(scale_multiplier, scale_multiplier)

func create_shrapnel_with_sync(pos: Vector2) -> void:
	"""Create shrapnel with HealthSystem integration"""
	if not shrapnel_scene:
		print_debug("Shrapnel scene not loaded!")
		return
	
	var shrapnel_data = []
	var angle_step = shrapnel_spread_angle / shrapnel_count
	var base_angle = randf() * TAU
	
	for i in range(shrapnel_count):
		var angle = base_angle + (angle_step * i) + randf_range(-0.2, 0.2)
		var direction = Vector2(cos(angle), sin(angle))
		var velocity_modifier = randf_range(0.8, 1.2)
		
		shrapnel_data.append({
			"direction": {"x": direction.x, "y": direction.y},
			"velocity_modifier": velocity_modifier,
			"damage": shrapnel_damage * velocity_modifier,
			"penetration": shrapnel_penetration,
			"damage_type": DamageType.BRUTE
		})
	
	if multiplayer.has_multiplayer_peer():
		sync_shrapnel_creation.rpc(pos, shrapnel_data)
	else:
		create_shrapnel_local(pos, shrapnel_data)

func create_shrapnel_local(pos: Vector2, shrapnel_data: Array) -> void:
	"""Create shrapnel projectiles with HealthSystem damage integration"""
	if not shrapnel_scene:
		return
	
	print_debug("Creating ", shrapnel_data.size(), " shrapnel pieces")
	
	for data in shrapnel_data:
		var direction = Vector2(data.direction.x, data.direction.y)
		var velocity_modifier = data.get("velocity_modifier", 1.0)
		var damage = data.get("damage", shrapnel_damage)
		var penetration = data.get("penetration", shrapnel_penetration)
		var damage_type = data.get("damage_type", DamageType.BRUTE)
		
		create_shrapnel_projectile(pos, direction, velocity_modifier, damage, penetration, damage_type)

func create_shrapnel_projectile(pos: Vector2, direction: Vector2, velocity_modifier: float, damage: float, penetration: float, damage_type: int) -> void:
	"""Create a single shrapnel projectile with proper damage integration"""
	var shrapnel = shrapnel_scene.instantiate()
	if not shrapnel:
		print_debug("Failed to instantiate shrapnel")
		return
	
	get_tree().current_scene.add_child(shrapnel)
	shrapnel.global_position = pos
	
	var velocity = direction * shrapnel_speed * velocity_modifier
	
	# Set velocity
	if "velocity" in shrapnel:
		shrapnel.velocity = velocity
	elif "linear_velocity" in shrapnel:
		shrapnel.linear_velocity = velocity
	elif shrapnel.has_method("set_velocity"):
		shrapnel.set_velocity(velocity)
	elif shrapnel.has_method("launch"):
		shrapnel.launch(direction, shrapnel_speed * velocity_modifier)
	
	# Set damage properties for HealthSystem integration
	if "damage" in shrapnel:
		shrapnel.damage = damage
	elif shrapnel.has_method("set_damage"):
		shrapnel.set_damage(damage)
	
	# Set penetration for armor calculations
	if "penetration" in shrapnel:
		shrapnel.penetration = penetration
	elif shrapnel.has_method("set_penetration"):
		shrapnel.set_penetration(penetration)
	
	# Set damage type for HealthSystem
	if "damage_type" in shrapnel:
		shrapnel.damage_type = damage_type
	elif shrapnel.has_method("set_damage_type"):
		shrapnel.set_damage_type(damage_type)
	
	# Set range
	if "max_range" in shrapnel:
		shrapnel.max_range = shrapnel_range * 32
	elif "range" in shrapnel:
		shrapnel.range = shrapnel_range * 32
	
	# Set projectile identification
	if "projectile_name" in shrapnel:
		shrapnel.projectile_name = "shrapnel"
	if "projectile_type" in shrapnel:
		shrapnel.projectile_type = "explosive_shrapnel"
	
	# Configure physics
	if shrapnel is RigidBody2D:
		shrapnel.linear_velocity = velocity
		shrapnel.gravity_scale = 0.3
	
	# Enable visual effects
	if "has_trail" in shrapnel:
		shrapnel.has_trail = true
	elif shrapnel.has_method("enable_trail"):
		shrapnel.enable_trail()
	
	create_cleanup_timer(shrapnel, 5.0)

func create_camera_shake_local(intensity: float, epicenter: Vector2):
	"""Create camera shake effect locally"""
	create_camera_shake(intensity)

func throw_impact(hit_atom, speed: float = 5) -> bool:
	"""Handle impact when thrown with HealthSystem integration"""
	var result = super.throw_impact(hit_atom, speed)
	
	# Check for impact detonation if launched
	if launched and hit_atom and hit_atom.get("density") == true:
		var detonation_chance = 0.25 + (speed / 20.0) * 0.25
		if not active and randf() < detonation_chance:
			print_debug("Impact detonation triggered")
			
			var impact_data = {
				"hit_atom_id": get_entity_id(hit_atom),
				"speed": speed,
				"detonation_chance": detonation_chance
			}
			
			if multiplayer.has_multiplayer_peer():
				sync_impact_detonation.rpc(global_position, impact_data)
			else:
				handle_impact_detonation_local(global_position, impact_data)
			
			activate()
	
	return result

func handle_impact_detonation_local(impact_pos: Vector2, impact_data: Dictionary):
	"""Handle impact detonation visual effects locally"""
	if impact_pos != Vector2.ZERO:
		create_impact_spark_effect(impact_pos)

func create_impact_spark_effect(pos: Vector2):
	"""Create spark effect at impact location"""
	var spark = Sprite2D.new()
	spark.modulate = Color(1.0, 0.8, 0.2, 1.0)
	spark.scale = Vector2(0.5, 0.5)
	
	get_tree().current_scene.add_child(spark)
	spark.global_position = pos
	
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
	"""Get all entities within explosion radius"""
	var entities = []
	var groups_to_check = ["players", "entities", "mobs", "characters"]
	
	for group_name in groups_to_check:
		var group_entities = get_tree().get_nodes_in_group(group_name)
		for entity in group_entities:
			if entity.global_position.distance_to(center) <= radius:
				if not entities.has(entity):
					entities.append(entity)
	
	return entities

func _destroy_item_local():
	"""Destroy the grenade locally"""
	queue_free()

func create_large_variant() -> HEGrenade:
	"""Create a large variant with increased properties"""
	var large_he = HEGrenade.new()
	large_he.obj_name = "M40 HEDP-L grenade"
	large_he.obj_desc = "A large variant of the M40 HEDP with increased explosive yield."
	
	large_he.explosion_variant = 1
	large_he.explosion_damage = 90
	large_he.light_impact_range = 3.5
	large_he.medium_impact_range = 2.2
	large_he.heavy_impact_range = 1.2
	large_he.shrapnel_count = 10
	large_he.shrapnel_damage = 20
	large_he.blast_penetration = 50.0
	large_he.camera_shake_intensity = 1.8
	
	return large_he

func create_small_variant() -> HEGrenade:
	"""Create a small variant with decreased properties"""
	var small_he = HEGrenade.new()
	small_he.obj_name = "M40 HEDP-S grenade"
	small_he.obj_desc = "A compact variant of the M40 HEDP with reduced explosive yield."
	
	small_he.explosion_variant = 2
	small_he.explosion_damage = 40
	small_he.light_impact_range = 1.8
	small_he.medium_impact_range = 1.0
	small_he.heavy_impact_range = 0.4
	small_he.shrapnel_count = 4
	small_he.shrapnel_damage = 10
	small_he.blast_penetration = 20.0
	small_he.camera_shake_intensity = 0.6
	
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
	data["shrapnel_penetration"] = shrapnel_penetration
	data["blast_penetration"] = blast_penetration
	data["concussion_range"] = concussion_range
	data["flash_duration"] = flash_duration
	data["deafness_duration"] = deafness_duration
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
	if "shrapnel_penetration" in data: shrapnel_penetration = data.shrapnel_penetration
	if "blast_penetration" in data: blast_penetration = data.blast_penetration
	if "concussion_range" in data: concussion_range = data.concussion_range
	if "flash_duration" in data: flash_duration = data.flash_duration
	if "deafness_duration" in data: deafness_duration = data.deafness_duration
	if "explosion_variant" in data: explosion_variant = data.explosion_variant
	if "camera_shake_intensity" in data: camera_shake_intensity = data.camera_shake_intensity
	if "max_explosion_particles" in data: max_explosion_particles = data.max_explosion_particles
	if "explosion_pending" in data: explosion_pending = data.explosion_pending
