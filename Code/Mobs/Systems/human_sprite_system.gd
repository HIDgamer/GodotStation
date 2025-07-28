extends Node2D
class_name HumanSpriteSystem

signal limb_attached(limb_name)
signal limb_detached(limb_name)
signal sprite_direction_changed(direction)
signal item_equipped(item, slot)
signal item_unequipped(item, slot)
signal customization_applied(success)

enum LimbType {BODY, HEAD, LEFT_ARM, RIGHT_ARM, LEFT_HAND, RIGHT_HAND, GROIN, LEFT_LEG, RIGHT_LEG, LEFT_FOOT, RIGHT_FOOT}
enum Direction {SOUTH, NORTH, EAST, WEST}
enum EquipSlot {
	HEAD, EYES, MASK, EARS, NECK, OUTER, UNIFORM, SUIT, GLOVES, BELT, SHOES, BACK, ID, LEFT_HAND, RIGHT_HAND
}

@export var sprite_frames_horizontal: int = 4
@export var sprite_frames_vertical: int = 1
@export var sprite_frame_width: int = 32
@export var sprite_frame_height: int = 32

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

var equipment_container: Node2D
var held_items_container: Node2D
var left_hand_item_position: Node2D
var right_hand_item_position: Node2D
var undergarment_container: Node2D
var inhand_sprites_container: Node2D

var left_hand_inhand_sprite: Sprite2D
var right_hand_inhand_sprite: Sprite2D

var Entity = null
var inventory_system: Node = null
var asset_manager = null

var current_direction: int = Direction.SOUTH
var is_lying: bool = false
var lying_direction: int = Direction.SOUTH
var lying_offset: Vector2 = Vector2(0, 2)

var limbs_attached = {
	LimbType.BODY: true, LimbType.HEAD: true, LimbType.LEFT_ARM: true, LimbType.RIGHT_ARM: true,
	LimbType.LEFT_HAND: true, LimbType.RIGHT_HAND: true, LimbType.LEFT_LEG: true, 
	LimbType.RIGHT_LEG: true, LimbType.LEFT_FOOT: true, LimbType.RIGHT_FOOT: true
}

var limb_sprites = {}
var equipped_items = {}
var equipment_sprites = {}

var underwear_sprite: Sprite2D = null
var undershirt_sprite: Sprite2D = null
var hair_sprite: Sprite2D = null
var facial_hair_sprite: Sprite2D = null

var character_sex: int = 0
var race_index: int = 0

var is_loading_textures: bool = false

var limb_z_index_layers = {
	Direction.SOUTH: {LimbType.BODY: 1, LimbType.HEAD: 2, LimbType.LEFT_ARM: 2, LimbType.RIGHT_ARM: 2,
		LimbType.LEFT_HAND: 2, LimbType.RIGHT_HAND: 2, LimbType.LEFT_LEG: 2, LimbType.RIGHT_LEG: 2,
		LimbType.LEFT_FOOT: 2, LimbType.RIGHT_FOOT: 2},
	Direction.NORTH: {LimbType.BODY: 1, LimbType.HEAD: 2, LimbType.LEFT_ARM: 2, LimbType.RIGHT_ARM: 2,
		LimbType.LEFT_HAND: 2, LimbType.RIGHT_HAND: 2, LimbType.LEFT_LEG: 2, LimbType.RIGHT_LEG: 2,
		LimbType.LEFT_FOOT: 2, LimbType.RIGHT_FOOT: 2},
	Direction.EAST: {LimbType.BODY: 1, LimbType.HEAD: 2, LimbType.LEFT_ARM: 2, LimbType.RIGHT_ARM: 2,
		LimbType.LEFT_HAND: 2, LimbType.RIGHT_HAND: 5, LimbType.LEFT_LEG: 2, LimbType.RIGHT_LEG: 2,
		LimbType.LEFT_FOOT: 2, LimbType.RIGHT_FOOT: 5},
	Direction.WEST: {LimbType.BODY: 1, LimbType.HEAD: 2, LimbType.LEFT_ARM: 2, LimbType.RIGHT_ARM: 2,
		LimbType.LEFT_HAND: 5, LimbType.RIGHT_HAND: 2, LimbType.LEFT_LEG: 2, LimbType.RIGHT_LEG: 2,
		LimbType.LEFT_FOOT: 5, LimbType.RIGHT_FOOT: 2}
}

var equipment_z_index_layers = {
	Direction.SOUTH: {EquipSlot.UNIFORM: 4, EquipSlot.SUIT: 5, EquipSlot.OUTER: 6, EquipSlot.BELT: 7, 
		EquipSlot.BACK: 5, EquipSlot.SHOES: 5, EquipSlot.GLOVES: 5, EquipSlot.MASK: 4, EquipSlot.EYES: 4, 
		EquipSlot.HEAD: 8, EquipSlot.EARS: 4, EquipSlot.NECK: 4, EquipSlot.ID: 5, EquipSlot.LEFT_HAND: 6, EquipSlot.RIGHT_HAND: 6},
	Direction.NORTH: {EquipSlot.UNIFORM: 4, EquipSlot.SUIT: 5, EquipSlot.OUTER: 6, EquipSlot.BELT: 7, 
		EquipSlot.BACK: 5, EquipSlot.SHOES: 5, EquipSlot.GLOVES: 5, EquipSlot.MASK: 4, EquipSlot.EYES: 4, 
		EquipSlot.HEAD: 8, EquipSlot.EARS: 4, EquipSlot.NECK: 4, EquipSlot.ID: 5, EquipSlot.LEFT_HAND: 6, EquipSlot.RIGHT_HAND: 6},
	Direction.EAST: {EquipSlot.UNIFORM: 4, EquipSlot.SUIT: 5, EquipSlot.OUTER: 6, EquipSlot.BELT: 7, 
		EquipSlot.BACK: 5, EquipSlot.SHOES: 6, EquipSlot.GLOVES: 6, EquipSlot.MASK: 4, EquipSlot.EYES: 4, 
		EquipSlot.HEAD: 8, EquipSlot.EARS: 4, EquipSlot.NECK: 4, EquipSlot.ID: 5, EquipSlot.LEFT_HAND: 6, EquipSlot.RIGHT_HAND: 8},
	Direction.WEST: {EquipSlot.UNIFORM: 4, EquipSlot.SUIT: 5, EquipSlot.OUTER: 6, EquipSlot.BELT: 7, 
		EquipSlot.BACK: 5, EquipSlot.SHOES: 6, EquipSlot.GLOVES: 6, EquipSlot.MASK: 4, EquipSlot.EYES: 4, 
		EquipSlot.HEAD: 8, EquipSlot.EARS: 4, EquipSlot.NECK: 4, EquipSlot.ID: 5, EquipSlot.LEFT_HAND: 8, EquipSlot.RIGHT_HAND: 6}
}

var thrust_tween = null
var is_thrusting = false

func _ready():
	asset_manager = get_node_or_null("/root/CharacterAssetManager")
	
	create_equipment_containers()
	create_undergarment_container()
	create_inhand_sprites_container()
	setup_sprites()
	
	limb_sprites = {
		LimbType.BODY: body_sprite, LimbType.HEAD: head_sprite, LimbType.LEFT_ARM: left_arm_sprite,
		LimbType.RIGHT_ARM: right_arm_sprite, LimbType.LEFT_HAND: left_hand_sprite, 
		LimbType.RIGHT_HAND: right_hand_sprite, LimbType.LEFT_LEG: left_leg_sprite,
		LimbType.RIGHT_LEG: right_leg_sprite, LimbType.LEFT_FOOT: left_foot_sprite,
		LimbType.RIGHT_FOOT: right_foot_sprite
	}
	
	set_direction(Direction.SOUTH)
	
	if get_parent() and Entity == null:
		initialize(get_parent())
	
	connect_to_inventory_system()

func connect_to_inventory_system():
	if not get_parent():
		return
	
	inventory_system = get_parent().get_node_or_null("InventorySystem")
	if not inventory_system:
		print("HumanSpriteSystem: No InventorySystem found in parent entity")
		return
	
	print("HumanSpriteSystem: Connected to InventorySystem")
	
	if inventory_system.has_signal("item_equipped"):
		if not inventory_system.item_equipped.is_connected(_on_inventory_item_equipped):
			inventory_system.item_equipped.connect(_on_inventory_item_equipped)
	
	if inventory_system.has_signal("item_unequipped"):
		if not inventory_system.item_unequipped.is_connected(_on_inventory_item_unequipped):
			inventory_system.item_unequipped.connect(_on_inventory_item_unequipped)
	
	if inventory_system.has_signal("inventory_updated"):
		if not inventory_system.inventory_updated.is_connected(_on_inventory_updated):
			inventory_system.inventory_updated.connect(_on_inventory_updated)
	
	update_inhand_sprites_from_inventory()

func _on_inventory_item_equipped(item, slot):
	if slot == 13 or slot == 14:
		update_inhand_sprites_from_inventory()

func _on_inventory_item_unequipped(item, slot):
	if slot == 13 or slot == 14:
		update_inhand_sprites_from_inventory()

func _on_inventory_updated():
	update_inhand_sprites_from_inventory()

func update_inhand_sprites_from_inventory():
	if not inventory_system:
		return
	
	var left_hand_item = inventory_system.get_item_in_slot(13)
	var right_hand_item = inventory_system.get_item_in_slot(14)
	
	update_single_inhand_sprite(left_hand_item, left_hand_inhand_sprite, "left")
	update_single_inhand_sprite(right_hand_item, right_hand_inhand_sprite, "right")

func update_single_inhand_sprite(item, sprite: Sprite2D, hand_suffix: String):
	if not sprite:
		return
	
	if not item or not is_instance_valid(item):
		sprite.visible = false
		sprite.texture = null
		return
	
	var item_name = get_item_name_for_inhand(item)
	if item_name == "":
		sprite.visible = false
		return
	
	var texture = get_inhand_texture_from_asset_manager(item_name, hand_suffix)
	
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
			apply_lying_rotation_to_sprite(sprite)
		
		print("HumanSpriteSystem: Updated ", hand_suffix, " hand in-hand sprite for ", item_name)
	else:
		sprite.visible = false
		sprite.texture = null
		print("HumanSpriteSystem: No in-hand texture found for ", item_name, "_", hand_suffix)

func get_item_name_for_inhand(item) -> String:
	if "obj_name" in item:
		return item.obj_name
	elif "name" in item:
		return item.name
	else:
		print("HumanSpriteSystem: Item has no obj_name or name property")
		return ""

func get_inhand_texture_from_asset_manager(item_name: String, hand_suffix: String) -> Texture2D:
	if not asset_manager:
		print("HumanSpriteSystem: No asset manager available")
		return null
	
	print("HumanSpriteSystem: Original item_name: '", item_name, "', hand_suffix: '", hand_suffix, "'")
	
	if asset_manager.has_method("get_inhand_texture"):
		var texture = asset_manager.get_inhand_texture(item_name, hand_suffix)
		if texture:
			print("HumanSpriteSystem: Found texture via asset manager get_inhand_texture method")
			return texture
	
	# Try multiple naming conventions
	var naming_variations = [
		item_name + "_" + hand_suffix,  # Original case: "M40_HEDP_grenade_right"
		item_name.to_lower() + "_" + hand_suffix,  # Lowercase: "m40_hedp_grenade_right"
		item_name.to_lower().replace(" ", "_") + "_" + hand_suffix  # Normalized: same in this case
	]
	
	for variation in naming_variations:
		print("HumanSpriteSystem: Trying variation: '", variation, "'")
		
		var possible_paths = [
			"res://Assets/Icons/Items/In_hand/" + variation + ".png",
			"res://Assets/Icons/Items/Inhand/" + variation + ".png",  # Alternative folder name
			"res://Assets/Icons/Items/in_hand/" + variation + ".png"   # Alternative folder name
		]
		
		for path in possible_paths:
			print("HumanSpriteSystem: Checking path: ", path)
			
			# Check if file exists first
			if ResourceLoader.exists(path):
				print("HumanSpriteSystem: File exists, attempting to load: ", path)
				var texture = load(path)
				if texture and texture is Texture2D:
					print("HumanSpriteSystem: Successfully loaded texture: ", path)
					return texture
				else:
					print("HumanSpriteSystem: File exists but failed to load as Texture2D: ", path)
			else:
				print("HumanSpriteSystem: File does not exist: ", path)
			
			# Also try via asset manager if available
			if asset_manager.has_method("get_resource"):
				var texture = asset_manager.get_resource(path)
				if texture:
					print("HumanSpriteSystem: Found texture via asset manager: ", path)
					return texture
	
	print("HumanSpriteSystem: No in-hand texture found for any variation of: ", item_name)
	return null

func create_undergarment_container():
	# Check if container already exists
	if undergarment_container and is_instance_valid(undergarment_container):
		print("HumanSpriteSystem: Undergarment container already exists, skipping creation")
		# Make sure sprites exist within the existing container
		if not underwear_sprite or not is_instance_valid(underwear_sprite):
			underwear_sprite = undergarment_container.get_node_or_null("UnderwearSprite")
			if not underwear_sprite:
				underwear_sprite = Sprite2D.new()
				underwear_sprite.name = "UnderwearSprite"
				underwear_sprite.centered = true
				underwear_sprite.region_enabled = true
				underwear_sprite.z_index = 3
				underwear_sprite.visible = false
				undergarment_container.add_child(underwear_sprite)
		
		if not undershirt_sprite or not is_instance_valid(undershirt_sprite):
			undershirt_sprite = undergarment_container.get_node_or_null("UndershirtSprite")
			if not undershirt_sprite:
				undershirt_sprite = Sprite2D.new()
				undershirt_sprite.name = "UndershirtSprite"
				undershirt_sprite.centered = true
				undershirt_sprite.region_enabled = true
				undershirt_sprite.z_index = 3
				undershirt_sprite.visible = false
				undergarment_container.add_child(undershirt_sprite)
		return
	
	# Create new container only if it doesn't exist
	print("HumanSpriteSystem: Creating new undergarment container")
	undergarment_container = Node2D.new()
	undergarment_container.name = "UndergarmentContainer"
	add_child(undergarment_container)
	
	underwear_sprite = Sprite2D.new()
	underwear_sprite.name = "UnderwearSprite"
	underwear_sprite.centered = true
	underwear_sprite.region_enabled = true
	underwear_sprite.z_index = 3
	underwear_sprite.visible = false
	undergarment_container.add_child(underwear_sprite)
	
	undershirt_sprite = Sprite2D.new()
	undershirt_sprite.name = "UndershirtSprite"
	undershirt_sprite.centered = true
	undershirt_sprite.region_enabled = true
	undershirt_sprite.z_index = 3
	undershirt_sprite.visible = false
	undergarment_container.add_child(undershirt_sprite)

func create_inhand_sprites_container():
	inhand_sprites_container = Node2D.new()
	inhand_sprites_container.name = "InhandSpritesContainer"
	add_child(inhand_sprites_container)
	
	left_hand_inhand_sprite = Sprite2D.new()
	left_hand_inhand_sprite.name = "LeftHandInhandSprite"
	left_hand_inhand_sprite.centered = true
	left_hand_inhand_sprite.region_enabled = true
	left_hand_inhand_sprite.visible = false
	inhand_sprites_container.add_child(left_hand_inhand_sprite)
	
	right_hand_inhand_sprite = Sprite2D.new()
	right_hand_inhand_sprite.name = "RightHandInhandSprite"
	right_hand_inhand_sprite.centered = true
	right_hand_inhand_sprite.region_enabled = true
	right_hand_inhand_sprite.visible = false
	inhand_sprites_container.add_child(right_hand_inhand_sprite)

func clear_all_customization():
	"""Clear all customization sprites to prepare for proper re-application"""
	print("HumanSpriteSystem: Clearing all customization sprites")
	
	# Clear hair
	if hair_sprite:
		hair_sprite.texture = null
		hair_sprite.visible = false
	
	# Clear facial hair
	if facial_hair_sprite:
		facial_hair_sprite.texture = null
		facial_hair_sprite.visible = false
	
	# Clear underwear
	if underwear_sprite:
		underwear_sprite.texture = null
		underwear_sprite.visible = false
		underwear_sprite.region_enabled = false
	
	# Clear undershirt
	if undershirt_sprite:
		undershirt_sprite.texture = null
		undershirt_sprite.visible = false
		undershirt_sprite.region_enabled = false
	
	# Clear equipment sprites
	for slot in equipment_sprites:
		var sprite = equipment_sprites[slot]
		if sprite:
			sprite.texture = null
			sprite.visible = false
	
	# Reset character properties to defaults
	character_sex = 0
	race_index = 0
	
	# Reset direction to default
	current_direction = Direction.SOUTH
	
	print("HumanSpriteSystem: All customization cleared, ready for proper re-application")

func create_equipment_containers():
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
	
	create_equipment_sprite_nodes()

func create_equipment_sprite_nodes():
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

func setup_sprites():
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

func _load_limb_textures():
	if !asset_manager:
		return
	
	var race_sprites = asset_manager.get_race_sprites(race_index, character_sex)
	
	var sprite_mapping = {
		"body": body_sprite,
		"head": head_sprite,
		"left_arm": left_arm_sprite,
		"right_arm": right_arm_sprite,
		"left_hand": left_hand_sprite,
		"right_hand": right_hand_sprite,
		"left_leg": left_leg_sprite,
		"right_leg": right_leg_sprite,
		"left_foot": left_foot_sprite,
		"right_foot": right_foot_sprite
	}
	
	for sprite_key in sprite_mapping:
		var sprite = sprite_mapping[sprite_key]
		if race_sprites.has(sprite_key) and sprite:
			var texture_path = race_sprites[sprite_key]["texture"]
			if texture_path and asset_manager:
				var texture = asset_manager.get_resource(texture_path)
				if texture:
					sprite.texture = texture

func _setup_sprite_properties():
	var all_sprites = [body_sprite, head_sprite, left_arm_sprite, right_arm_sprite,
		left_hand_sprite, right_hand_sprite, left_leg_sprite, right_leg_sprite,
		left_foot_sprite, right_foot_sprite]
	
	for sprite in all_sprites:
		if sprite:
			sprite.region_enabled = true
			sprite.region_rect = Rect2(0, 0, sprite_frame_width, sprite_frame_height)
			sprite.position = Vector2.ZERO
			sprite.centered = true

func initialize(entity_reference):
	Entity = entity_reference
	
	if Entity:
		if Entity.has_signal("body_part_damaged"):
			if !Entity.is_connected("body_part_damaged", Callable(self, "_on_body_part_damaged")):
				Entity.body_part_damaged.connect(_on_body_part_damaged)
	
	var grid_controller = get_parent()
	if grid_controller:
		var movement_comp = grid_controller.get_node_or_null("MovementComponent")
		if movement_comp:
			if !movement_comp.is_connected("direction_changed", Callable(self, "_on_direction_changed_from_movement")):
				movement_comp.direction_changed.connect(_on_direction_changed_from_movement)

func _on_direction_changed_from_movement(old_dir: int, new_dir: int):
	set_direction(new_dir)

func _process(_delta):
	if Entity:
		update_sprite_frames()
		update_sprite_z_ordering()
		
		if Entity.has_method("is_prone"):
			set_lying_state(Entity.is_prone())

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

func set_direction(direction: int):
	if current_direction == direction:
		return
	
	print("HumanSpriteSystem: Setting direction to ", direction, " (was ", current_direction, ")")
	current_direction = direction
	update_sprite_frames()
	update_sprite_z_ordering()
	update_clothing_frames()
	update_customization_frames()
	update_equipment_sprites()
	update_undergarment_frames()
	update_inhand_sprite_frames()
	
	if is_lying:
		apply_instant_lying_rotation()
	
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		sync_direction.rpc(direction)
	
	emit_signal("sprite_direction_changed", direction)

func update_sprite_frames():
	for limb_type in limb_sprites:
		var sprite = limb_sprites[limb_type]
		if sprite and sprite.texture and sprite.region_enabled:
			var frame_x = current_direction * sprite_frame_width
			sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)

func update_sprite_z_ordering():
	for limb_type in limb_sprites:
		var sprite = limb_sprites[limb_type]
		if sprite and limb_z_index_layers[current_direction].has(limb_type):
			sprite.z_index = limb_z_index_layers[current_direction][limb_type]
	
	for slot in equipment_sprites:
		var sprite = equipment_sprites[slot]
		if sprite and sprite.visible and equipment_z_index_layers[current_direction].has(slot):
			sprite.z_index = equipment_z_index_layers[current_direction][slot]
	
	update_inhand_sprite_z_ordering()

func update_inhand_sprite_z_ordering():
	if left_hand_inhand_sprite and left_hand_inhand_sprite.visible:
		left_hand_inhand_sprite.z_index = equipment_z_index_layers[current_direction][EquipSlot.LEFT_HAND]
	
	if right_hand_inhand_sprite and right_hand_inhand_sprite.visible:
		right_hand_inhand_sprite.z_index = equipment_z_index_layers[current_direction][EquipSlot.RIGHT_HAND]

func set_sex(sex: int):
	if character_sex == sex:
		return
	
	character_sex = sex
	_load_limb_textures()
	update_sprite_frames()
	
	if sex == 1 and facial_hair_sprite:
		facial_hair_sprite.visible = false
	
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		sync_sex.rpc(sex)

func set_race(race: int):
	if race_index == race:
		return
	
	race_index = race
	_load_limb_textures()
	update_sprite_frames()
	
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		sync_race.rpc(race)

func update_clothing_frames():
	for slot in equipment_sprites:
		var sprite = equipment_sprites[slot]
		if sprite and sprite.visible and sprite.texture and sprite.region_enabled:
			if slot != EquipSlot.LEFT_HAND and slot != EquipSlot.RIGHT_HAND:
				var frame_x = current_direction * sprite_frame_width
				sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)

func update_customization_frames():
	var frame_x = current_direction * sprite_frame_width
	
	if hair_sprite and hair_sprite.texture:
		hair_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
	
	if facial_hair_sprite and facial_hair_sprite.texture:
		facial_hair_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)

func update_equipment_sprites():
	for slot in equipment_sprites:
		var sprite = equipment_sprites[slot]
		if sprite and sprite.visible and sprite.texture and sprite.region_enabled:
			if slot != EquipSlot.LEFT_HAND and slot != EquipSlot.RIGHT_HAND:
				var frame_x = current_direction * sprite_frame_width
				sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
				
				if equipment_z_index_layers[current_direction].has(slot):
					sprite.z_index = equipment_z_index_layers[current_direction][slot]

func update_undergarment_frames():
	if not underwear_sprite and not undershirt_sprite:
		return
	
	var frame_x = current_direction * sprite_frame_width
	print("HumanSpriteSystem: Updating undergarment frames for direction ", current_direction, " frame_x: ", frame_x)
	
	if underwear_sprite and underwear_sprite.texture and underwear_sprite.region_enabled:
		underwear_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
		print("HumanSpriteSystem: Updated underwear frame to direction ", current_direction, " frame_x: ", frame_x)
	
	if undershirt_sprite and undershirt_sprite.texture and undershirt_sprite.region_enabled:
		undershirt_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
		print("HumanSpriteSystem: Updated undershirt frame to direction ", current_direction, " frame_x: ", frame_x)

func update_inhand_sprite_frames():
	var frame_x = current_direction * sprite_frame_width
	
	if left_hand_inhand_sprite and left_hand_inhand_sprite.texture and left_hand_inhand_sprite.region_enabled:
		left_hand_inhand_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
	
	if right_hand_inhand_sprite and right_hand_inhand_sprite.texture and right_hand_inhand_sprite.region_enabled:
		right_hand_inhand_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)

func set_lying_state(lying_state: bool, direction: int = -1):
	if is_lying == lying_state:
		return
	
	is_lying = lying_state
	
	if direction < 0:
		direction = current_direction
	
	if lying_state:
		lying_direction = direction
	
	apply_instant_lying_rotation()
	
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		sync_lying_state.rpc(lying_state, direction)

func apply_instant_lying_rotation():
	var target_rotation = 0.0
	var position_offset = Vector2.ZERO
	
	if is_lying:
		match current_direction:
			Direction.EAST:
				target_rotation = PI/2.0
				position_offset = Vector2(0, lying_offset.y * 2)
			Direction.WEST:
				target_rotation = -PI/2.0
				position_offset = Vector2(0, lying_offset.y * 2)
			Direction.SOUTH:
				target_rotation = PI/2.0
				position_offset = Vector2(lying_offset.x, lying_offset.y)
			Direction.NORTH:
				target_rotation = -PI/2.0
				position_offset = Vector2(-lying_offset.x, lying_offset.y)
	
	var all_sprites = []
	all_sprites.append_array(limb_sprites.values())
	all_sprites.append_array(equipment_sprites.values())
	
	if hair_sprite: all_sprites.append(hair_sprite)
	if facial_hair_sprite: all_sprites.append(facial_hair_sprite)
	if underwear_sprite: all_sprites.append(underwear_sprite)
	if undershirt_sprite: all_sprites.append(undershirt_sprite)
	if left_hand_inhand_sprite: all_sprites.append(left_hand_inhand_sprite)
	if right_hand_inhand_sprite: all_sprites.append(right_hand_inhand_sprite)
	
	for sprite in all_sprites:
		if sprite and sprite.visible:
			sprite.rotation = target_rotation
			sprite.position = position_offset

func apply_lying_rotation_to_sprite(sprite: Sprite2D):
	if not is_lying or not sprite:
		return
	
	var target_rotation = 0.0
	var position_offset = Vector2.ZERO
	
	match current_direction:
		Direction.EAST:
			target_rotation = PI/2.0
			position_offset = Vector2(0, lying_offset.y * 2)
		Direction.WEST:
			target_rotation = -PI/2.0
			position_offset = Vector2(0, lying_offset.y * 2)
		Direction.SOUTH:
			target_rotation = PI/2.0
			position_offset = Vector2(lying_offset.x, lying_offset.y)
		Direction.NORTH:
			target_rotation = -PI/2.0
			position_offset = Vector2(-lying_offset.x, lying_offset.y)
	
	sprite.rotation = target_rotation
	sprite.position = position_offset

func show_interaction_thrust(direction: Vector2, intent_type: int = 0):
	if is_thrusting:
		return
	
	if thrust_tween and thrust_tween.is_valid():
		thrust_tween.kill()
	
	is_thrusting = true
	
	var thrust_distance = 6.0
	var thrust_duration = 0.2
	var return_duration = 0.1
	
	var thrust_offset = direction * thrust_distance
	
	thrust_tween = create_tween()
	thrust_tween.set_ease(Tween.EASE_OUT)
	thrust_tween.set_trans(Tween.TRANS_BACK)
	
	var sprites_to_animate = []
	var original_positions = {}
	var original_colors = {}
	
	for limb_type in limb_sprites:
		var sprite = limb_sprites[limb_type]
		if sprite and sprite.visible and limbs_attached[limb_type]:
			sprites_to_animate.append(sprite)
			original_positions[sprite] = sprite.position
			original_colors[sprite] = sprite.modulate
	
	for slot in equipment_sprites:
		var sprite = equipment_sprites[slot]
		if sprite and sprite.visible:
			sprites_to_animate.append(sprite)
			original_positions[sprite] = sprite.position
			original_colors[sprite] = sprite.modulate
	
	if hair_sprite and hair_sprite.visible:
		sprites_to_animate.append(hair_sprite)
		original_positions[hair_sprite] = hair_sprite.position
		original_colors[hair_sprite] = hair_sprite.modulate
	
	if facial_hair_sprite and facial_hair_sprite.visible:
		sprites_to_animate.append(facial_hair_sprite)
		original_positions[facial_hair_sprite] = facial_hair_sprite.position
		original_colors[facial_hair_sprite] = facial_hair_sprite.modulate
	
	if underwear_sprite and underwear_sprite.visible:
		sprites_to_animate.append(underwear_sprite)
		original_positions[underwear_sprite] = underwear_sprite.position
		original_colors[underwear_sprite] = underwear_sprite.modulate
	
	if undershirt_sprite and undershirt_sprite.visible:
		sprites_to_animate.append(undershirt_sprite)
		original_positions[undershirt_sprite] = undershirt_sprite.position
		original_colors[undershirt_sprite] = undershirt_sprite.modulate
	
	if left_hand_inhand_sprite and left_hand_inhand_sprite.visible:
		sprites_to_animate.append(left_hand_inhand_sprite)
		original_positions[left_hand_inhand_sprite] = left_hand_inhand_sprite.position
		original_colors[left_hand_inhand_sprite] = left_hand_inhand_sprite.modulate
	
	if right_hand_inhand_sprite and right_hand_inhand_sprite.visible:
		sprites_to_animate.append(right_hand_inhand_sprite)
		original_positions[right_hand_inhand_sprite] = right_hand_inhand_sprite.position
		original_colors[right_hand_inhand_sprite] = right_hand_inhand_sprite.modulate
	
	for sprite in sprites_to_animate:
		var target_pos = original_positions[sprite] + thrust_offset
		thrust_tween.parallel().tween_property(sprite, "position", target_pos, thrust_duration)
	
	for sprite in sprites_to_animate:
		thrust_tween.parallel().tween_property(sprite, "position", original_positions[sprite], return_duration).set_delay(thrust_duration)
	
	thrust_tween.tween_callback(func(): is_thrusting = false).set_delay(thrust_duration + return_duration)

func equip_item(item, slot: int) -> bool:
	var result = _equip_item_internal(item, slot)
	
	if result and multiplayer.has_multiplayer_peer():
		var entity_id = get_entity_network_id()
		var item_id = get_item_network_id(item)
		sync_equip_item.rpc(item_id, slot, entity_id)
	
	return result

func unequip_item(slot: int) -> bool:
	var result = _unequip_item_internal(slot)
	
	if result and multiplayer.has_multiplayer_peer():
		var entity_id = get_entity_network_id()
		sync_unequip_item.rpc(slot, entity_id)
	
	return result

func _equip_item_internal(item, slot: int) -> bool:
	if equipped_items.has(slot) and equipped_items[slot] != null:
		_unequip_item_internal(slot)
	
	print("HumanSpriteSystem: Equipping item ", item.obj_name if "obj_name" in item else "Unknown", " to slot ", slot)
	
	equipped_items[slot] = item
	_create_equipment_visual(item, slot)
	emit_signal("item_equipped", item, slot)
	return true

func _unequip_item_internal(slot: int) -> bool:
	if !equipped_items.has(slot) or equipped_items[slot] == null:
		return false
	
	var item = equipped_items[slot]
	print("HumanSpriteSystem: Unequipping item from slot ", slot)
	
	if equipment_sprites.has(slot):
		equipment_sprites[slot].visible = false
		equipment_sprites[slot].texture = null
	
	equipped_items.erase(slot)
	emit_signal("item_unequipped", item, slot)
	return true

func _create_equipment_visual(item, slot: int):
	var equipment_sprite = equipment_sprites.get(slot)
	if !equipment_sprite:
		return
	
	if slot == EquipSlot.LEFT_HAND or slot == EquipSlot.RIGHT_HAND:
		return
	
	var texture = get_item_texture(item)
	
	if !texture:
		print("HumanSpriteSystem: No texture found for item: ", item.obj_name if "obj_name" in item else "Unknown")
		var image = Image.create(sprite_frame_width, sprite_frame_height, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.5, 0.5, 0.5, 0.5))
		texture = ImageTexture.create_from_image(image)
	
	equipment_sprite.texture = texture
	equipment_sprite.region_enabled = true
	
	var frame_x = current_direction * sprite_frame_width
	equipment_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
	equipment_sprite.z_index = equipment_z_index_layers[current_direction][slot]
	equipment_sprite.visible = true
	
	print("HumanSpriteSystem: Equipped ", item.obj_name if "obj_name" in item else "item", " in slot ", slot)
	
	if is_lying:
		apply_instant_lying_rotation()

func get_item_texture(item) -> Texture2D:
	if not item:
		return null
	
	if item.has_method("get_clothing_texture"):
		var texture = item.get_clothing_texture()
		if texture:
			return texture
	
	if item.has_method("get_texture"):
		var texture = item.get_texture()
		if texture:
			return texture
	
	var icon_node = item.get_node_or_null("Icon")
	if icon_node and icon_node.texture:
		return icon_node.texture
	
	if "sprite" in item and item.sprite and item.sprite.texture:
		return item.sprite.texture
	
	if "clothing_texture_path" in item and item.clothing_texture_path != "":
		var texture = load_texture_from_path(item.clothing_texture_path)
		if texture:
			return texture
	
	if "texture_path" in item and item.texture_path != "":
		var texture = load_texture_from_path(item.texture_path)
		if texture:
			return texture
	
	if asset_manager and "obj_name" in item:
		var texture = try_load_from_asset_manager(item)
		if texture:
			return texture
	
	return null

func load_texture_from_path(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	
	var texture = load(path)
	if texture and texture is Texture2D:
		return texture
	
	return null

func try_load_from_asset_manager(item) -> Texture2D:
	if not asset_manager or not "obj_name" in item:
		return null
	
	var item_name = item.obj_name.to_lower().replace(" ", "_")
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

func set_hair(hair_texture: Texture2D, hair_color: Color):
	if !hair_texture:
		if hair_sprite:
			hair_sprite.queue_free()
			hair_sprite = null
		return
	
	if !hair_sprite:
		hair_sprite = Sprite2D.new()
		hair_sprite.name = "HairSprite"
		hair_sprite.centered = true
		hair_sprite.z_index = 4
		hair_sprite.region_enabled = true
		add_child(hair_sprite)
	
	hair_sprite.texture = hair_texture
	hair_sprite.modulate = hair_color
	hair_sprite.visible = true
	
	var frame_x = current_direction * sprite_frame_width
	hair_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
	
	if is_lying:
		apply_instant_lying_rotation()

func set_facial_hair(facial_hair_texture: Texture2D, facial_hair_color: Color):
	if !facial_hair_texture or character_sex == 1:
		if facial_hair_sprite:
			facial_hair_sprite.queue_free()
			facial_hair_sprite = null
		return
	
	if !facial_hair_sprite:
		facial_hair_sprite = Sprite2D.new()
		facial_hair_sprite.name = "FacialHairSprite"
		facial_hair_sprite.centered = true
		facial_hair_sprite.z_index = 3.5
		facial_hair_sprite.region_enabled = true
		add_child(facial_hair_sprite)
	
	facial_hair_sprite.texture = facial_hair_texture
	facial_hair_sprite.modulate = facial_hair_color
	facial_hair_sprite.visible = true
	
	var frame_x = current_direction * sprite_frame_width
	facial_hair_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
	
	if is_lying:
		apply_instant_lying_rotation()

func set_underwear(underwear_texture: Texture2D):
	# Ensure undergarment container and sprites exist
	if !undergarment_container or !underwear_sprite:
		create_undergarment_container()
	
	if !underwear_texture:
		underwear_sprite.visible = false
		underwear_sprite.texture = null
		underwear_sprite.region_enabled = false
		print("HumanSpriteSystem: Clearing underwear texture")
		return
	
	underwear_sprite.texture = underwear_texture
	underwear_sprite.region_enabled = true
	underwear_sprite.visible = true
	underwear_sprite.z_index = 3
	
	# Only update frames if we're in the scene tree and properly initialized
	if is_inside_tree() and underwear_sprite.get_parent():
		var frame_x = current_direction * sprite_frame_width
		underwear_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
		print("HumanSpriteSystem: Set underwear texture, direction: ", current_direction, " frame_x: ", frame_x)
		
		if is_lying:
			apply_lying_rotation_to_sprite(underwear_sprite)
	else:
		# Set a default frame, will be fixed later when sprite system is ready
		underwear_sprite.region_rect = Rect2(0, 0, sprite_frame_width, sprite_frame_height)
		print("HumanSpriteSystem: Set underwear texture with default frame")

func set_undershirt(undershirt_texture: Texture2D):
	# Ensure undergarment container and sprites exist
	if !undergarment_container or !undershirt_sprite:
		create_undergarment_container()
	
	if !undershirt_texture:
		undershirt_sprite.visible = false
		undershirt_sprite.texture = null
		undershirt_sprite.region_enabled = false
		print("HumanSpriteSystem: Clearing undershirt texture")
		return
	
	undershirt_sprite.texture = undershirt_texture
	undershirt_sprite.region_enabled = true
	undershirt_sprite.visible = true
	undershirt_sprite.z_index = 3
	
	# Only update frames if we're in the scene tree and properly initialized
	if is_inside_tree() and undershirt_sprite.get_parent():
		var frame_x = current_direction * sprite_frame_width
		undershirt_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
		print("HumanSpriteSystem: Set undershirt texture, direction: ", current_direction, " frame_x: ", frame_x)
		
		if is_lying:
			apply_lying_rotation_to_sprite(undershirt_sprite)
	else:
		# Set a default frame, will be fixed later when sprite system is ready
		undershirt_sprite.region_rect = Rect2(0, 0, sprite_frame_width, sprite_frame_height)
		print("HumanSpriteSystem: Set undershirt texture with default frame")

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
		if !equipment_sprite:
			continue

		var texture = null
		if asset_manager:
			texture = asset_manager.get_resource(texture_path)
		else:
			texture = load(texture_path)
			
		if texture:
			equipment_sprite.texture = texture
			equipment_sprite.region_enabled = true

			var frame_x = current_direction * sprite_frame_width
			equipment_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
			equipment_sprite.z_index = equipment_z_index_layers[current_direction][slot_id]
			equipment_sprite.visible = true

			if is_lying:
				apply_instant_lying_rotation()

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

func _on_body_part_damaged(part_name: String, current_health: float):
	var limb_type = get_limb_type_from_part_name(part_name)
	
	if limb_type != null and current_health <= 0 and limb_type != LimbType.BODY:
		detach_limb(limb_type)

func get_limb_type_from_part_name(part_name: String) -> int:
	part_name = part_name.to_lower()
	
	match part_name:
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
	
	update_sprite_frames()
	update_sprite_z_ordering()
	
	if is_lying:
		apply_instant_lying_rotation()
	
	emit_signal("limb_attached", LimbType.keys()[limb_type])

func apply_character_data(data):
	if data == null or typeof(data) != TYPE_DICTIONARY:
		emit_signal("customization_applied", false)
		return
	
	print("HumanSpriteSystem: Applying character data instantly")
	
	if "sex" in data and data.sex != null:
		character_sex = data.sex
		_load_limb_textures()
	
	if "race" in data and data.race != null:
		race_index = data.race
		_load_limb_textures()
	
	if "underwear_texture" in data and data.underwear_texture != null:
		var texture = null
		if asset_manager:
			texture = asset_manager.get_resource(data.underwear_texture)
		else:
			texture = load(data.underwear_texture) if ResourceLoader.exists(data.underwear_texture) else null
		set_underwear(texture)
	
	if "undershirt_texture" in data and data.undershirt_texture != null:
		var texture = null
		if asset_manager:
			texture = asset_manager.get_resource(data.undershirt_texture)
		else:
			texture = load(data.undershirt_texture) if ResourceLoader.exists(data.undershirt_texture) else null
		set_undershirt(texture)
	
	if "hair_texture" in data and data.hair_texture != null and "hair_color" in data:
		var hair_color = data.hair_color
		if typeof(hair_color) != TYPE_COLOR:
			if typeof(hair_color) == TYPE_DICTIONARY and "r" in hair_color:
				hair_color = Color(hair_color.r, hair_color.g, hair_color.b, hair_color.get("a", 1.0))
			else:
				hair_color = Color(0.3, 0.2, 0.1)
		
		var texture = null
		if asset_manager:
			texture = asset_manager.get_resource(data.hair_texture)
		else:
			texture = load(data.hair_texture) if ResourceLoader.exists(data.hair_texture) else null
		set_hair(texture, hair_color)
	
	if character_sex == 0 and "facial_hair_texture" in data and data.facial_hair_texture != null and "facial_hair_color" in data:
		var facial_color = data.facial_hair_color
		if typeof(facial_color) != TYPE_COLOR:
			if typeof(facial_color) == TYPE_DICTIONARY and "r" in facial_color:
				facial_color = Color(facial_color.r, facial_color.g, facial_color.b, facial_color.get("a", 1.0))
			else:
				facial_color = Color(0.3, 0.2, 0.1)
		
		var texture = null
		if asset_manager:
			texture = asset_manager.get_resource(data.facial_hair_texture)
		else:
			texture = load(data.facial_hair_texture) if ResourceLoader.exists(data.facial_hair_texture) else null
		set_facial_hair(texture, facial_color)
	
	if "clothing_textures" in data and data.clothing_textures != null:
		if typeof(data.clothing_textures) == TYPE_DICTIONARY:
			set_clothing(data.clothing_textures)
	
	if "direction" in data and data.direction != null and typeof(data.direction) == TYPE_INT:
		if data.direction >= 0 and data.direction <= 3:
			set_direction(data.direction)
	
	call_deferred("_finalize_customization_application")

func _finalize_customization_application():
	update_sprite_frames()
	update_sprite_z_ordering()
	update_clothing_frames()
	update_customization_frames()
	update_equipment_sprites()
	update_undergarment_frames()
	update_inhand_sprite_frames()
	
	if is_lying:
		apply_instant_lying_rotation()
	
	emit_signal("customization_applied", true)
	print("HumanSpriteSystem: Character customization applied instantly")

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

@rpc("any_peer", "call_local", "reliable")
func sync_equip_item(item_network_id: String, slot: int, entity_network_id: String):
	var item = find_item_by_network_id(item_network_id)
	if item:
		_equip_item_internal(item, slot)

@rpc("any_peer", "call_local", "reliable")
func sync_unequip_item(slot: int, entity_network_id: String):
	_unequip_item_internal(slot)

func get_entity_network_id() -> String:
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

func get_item_network_id(item) -> String:
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

func find_item_by_network_id(network_id: String):
	if network_id == "":
		return null
	
	for slot in equipped_items:
		var item = equipped_items[slot]
		if item and get_item_network_id(item) == network_id:
			return item
	
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		world = get_tree().current_scene
	
	if world and world.has_method("get_item_by_network_id"):
		var item = world.get_item_by_network_id(network_id)
		if item:
			return item
	
	var all_items = get_tree().get_nodes_in_group("items")
	for item in all_items:
		if get_item_network_id(item) == network_id:
			return item
	
	return null

func refresh_all_equipment():
	for slot in equipped_items:
		var item = equipped_items[slot]
		if item:
			_create_equipment_visual(item, slot)
	
	print("HumanSpriteSystem: Refreshed all equipment visuals")
