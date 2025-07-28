extends ShotgunBullet
class_name BuckshotShell

func _init():
	super._init()
	item_name = "buckshot shell"
	icon_state_override = "buckshot"
	handful_state = "buckshot_shell"
	multiple_handful_name = true
	bonus_projectiles_type = "BuckshotSpread"
	
	accurate_range = 4
	max_range = 4
	damage = 65.0
	penetration = ArmorPenetrationTier.TIER_1
	shell_speed = SpeedTier.TIER_2

func on_hit_mob(target, projectile):
	super.on_hit_mob(target, projectile)
	_apply_knockback(target, projectile)

func _apply_knockback(target, projectile):
	if target.has_method("apply_knockback"):
		target.apply_knockback(3, projectile.get_direction() if projectile.has_method("get_direction") else Vector2.RIGHT)
