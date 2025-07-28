extends Node2D
class_name BulletHit

# Visual components
var impact_sprite: Sprite2D
var spark_particles: GPUParticles2D
var debris_particles: GPUParticles2D
var impact_light: PointLight2D

# Effect properties
@export var effect_duration: float = 0.5
@export var spark_count: int = 30
@export var debris_count: int = 15
@export var impact_color: Color = Color.ORANGE
@export var debris_color: Color = Color.BROWN

# Impact types for different materials
enum ImpactType {
	FLESH,
	METAL,
	WOOD,
	CONCRETE,
	GLASS,
	DIRT
}

@export var impact_type: ImpactType = ImpactType.METAL

func _ready():
	setup_components()
	
	# Auto-cleanup after effect
	var cleanup_timer = Timer.new()
	cleanup_timer.wait_time = 2.0
	cleanup_timer.one_shot = true
	cleanup_timer.timeout.connect(cleanup_effect)
	add_child(cleanup_timer)
	cleanup_timer.start()

func setup_components():
	"""Initialize all visual components"""
	create_impact_sprite()
	create_spark_particles()
	create_debris_particles()
	create_impact_light()

func create_impact_sprite():
	"""Create the main impact flash sprite"""
	impact_sprite = Sprite2D.new()
	impact_sprite.name = "ImpactSprite"
	add_child(impact_sprite)
	
	# Create impact texture
	impact_sprite.texture = create_impact_texture()
	impact_sprite.modulate = get_impact_color()
	impact_sprite.modulate.a = 0.0
	
	# Set additive blending
	var material = CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	impact_sprite.material = material

func create_impact_texture() -> ImageTexture:
	"""Create impact flash texture"""
	var size = 16
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = Vector2(size / 2, size / 2)
	var radius = size / 2
	
	for x in range(size):
		for y in range(size):
			var distance = Vector2(x, y).distance_to(center)
			var intensity = 1.0 - (distance / radius)
			intensity = max(0.0, intensity)
			intensity = pow(intensity, 0.8)  # Softer falloff
			
			var color = Color.WHITE
			color.a = intensity
			image.set_pixel(x, y, color)
	
	var texture = ImageTexture.new()
	texture.set_image(image)
	return texture

func get_impact_color() -> Color:
	"""Get impact color based on material type"""
	match impact_type:
		ImpactType.FLESH:
			return Color.RED
		ImpactType.METAL:
			return Color.ORANGE
		ImpactType.WOOD:
			return Color.YELLOW
		ImpactType.CONCRETE:
			return Color.GRAY
		ImpactType.GLASS:
			return Color.CYAN
		ImpactType.DIRT:
			return Color.BROWN
		_:
			return impact_color

func create_spark_particles():
	"""Create spark particles for metal/hard impacts"""
	spark_particles = GPUParticles2D.new()
	spark_particles.name = "SparkParticles"
	add_child(spark_particles)
	
	# Configure sparks
	spark_particles.emitting = false
	spark_particles.amount = get_spark_count()
	spark_particles.lifetime = 0.4
	spark_particles.one_shot = true
	spark_particles.explosiveness = 1.0
	
	# Create spark material
	var material = ParticleProcessMaterial.new()
	
	# Emission in hemisphere
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.direction = Vector3(0, -1, 0)  # Generally upward
	material.spread = 60.0
	
	# Velocity
	material.initial_velocity_min = 30.0
	material.initial_velocity_max = 100.0
	
	# Scale
	material.scale_min = 0.05
	material.scale_max = 0.15
	
	# Color
	material.color = get_spark_color()
	material.color_ramp = create_spark_gradient()
	
	# Physics
	material.gravity = Vector3(0, 200, 0)  # Sparks fall down
	material.linear_accel_min = -50.0
	material.linear_accel_max = -100.0
	
	spark_particles.process_material = material
	spark_particles.texture = create_spark_texture()

func get_spark_count() -> int:
	"""Get spark count based on impact type"""
	match impact_type:
		ImpactType.FLESH:
			return 5  # Blood droplets
		ImpactType.METAL:
			return 30
		ImpactType.WOOD:
			return 10  # Wood chips
		ImpactType.CONCRETE:
			return 20
		ImpactType.GLASS:
			return 25  # Glass shards
		ImpactType.DIRT:
			return 15  # Dust particles
		_:
			return spark_count

func get_spark_color() -> Color:
	"""Get spark color based on material"""
	match impact_type:
		ImpactType.FLESH:
			return Color.DARK_RED
		ImpactType.METAL:
			return Color.ORANGE
		ImpactType.WOOD:
			return Color.SANDY_BROWN
		ImpactType.CONCRETE:
			return Color.LIGHT_GRAY
		ImpactType.GLASS:
			return Color.WHITE
		ImpactType.DIRT:
			return Color.SADDLE_BROWN
		_:
			return Color.ORANGE

func create_spark_gradient() -> Gradient:
	"""Create color gradient for sparks"""
	var gradient = Gradient.new()
	var base_color = get_spark_color()
	
	gradient.add_point(0.0, base_color)
	gradient.add_point(0.5, base_color * 0.8)
	gradient.add_point(1.0, Color.TRANSPARENT)
	return gradient

func create_spark_texture() -> ImageTexture:
	"""Create small spark texture"""
	var size = 3
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	
	var texture = ImageTexture.new()
	texture.set_image(image)
	return texture

func create_debris_particles():
	"""Create debris particles for impact"""
	debris_particles = GPUParticles2D.new()
	debris_particles.name = "DebrisParticles"
	add_child(debris_particles)
	
	# Configure debris
	debris_particles.emitting = false
	debris_particles.amount = get_debris_count()
	debris_particles.lifetime = 1.0
	debris_particles.one_shot = true
	debris_particles.explosiveness = 0.8
	
	# Create debris material
	var material = ParticleProcessMaterial.new()
	
	# Emission
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.direction = Vector3(0, -1, 0)
	material.spread = 45.0
	
	# Velocity
	material.initial_velocity_min = 20.0
	material.initial_velocity_max = 60.0
	
	# Scale
	material.scale_min = 0.1
	material.scale_max = 0.3
	
	# Color
	material.color = get_debris_color()
	material.color_ramp = create_debris_gradient()
	
	# Physics
	material.gravity = Vector3(0, 150, 0)
	material.linear_accel_min = -30.0
	material.linear_accel_max = -60.0
	
	# Add some rotation
	material.angular_velocity_min = -180.0
	material.angular_velocity_max = 180.0
	
	debris_particles.process_material = material
	debris_particles.texture = create_debris_texture()

func get_debris_count() -> int:
	"""Get debris count based on impact type"""
	match impact_type:
		ImpactType.FLESH:
			return 3  # Minimal debris
		ImpactType.METAL:
			return 10
		ImpactType.WOOD:
			return 15
		ImpactType.CONCRETE:
			return 20
		ImpactType.GLASS:
			return 25
		ImpactType.DIRT:
			return 30  # Lots of dust
		_:
			return debris_count

func get_debris_color() -> Color:
	"""Get debris color based on material"""
	match impact_type:
		ImpactType.FLESH:
			return Color.DARK_RED
		ImpactType.METAL:
			return Color.DARK_GRAY
		ImpactType.WOOD:
			return Color.SADDLE_BROWN
		ImpactType.CONCRETE:
			return Color.GRAY
		ImpactType.GLASS:
			return Color.WHITE
		ImpactType.DIRT:
			return Color.PERU
		_:
			return debris_color

func create_debris_gradient() -> Gradient:
	"""Create color gradient for debris"""
	var gradient = Gradient.new()
	var base_color = get_debris_color()
	
	gradient.add_point(0.0, base_color)
	gradient.add_point(0.8, base_color * 0.7)
	gradient.add_point(1.0, Color.TRANSPARENT)
	return gradient

func create_debris_texture() -> ImageTexture:
	"""Create debris chunk texture"""
	var size = 6
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	
	# Create irregular debris shape
	for x in range(size):
		for y in range(size):
			var center_dist = Vector2(x, y).distance_to(Vector2(size/2, size/2))
			var noise_val = randf()
			
			if center_dist < size/2 and noise_val > 0.3:
				image.set_pixel(x, y, Color.WHITE)
			else:
				image.set_pixel(x, y, Color.TRANSPARENT)
	
	var texture = ImageTexture.new()
	texture.set_image(image)
	return texture

func create_impact_light():
	"""Create brief light flash for impact"""
	impact_light = PointLight2D.new()
	impact_light.name = "ImpactLight"
	add_child(impact_light)
	
	# Configure light
	impact_light.enabled = true
	impact_light.energy = 0.0
	impact_light.color = get_impact_color()
	impact_light.texture_scale = 0.3

func play_effect(impact_angle: float = 0.0):
	"""Play the complete impact effect"""
	# Set rotation to match impact angle
	rotation = impact_angle
	
	# Animate impact sprite
	animate_impact_sprite()
	
	# Animate light
	animate_impact_light()
	
	# Start particles
	start_particles()
	
	# Play impact sound
	play_impact_sound()

func animate_impact_sprite():
	"""Animate the impact flash"""
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Quick flash
	tween.tween_property(impact_sprite, "modulate:a", 1.0, 0.05)
	tween.tween_property(impact_sprite, "modulate:a", 0.0, 0.15)
	
	# Scale pulse
	impact_sprite.scale = Vector2(0.5, 0.5)
	tween.tween_property(impact_sprite, "scale", Vector2(1.5, 1.5), 0.1)
	tween.tween_property(impact_sprite, "scale", Vector2(0.8, 0.8), 0.1)

func animate_impact_light():
	"""Animate the impact light"""
	var tween = create_tween()
	
	# Brief light flash
	tween.tween_property(impact_light, "energy", 1.0, 0.02)
	tween.tween_property(impact_light, "energy", 0.0, 0.08)

func start_particles():
	"""Start all particle effects"""
	# Start sparks immediately
	spark_particles.restart()
	spark_particles.emitting = true
	
	# Start debris with slight delay
	var debris_timer = Timer.new()
	debris_timer.wait_time = 0.02
	debris_timer.one_shot = true
	debris_timer.timeout.connect(start_debris)
	add_child(debris_timer)
	debris_timer.start()

func start_debris():
	"""Start debris particles"""
	debris_particles.restart()
	debris_particles.emitting = true

func play_impact_sound():
	"""Play impact sound based on material"""
	var sound_name = get_impact_sound_name()
	
	# Play sound at impact location
	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_positioned_sound"):
		audio_manager.play_positioned_sound(sound_name, global_position, 0.5)

func get_impact_sound_name() -> String:
	"""Get appropriate sound name for impact type"""
	match impact_type:
		ImpactType.FLESH:
			return "bullet_hit_flesh"
		ImpactType.METAL:
			return "bullet_hit_metal"
		ImpactType.WOOD:
			return "bullet_hit_wood"
		ImpactType.CONCRETE:
			return "bullet_hit_concrete"
		ImpactType.GLASS:
			return "bullet_hit_glass"
		ImpactType.DIRT:
			return "bullet_hit_dirt"
		_:
			return "bullet_hit_generic"

func set_impact_type(type: ImpactType):
	"""Set the impact type and update colors"""
	impact_type = type
	
	# Update existing components
	if impact_sprite:
		impact_sprite.modulate = get_impact_color()
	if impact_light:
		impact_light.color = get_impact_color()

func cleanup_effect():
	"""Clean up and remove the effect"""
	queue_free()

# Static utility function
static func create_impact_effect(impact_type: ImpactType, position: Vector2, angle: float, parent: Node) -> BulletHit:
	"""Create and play an impact effect"""
	var impact = BulletHit.new()
	impact.impact_type = impact_type
	impact.global_position = position
	
	parent.add_child(impact)
	impact.play_effect(angle)
	
	return impact

# Utility function to detect impact type from target
static func detect_impact_type_from_target(target) -> ImpactType:
	"""Detect impact type based on target properties"""
	if not target:
		return ImpactType.METAL
	
	# Check for material type property
	if target.has_method("get_material_type"):
		match target.get_material_type():
			"flesh", "organic":
				return ImpactType.FLESH
			"metal", "steel", "iron":
				return ImpactType.METAL
			"wood", "wooden":
				return ImpactType.WOOD
			"concrete", "stone", "rock":
				return ImpactType.CONCRETE
			"glass":
				return ImpactType.GLASS
			"dirt", "earth", "sand":
				return ImpactType.DIRT
	
	# Check by class type or name
	var target_name = target.name.to_lower()
	
	if "flesh" in target_name or "body" in target_name or target.get_script() and "human" in str(target.get_script().get_path()):
		return ImpactType.FLESH
	elif "metal" in target_name or "steel" in target_name:
		return ImpactType.METAL
	elif "wood" in target_name or "tree" in target_name:
		return ImpactType.WOOD
	elif "wall" in target_name or "concrete" in target_name:
		return ImpactType.CONCRETE
	elif "glass" in target_name or "window" in target_name:
		return ImpactType.GLASS
	elif "dirt" in target_name or "ground" in target_name:
		return ImpactType.DIRT
	
	# Default to metal
	return ImpactType.METAL
