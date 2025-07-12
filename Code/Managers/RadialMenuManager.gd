extends Node
class_name RadialMenuManager

# Signals
signal option_selected(entity, option)
signal menu_opened(entity)
signal menu_closed()

# References
var world = null
var player = null
var click_system = null

# The actual radial menu
var radial_menu = null

# State tracking
var menu_active = false
var current_entity = null


# Initialize the system
func _ready():
	# Create the radial menu if not using a scene
	if get_child_count() == 0:
		radial_menu = RadialMenu.new()
		radial_menu.name = "RadialMenu"
		add_child(radial_menu)
	else:
		# Try to find an existing RadialMenu child
		radial_menu = get_node_or_null("RadialMenu")
	
	# Connect signals
	if radial_menu:
		radial_menu.connect("option_selected", _on_option_selected)
		radial_menu.connect("menu_closed", _on_menu_closed)
	
	# Connect to world/click system signals
	_connect_to_systems()


# Connect to world and click system
func _connect_to_systems():
	# Connect to parent if it's the world
	if get_parent() and get_parent().has_method("get_tile_data"):
		world = get_parent()
	
	# Find click system
	click_system = get_node_or_null("/root/ClickSystem")
	if !click_system:
		# Try to find in the world node
		if world:
			click_system = world.get_node_or_null("ClickSystem")
	
	# Connect to radial menu request signal
	if click_system and click_system.has_signal("radial_menu_requested"):
		if !click_system.is_connected("radial_menu_requested", Callable(self, "show_radial_menu")):
			click_system.connect("radial_menu_requested", Callable(self, "show_radial_menu"))
	
	# Connect to world signals if needed
	if world:
		var world_interaction_system = world.get_node_or_null("WorldInteractionSystem")
		if world_interaction_system and world_interaction_system.has_signal("radial_menu_requested"):
			if !world_interaction_system.is_connected("radial_menu_requested", Callable(self, "show_radial_menu")):
				world_interaction_system.connect("radial_menu_requested", Callable(self, "show_radial_menu"))


# Show the radial menu
func show_radial_menu(entity, options, position):
	# Set player reference if not already set
	if !player:
		_find_player()
	
	# Store current entity
	current_entity = entity
	menu_active = true
	
	# Process options to ensure callbacks are properly set
	var processed_options = _process_menu_options(entity, options)
	
	# Open the radial menu
	if radial_menu:
		radial_menu.open(entity, processed_options, position)
		emit_signal("menu_opened", entity)
	else:
		print("RadialMenuManager: Error - radial_menu not found")


# Process menu options to ensure callbacks are set
func _process_menu_options(entity, options):
	var processed_options = []
	
	# If no options provided, generate default ones
	if options.size() == 0:
		options = _generate_default_options(entity)
	
	# Process each option
	for option in options:
		var new_option = option.duplicate()
		
		# Add necessary callback if not already present
		if !("callback" in new_option):
			new_option["callback"] = Callable(self, "_execute_option_action").bind(entity, new_option)
		
		processed_options.append(new_option)
	
	return processed_options


# Generate default options for an entity
func _generate_default_options(entity):
	var options = []
	
	# Always add examine
	options.append({
		"name": "Examine",
		"icon": "examine",
		"action": "examine"
	})
	
	# Add options based on entity type and properties
	if entity is Node and "entity_type" in entity:
		match entity.entity_type:
			"character":
				options.append({
					"name": "Talk to",
					"icon": "talk",
					"action": "talk"
				})
				
				options.append({
					"name": "Attack",
					"icon": "attack",
					"action": "attack"
				})
				
				# Add drag option
				options.append({
					"name": "Pull",
					"icon": "pull",
					"action": "pull"
				})
				
				# Add grab option
				options.append({
					"name": "Grab",
					"icon": "grab",
					"action": "grab"
				})
				
			"item":
				if "pickupable" in entity and entity.pickupable:
					options.append({
						"name": "Pick up",
						"icon": "pickup",
						"action": "pickup"
					})
				
				options.append({
					"name": "Use",
					"icon": "use",
					"action": "use"
				})
				
				# Add throw option
				if entity.get("throwable", false):
					options.append({
						"name": "Throw",
						"icon": "throw",
						"action": "throw"
					})
	
	# Add options based on components
	if "door" in entity:
		var door_text = "Close" if !entity.door.closed else "Open"
		options.append({
			"name": door_text + " Door",
			"icon": "door",
			"action": "toggle_door"
		})
		
		# Add lock/unlock option if applicable
		if entity.door.get("can_lock", false):
			var lock_text = "Unlock" if entity.door.locked else "Lock"
			options.append({
				"name": lock_text,
				"icon": "lock",
				"action": "toggle_lock"
			})
	
	# Add options for containers
	if "is_container" in entity and entity.is_container:
		options.append({
			"name": "Open",
			"icon": "open",
			"action": "open"
		})
	
	# Add custom options based on entity's provided methods
	if entity.has_method("get_custom_options"):
		var custom_options = entity.get_custom_options(player)
		options.append_array(custom_options)
	
	return options


# Find the player character
func _find_player():
	# Try from world
	if world and world.has_method("get_player"):
		player = world.get_player()
		return
	
	# Try from root
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
		
		# Try to get grid controller
		if player and !player.has_method("interact_with_entity"):
			var grid_controller = player.get_node_or_null("GridMovementController")
			if grid_controller:
				player = grid_controller
	
	# If still not found, try click system's player reference
	if !player and click_system and click_system.player:
		player = click_system.player


# Execute option action
func _execute_option_action(entity, option):
	if !player:
		_find_player()
		
	if !player:
		print("RadialMenuManager: Cannot execute action - no player reference")
		return
	
	# Actions based on the option
	if "action" in option:
		match option.action:
			"examine":
				if player.has_method("ShiftClickOn"):
					player.ShiftClickOn(entity)
				elif player.has_method("examine"):
					player.examine(entity)
				elif entity.has_method("examine"):
					var examine_text = entity.examine(player)
					_display_message(examine_text)
			
			"use":
				if player.has_method("interact_with_entity"):
					player.interact_with_entity(entity)
				elif entity.has_method("interact"):
					entity.interact(player)
			
			"attack":
				if player.has_method("attack"):
					var active_item = null
					if player.has_method("get_active_item"):
						active_item = player.get_active_item()
					player.attack(entity, active_item)
			
			"pickup":
				if player.has_method("try_pick_up_item"):
					player.try_pick_up_item(entity)
			
			"talk":
				if entity.has_method("talk_to"):
					entity.talk_to(player)
			
			"toggle_door":
				if entity.has_method("toggle"):
					entity.toggle(player)
				elif "door" in entity:
					entity.door.closed = !entity.door.closed
			
			"toggle_lock":
				if entity.has_method("toggle_lock"):
					entity.toggle_lock(player)
				elif "door" in entity and "locked" in entity.door:
					entity.door.locked = !entity.door.locked
			
			"pull":
				if player.has_method("pull_entity"):
					player.pull_entity(entity)
			
			"push":
				if player.has_method("push_entity"):
					player.push_entity(entity)
			
			"grab":
				if player.has_method("grab_entity"):
					player.grab_entity(entity)
			
			"throw":
				if player.has_method("toggle_throw_mode"):
					player.toggle_throw_mode()
				elif player.has_method("enter_throw_mode"):
					player.enter_throw_mode(entity)
			
			"open":
				if entity.has_method("open"):
					entity.open(player)
			
			# Custom actions
			_:
				if "target" in option:
					# Action on a target object
					var target = option.target
					if target and target.has_method(option.action):
						if "params" in option:
							target.call(option.action, entity, option.params)
						else:
							target.call(option.action, entity)
				else:
					# Direct action on entity
					if entity.has_method(option.action):
						if "params" in option:
							entity.call(option.action, player, option.params)
						else:
							entity.call(option.action, player)


# Display message using sensory system
func _display_message(text):
	if !player:
		_find_player()
	
	if player and "sensory_system" in player and player.sensory_system:
		player.sensory_system.display_message(text)
	elif world and "sensory_system" in world and world.sensory_system:
		world.sensory_system.display_message(text)
	else:
		print("Message: ", text)


# Close the menu
func close_menu():
	if radial_menu and menu_active:
		radial_menu.close()


# Option selected handler
func _on_option_selected(option):
	# Forward to any systems that need to know
	emit_signal("option_selected", current_entity, option)


# Menu closed handler
func _on_menu_closed():
	menu_active = false
	emit_signal("menu_closed")


# Input handling if player tries to escape radial menu
func _input(event):
	if !menu_active:
		return
		
	# Close menu on Escape key
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_menu()


# Public API

# Set player reference
func set_player(player_ref):
	player = player_ref


# Set world reference
func set_world(world_ref):
	world = world_ref


# Set click system reference
func set_click_system(click_system_ref):
	click_system = click_system_ref
	
	if click_system and click_system.has_signal("radial_menu_requested"):
		if !click_system.is_connected("radial_menu_requested", Callable(self, "show_radial_menu")):
			click_system.connect("radial_menu_requested", Callable(self, "show_radial_menu"))


# Show a radial menu for tile
func show_tile_menu(tile_coords, z_level, position):
	# Generate tile-specific options
	var options = _generate_tile_options(tile_coords, z_level)
	
	# Show the menu
	show_radial_menu({"tile": tile_coords, "z_level": z_level}, options, position)


# Generate options for a tile
func _generate_tile_options(tile_coords, z_level):
	var options = []
	
	# Get tile data
	var tile_data = null
	if world and world.has_method("get_tile_data"):
		tile_data = world.get_tile_data(tile_coords, z_level)
	
	# Always add examine
	options.append({
		"name": "Examine Tile",
		"icon": "examine", 
		"action": "examine_tile",
		"params": {"position": tile_coords, "z_level": z_level}
	})
	
	# Check for tile objects
	if tile_data:
		# Door options
		if "door" in tile_data and tile_data.door:
			var door_text = "Open" if tile_data.door.closed else "Close"
			options.append({
				"name": door_text + " Door",
				"icon": "door",
				"action": "toggle_door",
				"params": {"position": tile_coords, "z_level": z_level}
			})
			
			# Lock option
			if "locked" in tile_data.door:
				var lock_text = "Unlock" if tile_data.door.locked else "Lock"
				options.append({
					"name": lock_text + " Door",
					"icon": "lock",
					"action": "toggle_door_lock",
					"params": {"position": tile_coords, "z_level": z_level}
				})
		
		# Window options
		if "window" in tile_data:
			options.append({
				"name": "Knock on Window",
				"icon": "knock",
				"action": "knock_window",
				"params": {"position": tile_coords, "z_level": z_level}
			})
	
	return options
