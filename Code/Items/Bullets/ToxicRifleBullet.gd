extends ArmorPiercingRifleBullet
class_name ToxicRifleBullet

@export var acid_per_hit: int = 7
@export var organic_damage_mult: float = 3.0

func _init():
	super._init()
	item_name = "toxic rifle bullet"

func on_hit_mob(target, projectile):
	super.on_hit_mob(target, projectile)
	
	# Apply toxic buildup
	if target.has_method("add_toxic_buildup"):
		target.add_toxic_buildup(acid_per_hit)

func on_hit_turf(target, projectile):
	super.on_hit_turf(target, projectile)
	
	# Increased damage vs organic terrain
	if target.has_method("has_property") and target.has_property("organic"):
		var enhanced_damage = damage * organic_damage_mult
		if target.has_method("take_damage"):
			target.take_damage(enhanced_damage, damage_type.to_lower(), "ballistic", true, penetration)

func on_hit_obj(target, projectile):
	super.on_hit_obj(target, projectile)
	
	# Increased damage vs organic objects
	if target.has_method("has_property") and target.has_property("organic"):
		var enhanced_damage = damage * organic_damage_mult
		if target.has_method("take_damage"):
			target.take_damage(enhanced_damage, damage_type.to_lower(), "ballistic", true, penetration)
