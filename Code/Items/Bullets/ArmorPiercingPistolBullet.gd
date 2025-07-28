extends PistolBullet
class_name ArmorPiercingPistolBullet

func _init():
	super._init()
	item_name = "armor-piercing pistol bullet"
	damage = 25.0
	accuracy = AccuracyTier.TIER_2
	penetration = ArmorPenetrationTier.TIER_8
	shrapnel_chance = 0.2
