extends Control
class_name HealthAnalyzerUI

signal ui_closed

@onready var main_panel = $MainPanel
@onready var title_label = $MainPanel/VBoxContainer/Header/VBoxContainer/TitleLabel
@onready var patient_name_label = $MainPanel/VBoxContainer/Header/VBoxContainer/PatientNameLabel
@onready var health_label: Label = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/VitalSignsContainer/HealthLabel
@onready var pulse_label: Label = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/VitalSignsContainer/PulseLabel
@onready var temp_label: Label = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/VitalSignsContainer/TempLabel
@onready var bp_label: Label = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/VitalSignsContainer/BPLabel
@onready var damage_header: Label = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/DamageContainer/DamageHeader
@onready var brute_label: Label = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/DamageContainer/BruteContainer/BruteLabel
@onready var burn_label: Label = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/DamageContainer/BurnContainer/BurnLabel
@onready var toxin_label: Label = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/DamageContainer/ToxinContainer/ToxinLabel
@onready var oxygen_label: Label = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/DamageContainer/OxygenContainer/OxygenLabel
@onready var blood_header: Label = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/BloodContainer/BloodHeader
@onready var blood_volume_label: Label = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/BloodContainer/BloodVolumeLabel
@onready var blood_type_label: Label = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/BloodContainer/BloodTypeLabel
@onready var bleeding_label: Label = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/BloodContainer/BleedingLabel
@onready var limbs_header: Label = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/LimbsContainer/LimbsHeader
@onready var chemicals_header: Label = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/ChemicalsContainer/ChemicalsHeader
@onready var advice_header: Label = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/AdviceContainer/AdviceHeader

@onready var close_button = $MainPanel/VBoxContainer/Header/CloseButton

@onready var vital_signs_container = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/VitalSignsContainer
@onready var damage_container = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/DamageContainer
@onready var blood_container = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/BloodContainer
@onready var limbs_container = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/LimbsContainer
@onready var chemicals_container = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/ChemicalsContainer
@onready var advice_container = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/AdviceContainer

@onready var health_bar = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/VitalSignsContainer/HealthBar
@onready var brute_bar = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/DamageContainer/BruteContainer/BruteBar
@onready var burn_bar = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/DamageContainer/BurnContainer/BurnBar
@onready var toxin_bar = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/DamageContainer/ToxinContainer/ToxinBar
@onready var oxygen_bar = $MainPanel/VBoxContainer/ScrollContainer/ContentContainer/DamageContainer/OxygenContainer/OxygenBar

var scan_data: Dictionary
var target_entity = null
var is_dragging: bool = false
var drag_offset: Vector2

var is_resizing: bool = false
var resize_edge: String = ""
var resize_threshold: float = 10.0
var min_size: Vector2 = Vector2(300, 400)
var original_mouse_pos: Vector2
var original_panel_pos: Vector2
var original_panel_size: Vector2

func _ready():
	close_button.pressed.connect(_on_close_pressed)
	main_panel.gui_input.connect(_on_panel_gui_input)
	setup_ui_theme()
	
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup_ui_theme():
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.1, 0.95)
	panel_style.border_color = Color(0.3, 0.6, 0.8, 1.0)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.corner_radius_top_left = 5
	panel_style.corner_radius_top_right = 5
	panel_style.corner_radius_bottom_left = 5
	panel_style.corner_radius_bottom_right = 5
	
	main_panel.add_theme_stylebox_override("panel", panel_style)

func show_scan_results(data: Dictionary):
	scan_data = data
	populate_ui(data)
	show()

func populate_ui(data: Dictionary):
	patient_name_label.text = data.patient_name
	
	if data.dead:
		patient_name_label.modulate = Color.RED
		title_label.text = "Health Analyzer - DECEASED"
	else:
		patient_name_label.modulate = Color.WHITE
		title_label.text = "Health Analyzer"
	
	populate_vital_signs(data.vital_signs, data.health, data.max_health)
	populate_damage_data(data.damage)
	populate_blood_data(data.blood)
	populate_pain_data(data.get("pain", {}))
	populate_limb_data(data.limbs, data.detail_level)
	populate_chemical_data(data.chemicals, data.detail_level)
	populate_advice_data(data.advice)

func populate_vital_signs(vitals: Dictionary, health: float, max_health: float):
	var health_percent = (health / max_health) * 100.0
	health_bar.value = health_percent
	
	if health_percent > 75:
		health_bar.modulate = Color.GREEN
	elif health_percent > 50:
		health_bar.modulate = Color.YELLOW
	elif health_percent > 25:
		health_bar.modulate = Color.ORANGE
	else:
		health_bar.modulate = Color.RED
	
	health_label.text = "Health: %.1f/%.1f (%.1f%%)" % [health, max_health, health_percent]
	pulse_label.text = "Pulse: %d BPM" % vitals.pulse
	temp_label.text = "Temperature: %.1f°C (%.1f°F)" % [vitals.temperature, vitals.temperature * 1.8 + 32]
	bp_label.text = "Blood Pressure: %s" % vitals.blood_pressure
	
	if vitals.pulse == 0:
		pulse_label.modulate = Color.RED
		pulse_label.text += " - NO PULSE"
	elif vitals.pulse < 60 or vitals.pulse > 100:
		pulse_label.modulate = Color.ORANGE
	else:
		pulse_label.modulate = Color.WHITE
	
	if vitals.has("consciousness"):
		add_consciousness_label(vitals.consciousness)

func add_consciousness_label(consciousness: float):
	var consciousness_label = Label.new()
	consciousness_label.name = "ConsciousnessLabel"
	consciousness_label.text = "Consciousness: %.1f%%" % consciousness
	
	if consciousness < 30:
		consciousness_label.modulate = Color.RED
	elif consciousness < 70:
		consciousness_label.modulate = Color.ORANGE
	else:
		consciousness_label.modulate = Color.WHITE
	
	vital_signs_container.add_child(consciousness_label)

func populate_damage_data(damage: Dictionary):
	brute_bar.value = min(damage.brute, 100)
	burn_bar.value = min(damage.burn, 100)
	toxin_bar.value = min(damage.toxin, 100)
	oxygen_bar.value = min(damage.oxygen, 100)
	
	brute_bar.modulate = Color.RED if damage.brute > 50 else Color.WHITE
	burn_bar.modulate = Color.ORANGE if damage.burn > 50 else Color.WHITE
	toxin_bar.modulate = Color.GREEN if damage.toxin > 50 else Color.WHITE
	oxygen_bar.modulate = Color.BLUE if damage.oxygen > 50 else Color.WHITE
	
	brute_label.text = "Brute: %.1f" % damage.brute
	burn_label.text = "Burn: %.1f" % damage.burn
	toxin_label.text = "Toxin: %.1f" % damage.toxin
	oxygen_label.text = "Oxygen: %.1f" % damage.oxygen
	
	if damage.has("brain") and damage.brain > 0:
		add_damage_label("Brain", damage.brain, Color.PURPLE)
	if damage.has("clone") and damage.clone > 0:
		add_damage_label("Cellular", damage.clone, Color.CYAN)
	if damage.has("stamina") and damage.stamina > 0:
		add_damage_label("Stamina", damage.stamina, Color.YELLOW)

func add_damage_label(damage_type: String, amount: float, color: Color):
	var damage_label = Label.new()
	damage_label.text = "%s: %.1f" % [damage_type, amount]
	damage_label.modulate = color if amount > 20 else Color.WHITE
	damage_container.add_child(damage_label)

func populate_pain_data(pain_data: Dictionary):
	if pain_data.is_empty():
		return
	
	var pain_container = VBoxContainer.new()
	pain_container.name = "PainContainer"
	
	var pain_header = Label.new()
	pain_header.text = "PAIN ANALYSIS"
	pain_header.add_theme_font_size_override("font_size", 14)
	pain_container.add_child(pain_header)
	
	var pain_level_label = Label.new()
	pain_level_label.text = "Pain Level: %.1f (%s)" % [pain_data.level, pain_data.status]
	
	if pain_data.level > 60:
		pain_level_label.modulate = Color.RED
	elif pain_data.level > 25:
		pain_level_label.modulate = Color.ORANGE
	else:
		pain_level_label.modulate = Color.WHITE
	
	pain_container.add_child(pain_level_label)
	
	if pain_data.has("shock"):
		var shock_label = Label.new()
		shock_label.text = "Shock Level: %.1f" % pain_data.shock
		shock_label.modulate = Color.RED if pain_data.shock > 50 else Color.WHITE
		pain_container.add_child(shock_label)
	
	if pain_data.has("pain_effects") and pain_data.pain_effects.size() > 0:
		var effects_label = Label.new()
		effects_label.text = "Effects: " + ", ".join(pain_data.pain_effects)
		effects_label.modulate = Color.ORANGE
		pain_container.add_child(effects_label)
	
	damage_container.add_child(pain_container)

func populate_blood_data(blood: Dictionary):
	var blood_percent = (blood.volume / blood.max_volume) * 100.0
	blood_volume_label.text = "Blood Volume: %d/%d mL (%.1f%%)" % [blood.volume, blood.max_volume, blood_percent]
	blood_type_label.text = "Blood Type: %s" % blood.type
	
	if blood_percent < 60:
		blood_volume_label.modulate = Color.RED
	elif blood_percent < 80:
		blood_volume_label.modulate = Color.ORANGE
	else:
		blood_volume_label.modulate = Color.WHITE
	
	if blood.bleeding:
		bleeding_label.text = "⚠ BLEEDING (Rate: %.1f mL/min)" % blood.bleeding_rate
		bleeding_label.modulate = Color.RED
		bleeding_label.visible = true
	else:
		bleeding_label.visible = false

func populate_limb_data(limbs: Array, detail_level: String):
	for child in limbs_container.get_children():
		if child.name.begins_with("LimbEntry"):
			child.queue_free()
	
	for i in range(limbs.size()):
		var limb = limbs[i]
		var limb_entry = create_limb_entry(limb, detail_level)
		limb_entry.name = "LimbEntry%d" % i
		limbs_container.add_child(limb_entry)

func create_limb_entry(limb: Dictionary, detail_level: String) -> Control:
	var entry = VBoxContainer.new()
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var main_info = HBoxContainer.new()
	
	var name_label = Label.new()
	name_label.text = limb.name
	name_label.custom_minimum_size.x = 100
	main_info.add_child(name_label)
	
	var status_label = Label.new()
	var status_text = ""
	var status_color = Color.WHITE
	
	if not limb.attached:
		status_text = "MISSING"
		status_color = Color.RED
	elif limb.fractured:
		if limb.splinted:
			status_text = "FRACTURED (Splinted)"
			status_color = Color.ORANGE
		else:
			status_text = "FRACTURED (Severity: %d)" % limb.fracture_severity
			status_color = Color.RED
	elif limb.brute > 20 or limb.burn > 20:
		status_text = "Damaged (B:%.0f/Bu:%.0f)" % [limb.brute, limb.burn]
		status_color = Color.YELLOW
	else:
		status_text = "Healthy"
		status_color = Color.GREEN
	
	if limb.bleeding:
		status_text += " BLEEDING"
		status_color = Color.RED
	
	if limb.bandaged:
		status_text += " [Bandaged]"
	
	if limb.infected:
		status_text += " [Infected]"
		status_color = Color.PURPLE
	
	status_label.text = status_text
	status_label.modulate = status_color
	main_info.add_child(status_label)
	
	entry.add_child(main_info)
	
	if detail_level == "medical" and limb.has("wounds") and limb.wounds > 0:
		var wounds_label = Label.new()
		wounds_label.text = "    Wounds: %d detected" % limb.wounds
		wounds_label.modulate = Color.ORANGE
		entry.add_child(wounds_label)
	
	return entry

func populate_chemical_data(chemicals: Dictionary, detail_level: String):
	for child in chemicals_container.get_children():
		if child.name.begins_with("ChemEntry") or child.name == "NoChemicals":
			child.queue_free()
	
	if not chemicals.has_chemicals:
		var no_chems_label = Label.new()
		no_chems_label.text = "No chemicals detected."
		no_chems_label.name = "NoChemicals"
		chemicals_container.add_child(no_chems_label)
		return
	
	var volume_label = Label.new()
	volume_label.text = "Total Volume: %.1f units" % chemicals.total_volume
	volume_label.modulate = Color.CYAN
	chemicals_container.add_child(volume_label)
	
	if chemicals.dangerous_detected:
		var warning_label = Label.new()
		warning_label.text = "⚠ DANGEROUS CHEMICALS DETECTED"
		warning_label.modulate = Color.RED
		chemicals_container.add_child(warning_label)
	
	for i in range(chemicals.reagents.size()):
		var reagent = chemicals.reagents[i]
		var chem_entry = create_chemical_entry(reagent, detail_level)
		chem_entry.name = "ChemEntry%d" % i
		chemicals_container.add_child(chem_entry)

func create_chemical_entry(reagent: Dictionary, detail_level: String) -> Control:
	var entry = VBoxContainer.new()
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var main_info = HBoxContainer.new()
	
	var name_label = Label.new()
	name_label.text = reagent.name
	name_label.custom_minimum_size.x = 120
	main_info.add_child(name_label)
	
	var amount_label = Label.new()
	amount_label.text = "%.1f units" % reagent.amount
	main_info.add_child(amount_label)
	
	var status_indicators = []
	
	if reagent.overdose:
		status_indicators.append("OVERDOSE")
		main_info.modulate = Color.RED
	elif reagent.dangerous:
		status_indicators.append("TOXIC")
		main_info.modulate = Color.ORANGE
	elif reagent.beneficial:
		status_indicators.append("BENEFICIAL")
		main_info.modulate = Color.GREEN
	
	if status_indicators.size() > 0:
		var status_label = Label.new()
		status_label.text = " [" + ", ".join(status_indicators) + "]"
		main_info.add_child(status_label)
	
	entry.add_child(main_info)
	
	if detail_level == "medical":
		if reagent.has("overdose_threshold") and reagent.overdose_threshold > 0:
			var od_label = Label.new()
			od_label.text = "    OD Threshold: %.1f units" % reagent.overdose_threshold
			od_label.modulate = Color.ORANGE
			entry.add_child(od_label)
		
		if reagent.has("effects") and reagent.effects.size() > 0:
			var effects_label = Label.new()
			effects_label.text = "    Effects: " + ", ".join(reagent.effects)
			effects_label.modulate = Color.CYAN
			entry.add_child(effects_label)
	
	return entry

func populate_advice_data(advice: Array):
	for child in advice_container.get_children():
		if child.name.begins_with("AdviceEntry") or child.name == "NoAdvice":
			child.queue_free()
	
	if advice.is_empty():
		var no_advice_label = Label.new()
		no_advice_label.text = "No specific medical recommendations."
		no_advice_label.name = "NoAdvice"
		advice_container.add_child(no_advice_label)
		return
	
	for i in range(advice.size()):
		var advice_item = advice[i]
		var advice_entry = create_advice_entry(advice_item)
		advice_entry.name = "AdviceEntry%d" % i
		advice_container.add_child(advice_entry)

func create_advice_entry(advice_item: Dictionary) -> Control:
	var entry = HBoxContainer.new()
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var icon_label = Label.new()
	icon_label.text = get_icon_text(advice_item.icon)
	icon_label.custom_minimum_size.x = 30
	icon_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	entry.add_child(icon_label)
	
	var text_label = Label.new()
	text_label.text = advice_item.text
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.clip_contents = false
	
	match advice_item.color:
		"red": text_label.modulate = Color.RED
		"orange": text_label.modulate = Color.ORANGE
		"yellow": text_label.modulate = Color.YELLOW
		"green": text_label.modulate = Color.GREEN
		"blue": text_label.modulate = Color.CYAN
		"purple": text_label.modulate = Color.PURPLE
		_: text_label.modulate = Color.WHITE
	
	entry.add_child(text_label)
	
	return entry

func get_icon_text(icon_name: String) -> String:
	match icon_name:
		"warning": return "⚠"
		"bandage": return "🩹"
		"fire": return "🔥"
		"poison": return "☠"
		"oxygen": return "💨"
		"blood": return "🩸"
		"bleeding": return "🔴"
		"fracture": return "🦴"
		"pain": return "😣"
		_: return "•"

func _on_close_pressed():
	hide()
	ui_closed.emit()

func get_resize_edge(mouse_pos: Vector2) -> String:
	var panel_rect = main_panel.get_rect()
	var panel_pos = main_panel.position
	var panel_size = main_panel.size
	
	var left = abs(mouse_pos.x - panel_pos.x) < resize_threshold
	var right = abs(mouse_pos.x - (panel_pos.x + panel_size.x)) < resize_threshold
	var top = abs(mouse_pos.y - panel_pos.y) < resize_threshold
	var bottom = abs(mouse_pos.y - (panel_pos.y + panel_size.y)) < resize_threshold
	
	if top and left: return "top_left"
	if top and right: return "top_right"
	if bottom and left: return "bottom_left"
	if bottom and right: return "bottom_right"
	
	if left: return "left"
	if right: return "right"
	if top: return "top"
	if bottom: return "bottom"
	
	return ""

func update_cursor(edge: String):
	match edge:
		"left", "right":
			mouse_default_cursor_shape = Control.CURSOR_HSIZE
		"top", "bottom":
			mouse_default_cursor_shape = Control.CURSOR_VSIZE
		"top_left", "bottom_right":
			mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
		"top_right", "bottom_left":
			mouse_default_cursor_shape = Control.CURSOR_BDIAGSIZE
		_:
			mouse_default_cursor_shape = Control.CURSOR_ARROW

func _on_panel_gui_input(event):
	if event is InputEventMouseMotion:
		if not is_dragging and not is_resizing:
			var edge = get_resize_edge(event.global_position)
			update_cursor(edge)
		
		if is_resizing:
			var delta = event.global_position - original_mouse_pos
			var new_pos = original_panel_pos
			var new_size = original_panel_size
			
			match resize_edge:
				"left":
					new_pos.x += delta.x
					new_size.x -= delta.x
				"right":
					new_size.x += delta.x
				"top":
					new_pos.y += delta.y
					new_size.y -= delta.y
				"bottom":
					new_size.y += delta.y
				"top_left":
					new_pos.x += delta.x
					new_pos.y += delta.y
					new_size.x -= delta.x
					new_size.y -= delta.y
				"top_right":
					new_pos.y += delta.y
					new_size.x += delta.x
					new_size.y -= delta.y
				"bottom_left":
					new_pos.x += delta.x
					new_size.x -= delta.x
					new_size.y += delta.y
				"bottom_right":
					new_size.x += delta.x
					new_size.y += delta.y
			
			if new_size.x >= min_size.x and new_size.y >= min_size.y:
				main_panel.position = new_pos
				main_panel.size = new_size
				
		elif is_dragging:
			var new_position = event.global_position + drag_offset
			
			var viewport = get_viewport()
			if viewport:
				var viewport_size = viewport.get_visible_rect().size
				var panel_size = main_panel.size
				
				new_position.x = clamp(new_position.x, 0, viewport_size.x - panel_size.x)
				new_position.y = clamp(new_position.y, 0, viewport_size.y - panel_size.y)
			
			main_panel.position = new_position
	
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var edge = get_resize_edge(event.global_position)
				
				if edge != "":
					is_resizing = true
					resize_edge = edge
					original_mouse_pos = event.global_position
					original_panel_pos = main_panel.position
					original_panel_size = main_panel.size
				else:
					is_dragging = true
					drag_offset = main_panel.global_position - event.global_position
			else:
				is_dragging = false
				is_resizing = false
				resize_edge = ""
				mouse_default_cursor_shape = Control.CURSOR_ARROW
