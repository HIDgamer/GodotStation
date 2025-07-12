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

# Grenade properties
var grenade_type: int = GrenadeType.EXPLOSIVE
var det_time: float = 5.0  # Time until detonation in seconds
var active: bool = false    # Whether the grenade is active/armed
var launched: bool = false  # Whether it was launched from a grenade launcher
var dangerous: bool = true  # Whether the grenade is harmful

# Effect ranges
var explosion_range: int = 3    # Range of explosion in tiles
var shrapnel_range: int = 4     # Range of shrapnel in tiles
var flash_range: int = 0        # Range of flash effect in tiles
var smoke_radius: int = 3       # Radius of smoke in tiles
var smoke_duration: float = 10.0 # Duration of smoke in seconds

# Sound effects
var arm_sound = null           # Sound when armed
var explosion_sound = null     # Sound when detonated

# Timer for detonation
var detonation_timer: Timer = null

# Signals
signal primed(user)
signal detonated(position)

func _init():
	super._init()  # Call parent _init
	obj_name = "grenade"
	obj_desc = "A hand grenade. Pull pin, throw, and count to 5."
	
	# Set grenade-specific properties
	force = 5  # Some base damage for hitting with it
	w_class = 2  # Small item
	throwforce = 10  # Good throwing force
	attack_verb = ["strikes", "hits", "bashes"]
	
	# Set slot flags for where this can be equipped
	equip_slot_flags = Slots.LEFT_HAND | Slots.RIGHT_HAND | Slots.BELT | Slots.POCKET
	
	# Add to appropriate groups
	add_to_group("grenade")

func _ready():
	super._ready()  # Call parent _ready
	
	# Set up collision
	if not has_node("CollisionShape2D"):
		var collision = CollisionShape2D.new()
		var shape = CircleShape2D.new()
		shape.radius = 8
		collision.shape = shape
		add_child(collision)

# Activate the grenade (pull the pin)
func activate(user = null) -> bool:
	if active:
		return false
	
	# Set active state
	active = true
	
	# Log bomber if user exists
	if user and "client" in user and user.client:
		print("Grenade activated by: ", user.name)
	
	# Play arm sound
	if arm_sound:
		play_audio(arm_sound)
	
	# Update appearance
	update_appearance()
	
	# Start detonation timer
	if det_time > 0:
		detonation_timer = Timer.new()
		detonation_timer.wait_time = det_time
		detonation_timer.one_shot = true
		detonation_timer.autostart = true
		detonation_timer.timeout.connect(prime)
		add_child(detonation_timer)
	else:
		# Detonate immediately if det_time is 0
		call_deferred("prime")
	
	# Emit signal
	emit_signal("primed", user)
	
	return true

# Called when the timer runs out - detonates the grenade
func prime() -> void:
	# Skip if already detonated
	if not active:
		return
	
	# Detonate
	explode()

# Handle explosion effects
func explode() -> void:
	# Skip if not active
	if not active:
		return
	
	# Set state
	active = false
	
	# Play explosion sound
	if explosion_sound:
		play_audio(explosion_sound)
	
	# Emit signal
	emit_signal("detonated", global_position)
	
	# Default behavior - delete the grenade
	queue_free()

# Override update_appearance to show active state
func update_appearance() -> void:
	super.update_appearance()

# Override attack_self to allow activation by using the grenade
func attack_self(user) -> bool:
	if not active:
		return activate(user)
	return false

func use(user):
	return attack_self(user)

# Handle being thrown
func throw_impact(hit_atom, speed: float = 5) -> bool:
	# Prime on impact if launched
	if launched and not active:
		activate()
	
	# Default handling
	return true

# Play audio at grenade position
func play_audio(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream:
		var audio_player = AudioStreamPlayer2D.new()
		audio_player.stream = stream
		audio_player.autoplay = true
		audio_player.position = global_position
		get_tree().get_root().add_child(audio_player)
		
		# Set up timer to free the audio node
		var timer = Timer.new()
		audio_player.add_child(timer)
		timer.wait_time = 5.0  # Adjust based on sound length
		timer.one_shot = true
		timer.autostart = true
		timer.timeout.connect(func(): audio_player.queue_free())

# Create a camera shake effect
func create_camera_shake(intensity: float) -> void:
	var camera = get_viewport().get_camera_2d()
	if camera and camera.has_method("add_trauma"):
		camera.add_trauma(intensity)

# Serialization
func serialize():
	var data = super.serialize()
	
	# Add grenade-specific properties
	data["grenade_type"] = grenade_type
	data["det_time"] = det_time
	data["active"] = active
	data["launched"] = launched
	
	return data

func deserialize(data):
	super.deserialize(data)
	
	# Restore grenade-specific properties
	if "grenade_type" in data: grenade_type = data.grenade_type
	if "det_time" in data: det_time = data.det_time
	if "active" in data: 
		active = data.active
		if active and det_time > 0:
			# Restart timer if active
			activate(null)
	if "launched" in data: launched = data.launched
