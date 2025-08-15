extends Clothing
class_name Uniform

@export var jumpsuit_storage: bool = false
@export var texture1: Texture2D
@export var texture2: Texture2D


func _init():
	super._init()
	
	primary_slot = Slots.W_UNIFORM
	
	blood_overlay_type = "uniform"
	
	valid_slots = [Slots.W_UNIFORM]
	
	if jumpsuit_storage:
		storage_slots = 2
		max_storage_space = 4

func _ready():
	super._ready()
	
	# Ensure equip_slot_flags is set correctly after parent initialization
	equip_slot_flags = get_slot_flag_for_slot(primary_slot)
	
	# Debug output to verify setup
	print("Uniform initialized:")
	print("  - primary_slot: ", primary_slot)
	print("  - equip_slot_flags: ", equip_slot_flags)
	print("  - valid_slots: ", valid_slots)

func update_clothing_icon():
	if inventory_owner:
		if inventory_owner.has_method("update_inv_under"):
			inventory_owner.update_inv_under()
		elif inventory_owner.has_method("update_inv_w_uniform"):
			inventory_owner.update_inv_w_uniform()

func can_equip(user, slot: int) -> bool:
	if slot != Slots.W_UNIFORM:
		return false
	return super.can_equip(user, slot)

func use(user):
	var sprite = get_node_or_null("Sprite")
	if not sprite:
		return
	if sprite.texture == texture1:
		sprite.texture = texture2
	else:
		sprite.texture = texture1
