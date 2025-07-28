extends CanvasLayer
class_name PlayerUI

# Signals for item interaction events
signal item_alt_clicked(item: Node)
signal item_ctrl_clicked(item: Node)
signal item_shift_clicked(item: Node)
signal item_right_clicked(item: Node)
signal item_middle_clicked(item: Node)
signal item_double_clicked(item: Node)

# Component references
var entity: Node = null
var inventory_system: Node = null
var item_interaction_component: Node = null
var weapon_handling_component: Node = null

# Drag and drop state
var drag_start_position: Vector2 = Vector2.ZERO
var is_dragging: bool = false
var drag_minimum_distance: int = 20
var dragging_item: Node = null
var dragging_from_slot = null
var drag_preview: Node = null

# Equipment slot mappings to inventory slots
var slot_mapping: Dictionary = {
	"HeadSlot": 1,
	"EyesSlot": 2,
	"BackSlot": 3,
	"MaskSlot": 4,
	"UniformSlot": 6,
	"ArmorSlot": 7,
	"EarsSlot": 8,
	"GlovesSlot": 9,
	"ShoesSlot": 10,
	"IDSlot": 12,
	"LeftHandSlot": 13,
	"RightHandSlot": 14,
	"BeltSlot": 15,
	"Pouch1": 16,
	"Pouch2": 17,
	"SuitSlot": 18
}

# UI state tracking
var slot_item_sprites: Dictionary = {}
var current_intent: int = 0
var is_movement_sprint: bool = true

# Input timing constants
const DOUBLE_CLICK_TIME: float = 0.3
const DRAG_START_DISTANCE: int = 5
var last_click_time: float = 0.0

# Intent types
enum Intent {HELP, DISARM, GRAB, HARM}

# Sound effects for feedback
enum SoundEffect {CLICK, EQUIP, UNEQUIP, DROP, THROW, ERROR}
var sound_effects: Dictionary = {
	SoundEffect.CLICK: preload("res://Sound/machines/Click_standard.wav") if ResourceLoader.exists("res://Sound/machines/Click_standard.wav") else null,
	SoundEffect.EQUIP: preload("res://Sound/handling/Uniform.wav") if ResourceLoader.exists("res://Sound/handling/Uniform.wav") else null,
	SoundEffect.UNEQUIP: preload("res://Sound/handling/Armor.wav") if ResourceLoader.exists("res://Sound/handling/Armor.wav") else null,
	SoundEffect.DROP: preload("res://Sound/handling/tape_drop.ogg") if ResourceLoader.exists("res://Sound/handling/tape_drop.ogg") else null,
	SoundEffect.THROW: preload("res://Sound/effects/throwing/throw.wav") if ResourceLoader.exists("res://Sound/effects/throwing/throw.wav") else null,
	SoundEffect.ERROR: preload("res://Sound/machines/terminal_error.ogg") if ResourceLoader.exists("res://Sound/machines/terminal_error.ogg") else null
}

func _ready():
	setup_ui()
	find_and_connect_player()

# Sets up UI components and drag preview
func setup_ui():
	drag_preview = $Control/DragPreview
	if drag_preview:
		drag_preview.visible = false
	
	initialize_slot_sprites()
	connect_ui_elements()

# Finds and connects to the authoritative player
func find_and_connect_player():
	await get_tree().create_timer(0.1).timeout
	
	var found_player = null
	var players = get_tree().get_nodes_in_group("player_controller")
	
	for player in players:
		if player.is_multiplayer_authority():
			found_player = player
			break
	
	if found_player:
		connect_to_player(found_player)
	else:
		await get_tree().create_timer(0.5).timeout
		find_and_connect_player()

# Establishes connection to player entity
func connect_to_player(player: Node):
	entity = player
	
	if not entity.is_multiplayer_authority():
		visible = false
		return
	
	# Connect to all required components
	item_interaction_component = entity.get_node_or_null("ItemInteractionComponent")
	inventory_system = entity.get_node_or_null("InventorySystem")
	weapon_handling_component = entity.get_node_or_null("WeaponHandlingComponent")
	
	# Connect signals
	if inventory_system:
		connect_inventory_signals()
	
	# Setup UI
	register_with_click_component()
	update_all_slots()
	update_active_hand()
	update_intent_buttons()
	update_movement_buttons()

# Registers this UI with the entity's click component
func register_with_click_component():
	if entity and entity.has_method("register_player_ui"):
		entity.register_player_ui(self)

# Connects signals from inventory system
func connect_inventory_signals():
	if not inventory_system:
		return
	
	if inventory_system.has_signal("inventory_updated"):
		if not inventory_system.inventory_updated.is_connected(_on_inventory_updated):
			inventory_system.inventory_updated.connect(_on_inventory_updated)
	if inventory_system.has_signal("item_equipped"):
		if not inventory_system.item_equipped.is_connected(_on_item_equipped):
			inventory_system.item_equipped.connect(_on_item_equipped)
	if inventory_system.has_signal("item_unequipped"):
		if not inventory_system.item_unequipped.is_connected(_on_item_unequipped):
			inventory_system.item_unequipped.connect(_on_item_unequipped)
	if inventory_system.has_signal("active_hand_changed"):
		if not inventory_system.active_hand_changed.is_connected(_on_active_hand_changed):
			inventory_system.active_hand_changed.connect(_on_active_hand_changed)

# Creates sprite nodes for all equipment slots
func initialize_slot_sprites():
	create_hand_slot_sprites()
	create_equipment_slot_sprites()
	create_main_slot_sprites()
	create_pouch_slot_sprites()

# Creates sprites for hand slots
func create_hand_slot_sprites():
	create_slot_sprite("LeftHandSlot", $Control/HandSlots/LeftHand)
	create_slot_sprite("RightHandSlot", $Control/HandSlots/RightHand)

# Creates sprites for equipment slots
func create_equipment_slot_sprites():
	var equipment_slots = ["HeadSlot", "EyesSlot", "MaskSlot", "UniformSlot", "ArmorSlot", "GlovesSlot", "ShoesSlot", "SuitSlot"]
	for slot_name in equipment_slots:
		var slot_rect = get_node_or_null("Control/EquipmentItems/EquipmentButton/EquipmentSlots/GridContainer/" + slot_name)
		if slot_rect:
			create_slot_sprite(slot_name, slot_rect)
	
	create_ear_slot_sprites()

# Creates sprites for ear slots
func create_ear_slot_sprites():
	var ear1_slot = get_node_or_null("Control/EquipmentItems/EquipmentButton/EquipmentSlots/GridContainer/Ear1Slot")
	var ear2_slot = get_node_or_null("Control/EquipmentItems/EquipmentButton/EquipmentSlots/GridContainer/Ear2Slot")
	if ear1_slot:
		create_slot_sprite("EarsSlot", ear1_slot, "Ear1ItemSprite")
	if ear2_slot:
		create_slot_sprite("EarsSlot", ear2_slot, "Ear2ItemSprite")

# Creates sprites for main slots
func create_main_slot_sprites():
	create_slot_sprite("BackSlot", $Control/MainSlots/BackSlot)
	create_slot_sprite("BeltSlot", $Control/MainSlots/BeltSlot)
	create_slot_sprite("IDSlot", $Control/MainSlots/IDSlot)

# Creates sprites for pouch slots
func create_pouch_slot_sprites():
	create_slot_sprite("Pouch1", $Control/PouchSlots/Pouch1)
	create_slot_sprite("Pouch2", $Control/PouchSlots/Pouch2)

# Creates a sprite node for displaying items in slots
func create_slot_sprite(slot_name: String, slot_container: Control, custom_name: String = ""):
	if not slot_container:
		return
	
	var sprite_name = custom_name if custom_name != "" else slot_name + "ItemSprite"
	
	var existing_sprite = slot_container.get_node_or_null(sprite_name)
	if existing_sprite:
		existing_sprite.queue_free()
	
	var item_sprite = Sprite2D.new()
	item_sprite.name = sprite_name
	item_sprite.position = slot_container.size / 2
	item_sprite.scale = Vector2(0.8, 0.8)
	item_sprite.visible = false
	
	slot_container.add_child(item_sprite)
	
	if custom_name == "":
		slot_item_sprites[slot_name] = item_sprite

# Connects mouse and keyboard events for UI elements
func connect_ui_elements():
	connect_slot_events()
	connect_intent_buttons()
	connect_hand_slots()
	connect_equipment_button()
	connect_movement_buttons()

# Connects events for equipment and main slots
func connect_slot_events():
	connect_equipment_slot_events()
	connect_main_slot_events()
	connect_pouch_slot_events()

# Connects events for equipment slots
func connect_equipment_slot_events():
	var equipment_slots = ["HeadSlot", "EyesSlot", "MaskSlot", "UniformSlot", "ArmorSlot", "GlovesSlot", "ShoesSlot", "SuitSlot"]
	
	for slot_name in equipment_slots:
		var slot_container = get_node_or_null("Control/EquipmentItems/EquipmentButton/EquipmentSlots/GridContainer/" + slot_name)
		var slot_button = get_node_or_null("Control/EquipmentItems/EquipmentButton/EquipmentSlots/GridContainer/" + slot_name + "/" + slot_name + "Button")
		
		if slot_container:
			slot_container.mouse_entered.connect(_on_slot_mouse_entered.bind(slot_name))
			slot_container.mouse_exited.connect(_on_slot_mouse_exited.bind(slot_name))
			slot_container.mouse_filter = Control.MOUSE_FILTER_PASS
		
		if slot_button:
			slot_button.mouse_entered.connect(_on_slot_mouse_entered.bind(slot_name))
			slot_button.mouse_exited.connect(_on_slot_mouse_exited.bind(slot_name))
			slot_button.pressed.connect(_on_equipment_slot_button_clicked.bind(slot_name))
			slot_button.gui_input.connect(_on_equipment_slot_gui_input.bind(slot_name))
			slot_button.mouse_filter = Control.MOUSE_FILTER_PASS

# Connects events for main slots
func connect_main_slot_events():
	for slot_name in ["BackSlot", "BeltSlot", "IDSlot"]:
		var slot_container = get_node_or_null("Control/MainSlots/" + slot_name)
		var slot_button = get_node_or_null("Control/MainSlots/" + slot_name + "/" + slot_name + "Button")
		
		if slot_container:
			slot_container.mouse_entered.connect(_on_slot_mouse_entered.bind(slot_name))
			slot_container.mouse_exited.connect(_on_slot_mouse_exited.bind(slot_name))
		
		if slot_button:
			slot_button.mouse_entered.connect(_on_slot_mouse_entered.bind(slot_name))
			slot_button.mouse_exited.connect(_on_slot_mouse_exited.bind(slot_name))
			slot_button.pressed.connect(_on_main_slot_button_clicked.bind(slot_name))

# Connects events for pouch slots
func connect_pouch_slot_events():
	for slot_name in ["Pouch1", "Pouch2"]:
		var slot_container = get_node_or_null("Control/PouchSlots/" + slot_name)
		var slot_button = get_node_or_null("Control/PouchSlots/" + slot_name + "/" + slot_name + "Button")
		
		if slot_container:
			slot_container.mouse_entered.connect(_on_slot_mouse_entered.bind(slot_name))
			slot_container.mouse_exited.connect(_on_slot_mouse_exited.bind(slot_name))
		
		if slot_button:
			slot_button.mouse_entered.connect(_on_slot_mouse_entered.bind(slot_name))
			slot_button.mouse_exited.connect(_on_slot_mouse_exited.bind(slot_name))
			slot_button.pressed.connect(_on_pouch_slot_button_clicked.bind(slot_name))

# Connects events for hand slots
func connect_hand_slots():
	if $Control/HandSlots/LeftHand:
		$Control/HandSlots/LeftHand.mouse_entered.connect(_on_slot_mouse_entered.bind("LeftHandSlot"))
		$Control/HandSlots/LeftHand.mouse_exited.connect(_on_slot_mouse_exited.bind("LeftHandSlot"))
		$Control/HandSlots/LeftHand.pressed.connect(_on_hand_slot_clicked.bind("LeftHandSlot"))
	
	if $Control/HandSlots/RightHand:
		$Control/HandSlots/RightHand.mouse_entered.connect(_on_slot_mouse_entered.bind("RightHandSlot"))
		$Control/HandSlots/RightHand.mouse_exited.connect(_on_slot_mouse_exited.bind("RightHandSlot"))
		$Control/HandSlots/RightHand.pressed.connect(_on_hand_slot_clicked.bind("RightHandSlot"))

# Connects events for equipment menu button
func connect_equipment_button():
	if $Control/EquipmentItems/EquipmentButton:
		$Control/EquipmentItems/EquipmentButton.gui_input.connect(_on_equipment_button_gui_input)
		$Control/EquipmentItems/EquipmentButton.toggled.connect(_on_equipment_button_toggled)

# Connects events for movement buttons
func connect_movement_buttons():
	if $Control/MovementButtons/RunButton:
		$Control/MovementButtons/RunButton.pressed.connect(_on_run_button_pressed)
	if $Control/MovementButtons/WalkButton:
		$Control/MovementButtons/WalkButton.pressed.connect(_on_walk_button_pressed)

# Connects signal handlers for intent buttons
func connect_intent_buttons():
	if $Control/IntentSelector/HelpIntent:
		$Control/IntentSelector/HelpIntent.toggled.connect(_on_intent_toggled.bind(Intent.HELP))
	if $Control/IntentSelector/DisarmIntent:
		$Control/IntentSelector/DisarmIntent.toggled.connect(_on_intent_toggled.bind(Intent.DISARM))
	if $Control/IntentSelector/GrabIntent:
		$Control/IntentSelector/GrabIntent.toggled.connect(_on_intent_toggled.bind(Intent.GRAB))
	if $Control/IntentSelector/HarmIntent:
		$Control/IntentSelector/HarmIntent.toggled.connect(_on_intent_toggled.bind(Intent.HARM))

# Main input handler for keyboard shortcuts
func _input(event: InputEvent):
	if not can_perform_ui_action():
		return
	
	if event is InputEventKey and event.pressed:
		handle_keyboard_input(event)
	elif event is InputEventMouseButton:
		handle_mouse_input(event)

# Handles keyboard shortcuts for inventory actions
func handle_keyboard_input(event: InputEventKey):
	if not inventory_system:
		return
	
	match event.keycode:
		KEY_Z:
			# Use active item through item interaction component
			if item_interaction_component:
				await item_interaction_component.use_active_item()
				play_sound_effect(SoundEffect.CLICK)
		KEY_Q:
			# Drop item through item interaction component
			if item_interaction_component:
				item_interaction_component.drop_active_item()
				play_sound_effect(SoundEffect.DROP)
		KEY_R:
			# Quick eject magazine if wielding weapon
			var wielded_weapon = inventory_system.get_wielded_weapon()
			if wielded_weapon and weapon_handling_component:
				weapon_handling_component.eject_magazine_to_floor(wielded_weapon)
				play_sound_effect(SoundEffect.CLICK)
		KEY_C:
			# Chamber round if wielding weapon
			var wielded_weapon = inventory_system.get_wielded_weapon()
			if wielded_weapon and weapon_handling_component:
				weapon_handling_component.chamber_round(wielded_weapon)
				play_sound_effect(SoundEffect.CLICK)
		KEY_1, KEY_2, KEY_3, KEY_4:
			var intent = event.keycode - KEY_1
			set_intent(intent)

# Handles mouse input events
func handle_mouse_input(event: InputEventMouseButton):
	if not is_position_in_ui(event.position):
		return
	
	var equipment_menu = $Control/EquipmentItems/EquipmentButton/EquipmentSlots
	
	if equipment_menu and equipment_menu.visible and equipment_menu.modulate.a > 0.5:
		if equipment_menu.get_global_rect().has_point(event.position):
			handle_equipment_menu_input(event)
			return
	
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				handle_left_click(event.position, event.shift_pressed, event.ctrl_pressed, event.alt_pressed)
			else:
				handle_left_release(event.position)
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				handle_right_click(event.position)

# Handles mouse input for equipment menu
func handle_equipment_menu_input(event: InputEventMouseButton):
	var equipment_slots = ["HeadSlot", "EyesSlot", "MaskSlot", "UniformSlot", "ArmorSlot", "GlovesSlot", "ShoesSlot", "SuitSlot"]
	
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				for slot_name in equipment_slots:
					var slot_container = get_slot_container(slot_name)
					if slot_container and slot_container.get_global_rect().has_point(event.position):
						handle_equipment_slot_click(slot_name, event)
						return
			else:
				handle_left_release(event.position)
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				for slot_name in equipment_slots:
					var slot_container = get_slot_container(slot_name)
					if slot_container and slot_container.get_global_rect().has_point(event.position):
						handle_equipment_slot_right_click(slot_name)
						return

# Handles left mouse clicks on slots
func handle_left_click(position: Vector2, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	drag_start_position = position
	
	var current_time = Time.get_ticks_msec() / 1000.0
	var is_double_click = (current_time - last_click_time) < DOUBLE_CLICK_TIME
	last_click_time = current_time
	
	for slot_name in slot_mapping:
		var slot_container = get_slot_container(slot_name)
		if slot_container and slot_container.get_global_rect().has_point(position):
			handle_slot_click(slot_name, is_double_click, shift_pressed, ctrl_pressed, alt_pressed)
			return

# Handles left mouse release for drag completion
func handle_left_release(position: Vector2):
	if is_dragging:
		handle_drag_release(position)
	
	is_dragging = false
	dragging_item = null
	dragging_from_slot = null

# Handles right mouse clicks for context actions
func handle_right_click(position: Vector2):
	if not inventory_system:
		return
	
	for slot_name in slot_mapping:
		var slot_container = get_slot_container(slot_name)
		if slot_container and slot_container.get_global_rect().has_point(position):
			var slot_id = slot_mapping[slot_name]
			var item = inventory_system.get_item_in_slot(slot_id)
			if item:
				emit_signal("item_right_clicked", item)
				play_sound_effect(SoundEffect.CLICK)
			return

# Main slot click handler - this is where we handle all slot interactions
func handle_slot_click(slot_name: String, is_double_click: bool, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	if not validate_equipment_interaction(slot_name):
		return
	
	var slot_id = slot_mapping[slot_name]
	var item = inventory_system.get_item_in_slot(slot_id)
	
	add_slot_click_highlight(slot_name)
	
	if item:
		handle_item_click(item, slot_name, slot_id, is_double_click, shift_pressed, ctrl_pressed, alt_pressed)
	else:
		handle_empty_slot_click(slot_name, slot_id)

# Handles clicks on slots containing items
func handle_item_click(item: Node, slot_name: String, slot_id: int, is_double_click: bool, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	# Handle weapon-specific interactions first
	if is_weapon(item):
		if handle_weapon_slot_interaction(item, slot_name, alt_pressed, ctrl_pressed, shift_pressed):
			return
	
	# Handle normal item interactions
	if is_double_click:
		emit_signal("item_double_clicked", item)
		use_item_in_slot(slot_id)
	elif shift_pressed:
		emit_signal("item_shift_clicked", item)
		handle_shift_item_click(item, slot_id)
	elif ctrl_pressed:
		emit_signal("item_ctrl_clicked", item)
		examine_item(item)
	elif alt_pressed:
		emit_signal("item_alt_clicked", item)
	else:
		start_drag(slot_name, item)

# Handle weapon-specific slot interactions
func handle_weapon_slot_interaction(weapon: Node, slot_name: String, alt_pressed: bool, ctrl_pressed: bool, shift_pressed: bool) -> bool:
	if not weapon_handling_component:
		return false
	
	# Alt+click to cycle firing mode
	if alt_pressed and not shift_pressed and not ctrl_pressed:
		weapon_handling_component.handle_weapon_alt_click(weapon)
		return true
	
	# Ctrl+click to eject magazine to floor
	if ctrl_pressed and not shift_pressed and not alt_pressed:
		weapon_handling_component.handle_weapon_ctrl_click(weapon)
		return true
	
	# Check for weapon reload interactions in hand slots
	if slot_name in ["LeftHandSlot", "RightHandSlot"] and not shift_pressed and not ctrl_pressed and not alt_pressed:
		return handle_hand_slot_weapon_interaction(slot_name, weapon)
	
	return false

# Handle weapon interactions with other hand
func handle_hand_slot_weapon_interaction(slot_name: String, weapon: Node) -> bool:
	if not weapon_handling_component:
		return false
	
	var other_slot_name = "RightHandSlot" if slot_name == "LeftHandSlot" else "LeftHandSlot"
	var other_slot_id = slot_mapping.get(other_slot_name, -1)
	var other_item = inventory_system.get_item_in_slot(other_slot_id) if other_slot_id != -1 else null
	
	# If other hand has a magazine, try to reload
	if other_item and is_magazine(other_item):
		weapon_handling_component.handle_weapon_click_with_magazine(weapon, other_item)
		return true
	
	# If other hand is empty, try to extract magazine
	if not other_item:
		weapon_handling_component.handle_weapon_click_with_empty_hand(weapon)
		return true
	
	return false

# Handles shift+click on items
func handle_shift_item_click(item: Node, slot_id: int):
	var equipment_slots = ["HeadSlot", "EyesSlot", "MaskSlot", "UniformSlot", "ArmorSlot", "GlovesSlot", "ShoesSlot", "SuitSlot"]
	var slot_name = slot_mapping.keys()[slot_mapping.values().find(slot_id)]
	
	if slot_name in equipment_slots:
		move_equipment_to_hand(item, slot_id)

# Moves equipment item to active hand
func move_equipment_to_hand(item: Node, slot_id: int):
	var active_hand = inventory_system.active_hand
	var active_item = inventory_system.get_active_item()
	
	if not active_item:
		var unequip_result = inventory_system.unequip_item(slot_id)
		if unequip_result == InventorySystem.ITEM_UNEQUIP_UNEQUIPPED:
			if inventory_system.equip_item(item, active_hand):
				play_sound_effect(SoundEffect.EQUIP)
			else:
				inventory_system.equip_item(item, slot_id)
				play_sound_effect(SoundEffect.ERROR)
	else:
		play_sound_effect(SoundEffect.ERROR)

# Handles clicks on empty slots - simplified for wielding
func handle_empty_slot_click(slot_name: String, slot_id: int):
	# Check if trying to switch hands while wielding
	if inventory_system.is_wielding_weapon():
		if slot_name in ["LeftHandSlot", "RightHandSlot"]:
			show_notification("You can't switch hands while wielding a weapon!")
			play_sound_effect(SoundEffect.ERROR)
			return
	
	if slot_name == "LeftHandSlot" and inventory_system.active_hand != 13:
		inventory_system.active_hand = 13
		update_active_hand()
		flash_hand_selection($Control/HandSlots/LeftHand)
		play_sound_effect(SoundEffect.CLICK)
	elif slot_name == "RightHandSlot" and inventory_system.active_hand != 14:
		inventory_system.active_hand = 14
		update_active_hand()
		flash_hand_selection($Control/HandSlots/RightHand)
		play_sound_effect(SoundEffect.CLICK)
	else:
		var equipment_slots = ["HeadSlot", "EyesSlot", "MaskSlot", "UniformSlot", "ArmorSlot", "GlovesSlot", "ShoesSlot", "SuitSlot"]
		if slot_name in equipment_slots:
			try_equip_to_equipment_slot(slot_name)

# Slot button click handlers - these prevent double events
func _on_hand_slot_clicked(slot_name: String):
	# Prevent double events from button clicks
	get_viewport().set_input_as_handled()

func _on_equipment_slot_button_clicked(slot_name: String):
	get_viewport().set_input_as_handled()

func _on_main_slot_button_clicked(slot_name: String):
	get_viewport().set_input_as_handled()

func _on_pouch_slot_button_clicked(slot_name: String):
	get_viewport().set_input_as_handled()

# Equipment slot specific handlers
func handle_equipment_slot_click(slot_name: String, event: InputEventMouseButton):
	if not inventory_system:
		return
	
	drag_start_position = event.position
	
	var current_time = Time.get_ticks_msec() / 1000.0
	var is_double_click = (current_time - last_click_time) < DOUBLE_CLICK_TIME
	last_click_time = current_time
	
	handle_slot_click(slot_name, is_double_click, event.shift_pressed, event.ctrl_pressed, event.alt_pressed)

func handle_equipment_slot_right_click(slot_name: String):
	if not inventory_system:
		return
	
	var slot_id = slot_mapping[slot_name]
	var item = inventory_system.get_item_in_slot(slot_id)
	if item:
		emit_signal("item_right_clicked", item)
		play_sound_effect(SoundEffect.CLICK)

func _on_equipment_slot_gui_input(event: InputEvent, slot_name: String):
	if not can_perform_ui_action():
		return
	
	if event is InputEventMouseButton and event.pressed:
		get_viewport().set_input_as_handled()
		
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				handle_equipment_slot_click(slot_name, event)
			MOUSE_BUTTON_RIGHT:
				handle_equipment_slot_right_click(slot_name)

# Drag and drop system
func start_drag(slot_name: String, item: Node):
	dragging_item = item
	dragging_from_slot = slot_name
	
	setup_drag_preview(item)
	play_sound_effect(SoundEffect.CLICK)

# Sets up drag preview visual
func setup_drag_preview(item: Node):
	var icon_node = item.get_node_or_null("Icon")
	if icon_node and drag_preview:
		if icon_node is Sprite2D and icon_node.texture:
			drag_preview.texture = icon_node.texture
		elif icon_node is AnimatedSprite2D and icon_node.sprite_frames:
			var anim = icon_node.animation if icon_node.animation != "" else icon_node.sprite_frames.get_animation_names()[0]
			drag_preview.texture = icon_node.sprite_frames.get_frame_texture(anim, icon_node.frame)
	
	if drag_preview:
		if not drag_preview.texture:
			drag_preview.texture = create_placeholder_texture()
		
		drag_preview.visible = true
		drag_preview.modulate.a = 0.7

# Handles drag release and item movement
func handle_drag_release(position: Vector2):
	if not dragging_item or not inventory_system:
		return
	
	var target_slot = find_target_slot(position)
	
	if target_slot and target_slot != dragging_from_slot:
		move_item_between_slots(dragging_from_slot, target_slot)
	else:
		var drag_distance = drag_start_position.distance_to(position)
		if drag_distance > drag_minimum_distance:
			throw_item_to_mouse_position(dragging_from_slot, position)
		else:
			cancel_drag()
	
	if drag_preview:
		drag_preview.visible = false

# Finds target slot for drag operation
func find_target_slot(position: Vector2) -> String:
	var equipment_menu = $Control/EquipmentItems/EquipmentButton/EquipmentSlots
	if equipment_menu and equipment_menu.visible and equipment_menu.modulate.a > 0.5:
		if equipment_menu.get_global_rect().has_point(position):
			var equipment_slots = ["HeadSlot", "EyesSlot", "MaskSlot", "UniformSlot", "ArmorSlot", "GlovesSlot", "ShoesSlot", "SuitSlot"]
			for slot_name in equipment_slots:
				var slot_container = get_slot_container(slot_name)
				if slot_container and slot_container.get_global_rect().has_point(position):
					return slot_name
	
	for slot_name in slot_mapping:
		if slot_name in ["HeadSlot", "EyesSlot", "MaskSlot", "UniformSlot", "ArmorSlot", "GlovesSlot", "ShoesSlot", "SuitSlot"]:
			continue
		
		var slot_container = get_slot_container(slot_name)
		if slot_container and slot_container.get_global_rect().has_point(position):
			return slot_name
	
	return ""

# Moves item between two slots
func move_item_between_slots(from_slot: String, to_slot: String):
	if not inventory_system:
		return
	
	var from_id = slot_mapping.get(from_slot, -1)
	var to_id = slot_mapping.get(to_slot, -1)
	
	if from_id == -1 or to_id == -1:
		return
	
	var item = inventory_system.get_item_in_slot(from_id)
	if not item:
		return
	
	if not inventory_system.can_equip_to_slot(item, to_id):
		play_sound_effect(SoundEffect.ERROR)
		return
	
	var unequip_result = inventory_system.unequip_item(from_id)
	if unequip_result != InventorySystem.ITEM_UNEQUIP_UNEQUIPPED:
		play_sound_effect(SoundEffect.ERROR)
		return
	
	if inventory_system.equip_item(item, to_id):
		play_sound_effect(SoundEffect.EQUIP)
	else:
		inventory_system.equip_item(item, from_id)
		play_sound_effect(SoundEffect.ERROR)

# Throws item towards mouse position
func throw_item_to_mouse_position(from_slot: String, mouse_position: Vector2):
	if not inventory_system or not entity:
		return
	
	var slot_id = slot_mapping[from_slot]
	var world_mouse_pos = entity.get_global_mouse_position()
	
	if inventory_system.throw_item_to_position(slot_id, world_mouse_pos):
		play_sound_effect(SoundEffect.THROW)
	else:
		inventory_system.drop_item(slot_id)
		play_sound_effect(SoundEffect.DROP)

# Cancels current drag operation
func cancel_drag():
	play_sound_effect(SoundEffect.CLICK)

# Updates drag preview position
func _process(delta: float):
	if dragging_item and drag_preview and drag_preview.visible:
		drag_preview.global_position = get_viewport().get_mouse_position() - Vector2(16, 16)
		
		if not is_dragging and drag_start_position.distance_to(get_viewport().get_mouse_position()) > DRAG_START_DISTANCE:
			is_dragging = true

# Item interaction methods
func use_item_in_slot(slot_id: int):
	if not inventory_system:
		return
	
	var old_active = inventory_system.active_hand
	inventory_system.active_hand = slot_id
	await inventory_system.use_active_item()
	inventory_system.active_hand = old_active
	
	play_sound_effect(SoundEffect.CLICK)

# Displays examination information for item
func examine_item(item: Node):
	var description = "An item."
	
	if item.has_method("examine"):
		description = item.examine(entity)
	elif "description" in item:
		description = item.description
	elif "item_name" in item:
		description = "This is " + item.item_name + "."
	
	show_notification(description)
	play_sound_effect(SoundEffect.CLICK)

# Visual update methods
func update_all_slots():
	if not inventory_system:
		return
	
	for slot_name in slot_mapping:
		update_slot(slot_name)

# Updates display of specific slot
func update_slot(slot_name: String):
	if not inventory_system:
		return
	
	var slot_id = slot_mapping.get(slot_name, -1)
	if slot_id == -1:
		return
	
	var item = inventory_system.get_item_in_slot(slot_id)
	display_item_in_slot(slot_name, item)

# Displays item sprite in slot
func display_item_in_slot(slot_name: String, item: Node):
	var sprite = get_slot_sprite(slot_name)
	
	if not item:
		if sprite:
			sprite.visible = false
		return
	
	var icon_node = item.get_node_or_null("Icon")
	if not icon_node:
		if sprite:
			sprite.visible = false
		return
	
	sprite = ensure_correct_sprite_type(slot_name, icon_node)
	if not sprite:
		return
	
	copy_icon_properties(sprite, icon_node)
	
	sprite.visible = true
	sprite.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(sprite, "modulate:a", 1.0, 0.2)

# Ensures sprite type matches icon type
func ensure_correct_sprite_type(slot_name: String, icon_node: Node) -> Node:
	var current_sprite = get_slot_sprite(slot_name)
	var needs_animated = icon_node is AnimatedSprite2D
	
	if (needs_animated and not (current_sprite is AnimatedSprite2D)) or (not needs_animated and (current_sprite is AnimatedSprite2D)):
		replace_slot_sprite(slot_name, needs_animated)
		current_sprite = get_slot_sprite(slot_name)
	
	return current_sprite

# Replaces slot sprite with correct type
func replace_slot_sprite(slot_name: String, use_animated: bool):
	var slot_container = get_slot_container(slot_name)
	if not slot_container:
		return
	
	var old_sprite = get_slot_sprite(slot_name)
	if old_sprite:
		old_sprite.queue_free()
	
	var new_sprite = null
	if use_animated:
		new_sprite = AnimatedSprite2D.new()
	else:
		new_sprite = Sprite2D.new()
	
	new_sprite.name = slot_name + "ItemSprite"
	new_sprite.position = slot_container.size / 2
	new_sprite.scale = Vector2(0.8, 0.8)
	new_sprite.visible = false
	
	slot_container.add_child(new_sprite)
	slot_item_sprites[slot_name] = new_sprite

# Copies icon properties to UI sprite
func copy_icon_properties(ui_sprite: Node, icon_node: Node):
	if icon_node is AnimatedSprite2D and ui_sprite is AnimatedSprite2D:
		ui_sprite.sprite_frames = icon_node.sprite_frames
		ui_sprite.animation = icon_node.animation
		ui_sprite.frame = icon_node.frame
		if icon_node.is_playing():
			ui_sprite.play()
		else:
			ui_sprite.stop()
	elif icon_node is Sprite2D and ui_sprite is Sprite2D:
		ui_sprite.texture = icon_node.texture
		ui_sprite.frame = icon_node.frame
		ui_sprite.hframes = icon_node.hframes
		ui_sprite.vframes = icon_node.vframes
	else:
		var texture = extract_texture_from_icon(icon_node)
		if texture and ui_sprite is Sprite2D:
			ui_sprite.texture = texture

# Extracts texture from icon node
func extract_texture_from_icon(icon_node: Node) -> Texture2D:
	if "texture" in icon_node:
		return icon_node.texture
	elif "sprite_frames" in icon_node and icon_node.sprite_frames:
		var anim_names = icon_node.sprite_frames.get_animation_names()
		if anim_names.size() > 0:
			var default_anim = anim_names[0]
			if icon_node.sprite_frames.get_frame_count(default_anim) > 0:
				return icon_node.sprite_frames.get_frame_texture(default_anim, 0)
	return null

# Updates active hand visual indicators - simplified
func update_active_hand():
	if not inventory_system:
		return
	
	var active_hand = inventory_system.active_hand
	var left_indicator = $Control/HandSlots/LeftHand/ActiveLeftIndicator
	var right_indicator = $Control/HandSlots/RightHand/ActiveRightIndicator
	var left_hand = $Control/HandSlots/LeftHand
	var right_hand = $Control/HandSlots/RightHand
	
	# Reset all indicators
	reset_hand_indicators(left_indicator, right_indicator, left_hand, right_hand)
	
	# Show active hand indicator
	if active_hand == 13 and left_indicator and left_hand:
		activate_left_hand_indicator(left_indicator, left_hand)
	elif active_hand == 14 and right_indicator and right_hand:
		activate_right_hand_indicator(right_indicator, right_hand)

# Resets all hand indicators
func reset_hand_indicators(left_indicator: Node, right_indicator: Node, left_hand: Node, right_hand: Node):
	if left_indicator:
		left_indicator.visible = false
	if right_indicator:
		right_indicator.visible = false
	
	if left_hand:
		left_hand.modulate = Color(0.8, 0.8, 0.8, 1.0)
	if right_hand:
		right_hand.modulate = Color(0.8, 0.8, 0.8, 1.0)

# Activates left hand indicator
func activate_left_hand_indicator(left_indicator: Node, left_hand: Node):
	left_indicator.visible = true
	left_indicator.modulate = Color(0.4, 0.8, 1.0, 0.8)
	left_hand.modulate = Color(1.2, 1.2, 1.2, 1.0)

# Activates right hand indicator
func activate_right_hand_indicator(right_indicator: Node, right_hand: Node):
	right_indicator.visible = true
	right_indicator.modulate = Color(0.4, 0.8, 1.0, 0.8)
	right_hand.modulate = Color(1.2, 1.2, 1.2, 1.0)

# Updates intent button states
func update_intent_buttons():
	var buttons = [
		$Control/IntentSelector/HelpIntent,
		$Control/IntentSelector/DisarmIntent,
		$Control/IntentSelector/GrabIntent,
		$Control/IntentSelector/HarmIntent
	]
	
	for i in range(buttons.size()):
		if buttons[i]:
			buttons[i].set_pressed_no_signal(i == current_intent)

# Updates movement button states
func update_movement_buttons():
	var run_button = $Control/MovementButtons/RunButton
	var walk_button = $Control/MovementButtons/WalkButton
	
	if run_button and walk_button:
		if is_movement_sprint:
			run_button.modulate = Color(1.2, 1.2, 1.2)
			walk_button.modulate = Color(0.7, 0.7, 0.7)
		else:
			run_button.modulate = Color(0.7, 0.7, 0.7)
			walk_button.modulate = Color(1.2, 1.2, 1.2)

# Visual effect methods
func add_slot_click_highlight(slot_name: String):
	var slot_container = get_slot_container(slot_name)
	if not slot_container:
		return
	
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	
	tween.tween_property(slot_container, "modulate", Color(1.5, 1.5, 1.5, 1.0), 0.1)
	tween.tween_property(slot_container, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.2)

# Creates flash effect for hand selection
func flash_hand_selection(hand_rect: Control):
	if not hand_rect:
		return
	
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	
	tween.tween_property(hand_rect, "modulate", Color(1.5, 1.8, 2.0, 1.0), 0.15)
	tween.tween_property(hand_rect, "modulate", Color(1.2, 1.2, 1.2, 1.0), 0.25)
	tween.tween_callback(update_active_hand)

# Tries to equip active item to equipment slot
func try_equip_to_equipment_slot(slot_name: String) -> bool:
	if not can_perform_ui_action():
		return false
	
	var slot_id = slot_mapping.get(slot_name, -1)
	if slot_id == -1:
		return false
	
	var active_item = inventory_system.get_active_item()
	var current_item = inventory_system.get_item_in_slot(slot_id)
	
	if not active_item:
		return false
	
	if not inventory_system.can_equip_to_slot(active_item, slot_id):
		play_sound_effect(SoundEffect.ERROR)
		return false
	
	var active_hand = inventory_system.active_hand
	
	if not current_item:
		return equip_to_empty_slot(active_item, slot_id, active_hand)
	else:
		return swap_items_between_slots(active_item, current_item, slot_id, active_hand)

# Equips item to empty slot
func equip_to_empty_slot(active_item: Node, slot_id: int, active_hand: int) -> bool:
	var unequip_result = inventory_system.unequip_item(active_hand)
	if unequip_result == InventorySystem.ITEM_UNEQUIP_UNEQUIPPED:
		if inventory_system.equip_item(active_item, slot_id):
			play_sound_effect(SoundEffect.EQUIP)
			return true
		else:
			inventory_system.equip_item(active_item, active_hand)
			play_sound_effect(SoundEffect.ERROR)
			return false
	
	return false

# Swaps items between two slots
func swap_items_between_slots(active_item: Node, current_item: Node, slot_id: int, active_hand: int) -> bool:
	if inventory_system.can_equip_to_slot(current_item, active_hand):
		inventory_system.unequip_item(active_hand)
		inventory_system.unequip_item(slot_id)
		
		var equip1_success = inventory_system.equip_item(active_item, slot_id)
		var equip2_success = inventory_system.equip_item(current_item, active_hand)
		
		if equip1_success and equip2_success:
			play_sound_effect(SoundEffect.EQUIP)
			return true
		else:
			restore_original_positions(active_item, current_item, slot_id, active_hand, equip1_success, equip2_success)
			play_sound_effect(SoundEffect.ERROR)
			return false
	else:
		play_sound_effect(SoundEffect.ERROR)
		return false

# Restores original item positions after failed swap
func restore_original_positions(active_item: Node, current_item: Node, slot_id: int, active_hand: int, equip1_success: bool, equip2_success: bool):
	if not equip1_success:
		inventory_system.equip_item(active_item, active_hand)
	if not equip2_success:
		inventory_system.equip_item(current_item, slot_id)

# Utility methods
func can_perform_ui_action() -> bool:
	return entity and entity.is_multiplayer_authority() and inventory_system

# Returns sprite node for slot
func get_slot_sprite(slot_name: String) -> Node:
	if slot_name in slot_item_sprites:
		return slot_item_sprites[slot_name]
	
	if slot_name == "EarsSlot":
		var ear1_slot = get_node_or_null("Control/EquipmentItems/EquipmentButton/EquipmentSlots/GridContainer/Ear1Slot")
		if ear1_slot:
			return ear1_slot.get_node_or_null("Ear1ItemSprite")
	
	return null

# Returns container node for slot
func get_slot_container(slot_name: String) -> Control:
	match slot_name:
		"LeftHandSlot":
			return $Control/HandSlots/LeftHand
		"RightHandSlot":
			return $Control/HandSlots/RightHand
		"HeadSlot", "EyesSlot", "MaskSlot", "UniformSlot", "ArmorSlot", "GlovesSlot", "ShoesSlot", "SuitSlot":
			var container = get_node_or_null("Control/EquipmentItems/EquipmentButton/EquipmentSlots/GridContainer/" + slot_name)
			if not container:
				container = get_node_or_null("Control/EquipmentItems/EquipmentButton/EquipmentSlots/" + slot_name)
			return container
		"BackSlot", "BeltSlot", "IDSlot":
			return get_node_or_null("Control/MainSlots/" + slot_name)
		"Pouch1", "Pouch2":
			return get_node_or_null("Control/PouchSlots/" + slot_name)
	
	return null

# Returns intent button node
func get_intent_button(intent: int) -> Node:
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

# Sets current intent
func set_intent(intent: int):
	if current_intent != intent:
		current_intent = intent
		update_intent_buttons()
		apply_current_intent()

# Applies intent to player controller
func apply_current_intent():
	if entity and entity.has_node("GridMovementController"):
		var grid_controller = entity.get_node("GridMovementController")
		if "intent" in grid_controller:
			grid_controller.intent = current_intent

# Applies movement mode to player controller
func apply_movement_mode():
	if entity and entity.has_node("GridMovementController"):
		var grid_controller = entity.get_node("GridMovementController")
		if "is_sprinting" in grid_controller:
			grid_controller.is_sprinting = is_movement_sprint

# Validates equipment interaction
func validate_equipment_interaction(slot_name: String) -> bool:
	var equipment_slots = ["HeadSlot", "EyesSlot", "MaskSlot", "UniformSlot", "ArmorSlot", "GlovesSlot", "ShoesSlot", "SuitSlot"]
	
	if slot_name in equipment_slots:
		var equipment_menu = $Control/EquipmentItems/EquipmentButton/EquipmentSlots
		
		if not equipment_menu or not equipment_menu.visible:
			return false
		
		if equipment_menu.modulate.a < 0.5:
			return false
	
	if not slot_mapping.has(slot_name):
		return false
	
	if not inventory_system:
		return false
	
	return true

# Checks if position is within UI area
func is_position_in_ui(position: Vector2) -> bool:
	return $Control.get_global_rect().has_point(position)

# Checks if position is within UI element
func is_position_in_ui_element(position: Vector2) -> bool:
	return is_position_in_ui(position)

# Creates placeholder texture for items without icons
func create_placeholder_texture(color: Color = Color(0.8, 0.2, 0.2)) -> Texture2D:
	var image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(color)
	
	for x in range(32):
		for y in range(32):
			if x == 0 or y == 0 or x == 31 or y == 31:
				image.set_pixel(x, y, Color.BLACK)
	
	return ImageTexture.create_from_image(image)

# Plays sound effect for UI feedback
func play_sound_effect(effect_type: int):
	if effect_type in sound_effects and sound_effects[effect_type]:
		var audio_player = AudioStreamPlayer.new()
		audio_player.stream = sound_effects[effect_type]
		audio_player.volume_db = -10
		add_child(audio_player)
		audio_player.play()
		audio_player.finished.connect(func(): audio_player.queue_free())

# Shows notification message
func show_notification(text: String):
	print("Notification: " + text)

# Forces complete UI refresh
func force_ui_refresh():
	update_all_slots()
	update_active_hand()
	update_intent_buttons()
	update_movement_buttons()

# Utility functions for item type checking
func get_weapon_name(weapon: Node) -> String:
	if not weapon:
		return "weapon"
	
	if "item_name" in weapon and weapon.item_name != "":
		return weapon.item_name
	elif "obj_name" in weapon and weapon.obj_name != "":
		return weapon.obj_name
	elif "name" in weapon:
		return weapon.name
	
	return "weapon"

func is_weapon(item: Node) -> bool:
	if not item:
		return false
	
	# Check entity type
	if item.entity_type == "gun":
		return true
	
	return false

func is_magazine(item: Node) -> bool:
	if not item:
		return false
	
	# Check script path
	if item.get_script():
		var script_path = str(item.get_script().get_path())
		if "Magazine" in script_path:
			return true
	
	# Check for magazine-specific properties
	if "ammo_type" in item and "current_ammo" in item:
		return true
	
	# Check entity type
	if "entity_type" in item and item.entity_type == "magazine":
		return true
	
	return false

# Signal handlers for inventory events
func _on_inventory_updated():
	update_all_slots()

func _on_item_equipped(item: Node, slot: int):
	play_sound_effect(SoundEffect.EQUIP)
	update_all_slots()

func _on_item_unequipped(item: Node, slot: int):
	play_sound_effect(SoundEffect.UNEQUIP)
	update_all_slots()

func _on_active_hand_changed(new_active_hand: int):
	update_active_hand()

func _on_slot_mouse_entered(slot_name: String):
	var sprite = get_slot_sprite(slot_name)
	if sprite and sprite.visible:
		var tween = create_tween()
		tween.tween_property(sprite, "scale", Vector2(0.9, 0.9), 0.1)

func _on_slot_mouse_exited(slot_name: String):
	var sprite = get_slot_sprite(slot_name)
	if sprite and sprite.visible:
		var tween = create_tween()
		tween.tween_property(sprite, "scale", Vector2(0.8, 0.8), 0.1)

func _on_intent_toggled(pressed: bool, intent: int):
	if not can_perform_ui_action():
		return
	
	if pressed and intent != current_intent:
		current_intent = intent
		update_intent_buttons()
		apply_current_intent()
		play_sound_effect(SoundEffect.CLICK)

func _on_equipment_button_gui_input(event: InputEvent):
	if not can_perform_ui_action():
		return
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var equipment_button = $Control/EquipmentItems/EquipmentButton
		var equipment_menu = $Control/EquipmentItems/EquipmentButton/EquipmentSlots
		
		if equipment_button and equipment_menu:
			if equipment_menu.visible and equipment_menu.get_global_rect().has_point(event.global_position):
				get_viewport().set_input_as_handled()
				return

func _on_equipment_button_toggled(toggled_on: bool):
	if not can_perform_ui_action():
		return
	
	await get_tree().process_frame
	
	var equipment_menu = $Control/EquipmentItems/EquipmentButton/EquipmentSlots
	if equipment_menu:
		var tween = create_tween()
		if toggled_on:
			equipment_menu.visible = true
			equipment_menu.modulate.a = 0.0
			equipment_menu.mouse_filter = Control.MOUSE_FILTER_PASS
			tween.tween_property(equipment_menu, "modulate:a", 1.0, 0.2)
		else:
			tween.tween_property(equipment_menu, "modulate:a", 0.0, 0.2)
			tween.tween_callback(func(): 
				equipment_menu.visible = false
				equipment_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE)
	
	play_sound_effect(SoundEffect.CLICK)

func _on_run_button_pressed():
	if not can_perform_ui_action():
		return
	
	is_movement_sprint = true
	update_movement_buttons()
	apply_movement_mode()
	play_sound_effect(SoundEffect.CLICK)

func _on_walk_button_pressed():
	if not can_perform_ui_action():
		return
	
	is_movement_sprint = false
	update_movement_buttons()
	apply_movement_mode()
	play_sound_effect(SoundEffect.CLICK)
