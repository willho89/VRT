class_name CabinetModel
extends Node3D
## A TV type's own 3D model (glTF 2.0 .glb/.gltf), loaded at runtime from the
## type's folder. The model supplies the cabinet; VRT supplies the tube, so
## the model should have an opening (or no glass) where the picture goes.
## Where the glass centre, speakers and power LED are comes from the type's
## "cabinet" object, in the model's own units times "scale" (see
## docs/tv-types.md).
##
## Cabinet convention (shared by every cabinet): metres, origin at the bottom
## centre of the front face, front facing +Z. "offset" moves the model to fit.

var screen_origin := Vector3.ZERO
var speakers: Array[Node3D] = []
var bounds := AABB()
var _led: MeshInstance3D
var _led_on := StandardMaterial3D.new()
var loaded := false


func _init(path: String, cfg: Dictionary) -> void:
	var s: float = cfg.get("scale", 1.0)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_warning("VRT: TV model failed to load: " + path)
		return
	var scene := doc.generate_scene(state) as Node3D
	if scene == null:
		return
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * s
	holder.position = _v3(cfg.get("offset"), Vector3.ZERO)
	holder.rotation_degrees = _v3(cfg.get("rotation_deg"), Vector3.ZERO)
	holder.add_child(scene)
	add_child(holder)
	loaded = true

	screen_origin = _v3(cfg.get("screen_center"), Vector3.ZERO)
	for p in cfg.get("speakers", [cfg.get("screen_center", [0, 0, 0])]):
		var n := Node3D.new()
		n.position = _v3(p, screen_origin)
		add_child(n)
		speakers.append(n)
	if speakers.size() == 1:
		speakers.append(speakers[0])
	if cfg.has("bounds"):
		var b: Dictionary = cfg.bounds
		var size := _v3(b.get("size"), Vector3.ONE * 0.5)
		bounds = AABB(_v3(b.get("center"), Vector3.ZERO) - size * 0.5, size)
	else:
		bounds = _mesh_bounds(self)
	if cfg.has("power_led"):
		_led_on.emission_enabled = true
		_led_on.emission = Color(cfg.get("led_color", "#20ff40"))
		_led_on.emission_energy_multiplier = 1.5
		_led = MeshInstance3D.new()
		var m := SphereMesh.new()
		m.radius = 0.0025
		m.height = 0.005
		_led.mesh = m
		_led.position = _v3(cfg.power_led, Vector3.ZERO)
		add_child(_led)


func set_power_led(on: bool) -> void:
	if _led:
		_led.visible = on
		_led.material_override = _led_on


## Union of every mesh's AABB, in this node's space.
static func _mesh_bounds(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var xf := root.global_transform.affine_inverse() * mi.global_transform if root.is_inside_tree() else _relative(root, mi)
		var box := xf * mi.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


static func _relative(root: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


static func _v3(a, fallback: Vector3) -> Vector3:
	return Vector3(a[0], a[1], a[2]) if a is Array and a.size() >= 3 else fallback
