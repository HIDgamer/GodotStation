extends Area2D
class_name Projectile

signal projectile_hit(target, damage)
signal projectile_missed()

@export var damage: float = 20.0
@export var speed: float = 500.0
@export var max_distance: float = 1000.0
@export var penetration: int = 0
@export var accuracy: float = 100.0
@export var lifetime: float = 5.0

var direction: Vector2 = Vector2.RIGHT
var distance_traveled: float = 0.0
var firer = null
var source_weapon = null
var target_position: Vector2 = Vector2.ZERO
var hit_targets: Array = []
var hits_remaining: int = 0

var sprite: Sprite2D
var trail_particles: GPUParticles2D

func _ready():
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	
	setup_visuals()
	
	collision_layer = 0
	collision_mask = 1
	
	hits_remaining = max(1, penetration + 1)
	
	get_tree().create_timer(lifetime).timeout.connect(func(): destroy_projectile())

func setup_visuals():
	sprite = Sprite2D.new()
	sprite.name = "ProjectileSprite"
	add_child(sprite)
	
	if ResourceLoader.exists("res://Assets/Icons/Items/Guns/Particals/Bullet.png"):
		sprite.texture = preload("res://Assets/Icons/Items/Guns/Particals/Bullet.png")
	else:
		var image = Image.create(8, 2, false, Image.FORMAT_RGBA8)
		image.fill(Color.YELLOW)
		var texture = ImageTexture.new()
		texture.set_image(image)
		sprite.texture = texture
	
	var collision_shape = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(8, 2)
	collision_shape.shape = shape
	collision_shape.name = "ProjectileCollision"
	add_child(collision_shape)
	
	create_trail_effect()

func create_trail_effect():
	trail_particles = GPUParticles2D.new()
	trail_particles.name = "TrailParticles"
	trail_particles.emitting = true
	trail_particles.amount = 50
	
	var material = ParticleProcessMaterial.new()
	material.direction = Vector3(-1, 0, 0)
	material.initial_velocity_min = 20.0
	material.initial_velocity_max = 40.0
	material.scale_min = 0.1
	material.scale_max = 0.3
	
	trail_particles.process_material = material
	add_child(trail_particles)

func fire_at(target_pos: Vector2, firing_entity, weapon = null):
	firer = firing_entity
	source_weapon = weapon
	target_position = target_pos
	
	direction = (target_pos - global_position).normalized()
	var rotation_angle = direction.angle()
	
	rotation = rotation_angle
	if sprite:
		sprite.rotation = 0
	var collision_shape = get_node_or_null("ProjectileCollision")
	if collision_shape:
		collision_shape.rotation = 0
	
	set_physics_process(true)

func _physics_process(delta):
	var movement = direction * speed * delta
	position += movement
	distance_traveled += movement.length()
	
	if trail_particles and trail_particles.process_material:
		var material = trail_particles.process_material as ParticleProcessMaterial
		var trail_dir = -direction
		material.direction = Vector3(trail_dir.x, trail_dir.y, 0)
	
	if distance_traveled >= max_distance:
		destroy_projectile()

func _on_body_entered(body):
	if not should_hit_target(body):
		return
	
	if body.has_method("is_wall_at") or body.name.contains("Wall") or body.name.contains("wall"):
		hit_wall(body)
		return
	
	hit_target(body)

func _on_area_entered(area):
	var body = area.get_parent()
	if not should_hit_target(body):
		return
	
	hit_target(body)

func should_hit_target(target) -> bool:
	if target == firer:
		return false
	
	if target in hit_targets and penetration <= 0:
		return false
	
	if target is Projectile:
		return false
	
	return true

func hit_wall(wall):
	play_hit_effects(wall)
	destroy_projectile()

func hit_target(target):
	hit_targets.append(target)
	hits_remaining -= 1
	
	var actual_damage = calculate_damage(target)
	apply_damage_to_target(target, actual_damage)
	
	play_hit_effects(target)
	emit_signal("projectile_hit", target, actual_damage)
	
	if hits_remaining <= 0:
		destroy_projectile()
	else:
		damage *= 0.8

func calculate_damage(target) -> float:
	var actual_damage = damage
	
	var falloff_start = max_distance * 0.3
	if distance_traveled > falloff_start:
		var falloff_factor = 1.0 - ((distance_traveled - falloff_start) / (max_distance - falloff_start)) * 0.5
		actual_damage *= max(0.1, falloff_factor)
	
	if target.has_method("get_armor_value"):
		var armor = target.get_armor_value("ballistic")
		actual_damage = apply_armor_reduction(actual_damage, armor)
	
	return actual_damage

func apply_armor_reduction(damage_value: float, armor_value: float) -> float:
	var reduction = armor_value / (armor_value + 50.0)
	return damage_value * (1.0 - reduction)

func apply_damage_to_target(target, damage_amount: int):
	var health_system = null
	
	if target:
		health_system = target.get_node("HealthSystem")
	elif target.get_parent() and target.get_parent().has_node("HealthSystem"):
		health_system = target.get_parent().get_node("HealthSystem")
	
	if health_system and health_system.has_method("apply_damage"):
		var damage_type = health_system.DamageType.BRUTE if "DamageType" in health_system else 0
		health_system.apply_damage(damage_amount, damage_type, 0, "", firer)
	elif target.has_method("take_damage"):
		target.take_damage(damage_amount, 1, "projectile", true, penetration, firer)
	elif target.has_method("apply_damage"):
		target.apply_damage(damage_amount, 1)
	elif target.has_method("damage"):
		target.damage(damage_amount)
	elif "health" in target:
		target.health -= damage_amount
		if target.health <= 0 and target.has_method("die"):
			target.die()

func play_hit_effects(target):
	play_hit_sound(target)
	apply_screen_shake_to_nearby_players()

func play_hit_sound(target):
	var sound_name = "bullet_hit"
	
	if target.has_method("get_material_type"):
		match target.get_material_type():
			"metal":
				sound_name = "bullet_hit_metal"
			"flesh":
				sound_name = "bullet_hit_flesh"
			"wood":
				sound_name = "bullet_hit_wood"
	
	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_positioned_sound"):
		audio_manager.play_positioned_sound(sound_name, global_position, 0.6)

func apply_screen_shake_to_nearby_players():
	var players = get_tree().get_nodes_in_group("players")
	var shake_radius = 200.0
	
	for player in players:
		if player.global_position.distance_to(global_position) <= shake_radius:
			if player.has_method("add_screen_shake"):
				player.add_screen_shake(0.5)

func destroy_projectile():
	if trail_particles:
		trail_particles.emitting = false
	
	create_destruction_effect()
	queue_free()

func create_destruction_effect():
	pass

func get_damage() -> float:
	return damage

func get_penetration() -> int:
	return penetration

func get_firer():
	return firer

func get_source_weapon():
	return source_weapon

func set_damage(new_damage: float):
	damage = new_damage

func set_penetration(new_penetration: int):
	penetration = new_penetration
	hits_remaining = max(1, penetration + 1)

func set_speed(new_speed: float):
	speed = new_speed

func set_accuracy(new_accuracy: float):
	accuracy = clamp(new_accuracy, 0.0, 100.0)

@rpc("any_peer", "call_local", "reliable")
func sync_projectile_fired(start_pos: Vector2, target_pos: Vector2, firer_id: String):
	global_position = start_pos
	fire_at(target_pos, get_node_by_id(firer_id))

@rpc("any_peer", "call_local", "reliable") 
func sync_projectile_hit(hit_pos: Vector2, target_id: String, damage_dealt: float):
	play_hit_sound(get_node_by_id(target_id))

func get_node_by_id(node_id: String):
	return null
