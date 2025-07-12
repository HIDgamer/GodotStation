extends Node
class_name MapValidator

var editor_ref = null
var validation_report = ""
var validation_issues = []

func _init(p_editor_ref = null):
	editor_ref = p_editor_ref

# Validate map and return number of issues found
func validate_map() -> int:
	validation_issues.clear()
	validation_report = ""
	
	# Check basic map properties
	_validate_map_dimensions()
	
	# Check for disconnected areas
	_validate_connectivity()
	
	# Check for atmospheric breaches
	_validate_atmosphere()
	
	# Check for missing or invalid tiles
	_validate_tiles()
	
	# Check for objects with issues
	_validate_objects()
	
	# Check for lighting issues
	_validate_lighting()
	
	# Generate final report
	_generate_report()
	
	return validation_issues.size()

# Validate map dimensions
func _validate_map_dimensions():
	if not editor_ref:
		return
	
	# Check if map has reasonable dimensions
	if editor_ref.map_width < 10 or editor_ref.map_height < 10:
		validation_issues.append({
			"type": "warning",
			"message": "Map dimensions are very small (width: " + str(editor_ref.map_width) + ", height: " + str(editor_ref.map_height) + ")"
		})
	
	if editor_ref.map_width > 500 or editor_ref.map_height > 500:
		validation_issues.append({
			"type": "warning",
			"message": "Map dimensions are very large, which may cause performance issues (width: " + str(editor_ref.map_width) + ", height: " + str(editor_ref.map_height) + ")"
		})
	
	# Check if map has areas with no floor tiles
	var floor_tiles_count = editor_ref.floor_tilemap.get_used_cells(0).size()
	if floor_tiles_count == 0:
		validation_issues.append({
			"type": "error",
			"message": "Map has no floor tiles"
		})

# Validate map connectivity
func _validate_connectivity():
	if not editor_ref or not editor_ref.floor_tilemap:
		return
	
	var used_floor_cells = editor_ref.floor_tilemap.get_used_cells(0)
	if used_floor_cells.size() == 0:
		return  # No floor tiles to check
	
	# Find disconnected areas using flood fill
	var checked_cells = {}
	var regions = []
	
	for cell in used_floor_cells:
		if cell in checked_cells:
			continue
		
		# Found a new potential region, flood fill from here
		var region = []
		var to_check = [cell]
		
		while to_check.size() > 0:
			var current = to_check.pop_front()
			
			if current in checked_cells:
				continue
			
			checked_cells[current] = true
			region.append(current)
			
			# Check neighbors (4-way connectivity)
			var neighbors = [
				Vector2i(current.x + 1, current.y),
				Vector2i(current.x - 1, current.y),
				Vector2i(current.x, current.y + 1),
				Vector2i(current.x, current.y - 1)
			]
			
			for neighbor in neighbors:
				if neighbor in used_floor_cells and not neighbor in checked_cells:
					to_check.append(neighbor)
		
		regions.append(region)
	
	# Report disconnected regions
	if regions.size() > 1:
		validation_issues.append({
			"type": "warning",
			"message": "Map has " + str(regions.size()) + " disconnected floor regions"
		})
		
		# Add details about regions
		for i in range(regions.size()):
			var region_size = regions[i].size()
			if region_size < 5:  # Small regions are more likely to be errors
				validation_issues.append({
					"type": "info",
					"message": "Small disconnected region #" + str(i+1) + " with " + str(region_size) + " tiles at position " + str(regions[i][0])
				})

# Validate atmosphere integrity
func _validate_atmosphere():
	if not editor_ref or not editor_ref.zone_manager:
		return
	
	# Check for breach points between zones with different atmospheres
	var breach_points = editor_ref.zone_manager.find_breach_points()
	
	if breach_points.size() > 0:
		validation_issues.append({
			"type": "error",
			"message": "Found " + str(breach_points.size()) + " atmosphere breach points between zones"
		})
		
		# Add details about first few breaches
		for i in range(min(breach_points.size(), 5)):
			var breach = breach_points[i]
			validation_issues.append({
				"type": "info",
				"message": "Breach at position " + str(breach.position) + " between zones " + str(breach.from_zone) + " and " + str(breach.to_zone)
			})
	
	# Check if exterior zones have proper environment setup
	for zone_id in editor_ref.zone_manager.zones:
		var zone = editor_ref.zone_manager.zones[zone_id]
		if zone.type == editor_ref.zone_manager.ZoneType.EXTERIOR:
			if zone.has_atmosphere:
				validation_issues.append({
					"type": "warning",
					"message": "Exterior zone " + zone.name + " has atmosphere enabled"
				})

# Validate tile placement
func _validate_tiles():
	if not editor_ref or not editor_ref.wall_tilemap:
		return
	
	var walls = editor_ref.wall_tilemap.get_used_cells(0)
	var floors = editor_ref.floor_tilemap.get_used_cells(0)
	
	# Check for walls with no adjacent floor
	for wall in walls:
		var has_adjacent_floor = false
		
		var adjacent_cells = [
			Vector2i(wall.x + 1, wall.y),
			Vector2i(wall.x - 1, wall.y),
			Vector2i(wall.x, wall.y + 1),
			Vector2i(wall.x, wall.y - 1)
		]
		
		for adj in adjacent_cells:
			if adj in floors:
				has_adjacent_floor = true
				break
		
		if not has_adjacent_floor:
			validation_issues.append({
				"type": "warning",
				"message": "Wall at position " + str(wall) + " has no adjacent floor tiles"
			})
	
	# Check for doors with no adjacent floor on both sides
	# This would require checking the object type, which we'll simplify for now
	var objects = editor_ref.objects_tilemap.get_used_cells(0)
	for obj in objects:
		var source_id = editor_ref.objects_tilemap.get_cell_source_id(0, obj)
		var atlas_coords = editor_ref.objects_tilemap.get_cell_atlas_coords(0, obj)
		
		# Simplified check for door-like objects (would be better with proper object type)
		if atlas_coords.y == 1:  # Assuming row 1 contains doors
			var has_both_sides = false
			
			# Check horizontal adjacency
			if Vector2i(obj.x + 1, obj.y) in floors and Vector2i(obj.x - 1, obj.y) in floors:
				has_both_sides = true
			
			# Check vertical adjacency
			if Vector2i(obj.x, obj.y + 1) in floors and Vector2i(obj.x, obj.y - 1) in floors:
				has_both_sides = true
			
			if not has_both_sides:
				validation_issues.append({
					"type": "warning",
					"message": "Door-like object at position " + str(obj) + " doesn't connect two floor areas"
				})

# Validate placed objects
func _validate_objects():
	if not editor_ref or not editor_ref.object_placer:
		return
	
	# This would need to check specific object requirements
	# For example, computers need power, doors need valid connections, etc.
	# Simplified version for now
	
	# Check for objects in invalid positions
	var floors = editor_ref.floor_tilemap.get_used_cells(0)
	var placed_objects_container = editor_ref.get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport/PlacedObjects")
	
	if placed_objects_container:
		for obj in placed_objects_container.get_children():
			var grid_pos = obj.get_meta("grid_position", Vector2i.ZERO)
			
			# Check if object is placed on a floor tile
			if not grid_pos in floors:
				validation_issues.append({
					"type": "warning",
					"message": "Object " + obj.name + " at position " + str(grid_pos) + " is not placed on a floor tile"
				})

# Validate lighting setup
func _validate_lighting():
	if not editor_ref or not editor_ref.lighting_system:
		return
	
	# Check for dark areas (areas with no light source)
	var light_sources = editor_ref.get_node_or_null("UI/MainPanel/VBoxContainer/HSplitContainer/EditorViewport/Viewport/LightSources")
	if not light_sources or light_sources.get_child_count() == 0:
		validation_issues.append({
			"type": "warning",
			"message": "No light sources found in the map"
		})
	
	# More specific lighting checks would be implemented here

# Generate the final validation report
func _generate_report():
	validation_report = "StationForge Map Validation Report\n"
	validation_report += "===============================\n\n"
	
	# Add map information
	if editor_ref:
		validation_report += "Map: " + editor_ref.current_map_name + "\n"
		validation_report += "Dimensions: " + str(editor_ref.map_width) + "x" + str(editor_ref.map_height) + "\n"
		validation_report += "Z-Levels: " + str(editor_ref.z_levels) + "\n\n"
	
	# Add issues summary
	var error_count = 0
	var warning_count = 0
	var info_count = 0
	
	for issue in validation_issues:
		match issue.type:
			"error": error_count += 1
			"warning": warning_count += 1
			"info": info_count += 1
	
	validation_report += "Found " + str(validation_issues.size()) + " issues:\n"
	validation_report += "- " + str(error_count) + " errors\n"
	validation_report += "- " + str(warning_count) + " warnings\n"
	validation_report += "- " + str(info_count) + " informational\n\n"
	
	# Add detailed issues list
	validation_report += "Issue Details:\n"
	validation_report += "==============\n\n"
	
	var issue_index = 1
	for issue in validation_issues:
		var prefix = ""
		match issue.type:
			"error": prefix = "ERROR: "
			"warning": prefix = "WARNING: "
			"info": prefix = "INFO: "
		
		validation_report += str(issue_index) + ". " + prefix + issue.message + "\n"
		issue_index += 1
	
	if validation_issues.size() == 0:
		validation_report += "No issues found. Map validation passed!\n"

# Get the validation report
func get_validation_report() -> String:
	return validation_report
