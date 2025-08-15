extends Item
class_name EngineeringTool

enum ToolType {
	WRENCH,
	SCREWDRIVER,
	WIRECUTTERS,
	BLOWTORCH,
	CROWBAR,
	MAINTENANCE_JACK,
	MULTITOOL
}

@export var tool_type: ToolType = ToolType.WRENCH
@export var tool_effectiveness: float = 1.0
@export var requires_fuel: bool = false
@export var max_fuel: float = 40.0
@export var current_fuel: float = 40.0
@export var fuel_per_use: float = 1.0
@export var is_powered: bool = false
@export var heat_source: float = 0.0
@export var welding_power: float = 0.0

# For maintenance jack
@export var crowbar_mode: bool = true
@export var requires_superstrength: bool = true
@export var prying_time: float = 3.0
@export var unbolt_time: float = 5.0

var is_on: bool = false
var last_use_time: float = 0.0
var use_cooldown: float = 1.0

signal tool_activated(tool)
signal tool_deactivated(tool)
signal fuel_depleted(tool)
signal tool_used(tool, target, user, success)

func _ready():
	super._ready()
	_initialize_tool()

func _initialize_tool():
	match tool_type:
		ToolType.WRENCH:
			item_name = "Wrench"
			description = "A wrench with many common uses."
			force = 5
			w_class = 1
			
		ToolType.SCREWDRIVER:
			item_name = "Screwdriver"
			description = "You can be totally screwy with this."
			force = 5
			w_class = 1
			sharp = true
			
		ToolType.WIRECUTTERS:
			item_name = "Wirecutters"
			description = "This cuts wires."
			force = 6
			w_class = 1
			sharp = true
			
		ToolType.BLOWTORCH:
			item_name = "Blowtorch"
			description = "A blowtorch for welding and cutting metals."
			force = 3
			w_class = 1
			requires_fuel = true
			max_fuel = 40.0
			current_fuel = 40.0
			fuel_per_use = 1.0
			
		ToolType.CROWBAR:
			item_name = "Crowbar"
			description = "Used to remove floors and pry open doors."
			force = 5
			w_class = 1
			
		ToolType.MAINTENANCE_JACK:
			item_name = "K92 Maintenance Jack"
			description = "A combination crowbar, wrench, and bludgeoning device."
			force = 30
			w_class = 3
			crowbar_mode = true
			requires_superstrength = true

func use_on_target(user, target) -> bool:
	if not _can_use():
		return false
	
	if requires_fuel and current_fuel < fuel_per_use:
		_send_message(user, item_name + " needs more fuel!")
		return false
	
	var success = false
	
	match tool_type:
		ToolType.WRENCH:
			success = _use_wrench(user, target)
		ToolType.SCREWDRIVER:
			success = _use_screwdriver(user, target)
		ToolType.WIRECUTTERS:
			success = _use_wirecutters(user, target)
		ToolType.BLOWTORCH:
			success = _use_blowtorch(user, target)
		ToolType.CROWBAR:
			success = await _use_crowbar(user, target)
		ToolType.MAINTENANCE_JACK:
			success = await _use_maintenance_jack(user, target)
	
	if success and requires_fuel:
		current_fuel -= fuel_per_use
		if current_fuel <= 0:
			_fuel_depleted()
	
	last_use_time = Time.get_time_dict_from_system()["unix"]
	emit_signal("tool_used", self, target, user, success)
	return success

func toggle_power(user) -> bool:
	if not requires_fuel:
		return false
	
	if not is_on:
		if current_fuel > 0:
			is_on = true
			is_powered = true
			heat_source = 1000
			welding_power = 15
			_send_message(user, "You turn on the " + item_name + ".")
			emit_signal("tool_activated", self)
			return true
		else:
			_send_message(user, item_name + " needs fuel!")
			return false
	else:
		is_on = false
		is_powered = false
		heat_source = 0
		welding_power = 0
		_send_message(user, "You turn off the " + item_name + ".")
		emit_signal("tool_deactivated", self)
		return true

func refuel(fuel_amount: float):
	var old_fuel = current_fuel
	current_fuel = min(max_fuel, current_fuel + fuel_amount)
	return current_fuel - old_fuel

func _can_use() -> bool:
	var current_time = Time.get_time_dict_from_system()["unix"]
	return current_time - last_use_time >= use_cooldown

func _use_wrench(user, target) -> bool:
	if target.has_method("wrench_act"):
		return target.wrench_act(user, self)
	
	_send_message(user, "You use the wrench on " + target.name + ".")
	return true

func _use_screwdriver(user, target) -> bool:
	if target.has_method("screwdriver_act"):
		return target.screwdriver_act(user, self)
	
	_send_message(user, "You use the screwdriver on " + target.name + ".")
	return true

func _use_wirecutters(user, target) -> bool:
	if target.has_method("wirecutter_act"):
		return target.wirecutter_act(user, self)
	
	# Special case for cutting restraints
	if target.has_method("is_restrained") and target.is_restrained():
		target.remove_restraints()
		_send_message(user, "You cut " + target.name + "'s restraints.")
		return true
	
	_send_message(user, "You use the wirecutters on " + target.name + ".")
	return true

func _use_blowtorch(user, target) -> bool:
	if not is_on:
		_send_message(user, "The blowtorch needs to be turned on first!")
		return false
	
	if target.has_method("welder_act"):
		return target.welder_act(user, self)
	
	# Special case for repairing robotic limbs
	if target.has_method("get_health_system"):
		var health_system = target.get_health_system()
		if health_system and health_system.has_method("repair_robotic_limb"):
			health_system.repair_robotic_limb("", 15)
			_send_message(user, "You repair some damage on " + target.name + ".")
			return true
	
	_send_message(user, "You use the blowtorch on " + target.name + ".")
	return true

func _use_crowbar(user, target) -> bool:
	if target.has_method("crowbar_act"):
		return target.crowbar_act(user, self)
	
	# Special case for prying doors
	if target.has_method("pry_open"):
		_send_message(user, "You start prying open " + target.name + "...")
		await get_tree().create_timer(prying_time).timeout
		target.pry_open(user)
		_send_message(user, "You pry open " + target.name + ".")
		return true
	
	_send_message(user, "You use the crowbar on " + target.name + ".")
	return true

func _use_maintenance_jack(user, target) -> bool:
	if crowbar_mode:
		# Check if user has super strength for prying
		if requires_superstrength and not user.has_method("has_super_strength"):
			_send_message(user, "You need more strength to pry with this.")
			return false
		
		return await _use_crowbar(user, target)
	else:
		# Wrench mode - unbolt doors
		if target.has_method("unbolt"):
			_send_message(user, "You start unbolting " + target.name + "...")
			await get_tree().create_timer(unbolt_time).timeout
			target.unbolt(user)
			_send_message(user, "You unbolt " + target.name + ".")
			return true
		
		return _use_wrench(user, target)

func switch_mode(user):
	if tool_type != ToolType.MAINTENANCE_JACK:
		return
	
	crowbar_mode = !crowbar_mode
	var mode_name = "crowbar" if crowbar_mode else "wrench"
	_send_message(user, "You switch the maintenance jack to " + mode_name + " mode.")

func _fuel_depleted():
	if is_on:
		is_on = false
		is_powered = false
		heat_source = 0
		welding_power = 0
	
	emit_signal("fuel_depleted", self)

func _send_message(entity, message: String):
	if entity and entity.has_method("display_message"):
		entity.display_message(message)

func get_examine_text() -> String:
	var text = super.get_examine_text()
	
	if requires_fuel:
		text += "\nFuel: " + str(int(current_fuel)) + "/" + str(int(max_fuel))
		if is_on:
			text += "\nThe blowtorch is currently on."
		else:
			text += "\nThe blowtorch is currently off."
	
	if tool_type == ToolType.MAINTENANCE_JACK:
		var mode = "crowbar" if crowbar_mode else "wrench"
		text += "\nCurrently in " + mode + " mode."
	
	return text

# Specialized tool classes
class TacticalScrewdriver extends EngineeringTool:
	func _init():
		super._init()
		tool_type = ToolType.SCREWDRIVER
		item_name = "Tactical Screwdriver"
		description = "Sharp, matte black, and deadly."
		force = 15
		tool_effectiveness = 1.2

class TacticalWirecutters extends EngineeringTool:
	func _init():
		super._init()
		tool_type = ToolType.WIRECUTTERS
		item_name = "Tactical Wirecutters"
		description = "Heavy-duty wirecutters for cutting barbed wire."
		force = 8
		tool_effectiveness = 1.3

class ShieldedBlowtorch extends EngineeringTool:
	func _init():
		super._init()
		tool_type = ToolType.BLOWTORCH
		item_name = "Shielded Blowtorch"
		description = "A blowtorch with a welding screen to prevent eye damage."
		tool_effectiveness = 1.1

class IndustrialBlowtorch extends EngineeringTool:
	func _init():
		super._init()
		tool_type = ToolType.BLOWTORCH
		item_name = "Industrial Blowtorch"
		description = "A heavy-duty blowtorch with larger fuel capacity."
		max_fuel = 60.0
		current_fuel = 60.0
		w_class = 2
		tool_effectiveness = 1.3

class ME3HandWelder extends EngineeringTool:
	func _init():
		super._init()
		tool_type = ToolType.BLOWTORCH
		item_name = "ME3 Hand Welder"
		description = "A compact, handheld welding torch used by marines."
		max_fuel = 5.0
		current_fuel = 5.0
		tool_effectiveness = 0.8

class TacticalPrybar extends EngineeringTool:
	func _init():
		super._init()
		tool_type = ToolType.CROWBAR
		item_name = "Tactical Prybar"
		description = "Makes you want to raid a townhouse filled with terrorists."
		force = 20
		tool_effectiveness = 1.2

# Factory methods
static func create_wrench() -> EngineeringTool:
	var tool = EngineeringTool.new()
	tool.tool_type = ToolType.WRENCH
	tool._initialize_tool()
	return tool

static func create_screwdriver() -> EngineeringTool:
	var tool = EngineeringTool.new()
	tool.tool_type = ToolType.SCREWDRIVER
	tool._initialize_tool()
	return tool

static func create_blowtorch() -> EngineeringTool:
	var tool = EngineeringTool.new()
	tool.tool_type = ToolType.BLOWTORCH
	tool._initialize_tool()
	return tool

static func create_maintenance_jack() -> EngineeringTool:
	var tool = EngineeringTool.new()
	tool.tool_type = ToolType.MAINTENANCE_JACK
	tool._initialize_tool()
	return tool
