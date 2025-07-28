extends ShotgunBullet
class_name BuckshotSpread

func _init():
	super._init()
	item_name = "additional buckshot"
	icon_state_override = "buckshot"
	
	accurate_range = 4
	max_range = 6
	damage = 65.0
	penetration = ArmorPenetrationTier.TIER_1
	shell_speed = SpeedTier.TIER_2
	scatter = 1.0  # SCATTER_AMOUNT_TIER_1
