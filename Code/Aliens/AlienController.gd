extends BaseObject
class_name AlienController

@export_group("Entity Configuration")
@export var can_be_interacted_with: bool = true
@export var auto_initialize_on_ready: bool = true
@export var alien_type: String = "Drone"

@export_group("AI Configuration")
@export var ai_enabled: bool = true
@export var player_controlled: bool = false
@export var ai_detection_range: float = 8.0
@export var ai_attack_range: float = 1.5

@export_group("Audio Configuration")
@export var enable_audio: bool = true
@export var audio_volume: float = 1.0
@export var audio_range: float = 15.0

@export_group("Performance Settings")
@export var component_initialization_delay: float = 0.1

signal systems_initialized()
signal component_ready(component_name: String)
signal initialization_complete()

signal body_part_damaged(part_name: String, current_health: float)
signal alien_died(cause_of_death: String)
signal alien_revived()

signal target_acquired(target: Node)
signal target_lost()

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
@onready var do_after_component: DoAfterComponent = $DoAfterComponent
@onready var sensory_system: SensorySystem = $SensorySystem
@onready var health_system: HealthSystem = $HealthSystem
@onready var player_ui: PlayerUI = $PlayerUI

@onready var input_controller: InputController = $InputController
@onready var click_component: ClickComponent = $ClickComponent

@onready var alien_sprite_system: AlienSpriteSystem = $AlienSpriteSystem
@onready var alien_ai_component: AlienAIComponent = $AlienAIComponent

var audio_player: AudioStreamPlayer2D
var death_audio_player: AudioStreamPlayer2D
var detection_audio_player: AudioStreamPlayer2D
var attack_audio_player: AudioStreamPlayer2D

var entity_id: String = ""
var is_local_player: bool = false
var alien_faction: String = "alien"
var is_dead: bool = false

var world: Node = null
var tile_occupancy_system: Node = null
var audio_system: Node = null

var is_fully_initialized: bool = false
var initialization_in_progress: bool = false

var death_sounds: Array[String] = [
	"res://Sound/voice/alien_death.ogg",
	"res://Sound/voice/alien_death2.ogg"
]

var gib_sounds: Array[String] = [
	"res://Sound/effects/gibbed.ogg"
]

var attack_sounds: Array[String] = [
	"res://Sound/weapons/genhit1.ogg",
	"res://Sound/weapons/genhit2.ogg",
	"res://Sound/weapons/genhit3.ogg"
]

var detection_sounds: Array[String] = [
	"res://Sound/voice/alien_hiss1.ogg",
	"res://Sound/voice/alien_hiss2.ogg",
	"res://Sound/voice/alien_hiss3.ogg"
]

var spawn_sounds: Array[String] = [
	"res://Sound/voice/alien_growl1.ogg",
	"res://Sound/voice/alien_growl2.ogg",
	"res://Sound/voice/alien_growl3.ogg"
]

var has_played_spawn_sound: bool = false

func _ready():
	_setup_audio_players()
	set_multiplayer_authority(1)
	if movement_component:
		movement_component.setup_singleplayer()
	if not auto_initialize_on_ready:
		return
	
	entity_type = "alien"
	
	if initialization_in_progress:
		return
	
	await _initialize_entity()

func _setup_audio_players():
	if not audio_player:
		audio_player = AudioStreamPlayer2D.new()
		audio_player.name = "AudioStreamPlayer2D"
		add_child(audio_player)
		audio_player.volume_db = linear_to_db(audio_volume)
		audio_player.max_distance = audio_range
	
	if not death_audio_player:
		death_audio_player = AudioStreamPlayer2D.new()
		death_audio_player.name = "DeathAudioPlayer"
		add_child(death_audio_player)
		death_audio_player.volume_db = linear_to_db(audio_volume)
		death_audio_player.max_distance = audio_range
	
	if not detection_audio_player:
		detection_audio_player = AudioStreamPlayer2D.new()
		detection_audio_player.name = "DetectionAudioPlayer"
		add_child(detection_audio_player)
		detection_audio_player.volume_db = linear_to_db(audio_volume)
		detection_audio_player.max_distance = audio_range
	
	if not attack_audio_player:
		attack_audio_player = AudioStreamPlayer2D.new()
		attack_audio_player.name = "AttackAudioPlayer"
		add_child(attack_audio_player)
		attack_audio_player.volume_db = linear_to_db(audio_volume)
		attack_audio_player.max_distance = audio_range

func _initialize_entity():
	initialization_in_progress = true
	
	_setup_entity_flags()
	_find_game_systems()
	
	await _create_components()
	await _initialize_components()
	
	call_deferred("_setup_ai_or_player_control")
	call_deferred("_connect_to_external_systems")
	call_deferred("_play_spawn_sound")
	
	is_fully_initialized = true
	initialization_in_progress = false
	
	emit_signal("initialization_complete")

func _play_sound_from_array(sound_array: Array[String], player: AudioStreamPlayer2D = null):
	if not enable_audio or sound_array.is_empty():
		return
	
	var audio_source = player if player else audio_player
	if not audio_source or audio_source.playing:
		return
	
	var sound_path = sound_array[randi() % sound_array.size()]
	var audio_stream = load(sound_path)
	
	if audio_stream:
		audio_source.stream = audio_stream
		audio_source.play()

func _play_spawn_sound():
	if not has_played_spawn_sound:
		_play_sound_from_array(spawn_sounds)
		has_played_spawn_sound = true

func _play_detection_sound():
	_play_sound_from_array(detection_sounds, detection_audio_player)

func _play_attack_sound():
	_play_sound_from_array(attack_sounds, attack_audio_player)

func _play_death_sound():
	_play_sound_from_array(death_sounds, death_audio_player)

func _play_gib_sound():
	_play_sound_from_array(gib_sounds, death_audio_player)

func _setup_entity_flags():
	if has_meta("alien_type"):
		alien_type = get_meta("alien_type")
	if has_meta("alien_faction"):
		alien_faction = get_meta("alien_faction")
	if has_meta("player_controlled"):
		player_controlled = get_meta("player_controlled")
	if has_meta("ai_enabled"):
		ai_enabled = get_meta("ai_enabled")

func _create_components():
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
	_create_do_after_component()
	_create_alien_specific_components()
	_create_ai_component()
	_create_player_control_components()
	
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

func _create_do_after_component():
	if not do_after_component:
		do_after_component = DoAfterComponent.new()
		do_after_component.name = "DoAfterComponent"
		add_child(do_after_component)

func _create_alien_specific_components():
	if not alien_sprite_system:
		alien_sprite_system = AlienSpriteSystem.new()
		alien_sprite_system.name = "AlienSpriteSystem"
		add_child(alien_sprite_system)

func _create_ai_component():
	if not alien_ai_component:
		alien_ai_component = AlienAIComponent.new()
		alien_ai_component.name = "AlienAIComponent"
		alien_ai_component.ai_enabled = ai_enabled and not player_controlled
		alien_ai_component.detection_range = ai_detection_range
		alien_ai_component.attack_range = ai_attack_range
		add_child(alien_ai_component)

func _create_player_control_components():
	if player_controlled:
		if not input_controller:
			input_controller = InputController.new()
			input_controller.name = "InputController"
			add_child(input_controller)
		
		if not click_component:
			click_component = ClickComponent.new()
			click_component.name = "ClickComponent"
			add_child(click_component)

func _initialize_components():
	var init_data = _build_initialization_data()
	
	_initialize_component(do_after_component, init_data)
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
	
	_initialize_alien_components(init_data)
	_initialize_ai_component(init_data)
	_initialize_player_components(init_data)
	
	_connect_component_signals()
	emit_signal("systems_initialized")

func _build_initialization_data() -> Dictionary:
	return {
		"controller": self,
		"world": world,
		"tile_occupancy_system": tile_occupancy_system,
		"sensory_system": sensory_system,
		"audio_system": audio_system,
		"health_system": health_system,
		"do_after_component": do_after_component,
		"entity_id": entity_id,
		"entity_name": _get_entity_name(entity_name),
		"is_local_player": is_local_player,
		"is_player_controlled": player_controlled,
		"alien_type": alien_type,
		"alien_faction": alien_faction,
		"peer_id": 1
	}

func _initialize_component(component: Node, init_data: Dictionary):
	if component and component.has_method("initialize"):
		component.initialize(init_data)
		emit_signal("component_ready", component.name)

func _initialize_alien_components(init_data: Dictionary):
	if alien_sprite_system:
		var sprite_init_data = init_data.duplicate()
		sprite_init_data.merge({
			"alien_type": alien_type,
			"movement_component": movement_component
		})
		alien_sprite_system.initialize(sprite_init_data)
		emit_signal("component_ready", "AlienSpriteSystem")

func _initialize_ai_component(init_data: Dictionary):
	if alien_ai_component:
		var ai_init_data = init_data.duplicate()
		ai_init_data.merge({
			"movement_component": movement_component,
			"interaction_component": interaction_component
		})
		alien_ai_component.initialize(ai_init_data)
		emit_signal("component_ready", "AlienAIComponent")
		
		if alien_ai_component.has_signal("target_acquired") and not alien_ai_component.target_acquired.is_connected(_on_target_acquired):
			alien_ai_component.target_acquired.connect(_on_target_acquired)
		
		if alien_ai_component.has_signal("target_lost") and not alien_ai_component.target_lost.is_connected(_on_target_lost):
			alien_ai_component.target_lost.connect(_on_target_lost)
		
		if alien_ai_component.has_signal("attack_attempted") and not alien_ai_component.attack_attempted.is_connected(_on_attack_attempted):
			alien_ai_component.attack_attempted.connect(_on_attack_attempted)

func _initialize_player_components(init_data: Dictionary):
	if player_controlled:
		if input_controller:
			if input_controller.has_method("connect_to_entity"):
				input_controller.connect_to_entity(self)
			elif input_controller.has_method("initialize"):
				input_controller.initialize(init_data)
			emit_signal("component_ready", "InputController")
		
		if click_component:
			click_component.initialize(init_data)
			emit_signal("component_ready", "ClickComponent")

func _setup_ai_or_player_control():
	if player_controlled:
		_setup_player_control()
	else:
		_setup_ai_control()

func _setup_player_control():
	is_local_player = true
	
	add_to_group("player_controller")
	add_to_group("players")
	add_to_group("aliens")
	add_to_group("entities")
	add_to_group("clickable_entities") 
	add_to_group("dense_entities")
	
	_setup_entity_properties()
	
	if alien_ai_component:
		alien_ai_component.disable_ai()
	
	_update_components_for_player()

func _setup_ai_control():
	is_local_player = false
	
	add_to_group("aliens")
	add_to_group("entities")
	add_to_group("ai_entities") 
	add_to_group("clickable_entities")
	add_to_group("dense_entities")
	
	_setup_entity_properties()
	
	if alien_ai_component and ai_enabled:
		alien_ai_component.enable_ai()
	
	_update_components_for_ai()

func _setup_entity_properties():
	entity_dense = true
	can_block_movement = true
	
	set_meta("entity_type", "alien") 
	set_meta("alien_type", alien_type)
	set_meta("can_take_damage", true)
	set_meta("is_alien", true)
	set_meta("is_player", player_controlled)

func _update_components_for_player():
	if movement_component:
		movement_component.is_local_player = is_local_player
	
	if intent_component:
		intent_component.set_intent(3)

func _update_components_for_ai():
	if movement_component:
		movement_component.is_local_player = false
	
	if intent_component:
		intent_component.set_intent(3)

func enable_ai():
	if alien_ai_component and not is_dead:
		ai_enabled = true
		alien_ai_component.enable_ai()
		_setup_ai_control()

func disable_ai():
	if alien_ai_component:
		ai_enabled = false
		alien_ai_component.disable_ai()

func toggle_ai():
	if ai_enabled:
		disable_ai()
	else:
		enable_ai()

func set_player_controlled(controlled: bool):
	if is_dead:
		return
	
	player_controlled = controlled
	
	if controlled:
		_setup_player_control()
	else:
		_setup_ai_control()

func is_ai_controlled() -> bool:
	return not player_controlled and ai_enabled and not is_dead

func get_ai_state() -> int:
	if alien_ai_component:
		return alien_ai_component.get_current_state()
	return 0

func get_ai_target() -> Node:
	if alien_ai_component:
		return alien_ai_component.get_current_target()
	return null

func force_ai_target(target: Node):
	if alien_ai_component and not is_dead:
		alien_ai_component.force_target(target)

func has_target_memory() -> bool:
	if alien_ai_component and alien_ai_component.has_method("has_target_memory"):
		return alien_ai_component.has_target_memory()
	return false

func get_memory_position() -> Vector2i:
	if alien_ai_component and alien_ai_component.has_method("get_memory_position"):
		return alien_ai_component.get_memory_position()
	return Vector2i.ZERO

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
			var success = tile_occupancy_system.register_entity_at_tile(self, pos, current_z_level)
			if not success:
				await get_tree().process_frame
				tile_occupancy_system.register_entity_at_tile(self, pos, current_z_level)
		elif tile_occupancy_system.has_method("register_entity"):
			var success = tile_occupancy_system.register_entity(self)
			if not success:
				await get_tree().process_frame
				tile_occupancy_system.register_entity(self)

func _register_with_spatial_manager():
	var spatial_manager = world.get_node_or_null("SpatialManager") if world else null
	if spatial_manager and spatial_manager.has_method("register_entity"):
		spatial_manager.register_entity(self)

func _register_with_interaction_system():
	var interaction_system = world.get_node_or_null("InteractionSystem") if world else null
	if interaction_system and interaction_system.has_method("register_entity"):
		interaction_system.register_entity(self, is_local_player)

func _find_game_systems():
	world = get_tree().get_first_node_in_group("world")
	
	if world:
		_find_world_systems()
	
	_find_entity_systems()

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
	health_system = get_node_or_null("HealthSystem")

func take_damage(damage_amount: float, damage_type: int, armor_type: String = "", effects: bool = true, armour_penetration: float = 0.0, attacker = null):
	if is_dead:
		return false
	
	if health_system and health_system.has_method("apply_damage"):
		var hs_damage_type = damage_type
		if damage_type == 1:
			hs_damage_type = health_system.DamageType.BRUTE
		elif damage_type == 2:
			hs_damage_type = health_system.DamageType.BURN
		
		return health_system.apply_damage(damage_amount, hs_damage_type, armour_penetration, "", attacker)
	
	return super.take_damage(damage_amount, damage_type, armor_type, effects, armour_penetration, attacker)

func _connect_component_signals():
	_connect_movement_signals()
	_connect_intent_signals()
	_connect_grab_signals()
	_connect_status_signals()
	_connect_posture_signals()
	_connect_weapon_signals()
	_connect_do_after_signals()
	_connect_health_signals()

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

func _connect_health_signals():
	if health_system:
		if not health_system.died.is_connected(_on_alien_died):
			health_system.died.connect(_on_alien_died)
		if not health_system.revived.is_connected(_on_alien_revived):
			health_system.revived.connect(_on_alien_revived)

func start_do_after_action(action_name: String, config_override: Dictionary = {}, callback: Callable = Callable(), target: Node = null) -> bool:
	if do_after_component and not is_dead:
		return do_after_component.start_action(action_name, config_override, callback, target)
	return false

func start_instant_action(action_name: String, callback: Callable = Callable(), target: Node = null) -> bool:
	if do_after_component and not is_dead:
		return do_after_component.start_instant_action(action_name, callback, target)
	return false

func cancel_current_action(reason: String = "manual") -> bool:
	if do_after_component:
		return do_after_component.cancel_action(reason)
	return false

func is_performing_action() -> bool:
	if do_after_component and not is_dead:
		return do_after_component.is_performing_action()
	return false

func get_current_tile_position() -> Vector2i:
	return movement_component.current_tile_position if movement_component else Vector2i.ZERO

func get_current_direction() -> int:
	return movement_component.current_direction if movement_component else 0

func move_externally(target_position: Vector2i, animated: bool = true, force: bool = false) -> bool:
	if is_dead:
		return false
	return movement_component.move_externally(target_position, animated, force) if movement_component else false

func attack_target(target: Node):
	if interaction_component and not is_dead:
		_play_attack_sound()
		if alien_sprite_system:
			alien_sprite_system.perform_thrust_attack()
		interaction_component._handle_harm_interaction(target, null)

func get_alien_type() -> String:
	return alien_type

func get_alien_faction() -> String:
	return alien_faction

func is_player_controlled() -> bool:
	return player_controlled

func _on_target_acquired(target: Node):
	if is_dead:
		return
	
	_play_detection_sound()
	emit_signal("target_acquired", target)
	
	if alien_sprite_system:
		alien_sprite_system.set_animation_state("moving")

func _on_target_lost():
	if is_dead:
		return
	
	emit_signal("target_lost")
	
	if alien_sprite_system:
		alien_sprite_system.set_animation_state("idle")

func _on_attack_attempted(target: Node):
	if is_dead:
		return
	
	_play_attack_sound()

func _on_tile_changed(old_tile: Vector2i, new_tile: Vector2i):
	if is_dead:
		return
	
	if tile_occupancy_system and tile_occupancy_system.has_method("move_entity"):
		tile_occupancy_system.move_entity(self, old_tile, new_tile, current_z_level)
	
	if movement_component:
		movement_component.check_tile_environment()

func _on_direction_changed(old_dir: int, new_dir: int):
	if is_dead:
		return
	
	if alien_sprite_system:
		alien_sprite_system.set_direction(new_dir)

func _on_both_hands_occupied_changed(is_occupied: bool):
	pass

func _on_do_after_started(action_name: String, duration: float):
	pass

func _on_do_after_completed(action_name: String, success: bool):
	pass

func _on_do_after_cancelled(action_name: String, reason: String):
	pass

func _on_alien_died(cause_of_death: String, death_time: float):
	if is_dead:
		return
	
	is_dead = true
	
	_disable_all_components()
	
	var should_gib = randf() > 0.05
	
	if should_gib:
		_play_gib_sound()
	else:
		_play_death_sound()
	
	if alien_sprite_system:
		alien_sprite_system.handle_death(should_gib)
	
	emit_signal("alien_died", cause_of_death)
	
	if should_gib:
		get_tree().create_timer(1.0).timeout.connect(_cleanup_alien_corpse)
	else:
		get_tree().create_timer(10.0).timeout.connect(_cleanup_alien_corpse)

func _disable_all_components():
	if alien_ai_component:
		alien_ai_component.disable_ai()
	
	if do_after_component:
		do_after_component.cancel_action("death")

func _cleanup_alien_corpse():
	if tile_occupancy_system and movement_component:
		var pos: Vector2i = movement_component.get_current_tile_position()
		var positions: Array[Vector2i] = [pos]
		tile_occupancy_system.remove_multi_tile_entity(self, positions, current_z_level)
	
	queue_free()

func _on_alien_revived(revival_method: String):
	if not is_dead:
		return
	
	is_dead = false
	
	if alien_sprite_system:
		alien_sprite_system.set_animation_state("idle")
	
	if movement_component:
		movement_component.set_enabled(true)
	
	if alien_ai_component and ai_enabled and not player_controlled:
		alien_ai_component.enable_ai()
	
	emit_signal("alien_revived")

func _get_entity_name(entity) -> String:
	if "entity_name" in entity and entity.entity_name != "":
		return entity.entity_name
	elif "name" in entity:
		return entity.name
	else:
		return "alien"

func world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x / 32), int(world_pos.y / 32))

func get_debug_info() -> Dictionary:
	var info = {
		"alien_type": alien_type,
		"faction": alien_faction,
		"player_controlled": player_controlled,
		"ai_enabled": ai_enabled,
		"is_local_player": is_local_player,
		"current_z_level": current_z_level,
		"position": get_current_tile_position(),
		"is_dead": is_dead,
		"enable_audio": enable_audio,
		"has_played_spawn_sound": has_played_spawn_sound
	}
	
	if alien_ai_component:
		info.merge(alien_ai_component.get_debug_info())
	
	return info

func _exit_tree():
	if audio_player:
		audio_player.stop()
	if death_audio_player:
		death_audio_player.stop()
	if detection_audio_player:
		detection_audio_player.stop()
	if attack_audio_player:
		attack_audio_player.stop()
	
	if do_after_component and do_after_component.has_method("cancel_action"):
		do_after_component.cancel_action("entity_cleanup")
	
	if grab_pull_component and grab_pull_component.has_method("cleanup"):
		grab_pull_component.cleanup()
	
	if tile_occupancy_system and movement_component and tile_occupancy_system.has_method("remove_entity"):
		var pos = movement_component.get_current_tile_position()
		tile_occupancy_system.remove_entity(self, pos, current_z_level)
