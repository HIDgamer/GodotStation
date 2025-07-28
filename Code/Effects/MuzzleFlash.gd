extends Node2D
class_name MuzzleFlash

# Visual components
var flash_sprite: Sprite2D
var flash_light: PointLight2D
var flash_particles: GPUParticles2D
var smoke_particles: GPUParticles2D

# Effect properties
@export var flash_duration: float = 0.1
@export var light_intensity: float = 2.0
@export var light_range: float = 100.0
@export var particle_count: int = 50
@export var flash_color: Color = Color.ORANGE
@export var smoke_color: Color = Color.GRAY

# Flash variants for different weapon types
enum FlashType {
	PISTOL,
	RIFLE,
	SHOTGUN,
	SNIPER,
	HEAVY
}

@export var flash_type: FlashType = FlashType.PISTOL

func _ready():
	setup_components()
	
	# Auto-destroy after animation
	var cleanup_timer = Timer.new()
	cleanup_timer.wait_time = 2.0
	cleanup_timer.one_shot = true
	cleanup_timer.timeout.connect(cleanup_effect)
	add_child(cleanup_timer)
	cleanup_timer.start()

func setup_components():
	"""Initialize all visual components"""
	create_flash_sprite()
	create_flash_light()
	create_flash_particles()
	create_smoke_particles()

func create_flash_sprite():
	"""Create the main flash sprite"""
	flash_sprite = Sprite2D.new()
	flash_sprite.name = "FlashSprite"
	add_child(flash_sprite)
	
	# Create flash texture based on type
	flash_sprite.texture = create_flash_texture()
	flash_sprite.modulate = flash_color
	flash_sprite.modulate.a = 0.0  # Start invisible
	
	# Set blend mode for additive effect
	flash_sprite.material = create_additive_material()

func create_flash_texture() -> ImageTexture:
	"""Create procedural flash texture"""
	var size = get_flash_size()
	var image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	
	# Create radial gradient flash
	var center = Vector2(size.x / 2, size.y / 2)
	var max_radius = min(size.x, size.y) / 2
	
	for x in range(size.x):
		for y in range(size.y):
			var distance = Vector2(x, y).distance_to(center)
			var intensity = 1.0 - (distance / max_radius)
			intensity = max(0.0, intensity)
			
			# Create star-like pattern
			var angle = atan2(y - center.y, x - center.x)
			var star_intensity = create_star_pattern(angle, 6) # 6 points
			intensity *= star_intensity
			
			# Apply falloff
			intensity = pow(intensity, 0.5)  # Softer falloff
			
			var color = Color.WHITE
			color.a = intensity
			image.set_pixel(x, y, color)
	
	var texture = ImageTexture.new()
	texture.set_image(image)
	return texture

func get_flash_size() -> Vector2i:
	"""Get flash size based on weapon type"""
	match flash_type:
		FlashType.PISTOL:
			return Vector2i(32, 16)
		FlashType.RIFLE:
			return Vector2i(48, 24)
		FlashType.SHOTGUN:
			return Vector2i(64, 32)
		FlashType.SNIPER:
			return Vector2i(56, 28)
		FlashType.HEAVY:
			return Vector2i(80, 40)
		_:
			return Vector2i(32, 16)

func create_star_pattern(angle: float, points: int) -> float:
	"""Create star-like intensity pattern"""
	var normalized_angle = fmod(angle + PI, 2 * PI / points)
	var point_angle = PI / points
	var intensity = 1.0 - abs(normalized_angle - point_angle) / point_angle
	return max(0.3, intensity)  # Minimum intensity for smooth look

func create_additive_material() -> CanvasItemMaterial:
	"""Create additive blend material for flash effect"""
	var material = CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return material

func create_flash_light():
	"""Create point light for flash illumination"""
	flash_light = PointLight2D.new()
	flash_light.name = "FlashLight"
	add_child(flash_light)
	
	# Configure light properties
	flash_light.enabled = true
	flash_light.energy = 0.0  # Start at 0
	flash_light.range_item_cull_mask = 1
	flash_light.color = flash_color
	flash_light.texture_scale = get_light_scale()
	
	# Create light texture
	flash_light.texture = create_light_texture()

func get_light_scale() -> float:
	"""Get light scale based on weapon type"""
	match flash_type:
		FlashType.PISTOL:
			return 0.5
		FlashType.RIFLE:
			return 0.7
		FlashType.SHOTGUN:
			return 1.0
		FlashType.SNIPER:
			return 0.8
		FlashType.HEAVY:
			return 1.2
		_:
			return 0.5

func create_light_texture() -> ImageTexture:
	"""Create soft circular light texture"""
	var size = 64
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = Vector2(size / 2, size / 2)
	var radius = size / 2
	
	for x in range(size):
		for y in range(size):
			var distance = Vector2(x, y).distance_to(center)
			var intensity = 1.0 - (distance / radius)
			intensity = max(0.0, intensity)
			intensity = pow(intensity, 2)  # Smooth falloff
			
			var color = Color.WHITE
			color.a = intensity
			image.set_pixel(x, y, color)
	
	var texture = ImageTexture.new()
	texture.set_image(image)
	return texture

func create_flash_particles():
	"""Create spark particles for flash effect"""
	flash_particles = GPUParticles2D.new()
	flash_particles.name = "FlashParticles"
	add_child(flash_particles)
	
	# Configure particles
	flash_particles.emitting = false
	flash_particles.amount = get_particle_count()
	flash_particles.lifetime = 0.3
	flash_particles.one_shot = true
	flash_particles.explosiveness = 1.0
	
	# Create process material
	var material = ParticleProcessMaterial.new()
	
	# Emission
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.direction = Vector3(1, 0, 0)  # Forward direction
	material.spread = get_particle_spread()
	
	# Velocity
	material.initial_velocity_min = 50.0
	material.initial_velocity_max = 150.0
	
	# Scale
	material.scale_min = 0.1
	material.scale_max = 0.3
	material.scale_over_velocity_min = 0.0
	material.scale_over_velocity_max = 0.1
	
	# Color
	material.color = flash_color
	material.color_ramp = create_flash_color_ramp()
	
	# Physics
	material.gravity = Vector3(0, 50, 0)  # Slight downward pull
	material.linear_accel_min = -20.0
	material.linear_accel_max = -50.0
	
	flash_particles.process_material = material
	flash_particles.texture = create_spark_texture()

func get_particle_count() -> int:
	"""Get particle count based on weapon type"""
	match flash_type:
		FlashType.PISTOL:
			return 20
		FlashType.RIFLE:
			return 35
		FlashType.SHOTGUN:
			return 60
		FlashType.SNIPER:
			return 25
		FlashType.HEAVY:
			return 80
		_:
			return 20

func get_particle_spread() -> float:
	"""Get particle spread angle based on weapon type"""
	match flash_type:
		FlashType.PISTOL:
			return 30.0
		FlashType.RIFLE:
			return 25.0
		FlashType.SHOTGUN:
			return 45.0
		FlashType.SNIPER:
			return 20.0
		FlashType.HEAVY:
			return 35.0
		_:
			return 30.0

func create_flash_color_ramp() -> Gradient:
	"""Create color gradient for flash particles"""
	var gradient = Gradient.new()
	gradient.add_point(0.0, flash_color)
	gradient.add_point(0.7, flash_color * 0.8)
	gradient.add_point(1.0, Color.TRANSPARENT)
	return gradient

func create_spark_texture() -> ImageTexture:
	"""Create small spark texture for particles"""
	var size = 4
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	
	var texture = ImageTexture.new()
	texture.set_image(image)
	return texture

func create_smoke_particles():
	"""Create smoke particles that appear after flash"""
	smoke_particles = GPUParticles2D.new()
	smoke_particles.name = "SmokeParticles"
	add_child(smoke_particles)
	
	# Configure smoke
	smoke_particles.emitting = false
	smoke_particles.amount = get_smoke_count()
	smoke_particles.lifetime = 1.5
	smoke_particles.one_shot = true
	smoke_particles.explosiveness = 0.3
	
	# Create smoke material
	var material = ParticleProcessMaterial.new()
	
	# Emission
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.direction = Vector3(1, -0.2, 0)  # Slightly upward
	material.spread = 20.0
	
	# Velocity
	material.initial_velocity_min = 10.0
	material.initial_velocity_max = 30.0
	
	# Scale
	material.scale_min = 0.2
	material.scale_max = 0.5
	material.scale_over_velocity_min = 0.5
	material.scale_over_velocity_max = 1.0
	
	# Color
	material.color = smoke_color
	material.color_ramp = create_smoke_color_ramp()
	
	# Physics
	material.gravity = Vector3(0, -10, 0)  # Smoke rises
	material.linear_accel_min = -5.0
	material.linear_accel_max = -10.0
	
	smoke_particles.process_material = material
	smoke_particles.texture = create_smoke_texture()

func get_smoke_count() -> int:
	"""Get smoke particle count based on weapon type"""
	match flash_type:
		FlashType.PISTOL:
			return 10
		FlashType.RIFLE:
			return 15
		FlashType.SHOTGUN:
			return 25
		FlashType.SNIPER:
			return 12
		FlashType.HEAVY:
			return 30
		_:
			return 10

func create_smoke_color_ramp() -> Gradient:
	"""Create color gradient for smoke particles"""
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color.TRANSPARENT)
	gradient.add_point(0.2, smoke_color * 0.8)
	gradient.add_point(0.6, smoke_color * 0.5)
	gradient.add_point(1.0, Color.TRANSPARENT)
	return gradient

func create_smoke_texture() -> ImageTexture:
	"""Create soft circular texture for smoke"""
	var size = 16
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = Vector2(size / 2, size / 2)
	var radius = size / 2
	
	for x in range(size):
		for y in range(size):
			var distance = Vector2(x, y).distance_to(center)
			var intensity = 1.0 - (distance / radius)
			intensity = max(0.0, intensity)
			intensity = pow(intensity, 3)  # Very soft edges
			
			var color = Color.WHITE
			color.a = intensity * 0.6  # Semi-transparent
			image.set_pixel(x, y, color)
	
	var texture = ImageTexture.new()
	texture.set_image(image)
	return texture

func show_flash(weapon_angle: float = 0.0):
	"""Display the muzzle flash effect"""
	# Set rotation to match weapon direction
	rotation = weapon_angle
	
	# Animate flash sprite
	animate_flash_sprite()
	
	# Animate light
	animate_flash_light()
	
	# Start particles
	start_particles()

func animate_flash_sprite():
	"""Animate the main flash sprite"""
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Fade in quickly, fade out slower
	tween.tween_property(flash_sprite, "modulate:a", 1.0, flash_duration * 0.2)
	tween.tween_property(flash_sprite, "modulate:a", 0.0, flash_duration * 0.8)
	
	# Scale effect
	flash_sprite.scale = Vector2(0.5, 0.5)
	tween.tween_property(flash_sprite, "scale", Vector2(1.2, 1.0), flash_duration * 0.3)
	tween.tween_property(flash_sprite, "scale", Vector2(0.8, 0.8), flash_duration * 0.7)

func animate_flash_light():
	"""Animate the point light"""
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Light intensity
	var max_energy = light_intensity * get_light_intensity_multiplier()
	tween.tween_property(flash_light, "energy", max_energy, flash_duration * 0.1)
	tween.tween_property(flash_light, "energy", 0.0, flash_duration * 0.9)
	
	# Light range flicker
	var base_range = light_range
	tween.tween_method(flicker_light_range, base_range, base_range * 0.8, flash_duration)

func get_light_intensity_multiplier() -> float:
	"""Get light intensity multiplier based on weapon type"""
	match flash_type:
		FlashType.PISTOL:
			return 1.0
		FlashType.RIFLE:
			return 1.3
		FlashType.SHOTGUN:
			return 1.8
		FlashType.SNIPER:
			return 1.1
		FlashType.HEAVY:
			return 2.0
		_:
			return 1.0

func flicker_light_range(range_value: float):
	"""Create flickering effect for light range"""
	var flicker = randf_range(0.9, 1.1)
	flash_light.texture_scale = range_value * flicker / 100.0

func start_particles():
	"""Start particle effects"""
	# Start flash particles immediately
	flash_particles.restart()
	flash_particles.emitting = true
	
	# Start smoke particles with slight delay
	var smoke_timer = Timer.new()
	smoke_timer.wait_time = flash_duration * 0.5
	smoke_timer.one_shot = true
	smoke_timer.timeout.connect(start_smoke_particles)
	add_child(smoke_timer)
	smoke_timer.start()

func start_smoke_particles():
	"""Start smoke particle emission"""
	smoke_particles.restart()
	smoke_particles.emitting = true

func set_flash_type(type: FlashType):
	"""Set the type of muzzle flash"""
	flash_type = type
	
	# Update components if they exist
	if flash_sprite:
		flash_sprite.texture = create_flash_texture()
	if flash_particles:
		flash_particles.amount = get_particle_count()

func set_flash_color(color: Color):
	"""Set the color of the flash effect"""
	flash_color = color
	
	if flash_sprite:
		flash_sprite.modulate = flash_color
	if flash_light:
		flash_light.color = flash_color

func cleanup_effect():
	"""Clean up the effect and remove from scene"""
	queue_free()

# Static utility function to create muzzle flash
static func create_muzzle_flash(flash_type: FlashType, position: Vector2, angle: float, parent: Node) -> MuzzleFlash:
	"""Create and show a muzzle flash effect"""
	var flash = MuzzleFlash.new()
	flash.flash_type = flash_type
	flash.global_position = position
	
	parent.add_child(flash)
	flash.show_flash(angle)
	
	return flash
