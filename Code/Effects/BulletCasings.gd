extends Node2D
class_name BulletCasing

# Simple properties
@export var despawn_time: float = 5.0  # Time before casing despawns
@export var fade_duration: float = 1.0  # How long the fade takes

# Audio
@export var eject_sound: AudioStream

# Components
var icon: AnimatedSprite2D

func _ready():
	# Get the Icon node (AnimatedSprite2D)
	icon = get_node_or_null("Icon")
	if not icon:
		# Create one if it doesn't exist
		icon = AnimatedSprite2D.new()
		icon.name = "Icon"
		add_child(icon)
	
	# Load default eject sound
	if not eject_sound and ResourceLoader.exists("res://Sound/weapons/bulletcasing_fall.ogg"):
		eject_sound = preload("res://Sound/weapons/bulletcasing_fall.ogg")

func eject_with_animation(direction: Vector2, _force: float = 0.0):
	"""Play casing eject animation"""
	
	# Play eject sound
	if eject_sound:
		play_audio_at_position(eject_sound, global_position, 0.3)
	
	# Rotate icon to face eject direction
	if icon:
		icon.rotation = direction.angle()
		
		# Play the Casing animation if it exists
		if icon.sprite_frames and icon.sprite_frames.has_animation("Casing"):
			icon.play("Casing")
			
			# Wait for animation to complete, then start fade
			if icon.sprite_frames.get_frame_count("Casing") > 0:
				var frame_count = icon.sprite_frames.get_frame_count("Casing")
				var fps = icon.sprite_frames.get_animation_speed("Casing")
				var animation_duration = frame_count / fps
				
				# Wait for animation, then fade
				await get_tree().create_timer(animation_duration).timeout
			
			start_fade_out()
		else:
			# No animation found, just fade immediately
			push_warning("BulletCasing: 'Casing' animation not found in Icon node")
			start_fade_out()
	else:
		# No icon node, just despawn after delay
		await get_tree().create_timer(despawn_time).timeout
		queue_free()

func start_fade_out():
	"""Start the fade out effect"""
	if not icon:
		queue_free()
		return
	
	# Create fade tween
	var tween = create_tween()
	tween.tween_property(icon, "modulate", Color(1, 1, 1, 0), fade_duration)
	tween.tween_callback(func(): queue_free())

func play_audio_at_position(sound: AudioStream, pos: Vector2, volume: float = 1.0):
	"""Play audio at a specific position"""
	# Try to use global audio manager first
	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_positioned_sound"):
		audio_manager.play_positioned_sound(sound, pos, volume)
		return
	
	# Fallback to local AudioStreamPlayer2D
	var audio_player = AudioStreamPlayer2D.new()
	audio_player.stream = sound
	audio_player.volume_db = linear_to_db(volume)
	audio_player.max_distance = 150.0  # Limit audio range
	audio_player.attenuation = 2.0     # Realistic falloff
	
	get_tree().current_scene.add_child(audio_player)
	audio_player.global_position = pos
	audio_player.play()
	
	# Remove audio player after sound finishes
	audio_player.finished.connect(func(): audio_player.queue_free())

# Factory methods for different casing types
static func create_pistol_casing() -> BulletCasing:
	"""Create a pistol casing"""
	var casing = BulletCasing.new()
	casing.despawn_time = 4.0
	casing.fade_duration = 0.8
	return casing

static func create_rifle_casing() -> BulletCasing:
	"""Create a rifle casing"""
	var casing = BulletCasing.new()
	casing.despawn_time = 5.0
	casing.fade_duration = 1.0
	return casing

static func create_shotgun_casing() -> BulletCasing:
	"""Create a shotgun shell casing"""
	var casing = BulletCasing.new()
	casing.despawn_time = 6.0
	casing.fade_duration = 1.2
	return casing

# Network synchronization for multiplayer
@rpc("any_peer", "call_local", "reliable")
func sync_casing_eject(position: Vector2, direction: Vector2, force: float):
	"""Synchronize casing ejection across network"""
	global_position = position
	eject_with_animation(direction, force)
