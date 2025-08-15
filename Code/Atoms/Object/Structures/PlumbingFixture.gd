extends BaseObject
class_name PlumbingFixture

# Plumbing-specific properties
@export_group("Plumbing Settings")
@export var fixture_type: String = "generic"
@export var has_water: bool = true
@export var water_temperature: String = "normal" # normal, hot, cold
@export var water_pressure: float = 1.0
@export var drainage_connected: bool = true
@export var can_fill_containers: bool = true

# Usage tracking
var is_in_use: bool = false
var current_user = null
var usage_timer: float = 0.0
var water_running: bool = false

# Effects and sounds
@export var water_sound: AudioStream = null
@export var usage_sound: AudioStream = null
@export var water_particles: PackedScene = null

# Signals
signal water_started(user)
signal water_stopped(user)
signal fixture_used(user, action)
signal container_filled(container, user)
signal cleaning_performed(target, user)

func _ready():
	super()
	entity_type = "plumbing"
	
	add_to_group("plumbing_fixtures")
	
	if fixture_type == "shower":
		add_to_group("shower_fixtures")
	elif fixture_type == "sink":
		add_to_group("sink_fixtures")
	elif fixture_type == "toilet":
		add_to_group("toilet_fixtures")
	
	setup_plumbing_actions()

func _process(delta):
	if usage_timer > 0.0:
		usage_timer -= delta
		if usage_timer <= 0.0:
			_finish_usage()

func setup_plumbing_actions():
	"""Set up plumbing-specific actions"""
	match fixture_type:
		"sink":
			actions.append({"name": "Wash Hands", "icon": "wash", "method": "wash_hands"})
			if can_fill_containers:
				actions.append({"name": "Fill Container", "icon": "fill", "method": "fill_container"})
		"shower":
			actions.append({"name": "Use Shower", "icon": "shower", "method": "use_shower"})
		"toilet":
			actions.append({"name": "Use Toilet", "icon": "toilet", "method": "use_toilet"})

# MULTIPLAYER SYNCHRONIZATION
@rpc("any_peer", "call_local", "reliable")
func sync_water_state(running: bool, user_network_id: String):
	var user = find_user_by_network_id(user_network_id)
	water_running = running
	_update_water_effects(user)

@rpc("any_peer", "call_local", "reliable")
func sync_fixture_usage(action: String, user_network_id: String, duration: float):
	var user = find_user_by_network_id(user_network_id)
	_start_usage_internal(user, action, duration)

# WATER SYSTEM
func start_water(user = null) -> bool:
	"""Start water flow"""
	if not has_water or water_running:
		return false
	
	water_running = true
	_update_water_effects(user)
	
	emit_signal("water_started", user)
	
	# Sync across network
	if multiplayer.has_multiplayer_peer():
		sync_water_state.rpc(true, get_user_network_id(user))
	
	return true

func stop_water(user = null) -> bool:
	"""Stop water flow"""
	if not water_running:
		return false
	
	water_running = false
	_update_water_effects(user)
	
	emit_signal("water_stopped", user)
	
	# Sync across network
	if multiplayer.has_multiplayer_peer():
		sync_water_state.rpc(false, get_user_network_id(user))
	
	return true

func _update_water_effects(user = null):
	"""Update water visual and audio effects"""
	if water_running:
		# Play water sound
		if water_sound:
			play_audio(water_sound, -10, true)  # Loop water sound
		
		# Start water particles
		if water_particles:
			var particles = water_particles.instantiate()
			add_child(particles)
			particles.name = "WaterParticles"
			particles.emitting = true
	else:
		# Stop water sound
		var audio_player = get_node_or_null("AudioPlayer")
		if audio_player:
			audio_player.stop()
		
		# Stop water particles
		var particles = get_node_or_null("WaterParticles")
		if particles:
			particles.emitting = false
			# Remove after particles finish
			var timer = get_tree().create_timer(2.0)
			timer.timeout.connect(func(): if particles: particles.queue_free())

# USAGE ACTIONS
func wash_hands(user) -> bool:
	"""Wash user's hands"""
	if is_in_use:
		show_user_message(user, "Someone is already using " + get_entity_name(self) + ".")
		return false
	
	return _start_usage(user, "wash_hands", 3.0)

func use_shower(user) -> bool:
	"""Use shower"""
	if is_in_use:
		show_user_message(user, "Someone is already using the shower.")
		return false
	
	return _start_usage(user, "shower", 30.0)

func use_toilet(user) -> bool:
	"""Use toilet"""
	if is_in_use:
		show_user_message(user, "The toilet is occupied.")
		return false
	
	return _start_usage(user, "toilet", 5.0)

func fill_container(user, container = null) -> bool:
	"""Fill a container with water"""
	if not can_fill_containers or not has_water:
		return false
	
	# Find container in user's hands if not specified
	if not container:
		if user.has_method("get_active_item"):
			container = user.get_active_item()
	
	if not container or not container.has_method("can_be_filled"):
		show_user_message(user, "You need a container to fill!")
		return false
	
	if not container.can_be_filled():
		show_user_message(user, "The " + get_entity_name(container) + " is already full!")
		return false
	
	return _fill_container_internal(container, user)

func _start_usage(user, action: String, duration: float) -> bool:
	"""Start using the fixture"""
	if not can_interact(user):
		return false
	
	_start_usage_internal(user, action, duration)
	
	# Sync across network
	if multiplayer.has_multiplayer_peer():
		sync_fixture_usage.rpc(action, get_user_network_id(user), duration)
	
	return true

func _start_usage_internal(user, action: String, duration: float):
	"""Internal usage logic"""
	is_in_use = true
	current_user = user
	usage_timer = duration
	
	# Start water for most actions
	if action in ["wash_hands", "shower", "fill_container"]:
		start_water(user)
	
	# Play usage sound
	if usage_sound:
		play_audio(usage_sound, -8)
	
	# Show usage message
	match action:
		"wash_hands":
			show_user_message(user, "You start washing your hands.")
		"shower":
			show_user_message(user, "You step into the shower.")
			if user.has_method("set_showering"):
				user.set_showering(true)
		"toilet":
			show_user_message(user, "You use the toilet.")
	
	emit_signal("fixture_used", user, action)

func _finish_usage():
	"""Finish using the fixture"""
	if not current_user:
		return
	
	var user = current_user
	var was_showering = false
	
	# Apply effects based on fixture type
	match fixture_type:
		"sink":
			apply_washing_effects(user)
		"shower":
			apply_shower_effects(user)
			if user.has_method("set_showering"):
				user.set_showering(false)
				was_showering = true
		"toilet":
			apply_toilet_effects(user)
	
	# Stop water
	stop_water(user)
	
	# Show completion message
	match fixture_type:
		"sink":
			show_user_message(user, "You finish washing your hands.")
		"shower":
			show_user_message(user, "You step out of the shower.")
		"toilet":
			show_user_message(user, "You finish using the toilet.")
	
	# Reset usage state
	is_in_use = false
	current_user = null
	usage_timer = 0.0

func apply_washing_effects(user):
	"""Apply hand washing effects"""
	if user.has_method("clean_hands"):
		user.clean_hands()
	
	if user.has_method("remove_germs"):
		user.remove_germs("hands")
	
	# Clean held items
	if user.has_method("get_active_item"):
		var item = user.get_active_item()
		if item and item.has_method("clean_blood"):
			item.clean_blood()

func apply_shower_effects(user):
	"""Apply shower effects"""
	# Full body cleaning
	if user.has_method("clean_blood"):
		user.clean_blood()
	
	if user.has_method("remove_germs"):
		user.remove_germs("all")
	
	if user.has_method("extinguish_fire"):
		user.extinguish_fire()
	
	# Clean all worn clothing
	if user.has_method("clean_clothing"):
		user.clean_clothing()
	
	# Apply temperature effects
	apply_water_temperature_effects(user)

func apply_toilet_effects(user):
	"""Apply toilet usage effects"""
	if user.has_method("relieve_bladder"):
		user.relieve_bladder()
	
	if user.has_method("add_hygiene"):
		user.add_hygiene(10)

func apply_water_temperature_effects(user):
	"""Apply temperature effects based on water temperature"""
	if not user.has_method("adjust_body_temperature"):
		return
	
	match water_temperature:
		"hot":
			user.adjust_body_temperature(5.0)
			if user.has_method("add_comfort"):
				user.add_comfort(5)
		"cold":
			user.adjust_body_temperature(-10.0)
			show_user_message(user, "The cold water makes you shiver!")
		"normal":
			user.adjust_body_temperature(2.0)

func _fill_container_internal(container, user) -> bool:
	"""Fill a container with water"""
	if container.has_method("fill_with_water"):
		container.fill_with_water(100)  # Fill 100ml
	elif container.has_method("add_reagent"):
		container.add_reagent("water", 100)
	else:
		return false
	
	emit_signal("container_filled", container, user)
	show_user_message(user, "You fill " + get_entity_name(container) + " with water.")
	
	# Brief water effect
	start_water(user)
	var timer = get_tree().create_timer(2.0)
	timer.timeout.connect(func(): stop_water(user))
	
	return true

# INTERACTION OVERRIDES
func attack_hand(user, params = null) -> bool:
	"""Handle hand interactions"""
	match fixture_type:
		"sink":
			return wash_hands(user)
		"shower":
			return use_shower(user)
		"toilet":
			return use_toilet(user)
		_:
			return super.attack_hand(user, params)

func attackby(item, user, params = null) -> bool:
	"""Handle item interactions"""
	if not item or not user:
		return false
	
	# Handle container filling
	if can_fill_containers and item.has_method("can_be_filled"):
		return fill_container(user, item)
	
	# Handle cleaning items with water
	if water_running and item.has_method("clean_blood"):
		item.clean_blood()
		show_user_message(user, "You clean " + get_entity_name(item) + " with water.")
		return true
	
	# Handle tools for maintenance
	if item.tool_behaviour == "wrench":
		return await perform_maintenance(user, item)
	
	return super.attackby(item, user, params)

func perform_maintenance(user, tool) -> bool:
	"""Perform maintenance on the fixture"""
	if is_in_use:
		show_user_message(user, "You can't perform maintenance while " + get_entity_name(self) + " is in use!")
		return false
	
	show_user_message(user, "You start performing maintenance on " + get_entity_name(self) + "...")
	
	# Simulate work time
	await get_tree().create_timer(5.0).timeout
	
	# Repair/improve fixture
	obj_integrity = min(obj_integrity + 25.0, max_integrity)
	water_pressure = min(water_pressure + 0.2, 2.0)
	
	show_user_message(user, "You finish maintenance on " + get_entity_name(self) + ".")
	return true

# UTILITY METHODS
func play_audio(stream: AudioStream, volume_db: float = 0.0, loop: bool = false) -> void:
	var audio_player = get_node_or_null("AudioPlayer")
	
	if not audio_player:
		audio_player = AudioStreamPlayer2D.new()
		audio_player.name = "AudioPlayer"
		add_child(audio_player)
	
	audio_player.stream = stream
	audio_player.volume_db = volume_db
	
	if loop and stream is AudioStreamOggVorbis:
		stream.loop = true
	
	audio_player.play()

func get_user_network_id(user) -> String:
	"""Get network ID for user"""
	if not user:
		return ""
	
	if user.has_method("get_network_id"):
		return user.get_network_id()
	elif "peer_id" in user:
		return "player_" + str(user.peer_id)
	else:
		return user.get_path()

func find_user_by_network_id(network_id: String):
	"""Find user by network ID"""
	if network_id == "":
		return null
	
	if network_id.begins_with("player_"):
		var peer_id_str = network_id.split("_")[1]
		var peer_id_val = peer_id_str.to_int()
		var players = get_tree().get_nodes_in_group("players")
		for player in players:
			if "peer_id" in player and player.peer_id == peer_id_val:
				return player
	
	return get_node_or_null(network_id)
