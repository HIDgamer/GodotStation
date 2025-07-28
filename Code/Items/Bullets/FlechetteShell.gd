extends ShotgunBullet
class_name FlechetteShell

func _init():
	super._init()
	item_name = "flechette shell"
	icon_state_override = "flechette"
	handful_state = "flechette_shell"
	multiple_handful_name = true
	bonus_projectiles_type = "FlechetteSpread"
	
	max_range = 12
	damage = 30.0
	penetration = ArmorPenetrationTier.TIER_7
	shrapnel_chance = 0.0
