class_name MenuPanel3D
extends Node3D
## Shows a Control in the 3D world and lets a controller ray click it.
## The Control renders into a SubViewport mapped onto a quad; ray hits are
## turned into mouse events pushed into that viewport.

const PIXELS_PER_METRE := 1400.0

var viewport := SubViewport.new()
var _quad := MeshInstance3D.new()
var _body := StaticBody3D.new()
var _size_m := Vector2.ONE
var _was_pressed := false


func _init(content: Control, px_size: Vector2i) -> void:
	viewport.size = px_size
	viewport.transparent_bg = false
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_size_m = Vector2(px_size) / PIXELS_PER_METRE
	var mesh := QuadMesh.new()
	mesh.size = _size_m
	_quad.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = viewport.get_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_quad.material_override = mat
	add_child(_quad)

	_body.collision_layer = 1 << 3  # layer 4: UI
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_size_m.x, _size_m.y, 0.01)
	shape.shape = box
	_body.add_child(shape)
	add_child(_body)


## Feed one ray sample. Returns true if the ray is on the panel.
func handle_ray(hit_global: Vector3, collider: Object, pressed: bool) -> bool:
	if collider != _body or not visible:
		if _was_pressed:
			_send_button(Vector2.ZERO, false)
		return false
	var local := to_local(hit_global)
	var px := Vector2((local.x / _size_m.x + 0.5) * viewport.size.x,
			(0.5 - local.y / _size_m.y) * viewport.size.y)
	var motion := InputEventMouseMotion.new()
	motion.position = px
	motion.global_position = px
	viewport.push_input(motion)
	if pressed != _was_pressed:
		_send_button(px, pressed)
	return true


func _send_button(px: Vector2, pressed: bool) -> void:
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = pressed
	b.position = px
	b.global_position = px
	viewport.push_input(b)
	_was_pressed = pressed


func set_active(active: bool) -> void:
	visible = active
	_body.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	_body.collision_layer = (1 << 3) if active else 0
