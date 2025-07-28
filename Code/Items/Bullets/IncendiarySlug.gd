extends ShotgunBullet
class_name IncendiarySlug

func _init():
	super._init()
	item_name = "incendiary slug"
	handful_state = "incendiary_slug"
	damage_type = "BURN"
	
	accuracy = AccuracyTier.TIER_2
	max_range = 12
	damage = 55.0
	penetration = ArmorPenetrationTier.TIER_1

func on_hit_mob(target, projectile):
	super.on_hit_mob(target, projectile)
	_create_fire_burst(target.global_position, projectile)
	_apply_knockback(target, projectile)

func on_hit_obj(target, projectile):
	super.on_hit_obj(target, projectile)
	_create_fire_burst(target.global_position, projectile)

func on_hit_turf(target, projectile):
	super.on_hit_turf(target, projectile)
	_create_fire_burst(target.global_position, projectile)

func _create_fire_burst(pos: Vector2, projectile):
	# Create fire burst effect
	var fire_manager = get_node_or_null("/root/FireManager")
	if fire_manager and fire_manager.has_method("create_fire_burst"):
		fire_manager.create_fire_burst(pos, damage_type)

func _apply_knockback(target, projectile):
	if target.has_method("apply_knockback"):
		target.apply_knockback(3, projectile.get_direction() if projectile.has_method("get_direction") else Vector2.RIGHT)
