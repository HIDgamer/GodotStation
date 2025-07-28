extends PistolBullet
class_name HollowpointPistolBullet

func _init():
	super._init()
	item_name = "hollowpoint pistol bullet"
	damage = 55.0  # Hollowpoint is strong
	penetration = 0  # Hollowpoint can't pierce armor!
	shrapnel_chance = 0.3  # Hollowpoint causes more shrapnel
