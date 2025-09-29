extends Node2D
class_name HumanSpriteSystem

# Configuration
@export_group("Sprite Configuration")
@export var sprite_frames_horizontal: int = 4
@export var sprite_frames_vertical: int = 1
@export var sprite_frame_width: int = 32
@export var sprite_frame_height: int = 32
@export var auto_initialize_on_ready: bool = true

@export_group("Animation Settings")
@export var thrust_animation_duration: float = 0.2
@export var thrust_return_duration: float = 0.1
@export var thrust_distance: float = 6.0
@export var lying_offset: Vector2 = Vector2(0, 2)

@export_group("Multiplayer Settings")
@export var sync_direction_changes: bool = true
@export var _sync_lying_state: bool = true
@export var sync_customization: bool = true

@export_group("Debug Settings")
@export var debug_sprite_updates: bool = false
@export var log_texture_loading: bool = false

# Sprite system signals
signal limb_attached(limb_name)
signal limb_detached(limb_name)
signal sprite_direction_changed(direction)
signal item_equipped(item, slot)
signal item_unequipped(item, slot)
signal customization_applied(success)

# Enumerations
enum LimbType {BODY, HEAD, LEFT_ARM, RIGHT_ARM, LEFT_HAND, RIGHT_HAND, GROIN, LEFT_LEG, RIGHT_LEG, LEFT_FOOT, RIGHT_FOOT}
enum Direction {SOUTH, NORTH, EAST, WEST}
enum EquipSlot {
	HEAD, EYES, MASK, EARS, NECK, OUTER, UNIFORM, SUIT, GLOVES, BELT, SHOES, BACK, ID, LEFT_HAND, RIGHT_HAND
}

# Sprite references - limbs
var body_sprite: Sprite2D
var head_sprite: Sprite2D
var left_arm_sprite: Sprite2D
var right_arm_sprite: Sprite2D
var left_hand_sprite: Sprite2D
var right_hand_sprite: Sprite2D
var left_leg_sprite: Sprite2D
var right_leg_sprite: Sprite2D
var left_foot_sprite: Sprite2D
var right_foot_sprite: Sprite2D

# Container references
var equipment_container: Node2D
var held_items_container: Node2D
var left_hand_item_position: Node2D
var right_hand_item_position: Node2D
var undergarment_container: Node2D
var inhand_sprites_container: Node2D

# In-hand sprite references
var left_hand_inhand_sprite: Sprite2D
var right_hand_inhand_sprite: Sprite2D

# Customization sprites
var underwear_sprite: Sprite2D = null
var undershirt_sprite: Sprite2D = null
var hair_sprite: Sprite2D = null
var facial_hair_sprite: Sprite2D = null

# System references
var Entity = null
var inventory_system: Node = null
var asset_manager = null

# State variablesz
var current_direction: int = Direction.SOUTH
var is_lying: bool = false
var lying_direction: int = Direction.SOUTH

# Character properties
var character_sex: int = 0
var race_index: int = 0
var is_loading_textures: bool = false

# Data structures
var limbs_attached = {
	LimbType.BODY: true, LimbType.HEAD: true, LimbType.LEFT_ARM: true, LimbType.RIGHT_ARM: true,
	LimbType.LEFT_HAND: true, LimbType.RIGHT_HAND: true, LimbType.LEFT_LEG: true, 
	LimbType.RIGHT_LEG: true, LimbType.LEFT_FOOT: true, LimbType.RIGHT_FOOT: true
}

var limb_sprites = {}
var equipped_items = {}
var equipment_sprites = {}

# Z-index layers for different directions
var limb_z_index_layers = {
	Direction.SOUTH: {
		LimbType.BODY: 0, LimbType.HEAD: 0, LimbType.LEFT_ARM: 1, LimbType.RIGHT_ARM: 1,
		LimbType.LEFT_HAND: 1, LimbType.RIGHT_HAND: 1, LimbType.LEFT_LEG: 1, LimbType.RIGHT_LEG: 1,
		LimbType.LEFT_FOOT: 1, LimbType.RIGHT_FOOT: 1
	},
	Direction.NORTH: {
		LimbType.BODY: 0, LimbType.HEAD: 0, LimbType.LEFT_ARM: 1, LimbType.RIGHT_ARM: 1,
		LimbType.LEFT_HAND: 1, LimbType.RIGHT_HAND: 1, LimbType.LEFT_LEG: 1, LimbType.RIGHT_LEG: 1,
		LimbType.LEFT_FOOT: 1, LimbType.RIGHT_FOOT: 1
	},
	Direction.EAST: {
		LimbType.BODY: 0, LimbType.HEAD: 0, LimbType.LEFT_ARM: 1, LimbType.RIGHT_ARM: 1,
		LimbType.LEFT_HAND: 0, LimbType.RIGHT_HAND: 6, LimbType.LEFT_LEG: 1, LimbType.RIGHT_LEG: 1,
		LimbType.LEFT_FOOT: 0, LimbType.RIGHT_FOOT: 2
	},
	Direction.WEST: {
		LimbType.BODY: 0, LimbType.HEAD: 0, LimbType.LEFT_ARM: 1, LimbType.RIGHT_ARM: 1,
		LimbType.LEFT_HAND: 6, LimbType.RIGHT_HAND: 0, LimbType.LEFT_LEG: 1, LimbType.RIGHT_LEG: 1,
		LimbType.LEFT_FOOT: 2, LimbType.RIGHT_FOOT: 0
	}
}

var equipment_z_index_layers = {
	Direction.SOUTH: {
		EquipSlot.UNIFORM: 4, EquipSlot.SUIT: 5, EquipSlot.OUTER: 6, EquipSlot.BELT: 6, 
		EquipSlot.BACK: 7, EquipSlot.SHOES: 3, EquipSlot.GLOVES: 3, EquipSlot.MASK: 2, 
		EquipSlot.EYES: 1, EquipSlot.HEAD: 8, EquipSlot.EARS: 2, EquipSlot.NECK: 2, 
		EquipSlot.ID: 2, EquipSlot.LEFT_HAND: 10, EquipSlot.RIGHT_HAND: 10
	},
	Direction.NORTH: {
		EquipSlot.UNIFORM: 4, EquipSlot.SUIT: 5, EquipSlot.OUTER: 6, EquipSlot.BELT: 6, 
		EquipSlot.BACK: 7, EquipSlot.SHOES: 3, EquipSlot.GLOVES: 3, EquipSlot.MASK: 2, 
		EquipSlot.EYES: 1, EquipSlot.HEAD: 8, EquipSlot.EARS: 2, EquipSlot.NECK: 2, 
		EquipSlot.ID: 2, EquipSlot.LEFT_HAND: 10, EquipSlot.RIGHT_HAND: 10
	},
	Direction.EAST: {
		EquipSlot.UNIFORM: 4, EquipSlot.SUIT: 5, EquipSlot.OUTER: 6, EquipSlot.BELT: 6,  
		EquipSlot.BACK: 7, EquipSlot.SHOES: 3, EquipSlot.GLOVES: 7, EquipSlot.MASK: 2, 
		EquipSlot.EYES: 1, EquipSlot.HEAD: 8, EquipSlot.EARS: 2, EquipSlot.NECK: 2, 
		EquipSlot.ID: 2, EquipSlot.LEFT_HAND: 10, EquipSlot.RIGHT_HAND: 10
	},
	Direction.WEST: {
		EquipSlot.UNIFORM: 4, EquipSlot.SUIT: 5, EquipSlot.OUTER: 6, EquipSlot.BELT: 6, 
		EquipSlot.BACK: 7, EquipSlot.SHOES: 3, EquipSlot.GLOVES: 7, EquipSlot.MASK: 2, 
		EquipSlot.EYES: 1, EquipSlot.HEAD: 8, EquipSlot.EARS: 2, EquipSlot.NECK: 2, 
		EquipSlot.ID: 2, EquipSlot.LEFT_HAND: 10, EquipSlot.RIGHT_HAND: 10
	}
}

# Animation properties
var thrust_tween = null
var is_thrusting = false

func _ready():
	if auto_initialize_on_ready:
		_initialize_sprite_system()

# Initialization functions
func _initialize_sprite_system():
	asset_manager = get_node_or_null("/root/CharacterAssetManager")
	
	_create_equipment_containers()
	_create_undergarment_container()
	_create_inhand_sprites_container()
	_setup_sprites()
	
	_populate_limb_sprites_dict()
	set_direction(Direction.SOUTH)
	
	if get_parent() and Entity == null:
		initialize(get_parent())
	
	_connect_to_inventory_system()
	
	if debug_sprite_updates:
		print("HumanSpriteSystem: Initialization complete")

func _populate_limb_sprites_dict():
	limb_sprites = {
		LimbType.BODY: body_sprite, LimbType.HEAD: head_sprite, 
		LimbType.LEFT_ARM: left_arm_sprite, LimbType.RIGHT_ARM: right_arm_sprite, 
		LimbType.LEFT_HAND: left_hand_sprite, LimbType.RIGHT_HAND: right_hand_sprite, 
		LimbType.LEFT_LEG: left_leg_sprite, LimbType.RIGHT_LEG: right_leg_sprite,
		LimbType.LEFT_FOOT: left_foot_sprite, LimbType.RIGHT_FOOT: right_foot_sprite
	}

# Container setup functions
func _create_equipment_containers():
	equipment_container = Node2D.new()
	equipment_container.name = "EquipmentContainer"
	add_child(equipment_container)
	
	held_items_container = Node2D.new()
	held_items_container.name = "HeldItemsContainer"
	add_child(held_items_container)
	
	left_hand_item_position = Node2D.new()
	left_hand_item_position.name = "LeftHandPosition"
	held_items_container.add_child(left_hand_item_position)
	
	right_hand_item_position = Node2D.new()
	right_hand_item_position.name = "RightHandPosition"
	held_items_container.add_child(right_hand_item_position)
	
	_create_equipment_sprite_nodes()

func _create_equipment_sprite_nodes():
	equipment_sprites.clear()
	
	var equipment_types = {
		EquipSlot.UNIFORM: "UniformContainer", EquipSlot.SUIT: "SuitContainer",
		EquipSlot.OUTER: "OuterContainer", EquipSlot.HEAD: "HeadContainer",
		EquipSlot.EYES: "EyesContainer", EquipSlot.MASK: "MaskContainer",
		EquipSlot.EARS: "EarsContainer", EquipSlot.GLOVES: "GlovesContainer",
		EquipSlot.SHOES: "ShoesContainer", EquipSlot.BELT: "BeltContainer",
		EquipSlot.BACK: "BackContainer", EquipSlot.NECK: "NeckContainer",
		EquipSlot.ID: "IDContainer", EquipSlot.LEFT_HAND: "LeftHandContainer", 
		EquipSlot.RIGHT_HAND: "RightHandContainer"
	}
	
	for slot in equipment_types:
		var container_name = equipment_types[slot]
		var container = Node2D.new()
		container.name = container_name
		equipment_container.add_child(container)
		
		var sprite_name = container_name.replace("Container", "Sprite")
		var sprite = Sprite2D.new()
		sprite.name = sprite_name
		sprite.centered = true
		sprite.region_enabled = true
		sprite.visible = false
		container.add_child(sprite)
		
		equipment_sprites[slot] = sprite
		sprite.z_index = equipment_z_index_layers[Direction.SOUTH][slot]

func _create_undergarment_container():
	if undergarment_container and is_instance_valid(undergarment_container):
		if debug_sprite_updates:
			print("Undergarment container already exists, validating sprites")
		_validate_undergarment_sprites()
		return
	
	if debug_sprite_updates:
		print("Creating new undergarment container")
	
	undergarment_container = Node2D.new()
	undergarment_container.name = "UndergarmentContainer"
	add_child(undergarment_container)
	
	underwear_sprite = _create_undergarment_sprite("UnderwearSprite")
	undershirt_sprite = _create_undergarment_sprite("UndershirtSprite")

func _validate_undergarment_sprites():
	if not underwear_sprite or not is_instance_valid(underwear_sprite):
		underwear_sprite = undergarment_container.get_node_or_null("UnderwearSprite")
		if not underwear_sprite:
			underwear_sprite = _create_undergarment_sprite("UnderwearSprite")
	
	if not undershirt_sprite or not is_instance_valid(undershirt_sprite):
		undershirt_sprite = undergarment_container.get_node_or_null("UndershirtSprite")
		if not undershirt_sprite:
			undershirt_sprite = _create_undergarment_sprite("UndershirtSprite")

func _create_undergarment_sprite(sprite_name: String) -> Sprite2D:
	var sprite = Sprite2D.new()
	sprite.name = sprite_name
	sprite.centered = true
	sprite.region_enabled = true
	sprite.z_index = 1
	sprite.visible = false
	undergarment_container.add_child(sprite)
	return sprite

func _create_inhand_sprites_container():
	inhand_sprites_container = Node2D.new()
	inhand_sprites_container.name = "InhandSpritesContainer"
	add_child(inhand_sprites_container)
	
	left_hand_inhand_sprite = _create_inhand_sprite("LeftHandInhandSprite")
	right_hand_inhand_sprite = _create_inhand_sprite("RightHandInhandSprite")

func _create_inhand_sprite(sprite_name: String) -> Sprite2D:
	var sprite = Sprite2D.new()
	sprite.name = sprite_name
	sprite.centered = true
	sprite.region_enabled = true
	sprite.visible = false
	inhand_sprites_container.add_child(sprite)
	return sprite

# Sprite setup functions
func _setup_sprites():
	var sprites_container = Node2D.new()
	sprites_container.name = "Sprites"
	add_child(sprites_container)
	
	body_sprite = _create_limb_sprite(sprites_container, "BodySprite", LimbType.BODY)
	head_sprite = _create_limb_sprite(sprites_container, "HeadSprite", LimbType.HEAD)
	left_arm_sprite = _create_limb_sprite(sprites_container, "LeftArmSprite", LimbType.LEFT_ARM)
	right_arm_sprite = _create_limb_sprite(sprites_container, "RightArmSprite", LimbType.RIGHT_ARM)
	left_hand_sprite = _create_limb_sprite(sprites_container, "LeftHandSprite", LimbType.LEFT_HAND)
	right_hand_sprite = _create_limb_sprite(sprites_container, "RightHandSprite", LimbType.RIGHT_HAND)
	left_leg_sprite = _create_limb_sprite(sprites_container, "LeftLegSprite", LimbType.LEFT_LEG)
	right_leg_sprite = _create_limb_sprite(sprites_container, "RightLegSprite", LimbType.RIGHT_LEG)
	left_foot_sprite = _create_limb_sprite(sprites_container, "LeftFootSprite", LimbType.LEFT_FOOT)
	right_foot_sprite = _create_limb_sprite(sprites_container, "RightFootSprite", LimbType.RIGHT_FOOT)
	
	_load_limb_textures()
	_setup_sprite_properties()

func _create_limb_sprite(parent: Node, sprite_name: String, limb_type: int) -> Sprite2D:
	var sprite = Sprite2D.new()
	sprite.name = sprite_name
	sprite.centered = true
	sprite.region_enabled = true
	sprite.z_index = limb_z_index_layers[Direction.SOUTH][limb_type]
	parent.add_child(sprite)
	return sprite

func _setup_sprite_properties():
	var all_sprites = _get_all_limb_sprites()
	
	for sprite in all_sprites:
		if sprite:
			sprite.region_enabled = true
			sprite.region_rect = Rect2(0, 0, sprite_frame_width, sprite_frame_height)
			sprite.position = Vector2.ZERO
			sprite.centered = true

func _get_all_limb_sprites() -> Array:
	return [body_sprite, head_sprite, left_arm_sprite, right_arm_sprite,
		left_hand_sprite, right_hand_sprite, left_leg_sprite, right_leg_sprite,
		left_foot_sprite, right_foot_sprite]

# Inventory system integration
func _connect_to_inventory_system():
	if not get_parent():
		return
	
	inventory_system = get_parent().get_node_or_null("InventorySystem")
	if not inventory_system:
		if debug_sprite_updates:
			print("No InventorySystem found in parent entity")
		return
	
	if debug_sprite_updates:
		print("Connected to InventorySystem")
	
	_connect_inventory_signals()
	update_inhand_sprites_from_inventory()

func _connect_inventory_signals():
	if inventory_system.has_signal("item_equipped"):
		if not inventory_system.item_equipped.is_connected(_on_inventory_item_equipped):
			inventory_system.item_equipped.connect(_on_inventory_item_equipped)
	
	if inventory_system.has_signal("item_unequipped"):
		if not inventory_system.item_unequipped.is_connected(_on_inventory_item_unequipped):
			inventory_system.item_unequipped.connect(_on_inventory_item_unequipped)
	
	if inventory_system.has_signal("inventory_updated"):
		if not inventory_system.inventory_updated.is_connected(_on_inventory_updated):
			inventory_system.inventory_updated.connect(_on_inventory_updated)

# Inventory signal handlers
func _on_inventory_item_equipped(item, slot):
	if slot == 13 or slot == 14:  # Hand slots
		update_inhand_sprites_from_inventory()

func _on_inventory_item_unequipped(item, slot):
	if slot == 13 or slot == 14:  # Hand slots
		update_inhand_sprites_from_inventory()

func _on_inventory_updated():
	update_inhand_sprites_from_inventory()

# Main processing loop
func _process(_delta):
	if Entity:
		_update_sprite_frames()
		_update_sprite_z_ordering()
		
		if Entity.has_method("is_prone"):
			set_lying_state(Entity.is_prone())

# Entity initialization
func initialize(entity_reference):
	Entity = entity_reference
	
	_connect_entity_signals()
	_connect_movement_signals()
	
	if debug_sprite_updates:
		print("HumanSpriteSystem initialized for entity: ", Entity.name)

func _connect_entity_signals():
	if Entity and Entity.has_signal("body_part_damaged"):
		if not Entity.is_connected("body_part_damaged", Callable(self, "_on_body_part_damaged")):
			Entity.body_part_damaged.connect(_on_body_part_damaged)

func _connect_movement_signals():
	var grid_controller = get_parent()
	if grid_controller:
		var movement_comp = grid_controller.get_node_or_null("MovementComponent")
		if movement_comp:
			if not movement_comp.is_connected("direction_changed", Callable(self, "_on_direction_changed_from_movement")):
				movement_comp.direction_changed.connect(_on_direction_changed_from_movement)

func _on_direction_changed_from_movement(old_dir: int, new_dir: int):
	set_direction(new_dir)

# Direction and orientation system
func set_direction(direction: int):
	if current_direction == direction:
		return
	
	if debug_sprite_updates:
		print("Setting direction to ", direction, " (was ", current_direction, ")")
	
	current_direction = direction
	_update_all_sprite_elements()
	
	emit_signal("sprite_direction_changed", direction)

func _update_all_sprite_elements():
	_update_sprite_frames()
	_update_sprite_z_ordering()
	_update_clothing_frames()
	_update_customization_frames()
	_update_equipment_sprites()
	_update_undergarment_frames()
	_update_inhand_sprite_frames()
	
	if is_lying:
		_apply_lying_rotation()

func _update_sprite_frames():
	for limb_type in limb_sprites:
		var sprite = limb_sprites[limb_type]
		if sprite and sprite.texture and sprite.region_enabled:
			var frame_x = current_direction * sprite_frame_width
			sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)

func _update_sprite_z_ordering():
	# Update limb z-ordering
	for limb_type in limb_sprites:
		var sprite = limb_sprites[limb_type]
		if sprite and limb_z_index_layers[current_direction].has(limb_type):
			sprite.z_index = limb_z_index_layers[current_direction][limb_type]
	
	# Update equipment z-ordering
	for slot in equipment_sprites:
		var sprite = equipment_sprites[slot]
		if sprite and sprite.visible and equipment_z_index_layers[current_direction].has(slot):
			sprite.z_index = equipment_z_index_layers[current_direction][slot]
	
	_update_inhand_sprite_z_ordering()

func _update_inhand_sprite_z_ordering():
	if left_hand_inhand_sprite and left_hand_inhand_sprite.visible:
		left_hand_inhand_sprite.z_index = equipment_z_index_layers[current_direction][EquipSlot.LEFT_HAND]
	
	if right_hand_inhand_sprite and right_hand_inhand_sprite.visible:
		right_hand_inhand_sprite.z_index = equipment_z_index_layers[current_direction][EquipSlot.RIGHT_HAND]

# In-hand sprite management
func update_inhand_sprites_from_inventory():
	if not inventory_system:
		return
	
	var left_hand_item = inventory_system.get_item_in_slot(13)
	var right_hand_item = inventory_system.get_item_in_slot(14)
	
	_update_single_inhand_sprite(left_hand_item, left_hand_inhand_sprite, "left")
	_update_single_inhand_sprite(right_hand_item, right_hand_inhand_sprite, "right")

func _update_single_inhand_sprite(item, sprite: Sprite2D, hand_suffix: String):
	if not sprite:
		return
	
	if not item or not is_instance_valid(item):
		sprite.visible = false
		sprite.texture = null
		return
	
	var item_name = _get_item_name_for_inhand(item)
	if item_name == "":
		sprite.visible = false
		return
	
	var texture = _get_inhand_texture_from_asset_manager(item_name, hand_suffix)
	
	if texture:
		sprite.texture = texture
		sprite.region_enabled = true
		sprite.visible = true
		
		var frame_x = current_direction * sprite_frame_width
		sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
		
		if hand_suffix == "left":
			sprite.z_index = equipment_z_index_layers[current_direction][EquipSlot.LEFT_HAND]
		else:
			sprite.z_index = equipment_z_index_layers[current_direction][EquipSlot.RIGHT_HAND]
		
		if is_lying:
			_apply_lying_rotation()
		
		if debug_sprite_updates:
			print("Updated ", hand_suffix, " hand in-hand sprite for ", item_name)
	else:
		sprite.visible = false
		sprite.texture = null
		if log_texture_loading:
			print("No in-hand texture found for ", item_name, "_", hand_suffix)

func _get_item_name_for_inhand(item) -> String:
	if "item_name" in item:
		return item.item_name
	elif "name" in item:
		return item.name
	else:
		if debug_sprite_updates:
			print("Item has no item_name or name property")
		return ""

func _get_inhand_texture_from_asset_manager(item_name: String, hand_suffix: String) -> Texture2D:
	if not asset_manager:
		if log_texture_loading:
			print("No asset manager available")
		return null
	
	if log_texture_loading:
		print("Loading in-hand texture for: '", item_name, "', hand: '", hand_suffix, "'")
	
	var texture = asset_manager.get_inhand_texture(item_name, hand_suffix)
	
	if texture and log_texture_loading:
		print("Successfully loaded in-hand texture for ", item_name, "_", hand_suffix)
	elif log_texture_loading:
		print("Failed to load in-hand texture for ", item_name, "_", hand_suffix)
	
	return texture

func _try_texture_variations(item_name: String, hand_suffix: String) -> Texture2D:
	var naming_variations = [
		item_name + "_" + hand_suffix,
		item_name.to_lower() + "_" + hand_suffix,
		item_name.to_lower().replace(" ", "_") + "_" + hand_suffix
	]
	
	for variation in naming_variations:
		var possible_paths = [
			"res://Assets/Icons/Items/In_hand/" + variation + ".png",
		]
		
		for path in possible_paths:
			if ResourceLoader.exists(path):
				var texture = load(path)
				if texture and texture is Texture2D:
					if log_texture_loading:
						print("Successfully loaded texture: ", path)
					return texture
			
			if asset_manager.has_method("get_resource"):
				var texture = asset_manager.get_resource(path)
				if texture:
					if log_texture_loading:
						print("Found texture via asset manager: ", path)
					return texture
	
	if log_texture_loading:
		print("No in-hand texture found for: ", item_name)
	return null

# Character customization system
func set_sex(sex: int):
	if character_sex == sex:
		return
	
	character_sex = sex
	_load_limb_textures()
	_update_sprite_frames()
	
	# Hide facial hair for female characters
	if sex == 1 and facial_hair_sprite:
		facial_hair_sprite.visible = false
	
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server() and sync_customization:
		sync_sex.rpc(sex)

func set_race(race: int):
	if race_index == race:
		return
	
	race_index = race
	_load_limb_textures()
	_update_sprite_frames()
	
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server() and sync_customization:
		sync_race.rpc(race)

func _load_limb_textures():
	if not asset_manager:
		return
	
	var race_sprites = asset_manager.get_race_sprites(race_index, character_sex)
	
	var sprite_mapping = {
		"body": body_sprite, "head": head_sprite,
		"left_arm": left_arm_sprite, "right_arm": right_arm_sprite,
		"left_hand": left_hand_sprite, "right_hand": right_hand_sprite,
		"left_leg": left_leg_sprite, "right_leg": right_leg_sprite,
		"left_foot": left_foot_sprite, "right_foot": right_foot_sprite
	}
	
	for sprite_key in sprite_mapping:
		var sprite = sprite_mapping[sprite_key]
		if race_sprites.has(sprite_key) and sprite:
			var texture_path = race_sprites[sprite_key]["texture"]
			if texture_path and asset_manager:
				var texture = asset_manager.get_resource(texture_path)
				if texture:
					sprite.texture = texture

func set_hair(hair_texture: Texture2D, hair_color: Color):
	if not hair_texture:
		if hair_sprite:
			hair_sprite.queue_free()
			hair_sprite = null
		return
	
	if not hair_sprite:
		hair_sprite = _create_customization_sprite("HairSprite", 7)
	
	hair_sprite.texture = hair_texture
	hair_sprite.modulate = hair_color
	hair_sprite.visible = true
	
	var frame_x = current_direction * sprite_frame_width
	hair_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
	
	if is_lying:
		_apply_lying_rotation()

func set_facial_hair(facial_hair_texture: Texture2D, facial_hair_color: Color):
	if not facial_hair_texture or character_sex == 1:
		if facial_hair_sprite:
			facial_hair_sprite.queue_free()
			facial_hair_sprite = null
		return
	
	if not facial_hair_sprite:
		facial_hair_sprite = _create_customization_sprite("FacialHairSprite", 7)
	
	facial_hair_sprite.texture = facial_hair_texture
	facial_hair_sprite.modulate = facial_hair_color
	facial_hair_sprite.visible = true
	
	var frame_x = current_direction * sprite_frame_width
	facial_hair_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
	
	if is_lying:
		_apply_lying_rotation()

func _create_customization_sprite(sprite_name: String, z_index: float) -> Sprite2D:
	var sprite = Sprite2D.new()
	sprite.name = sprite_name
	sprite.centered = true
	sprite.z_index = z_index
	sprite.region_enabled = true
	add_child(sprite)
	return sprite

func set_underwear(underwear_texture: Texture2D):
	if not undergarment_container or not underwear_sprite:
		_create_undergarment_container()
	
	if not underwear_texture:
		underwear_sprite.visible = false
		underwear_sprite.texture = null
		underwear_sprite.region_enabled = false
		if debug_sprite_updates:
			print("Clearing underwear texture")
		return
	
	_apply_undergarment_texture(underwear_sprite, underwear_texture, "underwear")

func set_undershirt(undershirt_texture: Texture2D):
	if not undergarment_container or not undershirt_sprite:
		_create_undergarment_container()
	
	if not undershirt_texture:
		undershirt_sprite.visible = false
		undershirt_sprite.texture = null
		undershirt_sprite.region_enabled = false
		if debug_sprite_updates:
			print("Clearing undershirt texture")
		return
	
	_apply_undergarment_texture(undershirt_sprite, undershirt_texture, "undershirt")

func _apply_undergarment_texture(sprite: Sprite2D, texture: Texture2D, type_name: String):
	sprite.texture = texture
	sprite.region_enabled = true
	sprite.visible = true
	sprite.z_index = 2
	
	if is_inside_tree() and sprite.get_parent():
		var frame_x = current_direction * sprite_frame_width
		sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
		if debug_sprite_updates:
			print("Set ", type_name, " texture, direction: ", current_direction)
		
		if is_lying:
			_apply_lying_rotation()
	else:
		sprite.region_rect = Rect2(0, 0, sprite_frame_width, sprite_frame_height)
		if debug_sprite_updates:
			print("Set ", type_name, " texture with default frame")

# Frame update functions
func _update_clothing_frames():
	for slot in equipment_sprites:
		var sprite = equipment_sprites[slot]
		if sprite and sprite.visible and sprite.texture and sprite.region_enabled:
			if slot != EquipSlot.LEFT_HAND and slot != EquipSlot.RIGHT_HAND:
				var frame_x = current_direction * sprite_frame_width
				sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)

func _update_customization_frames():
	var frame_x = current_direction * sprite_frame_width
	
	if hair_sprite and hair_sprite.texture:
		hair_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
	
	if facial_hair_sprite and facial_hair_sprite.texture:
		facial_hair_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)

func _update_equipment_sprites():
	for slot in equipment_sprites:
		var sprite = equipment_sprites[slot]
		if sprite and sprite.visible and sprite.texture and sprite.region_enabled:
			if slot != EquipSlot.LEFT_HAND and slot != EquipSlot.RIGHT_HAND:
				var frame_x = current_direction * sprite_frame_width
				sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
				
				if equipment_z_index_layers[current_direction].has(slot):
					sprite.z_index = equipment_z_index_layers[current_direction][slot]

func _update_undergarment_frames():
	if not underwear_sprite and not undershirt_sprite:
		return
	
	var frame_x = current_direction * sprite_frame_width
	
	if underwear_sprite and underwear_sprite.texture and underwear_sprite.region_enabled:
		underwear_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
		if debug_sprite_updates:
			print("Updated underwear frame to direction ", current_direction)
	
	if undershirt_sprite and undershirt_sprite.texture and undershirt_sprite.region_enabled:
		undershirt_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
		if debug_sprite_updates:
			print("Updated undershirt frame to direction ", current_direction)

func _update_inhand_sprite_frames():
	var frame_x = current_direction * sprite_frame_width
	
	if left_hand_inhand_sprite and left_hand_inhand_sprite.texture and left_hand_inhand_sprite.region_enabled:
		left_hand_inhand_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
	
	if right_hand_inhand_sprite and right_hand_inhand_sprite.texture and right_hand_inhand_sprite.region_enabled:
		right_hand_inhand_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)

# Lying and posture system
func set_lying_state(lying_state: bool, direction: int = -1):
	if is_lying == lying_state:
		return
	
	is_lying = lying_state
	
	if direction < 0:
		direction = current_direction
	
	if lying_state:
		lying_direction = direction
	
	_apply_lying_rotation()
	
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server() and sync_lying_state:
		sync_lying_state.rpc(lying_state, direction)

func _apply_lying_rotation():
	var target_rotation = 0.0
	var position_offset = Vector2.ZERO
	var h = false
	var v = false
	
	if is_lying:
		match current_direction:
			Direction.EAST:
				target_rotation = PI/2.0
				position_offset = Vector2(lying_offset.x, lying_offset.y)
				h = false
				v = false
			Direction.WEST:
				target_rotation = PI/2.0
				position_offset = Vector2(lying_offset.x, lying_offset.y)
				h = true
				v = true
			Direction.SOUTH:
				target_rotation = PI/2.0
				position_offset = Vector2(lying_offset.x, lying_offset.y)
				h = false
				v = true
			Direction.NORTH:
				target_rotation = PI/2.0
				position_offset = Vector2(-lying_offset.x, lying_offset.y)
				h = true
				v = false
	
	var all_sprites = _get_all_sprites_for_rotation()
	
	for sprite in all_sprites:
		if sprite and sprite.visible:
			sprite.rotation = target_rotation
			sprite.position = position_offset
			sprite.flip_h = h
			sprite.flip_v = v

func _get_all_sprites_for_rotation() -> Array:
	var all_sprites = []
	all_sprites.append_array(limb_sprites.values())
	all_sprites.append_array(equipment_sprites.values())
	
	if hair_sprite: all_sprites.append(hair_sprite)
	if facial_hair_sprite: all_sprites.append(facial_hair_sprite)
	if underwear_sprite: all_sprites.append(underwear_sprite)
	if undershirt_sprite: all_sprites.append(undershirt_sprite)
	if left_hand_inhand_sprite: all_sprites.append(left_hand_inhand_sprite)
	if right_hand_inhand_sprite: all_sprites.append(right_hand_inhand_sprite)
	
	return all_sprites

# Animation system
func show_interaction_thrust(direction: Vector2, intent_type: int = 0):
	if is_thrusting:
		return
	
	if thrust_tween and thrust_tween.is_valid():
		thrust_tween.kill()
	
	is_thrusting = true
	
	var thrust_offset = direction * thrust_distance
	var sprites_to_animate = []
	var original_positions = {}
	
	for sprite in _get_all_sprites_for_rotation():
		if sprite and sprite.visible:
			sprites_to_animate.append(sprite)
			original_positions[sprite] = sprite.position
	
	thrust_tween = create_tween()
	thrust_tween.set_ease(Tween.EASE_OUT)
	thrust_tween.set_trans(Tween.TRANS_BACK)
	
	# Forward thrust
	for sprite in sprites_to_animate:
		var target_pos = original_positions[sprite] + thrust_offset
		thrust_tween.parallel().tween_property(sprite, "position", target_pos, thrust_animation_duration)
	
	# Return to original position
	for sprite in sprites_to_animate:
		thrust_tween.parallel().tween_property(sprite, "position", original_positions[sprite], thrust_return_duration).set_delay(thrust_animation_duration)
	
	thrust_tween.tween_callback(func(): is_thrusting = false).set_delay(thrust_animation_duration + thrust_return_duration)

# Equipment system
func equip_item(item, slot: int) -> bool:
	var result = _equip_item_internal(item, slot)
	
	if result and multiplayer.has_multiplayer_peer():
		var entity_id = _get_entity_network_id()
		var item_id = _get_item_network_id(item)
		sync_equip_item.rpc(item_id, slot, entity_id)
	
	return result

func unequip_item(slot: int) -> bool:
	var result = _unequip_item_internal(slot)
	
	if result and multiplayer.has_multiplayer_peer():
		var entity_id = _get_entity_network_id()
		sync_unequip_item.rpc(slot, entity_id)
	
	return result

func _equip_item_internal(item, slot: int) -> bool:
	if equipped_items.has(slot) and equipped_items[slot] != null:
		_unequip_item_internal(slot)
	
	if debug_sprite_updates:
		print("Equipping item ", item.item_name if "item_name" in item else "Unknown", " to slot ", slot)
	
	equipped_items[slot] = item
	_create_equipment_visual(item, slot)
	emit_signal("item_equipped", item, slot)
	return true

func _unequip_item_internal(slot: int) -> bool:
	if not equipped_items.has(slot) or equipped_items[slot] == null:
		return false
	
	var item = equipped_items[slot]
	if debug_sprite_updates:
		print("Unequipping item from slot ", slot)
	
	if equipment_sprites.has(slot):
		equipment_sprites[slot].visible = false
		equipment_sprites[slot].texture = null
	
	equipped_items.erase(slot)
	emit_signal("item_unequipped", item, slot)
	return true

func _create_equipment_visual(item, slot: int):
	var equipment_sprite = equipment_sprites.get(slot)
	if not equipment_sprite:
		return
	
	if slot == EquipSlot.LEFT_HAND or slot == EquipSlot.RIGHT_HAND:
		return
	
	var texture = _get_item_texture(item)
	
	if not texture:
		if debug_sprite_updates:
			print("No texture found for item: ", item.item_name if "item_name" in item else "Unknown")
		texture = _create_placeholder_texture()
	
	equipment_sprite.texture = texture
	equipment_sprite.region_enabled = true
	
	var frame_x = current_direction * sprite_frame_width
	equipment_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
	equipment_sprite.z_index = equipment_z_index_layers[current_direction][slot]
	equipment_sprite.visible = true
	
	if debug_sprite_updates:
		print("Equipped ", item.item_name if "item_name" in item else "item", " in slot ", slot)
	
	if is_lying:
		_apply_lying_rotation()

func _get_item_texture(item) -> Texture2D:
	if not item:
		return null
	
	# Try various methods to get item texture
	if item.has_method("get_clothing_texture"):
		var texture = item.get_clothing_texture()
		if texture:
			return texture
	
	if item.has_method("get_texture"):
		var texture = item.get_texture()
		if texture:
			return texture
	
	var icon_node = item.get_node_or_null("Sprite")
	if icon_node and icon_node.texture:
		return icon_node.texture
	
	if "sprite" in item and item.sprite and item.sprite.texture:
		return item.sprite.texture
	
	if "clothing_texture_path" in item and item.clothing_texture_path != "":
		var texture = _load_texture_from_path(item.clothing_texture_path)
		if texture:
			return texture
	
	if "texture_path" in item and item.texture_path != "":
		var texture = _load_texture_from_path(item.texture_path)
		if texture:
			return texture
	
	if asset_manager and "item_name" in item:
		var texture = _try_load_from_asset_manager(item)
		if texture:
			return texture
	
	return null

func _load_texture_from_path(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	
	var texture = load(path)
	if texture and texture is Texture2D:
		return texture
	
	return null

func _try_load_from_asset_manager(item) -> Texture2D:
	if not asset_manager or not "item_name" in item:
		return null
	
	var item_name = item.item_name.to_lower().replace(" ", "_")
	var possible_paths = [
		"res://Assets/Icons/Items/In_hand/" + item_name + ".png"
	]
	
	for path in possible_paths:
		if asset_manager.has_method("get_resource"):
			var texture = asset_manager.get_resource(path)
			if texture:
				return texture
		elif ResourceLoader.exists(path):
			var texture = load(path)
			if texture and texture is Texture2D:
				return texture
	
	return null

func _create_placeholder_texture() -> Texture2D:
	var image = Image.create(sprite_frame_width, sprite_frame_height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.5, 0.5, 0.5, 0.5))
	return ImageTexture.create_from_image(image)

# Limb system
func _on_body_part_damaged(part_name: String, current_health: float):
	var limb_type = _get_limb_type_from_part_name(part_name)
	
	if limb_type != null and current_health <= 0 and limb_type != LimbType.BODY:
		detach_limb(limb_type)

func _get_limb_type_from_part_name(part_name: String) -> int:
	var part_lower = part_name.to_lower()
	match part_lower:
		"chest", "torso", "body": return LimbType.BODY
		"head": return LimbType.HEAD
		"left arm": return LimbType.LEFT_ARM
		"right arm": return LimbType.RIGHT_ARM
		"left hand": return LimbType.LEFT_HAND
		"right hand": return LimbType.RIGHT_HAND
		"left leg": return LimbType.LEFT_LEG
		"right leg": return LimbType.RIGHT_LEG
		"left foot": return LimbType.LEFT_FOOT
		"right foot": return LimbType.RIGHT_FOOT
		"groin": return LimbType.GROIN
		_: return -1

func detach_limb(limb_type: LimbType):
	if limb_type == LimbType.BODY or not limbs_attached[limb_type]:
		return
	
	limb_sprites[limb_type].visible = false
	limbs_attached[limb_type] = false
	
	if limb_type == LimbType.LEFT_HAND and left_hand_inhand_sprite:
		left_hand_inhand_sprite.visible = false
	elif limb_type == LimbType.RIGHT_HAND and right_hand_inhand_sprite:
		right_hand_inhand_sprite.visible = false
	
	emit_signal("limb_detached", LimbType.keys()[limb_type])

func reattach_limb(limb_type: LimbType):
	if limb_type == LimbType.BODY or limbs_attached[limb_type]:
		return
	
	limb_sprites[limb_type].visible = true
	limbs_attached[limb_type] = true
	
	if limb_type == LimbType.LEFT_HAND or limb_type == LimbType.RIGHT_HAND:
		update_inhand_sprites_from_inventory()
	
	_update_sprite_frames()
	_update_sprite_z_ordering()
	
	if is_lying:
		_apply_lying_rotation()
	
	emit_signal("limb_attached", LimbType.keys()[limb_type])

# Character data application
func apply_character_data(data):
	if data == null or typeof(data) != TYPE_DICTIONARY:
		emit_signal("customization_applied", false)
		return
	
	if debug_sprite_updates:
		print("Applying character data")
	
	_apply_character_properties(data)
	_apply_character_textures(data)
	_apply_character_clothing(data)
	
	call_deferred("_finalize_customization_application")

func _apply_character_properties(data: Dictionary):
	if "sex" in data and data.sex != null:
		character_sex = data.sex
		_load_limb_textures()
	
	if "race" in data and data.race != null:
		race_index = data.race
		_load_limb_textures()
	
	if "direction" in data and data.direction != null and typeof(data.direction) == TYPE_INT:
		if data.direction >= 0 and data.direction <= 3:
			set_direction(data.direction)

func _apply_character_textures(data: Dictionary):
	if "underwear_texture" in data and data.underwear_texture != null:
		var texture = _load_texture_from_asset_manager_or_file(data.underwear_texture)
		set_underwear(texture)
	
	if "undershirt_texture" in data and data.undershirt_texture != null:
		var texture = _load_texture_from_asset_manager_or_file(data.undershirt_texture)
		set_undershirt(texture)
	
	if "hair_texture" in data and data.hair_texture != null and "hair_color" in data:
		var hair_color = _convert_color_data(data.hair_color, Color(0.3, 0.2, 0.1))
		var texture = _load_texture_from_asset_manager_or_file(data.hair_texture)
		set_hair(texture, hair_color)
	
	if character_sex == 0 and "facial_hair_texture" in data and data.facial_hair_texture != null and "facial_hair_color" in data:
		var facial_color = _convert_color_data(data.facial_hair_color, Color(0.3, 0.2, 0.1))
		var texture = _load_texture_from_asset_manager_or_file(data.facial_hair_texture)
		set_facial_hair(texture, facial_color)

func _apply_character_clothing(data: Dictionary):
	if "clothing_textures" in data and data.clothing_textures != null:
		if typeof(data.clothing_textures) == TYPE_DICTIONARY:
			set_clothing(data.clothing_textures)

func _load_texture_from_asset_manager_or_file(texture_path: String) -> Texture2D:
	var texture = null
	if asset_manager:
		texture = asset_manager.get_resource(texture_path)
	else:
		texture = load(texture_path) if ResourceLoader.exists(texture_path) else null
	return texture

func _convert_color_data(color_data, default_color: Color) -> Color:
	if typeof(color_data) == TYPE_COLOR:
		return color_data
	elif typeof(color_data) == TYPE_DICTIONARY and "r" in color_data:
		return Color(color_data.r, color_data.g, color_data.b, color_data.get("a", 1.0))
	else:
		return default_color

func _finalize_customization_application():
	_update_all_sprite_elements()
	
	emit_signal("customization_applied", true)
	if debug_sprite_updates:
		print("Character customization applied")

# Clothing system
func set_clothing(clothing_textures: Dictionary):
	if clothing_textures.is_empty():
		return

	for slot_name in clothing_textures:
		var texture_path = clothing_textures[slot_name]
		if texture_path.is_empty():
			continue

		var slot_id = _get_slot_id_from_name(slot_name)
		if slot_id < 0:
			continue

		var equipment_sprite = equipment_sprites.get(slot_id)
		if not equipment_sprite:
			continue

		var texture = _load_texture_from_asset_manager_or_file(texture_path)
			
		if texture:
			equipment_sprite.texture = texture
			equipment_sprite.region_enabled = true

			var frame_x = current_direction * sprite_frame_width
			equipment_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
			equipment_sprite.z_index = equipment_z_index_layers[current_direction][slot_id]
			equipment_sprite.visible = true

			if is_lying:
				_apply_lying_rotation()

func _get_slot_id_from_name(slot_name: String) -> int:
	slot_name = slot_name.to_lower()
	
	match slot_name:
		"head", "hat", "helmet": return EquipSlot.HEAD
		"eyes", "glasses", "goggles": return EquipSlot.EYES
		"mask", "facemask": return EquipSlot.MASK
		"ears", "earpiece", "headset": return EquipSlot.EARS
		"neck", "tie": return EquipSlot.NECK
		"outer", "armor", "suit": return EquipSlot.OUTER
		"uniform", "jumpsuit", "body": return EquipSlot.UNIFORM
		"suit", "jacket", "coat": return EquipSlot.SUIT
		"gloves": return EquipSlot.GLOVES
		"belt": return EquipSlot.BELT
		"shoes", "boots": return EquipSlot.SHOES
		"back", "backpack": return EquipSlot.BACK
		"id", "badge": return EquipSlot.ID
		"left_hand", "lefthand": return EquipSlot.LEFT_HAND
		"right_hand", "righthand": return EquipSlot.RIGHT_HAND
		_: return -1

# Utility functions
func clear_all_customization():
	if debug_sprite_updates:
		print("Clearing all customization sprites")
	
	if hair_sprite:
		hair_sprite.texture = null
		hair_sprite.visible = false
	
	if facial_hair_sprite:
		facial_hair_sprite.texture = null
		facial_hair_sprite.visible = false
	
	if underwear_sprite:
		underwear_sprite.texture = null
		underwear_sprite.visible = false
		underwear_sprite.region_enabled = false
	
	if undershirt_sprite:
		undershirt_sprite.texture = null
		undershirt_sprite.visible = false
		undershirt_sprite.region_enabled = false
	
	for slot in equipment_sprites:
		var sprite = equipment_sprites[slot]
		if sprite:
			sprite.texture = null
			sprite.visible = false
	
	character_sex = 0
	race_index = 0
	current_direction = Direction.SOUTH
	
	if debug_sprite_updates:
		print("All customization cleared")

func refresh_all_equipment():
	for slot in equipped_items:
		var item = equipped_items[slot]
		if item:
			_create_equipment_visual(item, slot)
	
	if debug_sprite_updates:
		print("Refreshed all equipment visuals")

func get_direction_name() -> String:
	match current_direction:
		Direction.SOUTH: return "South"
		Direction.NORTH: return "North"
		Direction.EAST: return "East"
		Direction.WEST: return "West"
		_: return "Unknown"

func rotate_preview(clockwise: bool = true):
	var next_direction = current_direction
	
	if clockwise:
		match current_direction:
			Direction.SOUTH: next_direction = Direction.WEST
			Direction.WEST: next_direction = Direction.NORTH
			Direction.NORTH: next_direction = Direction.EAST
			Direction.EAST: next_direction = Direction.SOUTH
	else:
		match current_direction:
			Direction.SOUTH: next_direction = Direction.EAST
			Direction.EAST: next_direction = Direction.NORTH
			Direction.NORTH: next_direction = Direction.WEST
			Direction.WEST: next_direction = Direction.SOUTH
	
	set_direction(next_direction)

func rotate_left():
	rotate_preview(false)

func rotate_right():
	rotate_preview(true)

# Rotation effects for knockback and space drift
func _set_rotation(rotation_angle: float):
	if is_lying:  # Don't override lying rotation
		return
	
	var all_sprites = _get_all_sprites_for_rotation()
	
	for sprite in all_sprites:
		if sprite and sprite.visible:
			sprite.rotation = rotation_angle
			sprite.position = Vector2.ZERO

func clear_rotation():
	var all_sprites = _get_all_sprites_for_rotation()
	
	for sprite in all_sprites:
		if sprite and sprite.visible:
			sprite.rotation = 0.0
			sprite.position = Vector2.ZERO

# Network/multiplayer support
func _get_entity_network_id() -> String:
	if Entity and Entity.has_method("get_network_id"):
		return Entity.get_network_id()
	elif Entity and "peer_id" in Entity:
		return "player_" + str(Entity.peer_id)
	elif Entity and Entity.has_meta("network_id"):
		return Entity.get_meta("network_id")
	elif Entity:
		return Entity.get_path()
	else:
		return str(get_instance_id())

func _get_item_network_id(item) -> String:
	if not item:
		return ""

	if "network_id" in item and item.network_id != "":
		return str(item.network_id)
	elif item.has_meta("network_id"):
		return str(item.get_meta("network_id"))
	else:
		var new_id = str(item.get_instance_id()) + "_" + str(Time.get_ticks_msec())
		item.set_meta("network_id", new_id)
		return new_id

# RPC functions for multiplayer synchronization
@rpc("any_peer", "call_local", "reliable")
func sync_direction(direction: int):
	set_direction(direction)

@rpc("any_peer", "call_local", "reliable")
func sync_lying_state(lying: bool, direction: int = -1):
	set_lying_state(lying, direction)

@rpc("any_peer", "call_local", "reliable")
func sync_sex(sex: int):
	set_sex(sex)

@rpc("any_peer", "call_local", "reliable")
func sync_race(race: int):
	set_race(race)

@rpc("any_peer", "call_local", "reliable")
func sync_equip_item(item_network_id: String, slot: int, entity_network_id: String):
	var item = _find_item_by_network_id(item_network_id)
	if item:
		_equip_item_internal(item, slot)

@rpc("any_peer", "call_local", "reliable")
func sync_unequip_item(slot: int, entity_network_id: String):
	_unequip_item_internal(slot)

func _find_item_by_network_id(network_id: String):
	if network_id == "":
		return null
	
	# Check equipped items first
	for slot in equipped_items:
		var item = equipped_items[slot]
		if item and _get_item_network_id(item) == network_id:
			return item
	
	# Search world or scene for item
	var world_node = get_tree().get_first_node_in_group("world")
	if not world_node:
		world_node = get_tree().current_scene
	
	if world_node and world_node.has_method("get_item_by_network_id"):
		var item = world_node.get_item_by_network_id(network_id)
		if item:
			return item
	
	# Fallback: search all items in scene
	var all_items = get_tree().get_nodes_in_group("items")
	for item in all_items:
		if _get_item_network_id(item) == network_id:
			return item
	
	return null

# Public interface
func get_debug_info() -> Dictionary:
	return {
		"current_direction": current_direction,
		"is_lying": is_lying,
		"character_sex": character_sex,
		"race_index": race_index,
		"limbs_attached": limbs_attached.duplicate(),
		"equipped_items_count": equipped_items.size(),
		"is_thrusting": is_thrusting,
		"has_entity": Entity != null,
		"has_inventory_system": inventory_system != null,
		"has_asset_manager": asset_manager != null
	}

func force_update_all_sprites():
	_update_all_sprite_elements()
	if debug_sprite_updates:
		print("Forced update of all sprite elements")
