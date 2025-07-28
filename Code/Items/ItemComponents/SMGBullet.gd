extends Bullet
class_name SMGBullet

func _init():
	super._init()
	item_name = "submachinegun bullet"
	bullet_type = "smg"
	
	damage = 34.0
	accurate_range = 4
	effective_range_max = 4
	penetration = ArmorPenetrationTier.TIER_1
	shell_speed = SpeedTier.TIER_6
	damage_falloff = 0.5  # DAMAGE_FALLOFF_TIER_5
	scatter = 6.0  # SCATTER_AMOUNT_TIER_6
	accuracy = AccuracyTier.TIER_3
