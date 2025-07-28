extends BuckshotShell
class_name MasterkeyBuckshot

func _init():
	super._init()
	bonus_projectiles_type = "MasterkeySpread"
	damage = 55.0

func _apply_knockback(target, projectile):
	if target.has_method("apply_knockback"):
		target.apply_knockback(1, projectile.get_direction() if projectile.has_method("get_direction") else Vector2.RIGHT)
