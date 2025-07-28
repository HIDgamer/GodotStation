extends SMGBullet
class_name PlasteelNailBullet

func _init():
	super._init()
	item_name = "7x45mm plasteel nail"
	icon_state_override = "nail-projectile"
	
	damage = 25.0
	penetration = ArmorPenetrationTier.TIER_5
	damage_falloff = 0.6
	accurate_range = 5
	shell_speed = SpeedTier.TIER_4
