extends BulletComponent
class_name Bullet556Component

func _ready():
	super._ready()
	
	# Basic properties
	bullet_name = "5.56mm Rifle Round"
	description = "A standard 5.56×45mm NATO rifle cartridge."
	item_name = bullet_name
	caliber = "5.56mm"
	
	# Damage properties - higher damage and penetration than 9mm
	damage = 25
	penetration = 15
	
	# Set sprite if available
	var sprite = get_node_or_null("Sprite2D")
	if sprite and bullet_sprite:
		sprite.texture = bullet_sprite
	
	# Item properties
	w_class = 1  # Small size
	equip_slot_flags = Slots.POCKET | Slots.BACKPACK | Slots.BELT
	pickupable = true
	
	# Add to ammo group
	add_to_group("ammo")

# Static method to create a box of ammo
static func create_ammo_box(amount: int = 30) -> Node:
	var box = load("res://Items/AmmoBox/AmmoBox.tscn").instantiate()
	box.item_name = "Box of 5.56mm Rounds"
	box.description = "A box containing " + str(amount) + " rounds of 5.56mm ammunition."
	
	# Set ammo properties
	box.ammo_type = load("res://Scenes/Items/Bullets_Magazines/5.56.tscn")
	box.ammo_count = amount
	box.max_ammo = 30
	
	return box

# Enhanced examine function
func examine(user):
	return "[b][color=#d6c57e]" + item_name + "[/color][/b]\n" + \
		   description + "\n" + \
		   "Caliber: " + caliber + "\n" + \
		   "Damage: " + str(damage) + "\n" + \
		   "Penetration: " + str(penetration)
