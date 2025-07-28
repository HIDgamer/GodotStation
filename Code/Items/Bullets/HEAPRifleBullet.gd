extends RifleBullet
class_name HEAPRifleBullet

func _init():
	super._init()
	item_name = "high-explosive armor-piercing rifle bullet"
	headshot_state = "HEADSHOT_OVERLAY_HEAVY"
	damage = 55.0  # Big damage, doesn't actually blow up because that's stupid
	penetration = ArmorPenetrationTier.TIER_8
