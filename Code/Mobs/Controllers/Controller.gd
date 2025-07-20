extends BaseObject
class_name GridMovementController

## Main controller that coordinates all movement and interaction components
## This acts as the central hub for all character control systems

#region EXPORTS
@export var is_npc: bool = false ## Set to true to make this entity an NPC (not player-controlled)
@export var can_be_interacted_with: bool = true ## Allow interactions with this entity
#endregion

#region SIGNALS
signal systems_initialized()
signal component_ready(component_name: String)
signal npc_conversion_complete()
signal player_conversion_complete()
signal interaction_started(entity, interaction_type)
signal interaction_completed(entity, interaction_type, success)
signal body_part_damaged(part_name: String, current_health: float)
#endregion

#region COMPONENTS
@onready var movement_component: MovementComponent = $MovementComponent
@onready var interaction_component: InteractionComponent = $InteractionComponent
@onready var grab_pull_component: GrabPullComponent = $GrabPullComponent
@onready var z_level_component: ZLevelMovementComponent = $ZLevelMovementComponent
@onready var body_targeting_component: BodyTargetingComponent = $BodyTargetingComponent
@onready var intent_component: IntentComponent = $IntentComponent
@onready var status_effect_component: StatusEffectComponent = $StatusEffectComponent
@onready var item_interaction_component: ItemInteractionComponent = $ItemInteractionComponent
@onready var posture_component: PostureComponent = $PostureComponent
@onready var input_controller: InputController = $InputController
#endregion

#region CORE PROPERTIES
var entity_id: String = ""
var is_local_player: bool = false
var current_z_level: int = 0

# System references
var world = null
var tile_occupancy_system = null
var sensory_system = null
var inventory_system = null
var sprite_system = null
var audio_system = null
var click_system = null

# Initialization state
var is_fully_initialized: bool = false
var initialization_in_progress: bool = false
#endregion

func _ready():
	entity_type = "mob"
	
	# Prevent double initialization
	if initialization_in_progress:
		return
	initialization_in_progress = true
	
	# Check entity meta data for proper NPC detection
	if has_meta("is_npc") and get_meta("is_npc"):
		is_npc = true
	if has_meta("is_player") and get_meta("is_player"):
		is_npc = false
	
	print("GridMovementController: _ready - is_npc: ", is_npc)
	
	# Initialize core systems first
	find_game_systems()
	
	# Create and setup components if they don't exist
	await create_components()
	
	# Initialize components
	await initialize_components()
	
	# Setup based on type after components are ready
	if is_npc:
		call_deferred("setup_npc")
	else:
		call_deferred("setup_singleplayer")
	
	# Connect to external systems
	call_deferred("connect_to_external_systems")
	
	is_fully_initialized = true
	initialization_in_progress = false

func create_components():
	"""Create component instances if they don't exist"""
	# Movement Component
	if not movement_component:
		movement_component = MovementComponent.new()
		movement_component.name = "MovementComponent"
		add_child(movement_component)
	
	# Interaction Component (all entities need this to be interacted with)
	if not interaction_component:
		interaction_component = InteractionComponent.new()
		interaction_component.name = "InteractionComponent"
		add_child(interaction_component)
	
	# Grab/Pull Component
	if not grab_pull_component:
		grab_pull_component = GrabPullComponent.new()
		grab_pull_component.name = "GrabPullComponent"
		add_child(grab_pull_component)
	
	# Z-Level Movement Component
	if not z_level_component:
		z_level_component = ZLevelMovementComponent.new()
		z_level_component.name = "ZLevelMovementComponent"
		add_child(z_level_component)
	
	# Body Targeting Component
	if not body_targeting_component:
		body_targeting_component = BodyTargetingComponent.new()
		body_targeting_component.name = "BodyTargetingComponent"
		add_child(body_targeting_component)
	
	# Intent Component
	if not intent_component:
		intent_component = IntentComponent.new()
		intent_component.name = "IntentComponent"
		add_child(intent_component)
	
	# Status Effect Component
	if not status_effect_component:
		status_effect_component = StatusEffectComponent.new()
		status_effect_component.name = "StatusEffectComponent"
		add_child(status_effect_component)
	
	# Item Interaction Component
	if not item_interaction_component:
		item_interaction_component = ItemInteractionComponent.new()
		item_interaction_component.name = "ItemInteractionComponent"
		add_child(item_interaction_component)
	
	# Posture Component
	if not posture_component:
		posture_component = PostureComponent.new()
		posture_component.name = "PostureComponent"
		add_child(posture_component)
	
	# Input Controller
	if not is_npc and not input_controller:
		input_controller = InputController.new()
		input_controller.name = "InputController"
		add_child(input_controller)
	elif is_npc and input_controller:
		# Remove input controller from NPCs
		input_controller.queue_free()
		input_controller = null
	
	# Wait for components to be ready
	await get_tree().process_frame

func initialize_components():
	"""Initialize all components with necessary references"""
	var init_data = {
		"controller": self,
		"world": world,
		"tile_occupancy_system": tile_occupancy_system,
		"sensory_system": sensory_system,
		"inventory_system": inventory_system,
		"sprite_system": sprite_system,
		"audio_system": audio_system,
		"entity_id": entity_id,
		"entity_name": get_entity_name(entity_name),
		"is_local_player": is_local_player,
		"is_npc": is_npc  # Pass NPC status to components
	}
	
	# Initialize movement component with proper NPC handling
	if movement_component:
		if is_npc:
			# For NPCs, use the new setup method
			var npc_id = get_meta("peer_id", -(Time.get_ticks_msec() % 100000))
		movement_component.initialize(init_data)
		emit_signal("component_ready", "MovementComponent")
	
	# Initialize each component
	for component in [interaction_component, grab_pull_component, 
					  z_level_component, body_targeting_component, intent_component,
					  status_effect_component, item_interaction_component, posture_component]:
		if component and component.has_method("initialize"):
			component.initialize(init_data)
			emit_signal("component_ready", component.name)
		elif component:
			print("GridMovementController: Component ", component.name, " missing initialize method")
	
	# Initialize sprite system if it exists
	if sprite_system and sprite_system.has_method("initialize"):
		sprite_system.initialize(self)  # Pass controller as Entity reference
		emit_signal("component_ready", "HumanSpriteSystem")
	
	if input_controller and not is_npc:
		if input_controller.has_method("connect_to_entity"):
			input_controller.connect_to_entity(self)
		elif input_controller.has_method("initialize"):
			input_controller.initialize(init_data)
	
	# Connect inter-component communication
	connect_component_signals()
	
	emit_signal("systems_initialized")

func connect_to_external_systems():
	"""Connect to external game systems like ClickSystem"""
	# Only connect to click system if this is a local player (not NPC)
	if not is_npc and is_local_player:
		connect_to_click_system()
	
	# Register with world systems
	register_with_systems()

func connect_to_click_system():
	"""Connect to the click system for input handling (players only)"""
	if is_npc:
		print("GridMovementController: Skipping click system connection for NPC")
		return # NPCs don't connect to click system
	
	click_system = get_node_or_null("/root/World/ClickSystem")
	if not click_system:
		click_system = get_tree().get_first_node_in_group("click_system")
	
	if click_system:
		print("GridMovementController: Found ClickSystem, establishing connection")
		
		# Set player reference
		if click_system.has_method("set_player_reference"):
			click_system.set_player_reference(self)
		
		# Connect click signals
		if click_system.has_signal("tile_clicked") and not click_system.is_connected("tile_clicked", _on_tile_clicked):
			click_system.tile_clicked.connect(_on_tile_clicked)
		
		if click_system.has_signal("entity_clicked") and not click_system.is_connected("entity_clicked", _on_entity_clicked):
			click_system.entity_clicked.connect(_on_entity_clicked)

#region INPUT HANDLERS (Players only)
func _on_tile_clicked(tile_coords, mouse_button, shift_pressed, ctrl_pressed, alt_pressed):
	"""Handle tile click events from ClickSystem (players only)"""
	if is_npc:
		return
	
	if interaction_component:
		interaction_component.handle_tile_click(tile_coords, mouse_button, shift_pressed, ctrl_pressed, alt_pressed)

func _on_entity_clicked(entity, button_index: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	"""Handle entity click events from ClickSystem (players only)"""
	if is_npc:
		return
	
	# Determine interaction type based on intent
	var interaction_type = "use"
	if intent_component:
		match intent_component.get_intent():
			0: interaction_type = "help"
			1: interaction_type = "disarm"
			2: interaction_type = "grab"
			3: interaction_type = "harm"
	
	# Emit interaction started signal
	emit_signal("interaction_started", self, interaction_type)
	
	if interaction_component:
		var success = await interaction_component.process_interaction(entity, button_index, shift_pressed, ctrl_pressed, alt_pressed)
		# Emit interaction completed signal
		emit_signal("interaction_completed", self, interaction_type, success)

# Method for NPC AI to request movement
func npc_move_to_tile(target_tile: Vector2i) -> bool:
	"""Request NPC to move to target tile (for AI use)"""
	if not is_npc:
		print("GridMovementController: npc_move_to_tile called on non-NPC")
		return false
	
	if movement_component and movement_component.has_method("npc_move_to"):
		return movement_component.npc_move_to(target_tile)
	
	return false

# Method for NPC AI to request interactions
func npc_interact_with(target, interaction_type: String = "help"):
	"""Handle NPC AI interaction requests"""
	if not is_npc:
		return
	
	print("GridMovementController: NPC interaction with ", target, " type: ", interaction_type)
	
	if interaction_component:
		# Convert AI interaction type to appropriate method
		match interaction_type:
			"attack", "harm":
				interaction_component.handle_harm_interaction(target, null)
			"help":
				interaction_component.handle_help_interaction(target, null)
			"grab":
				interaction_component.handle_grab_interaction(target, null)
			"examine":
				interaction_component.handle_examine_interaction(target)
			_:
				interaction_component.handle_friendly_interaction(target)
#endregion

#region SETUP METHODS
func setup_singleplayer():
	"""Setup as a player character"""
	if is_npc:
		print("GridMovementController: Cannot setup as singleplayer - entity is marked as NPC")
		return
	
	print("GridMovementController: Setting up as PLAYER character")
	
	is_local_player = true
	
	# Add to player groups
	add_to_group("player_controller")
	add_to_group("players")
	add_to_group("entities")
	add_to_group("clickable_entities")
	
	# Mark as player
	set_meta("is_player", true)
	set_meta("is_npc", false)
	
	# Update components
	update_components_for_player()

func setup_multiplayer(peer_id: int):
	"""Setup for multiplayer mode"""
	if is_npc:
		print("GridMovementController: Cannot setup as multiplayer - entity is marked as NPC")
		return
	
	print("GridMovementController: Setting up for multiplayer, peer ID:", peer_id)
	
	# Check if this is the local player
	is_local_player = (peer_id == multiplayer.get_unique_id())
	
	# Add to appropriate groups
	if is_local_player:
		add_to_group("player_controller")
		add_to_group("players")
	else:
		add_to_group("remote_players")
	
	add_to_group("entities")
	add_to_group("clickable_entities")
	
	# Mark as player
	set_meta("is_player", true)
	set_meta("is_npc", false)
	
	# Update components
	update_components_for_player()

func setup_npc():
	"""Setup as an NPC"""
	print("GridMovementController: Setting up as NPC")
	
	is_local_player = false
	is_npc = true  # Ensure this is set
	
	# Add to NPC groups
	add_to_group("npcs")
	add_to_group("entities")
	if can_be_interacted_with:
		add_to_group("clickable_entities")
	
	# Mark as NPC in metadata
	set_meta("is_player", false)
	set_meta("is_npc", true)
	
	# Initialize sprite system
	if sprite_system:
		sprite_system.initialize(self)
	
	# Update components for NPC
	update_components_for_npc()
	
	print("GridMovementController: NPC setup complete")

func update_components_for_player():
	"""Update component configuration for player mode"""
	if movement_component:
		movement_component.is_local_player = is_local_player
	if interaction_component:
		interaction_component.is_local_player = is_local_player

func update_components_for_npc():
	"""Update component configuration for NPC mode"""
	if movement_component:
		movement_component.is_local_player = false
	if interaction_component:
		interaction_component.is_local_player = false
	
	# Properly disable input controller for NPCs
	if input_controller:
		if input_controller.has_method("disable_for_npc"):
			input_controller.disable_for_npc()
		else:
			# If no disable method, remove the input controller entirely
			input_controller.queue_free()
			input_controller = null
	
	# Set default NPC intent to help
	if intent_component:
		intent_component.set_intent(0) # HELP intent

#region PUBLIC INTERFACE
func get_current_tile_position() -> Vector2i:
	return movement_component.current_tile_position if movement_component else Vector2i.ZERO

func get_current_direction() -> int:
	return movement_component.current_direction if movement_component else 0

func get_intent() -> int:
	return intent_component.intent if intent_component else 0

func set_intent(new_intent: int):
	if intent_component:
		intent_component.set_intent(new_intent)

func can_interact_with(target) -> bool:
	return interaction_component.can_interact_with(target) if interaction_component else false

func is_adjacent_to(target) -> bool:
	return movement_component.is_adjacent_to(target) if movement_component else false

func move_externally(target_position: Vector2i, animated: bool = true, force: bool = false) -> bool:
	return movement_component.move_externally(target_position, animated, force) if movement_component else false

func apply_knockback(direction: Vector2, force: float):
	if movement_component:
		movement_component.apply_knockback(direction, force)

func stun(duration: float):
	if status_effect_component:
		status_effect_component.apply_stun(duration)

func take_damage(damage_amount: float, damage_type: String = "brute", armor_type: String = "", effects: bool = true, armour_penetration: float = 0.0, attacker = null):
	# Forward to health system or handle damage
	var health_system = get_parent().get_node_or_null("HealthSystem")
	if health_system:
		health_system.take_damage(damage_amount, damage_type)

func is_npc_entity() -> bool:
	"""Check if this entity is an NPC"""
	return is_npc

func can_be_controlled_by_player() -> bool:
	"""Check if this entity can be controlled by the player"""
	return not is_npc and is_local_player

# Public method for checking if can process player input
func can_process_player_input() -> bool:
	"""Check if this entity should process player input"""
	return not is_npc and is_local_player
#endregion

func connect_component_signals():
	"""Connect signals between components for communication"""
	# Movement -> Other components
	if movement_component:
		if not movement_component.tile_changed.is_connected(_on_tile_changed):
			movement_component.tile_changed.connect(_on_tile_changed)
		if not movement_component.direction_changed.is_connected(_on_direction_changed):
			movement_component.direction_changed.connect(_on_direction_changed)
	
	# Intent -> Interaction
	if intent_component and interaction_component:
		if intent_component:
			if not intent_component.intent_changed.is_connected(interaction_component._on_intent_changed):
				intent_component.intent_changed.connect(interaction_component._on_intent_changed)
	
	# Grab/Pull -> Movement
	if grab_pull_component and movement_component:
		if grab_pull_component.has_signal("movement_modifier_changed") and movement_component.has_method("set_movement_modifier"):
			if not grab_pull_component.movement_modifier_changed.is_connected(movement_component.set_movement_modifier):
				grab_pull_component.movement_modifier_changed.connect(movement_component.set_movement_modifier)
	
	# Status Effects -> Movement
	if status_effect_component and movement_component:
		if status_effect_component.has_signal("movement_speed_changed") and movement_component.has_method("set_speed_modifier"):
			if not status_effect_component.movement_speed_changed.is_connected(movement_component.set_speed_modifier):
				status_effect_component.movement_speed_changed.connect(movement_component.set_speed_modifier)
	
	# Posture -> Movement
	if posture_component and movement_component:
		if posture_component.has_signal("lying_state_changed") and movement_component.has_method("_on_lying_state_changed"):
			if not posture_component.lying_state_changed.is_connected(movement_component._on_lying_state_changed):
				posture_component.lying_state_changed.connect(movement_component._on_lying_state_changed)

#region SYSTEM DISCOVERY
func find_game_systems():
	"""Find and store references to game systems"""
	
	world = get_tree().get_first_node_in_group("world")
	
	print("GridMovementController: Successfully found world: ", world.name)
	
	# Now find systems within the world
	if world:
		tile_occupancy_system = world.get_node_or_null("TileOccupancySystem")
		if not tile_occupancy_system:
			# Try alternative names
			tile_occupancy_system = world.get_node_or_null("TileSystem")
		if not tile_occupancy_system:
			tile_occupancy_system = world.get_node_or_null("OccupancySystem")
		
		sensory_system = world.get_node_or_null("SensorySystem")
		if not sensory_system:
			# Try alternative names
			sensory_system = world.get_node_or_null("MessageSystem")
		if not sensory_system:
			sensory_system = world.get_node_or_null("SensoryManager")
		
		audio_system = world.get_node_or_null("AudioManager")
		if not audio_system:
			# Try alternative names
			audio_system = world.get_node_or_null("AudioSystem")
		if not audio_system:
			audio_system = world.get_node_or_null("SoundManager")
	
	# Find inventory system
	inventory_system = self.get_node_or_null("InventorySystem")
	if not inventory_system:
		inventory_system = self.get_node_or_null("Inventory")
	
	# Find sprite system
	sprite_system = self.get_node_or_null("HumanSpriteSystem")
	
	# Get entity info
	if "entity_name" in self:
		entity_name = self.entity_name
	if "entity_id" in self:
		entity_id = self.entity_id
	
	# Debug output
	print("GridMovementController: System references found:")
	print("  - World: ", world != null)
	print("  - TileOccupancySystem: ", tile_occupancy_system != null)
	print("  - SensorySystem: ", sensory_system != null)
	print("  - AudioSystem: ", audio_system != null)
	print("  - InventorySystem: ", inventory_system != null)
	print("  - SpriteSystem: ", sprite_system != null)

func find_world_node_recursive(node: Node) -> Node:
	"""Recursively search for a world node"""
	if not node:
		return null
	
	# Check if current node is the world
	if node.name == "World" or node.has_method("is_world") or "world" in node.name.to_lower():
		return node
	
	# Check children
	for child in node.get_children():
		var result = find_world_node_recursive(child)
		if result:
			return result
	
	return null

func get_entity_name(entity) -> String:
	if "entity_name" in entity and entity.entity_name != "":
		return entity.entity_name
	elif "name" in entity:
		return entity.name
	else:
		return "something"

func register_with_systems():
	"""Register this entity with world systems"""
	if tile_occupancy_system and movement_component:
		var pos = movement_component.get_current_tile_position()
		if tile_occupancy_system.has_method("register_entity_at_tile"):
			tile_occupancy_system.register_entity_at_tile(self, pos, current_z_level)
	
	# Register with other systems as needed
	var spatial_manager = world.get_node_or_null("SpatialManager") if world else null
	if spatial_manager and spatial_manager.has_method("register_entity"):
		spatial_manager.register_entity(self)
	
	# Register with appropriate system groups
	if is_npc:
		var npc_manager = world.get_node_or_null("NPCManager") if world else null
		if npc_manager and npc_manager.has_method("register_npc"):
			npc_manager.register_npc(self)
	else:
		var interaction_system = world.get_node_or_null("InteractionSystem") if world else null
		if interaction_system and interaction_system.has_method("register_player"):
			interaction_system.register_player(self, is_local_player)
#endregion

#region INPUT HANDLERS (Players only)
func _on_npc_interaction_requested(target, interaction_type: String):
	"""Handle NPC AI interaction requests"""
	if not is_npc:
		return
	
	if interaction_component:
		# Convert AI interaction type to appropriate method
		match interaction_type:
			"attack":
				interaction_component.handle_harm_interaction(target, null)
			"help":
				interaction_component.handle_help_interaction(target, null)
			"grab":
				interaction_component.handle_grab_interaction(target, null)
			"examine":
				interaction_component.handle_examine_interaction(target)
			_:
				interaction_component.handle_friendly_interaction(target)
#endregion

#region COMPONENT CALLBACKS
func _on_tile_changed(old_tile: Vector2i, new_tile: Vector2i):
	"""Handle tile change events from movement component"""
	# Update occupancy
	if tile_occupancy_system and tile_occupancy_system.has_method("move_entity"):
		tile_occupancy_system.move_entity(self, old_tile, new_tile, current_z_level)
	
	# Check environment
	if movement_component:
		movement_component.check_tile_environment()

func _on_direction_changed(old_dir: int, new_dir: int):
	"""Handle direction changes"""
	# Update sprite system directly
	if sprite_system:
		sprite_system.set_direction(new_dir)
#endregion

#region SETUP METHODS
func convert_to_player():
	"""Convert this entity to a player at runtime"""
	if not is_npc:
		return
	
	print("GridMovementController: Converting to player")
	
	# Prevent component issues during conversion
	var was_initialized = is_fully_initialized
	is_fully_initialized = false
	
	# Remove from NPC groups
	remove_from_group("npcs")
	
	# Create input controller
	if not input_controller:
		input_controller = InputController.new()
		input_controller.name = "InputController"
		add_child(input_controller)
		
		# Wait for it to be ready then initialize
		await get_tree().process_frame
		if input_controller.has_method("connect_to_entity"):
			input_controller.connect_to_entity(self)
	
	# Set player status
	is_npc = false
	is_local_player = true
	
	# Setup as player
	setup_singleplayer()
	
	# Reconnect to click system
	call_deferred("connect_to_click_system")
	
	# Reconnect component signals since we have new components
	if was_initialized:
		connect_component_signals()
		is_fully_initialized = true
	
	emit_signal("player_conversion_complete")
	print("GridMovementController: Conversion to player complete")

func disconnect_from_click_system():
	"""Disconnect from click system"""
	if click_system:
		if click_system.has_signal("tile_clicked") and click_system.is_connected("tile_clicked", _on_tile_clicked):
			click_system.tile_clicked.disconnect(_on_tile_clicked)
		if click_system.has_signal("entity_clicked") and click_system.is_connected("entity_clicked", _on_entity_clicked):
			click_system.entity_clicked.disconnect(_on_entity_clicked)
#endregion

func _exit_tree():
	"""Cleanup when removed from scene"""
	# Let components handle their own cleanup
	if grab_pull_component and grab_pull_component.has_method("cleanup"):
		grab_pull_component.cleanup()
	
	# Unregister from systems
	if tile_occupancy_system and movement_component and tile_occupancy_system.has_method("remove_entity"):
		var pos = movement_component.get_current_tile_position()
		tile_occupancy_system.remove_entity(self, pos, current_z_level)
