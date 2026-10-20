class_name SignalPresets
extends RefCounted
## How the picture reaches the TV. Parameters for signal_ntsc.gdshader (the
## TSUISHI/CRTshader Stage 1 port), adapted from its presets (MIT). Values in
## source pixels are tuned for a 320 px wide source; CrtPipeline rescales them.

enum Connection { RGB, SVIDEO, COMPOSITE, RF }

const NAMES := ["RGB", "S-Video", "Composite", "RF"]

## Overall degradation, scaling the shader's signal_amount (0 = clean picture).
const STRENGTHS := [0.0, 0.35, 0.65, 1.0]
const STRENGTH_NAMES := ["Off", "Low", "Medium", "High"]
const DEFAULT_STRENGTH := 1

## Parameters measured in source pixels (scaled by width / 320) and the one
## measured in radians per source pixel (scaled by 320 / width).
const PIXEL_PARAMS := ["chroma_delay_px", "y_band_px", "i_band_px", "q_band_px", "ghost_offset_px", "sync_jitter_px"]
const PER_PIXEL_PARAMS := ["subcarrier_phase_px"]

const PRESETS := {
	Connection.RGB: {"signal_amount": 0.0, "rgb_bypass_mix": 1.0, "rf_amount": 0.0},
	# Separate luma and chroma: no cross-color or dot crawl, chroma still band-limited.
	Connection.SVIDEO: {
		"signal_amount": 1.0, "rgb_bypass_mix": 0.0, "composite_artifact": 0.0,
		"composite_fringing": 0.0, "chroma_delay_px": 0.3, "y_band_px": 0.45,
		"i_band_px": 1.3, "q_band_px": 1.8, "ghost_strength": 0.0, "noise_luma": 0.004,
		"noise_chroma": 0.006, "rf_amount": 0.0, "phase_jitter": 0.0,
	},
	# A good composite connection to a decent TV: milder than TSUISHI's
	# defaults (artifact 0.85, Y/I/Q 1.25/2.75/4.25 px), which read as too
	# blurry and messy in the headset.
	Connection.COMPOSITE: {
		"signal_amount": 1.0, "rgb_bypass_mix": 0.0, "composite_artifact": 0.40,
		"composite_fringing": 0.30, "subcarrier_phase_px": 1.047, "line_phase_amount": 2.094,
		"phase_jitter": 0.012, "chroma_delay_px": 0.6, "y_band_px": 0.6, "i_band_px": 1.6,
		"q_band_px": 2.4, "ghost_strength": 0.025, "ghost_offset_px": 6.0, "noise_luma": 0.005,
		"noise_chroma": 0.008, "rf_amount": 0.0,
	},
	# "Famicom RF": an 8-bit console on the antenna socket.
	Connection.RF: {
		"y_band_px": 1.0, "i_band_px": 2.4, "q_band_px": 3.6,
		"signal_amount": 1.0, "rgb_bypass_mix": 0.0, "composite_artifact": 1.15,
		"composite_fringing": 0.92, "phase_jitter": 0.055, "chroma_delay_px": 1.85,
		"ghost_strength": 0.13, "noise_luma": 0.018, "noise_chroma": 0.026, "rf_amount": 1.0,
		"sync_jitter_px": 0.85, "rf_tuning_error": 0.32, "burst_phase_noise": 0.16,
		"rf_snow": 0.055, "rf_gain_wobble": 0.075, "saturation": 1.15,
	},
}


static func apply(mat: ShaderMaterial, input: int, source_width: int, strength := STRENGTHS[DEFAULT_STRENGTH]) -> void:
	var k := float(source_width) / 320.0
	var base: Dictionary = PRESETS[Connection.COMPOSITE].duplicate()
	base.merge(PRESETS[input], true)
	for key in base:
		var v = base[key]
		if key in PIXEL_PARAMS:
			v *= k
		elif key in PER_PIXEL_PARAMS:
			v /= k
		if key == "signal_amount":
			v *= strength
		mat.set_shader_parameter(key, v)
