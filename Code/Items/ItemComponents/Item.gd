extends BaseObject
class_name Item

# Signals
signal is_equipped(user, slot)
signal is_unequipped(user, slot)
signal used(user)
signal is_thrown(user, target)
signal dropped(user)
signal is_picked_up(user)
signal throw_started(thrower, initial_direction, force)
signal throw_ended(final_position)
# New: Signals for persistent effect integration
signal effect_update(effects_changed)

# Item flags
enum ItemFlags {
	IN_INVENTORY = 1,    # Item is in someone's inventory
	WIELDED = 2,         # Item is being wielded (for two-handed items)
	DELONDROP = 4,       # Item will be deleted when dropped
	NOBLUDGEON = 8,      # Item can't be used to attack
	ABSTRACT = 16,       # Item is abstract (can't be interacted with)
	IS_DEPLOYED = 32,    # Item is deployed (as a structure/machine)
	CAN_BUMP_ATTACK = 64 # Item can be used to attack by bumping
}

# Valid equipment slots (bitmask flags)
enum Slots {
	NONE = 0,
	LEFT_HAND = 1,
	RIGHT_HAND = 2,
	BACKPACK = 4,
	BELT = 8,
	POCKET = 16,
	WEAR_SUIT = 32,
	WEAR_MASK = 64,
	HEAD = 128,
	SHOES = 256,
	GLOVES = 512,
	EARS = 1024,
	EYES = 2048,
	WEAR_ID = 4096
}

# Core item properties
var item_name: String = "item"
var w_class: int = 3              # Weight class (1-5, determines storage)

# Visual properties
var highlight_color: Color = Color(1.0, 1.0, 0.0, 0.3)  # Color when highlighted
var is_highlighted: bool = false  # Whether item is currently highlighted
var inv_hide_flags: int = 0       # Item hide flags (for visuals)

# Combat properties
@export var force: int = 0                # Melee damage
@export var sharp: bool = false           # Whether item cuts
@export var edge: bool = false            # Whether item can dismember
@export var attack_verb: Array = ["hits"] # Verbs used when attacking
@export var attack_speed: float = 1.1     # Attack speed (lower is faster)

# Inventory properties
var equip_slot_flags: int = Slots.LEFT_HAND | Slots.RIGHT_HAND  # Which slots this can be equipped to
var current_slot: int = 0         # Current equipped slot
var last_equipped_slot: int = 0   # Last slot it was equipped to (for quick-equipping)
var inventory_owner = null        # Reference to owner of this entity
var wielded: bool = false         # If item is wielded (two-handed)
var item_flags: int = 0           # Current item flags

# Persistent effect properties
var has_persistent_effects: bool = false  # Whether this item has effects that persist in inventory
var active_effects = {}                   # Dictionary of active effects
var effect_proxy = null                  # Reference to effect proxy if created

# Equipment delays
var equip_delay: float = 0.0      # Time in seconds to equip
var unequip_delay: float = 0.0    # Time to unequip
var pickup_delay: float = 0.0     # Time to pick up from ground

# Throw properties
var throwable: bool = true
var throw_range_multiplier: float = 1.0  # Multiplier for throw range
var throw_accuracy: float = 1.0   # How accurate this item is when thrown (1.0 = perfect)
var throw_sound: AudioStream = null  # Sound to play when thrown
var throw_sounds: Array = []      # Sounds to play when thrown

# Throw state - used during throwing
var throw_start_pos: Vector2 = Vector2.ZERO
var throw_target_pos: Vector2 = Vector2.ZERO
var throw_target = null           # Target for guided throws
var throw_in_progress: bool = false  # If currently being thrown
var is_flying: bool = false
var flight_time: float = 0.0      # Current time in flight
var flight_duration: float = 0.0  # Total flight duration

# Tool properties
@export var tool_behaviour: String = ""   # What tool this functions as
@export var toolspeed: float = 1.0        # Tool speed multiplier (lower is faster)
var usesound = null               # Sound when used as tool

# Deployable properties
var deploy_type: String = ""      # Type to deploy into
var deploy_time: float = 0.0      # Time to deploy
var deployed: bool = false        # If currently deployed

# Sound effects
var drop_sound: AudioStream = null   # Sound to play when dropped
var pickup_sound: AudioStream = null # Sound to play when picked up

# Visual throw trail effect
var throw_trail_enabled: bool = false  # Whether to show trail when thrown
var throw_trail_color: Color = Color(1.0, 1.0, 1.0, 0.5)  # Color of throw trail
var throw_trail_points: int = 10  # Number of points in throw trail
var throw_trail = null            # Node for the throw trail

# Actions (abilities this item grants)
var actions: Array = []

# Initialization
func _init():
	super._init()  # Call parent _init
	obj_flags |= ObjectFlags.CAN_BE_HIT  # Items can be hit by default
	entity_type = "item"
	pickupable = true
	# Check for persistent effects
	_check_persistent_effects()

# Setup when ready
func _ready():
	super._ready()  # Call parent _ready
	
	# Register with tile occupancy system
	_register_with_tile_system()
	
	# Setup by type
	if sharp:
		add_to_group("sharp_objects")
	
	if deploy_type:
		add_to_group("deployable_items")
	
	# Set up throw trail if enabled
	if throw_trail_enabled:
		setup_throw_trail()
	
	# Auto create InteractionArea if it doesn't exist
	_ensure_interaction_area()
	
	# Make sure we're in the right groups
	if not is_in_group("items"):
		add_to_group("items")
	if not is_in_group("clickable_entities"):
		add_to_group("clickable_entities")
		
	# Ensure equip_slot_flags includes hand slots if pickupable
	_ensure_valid_equip_slots()
	
	# Configure persistence for effects
	_check_persistent_effects()

# Add signal connection to handle being added to scene
func _enter_tree():
	# Add to clickable group for detection
	if not is_in_group("clickable_entities"):
		add_to_group("clickable_entities")
	if not is_in_group("items"):
		add_to_group("items")

# Handle removal from scene
func _exit_tree():
	# Unregister from tile system
	var world_node = get_node_or_null("/root/World")
	if world_node and "tile_occupancy_system" in world_node and world_node.tile_occupancy_system:
		var tile_system = world_node.tile_occupancy_system
		if tile_system.has_method("unregister_entity"):
			tile_system.unregister_entity(self)
		elif tile_system.has_method("remove_entity"):
			tile_system.remove_entity(self)

# Process function for throw animation and effects
func _physics_process(delta: float) -> void:
	# Process throw motion
	if is_flying and !landed:
		process_throw(delta)
	
	# Show throw trail if enabled
	if throw_in_progress and throw_trail_enabled and throw_trail:
		update_throw_trail()
	
	# Update any continuous effects
	if has_persistent_effects and has_flag(item_flags, ItemFlags.IN_INVENTORY):
		update_effects(delta)

# NEW: Check for persistent effects to determine if we need special handling
func _check_persistent_effects():
	# Check if we have any nodes that should persist in inventory
	var persistent_nodes = false
	
	# PointLight2D should persist
	if has_node("PointLight2D"):
		persistent_nodes = true
	
	# Particles should persist
	if has_node("GPUParticles2D") or has_node("CPUParticles2D"):
		persistent_nodes = true
	
	# Audio should persist
	if has_node("AudioStreamPlayer2D"):
		persistent_nodes = true
	
	# Override with property if set
	has_persistent_effects = persistent_nodes

# NEW: Method to update continuous effects, called during physics_process
func update_effects(delta, proxy = null):
	# Process any nodes that need continuous updates
	var effects_changed = false
	
	# Handle light effects
	var light = get_node_or_null("PointLight2D")
	if light:
		# Do any processing needed for light effects
		# For example, light flicker effect
		if "flicker" in light and light.flicker:
			light.energy = light.base_energy + randf_range(-0.1, 0.1)
			effects_changed = true
	
	# Handle particle effects
	var particles = get_node_or_null("GPUParticles2D")
	if particles:
		# Keep track of emission state changes
		if "last_emitting" in self and particles.emitting != self.last_emitting:
			effects_changed = true
			self.last_emitting = particles.emitting
	
	# Signal changes if needed
	if effects_changed:
		emit_signal("effect_update", self)

# NEW: Allow items to set up their effect proxy
func setup_effect_proxy(proxy, slot):
	# Store the proxy reference
	effect_proxy = proxy
	
	# Default implementation - override in specific items
	pass

# NEW: Allow items to update their effect proxy
func update_effect_proxy(proxy, slot):
	# Default implementation - override in specific items
	pass

# Register with tile occupancy system
func _register_with_tile_system():
	# Find the world node
	var world_node = get_node_or_null("/root/World")
	if not world_node:
		# Try other common world node names
		world_node = get_node_or_null("/root/GameWorld")
		if not world_node:
			world_node = get_node_or_null("/root/Level")
	
	# Check if world has tile occupancy system
	if world_node and "tile_occupancy_system" in world_node and world_node.tile_occupancy_system:
		var tile_system = world_node.tile_occupancy_system
		
		# Get current tile position
		var tile_pos
		if tile_system.has_method("world_to_tile"):
			tile_pos = tile_system.world_to_tile(global_position)
		else:
			# Fallback calculation
			var tile_size = 32  # Default tile size
			if "TILE_SIZE" in world_node:
				tile_size = world_node.TILE_SIZE
			tile_pos = Vector2i(int(global_position.x / tile_size), int(global_position.y / tile_size))
		
		# Get current z level (default to 0)
		var z_level = 0
		
		# Register with tile system
		if tile_system.has_method("register_entity"):
			tile_system.register_entity(self, tile_pos, z_level)
		elif tile_system.has_method("add_entity"):
			tile_system.add_entity(self, tile_pos, z_level)

# Create InteractionArea if it doesn't exist
func _ensure_interaction_area():
	# Check if we already have an InteractionArea
	var interaction_area = get_node_or_null("InteractionArea")
	
	if interaction_area == null:
		# Create a new InteractionArea
		interaction_area = Area2D.new()
		interaction_area.name = "InteractionArea"
		
		# Create a collision shape for the interaction area
		var collision_shape = CollisionShape2D.new()
		collision_shape.name = "CollisionShape2D"
		
		# Try to determine appropriate shape
		var shape = CircleShape2D.new()
		
		# Default size for interaction
		shape.radius = 16.0  # Default size
		
		# Get item sprite size if possible to better fit the interaction area
		var sprite = get_node_or_null("Sprite2D")
		if sprite and sprite.texture:
			var texture_size = sprite.texture.get_size()
			var area_radius = max(texture_size.x, texture_size.y) / 2.0
			shape.radius = area_radius * 1.2  # Slightly larger than the sprite
		
		# Apply the shape to the collision shape
		collision_shape.shape = shape
		
		# Add the collision shape to the interaction area
		interaction_area.add_child(collision_shape)
		
		# Set collision layer and mask for interaction
		interaction_area.collision_layer = 8  # Interaction layer (adjust as needed)
		interaction_area.collision_mask = 0   # Doesn't need to detect anything
		
		# Add to the item
		add_child(interaction_area)
		
		# Add to the interaction_areas group for easy detection
		interaction_area.add_to_group("interaction_areas")

# Ensure equip_slot_flags includes hand slots if pickupable
func _ensure_valid_equip_slots():
	# If the item is pickupable, make sure it has proper slot flags
	if pickupable:
		if equip_slot_flags == 0:
			equip_slot_flags = Slots.LEFT_HAND | Slots.RIGHT_HAND

# Update appearance (visual state)
func update_appearance() -> void:
	super.update_appearance()  # Call parent method
	
	# Update based on wielded state
	if has_flag(item_flags, ItemFlags.WIELDED):
		# Change sprite to wielded state
		# You'd implement sprite changing here
		pass

#
# FLAG HANDLING
#

# Check if a flag is set
func has_flag(flags, flag):
	return (flags & flag) != 0

# Set or clear a flag
func set_flag(flags_var: String, flag: int, enabled: bool = true) -> void:
	if enabled:
		self[flags_var] |= flag
	else:
		self[flags_var] &= ~flag

#
# INVENTORY FUNCTIONS
#

# Handle being equipped to an entity
func equipped(user, slot: int):
	if inventory_owner and inventory_owner != user:
		handle_drop(inventory_owner)
	
	inventory_owner = user
	current_slot = slot
	last_equipped_slot = slot
	set_flag("item_flags", ItemFlags.IN_INVENTORY, true)
	
	# Set item visibility based on persistent effects
	if has_persistent_effects:
		# Item should stay active for effects but be invisible
		visible = false
		
		# Make sure to update any active effects
		emit_signal("effect_update", self)
	else:
		# Standard invisibility for non-effect items
		visible = false
		
	# Match item color to default to prevent tint issues
	modulate = Color(1, 1, 1, 1)
	
	# Apply any effects to the user
	apply_to_user(user)
	
	# Ensure the item is a child of the user
	if get_parent() != user:
		if get_parent():
			get_parent().remove_child(self)
		user.add_child(self)
	
	# Tell the world this item is now in an inventory
	var world = user.get_parent()
	if world and world.has_method("item_equipped"):
		world.item_equipped(self, user, slot)
	
	emit_signal("is_equipped", user, slot)

# Handle being unequipped from a mob
func unequipped(user, slot: int):
	if inventory_owner != user:
		return
		
	remove_from_user(user)
	
	inventory_owner = null
	current_slot = 0
	set_flag("item_flags", ItemFlags.IN_INVENTORY, false)
	
	# Clean up any effect proxy connections
	if has_persistent_effects and effect_proxy:
		effect_proxy = null
	
	emit_signal("is_unequipped", user, slot)

# Apply effects to user when equipped
func apply_to_user(user):
	# To be overridden by subclasses
	pass

# Remove effects from user when unequipped
func remove_from_user(user):
	# To be overridden by subclasses
	pass

# Check if the item can be equipped to a specific slot
func can_equip(user, slot: int) -> bool:
	if slot == 0:
		return false
	
	# Check if this item can be equipped to this slot
	if (equip_slot_flags & slot) == 0:
		return false
	
	# Check if user already has something in this slot
	if "get_item_in_slot" in user:
		var existing_item = user.get_item_in_slot(slot)
		if existing_item:
			return false
	
	return true

# Handle being picked up
func picked_up(user):
	# Ensure we exist in the scene tree
	if !is_inside_tree():
		print("Warning: Item.picked_up called but item not in scene tree!")
	
	# Ensure this item is now invisible
	visible = false
	
	# Play pickup sound
	if pickup_sound:
		play_audio(pickup_sound, -5)
	else:
		# Generic pickup sound
		var audio_manager = get_node_or_null("/root/AudioManager")
		if audio_manager:
			audio_manager.play_positioned_sound("pickup", global_position, 0.4)
	
	# Don't animate pickup if invisible
	if visible:
		# Animate pickup (raise and fade)
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(self, "modulate:a", 0.0, 0.2)
	
	emit_signal("is_picked_up", user)

# Handle being dropped
func handle_drop(user):
	if has_flag(item_flags, ItemFlags.DELONDROP):
		queue_free()
		return
	
	if inventory_owner == user:
		unequipped(user, current_slot)
	
	# Apply drop direction
	var drop_direction = Vector2.DOWN
	var drop_strength = 30.0
	
	# Check if user is moving, add horizontal velocity
	if "velocity" in user and user.velocity.length() > 0:
		drop_direction += Vector2(user.velocity.x, 0).normalized() * 0.5
		drop_strength *= (1.0 + user.velocity.length() / 200.0)
	
	# Ensure item is positioned correctly in world space
	global_position = user.global_position + drop_direction * 16.0
	
	# Ensure item is visible when dropped
	visible = true
	
	# Play drop sound
	if drop_sound:
		play_audio(drop_sound, -10)
	else:
		# Generic drop sound
		var audio_manager = get_node_or_null("/root/AudioManager")
		if audio_manager:
			audio_manager.play_positioned_sound("drop", global_position, 0.3)
	
	emit_signal("dropped", user)
	
	# Reset wielded status if dropped
	if has_flag(item_flags, ItemFlags.WIELDED):
		set_flag("item_flags", ItemFlags.WIELDED, false)
		wielded = false

# Play an audio clip at this item's position
func play_audio(stream: AudioStream, volume_db: float = 0.0) -> void:
	# Check if we already have an audio player
	var audio_player = get_node_or_null("AudioPlayer")
	
	# Create one if needed
	if !audio_player:
		audio_player = AudioStreamPlayer2D.new()
		audio_player.name = "AudioPlayer"
		add_child(audio_player)
	
	# Set up the audio
	audio_player.volume_db = volume_db
	audio_player.pitch_scale = randf_range(0.95, 1.05)  # Slight randomization
	audio_player.play()

# Remove from inventory
func _remove_from_inventory():
	# If we have an inventory owner
	if inventory_owner != null:
		# Try different approaches to remove from inventory
		var inventory_system = inventory_owner.get_node_or_null("InventorySystem")
		if inventory_system:
			# Try to find which slot we're in
			var slot = 0
			if inventory_system.has_method("get_item_slot"):
				slot = inventory_system.get_item_slot(self)
			
			# If slot is valid, unequip
			if slot != 0 and inventory_system.has_method("unequip_item"):
				inventory_system.unequip_item(slot)
			# Otherwise try direct removal
			elif inventory_system.has_method("remove_item"):
				inventory_system.remove_item(self)
		
		# Clear inventory state
		inventory_owner = null
		current_slot = 0
		set_flag("item_flags", ItemFlags.IN_INVENTORY, false)

# Verify and fix inventory state
func verify_inventory_state():
	# If item has inventory owner but not IN_INVENTORY flag
	if inventory_owner != null and !has_flag(item_flags, ItemFlags.IN_INVENTORY):
		set_flag("item_flags", ItemFlags.IN_INVENTORY, true)
	
	# If item has IN_INVENTORY flag but no inventory owner
	if inventory_owner == null and has_flag(item_flags, ItemFlags.IN_INVENTORY):
		set_flag("item_flags", ItemFlags.IN_INVENTORY, false)

#
# INTERACTION FUNCTIONS
#

# Enhance the use method to work better when inventory-owner uses it
func use(user):
	# First check if the user and inventory owner match
	if inventory_owner != null and inventory_owner != user:
		return false

	# Emit used signal 
	emit_signal("used", user)
	
	# Notify about effect changes
	emit_signal("effect_update", self)
	
	# Success by default, subclasses will override with specific behavior
	return true

# Handle interaction
func interact(user) -> bool:
	# Call parent method first
	super.interact(user)
	
	# If the item is on the ground (not in inventory), try to pick it up
	if pickupable and not has_flag(item_flags, ItemFlags.IN_INVENTORY):
		# Check if user has inventory system
		if "inventory_system" in user and user.inventory_system:
			user.inventory_system.pick_up_item(self)
			return true
		# Fallback to click system if available
		elif user.has_method("pickup_item"):
			user.pickup_item(self)
			return true
	
	return false

# Set highlight state for pickupable items
func set_highlighted(highlight: bool):
	if is_highlighted == highlight:
		return
		
	is_highlighted = highlight
	
	# Apply visual highlighting
	if is_highlighted:
		# Add highlight effect
		var sprite = get_node_or_null("Sprite2D")
		if sprite:
			# Create a highlight shader effect
			var material = ShaderMaterial.new()
			var shader = load("res://Shaders/outline.gdshader")
			if shader:
				material.shader = shader
				material.set_shader_parameter("outline_color", highlight_color)
				material.set_shader_parameter("outline_width", 2.0)
				sprite.material = material
			else:
				# Fallback to simple modulate
				sprite.modulate = Color(1.2, 1.2, 0.8)
	else:
		# Remove highlight effect
		var sprite = get_node_or_null("Sprite2D")
		if sprite:
			sprite.material = null
			sprite.modulate = Color(1.0, 1.0, 1.0)

# Self-attack handling (when used on oneself)
func attack_self(user):
	emit_signal("used", user)
	emit_signal("effect_update", self)
	return false  # Return true if handled

# Special interaction when clicking on something with this item
func afterattack(target, user, proximity: bool, params: Dictionary = {}):
	# To be overridden by subclasses
	return false

# Check if this item can interact with a target
func can_interact_with(target, user) -> bool:
	# Base interaction check
	return can_interact(user)

# Check if the item can be used
func can_use() -> bool:
	# Default implementation
	return true

#
# ATTACK FUNCTIONS
#

# Attack handling (when used as a weapon)
func attack(target, user):
	if has_flag(item_flags, ItemFlags.NOBLUDGEON):
		return false
	
	# Play attack sound
	if "hit_sound" in self and hit_sound:
		play_audio(hit_sound)
		
	# Get attack damage
	var damage = force
	
	# Apply wielded bonus if applicable
	if has_flag(item_flags, ItemFlags.WIELDED) and "force_wielded" in self:
		damage = self.force_wielded
	
	# Apply damage to target
	if "take_damage" in target:
		target.take_damage(damage, "brute", "melee", true, 0.0, user)
		
	# Show attack message
	if "visible_message" in user:
		var verb = attack_verb[randi() % attack_verb.size()] if attack_verb.size() > 0 else "hits"
		user.visible_message("%s %s %s with %s" % [user.name, verb, target.name, obj_name])
	
	# Emit effect update for anything that might be affected by attacking
	emit_signal("effect_update", self)
	
	return true

# Toggle wielded state (for two-handed items)
func toggle_wielded(user) -> bool:
	if not can_be_wielded():
		return false
	
	wielded = !wielded
	set_flag("item_flags", ItemFlags.WIELDED, wielded)
	
	if wielded:
		if "visible_message" in user:
			user.visible_message("%s grips %s with both hands." % [user.name, obj_name])
	else:
		if "visible_message" in user:
			user.visible_message("%s loosens their grip on %s." % [user.name, obj_name])
	
	update_appearance()
	return true

# Check if the item can be wielded
func can_be_wielded() -> bool:
	# Override in subclasses for items that can be wielded
	return false

#
# THROW FUNCTIONS - STRAIGHT LINE IMPLEMENTATION
#

# Setup throw trail
func setup_throw_trail():
	throw_trail = Line2D.new()
	throw_trail.name = "ThrowTrail"
	throw_trail.width = 2.0
	throw_trail.default_color = throw_trail_color
	throw_trail.visible = false
	add_child(throw_trail)

# Update throw trail during physics processing
func update_throw_trail():
	if throw_trail and throw_trail.visible:
		# Add current position to the trail
		throw_trail.add_point(Vector2.ZERO)  # Local coordinates
		
		# Limit number of points
		while throw_trail.get_point_count() > throw_trail_points:
			throw_trail.remove_point(0)
		
		# Fade the trail over time
		for i in range(throw_trail.get_point_count()):
			var point_color = throw_trail_color
			point_color.a = throw_trail_color.a * (float(i) / throw_trail_points)
			throw_trail.set_point_color(i, point_color)

# Throw the item
func throw(thrower, direction: Vector2, force: float = 100.0) -> bool:
	# Store original thrower position
	var original_thrower_pos = thrower.global_position
	
	# Make item visible
	visible = true
	
	# Clear inventory flags
	set_flag("item_flags", ItemFlags.IN_INVENTORY, false)
	inventory_owner = null
	
	# Get the world node
	var world = thrower.get_parent()
	
	# Remove from current parent if needed
	if get_parent():
		get_parent().remove_child(self)
	
	# Add to world
	world.call_deferred("add_child", self)
	
	# Set the start position
	global_position = original_thrower_pos
	
	# Calculate target position based on direction and force
	# For top-down games, force determines distance in tiles
	var throw_distance = clamp(force / 10.0, 1.0, 10.0) # Maximum 10 tiles throw distance 
	var normalized_dir = direction.normalized()
	var target_pos = original_thrower_pos + normalized_dir * throw_distance * 32.0 # 32 pixels per tile
	
	# Find nearest valid tile if target is invalid
	target_pos = find_nearest_valid_tile(target_pos)
	
	# Setup the throw with explicit positions
	call_deferred("_setup_throw_after_reparent", original_thrower_pos, target_pos, thrower)
	
	# Enable processing
	set_physics_process(true)
	throw_in_progress = true
	
	# Emit signals
	emit_signal("is_thrown", thrower, null)
	emit_signal("throw_started", thrower, direction, force)
	
	return true

# Setup throw after reparenting
func _setup_throw_after_reparent(start_pos: Vector2, end_pos: Vector2, thrower):
	# Force the global position to match thrower's position
	global_position = start_pos
	
	# Start throw motion with explicit start and end positions
	is_flying = true
	throw_start_pos = start_pos
	throw_target_pos = end_pos
	flight_time = 0.0
	landed = false
	
	# Calculate duration based on distance (faster for closer targets)
	var distance = start_pos.distance_to(end_pos)
	flight_duration = clamp(distance / 300.0, 0.2, 0.8) # Shorter duration = faster throw
	
	# Enable throw trail if enabled
	if throw_trail_enabled and throw_trail:
		throw_trail.visible = true
		throw_trail.clear_points()
	
	# Add rotation for visual effect
	var rotation_tween = create_tween()
	rotation_tween.tween_property(self, "rotation", rotation + randf_range(-PI, PI), flight_duration)
	
	# Play throw sound
	if throw_sound:
		play_audio(throw_sound, 0.5)
	else:
		# Generic throw sound
		var audio_manager = get_node_or_null("/root/AudioManager")
		if audio_manager:
			audio_manager.play_positioned_sound("throw", start_pos, 0.4)

# Find nearest valid tile if target position is invalid
func find_nearest_valid_tile(target_pos: Vector2) -> Vector2:
	# Get world node
	var world = get_node_or_null("/root/World")
	if not world:
		return target_pos
	
	# Get tile position
	var tile_pos = world_to_tile(target_pos)
	
	# Check if tile is valid
	if world.has_method("is_valid_throw_target") and !world.is_valid_throw_target(tile_pos):
		# Find nearest valid tile using simple search
		var max_search = 3 # Maximum search distance
		var nearest_valid_tile = null
		var closest_distance = 999999
		
		for x in range(-max_search, max_search + 1):
			for y in range(-max_search, max_search + 1):
				var check_pos = Vector2i(tile_pos.x + x, tile_pos.y + y)
				var distance = tile_pos.distance_to(check_pos)
				
				if distance < closest_distance and world.is_valid_throw_target(check_pos):
					closest_distance = distance
					nearest_valid_tile = check_pos
		
		# If found a valid tile, use it
		if nearest_valid_tile:
			return tile_to_world(nearest_valid_tile)
	
	return target_pos

# Simplified throw motion setup
func start_throw_motion(from_pos: Vector2, to_pos: Vector2):
	# Set throw parameters
	is_flying = true
	throw_start_pos = from_pos
	throw_target_pos = to_pos
	flight_time = 0.0
	landed = false
	
	# Calculate duration based on distance (faster for closer targets)
	var distance = from_pos.distance_to(to_pos)
	flight_duration = clamp(distance / 300.0, 0.2, 0.8) # Shorter duration = faster throw
	
	# Enable throw trail if enabled
	if throw_trail_enabled and throw_trail:
		throw_trail.visible = true
		throw_trail.clear_points()
	
	# Add rotation for visual effect
	var rotation_tween = create_tween()
	rotation_tween.tween_property(self, "rotation", rotation + randf_range(-PI, PI), flight_duration)
	
	# Ensure correct position
	global_position = from_pos

# Process throw - straight line movement
func process_throw(delta):
	# Update flight time
	flight_time += delta
	
	# Check if throw is complete
	if flight_time >= flight_duration:
		complete_throw()
		return
	
	# Calculate progress (0 to 1)
	var t = flight_time / flight_duration
	
	# Use ease function for natural acceleration/deceleration
	var eased_t = ease(t, 1.5) # Slight ease out for natural slowing
	
	# Simple linear interpolation with fixed start and end positions
	var current_pos = throw_start_pos.lerp(throw_target_pos, eased_t)
	
	# Update position directly
	global_position = current_pos
	
	# Add a small arc for realism (optional)
	var arc_height = 20.0 # Maximum height of arc in pixels
	var arc_offset = sin(eased_t * PI) * arc_height
	global_position.y -= arc_offset # Adjust Y to create arc effect

# Complete throw
func complete_throw():
	is_flying = false
	landed = true
	throw_in_progress = false
	
	# Final position
	global_position = throw_target_pos
	
	# Visual effect for impact
	create_impact_effect()
	
	# Register with tile system
	_register_with_tile_system()
	
	# Handle impact effects
	on_throw_impact()
	
	# Emit completion signal
	emit_signal("throw_ended", global_position)

# Handle throw impact
func on_throw_impact():
	# Play impact sound
	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager:
		audio_manager.play_positioned_sound("item_land", global_position, 0.4)
	
	# Visual impact effect
	var impact_tween = create_tween()
	impact_tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.1)
	impact_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.2)
	
	# Check for entities at landing position
	var world = get_parent()
	if world and "tile_occupancy_system" in world and world.tile_occupancy_system:
		var tile_system = world.tile_occupancy_system
		var tile_pos = world_to_tile(global_position)
		
		if tile_system.has_method("get_entities_at"):
			var entities = tile_system.get_entities_at(tile_pos, 0) # z-level 0
			
			# Check for hit entities (excluding self)
			for entity in entities:
				if entity != self and "entity_type" in entity:
					if entity.entity_type == "character" or entity.entity_type == "mob":
						# Apply damage
						if entity.has_method("take_damage"):
							entity.take_damage(5.0, "blunt", "thrown", true)
						
						# Play hit sound
						if audio_manager:
							audio_manager.play_positioned_sound("throw_hit", global_position, 0.5)
						break

# Create impact effect
func create_impact_effect():
	# Simple scale effect
	var impact_tween = create_tween()
	impact_tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.1)
	impact_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.2)
	
	# Flash effect
	var color_tween = create_tween()
	color_tween.tween_property(self, "modulate", Color(1.2, 1.2, 1.2, 1.0), 0.1)
	color_tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.2)

# Throw to specific target position
func throw_at_target(user, target_position: Vector2):
	# Calculate direction to target
	var throw_direction = (target_position - user.global_position).normalized()
	
	# Store target
	throw_target = target_position
	
	# Make item visible
	visible = true
	
	# Clear inventory flags
	set_flag("item_flags", ItemFlags.IN_INVENTORY, false)
	inventory_owner = null
	
	# Get the world node
	var world = user.get_parent()
	
	# Remove from current parent if needed
	if get_parent():
		get_parent().remove_child(self)
	
	# Add to world
	world.call_deferred("add_child", self)
	
	# Explicitly set the target position without recalculating it
	call_deferred("_setup_throw_after_reparent", user.global_position, target_position, user)
	
	# Enable processing
	set_physics_process(true)
	throw_in_progress = true
	
	# Emit signals
	emit_signal("is_thrown", user, null)
	emit_signal("throw_started", user, throw_direction, 100.0)
	
	return true

# Trigger any special effects when item lands
func trigger_landing_effects(position):
	# Override in subclasses to implement special effects
	pass

#
# TOOL FUNCTIONS
#

# Tool interaction handling
func use_tool(target, user, time: float, amount: int = 0, volume: float = 0) -> bool:
	if tool_behaviour.is_empty():
		return false
	
	# Play tool sound
	if usesound:
		play_audio(usesound, volume)
	
	# Signal effect update
	emit_signal("effect_update", self)
	
	# Wait for tool use time
	await get_tree().create_timer(time * toolspeed).timeout
	
	return true

# Get unique actions this item provides (for action buttons)
func get_actions() -> Array:
	return actions

#
# UTILITY FUNCTIONS
#

# Get display name
func get_display_name() -> String:
	if "item_name" in self and item_name:
		return item_name
	return name

# Convert world position to tile position
func world_to_tile(world_pos):
	# Try to get tile size from world
	var tile_size = 32  # Default
	var world = get_node_or_null("/root/World")
	if world and "TILE_SIZE" in world:
		tile_size = world.TILE_SIZE
	
	# Convert to tile coordinates
	return Vector2i(int(world_pos.x / tile_size), int(world_pos.y / tile_size))

# Convert tile position to world position (center of tile)
func tile_to_world(tile_pos):
	# Try to get tile size from world
	var tile_size = 32  # Default
	var world = get_node_or_null("/root/World")
	if world and "TILE_SIZE" in world:
		tile_size = world.TILE_SIZE
	
	# Convert to world coordinates (center of tile)
	return Vector2((tile_pos.x * tile_size) + (tile_size / 2.0), (tile_pos.y * tile_size) + (tile_size / 2.0))

#
# SERIALIZATION
#

# For serialization
func serialize():
	var data = {
		"item_name": item_name,
		"description": description,
		"force": force,
		"w_class": w_class,
		"sharp": sharp,
		"edge": edge,
		"attack_speed": attack_speed,
		"equip_slot_flags": equip_slot_flags,
		"item_flags": item_flags,
		"current_slot": current_slot,
		"last_equipped_slot": last_equipped_slot,
		"wielded": wielded,
		"pickupable": pickupable,
		"inv_hide_flags": inv_hide_flags,
		"obj_integrity": obj_integrity,
		"max_integrity": max_integrity,
		"has_persistent_effects": has_persistent_effects
	}
	return data

func deserialize(data):
	if "item_name" in data: item_name = data.item_name
	if "description" in data: description = data.description
	if "force" in data: force = data.force
	if "w_class" in data: w_class = data.w_class
	if "sharp" in data: sharp = data.sharp
	if "edge" in data: edge = data.edge
	if "attack_speed" in data: attack_speed = data.attack_speed
	if "equip_slot_flags" in data: equip_slot_flags = data.equip_slot_flags
	if "item_flags" in data: item_flags = data.item_flags
	if "current_slot" in data: current_slot = data.current_slot
	if "last_equipped_slot" in data: last_equipped_slot = data.last_equipped_slot
	if "wielded" in data: wielded = data.wielded
	if "pickupable" in data: pickupable = data.pickupable
	if "inv_hide_flags" in data: inv_hide_flags = data.inv_hide_flags
	if "obj_integrity" in data: obj_integrity = data.obj_integrity
	if "max_integrity" in data: max_integrity = data.max_integrity
	if "has_persistent_effects" in data: has_persistent_effects = data.has_persistent_effects
