extends GPUParticles2D
class_name EMPEffect

# Constants
const DEFAULT_LIFETIME = 1.5
const DEFAULT_AMOUNT = 200
const DEFAULT_RADIUS = 150.0  # Default radius in pixels
const DEFAULT_DURATION = 3.0  # How long the effect stays visible

# Variables
var emp_radius = DEFAULT_RADIUS
var emp_intensity = 1.0  # Scaling factor for intensity
var emp_color = Color(0.2, 0.4, 1.0, 1.0)  # Default blue EMP color
var emp_secondary_color = Color(0.5, 0.7, 1.0, 0.7)  # Secondary color
var emp_duration = DEFAULT_DURATION
var spark_emitter = null  # Reference to the spark emitter

# Visual components
var core_ring = null
var pulse_wave = null
var electric_arcs = null
var sparkles = null
var secondary_rings = []
var distortion_field = null
var energy_field = null
var impact_particles = null

# Sound components
var emp_sound = null
var electricity_sound = null
var pulse_sound = null

# State tracking
var active_electronics = []  # Track electronics affected by the EMP
var time_elapsed = 0.0
var arc_points = []  # Store points for arcs to create more natural flow

func _ready():
	# Set up basic properties
	emitting = false
	one_shot = true
	explosiveness = 1.0  # Burst all particles at once
	randomness = 0.3
	lifetime = DEFAULT_LIFETIME
	amount = DEFAULT_AMOUNT
	
	# Make sure we have a process material
	if not process_material:
		setup_particle_material()
	
	# Set up all visual components
	setup_visual_components()
	
	# Set up sounds
	setup_sounds()
	
	# Set up light sources
	setup_lighting()
	
	# Generate electric field points
	generate_arc_points()
	
	# Set lifetime timer
	if has_node("LifetimeTimer"):
		$LifetimeTimer.wait_time = emp_duration
		$LifetimeTimer.start()
	else:
		var timer = Timer.new()
		timer.name = "LifetimeTimer"
		timer.wait_time = emp_duration
		timer.one_shot = true
		timer.autostart = true
		timer.timeout.connect(_on_lifetime_timer_timeout)
		add_child(timer)
	
	# Set up arc update timer
	var arc_timer = Timer.new()
	arc_timer.name = "ArcTimer"
	arc_timer.wait_time = 0.05
	arc_timer.autostart = true
	arc_timer.timeout.connect(_on_arc_timer_timeout)
	add_child(arc_timer)
	
	# Set up pulse timer
	var pulse_timer = Timer.new()
	pulse_timer.name = "PulseTimer"
	pulse_timer.wait_time = 0.35
	pulse_timer.autostart = true
	pulse_timer.timeout.connect(_on_pulse_timer_timeout)
	add_child(pulse_timer)

func _process(delta):
	time_elapsed += delta
	
	# Update spark animation if present
	if spark_emitter and spark_emitter.has_method("play"):
		spark_emitter.play()
	
	# Update electrical arc positions
	update_electrical_arcs()
	
	# Update electronics affected by EMP
	update_affected_electronics(delta)
	
	# Rotate energy field for dynamic effect
	if energy_field:
		energy_field.rotation += delta * 0.5

# Generate points for more natural looking arcs
func generate_arc_points():
	arc_points.clear()
	
	# Create a field of potential points for arcs to travel through
	var num_points = 40
	for i in range(num_points):
		var distance = randf_range(emp_radius * 0.1, emp_radius * 0.6)
		var angle = randf() * TAU
		var point = Vector2(cos(angle), sin(angle)) * distance
		arc_points.append(point)

# Set up the particle material
func setup_particle_material():
	var material = ParticleProcessMaterial.new()
	
	# Emission settings
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = emp_radius * 0.1
	
	# Movement
	material.direction = Vector3(0, 0, 0)
	material.spread = 180.0
	material.gravity = Vector3(0, 0, 0)
	material.initial_velocity_min = 50.0 * emp_intensity
	material.initial_velocity_max = 150.0 * emp_intensity
	
	# Appearance
	material.scale_min = 0.5
	material.scale_max = 2.0
	
	# Color gradient for EMP effect
	var gradient = Gradient.new()
	gradient.add_point(0, Color(0.2, 0.4, 1.0, 1.0))  # Blue
	gradient.add_point(0.3, Color(0.4, 0.8, 1.0, 0.8))  # Light blue
	gradient.add_point(0.7, Color(0.2, 0.6, 1.0, 0.5))  # Fading blue
	gradient.add_point(1.0, Color(0.1, 0.3, 0.8, 0.0))  # Transparent blue
	
	var gradient_texture = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	
	material.color_ramp = gradient_texture
	
	# Turbulence for more chaotic movement
	material.turbulence_enabled = true
	material.turbulence_noise_strength = 0.3
	material.turbulence_noise_scale = 1.5
	
	# Apply material
	process_material = material

# Setup all visual components
func setup_visual_components():
	# Set up core ring (the central EMP ring)
	setup_core_ring()
	
	# Set up pulse wave (expanding shockwave)
	setup_pulse_wave()
	
	# Set up electric arcs (lightning bolts)
	setup_electric_arcs()
	
	# Set up sparkle particles (small bright points)
	setup_sparkles()
	
	# Set up secondary rings
	setup_secondary_rings()
	
	# Set up distortion field
	setup_distortion_field()
	
	# Set up energy field
	setup_energy_field()
	
	# Set up impact particles
	setup_impact_particles()
	
	# Set up spark emitter
	setup_spark_emitter()

# Setup core ring effect
func setup_core_ring():
	core_ring = get_node_or_null("CoreRing")
	if not core_ring:
		core_ring = GPUParticles2D.new()
		core_ring.name = "CoreRing"
		core_ring.emitting = false
		core_ring.one_shot = true
		core_ring.explosiveness = 1.0
		core_ring.lifetime = 0.8
		core_ring.amount = 1
		add_child(core_ring)
		
		# Setup material
		var material = ParticleProcessMaterial.new()
		material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
		material.direction = Vector3(0, 0, 0)
		material.spread = 180.0
		material.gravity = Vector3(0, 0, 0)
		material.initial_velocity_min = 0.0
		material.initial_velocity_max = 0.0
		
		material.scale_min = 1.0
		material.scale_max = 1.0
		
		# Scale over lifetime
		var curve = Curve.new()
		curve.add_point(Vector2(0, 0.2))
		curve.add_point(Vector2(0.1, 1.0))
		curve.add_point(Vector2(0.6, 1.2))
		curve.add_point(Vector2(0.8, 1.3))  # Slightly larger peak
		curve.add_point(Vector2(1.0, 0.0))
		
		var scale_curve = CurveTexture.new()
		scale_curve.curve = curve
		material.scale_curve = scale_curve
		
		# Color over lifetime
		var gradient = Gradient.new()
		gradient.add_point(0.0, Color(1.0, 1.0, 1.0, 1.0))
		gradient.add_point(0.2, Color(emp_color.r, emp_color.g, emp_color.b, 1.0))
		gradient.add_point(0.8, Color(emp_color.r, emp_color.g, emp_color.b, 0.7))
		gradient.add_point(1.0, Color(emp_color.r, emp_color.g, emp_color.b, 0.0))
		
		var gradient_texture = GradientTexture1D.new()
		gradient_texture.gradient = gradient
		material.color_ramp = gradient_texture
		
		core_ring.process_material = material

# Setup pulse wave effect
func setup_pulse_wave():
	pulse_wave = get_node_or_null("PulseWave")
	if not pulse_wave:
		pulse_wave = GPUParticles2D.new()
		pulse_wave.name = "PulseWave"
		pulse_wave.emitting = false
		pulse_wave.one_shot = true
		pulse_wave.explosiveness = 1.0
		pulse_wave.lifetime = 1.2
		pulse_wave.amount = 3
		add_child(pulse_wave)
		
		# Setup material
		var material = ParticleProcessMaterial.new()
		material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
		material.direction = Vector3(0, 0, 0)
		material.spread = 180.0
		material.gravity = Vector3(0, 0, 0)
		material.initial_velocity_min = 200.0 * emp_intensity
		material.initial_velocity_max = 500.0 * emp_intensity
		
		material.scale_min = 1.0
		material.scale_max = 1.0
		
		# Scale over lifetime
		var curve = Curve.new()
		curve.add_point(Vector2(0, 0.0))
		curve.add_point(Vector2(0.3, 0.3))
		curve.add_point(Vector2(0.6, 0.6))
		curve.add_point(Vector2(1.0, 1.0))
		
		var scale_curve = CurveTexture.new()
		scale_curve.curve = curve
		material.scale_curve = scale_curve
		
		# Color over lifetime
		var gradient = Gradient.new()
		gradient.add_point(0.0, Color(emp_color.r + 0.7, emp_color.g + 0.7, emp_color.b + 0.5, 0.9))
		gradient.add_point(0.3, Color(emp_color.r, emp_color.g, emp_color.b, 0.7))
		gradient.add_point(0.6, Color(emp_color.r, emp_color.g, emp_color.b, 0.3))
		gradient.add_point(1.0, Color(emp_color.r, emp_color.g, emp_color.b, 0.0))
		
		var gradient_texture = GradientTexture1D.new()
		gradient_texture.gradient = gradient
		material.color_ramp = gradient_texture
		
		pulse_wave.process_material = material

# Setup electric arcs effect
func setup_electric_arcs():
	electric_arcs = get_node_or_null("ElectricArcs")
	if not electric_arcs:
		electric_arcs = Node2D.new()
		electric_arcs.name = "ElectricArcs"
		add_child(electric_arcs)
		
		# Create initial arcs
		for i in range(8):  # Increased from 5 to 8
			create_electric_arc()

# Create a single electric arc with more natural branching
func create_electric_arc():
	var arc = Line2D.new()
	arc.width = randf_range(1.5, 3.0)  # Varied widths
	arc.width_curve = create_arc_width_curve()  # Tapered width
	
	# Create a more electric blue color with variation
	var hue_variation = randf_range(-0.05, 0.05)
	var brightness_variation = randf_range(0.0, 0.3)
	var arc_color = emp_color.lightened(0.5 + brightness_variation)
	arc_color.h += hue_variation
	
	arc.default_color = arc_color
	arc.begin_cap_mode = Line2D.LINE_CAP_ROUND
	arc.end_cap_mode = Line2D.LINE_CAP_ROUND
	
	# Add gradient to the arc
	var gradient = Gradient.new()
	gradient.add_point(0.0, arc_color.lightened(0.2))
	gradient.add_point(0.5, arc_color)
	gradient.add_point(1.0, arc_color.lightened(0.3))
	arc.gradient = gradient
	
	# Create random lightning shape
	var start_point = Vector2(randf_range(-emp_radius * 0.1, emp_radius * 0.1), 
							 randf_range(-emp_radius * 0.1, emp_radius * 0.1))
	var end_point = Vector2.from_angle(randf() * 2 * PI) * randf_range(emp_radius * 0.3, emp_radius * 0.7)
	
	arc.add_point(start_point)
	
	# Create more natural arc by sometimes routing through pre-generated arc points
	var distance = start_point.distance_to(end_point)
	var direction = (end_point - start_point).normalized()
	var segment_count = int(distance / 8.0)  # More segments for higher detail
	
	# Choose random path type (direct or through field)
	var through_field = randf() < 0.7  # 70% chance to go through field points
	
	if through_field and arc_points.size() > 0:
		# Find viable arc points that are roughly in our direction
		var viable_points = []
		for point in arc_points:
			var to_point = point - start_point
			if to_point.length() < distance and to_point.normalized().dot(direction) > 0.3:
				viable_points.append(point)
		
		# Use some arc points if available
		if viable_points.size() > 0:
			viable_points.shuffle()
			var num_to_use = min(viable_points.size(), 2 + randi() % 3)  # Use 2-4 points
			
			for i in range(num_to_use):
				var mid_point = viable_points[i]
				
				# Add some zigzag between current point and mid point
				var current = arc.get_point_position(arc.get_point_count() - 1)
				var to_mid = mid_point - current
				var mid_segments = int(to_mid.length() / 10.0)
				
				for j in range(mid_segments):
					var t = float(j) / mid_segments
					var segment_point = current.lerp(mid_point, t)
					var perp_scale = 1.0 - abs(2.0 * t - 1.0)  # Peak in the middle
					var perpendicular = Vector2(-to_mid.y, to_mid.x).normalized() * randf_range(-8, 8) * perp_scale
					
					# Add small branches occasionally (10% chance per segment)
					if randf() < 0.1:
						create_branch(arc, segment_point + perpendicular, randf_range(10, 20))
						
					arc.add_point(segment_point + perpendicular)
				
				arc.add_point(mid_point)
	
	# Add final zigzag points to the destination
	var current = arc.get_point_position(arc.get_point_count() - 1)
	var to_end = end_point - current
	var final_segments = int(to_end.length() / 8.0)
	
	for i in range(final_segments):
		var t = float(i) / final_segments
		var segment_point = current.lerp(end_point, t)
		var perp_scale = (1.0 - t) * 0.7  # Reduce zigzag near the end
		var perpendicular = Vector2(-to_end.y, to_end.x).normalized() * randf_range(-10, 10) * perp_scale
		
		# Add small branches occasionally (15% chance per segment)
		if randf() < 0.15:
			create_branch(arc, segment_point + perpendicular, randf_range(10, 25))
			
		arc.add_point(segment_point + perpendicular)
	
	arc.add_point(end_point)
	
	# Add a small end flare
	create_branch(arc, end_point, randf_range(5, 15))
	
	# Add to arcs container
	electric_arcs.add_child(arc)
	
	# Set up auto-destruction with random timing
	var timer = Timer.new()
	timer.wait_time = randf_range(0.1, 0.3)
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(func(): 
		# Sometimes replace with a new arc
		if randf() < 0.7:  # 70% chance to replace
			create_electric_arc() 
		arc.queue_free()
	)
	arc.add_child(timer)
	
	return arc

# Create a small branch from the main arc
func create_branch(parent_arc: Line2D, start_point: Vector2, length: float):
	var branch = Line2D.new()
	branch.width = parent_arc.width * 0.7  # Slightly thinner
	branch.default_color = parent_arc.default_color.lightened(0.2)  # Slightly brighter
	
	# Create a width curve that tapers off
	var width_curve = Curve.new()
	width_curve.add_point(Vector2(0, 1.0))
	width_curve.add_point(Vector2(1.0, 0.0))
	branch.width_curve = width_curve
	
	# Random branch direction
	var branch_angle = randf_range(-PI/4, PI/4)
	var branch_dir = Vector2.from_angle(branch_angle)
	
	branch.add_point(start_point)
	
	# Create small zigzag branch
	var segments = 3 + randi() % 3  # 3-5 segments
	var end_point = start_point + branch_dir.rotated(randf_range(-0.5, 0.5)) * length
	
	for i in range(segments):
		var t = float(i+1) / segments
		var segment_point = start_point.lerp(end_point, t)
		var perpendicular = Vector2(-branch_dir.y, branch_dir.x) * randf_range(-5, 5) * (1.0 - t)
		branch.add_point(segment_point + perpendicular)
	
	# Add to parent arc's parent (electric_arcs node)
	electric_arcs.add_child(branch)
	
	# Set up auto-destruction
	var timer = Timer.new()
	timer.wait_time = randf_range(0.05, 0.2)  # Shorter lifetime than main arcs
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(func(): branch.queue_free())
	branch.add_child(timer)
	
	return branch

# Create a width curve for arcs that tapers at the ends
func create_arc_width_curve() -> Curve:
	var curve = Curve.new()
	curve.add_point(Vector2(0, 0.7))  # Start slightly thinner
	curve.add_point(Vector2(0.1, 1.0))  # Quickly reach full width
	curve.add_point(Vector2(0.9, 1.0))  # Maintain full width
	curve.add_point(Vector2(1.0, 0.5))  # Taper at the end
	return curve

# Update electrical arcs
func update_electrical_arcs():
	# Maintain a certain number of arcs
	var desired_arcs = 6 + int(2 * emp_intensity)
	var current_arcs = 0
	
	# Count actual arcs (not branches)
	for child in electric_arcs.get_children():
		if child is Line2D and child.get_point_count() > 4:  # Main arcs have more points
			current_arcs += 1
	
	if current_arcs < desired_arcs:
		create_electric_arc()

# Arc timer callback - occasionally create new arcs
func _on_arc_timer_timeout():
	if randf() < 0.6:  # 60% chance each time (increased from 50%)
		create_electric_arc()
		
	# Periodically regenerate arc points for variety
	if randf() < 0.2:  # 20% chance
		generate_arc_points()

# Setup sparkle particles
func setup_sparkles():
	sparkles = get_node_or_null("Sparkles")
	if not sparkles:
		sparkles = GPUParticles2D.new()
		sparkles.name = "Sparkles"
		sparkles.emitting = false
		sparkles.lifetime = 0.5
		sparkles.amount = 80  # Increased from 50
		add_child(sparkles)
		
		# Setup material
		var material = ParticleProcessMaterial.new()
		material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		material.emission_sphere_radius = emp_radius * 0.5
		material.direction = Vector3(0, 0, 0)
		material.spread = 180.0
		material.gravity = Vector3(0, 0, 0)
		material.initial_velocity_min = 0.0
		material.initial_velocity_max = 20.0
		
		# Add attraction to origin for swirling effect
		material.attractor_interaction_enabled = true
		material.attractor_strength = 20.0
		material.attractor_attenuation = 1.0
		material.attractor_directionality = 0.2
		
		material.scale_min = 0.1
		material.scale_max = 0.4  # Slightly larger max
		
		# Color over lifetime
		var gradient = Gradient.new()
		gradient.add_point(0.0, Color(1.0, 1.0, 1.0, 1.0))
		gradient.add_point(0.3, Color(emp_color.r + 0.5, emp_color.g + 0.5, emp_color.b + 0.5, 0.9))
		gradient.add_point(0.6, Color(emp_color.r, emp_color.g, emp_color.b, 0.6))
		gradient.add_point(1.0, Color(emp_color.r, emp_color.g, emp_color.b, 0.0))
		
		var gradient_texture = GradientTexture1D.new()
		gradient_texture.gradient = gradient
		material.color_ramp = gradient_texture
		
		sparkles.process_material = material

# Setup secondary rings
func setup_secondary_rings():
	# Create 5 secondary expanding rings with different timings (increased from 3)
	for i in range(5):
		var ring = get_node_or_null("SecondaryRing" + str(i))
		if not ring:
			ring = GPUParticles2D.new()
			ring.name = "SecondaryRing" + str(i)
			ring.emitting = false
			ring.one_shot = true
			ring.explosiveness = 1.0
			ring.lifetime = 0.8 + i * 0.15  # Staggered lifetimes
			ring.amount = 1
			add_child(ring)
			
			# Setup material
			var material = ParticleProcessMaterial.new()
			material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
			material.direction = Vector3(0, 0, 0)
			material.spread = 180.0
			material.gravity = Vector3(0, 0, 0)
			material.initial_velocity_min = 0.0
			material.initial_velocity_max = 0.0
			
			material.scale_min = 1.0
			material.scale_max = 1.0
			
			# Scale over lifetime - different pattern for each ring
			var curve = Curve.new()
			if i % 2 == 0:
				# Even rings - standard growth
				curve.add_point(Vector2(0, 0.2 + i * 0.1))
				curve.add_point(Vector2(0.7, 0.8 + i * 0.1))
				curve.add_point(Vector2(1.0, 1.0 + i * 0.1))
			else:
				# Odd rings - pulse growth
				curve.add_point(Vector2(0, 0.1 + i * 0.1))
				curve.add_point(Vector2(0.3, 0.5 + i * 0.05))
				curve.add_point(Vector2(0.6, 0.7 + i * 0.08))
				curve.add_point(Vector2(1.0, 1.0 + i * 0.1))
			
			var scale_curve = CurveTexture.new()
			scale_curve.curve = curve
			material.scale_curve = scale_curve
			
			# Color over lifetime
			var gradient = Gradient.new()
			
			# Alternate color patterns for more variety
			if i % 2 == 0:
				gradient.add_point(0.0, Color(emp_secondary_color.r, emp_secondary_color.g, emp_secondary_color.b, 0.7))
				gradient.add_point(0.6, Color(emp_secondary_color.r, emp_secondary_color.g, emp_secondary_color.b, 0.4))
				gradient.add_point(1.0, Color(emp_secondary_color.r, emp_secondary_color.g, emp_secondary_color.b, 0.0))
			else:
				gradient.add_point(0.0, Color(emp_color.r, emp_color.g, emp_color.b, 0.6))
				gradient.add_point(0.5, Color(emp_secondary_color.r, emp_secondary_color.g, emp_secondary_color.b, 0.4))
				gradient.add_point(1.0, Color(emp_color.r + 0.2, emp_color.g + 0.2, emp_color.b + 0.2, 0.0))
			
			var gradient_texture = GradientTexture1D.new()
			gradient_texture.gradient = gradient
			material.color_ramp = gradient_texture
			
			ring.process_material = material
			
			secondary_rings.append(ring)
	
	# Set timers to emit rings with delays
	for i in range(secondary_rings.size()):
		var timer = Timer.new()
		timer.name = "RingTimer" + str(i)
		timer.wait_time = 0.2 * i
		timer.one_shot = true
		timer.autostart = true
		
		var current_ring = secondary_rings[i]
		timer.timeout.connect(func(): current_ring.emitting = true)
		add_child(timer)

# Setup distortion field effect
func setup_distortion_field():
	distortion_field = get_node_or_null("DistortionField")
	if not distortion_field:
		distortion_field = Sprite2D.new()
		distortion_field.name = "DistortionField"
		
		# In a real implementation, you would load a distortion shader material
		# distortion_field.material = load("res://materials/distortion_material.tres")
		
		distortion_field.scale = Vector2(0, 0)  # Start invisible
		distortion_field.modulate = Color(1, 1, 1, 0.3)
		add_child(distortion_field)
		
		# Create more complex animation sequence
		var tween = create_tween()
		tween.set_parallel(false)
		
		# First wave - quick expansion
		tween.tween_property(distortion_field, "scale", Vector2(emp_radius / 64.0, emp_radius / 64.0), 0.2)
		tween.tween_property(distortion_field, "modulate:a", 0.5, 0.1)
		
		# Second wave - further expansion
		tween.tween_property(distortion_field, "scale", Vector2(emp_radius / 32.0, emp_radius / 32.0), 0.4)
		
		# Pulse effect
		tween.tween_property(distortion_field, "scale", Vector2(emp_radius / 28.0, emp_radius / 28.0), 0.2)
		tween.tween_property(distortion_field, "scale", Vector2(emp_radius / 25.0, emp_radius / 25.0), 0.3)
		
		# Final fade
		tween.tween_property(distortion_field, "modulate:a", 0.0, 0.8)

# Setup energy field (new component)
func setup_energy_field():
	energy_field = get_node_or_null("EnergyField")
	if not energy_field:
		energy_field = Node2D.new()
		energy_field.name = "EnergyField"
		add_child(energy_field)
		
		# Create circular energy field with lines
		var num_lines = 16
		var angle_step = TAU / num_lines
		
		for i in range(num_lines):
			var angle = i * angle_step
			var line = Line2D.new()
			line.width = 2.0
			line.default_color = emp_color.lightened(0.3)
			
			# Width variation along the line
			var width_curve = Curve.new()
			width_curve.add_point(Vector2(0, 0.2))
			width_curve.add_point(Vector2(0.5, 1.0))
			width_curve.add_point(Vector2(1.0, 0.2))
			line.width_curve = width_curve
			
			# Color gradient
			var gradient = Gradient.new()
			gradient.add_point(0.0, emp_color.lightened(0.4))
			gradient.add_point(0.5, emp_secondary_color)
			gradient.add_point(1.0, emp_color.lightened(0.2))
			line.gradient = gradient
			
			# Create points for the line
			var inner_radius = emp_radius * 0.2
			var outer_radius = emp_radius * 0.6
			
			line.add_point(Vector2(cos(angle), sin(angle)) * inner_radius)
			line.add_point(Vector2(cos(angle), sin(angle)) * outer_radius)
			
			energy_field.add_child(line)
			
			# Animate the line
			var timer = Timer.new()
			timer.wait_time = 0.1
			timer.autostart = true
			timer.timeout.connect(func():
				# Pulse the line width
				var current_curve = line.width_curve
				if current_curve and current_curve.get_point_count() >= 3:
					var mid_value = current_curve.get_point_position(1).y
					var new_value = mid_value + randf_range(-0.2, 0.2)
					new_value = clamp(new_value, 0.7, 1.3)
					current_curve.set_point_value(1, new_value)
			)
			line.add_child(timer)

# Setup impact particles (new component)
func setup_impact_particles():
	impact_particles = get_node_or_null("ImpactParticles")
	if not impact_particles:
		impact_particles = GPUParticles2D.new()
		impact_particles.name = "ImpactParticles"
		impact_particles.emitting = false
		impact_particles.one_shot = true
		impact_particles.explosiveness = 1.0
		impact_particles.amount = 100
		impact_particles.lifetime = 1.0
		add_child(impact_particles)
		
		# Setup material
		var material = ParticleProcessMaterial.new()
		material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		material.emission_sphere_radius = emp_radius * 0.1
		material.direction = Vector3(0, 0, 0)
		material.spread = 180.0
		material.gravity = Vector3(0, 0, 0)
		material.initial_velocity_min = 100.0 * emp_intensity
		material.initial_velocity_max = 300.0 * emp_intensity
		
		# Add drag for more realistic physics
		material.damping_min = 50.0
		material.damping_max = 100.0
		
		material.scale_min = 0.1
		material.scale_max = 0.3
		
		# Color over lifetime
		var gradient = Gradient.new()
		gradient.add_point(0.0, Color(1.0, 1.0, 1.0, 1.0))
		gradient.add_point(0.2, Color(emp_color.r + 0.8, emp_color.g + 0.8, emp_color.b + 0.8, 0.9))
		gradient.add_point(0.6, Color(emp_color.r + 0.4, emp_color.g + 0.4, emp_color.b + 0.4, 0.6))
		gradient.add_point(1.0, Color(emp_color.r, emp_color.g, emp_color.b, 0.0))
		
		var gradient_texture = GradientTexture1D.new()
		gradient_texture.gradient = gradient
		material.color_ramp = gradient_texture
		
		impact_particles.process_material = material

# Setup spark emitter
func setup_spark_emitter():
	spark_emitter = get_node_or_null("Spark")
	
	# Spark would be an AnimatedSprite2D in the actual implementation
	# In this case, we'll leave it as is since it comes from your original code

# Setup sounds
func setup_sounds():
	# Main EMP sound
	emp_sound = get_node_or_null("EMPSound")
	if not emp_sound:
		emp_sound = AudioStreamPlayer2D.new()
		emp_sound.name = "EMPSound"
		emp_sound.volume_db = 0.0
		emp_sound.max_distance = 2000
		
		# In an actual implementation, you'd load the sound file
		# emp_sound.stream = load("res://assets/audio/effects/emp.ogg")
		
		add_child(emp_sound)
	
	# Electricity crackling sound
	electricity_sound = get_node_or_null("ElectricitySound")
	if not electricity_sound:
		electricity_sound = AudioStreamPlayer2D.new()
		electricity_sound.name = "ElectricitySound"
		electricity_sound.volume_db = -5.0
		electricity_sound.max_distance = 1500
		
		# In an actual implementation, you'd load the sound file
		# electricity_sound.stream = load("res://assets/audio/effects/electricity.ogg")
		
		add_child(electricity_sound)
		
		# Fade out electricity sound
		var tween = create_tween()
		tween.tween_property(electricity_sound, "volume_db", -40.0, emp_duration)
	
	# Pulse sound (new)
	pulse_sound = get_node_or_null("PulseSound")
	if not pulse_sound:
		pulse_sound = AudioStreamPlayer2D.new()
		pulse_sound.name = "PulseSound"
		pulse_sound.volume_db = -8.0
		pulse_sound.max_distance = 1200
		
		# In an actual implementation, you'd load the sound file
		# pulse_sound.stream = load("res://assets/audio/effects/pulse.ogg")
		
		add_child(pulse_sound)

# Setup lighting effects
func setup_lighting():
	# Main EMP light
	var emp_light = get_node_or_null("EMPLight")
	if not emp_light:
		emp_light = PointLight2D.new()
		emp_light.name = "EMPLight"
		emp_light.color = emp_color
		emp_light.energy = 2.0 * emp_intensity
		emp_light.texture_scale = emp_radius / 50.0
		emp_light.shadow_enabled = true
		emp_light.shadow_filter = 1  # Adds soft shadows
		emp_light.shadow_filter_smooth = 3.0
		add_child(emp_light)
		
		# Setup light animation with pulses
		var tween = create_tween()
		tween.set_loops(2)  # Multiple pulses
		tween.tween_property(emp_light, "energy", 2.5 * emp_intensity, 0.2)
		tween.tween_property(emp_light, "energy", 1.5 * emp_intensity, 0.3)
		tween.tween_property(emp_light, "energy", 2.0 * emp_intensity, 0.2)
		tween.tween_property(emp_light, "energy", 0.8 * emp_intensity, 0.4)
		tween.tween_property(emp_light, "energy", 0.0, 0.4)
	
	# Create flickering arc lights
	var arc_light = get_node_or_null("ArcLight")
	if not arc_light:
		arc_light = PointLight2D.new()
		arc_light.name = "ArcLight"
		arc_light.color = emp_color.lightened(0.5)
		arc_light.energy = 1.0 * emp_intensity
		arc_light.texture_scale = emp_radius / 100.0
		arc_light.position = Vector2(randf_range(-emp_radius * 0.2, emp_radius * 0.2), 
									 randf_range(-emp_radius * 0.2, emp_radius * 0.2))
		add_child(arc_light)
		
		# Flicker timer
		var flicker_timer = Timer.new()
		flicker_timer.name = "FlickerTimer"
		flicker_timer.wait_time = 0.05
		flicker_timer.autostart = true
		flicker_timer.timeout.connect(func():
			arc_light.energy = randf_range(0.5, 1.5) * emp_intensity
			arc_light.position = Vector2(randf_range(-emp_radius * 0.2, emp_radius * 0.2), 
										randf_range(-emp_radius * 0.2, emp_radius * 0.2))
		)
		arc_light.add_child(flicker_timer)
	
	# Add secondary flickering lights for more dramatic effect
	var secondary_light = get_node_or_null("SecondaryLight")
	if not secondary_light:
		secondary_light = PointLight2D.new()
		secondary_light.name = "SecondaryLight"
		secondary_light.color = emp_secondary_color
		secondary_light.energy = 0.7 * emp_intensity
		secondary_light.texture_scale = emp_radius / 70.0
		add_child(secondary_light)
		
		# Flicker timer with different pattern
		var flicker_timer = Timer.new()
		flicker_timer.name = "FlickerTimer"
		flicker_timer.wait_time = 0.07
		flicker_timer.autostart = true
		flicker_timer.timeout.connect(func():
			secondary_light.energy = randf_range(0.3, 0.9) * emp_intensity
			secondary_light.position = Vector2(randf_range(-emp_radius * 0.3, emp_radius * 0.3), 
										randf_range(-emp_radius * 0.3, emp_radius * 0.3))
			
			# Occasionally change color slightly
			if randf() < 0.3:
				var hue_shift = randf_range(-0.05, 0.05)
				secondary_light.color = emp_secondary_color
				secondary_light.color.h += hue_shift
		)
		secondary_light.add_child(flicker_timer)

# Set EMP properties from outside
func set_emp_properties(radius: float, intensity: float = 1.0, duration: float = DEFAULT_DURATION, color: Color = Color(0.2, 0.4, 1.0, 1.0)):
	emp_radius = radius
	emp_intensity = intensity
	emp_duration = duration
	emp_color = color
	
	# Calculate secondary color
	emp_secondary_color = Color(
		clamp(color.r + 0.3, 0, 1),
		clamp(color.g + 0.3, 0, 1),
		clamp(color.b + 0.3, 0, 1),
		0.7
	)
	
	# Update lifetime timer if present
	if has_node("LifetimeTimer"):
		$LifetimeTimer.wait_time = emp_duration
		$LifetimeTimer.start()
	
	# If material exists, update properties
	if process_material:
		process_material.emission_sphere_radius = emp_radius * 0.1
		process_material.initial_velocity_min = 50.0 * emp_intensity
		process_material.initial_velocity_max = 150.0 * emp_intensity
		
		# Update color ramp if possible
		if process_material.color_ramp and process_material.color_ramp.gradient:
			var gradient = process_material.color_ramp.gradient
			if gradient.get_point_count() >= 4:
				gradient.set_color(0, emp_color)
				gradient.set_color(1, Color(emp_color.r + 0.2, emp_color.g + 0.2, emp_color.b, 0.8))
				gradient.set_color(2, Color(emp_color.r, emp_color.g + 0.2, emp_color.b, 0.5))
				gradient.set_color(3, Color(emp_color.r - 0.1, emp_color.g - 0.1, emp_color.b, 0.0))
	
	# Update light if present
	if has_node("EMPLight"):
		$EMPLight.color = emp_color
		$EMPLight.energy = 2.0 * emp_intensity
		$EMPLight.texture_scale = emp_radius / 50.0
		
		# Update light animation
		var tween = create_tween()
		tween.set_loops(2)  # Multiple pulses
		tween.tween_property($EMPLight, "energy", 2.5 * emp_intensity, 0.2)
		tween.tween_property($EMPLight, "energy", 1.5 * emp_intensity, 0.3)
		tween.tween_property($EMPLight, "energy", 2.0 * emp_intensity, 0.2)
		tween.tween_property($EMPLight, "energy", 0.8 * emp_intensity, 0.4)
		tween.tween_property($EMPLight, "energy", 0.0, 0.4)
	
	# Update amount based on radius and intensity
	amount = int(DEFAULT_AMOUNT * (radius / DEFAULT_RADIUS) * sqrt(intensity))
	amount = clamp(amount, 50, 400)  # Increased max
	
	# Update children
	update_child_components()
	
	# Regenerate arc points for new size
	generate_arc_points()

# Update child component properties
func update_child_components():
	# Update core ring
	if core_ring and core_ring.process_material:
		# Update scale based on radius
		if core_ring.process_material.scale_curve and core_ring.process_material.scale_curve.curve:
			var curve = core_ring.process_material.scale_curve.curve
			var max_scale = emp_radius / 50.0
			for i in range(curve.get_point_count()):
				var point = curve.get_point_position(i)
				curve.set_point_value(i, point.y * max_scale)
		
		# Update color
		if core_ring.process_material.color_ramp and core_ring.process_material.color_ramp.gradient:
			var gradient = core_ring.process_material.color_ramp.gradient
			if gradient.get_point_count() >= 4:
				gradient.set_color(1, Color(emp_color.r, emp_color.g, emp_color.b, 1.0))
				gradient.set_color(2, Color(emp_color.r, emp_color.g, emp_color.b, 0.7))
				gradient.set_color(3, Color(emp_color.r, emp_color.g, emp_color.b, 0.0))
	
	# Update pulse wave
	if pulse_wave and pulse_wave.process_material:
		pulse_wave.process_material.initial_velocity_min = 200.0 * emp_intensity
		pulse_wave.process_material.initial_velocity_max = 500.0 * emp_intensity
		
		# Update color
		if pulse_wave.process_material.color_ramp and pulse_wave.process_material.color_ramp.gradient:
			var gradient = pulse_wave.process_material.color_ramp.gradient
			if gradient.get_point_count() >= 4:
				gradient.set_color(0, Color(emp_color.r + 0.7, emp_color.g + 0.7, emp_color.b + 0.5, 0.9))
				gradient.set_color(1, Color(emp_color.r, emp_color.g, emp_color.b, 0.7))
				gradient.set_color(2, Color(emp_color.r, emp_color.g, emp_color.b, 0.3))
				gradient.set_color(3, Color(emp_color.r, emp_color.g, emp_color.b, 0.0))
	
	# Update sparkles
	if sparkles and sparkles.process_material:
		sparkles.process_material.emission_sphere_radius = emp_radius * 0.5
		
		# Update color
		if sparkles.process_material.color_ramp and sparkles.process_material.color_ramp.gradient:
			var gradient = sparkles.process_material.color_ramp.gradient
			if gradient.get_point_count() >= 4:
				gradient.set_color(1, Color(emp_color.r + 0.5, emp_color.g + 0.5, emp_color.b + 0.5, 0.9))
				gradient.set_color(2, Color(emp_color.r, emp_color.g, emp_color.b, 0.6))
				gradient.set_color(3, Color(emp_color.r, emp_color.g, emp_color.b, 0.0))
	
	# Update secondary rings
	for i in range(secondary_rings.size()):
		var ring = secondary_rings[i]
		if ring and ring.process_material and ring.process_material.color_ramp and ring.process_material.color_ramp.gradient:
			var gradient = ring.process_material.color_ramp.gradient
			
			# Alternate colors for more variety
			if i % 2 == 0:
				if gradient.get_point_count() >= 3:
					gradient.set_color(0, Color(emp_secondary_color.r, emp_secondary_color.g, emp_secondary_color.b, 0.7))
					gradient.set_color(1, Color(emp_secondary_color.r, emp_secondary_color.g, emp_secondary_color.b, 0.4))
					gradient.set_color(2, Color(emp_secondary_color.r, emp_secondary_color.g, emp_secondary_color.b, 0.0))
			else:
				if gradient.get_point_count() >= 3:
					gradient.set_color(0, Color(emp_color.r, emp_color.g, emp_color.b, 0.6))
					gradient.set_color(1, Color(emp_secondary_color.r, emp_secondary_color.g, emp_secondary_color.b, 0.4))
					gradient.set_color(2, Color(emp_color.r + 0.2, emp_color.g + 0.2, emp_color.b + 0.2, 0.0))
	
	# Update distortion field
	if distortion_field:
		var tween = create_tween()
		tween.set_parallel(false)
		
		# First wave - quick expansion
		tween.tween_property(distortion_field, "scale", Vector2(emp_radius / 64.0, emp_radius / 64.0), 0.2)
		tween.tween_property(distortion_field, "modulate:a", 0.5, 0.1)
		
		# Second wave - further expansion
		tween.tween_property(distortion_field, "scale", Vector2(emp_radius / 32.0, emp_radius / 32.0), 0.4)
		
		# Pulse effect
		tween.tween_property(distortion_field, "scale", Vector2(emp_radius / 28.0, emp_radius / 28.0), 0.2)
		tween.tween_property(distortion_field, "scale", Vector2(emp_radius / 25.0, emp_radius / 25.0), 0.3)
		
		# Final fade
		tween.tween_property(distortion_field, "modulate:a", 0.0, 0.8)
	
	# Update energy field
	if energy_field:
		for child in energy_field.get_children():
			if child is Line2D:
				# Update color
				if child.gradient:
					var gradient = child.gradient
					if gradient.get_point_count() >= 3:
						gradient.set_color(0, emp_color.lightened(0.4))
						gradient.set_color(1, emp_secondary_color)
						gradient.set_color(2, emp_color.lightened(0.2))
				
				# Update position
				var point_count = child.get_point_count()
				if point_count >= 2:
					var direction = child.get_point_position(1) - child.get_point_position(0)
					direction = direction.normalized()
					
					var inner_radius = emp_radius * 0.2
					var outer_radius = emp_radius * 0.6
					
					child.set_point_position(0, direction * inner_radius)
					child.set_point_position(1, direction * outer_radius)
	
	# Update impact particles
	if impact_particles and impact_particles.process_material:
		impact_particles.process_material.emission_sphere_radius = emp_radius * 0.1
		impact_particles.process_material.initial_velocity_min = 100.0 * emp_intensity
		impact_particles.process_material.initial_velocity_max = 300.0 * emp_intensity
		
		# Update color
		if impact_particles.process_material.color_ramp and impact_particles.process_material.color_ramp.gradient:
			var gradient = impact_particles.process_material.color_ramp.gradient
			if gradient.get_point_count() >= 4:
				gradient.set_color(1, Color(emp_color.r + 0.8, emp_color.g + 0.8, emp_color.b + 0.8, 0.9))
				gradient.set_color(2, Color(emp_color.r + 0.4, emp_color.g + 0.4, emp_color.b + 0.4, 0.6))
				gradient.set_color(3, Color(emp_color.r, emp_color.g, emp_color.b, 0.0))

# Start emitting all particle systems
func start_emitting():
	emitting = true
	
	# Start impact particles
	if impact_particles:
		impact_particles.emitting = true
	
	# Start core ring
	if core_ring:
		core_ring.emitting = true
	
	# Start pulse wave
	if pulse_wave:
		pulse_wave.emitting = true
	
	# Start sparkles
	if sparkles:
		sparkles.emitting = true
	
	# Play sounds
	if emp_sound:
		emp_sound.play()
	
	if electricity_sound:
		electricity_sound.play()
	
	if pulse_sound:
		pulse_sound.play()
	
	# Create screen shake effect
	create_screen_shake(0.4 * emp_intensity)  # Increased intensity
	
	# Trigger pulse effect
	trigger_pulse_effect()

# Handle lifetime timer timeout - fade out and clean up
func _on_lifetime_timer_timeout():
	# Fade out effect with more complex animation
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Fade out main particles
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	
	# Special fade for arcs
	if electric_arcs:
		for arc in electric_arcs.get_children():
			if arc is Line2D:
				var arc_tween = create_tween()
				arc_tween.tween_property(arc, "default_color:a", 0.0, randf_range(0.2, 0.4))
	
	# Fade out energy field with delay
	if energy_field:
		var energy_tween = create_tween()
		energy_tween.tween_interval(0.1)
		energy_tween.tween_property(energy_field, "modulate:a", 0.0, 0.3)
	
	# Final explosive flash before disappearing
	if sparkles:
		sparkles.emitting = true
		var sparkle_tween = create_tween()
		sparkle_tween.tween_interval(0.2)
		sparkle_tween.tween_property(sparkles, "modulate:a", 0.0, 0.3)
	
	# Queue free after fade out
	tween.tween_callback(queue_free).set_delay(0.5)

# Create periodic pulse effect
func _on_pulse_timer_timeout():
	trigger_pulse_effect()

# Trigger a pulse effect
func trigger_pulse_effect():
	# Create a mini pulse wave
	var mini_pulse = pulse_wave.duplicate()
	mini_pulse.lifetime = 0.5
	mini_pulse.amount = 1
	
	if mini_pulse.process_material:
		mini_pulse.process_material.initial_velocity_min = 100.0 * emp_intensity
		mini_pulse.process_material.initial_velocity_max = 300.0 * emp_intensity
	
	add_child(mini_pulse)
	mini_pulse.emitting = true
	
	# Auto cleanup
	var timer = Timer.new()
	timer.wait_time = 1.0
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(func(): mini_pulse.queue_free())
	mini_pulse.add_child(timer)
	
	# Create mini sparkle burst
	if sparkles:
		var mini_sparkle = sparkles.duplicate()
		mini_sparkle.amount = 20
		mini_sparkle.lifetime = 0.3
		add_child(mini_sparkle)
		mini_sparkle.emitting = true
		
		var sparkle_timer = Timer.new()
		sparkle_timer.wait_time = 0.5
		sparkle_timer.one_shot = true
		sparkle_timer.autostart = true
		sparkle_timer.timeout.connect(func(): mini_sparkle.queue_free())
		mini_sparkle.add_child(sparkle_timer)
	
	# Play pulse sound if available
	if pulse_sound:
		pulse_sound.pitch_scale = randf_range(0.9, 1.1)  # Small pitch variation
		pulse_sound.play()
	
	# Find and affect random electronics
	affect_random_electronics()

# Affect random electronics in the scene
func affect_random_electronics():
	# Find all electronics in the scene
	var electronics = get_tree().get_nodes_in_group("electronics")
	
	# If no electronics group, try objects group
	if electronics.size() == 0:
		electronics = get_tree().get_nodes_in_group("objects")
	
	# Filter to only those in range
	var in_range_electronics = []
	for electronic in electronics:
		if electronic is Node2D:
			var distance = global_position.distance_to(electronic.global_position)
			if distance <= emp_radius:
				in_range_electronics.append(electronic)
	
	# Randomly affect some electronics
	var num_to_affect = min(4, in_range_electronics.size())  # Increased from 3
	for i in range(num_to_affect):
		if in_range_electronics.size() > 0:
			var idx = randi() % in_range_electronics.size()
			var target = in_range_electronics[idx]
			in_range_electronics.remove_at(idx)
			
			# Create arc to electronic
			create_arc_to_target(target)
			
			# Apply EMP effect
			if target.has_method("emp_act"):
				target.emp_act(1)  # Highest severity
			elif target.has_method("emp_effect"):
				target.emp_effect()
			
			# Add to active electronics list
			active_electronics.append({"target": target, "time": randf_range(1.0, 3.0)})

# Create arc to specific target with more dramatic effect
func create_arc_to_target(target: Node2D):
	if not is_instance_valid(target):
		return
		
	var direction = (target.global_position - global_position).normalized()
	var distance = global_position.distance_to(target.global_position)
	
	var arc = Line2D.new()
	arc.width = 3.0
	arc.width_curve = create_arc_width_curve()  # Add tapering
	arc.default_color = emp_color.lightened(0.7)
	arc.begin_cap_mode = Line2D.LINE_CAP_ROUND
	arc.end_cap_mode = Line2D.LINE_CAP_ROUND
	
	# Add gradient for more visual impact
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1.0, 1.0, 1.0, 0.9))  # Start white
	gradient.add_point(0.3, emp_color.lightened(0.8))
	gradient.add_point(0.7, emp_color.lightened(0.5))
	gradient.add_point(1.0, emp_color.lightened(0.3))
	arc.gradient = gradient
	
	arc.add_point(Vector2.ZERO)  # Center of EMP
	
	# Add zigzag points for lightning effect
	var segment_count = int(distance / 12.0)  # More segments for higher detail
	var target_local = to_local(target.global_position)
	
	for i in range(segment_count):
		var progress = float(i) / segment_count
		var segment_point = target_local * progress
		
		# Increase zigzag in the middle
		var perpendicular_scale = sin(progress * PI)  # Peak in the middle, min at ends
		var perpendicular = Vector2(-direction.y, direction.x) * randf_range(-15, 15) * perpendicular_scale
		arc.add_point(segment_point + perpendicular)
		
		# Occasionally add small branches
		if randf() < 0.15:  # 15% chance per segment
			create_branch(arc, segment_point + perpendicular, randf_range(8, 20))
	
	arc.add_point(target_local)
	
	# Add to arcs container
	electric_arcs.add_child(arc)
	
	# Create impact flash at target
	var flash = Sprite2D.new()
	flash.position = target_local
	flash.scale = Vector2(0.5, 0.5)
	flash.modulate = emp_color.lightened(0.7)
	add_child(flash)
	
	# Create additional impact particles at target
	var impact = GPUParticles2D.new()
	impact.position = target_local
	impact.amount = 20
	impact.lifetime = 0.5
	impact.explosiveness = 1.0
	impact.one_shot = true
	
	var impact_material = ParticleProcessMaterial.new()
	impact_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	impact_material.emission_sphere_radius = 5.0
	impact_material.direction = Vector3(0, 0, 0)
	impact_material.spread = 180.0
	impact_material.gravity = Vector3(0, 0, 0)
	impact_material.initial_velocity_min = 20.0
	impact_material.initial_velocity_max = 60.0
	impact_material.scale_min = 0.1
	impact_material.scale_max = 0.3
	
	var impact_gradient = Gradient.new()
	impact_gradient.add_point(0.0, Color(1.0, 1.0, 1.0, 1.0))
	impact_gradient.add_point(0.3, emp_color.lightened(0.8))
	impact_gradient.add_point(0.7, emp_color.lightened(0.3))
	impact_gradient.add_point(1.0, emp_color.lightened(0.1))
	
	var impact_ramp = GradientTexture1D.new()
	impact_ramp.gradient = impact_gradient
	impact_material.color_ramp = impact_ramp
	
	impact.process_material = impact_material
	impact.emitting = true
	add_child(impact)
	
	# Animate flash
	var tween = create_tween()
	tween.tween_property(flash, "scale", Vector2(1.5, 1.5), 0.1)
	tween.tween_property(flash, "modulate:a", 0.0, 0.2)
	tween.tween_callback(flash.queue_free)
	
	# Set up auto-destruction for arc
	var timer = Timer.new()
	timer.wait_time = 0.3
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(func(): arc.queue_free())
	arc.add_child(timer)
	
	# Set up auto-destruction for impact particles
	var impact_timer = Timer.new()
	impact_timer.wait_time = 0.7
	impact_timer.one_shot = true
	impact_timer.autostart = true
	impact_timer.timeout.connect(func(): impact.queue_free())
	impact.add_child(impact_timer)
	
	return arc

# Update electronics affected by EMP
func update_affected_electronics(delta: float):
	var i = 0
	while i < active_electronics.size():
		var electronic = active_electronics[i]
		electronic.time -= delta
		
		if electronic.time <= 0 or not is_instance_valid(electronic.target):
			active_electronics.remove_at(i)
		else:
			# Randomly create arcs to active electronics
			if randf() < 0.15:  # 15% chance per frame (increased from 10%)
				create_arc_to_target(electronic.target)
			i += 1

# Create a screen shake effect
func create_screen_shake(intensity: float = 1.0):
	var camera = get_viewport().get_camera_2d()
	if camera and camera.has_method("add_trauma"):
		camera.add_trauma(intensity)
	else:
		# Try to find a camera shake manager in the scene
		var camera_shake = get_node_or_null("/root/CameraShake")
		if camera_shake and camera_shake.has_method("add_trauma"):
			camera_shake.add_trauma(intensity)
