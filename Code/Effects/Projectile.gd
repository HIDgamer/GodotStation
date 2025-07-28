extends Area2D
class_name Projectile

signal projectile_hit(target, damage)
signal projectile_missed()

# Projectile properties
@export var damage: float = 20.0
@export var speed: float = 500.0
@export var max_distance: float = 1000.0
@export var penetration: int = 0
@export var accuracy: float = 85.0
@export var lifetime: float = 5.0

# Projectile state
var direction: Vector2 = Vector2.RIGHT
var distance_traveled: float = 0.0
var firer = null
var source_weapon = null
var target_position: Vector2 = Vector2.ZERO
var hit_targets: Array = []

# Visual components
var sprite: Sprite2D
var trail_particles: GPUParticles2D

func _ready():
	# Set up collision
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	
	# Create visual components
	setup_visuals()
	
	# Set collision layers
	collision_layer = 0  # Projectiles don't collide with each other
	collision_mask = 1   # Collide with world/entities
	
	# Auto-destroy after lifetime
	get_tree().create_timer(lifetime).timeout.connect(func(): destroy_projectile())

func setup_visuals():
	"""Set up projectile visual components"""
	# Create sprite
	sprite = Sprite2D.new()
	sprite.name = "ProjectileSprite"
	add_child(sprite)
	
	# Load default bullet texture
	if ResourceLoader.exists("res://Assets/Weapons/Particals/Bullet.png"):
		sprite.texture = preload("res://Assets/Weapons/Particals/Bullet.png")
	else:
		# Create a simple colored rectangle as fallback
		var image = Image.create(8, 2, false, Image.FORMAT_RGBA8)
		image.fill(Color.YELLOW)
		var texture = ImageTexture.new()
		texture.set_image(image)
		sprite.texture = texture
	
	# Create collision shape
	var collision_shape = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(8, 2)
	collision_shape.shape = shape
	collision_shape.name = "ProjectileCollision"
	add_child(collision_shape)
	
	# Add trail particles
	create_trail_effect()

func create_trail_effect():
	"""Create particle trail effect"""
	trail_particles = GPUParticles2D.new()
	trail_particles.name = "TrailParticles"
	trail_particles.emitting = true
	trail_particles.amount = 50
	
	# Configure particle material
	var material = ParticleProcessMaterial.new()
	material.direction = Vector3(-1, 0, 0)  # Trail behind
	material.initial_velocity_min = 20.0
	material.initial_velocity_max = 40.0
	material.scale_min = 0.1
	material.scale_max = 0.3
	
	trail_particles.process_material = material
	
	add_child(trail_particles)

func fire_at(target_pos: Vector2, firing_entity, weapon = null):
	"""Fire projectile at target position"""
	firer = firing_entity
	source_weapon = weapon
	target_position = target_pos
	
	# Calculate direction
	direction = (target_pos - global_position).normalized()
	var rotation_angle = direction.angle()
	
	# Apply rotation to sprite
	sprite.rotation = rotation_angle
	# Also rotate collision shape to match
	var collision_shape = get_node("ProjectileCollision")
	if collision_shape:
		collision_shape.rotation = rotation_angle
	
	# Apply scatter based on accuracy
	apply_scatter()
	
	# Start movement
	set_physics_process(true)

func apply_scatter():
	"""Apply accuracy-based scatter to direction"""
	var scatter_angle = deg_to_rad((100.0 - accuracy) * 2.0)  # Higher accuracy = less scatter
	var random_scatter = randf_range(-scatter_angle, scatter_angle)
	direction = direction.rotated(random_scatter)
	
	# Update visual rotation after scatter
	var rotation_angle = direction.angle()
	sprite.rotation = rotation_angle
	
	var collision_shape = get_node("ProjectileCollision")
	if collision_shape:
		collision_shape.rotation = rotation_angle

func _physics_process(delta):
	"""Move projectile each frame"""
	var movement = direction * speed * delta
	position += movement
	distance_traveled += movement.length()
	
	# Update trail particles direction if they exist
	if trail_particles and trail_particles.process_material:
		var material = trail_particles.process_material as ParticleProcessMaterial
		# Trail should go opposite to movement direction
		var trail_dir = -direction
		material.direction = Vector3(trail_dir.x, trail_dir.y, 0)
	
	# Check if projectile has traveled too far
	if distance_traveled >= max_distance:
		destroy_projectile()

func _on_body_entered(body):
	"""Handle collision with physics body"""
	if not should_hit_target(body):
		return
	
	hit_target(body)

func _on_area_entered(area):
	"""Handle collision with area"""
	var body = area.get_parent()
	if not should_hit_target(body):
		return
	
	hit_target(body)

func should_hit_target(target) -> bool:
	"""Check if projectile should hit this target"""
	# Don't hit firer
	if target == firer:
		return false
	
	# Don't hit targets we've already hit (unless penetrating)
	if target in hit_targets and penetration <= 0:
		return false
	
	# Don't hit projectiles
	if target is Projectile:
		return false
	
	return true

func hit_target(target):
	"""Handle hitting a target"""
	hit_targets.append(target)
	
	# Apply damage
	var actual_damage = calculate_damage(target)
	apply_damage_to_target(target, actual_damage)
	
	# Play hit effects
	play_hit_effects(target)
	
	# Emit signal
	emit_signal("projectile_hit", target, actual_damage)
	
	# Check if projectile should stop
	if penetration <= 0 or hit_targets.size() >= penetration:
		destroy_projectile()
	else:
		# Reduce damage for penetration
		damage *= 0.8

func calculate_damage(target) -> float:
	"""Calculate actual damage to target"""
	var actual_damage = damage
	
	# Apply distance falloff
	var falloff_start = max_distance * 0.3  # Start falloff at 30% of max range
	if distance_traveled > falloff_start:
		var falloff_factor = 1.0 - ((distance_traveled - falloff_start) / (max_distance - falloff_start)) * 0.5
		actual_damage *= max(0.1, falloff_factor)  # Minimum 10% damage
	
	# Apply armor reduction if target has armor
	if target.has_method("get_armor_value"):
		var armor = target.get_armor_value("ballistic")
		actual_damage = apply_armor_reduction(actual_damage, armor)
	
	return actual_damage

func apply_armor_reduction(damage_value: float, armor_value: float) -> float:
	"""Apply armor reduction to damage"""
	# Simple armor calculation - could be more complex
	var reduction = armor_value / (armor_value + 50.0)  # Diminishing returns
	return damage_value * (1.0 - reduction)

func apply_damage_to_target(target, damage_amount: float):
	"""Apply damage to the target"""
	if target.has_method("take_damage"):
		target.take_damage(damage_amount, "ballistic", "projectile", true, penetration, firer)
	elif target.has_method("apply_damage"):
		target.apply_damage(damage_amount, "brute")
	elif target.has_method("damage"):
		target.damage(damage_amount)
	
	# If target has health, reduce it directly as fallback
	if "health" in target:
		target.health -= damage_amount
		if target.health <= 0 and target.has_method("die"):
			target.die()

func play_hit_effects(target):
	"""Play visual and audio effects for hit"""
	# Create hit effect
	create_hit_effect(target.global_position)
	
	# Play hit sound
	play_hit_sound(target)
	
	# Screen shake for nearby players
	apply_screen_shake_to_nearby_players()

func create_hit_effect(hit_position: Vector2):
	"""Create visual hit effect"""
	# Detect impact type from target
	var impact_type = BulletHit.ImpactType.METAL  # Default
	if hit_targets.size() > 0:
		var last_target = hit_targets[-1]
		impact_type = BulletHit.detect_impact_type_from_target(last_target)
	
	# Create impact effect
	if ResourceLoader.exists("res://Scenes/Effects/BulletHit.tscn"):
		var hit_effect_scene = preload("res://Scenes/Effects/BulletHit.tscn")
		var hit_effect = hit_effect_scene.instantiate()
		hit_effect.set_impact_type(impact_type)
		
		get_tree().current_scene.add_child(hit_effect)
		hit_effect.global_position = hit_position
		hit_effect.play_effect(direction.angle())
	else:
		# Fallback to static method
		BulletHit.create_impact_effect(impact_type, hit_position, direction.angle(), get_tree().current_scene)

func play_hit_sound(target):
	"""Play appropriate hit sound"""
	var sound_name = "bullet_hit"
	
	# Choose sound based on target material
	if target.has_method("get_material_type"):
		match target.get_material_type():
			"metal":
				sound_name = "bullet_hit_metal"
			"flesh":
				sound_name = "bullet_hit_flesh"
			"wood":
				sound_name = "bullet_hit_wood"
	
	# Play sound at hit location
	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_positioned_sound"):
		audio_manager.play_positioned_sound(sound_name, global_position, 0.6)

func apply_screen_shake_to_nearby_players():
	"""Apply screen shake to nearby players"""
	var players = get_tree().get_nodes_in_group("players")
	var shake_radius = 200.0
	
	for player in players:
		if player.global_position.distance_to(global_position) <= shake_radius:
			if player.has_method("add_screen_shake"):
				player.add_screen_shake(0.5)

func destroy_projectile():
	"""Destroy the projectile"""
	# Stop trail particles
	if trail_particles:
		trail_particles.emitting = false
	
	# Create destruction effect
	create_destruction_effect()
	
	# Remove from scene
	queue_free()

func create_destruction_effect():
	"""Create effect when projectile is destroyed"""
	# Could add spark effects, smoke, etc.
	pass

# Utility functions
func get_damage() -> float:
	"""Get current damage value"""
	return damage

func get_penetration() -> int:
	"""Get penetration value"""
	return penetration

func get_firer():
	"""Get the entity that fired this projectile"""
	return firer

func get_source_weapon():
	"""Get the weapon that fired this projectile"""
	return source_weapon

func set_damage(new_damage: float):
	"""Set projectile damage"""
	damage = new_damage

func set_penetration(new_penetration: int):
	"""Set projectile penetration"""
	penetration = new_penetration

func set_speed(new_speed: float):
	"""Set projectile speed"""
	speed = new_speed

func set_accuracy(new_accuracy: float):
	"""Set projectile accuracy"""
	accuracy = clamp(new_accuracy, 0.0, 100.0)

# Network synchronization for multiplayer
@rpc("any_peer", "call_local", "reliable")
func sync_projectile_fired(start_pos: Vector2, target_pos: Vector2, firer_id: String):
	"""Synchronize projectile firing across network"""
	global_position = start_pos
	fire_at(target_pos, get_node_by_id(firer_id))

@rpc("any_peer", "call_local", "reliable") 
func sync_projectile_hit(hit_pos: Vector2, target_id: String, damage_dealt: float):
	"""Synchronize projectile hit across network"""
	create_hit_effect(hit_pos)
	play_hit_sound(get_node_by_id(target_id))

func get_node_by_id(node_id: String):
	"""Get node by network ID - implement based on your networking system"""
	return null
