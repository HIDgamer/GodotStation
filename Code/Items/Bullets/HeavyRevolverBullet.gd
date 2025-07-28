extends RevolverBullet
class_name HeavyRevolverBullet

func _init():
	super._init()
	item_name = "heavy revolver bullet"
	damage = 35.0
	penetration = ArmorPenetrationTier.TIER_4
	accuracy = AccuracyTier.TIER_3

func on_hit_mob(target, projectile):
	super.on_hit_mob(target, projectile)
	_apply_effects(target, projectile)

func _apply_effects(target, projectile):
	if target.has_method("apply_slow"):
		target.apply_slow(2.0, "SLOW")
	
	if target.has_method("apply_knockback"):
		target.apply_knockback(4, projectile.get_direction() if projectile.has_method("get_direction") else Vector2.RIGHT)
