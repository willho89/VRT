class_name CrtPipeline
extends Node
## Runs the per-frame CRT passes and feeds the tube surface material.
##
##   core frame -> signal (composite/RF/S-Video, source res) -> raster
##   (ping-pong SubViewports, RGBA16F) -> tube_surface
##
## The raster pass renders only when the core delivered a new frame, sized
## (source width, frame lines); in field mode frame lines are 2x the field.

const RASTER_SHADER := preload("res://shaders/crt/raster.gdshader")
const SIGNAL_SHADER := preload("res://shaders/crt/signal_ntsc.gdshader")
const HALATION_SHADER := preload("res://shaders/crt/halation.gdshader")
const HALATION_DOWNSCALE := 4
const SURFACE_SHADER := preload("res://shaders/crt/tube_surface.gdshader")

var profile: CrtProfile
var surface := ShaderMaterial.new()
var input: int = SignalPresets.Connection.COMPOSITE
var strength_level: int = SignalPresets.DEFAULT_STRENGTH
## How close to the headset's resolution limit scanlines and mask are kept
## visible: the period (in eye-buffer pixels) over which they fade out.
## Lower shows more structure from further away at the risk of moire.
const DETAIL_FADE_PX := [Vector2(3.0, 6.0), Vector2(2.0, 4.0), Vector2(1.2, 2.5)]
const DETAIL_NAMES := ["Clean", "Balanced", "Strong"]
const DEFAULT_DETAIL := 1
var detail_level: int = DEFAULT_DETAIL

var _sig_vp := SubViewport.new()
var _sig_mat := ShaderMaterial.new()
var _sig_rect := ColorRect.new()
var _sig_width := 0
var _halo_vp := SubViewport.new()
var _halo_mat := ShaderMaterial.new()
var _halo_rect := ColorRect.new()
var _frame_count := 0

var _vp: Array[SubViewport] = []
var _mat: Array[ShaderMaterial] = []
var _rect: Array[ColorRect] = []
var _cur := 0
var _have_prev := false
var _size := Vector2i.ZERO


func _init(p: CrtProfile) -> void:
	surface.shader = SURFACE_SHADER
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
	profile = p
	set_input(p.default_input)
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
	for m in _mat:
		m.set_shader_parameter("persistence", p.persistence)
		m.set_shader_parameter("gamma", p.gamma)


func set_input(i: int) -> void:
	input = i
	_sig_width = 0  # re-apply parameters on the next frame


func set_detail_level(level: int) -> void:
	detail_level = level
	surface.set_shader_parameter("fade_px", DETAIL_FADE_PX[level])


func set_strength_level(level: int) -> void:
	strength_level = level
	_sig_width = 0


## Feed the current core output. new_frames: frames landed since last call.
func push(tex: Texture2D, field: int, new_frames: int) -> void:
	surface.set_shader_parameter("powered", tex != null)
	if tex == null or new_frames <= 0:
		return
	var src := Vector2i(tex.get_width(), tex.get_height())
	var lines := src.y * (2 if field != 0 else 1)
	var size := Vector2i(src.x, lines)
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

	# Signal stage at source resolution (skipped entirely for RGB).
	var raster_src := tex
	var strength: float = SignalPresets.STRENGTHS[strength_level]
	if input != SignalPresets.Connection.RGB and strength > 0.0:
		if _sig_vp.size != src or _sig_width != src.x:
			_sig_vp.size = src
			_sig_rect.size = Vector2(src)
			_sig_width = src.x
			SignalPresets.apply(_sig_mat, input, src.x, strength)
		_frame_count += new_frames
		_sig_mat.set_shader_parameter("source_texture", tex)
		_sig_mat.set_shader_parameter("source_size", Vector2(src))
		_sig_mat.set_shader_parameter("frame_count", float(_frame_count))
		_sig_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		raster_src = _sig_vp.get_texture()

	var nxt := 1 - _cur
	var m := _mat[nxt]
	m.set_shader_parameter("source_tex", raster_src)
	m.set_shader_parameter("prev_tex", _vp[_cur].get_texture())
	m.set_shader_parameter("has_prev", _have_prev)
	m.set_shader_parameter("source_size", Vector2(src))
	m.set_shader_parameter("frame_lines", float(lines))
	m.set_shader_parameter("field", field)
	_vp[nxt].render_target_update_mode = SubViewport.UPDATE_ONCE
	_cur = nxt
	_have_prev = true

	surface.set_shader_parameter("raster_tex", _vp[_cur].get_texture())
	_halo_mat.set_shader_parameter("raster_tex", _vp[_cur].get_texture())
	_halo_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	surface.set_shader_parameter("raster_size", Vector2(size))
