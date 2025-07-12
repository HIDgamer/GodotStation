# ReagentItem.gd
extends MedicalItem
class_name ReagentItem

# Reagent-specific properties
@export var is_medicine_container: bool = false  # For pill bottles, etc.
@export var container_type: String = "bottle"    # bottle, syringe, patch, inhaler
@export var consume_on_transfer: bool = true     # If this is consumed after transferring reagents
@export var transfer_efficiency: float = 1.0     # How efficiently reagents are transferred
@export var can_refill: bool = false             # If this can be refilled with reagents
@export var primary_reagent: String = ""         # Main reagent for identification

# For reagent production/mixing
@export var can_mix: bool = false                # If this container supports reagent mixing
@export var temperature: float = 293.15          # 20°C in Kelvin
@export var mix_rate: float = 1.0                # Rate of mixing reactions
@export var catalysts: Dictionary = {}           # Catalysts that might be present

# For pills and patches
@export var dissolve_time: float = 0.5           # Time to dissolve and release reagents
@export var patch_strength: float = 1.0          # For transdermal patches, absorption rate

# UI properties
@export var color_from_reagents: bool = true     # If item color comes from reagents
@export var custom_color: Color = Color.WHITE    # Custom color to use if not from reagents
@export var show_reagent_color: bool = true      # If reagent color should be visible

# Signals
signal reagent_container_updated()
signal reagent_container_emptied()
signal reagent_container_filled()
signal reagent_mixed(reagent1, reagent2, result)

func _ready():
	# Already set has_reagents to true
	has_reagents = true
	
	# Call parent ready
	super._ready()
	
	# Set default properties based on container type
	match container_type:
		"pill":
			absorption_method = "ingestion"
			dissolve_time = 0.5
		"syringe":
			absorption_method = "injection"
			consume_on_transfer = false
			can_refill = true
		"patch":
			absorption_method = "topical"
			dissolve_time = 5.0
		"inhaler":
			absorption_method = "inhalation"
		"cream":
			absorption_method = "topical"
		"bottle":
			can_refill = true
			consume_on_transfer = false
			is_medicine_container = true
	
	# Initialize reagents if needed
	initialize_reagents()
	
	# Update color based on reagents
	update_color()

func initialize_reagents():
	# Don't re-initialize if already has reagents
	if !reagents.is_empty():
		return
	
	# For primary reagent containers, initialize with the primary reagent
	if primary_reagent != "" and reagent_max_volume > 0:
		reagents[primary_reagent] = reagent_max_volume
		reagent_volume = reagent_max_volume
	
	# For medicine containers, initialize as empty
	if is_medicine_container:
		reagent_volume = 0
		reagents.clear()

# Override use method for reagent-specific behavior
func use(user):
	# For containers that need to be used on self or others
	if is_medicine_container and container_type != "pill":
		return await super.use(user)
	
	# For self-use items like pills
	if container_type == "pill" or container_type == "inhaler":
		return await use_on(user, user)
	
	# Syringes and patches need a target
	if container_type == "syringe" or container_type == "patch":
		# Show an error message - need a target
		if user and user.has_method("display_message"):
			var message = "You need to use this on someone."
			user.display_message(message)
		return false
	
	# Default to parent behavior
	return await super.use(user)

# Override use_on for reagent-specific behavior
func use_on(user, target, targeted_limb = ""):
	# Check if we have reagents
	if reagent_volume <= 0:
		if user and user.has_method("display_message"):
			user.display_message("The " + item_name + " is empty!")
		return false
	
	# Look for chemical system on target
	find_target_systems(target)
	
	# Get the appropriate use time
	var actual_use_time = use_self_time if user == target else use_time
	
	# Show "using" message
	if user and user.has_method("display_message"):
		user.display_message("You begin to apply " + item_name + "...")
	
	# Play use sound
	if use_sound:
		play_audio(use_sound)
	
	# Container-specific behavior
	match container_type:
		"pill":
			if user and user.has_method("display_message"):
				user.display_message("You swallow the " + item_name + ".")
			await get_tree().create_timer(dissolve_time).timeout
		_:
			await get_tree().create_timer(actual_use_time).timeout
	
	# Make sure user is still there and close enough
	if !is_instance_valid(user) or !is_instance_valid(target):
		return false
	
	# Check if user is close enough to target
	if user != target:
		var distance = user.global_position.distance_to(target.global_position)
		if distance > 32:  # 1 tile
			if user.has_method("display_message"):
				user.display_message("You need to stay close to apply " + item_name + ".")
			return false
	
	# Transfer reagents to target's chemical system
	var transferred = false
	if target_chem_system:
		transferred = transfer_reagents_to_target(target_chem_system)
	else:
		# Apply effects directly if no chemical system
		apply_reagent_effects_directly(target)
		transferred = true
	
	# Show use messages if successful
	if transferred:
		if user and user.has_method("display_message"):
			if user == target:
				user.display_message(use_self_message % item_name)
			else:
				user.display_message(use_message % item_name)
		
		# Show message to target if different from user
		if target != user and target.has_method("display_message"):
			target.display_message(target_message % [user.entity_name, item_name])
		
		# Emit signal
		var effectiveness = calculate_effectiveness(user)
		emit_signal("medical_item_used", self, user, target, effectiveness)
		
		# Consume if needed
		if consume_on_transfer and should_be_consumed():
			consume_item(user)
		
		# Update state
		if is_medicine_container and !consume_on_transfer:
			update_color()
			emit_signal("reagent_container_updated")
			
			# Check if emptied
			if reagent_volume <= 0:
				emit_signal("reagent_container_emptied")
		
		return true
	
	return false

# Transfer reagents to target's chemical system
func transfer_reagents_to_target(chem_system):
	if reagent_volume <= 0:
		return false
	
	# For each reagent, transfer to the target's appropriate container
	for reagent_name in reagents.duplicate():
		var amount = reagents[reagent_name]
		if amount > 0:
			# Apply transfer efficiency
			var transfer_amount = amount * transfer_efficiency
			
			# Add reagent to target
			var added = chem_system.add_reagent(reagent_name, transfer_amount, absorption_method)
			
			# Reduce amount in this container
			if added > 0:
				reagents[reagent_name] -= added / transfer_efficiency
				reagent_volume -= added / transfer_efficiency
				
				# Remove key if depleted
				if reagents[reagent_name] <= 0:
					reagents.erase(reagent_name)
	
	return true

# Apply reagent effects directly if target doesn't have a chemical system
func apply_reagent_effects_directly(target):
	if reagent_volume <= 0:
		return false
	
	# Find target systems
	find_target_systems(target)
	
	# Skip if no health system
	if !target_health_system:
		return false
	
	# Apply effects based on reagent types
	for reagent_name in reagents:
		var amount = reagents[reagent_name]
		
		# Skip empty reagents
		if amount <= 0:
			continue
		
		# Apply effects based on reagent type
		match reagent_name:
			"bicaridine":
				target_health_system.adjustBruteLoss(-amount * 2)
			"kelotane":
				target_health_system.adjustFireLoss(-amount * 2)
			"dylovene":
				target_health_system.adjustToxLoss(-amount * 2)
			"dexalin":
				target_health_system.adjustOxyLoss(-amount * 2)
			"tricordrazine":
				target_health_system.adjustBruteLoss(-amount)
				target_health_system.adjustFireLoss(-amount)
				target_health_system.adjustToxLoss(-amount)
				target_health_system.adjustOxyLoss(-amount)
			"morphine":
				# Pain reduction
				target_health_system.traumatic_shock = max(0, target_health_system.traumatic_shock - (amount * 5))
				# Add status effect
				if target_status_system:
					target_status_system.add_effect("dizzy", 5.0, 0.5)
			"epinephrine":
				# Stabilize if critical
				if target_health_system.current_state == target_health_system.HealthState.CRITICAL:
					target_health_system.adjustOxyLoss(-amount * 5)
					
				# Reduce bleeding
				if target_blood_system:
					target_blood_system.set_bleeding_rate(max(0, target_blood_system.bleeding_rate - amount))
	
	# Consume reagents
	reagents.clear()
	reagent_volume = 0
	
	return true

# Add reagent to container
func add_reagent(reagent_name: String, amount: float) -> float:
	# Check if we have space
	var available_space = reagent_max_volume - reagent_volume
	
	if available_space <= 0:
		return 0.0
	
	# Add reagent
	var amount_to_add = min(amount, available_space)
	
	if !reagents.has(reagent_name):
		reagents[reagent_name] = amount_to_add
	else:
		reagents[reagent_name] += amount_to_add
	
	# Update total volume
	reagent_volume += amount_to_add
	
	# Update color
	update_color()
	
	# Emit signal
	emit_signal("reagent_added", reagent_name, amount_to_add)
	
	return amount_to_add

# Remove reagent from container
func remove_reagent(reagent_name: String, amount: float) -> float:
	if !reagents.has(reagent_name):
		return 0.0
	
	var available = reagents[reagent_name]
	var amount_to_remove = min(amount, available)
	
	reagents[reagent_name] -= amount_to_remove
	reagent_volume -= amount_to_remove
	
	# Remove key if depleted
	if reagents[reagent_name] <= 0:
		reagents.erase(reagent_name)
	
	# Update color
	update_color()
	
	# Emit signal
	emit_signal("reagent_removed", reagent_name, amount_to_remove)
	
	return amount_to_remove

# Add reagents from another container
func add_reagents_from(source_container):
	if !can_refill:
		return 0
	
	var total_transferred = 0
	
	# Check if source has reagents
	if !source_container.has_method("get_reagents") and !source_container.has("reagents"):
		return 0
	
	var source_reagents = source_container.get_reagents() if source_container.has_method("get_reagents") else source_container.reagents
	
	# Get available space
	var available_space = reagent_max_volume - reagent_volume
	
	if available_space <= 0:
		return 0
	
	# Transfer each reagent
	for reagent_name in source_reagents:
		var amount = source_reagents[reagent_name]
		
		# Skip if empty
		if amount <= 0:
			continue
		
		# Calculate how much to transfer
		var transfer_amount = min(amount, available_space)
		
		# Add to this container
		if add_reagent(reagent_name, transfer_amount) > 0:
			# Remove from source if successful
			if source_container.has_method("remove_reagent"):
				source_container.remove_reagent(reagent_name, transfer_amount)
			elif source_container.has("reagents"):
				source_container.reagents[reagent_name] -= transfer_amount
				if source_container.reagents[reagent_name] <= 0:
					source_container.reagents.erase(reagent_name)
			
			total_transferred += transfer_amount
			available_space -= transfer_amount
			
			# Stop if full
			if available_space <= 0:
				break
	
	# Update appearance
	update_color()
	
	# Emit signals
	emit_signal("reagent_container_updated")
	if reagent_volume >= reagent_max_volume:
		emit_signal("reagent_container_filled")
	
	return total_transferred

# Get all reagents in this container
func get_reagents():
	return reagents.duplicate()

# Mix reagents within this container
func mix_reagents():
	if !can_mix or reagents.size() < 2:
		return false
	
	# This is where you'd implement reaction logic between reagents
	# For example, if water and potassium are mixed, they could explode
	
	# Placeholder for reaction system
	var reacted = false
	
	# Simple example: If reagent A and B exist, they form C
	if reagents.has("reagent_a") and reagents.has("reagent_b"):
		var amount_a = reagents["reagent_a"]
		var amount_b = reagents["reagent_b"]
		
		# Choose the limiting reagent
		var amount_to_react = min(amount_a, amount_b)
		
		# Remove reactants
		reagents["reagent_a"] -= amount_to_react
		reagents["reagent_b"] -= amount_to_react
		
		# Clean up if depleted
		if reagents["reagent_a"] <= 0:
			reagents.erase("reagent_a")
		if reagents["reagent_b"] <= 0:
			reagents.erase("reagent_b")
		
		# Add product
		if !reagents.has("reagent_c"):
			reagents["reagent_c"] = 0
		reagents["reagent_c"] += amount_to_react
		
		# Emit signal
		emit_signal("reagent_mixed", "reagent_a", "reagent_b", "reagent_c")
		reacted = true
	
	# Update color after mixing
	update_color()
	
	return reacted

# Update item color based on reagent contents
func update_color():
	if !color_from_reagents or reagent_volume <= 0:
		modulate = custom_color
		return
	
	# Calculate color based on weighted average of reagent colors
	var final_color = Color(0, 0, 0, 0)
	var total_volume = reagent_volume
	
	for reagent_name in reagents:
		var amount = reagents[reagent_name]
		var reagent_color = get_reagent_color(reagent_name)
		
		# Weight by volume
		var weight = amount / total_volume
		final_color.r += reagent_color.r * weight
		final_color.g += reagent_color.g * weight
		final_color.b += reagent_color.b * weight
		final_color.a += reagent_color.a * weight
	
	# Apply the color
	if show_reagent_color:
		modulate = final_color

# Get color for a specific reagent
func get_reagent_color(reagent_name):
	# Define some default colors for common reagents
	var colors = {
		"bicaridine": Color(0.9, 0.1, 0.1),      # Red
		"kelotane": Color(0.9, 0.7, 0.1),        # Orange
		"dylovene": Color(0.1, 0.9, 0.1),        # Green
		"dexalin": Color(0.1, 0.7, 0.9),         # Cyan
		"tricordrazine": Color(0.7, 0.3, 0.7),   # Purple
		"morphine": Color(0.7, 0.7, 0.7),        # Gray
		"epinephrine": Color(0.9, 0.9, 0.1),     # Yellow
		"nutriment": Color(0.8, 0.8, 0.8),       # White-gray
		"water": Color(0.2, 0.6, 0.9),           # Blue
		"alcohol": Color(0.8, 0.7, 0.5),         # Tan
		"toxin": Color(0.3, 0.9, 0.3),           # Green
	}
	
	# Return color if defined
	if colors.has(reagent_name):
		return colors[reagent_name]
	
	# Or try to get it from the BodyChemicalSystem if it exists
	var world = get_tree().current_scene
	if world:
		var chemical_system = world.get_node_or_null("Player/BodyChemicalSystem")
		if chemical_system and chemical_system.has_method("get_reagent_color"):
			return chemical_system.get_reagent_color(reagent_name)
	
	# Default to white
	return Color.WHITE

# Override examine text
func get_examine_text() -> String:
	var examine_text = await super.get_examine_text()
	
	# Add specific info for reagent containers
	var container_desc = ""
	match container_type:
		"pill":
			container_desc = "A pill containing medication."
		"syringe":
			container_desc = "A syringe for injecting medication."
		"patch":
			container_desc = "A transdermal patch for medication delivery."
		"inhaler":
			container_desc = "An inhaler for respiratory medication."
		"cream":
			container_desc = "A topical cream or ointment."
		"bottle":
			container_desc = "A bottle of medication."
	
	examine_text += "\n" + container_desc
	
	# Show primary reagent if defined
	if primary_reagent != "":
		examine_text += "\nPrimary ingredient: " + primary_reagent
	
	# Show absorption method
	examine_text += "\nAbsorption method: " + absorption_method
	
	# Add reagent information
	examine_text += "\nIt contains " + str(reagent_volume) + "/" + str(reagent_max_volume) + " units of reagents."
		
	# List reagents if not empty
	if !reagents.is_empty():
		examine_text += "\nReagents:"
		for reagent in reagents:
			examine_text += "\n- " + reagent + ": " + str(reagents[reagent]) + " units"
	
	return examine_text

# Fill this container with a specific reagent
func fill_with(reagent_name, amount = -1):
	if !can_refill:
		return 0
	
	# Calculate fill amount
	var fill_amount = amount
	if amount < 0 or amount > reagent_max_volume:
		fill_amount = reagent_max_volume
	
	# Clear existing reagents
	reagents.clear()
	
	# Add new reagent
	reagents[reagent_name] = fill_amount
	reagent_volume = fill_amount
	
	# Update color
	update_color()
	
	# Emit signal
	emit_signal("reagent_container_updated")
	if reagent_volume >= reagent_max_volume:
		emit_signal("reagent_container_filled")
	
	return fill_amount

# Draw reagents from a target into this container (for syringes)
func draw_reagents_from(target, amount):
	if !can_refill or container_type != "syringe":
		return 0
	
	# Check if target has a chemical system
	var target_chem_system = null
	if target.has_method("get_node"):
		target_chem_system = target.get_node_or_null("BodyChemicalSystem")
	
	# Check if we have space
	var available_space = reagent_max_volume - reagent_volume
	if available_space <= 0:
		return 0
	
	var amount_to_draw = min(amount, available_space)
	var total_drawn = 0
	
	# Draw from chemical system if available
	if target_chem_system:
		# Get reagents from bloodstream
		var bloodstream = target_chem_system.get_reagents_in_container("bloodstream")
		
		# Draw each reagent
		for reagent_name in bloodstream:
			var reagent_amount = bloodstream[reagent_name]
			var draw_amount = min(reagent_amount, amount_to_draw - total_drawn)
			
			if draw_amount <= 0:
				continue
			
			# Add to this container
			if add_reagent(reagent_name, draw_amount) > 0:
				# Remove from target's bloodstream
				target_chem_system.remove_reagent_from_bloodstream(reagent_name, draw_amount)
				
				total_drawn += draw_amount
				
				# Stop if we've drawn enough
				if total_drawn >= amount_to_draw:
					break
	# If no chemical system, we could draw from a beaker or other container
	elif "reagents" in target and "reagent_volume" in target:
		# Draw from container
		for reagent_name in target.reagents:
			var reagent_amount = target.reagents[reagent_name]
			var draw_amount = min(reagent_amount, amount_to_draw - total_drawn)
			
			if draw_amount <= 0:
				continue
			
			# Add to this container
			if add_reagent(reagent_name, draw_amount) > 0:
				# Remove from target
				target.reagents[reagent_name] -= draw_amount
				target.reagent_volume -= draw_amount
				
				if target.reagents[reagent_name] <= 0:
					target.reagents.erase(reagent_name)
				
				total_drawn += draw_amount
				
				# Stop if we've drawn enough
				if total_drawn >= amount_to_draw:
					break
	
	# Update color
	update_color()
	
	# Emit signals
	emit_signal("reagent_container_updated")
	if reagent_volume >= reagent_max_volume:
		emit_signal("reagent_container_filled")
	
	return total_drawn

# Override should_be_consumed to respect consume_on_transfer
func should_be_consumed() -> bool:
	return consume_on_transfer
