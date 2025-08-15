extends Clothing
class_name Back

@export var wired: bool = false
@export var cell_path: String = ""

var cell_item = null

func _init():
	super._init()
	primary_slot = Slots.BACK
	
	blood_overlay_type = "uniform"
	
	valid_slots = [Slots.BACK]
	w_class = 5
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
