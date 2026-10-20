class_name SignalPresets
extends RefCounted
## How the picture reaches the TV. Parameters for signal_ntsc.gdshader (the
## TSUISHI/CRTshader Stage 1 port), adapted from its presets (MIT). Values in
## source pixels are tuned for a 320 px wide source; CrtPipeline rescales them.

enum Connection { RGB, SVIDEO, COMPOSITE, RF }

const NAMES := ["RGB", "S-Video", "Composite", "RF"]

## Parameters measured in source pixels (scaled by width / 320) and the one
## measured in radians per source pixel (scaled by 320 / width).
const PIXEL_PARAMS := ["chroma_delay_px", "y_band_px", "i_band_px", "q_band_px", "ghost_offset_px", "sync_jitter_px"]
const PER_PIXEL_PARAMS := ["subcarrier_phase_px"]

const PRESETS := {
	Connection.RGB: {"signal_amount": 0.0, "rgb_bypass_mix": 1.0, "rf_amount": 0.0},
	# Separate luma and chroma: no cross-color or dot crawl, chroma still band-limited.
	Connection.SVIDEO: {
		"signal_amount": 1.0, "rgb_bypass_mix": 0.0, "composite_artifact": 0.0,
		"composite_fringing": 0.0, "chroma_delay_px": 0.6, "y_band_px": 0.8,
		"i_band_px": 2.2, "q_band_px": 3.0, "ghost_strength": 0.0, "noise_luma": 0.004,
		"noise_chroma": 0.006, "rf_amount": 0.0, "phase_jitter": 0.0,
	},
	# TSUISHI's shipped defaults: a composite-video television.
	Connection.COMPOSITE: {
		"signal_amount": 1.0, "rgb_bypass_mix": 0.0, "composite_artifact": 0.85,
		"composite_fringing": 0.65, "subcarrier_phase_px": 1.047, "line_phase_amount": 2.094,
		"phase_jitter": 0.025, "chroma_delay_px": 1.25, "y_band_px": 1.25, "i_band_px": 2.75,
		"q_band_px": 4.25, "ghost_strength": 0.08, "ghost_offset_px": 6.0, "noise_luma": 0.012,
		"noise_chroma": 0.018, "rf_amount": 0.0,
	},
	# "Famicom RF": an 8-bit console on the antenna socket.
	Connection.RF: {
		"signal_amount": 1.0, "rgb_bypass_mix": 0.0, "composite_artifact": 1.15,
		"composite_fringing": 0.92, "phase_jitter": 0.055, "chroma_delay_px": 1.85,
		"ghost_strength": 0.13, "noise_luma": 0.018, "noise_chroma": 0.026, "rf_amount": 1.0,
		"sync_jitter_px": 0.85, "rf_tuning_error": 0.32, "burst_phase_noise": 0.16,
		"rf_snow": 0.055, "rf_gain_wobble": 0.075, "saturation": 1.15,
	},
}


static func apply(mat: ShaderMaterial, input: int, source_width: int) -> void:
	var k := float(source_width) / 320.0
	var base: Dictionary = PRESETS[Connection.COMPOSITE].duplicate()
	base.merge(PRESETS[input], true)
	for key in base:
		var v = base[key]
		if key in PIXEL_PARAMS:
			v *= k
		elif key in PER_PIXEL_PARAMS:
			v /= k
		mat.set_shader_parameter(key, v)
