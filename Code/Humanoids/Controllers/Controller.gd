extends BaseObject
class_name GridMovementController

# Entity configuration
@export_group("Entity Configuration")
@export var is_npc: bool = false
@export var can_be_interacted_with: bool = true
@export var auto_initialize_on_ready: bool = true

@export_group("Skill System")
@export var default_skillset: String = "civilian"
@export var auto_apply_skillset: bool = true

@export_group("Performance Settings")
@export var component_initialization_delay: float = 0.1
@export var system_connection_delay: float = 0.2

# System event signals
signal systems_initialized()
signal component_ready(component_name: String)
signal npc_conversion_complete()
signal player_conversion_complete()
signal initialization_complete()

# Interaction signals
signal interaction_started(entity: Node, interaction_type: String)
signal interaction_completed(entity: Node, interaction_type: String, success: bool)

# Health signals
signal body_part_damaged(part_name: String, current_health: float)

# Component node references
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
@onready var skill_component: SkillComponent = $SkillComponent
@onready var do_after_component: DoAfterComponent = $DoAfterComponent

# Player-only components
@onready var input_controller: InputController = $InputController
@onready var click_component: ClickComponent = $ClickComponent

# Entity identification and state
var entity_id: String = ""
var is_local_player: bool = false

# External system references
var world: Node = null
var tile_occupancy_system: Node = null
var sensory_system: Node = null
var inventory_system: Node = null
var sprite_system: Node = null
var audio_system: Node = null
var health_system: Node = null
var player_ui = null

# Initialization state tracking
var is_fully_initialized: bool = false
var initialization_in_progress: bool = false

func _ready():
	if not auto_initialize_on_ready:
		return
	
	entity_type = "mob"
	player_ui = get_node_or_null("PlayerUI")
	
	if initialization_in_progress:
		return
	
	await _initialize_entity()

# Initialization system
func _initialize_entity():
	initialization_in_progress = true
	
	_setup_entity_flags()
	_find_game_systems()
	
	await _create_components()
	await _initialize_components()
	
	if is_npc:
		call_deferred("_setup_npc")
	else:
		call_deferred("_setup_singleplayer")
	
	call_deferred("_connect_to_external_systems")
	
	is_fully_initialized = true
	initialization_in_progress = false
	
	emit_signal("initialization_complete")

func _setup_entity_flags():
	# Configure entity flags from metadata
	if has_meta("is_npc") and get_meta("is_npc"):
		is_npc = true
	if has_meta("is_player") and get_meta("is_player"):
		is_npc = false

# Component management
func _create_components():
	# Create all required component nodes
	_create_movement_component()
	_create_interaction_component()
	_create_grab_pull_component()
	_create_z_level_component()
	_create_body_targeting_component()
	_create_intent_component()
	_create_status_effect_component()
	_create_item_interaction_component()
	_create_posture_component()
	_create_weapon_handling_component()
	_create_skill_component()
	_create_do_after_component()
	_create_player_only_components()
	
	await get_tree().process_frame

func _create_movement_component():
	if not movement_component:
		movement_component = MovementComponent.new()
		movement_component.name = "MovementComponent"
		add_child(movement_component)

func _create_interaction_component():
	if not interaction_component:
		interaction_component = InteractionComponent.new()
		interaction_component.name = "InteractionComponent"
		add_child(interaction_component)

func _create_grab_pull_component():
	if not grab_pull_component:
		grab_pull_component = GrabPullComponent.new()
		grab_pull_component.name = "GrabPullComponent"
		add_child(grab_pull_component)

func _create_z_level_component():
	if not z_level_component:
		z_level_component = ZLevelMovementComponent.new()
		z_level_component.name = "ZLevelMovementComponent"
		add_child(z_level_component)

func _create_body_targeting_component():
	if not body_targeting_component:
		body_targeting_component = BodyTargetingComponent.new()
		body_targeting_component.name = "BodyTargetingComponent"
		add_child(body_targeting_component)

func _create_intent_component():
	if not intent_component:
		intent_component = IntentComponent.new()
		intent_component.name = "IntentComponent"
		add_child(intent_component)

func _create_status_effect_component():
	if not status_effect_component:
		status_effect_component = StatusEffectComponent.new()
		status_effect_component.name = "StatusEffectComponent"
		add_child(status_effect_component)

func _create_item_interaction_component():
	if not item_interaction_component:
		item_interaction_component = ItemInteractionComponent.new()
		item_interaction_component.name = "ItemInteractionComponent"
		add_child(item_interaction_component)

func _create_posture_component():
	if not posture_component:
		posture_component = PostureComponent.new()
		posture_component.name = "PostureComponent"
		add_child(posture_component)

func _create_weapon_handling_component():
	if not weapon_handling_component:
		weapon_handling_component = WeaponHandlingComponent.new()
		weapon_handling_component.name = "WeaponHandlingComponent"
		add_child(weapon_handling_component)

func _create_skill_component():
	if not skill_component:
		skill_component = SkillComponent.new()
		skill_component.name = "SkillComponent"
		add_child(skill_component)

func _create_do_after_component():
	if not do_after_component:
		do_after_component = DoAfterComponent.new()
		do_after_component.name = "DoAfterComponent"
		add_child(do_after_component)

func _create_player_only_components():
	# Create or remove player-only components based on entity type
	if not is_npc and not input_controller:
		input_controller = InputController.new()
		input_controller.name = "InputController"
		add_child(input_controller)
	elif is_npc and input_controller:
		input_controller.queue_free()
		input_controller = null
	
	if not is_npc and not click_component:
		click_component = ClickComponent.new()
		click_component.name = "ClickComponent"
		add_child(click_component)
	elif is_npc and click_component:
		click_component.queue_free()
		click_component = null

# Component initialization
func _initialize_components():
	var init_data = _build_initialization_data()
	
	# Initialize core components first
	_initialize_component(skill_component, init_data)
	_initialize_component(do_after_component, init_data)
	
	# Initialize other components
	_initialize_component(movement_component, init_data)
	_initialize_component(interaction_component, init_data)
	_initialize_component(grab_pull_component, init_data)
	_initialize_component(z_level_component, init_data)
	_initialize_component(body_targeting_component, init_data)
	_initialize_component(intent_component, init_data)
	_initialize_component(status_effect_component, init_data)
	_initialize_component(item_interaction_component, init_data)
	_initialize_component(posture_component, init_data)
	_initialize_component(weapon_handling_component, init_data)
	
	# Initialize player-only components
	if input_controller and not is_npc:
		_initialize_input_controller()
	
	if click_component and not is_npc:
		_initialize_click_component(init_data)
	
	# Initialize sprite system
	if sprite_system and sprite_system.has_method("initialize"):
		sprite_system.initialize(self)
		emit_signal("component_ready", "HumanSpriteSystem")
	
	_connect_component_signals()
	emit_signal("systems_initialized")

func _build_initialization_data() -> Dictionary:
	return {
		"controller": self,
		"world": world,
		"tile_occupancy_system": tile_occupancy_system,
		"sensory_system": sensory_system,
		"inventory_system": inventory_system,
		"sprite_system": sprite_system,
		"audio_system": audio_system,
		"health_system": health_system,
		"skill_component": skill_component,
		"do_after_component": do_after_component,
		"entity_id": entity_id,
		"entity_name": _get_entity_name(entity_name),
		"is_local_player": is_local_player,
		"is_npc": is_npc,
		"peer_id": 1 if not is_npc else 0
	}

func _initialize_component(component: Node, init_data: Dictionary):
	if component and component.has_method("initialize"):
		component.initialize(init_data)
		emit_signal("component_ready", component.name)

func _initialize_input_controller():
	if input_controller.has_method("connect_to_entity"):
		input_controller.connect_to_entity(self)
	elif input_controller.has_method("initialize"):
		input_controller.initialize(_build_initialization_data())

func _initialize_click_component(init_data: Dictionary):
	click_component.initialize(init_data)
	emit_signal("component_ready", "ClickComponent")

# Entity configuration functions
func _setup_singleplayer():
	if is_npc:
		return
	
	is_local_player = true
	
	# Add to appropriate groups
	add_to_group("player_controller")
	add_to_group("players")
	add_to_group("entities")
	add_to_group("clickable_entities")
	add_to_group("dense_entities")
	
	# Set metadata flags
	set_meta("is_player", true)
	set_meta("is_npc", false)
	
	_setup_entity_skills()
	_update_components_for_player()
	
	emit_signal("player_conversion_complete")

func _setup_npc():
	is_local_player = false
	is_npc = true
	
	# Add to appropriate groups
	add_to_group("npcs")
	add_to_group("entities")
	if can_be_interacted_with:
		add_to_group("clickable_entities")
	
	# Set metadata flags
	set_meta("is_player", false)
	set_meta("is_npc", true)
	
	_setup_entity_skills()
	_update_components_for_npc()
	
	if sprite_system:
		sprite_system.initialize(self)
	
	emit_signal("npc_conversion_complete")

func _setup_entity_skills():
	if not skill_component or not auto_apply_skillset:
		return
	
	var skillset_name = default_skillset
	
	# Determine skillset from entity metadata
	if has_meta("role"):
		skillset_name = _get_skillset_from_role(get_meta("role"))
	elif has_meta("skillset"):
		skillset_name = get_meta("skillset")
	
	skill_component.apply_skillset(skillset_name, true)

func _get_skillset_from_role(role: String) -> String:
	var role_lower = role.to_lower()
	match role_lower:
		"marine", "soldier":
			return "marine"
		"engineer", "tech":
			return "engineer"
		"medic", "doctor":
			return "medic"
		"officer", "commander":
			return "officer"
		_:
			return "civilian"

func _update_components_for_player():
	if movement_component:
		movement_component.is_local_player = is_local_player

func _update_components_for_npc():
	# Remove player UI
	if player_ui:
		player_ui.queue_free()
		player_ui = null
	
	# Deactivate input controller
	if input_controller:
		input_controller.set_active(false)
		input_controller.queue_free()
		input_controller = null
	
	# Disable click processing
	if click_component:
		click_component.set_process(false)
	
	# Set neutral intent
	if intent_component:
		intent_component.set_intent(0)
	
	# Disable weapon handling processing
	if weapon_handling_component:
		weapon_handling_component.set_process(false)

# System connection functions
func _connect_to_external_systems():
	_register_with_systems()

func _register_with_systems():
	_register_with_tile_system()
	_register_with_spatial_manager()
	_register_with_interaction_system()

func _register_with_tile_system():
	if tile_occupancy_system and movement_component:
		var pos = movement_component.get_current_tile_position()
		if tile_occupancy_system.has_method("register_entity_at_tile"):
			tile_occupancy_system.register_entity_at_tile(self, pos, current_z_level)

func _register_with_spatial_manager():
	var spatial_manager = world.get_node_or_null("SpatialManager") if world else null
	if spatial_manager and spatial_manager.has_method("register_entity"):
		spatial_manager.register_entity(self)

func _register_with_interaction_system():
	var interaction_system = world.get_node_or_null("InteractionSystem") if world else null
	if interaction_system and interaction_system.has_method("register_player"):
		interaction_system.register_player(self, is_local_player)

# System reference finding
func _find_game_systems():
	world = get_tree().get_first_node_in_group("world")
	
	if world:
		_find_world_systems()
	
	_find_entity_systems()
	_setup_entity_properties()

func _find_world_systems():
	tile_occupancy_system = _find_world_system(["TileOccupancySystem", "TileSystem", "OccupancySystem"])
	sensory_system = _find_world_system(["SensorySystem", "MessageSystem", "SensoryManager"])
	audio_system = _find_world_system(["AudioManager", "AudioSystem", "SoundManager"])

func _find_world_system(system_names: Array) -> Node:
	for name in system_names:
		var system = world.get_node_or_null(name)
		if system:
			return system
	return null

func _find_entity_systems():
	inventory_system = get_node_or_null("InventorySystem")
	sprite_system = get_node_or_null("HumanSpriteSystem")
	health_system = get_parent().get_node_or_null("HealthSystem") if get_parent() else null

func _setup_entity_properties():
	if "entity_name" in self:
		entity_name = self.entity_name
	if "entity_id" in self:
		entity_id = self.entity_id

# Signal connection system
func _connect_component_signals():
	_connect_movement_signals()
	_connect_intent_signals()
	_connect_grab_signals()
	_connect_status_signals()
	_connect_posture_signals()
	_connect_weapon_signals()
	_connect_do_after_signals()

func _connect_movement_signals():
	if movement_component:
		if not movement_component.tile_changed.is_connected(_on_tile_changed):
			movement_component.tile_changed.connect(_on_tile_changed)
		if not movement_component.direction_changed.is_connected(_on_direction_changed):
			movement_component.direction_changed.connect(_on_direction_changed)

func _connect_intent_signals():
	if intent_component and interaction_component:
		if not intent_component.intent_changed.is_connected(interaction_component._on_intent_changed):
			intent_component.intent_changed.connect(interaction_component._on_intent_changed)

func _connect_grab_signals():
	if grab_pull_component and movement_component:
		if grab_pull_component.has_signal("movement_modifier_changed") and movement_component.has_method("set_movement_modifier"):
			if not grab_pull_component.movement_modifier_changed.is_connected(movement_component.set_movement_modifier):
				grab_pull_component.movement_modifier_changed.connect(movement_component.set_movement_modifier)

func _connect_status_signals():
	if status_effect_component and movement_component:
		if status_effect_component.has_signal("movement_speed_changed") and movement_component.has_method("set_speed_modifier"):
			if not status_effect_component.movement_speed_changed.is_connected(movement_component.set_speed_modifier):
				status_effect_component.movement_speed_changed.connect(movement_component.set_speed_modifier)

func _connect_posture_signals():
	if posture_component and movement_component:
		if posture_component.has_signal("lying_state_changed") and movement_component.has_method("_on_lying_state_changed"):
			if not posture_component.lying_state_changed.is_connected(movement_component._on_lying_state_changed):
				posture_component.lying_state_changed.connect(movement_component._on_lying_state_changed)

func _connect_weapon_signals():
	if weapon_handling_component:
		if not weapon_handling_component.both_hands_occupied_changed.is_connected(_on_both_hands_occupied_changed):
			weapon_handling_component.both_hands_occupied_changed.connect(_on_both_hands_occupied_changed)

func _connect_do_after_signals():
	if do_after_component:
		if not do_after_component.do_after_started.is_connected(_on_do_after_started):
			do_after_component.do_after_started.connect(_on_do_after_started)
		if not do_after_component.do_after_completed.is_connected(_on_do_after_completed):
			do_after_component.do_after_completed.connect(_on_do_after_completed)
		if not do_after_component.do_after_cancelled.is_connected(_on_do_after_cancelled):
			do_after_component.do_after_cancelled.connect(_on_do_after_cancelled)

# DoAfter interface functions
func start_do_after_action(action_name: String, config_override: Dictionary = {}, callback: Callable = Callable(), target: Node = null) -> bool:
	if do_after_component:
		return do_after_component.start_action(action_name, config_override, callback, target)
	return false

func start_instant_action(action_name: String, callback: Callable = Callable(), target: Node = null) -> bool:
	if do_after_component:
		return do_after_component.start_instant_action(action_name, callback, target)
	return false

func cancel_current_action(reason: String = "manual") -> bool:
	if do_after_component:
		return do_after_component.cancel_action(reason)
	return false

func force_complete_current_action() -> bool:
	if do_after_component:
		return do_after_component.force_complete_action()
	return false

func is_performing_action() -> bool:
	if do_after_component:
		return do_after_component.is_performing_action()
	return false

func get_current_action() -> String:
	if do_after_component:
		return do_after_component.get_current_action()
	return ""

func get_action_progress() -> float:
	if do_after_component:
		return do_after_component.get_action_progress()
	return 0.0

func get_action_remaining_time() -> float:
	if do_after_component:
		return do_after_component.get_remaining_time()
	return 0.0

func can_start_new_action() -> bool:
	if do_after_component:
		return do_after_component.can_start_new_action()
	return true

func should_block_movement() -> bool:
	if do_after_component:
		return do_after_component.should_block_movement()
	return false

func should_block_interactions() -> bool:
	if do_after_component:
		return do_after_component.should_block_interactions()
	return false

# Action-specific convenience functions
func start_medical_action(action_type: String, target: Node = null, callback: Callable = Callable()) -> bool:
	if do_after_component:
		return do_after_component.start_medical_action(action_type, target, callback)
	return false

func start_combat_action(action_type: String, target: Node = null, callback: Callable = Callable()) -> bool:
	if do_after_component:
		return do_after_component.start_combat_action(action_type, target, callback)
	return false

func start_engineering_action(action_type: String, target: Node = null, callback: Callable = Callable()) -> bool:
	if do_after_component:
		return do_after_component.start_engineering_action(action_type, target, callback)
	return false

func start_posture_action(action_type: String, callback: Callable = Callable()) -> bool:
	if do_after_component:
		return do_after_component.start_posture_action(action_type, callback)
	return false

# NPC control interface
func npc_move_to_tile(target_tile: Vector2i) -> bool:
	if not is_npc:
		return false
	
	if movement_component and movement_component.has_method("npc_move_to"):
		return movement_component.npc_move_to(target_tile)
	
	return false

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

# Skill system interface
func get_skill_level(skill_name: String) -> int:
	if skill_component:
		return skill_component.get_skill_level(skill_name)
	return 0

func is_skilled(skill_name: String, required_level: int) -> bool:
	if skill_component:
		return skill_component.is_skilled(skill_name, required_level)
	return false

func skillcheck(skill_name: String, required_level: int, show_message: bool = true) -> bool:
	if skill_component:
		return skill_component.skillcheck(skill_name, required_level, show_message)
	return false

# Entity state getters
func get_current_tile_position() -> Vector2i:
	return movement_component.current_tile_position if movement_component else Vector2i.ZERO

func get_current_direction() -> int:
	return movement_component.current_direction if movement_component else 0

func get_intent() -> int:
	return intent_component.intent if intent_component else 0

func set_intent(new_intent: int):
	if intent_component:
		intent_component.set_intent(new_intent)

# Interaction interface
func can_interact_with(target: Node) -> bool:
	return interaction_component.can_interact_with(target) if interaction_component else false

func is_adjacent_to(target: Node) -> bool:
	return movement_component.is_adjacent_to(target) if movement_component else false

# Movement interface
func move_externally(target_position: Vector2i, animated: bool = true, force: bool = false) -> bool:
	return movement_component.move_externally(target_position, animated, force) if movement_component else false

func apply_knockback(direction: Vector2, force: float):
	if movement_component:
		movement_component.apply_knockback(direction, force)

# Status effects interface
func stun(duration: float):
	if status_effect_component:
		status_effect_component.apply_stun(duration)

func take_damage(damage_amount: float, damage_type: int, armor_type: String = "", effects: bool = true, armour_penetration: float = 0.0, attacker: Node = null):
	var health_system = get_parent().get_node_or_null("HealthSystem")
	if health_system:
		health_system.take_damage(damage_amount, damage_type)

# Entity type queries
func is_npc_entity() -> bool:
	return is_npc

func can_be_controlled_by_player() -> bool:
	return not is_npc and is_local_player

func can_process_player_input() -> bool:
	return not is_npc and is_local_player

# Weapon handling interface
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

# Entity conversion functions
func convert_to_player():
	if not is_npc:
		return
	
	var was_initialized = is_fully_initialized
	is_fully_initialized = false
	
	remove_from_group("npcs")
	
	# Create player-only components
	if not input_controller:
		_create_input_controller()
		await get_tree().process_frame
		_initialize_input_controller()
	
	if not click_component:
		_create_click_component()
		await get_tree().process_frame
		_initialize_click_component(_build_initialization_data())
	
	# Enable weapon handling for converted player
	if weapon_handling_component:
		weapon_handling_component.set_process(true)
	
	is_npc = false
	is_local_player = true
	
	_setup_singleplayer()
	
	if was_initialized:
		_connect_component_signals()
		is_fully_initialized = true
	
	emit_signal("player_conversion_complete")

func _create_input_controller():
	input_controller = InputController.new()
	input_controller.name = "InputController"
	add_child(input_controller)

func _create_click_component():
	click_component = ClickComponent.new()
	click_component.name = "ClickComponent"
	add_child(click_component)

# UI registration
func register_player_ui(ui_instance: Node):
	if click_component:
		click_component.register_player_ui(ui_instance)
	
	if weapon_handling_component:
		weapon_handling_component.player_ui = ui_instance

# Signal handlers
func _on_tile_changed(old_tile: Vector2i, new_tile: Vector2i):
	if tile_occupancy_system and tile_occupancy_system.has_method("move_entity"):
		tile_occupancy_system.move_entity(self, old_tile, new_tile, current_z_level)
	
	if movement_component:
		movement_component.check_tile_environment()

func _on_direction_changed(old_dir: int, new_dir: int):
	if sprite_system:
		sprite_system.set_direction(new_dir)

func _on_both_hands_occupied_changed(is_occupied: bool):
	# Tracked by UI systems for hand switching controls
	pass

func _on_do_after_started(action_name: String, duration: float):
	emit_signal("interaction_started", self, action_name)
	
	# Notify systems that the entity is busy
	if movement_component and do_after_component.should_block_movement():
		movement_component.set_movement_blocked(true)

func _on_do_after_completed(action_name: String, success: bool):
	emit_signal("interaction_completed", self, action_name, success)
	
	# Restore movement if it was blocked
	if movement_component:
		movement_component.set_movement_blocked(false)

func _on_do_after_cancelled(action_name: String, reason: String):
	emit_signal("interaction_completed", self, action_name, false)
	
	# Restore movement if it was blocked
	if movement_component:
		movement_component.set_movement_blocked(false)

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

# Utility functions
func _get_entity_name(entity) -> String:
	if "entity_name" in entity and entity.entity_name != "":
		return entity.entity_name
	elif "name" in entity:
		return entity.name
	else:
		return "something"

func force_initialize():
	if initialization_in_progress:
		return false
	
	await _initialize_entity()
	return true

func get_initialization_status() -> Dictionary:
	return {
		"is_initialized": is_fully_initialized,
		"in_progress": initialization_in_progress,
		"is_npc": is_npc,
		"is_local_player": is_local_player,
		"components_created": _count_created_components()
	}

func _count_created_components() -> int:
	var count = 0
	var components = [
		movement_component, interaction_component, grab_pull_component,
		z_level_component, body_targeting_component, intent_component,
		status_effect_component, item_interaction_component, posture_component,
		weapon_handling_component, skill_component, do_after_component,
		input_controller, click_component
	]
	
	for component in components:
		if component:
			count += 1
	
	return count

# Cleanup function
func _exit_tree():
	if do_after_component and do_after_component.has_method("cancel_action"):
		do_after_component.cancel_action("entity_cleanup")
	
	if grab_pull_component and grab_pull_component.has_method("cleanup"):
		grab_pull_component.cleanup()
	
	if weapon_handling_component and weapon_handling_component.has_method("force_unwield"):
		weapon_handling_component.force_unwield()
	
	if tile_occupancy_system and movement_component and tile_occupancy_system.has_method("remove_entity"):
		var pos = movement_component.get_current_tile_position()
		tile_occupancy_system.remove_entity(self, pos, current_z_level)
