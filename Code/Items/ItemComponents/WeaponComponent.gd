extends Item
class_name WeaponComponent

# Signal declarations
signal weapon_fired(target_position)
signal mode_changed(new_mode)
signal safety_toggled(is_safe)
signal ammo_changed(current_ammo, max_ammo)
signal weapon_wielded(is_wielded)
signal overheated(is_overheated)
signal reload_started()
signal reload_completed()
signal unload_started()
signal unload_completed()

# Enums
enum FiringMode {SEMI_AUTO, BURST, AUTO, SAFETY}
enum WeaponState {IDLE, FIRING, RELOADING, UNLOADING, OVERHEATED}
enum AnimationState {IDLE_EMPTY, IDLE_LOADED, SINGLE_SHOT, AUTO_FIRE, RELOADING, UNLOADING}

# Visual and animation properties
@export var weapon_name: String = "Basic Weapon"
@export var sprite_scale: Vector2 = Vector2(1.0, 1.0)
@export var two_handed: bool = true
@export var show_in_offhand_when_wielded: bool = true
@export var offhand_indicator_texture: CompressedTexture2D = null

# Ammo and magazine properties
@export var magazine_type: PackedScene = null
@export var default_ammo_type: PackedScene = null
@export var current_magazine: MagazineComponent = null
@export var max_rounds: int = 30
@export var rounds_per_shot: int = 1
@export_range(0, 100) var current_ammo: int = 0
@export var caliber: String = "9mm"

# Firing properties
@export_range(0, 1.0) var fire_delay: float = 0.15
@export_range(0, 1.0) var burst_delay: float = 0.1
@export var burst_amount: int = 3
@export_range(0, 100) var damage: int = 10
@export_range(0, 100) var penetration: int = 5
@export_range(0, 3.0) var accuracy_mult: float = 1.0
@export_range(0, 3.0) var accuracy_mult_unwielded: float = 0.6
@export_range(0, 100) var recoil: int = 4
@export_range(0, 100) var recoil_unwielded: int = 8
@export_range(0, 50) var scatter: int = 4
@export_range(0, 100) var scatter_unwielded: int = 12

# Overheating properties
@export var has_overheating: bool = true
@export_range(0, 100) var heat_per_shot: float = 5.0
@export_range(0, 100) var max_heat: float = 100.0
@export_range(0, 10.0) var cooling_rate: float = 5.0
@export_range(0, 10.0) var overheat_cooldown_multiplier: float = 2.0

# Gun modification properties
@export var attachment_slots: Dictionary = {
	"muzzle": null,
	"barrel": null,
	"underbarrel": null,
	"rail": null,
	"stock": null,
	"magazine": null
}

# Current state tracking
var current_firing_mode: int = FiringMode.SEMI_AUTO
var current_state: int = WeaponState.IDLE
var current_animation_state: int = AnimationState.IDLE_EMPTY
var is_wielded: bool = false
var is_safety_on: bool = false
var current_heat: float = 0.0
var shots_fired: int = 0
var last_fired_time: float = 0.0
var rounds_fired: int = 0

# Animation nodes
var weapon_sprite: AnimatedSprite2D
var muzzle_flash: AnimatedSprite2D
var casing_ejector: AnimatedSprite2D
var heat_particles: GPUParticles2D

# Audio nodes
var fire_sound: AudioStreamPlayer2D
var reload_sound: AudioStreamPlayer2D
var empty_sound: AudioStreamPlayer2D

# Reference to controller/owner
var controller = null
var inventory_system = null
var input_controller = null

# Initialization
func _ready():
	# Setup main weapon sprite
	weapon_sprite = $WeaponSprite
	if weapon_sprite:
		weapon_sprite.scale = sprite_scale
		
	# Setup muzzle flash
	muzzle_flash = $MuzzleFlash
	if muzzle_flash:
		muzzle_flash.visible = false
	
	# Setup casing ejector
	casing_ejector = $CasingEjector
	if casing_ejector:
		casing_ejector.visible = false
	
	# Setup heat particles
	heat_particles = $HeatParticles
	if heat_particles:
		heat_particles.emitting = false
	
	# Setup audio players
	fire_sound = $FireSound
	reload_sound = $ReloadSound
	empty_sound = $EmptySound
	
	# Set initial animation state
	update_animation_state()
	
	# Connect signals for inventory interaction
	connect("is_equipped", Callable(self, "_on_equipped"))
	connect("is_unequipped", Callable(self, "_on_unequipped"))
	connect("dropped", Callable(self, "_on_dropped"))
	
	# Configure as a two-handed item if needed
	if two_handed:
		item_flags |= ItemFlags.WIELDED
	
	# Setup persistent effects for UI integration
	has_persistent_effects = true
	
	# Setup interactive behaviors
	tool_behaviour = "weapon"
	
	# Register with groups for detection
	add_to_group("weapons")

# Process for continuous effects like cooling
func _process(delta):
	# Process cooling
	if current_heat > 0 and current_state != WeaponState.OVERHEATED:
		current_heat = max(0, current_heat - (cooling_rate * delta))
		
		# Update heat particles
		if heat_particles and current_heat > max_heat * 0.5:
			if not heat_particles.emitting:
				heat_particles.emitting = true
			heat_particles.amount = int((current_heat / max_heat) * 20)
		elif heat_particles and heat_particles.emitting:
			heat_particles.emitting = false
			
		emit_signal("effect_update", self)
	
	# Handle overheat cooldown
	if current_state == WeaponState.OVERHEATED:
		current_heat = max(0, current_heat - (cooling_rate * overheat_cooldown_multiplier * delta))
		if current_heat <= 0:
			current_state = WeaponState.IDLE
			update_animation_state()
			emit_signal("overheated", false)
	
	# Update ammo counter if magazine state changed
	if current_magazine and current_magazine.rounds_changed:
		current_magazine.rounds_changed = false
		current_ammo = current_magazine.current_rounds
		emit_signal("ammo_changed", current_ammo, max_rounds)
		update_animation_state()

# Update the animation state based on weapon state
func update_animation_state():
	var new_animation_state
	
	if current_state == WeaponState.RELOADING:
		new_animation_state = AnimationState.RELOADING
	elif current_state == WeaponState.UNLOADING:
		new_animation_state = AnimationState.UNLOADING
	elif current_state == WeaponState.FIRING:
		if current_firing_mode == FiringMode.AUTO:
			new_animation_state = AnimationState.AUTO_FIRE
		else:
			new_animation_state = AnimationState.SINGLE_SHOT
	else:
		# Idle state depends on ammo
		if current_magazine and current_magazine.current_rounds > 0:
			new_animation_state = AnimationState.IDLE_LOADED
		else:
			new_animation_state = AnimationState.IDLE_EMPTY
	
	# Only update if animation state changed
	if new_animation_state != current_animation_state:
		current_animation_state = new_animation_state
		
		# Update the sprite animation
		if weapon_sprite:
			match current_animation_state:
				AnimationState.IDLE_EMPTY:
					weapon_sprite.play("idle_unloaded")
				AnimationState.IDLE_LOADED:
					weapon_sprite.play("idle_loaded")
				AnimationState.SINGLE_SHOT:
					weapon_sprite.play("single_shot")
				AnimationState.AUTO_FIRE:
					weapon_sprite.play("auto_fire")
				AnimationState.RELOADING:
					weapon_sprite.play("reload")
				AnimationState.UNLOADING:
					weapon_sprite.play("unload")
		
		# Notify about effect change for UI
		emit_signal("effect_update", self)

# Method to attempt firing the weapon
func try_fire(target_position = null):
	# Safety checks
	if is_safety_on:
		play_sound(empty_sound)
		return false
		
	if current_state == WeaponState.OVERHEATED:
		play_sound(empty_sound)
		return false
		
	if current_state != WeaponState.IDLE:
		return false
	
	# Ammo check
	if not current_magazine or current_magazine.current_rounds <= 0:
		current_state = WeaponState.IDLE
		play_sound(empty_sound)
		update_animation_state()
		return false
	
	# Fire delay check
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_fired_time < fire_delay:
		return false
	
	# All checks passed - fire the weapon
	return fire(target_position)

# Main firing logic
func fire(target_position = null):
	current_state = WeaponState.FIRING
	
	# Process firing mode
	match current_firing_mode:
		FiringMode.SEMI_AUTO:
			fire_single_shot(target_position)
		FiringMode.BURST:
			fire_burst(target_position)
		FiringMode.AUTO:
			fire_auto(target_position)
		FiringMode.SAFETY:
			return false
	
	last_fired_time = Time.get_ticks_msec() / 1000.0
	update_animation_state()
	
	return true

# Fire a single shot
func fire_single_shot(target_position = null):
	# Consume ammo
	if current_magazine:
		current_magazine.consume_rounds(rounds_per_shot)
		current_ammo = current_magazine.current_rounds
	
	# Play effects
	play_fire_effects()
	
	# Calculate accuracy and scatter
	var accuracy = accuracy_mult if is_wielded else accuracy_mult_unwielded
	var shot_scatter = scatter if is_wielded else scatter_unwielded
	
	# Emit projectile or hitscan
	emit_projectile(target_position, accuracy, shot_scatter)
	
	# Add heat
	add_heat(heat_per_shot)
	
	# Apply recoil to camera
	apply_recoil()
	
	# Set state back to idle after firing
	current_state = WeaponState.IDLE
	
	# Signal firing
	emit_signal("weapon_fired", target_position)
	emit_signal("ammo_changed", current_ammo, max_rounds)

# Fire a burst of shots
func fire_burst(target_position = null):
	# Start the burst, the rest will happen in _process
	shots_fired = 0
	
	# Schedule burst shots
	for i in range(burst_amount):
		if current_magazine and current_magazine.current_rounds > 0:
			# Use a timer to schedule each shot in the burst
			var timer = Timer.new()
			timer.wait_time = i * burst_delay
			timer.one_shot = true
			timer.timeout.connect(func(): _fire_burst_shot(target_position))
			add_child(timer)
			timer.start()

# Helper for individual burst shots
func _fire_burst_shot(target_position):
	# Consume ammo
	if current_magazine:
		current_magazine.consume_rounds(rounds_per_shot)
		current_ammo = current_magazine.current_rounds
	
	# Play effects
	play_fire_effects()
	
	# Calculate accuracy and scatter
	var accuracy = accuracy_mult if is_wielded else accuracy_mult_unwielded
	var shot_scatter = scatter if is_wielded else scatter_unwielded
	
	# Burst fire has increasing scatter
	shot_scatter += shots_fired * 2
	
	# Emit projectile or hitscan
	emit_projectile(target_position, accuracy, shot_scatter)
	
	# Add heat
	add_heat(heat_per_shot)
	
	# Apply recoil to camera
	apply_recoil()
	
	# Count shots
	shots_fired += 1
	
	# If we've fired all shots, return to idle
	if shots_fired >= burst_amount or (current_magazine and current_magazine.current_rounds <= 0):
		current_state = WeaponState.IDLE
		update_animation_state()
	
	# Signal firing
	emit_signal("weapon_fired", target_position)
	emit_signal("ammo_changed", current_ammo, max_rounds)

# Fire in automatic mode
func fire_auto(target_position = null):
	# Similar to single shot but stays in firing state to allow continuous fire
	if current_magazine:
		current_magazine.consume_rounds(rounds_per_shot)
		current_ammo = current_magazine.current_rounds
	
	# Play effects
	play_fire_effects()
	
	# Calculate accuracy and scatter
	var accuracy = accuracy_mult if is_wielded else accuracy_mult_unwielded
	var shot_scatter = scatter if is_wielded else scatter_unwielded
	
	# Auto fire has increasing scatter
	shot_scatter += rounds_fired * 1.5
	rounds_fired += 1
	
	# Reset rounds fired counter if we pause
	var timer = Timer.new()
	timer.wait_time = fire_delay * 3
	timer.one_shot = true
	timer.timeout.connect(func(): rounds_fired = 0)
	add_child(timer)
	timer.start()
	
	# Emit projectile or hitscan
	emit_projectile(target_position, accuracy, shot_scatter)
	
	# Add heat
	add_heat(heat_per_shot)
	
	# Apply recoil to camera
	apply_recoil()
	
	# Set back to idle to allow continuous firing
	current_state = WeaponState.IDLE
	
	# Signal firing
	emit_signal("weapon_fired", target_position)
	emit_signal("ammo_changed", current_ammo, max_rounds)

# Play visual and audio effects for firing
func play_fire_effects():
	# Play fire sound
	play_sound(fire_sound)
	
	# Show muzzle flash
	if muzzle_flash:
		muzzle_flash.visible = true
		muzzle_flash.play("flash")
		await muzzle_flash.animation_finished
		muzzle_flash.visible = false
	
	# Show casing ejection
	if casing_ejector:
		casing_ejector.visible = true
		casing_ejector.play("eject")
		await casing_ejector.animation_finished
		casing_ejector.visible = false

# Add heat to the weapon
func add_heat(amount):
	if has_overheating:
		current_heat += amount
		
		# Check for overheat
		if current_heat >= max_heat:
			current_state = WeaponState.OVERHEATED
			current_heat = max_heat
			play_overheat_effect()
			emit_signal("overheated", true)
			
		# Notify about effect change for UI
		emit_signal("effect_update", self)

# Play overheat effect
func play_overheat_effect():
	if heat_particles:
		heat_particles.amount = 30
		heat_particles.emitting = true
		
		# Create smoke particles that fade out
		var smoke = GPUParticles2D.new()
		smoke.process_material = load("res://Materials/weapon_overheat_smoke.tres")
		smoke.amount = 50
		smoke.one_shot = true
		smoke.explosiveness = 0.8
		smoke.emitting = true
		add_child(smoke)
		
		# Clean up smoke after it's done
		var timer = Timer.new()
		timer.wait_time = 3.0
		timer.one_shot = true
		timer.timeout.connect(func(): smoke.queue_free())
		add_child(timer)
		timer.start()

# Apply recoil effect to camera
func apply_recoil():
	var recoil_amount = recoil if is_wielded else recoil_unwielded
	
	# Find camera to shake
	var camera = get_viewport().get_camera_2d()
	if camera and camera.has_method("add_trauma"):
		camera.add_trauma(recoil_amount / 10.0)
	
	# Apply screen shake through controller if available
	if controller and controller.has_method("apply_screen_shake"):
		controller.apply_screen_shake(recoil_amount / 100.0, 0.2)

# Emit projectile
func emit_projectile(target_position, accuracy, scatter_amount):
	# This is a base version - weapon implementations should override this
	# as needed with specific projectile behavior
	if target_position == null:
		# Get direction based on facing if no target provided
		var facing_dir = Vector2.RIGHT.rotated(global_rotation)
		target_position = global_position + facing_dir * 1000
	
	# Apply scatter
	var angle = global_position.angle_to_point(target_position)
	var scatter_rad = deg_to_rad(randf_range(-scatter_amount, scatter_amount))
	var scattered_angle = angle + scatter_rad
	
	# Apply accuracy
	var distance = global_position.distance_to(target_position)
	var accuracy_modifier = max(0.1, accuracy) # Prevent division by zero
	var accuracy_spread = distance * (1.0 / accuracy_modifier) * 0.01
	var final_target = Vector2(
		target_position.x + randf_range(-accuracy_spread, accuracy_spread),
		target_position.y + randf_range(-accuracy_spread, accuracy_spread)
	)
	
	# Emit signal for projectile creation (to be handled by weapon implementation)
	emit_signal("weapon_fired", final_target)

# Toggle firing mode
func toggle_firing_mode():
	# Cycle through available modes
	match current_firing_mode:
		FiringMode.SEMI_AUTO:
			if burst_amount > 1:
				current_firing_mode = FiringMode.BURST
			elif has_full_auto():
				current_firing_mode = FiringMode.AUTO
			else:
				current_firing_mode = FiringMode.SAFETY
		FiringMode.BURST:
			if has_full_auto():
				current_firing_mode = FiringMode.AUTO
			else:
				current_firing_mode = FiringMode.SAFETY
		FiringMode.AUTO:
			current_firing_mode = FiringMode.SAFETY
		FiringMode.SAFETY:
			current_firing_mode = FiringMode.SEMI_AUTO
	
	emit_signal("mode_changed", current_firing_mode)

# Check if weapon has auto fire capability
func has_full_auto() -> bool:
	# Can be overridden by specific weapons
	return true

# Toggle safety
func toggle_safety():
	is_safety_on = !is_safety_on
	emit_signal("safety_toggled", is_safety_on)

# Start reload process
func start_reload():
	if current_state != WeaponState.IDLE:
		return false
		
	if current_magazine and current_magazine.current_rounds >= current_magazine.max_rounds:
		return false
	
	current_state = WeaponState.RELOADING
	update_animation_state()
	emit_signal("reload_started")
	
	play_sound(reload_sound)
	
	# Wait for reload animation to complete
	if weapon_sprite and weapon_sprite.sprite_frames.has_animation("reload"):
		var reload_time = weapon_sprite.sprite_frames.get_frame_duration("reload", 16)
		await get_tree().create_timer(reload_time).timeout
	else:
		# Default reload time if no animation
		await get_tree().create_timer(1.5).timeout
	
	complete_reload()
	return true

# Complete reload process
func complete_reload():
	if current_state != WeaponState.RELOADING:
		return
	
	current_state = WeaponState.IDLE
	update_animation_state()
	
	emit_signal("reload_completed")
	emit_signal("ammo_changed", current_ammo, max_rounds)
	
	# Reload logic will depend on how we implement magazine handling
	# This will be expanded in the implementation

# Start unload process
func start_unload():
	if current_state != WeaponState.IDLE:
		return false
		
	if not current_magazine:
		return false
	
	current_state = WeaponState.UNLOADING
	update_animation_state()
	emit_signal("unload_started")
	
	if reload_sound:
		play_sound(reload_sound)
	
	# Wait for unload animation to complete
	if weapon_sprite and weapon_sprite.sprite_frames.has_animation("unload"):
		var unload_time = weapon_sprite.sprite_frames.get_frame_duration("unload", 16)
		await get_tree().create_timer(unload_time).timeout
	else:
		# Default unload time if no animation
		await get_tree().create_timer(1.0).timeout
	
	complete_unload()
	return true

# Complete unload process
func complete_unload():
	if current_state != WeaponState.UNLOADING:
		return
	
	# Ejecting magazine will be handled by the implementation
	var ejected_magazine = current_magazine
	current_magazine = null
	current_ammo = 0
	
	current_state = WeaponState.IDLE
	update_animation_state()
	
	emit_signal("unload_completed")
	emit_signal("ammo_changed", current_ammo, max_rounds)
	
	return ejected_magazine

# Toggle weapon wielding
func toggle_wielding(user):
	if is_wielded:
		unwield(user)
	else:
		wield(user)

# Wield the weapon (two-handed)
func wield(user):
	if not user or is_wielded:
		return false
	
	# Only wield if we're in the active hand
	var inventory = get_inventory_system(user)
	if not inventory:
		return false
	
	var active_item = inventory.get_active_item()
	if active_item != self:
		return false
	
	# Set wielded state
	is_wielded = true
	
	# Place offhand indicator if needed
	if show_in_offhand_when_wielded:
		show_offhand_indicator(user)
	
	emit_signal("weapon_wielded", true)
	return true

# Unwield the weapon
func unwield(user):
	if not user or not is_wielded:
		return false
	
	# Remove offhand indicator
	if show_in_offhand_when_wielded:
		remove_offhand_indicator(user)
	
	# Set unwielded state
	is_wielded = false
	
	emit_signal("weapon_wielded", false)
	return true

# Show indicator in offhand when wielded
func show_offhand_indicator(user):
	var inventory = get_inventory_system(user)
	if not inventory:
		return
	
	# Determine which hand we're in
	var active_hand = inventory.active_hand
	var inactive_hand = active_hand == inventory.EquipSlot.LEFT_HAND if inventory.EquipSlot.RIGHT_HAND else inventory.EquipSlot.LEFT_HAND
	
	# Create offhand indicator
	var indicator = Node2D.new()
	indicator.name = "WeaponOffhandIndicator"
	
	# Add visual indicator
	var sprite = Sprite2D.new()
	sprite.texture = offhand_indicator_texture if offhand_indicator_texture else weapon_sprite.sprite_frames.get_frame_texture("idle_loaded", 0)
	sprite.modulate = Color(1, 1, 1, 0.5)
	indicator.add_child(sprite)
	
	# Add to user's inactive hand
	# This depends on how your inventory system handles this
	# Here's a conceptual implementation
	if user.has_method("add_to_hand"):
		user.add_to_hand(indicator, inactive_hand)
	
	# Set flag on indicator to prevent interaction
	if "item_flags" in indicator:
		indicator.item_flags |= ItemFlags.ABSTRACT

# Remove offhand indicator
func remove_offhand_indicator(user):
	var inventory = get_inventory_system(user)
	if not inventory:
		return
	
	# Determine inactive hand
	var active_hand = inventory.active_hand
	var inactive_hand = active_hand == inventory.EquipSlot.LEFT_HAND if inventory.EquipSlot.RIGHT_HAND else inventory.EquipSlot.LEFT_HAND
	
	# Find and remove indicator
	var inactive_item = inventory.get_item_in_slot(inactive_hand)
	if inactive_item and inactive_item.name == "WeaponOffhandIndicator":
		inventory.unequip_item(inactive_hand)
		inactive_item.queue_free()

# Inventory integration helper
func get_inventory_system(user):
	if inventory_system:
		return inventory_system
	
	if "inventory_system" in user:
		inventory_system = user.inventory_system
		return inventory_system
		
	if user.has_node("InventorySystem"):
		inventory_system = user.get_node("InventorySystem")
		return inventory_system
	
	return null

# Play sound helper
func play_sound(sound_player):
	if sound_player and sound_player is AudioStreamPlayer2D:
		sound_player.play()

# Signal callbacks
func _on_equipped(user, slot):
	# Connect to controller
	controller = user
	
	# Find inventory system 
	inventory_system = get_inventory_system(user)
	
	# Find input controller
	if user.has_node("InputController"):
		input_controller = user.get_node("InputController")
		
		# Connect to input events if available
		if input_controller:
			if input_controller.has_signal("reload_weapon_requested") and not input_controller.is_connected("reload_weapon_requested", Callable(self, "start_reload")):
				input_controller.connect("reload_weapon_requested", Callable(self, "start_reload"))

func _on_unequipped(user, slot):
	# Unwield if wielded
	if is_wielded:
		unwield(user)
	
	# Disconnect from controller
	controller = null
	
	# Disconnect from input controller
	if input_controller:
		if input_controller.has_signal("reload_weapon_requested") and input_controller.is_connected("reload_weapon_requested", Callable(self, "start_reload")):
			input_controller.disconnect("reload_weapon_requested", Callable(self, "start_reload"))
		
		input_controller = null

func _on_dropped(user):
	# Unwield if wielded
	if is_wielded:
		unwield(user)
	
	# Reset state
	current_state = WeaponState.IDLE
	update_animation_state()

# Use action (for wielding toggle)
func use(user):
	if two_handed:
		toggle_wielding(user)
	return true

# Implementation of attack function for firing
func attack(target, user):
	if not is_wielded and two_handed:
		# Can still fire, but with reduced accuracy
		pass
	
	# Get target position from click
	var target_position = target.global_position if target else null
	
	# Attempt to fire
	return try_fire(target_position)

# Setup effect proxy for UI integration
func setup_effect_proxy(proxy, slot):
	# For weapons to display properly in the UI
	# Copy sprite frames to the proxy
	var proxy_sprite = AnimatedSprite2D.new()
	proxy_sprite.sprite_frames = weapon_sprite.sprite_frames
	proxy_sprite.play(weapon_sprite.animation)
	proxy_sprite.frame = weapon_sprite.frame
	
	# Add to proxy
	proxy.add_child(proxy_sprite)
	
	# Also sync heat particles if visible
	if heat_particles and heat_particles.emitting:
		var particles = GPUParticles2D.new()
		particles.process_material = heat_particles.process_material
		particles.texture = heat_particles.texture
		particles.amount = heat_particles.amount
		particles.emitting = true
		proxy.add_child(particles)

# Update effect proxy
func update_effect_proxy(proxy, slot):
	# Find the proxy sprite
	var proxy_sprite = proxy.get_node_or_null("AnimatedSprite2D")
	if proxy_sprite and weapon_sprite:
		# Sync animation
		if proxy_sprite.animation != weapon_sprite.animation:
			proxy_sprite.play(weapon_sprite.animation)
		proxy_sprite.frame = weapon_sprite.frame
	
	# Update particles
	var proxy_particles = proxy.get_node_or_null("GPUParticles2D")
	if proxy_particles and heat_particles:
		proxy_particles.emitting = heat_particles.emitting
		proxy_particles.amount = heat_particles.amount
