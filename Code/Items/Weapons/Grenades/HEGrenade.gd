extends Grenade
class_name HEGrenade

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

@export_group("Explosion Properties")
@export var explosion_damage: int = 100
@export var damage_radius: float = 5.0  # tiles
@export var direct_hit_multiplier: float = 3.0
@export var direct_hit_threshold: float = 0.3  # tiles

@export_group("Shrapnel Properties")
@export var shrapnel_count: int = 4
@export var shrapnel_damage: int = 12
@export var shrapnel_speed: float = 300.0

@export_group("Effects")
@export var explosion_scale: float = 1.0
@export var camera_shake_intensity: float = 0.8

var explosion_pending: bool = false
var tile_size: float = 32.0

static var explosion_effect: PackedScene
static var shrapnel_scene: PackedScene

const BODY_ZONES = ["head", "chest", "groin", "l_arm", "r_arm", "l_leg", "r_leg"]

func _init():
	super._init()
	obj_name = "M40_HEDP_grenade"
	obj_desc = "A small, but deceptively strong high explosive grenade that has been phasing out the M15 fragmentation grenades. Capable of being loaded in any grenade launcher, or thrown by hand."
	grenade_type = GrenadeType.EXPLOSIVE
	det_time = 4.0
	dangerous = true
	explosion_range = 3
	throwforce = 10
	
	if not explosion_effect:
		explosion_effect = preload("res://Scenes/Effects/Explosion.tscn")
	if not shrapnel_scene:
		shrapnel_scene = preload("res://Scenes/Effects/Shrapnel.tscn")

func explode() -> void:
	if not active or explosion_pending:
		return
	
	explosion_pending = true
	var explosion_pos = global_position
	
	super.explode()
	
	# Single RPC for entire explosion
	if multiplayer.has_multiplayer_peer():
		sync_explosion.rpc(explosion_pos)
	else:
		execute_explosion(explosion_pos)

@rpc("any_peer", "call_local", "reliable")
func sync_explosion(explosion_pos: Vector2):
	execute_explosion(explosion_pos)

func execute_explosion(explosion_pos: Vector2):
	create_explosion_effect(explosion_pos)
	apply_explosion_damage(explosion_pos)
	create_shrapnel(explosion_pos)
	create_camera_shake()
	
	var cleanup_timer = Timer.new()
	cleanup_timer.wait_time = 0.1
	cleanup_timer.one_shot = true
	cleanup_timer.timeout.connect(queue_free)
	add_child(cleanup_timer)
	cleanup_timer.start()

func create_explosion_effect(pos: Vector2):
	if not explosion_effect:
		return
	
	var effect = explosion_effect.instantiate()
	get_tree().current_scene.add_child(effect)
	effect.global_position = pos
	effect.scale = Vector2(explosion_scale, explosion_scale)
	
	# Simple particle configuration
	if effect.has_method("set_amount"):
		effect.set_amount(40)
	elif "amount" in effect:
		effect.amount = 40
	
	# Auto-cleanup
	var timer = Timer.new()
	timer.wait_time = 2.0
	timer.one_shot = true
	timer.timeout.connect(effect.queue_free)
	effect.add_child(timer)
	timer.start()

func apply_explosion_damage(explosion_pos: Vector2):
	var max_range = damage_radius * tile_size
	var entities = get_entities_in_range(explosion_pos, max_range)
	
	for entity in entities:
		var health_system = get_health_system(entity)
		if not health_system:
			continue
		
		var distance = entity.global_position.distance_to(explosion_pos)
		var distance_tiles = distance / tile_size
		
		var damage_multiplier = calculate_damage_multiplier(distance_tiles)
		var final_damage = explosion_damage * damage_multiplier
		
		var damage_zone = get_closest_body_zone(entity, explosion_pos)
		
		# Apply primary blast damage
		health_system.apply_damage(
			final_damage,
			DamageType.BRUTE,
			40.0,  # penetration
			damage_zone,
			self
		)
		
		# Apply burn damage for close range
		if distance_tiles <= 2.0:
			health_system.apply_damage(
				final_damage * 0.3,
				DamageType.BURN,
				20.0,
				damage_zone,
				self
			)
		
		# Apply knockback
		if entity.has_method("apply_knockback"):
			var knockback_dir = (entity.global_position - explosion_pos).normalized()
			var knockback_force = 300.0 * damage_multiplier
			entity.apply_knockback(knockback_dir, knockback_force)
		
		# Status effects for close hits
		if distance_tiles <= 1.5 and health_system.has_method("add_status_effect"):
			health_system.add_status_effect("stunned", 3.0 * damage_multiplier, 2.0)
			if distance_tiles <= 1.0:
				health_system.add_status_effect("deaf", 10.0, 1.0)

func calculate_damage_multiplier(distance_tiles: float) -> float:
	# Direct hit bonus
	if distance_tiles <= direct_hit_threshold:
		return direct_hit_multiplier
	
	# Linear falloff within damage radius
	if distance_tiles <= damage_radius:
		var falloff = 1.0 - (distance_tiles / damage_radius)
		return max(0.1, falloff)
	
	return 0.0

func get_closest_body_zone(entity: Node, explosion_pos: Vector2) -> String:
	var direction = (explosion_pos - entity.global_position).normalized()
	var angle = direction.angle()
	
	# Simple zone targeting based on explosion angle
	if abs(angle) < PI/4:  # Front
		return "chest"
	elif abs(angle) > 3*PI/4:  # Back
		return "chest"
	elif angle > 0:  # Right side
		return "r_arm"
	else:  # Left side
		return "l_arm"

func create_shrapnel(explosion_pos: Vector2):
	if not shrapnel_scene:
		return
	
	var angle_step = TAU / shrapnel_count
	
	for i in range(shrapnel_count):
		var angle = angle_step * i + randf_range(-0.3, 0.3)
		var direction = Vector2(cos(angle), sin(angle))
		
		var shrapnel = shrapnel_scene.instantiate()
		get_tree().current_scene.add_child(shrapnel)
		shrapnel.global_position = explosion_pos
		
		var velocity = direction * shrapnel_speed * randf_range(0.8, 1.2)
		
		# Set shrapnel properties
		if "velocity" in shrapnel:
			shrapnel.velocity = velocity
		elif "linear_velocity" in shrapnel:
			shrapnel.linear_velocity = velocity
		elif shrapnel.has_method("launch"):
			shrapnel.launch(direction, shrapnel_speed)
		
		if "damage" in shrapnel:
			shrapnel.damage = shrapnel_damage
		if "damage_type" in shrapnel:
			shrapnel.damage_type = DamageType.BRUTE
		if "penetration" in shrapnel:
			shrapnel.penetration = 15.0
		
		# Auto-cleanup
		var timer = Timer.new()
		timer.wait_time = 3.0
		timer.one_shot = true
		timer.timeout.connect(shrapnel.queue_free)
		shrapnel.add_child(timer)
		timer.start()

func create_camera_shake(intensity: float = 1.0):
	var camera = get_viewport().get_camera_2d()
	if not camera:
		return
	
	var tween = create_tween()
	var original_pos = camera.global_position
	
	for i in range(4):
		var shake_offset = Vector2(
			randf_range(-camera_shake_intensity * 8, camera_shake_intensity * 8),
			randf_range(-camera_shake_intensity * 8, camera_shake_intensity * 8)
		)
		tween.tween_property(camera, "global_position", original_pos + shake_offset, 0.05)
	
	tween.tween_property(camera, "global_position", original_pos, 0.1)

func get_entities_in_range(center: Vector2, radius: float) -> Array:
	var entities = []
	var space_state = get_world_2d().direct_space_state
	
	# Use physics query for better performance
	var query = PhysicsShapeQueryParameters2D.new()
	var circle = CircleShape2D.new()
	circle.radius = radius
	query.shape = circle
	query.transform.origin = center
	query.collision_mask = 1  # Adjust based on your collision layers
	
	var results = space_state.intersect_shape(query)
	
	for result in results:
		var entity = result.collider
		if entity and entity.is_in_group("damageable"):
			entities.append(entity)
	
	# Fallback to group search if physics query fails
	if entities.is_empty():
		var groups = ["players", "entities", "mobs"]
		for group_name in groups:
			var group_entities = get_tree().get_nodes_in_group(group_name)
			for entity in group_entities:
				if entity.global_position.distance_to(center) <= radius:
					entities.append(entity)
	
	return entities

func get_health_system(entity: Node) -> Node:
	if "health_system" in entity and entity.health_system:
		return entity.health_system
	elif entity.has_node("HealthSystem"):
		return entity.get_node("HealthSystem")
	return null

func throw_impact(hit_atom, speed: float = 5) -> bool:
	var result = super.throw_impact(hit_atom, speed)
	
	# Impact detonation chance
	if launched and hit_atom and speed > 15.0:
		var detonation_chance = min(0.4, speed / 30.0)
		if not active and randf() < detonation_chance:
			activate()
	
	return result

func serialize() -> Dictionary:
	var data = super.serialize()
	data["explosion_damage"] = explosion_damage
	data["damage_radius"] = damage_radius
	data["direct_hit_multiplier"] = direct_hit_multiplier
	data["shrapnel_count"] = shrapnel_count
	data["shrapnel_damage"] = shrapnel_damage
	data["explosion_pending"] = explosion_pending
	return data

func deserialize(data: Dictionary):
	super.deserialize(data)
	if "explosion_damage" in data: explosion_damage = data.explosion_damage
	if "damage_radius" in data: damage_radius = data.damage_radius
	if "direct_hit_multiplier" in data: direct_hit_multiplier = data.direct_hit_multiplier
	if "shrapnel_count" in data: shrapnel_count = data.shrapnel_count
	if "shrapnel_damage" in data: shrapnel_damage = data.shrapnel_damage
	if "explosion_pending" in data: explosion_pending = data.explosion_pending
