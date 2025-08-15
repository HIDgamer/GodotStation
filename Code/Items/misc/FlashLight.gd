@tool
extends Item

class_name Flashlight

signal battery_depleted
signal flashlight_toggled(is_on: bool)
signal battery_warning(battery_level: float)

@export_group("Flashlight Properties")
@export var is_on: bool = false:
	set(value):
		is_on = value
		_update_light_state()
		emit_signal("flashlight_toggled", is_on)

@export var battery_life: float = 100.0:
	set(value):
		battery_life = clamp(value, 0.0, max_battery_life)
		if battery_life <= 0.0:
			_on_battery_depleted()

@export var max_battery_life: float = 100.0
@export var battery_drain_rate: float = 1.0  # Battery units per second when on
@export var low_battery_threshold: float = 20.0

@export_group("Light Settings")
@export var beam_energy: float = 1.5
@export var beam_range: float = 300.0
@export var beam_color: Color = Color(1.0, 0.95, 0.8, 1.0)
@export var beam_width: float = 45.0  # Cone angle in degrees

@export var ambient_energy: float = 0.3
@export var ambient_range: float = 80.0
@export var ambient_color: Color = Color(1.0, 0.9, 0.7, 1.0)

@export_group("Effects")
@export var flicker_on_low_battery: bool = true
@export var flicker_threshold: float = 10.0
@export var flicker_intensity: float = 0.3
@export var use_startup_delay: bool = true
@export var startup_delay: float = 0.2

@export_group("Audio")
@export var click_on_sound: AudioStream = null
@export var click_off_sound: AudioStream = null
@export var low_battery_sound: AudioStream = null

# Light nodes
var beam_light: PointLight2D
var ambient_light: PointLight2D
var _battery_timer: float = 0.0
var _flicker_timer: float = 0.0
var _last_battery_warning: float = 100.0
var _is_flickering: bool = false
var _startup_tween: Tween

func _init():
	super._init()
	item_name = "Flashlight"
	w_class = 2
	force = 8
	attack_verb = ["hits", "bashes", "strikes"]
	equip_slot_flags = Slots.LEFT_HAND | Slots.RIGHT_HAND | Slots.BELT

func _ready():
	super._ready()
	if not beam_light or not ambient_light:
		_setup_lights()
	_update_light_state()
	
	# Load default sounds if not set
	if not click_on_sound:
		click_on_sound = preload("res://Sound/handling/light_on_1.ogg") if ResourceLoader.exists("res://Sound/effects/flashlight_on.wav") else null
	if not click_off_sound:
		click_off_sound = preload("res://Sound/handling/click_2.ogg") if ResourceLoader.exists("res://Sound/effects/flashlight_off.wav") else null
	if not low_battery_sound:
		low_battery_sound = preload("res://Sound/items/synth_reset_key/shortbeep.ogg") if ResourceLoader.exists("res://Sound/effects/low_battery.wav") else null

func _process(delta):
	if is_on and battery_life > 0:
		_drain_battery(delta)
		_handle_low_battery_effects(delta)

func _setup_lights():
	# Create beam light (main flashlight cone)
	beam_light = PointLight2D.new()
	beam_light.name = "BeamLight"
	beam_light.enabled = false
	beam_light.energy = beam_energy
	beam_light.color = beam_color
	beam_light.texture_scale = beam_range / 100.0
	beam_light.shadow_enabled = true
	beam_light.shadow_filter_smooth = 2.0
	add_child(beam_light)
	
	# Create cone texture for directional beam
	var beam_texture = _create_cone_texture()
	beam_light.texture = beam_texture
	
	# Create ambient light (weaker surround light)
	ambient_light = PointLight2D.new()
	ambient_light.name = "AmbientLight"
	ambient_light.enabled = false
	ambient_light.energy = ambient_energy
	ambient_light.color = ambient_color
	ambient_light.texture_scale = ambient_range / 100.0
	ambient_light.shadow_enabled = false
	add_child(ambient_light)

func _create_cone_texture() -> ImageTexture:
	var size = 128
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = Vector2(size/2, size/2)
	
	for x in range(size):
		for y in range(size):
			var pos = Vector2(x, y)
			var dir_to_center = (pos - center).normalized()
			var distance = pos.distance_to(center)
			
			# Create cone shape pointing upward (negative Y)
			var angle = rad_to_deg(dir_to_center.angle_to(Vector2.UP))
			var cone_half_angle = beam_width / 2.0
			
			var alpha = 0.0
			if abs(angle) <= cone_half_angle:
				# Inside cone
				var distance_factor = 1.0 - (distance / (size/2))
				var angle_factor = 1.0 - (abs(angle) / cone_half_angle)
				alpha = distance_factor * angle_factor
				alpha = clamp(alpha, 0.0, 1.0)
			
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	
	var texture = ImageTexture.new()
	texture.set_image(image)
	return texture

func _drain_battery(delta: float):
	battery_life -= battery_drain_rate * delta
	if battery_life <= 0:
		battery_life = 0
		_on_battery_depleted()

func _handle_low_battery_effects(delta: float):
	if battery_life <= low_battery_threshold and battery_life > 0:
		# Emit warning signal if crossing threshold
		if _last_battery_warning > low_battery_threshold:
			emit_signal("battery_warning", battery_life)
			if low_battery_sound:
				play_audio(low_battery_sound, -5)
		
		# Flicker effect when very low
		if flicker_on_low_battery and battery_life <= flicker_threshold:
			_flicker_timer += delta * 5.0  # Faster flicker when lower
			var flicker_value = sin(_flicker_timer) * flicker_intensity
			var energy_multiplier = 1.0 + flicker_value
			
			beam_light.energy = beam_energy * energy_multiplier * (battery_life / flicker_threshold)
			ambient_light.energy = ambient_energy * energy_multiplier * (battery_life / flicker_threshold)
			_is_flickering = true
		elif _is_flickering:
			# Stop flickering
			_is_flickering = false
			beam_light.energy = beam_energy
			ambient_light.energy = ambient_energy
	
	_last_battery_warning = battery_life

func _on_battery_depleted():
	is_on = false
	emit_signal("battery_depleted")
	
	# Visual feedback for dead battery
	var icon = get_node_or_null("Icon")
	if icon:
		var tween = create_tween()
		tween.tween_property(icon, "modulate", Color(0.6, 0.6, 0.6), 0.2)

func _update_light_state():
	if not beam_light or not ambient_light:
		return
	
	var should_be_on = is_on and battery_life > 0
	
	beam_light.enabled = should_be_on
	ambient_light.enabled = should_be_on
	
	if should_be_on:
		# Apply battery level dimming
		var battery_factor = battery_life / max_battery_life
		var dimming = clamp(battery_factor, 0.2, 1.0)  # Never go completely dark
		
		beam_light.energy = beam_energy * dimming
		ambient_light.energy = ambient_energy * dimming
		
		# Update light direction based on item orientation
		_update_light_direction()
	
	# Update visual appearance
	var icon = get_node_or_null("Icon")
	if icon:
		if should_be_on:
			icon.modulate = Color(1.2, 1.2, 1.0)  # Slightly bright when on
		else:
			var battery_factor = battery_life / max_battery_life
			icon.modulate = Color.WHITE.lerp(Color(0.7, 0.7, 0.7), 1.0 - battery_factor)

func _update_light_direction():
	if not inventory_owner:
		# Flashlight is on ground, point upward
		beam_light.rotation = 0
		return
	
	# Point in direction the user is facing
	var user_direction = Vector2.ZERO
	if "facing_direction" in inventory_owner:
		user_direction = inventory_owner.facing_direction
	elif "velocity" in inventory_owner and inventory_owner.velocity.length() > 10:
		user_direction = inventory_owner.velocity.normalized()
	else:
		user_direction = Vector2.UP  # Default direction
	
	beam_light.rotation = user_direction.angle() + PI/2  # Adjust for texture orientation

func toggle_flashlight():
	if battery_life <= 0:
		# Try to turn on but battery is dead
		if low_battery_sound:
			play_audio(low_battery_sound, -5)
		return false
	
	is_on = !is_on
	
	# Play audio feedback
	if is_on and click_on_sound:
		if use_startup_delay:
			_startup_tween = create_tween()
			_startup_tween.tween_delay(startup_delay)
			_startup_tween.tween_callback(func(): play_audio(click_on_sound, 0))
		else:
			play_audio(click_on_sound, 0)
	elif not is_on and click_off_sound:
		play_audio(click_off_sound, 0)
	
	return true

func use(user):
	if super.use(user):
		return toggle_flashlight()
	return false

func apply_to_user(user):
	super.apply_to_user(user)
	# When equipped, ensure lights follow the user
	_update_light_direction()

func remove_from_user(user):
	super.remove_from_user(user)
	# Reset light direction when unequipped
	_update_light_direction()

func attack(target, user):
	# Flashlight can be used as a weapon but turns off on impact
	var result = super.attack(target, user)
	
	if result and is_on:
		# Chance to turn off when used as weapon
		if randf() < 0.3:  # 30% chance
			is_on = false
			if "visible_message" in user:
				user.visible_message("The flashlight flickers off from the impact!")
	
	return result

func recharge_battery(amount: float):
	battery_life = clamp(battery_life + amount, 0.0, max_battery_life)
	
	# Visual feedback for recharging
	var icon = get_node_or_null("Icon")
	if icon:
		var tween = create_tween()
		tween.tween_property(icon, "modulate", Color(1.5, 1.5, 1.5), 0.1)
		tween.tween_property(icon, "modulate", Color.WHITE, 0.3)

func get_battery_percentage() -> float:
	return (battery_life / max_battery_life) * 100.0

func get_examine_text(examiner = null) -> String:
	var base_text = "A sturdy flashlight. "
	
	var battery_percent = get_battery_percentage()
	if battery_percent > 75:
		base_text += "The battery indicator shows it's fully charged."
	elif battery_percent > 50:
		base_text += "The battery indicator shows it's moderately charged."
	elif battery_percent > 25:
		base_text += "The battery indicator shows it's getting low."
	elif battery_percent > 0:
		base_text += "The battery indicator is flashing red - very low!"
	else:
		base_text += "The battery is completely dead."
	
	if is_on:
		base_text += " It's currently turned on."
	else:
		base_text += " It's currently turned off."
	
	return base_text

func can_be_wielded() -> bool:
	return true

func serialize():
	var data = super.serialize()
	data.merge({
		"is_on": is_on,
		"battery_life": battery_life,
		"max_battery_life": max_battery_life
	})
	return data

func deserialize(data):
	super.deserialize(data)
	if "is_on" in data: is_on = data.is_on
	if "battery_life" in data: battery_life = data.battery_life
	if "max_battery_life" in data: max_battery_life = data.max_battery_life

# Multiplayer synchronization
@rpc("any_peer", "call_local", "reliable")
func sync_flashlight_state(user_network_id: String, new_is_on: bool, new_battery: float):
	var user = find_user_by_network_id(user_network_id)
	if user:
		is_on = new_is_on
		battery_life = new_battery
		_update_light_state()

func _sync_flashlight_state():
	if multiplayer.has_multiplayer_peer() and inventory_owner:
		sync_flashlight_state.rpc(get_user_network_id(inventory_owner), is_on, battery_life)
