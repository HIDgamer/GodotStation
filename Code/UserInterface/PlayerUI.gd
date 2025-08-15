extends CanvasLayer
class_name PlayerUI

signal item_alt_clicked(item: Node)
signal item_ctrl_clicked(item: Node)
signal item_shift_clicked(item: Node)
signal item_right_clicked(item: Node)
signal item_middle_clicked(item: Node)
signal item_double_clicked(item: Node)
signal storage_item_clicked(storage_item: Node, held_item: Node)
signal storage_item_retrieved(storage_item: Node, item: Node)

enum EquipSlot {
	NONE = 0,
	HEAD = 1,
	GLASSES = 2,
	BACK = 3,
	WEAR_MASK = 4,
	HANDCUFFED = 5,
	W_UNIFORM = 6,
	WEAR_SUIT = 7,
	EARS = 8,
	GLOVES = 9,
	SHOES = 10,
	WEAR_ID = 12,
	LEFT_HAND = 13,
	RIGHT_HAND = 14,
	BELT = 15,
	L_STORE = 16,
	R_STORE = 17,
	S_STORE = 18,
	ACCESSORY = 19
}

enum Intent {
	HELP = 0,
	DISARM = 1,
	GRAB = 2,
	HARM = 3
}

enum SoundEffect {
	CLICK,
	EQUIP,
	UNEQUIP,
	DROP,
	THROW,
	ERROR,
	STORAGE_OPEN,
	STORAGE_CLOSE
}

const DOUBLE_CLICK_TIME: float = 0.3
const DRAG_START_DISTANCE: int = 5
const DRAG_MINIMUM_DISTANCE: int = 20
const STORAGE_PANEL_BASE_SIZE: Vector2 = Vector2(100, 100)
const STORAGE_ITEM_SIZE: int = 32
const STORAGE_PANEL_PADDING: int = 8

var slot_mapping: Dictionary = {
	"LeftHandSlot": EquipSlot.LEFT_HAND,
	"RightHandSlot": EquipSlot.RIGHT_HAND,
	"HeadSlot": EquipSlot.HEAD,
	"EyesSlot": EquipSlot.GLASSES,
	"BackSlot": EquipSlot.BACK,
	"MaskSlot": EquipSlot.WEAR_MASK,
	"UniformSlot": EquipSlot.W_UNIFORM,
	"ArmorSlot": EquipSlot.WEAR_SUIT,
	"Ear1Slot": EquipSlot.EARS,
	"Ear2Slot": EquipSlot.EARS,
	"GlovesSlot": EquipSlot.GLOVES,
	"ShoesSlot": EquipSlot.SHOES,
	"IDSlot": EquipSlot.WEAR_ID,
	"BeltSlot": EquipSlot.BELT,
	"Pouch1": EquipSlot.L_STORE,
	"Pouch2": EquipSlot.R_STORE,
	"SuitSlot": EquipSlot.S_STORE
}

var equipment_slots: Array[String] = [
	"HeadSlot", "EyesSlot", "MaskSlot", "UniformSlot", 
	"ArmorSlot", "Ear1Slot", "Ear2Slot", "GlovesSlot", "ShoesSlot", "SuitSlot"
]

var hand_slots: Array[String] = [
	"LeftHandSlot", "RightHandSlot"
]

var main_slots: Array[String] = [
	"BackSlot", "BeltSlot", "IDSlot"
]

var pocket_slots: Array[String] = [
	"Pouch1", "Pouch2"
]

var entity: Node = null
var inventory_system: Node = null
var item_interaction_component: Node = null
var weapon_handling_component: Node = null
var health_system: Node = null

var slot_item_sprites: Dictionary = {}
var current_intent: int = Intent.HELP
var is_movement_sprint: bool = true
var is_throw_mode: bool = false

var drag_start_position: Vector2 = Vector2.ZERO
var is_dragging: bool = false
var dragging_item: Node = null
var dragging_from_slot: String = ""
var drag_preview: Node = null
var last_click_time: float = 0.0

var sound_effects: Dictionary = {}
var status_indicator: AnimatedSprite2D = null
var temperature_indicator: AnimatedSprite2D = null
var throw_mode_indicator: TextureRect = null
var drop_button: TextureButton = null

var storage_panels: Dictionary = {}
var open_storage_items: Array = []

func _ready():
	setup_ui_components()
	load_sound_effects()
	setup_storage_container()
	await get_tree().create_timer(0.1).timeout
	find_and_connect_player()

func setup_storage_container():
	var storage_container = Control.new()
	storage_container.name = "StorageContainer"
	storage_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	storage_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(storage_container)

func setup_ui_components():
	drag_preview = $Control/DragPreview
	if drag_preview:
		drag_preview.visible = false
	
	status_indicator = $Control/StatusIndicator
	temperature_indicator = $Control/TemperatureIndicator
	throw_mode_indicator = $Control/MovementButtons/ThrowModeIndicator
	drop_button = $Control/MovementButtons/DropButton
	
	if throw_mode_indicator:
		throw_mode_indicator.visible = false
	
	initialize_all_slots()
	connect_all_ui_elements()

func load_sound_effects():
	sound_effects = {
		SoundEffect.CLICK: preload("res://Sound/machines/Click_standard.wav") if ResourceLoader.exists("res://Sound/machines/Click_standard.wav") else null,
		SoundEffect.EQUIP: preload("res://Sound/handling/Uniform.wav") if ResourceLoader.exists("res://Sound/handling/Uniform.wav") else null,
		SoundEffect.UNEQUIP: preload("res://Sound/handling/Armor.wav") if ResourceLoader.exists("res://Sound/handling/Armor.wav") else null,
		SoundEffect.DROP: preload("res://Sound/handling/tape_drop.ogg") if ResourceLoader.exists("res://Sound/handling/tape_drop.ogg") else null,
		SoundEffect.THROW: preload("res://Sound/effects/throwing/throw.wav") if ResourceLoader.exists("res://Sound/effects/throwing/throw.wav") else null,
		SoundEffect.ERROR: preload("res://Sound/machines/terminal_error.ogg") if ResourceLoader.exists("res://Sound/machines/terminal_error.ogg") else null,
		SoundEffect.STORAGE_OPEN: preload("res://Sound/machines/Click_standard.wav") if ResourceLoader.exists("res://Sound/machines/Click_standard.wav") else null,
		SoundEffect.STORAGE_CLOSE: preload("res://Sound/machines/Click_standard.wav") if ResourceLoader.exists("res://Sound/machines/Click_standard.wav") else null
	}

func find_and_connect_player():
	var found_player = null
	
	var players = get_tree().get_nodes_in_group("player_controller")
	for player in players:
		if not player.get_meta("is_npc", false) and player.is_multiplayer_authority() and player.get_meta("is_player", false):
			found_player = player
			break
	
	if not found_player:
		var all_players = get_tree().get_nodes_in_group("players")
		for player in all_players:
			if not player.get_meta("is_npc", false) and player.is_multiplayer_authority() and player.get_meta("is_player", false):
				found_player = player
				break
	
	if found_player:
		connect_to_player(found_player)
	else:
		await get_tree().create_timer(0.5).timeout
		find_and_connect_player()

func connect_to_player(player: Node):
	if not validate_player_entity(player):
		visible = false
		return
	
	entity = player
	inventory_system = entity.get_node_or_null("InventorySystem")
	item_interaction_component = entity.get_node_or_null("ItemInteractionComponent")
	weapon_handling_component = entity.get_node_or_null("WeaponHandlingComponent")
	health_system = entity.get_node_or_null("HealthSystem")
	
	if inventory_system and inventory_system.get_meta("is_npc_inventory", false):
		visible = false
		return
	
	connect_component_signals()
	register_with_click_component()
	refresh_entire_ui()

func connect_component_signals():
	if inventory_system:
		connect_inventory_signals()
	if health_system:
		connect_health_signals()

func connect_inventory_signals():
	var signals_to_connect = [
		["inventory_updated", "_on_inventory_updated"],
		["item_equipped", "_on_item_equipped"],
		["item_unequipped", "_on_item_unequipped"],
		["active_hand_changed", "_on_active_hand_changed"],
		["storage_opened", "_on_storage_opened"],
		["storage_closed", "_on_storage_closed"]
	]
	
	for signal_data in signals_to_connect:
		var signal_name = signal_data[0]
		var method_name = signal_data[1]
		if inventory_system.has_signal(signal_name):
			if not inventory_system.is_connected(signal_name, Callable(self, method_name)):
				inventory_system.connect(signal_name, Callable(self, method_name))

func connect_health_signals():
	var signals_to_connect = [
		["health_changed", "_on_health_changed"],
		["temperature_changed", "_on_temperature_changed"]
	]
	
	for signal_data in signals_to_connect:
		var signal_name = signal_data[0]
		var method_name = signal_data[1]
		if health_system.has_signal(signal_name):
			if not health_system.is_connected(signal_name, Callable(self, method_name)):
				health_system.connect(signal_name, Callable(self, method_name))

func register_with_click_component():
	if entity and entity.has_method("register_player_ui"):
		entity.register_player_ui(self)

func initialize_all_slots():
	initialize_hand_slots()
	initialize_equipment_slots()
	initialize_main_slots()
	initialize_pocket_slots()

func initialize_hand_slots():
	for slot_name in hand_slots:
		create_slot_sprite(slot_name, get_slot_container(slot_name))

func initialize_equipment_slots():
	for slot_name in equipment_slots:
		create_slot_sprite(slot_name, get_slot_container(slot_name))

func initialize_main_slots():
	for slot_name in main_slots:
		create_slot_sprite(slot_name, get_slot_container(slot_name))

func initialize_pocket_slots():
	for slot_name in pocket_slots:
		create_slot_sprite(slot_name, get_slot_container(slot_name))

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

func connect_all_ui_elements():
	connect_slot_events()
	connect_intent_buttons()
	connect_movement_buttons()
	connect_equipment_button()

func connect_slot_events():
	connect_hand_slot_events()
	connect_equipment_slot_events()
	connect_main_slot_events()
	connect_pocket_slot_events()

func connect_hand_slot_events():
	for slot_name in hand_slots:
		var slot_container = get_slot_container(slot_name)
		if slot_container:
			connect_slot_container_events(slot_container, slot_name)

func connect_equipment_slot_events():
	for slot_name in equipment_slots:
		var slot_container = get_slot_container(slot_name)
		var slot_button = get_slot_button(slot_name)
		
		if slot_container:
			connect_slot_container_events(slot_container, slot_name)
		if slot_button:
			connect_slot_button_events(slot_button, slot_name)

func connect_main_slot_events():
	for slot_name in main_slots:
		var slot_container = get_slot_container(slot_name)
		var slot_button = get_slot_button(slot_name)
		
		if slot_container:
			connect_slot_container_events(slot_container, slot_name)
		if slot_button:
			connect_slot_button_events(slot_button, slot_name)

func connect_pocket_slot_events():
	for slot_name in pocket_slots:
		var slot_container = get_slot_container(slot_name)
		var slot_button = get_slot_button(slot_name)
		
		if slot_container:
			connect_slot_container_events(slot_container, slot_name)
		if slot_button:
			connect_slot_button_events(slot_button, slot_name)

func connect_slot_container_events(slot_container: Control, slot_name: String):
	slot_container.mouse_entered.connect(_on_slot_mouse_entered.bind(slot_name))
	slot_container.mouse_exited.connect(_on_slot_mouse_exited.bind(slot_name))
	slot_container.mouse_filter = Control.MOUSE_FILTER_PASS

func connect_slot_button_events(slot_button: Control, slot_name: String):
	if slot_button is BaseButton:
		slot_button.mouse_entered.connect(_on_slot_mouse_entered.bind(slot_name))
		slot_button.mouse_exited.connect(_on_slot_mouse_exited.bind(slot_name))
		slot_button.pressed.connect(_on_slot_button_clicked.bind(slot_name))
		slot_button.gui_input.connect(_on_slot_gui_input.bind(slot_name))
		slot_button.mouse_filter = Control.MOUSE_FILTER_PASS

func connect_intent_buttons():
	var intent_buttons = [
		[$Control/IntentSelector/HelpIntent, Intent.HELP],
		[$Control/IntentSelector/DisarmIntent, Intent.DISARM],
		[$Control/IntentSelector/GrabIntent, Intent.GRAB],
		[$Control/IntentSelector/HarmIntent, Intent.HARM]
	]
	
	for button_data in intent_buttons:
		var button = button_data[0]
		var intent = button_data[1]
		if button:
			button.pressed.connect(_on_intent_button_pressed.bind(intent))

func connect_movement_buttons():
	if $Control/MovementButtons/RunButton:
		$Control/MovementButtons/RunButton.pressed.connect(_on_run_button_pressed)
	if $Control/MovementButtons/WalkButton:
		$Control/MovementButtons/WalkButton.pressed.connect(_on_walk_button_pressed)
	if drop_button:
		drop_button.pressed.connect(_on_drop_button_pressed)

func connect_equipment_button():
	if $Control/EquipmentItems/EquipmentButton:
		$Control/EquipmentItems/EquipmentButton.gui_input.connect(_on_equipment_button_gui_input)
		$Control/EquipmentItems/EquipmentButton.toggled.connect(_on_equipment_button_toggled)

func _input(event: InputEvent):
	if not can_perform_ui_action():
		return
	
	if not validate_player_entity(entity):
		return
	
	if event is InputEventKey and event.pressed:
		handle_keyboard_input(event)
	elif event is InputEventMouseButton:
		handle_mouse_input(event)

func handle_keyboard_input(event: InputEventKey):
	if not inventory_system:
		return
	
	match event.keycode:
		KEY_Q:
			if event.shift_pressed or event.ctrl_pressed or event.alt_pressed:
				return
			if item_interaction_component:
				item_interaction_component.drop_active_item()
				play_sound_effect(SoundEffect.DROP)
		KEY_R:
			if event.ctrl_pressed:
				var wielded_weapon = inventory_system.get_wielded_weapon()
				if wielded_weapon and weapon_handling_component:
					weapon_handling_component.eject_magazine_to_floor(wielded_weapon)
					play_sound_effect(SoundEffect.CLICK)
		KEY_C:
			var wielded_weapon = inventory_system.get_wielded_weapon()
			if wielded_weapon and weapon_handling_component:
				weapon_handling_component.chamber_round(wielded_weapon)
				play_sound_effect(SoundEffect.CLICK)
		KEY_1, KEY_2, KEY_3, KEY_4:
			var intent = event.keycode - KEY_1
			set_intent(intent)

func handle_mouse_input(event: InputEventMouseButton):
	if not is_position_in_ui(event.position):
		return
	
	var equipment_button = $Control/EquipmentItems/EquipmentButton
	if equipment_button and equipment_button.get_global_rect().has_point(event.position):
		return
	
	if is_click_in_storage_panel(event.position):
		handle_storage_panel_input(event)
		get_viewport().set_input_as_handled()
		return
	
	var equipment_menu = $Control/EquipmentItems/EquipmentButton/EquipmentSlots
	
	if equipment_menu and equipment_menu.visible and equipment_menu.modulate.a > 0.5:
		if equipment_menu.get_global_rect().has_point(event.position):
			handle_equipment_menu_input(event)
			get_viewport().set_input_as_handled()
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
		MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				handle_middle_click(event.position)
	
	get_viewport().set_input_as_handled()

func handle_equipment_menu_input(event: InputEventMouseButton):
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
		MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				for slot_name in equipment_slots:
					var slot_container = get_slot_container(slot_name)
					if slot_container and slot_container.get_global_rect().has_point(event.position):
						handle_equipment_slot_middle_click(slot_name)
						return

func is_click_in_storage_panel(position: Vector2) -> bool:
	for storage_item in storage_panels:
		var panel = storage_panels[storage_item]
		if panel and panel.visible and panel.get_global_rect().has_point(position):
			return true
	return false

func handle_storage_panel_input(event: InputEventMouseButton):
	for storage_item in storage_panels:
		var panel = storage_panels[storage_item]
		if panel and panel.visible and panel.get_global_rect().has_point(event.position):
			handle_storage_panel_click(storage_item, panel, event)
			return

func handle_storage_panel_click(storage_item: Node, panel: Control, event: InputEventMouseButton):
	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var clicked_item = find_storage_item_at_position(storage_item, panel, event.position)
		var held_item = inventory_system.get_active_item()
		
		if clicked_item:
			if not held_item:
				var success = false
				
				if storage_item.has_method("remove_item_from_storage"):
					if storage_item.remove_item_from_storage(clicked_item, entity):
						if inventory_system.equip_item(clicked_item, inventory_system.active_hand):
							success = true
						else:
							storage_item.add_item_to_storage(clicked_item, entity)
				
				if not success:
					if inventory_system.interact_with_storage_item(storage_item, null):
						var storage_items = storage_item.storage_items if "storage_items" in storage_item else []
						var item_index = storage_items.find(clicked_item)
						if item_index >= 0:
							if storage_item.has_method("remove_item_from_storage"):
								storage_item.remove_item_from_storage(clicked_item, entity)
							else:
								storage_items.erase(clicked_item)
								storage_item.storage_current_size -= storage_item.get_item_storage_size(clicked_item) if storage_item.has_method("get_item_storage_size") else 1
								if clicked_item.get_parent() == storage_item:
									storage_item.remove_child(clicked_item)
							
							if inventory_system.equip_item(clicked_item, inventory_system.active_hand):
								success = true
							else:
								var world = entity.get_parent()
								if world:
									world.add_child(clicked_item)
									clicked_item.global_position = entity.global_position
									clicked_item.visible = true
									success = true
				
				if success:
					update_storage_panel(storage_item)
					play_sound_effect(SoundEffect.CLICK)
					emit_signal("storage_item_retrieved", storage_item, clicked_item)
				else:
					play_sound_effect(SoundEffect.ERROR)
			else:
				if inventory_system.interact_with_storage_item(storage_item, held_item):
					update_storage_panel(storage_item)
					play_sound_effect(SoundEffect.CLICK)
				else:
					play_sound_effect(SoundEffect.ERROR)
		else:
			if held_item:
				if inventory_system.interact_with_storage_item(storage_item, held_item):
					update_storage_panel(storage_item)
					play_sound_effect(SoundEffect.CLICK)
				else:
					play_sound_effect(SoundEffect.ERROR)
	
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var clicked_item = find_storage_item_at_position(storage_item, panel, event.position)
		if clicked_item:
			emit_signal("item_right_clicked", clicked_item)
			play_sound_effect(SoundEffect.CLICK)
	
	elif event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
		var clicked_item = find_storage_item_at_position(storage_item, panel, event.position)
		if clicked_item:
			emit_signal("item_middle_clicked", clicked_item)
			play_sound_effect(SoundEffect.CLICK)

func find_storage_item_at_position(storage_item: Node, panel: Control, global_pos: Vector2) -> Node:
	var storage_items = storage_item.storage_items if "storage_items" in storage_item else []
	var content_area = panel.get_node_or_null("ContentArea")
	
	if not content_area:
		return null
	
	for item in storage_items:
		var item_control = content_area.get_node_or_null("StorageItem_" + str(item.get_instance_id()))
		if item_control and item_control.get_global_rect().has_point(global_pos):
			return item
	
	return null

func create_storage_panel(storage_item: Node):
	if storage_item in storage_panels:
		return storage_panels[storage_item]
	
	var panel = Panel.new()
	panel.name = "StoragePanel_" + str(storage_item.get_instance_id())
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.2, 0.2, 0.2, 0.9)
	style_box.border_width_left = 2
	style_box.border_width_top = 2
	style_box.border_width_right = 2
	style_box.border_width_bottom = 2
	style_box.border_color = Color(0.4, 0.4, 0.4, 1.0)
	style_box.corner_radius_top_left = 4
	style_box.corner_radius_top_right = 4
	style_box.corner_radius_bottom_left = 4
	style_box.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style_box)
	
	var header = Label.new()
	header.name = "Header"
	header.text = storage_item.obj_name if "obj_name" in storage_item else "Storage"
	header.add_theme_color_override("font_color", Color.WHITE)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(header)
	
	var close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(20, 20)
	close_button.pressed.connect(_on_storage_close_button_pressed.bind(storage_item))
	panel.add_child(close_button)
	
	var content_area = Control.new()
	content_area.name = "ContentArea"
	content_area.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(content_area)
	
	var storage_container = get_node("StorageContainer")
	storage_container.add_child(panel)
	
	storage_panels[storage_item] = panel
	
	update_storage_panel(storage_item)
	position_storage_panel(storage_item)
	
	return panel

func update_storage_panel(storage_item: Node):
	var panel = storage_panels.get(storage_item)
	if not panel:
		return
	
	var content_area = panel.get_node("ContentArea")
	var header = panel.get_node("Header")
	var close_button = panel.get_node("CloseButton")
	
	for child in content_area.get_children():
		child.queue_free()
	
	var storage_items = storage_item.storage_items if "storage_items" in storage_item else []
	var storage_type = storage_item.storage_type if "storage_type" in storage_item else 0
	
	var panel_size = calculate_storage_panel_size(storage_item)
	panel.custom_minimum_size = panel_size
	panel.size = panel_size
	
	header.position = Vector2(STORAGE_PANEL_PADDING, STORAGE_PANEL_PADDING)
	header.size = Vector2(panel_size.x - 2 * STORAGE_PANEL_PADDING - 25, 20)
	
	close_button.position = Vector2(panel_size.x - 25, STORAGE_PANEL_PADDING)
	
	content_area.position = Vector2(STORAGE_PANEL_PADDING, 30)
	content_area.size = Vector2(panel_size.x - 2 * STORAGE_PANEL_PADDING, panel_size.y - 40)
	
	if storage_type == 1:
		create_size_based_storage_display(storage_item, content_area)
	elif storage_type == 2:
		create_slot_based_storage_display(storage_item, content_area)

func calculate_storage_panel_size(storage_item: Node) -> Vector2:
	var storage_type = storage_item.storage_type if "storage_type" in storage_item else 0
	var storage_items = storage_item.storage_items if "storage_items" in storage_item else []
	
	if storage_type == 1:
		var max_size = storage_item.storage_max_size if "storage_max_size" in storage_item else 20
		var cols = max(1, int(sqrt(max_size)))
		var rows = max(1, int(ceil(float(max_size) / cols)))
		
		var width = cols * (STORAGE_ITEM_SIZE + 4) + 2 * STORAGE_PANEL_PADDING
		var height = rows * (STORAGE_ITEM_SIZE + 4) + 2 * STORAGE_PANEL_PADDING + 30
		
		return Vector2(max(width, STORAGE_PANEL_BASE_SIZE.x), max(height, STORAGE_PANEL_BASE_SIZE.y))
	
	elif storage_type == 2:
		var slots = storage_item.storage_slots if "storage_slots" in storage_item else 4
		var cols = max(1, min(slots, 4))
		var rows = max(1, int(ceil(float(slots) / cols)))
		
		var width = cols * (STORAGE_ITEM_SIZE + 4) + 2 * STORAGE_PANEL_PADDING
		var height = rows * (STORAGE_ITEM_SIZE + 4) + 2 * STORAGE_PANEL_PADDING + 30
		
		return Vector2(max(width, STORAGE_PANEL_BASE_SIZE.x), max(height, STORAGE_PANEL_BASE_SIZE.y))
	
	return STORAGE_PANEL_BASE_SIZE

func create_size_based_storage_display(storage_item: Node, content_area: Control):
	var storage_items = storage_item.storage_items if "storage_items" in storage_item else []
	var current_x = 0
	var current_y = 0
	var row_height = 0
	var content_width = content_area.size.x
	
	for item in storage_items:
		var w_class = item.w_class if "w_class" in item else 1
		var multiplier = storage_item.storage_w_class_multiplier if "storage_w_class_multiplier" in storage_item else 1.0
		var item_size = max(1, int(w_class * multiplier))
		
		var item_width = STORAGE_ITEM_SIZE * item_size
		var item_height = STORAGE_ITEM_SIZE
		
		if current_x + item_width > content_width and current_x > 0:
			current_x = 0
			current_y += row_height + 4
			row_height = 0
		
		var item_container = create_storage_item_display(item, Vector2(item_width, item_height))
		item_container.position = Vector2(current_x, current_y)
		content_area.add_child(item_container)
		
		current_x += item_width + 4
		row_height = max(row_height, item_height)

func create_slot_based_storage_display(storage_item: Node, content_area: Control):
	var storage_items = storage_item.storage_items if "storage_items" in storage_item else []
	var storage_slots = storage_item.storage_slots if "storage_slots" in storage_item else 4
	var cols = max(1, min(storage_slots, 4))
	var rows = max(1, int(ceil(float(storage_slots) / cols)))
	
	var slot_width = STORAGE_ITEM_SIZE
	var slot_height = STORAGE_ITEM_SIZE
	
	for i in range(storage_slots):
		var col = i % cols
		var row = i / cols
		
		var x = col * (slot_width + 4)
		var y = row * (slot_height + 4)
		
		var slot_bg = Panel.new()
		slot_bg.position = Vector2(x, y)
		slot_bg.size = Vector2(slot_width, slot_height)
		
		var slot_style = StyleBoxFlat.new()
		slot_style.bg_color = Color(0.1, 0.1, 0.1, 0.5)
		slot_style.border_width_left = 1
		slot_style.border_width_top = 1
		slot_style.border_width_right = 1
		slot_style.border_width_bottom = 1
		slot_style.border_color = Color(0.3, 0.3, 0.3, 1.0)
		slot_bg.add_theme_stylebox_override("panel", slot_style)
		
		content_area.add_child(slot_bg)
		
		if i < storage_items.size():
			var item = storage_items[i]
			var item_container = create_storage_item_display(item, Vector2(slot_width, slot_height))
			item_container.position = Vector2(x, y)
			content_area.add_child(item_container)

func create_storage_item_display(item: Node, size: Vector2) -> Control:
	var container = Control.new()
	container.name = "StorageItem_" + str(item.get_instance_id())
	container.size = size
	container.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var icon_node = item.get_node_or_null("Icon")
	if icon_node:
		var sprite = create_sprite_for_storage_item(icon_node)
		sprite.position = size / 2
		sprite.scale = Vector2(0.9, 0.9)
		container.add_child(sprite)
	else:
		var placeholder = ColorRect.new()
		placeholder.color = Color(0.5, 0.5, 0.5, 0.8)
		placeholder.size = size
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(placeholder)
	
	var panel = Panel.new()
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.3, 0.6, 1.0, 0.3)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.5, 0.8, 1.0, 0.8)
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.size = size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(panel)
	
	container.mouse_entered.connect(_on_storage_item_hover.bind(container, true))
	container.mouse_exited.connect(_on_storage_item_hover.bind(container, false))
	
	return container

func _on_storage_item_hover(container: Control, is_hovering: bool):
	if is_hovering:
		container.modulate = Color(1.2, 1.2, 1.2, 1.0)
	else:
		container.modulate = Color(1.0, 1.0, 1.0, 1.0)

func create_sprite_for_storage_item(icon_node: Node) -> Node:
	if icon_node is AnimatedSprite2D:
		var sprite = AnimatedSprite2D.new()
		var original = icon_node as AnimatedSprite2D
		sprite.sprite_frames = original.sprite_frames
		sprite.animation = original.animation
		sprite.frame = original.frame
		if original.is_playing():
			sprite.play()
		return sprite
	elif icon_node is Sprite2D:
		var sprite = Sprite2D.new()
		var original = icon_node as Sprite2D
		sprite.texture = original.texture
		sprite.frame = original.frame
		sprite.hframes = original.hframes
		sprite.vframes = original.vframes
		return sprite
	else:
		var sprite = Sprite2D.new()
		sprite.texture = extract_texture_from_icon(icon_node)
		return sprite

func position_storage_panel(storage_item: Node):
	var panel = storage_panels.get(storage_item)
	if not panel:
		return
	
	var storage_container = get_node("StorageContainer")
	storage_container.move_child(panel, -1)
	
	var control_container = $Control
	var panel_size = panel.size
	
	var hotbar_global_pos = control_container.global_position
	var hotbar_size = control_container.size
	
	var x = hotbar_global_pos.x + (hotbar_size.x - panel_size.x) / 2
	var y = hotbar_global_pos.y - panel_size.y - 10
	
	if x < 0:
		x = 10
	elif x + panel_size.x > get_viewport().size.x:
		x = get_viewport().size.x - panel_size.x - 10
	
	if y < 0:
		y = 10
	
	panel.position = Vector2(x, y)

func show_storage_panel(storage_item: Node):
	if storage_item in storage_panels:
		var panel = storage_panels[storage_item]
		panel.visible = true
		update_storage_panel(storage_item)
	else:
		create_storage_panel(storage_item)
	
	if storage_item not in open_storage_items:
		open_storage_items.append(storage_item)
	
	play_sound_effect(SoundEffect.STORAGE_OPEN)

func hide_storage_panel(storage_item: Node):
	if storage_item in storage_panels:
		var panel = storage_panels[storage_item]
		panel.visible = false
	
	if storage_item in open_storage_items:
		open_storage_items.erase(storage_item)
	
	play_sound_effect(SoundEffect.STORAGE_CLOSE)

func _on_storage_close_button_pressed(storage_item: Node):
	if storage_item.has_method("close_storage"):
		storage_item.close_storage(entity)

func _on_storage_opened(storage_item: Node):
	show_storage_panel(storage_item)

func _on_storage_closed(storage_item: Node):
	hide_storage_panel(storage_item)

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

func handle_left_release(position: Vector2):
	if is_dragging:
		handle_drag_release(position)
	
	is_dragging = false
	dragging_item = null
	dragging_from_slot = ""

func handle_right_click(position: Vector2):
	if not inventory_system:
		return
	
	for slot_name in slot_mapping:
		var slot_container = get_slot_container(slot_name)
		if slot_container and slot_container.get_global_rect().has_point(position):
			var slot_id = slot_mapping[slot_name]
			
			var item = null
			if slot_name in ["Ear1Slot", "Ear2Slot"]:
				item = inventory_system.get_item_in_slot(EquipSlot.EARS)
			else:
				item = inventory_system.get_item_in_slot(slot_id)
			
			if item:
				emit_signal("item_right_clicked", item)
				play_sound_effect(SoundEffect.CLICK)
			return

func handle_middle_click(position: Vector2):
	if not inventory_system:
		return
	
	for slot_name in slot_mapping:
		var slot_container = get_slot_container(slot_name)
		if slot_container and slot_container.get_global_rect().has_point(position):
			var slot_id = slot_mapping[slot_name]
			
			var item = null
			if slot_name in ["Ear1Slot", "Ear2Slot"]:
				item = inventory_system.get_item_in_slot(EquipSlot.EARS)
			else:
				item = inventory_system.get_item_in_slot(slot_id)
			
			if item and is_storage_item(item):
				var held_item = inventory_system.get_active_item()
				inventory_system.interact_with_storage_item(item, held_item)
				emit_signal("storage_item_clicked", item, held_item)
			return
	
	var held_item = inventory_system.get_active_item()
	if held_item and is_storage_item(held_item):
		inventory_system.interact_with_storage_item(held_item, null)
		emit_signal("storage_item_clicked", held_item, null)

func handle_slot_click(slot_name: String, is_double_click: bool, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	if not validate_slot_interaction(slot_name):
		return
	
	var slot_id = slot_mapping[slot_name]
	
	var item = null
	if slot_name in ["Ear1Slot", "Ear2Slot"]:
		item = inventory_system.get_item_in_slot(EquipSlot.EARS)
	else:
		item = inventory_system.get_item_in_slot(slot_id)
	
	add_slot_click_highlight(slot_name)
	
	if item:
		var actual_slot_id = EquipSlot.EARS if slot_name in ["Ear1Slot", "Ear2Slot"] else slot_id
		
		if is_storage_item(item):
			handle_storage_item_click(item, slot_name, actual_slot_id, is_double_click, shift_pressed, ctrl_pressed, alt_pressed)
		else:
			handle_item_click(item, slot_name, actual_slot_id, is_double_click, shift_pressed, ctrl_pressed, alt_pressed)
	else:
		var actual_slot_id = EquipSlot.EARS if slot_name in ["Ear1Slot", "Ear2Slot"] else slot_id
		handle_empty_slot_click(slot_name, actual_slot_id)

func handle_storage_item_click(storage_item: Node, slot_name: String, slot_id: int, is_double_click: bool, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	var held_item = inventory_system.get_active_item()
	
	if held_item:
		if inventory_system.interact_with_storage_item(storage_item, held_item):
			emit_signal("storage_item_clicked", storage_item, held_item)
			play_sound_effect(SoundEffect.CLICK)
		else:
			play_sound_effect(SoundEffect.ERROR)
	else:
		if inventory_system.interact_with_storage_item(storage_item, null):
			emit_signal("storage_item_clicked", storage_item, null)
			play_sound_effect(SoundEffect.CLICK)
		else:
			if storage_item.has_method("toggle_storage"):
				storage_item.toggle_storage(entity)
				play_sound_effect(SoundEffect.CLICK)
			else:
				play_sound_effect(SoundEffect.ERROR)

func handle_item_click(item: Node, slot_name: String, slot_id: int, is_double_click: bool, shift_pressed: bool, ctrl_pressed: bool, alt_pressed: bool):
	if is_weapon(item):
		if handle_weapon_interaction(item, slot_name, alt_pressed, ctrl_pressed, shift_pressed):
			return
	
	if is_throw_mode:
		throw_item_from_slot(slot_id)
		return
	
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

func handle_empty_slot_click(slot_name: String, slot_id: int):
	if inventory_system.is_wielding_weapon():
		if slot_name in hand_slots:
			show_notification("You can't switch hands while wielding a weapon!")
			play_sound_effect(SoundEffect.ERROR)
			return
	
	if slot_name == "LeftHandSlot" and inventory_system.active_hand != EquipSlot.LEFT_HAND:
		inventory_system.active_hand = EquipSlot.LEFT_HAND
		update_active_hand()
		flash_hand_selection(get_slot_container("LeftHandSlot"))
		play_sound_effect(SoundEffect.CLICK)
	elif slot_name == "RightHandSlot" and inventory_system.active_hand != EquipSlot.RIGHT_HAND:
		inventory_system.active_hand = EquipSlot.RIGHT_HAND
		update_active_hand()
		flash_hand_selection(get_slot_container("RightHandSlot"))
		play_sound_effect(SoundEffect.CLICK)
	else:
		if slot_name in equipment_slots or slot_name in main_slots or slot_name in pocket_slots:
			try_equip_to_slot(slot_name)

func _on_slot_button_clicked(slot_name: String):
	get_viewport().set_input_as_handled()

func _on_slot_gui_input(event: InputEvent, slot_name: String):
	if not can_perform_ui_action():
		return
	
	if event is InputEventMouseButton and event.pressed:
		get_viewport().set_input_as_handled()
		
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				handle_equipment_slot_click(slot_name, event)
			MOUSE_BUTTON_RIGHT:
				handle_equipment_slot_right_click(slot_name)
			MOUSE_BUTTON_MIDDLE:
				handle_equipment_slot_middle_click(slot_name)

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
	
	var item = null
	if slot_name in ["Ear1Slot", "Ear2Slot"]:
		item = inventory_system.get_item_in_slot(EquipSlot.EARS)
	else:
		item = inventory_system.get_item_in_slot(slot_id)
	
	if item:
		emit_signal("item_right_clicked", item)
		play_sound_effect(SoundEffect.CLICK)

func handle_equipment_slot_middle_click(slot_name: String):
	if not inventory_system:
		return
	
	var slot_id = slot_mapping[slot_name]
	
	var item = null
	if slot_name in ["Ear1Slot", "Ear2Slot"]:
		item = inventory_system.get_item_in_slot(EquipSlot.EARS)
	else:
		item = inventory_system.get_item_in_slot(slot_id)
	
	if item and is_storage_item(item):
		var held_item = inventory_system.get_active_item()
		inventory_system.interact_with_storage_item(item, held_item)
		emit_signal("storage_item_clicked", item, held_item)

func handle_weapon_interaction(weapon: Node, slot_name: String, alt_pressed: bool, ctrl_pressed: bool, shift_pressed: bool) -> bool:
	if not weapon_handling_component:
		return false
	
	if alt_pressed and not shift_pressed and not ctrl_pressed:
		weapon_handling_component.handle_weapon_alt_click(weapon)
		return true
	
	if ctrl_pressed and not shift_pressed and not alt_pressed:
		weapon_handling_component.handle_weapon_ctrl_click(weapon)
		return true
	
	if slot_name in hand_slots and not shift_pressed and not ctrl_pressed and not alt_pressed:
		return handle_hand_slot_weapon_interaction(slot_name, weapon)
	
	return false

func handle_hand_slot_weapon_interaction(slot_name: String, weapon: Node) -> bool:
	if not weapon_handling_component:
		return false
	
	var other_slot_name = "RightHandSlot" if slot_name == "LeftHandSlot" else "LeftHandSlot"
	var other_slot_id = slot_mapping.get(other_slot_name, -1)
	var other_item = inventory_system.get_item_in_slot(other_slot_id) if other_slot_id != -1 else null
	
	if other_item and is_magazine(other_item):
		weapon_handling_component.handle_weapon_click_with_magazine(weapon, other_item)
		return true
	
	if not other_item:
		weapon_handling_component.handle_weapon_click_with_empty_hand(weapon)
		return true
	
	return false

func handle_shift_item_click(item: Node, slot_id: int):
	var slot_name = get_slot_name_by_id(slot_id)
	
	if slot_name in equipment_slots:
		move_equipment_to_hand(item, slot_id)

func move_equipment_to_hand(item: Node, slot_id: int):
	var active_hand = inventory_system.active_hand
	var active_item = inventory_system.get_active_item()
	
	if not active_item:
		var unequip_result = inventory_system.unequip_item(slot_id)
		if unequip_result == inventory_system.ITEM_UNEQUIP_UNEQUIPPED:
			if inventory_system.equip_item(item, active_hand):
				play_sound_effect(SoundEffect.EQUIP)
			else:
				inventory_system.equip_item(item, slot_id)
				play_sound_effect(SoundEffect.ERROR)
	else:
		play_sound_effect(SoundEffect.ERROR)

func start_drag(slot_name: String, item: Node):
	dragging_item = item
	dragging_from_slot = slot_name
	
	setup_drag_preview(item)
	play_sound_effect(SoundEffect.CLICK)

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

func handle_drag_release(position: Vector2):
	if not dragging_item or not inventory_system:
		return
	
	for storage_item in storage_panels:
		var panel = storage_panels[storage_item]
		if panel and panel.visible and panel.get_global_rect().has_point(position):
			if inventory_system.interact_with_storage_item(storage_item, dragging_item):
				update_storage_panel(storage_item)
				play_sound_effect(SoundEffect.CLICK)
				return
			else:
				play_sound_effect(SoundEffect.ERROR)
				return
	
	var target_slot = find_target_slot(position)
	
	if target_slot and target_slot != dragging_from_slot:
		move_item_between_slots(dragging_from_slot, target_slot)
	else:
		var drag_distance = drag_start_position.distance_to(position)
		if drag_distance > DRAG_MINIMUM_DISTANCE:
			throw_item_to_mouse_position(dragging_from_slot, position)
		else:
			cancel_drag()

func find_target_slot(position: Vector2) -> String:
	var equipment_menu = $Control/EquipmentItems/EquipmentButton/EquipmentSlots
	if equipment_menu and equipment_menu.visible and equipment_menu.modulate.a > 0.5:
		if equipment_menu.get_global_rect().has_point(position):
			for slot_name in equipment_slots:
				var slot_container = get_slot_container(slot_name)
				if slot_container and slot_container.get_global_rect().has_point(position):
					return slot_name
	
	for slot_name in slot_mapping:
		if slot_name in equipment_slots:
			continue
		
		var slot_container = get_slot_container(slot_name)
		if slot_container and slot_container.get_global_rect().has_point(position):
			return slot_name
	
	return ""

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
	
	if not inventory_system._can_equip_to_slot(item, to_id):
		play_sound_effect(SoundEffect.ERROR)
		return
	
	var unequip_result = inventory_system.unequip_item(from_id)
	if unequip_result != inventory_system.ITEM_UNEQUIP_UNEQUIPPED:
		play_sound_effect(SoundEffect.ERROR)
		return
	
	if inventory_system.equip_item(item, to_id):
		play_sound_effect(SoundEffect.EQUIP)
	else:
		inventory_system.equip_item(item, from_id)
		play_sound_effect(SoundEffect.ERROR)

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

func throw_item_from_slot(slot_id: int):
	if not inventory_system or not entity:
		return
	
	var world_mouse_pos = entity.get_global_mouse_position()
	
	if inventory_system.throw_item_to_position(slot_id, world_mouse_pos):
		play_sound_effect(SoundEffect.THROW)
	else:
		play_sound_effect(SoundEffect.ERROR)

func cancel_drag():
	play_sound_effect(SoundEffect.CLICK)

func _process(delta: float):
	if dragging_item and drag_preview and drag_preview.visible:
		drag_preview.global_position = get_viewport().get_mouse_position() - Vector2(16, 16)
		
		if not is_dragging and drag_start_position.distance_to(get_viewport().get_mouse_position()) > DRAG_START_DISTANCE:
			is_dragging = true

func use_item_in_slot(slot_id: int):
	if not inventory_system:
		return
	
	var old_active = inventory_system.active_hand
	inventory_system.active_hand = slot_id
	await inventory_system.use_active_item()
	inventory_system.active_hand = old_active
	
	play_sound_effect(SoundEffect.CLICK)

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

func try_equip_to_slot(slot_name: String) -> bool:
	if not can_perform_ui_action():
		return false
	
	var slot_id = slot_mapping.get(slot_name, -1)
	if slot_id == -1:
		return false
	
	var active_item = inventory_system.get_active_item()
	var current_item = inventory_system.get_item_in_slot(slot_id)
	
	if not active_item:
		return false
	
	if not inventory_system._can_equip_to_slot(active_item, slot_id):
		play_sound_effect(SoundEffect.ERROR)
		return false
	
	var active_hand = inventory_system.active_hand
	
	if not current_item:
		return equip_to_empty_slot(active_item, slot_id, active_hand)
	else:
		return swap_items_between_slots(active_item, current_item, slot_id, active_hand)

func equip_to_empty_slot(active_item: Node, slot_id: int, active_hand: int) -> bool:
	var unequip_result = inventory_system.unequip_item(active_hand)
	if unequip_result == inventory_system.ITEM_UNEQUIP_UNEQUIPPED:
		if inventory_system.equip_item(active_item, slot_id):
			play_sound_effect(SoundEffect.EQUIP)
			return true
		else:
			inventory_system.equip_item(active_item, active_hand)
			play_sound_effect(SoundEffect.ERROR)
			return false
	
	return false

func swap_items_between_slots(active_item: Node, current_item: Node, slot_id: int, active_hand: int) -> bool:
	if inventory_system._can_equip_to_slot(current_item, active_hand):
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

func restore_original_positions(active_item: Node, current_item: Node, slot_id: int, active_hand: int, equip1_success: bool, equip2_success: bool):
	if not equip1_success:
		inventory_system.equip_item(active_item, active_hand)
	if not equip2_success:
		inventory_system.equip_item(current_item, slot_id)

func refresh_entire_ui():
	update_all_slots()
	update_active_hand()
	update_intent_buttons()
	update_movement_buttons()
	update_status_indicators()

func update_all_slots():
	if not inventory_system:
		return
	
	for slot_name in slot_mapping:
		update_slot(slot_name)

func update_slot(slot_name: String):
	if not inventory_system:
		return
	
	var slot_id = slot_mapping.get(slot_name, -1)
	if slot_id == -1:
		return
	
	if slot_name in ["Ear1Slot", "Ear2Slot"]:
		var ears_item = inventory_system.get_item_in_slot(EquipSlot.EARS)
		
		if slot_name == "Ear1Slot":
			display_item_in_slot(slot_name, ears_item)
		else:
			display_item_in_slot(slot_name, null)
		return
	
	var item = inventory_system.get_item_in_slot(slot_id)
	display_item_in_slot(slot_name, item)

func display_item_in_slot(slot_name: String, item: Node):
	var sprite = get_slot_sprite(slot_name)
	
	if slot_name in ["Ear1Slot", "Ear2Slot"]:
		if item:
			if slot_name == "Ear1Slot":
				var ear2_sprite = get_slot_sprite("Ear2Slot")
				if ear2_sprite:
					ear2_sprite.visible = false
			elif slot_name == "Ear2Slot":
				var ear1_sprite = get_slot_sprite("Ear1Slot")
				if ear1_sprite:
					ear1_sprite.visible = false
		else:
			var ear1_sprite = get_slot_sprite("Ear1Slot")
			var ear2_sprite = get_slot_sprite("Ear2Slot")
			if ear1_sprite:
				ear1_sprite.visible = false
			if ear2_sprite:
				ear2_sprite.visible = false
			return
	
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

func ensure_correct_sprite_type(slot_name: String, icon_node: Node) -> Node:
	var current_sprite = get_slot_sprite(slot_name)
	var needs_animated = icon_node is AnimatedSprite2D
	
	if (needs_animated and not (current_sprite is AnimatedSprite2D)) or (not needs_animated and (current_sprite is AnimatedSprite2D)):
		replace_slot_sprite(slot_name, needs_animated)
		current_sprite = get_slot_sprite(slot_name)
	
	return current_sprite

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

func update_active_hand():
	if not inventory_system:
		return
	
	var active_hand = inventory_system.active_hand
	var left_indicator = $Control/HandSlots/LeftHand/ActiveLeftIndicator
	var right_indicator = $Control/HandSlots/RightHand/ActiveRightIndicator
	var left_hand = $Control/HandSlots/LeftHand
	var right_hand = $Control/HandSlots/RightHand
	
	reset_hand_indicators(left_indicator, right_indicator, left_hand, right_hand)
	
	if active_hand == EquipSlot.LEFT_HAND and left_indicator and left_hand:
		activate_left_hand_indicator(left_indicator, left_hand)
	elif active_hand == EquipSlot.RIGHT_HAND and right_indicator and right_hand:
		activate_right_hand_indicator(right_indicator, right_hand)

func reset_hand_indicators(left_indicator: Node, right_indicator: Node, left_hand: Node, right_hand: Node):
	if left_indicator:
		left_indicator.visible = false
	if right_indicator:
		right_indicator.visible = false
	
	if left_hand:
		left_hand.modulate = Color(0.8, 0.8, 0.8, 1.0)
	if right_hand:
		right_hand.modulate = Color(0.8, 0.8, 0.8, 1.0)

func activate_left_hand_indicator(left_indicator: Node, left_hand: Node):
	left_indicator.visible = true
	left_indicator.modulate = Color(0.4, 0.8, 1.0, 0.8)
	left_hand.modulate = Color(1.2, 1.2, 1.2, 1.0)

func activate_right_hand_indicator(right_indicator: Node, right_hand: Node):
	right_indicator.visible = true
	right_indicator.modulate = Color(0.4, 0.8, 1.0, 0.8)
	right_hand.modulate = Color(1.2, 1.2, 1.2, 1.0)

func update_intent_buttons():
	var buttons = [
		$Control/IntentSelector/HelpIntent,
		$Control/IntentSelector/DisarmIntent,
		$Control/IntentSelector/GrabIntent,
		$Control/IntentSelector/HarmIntent
	]
	
	for i in range(buttons.size()):
		if buttons[i]:
			if i == current_intent:
				buttons[i].modulate = Color(1.5, 1.5, 1.5, 1.0)
			else:
				buttons[i].modulate = Color(1.0, 1.0, 1.0, 1.0)

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

func update_status_indicators():
	update_health_indicator()
	update_temperature_indicator()

func update_health_indicator():
	if not status_indicator or not health_system:
		return
	
	var health_percent = health_system.get_health_percent()
	var animation_name = ""
	
	if health_system.current_state == health_system.HealthState.DEAD:
		animation_name = "dead"
	elif health_system.current_state == health_system.HealthState.CRITICAL:
		animation_name = "critical"
	elif health_percent >= 90:
		animation_name = "healthy"
	elif health_percent >= 70:
		animation_name = "health_90"
	elif health_percent >= 50:
		animation_name = "health_70"
	elif health_percent >= 30:
		animation_name = "health_50"
	elif health_percent >= 20:
		animation_name = "health_30"
	else:
		animation_name = "health_20"
	
	if status_indicator.sprite_frames and status_indicator.sprite_frames.has_animation(animation_name):
		status_indicator.animation = animation_name
		status_indicator.play()

func update_temperature_indicator():
	if not temperature_indicator or not health_system:
		return
	
	var temp_status = health_system._get_temperature_status()
	var animation_name = ""
	
	match temp_status:
		health_system.TemperatureStatus.COLD:
			animation_name = "cold"
		health_system.TemperatureStatus.HYPOTHERMIC:
			animation_name = "very_cold"
		health_system.TemperatureStatus.CRITICAL:
			if health_system.body_temperature < health_system.BODY_TEMP_NORMAL:
				animation_name = "critically_cold"
			else:
				animation_name = "critically_hot"
		health_system.TemperatureStatus.WARM:
			animation_name = "hot"
		health_system.TemperatureStatus.HYPERTHERMIC:
			animation_name = "very_hot"
		_:
			animation_name = "none"
	
	if temperature_indicator.sprite_frames and temperature_indicator.sprite_frames.has_animation(animation_name):
		temperature_indicator.animation = animation_name
		temperature_indicator.play()

func toggle_throw_indicator(toggle: String):
	match toggle:
		"on":
			throw_mode_indicator.visible = true
		"off":
			throw_mode_indicator.visible = false
	
	play_sound_effect(SoundEffect.CLICK)

func add_slot_click_highlight(slot_name: String):
	var slot_container = get_slot_container(slot_name)
	if not slot_container:
		return
	
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	
	tween.tween_property(slot_container, "modulate", Color(1.5, 1.5, 1.5, 1.0), 0.1)
	tween.tween_property(slot_container, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.2)

func flash_hand_selection(hand_rect: Control):
	if not hand_rect:
		return
	
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	
	tween.tween_property(hand_rect, "modulate", Color(1.5, 1.8, 2.0, 1.0), 0.15)
	tween.tween_property(hand_rect, "modulate", Color(1.2, 1.2, 1.2, 1.0), 0.25)
	tween.tween_callback(update_active_hand)

func set_intent(intent: int):
	if current_intent != intent:
		current_intent = intent
		update_intent_buttons()
		apply_current_intent()

func apply_current_intent():
	if entity and entity.has_node("GridMovementController"):
		var grid_controller = entity.get_node("GridMovementController")
		if "intent" in grid_controller:
			grid_controller.intent = current_intent

func apply_movement_mode():
	if entity and entity.has_node("GridMovementController"):
		var grid_controller = entity.get_node("GridMovementController")
		if "is_sprinting" in grid_controller:
			grid_controller.is_sprinting = is_movement_sprint

func get_slot_container(slot_name: String) -> Control:
	match slot_name:
		"LeftHandSlot":
			return $Control/HandSlots/LeftHand
		"RightHandSlot":
			return $Control/HandSlots/RightHand
		"HeadSlot", "EyesSlot", "MaskSlot", "UniformSlot", "ArmorSlot", "GlovesSlot", "ShoesSlot", "SuitSlot", "Ear1Slot", "Ear2Slot":
			var container = get_node_or_null("Control/EquipmentItems/EquipmentButton/EquipmentSlots/GridContainer/" + slot_name)
			if not container:
				container = get_node_or_null("Control/EquipmentItems/EquipmentButton/EquipmentSlots/" + slot_name)
			return container
		"BackSlot", "BeltSlot", "IDSlot":
			return get_node_or_null("Control/MainSlots/" + slot_name)
		"Pouch1", "Pouch2":
			return get_node_or_null("Control/PouchSlots/" + slot_name)
	
	return null

func get_slot_button(slot_name: String) -> Control:
	var container = get_slot_container(slot_name)
	if not container:
		return null
	
	return container.get_node_or_null(slot_name + "Button")

func get_slot_sprite(slot_name: String) -> Node:
	if slot_name in slot_item_sprites:
		return slot_item_sprites[slot_name]
	
	return null

func get_slot_name_by_id(slot_id: int) -> String:
	for slot_name in slot_mapping:
		if slot_mapping[slot_name] == slot_id:
			return slot_name
	return ""

func can_perform_ui_action() -> bool:
	if not entity or not inventory_system:
		return false
	
	if entity.get_meta("is_npc", false):
		return false
	
	if not entity.get_meta("is_player", false):
		return false
	
	if not entity.is_multiplayer_authority():
		return false
	
	if inventory_system.get_meta("is_npc_inventory", false):
		return false
	
	return true

func validate_player_entity(player: Node) -> bool:
	if not player:
		return false
	
	if player.get_meta("is_npc", false):
		return false
	
	if not player.get_meta("is_player", false):
		return false
	
	if "is_npc" in player and player.is_npc:
		return false
	
	if "can_be_interacted_with" in player and player.can_be_interacted_with and player.get_meta("is_npc", false):
		return false
	
	return true

func validate_slot_interaction(slot_name: String) -> bool:
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
	
	var container = get_slot_container(slot_name)
	if not container:
		return false
	
	return true

func is_position_in_ui(position: Vector2) -> bool:
	if $Control.get_global_rect().has_point(position):
		return true
	
	for panel in storage_panels.values():
		if panel.get_global_rect().has_point(position):
			return true
	
	return false


func is_weapon(item: Node) -> bool:
	if not item:
		return false
	
	if "entity_type" in item and item.entity_type == "gun":
		return true
	
	return false

func is_magazine(item: Node) -> bool:
	if not item:
		return false
	
	if item.get_script():
		var script_path = str(item.get_script().get_path())
		if "Magazine" in script_path:
			return true
	
	if "ammo_type" in item and "current_ammo" in item:
		return true
	
	if "entity_type" in item and item.entity_type == "magazine":
		return true
	
	return false

func is_storage_item(item: Node) -> bool:
	if not item:
		return false
	
	if "storage_type" in item:
		return item.storage_type != 0
	
	return false

func create_placeholder_texture(color: Color = Color(0.8, 0.2, 0.2)) -> Texture2D:
	var image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(color)
	
	for x in range(32):
		for y in range(32):
			if x == 0 or y == 0 or x == 31 or y == 31:
				image.set_pixel(x, y, Color.BLACK)
	
	return ImageTexture.create_from_image(image)

func play_sound_effect(effect_type: int):
	if effect_type in sound_effects and sound_effects[effect_type]:
		var audio_player = AudioStreamPlayer.new()
		audio_player.stream = sound_effects[effect_type]
		audio_player.volume_db = -10
		add_child(audio_player)
		audio_player.play()
		audio_player.finished.connect(func(): audio_player.queue_free())

func show_notification(text: String):
	print("Notification: " + text)

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

func _on_health_changed(new_health: float, max_health: float, health_percent: float):
	update_health_indicator()

func _on_temperature_changed(new_temp: float, temp_status: int):
	update_temperature_indicator()

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

func _on_intent_button_pressed(intent: int):
	if not can_perform_ui_action():
		return
	
	if intent != current_intent:
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

func _on_drop_button_pressed():
	if not can_perform_ui_action():
		return
	
	if inventory_system:
		inventory_system.drop_active_item()
		play_sound_effect(SoundEffect.DROP)
