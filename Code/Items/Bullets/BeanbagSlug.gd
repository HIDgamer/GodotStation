extends ShotgunBullet
class_name BeanbagSlug

func _init():
	super._init()
	item_name = "beanbag slug"
	headshot_state = "HEADSHOT_OVERLAY_LIGHT"
	handful_state = "beanbag_slug"
	icon_state_override = "beanbag"
	
	set_bullet_flag(BulletFlags.IGNORE_RESIST, true)
	
	max_range = 12
	shrapnel_chance = 0.0
	damage = 0.0
	stamina_damage = 45.0
	accuracy = AccuracyTier.TIER_3
	shell_speed = SpeedTier.TIER_3

func on_hit_mob(target, projectile):
	super.on_hit_mob(target, projectile)
	
	if target.has_method("shake_camera"):
		target.shake_camera(2, 1)
