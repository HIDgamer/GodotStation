extends BaseObject
class_name AlienController

@export var is_npc: bool = false
@export var can_be_interacted_with: bool = true
@export var alien_type: String = "drone"

# System event signals
signal systems_initialized()
signal component_ready(component_name: String)
signal npc_conversion_complete()
signal player_conversion_complete()
signal interaction_started(entity: Node, interaction_type: String)
signal interaction_completed(entity: Node, interaction_type: String, success: bool)
signal alien_ability_used(ability_name: String, target: Node)

# Component node references
@onready var movement_component: MovementComponent = $MovementComponent
@onready var interaction_component: InteractionComponent = $InteractionComponent
@onready var grab_pull_component: AlienGrabPullComponent = $AlienGrabPullComponent
@onready var z_level_component: ZLevelMovementComponent = $ZLevelMovementComponent
@onready var alien_posture_component: AlienPostureComponent = $AlienPostureComponent
@onready var status_effect_component: StatusEffectComponent = $StatusEffectComponent
@onready var alien_vision_component: AlienVisionComponent = $AlienVisionComponent
@onready var alien_input_controller: AlienInputController = $AlienInputController
@onready var click_component: ClickComponent = $ClickComponent

# Entity identification and state
var entity_id: String = ""
var is_local_player: bool = false
var current_z_level: int = 0

# External system references
var world: Node = null
var tile_occupancy_system: Node = null
var sensory_system: Node = null
var alien_sprite_system: Node = null
var audio_system: Node = null
var player_ui = null

# Initialization state tracking
var is_fully_initialized: bool = false
var initialization_in_progress: bool = false

# Alien-specific properties
var pounce_range: int = 4
var pounce_cooldown: float = 3.0
var last_pounce_time: float = 0.0
var acid_spit_range: int = 6
var acid_spit_cooldown: float = 5.0
var last_acid_spit_time: float = 0.0

func _ready():
	entity_type = "alien"
	player_ui = get_node_or_null("PlayerUI")
	
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

func setup_entity_flags():
	if has_meta("is_npc") and get_meta("is_npc"):
		is_npc = true
	if has_meta("is_player") and get_meta("is_player"):
		is_npc = false
	if has_meta("alien_type"):
		alien_type = get_meta("alien_type")

func create_components():
	create_movement_component()
	create_interaction_component()
	create_alien_grab_component()
	create_z_level_component()
	create_alien_posture_component()
	create_status_effect_component()
	create_alien_vision_component()
	create_alien_sprite_system()
	create_alien_health_system()
	create_alien_ai_component()
	create_alien_input_controller()
	create_click_component()
	
	await get_tree().process_frame

func create_alien_ai_component():
	if is_npc:
		var ai_component = AlienAI.new()
		ai_component.name = "AlienAI"
		add_child(ai_component)

func create_movement_component():
	if not movement_component:
		movement_component = MovementComponent.new()
		movement_component.name = "MovementComponent"
		add_child(movement_component)

func create_interaction_component():
	if not interaction_component:
		interaction_component = InteractionComponent.new()
		interaction_component.name = "InteractionComponent"
		add_child(interaction_component)

func create_alien_grab_component():
	if not grab_pull_component:
		grab_pull_component = AlienGrabPullComponent.new()
		grab_pull_component.name = "AlienGrabPullComponent"
		add_child(grab_pull_component)

func create_z_level_component():
	if not z_level_component:
		z_level_component = ZLevelMovementComponent.new()
		z_level_component.name = "ZLevelMovementComponent"
		add_child(z_level_component)

func create_alien_posture_component():
	if not alien_posture_component:
		alien_posture_component = AlienPostureComponent.new()
		alien_posture_component.name = "AlienPostureComponent"
		add_child(alien_posture_component)

func create_status_effect_component():
	if not status_effect_component:
		status_effect_component = StatusEffectComponent.new()
		status_effect_component.name = "StatusEffectComponent"
		add_child(status_effect_component)

func create_alien_vision_component():
	if not alien_vision_component:
		alien_vision_component = AlienVisionComponent.new()
		alien_vision_component.name = "AlienVisionComponent"
		add_child(alien_vision_component)

func create_alien_sprite_system():
	if not alien_sprite_system:
		alien_sprite_system = AlienSpriteSystem.new()
		alien_sprite_system.name = "AlienSpriteSystem"
		alien_sprite_system.alien_type = alien_type
		add_child(alien_sprite_system)

func create_alien_health_system():
	var health_system = get_node_or_null("HealthSystem")
	if not health_system:
		health_system = AlienHealthSystem.new()
		health_system.name = "HealthSystem"
		add_child(health_system)

func create_alien_input_controller():
	if not is_npc and not alien_input_controller:
		alien_input_controller = AlienInputController.new()
		alien_input_controller.name = "AlienInputController"
		add_child(alien_input_controller)

func create_click_component():
	if not is_npc and not click_component:
		click_component = ClickComponent.new()
		click_component.name = "ClickComponent"
		add_child(click_component)
	elif is_npc and click_component:
		click_component.queue_free()
		click_component = null

func initialize_components():
	var init_data = build_initialization_data()
	
	initialize_component(movement_component, init_data)
	initialize_component(interaction_component, init_data)
	initialize_component(grab_pull_component, init_data)
	initialize_component(z_level_component, init_data)
	initialize_component(alien_posture_component, init_data)
	initialize_component(status_effect_component, init_data)
	initialize_component(alien_vision_component, init_data)
	initialize_component(alien_sprite_system, init_data)
	
	var health_system = get_node_or_null("HealthSystem")
	if health_system:
		initialize_component(health_system, init_data)
	
	var ai_component = get_node_or_null("AlienAI")
	if ai_component and is_npc:
		initialize_component(ai_component, init_data)
	
	if alien_input_controller:
		initialize_alien_input_controller()
	
	if click_component and not is_npc:
		initialize_click_component(init_data)
	
	connect_component_signals()
	emit_signal("systems_initialized")

func build_initialization_data() -> Dictionary:
	return {
		"controller": self,
		"world": world,
		"tile_occupancy_system": tile_occupancy_system,
		"sensory_system": sensory_system,
		"sprite_system": alien_sprite_system,
		"audio_system": audio_system,
		"entity_id": entity_id,
		"entity_name": get_entity_name(entity_name),
		"is_local_player": is_local_player,
		"is_npc": is_npc,
		"alien_type": alien_type
	}

func initialize_component(component: Node, init_data: Dictionary):
	if component and component.has_method("initialize"):
		component.initialize(init_data)
		emit_signal("component_ready", component.name)

func initialize_alien_input_controller():
	if alien_input_controller and not is_npc:
		alien_input_controller.connect_to_entity(self)
	elif alien_input_controller and is_npc:
		alien_input_controller.set_active(false)

func initialize_click_component(init_data: Dictionary):
	click_component.initialize(init_data)
	emit_signal("component_ready", "ClickComponent")

func connect_to_external_systems():
	register_with_systems()

func register_with_systems():
	register_with_tile_system()
	register_with_spatial_manager()
	register_with_interaction_system()

func register_with_tile_system():
	if tile_occupancy_system and movement_component:
		var pos = movement_component.get_current_tile_position()
		if tile_occupancy_system.has_method("register_entity_at_tile"):
			tile_occupancy_system.register_entity_at_tile(self, pos, current_z_level)

func register_with_spatial_manager():
	var spatial_manager = world.get_node_or_null("SpatialManager") if world else null
	if spatial_manager and spatial_manager.has_method("register_entity"):
		spatial_manager.register_entity(self)

func register_with_interaction_system():
	var interaction_system = world.get_node_or_null("InteractionSystem") if world else null
	if interaction_system and interaction_system.has_method("register_player"):
		interaction_system.register_player(self, is_local_player)

func setup_singleplayer():
	if is_npc:
		return
	
	is_local_player = true
	
	add_to_group("player_controller")
	add_to_group("players")
	add_to_group("entities")
	add_to_group("clickable_entities")
	add_to_group("dense_entities")
	add_to_group("aliens")
	
	set_meta("is_player", true)
	set_meta("is_npc", false)
	set_meta("alien_type", alien_type)
	
	update_components_for_player()

func setup_npc():
	is_local_player = false
	is_npc = true
	
	add_to_group("npcs")
	add_to_group("entities")
	add_to_group("aliens")
	if can_be_interacted_with:
		add_to_group("clickable_entities")
	add_to_group("dense_entities")
	
	set_meta("is_player", false)
	set_meta("is_npc", true)
	set_meta("alien_type", alien_type)
	
	if alien_sprite_system:
		alien_sprite_system.initialize(build_initialization_data())
	
	update_components_for_npc()
	enable_ai_control()

func enable_ai_control():
	var ai_component = get_node_or_null("AlienAI")
	if ai_component:
		ai_component.set_ai_enabled(true)
	
	if alien_input_controller:
		alien_input_controller.disable_for_alien_npc()

func set_ai_controlled(enabled: bool):
	var ai_component = get_node_or_null("AlienAI")
	
	if enabled:
		is_npc = true
		if ai_component:
			ai_component.set_ai_enabled(true)
		if alien_input_controller:
			alien_input_controller.set_active(false)
	else:
		is_npc = false
		if ai_component:
			ai_component.set_ai_enabled(false)
		if alien_input_controller:
			alien_input_controller.set_active(true)

func update_components_for_player():
	if movement_component:
		movement_component.is_local_player = is_local_player

func update_components_for_npc():
	if player_ui:
		player_ui.queue_free()
		player_ui = null
	
	if alien_input_controller:
		alien_input_controller.set_active(false)
		alien_input_controller.queue_free()
		alien_input_controller = null
	
	if click_component:
		click_component.set_process(false)

# Alien-specific ability methods
func handle_primary_attack():
	if not can_perform_action():
		return
	
	var target = find_nearest_target()
	if target:
		perform_claw_attack(target)

func handle_secondary_attack():
	if not can_perform_action():
		return
	
	var target = find_nearest_target()
	if target:
		perform_tail_attack(target)

func handle_pounce_attack():
	if not can_pounce():
		show_message("Cannot pounce right now.")
		return
	
	var target = find_pounce_target()
	if target:
		perform_pounce(target)
	else:
		show_message("No valid pounce target.")

func handle_acid_spit():
	if not can_acid_spit():
		show_message("Cannot spit acid right now.")
		return
	
	var target = find_ranged_target()
	if target:
		perform_acid_spit(target)
	else:
		show_message("No valid target for acid spit.")

func handle_life_sense():
	if alien_vision_component:
		var life_forms = alien_vision_component.scan_for_life_forms()
		if life_forms.size() > 0:
			show_message("You sense " + str(life_forms.size()) + " life forms nearby.")
		else:
			show_message("No life forms detected.")

func handle_wall_climb():
	show_message("Wall climbing not yet implemented.")

func handle_stealth():
	show_message("Stealth mode not yet implemented.")

func handle_alien_use():
	show_message("Aliens cannot use most objects.")

func set_examine_mode(enabled: bool):
	# Aliens examine differently than humans
	show_message("Alien examination mode toggled.")

func can_perform_action() -> bool:
	if alien_posture_component and alien_posture_component.is_lying:
		return false
	
	if status_effect_component and status_effect_component.has_effect("stunned"):
		return false
	
	return true

func can_pounce() -> bool:
	var current_time = Time.get_ticks_msec() / 1000.0
	return current_time >= last_pounce_time + pounce_cooldown and can_perform_action()

func can_acid_spit() -> bool:
	var current_time = Time.get_ticks_msec() / 1000.0
	return current_time >= last_acid_spit_time + acid_spit_cooldown and can_perform_action()

func find_nearest_target() -> Node:
	if alien_vision_component:
		return alien_vision_component.get_nearest_life_form()
	return null

func find_pounce_target() -> Node:
	var target = find_nearest_target()
	if target:
		var distance = get_distance_to_entity(target)
		if distance <= pounce_range and distance >= 2:
			return target
	return null

func find_ranged_target() -> Node:
	var target = find_nearest_target()
	if target:
		var distance = get_distance_to_entity(target)
		if distance <= acid_spit_range:
			return target
	return null

func get_distance_to_entity(entity: Node) -> float:
	if not movement_component:
		return 999.0
	
	var my_pos = movement_component.current_tile_position
	var target_pos = get_entity_tile_position(entity)
	return my_pos.distance_to(Vector2(target_pos))

func get_entity_tile_position(entity: Node) -> Vector2i:
	if "current_tile_position" in entity:
		return entity.current_tile_position
	elif entity.has_method("get_current_tile_position"):
		return entity.get_current_tile_position()
	return Vector2i.ZERO

func perform_claw_attack(target: Node):
	if interaction_component:
		interaction_component.handle_harm_interaction(target, null)
	
	if alien_sprite_system:
		var direction = get_direction_to_target(target)
		alien_sprite_system.show_interaction_thrust(direction, 3)
	
	emit_signal("alien_ability_used", "claw_attack", target)

func perform_tail_attack(target: Node):
	var damage = 15.0
	if target.has_method("take_damage"):
		target.take_damage(damage, "brute")
	
	if target.has_method("stun"):
		target.stun(2.0)
	
	show_message("You lash out with your tail!")
	emit_signal("alien_ability_used", "tail_attack", target)

func perform_pounce(target: Node):
	last_pounce_time = Time.get_ticks_msec() / 1000.0
	
	var target_pos = get_entity_tile_position(target)
	if movement_component:
		movement_component.move_externally(target_pos, true, true)
	
	# Damage and knockdown target
	if target.has_method("take_damage"):
		target.take_damage(20.0, "brute")
	
	if target.has_method("toggle_lying"):
		target.toggle_lying()
	
	if target.has_method("stun"):
		target.stun(3.0)
	
	show_message("You pounce on " + get_entity_name(target) + "!")
	emit_signal("alien_ability_used", "pounce", target)

func perform_acid_spit(target: Node):
	last_acid_spit_time = Time.get_ticks_msec() / 1000.0
	
	if target.has_method("take_damage"):
		target.take_damage(25.0, "burn")
	
	if target.has_method("add_status_effect"):
		target.add_status_effect("acid_burn", 8.0, 3.0)
	
	show_message("You spit acid at " + get_entity_name(target) + "!")
	emit_signal("alien_ability_used", "acid_spit", target)

func get_direction_to_target(target: Node) -> Vector2:
	var target_pos = target.position if "position" in target else Vector2.ZERO
	return (target_pos - position).normalized()

func show_message(text: String):
	if sensory_system:
		sensory_system.display_message(text)

func get_entity_name(entity) -> String:
	if "entity_name" in entity and entity.entity_name != "":
		return entity.entity_name
	elif "name" in entity:
		return entity.name
	else:
		return "something"

func connect_component_signals():
	if movement_component:
		if movement_component.has_signal("tile_changed"):
			movement_component.tile_changed.connect(_on_tile_changed)
		if movement_component.has_signal("direction_changed"):
			movement_component.direction_changed.connect(_on_direction_changed)
	
	if alien_vision_component:
		if alien_vision_component.has_signal("life_form_detected"):
			alien_vision_component.life_form_detected.connect(_on_life_form_detected)
		if alien_vision_component.has_signal("life_form_lost"):
			alien_vision_component.life_form_lost.connect(_on_life_form_lost)

func _on_tile_changed(old_tile: Vector2i, new_tile: Vector2i):
	if tile_occupancy_system and tile_occupancy_system.has_method("move_entity"):
		tile_occupancy_system.move_entity(self, old_tile, new_tile, current_z_level)

func _on_direction_changed(old_dir: int, new_dir: int):
	if alien_sprite_system:
		alien_sprite_system.set_direction(new_dir)

func _on_life_form_detected(entity: Node):
	if not is_npc:
		show_message("You sense a life form nearby.")

func _on_life_form_lost(entity: Node):
	pass

func find_game_systems():
	world = get_tree().get_first_node_in_group("world")
	
	if world:
		find_world_systems()
	
	find_entity_systems()
	setup_entity_properties()

func find_world_systems():
	tile_occupancy_system = find_world_system(["TileOccupancySystem", "TileSystem", "OccupancySystem"])
	sensory_system = find_world_system(["SensorySystem", "MessageSystem", "SensoryManager"])
	audio_system = find_world_system(["AudioManager", "AudioSystem", "SoundManager"])

func find_world_system(system_names: Array) -> Node:
	for name in system_names:
		var system = world.get_node_or_null(name)
		if system:
			return system
	return null

func find_entity_systems():
	pass

func setup_entity_properties():
	if "entity_name" in self:
		entity_name = self.entity_name
	if "entity_id" in self:
		entity_id = self.entity_id

func get_current_tile_position() -> Vector2i:
	return movement_component.current_tile_position if movement_component else Vector2i.ZERO

func get_current_direction() -> int:
	return movement_component.current_direction if movement_component else 0

func is_adjacent_to(target: Node) -> bool:
	return movement_component.is_adjacent_to(target) if movement_component else false

func move_externally(target_position: Vector2i, animated: bool = true, force: bool = false) -> bool:
	return movement_component.move_externally(target_position, animated, force) if movement_component else false

func take_damage(damage_amount: float, damage_type: int, armor_type: String = "", effects: bool = true, armour_penetration: float = 0.0, attacker: Node = null):
	var health_system = get_node_or_null("HealthSystem")
	if health_system:
		health_system.apply_damage(damage_amount, damage_type)

func _exit_tree():
	if grab_pull_component and grab_pull_component.has_method("cleanup"):
		grab_pull_component.cleanup()
	
	if tile_occupancy_system and movement_component and tile_occupancy_system.has_method("remove_entity"):
		var pos = movement_component.get_current_tile_position()
		tile_occupancy_system.remove_entity(self, pos, current_z_level)
