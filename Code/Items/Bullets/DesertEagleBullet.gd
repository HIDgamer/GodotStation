extends PistolBullet
class_name DesertEagleBullet

func _init():
	super._init()
	item_name = ".50 heavy pistol bullet"
	damage = 45.0
	headshot_state = "HEADSHOT_OVERLAY_HEAVY"
	penetration = ArmorPenetrationTier.TIER_6
	shrapnel_chance = 0.5  # SHRAPNEL_CHANCE_TIER_5
