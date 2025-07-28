extends PistolBullet
class_name HighPoweredPistolBullet

func _init():
	super._init()
	item_name = "high-powered pistol bullet"
	headshot_state = "HEADSHOT_OVERLAY_MEDIUM"
	accuracy = AccuracyTier.TIER_3
	damage = 36.0
	penetration = ArmorPenetrationTier.TIER_5
	damage_falloff = 0.7  # DAMAGE_FALLOFF_TIER_7
