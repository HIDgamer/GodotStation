extends ShotgunBullet
class_name ShotgunSlug

func _init():
	super._init()
	item_name = "shotgun slug"
	handful_state = "slug_shell"
	
	accurate_range = 8
	max_range = 8
	damage = 70.0
	penetration = ArmorPenetrationTier.TIER_4
	accuracy = AccuracyTier.TIER_3

func on_hit_mob(target, projectile):
	super.on_hit_mob(target, projectile)
	_apply_knockback(target, projectile)

func _apply_knockback(target, projectile):
	if target.has_method("apply_knockback"):
		target.apply_knockback(6, projectile.get_direction() if projectile.has_method("get_direction") else Vector2.RIGHT)
	
	_apply_knockback_effects(target, projectile)

func _apply_knockback_effects(target, projectile):
	if target.has_method("has_property") and target.has_property("xenomorph"):
		if target.has_method("knockdown"):
			target.knockdown(0.5)
		if target.has_method("stun"):
			target.stun(0.5)
		if target.has_method("apply_slow"):
			target.apply_slow(1.0, "SUPERSLOW")
			target.apply_slow(3.0, "SLOW")
	else:
		if not (target.has_method("has_property") and target.has_property("yautja")):
			if target.has_method("apply_slow"):
				target.apply_slow(1.0, "SUPERSLOW")
				target.apply_slow(2.0, "SLOW")
		
		if target.has_method("apply_stamina_damage"):
			target.apply_stamina_damage(damage, "bullet")
