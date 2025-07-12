extends Node

# Layer definitions to match the main game
enum TileLayer {
	FLOOR = 0,
	WALL = 1,
	OBJECTS = 2,
	WIRE = 3,
	PIPE = 4,
	ZONE = 5
}

# Direction enum to match the main game
enum Direction {
	NORTH,
	SOUTH,
	WEST,
	EAST
}

# Floor tile types
const FLOOR_TYPES = {
	"metal_floor": {
		"name": "Metal Floor",
		"atlas_coords": Vector2i(1, 1),  # Center tile
		"properties": {
			"material": "metal",
			"collision": false,
			"health": 100
		}
	},
	"metal_floor_corner_tl": {
		"name": "Metal Floor Corner (TL)",
		"atlas_coords": Vector2i(0, 0),
		"properties": {
			"material": "metal",
			"collision": false,
			"health": 100
		}
	},
	"metal_floor_edge_top": {
		"name": "Metal Floor Edge (Top)",
		"atlas_coords": Vector2i(1, 0),
		"properties": {
			"material": "metal",
			"collision": false,
			"health": 100
		}
	},
	"metal_floor_corner_tr": {
		"name": "Metal Floor Corner (TR)",
		"atlas_coords": Vector2i(2, 0),
		"properties": {
			"material": "metal",
			"collision": false,
			"health": 100
		}
	},
	"metal_floor_edge_left": {
		"name": "Metal Floor Edge (Left)",
		"atlas_coords": Vector2i(0, 1),
		"properties": {
			"material": "metal",
			"collision": false,
			"health": 100
		}
	},
	"metal_floor_edge_right": {
		"name": "Metal Floor Edge (Right)",
		"atlas_coords": Vector2i(2, 1),
		"properties": {
			"material": "metal",
			"collision": false,
			"health": 100
		}
	},
	"metal_floor_corner_bl": {
		"name": "Metal Floor Corner (BL)",
		"atlas_coords": Vector2i(0, 2),
		"properties": {
			"material": "metal",
			"collision": false,
			"health": 100
		}
	},
	"metal_floor_edge_bottom": {
		"name": "Metal Floor Edge (Bottom)",
		"atlas_coords": Vector2i(1, 2),
		"properties": {
			"material": "metal",
			"collision": false,
			"health": 100
		}
	},
	"metal_floor_corner_br": {
		"name": "Metal Floor Corner (BR)",
		"atlas_coords": Vector2i(2, 2),
		"properties": {
			"material": "metal",
			"collision": false,
			"health": 100
		}
	},
	"carpet_floor": {
		"name": "Carpet Floor",
		"atlas_coords": Vector2i(1, 5),
		"properties": {
			"material": "carpet",
			"collision": false,
			"health": 80
		}
	},
	"wood_floor": {
		"name": "Wood Floor",
		"atlas_coords": Vector2i(3, 0),
		"properties": {
			"material": "wood",
			"collision": false,
			"health": 80
		}
	},
	"exterior_floor": {
		"name": "Exterior Floor",
		"atlas_coords": Vector2i(3, 1),
		"properties": {
			"material": "exterior",
			"collision": false,
			"health": 120
		}
	}
}

# Wall tile types
const WALL_TYPES = {
	"metal_wall": {
		"name": "Metal Wall",
		"atlas_coords": Vector2i(2, 2),  # Center tile
		"properties": {
			"material": "metal",
			"collision": true,
			"health": 200
		}
	},
	"metal_wall_horizontal": {
		"name": "Metal Wall (Horizontal)",
		"atlas_coords": Vector2i(2, 1),
		"properties": {
			"material": "metal",
			"collision": true,
			"health": 200
		}
	},
	"metal_wall_vertical": {
		"name": "Metal Wall (Vertical)",
		"atlas_coords": Vector2i(1, 2),
		"properties": {
			"material": "metal",
			"collision": true,
			"health": 200
		}
	},
	"metal_wall_corner_tl": {
		"name": "Metal Wall Corner (TL)",
		"atlas_coords": Vector2i(1, 1),
		"properties": {
			"material": "metal",
			"collision": true,
			"health": 200
		}
	},
	"metal_wall_corner_tr": {
		"name": "Metal Wall Corner (TR)",
		"atlas_coords": Vector2i(3, 1),
		"properties": {
			"material": "metal",
			"collision": true,
			"health": 200
		}
	},
	"metal_wall_corner_bl": {
		"name": "Metal Wall Corner (BL)",
		"atlas_coords": Vector2i(1, 3),
		"properties": {
			"material": "metal",
			"collision": true,
			"health": 200
		}
	},
	"metal_wall_corner_br": {
		"name": "Metal Wall Corner (BR)",
		"atlas_coords": Vector2i(3, 3),
		"properties": {
			"material": "metal",
			"collision": true,
			"health": 200
		}
	},
	"glass_wall": {
		"name": "Glass Wall",
		"atlas_coords": Vector2i(7, 2),
		"properties": {
			"material": "glass",
			"collision": true,
			"health": 100,
			"transparent": true
		}
	},
	"insulated_wall": {
		"name": "Insulated Wall",
		"atlas_coords": Vector2i(4, 2),
		"properties": {
			"material": "insulated",
			"collision": true,
			"health": 150
		}
	},
	"reinforced_wall": {
		"name": "Reinforced Wall",
		"atlas_coords": Vector2i(5, 2),
		"properties": {
			"material": "reinforced",
			"collision": true,
			"health": 300
		}
	}
}

# Object tile types
const OBJECT_TYPES = {
	"door": {
		"name": "Door",
		"atlas_coords": Vector2i(0, 0),
		"properties": {
			"material": "metal",
			"collision": true,
			"interactive": true,
			"health": 100
		}
	},
	"door_open": {
		"name": "Door (Open)",
		"atlas_coords": Vector2i(1, 0),
		"properties": {
			"material": "metal",
			"collision": false,
			"interactive": true,
			"health": 100,
			"door": {
				"closed": false,
				"locked": false
			}
		}
	},
	"computer": {
		"name": "Computer Terminal",
		"atlas_coords": Vector2i(1, 0),
		"properties": {
			"material": "electronic",
			"collision": true,
			"interactive": true,
			"health": 80
		}
	},
	"locker": {
		"name": "Locker",
		"atlas_coords": Vector2i(2, 0),
		"properties": {
			"material": "metal",
			"collision": true,
			"interactive": true,
			"storage": true,
			"health": 120
		}
	},
	"table": {
		"name": "Table",
		"atlas_coords": Vector2i(0, 2),
		"properties": {
			"material": "metal",
			"collision": true,
			"health": 100
		}
	},
	"chair": {
		"name": "Chair",
		"atlas_coords": Vector2i(1, 2),
		"properties": {
			"material": "metal",
			"collision": true,
			"health": 80
		}
	},
	"window": {
		"name": "Window",
		"atlas_coords": Vector2i(3, 0),
		"properties": {
			"material": "glass",
			"collision": true,
			"health": 50,
			"transparent": true
		}
	}
}

# Zone tile types
const ZONE_TYPES = {
	"living_quarters": {
		"name": "Living Quarters",
		"atlas_coords": Vector2i(0, 0),
		"properties": {
			"type": "habitation",
			"has_gravity": true,
			"has_atmosphere": true,
			"color": Color(0.2, 0.6, 1.0, 0.5)
		}
	},
	"engineering": {
		"name": "Engineering",
		"atlas_coords": Vector2i(1, 0),
		"properties": {
			"type": "technical",
			"has_gravity": true,
			"has_atmosphere": true,
			"color": Color(1.0, 0.5, 0.0, 0.5)
		}
	},
	"medical": {
		"name": "Medical",
		"atlas_coords": Vector2i(2, 0),
		"properties": {
			"type": "medical",
			"has_gravity": true,
			"has_atmosphere": true,
			"color": Color(1.0, 0.2, 0.2, 0.5)
		}
	},
	"exterior": {
		"name": "Exterior (Vacuum)",
		"atlas_coords": Vector2i(2, 0),
		"properties": {
			"type": "exterior",
			"has_gravity": false,
			"has_atmosphere": false,
			"color": Color(0.5, 0.5, 0.5, 0.5)
		}
	}
}

# Dictionary of placeable objects (non-tilemap objects)
const PLACEABLE_OBJECTS = {
	"light": {
		"name": "Light",
		"scene_path": "res://objects/Light.tscn",
		"preview_icon": "res://assets/icons/light_icon.png",
		"properties": {
			"entity_type": "light",
			"entity_dense": false,
			"can_push": false
		}
	},
	"computer": {
		"name": "Computer Terminal",
		"scene_path": "res://objects/ComputerTerminal.tscn",
		"preview_icon": "res://assets/icons/computer_icon.png",
		"properties": {
			"entity_type": "computer",
			"entity_dense": true,
			"can_push": true,
			"mass": 20
		}
	},
	"switch": {
		"name": "Wall Switch",
		"scene_path": "res://objects/WallSwitch.tscn",
		"preview_icon": "res://assets/icons/switch_icon.png",
		"properties": {
			"entity_type": "switch",
			"entity_dense": false,
			"anchored": true
		}
	}
}

# Get a property dictionary for a specific tile type
static func get_tile_properties(layer: int, type_name: String) -> Dictionary:
	var properties = {}
	
	match layer:
		TileLayer.FLOOR:
			if type_name in FLOOR_TYPES:
				properties = FLOOR_TYPES[type_name].properties.duplicate()
		TileLayer.WALL:
			if type_name in WALL_TYPES:
				properties = WALL_TYPES[type_name].properties.duplicate()
		TileLayer.OBJECTS:
			if type_name in OBJECT_TYPES:
				properties = OBJECT_TYPES[type_name].properties.duplicate()
		TileLayer.ZONE:
			if type_name in ZONE_TYPES:
				properties = ZONE_TYPES[type_name].properties.duplicate()
	
	return properties

# Get properties for an object
static func get_object_properties(object_type: String) -> Dictionary:
	if object_type in PLACEABLE_OBJECTS:
		return PLACEABLE_OBJECTS[object_type].properties.duplicate()
	return {}

# Get all terrain neighbor indices for iteration
static func get_terrain_neighbor_indices() -> Array:
	# Return all valid terrain neighbor indices
	return [
		TileSet.CELL_NEIGHBOR_RIGHT_SIDE,
		TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
		TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
		TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
		TileSet.CELL_NEIGHBOR_LEFT_SIDE,
		TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
		TileSet.CELL_NEIGHBOR_TOP_SIDE,
		TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER
	]

# Convert direction enum to string
static func direction_to_string(dir: int) -> String:
	match dir:
		Direction.NORTH:
			return "North"
		Direction.SOUTH:
			return "South"
		Direction.EAST:
			return "East"
		Direction.WEST:
			return "West"
		_:
			return "Unknown"

# Convert string to direction enum
static func string_to_direction(dir_str: String) -> int:
	match dir_str.to_lower():
		"north":
			return Direction.NORTH
		"south":
			return Direction.SOUTH
		"east":
			return Direction.EAST
		"west":
			return Direction.WEST
		_:
			return Direction.NORTH
