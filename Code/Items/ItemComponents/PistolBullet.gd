extends Bullet
class_name PistolBullet

func _init():
	super._init()
	item_name = "pistol bullet"
	bullet_type = "pistol"
	headshot_state = "HEADSHOT_OVERLAY_MEDIUM"
	
	accuracy = AccuracyTier.TIER_3 - 20  # -HIT_ACCURACY_TIER_3
	damage = 40.0
	penetration = ArmorPenetrationTier.TIER_2
	shrapnel_chance = 0.2  # SHRAPNEL_CHANCE_TIER_2
