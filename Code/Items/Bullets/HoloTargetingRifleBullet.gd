extends RifleBullet
class_name HoloTargetingRifleBullet

@export var holo_stacks: int = 10
@export var bonus_damage_cap_increase: int = 0
@export var stack_loss_multiplier: float = 1.0

func _init():
	super._init()
	item_name = "holo-targeting rifle bullet"
	damage = 30.0

func on_hit_mob(target, projectile):
	super.on_hit_mob(target, projectile)
	
	# Apply holo stacks (would need HoloTargeting component implementation)
	if target.has_method("add_holo_stacks"):
		target.add_holo_stacks(holo_stacks, bonus_damage_cap_increase, stack_loss_multiplier)
