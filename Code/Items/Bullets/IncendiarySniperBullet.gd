extends SniperBullet
class_name IncendiarySniperBullet

func _init():
	super._init()
	item_name = "incendiary sniper bullet"
	damage_type = "BRUTE"
	shrapnel_chance = 0.0
	
	damage = 60.0
	penetration = ArmorPenetrationTier.TIER_4

func _apply_bullseye_effect(target, projectile):
	super._apply_bullseye_effect(target, projectile)
	
	# Apply blinding and fire on bullseye
	var blind_duration = 5.0
	if target.has_method("has_property") and target.has_property("xenomorph"):
		if target.has_method("get_mob_size") and target.get_mob_size() >= 3:  # MOB_SIZE_BIG
			blind_duration = 2.0
	
	if target.has_method("apply_eye_blur"):
		target.apply_eye_blur(blind_duration)
	
	if target.has_method("adjust_fire_stacks"):
		target.adjust_fire_stacks(10)

func on_hit_mob(target, projectile):
	super.on_hit_mob(target, projectile)
	_apply_fire_effect(target)

func _apply_fire_effect(target):
	if target.has_method("ignite"):
		target.ignite(3.0)
