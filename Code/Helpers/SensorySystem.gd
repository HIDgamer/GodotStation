extends Node2D
class_name SensorySystem

# =============================================================================
# CONSTANTS
# =============================================================================

const MESSAGE_DURATION = 4.0
const MAX_MESSAGES = 10
const PERCEPTION_RANGE = 12
const SOUND_DEDUPLICATION_TIME = 0.5
const MAX_RECENT_SOUNDS = 20

# =============================================================================
# EXPORTS
# =============================================================================

@export_group("Perception Settings")
@export var vision_range: float = PERCEPTION_RANGE
@export var smell_range: float = PERCEPTION_RANGE * 0.7
@export var hearing_range: float = PERCEPTION_RANGE * 1.5
@export var perception_update_interval: float = 0.1

@export_group("Sensory Capabilities")
@export var can_smell: bool = true
@export var can_hear: bool = true
@export var can_see: bool = true
@export var enable_directional_hearing: bool = true

@export_group("Vision Settings")
@export var is_blinded: bool = false
@export var darkness_level: float = 0.0
@export var night_vision_enabled: bool = false
@export var vision_cone_angle: float = 360.0

@export_group("Audio Settings")
@export var global_volume_modifier: float = 1.0
@export var sound_attenuation_rate: float = 0.8
@export var enable_sound_occlusion: bool = true
@export var footstep_volume_modifier: float = 0.7

@export_group("Message System")
@export var enable_chat_integration: bool = true
@export var message_display_duration: float = MESSAGE_DURATION
@export var max_message_history: int = MAX_MESSAGES
@export var auto_scroll_messages: bool = true

@export_group("Debug Settings")
@export var debug_mode: bool = false
@export var log_sound_events: bool = false
@export var log_vision_events: bool = false
@export var show_perception_ranges: bool = false

# =============================================================================
# SIGNALS
# =============================================================================

signal message_displayed(message, category)
signal sound_perceived(sound_name, position, emitter)
signal vision_changed(new_range)
signal smell_detected(smell_type, position, intensity)
signal entity_registered(entity)
signal entity_unregistered(entity)
signal perception_state_changed(state_type, enabled)

# =============================================================================
# PRIVATE VARIABLES
# =============================================================================

# Entity tracking
var registered_entities = {}
var entity_positions = {}
var entity_states = {}
var local_entity = null

# Sound management
var recent_sounds = []
var sound_cooldowns = {}
var sound_event_counter = 0

# Vision state
var vision_modifiers = {}
var vision_blocked_directions = []

# System references
var audio_manager = null
var parent_entity = null
var world = null
var chat_ui = null

# Performance tracking
var perception_update_timer = 0.0
var processed_entities_this_frame = 0

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready():
	_find_system_references()
	_setup_perception_system()
	_connect_to_chat_system()
	
	if debug_mode:
		print("SensorySystem: Initialized for ", parent_entity.name if parent_entity else "unknown entity")

func _process(delta):
	_update_perception_system(delta)

# =============================================================================
# INITIALIZATION
# =============================================================================

func _find_system_references():
	parent_entity = get_parent()
	
	world = get_parent()
	if not world:
		var root = get_tree().root
		world = root.get_node_or_null("World")
	
	audio_manager = world.get_node_or_null("AudioManager")

func _setup_perception_system():
	_apply_vision_settings()
	_setup_sound_system()
	_initialize_entity_tracking()

func _apply_vision_settings():
	if is_blinded:
		vision_range = 1.0
	elif darkness_level > 0.0:
		_apply_darkness_effects()

func _apply_darkness_effects():
	var darkness_modifier = 1.0 - darkness_level
	if night_vision_enabled:
		darkness_modifier = max(darkness_modifier, 0.3)
	
	vision_range = PERCEPTION_RANGE * darkness_modifier

func _setup_sound_system():
	recent_sounds = []
	sound_cooldowns = {}
	sound_event_counter = 0

func _initialize_entity_tracking():
	registered_entities = {}
	entity_positions = {}
	entity_states = {}

func _connect_to_chat_system():
	if not enable_chat_integration:
		return
		
	_find_chat_ui()
	
	if chat_ui:
		if not self.is_connected("message_displayed", Callable(self, "_on_message_displayed")):
			self.connect("message_displayed", Callable(self, "_on_message_displayed"))

func _find_chat_ui():
	var main = get_parent().get_tree().root
	chat_ui = main.get_node_or_null("ChatUI")

# =============================================================================
# PERCEPTION UPDATE SYSTEM
# =============================================================================

func _update_perception_system(delta: float):
	_update_timers(delta)
	_process_sound_cooldowns(delta)
	
	if perception_update_timer >= perception_update_interval:
		perception_update_timer = 0.0
		processed_entities_this_frame = 0
		_process_entity_awareness()

func _update_timers(delta: float):
	perception_update_timer += delta

func _process_sound_cooldowns(delta: float):
	var to_remove = []
	
	for sound in sound_cooldowns:
		sound_cooldowns[sound] -= delta
		if sound_cooldowns[sound] <= 0:
			to_remove.append(sound)
	
	for sound in to_remove:
		sound_cooldowns.erase(sound)

func _process_entity_awareness():
	if not local_entity:
		return
		
	var local_pos = _get_entity_position(local_entity)
	
	for id in registered_entities:
		if id == local_entity.get_instance_id():
			continue
			
		var entity = registered_entities[id]
		
		if not is_instance_valid(entity):
			_cleanup_invalid_entity(id)
			continue
		
		_update_entity_awareness(entity, id, local_pos)
		processed_entities_this_frame += 1

func _update_entity_awareness(entity: Node, entity_id: int, local_pos: Vector2):
	var entity_pos = _get_entity_position(entity)
	var distance = local_pos.distance_to(entity_pos) / 32.0
	
	var is_visible = _calculate_visibility(entity_pos, distance)
	var was_visible = entity_states[entity_id].is_visible
	
	if is_visible and not was_visible:
		_process_visible_entity(entity, distance)
		if log_vision_events:
			print("SensorySystem: Entity became visible: ", entity.name)
	
	_update_entity_state(entity_id, is_visible, entity_pos, distance)

func _calculate_visibility(entity_pos: Vector2, distance: float) -> bool:
	if not can_see or is_blinded:
		return false
		
	if distance > vision_range:
		return false
		
	if vision_cone_angle < 360.0:
		if not _is_in_vision_cone(entity_pos):
			return false
	
	if world and world.has_method("has_line_of_sight"):
		var local_pos = _get_entity_position(local_entity)
		return world.has_line_of_sight(local_pos, entity_pos)
	
	return true

func _is_in_vision_cone(target_pos: Vector2) -> bool:
	if not parent_entity:
		return true
		
	var local_pos = _get_entity_position(local_entity)
	var direction_to_target = (target_pos - local_pos).normalized()
	
	var entity_facing = Vector2.RIGHT
	if "facing_direction" in parent_entity:
		entity_facing = parent_entity.facing_direction
	elif parent_entity.has_method("get_facing_direction"):
		entity_facing = parent_entity.get_facing_direction()
	
	var angle_diff = rad_to_deg(direction_to_target.angle_to(entity_facing))
	return abs(angle_diff) <= vision_cone_angle / 2.0

func _update_entity_state(entity_id: int, is_visible: bool, position: Vector2, distance: float):
	if entity_id in entity_states:
		entity_states[entity_id].is_visible = is_visible
		entity_states[entity_id].last_seen = Time.get_ticks_msec() * 0.001
		entity_states[entity_id].last_position = position
		entity_states[entity_id].distance = distance
	
	if entity_id in entity_positions:
		entity_positions[entity_id] = position

# =============================================================================
# ENTITY MANAGEMENT
# =============================================================================

func register_entity(entity):
	if entity.get_instance_id() in registered_entities:
		return
		
	registered_entities[entity.get_instance_id()] = entity
	
	var position = _get_entity_position(entity)
	entity_positions[entity.get_instance_id()] = position
	
	if entity == parent_entity:
		local_entity = entity
	
	entity_states[entity.get_instance_id()] = {
		"last_seen": Time.get_ticks_msec() * 0.001,
		"is_visible": true,
		"last_position": position,
		"last_sound": 0,
		"distance": 0.0,
		"name": entity.entity_name if "entity_name" in entity else entity.name
	}
	
	emit_signal("entity_registered", entity)
	
	if debug_mode:
		print("SensorySystem: Registered entity: ", entity.name)

func unregister_entity(entity):
	var id = entity.get_instance_id()
	
	if registered_entities.has(id):
		registered_entities.erase(id)
		entity_positions.erase(id)
		entity_states.erase(id)
		
		emit_signal("entity_unregistered", entity)
		
		if debug_mode:
			print("SensorySystem: Unregistered entity: ", entity.name)

func update_entity_position(entity, position: Vector2):
	var entity_id = entity.get_instance_id()
	if entity_id in registered_entities:
		entity_positions[entity_id] = position
		
		if entity_id in entity_states:
			entity_states[entity_id].last_seen = Time.get_ticks_msec() * 0.001
			entity_states[entity_id].last_position = position

func _cleanup_invalid_entity(entity_id: int):
	registered_entities.erase(entity_id)
	entity_positions.erase(entity_id)
	entity_states.erase(entity_id)

func _process_visible_entity(entity: Node, distance: float):
	# Process special reactions to seeing entities
	pass

# =============================================================================
# MESSAGE SYSTEM
# =============================================================================

func display_message(message: String, category: String = "info"):
	if message.strip_edges().is_empty():
		return
		
	emit_signal("message_displayed", message, category)
	
	if debug_mode:
		print("SensorySystem: ", message)

func display_notification(message: String, category: String = "important"):
	display_message("[b]" + message + "[/b]", category)
	
	if audio_manager:
		audio_manager.play_global_sound("notification", 0.7)

func _on_message_displayed(message: String, category: String):
	if not enable_chat_integration or not chat_ui:
		return
		
	var chat_category = _map_message_category(category)
	
	if chat_ui.has_method("add_message"):
		chat_ui.add_message(message, chat_category)
	elif chat_ui.has_method("receive_message"):
		chat_ui.receive_message(message, chat_category, "System")

func _map_message_category(category: String) -> String:
	match category:
		"info": return "default"
		"warning": return "warning"
		"danger": return "alert"
		"important": return "system"
		_: return "default"

# =============================================================================
# SOUND SYSTEM
# =============================================================================

func emit_sound(position: Vector2, z_level: int, sound_name: String, volume: float = 1.0, emitter = null):
	if not audio_manager:
		return
	
	var modified_volume = volume * global_volume_modifier
	var subtype = _determine_sound_subtype(sound_name, position, z_level)
	
	audio_manager.play_positioned_sound(sound_name, position, modified_volume, subtype)
	
	emit_signal("sound_perceived", sound_name, position, emitter)
	
	_track_recent_sound(sound_name, position)
	
	if emitter and emitter.get_instance_id() in entity_states:
		entity_states[emitter.get_instance_id()].last_sound = Time.get_ticks_msec() * 0.001
	
	if log_sound_events:
		print("SensorySystem: Emitted sound '", sound_name, "' at ", position)

func perceive_sound(sound_name: String, position: Vector2, volume: float, emitter = null):
	if not can_hear:
		return
		
	if sound_cooldowns.has(sound_name) and sound_cooldowns[sound_name] > 0:
		return
	
	if volume < 0.1:
		return
	
	if not _is_sound_in_range(position, volume):
		return
	
	var cooldown = _calculate_sound_cooldown(sound_name)
	sound_cooldowns[sound_name] = cooldown
	
	if parent_entity and "is_local_player" in parent_entity and parent_entity.is_local_player:
		_generate_sound_message(sound_name, position, emitter)

func emit_footstep_sound(entity):
	if not entity or not audio_manager:
		return
		
	var position = _get_entity_position(entity)
	var z_level = entity.current_z_level if "current_z_level" in entity else 0
	
	emit_sound(position, z_level, "footstep", footstep_volume_modifier, entity)

func _determine_sound_subtype(sound_name: String, position: Vector2, z_level: int) -> String:
	if sound_name == "footstep" and world and world.has_method("get_tile_data"):
		var tile_pos = Vector2i(int(position.x / 32), int(position.y / 32))
		var tile_data = world.get_tile_data(tile_pos, z_level)
		if tile_data and tile_data.has("floor_type"):
			return tile_data.floor_type
	
	return "default"

func _is_sound_in_range(position: Vector2, volume: float) -> bool:
	if not parent_entity:
		return false
		
	var distance = parent_entity.position.distance_to(position) / 32.0
	var effective_range = hearing_range * volume
	
	if enable_sound_occlusion and world and world.has_method("has_line_of_sight"):
		var local_pos = _get_entity_position(local_entity)
		if not world.has_line_of_sight(local_pos, position):
			effective_range *= sound_attenuation_rate
	
	return distance <= effective_range

func _calculate_sound_cooldown(sound_name: String) -> float:
	match sound_name:
		"footstep": return 0.1
		"combat": return 0.3
		"ambient": return 0.5
		_: return 0.2

func _track_recent_sound(sound_name: String, position: Vector2):
	var sound_id = sound_name + str(position) + str(Time.get_ticks_msec() / 500)
	recent_sounds.append(sound_id)
	
	if recent_sounds.size() > MAX_RECENT_SOUNDS:
		recent_sounds.remove_at(0)

func _generate_sound_message(sound_name: String, position: Vector2, emitter = null):
	if sound_name in ["footstep", "ambient"]:
		return
	
	var direction_text = _get_direction_text_from_position(position)
	var message = ""
	var category = "info"
	
	match sound_name:
		"door_open":
			message = "You hear a door open " + direction_text + "."
		"door_close":
			message = "You hear a door close " + direction_text + "."
		"explosion":
			message = "You hear an explosion " + direction_text + "!"
			category = "danger"
		"gunshot":
			message = "You hear gunfire " + direction_text + "!"
			category = "danger"
		"scream":
			message = "You hear a scream " + direction_text + "!"
			category = "warning"
		"body_fall":
			message = "You hear a thud " + direction_text + "."
		"glass_break":
			message = "You hear glass breaking " + direction_text + "."
		"punch", "hit":
			message = "You hear fighting " + direction_text + "."
		"alarm":
			message = "You hear an alarm " + direction_text + "!"
			category = "danger"
		"machinery":
			message = "You hear machinery " + direction_text + "."
	
	if not message.is_empty():
		display_message(message, category)

# =============================================================================
# SMELL SYSTEM
# =============================================================================

func detect_smell(smell_type: String, position: Vector2, intensity: float = 1.0):
	if not can_smell:
		return
		
	if not _is_smell_in_range(position, intensity):
		return
	
	if parent_entity and "is_local_player" in parent_entity and parent_entity.is_local_player:
		_generate_smell_message(smell_type, position, intensity)
	
	emit_signal("smell_detected", smell_type, position, intensity)

func _is_smell_in_range(position: Vector2, intensity: float) -> bool:
	if not parent_entity:
		return false
		
	var distance = parent_entity.position.distance_to(position) / 32.0
	return distance <= smell_range * intensity

func _generate_smell_message(smell_type: String, position: Vector2, intensity: float):
	if intensity < 0.3:
		return
	
	var direction_text = _get_direction_text_from_position(position)
	var smell_intensity = _get_intensity_descriptor(intensity)
	var message = ""
	var category = "info"
	
	match smell_type:
		"smoke":
			message = "You smell " + smell_intensity + " smoke " + direction_text + "."
		"blood":
			message = "You smell " + smell_intensity + " blood " + direction_text + "."
			if intensity > 0.7:
				category = "warning"
		"burning":
			message = "You smell something burning " + direction_text + "."
		"chemical":
			message = "You smell " + smell_intensity + " chemicals " + direction_text + "."
		"food":
			message = "You smell food " + direction_text + "."
		"death":
			message = "You smell death " + direction_text + "."
			category = "warning"
		"plasma":
			message = "You smell plasma " + direction_text + "."
			if intensity > 0.7:
				category = "warning"
	
	if not message.is_empty():
		display_message(message, category)

func _get_intensity_descriptor(intensity: float) -> String:
	if intensity > 0.8:
		return "strong"
	elif intensity > 0.5:
		return "distinct"
	else:
		return "faint"

# =============================================================================
# VISION EFFECTS SYSTEM
# =============================================================================

func set_vision_range(new_range: float):
	vision_range = clamp(new_range, 0.5, PERCEPTION_RANGE * 2.0)
	emit_signal("vision_changed", vision_range)

func set_blinded(is_blind: bool, duration: float = 0.0):
	is_blinded = is_blind
	
	if is_blinded:
		set_vision_range(1.0)
		display_message("You can't see!", "warning")
		
		if duration > 0:
			var timer = Timer.new()
			timer.wait_time = duration
			timer.one_shot = true
			add_child(timer)
			timer.timeout.connect(func(): set_blinded(false))
			timer.start()
	else:
		set_vision_range(PERCEPTION_RANGE)
		display_message("Your vision returns.")
	
	emit_signal("perception_state_changed", "vision", not is_blinded)

func set_darkness_level(level: float):
	darkness_level = clamp(level, 0.0, 1.0)
	_apply_darkness_effects()
	
	emit_signal("vision_changed", vision_range)

func set_night_vision(enabled: bool):
	night_vision_enabled = enabled
	_apply_darkness_effects()
	
	emit_signal("perception_state_changed", "night_vision", enabled)

func set_muffled(is_muffled: bool, factor: float = 0.5):
	if is_muffled:
		global_volume_modifier *= factor
		hearing_range *= factor
	else:
		global_volume_modifier = 1.0
		hearing_range = PERCEPTION_RANGE * 1.5
	
	emit_signal("perception_state_changed", "hearing", not is_muffled)

# =============================================================================
# UTILITY METHODS
# =============================================================================

func _get_entity_position(entity) -> Vector2:
	if not entity or not is_instance_valid(entity):
		return Vector2.ZERO
		
	if entity.has_method("global_position"):
		return entity.global_position
	elif "position" in entity:
		return entity.position
	else:
		return Vector2.ZERO

func _get_direction_text_from_position(position: Vector2) -> String:
	if not parent_entity:
		return "nearby"
		
	var direction = position - parent_entity.position
	var angle = atan2(direction.y, direction.x)
	
	return _get_direction_text(angle)

func _get_direction_text(angle: float) -> String:
	var degrees = rad_to_deg(angle)
	
	if degrees > -22.5 and degrees <= 22.5:
		return "to the east"
	elif degrees > 22.5 and degrees <= 67.5:
		return "to the southeast"
	elif degrees > 67.5 and degrees <= 112.5:
		return "to the south"
	elif degrees > 112.5 and degrees <= 157.5:
		return "to the southwest"
	elif degrees > 157.5 or degrees <= -157.5:
		return "to the west"
	elif degrees > -157.5 and degrees <= -112.5:
		return "to the northwest"
	elif degrees > -112.5 and degrees <= -67.5:
		return "to the north"
	elif degrees > -67.5 and degrees <= -22.5:
		return "to the northeast"
	
	return "nearby"

# =============================================================================
# PUBLIC API
# =============================================================================

func get_perception_stats() -> Dictionary:
	return {
		"vision_range": vision_range,
		"hearing_range": hearing_range,
		"smell_range": smell_range,
		"is_blinded": is_blinded,
		"can_hear": can_hear,
		"can_smell": can_smell,
		"darkness_level": darkness_level,
		"night_vision": night_vision_enabled,
		"registered_entities": registered_entities.size(),
		"recent_sounds": recent_sounds.size(),
		"active_cooldowns": sound_cooldowns.size()
	}

func get_visible_entities() -> Array:
	var visible = []
	for entity_id in entity_states:
		if entity_states[entity_id].is_visible:
			if entity_id in registered_entities:
				visible.append(registered_entities[entity_id])
	return visible

func get_nearby_entities(range_override: float = -1.0) -> Array:
	var check_range = range_override if range_override > 0 else vision_range
	var nearby = []
	
	if not local_entity:
		return nearby
		
	var local_pos = _get_entity_position(local_entity)
	
	for entity_id in registered_entities:
		if entity_id == local_entity.get_instance_id():
			continue
			
		var entity = registered_entities[entity_id]
		if not is_instance_valid(entity):
			continue
			
		var distance = local_pos.distance_to(_get_entity_position(entity)) / 32.0
		if distance <= check_range:
			nearby.append(entity)
	
	return nearby

func force_perception_update():
	perception_update_timer = perception_update_interval
	_process_entity_awareness()

func clear_sound_cooldowns():
	sound_cooldowns.clear()

func reset_perception_ranges():
	vision_range = PERCEPTION_RANGE
	hearing_range = PERCEPTION_RANGE * 1.5
	smell_range = PERCEPTION_RANGE * 0.7
	
	emit_signal("vision_changed", vision_range)

# =============================================================================
# DEBUG VISUALIZATION
# =============================================================================

func _draw():
	if not show_perception_ranges or not parent_entity:
		return
		
	var pos = parent_entity.position
	
	# Draw vision range
	if can_see and not is_blinded:
		draw_circle(Vector2.ZERO, vision_range * 32, Color(0, 1, 0, 0.1))
		draw_arc(Vector2.ZERO, vision_range * 32, 0, TAU, 64, Color(0, 1, 0, 0.3), 2)
	
	# Draw hearing range
	if can_hear:
		draw_circle(Vector2.ZERO, hearing_range * 32, Color(0, 0, 1, 0.05))
		draw_arc(Vector2.ZERO, hearing_range * 32, 0, TAU, 64, Color(0, 0, 1, 0.2), 1)
	
	# Draw smell range
	if can_smell:
		draw_circle(Vector2.ZERO, smell_range * 32, Color(1, 1, 0, 0.05))
		draw_arc(Vector2.ZERO, smell_range * 32, 0, TAU, 64, Color(1, 1, 0, 0.2), 1)

# =============================================================================
# CLEANUP
# =============================================================================

func _exit_tree():
	for entity_id in registered_entities.keys():
		var entity = registered_entities[entity_id]
		if is_instance_valid(entity):
			unregister_entity(entity)
	
	registered_entities.clear()
	entity_positions.clear()
	entity_states.clear()
	recent_sounds.clear()
	sound_cooldowns.clear()
