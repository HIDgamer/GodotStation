extends PistolBullet
class_name HeavyPistolBullet

func _init():
	super._init()
	item_name = "heavy pistol bullet"
	headshot_state = "HEADSHOT_OVERLAY_MEDIUM"
	damage = 55.0
	penetration = ArmorPenetrationTier.TIER_3
	shrapnel_chance = 0.2
