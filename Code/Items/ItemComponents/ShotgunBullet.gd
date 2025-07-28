# Base Shotgun Bullet
extends Bullet
class_name ShotgunBullet

func _init():
	super._init()
	bullet_type = "shotgun"
	headshot_state = "HEADSHOT_OVERLAY_HEAVY"
