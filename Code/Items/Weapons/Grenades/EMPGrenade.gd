extends Grenade
class_name EMPGrenade

# EMP effect ranges in tiles
var devastate_range = 0  # Most severe - level 1
var heavy_range = 2      # Heavy effect - level 2
var light_range = 5      # Light effect - level 3
var weak_range = 5       # Least severe - level 4

# Effect durations in seconds
var devastate_duration = 40
var heavy_duration = 30
var light_duration = 20
var weak_duration = 10

# Preload the EMP particle scene
var emp_particle_scene = preload("res://Scenes/Effects/EMP.tscn")
var emp_pulse_scene = preload("res://Scenes/Effects/EMP.tscn")
var emp = null

func _init():
	super._init()
	obj_name = "EMP grenade"
	obj_desc = "A compact device that releases a strong electromagnetic pulse on activation. Is capable of damaging or degrading various electronic system. Capable of being loaded in the any grenade launcher, or thrown by hand."
	grenade_type = GrenadeType.EMP
	det_time = 4.0
	dangerous = false  # Not dangerous to organics
	
	# Use the Item class variables for type categorization
	if "item_type" in self:
		self.item_type = "grenade"

func _ready():
	super._ready()
	
	emp = get_node("Icon")
	emp.play("Pin")
	
	# Ensure sprite is created
	if not has_node("Sprite2D"):
		var sprite = Sprite2D.new()
		sprite.name = "Sprite2D"
		var texture = load("res://assets/sprites/items/grenades/emp_grenade.png")
		if texture:
			sprite.texture = texture
		add_child(sprite)

func activate(user = null) -> bool:
	super.activate()
	emp.play("Primed")
	return true

# Override to create custom EMP effect
func explode() -> void:
	# Default explosion behavior
	super.explode()
	
	# Create EMP effect at the explosion position
	create_emp(global_position)

# Creates the EMP effect at the given position
func create_emp(pos: Vector2) -> void:
	# Create EMP particles
	var emp = emp_particle_scene.instantiate()
	if emp:
		get_tree().get_root().add_child(emp)
		emp.global_position = pos
		emp.emitting = true
		
		# Auto cleanup
		var timer = Timer.new()
		emp.add_child(timer)
		timer.wait_time = 5.0
		timer.one_shot = true
		timer.autostart = true
		timer.timeout.connect(func(): emp.queue_free())
	
	# Play EMP sound
	var sound = AudioStreamPlayer2D.new()
	sound.stream = load("res://Sound/Grenades/EMP.wav")
	sound.global_position = pos
	sound.autoplay = true
	sound.max_distance = 500
	sound.bus = "SFX"
	get_tree().get_root().add_child(sound)
	
	# Set a timer to free the sound node after playing
	var timer = Timer.new()
	sound.add_child(timer)
	timer.wait_time = 4.0  # Assuming sound duration is less than 4 seconds
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(func(): sound.queue_free())
	
	# Apply EMP pulse effect to objects and devices in range
	empulse(pos)
	
	# Create camera shake effect (small)
	create_camera_shake(0.5)

# Create the EMP pulse effect that affects electronics
func empulse(pos: Vector2) -> void:
	# Convert tile ranges to pixels
	var tile_size = 32
	var devastate_range_px = devastate_range * tile_size
	var heavy_range_px = heavy_range * tile_size
	var light_range_px = light_range * tile_size
	var weak_range_px = weak_range * tile_size
	
	# Get maximum range
	var max_range = max(devastate_range_px, heavy_range_px, light_range_px, weak_range_px)
	
	# Log the pulse
	print_debug("EMP pulse with ranges (", devastate_range, ", ", heavy_range, ", ", light_range, ", ", weak_range, ") at ", pos)
	
	# Apply to electronics in range
	var electronics = get_tree().get_nodes_in_group("electronics")
	var objects = get_tree().get_nodes_in_group("objects")
	var entities = get_tree().get_nodes_in_group("entities")
	
	# Create pulse visual effect
	var pulse = emp_pulse_scene.instantiate()
	pulse.global_position = pos
	pulse.scale = Vector2(max_range / 50.0, max_range / 50.0)  # Adjust as needed
	get_tree().get_root().add_child(pulse)
	
	# Auto cleanup for pulse
	var timer = Timer.new()
	pulse.add_child(timer)
	timer.wait_time = 3.0
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(func(): pulse.queue_free())
	
	# Process electronics
	for device in electronics:
		process_emp_target(device, pos)
	
	# Process objects (some may be electronic)
	for obj in objects:
		process_emp_target(obj, pos)
	
	# Process entities (some may have electronic components)
	for entity in entities:
		process_emp_target(entity, pos)

# Process a potential EMP target
func process_emp_target(target, pos: Vector2) -> void:
	if not target is Node2D:
		return
		
	var distance = target.global_position.distance_to(pos)
	var tile_size = 32
	
	# Determine severity based on distance
	var severity = 0
	var duration = 0
	
	if distance <= devastate_range * tile_size:
		severity = 1  # EMP_DEVASTATE - most severe
		duration = devastate_duration
	elif distance <= heavy_range * tile_size:
		severity = 2  # EMP_HEAVY
		duration = heavy_duration
	elif distance <= light_range * tile_size:
		severity = 3  # EMP_LIGHT
		duration = light_duration
	elif distance <= weak_range * tile_size:
		severity = 4  # EMP_WEAK - least severe
		duration = weak_duration
	
	# Apply EMP effect if in range
	if severity > 0:
		# Apply generic emp_act method if available
		if target.has_method("emp_act"):
			target.emp_act(severity)
		
		# Apply to power systems
		if "uses_power" in target and target.uses_power:
			if target.has_method("power_failure"):
				target.power_failure(duration)
		
		# Apply device-specific methods
		apply_device_specific_effects(target, severity, duration)
		
		# Visual feedback
		if target.has_method("show_emp_effect"):
			target.show_emp_effect()
		else:
			# Create a basic EMP effect on the target
			create_emp_visual_effect(target)

# Apply specific effects based on device type
func apply_device_specific_effects(target, severity: int, duration: float) -> void:
	# Check for device type property
	if "device_type" in target:
		match target.device_type:
			"camera":
				if target.has_method("emp_disable"):
					target.emp_disable(duration)
			"door":
				if target.has_method("emp_effect"):
					target.emp_effect()
				elif target.has_method("open") and randf() < 0.7:  # 70% chance to open
					target.open()
			"turret":
				if target.has_method("emp_disable"):
					target.emp_disable(duration)
				elif target.has_method("toggle_active"):
					target.toggle_active(false)
			"robot":
				if target.has_method("emp_act"):
					target.emp_act(severity)
				elif target.has_method("stunned"):
					target.stunned(duration)
			"computer":
				if target.has_method("emp_act"):
					target.emp_act(severity)
				elif target.has_method("shutdown"):
					var shutdown_duration = duration * (1.0 - (severity * 0.2))
					target.shutdown(shutdown_duration)
	
	# Check for specific components
	if target.has_node("PowerSystem"):
		var power_system = target.get_node("PowerSystem")
		if power_system.has_method("emp_act"):
			power_system.emp_act(severity)
	
	if target.has_node("ElectronicSystem"):
		var electronic_system = target.get_node("ElectronicSystem")
		if electronic_system.has_method("emp_act"):
			electronic_system.emp_act(severity)

# Create a visual EMP effect on a target
func create_emp_visual_effect(target) -> void:
	# Skip if target already has an EMP effect
	if target.has_node("EMPEffect"):
		return
	
	# Create sprite for effect
	var emp_effect = Sprite2D.new()
	emp_effect.name = "EMPEffect"
	
	# Set texture (or create simple effect)
	var texture = load("res://Assets/Effects/Particles/EMP.png")
	if texture:
		emp_effect.texture = texture
	else:
		# If texture not found, create a simple indicator
		emp_effect.scale = Vector2(0.5, 0.5)
		emp_effect.modulate = Color(0.4, 0.6, 1.0, 0.7)
	
	# Add to target
	target.add_child(emp_effect)
	
	# Create fade out effect
	var tween = target.create_tween()
	tween.tween_property(emp_effect, "modulate:a", 0.0, 1.0)
	tween.tween_callback(emp_effect.queue_free)

# Override serialization to include EMP properties
func serialize():
	var data = super.serialize()
	
	# Add EMP-specific properties
	data["devastate_range"] = devastate_range
	data["heavy_range"] = heavy_range
	data["light_range"] = light_range
	data["weak_range"] = weak_range
	data["devastate_duration"] = devastate_duration
	data["heavy_duration"] = heavy_duration
	data["light_duration"] = light_duration
	data["weak_duration"] = weak_duration
	
	return data

func deserialize(data):
	super.deserialize(data)
	
	# Restore EMP-specific properties
	if "devastate_range" in data: devastate_range = data.devastate_range
	if "heavy_range" in data: heavy_range = data.heavy_range
	if "light_range" in data: light_range = data.light_range
	if "weak_range" in data: weak_range = data.weak_range
	if "devastate_duration" in data: devastate_duration = data.devastate_duration
	if "heavy_duration" in data: heavy_duration = data.heavy_duration
	if "light_duration" in data: light_duration = data.light_duration
	if "weak_duration" in data: weak_duration = data.weak_duration
