extends Node
class_name BodyChemicalSystem

# === SIGNALS ===
signal reagent_added(reagent_name, amount)
signal reagent_removed(reagent_name, amount)
signal reagent_metabolized(reagent_name, amount)
signal reagent_overdosed(reagent_name)
signal overdose_started(reagent_name)
signal overdose_stopped(reagent_name)
signal addiction_developed(reagent_name)
signal addiction_stage_increased(reagent_name, stage)

# === CONSTANTS ===
const METABOLISM_SPEED = 0.2  # Base metabolism speed (units per second)
const STOMACH_CAPACITY = 100.0  # Maximum volume of reagents in stomach
const BLOOD_CAPACITY = 250.0  # Maximum volume of reagents in bloodstream
const OVERDOSE_PROCESS_INTERVAL = 2.0  # Seconds between overdose processing

# === MEMBER VARIABLES ===
# Reagent containers
var stomach_reagents = {}  # Reagents in stomach (ingested)
var bloodstream_reagents = {}  # Reagents in bloodstream (injected/absorbed)
var touch_reagents = {}  # Reagents on skin (topical)
var lungs_reagents = {}  # Reagents in lungs (inhaled)

# Container volumes
var stomach_volume = 0.0
var bloodstream_volume = 0.0
var touch_volume = 0.0
var lungs_volume = 0.0

# Reagent metadata tracking
var reagent_timestamps = {}  # When reagents were added
var reagent_sources = {}  # Where reagents came from

# Addiction tracking
var addiction_cooldowns = {}  # Cooldown periods for each addiction
var addiction_stages = {}  # Addiction severity for each reagent
var addictions = []  # List of current addictions

# Overdose tracking
var overdose_reagents = []  # List of reagents currently in overdose

# System modifiers
var metabolism_modifier = 1.0  # Metabolism speed multiplier
var absorption_modifier = 1.0  # Absorption speed multiplier
var overdose_threshold_modifier = 1.0  # Modifier for overdose thresholds

# References to other systems
var entity = null
var health_system = null
var blood_system = null
var status_effect_manager = null
var limb_system = null

# Reagent definitions (normally these would be loaded from a data file)
var reagent_definitions = {
	# Basic medicines
	"bicaridine": {
		"name": "Bicaridine",
		"description": "A medication used to treat physical trauma.",
		"color": Color(0.9, 0.1, 0.1),  # Red
		"taste": "bitter",
		"metabolization_rate": 0.2,
		"overdose_threshold": 30,
		"addiction_threshold": 50,
		"effects": {
			"heal_brute": 2.0,
		},
		"overdose_effects": {
			"toxin_damage": 1.0,
			"cause_bleeding": true
		}
	},
	"kelotane": {
		"name": "Kelotane",
		"description": "A medication used to treat burns.",
		"color": Color(0.9, 0.7, 0.1),  # Orange
		"taste": "chalky",
		"metabolization_rate": 0.2,
		"overdose_threshold": 30,
		"addiction_threshold": 50,
		"effects": {
			"heal_burn": 2.0,
		},
		"overdose_effects": {
			"add_burn": 1.0,
		}
	},
	"dylovene": {
		"name": "Dylovene",
		"description": "A broad-spectrum anti-toxin.",
		"color": Color(0.1, 0.9, 0.1),  # Green
		"taste": "bitter",
		"metabolization_rate": 0.2,
		"overdose_threshold": 30,
		"addiction_threshold": 0,  # No addiction
		"effects": {
			"heal_toxin": 2.0,
			"purge_chemicals": ["toxin", "sleeptoxin", "mutagen"]
		},
		"overdose_effects": {
			"purge_all_chemicals": true
		}
	},
	"dexalin": {
		"name": "Dexalin",
		"description": "Used for treating oxygen deprivation.",
		"color": Color(0.1, 0.7, 0.9),  # Cyan
		"taste": "odorless",
		"metabolization_rate": 0.2,
		"overdose_threshold": 30,
		"addiction_threshold": 50,
		"effects": {
			"heal_oxygen": 2.0,
		},
		"overdose_effects": {
			"add_oxygen_loss": 1.0,
		}
	},
	"salbutamol": {
		"name": "Salbutamol",
		"description": "Respiratory stimulant that improves breathing.",
		"color": Color(0.9, 0.9, 0.9),  # White
		"taste": "slightly sweet",
		"metabolization_rate": 0.1,
		"overdose_threshold": 20,
		"addiction_threshold": 0,  # No addiction
		"effects": {
			"heal_oxygen": 1.0,
			"status_effect": "breathing_stabilized",
			"status_duration": 10.0
		},
		"overdose_effects": {
			"heart_damage": 1.0,
		}
	},
	
	# Advanced medicines
	"tricordrazine": {
		"name": "Tricordrazine",
		"description": "A multipurpose healing chemical.",
		"color": Color(0.7, 0.3, 0.7),  # Purple
		"taste": "bitter",
		"metabolization_rate": 0.1,
		"overdose_threshold": 30,
		"addiction_threshold": 60,
		"effects": {
			"heal_brute": 1.0,
			"heal_burn": 1.0,
			"heal_toxin": 1.0,
			"heal_oxygen": 1.0,
		},
		"overdose_effects": {
			"toxin_damage": 2.0,
		}
	},
	"alkysine": {
		"name": "Alkysine",
		"description": "Treats brain damage.",
		"color": Color(0.1, 0.1, 0.9),  # Blue
		"taste": "bitter",
		"metabolization_rate": 0.05,
		"overdose_threshold": 20,
		"addiction_threshold": 0,  # No addiction
		"effects": {
			"heal_brain": 2.0,
		},
		"overdose_effects": {
			"confusion": 20,
			"slur_speech": true
		}
	},
	"morphine": {
		"name": "Morphine",
		"description": "A powerful painkiller with sedative effects.",
		"color": Color(0.7, 0.7, 0.7),  # Gray
		"taste": "numbing",
		"metabolization_rate": 0.1,
		"overdose_threshold": 20,
		"addiction_threshold": 25,
		"effects": {
			"reduce_pain": 5.0,
			"slow_down": 0.7,  # Slows movement
			"status_effect": "dizzy",
			"status_duration": 5.0,
			"status_intensity": 0.5
		},
		"overdose_effects": {
			"status_effect": "unconscious",
			"status_duration": 10.0,
			"heart_damage": 1.0,
		},
		"addiction_effects": {
			"add_pain": 1.0,
			"nausea": true,
			"shakes": true
		}
	},
	"hyronalin": {
		"name": "Hyronalin",
		"description": "Treats radiation damage.",
		"color": Color(0.5, 0.9, 0.5),  # Light green
		"taste": "chalky",
		"metabolization_rate": 0.1,
		"overdose_threshold": 30,
		"addiction_threshold": 0,  # No addiction
		"effects": {
			"heal_radiation": 2.0,
		},
		"overdose_effects": {
			"toxin_damage": 1.0,
		}
	},
	
	# Stimulants and drugs
	"space_drugs": {
		"name": "Space Drugs",
		"description": "A recreational hallucinogen.",
		"color": Color(0.6, 0.1, 0.6),  # Purple
		"taste": "bitter",
		"metabolization_rate": 0.1,
		"overdose_threshold": 15,
		"addiction_threshold": 10,
		"effects": {
			"status_effect": "hallucinating",
			"status_duration": 20.0,
			"status_intensity": 1.0,
			"add_jitter": true
		},
		"overdose_effects": {
			"toxin_damage": 2.0,
			"status_effect": "confusion",
			"status_duration": 30.0,
			"status_intensity": 2.0,
		},
		"addiction_effects": {
			"craving": true,
			"hallucinations": true
		}
	},
	"epinephrine": {
		"name": "Epinephrine",
		"description": "Adrenaline. Stabilizes patients in critical condition.",
		"color": Color(0.9, 0.9, 0.1),  # Yellow 
		"taste": "bitter",
		"metabolization_rate": 0.2,
		"overdose_threshold": 20,
		"addiction_threshold": 0,  # No addiction
		"effects": {
			"reduce_pain": 1.0,
			"stabilize_critical": true,
			"heal_oxygen": 0.5,
			"stamina_boost": 1.0,
			"speed_up": 1.2,  # Movement speed boost
		},
		"overdose_effects": {
			"heart_damage": 2.0,
			"status_effect": "jittery",
			"status_duration": 10.0,
		}
	},
	"stimulants": {
		"name": "Stimulants",
		"description": "Increases stamina and reduces stuns.",
		"color": Color(0.9, 0.5, 0.1),  # Orange
		"taste": "bitter",
		"metabolization_rate": 0.3,
		"overdose_threshold": 20,
		"addiction_threshold": 15,
		"effects": {
			"stamina_boost": 3.0,
			"reduce_stun": true,
			"speed_up": 1.5,  # Movement speed boost
			"status_effect": "stimulated",
			"status_duration": 10.0,
		},
		"overdose_effects": {
			"heart_damage": 2.0,
			"toxin_damage": 1.0,
			"status_effect": "jittery",
			"status_duration": 20.0,
		},
		"addiction_effects": {
			"stamina_drain": 1.0,
			"depression": true,
			"shakes": true
		}
	},
	
	# Toxins
	"toxin": {
		"name": "Toxin",
		"description": "A generic toxin.",
		"color": Color(0.3, 0.9, 0.3),  # Green
		"taste": "bitter",
		"metabolization_rate": 0.1,
		"overdose_threshold": 100,  # Very high
		"addiction_threshold": 0,  # No addiction
		"effects": {
			"toxin_damage": 1.0,
		}
	},
	"sleeptoxin": {
		"name": "Sleep Toxin",
		"description": "A toxin that causes drowsiness.",
		"color": Color(0.1, 0.1, 0.6),  # Dark blue
		"taste": "sweet",
		"metabolization_rate": 0.1,
		"overdose_threshold": 30,
		"addiction_threshold": 0,  # No addiction
		"effects": {
			"status_effect": "drowsy",
			"status_duration": 10.0,
			"status_intensity": 1.0,
			"stamina_drain": 1.0
		},
		"overdose_effects": {
			"status_effect": "unconscious",
			"status_duration": 20.0,
		}
	},
	
	# Food and drink
	"nutriment": {
		"name": "Nutriment",
		"description": "Basic nutrition.",
		"color": Color(0.8, 0.8, 0.8),  # White-gray
		"taste": "bland",
		"metabolization_rate": 0.05,
		"overdose_threshold": 100,  # Very high
		"addiction_threshold": 0,  # No addiction
		"effects": {
			"add_nutrition": 2.0,
			"heal_brute": 0.2,  # Minor healing
		}
	},
	"alcohol": {
		"name": "Alcohol",
		"description": "Alcoholic beverages.",
		"color": Color(0.8, 0.7, 0.5),  # Tan
		"taste": "boozy",
		"metabolization_rate": 0.1,
		"overdose_threshold": 60,
		"addiction_threshold": 30,
		"effects": {
			"status_effect": "drunk",
			"status_duration": 10.0,
			"status_intensity": 0.5,
			"toxin_damage": 0.2,
			"add_jitter": true
		},
		"overdose_effects": {
			"toxin_damage": 1.0,
			"status_effect": "confused",
			"status_duration": 20.0,
			"status_intensity": 1.0,
			"slur_speech": true
		},
		"addiction_effects": {
			"shakes": true,
			"nausea": true,
			"irritability": true
		}
	}
}

# === INITIALIZATION ===
func _ready():
	entity = get_parent()
	_find_systems()
	
	# Set up a timer for regular metabolism processing
	var timer = Timer.new()
	timer.wait_time = 1.0  # Process every second
	timer.autostart = true
	timer.timeout.connect(_on_metabolism_tick)
	add_child(timer)
	
	# Set up a timer for overdose processing
	var overdose_timer = Timer.new()
	overdose_timer.wait_time = OVERDOSE_PROCESS_INTERVAL
	overdose_timer.autostart = true
	overdose_timer.timeout.connect(_on_overdose_tick)
	add_child(overdose_timer)

func _find_systems():
	# Try to find health system
	health_system = entity.get_node_or_null("HealthSystem")
	
	# Try to find blood system
	blood_system = entity.get_node_or_null("BloodSystem")
	
	# Try to find limb system
	limb_system = entity.get_node_or_null("LimbSystem")
	
	# Try to find status effect manager
	status_effect_manager = entity.get_node_or_null("StatusEffectManager")
	
	# If we can't find these directly, try looking for a health connector
	if !health_system:
		var health_connector = entity.get_node_or_null("HealthConnector")
		if health_connector and health_connector.health_system:
			health_system = health_connector.health_system
	
	print("BodyChemicalSystem: Connected to systems")
	print("  - Health: ", "Found" if health_system else "Not found")
	print("  - Blood: ", "Found" if blood_system else "Not found")
	print("  - Limb: ", "Found" if limb_system else "Not found")
	print("  - Status Effect: ", "Found" if status_effect_manager else "Not found")

# === MAIN PROCESS FUNCTIONS ===
# Metabolism processing tick - handle reagent metabolization
func _on_metabolism_tick():
	# Process each container type
	process_stomach_reagents()
	process_bloodstream_reagents()
	process_touch_reagents()
	process_lungs_reagents()
	
	# Process addictions
	process_addictions()

# Process reagents in stomach
func process_stomach_reagents():
	var reagents_to_remove = []
	
	# Loop through each reagent in stomach
	for reagent_name in stomach_reagents:
		var amount = stomach_reagents[reagent_name]
		
		if amount <= 0:
			reagents_to_remove.append(reagent_name)
			continue
		
		# Get metabolism rate for this reagent
		var metabolism_rate = get_reagent_metabolism_rate(reagent_name)
		
		# Calculate amount to metabolize
		var amount_to_metabolize = min(amount, metabolism_rate)
		
		# Reduce amount in stomach
		stomach_reagents[reagent_name] -= amount_to_metabolize
		stomach_volume -= amount_to_metabolize
		
		# Transfer to bloodstream (absorption)
		add_reagent_to_bloodstream(reagent_name, amount_to_metabolize)
		
		# Mark for removal if depleted
		if stomach_reagents[reagent_name] <= 0:
			reagents_to_remove.append(reagent_name)
	
	# Remove depleted reagents
	for reagent_name in reagents_to_remove:
		stomach_reagents.erase(reagent_name)

# Process reagents in bloodstream
func process_bloodstream_reagents():
	var reagents_to_remove = []
	
	# Loop through each reagent in bloodstream
	for reagent_name in bloodstream_reagents:
		var amount = bloodstream_reagents[reagent_name]
		
		if amount <= 0:
			reagents_to_remove.append(reagent_name)
			continue
		
		# Get metabolism rate for this reagent
		var metabolism_rate = get_reagent_metabolism_rate(reagent_name)
		
		# Calculate amount to metabolize
		var amount_to_metabolize = min(amount, metabolism_rate)
		
		# Reduce amount in bloodstream
		bloodstream_reagents[reagent_name] -= amount_to_metabolize
		bloodstream_volume -= amount_to_metabolize
		
		# Apply effects based on metabolized amount
		apply_reagent_effects(reagent_name, amount_to_metabolize)
		
		# Emit metabolism signal
		emit_signal("reagent_metabolized", reagent_name, amount_to_metabolize)
		
		# Check for addiction
		check_for_addiction(reagent_name, amount_to_metabolize)
		
		# Mark for removal if depleted
		if bloodstream_reagents[reagent_name] <= 0:
			reagents_to_remove.append(reagent_name)
			
			# If reagent was in overdose, remove from overdose list
			if overdose_reagents.has(reagent_name):
				overdose_reagents.erase(reagent_name)
				emit_signal("overdose_stopped", reagent_name)
	
	# Remove depleted reagents
	for reagent_name in reagents_to_remove:
		bloodstream_reagents.erase(reagent_name)

# Process reagents on skin (touch)
func process_touch_reagents():
	var reagents_to_remove = []
	
	# Loop through each reagent on skin
	for reagent_name in touch_reagents:
		var amount = touch_reagents[reagent_name]
		
		if amount <= 0:
			reagents_to_remove.append(reagent_name)
			continue
		
		# Touch reagents metabolize/absorb slower
		var absorption_rate = get_reagent_metabolism_rate(reagent_name) * 0.3
		
		# Calculate amount to absorb
		var amount_to_absorb = min(amount, absorption_rate)
		
		# Reduce amount on skin
		touch_reagents[reagent_name] -= amount_to_absorb
		touch_volume -= amount_to_absorb
		
		# Transfer portion to bloodstream
		add_reagent_to_bloodstream(reagent_name, amount_to_absorb * 0.2)
		
		# Apply touch effects directly
		apply_touch_effects(reagent_name, amount_to_absorb)
		
		# Mark for removal if depleted
		if touch_reagents[reagent_name] <= 0:
			reagents_to_remove.append(reagent_name)
	
	# Remove depleted reagents
	for reagent_name in reagents_to_remove:
		touch_reagents.erase(reagent_name)

# Process reagents in lungs
func process_lungs_reagents():
	var reagents_to_remove = []
	
	# Loop through each reagent in lungs
	for reagent_name in lungs_reagents:
		var amount = lungs_reagents[reagent_name]
		
		if amount <= 0:
			reagents_to_remove.append(reagent_name)
			continue
		
		# Lung absorption is faster
		var absorption_rate = get_reagent_metabolism_rate(reagent_name) * 1.5
		
		# Calculate amount to absorb
		var amount_to_absorb = min(amount, absorption_rate)
		
		# Reduce amount in lungs
		lungs_reagents[reagent_name] -= amount_to_absorb
		lungs_volume -= amount_to_absorb
		
		# Transfer to bloodstream (immediate absorption)
		add_reagent_to_bloodstream(reagent_name, amount_to_absorb)
		
		# Mark for removal if depleted
		if lungs_reagents[reagent_name] <= 0:
			reagents_to_remove.append(reagent_name)
	
	# Remove depleted reagents
	for reagent_name in reagents_to_remove:
		lungs_reagents.erase(reagent_name)

# Process overdose effects
func _on_overdose_tick():
	# Check each reagent in bloodstream for overdose
	for reagent_name in bloodstream_reagents:
		var amount = bloodstream_reagents[reagent_name]
		
		# Get the overdose threshold for this reagent
		var overdose_threshold = get_reagent_overdose_threshold(reagent_name)
		
		# Check if over threshold
		if amount >= overdose_threshold:
			# Apply overdose effects if not already overdosing
			if !overdose_reagents.has(reagent_name):
				overdose_reagents.append(reagent_name)
				emit_signal("overdose_started", reagent_name)
			
			# Apply overdose effects
			apply_overdose_effects(reagent_name, amount)
		elif overdose_reagents.has(reagent_name):
			# No longer overdosing
			overdose_reagents.erase(reagent_name)
			emit_signal("overdose_stopped", reagent_name)

# Process addiction effects
func process_addictions():
	# Process each addiction
	for reagent_name in addictions:
		# Skip if cooldown is active
		if addiction_cooldowns.has(reagent_name) and addiction_cooldowns[reagent_name] > 0:
			addiction_cooldowns[reagent_name] -= 1
			continue
		
		# Check if reagent is present in bloodstream
		if bloodstream_reagents.has(reagent_name) and bloodstream_reagents[reagent_name] > 0:
			# Reset cooldown - addiction satisfied
			addiction_cooldowns[reagent_name] = 60  # 1 minute cooldown
			continue
		
		# Apply addiction effects based on stage
		var stage = addiction_stages[reagent_name]
		apply_addiction_effects(reagent_name, stage)
		
		# Increase cooldown for next withdrawal effect
		addiction_cooldowns[reagent_name] = 20  # 20 seconds
		
		# Random chance to increase addiction stage
		if randf() < 0.1:  # 10% chance
			increment_addiction_stage(reagent_name)

# === REAGENT EFFECT FUNCTIONS ===
# Apply effects from reagent metabolism
func apply_reagent_effects(reagent_name, amount):
	# Skip if no definition exists
	if !reagent_definitions.has(reagent_name):
		return
	
	var reagent = reagent_definitions[reagent_name]
	
	# Skip if no effects defined
	if !reagent.has("effects"):
		return
	
	var effects = reagent.effects
	
	# Apply healing effects
	if effects.has("heal_brute") and health_system:
		health_system.adjustBruteLoss(-effects.heal_brute * amount)
	
	if effects.has("heal_burn") and health_system:
		health_system.adjustFireLoss(-effects.heal_burn * amount)
	
	if effects.has("heal_toxin") and health_system:
		health_system.adjustToxLoss(-effects.heal_toxin * amount)
	
	if effects.has("heal_oxygen") and health_system:
		health_system.adjustOxyLoss(-effects.heal_oxygen * amount)
	
	if effects.has("heal_brain") and health_system:
		health_system.adjustBrainLoss(-effects.heal_brain * amount)
	
	if effects.has("heal_radiation") and health_system:
		# If no direct radiation method, apply as toxin healing
		health_system.adjustToxLoss(-effects.heal_radiation * amount)
	
	# Apply damage effects
	if effects.has("toxin_damage") and health_system:
		health_system.adjustToxLoss(effects.toxin_damage * amount)
	
	# Apply pain reduction
	if effects.has("reduce_pain") and health_system:
		health_system.traumatic_shock = max(0, health_system.traumatic_shock - (effects.reduce_pain * amount))
	
	# Add pain
	if effects.has("add_pain") and health_system:
		health_system.traumatic_shock += effects.add_pain * amount
	
	# Stamina effects
	if effects.has("stamina_boost") and health_system:
		health_system.adjustStaminaLoss(-effects.stamina_boost * amount)
	
	if effects.has("stamina_drain") and health_system:
		health_system.adjustStaminaLoss(effects.stamina_drain * amount)
	
	# Status effects
	if effects.has("status_effect") and status_effect_manager:
		var duration = effects.status_duration if effects.has("status_duration") else 10.0
		var intensity = effects.status_intensity if effects.has("status_intensity") else 1.0
		status_effect_manager.add_effect(effects.status_effect, duration, intensity)
	
	# Movement speed effects
	if effects.has("speed_up") and entity.has_method("add_movement_modifier"):
		entity.add_movement_modifier("chemical_speed", effects.speed_up, 10.0)
	
	if effects.has("slow_down") and entity.has_method("add_movement_modifier"):
		entity.add_movement_modifier("chemical_slow", effects.slow_down, 10.0)
	
	# Blood effects
	if effects.has("stop_bleeding") and blood_system:
		blood_system.stop_bleeding()
	
	# Special effects
	if effects.has("stabilize_critical") and health_system and health_system.current_state == health_system.HealthState.CRITICAL:
		health_system.adjustOxyLoss(-5.0)  # Emergency oxygen
		if blood_system:
			blood_system.stop_bleeding()
	
	# Chemical purging - remove specific chemicals
	if effects.has("purge_chemicals"):
		for chem_name in effects.purge_chemicals:
			if bloodstream_reagents.has(chem_name):
				var purge_amount = min(bloodstream_reagents[chem_name], amount)
				bloodstream_reagents[chem_name] -= purge_amount
				bloodstream_volume -= purge_amount
				if bloodstream_reagents[chem_name] <= 0:
					bloodstream_reagents.erase(chem_name)
	
	# Purge all chemicals
	if effects.has("purge_all_chemicals") and effects.purge_all_chemicals:
		for chem_name in bloodstream_reagents.keys():
			if chem_name != reagent_name:  # Don't purge self
				var purge_amount = min(bloodstream_reagents[chem_name], amount * 2)
				bloodstream_reagents[chem_name] -= purge_amount
				bloodstream_volume -= purge_amount

# Apply topical/touch effects
func apply_touch_effects(reagent_name, amount):
	# Skip if no definition exists
	if !reagent_definitions.has(reagent_name):
		return
	
	var reagent = reagent_definitions[reagent_name]
	
	# Skip if no effects defined
	if !reagent.has("effects"):
		return
	
	var effects = reagent.effects
	
	# Touch effects typically apply much weaker versions of normal effects
	var touch_multiplier = 0.2
	
	# Apply healing effects at reduced effectiveness
	if effects.has("heal_brute") and health_system:
		health_system.adjustBruteLoss(-effects.heal_brute * amount * touch_multiplier)
	
	if effects.has("heal_burn") and health_system:
		health_system.adjustFireLoss(-effects.heal_burn * amount * touch_multiplier)
	
	# Apply damage effects
	if effects.has("toxin_damage") and health_system:
		health_system.adjustToxLoss(effects.toxin_damage * amount * touch_multiplier)
	
	# Status effects may still apply from touch
	if effects.has("status_effect") and status_effect_manager:
		var duration = (effects.status_duration if effects.has("status_duration") else 10.0) * touch_multiplier
		var intensity = (effects.status_intensity if effects.has("status_intensity") else 1.0) * touch_multiplier
		status_effect_manager.add_effect(effects.status_effect, duration, intensity)
	
	# Special touch effects
	# For example, some chemicals might cause burns on touch
	if effects.has("touch_burn") and health_system:
		health_system.adjustFireLoss(effects.touch_burn * amount)

# Apply overdose effects
func apply_overdose_effects(reagent_name, amount):
	# Skip if no definition exists
	if !reagent_definitions.has(reagent_name):
		return
	
	var reagent = reagent_definitions[reagent_name]
	
	# Skip if no overdose effects defined
	if !reagent.has("overdose_effects"):
		return
	
	var effects = reagent.overdose_effects
	var overdose_threshold = get_reagent_overdose_threshold(reagent_name)
	var severity = amount / overdose_threshold  # Calculate severity multiplier
	
	# Apply damage effects
	if effects.has("toxin_damage") and health_system:
		health_system.adjustToxLoss(effects.toxin_damage * severity)
	
	if effects.has("heart_damage") and health_system and health_system.organs.has("heart"):
		health_system.apply_organ_damage("heart", effects.heart_damage * severity)
	
	if effects.has("add_burn") and health_system:
		health_system.adjustFireLoss(effects.add_burn * severity)
	
	if effects.has("add_oxygen_loss") and health_system:
		health_system.adjustOxyLoss(effects.add_oxygen_loss * severity)
	
	# Status effects
	if effects.has("status_effect") and status_effect_manager:
		var duration = effects.status_duration if effects.has("status_duration") else 10.0
		var intensity = effects.status_intensity if effects.has("status_intensity") else 1.0
		status_effect_manager.add_effect(effects.status_effect, duration, intensity * severity)
	
	# Special effects
	if effects.has("cause_bleeding") and blood_system:
		blood_system.set_bleeding_rate(blood_system.bleeding_rate + (0.5 * severity))
	
	if effects.has("slur_speech") and status_effect_manager:
		status_effect_manager.add_effect("slurred_speech", 10.0, severity)
	
	# Emit overdose signal
	emit_signal("reagent_overdosed", reagent_name)

# Apply addiction effects
func apply_addiction_effects(reagent_name, stage):
	# Skip if no definition exists
	if !reagent_definitions.has(reagent_name):
		return
	
	var reagent = reagent_definitions[reagent_name]
	
	# Skip if no addiction effects defined
	if !reagent.has("addiction_effects"):
		return
	
	var effects = reagent.addiction_effects
	
	# The severity scales with addiction stage
	var severity = stage * 0.5
	
	# Status effects based on addiction type
	if effects.has("shakes") and status_effect_manager:
		status_effect_manager.add_effect("shaking", 20.0, severity)
	
	if effects.has("nausea") and status_effect_manager:
		status_effect_manager.add_effect("nausea", 20.0, severity)
	
	if effects.has("hallucinations") and status_effect_manager:
		if randf() < 0.3 * stage:  # Chance increases with stage
			status_effect_manager.add_effect("hallucinating", 20.0, severity)
	
	# Pain effects
	if effects.has("add_pain") and health_system:
		health_system.traumatic_shock += effects.add_pain * severity
	
	# Stamina effects
	if effects.has("stamina_drain") and health_system:
		health_system.adjustStaminaLoss(effects.stamina_drain * severity)
	
	# Craving messages
	if effects.has("craving") and entity.has_method("display_message"):
		if randf() < 0.2:  # 20% chance
			var messages = [
				"You feel an intense craving for " + reagent.name + ".",
				"Your body aches for " + reagent.name + ".",
				"You can't stop thinking about " + reagent.name + ".",
				"You need " + reagent.name + " badly."
			]
			var message = messages[randi() % messages.size()]
			entity.display_message(message)

# === REAGENT MANAGEMENT FUNCTIONS ===
# Add reagent to a specific container
func add_reagent(reagent_name, amount, method = "ingestion"):
	# Skip if reagent isn't defined
	if !is_valid_reagent(reagent_name):
		return 0
	
	# Different methods target different containers
	match method:
		"ingestion":
			return add_reagent_to_stomach(reagent_name, amount)
		"injection":
			return add_reagent_to_bloodstream(reagent_name, amount)
		"topical":
			return add_reagent_to_touch(reagent_name, amount)
		"inhalation":
			return add_reagent_to_lungs(reagent_name, amount)
		_:
			return add_reagent_to_stomach(reagent_name, amount)  # Default to ingestion

# Add reagent to stomach
func add_reagent_to_stomach(reagent_name, amount):
	# Check capacity
	if stomach_volume >= STOMACH_CAPACITY:
		return 0
	
	# Calculate how much we can add
	var amount_to_add = min(amount, STOMACH_CAPACITY - stomach_volume)
	
	# Add to stomach
	if stomach_reagents.has(reagent_name):
		stomach_reagents[reagent_name] += amount_to_add
	else:
		stomach_reagents[reagent_name] = amount_to_add
	
	# Update timestamp
	reagent_timestamps[reagent_name] = Time.get_ticks_msec() / 1000.0
	
	# Update volume
	stomach_volume += amount_to_add
	
	# Emit signal
	emit_signal("reagent_added", reagent_name, amount_to_add)
	
	# Apply immediate taste effects
	apply_taste_effects(reagent_name)
	
	return amount_to_add

# Add reagent directly to bloodstream (injection/absorption)
func add_reagent_to_bloodstream(reagent_name, amount):
	# Check capacity
	if bloodstream_volume >= BLOOD_CAPACITY:
		return 0
	
	# Calculate how much we can add
	var amount_to_add = min(amount, BLOOD_CAPACITY - bloodstream_volume)
	
	# Add to bloodstream
	if bloodstream_reagents.has(reagent_name):
		bloodstream_reagents[reagent_name] += amount_to_add
	else:
		bloodstream_reagents[reagent_name] = amount_to_add
	
	# Update timestamp
	reagent_timestamps[reagent_name] = Time.get_ticks_msec() / 1000.0
	
	# Update volume
	bloodstream_volume += amount_to_add
	
	# Emit signal
	emit_signal("reagent_added", reagent_name, amount_to_add)
	
	# Check for immediate overdose
	check_for_overdose(reagent_name)
	
	return amount_to_add

# Add reagent to touch (topical application)
func add_reagent_to_touch(reagent_name, amount):
	# Add to touch container
	if touch_reagents.has(reagent_name):
		touch_reagents[reagent_name] += amount
	else:
		touch_reagents[reagent_name] = amount
	
	# Update volume
	touch_volume += amount
	
	# Emit signal
	emit_signal("reagent_added", reagent_name, amount)
	
	# Apply immediate touch effects
	apply_touch_effects(reagent_name, amount * 0.1)  # Small initial effect
	
	return amount

# Add reagent to lungs (inhalation)
func add_reagent_to_lungs(reagent_name, amount):
	# Add to lungs container
	if lungs_reagents.has(reagent_name):
		lungs_reagents[reagent_name] += amount
	else:
		lungs_reagents[reagent_name] = amount
	
	# Update volume
	lungs_volume += amount
	
	# Emit signal
	emit_signal("reagent_added", reagent_name, amount)
	
	return amount

# Remove reagent from bloodstream
func remove_reagent_from_bloodstream(reagent_name, amount):
	if !bloodstream_reagents.has(reagent_name):
		return 0
	
	var actual_amount = min(bloodstream_reagents[reagent_name], amount)
	
	bloodstream_reagents[reagent_name] -= actual_amount
	bloodstream_volume -= actual_amount
	
	if bloodstream_reagents[reagent_name] <= 0:
		bloodstream_reagents.erase(reagent_name)
	
	# Emit signal
	emit_signal("reagent_removed", reagent_name, actual_amount)
	
	return actual_amount

# Get the total amount of a reagent in all containers
func get_reagent_total(reagent_name):
	var total = 0
	
	if stomach_reagents.has(reagent_name):
		total += stomach_reagents[reagent_name]
	
	if bloodstream_reagents.has(reagent_name):
		total += bloodstream_reagents[reagent_name]
	
	if touch_reagents.has(reagent_name):
		total += touch_reagents[reagent_name]
	
	if lungs_reagents.has(reagent_name):
		total += lungs_reagents[reagent_name]
	
	return total

# Check if the entity has a reagent in any container
func has_reagent(reagent_name):
	return stomach_reagents.has(reagent_name) or bloodstream_reagents.has(reagent_name) or touch_reagents.has(reagent_name) or lungs_reagents.has(reagent_name)

# Purge all reagents (vomiting, stomach pumping)
func purge_stomach():
	stomach_reagents.clear()
	stomach_volume = 0
	
	# Show purge message
	if entity.has_method("display_message"):
		entity.display_message("You vomit up the contents of your stomach!")

# === REAGENT HELPER FUNCTIONS ===
# Get the metabolism rate for a reagent
func get_reagent_metabolism_rate(reagent_name):
	# Default rate if not found
	var base_rate = METABOLISM_SPEED
	
	# Check if we have a definition for this reagent
	if reagent_definitions.has(reagent_name):
		if reagent_definitions[reagent_name].has("metabolization_rate"):
			base_rate = reagent_definitions[reagent_name].metabolization_rate
	
	# Apply metabolism modifier
	return base_rate * metabolism_modifier

# Get overdose threshold for a reagent
func get_reagent_overdose_threshold(reagent_name):
	# Default threshold if not found
	var threshold = 30
	
	# Check if we have a definition for this reagent
	if reagent_definitions.has(reagent_name):
		if reagent_definitions[reagent_name].has("overdose_threshold"):
			threshold = reagent_definitions[reagent_name].overdose_threshold
	
	# Apply overdose threshold modifier
	return threshold * overdose_threshold_modifier

# Check if reagent is valid
func is_valid_reagent(reagent_name):
	return reagent_definitions.has(reagent_name)

# Apply taste effects when reagent enters stomach
func apply_taste_effects(reagent_name):
	# Skip if no definition
	if !reagent_definitions.has(reagent_name):
		return
	
	var reagent = reagent_definitions[reagent_name]
	
	# Skip if no taste defined
	if !reagent.has("taste"):
		return
	
	# Display taste message
	if entity.has_method("display_message"):
		entity.display_message("You taste " + reagent.taste + ".")

# Check if reagent is in overdose
func check_for_overdose(reagent_name):
	# Skip if not in bloodstream
	if !bloodstream_reagents.has(reagent_name):
		return
	
	var amount = bloodstream_reagents[reagent_name]
	var threshold = get_reagent_overdose_threshold(reagent_name)
	
	if amount >= threshold and !overdose_reagents.has(reagent_name):
		# New overdose
		overdose_reagents.append(reagent_name)
		emit_signal("overdose_started", reagent_name)
		
		# Apply immediate overdose effects
		apply_overdose_effects(reagent_name, amount)

# Check if addiction should develop for a reagent
func check_for_addiction(reagent_name, amount_metabolized):
	# Skip if no definition
	if !reagent_definitions.has(reagent_name):
		return
	
	var reagent = reagent_definitions[reagent_name]
	
	# Skip if no addiction threshold defined or it's zero
	if !reagent.has("addiction_threshold") or reagent.addiction_threshold <= 0:
		return
	
	# Check if already addicted
	if addictions.has(reagent_name):
		return
	
	# Check threshold against total amount in bloodstream
	var total_amount = bloodstream_reagents[reagent_name] if bloodstream_reagents.has(reagent_name) else 0
	
	if total_amount >= reagent.addiction_threshold:
		# Chance to develop addiction
		var addiction_chance = reagent.addiction_chance if reagent.has("addiction_chance") else 0.1
		if randf() < addiction_chance * amount_metabolized:
			# Develop addiction
			addictions.append(reagent_name)
			addiction_stages[reagent_name] = 1  # Start at stage 1
			addiction_cooldowns[reagent_name] = 60  # 1 minute cooldown
			
			# Emit signal
			emit_signal("addiction_developed", reagent_name)
			
			# Display message
			if entity.has_method("display_message"):
				entity.display_message("You feel a sudden craving for more " + reagent.name + ".")

# Increase addiction stage
func increment_addiction_stage(reagent_name):
	if !addiction_stages.has(reagent_name):
		addiction_stages[reagent_name] = 1
		return
	
	# Maximum stage is 4
	if addiction_stages[reagent_name] < 4:
		addiction_stages[reagent_name] += 1
		
		# Emit signal
		emit_signal("addiction_stage_increased", reagent_name, addiction_stages[reagent_name])
		
		# Display message
		if entity.has_method("display_message"):
			var reagent_name_display = reagent_definitions[reagent_name].name if reagent_definitions.has(reagent_name) else reagent_name
			var messages = [
				"Your need for " + reagent_name_display + " is growing stronger.",
				"You feel increasingly dependent on " + reagent_name_display + ".",
				"The craving for " + reagent_name_display + " is becoming overwhelming.",
				"You can't function without " + reagent_name_display + "."
			]
			
			entity.display_message(messages[addiction_stages[reagent_name] - 1])

# Cure addiction to a specific reagent
func cure_addiction(reagent_name):
	if !addictions.has(reagent_name):
		return false
	
	# Remove from addictions
	addictions.erase(reagent_name)
	
	# Clear associated data
	if addiction_stages.has(reagent_name):
		addiction_stages.erase(reagent_name)
	
	if addiction_cooldowns.has(reagent_name):
		addiction_cooldowns.erase(reagent_name)
	
	# Display message
	if entity.has_method("display_message"):
		var reagent_name_display = reagent_definitions[reagent_name].name if reagent_definitions.has(reagent_name) else reagent_name
		entity.display_message("You no longer feel dependent on " + reagent_name_display + ".")
	
	return true

# Cure all addictions
func cure_all_addictions():
	var cured = []
	
	for reagent_name in addictions.duplicate():
		if cure_addiction(reagent_name):
			cured.append(reagent_name)
	
	return cured

# === PUBLIC API FUNCTIONS ===
# Set metabolism speed modifier
func set_metabolism_modifier(modifier):
	metabolism_modifier = max(0.1, modifier)
	return metabolism_modifier

# Get current reagents in a specific container
func get_reagents_in_container(container_type):
	match container_type:
		"stomach":
			return stomach_reagents.duplicate()
		"bloodstream":
			return bloodstream_reagents.duplicate()
		"touch":
			return touch_reagents.duplicate()
		"lungs":
			return lungs_reagents.duplicate()
		"all":
			var all_reagents = {}
			
			# Combine all containers
			for reagent_name in stomach_reagents:
				all_reagents[reagent_name] = stomach_reagents[reagent_name]
			
			for reagent_name in bloodstream_reagents:
				if all_reagents.has(reagent_name):
					all_reagents[reagent_name] += bloodstream_reagents[reagent_name]
				else:
					all_reagents[reagent_name] = bloodstream_reagents[reagent_name]
			
			for reagent_name in touch_reagents:
				if all_reagents.has(reagent_name):
					all_reagents[reagent_name] += touch_reagents[reagent_name]
				else:
					all_reagents[reagent_name] = touch_reagents[reagent_name]
			
			for reagent_name in lungs_reagents:
				if all_reagents.has(reagent_name):
					all_reagents[reagent_name] += lungs_reagents[reagent_name]
				else:
					all_reagents[reagent_name] = lungs_reagents[reagent_name]
			
			return all_reagents
	
	return {}

# Get container volumes
func get_container_volume(container_type):
	match container_type:
		"stomach":
			return stomach_volume
		"bloodstream":
			return bloodstream_volume
		"touch":
			return touch_volume
		"lungs":
			return lungs_volume
		"all":
			return stomach_volume + bloodstream_volume + touch_volume + lungs_volume
	
	return 0

# Get reagent color for a specific reagent
func get_reagent_color(reagent_name):
	if reagent_definitions.has(reagent_name) and reagent_definitions[reagent_name].has("color"):
		return reagent_definitions[reagent_name].color
	
	# Default color
	return Color(1, 1, 1)

# Get reagent name from ID
func get_reagent_name(reagent_id):
	if reagent_definitions.has(reagent_id) and reagent_definitions[reagent_id].has("name"):
		return reagent_definitions[reagent_id].name
	
	return reagent_id

# Get the current addiction stage for a reagent
func get_addiction_stage(reagent_name):
	if addiction_stages.has(reagent_name):
		return addiction_stages[reagent_name]
	
	return 0

# Get all current addictions
func get_all_addictions():
	var result = []
	
	for reagent_name in addictions:
		result.append({
			"name": reagent_name,
			"stage": addiction_stages[reagent_name],
			"display_name": get_reagent_name(reagent_name)
		})
	
	return result

# Get all reagents currently in overdose
func get_overdosing_reagents():
	var result = []
	
	for reagent_name in overdose_reagents:
		var amount = bloodstream_reagents[reagent_name] if bloodstream_reagents.has(reagent_name) else 0
		var threshold = get_reagent_overdose_threshold(reagent_name)
		
		result.append({
			"name": reagent_name,
			"amount": amount,
			"threshold": threshold,
			"severity": amount / threshold,
			"display_name": get_reagent_name(reagent_name)
		})
	
	return result

# Get a complete reagent report for medical scanning
func get_reagent_report():
	var report = {
		"containers": {
			"stomach": {
				"volume": stomach_volume,
				"capacity": STOMACH_CAPACITY,
				"reagents": stomach_reagents.duplicate()
			},
			"bloodstream": {
				"volume": bloodstream_volume,
				"capacity": BLOOD_CAPACITY,
				"reagents": bloodstream_reagents.duplicate()
			},
			"touch": {
				"volume": touch_volume,
				"reagents": touch_reagents.duplicate()
			},
			"lungs": {
				"volume": lungs_volume,
				"reagents": lungs_reagents.duplicate()
			}
		},
		"overdosing": get_overdosing_reagents(),
		"addictions": get_all_addictions(),
		"metabolism_rate": metabolism_modifier
	}
	
	return report

# Check if reagent has specific property or effect
func reagent_has_property(reagent_name, property_name):
	if !reagent_definitions.has(reagent_name):
		return false
	
	var reagent = reagent_definitions[reagent_name]
	
	if reagent.has("effects") and reagent.effects.has(property_name):
		return true
	
	return false

# Clear all reagents from all containers
func flush_system():
	# Clear all containers
	stomach_reagents.clear()
	bloodstream_reagents.clear()
	touch_reagents.clear()
	lungs_reagents.clear()
	
	# Reset volumes
	stomach_volume = 0
	bloodstream_volume = 0
	touch_volume = 0
	lungs_volume = 0
	
	# Clear overdosing list
	overdose_reagents.clear()
	
	return true

# Directly add a reagent definition (for custom chemicals)
func add_reagent_definition(reagent_id, definition):
	if reagent_definitions.has(reagent_id):
		# Update existing definition
		for key in definition:
			reagent_definitions[reagent_id][key] = definition[key]
	else:
		# Add new definition
		reagent_definitions[reagent_id] = definition
	
	return true
