extends HeavyPistolBullet
class_name SuperHeavyPistolBullet

func _init():
	super._init()
	item_name = ".50 heavy pistol bullet"
	damage = 60.0
	penetration = ArmorPenetrationTier.TIER_4
