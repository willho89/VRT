class_name CrtPipeline
extends Node
## Runs the per-frame CRT passes and feeds the tube surface material.
##
##   core frame -> signal (composite/RF/S-Video at 4 x fsc samples) -> raster
##   (ping-pong SubViewports, RGBA16F) -> tube_surface
##
## The raster pass renders only when the core delivered a new frame, sized
## (signal samples or source width for RGB, frame lines); in field mode frame
## lines are 2x the field.

const RASTER_SHADER := preload("res://shaders/crt/raster.gdshader")
const SIGNAL_SHADER := preload("res://shaders/crt/signal_ntsc.gdshader")
const HALATION_SHADER := preload("res://shaders/crt/halation.gdshader")
const HALATION_DOWNSCALE := 4
const LOWPASS_SHADER := preload("res://shaders/crt/raster_lowpass.gdshader")
const VHS_SHADER := preload("res://shaders/crt/vhs.gdshader")
const SURFACE_SHADER := preload("res://shaders/crt/tube_surface.gdshader")

var profile: CrtProfile
var surface := ShaderMaterial.new()
var input: int = SignalPresets.Connection.COMPOSITE
var strength_level: int = SignalPresets.DEFAULT_STRENGTH
var decoder: int = SignalPresets.Decoder.NOTCH
var system_core := ""
## How close to the headset's resolution limit scanlines and mask are kept
## visible: the period (in eye-buffer pixels) over which they fade out.
## Lower shows more structure from further away at the risk of moire.
## Exaggerated goes past what the headset can resolve cleanly: a coarser mask
## and scanlines kept down to ~1 px, trading some shimmer for a CRT look that
## still shows at couch distance.
## Raw drops the anti-moire fading altogether: scanlines and mask keep full
## contrast at any distance and the picture is never low-passed, so they
## shimmer and beat against the headset's pixels when finer than them. That
## visible artifacting is what reads as a CRT across a room (user decision
## 2026-10-21: "if we're not seeing CRT artifacting, it's just a curved
## screen"). Only a half-pixel filter remains, against per-pixel sparkle.
##
## Distance (the default since 2026-10-21) splits the two: the RGB mask fades
## like Strong (its fine coloured stripes are what turn into rainbow moire), at
## a slightly coarser pitch so it holds to about arm's length, while scanlines
## never fade or merge and the beam is thinned so the gaps stay dark: at ~3 ft
## (~2 px per 240p line) the full-width spot only modulated ~20%, invisible in
## the headset; at 0.6x it is ~55%. Exaggerated pushes both further.
## Fade periods in eye-buffer pixels: [mask], [scanlines].
const NO_FADE := Vector2(0.0, 0.001)
const DETAIL_FADE_PX := [Vector2(3.0, 6.0), Vector2(1.2, 2.5), Vector2(1.2, 2.5), Vector2(0.8, 1.6), NO_FADE]
const DETAIL_SCAN_FADE_PX := [Vector2(3.0, 6.0), Vector2(1.2, 2.5), NO_FADE, NO_FADE, NO_FADE]
const DETAIL_MASK_SCALE := [1.0, 1.0, 1.25, 1.6, 1.6]
const DETAIL_SCANLINE_FILTER := [2.0, 2.0, 0.75, 0.6, 0.5]
const DETAIL_BEAM_SHARP := [1.0, 1.0, 0.6, 0.5, 1.0]
const DETAIL_FILTER_WIDTH := [1.0, 1.0, 1.0, 1.0, 0.5]
const DETAIL_NAMES := ["Clean", "Strong", "Distance", "Exaggerated", "Raw"]
const DEFAULT_DETAIL := 2  # Distance (2026-10-21); Strong was the 2026-10-19 baseline
var detail_level: int = DEFAULT_DETAIL

var _sig_vp := SubViewport.new()
var _sig_mat := ShaderMaterial.new()
var _sig_rect := ColorRect.new()
var _sig_dirty := true
var _timing := {}
var _timing_key := ""
var _phase_index := 0
## Tape stage (vhs.gdshader) in front of the signal stage: -1 = no tape,
## else the tape's wear (0 good .. 1 worn).
var tape_wear := -1.0
var _vhs_vp := SubViewport.new()
var _vhs_mat := ShaderMaterial.new()
var _vhs_rect := ColorRect.new()
var _lo_vp := SubViewport.new()
var _lo_mat := ShaderMaterial.new()
var _lo_rect := ColorRect.new()
var _halo_vp := SubViewport.new()
var _halo_mat := ShaderMaterial.new()
var _halo_rect := ColorRect.new()
var _frame_count := 0
var _osd: TvOsd

var _vp: Array[SubViewport] = []
var _mat: Array[ShaderMaterial] = []
var _rect: Array[ColorRect] = []
var _cur := 0
var _have_prev := false
var _size := Vector2i.ZERO


func _init(p: CrtProfile) -> void:
	surface.shader = SURFACE_SHADER
	_vhs_vp.disable_3d = true
	_vhs_vp.transparent_bg = false
	_vhs_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vhs_mat.shader = VHS_SHADER
	_vhs_rect.material = _vhs_mat
	_vhs_vp.add_child(_vhs_rect)
	add_child(_vhs_vp)  # before the signal viewport: renders first
	_sig_vp.disable_3d = true
	_sig_vp.transparent_bg = false
	_sig_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_sig_mat.shader = SIGNAL_SHADER
	_sig_rect.material = _sig_mat
	_sig_vp.add_child(_sig_rect)
	add_child(_sig_vp)
	for i in 2:
		var vp := SubViewport.new()
		vp.use_hdr_2d = true
		vp.transparent_bg = false
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
		var mat := ShaderMaterial.new()
		mat.shader = RASTER_SHADER
		var rect := ColorRect.new()
		rect.material = mat
		vp.add_child(rect)
		add_child(vp)
		_vp.append(vp)
		_mat.append(mat)
		_rect.append(rect)
	_lo_vp.use_hdr_2d = true
	_lo_vp.disable_3d = true
	_lo_vp.transparent_bg = false
	_lo_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_lo_mat.shader = LOWPASS_SHADER
	_lo_rect.material = _lo_mat
	_lo_vp.add_child(_lo_rect)
	add_child(_lo_vp)  # after the raster viewports, like halation
	surface.set_shader_parameter("raster_lo_tex", _lo_vp.get_texture())
	_halo_vp.use_hdr_2d = true
	_halo_vp.disable_3d = true
	_halo_vp.transparent_bg = false
	_halo_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_halo_mat.shader = HALATION_SHADER
	_halo_rect.material = _halo_mat
	_halo_vp.add_child(_halo_rect)
	add_child(_halo_vp)  # after the raster viewports: renders from this frame's raster
	surface.set_shader_parameter("halation_tex", _halo_vp.get_texture())
	set_profile(p)


func set_profile(p: CrtProfile) -> void:
	profile = p  # the input is the user's (TvMenu); a TV type only suggests a default
	var s := surface
	s.set_shader_parameter("visible_mm", p.visible_size_mm)
	s.set_shader_parameter("corner_radius_mm", p.corner_radius_mm)
	s.set_shader_parameter("glass_thickness_mm", p.glass_thickness_mm)
	s.set_shader_parameter("glass_ior", p.glass_ior)
	s.set_shader_parameter("overscan", p.overscan)
	s.set_shader_parameter("pincushion", p.pincushion)
	s.set_shader_parameter("mask_type", p.mask_type)
	s.set_shader_parameter("mask_pitch_mm", p.mask_pitch_mm)
	s.set_shader_parameter("mask_vpitch_mm", p.mask_vpitch_mm)
	s.set_shader_parameter("phosphor_duty", p.phosphor_duty)
	s.set_shader_parameter("slot_duty", p.slot_duty)
	s.set_shader_parameter("beam_sigma_dark", p.beam_sigma_dark)
	s.set_shader_parameter("beam_sigma_bright", p.beam_sigma_bright)
	s.set_shader_parameter("convergence_r_mm", p.convergence_r_mm)
	s.set_shader_parameter("convergence_b_mm", p.convergence_b_mm)
	s.set_shader_parameter("phosphor_to_rec709", CrtColor.phosphor_to_rec709(p))
	s.set_shader_parameter("glass_tint", p.glass_tint)
	s.set_shader_parameter("glass_roughness", p.glass_roughness)
	s.set_shader_parameter("corner_falloff", p.corner_falloff)
	s.set_shader_parameter("halation", p.halation)
	s.set_shader_parameter("glass_scratches", p.glass_scratches)
	_apply_beam_h()
	for m in _mat:
		m.set_shader_parameter("persistence", p.persistence)
		m.set_shader_parameter("gamma", p.gamma)


## A TvControls entry at an OSD level (0..100, 50 neutral).
func set_tv_control(index: int, level: int) -> void:
	for m in _mat:
		m.set_shader_parameter(TvControls.ALL[index].key, TvControls.value(index, level))


func set_osd(osd: TvOsd) -> void:
	_osd = osd
	for m in _mat:
		m.set_shader_parameter("osd_tex", osd.texture())


## Show only the middle `c` of the picture's width, stretched across the tube.
func set_crop_x(c: float) -> void:
	for m in _mat:
		m.set_shader_parameter("crop_x", c)


## Put the picture through a VHS tape (wear 0..1), or take it off (-1).
func set_tape(wear: float) -> void:
	tape_wear = wear
	_vhs_mat.set_shader_parameter("wear", maxf(wear, 0.0))


func signal_texture() -> Texture2D:
	return _sig_vp.get_texture()


func set_input(i: int) -> void:
	input = i
	_sig_dirty = true
	_apply_beam_h()


## The horizontal spot, scaled by input: RGB arrives at full bandwidth and
## looks crisp (pixels with scanlines); composite and RF keep the soft spot,
## standing in for the bandwidth they lose on the way (with the signal stage).
const INPUT_SHARPNESS := {
	SignalPresets.Connection.RGB: 0.45, SignalPresets.Connection.SVIDEO: 0.7,
	SignalPresets.Connection.COMPOSITE: 1.0, SignalPresets.Connection.RF: 1.0,
}


func _apply_beam_h() -> void:
	if profile == null:
		return
	var k: float = INPUT_SHARPNESS.get(input, 1.0)
	for m in _mat:
		m.set_shader_parameter("beam_sigma_h", profile.beam_sigma_h * k)


func set_decoder(d: int) -> void:
	decoder = d
	_sig_dirty = true


## The running core, for its subcarrier timing (SystemTiming).
func set_system(core: String) -> void:
	system_core = core
	_timing_key = ""


func set_detail_level(level: int) -> void:
	detail_level = level
	surface.set_shader_parameter("fade_px", DETAIL_FADE_PX[level])
	surface.set_shader_parameter("scan_fade_px", DETAIL_SCAN_FADE_PX[level])
	surface.set_shader_parameter("mask_scale", DETAIL_MASK_SCALE[level])
	surface.set_shader_parameter("scanline_filter", DETAIL_SCANLINE_FILTER[level])
	surface.set_shader_parameter("filter_width", DETAIL_FILTER_WIDTH[level])
	surface.set_shader_parameter("beam_sharp", DETAIL_BEAM_SHARP[level])


func set_strength_level(level: int) -> void:
	strength_level = level
	_sig_dirty = true


## Feed the current core output. new_frames: frames landed since last call.
## internal: the set's own picture (no-signal screen), which never passes
## through the composite/RF path.
func push(tex: Texture2D, field: int, new_frames: int, internal := false) -> void:
	surface.set_shader_parameter("powered", tex != null)
	if tex == null or new_frames <= 0:
		return
	var src := Vector2i(tex.get_width(), tex.get_height())
	var lines := src.y * (2 if field != 0 else 1)
	var strength: float = SignalPresets.STRENGTHS[strength_level]
	var use_signal := input != SignalPresets.Connection.RGB and strength > 0.0 and not internal
	var key := "%s/%d/%d" % [system_core, src.x, int(field != 0)]
	if key != _timing_key:
		_timing_key = key
		_timing = SystemTiming.for_core(system_core, src.x, field != 0)
		_sig_dirty = true
	var width := SystemTiming.samples(_timing, src.x) if use_signal else src.x
	var size := Vector2i(width, lines)
	if size != _size:
		_size = size
		_have_prev = false
		for i in 2:
			_vp[i].size = size
			_rect[i].size = Vector2(size)
		var hs := Vector2i(maxi(size.x / HALATION_DOWNSCALE, 1), maxi(size.y / HALATION_DOWNSCALE, 1))
		_halo_vp.size = hs
		_halo_rect.size = Vector2(hs)
		_halo_mat.set_shader_parameter("raster_size", Vector2(size))
		_lo_vp.size = size
		_lo_rect.size = Vector2(size)
		_lo_mat.set_shader_parameter("width", float(size.x))

	# Tape stage (a VCR in the chain), then the signal stage (skipped entirely
	# for RGB or strength Off).
	var raster_src := tex
	_frame_count += new_frames
	if tape_wear >= 0.0 and not internal:
		if _vhs_vp.size != src:
			_vhs_vp.size = src
			_vhs_rect.size = Vector2(src)
		_vhs_mat.set_shader_parameter("source_texture", tex)
		_vhs_mat.set_shader_parameter("source_size", Vector2(src))
		_vhs_mat.set_shader_parameter("frame_count", float(_frame_count))
		_vhs_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		raster_src = _vhs_vp.get_texture()
	_phase_index += new_frames
	if use_signal:
		var sig_size := Vector2i(width, src.y)
		if _sig_vp.size != sig_size or _sig_dirty:
			_sig_vp.size = sig_size
			_sig_rect.size = Vector2(sig_size)
			_sig_dirty = false
			SignalPresets.apply(_sig_mat, input, strength, decoder)
			_sig_mat.set_shader_parameter("line_step", _timing.line_step)
		var steps: Array = _timing.frame_steps
		_sig_mat.set_shader_parameter("frame_phase", steps[_phase_index % steps.size()])
		_sig_mat.set_shader_parameter("source_texture", raster_src)
		_sig_mat.set_shader_parameter("source_size", Vector2(src))
		_sig_mat.set_shader_parameter("out_width", float(width))
		_sig_mat.set_shader_parameter("frame_count", float(_frame_count))
		_sig_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		raster_src = _sig_vp.get_texture()

	var nxt := 1 - _cur
	var m := _mat[nxt]
	m.set_shader_parameter("source_tex", raster_src)
	m.set_shader_parameter("prev_tex", _vp[_cur].get_texture())
	m.set_shader_parameter("has_prev", _have_prev)
	m.set_shader_parameter("source_size", Vector2(width, src.y))
	m.set_shader_parameter("frame_lines", float(lines))
	m.set_shader_parameter("field", field)
	m.set_shader_parameter("osd_on", _osd != null and _osd.visible_now())
	_vp[nxt].render_target_update_mode = SubViewport.UPDATE_ONCE
	_cur = nxt
	_have_prev = true

	surface.set_shader_parameter("raster_tex", _vp[_cur].get_texture())
	_halo_mat.set_shader_parameter("raster_tex", _vp[_cur].get_texture())
	_halo_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_lo_mat.set_shader_parameter("raster_tex", _vp[_cur].get_texture())
	_lo_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	surface.set_shader_parameter("raster_size", Vector2(size))
	surface.set_shader_parameter("beam_scale", maxf(float(lines) / 240.0, 1.0))
	surface.set_shader_parameter("sweep_lines", 2.0 if field != 0 else 1.0)
