class_name CabinetBox
extends Node3D
## Procedural cabinet sized around any tube: a front bezel with an opening for
## the glass, a deep body behind it, a power LED and two speaker points. Used
## by TV types without a 3D model (monitors, PVMs, prototypes), configured
## from the type's "cabinet" object (see docs/tv-types.md).
##
## Cabinet convention (shared by every cabinet): metres, origin at the bottom
## centre of the front face, front facing +Z.

var screen_origin := Vector3.ZERO
var speakers: Array[Node3D] = []
var bounds := AABB()
var _led_on := StandardMaterial3D.new()
var _led_off := StandardMaterial3D.new()
var _led := MeshInstance3D.new()


## visible_m: the tube's picture size. cfg keys (all optional, millimetres):
## bezel_mm [left/right, top, bottom], depth_mm, color, front_color, speakers
## ("sides" or "below" or "none").
func _init(visible_m: Vector2, cfg: Dictionary) -> void:
	var mm := 0.001
	var bezel: Array = cfg.get("bezel_mm", [45.0, 45.0, 70.0])
	var side: float = bezel[0] * mm
	var top: float = bezel[1] * mm
	var bottom: float = bezel[2] * mm
	var depth: float = cfg.get("depth_mm", maxf(visible_m.x * 1000.0 * 0.85, 300.0)) * mm
	var body_col := Color(cfg.get("color", "#1c1c1e"))
	var front_col := Color(cfg.get("front_color", cfg.get("color", "#1c1c1e")))
	var opening := visible_m * 1.06            # a little black glass round the picture
	var w := opening.x + 2.0 * side
	var h := opening.y + top + bottom
	bounds = AABB(Vector3(-w * 0.5, 0.0, -depth), Vector3(w, h, depth))
	screen_origin = Vector3(0.0, bottom + opening.y * 0.5, -0.012)

	var front := _mat(front_col, 0.55)
	var body := _mat(body_col, 0.6)
	var frame_d := 0.04
	# Bezel: four bars round the opening.
	_box(Vector3(w, bottom, frame_d), Vector3(0, bottom * 0.5, -frame_d * 0.5), front)
	_box(Vector3(w, top, frame_d), Vector3(0, h - top * 0.5, -frame_d * 0.5), front)
	for sx in [-1.0, 1.0]:
		_box(Vector3(side, opening.y, frame_d), Vector3(sx * (w - side) * 0.5, bottom + opening.y * 0.5, -frame_d * 0.5), front)
	# Body behind, slightly inset; a dark liner so the opening reads as a recess.
	_box(Vector3(w - 0.02, h - 0.02, depth - frame_d), Vector3(0, h * 0.5, -frame_d - (depth - frame_d) * 0.5), body)
	_box(Vector3(opening.x, opening.y, 0.02), Vector3(0, screen_origin.y, -0.06), _mat(Color(0.02, 0.02, 0.02), 0.9))

	_led_on.albedo_color = Color(0.05, 0.3, 0.05)
	_led_on.emission_enabled = true
	_led_on.emission = Color(0.1, 1.0, 0.2)
	_led_on.emission_energy_multiplier = 1.5
	_led_off.albedo_color = Color(0.02, 0.05, 0.02)
	var led_mesh := BoxMesh.new()
	led_mesh.size = Vector3(0.006, 0.004, 0.003)
	_led.mesh = led_mesh
	_led.position = Vector3(w * 0.5 - side - 0.02, bottom * 0.35, 0.001)
	add_child(_led)

	match cfg.get("speakers", "below"):
		"sides":
			for sx in [-1.0, 1.0]:
				_speaker(Vector3(sx * (w * 0.5 - side * 0.5), screen_origin.y, 0.0))
		"none":
			_speaker(screen_origin)
			_speaker(screen_origin)
		_:
			for sx in [-1.0, 1.0]:
				_speaker(Vector3(sx * w * 0.25, bottom * 0.5, 0.0))


func set_power_led(on: bool) -> void:
	_led.material_override = _led_on if on else _led_off


func _speaker(p: Vector3) -> void:
	var n := Node3D.new()
	n.position = p
	add_child(n)
	speakers.append(n)


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.material_override = mat
	add_child(m)


static func _mat(c: Color, rough: float) -> Material:
	return CabinetVcrCombo._plastic_material(c, rough)
