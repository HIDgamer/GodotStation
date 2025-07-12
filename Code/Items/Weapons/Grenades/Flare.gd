extends Grenade
class_name Flare

# Flare properties
var fuel = 0  # Duration in seconds
var lower_fuel_limit = 30000  # 300 seconds (5 minutes)
var upper_fuel_limit = 30000  # 300 seconds (5 minutes)
var light_range = 3  # Tiles
var light_color = Color(1.0, 0.5, 0.2)  # Orange-red light
var light_energy = 0.8  # Light brightness

# Performance settings
var performance_mode = true  # Set to true to reduce GPU load
var min_flicker_interval = 0.3  # Less frequent flickering (was 0.1)

# References to created nodes
var active_light = null
var active_fire = null
var user_squad = null  # For squad-based targeting

# Preload the fire particle scene
var fire_particle_scene = preload("res://Scenes/Effects/Fire.tscn")
var flare = null

# Signal for target designation
signal targeting_position(pos, squad)

func _init():
	super._init()
	obj_name = "M40 FLDP flare"
	obj_desc = "A TGMC standard issue flare utilizing the standard DP canister chassis. Capable of being loaded in any grenade launcher, or thrown by hand."
	grenade_type = GrenadeType.FLARE
	det_time = 0.0  # Activates instantly
	throwforce = 1
	dangerous = false
	
	# Use the Item class variables for type categorization
	if "item_type" in self:
		self.item_type = "grenade"
	
	# Randomize fuel amount
	fuel = randi_range(lower_fuel_limit, upper_fuel_limit) / 100.0  # Convert to seconds

func _ready():
	super._ready()
	
	flare = get_node("Icon")
	flare.play("Pin")
	
	# Create light immediately if item is already active
	if active:
		call_deferred("_create_light")

func _process(delta):
	# Only process if active
	if not active:
		return
	
	# Update fuel
	if fuel > 0:
		fuel -= delta
		
		# Start fading when fuel is almost gone (last 30 seconds)
		if fuel <= 30.0 and active_light and not has_node("FadeTween"):
			_start_fade_out()
		
		# Dynamically adjust light based on remaining fuel percentage
		# Only update every second to reduce GPU load
		if active_light and fuel > 30.0 and int(fuel) % 5 == 0 and fmod(fuel, 1.0) < delta:
			var fuel_percentage = min(1.0, fuel / (lower_fuel_limit / 100.0))
			active_light.texture_scale = (light_range / 2.0) * (0.8 + 0.2 * fuel_percentage)
			active_light.energy = light_energy * (0.9 + 0.1 * fuel_percentage)
			
		# Turn off when out of fuel
		if fuel <= 0:
			turn_off()
			
	# Emit targeting signal if this is a targeting flare (once per second)
	if active and "is_targeting_flare" in self and self.is_targeting_flare and int(fuel) % 1 == 0 and fmod(fuel, 1.0) < delta:
		emit_signal("targeting_position", global_position, user_squad)

# Implement interact method for ClickSystem
func interact(user) -> bool:
	# Call parent method first to handle basic item interaction
	super.interact(user)
	
	# If the flare is on the ground and not active, activate it
	if not active and not has_flag(item_flags, ItemFlags.IN_INVENTORY):
		activate(user)
		return true
	
	# Otherwise, let the standard pickup behavior handle it
	return false

# Override attack_self to allow activation from inventory
func attack_self(user):
	if not active:
		activate(user)
		return true
	else:
		# Turn off if already active
		turn_off()
		return true
	
	return false

# Override use method to activate flare
func use(user):
	if not active:
		activate(user)
		return true
	else:
		# Turn off if already active
		turn_off()
		return true
	
	return false

# Add afterattack to handle clicking on targets with the flare
func afterattack(target, user, proximity: bool, params: Dictionary = {}):
	# If we're not in proximity, we can't use the flare on something
	if not proximity:
		return false
	
	# If the target has a method to be set on fire
	if target.has_method("add_fire_stacks"):
		target.add_fire_stacks(5)
		return true
	elif target.has_method("ignite"):
		target.ignite(5)
		return true
	
	# No applicable effect
	return false

# Add highlighting support for ClickSystem
func set_highlighted(is_highlighted: bool):
	if has_node("Sprite2D"):
		var sprite = get_node("Sprite2D")
		if is_highlighted:
			sprite.modulate = Color(1.3, 1.3, 1.3, 1.0)  # Brighter when highlighted
		else:
			# Reset to the appropriate state
			if active:
				sprite.modulate = Color(1.5, 1.5, 1.0, 1.0)  # Brighter when active
			else:
				sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Normal when inactive

# Add tooltip support for ClickSystem
func get_tooltip_text() -> String:
	var tooltip = obj_name
	
	if active:
		var minutes = int(fuel) / 60
		var seconds = int(fuel) % 60
		tooltip += " (Active: " + str(minutes) + "m " + str(seconds) + "s remaining)"
	else:
		tooltip += " (Inactive)"
	
	return tooltip

# Get interaction options for radial menu
func get_interaction_options(user) -> Array:
	var options = []
	
	# Add examine option
	options.append({
		"name": "Examine",
		"icon": "examine",
		"callback": func(): 
			if user.has_method("handle_examine"):
				user.handle_examine(self)
			elif "interaction_system" in user and user.interaction_system:
				user.interaction_system.handle_examine(user, self)
	})
	
	# Add pickup option if the flare is on the ground
	if not has_flag(item_flags, ItemFlags.IN_INVENTORY):
		options.append({
			"name": "Pick Up",
			"icon": "pickup",
			"callback": func():
				if "inventory_system" in user and user.inventory_system:
					user.inventory_system.pick_up_item(self)
		})
	
	# Add activate/deactivate option
	var action_name = "Activate" if not active else "Deactivate"
	options.append({
		"name": action_name,
		"icon": "use",
		"callback": func():
			if not active:
				activate(user)
			else:
				turn_off()
	})
	
	# Add throw option if in inventory
	if has_flag(item_flags, ItemFlags.IN_INVENTORY):
		options.append({
			"name": "Throw",
			"icon": "throw",
			"callback": func():
				if "grid_controller" in user and user.grid_controller:
					user.grid_controller.enter_throw_mode(self)
		})
	
	return options

# Override activation to handle instant activation
func activate(user = null) -> bool:
	flare.play("Primed")
	
	if active:
		return false
	
	# Set active state
	active = true
	
	# Store squad if user has one
	if user and "assigned_squad" in user and user.assigned_squad:
		user_squad = user.assigned_squad
	
	# Log bomber if user exists
	if user and "client" in user and user.client:
		# Log activation
		print("Flare activated by: ", user.name)
	
	# Play arm sound
	if has_node("ArmSound") and $ArmSound.stream:
		$ArmSound.play()
	elif arm_sound:
		var audio_player = AudioStreamPlayer2D.new()
		audio_player.stream = arm_sound
		audio_player.autoplay = true
		audio_player.position = global_position
		get_tree().get_root().add_child(audio_player)
		
		# Set up timer to free the audio node
		var timer = Timer.new()
		audio_player.add_child(timer)
		timer.wait_time = 2.0  # Adjust based on sound length
		timer.one_shot = true
		timer.autostart = true
		timer.timeout.connect(func(): audio_player.queue_free())
	
	# Update appearance
	update_appearance()
	
	# Create activation effect (simple in performance mode)
	if not performance_mode:
		_create_activation_effect()
	
	# Create light effect
	call_deferred("_create_light")
	
	# Emit signal
	emit_signal("primed", user)
	
	return true

# Create a visual effect for activation (simplified)
func _create_activation_effect():
	# Create a flash of light
	var flash = PointLight2D.new()
	flash.texture = load("res://Assets/Effects/Light/Light_Circle.png")
	if not flash.texture and has_node("PreloadedTextures/LightTexture"):
		flash.texture = $PreloadedTextures/LightTexture.texture
	flash.color = Color(1.0, 0.8, 0.5, 1.0)
	flash.energy = 0.8
	flash.texture_scale = light_range / 0.5
	flash.shadow_enabled = false  # Disable shadows for performance
	add_child(flash)
	
	# Create flash tween
	var tween = create_tween()
	tween.tween_property(flash, "energy", 0.0, 0.5)
	tween.tween_callback(func(): flash.queue_free())

# Create light and fire effects
func _create_light():
	# Create light node
	active_light = PointLight2D.new()
	active_light.name = "FlareLight"
	var light_texture = load("res://Assets/Effects/Light/Light_Circle.png")
	if light_texture:
		active_light.texture = light_texture
	elif has_node("PreloadedTextures/LightTexture"):
		active_light.texture = $PreloadedTextures/LightTexture.texture
	else:
		# Create a simple light texture if not found
		active_light.texture = create_light_texture()
	
	active_light.color = light_color
	active_light.energy = light_energy
	active_light.texture_scale = light_range
	
	# Performance settings
	if performance_mode:
		active_light.shadow_enabled = false  # Disable shadows for better performance
	else:
		active_light.shadow_enabled = true
		active_light.shadow_filter = 1  # Smooth shadows
		active_light.shadow_filter_smooth = 2.0
		
	add_child(active_light)
	
	# In performance mode, don't create the glow sprite
	if not performance_mode:
		# Create a glow sprite
		var active_glow = Sprite2D.new()
		active_glow.name = "FlareGlow"
		active_glow.texture = active_light.texture
		active_glow.modulate = Color(light_color.r, light_color.g, light_color.b, 0.4)
		active_glow.scale = Vector2(0.5, 0.5)
		active_glow.z_index = 2  # Ensure glow appears above most items
		add_child(active_glow)
	
	# Create fire effect using the preloaded scene
	active_fire = fire_particle_scene.instantiate()
	if active_fire:
		# Configure fire particles for flare - reduced for performance
		if active_fire.has_method("set_fire_properties"):
			if performance_mode:
				# In performance mode, use fewer particles
				active_fire.set_fire_properties(32, 0.6)  # Small fire radius, lower intensity
			else:
				active_fire.set_fire_properties(32)  # Small fire radius
		
		# Update particle properties if needed
		if "amount" in active_fire:
			if performance_mode:
				active_fire.amount = 25  # Fewer particles for performance
			else:
				active_fire.amount = 50
		
		# Override fire color to match flare color
		active_fire.modulate = Color(1.0, 0.8, 0.4)
		
		add_child(active_fire)
		active_fire.emitting = true
		
		# If fire has a light, adjust its properties
		if active_fire.has_node("FireLight"):
			# In performance mode, disable the second light source
			if performance_mode:
				active_fire.get_node("FireLight").queue_free()
			else:
				active_fire.get_node("FireLight").energy = 1.2
				active_fire.get_node("FireLight").texture_scale = 1.5
	
	# In performance mode, don't create sparks or smoke
	if not performance_mode:
		# Create spark particle system
		_create_sparks()
		
		# Create smoke
		_create_smoke()
	
	# Play flare sound
	var flare_sound = AudioStreamPlayer2D.new()
	flare_sound.stream = load("res://Sound/handling/flare_activate_2.ogg")
	flare_sound.volume_db = -5.0  # Slightly quieter than current
	flare_sound.max_distance = 1000.0
	flare_sound.attenuation = 2.0  # More realistic falloff
	flare_sound.autoplay = true
	flare_sound.position = global_position
	get_tree().get_root().add_child(flare_sound)
	
	# Clean up sound after playing
	var timer = Timer.new()
	flare_sound.add_child(timer)
	timer.wait_time = 4.0  # Longer sound duration
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(func(): flare_sound.queue_free())
	
	# Start flickering
	_start_flickering()

# Create spark particles (simplified)
func _create_sparks():
	# Only in full quality mode
	if performance_mode:
		return
		
	# Create spark particles
	var active_sparks = GPUParticles2D.new()
	active_sparks.name = "SparksParticles"
	
	# Create particle material
	var spark_material = ParticleProcessMaterial.new()
	spark_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	spark_material.emission_sphere_radius = 5.0
	spark_material.direction = Vector3(0, -1, 0)
	spark_material.spread = 180.0
	spark_material.initial_velocity_min = 50.0
	spark_material.initial_velocity_max = 150.0
	spark_material.gravity = Vector3(0, 100, 0)  # Sparks fall down
	spark_material.damping_min = 20.0
	spark_material.damping_max = 50.0
	spark_material.scale_min = 0.5
	spark_material.scale_max = 1.5
	
	# Setup color gradient
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1.0, 0.9, 0.4, 1.0))  # Bright yellow
	gradient.add_point(0.3, Color(1.0, 0.7, 0.2, 1.0))  # Orange
	gradient.add_point(0.7, Color(1.0, 0.4, 0.1, 1.0))  # Darker orange
	gradient.add_point(1.0, Color(0.8, 0.0, 0.0, 0.0))  # Fade to transparent
	
	var gradient_texture = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	spark_material.color_ramp = gradient_texture
	
	# Apply material to particles
	active_sparks.process_material = spark_material
	active_sparks.amount = 10  # Reduced amount for performance
	active_sparks.lifetime = 1.0
	active_sparks.explosiveness = 0.0
	active_sparks.randomness = 0.8
	active_sparks.local_coords = false
	
	# Try to load a particle texture
	var particle_texture = load("res://Assets/Effects/Particles/fire.png")
	if particle_texture:
		active_sparks.texture = particle_texture
	
	add_child(active_sparks)
	active_sparks.emitting = true

# Create smoke particles (simplified)
func _create_smoke():
	# Only in full quality mode
	if performance_mode:
		return
		
	# Create smoke particles
	var smoke = GPUParticles2D.new()
	smoke.name = "SmokeParticles"
	
	# Create particle material
	var smoke_material = ParticleProcessMaterial.new()
	smoke_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	smoke_material.emission_sphere_radius = 8.0
	smoke_material.direction = Vector3(0, -1, 0)
	smoke_material.spread = 180.0
	smoke_material.initial_velocity_min = 5.0
	smoke_material.initial_velocity_max = 15.0
	smoke_material.gravity = Vector3(0, -5, 0)  # Slight upward drift
	smoke_material.angular_velocity_min = -50.0
	smoke_material.angular_velocity_max = 50.0
	smoke_material.scale_min = 0.3
	smoke_material.scale_max = 0.8
	
	# Setup color gradient
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.7, 0.7, 0.7, 0.0))  # Start transparent
	gradient.add_point(0.1, Color(0.7, 0.7, 0.7, 0.2))  # Fade in
	gradient.add_point(0.8, Color(0.5, 0.5, 0.5, 0.2))  # Darker gray
	gradient.add_point(1.0, Color(0.3, 0.3, 0.3, 0.0))  # Fade out
	
	var gradient_texture = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	smoke_material.color_ramp = gradient_texture
	
	# Apply material to particles
	smoke.process_material = smoke_material
	smoke.amount = 15  # Reduced for performance
	smoke.lifetime = 4.0
	smoke.explosiveness = 0.05
	smoke.randomness = 0.6
	smoke.local_coords = false
	smoke.z_index = -1  # Render behind the flare
	
	# Try to load a particle texture
	var particle_texture = load("res://Assets/Effects/Particles/Smoke.png")
	if particle_texture:
		smoke.texture = particle_texture
	
	add_child(smoke)
	smoke.emitting = true

# Start subtle flickering effect for the light
func _start_flickering():
	if not active_light:
		return
	
	if has_node("FlickerTimer"):
		$FlickerTimer.wait_time = min_flicker_interval  # Less frequent updates
		$FlickerTimer.start()
	else:
		var flicker_timer = Timer.new()
		flicker_timer.name = "FlickerTimer"
		flicker_timer.wait_time = min_flicker_interval  # Less frequent (was 0.1)
		flicker_timer.autostart = true
		flicker_timer.timeout.connect(_flicker_light)
		add_child(flicker_timer)

# Random small changes to light energy (simplified)
func _flicker_light():
	if not active_light:
		return
	
	# More dynamic flickering based on fuel level
	var fuel_percentage = min(1.0, fuel / (lower_fuel_limit / 100.0))
	
	# Less intense flicker in performance mode
	var flicker_intensity = 0.07 if performance_mode else 0.1 + (0.2 * (1.0 - fuel_percentage))
	var flicker_amount = randf_range(-flicker_intensity, flicker_intensity)
	
	# Apply flickering to main light
	active_light.energy = clamp(light_energy + flicker_amount, light_energy * 0.7, light_energy * 1.3)
	
	# Apply flickering to glow sprite if it exists
	if has_node("FlareGlow"):
		$FlareGlow.modulate.a = clamp(0.4 + (flicker_amount * 0.3), 0.1, 0.7)
		
		# Simplified scale changes
		if not performance_mode:
			var scale_change = randf_range(-0.05, 0.05)
			$FlareGlow.scale = Vector2(0.5, 0.5) * (1.0 + scale_change)
	
	# Fire particles can flicker too if they exist
	if active_fire and active_fire.has_node("FireLight"):
		active_fire.get_node("FireLight").energy = randf_range(0.8, 1.2)

# Start fading out the light (simplified)
func _start_fade_out():
	# Create a marker node to track the fade process
	var fade_node = Node.new()
	fade_node.name = "FadeTween"
	add_child(fade_node)
	
	# Create the tween
	var tween = create_tween()
	
	# Gradually reduce light energy
	if active_light:
		tween.tween_property(active_light, "energy", 0.0, 30.0)
	
	# Fade out glow if it exists
	if has_node("FlareGlow"):
		tween.parallel().tween_property($FlareGlow, "modulate:a", 0.0, 30.0)
	
	# If we have fire effect, fade it too
	if active_fire:
		tween.parallel().tween_property(active_fire, "modulate:a", 0.0, 30.0)
		
	# Fade out sparks if they exist
	if has_node("SparksParticles"):
		tween.parallel().tween_property($SparksParticles, "modulate:a", 0.0, 15.0)
	
	# Connect to finished signal to clean up the marker node
	tween.finished.connect(func(): 
		if is_instance_valid(fade_node):
			fade_node.queue_free()
	)

# Turn off the flare
func turn_off():
	active = false
	fuel = 0
	
	# Update appearance
	update_appearance()
	
	# Clean up light and fire
	if active_light:
		active_light.queue_free()
		active_light = null
	
	if active_fire:
		active_fire.queue_free()
		active_fire = null
	
	# Clean up other nodes
	for node in ["FlareGlow", "SparksParticles", "SmokeParticles"]:
		if has_node(node):
			get_node(node).queue_free()
	
	# Stop flickering
	if has_node("FlickerTimer"):
		$FlickerTimer.stop()
	
	# Remove any tweens
	if has_node("FadeTween"):
		get_node("FadeTween").queue_free()

# Override explode to prevent destruction
func explode():
	# Don't destroy the flare, just activate it
	if not active:
		activate()

# Create custom throw impact behavior
func throw_impact(hit_atom, speed: float = 5) -> bool:
	# In full quality mode, create impact effects
	if not performance_mode and speed > 3.0:
		_create_simple_impact_effect(speed)
	
	# Handle impact with open turf
	if hit_atom and "is_open_turf" in hit_atom and hit_atom.is_open_turf:
		# Check for alien weeds
		var nodes = get_tree().get_nodes_in_group("alien_weed_nodes")
		for node in nodes:
			if node.global_position.distance_to(global_position) < 16:  # Half a tile
				# Burn alien weeds
				node.queue_free()
				
				# Turn off the flare
				turn_off()
				break
	
	# Handle impact with living entities
	if hit_atom and hit_atom.is_in_group("entities") and active:
		# Set them on fire
		if hit_atom.has_method("add_fire_stacks"):
			hit_atom.add_fire_stacks(5)
		elif hit_atom.has_method("ignite"):
			hit_atom.ignite(5)
			
		# Apply direct damage if flare was launched
		if launched and hit_atom.has_method("take_damage"):
			var damage = randf_range(throwforce * 0.75, throwforce * 1.25)
			
			# Check if target has a targeted zone
			var target_zone = "chest"
			if "zone_selected" in hit_atom and hit_atom.zone_selected:
				target_zone = hit_atom.zone_selected
				
			hit_atom.take_damage(damage, "burn", target_zone)
	
	return true

# Simplified impact effect
func _create_simple_impact_effect(speed: float):
	# Play impact sound
	var impact_sound = AudioStreamPlayer2D.new()
	impact_sound.stream = load("res://Sound/effects/thud.ogg")
	if not impact_sound.stream:
		impact_sound.stream = load("res://Sound/handling/flare_activate_2.ogg")
		
	impact_sound.volume_db = -10.0
	impact_sound.pitch_scale = randf_range(0.9, 1.1)
	impact_sound.autoplay = true
	impact_sound.position = global_position
	get_tree().get_root().add_child(impact_sound)
	
	# Set up sound cleanup timer
	var sound_timer = Timer.new()
	impact_sound.add_child(sound_timer)
	sound_timer.wait_time = 2.0
	sound_timer.one_shot = true
	sound_timer.autostart = true
	sound_timer.timeout.connect(func(): impact_sound.queue_free())

# Create a light texture if needed
func create_light_texture() -> Texture2D:
	var size = 128  # Reduced size for performance (was 256)
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	
	# Create a simpler light texture
	var center = Vector2(size/2, size/2)
	for x in range(size):
		for y in range(size):
			var dist = Vector2(x, y).distance_to(center)
			if dist <= size/2:
				var alpha = 1.0 - dist/(size/2)
				image.set_pixel(x, y, Color(1, 1, 1, alpha))
	
	return ImageTexture.create_from_image(image)

# Helper function for smooth interpolation
func smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

# Override prime to handle flare behavior
func prime() -> void:
	# Don't explode, just ensure active
	if not active:
		activate()

# Override update_appearance to show active state
func update_appearance() -> void:
	super.update_appearance()
	
	# Update sprite based on active state
	if has_node("Sprite2D"):
		var sprite = get_node("Sprite2D")
		if active:
			sprite.modulate = Color(1.5, 1.5, 1.0, 1.0)  # Brighter when active
		else:
			sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Normal when inactive

# Create a targeting flare variant
func create_targeting_flare(stronger: bool = false) -> Flare:
	var targeting_flare = Flare.new()
	targeting_flare.obj_name = "M50 CFDP signal flare"
	targeting_flare.obj_desc = "A TGMC signal flare utilized for targeting. When activated, provides a target for CAS pilots."
	
	# Special properties
	targeting_flare.is_targeting_flare = true
	targeting_flare.light_color = Color(0, 1, 0)  # Green light
	
	# Lower fuel for targeting flares
	targeting_flare.lower_fuel_limit = 2500  # 25 seconds
	targeting_flare.upper_fuel_limit = 3000  # 30 seconds
	
	# Stronger variant gets extra brightness and range
	if stronger:
		targeting_flare.light_range = 12
		targeting_flare.light_energy = 1.5
		
		# Make it harder to move once deployed
		targeting_flare.pickupable = false
		
		# Make the stronger variant cyan colored
		targeting_flare.light_color = Color(0, 1, 1)  # Cyan light
	
	return targeting_flare

# Serialize for saving
func serialize():
	var data = super.serialize()
	data["fuel"] = fuel
	data["lower_fuel_limit"] = lower_fuel_limit
	data["upper_fuel_limit"] = upper_fuel_limit
	data["light_range"] = light_range
	data["light_color"] = {
		"r": light_color.r,
		"g": light_color.g,
		"b": light_color.b,
		"a": light_color.a
	}
	data["performance_mode"] = performance_mode
	data["active"] = active
	
	return data

# Deserialize for loading
func deserialize(data):
	super.deserialize(data)
	
	if "fuel" in data: fuel = data.fuel
	if "lower_fuel_limit" in data: lower_fuel_limit = data.lower_fuel_limit
	if "upper_fuel_limit" in data: upper_fuel_limit = data.upper_fuel_limit
	if "light_range" in data: light_range = data.light_range
	if "performance_mode" in data: performance_mode = data.performance_mode
	
	if "light_color" in data:
		var color_data = data.light_color
		light_color = Color(color_data.r, color_data.g, color_data.b, color_data.a)
	
	if "active" in data and data.active:
		# Activate without a user
		activate(null)
