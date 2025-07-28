extends SMGBullet
class_name ArmorShreddingSMGBullet

@export var pen_armor_punch: int = 4

func _init():
	super._init()
	item_name = "armor-shredding submachinegun bullet"
	scatter = 10.0  # SCATTER_AMOUNT_TIER_10
	damage = 20.0
	penetration = ArmorPenetrationTier.TIER_4
	shell_speed = SpeedTier.TIER_3
	damage_falloff = 1.0  # DAMAGE_FALLOFF_TIER_10

func on_hit_mob(target, projectile):
	super.on_hit_mob(target, projectile)
	
	if target.has_method("degrade_armor"):
		target.degrade_armor(pen_armor_punch)
