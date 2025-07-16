extends Grenade
class_name HEGrenade

# Explosion properties
var light_impact_range = 2.5  # Light damage range in tiles
var medium_impact_range = 1.5  # Medium damage range in tiles
var heavy_impact_range = 0.7   # Heavy damage range in tiles (increased for better impact feeling)
var explosion_damage = 60    # Base explosion damage
var shrapnel_count = 8       # Number of shrapnel projectiles (increased from 6)
var shrapnel_damage = 15     # Damage per shrapnel hit

# Effect properties
var explosion_variant = 0    # 0 = default, 1 = large, 2 = small
var camera_shake_intensity = 1.0  # How strong the camera shakes

var icon = null

func _init():
	super._init()
	obj_name = "M40 HEDP grenade"
	obj_desc = "A small, but deceptively strong high explosive grenade that has been phasing out the M15 fragmentation grenades. Capable of being loaded in any grenade launcher, or thrown by hand."
	grenade_type = GrenadeType.EXPLOSIVE
	det_time = 4.0
	dangerous = true
	
	# Set up throwforce for proper impact damage
	throwforce = 10
	
	# Use the Item class variables for type categorization
	if "item_type" in self:
		self.item_type = "grenade"

func _ready():
	super._ready()
	icon = get_node("Icon")
	icon.play("Pin")

# Override explode method to create explosion effect
func explode() -> void:
	# Default explosion behavior from parent
	super.explode()
	
	# Create explosion effect at the detonation position
	create_explosion(global_position)

func activate(user = null) -> bool:
	super.activate()
	icon.play("Primed")
	return true

# Creates the explosion effect with enhanced visuals
func create_explosion(pos: Vector2) -> void:
	# Apply explosion damage first
	apply_explosion_damage(pos)
	
	# Create explosion visual effect with variations based on environment
	var explosion_effect = preload("res://Scenes/Effects/Explosion.tscn").instantiate()
	if explosion_effect:
		explosion_effect.global_position = pos
		get_tree().get_root().add_child(explosion_effect)
		
		# Check for ground/ceiling proximity to adjust particles
		var space_state = get_world_2d().direct_space_state
		var ground_check = space_state.intersect_ray(
			PhysicsRayQueryParameters2D.create(
				pos, 
				pos + Vector2(0, 50), 
				0xFFFFFFFF,  # All collision layers
				[]  # No exclusions
			)
		)
		
		var ceiling_check = space_state.intersect_ray(
			PhysicsRayQueryParameters2D.create(
				pos, 
				pos + Vector2(0, -50), 
				0xFFFFFFFF,  # All collision layers
				[]  # No exclusions
			)
		)
		
		# Configure explosion based on environment and properties
		var impact_radius = max(light_impact_range * 32, 80)  # Convert to pixels
		var explosion_intensity = 1.0
		
		# Add variations based on environment
		if ground_check:
			# Explosion near ground - emphasize ground dust and debris
			explosion_intensity = 1.2
			if explosion_effect.has_node("GroundDustParticles"):
				explosion_effect.get_node("GroundDustParticles").emitting = true
				
		if ceiling_check:
			# Explosion near ceiling - more falling debris
			if explosion_effect.has_node("DebrisParticles"):
				var debris = explosion_effect.get_node("DebrisParticles")
				debris.amount += 20
				if debris.process_material:
					debris.process_material.initial_velocity_max *= 1.2
		
		# Configure based on this specific grenade variant
		match explosion_variant:
			0:  # Default
				explosion_intensity = 1.0
			1:  # Large
				explosion_intensity = 1.5
				impact_radius *= 1.3
			2:  # Small
				explosion_intensity = 0.7
				impact_radius *= 0.7
		
		# Apply final configuration
		if explosion_effect.has_method("configure"):
			explosion_effect.configure(impact_radius / 32.0, explosion_intensity)
	
	# Create shrapnel projectiles
	create_shrapnel(pos)
	
	# Create camera shake based on distance to player
	create_camera_shake(camera_shake_intensity)

# Applies explosion damage to entities in range with improved effects
func apply_explosion_damage(pos: Vector2) -> void:
	var entities = get_tree().get_nodes_in_group("entities")
	var players = get_tree().get_nodes_in_group("players")
	var tile_size = 32
	
	# Combine both arrays to ensure we're checking all valid targets
	var all_targets = entities + players
	
	for entity in all_targets:
		# Skip invalid entities
		if not is_instance_valid(entity):
			continue
			
		var distance_tiles = entity.global_position.distance_to(pos) / tile_size
		
		# Skip if out of range
		if distance_tiles > light_impact_range:
			continue
			
		# Calculate damage falloff with distance - improved curve
		var damage_multiplier = 1.0
		
		if distance_tiles <= heavy_impact_range:
			# Exponential falloff for heavy impact range
			damage_multiplier = 1.5 * (1.0 - (distance_tiles / heavy_impact_range) * 0.2)
		elif distance_tiles <= medium_impact_range:
			# Linear falloff in medium impact range
			damage_multiplier = 1.0 * (1.0 - (distance_tiles - heavy_impact_range) / (medium_impact_range - heavy_impact_range) * 0.3)
		else:
			# Inverse square falloff in light impact range
			var falloff_factor = (distance_tiles - medium_impact_range) / (light_impact_range - medium_impact_range)
			damage_multiplier = 0.7 * (1.0 - falloff_factor * falloff_factor)
		
		# Apply damage using all available methods to ensure compatibility
		var damage = explosion_damage * damage_multiplier
		
		# Try different damage application methods depending on what the entity supports
		if entity.has_method("apply_damage"):
			# Direct HealthSystem method
			entity.apply_damage(damage, entity.DamageType.BRUTE if "DamageType" in entity else "brute")
		elif entity.has_method("take_damage"):
			# GridMovementController method
			entity.take_damage(damage, "brute")
		
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
			var damage_type = health_system.DamageType.BRUTE if "DamageType" in health_system else 0
			health_system.apply_damage(damage, damage_type)
		
		# Apply knockback effect with improved physics feel
		if entity.has_method("apply_knockback"):
			var knockback_dir = (entity.global_position - pos).normalized()
			var knockback_strength = (1.0 - pow(distance_tiles / light_impact_range, 0.7)) * 350.0
			entity.apply_knockback(knockback_dir, knockback_strength)
		# Try alternate method
		elif entity.get_parent() and entity.get_parent().has_method("apply_knockback"):
			var knockback_dir = (entity.global_position - pos).normalized()
			var knockback_strength = (1.0 - pow(distance_tiles / light_impact_range, 0.7)) * 350.0
			entity.get_parent().apply_knockback(knockback_dir, knockback_strength)
		
		# Apply stun/paralyze effect based on distance with smoother falloff
		if "stun" in entity:
			var stun_time = (1.0 - pow(distance_tiles / light_impact_range, 0.6)) * 5.0
			entity.stun(stun_time)
		elif entity.has_method("apply_effects"):
			var stun_time = (1.0 - pow(distance_tiles / light_impact_range, 0.6)) * 5.0
			entity.apply_effects("stun", stun_time)
		
		# Apply additional effects for players (visual feedback, screen effects)
		# For player-specific effects
		if entity.is_in_group("players") or "is_local_player" in entity:
			# Try to apply sensory effects
			var sensory_system = null
			
			if "sensory_system" in entity and entity.sensory_system:
				sensory_system = entity.sensory_system
			elif entity.has_node("SensorySystem"):
				sensory_system = entity.get_node("SensorySystem")
			elif entity.get_parent() and entity.get_parent().has_node("SensorySystem"):
				sensory_system = entity.get_parent().get_node("SensorySystem")
			
			if sensory_system:
				var message = "You're hit by an explosion!"
				if damage_multiplier > 1.0:
					message = "You're hit by a powerful explosion!"
				elif damage_multiplier < 0.5:
					message = "You're hit by the edge of an explosion!"
				
				if sensory_system.has_method("display_message"):
					sensory_system.display_message(message, "red")

# Creates shrapnel projectiles with better distribution and effects
func create_shrapnel(pos: Vector2) -> void:
	var base_angles = []
	
	# Calculate evenly distributed base angles
	for i in range(shrapnel_count):
		base_angles.append(TAU * i / shrapnel_count)
	
	# Create shrapnel projectiles with slight variations
	for i in range(shrapnel_count):
		# Add some randomness to the angles
		var angle = base_angles[i] + randf_range(-0.2, 0.2)
		var direction = Vector2(cos(angle), sin(angle))
		
		# Random velocity variation
		var velocity_factor = randf_range(0.85, 1.15)
		
		# Create shrapnel projectile
		var shrapnel = preload("res://Scenes/Effects/Shrapnel.tscn").instantiate()
		if shrapnel:
			shrapnel.global_position = pos
			get_tree().get_root().add_child(shrapnel)
			
			# Configure shrapnel properties
			if "velocity" in shrapnel:
				shrapnel.velocity = direction * 700.0 * velocity_factor  # Fast moving shrapnel
			if "damage" in shrapnel:
				shrapnel.damage = shrapnel_damage * velocity_factor  # Damage proportional to velocity
			if "penetration" in shrapnel:
				shrapnel.penetration = 20  # Some armor penetration
			if "max_range" in shrapnel:
				shrapnel.max_range = shrapnel_range * 32  # Convert to pixels
			if "projectile_name" in shrapnel:
				shrapnel.projectile_name = "shrapnel"
			
			# Add visual trail effect if supported
			if "has_trail" in shrapnel:
				shrapnel.has_trail = true

# Create camera shake effect with intensity based on distance
func create_camera_shake(intensity: float = 1.0) -> void:
	var camera = get_viewport().get_camera_2d()
	if camera and camera.has_method("add_trauma"):
		# Find player to calculate distance-based intensity
		var player = get_tree().get_first_node_in_group("player_controller")
		if player:
			var distance = global_position.distance_to(player.global_position)
			var distance_factor = clamp(1.0 - (distance / (light_impact_range * 64)), 0.1, 1.0)
			camera.add_trauma(intensity * distance_factor)
		else:
			camera.add_trauma(intensity * 0.5)  # Default if player not found

# Apply custom throw impact behavior with improved effects
func throw_impact(hit_atom, speed: float = 5) -> bool:
	# If launched from a grenade launcher and hit a solid object
	if launched and hit_atom and hit_atom.get("density") == true:
		# Chance to detonate on impact based on speed
		var detonation_chance = 0.25 + (speed / 20.0) * 0.25  # Up to 50% at high speeds
		if not active and randf() < detonation_chance:
			activate()
			
	return super.throw_impact(hit_atom, speed)

# Override serialization to include explosion properties
func serialize():
	var data = super.serialize()
	
	# Add HE-specific properties
	data["light_impact_range"] = light_impact_range
	data["medium_impact_range"] = medium_impact_range
	data["heavy_impact_range"] = heavy_impact_range
	data["flash_range"] = flash_range
	data["shrapnel_range"] = shrapnel_range
	data["explosion_damage"] = explosion_damage
	data["shrapnel_count"] = shrapnel_count
	data["shrapnel_damage"] = shrapnel_damage
	data["explosion_variant"] = explosion_variant
	data["camera_shake_intensity"] = camera_shake_intensity
	
	return data

func deserialize(data):
	super.deserialize(data)
	
	# Restore HE-specific properties
	if "light_impact_range" in data: light_impact_range = data.light_impact_range
	if "medium_impact_range" in data: medium_impact_range = data.medium_impact_range
	if "heavy_impact_range" in data: heavy_impact_range = data.heavy_impact_range
	if "flash_range" in data: flash_range = data.flash_range
	if "shrapnel_range" in data: shrapnel_range = data.shrapnel_range
	if "explosion_damage" in data: explosion_damage = data.explosion_damage
	if "shrapnel_count" in data: shrapnel_count = data.shrapnel_count
	if "shrapnel_damage" in data: shrapnel_damage = data.shrapnel_damage
	if "explosion_variant" in data: explosion_variant = data.explosion_variant
	if "camera_shake_intensity" in data: camera_shake_intensity = data.camera_shake_intensity
