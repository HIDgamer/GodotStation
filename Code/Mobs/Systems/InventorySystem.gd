extends Node
class_name InventorySystem

# =============================================================================
# Constants
# =============================================================================
# Clothing/Equipment Hide Flags
const HIDEFACE = 1
const HIDEALLHAIR = 2
const HIDETOPHAIR = 4
const HIDELOWHAIR = 8
const HIDEEARS = 16
const HIDEEYES = 32
const HIDEJUMPSUIT = 64
const HIDESHOES = 128
const HIDE_EXCESS_HAIR = 256

# =============================================================================
# Equipment Slots Enum
# =============================================================================
enum EquipSlot {
	NONE = 0,
	LEFT_HAND = 13,
	RIGHT_HAND = 14,
	BACK = 3,
	WEAR_MASK = 4,
	HANDCUFFED = 5,
	BELT = 15,
	WEAR_ID = 12,
	EARS = 8,
	GLASSES = 1,
	GLOVES = 8,
	HEAD = 0,
	SHOES = 10,
	WEAR_SUIT = 7,
	W_UNIFORM = 6,
	L_STORE = 15,
	R_STORE = 16,
	S_STORE = 17,
	ACCESSORY = 18,
	IN_BOOT = 20,
	IN_BACKPACK = 21,
	IN_SUIT = 22,
	IN_BELT = 23,
	IN_HEAD = 24,
	IN_ACCESSORY = 25,
	IN_HOLSTER = 26,
	IN_S_HOLSTER = 27,
	IN_B_HOLSTER = 28,
	IN_STORAGE = 29,
	IN_L_POUCH = 30,
	IN_R_POUCH = 31
}

# =============================================================================
# Bit-based slot flags (useful for checking multiple slots at once)
# =============================================================================
enum ItemSlotFlags {
	ITEM_SLOT_OCLOTHING = 1,      # Outer clothing (suit)
	ITEM_SLOT_ICLOTHING = 2,      # Inner clothing (uniform)
	ITEM_SLOT_GLOVES = 4,
	ITEM_SLOT_EYES = 8,
	ITEM_SLOT_EARS = 16,
	ITEM_SLOT_MASK = 32,
	ITEM_SLOT_HEAD = 64,
	ITEM_SLOT_FEET = 128,
	ITEM_SLOT_ID = 256,
	ITEM_SLOT_BELT = 512,
	ITEM_SLOT_BACK = 1024,
	ITEM_SLOT_R_POCKET = 2048,
	ITEM_SLOT_L_POCKET = 4096,
	ITEM_SLOT_SUITSTORE = 8192,
	ITEM_SLOT_HANDCUFF = 16384,
	ITEM_SLOT_L_HAND = 32768,
	ITEM_SLOT_R_HAND = 65536
}

# =============================================================================
# Item unequip return constants
# =============================================================================
const ITEM_UNEQUIP_FAIL = 0
const ITEM_UNEQUIP_DROPPED = 1
const ITEM_UNEQUIP_UNEQUIPPED = 2

# Item visibility constants
const ITEM_FLAG_IN_INVENTORY = 1

# =============================================================================
# Signals
# =============================================================================
signal inventory_updated()
signal item_equipped(item, slot)
signal item_unequipped(item, slot)
signal item_added(item, container)
signal item_removed(item, container)
signal active_hand_changed(new_hand)

# =============================================================================
# Debug settings
# =============================================================================
var debug_mode = true  # Set to true to enable debug logging
var verbose_logging = false

# =============================================================================
# Inventory data
# =============================================================================
# Reference to the entity this inventory belongs to
var entity = null

# Equipment slots
var equipped_items = {}

# Active hand (LEFT_HAND or RIGHT_HAND)
var active_hand = EquipSlot.RIGHT_HAND

# Visual effect hooks - NEW
var effect_proxies = {}  # Maps items to their effect proxies

# =============================================================================
# Item categorization
# =============================================================================
var gun_list = []
var melee_list = []
var ammo_list = []
var medical_list = []
var grenade_list = []
var engineering_list = []
var food_list = []

# Damage type specific item lists
var brute_list = []
var burn_list = []
var tox_list = []
var oxy_list = []
var clone_list = []
var pain_list = []

# =============================================================================
# Initialization
# =============================================================================
func _init(owner_entity = null):
	entity = owner_entity
	
	# Debug output
	if debug_mode:
		print("InventorySystem: Initialized with entity:", entity)
	
	# Initialize equipment slots
	for slot in EquipSlot.values():
		equipped_items[slot] = null

func _ready():
	if debug_mode:
		print("InventorySystem: _ready() called")
	
	# If we don't have a reference to the owner entity yet, try to get it from parent
	if entity == null:
		entity = get_parent()
		if debug_mode:
			print("InventorySystem: Got entity reference from parent:", entity)
	
	# Create effects container if not exists
	ensure_effects_container()

# =============================================================================
# Core equipping/unequipping functions
# =============================================================================
# Main function to equip an item to a slot
func equip_item(item, slot):
	if debug_mode:
		print("InventorySystem: equip_item() called for", item.name if item else "null", "to slot", slot)
	
	if not item:
		if debug_mode:
			print("InventorySystem: Cannot equip null item")
		return false
	
	# Check if the slot is valid for this item
	if not can_equip_to_slot(item, slot):
		if debug_mode:
			print("InventorySystem: Item cannot be equipped to slot", slot)
		return false
	
	# If something is already in this slot, unequip it
	var existing_item = equipped_items[slot]
	if existing_item:
		if debug_mode:
			print("InventorySystem: Unequipping existing item", existing_item.name)
		unequip_item(slot)
	
	# Put the item in the slot
	equipped_items[slot] = item
	
	# Now handle the item's visual and effect states
	
	# First, check if we need to preserve any visual effects
	var has_visual_effects = check_for_persistent_effects(item)
	
	# Store original parent for reference
	var original_parent = item.get_parent()
	
	# Remove the item from scene tree if it has a parent
	if original_parent:
		if debug_mode:
			print("InventorySystem: Removing item from parent", original_parent.name)
		original_parent.remove_child(item)
	
	# Add the item to the entity
	entity.add_child(item)
	
	# ENHANCED: Create effect proxy if item has persistent effects
	if has_visual_effects:
		create_effect_proxy(item, slot)
	else:
		# Standard behavior - just hide the item
		item.visible = false
	
	# ENHANCED: Verify item was added correctly
	if !item.get_parent() == entity:
		if debug_mode:
			print("InventorySystem ERROR: Item parent is not entity after add_child!")
			print("Item parent:", item.get_parent(), "Entity:", entity)
		
		# Force reparent as a fallback
		if item.get_parent():
			item.get_parent().remove_child(item)
		entity.call_deferred("add_child", item)
	
	# Set the IN_INVENTORY flag on the item
	if item.has_method("set_flag"):
		if debug_mode:
			print("InventorySystem: Setting IN_INVENTORY flag on item")
		item.set_flag("item_flags", item.ItemFlags.IN_INVENTORY, true)
	elif "item_flags" in item and "ItemFlags" in item:
		if debug_mode:
			print("InventorySystem: Setting item_flags directly")
		item.item_flags |= item.ItemFlags.IN_INVENTORY
	
	# Call equipped method on the item
	if item.has_method("equipped"):
		if debug_mode:
			print("InventorySystem: Calling item.equipped()")
		item.equipped(entity, slot)
	
	# Store last equipped slot for quick re-equipping
	if "last_equipped_slot" in item:
		item.last_equipped_slot = slot
	
	# Sort the item into category lists
	sort_item(item)
	
	# Update visuals based on slot
	update_slot_visuals(slot)
	
	# Emit signals
	emit_signal("item_equipped", item, slot)
	emit_signal("inventory_updated")
	
	if debug_mode:
		print("InventorySystem: Item successfully equipped")
	
	return true

# Enhanced method to check if an item has effects that should persist
func check_for_persistent_effects(item):
	# Check for common types of effects
	
	# Light effects
	var light = item.get_node_or_null("PointLight2D") 
	if light:
		return true
		
	# Particles
	var particles = item.get_node_or_null("GPUParticles2D")
	if particles:
		return true
		
	# Sound emitters
	var audio_player = item.get_node_or_null("AudioStreamPlayer2D")
	if audio_player:
		return true
	
	# Check for custom effect flag
	if "has_persistent_effects" in item and item.has_persistent_effects:
		return true
	
	# Check if item has registered methods for persistent effects
	if item.has_method("has_persistent_effects"):
		return item.has_persistent_effects()
	
	return false

# Create an effect proxy for items with persistent effects
func create_effect_proxy(item, slot):
	# First, check if we already have a proxy for this item
	if effect_proxies.has(item):
		return effect_proxies[item]
	
	# Get or create the effects container
	var effects_container = get_effects_container()
	
	# Create a new proxy node
	var proxy = Node2D.new()
	proxy.name = "EffectProxy_" + item.name
	effects_container.add_child(proxy)
	
	# Set proxy's position based on slot
	position_effect_proxy(proxy, slot)
	
	# Store the reference to the proxy
	effect_proxies[item] = proxy
	
	# Set up visuals for the proxy - copy the necessary parts
	setup_effect_proxy_visuals(item, proxy, slot)
	
	# Connect signals for updating
	if item.has_signal("effect_update"):
		if !item.is_connected("effect_update", Callable(self, "_on_item_effect_update")):
			item.connect("effect_update", Callable(self, "_on_item_effect_update").bind(item))
	
	# Make the actual item invisible but keep it processing
	# We want the item to continue functioning (processing) even though invisible
	item.visible = false
	
	# Store slot info in the proxy for later reference
	proxy.set_meta("slot", slot)
	proxy.set_meta("item", item)
	
	if debug_mode:
		print("InventorySystem: Created effect proxy for", item.name, "in slot", slot)
	
	return proxy

# Position the effect proxy based on the slot
func position_effect_proxy(proxy, slot):
	match slot:
		EquipSlot.LEFT_HAND:
			proxy.position = Vector2(-16, 0)  # Left of character
		EquipSlot.RIGHT_HAND:
			proxy.position = Vector2(16, 0)   # Right of character
		EquipSlot.BELT:
			proxy.position = Vector2(0, 16)   # At belt level
		EquipSlot.BACK:
			proxy.position = Vector2(0, -8)   # Behind character
		EquipSlot.HEAD:
			proxy.position = Vector2(0, -24)  # Above character
		_:
			proxy.position = Vector2.ZERO     # Default at character center

# Set up the proxy visuals
func setup_effect_proxy_visuals(item, proxy, slot):
	# Handle item-specific effects that should persist
	
	# Handle PointLight2D
	var light = item.get_node_or_null("PointLight2D")
	if light:
		var proxy_light = light.duplicate()
		proxy.add_child(proxy_light)
		proxy_light.enabled = light.enabled
		
		# Reference the original for state changes
		proxy_light.set_meta("original_light", light)
	
	# Handle particles
	var particles = item.get_node_or_null("GPUParticles2D")
	if particles:
		var proxy_particles = particles.duplicate()
		proxy.add_child(proxy_particles)
		proxy_particles.emitting = particles.emitting
		
		# Reference the original for state changes
		proxy_particles.set_meta("original_particles", particles)
	
	# Audio effects that may need to continue
	var audio_player = item.get_node_or_null("AudioStreamPlayer2D")
	if audio_player and audio_player.playing:
		var proxy_audio = audio_player.duplicate()
		proxy.add_child(proxy_audio)
		proxy_audio.stream = audio_player.stream
		proxy_audio.volume_db = audio_player.volume_db
		proxy_audio.playing = audio_player.playing
		
		# Reference the original for state changes
		proxy_audio.set_meta("original_audio", audio_player)
	
	# Call item's custom proxy setup if it has one
	if item.has_method("setup_effect_proxy"):
		item.setup_effect_proxy(proxy, slot)

# Ensure the effects container exists
func ensure_effects_container():
	if !entity.has_node("InventoryEffects"):
		var effects_container = Node2D.new()
		effects_container.name = "InventoryEffects"
		entity.add_child(effects_container)
		
		if debug_mode:
			print("InventorySystem: Created InventoryEffects container")

# Get the effects container
func get_effects_container():
	ensure_effects_container()
	return entity.get_node("InventoryEffects")

# Update proxy for an item when its effects change
func update_effect_proxy(item):
	if !effect_proxies.has(item):
		return
		
	var proxy = effect_proxies[item]
	var slot = proxy.get_meta("slot")
	
	# Update light effects
	var proxy_light = proxy.get_node_or_null("PointLight2D")
	var original_light = item.get_node_or_null("PointLight2D")
	
	if proxy_light and original_light:
		proxy_light.enabled = original_light.enabled
		proxy_light.color = original_light.color
		proxy_light.energy = original_light.energy
		proxy_light.texture = original_light.texture
	
	# Update particles
	var proxy_particles = proxy.get_node_or_null("GPUParticles2D")
	var original_particles = item.get_node_or_null("GPUParticles2D")
	
	if proxy_particles and original_particles:
		proxy_particles.emitting = original_particles.emitting
	
	# Update audio
	var proxy_audio = proxy.get_node_or_null("AudioStreamPlayer2D")
	var original_audio = item.get_node_or_null("AudioStreamPlayer2D")
	
	if proxy_audio and original_audio:
		proxy_audio.playing = original_audio.playing
		proxy_audio.stream = original_audio.stream
	
	# Call item's custom update if it has one
	if item.has_method("update_effect_proxy"):
		item.update_effect_proxy(proxy, slot)

# Signal handler for item effect updates
func _on_item_effect_update(item):
	update_effect_proxy(item)

# Remove a proxy when an item is unequipped
func remove_effect_proxy(item):
	if !effect_proxies.has(item):
		return
		
	var proxy = effect_proxies[item]
	
	# Optional: Fade out effects nicely
	fade_out_proxy(proxy)
	
	# Remove from dictionary
	effect_proxies.erase(item)

# Fade out a proxy's effects before removing
func fade_out_proxy(proxy):
	# Create a tween to fade out any visible effects
	var tween = create_tween()
	tween.tween_property(proxy, "modulate", Color(1, 1, 1, 0), 0.3)
	tween.tween_callback(proxy.queue_free)

# Unequip an item from a slot
func unequip_item(slot, force = false):
	if debug_mode:
		print("InventorySystem: unequip_item() called for slot", slot)
	
	var item = equipped_items[slot]
	
	if not item:
		if debug_mode:
			print("InventorySystem: No item in slot", slot)
		return ITEM_UNEQUIP_FAIL
	
	# Check if item can be unequipped
	if "trait_nodrop" in item and item.trait_nodrop and not force:
		if debug_mode:
			print("InventorySystem: Item has trait_nodrop, canceling unequip")
		return ITEM_UNEQUIP_FAIL
	
	# Call unequipped method on the item
	if item.has_method("unequipped"):
		if debug_mode:
			print("InventorySystem: Calling item.unequipped()")
		item.unequipped(entity, slot)
	
	# Clear the IN_INVENTORY flag
	if item.has_method("set_flag"):
		if debug_mode:
			print("InventorySystem: Clearing IN_INVENTORY flag")
		item.set_flag("item_flags", item.ItemFlags.IN_INVENTORY, false)
	elif "item_flags" in item and "ItemFlags" in item:
		if debug_mode:
			print("InventorySystem: Clearing item_flags directly")
		item.item_flags &= ~item.ItemFlags.IN_INVENTORY
	
	# Remove any effect proxy for this item
	if effect_proxies.has(item):
		remove_effect_proxy(item)
	
	# Remove item from slot
	equipped_items[slot] = null
	
	# Remove from categorized lists
	remove_from_lists(item)
	
	# Update visuals
	update_slot_visuals(slot)
	
	# Emit signals
	emit_signal("item_unequipped", item, slot)
	emit_signal("inventory_updated")
	
	if debug_mode:
		print("InventorySystem: Item successfully unequipped")
	
	return ITEM_UNEQUIP_UNEQUIPPED

# Drop an item from inventory
func drop_item(item_or_slot, direction = Vector2.DOWN, force = false):
	if debug_mode:
		print("InventorySystem: drop_item() called for", item_or_slot)
	
	var item = null
	var slot = EquipSlot.NONE
	
	# Check if we got an item reference or a slot number
	if typeof(item_or_slot) == TYPE_OBJECT:
		item = item_or_slot
		slot = get_item_slot(item)
	else:
		slot = item_or_slot
		item = equipped_items[slot]
	
	if not item:
		if debug_mode:
			print("InventorySystem: No item to drop")
		return ITEM_UNEQUIP_FAIL
	
	if slot == EquipSlot.NONE:
		if debug_mode:
			print("InventorySystem: Item not found in inventory")
		return ITEM_UNEQUIP_FAIL
	
	# Unequip the item
	var result = unequip_item(slot, force)
	if result != ITEM_UNEQUIP_UNEQUIPPED:
		if debug_mode:
			print("InventorySystem: Failed to unequip item")
		return result
	
	# Drop the item to the ground
	if item.get_parent():
		if debug_mode:
			print("InventorySystem: Removing item from parent", item.get_parent().name)
		item.get_parent().remove_child(item)
	
	# Add to world at entity's position
	var world = entity.get_parent()
	if debug_mode:
		print("InventorySystem: Adding item to world", world.name)
	
	world.add_child(item)
	
	# Set position and make sure item is visible
	item.global_position = entity.global_position
	item.visible = true
	
	# Add random offset
	item.position += Vector2(randf_range(-6, 6), randf_range(-6, 6))
	
	# FIXED: Ensure direction is always a Vector2
	var drop_direction = Vector2.DOWN
	if typeof(direction) == TYPE_VECTOR2:
		drop_direction = direction
	
	# Apply drop force if the item supports it
	if item.has_method("apply_drop_force"):
		item.apply_drop_force(drop_direction, 30.0)
	elif item.has_method("handle_drop"):
		item.handle_drop(entity)
	else:
		# Call dropped method on the item
		if item.has_method("dropped"):
			if debug_mode:
				print("InventorySystem: Calling item.dropped()")
			item.dropped(entity)
		else:
			if debug_mode:
				print("InventorySystem: Item doesn't have dropped() method")
	
	# Emit inventory updated to refresh UI
	emit_signal("inventory_updated")
	
	if debug_mode:
		print("InventorySystem: Item successfully dropped")
	
	return ITEM_UNEQUIP_DROPPED

# Drop the active item
func drop_active_item(force = false):
	if debug_mode:
		print("InventorySystem: drop_active_item() called")
	
	var item = get_active_item()
	if item:
		if debug_mode:
			print("InventorySystem: Dropping active item", item.name)
		return drop_item(item, force)
	
	if debug_mode:
		print("InventorySystem: No active item to drop")
	
	return ITEM_UNEQUIP_FAIL

# Find the slot containing an item
func get_item_slot(item):
	if debug_mode and verbose_logging:
		print("InventorySystem: get_item_slot() called for", item.name if item else "null")
	
	for slot in equipped_items:
		if equipped_items[slot] == item:
			if debug_mode and verbose_logging:
				print("InventorySystem: Found item in slot", slot)
			return slot
	
	if debug_mode and verbose_logging:
		print("InventorySystem: Item not found in any slot")
	
	return EquipSlot.NONE

# =============================================================================
# Accessing item methods
# =============================================================================
# Get the item in the active hand
func get_active_item():
	if debug_mode and verbose_logging:
		print("InventorySystem: get_active_item() called, active hand:", active_hand)
	
	return equipped_items[active_hand]

# Get the item in the inactive hand
func get_inactive_item():
	var inactive_hand = EquipSlot.LEFT_HAND if active_hand == EquipSlot.RIGHT_HAND else EquipSlot.RIGHT_HAND
	
	if debug_mode and verbose_logging:
		print("InventorySystem: get_inactive_item() called, inactive hand:", inactive_hand)
	
	return equipped_items[inactive_hand]

# Get the item in a specific slot
func get_item_in_slot(slot):
	if debug_mode and verbose_logging:
		print("InventorySystem: get_item_in_slot() called for slot", slot)
	
	if slot in equipped_items:
		return equipped_items[slot]
	return null

# Check if inventory has a specific item
func has_item(item):
	if debug_mode and verbose_logging:
		print("InventorySystem: has_item() called for", item.name if item else "null")
	
	if not item:
		return false
		
	# Check equipped slots first
	for slot in equipped_items:
		if equipped_items[slot] == item:
			if debug_mode and verbose_logging:
				print("InventorySystem: Item found in slot", slot)
			return true
	
	# Add this extra check for inconsistent state
	if "item_flags" in item and "ItemFlags" in item and "inventory_owner" in item:
		if (item.item_flags & item.ItemFlags.IN_INVENTORY) != 0 and item.inventory_owner == entity:
			if debug_mode:
				print("InventorySystem: Item has IN_INVENTORY flag but not found in slots - fixing state")
			# Clear the bad state since we didn't find it in any slot
			item.item_flags &= ~item.ItemFlags.IN_INVENTORY
			item.inventory_owner = null
	
	if debug_mode and verbose_logging:
		print("InventorySystem: Item not found in inventory")
	
	return false

# =============================================================================
# Hand management
# =============================================================================
# Switch the active hand
func switch_active_hand():
	if debug_mode:
		print("InventorySystem: switch_active_hand() called, current active hand:", active_hand)
	
	active_hand = EquipSlot.LEFT_HAND if active_hand == EquipSlot.RIGHT_HAND else EquipSlot.RIGHT_HAND
	
	if debug_mode:
		print("InventorySystem: New active hand:", active_hand)
	
	# Update proxies for hand items
	update_hand_proxies()
	
	emit_signal("active_hand_changed", active_hand)
	return active_hand

# Update the positions of hand item proxies when switching hands
func update_hand_proxies():
	var left_item = get_item_in_slot(EquipSlot.LEFT_HAND)
	var right_item = get_item_in_slot(EquipSlot.RIGHT_HAND)
	
	# Update left hand item proxy
	if left_item and effect_proxies.has(left_item):
		var proxy = effect_proxies[left_item]
		# Adjust position based on active state
		if active_hand == EquipSlot.LEFT_HAND:
			# Position for active left hand
			proxy.position = Vector2(-12, 0)
		else:
			# Position for inactive left hand
			proxy.position = Vector2(-16, 8)
	
	# Update right hand item proxy
	if right_item and effect_proxies.has(right_item):
		var proxy = effect_proxies[right_item]
		# Adjust position based on active state
		if active_hand == EquipSlot.RIGHT_HAND:
			# Position for active right hand
			proxy.position = Vector2(12, 0)
		else:
			# Position for inactive right hand
			proxy.position = Vector2(16, 8)

# Put an item in a specific hand
func put_in_hand(item, hand_slot = null):
	if debug_mode:
		print("InventorySystem: put_in_hand() called for", item.name if item else "null", "hand:", hand_slot if hand_slot else active_hand)
	
	if not hand_slot:
		hand_slot = active_hand
		
	if hand_slot != EquipSlot.LEFT_HAND and hand_slot != EquipSlot.RIGHT_HAND:
		if debug_mode:
			print("InventorySystem: Invalid hand slot:", hand_slot)
		return false
	
	# Check if item is already in inventory
	if has_item(item):
		if debug_mode:
			print("InventorySystem: Item is already in inventory, no need to put in hand")
		return true
		
	return equip_item(item, hand_slot)

# Try to put an item in the active hand, then inactive hand, then fail
func put_in_hands(item):
	if debug_mode:
		print("InventorySystem: put_in_hands() called for", item.name if item else "null")
	
	if not item:
		if debug_mode:
			print("InventorySystem: Cannot put null item in hands")
		return false
	
	# Check if the item is already in inventory
	if has_item(item):
		if debug_mode:
			print("InventorySystem: Item is already in inventory, no need to put in hands")
		return true
	
	# First try active hand
	if put_in_hand(item, active_hand):
		if debug_mode:
			print("InventorySystem: Successfully put item in active hand:", active_hand)
		return true
		
	# Try inactive hand if active hand failed
	var inactive_hand = EquipSlot.LEFT_HAND if active_hand == EquipSlot.RIGHT_HAND else EquipSlot.RIGHT_HAND
	if put_in_hand(item, inactive_hand):
		if debug_mode:
			print("InventorySystem: Successfully put item in inactive hand:", inactive_hand)
		return true
	
	if debug_mode:
		print("InventorySystem: Failed to put item in any hand")
	return false

# =============================================================================
# Item pickup and interaction
# =============================================================================
# Pick up an item and put it in hands
func pick_up_item(item):
	if debug_mode:
		print("InventorySystem: pick_up_item() called for", item.name if item else "null")
	
	if not item:
		if debug_mode:
			print("InventorySystem: Cannot pick up null item")
		return false
	
	# Check if the item is pickupable
	if "pickupable" in item:
		if not item.pickupable:
			if debug_mode:
				print("InventorySystem: Item is not pickupable")
			return false
	else:
		# If item doesn't have pickupable flag, set it to true by default
		if debug_mode:
			print("InventorySystem: Item doesn't have pickupable property, setting it automatically")
		item.set("pickupable", true)
	
	# ENHANCED: Sanity check for visuals
	if item.visible == false:
		if debug_mode:
			print("InventorySystem: Item is already invisible - likely already in inventory")
		
		# If it's already in our inventory, just return success
		if has_item(item):
			if debug_mode:
				print("InventorySystem: Item is already in this inventory")
			return true
			
		# If we got here, it might be in someone else's inventory but invisible
		item.visible = true
		if debug_mode:
			print("InventorySystem: Fixed item visibility state (was invisible but not in inventory)")
	
	# Check if the item is already in inventory
	if has_item(item):
		if debug_mode:
			print("InventorySystem: Item is already in inventory")
		return true
	
	# Check if item is already in someone else's inventory
	if "item_flags" in item and "ItemFlags" in item:
		var in_inventory = item.has_flag(item.item_flags, item.ItemFlags.IN_INVENTORY) if item.has_method("has_flag") else (item.item_flags & item.ItemFlags.IN_INVENTORY) != 0
		
		if in_inventory:
			if debug_mode:
				print("InventorySystem: Item has IN_INVENTORY flag but is not in this inventory - clearing flag")
			
			# Clear the flag and ownership since it's wrong
			if item.has_method("set_flag"):
				item.set_flag("item_flags", item.ItemFlags.IN_INVENTORY, false)
			else:
				item.item_flags &= ~item.ItemFlags.IN_INVENTORY
				
			# Also clear inventory_owner if it's set
			if "inventory_owner" in item and item.inventory_owner != null:
				if debug_mode:
					print("InventorySystem: Item has inventory_owner but not in inventory - clearing reference")
				item.inventory_owner = null
	
	# ENHANCED: Check hands to make sure we don't exceed capacity
	var left_hand_item = get_item_in_slot(EquipSlot.LEFT_HAND)
	var right_hand_item = get_item_in_slot(EquipSlot.RIGHT_HAND)
	
	# If both hands are full, reject the pickup
	if left_hand_item != null and right_hand_item != null:
		if debug_mode:
			print("InventorySystem: Both hands are full, cannot pick up item")
		return false
	
	# ENHANCED: Try to find best hand for item 
	var target_hand = active_hand
	
	# If active hand is full but inactive hand is empty, use inactive hand
	if get_item_in_slot(active_hand) != null:
		var inactive_hand = EquipSlot.LEFT_HAND if active_hand == EquipSlot.RIGHT_HAND else EquipSlot.RIGHT_HAND
		if get_item_in_slot(inactive_hand) == null:
			target_hand = inactive_hand
			if debug_mode:
				print("InventorySystem: Active hand full, using inactive hand:", target_hand)
	
	# Try to put the item in the target hand
	var success = put_in_hand(item, target_hand)
	
	if success:
		if debug_mode:
			print("InventorySystem: Successfully put item in hand:", target_hand)
		
		# Call picked_up method on the item
		if item.has_method("picked_up"):
			if debug_mode:
				print("InventorySystem: Calling item.picked_up()")
			item.picked_up(entity)
		
		# Make sure to update everything
		emit_signal("inventory_updated")
		
		# Now that we have the item, make sure it's properly added to the entity
		if not item.get_parent() == entity:
			if item.get_parent():
				item.get_parent().remove_child(item)
			entity.add_child(item)
		
		if debug_mode:
			print("InventorySystem: Item pickup complete and successful")
		
		return true
	else:
		if debug_mode:
			print("InventorySystem: Failed to put item in hands")
		return false

func find_empty_slot() -> int:
	# Check some common equipment slots
	var slots_to_check = [
		EquipSlot.BELT,
		EquipSlot.BACK,
		EquipSlot.S_STORE,
		EquipSlot.L_STORE,
		EquipSlot.R_STORE
	]
	
	for slot in slots_to_check:
		if equipped_items[slot] == null:
			return slot
	
	return EquipSlot.NONE

# Use the active item
func use_active_item():
	if debug_mode:
		print("InventorySystem: use_active_item() called")
	
	var item = get_active_item()
	if !item:
		if debug_mode:
			print("InventorySystem: No active item to use")
		return false
	
	if debug_mode:
		print("InventorySystem: Using active item:", item.name)
	
	# ENHANCED: Check multiple use methods in order of preference
	var used = false
	
	# Try the standard use method first
	if item.has_method("use"):
		if debug_mode:
			print("InventorySystem: Calling item.use()")
			used = await item.use(entity)
	elif item.has_method("interact"):
		if debug_mode:
			print("InventorySystem: Calling item.interact()")
			used = await item.interact(entity)
	elif item.has_method("attack_self"):
		if debug_mode:
			print("InventorySystem: Calling item.attack_self()")
			used = await item.attack_self(entity)
	else:
		if debug_mode:
			print("InventorySystem: Item doesn't have use/interact/attack_self methods")
	
	# Emit item used signal regardless (for animation/sound)
	if item.has_signal("used"):
		item.emit_signal("used", entity)
	
	# Update any effect proxies after use
	if effect_proxies.has(item):
		update_effect_proxy(item)
	
	# Always emit inventory_updated to ensure UI refreshes
	emit_signal("inventory_updated")
	
	return used

# Remove an item from inventory without dropping it
func remove_item(item):
	if debug_mode:
		print("InventorySystem: remove_item() called for", item.name if item else "null")
	
	if not item:
		if debug_mode:
			print("InventorySystem: Cannot remove null item")
		return false
	
	# Find which slot the item is in
	var slot = get_item_slot(item)
	if slot == EquipSlot.NONE:
		if debug_mode:
			print("InventorySystem: Item not found in inventory")
		return false
	
	# Unequip the item
	var result = unequip_item(slot)
	
	# Remove from parent if it has one
	if item.get_parent():
		item.get_parent().remove_child(item)
	
	if debug_mode:
		print("InventorySystem: Item removed successfully, result:", result)
	
	return result == ITEM_UNEQUIP_UNEQUIPPED

# =============================================================================
# Equipment validation
# =============================================================================
# Check if an item can be equipped to a slot
func can_equip_to_slot(item, slot):
	if debug_mode:
		print("InventorySystem: can_equip_to_slot() called for", item.name if item else "null", "to slot", slot)
	
	if not item:
		if debug_mode:
			print("InventorySystem: Cannot equip null item")
		return false
	
	# Check if the entity has the limbs for this slot
	if entity.has_method("has_limb_for_slot"):
		if not entity.has_limb_for_slot(slot):
			if debug_mode:
				print("InventorySystem: Entity doesn't have required limb for slot", slot)
			return false
	
	# Special case for hand slots and pickupable items
	if (slot == EquipSlot.LEFT_HAND or slot == EquipSlot.RIGHT_HAND) and "pickupable" in item and item.pickupable:
		if debug_mode:
			print("InventorySystem: Item is pickupable, allowing equip to hand slot regardless of flags")
		return true
	
	# Check if the item has slot restrictions
	if "valid_slots" in item and item.valid_slots is Array:
		if not slot in item.valid_slots:
			if debug_mode:
				print("InventorySystem: Slot", slot, "not in item's valid_slots:", item.valid_slots)
			return false
	
	# Check if the item has slot bit restrictions
	if "equip_slot_flags" in item:
		var slot_bit = get_slot_bit(slot)
		if slot_bit != 0 and (item.equip_slot_flags & slot_bit) == 0:
			if debug_mode:
				print("InventorySystem: Slot bit", slot_bit, "not in item's equip_slot_flags:", item.equip_slot_flags)
			return false
	
	if debug_mode:
		print("InventorySystem: Item can be equipped to slot", slot)
	
	return true


# Get the slot bit for a slot enum
func get_slot_bit(slot):
	match slot:
		EquipSlot.WEAR_SUIT:
			return ItemSlotFlags.ITEM_SLOT_OCLOTHING
		EquipSlot.W_UNIFORM:
			return ItemSlotFlags.ITEM_SLOT_ICLOTHING
		EquipSlot.GLOVES:
			return ItemSlotFlags.ITEM_SLOT_GLOVES
		EquipSlot.GLASSES:
			return ItemSlotFlags.ITEM_SLOT_EYES
		EquipSlot.EARS:
			return ItemSlotFlags.ITEM_SLOT_EARS
		EquipSlot.WEAR_MASK:
			return ItemSlotFlags.ITEM_SLOT_MASK
		EquipSlot.HEAD:
			return ItemSlotFlags.ITEM_SLOT_HEAD
		EquipSlot.SHOES:
			return ItemSlotFlags.ITEM_SLOT_FEET
		EquipSlot.WEAR_ID:
			return ItemSlotFlags.ITEM_SLOT_ID
		EquipSlot.BELT:
			return ItemSlotFlags.ITEM_SLOT_BELT
		EquipSlot.BACK:
			return ItemSlotFlags.ITEM_SLOT_BACK
		EquipSlot.R_STORE:
			return ItemSlotFlags.ITEM_SLOT_R_POCKET
		EquipSlot.L_STORE:
			return ItemSlotFlags.ITEM_SLOT_L_POCKET
		EquipSlot.S_STORE:
			return ItemSlotFlags.ITEM_SLOT_SUITSTORE
		EquipSlot.HANDCUFFED:
			return ItemSlotFlags.ITEM_SLOT_HANDCUFF
		EquipSlot.LEFT_HAND:
			return ItemSlotFlags.ITEM_SLOT_L_HAND
		EquipSlot.RIGHT_HAND:
			return ItemSlotFlags.ITEM_SLOT_R_HAND
	return 0

# Convert between slot enums and bit flags
func slotbit2slotdefine(slot_bit):
	match slot_bit:
		ItemSlotFlags.ITEM_SLOT_OCLOTHING:
			return EquipSlot.WEAR_SUIT
		ItemSlotFlags.ITEM_SLOT_ICLOTHING:
			return EquipSlot.W_UNIFORM
		ItemSlotFlags.ITEM_SLOT_GLOVES:
			return EquipSlot.GLOVES
		ItemSlotFlags.ITEM_SLOT_EYES:
			return EquipSlot.GLASSES
		ItemSlotFlags.ITEM_SLOT_EARS:
			return EquipSlot.EARS
		ItemSlotFlags.ITEM_SLOT_MASK:
			return EquipSlot.WEAR_MASK
		ItemSlotFlags.ITEM_SLOT_HEAD:
			return EquipSlot.HEAD
		ItemSlotFlags.ITEM_SLOT_FEET:
			return EquipSlot.SHOES
		ItemSlotFlags.ITEM_SLOT_ID:
			return EquipSlot.WEAR_ID
		ItemSlotFlags.ITEM_SLOT_BELT:
			return EquipSlot.BELT
		ItemSlotFlags.ITEM_SLOT_BACK:
			return EquipSlot.BACK
		ItemSlotFlags.ITEM_SLOT_R_POCKET:
			return EquipSlot.R_STORE
		ItemSlotFlags.ITEM_SLOT_L_POCKET:
			return EquipSlot.L_STORE
		ItemSlotFlags.ITEM_SLOT_SUITSTORE:
			return EquipSlot.S_STORE
		ItemSlotFlags.ITEM_SLOT_HANDCUFF:
			return EquipSlot.HANDCUFFED
		ItemSlotFlags.ITEM_SLOT_L_HAND:
			return EquipSlot.LEFT_HAND
		ItemSlotFlags.ITEM_SLOT_R_HAND:
			return EquipSlot.RIGHT_HAND
	return EquipSlot.NONE

# =============================================================================
# Visual Updates
# =============================================================================
# Update visuals for a specific slot
func update_slot_visuals(slot):
	if debug_mode and verbose_logging:
		print("InventorySystem: update_slot_visuals() called for slot", slot)
	
	# Special handling for mask updates
	if slot == EquipSlot.WEAR_MASK:
		wear_mask_update(equipped_items[slot])
	
	if not entity:
		if debug_mode:
			print("InventorySystem: No entity reference for visual updates")
		return
	
	match slot:
		EquipSlot.BACK:
			if entity.has_method("update_inv_back"):
				entity.update_inv_back()
		EquipSlot.WEAR_MASK:
			if entity.has_method("update_inv_wear_mask"):
				entity.update_inv_wear_mask()
		EquipSlot.HANDCUFFED:
			if entity.has_method("update_inv_handcuffed"):
				entity.update_inv_handcuffed()
		EquipSlot.BELT:
			if entity.has_method("update_inv_belt"):
				entity.update_inv_belt()
		EquipSlot.WEAR_ID:
			if entity.has_method("update_inv_wear_id"):
				entity.update_inv_wear_id()
				if entity.has_method("get_visible_name"):
					entity.name = entity.get_visible_name()
		EquipSlot.EARS:
			if entity.has_method("update_inv_ears"):
				entity.update_inv_ears()
		EquipSlot.GLASSES:
			if entity.has_method("update_inv_glasses"):
				entity.update_inv_glasses()
		EquipSlot.GLOVES:
			if entity.has_method("update_inv_gloves"):
				entity.update_inv_gloves()
		EquipSlot.HEAD:
			if entity.has_method("update_inv_head"):
				entity.update_inv_head()
				# Update name if head covers face
				var item = equipped_items[EquipSlot.HEAD]
				if item and "inv_hide_flags" in item and item.inv_hide_flags & HIDEFACE:
					if entity.has_method("get_visible_name"):
						entity.name = entity.get_visible_name()
		EquipSlot.SHOES:
			if entity.has_method("update_inv_shoes"):
				entity.update_inv_shoes()
		EquipSlot.WEAR_SUIT:
			if entity.has_method("update_inv_wear_suit"):
				entity.update_inv_wear_suit()
				# Update other slots that might be hidden by suit
				var item = equipped_items[EquipSlot.WEAR_SUIT]
				if item and "inv_hide_flags" in item:
					if item.inv_hide_flags & HIDESHOES:
						if entity.has_method("update_inv_shoes"):
							entity.update_inv_shoes()
					if item.inv_hide_flags & HIDEJUMPSUIT:
						if entity.has_method("update_inv_w_uniform"):
							entity.update_inv_w_uniform()
		EquipSlot.W_UNIFORM:
			if entity.has_method("update_inv_w_uniform"):
				entity.update_inv_w_uniform()
		EquipSlot.L_STORE, EquipSlot.R_STORE:
			if entity.has_method("update_inv_pockets"):
				entity.update_inv_pockets()
		EquipSlot.S_STORE:
			if entity.has_method("update_inv_s_store"):
				entity.update_inv_s_store()
		EquipSlot.LEFT_HAND:
			if entity.has_method("update_inv_l_hand"):
				entity.update_inv_l_hand()
		EquipSlot.RIGHT_HAND:
			if entity.has_method("update_inv_r_hand"):
				entity.update_inv_r_hand()

# Update all slot visuals
func update_all_slots():
	if debug_mode:
		print("InventorySystem: update_all_slots() called")
	
	for slot in equipped_items:
		update_slot_visuals(slot)

# Handle mask updates
func wear_mask_update(item, equipping = false):
	if debug_mode and verbose_logging:
		print("InventorySystem: wear_mask_update() called")
	
	# Update mask visuals
	if entity.has_method("update_inv_wear_mask"):
		entity.update_inv_wear_mask()
	
	# Check if mask hides parts of the body and update accordingly
	if item and "inv_hide_flags" in item:
		if item.inv_hide_flags & HIDEFACE:
			if entity.has_method("get_visible_name"):
				entity.name = entity.get_visible_name()
				
		if item.inv_hide_flags & (HIDEALLHAIR|HIDETOPHAIR|HIDELOWHAIR):
			if entity.has_method("update_hair"):
				entity.update_hair()
				
		if item.inv_hide_flags & HIDEEARS:
			if entity.has_method("update_inv_ears"):
				entity.update_inv_ears()
				
		if item.inv_hide_flags & HIDEEYES:
			if entity.has_method("update_inv_glasses"):
				entity.update_inv_glasses()

# =============================================================================
# Item categorization
# =============================================================================
# Sort an item into appropriate category lists
func sort_item(item):
	if debug_mode and verbose_logging:
		print("InventorySystem: sort_item() called for", item.name if item else "null")
	
	if not item:
		return
		
	# First check for item_type property
	if "item_type" in item:
		match item.item_type:
			"gun":
				if not item in gun_list:
					gun_list.append(item)
			"melee":
				if not item in melee_list:
					melee_list.append(item)
			"ammo":
				if not item in ammo_list:
					ammo_list.append(item)
			"medical":
				if not item in medical_list:
					medical_list.append(item)
				sort_medical_item(item)
			"grenade":
				if not item in grenade_list:
					grenade_list.append(item)
			"engineering":
				if not item in engineering_list:
					engineering_list.append(item)
			"food":
				if not item in food_list:
					food_list.append(item)
	
	# Check for more specific types
	if "force" in item and item.force > 0:
		if not item in melee_list:
			melee_list.append(item)
	
	# Connect signals
	if item.has_signal("picked_up") and not item.is_connected("picked_up", Callable(self, "_on_item_picked_up")):
		item.connect("picked_up", Callable(self, "_on_item_picked_up"))
		
	if item.has_signal("dropped") and not item.is_connected("dropped", Callable(self, "_on_item_dropped")):
		item.connect("dropped", Callable(self, "_on_item_dropped"))
		
	# NEW: Connect effect update signal if it exists
	if item.has_signal("effect_update") and not item.is_connected("effect_update", Callable(self, "_on_item_effect_update")):
		item.connect("effect_update", Callable(self, "_on_item_effect_update").bind(item))

# Remove an item from all category lists
func remove_from_lists(item):
	if debug_mode and verbose_logging:
		print("InventorySystem: remove_from_lists() called for", item.name if item else "null")
	
	if not item:
		return
		
	if item in gun_list:
		gun_list.erase(item)
	if item in melee_list:
		melee_list.erase(item)
	if item in ammo_list:
		ammo_list.erase(item)
	if item in medical_list:
		medical_list.erase(item)
	if item in grenade_list:
		grenade_list.erase(item)
	if item in engineering_list:
		engineering_list.erase(item)
	if item in food_list:
		food_list.erase(item)
		
	# Remove from damage type lists
	if item in brute_list:
		brute_list.erase(item)
	if item in burn_list:
		burn_list.erase(item)
	if item in tox_list:
		tox_list.erase(item)
	if item in oxy_list:
		oxy_list.erase(item)
	if item in clone_list:
		clone_list.erase(item)
	if item in pain_list:
		pain_list.erase(item)
		
	# Disconnect signals
	if item.has_signal("picked_up") and item.is_connected("picked_up", Callable(self, "_on_item_picked_up")):
		item.disconnect("picked_up", Callable(self, "_on_item_picked_up"))
		
	if item.has_signal("dropped") and item.is_connected("dropped", Callable(self, "_on_item_dropped")):
		item.disconnect("dropped", Callable(self, "_on_item_dropped"))
		
	# NEW: Disconnect effect update signal
	if item.has_signal("effect_update") and item.is_connected("effect_update", Callable(self, "_on_item_effect_update")):
		item.disconnect("effect_update", Callable(self, "_on_item_effect_update"))

# Sort medical items by treatment type
func sort_medical_item(item):
	if not "damage_types" in item:
		return
		
	for damage_type in item.damage_types:
		match damage_type:
			"brute":
				if not item in brute_list:
					brute_list.append(item)
			"burn":
				if not item in burn_list:
					burn_list.append(item)
			"tox":
				if not item in tox_list:
					tox_list.append(item)
			"oxy":
				if not item in oxy_list:
					oxy_list.append(item)
			"clone":
				if not item in clone_list:
					clone_list.append(item)
			"pain":
				if not item in pain_list:
					pain_list.append(item)

# =============================================================================
# Signal handlers
# =============================================================================
func _on_item_picked_up(user):
	if debug_mode:
		print("InventorySystem: _on_item_picked_up() signal received")
	emit_signal("inventory_updated")

func _on_item_dropped(user):
	if debug_mode:
		print("InventorySystem: _on_item_dropped() signal received")
	emit_signal("inventory_updated")

# =============================================================================
# Special handling for specific slots
# =============================================================================
# Update handcuffed state
func update_handcuffed(restraints):
	if restraints:
		# Drop all held items
		drop_item(get_item_in_slot(EquipSlot.LEFT_HAND))
		drop_item(get_item_in_slot(EquipSlot.RIGHT_HAND))
		
		# Stop pulling (assuming GridMovementController handles this)
		if entity.has_method("stop_pulling"):
			entity.stop_pulling()
		
		# Set handcuffed item
		equipped_items[EquipSlot.HANDCUFFED] = restraints
		
		# Call equipped method on restraints
		if restraints.has_method("equipped"):
			restraints.equipped(entity, EquipSlot.HANDCUFFED)
			
		if restraints.has_method("register_signal"):
			restraints.register_signal(entity, "resist", "resisted_against")
	else:
		var handcuffs = equipped_items[EquipSlot.HANDCUFFED]
		if handcuffs:
			# Unregister signals first
			if handcuffs.has_method("unregister_signal"):
				handcuffs.unregister_signal(entity, "resist")
			
			# Call unequipped method
			if handcuffs.has_method("unequipped"):
				handcuffs.unequipped(entity, EquipSlot.HANDCUFFED)
			
			# Remove handcuffs
			equipped_items[EquipSlot.HANDCUFFED] = null
	
	# Update visuals
	if entity.has_method("update_inv_handcuffed"):
		entity.update_inv_handcuffed()

# =============================================================================
# Inventory Content Access
# =============================================================================
# Get all equipped items
func get_equipped_items(include_pockets = false):
	var items = []
	for slot in equipped_items:
		# Skip hands
		if slot == EquipSlot.LEFT_HAND or slot == EquipSlot.RIGHT_HAND:
			continue
			
		# Skip pockets if not requested
		if not include_pockets and (slot == EquipSlot.L_STORE or slot == EquipSlot.R_STORE or slot == EquipSlot.S_STORE):
			continue
			
		var item = equipped_items[slot]
		if item:
			items.append(item)
	
	return items

# Get all items, including those in hands
func get_all_items():
	var items = get_equipped_items(true)
	
	# Add hand items
	var left_hand = equipped_items[EquipSlot.LEFT_HAND]
	var right_hand = equipped_items[EquipSlot.RIGHT_HAND]
	
	if left_hand:
		items.append(left_hand)
	if right_hand:
		items.append(right_hand)
		
	return items

# Get all items, including those stored in containers
func get_all_contents():
	var all_items = get_all_items()
	
	# Add items in containers
	var items_to_check = all_items.duplicate()
	while items_to_check.size() > 0:
		var item = items_to_check.pop_front()
		
		# Check if item has storage and add its contents
		if "storage_datum" in item and item.storage_datum:
			for content in item.contents:
				all_items.append(content)
				items_to_check.append(content)
	
	return all_items

# Helper for equipping to appropriate slot
func equip_to_appropriate_slot(item):
	# Get valid slots for this item
	var valid_slots = []
	
	# Check equip_slot_flags if available
	if "equip_slot_flags" in item:
		for slot in EquipSlot.values():
			var slot_bit = get_slot_bit(slot)
			if slot_bit != 0 and (item.equip_slot_flags & slot_bit) != 0:
				valid_slots.append(slot)
	# Or use valid_slots property if available
	elif "valid_slots" in item and item.valid_slots is Array:
		valid_slots = item.valid_slots
	# Or try last_equipped_slot
	elif "last_equipped_slot" in item and item.last_equipped_slot != EquipSlot.NONE:
		valid_slots = [item.last_equipped_slot]
	
	# Try to equip to each slot
	for slot in valid_slots:
		if equip_item(item, slot):
			return true
	
	return false

# =============================================================================
# Serialization for saving/loading
# =============================================================================
func serialize():
	var data = {
		"active_hand": active_hand,
		"equipped_items": {}
	}
	
	# Store equipped items
	for slot in equipped_items:
		var item = equipped_items[slot]
		if item and item.has_method("serialize"):
			data["equipped_items"][slot] = {
				"path": item.scene_file_path if item.scene_file_path else item.get_class(),
				"data": item.serialize()
			}
	
	return data

func deserialize(data):
	# Restore active hand
	if "active_hand" in data:
		active_hand = data["active_hand"]
	
	# Restore equipped items
	if "equipped_items" in data:
		for slot_str in data["equipped_items"]:
			var slot = int(slot_str)
			var item_data = data["equipped_items"][slot_str]
			
			# Create the item
			var item_scene = load(item_data["path"])
			if item_scene:
				var item = item_scene.instantiate()
				
				# Restore item data
				if item.has_method("deserialize"):
					item.deserialize(item_data["data"])
				
				# Equip the item
				equip_item(item, slot)
	
	# Update all slots
	update_all_slots()
	emit_signal("inventory_updated")

# =============================================================================
# Throw-related functions
# =============================================================================
func throw_item(item, direction, force = 1.0):
	# Find which slot the item is in
	var slot = get_item_slot(item)
	if slot == EquipSlot.NONE:
		return false
	
	# Unequip the item
	var result = unequip_item(slot)
	if result != ITEM_UNEQUIP_UNEQUIPPED:
		return false
	
	# Add item to world
	if item.get_parent():
		item.get_parent().remove_child(item)
		
	entity.get_parent().add_child(item)
	item.global_position = entity.global_position
	item.visible = true
	
	# Call thrown method on item
	if item.has_method("throw") and item.has_method("throw"):
		item.throw(entity, direction)
	elif item.has_method("handle_throw"):
		item.handle_throw(entity, direction, force)
	elif item.has_method("thrown"):
		item.thrown(entity, direction)
	
	# Apply force in throw direction
	if "linear_velocity" in item:
		item.linear_velocity = direction * force * 500  # Adjust multiplier as needed
	
	return true

# =============================================================================
# Integration with GridMovementController
# =============================================================================
func connect_to_grid_controller():
	var grid_controller = entity
	if grid_controller:
		# Connect grid controller signals to inventory system
		if grid_controller.has_signal("item_picked_up") and not grid_controller.is_connected("item_picked_up", Callable(self, "_on_grid_item_picked_up")):
			grid_controller.connect("item_picked_up", Callable(self, "_on_grid_item_picked_up"))
			
		if grid_controller.has_signal("dropped_item") and not grid_controller.is_connected("dropped_item", Callable(self, "_on_grid_dropped_item")):
			grid_controller.connect("dropped_item", Callable(self, "_on_grid_dropped_item"))
			
		if grid_controller.has_signal("active_hand_changed") and not grid_controller.is_connected("active_hand_changed", Callable(self, "_on_grid_active_hand_changed")):
			grid_controller.connect("active_hand_changed", Callable(self, "_on_grid_active_hand_changed"))
		
		# Connect inventory signals to grid controller
		if not self.is_connected("inventory_updated", Callable(grid_controller, "_on_inventory_updated")):
			self.connect("inventory_updated", Callable(grid_controller, "_on_inventory_updated"))
			
		if not self.is_connected("item_equipped", Callable(grid_controller, "_on_item_equipped")):
			self.connect("item_equipped", Callable(grid_controller, "_on_item_equipped"))
			
		if not self.is_connected("item_unequipped", Callable(grid_controller, "_on_item_unequipped")):
			self.connect("item_unequipped", Callable(grid_controller, "_on_item_unequipped"))

# Grid controller signal handlers
func _on_grid_item_picked_up(item):
	pick_up_item(item)

func _on_grid_dropped_item(item):
	drop_item(item)

func _on_grid_active_hand_changed(hand_index):
	var new_hand = EquipSlot.LEFT_HAND if hand_index == 1 else EquipSlot.RIGHT_HAND
	if active_hand != new_hand:
		active_hand = new_hand
		emit_signal("active_hand_changed", active_hand)

# =============================================================================
# Debug Functions
# =============================================================================
# Toggle debug mode
func set_debug_mode(enable: bool):
	debug_mode = enable
	print("InventorySystem: Debug mode", "enabled" if enable else "disabled")

# Toggle verbose logging
func set_verbose_logging(enable: bool):
	verbose_logging = enable
	print("InventorySystem: Verbose logging", "enabled" if enable else "disabled")

# Print inventory contents
func debug_print_inventory():
	if !debug_mode:
		return
		
	print("\n=== INVENTORY CONTENTS ===")
	
	for slot in equipped_items:
		var item = equipped_items[slot]
		if item:
			print("Slot ", slot, ": ", item.name)
		else:
			print("Slot ", slot, ": Empty")
	
	print("Active hand: ", active_hand)
	print("Active item: ", get_active_item())
	print("=========================\n")

func check_item_flag(item, flag_name, flag_bit):
	if item == null:
		return false
		
	if item.has_method("has_flag"):
		return item.has_flag(item.get(flag_name), flag_bit)
	elif flag_name in item and typeof(item.get(flag_name)) == TYPE_INT:
		return (item.get(flag_name) & flag_bit) != 0
	
	return false

# =============================================================================
# Physics process for updating proxy effects
# =============================================================================
func _physics_process(delta):
	# Update effect proxies that need continuous updating
	for item in effect_proxies:
		var proxy = effect_proxies[item]
		
		# Check if the item has a method for continuous effects
		if item.has_method("update_effects"):
			item.update_effects(delta, proxy)
		
		# Or if the proxy has specific nodes that need updating
		update_proxy_components(proxy, item)

# Update individual proxy components that might need synchronization
func update_proxy_components(proxy, item):
	# Update light parameters if both exist
	var proxy_light = proxy.get_node_or_null("PointLight2D")
	var item_light = item.get_node_or_null("PointLight2D")
	
	if proxy_light and item_light:
		proxy_light.enabled = item_light.enabled
		proxy_light.energy = item_light.energy
		proxy_light.color = item_light.color
	
	# Update particles if both exist
	var proxy_particles = proxy.get_node_or_null("GPUParticles2D")
	var item_particles = item.get_node_or_null("GPUParticles2D")
	
	if proxy_particles and item_particles:
		proxy_particles.emitting = item_particles.emitting
