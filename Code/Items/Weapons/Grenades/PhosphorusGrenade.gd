extends Grenade
class_name PhosphorusGrenade

# Phosphorus properties
var fire_radius = 4      # Default fire radius in tiles
var inner_fire_radius = 1  # Inner intense fire radius in tiles
var burn_intensity = 75   # Higher burn intensity than regular incendiary
var burn_duration = 45    # Longer burn duration
var burn_damage = 15      # Higher initial damage
var fire_stacks = 75      # More fire stacks (makes entities burn longer/hotter)
var flame = null

# Preload scenes
var fire_particle_scene = preload("res://Scenes/Effects/Fire.tscn")
var smoke_particle_scene = preload("res://Scenes/Effects/Smoke.tscn")
var fire_area_scene = preload("res://Scenes/Effects/Fire_tile.tscn")

func _init():
	super._init()
	obj_name = "M40 HPDP grenade"
	obj_desc = "The M40 HPDP is a small, but powerful phosphorus grenade. It is set to detonate in 2 seconds."
	grenade_type = GrenadeType.PHOSPHORUS
	det_time = 2.0
	dangerous = true
	
	# Use the Item class variables for type categorization
	if "item_type" in self:
		self.item_type = "grenade"

func _ready():
	super._ready()
	
	flame = get_node("Icon")
	flame.play("Pin")
	
	# Ensure sprite is created
	if not has_node("Sprite2D"):
		var sprite = Sprite2D.new()
		sprite.name = "Sprite2D"
		var texture = load("res://assets/sprites/items/grenades/phos_grenade.png")
		if texture:
			sprite.texture = texture
		add_child(sprite)

# Override explode method
func explode() -> void:
	# Call parent explode method
	super.explode()
	
	# Create phosphorus effect at explosion position
	create_phosphorus(global_position)

# Create custom phosphorus effect
func create_phosphorus(pos: Vector2) -> void:
	# Play smoke sound effect
	var sound = AudioStreamPlayer2D.new()
	sound.stream = load("res://Sound/Explosions/explosion.wav") 
	sound.global_position = pos
	sound.autoplay = true
	sound.max_distance = 1000
	get_tree().get_root().add_child(sound)
	
	# Set up timer to free the sound after playing
	var timer = Timer.new()
	sound.add_child(timer)
	timer.wait_time = 3.0
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(func(): sound.queue_free())
	
	# Create smoke particles (white/grey phosphorus smoke)
	var smoke = smoke_particle_scene.instantiate()
	if smoke:
		get_tree().get_root().add_child(smoke)
		smoke.global_position = pos
		
		# Set smoke properties
		if smoke.has_method("set_smoke_properties"):
			# White dense smoke
			var smoke_color = Color(0.9, 0.9, 0.9, 0.9)
			smoke.set_smoke_properties(smoke_radius * 32, 7, smoke_color)
		else:
			# Manually adjust smoke properties
			if "amount" in smoke:
				smoke.amount = 300  # More particles for dense smoke
			if "lifetime" in smoke:
				smoke.lifetime = 15.0
			if "process_material" in smoke and smoke.process_material:
				smoke.process_material.color = Color(0.9, 0.9, 0.9, 0.9)
		
		smoke.emitting = true
		
		# Free smoke after its lifetime
		var smoke_timer = Timer.new()
		smoke.add_child(smoke_timer)
		smoke_timer.wait_time = 20.0  # Longer than lifetime to ensure all particles are gone
		smoke_timer.one_shot = true
		smoke_timer.autostart = true
		smoke_timer.timeout.connect(func(): smoke.queue_free())
	
	# Create fire particles (white/yellow phosphorus fire)
	var phosphorus_fire = fire_particle_scene.instantiate()
	if phosphorus_fire:
		get_tree().get_root().add_child(phosphorus_fire)
		phosphorus_fire.global_position = pos
		
		# Make phosphorus fire white
		phosphorus_fire.modulate = Color(1.0, 1.0, 1.0, 0.8)
		
		# Customize fire properties
		if "amount" in phosphorus_fire:
			phosphorus_fire.amount = 150  # More particles for main burst
		
		phosphorus_fire.emitting = true
		
		# Clean up after fire is done
		var fire_timer = Timer.new()
		phosphorus_fire.add_child(fire_timer)
		fire_timer.wait_time = 3.0
		fire_timer.one_shot = true
		fire_timer.autostart = true
		fire_timer.timeout.connect(func(): phosphorus_fire.queue_free())
	
	# Create fires on affected tiles
	ignite_area(pos)
	
	# Create smoke effect area that causes damage to entities in it
	create_smoke_effect(pos, smoke_radius)
	
	# Apply immediate damage to all entities in inner radius
	apply_immediate_damage(pos)
	
	# Create camera shake
	create_camera_shake(1.0)

# Create and ignite areas with fire
func ignite_area(pos: Vector2) -> void:
	var tile_size = 32
	var center_tile = Vector2i(int(pos.x / tile_size), int(pos.y / tile_size))
	
	# Get a list of all tile positions in the fire radius
	var fire_tiles = []
	for x in range(-fire_radius, fire_radius + 1):
		for y in range(-fire_radius, fire_radius + 1):
			if x*x + y*y <= fire_radius*fire_radius:  # Circle check
				fire_tiles.append(Vector2i(center_tile.x + x, center_tile.y + y))
	
	# Create fire on each tile
	for tile_pos in fire_tiles:
		var pixel_pos = Vector2(tile_pos.x * tile_size + tile_size/2, tile_pos.y * tile_size + tile_size/2)
		
		# Calculate distance from center
		var distance = pixel_pos.distance_to(pos)
		var in_inner_radius = distance <= inner_fire_radius * tile_size
		
		# Create a fire instance
		var fire = fire_area_scene.instantiate()
		fire.global_position = pixel_pos
		get_tree().get_root().add_child(fire)
		
		# Configure fire properties
		if "burn_damage" in fire:
			fire.burn_damage = burn_damage / 5.0  # Per-tick damage
			if in_inner_radius:
				fire.burn_damage *= 1.5  # Inner fire is more damaging
		
		if "burn_stacks" in fire:
			fire.burn_stacks = fire_stacks
		
		if "duration" in fire:
			fire.duration = burn_duration
		
		if "heat" in fire:
			fire.heat = burn_intensity * 10
		
		# Customize fire appearance for phosphorus
		if in_inner_radius:
			# Hotter, brighter fire in inner radius
			fire.scale = Vector2(1.2, 1.2)
			# If fire has children with modulate property
			for child in fire.get_children():
				if child is PointLight2D:
					child.color = Color(1.0, 1.0, 1.0, 1.0)  # White light
					child.energy = 1.5
				if "modulate" in child:
					child.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Bright white
		else:
			# Standard white phosphorus fire
			fire.scale = Vector2(1.0, 1.0)
			# If fire has children with modulate property
			for child in fire.get_children():
				if child is PointLight2D:
					child.color = Color(0.9, 0.9, 1.0, 0.8)  # Slightly blue-white
				if "modulate" in child:
					child.modulate = Color(0.9, 0.9, 1.0, 0.8)  # Slightly duller white

# Create smoke effect area that damages entities inside
func create_smoke_effect(pos: Vector2, radius: int) -> void:
	# Create the smoke area that will affect gameplay
	var smoke_area = Area2D.new()
	smoke_area.name = "PhosphorusSmokeArea"
	get_tree().get_root().add_child(smoke_area)
	smoke_area.global_position = pos
	
	# Add collision shape for smoke effect
	var collision = CollisionShape2D.new()
	var circle_shape = CircleShape2D.new()
	circle_shape.radius = radius * 32  # Convert tiles to pixels
	collision.shape = circle_shape
	smoke_area.add_child(collision)
	
	# Connect signals
	smoke_area.connect("body_entered", func(body): 
		if body.is_in_group("entities"):
			# Apply phosphorus effect
			if body.has_method("apply_chemical_effect"):
				body.apply_chemical_effect("phosphorus_burns", 5.0)
			
			# Apply damage
			if body.has_method("take_damage"):
				body.take_damage(3.0, "chemical", "chemical")
	)
	
	# Create timer for periodic damage
	var damage_timer = Timer.new()
	damage_timer.wait_time = 1.0
	damage_timer.autostart = true
	smoke_area.add_child(damage_timer)
	
	# Apply damage every second
	damage_timer.connect("timeout", func():
		var bodies = smoke_area.get_overlapping_bodies()
		for body in bodies:
			if body.is_in_group("entities"):
				# Apply phosphorus effect
				if body.has_method("apply_chemical_effect"):
					body.apply_chemical_effect("phosphorus_burns", 3.0)
				
				# Apply damage
				if body.has_method("take_damage"):
					body.take_damage(3.0, "chemical", "chemical")
	)
	
	# Set up duration timer
	var duration_timer = Timer.new()
	duration_timer.wait_time = 15.0
	duration_timer.one_shot = true
	duration_timer.autostart = true
	smoke_area.add_child(duration_timer)
	
	# Fade out when done
	duration_timer.connect("timeout", func():
		var tween = smoke_area.create_tween()
		tween.tween_property(collision, "scale", Vector2.ZERO, 2.0)
		tween.tween_callback(smoke_area.queue_free)
	)

# Apply immediate damage to entities in inner radius
func apply_immediate_damage(pos: Vector2) -> void:
	var entities = get_tree().get_nodes_in_group("entities")
	var tile_size = 32
	
	for entity in entities:
		var distance_tiles = entity.global_position.distance_to(pos) / tile_size
		
		# Apply damage with different intensity based on distance
		if distance_tiles <= inner_fire_radius:
			# Set entity on fire
			if entity.has_method("ignite"):
				entity.ignite(fire_stacks * 1.5)  # More fire in inner radius
			elif entity.has_method("add_fire_stacks"):
				entity.add_fire_stacks(fire_stacks * 1.5)
			
			# Apply severe initial damage
			if entity.has_method("take_damage"):
				entity.take_damage(burn_damage * 2.0, "fire", "fire")
				
			# Apply chemical effect
			if entity.has_method("apply_chemical_effect"):
				entity.apply_chemical_effect("phosphorus_burns", 10.0)
				
		elif distance_tiles <= fire_radius:
			# Set entity on fire
			if entity.has_method("ignite"):
				entity.ignite(fire_stacks)
			elif entity.has_method("add_fire_stacks"):
				entity.add_fire_stacks(fire_stacks)
			
			# Apply standard initial damage
			if entity.has_method("take_damage"):
				var damage_multiplier = 1.0 - (distance_tiles / fire_radius)
				var damage = burn_damage * damage_multiplier
				entity.take_damage(damage, "fire", "fire")
				
			# Apply chemical effect
			if entity.has_method("apply_chemical_effect"):
				entity.apply_chemical_effect("phosphorus_burns", 5.0)

# Record war crime when activated
func activate(user = null) -> bool:
	var result = super.activate(user)
	
	flame.play("Primed")
	
	# Record war crime if activated
	if result and user and user.has_method("record_war_crime"):
		user.record_war_crime()
	
	return result

# Override serialization to include phosphorus-specific properties
func serialize():
	var data = super.serialize()
	
	# Add phosphorus-specific properties
	data["fire_radius"] = fire_radius
	data["inner_fire_radius"] = inner_fire_radius
	data["burn_intensity"] = burn_intensity
	data["burn_duration"] = burn_duration
	data["burn_damage"] = burn_damage
	data["fire_stacks"] = fire_stacks
	data["smoke_radius"] = smoke_radius
	
	return data

func deserialize(data):
	super.deserialize(data)
	
	# Restore phosphorus-specific properties
	if "fire_radius" in data: fire_radius = data.fire_radius
	if "inner_fire_radius" in data: inner_fire_radius = data.inner_fire_radius
	if "burn_intensity" in data: burn_intensity = data.burn_intensity
	if "burn_duration" in data: burn_duration = data.burn_duration
	if "burn_damage" in data: burn_damage = data.burn_damage
	if "fire_stacks" in data: fire_stacks = data.fire_stacks
	if "smoke_radius" in data: smoke_radius = data.smoke_radius
