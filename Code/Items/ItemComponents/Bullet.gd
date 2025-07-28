extends Item
class_name Bullet

signal stack_changed(new_count: int)
signal stack_depleted()

# Bullet Properties
@export var damage: float = 0.0
@export var penetration: int = 0
@export var accuracy: float = 0.0
@export var shell_speed: float = 1.0
@export var accurate_range: int = 0
@export var effective_range_max: int = 0
@export var max_range: int = 24
@export var damage_falloff: float = 0.0
@export var scatter: float = 0.0
@export var shrapnel_chance: float = 0.0
@export var headshot_state: String = ""
@export var damage_type: String = "BRUTE"
@export var stamina_damage: float = 0.0

# Stacking Properties
@export var max_stack_size: int = 1
@export var current_stack_count: int = 1
@export var bullet_type: String = "standard"

# Visual Properties
@export var handful_state: String = ""
@export var multiple_handful_name: bool = false
@export var icon_state_override: String = ""

# Bullet Behavior Flags
enum BulletFlags {
	BALLISTIC = 1,
	ENERGY = 2,
	EXPLOSIVE = 4,
	SNIPER = 8,
	IGNORE_COVER = 16,
	IGNORE_ARMOR = 32,
	IGNORE_RESIST = 64,
	ANTIVEHICLE = 128
}

@export var bullet_flags: int = BulletFlags.BALLISTIC

# Damage Tiers
enum ArmorPenetrationTier {
	TIER_1 = 10,
	TIER_2 = 20,
	TIER_3 = 30,
	TIER_4 = 40,
	TIER_5 = 50,
	TIER_6 = 60,
	TIER_7 = 70,
	TIER_8 = 80,
	TIER_9 = 90,
	TIER_10 = 100
}

enum AccuracyTier {
	TIER_1 = 100,
	TIER_2 = 90,
	TIER_3 = 80,
	TIER_4 = 70,
	TIER_5 = 60,
	TIER_6 = 50,
	TIER_7 = 40,
	TIER_8 = 30
}

enum SpeedTier {
	TIER_1 = 1,
	TIER_2 = 2,
	TIER_3 = 3,
	TIER_4 = 4,
	TIER_5 = 5,
	TIER_6 = 6
}

# Components for special effects
var debilitate_effects: Array = []
var bonus_projectiles_amount: int = 0
var bonus_projectiles_type: String = ""

func _init():
	super._init()
	item_name = "bullet"
	w_class = 1
	
	# Set default stack sizes by bullet type
	_set_default_stack_size()

func _ready():
	super._ready()
	_setup_animated_sprite()
	_update_stack_display()
	
	# Connect stack change signal
	stack_changed.connect(_on_stack_changed)

func _set_default_stack_size():
	# Set default stack sizes based on bullet type
	match bullet_type:
		"pistol", "revolver":
			max_stack_size = 15
		"rifle", "sniper", "smg":
			max_stack_size = 30
		"shotgun":
			max_stack_size = 7
		"special", "smartgun":
			max_stack_size = 10
		_:
			max_stack_size = 1

func _setup_animated_sprite():
	# Replace regular sprite with AnimatedSprite2D if not already present
	var icon_node = get_node_or_null("Icon")
	if icon_node and not icon_node is AnimatedSprite2D:
		var animated_sprite = AnimatedSprite2D.new()
		animated_sprite.name = "Icon"
		
		# Copy properties from old sprite if it was a Sprite2D
		if icon_node is Sprite2D:
			animated_sprite.position = icon_node.position
			animated_sprite.scale = icon_node.scale
			animated_sprite.rotation = icon_node.rotation
			animated_sprite.modulate = icon_node.modulate
		
		# Remove old sprite and add animated sprite
		remove_child(icon_node)
		icon_node.queue_free()
		add_child(animated_sprite)
		
		# Create default animation frames
		_create_stack_animations(animated_sprite)

func _create_stack_animations(animated_sprite: AnimatedSprite2D):
	var sprite_frames = SpriteFrames.new()
	
	# Create animation for different stack states
	var stack_states = ["full", "high", "medium", "low", "empty"]
	
	for state in stack_states:
		sprite_frames.add_animation(state)
		sprite_frames.set_animation_loop(state, false)
		sprite_frames.set_animation_speed(state, 1.0)
		
		# You would load actual textures here
		# For now, creating placeholder colored rectangles
		var placeholder_texture = _create_placeholder_texture(state)
		sprite_frames.add_frame(state, placeholder_texture)
	
	animated_sprite.sprite_frames = sprite_frames
	animated_sprite.animation = "full"

func _create_placeholder_texture(state: String) -> ImageTexture:
	var image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var color = Color.WHITE
	
	match state:
		"full": color = Color.GOLD
		"high": color = Color.YELLOW
		"medium": color = Color.ORANGE
		"low": color = Color.RED
		"empty": color = Color.GRAY
	
	image.fill(color)
	var texture = ImageTexture.new()
	texture.set_image(image)
	return texture

func _update_stack_display():
	var animated_sprite = get_node_or_null("Icon") as AnimatedSprite2D
	if not animated_sprite or not animated_sprite.sprite_frames:
		return
	
	# Calculate which animation to show based on stack percentage
	var stack_percentage = float(current_stack_count) / float(max_stack_size)
	
	var animation_name = "empty"
	if stack_percentage > 0.8:
		animation_name = "full"
	elif stack_percentage > 0.6:
		animation_name = "high"
	elif stack_percentage > 0.4:
		animation_name = "medium"
	elif stack_percentage > 0.2:
		animation_name = "low"
	
	animated_sprite.animation = animation_name
	
	# Update item name to show count
	if current_stack_count > 1:
		if multiple_handful_name:
			item_name = name + " (" + str(current_stack_count) + ")"
		else:
			item_name = name + " x" + str(current_stack_count)
	else:
		item_name = name

func add_to_stack(amount: int) -> int:
	var space_available = max_stack_size - current_stack_count
	var amount_to_add = min(amount, space_available)
	
	current_stack_count += amount_to_add
	_update_stack_display()
	emit_signal("stack_changed", current_stack_count)
	
	return amount - amount_to_add  # Return overflow

func remove_from_stack(amount: int) -> int:
	var amount_to_remove = min(amount, current_stack_count)
	current_stack_count -= amount_to_remove
	
	_update_stack_display()
	emit_signal("stack_changed", current_stack_count)
	
	if current_stack_count <= 0:
		emit_signal("stack_depleted")
		_handle_stack_depletion()
	
	return amount_to_remove

func _handle_stack_depletion():
	# Mark as depleted and remove from inventory
	deplete_item()

func can_stack_with(other_bullet: Bullet) -> bool:
	if not other_bullet:
		return false
	
	# Check if same bullet type and has space
	return (get_script() == other_bullet.get_script() and 
			current_stack_count < max_stack_size)

func try_stack_with(other_bullet: Bullet) -> bool:
	if not can_stack_with(other_bullet):
		return false
	
	var overflow = add_to_stack(other_bullet.current_stack_count)
	
	if overflow <= 0:
		# All bullets were absorbed
		other_bullet.destroy_item()
		return true
	else:
		# Some bullets remain in other stack
		other_bullet.current_stack_count = overflow
		other_bullet._update_stack_display()
		return false

func _on_stack_changed(new_count: int):
	# Override in subclasses for special behavior
	pass

func get_single_bullet() -> Bullet:
	"""Create a single bullet instance for firing"""
	var single_bullet = duplicate()
	single_bullet.current_stack_count = 1
	single_bullet.max_stack_size = 1
	single_bullet._update_stack_display()
	
	# Remove one from this stack
	remove_from_stack(1)
	
	return single_bullet

# Bullet effect methods (override in subclasses)
func on_hit_mob(target, projectile):
	# Base hit behavior
	if target.has_method("take_damage"):
		target.take_damage(damage, damage_type.to_lower(), "ballistic", true, penetration)

func on_hit_obj(target, projectile):
	# Base object hit behavior
	if target.has_method("take_damage"):
		target.take_damage(damage * 0.5, damage_type.to_lower(), "ballistic", true, penetration)

func on_hit_turf(target, projectile):
	# Base terrain hit behavior
	pass

func on_near_target(target_turf, projectile) -> bool:
	# For proximity effects (like flak rounds)
	return false

# Special effect methods
func apply_debilitate_effects(target):
	# Apply status effects based on debilitate_effects array
	for i in range(debilitate_effects.size()):
		var effect_duration = debilitate_effects[i]
		if effect_duration > 0:
			_apply_specific_debilitate(target, i, effect_duration)

func _apply_specific_debilitate(target, effect_type: int, duration: float):
	# Map effect types to actual status effects
	# This would need to be implemented based on your status effect system
	match effect_type:
		0: # Stun
			if target.has_method("apply_stun"):
				target.apply_stun(duration)
		1: # Knockdown
			if target.has_method("apply_knockdown"):
				target.apply_knockdown(duration)
		2: # Pain
			if target.has_method("apply_pain"):
				target.apply_pain(duration)
		# Add more effect types as needed

# Utility methods
func has_bullet_flag(flag: BulletFlags) -> bool:
	return (bullet_flags & flag) != 0

func set_bullet_flag(flag: BulletFlags, enabled: bool = true):
	if enabled:
		bullet_flags |= flag
	else:
		bullet_flags &= ~flag

func get_display_name() -> String:
	if current_stack_count > 1:
		return item_name + " (" + str(current_stack_count) + ")"
	return item_name

# Serialization
func serialize() -> Dictionary:
	var data = super.serialize()
	data.merge({
		"damage": damage,
		"penetration": penetration,
		"accuracy": accuracy,
		"shell_speed": shell_speed,
		"accurate_range": accurate_range,
		"effective_range_max": effective_range_max,
		"max_range": max_range,
		"damage_falloff": damage_falloff,
		"scatter": scatter,
		"shrapnel_chance": shrapnel_chance,
		"headshot_state": headshot_state,
		"damage_type": damage_type,
		"stamina_damage": stamina_damage,
		"max_stack_size": max_stack_size,
		"current_stack_count": current_stack_count,
		"bullet_type": bullet_type,
		"bullet_flags": bullet_flags,
		"debilitate_effects": debilitate_effects
	})
	return data

func deserialize(data: Dictionary):
	super.deserialize(data)
	if "damage" in data: damage = data.damage
	if "penetration" in data: penetration = data.penetration
	if "accuracy" in data: accuracy = data.accuracy
	if "shell_speed" in data: shell_speed = data.shell_speed
	if "accurate_range" in data: accurate_range = data.accurate_range
	if "effective_range_max" in data: effective_range_max = data.effective_range_max
	if "max_range" in data: max_range = data.max_range
	if "damage_falloff" in data: damage_falloff = data.damage_falloff
	if "scatter" in data: scatter = data.scatter
	if "shrapnel_chance" in data: shrapnel_chance = data.shrapnel_chance
	if "headshot_state" in data: headshot_state = data.headshot_state
	if "damage_type" in data: damage_type = data.damage_type
	if "stamina_damage" in data: stamina_damage = data.stamina_damage
	if "max_stack_size" in data: max_stack_size = data.max_stack_size
	if "current_stack_count" in data: current_stack_count = data.current_stack_count
	if "bullet_type" in data: bullet_type = data.bullet_type
	if "bullet_flags" in data: bullet_flags = data.bullet_flags
	if "debilitate_effects" in data: debilitate_effects = data.debilitate_effects
	
	_update_stack_display()
