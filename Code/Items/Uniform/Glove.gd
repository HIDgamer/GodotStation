extends Clothing
class_name Gloves

@export var wired: bool = false
@export var cell_path: String = ""
@export var gloves_blood_amt: float = 0.0

var cell_item = null

func _init():
	super._init()
	primary_slot = Slots.GLOVES
	
	blood_overlay_type = "uniform"
	
	valid_slots = [Slots.GLOVES]
	w_class = 2  # SIZE_SMALL
	siemens_coefficient = 0.5
	attack_verb = ["challenged"]
	blood_overlay_type = "hands"
	valid_accessory_slots = AccessorySlot.WRIST_L | AccessorySlot.WRIST_R

func _ready():
	super._ready()
	
	# Initialize cell if specified
	if cell_path != "":
		var cell_scene = load(cell_path)
		if cell_scene:
			cell_item = cell_scene.instantiate()
			add_child(cell_item)

func update_clothing_icon():
	if inventory_owner:
		if inventory_owner.has_method("update_inv_gloves"):
			inventory_owner.update_inv_gloves()

func touch_interaction(target, user, proximity: bool) -> bool:
	"""Called before attack_hand interactions"""
	# Override this in specific glove types for special touch interactions
	return false

func emp_effect(severity: int):
	"""Handle EMP effects on electronic gloves"""
	if cell_item and cell_item.has_method("drain_charge"):
		var drain_amount = 1000.0 / severity
		cell_item.drain_charge(drain_amount)
		
		if cell_item.has_method("reduce_reliability"):
			if cell_item.reliability != 100 and randf() < (0.5 / severity):
				cell_item.reduce_reliability(10.0 / severity)
