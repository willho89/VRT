extends Node3D
## VRT application root. Builds the world, picks XR or flat desktop mode, and
## wires the libretro host, input and menu together.

const MENU_SIZE := Vector2i(1280, 800)
const POINTER_CORES := ["deevee"]  # cores driven by pointing at the screen
const STATS_INTERVAL := 5.0

var settings := VrtSettings.new()
var library := ContentLibrary.new()
var env := Environment.new()
var room := Room.new()
var tv := Tv.new()
var host := RetroHost.new()
var router := InputRouter.new()
var menu := MainMenu.new()

var xr_session: XrSession
var _flat_cam: FlatCamera
var menu_panel: MenuPanel3D
var menu_layer: CanvasLayer
var menu_visible := false
var tv_menu: TvMenu

var _trigger_was := false
var _stats_t := 0.0
var _frames_seen := 0
var _frames_skipped := 0
## --log-fields: print the field sequence the core delivers (interlace debugging).
var _log_fields := "--log-fields" in OS.get_cmdline_user_args()
var _field_log := ""


func _ready() -> void:
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	# Dim fill so the cabinet reads in the dark room (the CRT stays the key light).
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.ambient_light_energy = 0.2
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.35
	fill.light_color = Color(1.0, 0.95, 0.88)
	fill.rotation_degrees = Vector3(-45, 30, 0)
	add_child(fill)
	add_child(room)
	# Centre the cabinet's depth on the stand (front face at the origin of Tv).
	tv.position = Vector3(0, Room.STAND_TOP, -1.6 + CabinetVcrCombo.D * CabinetVcrCombo.MM * 0.5)
	add_child(tv)
	add_child(host)
	router.host = host
	add_child(router)
	router.menu_toggled.connect(func(): set_menu_visible(not menu_visible))

	menu.launch.connect(_on_launch)
	menu.action.connect(_on_action)
	host.content_started.connect(func(e): menu.set_status("Playing: %s  (%s)" % [e.title, e.system]))
	host.content_started.connect(func(e): tv.pipeline.set_system(e.core))
	host.content_failed.connect(func(msg): menu.set_status("Could not start: " + msg); set_menu_visible(true))

	var xr := XrSession.try_start()
	if xr:
		xr_session = XrSession.new(xr)
		add_child(xr_session)
		router.bind_controllers(xr_session.left, xr_session.right)
		menu_panel = MenuPanel3D.new(menu, MENU_SIZE)
		add_child(menu_panel)
		menu_panel.use_composition_layer(xr_session)
		xr.pose_recentered.connect(_place_viewer)
		xr.session_begun.connect(func(): get_tree().create_timer(1.0).timeout.connect(_place_viewer))
		menu.set_action_visible("passthrough", xr_session.supports_passthrough())
	else:
		print("VRT: no OpenXR, flat desktop mode")
		_flat_cam = FlatCamera.new()
		add_child(_flat_cam)
		_flat_cam.target = tv.screen.global_position
		menu_layer = CanvasLayer.new()
		add_child(menu_layer)
		menu.font_size = 20
		menu_layer.add_child(menu)
		menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 40)
		menu.set_action_visible("passthrough", false)
		menu.set_action_visible("recenter", false)

	tv_menu = TvMenu.new(settings, tv, xr_session)
	router.tv_menu_toggled.connect(_toggle_tv_menu)
	router.osd_button.connect(tv.osd.press)
	host.content_started.connect(func(_e): tv_menu.show_input_banner())
	_request_storage_access()
	rescan()
	set_menu_visible(true)
	# Smoke tests: --launch=<part of a title> starts the first match;
	# --shot=<png path> saves a screenshot after 8 s, --menu=0 hides the menu.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			# --shot=<png>[@seconds], default 8 s after start
			var spec := a.trim_prefix("--shot=").split("@")
			var path := spec[0]
			var when := spec[1].to_float() if spec.size() > 1 else 8.0
			get_tree().create_timer(when).timeout.connect(func():
				get_viewport().get_texture().get_image().save_png(path)
				# Also the signal stage's raw output, for decoder tuning.
				var sig := tv.pipeline.signal_texture().get_image()
				if sig:
					sig.save_png(path.get_basename() + "-signal.png")
				print("VRT: screenshot ", path))
		if a == "--menu=0":
			set_menu_visible.call_deferred(false)
		if a == "--tvmenu":
			tv_menu.open.call_deferred()
		if a.begins_with("--input="):
			router.set_script_input(a.trim_prefix("--input="))
		if a.begins_with("--cam=") and _flat_cam:
			# distance_m,yaw_deg,pitch_deg[,offset_x_mm,offset_y_mm] from the screen centre
			var v := a.trim_prefix("--cam=").split_floats(",")
			_flat_cam.distance = v[0]
			_flat_cam.yaw = deg_to_rad(v[1]) if v.size() > 1 else 0.0
			_flat_cam.pitch = deg_to_rad(v[2]) if v.size() > 2 else 0.0
			if v.size() > 4:
				_flat_cam.target += Vector3(v[3], v[4], 0.0) / 1000.0
			_flat_cam._apply()
		if a.begins_with("--launch="):
			var want := a.trim_prefix("--launch=").to_lower()
			for e in library.entries:
				if want in e.title.to_lower():
					_on_launch(e)
					break


func rescan() -> void:
	library.scan(settings.content_roots())
	print("VRT: library has %d entries in %s" % [library.entries.size(), library.systems()])
	menu.set_library(library)


func set_menu_visible(v: bool) -> void:
	menu_visible = v
	router.menu_open = v
	if menu_panel:
		menu_panel.set_active(v)
		if v:
			_place_menu_in_view()
	else:
		menu.visible = v
	if v:
		menu.focus_default()


func _place_menu_in_view() -> void:
	var cam := xr_session.camera.global_transform
	var fwd := -cam.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	menu_panel.global_position = cam.origin + fwd * 0.9 + Vector3(0, -0.15, 0)
	# -Z points away from the user, so the quad's +Z front faces them.
	menu_panel.look_at(menu_panel.global_position + fwd, Vector3.UP)


func _process(delta: float) -> void:
	var tex := host.video_texture() if host.is_running() else null
	var n := host.take_new_frames() if tex else 0
	tv.show_frame(tex, host.libretro.call("GetVideoImage") if tex else null, host.video_field(), n, delta)
	router.osd_open = tv.osd.is_open
	# The core's sound (an AudioStreamPlayer3D under the Libretro node) plays
	# from the set, so it follows the TV when it is moved.
	host.libretro.global_transform = tv.speaker_transform()
	_frames_seen += n
	if _log_fields and n > 0 and _field_log.length() < 600:
		_field_log += str(host.video_field()) + ("" if n == 1 else "(+%d)" % (n - 1))
		if _field_log.length() >= 600:
			print("VRT fields: ", _field_log)
	_frames_skipped += maxi(n - 1, 0)
	if xr_session:
		var on_menu := _handle_ray()
		if menu_visible and on_menu:
			var stick := xr_session.right.get_vector2("primary").y + xr_session.left.get_vector2("primary").y
			if absf(stick) > 0.2:
				menu.scroll(-stick * delta * 12.0)
		elif menu_visible and not xr_session.passthrough:
			xr_session.locomote(delta)
	_log_stats(delta)


## Returns true while the ray is on the menu panel.
func _handle_ray() -> bool:
	var r := xr_session.ray
	var trigger := xr_session.right.is_button_pressed("trigger_click")
	var pressed_edge := trigger and not _trigger_was
	_trigger_was = trigger
	var collider := r.get_collider() if r.is_colliding() else null
	var point := r.get_collision_point() if collider else Vector3.ZERO

	if menu_visible:
		if menu_panel.handle_ray(point, collider, trigger):
			return true
		# Pointing past the menu at the room or a real surface: place the TV.
		if pressed_edge and collider and collider != tv.screen_body:
			_place_tv(point, r.get_collision_normal())
		return false
	if collider == tv.screen_body and host.is_running() and host.current.core in POINTER_CORES:
		host.set_pointer(0, tv.screen_uv(point), trigger)
	return false


## VR room only: stand the viewer in front of the TV, facing it. In AR the
## room is real, so nothing moves.
func _place_viewer() -> void:
	if xr_session == null or xr_session.passthrough:
		return
	var facing := tv.global_transform.basis.z * Vector3(1, 0, 1)
	var spot := tv.global_position + facing.normalized() * XrSession.VIEW_DISTANCE
	xr_session.place_viewer(spot, tv.global_position)
	if menu_visible:
		_place_menu_in_view()


func _place_tv(p: Vector3, normal: Vector3) -> void:
	var to_user := (xr_session.camera.global_position - p) * Vector3(1, 0, 1)
	tv.global_position = p if normal.dot(Vector3.UP) > 0.7 else Vector3(p.x, 0.0, p.z) + normal * 0.3
	if to_user.length() > 0.01:
		tv.look_at(tv.global_position - to_user, Vector3.UP)


func _on_launch(entry: ContentLibrary.Entry) -> void:
	host.start(entry)
	if host.is_running():
		set_menu_visible(false)


func _on_action(name: String) -> void:
	match name:
		"resume":
			if host.is_running():
				set_menu_visible(false)
		"stop":
			host.stop()
			menu.set_status("Stopped")
		"save_state":
			host.quick_save()
			menu.set_status("State saved")
		"load_state":
			host.quick_load()
			set_menu_visible(false)
		"passthrough":
			xr_session.set_passthrough(not xr_session.passthrough, env)
			room.set_shown(not xr_session.passthrough)
		"recenter":
			_place_viewer()
			_place_menu_in_view()
		"tv_menu":
			_toggle_tv_menu()


## The set's own menu, on the screen. Closes the floating panel so the TV is
## in view and the buttons go to it.
func _toggle_tv_menu() -> void:
	if tv.osd.is_open:
		tv.osd.close()
	else:
		set_menu_visible(false)
		tv_menu.open()


## Quest: ask for All Files Access so /sdcard/VRT is readable. Android shows its
## own settings page; we rescan when the app regains focus.
func _request_storage_access() -> void:
	if OS.get_name() != "Android":
		return
	if not "android.permission.MANAGE_EXTERNAL_STORAGE" in OS.get_granted_permissions():
		OS.request_permission("android.permission.MANAGE_EXTERNAL_STORAGE")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and is_node_ready():
		rescan()


func _log_stats(delta: float) -> void:
	_stats_t += delta
	if menu_visible and Engine.get_process_frames() % 30 == 0:
		var hz := xr_session.xr.get_display_refresh_rate() if xr_session else 0.0
		var eye := xr_session.xr.get_render_target_size() if xr_session else Vector2.ZERO
		menu.set_perf("%d fps / %d Hz  ·  %dx%d%s  ·  %s" % [Engine.get_frames_per_second(), hz, eye.x, eye.y,
				"  ·  Quest 2 profile" if xr_session and xr_session.is_quest2 else "",
				ProjectSettings.get_setting("application/config/version", "dev")])
	if _stats_t < STATS_INTERVAL:
		return
	if xr_session:
		print("VRT: eye buffer ", xr_session.xr.get_render_target_size(), " x", xr_session.xr.render_target_size_multiplier)
	if host.is_running():
		var lr := host.libretro
		print("VRT stats: %s emu %.2f fps (declared %.2f) frames %d skipped %d field %d dropped %d render %d fps pacing %s" % [
				host.current.core, _frames_seen / _stats_t, lr.call("GetDeclaredFps"), _frames_seen,
				_frames_skipped, host.video_field(), lr.call("GetDroppedFrameCount"),
				Engine.get_frames_per_second(), str(lr.call("GetPacingStats"))])
	_stats_t = 0.0
	_frames_seen = 0
	_frames_skipped = 0
