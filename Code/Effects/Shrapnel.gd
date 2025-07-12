extends Node2D

var velocity = Vector2.ZERO
var damage = 15
var penetration = 20
var max_range = 112  # Default range in pixels
var travel_distance = 0
var projectile_name = "shrapnel"
var has_trail = true
var trail_length = 10
var trail_points = []

# Physical properties
var mass = 0.01
var drag_coefficient = 0.05
var gravity_scale = 0.3

func _ready():
	# Set up the trail renderer
	if has_trail:
		for i in range(trail_length):
			trail_points.append(global_position)
	
	# Set up the collision detection
	$Area2D/CollisionShape2D.disabled = false
	
	# Play the sound
	if has_node("ShrapnelSound"):
		$ShrapnelSound.pitch_scale = randf_range(0.9, 1.1)
		$ShrapnelSound.play()
	
	# Start with a random rotation
	rotation = randf_range(0, TAU)

func _process(delta):
	# Apply gravity and drag physics
	var gravity = Vector2(0, 980 * gravity_scale * delta)
	var drag = -velocity.normalized() * velocity.length_squared() * drag_coefficient * delta
	
	velocity += gravity + drag
	
	# Move based on velocity
	var movement = velocity * delta
	global_position += movement
	
	# Update travel distance
	travel_distance += movement.length()
	
	# Rotate sprite based on velocity
	rotation = velocity.angle() + PI/2
	
	# Update trail if it exists
	if has_trail and trail_points.size() > 0:
		trail_points.pop_back()
		trail_points.push_front(global_position)
		$Trail.points = trail_points
	
	# Check if we've gone too far
	if travel_distance > max_range:
		queue_free()

func _draw():
	# Draw the trail manually if needed
	if has_trail and not has_node("Trail") and trail_points.size() > 1:
		var points = PackedVector2Array(trail_points)
		draw_polyline(points, Color(1, 0.5, 0.2, 0.7), 2.0, true)

func _on_area_2d_body_entered(body):
	# Handle collision with environment
	if body.is_in_group("world"):
		spawn_impact_effect()
		queue_free()
	
	# Handle collision with entities
	if body.is_in_group("entities") and body.has_method("take_damage"):
		body.take_damage(damage, "brute", "shrapnel")
		
		# Chance to penetrate based on penetration value
		var penetration_chance = penetration / 100.0
		if randf() > penetration_chance:
			spawn_impact_effect()
			queue_free()

func spawn_impact_effect():
	# Spawn a small spark/impact effect
	var impact = preload("res://Scenes/Effects/Spark.tscn").instantiate()
	if impact:
		impact.global_position = global_position
		impact.global_rotation = global_rotation
		get_tree().get_root().add_child(impact)
