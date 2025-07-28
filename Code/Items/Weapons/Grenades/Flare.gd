extends Grenade
class_name Flare

# Flare properties
var fuel: float = 0.0  # Current fuel in seconds
var lower_fuel_limit: int = 30000  # 300 seconds (5 minutes)
var upper_fuel_limit: int = 30000  # 300 seconds (5 minutes)
var light_range: float = 3.0  # Tiles
var light_color: Color = Color(1.0, 0.5, 0.2)  # Orange-red light
var light_energy: float = 0.8  # Light brightness

# Active components
var active_light: PointLight2D = null
var active_fire_particles: GPUParticles2D = null
var user_squad = null  # For squad-based targeting

# Flicker timer
var flicker_timer: Timer = null
var flicker_interval: float = 0.5

# State persistence
var was_active_before_move: bool = false
var is_depleted: bool = false

# Preloaded resources
static var fire_particle_scene: PackedScene

# Signal for target designation
signal targeting_position(pos, squad)
signal flare_depleted()

func _init():
	super._init()
	obj_name = "M40 FLDP flare"
	obj_desc = "A TGMC standard issue flare utilizing the standard DP canister chassis. Capable of being loaded in any grenade launcher, or thrown by hand."
	grenade_type = GrenadeType.FLARE
	det_time = 0.0  # Activates instantly
	throwforce = 1
	dangerous = false
	
	# Load resources
	if not fire_particle_scene:
		fire_particle_scene = preload("res://Scenes/Effects/Fire.tscn")
	
	# Randomize fuel amount
	fuel = randf_range(lower_fuel_limit, upper_fuel_limit) / 100.0

func _ready():
	super._ready()
	
	# Set initial animation
	if icon:
		set_animation_state("armed")
	
	# If already active, create light
	if active:
		call_deferred("create_light")

# Let inventory system handle basic equipped state, only manage flare-specific logic
func equipped(user, slot: int):
	super.equipped(user, slot)
	
	# Restore effects if active and lost during move
	if active and not active_light:
		call_deferred("create_light")
	
	# Sync flare-specific state
	if multiplayer.has_multiplayer_peer():
		sync_flare_state.rpc(active, fuel, is_depleted, get_item_network_id())

func unequipped(user, slot: int):
	super.unequipped(user, slot)
	
	# Sync state
	if multiplayer.has_multiplayer_peer():
		sync_flare_state.rpc(active, fuel, is_depleted, get_item_network_id())

func picked_up(user):
	super.picked_up(user)
	
	# Restore effects if active
	if active and not active_light:
		call_deferred("create_light")
	
	# Sync flare state when picked up
	if multiplayer.has_multiplayer_peer():
		sync_flare_state.rpc(active, fuel, is_depleted, get_item_network_id())

func handle_drop(user):
	super.handle_drop(user)
	
	# Restore effects if they were lost during drop
	if active and not active_light:
		call_deferred("create_light")
	
	# Sync drop state
	if multiplayer.has_multiplayer_peer():
		sync_flare_state.rpc(active, fuel, is_depleted, get_item_network_id())

func throw_to_position(thrower, target_position: Vector2) -> bool:
	# Store state before throw
	var was_active = active
	var stored_fuel = fuel
	
	# Use parent throw logic
	var result = await super.throw_to_position(thrower, target_position)
	
	# Restore state and effects after throw
	if was_active:
		active = true
		fuel = stored_fuel
		if not active_light:
			call_deferred("create_light")
	
	# Sync throw state
	if multiplayer.has_multiplayer_peer():
		sync_flare_state.rpc(active, fuel, is_depleted, get_item_network_id())
	
	return result

func use(user):
	var result = super.use(user)
	
	# Check if flare is depleted
	if is_depleted:
		if user and user.has_method("show_message"):
			user.show_message("The flare is depleted and cannot be used.", "red")
		return false
	
	# If not active, try to activate
	if not active:
		result = activate(user)
	else:
		# If already active, show message that it's already burning
		if user and user.has_method("show_message"):
			user.show_message("The flare is already burning.", "yellow")
		result = false
	
	return result

func get_item_network_id() -> String:
	if has_method("get_network_id"):
		return get_network_id()
	elif "network_id" in self and network_id != "":
		return str(network_id)
	elif has_meta("network_id"):
		return str(get_meta("network_id"))
	else:
		var new_id = str(get_instance_id()) + "_" + str(Time.get_ticks_msec())
		set_meta("network_id", new_id)
		return new_id

@rpc("any_peer", "call_local", "reliable")
func sync_flare_state(is_active: bool, current_fuel: float, depleted: bool, item_id: String):
	active = is_active
	fuel = current_fuel
	is_depleted = depleted
	
	if active and not active_light:
		call_deferred("create_light")
	elif not active and active_light:
		cleanup_effects()

@rpc("any_peer", "call_local", "reliable")
func sync_flare_activation(activator_id: String, squad_info: Dictionary):
	activate_local(activator_id, squad_info)

@rpc("any_peer", "call_local", "reliable")
func sync_flare_deactivation():
	turn_off_local()

@rpc("any_peer", "call_local", "reliable")
func sync_fuel_update(new_fuel: float):
	update_fuel_local(new_fuel)

@rpc("any_peer", "call_local", "reliable")
func sync_targeting_signal(position: Vector2, squad_data: Dictionary):
	emit_targeting_signal_local(position, squad_data)

@rpc("any_peer", "call_local", "reliable")
func sync_flare_depleted():
	mark_as_depleted_local()

func _enter_tree():
	super._enter_tree()
	
	# Restore effects if we were active before being moved
	if was_active_before_move and active and not active_light:
		call_deferred("create_light")
		was_active_before_move = false

func _exit_tree():
	# Store state before being moved
	if active and active_light:
		was_active_before_move = true
	
	super._exit_tree()

func _process(delta: float):
	super._process(delta)
	
	if not active or is_depleted:
		return
	
	process_fuel_consumption(delta)
	process_targeting_signals(delta)

func process_fuel_consumption(delta: float):
	if fuel > 0:
		fuel -= delta
		
		# Sync fuel updates every 5 seconds to reduce network traffic
		if is_multiplayer_authority() and int(fuel) % 5 == 0 and fmod(fuel, 1.0) < delta:
			if multiplayer.has_multiplayer_peer():
				sync_fuel_update.rpc(fuel)
		
		# Start fade when fuel is low
		if fuel <= 30.0 and active_light and not has_node("FadeTimer"):
			start_fade_out()
		
		# Update light intensity based on fuel
		if active_light and int(fuel) % 3 == 0 and fmod(fuel, 1.0) < delta:
			update_light_intensity()
		
		# Turn off when depleted
		if fuel <= 0:
			if is_multiplayer_authority():
				deplete_flare()
			else:
				mark_as_depleted_local()

func process_targeting_signals(delta: float):
	if active and "is_targeting_flare" in self and self.is_targeting_flare:
		if int(fuel) % 1 == 0 and fmod(fuel, 1.0) < delta:
			var squad_info = get_squad_info_dict()
			
			if is_multiplayer_authority():
				if multiplayer.has_multiplayer_peer():
					sync_targeting_signal.rpc(global_position, squad_info)
				else:
					emit_targeting_signal_local(global_position, squad_info)

func get_squad_info_dict() -> Dictionary:
	var squad_data = {}
	
	if user_squad:
		if "name" in user_squad:
			squad_data["name"] = user_squad.name
		if "id" in user_squad:
			squad_data["id"] = user_squad.id
	
	return squad_data

func update_fuel_local(new_fuel: float):
	fuel = new_fuel
	
	if active_light:
		update_light_intensity()

func update_light_intensity():
	if not active_light:
		return
	
	var fuel_percentage = min(1.0, fuel / (lower_fuel_limit / 100.0))
	active_light.texture_scale = (light_range / 2.0) * (0.8 + 0.2 * fuel_percentage)
	active_light.energy = light_energy * (0.9 + 0.1 * fuel_percentage)

func activate(user = null) -> bool:
	# Check if flare is depleted
	if is_depleted:
		return false
	
	if active:
		return false
	
	var user_id = get_user_id(user)
	var squad_info = get_squad_info(user)
	
	# Sync activation across network
	if multiplayer.has_multiplayer_peer():
		sync_flare_activation.rpc(user_id, squad_info)
	else:
		activate_local(user_id, squad_info)
	
	return true

func activate_local(user_id: String, squad_info: Dictionary):
	if active or is_depleted:
		return false
	
	# Set active state
	active = true
	
	# Store squad info
	if squad_info.size() > 0:
		user_squad = squad_info
	
	# Log activation
	var user = find_user_by_id(user_id)
	if user and "client" in user and user.client:
		print("Flare activated by: ", user.name)
	
	# Play activation sound
	play_activation_sound()
	
	# Update visual state
	set_animation_state("primed")
	update_appearance()
	
	# Create lighting and effects
	create_light()
	
	# Emit signal
	emit_signal("primed", user)
	
	return true

func deplete_flare():
	if not is_multiplayer_authority():
		return
	
	# Sync depletion across network
	if multiplayer.has_multiplayer_peer():
		sync_flare_depleted.rpc()
	else:
		mark_as_depleted_local()

func mark_as_depleted_local():
	active = false
	fuel = 0.0
	is_depleted = true
	was_active_before_move = false
	
	# Update appearance to show depleted state
	set_animation_state("empty")
	update_appearance()
	
	# Clean up all effects
	cleanup_effects()
	
	# Add to depleted items group for inventory system cleanup
	add_to_group("depleted_items")
	
	# Emit depletion signal
	emit_signal("flare_depleted")

func turn_off():
	# Sync deactivation across network
	if multiplayer.has_multiplayer_peer():
		sync_flare_deactivation.rpc()
	else:
		turn_off_local()

func turn_off_local():
	active = false
	was_active_before_move = false
	
	# Update appearance
	set_animation_state("armed")
	update_appearance()
	
	# Clean up all effects
	cleanup_effects()

func play_activation_sound():
	var flare_sound = load("res://Sound/handling/flare_activate_2.ogg")
	if flare_sound:
		play_cached_sound(flare_sound, -5.0)

func create_light():
	# Clean up existing light first
	if active_light:
		cleanup_effects()
	
	# Create primary light
	active_light = PointLight2D.new()
	active_light.name = "FlareLight"
	
	# Load light texture
	var light_texture = load("res://Assets/Effects/Light/Light_Circle.png")
	if light_texture:
		active_light.texture = light_texture
	else:
		active_light.texture = create_simple_light_texture()
	
	# Configure light properties
	active_light.color = light_color
	active_light.energy = light_energy
	active_light.texture_scale = light_range
	active_light.shadow_enabled = true
	
	add_child(active_light)
	
	# Create fire effect
	create_fire_effect()
	
	# Start subtle flickering
	start_flickering()

func create_fire_effect():
	if not fire_particle_scene:
		return
	
	var fire = fire_particle_scene.instantiate()
	if fire:
		add_child(fire)
		
		# Configure for minimal performance impact
		configure_fire_particles(fire)
		
		# Store reference
		active_fire_particles = fire
		
		# Start emitting
		if "emitting" in fire:
			fire.emitting = true

func configure_fire_particles(fire: Node):
	# Reduce particle count
	if "amount" in fire:
		fire.amount = 30
	
	# Set flare color
	fire.modulate = Color(1.0, 0.8, 0.4)
	
	# Disable additional light sources in fire effect
	if fire.has_node("FireLight"):
		fire.get_node("FireLight").queue_free()

func start_flickering():
	if not active_light:
		return
	
	# Clean up existing flicker timer
	if flicker_timer:
		flicker_timer.queue_free()
	
	flicker_timer = Timer.new()
	flicker_timer.name = "FlickerTimer"
	flicker_timer.wait_time = flicker_interval
	flicker_timer.autostart = true
	flicker_timer.timeout.connect(flicker_light)
	add_child(flicker_timer)

func flicker_light():
	if not active_light:
		return
	
	# Calculate flicker based on fuel level
	var fuel_percentage = min(1.0, fuel / (lower_fuel_limit / 100.0))
	var flicker_intensity = 0.05 + (0.1 * (1.0 - fuel_percentage))
	var flicker_amount = randf_range(-flicker_intensity, flicker_intensity)
	
	# Apply flicker to main light
	var base_energy = light_energy * (0.9 + 0.1 * fuel_percentage)
	active_light.energy = clamp(base_energy + flicker_amount, base_energy * 0.8, base_energy * 1.2)

func start_fade_out():
	var fade_timer = Timer.new()
	fade_timer.name = "FadeTimer"
	add_child(fade_timer)
	
	# Create fade tween
	var tween = create_tween()
	
	# Fade out light over 30 seconds
	if active_light:
		tween.tween_property(active_light, "energy", 0.0, 30.0)
	
	# Fade out fire particles
	if active_fire_particles:
		tween.parallel().tween_property(active_fire_particles, "modulate:a", 0.0, 30.0)
	
	# Clean up fade timer when done
	tween.finished.connect(func(): 
		if is_instance_valid(fade_timer):
			fade_timer.queue_free()
	)

func cleanup_effects():
	# Clean up light
	if active_light and is_instance_valid(active_light):
		active_light.queue_free()
		active_light = null
	
	# Clean up fire particles
	if active_fire_particles and is_instance_valid(active_fire_particles):
		active_fire_particles.queue_free()
		active_fire_particles = null
	
	# Stop flickering
	if flicker_timer and is_instance_valid(flicker_timer):
		flicker_timer.queue_free()
		flicker_timer = null
	
	# Remove fade timer if it exists
	if has_node("FadeTimer"):
		get_node("FadeTimer").queue_free()

func emit_targeting_signal_local(position: Vector2, squad_data: Dictionary):
	var squad = null
	if squad_data.size() > 0:
		squad = squad_data
	
	emit_signal("targeting_position", position, squad)

func create_simple_light_texture() -> Texture2D:
	var size = 64
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	
	var center = Vector2(size/2, size/2)
	for x in range(size):
		for y in range(size):
			var dist = Vector2(x, y).distance_to(center)
			if dist <= size/2:
				var alpha = 1.0 - (dist / (size/2))
				image.set_pixel(x, y, Color(1, 1, 1, alpha * alpha))
	
	return ImageTexture.create_from_image(image)

func explode():
	if not active and not is_depleted:
		activate()

func attack_self(user) -> bool:
	# Check if flare is depleted
	if is_depleted:
		if user and user.has_method("show_message"):
			user.show_message("The flare is depleted and cannot be used.", "red")
		return false
	
	if not active:
		return activate(user)
	else:
		# If already active, show message that it's already burning
		if user and user.has_method("show_message"):
			user.show_message("The flare is already burning.", "yellow")
		return false

func throw_impact(hit_atom, speed: float = 5) -> bool:
	var result = super.throw_impact(hit_atom, speed)
	
	# Impact with open turf - check for alien weeds
	if hit_atom and "is_open_turf" in hit_atom and hit_atom.is_open_turf:
		var nodes = get_tree().get_nodes_in_group("alien_weed_nodes")
		for node in nodes:
			if node.global_position.distance_to(global_position) < 16:
				node.queue_free()
				# Use networked depletion system
				if multiplayer.has_multiplayer_peer():
					sync_flare_depleted.rpc()
				else:
					mark_as_depleted_local()
				break
	
	# Impact with living entities
	if hit_atom and hit_atom.is_in_group("entities") and active:
		apply_fire_to_entity(hit_atom)
		
		# Apply damage if launched
		if launched and hit_atom.has_method("take_damage"):
			var damage = randf_range(throwforce * 0.75, throwforce * 1.25)
			hit_atom.take_damage(damage, "burn")
	
	return result

func apply_fire_to_entity(entity: Node):
	if entity.has_method("add_fire_stacks"):
		entity.add_fire_stacks(5)
	elif entity.has_method("ignite"):
		entity.ignite(5)

func update_appearance():
	super.update_appearance()
	
	if has_node("Sprite2D"):
		var sprite = get_node("Sprite2D")
		if is_depleted:
			sprite.modulate = Color(0.5, 0.5, 0.5, 1.0)  # Grayed out when depleted
		elif active:
			sprite.modulate = Color(1.3, 1.2, 1.0, 1.0)  # Bright when active
		else:
			sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Normal when inactive

func get_tooltip_text() -> String:
	var tooltip = obj_name
	
	if is_depleted:
		tooltip += " (Depleted)"
	elif active:
		var minutes = int(fuel) / 60
		var seconds = int(fuel) % 60
		tooltip += " (Active: " + str(minutes) + "m " + str(seconds) + "s remaining)"
	else:
		var minutes = int(fuel) / 60
		var seconds = int(fuel) % 60
		tooltip += " (Fuel: " + str(minutes) + "m " + str(seconds) + "s)"
	
	return tooltip

# Helper functions for multiplayer integration
func get_user_id(user: Node) -> String:
	if not user:
		return ""
	
	if user.has_method("get_network_id"):
		return user.get_network_id()
	elif "peer_id" in user:
		return "player_" + str(user.peer_id)
	elif user.has_meta("network_id"):
		return user.get_meta("network_id")
	else:
		return user.get_path()

func get_squad_info(user: Node) -> Dictionary:
	var squad_info = {}
	
	if user and "assigned_squad" in user and user.assigned_squad:
		squad_info["name"] = user.assigned_squad.get("name", "")
		squad_info["id"] = user.assigned_squad.get("id", 0)
	
	return squad_info

func find_user_by_id(user_id: String) -> Node:
	if user_id == "":
		return null
	
	# Handle player targets
	if user_id.begins_with("player_"):
		var peer_id_str = user_id.split("_")[1]
		var peer_id_val = peer_id_str.to_int()
		return find_player_by_peer_id(peer_id_val)
	
	# Handle path-based targets
	if user_id.begins_with("/"):
		return get_node_or_null(user_id)
	
	return null

func find_player_by_peer_id(peer_id_val: int) -> Node:
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player.has_meta("peer_id") and player.get_meta("peer_id") == peer_id_val:
			return player
		if "peer_id" in player and player.peer_id == peer_id_val:
			return player
	
	return null

func serialize() -> Dictionary:
	var data = super.serialize()
	
	data["fuel"] = fuel
	data["lower_fuel_limit"] = lower_fuel_limit
	data["upper_fuel_limit"] = upper_fuel_limit
	data["light_range"] = light_range
	data["light_color"] = {
		"r": light_color.r,
		"g": light_color.g,
		"b": light_color.b,
		"a": light_color.a
	}
	data["light_energy"] = light_energy
	data["active"] = active
	data["was_active_before_move"] = was_active_before_move
	data["is_depleted"] = is_depleted
	
	return data

func deserialize(data: Dictionary):
	super.deserialize(data)
	
	if "fuel" in data: fuel = data.fuel
	if "lower_fuel_limit" in data: lower_fuel_limit = data.lower_fuel_limit
	if "upper_fuel_limit" in data: upper_fuel_limit = data.upper_fuel_limit
	if "light_range" in data: light_range = data.light_range
	if "light_energy" in data: light_energy = data.light_energy
	if "active" in data: active = data.active
	if "was_active_before_move" in data: was_active_before_move = data.was_active_before_move
	if "is_depleted" in data: is_depleted = data.is_depleted
	
	if "light_color" in data:
		var color_data = data.light_color
		light_color = Color(color_data.r, color_data.g, color_data.b, color_data.a)
	
	# Reactivate if it was active (and not depleted)
	if active and not is_depleted:
		call_deferred("create_light")
