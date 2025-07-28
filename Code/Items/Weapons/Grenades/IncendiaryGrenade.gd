extends Grenade
class_name IncendiaryGrenade

# Exported fire properties for easy tuning
@export_group("Fire Properties")
@export var fire_radius: int = 2  # Tiles to ignite
@export var burn_duration: float = 25.0  # Seconds fire lasts
@export var burn_intensity: int = 25
@export var burn_damage: float = 25.0
@export var fire_stacks: int = 15

@export_group("Performance Settings")
@export var max_fire_particles: int = 60  # Reduced from 100
@export var fire_tile_check_interval: float = 0.5
@export var max_fire_tiles: int = 20  # Limit for performance

@export_group("Effect Settings")
@export var explosion_scale: float = 1.0
@export var camera_shake_intensity: float = 1.0
@export var fire_spread_chance: float = 0.8

# Active fire areas for cleanup
var active_fires: Array = []
var fire_cleanup_timer: Timer

# Preloaded resources
static var fire_particle_scene: PackedScene
static var fire_area_scene: PackedScene

func _init():
	super._init()
	obj_name = "M40 HIDP incendiary grenade"
	obj_desc = "The M40 HIDP is a small, but deceptively strong incendiary grenade. It is set to detonate in 4 seconds."
	grenade_type = GrenadeType.INCENDIARY
	det_time = 4.0
	dangerous = true
	
	# Load resources once
	if not fire_particle_scene:
		fire_particle_scene = preload("res://Scenes/Effects/Fire.tscn")
	if not fire_area_scene:
		fire_area_scene = preload("res://Scenes/Effects/Fire_tile.tscn")

func explode() -> void:
	"""Handle incendiary grenade explosion with fire effects"""
	if not active:
		return
	
	# Store position before calling super
	var explosion_pos = global_position
	
	# Call parent explosion
	super.explode()
	
	# Create incendiary effects
	create_fire_explosion(explosion_pos)
	ignite_area(explosion_pos)
	apply_immediate_fire_damage(explosion_pos)
	create_camera_shake(camera_shake_intensity)

func create_fire_explosion(pos: Vector2) -> void:
	"""Create initial fire explosion effect"""
	# Play incendiary explosion sound
	var explosion_sound = load("res://Sound/Explosions/explosion09.wav")
	play_cached_sound(explosion_sound)
	
	# Create main fire explosion particle effect
	if fire_particle_scene:
		var fire_explosion = fire_particle_scene.instantiate()
		if fire_explosion:
			get_tree().current_scene.add_child(fire_explosion)
			fire_explosion.global_position = pos
			
			# Configure for optimized burst
			configure_fire_explosion(fire_explosion)
			
			# Auto cleanup
			create_cleanup_timer(fire_explosion, 3.0)

func configure_fire_explosion(fire_explosion: Node) -> void:
	"""Configure main explosion fire effect"""
	# Optimize particle count for performance
	if "amount" in fire_explosion:
		fire_explosion.amount = max_fire_particles
	
	if "lifetime" in fire_explosion:
		fire_explosion.lifetime = 1.5
	
	if "emitting" in fire_explosion:
		fire_explosion.emitting = true
	
	# Scale effect
	fire_explosion.scale = Vector2(explosion_scale, explosion_scale)

func ignite_area(pos: Vector2) -> void:
	"""Create persistent fire areas on tiles within radius"""
	var tile_size = 32
	var center_tile = Vector2i(int(pos.x / tile_size), int(pos.y / tile_size))
	
	# Calculate tiles to ignite
	var fire_tiles = get_fire_tiles(center_tile, fire_radius)
	
	# Limit fire tiles for performance
	if fire_tiles.size() > max_fire_tiles:
		fire_tiles.shuffle()
		fire_tiles = fire_tiles.slice(0, max_fire_tiles)
	
	print_debug("Creating ", fire_tiles.size(), " fire tiles")
	
	# Create fire on each tile
	for i in range(fire_tiles.size()):
		var tile_pos = fire_tiles[i]
		var pixel_pos = Vector2(tile_pos.x * tile_size + tile_size/2, tile_pos.y * tile_size + tile_size/2)
		
		# Add slight delay for performance
		if i > 5:
			await get_tree().process_frame
		
		create_fire_tile(pixel_pos, pos)

func get_fire_tiles(center_tile: Vector2i, radius: int) -> Array:
	"""Get array of tile positions within fire radius"""
	var tiles = []
	
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			var distance_sq = x*x + y*y
			if distance_sq <= radius*radius:  # Circle check
				# Add randomness for more natural spread
				if distance_sq == 0 or randf() < fire_spread_chance:
					tiles.append(Vector2i(center_tile.x + x, center_tile.y + y))
	
	return tiles

func create_fire_tile(pixel_pos: Vector2, explosion_center: Vector2) -> void:
	"""Create a fire area on a specific tile"""
	if not fire_area_scene:
		print_debug("Fire area scene not loaded!")
		return
	
	var fire = fire_area_scene.instantiate()
	if not fire:
		print_debug("Failed to instantiate fire tile")
		return
	
	# Add to scene first
	get_tree().current_scene.add_child(fire)
	fire.global_position = pixel_pos
	
	print_debug("Created fire tile at ", pixel_pos)
	
	# Configure fire properties
	configure_fire_tile(fire, pixel_pos, explosion_center)
	
	# Track active fire for cleanup
	active_fires.append(fire)
	
	# Connect area signals for entity interaction if it's an Area2D
	if fire is Area2D:
		connect_fire_signals(fire)
	
	# Set up fire duration cleanup
	create_cleanup_timer(fire, burn_duration)

func configure_fire_tile(fire: Node, pixel_pos: Vector2, explosion_center: Vector2) -> void:
	"""Configure individual fire tile properties"""
	# Calculate intensity based on distance from explosion center
	var distance = pixel_pos.distance_to(explosion_center)
	var max_distance = fire_radius * 32
	var intensity_factor = 1.0 - (distance / max_distance) if max_distance > 0 else 1.0
	
	# Set fire properties if they exist
	if "burn_damage" in fire:
		fire.burn_damage = (burn_damage / 5.0) * (1.0 + intensity_factor)
	
	if "burn_stacks" in fire:
		fire.burn_stacks = fire_stacks
	
	if "duration" in fire:
		fire.duration = burn_duration
	
	if "heat" in fire:
		fire.heat = burn_intensity * 10
	
	if "intensity" in fire:
		fire.intensity = intensity_factor
	
	# Scale fire based on intensity
	var fire_scale = 0.7 + intensity_factor * 0.6
	fire.scale = Vector2(fire_scale, fire_scale)
	
	# Configure visual effects
	configure_fire_visuals(fire, intensity_factor)

func configure_fire_visuals(fire: Node, intensity: float) -> void:
	"""Configure fire visual effects"""
	# Adjust light if present
	for child in fire.get_children():
		if child is PointLight2D:
			child.energy = 0.8 + intensity * 0.4
			child.texture_scale = 0.5 + intensity * 0.3
		
		# Adjust particles if present
		if "amount" in child and child.has_method("set_emitting"):
			child.amount = int(20 + intensity * 15)  # Scale particle count

func connect_fire_signals(fire: Area2D) -> void:
	"""Connect fire area signals for entity interaction"""
	if fire.has_signal("body_entered") and not fire.is_connected("body_entered", _on_fire_body_entered):
		fire.connect("body_entered", _on_fire_body_entered.bind(fire))
	
	if fire.has_signal("body_exited") and not fire.is_connected("body_exited", _on_fire_body_exited):
		fire.connect("body_exited", _on_fire_body_exited.bind(fire))

func apply_immediate_fire_damage(pos: Vector2) -> void:
	"""Apply immediate fire damage to entities in blast radius"""
	var tile_size = 32
	var max_distance = fire_radius * tile_size
	
	var entities = get_entities_in_radius(pos, max_distance)
	
	for entity in entities:
		var distance_tiles = entity.global_position.distance_to(pos) / tile_size
		
		if distance_tiles <= fire_radius:
			# Apply fire stacks
			apply_fire_stacks(entity, fire_stacks)
			
			# Apply initial burn damage
			var damage = burn_damage * (1.0 - (distance_tiles / fire_radius))
			apply_damage_to_entity(entity, damage, "fire")
			
			# Send feedback to players
			send_fire_feedback(entity)

func apply_fire_stacks(entity: Node, stacks: int) -> void:
	"""Apply fire status to an entity"""
	if entity.has_method("ignite"):
		entity.ignite(stacks)
	elif entity.has_method("add_fire_stacks"):
		entity.add_fire_stacks(stacks)
	elif entity.has_method("apply_status_effect"):
		entity.apply_status_effect("burning", 10.0, stacks / 10.0)

func send_fire_feedback(entity: Node) -> void:
	"""Send fire damage feedback to players"""
	if not entity.is_in_group("players") and not "is_local_player" in entity:
		return
	
	var sensory_system = get_entity_sensory_system(entity)
	if sensory_system and sensory_system.has_method("display_message"):
		sensory_system.display_message("You're engulfed in flames!", "red")

func get_entity_sensory_system(entity: Node) -> Node:
	"""Get sensory system for an entity"""
	if "sensory_system" in entity and entity.sensory_system:
		return entity.sensory_system
	elif entity.has_node("SensorySystem"):
		return entity.get_node("SensorySystem")
	elif entity.get_parent() and entity.get_parent().has_node("SensorySystem"):
		return entity.get_parent().get_node("SensorySystem")
	return null

func _on_fire_body_entered(body: Node, fire_effect: Node) -> void:
	"""Handle entity entering fire area"""
	if not is_instance_valid(body) or not is_instance_valid(fire_effect):
		return
	
	if body.is_in_group("players") or body.is_in_group("entities"):
		# Apply fire stacks
		var stacks = fire_effect.burn_stacks if "burn_stacks" in fire_effect else fire_stacks
		apply_fire_stacks(body, stacks)
		
		# Apply initial damage
		var damage = fire_effect.burn_damage if "burn_damage" in fire_effect else burn_damage
		apply_damage_to_entity(body, damage, "fire")

func _on_fire_body_exited(body: Node, fire_effect: Node) -> void:
	"""Handle entity leaving fire area"""
	# Fire continues to burn on the entity, so no immediate action needed
	pass

func throw_impact(hit_atom, speed: float = 5) -> bool:
	"""Handle impact when thrown - can ignite entities on direct hit"""
	var result = super.throw_impact(hit_atom, speed)
	
	# Direct impact ignition
	if hit_atom and (hit_atom.is_in_group("entities") or hit_atom.is_in_group("players")):
		apply_fire_stacks(hit_atom, fire_stacks)
		
		# Apply impact damage if launched
		if launched:
			apply_damage_to_entity(hit_atom, burn_damage * 0.5, "fire")
	
	return result

func create_molotov_variant() -> IncendiaryGrenade:
	"""Create a molotov cocktail variant with different properties"""
	var molotov = IncendiaryGrenade.new()
	molotov.obj_name = "improvised firebomb"
	molotov.obj_desc = "A potent, improvised firebomb, coupled with a pinch of gunpowder. Cheap, very effective, and deadly in confined spaces. It can be difficult to predict how many seconds you have before it goes off, so be careful. Chances are, it might explode in your face."
	
	# Randomize detonation time for unpredictability
	molotov.det_time = randf_range(1.0, 4.0)
	
	# Adjust fire properties
	molotov.fire_radius = 1
	molotov.burn_duration = 15.0
	molotov.burn_damage = 20.0
	molotov.max_fire_tiles = 10
	
	return molotov

func cleanup_all_fires() -> void:
	"""Force cleanup of all active fires"""
	for fire in active_fires:
		if is_instance_valid(fire):
			fire.queue_free()
	active_fires.clear()

func _exit_tree():
	"""Clean up active fires when grenade is destroyed"""
	cleanup_all_fires()

func serialize() -> Dictionary:
	"""Save incendiary grenade properties"""
	var data = super.serialize()
	
	data["fire_radius"] = fire_radius
	data["burn_duration"] = burn_duration
	data["burn_intensity"] = burn_intensity
	data["burn_damage"] = burn_damage
	data["fire_stacks"] = fire_stacks
	data["max_fire_particles"] = max_fire_particles
	data["max_fire_tiles"] = max_fire_tiles
	
	return data

func deserialize(data: Dictionary):
	"""Restore incendiary grenade properties"""
	super.deserialize(data)
	
	if "fire_radius" in data: fire_radius = data.fire_radius
	if "burn_duration" in data: burn_duration = data.burn_duration
	if "burn_intensity" in data: burn_intensity = data.burn_intensity
	if "burn_damage" in data: burn_damage = data.burn_damage
	if "fire_stacks" in data: fire_stacks = data.fire_stacks
	if "max_fire_particles" in data: max_fire_particles = data.max_fire_particles
	if "max_fire_tiles" in data: max_fire_tiles = data.max_fire_tiles
