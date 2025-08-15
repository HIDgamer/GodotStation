extends Item
class_name WeldingEquipment

enum WeldingType {
	WELDING_BACKPACK,
	MINI_FUEL_CANISTER,
	WELDING_MASK,
	WELDING_GOGGLES,
	ADVANCED_WELDER,
	INDUSTRIAL_WELDER
}

@export var welding_type: WeldingType = WeldingType.WELDING_BACKPACK
@export var max_fuel: float = 600.0
@export var current_fuel: float = 600.0
@export var fuel_transfer_rate: float = 50.0
@export var is_damaged: bool = false
@export var original_health: float = 75.0

# Mask/Goggles specific
@export var eye_protection_level: int = 4  # 4 = full welding protection
@export var _is_equipped: bool = false

# Advanced welder specific
@export var efficiency_multiplier: float = 1.0
@export var fuel_efficiency: float = 1.0
@export var welding_power: float = 15.0

var refill_in_progress: bool = false

signal fuel_transferred(equipment, target, amount)
signal equipment_damaged(equipment, damage_amount)
signal equipment_exploded(equipment)
signal welder_refilled(equipment, welder, amount)

func _ready():
	super._ready()
	_initialize_welding_equipment()

func _initialize_welding_equipment():
	match welding_type:
		WeldingType.WELDING_BACKPACK:
			item_name = "Welding Kit"
			description = "A heavy-duty, portable welding fluid carrier."
			w_class = 3  # SIZE_LARGE equivalent
			force = 0
			max_fuel = 600.0
			current_fuel = max_fuel
			original_health = 75.0
			health = original_health
			
		WeldingType.MINI_FUEL_CANISTER:
			item_name = "ES-11 Fuel Canister"
			description = "A robust little pressurized canister for welding fuel."
			w_class = 2  # SIZE_MEDIUM equivalent
			force = 0
			max_fuel = 120.0
			current_fuel = max_fuel
			original_health = 50.0
			health = original_health
			
		WeldingType.WELDING_MASK:
			item_name = "Welding Mask"
			description = "A protective mask that shields eyes from welding light."
			w_class = 1
			force = 0
			eye_protection_level = 4
			
		WeldingType.WELDING_GOGGLES:
			item_name = "Welding Goggles"
			description = "Protective goggles for welding work."
			w_class = 1
			force = 0
			eye_protection_level = 3
			
		WeldingType.ADVANCED_WELDER:
			item_name = "Advanced Welding Tool"
			description = "A high-efficiency welding tool with improved fuel consumption."
			w_class = 1
			force = 3
			max_fuel = 50.0
			current_fuel = max_fuel
			efficiency_multiplier = 1.5
			fuel_efficiency = 1.3
			welding_power = 20.0
			
		WeldingType.INDUSTRIAL_WELDER:
			item_name = "Industrial Welding Tool"
			description = "A heavy-duty industrial welding tool."
			w_class = 2
			force = 5
			max_fuel = 80.0
			current_fuel = max_fuel
			efficiency_multiplier = 1.2
			fuel_efficiency = 1.1
			welding_power = 25.0

func use_on_target(user, target) -> bool:
	match welding_type:
		WeldingType.WELDING_BACKPACK, WeldingType.MINI_FUEL_CANISTER:
			return await _refill_welder(user, target)
		WeldingType.WELDING_MASK, WeldingType.WELDING_GOGGLES:
			return _equip_protection(user)
		WeldingType.ADVANCED_WELDER, WeldingType.INDUSTRIAL_WELDER:
			return _use_advanced_welder(user, target)
	
	return false

func _refill_welder(user, target) -> bool:
	if not target.has_method("is_welder") or not target.is_welder():
		_send_message(user, "You can only refill welding tools with this.")
		return false
	
	if target.has_method("is_welding") and target.is_welding():
		_send_message(user, "Turn off the welder first!")
		# Small chance of explosion if they try anyway
		if randf() < 0.1:
			_cause_explosion(user)
		return false
	
	if target.has_method("get_fuel_level"):
		var target_fuel = target.get_fuel_level()
		var target_max_fuel = target.get_max_fuel() if target.has_method("get_max_fuel") else 40.0
		
		if target_fuel >= target_max_fuel:
			_send_message(user, "The welder is already full!")
			return false
		
		var transfer_amount = min(current_fuel, target_max_fuel - target_fuel)
		
		if transfer_amount <= 0:
			_send_message(user, "No fuel to transfer!")
			return false
		
		# Perform refill
		refill_in_progress = true
		_send_message(user, "You start refilling the welder...")
		
		await get_tree().create_timer(2.0).timeout
		
		if not _can_continue_refill(user, target):
			refill_in_progress = false
			return false
		
		# Transfer fuel
		current_fuel -= transfer_amount
		if target.has_method("add_fuel"):
			target.add_fuel(transfer_amount)
		
		refill_in_progress = false
		emit_signal("welder_refilled", self, target, transfer_amount)
		_send_message(user, "Welder refilled!")
		
		return true
	
	return false

func _equip_protection(user) -> bool:
	if user.has_method("equip_eye_protection"):
		if is_equipped:
			user.unequip_eye_protection(self)
			_is_equipped = false
			_send_message(user, "You remove the " + item_name + ".")
		else:
			user.equip_eye_protection(self)
			_is_equipped = true
			_send_message(user, "You put on the " + item_name + ".")
		return true
	
	return false

func _use_advanced_welder(user, target) -> bool:
	# This would integrate with your existing welding tool system
	# Advanced welders work like regular welders but with better efficiency
	if target.has_method("weld_with"):
		var effective_power = welding_power * efficiency_multiplier
		var fuel_cost = 1.0 / fuel_efficiency
		
		if current_fuel >= fuel_cost:
			current_fuel -= fuel_cost
			return target.weld_with(effective_power)
	
	return false

func refill_from_source(user, fuel_source) -> bool:
	if welding_type != WeldingType.WELDING_BACKPACK and welding_type != WeldingType.MINI_FUEL_CANISTER:
		return false
	
	if not fuel_source.has_method("is_fuel_tank") or not fuel_source.is_fuel_tank():
		_send_message(user, "This must be filled with a fuel tank.")
		return false
	
	if current_fuel >= max_fuel:
		_send_message(user, item_name + " is already full!")
		return false
	
	var transfer_amount = max_fuel - current_fuel
	
	if fuel_source.has_method("transfer_fuel"):
		var actual_transfer = fuel_source.transfer_fuel(transfer_amount)
		current_fuel += actual_transfer
		
		_send_message(user, "You refill the " + item_name + " from the fuel tank.")
		emit_signal("fuel_transferred", self, fuel_source, actual_transfer)
		return true
	
	return false

func take_damage(damage_amount: float, damage_type: String = "brute", armor_type: String = "", effects: bool = true, armour_penetration: float = 0.0, attacker = null):
	super.take_damage(damage_amount, damage_type)
	
	emit_signal("equipment_damaged", self, damage_amount)
	
	# Check for damage effects
	if health < original_health * 0.5:
		is_damaged = true
		description += "\nThe self-sealing liner has been exposed."
	
	# Risk of explosion when damaged
	if health <= 0 and current_fuel > 0:
		_cause_explosion(null)

func _cause_explosion(user):
	if user:
		_send_message(user, "That was stupid of you.")
	
	emit_signal("equipment_exploded", self)
	
	# Create explosion effect at current position
	_create_explosion_effect()
	
	# Damage nearby entities
	_damage_nearby_entities()
	
	queue_free()

func _create_explosion_effect():
	# Create visual/audio explosion effect
	# This would depend on your effects system
	pass

func _damage_nearby_entities():
	var explosion_radius = 96.0  # 3 tiles
	var explosion_damage = 30.0
	
	var nearby_entities = _get_entities_in_radius(explosion_radius)
	for entity in nearby_entities:
		if entity.has_method("take_damage"):
			entity.take_damage(explosion_damage, "burn")

func _get_entities_in_radius(radius: float) -> Array:
	var entities = []
	var world = get_parent()
	if not world:
		return entities
	
	for child in world.get_children():
		if child == self:
			continue
		if child.has_method("take_damage"):
			if global_position.distance_to(child.global_position) <= radius:
				entities.append(child)
	
	return entities

func _can_continue_refill(user, target) -> bool:
	if not user or not target:
		return false
	
	if user.global_position.distance_to(global_position) > 64:
		_send_message(user, "You moved too far away!")
		return false
	
	return true

func get_eye_protection_level() -> int:
	if welding_type == WeldingType.WELDING_MASK or welding_type == WeldingType.WELDING_GOGGLES:
		return eye_protection_level
	return 0

func can_protect_from_welding() -> bool:
	return get_eye_protection_level() >= 4

func _send_message(entity, message: String):
	if entity and entity.has_method("display_message"):
		entity.display_message(message)

func get_examine_text() -> String:
	var text = super.get_examine_text()
	
	match welding_type:
		WeldingType.WELDING_BACKPACK, WeldingType.MINI_FUEL_CANISTER:
			text += "\n" + str(int(current_fuel)) + " units of welding fuel left!"
			if is_damaged:
				text += "\nThe fuel container appears damaged - the self sealing liner has been exposed."
			else:
				text += "\nNo punctures are seen on the container upon closer inspection."
		WeldingType.WELDING_MASK, WeldingType.WELDING_GOGGLES:
			text += "\nProvides level " + str(eye_protection_level) + " eye protection."
			if is_equipped:
				text += "\nCurrently being worn."
		WeldingType.ADVANCED_WELDER, WeldingType.INDUSTRIAL_WELDER:
			text += "\nFuel: " + str(int(current_fuel)) + "/" + str(int(max_fuel))
			text += "\nEfficiency rating: " + str(efficiency_multiplier) + "x"
	
	return text

# Specialized welding equipment classes
class HeavyDutyWeldpack extends WeldingEquipment:
	func _init():
		super._init()
		welding_type = WeldingType.WELDING_BACKPACK
		item_name = "Heavy-Duty Welding Kit"
		description = "An industrial-grade welding fuel carrier with extra capacity."
		max_fuel = 1000.0
		current_fuel = max_fuel
		original_health = 120.0
		health = original_health
		w_class = 3
		_initialize_welding_equipment()

class CompactFuelCanister extends WeldingEquipment:
	func _init():
		super._init()
		welding_type = WeldingType.MINI_FUEL_CANISTER
		item_name = "Compact Fuel Canister"
		description = "A small, portable fuel canister for emergency use."
		max_fuel = 60.0
		current_fuel = max_fuel
		original_health = 30.0
		health = original_health
		w_class = 1
		_initialize_welding_equipment()

class EngineerWeldingMask extends WeldingEquipment:
	func _init():
		super._init()
		welding_type = WeldingType.WELDING_MASK
		item_name = "Engineering Welding Mask"
		description = "A professional welding mask with auto-darkening lens."
		eye_protection_level = 5  # Superior protection
		_initialize_welding_equipment()

class MasterWeldingTool extends WeldingEquipment:
	func _init():
		super._init()
		welding_type = WeldingType.ADVANCED_WELDER
		item_name = "Master Welding Tool"
		description = "The pinnacle of welding technology - efficient and powerful."
		max_fuel = 60.0
		current_fuel = max_fuel
		efficiency_multiplier = 2.0
		fuel_efficiency = 1.5
		welding_power = 30.0
		_initialize_welding_equipment()

class ExperimentalWelder extends WeldingEquipment:
	var last_fuel_gen_time: float = 0.0
	var fuel_gen_rate: float = 0.1  # fuel per second
	
	func _init():
		super._init()
		welding_type = WeldingType.ADVANCED_WELDER
		item_name = "Experimental Welding Tool"
		description = "An experimental welder that slowly regenerates fuel."
		max_fuel = 40.0
		current_fuel = max_fuel
		efficiency_multiplier = 1.3
		fuel_efficiency = 1.2
		welding_power = 18.0
		_initialize_welding_equipment()
		set_process(true)
	
	func _process(delta):
		# Regenerate fuel slowly
		if current_fuel < max_fuel:
			current_fuel = min(max_fuel, current_fuel + fuel_gen_rate * delta)

# Factory methods
static func create_welding_backpack() -> WeldingEquipment:
	var equipment = WeldingEquipment.new()
	equipment.welding_type = WeldingType.WELDING_BACKPACK
	equipment._initialize_welding_equipment()
	return equipment

static func create_mini_fuel_canister() -> WeldingEquipment:
	var equipment = WeldingEquipment.new()
	equipment.welding_type = WeldingType.MINI_FUEL_CANISTER
	equipment._initialize_welding_equipment()
	return equipment

static func create_welding_mask() -> WeldingEquipment:
	var equipment = WeldingEquipment.new()
	equipment.welding_type = WeldingType.WELDING_MASK
	equipment._initialize_welding_equipment()
	return equipment

static func create_advanced_welder() -> WeldingEquipment:
	var equipment = WeldingEquipment.new()
	equipment.welding_type = WeldingType.ADVANCED_WELDER
	equipment._initialize_welding_equipment()
	return equipment

static func create_heavy_duty_weldpack() -> HeavyDutyWeldpack:
	return HeavyDutyWeldpack.new()

static func create_experimental_welder() -> ExperimentalWelder:
	return ExperimentalWelder.new()
