extends Node2D
class_name HumanSpriteSystem

# ========== SIGNALS ==========
signal limb_attached(limb_name)
signal limb_detached(limb_name)
signal sprite_direction_changed(direction)
signal item_equipped(item, slot)
signal item_unequipped(item, slot)
signal interaction_feedback(type, intensity)
signal highlight_state_changed(is_highlighted)
signal customization_applied(success)

# ========== ENUMS ==========
enum LimbType {BODY, HEAD, LEFT_ARM, RIGHT_ARM, LEFT_HAND, RIGHT_HAND, GROIN, LEFT_LEG, RIGHT_LEG, LEFT_FOOT, RIGHT_FOOT}
enum Direction {SOUTH, NORTH, EAST, WEST}
enum EquipSlot {
	HEAD,       # Helmets, hats
	EYES,       # Glasses, goggles
	MASK,       # Face masks, respirators
	EARS,       # Headsets, earpieces
	NECK,       # Ties, necklaces
	OUTER,      # Space suits, armor
	UNIFORM,    # Jumpsuits, clothes
	SUIT,       # Jackets, lab coats
	GLOVES,     # Different types of gloves
	BELT,       # Tool belts, gun belts
	SHOES,      # Boots, slippers
	BACK,       # Backpacks, satchels
	ID,         # ID cards
	LEFT_HAND,  # Active hand slot
	RIGHT_HAND  # Secondary hand slot
}

# ========== CONSTANTS ==========
# Visual effect constants
const HIGHLIGHT_COLOR = Color(1.0, 0.8, 0.2, 0.5)
const INTERACTION_FLASH_DURATION = 0.2
const SELECTION_OUTLINE_COLOR = Color(0.3, 0.7, 1.0, 0.6)
const INTERACTION_FEEDBACK_COLORS = {
	"use": Color(0.2, 0.8, 0.2),
	"examine": Color(0.2, 0.6, 1.0),
	"attack": Color(1.0, 0.2, 0.2),
	"grab": Color(0.8, 0.6, 0.1),
	"disarm": Color(0.8, 0.2, 0.8),
	"default": Color(1.0, 1.0, 1.0)
}

# ========== EXPORTED VARIABLES ==========
# Sprite paths
@export var body_sprite_path: String = "res://Assets/Human/Body.png"
@export var head_sprite_path: String = "res://Assets/Human/Head.png"
@export var left_arm_sprite_path: String = "res://Assets/Human/Left_arm.png"
@export var right_arm_sprite_path: String = "res://Assets/Human/Right_arm.png"
@export var left_hand_sprite_path: String = "res://Assets/Human/Left_hand.png"
@export var right_hand_sprite_path: String = "res://Assets/Human/Right_hand.png"
@export var left_leg_sprite_path: String = "res://Assets/Human/Left_leg.png"
@export var right_leg_sprite_path: String = "res://Assets/Human/Right_leg.png"
@export var left_foot_sprite_path: String = "res://Assets/Human/Left_foot.png"
@export var right_foot_sprite_path: String = "res://Assets/Human/Right_foot.png"

# Sprite sheet configuration
@export var sprite_frames_horizontal: int = 4  # Number of frames horizontally in spritesheet
@export var sprite_frames_vertical: int = 1    # Number of frames vertically in spritesheet
@export var sprite_frame_width: int = 32       # Width of each frame
@export var sprite_frame_height: int = 32      # Height of each frame

# ========== NODE REFERENCES ==========
# Limb nodes
@onready var body_sprite = $Sprites/BodySprite
@onready var head_sprite = $Sprites/HeadSprite
@onready var left_arm_sprite = $Sprites/LeftArmSprite
@onready var right_arm_sprite = $Sprites/RightArmSprite
@onready var left_hand_sprite = $Sprites/LeftHandSprite
@onready var right_hand_sprite = $Sprites/RightHandSprite
@onready var left_leg_sprite = $Sprites/LeftLegSprite
@onready var right_leg_sprite = $Sprites/RightLegSprite
@onready var left_foot_sprite = $Sprites/LeftFootSprite
@onready var right_foot_sprite = $Sprites/RightFootSprite

# Equipment display nodes
@onready var equipment_container = $EquipmentContainer
@onready var held_items_container = $HeldItemsContainer
@onready var left_hand_item_position = $HeldItemsContainer/LeftHandPosition
@onready var right_hand_item_position = $HeldItemsContainer/RightHandPosition

# Undergarment container for underwear/undershirt
@onready var undergarment_container = get_node_or_null("UndergarmentContainer")

# Visual feedback nodes
@onready var selection_outline = $VisualEffects/SelectionOutline
@onready var interaction_flash = $VisualEffects/InteractionFlash
@onready var status_effect_container = $VisualEffects/StatusEffects
@onready var highlight_sprite = $VisualEffects/HighlightSprite

# ========== NETWORK STATE VARIABLES ==========
var is_network_controlled: bool = false
var network_authority_id: int = -1
var last_synced_direction: int = -1
var direction_changed_this_frame: bool = false
var pending_direction_change: int = -1

# ========== STATE VARIABLES ==========
# Reference to the entity this system belongs to
var Entity = null

# Current facing direction
var current_direction: int = Direction.SOUTH

# Dictionary to track if limbs are attached
var limbs_attached = {
	LimbType.BODY: true,
	LimbType.HEAD: true,
	LimbType.LEFT_ARM: true,
	LimbType.RIGHT_ARM: true,
	LimbType.LEFT_HAND: true,
	LimbType.RIGHT_HAND: true,
	LimbType.LEFT_LEG: true,
	LimbType.RIGHT_LEG: true,
	LimbType.LEFT_FOOT: true,
	LimbType.RIGHT_FOOT: true
}

# Dictionary to map LimbType to Sprite nodes
var limb_sprites = {}

# Dictionary to map LimbType to normal and specular map materials
var limb_materials = {}

# Equipment management
var equipped_items = {}  # Dictionary mapping slots to items
var visible_equipment_sprites = {}  # Dictionary tracking visible equipment sprites by slot

# CLOTHING LAYER SYSTEM - New dictionaries to track clothing sprites by type
var uniform_sprite: Sprite2D = null
var suit_sprite: Sprite2D = null
var outer_sprite: Sprite2D = null
var head_equipment_sprite: Sprite2D = null
var mask_sprite: Sprite2D = null
var eyes_sprite: Sprite2D = null
var ears_sprite: Sprite2D = null
var gloves_sprite: Sprite2D = null
var shoes_sprite: Sprite2D = null
var back_sprite: Sprite2D = null
var belt_sprite: Sprite2D = null
var neck_sprite: Sprite2D = null
var id_sprite: Sprite2D = null

# Underwear and undershirt sprites
var underwear_sprite: Sprite2D = null
var undershirt_sprite: Sprite2D = null

# Dictionary mapping equipment slots to their dedicated sprite nodes
var equipment_sprites = {}

# Z-index layers for body parts
var limb_z_index_layers = {
	Direction.SOUTH: {
		LimbType.BODY: 1,
		LimbType.HEAD: 2,
		LimbType.LEFT_ARM: 2,
		LimbType.RIGHT_ARM: 2,
		LimbType.LEFT_HAND: 2,
		LimbType.RIGHT_HAND: 2,
		LimbType.LEFT_LEG: 2,
		LimbType.RIGHT_LEG: 2,
		LimbType.LEFT_FOOT: 2,
		LimbType.RIGHT_FOOT: 2,
	},
	Direction.NORTH: {
		LimbType.BODY: 1,
		LimbType.HEAD: 2,
		LimbType.LEFT_ARM: 2,      # Arms behind when facing north
		LimbType.RIGHT_ARM: 2,
		LimbType.LEFT_HAND: 2,
		LimbType.RIGHT_HAND: 2,
		LimbType.LEFT_LEG: 2,
		LimbType.RIGHT_LEG: 2,
		LimbType.LEFT_FOOT: 2,
		LimbType.RIGHT_FOOT: 2,
	},
	Direction.EAST: {
		LimbType.BODY: 1,
		LimbType.HEAD: 2,
		LimbType.LEFT_ARM: 2,      # Left arm behind when facing east
		LimbType.RIGHT_ARM: 2,     # Right arm in front
		LimbType.LEFT_HAND: 2,
		LimbType.RIGHT_HAND: 2,
		LimbType.LEFT_LEG: 2,
		LimbType.RIGHT_LEG: 2,
		LimbType.LEFT_FOOT: 2,
		LimbType.RIGHT_FOOT: 2,
	},
	Direction.WEST: {
		LimbType.BODY: 1,
		LimbType.HEAD: 2,
		LimbType.LEFT_ARM: 2,      # Left arm in front when facing west
		LimbType.RIGHT_ARM: 2,     # Right arm behind
		LimbType.LEFT_HAND: 2,
		LimbType.RIGHT_HAND: 2,
		LimbType.LEFT_LEG: 2,
		LimbType.RIGHT_LEG: 2,
		LimbType.LEFT_FOOT: 2,
		LimbType.RIGHT_FOOT: 2,
	}
}

# Z-index layers for equipment
var equipment_z_index_layers = {
	Direction.SOUTH: {
		EquipSlot.UNIFORM: 2,    # Base layer under body
		EquipSlot.SUIT: 3,       # Over body, under arms
		EquipSlot.OUTER: 4,      # Over suit
		EquipSlot.BELT: 5,       # Over suit, on body
		EquipSlot.BACK: 5,       # Behind body
		EquipSlot.SHOES: 5,      # Over feet
		EquipSlot.GLOVES: 5,     # Over hands
		EquipSlot.MASK: 4,       # Over face, under eyes
		EquipSlot.EYES: 4,       # Over mask
		EquipSlot.HEAD: 4,       # Top layer on head
		EquipSlot.EARS: 4,      # On head, under hat
		EquipSlot.NECK: 4,       # On neck/chest
		EquipSlot.ID: 5          # Over suit/outer
	},
	Direction.NORTH: {
		EquipSlot.UNIFORM: 2,    # Base layer under body
		EquipSlot.SUIT: 3,       # Over body, under arms
		EquipSlot.OUTER: 4,      # Over suit
		EquipSlot.BELT: 5,       # Over suit, on body
		EquipSlot.BACK: 5,       # Behind body
		EquipSlot.SHOES: 5,      # Over feet
		EquipSlot.GLOVES: 5,     # Over hands
		EquipSlot.MASK: 4,       # Over face, under eyes
		EquipSlot.EYES: 4,       # Over mask
		EquipSlot.HEAD: 4,       # Top layer on head
		EquipSlot.EARS: 4,      # On head, under hat
		EquipSlot.NECK: 4,       # On neck/chest
		EquipSlot.ID: 5          # Over suit/outer
	},
	Direction.EAST: {
		EquipSlot.UNIFORM: 2,    # Base layer under body
		EquipSlot.SUIT: 3,       # Over body, under arms
		EquipSlot.OUTER: 4,      # Over suit
		EquipSlot.BELT: 5,       # Over suit, on body
		EquipSlot.BACK: 5,       # Behind body
		EquipSlot.SHOES: 5,      # Over feet
		EquipSlot.GLOVES: 5,     # Over hands
		EquipSlot.MASK: 4,       # Over face, under eyes
		EquipSlot.EYES: 4,       # Over mask
		EquipSlot.HEAD: 4,       # Top layer on head
		EquipSlot.EARS: 4,      # On head, under hat
		EquipSlot.NECK: 4,       # On neck/chest
		EquipSlot.ID: 5          # Over suit/outer
	},
	Direction.WEST: {
		EquipSlot.UNIFORM: 2,    # Base layer under body
		EquipSlot.SUIT: 3,       # Over body, under arms
		EquipSlot.OUTER: 4,      # Over suit
		EquipSlot.BELT: 5,       # Over suit, on body
		EquipSlot.BACK: 5,       # Behind body
		EquipSlot.SHOES: 5,      # Over feet
		EquipSlot.GLOVES: 5,     # Over hands
		EquipSlot.MASK: 4,       # Over face, under eyes
		EquipSlot.EYES: 4,       # Over mask
		EquipSlot.HEAD: 4,       # Top layer on head
		EquipSlot.EARS: 4,      # On head, under hat
		EquipSlot.NECK: 4,       # On neck/chest
		EquipSlot.ID: 5          # Over suit/outer
	}
}

# Clothing sprite layers
var clothing_sprites = {}
var character_sex: int = 0

# Interaction visual state tracking
var is_highlighted: bool = false
var highlight_intensity: float = 0.0
var is_selected: bool = false
var current_interaction_feedback: String = ""
var interaction_feedback_timer: float = 0.0

# Lying state tracking
var is_lying: bool = false
var lying_direction: int = Direction.SOUTH  # The direction character is facing while lying
var lying_animation_time: float = 0.4  # Time for lying down/getting up animation
var lying_offset: Vector2 = Vector2(0, 2)  # Slight offset when lying to look better
var active_lying_tween = null  # Track the active lying animation tween

# Status effect tracking
var active_status_effects = {}

# Customization sprites references
var hair_sprite: Sprite2D = null
var facial_hair_sprite: Sprite2D = null 

# Current active tweens for animations
var active_tweens = {}
var thrust_tween = null
var is_thrusting = false

# Race information
var race_index: int = 0
var race_variant: int = 0

# Asset manager reference for loading resources
var asset_manager = null

# Dictionary to store created shader materials
var shader_materials = {}

# ========== INITIALIZATION ==========
func _ready():
	print("HumanSpriteSystem: Initializing...")
	
	# Get asset manager reference
	asset_manager = get_node_or_null("/root/CharacterAssetManager")
	if !asset_manager:
		print("HumanSpriteSystem: WARNING - Could not find CharacterAssetManager")
	
	# Connect to world interaction system signals if available
	connect_to_click_system()
	
	# Setup equipment sprite containers
	create_equipment_containers()
	
	# Create undergarment container if not exists
	create_undergarment_container()
	
	# Initialize sprites
	setup_sprites()
	
	# Create visual effect nodes if they don't exist
	_setup_visual_effects()
	
	# Set reference in dictionary for easier access
	limb_sprites = {
		LimbType.BODY: body_sprite,
		LimbType.HEAD: head_sprite,
		LimbType.LEFT_ARM: left_arm_sprite,
		LimbType.RIGHT_ARM: right_arm_sprite,
		LimbType.LEFT_HAND: left_hand_sprite,
		LimbType.RIGHT_HAND: right_hand_sprite,
		LimbType.LEFT_LEG: left_leg_sprite,
		LimbType.RIGHT_LEG: right_leg_sprite,
		LimbType.LEFT_FOOT: left_foot_sprite,
		LimbType.RIGHT_FOOT: right_foot_sprite
	}
	
	# Get references to customization sprites if they exist
	hair_sprite = get_node_or_null("HairSprite")
	facial_hair_sprite = get_node_or_null("FacialHairSprite")
	
	# Set initial direction
	set_direction(Direction.SOUTH)
	
	# Check for network synchronizer in parent entity
	if get_parent() and get_parent().has_node("EntitySynchronizer"):
		var sync_node = get_parent().get_node("EntitySynchronizer")
		if sync_node and sync_node.has_method("is_local_player"):
			is_network_controlled = !sync_node.is_local_player
			print("HumanSpriteSystem: Network controlled = ", is_network_controlled)
	
	# Self-initialize if in preview mode (no Entity set)
	if get_parent() and Entity == null:
		print("HumanSpriteSystem: Self-initializing with parent entity")
		initialize(get_parent())
	
	print("HumanSpriteSystem: Initialization complete")
	
	# Add a short delay before applying saved customization
	_schedule_customization_check()
	
	# Connect to world interaction system signals if available
	connect_to_world_interaction_system()

# Create the undergarment container if it doesn't exist
func create_undergarment_container():
	if !has_node("UndergarmentContainer"):
		undergarment_container = Node2D.new()
		undergarment_container.name = "UndergarmentContainer"
		add_child(undergarment_container)
		
		# Create underwear sprite
		underwear_sprite = Sprite2D.new()
		underwear_sprite.name = "UnderwearSprite"
		underwear_sprite.centered = true
		underwear_sprite.region_enabled = true
		underwear_sprite.z_index = 3  # Between body and uniform
		underwear_sprite.visible = false
		undergarment_container.add_child(underwear_sprite)
		
		# Create undershirt sprite
		undershirt_sprite = Sprite2D.new()
		undershirt_sprite.name = "UndershirtSprite"
		undershirt_sprite.centered = true
		undershirt_sprite.region_enabled = true
		undershirt_sprite.z_index = 3 # Between body and uniform
		undershirt_sprite.visible = false
		undergarment_container.add_child(undershirt_sprite)
	else:
		undergarment_container = get_node("UndergarmentContainer")
		underwear_sprite = undergarment_container.get_node_or_null("UnderwearSprite")
		undershirt_sprite = undergarment_container.get_node_or_null("UndershirtSprite")
		
		# Create if missing
		if !underwear_sprite:
			underwear_sprite = Sprite2D.new()
			underwear_sprite.name = "UnderwearSprite"
			underwear_sprite.centered = true
			underwear_sprite.region_enabled = true
			underwear_sprite.z_index = 3
			underwear_sprite.visible = false
			undergarment_container.add_child(underwear_sprite)
			
		if !undershirt_sprite:
			undershirt_sprite = Sprite2D.new()
			undershirt_sprite.name = "UndershirtSprite"
			undershirt_sprite.centered = true
			undershirt_sprite.region_enabled = true
			undershirt_sprite.z_index = 3
			undershirt_sprite.visible = false
			undergarment_container.add_child(undershirt_sprite)

# Create dedicated containers for each equipment type
func create_equipment_containers():
	# Main equipment container
	if !has_node("EquipmentContainer"):
		equipment_container = Node2D.new()
		equipment_container.name = "EquipmentContainer"
		add_child(equipment_container)
	else:
		equipment_container = get_node("EquipmentContainer")
	
	# Held items container
	if !has_node("HeldItemsContainer"):
		held_items_container = Node2D.new()
		held_items_container.name = "HeldItemsContainer"
		add_child(held_items_container)
		
		# Create positions for left and right hands
		var left_pos = Node2D.new()
		left_pos.name = "LeftHandPosition"
		held_items_container.add_child(left_pos)
		left_hand_item_position = left_pos
		
		var right_pos = Node2D.new()
		right_pos.name = "RightHandPosition"
		held_items_container.add_child(right_pos)
		right_hand_item_position = right_pos
	else:
		held_items_container = get_node("HeldItemsContainer")
		left_hand_item_position = held_items_container.get_node_or_null("LeftHandPosition")
		right_hand_item_position = held_items_container.get_node_or_null("RightHandPosition")
		
		# Create if missing
		if !left_hand_item_position:
			left_hand_item_position = Node2D.new()
			left_hand_item_position.name = "LeftHandPosition"
			held_items_container.add_child(left_hand_item_position)
			
		if !right_hand_item_position:
			right_hand_item_position = Node2D.new()
			right_hand_item_position.name = "RightHandPosition"
			held_items_container.add_child(right_hand_item_position)
	
	# Create dedicated nodes for each equipment type
	create_equipment_sprite_nodes()

# Create dedicated sprite nodes for each equipment type
func create_equipment_sprite_nodes():
	# Clear existing equipment_sprites dictionary
	equipment_sprites.clear()
	
	# Create dedicated Node2D for each equipment type to group related sprites
	var equipment_types = {
		EquipSlot.UNIFORM: "UniformContainer",
		EquipSlot.SUIT: "SuitContainer",
		EquipSlot.OUTER: "OuterContainer", 
		EquipSlot.HEAD: "HeadContainer",
		EquipSlot.EYES: "EyesContainer",
		EquipSlot.MASK: "MaskContainer",
		EquipSlot.EARS: "EarsContainer",
		EquipSlot.GLOVES: "GlovesContainer",
		EquipSlot.SHOES: "ShoesContainer",
		EquipSlot.BELT: "BeltContainer",
		EquipSlot.BACK: "BackContainer",
		EquipSlot.NECK: "NeckContainer",
		EquipSlot.ID: "IDContainer"
	}
	
	# Create containers and sprite nodes for each equipment type
	for slot in equipment_types:
		var container_name = equipment_types[slot]
		var container = equipment_container.get_node_or_null(container_name)
		
		# Create container if it doesn't exist
		if !container:
			container = Node2D.new()
			container.name = container_name
			equipment_container.add_child(container)
		
		# Create sprite for this equipment type
		var sprite_name = container_name.replace("Container", "Sprite")
		var sprite = container.get_node_or_null(sprite_name)
		
		if !sprite:
			sprite = Sprite2D.new()
			sprite.name = sprite_name
			sprite.centered = true
			sprite.region_enabled = true
			sprite.visible = false  # Initially not visible
			container.add_child(sprite)
		
		# Store reference in our tracking dictionary
		equipment_sprites[slot] = sprite
		
		# Set z-index based on our layering system (for South direction initially)
		sprite.z_index = equipment_z_index_layers[Direction.SOUTH][slot]
	
	# Set direct references for commonly accessed sprites
	uniform_sprite = equipment_sprites[EquipSlot.UNIFORM]
	suit_sprite = equipment_sprites[EquipSlot.SUIT]
	outer_sprite = equipment_sprites[EquipSlot.OUTER]
	head_equipment_sprite = equipment_sprites[EquipSlot.HEAD]
	mask_sprite = equipment_sprites[EquipSlot.MASK]
	eyes_sprite = equipment_sprites[EquipSlot.EYES]
	gloves_sprite = equipment_sprites[EquipSlot.GLOVES]
	shoes_sprite = equipment_sprites[EquipSlot.SHOES]
	back_sprite = equipment_sprites[EquipSlot.BACK]
	belt_sprite = equipment_sprites[EquipSlot.BELT]

# Set up visual effects nodes
func _setup_visual_effects():
	# Check if visual effects container exists
	if !has_node("VisualEffects"):
		var effects_container = Node2D.new()
		effects_container.name = "VisualEffects"
		add_child(effects_container)
		
		# Create selection outline
		if !effects_container.has_node("SelectionOutline"):
			var outline = Sprite2D.new()
			outline.name = "SelectionOutline"
			outline.z_index = -1  # Behind everything
			outline.visible = false
			
			# Create basic outline texture if needed
			var outline_texture = create_outline_texture()
			outline.texture = outline_texture
			
			effects_container.add_child(outline)
			selection_outline = outline
		
		# Create interaction flash
		if !effects_container.has_node("InteractionFlash"):
			var flash = Sprite2D.new()
			flash.name = "InteractionFlash"
			flash.z_index = 10  # In front of everything
			flash.visible = false
			
			# Create basic flash texture
			var flash_texture = create_circle_texture(Color(1, 1, 1, 0.7))
			flash.texture = flash_texture
			
			effects_container.add_child(flash)
			interaction_flash = flash
		
		# Create highlight sprite
		if !effects_container.has_node("HighlightSprite"):
			var highlight = Sprite2D.new()
			highlight.name = "HighlightSprite"
			highlight.z_index = -1  # Behind everything
			highlight.modulate = HIGHLIGHT_COLOR
			highlight.visible = false
			
			# Create basic highlight texture
			var highlight_texture = create_circle_texture(Color(1, 1, 1, 0.3))
			highlight.texture = highlight_texture
			
			effects_container.add_child(highlight)
			highlight_sprite = highlight
		
		# Create status effects container
		if !effects_container.has_node("StatusEffects"):
			var status_container = Node2D.new()
			status_container.name = "StatusEffects"
			effects_container.add_child(status_container)
			status_effect_container = status_container
	else:
		var effects_container = get_node("VisualEffects")
		selection_outline = effects_container.get_node_or_null("SelectionOutline")
		interaction_flash = effects_container.get_node_or_null("InteractionFlash")
		highlight_sprite = effects_container.get_node_or_null("HighlightSprite")
		status_effect_container = effects_container.get_node_or_null("StatusEffects")

# Connect to world interaction system
func connect_to_world_interaction_system():
	var world = get_node_or_null("/root/World")
	if world:
		var interaction_system = world.get_node_or_null("WorldInteractionSystem")
		if interaction_system:
			# Connect to entity_clicked if not already connected
			if interaction_system.has_signal("entity_clicked") and !interaction_system.is_connected("entity_clicked", Callable(self, "_on_entity_clicked")):
				interaction_system.entity_clicked.connect(_on_entity_clicked)
			
			print("HumanSpriteSystem: Connected to WorldInteractionSystem")

# Create a simple outline texture
func create_outline_texture() -> Texture2D:
	var image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))  # Start transparent
	
	# Draw outline circle
	for x in range(64):
		for y in range(64):
			var dist = Vector2(x - 32, y - 32).length()
			if dist >= 30 and dist <= 32:  # 2-pixel wide outline
				image.set_pixel(x, y, SELECTION_OUTLINE_COLOR)
	
	return ImageTexture.create_from_image(image)

# Create a simple circle texture
func create_circle_texture(color: Color) -> Texture2D:
	var image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))  # Start transparent
	
	# Draw filled circle with gradient
	for x in range(64):
		for y in range(64):
			var dist = Vector2(x - 32, y - 32).length()
			if dist <= 32:
				# Create gradient from center to edge
				var alpha = 1.0 - (dist / 32.0)
				var pixel_color = Color(color.r, color.g, color.b, color.a * alpha)
				image.set_pixel(x, y, pixel_color)
	
	return ImageTexture.create_from_image(image)

# ========== SHADER MATERIAL MANAGEMENT ==========

# Create a shader material with normal and specular maps
func create_mapped_material(normal_map_path: String = "", specular_map_path: String = "") -> ShaderMaterial:
	# Create a new material or reuse existing one with same maps
	var cache_key = str(normal_map_path, "_", specular_map_path)
	if shader_materials.has(cache_key):
		return shader_materials[cache_key]
	
	# Create a new shader material
	var material = ShaderMaterial.new()
	
	# Define the shader to use normal and specular maps
	var shader_code = """
	shader_type canvas_item;
	
	uniform sampler2D normal_map : hint_normal;
	uniform sampler2D specular_map : hint_default_white;
	uniform float specular_strength : hint_range(0.0, 1.0) = 0.5;
	uniform float normal_strength : hint_range(0.0, 1.0) = 0.5;
	
	void fragment() {
		vec4 color = texture(TEXTURE, UV);
		
		// Sample normal map if available
		vec3 normal = vec3(0.5, 0.5, 1.0);
		if (normal_strength > 0.0) {
			normal = texture(normal_map, UV).rgb;
			normal = normal * 2.0 - 1.0;
			normal.z = normal_strength;
			normal = normalize(normal);
		}
		
		// Sample specular map if available
		float specular = specular_strength;
		if (specular_strength > 0.0) {
			specular = texture(specular_map, UV).r * specular_strength;
		}
		
		// Basic lighting calculation (directional light from top-right)
		vec3 light_dir = normalize(vec3(1.0, 1.0, 0.5));
		float ndotl = max(dot(normal, light_dir), 0.0);
		
		// Combine diffuse and specular
		vec3 diffuse = color.rgb * (0.5 + 0.5 * ndotl);
		vec3 specular_color = vec3(1.0) * pow(ndotl, 8.0) * specular;
		
		// Final color
		COLOR = vec4(diffuse + specular_color, color.a);
	}
	"""
	
	var shader = Shader.new()
	shader.code = shader_code
	material.shader = shader
	
	# Load and assign normal map if available
	if normal_map_path and !normal_map_path.is_empty() and ResourceLoader.exists(normal_map_path):
		var normal_texture = load(normal_map_path)
		material.set_shader_parameter("normal_map", normal_texture)
		material.set_shader_parameter("normal_strength", 0.5)  # Moderate normal map strength
	else:
		# Create a default normal map (flat surface)
		var default_normal = Image.create(4, 4, false, Image.FORMAT_RGB8)
		default_normal.fill(Color(0.5, 0.5, 1.0))  # Default normal pointing out
		var default_normal_texture = ImageTexture.create_from_image(default_normal)
		material.set_shader_parameter("normal_map", default_normal_texture)
		material.set_shader_parameter("normal_strength", 0.0)  # Disable normal mapping
	
	# Load and assign specular map if available
	if specular_map_path and !specular_map_path.is_empty() and ResourceLoader.exists(specular_map_path):
		var specular_texture = load(specular_map_path)
		material.set_shader_parameter("specular_map", specular_texture)
		material.set_shader_parameter("specular_strength", 0.5)  # Moderate specular strength
	else:
		# Create a default specular map (uniform)
		var default_specular = Image.create(4, 4, false, Image.FORMAT_L8)
		default_specular.fill(Color(0.2, 0.2, 0.2))  # Low specular by default
		var default_specular_texture = ImageTexture.create_from_image(default_specular)
		material.set_shader_parameter("specular_map", default_specular_texture)
		material.set_shader_parameter("specular_strength", 0.0)  # Disable specular
	
	# Cache the created material
	shader_materials[cache_key] = material
	return material

# Apply material with maps to a sprite
func apply_mapped_material(sprite: Sprite2D, normal_map_path: String = "", specular_map_path: String = ""):
	if !sprite:
		return
		
	# Skip if no maps provided
	if normal_map_path.is_empty() and specular_map_path.is_empty():
		sprite.material = null
		return
		
	# Create and apply the material
	var material = create_mapped_material(normal_map_path, specular_map_path)
	sprite.material = material

# ========== SPRITE SETUP ==========
# Load sprites and set up frames
func setup_sprites():
	print("HumanSpriteSystem: Setting up sprites")
	
	# First check if Sprites container exists
	if !has_node("Sprites"):
		var sprites_container = Node2D.new()
		sprites_container.name = "Sprites"
		add_child(sprites_container)
		
		# Create all necessary sprite nodes
		_create_limb_sprite(sprites_container, "BodySprite", LimbType.BODY)
		_create_limb_sprite(sprites_container, "HeadSprite", LimbType.HEAD)
		_create_limb_sprite(sprites_container, "LeftArmSprite", LimbType.LEFT_ARM)
		_create_limb_sprite(sprites_container, "RightArmSprite", LimbType.RIGHT_ARM)
		_create_limb_sprite(sprites_container, "LeftHandSprite", LimbType.LEFT_HAND)
		_create_limb_sprite(sprites_container, "RightHandSprite", LimbType.RIGHT_HAND)
		_create_limb_sprite(sprites_container, "LeftLegSprite", LimbType.LEFT_LEG)
		_create_limb_sprite(sprites_container, "RightLegSprite", LimbType.RIGHT_LEG)
		_create_limb_sprite(sprites_container, "LeftFootSprite", LimbType.LEFT_FOOT)
		_create_limb_sprite(sprites_container, "RightFootSprite", LimbType.RIGHT_FOOT)
		
		# Get references to the newly created nodes
		body_sprite = sprites_container.get_node("BodySprite")
		head_sprite = sprites_container.get_node("HeadSprite")
		left_arm_sprite = sprites_container.get_node("LeftArmSprite")
		right_arm_sprite = sprites_container.get_node("RightArmSprite")
		left_hand_sprite = sprites_container.get_node("LeftHandSprite")
		right_hand_sprite = sprites_container.get_node("RightHandSprite")
		left_leg_sprite = sprites_container.get_node("LeftLegSprite")
		right_leg_sprite = sprites_container.get_node("RightLegSprite")
		left_foot_sprite = sprites_container.get_node("LeftFootSprite")
		right_foot_sprite = sprites_container.get_node("RightFootSprite")
	else:
		var sprites_container = get_node("Sprites")
		
		# Get references to existing nodes
		body_sprite = sprites_container.get_node_or_null("BodySprite")
		head_sprite = sprites_container.get_node_or_null("HeadSprite")
		left_arm_sprite = sprites_container.get_node_or_null("LeftArmSprite")
		right_arm_sprite = sprites_container.get_node_or_null("RightArmSprite")
		left_hand_sprite = sprites_container.get_node_or_null("LeftHandSprite")
		right_hand_sprite = sprites_container.get_node_or_null("RightHandSprite")
		left_leg_sprite = sprites_container.get_node_or_null("LeftLegSprite")
		right_leg_sprite = sprites_container.get_node_or_null("RightLegSprite")
		left_foot_sprite = sprites_container.get_node_or_null("LeftFootSprite")
		right_foot_sprite = sprites_container.get_node_or_null("RightFootSprite")
		
		# Create any missing nodes
		if !body_sprite:
			body_sprite = _create_limb_sprite(sprites_container, "BodySprite", LimbType.BODY)
		if !head_sprite:
			head_sprite = _create_limb_sprite(sprites_container, "HeadSprite", LimbType.HEAD)
		if !left_arm_sprite:
			left_arm_sprite = _create_limb_sprite(sprites_container, "LeftArmSprite", LimbType.LEFT_ARM)
		if !right_arm_sprite:
			right_arm_sprite = _create_limb_sprite(sprites_container, "RightArmSprite", LimbType.RIGHT_ARM)
		if !left_hand_sprite:
			left_hand_sprite = _create_limb_sprite(sprites_container, "LeftHandSprite", LimbType.LEFT_HAND)
		if !right_hand_sprite:
			right_hand_sprite = _create_limb_sprite(sprites_container, "RightHandSprite", LimbType.RIGHT_HAND)
		if !left_leg_sprite:
			left_leg_sprite = _create_limb_sprite(sprites_container, "LeftLegSprite", LimbType.LEFT_LEG)
		if !right_leg_sprite:
			right_leg_sprite = _create_limb_sprite(sprites_container, "RightLegSprite", LimbType.RIGHT_LEG)
		if !left_foot_sprite:
			left_foot_sprite = _create_limb_sprite(sprites_container, "LeftFootSprite", LimbType.LEFT_FOOT)
		if !right_foot_sprite:
			right_foot_sprite = _create_limb_sprite(sprites_container, "RightFootSprite", LimbType.RIGHT_FOOT)
	
	# Load textures for all limb sprites
	var textures = {}
	
	# Load each texture with error handling
	for limb_type in [LimbType.BODY, LimbType.HEAD, LimbType.LEFT_ARM, LimbType.RIGHT_ARM, 
					   LimbType.LEFT_HAND, LimbType.RIGHT_HAND, LimbType.LEFT_LEG, 
					   LimbType.RIGHT_LEG, LimbType.LEFT_FOOT, LimbType.RIGHT_FOOT]:
		var path = ""
		
		# Get the appropriate path for each limb type
		match limb_type:
			LimbType.BODY: path = body_sprite_path
			LimbType.HEAD: path = head_sprite_path
			LimbType.LEFT_ARM: path = left_arm_sprite_path
			LimbType.RIGHT_ARM: path = right_arm_sprite_path
			LimbType.LEFT_HAND: path = left_hand_sprite_path
			LimbType.RIGHT_HAND: path = right_hand_sprite_path
			LimbType.LEFT_LEG: path = left_leg_sprite_path
			LimbType.RIGHT_LEG: path = right_leg_sprite_path
			LimbType.LEFT_FOOT: path = left_foot_sprite_path
			LimbType.RIGHT_FOOT: path = right_foot_sprite_path
		
		# Try to load the texture
		if path and FileAccess.file_exists(path):
			textures[limb_type] = load(path)
			print("HumanSpriteSystem: Loaded texture for limb: ", LimbType.keys()[limb_type])
		else:
			print("HumanSpriteSystem: ERROR - Failed to load texture for limb: ", LimbType.keys()[limb_type], " - Path: ", path)
			textures[limb_type] = null
	
	# Assign textures to sprites
	if textures[LimbType.BODY]: body_sprite.texture = textures[LimbType.BODY]
	if textures[LimbType.HEAD]: head_sprite.texture = textures[LimbType.HEAD]
	if textures[LimbType.LEFT_ARM]: left_arm_sprite.texture = textures[LimbType.LEFT_ARM]
	if textures[LimbType.RIGHT_ARM]: right_arm_sprite.texture = textures[LimbType.RIGHT_ARM]
	if textures[LimbType.LEFT_HAND]: left_hand_sprite.texture = textures[LimbType.LEFT_HAND]
	if textures[LimbType.RIGHT_HAND]: right_hand_sprite.texture = textures[LimbType.RIGHT_HAND]
	if textures[LimbType.LEFT_LEG]: left_leg_sprite.texture = textures[LimbType.LEFT_LEG]
	if textures[LimbType.RIGHT_LEG]: right_leg_sprite.texture = textures[LimbType.RIGHT_LEG]
	if textures[LimbType.LEFT_FOOT]: left_foot_sprite.texture = textures[LimbType.LEFT_FOOT]
	if textures[LimbType.RIGHT_FOOT]: right_foot_sprite.texture = textures[LimbType.RIGHT_FOOT]
	
	# Set up sprite regions and positions
	_setup_sprite_properties()
	
	# Apply normal and specular maps if available
	if asset_manager:
		_apply_maps_to_limbs()
	
	print("HumanSpriteSystem: Sprites setup complete")

# Apply normal and specular maps to limb sprites
func _apply_maps_to_limbs():
	if !asset_manager:
		return
		
	var normal_maps = asset_manager.normal_maps
	var specular_maps = asset_manager.specular_maps
	
	# Get base part names
	var base_part_names = {
		LimbType.BODY: "Body",
		LimbType.HEAD: "Head",
		LimbType.LEFT_ARM: "Left_arm",
		LimbType.RIGHT_ARM: "Right_arm",
		LimbType.LEFT_HAND: "Left_hand",
		LimbType.RIGHT_HAND: "Right_hand",
		LimbType.LEFT_LEG: "Left_leg",
		LimbType.RIGHT_LEG: "Right_leg",
		LimbType.LEFT_FOOT: "Left_foot",
		LimbType.RIGHT_FOOT: "Right_foot"
	}
	
	# Apply maps to each limb
	for limb_type in limb_sprites:
		var sprite = limb_sprites[limb_type]
		if sprite and sprite.texture:
			var base_name = base_part_names[limb_type]
			var normal_map_path = ""
			var specular_map_path = ""
			
			# Check for normal map
			if normal_maps.has(base_name):
				normal_map_path = normal_maps[base_name]
				print("HumanSpriteSystem: Found normal map for ", base_name, ": ", normal_map_path)
			
			# Check for specular map
			if specular_maps.has(base_name):
				specular_map_path = specular_maps[base_name]
				print("HumanSpriteSystem: Found specular map for ", base_name, ": ", specular_map_path)
			
			# Apply material if any maps found
			if !normal_map_path.is_empty() or !specular_map_path.is_empty():
				apply_mapped_material(sprite, normal_map_path, specular_map_path)
				print("HumanSpriteSystem: Applied mapped material to ", base_name)

# Helper function to create a limb sprite
func _create_limb_sprite(parent: Node, sprite_name: String, limb_type: int) -> Sprite2D:
	var sprite = Sprite2D.new()
	sprite.name = sprite_name
	sprite.centered = true
	sprite.region_enabled = true
	
	# Set initial z-index based on limb type and south direction
	sprite.z_index = limb_z_index_layers[Direction.SOUTH][limb_type]
	
	parent.add_child(sprite)
	return sprite

# Set up common properties for all sprites
func _setup_sprite_properties():
	# List of all limb sprites
	var all_sprites = [
		body_sprite, head_sprite, 
		left_arm_sprite, right_arm_sprite,
		left_hand_sprite, right_hand_sprite,
		left_leg_sprite, right_leg_sprite,
		left_foot_sprite, right_foot_sprite
	]
	
	# Set up common properties for all sprites
	for sprite in all_sprites:
		if sprite:
			sprite.region_enabled = true
			sprite.region_rect = Rect2(0, 0, sprite_frame_width, sprite_frame_height)
			sprite.position = Vector2.ZERO
			sprite.centered = true

# Link this system to its entity
func initialize(entity_reference):
	Entity = entity_reference
	
	# Connect relevant signals from entity
	if Entity and Entity.has_signal("body_part_damaged"):
		if !Entity.is_connected("body_part_damaged", Callable(self, "_on_body_part_damaged")):
			Entity.body_part_damaged.connect(_on_body_part_damaged)
	
	# Connect to movement controller if available
	var grid_controller = Entity.get_node_or_null("GridMovementController")
	if grid_controller:
		if grid_controller.has_signal("state_changed") and !grid_controller.is_connected("state_changed", Callable(self, "_on_movement_state_changed")):
			grid_controller.state_changed.connect(_on_movement_state_changed)
	
	# Connect to entity integration if available
	if Entity:
		if Entity.has_signal("interaction_started") and !Entity.is_connected("interaction_started", Callable(self, "_on_interaction_started")):
			Entity.interaction_started.connect(_on_interaction_started)
		
		if Entity.has_signal("interaction_completed") and !Entity.is_connected("interaction_completed", Callable(self, "_on_interaction_completed")):
			Entity.interaction_completed.connect(_on_interaction_completed)

# ========== UNDERWEAR & UNDERSHIRT METHODS ==========

# Set underwear texture
func set_underwear(underwear_texture_path: String, normal_map_path: String = "", specular_map_path: String = ""):
	print("HumanSpriteSystem: Setting underwear: ", underwear_texture_path)
	
	# Skip if no container or sprite
	if !underwear_sprite:
		create_undergarment_container()
	
	# Handle null or empty texture path
	if underwear_texture_path == null or underwear_texture_path.is_empty() or underwear_texture_path == "null":
		# Hide underwear sprite
		underwear_sprite.visible = false
		print("HumanSpriteSystem: No underwear texture provided, hiding sprite")
		return
	
	# Make sure the file exists
	if !ResourceLoader.exists(underwear_texture_path):
		push_error("HumanSpriteSystem: Underwear texture file not found: " + underwear_texture_path)
		underwear_sprite.visible = false
		return
	
	# Set texture
	if asset_manager:
		underwear_sprite.texture = asset_manager.get_resource(underwear_texture_path)
	else:
		underwear_sprite.texture = load(underwear_texture_path)
	
	underwear_sprite.region_enabled = true
	
	# Update region based on current direction
	var frame_x = current_direction * sprite_frame_width
	underwear_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
	
	# Set z-index (between body and uniform)
	underwear_sprite.z_index = 3
	
	# Apply material with maps if provided
	apply_mapped_material(underwear_sprite, normal_map_path, specular_map_path)
	
	# Make visible
	underwear_sprite.visible = true
	
	# Apply lying rotation if needed
	if is_lying:
		apply_sprite_rotation_for_lying(underwear_sprite)
	
	print("HumanSpriteSystem: Underwear setup successful")

# Set undershirt texture
func set_undershirt(undershirt_texture_path: String, normal_map_path: String = "", specular_map_path: String = ""):
	print("HumanSpriteSystem: Setting undershirt: ", undershirt_texture_path)
	
	# Skip if no container or sprite
	if !undershirt_sprite:
		create_undergarment_container()
	
	# Handle null or empty texture path
	if undershirt_texture_path == null or undershirt_texture_path.is_empty() or undershirt_texture_path == "null":
		# Hide undershirt sprite
		undershirt_sprite.visible = false
		print("HumanSpriteSystem: No undershirt texture provided, hiding sprite")
		return
	
	# Make sure the file exists
	if !ResourceLoader.exists(undershirt_texture_path):
		push_error("HumanSpriteSystem: Undershirt texture file not found: " + undershirt_texture_path)
		undershirt_sprite.visible = false
		return
	
	# Set texture
	if asset_manager:
		undershirt_sprite.texture = asset_manager.get_resource(undershirt_texture_path)
	else:
		undershirt_sprite.texture = load(undershirt_texture_path)
		
	undershirt_sprite.region_enabled = true
	
	# Update region based on current direction
	var frame_x = current_direction * sprite_frame_width
	undershirt_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
	
	# Set z-index (between body and uniform)
	undershirt_sprite.z_index = 3
	
	# Apply material with maps if provided
	apply_mapped_material(undershirt_sprite, normal_map_path, specular_map_path)
	
	# Make visible
	undershirt_sprite.visible = true
	
	# Apply lying rotation if needed
	if is_lying:
		apply_sprite_rotation_for_lying(undershirt_sprite)
	
	print("HumanSpriteSystem: Undershirt setup successful")

# ========== CHARACTER DATA METHODS ==========

# Apply complete character data from character creation with improved null checks
func apply_character_data(data):
	print("HumanSpriteSystem: Applying character data")
	
	# First verify that data is not null
	if data == null:
		print("HumanSpriteSystem: ERROR - Null data provided to apply_character_data")
		emit_signal("customization_applied", false)
		return
		
	# Verify data is a dictionary
	if typeof(data) != TYPE_DICTIONARY:
		print("HumanSpriteSystem: ERROR - Data is not a dictionary in apply_character_data")
		emit_signal("customization_applied", false)
		return
	
	# Apply sex first as it affects other properties
	if "sex" in data and data.sex != null:
		set_sex(data.sex)
	else:
		set_sex(0)  # Default to male if not specified
	
	# Apply race if available
	if "race" in data and data.race != null:
		set_race(data.race)
	
	# Apply hair style and color with map support
	if "hair_texture" in data and data.hair_texture != null and "hair_color" in data:
		var hair_color = data.hair_color
		if typeof(hair_color) != TYPE_COLOR:
			if typeof(hair_color) == TYPE_DICTIONARY and "r" in hair_color and "g" in hair_color and "b" in hair_color:
				hair_color = Color(hair_color.r, hair_color.g, hair_color.b, hair_color.a if "a" in hair_color else 1.0)
			else:
				hair_color = Color(0.3, 0.2, 0.1)
				print("HumanSpriteSystem: WARNING - Invalid hair color, using default")
		
		# Look for normal and specular maps
		var normal_map = data.get("hair_normal_map", "")
		var specular_map = data.get("hair_specular_map", "")
		
		# Get base name for map lookup if not provided explicitly
		if normal_map.is_empty() or specular_map.is_empty() and asset_manager:
			var base_name = data.hair_texture.get_file().get_basename()
			
			if normal_map.is_empty() and asset_manager.normal_maps.has(base_name):
				normal_map = asset_manager.normal_maps[base_name]
			
			if specular_map.is_empty() and asset_manager.specular_maps.has(base_name):
				specular_map = asset_manager.specular_maps[base_name]
		
		set_hair(data.hair_texture, hair_color, normal_map, specular_map)
	
	# Apply facial hair for males with map support
	if character_sex == 0 and "facial_hair_texture" in data and data.facial_hair_texture != null and "facial_hair_color" in data:
		var facial_color = data.facial_hair_color
		if typeof(facial_color) != TYPE_COLOR:
			if typeof(facial_color) == TYPE_DICTIONARY and "r" in facial_color and "g" in facial_color and "b" in facial_color:
				facial_color = Color(facial_color.r, facial_color.g, facial_color.b, facial_color.a if "a" in facial_color else 1.0)
			else:
				facial_color = Color(0.3, 0.2, 0.1)
				print("HumanSpriteSystem: WARNING - Invalid facial hair color, using default")
		
		# Look for normal and specular maps
		var normal_map = data.get("facial_hair_normal_map", "")
		var specular_map = data.get("facial_hair_specular_map", "")
		
		# Get base name for map lookup if not provided explicitly
		if (normal_map.is_empty() or specular_map.is_empty()) and asset_manager:
			var base_name = data.facial_hair_texture.get_file().get_basename()
			
			if normal_map.is_empty() and asset_manager.normal_maps.has(base_name):
				normal_map = asset_manager.normal_maps[base_name]
			
			if specular_map.is_empty() and asset_manager.specular_maps.has(base_name):
				specular_map = asset_manager.specular_maps[base_name]
		
		set_facial_hair(data.facial_hair_texture, facial_color, normal_map, specular_map)
	
	# Apply clothing if available
	if "clothing_textures" in data and data.clothing_textures != null:
		if typeof(data.clothing_textures) == TYPE_DICTIONARY:
			var clothing_normal_maps = data.get("clothing_normal_maps", {})
			var clothing_specular_maps = data.get("clothing_specular_maps", {})
			set_clothing(data.clothing_textures, clothing_normal_maps, clothing_specular_maps)
		else:
			print("HumanSpriteSystem: WARNING - clothing_textures is not a dictionary, skipping")
	
	# Apply underwear and undershirt with map support
	if "underwear_texture" in data and data.underwear_texture != null:
		var underwear_normal_map = data.get("underwear_normal_map", "")
		var underwear_specular_map = data.get("underwear_specular_map", "")
		set_underwear(data.underwear_texture, underwear_normal_map, underwear_specular_map)
	
	if "undershirt_texture" in data and data.undershirt_texture != null:
		var undershirt_normal_map = data.get("undershirt_normal_map", "")
		var undershirt_specular_map = data.get("undershirt_specular_map", "")
		set_undershirt(data.undershirt_texture, undershirt_normal_map, undershirt_specular_map)
	
	# Apply direction if specified
	if "direction" in data and data.direction != null and typeof(data.direction) == TYPE_INT:
		if data.direction >= 0 and data.direction <= 3:
			set_direction(data.direction)
	
	# Apply any body modifiers or colors for race
	if has_method("_apply_race_modifiers"):
		_apply_race_modifiers()
	
	# Safely call update methods
	if has_method("update_customization_frames"):
		update_customization_frames()
	
	if has_method("update_equipment_sprites"):
		update_equipment_sprites()
	
	if has_method("update_undergarment_frames"):
		update_undergarment_frames()
	
	print("HumanSpriteSystem: Character data applied successfully")
	emit_signal("customization_applied", true)

func apply_customization(data):
	print("HumanSpriteSystem: apply_customization called (alias for apply_character_data)")
	if data == null:
		print("HumanSpriteSystem: ERROR - Null data provided to apply_customization")
		return false
		
	return apply_character_data(data)

# Apply race-specific modifiers to appearance
func _apply_race_modifiers():
	# Default to no modifiers
	for sprite in limb_sprites.values():
		sprite.modulate = Color(1, 1, 1, 1)
	
	# Apply specific modifiers based on race
	match race_index:
		0:  # Human - no modifiers
			pass
		1:  # Synthetic or other race
			# Apply a subtle bluish tint for synthetic race
			for sprite in limb_sprites.values():
				sprite.modulate = Color(0.9, 0.95, 1.0, 1.0)
		_:  # Other races
			# Check if race name contains variant info
			if race_variant > 0:
				# Apply different color tints based on variant
				match race_variant:
					1:  # Variant 1 - subtle green tint
						for sprite in limb_sprites.values():
							sprite.modulate = Color(0.9, 1.0, 0.9, 1.0)
					2:  # Variant 2 - subtle tan/gold tint
						for sprite in limb_sprites.values():
							sprite.modulate = Color(1.0, 0.95, 0.8, 1.0)
					3:  # Variant 3 - subtle purple tint
						for sprite in limb_sprites.values():
							sprite.modulate = Color(0.95, 0.9, 1.0, 1.0)
					_:  # Default
						pass

# Set race
func set_race(race_idx: int):
	print("HumanSpriteSystem: Setting race to index: ", race_idx)
	race_index = race_idx
	
	# Extract variant number if present
	var race_name = "Human"  # Default
	var asset_manager = get_node_or_null("/root/CharacterAssetManager")
	
	if asset_manager and race_idx < asset_manager.races.size():
		race_name = asset_manager.races[race_idx]
	
	# Check if race name contains variant info (e.g., "Human_2")
	if "_" in race_name:
		var parts = race_name.split("_")
		if parts.size() > 1 and parts[1].is_valid_int():
			race_variant = int(parts[1])
			print("HumanSpriteSystem: Race variant detected: ", race_variant)
	else:
		race_variant = 0
	
	# Update sprite paths based on race and sex
	_update_sprite_paths_for_race()
	
	# Reload sprites with new paths
	_reload_sprites_for_race()
	
	# Apply race-specific appearance modifiers
	_apply_race_modifiers()
	
	print("HumanSpriteSystem: Race setup complete")

# Update sprite paths based on race and sex
func _update_sprite_paths_for_race():
	print("HumanSpriteSystem: Updating sprite paths for race: ", race_index, " and sex: ", character_sex)
	
	# Try to get race sprites from AssetManager
	var asset_manager = get_node_or_null("/root/CharacterAssetManager")
	if asset_manager:
		var race_sprites = asset_manager.get_race_sprites(race_index, character_sex)
		print("HumanSpriteSystem: Got race sprites from asset manager: ", race_sprites.size(), " sprites")
		
		# Update paths for each body part
		if race_sprites.has("body"):
			var body_data = race_sprites["body"]
			body_sprite_path = body_data["texture"]
			
			# Store maps for applying later
			limb_materials[LimbType.BODY] = {
				"normal_map": body_data.get("normal_map", ""),
				"specular_map": body_data.get("specular_map", "")
			}
		
		if race_sprites.has("head"):
			var head_data = race_sprites["head"]
			head_sprite_path = head_data["texture"]
			
			limb_materials[LimbType.HEAD] = {
				"normal_map": head_data.get("normal_map", ""),
				"specular_map": head_data.get("specular_map", "")
			}
		
		if race_sprites.has("left_arm"):
			var left_arm_data = race_sprites["left_arm"]
			left_arm_sprite_path = left_arm_data["texture"]
			
			limb_materials[LimbType.LEFT_ARM] = {
				"normal_map": left_arm_data.get("normal_map", ""),
				"specular_map": left_arm_data.get("specular_map", "")
			}
		
		if race_sprites.has("right_arm"):
			var right_arm_data = race_sprites["right_arm"]
			right_arm_sprite_path = right_arm_data["texture"]
			
			limb_materials[LimbType.RIGHT_ARM] = {
				"normal_map": right_arm_data.get("normal_map", ""),
				"specular_map": right_arm_data.get("specular_map", "")
			}
		
		if race_sprites.has("left_hand"):
			var left_hand_data = race_sprites["left_hand"] 
			left_hand_sprite_path = left_hand_data["texture"]
			
			limb_materials[LimbType.LEFT_HAND] = {
				"normal_map": left_hand_data.get("normal_map", ""),
				"specular_map": left_hand_data.get("specular_map", "")
			}
		
		if race_sprites.has("right_hand"):
			var right_hand_data = race_sprites["right_hand"]
			right_hand_sprite_path = right_hand_data["texture"]
			
			limb_materials[LimbType.RIGHT_HAND] = {
				"normal_map": right_hand_data.get("normal_map", ""),
				"specular_map": right_hand_data.get("specular_map", "")
			}
		
		if race_sprites.has("left_leg"):
			var left_leg_data = race_sprites["left_leg"]
			left_leg_sprite_path = left_leg_data["texture"]
			
			limb_materials[LimbType.LEFT_LEG] = {
				"normal_map": left_leg_data.get("normal_map", ""),
				"specular_map": left_leg_data.get("specular_map", "")
			}
		
		if race_sprites.has("right_leg"):
			var right_leg_data = race_sprites["right_leg"]
			right_leg_sprite_path = right_leg_data["texture"]
			
			limb_materials[LimbType.RIGHT_LEG] = {
				"normal_map": right_leg_data.get("normal_map", ""),
				"specular_map": right_leg_data.get("specular_map", "")
			}
		
		if race_sprites.has("left_foot"):
			var left_foot_data = race_sprites["left_foot"]
			left_foot_sprite_path = left_foot_data["texture"]
			
			limb_materials[LimbType.LEFT_FOOT] = {
				"normal_map": left_foot_data.get("normal_map", ""),
				"specular_map": left_foot_data.get("specular_map", "")
			}
		
		if race_sprites.has("right_foot"):
			var right_foot_data = race_sprites["right_foot"]
			right_foot_sprite_path = right_foot_data["texture"]
			
			limb_materials[LimbType.RIGHT_FOOT] = {
				"normal_map": right_foot_data.get("normal_map", ""),
				"specular_map": right_foot_data.get("specular_map", "")
			}
	else:
		# Fallback to basic path construction
		var sex_suffix = "_Female" if character_sex == 1 else ""
		var variant_suffix = "_" + str(race_variant) if race_variant > 0 else ""
		
		# Base path patterns
		var base_path = "res://Assets/Human/"
		
		# Handle different race directories
		if race_index > 0:
			var race_dir = "Human"  # Default
			if asset_manager and race_index < asset_manager.races.size():
				race_dir = asset_manager.races[race_index].split("_")[0]  # Get base race name
			
			base_path = "res://Assets/Human/" + race_dir + "/"
		
		# Update paths with appropriate suffixes
		body_sprite_path = base_path + "Body" + sex_suffix + variant_suffix + ".png"
		head_sprite_path = base_path + "Head" + sex_suffix + variant_suffix + ".png"
		left_arm_sprite_path = base_path + "Left_arm" + sex_suffix + variant_suffix + ".png"
		right_arm_sprite_path = base_path + "Right_arm" + sex_suffix + variant_suffix + ".png"
		left_hand_sprite_path = base_path + "Left_hand" + sex_suffix + variant_suffix + ".png"
		right_hand_sprite_path = base_path + "Right_hand" + sex_suffix + variant_suffix + ".png"
		left_leg_sprite_path = base_path + "Left_leg" + sex_suffix + variant_suffix + ".png"
		right_leg_sprite_path = base_path + "Right_leg" + sex_suffix + variant_suffix + ".png"
		left_foot_sprite_path = base_path + "Left_foot" + sex_suffix + variant_suffix + ".png"
		right_foot_sprite_path = base_path + "Right_foot" + sex_suffix + variant_suffix + ".png"
	
	print("HumanSpriteSystem: Sprite paths updated for race and sex")

# Reload sprites after race/sex change
func _reload_sprites_for_race():
	print("HumanSpriteSystem: Reloading sprites for new race/sex")
	
	# Cache the current direction
	var old_direction = current_direction
	
	# Load new textures
	var textures = {}
	
	# Load each texture with error handling
	for limb_type in [LimbType.BODY, LimbType.HEAD, LimbType.LEFT_ARM, LimbType.RIGHT_ARM, 
					   LimbType.LEFT_HAND, LimbType.RIGHT_HAND, LimbType.LEFT_LEG, 
					   LimbType.RIGHT_LEG, LimbType.LEFT_FOOT, LimbType.RIGHT_FOOT]:
		var path = ""
		
		# Get the appropriate path for each limb type
		match limb_type:
			LimbType.BODY: path = body_sprite_path
			LimbType.HEAD: path = head_sprite_path
			LimbType.LEFT_ARM: path = left_arm_sprite_path
			LimbType.RIGHT_ARM: path = right_arm_sprite_path
			LimbType.LEFT_HAND: path = left_hand_sprite_path
			LimbType.RIGHT_HAND: path = right_hand_sprite_path
			LimbType.LEFT_LEG: path = left_leg_sprite_path
			LimbType.RIGHT_LEG: path = right_leg_sprite_path
			LimbType.LEFT_FOOT: path = left_foot_sprite_path
			LimbType.RIGHT_FOOT: path = right_foot_sprite_path
		
		# Try to load the texture
		if path and FileAccess.file_exists(path):
			if asset_manager:
				textures[limb_type] = asset_manager.get_resource(path)
			else:
				textures[limb_type] = load(path)
				
			print("HumanSpriteSystem: Loaded texture for limb: ", LimbType.keys()[limb_type])
		else:
			print("HumanSpriteSystem: WARNING - Failed to load texture for limb: ", LimbType.keys()[limb_type], " - Path: ", path)
			# Keep existing texture if available
			match limb_type:
				LimbType.BODY: textures[limb_type] = body_sprite.texture
				LimbType.HEAD: textures[limb_type] = head_sprite.texture
				LimbType.LEFT_ARM: textures[limb_type] = left_arm_sprite.texture
				LimbType.RIGHT_ARM: textures[limb_type] = right_arm_sprite.texture
				LimbType.LEFT_HAND: textures[limb_type] = left_hand_sprite.texture
				LimbType.RIGHT_HAND: textures[limb_type] = right_hand_sprite.texture
				LimbType.LEFT_LEG: textures[limb_type] = left_leg_sprite.texture
				LimbType.RIGHT_LEG: textures[limb_type] = right_leg_sprite.texture
				LimbType.LEFT_FOOT: textures[limb_type] = left_foot_sprite.texture
				LimbType.RIGHT_FOOT: textures[limb_type] = right_foot_sprite.texture
	
	# Apply textures to sprites
	if textures[LimbType.BODY]: body_sprite.texture = textures[LimbType.BODY]
	if textures[LimbType.HEAD]: head_sprite.texture = textures[LimbType.HEAD]
	if textures[LimbType.LEFT_ARM]: left_arm_sprite.texture = textures[LimbType.LEFT_ARM]
	if textures[LimbType.RIGHT_ARM]: right_arm_sprite.texture = textures[LimbType.RIGHT_ARM]
	if textures[LimbType.LEFT_HAND]: left_hand_sprite.texture = textures[LimbType.LEFT_HAND]
	if textures[LimbType.RIGHT_HAND]: right_hand_sprite.texture = textures[LimbType.RIGHT_HAND]
	if textures[LimbType.LEFT_LEG]: left_leg_sprite.texture = textures[LimbType.LEFT_LEG]
	if textures[LimbType.RIGHT_LEG]: right_leg_sprite.texture = textures[LimbType.RIGHT_LEG]
	if textures[LimbType.LEFT_FOOT]: left_foot_sprite.texture = textures[LimbType.LEFT_FOOT]
	if textures[LimbType.RIGHT_FOOT]: right_foot_sprite.texture = textures[LimbType.RIGHT_FOOT]
	
	# Apply maps to sprites
	for limb_type in limb_materials:
		var sprite = limb_sprites[limb_type]
		if sprite and limb_materials[limb_type]:
			var normal_map = limb_materials[limb_type].get("normal_map", "")
			var specular_map = limb_materials[limb_type].get("specular_map", "")
			
			if !normal_map.is_empty() or !specular_map.is_empty():
				apply_mapped_material(sprite, normal_map, specular_map)
				print("HumanSpriteSystem: Applied maps to limb: ", LimbType.keys()[limb_type])
	
	# Reset direction to force update of frame regions
	set_direction(old_direction)
	
	print("HumanSpriteSystem: Sprites reloaded for new race/sex")

# Update underwear/undershirt frames when direction changes
func update_undergarment_frames():
	if underwear_sprite and underwear_sprite.visible and underwear_sprite.texture:
		var frame_x = current_direction * sprite_frame_width
		underwear_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
	
	if undershirt_sprite and undershirt_sprite.visible and undershirt_sprite.texture:
		var frame_x = current_direction * sprite_frame_width
		undershirt_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)

# ========== MAIN UPDATE LOOP ==========

func _process(delta):
	# Update limb appearance continually
	if Entity:
		# Update limb frames
		update_sprite_frames()
		
		# Update z-ordering based on direction
		update_sprite_z_ordering()
		
		# Handle prone state if Entity has is_prone property
		if Entity.has_method("is_prone"):
			set_lying_state(Entity.is_prone())
		
		# Update held items positions to match hands
		update_held_items_positions()
	
	# Process highlight pulsing if highlighted
	if is_highlighted:
		update_highlight_pulse(delta)
	
	# Process interaction feedback fadeout
	if interaction_feedback_timer > 0:
		interaction_feedback_timer -= delta
		if interaction_feedback_timer <= 0:
			hide_interaction_feedback()

# Update highlight pulse effect
func update_highlight_pulse(delta: float):
	if highlight_sprite and highlight_sprite.visible:
		# Simple pulsing effect
		var pulse_value = (sin(Time.get_ticks_msec() * 0.003) + 1) / 2.0
		highlight_sprite.modulate.a = lerp(0.3, 0.7, pulse_value)
		
		# Slightly vary the scale too
		var scale_pulse = lerp(0.95, 1.05, pulse_value)
		highlight_sprite.scale = Vector2(scale_pulse, scale_pulse)

# ========== DIRECTION MANAGEMENT ==========

# Set the current facing direction
func set_direction(direction: int):
	if current_direction == direction:
		return
	
	var previous_direction = current_direction
	current_direction = direction

	# Update frame regions for all sprites based on direction
	update_sprite_frames()
	
	# Update z-ordering based on direction
	update_sprite_z_ordering()
	
	# Update clothing sprites if any
	update_clothing_frames()
	
	# Update customization sprites like hair and facial hair
	update_customization_frames()
	
	# Update equipment sprites
	update_equipment_sprites()
	
	# Update underwear and undershirt frames
	update_undergarment_frames()
	
	# If lying, update lying rotation based on new direction
	if is_lying:
		update_lying_rotation_for_direction_change(direction)
	
	# Notify that direction has changed
	direction_changed_this_frame = true
	emit_signal("sprite_direction_changed", direction)

@rpc("any_peer", "call_local")
func sync_sprite_direction(direction: int):
	# When called from network, ensure only the authority can send directions for others
	var is_valid_sender = false
	
	# Check if sender is server (always trusted)
	if multiplayer.get_remote_sender_id() == 1:
		is_valid_sender = true
	# Check if sender is authority for this entity    
	elif Entity and Entity.has_node("MultiplayerSynchronizer"):
		var synchronizer = Entity.get_node("MultiplayerSynchronizer")
		is_valid_sender = multiplayer.get_remote_sender_id() == synchronizer.get_multiplayer_authority()
	
	if is_valid_sender and direction >= 0 and direction <= 3:
		# Apply the direction change without re-syncing
		current_direction = direction
		
		# Update visuals
		update_sprite_frames()
		update_sprite_z_ordering()
		update_clothing_frames()
		update_customization_frames()
		update_equipment_sprites()
		update_undergarment_frames()
		
		if is_lying:
			# CHANGE THIS LINE: Use our new function instead
			update_lying_rotation_for_direction_change(direction)
			
		direction_changed_this_frame = true
		emit_signal("sprite_direction_changed", direction)

func network_set_direction(direction: int):
	if direction < 0 or direction > 3:
		return
	
	# This gets called by a network synchronizer or other external system
	# Apply the direction change through our sync method to ensure visuals update
	current_direction = direction
	
	# Update everything visually
	update_sprite_frames()
	update_sprite_z_ordering()
	update_clothing_frames()
	update_customization_frames()
	update_equipment_sprites()
	update_undergarment_frames()
	
	if is_lying:
		# CHANGE THIS LINE: Use our new function instead
		update_lying_rotation_for_direction_change(direction)
		
	emit_signal("sprite_direction_changed", direction)

# Update sprite frame regions based on current direction
func update_sprite_frames():
	for limb_type in limb_sprites:
		var sprite = limb_sprites[limb_type]
		if sprite and sprite.texture and sprite.region_enabled:
			# Calculate frame position in sprite sheet
			var frame_x = current_direction * sprite_frame_width
			
			# Update region rect to show correct direction
			sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)

# Update sprite z-ordering for proper layering based on direction
func update_sprite_z_ordering():
	# Different z-ordering when lying down
	if is_lying:
		# When lying, we want different layering
		for limb_type in limb_sprites:
			var sprite = limb_sprites[limb_type]
			if sprite:
				# Override z-index for lying state
				match lying_direction:
					Direction.SOUTH:
						# Head to the right, feet to the left
						if limb_type == LimbType.HEAD:
							sprite.z_index = 3  # Head on top
						elif limb_type in [LimbType.LEFT_LEG, LimbType.RIGHT_LEG, LimbType.LEFT_FOOT, LimbType.RIGHT_FOOT]:
							sprite.z_index = 1  # Feet at bottom
						else:
							sprite.z_index = 2  # Body in middle
					Direction.NORTH:
						# Head to the left, feet to the right
						if limb_type == LimbType.HEAD:
							sprite.z_index = 3
						elif limb_type in [LimbType.LEFT_LEG, LimbType.RIGHT_LEG, LimbType.LEFT_FOOT, LimbType.RIGHT_FOOT]:
							sprite.z_index = 1
						else:
							sprite.z_index = 2
					Direction.EAST, Direction.WEST:
						# Head up/down, regular layering
						sprite.z_index = limb_z_index_layers[lying_direction][limb_type]
		
		# Update equipment z-indices for lying state
		for slot in equipment_sprites:
			var sprite = equipment_sprites[slot]
			if sprite and sprite.visible:
				match lying_direction:
					Direction.SOUTH, Direction.NORTH:
						if slot in [EquipSlot.HEAD, EquipSlot.EYES, EquipSlot.MASK]:
							sprite.z_index = 4  # Head equipment on top
						elif slot in [EquipSlot.SHOES]:
							sprite.z_index = 1  # Shoes at bottom
						else:
							sprite.z_index = 3  # Other equipment in middle
					Direction.EAST, Direction.WEST:
						sprite.z_index = equipment_z_index_layers[lying_direction][slot]
						
		# Update undergarment z-indices for lying state
		if underwear_sprite and underwear_sprite.visible:
			underwear_sprite.z_index = 3  # Under body
		
		if undershirt_sprite and undershirt_sprite.visible:
			undershirt_sprite.z_index = 3  # Under body
	else:
		# Normal standing z-ordering
		for limb_type in limb_sprites:
			var sprite = limb_sprites[limb_type]
			if sprite and limb_z_index_layers[current_direction].has(limb_type):
				sprite.z_index = limb_z_index_layers[current_direction][limb_type]
		
		# Update equipment sprites z-indices - ONLY FOR VISIBLE SPRITES
		for slot in equipment_sprites:
			var sprite = equipment_sprites[slot]
			if sprite and sprite.visible and equipment_z_index_layers[current_direction].has(slot):
				sprite.z_index = equipment_z_index_layers[current_direction][slot]
				# Make sure sprite is actually visible
				sprite.visible = true
		
		# Update undergarment z-indices
		if underwear_sprite and underwear_sprite.visible:
			underwear_sprite.z_index = 3  # Under body
		
		if undershirt_sprite and undershirt_sprite.visible:
			undershirt_sprite.z_index = 3  # Under body

# Set the character's sex
func set_sex(sex: int):
	print("HumanSpriteSystem: Setting character sex to: ", "Female" if sex == 1 else "Male")
	character_sex = sex
	
	# Update sprite paths to use sex-specific versions if available
	_update_sprite_paths_for_sex()
	
	# Update sprites to reflect the change
	setup_sprites()
	
	# Update sprite frames based on current direction
	update_sprite_frames()
	
	# Handle gender-specific clothing elements
	if sex == 1:  # Female
		# If female, make sure facial hair is removed
		if facial_hair_sprite:
			facial_hair_sprite.visible = false
	
	print("HumanSpriteSystem: Character sex updated successfully")

# Update sprite paths based on character sex
func _update_sprite_paths_for_sex():
	# Only check for female sprites - keep male as default
	if character_sex == 1:  # Female
		# Check for sex-specific body parts and update paths
		var female_body_path = "res://Assets/Human/Body_Female.png"
		var female_head_path = "res://Assets/Human/Head_Female.png"
		
		# Only update if the female sprite exists
		if FileAccess.file_exists(female_body_path):
			body_sprite_path = female_body_path
			print("HumanSpriteSystem: Using female body sprite: ", body_sprite_path)
		else:
			print("HumanSpriteSystem: Female body sprite not found, using default")
		
		if FileAccess.file_exists(female_head_path):
			head_sprite_path = female_head_path
			print("HumanSpriteSystem: Using female head sprite: ", head_sprite_path)
		else:
			print("HumanSpriteSystem: Female head sprite not found, using default")
			
		# Check for female-specific arm sprites
		var female_left_arm_path = "res://Assets/Human/Left_arm_Female.png"
		if FileAccess.file_exists(female_left_arm_path):
			left_arm_sprite_path = female_left_arm_path
			print("HumanSpriteSystem: Using female left arm sprite: ", left_arm_sprite_path)
		
		var female_right_arm_path = "res://Assets/Human/Right_arm_Female.png"
		if FileAccess.file_exists(female_right_arm_path):
			right_arm_sprite_path = female_right_arm_path
			print("HumanSpriteSystem: Using female right arm sprite: ", right_arm_sprite_path)
			
		# Check for female-specific leg sprites
		var female_left_leg_path = "res://Assets/Human/Left_leg_Female.png"
		if FileAccess.file_exists(female_left_leg_path):
			left_leg_sprite_path = female_left_leg_path
			print("HumanSpriteSystem: Using female left leg sprite: ", left_leg_sprite_path)
			
		var female_right_leg_path = "res://Assets/Human/Right_leg_Female.png"
		if FileAccess.file_exists(female_right_leg_path):
			right_leg_sprite_path = female_right_leg_path
			print("HumanSpriteSystem: Using female right leg sprite: ", right_leg_sprite_path)
	else:
		# Reset to male/default sprites
		body_sprite_path = "res://Assets/Human/Body.png"
		head_sprite_path = "res://Assets/Human/Head.png"
		left_arm_sprite_path = "res://Assets/Human/Left_arm.png"
		right_arm_sprite_path = "res://Assets/Human/Right_arm.png"
		left_leg_sprite_path = "res://Assets/Human/Left_leg.png"
		right_leg_sprite_path = "res://Assets/Human/Right_leg.png"
		
		print("HumanSpriteSystem: Using default male sprites")

# Update clothing sprites when direction changes
func update_clothing_frames():
	# Update all clothing sprites to match current direction
	for slot in equipment_sprites:
		var sprite = equipment_sprites[slot]
		if sprite and sprite.visible and sprite.texture and sprite.region_enabled:
			# Update region to match current direction
			var frame_x = current_direction * sprite_frame_width
			sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)

# Update customization elements when direction changes
func update_customization_frames():
	var frame_x = current_direction * sprite_frame_width
	
	# Update hair sprite
	if hair_sprite and hair_sprite.texture:
		hair_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
	
	# Update facial hair sprite
	if facial_hair_sprite and facial_hair_sprite.texture:
		facial_hair_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)

# Set hair style and color
func set_hair(hair_texture_path: String, hair_color: Color, normal_map_path: String = "", specular_map_path: String = ""):
	print("HumanSpriteSystem: Setting hair - Texture: ", hair_texture_path, " Color: ", hair_color)
	
	# Handle null or empty texture path
	if hair_texture_path == null or hair_texture_path.is_empty() or hair_texture_path == "null":
		# Remove hair if texture doesn't exist
		if has_node("HairSprite"):
			$HairSprite.queue_free()
			hair_sprite = null
			print("HumanSpriteSystem: Removed hair (null or empty path)")
		return
	
	# Make sure the file exists
	if !ResourceLoader.exists(hair_texture_path):
		push_error("HumanSpriteSystem: Hair texture file not found: " + hair_texture_path)
		return
	
	# Create or update hair sprite
	hair_sprite = get_node_or_null("HairSprite")
	if !hair_sprite:
		hair_sprite = Sprite2D.new()
		hair_sprite.name = "HairSprite"
		hair_sprite.centered = true
		hair_sprite.z_index = 4  # Above head
		
		# Enable region for frame animation
		hair_sprite.region_enabled = true
		
		add_child(hair_sprite)
		print("HumanSpriteSystem: Created new hair sprite")
	
	# Set hair texture and color
	if asset_manager:
		hair_sprite.texture = asset_manager.get_resource(hair_texture_path)
	else:
		hair_sprite.texture = load(hair_texture_path)
		
	hair_sprite.modulate = hair_color
	
	# Apply material with maps if provided
	if !normal_map_path.is_empty() or !specular_map_path.is_empty():
		apply_mapped_material(hair_sprite, normal_map_path, specular_map_path)
		print("HumanSpriteSystem: Applied maps to hair sprite")
	
	# Update frame based on current direction
	var frame_x = current_direction * sprite_frame_width
	hair_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
	
	# If we're already in prone state, apply rotation
	if is_lying:
		apply_sprite_rotation_for_lying(hair_sprite)
	
	print("HumanSpriteSystem: Hair setup successful")

# Set facial hair style and color
func set_facial_hair(
	facial_hair_texture_path: String,
	facial_hair_color: Color,
	normal_map: Texture2D = null,
	specular_map: Texture2D = null
):
	print("HumanSpriteSystem: Setting facial hair - Texture: ", facial_hair_texture_path, " Color: ", facial_hair_color)

	# Handle null or empty texture path
	if facial_hair_texture_path == null or facial_hair_texture_path.is_empty() or facial_hair_texture_path == "null":
		if has_node("FacialHairSprite"):
			$FacialHairSprite.queue_free()
			facial_hair_sprite = null
			print("HumanSpriteSystem: Removed facial hair (null or empty path)")
		return

	# Skip facial hair for females
	if character_sex == 1:
		print("HumanSpriteSystem: Skipping facial hair for female character")
		if has_node("FacialHairSprite"):
			$FacialHairSprite.queue_free()
			facial_hair_sprite = null
		return

	# Make sure the file exists
	if !ResourceLoader.exists(facial_hair_texture_path):
		push_error("HumanSpriteSystem: Facial hair texture file not found: " + facial_hair_texture_path)
		return

	# Create or update facial hair sprite
	facial_hair_sprite = get_node_or_null("FacialHairSprite")
	if !facial_hair_sprite:
		facial_hair_sprite = Sprite2D.new()
		facial_hair_sprite.name = "FacialHairSprite"
		facial_hair_sprite.centered = true
		facial_hair_sprite.z_index = 3.5
		facial_hair_sprite.region_enabled = true
		add_child(facial_hair_sprite)
		print("HumanSpriteSystem: Created new facial hair sprite")

	# Set the texture and modulate
	facial_hair_sprite.texture = load(facial_hair_texture_path)
	facial_hair_sprite.modulate = facial_hair_color

	# Apply optional normal and specular maps via CanvasItemMaterial
	if normal_map or specular_map:
		var mat := CanvasItemMaterial.new()
		if normal_map:
			mat.normal_texture = normal_map
		if specular_map:
			mat.specular_texture = specular_map
		facial_hair_sprite.material = mat

	# Set frame based on current direction
	var frame_x = current_direction * sprite_frame_width
	facial_hair_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)

	# Apply rotation if prone
	if is_lying:
		apply_sprite_rotation_for_lying(facial_hair_sprite)

	print("HumanSpriteSystem: Facial hair setup successful")


# Set clothing textures for multiple layers
func set_clothing(
	clothing_textures: Dictionary,
	clothing_normal_maps: Dictionary = {},
	clothing_specular_maps: Dictionary = {}
):
	print("HumanSpriteSystem: Setting clothing - Textures: ", clothing_textures)

	if clothing_textures.is_empty():
		print("HumanSpriteSystem: No clothing textures provided, no changes made")
		return

	for slot_name in clothing_textures:
		var texture_path = clothing_textures[slot_name]
		if texture_path.is_empty():
			continue

		var slot_id = _get_slot_id_from_name(slot_name)
		if slot_id < 0:
			print("HumanSpriteSystem: Unknown clothing slot: ", slot_name)
			continue

		var equipment_sprite = equipment_sprites.get(slot_id)
		if !equipment_sprite:
			print("HumanSpriteSystem: No sprite found for slot: ", slot_name)
			continue

		if ResourceLoader.exists(texture_path):
			var texture = load(texture_path)
			equipment_sprite.texture = texture
			equipment_sprite.region_enabled = true

			# Set region for animation frame
			var frame_x = current_direction * sprite_frame_width
			equipment_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)

			# Set z-index based on direction and slot
			equipment_sprite.z_index = equipment_z_index_layers[current_direction][slot_id]
			equipment_sprite.visible = true

			# Apply prone rotation if needed
			if is_lying:
				apply_sprite_rotation_for_lying(equipment_sprite)

			# Apply normal/specular maps if available
			var normal_map = clothing_normal_maps.get(slot_name, null)
			var specular_map = clothing_specular_maps.get(slot_name, null)

			if normal_map or specular_map:
				var mat := CanvasItemMaterial.new()
				if normal_map:
					mat.normal_texture = normal_map
				if specular_map:
					mat.specular_texture = specular_map
				equipment_sprite.material = mat

			print("HumanSpriteSystem: Applied clothing for slot ", slot_name)
		else:
			print("HumanSpriteSystem: Clothing texture not found: ", texture_path)

	print("HumanSpriteSystem: Clothing setup complete")

# Helper to get slot ID from name (for set_clothing)
func _get_slot_id_from_name(slot_name: String) -> int:
	slot_name = slot_name.to_lower()
	
	match slot_name:
		"head", "hat", "helmet":
			return EquipSlot.HEAD
		"eyes", "glasses", "goggles":
			return EquipSlot.EYES
		"mask", "facemask":
			return EquipSlot.MASK
		"ears", "earpiece", "headset":
			return EquipSlot.EARS
		"neck", "tie":
			return EquipSlot.NECK
		"outer", "armor", "suit":
			return EquipSlot.OUTER
		"uniform", "jumpsuit", "body":
			return EquipSlot.UNIFORM
		"suit", "jacket", "coat":
			return EquipSlot.SUIT
		"gloves":
			return EquipSlot.GLOVES
		"belt":
			return EquipSlot.BELT
		"shoes", "boots":
			return EquipSlot.SHOES
		"back", "backpack":
			return EquipSlot.BACK
		"id", "badge":
			return EquipSlot.ID
		_:
			return -1

# Update all equipment visuals when direction changes
func update_equipment_sprites():
	# Update all visible equipment sprites with the new direction
	
	# First, update dedicated equipment sprites for each slot
	for slot in equipment_sprites:
		var sprite = equipment_sprites[slot]
		if sprite and sprite.visible and sprite.texture and sprite.region_enabled:
			# Update frame based on new direction
			var frame_x = current_direction * sprite_frame_width
			sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
			
			# Update z-index for new direction
			if equipment_z_index_layers[current_direction].has(slot):
				sprite.z_index = equipment_z_index_layers[current_direction][slot]
	
	# Update held items
	for slot in [EquipSlot.LEFT_HAND, EquipSlot.RIGHT_HAND]:
		if visible_equipment_sprites.has(slot):
			update_held_item_rotation(visible_equipment_sprites[slot], slot)

# Update the rotation and position of held items based on direction
func update_held_item_rotation(sprite: Sprite2D, slot: int):
	# Skip if sprite is invalid
	if !sprite:
		return
	
	# Get item properties
	var item = null
	if slot == EquipSlot.LEFT_HAND and equipped_items.has(EquipSlot.LEFT_HAND):
		item = equipped_items[EquipSlot.LEFT_HAND]
	elif slot == EquipSlot.RIGHT_HAND and equipped_items.has(EquipSlot.RIGHT_HAND):
		item = equipped_items[EquipSlot.RIGHT_HAND]
	
	# Adjust for item size if available
	var size_modifier = 1.0
	if item and item.has_method("get_size"):
		# Scale based on item size - larger items appear slightly smaller in hand
		var item_size = item.get_size()
		size_modifier = clamp(1.0 / sqrt(item_size.x * item_size.y), 0.6, 1.2)
	
	# Apply size
	sprite.scale = Vector2(size_modifier, size_modifier)
	
	# Held item rotation based on direction
	var rotation = 0.0
	var offset = Vector2.ZERO
	
	match current_direction:
		Direction.SOUTH:
			rotation = 0.0
			# Left hand on left side, right hand on right side
			offset = Vector2(-8 if slot == EquipSlot.LEFT_HAND else 8, 6)
		Direction.NORTH:
			rotation = 0.0
			# Reversed hands when facing north
			offset = Vector2(-8 if slot == EquipSlot.LEFT_HAND else 8, -6)
		Direction.EAST:
			# Item points right when facing east
			rotation = -PI/4 if slot == EquipSlot.RIGHT_HAND else PI/4
			offset = Vector2(10, -2 if slot == EquipSlot.RIGHT_HAND else 2)
		Direction.WEST:
			# Item points left when facing west
			rotation = PI/4 if slot == EquipSlot.RIGHT_HAND else -PI/4
			offset = Vector2(-10, -2 if slot == EquipSlot.RIGHT_HAND else 2)
	
	# Apply item-specific rotation adjustments if available
	if item and item.has_method("get_held_rotation_offset"):
		rotation += item.get_held_rotation_offset()
	
	# Set rotation and position
	sprite.rotation = rotation
	
	# Set position based on hand
	if slot == EquipSlot.LEFT_HAND:
		sprite.position = left_hand_item_position.position + offset
	elif slot == EquipSlot.RIGHT_HAND:
		sprite.position = right_hand_item_position.position + offset

# Update the positions of held items to follow hands
func update_held_items_positions():
	# Update held items container position to match entity position
	if held_items_container:
		held_items_container.position = Vector2.ZERO
	
	# Update left hand position
	if left_hand_sprite and left_hand_item_position:
		left_hand_item_position.position = left_hand_sprite.position
		
		# Update item sprite if it exists
		if visible_equipment_sprites.has(EquipSlot.LEFT_HAND):
			update_held_item_rotation(visible_equipment_sprites[EquipSlot.LEFT_HAND], EquipSlot.LEFT_HAND)
	
	# Update right hand position
	if right_hand_sprite and right_hand_item_position:
		right_hand_item_position.position = right_hand_sprite.position
		
		# Update item sprite if it exists
		if visible_equipment_sprites.has(EquipSlot.RIGHT_HAND):
			update_held_item_rotation(visible_equipment_sprites[EquipSlot.RIGHT_HAND], EquipSlot.RIGHT_HAND)

# ========== EQUIPMENT MANAGEMENT ==========
# Equip an item in a specific slot
func equip_item(item, slot: int) -> bool:
	print("HumanSpriteSystem: Equipping item to slot ", slot)
	
	# Check if slot is already occupied
	if equipped_items.has(slot) and equipped_items[slot] != null:
		# Unequip current item first
		unequip_item(slot)
	
	# Store reference to the item
	equipped_items[slot] = item
	
	# Handle worn equipment
	_create_equipment_visual(item, slot)
	print("HumanSpriteSystem: Created visual for equipment in slot ", slot)
	
	# Apply any equipment effects
	_apply_equipment_effects(item, slot)
	
	# Emit signal
	emit_signal("item_equipped", item, slot)
	
	return true

# Unequip an item from a specific slot
func unequip_item(slot: int) -> bool:
	# Check if there's an item in this slot
	if !equipped_items.has(slot) or equipped_items[slot] == null:
		print("HumanSpriteSystem: No item to unequip from slot ", slot)
		return false
	
	var item = equipped_items[slot]
	print("HumanSpriteSystem: Unequipping item from slot ", slot)
	
	# Remove visual representation for held items
	if slot == EquipSlot.LEFT_HAND or slot == EquipSlot.RIGHT_HAND:
		if visible_equipment_sprites.has(slot):
			visible_equipment_sprites[slot].queue_free()
			visible_equipment_sprites.erase(slot)
			print("HumanSpriteSystem: Removed visible sprite for slot ", slot)
	else:
		# Hide the dedicated equipment sprite for this slot
		if equipment_sprites.has(slot):
			# IMPORTANT: Only hide this specific slot's sprite
			equipment_sprites[slot].visible = false
			equipment_sprites[slot].texture = null
			print("HumanSpriteSystem: Hidden dedicated equipment sprite for slot ", slot)
	
	# Clear reference
	equipped_items.erase(slot)
	
	# Emit signal
	emit_signal("item_unequipped", item, slot)
	
	return true

# Create visual representation for worn equipment - IMPROVED FOR MULTI-LAYER SUPPORT
func _create_equipment_visual(item, slot: int):
	print("HumanSpriteSystem: Creating equipment visual for slot ", slot)
	
	# Get the dedicated equipment sprite for this slot
	var equipment_sprite = equipment_sprites.get(slot)
	if !equipment_sprite:
		print("HumanSpriteSystem: ERROR - No sprite found for slot ", slot)
		return
	
	# Get texture from item
	var texture = null
	
	if item.has_node("Icon") and item.get_node("Icon").texture:
		texture = item.get_node("Icon").texture
		print("HumanSpriteSystem: Using Icon texture for equipment")
	elif "sprite" in item and item.sprite and item.sprite.texture:
		texture = item.sprite.texture
		print("HumanSpriteSystem: Using sprite texture for equipment")
	elif item.has_method("get_texture"):
		texture = item.get_texture()
		print("HumanSpriteSystem: Using get_texture() method for equipment")
	
	# If no texture found, try to create a placeholder
	if !texture:
		print("HumanSpriteSystem: No texture found for equipment item, creating placeholder")
		var image = Image.create(sprite_frame_width, sprite_frame_height, false, Image.FORMAT_RGBA8)
		
		# Color based on slot type
		var color = Color(0.5, 0.5, 0.5, 0.5)  # Default semi-transparent gray
		match slot:
			EquipSlot.UNIFORM:
				color = Color(0.2, 0.2, 0.8, 0.5)  # Blue for uniform
			EquipSlot.SUIT:
				color = Color(0.8, 0.2, 0.2, 0.5)  # Red for suit
			EquipSlot.OUTER:
				color = Color(0.2, 0.8, 0.2, 0.5)  # Green for outer armor
			EquipSlot.HEAD:
				color = Color(0.8, 0.8, 0.2, 0.5)  # Yellow for head
		
		image.fill(color)
		texture = ImageTexture.create_from_image(image)
	
	# Configure the equipment sprite
	equipment_sprite.texture = texture
	equipment_sprite.region_enabled = true
	
	# Set frame based on current direction
	var frame_x = current_direction * sprite_frame_width
	equipment_sprite.region_rect = Rect2(frame_x, 0, sprite_frame_width, sprite_frame_height)
	
	# Set z-index based on slot and direction
	equipment_sprite.z_index = equipment_z_index_layers[current_direction][slot]
	
	# Make the sprite visible - THIS IS CRITICAL
	equipment_sprite.visible = true
	
	# Apply lying rotation if needed
	if is_lying:
		apply_sprite_rotation_for_lying(equipment_sprite)
	
	# Add equip animation
	play_equip_animation(equipment_sprite)
	
	print("HumanSpriteSystem: Equipment visual created for slot ", slot)

# Play equip animation for a newly equipped item
func play_equip_animation(sprite: Sprite2D):
	# Start with item slightly enlarged and transparent
	sprite.scale = Vector2(1.2, 1.2)
	sprite.modulate.a = 0
	
	# Create animation tween
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_ELASTIC)
	
	# Scale and fade in
	tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.3)
	tween.parallel().tween_property(sprite, "modulate:a", 1.0, 0.2)

# Apply effects from equipment (like vision enhancement)
func _apply_equipment_effects(item, slot: int):
	# Skip if entity reference doesn't exist
	if !Entity:
		return
	
	# Example: Apply effects based on item and slot
	if item.has_method("get_enhanced_vision") and Entity.has_method("set_enhanced_vision"):
		Entity.set_enhanced_vision(Entity.get_enhanced_vision() + item.get_enhanced_vision())
	
	if item.has_method("get_hearing_modifier") and Entity.has_method("set_hearing_modifier"):
		Entity.set_hearing_modifier(Entity.get_hearing_modifier() * item.get_hearing_modifier())
	
	# Apply any status effects
	if item.has_method("get_status_effects") and Entity.has_method("add_status_effect"):
		var effects = item.get_status_effects()
		for effect in effects:
			Entity.add_status_effect(effect, effects[effect])

# Get item currently equipped in a slot
func get_item_in_slot(slot: int):
	return equipped_items.get(slot)

# ========== LYING STATE MANAGEMENT ==========

func show_interaction_feedback(interaction_type: String = "default", direction: Vector2 = Vector2.ZERO):
	# Map interaction type to intent number
	var intent_num = 0
	match interaction_type:
		"help", "use":
			intent_num = 0
		"disarm":
			intent_num = 1
		"grab":
			intent_num = 2
		"harm", "attack":
			intent_num = 3
	
	# Add thrust effect if direction provided
	if direction != Vector2.ZERO:
		show_interaction_thrust(direction, intent_num)
	else:
		# Default thrust forward based on character facing
		var facing_direction = Vector2.ZERO
		match current_direction:
			Direction.SOUTH:
				facing_direction = Vector2(0, 1)
			Direction.NORTH:
				facing_direction = Vector2(0, -1)
			Direction.EAST:
				facing_direction = Vector2(1, 0)
			Direction.WEST:
				facing_direction = Vector2(-1, 0)
		
		show_interaction_thrust(facing_direction, intent_num)

func show_interaction_thrust_to_position(world_position: Vector2, intent_type: int = 0):
	var my_position = global_position if has_method("global_position") else position
	var direction = (world_position - my_position).normalized()
	show_interaction_thrust(direction, intent_type)

# Show interaction thrust in specified direction
func show_interaction_thrust(direction: Vector2, intent_type: int = 0):
	if is_thrusting:
		return # Already thrusting, skip
	
	print("HumanSpriteSystem: Showing interaction thrust in direction: ", direction)
	
	# Cancel any existing thrust animation
	if thrust_tween and thrust_tween.is_valid():
		thrust_tween.kill()
	
	is_thrusting = true
	
	# Calculate thrust distance and duration based on intent
	var thrust_distance = 6.0
	var thrust_duration = 0.2
	var return_duration = 0.1
	
	# Adjust based on intent type
	match intent_type:
		0: # HELP - gentle thrust
			thrust_distance = 6.0
			thrust_duration = 0.25
		1: # DISARM - quick thrust
			thrust_distance = 6.0
			thrust_duration = 0.25
		2: # GRAB - reaching thrust
			thrust_distance = 6.0
			thrust_duration = 0.25
		3: # HARM - aggressive thrust
			thrust_distance = 6.0
			thrust_duration = 0.25
	
	# Calculate thrust offset
	var thrust_offset = direction * thrust_distance
	
	# Get intent-specific color tint
	var intent_colors = [
		Color(0.9, 1.1, 0.9), # HELP - slight green tint
		Color(1.1, 1.1, 0.8), # DISARM - yellow tint
		Color(0.9, 0.9, 1.1), # GRAB - blue tint
		Color(1.2, 0.8, 0.8)  # HARM - red tint
	]
	var thrust_color = intent_colors[intent_type] if intent_type < intent_colors.size() else Color.WHITE
	
	# Create main thrust animation
	thrust_tween = create_tween()
	thrust_tween.set_ease(Tween.EASE_OUT)
	thrust_tween.set_trans(Tween.TRANS_BACK)
	
	# Store original positions and colors
	var original_positions = {}
	var original_colors = {}
	
	# Animate all visible sprites
	var sprites_to_animate = []
	
	# Add body part sprites
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
	
	# Add customization sprites
	if hair_sprite and hair_sprite.visible:
		sprites_to_animate.append(hair_sprite)
		original_positions[hair_sprite] = hair_sprite.position
		original_colors[hair_sprite] = hair_sprite.modulate
	
	if facial_hair_sprite and facial_hair_sprite.visible:
		sprites_to_animate.append(facial_hair_sprite)
		original_positions[facial_hair_sprite] = facial_hair_sprite.position
		original_colors[facial_hair_sprite] = facial_hair_sprite.modulate
	
	# Add undergarment sprites
	if underwear_sprite and underwear_sprite.visible:
		sprites_to_animate.append(underwear_sprite)
		original_positions[underwear_sprite] = underwear_sprite.position
		original_colors[underwear_sprite] = underwear_sprite.modulate
	
	if undershirt_sprite and undershirt_sprite.visible:
		sprites_to_animate.append(undershirt_sprite)
		original_positions[undershirt_sprite] = undershirt_sprite.position
		original_colors[undershirt_sprite] = undershirt_sprite.modulate
	
	# Phase 1: Thrust forward with color tint
	for sprite in sprites_to_animate:
		var target_pos = original_positions[sprite] + thrust_offset
		thrust_tween.parallel().tween_property(sprite, "position", target_pos, thrust_duration)
		thrust_tween.parallel().tween_property(sprite, "modulate", thrust_color, thrust_duration * 0.5)
	
	# Phase 2: Return to original position
	for sprite in sprites_to_animate:
		thrust_tween.parallel().tween_property(sprite, "position", original_positions[sprite], return_duration).set_delay(thrust_duration)
		thrust_tween.parallel().tween_property(sprite, "modulate", original_colors[sprite], return_duration).set_delay(thrust_duration * 0.5)
	
	# Reset thrusting flag when animation completes
	thrust_tween.tween_callback(func(): 
		is_thrusting = false
		print("HumanSpriteSystem: Thrust animation completed")
	).set_delay(thrust_duration + return_duration)

# Apply rotation to a specific sprite based on lying state and direction
func apply_sprite_rotation_for_lying(sprite: Sprite2D, transition_time: float = 0.3):
	if sprite == null:
		return
		
	# Calculate target rotation based on direction and lying state
	var target_rotation = 0.0
	
	if is_lying:
		# Apply different rotations based on direction as specified
		match current_direction:
			Direction.EAST:
				target_rotation = PI/2.0  # 90 degrees clockwise
			Direction.WEST:
				target_rotation = -PI/2.0  # -90 degrees (counter-clockwise)
			Direction.SOUTH:
				target_rotation = PI  # 180 degrees
			Direction.NORTH:
				target_rotation = 0.0  # No rotation
	
	# Clear any existing tweens
	var existing_tween = sprite.get_meta("active_tween", null)
	if existing_tween and existing_tween.is_valid():
		existing_tween.kill()
	
	# Create a new tween with customizable timing
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(sprite, "rotation", target_rotation, transition_time)
	
	# Store the tween reference
	sprite.set_meta("active_tween", tween)

# Update lying state for all sprite elements
func set_lying_state(lying_state: bool, direction: int = -1, transition_time: float = 0.4):
	# If no change, do nothing
	if is_lying == lying_state:
		return
	
	# Track old state for cleanup
	var was_previously_lying = is_lying
	
	# Update state
	is_lying = lying_state
	
	# Use current direction if none specified
	if direction < 0:
		direction = current_direction
	
	# Store the lying direction
	if lying_state:
		lying_direction = direction
	
	# Cancel any active lying animation
	if active_lying_tween and active_lying_tween.is_valid():
		active_lying_tween.kill()
	
	# Create a new animation tween
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	active_lying_tween = tween
	
	# Update Z-index ordering if transitioning to lying state
	if lying_state:
		update_z_index_for_lying()
	else:
		# Revert to standard z-ordering when standing up
		update_sprite_z_ordering()
	
	# Handle all body part sprites
	for limb_type in limb_sprites:
		var sprite = limb_sprites[limb_type]
		if sprite and limbs_attached[limb_type]:
			apply_lying_rotation_to_sprite(sprite, lying_state, transition_time, tween)
	
	# Handle all customization sprites
	if hair_sprite:
		apply_lying_rotation_to_sprite(hair_sprite, lying_state, transition_time, tween)
	
	if facial_hair_sprite:
		apply_lying_rotation_to_sprite(facial_hair_sprite, lying_state, transition_time, tween)
	
	# Handle underwear and undershirt sprites
	if underwear_sprite and underwear_sprite.visible:
		apply_lying_rotation_to_sprite(underwear_sprite, lying_state, transition_time, tween)
	
	if undershirt_sprite and undershirt_sprite.visible:
		apply_lying_rotation_to_sprite(undershirt_sprite, lying_state, transition_time, tween)
	
	# Handle all equipment sprites
	for slot in equipment_sprites:
		var equipment_sprite = equipment_sprites[slot]
		if equipment_sprite and equipment_sprite.visible:
			apply_lying_rotation_to_sprite(equipment_sprite, lying_state, transition_time, tween)
	
	# Handle any held items
	for slot in [EquipSlot.LEFT_HAND, EquipSlot.RIGHT_HAND]:
		if visible_equipment_sprites.has(slot):
			apply_lying_rotation_to_sprite(visible_equipment_sprites[slot], lying_state, transition_time, tween)
	
	# Update status effects container position
	if status_effect_container:
		if lying_state:
			tween.parallel().tween_property(status_effect_container, "position:y", -16, transition_time)
		else:
			tween.parallel().tween_property(status_effect_container, "position:y", -32, transition_time)
	
	# Add or remove lying status effect
	if lying_state:
		if !active_status_effects.has("lying"):
			add_status_effect("lying", {"duration": -1})  # -1 indicates indefinite
	else:
		if active_status_effects.has("lying"):
			remove_status_effect("lying")

# Apply lying rotation and position changes to a sprite
func apply_lying_rotation_to_sprite(sprite: Sprite2D, is_lying: bool, transition_time: float = 0.4, parent_tween = null):
	if sprite == null:
		return
	
	# Calculate target rotation and position based on direction and lying state
	var target_rotation = 0.0
	var position_offset = Vector2.ZERO
	
	if is_lying:
		# Apply different rotations based on direction as specified
		match lying_direction:
			Direction.EAST:
				target_rotation = PI/2.0  # 90 degrees clockwise
			Direction.WEST:
				target_rotation = -PI/2.0  # -90 degrees (counter-clockwise)
			Direction.SOUTH:
				target_rotation = PI  # 180 degrees
			Direction.NORTH:
				target_rotation = 0.0  # No rotation
		
		# Different offsets based on the lying direction
		match lying_direction:
			Direction.SOUTH:
				position_offset = Vector2(lying_offset.x, lying_offset.y)
			Direction.NORTH:
				position_offset = Vector2(-lying_offset.x, lying_offset.y)
			Direction.EAST:
				position_offset = Vector2(0, lying_offset.y * 2)
			Direction.WEST:
				position_offset = Vector2(0, lying_offset.y * 2)
	
	# Create a new tween if one wasn't provided
	var tween = parent_tween
	if tween == null:
		tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
	
	# Animate rotation
	tween.parallel().tween_property(sprite, "rotation", target_rotation, transition_time)
	
	# Animate position
	if is_lying:
		tween.parallel().tween_property(sprite, "position", sprite.position + position_offset, transition_time)
	else:
		tween.parallel().tween_property(sprite, "position", Vector2.ZERO, transition_time)
	
	# Store the tween reference if not part of a parent tween
	if parent_tween == null:
		sprite.set_meta("active_lying_tween", tween)

# Update z-index for lying down state
func update_z_index_for_lying():
	# When lying, we need special Z-index ordering
	for limb_type in limb_sprites:
		var sprite = limb_sprites[limb_type]
		if sprite:
			# When lying down, limbs should be ordered so legs are visible above torso
			if limb_type == LimbType.BODY:
				sprite.z_index = 0  # Body lowest
			elif limb_type in [LimbType.LEFT_LEG, LimbType.RIGHT_LEG, LimbType.LEFT_FOOT, LimbType.RIGHT_FOOT]:
				sprite.z_index = 2  # Legs/feet on top
			elif limb_type == LimbType.HEAD:
				sprite.z_index = 2  # Head on top
			else:
				sprite.z_index = 2  # Arms in middle
	
	# Update equipment z-indices for lying state
	for slot in equipment_sprites:
		var sprite = equipment_sprites[slot]
		if sprite and sprite.visible:
			if slot in [EquipSlot.HEAD, EquipSlot.EYES, EquipSlot.MASK]:
				sprite.z_index = 4  # Head equipment on top
			elif slot in [EquipSlot.SHOES]:
				sprite.z_index = 4  # Shoes above legs
			elif slot in [EquipSlot.UNIFORM, EquipSlot.SUIT]:
				sprite.z_index = 3  # Body clothing below all limbs
			else:
				sprite.z_index = 4  # Other equipment in middle
	
	# Update undergarment z-indices
	if underwear_sprite and underwear_sprite.visible:
		underwear_sprite.z_index = 3  # Under body
	
	if undershirt_sprite and undershirt_sprite.visible:
		undershirt_sprite.z_index = 3  # Under body

# Update lying rotation immediately when direction changes
func update_lying_rotation_for_direction_change(new_direction: int):
	# Only proceed if already lying down
	if !is_lying:
		return
	
	# Update the lying direction
	lying_direction = new_direction
	
	# First update the z-index ordering for lying down
	update_z_index_for_lying()
	
	# Update rotation for all sprites immediately without tweens
	for limb_type in limb_sprites:
		var sprite = limb_sprites[limb_type]
		if sprite and limbs_attached[limb_type]:
			apply_immediate_lying_rotation(sprite, new_direction)
	
	# Handle all customization sprites
	if hair_sprite:
		apply_immediate_lying_rotation(hair_sprite, new_direction)
	
	if facial_hair_sprite:
		apply_immediate_lying_rotation(facial_hair_sprite, new_direction)
	
	# Handle underwear and undershirt sprites
	if underwear_sprite and underwear_sprite.visible:
		apply_immediate_lying_rotation(underwear_sprite, new_direction)
	
	if undershirt_sprite and undershirt_sprite.visible:
		apply_immediate_lying_rotation(undershirt_sprite, new_direction)
	
	# Handle all equipment sprites
	for slot in equipment_sprites:
		var equipment_sprite = equipment_sprites[slot]
		if equipment_sprite and equipment_sprite.visible:
			apply_immediate_lying_rotation(equipment_sprite, new_direction)
	
	# Handle any held items
	for slot in [EquipSlot.LEFT_HAND, EquipSlot.RIGHT_HAND]:
		if visible_equipment_sprites.has(slot):
			apply_immediate_lying_rotation(visible_equipment_sprites[slot], new_direction)

# Apply immediate rotation without tweening for direction changes
func apply_immediate_lying_rotation(sprite: Sprite2D, direction: int):
	if sprite == null:
		return
	
	# Calculate target rotation and position based on direction
	var target_rotation = 0.0
	var position_offset = Vector2.ZERO
	
	# Apply different rotations based on direction as specified
	match direction:
		Direction.EAST:
			target_rotation = PI/2.0  # 90 degrees clockwise
		Direction.WEST:
			target_rotation = -PI/2.0  # -90 degrees (counter-clockwise)
		Direction.SOUTH:
			target_rotation = PI  # 180 degrees
		Direction.NORTH:
			target_rotation = 0.0  # No rotation
	
	# Different offsets based on the lying direction
	match direction:
		Direction.SOUTH:
			position_offset = Vector2(lying_offset.x, lying_offset.y)
		Direction.NORTH:
			position_offset = Vector2(-lying_offset.x, lying_offset.y)
		Direction.EAST:
			position_offset = Vector2(0, lying_offset.y * 2)
		Direction.WEST:
			position_offset = Vector2(0, lying_offset.y * 2)
	
	# Apply rotation and position immediately
	sprite.rotation = target_rotation
	sprite.position = Vector2.ZERO + position_offset

# ========== STATUS EFFECT VISUALIZATION ==========
# Add a visual status effect
func add_status_effect(effect_id: String, effect_data: Dictionary):
	# Skip if we already have this effect
	if active_status_effects.has(effect_id):
		update_status_effect(effect_id, effect_data)
		return
	
	# Create status effect icon
	var effect_icon = Sprite2D.new()
	effect_icon.name = "StatusEffect_" + effect_id
	
	# Try to load icon texture based on effect ID
	var icon_path = "res://Assets/StatusEffects/" + effect_id + ".png"
	if ResourceLoader.exists(icon_path):
		effect_icon.texture = load(icon_path)
	else:
		# Use default icon if specific one not found
		var icon_image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
		icon_image.fill(Color(1.0, 0.5, 0.5))  # Default reddish color
		effect_icon.texture = ImageTexture.create_from_image(icon_image)
	
	# Set position based on existing icons
	var icon_count = status_effect_container.get_child_count()
	effect_icon.position = Vector2(icon_count * 18 - 27, -32)  # Position above head, offset by icon count
	
	# Add to container
	status_effect_container.add_child(effect_icon)
	
	# Store reference
	active_status_effects[effect_id] = {
		"icon": effect_icon,
		"data": effect_data
	}
	
	# Create appear animation
	effect_icon.scale = Vector2.ZERO
	effect_icon.modulate.a = 0
	
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.tween_property(effect_icon, "scale", Vector2(1.0, 1.0), 0.4)
	tween.parallel().tween_property(effect_icon, "modulate:a", 1.0, 0.3)
	
	# Add ongoing animation based on effect type
	add_status_effect_animation(effect_icon, effect_id)

# Update an existing status effect
func update_status_effect(effect_id: String, effect_data: Dictionary):
	if !active_status_effects.has(effect_id):
		return
	
	var effect = active_status_effects[effect_id]
	effect.data = effect_data
	
	# Flash the icon to indicate update
	var icon = effect.icon
	if icon:
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(icon, "modulate", Color(1.5, 1.5, 1.5), 0.1)
		tween.tween_property(icon, "modulate", Color(1.0, 1.0, 1.0), 0.2)

# Remove a status effect
func remove_status_effect(effect_id: String):
	if !active_status_effects.has(effect_id):
		return
	
	var effect = active_status_effects[effect_id]
	var icon = effect.icon
	
	if icon:
		# Play disappear animation
		var tween = create_tween()
		tween.set_ease(Tween.EASE_IN)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(icon, "scale", Vector2.ZERO, 0.3)
		tween.parallel().tween_property(icon, "modulate:a", 0, 0.2)
		tween.tween_callback(func(): 
			icon.queue_free()
			active_status_effects.erase(effect_id)
			reorganize_status_effects()
		)

# Add animation to status effect based on type
func add_status_effect_animation(icon: Sprite2D, effect_id: String):
	# Choose animation based on effect type
	match effect_id:
		"burning":
			# Flickering orange-red glow
			var burn_tween = create_tween()
			burn_tween.set_loops()
			burn_tween.set_ease(Tween.EASE_IN_OUT)
			burn_tween.set_trans(Tween.TRANS_SINE)
			burn_tween.tween_property(icon, "modulate", Color(1.5, 0.5, 0.2), 0.3)
			burn_tween.tween_property(icon, "modulate", Color(1.2, 0.2, 0.2), 0.3)
		
		"poisoned":
			# Pulsing green
			var poison_tween = create_tween()
			poison_tween.set_loops()
			poison_tween.set_ease(Tween.EASE_IN_OUT)
			poison_tween.set_trans(Tween.TRANS_SINE)
			poison_tween.tween_property(icon, "modulate", Color(0.2, 1.0, 0.2), 0.8)
			poison_tween.tween_property(icon, "modulate", Color(0.2, 0.6, 0.2), 0.8)
		
		"stunned":
			# Spinning motion
			var stun_tween = create_tween()
			stun_tween.set_loops()
			stun_tween.set_ease(Tween.EASE_IN_OUT)
			stun_tween.set_trans(Tween.TRANS_CUBIC)
			stun_tween.tween_property(icon, "rotation", PI * 2, 1.5)
		
		"bleeding":
			# Dripping animation
			var bleed_tween = create_tween()
			bleed_tween.set_loops()
			bleed_tween.set_ease(Tween.EASE_IN_OUT)
			bleed_tween.set_trans(Tween.TRANS_SINE)
			bleed_tween.tween_property(icon, "position:y", icon.position.y + 3, 0.5)
			bleed_tween.tween_property(icon, "position:y", icon.position.y, 0.3)
		
		"slowed":
			# Slow pulse
			var slow_tween = create_tween()
			slow_tween.set_loops()
			slow_tween.set_ease(Tween.EASE_IN_OUT)
			slow_tween.set_trans(Tween.TRANS_SINE)
			slow_tween.tween_property(icon, "scale", Vector2(0.9, 0.9), 1.0)
			slow_tween.tween_property(icon, "scale", Vector2(1.1, 1.1), 1.0)
		
		_:
			# Default gentle pulse for other effects
			var default_tween = create_tween()
			default_tween.set_loops()
			default_tween.set_ease(Tween.EASE_IN_OUT)
			default_tween.set_trans(Tween.TRANS_SINE)
			default_tween.tween_property(icon, "scale", Vector2(0.95, 0.95), 0.8)
			default_tween.tween_property(icon, "scale", Vector2(1.05, 1.05), 0.8)

# Reorganize status effect icons after removing one
func reorganize_status_effects():
	var index = 0
	for effect_id in active_status_effects:
		var effect = active_status_effects[effect_id]
		var icon = effect.icon
		if icon:
			# Calculate new position
			var target_pos = Vector2(index * 18 - 27, -32)
			
			# Animate to new position
			var tween = create_tween()
			tween.set_ease(Tween.EASE_OUT)
			tween.set_trans(Tween.TRANS_BACK)
			tween.tween_property(icon, "position", target_pos, 0.3)
			
			index += 1

# ========== DAMAGE AND HEALTH VISUALIZATION ==========

# Handle entity being damaged
func _on_body_part_damaged(part_name: String, current_health: float):
	# Map the part name back to a LimbType
	var limb_type = get_limb_type_from_part_name(part_name)
	
	if limb_type == null:
		return
	
	# Check if health is at zero - limb should detach
	if current_health <= 0 and limb_type != LimbType.BODY:
		detach_limb(limb_type)
	else:
		# Show damage effect without detachment
		show_damage_effect(limb_type)

# Helper function to convert part name to LimbType
func get_limb_type_from_part_name(part_name: String) -> int:
	part_name = part_name.to_lower()
	
	match part_name:
		"chest", "torso", "body":
			return LimbType.BODY
		"head":
			return LimbType.HEAD
		"left arm":
			return LimbType.LEFT_ARM
		"right hand":
			return LimbType.RIGHT_HAND
		"left hand":
			return LimbType.LEFT_HAND
		"right arm":
			return LimbType.RIGHT_ARM
		"left leg":
			return LimbType.LEFT_LEG
		"right leg":
			return LimbType.RIGHT_LEG
		"left foot":
			return LimbType.LEFT_FOOT
		"right foot":
			return LimbType.RIGHT_FOOT
		"groin":
			return LimbType.GROIN
		_:
			return -1

# Show damage effect on a limb
func show_damage_effect(limb_type: int):
	if limb_type < 0 or !limb_sprites.has(limb_type):
		return
	
	var sprite = limb_sprites[limb_type]
	if !sprite:
		return
	
	# Flash red
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(sprite, "modulate", Color(1.5, 0.5, 0.5), 0.1)
	tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0), 0.3)
	
	# Slight shake
	var original_pos = sprite.position
	tween.parallel().tween_property(sprite, "position", original_pos + Vector2(1, 0), 0.05)
	tween.tween_property(sprite, "position", original_pos + Vector2(-1, 0), 0.05)
	tween.tween_property(sprite, "position", original_pos, 0.05)
	
	# Check if entity has bleeding status
	if Entity and Entity.has_method("is_bleeding") and Entity.is_bleeding():
		# Add bleeding status effect if not already present
		if !active_status_effects.has("bleeding"):
			add_status_effect("bleeding", {"duration": 10.0})

# Detach a limb based on limb type
func detach_limb(limb_type: LimbType):
	if limb_type == LimbType.BODY:
		return  # Cannot detach body
	
	if not limbs_attached[limb_type]:
		return  # Already detached
	
	# Hide the sprite for the detached limb
	limb_sprites[limb_type].visible = false
	limbs_attached[limb_type] = false
	
	# Emit signal that limb was detached
	emit_signal("limb_detached", LimbType.keys()[limb_type])
	
	# Add status effect for missing limb
	var effect_id = "missing_" + LimbType.keys()[limb_type].to_lower()
	if !active_status_effects.has(effect_id):
		add_status_effect(effect_id, {"duration": -1})  # -1 indicates indefinite

# Reattach a limb
func reattach_limb(limb_type: LimbType):
	if limb_type == LimbType.BODY:
		return  # Body is always attached
	
	if limbs_attached[limb_type]:
		return  # Already attached
	
	# Show the sprite for the reattached limb
	limb_sprites[limb_type].visible = true
	limbs_attached[limb_type] = true
	
	# Update position and frame
	update_sprite_frames()
	update_sprite_z_ordering()
	
	# If lying, apply proper rotation
	if is_lying:
		apply_sprite_rotation_for_lying(limb_sprites[limb_type])
	
	# Emit signal that limb was reattached
	emit_signal("limb_attached", LimbType.keys()[limb_type])
	
	# Remove status effect for missing limb
	var effect_id = "missing_" + LimbType.keys()[limb_type].to_lower()
	if active_status_effects.has(effect_id):
		remove_status_effect(effect_id)
	
	# Add healing effect
	add_status_effect("healing", {"duration": 3.0})

# Create blood splatter effect
func create_blood_splatter():
	# Create blood particles
	var blood_particles = CPUParticles2D.new()
	blood_particles.position = Vector2.ZERO
	blood_particles.z_index = -1  # Below character
	
	# Configure particles
	blood_particles.amount = 20
	blood_particles.lifetime = 0.8
	blood_particles.explosiveness = 0.8
	blood_particles.randomness = 0.5
	blood_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	blood_particles.emission_sphere_radius = 5.0
	blood_particles.direction = Vector2(0, 1)
	blood_particles.spread = 180
	blood_particles.gravity = Vector2(0, 98)
	blood_particles.initial_velocity_min = 40.0
	blood_particles.initial_velocity_max = 80.0
	blood_particles.scale_amount_min = 2.0
	blood_particles.scale_amount_max = 4.0
	blood_particles.color = Color(0.8, 0.0, 0.0)
	blood_particles.one_shot = true
	
	# Add to scene
	add_child(blood_particles)
	
	# Automatically remove after particles finish
	var timer = Timer.new()
	timer.wait_time = 2.0
	timer.one_shot = true
	blood_particles.add_child(timer)
	timer.timeout.connect(func(): blood_particles.queue_free())
	timer.start()

# ========== INTERACTION VISUALIZATION ==========

# Handle entity being clicked - visual highlight
func _on_entity_clicked(entity, mouse_button, shift_pressed, ctrl_pressed, alt_pressed):
	# Only process if this is our entity
	if entity != Entity:
		return
	
	# Get intent from grid controller
	var grid_controller = Entity.get_node_or_null("GridMovementController")
	var intent_type = 0
	if grid_controller and "intent" in grid_controller:
		intent_type = grid_controller.intent
	
	# Calculate direction from character to mouse
	var mouse_pos = get_global_mouse_position()
	var my_pos = global_position if has_method("global_position") else position
	var direction = (mouse_pos - my_pos).normalized()
	
	# Show thrust effect
	show_interaction_thrust(direction, intent_type)
	
	# Show different feedback based on mouse button
	if mouse_button == MOUSE_BUTTON_LEFT:
		show_interaction_feedback("use")
	elif mouse_button == MOUSE_BUTTON_RIGHT:
		show_interaction_feedback("examine")
	
	# Flash briefly
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "modulate", Color(1.2, 1.2, 1.2), 0.1)
	tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0), 0.2)

# Handle interaction started
func _on_interaction_started(entity, interaction_type):
	if entity != Entity:
		return
	
	# Show interaction feedback based on type with thrust
	match interaction_type:
		"use":
			show_interaction_feedback("use")
		"examine":
			show_interaction_feedback("examine")
		"attack":
			show_interaction_feedback("attack")
		"grab":
			show_interaction_feedback("grab")
		"disarm":
			show_interaction_feedback("disarm")
		_:
			show_interaction_feedback("default")

# Handle interaction completed
func _on_interaction_completed(entity, interaction_type, success):
	if entity != Entity:
		return
	
	# Hide interaction feedback
	hide_interaction_feedback()
	
	# Flash success/failure feedback
	if success:
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(self, "modulate", Color(1.2, 1.2, 1.2), 0.1)
		tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0), 0.2)
	else:
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(self, "modulate", Color(1.2, 0.8, 0.8), 0.1)
		tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0), 0.2)

func stop_thrust_animation():
	if thrust_tween and thrust_tween.is_valid():
		thrust_tween.kill()
	
	is_thrusting = false
	
	# Reset all sprite positions and colors
	for limb_type in limb_sprites:
		var sprite = limb_sprites[limb_type]
		if sprite:
			sprite.position = Vector2.ZERO
			sprite.modulate = Color.WHITE
	
	for slot in equipment_sprites:
		var sprite = equipment_sprites[slot]
		if sprite:
			sprite.position = Vector2.ZERO
			sprite.modulate = Color.WHITE

# Show entity as highlighted (when mouse hovers or for targeted actions)
func set_highlighted(highlight: bool):
	if is_highlighted == highlight:
		return
	
	is_highlighted = highlight
	
	if highlight_sprite:
		if highlight:
			# Show highlight with animation
			highlight_sprite.scale = Vector2(1.0, 1.0)
			highlight_sprite.modulate = HIGHLIGHT_COLOR
			highlight_sprite.visible = true
			
			# Create pulse animation
			var tween = create_tween()
			tween.set_ease(Tween.EASE_OUT)
			tween.set_trans(Tween.TRANS_SINE)
			tween.tween_property(highlight_sprite, "scale", Vector2(1.1, 1.1), 0.3)
			tween.parallel().tween_property(highlight_sprite, "modulate:a", 0.7, 0.3)
		else:
			# Hide highlight with animation
			var tween = create_tween()
			tween.set_ease(Tween.EASE_IN)
			tween.set_trans(Tween.TRANS_SINE)
			tween.tween_property(highlight_sprite, "modulate:a", 0, 0.2)
			tween.tween_callback(func(): highlight_sprite.visible = false)
	
	# Emit signal
	emit_signal("highlight_state_changed", highlight)

# Show entity as selected (for current target of action)
func set_selected(selected: bool):
	if is_selected == selected:
		return
	
	is_selected = selected
	
	if selection_outline:
		if selected:
			# Show selection outline with animation
			selection_outline.scale = Vector2(1.2, 1.2)  # Start larger
			selection_outline.modulate.a = 0
			selection_outline.visible = true
			
			# Animate to normal size and opacity
			var tween = create_tween()
			tween.set_ease(Tween.EASE_OUT)
			tween.set_trans(Tween.TRANS_ELASTIC)
			tween.tween_property(selection_outline, "scale", Vector2(1.0, 1.0), 0.4)
			tween.parallel().tween_property(selection_outline, "modulate:a", 1.0, 0.3)
		else:
			# Hide selection outline with animation
			var tween = create_tween()
			tween.set_ease(Tween.EASE_IN)
			tween.set_trans(Tween.TRANS_CUBIC)
			tween.tween_property(selection_outline, "modulate:a", 0, 0.2)
			tween.tween_callback(func(): selection_outline.visible = false)

# Hide interaction feedback
func hide_interaction_feedback():
	if interaction_flash and interaction_flash.visible:
		interaction_flash.visible = false
	
	current_interaction_feedback = ""
	interaction_feedback_timer = 0

# ========== ANIMATION HANDLERS ==========

# Handle changes in movement state
func _on_movement_state_changed(old_state: int, new_state: int):
	# Skip if no entity
	if !Entity:
		return
	
	# Get grid controller reference
	var grid_controller = Entity.get_node_or_null("GridMovementController")
	if !grid_controller:
		return
	
	# Access the enum directly from grid controller if possible
	var IDLE = 0  # MovementState.IDLE
	var MOVING = 1  # MovementState.MOVING  
	var RUNNING = 2  # MovementState.RUNNING
	var STUNNED = 3  # MovementState.STUNNED
	var CRAWLING = 4  # MovementState.CRAWLING
	var FLOATING = 5  # MovementState.FLOATING
	
	# Try to get actual enum values from grid controller if available
	if grid_controller and "MovementState" in grid_controller:
		IDLE = grid_controller.MovementState.IDLE
		MOVING = grid_controller.MovementState.MOVING
		RUNNING = grid_controller.MovementState.RUNNING
		STUNNED = grid_controller.MovementState.STUNNED
		CRAWLING = grid_controller.MovementState.CRAWLING
		FLOATING = grid_controller.MovementState.FLOATING
	
	# Print state change for debugging
	print("SpriteSystem: Movement state changed from ", old_state, " to ", new_state)
	
	# Update animation based on correct state values
	match new_state:
		IDLE:
			print("SpriteSystem: Setting IDLE animations")
			reset_movement_animations()
			
		MOVING:
			print("SpriteSystem: Setting MOVING animations")
			reset_movement_animations()
			apply_walking_animation()
			
		RUNNING:
			print("SpriteSystem: Setting RUNNING animations")
			reset_movement_animations()
			apply_running_animation()
			
		STUNNED:
			print("SpriteSystem: Setting STUNNED animations")
			apply_stun_animation()
			
		CRAWLING:
			print("SpriteSystem: Setting CRAWLING animations")
			# Only apply crawling animations if actually lying down
			if is_lying:
				apply_crawling_animation()
			else:
				# Fix sync issue - apply lying state if it wasn't applied yet
				set_lying_state(true, current_direction)
				# Then apply crawling animation after a small delay
				await get_tree().create_timer(0.1).timeout
				apply_crawling_animation()
				
		FLOATING:
			print("SpriteSystem: Setting FLOATING animations")
			apply_floating_animation()

# Reset any movement animations
func reset_movement_animations():
	print("HumanSpriteSystem: Resetting all movement animations")
	
	# Reset any animations or modifiers applied to limbs
	for limb_type in limb_sprites:
		var sprite = limb_sprites[limb_type]
		if sprite:
			# Cancel any active tweens for this sprite
			if active_tweens.has(sprite) and active_tweens[sprite].is_valid():
				active_tweens[sprite].kill()
				active_tweens.erase(sprite)  # Remove reference to killed tween
			
			# Reset any modifiers like rotations, scales, etc.
			sprite.scale = Vector2.ONE
			
			# Only reset position if not lying down
			if !is_lying:
				sprite.position = Vector2.ZERO
				sprite.rotation = 0.0
			else:
				# If still lying, make sure rotation is maintained
				apply_sprite_rotation_for_lying(sprite)
	
	# Also reset equipment sprites
	for slot in equipment_sprites:
		var sprite = equipment_sprites[slot]
		if sprite and sprite.visible:
			# Cancel any active tweens
			if active_tweens.has(sprite) and active_tweens[sprite].is_valid():
				active_tweens[sprite].kill()
				active_tweens.erase(sprite)  # Remove reference to killed tween
			
			# Reset modifiers
			sprite.scale = Vector2.ONE
			
			# If lying, re-apply lying rotation, otherwise reset
			if is_lying:
				apply_sprite_rotation_for_lying(sprite)
			else:
				sprite.rotation = 0.0
				
	# Remove crawling status effect if not lying anymore
	if !is_lying and active_status_effects.has("crawling"):
		remove_status_effect("crawling")

# Apply walking animation
func apply_walking_animation():
	# Basic walking animation for arms and legs
	for limb_type in [LimbType.LEFT_ARM, LimbType.RIGHT_ARM, LimbType.LEFT_LEG, LimbType.RIGHT_LEG]:
		var sprite = limb_sprites[limb_type]
		if sprite:
			var tween = create_tween()
			tween.set_loops()
			
			var move_distance = 2.0
			var move_time = 0.3
			
			# Different animation based on direction
			match current_direction:
				Direction.SOUTH, Direction.NORTH:
					# When walking up/down, arms and legs swing back and forth
					if limb_type == LimbType.LEFT_ARM or limb_type == LimbType.LEFT_LEG:
						# Left limbs move opposite to right limbs
						tween.tween_property(sprite, "position:x", -move_distance, move_time)
						tween.tween_property(sprite, "position:x", move_distance, move_time)
						tween.tween_property(sprite, "position:x", 0, move_time)
					else:
						tween.tween_property(sprite, "position:x", move_distance, move_time)
						tween.tween_property(sprite, "position:x", -move_distance, move_time)
						tween.tween_property(sprite, "position:x", 0, move_time)
				
				Direction.EAST, Direction.WEST:
					# When walking sideways, limbs move up and down
					if limb_type == LimbType.LEFT_ARM or limb_type == LimbType.LEFT_LEG:
						tween.tween_property(sprite, "position:y", -move_distance, move_time)
						tween.tween_property(sprite, "position:y", move_distance, move_time)
						tween.tween_property(sprite, "position:y", 0, move_time)
					else:
						tween.tween_property(sprite, "position:y", move_distance, move_time)
						tween.tween_property(sprite, "position:y", -move_distance, move_time)
						tween.tween_property(sprite, "position:y", 0, move_time)
			
			# Store tween reference
			active_tweens[sprite] = tween

# Apply running animation
func apply_running_animation():
	# Similar to walking but faster and more pronounced
	for limb_type in [LimbType.LEFT_ARM, LimbType.RIGHT_ARM, LimbType.LEFT_LEG, LimbType.RIGHT_LEG]:
		var sprite = limb_sprites[limb_type]
		if sprite:
			var tween = create_tween()
			tween.set_loops()
			
			var move_distance = 3.5
			var move_time = 0.2
			
			# Different animation based on direction
			match current_direction:
				Direction.SOUTH, Direction.NORTH:
					if limb_type == LimbType.LEFT_ARM or limb_type == LimbType.LEFT_LEG:
						tween.tween_property(sprite, "position:x", -move_distance, move_time)
						tween.tween_property(sprite, "position:x", move_distance, move_time)
						tween.tween_property(sprite, "position:x", 0, move_time)
					else:
						tween.tween_property(sprite, "position:x", move_distance, move_time)
						tween.tween_property(sprite, "position:x", -move_distance, move_time)
						tween.tween_property(sprite, "position:x", 0, move_time)
				
				Direction.EAST, Direction.WEST:
					if limb_type == LimbType.LEFT_ARM or limb_type == LimbType.LEFT_LEG:
						tween.tween_property(sprite, "position:y", -move_distance, move_time)
						tween.tween_property(sprite, "position:y", move_distance, move_time)
						tween.tween_property(sprite, "position:y", 0, move_time)
					else:
						tween.tween_property(sprite, "position:y", move_distance, move_time)
						tween.tween_property(sprite, "position:y", -move_distance, move_time)
						tween.tween_property(sprite, "position:y", 0, move_time)
			
			# Store tween reference
			active_tweens[sprite] = tween
			
	# Add slight bob to body and head
	for limb_type in [LimbType.BODY, LimbType.HEAD]:
		var sprite = limb_sprites[limb_type]
		if sprite:
			var tween = create_tween()
			tween.set_loops()
			
			tween.tween_property(sprite, "position:y", -1.0, 0.2)
			tween.tween_property(sprite, "position:y", 1.0, 0.2)
			tween.tween_property(sprite, "position:y", 0.0, 0.2)
			
			active_tweens[sprite] = tween

# Apply stun animation
func apply_stun_animation():
	reset_movement_animations()
	
	# Apply wobble effect to all limbs
	for limb_type in limb_sprites:
		var sprite = limb_sprites[limb_type]
		if sprite:
			# Wobble rotation
			var tween = create_tween()
			tween.set_loops()
			tween.tween_property(sprite, "rotation", 0.1, 0.2)
			tween.tween_property(sprite, "rotation", -0.1, 0.4)
			tween.tween_property(sprite, "rotation", 0.0, 0.2)
			
			# Store tween reference
			active_tweens[sprite] = tween
	
	# Add status effect for stun visual
	if !active_status_effects.has("stunned"):
		add_status_effect("stunned", {"duration": 2.0})

# Add crawling animation
func apply_crawling_animation():
	print("HumanSpriteSystem: Applying crawling animation")
	
	# Verify character is lying down
	if !is_lying:
		print("HumanSpriteSystem: WARNING - Tried to apply crawling animation while not lying")
		# Fix the sync issue by setting lying state
		set_lying_state(true, current_direction)
		
		# Short delay to let lying state apply
		await get_tree().create_timer(0.1).timeout
	
	# Clear any existing animations
	reset_movement_animations()
	
	# Now apply the crawling animation based on lying state
	if is_lying:
		print("HumanSpriteSystem: Applying lying crawl animation")
		# Lying crawl - subtle arm movement and body drag
		for limb_type in [LimbType.LEFT_ARM, LimbType.RIGHT_ARM]:
			var sprite = limb_sprites[limb_type]
			if sprite:
				# Create arm pulling animation
				var tween = create_tween()
				tween.set_loops()
				
				var arm_offset = 5.0
				var move_time = 0.6  # Slower crawl animation
				
				if lying_direction == Direction.SOUTH or lying_direction == Direction.NORTH:
					# Moving left/right, arms pull forward
					tween.tween_property(sprite, "position:x", sprite.position.x + arm_offset * (1 if limb_type == LimbType.RIGHT_ARM else -1), move_time)
					tween.tween_property(sprite, "position:x", sprite.position.x, move_time)
				else:
					# Moving up/down, arms pull up
					tween.tween_property(sprite, "position:y", sprite.position.y - arm_offset, move_time)
					tween.tween_property(sprite, "position:y", sprite.position.y, move_time)
				
				# Store tween reference
				active_tweens[sprite] = tween
		
		# Subtle body drag animation
		var body_sprite = limb_sprites[LimbType.BODY]
		if body_sprite:
			var tween = create_tween()
			tween.set_loops()
			
			var drag_offset = 2.0
			var move_time = 0.6
			
			if lying_direction == Direction.SOUTH or lying_direction == Direction.NORTH:
				tween.tween_property(body_sprite, "position:x", body_sprite.position.x + drag_offset, move_time)
				tween.tween_property(body_sprite, "position:x", body_sprite.position.x, move_time)
			else:
				tween.tween_property(body_sprite, "position:y", body_sprite.position.y + drag_offset, move_time)
				tween.tween_property(body_sprite, "position:y", body_sprite.position.y, move_time)
			
			active_tweens[body_sprite] = tween
			
		# Add status effect for crawling if not already present
		if !active_status_effects.has("crawling"):
			add_status_effect("crawling", {"duration": -1})  # -1 indicates indefinite
	else:
		print("HumanSpriteSystem: Applying non-lying crawl animation - THIS SHOULD NOT HAPPEN")
		# This is a fallback in case something went wrong with the sync
		# Regular crawling - on hands and knees
		for limb_type in [LimbType.LEFT_LEG, LimbType.RIGHT_LEG, LimbType.LEFT_ARM, LimbType.RIGHT_ARM]:
			var sprite = limb_sprites[limb_type]
			if sprite:
				# Extend limbs slightly
				var tween = create_tween()
				tween.set_loops()
				
				var limb_offset = 4.0
				var move_time = 0.4
				
				if limb_type == LimbType.LEFT_ARM or limb_type == LimbType.LEFT_LEG:
					# Left limbs
					tween.tween_property(sprite, "position:x", sprite.position.x - limb_offset, move_time)
					tween.tween_property(sprite, "position:x", sprite.position.x, move_time)
				else:
					# Right limbs
					tween.tween_property(sprite, "position:x", sprite.position.x + limb_offset, move_time)
					tween.tween_property(sprite, "position:x", sprite.position.x, move_time)
				
				# Store tween reference
				active_tweens[sprite] = tween
				
		# Log warning
		push_warning("HumanSpriteSystem: Applied crawling animation without lying down")

# Apply floating animation
func apply_floating_animation():
	if active_status_effects.has("floating"):
		return  # Already floating, skip reapplying
	
	reset_movement_animations()
	
	# Apply to all limbs and equipment
	
	# Body parts
	for limb_type in limb_sprites:
		var sprite = limb_sprites[limb_type]
		if sprite and !active_tweens.has(sprite):
			var tween = create_tween()
			tween.set_loops()
			
			tween.tween_property(sprite, "position:y", sprite.position.y - 2, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tween.tween_property(sprite, "position:y", sprite.position.y + 2, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			
			active_tweens[sprite] = tween
	
	# Equipment sprites
	for slot in equipment_sprites:
		var sprite = equipment_sprites[slot]
		if sprite and sprite.visible and !active_tweens.has(sprite):
			var tween = create_tween()
			tween.set_loops()
			
			tween.tween_property(sprite, "position:y", sprite.position.y - 2, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tween.tween_property(sprite, "position:y", sprite.position.y + 2, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			
			active_tweens[sprite] = tween

	# Add status effect for floating
	add_status_effect("floating", {"duration": -1})

# ========== UTILITY AND HELPER METHODS ==========

# Get a string representation of the direction
func get_direction_name() -> String:
	match current_direction:
		Direction.SOUTH:
			return "South"
		Direction.NORTH:
			return "North"
		Direction.EAST:
			return "East"
		Direction.WEST:
			return "West"
		_:
			return "Unknown"

# Change visibility of all limbs
func set_all_limbs_visible(visible: bool):
	for limb in limb_sprites.values():
		limb.visible = visible

# Schedule a check for saved character data
func _schedule_customization_check():
	var timer = Timer.new()
	timer.wait_time = 1.0  # One second delay to ensure everything is loaded
	timer.one_shot = true
	add_child(timer)
	timer.timeout.connect(func(): _check_for_saved_customization())
	timer.start()

# Check if there's saved character data to apply
func _check_for_saved_customization():
	print("HumanSpriteSystem: Checking for saved character customization")
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("reapply_character_customization"):
		print("HumanSpriteSystem: Requesting character customization from GameManager")
		var custom_data = game_manager.reapply_character_customization()
		
		if custom_data and custom_data.size() > 0:
			print("HumanSpriteSystem: Received character data with", custom_data.size(), "items, applying now")
			# Actually apply the data that was returned!
			apply_character_data(custom_data)
			print("HumanSpriteSystem: Character customization applied successfully")
		else:
			print("HumanSpriteSystem: No character customization data received or empty data")
	else:
		print("HumanSpriteSystem: No GameManager found or it doesn't have reapply_character_customization method")

# Preview rotation helpers for character customization UI
func rotate_preview(clockwise: bool = true):
	var next_direction = current_direction
	
	if clockwise:
		# Rotate clockwise: SOUTH -> WEST -> NORTH -> EAST -> SOUTH
		match current_direction:
			Direction.SOUTH: next_direction = Direction.WEST
			Direction.WEST: next_direction = Direction.NORTH
			Direction.NORTH: next_direction = Direction.EAST
			Direction.EAST: next_direction = Direction.SOUTH
	else:
		# Rotate counter-clockwise: SOUTH -> EAST -> NORTH -> WEST -> SOUTH
		match current_direction:
			Direction.SOUTH: next_direction = Direction.EAST
			Direction.EAST: next_direction = Direction.NORTH
			Direction.NORTH: next_direction = Direction.WEST
			Direction.WEST: next_direction = Direction.SOUTH
	
	# Set the new direction
	set_direction(next_direction)
	print("HumanSpriteSystem: Rotated to direction: ", Direction.keys()[next_direction])

# Method to handle UI button presses for preview rotation
func rotate_left():
	rotate_preview(false)

func rotate_right():
	rotate_preview(true)

# Connect to click system
func connect_to_click_system():
	# Get our entity
	var entity = get_parent()
	if !entity:
		return
		
	# Find click system
	var click_system = entity.get_node_or_null("GridMovementController/ClickSystem")
	if click_system:
		# Connect to click system signals
		if !click_system.is_connected("interaction_started", Callable(self, "_on_interaction_started")):
			click_system.connect("interaction_started", Callable(self, "_on_interaction_started"))
		
		if !click_system.is_connected("interaction_completed", Callable(self, "_on_interaction_completed")):
			click_system.connect("interaction_completed", Callable(self, "_on_interaction_completed"))
			
		print("HumanSpriteSystem: Connected to ClickSystem")

# Add method to highlight specific body part
func highlight_body_part(zone_name: String):
	# Reset any previous highlighting
	for limb_type in limb_sprites:
		var sprite = limb_sprites[limb_type]
		if sprite:
			sprite.modulate = Color(1, 1, 1)
	
	# Get the appropriate limb based on zone name
	var limb_to_highlight = LimbType.BODY  # Default to body
	
	match zone_name:
		"head":
			limb_to_highlight = LimbType.HEAD
		"chest":
			limb_to_highlight = LimbType.BODY
		"l_arm":
			limb_to_highlight = LimbType.LEFT_ARM
		"r_arm":
			limb_to_highlight = LimbType.RIGHT_ARM
		"l_hand":
			limb_to_highlight = LimbType.LEFT_HAND
		"r_hand":
			limb_to_highlight = LimbType.RIGHT_HAND
		"l_leg":
			limb_to_highlight = LimbType.LEFT_LEG
		"r_leg":
			limb_to_highlight = LimbType.RIGHT_LEG
		"l_foot":
			limb_to_highlight = LimbType.LEFT_FOOT
		"r_foot":
			limb_to_highlight = LimbType.RIGHT_FOOT
	
	# Highlight the selected limb
	var sprite = limb_sprites[limb_to_highlight]
	if sprite:
		# Create highlight effect - subtle yellow tint
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_SINE)
		tween.tween_property(sprite, "modulate", Color(1.2, 1.2, 0.8), 0.2)
		
		# Store the tween to cancel it later if needed
		active_tweens[sprite] = tween
