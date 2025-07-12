@tool
extends Node2D

enum Direction {
	NORTH,
	SOUTH,
	WEST,
	EAST
}

@export var facing_direction = Direction.NORTH:
	set(value):
		facing_direction = value
		_set_sprite_animation()

@export var is_active: bool = true:
	set(value):
		is_active = value
		_update_light_state()

@export var light_color: Color = Color(1, 1, 0.8, 1):
	set(value):
		light_color = value
		_update_light_color()

@export var light_energy: float = 1.0:
	set(value):
		light_energy = value
		_update_light_energy()

@export var light_range: float = 256.0:
	set(value):
		light_range = value
		_update_light_range()

@onready var on_sprite = $On
@onready var off_sprite = $Off
@onready var light_2d = $PointLight2D

func _ready() -> void:
	_set_sprite_animation()
	_update_light_state()
	_update_light_color()
	_update_light_energy()
	_update_light_range()

func _set_sprite_animation():
	if not on_sprite or not off_sprite:
		return
		
	var dir := ""
	match facing_direction:
		Direction.NORTH:
			dir = "North"
		Direction.SOUTH:
			dir = "South"
		Direction.EAST:
			dir = "East"
		Direction.WEST:
			dir = "West"
	
	# Check if animation exists
	if on_sprite.sprite_frames.has_animation(dir):
		on_sprite.animation = dir
	else:
		# Create a default animation if it doesn't exist
		_create_default_sprites()
		
	if off_sprite.sprite_frames.has_animation(dir):
		off_sprite.animation = dir
	
	# Update visibility
	on_sprite.visible = is_active
	off_sprite.visible = not is_active

func _create_default_sprites():
	# If no sprite frames provided, create simple placeholder frames
	# This is particularly useful in the editor
	
	# Create sprite frames if not already set
	if not on_sprite.sprite_frames:
		on_sprite.sprite_frames = SpriteFrames.new()
	
	if not off_sprite.sprite_frames:
		off_sprite.sprite_frames = SpriteFrames.new()
	
	# Add animations if they don't exist
	for dir in ["North", "South", "East", "West"]:
		if not on_sprite.sprite_frames.has_animation(dir):
			on_sprite.sprite_frames.add_animation(dir)
			on_sprite.sprite_frames.set_animation_speed(dir, 5)
			
		if not off_sprite.sprite_frames.has_animation(dir):
			off_sprite.sprite_frames.add_animation(dir)
			off_sprite.sprite_frames.set_animation_speed(dir, 5)

func _update_light_state():
	if not light_2d:
		return
		
	light_2d.visible = is_active
	
	if on_sprite and off_sprite:
		on_sprite.visible = is_active
		off_sprite.visible = not is_active

func _update_light_color():
	if not light_2d:
		return
		
	light_2d.color = light_color

func _update_light_energy():
	if not light_2d:
		return
		
	light_2d.energy = light_energy

func _update_light_range():
	if not light_2d:
		return
		
	light_2d.texture_scale = light_range / 256.0  # Assuming a 256x256 light texture

func turn_on() -> void:
	is_active = true
	_update_light_state()

func turn_off() -> void:
	is_active = false
	_update_light_state()

func toggle() -> void:
	is_active = !is_active
	_update_light_state()
