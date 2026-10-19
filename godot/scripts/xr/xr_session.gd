class_name XrSession
extends XROrigin3D
## OpenXR session: refresh rate, VR <-> passthrough, Meta scene (room setup)
## anchors, and the two Touch controllers with a pointing ray on the right.

signal passthrough_changed(enabled: bool)

const GLOW_ANCHOR_SCENE := preload("res://scenes/glow_anchor.tscn")
const RAY_LENGTH := 10.0

var xr: OpenXRInterface
var camera := XRCamera3D.new()
var left := XRController3D.new()
var right := XRController3D.new()
var ray := RayCast3D.new()
var passthrough := false
var scene_manager: Node

var _beam := MeshInstance3D.new()


static func try_start() -> OpenXRInterface:
	var i: OpenXRInterface = XRServer.find_interface("OpenXR")
	return i if i and i.is_initialized() else null


func _init(interface: OpenXRInterface) -> void:
	xr = interface


func _ready() -> void:
	var vp := get_viewport()
	vp.use_xr = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if RenderingServer.get_rendering_device():
		vp.vrs_mode = Viewport.VRS_XR

	add_child(camera)
	for c in [left, right]:
		c.pose = &"aim"
		add_child(c)
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.03, 0.03, 0.08)
		m.mesh = box
		c.add_child(m)
	left.tracker = &"left_hand"
	right.tracker = &"right_hand"

	ray.target_position = Vector3(0, 0, -RAY_LENGTH)
	ray.collision_mask = 0b11011  # room, real scene, UI, screen
	ray.collide_with_areas = false
	right.add_child(ray)
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(0.003, 0.003, 1.0)
	_beam.mesh = beam_mesh
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.albedo_color = Color(0.8, 0.9, 1.0)
	_beam.material_override = beam_mat
	right.add_child(_beam)

	if ClassDB.class_exists("OpenXRFbSceneManager"):
		scene_manager = ClassDB.instantiate("OpenXRFbSceneManager")
		scene_manager.set("default_scene", GLOW_ANCHOR_SCENE)
		scene_manager.set("scenes/global_mesh", GLOW_ANCHOR_SCENE)
		add_child(scene_manager)
		scene_manager.connect("openxr_fb_scene_data_missing", func(): scene_manager.call("request_scene_capture"))
		scene_manager.connect("openxr_fb_scene_capture_completed", _on_scene_capture_completed)

	xr.session_begun.connect(_on_session_begun)


func _process(_delta: float) -> void:
	var length := RAY_LENGTH
	if ray.is_colliding():
		length = ray.global_position.distance_to(ray.get_collision_point())
	_beam.scale = Vector3(1, 1, length)
	_beam.position = Vector3(0, 0, -length / 2.0)


func set_ray_visible(v: bool) -> void:
	_beam.visible = v


func supports_passthrough() -> bool:
	return XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in xr.get_supported_environment_blend_modes()


func set_passthrough(enable: bool, env: Environment) -> void:
	if not supports_passthrough():
		return
	passthrough = enable
	xr.environment_blend_mode = (XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND if enable
			else XRInterface.XR_ENV_BLEND_MODE_OPAQUE)
	get_viewport().transparent_bg = enable
	env.background_color = Color(0, 0, 0, 0) if enable else Color(0, 0, 0, 1)
	get_tree().call_group(&"real_scene", &"set_visible", enable)
	if scene_manager and enable and not scene_manager.call("are_scene_anchors_created"):
		scene_manager.call("create_scene_anchors")
	passthrough_changed.emit(enable)


func _on_session_begun() -> void:
	var rates: Array = xr.get_available_display_refresh_rates()
	print("VRT: refresh rates ", rates)
	if not rates.is_empty():
		var best: float = rates.max()
		xr.set_display_refresh_rate(best)
		Engine.physics_ticks_per_second = int(round(best))


func _on_scene_capture_completed(success: bool) -> void:
	if success:
		if scene_manager.call("are_scene_anchors_created"):
			scene_manager.call("remove_scene_anchors")
		scene_manager.call("create_scene_anchors")
