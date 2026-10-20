class_name CabinetVcrCombo
extends Node3D
## A mid-90s 25" TV/VCR combo cabinet, modelled procedurally (original,
## unbadged geometry; proportions measured from photos of a 1996 combo set:
## 635 W x 577 H x 584 D mm). Origin: bottom centre of the front face;
## +Z points out of the screen. Units in this file: millimetres -> MM.

const MM := 0.001
const W := 635.0
const H := 577.0
const D := 584.0
const FRAME_DEPTH := 150.0
const OPENING := Vector2(561.0, 401.0)
const OPENING_RADIUS := 26.0
## Centre of the screen opening above the base.
const SCREEN_Y := 341.0
const BEVEL_DEPTH := 50.0
const CORNER_SEGS := 6

var plastic := _plastic_material(Color(0.045, 0.045, 0.048), 0.55)
var plastic_dark := _plastic_material(Color(0.02, 0.02, 0.022), 0.4)
var grille_mat := _grille_material()
var led_mat := StandardMaterial3D.new()

## Where the tube's glass centre goes (cabinet space, metres).
var screen_origin := Vector3(0, SCREEN_Y * MM, -12.0 * MM)
## Inner edge of the bevel; the tube must cover at least this (mm).
var glass_window := OPENING - Vector2(40.0, 10.0)


func _ready() -> void:
	led_mat.albedo_color = Color(0.05, 0.3, 0.05)
	led_mat.emission_enabled = true
	led_mat.emission = Color(0.1, 1.0, 0.2)
	led_mat.emission_energy_multiplier = 1.5
	_build_shell()
	_build_front_details()


# ---------------------------------------------------------------- shell ----

func _build_shell() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cy := H * 0.5
	var outer := _rrect(W, H, 18.0, 0.0, cy)
	var opening := _rrect(OPENING.x, OPENING.y, OPENING_RADIUS, 0.0, SCREEN_Y)
	var lip := _rrect(OPENING.x + 16.0, OPENING.y + 16.0, OPENING_RADIUS + 8.0, 0.0, SCREEN_Y)
	var window := _rrect(glass_window.x, glass_window.y, OPENING_RADIUS - 6.0, 0.0, SCREEN_Y)

	# Front face (outer edge to the raised lip), lip, then the bevel into the glass.
	_strip(st, outer, 0.0, lip, 0.0, true)
	_strip(st, lip, 0.0, lip, 4.0, false)
	_strip(st, lip, 4.0, opening, 4.0, true)
	_strip(st, opening, 4.0, window, -BEVEL_DEPTH, true)

	# Front frame sides, then the rear shell lofted in stages over the tube bell.
	var sections := [
		[0.0, W, H, 18.0, cy],
		[-FRAME_DEPTH, W, H, 18.0, cy],
		[-FRAME_DEPTH - 6.0, W - 20.0, H - 20.0, 26.0, cy],
		[-260.0, W - 40.0, H - 60.0, 60.0, cy + 15.0],
		[-380.0, W - 130.0, H - 170.0, 90.0, cy + 45.0],
		[-480.0, W - 210.0, H - 255.0, 100.0, cy + 70.0],
		[-D, W - 280.0, H - 320.0, 90.0, cy + 90.0],
	]
	for i in sections.size() - 1:
		var a: Array = sections[i]
		var b: Array = sections[i + 1]
		_strip(st, _rrect(a[1], a[2], a[3], 0.0, a[4]), a[0], _rrect(b[1], b[2], b[3], 0.0, b[4]), b[0], false)
	var last: Array = sections[-1]
	_cap(st, _rrect(last[1], last[2], last[3], 0.0, last[4]), last[0], Vector3.BACK)
	st.generate_normals()
	_add(st.commit(), plastic)

	# Lower rear housing (chassis box under the tube neck) and the base plinth.
	_box(Vector3(420.0, 185.0, D - 300.0), Vector3(0.0, 92.5, -300.0 - (D - 300.0) * 0.5), plastic)


# ------------------------------------------------------- front details ----

func _build_front_details() -> void:
	var panel_y := 62.0  # centre line of the lower control panel
	# VCR cassette door: recessed dark slot with a slightly proud flap.
	_box(Vector3(196.0, 30.0, 6.0), Vector3(0.0, panel_y + 8.0, -3.0), plastic_dark)
	_box(Vector3(188.0, 24.0, 2.0), Vector3(0.0, panel_y + 8.0, 0.6), plastic)
	# Speaker grilles left and right.
	for sx in [-1.0, 1.0]:
		var g := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(107.0, 65.0) * MM
		g.mesh = q
		g.material_override = grille_mat
		g.position = Vector3(sx * (W * 0.5 - 70.0), panel_y + 8.0, 0.4) * MM
		add_child(g)
	# Power button (left) and transport disc (right).
	_cylinder(12.0, 6.0, Vector3(-185.0, panel_y + 6.0, 2.0), plastic_dark)
	_cylinder(19.0, 5.0, Vector3(160.0, panel_y + 4.0, 1.5), plastic)
	_cylinder(9.0, 7.0, Vector3(140.0, panel_y + 4.0, 2.0), plastic_dark)
	# Row of small buttons under the cassette door, then indicator LEDs.
	for i in 7:
		_cylinder(4.5, 3.0, Vector3(-52.0 + i * 16.0, panel_y - 20.0, 1.5), plastic_dark)
	for i in 4:
		var led := _cylinder(1.6, 1.5, Vector3(78.0 + i * 18.0, panel_y - 20.0, 0.8), plastic_dark)
		if i == 0:
			led.material_override = led_mat
			led.name = "PowerLed"
	# Front A/V jack recess.
	_box(Vector3(55.0, 16.0, 8.0), Vector3(-115.0, panel_y - 42.0, -4.0), plastic_dark)
	# Separation groove between the screen surround and the control panel.
	_box(Vector3(W - 40.0, 2.0, 2.0), Vector3(0.0, panel_y + 40.0, -0.5), plastic_dark)


func set_power_led(on: bool) -> void:
	var led := find_child("PowerLed", true, false) as MeshInstance3D
	if led:
		led.material_override = led_mat if on else plastic_dark


# --------------------------------------------------------------- helpers ----

## Rounded rectangle outline (CCW seen from +Z), mm, centred at (cx, cy).
static func _rrect(w: float, h: float, r: float, cx: float, cy: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	r = minf(r, minf(w, h) * 0.5)
	var centres := [Vector2(w * 0.5 - r, h * 0.5 - r), Vector2(-w * 0.5 + r, h * 0.5 - r),
			Vector2(-w * 0.5 + r, -h * 0.5 + r), Vector2(w * 0.5 - r, -h * 0.5 + r)]
	for c in 4:
		for s in CORNER_SEGS + 1:
			var a := (c + float(s) / CORNER_SEGS) * PI * 0.5
			pts.append(Vector2(cx, cy) + centres[c] + Vector2(cos(a), sin(a)) * r)
	return pts


## Quad strip between two outlines with equal point counts at depths za, zb.
static func _strip(st: SurfaceTool, a: PackedVector2Array, za: float, b: PackedVector2Array, zb: float,
		facing_front: bool) -> void:
	var n := a.size()
	for i in n:
		var j := (i + 1) % n
		var p0 := Vector3(a[i].x, a[i].y, za) * MM
		var p1 := Vector3(a[j].x, a[j].y, za) * MM
		var q0 := Vector3(b[i].x, b[i].y, zb) * MM
		var q1 := Vector3(b[j].x, b[j].y, zb) * MM
		if facing_front:
			# a is the outer loop, b the inner: front faces wind CCW from +Z.
			st.add_vertex(p0); st.add_vertex(q0); st.add_vertex(p1)
			st.add_vertex(p1); st.add_vertex(q0); st.add_vertex(q1)
		else:
			# Side walls facing outward, a in front of b.
			st.add_vertex(p0); st.add_vertex(p1); st.add_vertex(q0)
			st.add_vertex(p1); st.add_vertex(q1); st.add_vertex(q0)


static func _cap(st: SurfaceTool, loop: PackedVector2Array, z: float, facing: Vector3) -> void:
	var c := Vector2.ZERO
	for p in loop:
		c += p
	c /= loop.size()
	for i in loop.size():
		var j := (i + 1) % loop.size()
		var a := Vector3(loop[i].x, loop[i].y, z) * MM
		var b := Vector3(loop[j].x, loop[j].y, z) * MM
		var m := Vector3(c.x, c.y, z) * MM
		if facing.z < 0.0:
			st.add_vertex(m); st.add_vertex(b); st.add_vertex(a)
		else:
			st.add_vertex(m); st.add_vertex(a); st.add_vertex(b)


func _add(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	return mi


func _box(size_mm: Vector3, centre_mm: Vector3, mat: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size_mm * MM
	var mi := _add(b, mat)
	mi.position = centre_mm * MM
	return mi


func _cylinder(radius_mm: float, depth_mm: float, centre_mm: Vector3, mat: Material) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = radius_mm * MM
	c.bottom_radius = radius_mm * MM
	c.height = depth_mm * MM
	c.radial_segments = 24
	c.rings = 1
	var mi := _add(c, mat)
	mi.position = centre_mm * MM
	mi.rotation_degrees = Vector3(90, 0, 0)
	return mi


static func _plastic_material(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic_specular = 0.4
	# Fine injection-moulding texture.
	var noise := FastNoiseLite.new()
	noise.frequency = 0.35
	var nt := NoiseTexture2D.new()
	nt.noise = noise
	nt.as_normal_map = true
	nt.bump_strength = 1.5
	nt.width = 256
	nt.height = 256
	m.normal_enabled = true
	m.normal_texture = nt
	m.normal_scale = 0.15
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(40, 40, 40)
	return m


static func _grille_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
// Speaker grille: horizontal slots moulded into the front panel.
uniform vec3 plastic : source_color = vec3(0.045, 0.045, 0.048);
void fragment() {
	float slot = smoothstep(0.35, 0.45, abs(fract(UV.y * 13.0) - 0.5));
	float border = step(0.04, UV.x) * step(UV.x, 0.96) * step(0.06, UV.y) * step(UV.y, 0.94);
	ALBEDO = plastic * mix(1.0, 0.15, (1.0 - slot) * border);
	ROUGHNESS = 0.6;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m
