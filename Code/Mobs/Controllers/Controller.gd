extends BaseObject
class_name GridMovementController

#region CONSTANTS
# Movement constants - REVISED
const TILE_SIZE: int = 32  # Size of a tile in pixels
const BASE_MOVE_TIME: float = 0.3  # Time to move one tile (seconds) - balanced speed
const RUNNING_MOVE_TIME: float = 0.2  # Faster movement when running
const CRAWLING_MOVE_TIME: float = 0.35  # Slower movement when crawling
const MIN_MOVE_INTERVAL: float = 0.01  # Minimum time between move attempts for responsiveness
const INPUT_BUFFER_TIME: float = 0.2  # How l ong to remember input after movement starts

# Zero-G constants
const ZERO_G_THRUST: float = 2.5        # Base thrust force when pushing in zero-G
const ZERO_G_DAMPING: float = 0.02      # Gradual velocity reduction in zero-G (low value for space)
const ZERO_G_ROTATION_SPEED: float = 3.0 # How quickly character can rotate in zero-G
const ZERO_G_MAX_SPEED: float = 5.0     # Maximum speed in zero-G
const ZERO_G_CONTROL_FACTOR: float = 0.5 # How much control you have over movement in zero-G (0-1)
const ZERO_G_BOUNCE_FACTOR: float = 0.7  # How much velocity is retained on collision
const ZERO_G_GRID_SNAP_THRESHOLD: float = 0.25  # When to snap to grid positions

# Item interaction constants
const PICKUP_RANGE: float = 1.5  # Maximum range in tiles to pick up items
const THROW_RANGE_BASE: float = 10.0  # Base throw range in tiles
const THROW_STRENGTH_MULTIPLIER: float = 1.0  # Default throw strength
const MIN_THROW_DISTANCE: float = 1.0  # Minimum distance (tiles) for throw to be valid
const DROP_DISTANCE: float = 0.5  # Distance in tiles to drop an item from player

# Movement states
enum MovementState {
	IDLE,
	MOVING,
	RUNNING,
	STUNNED,
	CRAWLING,
	FLOATING  # For zero-gravity areas
}

# Direction constants
enum Direction {
	NONE = -1,
	NORTH = 0,
	EAST = 1,
	SOUTH = 2,
	WEST = 3,
	NORTHEAST = 4,
	SOUTHEAST = 5,
	SOUTHWEST = 6,
	NORTHWEST = 7
}

# Collision types
enum CollisionType {
	NONE,
	WALL,
	ENTITY,
	DENSE_OBJECT,
	DOOR_CLOSED,
	WINDOW
}

# Intent constants
enum Intent {
	HELP = 0,
	DISARM = 1,
	GRAB = 2,
	HARM = 3
}

# Z-movement flags
enum ZMoveFlags {
	NONE = 0,
	IGNORE_CHECKS = 1,
	FORCED = 2,
	CAN_FLY_CHECKS = 4,
	FEEDBACK = 8,
	FLIGHT_FLAGS = 12
}

# Grab states
enum GrabState {
	NONE,
	PASSIVE,  # Just pulling
	AGGRESSIVE,  # Restrains movement somewhat
	NECK,  # Restrains movement significantly
	KILL  # Strangling
}

# Body zone constants
const BODY_ZONE_HEAD = "head"
const BODY_ZONE_CHEST = "chest"
const BODY_ZONE_L_ARM = "l_arm"
const BODY_ZONE_R_ARM = "r_arm"
const BODY_ZONE_L_LEG = "l_leg"
const BODY_ZONE_R_LEG = "r_leg"
const BODY_ZONE_PRECISE_EYES = "eyes"
const BODY_ZONE_PRECISE_MOUTH = "mouth"
const BODY_ZONE_PRECISE_GROIN = "groin"
const BODY_ZONE_PRECISE_L_HAND = "l_hand"
const BODY_ZONE_PRECISE_R_HAND = "r_hand"
const BODY_ZONE_PRECISE_L_FOOT = "l_foot"
const BODY_ZONE_PRECISE_R_FOOT = "r_foot"
#endregion

#region VARIABLES
# Direction light indicators
@onready var north: PointLight2D = $North
@onready var west: PointLight2D = $West
@onready var south: PointLight2D = $South
@onready var east: PointLight2D = $East
@onready var north_east: PointLight2D = $NorthEast
@onready var south_east: PointLight2D = $SouthEast
@onready var south_west: PointLight2D = $SouthWest
@onready var north_west: PointLight2D = $NorthWest

# Stamina System
var max_stamina: float = 100.0
var current_stamina: float = 100.0
var stamina_drain_rate: float = 3.33  # Drains in ~30 seconds (100/3.33)
var stamina_regen_rate: float = 5.0   # Recovers in ~20 seconds
var sprint_allowed: bool = true
var sprint_recovery_threshold: float = 25.0  # Must recover to this % before sprinting again
var sprint_disabled_timeout: float = 0.0

# Movement variables
var is_local_player: bool = false
var current_state: int = MovementState.IDLE
var current_direction: int = Direction.SOUTH
var current_z_level: int = 0
var current_tile_position: Vector2i = Vector2i.ZERO
var previous_tile_position: Vector2i = Vector2i.ZERO
var target_tile_position: Vector2i = Vector2i.ZERO
var move_progress: float = 0.0  # 0.0 to 1.0
var is_moving: bool = false
var current_move_time: float = BASE_MOVE_TIME
var last_move_time: float = 0.0
var movement_cooldown_active: bool = false
var input_buffer_timer: float = 0.0
var buffered_movement: Vector2i = Vector2i.ZERO
var is_sprinting: bool = false
var allow_diagonal: bool = true
var movement_speed_modifier: float = 1.0
var last_input_direction: Vector2 = Vector2.ZERO
var next_move_time: float = 0.0

# Zero-G movement
var is_floating: bool = false
var gravity_strength: float = 1.0
var inertia_dir: Vector2 = Vector2.ZERO
var last_push_time: float = 0.0

# Entity characteristics
var is_stunned: bool = false
var stun_remaining: float = 0.0
var entity_dense: bool = true
var can_push: bool = true
var push_force: float = 1.0
var mass: float = 70.0
var interaction_range: float = 1.5
var dexterity: float = 10.0
var is_admin_mode: bool = false
var is_lying: bool = false
var lying_angle: float = 90.0
var can_crawl: bool = true
var crawl_cooldown: float = 0.0
var crawl_speed_multiplier: float = 0.5
var lying_stamina_recovery_bonus: float = 1.5
var last_lying_state_change: float = 0.0
var lying_state_change_cooldown: float = 0.8
var stand_up_attempts: int = 0

# Pulling/pushing
var pulling_entity = null
var pulled_by_entity = null
var has_pull_flag = true
var pull_speed_modifier: float = 0.7

# Grab-related variables
var grab_state: int = GrabState.NONE
var grabbing_entity = null
var grab_resist_progress: float = 0.0
var grab_time: float = 0.0

# Throwing
var throw_mode: bool = false
var throw_trajectory = []
var throw_power: float = 1.0
var is_throw_mode_active: bool = false
var throw_target_item = null
var throw_toggle_cooldown: float = 0.0
var throw_cooldown_duration: float = 0.5

# Item interaction
var active_equipment = {}
var held_items = []
var active_hand_index: int = 0
var entity_id: String = ""
var entity_type: String = "character"
var entity_name: String = "Unnamed Character"
var parent_container = null
var carried_items = []
var max_carry_weight: float = 50.0
var current_carry_weight: float = 0.0

# Environmental factors
var current_tile_type: String = "floor"
var current_tile_friction: float = 1.0

# Targeting
var zone_selected: String = BODY_ZONE_CHEST
var intent: int = Intent.HELP
var active_radial_menu = null
var status_effects = {}

# System references
var world = null
var tile_occupancy_system = null
var collision_resolver: Node = null
var spatial_manager = null
var sensory_system = null
var atmosphere_system = null
var audio_manager = null
var sprite_system = null
var world_interaction_system = null
var input_controller = null
var inventory_system = null
var health_system = null
var interaction_system = null
var audio_system = null
var limb_system = null
var status_effect_manager = null
var interaction_processor = null
var update_sprite_direction: Callable

# Body zones as organized lists for cycling
var body_zones_head = [BODY_ZONE_HEAD, BODY_ZONE_PRECISE_EYES, BODY_ZONE_PRECISE_MOUTH]
var body_zones_r_arm = [BODY_ZONE_R_ARM, BODY_ZONE_PRECISE_R_HAND]
var body_zones_l_arm = [BODY_ZONE_L_ARM, BODY_ZONE_PRECISE_L_HAND]
var body_zones_r_leg = [BODY_ZONE_R_LEG, BODY_ZONE_PRECISE_R_FOOT]
var body_zones_l_leg = [BODY_ZONE_L_LEG, BODY_ZONE_PRECISE_L_FOOT]
#endregion

#region SIGNALS
signal direction_changed(old_direction, new_direction)
signal tile_changed(old_tile, new_tile)
signal state_changed(old_state, new_state)
signal entity_moved(old_tile, new_tile, entity)
signal z_level_changed(old_z, new_z, position)
signal bump(entity, bumped_entity, direction)
signal interaction_requested(target)
signal began_floating()
signal stopped_floating()
signal pushing_entity(pushed_entity, direction)
signal footstep(position, floor_type)
signal throw_trajectory_updated(trajectory)
signal zone_selected_changed(new_zone)
signal grab_state_changed(new_state, grabbed_entity)
signal pulling_changed(pulled_entity)
signal being_pulled_changed(pulling_entity)
signal dropped_item(item)
signal picked_up_item(item)
signal intent_changed(new_intent)
signal began_restraint_resist()
signal broke_free()
signal active_hand_changed(hand_index, item)
signal movement_input_received(direction)
signal systems_initialized()
signal item_picked_up(item)
signal item_dropped(item)
signal inventory_updated()
signal interaction_started(entity)
signal interaction_completed(entity, success)
signal radial_menu_opened(entity)
signal radial_menu_closed()
signal ghost_mode_requested()
signal possession_started(ghost)
signal possession_ended()
#endregion

#region INITIALIZATION AND SETUP
func _ready():
	limb_system = get_node("LimbSystem")
	status_effect_manager = get_node("StatusEffectManager")
	
	allow_diagonal = false  # Disable diagonal movement
	
	# Configure click manager if available
	var click_manager = get_node_or_null("World/ClickSystemManager")
	if click_manager:
		click_manager.grid_controller = self
		click_manager.player = self
		click_manager.initialize_systems()
		print("Player: Manually setting grid controller reference")
	
	setup_singleplayer()
	
	# Find intent system if it exists, or create one
	var intent_system = get_node_or_null("IntentSystem")
	if !intent_system:
		intent_system = IntentSystem.new()
		intent_system.name = "IntentSystem"
		add_child(intent_system)
	
	# Initialize position and sprite
	connect_to_sprite_system()
	current_tile_position = world_to_tile(position)
	previous_tile_position = current_tile_position
	target_tile_position = current_tile_position
	
	# Initialize input controller
	setup_input_controller()
	
	# Find necessary systems
	find_game_systems()
	find_inventory_system()
	
	# Register with systems
	register_with_systems()
	
	# Set initial tile type
	current_tile_type = get_current_floor_type()
	
	# Register character tile occupancy
	if tile_occupancy_system:
		tile_occupancy_system.register_entity_at_tile(self, current_tile_position, current_z_level)
	
	# Setup body zones and held items
	initialize_held_items()
	var weapon_controller = get_node("WeaponController")
	if weapon_controller:
		weapon_controller.connect("ammo_changed", Callable(self, "_on_ammo_changed"))
		weapon_controller.connect("firing_mode_changed", Callable(self, "_on_firing_mode_changed"))
		weapon_controller.connect("weapon_state_changed", Callable(self, "_on_weapon_state_changed"))
	
	# Give systems time to initialize before connecting signals
	var timer = Timer.new()
	timer.wait_time = 0.2
	timer.one_shot = true
	add_child(timer)
	timer.timeout.connect(connect_signals)
	timer.start()
	
	# Connect to ClickSystem if available
	connect_to_click_system()

func _enter_tree():
	# If we have a multiplayer authority set, configure based on whether we're local
	if has_node("MultiplayerSynchronizer"):
		var sync = get_node("MultiplayerSynchronizer")
		var is_local = sync.get_multiplayer_authority() == multiplayer.get_unique_id()
		_configure_local_player(is_local)
	
	set_multiplayer_authority(name.to_int())

func _configure_local_player(is_local: bool):
	is_local_player = is_local
	
	# Enable/disable camera based on locality
	var camera = get_node_or_null("Camera2D")
	if camera:
		camera.enabled = is_local
		print("Player Controller: Camera ", "enabled" if is_local else "disabled")
	
	# Enable/disable UI
	var ui = get_node_or_null("PlayerUI")
	if ui:
		ui.visible = is_local
		print("Player Controller: UI ", "visible" if is_local else "hidden")
	
	# Configure input processing
	var input_controller = get_node_or_null("InputController")
	if input_controller:
		input_controller.set_process_input(is_local)
		input_controller.set_process_unhandled_input(is_local)
		print("Player Controller: Input processing ", "enabled" if is_local else "disabled")
	
	# Set processing modes
	set_process_input(is_local)
	set_process_unhandled_input(is_local)
	
	print("Player Controller: Configured as ", "local" if is_local else "remote", " player")

func find_game_systems():
	# Get world reference
	world = get_parent()
	if !world:
		# Try parent.parent (World > Player > Controller)
		if get_parent() and get_parent().get_parent():
			world = get_parent().get_parent()
	
	# Verify this is the correct World node
	if world and !world.has_method("get_tile_data"):
		print("WARNING: Found 'world' node but it doesn't have get_tile_data method!")
		world = null  # Reset since this isn't the right node
		
		# Try to find by name instead
		var root = get_node_or_null("/root")
		if root:
			world = root.find_child("World", true, false)
		if world:
			print("Found World node by name search")
	
	# Find inventory system
	inventory_system = get_parent().get_node_or_null("InventorySystem")
	
	# Find sprite system - check for both versions
	sprite_system = get_parent().get_node_or_null("UpdatedHumanSpriteSystem")
	if !sprite_system:
		sprite_system = get_parent().get_node_or_null("HumanSpriteSystem")
	
	# Find health system (if any)
	health_system = get_parent().get_node_or_null("HealthSystem")
	
	# Get entity info
	if "entity_name" in get_parent():
		entity_name = get_parent().entity_name
	
	if "entity_id" in get_parent():
		entity_id = get_parent().entity_id
	
	# Try to find other systems based on world reference
	if world:
		tile_occupancy_system = world.get_node_or_null("TileOccupancySystem")
		spatial_manager = world.get_node_or_null("SpatialManager")
		sensory_system = world.get_node_or_null("SensorySystem")
		atmosphere_system = world.get_node_or_null("AtmosphereSystem")
		audio_manager = world.get_node_or_null("AudioManager")

func register_with_systems():
	if spatial_manager:
		spatial_manager.register_entity(self)
	
	if sensory_system:
		sensory_system.register_entity(self)
		
	# Find any interaction systems
	var interaction_systems = get_tree().get_nodes_in_group("interaction_system")
	if interaction_systems.size() > 0:
		interaction_system = interaction_systems[0]
		
		# Connect signals if needed
		if interaction_system.has_signal("entity_interaction"):
			interaction_system.connect("entity_interaction", Callable(self, "_on_entity_interaction"))

func unregister_from_systems():
	if spatial_manager:
		spatial_manager.unregister_entity(self)
	
	if sensory_system:
		sensory_system.unregister_entity(self)
	
	if tile_occupancy_system:
		tile_occupancy_system.remove_entity(self, current_tile_position, current_z_level)

func connect_signals():
	if inventory_system:
		# Connect inventory signals
		var inventory_signals = [
			["inventory_updated", "_on_inventory_updated"],
			["item_equipped", "_on_item_equipped"],
			["item_unequipped", "_on_item_unequipped"],
			["item_added", "_on_inventory_updated"],
			["item_removed", "_on_inventory_updated"]
		]
		
		for signal_info in inventory_signals:
			var signal_name = signal_info[0]
			var method_name = signal_info[1]
			
			if inventory_system.has_signal(signal_name) and self.has_method(method_name):
				if !inventory_system.is_connected(signal_name, Callable(self, method_name)):
					inventory_system.connect(signal_name, Callable(self, method_name))
					print("GridMovementController: Connected " + signal_name + " signal")
	
	# Connect any UI system to inventory system
	var ui = get_parent().get_node_or_null("PlayerUI")
	if ui and inventory_system:
		# Make sure the UI's inventory_system reference is set
		ui.inventory_system = inventory_system
		
		# Connect inventory update signals to UI
		var ui_signals = [
			["inventory_updated", "_on_inventory_updated"],
			["item_equipped", "_on_item_equipped"],
			["item_unequipped", "_on_item_unequipped"],
			["active_hand_changed", "_on_active_hand_changed"]
		]
		
		for signal_info in ui_signals:
			connect_signal_if_possible(inventory_system, ui, signal_info[0], signal_info[1])
	
	if world_interaction_system:
		# Connect tile_clicked signal if it exists and not already connected
		if world_interaction_system.has_signal("tile_clicked") and !world_interaction_system.is_connected("tile_clicked", Callable(self, "_on_tile_clicked")):
			world_interaction_system.tile_clicked.connect(_on_tile_clicked)
		
		# Connect entity_clicked signal if it exists and not already connected
		if world_interaction_system.has_signal("entity_clicked") and !world_interaction_system.is_connected("entity_clicked", Callable(self, "_on_entity_clicked")):
			world_interaction_system.entity_clicked.connect(_on_entity_clicked)
			
	# Initialize sprite system
	if sprite_system and sprite_system.has_method("initialize"):
		sprite_system.initialize(get_parent())
	
	# Signal that we're done initializing
	emit_signal("systems_initialized")

func connect_signal_if_possible(source, target, signal_name, method_name):
	if source.has_signal(signal_name) and target.has_method(method_name):
		if !source.is_connected(signal_name, Callable(target, method_name)):
			source.connect(signal_name, Callable(target, method_name))
			print("Connected signal " + signal_name + " to " + method_name)

func connect_to_sprite_system():
	# First check if it's a direct child of us
	sprite_system = get_node_or_null("UpdatedHumanSpriteSystem")
	
	if !sprite_system:
		# If not a direct child, check if it's a sibling (child of our parent)
		if get_parent():
			sprite_system = get_parent().get_node_or_null("UpdatedHumanSpriteSystem")
	
	if !sprite_system:
		# Try looking for the original HumanSpriteSystem as fallback
		sprite_system = get_node_or_null("HumanSpriteSystem")
		if !sprite_system and get_parent():
			sprite_system = get_parent().get_node_or_null("HumanSpriteSystem")
	
	if !sprite_system:
		# If still not found, look for any sprite system in our descendants
		var potential_systems = find_children("*", "UpdatedHumanSpriteSystem", true, false)
		if potential_systems.size() > 0:
			sprite_system = potential_systems[0]
		else:
			potential_systems = find_children("*", "HumanSpriteSystem", true, false)
			if potential_systems.size() > 0:
				sprite_system = potential_systems[0]
	
	if sprite_system:
		print("CharacterController: Connected to sprite system: ", sprite_system.name)
		
		# Initialize the sprite system with our entity
		if sprite_system.has_method("initialize"):
			sprite_system.initialize(get_parent())
	else:
		print("CharacterController: No sprite system found")

func connect_to_click_system():
	# First look for the ClickSystem as a direct sibling
	var click_system = get_node_or_null("World/ClickSystem")
	if click_system:
		print("GridMovementController: Found ClickSystem, connecting signals")
		if click_system.has_signal("tile_clicked") and !click_system.is_connected("tile_clicked", Callable(self, "_on_tile_clicked")):
			click_system.tile_clicked.connect(_on_tile_clicked)
			print("GridMovementController: Connected tile_clicked signal directly from ClickSystem")
	else:
		# Try to find ClickSystem in parent
		click_system = get_parent().get_node_or_null("World/ClickSystem")
		if click_system:
			print("GridMovementController: Found ClickSystem in parent, connecting signals")
			if click_system.has_signal("tile_clicked") and !click_system.is_connected("tile_clicked", Callable(self, "_on_tile_clicked")):
				click_system.tile_clicked.connect(_on_tile_clicked)
				print("GridMovementController: Connected tile_clicked signal directly from parent's ClickSystem")
		else:
			# Try to find ClickSystem anywhere in the scene
			var potential_systems = get_tree().get_nodes_in_group("click_system")
			if potential_systems.size() > 0:
				click_system = potential_systems[0]
				print("GridMovementController: Found ClickSystem via group, connecting signals")
				if click_system.has_signal("tile_clicked") and !click_system.is_connected("tile_clicked", Callable(self, "_on_tile_clicked")):
					click_system.tile_clicked.connect(_on_tile_clicked)
					print("GridMovementController: Connected tile_clicked signal directly from found ClickSystem")

func setup_input_controller():
	# Check if an InputController already exists
	for child in get_children():
		if child is InputController:
			print("InputController already exists, using existing one")
			input_controller = child
			input_controller.connect_to_entity(self)
			return
	
	# Create a new InputController if none exists
	print("Creating new InputController")
	input_controller = InputController.new()
	input_controller.name = "InputController"
	add_child(input_controller)
	
	# Connect the input controller to this entity
	input_controller.connect_to_entity(self)

func initialize_held_items():
	# Ensure we have slots for both hands
	if held_items.size() < 2:
		held_items = [null, null]
#endregion

#region MAIN PROCESSING
func _process(delta):
	var weapon_controller = get_node_or_null("WeaponController")
	if weapon_controller:
		weapon_controller.process_weapon_targeting(delta)
	
	# Update status effects
	update_status_effects(delta)
	
	# Update throw toggle cooldown
	if throw_toggle_cooldown > 0:
		throw_toggle_cooldown -= delta
	
	# Process input buffering
	if input_buffer_timer > 0:
		input_buffer_timer -= delta
		if input_buffer_timer <= 0:
			buffered_movement = Vector2i.ZERO  # Clear buffered input if expired

func _physics_process(delta: float) -> void:
	if !is_multiplayer_authority():
		return
	# Handle stun effect
	if is_stunned:
		stun_remaining -= delta
		if stun_remaining <= 0:
			is_stunned = false
			set_state(MovementState.IDLE)
		else:
			return  # Skip movement while stunned
	
	# Process grab effects
	if grabbing_entity != null:
		process_grab_effects(delta)
	
	# Process being grabbed/restrained effects
	if pulled_by_entity != null:
		process_being_pulled(delta)
	
	# Process pulling mechanics
	if pulling_entity != null:
		process_pulling(delta)
	
	# Handle zero-g floating physics
	if is_floating:
		process_zero_g_movement(delta)
	# Handle normal movement
	else:
		process_grid_movement(delta)
	if is_moving && sprite_system && sprite_system.has_method("update_movement_offset"):
		# Provide a subtle movement offset that avoids the "thrusting" effect
		var progress = ease_movement_progress(move_progress)
		sprite_system.update_movement_offset(progress)
	# Process pending buffered movement if we're not moving
	if !is_moving and buffered_movement != Vector2i.ZERO and input_buffer_timer > 0:
		attempt_move(buffered_movement)
		buffered_movement = Vector2i.ZERO
		input_buffer_timer = 0
#endregion

#region MOVEMENT SYSTEM
# Handle movement input with better responsiveness
func handle_move_input(direction: Vector2):
	emit_signal("movement_input_received", direction)
	
	# Store the last input direction for buffering
	last_input_direction = direction
	
	# Convert to grid direction - Cardinal directions only!
	var normalized_dir = get_normalized_input_direction(direction)
	
	# If no real direction, nothing to do
	if normalized_dir == Vector2i.ZERO:
		return
	
	# If already moving, buffer this movement for more responsive feel
	if is_moving:
		buffered_movement = normalized_dir
		input_buffer_timer = INPUT_BUFFER_TIME
	else:
		# Try to move now
		attempt_move(normalized_dir)

func process_grid_movement(delta):
	# Update stamina
	process_stamina(delta)
		
	# Only handle interpolation/completion, NO input detection
	if is_moving:
		# Steady linear progress with fixed rate
		move_progress += delta / current_move_time
		
		if move_progress >= 1.0:
			# Completed the move
			complete_movement()
		else:
			# Interpolate position with minimal easing
			var start_pos = tile_to_world(current_tile_position)
			var end_pos = tile_to_world(target_tile_position)
			
			# Very mild easing for smooth but consistent movement
			var eased_progress = ease_movement_progress(move_progress)
			position = start_pos.lerp(end_pos, eased_progress)

# Complete the current movement
func complete_movement():
	# Ensure we only complete once
	move_progress = 1.0
	is_moving = false
	
	# Update position
	position = tile_to_world(target_tile_position)
	
	# Update current tile
	previous_tile_position = current_tile_position
	current_tile_position = target_tile_position
	
	# Emit signals
	emit_signal("tile_changed", previous_tile_position, current_tile_position)
	emit_signal("entity_moved", previous_tile_position, current_tile_position, self)
	
	# Check for environmental effects
	check_tile_environment()
	
	# If crawling, emit a crawling sound
	if is_lying && current_state == MovementState.CRAWLING:
		emit_crawling_sound()
	else:
		emit_footstep_sound()
	
	# Decrease next move time for more responsive movement
	next_move_time = Time.get_ticks_msec() * 0.001 + MIN_MOVE_INTERVAL * 0.8
	
	# Process buffered movement with improved timing
	if buffered_movement != Vector2i.ZERO && input_buffer_timer > 0:
		# Create a reference to the buffered movement and clear it
		var next_dir = buffered_movement
		buffered_movement = Vector2i.ZERO
		input_buffer_timer = 0
		
		# Instead of delaying, try to move immediately for better responsiveness
		attempt_move(next_dir)
	else:
		# No more movement, update state
		if is_lying:
			set_state(MovementState.CRAWLING)
		else:
			set_state(MovementState.IDLE)

func ease_movement_progress(progress: float) -> float:
	return lerp(progress, progress * progress * (3.0 - 2.0 * progress), 0.3)

func attempt_move(direction: Vector2i):
	# Skip movement if stunned or already moving
	if is_stunned || is_moving:
		# Buffer the input if we're moving
		if is_moving:
			buffered_movement = direction
			input_buffer_timer = INPUT_BUFFER_TIME
		return false
	
	# Check if enough time has passed since last move (prevents too rapid movement)
	var current_time = Time.get_ticks_msec() * 0.001
	if current_time < next_move_time:
		buffered_movement = direction
		input_buffer_timer = INPUT_BUFFER_TIME
		return false
	
	# Check for special movement restrictions
	if !can_move():
		return false
	
	# Update the visual direction
	update_facing_from_input(direction)
	
	# Calculate target tile
	var target_tile = current_tile_position + direction
	
	# Check for collision
	var collision = check_collision(target_tile, current_z_level)
	
	if collision == CollisionType.NONE || is_admin_mode:
		# Clear path or admin mode - move to target tile
		start_move_to(target_tile)
		return true
	else:
		# Handle collision based on type
		handle_collision(collision, target_tile, direction)
		return false

# Start moving to a target tile
func start_move_to(target: Vector2i):
	# Update movement state
	is_moving = true
	move_progress = 0.0
	
	# Determine movement direction based on target tile
	var move_direction = target_tile_position - current_tile_position
	
	# Set target position
	target_tile_position = target
	
	# NOW update the facing direction based on actual movement
	update_facing_from_movement(target - current_tile_position)
	
	# Set next_move_time to enforce minimum intervals
	next_move_time = Time.get_ticks_msec() * 0.001 + MIN_MOVE_INTERVAL
	
	# Adjust movement speed based on state and conditions
	calculate_move_time()
	
	# Update occupancy grid
	if tile_occupancy_system:
		tile_occupancy_system.move_entity(self, current_tile_position, target_tile_position, current_z_level)
	
	# Play movement sound
	if is_lying:
		emit_crawling_sound()
	else:
		emit_footstep_sound()
	
	# Update state
	if is_sprinting && !is_lying:
		set_state(MovementState.RUNNING)
	elif is_lying:
		set_state(MovementState.CRAWLING)
	else:
		set_state(MovementState.MOVING)

# Calculate movement time based on multiple factors
func calculate_move_time():
	# Reset to the actual constant values first
	if current_state == MovementState.RUNNING:
		current_move_time = RUNNING_MOVE_TIME
	elif current_state == MovementState.CRAWLING && is_lying:
		current_move_time = CRAWLING_MOVE_TIME
	else:
		current_move_time = BASE_MOVE_TIME
	
	# Apply modifiers as percentage adjustments
	current_move_time /= movement_speed_modifier
	
	# Apply tile friction as a small adjustment
	current_move_time /= max(0.5, min(1.5, current_tile_friction))
	
	# Apply pulling penalty as a fixed percentage
	if pulling_entity != null:
		current_move_time *= 1.5  # 50% slower when pulling
	
	# Apply extra penalty if lying down
	if is_lying:
		current_move_time *= 1.2  # 20% slower when lying

# Update pull movespeed
func update_pull_movespeed():
	if !pulling_entity:
		# Remove any existing pull modifier
		movement_speed_modifier /= pull_speed_modifier
		return
	
	var drag_delay = 1.4  # Default drag delay multiplier
	
	# If pulling a mob
	if "entity_type" in pulling_entity and pulling_entity.entity_type == "character":
		var pulled_mob = pulling_entity
		
		# If pulled mob is buckled, use buckled object's drag delay
		if "buckled" in pulled_mob and pulled_mob.buckled != null:
			if "drag_delay" in pulled_mob.buckled:
				drag_delay = pulled_mob.buckled.drag_delay
	
	# Apply the drag speed modifier
	movement_speed_modifier *= pull_speed_modifier

func get_normalized_input_direction(raw_input: Vector2 = Vector2.ZERO) -> Vector2i:
	# If no input provided, use the last recorded input
	if raw_input == Vector2.ZERO:
		raw_input = last_input_direction
	
	# No input
	if raw_input == Vector2.ZERO:
		return Vector2i.ZERO
	
	# Determine the primary direction (cardinal only, no diagonals)
	var input_dir = Vector2i.ZERO
	
	# Choose the stronger input axis - forcing cardinal movement only
	if abs(raw_input.x) > abs(raw_input.y):
		input_dir.x = 1 if raw_input.x > 0 else -1
	else:
		input_dir.y = 1 if raw_input.y > 0 else -1
	
	# Apply confusion if active
	if status_effects.has("confused"):
		var confusion_amount = status_effects["confused"]
		
		# confusion logic
		if confusion_amount > 40:
			# Completely random cardinal direction
			var random_dir = randi() % 4
			match random_dir:
				0: return Vector2i(0, -1)  # NORTH
				1: return Vector2i(1, 0)   # EAST
				2: return Vector2i(0, 1)   # SOUTH
				3: return Vector2i(-1, 0)  # WEST
		elif randf() < confusion_amount * 0.015:  # 1.5% chance per confusion unit
			# 90 degree turn
			if input_dir.x != 0:  # Was horizontal
				input_dir = Vector2i(0, [-1, 1][randi() % 2])
			else:  # Was vertical
				input_dir = Vector2i([-1, 1][randi() % 2], 0)
	
	return input_dir

func process_stamina(delta):
	# Drain stamina while sprinting and moving
	if is_sprinting && is_moving:
		current_stamina = max(0, current_stamina - stamina_drain_rate * delta)
		
		# Disable sprinting if stamina is depleted
		if current_stamina <= 0 && sprint_allowed:
			sprint_allowed = false
			is_sprinting = false
			if sensory_system:
				sensory_system.display_message("You're too exhausted to keep running!")
	else:
		# Regenerate stamina when not sprinting
		if current_stamina < max_stamina:
			# Faster recovery when lying down
			var recovery_multiplier = lying_stamina_recovery_bonus if is_lying else 1.0
			current_stamina = min(max_stamina, current_stamina + stamina_regen_rate * recovery_multiplier * delta)
			
			# Re-enable sprinting once recovery threshold is reached
			if !sprint_allowed && current_stamina >= sprint_recovery_threshold:
				sprint_allowed = true
				if sensory_system:
					sensory_system.display_message("You've caught your breath.")
	
	# Update any UI that shows stamina
	var ui = get_node_or_null("../PlayerUI")
	if ui && ui.has_method("update_stamina"):
		ui.update_stamina(current_stamina, max_stamina)

func update_facing_from_input(direction: Vector2i):
	var new_direction = Direction.NONE
	
	# Map the direction vector to Direction enum
	if direction.x > 0 && direction.y == 0:
		new_direction = Direction.EAST
	elif direction.x < 0 && direction.y == 0:
		new_direction = Direction.WEST
	elif direction.x == 0 && direction.y < 0:
		new_direction = Direction.NORTH
	elif direction.x == 0 && direction.y > 0:
		new_direction = Direction.SOUTH
	elif direction.x > 0 && direction.y < 0:
		new_direction = Direction.NORTHEAST
	elif direction.x > 0 && direction.y > 0:
		new_direction = Direction.SOUTHEAST
	elif direction.x < 0 && direction.y > 0:
		new_direction = Direction.SOUTHWEST
	elif direction.x < 0 && direction.y < 0:
		new_direction = Direction.NORTHWEST
	
	# Only update if actually changing direction
	if new_direction != Direction.NONE && new_direction != current_direction:
		var old_direction = current_direction
		current_direction = new_direction
		
		# Update sprite system if available
		if sprite_system != null:
			update_sprite_system_direction(new_direction)
		else:
			# Try to find sprite system if not set
			sprite_system = get_node_or_null("UpdatedHumanSpriteSystem")
			if !sprite_system:
				sprite_system = get_node_or_null("HumanSpriteSystem")
		
		# IMPORTANT: Emit the direction_changed signal
		emit_signal("direction_changed", old_direction, new_direction)
		print("Direction changed from", old_direction, "to", new_direction)
	
# Similarly modify update_facing_from_movement to emit the signal
func update_facing_from_movement(movement_vector: Vector2i):
	var new_direction = Direction.NONE
	
	# Map the movement vector to Direction enum
	if movement_vector.x > 0 && movement_vector.y == 0:
		new_direction = Direction.EAST
	elif movement_vector.x < 0 && movement_vector.y == 0:
		new_direction = Direction.WEST
	elif movement_vector.x == 0 && movement_vector.y < 0:
		new_direction = Direction.NORTH
	elif movement_vector.x == 0 && movement_vector.y > 0:
		new_direction = Direction.SOUTH
	elif movement_vector.x > 0 && movement_vector.y < 0:
		new_direction = Direction.NORTHEAST
	elif movement_vector.x > 0 && movement_vector.y > 0:
		new_direction = Direction.SOUTHEAST
	elif movement_vector.x < 0 && movement_vector.y > 0:
		new_direction = Direction.SOUTHWEST
	elif movement_vector.x < 0 && movement_vector.y < 0:
		new_direction = Direction.NORTHWEST
	
	# Only update if actually changing direction
	if new_direction != Direction.NONE && new_direction != current_direction:
		var old_direction = current_direction
		current_direction = new_direction
		
		# Update sprite system if available
		if sprite_system != null:
			update_sprite_system_direction(new_direction)
		else:
			# Try to find sprite system if not set
			sprite_system = get_node_or_null("UpdatedHumanSpriteSystem")
			if !sprite_system:
				sprite_system = get_node_or_null("HumanSpriteSystem")
		
		# IMPORTANT: Emit the direction_changed signal
		emit_signal("direction_changed", old_direction, new_direction)
		print("Direction changed from", old_direction, "to", new_direction)

# Check if a direction is diagonal
func is_diagonal_movement(direction: Vector2i) -> bool:
	return direction.x != 0 and direction.y != 0

# Attempt diagonal sliding (wall sliding)
func try_diagonal_slide(direction: Vector2i, blocked_tile: Vector2i) -> bool:
	# Try horizontal component
	var horizontal = Vector2i(direction.x, 0)
	var h_target = current_tile_position + horizontal
	
	if check_collision(h_target, current_z_level) == CollisionType.NONE:
		return attempt_move(horizontal)
	
	# Try vertical component
	var vertical = Vector2i(0, direction.y)
	var v_target = current_tile_position + vertical
	
	if check_collision(v_target, current_z_level) == CollisionType.NONE:
		return attempt_move(vertical)
	
	# Both directions blocked
	return false

# Check for collision at a target tile
func check_collision(target_tile: Vector2i, z_level: int) -> int:
	# Check for walls first
	if is_wall_at(target_tile, z_level):
		return CollisionType.WALL
	
	# Check for closed doors
	if is_closed_door_at(target_tile, z_level):
		return CollisionType.DOOR_CLOSED
	
	# Check for windows
	if is_window_at(target_tile, z_level):
		return CollisionType.WINDOW
	
	# Check for dense objects/entities
	if tile_occupancy_system and tile_occupancy_system.has_dense_entity_at(target_tile, z_level, self):
		return CollisionType.ENTITY
	
	# Check if the tile is space (will activate zero-g)
	if world and world.has_method("is_space") and world.is_space(target_tile, z_level):
		check_void_transition()
	
	# No collision
	return CollisionType.NONE

# Handle collision with an object or entity
func handle_collision(collision_type: int, target_tile: Vector2i, direction: Vector2i):
	match collision_type:
		CollisionType.ENTITY:
			# Try to bump/push the entity
			var entity = tile_occupancy_system.get_entity_at(target_tile, current_z_level)
			if entity and can_push:
				emit_signal("bump", self, entity, direction)
				emit_signal("pushing_entity", entity, direction)
				
				# If we're in GRAB intent, try to grab the entity
				if intent == Intent.GRAB:
					grab_entity(entity)
		
		CollisionType.DOOR_CLOSED:
			# Try to open the door
			if world:
				var door_data = world.get_door_at(target_tile, current_z_level)
				if door_data and door_data.has("can_open") and door_data.can_open:
					world.toggle_door(target_tile, current_z_level)
					
					# Play door sound
					if audio_manager:
						audio_manager.play_positioned_sound("door_open", position, 0.5)
		
		CollisionType.WALL, CollisionType.WINDOW:
			# Just bump effect, no special handling
			# Play bump sound
			if audio_manager:
				audio_manager.play_positioned_sound("bump", position, 0.3)
		
		CollisionType.DENSE_OBJECT:
			# Try to interact with the object
			var object = world.get_object_at(target_tile, current_z_level)
			if object:
				emit_signal("interaction_requested", object)

# Toggle running state
func toggle_run(is_running: bool):
	# Don't allow running if stamina is depleted
	if is_running && (!sprint_allowed || current_stamina <= 0):
		if sensory_system:
			sensory_system.display_message("You're too exhausted to run!")
		return
		
	is_sprinting = is_running && sprint_allowed
	
	if is_sprinting && is_moving:
		set_state(MovementState.RUNNING)
	elif is_moving:
		set_state(MovementState.MOVING)
		
	# Visual feedback
	if is_sprinting && sensory_system && !is_moving:
		sensory_system.display_message("You prepare to run.")

# Check if can move (restraints, grabbed, etc)
func can_move() -> bool:
	# If being pulled/grabbed and force is too strong
	if pulled_by_entity != null and grab_state >= GrabState.AGGRESSIVE:
		var resist_check = perform_resist_check()
		if !resist_check:
			# Apply movement cooldown
			apply_movement_cooldown(1.0)
			return false
	
	# Check for restraints
	if status_effects.has("restrained"):
		# Emit a message that you can't move
		if sensory_system:
			sensory_system.display_message("You're restrained and can't move!")
		return false
	
	# Check for buckled state
	if status_effects.has("buckled"):
		return false
	
	return true

# Apply a movement cooldown without awaiting in the function
func apply_movement_cooldown(duration: float):
	movement_cooldown_active = true
	var timer = get_tree().create_timer(duration)
	timer.timeout.connect(func(): movement_cooldown_active = false)

# Process zero-g movement
func process_zero_g_movement(delta):
	# Process input for zero-G movement
	var input_dir = get_zero_g_input_direction()
	
	# Handle rotation in zero-G without changing position
	if input_dir != Vector2.ZERO:
		# Determine the facing direction from input
		var target_angle = input_dir.angle()
		
		# Convert to grid direction first (for 8-way movement)
		var grid_dir = convert_angle_to_grid_direction(target_angle)
		
		# Update character facing
		if grid_dir != Direction.NONE:
			current_direction = grid_dir
			update_sprite_system_direction(grid_dir)
		
		# Apply thrust if there's input and we can push off something
		if check_zero_g_push_possible():
			# Apply thrust in input direction
			velocity += input_dir * ZERO_G_THRUST * delta
			
			# Play push sound
			if audio_manager && Time.get_ticks_msec() * 0.001 - last_push_time > 0.5:
				audio_manager.play_positioned_sound("space_push", position, 0.2)
				last_push_time = Time.get_ticks_msec() * 0.001
		else:
			# Slight velocity adjustment with thrusters (limited control)
			velocity = velocity.lerp(velocity + input_dir * ZERO_G_THRUST * 0.2 * delta, ZERO_G_CONTROL_FACTOR)
			
			# Visual feedback for no push
			if Time.get_ticks_msec() * 0.001 - last_push_time > 1.0 && input_dir.length() > 0.5:
				if sensory_system:
					sensory_system.display_message("You need something to push against!")
					last_push_time = Time.get_ticks_msec() * 0.001
	
	# Apply velocity to position
	if velocity.length() > 0:
		# Apply damping (very small in space)
		velocity = velocity.lerp(Vector2.ZERO, ZERO_G_DAMPING * delta)
		
		# Limit max speed
		if velocity.length() > ZERO_G_MAX_SPEED:
			velocity = velocity.normalized() * ZERO_G_MAX_SPEED
		
		# Move position
		var old_position = position
		position += velocity * delta * TILE_SIZE  # Scale by tile size
		
		# Check for collision
		var collision = check_zero_g_collision()
		if collision.collided:
			# Handle collision - bounce or stop
			handle_zero_g_collision(collision, old_position)
		
		# Check if we've moved to a new tile
		var new_tile_pos = world_to_tile(position)
		if new_tile_pos != current_tile_position:
			# Handle tile transition
			handle_zero_g_tile_change(new_tile_pos)
		
		# Draw a visual trail if we're moving fast
		if velocity.length() > 2.0 && world && world.has_method("add_visual_effect"):
			if randf() < 0.2:  # Only add particles occasionally
				world.add_visual_effect("zero_g_trail", position, 0.5)
	
	# Apply input to velocity
	var input = get_normalized_input_direction()
	if input != Vector2i.ZERO:
		var input_vec = Vector2(input.x, input.y).normalized()
		
		# Check if we have something to push against
		if check_dense_object_nearby():
			# Can push against something
			velocity += input_vec * ZERO_G_THRUST * delta
			last_push_time = Time.get_ticks_msec() / 1000.0
			inertia_dir = velocity.normalized()
			
			# Cap max speed
			if velocity.length() > ZERO_G_MAX_SPEED:
				velocity = velocity.normalized() * ZERO_G_MAX_SPEED
				
			# Emit sound or effect for pushing off
			if audio_manager:
				audio_manager.play_positioned_sound("space_push", position, 0.2)
		else:
			# Nothing to push against, show warning
			if Time.get_ticks_msec() / 1000.0 - last_push_time > 1.0:  # Limit message frequency
				if sensory_system:
					sensory_system.display_message("You flail but have nothing to push against!")
	
	# Check for tile boundary crossing
	if velocity.length() > 0:
		var old_tile_pos = current_tile_position
		position += velocity * TILE_SIZE * delta
		
		# Check for tile boundary crossing
		var new_tile_pos = world_to_tile(position)
		if new_tile_pos != old_tile_pos:
			handle_zero_g_tile_transition(old_tile_pos, new_tile_pos)

# Handle receiving impulse from another entity in zero-G
func apply_zero_g_impulse(impulse: Vector2):
	if is_floating:
		# Apply the impulse based on mass
		velocity += impulse / mass
		
		# Limit max speed
		if velocity.length() > ZERO_G_MAX_SPEED * 1.5:
			velocity = velocity.normalized() * ZERO_G_MAX_SPEED * 1.5

# Get input direction specifically for zero-G movement
func get_zero_g_input_direction() -> Vector2:
	if !input_controller:
		return Vector2.ZERO
	
	var raw_input = input_controller.process_movement_input()
	
	if raw_input == null or raw_input.length() < 0.1:
		return Vector2.ZERO
	
	return raw_input.normalized()

# Convert an angle to the closest grid direction enum
func convert_angle_to_grid_direction(angle: float) -> int:
	# Normalize angle to 0-2PI range
	while angle < 0:
		angle += 2 * PI
	while angle >= 2 * PI:
		angle -= 2 * PI
	
	# Map angle to direction
	var direction = Direction.NONE
	
	# Using 45-degree sectors for 8-way direction
	if angle >= 7 * PI / 4 || angle < PI / 4:
		direction = Direction.EAST
	elif angle >= PI / 4 && angle < 3 * PI / 4:
		direction = Direction.SOUTH
	elif angle >= 3 * PI / 4 && angle < 5 * PI / 4:
		direction = Direction.WEST
	elif angle >= 5 * PI / 4 && angle < 7 * PI / 4:
		direction = Direction.NORTH
	
	return direction

# Check if we can push off something in zero-G
func check_zero_g_push_possible() -> bool:
	# Check surrounding tiles (4 directions)
	var check_offsets = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	
	var current_pos = world_to_tile(position)
	
	for offset in check_offsets:
		var check_pos = current_pos + offset
		
		# Check if there's a wall, door, or dense object
		if is_wall_at(check_pos, current_z_level) || is_closed_door_at(check_pos, current_z_level) || is_window_at(check_pos, current_z_level):
			return true
			
		# Check for dense entities
		if tile_occupancy_system && tile_occupancy_system.has_dense_entity_at(check_pos, current_z_level, self):
			return true
	
	# Check if current tile has a lattice (special structure that provides traction in space)
	if world && world.has_method("has_lattice_at") && world.has_lattice_at(current_pos, current_z_level):
		return true
	
	return false

# Check for collision in zero-G movement
func check_zero_g_collision() -> Dictionary:
	var result = {
		"collided": false,
		"position": Vector2.ZERO,
		"normal": Vector2.ZERO,
		"entity": null
	}
	
	var current_pos = world_to_tile(position)
	
	# Check all 8 surrounding tiles for walls, doors, windows
	var check_offsets = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)
	]
	
	# Calculate the character's bounding box (half a tile from center)
	var bounds_min = position - Vector2(TILE_SIZE * 0.4, TILE_SIZE * 0.4)
	var bounds_max = position + Vector2(TILE_SIZE * 0.4, TILE_SIZE * 0.4)
	
	for offset in check_offsets:
		var check_pos = current_pos + offset
		var tile_center = tile_to_world(check_pos)
		var tile_bounds_min = tile_center - Vector2(TILE_SIZE * 0.5, TILE_SIZE * 0.5)
		var tile_bounds_max = tile_center + Vector2(TILE_SIZE * 0.5, TILE_SIZE * 0.5)
		
		# Check if our bounds intersect with the tile bounds
		if bounds_max.x > tile_bounds_min.x && bounds_min.x < tile_bounds_max.x && bounds_max.y > tile_bounds_min.y && bounds_min.y < tile_bounds_max.y:
			
			# Check if this tile is solid
			if is_wall_at(check_pos, current_z_level) || is_closed_door_at(check_pos, current_z_level) || is_window_at(check_pos, current_z_level):
				
				# Calculate normal (direction from tile to character)
				var to_character = (position - tile_center).normalized()
				
				result.collided = true
				result.position = tile_center
				result.normal = to_character
				return result
			
			# Check for dense entities
			if tile_occupancy_system && tile_occupancy_system.has_dense_entity_at(check_pos, current_z_level, self):
				var entity = tile_occupancy_system.get_entity_at(check_pos, current_z_level)
				if entity && entity != self:
					# Calculate normal (direction from entity to character)
					var entity_pos = tile_to_world(check_pos)
					var to_character = (position - entity_pos).normalized()
					
					result.collided = true
					result.position = entity_pos
					result.normal = to_character
					result.entity = entity
					return result
	
	return result

# Handle collision in zero-G
func handle_zero_g_collision(collision: Dictionary, old_position: Vector2):
	if !collision.collided:
		return
	
	# Play collision sound
	if audio_manager:
		var volume = min(0.3 + (velocity.length() * 0.1), 0.8)
		audio_manager.play_positioned_sound("space_bump", position, volume)
	
	# Calculate bounce
	if collision.normal != Vector2.ZERO:
		# Reflect velocity around the normal vector and apply bounce factor
		velocity = velocity.bounce(collision.normal) * ZERO_G_BOUNCE_FACTOR
		
		# Move slightly away from collision to prevent sticking
		position = old_position + collision.normal * 1.0
	else:
		# Fallback - just reverse velocity
		velocity = -velocity * ZERO_G_BOUNCE_FACTOR
		position = old_position
	
	# Handle entity collision
	if collision.entity != null:
		# Transfer some momentum to the entity if it has the right methods
		if collision.entity.has_method("apply_zero_g_impulse"):
			var impulse = -collision.normal * velocity.length() * mass * 0.5
			collision.entity.apply_zero_g_impulse(impulse)
		
		# Apply damage based on velocity
		var impact_force = velocity.length()
		if impact_force > 4.0:
			var damage = (impact_force - 4.0) * 2.0
			
			# Damage to self
			take_damage(damage * 0.5, "blunt")
			
			# Damage to other entity
			if collision.entity.has_method("take_damage"):
				collision.entity.take_damage(damage, "blunt")
			
			# Show impact message
			if sensory_system:
				sensory_system.display_message("You slam into " + collision.entity.entity_name + "!")

# Handle changing tiles in zero-G
func handle_zero_g_tile_change(new_tile_pos: Vector2i):
	# Validate the new position
	if is_valid_tile(new_tile_pos, current_z_level):
		var old_tile_pos = current_tile_position
		previous_tile_position = current_tile_position
		current_tile_position = new_tile_pos
		
		# Update tile occupancy
		if tile_occupancy_system:
			tile_occupancy_system.move_entity(self, old_tile_pos, new_tile_pos, current_z_level)
		
		# Emit signals
		emit_signal("tile_changed", old_tile_pos, new_tile_pos)
		emit_signal("entity_moved", old_tile_pos, new_tile_pos, self)
		
		# Check new environment
		check_tile_environment()
		
		# Emit a quiet movement sound
		emit_footstep_sound(0.15)
	else:
		# Invalid tile, bounce back
		velocity = -velocity * 0.5

# Handle a tile transition in zero-g
func handle_zero_g_tile_transition(old_tile_pos, new_tile_pos):
	# Check for collision at the new tile
	var collision = check_collision(new_tile_pos, current_z_level)
	
	if collision != CollisionType.NONE:
		# Bounce off the obstacle with vector reflection
		position = tile_to_world(old_tile_pos)
		
		# Get the surface normal
		var normal = Vector2.ZERO
		if new_tile_pos.x > old_tile_pos.x:
			normal = Vector2(-1, 0)
		elif new_tile_pos.x < old_tile_pos.x:
			normal = Vector2(1, 0)
		elif new_tile_pos.y > old_tile_pos.y:
			normal = Vector2(0, -1)
		else:
			normal = Vector2(0, 1)
		
		# Reflect velocity around the normal vector and reduce by bounce factor
		velocity = velocity.bounce(normal) * ZERO_G_BOUNCE_FACTOR
		
		# Play collision sound/effect
		if audio_manager:
			audio_manager.play_positioned_sound("space_bump", position, 0.4)
		
		# Maybe take damage if going fast enough
		var impact_velocity = velocity.length()
		if impact_velocity > 5.0:
			var damage = (impact_velocity - 5.0) * 2.0
			take_damage(damage, "blunt")
		
		return
	
	# Valid movement to new tile
	previous_tile_position = current_tile_position
	current_tile_position = new_tile_pos
	
	# Update tile occupancy
	if tile_occupancy_system:
		tile_occupancy_system.move_entity(self, previous_tile_position, current_tile_position, current_z_level)
	
	# Emit signals
	emit_signal("tile_changed", previous_tile_position, current_tile_position)
	emit_signal("entity_moved", previous_tile_position, current_tile_position, self)
	
	# Check for environmental effects at new tile
	check_tile_environment()
	
	# Play movement sound
	emit_footstep_sound(0.2)  # Quieter in zero-g

# Check for dense objects nearby to push against
func check_dense_object_nearby() -> bool:
	# Check surrounding tiles (8 directions)
	var check_offsets = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)
	]
	
	for offset in check_offsets:
		var check_pos = current_tile_position + offset
		
		# Check if there's a wall or dense object
		if is_wall_at(check_pos, current_z_level):
			return true
		
		if is_closed_door_at(check_pos, current_z_level) or is_window_at(check_pos, current_z_level):
			return true
			
		# Check for dense entities
		if tile_occupancy_system and tile_occupancy_system.has_dense_entity_at(check_pos, current_z_level, self):
			return true
	
	# Check if current tile has a lattice (special structure that provides traction in space)
	if world and world.has_method("has_lattice_at") and world.has_lattice_at(current_tile_position, current_z_level):
		return true
	
	# Nothing to push against
	return false

# Process chance of slipping in space
func process_space_slipping() -> bool:
	# Skip if we're not moving
	if velocity.length() < 0.1:
		return false
	
	# Check if stunned (higher chance when stunned)
	var slip_chance = 5  # Base chance percentage
	if is_stunned:
		slip_chance *= 2
	
	# Check for magboots or similar effect
	if status_effects.has("magboots") and status_effects["magboots"]:
		slip_chance = 0  # No slipping with magboots
	
	# Roll for slip
	if randf() * 100 < slip_chance:
		# We slipped!
		if sensory_system:
			sensory_system.display_message("You slip in zero-g!")
		
		# Use inertia direction
		inertia_dir = velocity.normalized()
		return true
	
	return false

# Set gravity state
func set_gravity(has_gravity: bool):
	if has_gravity and is_floating:
		# Transitioning to gravity
		gravity_strength = 1.0
		is_floating = false
		
		# Ground velocity
		velocity = Vector2.ZERO
		
		# Signal transition
		emit_signal("stopped_floating")
		
		# Update state
		set_state(MovementState.IDLE)
	elif !has_gravity and !is_floating:
		# Transitioning to zero-g
		gravity_strength = 0.0
		is_floating = true
		
		# Inherit any movement momentum
		if is_moving:
			var direction = Vector2(target_tile_position - current_tile_position).normalized()
			velocity = Vector2(direction.x, direction.y) * 2.0  # Initial momentum
			
			# Cancel tile movement
			is_moving = false
			move_progress = 0.0
		
		# Signal transition
		emit_signal("began_floating")
		
		# Update state
		set_state(MovementState.FLOATING)

# Check void transition for zero-g
func check_void_transition():
	if world and world.has_method("is_space"):
		var is_space = world.is_space(current_tile_position, current_z_level)
		
		if is_space and !is_floating:
			# Entering zero-g
			set_gravity(false)
		elif !is_space and is_floating:
			# Exiting zero-g
			set_gravity(true)

# Set character state
func set_state(new_state: int):
	if new_state != current_state:
		var old_state = current_state
		current_state = new_state
		
		# Reset movement speed modifier when leaving CRAWLING state
		if old_state == MovementState.CRAWLING and new_state != MovementState.CRAWLING:
			print("GridMovementController: Resetting movement speed after crawling")
			movement_speed_modifier = 1.0  # Reset to default speed
		
		# Handle state-specific logic
		match new_state:
			MovementState.IDLE:
				# Ensure normal speed in IDLE
				if old_state == MovementState.CRAWLING:
					movement_speed_modifier = 1.0
				
			MovementState.MOVING:
				# Ensure normal speed in MOVING
				if old_state == MovementState.CRAWLING:
					movement_speed_modifier = 1.0
				
			MovementState.RUNNING:
				# Running uses its own speed (don't reset)
				pass
				
			MovementState.STUNNED:
				is_stunned = true
				
			MovementState.CRAWLING:
				# Only modify speed if actually lying down
				if is_lying:
					movement_speed_modifier = 0.5 * crawl_speed_multiplier
				
			MovementState.FLOATING:
				# Floating uses its own physics
				pass
		
		# Emit state change signal
		emit_signal("state_changed", old_state, new_state)
		
		# Debug state change
		print("GridMovementController: State changed from ", 
			  MovementState.keys()[old_state], " to ", 
			  MovementState.keys()[new_state], 
			  " - Speed modifier: ", movement_speed_modifier)

# Process pulling logic (when we're pulling someone)
func process_pulling(delta):
	if pulling_entity == null:
		return
	
	# Check if pulled entity is too far
	var pulled_pos = Vector2i.ZERO
	
	# Get pulled entity's position
	if pulling_entity.has("current_tile_position"):
		pulled_pos = pulling_entity.current_tile_position
	
	# Calculate distance
	var distance = (pulled_pos - current_tile_position).length()
	
	# If too far, break the pull
	if distance > 2.0:  # More than two tiles away
		stop_pulling()
		
		# Show message
		if sensory_system:
			sensory_system.display_message(pulling_entity.entity_name + " is too far away to pull!")
		
		return

# Process being pulled (when we're being pulled by someone)
func process_being_pulled(delta):
	# Check if we need to follow the puller
	if pulled_by_entity != null:
		var puller_pos = Vector2i.ZERO
		
		# Get puller's position
		if pulled_by_entity.has("current_tile_position"):
			puller_pos = pulled_by_entity.current_tile_position
		
		# Calculate distance
		var distance = (puller_pos - current_tile_position).length()
		
		# If too far, catch up
		if distance > 1.5:  # More than one tile away
			# Calculate direction to puller
			var dir_to_puller = (puller_pos - current_tile_position).normalized()
			var move_dir = Vector2i(round(dir_to_puller.x), round(dir_to_puller.y))
			
			# Try to move in that direction
			if !is_moving and !is_stunned:
				attempt_move(move_dir)

# Process grab effects during physics update
func process_grab_effects(delta):
	if grabbing_entity == null:
		return
	
	# Increment grab time
	grab_time += delta
	
	# Process effects based on grab state
	match grab_state:
		GrabState.NECK:
			# Slow stun buildup
			if grabbing_entity.has_method("add_stamina_loss"):
				grabbing_entity.add_stamina_loss(10 * delta)
			
			# Make it harder to speak
			if grabbing_entity.has_method("set_muffled"):
				grabbing_entity.set_muffled(true)
		
		GrabState.KILL:
			# Apply damage every second
			if fmod(grab_time, 1.0) < delta:
				if grabbing_entity.has_method("apply_damage"):
					grabbing_entity.apply_damage(2.0, "asphyxiation")
				
				# Play choking sound
				if audio_manager:
					audio_manager.play_positioned_sound("choking", position, 0.4)
			
			# Prevent speaking entirely
			if grabbing_entity.has_method("set_muffled"):
				grabbing_entity.set_muffled(true, 2.0)  # Completely muffled
			
			# Apply oxygen loss
			if grabbing_entity.has_method("reduce_oxygen"):
				grabbing_entity.reduce_oxygen(20 * delta)

# Signal handler for grabbed entity movement attempts
func _on_grabbed_movement_attempt(direction):
	# Only restrict movement for aggressive+ grabs
	if grab_state >= GrabState.AGGRESSIVE:
		# Calculate resist chance
		var resist_chance = 30 - (grab_state * 10)  # Lower chance at higher grab states
		
		# Check if they can move
		if randf() * 100 < resist_chance:
			# They can still move
			return
		
		# Stop the movement
		if grabbing_entity.has_method("cancel_movement"):
			grabbing_entity.cancel_movement()
		
		# Show message
		if sensory_system and fmod(grab_time, 1.0) < 0.1:  # Limit message frequency
			if grab_state == GrabState.NECK:
				sensory_system.display_message("You restrict their movement!")
			else:  # AGGRESSIVE
				sensory_system.display_message("You hold them in place!")

# Perform a resist check against being pulled/grabbed
func perform_resist_check() -> bool:
	if pulled_by_entity == null:
		return true
	
	# Calculate resistance chance based on stats
	var stat_modifier = 1.0
	var chance = 40 + (dexterity * 2) * stat_modifier
	
	# Send signal for UI feedback
	emit_signal("began_restraint_resist")
	
	# Check if we're successful
	if randf() * 100 < chance:
		# Break free!
		pulled_by_entity = null
		# Signal break free event
		emit_signal("broke_free")
		if sensory_system:
			sensory_system.display_message("You break free!")
		return true
	
	# Failed to break free
	if sensory_system:
		sensory_system.display_message("You struggle but can't break free!")
	return false
#endregion

#region INTERACTIONS AND ITEM MANAGEMENT
# Handle clicking on a world entity
func on_entity_clicked(entity, double_clicked = false):
	# Check if entity is in reach
	if world_interaction_system and world_interaction_system.has_method("can_reach"):
		if !world_interaction_system.can_reach(self, entity):
			# Show "too far away" message
			if sensory_system:
				sensory_system.display_message("That's too far away.")
			return false
	
	# Process the interaction based on entity type and intent
	return interact_with_entity(entity, double_clicked)

# Handle alt-click on tile
func handle_alt_tile_action(tile_coords, z_level):
	# Get tile data
	var tile_data = world.get_tile_data(tile_coords, z_level) if world else null
	if !tile_data:
		return
	
	# Alt-click on door to toggle
	if "door" in tile_data:
		if world and world.has_method("toggle_door"):
			world.toggle_door(tile_coords, z_level)
		return
	
	# Alt-click on window to knock
	if "window" in tile_data:
		if world and world.has_method("knock_window"):
			world.knock_window(tile_coords, z_level)
		return

# Throw an item at a tile
func throw_item_at_tile(item, tile_position):
	if !inventory_system or !item:
		print("GridMovementController: Cannot throw - missing inventory_system or item")
		return false
	
	# Convert tile position to world position
	var world_position = tile_to_world(tile_position)
	
	# Save thrower position BEFORE removing from inventory
	var thrower_position = self.global_position
	
	# Find which slot the item is in
	var slot = 0
	if inventory_system.has_method("get_item_slot"):
		slot = inventory_system.get_item_slot(item)
	
	# Remove item from inventory
	if slot != 0 and inventory_system.has_method("unequip_item"):
		inventory_system.unequip_item(slot)
	elif inventory_system.has_method("remove_item"):
		inventory_system.remove_item(item)
	else:
		print("GridMovementController: Cannot remove item from inventory!")
		return false
	
	# Add item to world
	var world_node = get_parent().get_node("World")
	if item.get_parent():
		item.get_parent().remove_child(item)
	world_node.add_child(item)
	
	# Make item visible and set initial position
	item.global_position = thrower_position
	item.visible = true
	
	# Check path for obstacles to find the final position
	var final_position = find_throw_landing_position(thrower_position, world_position)
	
	# Perform the throw based on what methods are available
	var success = false
	
	if item.has_method("throw_at_target"):
		item.throw_at_target(self, final_position)
		success = true
	elif item.has_method("enhanced_throw"):
		item.enhanced_throw(self, thrower_position, final_position)
		success = true
	elif item.has_method("throw"):
		var direction = (final_position - thrower_position).normalized()
		item.throw(self, direction)
		success = true
	else:
		# Last resort - just move the item to the destination
		item.global_position = final_position
		success = true
	
	# Play throw sound
	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager:
		audio_manager.play_positioned_sound("throw", self.position, 0.4)
	
	# Visual feedback
	if sensory_system:
		sensory_system.display_message("You throw " + (item.item_name if "item_name" in item else item.name) + "!")
	
	# Exit throw mode if throw was successful
	if success:
		exit_throw_mode()
		throw_mode = false
	
	return success

# Find the landing position for a thrown item by checking for obstacles
func find_throw_landing_position(start_pos, target_pos):
	# Convert positions to tile coordinates
	var start_tile = world_to_tile(start_pos)
	var end_tile = world_to_tile(target_pos)
	
	# Get tiles along the path using Bresenham's line algorithm
	var path_tiles = get_line_tiles(start_tile, end_tile)
	
	# Skip the starting tile (where the thrower is)
	if path_tiles.size() > 1:
		path_tiles.remove_at(0)
	
	# Check each tile for obstacles
	for tile_pos in path_tiles:
		if check_collision(tile_pos, current_z_level) != CollisionType.NONE:
			# We hit an obstacle, find the previous valid tile
			var index = path_tiles.find(tile_pos)
			if index > 0:
				# Return position of the tile before the obstacle
				var landing_tile = path_tiles[index - 1]
				return tile_to_world(landing_tile)
			else:
				# If the first tile is an obstacle (shouldn't happen since we removed it)
				return start_pos
	
	# No obstacles found, target is valid
	return target_pos

# Calculate throw path considering obstacles
func calculate_throw_path(start: Vector2i, end: Vector2i) -> Array:
	var path = []
	path.append(start)
	
	# Use Bresenham's line algorithm to trace path
	var x0 = start.x
	var y0 = start.y
	var x1 = end.x
	var y1 = end.y
	
	var dx = abs(x1 - x0)
	var dy = -abs(y1 - y0)
	var sx = 1 if x0 < x1 else -1
	var sy = 1 if y0 < y1 else -1
	var err = dx + dy
	
	while true:
		var current_pos = Vector2i(x0, y0)
		
		# If current position is not start, check for collision
		if current_pos != start:
			var collision = check_collision(current_pos, current_z_level)
			
			if collision != CollisionType.NONE:
				# Hit an obstacle, stop here
				break
		
		# Add current position to path
		if current_pos != start:
			path.append(current_pos)
		
		# Check if reached end
		if x0 == x1 and y0 == y1:
			break
		
		# Progress along line
		var e2 = 2 * err
		if e2 >= dy:
			if x0 == x1:
				break
			err += dy
			x0 += sx
		
		if e2 <= dx:
			if y0 == y1:
				break
			err += dx
			y0 += sy
	
	return path

# Called when a tile is clicked
func _on_tile_clicked(tile_coords, mouse_button, shift_pressed, ctrl_pressed, alt_pressed):
	# Convert tile coords to world position for facing
	var world_pos = tile_to_world(tile_coords)
	
	# First make the character face the clicked tile
	face_entity(world_pos)
	
	# Handle different click types on tiles
	match mouse_button:
		MOUSE_BUTTON_LEFT:
			if shift_pressed:
				# Examine the tile
				examine_tile(tile_coords, current_z_level)
			elif ctrl_pressed:
				# Pull or interact with object on tile
				var entity = get_entity_on_tile(tile_coords, current_z_level)
				if entity:
					if has_method("pull_entity"):
						pull_entity(entity)
			elif alt_pressed:
				# Alt action on tile (context dependent)
				handle_alt_tile_action(tile_coords, current_z_level)
			else:
				# In throw mode, throw at tile
				throw_item_at_tile(throw_target_item, tile_coords)
				exit_throw_mode()
		
		MOUSE_BUTTON_RIGHT:
			# Show context menu for tile
			handle_tile_context_menu(tile_coords, current_z_level)
		
		MOUSE_BUTTON_MIDDLE:
			if shift_pressed:
				# Point at tile
				point_to(Vector2(tile_coords.x * 32 + 16, tile_coords.y * 32 + 16))
			else:
				# Default middle-click tile action
				pass

# Point to a location (for Shift+Middle Click)
func point_to(position):
	# Create a pointing indicator
	if sensory_system:
		var direction = (position - self.position).normalized()
		var entity_name = entity_name if "entity_name" in self else "Someone"
		
		# Get direction text based on angle
		var dir_text = "somewhere"
		var angle = rad_to_deg(atan2(direction.y, direction.x))
		
		if angle > -22.5 and angle <= 22.5:
			dir_text = "east"
		elif angle > 22.5 and angle <= 67.5:
			dir_text = "southeast"
		elif angle > 67.5 and angle <= 112.5:
			dir_text = "south"
		elif angle > 112.5 and angle <= 157.5:
			dir_text = "southwest"
		elif angle > 157.5 or angle <= -157.5:
			dir_text = "west"
		elif angle > -157.5 and angle <= -112.5:
			dir_text = "northwest"
		elif angle > -112.5 and angle <= -67.5:
			dir_text = "north"
		elif angle > -67.5 and angle <= -22.5:
			dir_text = "northeast"
		
		sensory_system.display_message(entity_name + " points to the " + dir_text + ".")
		
		# Visual effect for pointing
		var effect_position = position
		if world and world.has_method("spawn_visual_effect"):
			world.spawn_visual_effect("point", effect_position, 1.0)
	
	return true

# Handle tile context menu
func handle_tile_context_menu(tile_coords, z_level):
	# Create context options for this tile
	var options = []
	
	# Add examine option
	options.append({
		"name": "Examine Tile",
		"icon": "examine",
		"action": "examine_tile",
		"params": {"position": tile_coords, "z_level": z_level}
	})
	
	# Check for doors at this tile
	var tile_data = world.get_tile_data(tile_coords, z_level) if world else null
	if tile_data and "door" in tile_data:
		var door = tile_data.door
		if door.closed:
			options.append({
				"name": "Open Door",
				"icon": "door_open",
				"action": "toggle_door",
				"params": {"position": tile_coords, "z_level": z_level}
			})
		else:
			options.append({
				"name": "Close Door",
				"icon": "door_close",
				"action": "toggle_door",
				"params": {"position": tile_coords, "z_level": z_level}
			})
			
		# Add lock option if applicable
		if "can_lock" in door and door.can_lock:
			var lock_text = "Lock Door" if !door.locked else "Unlock Door"
			options.append({
				"name": lock_text,
				"icon": "lock",
				"action": "toggle_lock",
				"params": {"position": tile_coords, "z_level": z_level}
			})
	
	# Check for windows
	if tile_data and "window" in tile_data:
		options.append({
			"name": "Knock on Window",
			"icon": "knock",
			"action": "knock_window",
			"params": {"position": tile_coords, "z_level": z_level}
		})
	
	# Show the context menu
	if world and "context_interaction_system" in world:
		world.context_interaction_system.show_context_menu(options, get_viewport().get_mouse_position())

func _on_entity_clicked(entity, mouse_button, shift_pressed, ctrl_pressed, alt_pressed):
	# No interaction if we're too far away
	if global_position.distance_to(entity.global_position) > interaction_range:
		return
	
	# Determine what to do based on modifiers
	if ctrl_pressed:
		# Ctrl-click is examine
		examine_atom(entity)
		return
	
	if mouse_button == MOUSE_BUTTON_LEFT:
		# Check if this is an item that can be picked up
		if "pickupable" in entity and entity.pickupable and !entity.has_flag(entity.item_flags, entity.ItemFlags.IN_INVENTORY):
			# Try to pick up the item
			if inventory_system:
				inventory_system.pick_up_item(entity)
				return
		
		# If not picked up, call interact instead
		if entity.has_method("interact"):
			# Pass the parent entity (the character) instead of the controller
			entity.interact(self)
	
	# Right-click behavior
	elif mouse_button == MOUSE_BUTTON_RIGHT:
		# Let the click system show a radial menu
		if get_parent().has_node("World/ClickSystem"):
			var click_system = get_parent().get_node("World/ClickSystem")
			click_system.show_radial_menu(entity, get_viewport().get_mouse_position())

func examine_atom(atom):
	if atom.has_method("examine"):
		var examine_text = atom.examine(self)
		
		if has_node("../PlayerUI"):
			var player_ui = get_node("../PlayerUI")
			if player_ui.has_method("show_notification"):
				player_ui.show_notification(examine_text)
		
		# Print to console for debugging
		print("Examining: ", atom.name, " - ", examine_text)

# Examine a tile
func examine_tile(tile_position, z_level):
	if !world:
		return
	
	var tile_data = world.get_tile_data(tile_position, z_level)
	if !tile_data:
		return
	
	var description = "You see nothing special."
	
	# Generate description based on tile components
	if "door" in tile_data:
		description = "A door. It appears to be " + ("closed" if tile_data.door.closed else "open") + "."
		
		if "locked" in tile_data.door and tile_data.door.locked:
			description += " It seems to be locked."
			
		if "broken" in tile_data.door and tile_data.door.broken:
			description += " It looks broken."
	
	elif "window" in tile_data:
		description = "A window made of glass."
		
		if "reinforced" in tile_data.window and tile_data.window.reinforced:
			description += " It appears to be reinforced."
			
		if "health" in tile_data.window and tile_data.window.health < tile_data.window.max_health:
			description += " It has some cracks."
	
	elif "floor" in tile_data:
		description = "A " + tile_data.floor.type + " floor."
	
	elif "wall" in tile_data:
		description = "A solid wall made of " + tile_data.wall.material + "."
	
	# Display the description
	if interaction_system:
		interaction_system.emit_signal("examine_result", {"tile_position": tile_position}, description)

# Handle interaction with a building or structure
func interact_with_building(building):
	# Get active item in case we need it for the interaction
	var active_item = get_active_item()
	
	# Check if building has a custom interaction method
	if building.has_method("interact"):
		return building.interact(self)
	
	# Check for special building types
	if "building_type" in building:
		match building.building_type:
			"door":
				return toggle_door(building)
			"vendor":
				return use_vendor(building)
			"terminal":
				return use_terminal(building)
			"medical":
				return use_medical_machine(building)
			"power":
				return toggle_power(building)
			
	# Handle generic building interactions based on intent
	match intent:
		Intent.HELP:
			# Use building or active item on building
			if active_item and building.has_method("attackby"):
				return building.attackby(active_item, self)
			elif building.has_method("use"):
				return building.use(self)
		Intent.DISARM:
			# Try to disable/deactivate building
			if building.has_method("deactivate"):
				return building.deactivate(self)
		Intent.GRAB:
			# Try to pull/drag building if it's movable
			if building.has_method("can_be_pulled") and building.can_be_pulled():
				return pull_entity(building)
		Intent.HARM:
			# Attack building with active item or bare hands
			if active_item and active_item.has_method("attack"):
				return active_item.attack(building, self)
			elif building.has_method("take_damage"):
				building.take_damage(5.0, "brute", "melee", true, 0.0, self)
				if sensory_system:
					sensory_system.display_message("You hit " + building.obj_name + ".")
				return true
	
	# Default message if no valid interaction
	if sensory_system:
		sensory_system.display_message("You don't know how to interact with this.")
	
	return false

# High-level interaction logic
func interact_with_entity(entity, double_clicked = false):
	# Get active item
	var active_item = get_active_item()
	
	# NEW: Check if entity is a building
	if ("entity_type" in entity and entity.entity_type == "building") or ("obj_flags" in entity and entity.has_flag(entity.obj_flags, entity.ObjectFlags.BLOCKS_CONSTRUCTION)):
		return interact_with_building(entity)
	
	# If target is an item and we're in HELP or GRAB intent, prioritize pickup
	if entity.has_method("entity_type") and entity.entity_type == "item" and (intent == Intent.HELP or intent == Intent.GRAB):
		return try_pick_up_item(entity)
	
	# If in throw mode and have an active item, throw at target
	if throw_mode and active_item:
		return throw_item_at(entity)
	
	# Otherwise, process normally based on intent
	return determine_entity_interaction(entity, active_item)

# Toggle door open/closed
func toggle_door(door):
	if door.has_method("toggle"):
		door.toggle(self)
		return true
	elif "opened" in door:
		door.opened = !door.opened
		return true
	return false

# Use vendor machines like the medical vendor
func use_vendor(vendor):
	if vendor.has_method("interact"):
		return vendor.interact(self)
	return false

# Use computer terminals
func use_terminal(terminal):
	if terminal.has_method("interact"):
		return terminal.interact(self)
	return false

# Use medical equipment
func use_medical_machine(machine):
	if machine.has_method("interact"):
		return machine.interact(self)
	return false

# Toggle power on machinery
func toggle_power(machine):
	if machine.has_method("toggle_power"):
		return machine.toggle_power(self)
	elif "powered" in machine:
		machine.powered = !machine.powered
		
		# Show feedback message
		if sensory_system:
			var status = "on" if machine.powered else "off"
			sensory_system.display_message("You turn " + machine.obj_name + " " + status + ".")
		return true
	return false

# Method to determine the correct interaction with an entity
func determine_entity_interaction(target, active_item = null):
	# Use the intent system if available
	var intent_system = get_node_or_null("IntentSystem")
	if intent_system:
		return intent_system.process_interaction(target)
	# Check if the target is an item
	if ("entity_type") in target and target.entity_type == "item":
		# For items, prioritize pickup when intent is HELP
		if intent == Intent.HELP: # HELP intent
			return interact_with_item(target)
		elif intent == Intent.GRAB: # GRAB intent
			return interact_with_item(target)
		elif intent == Intent.HARM and active_item: # HARM intent with item
			# Use active item on target
			if world_interaction_system and world_interaction_system.has_method("handle_use_item_on"):
				return world_interaction_system.handle_use_item_on(self, target, active_item)
		elif intent == Intent.HARM: # HARM intent without item
			# Attack bare-handed
			if world_interaction_system and world_interaction_system.has_method("handle_attack"):
				return world_interaction_system.handle_attack(self, target)
	else:
		# For non-items, process differently based on intent
		if intent == Intent.HELP: # HELP intent
			if active_item:
				# Use item on target
				if world_interaction_system and world_interaction_system.has_method("handle_use_item_on"):
					return world_interaction_system.handle_use_item_on(self, target, active_item)
			else:
				# Use target
				if world_interaction_system and world_interaction_system.has_method("handle_use"):
					return world_interaction_system.handle_use(self, target)
		elif intent == Intent.DISARM: # DISARM intent
			if world_interaction_system and world_interaction_system.has_method("handle_disarm"):
				return world_interaction_system.handle_disarm(self, target)
			else:
				return disarm_entity(target)
		elif intent == Intent.GRAB: # GRAB intent
			if world_interaction_system and world_interaction_system.has_method("handle_grab"):
				return world_interaction_system.handle_grab(self, target)
			else:
				return grab_entity(target)
		elif intent == Intent.HARM: # HARM intent
			if world_interaction_system and world_interaction_system.has_method("handle_attack"):
				return world_interaction_system.handle_attack(self, target, active_item)
			else:
				# Basic attack implementation
				if active_item and active_item.has_method("attack"):
					return active_item.attack(target, self)
				elif target.has_method("apply_damage"):
					# Apply some basic unarmed damage
					var zone = get_target_zone()
					var damage = 5.0  # Base unarmed damage
					
					# Apply zone effects/multipliers
					var effects = get_zone_effects(zone)
					if effects.has("damage_multiplier"):
						damage *= effects.damage_multiplier
					
					# Apply damage
					if target.has_method("apply_zone_damage"):
						target.apply_zone_damage(zone, damage, "blunt", self)
					else:
						target.apply_damage(damage, "blunt")
					
					# Apply additional zone effects
					apply_zone_effects(target, damage, zone)
					
					# Play attack sound
					if audio_manager:
						audio_manager.play_positioned_sound("punch", position, 0.5)
					
					# Send message
					if sensory_system:
						sensory_system.display_message("You punch " + target.entity_name + " in the " + zone + "!")
					
					return true
	
	return false

# Method to handle interaction with items - prioritizing pickup over use
func interact_with_item(item):
	# Check if item is pickupable
	if item.has("pickupable") and item.pickupable:
		return try_pick_up_item(item)
	
	# If item is not pickupable or pickup failed, try using it
	if item.has_method("use"):
		return item.use(self)
	
	return false

# Get the currently active item
func get_active_item():
	# If we have a dedicated inventory system node, use that
	if inventory_system and inventory_system.has_method("get_active_item"):
		return inventory_system.get_active_item()
	
	# Fallback implementation
	if held_items.size() > active_hand_index and held_items[active_hand_index] != null:
		return held_items[active_hand_index]
	
	return null

# Swap active hand
func swap_active_hand():
	active_hand_index = 1 - active_hand_index  # Toggle between 0 and 1
	
	# Get the item in the current active hand
	var active_item = get_active_item()
	
	# Emit signal for UI updates
	emit_signal("active_hand_changed", active_hand_index, active_item)
	
	# Send message
	if sensory_system:
		var hand_name = "right" if active_hand_index == 0 else "left"
		if active_item:
			sensory_system.display_message("You switch to your " + hand_name + " hand (" + active_item.name + ").")
		else:
			sensory_system.display_message("You switch to your " + hand_name + " hand.")
	
	# Return the new active item for convenience
	return active_item

# Drop the active item
func drop_active_item(throw_force: float = 0.0):
	var active_item = get_active_item()
	
	if !active_item:
		return false
	
	print("GridMovementController: Dropping active item: " + active_item.name)
	
	# Calculate drop position and direction
	var drop_dir = get_drop_direction()
	var drop_pos = self.global_position + drop_dir * 32.0 * 0.5  # Half a tile away
	
	# Prepare item for dropping
	active_item.global_position = drop_pos
	
	# Get inventory system
	if inventory_system and inventory_system.has_method("drop_item"):
		# Get which hand the item is in
		var slot = 0  # Default to NONE (0)
		
		# Use inventory_system's enum values
		if inventory_system.get_item_in_slot(inventory_system.EquipSlot.LEFT_HAND) == active_item:
			slot = inventory_system.EquipSlot.LEFT_HAND
		elif inventory_system.get_item_in_slot(inventory_system.EquipSlot.RIGHT_HAND) == active_item:
			slot = inventory_system.EquipSlot.RIGHT_HAND
		
		if slot == 0:  # If still NONE
			# Try to find the item in any slot
			slot = inventory_system.get_item_slot(active_item)
			
		# If throwing, apply throw physics
		if throw_force > 0.0:
			# Will need to have removed from inventory first
			inventory_system.unequip_item(slot)
			
			# Apply throw force
			if active_item.has_method("apply_throw_force"):
				active_item.apply_throw_force(drop_dir, throw_force * 100.0, self)
			else:
				# Fallback to basic throw
				active_item.throw(self, drop_dir)
			
			# Play throw sound
			var audio_manager = get_node_or_null("/root/AudioManager")
			if audio_manager:
				audio_manager.play_positioned_sound("throw", self.position, 0.4)
		else:
			# Normal drop - use the slot we found
			var success = false
			if slot != 0:  # Not NONE
				success = inventory_system.drop_item(slot)
			else:
				success = inventory_system.drop_item(active_item)
			
			if !success:
				print("GridMovementController: Failed to drop item")
				return false
		
		# Play drop sound if not thrown
		if throw_force <= 0.0:
			var audio_manager = get_node_or_null("/root/AudioManager")
			if audio_manager:
				audio_manager.play_positioned_sound("drop", self.position, 0.3)
		
		# Send message
		if sensory_system:
			var action = "drop" if throw_force <= 0.0 else "toss"
			sensory_system.display_message("You " + action + " " + active_item.item_name + ".")
		
		# Emit signal
		emit_signal("dropped_item", active_item)
		
		# Force refresh UI
		var ui = self.get_node_or_null("PlayerUI")
		if ui and ui.has_method("force_ui_refresh"):
			ui.force_ui_refresh()
		
		print("GridMovementController: Item successfully dropped/thrown")
		return true
	
	return false

# Calculate drop direction based on character facing
func get_drop_direction() -> Vector2:
	# Default to dropping in front
	var drop_dir = Vector2.DOWN
	
	# Use character direction if available
	match current_direction:
		Direction.NORTH:
			drop_dir = Vector2(0, -1)
		Direction.EAST:
			drop_dir = Vector2(1, 0)
		Direction.SOUTH:
			drop_dir = Vector2(0, 1)
		Direction.WEST:
			drop_dir = Vector2(-1, 0)
		Direction.NORTHEAST:
			drop_dir = Vector2(1, -1).normalized()
		Direction.SOUTHEAST:
			drop_dir = Vector2(1, 1).normalized()
		Direction.SOUTHWEST:
			drop_dir = Vector2(-1, 1).normalized()
		Direction.NORTHWEST:
			drop_dir = Vector2(-1, -1).normalized()
	
	return drop_dir

# Try to pick up an item
func try_pick_up_item(item):
	print("GridMovementController: Attempting to pick up item:", item.name if item else "Unknown")
	
	if !item:
		print("GridMovementController: Item is null!")
		return false
	
	# Make sure we have a valid inventory system
	if !find_inventory_system():
		if sensory_system:
			sensory_system.display_message("ERROR: No inventory system found!")
		return false
	
	# Check if item is pickupable
	if !("pickupable" in item and item.pickupable):
		if sensory_system:
			sensory_system.display_message("You can't pick that up.")
			print("GridMovementController: Item is not pickupable")
			return false
	
	# Check distance
	var distance = self.position.distance_to(item.position)
	if distance > PICKUP_RANGE * 32:  # Convert tiles to pixels
		if sensory_system:
			sensory_system.display_message("That's too far away.")
			print("GridMovementController: Item too far away")
			return false
	
	# Face toward the item before picking up
	face_entity(item)
	
	# Now try to pick up the item using inventory system
	if inventory_system.has_method("pick_up_item"):
		print("GridMovementController: Calling inventory_system.pick_up_item")
		var success = inventory_system.pick_up_item(item)
	  
		if success:
			# Play pickup sound
			var audio_manager = get_node_or_null("/root/AudioManager")
			if audio_manager:
				audio_manager.play_positioned_sound("pickup", position, 0.3)
		
			# Send message
			if sensory_system:
				sensory_system.display_message("You pick up " + item.item_name + ".")
		
			# Emit signal
			emit_signal("picked_up_item", item)
			
			# Force refresh UI
			var ui = self.get_node_or_null("PlayerUI")
			if ui:
				if ui.has_method("force_ui_refresh"):
					ui.force_ui_refresh()
				elif ui.has_method("update_all_slots"):
					ui.update_all_slots()
					ui.update_active_hand()
		
			# UI notification
			var ui_integration = self.get_node_or_null("UIIntegration")
			if ui_integration and ui_integration.has_method("show_notification"):
				ui_integration.show_notification("Picked up " + item.item_name, "info")
		
			return true
		else:
			# Failed to pick up - hands probably full
			if sensory_system:
				sensory_system.display_message("Your hands are full!")
			return false
	else:
		print("GridMovementController: ERROR - inventory_system doesn't have pick_up_item method!")
		return false

# Try to pick up the nearest highlighted item
func try_pickup_nearest_item():
	if !inventory_system:
		return false
	
	var nearest_item = null
	var nearest_distance = PICKUP_RANGE * 32  # Convert tiles to pixels - max range
	
	# Get all items in a radius
	var nearby_items = get_items_in_radius(self.position, nearest_distance)
	
	# Find closest pickupable item
	for item in nearby_items:
		if !is_instance_valid(item):
			continue
		
		if !("pickupable" in item and item.pickupable):
			continue
			
		var distance = self.position.distance_to(item.position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_item = item
	
	# If found, pick it up
	if nearest_item:
		return try_pick_up_item(nearest_item)
	else:
		if sensory_system:
			sensory_system.display_message("There's nothing nearby to pick up.")
		return false

# Get all items in a radius
func get_items_in_radius(center: Vector2, radius: float) -> Array:
	var items = []
	
	# First try using the world system
	if world and world.has_method("get_entities_in_radius"):
		var entities = world.get_entities_in_radius(center, radius, current_z_level)
		
		# Filter to only include items
		for entity in entities:
			if "entity_type" in entity and entity.entity_type == "item":
				items.append(entity)
	else:
		# Fallback - get all items in the scene
		var all_items = get_tree().get_nodes_in_group("items")
		
		# Filter by distance
		for item in all_items:
			if item.global_position.distance_to(center) <= radius:
				items.append(item)
	
	return items

# Attack self (use held item on self)
func attack_self():
	var active_item = get_active_item()
	
	if active_item:
		# Try to use item on self
		if active_item.has_method("use_on_self"):
			active_item.use_on_self(self)
			return true
		
		# Display message
		if sensory_system:
			sensory_system.display_message("You can't use that on yourself.")
	else:
		# No item, default self-interaction
		if sensory_system:
			sensory_system.display_message("You pat yourself down.")
	
	return false

# Toggle throw mode
func toggle_throw_mode():
	print("GridMovementController: toggle_throw_mode called, current state:", throw_mode)
	
	# Check cooldown
	if throw_toggle_cooldown > 0:
		return false
	
	# Make sure we have a valid inventory system
	if !find_inventory_system():
		if sensory_system:
			sensory_system.display_message("ERROR: No inventory system found!")
		return false
	
	# Toggle the base throw mode flag
	throw_mode = !throw_mode
	
	# Get active item for potential throwing
	var active_item = null
	if inventory_system and inventory_system.has_method("get_active_item"):
		active_item = inventory_system.get_active_item()
	else:
		# Direct inventory checking fallback
		if inventory_system:
			var active_hand = inventory_system.active_hand
			active_item = inventory_system.get_item_in_slot(active_hand)
	
	if throw_mode:
		# Don't enter throw mode if no item
		if active_item == null:
			throw_mode = false
			if sensory_system:
				sensory_system.display_message("You have nothing to throw!")
			return false
		
		# Set throw mode active and store target item
		is_throw_mode_active = true
		throw_target_item = active_item
		
		# Visual indicator that throw mode is active
		if sensory_system:
			sensory_system.display_message("You prepare to throw " + active_item.name + ".")
		
		# Create trajectory visualization
		update_throw_trajectory()
		
		# Update cursor if possible
		var cursor_controller = get_parent().get_node_or_null("CursorController")
		if cursor_controller and cursor_controller.has_method("set_cursor_mode"):
			cursor_controller.set_cursor_mode("throw")
		
		# Notify UI
		if "throw_mode" in get_parent():
			get_parent().throw_mode = true
		
		# Create a subtle highlight effect on the item
		if active_item.has_method("set_highlighted"):
			active_item.set_highlighted(true)
		elif "set_highlighted" in active_item:
			active_item.set_highlighted(true)
		
		# Check if the throw_target_item is still valid
		if !is_instance_valid(throw_target_item):
			exit_throw_mode()
			throw_mode = false
			return false
		
		# Set cooldown
		throw_toggle_cooldown = throw_cooldown_duration
		
		return true
	else:
		# Exit throw mode
		exit_throw_mode()
	
	# Set cooldown
	throw_toggle_cooldown = throw_cooldown_duration
	
	return throw_mode

# Exit throw mode
func exit_throw_mode():
	if !is_throw_mode_active:
		return
	
	print("GridMovementController: exit_throw_mode called")
	is_throw_mode_active = false
	throw_mode = false  # Make sure the main flag is reset too
	
	# Remove highlight from target item
	if throw_target_item:
		if throw_target_item.has_method("set_highlighted"):
			throw_target_item.set_highlighted(false)
		elif "set_highlighted" in throw_target_item:
			throw_target_item.set_highlighted(false)
	
	throw_target_item = null
	
	# Update entity throw mode flag
	if "throw_mode" in get_parent():
		get_parent().throw_mode = false
	
	# Clear trajectory visualization
	emit_signal("throw_trajectory_updated", [])
	
	# Reset cursor if possible
	var cursor_controller = get_parent().get_node_or_null("CursorController")
	if cursor_controller and cursor_controller.has_method("set_cursor_mode"):
		cursor_controller.set_cursor_mode("default")
	
	# Message
	if sensory_system:
		sensory_system.display_message("You relax your throwing arm.")

# Update throw trajectory visualization
func update_throw_trajectory():
	if !is_throw_mode_active or !throw_target_item:
		print("GridMovementController: Not updating trajectory - throw mode inactive or no item")
		return
	
	print("GridMovementController: Updating throw trajectory")
	
	# Get mouse position
	var mouse_pos = get_viewport().get_mouse_position()
	var mouse_world_pos = get_global_mouse_position()
	
	# Get maximum throw distance with improved stats integration
	var max_throw_dist = 10 * 32  # Default: 10 tiles (32 pixels per tile)
	
	# Get strength modifier from Stats System
	var strength_modifier = 1.0
	var stats_system = get_parent().get_node_or_null("StatsSystem")
	if stats_system and stats_system.has_method("get_throw_strength_multiplier"):
		strength_modifier = stats_system.get_throw_strength_multiplier()
	
	# Adjust throw distance by strength with minimum threshold
	max_throw_dist *= max(strength_modifier, 0.5)  # Ensure minimum throw distance
	
	# Apply item mass penalty with better scaling
	var mass_penalty = 1.0
	if "mass" in throw_target_item and throw_target_item.mass > 0:
		# More gradual penalty formula - lighter penalty for normal items
		mass_penalty = clamp(1.0 - (throw_target_item.mass - 1.0) * 0.05, 0.2, 1.0)
	
	# Scale throw distance by mass
	max_throw_dist *= mass_penalty
	
	# Apply item's own throw range multiplier if it exists
	if "throw_range_multiplier" in throw_target_item:
		max_throw_dist *= throw_target_item.throw_range_multiplier
	
	# Check if item has its own max throw range
	if "throw_range" in throw_target_item and throw_target_item.throw_range > 0:
		var item_max_dist = throw_target_item.throw_range * 32
		max_throw_dist = min(max_throw_dist, item_max_dist)
	
	# Calculate direction and distance
	var direction = (mouse_world_pos - get_parent().position).normalized()
	var distance = get_parent().position.distance_to(mouse_world_pos)
	
	# Limit to max distance
	if distance > max_throw_dist:
		mouse_world_pos = get_parent().position + direction * max_throw_dist
	
	# Check for collisions and get final position
	var final_position = check_throw_path(get_parent().position, mouse_world_pos)
	
	# Calculate trajectory points with improved arc
	var trajectory = []
	var start_pos = get_parent().position
	var end_pos = final_position
	
	# Create a curved arc for visualization
	var segments = 20
	var arc_height = min(distance * 0.2, 32.0)  # Arc height proportional to distance, but capped
	
	for i in range(segments + 1):
		var t = float(i) / segments
		
		# Calculate point along curve (parabolic arc)
		var x = lerp(start_pos.x, end_pos.x, t)
		var y = lerp(start_pos.y, end_pos.y, t)
		
		# Add height using a parabola: h(t) = 4ht(1-t) where h is max height
		var height_offset = 4.0 * arc_height * t * (1.0 - t)
		
		# Calculate direction perpendicular to throw (for 2D this is just the y component)
		var perp_y = -1.0  # Up direction
		
		# Apply height in the perpendicular direction
		y += perp_y * height_offset
		
		trajectory.append(Vector2(x, y))
	
	# Emit trajectory updated signal
	emit_signal("throw_trajectory_updated", trajectory)
	print("GridMovementController: Trajectory updated with", trajectory.size(), "points")

# Check throw path for collisions
func check_throw_path(start_pos: Vector2, end_pos: Vector2) -> Vector2:
	# Convert positions to tile coordinates
	var start_tile = world_to_tile(start_pos)
	var end_tile = world_to_tile(end_pos)
	
	# Get tiles along the path using Bresenham's line algorithm
	var path_tiles = get_line_tiles(start_tile, end_tile)
	
	# Skip the starting tile (where the thrower is)
	if path_tiles.size() > 1:
		path_tiles.remove_at(0)
	
	# Check each tile for obstacles
	for tile_pos in path_tiles:
		# Check for walls
		if world and world.has_method("is_wall_at") and world.is_wall_at(tile_pos, current_z_level):
			# Wall found, use previous position
			var index = path_tiles.find(tile_pos)
			if index > 0:
				# Return the position of the tile before the wall
				var landing_tile = path_tiles[index - 1]
				return tile_to_world(landing_tile)
			else:
				# Can't throw if first tile is a wall (shouldn't happen since we removed first tile)
				return start_pos
		
		# Check for closed doors
		if world and world.has_method("is_closed_door_at") and world.is_closed_door_at(tile_pos, current_z_level):
			# Door found, use previous position
			var index = path_tiles.find(tile_pos)
			if index > 0:
				var landing_tile = path_tiles[index - 1]
				return tile_to_world(landing_tile)
			else:
				return start_pos
		
		# Check for windows
		if world and world.has_method("is_window_at") and world.is_window_at(tile_pos, current_z_level):
			# Window found, use previous position
			var index = path_tiles.find(tile_pos)
			if index > 0:
				var landing_tile = path_tiles[index - 1]
				return tile_to_world(landing_tile)
			else:
				return start_pos
		
		# Check for dense entities that would block the throw
		if tile_occupancy_system and tile_occupancy_system.has_dense_entity_at(tile_pos, current_z_level, get_parent()):
			# Dense entity found, use previous position
			var index = path_tiles.find(tile_pos)
			if index > 0:
				var landing_tile = path_tiles[index - 1]
				return tile_to_world(landing_tile)
			else:
				return start_pos
	
	# No collision found, return original end position
	return end_pos

# Throw current active item at a target
func throw_item_at(target):
	var active_item = get_active_item()
	
	if active_item == null:
		if sensory_system:
			sensory_system.display_message("You have nothing to throw!")
		return false
	
	# Calculate direction and distance
	var target_pos = Vector2i.ZERO
	
	if ("current_tile_position") in target:
		target_pos = target.current_tile_position
	elif target.has_method("global_position"):
		target_pos = world_to_tile(target.global_position)
	else:
		target_pos = world_to_tile(target.position)
	
	var direction = target_pos - current_tile_position
	var distance = direction.length()
	
	# Check maximum throw distance based on stats and item weight
	var max_distance = 5.0  # Base throw distance
	
	# Adjust for item weight
	if ("weight") in active_item:
		max_distance = max(1.0, max_distance - (active_item.weight / 10.0))
	
	# Adjust for stats
	max_distance *= (throw_power * (1.0 + (dexterity / 20.0)))
	
	# Check if target is within throwing range
	if distance > max_distance:
		if sensory_system:
			sensory_system.display_message("That's too far to throw!")
		return false
	
	# Drop item first
	drop_active_item()
	
	# Adjust throw trajectory for obstacles
	var throw_path = calculate_throw_path(current_tile_position, target_pos)
	
	# If no valid path, item just drops at feet
	if throw_path.size() <= 1:
		if sensory_system:
			sensory_system.display_message("You fumble the throw!")
		return true
	
	# Determine final landing position
	var landing_pos = throw_path[throw_path.size() - 1]
	
	# Move item to landing position
	if world and world.has_method("spawn_item_at"):
		world.spawn_item_at(active_item, landing_pos, current_z_level)
	
	# Play throw sound
	if audio_manager:
		audio_manager.play_positioned_sound("throw", position, 0.4)
	
	# Send message
	if sensory_system:
		sensory_system.display_message("You throw " + active_item.name + "!")
	
	# Exit throw mode
	throw_mode = false
	
	# If item hits someone, apply effects
	var entity_at_landing = null
	if tile_occupancy_system:
		entity_at_landing = tile_occupancy_system.get_entity_at(landing_pos, current_z_level)
	
	if entity_at_landing and entity_at_landing != self:
		# Play hit sound
		if audio_manager:
			audio_manager.play_positioned_sound("throw_hit", tile_to_world(landing_pos), 0.5)
		
		# Apply damage if appropriate
		if active_item.has("throw_damage"):
			var damage = active_item.throw_damage
			var damage_type = "blunt"
			
			if active_item.has("throw_damage_type"):
				damage_type = active_item.throw_damage_type
			
			# Apply damage to target
			if entity_at_landing.has_method("take_damage"):
				entity_at_landing.take_damage(damage, damage_type)
		
		# Send message
		if sensory_system:
			sensory_system.display_message("The " + active_item.name + " hits " + entity_at_landing.entity_name + "!")
	
	return true

# Throw an item at a position
func throw_item_at_position(item, world_position):
	if !item:
		return false
		
	if !inventory_system:
		# Try to find it
		inventory_system = get_node_or_null("InventorySystem")
		if !inventory_system:
			return false
	
	# Calculate throw direction
	var direction = (world_position - self.global_position).normalized()
	
	# Face toward the throw direction
	face_entity(world_position)
	
	# IMPORTANT: Save global position BEFORE removing from inventory
	var original_global_position = self.global_position
	
	# Get which slot the item is in
	var slot = 0
	if inventory_system.has_method("get_item_slot"):
		slot = inventory_system.get_item_slot(item)
	
	# Remove from inventory first - CRUCIAL STEP
	if inventory_system.has_method("unequip_item") and slot != 0:
		inventory_system.unequip_item(slot)
	elif inventory_system.has_method("remove_item"):
		inventory_system.remove_item(item)
	
	# Now handle the throw itself with the EXACT target world position
	var throw_success = false
	
	if item.has_method("throw_at_target"):
		# Pass the exact world position without modifications
		item.throw_at_target(self, world_position)
		throw_success = true
	elif item.has_method("throw"):
		item.throw(self, direction)
		throw_success = true
	
	# Play throw sound if successful
	if throw_success:
		var audio_manager = get_node_or_null("/root/AudioManager")
		if audio_manager:
			audio_manager.play_positioned_sound("throw", get_parent().position, 0.4)
	
	return throw_success

# Bresenham's line algorithm to get tiles along a line
func get_line_tiles(start: Vector2i, end: Vector2i) -> Array:
	var tiles = []
	
	var x0 = start.x
	var y0 = start.y
	var x1 = end.x
	var y1 = end.y
	
	var dx = abs(x1 - x0)
	var dy = abs(y1 - y0)
	var sx = 1 if x0 < x1 else -1
	var sy = 1 if y0 < y1 else -1
	var err = dx - dy
	
	tiles.append(Vector2i(x0, y0))
	
	while x0 != x1 or y0 != y1:
		var e2 = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy
		
		tiles.append(Vector2i(x0, y0))
	
	return tiles
#endregion

#region GRAB AND PULL SYSTEM
# Start grabbing an entity
func grab_entity(target, initial_state: int = GrabState.PASSIVE) -> bool:
	# Check if entity can be grabbed
	if !can_grab_entity(target):
		return false
	
	# Check if already grabbing something else
	if grabbing_entity != null:
		# If so, release it first
		release_grab()
	
	# Set up the grab
	grabbing_entity = target
	grab_state = initial_state
	grab_time = 0.0
	
	# Connect signals from the grabbed entity if it has them
	if target.has_signal("movement_attempt"):
		if !target.is_connected("movement_attempt", Callable(self, "_on_grabbed_movement_attempt")):
			target.connect("movement_attempt", Callable(self, "_on_grabbed_movement_attempt"))
	
	# Set target's grabbed_by
	if target.has_method("set_grabbed_by"):
		target.set_grabbed_by(self, grab_state)
	
	# Start pulling automatically for passive grabs
	if grab_state == GrabState.PASSIVE:
		pull_entity(target)
	
	# Play grab sound/effect
	if audio_manager:
		audio_manager.play_positioned_sound("grab", position, 0.3)
	
	# Send grab message
	if sensory_system:
		match grab_state:
			GrabState.PASSIVE:
				sensory_system.display_message("You passively grab " + target.entity_name + ".")
			GrabState.AGGRESSIVE:
				sensory_system.display_message("You aggressively grab " + target.entity_name + "!")
	
	# Emit signal for UI updates
	emit_signal("grab_state_changed", grab_state, target)
	
	return true

# Release the current grab
func release_grab():
	if grabbing_entity == null:
		return
	
	# Stop pulling if we were
	if pulling_entity == grabbing_entity:
		stop_pulling()
	
	# Disconnect signals
	if grabbing_entity.has_signal("movement_attempt"):
		if grabbing_entity.is_connected("movement_attempt", Callable(self, "_on_grabbed_movement_attempt")):
			grabbing_entity.disconnect("movement_attempt", Callable(self, "_on_grabbed_movement_attempt"))
	
	# Notify the grabbed entity
	if grabbing_entity.has_method("set_grabbed_by"):
		grabbing_entity.set_grabbed_by(null, GrabState.NONE)
	
	# Play release sound
	if audio_manager:
		audio_manager.play_positioned_sound("release", position, 0.2)
	
	# Reset grab variables
	var old_state = grab_state
	grab_state = GrabState.NONE
	var old_entity = grabbing_entity
	grabbing_entity = null
	grab_time = 0.0
	grab_resist_progress = 0.0
	
	# Emit signal for UI updates
	emit_signal("grab_state_changed", GrabState.NONE, null)
	
	# Send message
	if sensory_system:
		sensory_system.display_message("You release your grab.")
	
	return true

# Upgrade the current grab to the next state
func upgrade_grab() -> bool:
	if grabbing_entity == null or grab_state == GrabState.KILL:
		return false
	
	# Check if enough time has passed for an upgrade
	if grab_time < 0.5:  # Need to hold for at least 0.5 seconds
		if sensory_system:
			sensory_system.display_message("You need to wait before upgrading your grab!")
		return false
	
	# Reset resist progress when upgrading
	grab_resist_progress = 0.0
	
	# Calculate upgrade success chance (based on stats)
	var upgrade_chance = 70 + (dexterity * 1.5)
	if randf() * 100 < upgrade_chance:
		# Success - upgrade grab state
		var old_state = grab_state
		grab_state += 1
		
		# If upgrading from passive, stop pulling
		if old_state == GrabState.PASSIVE and pulling_entity == grabbing_entity:
			stop_pulling()
		
		# Effect on target
		if grabbing_entity.has_method("set_grabbed_by"):
			grabbing_entity.set_grabbed_by(self, grab_state)
		
		# Play sound/effect
		if audio_manager:
			if grab_state == GrabState.KILL:
				audio_manager.play_positioned_sound("choke", position, 0.5)
			else:
				audio_manager.play_positioned_sound("grab_tighten", position, 0.3 + (0.1 * grab_state))
		
		# Send message
		if sensory_system:
			match grab_state:
				GrabState.AGGRESSIVE:
					sensory_system.display_message("Your grip tightens!")
				GrabState.NECK:
					sensory_system.display_message("You grab the neck!")
				GrabState.KILL:
					sensory_system.display_message("You start to strangle!")
		
		# Emit signal for UI updates
		emit_signal("grab_state_changed", grab_state, grabbing_entity)
		
		# Apply immediate effects for kill state
		if grab_state == GrabState.KILL:
			if grabbing_entity.has_method("apply_damage"):
				grabbing_entity.apply_damage(1.0, "asphyxiation")
		
		# Reset grab time
		grab_time = 0.0
		
		return true
	else:
		# Failed to upgrade - release the grab entirely
		if sensory_system:
			sensory_system.display_message("You fumble and release your grab!")
		
		release_grab()
		return false

# Downgrade the current grab
func downgrade_grab() -> bool:
	if grabbing_entity == null or grab_state == GrabState.PASSIVE:
		return false
	
	# Downgrade grab state
	grab_state -= 1
	
	# Effect on target
	if grabbing_entity.has_method("set_grabbed_by"):
		grabbing_entity.set_grabbed_by(self, grab_state)
	
	# Start pulling again if we downgraded to passive
	if grab_state == GrabState.PASSIVE:
		pull_entity(grabbing_entity)
	
	# Reset resist progress
	grab_resist_progress = 0.0
	
	# Send message
	if sensory_system:
		sensory_system.display_message("You loosen your grip.")
	
	# Emit signal for UI updates
	emit_signal("grab_state_changed", grab_state, grabbing_entity)
	
	return true

# Pull a different entity without grabbing
func pull_entity(target) -> bool:
	# Check if we can pull
	if !has_pull_flag:
		return false
	
	# Check if entity can be pulled
	if !can_pull_entity(target):
		return false
	
	# Check if already pulling something else
	if pulling_entity != null:
		# If so, stop pulling it first
		stop_pulling()
	
	# Set up the pull
	pulling_entity = target
	
	# Notify the pulled entity
	if target.has_method("set_pulled_by"):
		target.set_pulled_by(self)
	
	# Send message
	if sensory_system:
		sensory_system.display_message("You start pulling " + target.entity_name + ".")
	
	# Emit signal for UI updates
	emit_signal("pulling_changed", target)
	
	# Update movement speed
	update_pull_movespeed()
	
	return true

# Stop pulling the current entity
func stop_pulling():
	if pulling_entity == null:
		return
	
	# Notify the pulled entity
	if pulling_entity.has_method("set_pulled_by"):
		pulling_entity.set_pulled_by(null)
	
	# Reset variables
	var old_entity = pulling_entity
	pulling_entity = null
	
	# Reset movement speed modifier from pulling
	update_pull_movespeed()
	
	# Send message
	if sensory_system:
		sensory_system.display_message("You stop pulling " + old_entity.entity_name + ".")
	
	# Emit signal for UI updates
	emit_signal("pulling_changed", null)
	
	return true

# Check if entity can be grabbed
func can_grab_entity(target) -> bool:
	# Check if target is valid and has required methods/properties
	if target == null or target == self:
		return false
	
	# Check if target is an entity type that can be grabbed
	if !target.has("entity_type"):
		return false
	
	# Check if target is too big or has the no_grab flag
	if target.has("no_grab") and target.no_grab:
		return false
	
	# Check if target is in range
	if !is_adjacent_to(target):
		if sensory_system:
			sensory_system.display_message("You need to be closer to grab that!")
		return false
	
	return true

# Check if entity can be pulled
func can_pull_entity(target) -> bool:
	# Much of the same logic as grabbing
	if target == null or target == self:
		return false
	
	# Check if target has the no_pull flag
	if target.has("no_pull") and target.no_pull:
		return false
	
	# Check if target is in range
	if !is_adjacent_to(target):
		if sensory_system:
			sensory_system.display_message("You need to be closer to pull that!")
		return false
	
	return true
#endregion

#region Z-LEVEL MOVEMENT
# Move up a Z-level
func move_up():
	# Check if currently moving
	if is_moving:
		return false
	
	# Check for ladders first
	var current_turf = Vector2i(current_tile_position.x, current_tile_position.y)
	var ladder = world.get_ladder_at(current_turf, current_z_level)
	
	if ladder and ladder.has("top_z") and ladder.top_z > current_z_level:
		# Use ladder to climb up
		use_ladder(ladder, true)
		return true
	
	# No ladder, check if we can z-move otherwise
	if !can_z_move(1, current_turf, ZMoveFlags.CAN_FLY_CHECKS | ZMoveFlags.FEEDBACK):
		return false
	
	# Show "moving up" effect
	if sensory_system:
		sensory_system.display_message("Moving up...")
	
	# Wait animation/delay
	var timer = get_tree().create_timer(1.0)
	await timer.timeout
	
	# Perform the z-move
	return z_move(1, ZMoveFlags.FLIGHT_FLAGS | ZMoveFlags.FEEDBACK)

# Move down a Z-level
func move_down():
	# Check if currently moving
	if is_moving:
		return false
	
	# Check for ladders first
	var current_turf = Vector2i(current_tile_position.x, current_tile_position.y)
	var ladder = world.get_ladder_at(current_turf, current_z_level)
	
	if ladder and ladder.has("bottom_z") and ladder.bottom_z < current_z_level:
		# Use ladder to climb down
		use_ladder(ladder, false)
		return true
	
	# No ladder, check if we can z-move otherwise
	if !can_z_move(-1, current_turf, ZMoveFlags.CAN_FLY_CHECKS | ZMoveFlags.FEEDBACK):
		return false
	
	# Show "moving down" effect
	if sensory_system:
		sensory_system.display_message("Moving down...")
	
	# Wait animation/delay
	var timer = get_tree().create_timer(1.0)
	await timer.timeout
	
	# Perform the z-move
	return z_move(-1, ZMoveFlags.FLIGHT_FLAGS | ZMoveFlags.FEEDBACK)

# Check if a Z-movement is possible
func can_z_move(direction: int, current_turf: Vector2i, flags: int) -> bool:
	# Handle entity being in special containers
	if parent_container != null:
		if parent_container.has_method("handle_z_move"):
			return parent_container.handle_z_move(self, direction)
		return false  # Can't move Z in most containers
	
	# Skip checks if forced
	if flags & ZMoveFlags.IGNORE_CHECKS:
		return true
	
	# Check for above/below z-levels
	var target_z = current_z_level + direction
	
	# Check if target z-level exists
	if world and !world.has_z_level(target_z):
		if flags & ZMoveFlags.FEEDBACK:
			if sensory_system:
				sensory_system.display_message("There's nothing in that direction!")
		return false
	
	# For upward movement, check ceiling
	if direction > 0:
		if world and world.has_ceiling_at(current_turf, current_z_level):
			if flags & ZMoveFlags.FEEDBACK:
				if sensory_system:
					sensory_system.display_message("There's a ceiling in the way!")
			return false
	
	# For downward movement, check floor
	if direction < 0:
		if world and world.has_solid_floor_at(current_turf, current_z_level):
			if flags & ZMoveFlags.FEEDBACK:
				if sensory_system:
					sensory_system.display_message("The floor is in the way!")
			return false
	
	# Check for flying ability for open space transitions
	if flags & ZMoveFlags.CAN_FLY_CHECKS:
		if !can_fly() and !is_floating:
			if flags & ZMoveFlags.FEEDBACK:
				if sensory_system:
					sensory_system.display_message("You can't fly!")
			return false
	
	# Check destination turf (is it a valid tile?)
	if !is_valid_tile(current_turf, target_z):
		if flags & ZMoveFlags.FEEDBACK:
			if sensory_system:
				sensory_system.display_message("There's nothing there to land on!")
		return false
	
	return true

# Check if entity can fly/float
func can_fly() -> bool:
	# Check for any flight abilities or status effects
	if status_effects.has("flying") and status_effects["flying"]:
		return true
	
	# Check for jetpack equipment
	if active_equipment.has("back"):
		var jetpack = active_equipment["back"]
		if jetpack and jetpack.has("enables_flight") and jetpack.enables_flight:
			return true
	
	return false

# Perform Z-movement
func z_move(direction: int, flags: int = ZMoveFlags.NONE) -> bool:
	# Final check if movement is possible
	if !can_z_move(direction, current_tile_position, flags):
		return false
	
	# Calculate target z-level
	var target_z = current_z_level + direction
	
	# Update Z position
	var old_z = current_z_level
	current_z_level = target_z
	
	# Update tile occupancy
	if tile_occupancy_system:
		tile_occupancy_system.move_entity_z(
			self, 
			current_tile_position, 
			current_tile_position, 
			old_z, 
			target_z
		)
	
	# Emit appropriate signals
	emit_signal("z_level_changed", old_z, target_z, current_tile_position)
	
	# Display message
	if flags & ZMoveFlags.FEEDBACK:
		if sensory_system:
			if direction > 0:
				sensory_system.display_message("You move upward.")
			else:
				sensory_system.display_message("You move downward.")
	
	# Check new environment
	check_tile_environment()
	
	return true

# Use a ladder to change Z-levels
func use_ladder(ladder, going_up: bool = true):
	# Determine target z and position
	var target_z = current_z_level
	var target_pos = current_tile_position
	
	if going_up and ladder.has("top_z"):
		target_z = ladder.top_z
		if ladder.has("top_position"):
			target_pos = ladder.top_position
	elif !going_up and ladder.has("bottom_z"):
		target_z = ladder.bottom_z
		if ladder.has("bottom_position"):
			target_pos = ladder.bottom_position
	
	# Play climbing sound/animation
	if audio_manager:
		audio_manager.play_positioned_sound("ladder_climb", position, 0.5)
	
	# Show climbing message
	if sensory_system:
		if going_up:
			sensory_system.display_message("You climb up the ladder.")
		else:
			sensory_system.display_message("You climb down the ladder.")
	
	# Wait for animation
	var timer = get_tree().create_timer(1.2)
	await timer.timeout
	
	# Update position
	var old_z = current_z_level
	current_z_level = target_z
	
	var old_pos = current_tile_position
	current_tile_position = target_pos
	previous_tile_position = target_pos
	
	# Update world position
	position = tile_to_world(target_pos)
	
	# Update tile occupancy
	if tile_occupancy_system:
		tile_occupancy_system.move_entity_z(self, old_pos, target_pos, old_z, target_z)
	
	# Emit signals
	emit_signal("z_level_changed", old_z, target_z, target_pos)
	
	# Check new environment
	check_tile_environment()
#endregion

#region BODY TARGETING
# Handle body part selection from input
func handle_body_part_selection(part: String):
	var weapon_controller = get_node_or_null("WeaponController")
	if weapon_controller:
		weapon_controller.set_target_zone(part)
	
	match part:
		"head":
			toggle_head_zone()
		"chest":
			select_chest_zone()
		"groin":
			select_groin_zone()
		"r_arm":
			toggle_r_arm_zone()
		"l_arm":
			toggle_l_arm_zone()
		"r_leg":
			toggle_r_leg_zone()
		"l_leg":
			toggle_l_leg_zone()

# Select a specific body zone
func set_selected_zone(new_zone: String):
	# Check if valid zone
	if is_valid_body_zone(new_zone):
		zone_selected = new_zone
		emit_signal("zone_selected_changed", new_zone)
		
		# Notify any UI or sprite system
		if sprite_system and sprite_system.has_method("highlight_body_part"):
			sprite_system.highlight_body_part(new_zone)
		
		return true
	
	return false

# Check if zone is valid
func is_valid_body_zone(zone: String) -> bool:
	var all_zones = [
		BODY_ZONE_HEAD, BODY_ZONE_CHEST, 
		BODY_ZONE_L_ARM, BODY_ZONE_R_ARM,
		BODY_ZONE_L_LEG, BODY_ZONE_R_LEG,
		BODY_ZONE_PRECISE_EYES, BODY_ZONE_PRECISE_MOUTH,
		BODY_ZONE_PRECISE_GROIN, 
		BODY_ZONE_PRECISE_L_HAND, BODY_ZONE_PRECISE_R_HAND,
		BODY_ZONE_PRECISE_L_FOOT, BODY_ZONE_PRECISE_R_FOOT
	]
	
	return zone in all_zones

# Cycle through head zones
func toggle_head_zone():
	var next_index = 0
	var current_index = body_zones_head.find(zone_selected)
	
	if current_index != -1:
		next_index = (current_index + 1) % body_zones_head.size()
	
	set_selected_zone(body_zones_head[next_index])

# Cycle through right arm zones
func toggle_r_arm_zone():
	var next_index = 0
	var current_index = body_zones_r_arm.find(zone_selected)
	
	if current_index != -1:
		next_index = (current_index + 1) % body_zones_r_arm.size()
	
	set_selected_zone(body_zones_r_arm[next_index])

# Cycle through left arm zones
func toggle_l_arm_zone():
	var next_index = 0
	var current_index = body_zones_l_arm.find(zone_selected)
	
	if current_index != -1:
		next_index = (current_index + 1) % body_zones_l_arm.size()
	
	set_selected_zone(body_zones_l_arm[next_index])

# Select chest
func select_chest_zone():
	set_selected_zone(BODY_ZONE_CHEST)

# Select groin
func select_groin_zone():
	set_selected_zone(BODY_ZONE_PRECISE_GROIN)

# Cycle through right leg zones
func toggle_r_leg_zone():
	var next_index = 0
	var current_index = body_zones_r_leg.find(zone_selected)
	
	if current_index != -1:
		next_index = (current_index + 1) % body_zones_r_leg.size()
	
	set_selected_zone(body_zones_r_leg[next_index])

# Cycle through left leg zones
func toggle_l_leg_zone():
	var next_index = 0
	var current_index = body_zones_l_leg.find(zone_selected)
	
	if current_index != -1:
		next_index = (current_index + 1) % body_zones_l_leg.size()
	
	set_selected_zone(body_zones_l_leg[next_index])

# Get target zone for attacks/interactions
func get_target_zone() -> String:
	return zone_selected

# Get special effects based on targeted zone
func get_zone_effects(zone: String) -> Dictionary:
	var effects = {}
	
	match zone:
		BODY_ZONE_HEAD:
			effects["damage_multiplier"] = 1.5
			effects["stun_chance"] = 0.3
		BODY_ZONE_PRECISE_EYES:
			effects["damage_multiplier"] = 0.8
			effects["blind_chance"] = 0.6
		BODY_ZONE_PRECISE_MOUTH:
			effects["damage_multiplier"] = 0.8
			effects["mute_chance"] = 0.4
		BODY_ZONE_CHEST:
			effects["damage_multiplier"] = 1.2
			effects["knockback_chance"] = 0.3
		BODY_ZONE_PRECISE_GROIN:
			effects["damage_multiplier"] = 1.1
			effects["stun_chance"] = 0.4
			effects["pain_multiplier"] = 1.5
		BODY_ZONE_L_ARM, BODY_ZONE_R_ARM:
			effects["damage_multiplier"] = 0.9
			effects["disarm_chance"] = 0.3
		BODY_ZONE_PRECISE_L_HAND, BODY_ZONE_PRECISE_R_HAND:
			effects["damage_multiplier"] = 0.7
			effects["disarm_chance"] = 0.6
		BODY_ZONE_L_LEG, BODY_ZONE_R_LEG:
			effects["damage_multiplier"] = 0.9
			effects["slow_chance"] = 0.4
		BODY_ZONE_PRECISE_L_FOOT, BODY_ZONE_PRECISE_R_FOOT:
			effects["damage_multiplier"] = 0.7
			effects["trip_chance"] = 0.4
	
	return effects

# Apply zone effects based on damage
func apply_zone_effects(target, damage: float, zone: String):
	var effects = get_zone_effects(zone)
	
	# Check each effect and apply based on chance
	for effect in effects:
		if effect == "damage_multiplier":
			continue  # Skip, already applied to damage
		
		var chance = effects[effect]
		if randf() < chance:
			match effect:
				"stun_chance":
					if target.has_method("stun"):
						target.stun(2.0 * (damage / 10.0))
				
				"blind_chance":
					if target.has_method("apply_status_effect"):
						target.apply_status_effect("blind", 5.0 * (damage / 10.0))
				
				"mute_chance":
					if target.has_method("apply_status_effect"):
						target.apply_status_effect("mute", 3.0 * (damage / 10.0))
				
				"knockback_chance":
					if target.has_method("apply_knockback"):
						var direction = (target.position - position).normalized()
						target.apply_knockback(direction, damage)
				
				"disarm_chance":
					if target.has_method("drop_active_item"):
						target.drop_active_item()
				
				"slow_chance":
					if target.has_method("apply_status_effect"):
						target.apply_status_effect("slow", 2.0 * (damage / 10.0))
				
				"trip_chance":
					if target.has_method("slip"):
						target.slip(1.0 * (damage / 5.0))
#endregion

#region INTENT SYSTEM
# Set the current intent
func set_intent(new_intent: int):
	if new_intent >= 0 and new_intent <= 3:  # Valid intent values
		intent = new_intent
		
		# Emit signal for UI updates
		emit_signal("intent_changed", intent)
		
		# Send message
		if sensory_system:
			var intent_names = ["help", "disarm", "grab", "harm"]
			sensory_system.display_message("Intent: " + intent_names[intent].to_upper())
		
		return true
	
	return false

# Cycle through intents (help -> disarm -> grab -> harm -> help)
func cycle_intent():
	var new_intent = (intent + 1) % 4
	set_intent(new_intent)
	return new_intent

# Set examine mode
func set_examine_mode():
	# Set intent to HELP
	if interaction_system and interaction_system.has_method("set_intent"):
		interaction_system.set_intent(0)  # HELP intent

# Process disarm action on target
func disarm_entity(target):
	if interaction_processor:
		return interaction_processor.handle_disarm(self, target)
	
	# Fallback implementation
	if target.has_method("get_active_item"):
		var item = target.get_active_item()
		if item:
			# Try to make target drop item
			if target.has_method("drop_item"):
				target.drop_item(item)
				
				# Play sound
				if audio_manager:
					audio_manager.play_positioned_sound("disarm", position, 0.5)
				
				# Show message
				if sensory_system:
					sensory_system.display_message("You disarm " + target.entity_name + "!")
				
				return true
	
	# Failed to disarm
	if sensory_system:
		sensory_system.display_message("You attempt to disarm " + target.entity_name + " but fail!")
	
	return false
#endregion

#region STATUS EFFECTS
# Add a status effect
func apply_status_effect(effect_name: String, duration: float, intensity: float = 1.0):
	status_effects[effect_name] = {
		"duration": duration,
		"intensity": intensity,
		"start_time": Time.get_ticks_msec() / 1000.0
	}
	
	# Apply immediate effects
	match effect_name:
		"confused":
			if sensory_system:
				sensory_system.display_message("You feel confused!")
		"blinded":
			if sensory_system:
				sensory_system.display_message("You can't see!")
		"slowed":
			movement_speed_modifier *= 0.5
			if sensory_system:
				sensory_system.display_message("You feel sluggish!")
		"muted":
			if sensory_system:
				sensory_system.display_message("You can't speak!")
	
	# Return the actual effect data for reference
	return status_effects[effect_name]

# Check if an effect is active
func has_status_effect(effect_name: String) -> bool:
	return status_effects.has(effect_name)

# Get effect intensity
func get_status_effect_intensity(effect_name: String) -> float:
	if status_effects.has(effect_name):
		return status_effects[effect_name].intensity
	return 0.0

# Update status effects - call this from _process
func update_status_effects(delta: float):
	var current_time = Time.get_ticks_msec() / 1000.0
	var effects_to_remove = []
	
	# Check all effects
	for effect_name in status_effects:
		var effect = status_effects[effect_name]
		var elapsed = current_time - effect.start_time
		
		# Check if expired
		if elapsed >= effect.duration:
			effects_to_remove.append(effect_name)
			continue
		
		# Process active effects
		match effect_name:
			"confused":
				# Handled in movement logic
				pass
			"blinded":
				# Handled by sensory system
				pass
			"slowed":
				# Already applied modifier on start, will reset on removal
				pass
			"muted":
				# Handled by speech system
				pass
	
	# Remove expired effects
	for effect_name in effects_to_remove:
		# Handle cleanup
		match effect_name:
			"slowed":
				movement_speed_modifier *= 2.0  # Reverse the slowdown
			"confused":
				if sensory_system:
					sensory_system.display_message("Your mind clears.")
			"blinded":
				if sensory_system:
					sensory_system.display_message("You can see again!")
		
		# Remove from dictionary
		status_effects.erase(effect_name)
#endregion

#region UTILITY FUNCTIONS
# Apply stun effect
func stun(duration: float):
	stun_remaining = duration
	is_stunned = true
	set_state(MovementState.STUNNED)
	
	# Cancel any active movement
	if is_moving:
		position = tile_to_world(current_tile_position)
		is_moving = false
		move_progress = 0.0
	
	# Show stun effect
	if sensory_system:
		sensory_system.display_message("You are stunned!")

# Get entity on a specific tile
func get_entity_on_tile(tile_coords, z_level):
	if world and "tile_occupancy_system" in world and world.tile_occupancy_system:
		var entities = world.tile_occupancy_system.get_entities_at(tile_coords, z_level)
		if entities and entities.size() > 0:
			return entities[0]  # Return the topmost entity
	return null

# Apply slip effect
func slip(duration: float, direction: Vector2 = Vector2.ZERO):
	stun(duration)  # Slipping is a kind of stun
	
	# Make slip sound
	emit_slip_sound()

# Emit slip sound
func emit_slip_sound():
	# Try to play through audio manager
	if audio_manager:
		audio_manager.play_positioned_sound("slip", position, 0.6)
	
	# Try to play through sensory system
	if sensory_system:
		sensory_system.emit_sound(position, current_z_level, "thud", 0.6, self)

# Emit crawling sound
func emit_crawling_sound():
	# Try to play through audio manager
	if audio_system:
		audio_system.play_positioned_sound("crawl", position, 0.3)
	
	# Try to play through sensory system
	if sensory_system:
		sensory_system.emit_sound(position, current_z_level, "crawl", 0.3, self)

# Emit footstep sound
func emit_footstep_sound(volume_override = null):
	var floor_type = get_current_floor_type()
	
	# Calculate appropriate volume based on movement state
	var volume = 0.3  # Default
	if current_state == MovementState.RUNNING:
		volume = 0.5
	elif current_state == MovementState.CRAWLING:
		volume = 0.1
	
	# Use override if provided
	if volume_override != null:
		volume = volume_override
	
	# Emit footstep signal
	emit_signal("footstep", position, floor_type)
	
	# Try to play through audio manager
	if audio_manager:
		audio_manager.play_positioned_sound("footstep", position, volume, floor_type)
	
	# Try to play through sensory system
	if sensory_system:
		sensory_system.emit_sound(position, current_z_level, "footstep", volume, self)

# Check if is in range of an entity
func is_adjacent_to(other_entity) -> bool:
	# Get positions
	var my_pos = current_tile_position
	var other_pos = Vector2i.ZERO
	
	if ("current_tile_position") in other_entity:
		other_pos = other_entity.current_tile_position
	elif other_entity.has_method("global_position"):
		other_pos = world_to_tile(other_entity.global_position)
	elif other_entity.has_method("position"):
		other_pos = world_to_tile(other_entity.position)
	else:
		return false
	
	# Check if directly adjacent or same tile
	var diff_x = abs(my_pos.x - other_pos.x)
	var diff_y = abs(my_pos.y - other_pos.y)
	
	return (diff_x == 0 and diff_y == 0) or (diff_x <= 1 and diff_y <= 1)

# Check if tile is in a valid zone
func is_valid_tile(tile_pos: Vector2i, z_level: int) -> bool:
	if !world:
		return false
	
	# Use zone system if available
	if world.has_method("is_in_zone"):
		return world.is_in_zone(tile_pos, z_level)
	
	# Fallback to tile data check
	var tile = world.get_tile_data(tile_pos, z_level)
	return tile != null

# Check for tile environment effects
func check_tile_environment():
	current_tile_type = get_current_floor_type()
	
	# Check for gravity changes
	if atmosphere_system:
		var atmos_data = atmosphere_system.get_atmosphere_data(current_tile_position)
		if atmos_data and atmos_data.has("has_gravity") and atmos_data.has_gravity == false:
			set_gravity(false)
		else:
			set_gravity(true)
	
	# Check for slippery floors
	var tile_data = null
	if world and world.has_method("get_tile_data"):
		tile_data = world.get_tile_data(current_tile_position, current_z_level)
	
	if tile_data:
		if tile_data.has("slippery") and tile_data.slippery:
			current_tile_friction = 0.2  # Very slippery
			
			# Maybe slip the player
			if !is_stunned and !is_floating and randf() < 0.4:  # 40% chance to slip
				slip(1.5)
		else:
			current_tile_friction = 1.0  # Normal friction
	
	# Check for hazards
	check_tile_hazards()

# Check if the tile has any hazards
func check_tile_hazards():
	if world and world.has_method("get_tile_hazards"):
		var hazards = world.get_tile_hazards(current_tile_position, current_z_level)
		
		for hazard in hazards:
			match hazard.type:
				"slippery":
					if randf() < hazard.slip_chance:
						slip(hazard.slip_time, hazard.slip_direction)
				
				"damage":
					# Handle taking damage
					take_damage(hazard.damage_amount, hazard.damage_type)
				
				"radiation":
					# Handle radiation exposure
					expose_to_radiation(hazard.radiation_level)

# Get current floor type
func get_current_floor_type() -> String:
	if world and world.has_method("get_tile_data"):
		var tile_data = world.get_tile_data(current_tile_position, current_z_level)
		if tile_data and tile_data.has("floor_type"):
			return tile_data.floor_type
	
	return "floor"  # Default if unknown

# Check if tile has a wall
func is_wall_at(tile_pos: Vector2i, z_level: int) -> bool:
	# Use world's wall detection if available (most reliable)
	if world and world.has_method("is_wall_at"):
		return world.is_wall_at(tile_pos, z_level)
	
	# Fallback implementation
	if world and world.has_method("get_tile_data"):
		var tile_data = world.get_tile_data(tile_pos, z_level)
		if tile_data and tile_data.has("wall"):
			return tile_data.wall != null
	
	return false

# Check if tile has a closed door
func is_closed_door_at(tile_pos: Vector2i, z_level: int) -> bool:
	if world and world.has_method("get_tile_data"):
		var tile_data = world.get_tile_data(tile_pos, z_level)
		if tile_data and tile_data.has("door"):
			return tile_data.door.has("closed") and tile_data.door.closed
	return false

# Check if tile has a window
func is_window_at(tile_pos: Vector2i, z_level: int) -> bool:
	if world and world.has_method("get_tile_data"):
		var tile_data = world.get_tile_data(tile_pos, z_level)
		if tile_data and tile_data.has("window"):
			return true
	return false

# Convert world position to tile coordinates
func world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x / TILE_SIZE), int(world_pos.y / TILE_SIZE))

# Convert tile coordinates to world position (centered in tile)
func tile_to_world(tile_pos: Vector2i) -> Vector2:
	return Vector2((tile_pos.x * TILE_SIZE) + (TILE_SIZE / 2.0), 
				   (tile_pos.y * TILE_SIZE) + (TILE_SIZE / 2.0))

# Handle damage
func take_damage(damage_amount: float, damage_type: String = "brute", armor_type: String = "", effects: bool = true, armour_penetration: float = 0.0, attacker = null):
	if damage_amount <= 0:
		return
	
	# Play damage sound
	if audio_manager:
		var sound_name = "hit"
		match damage_type:
			"burn":
				sound_name = "burn"
			"toxin":
				sound_name = "poison"
			"oxygen":
				sound_name = "gasp"
			_:
				sound_name = "hit"
		
		audio_manager.play_positioned_sound(sound_name, position, min(0.3 + (damage_amount / 20.0), 0.9))
	
	# Show damage message
	if sensory_system:
		var message = "You take " + str(damage_amount) + " " + damage_type + " damage!"
		sensory_system.display_message(message)
	
	# Stun briefly for high damage
	if damage_amount > 15 and !is_stunned:
		stun(0.5)
	
	# Let health system handle the rest if available
	if health_system and health_system.has_method("take_damage"):
		health_system.take_damage(damage_amount, damage_type)

# Handle radiation exposure
func expose_to_radiation(level: float):
	# Implementation would depend on your radiation system
	if level <= 0:
		return
	
	# Show message for high radiation
	if level > 50 and sensory_system:
		sensory_system.display_message("You feel a wave of intense radiation!")
	
	# Let radiation system handle the rest if available
	if health_system and health_system.has_method("apply_radiation"):
		health_system.apply_radiation(level)

# Update sprite system direction
func update_sprite_system_direction(direction: int):
	if sprite_system == null:
		return
		
	# Convert from Direction enum to HumanSpriteSystem direction
	# DirectionEnum: NONE = -1, NORTH = 0, EAST = 1, SOUTH = 2, WEST = 3
	# HumanSpriteSystem: SOUTH = 0, NORTH = 1, EAST = 2, WEST = 3
	
	var sprite_direction = 0  # Default to SOUTH
	
	match direction:
		Direction.NORTH:
			sprite_direction = 1  # NORTH in HumanSpriteSystem
		Direction.EAST:
			sprite_direction = 2  # EAST in HumanSpriteSystem
		Direction.SOUTH:
			sprite_direction = 0  # SOUTH in HumanSpriteSystem
		Direction.WEST:
			sprite_direction = 3  # WEST in HumanSpriteSystem
		# Handle diagonals by choosing the dominant direction
		Direction.NORTHEAST:
			sprite_direction = 2  # EAST in HumanSpriteSystem
		Direction.SOUTHEAST:
			sprite_direction = 0  # SOUTH in HumanSpriteSystem
		Direction.SOUTHWEST:
			sprite_direction = 0  # SOUTH in HumanSpriteSystem
		Direction.NORTHWEST:
			sprite_direction = 3  # WEST in HumanSpriteSystem
	
	# Try different sprite system update methods
	if sprite_system.has_method("set_direction"):
		sprite_system.set_direction(sprite_direction)
	elif sprite_system.has_method("adapt_to_grid_controller_direction"):
		sprite_system.adapt_to_grid_controller_direction(direction)  # Pass original direction

# Makes the entity face toward a target atom/entity or position
func face_entity(target):
	var target_position = Vector2.ZERO
	
	# Get position of the target
	if typeof(target) == TYPE_VECTOR2:
		# If target is already a Vector2
		target_position = target
	elif target.has_method("global_position"):
		# If target has a global_position method
		target_position = target.global_position
	elif "position" in target:
		# If target has a position property
		target_position = target.position
	else:
		# Can't determine position, return
		return false
	
	# Calculate direction vector from entity to target
	var direction_vector = target_position - position
	
	# Skip if the direction vector is zero (same position)
	if direction_vector == Vector2.ZERO:
		return false
	
	# Convert to normalized direction
	direction_vector = direction_vector.normalized()
	
	# Convert to grid-based direction vector for our system
	var grid_direction = Vector2i(
		round(direction_vector.x), 
		round(direction_vector.y)
	)
	
	# Normalize to ensure we're getting a proper direction vector
	if grid_direction.x != 0 and grid_direction.y != 0:
		# For diagonal directions, keep both components but ensure they're -1 or 1
		grid_direction.x = sign(grid_direction.x)
		grid_direction.y = sign(grid_direction.y)
	elif grid_direction == Vector2i.ZERO:
		# If rounding gave us zero, use the strongest component
		if abs(direction_vector.x) > abs(direction_vector.y):
			grid_direction.x = sign(direction_vector.x)
		else:
			grid_direction.y = sign(direction_vector.y)
	
	# Update the facing direction using existing function
	update_facing_from_input(grid_direction)
	
	return true

# Method for applying knockback (used by grenades and other explosions)
func apply_knockback(direction: Vector2, force: float):
	# If in zero-G, apply as velocity
	if is_floating:
		velocity += direction * force * 0.5
		if velocity.length() > ZERO_G_MAX_SPEED * 1.5:  # Allow exceeding normal max speed temporarily
			velocity = velocity.normalized() * ZERO_G_MAX_SPEED * 1.5
	else:
		# In normal gravity, stun briefly and move
		
		# Calculate knockback distance in tiles
		var knockback_tiles = int(force / 20.0)  # Convert force to tile distance
		
		# Limit maximum knockback
		knockback_tiles = min(knockback_tiles, 3)
		
		if knockback_tiles > 0:
			# Try to move in the knockback direction
			var target = current_tile_position
			for i in range(knockback_tiles):
				var next_tile = target + Vector2i(int(direction.x), int(direction.y))
				
				# Check for collision
				if check_collision(next_tile, current_z_level) != CollisionType.NONE:
					break
				
				target = next_tile
			
			# Move to final valid position
			if target != current_tile_position:
				position = tile_to_world(target)
				previous_tile_position = current_tile_position
				current_tile_position = target
				
				# Update tile occupancy
				if tile_occupancy_system:
					tile_occupancy_system.move_entity(self, previous_tile_position, current_tile_position, current_z_level)
				
				# Emit signals
				emit_signal("tile_changed", previous_tile_position, current_tile_position)
				emit_signal("entity_moved", previous_tile_position, current_tile_position, self)

# Find inventory system
func find_inventory_system():
	# Try to find inventory system if not already referenced
	if !inventory_system:
		# Check if it's a direct child
		inventory_system = self.get_node_or_null("InventorySystem")
		
		if inventory_system:
			print("GridMovementController: Found InventorySystem as direct child")
			return true
		
		# Check if it's a child of our parent entity
		inventory_system = get_parent().get_node_or_null("InventorySystem")
		
		if inventory_system:
			print("GridMovementController: Found InventorySystem as sibling node")
			return true
		
		# Try to find it in the player's other controllers
		var possible_inventory = self.get_node_or_null("InventorySystem")
		if possible_inventory:
			inventory_system = possible_inventory
			print("GridMovementController: Found InventorySystem in PlayerController")
			return true
			
		# Try to find it in the entity itself (if we're a component)
		if get_parent().has_method("get_inventory_system"):
			inventory_system = get_parent().get_inventory_system()
			if inventory_system:
				print("GridMovementController: Got InventorySystem via get_inventory_system() method")
				return true
		
		# Last resort - look through all nodes in the entity
		var inventory_nodes = get_parent().find_children("*", "InventorySystem", true, false)
		if inventory_nodes.size() > 0:
			inventory_system = inventory_nodes[0]
			print("GridMovementController: Found InventorySystem via deep search:", inventory_system)
			return true
			
		print("GridMovementController: ERROR - Couldn't find InventorySystem!")
		return false
	
	return true
#endregion

#region POSTURE CONTROL
# Toggle between lying and standing
func toggle_lying():
	if Time.get_ticks_msec() * 0.001 - last_lying_state_change < lying_state_change_cooldown:
		return false  # Still on cooldown
		
	if is_lying:
		return get_up()
	else:
		return await lie_down()

# Make the character lie down
func lie_down(forced: bool = false):
	print("GridMovementController: Attempting to lie down")
	
	# Can't lie down if currently moving between tiles
	if is_moving and !forced:
		print("GridMovementController: Can't lie down while moving")
		return false
		
	# Can't lie down if stunned (already incapacitated)
	if is_stunned and !forced:
		print("GridMovementController: Can't lie down while stunned")
		return false
	
	# Already lying down
	if is_lying:
		print("GridMovementController: Already lying down")
		return false
	
	# Update lying state
	is_lying = true
	last_lying_state_change = Time.get_ticks_msec() * 0.001
	
	# Cancel any active movement and switch to crawling state
	if is_moving:
		is_moving = false
		move_progress = 0.0
		position = tile_to_world(current_tile_position)
	
	# First update sprite system (before changing state)
	var sprites_updated = false
	if sprite_system and sprite_system.has_method("set_lying_state"):
		sprite_system.set_lying_state(true, current_direction)
		sprites_updated = true
		print("GridMovementController: Sprite system updated to lying state")
	else:
		print("GridMovementController: Warning - No sprite system found or no set_lying_state method")
	
	# Give sprites time to update before changing movement state
	if sprites_updated:
		# Insert short delay to let sprite animation start
		await get_tree().create_timer(0.1).timeout
	
	# Change to crawling movement state AFTER sprites begin update
	set_state(MovementState.CRAWLING)
	
	# Play lying down sound
	if audio_system:
		audio_system.play_positioned_sound("body_fall", position, 0.4)
	
	# Display message if sensory system exists
	if self.get_node_or_null("SensorySystem"):
		self.get_node("SensorySystem").display_message("You lie down.")
	
	# Emit signal about state change
	emit_signal("state_changed", MovementState.IDLE, MovementState.CRAWLING)
	
	print("GridMovementController: Successfully lying down")
	return true

# Attempt to get up from lying position
func get_up(forced: bool = false):
	print("GridMovementController: Attempting to get up")
	
	# Can't get up if currently moving between tiles
	if is_moving and !forced:
		print("GridMovementController: Can't get up while moving")
		return false
		
	# Can't get up if stunned unless forced
	if is_stunned and !forced:
		print("GridMovementController: Can't get up while stunned")
		return false
	
	# Not lying down
	if !is_lying:
		print("GridMovementController: Not lying down, can't get up")
		return false
	
	# Check if we can get up (based on health, etc)
	if !can_stand_up() and !forced:
		stand_up_attempts += 1
		
		# Display message about failing to stand
		if self.get_node_or_null("SensorySystem"):
			var messages = [
				"You struggle to get up...",
				"You try to push yourself up, but fail.",
				"You can't seem to get up right now."
			]
			
			# More severe message after multiple failed attempts
			if stand_up_attempts >= 3:
				messages = [
					"You're too weak to get up!",
					"Your body refuses to cooperate!",
					"You need help getting up!"
				]
				
			self.get_node("SensorySystem").display_message(messages[stand_up_attempts % messages.size()])
			
		# Increase stamina loss with each failed attempt
		if health_system:
			health_system.adjustStaminaLoss(5.0 * stand_up_attempts)
		
		print("GridMovementController: Failed to get up - health check failed")
		return false
	
	# Update state
	is_lying = false
	last_lying_state_change = Time.get_ticks_msec() * 0.001
	stand_up_attempts = 0
	
	# Cancel any active movement
	if is_moving:
		is_moving = false
		move_progress = 0.0
		position = tile_to_world(current_tile_position)
	
	# First change state to idle - this will reset movement speed FIRST
	set_state(MovementState.IDLE)
	
	# Then update sprite system
	var sprites_updated = false
	if sprite_system and sprite_system.has_method("set_lying_state"):
		sprite_system.set_lying_state(false, current_direction)
		sprites_updated = true
		print("GridMovementController: Sprite system updated to standing state")
	else:
		print("GridMovementController: Warning - No sprite system found or no set_lying_state method")
	
	# Play getting up sound
	if audio_system:
		audio_system.play_positioned_sound("rustle", position, 0.4)
	
	# Display message
	if self.get_node_or_null("SensorySystem"):
		self.get_node("SensorySystem").display_message("You get back up.")
	
	# Double-check movement speed modifier is reset
	movement_speed_modifier = 1.0
	
	print("GridMovementController: Successfully got up")
	return true

# Check if the entity can stand up based on current status
func can_stand_up() -> bool:
	# Check if the player is too injured to stand
	if health_system:
		# Too injured to stand (below 10% health)
		if health_system.health < (health_system.max_health * 0.1):
			return false
			
		# Too exhausted to stand
		if health_system.staminaloss > 90:
			return false
	
	# Check if the player has necessary limbs to stand
	if limb_system:
		# Need at least one leg to stand
		var has_leg = false
		if limb_system.limbs.has("l_leg") and limb_system.limbs["l_leg"].attached:
			has_leg = true
		elif limb_system.limbs.has("r_leg") and limb_system.limbs["r_leg"].attached:
			has_leg = true
			
		if !has_leg:
			return false
	
	# Check for movement restricting status effects
	if status_effect_manager and status_effect_manager.has_effect_flag("movement_restricting"):
		return false
	
	return true

# Handle rest key pressed
func handle_rest_key_pressed():
	toggle_lying()
#endregion

#region MULTIPLAYER & SETUP
# Setup singleplayer
func setup_singleplayer():
	print("Player: Setting up singleplayer character")
	
	# Set as local player
	set_local_player(true)
	
	# Get customization data from GameManager
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		var character_data = game_manager.get_character_data()
		if character_data.size() > 0:
			# Apply customization
			if sprite_system and sprite_system.has_method("apply_customization"):
				sprite_system.apply_customization(character_data)
	
	# Add to player groups
	self.add_to_group("player_controller")
	self.add_to_group("players")
	
	print("Player: Singleplayer setup complete")

# Set the local player flag
func set_local_player(is_local: bool):
	is_local_player = is_local
	
	# Enable/disable camera based on locality
	var camera = self.get_node_or_null("Camera2D")
	if camera:
		camera.enabled = is_local
		print("Player Controller: Camera ", "enabled" if is_local else "disabled")
	
	# Enable/disable UI
	var ui = self.get_node_or_null("PlayerUI")
	if ui:
		ui.visible = is_local
		print("Player Controller: UI ", "visible" if is_local else "hidden")
	
	# Configure input processing
	if input_controller:
		input_controller.set_process_input(is_local)
		input_controller.set_process_unhandled_input(is_local)
		print("Player Controller: Input processing ", "enabled" if is_local else "disabled")
	
	# Set processing modes
	set_process_input(is_local)
	set_process_unhandled_input(is_local)
	
	# Configure local processing
	if !is_local:
		# Disable processing for non-local entities
		set_process(false)
		set_physics_process(false)
	
	print("Player Controller: Configured as ", "local" if is_local else "remote", " player")

# Setup multiplayer
func setup_multiplayer(peer_id: int):
	# Only setup if we have the synchronizer
	if has_node("MultiplayerSynchronizer"):
		var sync = get_node("MultiplayerSynchronizer")
		
		# Set the proper authority ID
		sync.set_multiplayer_authority(peer_id)
		
		# Configure processing based on authority
		var is_local = peer_id == multiplayer.get_unique_id()
		set_local_player(is_local)
		
		print("CharacterController: Multiplayer setup complete - Is local: ", is_local)

# Clean up when removed from scene
func _exit_tree():
	unregister_from_systems()
	
	# Stop any active grabs
	if grabbing_entity:
		release_grab()
	
	# Stop any active pulling
	if pulling_entity:
		stop_pulling()
#endregion
