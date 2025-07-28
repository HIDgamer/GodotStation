extends SMGBullet
class_name IncendiarySMGBullet

func _init():
	super._init()
	item_name = "incendiary submachinegun bullet"
	damage_type = "BURN"
	shrapnel_chance = 0.0
	
	damage = 25.0
	accuracy = AccuracyTier.TIER_2 - 20  # -HIT_ACCURACY_TIER_2

func on_hit_mob(target, projectile):
	super.on_hit_mob(target, projectile)
	_apply_fire_effect(target)

func _apply_fire_effect(target):
	if target.has_method("ignite"):
		target.ignite(3.0)
