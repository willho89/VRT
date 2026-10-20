class_name TvMover
extends Node
## Placing the TV anywhere: grab it with a controller, or nudge it from the
## TV PLACEMENT page of its OSD. Placement is saved separately for the VR room
## and for AR (the real room), including scale.
##
## In AR the set is also pinned to a persistent Meta spatial anchor, so it
## stays put in the real room across sessions, recentering and guardian
## changes. AR placements are kept relative to the XR origin (anchors live
## there too), since walking in the VR room moves the origin.
##
## Grab: point at the set and hold the right grip (the left grip walks). The set follows the hand, kept
## upright; while held, right stick Y pushes/pulls, right stick X turns,
## left stick Y tilts; holding the other grip too scales it by the change in
## distance between the hands.

signal moved

const PUSH_SPEED := 1.2      # m/s at full stick
const TURN_SPEED := 90.0     # deg/s
const TILT_SPEED := 40.0     # deg/s
const MAX_TILT := 60.0
const SCALE_RANGE := Vector2(0.4, 2.5)
const STICK_DEADZONE := 0.25

var tv: Tv
var xr: XrSession
var settings: VrtSettings
var default_transform := Transform3D.IDENTITY
var grabbing := false

var _hand: XRController3D
var _offset := Transform3D.IDENTITY   # TV origin relative to the hand, yaw only
var _yaw := 0.0                       # TV yaw (radians) while held
var _tilt := 0.0                      # TV pitch (radians)
var _scale := 1.0
var _two_hand_d0 := 0.0
var _two_hand_s0 := 1.0
var _anchor: XRAnchor3D
var _anchor_entity: RefCounted        # OpenXRFbSpatialEntity
var _anchor_scale := 1.0
const STORAGE_LOCAL := 0              # OpenXRFbSpatialEntity.STORAGE_LOCAL
const COMPONENT_STORABLE := 1         # OpenXRFbSpatialEntity.COMPONENT_TYPE_STORABLE
## Re-anchor once the set has been still this long (nudges arrive in bursts).
const REANCHOR_DELAY := 1.0
var _reanchor_t := 0.0


func _init(t: Tv, x: XrSession, s: VrtSettings) -> void:
	tv = t
	xr = x
	settings = s
	default_transform = t.global_transform


## Restore the saved placement for the current mode (VR room or AR).
func load_placement() -> void:
	var saved = settings.get_value("tv", _key(), false)  # (a null default means "none" to ConfigFile)
	if saved is Transform3D:
		tv.global_transform = _from_stored(saved)
	else:
		tv.global_transform = default_transform
	if _ar():
		_load_anchor()


func save() -> void:
	settings.set_value("tv", _key(), _to_stored(tv.global_transform))
	if _ar():
		if _anchors_supported():
			_drop_anchor()  # stop following the old pose right away
			_reanchor_t = REANCHOR_DELAY
		else:
			print("VRT: TV anchor: spatial anchors not supported here")
	moved.emit()


func _process(delta: float) -> void:
	if _reanchor_t > 0.0 and not grabbing:
		_reanchor_t -= delta
		if _reanchor_t <= 0.0 and _ar():
			_reanchor()
	# Follow the anchor: the real room is the reference, not the play space.
	if _ar() and not grabbing and _anchor and _anchor.get_has_tracking_data():
		var a := _anchor.global_transform
		tv.global_transform = Transform3D(a.basis.scaled_local(Vector3.ONE * _anchor_scale), a.origin)


func reset_to_stand() -> void:
	tv.global_transform = default_transform
	save()


## Turn the set to face the viewer (yaw only, tilt kept).
func face_viewer() -> void:
	if xr == null:
		return
	var to_user := (xr.camera.global_position - tv.global_position) * Vector3(1, 0, 1)
	if to_user.length() > 0.01:
		_set_pose(tv.global_position, atan2(to_user.x, to_user.z), tilt(), scale_factor())
		save()


## Fine adjustment from the OSD: what is one of height/distance/yaw/tilt/scale.
func nudge(what: String, dir: int) -> void:
	var pos := tv.global_position
	var yaw := yaw_angle()
	var t := tilt()
	var s := scale_factor()
	match what:
		"height":
			pos.y += 0.01 * dir
		"distance":
			var away := Vector3(sin(yaw), 0, cos(yaw)) * -1.0  # behind the screen
			pos += away * 0.02 * dir
		"left_right":
			pos += Vector3(cos(yaw), 0, -sin(yaw)) * 0.02 * dir
		"yaw":
			yaw += deg_to_rad(2.0) * dir
		"tilt":
			t = clampf(t + deg_to_rad(1.0) * dir, -deg_to_rad(MAX_TILT), deg_to_rad(MAX_TILT))
		"scale":
			s = clampf(s * (1.0 + 0.05 * dir), SCALE_RANGE.x, SCALE_RANGE.y)
	_set_pose(pos, yaw, t, s)
	save()


func yaw_angle() -> float:
	var f := tv.global_transform.basis.z
	return atan2(f.x, f.z)


func tilt() -> float:
	var f := tv.global_transform.basis.z.normalized()
	return asin(clampf(f.y, -1.0, 1.0))  # + faces the screen upward


func scale_factor() -> float:
	return tv.global_transform.basis.get_scale().x


## Called every frame with the screen-pointing state. allowed: grabbing is
## permitted now (a menu is up or nothing is playing, so grip is not R2).
func update(delta: float, pointing_at_tv: bool, allowed: bool) -> void:
	if xr == null:
		return
	if not grabbing:
		if allowed and pointing_at_tv and xr.right.is_button_pressed("grip_click"):
			_begin(xr.right)
		return
	if not _hand.is_button_pressed("grip_click"):
		grabbing = false
		save()
		return

	var other := xr.left if _hand == xr.right else xr.right
	var both := other.is_button_pressed("grip_click")
	var d := _hand.global_position.distance_to(other.global_position)
	if both:
		if _two_hand_d0 <= 0.0:
			_two_hand_d0 = maxf(d, 0.05)
			_two_hand_s0 = _scale
		_scale = clampf(_two_hand_s0 * d / _two_hand_d0, SCALE_RANGE.x, SCALE_RANGE.y)
	else:
		_two_hand_d0 = 0.0

	var rs := _hand.get_vector2("primary")
	if absf(rs.y) > STICK_DEADZONE:
		_offset.origin.z -= rs.y * PUSH_SPEED * delta
		_offset.origin.z = minf(_offset.origin.z, -0.2)
	if absf(rs.x) > STICK_DEADZONE:
		_yaw -= deg_to_rad(rs.x * TURN_SPEED * delta)
	var ls := other.get_vector2("primary")
	if absf(ls.y) > STICK_DEADZONE:
		_tilt = clampf(_tilt + deg_to_rad(ls.y * TILT_SPEED * delta), -deg_to_rad(MAX_TILT), deg_to_rad(MAX_TILT))

	var hand_yaw := _hand_yaw()
	var frame := Transform3D(Basis(Vector3.UP, hand_yaw), _hand.global_position)
	_set_pose((frame * _offset).origin, hand_yaw + _yaw, _tilt, _scale)


func _begin(hand: XRController3D) -> void:
	grabbing = true
	_hand = hand
	_two_hand_d0 = 0.0
	_scale = scale_factor()
	_tilt = tilt()
	var hand_yaw := _hand_yaw()
	_yaw = yaw_angle() - hand_yaw
	var frame := Transform3D(Basis(Vector3.UP, hand_yaw), hand.global_position)
	_offset = Transform3D(Basis.IDENTITY, frame.affine_inverse() * tv.global_position)


## The hand's heading, ignoring wrist pitch and roll.
func _hand_yaw() -> float:
	var f := -_hand.global_transform.basis.z
	return atan2(-f.x, -f.z)


func _set_pose(pos: Vector3, yaw: float, pitch: float, s: float) -> void:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch)
	tv.global_transform = Transform3D(b.scaled_local(Vector3.ONE * s), pos)


func _key() -> String:
	return "placement_ar" if _ar() else "placement_vr"


func _ar() -> bool:
	return xr != null and xr.passthrough


func _to_stored(t: Transform3D) -> Transform3D:
	return xr.global_transform.affine_inverse() * t if _ar() else t


func _from_stored(t: Transform3D) -> Transform3D:
	return xr.global_transform * t if _ar() else t


func _anchors_supported() -> bool:
	if not ClassDB.class_exists("OpenXRFbSpatialEntity") or not Engine.has_singleton("OpenXRFbSpatialEntityStorageExtension"):
		return false
	return Engine.get_singleton("OpenXRFbSpatialEntityStorageExtension").call("is_spatial_entity_storage_supported")


func _load_anchor() -> void:
	var uuid: String = settings.get_value("tv", "anchor_uuid", "")
	print("VRT: TV anchor: load '%s' supported=%s" % [uuid, _anchors_supported()])
	if uuid == "" or not _anchors_supported() or _anchor_entity:
		return
	var q: RefCounted = ClassDB.instantiate("OpenXRFbSpatialEntityQuery")
	q.call("query_by_uuid", [StringName(uuid)], STORAGE_LOCAL)
	q.connect("openxr_fb_spatial_entity_query_completed", func(results: Array):
		if results.is_empty():
			print("VRT: TV anchor %s not found" % uuid)
		else:
			print("VRT: TV anchor found ", uuid)
			_track(results[0]))
	q.call("execute")


## Replace the anchor with one at the set's current pose.
func _reanchor() -> void:
	if not _anchors_supported():
		return
	_drop_anchor()
	var t := tv.global_transform
	_anchor_scale = t.basis.get_scale().x
	var rigid := xr.global_transform.affine_inverse() * Transform3D(t.basis.orthonormalized(), t.origin)
	var entity: RefCounted = ClassDB.class_call_static("OpenXRFbSpatialEntity", "create_spatial_anchor", rigid)
	print("VRT: TV anchor: creating at ", rigid.origin, " -> ", entity)
	if entity == null:
		return
	entity.connect("openxr_fb_spatial_entity_created", func(ok: bool):
		if not ok:
			print("VRT: TV anchor create failed")
			return
		entity.connect("openxr_fb_spatial_entity_saved", func(saved: bool, _loc):
			if saved:
				settings.set_value("tv", "anchor_uuid", str(entity.get("uuid")))
				print("VRT: TV anchored ", entity.get("uuid"))
			else:
				print("VRT: TV anchor save failed"))
		# Saving needs the storable component switched on first.
		entity.connect("openxr_fb_spatial_entity_set_component_enabled_completed",
				func(enabled_ok: bool, component: int, _enabled: bool):
					if component != COMPONENT_STORABLE:
						return
					if enabled_ok:
						entity.call("save_to_storage", STORAGE_LOCAL)
					else:
						print("VRT: TV anchor: storable component refused"))
		entity.call("set_component_enabled", COMPONENT_STORABLE, true)
		_track(entity))


func _track(entity: RefCounted) -> void:
	_anchor_entity = entity
	_anchor_scale = settings.get_value("tv", "placement_ar", Transform3D()).basis.get_scale().x
	entity.call("track")
	_anchor = XRAnchor3D.new()
	_anchor.tracker = StringName(str(entity.get("uuid")))
	xr.add_child(_anchor)


func _drop_anchor() -> void:
	if _anchor_entity:
		_anchor_entity.call("untrack")
		_anchor_entity.call("erase_from_storage", STORAGE_LOCAL)
		_anchor_entity.call("destroy")
		_anchor_entity = null
	if _anchor:
		_anchor.queue_free()
		_anchor = null
