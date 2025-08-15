extends Node

var all_doors: Dictionary = {}
var doors_by_id: Dictionary = {}
var doors_by_type: Dictionary = {}
var emergency_mode: bool = false

signal emergency_mode_changed(active: bool)
signal door_registered(door: Door)
signal door_unregistered(door: Door)

func _ready():
	var existing_doors = get_tree().get_nodes_in_group("doors")
	for door in existing_doors:
		register_door(door)
	
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node):
	if node is Door:
		call_deferred("register_door", node)

func register_door(door: Door):
	if not door or door in all_doors.values():
		return
	
	var door_id = door.get_instance_id()
	all_doors[door_id] = door
	
	# Register by custom ID if provided
	if door.door_id_override != "":
		doors_by_id[door.door_id_override] = door
	
	# Register by type
	var type_key = Door.DoorType.keys()[door.door_type]
	if not type_key in doors_by_type:
		doors_by_type[type_key] = []
	doors_by_type[type_key].append(door)
	
	# Connect door signals
	door.door_state_changed.connect(_on_door_state_changed)
	door.tree_exiting.connect(_on_door_removed.bind(door))
	
	emit_signal("door_registered", door)

func unregister_door(door: Door):
	if not door:
		return
	
	var door_id = door.get_instance_id()
	all_doors.erase(door_id)
	
	if "door_id" in door and "door_id" != "":
		doors_by_id.erase(door.door_id)
	
	var type_key = Door.DoorType.keys()[door.door_type]
	if type_key in doors_by_type:
		doors_by_type[type_key].erase(door)
	
	emit_signal("door_unregistered", door)

func get_door_by_id(door_id: String) -> Door:
	return doors_by_id.get(door_id)

func get_doors_by_type(door_type: Door.DoorType) -> Array[Door]:
	var type_key = Door.DoorType.keys()[door_type]
	return doors_by_type.get(type_key, [])

func get_doors_in_area(center: Vector2, radius: float) -> Array[Door]:
	var nearby_doors: Array[Door] = []
	
	for door in all_doors.values():
		if door and is_instance_valid(door):
			var distance = center.distance_to(door.global_position)
			if distance <= radius:
				nearby_doors.append(door)
	
	return nearby_doors

func get_doors_on_z_level(z_level: int) -> Array[Door]:
	var level_doors: Array[Door] = []
	
	for door in all_doors.values():
		if door and is_instance_valid(door) and door.current_z_level == z_level:
			level_doors.append(door)
	
	return level_doors

# Emergency control
func activate_emergency_mode():
	if emergency_mode:
		return
	
	emergency_mode = true
	
	# Open all civilian and maintenance doors
	for door in get_doors_by_type(Door.DoorType.CIVILIAN):
		door.emergency_open()
	
	for door in get_doors_by_type(Door.DoorType.MAINTENANCE):
		door.emergency_open()
	
	# Close security doors
	for door in get_doors_by_type(Door.DoorType.SECURITY):
		door.emergency_close()
	
	emit_signal("emergency_mode_changed", true)

func deactivate_emergency_mode():
	if not emergency_mode:
		return
	
	emergency_mode = false
	emit_signal("emergency_mode_changed", false)

# Bulk operations
func open_doors_by_id_pattern(pattern: String):
	for door_id in doors_by_id.keys():
		if door_id.match(pattern):
			var door = doors_by_id[door_id]
			if door:
				door.open_door()

func close_doors_by_id_pattern(pattern: String):
	for door_id in doors_by_id.keys():
		if door_id.match(pattern):
			var door = doors_by_id[door_id]
			if door:
				door.close_door()

func lock_doors_by_type(door_type: Door.DoorType, locked: bool = true):
	for door in get_doors_by_type(door_type):
		door.set_locked(locked)

# Event handlers
func _on_door_state_changed(door: Door, old_state, new_state):
	# Handle global door state changes if needed
	pass

func _on_door_removed(door: Door):
	unregister_door(door)

# Utility functions for scene setup
static func create_door_scene(door_type: Door.DoorType, orientation: Door.DoorOrientation, width: int = 1) -> Door:
	var door = Door.new()
	door.door_type = door_type
	door.door_orientation = orientation
	door.door_width = width
	
	# Create required child nodes
	var sprite = AnimatedSprite2D.new()
	sprite.name = "Door"
	door.add_child(sprite)
	
	var audio = AudioStreamPlayer2D.new()
	audio.name = "AudioPlayer"
	door.add_child(audio)
	
	return door

static func setup_door_animations(door: Door, sprite_frames: SpriteFrames):
	var door_sprite = door.get_node("Door") as AnimatedSprite2D
	if door_sprite:
		door_sprite.sprite_frames = sprite_frames

# Debug functions
func get_door_count() -> int:
	return all_doors.size()

func get_door_stats() -> Dictionary:
	var stats = {
		"total_doors": all_doors.size(),
		"by_type": {},
		"by_state": {
			"open": 0,
			"closed": 0,
			"operating": 0
		}
	}
	
	for type_name in doors_by_type.keys():
		stats.by_type[type_name] = doors_by_type[type_name].size()
	
	for door in all_doors.values():
		if door and is_instance_valid(door):
			match door.current_state:
				Door.DoorState.OPEN:
					stats.by_state.open += 1
				Door.DoorState.CLOSED:
					stats.by_state.closed += 1
				_:
					stats.by_state.operating += 1
	
	return stats
