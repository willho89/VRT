class_name Tv
extends Node3D
## The TV set. M1: a box with a flat screen quad showing the core's frame.
## M2 replaces the screen with the curved tube and the CRT pipeline.
##
## Also publishes the screen-light globals (screen_light.gdshaderinc) every
## frame: face geometry, and its average color sampled from the CPU-side frame.

const SCREEN_HALF := Vector2(0.25, 0.1875)  # 4:3 face, ~20"
const SCREEN_RADIANCE := 2.0
const SAMPLES := Vector2i(16, 12)

var screen := MeshInstance3D.new()
var screen_body := StaticBody3D.new()
var _mat := StandardMaterial3D.new()
var _radiance := Color.BLACK


func _ready() -> void:
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.62, 0.5, 0.48)
	body.mesh = box
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.06, 0.06, 0.065)
	body_mat.roughness = 0.6
	body.material_override = body_mat
	body.position = Vector3(0, 0.25, 0)
	add_child(body)

	var quad := QuadMesh.new()
	quad.size = SCREEN_HALF * 2.0
	screen.mesh = quad
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_mat.albedo_color = Color.BLACK
	screen.material_override = _mat
	screen.position = Vector3(0, 0.26, 0.241)
	add_child(screen)

	# Ray target for DVD menu pointing.
	screen_body.collision_layer = 1 << 4  # layer 5: screen
	var shape := CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = Vector3(SCREEN_HALF.x * 2.0, SCREEN_HALF.y * 2.0, 0.005)
	shape.shape = bshape
	screen_body.add_child(shape)
	screen.add_child(screen_body)


## Called each frame with the core's current output (null when idle).
func show_frame(tex: Texture2D, image: Image) -> void:
	if tex != _mat.albedo_texture:
		_mat.albedo_texture = tex
		_mat.albedo_color = Color.WHITE if tex else Color.BLACK
	_radiance = _average(image) if tex else Color.BLACK


## UV of a world-space point on the screen face, top-left origin.
func screen_uv(world_point: Vector3) -> Vector2:
	var l := screen.to_local(world_point)
	return Vector2(l.x / (SCREEN_HALF.x * 2.0) + 0.5, 0.5 - l.y / (SCREEN_HALF.y * 2.0))


func _process(_delta: float) -> void:
	var b := screen.global_transform.basis
	RenderingServer.global_shader_parameter_set("VRT_SCREEN_CENTER", screen.global_position)
	RenderingServer.global_shader_parameter_set("VRT_SCREEN_RIGHT", b.x.normalized() * SCREEN_HALF.x)
	RenderingServer.global_shader_parameter_set("VRT_SCREEN_UP", b.y.normalized() * SCREEN_HALF.y)
	RenderingServer.global_shader_parameter_set("VRT_SCREEN_RADIANCE",
			Vector3(_radiance.r, _radiance.g, _radiance.b) * SCREEN_RADIANCE)


## Mean linear color over a coarse grid of the frame.
static func _average(image: Image) -> Color:
	if image == null or image.is_empty():
		return Color.BLACK
	var w := image.get_width()
	var h := image.get_height()
	var sum := Color(0, 0, 0, 0)
	for y in SAMPLES.y:
		for x in SAMPLES.x:
			var c := image.get_pixel(int((x + 0.5) * w / SAMPLES.x), int((y + 0.5) * h / SAMPLES.y))
			sum += c.srgb_to_linear()
	return sum / float(SAMPLES.x * SAMPLES.y)
