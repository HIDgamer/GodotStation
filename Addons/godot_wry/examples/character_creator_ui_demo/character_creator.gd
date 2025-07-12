extends Node3D

var rotating = false

@onready var body_material = $"Character/ACNH Character Armature/Skeleton3D/ACNHBody_001".get_active_material(0)
@onready var hair_meshes = {
	"short": $"Character/ACNH Character Armature/Skeleton3D/Hair 01/Hair 01",
	"long": $"Character/ACNH Character Armature/Skeleton3D/Hair_02/Hair_02"
}
@onready var hair_material = $"Character/ACNH Character Armature/Skeleton3D/Hair 01/Hair 01".get_active_material(0)
@onready var face_material = $"Character/ACNH Character Armature/Skeleton3D/ACNHBody_001".get_active_material(1)
@onready var eye_material = $"Character/ACNH Character Armature/Skeleton3D/Eyes/Eyes".get_active_material(0)
@onready var eye_textures = {
	"a": preload("res://addons/godot_wry/examples/character_creator_ui_demo/assets/character/tex_eyes_1.png"),
	"b": preload("res://addons/godot_wry/examples/character_creator_ui_demo/assets/character/tex_eyes_2.png"),
}
@onready var top_meshes = {
	"tshirt": $"Character/ACNH Character Armature/Skeleton3D/Shirt01",
	"sweater": $"Character/ACNH Character Armature/Skeleton3D/Shirt02",
	"dress": $"Character/ACNH Character Armature/Skeleton3D/Dress",
}
@onready var necklace_mesh = $"Character/ACNH Character Armature/Skeleton3D/Necklace"
@onready var top_materials = {
	"tshirt": top_meshes["tshirt"].get_active_material(1),
	"sweater": top_meshes["sweater"].get_active_material(0),
	"dress": top_meshes["dress"].get_active_material(1),
}
@onready var bottom_meshes = {
	"pants": $"Character/ACNH Character Armature/Skeleton3D/Pants01",
	"shorts": $"Character/ACNH Character Armature/Skeleton3D/Shorts",
	"skirt": $"Character/ACNH Character Armature/Skeleton3D/Skirt",
}
@onready var shoes_meshes = {
	"shoes": $"Character/ACNH Character Armature/Skeleton3D/Shoes",
	"rain_boots": $"Character/ACNH Character Armature/Skeleton3D/Boots",
}
@onready var accessories_meshes = {
	"glasses": $"Character/ACNH Character Armature/Skeleton3D/Glasses",
	"cap": $"Character/ACNH Character Armature/Skeleton3D/Hat",
	"cat_ears": $"Character/ACNH Character Armature/Skeleton3D/CatEars",
}

func _input(event):
	if event is InputEventMouseButton:
		if event.is_pressed():
			rotating = true
		
		if event.is_released():
			rotating = false
	
	if event is InputEventMouseMotion and rotating:
		var delta = get_process_delta_time()
		var rel = event.relative
		
		$Character.rotate_y(rel.x * .5 * delta)

func _on_web_view_ipc_message(message):
	var data = JSON.parse_string(message)
	
	match data.type:
		"open_url":
			OS.shell_open(data.url)
			
		"open_devtools":
			$WebView.open_devtools()
		
		"change_tab":
			var tween = get_tree().create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUINT)
			var position = Vector3(0, 0, 0)
			if data.tab == "hair" || data.tab == "eyes":
				position = Vector3(-0.23, 0.2, -1)
			tween.tween_property($Camera3D, "position", position, .8)
			
		"set_color_skin":
			body_material.albedo_color = Color(data.color)
			
		"set_hair":
			for id in hair_meshes:
				var mesh = hair_meshes[id]
				mesh.visible = id == data.item
			
		"set_color_hair":
			hair_material.albedo_color = Color(data.color)
			
		"set_eyes":
			face_material.albedo_texture = eye_textures[data.item]
			
		"set_color_eyes":
			eye_material.albedo_color = Color(data.color)
			
		"set_top":
			for id in top_meshes:
				var mesh = top_meshes[id]
				mesh.visible = id == data.item
			necklace_mesh.visible = data.item == "dress"
			
		"set_color_top":
			for id in top_materials:
				var material = top_materials[id]
				material.albedo_color = Color(data.color)
				
		"set_bottom":
			for id in bottom_meshes:
				var mesh = bottom_meshes[id]
				mesh.visible = id == data.item
			
		"set_color_bottom":
			for id in bottom_meshes:
				var material = bottom_meshes[id].get_active_material(0)
				material.albedo_color = Color(data.color)
				
		"set_accessories":
			for id in accessories_meshes:
				var mesh = accessories_meshes[id]
				mesh.visible = id == data.item
				
		"set_shoes":
			for id in shoes_meshes:
				var mesh = shoes_meshes[id]
				mesh.visible = id == data.item
			
		"set_color_shoes":
			for id in shoes_meshes:
				var material = shoes_meshes[id].get_active_material(0)
				material.albedo_color = Color(data.color)
