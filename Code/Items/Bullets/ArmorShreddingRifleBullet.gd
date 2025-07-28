extends RifleBullet
class_name ArmorShreddingRifleBullet

@export var pen_armor_punch: int = 5

func _init():
	super._init()
	item_name = "armor-shredding rifle bullet"
	damage = 20.0
	penetration = ArmorPenetrationTier.TIER_4

func on_hit_mob(target, projectile):
	super.on_hit_mob(target, projectile)
	
	# Apply armor degradation
	if target.has_method("degrade_armor"):
		target.degrade_armor(pen_armor_punch)
