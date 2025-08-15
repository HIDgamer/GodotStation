extends Item
class_name UtilityTool

enum UtilityType {
	FIRE_EXTINGUISHER,
	MOP,
	SOAP,
	WET_SIGN,
	WARNING_CONE,
	CREW_MONITOR,
	HAND_LABELER,
	PEN,
	STAMP,
	SHOVEL,
	HATCHET,
	SCYTHE
}

@export var utility_type: UtilityType = UtilityType.FIRE_EXTINGUISHER
@export var max_capacity: float = 50.0
@export var current_capacity: float = 50.0
@export var extinguisher_power: float = 7.0
@export var safety_on: bool = true
@export var last_use_time: float = 0.0
@export var use_cooldown: float = 2.0

# Pen/Labeler specific
@export var pen_color: String = "black"
@export var pen_on: bool = true
@export var label_text: String = ""
@export var labels_left: int = 50
@export var max_labels: int = 50

# Shovel specific
@export var dirt_amount: int = 0
@export var max_dirt: int = 6
@export var dirt_type: String = "dirt"
@export var is_folded: bool = false

# Monitor specific
@export var faction: String = "marine"

var reagent_container = null

signal extinguisher_used(tool, user, target)
signal area_cleaned(tool, user, location)
signal item_labeled(tool, user, target, label)
signal dirt_collected(tool, user, amount, type)

func _ready():
	super._ready()
	_initialize_utility_tool()

func _initialize_utility_tool():
	match utility_type:
		UtilityType.FIRE_EXTINGUISHER:
			item_name = "Fire Extinguisher"
			description = "A traditional red fire extinguisher."
			force = 10
			w_class = 2
			max_capacity = 50.0
			current_capacity = max_capacity
			extinguisher_power = 7.0
			safety_on = true
			_create_reagent_container()
			
		UtilityType.MOP:
			item_name = "Mop"
			description = "Essential for keeping the ship clean."
			force = 3
			w_class = 2
			max_capacity = 15.0
			current_capacity = 0.0
			
		UtilityType.SOAP:
			item_name = "Soap"
			description = "A cheap bar of soap. Doesn't smell."
			force = 0
			w_class = 1
			
		UtilityType.WET_SIGN:
			item_name = "Wet Floor Sign"
			description = "Caution! Wet Floor!"
			force = 1
			w_class = 1
			
		UtilityType.WARNING_CONE:
			item_name = "Warning Cone"
			description = "This cone is trying to warn you of something!"
			force = 1
			w_class = 1
			
		UtilityType.CREW_MONITOR:
			item_name = "Crew Monitor"
			description = "A tool for tracking deployed personnel coordinates."
			force = 0
			w_class = 1
			faction = "marine"
			
		UtilityType.HAND_LABELER:
			item_name = "Hand Labeler"
			description = "For labeling items and containers."
			force = 0
			w_class = 1
			labels_left = max_labels
			
		UtilityType.PEN:
			item_name = "Pen"
			description = "It's a normal black ink pen."
			force = 0
			w_class = 1
			pen_color = "black"
			pen_on = true
			
		UtilityType.STAMP:
			item_name = "Rubber Stamp"
			description = "A rubber stamp for stamping important documents."
			force = 0
			w_class = 1
			
		UtilityType.SHOVEL:
			item_name = "Shovel"
			description = "A large tool for digging and moving dirt."
			force = 8
			w_class = 2
			max_dirt = 6
			dirt_amount = 0
			
		UtilityType.HATCHET:
			item_name = "Hatchet"
			description = "A sharp hand hatchet for cutting timber."
			force = 20
			w_class = 1
			sharp = true
			
		UtilityType.SCYTHE:
			item_name = "Scythe"
			description = "A curved blade for reaping what you sow."
			force = 13
			w_class = 3
			sharp = true

func use_on_target(user, target) -> bool:
	if not _can_use():
		return false
	
	var success = false
	
	match utility_type:
		UtilityType.FIRE_EXTINGUISHER:
			success = _use_extinguisher(user, target)
		UtilityType.MOP:
			success = _use_mop(user, target)
		UtilityType.SOAP:
			success = _use_soap(user, target)
		UtilityType.HAND_LABELER:
			success = _use_labeler(user, target)
		UtilityType.PEN:
			success = _use_pen(user, target)
		UtilityType.STAMP:
			success = _use_stamp(user, target)
		UtilityType.SHOVEL:
			success = _use_shovel(user, target)
		UtilityType.HATCHET:
			success = _use_hatchet(user, target)
		UtilityType.SCYTHE:
			success = _use_scythe(user, target)
		UtilityType.CREW_MONITOR:
			success = _use_crew_monitor(user)
	
	if success:
		last_use_time = Time.get_time_dict_from_system()["unix"]
	
	return success

func _use_extinguisher(user, target) -> bool:
	if safety_on:
		_send_message(user, "The safety is on! Click the extinguisher to turn it off.")
		return false
	
	if current_capacity < 1:
		_send_message(user, "The extinguisher is empty!")
		return false
	
	if target == user:
		# Extinguish user
		if user.has_method("extinguish_fire"):
			user.extinguish_fire()
			_send_message(user, "You extinguish yourself with the fire extinguisher.")
		current_capacity -= 1
		return true
	
	# Extinguish target area
	var extinguish_area = _get_extinguish_area(target)
	for location in extinguish_area:
		_extinguish_location(location)
	
	current_capacity -= 3
	emit_signal("extinguisher_used", self, user, target)
	_send_message(user, "You spray the fire extinguisher.")
	
	# Apply knockback if in space
	if user.has_method("is_in_space") and user.is_in_space():
		var knockback_dir = (user.global_position - target.global_position).normalized()
		user.apply_impulse(knockback_dir * 100)
	
	return true

func _use_mop(user, target) -> bool:
	if current_capacity < 1:
		_send_message(user, "The mop is dry!")
		return false
	
	if target.has_method("clean_area"):
		target.clean_area()
		current_capacity -= 1
		emit_signal("area_cleaned", self, user, target.global_position)
		_send_message(user, "You clean the area with the mop.")
		return true
	
	return false

func _use_soap(user, target) -> bool:
	if target.has_method("clean_item"):
		target.clean_item()
		_send_message(user, "You clean " + target.name + " with the soap.")
		return true
	
	# Make target slippery if it's a floor
	if target.has_method("make_slippery"):
		target.make_slippery(3.0)  # 3 seconds of slipperiness
		_send_message(user, "You accidentally drop the soap!")
		return true
	
	return false

func _use_labeler(user, target) -> bool:
	if labels_left <= 0:
		_send_message(user, "No labels left!")
		return false
	
	if label_text == "":
		_send_message(user, "No label text set! Click the labeler to set text.")
		return false
	
	if target.has_method("apply_label"):
		if target.apply_label(label_text):
			labels_left -= 1
			emit_signal("item_labeled", self, user, target, label_text)
			_send_message(user, "You label " + target.name + " as '" + label_text + "'.")
			return true
	
	return false

func _use_pen(user, target) -> bool:
	if not pen_on:
		_send_message(user, "The pen is clicked off!")
		return false
	
	if target.has_method("write_on"):
		var text = _get_user_input(user, "What do you want to write?")
		if text != "":
			target.write_on(text, pen_color)
			_send_message(user, "You write on " + target.name + " with the pen.")
			return true
	
	return false

func _use_stamp(user, target) -> bool:
	if target.has_method("stamp_on"):
		target.stamp_on(item_name)
		_send_message(user, "You stamp " + target.name + ".")
		return true
	
	return false

func _use_shovel(user, target) -> bool:
	if target.has_method("dig_from"):
		if dirt_amount >= max_dirt:
			_send_message(user, "The shovel is full of dirt!")
			return false
		
		var dug_dirt = target.dig_from(1)
		if dug_dirt > 0:
			dirt_amount += dug_dirt
			dirt_type = target.get_dirt_type()
			emit_signal("dirt_collected", self, user, dug_dirt, dirt_type)
			_send_message(user, "You dig up some " + dirt_type + ".")
			return true
	
	# Dump dirt
	if dirt_amount > 0:
		_dump_dirt(target.global_position)
		_send_message(user, "You dump the " + dirt_type + ".")
		return true
	
	return false

func _use_hatchet(user, target) -> bool:
	if target.has_method("chop_down"):
		target.chop_down()
		_send_message(user, "You chop down " + target.name + " with the hatchet.")
		return true
	
	return false

func _use_scythe(user, target) -> bool:
	if target.has_method("cut_plants"):
		var cut_area = _get_adjacent_positions(target.global_position)
		for pos in cut_area:
			var plants = _get_plants_at_position(pos)
			for plant in plants:
				if plant.has_method("cut_down"):
					plant.cut_down()
		
		_send_message(user, "You cut down plants with the scythe.")
		return true
	
	return false

func _use_crew_monitor(user) -> bool:
	# Open crew monitoring interface
	if user.has_method("open_interface"):
		user.open_interface("crew_monitor", {"faction": faction})
		return true
	
	return false

func toggle_safety(user) -> bool:
	if utility_type != UtilityType.FIRE_EXTINGUISHER:
		return false
	
	safety_on = !safety_on
	_send_message(user, "The safety is " + ("on" if safety_on else "off") + ".")
	return true

func toggle_pen(user) -> bool:
	if utility_type != UtilityType.PEN:
		return false
	
	pen_on = !pen_on
	_send_message(user, "You click the pen " + ("on" if pen_on else "off") + ".")
	return true

func set_label_text(user, text: String) -> bool:
	if utility_type != UtilityType.HAND_LABELER:
		return false
	
	label_text = text
	_send_message(user, "You set the label text to '" + text + "'.")
	return true

func refill_extinguisher(user, refill_source) -> bool:
	if utility_type != UtilityType.FIRE_EXTINGUISHER:
		return false
	
	if refill_source.has_method("transfer_water"):
		var transferred = refill_source.transfer_water(max_capacity - current_capacity)
		current_capacity += transferred
		_send_message(user, "You refill the fire extinguisher.")
		return true
	
	return false

func refill_mop(user, water_source) -> bool:
	if utility_type != UtilityType.MOP:
		return false
	
	if water_source.has_method("get_water"):
		current_capacity = max_capacity
		_send_message(user, "You wet the mop.")
		return true
	
	return false

func refill_labeler(user, paper_item) -> bool:
	if utility_type != UtilityType.HAND_LABELER:
		return false
	
	if labels_left >= max_labels:
		_send_message(user, "The labeler is already full.")
		return false
	
	if paper_item.has_method("consume_for_labels"):
		labels_left = max_labels
		paper_item.queue_free()
		_send_message(user, "You refill the labeler with paper.")
		return true
	
	return false

func fold_shovel(user) -> bool:
	if utility_type != UtilityType.SHOVEL:
		return false
	
	# Only entrenching tools can fold
	if not item_name.contains("Entrenching"):
		return false
	
	is_folded = !is_folded
	if is_folded:
		w_class = 1
		force = 2
		_send_message(user, "You fold the entrenching tool.")
	else:
		w_class = 2
		force = 8
		_send_message(user, "You unfold the entrenching tool.")
	
	return true

func _can_use() -> bool:
	var current_time = Time.get_time_dict_from_system()["unix"]
	return current_time - last_use_time >= use_cooldown

func _create_reagent_container():
	# Create reagent container for extinguisher
	pass

func _get_extinguish_area(target) -> Array:
	var area = []
	var center = target.global_position if target else Vector2.ZERO
	
	# 3x3 area around target
	for x in range(-32, 33, 32):
		for y in range(-32, 33, 32):
			area.append(center + Vector2(x, y))
	
	return area

func _extinguish_location(location: Vector2):
	# Extinguish fires at location
	pass

func _dump_dirt(location: Vector2):
	dirt_amount = 0
	dirt_type = ""
	# Create dirt pile at location
	pass

func _get_adjacent_positions(center: Vector2) -> Array:
	var positions = []
	for x in range(-32, 33, 32):
		for y in range(-32, 33, 32):
			positions.append(center + Vector2(x, y))
	return positions

func _get_plants_at_position(position: Vector2) -> Array:
	# Get all plants at the given position
	return []

func _get_user_input(user, prompt: String) -> String:
	# Get text input from user
	return ""

func _send_message(entity, message: String):
	if entity and entity.has_method("display_message"):
		entity.display_message(message)

func get_examine_text() -> String:
	var text = super.get_examine_text()
	
	match utility_type:
		UtilityType.FIRE_EXTINGUISHER:
			text += "\nContains " + str(int(current_capacity)) + "/" + str(int(max_capacity)) + " units of water."
			text += "\nSafety is " + ("on" if safety_on else "off") + "."
		UtilityType.MOP:
			if current_capacity > 0:
				text += "\nThe mop is wet."
			else:
				text += "\nThe mop is dry."
		UtilityType.HAND_LABELER:
			text += "\nIt has " + str(labels_left) + " out of " + str(max_labels) + " labels left."
			if label_text != "":
				text += "\nLabel text: '" + label_text + "'"
		UtilityType.PEN:
			text += "\nInk color: " + pen_color
			text += "\nPen is " + ("on" if pen_on else "off") + "."
		UtilityType.SHOVEL:
			if dirt_amount > 0:
				text += "\nContains " + str(dirt_amount) + " units of " + dirt_type + "."
			if is_folded:
				text += "\nThe tool is currently folded."
	
	return text

# Specialized utility tool classes
class MiniFireExtinguisher extends UtilityTool:
	func _init():
		super._init()
		utility_type = UtilityType.FIRE_EXTINGUISHER
		item_name = "Mini Fire Extinguisher"
		description = "A compact fire extinguisher."
		max_capacity = 30.0
		w_class = 1
		force = 3
		_initialize_utility_tool()

class EntrenchingTool extends UtilityTool:
	func _init():
		super._init()
		utility_type = UtilityType.SHOVEL
		item_name = "Entrenching Tool"
		description = "A folding shovel used for digging foxholes."
		force = 30
		w_class = 3
		is_folded = false
		_initialize_utility_tool()

class MulticolorPen extends UtilityTool:
	var color_list: Array = ["red", "blue", "black", "green"]
	var current_color_index: int = 0
	
	func _init():
		super._init()
		utility_type = UtilityType.PEN
		item_name = "Multicolor Pen"
		description = "A color switching pen!"
		_initialize_utility_tool()
	
	func cycle_color(user):
		current_color_index = (current_color_index + 1) % color_list.size()
		pen_color = color_list[current_color_index]
		_send_message(user, "You twist the pen and change the ink color to " + pen_color + ".")

# Factory methods
static func create_fire_extinguisher() -> UtilityTool:
	var tool = UtilityTool.new()
	tool.utility_type = UtilityType.FIRE_EXTINGUISHER
	tool._initialize_utility_tool()
	return tool

static func create_mop() -> UtilityTool:
	var tool = UtilityTool.new()
	tool.utility_type = UtilityType.MOP
	tool._initialize_utility_tool()
	return tool

static func create_hand_labeler() -> UtilityTool:
	var tool = UtilityTool.new()
	tool.utility_type = UtilityType.HAND_LABELER
	tool._initialize_utility_tool()
	return tool

static func create_crew_monitor(faction: String = "marine") -> UtilityTool:
	var tool = UtilityTool.new()
	tool.utility_type = UtilityType.CREW_MONITOR
	tool.faction = faction
	tool._initialize_utility_tool()
	return tool
