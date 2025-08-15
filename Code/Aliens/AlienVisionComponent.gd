extends Node
class_name AlienVisionComponent

const LIFE_SENSE_RANGE: float = 20.0
const HEAT_VISION_RANGE: float = 15.0
const MOTION_DETECTION_RANGE: float = 25.0

enum VisionMode {
	NORMAL,
	HEAT_VISION,
	LIFE_SENSE,
	MOTION_DETECTION
}

signal life_form_detected(entity: Node)
signal life_form_lost(entity: Node)
signal movement_detected(position: Vector2i, entity: Node)
signal heat_signature_found(position: Vector2i, intensity: float)

var controller: Node = null
var world: Node = null
var tile_occupancy_system: Node = null

var current_vision_mode: VisionMode = VisionMode.NORMAL
var detected_life_forms: Dictionary = {}
var tracked_movements: Dictionary = {}
var heat_signatures: Dictionary = {}

var scan_timer: float = 0.0
var scan_interval: float = 2.0
var vision_range_modifier: float = 1.0

func initialize(init_data: Dictionary):
	controller = init_data.get("controller")
	world = init_data.get("world")
	tile_occupancy_system = init_data.get("tile_occupancy_system")

func _process(delta: float):
	scan_timer += delta
	
	if scan_timer >= scan_interval:
		_perform_vision_scan()
		scan_timer = 0.0
		scan_interval = randf_range(1.5, 2.5)

func scan_for_life_forms() -> Array:
	var life_forms = []
	
	if not controller or not tile_occupancy_system:
		return life_forms
	
	var my_pos = _get_my_position()
	var z_level = controller.current_z_level
	var range_limit = LIFE_SENSE_RANGE * vision_range_modifier
	
	for x in range(my_pos.x - int(range_limit), my_pos.x + int(range_limit) + 1):
		for y in range(my_pos.y - int(range_limit), my_pos.y + int(range_limit) + 1):
			var check_pos = Vector2i(x, y)
			var distance = my_pos.distance_to(Vector2(check_pos))
			
			if distance > range_limit:
				continue
			
			var entities = tile_occupancy_system.get_entities_at(check_pos, z_level)
			for entity in entities:
				if _is_life_form(entity) and entity != controller:
					life_forms.append(entity)
	
	return life_forms

func get_nearest_life_form() -> Node:
	var life_forms = scan_for_life_forms()
	if life_forms.size() == 0:
		return null
	
	var my_pos = _get_my_position()
	var nearest_entity = null
	var nearest_distance = INF
	
	for entity in life_forms:
		var entity_pos = _get_entity_position(entity)
		var distance = my_pos.distance_to(Vector2(entity_pos))
		
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_entity = entity
	
	return nearest_entity

func detect_heat_signatures() -> Array:
	var signatures = []
	
	if not controller:
		return signatures
	
	var my_pos = _get_my_position()
	var range_limit = HEAT_VISION_RANGE * vision_range_modifier
	
	for x in range(my_pos.x - int(range_limit), my_pos.x + int(range_limit) + 1):
		for y in range(my_pos.y - int(range_limit), my_pos.y + int(range_limit) + 1):
			var check_pos = Vector2i(x, y)
			var distance = my_pos.distance_to(Vector2(check_pos))
			
			if distance > range_limit:
				continue
			
			var heat_intensity = _calculate_heat_at_position(check_pos)
			if heat_intensity > 0.3:
				signatures.append({
					"position": check_pos,
					"intensity": heat_intensity,
					"distance": distance
				})
	
	signatures.sort_custom(func(a, b): return a.intensity > b.intensity)
	return signatures

func track_movement_in_area() -> Array:
	var movements = []
	
	if not controller:
		return movements
	
	var my_pos = _get_my_position()
	var range_limit = MOTION_DETECTION_RANGE * vision_range_modifier
	
	for entity_id in tracked_movements.keys():
		var movement_data = tracked_movements[entity_id]
		var current_pos = movement_data.current_position
		var last_pos = movement_data.last_position
		
		if current_pos != last_pos:
			var distance = my_pos.distance_to(Vector2(current_pos))
			if distance <= range_limit:
				movements.append({
					"entity_id": entity_id,
					"from": last_pos,
					"to": current_pos,
					"distance": distance
				})
	
	return movements

func set_vision_mode(mode: VisionMode):
	current_vision_mode = mode
	
	match mode:
		VisionMode.HEAT_VISION:
			scan_interval = 1.0
			vision_range_modifier = 0.8
		VisionMode.LIFE_SENSE:
			scan_interval = 1.5
			vision_range_modifier = 1.2
		VisionMode.MOTION_DETECTION:
			scan_interval = 0.5
			vision_range_modifier = 1.5
		_:
			scan_interval = 2.0
			vision_range_modifier = 1.0

func enhance_vision_range(multiplier: float):
	vision_range_modifier = multiplier

func can_see_through_walls() -> bool:
	return current_vision_mode == VisionMode.LIFE_SENSE

func _perform_vision_scan():
	match current_vision_mode:
		VisionMode.HEAT_VISION:
			_scan_heat_signatures()
		VisionMode.LIFE_SENSE:
			_scan_life_forms()
		VisionMode.MOTION_DETECTION:
			_scan_for_movement()
		_:
			_scan_normal_vision()

func _scan_life_forms():
	var current_life_forms = scan_for_life_forms()
	var previously_detected = detected_life_forms.keys()
	
	for entity in current_life_forms:
		var entity_id = _get_entity_id(entity)
		
		if entity_id not in detected_life_forms:
			detected_life_forms[entity_id] = {
				"entity": entity,
				"first_detected": Time.get_ticks_msec() / 1000.0,
				"last_seen": Time.get_ticks_msec() / 1000.0
			}
			emit_signal("life_form_detected", entity)
		else:
			detected_life_forms[entity_id].last_seen = Time.get_ticks_msec() / 1000.0
	
	for entity_id in previously_detected:
		var entity_data = detected_life_forms[entity_id]
		var entity = entity_data.entity
		
		if entity not in current_life_forms:
			emit_signal("life_form_lost", entity)
			detected_life_forms.erase(entity_id)

func _scan_heat_signatures():
	var signatures = detect_heat_signatures()
	
	for signature in signatures:
		var pos = signature.position
		var intensity = signature.intensity
		
		emit_signal("heat_signature_found", pos, intensity)

func _scan_for_movement():
	_update_movement_tracking()
	var movements = track_movement_in_area()
	
	for movement in movements:
		var entity = _find_entity_by_id(movement.entity_id)
		if entity:
			emit_signal("movement_detected", movement.to, entity)

func _scan_normal_vision():
	var visible_entities = _get_visible_entities()
	
	for entity in visible_entities:
		if _is_life_form(entity):
			var entity_id = _get_entity_id(entity)
			
			if entity_id not in detected_life_forms:
				detected_life_forms[entity_id] = {
					"entity": entity,
					"first_detected": Time.get_ticks_msec() / 1000.0,
					"last_seen": Time.get_ticks_msec() / 1000.0
				}
				emit_signal("life_form_detected", entity)

func _update_movement_tracking():
	if not tile_occupancy_system:
		return
	
	var my_pos = _get_my_position()
	var z_level = controller.current_z_level if controller else 0
	var range_limit = MOTION_DETECTION_RANGE * vision_range_modifier
	
	for x in range(my_pos.x - int(range_limit), my_pos.x + int(range_limit) + 1):
		for y in range(my_pos.y - int(range_limit), my_pos.y + int(range_limit) + 1):
			var check_pos = Vector2i(x, y)
			var entities = tile_occupancy_system.get_entities_at(check_pos, z_level)
			
			for entity in entities:
				if entity == controller:
					continue
				
				var entity_id = _get_entity_id(entity)
				var entity_pos = _get_entity_position(entity)
				
				if entity_id in tracked_movements:
					tracked_movements[entity_id].last_position = tracked_movements[entity_id].current_position
					tracked_movements[entity_id].current_position = entity_pos
				else:
					tracked_movements[entity_id] = {
						"current_position": entity_pos,
						"last_position": entity_pos,
						"entity": entity
					}

func _get_visible_entities() -> Array:
	var visible = []
	
	if not controller or not tile_occupancy_system:
		return visible
	
	var my_pos = _get_my_position()
	var z_level = controller.current_z_level
	var vision_range = 10.0 * vision_range_modifier
	
	for x in range(my_pos.x - int(vision_range), my_pos.x + int(vision_range) + 1):
		for y in range(my_pos.y - int(vision_range), my_pos.y + int(vision_range) + 1):
			var check_pos = Vector2i(x, y)
			var distance = my_pos.distance_to(Vector2(check_pos))
			
			if distance > vision_range:
				continue
			
			if _has_line_of_sight(my_pos, check_pos):
				var entities = tile_occupancy_system.get_entities_at(check_pos, z_level)
				for entity in entities:
					if entity != controller:
						visible.append(entity)
	
	return visible

func _calculate_heat_at_position(pos: Vector2i) -> float:
	if not tile_occupancy_system:
		return 0.0
	
	var heat_value = 0.0
	var z_level = controller.current_z_level if controller else 0
	var entities = tile_occupancy_system.get_entities_at(pos, z_level)
	
	for entity in entities:
		if _is_life_form(entity):
			heat_value += 0.8
		elif _is_machinery(entity):
			heat_value += 0.4
		elif _is_heat_source(entity):
			heat_value += 0.6
	
	if world and world.has_method("get_tile_data"):
		var tile_data = world.get_tile_data(pos, z_level)
		if tile_data:
			if "temperature" in tile_data and tile_data.temperature > 300:
				heat_value += (tile_data.temperature - 300) / 100.0
			
			if "on_fire" in tile_data and tile_data.on_fire:
				heat_value += 1.0
	
	return clamp(heat_value, 0.0, 1.0)

func _has_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	if can_see_through_walls():
		return true
	
	if not world:
		return true
	
	var line_points = _bresenham_line(from, to)
	var z_level = controller.current_z_level if controller else 0
	
	for point in line_points:
		if point == from:
			continue
		
		if world.has_method("is_wall_at") and world.is_wall_at(point, z_level):
			return false
	
	return true

func _bresenham_line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var x0 = from.x
	var y0 = from.y
	var x1 = to.x
	var y1 = to.y
	
	var dx = abs(x1 - x0)
	var dy = abs(y1 - y0)
	var sx = 1 if x0 < x1 else -1
	var sy = 1 if y0 < y1 else -1
	var err = dx - dy
	
	while true:
		points.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		
		var e2 = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy
	
	return points

func _is_life_form(entity: Node) -> bool:
	if not entity or not is_instance_valid(entity):
		return false
	
	return entity.is_in_group("players") or entity.is_in_group("humans") or entity.is_in_group("aliens")

func _is_machinery(entity: Node) -> bool:
	if not entity:
		return false
	
	return entity.is_in_group("machinery") or "machine" in entity.name.to_lower()

func _is_heat_source(entity: Node) -> bool:
	if not entity:
		return false
	
	if "heat_source" in entity:
		return entity.heat_source
	
	if "temperature" in entity:
		return entity.temperature > 300
	
	return "fire" in entity.name.to_lower() or "heater" in entity.name.to_lower()

func _get_my_position() -> Vector2i:
	if controller and controller.has_method("get_current_tile_position"):
		return controller.get_current_tile_position()
	elif controller and "current_tile_position" in controller:
		return controller.current_tile_position
	return Vector2i.ZERO

func _get_entity_position(entity: Node) -> Vector2i:
	if not entity:
		return Vector2i.ZERO
	
	if "current_tile_position" in entity:
		return entity.current_tile_position
	elif entity.has_method("get_current_tile_position"):
		return entity.get_current_tile_position()
	
	return Vector2i.ZERO

func _get_entity_id(entity: Node) -> String:
	if not entity:
		return ""
	
	if "entity_id" in entity:
		return entity.entity_id
	
	return "entity_" + str(entity.get_instance_id())

func _find_entity_by_id(entity_id: String) -> Node:
	for tracked_id in tracked_movements.keys():
		if tracked_id == entity_id:
			return tracked_movements[tracked_id].entity
	
	return null

func cleanup():
	detected_life_forms.clear()
	tracked_movements.clear()
	heat_signatures.clear()
