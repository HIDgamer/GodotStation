extends Item
class_name StackableItem

enum StackType {
	METAL_SHEET,
	PLASTEEL_SHEET,
	WOOD_PLANK,
	CLOTH,
	CARDBOARD,
	CABLE_COIL,
	METAL_ROD,
	PLASTEEL_ROD,
	SANDBAGS_EMPTY,
	SANDBAGS_FULL,
	NANOPASTE,
	MEDICAL_BRUISE_PACK,
	MEDICAL_OINTMENT,
	MEDICAL_SPLINT
}

@export var stack_type: StackType = StackType.METAL_SHEET
@export var amount: int = 1
@export var max_amount: int = 50
@export var singular_name: String = ""
@export var stack_id: String = ""
@export var has_recipes: bool = false
@export var amount_sprites: bool = false
@export var per_unit_value: float = 10.0

# For cable coils
@export var cable_color: Color = Color.RED
@export var can_restrain: bool = false

# For construction materials
@export var sheet_type: String = ""

var recipes: Array = []

signal stack_changed(stack, old_amount, new_amount)
signal stack_depleted(stack)
signal recipe_used(stack, recipe_name, amount_used)

func _ready():
	super._ready()
	_initialize_stack()
	_update_appearance()

func _initialize_stack():
	match stack_type:
		StackType.METAL_SHEET:
			item_name = "Metal Sheets"
			singular_name = "metal sheet"
			description = "Sheets made out of metal."
			max_amount = 50
			sheet_type = "metal"
			has_recipes = true
			amount_sprites = true
			
		StackType.PLASTEEL_SHEET:
			item_name = "Plasteel Sheets"
			singular_name = "plasteel sheet"
			description = "Expensive, durable plasteel sheets."
			max_amount = 50
			sheet_type = "plasteel"
			has_recipes = true
			amount_sprites = true
			per_unit_value = 25.0
			
		StackType.WOOD_PLANK:
			item_name = "Wood Planks"
			singular_name = "wood plank"
			description = "One can only guess that this is a bunch of wood."
			max_amount = 50
			sheet_type = "wood"
			has_recipes = true
			amount_sprites = true
			
		StackType.CLOTH:
			item_name = "Cloth"
			singular_name = "cloth roll"
			description = "This roll of cloth is made from fine materials."
			max_amount = 50
			
		StackType.CARDBOARD:
			item_name = "Cardboard"
			singular_name = "cardboard sheet"
			description = "Large sheets of card, like boxes folded flat."
			max_amount = 50
			has_recipes = true
			
		StackType.CABLE_COIL:
			item_name = "Cable Coil"
			singular_name = "cable length"
			description = "A coil of power cable."
			max_amount = 30
			cable_color = Color.RED
			can_restrain = true
			
		StackType.METAL_ROD:
			item_name = "Metal Rods"
			singular_name = "metal rod"
			description = "Some rods. Can be used for building."
			max_amount = 60
			has_recipes = true
			
		StackType.PLASTEEL_ROD:
			item_name = "Plasteel Rods"
			singular_name = "plasteel rod"
			description = "Some plasteel rods for sturdy construction."
			max_amount = 30
			per_unit_value = 15.0
			
		StackType.SANDBAGS_EMPTY:
			item_name = "Empty Sandbags"
			singular_name = "sandbag"
			description = "Some empty sandbags, best to fill them up."
			max_amount = 50
			
		StackType.SANDBAGS_FULL:
			item_name = "Sandbags"
			singular_name = "sandbag"
			description = "Bags filled with sand for fortifications."
			max_amount = 25
			force = 9
			
		StackType.NANOPASTE:
			item_name = "Nanopaste"
			singular_name = "nanite swarm"
			description = "Repair nanites for robotic machinery."
			max_amount = 10
			per_unit_value = 25.0
			
		StackType.MEDICAL_BRUISE_PACK:
			item_name = "Medical Gauze"
			singular_name = "medical gauze"
			description = "Sterile gauze to wrap around wounds."
			max_amount = 10
			
		StackType.MEDICAL_OINTMENT:
			item_name = "Ointment"
			singular_name = "ointment"
			description = "Used to treat burns and infected wounds."
			max_amount = 10
			
		StackType.MEDICAL_SPLINT:
			item_name = "Medical Splints"
			singular_name = "medical splint"
			description = "Splints and gauze for treating fractures."
			max_amount = 5
	
	_set_stack_id()
	_setup_recipes()

func _set_stack_id():
	if stack_id == "":
		stack_id = singular_name.replace(" ", "_")

func _setup_recipes():
	if not has_recipes:
		return
	
	match stack_type:
		StackType.METAL_SHEET:
			recipes = _get_metal_recipes()
		StackType.PLASTEEL_SHEET:
			recipes = _get_plasteel_recipes()
		StackType.WOOD_PLANK:
			recipes = _get_wood_recipes()
		StackType.CARDBOARD:
			recipes = _get_cardboard_recipes()
		StackType.METAL_ROD:
			recipes = _get_rod_recipes()

func use_amount(amount_to_use: int) -> bool:
	if amount < amount_to_use:
		return false
	
	var old_amount = amount
	amount -= amount_to_use
	
	emit_signal("stack_changed", self, old_amount, amount)
	
	if amount <= 0:
		emit_signal("stack_depleted", self)
		queue_free()
		return true
	
	_update_appearance()
	return true

func add_amount(amount_to_add: int) -> bool:
	if amount + amount_to_add > max_amount:
		return false
	
	var old_amount = amount
	amount += amount_to_add
	
	emit_signal("stack_changed", self, old_amount, amount)
	_update_appearance()
	return true

func try_merge_with(other_stack: StackableItem) -> bool:
	if not can_merge_with(other_stack):
		return false
	
	var transfer_amount = min(other_stack.amount, max_amount - amount)
	
	if transfer_amount <= 0:
		return false
	
	add_amount(transfer_amount)
	other_stack.use_amount(transfer_amount)
	return true

func can_merge_with(other_stack: StackableItem) -> bool:
	if not other_stack:
		return false
	
	if stack_id != other_stack.stack_id:
		return false
	
	if stack_type == StackType.CABLE_COIL:
		return cable_color == other_stack.cable_color
	
	return true

func split_stack(split_amount: int) -> StackableItem:
	if split_amount >= amount or split_amount <= 0:
		return null
	
	var new_stack = _create_similar_stack()
	new_stack.amount = split_amount
	
	use_amount(split_amount)
	return new_stack

func construct_recipe(recipe_name: String, user, location: Vector2) -> bool:
	var recipe = _get_recipe(recipe_name)
	if not recipe:
		return false
	
	if amount < recipe.required_amount:
		_send_message(user, "You need " + str(recipe.required_amount) + " " + singular_name + "(s) to build " + recipe.name + ".")
		return false
	
	# Check if user has required skills
	if recipe.has("skill_required") and user.has_method("has_skill"):
		if not user.has_skill(recipe.skill_required, recipe.skill_level):
			_send_message(user, "You don't have the required skill to build " + recipe.name + ".")
			return false
	
	# Start construction
	if recipe.has("construction_time") and recipe.construction_time > 0:
		_send_message(user, "You start constructing " + recipe.name + "...")
		await get_tree().create_timer(recipe.construction_time).timeout
	
	# Create the item
	var constructed_item = _create_recipe_result(recipe, location)
	if constructed_item:
		use_amount(recipe.required_amount)
		emit_signal("recipe_used", self, recipe_name, recipe.required_amount)
		_send_message(user, "You construct " + recipe.name + ".")
		return true
	
	return false

func make_restraints(user) -> bool:
	if stack_type != StackType.CABLE_COIL or not can_restrain:
		return false
	
	if amount < 15:
		_send_message(user, "You need at least 15 lengths to make restraints!")
		return false
	
	# Create cable restraints
	var restraints = _create_cable_restraints()
	if restraints:
		restraints.global_position = user.global_position
		user.get_parent().add_child(restraints)
		
		use_amount(15)
		_send_message(user, "You wind some cable together to make restraints.")
		return true
	
	return false

func fill_sandbag(user, dirt_type: String = "dirt") -> bool:
	if stack_type != StackType.SANDBAGS_EMPTY:
		return false
	
	# Convert empty sandbag to full sandbag
	var filled_bag = _create_filled_sandbag(dirt_type)
	if filled_bag:
		filled_bag.global_position = global_position
		get_parent().add_child(filled_bag)
		
		use_amount(1)
		_send_message(user, "You fill the sandbag with " + dirt_type + ".")
		return true
	
	return false

func _update_appearance():
	_update_name()
	_update_icon()

func _update_name():
	if amount == 1:
		item_name = singular_name
	else:
		var base_name = singular_name
		if base_name.ends_with("s"):
			item_name = base_name
		else:
			item_name = base_name + "s"
		
		if amount > 1:
			item_name += " (" + str(amount) + ")"

func _update_icon():
	if not amount_sprites:
		return
	
	# Update icon based on amount
	# This would depend on your sprite system

func _create_similar_stack() -> StackableItem:
	var new_stack = StackableItem.new()
	new_stack.stack_type = stack_type
	new_stack.cable_color = cable_color
	new_stack._initialize_stack()
	return new_stack

func _get_recipe(recipe_name: String) -> Dictionary:
	for recipe in recipes:
		if recipe.name == recipe_name:
			return recipe
	return {}

func _create_recipe_result(recipe: Dictionary, location: Vector2):
	# This would depend on your item creation system
	# Return the created item
	pass

func _create_cable_restraints():
	# Create cable restraint item
	pass

func _create_filled_sandbag(dirt_type: String):
	# Create filled sandbag item
	pass

func _get_metal_recipes() -> Array:
	return [
		{
			"name": "metal barricade",
			"required_amount": 4,
			"construction_time": 2.0,
			"skill_required": "construction",
			"skill_level": 1
		},
		{
			"name": "wall girder", 
			"required_amount": 2,
			"construction_time": 5.0,
			"skill_required": "construction",
			"skill_level": 2
		},
		{
			"name": "metal rod",
			"required_amount": 1,
			"result_amount": 2,
			"construction_time": 1.0
		}
	]

func _get_plasteel_recipes() -> Array:
	return [
		{
			"name": "plasteel barricade",
			"required_amount": 8,
			"construction_time": 4.0,
			"skill_required": "construction", 
			"skill_level": 2
		},
		{
			"name": "reinforced window frame",
			"required_amount": 5,
			"construction_time": 4.0,
			"skill_required": "construction",
			"skill_level": 2
		}
	]

func _get_wood_recipes() -> Array:
	return [
		{
			"name": "wooden chair",
			"required_amount": 1,
			"construction_time": 1.0
		},
		{
			"name": "wooden barricade",
			"required_amount": 5,
			"construction_time": 2.0
		},
		{
			"name": "campfire",
			"required_amount": 5,
			"construction_time": 1.5
		}
	]

func _get_cardboard_recipes() -> Array:
	return [
		{
			"name": "cardboard box",
			"required_amount": 1,
			"construction_time": 0.5
		},
		{
			"name": "pizza box",
			"required_amount": 1,
			"construction_time": 0.5
		}
	]

func _get_rod_recipes() -> Array:
	return [
		{
			"name": "grille",
			"required_amount": 4,
			"construction_time": 2.0,
			"skill_required": "construction",
			"skill_level": 1
		}
	]

func _send_message(entity, message: String):
	if entity and entity.has_method("display_message"):
		entity.display_message(message)

func get_examine_text() -> String:
	var text = super.get_examine_text()
	text += "\nThere are " + str(amount) + " " + singular_name + "(s) in the stack."
	
	if has_recipes and recipes.size() > 0:
		text += "\nThis can be used to construct various items."
	
	return text

# Factory methods for different stack types
static func create_metal_sheets(amount: int = 50) -> StackableItem:
	var stack = StackableItem.new()
	stack.stack_type = StackType.METAL_SHEET
	stack.amount = amount
	stack._initialize_stack()
	return stack

static func create_cable_coil(amount: int = 30, color: Color = Color.RED) -> StackableItem:
	var stack = StackableItem.new()
	stack.stack_type = StackType.CABLE_COIL
	stack.amount = amount
	stack.cable_color = color
	stack._initialize_stack()
	return stack

static func create_wood_planks(amount: int = 50) -> StackableItem:
	var stack = StackableItem.new()
	stack.stack_type = StackType.WOOD_PLANK
	stack.amount = amount
	stack._initialize_stack()
	return stack

static func create_empty_sandbags(amount: int = 50) -> StackableItem:
	var stack = StackableItem.new()
	stack.stack_type = StackType.SANDBAGS_EMPTY
	stack.amount = amount
	stack._initialize_stack()
	return stack
