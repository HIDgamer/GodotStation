extends Grenade
class_name SmokeGrenade

# Smoke properties
var smoke_type = "normal"  # Type of smoke: normal, cloak, acid, neuro, drain, antigas, satrapine, etc.
var smoke_color = Color(0.7, 0.7, 0.7, 0.8)  # Default gray color
var smoke_effects = {}    # Dictionary of effects to apply
var active_smoke_area = null  # Reference to the active smoke area (for cleanup)
var smoke = null

# Preload the smoke particle scene
var smoke_particle_scene = preload("res://Scenes/Effects/Smoke.tscn")

func _init():
	super._init()
	obj_name = "M40 HSDP smoke grenade"
	obj_desc = "The M40 HSDP is a small, but powerful smoke grenade. Based off the same platform as the M40 HEDP. It is set to detonate in 2 seconds."
	grenade_type = GrenadeType.SMOKE
	det_time = 2.0
	dangerous = false
	
	# Initialize smoke effects for different types
	initialize_smoke_effects()
	
	# Use the Item class variables for type categorization
	if "item_type" in self:
		self.item_type = "grenade"

func _ready():
	super._ready()
	
	smoke = get_node("Icon")
	smoke.play("Pin")
	
	# Ensure sprite is updated based on smoke type
	update_appearance()

# Initialize smoke effects for different types
func initialize_smoke_effects():
	# Standard smoke effects
	smoke_effects = {
		"normal": {
			"vision_modifier": 0.5,  # Reduces vision to 50%
			"duration": 9.0,         # Duration in seconds
			"color": Color(0.7, 0.7, 0.7, 0.8)  # Default gray
		},
		"cloak": {
			"vision_modifier": 0.3,  # Reduces vision to 30%
			"duration": 11.0,
			"cloaking": true,        # Provides cloaking effect
			"color": Color(0.2, 0.3, 0.25, 0.9)  # Dark green
		},
		"acid": {
			"vision_modifier": 0.5,
			"duration": 9.0,
			"acid_damage": 5,        # Acid damage per tick
			"color": Color(0.7, 0.9, 0.2, 0.8)  # Acid green
		},
		"neuro": {
			"vision_modifier": 0.6,
			"duration": 9.0,
			"effects": {
				"dizzy": 1.5,
				"weakened": 1.0
			},
			"color": Color(0.8, 0.4, 0.8, 0.8)  # Purple
		},
		"drain": {
			"vision_modifier": 0.5,
			"duration": 11.0,
			"plasma_drain": 15,      # Plasma/energy drain per tick
			"color": Color(0.3, 0.7, 0.9, 0.8)  # Blue
		},
		"antigas": {
			"vision_modifier": 0.7,
			"duration": 11.0,
			"purge_gases": true,     # Purges gas effects
			"color": Color(0.9, 0.7, 0.2, 0.7)  # Yellow
		},
		"satrapine": {
			"vision_modifier": 0.5,
			"duration": 9.0,
			"effects": {
				"pain": 2.0
			},
			"purge_chemicals": ["painkiller", "morphine", "epinephrine"],
			"color": Color(0.7, 0.2, 0.2, 0.8)  # Red
		}
	}

# Override explode to create smoke
func explode() -> void:
	# Call parent explode method
	super.explode()
	
	# Create smoke at explosion position
	create_smoke(global_position)

# Override to create custom smoke effect
func create_smoke(pos: Vector2) -> void:
	# Play activation sound
	var sound = AudioStreamPlayer2D.new()
	sound.stream = load("res://Sound/effects/thud.ogg")
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
	
	# Determine smoke color based on type
	var current_smoke_type = smoke_effects.get(smoke_type, smoke_effects["normal"])
	smoke_color = current_smoke_type.get("color", Color(0.7, 0.7, 0.7, 0.8))
	
	# Create smoke particles
	var smoke = smoke_particle_scene.instantiate()
	if smoke:
		get_tree().get_root().add_child(smoke)
		smoke.global_position = pos
		
		# Configure smoke properties
		if smoke.has_method("set_smoke_properties"):
			smoke.set_smoke_properties(smoke_radius * 32, smoke_duration, smoke_color)
		else:
			# Manually adjust smoke properties if set_smoke_properties isn't available
			if "process_material" in smoke and smoke.process_material:
				if "color" in smoke.process_material:
					smoke.process_material.color = smoke_color
				if "emission_sphere_radius" in smoke.process_material:
					smoke.process_material.emission_sphere_radius = smoke_radius * 16  # Half of full radius
			if "lifetime" in smoke:
				smoke.lifetime = smoke_duration
		
		smoke.emitting = true
		
		# Set up auto-cleanup
		var cleanup_timer = Timer.new()
		smoke.add_child(cleanup_timer)
		cleanup_timer.wait_time = smoke_duration + 2.0  # Extra time to ensure all particles are gone
		cleanup_timer.one_shot = true
		cleanup_timer.autostart = true
		cleanup_timer.timeout.connect(func(): smoke.queue_free())
	
	# Create physical smoke effect in the game world
	create_smoke_effect(pos)

# Create in-game smoke effect that implements gameplay behavior
func create_smoke_effect(pos: Vector2) -> void:
	# Get current smoke type effects
	var current_smoke_type = smoke_effects.get(smoke_type, smoke_effects["normal"])
	var effect_duration = current_smoke_type.get("duration", 9.0)
	
	# Create the smoke area that will affect gameplay
	var smoke_area = Area2D.new()
	smoke_area.name = "SmokeArea_" + smoke_type
	get_tree().get_root().add_child(smoke_area)
	smoke_area.global_position = pos
	
	# Store reference to active smoke area
	active_smoke_area = smoke_area
	
	# Add collision shape
	var collision = CollisionShape2D.new()
	var circle_shape = CircleShape2D.new()
	circle_shape.radius = smoke_radius * 32  # Convert tiles to pixels
	collision.shape = circle_shape
	smoke_area.add_child(collision)
	
	# Keep track of entities in smoke
	var entities_in_smoke = []
	
	# Connect signals
	smoke_area.connect("body_entered", func(body):
		if body.is_in_group("entities") and not body in entities_in_smoke:
			entities_in_smoke.append(body)
			apply_entry_effect(body, current_smoke_type)
	)
	
	smoke_area.connect("body_exited", func(body):
		if body in entities_in_smoke:
			entities_in_smoke.erase(body)
			clear_effects(body, current_smoke_type)
	)
	
	# Create timer for periodic effects
	var effect_timer = Timer.new()
	effect_timer.wait_time = 1.0  # Apply effects every second
	effect_timer.autostart = true
	smoke_area.add_child(effect_timer)
	
	# Connect effect timer
	effect_timer.connect("timeout", func():
		apply_periodic_effects(entities_in_smoke, current_smoke_type)
	)
	
	# Create duration timer
	var duration_timer = Timer.new()
	duration_timer.wait_time = effect_duration
	duration_timer.one_shot = true
	duration_timer.autostart = true
	smoke_area.add_child(duration_timer)
	
	# Connect duration timer for fade out
	duration_timer.connect("timeout", func():
		# Fade out collision shape
		var tween = smoke_area.create_tween()
		tween.tween_property(collision, "scale", Vector2.ZERO, 1.0)
		tween.tween_callback(func():
			# Remove effects from any remaining entities
			for entity in entities_in_smoke:
				if is_instance_valid(entity):
					clear_effects(entity, current_smoke_type)
			
			# Clean up
			smoke_area.queue_free()
			active_smoke_area = null
		)
	)

# Apply initial effects when entering smoke
func apply_entry_effect(entity, smoke_type_effects):
	# Apply special effects based on smoke type
	if "acid_damage" in smoke_type_effects and entity.has_method("apply_acid"):
		entity.apply_acid(smoke_type_effects["acid_damage"] * 2)  # Initial acid is stronger
		
	if "effects" in smoke_type_effects:
		for effect_name in smoke_type_effects["effects"]:
			if entity.has_method("apply_effects"):
				var effect_strength = smoke_type_effects["effects"][effect_name]
				entity.apply_effects(effect_name, effect_strength)

# Apply periodic effects to entities in smoke
func apply_periodic_effects(entities, smoke_type_effects):
	for entity in entities:
		if not is_instance_valid(entity):
			entities.erase(entity)
			continue
		
		# Apply vision modifier
		if "vision_modifier" in smoke_type_effects and entity.has_method("add_vision_modifier"):
			entity.add_vision_modifier("smoke", smoke_type_effects["vision_modifier"], 1.5)
		
		# Apply cloaking effect
		if smoke_type_effects.get("cloaking", false) and entity.has_method("add_effect"):
			entity.add_effect("cloaked", 1.5)
		
		# Apply acid damage
		if "acid_damage" in smoke_type_effects and entity.has_method("apply_acid"):
			entity.apply_acid(smoke_type_effects["acid_damage"])
		
		# Apply status effects
		if "effects" in smoke_type_effects:
			for effect_name in smoke_type_effects["effects"]:
				if entity.has_method("apply_effects"):
					var effect_strength = smoke_type_effects["effects"][effect_name]
					entity.apply_effects(effect_name, effect_strength)
		
		# Apply plasma/energy drain
		if "plasma_drain" in smoke_type_effects and entity.has_method("drain_plasma"):
			entity.drain_plasma(smoke_type_effects["plasma_drain"])
		
		# Purge specific gases
		if smoke_type_effects.get("purge_gases", false) and entity.has_method("remove_effect"):
			entity.remove_effect("toxic_gas")
			entity.remove_effect("sleeping_gas")
			entity.remove_effect("knockout_gas")
		
		# Purge specific chemicals
		if "purge_chemicals" in smoke_type_effects and entity.has_method("purge_chemicals"):
			entity.purge_chemicals(smoke_type_effects["purge_chemicals"])

# Clear effects when leaving smoke
func clear_effects(entity, smoke_type_effects):
	# Remove vision modifier
	if entity.has_method("remove_vision_modifier"):
		entity.remove_vision_modifier("smoke")
	
	# Remove cloaking effect
	if smoke_type_effects.get("cloaking", false) and entity.has_method("remove_effect"):
		entity.remove_effect("cloaked")

# Set the smoke type and update appearance
func set_smoke_type(type: String) -> void:
	if type in smoke_effects:
		smoke_type = type
		# Update sprite color based on smoke type
		update_appearance()
	else:
		print("Warning: Unknown smoke type '%s'" % type)

# Override update_appearance to show smoke type
func update_appearance() -> void:
	super.update_appearance()
	
	# Get sprite
	var sprite = get_node("Icon")
	
	# Adjust sprite color based on smoke type
	var current_smoke_type = smoke_effects.get(smoke_type, smoke_effects["normal"])
	var color = current_smoke_type.get("color", Color(1, 1, 1, 1))
	
	# Apply a tint to show smoke type
	sprite.modulate = Color(
		clamp(color.r * 1.2, 0, 1), 
		clamp(color.g * 1.2, 0, 1),
		clamp(color.b * 1.2, 0, 1),
		1.0
	)

# Called when the grenade is thrown
func throw_impact(hit_atom, speed: float = 5) -> bool:
	var result = super.throw_impact(hit_atom, speed)
	
	# If this is chemical warfare, record war crime
	if smoke_type in ["acid", "neuro", "satrapine"] and inventory_owner and inventory_owner.has_method("record_war_crime"):
		inventory_owner.record_war_crime()
	
	return result

# Override activate for chemical warfare types
func activate(user = null) -> bool:
	var result = super.activate(user)
	
	smoke.play("Primed")
	
	# If this is chemical warfare, record war crime
	if result and smoke_type in ["acid", "neuro", "satrapine"] and user and user.has_method("record_war_crime"):
		user.record_war_crime()
	
	return result

# Clean up when destroyed
func _exit_tree():
	# Ensure any active smoke area is cleaned up
	if active_smoke_area and is_instance_valid(active_smoke_area):
		active_smoke_area.queue_free()
		active_smoke_area = null

# Override serialization to include smoke properties
func serialize():
	var data = super.serialize()
	
	# Add smoke-specific properties
	data["smoke_type"] = smoke_type
	
	return data

func deserialize(data):
	super.deserialize(data)
	
	# Restore smoke-specific properties
	if "smoke_type" in data: 
		smoke_type = data.smoke_type
		update_appearance()
