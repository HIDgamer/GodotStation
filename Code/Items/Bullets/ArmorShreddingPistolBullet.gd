extends PistolBullet
class_name ArmorShreddingPistolBullet

@export var pen_armor_punch: int = 3

func _init():
	super._init()
	item_name = "armor-shredding pistol bullet"
	damage = 15.0
	penetration = ArmorPenetrationTier.TIER_4

func on_hit_mob(target, projectile):
	super.on_hit_mob(target, projectile)
	
	if target.has_method("degrade_armor"):
		target.degrade_armor(pen_armor_punch)
