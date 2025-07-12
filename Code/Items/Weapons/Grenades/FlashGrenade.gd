extends Grenade
class_name FlashbangGrenade

# Range values for effects
var inner_range = 2  # Tiles - severe effects
var outer_range = 5  # Tiles - moderate effects
var max_range = 7    # Tiles - mild effects
var mp_only = true   # If this requires military police training
var banglet = false  # If this is a cluster grenade part

# Effect parameters
var flash_duration = 10     # Flash effect duration in seconds
var ear_damage_base = 5     # Base ear damage amount
var stun_duration_base = 20 # Base stun duration in seconds
var paralyze_duration = 6   # Paralyze duration in seconds (inner range only)
var ear_damage_chance = 70  # Chance for ear damage at close range
var blur_duration = 7       # Vision blur duration in seconds

# Preload the flash effect scene
var flash_scene = preload("res://Scenes/Effects/Flash.tscn")
var flash = null

func _init():
	super._init()
	obj_name = "flashbang"
	obj_desc = "A grenade sometimes used by police, civilian or military, to stun targets with a flash, then a bang. May cause hearing loss, and induce feelings of overwhelming rage in victims."
	grenade_type = GrenadeType.FLASHBANG
	det_time = 4.0
	flash_range = 7
	dangerous = true
	
	# Use the Item class variables for type categorization
	if "item_type" in self:
		self.item_type = "grenade"

func _ready():
	super._ready()
	
	flash = get_node("Icon")
	flash.play("Pin")
	
	# Ensure sprite is created
	if not has_node("Sprite2D"):
		var sprite = Sprite2D.new()
		sprite.name = "Sprite2D"
		var texture = load("res://assets/sprites/items/grenades/flashbang.png")
		if texture:
			sprite.texture = texture
		add_child(sprite)

# Override attack_self to check for military police skill
func attack_self(user) -> bool:
	if mp_only and "skills" in user and user.skills.has_method("getRating"):
		var police_skill = user.skills.getRating("POLICE")
		if police_skill < 3:  # Assuming 3 is MP level (SKILL_POLICE_MP)
			if user.has_method("display_message"):
				user.display_message("You don't seem to know how to use [color=yellow]%s[/color]..." % [obj_name])
			return false
	
	return super.attack_self(user)

func activate(user = null) -> bool:
	super.activate()
	flash.play("Primed")
	return true

# Override explode to apply flashbang effects
func explode() -> void:
	# Call parent explode method
	super.explode()
	
	# Apply flashbang effects at the explosion position
	apply_flashbang_effects(global_position)

# Apply the flashbang effects at the given position
func apply_flashbang_effects(pos: Vector2) -> void:
	# Create visual flash effect
	var flash = flash_scene.instantiate()
	flash.global_position = pos
	get_tree().get_root().add_child(flash)
	
	# Play flashbang sound at location
	var sound = AudioStreamPlayer2D.new()
	sound.stream = load("res://Sound/Grenades/flashbang2.mp3")
	sound.volume_db = 10.0  # Loud!
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
	
	# Apply effects to entities in range
	var entities = get_tree().get_nodes_in_group("entities")
	var tile_size = 32
	
	for entity in entities:
		var distance_tiles = entity.global_position.distance_to(pos) / tile_size
		
		# Skip entities that are immune to flashbangs
		if "has_trait" in entity and entity.has_method("has_trait") and entity.has_trait("FLASHBANGIMMUNE"):
			continue
		
		# Check if entity has direct line of sight to explosion
		var has_los = check_line_of_sight(pos, entity.global_position)
		
		if not has_los:
			continue  # Skip entities without line of sight
		
		# Send visual message to entity
		if entity.has_method("display_message"):
			entity.display_message("[color=red]BANG[/color]")
		
		# Common flash effect for all ranges if visible
		if entity.has_method("flash_act"):
			# Determine flash intensity based on distance
			var flash_intensity
			if distance_tiles <= inner_range:
				flash_intensity = 10
			elif distance_tiles <= outer_range:
				flash_intensity = 6
			else: # max_range
				flash_intensity = 3
				
			entity.flash_act(flash_intensity)
			
		# Apply blur effect if entity has the method
		if entity.has_method("blur_eyes"):
			var blur_power
			if distance_tiles <= inner_range:
				blur_power = blur_duration
			elif distance_tiles <= outer_range:
				blur_power = blur_duration * 0.8
			else: # max_range
				blur_power = blur_duration * 0.6
				
			entity.blur_eyes(blur_power)
		
		# Inner range effects (strongest)
		if distance_tiles <= inner_range:
			apply_inner_range_effects(entity)
		
		# Middle range effects
		elif distance_tiles <= outer_range:
			apply_middle_range_effects(entity)
		
		# Outer range effects (weakest)
		elif distance_tiles <= max_range:
			apply_outer_range_effects(entity)

# Check if there's a clear line of sight between two points
func check_line_of_sight(from_pos: Vector2, to_pos: Vector2) -> bool:
	# Simple implementation - check for walls or obstacles
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(from_pos, to_pos)
	query.collision_mask = 1  # Assuming walls are on layer 1
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	return result.is_empty()

# Apply strongest effects (inner range)
func apply_inner_range_effects(entity):
	# Check for ear protection
	var ear_safety = get_ear_protection(entity)
	
	if "is_human" in entity and entity.is_human:
		if ear_safety > 0:
			# Protected but still affected
			if entity.has_method("apply_effects"):
				entity.apply_effects("stun", 4.0)
				entity.apply_effects("paralyze", 2.0)
		else:
			# Unprotected - severe effects
			if entity.has_method("apply_effects"):
				entity.apply_effects("stun", stun_duration_base)
				entity.apply_effects("paralyze", paralyze_duration)
				
			# Apply ear damage
			if entity.has_method("adjust_ear_damage"):
				var chance_modifier = 1.0
				if entity == inventory_owner:
					chance_modifier = 1.2  # Higher chance if you're holding it
					
				if randf() * 100 < (ear_damage_chance * chance_modifier):
					var damage_amount = randi_range(1, 10)
					var deafen_amount = 15
					entity.adjust_ear_damage(damage_amount, deafen_amount)
				else:
					var damage_amount = randi_range(0, 5)
					var deafen_amount = 10
					entity.adjust_ear_damage(damage_amount, deafen_amount)

# Apply medium effects (middle range)
func apply_middle_range_effects(entity):
	# Check for ear protection
	var ear_safety = get_ear_protection(entity)
	
	if "is_human" in entity and entity.is_human:
		if ear_safety == 0:
			# Only affects unprotected targets
			if entity.has_method("apply_effects"):
				entity.apply_effects("stun", stun_duration_base * 0.8)
			
			# Apply ear damage
			if entity.has_method("adjust_ear_damage"):
				var damage_amount = randi_range(0, 3)
				var deafen_amount = 8
				entity.adjust_ear_damage(damage_amount, deafen_amount)

# Apply weakest effects (outer range)
func apply_outer_range_effects(entity):
	# Check for ear protection
	var ear_safety = get_ear_protection(entity)
	
	if "is_human" in entity and entity.is_human:
		if ear_safety == 0:
			# Minor effects for unprotected targets
			if entity.has_method("apply_effects"):
				entity.apply_effects("stun", stun_duration_base * 0.4)
			
			# Minor ear damage
			if entity.has_method("adjust_ear_damage"):
				var damage_amount = randi_range(0, 1)
				var deafen_amount = 6
				entity.adjust_ear_damage(damage_amount, deafen_amount)

# Calculate ear protection level for an entity
func get_ear_protection(entity) -> int:
	var ear_safety = 0
	
	# Check if entity has inventory system
	if "inventory" in entity and entity.inventory:
		# Check for earmuffs
		var ear_item = entity.inventory.get_item_in_slot(entity.inventory.EquipSlot.EARS)
		if ear_item and ear_item.has_method("get_type") and ear_item.get_type() == "earmuffs":
			ear_safety += 2
		
		# Check for helmets with ear protection
		var head_item = entity.inventory.get_item_in_slot(entity.inventory.EquipSlot.HEAD)
		if head_item and head_item.has_method("get_type"):
			var helmet_type = head_item.get_type()
			if helmet_type == "riot_helmet":
				ear_safety += 2
			elif helmet_type == "commando_helmet":
				ear_safety = 999  # Immune
	
	# Fallback for old system
	else:
		# Check for earmuffs
		if "wear_ear" in entity and entity.wear_ear:
			if entity.wear_ear.has_method("get_type") and entity.wear_ear.get_type() == "earmuffs":
				ear_safety += 2
		
		# Check for helmets with ear protection
		if "head" in entity and entity.head:
			if entity.head.has_method("get_type"):
				var helmet_type = entity.head.get_type()
				if helmet_type == "riot_helmet":
					ear_safety += 2
				elif helmet_type == "commando_helmet":
					ear_safety = 999  # Immune
	
	return ear_safety

# Create a stun variant with different effect profile
func create_stun_variant() -> FlashbangGrenade:
	var stun_grenade = FlashbangGrenade.new()
	stun_grenade.obj_name = "stun grenade"
	stun_grenade.obj_desc = "A grenade designed to disorientate the senses of anyone caught in the blast radius with a blinding flash of light and viciously loud noise. Repeated use can cause deafness."
	
	# Adjust properties for stun variant
	stun_grenade.inner_range = 3
	stun_grenade.det_time = 2.0
	stun_grenade.mp_only = false
	
	# Different effect profile - more disorientation, less hard stun
	stun_grenade.flash_duration = 15
	stun_grenade.blur_duration = 10
	stun_grenade.ear_damage_base = 3
	stun_grenade.stun_duration_base = 12
	stun_grenade.paralyze_duration = 0  # No hard paralyze
	
	# Update the effect application for stun grenade - override inner range
	stun_grenade.apply_inner_range_effects = func(entity):
		# Flash effect already applied in main function
		
		# Check for ear protection
		var ear_safety = stun_grenade.get_ear_protection(entity)
		
		if "is_human" in entity and entity.is_human:
			if ear_safety > 0:
				# Protected but still affected
				if entity.has_method("adjust_stagger"):
					entity.adjust_stagger(3.0)
				if entity.has_method("add_slowdown"):
					entity.add_slowdown(3)
			else:
				# Unprotected - disorienting effects
				if entity.has_method("adjust_stagger"):
					entity.adjust_stagger(6.0)
				if entity.has_method("add_slowdown"):
					entity.add_slowdown(6)
				
				# Apply ear damage
				if entity.has_method("adjust_ear_damage"):
					var chance_modifier = 1.0
					if entity == stun_grenade.inventory_owner:
						chance_modifier = 1.2  # Higher chance if you're holding it
						
					if randf() * 100 < (stun_grenade.ear_damage_chance * chance_modifier):
						var damage_amount = randi_range(1, 10)
						var deafen_amount = 15
						entity.adjust_ear_damage(damage_amount, deafen_amount)
					else:
						var damage_amount = randi_range(0, 5)
						var deafen_amount = 10
						entity.adjust_ear_damage(damage_amount, deafen_amount)
	
	# Override middle range effects
	stun_grenade.apply_middle_range_effects = func(entity):
		# Check for ear protection
		var ear_safety = stun_grenade.get_ear_protection(entity)
		
		if "is_human" in entity and entity.is_human:
			if ear_safety == 0:
				# Apply stagger and slowdown
				if entity.has_method("adjust_stagger"):
					entity.adjust_stagger(4.0)
				if entity.has_method("add_slowdown"):
					entity.add_slowdown(4)
				
				# Apply ear damage
				if entity.has_method("adjust_ear_damage"):
					var damage_amount = randi_range(0, 3)
					var deafen_amount = 8
					entity.adjust_ear_damage(damage_amount, deafen_amount)
	
	# Override outer range effects
	stun_grenade.apply_outer_range_effects = func(entity):
		# Check for ear protection
		var ear_safety = stun_grenade.get_ear_protection(entity)
		
		if "is_human" in entity and entity.is_human:
			if ear_safety == 0:
				# Apply stagger and slowdown
				if entity.has_method("adjust_stagger"):
					entity.adjust_stagger(2.0)
				if entity.has_method("add_slowdown"):
					entity.add_slowdown(2)
				
				# Apply ear damage
				if entity.has_method("adjust_ear_damage"):
					var damage_amount = randi_range(0, 1)
					var deafen_amount = 6
					entity.adjust_ear_damage(damage_amount, deafen_amount)
	
	return stun_grenade

# Override serialization to include flashbang properties
func serialize():
	var data = super.serialize()
	
	# Add flashbang-specific properties
	data["inner_range"] = inner_range
	data["outer_range"] = outer_range
	data["max_range"] = max_range
	data["mp_only"] = mp_only
	data["banglet"] = banglet
	data["flash_duration"] = flash_duration
	data["stun_duration_base"] = stun_duration_base
	data["paralyze_duration"] = paralyze_duration
	
	return data

func deserialize(data):
	super.deserialize(data)
	
	# Restore flashbang-specific properties
	if "inner_range" in data: inner_range = data.inner_range
	if "outer_range" in data: outer_range = data.outer_range
	if "max_range" in data: max_range = data.max_range
	if "mp_only" in data: mp_only = data.mp_only
	if "banglet" in data: banglet = data.banglet
	if "flash_duration" in data: flash_duration = data.flash_duration
	if "stun_duration_base" in data: stun_duration_base = data.stun_duration_base
	if "paralyze_duration" in data: paralyze_duration = data.paralyze_duration
