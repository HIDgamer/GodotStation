extends Item
class_name SurgeryTool

enum SurgeryType {
	RETRACTOR,
	HEMOSTAT,
	CAUTERY,
	SURGICAL_DRILL,
	SCALPEL,
	CIRCULAR_SAW,
	BONE_SETTER,
	SURGICAL_LINE,
	SYNTH_GRAFT
}

@export var surgery_type: SurgeryType = SurgeryType.SCALPEL
@export var surgery_effectiveness: float = 1.0
@export var bloodless_chance: float = 0.0  # For laser scalpels
@export var animated: bool = false  # For tools that have animation effects

var is_advanced: bool = false
var is_laser: bool = false

signal surgery_started(tool, user, patient, procedure)
signal surgery_completed(tool, user, patient, procedure, success)
signal surgery_failed(tool, user, patient, procedure, reason)

func _ready():
	super._ready()
	_initialize_surgery_tool()

func _initialize_surgery_tool():
	match surgery_type:
		SurgeryType.RETRACTOR:
			item_name = "Retractor"
			description = "Retracts tissue during surgery."
			force = 0
			w_class = 1
			
		SurgeryType.HEMOSTAT:
			item_name = "Hemostat"
			description = "Clamps blood vessels during surgery."
			force = 0
			w_class = 1
			
		SurgeryType.CAUTERY:
			item_name = "Cautery"
			description = "Cauterizes wounds to stop bleeding."
			force = 0
			w_class = 1
			animated = true
			
		SurgeryType.SURGICAL_DRILL:
			item_name = "Surgical Drill"
			description = "For drilling through bone during surgery."
			force = 0
			w_class = 1
			animated = true
			
		SurgeryType.SCALPEL:
			item_name = "Scalpel"
			description = "A precise cutting instrument for surgery."
			force = 10
			sharp = true
			w_class = 1
			
		SurgeryType.CIRCULAR_SAW:
			item_name = "Circular Saw"
			description = "For cutting through bone and thick tissue."
			force = 0
			sharp = true
			w_class = 1
			animated = true
			
		SurgeryType.BONE_SETTER:
			item_name = "Bone Setter"
			description = "For setting broken bones during surgery."
			force = 0
			w_class = 1
			
		SurgeryType.SURGICAL_LINE:
			item_name = "Surgical Line"
			description = "Military-grade surgical line for suturing wounds."
			force = 0
			w_class = 1
			
		SurgeryType.SYNTH_GRAFT:
			item_name = "Synth-Graft"
			description = "Synthetic skin grafts for burn treatment."
			force = 0
			w_class = 1

func use_on_patient(user, patient, procedure_type: String) -> bool:
	if not _validate_surgery(user, patient, procedure_type):
		return false
	
	emit_signal("surgery_started", self, user, patient, procedure_type)
	
	var success_chance = _calculate_success_chance(user, procedure_type)
	var surgery_time = _get_surgery_time(procedure_type)
	
	_send_message(user, "You begin " + procedure_type + " using " + item_name + ".")
	
	# Start surgery animation/effects
	if animated:
		_play_surgery_animation()
	
	await get_tree().create_timer(surgery_time).timeout
	
	var success = randf() < success_chance
	
	if success:
		_complete_surgery(user, patient, procedure_type)
		emit_signal("surgery_completed", self, user, patient, procedure_type, true)
		return true
	else:
		_fail_surgery(user, patient, procedure_type)
		emit_signal("surgery_failed", self, user, patient, procedure_type, "procedure_failed")
		return false

func _validate_surgery(user, patient, procedure_type: String) -> bool:
	if not patient.has_method("get_health_system"):
		_send_message(user, "Invalid surgical target.")
		return false
	
	if not _is_compatible_with_procedure(procedure_type):
		_send_message(user, item_name + " cannot be used for " + procedure_type + ".")
		return false
	
	return true

func _is_compatible_with_procedure(procedure_type: String) -> bool:
	match surgery_type:
		SurgeryType.SCALPEL:
			return procedure_type in ["incision", "amputation", "implant_removal"]
		SurgeryType.RETRACTOR:
			return procedure_type in ["organ_surgery", "implant_surgery", "brain_surgery"]
		SurgeryType.HEMOSTAT:
			return procedure_type in ["organ_surgery", "bleeding_control", "bullet_removal"]
		SurgeryType.CAUTERY:
			return procedure_type in ["incision_closure", "bleeding_control"]
		SurgeryType.SURGICAL_DRILL:
			return procedure_type in ["bone_surgery", "skull_surgery"]
		SurgeryType.CIRCULAR_SAW:
			return procedure_type in ["amputation", "bone_cutting", "autopsy"]
		SurgeryType.BONE_SETTER:
			return procedure_type in ["bone_repair", "fracture_treatment"]
		SurgeryType.SURGICAL_LINE:
			return procedure_type in ["suturing", "wound_closure"]
		SurgeryType.SYNTH_GRAFT:
			return procedure_type in ["burn_treatment", "skin_grafting"]
	
	return false

func _calculate_success_chance(user, procedure_type: String) -> float:
	var base_chance = 0.7
	
	# Skill modifiers
	if user.has_method("get_skill_level"):
		var skill_level = user.get_skill_level("medical")
		base_chance += skill_level * 0.1
	
	# Tool effectiveness
	base_chance *= surgery_effectiveness
	
	# Advanced tools bonus
	if is_advanced:
		base_chance += 0.15
	
	# Laser tools special effects
	if is_laser and procedure_type == "incision":
		if randf() < bloodless_chance:
			base_chance += 0.2  # Bloodless incisions are easier
	
	return clamp(base_chance, 0.1, 0.95)

func _get_surgery_time(procedure_type: String) -> float:
	var base_time = 5.0
	
	match procedure_type:
		"incision":
			base_time = 2.0
		"amputation":
			base_time = 8.0
		"organ_surgery":
			base_time = 10.0
		"brain_surgery":
			base_time = 15.0
		"suturing":
			base_time = 3.0
		_:
			base_time = 5.0
	
	# Advanced tools work faster
	if is_advanced:
		base_time *= 0.8
	
	return base_time

func _complete_surgery(user, patient, procedure_type: String):
	match procedure_type:
		"incision":
			_send_message(user, "You make a clean incision.")
			if is_laser and randf() < bloodless_chance:
				_send_message(user, "The laser scalpel cauterizes as it cuts, preventing bleeding.")
		"suturing":
			_send_message(user, "You successfully suture the wound closed.")
			var health_system = patient.get_health_system()
			if health_system and health_system.has_method("heal_damage"):
				health_system.heal_damage(5, 5)
		"bone_repair":
			_send_message(user, "You successfully set the broken bone.")
		_:
			_send_message(user, "You complete the " + procedure_type + " successfully.")

func _fail_surgery(user, patient, procedure_type: String):
	_send_message(user, "The " + procedure_type + " fails!")
	
	# Apply damage on failure
	var health_system = patient.get_health_system()
	if health_system and health_system.has_method("take_damage"):
		health_system.take_damage(5, "brute")

func _play_surgery_animation():
	if animated:
		# Play tool-specific animation/sound effects
		pass

func _send_message(entity, message: String):
	if entity and entity.has_method("display_message"):
		entity.display_message(message)

# Specialized surgery tool classes
class LaserScalpel extends SurgeryTool:
	func _init():
		super._init()
		surgery_type = SurgeryType.SCALPEL
		is_laser = true
		is_advanced = true
		bloodless_chance = 0.6
		surgery_effectiveness = 1.2
		item_name = "Laser Scalpel"
		description = "An advanced scalpel that uses directed laser energy."

class AdvancedScalpel extends SurgeryTool:
	func _init():
		super._init()
		surgery_type = SurgeryType.SCALPEL
		is_advanced = true
		bloodless_chance = 1.0
		surgery_effectiveness = 1.5
		item_name = "Advanced Laser Scalpel"
		description = "The pinnacle of precision cutting technology."

class PICTSystem extends SurgeryTool:
	func _init():
		super._init()
		surgery_type = SurgeryType.SCALPEL
		is_advanced = true
		surgery_effectiveness = 1.1
		item_name = "PICT System"
		description = "Precision Incision and Cauterization Tool with vibrating blade and laser cautery."

# Factory methods
static func create_scalpel() -> SurgeryTool:
	var tool = SurgeryTool.new()
	tool.surgery_type = SurgeryType.SCALPEL
	tool._initialize_surgery_tool()
	return tool

static func create_laser_scalpel() -> LaserScalpel:
	return LaserScalpel.new()

static func create_retractor() -> SurgeryTool:
	var tool = SurgeryTool.new()
	tool.surgery_type = SurgeryType.RETRACTOR
	tool._initialize_surgery_tool()
	return tool

static func create_hemostat() -> SurgeryTool:
	var tool = SurgeryTool.new()
	tool.surgery_type = SurgeryType.HEMOSTAT
	tool._initialize_surgery_tool()
	return tool
