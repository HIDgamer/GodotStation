extends Item
class_name Grenade

# Grenade types enum
enum GrenadeType {
	EXPLOSIVE,
	INCENDIARY,
	SMOKE,
	FLASHBANG,
	PHOSPHORUS,
	EMP,
	CHEMICAL,
	FLARE
}

# Core grenade properties
var grenade_type: int = GrenadeType.EXPLOSIVE
var det_time: float = 5.0  # Time until detonation in seconds
var active: bool = false    # Whether the grenade is active/armed
var launched: bool = false  # Whether it was launched from a grenade launcher
var dangerous: bool = true  # Whether the grenade is harmful

# Effect ranges
@export var explosion_range: int = 3    # Range of explosion in tiles
@export var shrapnel_range: int = 4     # Range of shrapnel in tiles
@export var flash_range: int = 0        # Range of flash effect in tiles
@export var smoke_radius: int = 3       # Radius of smoke in tiles
@export var smoke_duration: float = 9.0 # Duration of smoke in seconds

# Audio system
var arm_sound = null           # Sound when armed
var explosion_sound = null     # Sound when detonated
var _audio_player: AudioStreamPlayer2D

# Animation system
@onready var icon: AnimatedSprite2D = $Icon
var animation_states = {
	"armed": "Pin",
	"primed": "Primed"
}

# Timer system
var detonation_timer: Timer = null

# Performance caching
var _cached_entities: Array = []
var _cache_timer: float = 0.0
var _cache_interval: float = 0.3  # Update entity cache every 300ms

# Resource caching
static var sound_cache: Dictionary = {}

# Signals
signal primed(user)
signal detonated(position)

func _init():
	super._init()
	entity_type = "grenade"
	obj_name = "grenade"
	obj_desc = "A hand grenade. Pull pin, throw, and count to 5."
	
	# Set grenade-specific properties
	force = 5
	w_class = 2
	throwforce = 10
	attack_verb = ["strikes", "hits", "bashes"]
	
	# Set slot flags for where this can be equipped
	equip_slot_flags = Slots.LEFT_HAND | Slots.RIGHT_HAND | Slots.BELT | Slots.POCKET
	
	# Add to appropriate groups
	add_to_group("grenade")

func _ready():
	super._ready()
	
	# Set up collision shape
	setup_collision()
	
	# Initialize audio system
	setup_audio_system()
	
	# Set initial animation state
	if icon:
		set_animation_state("armed")

func _process(delta: float):
	# Update entity cache periodically for better performance
	_cache_timer += delta
	if _cache_timer >= _cache_interval:
		update_entity_cache()
		_cache_timer = 0.0

func setup_collision():
	"""Set up collision shape for the grenade"""
	if not has_node("CollisionShape2D"):
		var collision = CollisionShape2D.new()
		var shape = CircleShape2D.new()
		shape.radius = 8
		collision.shape = shape
		add_child(collision)

func setup_audio_system():
	"""Initialize reusable audio player"""
	if not _audio_player:
		_audio_player = AudioStreamPlayer2D.new()
		_audio_player.max_distance = 800
		add_child(_audio_player)

func update_entity_cache():
	"""Cache nearby entities for performance during explosions"""
	_cached_entities.clear()
	
	var entities = get_tree().get_nodes_in_group("entities")
	var players = get_tree().get_nodes_in_group("players")
	
	# Combine and filter valid entities
	for entity in entities + players:
		if is_instance_valid(entity) and entity.has_method("global_position"):
			_cached_entities.append(entity)

func set_animation_state(state: String):
	"""Set animation based on grenade state"""
	if not icon:
		return
	
	var anim_name = animation_states.get(state, "Pin")
	if icon.animation != anim_name:
		icon.play(anim_name)

func activate(user = null) -> bool:
	"""Activate the grenade by pulling the pin"""
	if active:
		return false
	
	# Set active state
	active = true
	
	# Log activation
	if user and "client" in user and user.client:
		print("Grenade activated by: ", user.name)
	
	# Play activation sound
	play_cached_sound(arm_sound)
	
	# Update visual state
	set_animation_state("primed")
	update_appearance()
	
	# Start detonation countdown
	start_detonation_timer()
	
	# Emit signal
	emit_signal("primed", user)
	
	return true

func start_detonation_timer():
	"""Start the countdown timer for detonation"""
	if det_time > 0:
		if detonation_timer:
			detonation_timer.queue_free()
		
		detonation_timer = Timer.new()
		detonation_timer.wait_time = det_time
		detonation_timer.one_shot = true
		detonation_timer.autostart = true
		detonation_timer.timeout.connect(prime)
		add_child(detonation_timer)
	else:
		# Detonate immediately if det_time is 0
		call_deferred("prime")

func prime() -> void:
	"""Called when timer expires - triggers explosion"""
	if not active:
		return
	
	explode()

func explode() -> void:
	"""Handle the grenade explosion"""
	if not active:
		return
	
	# Set inactive state
	active = false
	
	# Play explosion audio
	play_cached_sound(explosion_sound)
	
	# Emit detonation signal
	emit_signal("detonated", global_position)
	
	# Apply basic explosion effects
	apply_base_effects()
	
	# Remove the grenade
	queue_free()

func apply_base_effects():
	"""Apply basic explosion effects to nearby entities"""
	if explosion_range <= 0:
		return
	
	var tile_size = 32
	var max_distance = explosion_range * tile_size
	
	for entity in _cached_entities:
		if not is_instance_valid(entity):
			continue
		
		var distance = global_position.distance_to(entity.global_position)
		if distance <= max_distance:
			var damage_factor = 1.0 - (distance / max_distance)
			var damage = 20.0 * damage_factor  # Base explosion damage
			
			apply_damage_to_entity(entity, damage)

func apply_damage_to_entity(entity: Node, damage: float, damage_type: String = "explosive"):
	"""Apply damage to an entity using available methods"""
	if entity.has_method("apply_damage"):
		entity.apply_damage(damage, damage_type)
	elif entity.has_method("take_damage"):
		entity.take_damage(damage, damage_type)
	elif entity.has_method("damage"):
		entity.damage(damage)

func get_entities_in_radius(center: Vector2, radius: float) -> Array:
	"""Get all valid entities within the specified radius"""
	var result: Array = []
	var radius_squared = radius * radius  # Avoid sqrt calculations
	
	for entity in _cached_entities:
		if not is_instance_valid(entity):
			continue
		
		var distance_squared = center.distance_squared_to(entity.global_position)
		if distance_squared <= radius_squared:
			result.append(entity)
	
	return result

func has_line_of_sight(from_pos: Vector2, to_pos: Vector2) -> bool:
	"""Check if there's a clear line of sight between two positions"""
	var space_state = get_world_2d().direct_space_state
	if not space_state:
		return true
	
	var query = PhysicsRayQueryParameters2D.create(from_pos, to_pos)
	query.collision_mask = 1  # Check walls only
	query.collide_with_bodies = true
	query.collide_with_areas = false
	
	var result = space_state.intersect_ray(query)
	return result.is_empty()

func play_cached_sound(stream: AudioStream, volume_db: float = 0.0):
	"""Play audio using cached player for better performance"""
	if not stream or not _audio_player:
		return
	
	_audio_player.stream = stream
	_audio_player.volume_db = volume_db
	_audio_player.global_position = global_position
	_audio_player.play()

func create_camera_shake(intensity: float = 1.0):
	"""Create camera shake effect based on distance to player"""
	var camera = get_viewport().get_camera_2d()
	if not camera or not camera.has_method("add_trauma"):
		return
	
	var player = get_tree().get_first_node_in_group("player_controller")
	if player:
		var distance = global_position.distance_to(player.global_position)
		var distance_factor = clamp(1.0 - (distance / 320.0), 0.1, 1.0)  # 10 tiles range
		camera.add_trauma(intensity * distance_factor)
	else:
		camera.add_trauma(intensity * 0.5)

func create_cleanup_timer(node: Node, duration: float):
	"""Create a timer to automatically clean up temporary nodes"""
	var timer = Timer.new()
	timer.wait_time = duration
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(func(): if is_instance_valid(node): node.queue_free())
	node.add_child(timer)

func attack_self(user) -> bool:
	"""Allow activation by using the grenade"""
	if not active:
		return activate(user)
	return false

func use(user):
	"""Use method calls attack_self"""
	return attack_self(user)

func throw_impact(hit_atom, speed: float = 5) -> bool:
	"""Handle impact when thrown"""
	# Auto-activate if launched from grenade launcher
	if launched and not active:
		activate()
	
	return true

func update_appearance() -> void:
	"""Update visual appearance based on current state"""
	super.update_appearance()
	
	# Additional appearance updates based on grenade state can be added here

func serialize():
	"""Save grenade state to dictionary"""
	var data = super.serialize()
	
	data["grenade_type"] = grenade_type
	data["det_time"] = det_time
	data["active"] = active
	data["launched"] = launched
	data["dangerous"] = dangerous
	data["explosion_range"] = explosion_range
	data["shrapnel_range"] = shrapnel_range
	data["flash_range"] = flash_range
	data["smoke_radius"] = smoke_radius
	data["smoke_duration"] = smoke_duration
	
	return data

func deserialize(data):
	"""Restore grenade state from dictionary"""
	super.deserialize(data)
	
	if "grenade_type" in data: grenade_type = data.grenade_type
	if "det_time" in data: det_time = data.det_time
	if "active" in data: 
		active = data.active
		if active and det_time > 0:
			# Restart timer if grenade was active
			start_detonation_timer()
		# Update visual state
		set_animation_state("primed" if active else "armed")
	if "launched" in data: launched = data.launched
	if "dangerous" in data: dangerous = data.dangerous
	if "explosion_range" in data: explosion_range = data.explosion_range
	if "shrapnel_range" in data: shrapnel_range = data.shrapnel_range
	if "flash_range" in data: flash_range = data.flash_range
	if "smoke_radius" in data: smoke_radius = data.smoke_radius
	if "smoke_duration" in data: smoke_duration = data.smoke_duration
