extends ArmorPiercingRifleBullet
class_name PenetratingRifleBullet

func _init():
	super._init()
	item_name = "wall-penetrating rifle bullet"
	shrapnel_chance = 0.0
	damage = 35.0
	penetration = ArmorPenetrationTier.TIER_10
	
	# Add penetrating trait
	set_bullet_flag(BulletFlags.IGNORE_COVER, true)
