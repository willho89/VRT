class_name Tv
extends Node3D
## The TV set: cabinet and bezel sized from the active CrtProfile, the curved
## faceplate running the CRT pipeline, and the screen-light globals
## (screen_light.gdshaderinc) published every frame.

const SCREEN_RADIANCE := 2.0
const SAMPLES := Vector2i(16, 12)
const BEZEL := Vector2(0.06, 0.07)    # bezel width beyond the picture, m
const CABINET_DEPTH := 0.46

var profile := CrtProfile.generic_shadowmask_27()
var pipeline := CrtPipeline.new(profile)
var screen := MeshInstance3D.new()
var screen_body := StaticBody3D.new()
var _cabinet := Node3D.new()
var _cells := Image.create_empty(SAMPLES.x, SAMPLES.y, false, Image.FORMAT_RGBF)
var _cells_tex := ImageTexture.create_from_image(_cells)
var _coarse := Image.create_empty(4, 3, false, Image.FORMAT_RGBF)
var _coarse_tex := ImageTexture.create_from_image(_coarse)
var _half := Vector2.ONE


func _ready() -> void:
	add_child(pipeline)
	screen.material_override = pipeline.surface
	add_child(screen)
	add_child(_cabinet)
	screen_body.collision_layer = 1 << 4  # layer 5: screen (DVD menu pointing)
	screen.add_child(screen_body)
	apply_profile(profile)


## Rebuild tube, cabinet and collider for a profile (one active at a time).
func apply_profile(p: CrtProfile) -> void:
	profile = p
	pipeline.set_profile(p)
	var size := p.size_m()
	_half = size * 0.5
	screen.mesh = TubeMesh.build(p)
	var face_h := size.y + 2.0 * BEZEL.y
	screen.position = Vector3(0, face_h * 0.5 + 0.02, 0)

	for c in screen_body.get_children():
		c.queue_free()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y, 0.01)
	shape.shape = box
	screen_body.add_child(shape)

	for c in _cabinet.get_children():
		c.queue_free()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.07, 0.07, 0.075)
	mat.roughness = 0.55
	var face := Vector2(size.x + 2.0 * BEZEL.x, face_h)
	var sag := TubeMesh.edge_sag(p)
	# Cabinet body behind the bezel.
	_add_box(Vector3(face.x, face.y, CABINET_DEPTH),
			Vector3(0, screen.position.y, -sag - CABINET_DEPTH * 0.5), mat)
	# Bezel frame: four bars around the picture, flush with the glass edge.
	var depth := sag + 0.03
	var z := -sag * 0.5 + 0.012
	_add_box(Vector3(face.x, BEZEL.y, depth), Vector3(0, screen.position.y + (size.y + BEZEL.y) * 0.5, z), mat)
	_add_box(Vector3(face.x, BEZEL.y, depth), Vector3(0, screen.position.y - (size.y + BEZEL.y) * 0.5, z), mat)
	_add_box(Vector3(BEZEL.x, size.y, depth), Vector3(-(size.x + BEZEL.x) * 0.5, screen.position.y, z), mat)
	_add_box(Vector3(BEZEL.x, size.y, depth), Vector3((size.x + BEZEL.x) * 0.5, screen.position.y, z), mat)


func _add_box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	_cabinet.add_child(mi)


## Called each frame with the core's current output (null when idle).
func show_frame(tex: Texture2D, image: Image, field: int, new_frames: int) -> void:
	pipeline.push(tex, field, new_frames)
	_sample_cells(image if tex else null)


## UV of a world-space point on the screen face, top-left origin.
func screen_uv(world_point: Vector3) -> Vector2:
	var l := screen.to_local(world_point)
	return Vector2(l.x / (_half.x * 2.0) + 0.5, 0.5 - l.y / (_half.y * 2.0))


func _process(_delta: float) -> void:
	var b := screen.global_transform.basis
	RenderingServer.global_shader_parameter_set("VRT_SCREEN_CENTER", screen.global_position)
	RenderingServer.global_shader_parameter_set("VRT_SCREEN_RIGHT", b.x.normalized() * _half.x)
	RenderingServer.global_shader_parameter_set("VRT_SCREEN_UP", b.y.normalized() * _half.y)
	RenderingServer.global_shader_parameter_set("VRT_SCREEN_RADIANCE", Vector3.ONE * SCREEN_RADIANCE)
	RenderingServer.global_shader_parameter_set("VRT_SCREEN_CELLS", _cells_tex)
	RenderingServer.global_shader_parameter_set("VRT_SCREEN_CELLS_COARSE", _coarse_tex)


## Linear color of each light cell: a 2x2 sample per cell of the CPU frame.
func _sample_cells(image: Image) -> void:
	if image == null or image.is_empty():
		_cells.fill(Color.BLACK)
	else:
		var w := image.get_width()
		var h := image.get_height()
		for y in SAMPLES.y:
			for x in SAMPLES.x:
				var c := Color(0, 0, 0)
				for sy in 2:
					for sx in 2:
						c += image.get_pixel(int((x + 0.25 + 0.5 * sx) * w / SAMPLES.x),
								int((y + 0.25 + 0.5 * sy) * h / SAMPLES.y)).srgb_to_linear()
				_cells.set_pixel(x, y, c * 0.25)
	# 4x3 summary for per-pixel use: each coarse cell averages 4x4 fine cells.
	for y in 3:
		for x in 4:
			var s := Color(0, 0, 0)
			for fy in 4:
				for fx in 4:
					s += _cells.get_pixel(x * 4 + fx, y * 4 + fy)
			_coarse.set_pixel(x, y, s / 16.0)
	_cells_tex.update(_cells)
	_coarse_tex.update(_coarse)
