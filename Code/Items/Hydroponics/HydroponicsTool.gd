extends Item
class_name HydroponicsTool

enum PlantToolType {
	PLANT_SPRAY,
	WEED_KILLER,
	PEST_SPRAY,
	MINI_HOE,
	PLANT_ANALYZER,
	WATERING_CAN,
	SEED_PACKET,
	FERTILIZER,
	PLANT_BAG
}

@export var tool_type: PlantToolType = PlantToolType.MINI_HOE
@export var toxicity: float = 4.0
@export var pest_kill_strength: float = 0.0
@export var weed_kill_strength: float = 0.0
@export var water_capacity: float = 50.0
@export var current_water: float = 0.0
@export var nutrient_value: float = 0.0
@export var uses_remaining: int = 10

# Spray specific
@export var spray_range: float = 64.0
@export var chemical_type: String = ""

# Analyzer specific
@export var scan_range: float = 32.0
@export var detailed_scan: bool = false

# Seed packet specific
@export var seed_type: String = ""
@export var seed_count: int = 5

var target_plant = null
var spraying: bool = false

signal plant_treated(tool, plant, treatment_type)
signal pest_eliminated(tool, plant, pest_count)
signal weed_removed(tool, plant, weed_count)
signal plant_watered(tool, plant, water_amount)
signal plant_analyzed(tool, plant, data)
signal seeds_planted(tool, location, seed_type, count)

func _ready():
	super._ready()
	_initialize_plant_tool()

func _initialize_plant_tool():
	match tool_type:
		PlantToolType.PLANT_SPRAY:
			item_name = "Plant Spray"
			description = "A generic plant treatment spray."
			w_class = 1
			force = 0
			uses_remaining = 20
			spray_range = 64.0
			
		PlantToolType.WEED_KILLER:
			item_name = "Weed Spray"
			description = "A toxic mixture in spray form to kill small weeds."
			w_class = 1
			force = 0
			toxicity = 4.0
			weed_kill_strength = 6.0
			uses_remaining = 15
			chemical_type = "herbicide"
			
		PlantToolType.PEST_SPRAY:
			item_name = "Pest Spray"
			description = "Pest eliminator spray! Do not inhale!"
			w_class = 1
			force = 0
			toxicity = 6.0
			pest_kill_strength = 6.0
			uses_remaining = 15
			chemical_type = "pesticide"
			
		PlantToolType.MINI_HOE:
			item_name = "Mini Hoe"
			description = "Used for removing weeds or scratching your back."
			w_class = 1
			force = 5
			weed_kill_strength = 3.0
			
		PlantToolType.PLANT_ANALYZER:
			item_name = "Plant Analyzer"
			description = "A device for analyzing plant health and growth."
			w_class = 1
			force = 0
			scan_range = 32.0
			
		PlantToolType.WATERING_CAN:
			item_name = "Watering Can"
			description = "A container for watering plants."
			w_class = 2
			force = 2
			water_capacity = 100.0
			current_water = water_capacity
			
		PlantToolType.SEED_PACKET:
			item_name = "Seed Packet"
			description = "A packet containing plant seeds."
			w_class = 1
			force = 0
			seed_type = "tomato"
			seed_count = 5
			
		PlantToolType.FERTILIZER:
			item_name = "Plant Fertilizer"
			description = "Nutrient-rich fertilizer for healthy plant growth."
			w_class = 1
			force = 0
			nutrient_value = 50.0
			uses_remaining = 10
			
		PlantToolType.PLANT_BAG:
			item_name = "Plant Collection Bag"
			description = "A bag for collecting harvested plants and seeds."
			w_class = 2
			force = 0

func use_on_target(user, target) -> bool:
	match tool_type:
		PlantToolType.PLANT_SPRAY, PlantToolType.WEED_KILLER, PlantToolType.PEST_SPRAY:
			return _use_spray(user, target)
		PlantToolType.MINI_HOE:
			return _use_hoe(user, target)
		PlantToolType.PLANT_ANALYZER:
			return await _analyze_plant(user, target)
		PlantToolType.WATERING_CAN:
			return _water_plant(user, target)
		PlantToolType.SEED_PACKET:
			return _plant_seeds(user, target)
		PlantToolType.FERTILIZER:
			return _apply_fertilizer(user, target)
		PlantToolType.PLANT_BAG:
			return _collect_plant(user, target)
	
	return false

func _use_spray(user, target) -> bool:
	if uses_remaining <= 0:
		_send_message(user, "The spray bottle is empty!")
		return false
	
	if not _is_valid_plant_target(target):
		_send_message(user, "You can only spray this on plants.")
		return false
	
	if user.global_position.distance_to(target.global_position) > spray_range:
		_send_message(user, "You're too far away to spray that.")
		return false
	
	spraying = true
	_send_message(user, "You spray " + target.name + " with " + item_name + ".")
	
	match tool_type:
		PlantToolType.WEED_KILLER:
			_kill_weeds(target)
		PlantToolType.PEST_SPRAY:
			_eliminate_pests(target)
		PlantToolType.PLANT_SPRAY:
			_apply_general_treatment(target)
	
	uses_remaining -= 1
	spraying = false
	
	# Apply toxicity to user if they get some spray on themselves
	if randf() < 0.1:
		_apply_spray_toxicity(user)
	
	return true

func _use_hoe(user, target) -> bool:
	if _is_valid_plant_target(target):
		if target.has_method("remove_weeds"):
			var weeds_removed = target.remove_weeds(weed_kill_strength)
			if weeds_removed > 0:
				_send_message(user, "You remove " + str(weeds_removed) + " weeds from " + target.name + ".")
				emit_signal("weed_removed", self, target, weeds_removed)
				return true
			else:
				_send_message(user, "There are no weeds to remove.")
				return false
	
	# Can also be used to till soil
	if target.has_method("till_soil"):
		target.till_soil()
		_send_message(user, "You till the soil.")
		return true
	
	return false

func _analyze_plant(user, target) -> bool:
	if not _is_valid_plant_target(target):
		_send_message(user, "You can only analyze plants with this.")
		return false
	
	if user.global_position.distance_to(target.global_position) > scan_range:
		_send_message(user, "You need to be closer to analyze that plant.")
		return false
	
	_send_message(user, "You begin analyzing " + target.name + "...")
	
	await get_tree().create_timer(2.0).timeout
	
	var plant_data = _get_plant_analysis(target)
	_display_analysis_results(user, plant_data)
	emit_signal("plant_analyzed", self, target, plant_data)
	
	return true

func _water_plant(user, target) -> bool:
	if current_water <= 0:
		_send_message(user, "The watering can is empty!")
		return false
	
	if not _is_valid_plant_target(target):
		_send_message(user, "You can only water plants with this.")
		return false
	
	var water_needed = 10.0
	if target.has_method("get_water_need"):
		water_needed = target.get_water_need()
	
	if water_needed <= 0:
		_send_message(user, target.name + " doesn't need water right now.")
		return false
	
	var water_given = min(current_water, water_needed)
	current_water -= water_given
	
	if target.has_method("add_water"):
		target.add_water(water_given)
	
	_send_message(user, "You water " + target.name + " with " + str(water_given) + " units of water.")
	emit_signal("plant_watered", self, target, water_given)
	
	return true

func _plant_seeds(user, target) -> bool:
	if seed_count <= 0:
		_send_message(user, "No seeds left in the packet!")
		return false
	
	if not target.has_method("can_plant_seeds"):
		_send_message(user, "You can't plant seeds there.")
		return false
	
	if not target.can_plant_seeds():
		_send_message(user, "The soil isn't suitable for planting.")
		return false
	
	var seeds_to_plant = min(seed_count, 1)  # Plant one seed at a time
	
	_send_message(user, "You plant " + str(seeds_to_plant) + " " + seed_type + " seed(s).")
	
	if target.has_method("plant_seeds"):
		target.plant_seeds(seed_type, seeds_to_plant)
	
	seed_count -= seeds_to_plant
	emit_signal("seeds_planted", self, target.global_position, seed_type, seeds_to_plant)
	
	if seed_count <= 0:
		_send_message(user, "The seed packet is now empty.")
		queue_free()
	
	return true

func _apply_fertilizer(user, target) -> bool:
	if uses_remaining <= 0:
		_send_message(user, "No fertilizer left!")
		return false
	
	if not _is_valid_plant_target(target):
		_send_message(user, "You can only use fertilizer on plants.")
		return false
	
	if target.has_method("add_nutrients"):
		target.add_nutrients(nutrient_value)
		uses_remaining -= 1
		_send_message(user, "You apply fertilizer to " + target.name + ".")
		return true
	
	return false

func _collect_plant(user, target) -> bool:
	if not _is_valid_plant_target(target):
		_send_message(user, "You can only collect plants with this bag.")
		return false
	
	if target.has_method("can_harvest") and target.can_harvest():
		var harvest_result = target.harvest()
		if harvest_result.size() > 0:
			_add_to_collection(harvest_result)
			_send_message(user, "You harvest " + target.name + " and add it to your collection bag.")
			return true
		else:
			_send_message(user, target.name + " has nothing to harvest.")
			return false
	
	_send_message(user, target.name + " is not ready for harvest.")
	return false

func _kill_weeds(plant):
	if plant.has_method("remove_weeds"):
		var weeds_killed = plant.remove_weeds(weed_kill_strength)
		if weeds_killed > 0:
			emit_signal("weed_removed", self, plant, weeds_killed)

func _eliminate_pests(plant):
	if plant.has_method("remove_pests"):
		var pests_killed = plant.remove_pests(pest_kill_strength)
		if pests_killed > 0:
			emit_signal("pest_eliminated", self, plant, pests_killed)

func _apply_general_treatment(plant):
	if plant.has_method("apply_treatment"):
		plant.apply_treatment("general", 1.0)
		emit_signal("plant_treated", self, plant, "general")

func _apply_spray_toxicity(user):
	if user.has_method("get_health_system"):
		var health_system = user.get_health_system()
		if health_system and health_system.has_method("add_toxin"):
			health_system.add_toxin("chemical", toxicity)
			_send_message(user, "You accidentally inhale some of the spray! *cough*")

func _is_valid_plant_target(target) -> bool:
	return target.has_method("is_plant") and target.is_plant()

func _get_plant_analysis(plant) -> Dictionary:
	var data = {}
	
	if plant.has_method("get_health"):
		data["health"] = plant.get_health()
	
	if plant.has_method("get_growth_stage"):
		data["growth_stage"] = plant.get_growth_stage()
	
	if plant.has_method("get_water_level"):
		data["water_level"] = plant.get_water_level()
	
	if plant.has_method("get_nutrient_level"):
		data["nutrient_level"] = plant.get_nutrient_level()
	
	if plant.has_method("get_pest_count"):
		data["pest_count"] = plant.get_pest_count()
	
	if plant.has_method("get_weed_count"):
		data["weed_count"] = plant.get_weed_count()
	
	if plant.has_method("get_disease_status"):
		data["diseases"] = plant.get_disease_status()
	
	return data

func _display_analysis_results(user, data: Dictionary):
	var result_text = "=== PLANT ANALYSIS ===\n"
	
	for key in data.keys():
		var value = data[key]
		var formatted_key = key.replace("_", " ").capitalize()
		result_text += formatted_key + ": " + str(value) + "\n"
	
	if user.has_method("display_interface"):
		user.display_interface("plant_analysis", result_text)
	else:
		_send_message(user, result_text)

func _add_to_collection(items: Array):
	# Add harvested items to bag
	# This would depend on your inventory system
	pass

func refill_water(user, water_source) -> bool:
	if tool_type != PlantToolType.WATERING_CAN:
		return false
	
	if current_water >= water_capacity:
		_send_message(user, "The watering can is already full.")
		return false
	
	if water_source.has_method("transfer_water"):
		var water_needed = water_capacity - current_water
		var water_transferred = water_source.transfer_water(water_needed)
		current_water += water_transferred
		_send_message(user, "You refill the watering can.")
		return true
	
	return false

func refill_spray(user, chemical_source) -> bool:
	if tool_type != PlantToolType.PLANT_SPRAY and tool_type != PlantToolType.WEED_KILLER and tool_type != PlantToolType.PEST_SPRAY:
		return false
	
	if uses_remaining >= 20:
		_send_message(user, "The spray bottle is already full.")
		return false
	
	if chemical_source.has_method("get_chemical_type"):
		if chemical_source.get_chemical_type() == chemical_type:
			uses_remaining = 20
			_send_message(user, "You refill the spray bottle.")
			return true
	
	_send_message(user, "That chemical isn't compatible with this spray bottle.")
	return false

func _send_message(entity, message: String):
	if entity and entity.has_method("display_message"):
		entity.display_message(message)

func get_examine_text() -> String:
	var text = super.get_examine_text()
	
	match tool_type:
		PlantToolType.PLANT_SPRAY, PlantToolType.WEED_KILLER, PlantToolType.PEST_SPRAY:
			text += "\nUses remaining: " + str(uses_remaining) + "/20"
			if toxicity > 0:
				text += "\nToxicity level: " + str(toxicity)
		PlantToolType.WATERING_CAN:
			text += "\nWater: " + str(int(current_water)) + "/" + str(int(water_capacity))
		PlantToolType.SEED_PACKET:
			text += "\nSeeds remaining: " + str(seed_count)
			text += "\nSeed type: " + seed_type
		PlantToolType.FERTILIZER:
			text += "\nUses remaining: " + str(uses_remaining)
			text += "\nNutrient value: " + str(nutrient_value)
		PlantToolType.PLANT_ANALYZER:
			text += "\nScan range: " + str(scan_range) + " units"
	
	return text

# Specialized hydroponics tool classes
class AdvancedPlantAnalyzer extends HydroponicsTool:
	func _init():
		super._init()
		tool_type = PlantToolType.PLANT_ANALYZER
		item_name = "Advanced Plant Analyzer"
		description = "A high-tech plant analysis device with detailed scanning."
		detailed_scan = true
		scan_range = 64.0
		_initialize_plant_tool()

class IndustrialWateringSystem extends HydroponicsTool:
	func _init():
		super._init()
		tool_type = PlantToolType.WATERING_CAN
		item_name = "Industrial Watering System"
		description = "A large-capacity watering system for commercial growing."
		water_capacity = 500.0
		current_water = water_capacity
		w_class = 3
		_initialize_plant_tool()

class OrganicFertilizer extends HydroponicsTool:
	func _init():
		super._init()
		tool_type = PlantToolType.FERTILIZER
		item_name = "Organic Fertilizer"
		description = "Eco-friendly organic fertilizer for sustainable growing."
		nutrient_value = 75.0
		uses_remaining = 15
		toxicity = 0.0  # No toxicity
		_initialize_plant_tool()

class PremiumSeedPacket extends HydroponicsTool:
	func _init():
		super._init()
		tool_type = PlantToolType.SEED_PACKET
		item_name = "Premium Seed Collection"
		description = "A collection of high-quality hybrid seeds."
		seed_count = 10
		seed_type = "hybrid_tomato"
		_initialize_plant_tool()

class ProfessionalSprayKit extends HydroponicsTool:
	func _init():
		super._init()
		tool_type = PlantToolType.PEST_SPRAY
		item_name = "Professional Pest Control Kit"
		description = "Industrial-strength pest elimination system."
		uses_remaining = 30
		pest_kill_strength = 10.0
		toxicity = 8.0
		spray_range = 96.0
		_initialize_plant_tool()

# Factory methods
static func create_mini_hoe() -> HydroponicsTool:
	var tool = HydroponicsTool.new()
	tool.tool_type = PlantToolType.MINI_HOE
	tool._initialize_plant_tool()
	return tool

static func create_plant_spray() -> HydroponicsTool:
	var tool = HydroponicsTool.new()
	tool.tool_type = PlantToolType.PLANT_SPRAY
	tool._initialize_plant_tool()
	return tool

static func create_weed_killer() -> HydroponicsTool:
	var tool = HydroponicsTool.new()
	tool.tool_type = PlantToolType.WEED_KILLER
	tool._initialize_plant_tool()
	return tool

static func create_watering_can() -> HydroponicsTool:
	var tool = HydroponicsTool.new()
	tool.tool_type = PlantToolType.WATERING_CAN
	tool._initialize_plant_tool()
	return tool

static func create_plant_analyzer() -> HydroponicsTool:
	var tool = HydroponicsTool.new()
	tool.tool_type = PlantToolType.PLANT_ANALYZER
	tool._initialize_plant_tool()
	return tool
