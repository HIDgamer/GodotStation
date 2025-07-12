extends Node
class_name AtmosphereSystem

# === CONSTANTS ===
# Temperature constants
const T0C = 273.15           # 0°C in Kelvin
const T20C = 293.15          # 20°C in Kelvin
const TCMB = 2.7             # -270.3°C in Kelvin (cosmic background)
const T22C = 295.15          # 22°C
const T40C = 313.15          # 40°C

# Pressure constants in kPa
const HAZARD_HIGH_PRESSURE = 550     # Ultra-high pressure danger threshold
const WARNING_HIGH_PRESSURE = 325    # High pressure warning threshold
const WARNING_LOW_PRESSURE = 50      # Low pressure warning threshold
const HAZARD_LOW_PRESSURE = 20       # Ultra-low pressure danger threshold
const ONE_ATMOSPHERE = 101.325       # Standard atmospheric pressure

# Standard gas composition
const O2STANDARD = 0.21    # 21% oxygen
const N2STANDARD = 0.79    # 79% nitrogen

# Cell parameters
const CELL_VOLUME = 2500    # Liters in a cell
const R_IDEAL_GAS_EQUATION = 8.31    # kPa*L/(K*mol)
const MOLES_CELLSTANDARD = (ONE_ATMOSPHERE * CELL_VOLUME / (T20C * R_IDEAL_GAS_EQUATION))

# Gas types
const GAS_TYPE_AIR = "air"
const GAS_TYPE_OXYGEN = "oxygen"
const GAS_TYPE_NITROGEN = "nitrogen"
const GAS_TYPE_N2O = "anesthetic"
const GAS_TYPE_PHORON = "phoron"
const GAS_TYPE_CO2 = "carbon_dioxide"

# Heat transfer coefficients
const WALL_HEAT_TRANSFER_COEFFICIENT = 0.0
const OPEN_HEAT_TRANSFER_COEFFICIENT = 0.4
const WINDOW_HEAT_TRANSFER_COEFFICIENT = 0.1

# Damage coefficients
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

# === SYSTEM VARIABLES ===
# World reference
var world = null
var threading_manager = null
var spatial_manager = null

# Active cells
var active_cells = []        # List of cells that need processing
var active_count = 0         # Current number of active cells
var cells_processed = 0      # Number of cells processed in the current tick
var max_cells_per_tick = 200 # Maximum cells to process per tick

# Caching for optimization
var tile_neighbors_cache = {}   # Cache of neighboring tiles
var room_tiles_cache = {}       # Cache of room tile compositions
var cell_airtight_cache = {}    # Cache of airtight barriers

# Debug flags
var debug_mode = false
var visualize_active_cells = false
var show_temperature_overlay = false
var show_pressure_overlay = false

# Gas properties
var gas_properties = {
	GAS_TYPE_OXYGEN: {
		"name": "Oxygen",
		"molar_mass": 32.0,
		"specific_heat": 20.0,
		"min_breathable": 16.0,  # Percentage
		"supports_combustion": true,
		"color": Color(0.0, 0.3, 1.0, 0.4)  # Blue
	},
	GAS_TYPE_NITROGEN: {
		"name": "Nitrogen",
		"molar_mass": 28.0,
		"specific_heat": 20.0,
		"min_breathable": 0.0,
		"supports_combustion": false,
		"color": Color(0.7, 0.7, 0.7, 0.1)  # Light gray
	},
	GAS_TYPE_CO2: {
		"name": "Carbon Dioxide",
		"molar_mass": 44.0,
		"specific_heat": 30.0,
		"min_breathable": 0.0,
		"toxic": true,
		"toxic_threshold": 5.0,  # Percentage
		"color": Color(0.3, 0.3, 0.3, 0.2)  # Dark gray
	},
	GAS_TYPE_PHORON: {
		"name": "Phoron",
		"molar_mass": 80.0,
		"specific_heat": 200.0,
		"min_breathable": 0.0,
		"flammable": true,
		"flammable_threshold": 2.0,  # Percentage
		"toxic": true,
		"toxic_threshold": 0.5,
		"color": Color(0.9, 0.3, 0.9, 0.5)  # Purple
	},
	GAS_TYPE_N2O: {
		"name": "Nitrous Oxide",
		"molar_mass": 44.0,
		"specific_heat": 40.0,
		"min_breathable": 0.0,
		"anesthetic": true,
		"anesthetic_threshold": 1.0,
		"color": Color(0.8, 0.8, 1.0, 0.2)  # Light blue
	}
}

# Chemical reactions
var gas_reactions = [
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

# Active breaches
var active_breaches = []
var breach_counter = 0

# === SIGNALS ===
signal atmosphere_changed(coords, old_data, new_data)
signal reaction_occurred(coords, reaction_name, intensity)
signal breach_detected(coords)
signal breach_sealed(coords)
signal warning_pressure(coords, pressure_level, is_high)
signal warning_temperature(coords, temperature, is_hot)
signal entity_atmosphere_effect(entity, effect_type, severity)

# === INITIALIZATION ===
func _ready():
	# Get references
	world = get_node_or_null("/root/World")
	
	# Try to find threading manager
	threading_manager = get_node_or_null("/root/ThreadingManager")
	
	# Try to find spatial manager
	spatial_manager = get_node_or_null("/root/SpatialManager")
	if not spatial_manager and world:
		spatial_manager = world.get_node_or_null("SpatialManager")
	
	# Initialize active cells list
	active_cells = []
	active_count = 0
	
	# Register with world
	if world:
		# Connect to world signals
		world.connect("tile_changed", Callable(self, "_on_tile_changed"))
		world.connect("door_toggled", Callable(self, "_on_door_toggled"))
	
	# Initial activation of all cells with atmosphere
	initialize_atmosphere()
	
	print("AtmosphereSystem: Initialized")

# === MAIN PROCESSING ===
# Process a step of atmospheric simulation
func process_atmosphere_step():
	# Reset stats
	cells_processed = 0
	
	# Process active cells
	var start_time = Time.get_ticks_msec()
	var max_time = 16  # Maximum milliseconds to spend processing
	
	# While we have active cells and haven't exceeded time budget
	while active_count > 0 and cells_processed < max_cells_per_tick and Time.get_ticks_msec() - start_time < max_time:
		# Get next cell to process
		var coords = active_cells[cells_processed % active_count]
		cells_processed += 1
		
		# Process this cell
		process_cell(coords)
	
	# Re-evaluate active cells after processing
	if cells_processed >= active_count:
		# We processed everything, rebuild active list
		rebuild_active_cells()
	
	# Process breaches separately
	process_breaches()
	
	# Check for entity atmospheric effects
	process_entity_atmosphere_effects()
	
	# Debug output
	if debug_mode:
		print("AtmosphereSystem: Processed ", cells_processed, " cells out of ", active_count, " active")

# Process a single atmospheric cell
func process_cell(coords):
	var tile_coords = Vector2i(coords.x, coords.y)
	var z_level = coords.z
	
	# Get the tile
	var tile = get_tile_data(tile_coords, z_level)
	if not tile:
		# Invalid tile, remove from active list
		remove_active_cell(coords)
		return
	
	# Get atmosphere data
	var atmosphere = get_atmosphere_data(tile)
	if not atmosphere:
		# No atmosphere data, remove from active list
		remove_active_cell(coords)
		return
	
	# Store old state for comparison
	var old_atmosphere = atmosphere.duplicate()
	var old_pressure = calculate_pressure(old_atmosphere)
	
	# Skip if tile has breach (handled separately)
	if tile.get("breach", false):
		return
	
	# Get neighboring tiles
	var neighbors = get_neighboring_tiles(tile_coords, z_level)
	
	# Process gas exchange with neighbors
	for neighbor in neighbors:
		var neighbor_tile = get_tile_data(neighbor, z_level)
		if not neighbor_tile:
			continue
			
		var neighbor_atmosphere = get_atmosphere_data(neighbor_tile)
		if not neighbor_atmosphere:
			continue
			
		# Skip if neighbor has breach (handled separately)
		if neighbor_tile.get("breach", false):
			continue
			
		# Check for airtight barrier
		if is_airtight_barrier(tile_coords, neighbor, z_level):
			# No gas exchange, but still some heat transfer through walls
			process_heat_transfer_through_barrier(atmosphere, neighbor_atmosphere, tile_coords, neighbor, z_level)
			continue
		
		# Process gas exchange between cells
		process_gas_exchange(atmosphere, neighbor_atmosphere, tile_coords, neighbor, z_level)
		
		# Activate neighbor cell
		add_active_cell(Vector3(neighbor.x, neighbor.y, z_level))
	
	# Process reactions in this cell
	process_reactions(atmosphere, tile_coords, z_level)
	
	# Calculate new pressure
	var new_pressure = calculate_pressure(atmosphere)
	
	# Check for significant changes
	var pressure_delta = abs(new_pressure - old_pressure)
	var temp_delta = abs(atmosphere.get("temperature", T20C) - old_atmosphere.get("temperature", T20C))
	
	# If changes are small, consider removing from active list
	if pressure_delta < 0.1 and temp_delta < 0.1:
		remove_active_cell(coords)
	
	# Check if we need to issue warning for dangerous conditions
	check_warning_conditions(atmosphere, new_pressure, tile_coords, z_level)
	
	# Update tile with new atmosphere data
	update_atmosphere_data(tile, atmosphere, tile_coords, z_level)
	
	# Emit signal with changes
	emit_signal("atmosphere_changed", coords, old_atmosphere, atmosphere)

# Process gas exchange between two cells
func process_gas_exchange(atmos1, atmos2, tile1, tile2, z_level):
	# Calculate pressure difference
	var pressure1 = calculate_pressure(atmos1)
	var pressure2 = calculate_pressure(atmos2)
	var pressure_diff = pressure1 - pressure2
	
	# Skip if difference is negligible
	if abs(pressure_diff) < 0.1:
		return
	
	# Calculate flow rate based on pressure difference
	var flow_direction = 1 if pressure_diff > 0 else -1
	var flow_rate = 0.4 * min(1.0, abs(pressure_diff) / 100.0)  # 0-40% transfer rate
	
	# Transfer gases from higher to lower pressure
	if flow_direction > 0:  # from atmos1 to atmos2
		for gas in atmos1.keys():
			if gas == "temperature":
				continue
				
			# Skip if gas doesn't exist
			if typeof(atmos1[gas]) != TYPE_FLOAT:
				continue
				
			# Calculate amount to transfer
			var transfer_amount = atmos1[gas] * flow_rate
			
			# Ensure target gas entry exists
			if not gas in atmos2:
				atmos2[gas] = 0.0
				
			# Transfer
			atmos1[gas] -= transfer_amount
			atmos2[gas] += transfer_amount
	else:  # from atmos2 to atmos1
		for gas in atmos2.keys():
			if gas == "temperature":
				continue
				
			# Skip if gas doesn't exist
			if typeof(atmos2[gas]) != TYPE_FLOAT:
				continue
				
			# Calculate amount to transfer
			var transfer_amount = atmos2[gas] * flow_rate
			
			# Ensure target gas entry exists
			if not gas in atmos1:
				atmos1[gas] = 0.0
				
			# Transfer
			atmos2[gas] -= transfer_amount
			atmos1[gas] += transfer_amount
	
	# Heat exchange alongside gas exchange
	process_heat_exchange(atmos1, atmos2, OPEN_HEAT_TRANSFER_COEFFICIENT)

# Process heat transfer through walls and barriers
func process_heat_transfer_through_barrier(atmos1, atmos2, tile1, tile2, z_level):
	# Determine barrier type coefficient
	var barrier_coefficient = WALL_HEAT_TRANSFER_COEFFICIENT
	
	# Check for window
	var tile1_data = get_tile_data(tile1, z_level)
	var tile2_data = get_tile_data(tile2, z_level)
	
	# Check for window type
	if "door" in tile1_data or "door" in tile2_data:
		# Doors transfer some heat even when closed
		barrier_coefficient = 0.05
	elif "window" in tile1_data or "window" in tile2_data:
		barrier_coefficient = WINDOW_HEAT_TRANSFER_COEFFICIENT
	elif world and world.has_method("is_window_at"):
		if world.is_window_at(tile1, z_level) or world.is_window_at(tile2, z_level):
			barrier_coefficient = WINDOW_HEAT_TRANSFER_COEFFICIENT
	
	# Process heat exchange with appropriate coefficient
	process_heat_exchange(atmos1, atmos2, barrier_coefficient)

# Process heat exchange between two atmospheres
func process_heat_exchange(atmos1, atmos2, coefficient):
	# Skip if either lacks temperature data
	if not "temperature" in atmos1 or not "temperature" in atmos2:
		if not "temperature" in atmos1:
			atmos1.temperature = T20C
		if not "temperature" in atmos2:
			atmos2.temperature = T20C
	
	# Calculate thermal energy in each cell
	var energy1 = atmos1.temperature
	var energy2 = atmos2.temperature
	
	# Calculate energy transfer
	var energy_diff = energy1 - energy2
	var transfer = energy_diff * coefficient
	
	# Apply transfer
	atmos1.temperature -= transfer
	atmos2.temperature += transfer

# Process chemical reactions in an atmosphere
func process_reactions(atmosphere, coords, z_level):
	# Skip if no temperature data
	if not "temperature" in atmosphere:
		atmosphere.temperature = T20C
	
	# Check each reaction for applicability
	for reaction in gas_reactions:
		# Check temperature requirement
		if atmosphere.temperature < reaction.min_temp:
			continue
			
		# Check if all reactants are present
		var can_react = true
		var min_ratio = INF
		
		for gas in reaction.reactants:
			if not gas in atmosphere or atmosphere[gas] < reaction.reactants[gas]:
				can_react = false
				break
				
			# Calculate limiting ratio
			var ratio = atmosphere[gas] / reaction.reactants[gas]
			min_ratio = min(min_ratio, ratio)
		
		if not can_react:
			continue
			
		# Calculate reaction intensity (1.0 means full reaction)
		var intensity = min(1.0, min_ratio)
		
		# Consume reactants
		for gas in reaction.reactants:
			atmosphere[gas] -= reaction.reactants[gas] * intensity
		
		# Add products
		for gas in reaction.products:
			if not gas in atmosphere:
				atmosphere[gas] = 0.0
			atmosphere[gas] += reaction.products[gas] * intensity
		
		# Apply energy change
		atmosphere.temperature += reaction.energy_released * intensity / 20.0
		
		# Add cell to active list for next cycle
		add_active_cell(Vector3(coords.x, coords.y, z_level))
		
		# Emit reaction signal
		emit_signal("reaction_occurred", Vector3(coords.x, coords.y, z_level), reaction.name, intensity)

# Process active breaches
func process_breaches():
	for i in range(active_breaches.size() - 1, -1, -1):
		var breach = active_breaches[i]
		
		# Get tile data
		var tile_coords = Vector2i(breach.coords.x, breach.coords.y)
		var z_level = breach.coords.z
		var tile = get_tile_data(tile_coords, z_level)
		
		# Skip if invalid or breach sealed
		if not tile or not tile.get("breach", false):
			# Breach was sealed
			active_breaches.remove_at(i)
			emit_signal("breach_sealed", breach.coords)
			continue
		
		# Get atmosphere data
		var atmosphere = get_atmosphere_data(tile)
		if not atmosphere:
			continue
		
		# Process breach effects
		var vent_rate = breach.size * 0.4  # 40% per step for size 1
		
		# Vent gases to space
		for gas in atmosphere.keys():
			if gas == "temperature":
				continue
				
			if typeof(atmosphere[gas]) == TYPE_FLOAT:
				atmosphere[gas] *= (1.0 - vent_rate)
		
		# Cool down to space temperature
		if "temperature" in atmosphere:
			atmosphere.temperature = lerp(atmosphere.temperature, TCMB, vent_rate)
		
		# Add to active list for next cycle
		add_active_cell(breach.coords)
		
		# Process neighboring tiles
		var neighbors = get_neighboring_tiles(tile_coords, z_level)
		for neighbor in neighbors:
			# Skip if blocked by airtight barrier
			if is_airtight_barrier(tile_coords, neighbor, z_level):
				continue
				
			add_active_cell(Vector3(neighbor.x, neighbor.y, z_level))
			
			# Get neighbor data
			var neighbor_tile = get_tile_data(neighbor, z_level)
			if not neighbor_tile:
				continue
				
			var neighbor_atmosphere = get_atmosphere_data(neighbor_tile)
			if not neighbor_atmosphere:
				continue
			
			# Apply strong pull toward breach
			var pull_rate = 0.3 * breach.size
			
			for gas in neighbor_atmosphere.keys():
				if gas == "temperature":
					continue
					
				if typeof(neighbor_atmosphere[gas]) == TYPE_FLOAT:
					neighbor_atmosphere[gas] *= (1.0 - pull_rate * 0.5)
			
			# Cool neighbor due to rapid depressurization
			if "temperature" in neighbor_atmosphere:
				neighbor_atmosphere.temperature -= 5.0 * pull_rate
			
			# Update neighbor atmosphere
			update_atmosphere_data(neighbor_tile, neighbor_atmosphere, neighbor, z_level)

# Process atmosphere effects on entities
func process_entity_atmosphere_effects():
	# Skip if no spatial manager
	if not spatial_manager:
		return
	
	# Get all entity types we need to check
	var entity_types = ["character", "human", "mob"]
	var entities = []
	
	# Collect entities of relevant types
	for type in entity_types:
		var type_entities = spatial_manager.get_entities_by_type(type)
		for entity in type_entities:
			if not entity in entities:
				entities.append(entity)
	
	# Process each entity
	for entity in entities:
		process_entity_atmosphere(entity)

# Process atmosphere effects for a single entity
func process_entity_atmosphere(entity):
	# Get entity position
	var entity_pos = entity.position
	var z_level = entity.current_z_level if "current_z_level" in entity else 0
	
	# Get tile
	var tile_coords = world.get_tile_at(entity_pos) if world else Vector2i(floor(entity_pos.x / 32), floor(entity_pos.y / 32))
	var tile = get_tile_data(tile_coords, z_level)
	
	if not tile:
		# Entity is in void space - immediate effects
		apply_void_effects(entity, 1.0)
		return
	
	# Get atmosphere data
	var atmosphere = get_atmosphere_data(tile)
	if not atmosphere:
		# No atmosphere data - treat as void
		apply_void_effects(entity, 1.0)
		return
	
	# Calculate effects
	var pressure = calculate_pressure(atmosphere)
	var temperature = atmosphere.get("temperature", T20C)
	
	# Apply effects based on conditions
	
	# Pressure effects
	if pressure < HAZARD_LOW_PRESSURE:
		apply_low_pressure_effects(entity, pressure)
	elif pressure > HAZARD_HIGH_PRESSURE:
		apply_high_pressure_effects(entity, pressure)
	
	# Temperature effects
	if temperature < BODYTEMP_COLD_DAMAGE_LIMIT_ONE:
		apply_cold_effects(entity, temperature)
	elif temperature > BODYTEMP_HEAT_DAMAGE_LIMIT_ONE:
		apply_heat_effects(entity, temperature)
	
	# Gas composition effects
	apply_gas_effects(entity, atmosphere, pressure)

# Apply void space effects (no atmosphere)
func apply_void_effects(entity, severity):
	# Skip if entity has protection
	if entity.get("void_protected", false):
		return
	
	# Apply damage
	if entity.has_method("take_damage"):
		var damage = 5.0 * severity
		entity.take_damage(damage, "vacuum")
	
	# Emit signal for UI effects
	emit_signal("entity_atmosphere_effect", entity, "void", severity)

# Apply low pressure effects
func apply_low_pressure_effects(entity, pressure):
	# Calculate severity
	var severity = 1.0 - (pressure / HAZARD_LOW_PRESSURE)
	severity = clamp(severity, 0.0, 1.0)
	
	# Skip if negligible
	if severity < 0.1:
		return
	
	# Skip if entity has protection
	if entity.get("pressure_protected", false):
		return
	
	# Apply damage
	if entity.has_method("take_damage"):
		var damage = LOW_PRESSURE_DAMAGE * severity
		entity.take_damage(damage, "pressure")
	
	# Emit signal for UI effects
	emit_signal("entity_atmosphere_effect", entity, "low_pressure", severity)

# Apply high pressure effects
func apply_high_pressure_effects(entity, pressure):
	# Calculate severity based on how much it exceeds the hazard level
	var severity = (pressure - HAZARD_HIGH_PRESSURE) / HAZARD_HIGH_PRESSURE
	severity = clamp(severity, 0.0, 1.0)
	
	# Skip if negligible
	if severity < 0.1:
		return
	
	# Skip if entity has protection
	if entity.get("pressure_protected", false):
		return
	
	# Apply damage
	if entity.has_method("take_damage"):
		var damage = min(severity * PRESSURE_DAMAGE_COEFFICIENT, MAX_HIGH_PRESSURE_DAMAGE)
		entity.take_damage(damage, "pressure")
	
	# Emit signal for UI effects
	emit_signal("entity_atmosphere_effect", entity, "high_pressure", severity)

# Apply cold temperature effects
func apply_cold_effects(entity, temperature):
	var severity = 0.0
	
	# Calculate severity based on temperature thresholds
	if temperature < BODYTEMP_COLD_DAMAGE_LIMIT_THREE:
		severity = 1.0
	elif temperature < BODYTEMP_COLD_DAMAGE_LIMIT_TWO:
		severity = 0.75
	else:  # BODYTEMP_COLD_DAMAGE_LIMIT_ONE
		severity = 0.5
	
	# Skip if entity has protection
	if entity.get("cold_protected", false):
		return
	
	# Apply damage
	if entity.has_method("take_damage"):
		var damage = severity * TEMPERATURE_DAMAGE_COEFFICIENT
		entity.take_damage(damage, "cold")
	
	# Emit signal for UI effects
	emit_signal("entity_atmosphere_effect", entity, "cold", severity)

# Apply heat temperature effects
func apply_heat_effects(entity, temperature):
	var severity = 0.0
	
	# Calculate severity based on temperature thresholds
	if temperature > BODYTEMP_HEAT_DAMAGE_LIMIT_THREE:
		severity = 1.0
	elif temperature > BODYTEMP_HEAT_DAMAGE_LIMIT_TWO:
		severity = 0.75
	else:  # BODYTEMP_HEAT_DAMAGE_LIMIT_ONE
		severity = 0.5
	
	# Skip if entity has protection
	if entity.get("heat_protected", false):
		return
	
	# Apply damage
	if entity.has_method("take_damage"):
		var damage = severity * TEMPERATURE_DAMAGE_COEFFICIENT
		entity.take_damage(damage, "heat")
	
	# Emit signal for UI effects
	emit_signal("entity_atmosphere_effect", entity, "heat", severity)

# Apply effects from gas composition
func apply_gas_effects(entity, atmosphere, pressure):
	# Skip if pressure is too low for gases to matter
	if pressure < HAZARD_LOW_PRESSURE:
		return
	
	# Check for breathability
	var oxygen_percent = 0.0
	if GAS_TYPE_OXYGEN in atmosphere:
		oxygen_percent = (atmosphere[GAS_TYPE_OXYGEN] / pressure) * 100.0
	
	# Check oxygen levels
	if oxygen_percent < 16.0:  # Minimum safe oxygen percentage
		# Calculate severity
		var severity = 1.0 - (oxygen_percent / 16.0)
		severity = clamp(severity, 0.0, 1.0)
		
		# Skip if entity has protection
		if entity.get("breathing_protected", false):
			return
		
		# Apply damage
		if entity.has_method("take_damage"):
			var damage = severity * 1.0  # Mild damage from low oxygen
			entity.take_damage(damage, "oxygen_deprivation")
		
		# Emit signal for UI effects
		emit_signal("entity_atmosphere_effect", entity, "suffocation", severity)
	
	# Check for toxic gases
	var toxic_severity = 0.0
	
	# Check phoron
	if GAS_TYPE_PHORON in atmosphere:
		var phoron_percent = (atmosphere[GAS_TYPE_PHORON] / pressure) * 100.0
		if phoron_percent > 0.5:  # Toxic threshold
			var phoron_severity = (phoron_percent - 0.5) / 10.0  # Full severity at 10% phoron
			toxic_severity = max(toxic_severity, phoron_severity)
	
	# Check CO2
	if GAS_TYPE_CO2 in atmosphere:
		var co2_percent = (atmosphere[GAS_TYPE_CO2] / pressure) * 100.0
		if co2_percent > 5.0:  # Toxic threshold
			var co2_severity = (co2_percent - 5.0) / 15.0  # Full severity at 20% CO2
			toxic_severity = max(toxic_severity, co2_severity)
	
	# Apply toxic effects
	if toxic_severity > 0.1:
		# Skip if entity has protection
		if entity.get("toxin_protected", false):
			return
		
		# Apply damage
		if entity.has_method("take_damage"):
			var damage = toxic_severity * 2.0
			entity.take_damage(damage, "toxin")
		
		# Emit signal for UI effects
		emit_signal("entity_atmosphere_effect", entity, "toxins", toxic_severity)

# === ATMOSPHERE MANAGEMENT ===
# Initialize atmosphere in the world
func initialize_atmosphere():
	if not world:
		return
	
	# Reset active cells
	active_cells = []
	active_count = 0
	
	# Standard atmosphere
	var standard_atmosphere = {
		GAS_TYPE_OXYGEN: ONE_ATMOSPHERE * O2STANDARD,
		GAS_TYPE_NITROGEN: ONE_ATMOSPHERE * N2STANDARD,
		"temperature": T20C
	}
	
	# Loop through all z-levels
	for z in range(world.z_levels):
		# Tiles that need atmosphere initialization
		var tiles_to_init = []
		
		# Find tiles that need atmosphere
		if z in world.world_data:
			for coords in world.world_data[z]:
				var tile = world.world_data[z][coords]
				
				# Skip tiles with existing atmosphere
				if world.TileLayer.ATMOSPHERE in tile:
					# Add to active cells if it has atmosphere
					add_active_cell(Vector3(coords.x, coords.y, z))
					continue
				
				# Add to initialization list if it needs atmosphere
				if world.TileLayer.FLOOR in tile:
					tiles_to_init.append(coords)
		
		# Initialize atmosphere on tiles that need it
		for coords in tiles_to_init:
			var tile = world.world_data[z][coords]
			
			# Create standard atmosphere data
			var atmosphere = standard_atmosphere.duplicate()
			
			# Adjust based on tile type
			if "tile_type" in tile:
				if tile.tile_type == "space":
					# Space has minimal atmosphere
					atmosphere = {
						GAS_TYPE_OXYGEN: 0.2,
						GAS_TYPE_NITROGEN: 0.5,
						"temperature": 3.0  # Near vacuum
					}
				elif tile.tile_type == "exterior":
					# Exterior has colder, thinner air
					atmosphere = {
						GAS_TYPE_OXYGEN: ONE_ATMOSPHERE * O2STANDARD * 0.7,
						GAS_TYPE_NITROGEN: ONE_ATMOSPHERE * N2STANDARD * 0.7,
						"temperature": 273.15  # 0°C
					}
			
			# Add atmosphere data to tile
			tile[world.TileLayer.ATMOSPHERE] = atmosphere
			
			# Add to active cells
			add_active_cell(Vector3(coords.x, coords.y, z))
	
	print("AtmosphereSystem: Initialized atmospheres for ", active_count, " cells")

# Get references to the world's functions for the atmosphere
func get_tile_data(coords, z_level):
	if not world:
		return null
	
	return world.get_tile_data(coords, z_level)

# Get atmosphere data from a tile
# Get atmosphere data from a tile
func get_atmosphere_data(tile):
	if tile == null or not (tile is Dictionary):
		return null
	
	# Direct atmosphere data
	if "atmosphere" in tile:
		return tile["atmosphere"]
	
	# TileLayer-based atmosphere (preferred)
	if world and world.TileLayer:
		# Access using the enum value directly instead of converting to string
		if world.TileLayer.ATMOSPHERE in tile:
			return tile[world.TileLayer.ATMOSPHERE]
	
	return null

# Update atmosphere data for a tile
func update_atmosphere_data(tile, atmosphere, coords, z_level):
	if not tile:
		return
	
	# Determine which property to update
	if "atmosphere" in tile:
		tile.atmosphere = atmosphere
	elif world and world.TileLayer.ATMOSPHERE in tile:
		tile[world.TileLayer.ATMOSPHERE] = atmosphere

# Calculate total pressure of an atmosphere
func calculate_pressure(atmosphere):
	var total_pressure = 0.0
	
	# Sum all gas pressures
	for gas in atmosphere.keys():
		if gas != "temperature" and typeof(atmosphere[gas]) == TYPE_FLOAT:
			total_pressure += atmosphere[gas]
	
	return total_pressure

# === BREACH HANDLING ===
# Create a new breach at the given coordinates
func create_breach(coords, size = 1.0):
	var tile_coords = Vector2i(coords.x, coords.y) if coords is Vector3 else coords
	var z_level = coords.z if coords is Vector3 else 0
	
	# Get tile data
	var tile = get_tile_data(tile_coords, z_level)
	if not tile:
		return
	
	# Set breach flag
	tile.breach = true
	tile.breach_size = size
	tile.exposed_to_space = true
	
	# Add to active breaches
	var breach_coords = Vector3(tile_coords.x, tile_coords.y, z_level)
	active_breaches.append({
		"id": breach_counter,
		"coords": breach_coords,
		"size": size,
		"created_at": Time.get_ticks_msec()
	})
	breach_counter += 1
	
	# Emit signal
	emit_signal("breach_detected", breach_coords)
	
	# Add to active cells
	add_active_cell(breach_coords)
	
	# Add neighboring tiles to active list
	var neighbors = get_neighboring_tiles(tile_coords, z_level)
	for neighbor in neighbors:
		add_active_cell(Vector3(neighbor.x, neighbor.y, z_level))

# Seal a breach at the given coordinates
func seal_breach(coords):
	var tile_coords = Vector2i(coords.x, coords.y) if coords is Vector3 else coords
	var z_level = coords.z if coords is Vector3 else 0
	
	# Get tile data
	var tile = get_tile_data(tile_coords, z_level)
	if not tile:
		return
	
	# Clear breach flag
	tile.breach = false
	tile.exposed_to_space = false
	if "breach_size" in tile:
		tile.erase("breach_size")
	
	# Emit signal
	emit_signal("breach_sealed", Vector3(tile_coords.x, tile_coords.y, z_level))
	
	# Add to active cells
	add_active_cell(Vector3(tile_coords.x, tile_coords.y, z_level))

# === ACTIVE CELL MANAGEMENT ===
# Add a cell to the active list
func add_active_cell(coords):
	# Check if already in the list
	for i in range(active_count):
		if active_cells[i] == coords:
			return
	
	# Add to list
	if active_count < active_cells.size():
		active_cells[active_count] = coords
	else:
		active_cells.append(coords)
	
	active_count += 1

# Remove a cell from the active list
func remove_active_cell(coords):
	# Find in the list
	for i in range(active_count):
		if active_cells[i] == coords:
			# Move last active cell to this position
			active_count -= 1
			if i < active_count:
				active_cells[i] = active_cells[active_count]
			return

# Rebuild the active cells list
func rebuild_active_cells():
	# Clear the list
	active_cells = []
	active_count = 0
	
	# Add all cells with atmosphere
	if world:
		for z in world.world_data.keys():
			for coords in world.world_data[z].keys():
				var tile = world.world_data[z][coords]
				
				# Skip tiles without atmosphere
				if not world.TileLayer.ATMOSPHERE in tile and not "atmosphere" in tile:
					continue
				
				# Add to active list
				add_active_cell(Vector3(coords.x, coords.y, z))
	
	print("AtmosphereSystem: Rebuilt active cells list with ", active_count, " cells")

# === UTILITY FUNCTIONS ===
# Get neighboring tiles with caching
func get_neighboring_tiles(coords, z_level):
	# Check cache
	var cache_key = str(coords) + "-" + str(z_level)
	if cache_key in tile_neighbors_cache:
		return tile_neighbors_cache[cache_key]
	
	# Calculate neighbors
	var neighbors = [
		Vector2i(coords.x + 1, coords.y),
		Vector2i(coords.x - 1, coords.y),
		Vector2i(coords.x, coords.y + 1),
		Vector2i(coords.x, coords.y - 1)
	]
	
	# Filter invalid tiles
	var valid_neighbors = []
	for neighbor in neighbors:
		if world and world.is_valid_tile(neighbor, z_level):
			valid_neighbors.append(neighbor)
	
	# Cache result
	tile_neighbors_cache[cache_key] = valid_neighbors
	
	return valid_neighbors

# Check if there's an airtight barrier between two tiles
func is_airtight_barrier(tile1, tile2, z_level):
	# Check cache
	var cache_key = str(tile1) + "-" + str(tile2) + "-" + str(z_level)
	if cache_key in cell_airtight_cache:
		return cell_airtight_cache[cache_key]
	
	var result = false
	
	if world:
		# Check if world has specialized function
		if world.has_method("is_airtight_barrier"):
			result = world.is_airtight_barrier(tile1, tile2, z_level)
		else:
			# Fall back to our own implementation
			var tile1_data = world.get_tile_data(tile1, z_level)
			var tile2_data = world.get_tile_data(tile2, z_level)
			
			if tile1_data == null or tile2_data == null:
				result = true
			
			# Check for walls
			elif world.TileLayer.WALL in tile1_data and tile1_data[world.TileLayer.WALL] != null:
				result = true
			elif world.TileLayer.WALL in tile2_data and tile2_data[world.TileLayer.WALL] != null:
				result = true
			
			# Check for closed doors
			elif "door" in tile1_data and "closed" in tile1_data.door and tile1_data.door.closed:
				result = true
			elif "door" in tile2_data and "closed" in tile2_data.door and tile2_data.door.closed:
				result = true
	
	# Cache result
	cell_airtight_cache[cache_key] = result
	
	return result

# Check for warning conditions
func check_warning_conditions(atmosphere, pressure, coords, z_level):
	# Check pressure warnings
	if pressure > HAZARD_HIGH_PRESSURE:
		emit_signal("warning_pressure", Vector3(coords.x, coords.y, z_level), pressure, true)
	elif pressure < HAZARD_LOW_PRESSURE:
		emit_signal("warning_pressure", Vector3(coords.x, coords.y, z_level), pressure, false)
	
	# Check temperature warnings
	if "temperature" in atmosphere:
		var temp = atmosphere.temperature
		if temp > BODYTEMP_HEAT_DAMAGE_LIMIT_ONE:
			emit_signal("warning_temperature", Vector3(coords.x, coords.y, z_level), temp, true)
		elif temp < BODYTEMP_COLD_DAMAGE_LIMIT_ONE:
			emit_signal("warning_temperature", Vector3(coords.x, coords.y, z_level), temp, false)

# Convert temperature from Kelvin to Celsius
func kelvin_to_celsius(kelvin):
	return kelvin - T0C

# Convert temperature from Celsius to Kelvin
func celsius_to_kelvin(celsius):
	return celsius + T0C

# === EVENT HANDLERS ===
# Handle tile changes
func _on_tile_changed(tile_coords, z_level, old_data, new_data):
	# Clear neighbor cache for this tile
	var cache_key = str(tile_coords) + "-" + str(z_level)
	if cache_key in tile_neighbors_cache:
		tile_neighbors_cache.erase(cache_key)
	
	# Clear airtight cache for this tile
	for key in cell_airtight_cache.keys():
		if key.begins_with(str(tile_coords)) or key.find("-" + str(tile_coords)) > 0:
			cell_airtight_cache.erase(key)
	
	# Add to active cells
	add_active_cell(Vector3(tile_coords.x, tile_coords.y, z_level))
	
	# Add neighbors to active cells
	var neighbors = get_neighboring_tiles(tile_coords, z_level)
	for neighbor in neighbors:
		add_active_cell(Vector3(neighbor.x, neighbor.y, z_level))

# Handle door toggling
func _on_door_toggled(tile_coords, z_level, is_open):
	# Clear airtight cache for this tile
	var cache_key_base = str(tile_coords) + "-"
	for key in cell_airtight_cache.keys():
		if key.begins_with(cache_key_base) or key.find("-" + str(tile_coords)) > 0:
			cell_airtight_cache.erase(key)
	
	# Add to active cells
	add_active_cell(Vector3(tile_coords.x, tile_coords.y, z_level))
	
	# Add neighbors to active cells
	var neighbors = get_neighboring_tiles(tile_coords, z_level)
	for neighbor in neighbors:
		add_active_cell(Vector3(neighbor.x, neighbor.y, z_level))
	
	# If this is a room transition, mark rooms for equalization
	if world and world.has_method("equalize_room_pressure"):
		# Find room IDs
		var room_key = Vector3(tile_coords.x, tile_coords.y, z_level)
		if is_open and room_key in world.tile_to_room:
			var room_id = world.tile_to_room[room_key]
			if room_id in world.rooms:
				world.rooms[room_id].needs_equalization = true
				
				# Check neighboring tiles for different rooms
				for neighbor in neighbors:
					var neighbor_key = Vector3(neighbor.x, neighbor.y, z_level)
					if neighbor_key in world.tile_to_room:
						var neighbor_room = world.tile_to_room[neighbor_key]
						if neighbor_room != room_id and neighbor_room in world.rooms:
							world.rooms[neighbor_room].needs_equalization = true

# === DEBUG FUNCTIONS ===
# Enable debug mode
func set_debug_mode(enabled):
	debug_mode = enabled
	print("AtmosphereSystem: Debug mode ", "enabled" if enabled else "disabled")

# Visualize the atmosphere
func visualize_atmosphere(camera_node = null):
	# Create a visualization node if it doesn't exist
	var vis_node = get_node_or_null("VisualizationNode")
	if not vis_node:
		vis_node = Node2D.new()
		vis_node.name = "VisualizationNode"
		add_child(vis_node)
	
	# Clear existing visualization
	for child in vis_node.get_children():
		child.queue_free()
	
	# Get camera position and visible area
	var center_pos = Vector2(0, 0)
	var view_size = Vector2(2000, 2000)
	
	if camera_node:
		center_pos = camera_node.get_camera_screen_center()
		view_size = camera_node.get_viewport_rect().size * camera_node.zoom
	
	# Calculate visible tile range
	var tile_size = 32
	var top_left = center_pos - view_size / 2
	var bottom_right = center_pos + view_size / 2
	
	var min_tile_x = floor(top_left.x / tile_size)
	var min_tile_y = floor(top_left.y / tile_size)
	var max_tile_x = ceil(bottom_right.x / tile_size)
	var max_tile_y = ceil(bottom_right.y / tile_size)
	
	# Visualize active cells
	if visualize_active_cells:
		for i in range(active_count):
			var coords = active_cells[i]
			
			# Skip if outside visible range
			if coords.x < min_tile_x or coords.x > max_tile_x or coords.y < min_tile_y or coords.y > max_tile_y:
				continue
			
			# Create visualization rect
			var rect = ColorRect.new()
			rect.position = Vector2(coords.x * tile_size, coords.y * tile_size)
			rect.size = Vector2(tile_size, tile_size)
			rect.color = Color(1.0, 0.0, 0.0, 0.3)
			vis_node.add_child(rect)
	
	# Visualize temperature or pressure if enabled
	if show_temperature_overlay or show_pressure_overlay:
		for z in range(1):  # Just current z-level
			for x in range(min_tile_x, max_tile_x + 1):
				for y in range(min_tile_y, max_tile_y + 1):
					var tile = get_tile_data(Vector2i(x, y), z)
					if not tile:
						continue
					
					var atmosphere = get_atmosphere_data(tile)
					if not atmosphere:
						continue
					
					if show_temperature_overlay and "temperature" in atmosphere:
						# Create temperature visualization
						var color = get_temperature_color(atmosphere.temperature)
						var rect = ColorRect.new()
						rect.position = Vector2(x * tile_size, y * tile_size)
						rect.size = Vector2(tile_size, tile_size)
						rect.color = color
						vis_node.add_child(rect)
					
					if show_pressure_overlay:
						# Create pressure visualization
						var pressure = calculate_pressure(atmosphere)
						var color = get_pressure_color(pressure)
						var rect = ColorRect.new()
						rect.position = Vector2(x * tile_size, y * tile_size)
						rect.size = Vector2(tile_size, tile_size)
						rect.color = color
						vis_node.add_child(rect)

# Get color based on temperature
func get_temperature_color(temperature):
	# Blue-green-red gradient
	if temperature < T0C:  # Below 0°C
		var t = clamp((temperature - TCMB) / (T0C - TCMB), 0.0, 1.0)
		return Color(0.0, 0.0, 1.0, 0.3 * t)
	elif temperature < T20C:  # 0-20°C
		var t = (temperature - T0C) / (T20C - T0C)
		return Color(0.0, 0.0, 1.0, 0.3).lerp(Color(0.0, 1.0, 0.0, 0.3), t)
	elif temperature < 373.15:  # 20-100°C
		var t = (temperature - T20C) / (373.15 - T20C)
		return Color(0.0, 1.0, 0.0, 0.3).lerp(Color(1.0, 1.0, 0.0, 0.4), t)
	else:  # Above 100°C
		var t = clamp((temperature - 373.15) / 627.0, 0.0, 1.0)  # Caps at 1000K
		return Color(1.0, 1.0, 0.0, 0.4).lerp(Color(1.0, 0.0, 0.0, 0.5), t)

# Get color based on pressure
func get_pressure_color(pressure):
	if pressure < HAZARD_LOW_PRESSURE:  # Danger low
		return Color(0.0, 0.0, 0.0, 0.5)
	elif pressure < WARNING_LOW_PRESSURE:  # Warning low
		var t = (pressure - HAZARD_LOW_PRESSURE) / (WARNING_LOW_PRESSURE - HAZARD_LOW_PRESSURE)
		return Color(0.0, 0.0, 0.0, 0.5).lerp(Color(0.5, 0.5, 0.5, 0.3), t)
	elif pressure < WARNING_HIGH_PRESSURE:  # Normal
		var t = (pressure - WARNING_LOW_PRESSURE) / (WARNING_HIGH_PRESSURE - WARNING_LOW_PRESSURE)
		return Color(0.5, 0.5, 0.5, 0.3).lerp(Color(0.0, 0.0, 1.0, 0.3), t)
	elif pressure < HAZARD_HIGH_PRESSURE:  # Warning high
		var t = (pressure - WARNING_HIGH_PRESSURE) / (HAZARD_HIGH_PRESSURE - WARNING_HIGH_PRESSURE)
		return Color(0.0, 0.0, 1.0, 0.3).lerp(Color(1.0, 0.0, 0.0, 0.4), t)
	else:  # Danger high
		var t = clamp((pressure - HAZARD_HIGH_PRESSURE) / 450.0, 0.0, 1.0)
		return Color(1.0, 0.0, 0.0, 0.4).lerp(Color(1.0, 0.0, 0.0, 0.7), t)

# Print debug information
func print_debug_info():
	print("=== AtmosphereSystem Debug Info ===")
	print("Active cells: ", active_count, " / ", active_cells.size())
	print("Cells processed this tick: ", cells_processed)
	print("Active breaches: ", active_breaches.size())
	print("Cache sizes:")
	print("- Tile neighbors cache: ", tile_neighbors_cache.size())
	print("- Airtight cache: ", cell_airtight_cache.size())
	print("==================================")
