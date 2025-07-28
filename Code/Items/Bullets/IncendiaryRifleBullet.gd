extends RifleBullet
class_name IncendiaryRifleBullet

func _init():
	super._init()
	item_name = "incendiary rifle bullet"
	damage_type = "BURN"
	shrapnel_chance = 0.0
	
	damage = 30.0
	shell_speed = SpeedTier.TIER_4
	accuracy = AccuracyTier.TIER_2 - 20  # -HIT_ACCURACY_TIER_2
	damage_falloff = 1.0  # DAMAGE_FALLOFF_TIER_10

func on_hit_mob(target, projectile):
	super.on_hit_mob(target, projectile)
	_apply_fire_effect(target)

func on_hit_obj(target, projectile):
	super.on_hit_obj(target, projectile)
	_apply_fire_effect(target)

func _apply_fire_effect(target):
	if target.has_method("ignite"):
		target.ignite(3.0)  # Burn for 3 seconds
