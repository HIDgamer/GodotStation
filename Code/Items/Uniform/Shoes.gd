extends Clothing
class_name ClothingShoes

@export var stored_item_types: Array = [] # Types that can be stored in shoes
@export var spawn_item_type: String = ""
@export var shoes_blood_amt: float = 0.0

var stored_item = null

func _init():
	super._init()
	primary_slot = Slots.SHOES
	
	valid_slots = [Slots.SHOES]
	siemens_coefficient = 0.9
	blood_overlay_type = "feet"

func _ready():
	super._ready()
	
	# Spawn default item if specified
	if spawn_item_type != "":
		var item_scene = load(spawn_item_type)
		if item_scene:
			var item = item_scene.instantiate()
			_insert_item_direct(item)

func update_clothing_icon():
	if inventory_owner:
		if inventory_owner.has_method("update_inv_shoes"):
			inventory_owner.update_inv_shoes()

func can_store_shoe_item(item) -> bool:
	"""Check if an item can be stored in the shoes"""
	if stored_item:
		return false
	
	if stored_item_types.size() == 0:
		return false
	
	var item_script = item.get_script()
	for allowed_type in stored_item_types:
		var allowed_script = load(allowed_type)
		if item_script == allowed_script or item.is_class(allowed_type):
			return true
	
	return false

func store_shoe_item(item, user) -> bool:
	"""Store an item in the shoes"""
	if not can_store_shoe_item(item):
		return false
	
	if user and not user.has_method("drop_inv_item_to_loc"):
		return false
	
	if user and not user.drop_inv_item_to_loc(item, self):
		return false
	
	_insert_item_direct(item)
	show_user_message(user, "You slide " + get_entity_name(item) + " into " + get_entity_name(self) + ".")
	
	# Play sound
	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager:
		audio_manager.play_positioned_sound("item_insert", global_position, 0.3)
	
	return true

func retrieve_shoe_item(user) -> bool:
	"""Remove stored item from shoes"""
	if not stored_item:
		return false
	
	if user and user.has_method("put_in_hands") and user.put_in_hands(stored_item):
		show_user_message(user, "You slide " + get_entity_name(stored_item) + " out of " + get_entity_name(self) + ".")
		
		# Play sound
		var audio_manager = get_node_or_null("/root/AudioManager")
		if audio_manager:
			audio_manager.play_positioned_sound("item_remove", global_position, 0.3)
		
		stored_item = null
		update_appearance()
		return true
	
	return false

func _insert_item_direct(item):
	"""Insert item directly without checks"""
	stored_item = item
	add_child(item)
	item.position = Vector2.ZERO
	item.visible = false
	update_appearance()

func attackby(item, user, params = null) -> bool:
	"""Handle item interactions - try to store items"""
	if can_store_shoe_item(item):
		return store_shoe_item(item, user)
	
	return super.attackby(item, user, params)

func examine(examiner) -> String:
	var examine_text = super.examine(examiner)
	
	if stored_item:
		examine_text += " There is " + get_entity_name(stored_item) + " stored inside."
	
	return examine_text
