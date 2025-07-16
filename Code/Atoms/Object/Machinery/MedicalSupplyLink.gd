extends BaseObject
class_name MedicalSupplyLink

@export var is_green_variant: bool = false

# Visual properties
var base_state: String = "medlink"
var icon_state_unclamped: String = "medlink_unclamped"
var icon_state_clamped: String = "medlink_clamped"

# Signals
signal structure_wrenched()
signal structure_unwrenched()

func _ready():
	# Setup basic properties
	obj_name = "medilink supply port"
	obj_desc = "A complex network of pipes and machinery, linking to large storage systems below the deck. Medical vendors linked to this port will be able to infinitely restock supplies."
	
	# Set physical properties
	anchored = true
	
	# Set visual properties
	if is_green_variant:
		base_state = "medlink_green"
		icon_state_unclamped = "medlink_green_unclamped" 
		icon_state_clamped = "medlink_green_clamped"
	else:
		base_state = "medlink"
		icon_state_unclamped = "medlink_unclamped"
		icon_state_clamped = "medlink_clamped"
	
	# Add to group
	add_to_group("medical_supply_links")
	
	# Set initial visual state
	update_visual_state()

func update_visual_state():
	# Check if there's a vendor above us
	var vendor = find_vendor_above()
	var sprite = get_node_or_null("Sprite2D")
	
	if sprite:
		if vendor and vendor.anchored:
			sprite.texture = load("res://textures/objects/medical/" + icon_state_clamped + ".png")
		else:
			sprite.texture = load("res://textures/objects/medical/" + icon_state_unclamped + ".png")

func find_vendor_above() -> MedicalVendor:
	# Get all objects at our position
	var objects = []
	var world = get_node_or_null("/root/World")
	
	if world and world.has_method("get_objects_at"):
		objects = world.get_objects_at(global_position)
	else:
		# Fallback to getting siblings
		for node in get_parent().get_children():
			if node.global_position.distance_to(global_position) < 5 and node != self:
				objects.append(node)
	
	# Find the vendor
	for object in objects:
		if object is MedicalVendor:
			return object
	
	return null

func do_clamp_animation():
	# Play clamping animation
	var sprite = get_node_or_null("Sprite2D")
	if sprite:
		# First set to clamping animation
		var clamping_texture = load("res://textures/objects/medical/" + base_state + "_clamping.png")
		if clamping_texture:
			sprite.texture = clamping_texture
		
		# Schedule update after animation
		await get_tree().create_timer(2.6).timeout
		update_visual_state()
	
	# Emit signal
	emit_signal("structure_wrenched")

func do_unclamp_animation():
	# Play unclamping animation
	var sprite = get_node_or_null("Sprite2D")
	if sprite:
		# First set to unclamping animation
		var unclamping_texture = load("res://textures/objects/medical/" + base_state + "_unclamping.png")
		if unclamping_texture:
			sprite.texture = unclamping_texture
		
		# Schedule update after animation
		await get_tree().create_timer(2.6).timeout
		update_visual_state()
	
	# Emit signal
	emit_signal("structure_unwrenched")

func interact(user) -> bool:
	# Base interaction
	super.interact(user)
	
	# Simply examine
	if user and user.has_method("display_message"):
		user.display_message("This is a " + obj_name + ". " + obj_desc)
	
	return true
