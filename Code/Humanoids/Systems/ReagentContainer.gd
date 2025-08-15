extends Resource
class_name ReagentContainer

# === SIGNALS ===
signal reagent_added(reagent_id: String, amount: float)
signal reagent_removed(reagent_id: String, amount: float)
signal reaction_occurred(reaction_name: String, products: Array)
signal volume_changed(new_volume: float, max_volume: float)
signal container_emptied()
signal container_full()
signal explosive_reaction(power: float)
signal fire_reaction(intensity: float, duration: float)

# === CORE PROPERTIES ===
@export var reagent_list: Array[Reagent] = []
@export var total_volume: float = 0.0
@export var maximum_volume: float = 100.0
@export var container_type: String = "generic"  # For reaction requirements

# === REACTION PROPERTIES ===
@export var allow_reactions: bool = true
@export var temperature: float = 293.15  # Room temperature in Kelvin
@export var pressure: float = 101.325  # Standard atmospheric pressure in kPa
@export var is_sealed: bool = false

# === FLAGS ===
@export var locked: bool = false  # Prevents modifications
@export var no_reactions: bool = false  # Disables all reactions

# === REFERENCES ===
var parent_entity = null
var reaction_manager = null

func _init(max_vol: float = 100.0):
	maximum_volume = max_vol
	
	# Get global reaction manager
	if Engine.has_singleton("ReactionManager"):
		reaction_manager = Engine.get_singleton("ReactionManager")

# === CORE REAGENT MANAGEMENT ===
func add_reagent(reagent_id: String, amount: float, data: Dictionary = {}) -> float:
	"""Add reagent to container, returns actual amount added"""
	if locked or amount <= 0:
		return 0.0
	
	# Check volume constraints
	var available_space = maximum_volume - total_volume
	var actual_amount = min(amount, available_space)
	
	if actual_amount <= 0:
		emit_signal("container_full")
		return 0.0
	
	# Find existing reagent or create new one
	var existing_reagent = get_reagent(reagent_id)
	
	if existing_reagent:
		# Add to existing reagent
		existing_reagent.add_volume(actual_amount)
		
		# Merge data if provided
		if data.size() > 0:
			_merge_reagent_data(existing_reagent, data)
	else:
		# Create new reagent
		var new_reagent = _create_reagent_from_id(reagent_id, actual_amount)
		if new_reagent:
			if data.size() > 0:
				new_reagent.data = data.duplicate()
			reagent_list.append(new_reagent)
	
	# Update totals
	total_volume += actual_amount
	_update_container()
	
	# Emit signals
	emit_signal("reagent_added", reagent_id, actual_amount)
	emit_signal("volume_changed", total_volume, maximum_volume)
	
	# Process reactions if enabled
	if allow_reactions and not no_reactions:
		_process_reactions()
	
	return actual_amount

func remove_reagent(reagent_id: String, amount: float) -> float:
	"""Remove reagent from container, returns actual amount removed"""
	if locked or amount <= 0:
		return 0.0
	
	var reagent = get_reagent(reagent_id)
	if not reagent:
		return 0.0
	
	var removed_amount = reagent.remove_volume(amount)
	
	# Remove reagent if volume is too low
	if reagent.volume < 0.1:
		reagent_list.erase(reagent)
	
	# Update totals
	total_volume = max(0.0, total_volume - removed_amount)
	_update_container()
	
	# Emit signals
	emit_signal("reagent_removed", reagent_id, removed_amount)
	emit_signal("volume_changed", total_volume, maximum_volume)
	
	if total_volume <= 0:
		emit_signal("container_emptied")
	
	return removed_amount

func get_reagent(reagent_id: String) -> Reagent:
	"""Get reagent by ID"""
	for reagent in reagent_list:
		if reagent.id == reagent_id:
			return reagent
	return null

func get_reagent_amount(reagent_id: String) -> float:
	"""Get amount of specific reagent"""
	var reagent = get_reagent(reagent_id)
	return reagent.volume if reagent else 0.0

func has_reagent(reagent_id: String, minimum_amount: float = 0.1) -> bool:
	"""Check if container has reagent in sufficient quantity"""
	return get_reagent_amount(reagent_id) >= minimum_amount

func clear_reagents():
	"""Remove all reagents"""
	if locked:
		return
	
	reagent_list.clear()
	total_volume = 0.0
	_update_container()
	emit_signal("container_emptied")
	emit_signal("volume_changed", 0.0, maximum_volume)

# === TRANSFER METHODS ===
func transfer_to(target_container: ReagentContainer, amount: float) -> float:
	"""Transfer reagents to another container"""
	if locked or target_container.locked or total_volume <= 0:
		return 0.0
	
	amount = min(amount, total_volume)
	amount = min(amount, target_container.maximum_volume - target_container.total_volume)
	
	if amount <= 0:
		return 0.0
	
	var transfer_ratio = amount / total_volume
	var total_transferred = 0.0
	
	# Transfer proportional amounts of each reagent
	for reagent in reagent_list.duplicate():  # Duplicate to avoid modification during iteration
		var transfer_amount = reagent.volume * transfer_ratio
		if transfer_amount > 0.1:
			var transferred = remove_reagent(reagent.id, transfer_amount)
			target_container.add_reagent(reagent.id, transferred, reagent.data)
			total_transferred += transferred
	
	return total_transferred

func transfer_reagent_to(target_container: ReagentContainer, reagent_id: String, amount: float) -> float:
	"""Transfer specific reagent to another container"""
	if locked or target_container.locked:
		return 0.0
	
	var reagent = get_reagent(reagent_id)
	if not reagent:
		return 0.0
	
	amount = min(amount, reagent.volume)
	amount = min(amount, target_container.maximum_volume - target_container.total_volume)
	
	if amount <= 0:
		return 0.0
	
	var removed = remove_reagent(reagent_id, amount)
	target_container.add_reagent(reagent_id, removed, reagent.data)
	
	return removed

func copy_to(target_container: ReagentContainer, amount: float) -> float:
	"""Copy reagents to another container without removing from this one"""
	if total_volume <= 0:
		return 0.0
	
	amount = min(amount, total_volume)
	amount = min(amount, target_container.maximum_volume - target_container.total_volume)
	
	if amount <= 0:
		return 0.0
	
	var copy_ratio = amount / total_volume
	var total_copied = 0.0
	
	for reagent in reagent_list:
		var copy_amount = reagent.volume * copy_ratio
		if copy_amount > 0.1:
			target_container.add_reagent(reagent.id, copy_amount, reagent.data)
			total_copied += copy_amount
	
	return total_copied

# === REACTION PROCESSING ===
func _process_reactions():
	"""Process chemical reactions between reagents"""
	if no_reactions or not reaction_manager:
		return
	
	var reactions_occurred = true
	var safety_counter = 0
	
	# Keep processing until no more reactions occur
	while reactions_occurred and safety_counter < 20:
		reactions_occurred = false
		safety_counter += 1
		
		# Get all possible reactions
		var possible_reactions = reaction_manager.get_possible_reactions(self)
		
		for reaction in possible_reactions:
			if _can_reaction_occur(reaction):
				_execute_reaction(reaction)
				reactions_occurred = true
				break  # Process one reaction at a time

func _can_reaction_occur(reaction) -> bool:
	"""Check if a reaction can occur with current reagents"""
	if not reaction:
		return false
	
	# Check required reagents
	for required_id in reaction.required_reagents:
		var required_amount = reaction.required_reagents[required_id]
		if not has_reagent(required_id, required_amount):
			return false
	
	# Check catalysts
	if reaction.required_catalysts:
		for catalyst_id in reaction.required_catalysts:
			var catalyst_amount = reaction.required_catalysts[catalyst_id]
			if not has_reagent(catalyst_id, catalyst_amount):
				return false
	
	# Check temperature requirements
	if reaction.has("min_temperature") and temperature < reaction.min_temperature:
		return false
	if reaction.has("max_temperature") and temperature > reaction.max_temperature:
		return false
	
	# Check container requirements
	if reaction.has("required_container") and container_type != reaction.required_container:
		return false
	
	return true

func _execute_reaction(reaction):
	"""Execute a chemical reaction"""
	if not reaction:
		return
	
	# Calculate reaction multiplier based on limiting reagent
	var multiplier = _calculate_reaction_multiplier(reaction)
	if multiplier <= 0:
		return
	
	# Remove required reagents
	for required_id in reaction.required_reagents:
		var required_amount = reaction.required_reagents[required_id] * multiplier
		remove_reagent(required_id, required_amount)
	
	# Add products
	for product_id in reaction.products:
		var product_amount = reaction.products[product_id] * multiplier
		add_reagent(product_id, product_amount)
	
	# Special reaction effects
	_handle_reaction_effects(reaction, multiplier)
	
	# Emit signal
	emit_signal("reaction_occurred", reaction.name, reaction.products.keys())

func _calculate_reaction_multiplier(reaction) -> float:
	"""Calculate how many times a reaction can occur"""
	var multiplier = 999999.0
	
	for required_id in reaction.required_reagents:
		var required_amount = reaction.required_reagents[required_id]
		var available_amount = get_reagent_amount(required_id)
		var possible_multiplier = available_amount / required_amount
		multiplier = min(multiplier, possible_multiplier)
	
	return floor(multiplier)

func _handle_reaction_effects(reaction, multiplier: float):
	"""Handle special effects from reactions"""
	if not reaction.has("effects"):
		return
	
	for effect in reaction.effects:
		match effect:
			"explosive":
				var power = reaction.get("explosive_power", 10.0) * multiplier
				_handle_explosive_reaction(power)
			"fire":
				var intensity = reaction.get("fire_intensity", 5.0) * multiplier
				var duration = reaction.get("fire_duration", 10.0)
				_handle_fire_reaction(intensity, duration)
			"heat":
				var heat_amount = reaction.get("heat_amount", 50.0) * multiplier
				temperature += heat_amount
			"cool":
				var cool_amount = reaction.get("cool_amount", 50.0) * multiplier
				temperature -= cool_amount
			"bubble":
				_handle_bubble_effect()

func _handle_explosive_reaction(power: float):
	"""Handle explosive reaction"""
	if parent_entity and parent_entity.has_method("create_explosion"):
		parent_entity.create_explosion(power)
	
	emit_signal("explosive_reaction", power)
	
	# Clear container after explosion
	clear_reagents()

func _handle_fire_reaction(intensity: float, duration: float):
	"""Handle fire-creating reaction"""
	if parent_entity and parent_entity.has_method("create_fire"):
		parent_entity.create_fire(intensity, duration)
	
	emit_signal("fire_reaction", intensity, duration)

func _handle_bubble_effect():
	"""Handle bubbling effect"""
	if parent_entity and parent_entity.has_method("create_bubbles"):
		parent_entity.create_bubbles()

# === METABOLISM PROCESSING ===
func process_metabolism(target, delta_time: float):
	"""Process reagent metabolism in a living entity"""
	if locked or reagent_list.size() == 0:
		return
	
	var reagents_to_remove = []
	
	for reagent in reagent_list:
		# Process reagent effects
		reagent.process_effects(target, delta_time, self)
		
		# Metabolize reagent
		if not reagent.has_flag(Reagent.FLAG_NO_METABOLISM):
			var metabolism_amount = reagent.custom_metabolism * delta_time
			reagent.remove_volume(metabolism_amount)
			
			# Mark for removal if depleted
			if reagent.volume < 0.1:
				reagents_to_remove.append(reagent)
	
	# Remove depleted reagents
	for reagent in reagents_to_remove:
		reagent_list.erase(reagent)
	
	_update_container()

# === UTILITY METHODS ===
func _update_container():
	"""Update container state"""
	# Recalculate total volume
	total_volume = 0.0
	for reagent in reagent_list:
		total_volume += reagent.volume
	
	# Remove empty reagents
	reagent_list = reagent_list.filter(func(r): return r.volume >= 0.1)

func _merge_reagent_data(reagent: Reagent, new_data: Dictionary):
	"""Merge data into existing reagent"""
	for key in new_data:
		reagent.data[key] = new_data[key]

func _create_reagent_from_id(reagent_id: String, volume: float) -> Reagent:
	"""Create reagent from ID using reagent database"""
	if reaction_manager and reaction_manager.has_method("create_reagent"):
		return reaction_manager.create_reagent(reagent_id, volume)
	
	# Fallback: create basic reagent
	var reagent = Reagent.new(reagent_id, volume)
	reagent.name = reagent_id.capitalize()
	return reagent

# === COLOR AND APPEARANCE ===
func get_mixed_color() -> Color:
	"""Get color of mixed reagents"""
	if reagent_list.size() == 0:
		return Color.TRANSPARENT
	
	if reagent_list.size() == 1:
		return reagent_list[0].color
	
	# Mix colors based on volume ratios
	var total_r = 0.0
	var total_g = 0.0
	var total_b = 0.0
	var total_a = 0.0
	
	for reagent in reagent_list:
		var ratio = reagent.volume / total_volume
		total_r += reagent.color.r * ratio
		total_g += reagent.color.g * ratio
		total_b += reagent.color.b * ratio
		total_a += reagent.color.a * ratio
	
	return Color(total_r, total_g, total_b, total_a)

func get_dominant_reagent() -> Reagent:
	"""Get reagent with highest volume"""
	if reagent_list.size() == 0:
		return null
	
	var dominant = reagent_list[0]
	for reagent in reagent_list:
		if reagent.volume > dominant.volume:
			dominant = reagent
	
	return dominant

func get_reagent_names() -> Array:
	"""Get array of reagent names"""
	var names = []
	for reagent in reagent_list:
		names.append(reagent.name)
	return names

func get_description() -> String:
	"""Get description of container contents"""
	if total_volume == 0:
		return "Empty"
	
	var desc = "Contains " + str(total_volume) + "/" + str(maximum_volume) + " units:\n"
	
	for reagent in reagent_list:
		desc += "• " + reagent.name + " (" + str(reagent.volume) + " units)\n"
	
	return desc.trim_suffix("\n")

# === ANALYSIS METHODS ===
func is_dangerous() -> bool:
	"""Check if container contains dangerous reagents"""
	for reagent in reagent_list:
		if reagent.is_harmful():
			return true
	return false

func is_medical() -> bool:
	"""Check if container contains medical reagents"""
	for reagent in reagent_list:
		if reagent.is_medical:
			return true
	return false

func is_food() -> bool:
	"""Check if container contains food reagents"""
	for reagent in reagent_list:
		if reagent.is_food:
			return true
	return false

func get_total_nutrition() -> float:
	"""Get total nutritional value"""
	var nutrition = 0.0
	for reagent in reagent_list:
		nutrition += reagent.nutriment_factor * reagent.volume
	return nutrition

# === SAVING/LOADING ===
func to_dict() -> Dictionary:
	"""Convert container to dictionary for saving"""
	var reagent_data = []
	for reagent in reagent_list:
		reagent_data.append(reagent.to_dict())
	
	return {
		"reagents": reagent_data,
		"total_volume": total_volume,
		"maximum_volume": maximum_volume,
		"container_type": container_type,
		"temperature": temperature,
		"pressure": pressure,
		"is_sealed": is_sealed,
		"locked": locked,
		"no_reactions": no_reactions
	}

func from_dict(dict: Dictionary):
	"""Load container from dictionary"""
	clear_reagents()
	
	if dict.has("maximum_volume"):
		maximum_volume = dict.maximum_volume
	if dict.has("container_type"):
		container_type = dict.container_type
	if dict.has("temperature"):
		temperature = dict.temperature
	if dict.has("pressure"):
		pressure = dict.pressure
	if dict.has("is_sealed"):
		is_sealed = dict.is_sealed
	if dict.has("locked"):
		locked = dict.locked
	if dict.has("no_reactions"):
		no_reactions = dict.no_reactions
	
	# Load reagents
	if dict.has("reagents"):
		for reagent_dict in dict.reagents:
			var reagent = Reagent.new()
			reagent.from_dict(reagent_dict)
			reagent_list.append(reagent)
	
	_update_container()
