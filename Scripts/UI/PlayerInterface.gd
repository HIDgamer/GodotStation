extends Control

# PUI - the restored old prototype's HUD, rewired against the current
# architecture. Connection rebuild vs. the restored-as-is version:
#  - Local-player lookup: this scene now lives INSIDE Human.tscn
#    (UILayer/PlayerInterface, one copy per mob, same as every other
#    peer's mob) instead of being a single global overlay - so instead of
#    searching the "Mob" group + is_multiplayer_authority() (wrong check
#    here anyway; authority is always the server, see PlayerMob's header
#    comment), it just walks straight up to its own owning mob and checks
#    OwnerPeerId against the local peer id.
#  - Hands/equipment/intent read from PlayerMob's frozen Hud* signals
#    (HudHandsChanged/HudEquipmentChanged/HudIntentChanged), NOT from the
#    Inventory component directly. Inventory only ever gets mutated
#    server-side - a non-host client's own local copy of their own
#    Inventory node is never written to, so reading it directly would work
#    for the host testing their own character and silently show nothing
#    for anyone who joined. The Hud* signals are synced to every peer for
#    exactly this reason.
#  - Health-based icons (hunger/status) read from HudHealthChanged
#    (synced) instead of HealthSystem.GetHealthPercentage() directly. Pain
#    level and fire-stack icons still read HealthSystem/FireSystem
#    directly - there's no synced Hud signal for those yet, so they're
#    host-correct/remote-approximate until the Hud ABI grows one; noted
#    inline rather than silently left looking fully correct.
#  - InteractionComponent/IntentSystem are gone: switch_hand/drop/throw/
#    equip route through PlayerMob's HudRequest* verbs. Intent buttons are
#    IntentUI.gd's job (a sibling script already wired to the same
#    buttons) - this script no longer touches them, to avoid both scripts
#    fighting over the same TextureButtons.
#  - Limb selector stays purely local/visual - there's no "selected limb"
#    consumer in CombatResolver yet (limb-targeted damage is future work),
#    so nothing is sent over the network for it.

@onready var lhand: TextureButton = $CenterBar/MainContainer/LHand
@onready var rhand: TextureButton = $CenterBar/MainContainer/RHand
@onready var lhighlight: TextureRect = $CenterBar/MainContainer/LHand/LHighlight
@onready var rhighlight: TextureRect = $CenterBar/MainContainer/RHand/RHighlight
@onready var equipment_button: TextureButton = $CenterBar/MainContainer/Equipment
@onready var equipment_section: Control = $CenterBar/MainContainer/Equipment/GridContainer
@onready var main_container: Control = $CenterBar/MainContainer
@onready var left_bar: Control = $LeftBar
@onready var throw_button: Sprite2D = $RightBar/UpperRow/Throw
@onready var pull_button: TextureButton = $RightBar/UpperRow/Pull
@onready var run_button: TextureButton = $RightBar/LowerRow/Run

@onready var status_sprite: Sprite2D = $StatusColumn/Status
@onready var temp_sprite: Sprite2D = $StatusColumn/Temp
@onready var hunger_sprite: Sprite2D = $StatusColumn/Hunger
@onready var effect_sprite: Sprite2D = $StatusColumn/Effect

@onready var limbs_selector: TextureRect = $RightBar/LowerRow/LimbContainer/LimbsSelector
@onready var mouth_button: TextureRect = $RightBar/LowerRow/LimbContainer/LimbsSelector/Mouth
@onready var eyes_button: TextureRect = $RightBar/LowerRow/LimbContainer/LimbsSelector/Eyes
@onready var head_button: TextureRect = $RightBar/LowerRow/LimbContainer/LimbsSelector/Head
@onready var body_button: TextureRect = $RightBar/LowerRow/LimbContainer/LimbsSelector/Body
@onready var right_arm_button: TextureRect = $RightBar/LowerRow/LimbContainer/LimbsSelector/RightArm
@onready var right_hand_button: TextureRect = $RightBar/LowerRow/LimbContainer/LimbsSelector/RightHand
@onready var left_arm_button: TextureRect = $RightBar/LowerRow/LimbContainer/LimbsSelector/LeftArm
@onready var left_hand_button: TextureRect = $RightBar/LowerRow/LimbContainer/LimbsSelector/LeftHand
@onready var groin_button: TextureRect = $RightBar/LowerRow/LimbContainer/LimbsSelector/Groin
@onready var left_leg_button: TextureRect = $RightBar/LowerRow/LimbContainer/LimbsSelector/LeftLeg
@onready var left_foot_button: TextureRect = $RightBar/LowerRow/LimbContainer/LimbsSelector/LeftFoot
@onready var right_leg_button: TextureRect = $RightBar/LowerRow/LimbContainer/LimbsSelector/RightLeg
@onready var right_foot_button: TextureRect = $RightBar/LowerRow/LimbContainer/LimbsSelector/RightFoot

const HUD_SHEET := "res://Icons/mob/hud/screen1.png"
const ZONE_SEL_SHEET := "res://Icons/mob/hud/zone_sel.png"

var player: Node = null
var clothing_slots: Dictionary = {}
var current_limb: String = "right_hand"

# Cached from PlayerMob's Hud* signals - index 0 = right hand, 1 = left
# hand (current Inventory convention).
var hand_state: Array = [{"sheet": "", "state": ""}, {"sheet": "", "state": ""}]
var active_hand: int = 0
var equipment_state: Dictionary = {}
var last_health_percent: float = 100.0

func _ready() -> void:
	equipment_section.visible = false
	lhighlight.visible = true
	rhighlight.visible = false
	visible = false

	player = get_parent().get_parent()
	if not player or player.OwnerPeerId != multiplayer.get_unique_id():
		return

	visible = true

	player.HudHandsChanged.connect(_on_hud_hands_changed)
	player.HudEquipmentChanged.connect(_on_hud_equipment_changed)
	player.HudHealthChanged.connect(_on_hud_health_changed)

	equipment_button.pressed.connect(func(): equipment_section.visible = !equipment_section.visible)
	lhand.pressed.connect(func(): _switch_hand(1))
	rhand.pressed.connect(func(): _switch_hand(0))
	pull_button.gui_input.connect(_on_pull_button_input)

	_setup_static_textures()
	_setup_clothing_slots()
	_setup_limb_selector()
	_setup_status_effects()
	_update_ui()
	_update_limb_selection_visuals("right_hand")

func _process(_delta: float) -> void:
	if not player:
		return

	var interaction = player.get_node_or_null("PlayerInteractionSystem")
	var is_pulling = interaction != null and interaction.IsPulling()
	pull_button.modulate = Color.RED if is_pulling else Color.WHITE

func _unhandled_input(event: InputEvent) -> void:
	if not player:
		return

	if event.is_action_pressed("head"):
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

func _on_pull_button_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var interaction = player.get_node_or_null("PlayerInteractionSystem")
		if interaction != null and interaction.IsPulling():
			player.HudRequestFiremanCarry()
		get_viewport().set_input_as_handled()

func _switch_hand(hand: int) -> void:
	if player and active_hand != hand:
		player.HudRequestSwitchHand()

func _on_hud_hands_changed(hand0_path: String, hand0_state: String, hand1_path: String, hand1_state: String, active_hand_idx: int) -> void:
	hand_state[0] = {"sheet": hand0_path, "state": hand0_state}
	hand_state[1] = {"sheet": hand1_path, "state": hand1_state}
	active_hand = active_hand_idx
	_update_ui()

func _on_hud_equipment_changed(slot: String, sheet_path: String, state: String) -> void:
	equipment_state[slot] = {"sheet": sheet_path, "state": state}
	_update_clothing_slot_icon(slot)

func _on_hud_health_changed(integrity: float, max_integrity: float) -> void:
	last_health_percent = (integrity / max_integrity) * 100.0 if max_integrity > 0 else 0.0
	_update_status_effects()

# Base HUD chrome (hand slots, equipment toggle, pull button, limb doll) -
# real ucfss13 icon states from screen1.png/zone_sel.png, confirmed against
# their .icon.json state lists (2026-09-14), not guessed. Every one of these
# nodes had layout but zero texture assigned in PUI.tscn - the whole HUD
# frame was invisible, not just unpopulated, until this ran. Item/equipment
# icons layered on top of this backdrop are handled separately by
# _make_icon() and were already working.
func _setup_static_textures() -> void:
	lhand.texture_normal = IconBridge.GetFrame(HUD_SHEET, "hand")
	rhand.texture_normal = IconBridge.GetFrame(HUD_SHEET, "hand")
	lhighlight.texture = IconBridge.GetFrame(HUD_SHEET, "selector")
	rhighlight.texture = IconBridge.GetFrame(HUD_SHEET, "selector")
	equipment_button.texture_normal = IconBridge.GetFrame(HUD_SHEET, "equip")
	pull_button.texture_normal = IconBridge.GetFrame(HUD_SHEET, "pull0")

	if limbs_selector:
		limbs_selector.texture = IconBridge.GetFrame(HUD_SHEET, "zone_sel")

	# zone_sel.png holds one highlight overlay per body part (DM convention:
	# the doll backdrop above is a screen1.dmi state, the per-zone highlight
	# is a separate file) - mapped from this UI's own limb names to DM's.
	var limb_zone_states = {
		mouth_button: "mouth", eyes_button: "eyes", head_button: "head", body_button: "chest",
		right_arm_button: "r_arm", right_hand_button: "r_hand",
		left_arm_button: "l_arm", left_hand_button: "l_hand",
		groin_button: "groin", left_leg_button: "l_leg", left_foot_button: "l_foot",
		right_leg_button: "r_leg", right_foot_button: "r_foot",
	}
	for limb_button in limb_zone_states.keys():
		if limb_button:
			limb_button.texture = IconBridge.GetFrame(ZONE_SEL_SHEET, limb_zone_states[limb_button])

func _setup_clothing_slots() -> void:
	var equipment_slot_map = {
		"head": "Head/HeadSlot",
		"eyes": "Eyes/EyesSlot",
		"mask": "Mask/MaskSlot",
		"ear_left": "LEar/LEarSlot",
		"ear_right": "REar/REarSlot",
		"gloves": "Gloves/GlovesSlot",
		"uniform": "Uniform/UniformSlot",
		"jacket": "Armor/ArmorSlot",
		"shoes": "Shoes/ShoesSlot",
		"accessory": "ArmorHolster/ArmorHolsterSlot",
	}
	for slot_name in equipment_slot_map.keys():
		_wire_clothing_slot(equipment_section, slot_name, equipment_slot_map[slot_name])

	var left_bar_slot_map = {
		"id": "ID/IDSlot",
		"belt": "Belt/BeltSlot",
		"back": "Backpack/BackpackSlot",
	}
	for slot_name in left_bar_slot_map.keys():
		_wire_clothing_slot(left_bar, slot_name, left_bar_slot_map[slot_name])

	var main_slot_map = {
		"pouch_left": "LPouch/LPouchSlot",
		"pouch_right": "RPouch/LPouchSlot", # scene typo: RPouch's own slot child is misnamed LPouchSlot
	}
	for slot_name in main_slot_map.keys():
		_wire_clothing_slot(main_container, slot_name, main_slot_map[slot_name])

func _wire_clothing_slot(root: Node, slot_name: String, node_path: String) -> void:
	var slot_node = root.get_node_or_null(node_path)
	if slot_node:
		clothing_slots[slot_name] = slot_node
		slot_node.gui_input.connect(_on_clothing_slot_input.bind(slot_name))

func _setup_limb_selector() -> void:
	if limbs_selector:
		limbs_selector.mouse_filter = Control.MOUSE_FILTER_STOP
		limbs_selector.gui_input.connect(_on_limbs_selector_input)

	var limb_buttons_map = {
		"head": head_button, "body": body_button,
		"left_arm": left_arm_button, "right_arm": right_arm_button,
		"left_leg": left_leg_button, "right_leg": right_leg_button,
		"groin": groin_button, "left_hand": left_hand_button, "right_hand": right_hand_button,
		"left_foot": left_foot_button, "right_foot": right_foot_button,
		"mouth": mouth_button, "eyes": eyes_button,
	}
	for limb_name in limb_buttons_map.keys():
		var limb_button = limb_buttons_map[limb_name]
		if limb_button:
			limb_button.mouse_filter = Control.MOUSE_FILTER_IGNORE

# Local-only visual state - no "selected limb" consumer exists on the
# server yet (limb-targeted damage is future work), so this never sends
# anything over the network.
func _select_limb(limb_name: String) -> void:
	var final_limb = _get_toggled_limb(limb_name)
	current_limb = final_limb
	_update_limb_selection_visuals(final_limb)

func _get_toggled_limb(requested_limb: String) -> String:
	var head_cycle = ["head", "eyes", "mouth"]
	var left_arm_cycle = ["left_arm", "left_hand"]
	var right_arm_cycle = ["right_arm", "right_hand"]
	var left_leg_cycle = ["left_leg", "left_foot"]
	var right_leg_cycle = ["right_leg", "right_foot"]

	for cycle in [head_cycle, left_arm_cycle, right_arm_cycle, left_leg_cycle, right_leg_cycle]:
		if requested_limb in cycle:
			if current_limb in cycle:
				var idx = cycle.find(current_limb)
				return cycle[(idx + 1) % cycle.size()]
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

func _update_limb_selection_visuals(selected_limb: String) -> void:
	var all_limbs = [
		mouth_button, eyes_button, head_button, body_button,
		right_arm_button, right_hand_button, left_arm_button, left_hand_button,
		groin_button, left_leg_button, left_foot_button, right_leg_button, right_foot_button,
	]
	var all_limb_names = [
		"mouth", "eyes", "head", "body",
		"right_arm", "right_hand", "left_arm", "left_hand",
		"groin", "left_leg", "left_foot", "right_leg", "right_foot",
	]
	for i in range(all_limbs.size()):
		if all_limbs[i]:
			all_limbs[i].visible = (all_limb_names[i] == selected_limb)

func _setup_status_effects() -> void:
	if not player:
		return

	# Pain/fire icons: no synced Hud signal for these yet, so they only
	# reflect the truth for the host's own view of their own character
	# (see header comment) - HudHealthChanged already covers the
	# health-based icons correctly for everyone.
	var health_system = player.get_node_or_null("HealthSystem")
	if health_system:
		health_system.PainLevelChanged.connect(_update_status_effects.unbind(2))

	var fire_system = player.get_node_or_null("FireSystem")
	if fire_system:
		fire_system.FireStateChanged.connect(_update_status_effects.unbind(1))
		fire_system.FireStacksChanged.connect(_update_status_effects.unbind(1))

func _update_status_effects() -> void:
	if not player or not is_node_ready():
		return

	var hunger_frame = 0
	if last_health_percent < 20:
		hunger_frame = 2
	elif last_health_percent < 40:
		hunger_frame = 1
	elif last_health_percent < 60:
		hunger_frame = 0
	else:
		hunger_frame = -1

	if hunger_sprite:
		hunger_sprite.visible = hunger_frame >= 0
		if hunger_frame >= 0:
			hunger_sprite.frame = hunger_frame

	var fire_system = player.get_node_or_null("FireSystem")
	var fire_stacks = fire_system.GetFireStacks() if fire_system else 0.0
	if temp_sprite:
		temp_sprite.visible = fire_stacks > 0
		if fire_stacks > 0:
			temp_sprite.frame = 0 if fire_stacks > 5 else (1 if fire_stacks > 2 else 2)

	var health_system = player.get_node_or_null("HealthSystem")
	var pain_level = health_system.GetCurrentPainLevel() if health_system else 0
	var status_frame = 0
	if last_health_percent < 20:
		status_frame = 9
	elif last_health_percent < 40:
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

func _on_clothing_slot_input(event: InputEvent, slot_name: String) -> void:
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			var occupied = equipment_state.has(slot_name) and equipment_state[slot_name].sheet != ""
			if occupied:
				player.HudRequestUnequip(slot_name)
			else:
				player.HudRequestEquip(slot_name)
			get_viewport().set_input_as_handled()

func _make_icon(sheet_path: String, state: String) -> TextureRect:
	var icon := TextureRect.new()
	icon.name = "ItemIcon"
	icon.texture = IconBridge.GetFrame(sheet_path, state)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(32, 32)
	icon.size = Vector2(32, 32)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func _update_ui() -> void:
	if not is_node_ready():
		return

	var lhand_slot = lhand.get_node_or_null("LHandSlot")
	var rhand_slot = rhand.get_node_or_null("RHandSlot")
	if not lhand_slot or not rhand_slot:
		return

	for child in lhand_slot.get_children():
		child.queue_free()
	for child in rhand_slot.get_children():
		child.queue_free()

	var right = hand_state[0]
	var left = hand_state[1]

	if right.sheet != "":
		rhand_slot.add_child(_make_icon(right.sheet, right.state))
	if left.sheet != "":
		lhand_slot.add_child(_make_icon(left.sheet, left.state))

	lhighlight.visible = (active_hand == 1)
	rhighlight.visible = (active_hand == 0)

func _update_clothing_slot_icon(slot_name: String) -> void:
	if not clothing_slots.has(slot_name):
		return
	var slot_node = clothing_slots[slot_name]
	if not is_instance_valid(slot_node):
		return

	for child in slot_node.get_children():
		child.queue_free()

	var st = equipment_state.get(slot_name, {"sheet": "", "state": ""})
	if st.sheet != "":
		slot_node.add_child(_make_icon(st.sheet, st.state))
