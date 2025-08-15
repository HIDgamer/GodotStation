extends Item
class_name SmokingItem

enum SmokingType {
	CIGARETTE,
	CIGAR,
	PIPE,
	LIGHTER,
	MATCH,
	CANDLE,
	ELECTRONIC_CIGARETTE
}

@export var smoking_type: SmokingType = SmokingType.CIGARETTE
@export var is_lit: bool = false
@export var smoke_time: float = 600.0  # 10 minutes in seconds
@export var remaining_smoke_time: float = 600.0
@export var heat_source: float = 0.0
@export var light_range: int = 0
@export var light_power: float = 0.0

# Lighter specific
@export var fuel_amount: float = 100.0
@export var max_fuel: float = 100.0
@export var is_zippo: bool = false

# Match specific
@export var is_burnt: bool = false
@export var burn_time: float = 10.0

# Pipe specific
@export var has_tobacco: bool = true
@export var is_ash: bool = false

# Candle specific
@export var wax_amount: float = 800.0

# Electronic cigarette
@export var is_enabled: bool = false

var icon_lit: String = ""
var icon_unlit: String = ""
var reagent_volume: float = 15.0
var chem_per_puff: float = 0.5

signal smoking_started(item, user)
signal smoking_finished(item, user)
signal lighter_lit(item, user)
signal lighter_extinguished(item, user)
signal item_burnt_out(item)

func _ready():
	super._ready()
	_initialize_smoking_item()
	
	if is_lit:
		_start_processing()

func _initialize_smoking_item():
	match smoking_type:
		SmokingType.CIGARETTE:
			item_name = "Cigarette"
			description = "A roll of tobacco and fillers wrapped in paper."
			force = 0
			w_class = 1
			smoke_time = 600.0
			remaining_smoke_time = smoke_time
			icon_lit = "cig_on"
			icon_unlit = "cig_off"
			
		SmokingType.CIGAR:
			item_name = "Premium Cigar"
			description = "A huge, brown roll of tobacco that makes you feel like a true USCM sergeant."
			force = 0
			w_class = 1
			smoke_time = 3000.0  # 50 minutes
			remaining_smoke_time = smoke_time
			reagent_volume = 20.0
			icon_lit = "cigar_on"
			icon_unlit = "cigar_off"
			
		SmokingType.PIPE:
			item_name = "Smoking Pipe"
			description = "A pipe, for smoking. Probably made of meershaum."
			force = 0
			w_class = 1
			smoke_time = 200.0
			remaining_smoke_time = smoke_time
			has_tobacco = true
			icon_lit = "pipe_on"
			icon_unlit = "pipe_off"
			
		SmokingType.LIGHTER:
			item_name = "Cheap Lighter"
			description = "A cheap-as-free lighter."
			force = 4
			w_class = 1
			heat_source = 1500
			fuel_amount = 100.0
			max_fuel = 100.0
			
		SmokingType.MATCH:
			item_name = "Match"
			description = "A simple match stick, used for lighting fine smokables."
			force = 0
			w_class = 1
			heat_source = 1000
			burn_time = 10.0
			light_range = 2
			light_power = 1.0
			
		SmokingType.CANDLE:
			item_name = "Red Candle"
			description = "A candle."
			force = 0
			w_class = 1
			heat_source = 1000
			wax_amount = 800.0
			light_range = 2
			light_power = 1.0
			
		SmokingType.ELECTRONIC_CIGARETTE:
			item_name = "Electronic Cigarette"
			description = "An electronic cigarette by The American Tobacco Company."
			force = 0
			w_class = 1
			is_enabled = false

func _process(delta):
	if not is_lit:
		return
	
	match smoking_type:
		SmokingType.CIGARETTE, SmokingType.CIGAR:
			_process_smoking(delta)
		SmokingType.PIPE:
			_process_pipe_smoking(delta)
		SmokingType.MATCH:
			_process_match_burning(delta)
		SmokingType.CANDLE:
			_process_candle_burning(delta)

func _process_smoking(delta):
	remaining_smoke_time -= delta
	
	# Apply effects to user if being smoked
	var user = _get_current_user()
	if user and user.has_method("get_health_system"):
		var health_system = user.get_health_system()
		if health_system:
			# Add nicotine and slight damage
			health_system.add_reagent("nicotine", chem_per_puff * delta)
			
			# Small chance of coughing
			if randf() < 0.01:
				user.emote("cough")
	
	if remaining_smoke_time <= 0:
		_burn_out()

func _process_pipe_smoking(delta):
	if not has_tobacco:
		_burn_out()
		return
	
	remaining_smoke_time -= delta
	
	if remaining_smoke_time <= 0:
		_burn_out()
		is_ash = true

func _process_match_burning(delta):
	burn_time -= delta
	
	if burn_time <= 0:
		_burn_out()
		is_burnt = true

func _process_candle_burning(delta):
	wax_amount -= delta
	
	if wax_amount <= 0:
		_burn_out()
		# Create candle stub
		queue_free()

func light_item(user, ignition_source = null) -> bool:
	if is_lit:
		_send_message(user, item_name + " is already lit.")
		return false
	
	match smoking_type:
		SmokingType.CIGARETTE, SmokingType.CIGAR:
			return _light_smokable(user, ignition_source)
		SmokingType.PIPE:
			return _light_pipe(user, ignition_source)
		SmokingType.LIGHTER:
			return _light_lighter(user)
		SmokingType.MATCH:
			return _light_match(user, ignition_source)
		SmokingType.CANDLE:
			return _light_candle(user, ignition_source)
	
	return false

func _light_smokable(user, ignition_source) -> bool:
	if not ignition_source or not ignition_source.has_method("get_heat_source"):
		_send_message(user, "You need something to light the " + item_name + " with.")
		return false
	
	if ignition_source.get_heat_source() < 400:
		_send_message(user, "That's not hot enough to light the " + item_name + ".")
		return false
	
	is_lit = true
	heat_source = 1000
	_start_processing()
	_update_appearance()
	
	var light_message = "You light the " + item_name
	if ignition_source.is_zippo:
		light_message = "With a flick of your wrist, you light the " + item_name + " with your zippo."
	
	_send_message(user, light_message + ".")
	emit_signal("smoking_started", self, user)
	return true

func _light_pipe(user, ignition_source) -> bool:
	if not has_tobacco:
		_send_message(user, "The pipe is empty!")
		return false
	
	if is_ash:
		_send_message(user, "The pipe is full of ash and needs to be emptied.")
		return false
	
	return _light_smokable(user, ignition_source)

func _light_lighter(user) -> bool:
	if fuel_amount <= 0:
		_send_message(user, "The lighter is out of fuel.")
		return false
	
	if not is_lit:
		is_lit = true
		heat_source = 1500
		_start_processing()
		
		if is_zippo:
			_send_message(user, "Without even breaking stride, you flip open and light the zippo in one smooth movement.")
		else:
			if randf() < 0.95:
				_send_message(user, "After a few attempts, you manage to light the lighter.")
			else:
				_send_message(user, "You burn yourself while lighting the lighter.")
				if user.has_method("take_damage"):
					user.take_damage(2, "burn")
		
		emit_signal("lighter_lit", self, user)
		return true
	else:
		extinguish_item(user)
		return true

func _light_match(user, ignition_source) -> bool:
	if is_burnt:
		_send_message(user, "The match is already burnt out.")
		return false
	
	# Matches can be lit on shoes or other rough surfaces
	if ignition_source and ignition_source.has_method("can_light_match"):
		if ignition_source.can_light_match():
			is_lit = true
			heat_source = 1000
			_start_processing()
			_update_appearance()
			
			if randf() < 0.05:
				_send_message(user, "The match splinters into pieces!")
				queue_free()
				return false
			else:
				_send_message(user, "You strike the match and it ignites!")
				return true
	
	_send_message(user, "You need something rough to strike the match on.")
	return false

func _light_candle(user, ignition_source) -> bool:
	if not ignition_source or ignition_source.get_heat_source() < 400:
		_send_message(user, "You need a flame to light the candle.")
		return false
	
	is_lit = true
	heat_source = 1000
	_start_processing()
	_update_appearance()
	
	_send_message(user, "You light the candle.")
	return true

func extinguish_item(user = null) -> bool:
	if not is_lit:
		return false
	
	is_lit = false
	heat_source = 0
	_stop_processing()
	_update_appearance()
	
	match smoking_type:
		SmokingType.CIGARETTE, SmokingType.CIGAR:
			if user:
				_send_message(user, "You put out the " + item_name + ".")
			# Create cigarette butt
			_create_butt()
		SmokingType.LIGHTER:
			if user:
				if is_zippo:
					_send_message(user, "You hear a quiet click as you shut off the zippo.")
				else:
					_send_message(user, "You quietly shut off the lighter.")
			emit_signal("lighter_extinguished", self, user)
		_:
			if user:
				_send_message(user, "You extinguish the " + item_name + ".")
	
	return true

func toggle_electronic_cigarette(user):
	if smoking_type != SmokingType.ELECTRONIC_CIGARETTE:
		return
	
	is_enabled = !is_enabled
	_send_message(user, "You " + ("enable" if is_enabled else "disable") + " the electronic cigarette.")
	_update_appearance()

func empty_pipe_ash(user):
	if smoking_type != SmokingType.PIPE or not is_ash:
		return false
	
	is_ash = false
	_send_message(user, "You empty the ash out of the pipe.")
	# Create ash effect at user location
	return true

func refill_pipe_tobacco(user):
	if smoking_type != SmokingType.PIPE:
		return false
	
	if has_tobacco:
		_send_message(user, "The pipe already has tobacco.")
		return false
	
	has_tobacco = true
	remaining_smoke_time = smoke_time
	_send_message(user, "You refill the pipe with tobacco.")
	return true

func refuel_lighter(fuel_to_add: float) -> float:
	if smoking_type != SmokingType.LIGHTER:
		return 0.0
	
	var old_fuel = fuel_amount
	fuel_amount = min(max_fuel, fuel_amount + fuel_to_add)
	return fuel_amount - old_fuel

func _burn_out():
	is_lit = false
	heat_source = 0
	_stop_processing()
	_update_appearance()
	
	emit_signal("item_burnt_out", self)
	
	match smoking_type:
		SmokingType.CIGARETTE, SmokingType.CIGAR:
			_create_butt()
		SmokingType.MATCH:
			is_burnt = true

func _create_butt():
	# Create cigarette/cigar butt at current location
	var butt_name = "cigarette butt"
	if smoking_type == SmokingType.CIGAR:
		butt_name = "cigar butt"
	
	# Implementation would depend on your item creation system
	queue_free()

func _start_processing():
	set_process(true)

func _stop_processing():
	set_process(false)

func _update_appearance():
	if smoking_type == SmokingType.ELECTRONIC_CIGARETTE:
		# Update based on enabled state
		return
	
	if is_lit and icon_lit != "":
		# Update to lit appearance
		pass
	elif icon_unlit != "":
		# Update to unlit appearance  
		pass

func _get_current_user():
	# Get the current user holding/wearing this item
	if inventory_owner:
		return inventory_owner
	return null

func get_heat_source() -> float:
	return heat_source if is_lit else 0.0

func _send_message(entity, message: String):
	if entity and entity.has_method("display_message"):
		entity.display_message(message)

func get_examine_text() -> String:
	var text = super.get_examine_text()
	
	match smoking_type:
		SmokingType.CIGARETTE, SmokingType.CIGAR:
			if is_lit:
				text += "\nIt is currently lit and smoking."
			else:
				text += "\nIt is unlit."
		SmokingType.PIPE:
			if is_ash:
				text += "\nIt is full of ash."
			elif not has_tobacco:
				text += "\nIt is empty."
			else:
				text += "\nIt is filled with tobacco."
		SmokingType.LIGHTER:
			text += "\nFuel: " + str(int(fuel_amount)) + "%"
		SmokingType.CANDLE:
			text += "\nWax remaining: " + str(int(wax_amount))
		SmokingType.ELECTRONIC_CIGARETTE:
			text += "\nIt is currently " + ("enabled" if is_enabled else "disabled") + "."
	
	return text

# Specialized smoking item classes
class Zippo extends SmokingItem:
	func _init():
		super._init()
		smoking_type = SmokingType.LIGHTER
		item_name = "Zippo Lighter"
		description = "A fancy steel Zippo lighter. Ignite in style."
		is_zippo = true
		_initialize_smoking_item()

class PremiumCigar extends SmokingItem:
	func _init():
		super._init()
		smoking_type = SmokingType.CIGAR
		item_name = "Premium Havanian Cigar"
		description = "A cigar fit for only the best of the best."
		smoke_time = 7200.0  # 2 hours
		reagent_volume = 30.0
		_initialize_smoking_item()

class WeedJoint extends SmokingItem:
	func _init():
		super._init()
		smoking_type = SmokingType.CIGARETTE
		item_name = "Weed Joint"
		description = "A rolled-up package of space weed."
		smoke_time = 1200.0  # 20 minutes
		reagent_volume = 39.0
		_initialize_smoking_item()

# Factory methods
static func create_cigarette() -> SmokingItem:
	var item = SmokingItem.new()
	item.smoking_type = SmokingType.CIGARETTE
	item._initialize_smoking_item()
	return item

static func create_zippo() -> Zippo:
	return Zippo.new()

static func create_match() -> SmokingItem:
	var item = SmokingItem.new()
	item.smoking_type = SmokingType.MATCH
	item._initialize_smoking_item()
	return item
