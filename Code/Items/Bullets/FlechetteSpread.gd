extends ShotgunBullet
class_name FlechetteSpread

func _init():
	super._init()
	item_name = "additional flechette"
	icon_state_override = "flechette"
	
	max_range = 12
	damage = 30.0
	penetration = ArmorPenetrationTier.TIER_7
	scatter = 5.0  # SCATTER_AMOUNT_TIER_5
