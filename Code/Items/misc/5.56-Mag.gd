extends MagazineComponent
class_name AR15MagazineComponent

func _ready():
	super._ready()
	
	# Magazine properties
	magazine_name = "STANAG 5.56mm Magazine"
	description = "A standard 30-round magazine for 5.56mm rifles."
	item_name = magazine_name
	max_rounds = 40
	current_rounds = 40
	caliber = "5.56mm"
	
	# Set visuals
	var sprite = get_node_or_null("Sprite2D")
	if sprite:
		if magazine_sprite:
			sprite.texture = magazine_sprite
			
	# Set compatible weapons
	compatible_weapons = ["AR15WeaponComponent"]
	
	# Set ammo type reference
	var ammo_scene_path = "res://Scenes/Items/Bullets_Magazines/5.56.tscn"
	if ResourceLoader.exists(ammo_scene_path):
		ammo_type = load(ammo_scene_path)
	
	# Set item properties
	equip_slot_flags = Slots.BELT | Slots.POCKET | Slots.BACKPACK
	w_class = 2  # Medium size
	pickupable = true
	
	# Add to magazines group
	add_to_group("magazines")
	
	# Update appearance based on loaded status
	update_appearance()

# Override to customize appearance
func update_appearance():
	var sprite = get_node_or_null("Sprite2D")
	if sprite:
		if current_rounds <= 0 and empty_sprite:
			sprite.texture = empty_sprite
		elif current_rounds > 0 and loaded_sprite:
			sprite.texture = loaded_sprite
		elif magazine_sprite:
			sprite.texture = magazine_sprite
			
	# Update modulation color based on ammo amount
	if sprite:
		if current_rounds == 0:
			sprite.modulate = Color(0.7, 0.7, 0.7)  # Gray for empty
		elif current_rounds < max_rounds * 0.25:
			sprite.modulate = Color(1.0, 0.5, 0.5)  # Red tint for low ammo
		else:
			sprite.modulate = Color(1.0, 1.0, 1.0)  # Normal color

# Create a loaded magazine
static func create_loaded(magazine_scene: PackedScene, amount: int = -1) -> AR15MagazineComponent:
	magazine_scene = load("res://Scenes/Items/Bullets_Magazines/5.56-Mag.tscn")
	var magazine = magazine_scene.instantiate()
	
	if amount < 0:
		magazine.current_rounds = magazine.max_rounds
	else:
		magazine.current_rounds = min(amount, magazine.max_rounds)
	
	magazine.update_appearance()
	return magazine

# Examine function with ammo count
func examine(user):
	return "[b][color=#d6c57e]" + item_name + "[/color][/b]\n" + \
		   description + "\n" + \
		   "Caliber: " + caliber + "\n" + \
		   "Rounds: [" + str(current_rounds) + "/" + str(max_rounds) + "]"
