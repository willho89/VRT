class_name GlowAnchor
extends Node3D
## Instanced by OpenXRFbSceneManager for each real surface from Meta room setup
## (walls, floor, furniture, global mesh). Shows the CRT's light on it and gives
## the placement ray something to hit.

const GLOW_SHADER := preload("res://shaders/ar_screen_glow.gdshader")
## TV menu > AR LIGHT: whether the CRT's light is drawn on the real room. The
## surfaces stay for pointing either way.
static var light_enabled := true


static func set_light_enabled(tree: SceneTree, on: bool) -> void:
	light_enabled = on
	tree.call_group(&"ar_glow", &"set_visible", on)


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
		mesh_instance.add_to_group(&"ar_glow")
		mesh_instance.visible = light_enabled
		add_child(mesh_instance)
