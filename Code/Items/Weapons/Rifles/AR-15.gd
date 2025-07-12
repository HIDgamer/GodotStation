extends WeaponComponent
class_name AR15WeaponComponent

var weight = 3.5

func _ready():
	super._ready()
	
	# Basic weapon properties
	weapon_name = "AR-15 Assault Rifle"
	description = "A reliable semi-automatic rifle chambered in 5.56mm. Standard issue for security personnel."
	item_name = weapon_name
	
	# Visual settings
	sprite_scale = Vector2(1.2, 1.2)
	two_handed = true
	show_in_offhand_when_wielded = true
	
	# Ammo settings
	caliber = "5.56mm"
	max_rounds = 40
	rounds_per_shot = 1
	
	# Load magazine and ammo references
	var magazine_scene_path = "res://Scenes/Items/Bullets_Magazines/5.56-Mag.tscn"
	if ResourceLoader.exists(magazine_scene_path):
		magazine_type = load(magazine_scene_path)
	
	var ammo_scene_path = "res://Scenes/Items/Bullets_Magazines/5.56.tscn" 
	if ResourceLoader.exists(ammo_scene_path):
		default_ammo_type = load(ammo_scene_path)
	
	# Firing properties
	fire_delay = 0.1  # Fast firing rate
	burst_delay = 0.08
	burst_amount = 3
	damage = 20
	penetration = 10
	accuracy_mult = 1.5
	accuracy_mult_unwielded = 0.4  # Poor accuracy when not wielded
	recoil = 6
	recoil_unwielded = 15
	scatter = 3
	scatter_unwielded = 20
	
	# Overheating properties
	has_overheating = true
	heat_per_shot = 3.0
	max_heat = 100.0
	cooling_rate = 8.0
	overheat_cooldown_multiplier = 1.5
	
	# Configure as a weapon
	tool_behaviour = "weapon"
	pickupable = true
	weight = 3.5  # Weight in kg
	
	# Set firing mode to semi-auto initially
	current_firing_mode = FiringMode.SEMI_AUTO
	
	# Slot flags - can be equipped to hands and back
	equip_slot_flags = Slots.LEFT_HAND | Slots.RIGHT_HAND | Slots.BACKPACK
	
	# Add to weapon group
	add_to_group("weapons")

# Override to provide all firing modes
func has_full_auto() -> bool:
	return true

# Override for custom fire effects
func play_fire_effects():
	# Play fire sound
	play_sound(fire_sound)
	
	# Show muzzle flash
	if muzzle_flash:
		muzzle_flash.visible = true
		muzzle_flash.play("flash")
		await muzzle_flash.animation_finished
		muzzle_flash.visible = false
	
	# Show casing ejection
	if casing_ejector:
		casing_ejector.visible = true
		casing_ejector.play("eject")
		await casing_ejector.animation_finished
		casing_ejector.visible = false
	
	# Show particles
	var particles = get_node_or_null("FireParticles")
	if particles:
		particles.emitting = true
		
	# Camera shake effect
	var camera = get_viewport().get_camera_2d()
	if camera and camera.has_method("add_trauma"):
		camera.add_trauma(0.3)

# Override for custom projectile emission
func emit_projectile(target_position, accuracy, scatter_amount):
	# Get world reference for spawning projectiles
	var world = get_tree().get_root().get_node_or_null("World")
	if !world:
		return
		
	# Calculate bullet direction with scatter
	var direction = (target_position - global_position).normalized()
	var angle = direction.angle()
	var scatter_rad = deg_to_rad(randf_range(-scatter_amount, scatter_amount))
	var scattered_angle = angle + scatter_rad
	var final_direction = Vector2(cos(scattered_angle), sin(scattered_angle))
	
	# Apply accuracy modifier to scatter
	var accuracy_modifier = max(0.1, accuracy)
	var accuracy_scatter = randf_range(-1, 1) / accuracy_modifier
	final_direction = final_direction.rotated(accuracy_scatter * 0.05)
	
	# Create bullet effect
	if world.has_method("spawn_bullet_effect"):
		# Get damage from current magazine if available
		var bullet_damage = damage
		var bullet_penetration = penetration
		
		if current_magazine and current_magazine.ammo_type:
			# Try to get ammo stats
			var test_ammo = current_magazine.ammo_type.instantiate()
			if test_ammo:
				bullet_damage = test_ammo.damage
				bullet_penetration = test_ammo.penetration
				test_ammo.queue_free()
		
		# Spawn the bullet effect in the world
		world.spawn_bullet_effect(
			global_position,          # Start position
			final_direction,          # Direction
			1200.0,                   # Speed in pixels per second
			bullet_damage,            # Damage
			bullet_penetration,       # Penetration
			self,                     # Source weapon
			inventory_owner           # Shooter
		)
	
	# Call parent implementation
	super.emit_projectile(target_position, accuracy, scatter_amount)

# Override custom complete reload process for AR-15
func complete_reload():
	if current_state != WeaponState.RELOADING:
		return
	
	current_state = WeaponState.IDLE
	update_animation_state()
	
	# Check inventory for compatible magazines
	if inventory_owner and "inventory_system" in inventory_owner:
		var inventory = inventory_owner.inventory_system
		
		# If we have a current magazine, swap it
		if current_magazine:
			# Eject current magazine
			var ejected_magazine = current_magazine
			current_magazine = null
			current_ammo = 0
			
			# Look for a new magazine in inventory
			var new_magazine = null
			
			# Try to find a magazine with ammo
			for item in inventory.get_all_items():
				if item is MagazineComponent and item.caliber == caliber and item.current_rounds > 0:
					new_magazine = item
					break
			
			# If no magazine with ammo, try any compatible magazine
			if !new_magazine:
				for item in inventory.get_all_items():
					if item is MagazineComponent and item.caliber == caliber:
						new_magazine = item
						break
			
			# If we found a magazine, load it
			if new_magazine:
				# Remove from inventory
				inventory.remove_item(new_magazine)
				
				# Load the magazine
				current_magazine = new_magazine
				current_ammo = current_magazine.current_rounds
				
				# Give old magazine back to inventory
				if ejected_magazine and ejected_magazine.current_rounds > 0:
					inventory.add_item(ejected_magazine)
				elif ejected_magazine:
					# Store empty magazines in the backpack or belt
					var stored = false
					if inventory.has_method("try_equip_to_slot"):
						stored = inventory.try_equip_to_slot(ejected_magazine, Slots.BACKPACK | Slots.BELT)
					
					if !stored:
						# If couldn't store, hold in hands
						inventory.add_item(ejected_magazine)
			else:
				# No replacement magazine found, give the old one back
				inventory.add_item(ejected_magazine)
		else:
			# We don't have a magazine, try to find one
			for item in inventory.get_all_items():
				if item is MagazineComponent and item.caliber == caliber:
					# Remove from inventory
					inventory.remove_item(item)
					
					# Load the magazine
					current_magazine = item
					current_ammo = current_magazine.current_rounds
					break
	
	emit_signal("reload_completed")
	emit_signal("ammo_changed", current_ammo, max_rounds)
