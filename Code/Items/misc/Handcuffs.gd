extends Item
class_name Handcuffs

# Handcuff-specific properties
var breakout_time: float = 600.0  # Time in seconds to break out (10 minutes default)
var breakoutable: bool = true     # Can be broken out of
var resist_strength_effect: float = 1.0  # How much strength affects breakout time

# Signals
signal resisted_against(user)  # Emitted when someone resists the cuffs

func _init():
	super._init()
	item_name = "handcuffs"
	description = "Restraints used to keep prisoners in line."
	obj_name = "handcuffs"
	obj_desc = "Used to keep prisoners in check."
	
	# Set valid equipment slots for handcuffs
	equip_slot_flags = Slots.LEFT_HAND | Slots.RIGHT_HAND
	
	# Handcuffs cause restraint status
	tool_behaviour = "restraining"
	w_class = 2  # Small item
	
	# Set force and attack properties
	force = 5
	attack_verb = ["restrains"]
	
	# Allow picking up
	pickupable = true

# Override equipped to handle being equipped as handcuffs
func equipped(user, slot: int):
	super.equipped(user, slot)
	
	# If equipped as handcuffs, not in hands
	if slot == InventorySystem.EquipSlot.HANDCUFFED:
		# Update the restraint state of the target
		if "is_restrained" in user:
			user.is_restrained = true
		
		# Connect resist signal
		if not self.is_connected("resisted_against", Callable(self, "_on_resisted_against")):
			user.connect("resist", Callable(self, "_on_resisted_against"))

# Override unequipped to handle being removed as handcuffs
func unequipped(user, slot: int):
	super.unequipped(user, slot)
	
	# If unequipped as handcuffs
	if slot == InventorySystem.EquipSlot.HANDCUFFED:
		# Update the restraint state of the target
		if "is_restrained" in user:
			user.is_restrained = false
		
		# Disconnect resist signal
		if user.is_connected("resist", Callable(self, "_on_resisted_against")):
			user.disconnect("resist", Callable(self, "_on_resisted_against"))

# Handle resist attempts
func _on_resisted_against(user):
	# Only process resist if we're actually being worn as handcuffs
	if current_slot != InventorySystem.EquipSlot.HANDCUFFED or not breakoutable:
		return
	
	# Get escape time based on user's strength
	var escape_time = breakout_time
	if "strength" in user:
		escape_time = escape_time / (1 + (user.strength * 0.01 * resist_strength_effect))
	
	# Show resist message
	if "visible_message" in user:
		user.visible_message("%s attempts to break out of %s!" % [user.name, item_name])
	
	# Start the resist timer
	await get_tree().create_timer(escape_time).timeout
	
	# Check if still being worn by same person
	if inventory_owner != user or current_slot != InventorySystem.EquipSlot.HANDCUFFED:
		return
	
	# Break free
	emit_signal("resisted_against", user)
	
	# Remove the cuffs
	if "update_handcuffed" in user:
		user.update_handcuffed(null)
	
	# Show success message
	if "visible_message" in user:
		user.visible_message("%s manages to break out of %s!" % [user.name, item_name])

# Use handcuffs on a target
func afterattack(target, user, proximity: bool, params: Dictionary = {}):
	if not proximity:
		return false
	
	# Can only use on humanoids
	if not "is_human" in target or not target.is_human:
		return false
	
	# Handcuff the target
	if "update_handcuffed" in target:
		# Start handcuffing process
		if "visible_message" in user:
			user.visible_message("%s is trying to put %s on %s!" % [user.name, item_name, target.name])
		
		# Delay to simulate handcuffing action
		await get_tree().create_timer(3.0).timeout
		
		# Add handcuffs to target
		target.update_handcuffed(self)
		
		# Show success message
		if "visible_message" in user:
			user.visible_message("%s has put %s on %s!" % [user.name, item_name, target.name])
		
		return true
	
	return false

# Register signal for living resistance
func register_signal(entity, signal_name, callback_method):
	if entity.has_signal(signal_name) and not entity.is_connected(signal_name, Callable(self, callback_method)):
		entity.connect(signal_name, Callable(self, callback_method))

# Unregister signal
func unregister_signal(entity, signal_name):
	if entity.has_signal(signal_name) and entity.is_connected(signal_name, Callable(self, "_on_resisted_against")):
		entity.disconnect(signal_name, Callable(self, "_on_resisted_against"))

# Extended serialization for handcuffs
func serialize():
	var data = super.serialize()
	data["breakout_time"] = breakout_time
	data["breakoutable"] = breakoutable
	data["resist_strength_effect"] = resist_strength_effect
	return data

func deserialize(data):
	super.deserialize(data)
	if "breakout_time" in data: breakout_time = data.breakout_time
	if "breakoutable" in data: breakoutable = data.breakoutable
	if "resist_strength_effect" in data: resist_strength_effect = data.resist_strength_effect
