extends BaseObject
class_name GridMovementController

@export var is_npc: bool = false
@export var can_be_interacted_with: bool = true

# Signals for system events
signal systems_initialized()
signal component_ready(component_name: String)
signal npc_conversion_complete()
signal player_conversion_complete()
signal interaction_started(entity: Node, interaction_type: String)
signal interaction_completed(entity: Node, interaction_type: String, success: bool)
signal body_part_damaged(part_name: String, current_health: float)

# Component references
@onready var movement_component: MovementComponent = $MovementComponent
@onready var interaction_component: InteractionComponent = $InteractionComponent
@onready var grab_pull_component: GrabPullComponent = $GrabPullComponent
@onready var z_level_component: ZLevelMovementComponent = $ZLevelMovementComponent
@onready var body_targeting_component: BodyTargetingComponent = $BodyTargetingComponent
@onready var intent_component: IntentComponent = $IntentComponent
@onready var status_effect_component: StatusEffectComponent = $StatusEffectComponent
@onready var item_interaction_component: ItemInteractionComponent = $ItemInteractionComponent
@onready var posture_component: PostureComponent = $PostureComponent
@onready var weapon_handling_component: WeaponHandlingComponent = $WeaponHandlingComponent
@onready var input_controller: InputController = $InputController
@onready var click_component: ClickComponent = $ClickComponent

# Entity properties
var entity_id: String = ""
var is_local_player: bool = false
var current_z_level: int = 0

# System references
var world: Node = null
var tile_occupancy_system: Node = null
var sensory_system: Node = null
var inventory_system: Node = null
var sprite_system: Node = null
var audio_system: Node = null

# Initialization tracking
var is_fully_initialized: bool = false
var initialization_in_progress: bool = false

func _ready():
	entity_type = "mob"
	
	if initialization_in_progress:
		return
	initialization_in_progress = true
	
	setup_entity_flags()
	find_game_systems()
	
	await create_components()
	await initialize_components()
	
	if is_npc:
		call_deferred("setup_npc")
	else:
		call_deferred("setup_singleplayer")
	
	call_deferred("connect_to_external_systems")
	
	is_fully_initialized = true
	initialization_in_progress = false

# Sets entity flags based on metadata
func setup_entity_flags():
	if has_meta("is_npc") and get_meta("is_npc"):
		is_npc = true
	if has_meta("is_player") and get_meta("is_player"):
		is_npc = false

# Creates all required components
func create_components():
	create_movement_component()
	create_interaction_component()
	create_grab_pull_component()
	create_z_level_component()
	create_body_targeting_component()
	create_intent_component()
	create_status_effect_component()
	create_item_interaction_component()
	create_posture_component()
	create_weapon_handling_component()
	create_input_controller()
	create_click_component()
	
	await get_tree().process_frame

# Creates movement component if missing
func create_movement_component():
	if not movement_component:
		movement_component = MovementComponent.new()
		movement_component.name = "MovementComponent"
		add_child(movement_component)

# Creates interaction component if missing
func create_interaction_component():
	if not interaction_component:
		interaction_component = InteractionComponent.new()
		interaction_component.name = "InteractionComponent"
		add_child(interaction_component)

# Creates grab and pull component if missing
func create_grab_pull_component():
	if not grab_pull_component:
		grab_pull_component = GrabPullComponent.new()
		grab_pull_component.name = "GrabPullComponent"
		add_child(grab_pull_component)

# Creates z-level movement component if missing
func create_z_level_component():
	if not z_level_component:
		z_level_component = ZLevelMovementComponent.new()
		z_level_component.name = "ZLevelMovementComponent"
		add_child(z_level_component)

# Creates body targeting component if missing
func create_body_targeting_component():
	if not body_targeting_component:
		body_targeting_component = BodyTargetingComponent.new()
		body_targeting_component.name = "BodyTargetingComponent"
		add_child(body_targeting_component)

# Creates intent component if missing
func create_intent_component():
	if not intent_component:
		intent_component = IntentComponent.new()
		intent_component.name = "IntentComponent"
		add_child(intent_component)

# Creates status effect component if missing
func create_status_effect_component():
	if not status_effect_component:
		status_effect_component = StatusEffectComponent.new()
		status_effect_component.name = "StatusEffectComponent"
		add_child(status_effect_component)

# Creates item interaction component if missing
func create_item_interaction_component():
	if not item_interaction_component:
		item_interaction_component = ItemInteractionComponent.new()
		item_interaction_component.name = "ItemInteractionComponent"
		add_child(item_interaction_component)

# Creates posture component if missing
func create_posture_component():
	if not posture_component:
		posture_component = PostureComponent.new()
		posture_component.name = "PostureComponent"
		add_child(posture_component)

# Creates weapon handling component if missing
func create_weapon_handling_component():
	if not weapon_handling_component:
		weapon_handling_component = WeaponHandlingComponent.new()
		weapon_handling_component.name = "WeaponHandlingComponent"
		add_child(weapon_handling_component)

# Creates input controller for players only
func create_input_controller():
	if not is_npc and not input_controller:
		input_controller = InputController.new()
		input_controller.name = "InputController"
		add_child(input_controller)
	elif is_npc and input_controller:
		input_controller.queue_free()
		input_controller = null

# Creates click component for players only
func create_click_component():
	if not is_npc and not click_component:
		click_component = ClickComponent.new()
		click_component.name = "ClickComponent"
		add_child(click_component)
	elif is_npc and click_component:
		click_component.queue_free()
		click_component = null

# Initializes all components with shared data
func initialize_components():
	var init_data = build_initialization_data()
	
	initialize_component(movement_component, init_data)
	initialize_component(interaction_component, init_data)
	initialize_component(grab_pull_component, init_data)
	initialize_component(z_level_component, init_data)
	initialize_component(body_targeting_component, init_data)
	initialize_component(intent_component, init_data)
	initialize_component(status_effect_component, init_data)
	initialize_component(item_interaction_component, init_data)
	initialize_component(posture_component, init_data)
	initialize_component(weapon_handling_component, init_data)
	
	if input_controller and not is_npc:
		initialize_input_controller()
	
	if click_component and not is_npc:
		initialize_click_component(init_data)
	
	if sprite_system and sprite_system.has_method("initialize"):
		sprite_system.initialize(self)
		emit_signal("component_ready", "HumanSpriteSystem")
	
	connect_component_signals()
	emit_signal("systems_initialized")

# Builds initialization data dictionary for components
func build_initialization_data() -> Dictionary:
	return {
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
		"is_npc": is_npc
	}

# Initializes a single component with error handling
func initialize_component(component: Node, init_data: Dictionary):
	if component and component.has_method("initialize"):
		component.initialize(init_data)
		emit_signal("component_ready", component.name)

# Initializes input controller for player entities
func initialize_input_controller():
	if input_controller.has_method("connect_to_entity"):
		input_controller.connect_to_entity(self)
	elif input_controller.has_method("initialize"):
		input_controller.initialize(build_initialization_data())

# Initializes click component for player entities
func initialize_click_component(init_data: Dictionary):
	click_component.initialize(init_data)
	emit_signal("component_ready", "ClickComponent")

# Connects to external game systems
func connect_to_external_systems():
	register_with_systems()

# Registers entity with various game systems
func register_with_systems():
	register_with_tile_system()
	register_with_spatial_manager()
	register_with_specialized_managers()

# Registers entity with tile occupancy system
func register_with_tile_system():
	if tile_occupancy_system and movement_component:
		var pos = movement_component.get_current_tile_position()
		if tile_occupancy_system.has_method("register_entity_at_tile"):
			tile_occupancy_system.register_entity_at_tile(self, pos, current_z_level)

# Registers entity with spatial manager
func register_with_spatial_manager():
	var spatial_manager = world.get_node_or_null("SpatialManager") if world else null
	if spatial_manager and spatial_manager.has_method("register_entity"):
		spatial_manager.register_entity(self)

# Registers entity with specialized managers based on type
func register_with_specialized_managers():
	if is_npc:
		register_with_npc_manager()
	else:
		register_with_interaction_system()

# Registers NPC with NPC manager
func register_with_npc_manager():
	var npc_manager = world.get_node_or_null("NPCManager") if world else null
	if npc_manager and npc_manager.has_method("register_npc"):
		npc_manager.register_npc(self)

# Registers player with interaction system
func register_with_interaction_system():
	var interaction_system = world.get_node_or_null("InteractionSystem") if world else null
	if interaction_system and interaction_system.has_method("register_player"):
		interaction_system.register_player(self, is_local_player)

# Moves NPC to target tile position
func npc_move_to_tile(target_tile: Vector2i) -> bool:
	if not is_npc:
		return false
	
	if movement_component and movement_component.has_method("npc_move_to"):
		return movement_component.npc_move_to(target_tile)
	
	return false

# Makes NPC interact with target entity
func npc_interact_with(target: Node, interaction_type: String = "help"):
	if not is_npc:
		return
	
	if interaction_component:
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

# Configures entity as a singleplayer character
func setup_singleplayer():
	if is_npc:
		return
	
	is_local_player = true
	
	add_to_group("player_controller")
	add_to_group("players")
	add_to_group("entities")
	add_to_group("clickable_entities")
	
	set_meta("is_player", true)
	set_meta("is_npc", false)
	
	update_components_for_player()

# Configures entity as an NPC
func setup_npc():
	is_local_player = false
	is_npc = true
	
	add_to_group("npcs")
	add_to_group("entities")
	if can_be_interacted_with:
		add_to_group("clickable_entities")
	
	set_meta("is_player", false)
	set_meta("is_npc", true)
	
	if sprite_system:
		sprite_system.initialize(self)
	
	update_components_for_npc()

# Updates components for player configuration
func update_components_for_player():
	if movement_component:
		movement_component.is_local_player = is_local_player

# Updates components for NPC configuration
func update_components_for_npc():
	if movement_component:
		movement_component.is_local_player = false
	
	if input_controller:
		if input_controller.has_method("disable_for_npc"):
			input_controller.disable_for_npc()
		else:
			input_controller.queue_free()
			input_controller = null
	
	if intent_component:
		intent_component.set_intent(0)
	
	# Disable weapon handling for NPCs
	if weapon_handling_component:
		weapon_handling_component.set_process(false)

# Returns current tile position
func get_current_tile_position() -> Vector2i:
	return movement_component.current_tile_position if movement_component else Vector2i.ZERO

# Returns current facing direction
func get_current_direction() -> int:
	return movement_component.current_direction if movement_component else 0

# Returns current intent value
func get_intent() -> int:
	return intent_component.intent if intent_component else 0

# Sets new intent value
func set_intent(new_intent: int):
	if intent_component:
		intent_component.set_intent(new_intent)

# Checks if entity can interact with target
func can_interact_with(target: Node) -> bool:
	return interaction_component.can_interact_with(target) if interaction_component else false

# Checks if entity is adjacent to target
func is_adjacent_to(target: Node) -> bool:
	return movement_component.is_adjacent_to(target) if movement_component else false

# Moves entity to external position
func move_externally(target_position: Vector2i, animated: bool = true, force: bool = false) -> bool:
	return movement_component.move_externally(target_position, animated, force) if movement_component else false

# Applies knockback force to entity
func apply_knockback(direction: Vector2, force: float):
	if movement_component:
		movement_component.apply_knockback(direction, force)

# Applies stun effect to entity
func stun(duration: float):
	if status_effect_component:
		status_effect_component.apply_stun(duration)

# Applies damage to entity
func take_damage(damage_amount: float, damage_type: String = "brute", armor_type: String = "", effects: bool = true, armour_penetration: float = 0.0, attacker: Node = null):
	var health_system = get_parent().get_node_or_null("HealthSystem")
	if health_system:
		health_system.take_damage(damage_amount, damage_type)

# Returns whether entity is an NPC
func is_npc_entity() -> bool:
	return is_npc

# Returns whether entity can be controlled by player
func can_be_controlled_by_player() -> bool:
	return not is_npc and is_local_player

# Returns whether entity can process player input
func can_process_player_input() -> bool:
	return not is_npc and is_local_player

# Weapon handling methods
func try_wield_weapon(weapon: Node) -> bool:
	if weapon_handling_component:
		return weapon_handling_component.try_wield_weapon(weapon)
	return false

func unwield_weapon() -> bool:
	if weapon_handling_component:
		return weapon_handling_component.unwield_weapon()
	return false

func is_wielding_weapon() -> bool:
	if weapon_handling_component:
		return weapon_handling_component.is_wielding_weapon()
	return false

func get_wielded_weapon() -> Node:
	if weapon_handling_component:
		return weapon_handling_component.get_wielded_weapon()
	return null

func can_switch_hands() -> bool:
	if weapon_handling_component:
		return weapon_handling_component.can_switch_hands_currently()
	return true

# Connects signals between components
func connect_component_signals():
	connect_movement_signals()
	connect_intent_signals()
	connect_grab_signals()
	connect_status_signals()
	connect_posture_signals()
	connect_weapon_signals()

# Connects movement-related signals
func connect_movement_signals():
	if movement_component:
		if not movement_component.tile_changed.is_connected(_on_tile_changed):
			movement_component.tile_changed.connect(_on_tile_changed)
		if not movement_component.direction_changed.is_connected(_on_direction_changed):
			movement_component.direction_changed.connect(_on_direction_changed)

# Connects intent-related signals
func connect_intent_signals():
	if intent_component and interaction_component:
		if not intent_component.intent_changed.is_connected(interaction_component._on_intent_changed):
			intent_component.intent_changed.connect(interaction_component._on_intent_changed)

# Connects grab and pull signals
func connect_grab_signals():
	if grab_pull_component and movement_component:
		if grab_pull_component.has_signal("movement_modifier_changed") and movement_component.has_method("set_movement_modifier"):
			if not grab_pull_component.movement_modifier_changed.is_connected(movement_component.set_movement_modifier):
				grab_pull_component.movement_modifier_changed.connect(movement_component.set_movement_modifier)

# Connects status effect signals
func connect_status_signals():
	if status_effect_component and movement_component:
		if status_effect_component.has_signal("movement_speed_changed") and movement_component.has_method("set_speed_modifier"):
			if not status_effect_component.movement_speed_changed.is_connected(movement_component.set_speed_modifier):
				status_effect_component.movement_speed_changed.connect(movement_component.set_speed_modifier)

# Connects posture-related signals
func connect_posture_signals():
	if posture_component and movement_component:
		if posture_component.has_signal("lying_state_changed") and movement_component.has_method("_on_lying_state_changed"):
			if not posture_component.lying_state_changed.is_connected(movement_component._on_lying_state_changed):
				posture_component.lying_state_changed.connect(movement_component._on_lying_state_changed)

# Connects weapon handling signals
func connect_weapon_signals():
	if weapon_handling_component:
		if not weapon_handling_component.both_hands_occupied_changed.is_connected(_on_both_hands_occupied_changed):
			weapon_handling_component.both_hands_occupied_changed.connect(_on_both_hands_occupied_changed)

# Finds and stores references to game systems
func find_game_systems():
	world = get_tree().get_first_node_in_group("world")
	
	if world:
		find_world_systems()
	
	find_entity_systems()
	setup_entity_properties()

# Finds systems attached to the world
func find_world_systems():
	tile_occupancy_system = find_world_system(["TileOccupancySystem", "TileSystem", "OccupancySystem"])
	sensory_system = find_world_system(["SensorySystem", "MessageSystem", "SensoryManager"])
	audio_system = find_world_system(["AudioManager", "AudioSystem", "SoundManager"])

# Finds a world system by trying multiple possible names
func find_world_system(system_names: Array) -> Node:
	for name in system_names:
		var system = world.get_node_or_null(name)
		if system:
			return system
	return null

# Finds systems attached to this entity
func find_entity_systems():
	inventory_system = get_node_or_null("InventorySystem")
	sprite_system = get_node_or_null("HumanSpriteSystem")

# Sets up entity name and ID properties
func setup_entity_properties():
	if "entity_name" in self:
		entity_name = self.entity_name
	if "entity_id" in self:
		entity_id = self.entity_id

# Returns entity name from various sources
func get_entity_name(entity) -> String:
	if "entity_name" in entity and entity.entity_name != "":
		return entity.entity_name
	elif "name" in entity:
		return entity.name
	else:
		return "something"

# Handles tile position changes
func _on_tile_changed(old_tile: Vector2i, new_tile: Vector2i):
	if tile_occupancy_system and tile_occupancy_system.has_method("move_entity"):
		tile_occupancy_system.move_entity(self, old_tile, new_tile, current_z_level)
	
	if movement_component:
		movement_component.check_tile_environment()

# Handles direction changes
func _on_direction_changed(old_dir: int, new_dir: int):
	if sprite_system:
		sprite_system.set_direction(new_dir)

# Handles weapon wielding state changes
func _on_both_hands_occupied_changed(is_occupied: bool):
	# This will be used by UI to show/hide hand switching controls
	pass

# Handles NPC interaction requests
func _on_npc_interaction_requested(target: Node, interaction_type: String):
	if not is_npc:
		return
	
	if interaction_component:
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

# Converts NPC to player character
func convert_to_player():
	if not is_npc:
		return
	
	var was_initialized = is_fully_initialized
	is_fully_initialized = false
	
	remove_from_group("npcs")
	
	if not input_controller:
		create_input_controller()
		await get_tree().process_frame
		initialize_input_controller()
	
	if not click_component:
		create_click_component()
		await get_tree().process_frame
		initialize_click_component(build_initialization_data())
	
	# Enable weapon handling for converted player
	if weapon_handling_component:
		weapon_handling_component.set_process(true)
	
	is_npc = false
	is_local_player = true
	
	setup_singleplayer()
	
	if was_initialized:
		connect_component_signals()
		is_fully_initialized = true
	
	emit_signal("player_conversion_complete")

# Registers PlayerUI with click component
func register_player_ui(ui_instance: Node):
	if click_component:
		click_component.register_player_ui(ui_instance)
	
	# Also register with weapon handling component
	if weapon_handling_component:
		weapon_handling_component.player_ui = ui_instance

# Cleans up entity when removed from scene
func _exit_tree():
	if grab_pull_component and grab_pull_component.has_method("cleanup"):
		grab_pull_component.cleanup()
	
	if weapon_handling_component and weapon_handling_component.has_method("force_unwield"):
		weapon_handling_component.force_unwield()
	
	if tile_occupancy_system and movement_component and tile_occupancy_system.has_method("remove_entity"):
		var pos = movement_component.get_current_tile_position()
		tile_occupancy_system.remove_entity(self, pos, current_z_level)
