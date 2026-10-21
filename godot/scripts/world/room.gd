class_name Room
extends Node3D
## The VR room around the TV, built from a room definition (rooms/*.json,
## format in docs/rooms.md): the built-in empty room, or a user's glTF model
## whose surfaces are re-lit by the CRT (shaders/room_lit_model.gdshader).
## Every room is lit only by the CRT plus a dim ambient fill, which the
## definition can tune. Hidden in AR (the real room takes over).
##
## Room convention: metres, Y up, floor at y = 0.

const SIZE := Vector3(4.0, 2.8, 5.0)
const ROOM_SHADER := preload("res://shaders/room_lit.gdshader")
const MODEL_SHADER := preload("res://shaders/room_lit_model.gdshader")
const STAND_TOP := 0.55
const DEFAULT_ID := "empty_room"

var def := {}
var floor_body := StaticBody3D.new()
var _content := Node3D.new()
var _bodies: Array[StaticBody3D] = []
## What the TV's glass reflects in the VR room: a box-projected probe captured
## once, shortly after building (so the CRT's light is in it). Hidden with the
## room in AR.
var _probe: ReflectionProbe


func _ready() -> void:
	floor_body.collision_layer = 1 << 0
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(shape)
	add_child(floor_body)
	add_child(_content)


## Replace the room with definition d (from UserDefs.load_all("rooms")).
func build(d: Dictionary) -> void:
	def = d
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_bodies.clear()
	if d.has("model"):
		var scene := UserDefs.load_gltf(str(d.dir).path_join(d.model))
		if scene:
			_add_model(scene, d)
			_add_probe()
			return
	_build_empty()
	_add_probe()


func _add_probe() -> void:
	if _probe:
		_probe.queue_free()
	var box := CabinetModel._mesh_bounds(_content) if _content.get_child_count() > 0 else AABB()
	if box.size == Vector3.ZERO:
		return
	_probe = ReflectionProbe.new()
	_probe.box_projection = true
	_probe.interior = true
	_probe.size = box.size
	_probe.position = box.get_center()
	# Capture from about eye height in front of the TV, where reflections are seen.
	_probe.origin_offset = Vector3(0.0, 1.1 - box.get_center().y, 0.0)
	_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	_probe.visible = false
	add_child(_probe)
	get_tree().create_timer(1.5).timeout.connect(func():
		if is_instance_valid(_probe):
			_probe.visible = true)


## Where the TV goes by default: its base centre and heading (TV front faces
## +Z at yaw 0). depth: the cabinet's depth, so its footprint is centred.
func tv_transform(depth: float) -> Transform3D:
	var tvd: Dictionary = def.get("tv", {})
	var base := UserDefs.v3(tvd.get("position"), Vector3(0, STAND_TOP, -1.6))
	var b := Basis(Vector3.UP, deg_to_rad(tvd.get("yaw_deg", 0.0)))
	return Transform3D(b, base + b.z * depth * 0.5)


## Optional fixed viewing spot ([x, z]); empty when the room has none and
## the viewer stands in front of the TV instead.
func spawn() -> Variant:
	var s = def.get("spawn", {}).get("position")
	return Vector3(s[0], 0.0, s[1]) if s is Array and s.size() >= 2 else null


## Apply the room's lighting to the scene's environment and fill light.
func apply_lighting(env: Environment, fill: DirectionalLight3D) -> void:
	var l: Dictionary = def.get("lighting", {})
	env.ambient_light_color = Color(l.get("ambient_color", "#8c8c99"))
	env.ambient_light_energy = l.get("ambient_energy", 0.2)
	fill.light_energy = l.get("fill_energy", 0.35)
	fill.light_color = Color(l.get("fill_color", "#fff2e0"))


func set_shown(shown: bool) -> void:
	visible = shown
	floor_body.collision_layer = (1 << 0) if shown else 0
	for b in _bodies:
		b.collision_layer = (1 << 0) if shown else 0


func _add_model(scene: Node3D, d: Dictionary) -> void:
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * float(d.get("scale", 1.0))
	holder.position = UserDefs.v3(d.get("offset"), Vector3.ZERO)
	holder.rotation_degrees = UserDefs.v3(d.get("rotation_deg"), Vector3.ZERO)
	holder.add_child(scene)
	_content.add_child(holder)
	var relight: bool = d.get("screen_light", true)
	var ambient: float = d.get("lighting", {}).get("surface_ambient", 0.07)
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if relight:
			for i in mi.mesh.get_surface_count():
				mi.set_surface_override_material(i, _relit(mi.get_active_material(i), ambient))
		if d.get("collision", true):
			# Lets the pointer place the TV on tables and shelves (layer 1: room).
			mi.create_trimesh_collision()
			for c in mi.get_children():
				if c is StaticBody3D:
					c.collision_layer = 1 << 0
					_bodies.append(c)


## A screen-lit copy of an imported material: keeps colour, texture, alpha
## cut-out and emission.
func _relit(m: Material, ambient: float) -> Material:
	var sm := ShaderMaterial.new()
	sm.shader = MODEL_SHADER
	sm.set_shader_parameter("ambient", ambient)
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		sm.set_shader_parameter("albedo", b.albedo_color)
		if b.albedo_texture:
			sm.set_shader_parameter("albedo_texture", b.albedo_texture)
		if b.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
			sm.set_shader_parameter("use_alpha_scissor", true)
			sm.set_shader_parameter("alpha_scissor", b.alpha_scissor_threshold)
		if b.emission_enabled:
			sm.set_shader_parameter("emission", b.emission)
			sm.set_shader_parameter("emission_energy", b.emission_energy_multiplier)
			if b.emission_texture:
				sm.set_shader_parameter("emission_texture", b.emission_texture)
	return sm


func _build_empty() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = ROOM_SHADER
	var box := BoxMesh.new()
	box.size = SIZE
	box.flip_faces = true
	# Vertex density for the per-vertex screen light (~8 cm grid).
	box.subdivide_width = 48
	box.subdivide_height = 32
	box.subdivide_depth = 60
	var walls := MeshInstance3D.new()
	walls.mesh = box
	walls.material_override = mat
	walls.position = Vector3(0, SIZE.y / 2.0, -1.0)
	_content.add_child(walls)

	var stand := MeshInstance3D.new()
	var stand_mat := ShaderMaterial.new()
	stand_mat.shader = ROOM_SHADER
	var stand_mesh := BoxMesh.new()
	stand_mesh.size = Vector3(0.9, STAND_TOP, 0.5)
	stand_mesh.subdivide_width = 18
	stand_mesh.subdivide_height = 10
	stand_mesh.subdivide_depth = 10
	stand.mesh = stand_mesh
	stand.material_override = stand_mat
	stand.position = Vector3(0, STAND_TOP / 2.0, -1.6)
	_content.add_child(stand)
