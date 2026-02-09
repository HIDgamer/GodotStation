extends Control

# Import the Intent enum
enum Intent { Help, Disarm, Grab, Harm }

@onready var lhand: TextureButton = $HBoxContainer/MainContainer/LHand
@onready var rhand: TextureButton = $HBoxContainer/MainContainer/RHand
@onready var lhighlight: TextureRect = $HBoxContainer/MainContainer/LHand/LHighlight
@onready var rhighlight: TextureRect = $HBoxContainer/MainContainer/RHand/RHighlight
@onready var equipment_button: TextureButton = $HBoxContainer/MainContainer/Equipment
@onready var equipment_section: Control = $HBoxContainer/MainContainer/Equipment/GridContainer
@onready var throw_button: TextureButton = $HBoxContainer/ActionContainer/Throw

var selected_hand: int = 0
var inventory: Node = null
var player: Node = null
var interaction: Node = null
var clothing_slots: Dictionary = {}

func _ready() -> void:
	equipment_section.visible = false
	lhighlight.visible = true
	rhighlight.visible = false

	# Hide UI by default until we find our player
	visible = false

	await get_tree().process_frame
	await get_tree().process_frame

	# Find the player that this client controls
	var mobs = get_tree().get_nodes_in_group("Mob")
	for mob in mobs:
		if mob.is_multiplayer_authority():
			player = mob
			break

	if not player:
		print("[PlayerInterface] No local player found yet, will retry")
		await get_tree().create_timer(0.5).timeout
		mobs = get_tree().get_nodes_in_group("Mob")
		for mob in mobs:
			if mob.is_multiplayer_authority():
				player = mob
				break

	if not player:
		print("[PlayerInterface] Still no local player, hiding UI")
		return

	print("[PlayerInterface] Found local player: ", player.name)
	# Show UI only for our player
	visible = true
	inventory = player.get_node_or_null("Inventory")
	interaction = player.get_node_or_null("InteractionComponent")

	# Connect signals with proper null checks
	if inventory:
		if not inventory.InventoryChanged.is_connected(_update_ui):
			inventory.InventoryChanged.connect(_update_ui)
	else:
		print("[PlayerInterface] Warning: Inventory not found for player ", player.name)

	if interaction:
		if not interaction.HandSwitched.is_connected(_on_hand_switched):
			interaction.HandSwitched.connect(_on_hand_switched)
	else:
		print("[PlayerInterface] Warning: InteractionComponent not found for player ", player.name)

	equipment_button.pressed.connect(func(): equipment_section.visible = !equipment_section.visible)
	lhand.pressed.connect(func(): _switch_hand(0))
	rhand.pressed.connect(func(): _switch_hand(1))
	throw_button.pressed.connect(_toggle_throw_mode)

	_setup_clothing_slots()
	_setup_intent_buttons()
	_update_ui()

	# Connect to tree_exiting to cleanup signals
	tree_exiting.connect(_cleanup_signals)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("switch_hand"):
		_switch_hand(1 - selected_hand)
	elif event.is_action_pressed("drop") and inventory:
		var slot = "left_hand" if selected_hand == 0 else "right_hand"
		var item = inventory.Unequip(slot)
		if item and player:
			_spawn_item(item, player.global_position)
	elif event.is_action_pressed("throw"):
		if Input.is_key_pressed(KEY_CTRL):
			_toggle_throw_mode()

func _on_hand_switched(hand: int) -> void:
	selected_hand = hand
	lhighlight.visible = (hand == 0)
	rhighlight.visible = (hand == 1)

func _toggle_throw_mode() -> void:
	if interaction:
		var is_throw = interaction.IsThrowMode()
		throw_button.modulate = Color.RED if is_throw else Color.WHITE

func _process(_delta: float) -> void:
	if interaction:
		throw_button.modulate = Color.RED if interaction.IsThrowMode() else Color.WHITE

func _switch_hand(hand: int) -> void:
	selected_hand = hand
	lhighlight.visible = (hand == 0)
	rhighlight.visible = (hand == 1)
	if inventory:
		inventory.SetActiveHand(hand)

func _setup_clothing_slots() -> void:
	if not equipment_section:
		return
	
	var slot_map = {
		"head": "Head/HeadSlot",
		"eyes": "Eyes/EyesSlot",
		"mask": "Mask/MaskSlot",
		"ears_left": "LEar/LEarSlot",
		"ears_right": "REar/REarSlot",
		"gloves": "Gloves/GlovesSlot",
		"uniform": "Uniform/UniformSlot",
		"armor": "Armor/ArmorSlot",
		"shoes": "Shoes/ShoesSlot",
		"armor_holster": "ArmorHolster/ArmorHolsterSlot"
	}
	
	for slot_name in slot_map.keys():
		var slot_node = equipment_section.get_node_or_null(slot_map[slot_name])
		if slot_node:
			clothing_slots[slot_name] = slot_node
			slot_node.gui_input.connect(_on_clothing_slot_input.bind(slot_name))

func _setup_intent_buttons() -> void:
	# Find intent buttons in the scene
	var intent_container = get_node_or_null("HBoxContainer/IntentContainer")
	if intent_container:
		for child in intent_container.get_children():
			if child is TextureButton:
				child.pressed.connect(_on_intent_button_pressed.bind(child.name))

func _on_intent_button_pressed(button_name: String) -> void:
	if not interaction:
		return
	
	# Map button names to intent values
	var intent_map = {
		"Help": Intent.Help,
		"Disarm": Intent.Disarm,
		"Grab": Intent.Grab,
		"Harm": Intent.Harm
	}
	
	if intent_map.has(button_name):
		var new_intent = intent_map[button_name]
		interaction.SetIntent(new_intent)
		_update_intent_visuals(new_intent)

func _update_intent_visuals(current_intent: Intent) -> void:
	# Update visual feedback for intent buttons
	var intent_container = get_node_or_null("HBoxContainer/IntentContainer")
	if intent_container:
		for child in intent_container.get_children():
			if child is TextureButton:
				var is_current = false
				match child.name:
					"Help": is_current = current_intent == Intent.Help
					"Disarm": is_current = current_intent == Intent.Disarm
					"Grab": is_current = current_intent == Intent.Grab
					"Harm": is_current = current_intent == Intent.Harm
				
				if is_current:
					child.modulate = Color(1, 1, 0.5, 1) # Yellow highlight
				else:
					child.modulate = Color.WHITE # Normal color

func _on_clothing_slot_input(event: InputEvent, slot_name: String) -> void:
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if inventory:
				var item = inventory.GetEquipped(slot_name)
				if item:
					if mb.shift_pressed:
						if multiplayer.is_server():
							inventory.DropEquipped(slot_name)
						else:
							var mob_path = player.get_path()
							inventory.rpc_id(1, "RequestDropEquippedRpc", mob_path, slot_name)
					else:
						var activeSlot = "left_hand" if selected_hand == 0 else "right_hand"
						if inventory.GetEquipped(activeSlot) == null:
							var mob_path = player.get_path()
							if multiplayer.is_server():
								inventory.Unequip(slot_name)
								inventory.Equip(item, activeSlot)
							else:
								inventory.rpc_id(1, "RequestUnequipToHandRpc", mob_path, slot_name, activeSlot)
				else:
					var mob_path = player.get_path()
					if multiplayer.is_server():
						inventory.TryEquipFromInventory(slot_name)
					else:
						inventory.rpc_id(1, "RequestEquipFromHandRpc", mob_path, slot_name)
			get_viewport().set_input_as_handled()

func _update_ui() -> void:
	if not inventory: 
		return

	if not is_node_ready():
		return

	var left_item = inventory.GetEquipped("left_hand")
	var right_item = inventory.GetEquipped("right_hand")

	var lhand_slot = lhand.get_node_or_null("LHandSlot")
	var rhand_slot = rhand.get_node_or_null("RHandSlot")

	if not lhand_slot or not rhand_slot:
		return

	# Clear old icons
	for child in lhand_slot.get_children():
		child.queue_free()
	for child in rhand_slot.get_children():
		child.queue_free()

	# Add left hand item
	if left_item and left_item.Icon:
		var icon = TextureRect.new()
		icon.name = "ItemIcon"
		icon.texture = left_item.GetIconWithFrame()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(32, 32)
		icon.size = Vector2(32, 32)
		icon.position = Vector2.ZERO
		icon.visible = true
		lhand_slot.add_child(icon)

	# Add right hand item
	if right_item and right_item.Icon:
		var icon = TextureRect.new()
		icon.name = "ItemIcon"
		icon.texture = right_item.GetIconWithFrame()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(32, 32)
		icon.size = Vector2(32, 32)
		icon.position = Vector2.ZERO
		icon.visible = true
		rhand_slot.add_child(icon)

	_update_clothing_slots()

func _update_clothing_slots() -> void:
	if not inventory:
		return

	if not is_node_ready():
		return

	for slot_name in clothing_slots.keys():
		var slot_node = clothing_slots[slot_name]
		if not slot_node or not is_instance_valid(slot_node):
			continue

		# Clear old icons
		for child in slot_node.get_children():
			child.queue_free()

		var item = inventory.GetEquipped(slot_name)
		if item and item.Icon:
			var icon = TextureRect.new()
			icon.name = "ItemIcon"
			icon.texture = item.GetIconWithFrame()
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(32, 32)
			icon.size = Vector2(32, 32)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot_node.add_child(icon)

func _cleanup_signals() -> void:
	# Disconnect all signals when the UI is being destroyed
	if inventory and inventory.InventoryChanged.is_connected(_update_ui):
		inventory.InventoryChanged.disconnect(_update_ui)

	if interaction and interaction.HandSwitched.is_connected(_on_hand_switched):
		interaction.HandSwitched.disconnect(_on_hand_switched)

func _spawn_item(item: Resource, pos: Vector2) -> void:
	var scene = load("res://Scenes/Items/" + item.ItemName + ".tscn")
	if scene:
		var world_item = scene.instantiate()
		world_item.position = pos
		world_item.ItemId = item.ItemName
		world_item.Quantity = 1
		get_tree().current_scene.add_child(world_item)
