extends Node2D
class_name SensorySystem

# Constants
const MESSAGE_DURATION = 4.0  # How long messages stay on screen
const MAX_MESSAGES = 10  # Maximum messages in history
const PERCEPTION_RANGE = 12  # Default perception range in tiles

# Entity tracking
var registered_entities = {}  # Dictionary of registered entities by id
var entity_positions = {}    # Last known positions of entities
var entity_states = {}       # State information for tracked entities
var local_entity = null      # Reference to the local entity (player)

# Sound variables
var recent_sounds = []  # Sounds heard recently for deduplication
var sound_cooldowns = {}  # Cooldowns for specific sound types

# Vision variables
var vision_range = PERCEPTION_RANGE
var is_blinded = false
var darkness_level = 0.0  # 0 = full light, 1 = complete darkness

# Smell variables 
var can_smell = true
var smell_range = PERCEPTION_RANGE * 0.7

# System references
var audio_manager = null
var parent_entity = null
var world = null
var chat_ui = null  # Reference to the chat UI

# Signal for external systems to subscribe to
signal message_displayed(message, category)
signal sound_perceived(sound_name, position, emitter)
signal vision_changed(new_range)
signal smell_detected(smell_type, position, intensity)
signal entity_registered(entity)
signal entity_unregistered(entity)

func _ready():
	# Get parent entity
	parent_entity = get_parent()
	
	# Try to find world reference
	world = get_node_or_null("/root/World")
	if !world:
		var root = get_tree().root
		world = root.find_child("World", true, false)
	
	# Find audio manager
	audio_manager = get_node_or_null("/root/AudioManager")
	if !audio_manager:
		# Try to find by name
		var root = get_tree().root
		audio_manager = root.find_child("AudioManager", true, false)
	
	# Find chat UI - try multiple methods
	find_chat_ui()
	
	print("SensorySystem: Initialized for ", parent_entity.name if parent_entity else "unknown entity")

func _process(delta):
	# Process sound cooldowns
	_process_sound_cooldowns(delta)
	
	# Process entity awareness updates
	_process_entity_awareness()

# Find and connect to chat UI system
func find_chat_ui():
	# Try to find it in the scene tree
	chat_ui = get_node_or_null("/root/EnhancedChatUI")
	
	if !chat_ui:
		# Try to find it by class in the entire scene
		var potential_chat_uis = get_tree().get_nodes_in_group("chat_ui")
		if potential_chat_uis.size() > 0:
			chat_ui = potential_chat_uis[0]
	
	if !chat_ui:
		# Last resort - look for any node with "ChatUI" in the name
		var root = get_tree().root
		chat_ui = root.find_child("*ChatUI*", true, false)
	
	# If we found chat UI, connect signals
	if chat_ui:
		print("SensorySystem: Connected to chat UI")
		
		# Connect our message signal to chat
		if !self.is_connected("message_displayed", Callable(self, "_on_message_displayed")):
			self.connect("message_displayed", Callable(self, "_on_message_displayed"))
	else:
		print("SensorySystem: No chat UI found")

# Register an entity with the sensory system
func register_entity(entity):
	# Skip if already registered
	if entity.get_instance_id() in registered_entities:
		return
		
	# Add to our tracked entities
	registered_entities[entity.get_instance_id()] = entity
	
	# Store initial position if available
	if "position" in entity:
		entity_positions[entity.get_instance_id()] = entity.position
	elif entity.has_method("position"):
		entity_positions[entity.get_instance_id()] = entity.position()
	
	# Store if this is our local player entity
	if entity == parent_entity:
		local_entity = entity
	
	# Store initial state
	entity_states[entity.get_instance_id()] = {
		"last_seen": Time.get_ticks_msec() * 0.001,
		"is_visible": true,
		"last_position": entity_positions.get(entity.get_instance_id(), Vector2.ZERO),
		"last_sound": 0,
		"name": entity.entity_name if "entity_name" in entity else entity.name
	}
	
	# Emit signal
	emit_signal("entity_registered", entity)
	
	print("SensorySystem: Registered entity: ", entity.name)

# Unregister an entity
func unregister_entity(entity):
	var id = entity.get_instance_id()
	
	if registered_entities.has(id):
		registered_entities.erase(id)
		entity_positions.erase(id)
		entity_states.erase(id)
		
		# Emit signal
		emit_signal("entity_unregistered", entity)
		
		print("SensorySystem: Unregistered entity: ", entity.name)

# Update entity position
func update_entity_position(entity, position):
	if entity.get_instance_id() in registered_entities:
		entity_positions[entity.get_instance_id()] = position
		
		# Update last seen time
		entity_states[entity.get_instance_id()].last_seen = Time.get_ticks_msec() * 0.001
		entity_states[entity.get_instance_id()].last_position = position

# Process entity awareness updates
func _process_entity_awareness():
	# Skip if no local entity
	if !local_entity:
		return
		
	# Get local entity position
	var local_pos = Vector2.ZERO
	if "position" in local_entity:
		local_pos = local_entity.position
	elif local_entity.has_method("position"):
		local_pos = local_entity.position()
	
	# Check awareness of all registered entities
	for id in registered_entities:
		# Skip own entity
		if id == local_entity.get_instance_id():
			continue
			
		var entity = registered_entities[id]
		
		# Skip invalid entities
		if !is_instance_valid(entity):
			registered_entities.erase(id)
			entity_positions.erase(id)
			entity_states.erase(id)
			continue
		
		# Get entity position
		var entity_pos = Vector2.ZERO
		if id in entity_positions:
			entity_pos = entity_positions[id]
		elif "position" in entity:
			entity_pos = entity.position
			entity_positions[id] = entity_pos
		
		# Calculate distance
		var distance = local_pos.distance_to(entity_pos) / 32.0  # Convert to tiles
		
		# Update visibility based on distance and vision range
		var is_visible = distance <= vision_range and !is_blinded
		
		# Check for line of sight if world system supports it
		if is_visible and world and world.has_method("has_line_of_sight"):
			is_visible = world.has_line_of_sight(local_pos, entity_pos)
		
		# Update entity awareness state
		if is_visible:
			# Entity is visible
			if !entity_states[id].is_visible:
				# Entity just became visible
				process_visible_entity(entity, distance)
			
			entity_states[id].is_visible = true
			entity_states[id].last_seen = Time.get_ticks_msec() * 0.001
			entity_states[id].last_position = entity_pos
		else:
			# Entity is not visible
			entity_states[id].is_visible = false

# Process a visible entity
func process_visible_entity(entity, distance: float):
	# This method can be expanded for special reactions to seeing entities
	pass

# Display a message to the player via chat system
func display_message(message: String, category: String = "info"):
	# Skip empty messages
	if message.strip_edges().is_empty():
		return
		
	# Emit signal for subscribers
	emit_signal("message_displayed", message, category)
	
	# Print to console for debugging
	print("SensorySystem: ", message)

# Signal handler for message display - sends to chat if available
func _on_message_displayed(message, category):
	# Map our categories to chat categories
	var chat_category = "default"
	match category:
		"info": chat_category = "default"
		"warning": chat_category = "warning"
		"danger": chat_category = "alert"
		"important": chat_category = "system"
	
	# Forward to chat UI if available
	if chat_ui:
		# Check which method the chat UI has available
		if chat_ui.has_method("add_message"):
			chat_ui.add_message(message, chat_category)
		elif chat_ui.has_method("receive_message"):
			chat_ui.receive_message(message, chat_category, "System")

# Display a notification
func display_notification(message: String, category: String = "important"):
	# Display as a prominent message
	display_message("[b]" + message + "[/b]", category)
	
	# Play notification sound if we have audio
	if audio_manager:
		audio_manager.play_global_sound("notification", 0.7)

# Emit a sound in the world
func emit_sound(position: Vector2, z_level: int, sound_name: String, volume: float = 1.0, emitter = null):
	# Skip if no audio manager
	if !audio_manager:
		return
	
	# Use floor type for footsteps if available
	var subtype = "default"
	if sound_name == "footstep" and world and world.has_method("get_tile_data"):
		var tile_pos = Vector2i(int(position.x / 32), int(position.y / 32))
		var tile_data = world.get_tile_data(tile_pos, z_level)
		if tile_data and tile_data.has("floor_type"):
			subtype = tile_data.floor_type
	
	# Play the sound through audio manager
	audio_manager.play_positioned_sound(sound_name, position, volume, subtype)
	
	# Emit signal for other systems
	emit_signal("sound_perceived", sound_name, position, emitter)
	
	# Add unique ID for recent sounds to prevent too many duplicates
	var sound_id = sound_name + str(position) + str(Time.get_ticks_msec() / 500)  # Half-second precision
	recent_sounds.append(sound_id)
	
	# Limit recent sounds list
	if recent_sounds.size() > 20:
		recent_sounds.remove_at(0)
	
	# Update entity that made sound
	if emitter and emitter.get_instance_id() in entity_states:
		entity_states[emitter.get_instance_id()].last_sound = Time.get_ticks_msec() * 0.001

# Perceive a sound (heard by this entity)
func perceive_sound(sound_name: String, position: Vector2, volume: float, emitter = null):
	# Skip if on cooldown
	if sound_cooldowns.has(sound_name) and sound_cooldowns[sound_name] > 0:
		return
	
	# Apply perception filters
	if volume < 0.1:
		return  # Too quiet to hear
	
	# Check distance
	if parent_entity:
		var distance = parent_entity.position.distance_to(position) / 32.0  # Convert to tiles
		if distance > PERCEPTION_RANGE:
			return  # Too far to hear
	
	# Create a cooldown for this sound type to prevent spam
	var cooldown = 0.2  # Default cooldown
	match sound_name:
		"footstep":
			cooldown = 0.1  # Faster for footsteps
		"combat":
			cooldown = 0.3  # Slower for combat sounds
	
	sound_cooldowns[sound_name] = cooldown
	
	# Generate a message for the sound if it's significant
	if parent_entity and "is_local_player" in parent_entity and parent_entity.is_local_player:
		_generate_sound_message(sound_name, position, emitter)

# Process sound cooldowns
func _process_sound_cooldowns(delta):
	var to_remove = []
	
	for sound in sound_cooldowns:
		sound_cooldowns[sound] -= delta
		if sound_cooldowns[sound] <= 0:
			to_remove.append(sound)
	
	# Remove expired cooldowns
	for sound in to_remove:
		sound_cooldowns.erase(sound)

# Generate a message describing a sound
func _generate_sound_message(sound_name: String, position: Vector2, emitter = null):
	# Don't describe common ambient sounds
	if sound_name in ["footstep", "ambient"]:
		return
	
	# Get direction to sound
	var direction_text = "somewhere nearby"
	
	if parent_entity:
		var direction = position - parent_entity.position
		var angle = atan2(direction.y, direction.x)
		direction_text = _get_direction_text(angle)
	
	# Generate appropriate message based on sound type
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
		# Add more sound types as needed
	
	# Display the message if one was generated
	if !message.is_empty():
		display_message(message, category)

# Get text description of a direction based on angle
func _get_direction_text(angle: float) -> String:
	# Convert to degrees and normalize
	var degrees = rad_to_deg(angle)
	
	# Determine direction based on angle
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
	
	return "nearby"  # Fallback

# Set vision range
func set_vision_range(new_range: float):
	vision_range = new_range
	emit_signal("vision_changed", vision_range)

# Apply blinded effect
func set_blinded(is_blind: bool, duration: float = 0.0):
	is_blinded = is_blind
	
	# Apply vision changes
	if is_blinded:
		set_vision_range(1.0)  # Severely limited vision
		display_message("You can't see!", "warning")
		
		# Set timer to restore vision if duration provided
		if duration > 0:
			var timer = Timer.new()
			timer.wait_time = duration
			timer.one_shot = true
			add_child(timer)
			timer.timeout.connect(func(): set_blinded(false))
			timer.start()
	else:
		set_vision_range(PERCEPTION_RANGE)  # Restore normal vision
		display_message("Your vision returns.")

# Set muffled state for sounds
func set_muffled(is_muffled: bool, factor: float = 0.5):
	# Handle muffled hearing - can be implemented to affect sound perception
	pass

# Handle detecting a smell
func detect_smell(smell_type: String, position: Vector2, intensity: float = 1.0):
	if !can_smell:
		return
		
	# Check if within smell range
	if parent_entity:
		var distance = parent_entity.position.distance_to(position) / 32.0  # Convert to tiles
		if distance > smell_range:
			return  # Too far to smell
	
	# Generate a message for the smell
	if parent_entity and "is_local_player" in parent_entity and parent_entity.is_local_player:
		_generate_smell_message(smell_type, position, intensity)
	
	# Emit signal for other systems
	emit_signal("smell_detected", smell_type, position, intensity)

# Generate a message describing a smell
func _generate_smell_message(smell_type: String, position: Vector2, intensity: float):
	# Don't describe faint smells
	if intensity < 0.3:
		return
	
	# Get direction to smell
	var direction_text = "nearby"
	
	if parent_entity:
		var direction = position - parent_entity.position
		var angle = atan2(direction.y, direction.x)
		direction_text = _get_direction_text(angle)
	
	# Generate appropriate message based on smell type
	var message = ""
	var smell_intensity = ""
	var category = "info"
	
	# Determine intensity descriptor
	if intensity > 0.8:
		smell_intensity = "strong"
	elif intensity > 0.5:
		smell_intensity = "distinct"
	else:
		smell_intensity = "faint"
	
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
		# Add more smell types as needed
	
	# Display the message if one was generated
	if !message.is_empty():
		display_message(message, category)

# Apply darkness level (for lighting system integration)
func set_darkness_level(level: float):
	darkness_level = clamp(level, 0.0, 1.0)
	
	# Adjust vision based on darkness
	if darkness_level > 0.8:
		set_vision_range(PERCEPTION_RANGE * 0.3)  # Severely limited
	elif darkness_level > 0.5:
		set_vision_range(PERCEPTION_RANGE * 0.6)  # Moderately limited
	elif darkness_level > 0.2:
		set_vision_range(PERCEPTION_RANGE * 0.8)  # Slightly limited
	else:
		set_vision_range(PERCEPTION_RANGE)  # Normal vision
