class_name Tv
extends Node3D
## The TV set: cabinet and bezel sized from the active CrtProfile, the curved
## faceplate running the CRT pipeline, and the screen-light globals
## (screen_light.gdshaderinc) published every frame.

const SCREEN_RADIANCE := 2.0
const NO_SIGNAL_SHADER := preload("res://shaders/crt/no_signal.gdshader")
const NO_SIGNAL_SIZE := Vector2i(640, 240)
enum NoSignal { BLUE, SNOW }
## Everything the set plays (the core's sound, static hiss) goes through this
## bus; the TV's VOLUME control sets its level.
const AUDIO_BUS := &"TV"
const SAMPLES := Vector2i(16, 12)

var profile := CrtProfile.vcr_combo_25()
## CabinetVcrCombo, CabinetBox or CabinetModel: each has screen_origin,
## speakers, bounds and set_power_led().
var cabinet: Node3D
var type_id := ""
var pipeline := CrtPipeline.new(profile)
var screen := MeshInstance3D.new()
var screen_body := StaticBody3D.new()
## The whole set, for grabbing (layer 6). The screen collider sits behind its
## front face, so pointing queries each layer on its own.
var cabinet_body := StaticBody3D.new()
const SCREEN_LAYER := 1 << 4
const CABINET_LAYER := 1 << 5
var _cabinet := Node3D.new()
var _cells := Image.create_empty(SAMPLES.x, SAMPLES.y, false, Image.FORMAT_RGBF)
var _cells_tex := ImageTexture.create_from_image(_cells)
var _coarse := Image.create_empty(4, 3, false, Image.FORMAT_RGBF)
var _coarse_tex := ImageTexture.create_from_image(_coarse)
var _half := Vector2.ONE
var osd := TvOsd.new()
var no_signal := NoSignal.BLUE
var _ns_vp := SubViewport.new()
var _ns_mat := ShaderMaterial.new()
var _ns_t := 0.0
var _ns_frames := 0
## Hiss from the speakers while showing snow (an untuned channel).
var _hiss := AudioStreamPlayer3D.new()
var _hiss_play: AudioStreamGeneratorPlayback
var _hiss_lp := 0.0
const HISS_DB := -26.0


func _ready() -> void:
	add_child(pipeline)
	add_child(osd)
	if AudioServer.get_bus_index(AUDIO_BUS) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, AUDIO_BUS)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, &"Master")
	_hiss.bus = AUDIO_BUS
	pipeline.set_osd(osd)
	_ns_vp.size = NO_SIGNAL_SIZE
	_ns_vp.disable_3d = true
	_ns_vp.transparent_bg = false
	_ns_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var rect := ColorRect.new()
	rect.size = Vector2(NO_SIGNAL_SIZE)
	_ns_mat.shader = NO_SIGNAL_SHADER
	rect.material = _ns_mat
	_ns_vp.add_child(rect)
	add_child(_ns_vp)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.15
	_hiss.stream = gen
	_hiss.volume_db = HISS_DB
	add_child(_hiss)
	screen.material_override = pipeline.surface
	add_child(screen)
	add_child(_cabinet)
	screen_body.collision_layer = SCREEN_LAYER  # layer 5: screen (guide, DVD menus)
	screen.add_child(screen_body)
	cabinet_body.collision_layer = CABINET_LAYER
	add_child(cabinet_body)
	_rebuild(TvTypes.make_cabinet({"profile": profile, "cabinet": {"builtin": "vcr_combo"}}))


## Become another TV type (TvTypes): tube, cabinet, colliders and CRT
## settings. One type is active at a time.
func apply_type(t: Dictionary) -> void:
	if t.is_empty():
		return
	type_id = t.id
	profile = t.profile
	_rebuild(TvTypes.make_cabinet(t))


func _rebuild(cab: Node3D) -> void:
	var p := profile
	pipeline.set_profile(p)
	pipeline.surface.set_shader_parameter("overscan", overscan)  # the set's setting wins
	var size := p.size_m()
	_half = size * 0.5
	screen.mesh = TubeMesh.build(p)

	for c in _cabinet.get_children():
		_cabinet.remove_child(c)
		c.queue_free()
	cabinet = cab
	_cabinet.add_child(cabinet)
	screen.position = cabinet.screen_origin

	for c in screen_body.get_children():
		c.queue_free()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y, 0.01)
	shape.shape = box
	screen_body.add_child(shape)

	for c in cabinet_body.get_children():
		c.queue_free()
	var cab_shape := CollisionShape3D.new()
	var cab_box := BoxShape3D.new()
	var bounds: AABB = cabinet.get("bounds")
	cab_box.size = bounds.size
	cab_shape.shape = cab_box
	cab_shape.position = bounds.get_center()
	cabinet_body.add_child(cab_shape)


## Volume 0..100 on a perceptual (squared) curve; 0 mutes.
func set_volume(level: int) -> void:
	var bus := AudioServer.get_bus_index(AUDIO_BUS)
	var lin := pow(clampi(level, 0, 100) / 100.0, 2.0)
	AudioServer.set_bus_mute(bus, level <= 0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(lin, 1e-4)))


## Picture hidden under the bezel on each side, as a fraction (TV setting;
## the profile's own figure is only a default).
var overscan := Vector2(0.03, 0.03)


func set_overscan(fraction: float) -> void:
	overscan = Vector2(fraction, fraction)
	pipeline.surface.set_shader_parameter("overscan", overscan)


func set_no_signal(mode: int) -> void:
	no_signal = mode
	_ns_mat.set_shader_parameter("mode", mode)


## Called each frame with the core's current output (null when idle: the
## set then shows its own no-signal screen at 60 Hz).
func show_frame(tex: Texture2D, image: Image, field: int, new_frames: int, delta: float) -> void:
	if cabinet:
		cabinet.call("set_power_led", true)
	if tex:
		_ns_t = 0.0
		if _hiss.playing:
			_hiss.stop()
		pipeline.push(tex, field, new_frames)
		_sample_cells(image)
		return
	_ns_t += delta
	var n := int(_ns_t * 60.0)
	_ns_t -= n / 60.0
	if n > 0:
		_ns_frames += n
		_ns_mat.set_shader_parameter("frame_count", float(_ns_frames))
		_ns_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	pipeline.push(_ns_vp.get_texture(), 0, n, true)
	_feed_hiss()
	_fill_cells(Color(0.0, 0.006, 0.47) if no_signal == NoSignal.BLUE else Color(0.12, 0.12, 0.12))


func _feed_hiss() -> void:
	if no_signal != NoSignal.SNOW:
		if _hiss.playing:
			_hiss.stop()
		return
	if not _hiss.playing:
		_hiss.play()
		_hiss_play = _hiss.get_stream_playback()
	_hiss.global_transform = speaker_transform()
	# White noise through a gentle one-pole low-pass: TV-speaker static.
	for i in _hiss_play.get_frames_available():
		_hiss_lp = lerpf(_hiss_lp, randf() * 2.0 - 1.0, 0.6)
		_hiss_play.push_frame(Vector2(_hiss_lp, _hiss_lp))


## Where the set's sound comes from: between its speaker grilles.
func speaker_transform() -> Transform3D:
	var t := screen.global_transform
	var sp: Array = cabinet.get("speakers") if cabinet else []
	if sp.size() == 2 and sp[0].is_inside_tree():
		t.origin = (sp[0].global_position + sp[1].global_position) * 0.5
	return t


## Screen UV to OSD pixel: through the overscan and pincushion the tube
## shader applies, so the pointer lands where the text is drawn.
func screen_to_osd(uv: Vector2) -> Vector2:
	var c := uv * 2.0 - Vector2.ONE
	c *= Vector2.ONE - 2.0 * overscan
	c *= 1.0 + profile.pincushion * c.dot(c)
	return (c * 0.5 + Vector2(0.5, 0.5)) * Vector2(TvOsd.SIZE)


## UV of a world-space point on the screen face, top-left origin.
func screen_uv(world_point: Vector3) -> Vector2:
	var l := screen.to_local(world_point)
	return Vector2(l.x / (_half.x * 2.0) + 0.5, 0.5 - l.y / (_half.y * 2.0))


func _process(_delta: float) -> void:
	var b := screen.global_transform.basis
	RenderingServer.global_shader_parameter_set("VRT_SCREEN_CENTER", screen.global_position)
	RenderingServer.global_shader_parameter_set("VRT_SCREEN_RIGHT", b.x.normalized() * _half.x)
	RenderingServer.global_shader_parameter_set("VRT_SCREEN_UP", b.y.normalized() * _half.y)
	RenderingServer.global_shader_parameter_set("VRT_SCREEN_RADIANCE", Vector3.ONE * SCREEN_RADIANCE)
	RenderingServer.global_shader_parameter_set("VRT_SCREEN_CELLS", _cells_tex)
	RenderingServer.global_shader_parameter_set("VRT_SCREEN_CELLS_COARSE", _coarse_tex)


## Linear color of each light cell: a 2x2 sample per cell of the CPU frame.
func _sample_cells(image: Image) -> void:
	if image == null or image.is_empty():
		_cells.fill(Color.BLACK)
	else:
		var w := image.get_width()
		var h := image.get_height()
		for y in SAMPLES.y:
			for x in SAMPLES.x:
				var c := Color(0, 0, 0)
				for sy in 2:
					for sx in 2:
						c += image.get_pixel(int((x + 0.25 + 0.5 * sx) * w / SAMPLES.x),
								int((y + 0.25 + 0.5 * sy) * h / SAMPLES.y)).srgb_to_linear()
				_cells.set_pixel(x, y, c * 0.25)
	# 4x3 summary for per-pixel use: each coarse cell averages 4x4 fine cells.
	for y in 3:
		for x in 4:
			var s := Color(0, 0, 0)
			for fy in 4:
				for fx in 4:
					s += _cells.get_pixel(x * 4 + fx, y * 4 + fy)
			_coarse.set_pixel(x, y, s / 16.0)
	_cells_tex.update(_cells)
	_coarse_tex.update(_coarse)


## Uniform screen light (the set's own no-signal screen).
func _fill_cells(c: Color) -> void:
	_cells.fill(c)
	_coarse.fill(c)
	_cells_tex.update(_cells)
	_coarse_tex.update(_coarse)
