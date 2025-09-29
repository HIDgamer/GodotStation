@tool
extends Machinery
class_name Door

const TILE_SIZE = 32
const DEFAULT_OPEN_TIME = 0.4
const DEFAULT_AUTOCLOSE_TIME = 15.0
const COLLISION_CHECK_DELAY = 0.1
const BLOCKING_CHECK_INTERVAL = 2.0
const BUMP_COOLDOWN = 0.5

const SOUND_AIRLOCK_OPEN = preload("res://Sound/machines/airlock.ogg")
const SOUND_AIRLOCK_CLOSE = preload("res://Sound/machines/airlock.ogg")
const SOUND_DOOR_OPEN = preload("res://Sound/machines/door_open.ogg")
const SOUND_DOOR_CLOSE = preload("res://Sound/machines/door_close.ogg")
const SOUND_BUZZ_DENY = preload("res://Sound/machines/buzz-two.ogg")
const SOUND_DOOR_BANG = preload("res://Sound/machines/door_locked.ogg")

enum DoorState {
	CLOSED,
	OPENING,
	OPEN,
	CLOSING,
	DENIED,
	MALFUNCTIONING
}

enum DoorType {
	CIVILIAN,
	SECURITY,
	ENGINEERING,
	MEDICAL,
	COMMAND,
	MAINTENANCE,
	EXTERNAL,
	BLAST_DOOR
}

enum DoorOrientation {
	HORIZONTAL,
	VERTICAL
}

@export_group("Door Configuration")
@export var door_type: DoorType = DoorType.CIVILIAN
@export var door_orientation: DoorOrientation = DoorOrientation.HORIZONTAL
@export var door_width: int = 1 : set = _set_door_width
@export var door_id_override: String = ""
@export var is_airlock: bool = false : set = _set_is_airlock

@export_group("Access Control")
@export var require_access: bool = true
@export var access_level: int = 0
@export var access_cards_required: Array[int] = []
@export var emergency_access: bool = false

@export_group("Door Behavior")
@export var auto_close: bool = true
@export var auto_close_delay: float = DEFAULT_AUTOCLOSE_TIME
@export var open_speed: float = DEFAULT_OPEN_TIME
@export var start_open: bool = false
@export var locked: bool = false

@export_group("Visual Settings")
@export var _blocks_light: bool = true
@export var glass_door: bool = false

@export_group("Audio Settings")
@export var open_sound: AudioStream = SOUND_DOOR_OPEN
@export var close_sound: AudioStream = SOUND_DOOR_CLOSE
@export var deny_sound: AudioStream = SOUND_BUZZ_DENY
@export var sound_volume: float = 0.6

var current_door_state: DoorState = DoorState.CLOSED
var is_operating: bool = false
var last_interaction_time: float = 0.0
var last_bump_time: float = 0.0

var door_tiles: Array[Vector2i] = []
var occupied_tiles: Array[Vector2i] = []
var current_tile_position: Vector2i

var autoclose_timer: Timer
var operation_timer: Timer
var collision_check_timer: Timer
var blocking_check_timer: Timer

@onready var door_sprite: AnimatedSprite2D = $Door
@onready var audio_player: AudioStreamPlayer2D = $AudioPlayer
@onready var collision_component: DoorCollisionComponent = $DoorCollisionComponent

var authorized_entities: Array = []
var world = null
var tile_occupancy_system = null
var audio_system = null

signal door_opened(door: Door)
signal door_closed(door: Door)
signal door_access_denied(door: Door, entity: Node)
signal door_blocked(door: Door, blocking_entity: Node)
signal door_state_changed(door: Door, old_state: DoorState, new_state: DoorState)

func _process(_delta):
	if Engine.is_editor_hint():
		if door_orientation == DoorOrientation.HORIZONTAL:
			_set_door_animation("closed")
		elif door_orientation == DoorOrientation.VERTICAL:
			_set_door_animation("closed")

func _ready():
	machinery_type = "door"
	obj_name = _get_door_type_name()
	obj_desc = "A " + _get_door_type_name() + " door."
	entity_type = "door"
	entity_dense = true
	pickupable = false
	can_be_bumped = true
	anchored = true
	can_block_movement = true
	
	requires_power = (door_type in [DoorType.BLAST_DOOR, DoorType.SECURITY])
	power_usage = 0.1 if requires_power else 0.0
	use_cooldown = open_speed
	
	if door_id_override != "":
		machinery_id = door_id_override
	else:
		machinery_id = "door_" + _get_door_type_prefix() + "_" + str(get_instance_id())
	
	super()
	
	_set_door_sounds()
	_setup_systems()
	_setup_timers()
	
	await get_tree().process_frame
	_setup_initial_state()
	_register_with_systems()
	
	add_to_group("doors")

func _set_door_sounds():
	if is_airlock:
		open_sound = SOUND_AIRLOCK_OPEN
		close_sound = SOUND_AIRLOCK_CLOSE
	else:
		match door_type:
			DoorType.BLAST_DOOR, DoorType.EXTERNAL:
				open_sound = SOUND_AIRLOCK_OPEN
				close_sound = SOUND_AIRLOCK_CLOSE
			_:
				open_sound = SOUND_DOOR_OPEN
				close_sound = SOUND_DOOR_CLOSE

func _set_is_airlock(value: bool):
	is_airlock = value
	if is_inside_tree():
		_set_door_sounds()

func _setup_systems():
	world = get_node_or_null("/root/World")
	if not world:
		world = get_tree().get_first_node_in_group("world")
	
	tile_occupancy_system = get_node_or_null("/root/World/TileOccupancySystem")
	if not tile_occupancy_system:
		tile_occupancy_system = get_tree().get_first_node_in_group("tile_occupancy_system")
	
	audio_system = get_node_or_null("/root/World/AudioSystem")
	if not audio_system:
		audio_system = get_tree().get_first_node_in_group("audio_system")

func _setup_timers():
	autoclose_timer = Timer.new()
	autoclose_timer.wait_time = auto_close_delay
	autoclose_timer.one_shot = true
	autoclose_timer.timeout.connect(_on_autoclose_timeout)
	add_child(autoclose_timer)
	
	operation_timer = Timer.new()
	operation_timer.wait_time = open_speed
	operation_timer.one_shot = true
	operation_timer.timeout.connect(_on_operation_complete)
	add_child(operation_timer)
	
	collision_check_timer = Timer.new()
	collision_check_timer.wait_time = COLLISION_CHECK_DELAY
	collision_check_timer.one_shot = true
	collision_check_timer.timeout.connect(_check_collision_delayed)
	add_child(collision_check_timer)
	
	blocking_check_timer = Timer.new()
	blocking_check_timer.wait_time = BLOCKING_CHECK_INTERVAL
	blocking_check_timer.timeout.connect(_check_for_blocking_entities)
	add_child(blocking_check_timer)

func _setup_initial_state():
	if not world:
		await get_tree().process_frame
	
	current_tile_position = world_to_tile(global_position)
	_calculate_door_tiles()
	
	if start_open:
		current_door_state = DoorState.OPEN
		entity_dense = false
		machinery_state = "open"
		_set_door_animation("open")
	else:
		current_door_state = DoorState.CLOSED
		entity_dense = true
		machinery_state = "closed"
		_set_door_animation("close")
	
	_update_collision_and_opacity()

func _register_with_systems():
	await get_tree().process_frame
	
	if collision_component:
		collision_component.force_collision_update()
	
	if tile_occupancy_system and door_tiles.size() > 0:
		var success = tile_occupancy_system.register_multi_tile_entity(self, door_tiles, current_z_level)
		if not success:
			for tile_pos in door_tiles:
				tile_occupancy_system.register_entity_at_tile(self, tile_pos, current_z_level)

func _set_door_width(value: int):
	var old_tiles = door_tiles.duplicate()
	door_width = max(1, value)
	
	if is_inside_tree():
		_unregister_from_systems(old_tiles)
		
		_calculate_door_tiles()
		_update_collision_and_opacity()
		
		if collision_component:
			collision_component.force_collision_update()
		elif tile_occupancy_system:
			tile_occupancy_system.register_multi_tile_entity(self, door_tiles, current_z_level)

func _unregister_from_systems(tiles_to_unregister: Array[Vector2i] = []):
	if tiles_to_unregister.is_empty():
		tiles_to_unregister = door_tiles
	
	if collision_component:
		collision_component._cleanup_current_collision_mode()
	elif tile_occupancy_system and tiles_to_unregister.size() > 0:
		tile_occupancy_system.remove_multi_tile_entity(self, tiles_to_unregister, current_z_level)

func _calculate_door_tiles():
	door_tiles.clear()
	occupied_tiles.clear()
	
	var base_tile = current_tile_position
	
	for i in range(door_width):
		var tile_offset = Vector2i.ZERO
		
		if door_orientation == DoorOrientation.HORIZONTAL:
			tile_offset = Vector2i(i, 0)
		else:
			tile_offset = Vector2i(0, i)
		
		var tile_pos = base_tile + tile_offset
		door_tiles.append(tile_pos)
		occupied_tiles.append(tile_pos)

func world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x / TILE_SIZE), int(world_pos.y / TILE_SIZE))

func tile_to_world(tile_pos: Vector2i) -> Vector2:
	return Vector2((tile_pos.x * TILE_SIZE) + (TILE_SIZE / 2.0), 
				   (tile_pos.y * TILE_SIZE) + (TILE_SIZE / 2.0))

func get_time() -> float:
	return Time.get_ticks_msec() / 1000.0

func interact(user) -> bool:
	if is_operating:
		return false
	
	if get_time() < last_interaction_time + 0.2:
		return false
	
	if not _check_access(user):
		_deny_access(user)
		return false
	
	last_interaction_time = get_time()
	
	if current_door_state == DoorState.CLOSED:
		return open_door(user)
	elif current_door_state == DoorState.OPEN:
		return close_door(user)
	
	return false

func on_bump(bumper, direction: Vector2i = Vector2i.ZERO) -> bool:
	if not can_be_bumped:
		return blocks_movement()
	
	if is_operating:
		return blocks_movement()
	
	var current_time = get_time()
	if current_time < last_bump_time + BUMP_COOLDOWN:
		return blocks_movement()
	
	last_bump_time = current_time
	
	if current_door_state == DoorState.CLOSED and _check_access(bumper):
		open_door(bumper)
		return false
	
	if current_door_state == DoorState.CLOSING:
		if _check_access(bumper):
			cancel_closing()
			return false
		else:
			return blocks_movement()
	
	return blocks_movement()

func blocks_light() -> bool:
	return _blocks_light and is_closed

func blocks_movement() -> bool:
	return entity_dense and can_block_movement and _door_blocks_movement()

func _door_blocks_movement() -> bool:
	match current_door_state:
		DoorState.CLOSED:
			return true
		DoorState.DENIED:
			return true
		DoorState.CLOSING:
			return true
		DoorState.OPENING:
			return false
		DoorState.OPEN:
			return false
		DoorState.MALFUNCTIONING:
			return obj_integrity > integrity_failure
		_:
			return true

func open_door(activator: Node = null) -> bool:
	if current_door_state == DoorState.OPEN or is_operating:
		return false
	
	if locked and not _has_emergency_access(activator):
		_deny_access(activator)
		return false
	
	if requires_power and not is_powered:
		show_user_message(activator, "The door has no power!")
		return false
	
	if not _can_open():
		return false
	
	_change_door_state(DoorState.OPENING)
	is_operating = true
	
	_set_door_animation("opening")
	_play_sound(open_sound)
	
	operation_timer.wait_time = open_speed
	operation_timer.start()
	
	if autoclose_timer.time_left > 0:
		autoclose_timer.stop()
	if blocking_check_timer.time_left > 0:
		blocking_check_timer.stop()
	
	return true

func close_door(activator: Node = null) -> bool:
	if current_door_state == DoorState.CLOSED or is_operating:
		return false
	
	if not _can_close():
		collision_check_timer.start()
		return false
	
	_change_door_state(DoorState.CLOSING)
	is_operating = true
	
	_set_door_animation("closing")
	_play_sound(close_sound)
	
	operation_timer.wait_time = open_speed
	operation_timer.start()
	
	return true

func cancel_closing():
	if current_door_state != DoorState.CLOSING:
		return
	
	if operation_timer.time_left > 0:
		operation_timer.stop()
	
	_change_door_state(DoorState.OPENING)
	is_operating = true
	
	_set_door_animation("opening")
	_play_sound(open_sound)
	
	operation_timer.wait_time = open_speed * 0.5
	operation_timer.start()

func force_open(reason: String = ""):
	if current_door_state != DoorState.OPEN:
		_change_door_state(DoorState.OPENING)
		is_operating = true
		_set_door_animation("opening")
		operation_timer.wait_time = open_speed * 0.5
		operation_timer.start()

func emergency_open():
	force_open("emergency")

func emergency_close():
	if current_door_state != DoorState.CLOSED:
		if autoclose_timer.time_left > 0:
			autoclose_timer.stop()
		if blocking_check_timer.time_left > 0:
			blocking_check_timer.stop()
		close_door()

func set_close_delay(delay: float):
	if auto_close:
		auto_close_delay = delay
		if autoclose_timer.time_left > 0:
			autoclose_timer.wait_time = delay
			autoclose_timer.start()

func _can_open() -> bool:
	return true

func _can_close() -> bool:
	if collision_component and collision_component.has_method("can_door_close"):
		return collision_component.can_door_close()
	
	if not tile_occupancy_system:
		return true
	
	for tile_pos in door_tiles:
		var entities = tile_occupancy_system.get_entities_at(tile_pos, current_z_level)
		for entity in entities:
			if entity == self:
				continue
			
			if _is_entity_blocking(entity):
				emit_signal("door_blocked", self, entity)
				return false
	
	return true

func _is_entity_blocking(entity: Node) -> bool:
	if not is_instance_valid(entity):
		return false
	
	if "entity_dense" in entity and entity.entity_dense:
		return true
	
	if "movable" in entity and not entity.movable:
		return true
	
	if entity.has_method("blocks_door_closure"):
		return entity.blocks_door_closure()
	
	return false

func _check_collision_delayed():
	if current_door_state == DoorState.OPEN:
		close_door()

func _check_for_blocking_entities():
	if current_door_state == DoorState.OPEN and autoclose_timer.time_left > 0:
		if collision_component and collision_component.has_method("has_blocking_entities"):
			if collision_component.has_blocking_entities():
				autoclose_timer.start()

func _change_door_state(new_state: DoorState):
	var old_state = current_door_state
	current_door_state = new_state
	
	entity_dense = _should_be_dense()
	
	match new_state:
		DoorState.OPEN:
			machinery_state = "open"
		DoorState.CLOSED:
			machinery_state = "closed"
		DoorState.OPENING:
			machinery_state = "opening"
		DoorState.CLOSING:
			machinery_state = "closing"
		_:
			machinery_state = "processing"
	
	emit_signal("door_state_changed", self, old_state, new_state)

func _should_be_dense() -> bool:
	return current_door_state in [DoorState.CLOSED, DoorState.CLOSING, DoorState.DENIED]

func _on_operation_complete():
	is_operating = false
	
	match current_door_state:
		DoorState.OPENING:
			_change_door_state(DoorState.OPEN)
			_set_door_animation("open")
			_update_collision_and_opacity()
			
			if auto_close:
				autoclose_timer.start()
				blocking_check_timer.start()
			
			emit_signal("door_opened", self)
		
		DoorState.CLOSING:
			_change_door_state(DoorState.CLOSED)
			_set_door_animation("close")
			_update_collision_and_opacity()
			
			if blocking_check_timer.time_left > 0:
				blocking_check_timer.stop()
			
			emit_signal("door_closed", self)

func _on_autoclose_timeout():
	if current_door_state == DoorState.OPEN and not is_operating:
		if collision_component and collision_component.has_method("can_door_close"):
			if not collision_component.can_door_close():
				autoclose_timer.start()
				return
		
		close_door()

func _set_door_animation(animation_state: String):
	if not door_sprite:
		return
	
	var door_type_prefix = _get_door_type_prefix()
	var orientation_suffix = "h" if door_orientation == DoorOrientation.HORIZONTAL else "v"
	var animation_name = door_type_prefix + "_" + animation_state + "_" + orientation_suffix
	
	if door_sprite.sprite_frames and door_sprite.sprite_frames.has_animation(animation_name):
		door_sprite.play(animation_name)

func _play_sound(sound: AudioStream):
	if not sound:
		return
	
	if not audio_player:
		var new_audio_player = AudioStreamPlayer2D.new()
		add_child(new_audio_player)
		audio_player = new_audio_player
	
	audio_player.stream = sound
	audio_player.volume_db = linear_to_db(sound_volume)
	audio_player.play()

func _update_collision_and_opacity():
	if not world:
		return
	
	entity_dense = _should_be_dense()
	
	if world.has_method("update_tile_opacity"):
		for tile_pos in door_tiles:
			var blocks_light_now = entity_dense and _blocks_light and not glass_door
			world.update_tile_opacity(tile_pos, current_z_level, blocks_light_now)

func _get_door_type_prefix() -> String:
	match door_type:
		DoorType.CIVILIAN: return "civ"
		DoorType.SECURITY: return "sec"
		DoorType.ENGINEERING: return "engi"
		DoorType.MEDICAL: return "med"
		DoorType.COMMAND: return "cmd"
		DoorType.MAINTENANCE: return "maint"
		DoorType.EXTERNAL: return "ext"
		DoorType.BLAST_DOOR: return "blast"
		_: return "civ"

func _get_door_type_name() -> String:
	var base_name = ""
	match door_type:
		DoorType.CIVILIAN: base_name = "civilian"
		DoorType.SECURITY: base_name = "security"
		DoorType.ENGINEERING: base_name = "engineering"
		DoorType.MEDICAL: base_name = "medical"
		DoorType.COMMAND: base_name = "command"
		DoorType.MAINTENANCE: base_name = "maintenance"
		DoorType.EXTERNAL: base_name = "external"
		DoorType.BLAST_DOOR: base_name = "blast"
		_: base_name = "civilian"
	
	if is_airlock:
		return base_name + " airlock"
	else:
		return base_name

func _check_access(entity: Node) -> bool:
	if not require_access:
		return true
	
	if emergency_access and _is_emergency_situation():
		return true
	
	if entity in authorized_entities:
		return true
	
	if entity.has_method("get_access_level"):
		var entity_access = entity.get_access_level()
		if entity_access >= access_level:
			return true
	
	if entity.has_method("get_id_card"):
		var id_card = entity.get_id_card()
		if id_card and _check_id_access(id_card):
			return true
	
	return false

func _check_id_access(id_card: Node) -> bool:
	if not id_card:
		return false
	
	if id_card.has_method("get_access_codes"):
		var access_codes = id_card.get_access_codes()
		for required_code in access_cards_required:
			if required_code in access_codes:
				return true
	
	return false

func _has_emergency_access(entity: Node) -> bool:
	if not entity:
		return false
	
	if entity.has_method("has_emergency_access"):
		return entity.has_emergency_access()
	
	return false

func _is_emergency_situation() -> bool:
	if world and world.has_method("is_emergency_active"):
		return world.is_emergency_active()
	
	return false

func _deny_access(entity: Node):
	if current_door_state != DoorState.DENIED:
		_change_door_state(DoorState.DENIED)
		_set_door_animation("deny")
		_play_sound(deny_sound)
		
		await get_tree().create_timer(0.5).timeout
		if current_door_state == DoorState.DENIED:
			_change_door_state(DoorState.CLOSED)
			_set_door_animation("close")
	
	emit_signal("door_access_denied", self, entity)

func attackby(item, user, params = null) -> bool:
	if not item or not user:
		return false
	
	if "tool_behaviour" in item:
		match item.tool_behaviour:
			"crowbar":
				return await handle_crowbar_interaction(item, user)
			"multitool":
				return handle_multitool_interaction(item, user)
			"id_card":
				return handle_id_card_interaction(item, user)
			_:
				return super.attackby(item, user, params)
	
	if item.has_method("force_door"):
		return item.force_door(self, user)
	
	return super.attackby(item, user, params)

func handle_crowbar_interaction(crowbar, user) -> bool:
	if not is_powered and current_door_state == DoorState.CLOSED:
		show_user_message(user, "You start prying the door open...")
		
		await get_tree().create_timer(2.0).timeout
		
		if not is_powered:
			force_open("crowbar")
			show_user_message(user, "You pry the door open!")
			return true
	
	show_user_message(user, "The door is powered and won't budge.")
	return false

func handle_multitool_interaction(multitool, user) -> bool:
	if user.has_method("has_skill") and not user.has_skill("engineering", 2):
		show_user_message(user, "You don't know how to use this on the door.")
		return false
	
	locked = not locked
	var status = "locked" if locked else "unlocked"
	show_user_message(user, "You " + status + " the door with the multitool.")
	return true

func handle_id_card_interaction(id_card, user) -> bool:
	if _check_id_access(id_card):
		return interact(user)
	else:
		_deny_access(user)
		return false

func attack_hand(user, params = null) -> bool:
	var user_intent = get_user_intent(user)
	
	match user_intent:
		0: return interact(user)
		1: return handle_disarm_door(user)
		2: return handle_grab_door(user)
		3: return handle_harm_door(user)
		_: return interact(user)

func handle_disarm_door(user) -> bool:
	if current_door_state == DoorState.OPEN and auto_close:
		close_door(user)
		return true
	
	show_user_message(user, "You push against the door.")
	return false

func handle_grab_door(user) -> bool:
	show_user_message(user, "You can't grab a door!")
	return false

func handle_harm_door(user) -> bool:
	take_damage(5.0, 1, "melee", true, 0.0, user)
	show_user_message(user, "You bang on the door!")
	_play_sound(SOUND_DOOR_BANG)
	return true

func is_open() -> bool:
	return current_door_state == DoorState.OPEN

func is_closed() -> bool:
	return current_door_state == DoorState.CLOSED

func get_door_tiles() -> Array[Vector2i]:
	return door_tiles.duplicate()

func add_authorized_entity(entity: Node):
	if entity and entity not in authorized_entities:
		authorized_entities.append(entity)

func remove_authorized_entity(entity: Node):
	authorized_entities.erase(entity)

func set_locked(is_locked: bool):
	locked = is_locked

func obj_break(damage_flag: String = "") -> void:
	super.obj_break(damage_flag)
	
	if is_operating:
		is_operating = false
		operation_timer.stop()
	
	if autoclose_timer.time_left > 0:
		autoclose_timer.stop()
	if blocking_check_timer.time_left > 0:
		blocking_check_timer.stop()
	
	if current_door_state != DoorState.OPEN:
		force_open("damaged")
	
	_change_door_state(DoorState.MALFUNCTIONING)

func _on_power_restored():
	super._on_power_restored()
	if current_door_state == DoorState.MALFUNCTIONING:
		_change_door_state(DoorState.CLOSED)

func _on_power_lost():
	super._on_power_lost()
	if door_type == DoorType.BLAST_DOOR:
		if current_door_state == DoorState.OPEN:
			emergency_close()

func _can_activate_custom(user = null) -> bool:
	return not is_operating and current_door_state in [DoorState.CLOSED, DoorState.OPEN]

func _on_activated(user = null):
	if current_door_state == DoorState.CLOSED:
		open_door(user)
	elif current_door_state == DoorState.OPEN:
		close_door(user)

func examine(examiner) -> String:
	var examine_text = super.examine(examiner)
	
	var door_state_text = ""
	match current_door_state:
		DoorState.OPEN:
			door_state_text = "It is open."
		DoorState.CLOSED:
			door_state_text = "It is closed."
		DoorState.OPENING:
			door_state_text = "It is opening."
		DoorState.CLOSING:
			door_state_text = "It is closing."
		_:
			door_state_text = "It appears to be malfunctioning."
	
	examine_text += "\n" + door_state_text
	
	if locked:
		examine_text += " It appears to be locked."
	
	if requires_power:
		if is_powered:
			examine_text += " The power indicator is lit."
		else:
			examine_text += " It has no power."
	
	if door_width > 1:
		examine_text += " It is " + str(door_width) + " tiles wide."
	
	if is_airlock:
		examine_text += " It appears to be an airlock."
	
	return examine_text

func _exit_tree():
	_unregister_from_systems()
	super._exit_tree()

func _get_configuration_warnings():
	var warnings = []
	
	if not door_sprite:
		warnings.append("Door sprite (AnimatedSprite2D) not found as child node named 'Door'")
	
	if door_width < 1:
		warnings.append("Door width must be at least 1")
	
	if door_width > 3:
		warnings.append("Door width greater than 3 may cause performance issues")
	
	return warnings
