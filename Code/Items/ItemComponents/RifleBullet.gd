extends Bullet
class_name RifleBullet

func _init():
	super._init()
	item_name = "rifle bullet"
	bullet_type = "rifle"
	headshot_state = "HEADSHOT_OVERLAY_MEDIUM"
	
	damage = 40.0
	penetration = ArmorPenetrationTier.TIER_1
	accurate_range = 16
	accuracy = AccuracyTier.TIER_4
	scatter = 10.0  # SCATTER_AMOUNT_TIER_10
	shell_speed = SpeedTier.TIER_6
	effective_range_max = 7
	damage_falloff = 0.7  # DAMAGE_FALLOFF_TIER_7
	max_range = 24
