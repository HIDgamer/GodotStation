# Inventorywindow - full inventory management interface.
# Provides drag-and-drop item management, container viewing, and equipment management.
extends Window

signal item_selected(item: Node)
signal item_dropped(item: Node, target_slot: String)
signal container_opened(container: Node)

@onready var inventory_grid: GridContainer = $Container/InventoryTab/InventoryGrid
@onready var equipment_grid: GridContainer = $Container/EquipmentTab/EquipmentGrid
@onready var container_grid: GridContainer = $Container/ContainerTab/ContainerGrid
@onready var quick_slots: HBoxContainer = $Container/QuickSlots/QuickSlotsContainer

@onready var inventory_tab: TabContainer = $Container
@onready var status_label: Label = $Container/StatusLabel
@onready var audio_manager: Node = $/root/AudioManager

var inventory_system = null
var current_container = null
var selected_item = null
var drag_start_slot: String = ""
var drag_start_index: int = -1

func _ready() -> void:
	set_process_input(true)
	
	# Connect to inventory events.
	var player = get_tree().get_first_node_in_group("Player")
	if player:
		inventory_system = player.get_node_or_null("InventorySystem")
	
	if inventory_system:
		inventory_system.connect("item_added", _on_item_added)
		inventory_system.connect("item_removed", _on_item_removed)
		inventory_system.connect("item_equipped", _on_item_equipped)
		inventory_system.connect("item_unequipped", _on_item_unequipped)
		inventory_system.connect("inventory_updated", _on_inventory_updated)
	
	_update_inventory_display()
	_update_equipment_display()
	
	# Add hover sounds to inventory tabs.
	if audio_manager:
		for i in range(inventory_tab.get_tab_count()):
			var tab = inventory_tab.get_tab_control(i)
			if tab:
				tab.mouse_entered.connect(_on_button_hover)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_handle_drag_start(mouse_event)
		elif not mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_handle_drag_end(mouse_event)

func _handle_drag_start(event: InputEventMouseButton) -> void:
	if audio_manager:
		audio_manager.play_ui_menu_selection()
	var clicked_control = get_viewport().gui_get_drag_data()
	if clicked_control and clicked_control is TextureRect:
		var item_data = clicked_control.get_meta("item_data", null)
		if item_data:
			selected_item = item_data
			drag_start_slot = clicked_control.get_meta("slot_type", "")
			drag_start_index = clicked_control.get_meta("slot_index", -1)
			
			# Create drag preview.
			var preview = TextureRect.new()
			preview.texture = clicked_control.texture
			preview.size = clicked_control.size
			clicked_control.set_drag_preview(preview)

func _handle_drag_end(event: InputEventMouseButton) -> void:
	if selected_item == null:
		return
	
	var target_control = get_viewport().gui_find_control(event.position)
	if target_control:
		var target_slot = target_control.get_meta("target_slot", "")
		var target_index = target_control.get_meta("target_index", -1)
		
		if target_slot != "" and _can_transfer_item(selected_item, target_slot, target_index):
			_transfer_item(selected_item, target_slot, target_index)
	
	selected_item = null
	drag_start_slot = ""
	drag_start_index = -1

func _can_transfer_item(item, target_slot: String, target_index: int) -> bool:
	if target_slot == "inventory":
		return inventory_system.get_free_slots() > 0
	elif target_slot == "equipment":
		return true  # Equipment slots can always be filled
	elif target_slot == "container":
		if current_container:
			return not current_container.is_full()
	elif target_slot == "quick":
		return target_index >= 0 and target_index < inventory_system.MaxQuickSlots
	
	return false

func _transfer_item(item, target_slot: String, target_index: int) -> void:
	if audio_manager:
		audio_manager.play_ui_click()
	match target_slot:
		"inventory":
			# Move from equipment/container to inventory.
			if drag_start_slot == "equipment":
				inventory_system.unequip_item(drag_start_slot)
				inventory_system.add_item(item)
			elif drag_start_slot == "container" and current_container:
				current_container.remove_item(item)
				inventory_system.add_item(item)
			elif drag_start_slot == "quick":
				inventory_system.set_quick_slot(null, drag_start_index)
				inventory_system.add_item(item)
				
		"equipment":
			# Move to equipment slot.
			if drag_start_slot == "inventory":
				inventory_system.remove_item(item)
				inventory_system.equip_item(item, "left_hand")  # Default to left hand
			elif drag_start_slot == "container" and current_container:
				current_container.remove_item(item)
				inventory_system.equip_item(item, "left_hand")
			elif drag_start_slot == "quick":
				inventory_system.set_quick_slot(null, drag_start_index)
				inventory_system.equip_item(item, "left_hand")
				
		"container":
			# Move to container.
			if drag_start_slot == "inventory":
				inventory_system.remove_item(item)
				if current_container:
					current_container.add_item(item)
			elif drag_start_slot == "equipment":
				inventory_system.unequip_item(drag_start_slot)
				if current_container:
					current_container.add_item(item)
			elif drag_start_slot == "quick":
				inventory_system.set_quick_slot(null, drag_start_index)
				if current_container:
					current_container.add_item(item)
					
		"quick":
			# Move to quick slot.
			if drag_start_slot == "inventory":
				inventory_system.remove_item(item)
				inventory_system.set_quick_slot(item, target_index)
			elif drag_start_slot == "equipment":
				inventory_system.unequip_item(drag_start_slot)
				inventory_system.set_quick_slot(item, target_index)
			elif drag_start_slot == "container" and current_container:
				current_container.remove_item(item)
				inventory_system.set_quick_slot(item, target_index)

func _update_inventory_display() -> void:
	# Clear existing inventory items.
	for child in inventory_grid.get_children():
		child.queue_free()
	
	# Add inventory items.
	var items = inventory_system.get_all_items()
	for i in range(items.size()):
		var item = items[i]
		var slot = _create_item_slot(item, "inventory", i)
		inventory_grid.add_child(slot)

func _update_equipment_display() -> void:
	# Clear existing equipment.
	for child in equipment_grid.get_children():
		child.queue_free()
	
	# Add equipment items.
	var equipment = inventory_system.get_equipped_items()
	for slot_name in equipment.keys():
		var item = equipment[slot_name]
		if item:
			var slot = _create_item_slot(item, "equipment", -1, slot_name)
			equipment_grid.add_child(slot)

func _update_container_display() -> void:
	if current_container == null:
		container_grid.clear()
		return
	
	# Clear existing container items.
	for child in container_grid.get_children():
		child.queue_free()
	
	# Add container items.
	var items = current_container.get_all_items()
	for i in range(items.size()):
		var item = items[i]
		var slot = _create_item_slot(item, "container", i)
		container_grid.add_child(slot)

func _create_item_slot(item, slot_type: String, slot_index: int, equipment_slot: String = "") -> TextureRect:
	var slot = TextureRect.new()
	slot.size = Vector2(64, 64)
	slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.tooltip_text = item.get_display_name()
	
	# Set texture.
	if item.icon:
		slot.texture = item.icon
	else:
		slot.texture = load("uid://pdxoqf3bvtwl")
	
	# Add metadata.
	slot.set_meta("item_data", item)
	slot.set_meta("slot_type", slot_type)
	slot.set_meta("slot_index", slot_index)
	if equipment_slot != "":
		slot.set_meta("equipment_slot", equipment_slot)
	
	# Connect signals.
	slot.connect("gui_input", _on_slot_input)
	
	return slot

func _on_slot_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			var slot = event.target as TextureRect
			var item = slot.get_meta("item_data")
			if item:
				_show_item_context_menu(item, mouse_event.position)

func _show_item_context_menu(item, position: Vector2) -> void:
	var menu = PopupMenu.new()
	add_child(menu)
	
	# Add common actions.
	menu.add_item("Use", 1)
	menu.add_item("Examine", 2)
	menu.add_item("Drop", 3)
	
	if inventory_system.get_left_hand_item() != item and inventory_system.get_right_hand_item() != item:
		menu.add_item("Equip", 4)
	
	menu.set_position(position)
	menu.connect("id_pressed", Callable(self, "_on_menu_item_selected").bind(item))
	menu.popup()

func _on_menu_item_selected(item, option_id: int) -> void:
	if audio_manager:
		audio_manager.play_ui_click()
	match option_id:
		1:  # Use
			item.use(inventory_system.owner)
		2:  # Examine
			var description = item.description if item.description else "No description available."
			inventory_system.owner.show_chat_bubble("[b]%s[/b]\n%s" % [item.get_display_name(), description])
		3:  # Drop
			var position = inventory_system.owner.position
			item.drop(position, inventory_system.owner)
		4:  # Equip
			inventory_system.equip_item(item, "left_hand")

func _on_item_added(_item, _slot_index: int) -> void:
	_update_inventory_display()
	_update_status()

func _on_item_removed(_item, _slot_index: int) -> void:
	_update_inventory_display()
	_update_status()

func _on_item_equipped(_item, _slot_name: String) -> void:
	_update_equipment_display()
	_update_status()

func _on_item_unequipped(_item, _slot_name: String) -> void:
	_update_equipment_display()
	_update_status()

func _on_inventory_updated() -> void:
	_update_inventory_display()
	_update_equipment_display()
	_update_container_display()
	_update_status()

func _update_status() -> void:
	if inventory_system:
		var weight_pct = inventory_system.get_weight_percentage()
		var free_slots = inventory_system.get_free_slots()
		var total_slots = inventory_system.MaxInventorySlots
		
		status_label.text = "Weight: %.1f%% | Slots: %d/%d" % [weight_pct, total_slots - free_slots, total_slots]

func open_container(container) -> void:
	if audio_manager:
		audio_manager.play_ui_click()
	current_container = container
	inventory_tab.set_current_tab(2)  # Switch to container tab
	_update_container_display()
	emit_signal("container_opened", container)

func close_container() -> void:
	if audio_manager:
		audio_manager.play_ui_close_menu()
	current_container = null
	_update_container_display()

func show_inventory() -> void:
	if audio_manager:
		audio_manager.play_ui_click()
	popup()
	_update_inventory_display()
	_update_equipment_display()
	_update_status()

func _on_button_hover() -> void:
	if audio_manager:
		audio_manager.play_ui_hover()
