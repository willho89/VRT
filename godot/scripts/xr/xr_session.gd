class_name XrSession
extends XROrigin3D
## OpenXR session: refresh rate, VR <-> passthrough, Meta scene (room setup)
## anchors, and the two Touch controllers with a pointing ray on the right.

signal passthrough_changed(enabled: bool)

const GLOW_ANCHOR_SCENE := preload("res://scenes/glow_anchor.tscn")
const RAY_LENGTH := 10.0
## The pointer ray's layers: room, UI, screen; AR adds the real room's scene
## mesh (layer 2), which in VR would be invisible furniture blocking the TV.
const RAY_MASK_VR := 0b11001
const RAY_MASK_AR := 0b11011
## Room-mode locomotion (menu open, not pointing at it): left stick walks,
## right stick snap-turns around the head.
const WALK_SPEED := 1.4  # m/s
const SNAP_TURN_DEG := 30.0
## Where Recenter puts the viewer: this far in front of the TV, facing it.
const VIEW_DISTANCE := 1.5
## Eye-buffer widths offered by the Resolution setting. Absolute, because the
## runtime's recommended size varies (Quest 3 stock 1680x1760; tools like Quest
## Games Optimizer override it per app). Panels: Quest 3 2064x2208, Quest 2
## 1832x1920; lens distortion needs ~1.3x the stock size for 1:1 at the centre.
## The CRT mask and scanlines resolve from further away the higher this goes.
const EYE_WIDTHS := [1680, 2064, 2400, 2800]
const DEFAULT_EYE_WIDTH := 1
const QUEST2_EYE_WIDTHS := [1440, 1832, 2064, 2304]
## Quest 2 (XR2 Gen 1) defaults to its panel width and a 90 Hz cap for headroom.
const QUEST2_DEFAULT_EYE_WIDTH := 1
const QUEST2_MAX_HZ := 90.0

var xr: OpenXRInterface
var camera := XRCamera3D.new()
var left := XRController3D.new()
var right := XRController3D.new()
var ray := RayCast3D.new()
var passthrough := false
var is_quest2 := false
var scene_manager: Node

var _beam := MeshInstance3D.new()
## AR occlusion: real-world depth from the Quest 3 depth sensor written into
## the depth buffer, so real things in front of the TV (hands, furniture)
## hide it. Null where unsupported (Quest 2).
var _env_depth: Node3D
var _base_width := 0.0  # runtime-recommended eye width at multiplier 1
var _turn_held := false
## Display refresh the user asked for (Hz); 0 = the highest allowed.
var preferred_hz := 0.0


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

	# The OpenXR system name is still empty this early; Android's model is not.
	var model := OS.get_model_name()
	var system: String = xr.get_system_info().get("XRSystemName", "")
	is_quest2 = ("Quest 2" in model or "Quest2" in model or "Quest 2" in system
			or "Quest2" in system)
	print("VRT: device '%s', XR system '%s'%s" % [model, system, " (Quest 2 profile)" if is_quest2 else ""])
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
	ray.collision_mask = RAY_MASK_VR
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
	if ClassDB.class_exists("OpenXRMetaEnvironmentDepth"):
		_env_depth = ClassDB.instantiate("OpenXRMetaEnvironmentDepth")
		_env_depth.visible = false
		camera.add_child(_env_depth)


func _process(_delta: float) -> void:
	var length := RAY_LENGTH
	if ray.is_colliding():
		length = ray.global_position.distance_to(ray.get_collision_point())
	_beam.scale = Vector3(1, 1, length)
	_beam.position = Vector3(0, 0, -length / 2.0)


func eye_widths() -> Array:
	return QUEST2_EYE_WIDTHS if is_quest2 else EYE_WIDTHS


func default_eye_width() -> int:
	return QUEST2_DEFAULT_EYE_WIDTH if is_quest2 else DEFAULT_EYE_WIDTH


## The swapchain follows the multiplier on the next frame.
func set_eye_width(level: int) -> void:
	if _base_width <= 0.0:
		_base_width = xr.get_render_target_size().x / xr.render_target_size_multiplier
	var w: int = eye_widths()[clampi(level, 0, eye_widths().size() - 1)]
	xr.render_target_size_multiplier = w / maxf(_base_width, 1.0)
	print("VRT: eye width %d (runtime base %d, x%.3f)" % [w, _base_width, xr.render_target_size_multiplier])


## Smooth walk relative to where the head faces, plus snap turn.
func locomote(delta: float) -> void:
	var move := left.get_vector2("primary")
	if move.length() > 0.2:
		var fwd := -camera.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var right_dir := fwd.cross(Vector3.UP)
		global_position += (right_dir * move.x + fwd * move.y) * WALK_SPEED * delta
	var turn := right.get_vector2("primary").x
	if absf(turn) > 0.7 and not _turn_held:
		_turn_around_head(-signf(turn) * deg_to_rad(SNAP_TURN_DEG))
	_turn_held = absf(turn) > 0.4


## Move the play space so the head is at `spot` (floor height unchanged),
## looking toward `look_at_point`.
func place_viewer(spot: Vector3, look_at_point: Vector3) -> void:
	var fwd := -camera.global_transform.basis.z
	var want := look_at_point - spot
	if Vector2(fwd.x, fwd.z).length() > 0.01 and Vector2(want.x, want.z).length() > 0.01:
		_turn_around_head(Vector2(fwd.x, fwd.z).angle_to(Vector2(want.x, want.z)) * -1.0)
	var head := camera.global_position
	global_position += Vector3(spot.x - head.x, 0.0, spot.z - head.z)


func _turn_around_head(angle: float) -> void:
	var pivot := camera.global_position
	var t := Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO)
	global_transform = Transform3D.IDENTITY.translated(pivot) * t * Transform3D.IDENTITY.translated(-pivot) * global_transform


## Where the pointer ray meets only the given layers (ignoring anything in
## front), or {} for a miss. Keys: position, collider.
func ray_hit(mask: int) -> Dictionary:
	var from := ray.global_position
	var to := ray.to_global(ray.target_position)
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	return get_world_3d().direct_space_state.intersect_ray(q)


func set_ray_visible(v: bool) -> void:
	_beam.visible = v


func supports_passthrough() -> bool:
	return XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in xr.get_supported_environment_blend_modes()


func set_passthrough(enable: bool, env: Environment) -> void:
	if not supports_passthrough():
		return
	passthrough = enable
	ray.collision_mask = RAY_MASK_AR if enable else RAY_MASK_VR
	xr.environment_blend_mode = (XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND if enable
			else XRInterface.XR_ENV_BLEND_MODE_OPAQUE)
	get_viewport().transparent_bg = enable
	env.background_color = Color(0, 0, 0, 0) if enable else Color(0, 0, 0, 1)
	get_tree().call_group(&"real_scene", &"set_visible", enable)
	_set_occlusion(enable)
	if scene_manager and enable and not scene_manager.call("are_scene_anchors_created"):
		scene_manager.call("create_scene_anchors")
	passthrough_changed.emit(enable)


func _on_session_begun() -> void:
	print("VRT: refresh rates ", xr.get_available_display_refresh_rates())
	apply_refresh()


## Refresh rates this headset offers (Quest 2 capped for headroom).
func refresh_rates() -> Array:
	var rates: Array = xr.get_available_display_refresh_rates()
	if is_quest2:
		rates = rates.filter(func(r): return r <= QUEST2_MAX_HZ)
	rates.sort()
	return rates


func set_preferred_hz(hz: float) -> void:
	preferred_hz = hz
	apply_refresh()


func apply_refresh() -> void:
	var rates := refresh_rates()
	if rates.is_empty():
		return
	var hz: float = rates.max()
	if preferred_hz > 0.0:
		for r in rates:
			if absf(r - preferred_hz) < 1.0:
				hz = r
	xr.set_display_refresh_rate(hz)
	Engine.physics_ticks_per_second = int(round(hz))


func _set_occlusion(enable: bool) -> void:
	if _env_depth == null or not Engine.has_singleton("OpenXRMetaEnvironmentDepthExtension"):
		return
	var ext: Object = Engine.get_singleton("OpenXRMetaEnvironmentDepthExtension")
	if not ext.call("is_environment_depth_supported"):
		return
	if enable and not ext.call("is_environment_depth_started"):
		ext.call("start_environment_depth")
	elif not enable and ext.call("is_environment_depth_started"):
		ext.call("stop_environment_depth")
	_env_depth.visible = enable
	print("VRT: AR occlusion ", "on" if enable else "off")


func _on_scene_capture_completed(success: bool) -> void:
	if success:
		if scene_manager.call("are_scene_anchors_created"):
			scene_manager.call("remove_scene_anchors")
		scene_manager.call("create_scene_anchors")
