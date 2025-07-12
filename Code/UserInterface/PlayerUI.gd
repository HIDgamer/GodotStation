extends CanvasLayer
class_name PlayerUI

#region PROPERTIES
#------------------------------------------------------------------
# Click signals
signal item_alt_clicked(item)
signal item_ctrl_clicked(item)
signal item_shift_clicked(item)
signal item_right_clicked(item)
signal item_middle_clicked(item)
signal item_double_clicked(item)

# References to entity and systems
var entity = null
var inventory_system = null
var entity_integration = null
var interaction_system = null
var grid_controller = null

# Mouse tracking for drag and throw
var drag_start_position = Vector2.ZERO
var last_mouse_position = Vector2.ZERO
var is_dragging = false
var throw_minimum_distance = 20  # Minimum distance to consider a throw vs a cancel
var throw_force_multiplier = 2.0

var animation_signal_connections = {}
var pending_animation_updates = {}
var animation_frame_handlers = {}
var current_hand_animations = {
	"LeftHandSlot": "",
	"RightHandSlot": ""
}

# Hand item tracking
var hand_slot_items = {
	"LeftHandSlot": null,
	"RightHandSlot": null
}

# Slot names to EquipSlot enum value mapping
var slot_mapping = {
	"HeadSlot": 0,  # EquipSlot.HEAD
	"EyesSlot": 1,  # EquipSlot.GLASSES
	"MaskSlot": 4,  # EquipSlot.WEAR_MASK
	"EarsSlot": 8,  # EquipSlot.EARS (includes both Ear1Slot and Ear2Slot)
	"NeckSlot": 18,  # EquipSlot.ACCESSORY
	"OuterSlot": 7, # EquipSlot.WEAR_SUIT
	"UniformSlot": 6, # EquipSlot.W_UNIFORM
	"SuitSlot": 7,  # EquipSlot.WEAR_SUIT
	"GlovesSlot": 8, # EquipSlot.GLOVES
	"ArmorSlot": 7, # Map to WEAR_SUIT as fallback
	"ShoesSlot": 10, # EquipSlot.SHOES
	"BackSlot": 3, # EquipSlot.BACK
	"IDSlot": 12,   # EquipSlot.WEAR_ID
	"LeftHandSlot": 13, # EquipSlot.LEFT_HAND
	"RightHandSlot": 14, # EquipSlot.RIGHT_HAND
	"BeltSlot": 15  # EquipSlot.BELT
}

var last_inventory_check_time = 0
var inventory_check_interval = 0.5 # Check every half second for inventory discrepancies

# Reverse mapping from enum values to slot names
var slot_enum_to_name = {}

# Item sprites (overlay on top of slots)
var slot_item_sprites = {}

# Track if slot sprites are animated
var animated_slot_sprites = {}

# Config for animation syncing
var sync_animations = true
var animation_sync_interval = 0.2  # How often to check for animation changes

# Placeholder textures for empty slots
var slot_textures = {}

# Click detection enums
enum ClickType {
	NORMAL,
	SHIFT,
	CTRL,
	ALT,
	SHIFT_CTRL,
	SHIFT_ALT,
	CTRL_ALT,
	SHIFT_CTRL_ALT
}

const MAX_THROW_DISTANCE = 200  # Maximum drag distance to consider for throws
const MAX_THROW_FORCE = 200     # Cap on throw force
const THROW_CURVE_FACTOR = 0.5  # Controls how quickly throw force increases (lower = more gradual)

# Click constants
const DOUBLE_CLICK_TIME = 0.3  # Time window for double clicks in seconds
const DRAG_START_DISTANCE = 5  # Pixels needed to start a drag
const CLICK_COOLDOWN = 0.1  # Cooldown between clicks in seconds

# Click tracking variables
var last_click_position: Vector2 = Vector2.ZERO
var last_click_time: float = 0.0
var last_click_button: int = -1
var click_cooldown_timer: float = 0.0
var is_double_click: bool = false

# Item drag and drop
var dragging_item = null
var dragging_from_slot = null
var drag_preview = null
var drag_origin = Vector2.ZERO
var drag_over_slot = null  # Currently hovered slot during drag
var mouse_down_over_item = false  # Track if mouse was pressed over an item

# Current intent
enum Intent {HELP, DISARM, GRAB, HARM}
var current_intent = Intent.HELP

# UI state tracking
var is_movement_sprint = true
var tooltip_item = null

# Animation constants
const BUTTON_HOVER_SCALE = Vector2(1.1, 1.1)
const BUTTON_PRESS_SCALE = Vector2(0.9, 0.9)
const ANIMATION_DURATION = 0.1
const INTENT_GLOW_COLOR = Color(1.0, 1.0, 1.0, 0.5)
const HAND_INDICATOR_COLOR = Color(0.3, 0.7, 0.9, 0.7)
const EQUIPMENT_MENU_TRANSITION_TIME = 0.25

# Enhanced drag and drop constants
const DRAG_PREVIEW_OPACITY = 0.85
const DRAG_SCALE_DOWN = Vector2(0.95, 0.95)
const DRAG_SCALE_UP = Vector2(1.0, 1.0)
const INVALID_SLOT_OPACITY = 0.4
const VALID_SLOT_HIGHLIGHT = Color(1.2, 1.2, 1.2)

# Enhanced slot visualization
const SLOT_ITEM_SCALE = Vector2(0.9, 0.9)
const SLOT_ITEM_HOVER_SCALE = Vector2(1.0, 1.0)
const SLOT_DEFAULT_OPACITY = 0.8
const SLOT_FILLED_OPACITY = 1.0

# Tweens for animation
var active_tweens = {}

# UI sound effects
enum SoundEffect {CLICK, EQUIP, UNEQUIP, DROP, THROW, ERROR, PICKUP, SUCCESS}
var sound_effects = {
	SoundEffect.CLICK: preload("res://Sound/machines/Click_standard.wav") if ResourceLoader.exists("res://Sound/machines/Click_standard.wav") else null,
	SoundEffect.EQUIP: preload("res://Sound/handling/Uniform.wav") if ResourceLoader.exists("res://Sound/handling/Uniform.wav") else null,
	SoundEffect.UNEQUIP: preload("res://Sound/handling/Armor.wav") if ResourceLoader.exists("res://Sound/handling/Armor.wav") else null,
	SoundEffect.DROP: preload("res://Sound/handling/tape_drop.ogg") if ResourceLoader.exists("res://Sound/handling/tape_drop.ogg") else null,
	SoundEffect.THROW: preload("res://Sound/effects/throwing/throw.wav") if ResourceLoader.exists("res://Sound/effects/throwing/throw.wav") else null,
	SoundEffect.ERROR: preload("res://Sound/machines/terminal_error.ogg") if ResourceLoader.exists("res://Sound/machines/terminal_error.ogg") else null,
	SoundEffect.PICKUP: preload("res://Sound/handling/toolbelt_pickup.ogg") if ResourceLoader.exists("res://Sound/handling/toolbelt_pickup.ogg") else null,
	SoundEffect.SUCCESS: preload("res://Sound/machines/Success.wav") if ResourceLoader.exists("res://Sound/machines/Success.wav") else null
}

# Visibility check timers
var visibility_retry_count = 0
var max_visibility_retries = 5
#------------------------------------------------------------------
#endregion

#region INITIALIZATION
#------------------------------------------------------------------
func _ready():
	print("PlayerUI: Initializing...")
	
	# Register with input priority system
	var input_manager = get_node_or_null("/root/InputPriorityManager")
	if input_manager:
		input_manager.register_ui_system(self)
	
	# Register with ClickSystem
	var click_system = get_node_or_null("/root/ClickSystem")
	if not click_system:
		click_system = get_tree().get_nodes_in_group("click_system").front()
		
	if click_system and click_system.has_method("register_player_ui"):
		click_system.register_player_ui(self)
	
	# Setup reverse mapping
	for slot_name in slot_mapping:
		slot_enum_to_name[slot_mapping[slot_name]] = slot_name
	
	# Configure mouse filtering properly
	setup_ui_filtering()
	
	# Add UI controls to groups for click detection
	register_ui_widgets()
	
	# Set up drag preview
	drag_preview = $Control/DragPreview
	drag_preview.visible = false  # Ensure hidden initially
	
	# Setup input actions
	setup_input_actions()
	
	# Connect all slot buttons
	connect_slot_buttons()
	
	# Connect intent buttons with proper action handling
	connect_intent_buttons()
	
	# Connect hand buttons for direct selection
	connect_hand_buttons()
	
	# Connect equipment button
	if $Control/EquipmentItems/EquipmentButton:
		$Control/EquipmentItems/EquipmentButton.toggled.connect(_on_equipment_button_toggled)
		add_button_hover_animation($Control/EquipmentItems/EquipmentButton)
	
	# Connect movement buttons
	if $Control/MovementButtons/RunButton:
		$Control/MovementButtons/RunButton.pressed.connect(_on_run_button_pressed)
		add_button_hover_animation($Control/MovementButtons/RunButton)
	
	if $Control/MovementButtons/WalkButton:
		$Control/MovementButtons/WalkButton.pressed.connect(_on_walk_button_pressed)
		add_button_hover_animation($Control/MovementButtons/WalkButton)
	
	# Get textures from the scene for placeholders
	cache_slot_textures()
	
	# Setup hand indicators with glowing effect
	setup_hand_indicators()
	
	# Initialize slot item sprites for all slots
	initialize_slot_item_sprites()
	
	# Start looking for player entity
	find_player_entity()

func setup_ui_filtering():
	"""Configure proper mouse filtering for UI elements"""
	# Set the main container to pass through mouse events
	$Control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Make non-interactive containers pass through events
	var ignore_containers = [
		$Control/HandSlots,
		$Control/EquipmentItems,
		$Control/IntentSelector,
		$Control/MovementButtons,
		$Control/MainSlots,
		$Control/PouchSlots
	]
	
	for container in ignore_containers:
		if container:
			container.mouse_filter = Control.MOUSE_FILTER_IGNORE

func validate_ui_state():
	"""Validate UI state against inventory to catch any inconsistencies"""
	if !inventory_system:
		return
		
	# CRITICAL: First check if hand items still exist in inventory
	verify_hand_items_exist()
		
	# Check hand slots for mismatches
	validate_hand_slot("LeftHandSlot", 13)  # LEFT_HAND
	validate_hand_slot("RightHandSlot", 14) # RIGHT_HAND
	
	# Check equipment slots
	for slot_name in slot_mapping:
		# Skip hand slots (already checked)
		if slot_name == "LeftHandSlot" or slot_name == "RightHandSlot":
			continue
			
		# Get actual inventory item
		var equip_slot = slot_mapping.get(slot_name, -1)
		if equip_slot == -1:
			continue
			
		# Special handling for ear slots
		if slot_name == "EarsSlot":
			validate_ear_slots()
			continue
			
		# Get actual item in this slot
		var actual_item = inventory_system.get_item_in_slot(equip_slot)
		
		# Find slot element
		var slot_element = find_slot_element(slot_name)
		if !slot_element:
			continue
			
		# Get item sprite
		var item_sprite = get_item_sprite_for_slot(slot_name)
		if !item_sprite:
			continue
			
		# Check if UI state matches actual inventory
		if actual_item == null && item_sprite.visible:
			# UI shows an item that's not in inventory - fix it
			print("PlayerUI: Fixed ghost item in " + slot_name)
			
			# Force cleanup of the sprite
			cleanup_slot_sprite(slot_name, item_sprite)
		
		# Check for animated sprites that should be updated
		if actual_item && item_sprite.visible && has_animated_sprite(actual_item):
			# Ensure animation is in sync
			refresh_animated_sprite(slot_name, actual_item, item_sprite)

# Validate and fix hand slots
func validate_hand_slot(slot_name, slot_id):
	"""Validate and fix a hand slot if needed"""
	if !inventory_system:
		return
		
	# Get actual item in this slot
	var actual_item = inventory_system.get_item_in_slot(slot_id)
	
	# Get displayed item
	var displayed_item = hand_slot_items[slot_name]
	
	# Check for mismatch
	if actual_item != displayed_item:
		print("PlayerUI: Hand slot mismatch in " + slot_name + ", fixing...")
		
		# Force update the hand slot
		update_hand_item_sprite(slot_name, actual_item)
		
		# Update tracking
		hand_slot_items[slot_name] = actual_item
	
	# Get sprite
	var item_sprite = slot_item_sprites.get(slot_name)
	if !item_sprite:
		return
		
	# Check for ghost sprite (sprite visible but no item)
	if actual_item == null && item_sprite.visible:
		print("PlayerUI: Fixed ghost sprite in " + slot_name)
		cleanup_slot_sprite(slot_name, item_sprite)

# Validate and fix ear slots
func validate_ear_slots():
	"""Validate and fix ear slots if needed"""
	if !inventory_system:
		return
		
	# Get actual item in ear slot
	var equip_slot = slot_mapping.get("EarsSlot", -1)
	var actual_item = inventory_system.get_item_in_slot(equip_slot)
	
	# Check both ear slots
	var ear1_sprite = get_item_sprite_for_slot("EarsSlot", "Ear1ItemSprite")
	var ear2_sprite = get_item_sprite_for_slot("EarsSlot", "Ear2ItemSprite")
	
	# Fix ear1 if needed
	if ear1_sprite && ((actual_item == null && ear1_sprite.visible) || 
					  (actual_item && !ear1_sprite.visible)):
		print("PlayerUI: Fixed ear1 slot display")
		var ear1_slot = find_slot_element("EarsSlot")
		if ear1_slot:
			update_slot_with_item("EarsSlot", ear1_slot, actual_item, "Ear1ItemSprite")
	
	# Fix ear2 if needed
	if ear2_sprite && ((actual_item == null && ear2_sprite.visible) || 
					  (actual_item && !ear2_sprite.visible)):
		print("PlayerUI: Fixed ear2 slot display")
		var ear2_slot = get_node_or_null("Control/EquipmentItems/EquipmentButton/EquipmentSlots/GridContainer/Ear2Slot")
		if ear2_slot:
			update_slot_with_item("EarsSlot", ear2_slot, actual_item, "Ear2ItemSprite")

# Clean up a slot sprite (handles both regular and animated sprites)
func cleanup_slot_sprite(slot_name, sprite):
	"""Clean up a slot sprite with proper signal disconnection"""
	if !sprite:
		return
	
	# Disconnect any animation handlers first
	disconnect_animation_handlers(slot_name)
	
	# Hide immediately
	sprite.visible = false
	
	# Handle specific cleanup for animated sprites
	if sprite is AnimatedSprite2D:
		# Stop animation
		sprite.stop()
		
		# Remove any timers
		for child in sprite.get_children():
			if child is Timer:
				child.queue_free()
		
		# Update animation tracking
		if slot_name in ["LeftHandSlot", "RightHandSlot"]:
			current_hand_animations[slot_name] = ""
		
		# Mark as no longer animated
		if slot_name in animated_slot_sprites:
			animated_slot_sprites[slot_name] = false
	
	# Cancel any active tweens for this sprite
	if sprite in active_tweens and active_tweens[sprite].is_valid():
		active_tweens[sprite].kill()

# Refresh an animated sprite to ensure it stays in sync
func refresh_animated_sprite(slot_name, item, sprite):
	"""Refresh an animated sprite to ensure it stays in sync with the item"""
	if !sprite || !item || !has_animated_sprite(item):
		return
	
	# If this is not an AnimatedSprite2D but should be, recreate it
	if !(sprite is AnimatedSprite2D):
		var slot_element = find_slot_element(slot_name)
		if slot_element:
			var item_animated_sprite = get_item_animated_sprite(item)
			if item_animated_sprite:
				update_or_create_animated_sprite(slot_name, slot_element, item_animated_sprite)
		return
	
	# Otherwise, ensure the animation is in sync
	var item_animated_sprite = get_item_animated_sprite(item)
	if !item_animated_sprite:
		return
		
	# Update sprite frames if needed
	if sprite.sprite_frames != item_animated_sprite.sprite_frames:
		sprite.sprite_frames = item_animated_sprite.sprite_frames
	
	# Sync animation state
	if item_animated_sprite.is_playing():
		# If animation names don't match, update
		if sprite.animation != item_animated_sprite.animation:
			sprite.play(item_animated_sprite.animation)
			sprite.frame = item_animated_sprite.frame
		
		# Make sure speed is the same
		sprite.speed_scale = item_animated_sprite.speed_scale
	else:
		# If item is stopped, make sure UI is stopped too
		sprite.stop()
		sprite.animation = item_animated_sprite.animation
		sprite.frame = item_animated_sprite.frame
#------------------------------------------------------------------
#endregion

#region ITEM SPRITE HANDLING
#------------------------------------------------------------------
# Initialize item sprites for all slots 
func initialize_slot_item_sprites():
	"""Create item sprites as overlays for all slots"""
	# Initialize hand sprites first
	update_hand_item_sprite("LeftHandSlot", null)
	update_hand_item_sprite("RightHandSlot", null)
	
	# Now create item sprites for all equipment slots
	create_equipment_item_sprites()
	
	# Create item sprites for main slots
	create_item_sprite_for_slot("BackSlot", $Control/MainSlots/BackSlot)
	create_item_sprite_for_slot("BeltSlot", $Control/MainSlots/BeltSlot)
	create_item_sprite_for_slot("IDSlot", $Control/MainSlots/IDSlot)
	
	# Create item sprites for pouch slots
	create_item_sprite_for_slot("Pouch1", $Control/PouchSlots/Pouch1)
	create_item_sprite_for_slot("Pouch2", $Control/PouchSlots/Pouch2)

# Create item sprites for equipment slots
func create_equipment_item_sprites():
	"""Create item sprites for all equipment slots"""
	var equipment_slots = [
		"HeadSlot", "EyesSlot", "MaskSlot", "UniformSlot", 
		"ArmorSlot", "SuitSlot", "GlovesSlot", "ShoesSlot"
	]
	
	for slot_name in equipment_slots:
		var slot_rect = get_node_or_null("Control/EquipmentItems/EquipmentButton/EquipmentSlots/GridContainer/" + slot_name)
		if slot_rect:
			create_item_sprite_for_slot(slot_name, slot_rect)
	
	# Special handling for ear slots
	var ear1_slot = get_node_or_null("Control/EquipmentItems/EquipmentButton/EquipmentSlots/GridContainer/Ear1Slot")
	var ear2_slot = get_node_or_null("Control/EquipmentItems/EquipmentButton/EquipmentSlots/GridContainer/Ear2Slot")
	
	if ear1_slot:
		create_item_sprite_for_slot("EarsSlot", ear1_slot, "Ear1ItemSprite")
	
	if ear2_slot:
		create_item_sprite_for_slot("EarsSlot", ear2_slot, "Ear2ItemSprite")

# Create an item sprite overlay for a slot
func create_item_sprite_for_slot(slot_name, slot_rect, custom_name = null):
	"""Create an item sprite as child of a slot"""
	if !slot_rect:
		print("PlayerUI: Cannot create item sprite for null slot rect")
		return
		
	# Create sprite name
	var sprite_name = custom_name if custom_name else slot_name + "ItemSprite"
	
	# Create the sprite
	var item_sprite = Sprite2D.new()
	item_sprite.name = sprite_name
	item_sprite.position = slot_rect.size / 2  # Center in the slot
	item_sprite.scale = SLOT_ITEM_SCALE
	item_sprite.visible = false  # Start hidden
	
	# Add to slot
	slot_rect.add_child(item_sprite)
	
	# Store reference
	if !custom_name:  # Don't store duplicated EarsSlot references
		slot_item_sprites[slot_name] = item_sprite
		animated_slot_sprites[slot_name] = false
	
	print("PlayerUI: Created item sprite for " + slot_name)

# Update active hand visualization
func update_active_hand():
	"""Update the visual indication of which hand is active with ghost item prevention"""
	if !inventory_system:
		print("PlayerUI: Can't update active hand - no inventory system")
		return
	
	# CRITICAL: First verify no ghost items exist
	verify_hand_items_exist()
	
	# Get active hand
	var active_hand = inventory_system.active_hand
	
	print("PlayerUI: Updating active hand indication - active hand is:", active_hand)
	
	# Get the actual items from inventory to verify
	var left_hand_item = inventory_system.get_item_in_slot(13) # LEFT_HAND
	var right_hand_item = inventory_system.get_item_in_slot(14) # RIGHT_HAND
	
	# Double-check our cached references match reality
	if (left_hand_item == null && hand_slot_items["LeftHandSlot"] != null) || (right_hand_item == null && hand_slot_items["RightHandSlot"] != null):
		print("PlayerUI: Detected ghost items during active hand update, fixing...")
		
		# Force update our tracking
		hand_slot_items["LeftHandSlot"] = left_hand_item
		hand_slot_items["RightHandSlot"] = right_hand_item
		
		# Force update the sprites
		update_hand_item_sprite("LeftHandSlot", left_hand_item)
		update_hand_item_sprite("RightHandSlot", right_hand_item)
	
	# Update indicators
	var left_indicator = $Control/HandSlots/LeftHand/ActiveLeftIndicator
	var right_indicator = $Control/HandSlots/RightHand/ActiveRightIndicator
	
	if !left_indicator or !right_indicator:
		print("PlayerUI: Missing hand indicators, can't update active hand")
		return
	
	# First hide both indicators
	left_indicator.visible = false
	right_indicator.visible = false
	
	# Now show only the correct one with improved visibility
	if active_hand == 13:  # EquipSlot.LEFT_HAND
		print("PlayerUI: Left hand is active")
		left_indicator.visible = true
		left_indicator.modulate = Color(0.4, 0.8, 1.0, 0.8)  # Brighter, more visible blue
		
		# Add a border or highlight to the active hand
		$Control/HandSlots/LeftHand.modulate = Color(1.2, 1.2, 1.2)
		$Control/HandSlots/RightHand.modulate = Color(0.9, 0.9, 0.9)
		
		# Set proper z-index for sprites
		if "LeftHandSlot" in slot_item_sprites and "RightHandSlot" in slot_item_sprites:
			# Ensure active hand sprite is on top (higher z_index)
			slot_item_sprites["LeftHandSlot"].z_index = 1
			slot_item_sprites["RightHandSlot"].z_index = 0
			
			# Make sure active item is visible ONLY if it exists
			if left_hand_item != null and hand_slot_items["LeftHandSlot"] != null:
				slot_item_sprites["LeftHandSlot"].visible = true
			else:
				slot_item_sprites["LeftHandSlot"].visible = false
	elif active_hand == 14:  # EquipSlot.RIGHT_HAND
		print("PlayerUI: Right hand is active")
		right_indicator.visible = true
		right_indicator.modulate = Color(0.4, 0.8, 1.0, 0.8)  # Brighter, more visible blue
		
		# Add a border or highlight to the active hand
		$Control/HandSlots/RightHand.modulate = Color(1.2, 1.2, 1.2)
		$Control/HandSlots/LeftHand.modulate = Color(0.9, 0.9, 0.9)
		
		# Set proper z-index for sprites
		if "LeftHandSlot" in slot_item_sprites and "RightHandSlot" in slot_item_sprites:
			# Ensure active hand sprite is on top (higher z_index)
			slot_item_sprites["LeftHandSlot"].z_index = 0
			slot_item_sprites["RightHandSlot"].z_index = 1
			
			# Make sure active item is visible ONLY if it exists
			if right_hand_item != null and hand_slot_items["RightHandSlot"] != null:
				slot_item_sprites["RightHandSlot"].visible = true
			else:
				slot_item_sprites["RightHandSlot"].visible = false
	
	# Special case: if same item in both hands, only show in active hand
	if left_hand_item != null and right_hand_item != null and left_hand_item == right_hand_item:
		if active_hand == 13:  # LEFT_HAND
			# Show in left, hide in right
			if "LeftHandSlot" in slot_item_sprites:
				slot_item_sprites["LeftHandSlot"].visible = true
			if "RightHandSlot" in slot_item_sprites:
				slot_item_sprites["RightHandSlot"].visible = false
		else:
			# Show in right, hide in left
			if "LeftHandSlot" in slot_item_sprites:
				slot_item_sprites["LeftHandSlot"].visible = false
			if "RightHandSlot" in slot_item_sprites:
				slot_item_sprites["RightHandSlot"].visible = true

# Create or update hand item sprite overlays
func update_hand_item_sprite(hand_slot_name, item):
	"""Update hand sprite for an item, with dynamic AnimatedSprite2D handling"""
	print("PlayerUI: Updating hand sprite for " + hand_slot_name)
	
	# First, determine the correct parent container
	var parent_container = null
	
	if hand_slot_name == "LeftHandSlot":
		parent_container = $Control/HandSlots/LeftHand
	elif hand_slot_name == "RightHandSlot":
		parent_container = $Control/HandSlots/RightHand
	
	if !parent_container:
		print("PlayerUI: ERROR - Cannot find parent container for " + hand_slot_name)
		return
	
	# Disconnect any existing animation handlers
	disconnect_animation_handlers(hand_slot_name)
	
	# Reset current animation tracking
	current_hand_animations[hand_slot_name] = ""
	
	# Get existing sprite reference
	var existing_sprite = slot_item_sprites.get(hand_slot_name)
	
	# Handle item removal case
	if !item:
		# Clean up any existing sprite
		if existing_sprite:
			existing_sprite.visible = false
			
			# If it's an AnimatedSprite2D, stop animation
			if existing_sprite is AnimatedSprite2D:
				existing_sprite.stop()
		
		# Update tracking
		hand_slot_items[hand_slot_name] = null
		return
	
	# Check if the item has an AnimatedSprite2D
	var is_animated = has_animated_sprite(item)
	
	# Handle animated items
	if is_animated:
		var item_animated_sprite = get_item_animated_sprite(item)
		
		if item_animated_sprite:
			# Create or update AnimatedSprite2D for this slot
			var ui_animated_sprite = update_or_create_animated_sprite(hand_slot_name, parent_container, item_animated_sprite)
			
			# Store item reference
			hand_slot_items[hand_slot_name] = item
			
			print("PlayerUI: Updated " + hand_slot_name + " with animated item")
			return
	
	# If not animated or couldn't get the AnimatedSprite2D, fall back to regular sprite handling
	
	# Clean up any existing AnimatedSprite2D
	if existing_sprite is AnimatedSprite2D:
		existing_sprite.queue_free()
		
		# Create a new regular Sprite2D
		var item_sprite = Sprite2D.new()
		item_sprite.name = hand_slot_name + "ItemSprite"
		item_sprite.position = Vector2(16, 16)  # Center in the slot
		item_sprite.scale = SLOT_ITEM_SCALE
		
		# Add sprite as a child of the hand
		parent_container.add_child(item_sprite)
		
		# Update reference
		slot_item_sprites[hand_slot_name] = item_sprite
		animated_slot_sprites[hand_slot_name] = false
	
	# Get the regular sprite reference (or the newly created one)
	var sprite = slot_item_sprites.get(hand_slot_name)
	if sprite:
		# Get texture for the item
		var texture = get_item_icon_texture(item)
		if texture:
			sprite.texture = texture
			sprite.visible = true
			
			# Create a fade in tween
			var tween = create_tween()
			tween.set_ease(Tween.EASE_OUT)
			tween.set_trans(Tween.TRANS_CUBIC)
			sprite.modulate.a = 0
			tween.tween_property(sprite, "modulate:a", 1.0, 0.2)
		else:
			sprite.visible = false
	
	# Store item reference
	hand_slot_items[hand_slot_name] = item

# Get the texture for an item's icon
func get_item_icon_texture(item):
	"""Find or create an appropriate texture for an item icon"""
	if !item:
		return null
	
	# Debug: Print item type information
	print("PlayerUI: Getting icon for item: ", item.name, " (", item.get_class(), ")")
	if "item_name" in item:
		print("PlayerUI: Item name: ", item.item_name)
	
	var texture = null
	
	# Try to get from Icon node first (preferred for UI)
	if item.has_node("Icon"):
		var icon_node = item.get_node("Icon")
		if icon_node is Sprite2D and icon_node.texture:
			texture = icon_node.texture
			print("PlayerUI: Found texture from Icon node")
	
	# Try sprite next
	if texture == null and item.has_node("Sprite2D"):
		var sprite_node = item.get_node("Sprite2D")
		if sprite_node is Sprite2D and sprite_node.texture:
			texture = sprite_node.texture
			print("PlayerUI: Found texture from Sprite2D node")
	
	# Try texture property
	if texture == null and "texture" in item:
		texture = item.texture
		if texture:
			print("PlayerUI: Found texture from texture property")
	
	# Try other common child nodes
	if texture == null:
		var potential_sprite_names = ["Visual", "Sprite", "Renderer", "ItemSprite", "Image"]
		for name in potential_sprite_names:
			if item.has_node(name):
				var node = item.get_node(name)
				if node is Sprite2D and node.texture:
					texture = node.texture
					print("PlayerUI: Found texture from", name, "node")
					break
	
	# If still no texture, create a fallback
	if texture == null:
		print("PlayerUI: Creating fallback texture for item")
		var img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.8, 0.2, 0.2))  # Red square as fallback
		
		# Draw a border
		for x in range(32):
			for y in range(32):
				if x == 0 or y == 0 or x == 31 or y == 31:
					img.set_pixel(x, y, Color(0, 0, 0))
		
		texture = ImageTexture.create_from_image(img)
	
	return texture

# Update a slot with an item (supports both regular and animated sprites)
func update_slot_with_item(slot_name, slot_rect, item, sprite_name = null):
	"""Update a slot with an item, supporting both regular and animated sprites"""
	if !slot_rect:
		return
	
	# Get the current sprite to check if it needs cleanup
	var current_sprite = null
	if sprite_name:
		current_sprite = slot_rect.get_node_or_null(sprite_name)
	else:
		current_sprite = slot_rect.get_node_or_null(slot_name + "ItemSprite")
		
		# For hands, use the stored reference
		if (slot_name == "LeftHandSlot" || slot_name == "RightHandSlot") && slot_name in slot_item_sprites:
			current_sprite = slot_item_sprites[slot_name]
	
	# If no item, clean up any existing sprite
	if !item:
		if current_sprite:
			# Clean up the sprite
			cleanup_slot_sprite(slot_name, current_sprite)
			
			# If for hands, update tracking
			if slot_name == "LeftHandSlot" || slot_name == "RightHandSlot":
				hand_slot_items[slot_name] = null
				
			# If this was an animated sprite, we may need to replace it
			if current_sprite is AnimatedSprite2D:
				current_sprite.queue_free()
				create_item_sprite_for_slot(slot_name, slot_rect, sprite_name)
		
		return
	
	# Item exists - check if it has an AnimatedSprite2D
	var is_animated = has_animated_sprite(item)
	
	# Handle differently based on whether item uses AnimatedSprite2D
	if is_animated:
		# Get the AnimatedSprite2D from the item
		var item_animated_sprite = get_item_animated_sprite(item)
		
		if item_animated_sprite:
			# Create or update AnimatedSprite2D in the slot
			var ui_animated_sprite = update_or_create_animated_sprite(slot_name, slot_rect, item_animated_sprite, sprite_name)
			
			# Show the animated sprite
			ui_animated_sprite.visible = true
			ui_animated_sprite.modulate.a = 1.0
			
			# Update hand_slot_items reference if it's a hand slot
			if (slot_name == "LeftHandSlot" || slot_name == "RightHandSlot"):
				hand_slot_items[slot_name] = item
				
			# Create a sync timer if we want animations to stay in sync
			if sync_animations:
				setup_animation_sync(slot_name, item, ui_animated_sprite, item_animated_sprite)
				
			return
	
	# If we get here, it's not an animated sprite or we couldn't handle it
	# Fallback to normal sprite handling
	
	# Get the item sprite (default name or custom)
	var item_sprite = null
	if sprite_name:
		item_sprite = slot_rect.get_node_or_null(sprite_name)
	else:
		item_sprite = slot_rect.get_node_or_null(slot_name + "ItemSprite")
		
		# For hands, use the stored reference
		if (slot_name == "LeftHandSlot" || slot_name == "RightHandSlot") && slot_name in slot_item_sprites:
			item_sprite = slot_item_sprites[slot_name]
			
			# Also update the hand_slot_items reference
			hand_slot_items[slot_name] = item
	
	# If we couldn't find the sprite, create it
	if !item_sprite:
		create_item_sprite_for_slot(slot_name, slot_rect, sprite_name)
		item_sprite = slot_rect.get_node_or_null(sprite_name if sprite_name else slot_name + "ItemSprite")
	
	# If it's an AnimatedSprite2D from before but now we need a regular Sprite2D
	if item_sprite is AnimatedSprite2D && !is_animated:
		# Replace the AnimatedSprite2D with a regular Sprite2D
		cleanup_slot_sprite(slot_name, item_sprite)
		item_sprite.queue_free()
		create_item_sprite_for_slot(slot_name, slot_rect, sprite_name)
		item_sprite = slot_rect.get_node_or_null(sprite_name if sprite_name else slot_name + "ItemSprite")
		
		# Update tracking
		if !sprite_name && slot_name in animated_slot_sprites:
			animated_slot_sprites[slot_name] = false
	
	# Create a tween for smooth transition
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	
	# Get texture for the item
	var texture = get_item_icon_texture(item)
	if texture:
		# Keep slot visible with normal opacity
		slot_rect.modulate.a = SLOT_DEFAULT_OPACITY
		
		# Transition item sprite to new texture
		tween.tween_property(item_sprite, "modulate:a", 0, 0.15)
		tween.tween_callback(func(): 
			item_sprite.texture = texture
			item_sprite.visible = true
		)
		tween.tween_property(item_sprite, "modulate:a", 1.0, 0.25)
		tween.parallel().tween_property(item_sprite, "scale", SLOT_ITEM_SCALE, 0.2)
	else:
		# No texture found - hide the sprite
		if item_sprite && item_sprite.visible:
			tween.tween_property(item_sprite, "modulate:a", 0, 0.2)
			tween.tween_callback(func(): item_sprite.visible = false)
#------------------------------------------------------------------
#endregion

#region ANIMATED SPRITE SUPPORT
#------------------------------------------------------------------
# Check if an item has an AnimatedSprite2D
func has_animated_sprite(item):
	"""Check if an item uses AnimatedSprite2D with focus on 'Icon' node"""
	if !item:
		return false
		
	# First priority: Check for "Icon" node
	if item.has_node("Icon") and item.get_node("Icon") is AnimatedSprite2D:
		return true
		
	# Check for direct AnimatedSprite2D child
	if item.has_node("AnimatedSprite2D"):
		return true
		
	# Check for Sprite that might be an AnimatedSprite2D
	if item.has_node("Sprite2D") and item.get_node("Sprite2D") is AnimatedSprite2D:
		return true
		
	# Check other common visual nodes
	var potential_sprite_names = ["Visual", "Renderer", "ItemSprite", "Image"]
	for name in potential_sprite_names:
		if item.has_node(name) and item.get_node(name) is AnimatedSprite2D:
			return true
	
	return false

# Get the AnimatedSprite2D from an item
func get_item_animated_sprite(item):
	"""Get the AnimatedSprite2D node from an item, prioritizing the 'Icon' node"""
	if !item:
		return null
	
	# First priority: Check for "Icon" (as specified in requirements)
	if item.has_node("Icon") and item.get_node("Icon") is AnimatedSprite2D:
		return item.get_node("Icon")
	
	# Check direct child
	if item.has_node("AnimatedSprite2D"):
		return item.get_node("AnimatedSprite2D")
	
	# Check Sprite
	if item.has_node("Sprite2D") and item.get_node("Sprite2D") is AnimatedSprite2D:
		return item.get_node("Sprite2D")
	
	# Check other common nodes
	var potential_sprite_names = ["Visual", "Renderer", "ItemSprite", "Image"]
	for name in potential_sprite_names:
		if item.has_node(name) and item.get_node(name) is AnimatedSprite2D:
			return item.get_node(name)
	
	return null

# Update or create an AnimatedSprite2D for a slot
func update_or_create_animated_sprite(slot_name, slot_rect, item_animated_sprite, custom_name = null):
	"""Create or update an AnimatedSprite2D for a slot with direct signal connections"""
	var sprite_name = custom_name if custom_name else slot_name + "ItemSprite"
	
	# Check if we already have a sprite
	var existing_sprite = slot_rect.get_node_or_null(sprite_name)
	
	# If we need to replace a regular Sprite2D with AnimatedSprite2D
	if existing_sprite and not existing_sprite is AnimatedSprite2D:
		# Disconnect any existing handlers
		disconnect_animation_handlers(slot_name)
		
		# Remove existing sprite
		existing_sprite.queue_free()
		existing_sprite = null
	
	# Create new AnimatedSprite2D if needed
	if not existing_sprite:
		existing_sprite = AnimatedSprite2D.new()
		existing_sprite.name = sprite_name
		existing_sprite.position = slot_rect.size / 2  # Center in the slot
		existing_sprite.scale = SLOT_ITEM_SCALE
		slot_rect.add_child(existing_sprite)
		
		# Update references
		if !custom_name:
			slot_item_sprites[slot_name] = existing_sprite
			animated_slot_sprites[slot_name] = true
	
	# Update the sprite with item's animation properties
	update_animated_sprite_properties(existing_sprite, item_animated_sprite, slot_name)
	
	# Connect animation signals directly for hand slots (more responsive)
	if slot_name == "LeftHandSlot" or slot_name == "RightHandSlot":
		connect_animation_signals(slot_name, item_animated_sprite, existing_sprite)
	
	return existing_sprite

func update_animated_sprite_properties(target_sprite, source_sprite, slot_name = ""):
	"""Update AnimatedSprite2D properties from source to target with direct property copying"""
	if not source_sprite or not target_sprite or not source_sprite.sprite_frames:
		return
	
	# Copy the sprite frames reference
	target_sprite.sprite_frames = source_sprite.sprite_frames
	
	# Set animation
	if source_sprite.animation != "":
		var animation_name = source_sprite.animation
		
		# Update current animation tracking for hand slots
		if slot_name in ["LeftHandSlot", "RightHandSlot"]:
			current_hand_animations[slot_name] = animation_name
		
		# Set animation and frame
		target_sprite.animation = animation_name
		if source_sprite.sprite_frames.get_frame_count(animation_name) > 0:
			var frame = min(source_sprite.frame, source_sprite.sprite_frames.get_frame_count(animation_name) - 1)
			target_sprite.frame = frame
	
	# Match animation playback state
	if source_sprite.is_playing():
		target_sprite.play(source_sprite.animation)
		target_sprite.speed_scale = source_sprite.speed_scale
	else:
		target_sprite.stop()
	
	# Copy visual properties
	target_sprite.flip_h = source_sprite.flip_h
	target_sprite.flip_v = source_sprite.flip_v
	target_sprite.modulate = source_sprite.modulate
	target_sprite.visible = true

func connect_animation_signals(slot_name, source_sprite, target_sprite):
	"""Connect animation signals from the item sprite to the UI sprite for immediate updates"""
	# First disconnect any existing signals
	disconnect_animation_handlers(slot_name)
	
	# Skip if source sprite is invalid
	if !is_instance_valid(source_sprite):
		return
	
	# Create handlers for this slot
	var animation_changed_handler = func():
		if is_instance_valid(source_sprite) and is_instance_valid(target_sprite):
			# Queue animation update for the next frame to ensure sync
			pending_animation_updates[slot_name] = [target_sprite, source_sprite]
	
	var frame_changed_handler = func():
		if is_instance_valid(source_sprite) and is_instance_valid(target_sprite):
			if target_sprite.animation == source_sprite.animation:
				if source_sprite.sprite_frames.get_frame_count(source_sprite.animation) > 0:
					var frame = min(source_sprite.frame, source_sprite.sprite_frames.get_frame_count(source_sprite.animation) - 1)
					target_sprite.frame = frame
	
	# Connect source sprite signals if they exist
	if source_sprite.has_signal("animation_changed"):
		if !source_sprite.is_connected("animation_changed", animation_changed_handler):
			source_sprite.connect("animation_changed", animation_changed_handler)
	
	if source_sprite.has_signal("frame_changed"):
		if !source_sprite.is_connected("frame_changed", frame_changed_handler):
			source_sprite.connect("frame_changed", frame_changed_handler)
	
	# Store handlers for later disconnection
	animation_signal_connections[slot_name] = source_sprite
	animation_frame_handlers[slot_name] = [animation_changed_handler, frame_changed_handler]

func disconnect_animation_handlers(slot_name):
	"""Disconnect any animation handlers for a slot"""
	if slot_name in animation_signal_connections and is_instance_valid(animation_signal_connections[slot_name]):
		var source_sprite = animation_signal_connections[slot_name]
		var handlers = animation_frame_handlers.get(slot_name, [])
		
		if handlers.size() >= 2:
			if source_sprite.has_signal("animation_changed") and handlers[0]:
				if source_sprite.is_connected("animation_changed", handlers[0]):
					source_sprite.disconnect("animation_changed", handlers[0])
			
			if source_sprite.has_signal("frame_changed") and handlers[1]:
				if source_sprite.is_connected("frame_changed", handlers[1]):
					source_sprite.disconnect("frame_changed", handlers[1])
	
	# Clear the stored connections
	animation_signal_connections.erase(slot_name)
	animation_frame_handlers.erase(slot_name)

# Copy properties from an item's AnimatedSprite2D
func copy_animated_sprite_properties(target_sprite, source_sprite):
	"""Copy AnimatedSprite2D properties from source to target"""
	if not source_sprite or not target_sprite:
		return
		
	# Copy the sprite frames
	target_sprite.sprite_frames = source_sprite.sprite_frames
	
	# Sync current animation if playing
	if source_sprite.is_playing():
		target_sprite.play(source_sprite.animation)
		# Try to sync frame position if possible
		if source_sprite.frame >= 0 and source_sprite.frame < target_sprite.sprite_frames.get_frame_count(source_sprite.animation):
			target_sprite.frame = source_sprite.frame
	else:
		# If not playing, just set the same frame
		target_sprite.animation = source_sprite.animation
		target_sprite.frame = source_sprite.frame
		target_sprite.stop()
	
	# Copy visual properties
	target_sprite.flip_h = source_sprite.flip_h
	target_sprite.flip_v = source_sprite.flip_v
	target_sprite.modulate = source_sprite.modulate

# Setup animation synchronization
func setup_animation_sync(slot_name, item, ui_sprite, item_sprite):
	"""Setup periodic animation sync between item sprite and UI sprite"""
	# Create a timer for sync
	var sync_timer = Timer.new()
	sync_timer.name = "SyncTimer_" + slot_name
	sync_timer.wait_time = animation_sync_interval
	sync_timer.autostart = true
	
	# Connect timer to animation sync function
	sync_timer.timeout.connect(func(): sync_animation(item, ui_sprite, item_sprite))
	
	# Add timer to UI sprite
	ui_sprite.add_child(sync_timer)

# Sync animations
func sync_animation(item, ui_sprite, item_sprite):
	"""Sync animation between item sprite and UI sprite"""
	# First check if item is still valid and has the animated sprite
	if !is_instance_valid(item) or !is_instance_valid(item_sprite) or !is_instance_valid(ui_sprite):
		return
	
	# If the item sprite is playing an animation
	if item_sprite.is_playing():
		# If UI sprite is not playing the same animation, start it
		if !ui_sprite.is_playing() or ui_sprite.animation != item_sprite.animation:
			ui_sprite.play(item_sprite.animation)
		
		# Try to sync frames approximately
		ui_sprite.speed_scale = item_sprite.speed_scale
	else:
		# If item sprite is not playing, stop UI sprite and match frame
		ui_sprite.stop()
		ui_sprite.animation = item_sprite.animation
		ui_sprite.frame = item_sprite.frame
#------------------------------------------------------------------
#endregion

#region SLOT UPDATES
#------------------------------------------------------------------
# Update all UI slots with current inventory data
func update_all_slots():
	if !inventory_system:
		print("PlayerUI: Can't update slots - no inventory system")
		return
	
	print("PlayerUI: Updating all slots")
	
	# Update equipment slots in the menu
	var equipment_slots = [
		"HeadSlot", "EyesSlot", "MaskSlot", "UniformSlot", 
		"ArmorSlot", "SuitSlot", "GlovesSlot", "ShoesSlot", "EarsSlot"
	]
	
	for slot_name in equipment_slots:
		update_equipment_slot(slot_name)
	
	# Update hand slots
	update_both_hand_slots()
	
	# Update main slots (belt, backpack, ID)
	update_generic_slot("BackSlot")
	update_generic_slot("BeltSlot")
	update_generic_slot("IDSlot")
	
	# Update pouch slots
	update_generic_slot("Pouch1")
	update_generic_slot("Pouch2")

# Update a specific equipment slot with animation
func update_equipment_slot(slot_name):
	if !inventory_system:
		return
	
	# Handle special case for EarsSlot - find both Ear1Slot and Ear2Slot
	if slot_name == "EarsSlot":
		update_ear_slots()
		return
	
	# Get the slot texture rect
	var slot_rect = get_node_or_null("Control/EquipmentItems/EquipmentButton/EquipmentSlots/GridContainer/" + slot_name)
	if !slot_rect:
		return
	
	# Get the equip slot enum value
	var equip_slot = slot_mapping.get(slot_name, -1)
	if equip_slot == -1:
		return
	
	# Get item in this slot
	var item = inventory_system.get_item_in_slot(equip_slot)
	
	# Update the slot
	update_slot_with_item(slot_name, slot_rect, item)

# Update generic slots (main slots, pouch slots, etc.)
func update_generic_slot(slot_name):
	if !inventory_system:
		return
	
	# Find the slot rect
	var slot_rect = null
	
	if slot_name in ["BackSlot", "BeltSlot", "IDSlot"]:
		slot_rect = get_node_or_null("Control/MainSlots/" + slot_name)
	elif slot_name.begins_with("Pouch"):
		slot_rect = get_node_or_null("Control/PouchSlots/" + slot_name)
	
	if !slot_rect:
		return
	
	# Get the equip slot enum value if applicable
	var equip_slot = slot_mapping.get(slot_name, -1)
	var item = null
	
	if equip_slot != -1:
		# Get item from inventory system
		item = inventory_system.get_item_in_slot(equip_slot)
	
	# Update the slot
	update_slot_with_item(slot_name, slot_rect, item)

# Special function to update both ear slots
func update_ear_slots():
	if !inventory_system:
		return
	
	var ear1_slot = get_node_or_null("Control/EquipmentItems/EquipmentButton/EquipmentSlots/GridContainer/Ear1Slot")
	var ear2_slot = get_node_or_null("Control/EquipmentItems/EquipmentButton/EquipmentSlots/GridContainer/Ear2Slot")
	
	if !ear1_slot or !ear2_slot:
		return
	
	# Get the ear slot item
	var equip_slot = slot_mapping.get("EarsSlot", -1)
	var item = inventory_system.get_item_in_slot(equip_slot)
	
	# Update both ear slots with the same item
	update_slot_with_item("EarsSlot", ear1_slot, item, "Ear1ItemSprite")
	update_slot_with_item("EarsSlot", ear2_slot, item, "Ear2ItemSprite")

# Force refresh of hand slots
func refresh_hand_slots():
	print("PlayerUI: Forcing refresh of hand slots")
	
	# Get items directly from inventory
	if inventory_system:
		var left_hand_item = inventory_system.get_item_in_slot(13)  # LEFT_HAND
		var right_hand_item = inventory_system.get_item_in_slot(14) # RIGHT_HAND
		
		# Update hand slot items
		update_hand_item_sprite("LeftHandSlot", left_hand_item)
		update_hand_item_sprite("RightHandSlot", right_hand_item)
		
		# Store references
		hand_slot_items["LeftHandSlot"] = left_hand_item
		hand_slot_items["RightHandSlot"] = right_hand_item
	
	update_active_hand()

# Update both hand slots
func update_both_hand_slots():
	print("PlayerUI: Updating both hand slots")
	
	if !inventory_system:
		return
	
	# Get items directly from inventory
	var left_hand_item = inventory_system.get_item_in_slot(13)  # LEFT_HAND
	var right_hand_item = inventory_system.get_item_in_slot(14) # RIGHT_HAND
	
	# Debug info
	print("PlayerUI: Left hand item: ", left_hand_item != null)
	print("PlayerUI: Right hand has item: ", right_hand_item != null)
	
	# Special case: same item in both hands (this is a special case in inventory systems)
	var same_item_in_both_hands = (left_hand_item == right_hand_item) and left_hand_item != null
	
	if same_item_in_both_hands:
		print("PlayerUI: SAME ITEM IN BOTH HANDS - Special rendering needed!")
		
		# For same item in both hands, we'll only show in active hand
		var active_hand = inventory_system.active_hand
		
		if active_hand == 13:  # LEFT_HAND is active
			# Show in left, hide in right
			update_hand_item_sprite("LeftHandSlot", left_hand_item)
			
			# Update right hand but hide the sprite
			if "RightHandSlot" in slot_item_sprites:
				slot_item_sprites["RightHandSlot"].visible = false
			hand_slot_items["RightHandSlot"] = right_hand_item  # Still track the item
		else:
			# Show in right, hide in left
			update_hand_item_sprite("RightHandSlot", right_hand_item)
			
			# Update left hand but hide the sprite
			if "LeftHandSlot" in slot_item_sprites:
				slot_item_sprites["LeftHandSlot"].visible = false
			hand_slot_items["LeftHandSlot"] = left_hand_item  # Still track the item
	else:
		# Normal case - different items or empty slots
		update_hand_item_sprite("LeftHandSlot", left_hand_item)
		update_hand_item_sprite("RightHandSlot", right_hand_item)
	
	# Always update active hand indicator
	update_active_hand()
#------------------------------------------------------------------
#endregion

#region SIGNAL HANDLING
#------------------------------------------------------------------
# On inventory updated signal handler
func _on_inventory_updated():
	print("PlayerUI: Inventory updated signal received")
	
	# CRITICAL: First check if hand items still exist in inventory
	verify_hand_items_exist()
	
	# Refresh hand slots - this is critical for item pickup
	update_both_hand_slots()
	
	# Update all other slots
	update_all_slots()

# Add this new function to verify hand items exist in inventory
func verify_hand_items_exist():
	"""Verify hand items actually exist in inventory and clean up ghost items"""
	if !inventory_system:
		return
		
	# Check left hand
	var left_hand_item = inventory_system.get_item_in_slot(13) # LEFT_HAND
	if left_hand_item == null and hand_slot_items["LeftHandSlot"] != null:
		print("PlayerUI: Detected ghost item in left hand, cleaning up")
		# Force cleanup
		hand_slot_items["LeftHandSlot"] = null
		
		# Force visibility off for the sprite
		if "LeftHandSlot" in slot_item_sprites and slot_item_sprites["LeftHandSlot"]:
			cleanup_slot_sprite("LeftHandSlot", slot_item_sprites["LeftHandSlot"])
			
			# Create a fade-out effect for visual feedback
			var sprite = slot_item_sprites["LeftHandSlot"]
			if sprite and sprite.visible:
				var tween = create_tween()
				tween.set_ease(Tween.EASE_IN)
				tween.set_trans(Tween.TRANS_CUBIC)
				tween.tween_property(sprite, "modulate:a", 0, 0.2)
				tween.tween_callback(func(): sprite.visible = false)
	
	# Check right hand
	var right_hand_item = inventory_system.get_item_in_slot(14) # RIGHT_HAND
	if right_hand_item == null and hand_slot_items["RightHandSlot"] != null:
		print("PlayerUI: Detected ghost item in right hand, cleaning up")
		# Force cleanup
		hand_slot_items["RightHandSlot"] = null
		
		# Force visibility off for the sprite
		if "RightHandSlot" in slot_item_sprites and slot_item_sprites["RightHandSlot"]:
			cleanup_slot_sprite("RightHandSlot", slot_item_sprites["RightHandSlot"])
			
			# Create a fade-out effect for visual feedback
			var sprite = slot_item_sprites["RightHandSlot"]
			if sprite and sprite.visible:
				var tween = create_tween()
				tween.set_ease(Tween.EASE_IN)
				tween.set_trans(Tween.TRANS_CUBIC)
				tween.tween_property(sprite, "modulate:a", 0, 0.2)
				tween.tween_callback(func(): sprite.visible = false)

# On active hand changed signal handler
func _on_active_hand_changed(new_active_hand):
	print("PlayerUI: Active hand changed to: ", new_active_hand)
	
	# First cancel any animations on both hands
	var left_hand = $Control/HandSlots/LeftHand
	var right_hand = $Control/HandSlots/RightHand
	
	if left_hand and left_hand in active_tweens and active_tweens[left_hand].is_valid():
		active_tweens[left_hand].kill()
	
	if right_hand and right_hand in active_tweens and active_tweens[right_hand].is_valid():
		active_tweens[right_hand].kill()
	
	# Update the active hand indicators
	update_active_hand()
	
	# Add a brief flash animation to the newly active hand
	var hand_rect = null
	if new_active_hand == 13:  # LEFT_HAND
		hand_rect = left_hand
	else:
		hand_rect = right_hand
		
	if hand_rect:
		flash_hand_selection(hand_rect)

# Item equipped signal handler
func _on_item_equipped(item, slot):
	print("PlayerUI: Item equipped in slot:", slot)
	
	# Play equip sound effect
	play_sound_effect(SoundEffect.EQUIP)
	
	if slot_enum_to_name.has(slot):
		var slot_name = slot_enum_to_name[slot]
		var slot_element = find_slot_element(slot_name)
		
		if slot_element:
			# Add visual feedback for the equip action
			var tween = create_tween()
			tween.set_ease(Tween.EASE_OUT)
			tween.set_trans(Tween.TRANS_ELASTIC)
			
			# Create a pop-out effect
			tween.tween_property(slot_element, "scale", Vector2(1.2, 1.2), 0.2)
			tween.tween_property(slot_element, "scale", Vector2(1.0, 1.0), 0.3)
	
	# Update specific slot if it's a hand slot
	if slot == 13:  # LEFT_HAND
		update_hand_item_sprite("LeftHandSlot", item)
		
		# Add equip animation effect
		var hand_rect = $Control/HandSlots/LeftHand
		flash_hand_selection(hand_rect)
	elif slot == 14:  # RIGHT_HAND
		update_hand_item_sprite("RightHandSlot", item)
		
		# Add equip animation effect
		var hand_rect = $Control/HandSlots/RightHand
		flash_hand_selection(hand_rect)
	else:
		# For other slots, just update all
		update_all_slots()

# Item unequipped signal handler
func _on_item_unequipped(item, slot):
	print("PlayerUI: Item unequipped from slot:", slot)
	
	# Play unequip sound effect
	play_sound_effect(SoundEffect.UNEQUIP)
	
	if slot_enum_to_name.has(slot):
		var slot_name = slot_enum_to_name[slot]
		
		# IMMEDIATELY clear the cached item reference
		if slot == 13: # LEFT_HAND
			hand_slot_items["LeftHandSlot"] = null
		elif slot == 14: # RIGHT_HAND
			hand_slot_items["RightHandSlot"] = null
		
		# Clean up any animations and sprites before updating
		if slot == 13:  # LEFT_HAND
			var left_sprite = slot_item_sprites.get("LeftHandSlot")
			if left_sprite:
				cleanup_slot_sprite("LeftHandSlot", left_sprite)
		elif slot == 14:  # RIGHT_HAND
			var right_sprite = slot_item_sprites.get("RightHandSlot")
			if right_sprite:
				cleanup_slot_sprite("RightHandSlot", right_sprite)
		else:
			# For other slots, find the slot element and update
			var slot_element = find_slot_element(slot_name)
			var item_sprite = get_item_sprite_for_slot(slot_name)
			
			if slot_element && item_sprite:
				# Clean up the sprite
				cleanup_slot_sprite(slot_name, item_sprite)
				
				# Animate the item being removed
				var tween = create_tween()
				tween.set_ease(Tween.EASE_IN)
				tween.set_trans(Tween.TRANS_CUBIC)
				
				# Return the slot to default state
				tween.tween_property(slot_element, "modulate:a", SLOT_DEFAULT_OPACITY, 0.2)
	
	# Update all slots to ensure consistency
	update_all_slots()

# Slot mouse enter handler
func _on_slot_mouse_entered(slot_name):
	"""Handle mouse entering a slot"""
	# Make sure inventory_system exists
	if inventory_system == null:
		return

	# Store the slot we're hovering over for drag and drop
	drag_over_slot = slot_name
	
	# If we're dragging an item, highlight the slot appropriately
	if dragging_item:
		highlight_slot_for_drag(slot_name)
		return

	# Validate slot mapping exists
	if slot_mapping == null or not slot_mapping.has(slot_name):
		return
	
	var equip_slot = slot_mapping[slot_name]
	var item = inventory_system.get_item_in_slot(equip_slot)

	if item == null:
		# No item, still show slot highlight
		var slot_element = find_slot_element(slot_name)
		if slot_element:
			var slot_tween = create_tween()
			slot_tween.set_ease(Tween.EASE_OUT)
			slot_tween.set_trans(Tween.TRANS_CUBIC)
			slot_tween.tween_property(slot_element, "modulate", Color(1.1, 1.1, 1.1, 1.0), 0.2)
		return

	# Show tooltip with item info
	tooltip_item = item
	
	# Build tooltip text safely
	var tooltip_text = ""
	if "item_name" in item and item.item_name != null:
		tooltip_text = item.item_name
	else:
		tooltip_text = "Item"

	# Add description if available
	if "description" in item and item.description != null:
		tooltip_text += "\n" + str(item.description)
	
	# Add any special properties if available
	if "properties" in item and item.properties is Array and item.properties.size() > 0:
		tooltip_text += "\n\nProperties: " + ", ".join(item.properties)
	
	var tooltip_label = $Control/TooltipPanel/TooltipLabel
	var tooltip_panel = $Control/TooltipPanel
	
	if tooltip_label and tooltip_panel:
		tooltip_label.text = tooltip_text

		# Position tooltip at mouse
		var viewport = get_viewport()
		if viewport:
			tooltip_panel.global_position = viewport.get_mouse_position() + Vector2(20, 20)

		# Resize tooltip panel after frame
		await get_tree().process_frame  # Wait for label to resize
		tooltip_panel.size = tooltip_label.size + Vector2(20, 20)

		# Animate tooltip showing
		tooltip_panel.modulate.a = 0
		tooltip_panel.visible = true

		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(tooltip_panel, "modulate:a", 1.0, 0.2)

	# Highlight the slot and item to indicate hover
	var slot_element = find_slot_element(slot_name)
	if slot_element:
		var highlight_tween = create_tween()
		highlight_tween.set_ease(Tween.EASE_OUT)
		highlight_tween.set_trans(Tween.TRANS_CUBIC)
		highlight_tween.tween_property(slot_element, "modulate", Color(1.2, 1.2, 1.2, 1.0), 0.2)

	# Make item sprite a bit larger on hover
	var item_sprite = get_item_sprite_for_slot(slot_name)
	if item_sprite and item_sprite.visible:
		var sprite_tween = create_tween()
		sprite_tween.set_ease(Tween.EASE_OUT)
		sprite_tween.set_trans(Tween.TRANS_BACK)
		sprite_tween.tween_property(item_sprite, "scale", SLOT_ITEM_HOVER_SCALE, 0.2)

# Handle mouse exiting a slot
func _on_slot_mouse_exited(slot_name):
	"""Handle mouse exiting a slot"""
	# Clear drag over slot if we're exiting the current one
	if drag_over_slot == slot_name:
		drag_over_slot = null
		
	# Reset highlighting if we were dragging
	if dragging_item:
		reset_slot_highlight(slot_name)
	
	# Hide tooltip with animation
	if $Control/TooltipPanel.visible:
		var tween = create_tween()
		tween.set_ease(Tween.EASE_IN)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property($Control/TooltipPanel, "modulate:a", 0, 0.2)
		tween.tween_callback(func(): 
			$Control/TooltipPanel.visible = false
			tooltip_item = null
		)
		
	# Reset slot highlight
	var slot_element = find_slot_element(slot_name)
	if slot_element and !dragging_item:
		var highlight_tween = create_tween()
		highlight_tween.set_ease(Tween.EASE_OUT)
		highlight_tween.set_trans(Tween.TRANS_CUBIC)
		highlight_tween.tween_property(slot_element, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.2)
	
	# Reset item sprite scale on exit
	var item_sprite = get_item_sprite_for_slot(slot_name)
	if item_sprite and item_sprite.visible:
		var sprite_tween = create_tween()
		sprite_tween.set_ease(Tween.EASE_OUT)
		sprite_tween.set_trans(Tween.TRANS_CUBIC)
		sprite_tween.tween_property(item_sprite, "scale", SLOT_ITEM_SCALE, 0.2)

# Intent toggled handler - fixed to properly handle selection states
func _on_intent_toggled(pressed, intent):
	print("PlayerUI: Intent toggled:", intent, " pressed:", pressed)
	
	if !pressed:
		# Don't allow untoggling the current intent
		if intent == current_intent:
			get_intent_button(intent).set_pressed_no_signal(true)
		return
	
	# Only continue if this is a newly selected intent or different from current
	if intent == current_intent:
		return
		
	# Play button sound
	play_sound_effect(SoundEffect.CLICK)
	
	# Set the new intent
	current_intent = intent
	
	# Cancel any existing animations on all buttons
	for i in range(4):  # 4 intents
		var button = get_intent_button(i)
		if button:
			if button in active_tweens and active_tweens[button].is_valid():
				active_tweens[button].kill()
	
	# Update all intent buttons to reflect new state
	update_intent_buttons()
	
	# Apply the intent to the entity
	apply_current_intent()

# Equipment button toggle handler with animation
func _on_equipment_button_toggled(toggled_on):
	print("PlayerUI: Equipment button toggled:", toggled_on)
	
	var equipment_menu = $Control/EquipmentItems/EquipmentButton/EquipmentSlots
	if !equipment_menu:
		return
		
	# Cancel any active tween
	if equipment_menu in active_tweens and active_tweens[equipment_menu].is_valid():
		active_tweens[equipment_menu].kill()
	
	# Create new tween
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	
	# Store tween reference
	active_tweens[equipment_menu] = tween
	
	# Play button click sound
	play_sound_effect(SoundEffect.CLICK)
	
	if toggled_on:
		# Show menu with fade-in and scale animation
		equipment_menu.visible = true
		equipment_menu.modulate.a = 0
		equipment_menu.scale = Vector2(0.8, 0.8)
		
		tween.tween_property(equipment_menu, "modulate:a", 1.0, EQUIPMENT_MENU_TRANSITION_TIME)
		tween.parallel().tween_property(equipment_menu, "scale", Vector2.ONE, EQUIPMENT_MENU_TRANSITION_TIME)
	else:
		# Hide menu with fade-out and scale animation
		tween.tween_property(equipment_menu, "modulate:a", 0, EQUIPMENT_MENU_TRANSITION_TIME)
		tween.parallel().tween_property(equipment_menu, "scale", Vector2(0.8, 0.8), EQUIPMENT_MENU_TRANSITION_TIME)
		tween.tween_callback(func(): equipment_menu.visible = false)

# Run button pressed handler
func _on_run_button_pressed():
	print("PlayerUI: Run button pressed")
	play_sound_effect(SoundEffect.CLICK)
	
	is_movement_sprint = true
	
	# Animate button selection
	var run_button = $Control/MovementButtons/RunButton
	var walk_button = $Control/MovementButtons/WalkButton
	
	if run_button and walk_button:
		var tween_run = create_tween()
		var tween_walk = create_tween()
		tween_run.set_ease(Tween.EASE_OUT)
		tween_walk.set_ease(Tween.EASE_OUT)
		
		tween_run.tween_property(run_button, "modulate", Color(1.5, 1.5, 1.5, 1.0), 0.2)
		tween_walk.tween_property(walk_button, "modulate", Color(0.7, 0.7, 0.7, 1.0), 0.2)
	
	update_movement_buttons()
	apply_movement_mode()

# Walk button pressed handler
func _on_walk_button_pressed():
	print("PlayerUI: Walk button pressed")
	play_sound_effect(SoundEffect.CLICK)
	
	is_movement_sprint = false
	
	# Animate button selection
	var run_button = $Control/MovementButtons/RunButton
	var walk_button = $Control/MovementButtons/WalkButton
	
	if run_button and walk_button:
		var tween_run = create_tween()
		var tween_walk = create_tween()
		tween_run.set_ease(Tween.EASE_OUT)
		tween_walk.set_ease(Tween.EASE_OUT)
		
		tween_run.tween_property(run_button, "modulate", Color(0.7, 0.7, 0.7, 1.0), 0.2)
		tween_walk.tween_property(walk_button, "modulate", Color(1.5, 1.5, 1.5, 1.0), 0.2)
	
	update_movement_buttons()
	apply_movement_mode()

# Button hover animation
func _on_button_hover(button, is_hovering):
	"""Handle button hover state changes"""
	if !button:
		return
		
	# Cancel any existing tween for this button
	if button in active_tweens and active_tweens[button].is_valid():
		active_tweens[button].kill()
	
	# Create new tween
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	
	# Store the tween reference
	active_tweens[button] = tween
	
	if is_hovering:
		# Hover animation - scale up
		tween.tween_property(button, "scale", BUTTON_HOVER_SCALE, ANIMATION_DURATION)
		
		# Add a subtle brightness increase
		if button is TextureButton:
			tween.parallel().tween_property(button, "modulate", Color(1.2, 1.2, 1.2), ANIMATION_DURATION)
		else:
			tween.parallel().tween_property(button, "modulate:a", 0.9, ANIMATION_DURATION)
	else:
		# Return to normal
		tween.tween_property(button, "scale", Vector2.ONE, ANIMATION_DURATION)
		
		# Reset brightness
		tween.parallel().tween_property(button, "modulate", Color(1.0, 1.0, 1.0), ANIMATION_DURATION)

# Button press animation
func _on_button_pressed(button):
	"""Handle button press animation"""
	if !button:
		return
	
	# Play click sound
	play_sound_effect(SoundEffect.CLICK)
		
	# Cancel any existing tween for this button
	if button in active_tweens and active_tweens[button].is_valid():
		active_tweens[button].kill()
	
	# Create new tween
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BOUNCE)
	
	# Store the tween reference
	active_tweens[button] = tween
	
	# Press animation - scale down and darken slightly
	tween.tween_property(button, "scale", BUTTON_PRESS_SCALE, ANIMATION_DURATION)
	
	# Add a subtle darkening
	if button is TextureButton:
		tween.parallel().tween_property(button, "modulate", Color(0.9, 0.9, 0.9), ANIMATION_DURATION)
	else:
		tween.parallel().tween_property(button, "modulate:a", 0.8, ANIMATION_DURATION)

# Button release animation
func _on_button_released(button):
	"""Handle button release animation"""
	if !button:
		return
		
	# Return to hover state
	_on_button_hover(button, true)
#------------------------------------------------------------------
#endregion

#region UI SETUP
#------------------------------------------------------------------
# Setup glowing hand indicators
func setup_hand_indicators():
	"""Set up the hand indicator visuals"""
	var left_indicator = $Control/HandSlots/LeftHand/ActiveLeftIndicator
	var right_indicator = $Control/HandSlots/RightHand/ActiveRightIndicator
	
	if left_indicator and right_indicator:
		# Setup a subtle pulsing glow for active hand
		left_indicator.modulate = HAND_INDICATOR_COLOR
		right_indicator.modulate = HAND_INDICATOR_COLOR
		
		# Initially hide both indicators
		left_indicator.visible = false
		right_indicator.visible = false
	else:
		print("PlayerUI: Missing hand indicators, can't set up properly")

# Add hover animation to a button
func add_button_hover_animation(button):
	"""Add hover animations to a button"""
	if button:
		if not button.is_connected("mouse_entered", Callable(self, "_on_button_hover")):
			button.mouse_entered.connect(func(): _on_button_hover(button, true))
		
		if not button.is_connected("mouse_exited", Callable(self, "_on_button_hover")):
			button.mouse_exited.connect(func(): _on_button_hover(button, false))
		
		if not button.is_connected("button_down", Callable(self, "_on_button_pressed")):
			button.button_down.connect(func(): _on_button_pressed(button))
		
		if not button.is_connected("button_up", Callable(self, "_on_button_released")):
			button.button_up.connect(func(): _on_button_released(button))

# Connect slot buttons and setup mouse event handlers
func connect_slot_buttons():
	print("PlayerUI: Connecting slot buttons")
	
	# Connect equipment slot buttons inside the equipment menu
	var equipment_slots = [
		"HeadSlot", "EyesSlot", "MaskSlot", "UniformSlot", 
		"ArmorSlot", "SuitSlot", "GlovesSlot", "ShoesSlot"
	]
	
	# Special handling for ear slots which have different names
	var ear_slots = ["Ear1Slot", "Ear2Slot"]
	
	for slot_name in equipment_slots:
		var button_path = "Control/EquipmentItems/EquipmentButton/EquipmentSlots/GridContainer/%s/%sButton" % [slot_name, slot_name]
		var button = get_node_or_null(button_path)
		if button:
			# Connect mouse events for better drag and drop
			if not button.is_connected("mouse_entered", Callable(self, "_on_slot_mouse_entered")):
				button.mouse_entered.connect(_on_slot_mouse_entered.bind(slot_name))
			
			if not button.is_connected("mouse_exited", Callable(self, "_on_slot_mouse_exited")):
				button.mouse_exited.connect(_on_slot_mouse_exited.bind(slot_name))
	
	# Connect ear slots
	for ear_slot in ear_slots:
		var button_path = "Control/EquipmentItems/EquipmentButton/EquipmentSlots/GridContainer/%s/EarsSlotButton" % ear_slot
		var button = get_node_or_null(button_path)
		if button:
			if not button.is_connected("mouse_entered", Callable(self, "_on_slot_mouse_entered")):
				button.mouse_entered.connect(_on_slot_mouse_entered.bind("EarsSlot"))
			
			if not button.is_connected("mouse_exited", Callable(self, "_on_slot_mouse_exited")):
				button.mouse_exited.connect(_on_slot_mouse_exited.bind("EarsSlot"))
	
	# Connect main slots (belt, backpack, ID)
	var main_slots = ["BackSlot", "BeltSlot", "IDSlot"]
	for slot_name in main_slots:
		var button_path = "Control/MainSlots/%s/%sButton" % [slot_name, slot_name]
		var button = get_node_or_null(button_path)
		if button:
			if not button.is_connected("mouse_entered", Callable(self, "_on_slot_mouse_entered")):
				button.mouse_entered.connect(_on_slot_mouse_entered.bind(slot_name))
			
			if not button.is_connected("mouse_exited", Callable(self, "_on_slot_mouse_exited")):
				button.mouse_exited.connect(_on_slot_mouse_exited.bind(slot_name))
	
	# Connect pouch slots
	for i in range(1, 3):
		var pouch_name = "Pouch%d" % i
		var button_path = "Control/PouchSlots/%s/%sButton" % [pouch_name, pouch_name]
		var button = get_node_or_null(button_path)
		if button:
			if not button.is_connected("mouse_entered", Callable(self, "_on_slot_mouse_entered")):
				button.mouse_entered.connect(_on_slot_mouse_entered.bind(pouch_name))
			
			if not button.is_connected("mouse_exited", Callable(self, "_on_slot_mouse_exited")):
				button.mouse_exited.connect(_on_slot_mouse_exited.bind(pouch_name))

# Connect hand buttons for direct interaction
func connect_hand_buttons():
	print("PlayerUI: Connecting hand buttons")
	
	# Connect hand buttons for direct selection
	var left_hand_button = $Control/HandSlots/LeftHand
	var right_hand_button = $Control/HandSlots/RightHand
	
	if left_hand_button:
		if not left_hand_button.is_connected("mouse_entered", Callable(self, "_on_slot_mouse_entered")):
			left_hand_button.mouse_entered.connect(_on_slot_mouse_entered.bind("LeftHandSlot"))
		
		if not left_hand_button.is_connected("mouse_exited", Callable(self, "_on_slot_mouse_exited")):
			left_hand_button.mouse_exited.connect(_on_slot_mouse_exited.bind("LeftHandSlot"))
		
		# Add hover animation
		add_button_hover_animation(left_hand_button)
	
	if right_hand_button:
		if not right_hand_button.is_connected("mouse_entered", Callable(self, "_on_slot_mouse_entered")):
			right_hand_button.mouse_entered.connect(_on_slot_mouse_entered.bind("RightHandSlot"))
		
		if not right_hand_button.is_connected("mouse_exited", Callable(self, "_on_slot_mouse_exited")):
			right_hand_button.mouse_exited.connect(_on_slot_mouse_exited.bind("RightHandSlot"))
		
		# Add hover animation
		add_button_hover_animation(right_hand_button)

# Connect intent buttons and setup actions
func connect_intent_buttons():
	print("PlayerUI: Connecting intent buttons")
	
	# Connect intent buttons with proper action inputs
	var help_button = $Control/IntentSelector/HelpIntent
	var disarm_button = $Control/IntentSelector/DisarmIntent
	var grab_button = $Control/IntentSelector/GrabIntent
	var harm_button = $Control/IntentSelector/HarmIntent
	
	if help_button:
		if not help_button.is_connected("toggled", Callable(self, "_on_intent_toggled")):
			help_button.toggled.connect(_on_intent_toggled.bind(Intent.HELP))
		add_button_hover_animation(help_button)
	
	if disarm_button:
		if not disarm_button.is_connected("toggled", Callable(self, "_on_intent_toggled")):
			disarm_button.toggled.connect(_on_intent_toggled.bind(Intent.DISARM))
		add_button_hover_animation(disarm_button)
	
	if grab_button:
		if not grab_button.is_connected("toggled", Callable(self, "_on_intent_toggled")):
			grab_button.toggled.connect(_on_intent_toggled.bind(Intent.GRAB))
		add_button_hover_animation(grab_button)
	
	if harm_button:
		if not harm_button.is_connected("toggled", Callable(self, "_on_intent_toggled")):
			harm_button.toggled.connect(_on_intent_toggled.bind(Intent.HARM))
		add_button_hover_animation(harm_button)
	
	# Set up intent selection number key shortcuts
	setup_intent_actions()

# Cache textures from the scene to use as placeholders
func cache_slot_textures():
	"""Cache textures from the scene for slots"""
	# Equipment slots
	var equipment_slots = ["HeadSlot", "EyesSlot", "MaskSlot", "UniformSlot", "ArmorSlot", "SuitSlot", "GlovesSlot", "ShoesSlot"]
	for slot_name in equipment_slots:
		var texture_rect = get_node_or_null("Control/EquipmentItems/EquipmentButton/EquipmentSlots/GridContainer/" + slot_name)
		if texture_rect and texture_rect.texture:
			slot_textures[slot_name] = texture_rect.texture
	
	# Special handling for ear slots which have different names in scene
	var ear1_slot = get_node_or_null("Control/EquipmentItems/EquipmentButton/EquipmentSlots/GridContainer/Ear1Slot")
	var ear2_slot = get_node_or_null("Control/EquipmentItems/EquipmentButton/EquipmentSlots/GridContainer/Ear2Slot")
	if ear1_slot and ear1_slot.texture:
		slot_textures["EarsSlot"] = ear1_slot.texture
	
	# Pouch slots
	if $Control/PouchSlots/Pouch1 and $Control/PouchSlots/Pouch1.texture:
		slot_textures["Pouch1"] = $Control/PouchSlots/Pouch1.texture
	
	if $Control/PouchSlots/Pouch2 and $Control/PouchSlots/Pouch2.texture:
		slot_textures["Pouch2"] = $Control/PouchSlots/Pouch2.texture
	
	# Main slots (belt, backpack, ID)
	if $Control/MainSlots/BackSlot and $Control/MainSlots/BackSlot.texture:
		slot_textures["BackSlot"] = $Control/MainSlots/BackSlot.texture
	
	if $Control/MainSlots/BeltSlot and $Control/MainSlots/BeltSlot.texture:
		slot_textures["BeltSlot"] = $Control/MainSlots/BeltSlot.texture
	
	if $Control/MainSlots/IDSlot and $Control/MainSlots/IDSlot.texture:
		slot_textures["IDSlot"] = $Control/MainSlots/IDSlot.texture
	
	# Hand slots
	if $Control/HandSlots/LeftHand/LeftHandSlot and $Control/HandSlots/LeftHand/LeftHandSlot.texture:
		slot_textures["LeftHandSlot"] = $Control/HandSlots/LeftHand/LeftHandSlot.texture
	
	if $Control/HandSlots/RightHand/RightHandSlot and $Control/HandSlots/RightHand/RightHandSlot.texture:
		slot_textures["RightHandSlot"] = $Control/HandSlots/RightHand/RightHandSlot.texture

# Update intent buttons to reflect current selection
func update_intent_buttons():
	"""Update intent button visuals to match current intent"""
	print("PlayerUI: Updating intent buttons, current intent:", current_intent)
	
	# Set the correct button as pressed
	var help_button = $Control/IntentSelector/HelpIntent
	var disarm_button = $Control/IntentSelector/DisarmIntent
	var grab_button = $Control/IntentSelector/GrabIntent
	var harm_button = $Control/IntentSelector/HarmIntent
	
	if help_button and disarm_button and grab_button and harm_button:
		# Updated: Set button_pressed property directly without triggering signals
		help_button.set_pressed_no_signal(current_intent == Intent.HELP)
		disarm_button.set_pressed_no_signal(current_intent == Intent.DISARM)
		grab_button.set_pressed_no_signal(current_intent == Intent.GRAB)
		harm_button.set_pressed_no_signal(current_intent == Intent.HARM)
		
		# Reset all button visuals first
		help_button.modulate = Color(1.0, 1.0, 1.0, 1.0)
		disarm_button.modulate = Color(1.0, 1.0, 1.0, 1.0)
		grab_button.modulate = Color(1.0, 1.0, 1.0, 1.0)
		harm_button.modulate = Color(1.0, 1.0, 1.0, 1.0)
		
		# Now highlight only the active one
		match current_intent:
			Intent.HELP:
				help_button.modulate = Color(1.2, 1.2, 1.2, 1.0)
				add_intent_pulse_animation(help_button)
			Intent.DISARM:
				disarm_button.modulate = Color(1.2, 1.2, 1.2, 1.0)
				add_intent_pulse_animation(disarm_button)
			Intent.GRAB:
				grab_button.modulate = Color(1.2, 1.2, 1.2, 1.0)
				add_intent_pulse_animation(grab_button)
			Intent.HARM:
				harm_button.modulate = Color(1.2, 1.2, 1.2, 1.0)
				add_intent_pulse_animation(harm_button)
	else:
		print("PlayerUI: Some intent buttons are missing")

# Add pulsing animation to active intent button
func add_intent_pulse_animation(button):
	"""Add pulsing animation to the active intent button"""
	if !button:
		return
	
	# Cancel any existing tween
	if button in active_tweens and active_tweens[button].is_valid():
		active_tweens[button].kill()
	
	# Create pulsing animation
	var tween = create_tween()
	tween.set_loops()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	
	# Store the tween reference
	active_tweens[button] = tween
	
	# Pulse between bright and normal
	tween.tween_property(button, "modulate", Color(1.3, 1.3, 1.3, 1.0), 0.8)
	tween.tween_property(button, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.8)

# Update movement buttons based on current movement state
func update_movement_buttons():
	"""Update movement button states"""
	if !$Control/MovementButtons/RunButton or !$Control/MovementButtons/WalkButton:
		return
		
	# Update run/walk buttons based on state
	$Control/MovementButtons/RunButton.disabled = is_movement_sprint
	$Control/MovementButtons/WalkButton.disabled = !is_movement_sprint
	
	# Add visual feedback
	var run_button = $Control/MovementButtons/RunButton
	var walk_button = $Control/MovementButtons/WalkButton
	
	if is_movement_sprint:
		# Running mode active
		run_button.modulate = Color(1.2, 1.2, 1.2, 1.0)
		walk_button.modulate = Color(0.7, 0.7, 0.7, 1.0)
	else:
		# Walking mode active
		run_button.modulate = Color(0.7, 0.7, 0.7, 1.0)
		walk_button.modulate = Color(1.2, 1.2, 1.2, 1.0)

# Setup all input actions required for inventory
func setup_input_actions():
	print("PlayerUI: Setting up input actions")
	
	# Setup intent actions
	setup_intent_actions()
	
	# Add actions for hand switching and item use
	var actions = [
		["switch_hand", KEY_X],
		["use_item", KEY_Z],
		["drop_item", KEY_Q]
	]
	
	for action_info in actions:
		var action_name = action_info[0]
		var key_code = action_info[1]
		
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
			var event = InputEventKey.new()
			event.keycode = key_code
			InputMap.action_add_event(action_name, event)

# Setup keyboard shortcuts for intent selection
func setup_intent_actions():
	var intent_actions = [
		["mode_help", KEY_1],
		["mode_disarm", KEY_2],
		["mode_grab", KEY_3], 
		["mode_harm", KEY_4]
	]
	
	for action_info in intent_actions:
		var action_name = action_info[0]
		var key_code = action_info[1]
		
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
			var event = InputEventKey.new()
			event.keycode = key_code
			InputMap.action_add_event(action_name, event)

# Register all buttons for UI click detection
func register_ui_buttons():
	"""Register all buttons for UI interaction handling"""
	# Add buttons to a group for detection
	var buttons = []
	
	# Intent buttons
	if $Control/IntentSelector:
		if $Control/IntentSelector/HelpIntent:
			buttons.append($Control/IntentSelector/HelpIntent)
		if $Control/IntentSelector/DisarmIntent:
			buttons.append($Control/IntentSelector/DisarmIntent)
		if $Control/IntentSelector/GrabIntent:
			buttons.append($Control/IntentSelector/GrabIntent)
		if $Control/IntentSelector/HarmIntent:
			buttons.append($Control/IntentSelector/HarmIntent)
	
	# Movement buttons
	if $Control/MovementButtons:
		if $Control/MovementButtons/RunButton:
			buttons.append($Control/MovementButtons/RunButton)
		if $Control/MovementButtons/WalkButton:
			buttons.append($Control/MovementButtons/WalkButton)
	
	# Hand buttons
	if $Control/HandSlots:
		if $Control/HandSlots/LeftHand:
			buttons.append($Control/HandSlots/LeftHand)
		if $Control/HandSlots/RightHand:
			buttons.append($Control/HandSlots/RightHand)
	
	# Equipment button
	if $Control/EquipmentItems and $Control/EquipmentItems/EquipmentButton:
		buttons.append($Control/EquipmentItems/EquipmentButton)
	
	# Add slot buttons - these need to be blocking to handle drag and drop
	add_slot_buttons_to_array(buttons)
	
	# Add all buttons to the group for detection
	for button in buttons:
		if button:
			button.add_to_group("ui_buttons")
			# Ensure clickable buttons have proper mouse_filter
			button.mouse_filter = Control.MOUSE_FILTER_STOP

# Helper to gather all slot buttons
func add_slot_buttons_to_array(buttons_array):
	"""Add all inventory slot buttons to an array"""
	# Equipment slot buttons
	var equipment_slots = [
		"HeadSlot", "EyesSlot", "MaskSlot", "UniformSlot", 
		"ArmorSlot", "SuitSlot", "GlovesSlot", "ShoesSlot"
	]
	
	# Special handling for ear slots which have different names
	var ear_slots = ["Ear1Slot", "Ear2Slot"]
	
	for slot_name in equipment_slots:
		var button_path = "Control/EquipmentItems/EquipmentButton/EquipmentSlots/GridContainer/%s/%sButton" % [slot_name, slot_name]
		var button = get_node_or_null(button_path)
		if button:
			buttons_array.append(button)
	
	# Connect ear slots
	for ear_slot in ear_slots:
		var button_path = "Control/EquipmentItems/EquipmentButton/EquipmentSlots/GridContainer/%s/EarsSlotButton" % ear_slot
		var button = get_node_or_null(button_path)
		if button:
			buttons_array.append(button)
	
	# Connect main slots (belt, backpack, ID)
	var main_slots = ["BackSlot", "BeltSlot", "IDSlot"]
	for slot_name in main_slots:
		var button_path = "Control/MainSlots/%s/%sButton" % [slot_name, slot_name]
		var button = get_node_or_null(button_path)
		if button:
			buttons_array.append(button)
	
	# Connect pouch slots
	for i in range(1, 3):
		var pouch_name = "Pouch%d" % i
		var button_path = "Control/PouchSlots/%s/%sButton" % [pouch_name, pouch_name]
		var button = get_node_or_null(button_path)
		if button:
			buttons_array.append(button)

# Make UI widgets register to groups
func register_ui_widgets():
	"""Register UI elements to appropriate interaction groups"""
	# Add UI controls to groups for click detection
	add_to_group("ui_root")
	
	# Make sure the Control node is in the ui_elements group
	$Control.add_to_group("ui_elements")
	
	# Add all sections to ui_elements group
	var sections = [
		$Control/HandSlots,
		$Control/EquipmentItems,
		$Control/IntentSelector,
		$Control/MovementButtons,
		$Control/MainSlots,
		$Control/PouchSlots,
		$Control/TooltipPanel
	]
	
	for section in sections:
		if section:
			section.add_to_group("ui_elements")
	
	# Important: Add slots to a specific group for the ClickSystem to recognize
	register_inventory_slots()
	
	# Add specific controls to ui_buttons group
	register_ui_buttons()
	
	# Add equipment menu to ui_elements if it exists
	if $Control/EquipmentItems/EquipmentButton/EquipmentSlots:
		$Control/EquipmentItems/EquipmentButton/EquipmentSlots.add_to_group("ui_elements")

func register_inventory_slots():
	"""Register all inventory slots for proper click detection"""
	# Register hand slots
	var left_hand = $Control/HandSlots/LeftHand if has_node("Control/HandSlots/LeftHand") else null
	var right_hand = $Control/HandSlots/RightHand if has_node("Control/HandSlots/RightHand") else null
	
	if left_hand:
		left_hand.add_to_group("inventory_slots")
		left_hand.add_to_group("ui_elements")
	
	if right_hand:
		right_hand.add_to_group("inventory_slots")
		right_hand.add_to_group("ui_elements")
	
	# Register equipment slots
	for slot_name in slot_mapping:
		var slot_element = find_slot_element(slot_name)
		if slot_element:
			slot_element.add_to_group("inventory_slots")
			slot_element.add_to_group("ui_elements")
	
	# Register main slots
	for slot_name in ["BackSlot", "BeltSlot", "IDSlot"]:
		var slot_element = get_node_or_null("Control/MainSlots/" + slot_name)
		if slot_element:
			slot_element.add_to_group("inventory_slots") 
			slot_element.add_to_group("ui_elements")
	
	# Register pouch slots
	for i in range(1, 3):
		var pouch_slot = get_node_or_null("Control/PouchSlots/Pouch" + str(i))
		if pouch_slot:
			pouch_slot.add_to_group("inventory_slots")
			pouch_slot.add_to_group("ui_elements")
#------------------------------------------------------------------
#endregion

#region PLAYER CONNECTION
#------------------------------------------------------------------
# Find the player entity and connect to its systems
func find_player_entity():
	print("PlayerUI: find_player_entity() called - searching for player")
	
	# Make sure UI is visible from the start
	$Control.visible = true
	$Control.modulate.a = 1.0
	
	# Find the player entity
	var players = get_tree().get_nodes_in_group("player_controller")
	if players.size() > 0:
		entity = players[0]
		print("PlayerUI: Found player entity:", entity.name)
		
		# Get inventory system
		if entity.has_node("InventorySystem"):
			inventory_system = entity.get_node("InventorySystem")
			print("PlayerUI: Found inventory system")
			
			# Connect inventory signals with high priority
			connect_inventory_signals()
			
			# IMPORTANT: Enable process mode for signals to work
			process_mode = Node.PROCESS_MODE_ALWAYS
		else:
			print("PlayerUI: Entity has no InventorySystem node")
		
		# Get entity integration
		if entity.has_node("EntityIntegration"):
			entity_integration = entity.get_node("EntityIntegration")
			print("PlayerUI: Found entity integration")
			
			# Connect entity integration signals
			if entity_integration.has_signal("inventory_updated"):
				if !entity_integration.is_connected("inventory_updated", Callable(self, "_on_inventory_updated")):
					entity_integration.inventory_updated.connect(_on_inventory_updated)
					# Ensure high priority - disconnect and reconnect
					if entity_integration.is_connected("inventory_updated", Callable(self, "_on_inventory_updated")):
						entity_integration.disconnect("inventory_updated", Callable(self, "_on_inventory_updated"))
						entity_integration.inventory_updated.connect(_on_inventory_updated, CONNECT_DEFERRED)
		
		# Get grid controller for intent and movement
		if entity.has_node("GridMovementController"):
			grid_controller = entity.get_node("GridMovementController")
			print("PlayerUI: Found grid movement controller")
		
		# Find world if needed
		var world = get_node_or_null("/root/World")
		if world and world.has_node("InteractionSystem"):
			interaction_system = world.get_node("InteractionSystem")
			print("PlayerUI: Found interaction system")
		
		# Initialize UI state
		update_all_slots()
		update_active_hand()
		update_intent_buttons()
		update_movement_buttons()
		
		# Force a full UI refresh
		force_ui_refresh()
		
		# IMPORTANT: Verify no ghost items exist immediately
		verify_hand_items_exist()
		
		return true
	else:
		# No player found, try again later
		print("PlayerUI: No player found, will retry in 1 second")
		await get_tree().create_timer(1.0).timeout
		return await find_player_entity()

# Connect all inventory system signals
func connect_inventory_signals():
	"""Connect to all inventory system signals"""
	if !inventory_system:
		print("PlayerUI: Can't connect signals - no inventory system")
		return
		
	var inventory_signals = [
		["inventory_updated", _on_inventory_updated],
		["item_equipped", _on_item_equipped],
		["item_unequipped", _on_item_unequipped],
		["item_added", _on_inventory_updated],
		["item_removed", _on_inventory_updated],
		["active_hand_changed", _on_active_hand_changed]
	]
	
	for signal_info in inventory_signals:
		var signal_name = signal_info[0]
		var callback = signal_info[1]
		
		if inventory_system.has_signal(signal_name):
			if !inventory_system.is_connected(signal_name, Callable(self, callback.get_method())):
				print("PlayerUI: Connecting signal: " + signal_name)
				inventory_system.connect(signal_name, Callable(self, callback.get_method()))
				
	# Connect to GridMovementController if needed
	if inventory_system.has_method("connect_to_grid_controller"):
		inventory_system.connect_to_grid_controller()
		
	print("PlayerUI: Inventory signals connected successfully")

# Connect to a specific entity
func connect_to_entity(target_entity):
	"""Connect to a player entity"""
	entity = target_entity
	
	# Get systems
	if entity.has_node("InventorySystem"):
		inventory_system = entity.get_node("InventorySystem")
		
		# Connect inventory signals
		connect_inventory_signals()
	
	# Get entity integration
	if entity:
		entity_integration = entity
		
		# Connect entity integration signals
	if entity_integration.has_signal("inventory_updated"):
		if !entity_integration.is_connected("inventory_updated", Callable(self, "_on_inventory_updated")):
			entity_integration.inventory_updated.connect(_on_inventory_updated)
	
	# Get grid controller for movement and intent handling
	if entity:
		grid_controller = entity
	
	# Get interaction system
	var world = get_node_or_null("/root/World")
	if world and world.has_node("InteractionSystem"):
		interaction_system = world.get_node("InteractionSystem")
	
	# Initialize UI state
	update_all_slots()
	update_active_hand()
	update_intent_buttons()
	update_movement_buttons()
	force_ui_refresh()

# Find inventory system to connect with
func find_inventory_system():
	"""Find inventory system to connect with"""
	print("PlayerUI: Searching for inventory system")
	
	# Get entity (should be parent)
	var entity = get_parent()
	if entity:
		# Try to get inventory system directly
		inventory_system = entity.get_node_or_null("InventorySystem")
		if inventory_system:
			print("PlayerUI: Found inventory system!")
			connect_inventory_signals()
			force_ui_refresh()
			return true
		
		# Try using a controller component
		var grid_controller = entity
		if grid_controller and grid_controller.inventory_system:
			inventory_system = grid_controller.inventory_system
			print("PlayerUI: Found inventory system via grid controller!")
			connect_inventory_signals()
			force_ui_refresh()
			return true
	
	# Try searching broadly
	var potential_systems = get_tree().get_nodes_in_group("inventory_systems")
	if potential_systems.size() > 0:
		inventory_system = potential_systems[0]
		print("PlayerUI: Found inventory system via group!")
		connect_inventory_signals()
		force_ui_refresh()
		return true
		
	print("PlayerUI: WARNING - Could not find inventory system")
	return false

# Verify inventory connections
func verify_inventory_connections():
	"""Verify inventory system connections"""
	if !inventory_system:
		print("PlayerUI: ERROR: No inventory_system reference!")
		find_inventory_system()
		return
	
	# Verify signals are connected
	var signals_to_verify = [
		"inventory_updated",
		"item_equipped",
		"item_unequipped",
		"active_hand_changed"
	]
	
	var missing_signals = []
	for signal_name in signals_to_verify:
		if !inventory_system.has_signal(signal_name):
			print("PlayerUI: WARNING: inventory_system missing signal: " + signal_name)
			missing_signals.append(signal_name)
			continue
			
		if !inventory_system.is_connected(signal_name, Callable(self, "_on_" + signal_name)):
			print("PlayerUI: Connecting missing signal: " + signal_name)
			inventory_system.connect(signal_name, Callable(self, "_on_" + signal_name))
	
	# Report status
	if missing_signals.size() > 0:
		print("PlayerUI: WARNING: Some inventory signals are missing: ", missing_signals)
	else:
		print("PlayerUI: All inventory signals verified")
	
	# Verify hand slots are initialized
	if !("LeftHandSlot" in slot_item_sprites) or !slot_item_sprites["LeftHandSlot"]:
		print("PlayerUI: Left hand slot sprite missing, recreating")
		update_hand_item_sprite("LeftHandSlot", null)
		
	if !("RightHandSlot" in slot_item_sprites) or !slot_item_sprites["RightHandSlot"]:
		print("PlayerUI: Right hand slot sprite missing, recreating")
		update_hand_item_sprite("RightHandSlot", null)
#------------------------------------------------------------------
#endregion

#region DRAG AND DROP
#------------------------------------------------------------------
# Handle input events for drag and drop + keyboard shortcuts
func _input(event):
	# HANDLE KEYBOARD SHORTCUTS
	if event is InputEventKey and event.pressed:
		# Handle keyboard shortcuts
		if event.is_action_pressed("switch_hand"):
			print("PlayerUI: Switch active hand action pressed")
			if inventory_system:
				# Switch hand
				inventory_system.switch_active_hand()
				
				# Play sound effect
				play_sound_effect(SoundEffect.CLICK)
				
				# Update indicators
				update_active_hand()
				
		elif event.is_action_pressed("use_item"):
			print("PlayerUI: Use active item action pressed")
			if inventory_system:
				# Get active item before using it (for visual feedback)
				var active_hand = inventory_system.active_hand
				var hand_rect = $Control/HandSlots/LeftHand if active_hand == 13 else $Control/HandSlots/RightHand
				
				# Use the item
				var success = await inventory_system.use_active_item()
				
				# Play sound effect
				play_sound_effect(SoundEffect.CLICK)
				
				# Show feedback for success/failure if UI integration exists
				if success:
					var item = inventory_system.get_active_item()
					if item and entity and entity.has_node("UIIntegration"):
						var ui = entity.get_node("UIIntegration")
						if ui.has_method("show_notification"):
							ui.show_notification("Used " + item.item_name, "info")
				
				# Update UI in case the item changed
				update_all_slots()
				
		elif event.is_action_pressed("drop_item"):
			print("PlayerUI: Drop active item action pressed")
			if inventory_system and inventory_system.has_method("drop_active_item"):
				# Drop active item
				var success = inventory_system.drop_active_item()
				
				# Play sound effect
				if success:
					play_sound_effect(SoundEffect.DROP)
				
				# Update UI after dropping
				update_all_slots()
		
		# Handle intent selection via number keys
		elif event.is_action_pressed("mode_help"):
			print("PlayerUI: Help intent action pressed")
			set_intent(Intent.HELP)
		elif event.is_action_pressed("mode_disarm"):
			print("PlayerUI: Disarm intent action pressed")
			set_intent(Intent.DISARM)
		elif event.is_action_pressed("mode_grab"):
			print("PlayerUI: Grab intent action pressed")
			set_intent(Intent.GRAB)
		elif event.is_action_pressed("mode_harm"):
			print("PlayerUI: Harm intent action pressed")
			set_intent(Intent.HARM)
	
	# HANDLE MOUSE EVENTS
	# Check if this is a mouse event
	elif event is InputEventMouseButton:
		var position = event.position
		if is_position_in_ui_element(position):
			# Tell the input priority system we're handling this
			var input_manager = get_node_or_null("/root/InputPriorityManager")
			if input_manager:
				input_manager.set_ui_active()
				
			# Update click cooldown timer
			if click_cooldown_timer > 0:
				return
				
			# Now handle the event as before
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					# Mouse button pressed - handle the press with modifier keys
					handle_mouse_down(event.global_position, event.button_index, 
									 event.shift_pressed, event.ctrl_pressed, 
									 event.alt_pressed)
				else:
					# Mouse button released - handle release with modifier keys
					handle_mouse_up(event.global_position, event.button_index, 
								   event.shift_pressed, event.ctrl_pressed, 
								   event.alt_pressed)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				if event.pressed:
					handle_right_click_press(event.global_position, event.shift_pressed, 
										  event.ctrl_pressed, event.alt_pressed)
				else:
					handle_right_click_release(event.global_position, event.shift_pressed, 
											event.ctrl_pressed, event.alt_pressed)
			elif event.button_index == MOUSE_BUTTON_MIDDLE:
				if event.pressed:
					handle_middle_click_press(event.global_position, event.shift_pressed, 
										   event.ctrl_pressed, event.alt_pressed)
				else:
					handle_middle_click_release(event.global_position, event.shift_pressed, 
											 event.ctrl_pressed, event.alt_pressed)
		else:
			# Not over UI - clear UI active flag
			var input_manager = get_node_or_null("/root/InputPriorityManager") 
			if input_manager:
				input_manager.clear_ui_active()
	
	# Handle mouse motion for drag operations if we're already dragging
	elif event is InputEventMouseMotion and dragging_item:
		# Always update mouse position for dragging
		last_mouse_position = event.global_position
		
		# If we've dragged far enough from the start, set is_dragging to true
		if drag_start_position.distance_to(last_mouse_position) > DRAG_START_DISTANCE:
			is_dragging = true
			
			# When drag is active, make sure the UI has priority
			var input_manager = get_node_or_null("/root/InputPriorityManager")
			if input_manager:
				input_manager.set_ui_active()

func _on_mouse_down(position):
	"""Handle mouse down events for drag and drop"""
	if inventory_system == null or slot_mapping == null:
		return

	# Check if we're over a slot with an item
	for slot_name in slot_mapping:
		var slot_element = find_slot_element(slot_name)
		if slot_element and slot_element.visible and slot_element.get_global_rect().has_point(position):
			var equip_slot = slot_mapping[slot_name]
			var item = inventory_system.get_item_in_slot(equip_slot)
			
			if item != null:
				# Mark that we pressed on an item - will start drag if mouse moves
				mouse_down_over_item = true
				start_dragging_from_slot(slot_name)
				return
	
	# If not over a slot with an item, check if we've clicked on a hand
	var left_hand = $Control/HandSlots/LeftHand if has_node("Control/HandSlots/LeftHand") else null
	var right_hand = $Control/HandSlots/RightHand if has_node("Control/HandSlots/RightHand") else null

	if left_hand and left_hand.get_global_rect().has_point(position):
		if inventory_system:
			var item = inventory_system.get_item_in_slot(13) # LEFT_HAND
			if item != null:
				start_dragging_from_slot("LeftHandSlot")
			else:
				# Set left hand as active
				if inventory_system.active_hand != 13:
					inventory_system.active_hand = 13
					update_active_hand()
					if left_hand:
						flash_hand_selection(left_hand)
					play_sound_effect(SoundEffect.CLICK)
	elif right_hand and right_hand.get_global_rect().has_point(position):
		if inventory_system:
			var item = inventory_system.get_item_in_slot(14) # RIGHT_HAND
			if item != null:
				start_dragging_from_slot("RightHandSlot")
			else:
				# Set right hand as active
				if inventory_system.active_hand != 14:
					inventory_system.active_hand = 14
					update_active_hand()
					if right_hand:
						flash_hand_selection(right_hand)
					play_sound_effect(SoundEffect.CLICK)

# Mouse button release handler - drop or throw item
func _on_mouse_up(position):
	"""Handle mouse up events for completing drag operations"""
	# If we're not dragging, nothing to do
	if !dragging_item:
		mouse_down_over_item = false
		return
	
	# If we're over a valid slot, drop into that slot
	if drag_over_slot:
		drop_item_into_slot(drag_over_slot)
	else:
		# Check if we've dragged enough to consider it a throw
		if is_dragging:
			# Mouse released outside UI - throw the item
			throw_dragged_item(position)
		else:
			# Short drag distance - cancel the drag
			cancel_drag_with_animation()

# Start dragging an item from a slot
func start_dragging_from_slot(slot_name):
	"""Begin dragging an item from a slot"""
	print("PlayerUI: Start dragging from slot:", slot_name)
	
	if !inventory_system:
		return
	
	# Get the equip slot enum value
	var equip_slot = slot_mapping.get(slot_name, -1)
	if equip_slot == -1:
		return
	
	# Get item in this slot
	var item = inventory_system.get_item_in_slot(equip_slot)
	
	if item:
		# Start dragging
		dragging_item = item
		dragging_from_slot = slot_name
		
		# Record drag start position for throw calculation
		drag_start_position = get_viewport().get_mouse_position()
		last_mouse_position = drag_start_position
		is_dragging = false
		
		# Play pickup sound
		play_sound_effect(SoundEffect.PICKUP)
		
		# Set up drag preview with animation
		var texture = get_item_icon_texture(item)
		if texture:
			drag_preview.texture = texture
		else:
			# Create a default drag preview
			var default_texture = create_placeholder_texture()
			drag_preview.texture = default_texture
		
		# Set drag origin to center of preview
		drag_origin = Vector2(drag_preview.texture.get_width() / 2, drag_preview.texture.get_height() / 2)
		
		# Show drag preview with animation
		drag_preview.modulate.a = 0
		drag_preview.scale = Vector2(0.8, 0.8)
		drag_preview.visible = true
		
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_BACK)
		tween.tween_property(drag_preview, "modulate:a", DRAG_PREVIEW_OPACITY, 0.2)
		tween.parallel().tween_property(drag_preview, "scale", DRAG_SCALE_UP, 0.2)
		
		# Hide tooltip while dragging
		$Control/TooltipPanel.visible = false
		
		# Highlight valid slots for item
		highlight_valid_slots_for_item(item)
		
		# Make the original slot semi-transparent to indicate dragging
		var slot_element = find_slot_element(slot_name)
		if slot_element:
			var tween2 = create_tween()
			tween2.set_ease(Tween.EASE_OUT)
			tween2.set_trans(Tween.TRANS_CUBIC)
			tween2.tween_property(slot_element, "modulate:a", 0.5, 0.2)

# Cancel drag with animation
func cancel_drag_with_animation():
	"""Cancel a drag operation with animation"""
	if !dragging_item:
		return
	
	# Create animation for cancellation
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	
	# Fade out and scale down
	tween.tween_property(drag_preview, "modulate:a", 0, 0.2)
	tween.parallel().tween_property(drag_preview, "scale", DRAG_SCALE_DOWN, 0.2)
	
	# Reset all slot highlights
	reset_all_slot_highlights()
	
	# Restore the original slot opacity
	var slot_element = find_slot_element(dragging_from_slot)
	if slot_element:
		var tween2 = create_tween()
		tween2.set_ease(Tween.EASE_OUT)
		tween2.set_trans(Tween.TRANS_CUBIC)
		tween2.tween_property(slot_element, "modulate:a", 1.0, 0.3)
	
	# When animation completes, fully reset drag state
	tween.tween_callback(func():
		dragging_item = null
		dragging_from_slot = null
		drag_preview.visible = false
		is_dragging = false
		drag_start_position = Vector2.ZERO
		last_mouse_position = Vector2.ZERO
		mouse_down_over_item = false
	)

# Drop dragged item into a slot
func drop_item_into_slot(slot_name):
	"""Drop a dragged item into a slot"""
	print("PlayerUI: Drop item into slot:", slot_name)
	
	if !inventory_system or !dragging_item:
		cancel_drag_with_animation()
		return
	
	# Get the equip slot enum value for the target slot
	var target_slot = slot_mapping.get(slot_name, -1)
	if target_slot == -1:
		print("PlayerUI: Invalid target slot name: " + slot_name)
		cancel_drag_with_animation()
		return
	
	# Get the equip slot enum value for the source slot
	var source_slot = slot_mapping.get(dragging_from_slot, -1)
	if source_slot == -1:
		print("PlayerUI: Invalid source slot name: " + dragging_from_slot)
		cancel_drag_with_animation()
		return
	
	# If dropping to same slot, cancel drag
	if source_slot == target_slot:
		print("PlayerUI: Dropped to same slot, canceling")
		cancel_drag_with_animation()
		return
	
	# Validate item can be equipped to this slot
	var can_equip = true  # Default assumption
	
	# Check if the dragged item has valid_slots defined
	if "valid_slots" in dragging_item and dragging_item.valid_slots is Array:
		can_equip = dragging_item.valid_slots.has(target_slot)
		print("PlayerUI: Slot validation - can equip to slot ", target_slot, ": ", can_equip)
	else:
		print("PlayerUI: Item has no valid_slots property, allowing equip by default")
	
	# Store references before canceling drag
	var item = dragging_item
	
	# Get target slot element for animation
	var target_element = find_slot_element(slot_name)
	
	# Create drop animation
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	
	if target_element:
		# Animate moving the drag preview to target slot
		var target_pos = target_element.global_position + target_element.size / 2 - drag_origin
		tween.tween_property(drag_preview, "global_position", target_pos, 0.25)
		tween.parallel().tween_property(drag_preview, "scale", Vector2(0.8, 0.8), 0.25)
	
	# Fade out at the end
	tween.tween_property(drag_preview, "modulate:a", 0, 0.15)
	
	# Reset all slot highlights
	reset_all_slot_highlights()
	
	# Complete the drop operation
	tween.tween_callback(func(): 
		# Clean up the drag preview and state
		dragging_item = null
		dragging_from_slot = null
		drag_preview.visible = false
		is_dragging = false
		mouse_down_over_item = false
		
		if can_equip:
			print("PlayerUI: Equipping item to slot " + str(target_slot))
			
			# Play equip success sound
			play_sound_effect(SoundEffect.EQUIP)
			
			# Unequip from source slot
			inventory_system.unequip_item(source_slot)
			
			# Equip to target slot
			inventory_system.equip_item(item, target_slot)
			
			# Show notification about equipping
			if entity and entity.has_node("UIIntegration"):
				var ui_integration = entity.get_node("UIIntegration")
				if ui_integration.has_method("show_notification"):
					var item_name = item.item_name if "item_name" in item else "Item"
					ui_integration.show_notification("Equipped " + item_name, "info")
		else:
			print("PlayerUI: Cannot equip item to slot " + str(target_slot) + " - invalid slot")
			
			# Play error sound
			play_sound_effect(SoundEffect.ERROR)
			
			# Invalid slot - show error notification
			if entity and entity.has_node("UIIntegration"):
				var ui_integration = entity.get_node("UIIntegration")
				if ui_integration.has_method("show_notification"):
					var item_name = item.item_name if "item_name" in item else "Item"
					ui_integration.show_notification(item_name + " cannot be equipped in this slot", "error")
		
		# Update all slots after a change
		update_all_slots()
	)

# Throw the dragged item when released outside UI
func throw_dragged_item(release_position):
	"""Throw a dragged item with improved distance control"""
	print("PlayerUI: Throwing item with improved distance control")
	
	if !dragging_item or !inventory_system:
		cancel_drag_with_animation()
		return
	
	# Only throw if we've moved enough distance
	if !is_dragging:
		print("PlayerUI: Drag distance too small, canceling throw")
		cancel_drag_with_animation()
		return
	
	# Calculate throw direction and apply clamping
	var throw_direction = (release_position - drag_start_position).normalized()
	var throw_distance = min(drag_start_position.distance_to(release_position), 200)  # Cap maximum drag distance
	
	# Use a logarithmic scale for better control
	# This gives more precision for short throws and prevents items from flying too far
	var throw_force = min(log(throw_distance) * throw_force_multiplier, 200)
	
	print("PlayerUI: Throw direction: ", throw_direction, " force: ", throw_force)
	
	# Store references before canceling drag
	var item = dragging_item
	var source_slot = slot_mapping.get(dragging_from_slot, -1)
	
	# Create throw animation
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	
	# Animate in throw direction - keep distance reasonable
	var max_visual_distance = 100  # Max distance for animation
	var throw_dest = drag_preview.global_position + (throw_direction * min(throw_force, max_visual_distance))
	tween.tween_property(drag_preview, "global_position", throw_dest, 0.2)
	tween.parallel().tween_property(drag_preview, "modulate:a", 0, 0.2)
	tween.parallel().tween_property(drag_preview, "scale", Vector2(0.7, 0.7), 0.2)
	
	# Reset all slot highlights
	reset_all_slot_highlights()
	
	# Complete throw operation
	tween.tween_callback(func(): 
		# Clean up the drag state
		dragging_item = null
		dragging_from_slot = null
		drag_preview.visible = false
		is_dragging = false
		mouse_down_over_item = false
		
		# IMPORTANT: PRE-EMPTIVELY clean up the source slot's visual BEFORE calling throw_item
		# This prevents the ghost item bug by ensuring the UI is updated before the inventory changes
		if source_slot == 13: # LEFT_HAND
			hand_slot_items["LeftHandSlot"] = null
			if "LeftHandSlot" in slot_item_sprites and slot_item_sprites["LeftHandSlot"]:
				cleanup_slot_sprite("LeftHandSlot", slot_item_sprites["LeftHandSlot"])
		elif source_slot == 14: # RIGHT_HAND
			hand_slot_items["RightHandSlot"] = null
			if "RightHandSlot" in slot_item_sprites and slot_item_sprites["RightHandSlot"]:
				cleanup_slot_sprite("RightHandSlot", slot_item_sprites["RightHandSlot"])
		
		# Use throw_item method if available, otherwise fall back to unequip
		if inventory_system.has_method("throw_item"):
			# Some inventory systems have a dedicated throw method
			inventory_system.throw_item(item, throw_direction, throw_force)
			
			# Play throw sound
			play_sound_effect(SoundEffect.THROW)
			
			# Show notification about throwing
			if entity and entity.has_node("UIIntegration"):
				var ui_integration = entity.get_node("UIIntegration")
				if ui_integration.has_method("show_notification"):
					var item_name = item.item_name if "item_name" in item else "Item"
					ui_integration.show_notification("Threw " + item_name, "info")
		elif inventory_system.has_method("drop_item"):
			# If no throw method, try to use drop_item with direction
			inventory_system.drop_item(source_slot, throw_direction, throw_force)
			
			# Play drop sound
			play_sound_effect(SoundEffect.DROP)
		else:
			# No specialized methods, just unequip the item
			print("PlayerUI: No throw/drop method found, just unequipping")
			inventory_system.unequip_item(source_slot)
			
			# Play drop sound
			play_sound_effect(SoundEffect.DROP)
		
		# IMPORTANT: Force an immediate update after throwing
		verify_hand_items_exist()
		update_all_slots()
	)

func calculate_throw_force(drag_distance: float) -> float:
	"""Calculate throw force with a curve for better control"""
	# Clamp the drag distance
	var clamped_distance = min(drag_distance, MAX_THROW_DISTANCE)
	
	# Apply a curve for better control (power curve gives more precision for short throws)
	# This gives more gradual increase at short distances and flatter curve at longer distances
	var normalized_distance = clamped_distance / MAX_THROW_DISTANCE
	var curved_force = pow(normalized_distance, THROW_CURVE_FACTOR) * MAX_THROW_FORCE
	
	return curved_force

# Highlight valid slots for dragging an item
func highlight_valid_slots_for_item(item):
	"""Highlight valid slots for the item being dragged"""
	print("PlayerUI: Highlighting valid slots for item")
	
	# Get valid slots for this item
	var valid_slots = []
	
	# Check if item has valid_slots
	if "valid_slots" in item and item.valid_slots is Array:
		valid_slots = item.valid_slots
		print("PlayerUI: Item has valid_slots: ", valid_slots)
	else:
		# Default to all slots if no validation exists
		valid_slots = slot_mapping.values()
		print("PlayerUI: Item has no valid_slots, highlighting all slots")
	
	# Loop through all equipment slots and highlight valid ones
	for slot_name in slot_mapping.keys():
		var slot_id = slot_mapping[slot_name]
		
		# Skip the slot we're dragging from
		if slot_name == dragging_from_slot:
			continue
			
		# Get the slot's UI element
		var slot_element = find_slot_element(slot_name)
		if !slot_element:
			continue
		
		# Highlight/dim based on validity
		if valid_slots.has(slot_id):
			# Valid slot - highlight
			var tween = create_tween()
			tween.set_ease(Tween.EASE_OUT)
			tween.set_trans(Tween.TRANS_SINE)
			tween.tween_property(slot_element, "modulate", VALID_SLOT_HIGHLIGHT, 0.2)
		else:
			# Invalid slot - dim
			var tween = create_tween()
			tween.set_ease(Tween.EASE_OUT)
			tween.set_trans(Tween.TRANS_SINE)
			tween.tween_property(slot_element, "modulate", Color(0.5, 0.5, 0.5, INVALID_SLOT_OPACITY), 0.2)

# Highlight a slot during drag and drop based on validity
func highlight_slot_for_drag(slot_name):
	"""Highlight a slot during drag and drop interaction"""
	if !dragging_item:
		return
		
	# Get slot element
	var slot_element = find_slot_element(slot_name)
	if !slot_element:
		return
		
	# Check if item can be equipped in this slot
	var target_slot = slot_mapping.get(slot_name, -1)
	var can_equip = true
	
	# Check if the dragged item has valid_slots defined
	if "valid_slots" in dragging_item and dragging_item.valid_slots is Array:
		can_equip = dragging_item.valid_slots.has(target_slot)
	
	# Create tween for visual effect
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	
	if can_equip:
		# Valid slot - highlight with a greenish tint
		tween.tween_property(slot_element, "modulate", Color(0.8, 1.2, 0.8, 1.0), 0.2)
	else:
		# Invalid slot - dim with a reddish tint
		tween.tween_property(slot_element, "modulate", Color(1.2, 0.6, 0.6, INVALID_SLOT_OPACITY), 0.2)

# Reset slot highlight after dragging
func reset_slot_highlight(slot_name):
	"""Reset slot highlighting after drag operation"""
	var slot_element = find_slot_element(slot_name)
	if !slot_element:
		return
		
	# Reset to normal appearance with a tween
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(slot_element, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.2)

# Reset highlighting on all slots
func reset_all_slot_highlights():
	"""Reset highlighting on all slots"""
	for slot_name in slot_mapping.keys():
		reset_slot_highlight(slot_name)
#------------------------------------------------------------------
#endregion

#region INTENT & MOVEMENT
#------------------------------------------------------------------
# Get button reference by intent type
func get_intent_button(intent):
	match intent:
		Intent.HELP:
			return $Control/IntentSelector/HelpIntent
		Intent.DISARM:
			return $Control/IntentSelector/DisarmIntent
		Intent.GRAB:
			return $Control/IntentSelector/GrabIntent
		Intent.HARM:
			return $Control/IntentSelector/HarmIntent
	return null

# Apply current intent to relevant systems
func apply_current_intent():
	"""Apply the current intent to game systems"""
	print("PlayerUI: Applying intent:", current_intent)
	
	# If interaction system is available, tell it about the intent
	if interaction_system:
		# Map our Intent enum to InteractionSystem's InteractionType enum
		var interaction_type = 0  # Default to HELP/USE
		match current_intent:
			Intent.HELP:
				interaction_type = interaction_system.InteractionType.USE
			Intent.DISARM:
				# Find an appropriate interaction type for disarm in your InteractionSystem
				if "DISARM" in interaction_system.InteractionType:
					interaction_type = interaction_system.InteractionType.DISARM
			Intent.GRAB:
				interaction_type = interaction_system.InteractionType.GRAB
			Intent.HARM:
				interaction_type = interaction_system.InteractionType.ATTACK
				
		# Assuming the interaction system has a set_intent method
		if interaction_system.has_method("set_intent"):
			interaction_system.set_intent(interaction_type)
	
	# Also inform the grid controller (might affect bump interactions)
	if grid_controller:
		# Store the intent on the grid controller if it supports it
		if "intent" in grid_controller:
			grid_controller.intent = current_intent

# Apply movement mode to player entity
func apply_movement_mode():
	"""Apply the movement mode to the player entity"""
	# Set movement mode on grid controller
	if grid_controller:
		grid_controller.is_sprinting = is_movement_sprint
		
		# Update movement state if needed
		if grid_controller.has_method("update_movement_state"):
			grid_controller.update_movement_state()

# Set intent via code
func set_intent(intent):
	"""Set the current intent and update UI"""
	if current_intent == intent:
		return
		
	current_intent = intent
	update_intent_buttons()
	apply_current_intent()
	
	# Add visual feedback when intent is changed
	flash_intent_button(intent)

# Flash intent button for visual feedback
func flash_intent_button(intent):
	"""Flash an intent button to provide visual feedback"""
	var button = get_intent_button(intent)
	if button:
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_SINE)
		tween.tween_property(button, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.1)
		tween.tween_property(button, "modulate", Color(1.3, 1.3, 1.3, 1.0), 0.2)

# Flash effect for hand selection
func flash_hand_selection(hand_rect):
	"""Add highlight flash animation to indicate hand selection"""
	if !hand_rect:
		return
	
	# Cancel any active tween for this hand
	if hand_rect in active_tweens and active_tweens[hand_rect].is_valid():
		active_tweens[hand_rect].kill()
	
	# Create a new, isolated flash tween
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	
	# Store original modulate
	var original_modulate = hand_rect.modulate
	
	# Flash brighter then back to original
	tween.tween_property(hand_rect, "modulate", Color(1.8, 1.8, 1.8, 1.0), 0.1)
	tween.tween_property(hand_rect, "modulate", original_modulate, 0.2)
	
	# When flash is complete, ensure active hand state is correct
	tween.tween_callback(func(): update_active_hand())
	
	# Store tween reference
	active_tweens[hand_rect] = tween
#------------------------------------------------------------------
#endregion

#region UTILITY FUNCTIONS
#------------------------------------------------------------------
# Force refresh entire UI
func force_ui_refresh():
	"""Force a complete refresh of the UI"""
	# First verify inventory state
	if inventory_system:
		print("PlayerUI: Force refreshing inventory UI...")
		
		# Check each hand directly
		var left_hand_item = inventory_system.get_item_in_slot(13) # LEFT_HAND
		var right_hand_item = inventory_system.get_item_in_slot(14) # RIGHT_HAND
		
		print("PlayerUI: Left hand has item: ", left_hand_item != null)
		print("PlayerUI: Right hand has item: ", right_hand_item != null)
		
		# Update our cached references
		hand_slot_items["LeftHandSlot"] = left_hand_item
		hand_slot_items["RightHandSlot"] = right_hand_item
		
		# Update item sprites with force flag
		update_hand_item_sprite("LeftHandSlot", left_hand_item)
		update_hand_item_sprite("RightHandSlot", right_hand_item)
		
		# Update active hand indicators
		update_active_hand()
		
		# Update all equipment slots
		update_all_slots()
		
		# Update intent indicators
		update_intent_buttons()
		
		print("PlayerUI: Force refresh completed")

func create_tween_with_cleanup():
	"""Create a tween that cleans up after itself"""
	var tween = create_tween()
	
	# Auto-cleanup when finished
	tween.finished.connect(func(): 
		# Remove from active_tweens
		for key in active_tweens.keys():
			if active_tweens[key] == tween:
				active_tweens.erase(key)
				break
	)
	
	return tween

# Get the item sprite for a slot
func get_item_sprite_for_slot(slot_name, sprite_name = null):
	"""Get the item sprite attached to a slot"""
	# For most slots, we use the stored reference
	if slot_name in slot_item_sprites:
		return slot_item_sprites[slot_name]
	
	# For ear slots, handle special case
	if slot_name == "EarsSlot" and sprite_name:
		var slot_element = find_slot_element(slot_name)
		if slot_element:
			return slot_element.get_node_or_null(sprite_name)
	
	# For other slots, try to find by name
	var slot_element = find_slot_element(slot_name)
	if slot_element:
		return slot_element.get_node_or_null(slot_name + "ItemSprite")
	
	return null

# Find the UI element for a slot by name
func find_slot_element(slot_name):
	"""Find the UI element for a specific slot name"""
	# Different paths based on slot type
	var equipment_slots = ["HeadSlot", "EyesSlot", "MaskSlot", "UniformSlot", 
		"ArmorSlot", "SuitSlot", "GlovesSlot", "ShoesSlot"]
	
	if equipment_slots.has(slot_name):
		return get_node_or_null("Control/EquipmentItems/EquipmentButton/EquipmentSlots/GridContainer/" + slot_name)
	elif slot_name == "EarsSlot":
		return get_node_or_null("Control/EquipmentItems/EquipmentButton/EquipmentSlots/GridContainer/Ear1Slot")
	elif slot_name == "LeftHandSlot":
		return get_node_or_null("Control/HandSlots/LeftHand")
	elif slot_name == "RightHandSlot":
		return get_node_or_null("Control/HandSlots/RightHand")
	elif slot_name in ["BackSlot", "BeltSlot", "IDSlot"]:
		return get_node_or_null("Control/MainSlots/" + slot_name)
	elif slot_name.begins_with("Pouch"):
		return get_node_or_null("Control/PouchSlots/" + slot_name)
		
	return null

# Create a placeholder texture
func create_placeholder_texture(color: Color = Color(0.8, 0.2, 0.2)):
	"""Create a fallback texture when none is available"""
	var image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(color)
	
	# Add simple border
	for x in range(32):
		for y in range(32):
			if x == 0 or y == 0 or x == 31 or y == 31:
				image.set_pixel(x, y, Color(0, 0, 0))
	
	return ImageTexture.create_from_image(image)

# Check if a point is inside any UI element
func is_point_in_ui(point: Vector2) -> bool:
	"""Check if a point is inside any UI element"""
	# Special handling for drag and drop operations
	if dragging_item != null:
		# If we're actively dragging an item, check if we're over a valid drop target
		if is_over_valid_drop_target(point):
			return true
	
	# Get all UI elements and check if point is inside any of them
	var ui_elements = get_tree().get_nodes_in_group("ui_elements")
	for element in ui_elements:
		if element.visible and element.global_position.distance_to(point) < 200:  # Only check nearby elements
			if element is Control and element.get_global_rect().has_point(point):
				# UI element is capturing this point
				return true
	
	# UI buttons are a separate group for better organization
	var ui_buttons = get_tree().get_nodes_in_group("ui_buttons")
	for button in ui_buttons:
		if button.visible and button is Control and button.get_global_rect().has_point(point):
			# Button is capturing this point
			return true
	
	# No UI element capturing clicks at this point
	return false

# Check if the point is over a valid drop target for dragging
func is_over_valid_drop_target(point: Vector2) -> bool:
	"""Check if a point is over a valid drop target during drag operations"""
	if !dragging_item:
		return false
	
	# Create an array to hold all potential drop targets
	var drop_targets = []
	
	# Add equipment slots if visible
	if $Control/EquipmentItems/EquipmentButton/EquipmentSlots.visible:
		var grid = $Control/EquipmentItems/EquipmentButton/EquipmentSlots/GridContainer
		for child in grid.get_children():
			if child is TextureRect:
				drop_targets.append(child)
	
	# Add hand slots
	drop_targets.append($Control/HandSlots/LeftHand)
	drop_targets.append($Control/HandSlots/RightHand)
	
	# Add main slots
	for slot in $Control/MainSlots.get_children():
		if slot is TextureRect:
			drop_targets.append(slot)
	
	# Add pouch slots
	for slot in $Control/PouchSlots.get_children():
		if slot is TextureRect:
			drop_targets.append(slot)
	
	# Check if point is in any of the drop targets
	for target in drop_targets:
		if target.visible and target.get_global_rect().has_point(point):
			return true
	
	return false

# Play sound effects
func play_sound_effect(effect_type):
	"""Play a UI sound effect"""
	if effect_type in sound_effects and sound_effects[effect_type] != null:
		var audio_player = AudioStreamPlayer.new()
		audio_player.stream = sound_effects[effect_type]
		audio_player.volume_db = -10  # Slightly quieter than game sounds
		audio_player.pitch_scale = randf_range(0.95, 1.05)  # Slight pitch variation for variety
		add_child(audio_player)
		audio_player.play()
		
		# Remove the player once finished
		audio_player.finished.connect(func(): audio_player.queue_free())
	elif entity and entity.has_node("UIIntegration"):
		# Fall back to entity UI integration for sounds if available
		var ui_integration = entity.get_node("UIIntegration")
		if ui_integration.has_method("play_ui_sound"):
			match effect_type:
				SoundEffect.CLICK:
					ui_integration.play_ui_sound("click")
				SoundEffect.EQUIP:
					ui_integration.play_ui_sound("equip")
				SoundEffect.UNEQUIP:
					ui_integration.play_ui_sound("unequip")
				SoundEffect.DROP:
					ui_integration.play_ui_sound("drop")
				SoundEffect.THROW:
					ui_integration.play_ui_sound("throw")
				SoundEffect.ERROR:
					ui_integration.play_ui_sound("error")
				SoundEffect.PICKUP:
					ui_integration.play_ui_sound("pickup")
				SoundEffect.SUCCESS:
					ui_integration.play_ui_sound("success")

# Display notification to the user
func show_notification(text: String, type: String = "info"):
	"""Display a notification to the user"""
	# Get notification panel
	var notification_panel = $Control/NotificationPanel
	var notification_label = $Control/NotificationPanel/NotificationLabel
	
	if !notification_panel or !notification_label:
		return
	
	# Set text
	notification_label.text = text
	
	# Set color based on type
	match type:
		"error":
			notification_panel.modulate = Color(1.3, 0.5, 0.5)
		"warning":
			notification_panel.modulate = Color(1.3, 1.0, 0.5)
		"success":
			notification_panel.modulate = Color(0.5, 1.3, 0.5)
		_: # info or default
			notification_panel.modulate = Color(1.0, 1.0, 1.0)
	
	# Stop any existing animations
	if notification_panel in active_tweens and active_tweens[notification_panel].is_valid():
		active_tweens[notification_panel].kill()
	
	# Create animation sequence
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	
	# Store reference
	active_tweens[notification_panel] = tween
	
	# Show and animate
	notification_panel.modulate.a = 0
	notification_panel.visible = true
	notification_panel.scale = Vector2(0.9, 0.9)
	
	# Fade in
	tween.tween_property(notification_panel, "modulate:a", 1.0, 0.2)
	tween.parallel().tween_property(notification_panel, "scale", Vector2(1.0, 1.0), 0.25)
	
	# Wait
	tween.tween_interval(2.0)
	
	# Fade out
	tween.tween_property(notification_panel, "modulate:a", 0, 0.3)
	tween.tween_callback(func(): notification_panel.visible = false)
#------------------------------------------------------------------
#endregion

# Main process function
func _process(delta):
	# Update tooltip position if visible
	if $Control/TooltipPanel.visible and tooltip_item != null:
		$Control/TooltipPanel.global_position = get_viewport().get_mouse_position() + Vector2(20, 20)
	
	# Process any pending animation updates
	process_pending_animation_updates()
	
	# Check hand animations for slots without direct signal connections
	check_hand_animations()
	
	# Periodically check for inventory discrepancies to catch ghost items
	last_inventory_check_time += delta
	if last_inventory_check_time > inventory_check_interval:
		verify_hand_items_exist()
		last_inventory_check_time = 0
	
	# Update tooltip position if visible
	if $Control/TooltipPanel.visible and tooltip_item != null:
		$Control/TooltipPanel.global_position = get_viewport().get_mouse_position() + Vector2(20, 20)
	
	# Update drag preview position if dragging
	if dragging_item != null:
		drag_preview.global_position = get_viewport().get_mouse_position() - drag_origin
		
		# If we're over a valid slot, add a subtle attraction effect
		if drag_over_slot != null:
			var slot_element = find_slot_element(drag_over_slot)
			if slot_element:
				var target_pos = slot_element.global_position + slot_element.size / 2
				var attraction_strength = 0.1  # Lower values = more subtle
				drag_preview.global_position = drag_preview.global_position.lerp(
					target_pos - drag_origin, 
					attraction_strength
				)
	
	# Handle animated hand indicators - subtle pulsing
	var left_indicator = $Control/HandSlots/LeftHand/ActiveLeftIndicator
	var right_indicator = $Control/HandSlots/RightHand/ActiveRightIndicator
	
	if left_indicator and left_indicator.visible:
		left_indicator.modulate.a = 0.5 + (sin(Time.get_ticks_msec() * 0.002) * 0.2)
	
	if right_indicator and right_indicator.visible:
		right_indicator.modulate.a = 0.5 + (sin(Time.get_ticks_msec() * 0.002) * 0.2)

func process_pending_animation_updates():
	"""Process any animation updates that were queued from signal handlers"""
	if pending_animation_updates.size() > 0:
		for slot_name in pending_animation_updates.keys():
			var update = pending_animation_updates[slot_name]
			if update.size() >= 2 and is_instance_valid(update[0]) and is_instance_valid(update[1]):
				update_animated_sprite_properties(update[0], update[1], slot_name)
		
		# Clear processed updates
		pending_animation_updates.clear()

func check_hand_animations():
	"""Check hand items for animation changes as a fallback mechanism"""
	if inventory_system:
		# Only handle slots that don't have direct signal connections
		var slots_to_check = []
		for slot_name in ["LeftHandSlot", "RightHandSlot"]:
			if not animation_signal_connections.has(slot_name):
				slots_to_check.append(slot_name)
		
		# No slots to check
		if slots_to_check.size() == 0:
			return
			
		# Check each slot
		for slot_name in slots_to_check:
			var item = hand_slot_items.get(slot_name)
			if item and is_instance_valid(item):
				var item_sprite = get_item_animated_sprite(item)
				if item_sprite and is_instance_valid(item_sprite):
					var ui_sprite = slot_item_sprites.get(slot_name)
					
					if ui_sprite and ui_sprite is AnimatedSprite2D:
						# Check if animation has changed
						if item_sprite.animation != current_hand_animations.get(slot_name, ""):
							update_animated_sprite_properties(ui_sprite, item_sprite, slot_name)
						# Check for play/stop state changes
						elif item_sprite.is_playing() != ui_sprite.is_playing():
							if item_sprite.is_playing():
								ui_sprite.play(item_sprite.animation)
							else:
								ui_sprite.stop()
								ui_sprite.frame = item_sprite.frame

# Handler for mouse button press with modifiers
func handle_mouse_down(position: Vector2, button_index: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	"""Handle mouse down events for inventory with modifier support"""
	# Store click start data
	drag_start_position = position
	last_click_button = button_index
	
	# Check for double click
	var current_time = Time.get_ticks_msec() / 1000.0
	is_double_click = false
	
	if button_index == last_click_button:
		var time_since_last_click = current_time - last_click_time
		var distance_from_last_click = position.distance_to(last_click_position)
		
		if time_since_last_click < DOUBLE_CLICK_TIME and distance_from_last_click < 10:
			is_double_click = true
			print("PlayerUI: Detected double click")
	
	# Update click tracking
	last_click_position = position
	last_click_time = current_time
	
	# Check if we're over a slot with an item
	for slot_name in slot_mapping:
		var slot_element = find_slot_element(slot_name)
		if slot_element and slot_element.visible and slot_element.get_global_rect().has_point(position):
			var equip_slot = slot_mapping[slot_name]
			var item = inventory_system.get_item_in_slot(equip_slot)
			
			if item != null:
				# Handle based on modifiers
				if is_double_click:
					handle_item_double_click(item, slot_name)
				elif shift_pressed and ctrl_pressed and alt_pressed:
					handle_shift_ctrl_alt_click(item, slot_name)
				elif shift_pressed and ctrl_pressed:
					handle_shift_ctrl_click(item, slot_name)
				elif shift_pressed and alt_pressed:
					handle_shift_alt_click(item, slot_name)
				elif ctrl_pressed and alt_pressed:
					handle_ctrl_alt_click(item, slot_name)
				elif shift_pressed:
					handle_shift_click(item, slot_name)
				elif ctrl_pressed:
					handle_ctrl_click(item, slot_name)
				elif alt_pressed:
					handle_alt_click(item, slot_name)
				else:
					# Regular click - start drag operation
					mouse_down_over_item = true
					start_dragging_from_slot(slot_name)
				
				return
	
	# Handle hand slots explicitly
	handle_hand_slot_click(position, shift_pressed, ctrl_pressed, alt_pressed)

# Handler for mouse button release with modifiers
func handle_mouse_up(position: Vector2, button_index: int, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	"""Handle mouse up events for completing drag operations with modifier support"""
	# Calculate distance moved since click start
	var distance_moved = position.distance_to(drag_start_position)
	
	# If we weren't dragging or moved very little, treat as a click
	if !is_dragging or distance_moved < DRAG_START_DISTANCE:
		# Click release was already handled in mouse down for items
		pass
	else:
		# We have an existing drag operation to complete
		if dragging_item != null:
			# Check if we're over a valid slot
			var drag_over_slot = null
			for slot_name in slot_mapping:
				var slot_element = find_slot_element(slot_name)
				if slot_element and slot_element.visible and slot_element.get_global_rect().has_point(position):
					drag_over_slot = slot_name
					break
			
			if drag_over_slot:
				drop_item_into_slot(drag_over_slot)
			else:
				# Mouse released outside UI - throw the item
				throw_dragged_item(position)
	
	# Reset drag state
	is_dragging = false
	
	# Start cooldown timer
	click_cooldown_timer = CLICK_COOLDOWN

# Handler for right click press
func handle_right_click_press(position: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	"""Handle right-click press with modifiers"""
	for slot_name in slot_mapping:
		var slot_element = find_slot_element(slot_name)
		if slot_element and slot_element.visible and slot_element.get_global_rect().has_point(position):
			var equip_slot = slot_mapping[slot_name]
			var item = inventory_system.get_item_in_slot(equip_slot)
			
			if item != null:
				# Emit signal with the right-clicked item
				emit_signal("item_right_clicked", item)
				
				# Special handling based on item type
				if "context_menu" in item and item.has_method("show_context_menu"):
					item.show_context_menu(position)
				
				# Play sound feedback
				play_sound_effect(SoundEffect.CLICK)
				return

# Handler for right click release
func handle_right_click_release(position: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	"""Handle right-click release with modifiers"""
	# Usually handled in press, but can add custom release behavior here
	pass

# Handler for middle click press
func handle_middle_click_press(position: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	"""Handle middle-click press with modifiers"""
	for slot_name in slot_mapping:
		var slot_element = find_slot_element(slot_name)
		if slot_element and slot_element.visible and slot_element.get_global_rect().has_point(position):
			var equip_slot = slot_mapping[slot_name]
			var item = inventory_system.get_item_in_slot(equip_slot)
			
			if item != null:
				# Emit signal with the middle-clicked item
				emit_signal("item_middle_clicked", item)
				
				# Default middle-click behavior: examine item
				examine_item(item)
				
				# Play feedback
				play_sound_effect(SoundEffect.CLICK)
				return

# Handler for middle click release
func handle_middle_click_release(position: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	"""Handle middle-click release with modifiers"""
	# Usually used for panning view or other release functionality
	pass

# Handler for hand slot clicks specifically
func handle_hand_slot_click(position: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	"""Handle clicks on hand slots with modifier support"""
	var left_hand = $Control/HandSlots/LeftHand if has_node("Control/HandSlots/LeftHand") else null
	var right_hand = $Control/HandSlots/RightHand if has_node("Control/HandSlots/RightHand") else null

	if left_hand and left_hand.get_global_rect().has_point(position):
		if inventory_system:
			var item = inventory_system.get_item_in_slot(13) # LEFT_HAND
			if item != null:
				# Handle based on modifiers
				if shift_pressed and ctrl_pressed and alt_pressed:
					handle_shift_ctrl_alt_click(item, "LeftHandSlot")
				elif shift_pressed and ctrl_pressed:
					handle_shift_ctrl_click(item, "LeftHandSlot")
				elif shift_pressed and alt_pressed:
					handle_shift_alt_click(item, "LeftHandSlot")
				elif ctrl_pressed and alt_pressed:
					handle_ctrl_alt_click(item, "LeftHandSlot")
				elif shift_pressed:
					handle_shift_click(item, "LeftHandSlot")
				elif ctrl_pressed:
					handle_ctrl_click(item, "LeftHandSlot")
				elif alt_pressed:
					handle_alt_click(item, "LeftHandSlot")
				else:
					# Regular click - start drag operation
					start_dragging_from_slot("LeftHandSlot")
			else:
				# Set left hand as active
				if inventory_system.active_hand != 13:
					inventory_system.active_hand = 13
					update_active_hand()
					if left_hand:
						flash_hand_selection(left_hand)
					play_sound_effect(SoundEffect.CLICK)
	elif right_hand and right_hand.get_global_rect().has_point(position):
		if inventory_system:
			var item = inventory_system.get_item_in_slot(14) # RIGHT_HAND
			if item != null:
				# Handle based on modifiers
				if shift_pressed and ctrl_pressed and alt_pressed:
					handle_shift_ctrl_alt_click(item, "RightHandSlot")
				elif shift_pressed and ctrl_pressed:
					handle_shift_ctrl_click(item, "RightHandSlot")
				elif shift_pressed and alt_pressed:
					handle_shift_alt_click(item, "RightHandSlot")
				elif ctrl_pressed and alt_pressed:
					handle_ctrl_alt_click(item, "RightHandSlot")
				elif shift_pressed:
					handle_shift_click(item, "RightHandSlot")
				elif ctrl_pressed:
					handle_ctrl_click(item, "RightHandSlot")
				elif alt_pressed:
					handle_alt_click(item, "RightHandSlot")
				else:
					# Regular click - start drag operation
					start_dragging_from_slot("RightHandSlot")
			else:
				# Set right hand as active
				if inventory_system.active_hand != 14:
					inventory_system.active_hand = 14
					update_active_hand()
					if right_hand:
						flash_hand_selection(right_hand)
					play_sound_effect(SoundEffect.CLICK)

# Handler for shift clicks on items
func handle_shift_click(item, slot_name):
	"""Handle shift-click on an item"""
	print("PlayerUI: Shift-click detected on item in slot:", slot_name)
	
	# Emit signal
	emit_signal("item_shift_clicked", item)
	
	# Default behavior: Try to move item to belt/backpack/storage
	if inventory_system and inventory_system.has_method("store_item"):
		inventory_system.store_item(item)
		play_sound_effect(SoundEffect.CLICK)
	
	# If item has a method for shift-click, use it
	if item.has_method("on_shift_click"):
		item.on_shift_click(entity)

# Handler for ctrl clicks on items
func handle_ctrl_click(item, slot_name):
	"""Handle ctrl-click on an item"""
	print("PlayerUI: Ctrl-click detected on item in slot:", slot_name)
	
	# Emit signal
	emit_signal("item_ctrl_clicked", item)
	
	# Default behavior: Examine item in detail
	examine_item(item)
	
	# If item has a method for ctrl-click, use it
	if item.has_method("on_ctrl_click"):
		item.on_ctrl_click(entity)

# Handler for alt clicks on items
func handle_alt_click(item, slot_name):
	"""Handle alt-click on an item"""
	print("PlayerUI: Alt-click detected on item in slot:", slot_name)
	
	# Emit signal
	emit_signal("item_alt_clicked", item)
	
	# Default behavior: Use alternative action of item
	if item.has_method("alt_click"):
		item.alt_click(entity)
	elif item.has_method("secondary_action"):
		item.secondary_action(entity)
	
	# Play feedback
	play_sound_effect(SoundEffect.CLICK)

# Handler for shift+ctrl clicks
func handle_shift_ctrl_click(item, slot_name):
	"""Handle shift+ctrl-click on an item"""
	print("PlayerUI: Shift+Ctrl-click detected on item in slot:", slot_name)
	
	# Default behavior: Advanced action
	if item.has_method("on_shift_ctrl_click"):
		item.on_shift_ctrl_click(entity)
	
	# Play feedback
	play_sound_effect(SoundEffect.CLICK)

# Handler for shift+alt clicks
func handle_shift_alt_click(item, slot_name):
	"""Handle shift+alt-click on an item"""
	print("PlayerUI: Shift+Alt-click detected on item in slot:", slot_name)
	
	# Default behavior: Special action
	if item.has_method("on_shift_alt_click"):
		item.on_shift_alt_click(entity)
	
	# Play feedback
	play_sound_effect(SoundEffect.CLICK)

# Handler for ctrl+alt clicks
func handle_ctrl_alt_click(item, slot_name):
	"""Handle ctrl+alt-click on an item"""
	print("PlayerUI: Ctrl+Alt-click detected on item in slot:", slot_name)
	
	# Default behavior: Toggle mode or similar advanced action
	if item.has_method("on_ctrl_alt_click"):
		item.on_ctrl_alt_click(entity)
	elif item.has_method("toggle_mode"):
		item.toggle_mode()
	
	# Play feedback
	play_sound_effect(SoundEffect.CLICK)

# Handler for shift+ctrl+alt clicks
func handle_shift_ctrl_alt_click(item, slot_name):
	"""Handle shift+ctrl+alt-click on an item"""
	print("PlayerUI: Shift+Ctrl+Alt-click detected on item in slot:", slot_name)
	
	# Usually a rare, special action
	if item.has_method("on_shift_ctrl_alt_click"):
		item.on_shift_ctrl_alt_click(entity)
	
	# Play feedback
	play_sound_effect(SoundEffect.CLICK)

# Handler for double clicks
func handle_item_double_click(item, slot_name):
	"""Handle double-click on an item"""
	print("PlayerUI: Double-click detected on item in slot:", slot_name)
	
	# Emit signal
	emit_signal("item_double_clicked", item)
	
	# Default behavior: Use item on self or activate
	if item.has_method("use_on_self"):
		item.use_on_self(entity)
	elif item.has_method("activate"):
		item.activate(entity)
	
	# Play feedback
	play_sound_effect(SoundEffect.CLICK)

# Helper to examine an item
func examine_item(item):
	"""Examine an item to show its details"""
	if !item:
		return
	
	var description = "An item."
	
	# Get description from item
	if "description" in item:
		description = item.description
	elif item.has_method("get_description"):
		description = item.get_description()
	elif item.has_method("examine"):
		description = item.examine()
	
	# If item has a detailed examine method, use that
	if item.has_method("examine_detailed"):
		description = item.examine_detailed()
	
	# Show notification or tooltip with the information
	if description:
		show_notification(description, "info")
		
	# Play feedback sound
	play_sound_effect(SoundEffect.CLICK)

func get_world_throw_distance(screen_distance: float) -> float:
	"""Convert screen distance to world distance for throws"""
	# If we have a camera reference, account for zoom
	var camera = get_viewport().get_camera_2d()
	if camera:
		return screen_distance / camera.zoom.x
	return screen_distance

func get_normalized_drag_value(start_pos: Vector2, end_pos: Vector2) -> float:
	"""Get a normalized value (0-1) based on drag distance with better curve"""
	var distance = start_pos.distance_to(end_pos)
	
	# Normalize between minimum and maximum throw distances
	var normalized = clamp((distance - throw_minimum_distance) / 
						  (MAX_THROW_DISTANCE - throw_minimum_distance), 0.0, 1.0)
	
	# Apply curve for more intuitive control (squared for more precision with short throws)
	return normalized * normalized

func update_throw_feedback(current_pos: Vector2):
	"""Update visual feedback for throw strength during drag"""
	if !is_dragging or !drag_preview.visible:
		return
	
	var distance = drag_start_position.distance_to(current_pos)
	var normalized = get_normalized_drag_value(drag_start_position, current_pos)
	
	# Visual feedback: color changes from green (short throw) to yellow to red (max throw)
	var color = lerp(Color(0.2, 0.8, 0.2), Color(0.8, 0.2, 0.2), normalized)

func is_position_in_ui_element(position: Vector2) -> bool:
	"""Check if a position is inside any PlayerUI interactive element"""
	# Check hand slots
	var left_hand = $Control/HandSlots/LeftHand if has_node("Control/HandSlots/LeftHand") else null
	var right_hand = $Control/HandSlots/RightHand if has_node("Control/HandSlots/RightHand") else null
	
	if left_hand and left_hand.visible and left_hand.get_global_rect().has_point(position):
		return true
		
	if right_hand and right_hand.visible and right_hand.get_global_rect().has_point(position):
		return true
	
	# Check equipment slots
	if $Control/EquipmentItems/EquipmentButton/EquipmentSlots.visible:
		for slot_name in slot_mapping:
			var slot_element = find_slot_element(slot_name)
			if slot_element and slot_element.visible and slot_element.get_global_rect().has_point(position):
				return true
	
	# Check main slots (belt, backpack, ID)
	for slot_name in ["BackSlot", "BeltSlot", "IDSlot"]:
		var slot_element = get_node_or_null("Control/MainSlots/" + slot_name)
		if slot_element and slot_element.visible and slot_element.get_global_rect().has_point(position):
			return true
	
	# Check pouch slots
	for i in range(1, 3):
		var pouch_slot = get_node_or_null("Control/PouchSlots/Pouch" + str(i))
		if pouch_slot and pouch_slot.visible and pouch_slot.get_global_rect().has_point(position):
			return true
	
	# Check if dragging an item
	if dragging_item != null:
		return true
		
	return false
