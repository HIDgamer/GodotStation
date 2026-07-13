extends Control

enum Intent { Help, Disarm, Grab, Harm }

@onready var lhand: TextureButton = $HBoxContainer/MainContainer/LHand
@onready var rhand: TextureButton = $HBoxContainer/MainContainer/RHand
@onready var lhighlight: TextureRect = $HBoxContainer/MainContainer/LHand/LHighlight
@onready var rhighlight: TextureRect = $HBoxContainer/MainContainer/RHand/RHighlight
@onready var equipment_button: TextureButton = $HBoxContainer/MainContainer/Equipment
@onready var equipment_section: Control = $HBoxContainer/MainContainer/Equipment/GridContainer
@onready var throw_button: Sprite2D = $HBoxContainer/ActionContainer/Throw
@onready var pull_button: Sprite2D = $HBoxContainer/ActionContainer/Pull
@onready var run_button: TextureButton = $HBoxContainer/ActionContainer/Run

@onready var status_sprite: Sprite2D = $HBoxContainer/StatusEffectContainer/Status
@onready var temp_sprite: Sprite2D = $HBoxContainer/StatusEffectContainer/Temp
@onready var hunger_sprite: Sprite2D = $HBoxContainer/StatusEffectContainer/Hunger
@onready var effect_sprite: Sprite2D = $HBoxContainer/StatusEffectContainer/Effect

@onready var limbs_selector: TextureRect = $HBoxContainer/LimbContainer/LimbsSelector
@onready var mouth_button: TextureRect = $HBoxContainer/LimbContainer/LimbsSelector/Mouth
@onready var eyes_button: TextureRect = $HBoxContainer/LimbContainer/LimbsSelector/Eyes
@onready var head_button: TextureRect = $HBoxContainer/LimbContainer/LimbsSelector/Head
@onready var body_button: TextureRect = $HBoxContainer/LimbContainer/LimbsSelector/Body
@onready var right_arm_button: TextureRect = $HBoxContainer/LimbContainer/LimbsSelector/RightArm
@onready var right_hand_button: TextureRect = $HBoxContainer/LimbContainer/LimbsSelector/RightHand
@onready var left_arm_button: TextureRect = $HBoxContainer/LimbContainer/LimbsSelector/LeftArm
@onready var left_hand_button: TextureRect = $HBoxContainer/LimbContainer/LimbsSelector/LeftHand
@onready var groin_button: TextureRect = $HBoxContainer/LimbContainer/LimbsSelector/Groin
@onready var left_leg_button: TextureRect = $HBoxContainer/LimbContainer/LimbsSelector/LeftLeg
@onready var left_foot_button: TextureRect = $HBoxContainer/LimbContainer/LimbsSelector/LeftFoot
@onready var right_leg_button: TextureRect = $HBoxContainer/LimbContainer/LimbsSelector/RightLeg
@onready var right_foot_button: TextureRect = $HBoxContainer/LimbContainer/LimbsSelector/RightFoot

var selected_hand: int = 0
var inventory: Node = null
var player: Node = null
var interaction: Node = null
var clothing_slots: Dictionary = {}
var current_limb: String = "right_hand"

func _ready() -> void:
	equipment_section.visible = false
	lhighlight.visible = true
	rhighlight.visible = false
	visible = false

	var tree = get_tree()
	if tree == null:
		return

	var mobs = tree.get_nodes_in_group("Mob")
	for mob in mobs:
		if mob.is_multiplayer_authority():
			player = mob
			break

	if not player:
		await tree.create_timer(0.5).timeout
		tree = get_tree()
		if tree == null:
			return
		mobs = tree.get_nodes_in_group("Mob")
		for mob in mobs:
			if mob.is_multiplayer_authority():
				player = mob
				break

	if not player:
		return

	if not player.is_multiplayer_authority():
		return

	visible = true
	inventory = player.get_node_or_null("Inventory")
	interaction = player.get_node_or_null("InteractionComponent")

	if inventory:
		if not inventory.InventoryChanged.is_connected(_update_ui):
			inventory.InventoryChanged.connect(_update_ui)

	if interaction:
		if not interaction.HandSwitched.is_connected(_on_hand_switched):
			interaction.HandSwitched.connect(_on_hand_switched)
		if not interaction.LimbSelected.is_connected(_on_limb_selected):
			interaction.LimbSelected.connect(_on_limb_selected)

	equipment_button.pressed.connect(func(): equipment_section.visible = !equipment_section.visible)
	lhand.pressed.connect(func(): _switch_hand(0))
	rhand.pressed.connect(func(): _switch_hand(1))

	_setup_clothing_slots()
	_setup_intent_buttons()
	_setup_limb_selector()
	_setup_status_effects()
	_update_ui()
	_update_limb_selection_visuals("right_hand")

	tree_exiting.connect(_cleanup_signals)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var local_pos = get_local_mouse_position()
			
			if throw_button and throw_button.visible:
				var throw_rect = Rect2(throw_button.position - throw_button.texture.get_size() / 2, throw_button.texture.get_size())
				if throw_rect.has_point(local_pos):
					# Let interactioncomponent handle throw toggle.
					# Just don't consume the input here.
					return
			
			if pull_button and pull_button.visible:
				var pull_rect = Rect2(pull_button.position - pull_button.texture.get_size() / 2, pull_button.texture.get_size())
				if pull_rect.has_point(local_pos):
					_toggle_pull_mode()
					get_viewport().set_input_as_handled()
					return

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("switch_hand"):
		_switch_hand(1 - selected_hand)
	elif event.is_action_pressed("pull"):
		if Input.is_key_pressed(KEY_CTRL):
			_toggle_pull_mode()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("head"):
		_select_limb("head")
	elif event.is_action_pressed("body"):
		_select_limb("body")
	elif event.is_action_pressed("left_arm"):
		_select_limb("left_arm")
	elif event.is_action_pressed("right_arm"):
		_select_limb("right_arm")
	elif event.is_action_pressed("left_leg"):
		_select_limb("left_leg")
	elif event.is_action_pressed("right_leg"):
		_select_limb("right_leg")
	elif event.is_action_pressed("groin"):
		_select_limb("groin")

func _on_hand_switched(hand: int) -> void:
	selected_hand = hand
	lhighlight.visible = (hand == 0)
	rhighlight.visible = (hand == 1)

func _on_limb_selected(limb_name: String) -> void:
	_update_limb_selection_visuals(limb_name)

func _toggle_pull_mode() -> void:
	if interaction and interaction.has_method("TogglePullMode"):
		interaction.TogglePullMode()

func _process(_delta: float) -> void:
	if interaction:
		var is_throw = interaction.IsThrowMode()
		var is_long_throw = interaction.IsLongThrowMode()
		var is_pull = interaction.has_method("IsPullMode") and interaction.IsPullMode()
		
		if is_long_throw:
			throw_button.frame = 2
		elif is_throw:
			throw_button.frame = 1
		else:
			throw_button.frame = 0
		
		if is_pull:
			pull_button.modulate = Color.RED
		else:
			pull_button.modulate = Color.WHITE

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
	var intent_container = get_node_or_null("HBoxContainer/IntentContainer")
	if intent_container:
		for child in intent_container.get_children():
			if child is TextureButton:
				child.pressed.connect(_on_intent_button_pressed.bind(child.name))

func _setup_limb_selector() -> void:
	if limbs_selector:
		limbs_selector.mouse_filter = Control.MOUSE_FILTER_STOP
		limbs_selector.gui_input.connect(_on_limbs_selector_input)
	
	var limb_buttons_map = {
		"head": head_button,
		"body": body_button,
		"left_arm": left_arm_button,
		"right_arm": right_arm_button,
		"left_leg": left_leg_button,
		"right_leg": right_leg_button,
		"groin": groin_button,
		"left_hand": left_hand_button,
		"right_hand": right_hand_button,
		"left_foot": left_foot_button,
		"right_foot": right_foot_button,
		"mouth": mouth_button,
		"eyes": eyes_button
	}
	
	for limb_name in limb_buttons_map.keys():
		var limb_button = limb_buttons_map[limb_name]
		if limb_button:
			limb_button.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _select_limb(limb_name: String) -> void:
	var final_limb = _get_toggled_limb(limb_name)
	current_limb = final_limb
	
	if interaction and interaction.has_method("SetSelectedLimb"):
		interaction.SetSelectedLimb(final_limb)
	_update_limb_selection_visuals(final_limb)

func _get_toggled_limb(requested_limb: String) -> String:
	var head_cycle = ["head", "eyes", "mouth"]
	var left_arm_cycle = ["left_arm", "left_hand"]
	var right_arm_cycle = ["right_arm", "right_hand"]
	var left_leg_cycle = ["left_leg", "left_foot"]
	var right_leg_cycle = ["right_leg", "right_foot"]
	
	if requested_limb in head_cycle:
		if current_limb in head_cycle:
			var idx = head_cycle.find(current_limb)
			return head_cycle[(idx + 1) % head_cycle.size()]
		return requested_limb
	elif requested_limb in left_arm_cycle:
		if current_limb in left_arm_cycle:
			var idx = left_arm_cycle.find(current_limb)
			return left_arm_cycle[(idx + 1) % left_arm_cycle.size()]
		return requested_limb
	elif requested_limb in right_arm_cycle:
		if current_limb in right_arm_cycle:
			var idx = right_arm_cycle.find(current_limb)
			return right_arm_cycle[(idx + 1) % right_arm_cycle.size()]
		return requested_limb
	elif requested_limb in left_leg_cycle:
		if current_limb in left_leg_cycle:
			var idx = left_leg_cycle.find(current_limb)
			return left_leg_cycle[(idx + 1) % left_leg_cycle.size()]
		return requested_limb
	elif requested_limb in right_leg_cycle:
		if current_limb in right_leg_cycle:
			var idx = right_leg_cycle.find(current_limb)
			return right_leg_cycle[(idx + 1) % right_leg_cycle.size()]
		return requested_limb
	
	return requested_limb

func _on_limbs_selector_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var local_pos = limbs_selector.get_local_mouse_position()
			var limb_name = _determine_limb_from_position(local_pos)
			if limb_name != "":
				_select_limb(limb_name)
				get_viewport().set_input_as_handled()

func _determine_limb_from_position(pos: Vector2) -> String:
	var siz = limbs_selector.size
	var x_ratio = pos.x / siz.x
	var y_ratio = pos.y / siz.y
	
	if y_ratio < 0.15:
		if x_ratio > 0.4 and x_ratio < 0.6:
			return "head"
		elif x_ratio <= 0.4:
			return "head"
		else:
			return "head"
	elif y_ratio < 0.35:
		if x_ratio < 0.3:
			return "right_arm"
		elif x_ratio > 0.7:
			return "left_arm"
		else:
			return "body"
	elif y_ratio < 0.5:
		if x_ratio < 0.35:
			return "right_arm"
		elif x_ratio > 0.65:
			return "left_arm"
		else:
			return "groin"
	elif y_ratio < 0.8:
		if x_ratio < 0.4:
			return "right_leg"
		elif x_ratio > 0.6:
			return "left_leg"
		else:
			return "groin"
	else:
		if x_ratio < 0.4:
			return "right_leg"
		elif x_ratio > 0.6:
			return "left_leg"
	
	return "body"

func _on_action_button_input(event: InputEvent, action_name: String) -> void:
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			match action_name:
				"pull":
					_toggle_pull_mode()
			get_viewport().set_input_as_handled()

func _update_limb_selection_visuals(selected_limb: String) -> void:
	var all_limbs = [
		mouth_button, eyes_button, head_button, body_button,
		right_arm_button, right_hand_button, left_arm_button, left_hand_button,
		groin_button, left_leg_button, left_foot_button, right_leg_button, right_foot_button
	]
	var all_limb_names = [
		"mouth", "eyes", "head", "body",
		"right_arm", "right_hand", "left_arm", "left_hand",
		"groin", "left_leg", "left_foot", "right_leg", "right_foot"
	]
	
	for i in range(all_limbs.size()):
		var limb_button = all_limbs[i]
		if limb_button:
			limb_button.visible = (all_limb_names[i] == selected_limb)

func _setup_status_effects() -> void:
	if player:
		var health_system = player.get_node_or_null("HealthSystem")
		if health_system:
			health_system.HealthChanged.connect(_update_status_effects)
			health_system.PainLevelChanged.connect(_update_status_effects)
		
		
		var fire_system = player.get_node_or_null("FireSystem")
		if fire_system:
			fire_system.FireStateChanged.connect(_update_status_effects)
			fire_system.FireStacksChanged.connect(_update_status_effects)

func _update_status_effects(_arg1 = null, _arg2 = null, _arg3 = null) -> void:
	if not player or not is_node_ready():
		return
	
	var hunger_frame = 0
	var health_system = player.get_node_or_null("HealthSystem")
	if health_system:
		var health_percent = health_system.GetHealthPercentage()
		if health_percent < 20:
			hunger_frame = 2
		elif health_percent < 40:
			hunger_frame = 1
		elif health_percent < 60:
			hunger_frame = 0
		else:
			hunger_frame = -1
	
	if hunger_sprite and hunger_frame >= 0:
		hunger_sprite.visible = true
		hunger_sprite.frame = hunger_frame
	else:
		hunger_sprite.visible = false
	
	var temp_frame = 0
	var fire_system = player.get_node_or_null("FireSystem")
	var fire_stacks = 0
	if fire_system:
		fire_stacks = fire_system.GetFireStacks()
		if fire_stacks > 5:
			temp_frame = 0
		elif fire_stacks > 2:
			temp_frame = 1
		elif fire_stacks > 0:
			temp_frame = 2
		else:
			temp_frame = 3
	
	if temp_sprite:
		temp_sprite.visible = fire_stacks > 0
		if fire_stacks > 0:
			temp_sprite.frame = temp_frame
	
	var status_frame = 0
	if health_system:
		var pain_level = health_system.GetCurrentPainLevel()
		var health_percent = health_system.GetHealthPercentage()
		
		if health_percent < 20:
			status_frame = 9
		elif health_percent < 40:
			status_frame = 7
		elif pain_level == 6:
			status_frame = 5
		elif pain_level == 5:
			status_frame = 4
		elif pain_level == 4:
			status_frame = 3
		elif pain_level == 3:
			status_frame = 2
		elif pain_level == 2:
			status_frame = 1
		else:
			status_frame = 0
	
	if status_sprite:
		status_sprite.visible = true
		status_sprite.frame = status_frame

func _on_intent_button_pressed(button_name: String) -> void:
	if not player:
		return
	
	var intent_map = {
		"Help": Intent.Help,
		"Disarm": Intent.Disarm,
		"Grab": Intent.Grab,
		"Harm": Intent.Harm
	}
	
	if intent_map.has(button_name):
		var new_intent = intent_map[button_name]
		var intent_system = player.get_node_or_null("IntentSystem")
		if intent_system:
			if intent_system.has_method("SetIntent"):
				intent_system.call("SetIntent", new_intent)
			elif intent_system.has_method("set_intent"):
				intent_system.call("set_intent", new_intent)
		_update_intent_visuals(new_intent)

func _update_intent_visuals(current_intent: Intent) -> void:
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
					child.modulate = Color(1, 1, 0.5, 1)
				else:
					child.modulate = Color.WHITE

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
							var owner_peer_id = player.get_multiplayer_authority()
							inventory.rpc_id(1, "RequestDropEquippedRpc", owner_peer_id, slot_name)
					else:
						var activeSlot = "left_hand" if selected_hand == 0 else "right_hand"
						if inventory.GetEquipped(activeSlot) == null:
							var owner_peer_id = player.get_multiplayer_authority()
							if multiplayer.is_server():
								inventory.Unequip(slot_name)
								inventory.Equip(item, activeSlot)
							else:
								inventory.rpc_id(1, "RequestUnequipToHandRpc", owner_peer_id, slot_name, activeSlot)
				else:
					var owner_peer_id = player.get_multiplayer_authority()
					if multiplayer.is_server():
						inventory.TryEquipFromInventory(slot_name)
					else:
						inventory.rpc_id(1, "RequestEquipFromHandRpc", owner_peer_id, slot_name)
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

	for child in lhand_slot.get_children():
		child.queue_free()
	for child in rhand_slot.get_children():
		child.queue_free()

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
	if inventory and inventory.InventoryChanged.is_connected(_update_ui):
		inventory.InventoryChanged.disconnect(_update_ui)

	if interaction and interaction.HandSwitched.is_connected(_on_hand_switched):
		interaction.HandSwitched.disconnect(_on_hand_switched)
