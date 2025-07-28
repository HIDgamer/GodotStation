extends SMGBullet
class_name ArmorPiercingSMGBullet

func _init():
	super._init()
	item_name = "armor-piercing submachinegun bullet"
	damage = 26.0
	penetration = ArmorPenetrationTier.TIER_6
	shell_speed = SpeedTier.TIER_4
