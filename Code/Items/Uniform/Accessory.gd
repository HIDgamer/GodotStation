extends Item
class_name Accessory

@export var worn_accessory_slot: Clothing.AccessorySlot = Clothing.AccessorySlot.DEFAULT
@export var worn_accessory_limit: int = 1
@export var high_visibility: bool = false
@export var removable: bool = true
@export var original_item_path: String = ""

var attached_to = null

func _init():
	super._init()
	pickupable = true
	w_class = 1

func get_accessory_slot() -> Clothing.AccessorySlot:
	return worn_accessory_slot

func get_armor_bonus(armor_type: String) -> int:
	"""Override in specific accessories to provide armor bonuses"""
	return 0

func attack_self(user):
	"""Convert accessory back to regular clothing if possible"""
	if original_item_path != "":
		revert_to_clothing(user)
		return true
	
	return super.attack_self(user)

func revert_to_clothing(user):
	"""Convert accessory back to original clothing item"""
	if original_item_path == "":
		show_user_message(user, get_entity_name(self) + " cannot be reverted.")
		return
	
	var original_script = load(original_item_path)
	if not original_script:
		show_user_message(user, "Failed to revert " + get_entity_name(self) + ".")
		return
	
	var original_item = original_script.new()
	
	# Copy properties back
	original_item.name = name
	original_item.obj_name = obj_name
	original_item.description = description
	
	# Add to world/user
	var parent = get_parent()
	if attached_to:
		attached_to.remove_accessory(self)
	
	parent.add_child(original_item)
	original_item.global_position = global_position
	
	if user and user.has_method("put_in_hands"):
		user.put_in_hands(original_item)
	
	show_user_message(user, "You convert " + get_entity_name(self) + " back to normal clothing.")
	queue_free()

func update_overlay():
	"""Update visual overlay when attached to clothing"""
	# Override in specific accessories for custom overlay behavior
	pass
