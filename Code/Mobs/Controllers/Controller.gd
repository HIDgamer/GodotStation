extends BaseObject
class_name GridMovementController

## Main controller that coordinates all movement and interaction components
## This acts as the central hub for all character control systems

#region EXPORTS
@export var is_npc: bool = false ## Set to true to make this entity an NPC (not player-controlled)
@export var npc_ai_enabled: bool = true ## Enable AI for NPCs
@export var can_be_interacted_with: bool = true ## Allow interactions with this entity
#endregion

#region SIGNALS
signal systems_initialized()
signal component_ready(component_name: String)
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
@onready var npc_ai_component: Node = $NPCAIComponent # Optional AI component for NPCs
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
#endregion

func _ready():
	# Set click priority based on entity type
	if not has_meta("click_priority"):
		set_meta("click_priority", 10 if not is_npc else 5) # NPCs have lower priority
	
	# Set entity type
	if not has_meta("entity_type"):
		set_meta("entity_type", "character")
	
	# Set NPC metadata
	set_meta("is_npc", is_npc)
	set_meta("is_player", not is_npc)
	
	# Initialize based on type
	if is_npc:
		call_deferred("setup_npc")
	else:
		call_deferred("setup_singleplayer")
	
	# Initialize core systems
	find_game_systems()
	
	# Create and setup components if they don't exist
	await create_components()
	
	# Initialize components
	await initialize_components()
	
	# Connect to external systems
	call_deferred("connect_to_external_systems")

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
	
	# Input Controller - Only for players
	if not is_npc:
		if not input_controller:
			input_controller = InputController.new()
			input_controller.name = "InputController"
			add_child(input_controller)
	elif input_controller:
		# Remove input controller if this is an NPC
		input_controller.queue_free()
		input_controller = null
	
	# NPC AI Component - Only for NPCs
	if is_npc and npc_ai_enabled:
		if not npc_ai_component:
			# Try to load NPC AI component
			var ai_script = load("res://Scripts/AI/NPCAIComponent.gd")
			if ai_script:
				npc_ai_component = ai_script.new()
				npc_ai_component.name = "NPCAIComponent"
				add_child(npc_ai_component)
			else:
				print("GridMovementController: Could not load NPC AI component")
	elif npc_ai_component:
		# Remove AI component if this is a player
		npc_ai_component.queue_free()
		npc_ai_component = null
	
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
		"entity_name": entity_name,
		"is_local_player": is_local_player,
		"is_npc": is_npc
	}
	
	# Initialize each component
	for component in [movement_component, interaction_component, grab_pull_component, 
					  z_level_component, body_targeting_component, intent_component,
					  status_effect_component, item_interaction_component, posture_component]:
		if component and component.has_method("initialize"):
			component.initialize(init_data)
			emit_signal("component_ready", component.name)
	
	# Setup input controller (only for players)
	if input_controller and not is_npc:
		input_controller.connect_to_entity(self)
	
	# Setup NPC AI component (only for NPCs)
	if npc_ai_component and is_npc:
		if npc_ai_component.has_method("initialize"):
			npc_ai_component.initialize(init_data)
			emit_signal("component_ready", "NPCAIComponent")
	
	# Connect inter-component communication
	connect_component_signals()
	
	emit_signal("systems_initialized")

func connect_component_signals():
	"""Connect signals between components for communication"""
	# Movement -> Other components
	if movement_component:
		movement_component.tile_changed.connect(_on_tile_changed)
		movement_component.state_changed.connect(_on_movement_state_changed)
		movement_component.direction_changed.connect(_on_direction_changed)
	
	# Intent -> Interaction
	if intent_component and interaction_component:
		intent_component.intent_changed.connect(interaction_component._on_intent_changed)
	
	# Grab/Pull -> Movement
	if grab_pull_component and movement_component:
		grab_pull_component.movement_modifier_changed.connect(movement_component.set_movement_modifier)
	
	# Status Effects -> Movement
	if status_effect_component and movement_component:
		status_effect_component.movement_speed_changed.connect(movement_component.set_speed_modifier)
	
	# Posture -> Movement
	if posture_component and movement_component:
		posture_component.lying_state_changed.connect(movement_component._on_lying_state_changed)
	
	# NPC AI -> Movement (if NPC)
	if npc_ai_component and is_npc and movement_component:
		if npc_ai_component.has_signal("move_requested"):
			npc_ai_component.move_requested.connect(movement_component.handle_move_input)
		if npc_ai_component.has_signal("interaction_requested"):
			npc_ai_component.interaction_requested.connect(_on_npc_interaction_requested)

func connect_to_external_systems():
	"""Connect to external game systems like ClickSystem"""
	# Only connect to click system if this is a player
	if not is_npc and is_local_player:
		connect_to_click_system()
	
	# Register with world systems
	register_with_systems()

func connect_to_click_system():
	"""Connect to the click system for input handling (players only)"""
	if is_npc:
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

#region SYSTEM DISCOVERY
func find_game_systems():
	"""Find and store references to game systems"""
	# Get world reference
	world = get_parent().get_node_or_null("World")
	if not world:
		world = get_tree().current_scene
	
	if world:
		tile_occupancy_system = world.get_node_or_null("TileOccupancySystem")
		sensory_system = world.get_node_or_null("SensorySystem")
		audio_system = world.get_node_or_null("AudioManager")
	
	# Find inventory system
	inventory_system = self.get_node_or_null("InventorySystem")
	
	# Find sprite system
	sprite_system = self.get_node_or_null("HumanSpriteSystem")
	
	# Get entity info
	var parent = self
	if parent:
		if "entity_name" in parent:
			entity_name = parent.entity_name
		if "entity_id" in parent:
			entity_id = parent.entity_id

func register_with_systems():
	"""Register this entity with world systems"""
	if tile_occupancy_system and movement_component:
		var pos = movement_component.get_current_tile_position()
		tile_occupancy_system.register_entity_at_tile(self, pos, current_z_level)
	
	# Register with other systems as needed
	var spatial_manager = world.get_node_or_null("SpatialManager") if world else null
	if spatial_manager:
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
	
	if interaction_component:
		interaction_component.process_interaction(entity, button_index, shift_pressed, ctrl_pressed, alt_pressed)

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
	if tile_occupancy_system:
		tile_occupancy_system.move_entity(self, old_tile, new_tile, current_z_level)
	
	# Check environment
	if movement_component:
		movement_component.check_tile_environment()

func _on_movement_state_changed(old_state: int, new_state: int):
	"""Handle movement state changes"""
	# Update sprite system if needed
	if sprite_system and sprite_system.has_method("update_movement_state"):
		sprite_system.update_movement_state(new_state)

func _on_direction_changed(old_dir: int, new_dir: int):
	"""Handle direction changes"""
	if sprite_system:
		movement_component.update_sprite_direction(new_dir)
#endregion

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

# NPC-specific methods
func set_npc_target(target):
	"""Set target for NPC AI"""
	if is_npc and npc_ai_component and npc_ai_component.has_method("set_target"):
		npc_ai_component.set_target(target)

func get_npc_target():
	"""Get current NPC target"""
	if is_npc and npc_ai_component and npc_ai_component.has_method("get_target"):
		return npc_ai_component.get_target()
	return null

func set_npc_behavior(behavior: String):
	"""Set NPC behavior mode"""
	if is_npc and npc_ai_component and npc_ai_component.has_method("set_behavior"):
		npc_ai_component.set_behavior(behavior)

func is_npc_entity() -> bool:
	"""Check if this entity is an NPC"""
	return is_npc

func can_be_controlled_by_player() -> bool:
	"""Check if this entity can be controlled by the player"""
	return not is_npc and is_local_player
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
	if movement_component:
		movement_component.is_local_player = true
	if interaction_component:
		interaction_component.is_local_player = true

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
	if movement_component:
		movement_component.is_local_player = is_local_player
	if interaction_component:
		interaction_component.is_local_player = is_local_player

func setup_npc():
	"""Setup as an NPC"""
	print("GridMovementController: Setting up as NPC")
	
	is_local_player = false
	
	# Add to NPC groups
	add_to_group("npcs")
	add_to_group("entities")
	if can_be_interacted_with:
		add_to_group("clickable_entities")
	
	# Mark as NPC
	set_meta("is_npc", true)
	set_meta("is_player", false)
	
	# Update components
	if movement_component:
		movement_component.is_local_player = false
	if interaction_component:
		interaction_component.is_local_player = false
	
	# Set default NPC intent to help
	if intent_component:
		intent_component.set_intent(0) # HELP intent
	
	print("GridMovementController: NPC setup complete")

func convert_to_npc():
	"""Convert this entity to an NPC at runtime"""
	if is_npc:
		return
	
	print("GridMovementController: Converting to NPC")
	
	# Remove from player groups
	remove_from_group("player_controller")
	remove_from_group("players")
	remove_from_group("remote_players")
	
	# Disconnect from click system
	if click_system:
		if click_system.has_signal("tile_clicked") and click_system.is_connected("tile_clicked", _on_tile_clicked):
			click_system.tile_clicked.disconnect(_on_tile_clicked)
		if click_system.has_signal("entity_clicked") and click_system.is_connected("entity_clicked", _on_entity_clicked):
			click_system.entity_clicked.disconnect(_on_entity_clicked)
	
	# Remove input controller
	if input_controller:
		input_controller.queue_free()
		input_controller = null
	
	# Set NPC status
	is_npc = true
	is_local_player = false
	
	# Setup as NPC
	setup_npc()
	
	print("GridMovementController: Conversion to NPC complete")

func convert_to_player():
	"""Convert this entity to a player at runtime"""
	if not is_npc:
		return
	
	print("GridMovementController: Converting to player")
	
	# Remove from NPC groups
	remove_from_group("npcs")
	
	# Remove AI component
	if npc_ai_component:
		npc_ai_component.queue_free()
		npc_ai_component = null
	
	# Create input controller
	if not input_controller:
		input_controller = InputController.new()
		input_controller.name = "InputController"
		add_child(input_controller)
		input_controller.connect_to_entity(self)
	
	# Set player status
	is_npc = false
	is_local_player = true
	
	# Setup as player
	setup_singleplayer()
	
	# Reconnect to click system
	call_deferred("connect_to_click_system")
	
	print("GridMovementController: Conversion to player complete")
#endregion

func _exit_tree():
	"""Cleanup when removed from scene"""
	# Let components handle their own cleanup
	if grab_pull_component:
		grab_pull_component.cleanup()
	
	# Unregister from systems
	if tile_occupancy_system and movement_component:
		var pos = movement_component.get_current_tile_position()
		tile_occupancy_system.remove_entity(self, pos, current_z_level)
