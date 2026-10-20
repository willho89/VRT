extends SceneTree
## Generates examples/rooms/den/den.glb: a small den built from boxes, as a
## starting point for custom rooms (open it in Blender, replace, re-export).
## Run: godot --headless -s tools/make_example_room.gd -- <out.glb>

func _box(root: Node3D, name: String, size: Vector3, pos: Vector3, color: Color, emit := Color(0, 0, 0)) -> void:
	var m := MeshInstance3D.new()
	m.name = name
	var b := BoxMesh.new()
	b.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	if emit != Color(0, 0, 0):
		mat.emission_enabled = true
		mat.emission = emit
		mat.emission_energy_multiplier = 1.0
	b.material = mat
	m.mesh = b
	m.position = pos
	root.add_child(m)
	m.owner = root

func _init():
	var root := Node3D.new()
	root.name = "Den"
	var wall := Color(0.62, 0.55, 0.45)
	_box(root, "Floor", Vector3(4.2, 0.02, 4.6), Vector3(0, -0.01, -0.5), Color(0.33, 0.22, 0.14))
	_box(root, "WallBack", Vector3(4.2, 2.6, 0.1), Vector3(0, 1.3, -2.8), wall)
	_box(root, "WallLeft", Vector3(0.1, 2.6, 4.6), Vector3(-2.1, 1.3, -0.5), wall)
	_box(root, "WallRight", Vector3(0.1, 2.6, 4.6), Vector3(2.1, 1.3, -0.5), wall)
	_box(root, "Ceiling", Vector3(4.2, 0.05, 4.6), Vector3(0, 2.62, -0.5), Color(0.8, 0.78, 0.74))
	_box(root, "Rug", Vector3(2.0, 0.01, 1.4), Vector3(0, 0.005, -0.9), Color(0.45, 0.12, 0.12))
	# TV table: top at 0.62 m, centred at z = -2.3.
	_box(root, "TableTop", Vector3(1.1, 0.04, 0.55), Vector3(0, 0.6, -2.3), Color(0.25, 0.16, 0.09))
	for x in [-0.5, 0.5]:
		_box(root, "TableLeg", Vector3(0.05, 0.58, 0.45), Vector3(x, 0.29, -2.3), Color(0.22, 0.14, 0.08))
	_box(root, "CouchSeat", Vector3(1.8, 0.42, 0.8), Vector3(0, 0.21, 0.9), Color(0.2, 0.3, 0.42))
	_box(root, "CouchBack", Vector3(1.8, 0.45, 0.2), Vector3(0, 0.62, 1.25), Color(0.2, 0.3, 0.42))
	_box(root, "LampPole", Vector3(0.04, 1.4, 0.04), Vector3(1.7, 0.7, -2.4), Color(0.1, 0.1, 0.1))
	_box(root, "LampShade", Vector3(0.3, 0.25, 0.3), Vector3(1.7, 1.45, -2.4), Color(0.9, 0.8, 0.6), Color(1.0, 0.75, 0.45))
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_scene(root, state)
	var out: String = OS.get_cmdline_user_args()[0]
	print("wrote ", out, ": ", doc.write_to_filesystem(state, out))
	quit()
