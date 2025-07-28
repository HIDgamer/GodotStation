extends ArmorPiercingSMGBullet
class_name HEAPSMGBullet

func _init():
	super._init()
	item_name = "high-explosive armor-piercing submachinegun bullet"
	damage = 45.0
	headshot_state = "HEADSHOT_OVERLAY_MEDIUM"
