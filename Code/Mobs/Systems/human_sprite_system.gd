extends Node2D
class_name HumanSpriteSystem

# Signals
signal limb_attached(limb_name)
signal limb_detached(limb_name)
signal sprite_direction_changed(direction)
signal item_equipped(item, slot)
signal item_unequipped(item, slot)
signal customization_applied(success)

# Enums
enum LimbType {BODY, HEAD, LEFT_ARM, RIGHT_ARM, LEFT_HAND, RIGHT_HAND, GROIN, LEFT_LEG, RIGHT_LEG, LEFT_FOOT, RIGHT_FOOT}
enum Direction {SOUTH, NORTH, EAST, WEST}
enum EquipSlot {
	HEAD, EYES, MASK, EARS, NECK, OUTER, UNIFORM, SUIT, GLOVES, BELT, SHOES, BACK, ID, LEFT_HAND, RIGHT_HAND
}

# Sprite configuration
@export var sprite_frames_horizontal: int = 4
@export var sprite_frames_vertical: int = 1
@export var sprite_frame_width: int = 32
@export var sprite_frame_height: int = 32

# Node references - created dynamically
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

# State variables
var Entity = null
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

# Equipment and customization sprites
var underwear_sprite: Sprite2D = null
var undershirt_sprite: Sprite2D = null
var hair_sprite: Sprite2D = null
var facial_hair_sprite: Sprite2D = null

# Character properties
var character_sex: int = 0
var race_index: int = 0
var asset_manager = null

# Recursion guard
var is_loading_textures: bool = false

# Z-index layers for proper rendering order
var limb_z_index_layers = {
	Direction.SOUTH: {LimbType.BODY: 1, LimbType.HEAD: 2, LimbType.LEFT_ARM: 2, LimbType.RIGHT_ARM: 2,
		LimbType.LEFT_HAND: 2, LimbType.RIGHT_HAND: 2, LimbType.LEFT_LEG: 2, LimbType.RIGHT_LEG: 2,
		LimbType.LEFT_FOOT: 2, LimbType.RIGHT_FOOT: 2},
	Direction.NORTH: {LimbType.BODY: 1, LimbType.HEAD: 2, LimbType.LEFT_ARM: 2, LimbType.RIGHT_ARM: 2,
		LimbType.LEFT_HAND: 2, LimbType.RIGHT_HAND: 2, LimbType.LEFT_LEG: 2, LimbType.RIGHT_LEG: 2,
		LimbType.LEFT_FOOT: 2, LimbType.RIGHT_FOOT: 2},
	Direction.EAST: {LimbType.BODY: 1, LimbType.HEAD: 2, LimbType.LEFT_ARM: 2, LimbType.RIGHT_ARM: 2,
		LimbType.LEFT_HAND: 2, LimbType.RIGHT_HAND: 2, LimbType.LEFT_LEG: 2, LimbType.RIGHT_LEG: 2,
		LimbType.LEFT_FOOT: 2, LimbType.RIGHT_FOOT: 2},
	Direction.WEST: {LimbType.BODY: 1, LimbType.HEAD: 2, LimbType.LEFT_ARM: 2, LimbType.RIGHT_ARM: 2,
		LimbType.LEFT_HAND: 2, LimbType.RIGHT_HAND: 2, LimbType.LEFT_LEG: 2, LimbType.RIGHT_LEG: 2,
		LimbType.LEFT_FOOT: 2, LimbType.RIGHT_FOOT: 2}
}

var equipment_z_index_layers = {
	Direction.SOUTH: {EquipSlot.UNIFORM: 2, EquipSlot.SUIT: 3, EquipSlot.OUTER: 4, EquipSlot.BELT: 5, 
		EquipSlot.BACK: 5, EquipSlot.SHOES: 5, EquipSlot.GLOVES: 5, EquipSlot.MASK: 4, EquipSlot.EYES: 4, 
		EquipSlot.HEAD: 4, EquipSlot.EARS: 4, EquipSlot.NECK: 4, EquipSlot.ID: 5},
	Direction.NORTH: {EquipSlot.UNIFORM: 2, EquipSlot.SUIT: 3, EquipSlot.OUTER: 4, EquipSlot.BELT: 5, 
		EquipSlot.BACK: 5, EquipSlot.SHOES: 5, EquipSlot.GLOVES: 5, EquipSlot.MASK: 4, EquipSlot.EYES: 4, 
		EquipSlot.HEAD: 4, EquipSlot.EARS: 4, EquipSlot.NECK: 4, EquipSlot.ID: 5},
	Direction.EAST: {EquipSlot.UNIFORM: 2, EquipSlot.SUIT: 3, EquipSlot.OUTER: 4, EquipSlot.BELT: 5, 
		EquipSlot.BACK: 5, EquipSlot.SHOES: 5, EquipSlot.GLOVES: 5, EquipSlot.MASK: 4, EquipSlot.EYES: 4, 
		EquipSlot.HEAD: 4, EquipSlot.EARS: 4, EquipSlot.NECK: 4, EquipSlot.ID: 5},
	Direction.WEST: {EquipSlot.UNIFORM: 2, EquipSlot.SUIT: 3, EquipSlot.OUTER: 4, EquipSlot.BELT: 5, 
		EquipSlot.BACK: 5, EquipSlot.SHOES: 5, EquipSlot.GLOVES: 5, EquipSlot.MASK: 4, EquipSlot.EYES: 4, 
		EquipSlot.HEAD: 4, EquipSlot.EARS: 4, EquipSlot.NECK: 4, EquipSlot.ID: 5}
}

# Thrust animation
var thrust_tween = null
var is_thrusting = false

func _ready():
	asset_manager = get_node_or_null("/root/CharacterAssetManager")
	
	create_equipment_containers()
	create_undergarment_container()
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

func create_undergarment_container():
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
		EquipSlot.ID: "IDContainer"
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
	
	# Create all limb sprites dynamically
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
	
	# Load textures automatically
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

# Automatically load limb textures from asset manager
func _load_limb_textures():
	if !asset_manager or is_loading_textures:
		return
	
	# Set guard to prevent recursion
	is_loading_textures = true
	
	# Safety timeout to prevent infinite loading state
	get_tree().create_timer(1.0).timeout.connect(func(): is_loading_textures = false)
	
	var race_sprites = asset_manager.get_race_sprites(race_index, character_sex)
	
	# Map asset manager keys to our sprite references
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
	
	# Apply textures from asset manager
	for sprite_key in sprite_mapping:
		var sprite = sprite_mapping[sprite_key]
		if race_sprites.has(sprite_key) and sprite:
			var texture_path = race_sprites[sprite_key]["texture"]
			if texture_path and asset_manager:
				var texture = asset_manager.get_resource(texture_path)
				if texture:
					sprite.texture = texture
	
	# Clear guard immediately after successful completion
	is_loading_textures = false

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
	
	current_direction = direction
	update_sprite_frames()
	update_sprite_z_ordering()
	update_clothing_frames()
	update_customization_frames()
	update_equipment_sprites()
	update_undergarment_frames()
	
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

func set_sex(sex: int):
	if character_sex == sex or is_loading_textures:
		return
	
	character_sex = sex
	_load_limb_textures()
	update_sprite_frames()
	
	if sex == 1 and facial_hair_sprite:
		facial_hair_sprite.visible = false
	
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		sync_sex.rpc(sex)

func set_race(race: int):
	if race_index == race or is_loading_textures:
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
			var frame_x = current_direction * sprite_frame_width
			sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
			
			if equipment_z_index_layers[current_direction].has(slot):
				sprite.z_index = equipment_z_index_layers[current_direction][slot]

func update_undergarment_frames():
	if underwear_sprite and underwear_sprite.visible and underwear_sprite.texture:
		var frame_x = current_direction * sprite_frame_width
		underwear_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
	
	if undershirt_sprite and undershirt_sprite.visible and undershirt_sprite.texture:
		var frame_x = current_direction * sprite_frame_width
		undershirt_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)

# Instant lying state with no tweening
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
				target_rotation = PI/2.0  # 90 degrees
				position_offset = Vector2(0, lying_offset.y * 2)
			Direction.WEST:
				target_rotation = -PI/2.0  # -90 degrees
				position_offset = Vector2(0, lying_offset.y * 2)
			Direction.SOUTH:
				target_rotation = PI/2.0  # Changed from PI (180°) to PI/2 (90°)
				position_offset = Vector2(lying_offset.x, lying_offset.y)
			Direction.NORTH:
				target_rotation = -PI/2.0  # Changed from 0.0 to -90 degrees
				position_offset = Vector2(-lying_offset.x, lying_offset.y)
	
	# Apply to all sprites instantly
	var all_sprites = []
	all_sprites.append_array(limb_sprites.values())
	all_sprites.append_array(equipment_sprites.values())
	
	if hair_sprite: all_sprites.append(hair_sprite)
	if facial_hair_sprite: all_sprites.append(facial_hair_sprite)
	if underwear_sprite: all_sprites.append(underwear_sprite)
	if undershirt_sprite: all_sprites.append(undershirt_sprite)
	
	for sprite in all_sprites:
		if sprite and sprite.visible:
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
	
	# Add limb sprites
	for limb_type in limb_sprites:
		var sprite = limb_sprites[limb_type]
		if sprite and sprite.visible and limbs_attached[limb_type]:
			sprites_to_animate.append(sprite)
			original_positions[sprite] = sprite.position
			original_colors[sprite] = sprite.modulate
	
	# Add equipment sprites
	for slot in equipment_sprites:
		var sprite = equipment_sprites[slot]
		if sprite and sprite.visible:
			sprites_to_animate.append(sprite)
			original_positions[sprite] = sprite.position
			original_colors[sprite] = sprite.modulate
	
	# Add hair sprites
	if hair_sprite and hair_sprite.visible:
		sprites_to_animate.append(hair_sprite)
		original_positions[hair_sprite] = hair_sprite.position
		original_colors[hair_sprite] = hair_sprite.modulate
	
	if facial_hair_sprite and facial_hair_sprite.visible:
		sprites_to_animate.append(facial_hair_sprite)
		original_positions[facial_hair_sprite] = facial_hair_sprite.position
		original_colors[facial_hair_sprite] = facial_hair_sprite.modulate
	
	# Add underwear sprites (THIS WAS MISSING!)
	if underwear_sprite and underwear_sprite.visible:
		sprites_to_animate.append(underwear_sprite)
		original_positions[underwear_sprite] = underwear_sprite.position
		original_colors[underwear_sprite] = underwear_sprite.modulate
	
	if undershirt_sprite and undershirt_sprite.visible:
		sprites_to_animate.append(undershirt_sprite)
		original_positions[undershirt_sprite] = undershirt_sprite.position
		original_colors[undershirt_sprite] = undershirt_sprite.modulate
	
	# Thrust forward
	for sprite in sprites_to_animate:
		var target_pos = original_positions[sprite] + thrust_offset
		thrust_tween.parallel().tween_property(sprite, "position", target_pos, thrust_duration)
	
	# Return to original position
	for sprite in sprites_to_animate:
		thrust_tween.parallel().tween_property(sprite, "position", original_positions[sprite], return_duration).set_delay(thrust_duration)
	
	thrust_tween.tween_callback(func(): is_thrusting = false).set_delay(thrust_duration + return_duration)

# Equipment management
func equip_item(item, slot: int) -> bool:
	if equipped_items.has(slot) and equipped_items[slot] != null:
		unequip_item(slot)
	
	equipped_items[slot] = item
	_create_equipment_visual(item, slot)
	emit_signal("item_equipped", item, slot)
	return true

func unequip_item(slot: int) -> bool:
	if !equipped_items.has(slot) or equipped_items[slot] == null:
		return false
	
	var item = equipped_items[slot]
	
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
	
	var texture = null
	
	if item.has_node("Icon") and item.get_node("Icon").texture:
		texture = item.get_node("Icon").texture
	elif "sprite" in item and item.sprite and item.sprite.texture:
		texture = item.sprite.texture
	elif item.has_method("get_texture"):
		texture = item.get_texture()
	
	if !texture:
		var image = Image.create(sprite_frame_width, sprite_frame_height, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.5, 0.5, 0.5, 0.5))
		texture = ImageTexture.create_from_image(image)
	
	equipment_sprite.texture = texture
	equipment_sprite.region_enabled = true
	
	var frame_x = current_direction * sprite_frame_width
	equipment_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
	equipment_sprite.z_index = equipment_z_index_layers[current_direction][slot]
	equipment_sprite.visible = true
	
	if is_lying:
		apply_instant_lying_rotation()

# Hair and facial hair
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
	
	var frame_x = current_direction * sprite_frame_width
	facial_hair_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
	
	if is_lying:
		apply_instant_lying_rotation()

# Underwear
func set_underwear(underwear_texture: Texture2D):
	if !underwear_sprite:
		create_undergarment_container()
	
	if !underwear_texture:
		underwear_sprite.visible = false
		return
	
	underwear_sprite.texture = underwear_texture
	underwear_sprite.region_enabled = true
	
	var frame_x = current_direction * sprite_frame_width
	underwear_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
	underwear_sprite.z_index = 3
	underwear_sprite.visible = true
	
	if is_lying:
		apply_instant_lying_rotation()

func set_undershirt(undershirt_texture: Texture2D):
	if !undershirt_sprite:
		create_undergarment_container()
	
	if !undershirt_texture:
		undershirt_sprite.visible = false
		return
	
	undershirt_sprite.texture = undershirt_texture
	undershirt_sprite.region_enabled = true
	
	var frame_x = current_direction * sprite_frame_width
	undershirt_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
	undershirt_sprite.z_index = 3
	undershirt_sprite.visible = true
	
	if is_lying:
		apply_instant_lying_rotation()

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
		_: return -1

# Damage system
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
	emit_signal("limb_detached", LimbType.keys()[limb_type])

func reattach_limb(limb_type: LimbType):
	if limb_type == LimbType.BODY or limbs_attached[limb_type]:
		return
	
	limb_sprites[limb_type].visible = true
	limbs_attached[limb_type] = true
	
	update_sprite_frames()
	update_sprite_z_ordering()
	
	if is_lying:
		apply_instant_lying_rotation()
	
	emit_signal("limb_attached", LimbType.keys()[limb_type])

# Character data application
func apply_character_data(data):
	if data == null or typeof(data) != TYPE_DICTIONARY or is_loading_textures:
		emit_signal("customization_applied", false)
		return
	
	# Set sex first as it affects other properties
	if "sex" in data and data.sex != null:
		set_sex(data.sex)
	
	# Set race
	if "race" in data and data.race != null:
		set_race(data.race)
	
	# Wait a frame to ensure sex/race changes are processed
	await get_tree().process_frame
	
	# Set underwear
	if "underwear_texture" in data and data.underwear_texture != null:
		var texture = null
		if asset_manager:
			texture = asset_manager.get_resource(data.underwear_texture)
		else:
			texture = load(data.underwear_texture)
		set_underwear(texture)
	
	# Set undershirt
	if "undershirt_texture" in data and data.undershirt_texture != null:
		var texture = null
		if asset_manager:
			texture = asset_manager.get_resource(data.undershirt_texture)
		else:
			texture = load(data.undershirt_texture)
		set_undershirt(texture)
	
	# Set hair
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
			texture = load(data.hair_texture)
		set_hair(texture, hair_color)
	
	# Set facial hair for males
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
			texture = load(data.facial_hair_texture)
		set_facial_hair(texture, facial_color)
	
	# Set clothing
	if "clothing_textures" in data and data.clothing_textures != null:
		if typeof(data.clothing_textures) == TYPE_DICTIONARY:
			set_clothing(data.clothing_textures)
	
	# Set direction
	if "direction" in data and data.direction != null and typeof(data.direction) == TYPE_INT:
		if data.direction >= 0 and data.direction <= 3:
			set_direction(data.direction)
	
	emit_signal("customization_applied", true)

# Utility functions
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
