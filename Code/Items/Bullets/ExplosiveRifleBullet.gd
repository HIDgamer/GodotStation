extends RifleBullet
class_name ExplosiveRifleBullet

func _init():
	super._init()
	item_name = "explosive rifle bullet"
	damage = 25.0
	accurate_range = 22
	accuracy = 0
	shell_speed = SpeedTier.TIER_4
	damage_falloff = 0.9  # DAMAGE_FALLOFF_TIER_9

func on_hit_mob(target, projectile):
	super.on_hit_mob(target, projectile)
	_create_explosion(target.global_position, projectile)

func on_hit_obj(target, projectile):
	super.on_hit_obj(target, projectile)
	_create_explosion(target.global_position, projectile)

func on_hit_turf(target, projectile):
	super.on_hit_turf(target, projectile)
	_create_explosion(target.global_position, projectile)

func _create_explosion(pos: Vector2, projectile):
	# Create explosion effect - would need explosion system
	var explosion_manager = get_node_or_null("/root/ExplosionManager")
	if explosion_manager and explosion_manager.has_method("create_explosion"):
		explosion_manager.create_explosion(pos, 80, 40, "LINEAR")
