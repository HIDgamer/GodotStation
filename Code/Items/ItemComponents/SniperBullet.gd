# Base Sniper Bullet
extends Bullet
class_name SniperBullet

func _init():
	super._init()
	item_name = "sniper bullet"
	bullet_type = "sniper"
	headshot_state = "HEADSHOT_OVERLAY_HEAVY"
	
	damage_falloff = 0.0
	set_bullet_flag(BulletFlags.SNIPER, true)
	set_bullet_flag(BulletFlags.IGNORE_COVER, true)
	effective_range_max = 4
	
	accuracy = AccuracyTier.TIER_8
	accurate_range = 32
	max_range = 32
	scatter = 0.0
	damage = 70.0
	penetration = ArmorPenetrationTier.TIER_10
	shell_speed = SpeedTier.TIER_6

func on_hit_mob(target, projectile):
	super.on_hit_mob(target, projectile)
	
	# Check for bullseye (direct aimed shot)
	if projectile.has_method("is_bullseye") and projectile.is_bullseye() and target == projectile.get_original_target():
		_apply_bullseye_effect(target, projectile)

func _apply_bullseye_effect(target, projectile):
	# Double damage on bullseye
	if target.has_method("take_damage"):
		target.take_damage(damage * 2, damage_type.to_lower(), "ballistic", true, penetration)
	
	var shooter = projectile.get_firer() if projectile.has_method("get_firer") else null
	if shooter and shooter.has_method("send_message"):
		shooter.send_message("Bullseye!", "warning")
