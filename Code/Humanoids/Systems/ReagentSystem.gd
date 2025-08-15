extends Node
class_name ReagentSystem

#region EXPORTS AND CONFIGURATION
@export_group("Container Settings")
@export var container_type: ContainerType = ContainerType.BLOODSTREAM
@export var maximum_volume: float = 100.0
@export var temperature: float = 310.15
@export var pressure: float = 101.325
@export var is_sealed: bool = false

@export_group("Processing Settings")
@export var allow_reactions: bool = true
@export var allow_metabolism: bool = true
@export var metabolism_rate_multiplier: float = 1.0
@export var process_interval: float = 1.0
@export var reaction_check_interval: float = 0.5
@export var max_reactions_per_cycle: int = 5

@export_group("Initial Configuration")
@export var initial_reagents: Dictionary = {}
@export var auto_purge_empty: bool = true

@export_group("Debug Settings")
@export var debug_mode: bool = false
@export var log_metabolism: bool = false
@export var log_reactions: bool = true
@export var log_overdoses: bool = true
#endregion

#region ENUMS
enum ContainerType {
	BLOODSTREAM,
	STOMACH,
	BEAKER,
	SYRINGE,
	BOTTLE,
	TANK,
	PILL,
	INHALER,
	IV_BAG,
	HYPOSPRAY
}
#endregion

#region SIGNALS
signal reagent_added(reagent_id: String, amount: float)
signal reagent_removed(reagent_id: String, amount: float)
signal reagent_metabolized(reagent_id: String, amount: float)
signal reaction_occurred(reaction_name: String, products: Array)
signal container_changed(new_volume: float, max_volume: float)
signal overdose_detected(reagent_id: String, amount: float)
signal metabolism_processed(reagents_processed: Array)
signal explosive_reaction(power: float)
signal fire_reaction(intensity: float, duration: float)
signal temperature_changed(new_temperature: float)
signal pressure_changed(new_pressure: float)
#endregion

#region PROPERTIES
# Core references
var entity = null
var health_system = null
var reagent_container: ReagentContainer = null
var health_connector = null

# Processing timers
var metabolism_timer: float = 0.0
var reaction_timer: float = 0.0
var last_metabolism_time: float = 0.0

# Multiplayer properties
var peer_id: int = 1
var is_local_player: bool = false

# Container type string mapping
var container_type_strings: Dictionary = {}
#endregion

#region INITIALIZATION
func _ready():
	"""Initialize the reagent system"""
	entity = get_parent()
	health_system = get_node_or_null("../HealthSystem")
	health_connector = get_node_or_null("../HealthConnector")
	
	_setup_container_type_mapping()
	_initialize_container()
	_connect_signals()
	_add_initial_reagents()
	_setup_multiplayer()
	
	if debug_mode:
		print("ReagentSystem: Initialized with container type: " + _get_container_type_string())

func _setup_container_type_mapping():
	"""Set up container type to string mapping"""
	container_type_strings = {
		ContainerType.BLOODSTREAM: "bloodstream",
		ContainerType.STOMACH: "stomach",
		ContainerType.BEAKER: "beaker",
		ContainerType.SYRINGE: "syringe",
		ContainerType.BOTTLE: "bottle",
		ContainerType.TANK: "tank",
		ContainerType.PILL: "pill",
		ContainerType.INHALER: "inhaler",
		ContainerType.IV_BAG: "iv_bag",
		ContainerType.HYPOSPRAY: "hypospray"
	}

func _initialize_container():
	"""Initialize the reagent container"""
	reagent_container = ReagentContainer.new(maximum_volume)
	reagent_container.container_type = _get_container_type_string()
	reagent_container.temperature = temperature
	reagent_container.pressure = pressure
	reagent_container.is_sealed = is_sealed
	reagent_container.parent_entity = entity
	reagent_container.allow_reactions = allow_reactions

func _connect_signals():
	"""Connect to reagent container signals"""
	if reagent_container:
		var signal_connections = [
			["reagent_added", "_on_reagent_added"],
			["reagent_removed", "_on_reagent_removed"],
			["reaction_occurred", "_on_reaction_occurred"],
			["volume_changed", "_on_volume_changed"],
			["explosive_reaction", "_on_explosive_reaction"],
			["fire_reaction", "_on_fire_reaction"]
		]
		
		for connection in signal_connections:
			var signal_name = connection[0]
			var method_name = connection[1]
			
			if reagent_container.has_signal(signal_name):
				if not reagent_container.is_connected(signal_name, Callable(self, method_name)):
					reagent_container.connect(signal_name, Callable(self, method_name))

func _add_initial_reagents():
	"""Add initial reagents to the container"""
	for reagent_id in initial_reagents:
		var amount = initial_reagents[reagent_id]
		add_reagent(reagent_id, amount)

func _setup_multiplayer():
	"""Configure multiplayer settings"""
	if entity and entity.has_meta("peer_id"):
		peer_id = entity.get_meta("peer_id")
		set_multiplayer_authority(peer_id)
		is_local_player = (multiplayer.get_unique_id() == peer_id)
#endregion

#region PROCESSING
func _process(delta):
	"""Process reagent metabolism and reactions"""
	if not reagent_container or not is_multiplayer_authority():
		return
	
	metabolism_timer += delta
	reaction_timer += delta
	
	if allow_metabolism and metabolism_timer >= process_interval:
		_process_metabolism(delta)
		metabolism_timer = 0.0
	
	if allow_reactions and reaction_timer >= reaction_check_interval:
		_check_reactions()
		reaction_timer = 0.0

func _process_metabolism(delta_time: float):
	"""Process reagent metabolism"""
	if not reagent_container or reagent_container.reagent_list.size() == 0:
		return
	
	if not _should_process_metabolism():
		return
	
	var processed_reagents = []
	var reagents_to_remove = []
	
	for reagent in reagent_container.reagent_list:
		# Process reagent effects on entity
		if entity:
			reagent.process_effects(entity, delta_time, reagent_container)
		
		# Handle metabolism
		if not reagent.has_flag(Reagent.FLAG_NO_METABOLISM):
			var metabolism_amount = reagent.custom_metabolism * metabolism_rate_multiplier * delta_time
			var metabolized = reagent.remove_volume(metabolism_amount)
			
			if metabolized > 0:
				processed_reagents.append({
					"id": reagent.id,
					"name": reagent.name,
					"metabolized": metabolized,
					"remaining": reagent.volume
				})
				
				if log_metabolism:
					print("ReagentSystem: Metabolized ", metabolized, " units of ", reagent.name)
				
				_sync_reagent_metabolized.rpc(reagent.id, metabolized)
		
		# Check for overdose
		_check_overdose(reagent)
		
		# Mark for removal if depleted
		if reagent.volume < 0.1:
			reagents_to_remove.append(reagent)
	
	# Remove depleted reagents
	for reagent in reagents_to_remove:
		reagent_container.reagent_list.erase(reagent)
	
	reagent_container._update_container()
	
	if processed_reagents.size() > 0:
		_sync_metabolism_processed.rpc(processed_reagents)

func _should_process_metabolism() -> bool:
	"""Check if metabolism should be processed for this container type"""
	match container_type:
		ContainerType.BLOODSTREAM, ContainerType.STOMACH:
			return entity and entity.has_method("is_living") and entity.is_living()
		ContainerType.PILL, ContainerType.INHALER:
			return false
		_:
			return true

func _check_reactions():
	"""Check for and process chemical reactions"""
	if not reagent_container or not allow_reactions:
		return
	
	var reaction_manager = _get_reaction_manager()
	if not reaction_manager:
		return
	
	var reactions_this_cycle = 0
	var possible_reactions = reaction_manager.get_possible_reactions(reagent_container)
	
	for reaction in possible_reactions:
		if reactions_this_cycle >= max_reactions_per_cycle:
			break
		
		if reaction.can_occur(reagent_container):
			reaction.execute(reagent_container)
			reactions_this_cycle += 1
			
			if log_reactions:
				print("ReagentSystem: Reaction occurred - ", reaction.name)

func _check_overdose(reagent: Reagent):
	"""Check for reagent overdose"""
	if reagent.overdose_threshold <= 0:
		return
	
	if reagent.volume > reagent.overdose_threshold:
		_sync_overdose_detected.rpc(reagent.id, reagent.volume)
		
		if log_overdoses:
			print("ReagentSystem: Overdose detected - ", reagent.name, " at ", reagent.volume, " units")
		
		_handle_overdose_effects(reagent)

func _handle_overdose_effects(reagent: Reagent):
	"""Handle overdose effects"""
	if not health_system:
		return
	
	var overdose_severity = reagent.volume / reagent.overdose_threshold
	
	# General toxicity from overdose
	health_system.adjustToxLoss(overdose_severity * 0.5, false)
	
	# Specific overdose effects
	match reagent.id:
		"tramadol":
			if overdose_severity > 2.0:
				health_system.add_status_effect("respiratory_depression", 30.0, overdose_severity)
		"bicaridine":
			if overdose_severity > 3.0:
				health_system.add_status_effect("alkalosis", 60.0, overdose_severity)
		"epinephrine":
			if overdose_severity > 1.5:
				health_system.add_status_effect("cardiac_stress", 45.0, overdose_severity)
		"dexalinp":
			if overdose_severity > 2.5:
				health_system.add_status_effect("oxygen_toxicity", 60.0, overdose_severity)
#endregion

#region REAGENT MANAGEMENT
func add_reagent(reagent_id: String, amount: float, data: Dictionary = {}) -> float:
	"""Add a reagent to the container"""
	if not is_multiplayer_authority():
		return 0.0
	
	if not reagent_container:
		return 0.0
	
	var added = reagent_container.add_reagent(reagent_id, amount, data)
	
	# Handle container-specific effects
	match container_type:
		ContainerType.BLOODSTREAM:
			_handle_bloodstream_addition(reagent_id, added)
		ContainerType.STOMACH:
			_handle_stomach_addition(reagent_id, added)
	
	if added > 0:
		_sync_reagent_added.rpc(reagent_id, added, data)
		
		if debug_mode:
			print("ReagentSystem: Added ", added, " units of ", reagent_id)
	
	return added

func remove_reagent(reagent_id: String, amount: float) -> float:
	"""Remove a reagent from the container"""
	if not is_multiplayer_authority():
		return 0.0
	
	if not reagent_container:
		return 0.0
	
	var removed = reagent_container.remove_reagent(reagent_id, amount)
	
	if removed > 0:
		_sync_reagent_removed.rpc(reagent_id, removed)
		
		if debug_mode:
			print("ReagentSystem: Removed ", removed, " units of ", reagent_id)
	
	return removed

func has_reagent(reagent_id: String, minimum_amount: float = 0.1) -> bool:
	"""Check if container has a specific reagent"""
	if not reagent_container:
		return false
	
	return reagent_container.has_reagent(reagent_id, minimum_amount)

func get_reagent_amount(reagent_id: String) -> float:
	"""Get the amount of a specific reagent"""
	if not reagent_container:
		return 0.0
	
	return reagent_container.get_reagent_amount(reagent_id)

func get_total_volume() -> float:
	"""Get the total volume of all reagents"""
	if not reagent_container:
		return 0.0
	
	return reagent_container.total_volume

func get_free_space() -> float:
	"""Get the available space in the container"""
	if not reagent_container:
		return 0.0
	
	return reagent_container.maximum_volume - reagent_container.total_volume

func clear_reagents():
	"""Clear all reagents from the container"""
	if not is_multiplayer_authority():
		return
	
	if reagent_container:
		reagent_container.clear_reagents()
		_sync_clear_reagents.rpc()
		
		if debug_mode:
			print("ReagentSystem: Cleared all reagents")

func purge_reagent(reagent_id: String):
	"""Purge a specific reagent completely"""
	if not is_multiplayer_authority():
		return
	
	if reagent_container:
		var reagent = reagent_container.get_reagent(reagent_id)
		if reagent:
			remove_reagent(reagent_id, reagent.volume)
			
			if debug_mode:
				print("ReagentSystem: Purged ", reagent_id)
#endregion

#region TRANSFER OPERATIONS
func transfer_to(target_reagent_system: ReagentSystem, amount: float) -> float:
	"""Transfer reagents to another system"""
	if not is_multiplayer_authority():
		return 0.0
	
	if not reagent_container or not target_reagent_system or not target_reagent_system.reagent_container:
		return 0.0
	
	var transferred = reagent_container.transfer_to(target_reagent_system.reagent_container, amount)
	
	if transferred > 0:
		_sync_transfer.rpc(target_reagent_system.get_path(), transferred)
		
		if debug_mode:
			print("ReagentSystem: Transferred ", transferred, " units to ", target_reagent_system.name)
	
	return transferred

func transfer_reagent_to(target_reagent_system: ReagentSystem, reagent_id: String, amount: float) -> float:
	"""Transfer a specific reagent to another system"""
	if not is_multiplayer_authority():
		return 0.0
	
	if not reagent_container or not target_reagent_system or not target_reagent_system.reagent_container:
		return 0.0
	
	var transferred = reagent_container.transfer_reagent_to(target_reagent_system.reagent_container, reagent_id, amount)
	
	if transferred > 0:
		_sync_reagent_transfer.rpc(target_reagent_system.get_path(), reagent_id, transferred)
		
		if debug_mode:
			print("ReagentSystem: Transferred ", transferred, " units of ", reagent_id, " to ", target_reagent_system.name)
	
	return transferred

func inject_reagent(reagent_id: String, amount: float, injection_time: float = 0.5) -> bool:
	"""Inject a reagent over time"""
	if not is_multiplayer_authority():
		return false
	
	if amount <= 0:
		return false
	
	if injection_time <= 0:
		add_reagent(reagent_id, amount)
		return true
	
	_inject_over_time(reagent_id, amount, injection_time)
	return true

func _inject_over_time(reagent_id: String, total_amount: float, duration: float):
	"""Inject reagent gradually over time"""
	var injections_per_second = 10
	var injection_interval = 1.0 / injections_per_second
	var amount_per_injection = total_amount / (duration * injections_per_second)
	var injections_remaining = int(duration * injections_per_second)
	
	_perform_timed_injection(reagent_id, amount_per_injection, injection_interval, injections_remaining)

func _perform_timed_injection(reagent_id: String, amount: float, interval: float, remaining: int):
	"""Perform timed injection sequence"""
	if remaining <= 0:
		return
	
	add_reagent(reagent_id, amount)
	
	if remaining > 1:
		await get_tree().create_timer(interval).timeout
		_perform_timed_injection(reagent_id, amount, interval, remaining - 1)
#endregion

#region CONTAINER-SPECIFIC EFFECTS
func _handle_bloodstream_addition(reagent_id: String, amount: float):
	"""Handle reagents added to bloodstream"""
	if not health_system:
		return
	
	match reagent_id:
		"epinephrine":
			if health_system.has_method("exit_cardiac_arrest"):
				if randf() < 0.3:
					health_system.exit_cardiac_arrest()
		"dexalinp":
			health_system.adjustOxyLoss(-amount * 2, false)
		"bicaridine":
			if health_system.has_method("set_bleeding_rate"):
				var current_bleeding = health_system.bleeding_rate
				health_system.set_bleeding_rate(max(0, current_bleeding - amount * 0.1))
		"tramadol":
			if health_system.has_method("adjust_pain_level"):
				health_system.adjust_pain_level(-amount * 1.5)
		"kelotane":
			health_system.adjustFireLoss(-amount * 1.2, false)
		"anti_toxin":
			health_system.adjustToxLoss(-amount * 1.5, false)
		"inaprovaline":
			if health_system.current_state == health_system.HealthState.CRITICAL:
				health_system.add_status_effect("stabilized", 30.0, 1.0)

func _handle_stomach_addition(reagent_id: String, amount: float):
	"""Handle reagents added to stomach"""
	if entity and entity.has_method("get_node"):
		var bloodstream = entity.get_node_or_null("BloodstreamReagents")
		if bloodstream:
			# Stomach contents gradually move to bloodstream
			var absorption_rate = 0.1  # 10% per process cycle
			var absorbed_amount = amount * absorption_rate
			
			# Add to bloodstream with delay
			call_deferred("_delayed_absorption", bloodstream, reagent_id, absorbed_amount)

func _delayed_absorption(bloodstream: ReagentSystem, reagent_id: String, amount: float):
	"""Handle delayed absorption from stomach to bloodstream"""
	if bloodstream and amount > 0:
		bloodstream.add_reagent(reagent_id, amount)
		remove_reagent(reagent_id, amount)
#endregion

#region ANALYSIS AND INFORMATION
func analyze_contents() -> Dictionary:
	"""Analyze container contents and return detailed information"""
	if not reagent_container:
		return {}
	
	var analysis = {
		"total_volume": reagent_container.total_volume,
		"maximum_volume": reagent_container.maximum_volume,
		"fill_percentage": (reagent_container.total_volume / reagent_container.maximum_volume) * 100.0,
		"container_type": _get_container_type_string(),
		"temperature": reagent_container.temperature,
		"pressure": reagent_container.pressure,
		"reagents": [],
		"is_dangerous": reagent_container.is_dangerous(),
		"is_medical": reagent_container.is_medical(),
		"dominant_reagent": null,
		"mixed_color": reagent_container.get_mixed_color().to_html(),
		"analysis_time": Time.get_unix_time_from_system()
	}
	
	# Analyze individual reagents
	for reagent in reagent_container.reagent_list:
		var reagent_analysis = {
			"id": reagent.id,
			"name": reagent.name,
			"volume": reagent.volume,
			"percentage": (reagent.volume / reagent_container.total_volume) * 100.0,
			"color": reagent.color.to_html(),
			"is_harmful": reagent.is_harmful(),
			"is_beneficial": reagent.is_beneficial(),
			"overdose_threshold": reagent.overdose_threshold,
			"is_overdosed": reagent.overdose_threshold > 0 and reagent.volume > reagent.overdose_threshold,
			"metabolism_rate": reagent.custom_metabolism,
			"temperature_stable": reagent.is_temperature_stable(reagent_container.temperature),
			"pressure_stable": reagent.is_pressure_stable(reagent_container.pressure)
		}
		analysis.reagents.append(reagent_analysis)
	
	# Find dominant reagent
	var dominant = reagent_container.get_dominant_reagent()
	if dominant:
		analysis.dominant_reagent = dominant.name
	
	return analysis

func get_reagent_list() -> Array:
	"""Get list of reagent names"""
	if not reagent_container:
		return []
	
	var reagent_names = []
	for reagent in reagent_container.reagent_list:
		reagent_names.append(reagent.name)
	
	return reagent_names

func get_dangerous_reagents() -> Array:
	"""Get list of dangerous reagents"""
	if not reagent_container:
		return []
	
	var dangerous = []
	for reagent in reagent_container.reagent_list:
		if reagent.is_harmful():
			dangerous.append({
				"id": reagent.id,
				"name": reagent.name,
				"volume": reagent.volume,
				"danger_level": _calculate_danger_level(reagent)
			})
	
	return dangerous

func get_medical_reagents() -> Array:
	"""Get list of medical reagents"""
	if not reagent_container:
		return []
	
	var medical = []
	for reagent in reagent_container.reagent_list:
		if reagent.is_beneficial():
			medical.append({
				"id": reagent.id,
				"name": reagent.name,
				"volume": reagent.volume,
				"medical_type": _get_medical_type(reagent)
			})
	
	return medical

func _calculate_danger_level(reagent: Reagent) -> String:
	"""Calculate danger level of a reagent"""
	var volume_ratio = reagent.volume / reagent.overdose_threshold if reagent.overdose_threshold > 0 else 0
	
	if volume_ratio > 2.0:
		return "CRITICAL"
	elif volume_ratio > 1.0:
		return "HIGH"
	elif reagent.is_harmful():
		return "MODERATE"
	else:
		return "LOW"

func _get_medical_type(reagent: Reagent) -> String:
	"""Get medical classification of a reagent"""
	match reagent.id:
		"bicaridine", "kelotane", "anti_toxin", "dexalinp":
			return "healing"
		"tramadol", "morphine":
			return "painkiller"
		"epinephrine", "inaprovaline":
			return "stimulant"
		"spaceacillin":
			return "antibiotic"
		_:
			return "unknown"

func is_empty() -> bool:
	"""Check if container is empty"""
	return get_total_volume() <= 0

func is_full() -> bool:
	"""Check if container is full"""
	return get_free_space() <= 0.1

func get_purity() -> float:
	"""Get purity percentage (dominant reagent vs total)"""
	if not reagent_container or reagent_container.reagent_list.is_empty():
		return 0.0
	
	var dominant = reagent_container.get_dominant_reagent()
	if dominant:
		return (dominant.volume / reagent_container.total_volume) * 100.0
	
	return 0.0
#endregion

#region NETWORK SYNCHRONIZATION
@rpc("any_peer", "call_local", "reliable")
func _sync_reagent_added(reagent_id: String, amount: float, data: Dictionary = {}):
	if is_multiplayer_authority():
		return
	
	if reagent_container:
		reagent_container.add_reagent(reagent_id, amount, data)
	
	emit_signal("reagent_added", reagent_id, amount)

@rpc("any_peer", "call_local", "reliable")
func _sync_reagent_removed(reagent_id: String, amount: float):
	if is_multiplayer_authority():
		return
	
	emit_signal("reagent_removed", reagent_id, amount)

@rpc("any_peer", "call_local", "reliable")
func _sync_reagent_metabolized(reagent_id: String, amount: float):
	emit_signal("reagent_metabolized", reagent_id, amount)

@rpc("any_peer", "call_local", "reliable")
func _sync_metabolism_processed(reagents_processed: Array):
	emit_signal("metabolism_processed", reagents_processed)

@rpc("any_peer", "call_local", "reliable")
func _sync_overdose_detected(reagent_id: String, amount: float):
	emit_signal("overdose_detected", reagent_id, amount)

@rpc("any_peer", "call_local", "reliable")
func _sync_transfer(target_path: String, amount: float):
	pass  # Handle transfer completion on remote clients

@rpc("any_peer", "call_local", "reliable")
func _sync_reagent_transfer(target_path: String, reagent_id: String, amount: float):
	pass  # Handle specific reagent transfer on remote clients

@rpc("any_peer", "call_local", "reliable")
func _sync_clear_reagents():
	if is_multiplayer_authority():
		return
	
	if reagent_container:
		reagent_container.clear_reagents()

@rpc("any_peer", "call_local", "reliable")
func _sync_container_state(container_data: Dictionary):
	if is_multiplayer_authority():
		return
	
	if reagent_container:
		reagent_container.from_dict(container_data)

@rpc("any_peer", "call_local", "reliable")
func _sync_reaction_occurred(reaction_name: String, products: Array):
	if is_multiplayer_authority():
		return
	
	emit_signal("reaction_occurred", reaction_name, products)
#endregion

#region EVENT HANDLERS
func _on_reagent_added(reagent_id: String, amount: float):
	"""Handle reagent addition"""
	emit_signal("reagent_added", reagent_id, amount)

func _on_reagent_removed(reagent_id: String, amount: float):
	"""Handle reagent removal"""
	emit_signal("reagent_removed", reagent_id, amount)

func _on_reaction_occurred(reaction_name: String, products: Array):
	"""Handle chemical reaction"""
	emit_signal("reaction_occurred", reaction_name, products)
	
	if is_multiplayer_authority():
		_sync_reaction_occurred.rpc(reaction_name, products)
	
	if log_reactions:
		print("ReagentSystem: Reaction occurred - " + reaction_name + " -> " + str(products))

func _on_volume_changed(new_volume: float, max_volume: float):
	"""Handle volume changes"""
	emit_signal("container_changed", new_volume, max_volume)

func _on_explosive_reaction(power: float):
	"""Handle explosive reactions"""
	emit_signal("explosive_reaction", power)
	
	if health_system:
		health_system.apply_damage(power * 10, health_system.DamageType.BRUTE, 0, "chest")
		
		if debug_mode:
			print("ReagentSystem: Explosive reaction with power ", power)
	
	if entity and entity.has_method("create_explosion"):
		entity.create_explosion(power)

func _on_fire_reaction(intensity: float, duration: float):
	"""Handle fire reactions"""
	emit_signal("fire_reaction", intensity, duration)
	
	if health_system:
		health_system.apply_damage(intensity * 2, health_system.DamageType.BURN)
		
		if debug_mode:
			print("ReagentSystem: Fire reaction with intensity ", intensity, " for ", duration, " seconds")
	
	if entity and entity.has_method("create_fire"):
		entity.create_fire(intensity, duration)
#endregion

#region UTILITY FUNCTIONS
func _get_container_type_string() -> String:
	"""Get string representation of container type"""
	return container_type_strings.get(container_type, "generic")

func _get_reaction_manager():
	"""Get the chemical reaction manager"""
	if Engine.has_singleton("ChemicalReactionManager"):
		return Engine.get_singleton("ChemicalReactionManager")
	return null

func set_temperature(new_temperature: float):
	"""Set container temperature"""
	if reagent_container:
		reagent_container.temperature = new_temperature
		temperature = new_temperature
		emit_signal("temperature_changed", new_temperature)
		
		if debug_mode:
			print("ReagentSystem: Temperature set to ", new_temperature)

func set_pressure(new_pressure: float):
	"""Set container pressure"""
	if reagent_container:
		reagent_container.pressure = new_pressure
		pressure = new_pressure
		emit_signal("pressure_changed", new_pressure)
		
		if debug_mode:
			print("ReagentSystem: Pressure set to ", new_pressure)

func get_temperature() -> float:
	"""Get current temperature"""
	return reagent_container.temperature if reagent_container else temperature

func get_pressure() -> float:
	"""Get current pressure"""
	return reagent_container.pressure if reagent_container else pressure

func is_temperature_stable() -> bool:
	"""Check if temperature is stable for all reagents"""
	if not reagent_container:
		return true
	
	for reagent in reagent_container.reagent_list:
		if not reagent.is_temperature_stable(reagent_container.temperature):
			return false
	
	return true

func is_pressure_stable() -> bool:
	"""Check if pressure is stable for all reagents"""
	if not reagent_container:
		return true
	
	for reagent in reagent_container.reagent_list:
		if not reagent.is_pressure_stable(reagent_container.pressure):
			return false
	
	return true

func get_container_status() -> Dictionary:
	"""Get comprehensive container status"""
	return {
		"type": _get_container_type_string(),
		"volume": get_total_volume(),
		"max_volume": maximum_volume,
		"fill_percentage": (get_total_volume() / maximum_volume) * 100.0,
		"temperature": get_temperature(),
		"pressure": get_pressure(),
		"is_sealed": is_sealed,
		"reagent_count": reagent_container.reagent_list.size() if reagent_container else 0,
		"is_dangerous": reagent_container.is_dangerous() if reagent_container else false,
		"is_medical": reagent_container.is_medical() if reagent_container else false,
		"purity": get_purity(),
		"temperature_stable": is_temperature_stable(),
		"pressure_stable": is_pressure_stable()
	}
#endregion

#region SAVE/LOAD
func save_state() -> Dictionary:
	"""Save reagent system state"""
	var state = {
		"container_type": container_type,
		"maximum_volume": maximum_volume,
		"allow_reactions": allow_reactions,
		"allow_metabolism": allow_metabolism,
		"metabolism_rate_multiplier": metabolism_rate_multiplier,
		"temperature": temperature,
		"pressure": pressure,
		"is_sealed": is_sealed,
		"peer_id": peer_id,
		"process_interval": process_interval,
		"reaction_check_interval": reaction_check_interval,
		"max_reactions_per_cycle": max_reactions_per_cycle
	}
	
	if reagent_container:
		state["container"] = reagent_container.to_dict()
	
	return state

func load_state(state: Dictionary):
	"""Load reagent system state"""
	if state.has("container_type"):
		container_type = state.container_type
	if state.has("maximum_volume"):
		maximum_volume = state.maximum_volume
	if state.has("allow_reactions"):
		allow_reactions = state.allow_reactions
	if state.has("allow_metabolism"):
		allow_metabolism = state.allow_metabolism
	if state.has("metabolism_rate_multiplier"):
		metabolism_rate_multiplier = state.metabolism_rate_multiplier
	if state.has("temperature"):
		temperature = state.temperature
	if state.has("pressure"):
		pressure = state.pressure
	if state.has("is_sealed"):
		is_sealed = state.is_sealed
	if state.has("peer_id"):
		peer_id = state.peer_id
		set_multiplayer_authority(peer_id)
	if state.has("process_interval"):
		process_interval = state.process_interval
	if state.has("reaction_check_interval"):
		reaction_check_interval = state.reaction_check_interval
	if state.has("max_reactions_per_cycle"):
		max_reactions_per_cycle = state.max_reactions_per_cycle
	
	_initialize_container()
	
	if state.has("container"):
		reagent_container.from_dict(state.container)
	
	if debug_mode:
		print("ReagentSystem: State loaded successfully")
#endregion
