extends Bullet
class_name RevolverBullet

func _init():
	super._init()
	item_name = "revolver bullet"
	bullet_type = "revolver"
	headshot_state = "HEADSHOT_OVERLAY_MEDIUM"
	
	damage = 72.0
	penetration = ArmorPenetrationTier.TIER_1
	accuracy = AccuracyTier.TIER_1
