extends PistolBullet
class_name IncendiaryPistolBullet

func _init():
	super._init()
	item_name = "incendiary pistol bullet"
	damage_type = "BURN"
	shrapnel_chance = 0.0
	accuracy = AccuracyTier.TIER_3
	damage = 20.0

func on_hit_mob(target, projectile):
	super.on_hit_mob(target, projectile)
	_apply_fire_effect(target)

func _apply_fire_effect(target):
	if target.has_method("ignite"):
		target.ignite(3.0)
