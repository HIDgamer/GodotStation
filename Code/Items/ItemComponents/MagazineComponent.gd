extends Item
class_name MagazineComponent

# Signals
signal rounds_updated(current, max)

# Magazine properties
@export var magazine_name: String = "Standard Magazine"
@export var max_rounds: int = 30
@export var current_rounds: int = 0
@export var caliber: String = "9mm"
@export var ammo_type: PackedScene = null
@export var compatible_weapons: Array = []

# Visual properties
@export var magazine_sprite: Texture2D = null
@export var loaded_sprite: Texture2D = null
@export var empty_sprite: Texture2D = null

# State tracking
var rounds_changed: bool = false

# Initialize magazine
func _ready():
	# Set item class properties
	item_name = magazine_name
	
	# Configure as pickupable
	pickupable = true
	
	# Set initial sprite based on ammo count
	update_appearance()
	
	# Add to magazines group
	add_to_group("magazines")

# Update appearance based on ammo state
func update_appearance():
	var sprite = get_node_or_null("Icon")
	if sprite:
		if current_rounds <= 0 and empty_sprite:
			sprite.texture = empty_sprite
		elif current_rounds > 0 and loaded_sprite:
			sprite.texture = loaded_sprite
		elif magazine_sprite:
			sprite.texture = magazine_sprite

# Load rounds into the magazine
func load_rounds(amount: int) -> int:
	var space_left = max_rounds - current_rounds
	var rounds_to_add = min(amount, space_left)
	
	if rounds_to_add > 0:
		current_rounds += rounds_to_add
		rounds_changed = true
		emit_signal("rounds_updated", current_rounds, max_rounds)
		update_appearance()
	
	return rounds_to_add

# Consume rounds from the magazine
func consume_rounds(amount: int) -> int:
	var rounds_to_consume = min(amount, current_rounds)
	
	if rounds_to_consume > 0:
		current_rounds -= rounds_to_consume
		rounds_changed = true
		emit_signal("rounds_updated", current_rounds, max_rounds)
		update_appearance()
	
	return rounds_to_consume

# Check if magazine is compatible with a weapon
func is_compatible_with(weapon) -> bool:
	if not weapon:
		return false
	
	# Check by class name
	var weapon_class = weapon.get_class()
	if compatible_weapons.has(weapon_class):
		return true
	
	# Check by caliber
	if "caliber" in weapon and weapon.caliber == caliber:
		return true
	
	return false

# Create a loaded magazine
static func create_loaded(magazine_scene: PackedScene, amount: int = -1) -> MagazineComponent:
	var magazine = magazine_scene.instantiate()
	
	if amount < 0:
		magazine.current_rounds = magazine.max_rounds
	else:
		magazine.current_rounds = min(amount, magazine.max_rounds)
	
	magazine.update_appearance()
	return magazine

# Handle use action (for loading into weapon)
func use(user):
	# Find active weapon
	var inventory = null
	
	if "inventory_system" in user:
		inventory = user.inventory_system
	elif user.has_node("InventorySystem"):
		inventory = user.get_node("InventorySystem")
	
	if inventory:
		var active_item = inventory.get_active_item()
		
		# If holding a weapon, try to load this magazine into it
		if active_item and active_item is WeaponComponent:
			return await load_into_weapon(active_item, user)
	
	# Default behavior
	return super.use(user)

# Load this magazine into a weapon
func load_into_weapon(weapon, user) -> bool:
	if not is_compatible_with(weapon):
		# Not compatible
		if user:
			user.balloon_alert(user, "Incompatible magazine")
		return false
	
	# Check if weapon is already being reloaded
	if weapon.current_state == weapon.WeaponState.RELOADING:
		return false
	
	# Check if weapon already has full magazine
	if weapon.current_magazine and weapon.current_magazine.current_rounds >= weapon.current_magazine.max_rounds:
		if user:
			user.balloon_alert(user, "Magazine already full")
		return false
	
	# Unload current magazine if any
	var old_magazine = null
	if weapon.current_magazine:
		weapon.start_unload()
		old_magazine = await weapon.complete_unload()
		
		# Give old magazine to user
		if old_magazine and user and "inventory_system" in user:
			user.inventory_system.put_in_hands(old_magazine)
	
	# Remove from inventory
	if inventory_owner and "inventory_system" in inventory_owner:
		inventory_owner.inventory_system.remove_item(self)
	
	# Load into weapon
	weapon.current_magazine = self
	weapon.current_ammo = current_rounds
	
	# Start reload animation
	weapon.start_reload()
	
	return true

# Examine information
func examine(user):
	return "[b][color=#d6c57e]" + item_name + "[/color][/b]\n" + \
		   description + "\n" + \
		   "Caliber: " + caliber + "\n" + \
		   "Rounds: [" + str(current_rounds) + "/" + str(max_rounds) + "]"
