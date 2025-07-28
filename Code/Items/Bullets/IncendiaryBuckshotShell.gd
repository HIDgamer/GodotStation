extends BuckshotShell
class_name IncendiaryBuckshotShell

func _init():
	super._init()
	item_name = "incendiary buckshot shell"
	handful_state = "incen_buckshot"

func on_hit_mob(target, projectile):
	super.on_hit_mob(target, projectile)
	_apply_fire_effect(target)

func _apply_fire_effect(target):
	if target.has_method("ignite"):
		target.ignite(3.0)
