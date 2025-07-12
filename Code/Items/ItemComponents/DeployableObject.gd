extends BaseObject
class_name DeployableObject

# The item this was deployed from
var deployed_item = null
# The entity that deployed this
var deployer = null
# Whether this can be undeployed
var can_undeploy: bool = true
# Time it takes to undeploy this object
var undeploy_time: float = 2.0

signal undeployed(user)

func _init():
	super._init()
	# Set default values
	anchored = true

func _ready():
	super._ready()
	add_to_group("deployable_objects")
	
# Initialize from a deployable item
func init_from_item(item, user = null):
	if item:
		deployed_item = item
		obj_name = item.obj_name
		obj_desc = "A deployed " + item.obj_name
		max_integrity = item.max_integrity
		obj_integrity = item.obj_integrity
		deployer = user
		
		# Copy resistances and other relevant properties
		resistance_flags = item.resistance_flags
		
		# Setup appearance based on the item
		update_appearance()
		
	return self

# Get the deployed item
func get_internal_item():
	return deployed_item

# Clear internal item reference
func clear_internal_item():
	deployed_item = null

# Interact with the deployable object
func interact(user):
	super.interact(user)
	
	# If the deployer interacts with it, show additional options
	if user == deployer:
		# This would typically show options in a UI
		# For simplicity, just check if they can undeploy
		if can_undeploy and deployed_item:
			# Show undeploy option
			if user.has_method("display_message"):
				user.display_message("You can disassemble the [obj_name].")
	
	return true

# Start the undeployment process
func start_undeploy(user):
	if !can_undeploy or !deployed_item:
		return false
	
	if user.has_method("display_message"):
		user.display_message("You begin disassembling [obj_name]...")
	
	# Wait for the undeploy time
	# In a real implementation, you'd use a timer or signal here
	await get_tree().create_timer(undeploy_time).timeout
	
	# Complete undeployment
	undeploy(user)
	return true

# Finish the undeployment process
func undeploy(user):
	if !deployed_item:
		return false
	
	# Signal undeployment
	emit_signal("undeployed", user)
	
	if user.has_method("display_message"):
		user.display_message("You disassemble [obj_name].")
	
	# Handle putting the item in the user's hands or on the ground
	if user.has_method("put_in_hands"):
		user.put_in_hands(deployed_item)
	else:
		deployed_item.global_position = global_position
		deployed_item.visible = true
	
	# Reset the deployed item's state
	deployed_item.set_flag("item_flags", deployed_item.ItemFlags.IS_DEPLOYED, false)
	
	# Remove the deployable object
	queue_free()
	return true

# Handle destruction
func obj_destruction(damage_amount, damage_type, damage_flag, attacker = null):
	if deployed_item:
		# Damage the item if the deployable is destroyed
		deployed_item.take_damage(damage_amount, damage_type, damage_flag, true, null, 0, attacker)
		
		# Reset the deployed item's state
		deployed_item.set_flag("item_flags", deployed_item.ItemFlags.IS_DEPLOYED, false)
		deployed_item.visible = true
		
		# Drop the item at this location
		deployed_item.global_position = global_position
	
	# Call parent destruction method
	super.obj_destruction(damage_amount, damage_type, damage_flag, attacker)

# Custom interaction methods
func alt_interact(user):
	if can_undeploy and deployed_item:
		start_undeploy(user)
		return true
	
	return false

# Optional: Add special tool interactions
func wrench_act(user, item):
	if can_undeploy and deployed_item:
		start_undeploy(user)
		return true
	
	return false

# Called before undeployment is completed
func post_disassemble(user):
	# For subclasses to override
	pass
