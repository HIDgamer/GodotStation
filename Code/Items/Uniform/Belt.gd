extends Clothing
class_name Belt

@export var wired: bool = false
@export var cell_path: String = ""
@export var belts_blood_amt: float = 0.0

var cell_item = null

func _init():
	super._init()
	primary_slot = Slots.BELT
	
	blood_overlay_type = "uniform"
	
	valid_slots = [Slots.BELT]
	w_class = 2  # SIZE_SMALL
	siemens_coefficient = 0.5
	attack_verb = ["challenged"]
	blood_overlay_type = "hands"

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
