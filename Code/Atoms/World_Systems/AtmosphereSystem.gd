extends Node
class_name AtmosphereSystem

# =============================================================================
# CONSTANTS - TEMPERATURE
# =============================================================================

const T0C = 273.15           # 0°C in Kelvin
const T20C = 293.15          # 20°C in Kelvin
const TCMB = 2.7             # -270.3°C in Kelvin (cosmic background)
const T22C = 295.15          # 22°C
const T40C = 313.15          # 40°C

# =============================================================================
# CONSTANTS - PRESSURE
# =============================================================================

const HAZARD_HIGH_PRESSURE = 550     # Ultra-high pressure danger threshold
const WARNING_HIGH_PRESSURE = 325    # High pressure warning threshold
const WARNING_LOW_PRESSURE = 50      # Low pressure warning threshold
const HAZARD_LOW_PRESSURE = 20       # Ultra-low pressure danger threshold
const ONE_ATMOSPHERE = 101.325       # Standard atmospheric pressure

# =============================================================================
# CONSTANTS - GAS COMPOSITION
# =============================================================================

const O2STANDARD = 0.21    # 21% oxygen
const N2STANDARD = 0.79    # 79% nitrogen

# =============================================================================
# CONSTANTS - PHYSICS
# =============================================================================

const CELL_VOLUME = 2500    # Liters in a cell
const R_IDEAL_GAS_EQUATION = 8.31    # kPa*L/(K*mol)
const MOLES_CELLSTANDARD = (ONE_ATMOSPHERE * CELL_VOLUME / (T20C * R_IDEAL_GAS_EQUATION))

# =============================================================================
# CONSTANTS - DAMAGE
# =============================================================================

const TEMPERATURE_DAMAGE_COEFFICIENT = 1.5
const PRESSURE_DAMAGE_COEFFICIENT = 4
const MAX_HIGH_PRESSURE_DAMAGE = 4
const LOW_PRESSURE_DAMAGE = 2

# Temperature damage thresholds for humans
const BODYTEMP_NORMAL = 310.15       # 37°C
const BODYTEMP_HEAT_DAMAGE_LIMIT_ONE = 360.15
const BODYTEMP_HEAT_DAMAGE_LIMIT_TWO = 400.15
const BODYTEMP_HEAT_DAMAGE_LIMIT_THREE = 1000
const BODYTEMP_COLD_DAMAGE_LIMIT_ONE = 260.15
const BODYTEMP_COLD_DAMAGE_LIMIT_TWO = 240.15
const BODYTEMP_COLD_DAMAGE_LIMIT_THREE = 120.15

# =============================================================================
# CONSTANTS - HEAT TRANSFER
# =============================================================================

const WALL_HEAT_TRANSFER_COEFFICIENT = 0.0
const OPEN_HEAT_TRANSFER_COEFFICIENT = 0.4
const WINDOW_HEAT_TRANSFER_COEFFICIENT = 0.1

# =============================================================================
# CONSTANTS - GAS TYPES
# =============================================================================

const GAS_TYPE_AIR = "air"
const GAS_TYPE_OXYGEN = "oxygen"
const GAS_TYPE_NITROGEN = "nitrogen"
const GAS_TYPE_N2O = "anesthetic"
const GAS_TYPE_PHORON = "phoron"
const GAS_TYPE_CO2 = "carbon_dioxide"

# =============================================================================
# EXPORTS
# =============================================================================

@export_group("System Settings")
@export var auto_initialize: bool = true
@export var enable_atmosphere_processing: bool = true
@export var enable_entity_effects: bool = true
@export var enable_reactions: bool = true

@export_group("Performance Settings")
@export var max_cells_per_tick: int = 200
@export var max_processing_time_ms: int = 16
@export var enable_threading: bool = true
@export var batch_processing_size: int = 50

@export_group("Gas Settings")
@export var standard_pressure: float = ONE_ATMOSPHERE
@export var oxygen_ratio: float = O2STANDARD
@export var nitrogen_ratio: float = N2STANDARD
@export var standard_temperature: float = T20C

@export_group("Breach Settings")
@export var enable_breach_system: bool = true
@export var breach_vent_rate: float = 0.4
@export var breach_cooling_rate: float = 5.0
@export var max_active_breaches: int = 100

@export_group("Entity Effects")
@export var pressure_damage_enabled: bool = true
@export var temperature_damage_enabled: bool = true
@export var gas_toxicity_enabled: bool = true
@export var breathing_effects_enabled: bool = true

@export_group("Debug Settings")
@export var debug_mode: bool = false
@export var visualize_active_cells: bool = false
@export var show_temperature_overlay: bool = false
@export var show_pressure_overlay: bool = false
@export var log_reactions: bool = false

# =============================================================================
# SIGNALS
# =============================================================================

signal atmosphere_changed(coords, old_data, new_data)
signal reaction_occurred(coords, reaction_name, intensity)
signal breach_detected(coords)
signal breach_sealed(coords)
signal warning_pressure(coords, pressure_level, is_high)
signal warning_temperature(coords, temperature, is_hot)
signal entity_atmosphere_effect(entity, effect_type, severity)

# =============================================================================
# PRIVATE VARIABLES
# =============================================================================

# System references
var world = null
var threading_manager = null
var spatial_manager = null

# Active cells management
var active_cells = []
var active_count = 0
var cells_processed = 0

# Caching for optimization
var tile_neighbors_cache = {}
var room_tiles_cache = {}
var cell_airtight_cache = {}

# Gas properties database
var gas_properties = {}
var gas_reactions = []

# Breach management
var active_breaches = []
var breach_counter = 0

# Performance tracking
var processing_stats = {}

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready():
	_find_system_references()
	_initialize_gas_properties()
	_initialize_gas_reactions()
	_setup_performance_tracking()
	
	if auto_initialize:
		_initialize_atmosphere()
	
	if debug_mode:
		print("AtmosphereSystem: Initialized")

# =============================================================================
# INITIALIZATION
# =============================================================================

func _find_system_references():
	world = get_parent()
	threading_manager = get_node_or_null("/root/ThreadingManager")
	spatial_manager = world.get_node_or_null("SpatialManager")
	
	if world:
		_connect_world_signals()

func _connect_world_signals():
	if world.has_signal("tile_changed"):
		world.connect("tile_changed", Callable(self, "_on_tile_changed"))
	
	if world.has_signal("door_toggled"):
		world.connect("door_toggled", Callable(self, "_on_door_toggled"))

func _initialize_gas_properties():
	gas_properties = {
		GAS_TYPE_OXYGEN: {
			"name": "Oxygen",
			"molar_mass": 32.0,
			"specific_heat": 20.0,
			"min_breathable": 16.0,
			"supports_combustion": true,
			"color": Color(0.0, 0.3, 1.0, 0.4)
		},
		GAS_TYPE_NITROGEN: {
			"name": "Nitrogen",
			"molar_mass": 28.0,
			"specific_heat": 20.0,
			"min_breathable": 0.0,
			"supports_combustion": false,
			"color": Color(0.7, 0.7, 0.7, 0.1)
		},
		GAS_TYPE_CO2: {
			"name": "Carbon Dioxide",
			"molar_mass": 44.0,
			"specific_heat": 30.0,
			"min_breathable": 0.0,
			"toxic": true,
			"toxic_threshold": 5.0,
			"color": Color(0.3, 0.3, 0.3, 0.2)
		},
		GAS_TYPE_PHORON: {
			"name": "Phoron",
			"molar_mass": 80.0,
			"specific_heat": 200.0,
			"min_breathable": 0.0,
			"flammable": true,
			"flammable_threshold": 2.0,
			"toxic": true,
			"toxic_threshold": 0.5,
			"color": Color(0.9, 0.3, 0.9, 0.5)
		},
		GAS_TYPE_N2O: {
			"name": "Nitrous Oxide",
			"molar_mass": 44.0,
			"specific_heat": 40.0,
			"min_breathable": 0.0,
			"anesthetic": true,
			"anesthetic_threshold": 1.0,
			"color": Color(0.8, 0.8, 1.0, 0.2)
		}
	}

func _initialize_gas_reactions():
	gas_reactions = [
		{
			"name": "phoron_combustion",
			"reactants": {
				GAS_TYPE_PHORON: 0.2,
				GAS_TYPE_OXYGEN: 0.5
			},
			"min_temp": 373.15,  # 100°C
			"energy_released": 3000.0,
			"products": {
				GAS_TYPE_CO2: 0.5
			}
		},
		{
			"name": "phoron_supercombustion",
			"reactants": {
				GAS_TYPE_PHORON: 0.5,
				GAS_TYPE_OXYGEN: 1.0
			},
			"min_temp": 573.15,  # 300°C
			"energy_released": 12000.0,
			"products": {
				GAS_TYPE_CO2: 1.0
			}
		}
	]

func _setup_performance_tracking():
	processing_stats = {
		"cells_processed_last_tick": 0,
		"active_cell_count": 0,
		"processing_time_ms": 0.0,
		"reactions_processed": 0,
		"entities_affected": 0
	}

func _initialize_atmosphere():
	active_cells = []
	active_count = 0
	
	var standard_atmosphere = _create_standard_atmosphere()
	
	if not world:
		return
	
	for z in range(world.z_levels):
		var tile_count = _initialize_z_level_atmosphere(z, standard_atmosphere)
		if debug_mode:
			print("AtmosphereSystem: Initialized ", tile_count, " tiles for z-level ", z)

# =============================================================================
# MAIN PROCESSING
# =============================================================================

func process_atmosphere_step():
	if not enable_atmosphere_processing:
		return
		
	var start_time = Time.get_ticks_msec()
	cells_processed = 0
	
	_process_active_cells(start_time)
	_process_breaches()
	
	if enable_entity_effects:
		_process_entity_atmosphere_effects()
	
	_update_processing_stats(start_time)

func _process_active_cells(start_time: int):
	while active_count > 0 and cells_processed < max_cells_per_tick and Time.get_ticks_msec() - start_time < max_processing_time_ms:
		var coords = active_cells[cells_processed % active_count]
		cells_processed += 1
		
		_process_cell(coords)
	
	if cells_processed >= active_count:
		_rebuild_active_cells()

func _process_cell(coords: Vector3):
	var tile_coords = Vector2i(coords.x, coords.y)
	var z_level = coords.z
	
	var tile = _get_tile_data(tile_coords, z_level)
	if not tile:
		_remove_active_cell(coords)
		return
	
	var atmosphere = _get_atmosphere_data(tile)
	if not atmosphere:
		_remove_active_cell(coords)
		return
	
	var old_atmosphere = atmosphere.duplicate()
	var old_pressure = _calculate_pressure(old_atmosphere)
	
	if tile.get("breach", false):
		return
	
	var neighbors = _get_neighboring_tiles(tile_coords, z_level)
	
	for neighbor in neighbors:
		var neighbor_tile = _get_tile_data(neighbor, z_level)
		if not neighbor_tile:
			continue
			
		var neighbor_atmosphere = _get_atmosphere_data(neighbor_tile)
		if not neighbor_atmosphere:
			continue
			
		if neighbor_tile.get("breach", false):
			continue
			
		if _is_airtight_barrier(tile_coords, neighbor, z_level):
			_process_heat_transfer_through_barrier(atmosphere, neighbor_atmosphere, tile_coords, neighbor, z_level)
			continue
		
		_process_gas_exchange(atmosphere, neighbor_atmosphere, tile_coords, neighbor, z_level)
		add_active_cell(Vector3(neighbor.x, neighbor.y, z_level))
	
	if enable_reactions:
		_process_reactions(atmosphere, tile_coords, z_level)
	
	var new_pressure = _calculate_pressure(atmosphere)
	
	var pressure_delta = abs(new_pressure - old_pressure)
	var temp_delta = abs(atmosphere.get("temperature", T20C) - old_atmosphere.get("temperature", T20C))
	
	if pressure_delta < 0.1 and temp_delta < 0.1:
		_remove_active_cell(coords)
	
	_check_warning_conditions(atmosphere, new_pressure, tile_coords, z_level)
	_update_atmosphere_data(tile, atmosphere, tile_coords, z_level)
	
	emit_signal("atmosphere_changed", coords, old_atmosphere, atmosphere)

# =============================================================================
# GAS EXCHANGE PROCESSING
# =============================================================================

func _process_gas_exchange(atmos1: Dictionary, atmos2: Dictionary, tile1: Vector2i, tile2: Vector2i, z_level: int):
	var pressure1 = _calculate_pressure(atmos1)
	var pressure2 = _calculate_pressure(atmos2)
	var pressure_diff = pressure1 - pressure2
	
	if abs(pressure_diff) < 0.1:
		return
	
	var flow_direction = 1 if pressure_diff > 0 else -1
	var flow_rate = 0.4 * min(1.0, abs(pressure_diff) / 100.0)
	
	if flow_direction > 0:
		_transfer_gases(atmos1, atmos2, flow_rate)
	else:
		_transfer_gases(atmos2, atmos1, flow_rate)
	
	_process_heat_exchange(atmos1, atmos2, OPEN_HEAT_TRANSFER_COEFFICIENT)

func _transfer_gases(source: Dictionary, target: Dictionary, flow_rate: float):
	for gas in source.keys():
		if gas == "temperature":
			continue
			
		if typeof(source[gas]) != TYPE_FLOAT:
			continue
			
		var transfer_amount = source[gas] * flow_rate
		
		if not gas in target:
			target[gas] = 0.0
			
		source[gas] -= transfer_amount
		target[gas] += transfer_amount

func _process_heat_transfer_through_barrier(atmos1: Dictionary, atmos2: Dictionary, tile1: Vector2i, tile2: Vector2i, z_level: int):
	var barrier_coefficient = WALL_HEAT_TRANSFER_COEFFICIENT
	
	var tile1_data = _get_tile_data(tile1, z_level)
	var tile2_data = _get_tile_data(tile2, z_level)
	
	if "door" in tile1_data or "door" in tile2_data:
		barrier_coefficient = 0.05
	elif "window" in tile1_data or "window" in tile2_data:
		barrier_coefficient = WINDOW_HEAT_TRANSFER_COEFFICIENT
	elif world and world.has_method("is_window_at"):
		if world.is_window_at(tile1, z_level) or world.is_window_at(tile2, z_level):
			barrier_coefficient = WINDOW_HEAT_TRANSFER_COEFFICIENT
	
	_process_heat_exchange(atmos1, atmos2, barrier_coefficient)

func _process_heat_exchange(atmos1: Dictionary, atmos2: Dictionary, coefficient: float):
	if not "temperature" in atmos1 or not "temperature" in atmos2:
		if not "temperature" in atmos1:
			atmos1.temperature = T20C
		if not "temperature" in atmos2:
			atmos2.temperature = T20C
	
	var energy1 = atmos1.temperature
	var energy2 = atmos2.temperature
	
	var energy_diff = energy1 - energy2
	var transfer = energy_diff * coefficient
	
	atmos1.temperature -= transfer
	atmos2.temperature += transfer

# =============================================================================
# CHEMICAL REACTIONS
# =============================================================================

func _process_reactions(atmosphere: Dictionary, coords: Vector2i, z_level: int):
	if not "temperature" in atmosphere:
		atmosphere.temperature = T20C
	
	for reaction in gas_reactions:
		if atmosphere.temperature < reaction.min_temp:
			continue
			
		var can_react = true
		var min_ratio = INF
		
		for gas in reaction.reactants:
			if not gas in atmosphere or atmosphere[gas] < reaction.reactants[gas]:
				can_react = false
				break
				
			var ratio = atmosphere[gas] / reaction.reactants[gas]
			min_ratio = min(min_ratio, ratio)
		
		if not can_react:
			continue
			
		var intensity = min(1.0, min_ratio)
		
		for gas in reaction.reactants:
			atmosphere[gas] -= reaction.reactants[gas] * intensity
		
		for gas in reaction.products:
			if not gas in atmosphere:
				atmosphere[gas] = 0.0
			atmosphere[gas] += reaction.products[gas] * intensity
		
		atmosphere.temperature += reaction.energy_released * intensity / 20.0
		
		add_active_cell(Vector3(coords.x, coords.y, z_level))
		
		if log_reactions:
			print("AtmosphereSystem: Reaction ", reaction.name, " at ", coords, " intensity: ", intensity)
		
		emit_signal("reaction_occurred", Vector3(coords.x, coords.y, z_level), reaction.name, intensity)
		
		processing_stats.reactions_processed += 1

# =============================================================================
# BREACH SYSTEM
# =============================================================================

func create_breach(coords, size = 1.0):
	if not enable_breach_system:
		return
		
	var tile_coords = Vector2i(coords.x, coords.y) if coords is Vector3 else coords
	var z_level = coords.z if coords is Vector3 else 0
	
	var tile = _get_tile_data(tile_coords, z_level)
	if not tile:
		return
	
	tile.breach = true
	tile.breach_size = size
	tile.exposed_to_space = true
	
	if active_breaches.size() >= max_active_breaches:
		_remove_oldest_breach()
	
	var breach_coords = Vector3(tile_coords.x, tile_coords.y, z_level)
	active_breaches.append({
		"id": breach_counter,
		"coords": breach_coords,
		"size": size,
		"created_at": Time.get_ticks_msec()
	})
	breach_counter += 1
	
	emit_signal("breach_detected", breach_coords)
	add_active_cell(breach_coords)
	
	var neighbors = _get_neighboring_tiles(tile_coords, z_level)
	for neighbor in neighbors:
		add_active_cell(Vector3(neighbor.x, neighbor.y, z_level))

func seal_breach(coords):
	var tile_coords = Vector2i(coords.x, coords.y) if coords is Vector3 else coords
	var z_level = coords.z if coords is Vector3 else 0
	
	var tile = _get_tile_data(tile_coords, z_level)
	if not tile:
		return
	
	tile.breach = false
	tile.exposed_to_space = false
	if "breach_size" in tile:
		tile.erase("breach_size")
	
	emit_signal("breach_sealed", Vector3(tile_coords.x, tile_coords.y, z_level))
	add_active_cell(Vector3(tile_coords.x, tile_coords.y, z_level))

func _process_breaches():
	if not enable_breach_system:
		return
		
	for i in range(active_breaches.size() - 1, -1, -1):
		var breach = active_breaches[i]
		
		var tile_coords = Vector2i(breach.coords.x, breach.coords.y)
		var z_level = breach.coords.z
		var tile = _get_tile_data(tile_coords, z_level)
		
		if not tile or not tile.get("breach", false):
			active_breaches.remove_at(i)
			emit_signal("breach_sealed", breach.coords)
			continue
		
		_process_breach_effects(breach, tile, tile_coords, z_level)

func _process_breach_effects(breach: Dictionary, tile: Dictionary, tile_coords: Vector2i, z_level: int):
	var atmosphere = _get_atmosphere_data(tile)
	if not atmosphere:
		return
	
	var vent_rate = breach.size * breach_vent_rate
	
	for gas in atmosphere.keys():
		if gas == "temperature":
			continue
			
		if typeof(atmosphere[gas]) == TYPE_FLOAT:
			atmosphere[gas] *= (1.0 - vent_rate)
	
	if "temperature" in atmosphere:
		atmosphere.temperature = lerp(atmosphere.temperature, TCMB, vent_rate)
	
	add_active_cell(breach.coords)
	
	var neighbors = _get_neighboring_tiles(tile_coords, z_level)
	for neighbor in neighbors:
		if _is_airtight_barrier(tile_coords, neighbor, z_level):
			continue
			
		add_active_cell(Vector3(neighbor.x, neighbor.y, z_level))
		
		var neighbor_tile = _get_tile_data(neighbor, z_level)
		if not neighbor_tile:
			continue
			
		var neighbor_atmosphere = _get_atmosphere_data(neighbor_tile)
		if not neighbor_atmosphere:
			continue
		
		var pull_rate = 0.3 * breach.size
		
		for gas in neighbor_atmosphere.keys():
			if gas == "temperature":
				continue
				
			if typeof(neighbor_atmosphere[gas]) == TYPE_FLOAT:
				neighbor_atmosphere[gas] *= (1.0 - pull_rate * 0.5)
		
		if "temperature" in neighbor_atmosphere:
			neighbor_atmosphere.temperature -= breach_cooling_rate * pull_rate
		
		_update_atmosphere_data(neighbor_tile, neighbor_atmosphere, neighbor, z_level)

func _remove_oldest_breach():
	if active_breaches.size() == 0:
		return
		
	var oldest_breach = active_breaches[0]
	active_breaches.remove_at(0)
	
	var tile_coords = Vector2i(oldest_breach.coords.x, oldest_breach.coords.y)
	var z_level = oldest_breach.coords.z
	seal_breach(Vector3(tile_coords.x, tile_coords.y, z_level))

# =============================================================================
# ENTITY EFFECTS SYSTEM
# =============================================================================

func _process_entity_atmosphere_effects():
	if not spatial_manager:
		return
	
	var entity_types = ["character", "human", "mob"]
	var entities = []
	
	for type in entity_types:
		var type_entities = spatial_manager.get_entities_by_type(type)
		for entity in type_entities:
			if not entity in entities:
				entities.append(entity)
	
	for entity in entities:
		_process_entity_atmosphere(entity)
	
	processing_stats.entities_affected = entities.size()

func _process_entity_atmosphere(entity):
	var entity_pos = entity.position
	var z_level = entity.current_z_level if "current_z_level" in entity else 0
	
	var tile_coords = world.get_tile_at(entity_pos) if world else Vector2i(floor(entity_pos.x / 32), floor(entity_pos.y / 32))
	var tile = _get_tile_data(tile_coords, z_level)
	
	if not tile:
		_apply_void_effects(entity, 1.0)
		return
	
	var atmosphere = _get_atmosphere_data(tile)
	if not atmosphere:
		_apply_void_effects(entity, 1.0)
		return
	
	var pressure = _calculate_pressure(atmosphere)
	var temperature = atmosphere.get("temperature", T20C)
	
	if pressure_damage_enabled:
		_apply_pressure_effects(entity, pressure)
	
	if temperature_damage_enabled:
		_apply_temperature_effects(entity, temperature)
	
	if gas_toxicity_enabled or breathing_effects_enabled:
		_apply_gas_effects(entity, atmosphere, pressure)

func _apply_void_effects(entity, severity: float):
	if entity.get("void_protected"):
		return
	
	if entity.has_method("take_damage"):
		var damage = 5.0 * severity
		entity.take_damage(damage, 4)
	
	emit_signal("entity_atmosphere_effect", entity, "void", severity)

func _apply_pressure_effects(entity, pressure: float):
	var severity = 0.0
	var effect_type = ""
	
	if pressure < HAZARD_LOW_PRESSURE:
		severity = 1.0 - (pressure / HAZARD_LOW_PRESSURE)
		effect_type = "low_pressure"
	elif pressure > HAZARD_HIGH_PRESSURE:
		severity = (pressure - HAZARD_HIGH_PRESSURE) / HAZARD_HIGH_PRESSURE
		effect_type = "high_pressure"
	
	if severity < 0.1:
		return
	
	if entity.get("pressure_protected", false):
		return
	
	if entity.has_method("take_damage"):
		var damage = 0.0
		if effect_type == "low_pressure":
			damage = LOW_PRESSURE_DAMAGE * severity
		else:
			damage = min(severity * PRESSURE_DAMAGE_COEFFICIENT, MAX_HIGH_PRESSURE_DAMAGE)
		
		entity.take_damage(damage, "pressure")
	
	emit_signal("entity_atmosphere_effect", entity, effect_type, severity)

func _apply_temperature_effects(entity, temperature: float):
	var severity = 0.0
	var effect_type = ""
	
	if temperature < BODYTEMP_COLD_DAMAGE_LIMIT_ONE:
		if temperature < BODYTEMP_COLD_DAMAGE_LIMIT_THREE:
			severity = 1.0
		elif temperature < BODYTEMP_COLD_DAMAGE_LIMIT_TWO:
			severity = 0.75
		else:
			severity = 0.5
		effect_type = "cold"
		
		if entity.get("cold_protected", false):
			return
	elif temperature > BODYTEMP_HEAT_DAMAGE_LIMIT_ONE:
		if temperature > BODYTEMP_HEAT_DAMAGE_LIMIT_THREE:
			severity = 1.0
		elif temperature > BODYTEMP_HEAT_DAMAGE_LIMIT_TWO:
			severity = 0.75
		else:
			severity = 0.5
		effect_type = "heat"
		
		if entity.get("heat_protected", false):
			return
	
	if severity > 0.0 and entity.has_method("take_damage"):
		var damage = severity * TEMPERATURE_DAMAGE_COEFFICIENT
		entity.take_damage(damage, effect_type)
		
		emit_signal("entity_atmosphere_effect", entity, effect_type, severity)

func _apply_gas_effects(entity, atmosphere: Dictionary, pressure: float):
	if pressure < HAZARD_LOW_PRESSURE:
		return
	
	if breathing_effects_enabled:
		_check_breathing_effects(entity, atmosphere, pressure)
	
	if gas_toxicity_enabled:
		_check_toxicity_effects(entity, atmosphere, pressure)

func _check_breathing_effects(entity, atmosphere: Dictionary, pressure: float):
	var oxygen_percent = 0.0
	if GAS_TYPE_OXYGEN in atmosphere:
		oxygen_percent = (atmosphere[GAS_TYPE_OXYGEN] / pressure) * 100.0
	
	if oxygen_percent < 16.0:
		var severity = 1.0 - (oxygen_percent / 16.0)
		severity = clamp(severity, 0.0, 1.0)
		
		if entity.get("breathing_protected", false):
			return
		
		if entity.has_method("take_damage"):
			var damage = severity * 1.0
			entity.take_damage(damage, "oxygen_deprivation")
		
		emit_signal("entity_atmosphere_effect", entity, "suffocation", severity)

func _check_toxicity_effects(entity, atmosphere: Dictionary, pressure: float):
	var toxic_severity = 0.0
	
	if GAS_TYPE_PHORON in atmosphere:
		var phoron_percent = (atmosphere[GAS_TYPE_PHORON] / pressure) * 100.0
		if phoron_percent > 0.5:
			var phoron_severity = (phoron_percent - 0.5) / 10.0
			toxic_severity = max(toxic_severity, phoron_severity)
	
	if GAS_TYPE_CO2 in atmosphere:
		var co2_percent = (atmosphere[GAS_TYPE_CO2] / pressure) * 100.0
		if co2_percent > 5.0:
			var co2_severity = (co2_percent - 5.0) / 15.0
			toxic_severity = max(toxic_severity, co2_severity)
	
	if toxic_severity > 0.1:
		if entity.get("toxin_protected", false):
			return
		
		if entity.has_method("take_damage"):
			var damage = toxic_severity * 2.0
			entity.take_damage(damage, "toxin")
		
		emit_signal("entity_atmosphere_effect", entity, "toxins", toxic_severity)

# =============================================================================
# ACTIVE CELL MANAGEMENT
# =============================================================================

func add_active_cell(coords: Vector3):
	for i in range(active_count):
		if active_cells[i] == coords:
			return
	
	if active_count < active_cells.size():
		active_cells[active_count] = coords
	else:
		active_cells.append(coords)
	
	active_count += 1

func _remove_active_cell(coords: Vector3):
	for i in range(active_count):
		if active_cells[i] == coords:
			active_count -= 1
			if i < active_count:
				active_cells[i] = active_cells[active_count]
			return

func _rebuild_active_cells():
	active_cells = []
	active_count = 0
	
	if world:
		for z in world.world_data.keys():
			for coords in world.world_data[z].keys():
				var tile = world.world_data[z][coords]
				
				if not world.TileLayer.ATMOSPHERE in tile and not "atmosphere" in tile:
					continue
				
				add_active_cell(Vector3(coords.x, coords.y, z))
	
	if debug_mode:
		print("AtmosphereSystem: Rebuilt active cells list with ", active_count, " cells")

# =============================================================================
# UTILITY METHODS
# =============================================================================

func _get_tile_data(coords: Vector2i, z_level: int):
	if not world:
		return null
	
	return world.get_tile_data(coords, z_level)

func _get_atmosphere_data(tile):
	if tile == null or not (tile is Dictionary):
		return null
	
	if "atmosphere" in tile:
		return tile["atmosphere"]
	
	if world and world.TileLayer:
		if world.TileLayer.ATMOSPHERE in tile:
			return tile[world.TileLayer.ATMOSPHERE]
	
	return null

func _update_atmosphere_data(tile: Dictionary, atmosphere: Dictionary, coords: Vector2i, z_level: int):
	if not tile:
		return
	
	if "atmosphere" in tile:
		tile.atmosphere = atmosphere
	elif world and world.TileLayer.ATMOSPHERE in tile:
		tile[world.TileLayer.ATMOSPHERE] = atmosphere

func _calculate_pressure(atmosphere: Dictionary) -> float:
	var total_pressure = 0.0
	
	for gas in atmosphere.keys():
		if gas != "temperature" and typeof(atmosphere[gas]) == TYPE_FLOAT:
			total_pressure += atmosphere[gas]
	
	return total_pressure

func _get_neighboring_tiles(coords: Vector2i, z_level: int) -> Array:
	var cache_key = str(coords) + "-" + str(z_level)
	if cache_key in tile_neighbors_cache:
		return tile_neighbors_cache[cache_key]
	
	var neighbors = [
		Vector2i(coords.x + 1, coords.y),
		Vector2i(coords.x - 1, coords.y),
		Vector2i(coords.x, coords.y + 1),
		Vector2i(coords.x, coords.y - 1)
	]
	
	var valid_neighbors = []
	for neighbor in neighbors:
		if world and world.is_valid_tile(neighbor, z_level):
			valid_neighbors.append(neighbor)
	
	tile_neighbors_cache[cache_key] = valid_neighbors
	return valid_neighbors

func _is_airtight_barrier(tile1: Vector2i, tile2: Vector2i, z_level: int) -> bool:
	var cache_key = str(tile1) + "-" + str(tile2) + "-" + str(z_level)
	if cache_key in cell_airtight_cache:
		return cell_airtight_cache[cache_key]
	
	var result = false
	
	if world:
		if world.has_method("is_airtight_barrier"):
			result = world.is_airtight_barrier(tile1, tile2, z_level)
		else:
			var tile1_data = world.get_tile_data(tile1, z_level)
			var tile2_data = world.get_tile_data(tile2, z_level)
			
			if tile1_data == null or tile2_data == null:
				result = true
			elif world.TileLayer.WALL in tile1_data and tile1_data[world.TileLayer.WALL] != null:
				result = true
			elif world.TileLayer.WALL in tile2_data and tile2_data[world.TileLayer.WALL] != null:
				result = true
			elif "door" in tile1_data and "closed" in tile1_data.door and tile1_data.door.closed:
				result = true
			elif "door" in tile2_data and "closed" in tile2_data.door and tile2_data.door.closed:
				result = true
	
	cell_airtight_cache[cache_key] = result
	return result

func _check_warning_conditions(atmosphere: Dictionary, pressure: float, coords: Vector2i, z_level: int):
	if pressure > HAZARD_HIGH_PRESSURE:
		emit_signal("warning_pressure", Vector3(coords.x, coords.y, z_level), pressure, true)
	elif pressure < HAZARD_LOW_PRESSURE:
		emit_signal("warning_pressure", Vector3(coords.x, coords.y, z_level), pressure, false)
	
	if "temperature" in atmosphere:
		var temp = atmosphere.temperature
		if temp > BODYTEMP_HEAT_DAMAGE_LIMIT_ONE:
			emit_signal("warning_temperature", Vector3(coords.x, coords.y, z_level), temp, true)
		elif temp < BODYTEMP_COLD_DAMAGE_LIMIT_ONE:
			emit_signal("warning_temperature", Vector3(coords.x, coords.y, z_level), temp, false)

func _create_standard_atmosphere() -> Dictionary:
	return {
		GAS_TYPE_OXYGEN: standard_pressure * oxygen_ratio,
		GAS_TYPE_NITROGEN: standard_pressure * nitrogen_ratio,
		"temperature": standard_temperature
	}

func _initialize_z_level_atmosphere(z: int, standard_atmosphere: Dictionary) -> int:
	var tiles_to_init = []
	
	if z in world.world_data:
		for coords in world.world_data[z]:
			var tile = world.world_data[z][coords]
			
			if world.TileLayer.ATMOSPHERE in tile:
				add_active_cell(Vector3(coords.x, coords.y, z))
				continue
			
			if world.TileLayer.FLOOR in tile:
				tiles_to_init.append(coords)
	
	for coords in tiles_to_init:
		world.add_atmosphere_to_tile(coords, z, standard_atmosphere)
	
	return tiles_to_init.size()

func _update_processing_stats(start_time: int):
	processing_stats.cells_processed_last_tick = cells_processed
	processing_stats.active_cell_count = active_count
	processing_stats.processing_time_ms = Time.get_ticks_msec() - start_time

# =============================================================================
# PUBLIC API
# =============================================================================

func kelvin_to_celsius(kelvin: float) -> float:
	return kelvin - T0C

func celsius_to_kelvin(celsius: float) -> float:
	return celsius + T0C

func get_gas_properties(gas_type: String) -> Dictionary:
	return gas_properties.get(gas_type, {})

func get_processing_stats() -> Dictionary:
	return processing_stats.duplicate()

func set_debug_mode(enabled: bool):
	debug_mode = enabled
	if debug_mode:
		print("AtmosphereSystem: Debug mode enabled")

func get_active_cell_count() -> int:
	return active_count

func get_breach_count() -> int:
	return active_breaches.size()

# =============================================================================
# SIGNAL HANDLERS
# =============================================================================

func _on_tile_changed(tile_coords: Vector2i, z_level: int, old_data, new_data):
	var cache_key = str(tile_coords) + "-" + str(z_level)
	if cache_key in tile_neighbors_cache:
		tile_neighbors_cache.erase(cache_key)
	
	for key in cell_airtight_cache.keys():
		if key.begins_with(str(tile_coords)) or key.find("-" + str(tile_coords)) > 0:
			cell_airtight_cache.erase(key)
	
	add_active_cell(Vector3(tile_coords.x, tile_coords.y, z_level))
	
	var neighbors = _get_neighboring_tiles(tile_coords, z_level)
	for neighbor in neighbors:
		add_active_cell(Vector3(neighbor.x, neighbor.y, z_level))

func _on_door_toggled(tile_coords: Vector2i, z_level: int, is_open: bool):
	var cache_key_base = str(tile_coords) + "-"
	for key in cell_airtight_cache.keys():
		if key.begins_with(cache_key_base) or key.find("-" + str(tile_coords)) > 0:
			cell_airtight_cache.erase(key)
	
	add_active_cell(Vector3(tile_coords.x, tile_coords.y, z_level))
	
	var neighbors = _get_neighboring_tiles(tile_coords, z_level)
	for neighbor in neighbors:
		add_active_cell(Vector3(neighbor.x, neighbor.y, z_level))
