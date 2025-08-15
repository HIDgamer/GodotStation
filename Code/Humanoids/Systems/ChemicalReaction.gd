extends Resource
class_name ChemicalReaction

# === CORE PROPERTIES ===
@export var id: String = ""
@export var name: String = ""
@export var description: String = ""

# === REACTION REQUIREMENTS ===
@export var required_reagents: Dictionary = {}  # reagent_id -> required_amount
@export var required_catalysts: Dictionary = {}  # catalyst_id -> required_amount
@export var required_container: String = ""  # Specific container type needed
@export var mob_react: bool = true  # Can reaction occur inside living entities
@export var requires_heating: bool = false

# === TEMPERATURE REQUIREMENTS ===
@export var min_temperature: float = 0.0  # Minimum temperature in Kelvin
@export var max_temperature: float = 1000.0  # Maximum temperature in Kelvin
@export var optimal_temperature: float = 293.15  # Optimal temperature

# === PRODUCTS ===
@export var products: Dictionary = {}  # product_id -> amount_produced
@export var secondary_products: Dictionary = {}  # secondary_product_id -> amount

# === REACTION PROPERTIES ===
@export var result_amount_multiplier: float = 1.0  # Multiplier for product amounts
@export var efficiency: float = 1.0  # How efficiently reagents convert (0.0-1.0)
@export var reaction_rate: float = 1.0  # How quickly reaction occurs
@export var reversible: bool = false  # Can reaction be reversed

# === SPECIAL EFFECTS ===
@export var effects: Array[String] = []  # Special effects: "explosive", "fire", "heat", etc.
@export var explosive_power: float = 0.0
@export var fire_intensity: float = 0.0
@export var fire_duration: float = 0.0
@export var heat_amount: float = 0.0  # Temperature change
@export var creates_sound: bool = false
@export var sound_effect: String = ""

# === CLASSIFICATION ===
@export var reaction_tier: int = 1  # Difficulty/rarity tier (1-5)
@export var is_secret: bool = false  # Hidden from normal analysis
@export var is_dangerous: bool = false  # Marked as dangerous reaction

# === CONDITIONS ===
@export var pressure_sensitive: bool = false
@export var min_pressure: float = 0.0
@export var max_pressure: float = 1000.0
@export var light_sensitive: bool = false
@export var requires_darkness: bool = false

func _init(reaction_id: String = ""):
	if reaction_id != "":
		id = reaction_id

# === CORE METHODS ===
func can_occur(container: ReagentContainer) -> bool:
	"""Check if reaction can occur in given container"""
	
	# Check required reagents
	for reagent_id in required_reagents:
		var required_amount = required_reagents[reagent_id]
		if not container.has_reagent(reagent_id, required_amount):
			return false
	
	# Check catalysts
	for catalyst_id in required_catalysts:
		var catalyst_amount = required_catalysts[catalyst_id]
		if not container.has_reagent(catalyst_id, catalyst_amount):
			return false
	
	# Check container type
	if required_container != "" and container.container_type != required_container:
		return false
	
	# Check temperature
	if container.temperature < min_temperature or container.temperature > max_temperature:
		return false
	
	# Check pressure
	if pressure_sensitive:
		if container.pressure < min_pressure or container.pressure > max_pressure:
			return false
	
	# Check mob compatibility
	if not mob_react and container.parent_entity and container.parent_entity.has_method("is_living"):
		if container.parent_entity.is_living():
			return false
	
	# Check heating requirements
	if requires_heating and container.temperature <= optimal_temperature:
		return false
	
	return true

func calculate_multiplier(container: ReagentContainer) -> float:
	"""Calculate how many times reaction can occur"""
	var multiplier = 999999.0
	
	# Find limiting reagent
	for reagent_id in required_reagents:
		var required_amount = required_reagents[reagent_id]
		var available_amount = container.get_reagent_amount(reagent_id)
		var possible_multiplier = available_amount / required_amount
		multiplier = min(multiplier, possible_multiplier)
	
	# Apply efficiency
	multiplier *= efficiency
	
	# Apply temperature efficiency
	var temp_efficiency = _calculate_temperature_efficiency(container.temperature)
	multiplier *= temp_efficiency
	
	return floor(multiplier)

func _calculate_temperature_efficiency(temperature: float) -> float:
	"""Calculate efficiency based on temperature"""
	if temperature < min_temperature or temperature > max_temperature:
		return 0.0
	
	# Maximum efficiency at optimal temperature
	if abs(temperature - optimal_temperature) < 5.0:
		return 1.0
	
	# Reduced efficiency away from optimal
	var temp_diff = abs(temperature - optimal_temperature)
	var max_diff = max(optimal_temperature - min_temperature, max_temperature - optimal_temperature)
	
	return max(0.1, 1.0 - (temp_diff / max_diff))

func execute(container: ReagentContainer) -> bool:
	"""Execute the reaction in given container"""
	if not can_occur(container):
		return false
	
	var multiplier = calculate_multiplier(container)
	if multiplier <= 0:
		return false
	
	# Remove required reagents
	for reagent_id in required_reagents:
		var required_amount = required_reagents[reagent_id] * multiplier
		container.remove_reagent(reagent_id, required_amount)
	
	# Catalysts are not consumed, just check they exist
	
	# Add products
	for product_id in products:
		var product_amount = products[product_id] * multiplier * result_amount_multiplier
		container.add_reagent(product_id, product_amount)
	
	# Add secondary products
	for secondary_id in secondary_products:
		var secondary_amount = secondary_products[secondary_id] * multiplier * result_amount_multiplier
		container.add_reagent(secondary_id, secondary_amount)
	
	# Apply special effects
	_apply_reaction_effects(container, multiplier)
	
	return true

func _apply_reaction_effects(container: ReagentContainer, multiplier: float):
	"""Apply special effects from the reaction"""
	for effect in effects:
		match effect:
			"explosive":
				_apply_explosive_effect(container, multiplier)
			"fire":
				_apply_fire_effect(container, multiplier)
			"heat":
				container.temperature += heat_amount * multiplier
			"cool":
				container.temperature -= heat_amount * multiplier
			"bubble":
				_apply_bubble_effect(container)
			"foam":
				_apply_foam_effect(container, multiplier)
			"smoke":
				_apply_smoke_effect(container, multiplier)
			"flash":
				_apply_flash_effect(container)
			"emp":
				_apply_emp_effect(container, multiplier)
	
	# Play sound effects
	if creates_sound and sound_effect != "":
		_play_sound_effect(container)

func _apply_explosive_effect(container: ReagentContainer, multiplier: float):
	"""Apply explosive effects"""
	var power = explosive_power * multiplier
	
	if container.parent_entity:
		if container.parent_entity.has_method("create_explosion"):
			container.parent_entity.create_explosion(power)
		
		# Damage container
		if container.parent_entity.has_method("take_damage"):
			container.parent_entity.take_damage(power * 10, "explosive")
	
	# Clear container contents (explosion destroys reagents)
	container.clear_reagents()

func _apply_fire_effect(container: ReagentContainer, multiplier: float):
	"""Apply fire creation effects"""
	var intensity = fire_intensity * multiplier
	var duration = fire_duration
	
	if container.parent_entity:
		if container.parent_entity.has_method("create_fire"):
			container.parent_entity.create_fire(intensity, duration)
		
		# Heat damage to container
		if container.parent_entity.has_method("take_damage"):
			container.parent_entity.take_damage(intensity * 2, "fire")

func _apply_bubble_effect(container: ReagentContainer):
	"""Apply bubbling visual effect"""
	if container.parent_entity and container.parent_entity.has_method("create_bubbles"):
		container.parent_entity.create_bubbles()

func _apply_foam_effect(container: ReagentContainer, multiplier: float):
	"""Apply foam creation effect"""
	if container.parent_entity and container.parent_entity.has_method("create_foam"):
		container.parent_entity.create_foam(multiplier)

func _apply_smoke_effect(container: ReagentContainer, multiplier: float):
	"""Apply smoke creation effect"""
	if container.parent_entity and container.parent_entity.has_method("create_smoke"):
		container.parent_entity.create_smoke(multiplier)

func _apply_flash_effect(container: ReagentContainer):
	"""Apply flash effect"""
	if container.parent_entity and container.parent_entity.has_method("create_flash"):
		container.parent_entity.create_flash()

func _apply_emp_effect(container: ReagentContainer, multiplier: float):
	"""Apply EMP effect"""
	if container.parent_entity and container.parent_entity.has_method("create_emp"):
		container.parent_entity.create_emp(multiplier)

func _play_sound_effect(container: ReagentContainer):
	"""Play sound effect"""
	if container.parent_entity and container.parent_entity.has_method("play_sound"):
		container.parent_entity.play_sound(sound_effect)

# === ANALYSIS METHODS ===
func get_required_reagent_names() -> Array:
	"""Get names of required reagents"""
	var names = []
	for reagent_id in required_reagents:
		names.append(reagent_id.capitalize())
	return names

func get_product_names() -> Array:
	"""Get names of products"""
	var names = []
	for product_id in products:
		names.append(product_id.capitalize())
	return names

func get_difficulty_rating() -> String:
	"""Get difficulty rating as string"""
	match reaction_tier:
		1:
			return "Basic"
		2:
			return "Simple"
		3:
			return "Moderate"
		4:
			return "Advanced"
		5:
			return "Expert"
		_:
			return "Unknown"

func is_simple_reaction() -> bool:
	"""Check if this is a simple reaction (tier 1-2)"""
	return reaction_tier <= 2

func requires_special_conditions() -> bool:
	"""Check if reaction requires special conditions"""
	return (required_container != "" or requires_heating or 
			pressure_sensitive or light_sensitive or requires_darkness)

func get_safety_rating() -> String:
	"""Get safety rating"""
	if is_dangerous or "explosive" in effects or "fire" in effects:
		return "Dangerous"
	elif "heat" in effects or "smoke" in effects:
		return "Caution"
	else:
		return "Safe"

# === UTILITY METHODS ===
func get_total_required_volume() -> float:
	"""Get total volume of required reagents"""
	var total = 0.0
	for reagent_id in required_reagents:
		total += required_reagents[reagent_id]
	return total

func get_total_product_volume() -> float:
	"""Get total volume of products"""
	var total = 0.0
	for product_id in products:
		total += products[product_id]
	for secondary_id in secondary_products:
		total += secondary_products[secondary_id]
	return total * result_amount_multiplier

func is_balanced() -> bool:
	"""Check if reaction is volume-balanced"""
	var required_vol = get_total_required_volume()
	var product_vol = get_total_product_volume()
	return abs(required_vol - product_vol) < 1.0

func get_description_text() -> String:
	"""Get full description of reaction"""
	var desc = description
	
	if desc == "":
		desc = "Chemical reaction producing " + str(get_product_names())
	
	desc += "\n\nRequired: "
	for reagent_id in required_reagents:
		desc += reagent_id.capitalize() + " (" + str(required_reagents[reagent_id]) + "), "
	desc = desc.trim_suffix(", ")
	
	if required_catalysts.size() > 0:
		desc += "\nCatalysts: "
		for catalyst_id in required_catalysts:
			desc += catalyst_id.capitalize() + " (" + str(required_catalysts[catalyst_id]) + "), "
		desc = desc.trim_suffix(", ")
	
	desc += "\nProduces: "
	for product_id in products:
		desc += product_id.capitalize() + " (" + str(products[product_id]) + "), "
	desc = desc.trim_suffix(", ")
	
	if requires_special_conditions():
		desc += "\n\nSpecial conditions required."
	
	if is_dangerous:
		desc += "\n[color=red]WARNING: Dangerous reaction![/color]"
	
	return desc

# === SAVING/LOADING ===
func to_dict() -> Dictionary:
	"""Convert reaction to dictionary"""
	return {
		"id": id,
		"name": name,
		"description": description,
		"required_reagents": required_reagents,
		"required_catalysts": required_catalysts,
		"required_container": required_container,
		"mob_react": mob_react,
		"requires_heating": requires_heating,
		"min_temperature": min_temperature,
		"max_temperature": max_temperature,
		"optimal_temperature": optimal_temperature,
		"products": products,
		"secondary_products": secondary_products,
		"result_amount_multiplier": result_amount_multiplier,
		"efficiency": efficiency,
		"reaction_rate": reaction_rate,
		"reversible": reversible,
		"effects": effects,
		"explosive_power": explosive_power,
		"fire_intensity": fire_intensity,
		"fire_duration": fire_duration,
		"heat_amount": heat_amount,
		"creates_sound": creates_sound,
		"sound_effect": sound_effect,
		"reaction_tier": reaction_tier,
		"is_secret": is_secret,
		"is_dangerous": is_dangerous,
		"pressure_sensitive": pressure_sensitive,
		"min_pressure": min_pressure,
		"max_pressure": max_pressure,
		"light_sensitive": light_sensitive,
		"requires_darkness": requires_darkness
	}

func from_dict(dict: Dictionary):
	"""Load reaction from dictionary"""
	if dict.has("id"): id = dict.id
	if dict.has("name"): name = dict.name
	if dict.has("description"): description = dict.description
	if dict.has("required_reagents"): required_reagents = dict.required_reagents
	if dict.has("required_catalysts"): required_catalysts = dict.required_catalysts
	if dict.has("required_container"): required_container = dict.required_container
	if dict.has("mob_react"): mob_react = dict.mob_react
	if dict.has("requires_heating"): requires_heating = dict.requires_heating
	if dict.has("min_temperature"): min_temperature = dict.min_temperature
	if dict.has("max_temperature"): max_temperature = dict.max_temperature
	if dict.has("optimal_temperature"): optimal_temperature = dict.optimal_temperature
	if dict.has("products"): products = dict.products
	if dict.has("secondary_products"): secondary_products = dict.secondary_products
	if dict.has("result_amount_multiplier"): result_amount_multiplier = dict.result_amount_multiplier
	if dict.has("efficiency"): efficiency = dict.efficiency
	if dict.has("reaction_rate"): reaction_rate = dict.reaction_rate
	if dict.has("reversible"): reversible = dict.reversible
	if dict.has("effects"): effects = dict.effects
	if dict.has("explosive_power"): explosive_power = dict.explosive_power
	if dict.has("fire_intensity"): fire_intensity = dict.fire_intensity
	if dict.has("fire_duration"): fire_duration = dict.fire_duration
	if dict.has("heat_amount"): heat_amount = dict.heat_amount
	if dict.has("creates_sound"): creates_sound = dict.creates_sound
	if dict.has("sound_effect"): sound_effect = dict.sound_effect
	if dict.has("reaction_tier"): reaction_tier = dict.reaction_tier
	if dict.has("is_secret"): is_secret = dict.is_secret
	if dict.has("is_dangerous"): is_dangerous = dict.is_dangerous
	if dict.has("pressure_sensitive"): pressure_sensitive = dict.pressure_sensitive
	if dict.has("min_pressure"): min_pressure = dict.min_pressure
	if dict.has("max_pressure"): max_pressure = dict.max_pressure
	if dict.has("light_sensitive"): light_sensitive = dict.light_sensitive
	if dict.has("requires_darkness"): requires_darkness = dict.requires_darkness
