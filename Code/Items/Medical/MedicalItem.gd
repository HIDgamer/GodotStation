extends Item
class_name MedicalItem

enum MedicalType {
	TRAUMA_KIT,
	BURN_KIT,
	BANDAGE,
	SPLINT,
	SURGICAL_TOOL,
	MEDICINE,
	INJECTOR,
	SURGICAL_LINE,
	SYNTH_GRAFT,
	NANOPASTE,
	BONE_GEL
}

@export var medical_type: MedicalType = MedicalType.MEDICINE
@export var target_limb_required: bool = false
@export var allowed_limbs: Array[String] = []
@export var use_time: float = 3.0
@export var self_use_time: float = 4.0

@export var instant_brute_heal: float = 0.0
@export var instant_burn_heal: float = 0.0
@export var slow_brute_heal: float = 0.0
@export var slow_burn_heal: float = 0.0
@export var stop_bleeding: bool = false
@export var heal_infection: bool = false

@export var is_stackable: bool = false
@export var max_stack: int = 1
@export var current_stack: int = 1

@export var injector_capacity: float = 0.0
@export var injection_dose: float = 0.0
@export var max_injections: int = 0
@export var current_injections: int = 0

@export var bone_gel_remaining: float = 100.0
@export var fracture_fix_cost: float = 5.0
@export var bone_mend_cost: float = 5.0

@export var removes_status_effects: Array[String] = []
@export var adds_status_effects: Dictionary = {}

@export var use_sound: AudioStream = null
@export var success_sound: AudioStream = null
@export var fail_sound: AudioStream = null

var is_being_used: bool = false
var healing_progress: float = 0.0
var target_entity = null
var target_limb: String = ""

signal medical_use_started(item, user, target, limb)
signal medical_use_completed(item, user, target, limb, success)
signal medical_use_interrupted(item, user, target, limb, progress)
signal stack_consumed(item, remaining_stack)
signal injector_used(item, reagent_transferred, injections_remaining)

func _ready():
	super._ready()
	pickupable = true
	_initialize_medical_item()

func _initialize_medical_item():
	match medical_type:
		MedicalType.TRAUMA_KIT:
			is_stackable = true
			max_stack = 10
			current_stack = max_stack
			target_limb_required = true
			use_time = 1.0
			self_use_time = 1.5
			instant_brute_heal = 8.0
			w_class = 1
			
		MedicalType.BURN_KIT:
			is_stackable = true
			max_stack = 10
			current_stack = max_stack
			target_limb_required = true
			use_time = 1.0
			self_use_time = 1.5
			instant_burn_heal = 8.0
			w_class = 1
			
		MedicalType.BANDAGE:
			target_limb_required = true
			use_time = 3.0
			self_use_time = 4.0
			stop_bleeding = true
			w_class = 1
			
		MedicalType.SPLINT:
			target_limb_required = true
			allowed_limbs = ["l_arm", "r_arm", "l_leg", "r_leg", "chest"]
			use_time = 5.0
			self_use_time = 8.0
			w_class = 2

func use(user) -> bool:
	var target = get_target_for_use(user)
	var limb = get_target_limb(user, target)
	
	if target:
		return await use_on(user, target, limb)
	return false

func get_target_for_use(user):
	if user.has_method("get_current_target"):
		var target = user.get_current_target()
		if target and _get_health_system(target):
			return target
	
	var nearby_targets = get_nearby_medical_targets(user)
	if nearby_targets.size() > 0:
		return nearby_targets[0]
	
	return user

func get_target_limb(user, target) -> String:
	if not target_limb_required:
		return ""
	
	if user.has_method("get_targeted_limb"):
		var limb = user.get_targeted_limb()
		if limb and limb != "":
			return limb
	
	var health_system = _get_health_system(target)
	if health_system and health_system.has_method("get_injured_limbs"):
		var injured_limbs = health_system.get_injured_limbs()
		if injured_limbs.size() > 0:
			return injured_limbs[0]
	
	return "torso"

func get_nearby_medical_targets(user) -> Array:
	var targets = []
	var world = user.get_parent()
	if not world:
		return targets
	
	for child in world.get_children():
		if child == user:
			continue
		if not _get_health_system(child):
			continue
		if user.global_position.distance_to(child.global_position) <= 64:
			targets.append(child)
	
	targets.sort_custom(func(a, b): return user.global_position.distance_to(a.global_position) < user.global_position.distance_to(b.global_position))
	return targets

func use_on(user, target, limb: String = "") -> bool:
	if is_being_used:
		_send_message(user, "You're already using " + item_name + ".")
		return false
	
	if not _validate_use(user, target, limb):
		return false
	
	target_entity = target
	target_limb = limb
	
	match medical_type:
		MedicalType.TRAUMA_KIT, MedicalType.BURN_KIT:
			return _use_instant_kit(user, target, limb)
		MedicalType.BANDAGE:
			return _use_bandage(user, target, limb)
		MedicalType.SPLINT:
			return await _use_splint(user, target, limb)
		MedicalType.INJECTOR:
			return _use_injector(user, target, limb)
		MedicalType.BONE_GEL:
			return _use_bone_gel(user, target, limb)
		MedicalType.NANOPASTE:
			return _use_nanopaste(user, target, limb)
		_:
			return _use_generic_medicine(user, target, limb)

func _validate_use(user, target, limb: String) -> bool:
	var health_system = _get_health_system(target)
	if not health_system:
		_send_message(user, target.entity_name + " has no health system.")
		return false
	
	if target_limb_required and limb.is_empty():
		_send_message(user, "You need to target a specific body part.")
		return false
	
	if not allowed_limbs.is_empty() and not allowed_limbs.has(limb):
		_send_message(user, "You can't use " + item_name + " on that body part.")
		return false
	
	if is_stackable and current_stack <= 0:
		_send_message(user, "No " + item_name + " remaining.")
		return false
	
	if medical_type == MedicalType.INJECTOR and current_injections <= 0:
		_send_message(user, item_name + " is empty.")
		return false
	
	return true

func _use_instant_kit(user, target, limb: String) -> bool:
	var health_system = _get_health_system(target)
	
	if medical_type == MedicalType.TRAUMA_KIT:
		health_system.heal_limb_damage(limb, instant_brute_heal, 0)
		_send_message(user, "You treat trauma on " + target.entity_name + "'s " + limb + ".")
	else:
		health_system.heal_limb_damage(limb, 0, instant_burn_heal)
		_send_message(user, "You treat burns on " + target.entity_name + "'s " + limb + ".")
	
	_consume_stack()
	emit_signal("medical_use_completed", self, user, target, limb, true)
	return true

func _use_bandage(user, target, limb: String) -> bool:
	var health_system = _get_health_system(target)
	
	if health_system.has_method("stop_bleeding"):
		health_system.stop_bleeding(limb)
		_send_message(user, "You bandage " + target.entity_name + "'s " + limb + ".")
		_consume_item()
		return true
	
	return false

func _use_splint(user, target, limb: String) -> bool:
	is_being_used = true
	var actual_use_time = self_use_time if user == target else use_time
	
	_send_message(user, "You begin splinting " + target.entity_name + "'s " + limb + "...")
	
	await get_tree().create_timer(actual_use_time).timeout
	
	var health_system = _get_health_system(target)
	if health_system.has_method("apply_splint"):
		health_system.apply_splint(limb)
		_send_message(user, "You successfully splint " + target.entity_name + "'s " + limb + ".")
		_consume_item()
		is_being_used = false
		emit_signal("medical_use_completed", self, user, target, limb, true)
		return true
	
	is_being_used = false
	return false

func _use_bone_gel(user, target, limb: String) -> bool:
	if bone_gel_remaining < fracture_fix_cost:
		_send_message(user, "Not enough bone gel remaining.")
		return false
	
	var health_system = _get_health_system(target)
	if health_system.has_method("repair_fracture"):
		health_system.repair_fracture(limb)
		bone_gel_remaining -= fracture_fix_cost
		_send_message(user, "You apply bone gel to repair " + target.entity_name + "'s " + limb + ".")
		
		if bone_gel_remaining <= 0:
			_consume_item()
		
		return true
	
	return false

func _use_nanopaste(user, target, limb: String) -> bool:
	var health_system = _get_health_system(target)
	
	if health_system.has_method("repair_robotic_limb"):
		health_system.repair_robotic_limb(limb, 15)
		_consume_stack()
		_send_message(user, "You apply nanopaste to repair " + target.entity_name + "'s " + limb + ".")
		return true
	
	return false

func _use_injector(user, target, limb: String) -> bool:
	if current_injections <= 0:
		_send_message(user, item_name + " is empty.")
		return false
	
	# This would integrate with a reagent system
	current_injections -= 1
	_send_message(user, "You inject " + target.entity_name + " with " + item_name + ".")
	
	if current_injections <= 0:
		_consume_item()
	
	emit_signal("injector_used", self, injection_dose, current_injections)
	return true

func _use_generic_medicine(user, target, limb: String) -> bool:
	var health_system = _get_health_system(target)
	
	if instant_brute_heal > 0:
		health_system.heal_damage(instant_brute_heal, 0)
	if instant_burn_heal > 0:
		health_system.heal_damage(0, instant_burn_heal)
	
	for effect_name in removes_status_effects:
		health_system.remove_status_effect(effect_name)
	
	for effect_name in adds_status_effects:
		var duration = adds_status_effects[effect_name]
		health_system.add_status_effect(effect_name, duration)
	
	_send_message(user, "You apply " + item_name + " to " + target.entity_name + ".")
	_consume_item()
	return true

func _consume_stack():
	if is_stackable and current_stack > 0:
		current_stack -= 1
		emit_signal("stack_consumed", self, current_stack)
		
		if current_stack <= 0:
			_consume_item()
		else:
			_update_stack_name()

func _consume_item():
	if inventory_owner and inventory_owner.has_method("remove_item_from_inventory"):
		inventory_owner.remove_item_from_inventory(self)
	queue_free()

func _update_stack_name():
	if is_stackable and current_stack > 1:
		var base_name = item_name.split(" (")[0]
		item_name = base_name + " (" + str(current_stack) + ")"

func _get_health_system(entity):
	if entity.has_method("get_health_system"):
		return entity.get_health_system()
	return entity.get_node_or_null("HealthSystem")

func _send_message(entity, message: String):
	if entity and entity.has_method("display_message"):
		entity.display_message(message)

# Factory methods for common medical items
static func create_trauma_kit() -> MedicalItem:
	var item = MedicalItem.new()
	item.medical_type = MedicalType.TRAUMA_KIT
	item.item_name = "Trauma Kit"
	item.description = "A compact kit for treating physical injuries."
	item._initialize_medical_item()
	return item

static func create_burn_kit() -> MedicalItem:
	var item = MedicalItem.new()
	item.medical_type = MedicalType.BURN_KIT
	item.item_name = "Burn Kit"
	item.description = "A specialized kit for treating burn injuries."
	item._initialize_medical_item()
	return item

static func create_bandage() -> MedicalItem:
	var item = MedicalItem.new()
	item.medical_type = MedicalType.BANDAGE
	item.item_name = "Medical Bandage"
	item.description = "Sterile gauze for treating wounds."
	item._initialize_medical_item()
	return item
