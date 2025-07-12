extends Machinery
class_name Door

# === DOOR PROPERTIES ===
enum DoorOrientation { HORIZONTAL, VERTICAL }

var door_orientation: DoorOrientation = DoorOrientation.HORIZONTAL
var secondary_tile_pos: Vector2i
var is_multi_tile: bool = true  # Whether door spans multiple tiles
var is_open: bool = false
var auto_close: bool = true
var auto_close_delay: float = 5.0
var is_locked: bool = false
var requires_power_to_open: bool = false
var requires_power_to_close: bool = false
var open_sound_path: String = "res://Sound/machines/airlock.ogg"
var close_sound_path: String = "res://Sound/machines/airlock.oggg"
var deny_sound_path: String = "res://Sound/machines/buzz-two.ogg"

# === ANIMATION REFERENCES ===
@onready var animated_sprite: AnimatedSprite2D = $Door
@onready var auto_close_timer: Timer = $AutoCloseTimer

# === SIGNALS ===
signal door_opened(by_who)
signal door_closed(by_who)
signal door_locked(by_who)
signal door_unlocked(by_who)
signal door_denied(to_who)

func _ready():
	# Call parent ready function
	super()
	
	animated_sprite.play("Close")
	
	# Set door-specific properties
	obj_name = "door"
	obj_desc = "A door."
	entity_type = "door"
	entity_id = "door_" + str(get_instance_id())
	
	# Override entity_dense based on door state
	entity_dense = !is_open
	
	# Ensure we have auto-close timer
	if not auto_close_timer:
		auto_close_timer = Timer.new()
		auto_close_timer.one_shot = true
		auto_close_timer.wait_time = auto_close_delay
		auto_close_timer.name = "AutoCloseTimer"
		add_child(auto_close_timer)
	
	# Connect timer signal
	if not auto_close_timer.timeout.is_connected(_on_auto_close_timer_timeout):
		auto_close_timer.timeout.connect(_on_auto_close_timer_timeout)
	
	# Connect animation finished signal if available
	if animated_sprite and animated_sprite.has_signal("animation_finished"):
		if not animated_sprite.animation_finished.is_connected(_on_door_animation_finished):
			animated_sprite.animation_finished.connect(_on_door_animation_finished)
	
	# Add to necessary groups
	add_to_group("doors")
	add_to_group("clickable_entities")
	add_to_group("dense_entities")
	
	# Register with tile occupancy system
	_register_with_tile_occupancy()
	
	print("Door initialized at position ", position, " with entity_dense=", entity_dense)

# Set the door orientation and calculate secondary tile position
func set_orientation(orientation: DoorOrientation):
	door_orientation = orientation
	# Call register with tile occupancy to update the secondary tile position
	_register_with_tile_occupancy()

# Try to register with the tile occupancy system
func _register_with_tile_occupancy():
	# Find the world
	var world = get_node_or_null("/root/World")
	if not world:
		print("Door: Cannot find World node!")
		return
	
	# Find the tile occupancy system
	var tile_occupancy = world.get_node_or_null("TileOccupancySystem")
	if not tile_occupancy:
		tile_occupancy = world.get_node_or_null("ImprovedTileOccupancySystem")
	
	if not tile_occupancy:
		print("Door: Cannot find TileOccupancySystem!")
		return
	
	# Get our primary tile position
	var primary_tile_pos = world.get_tile_at(global_position)
	var z_level = 0  # Assuming z_level 0 by default
	
	# Determine secondary tile position based on orientation
	if is_multi_tile:
		if door_orientation == DoorOrientation.HORIZONTAL:
			secondary_tile_pos = Vector2i(primary_tile_pos.x + 1, primary_tile_pos.y)
		else: # VERTICAL
			secondary_tile_pos = Vector2i(primary_tile_pos.x, primary_tile_pos.y + 1)
	else:
		# For 1x1 doors, secondary tile is the same as primary
		secondary_tile_pos = primary_tile_pos
	
	# Register primary tile
	if tile_occupancy.has_method("register_entity_at_tile"):
		var success = tile_occupancy.register_entity_at_tile(self, primary_tile_pos, z_level)
		print("Door: Registered primary tile with TileOccupancySystem at ", primary_tile_pos, ", z=", z_level, " - Success: ", success)
	
	# Register secondary tile with the same entity (only if multi-tile)
	if is_multi_tile and tile_occupancy.has_method("register_entity_at_tile"):
		var success = tile_occupancy.register_entity_at_tile(self, secondary_tile_pos, z_level)
		print("Door: Registered secondary tile with TileOccupancySystem at ", secondary_tile_pos, ", z=", z_level, " - Success: ", success)

# === DOOR STATE METHODS ===
func toggle_door(user = null) -> bool:
	if is_open:
		return close_door(user)
	else:
		return open_door(user)

func open_door(user = null) -> bool:
	# Checks if door can be opened
	if not can_open(user):
		# Play deny sound
		play_sound(deny_sound_path)
		door_denied.emit(user)
		return false
	
	print("Door: Opening door...")
	
	# Update door state
	is_open = true
	
	# CRITICAL: Update entity property for grid collision system
	entity_dense = false
	
	# Notify the tile occupancy system about the change
	_update_tile_occupancy_dense_state()
	
	# Play animation
	if animated_sprite and animated_sprite.sprite_frames.has_animation("Open"):
		animated_sprite.play("Open")
	
	# Play sound
	play_sound(open_sound_path)
	
	# Emit signal
	door_opened.emit(user)
	
	# Start auto-close timer if enabled
	if auto_close:
		auto_close_timer.start()
	
	print("Door: Opened! entity_dense=", entity_dense)
	return true

func close_door(user = null) -> bool:
	# Check if door can be closed
	if not can_close(user):
		# Play deny sound
		play_sound(deny_sound_path)
		door_denied.emit(user)
		return false
	
	print("Door: Attempting to close door...")
	
	# Check if something is blocking the door
	if is_entity_in_doorway():
		print("Door: Cannot close - entity in doorway")
		# Can't close, entity in the way
		if auto_close:
			# Try again later
			auto_close_timer.start()
		return false
	
	# Update door state
	is_open = false
	
	# CRITICAL: Update entity property for grid collision system
	entity_dense = true
	
	# Notify the tile occupancy system about the change
	_update_tile_occupancy_dense_state()
	
	# Play animation
	if animated_sprite and animated_sprite.sprite_frames.has_animation("Close"):
		animated_sprite.play("Close")
	
	# Play sound
	play_sound(close_sound_path)
	
	# Emit signal
	door_closed.emit(user)
	
	print("Door: Closed! entity_dense=", entity_dense)
	return true

# Update the tile occupancy system when density changes
func _update_tile_occupancy_dense_state():
	# Find the world
	var world = get_node_or_null("/root/World")
	if not world:
		return
	
	# Find the tile occupancy system
	var tile_occupancy = world.get_node_or_null("TileOccupancySystem")
	if not tile_occupancy:
		tile_occupancy = world.get_node_or_null("ImprovedTileOccupancySystem")
	
	if not tile_occupancy:
		return
	
	# Get our primary tile position
	var primary_tile_pos = world.get_tile_at(global_position)
	var z_level = 0  # Assuming z_level 0 by default
	
	# Improved approach - directly update the entity property without manipulating global position
	if tile_occupancy.has_method("update_entity_property"):
		# Update primary tile
		tile_occupancy.update_entity_property(self, "dense", entity_dense)
		tile_occupancy.update_entity_property(self, "entity_dense", entity_dense)
		
		# Force the system to recognize the change
		if tile_occupancy.has_method("update_entity_position"):
			tile_occupancy.update_entity_position(self)
		
		# Add door state to the tile data in the World
		if world.has_method("set_door_state"):
			world.set_door_state(primary_tile_pos, z_level, !is_open)
			
			# Also update secondary tile if multi-tile
			if is_multi_tile:
				world.set_door_state(secondary_tile_pos, z_level, !is_open)
		
		# If multi-tile, update secondary tile properties
		if is_multi_tile:
			# New approach: use the door_set_secondary_tile_property method if available
			if tile_occupancy.has_method("door_set_secondary_tile_property"):
				tile_occupancy.door_set_secondary_tile_property(self, secondary_tile_pos, z_level, "entity_dense", entity_dense)
				tile_occupancy.door_set_secondary_tile_property(self, secondary_tile_pos, z_level, "dense", entity_dense)
			else:
				# Fallback to direct method - this might have issues but it's better than nothing
				var entities_at_secondary = tile_occupancy.get_entities_at(secondary_tile_pos, z_level)
				if self in entities_at_secondary:
					tile_occupancy.update_entity_property(self, "dense", entity_dense)
					tile_occupancy.update_entity_property(self, "entity_dense", entity_dense)
	
	# Ensure the door state is correctly communicated to all systems
	if world.has_method("emit_door_state_changed"):
		world.emit_door_state_changed(primary_tile_pos, z_level, is_open)
		if is_multi_tile:
			world.emit_door_state_changed(secondary_tile_pos, z_level, is_open)

func lock_door(user = null) -> bool:
	if is_locked:
		return true
		
	is_locked = true
	door_locked.emit(user)
	
	return true

func unlock_door(user = null) -> bool:
	if not is_locked:
		return true
		
	is_locked = false
	door_unlocked.emit(user)
	
	return true

# === STATE CHECKS ===
func can_open(user = null) -> bool:
	# Already open
	if is_open:
		return false
	
	# Locked
	if is_locked:
		return false
	
	# Power check
	if requires_power_to_open and requires_power and not is_powered:
		return false
	
	# Broken
	if obj_integrity <= integrity_failure:
		return false
	
	return true

func can_close(user = null) -> bool:
	# Already closed
	if not is_open:
		return false
	
	# Power check for closing
	if requires_power_to_close and requires_power and not is_powered:
		return false
	
	# Broken
	if obj_integrity <= integrity_failure:
		return false
	
	return true

# === INTERACTION HANDLERS ===
# Override interact method
func interact(user) -> bool:
	print("Door: Interact called by ", user.name if "name" in user else "Unknown")
	
	# For doors, just toggle open/close
	toggle_door(user)
	
	# Call parent interact without using its activation logic
	interacted_with.emit(user)
	return true

# === ANIMATION HANDLERS ===
func _on_door_animation_finished():
	if not animated_sprite:
		return
		
	var anim_name = animated_sprite.animation
	
	# Handle animation completion
	if anim_name == "Open":
		# Ensure door is fully opened
		print("Door: Open animation finished")
		is_open = true
		entity_dense = false
		_update_tile_occupancy_dense_state()
	elif anim_name == "Close":
		# Ensure door is fully closed
		print("Door: Close animation finished")
		is_open = false
		entity_dense = true
		_update_tile_occupancy_dense_state()

# === AUTO-CLOSE TIMER ===
func _on_auto_close_timer_timeout():
	# Try to close the door
	if is_open:
		close_door(null)

# === UTILITY FUNCTIONS ===
func play_sound(sound_path: String):
	if not sound_path:
		return
		
	var audio_player = AudioStreamPlayer2D.new()
	add_child(audio_player)
	
	# Try to load the sound
	var sound = load(sound_path) if ResourceLoader.exists(sound_path) else null
	if sound:
		audio_player.stream = sound
		audio_player.play()
		await audio_player.finished
		audio_player.queue_free()

# === CLICK SYSTEM INTEGRATION ===
# Called by your ClickSystem
func ClickOn(clicker):
	print("Door: ClickOn called by ", clicker.name if "name" in clicker else "Unknown")
	return interact(clicker)

# === GRID MOVEMENT INTEGRATION ===
# This is called directly by the GridMovementController
func check_collision(_entity, _direction) -> bool:
	# For doors, explicitly block if closed
	return !is_open

# Check for entities blocking the door
func is_entity_in_doorway() -> bool:
	# Find the world
	var world = get_parent().get_parent()
	if not world:
		return false
	
	# Get tile occupancy system if available
	var tile_occupancy = world.get_node_or_null("TileOccupancySystem")
	if not tile_occupancy:
		tile_occupancy = world.get_node_or_null("ImprovedTileOccupancySystem")
	
	if not tile_occupancy:
		return false
	
	# Get our primary tile position
	var primary_tile_pos = world.get_tile_at(global_position)
	var z_level = 0  # Assuming z_level 0 by default
	
	# Check primary tile for blocking entities
	var primary_blocked = _is_tile_blocked(tile_occupancy, primary_tile_pos, z_level)
	
	# Check secondary tile for blocking entities (if multi-tile)
	var secondary_blocked = false
	if is_multi_tile:
		secondary_blocked = _is_tile_blocked(tile_occupancy, secondary_tile_pos, z_level)
	
	return primary_blocked || secondary_blocked

func _is_tile_blocked(tile_occupancy, tile_pos, z_level) -> bool:
	# Get entities at this tile position (excluding this door)
	var entities
	if tile_occupancy.has_method("get_entities_at"):
		entities = tile_occupancy.get_entities_at(tile_pos, z_level)
	else:
		return false
	
	# Check if any entity is dense
	for entity in entities:
		if entity != self and is_instance_valid(entity):
			# Check if it's a player or character that can be blocked
			if ("entity_type" in entity and 
				(entity.entity_type == "character" or entity.entity_type == "player")):
				print("Door: Entity blocking doorway: ", entity.name if "name" in entity else "Unknown")
				return true
			
			# General dense entity check
			if "entity_dense" in entity and entity.entity_dense:
				print("Door: Entity blocking doorway: ", entity.name if "name" in entity else "Unknown")
				return true
	
	return false

# Handle being bumped by characters (from grid movement)
func on_bump(bumper) -> bool:
	print("Door: on_bump called by ", bumper.name if "name" in bumper else "Unknown")
	
	# If door is closed, try to open it when bumped
	if not is_open:
		# Check if bumper is a character or player
		if (bumper is GridMovementController or 
			bumper.is_in_group("player") or 
			("entity_type" in bumper and bumper.entity_type == "character")):
			
			# Try to open the door
			open_door(bumper)
			return true  # Block movement this time, but the door should be open for next move
		else:
			# For non-character entities, just block
			return true
	
	# Door is open, allow passage
	return false

# === OVERRIDE EXAMINE ===
func examine(examiner) -> String:
	var examine_text = obj_desc
	
	# Add door state
	if is_open:
		examine_text += "\nThe door is open."
	else:
		examine_text += "\nThe door is closed."
	
	# Add lock state
	if is_locked:
		examine_text += "\nIt appears to be locked."
	
	# Add power state if relevant
	if requires_power and (requires_power_to_open or requires_power_to_close):
		if is_powered:
			examine_text += "\nThe power indicator is lit."
		else:
			examine_text += "\nThe power indicator is off."
	
	# Add damage info
	if obj_integrity < max_integrity:
		var damage_percent = obj_integrity / max_integrity * 100
		if damage_percent < 25:
			examine_text += "\nIt looks severely damaged!"
		elif damage_percent < 50:
			examine_text += "\nIt looks badly damaged."
		elif damage_percent < 75:
			examine_text += "\nIt looks damaged."
		elif damage_percent < 95:
			examine_text += "\nIt has a few scratches."
	
	return examine_text
