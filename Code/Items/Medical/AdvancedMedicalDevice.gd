extends Item
class_name AdvancedMedicalDevice

enum DeviceType {
	AUTO_CPR,
	PORTABLE_DIALYSIS,
	BODY_SCANNER,
	DEFIBRILLATOR,
	SURGICAL_MEMBRANE,
	EMERGENCY_AUTOINJECTOR
}

@export var device_type: DeviceType = DeviceType.AUTO_CPR
@export var is_powered: bool = false
@export var battery_level: float = 100.0
@export var max_battery: float = 100.0
@export var power_consumption: float = 20.0  # per use/minute
@export var is_attached: bool = false
@export var attached_patient = null

# Auto CPR specific
@export var pump_interval: float = 7.5  # seconds between pumps
@export var last_pump_time: float = 0.0
@export var effectiveness: float = 1.0

# Dialysis specific
@export var filter_rate: float = 3.0  # reagents removed per second
@export var blood_cost: float = 12.0  # blood lost per second
@export var attachment_time: float = 1.2

# Body scanner specific
@export var scan_time: float = 5.0
@export var detailed_scan: bool = false

var attachment_in_progress: bool = false
var filtering_active: bool = false
var cpr_active: bool = false

signal device_activated(device, patient)
signal device_deactivated(device, patient) 
signal patient_attached(device, patient)
signal patient_detached(device, patient)
signal battery_depleted(device)
signal cpr_administered(device, patient)
signal dialysis_complete(device, patient, toxins_removed)

func _ready():
	super._ready()
	_initialize_device()

func _initialize_device():
	match device_type:
		DeviceType.AUTO_CPR:
			item_name = "Autocompressor"
			description = "A device that gives regular compression to the victim's ribcage."
			w_class = 2
			force = 5
			battery_level = max_battery
			pump_interval = 7.5
			
		DeviceType.PORTABLE_DIALYSIS:
			item_name = "Portable Dialysis Machine"
			description = "A man-portable dialysis machine with internal battery."
			w_class = 2
			force = 0
			battery_level = max_battery
			filter_rate = 3.0
			blood_cost = 12.0
			attachment_time = 1.2
			
		DeviceType.BODY_SCANNER:
			item_name = "Portable Body Scanner"
			description = "A handheld medical scanner for diagnostics."
			w_class = 1
			force = 0
			scan_time = 5.0
			
		DeviceType.DEFIBRILLATOR:
			item_name = "Emergency Defibrillator"
			description = "For emergency cardiac resuscitation."
			w_class = 2
			force = 0
			power_consumption = 50.0
			
		DeviceType.SURGICAL_MEMBRANE:
			item_name = "Surgical Membrane Applicator"
			description = "Applies bio-synthetic membranes to surgical sites."
			w_class = 1
			force = 0

func use_on_patient(user, patient) -> bool:
	if not _validate_patient(user, patient):
		return false
	
	match device_type:
		DeviceType.AUTO_CPR:
			return await _attach_auto_cpr(user, patient)
		DeviceType.PORTABLE_DIALYSIS:
			return await _attach_dialysis(user, patient)
		DeviceType.BODY_SCANNER:
			return await _perform_body_scan(user, patient)
		DeviceType.DEFIBRILLATOR:
			return _use_defibrillator(user, patient)
		DeviceType.SURGICAL_MEMBRANE:
			return _apply_membrane(user, patient)
	
	return false

func _attach_auto_cpr(user, patient) -> bool:
	if is_attached:
		if attached_patient == patient:
			# Detach from current patient
			_detach_device(user)
			return true
		else:
			_send_message(user, "Device is already attached to someone else!")
			return false
	
	# Check if patient needs CPR
	var health_system = _get_health_system(patient)
	if not health_system:
		return false
	
	if patient.has_method("is_dead") and not patient.is_dead():
		_send_message(user, "Patient doesn't need CPR - they're still alive!")
		return false
	
	# Check if patient is wearing suit already
	if patient.has_method("is_wearing_suit") and patient.is_wearing_suit():
		_send_message(user, "Remove their suit first!")
		return false
	
	attachment_in_progress = true
	_send_message(user, "You start fitting the autocompressor onto " + patient.entity_name + "'s chest...")
	
	await get_tree().create_timer(2.0).timeout
	
	if not _can_continue_attachment(user, patient):
		attachment_in_progress = false
		return false
	
	# Attach device
	is_attached = true
	attached_patient = patient
	cpr_active = true
	attachment_in_progress = false
	
	_send_message(user, "You attach the autocompressor to " + patient.entity_name + ".")
	emit_signal("patient_attached", self, patient)
	
	# Start CPR process
	_start_cpr_process()
	return true

func _attach_dialysis(user, patient) -> bool:
	if is_attached:
		if attached_patient == patient:
			# Detach
			_detach_device(user)
			return true
		else:
			_send_message(user, "Device is already attached to someone else!")
			return false
	
	# Check patient has arms
	var health_system = _get_health_system(patient)
	if not health_system or not health_system.has_method("has_limb"):
		return false
	
	if not health_system.has_limb("left_arm") and not health_system.has_limb("right_arm"):
		_send_message(user, patient.entity_name + " has no arms to attach the dialysis machine to!")
		return false
	
	attachment_in_progress = true
	_send_message(user, "You start setting up the dialysis machine's needle on " + patient.entity_name + "'s arm...")
	
	await get_tree().create_timer(attachment_time).timeout
	
	if not _can_continue_attachment(user, patient):
		attachment_in_progress = false
		return false
	
	# Attach device
	is_attached = true
	attached_patient = patient
	filtering_active = true
	attachment_in_progress = false
	
	_send_message(user, "You attach the dialysis machine to " + patient.entity_name + ".")
	emit_signal("patient_attached", self, patient)
	
	# Start dialysis process
	_start_dialysis_process()
	return true

func _perform_body_scan(user, patient) -> bool:
	if battery_level < 10:
		_send_message(user, "Scanner battery is too low!")
		return false
	
	_send_message(user, "You begin scanning " + patient.entity_name + "...")
	
	await get_tree().create_timer(scan_time).timeout
	
	battery_level -= 10
	
	# Get patient health data
	var health_system = _get_health_system(patient)
	if health_system:
		var scan_results = _generate_scan_results(health_system)
		_display_scan_results(user, scan_results)
		return true
	
	return false

func _use_defibrillator(user, patient) -> bool:
	if battery_level < power_consumption:
		_send_message(user, "Defibrillator battery depleted!")
		return false
	
	var health_system = _get_health_system(patient)
	if not health_system:
		return false
	
	if not patient.has_method("is_dead") or not patient.is_dead():
		_send_message(user, "Patient has a pulse - defibrillation not recommended!")
		return false
	
	_send_message(user, "CLEAR! You use the defibrillator on " + patient.entity_name + "!")
	
	battery_level -= power_consumption
	
	# Chance to revive based on how recently they died
	var revival_chance = 0.3
	if patient.has_method("get_time_since_death"):
		var time_dead = patient.get_time_since_death()
		revival_chance = max(0.1, 0.8 - (time_dead / 60.0))  # Decreases over time
	
	if randf() < revival_chance:
		if health_system.has_method("revive_patient"):
			health_system.revive_patient()
			_send_message(user, patient.entity_name + " gasps as their heart starts beating again!")
		return true
	else:
		_send_message(user, "The defibrillation attempt fails.")
		return false

func _apply_membrane(user, patient) -> bool:
	var health_system = _get_health_system(patient)
	if not health_system:
		return false
	
	# Check for open surgical sites
	if health_system.has_method("has_open_surgery"):
		if health_system.has_open_surgery():
			health_system.apply_surgical_membrane()
			_send_message(user, "You apply surgical membrane to " + patient.entity_name + "'s surgical site.")
			return true
	
	_send_message(user, "No open surgical sites to treat.")
	return false

func _start_cpr_process():
	if not cpr_active or not attached_patient:
		return
	
	set_process(true)

func _start_dialysis_process():
	if not filtering_active or not attached_patient:
		return
	
	set_process(true)

func _process(delta):
	if battery_level <= 0:
		_battery_depleted()
		return
	
	if cpr_active and attached_patient:
		_process_cpr(delta)
	
	if filtering_active and attached_patient:
		_process_dialysis(delta)

func _process_cpr(delta):
	var current_time = Time.get_time_dict_from_system()["unix"]
	
	if current_time - last_pump_time >= pump_interval:
		last_pump_time = current_time
		
		var health_system = _get_health_system(attached_patient)
		if not health_system:
			_detach_device(null)
			return
		
		# Check if patient still needs CPR
		if attached_patient.has_method("is_dead"):
			if attached_patient.is_dead() and attached_patient.has_method("is_revivable"):
				if attached_patient.is_revivable():
					# Perform CPR
					health_system.apply_cpr_effect()
					battery_level -= power_consumption * (pump_interval / 60.0)
					emit_signal("cpr_administered", self, attached_patient)
					
					# Small chance of revival
					if randf() < 0.1:
						if health_system.has_method("revive_patient"):
							health_system.revive_patient()
				else:
					# Patient can't be revived, stop CPR
					_send_message(null, "Patient cannot be revived. Autocompressor detaching.")
					_detach_device(null)
			else:
				# Patient is alive, stop CPR
				_send_message(null, "Patient has stabilized. Autocompressor detaching.")
				_detach_device(null)

func _process_dialysis(delta):
	var health_system = _get_health_system(attached_patient)
	if not health_system:
		_detach_device(null)
		return
	
	# Check distance
	if global_position.distance_to(attached_patient.global_position) > 64:
		_send_message(null, "Dialysis needle ripped out!")
		_painful_detach()
		return
	
	# Filter toxins and consume blood
	if health_system.has_method("remove_toxins"):
		var toxins_removed = health_system.remove_toxins(filter_rate * delta)
		health_system.remove_blood(blood_cost * delta)
		
		battery_level -= power_consumption * delta / 60.0
		
		# Check blood levels
		if health_system.has_method("get_blood_level"):
			if health_system.get_blood_level() < 0.6:  # Low blood warning
				if randf() < 0.05:  # 5% chance per second to beep
					_send_message(null, "Dialysis machine beeps loudly - low blood detected!")

func _detach_device(user):
	is_attached = false
	cpr_active = false
	filtering_active = false
	set_process(false)
	
	if attached_patient:
		if user:
			_send_message(user, "You detach the " + item_name + " from " + attached_patient.entity_name + ".")
		emit_signal("patient_detached", self, attached_patient)
		attached_patient = null

func _painful_detach():
	if attached_patient and device_type == DeviceType.PORTABLE_DIALYSIS:
		var health_system = _get_health_system(attached_patient)
		if health_system:
			health_system.damage_limb("left_arm", 3, "brute")  # Damage from needle ripping out
		
		_send_message(null, "The dialysis needle is painfully ripped out!")
		if attached_patient.has_method("scream"):
			attached_patient.scream()
	
	_detach_device(null)

func _battery_depleted():
	battery_level = 0
	if is_attached:
		_send_message(null, item_name + " battery depleted - automatically detaching.")
		_detach_device(null)
	
	emit_signal("battery_depleted", self)

func _validate_patient(user, patient) -> bool:
	if not patient.has_method("get_health_system"):
		_send_message(user, "Invalid target for medical device.")
		return false
	
	return true

func _can_continue_attachment(user, patient) -> bool:
	if not user or not patient:
		return false
	
	if user.global_position.distance_to(patient.global_position) > 64:
		_send_message(user, "You moved too far away!")
		return false
	
	return true

func _get_health_system(entity):
	if entity and entity.has_method("get_health_system"):
		return entity.get_health_system()
	return null

func _generate_scan_results(health_system) -> Dictionary:
	var results = {}
	
	if health_system.has_method("get_vital_signs"):
		results = health_system.get_vital_signs()
	
	# Add detailed information if this is an advanced scanner
	if detailed_scan:
		if health_system.has_method("get_detailed_health"):
			results.merge(health_system.get_detailed_health())
	
	return results

func _display_scan_results(user, results: Dictionary):
	var result_text = "=== MEDICAL SCAN RESULTS ===\n"
	
	for key in results.keys():
		result_text += key + ": " + str(results[key]) + "\n"
	
	if user.has_method("display_interface"):
		user.display_interface("medical_scan", result_text)
	else:
		_send_message(user, result_text)

func recharge_battery(charge_amount: float) -> float:
	var old_battery = battery_level
	battery_level = min(max_battery, battery_level + charge_amount)
	return battery_level - old_battery

func toggle_detailed_scan(user):
	if device_type != DeviceType.BODY_SCANNER:
		return
	
	detailed_scan = !detailed_scan
	_send_message(user, "Scanner mode: " + ("Detailed" if detailed_scan else "Basic"))

func _send_message(entity, message: String):
	if entity and entity.has_method("display_message"):
		entity.display_message(message)

func get_examine_text() -> String:
	var text = super.get_examine_text()
	
	text += "\nBattery: " + str(int(battery_level)) + "%"
	
	if is_attached and attached_patient:
		text += "\nAttached to: " + attached_patient.entity_name
		
		match device_type:
			DeviceType.AUTO_CPR:
				if cpr_active:
					text += "\nCurrently performing CPR."
			DeviceType.PORTABLE_DIALYSIS:
				if filtering_active:
					text += "\nCurrently filtering blood."
	
	match device_type:
		DeviceType.BODY_SCANNER:
			text += "\nScan mode: " + ("Detailed" if detailed_scan else "Basic")
		DeviceType.PORTABLE_DIALYSIS:
			text += "\nFilter rate: " + str(filter_rate) + " units/sec"
	
	return text

# Specialized device classes
class AdvancedCPRUnit extends AdvancedMedicalDevice:
	func _init():
		super._init()
		device_type = DeviceType.AUTO_CPR
		item_name = "Advanced Autocompressor"
		description = "A high-tech automated CPR device with enhanced effectiveness."
		effectiveness = 1.5
		pump_interval = 5.0  # Faster pumping
		max_battery = 200.0
		battery_level = max_battery
		_initialize_device()

class MilitaryDialysisMachine extends AdvancedMedicalDevice:
	func _init():
		super._init()
		device_type = DeviceType.PORTABLE_DIALYSIS
		item_name = "Military Dialysis Unit"
		description = "A ruggedized portable dialysis machine for field use."
		filter_rate = 5.0  # Faster filtering
		blood_cost = 8.0   # Less blood loss
		max_battery = 300.0
		battery_level = max_battery
		_initialize_device()

class AdvancedBodyScanner extends AdvancedMedicalDevice:
	func _init():
		super._init()
		device_type = DeviceType.BODY_SCANNER
		item_name = "Advanced Medical Scanner"
		description = "A high-resolution medical scanner with detailed analysis capabilities."
		detailed_scan = true
		scan_time = 3.0  # Faster scanning
		max_battery = 150.0
		battery_level = max_battery
		_initialize_device()

# Factory methods
static func create_auto_cpr() -> AdvancedMedicalDevice:
	var device = AdvancedMedicalDevice.new()
	device.device_type = DeviceType.AUTO_CPR
	device._initialize_device()
	return device

static func create_dialysis_machine() -> AdvancedMedicalDevice:
	var device = AdvancedMedicalDevice.new()
	device.device_type = DeviceType.PORTABLE_DIALYSIS
	device._initialize_device()
	return device

static func create_body_scanner() -> AdvancedMedicalDevice:
	var device = AdvancedMedicalDevice.new()
	device.device_type = DeviceType.BODY_SCANNER
	device._initialize_device()
	return device
