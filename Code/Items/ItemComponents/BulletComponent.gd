extends Item
class_name BulletComponent

# Bullet properties
@export var bullet_name: String = "Standard Bullet"
@export var caliber: String = "9mm"
@export var damage: int = 10
@export var penetration: int = 0
@export var bullet_sprite: Texture2D = null

# Initialize
func _ready():
	# Set item properties
	item_name = bullet_name
	pickupable = true
	
	# Set sprite
	var sprite = get_node_or_null("Icon")
	if sprite and bullet_sprite:
		sprite.texture = bullet_sprite
	
	# Add to ammo group
	add_to_group("ammo")

# Load into a magazine
func load_into_magazine(magazine, user) -> bool:
	if not magazine or not magazine is MagazineComponent:
		return false
	
	# Check compatibility
	if magazine.caliber != caliber:
		if user:
			user.balloon_alert(user, "Incompatible caliber")
		return false
	
	# Check if magazine is full
	if magazine.current_rounds >= magazine.max_rounds:
		if user:
			user.balloon_alert(user, "Magazine full")
		return false
	
	# Load into magazine
	magazine.load_rounds(1)
	
	# Remove this bullet from inventory
	if inventory_owner and "inventory_system" in inventory_owner:
		inventory_owner.inventory_system.remove_item(self)
	
	# Queue for deletion
	queue_free()
	
	return true

# Handle use action (for loading into magazine)
func use(user):
	# Find active magazine
	var inventory = null
	
	if "inventory_system" in user:
		inventory = user.inventory_system
	elif user.has_node("InventorySystem"):
		inventory = user.get_node("InventorySystem")
	
	if inventory:
		var active_item = inventory.get_active_item()
		
		# If holding a magazine, try to load this bullet into it
		if active_item and active_item is MagazineComponent:
			return load_into_magazine(active_item, user)
	
	# Default behavior
	return super.use(user)

# Create multiple bullets
static func create_handful(bullet_scene: PackedScene, amount: int) -> Array:
	var bullets = []
	
	for i in range(amount):
		var bullet = bullet_scene.instantiate()
		bullets.append(bullet)
	
	return bullets

# Examine information
func examine(user):
	return "[b][color=#d6c57e]" + item_name + "[/color][/b]\n" + \
		   description + "\n" + \
		   "Caliber: " + caliber
