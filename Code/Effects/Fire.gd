extends Area2D

# Fire properties
var burn_damage = 5.0
var burn_stacks = 10
var duration = 15.0  # Seconds
var burn_interval = 1.0  # Seconds between damage ticks
var heat = 800  # Heat level (affects nearby objects)
var entities_in_fire = []
var timer = 0.0
var flame = null

func _ready():
	# Create timers if they don't exist
	if not has_node("DurationTimer"):
		var duration_timer = Timer.new()
		duration_timer.name = "DurationTimer"
		add_child(duration_timer)
		duration_timer.timeout.connect(_on_duration_timer_timeout)
	
	if not has_node("BurnTimer"):
		var burn_timer = Timer.new()
		burn_timer.name = "BurnTimer"
		add_child(burn_timer)
		burn_timer.timeout.connect(_on_burn_timer_timeout)
	
	if not has_node("FlickerTimer"):
		var flicker_timer = Timer.new()
		flicker_timer.name = "FlickerTimer"
		add_child(flicker_timer)
		flicker_timer.timeout.connect(_on_flicker_timer_timeout)
	
	# Start the burn timer
	$DurationTimer.wait_time = duration
	$DurationTimer.start()
	
	# Start the burn interval timer
	$BurnTimer.wait_time = burn_interval
	$BurnTimer.start()
	
	# Start the flicker timer for the light
	$FlickerTimer.start()
	
	# Get flame animation reference
	flame = get_node_or_null("Flame")
	
	# Connect signals if they're not already connected
	if not is_connected("body_entered", _on_body_entered):
		connect("body_entered", _on_body_entered)
	
	if not is_connected("body_exited", _on_body_exited):
		connect("body_exited", _on_body_exited)

func _process(delta):
	# Track overall duration
	timer += delta
	
	# If we exceed duration, begin fading out
	if timer >= duration and not $FadeOut and not has_node("FadeOut"):
		start_fade_out()
	
	# Play flame animation if it exists
	if flame and flame.has_method("play"):
		flame.play()

func _on_body_entered(body):
	# Track entities that enter the fire
	if body.is_in_group("entities") and not body in entities_in_fire:
		entities_in_fire.append(body)
		
		# Initial ignition
		if object_has_method(body, "ignite"):
			body.ignite(burn_stacks)
		elif object_has_method(body, "add_fire_stacks"):
			body.add_fire_stacks(burn_stacks)
		
		# Initial damage
		if object_has_method(body, "take_damage"):
			body.take_damage(burn_damage, "fire", "fire")

func _on_body_exited(body):
	# Remove entities that leave the fire
	if body in entities_in_fire:
		entities_in_fire.erase(body)

func _on_burn_timer_timeout():
	# Apply burn damage to all entities in the fire
	for entity in entities_in_fire:
		if not is_instance_valid(entity):
			entities_in_fire.erase(entity)
			continue
			
		# Apply burn damage
		if object_has_method(entity, "take_damage"):
			entity.take_damage(burn_damage, "fire", "fire")
		
		# Ensure entity stays on fire
		if object_has_method(entity, "add_fire_stacks"):
			entity.add_fire_stacks(2)  # Maintain fire

func _on_flicker_timer_timeout():
	# Random light flicker
	var fire_light = get_node_or_null("FireLight")
	if fire_light:
		fire_light.energy = randf_range(0.8, 1.2)

func _on_duration_timer_timeout():
	# Start fading out when duration expires
	start_fade_out()

func start_fade_out():
	# Create a new node to handle the fade out
	var fade_out = Node.new()
	fade_out.name = "FadeOut"
	add_child(fade_out)
	
	# Create a tween for fading
	var tween = create_tween()
	var fire_particles = get_node_or_null("FireParticles")
	var fire_light = get_node_or_null("FireLight")
	
	if fire_particles:
		tween.tween_property(fire_particles, "modulate:a", 0.0, 2.0)
	
	if fire_light:
		tween.parallel().tween_property(fire_light, "energy", 0.0, 2.0)
	
	tween.tween_callback(queue_free)
	
	# Stop burning entities
	if has_node("BurnTimer"):
		$BurnTimer.stop()
	
	# Reduce collision shape to prevent new entities from being affected
	var collision = get_node_or_null("CollisionShape2D")
	if collision:
		var tween2 = create_tween()
		tween2.tween_property(collision, "scale", Vector2.ZERO, 1.0)

# Check if an object has a method (renamed to avoid conflict with built-in has_method)
func object_has_method(obj, method_name: String) -> bool:
	return obj and is_instance_valid(obj) and obj.has_method(method_name)

# Use to set fire properties externally
func set_fire_properties(new_damage: float, new_burn_stacks: int, new_duration: float, new_heat: float = 800) -> void:
	burn_damage = new_damage
	burn_stacks = new_burn_stacks
	duration = new_duration
	heat = new_heat
	
	# Update the duration timer
	if has_node("DurationTimer"):
		$DurationTimer.wait_time = duration
		$DurationTimer.start()

# Manually spread fire to nearby flammable objects
func try_spread_fire() -> void:
	var flammable_objects = get_tree().get_nodes_in_group("flammable")
	
	for object in flammable_objects:
		if not is_instance_valid(object):
			continue
			
		# Check if within range to spread
		if object.global_position.distance_to(global_position) < 64:  # 2 tiles
			# Skip if already on fire
			if "on_fire" in object and object.on_fire:
				continue
				
			# Random chance to spread based on heat
			var spread_chance = heat / 2000.0  # 40% chance at 800 heat
			if randf() < spread_chance:
				if object_has_method(object, "ignite"):
					object.ignite(burn_stacks / 2)  # Lower intensity when spreading
				elif object_has_method(object, "set_on_fire"):
					object.set_on_fire(duration / 2)  # Shorter duration when spreading
