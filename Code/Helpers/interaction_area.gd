extends Area2D
class_name ItemClickableArea

# Reference to the parent item
var parent_item = null

func _ready():
	# Get the parent item (which should be the Item node)
	parent_item = get_parent()
	
	# Ensure this Area2D is in the "clickable_items" group for easy detection
	add_to_group("clickable_items")
	
	# Make sure this Area2D has a collision shape
	if get_child_count() == 0 or not (get_child(0) is CollisionShape2D or get_child(0) is CollisionPolygon2D):
		printerr("Warning: ItemClickableArea on " + str(parent_item.name) + " has no collision shape!")
