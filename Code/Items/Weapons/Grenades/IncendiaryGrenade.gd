extends Grenade
class_name IncendiaryGrenade

# Fire properties
var fire_radius = 2  # Tiles
var burn_duration = 25  # Seconds
var burn_intensity = 25
var burn_damage = 25
var fire_stacks = 15

# Preload scenes
var fire_particle_scene = preload("res://Scenes/Effects/Fire.tscn")
var fire_area_scene = preload("res://Scenes/Effects/Fire_tile.tscn")
var grenade = null

func _init():
	super._init()
	obj_name = "M40 HIDP incendiary grenade"
	obj_desc = "The M40 HIDP is a small, but deceptively strong incendiary grenade. It is set to detonate in 4 seconds."
	grenade_type = GrenadeType.INCENDIARY
	det_time = 4.0
	dangerous = true
	
	# Use the Item class variables for type categorization
	if "item_type" in self:
		self.item_type = "grenade"

func _ready():
	super._ready()
	
	grenade = get_node("Icon")
	
	grenade.play("Pin")

func activate(user = null) -> bool:
	super.activate()
	grenade.play("Primed")
	return true

# Override explode to create fire effect
func explode() -> void:
	# Call parent explode method
	super.explode()
	
	# Create fire at explosion position
	create_fire(global_position)

# Create a specialized fire effect
func create_fire(pos: Vector2) -> void:
	# Play specialized incendiary explosion sound
	var sound = AudioStreamPlayer2D.new()
	sound.stream = load("res://Sound/Explosions/explosion09.wav")
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
	
	# Create fire particles for main explosion
	var fire_explosion = fire_particle_scene.instantiate()
	if fire_explosion:
		get_tree().get_root().add_child(fire_explosion)
		fire_explosion.global_position = pos
		
		# Make main explosion larger and shorter-lived
		if "lifetime" in fire_explosion:
			fire_explosion.lifetime = 1.5
		if "amount" in fire_explosion:
			fire_explosion.amount = 150
		
		fire_explosion.emitting = true
		
		# Set up auto-cleanup
		var cleanup_timer = Timer.new()
		fire_explosion.add_child(cleanup_timer)
		cleanup_timer.wait_time = 3.0
		cleanup_timer.one_shot = true
		cleanup_timer.autostart = true
		cleanup_timer.timeout.connect(func(): fire_explosion.queue_free())
	
	# Create fires on tiles in radius
	ignite_area(pos, fire_radius)
	
	# Apply immediate fire damage to entities in range
	apply_fire_damage(pos)
	
	# Create camera shake
	create_camera_shake(1.0)

# Ignite an area centered on position
func ignite_area(pos: Vector2, radius: int) -> void:
	var tile_size = 32
	var center_tile = Vector2i(int(pos.x / tile_size), int(pos.y / tile_size))
	
	# Get a list of all tile positions in the fire radius
	var fire_tiles = []
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			if x*x + y*y <= radius*radius:  # Circle check
				fire_tiles.append(Vector2i(center_tile.x + x, center_tile.y + y))
	
	# Create fire on each tile
	for tile_pos in fire_tiles:
		var pixel_pos = Vector2(tile_pos.x * tile_size + tile_size/2, tile_pos.y * tile_size + tile_size/2)
		
		# Create a fire instance from the fire scene
		var fire = fire_area_scene.instantiate()
		fire.global_position = pixel_pos
		get_tree().get_root().add_child(fire)
		
		# Configure fire properties
		if "burn_damage" in fire:
			fire.burn_damage = burn_damage / 5.0  # Per-tick damage
		if "burn_stacks" in fire:
			fire.burn_stacks = fire_stacks
		if "duration" in fire:
			fire.duration = burn_duration
		if "heat" in fire:
			fire.heat = burn_intensity * 10
		
		# Make fires closer to the center more intense
		var distance_from_center = pixel_pos.distance_to(pos)
		var intensity_multiplier = 1.0 - (distance_from_center / (radius * tile_size))
		if "burn_damage" in fire:
			fire.burn_damage *= (1.0 + intensity_multiplier)
		
		# Size the fire based on intensity
		var fire_scale = 0.7 + intensity_multiplier * 0.6
		fire.scale = Vector2(fire_scale, fire_scale)
		
		# Make sure fire can damage players by setting up proper connections
		if fire.has_signal("body_entered") and not fire.is_connected("body_entered", _on_fire_body_entered):
			fire.connect("body_entered", _on_fire_body_entered.bind(fire))

# Apply immediate fire damage to entities
func apply_fire_damage(pos: Vector2) -> void:
	var entities = get_tree().get_nodes_in_group("entities")
	var players = get_tree().get_nodes_in_group("players")
	var tile_size = 32
	
	# Combine both groups to ensure we check all valid targets
	var all_targets = entities + players
	
	for entity in all_targets:
		# Skip invalid entities
		if not is_instance_valid(entity):
			continue
		
		var distance_tiles = entity.global_position.distance_to(pos) / tile_size
		
		if distance_tiles <= fire_radius:
			# Try different ignition methods based on what the entity supports
			if entity.has_method("ignite"):
				entity.ignite(fire_stacks)
			elif entity.has_method("add_fire_stacks"):
				entity.add_fire_stacks(fire_stacks)
			elif entity.has_method("apply_status_effect"):
				entity.apply_status_effect("burning", 10.0, fire_stacks/10.0)
			
			# Try to apply damage through all possible methods
			var damage = burn_damage * (1.0 - (distance_tiles / fire_radius))
			
			# Try direct damage methods
			if entity.has_method("apply_damage"):
				entity.apply_damage(damage, entity.DamageType.BURN if "DamageType" in entity else "burn")
			elif entity.has_method("take_damage"):
				entity.take_damage(damage, "fire")
			
			# Try to find and use the health system if available
			var health_system = null
			
			# Check if entity has health_system property
			if "health_system" in entity and entity.health_system:
				health_system = entity.health_system
			# Check if it's accessible as a child node
			elif entity.has_node("HealthSystem"):
				health_system = entity.get_node("HealthSystem")
			# Check if the parent has it
			elif entity.get_parent() and entity.get_parent().has_node("HealthSystem"):
				health_system = entity.get_parent().get_node("HealthSystem")
			
			# If we found a health system, apply damage directly
			if health_system and health_system.has_method("apply_damage"):
				var damage_type = health_system.DamageType.BURN if "DamageType" in health_system else 1
				health_system.apply_damage(damage, damage_type)
			
			# Apply visual effects for players
			if entity.is_in_group("players") or "is_local_player" in entity:
				var sensory_system = null
				
				if "sensory_system" in entity and entity.sensory_system:
					sensory_system = entity.sensory_system
				elif entity.has_node("SensorySystem"):
					sensory_system = entity.get_node("SensorySystem")
				elif entity.get_parent() and entity.get_parent().has_node("SensorySystem"):
					sensory_system = entity.get_parent().get_node("SensorySystem")
				
				if sensory_system and sensory_system.has_method("display_message"):
					sensory_system.display_message("You're engulfed in flames!", "red")

# Handle entity entering fire
func _on_fire_body_entered(body, fire_effect):
	if not is_instance_valid(body) or not is_instance_valid(fire_effect):
		return
		
	# Check if this is a player or valid entity
	if body.is_in_group("players") or body.is_in_group("entities"):
		# Apply burn effect
		if body.has_method("ignite"):
			body.ignite(fire_effect.burn_stacks if "burn_stacks" in fire_effect else fire_stacks)
		elif body.has_method("add_fire_stacks"):
			body.add_fire_stacks(fire_effect.burn_stacks if "burn_stacks" in fire_effect else fire_stacks)
		elif body.has_method("apply_status_effect"):
			var stacks = fire_effect.burn_stacks if "burn_stacks" in fire_effect else fire_stacks
			body.apply_status_effect("burning", 10.0, stacks/10.0)
		
		# Apply initial damage
		if body.has_method("take_damage"):
			var damage = fire_effect.burn_damage if "burn_damage" in fire_effect else burn_damage
			body.take_damage(damage, "fire", "fire")

# Override thrown behavior to handle special cases
func throw_impact(hit_atom, speed: float = 5) -> bool:
	var result = super.throw_impact(hit_atom, speed)
	
	# If we hit a living entity with a direct impact, set them on fire
	if hit_atom and (hit_atom.is_in_group("entities") or hit_atom.is_in_group("players")):
		if hit_atom.has_method("ignite"):
			hit_atom.ignite(fire_stacks)
		elif hit_atom.has_method("add_fire_stacks"):
			hit_atom.add_fire_stacks(fire_stacks)
		elif hit_atom.has_method("apply_status_effect"):
			hit_atom.apply_status_effect("burning", 10.0, fire_stacks/10.0)
			
		# Apply direct damage if incendiary was launched
		if launched:
			if hit_atom.has_method("take_damage"):
				hit_atom.take_damage(burn_damage * 0.5, "fire", "fire")
			elif hit_atom.has_method("apply_damage"):
				hit_atom.apply_damage(burn_damage * 0.5, hit_atom.DamageType.BURN if "DamageType" in hit_atom else "burn")
	
	return result

# Add a Molotov variant
func create_molotov_variant() -> IncendiaryGrenade:
	var molotov = IncendiaryGrenade.new()
	molotov.obj_name = "improvised firebomb"
	molotov.obj_desc = "A potent, improvised firebomb, coupled with a pinch of gunpowder. Cheap, very effective, and deadly in confined spaces. It can be difficult to predict how many seconds you have before it goes off, so be careful. Chances are, it might explode in your face."
	
	# Randomize detonation time for unpredictability
	molotov.det_time = randf_range(1.0, 4.0)
	
	# Adjust fire properties
	molotov.fire_radius = 1
	molotov.burn_duration = 15
	molotov.burn_damage = 20
	
	# Special handling for molotov - chance to break on impact
	molotov.connect("throw_impact", func(hit_atom, speed): 
		if hit_atom and hit_atom.density and randf() < 0.35:
			molotov.activate())
	
	return molotov

# Override serialization to include fire properties
func serialize():
	var data = super.serialize()
	
	# Add incendiary specific properties
	data["fire_radius"] = fire_radius
	data["burn_duration"] = burn_duration
	data["burn_intensity"] = burn_intensity
	data["burn_damage"] = burn_damage
	data["fire_stacks"] = fire_stacks
	
	return data

func deserialize(data):
	super.deserialize(data)
	
	# Restore incendiary specific properties
	if "fire_radius" in data: fire_radius = data.fire_radius
	if "burn_duration" in data: burn_duration = data.burn_duration
	if "burn_intensity" in data: burn_intensity = data.burn_intensity
	if "burn_damage" in data: burn_damage = data.burn_damage
	if "fire_stacks" in data: fire_stacks = data.fire_stacks
