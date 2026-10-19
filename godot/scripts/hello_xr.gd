extends Node3D
## M0 spike: XR startup, refresh-rate control, VR room <-> AR passthrough, and
## CRT light spill onto both the virtual room and the real (Meta scene) room.
##
## Controls (Touch):
##   Left Y      toggle passthrough (Quest 3)
##   Left X      cycle display refresh rate
##   Left menu   re-run Meta room setup (scene capture)
##   Right trig  move the TV to where the right controller points
## Without a headset it runs flat on the desktop for quick checks.

const ROOM_SIZE := Vector3(4.0, 2.8, 5.0)
const TV_SCREEN_HALF := Vector2(0.25, 0.19)  # ~20" 4:3 face, metres
const SCREEN_NITS_SCALE := 2.0  # radiance units fed to the light function

const GLOW_ANCHOR_SCENE := preload("res://scenes/glow_anchor.tscn")
const ROOM_SHADER := preload("res://shaders/room_lit.gdshader")
const PATTERN_SHADER := preload("res://shaders/test_pattern.gdshader")

var xr_interface: OpenXRInterface
var passthrough := false

var _origin: XROrigin3D
var _left: XRController3D
var _right: XRController3D
var _ray: RayCast3D
var _hud: Label3D
var _env: Environment
var _room: Node3D
var _tv: Node3D
var _screen_mat: ShaderMaterial
var _scene_manager: Node
var _time := 0.0
var _fps_accum := 0.0
var _fps_frames := 0


func _ready() -> void:
	_build_environment()
	_build_room()
	_build_tv()

	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		_start_xr()
	else:
		print("VRT: OpenXR not available, running flat")
		var cam := Camera3D.new()
		cam.position = Vector3(0.0, 1.2, 0.3)
		add_child(cam)
		cam.look_at(_tv.global_position + Vector3(0, 0.1, 0))


func _start_xr() -> void:
	var vp := get_viewport()
	vp.use_xr = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if RenderingServer.get_rendering_device():
		vp.vrs_mode = Viewport.VRS_XR

	_origin = XROrigin3D.new()
	add_child(_origin)
	var cam := XRCamera3D.new()
	_origin.add_child(cam)

	_left = _make_controller(&"left_hand")
	_right = _make_controller(&"right_hand")
	_left.button_pressed.connect(_on_left_button)
	_right.button_pressed.connect(_on_right_button)

	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0, 0, -10)
	_ray.collision_mask = 0b11
	_right.add_child(_ray)
	var beam := MeshInstance3D.new()
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(0.004, 0.004, 1.0)
	beam.mesh = beam_mesh
	beam.position = Vector3(0, 0, -0.5)
	_right.add_child(beam)

	_hud = Label3D.new()
	_hud.pixel_size = 0.0007
	_hud.font_size = 32
	_hud.outline_size = 8
	_hud.position = Vector3(0, 0.06, -0.12)
	_hud.rotation_degrees = Vector3(-50, 0, 0)
	_left.add_child(_hud)

	# Meta scene (room setup) anchors: every surface gets the AR glow material.
	if ClassDB.class_exists("OpenXRFbSceneManager"):
		_scene_manager = ClassDB.instantiate("OpenXRFbSceneManager")
		_scene_manager.set("default_scene", GLOW_ANCHOR_SCENE)
		_scene_manager.set("scenes/global_mesh", GLOW_ANCHOR_SCENE)
		_origin.add_child(_scene_manager)
		_scene_manager.connect("openxr_fb_scene_data_missing", _on_scene_data_missing)
		_scene_manager.connect("openxr_fb_scene_capture_completed", _on_scene_capture_completed)

	xr_interface.session_begun.connect(_on_session_begun)


func _make_controller(tracker: StringName) -> XRController3D:
	var c := XRController3D.new()
	c.tracker = tracker
	c.pose = &"aim"
	_origin.add_child(c)
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.03, 0.03, 0.08)
	m.mesh = box
	c.add_child(m)
	return c


func _on_session_begun() -> void:
	var rates: Array = xr_interface.get_available_display_refresh_rates()
	print("VRT: refresh rates available: ", rates)
	if not rates.is_empty():
		_set_refresh_rate(rates.max())
	var modes: Array = xr_interface.get_supported_environment_blend_modes()
	print("VRT: blend modes: ", modes)


func _set_refresh_rate(rate: float) -> void:
	xr_interface.set_display_refresh_rate(rate)
	Engine.physics_ticks_per_second = int(round(rate))
	print("VRT: refresh rate -> ", rate)


func _on_left_button(button: String) -> void:
	match button:
		"by_button":
			_set_passthrough(not passthrough)
		"ax_button":
			var rates: Array = xr_interface.get_available_display_refresh_rates()
			if rates.is_empty():
				return
			rates.sort()
			var i := rates.find(xr_interface.get_display_refresh_rate())
			_set_refresh_rate(rates[(i + 1) % rates.size()])
		"menu_button":
			if _scene_manager:
				_scene_manager.call("request_scene_capture")


func _on_right_button(button: String) -> void:
	if button == "trigger_click" and _ray.is_colliding():
		var p := _ray.get_collision_point()
		var to_user := (_origin.global_position - p) * Vector3(1, 0, 1)
		var n := _ray.get_collision_normal()
		if n.dot(Vector3.UP) > 0.7:
			_tv.global_position = p
		else:
			# Pointing at a wall: stand the TV on the floor in front of it.
			_tv.global_position = Vector3(p.x, 0.0, p.z) + n * 0.3
		if to_user.length() > 0.01:
			_tv.look_at(_tv.global_position - to_user, Vector3.UP)


func _set_passthrough(enable: bool) -> void:
	var modes: Array = xr_interface.get_supported_environment_blend_modes()
	if not XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in modes:
		print("VRT: passthrough not supported")
		return
	passthrough = enable
	xr_interface.environment_blend_mode = (XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND if enable
			else XRInterface.XR_ENV_BLEND_MODE_OPAQUE)
	get_viewport().transparent_bg = enable
	_env.background_color = Color(0, 0, 0, 0) if enable else Color(0, 0, 0, 1)
	_room.visible = not enable
	get_tree().call_group(&"real_scene", &"set_visible", enable)
	if _scene_manager:
		if enable and not _scene_manager.call("are_scene_anchors_created"):
			_scene_manager.call("create_scene_anchors")


func _on_scene_data_missing() -> void:
	print("VRT: no room setup data, requesting scene capture")
	_scene_manager.call("request_scene_capture")


func _on_scene_capture_completed(success: bool) -> void:
	if success:
		if _scene_manager.call("are_scene_anchors_created"):
			_scene_manager.call("remove_scene_anchors")
		_scene_manager.call("create_scene_anchors")


func _build_environment() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color.BLACK
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)


func _build_room() -> void:
	_room = Node3D.new()
	add_child(_room)
	var mat := ShaderMaterial.new()
	mat.shader = ROOM_SHADER
	var box := BoxMesh.new()
	box.size = ROOM_SIZE
	box.flip_faces = true
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = mat
	mi.position = Vector3(0, ROOM_SIZE.y / 2.0, -1.0)
	_room.add_child(mi)

	# Floor collider for TV placement in VR.
	var body := StaticBody3D.new()
	body.collision_layer = 0b01
	var shape := CollisionShape3D.new()
	var plane := WorldBoundaryShape3D.new()
	shape.shape = plane
	body.add_child(shape)
	_room.add_child(body)

	# A low stand for the TV.
	var stand := MeshInstance3D.new()
	var stand_mesh := BoxMesh.new()
	stand_mesh.size = Vector3(0.9, 0.55, 0.5)
	stand.mesh = stand_mesh
	stand.material_override = mat
	stand.position = Vector3(0, 0.275, -1.6)
	_room.add_child(stand)


func _build_tv() -> void:
	_tv = Node3D.new()
	_tv.position = Vector3(0, 0.55, -1.6)
	add_child(_tv)

	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.62, 0.5, 0.48)
	body.mesh = body_mesh
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.06, 0.06, 0.065)
	body_mat.roughness = 0.6
	body.material_override = body_mat
	body.position = Vector3(0, 0.25, 0)
	_tv.add_child(body)

	var screen := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = TV_SCREEN_HALF * 2.0
	screen.mesh = quad
	_screen_mat = ShaderMaterial.new()
	_screen_mat.shader = PATTERN_SHADER
	screen.material_override = _screen_mat
	screen.position = Vector3(0, 0.26, 0.241)
	screen.name = "Screen"
	_tv.add_child(screen)


func _process(delta: float) -> void:
	_time += delta
	_screen_mat.set_shader_parameter("pattern_time", _time)

	var screen: Node3D = _tv.get_node("Screen")
	var b := screen.global_transform.basis
	RenderingServer.global_shader_parameter_set("VRT_SCREEN_CENTER", screen.global_position)
	RenderingServer.global_shader_parameter_set("VRT_SCREEN_RIGHT", b.x.normalized() * TV_SCREEN_HALF.x)
	RenderingServer.global_shader_parameter_set("VRT_SCREEN_UP", b.y.normalized() * TV_SCREEN_HALF.y)
	var c := _pattern_color(_time)
	RenderingServer.global_shader_parameter_set("VRT_SCREEN_RADIANCE",
			Vector3(c.r, c.g, c.b) * SCREEN_NITS_SCALE)

	_fps_accum += delta
	_fps_frames += 1
	if _fps_accum >= 0.5 and _hud:
		var fps := _fps_frames / _fps_accum
		_fps_accum = 0.0
		_fps_frames = 0
		_hud.text = "VRT M0\n%.0f fps @ %.0f Hz\n%s\n[Y] passthrough  [X] Hz\n[Menu] room setup  [Trig] place TV" % [
				fps, xr_interface.get_display_refresh_rate(), "AR" if passthrough else "VR"]


## Average color of the test pattern, mirroring test_pattern.gdshader.
func _pattern_color(t: float) -> Color:
	var slot := int(fmod(floor(t / 2.0), 6.0))
	match slot:
		0: return Color(1, 0, 0)
		1: return Color(0, 1, 0)
		2: return Color(0, 0, 1)
		3: return Color(1, 1, 1)
		4: return Color(0, 0, 0)
	return Color(0.75, 0.75, 0.75) * (4.0 / 7.0)
