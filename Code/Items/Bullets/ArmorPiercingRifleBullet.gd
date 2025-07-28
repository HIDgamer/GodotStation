extends RifleBullet
class_name ArmorPiercingRifleBullet

func _init():
	super._init()
	item_name = "armor-piercing rifle bullet"
	damage = 30.0
	penetration = ArmorPenetrationTier.TIER_8
