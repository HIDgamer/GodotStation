extends ArmorPiercingPistolBullet
class_name PenetratingPistolBullet

func _init():
	super._init()
	item_name = "wall-penetrating pistol bullet"
	shrapnel_chance = 0.0
	damage = 30.0
	penetration = ArmorPenetrationTier.TIER_10
	set_bullet_flag(BulletFlags.IGNORE_COVER, true)
