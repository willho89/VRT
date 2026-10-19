extends Node3D
## Instanced by OpenXRFbSceneManager for each real surface from Meta room setup
## (walls, floor, furniture, global mesh). Shows the CRT's light on it and gives
## the placement ray something to hit.

const GLOW_SHADER := preload("res://shaders/ar_screen_glow.gdshader")


func setup_scene(entity: Object) -> void:
	add_to_group(&"real_scene")
	visible = get_viewport().transparent_bg  # only shown in passthrough
	print("VRT: scene anchor ", entity.call("get_semantic_labels"))
	var body := StaticBody3D.new()
	body.collision_layer = 0b10
	add_child(body)
	var shape = entity.call("create_collision_shape")
	if shape:
		body.add_child(shape)

	var mesh_instance: MeshInstance3D = entity.call("create_mesh_instance")
	if mesh_instance:
		var mat := ShaderMaterial.new()
		mat.shader = GLOW_SHADER
		mesh_instance.material_override = mat
		add_child(mesh_instance)
