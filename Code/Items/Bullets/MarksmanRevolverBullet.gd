extends RevolverBullet
class_name MarksmanRevolverBullet

func _init():
	super._init()
	item_name = "marksman revolver bullet"
	damage = 55.0
	shrapnel_chance = 0.0
	damage_falloff = 0.0
	accurate_range = 12
	penetration = ArmorPenetrationTier.TIER_7
