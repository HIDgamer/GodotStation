extends Item
class_name KitchenTool

enum KitchenType {
	FORK,
	SPOON,
	KNIFE,
	KITCHEN_KNIFE,
	BUTCHER_CLEAVER,
	PIZZA_CUTTER,
	ROLLING_PIN,
	TRAY,
	CAN_OPENER
}

@export var kitchen_type: KitchenType = KitchenType.KNIFE
@export var food_effectiveness: float = 1.0
@export var can_cut_food: bool = false
@export var can_serve_food: bool = false
@export var loaded_food: String = ""
@export var max_food_capacity: int = 1
@export var is_sharp_utensil: bool = false

# Tray specific
@export var shield_bash_cooldown: float = 25.0
var last_bash_time: float = 0.0

# Can opener specific
@export var is_compact: bool = false
@export var is_active: bool = false

signal food_served(tool, user, target)
signal food_consumed(tool, user, food_type)
signal tray_bashed(tool, user, target)

func _ready():
	super._ready()
	_initialize_kitchen_tool()

func _initialize_kitchen_tool():
	match kitchen_type:
		KitchenType.FORK:
			item_name = "Fork"
			description = "It's a fork. Sure is pointy."
			force = 5
			w_class = 1
			can_serve_food = true
			is_sharp_utensil = true
			
		KitchenType.SPOON:
			item_name = "Spoon"
			description = "You can see your own upside-down face in it."
			force = 5
			w_class = 1
			can_serve_food = true
			
		KitchenType.KNIFE:
			item_name = "Knife"
			description = "Can cut through any food."
			force = 10
			w_class = 1
			sharp = true
			can_cut_food = true
			is_sharp_utensil = true
			
		KitchenType.KITCHEN_KNIFE:
			item_name = "Kitchen Knife"
			description = "A general purpose Chef's Knife made by SpaceCook Incorporated."
			force = 25
			w_class = 2
			sharp = true
			can_cut_food = true
			food_effectiveness = 1.5
			
		KitchenType.BUTCHER_CLEAVER:
			item_name = "Butcher's Cleaver"
			description = "A huge thing used for chopping and chopping up meat."
			force = 20
			w_class = 1
			sharp = true
			can_cut_food = true
			food_effectiveness = 2.0
			
		KitchenType.PIZZA_CUTTER:
			item_name = "Pizza Cutter"
			description = "A circular blade used for cutting pizzas."
			force = 10
			w_class = 2
			sharp = true
			can_cut_food = true
			food_effectiveness = 1.2
			
		KitchenType.ROLLING_PIN:
			item_name = "Rolling Pin"
			description = "Used to knock out the Bartender."
			force = 8
			w_class = 2
			food_effectiveness = 1.0
			
		KitchenType.TRAY:
			item_name = "Tray"
			description = "A metal tray to lay food on."
			force = 12
			w_class = 2
			can_serve_food = true
			max_food_capacity = 6
			
		KitchenType.CAN_OPENER:
			item_name = "Can Opener"
			description = "A simple can opener, popular among UPP."
			force = 15
			w_class = 1
			sharp = true

func use_on_target(user, target) -> bool:
	match kitchen_type:
		KitchenType.FORK, KitchenType.SPOON, KitchenType.KNIFE:
			return _use_utensil(user, target)
		KitchenType.KITCHEN_KNIFE, KitchenType.BUTCHER_CLEAVER, KitchenType.PIZZA_CUTTER:
			return _use_cutting_tool(user, target)
		KitchenType.ROLLING_PIN:
			return _use_rolling_pin(user, target)
		KitchenType.TRAY:
			return _use_tray(user, target)
		KitchenType.CAN_OPENER:
			return _use_can_opener(user, target)
	
	return false

func _use_utensil(user, target) -> bool:
	# Feed food to target if utensil has food loaded
	if loaded_food != "" and target.has_method("consume_food"):
		var nutrition_value = _get_food_nutrition(loaded_food)
		
		if target.consume_food(nutrition_value):
			_send_message(user, "You feed " + target.name + " some " + loaded_food + ".")
			loaded_food = ""
			emit_signal("food_served", self, user, target)
			return true
		else:
			_send_message(user, target.name + " doesn't want to eat right now.")
			return false
	
	# Load food from target if it's a food item
	if loaded_food == "" and target.has_method("get_food_type"):
		loaded_food = target.get_food_type()
		_send_message(user, "You pick up some " + loaded_food + " with the " + item_name + ".")
		target.queue_free()  # Consume the food item
		return true
	
	return false

func _use_cutting_tool(user, target) -> bool:
	if target.has_method("can_be_cut") and target.can_be_cut():
		var cut_result = target.cut_food(food_effectiveness)
		if cut_result.size() > 0:
			_send_message(user, "You cut the " + target.name + " with the " + item_name + ".")
			
			# Spawn cut pieces
			for piece in cut_result:
				var cut_item = _create_food_piece(piece)
				cut_item.global_position = target.global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
				target.get_parent().add_child(cut_item)
			
			target.queue_free()
			return true
		else:
			_send_message(user, "You can't cut the " + target.name + " any further.")
			return false
	
	_send_message(user, "You can't cut that with the " + item_name + ".")
	return false

func _use_rolling_pin(user, target) -> bool:
	if target.has_method("get_health_system"):
		var health_system = target.get_health_system()
		if health_system:
			# Special head attack with drowsy effect
			if user.has_method("get_target_zone") and user.get_target_zone() == "head":
				_send_message(user, "You hit " + target.name + " over the head with the rolling pin!")
				health_system.apply_status_effect("drowsy", 10.0)
				health_system.take_damage(force, "brute")
				return true
	
	return false

func _use_tray(user, target) -> bool:
	# Tray shield bash
	if target.has_method("get_health_system"):
		var current_time = Time.get_time_dict_from_system()["unix"]
		if current_time - last_bash_time >= shield_bash_cooldown:
			_send_message(user, "You bash " + target.name + " with the tray!")
			var health_system = target.get_health_system()
			health_system.take_damage(force, "brute")
			health_system.apply_status_effect("stunned", 2.0)
			
			last_bash_time = current_time
			emit_signal("tray_bashed", self, user, target)
			return true
		else:
			_send_message(user, "You need to wait before bashing again.")
			return false
	
	# Serve food from tray
	if can_serve_food and _has_food_on_tray():
		return _serve_food_from_tray(user, target)
	
	return false

func _use_can_opener(user, target) -> bool:
	if is_compact and not is_active:
		_send_message(user, "You need to flip out the can opener first!")
		return false
	
	if target.has_method("open_can"):
		target.open_can()
		_send_message(user, "You open the " + target.name + " with the can opener.")
		return true
	
	_send_message(user, "You can't open that with a can opener.")
	return false

func toggle_can_opener(user):
	if kitchen_type != KitchenType.CAN_OPENER or not is_compact:
		return
	
	is_active = !is_active
	if is_active:
		_send_message(user, "You flip out the can opener.")
		force = 15
		sharp = true
	else:
		_send_message(user, "You fold the can opener.")
		force = 0
		sharp = false

func add_food_to_tray(food_item) -> bool:
	if kitchen_type != KitchenType.TRAY:
		return false
	
	# Implementation would depend on your food system
	return true

func _has_food_on_tray() -> bool:
	# Check if tray has food items
	return false  # Placeholder

func _serve_food_from_tray(user, target) -> bool:
	# Serve food from tray to target
	return false  # Placeholder

func _get_food_nutrition(food_type: String) -> float:
	# Return nutrition value based on food type
	match food_type:
		"bread":
			return 50.0
		"meat":
			return 75.0
		"vegetables":
			return 30.0
		_:
			return 25.0

func _create_food_piece(piece_data: Dictionary):
	# Create a food piece based on cutting result
	# This would depend on your food system implementation
	pass

func _send_message(entity, message: String):
	if entity and entity.has_method("display_message"):
		entity.display_message(message)

func get_examine_text() -> String:
	var text = super.get_examine_text()
	
	if loaded_food != "":
		text += "\nIt has some " + loaded_food + " on it."
	
	if kitchen_type == KitchenType.CAN_OPENER and is_compact:
		if is_active:
			text += "\nThe can opener is flipped out and ready to use."
		else:
			text += "\nThe can opener is folded and safe to store."
	
	return text

# Specialized kitchen tool classes
class PlasticUtensil extends KitchenTool:
	func _init(utensil_type: KitchenType):
		super._init()
		kitchen_type = utensil_type
		item_name = "Plastic " + _get_utensil_name(utensil_type)
		description = "A plastic " + _get_utensil_name(utensil_type).to_lower() + "."
		force = 5
		food_effectiveness = 0.8
		_initialize_kitchen_tool()
	
	func _get_utensil_name(type: KitchenType) -> String:
		match type:
			KitchenType.FORK:
				return "Fork"
			KitchenType.SPOON:
				return "Spoon"
			KitchenType.KNIFE:
				return "Knife"
			_:
				return "Utensil"

class WoodPizzaCutter extends KitchenTool:
	func _init():
		super._init()
		kitchen_type = KitchenType.PIZZA_CUTTER
		item_name = "Wood Pizza Cutter"
		description = "A pizza cutter with an authentic wooden handle."
		_initialize_kitchen_tool()

class HolyRelicPizzaCutter extends KitchenTool:
	func _init():
		super._init()
		kitchen_type = KitchenType.PIZZA_CUTTER
		item_name = "PIZZA TIME"
		description = "A holy relic of a bygone era when the great Pizza Lords reigned supreme."
		force = 35
		food_effectiveness = 3.0
		_initialize_kitchen_tool()

class CompactCanOpener extends KitchenTool:
	func _init():
		super._init()
		kitchen_type = KitchenType.CAN_OPENER
		item_name = "Folding Can Opener"
		description = "A small compact can opener that can be folded."
		is_compact = true
		is_active = false
		force = 0
		sharp = false
		w_class = 1
		_initialize_kitchen_tool()

# Factory methods
static func create_fork() -> KitchenTool:
	var tool = KitchenTool.new()
	tool.kitchen_type = KitchenType.FORK
	tool._initialize_kitchen_tool()
	return tool

static func create_kitchen_knife() -> KitchenTool:
	var tool = KitchenTool.new()
	tool.kitchen_type = KitchenType.KITCHEN_KNIFE
	tool._initialize_kitchen_tool()
	return tool

static func create_pizza_cutter() -> KitchenTool:
	var tool = KitchenTool.new()
	tool.kitchen_type = KitchenType.PIZZA_CUTTER
	tool._initialize_kitchen_tool()
	return tool

static func create_plastic_spork() -> PlasticUtensil:
	return PlasticUtensil.new(KitchenType.SPOON)  # Close enough to a spork
