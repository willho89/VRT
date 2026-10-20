class_name SignalPresets
extends RefCounted
## How the picture reaches the TV: parameters for signal_ntsc.gdshader.
## Times are in samples at 4 x fsc (14.318 MHz; 1 sample = 70 ns), the same
## for every console.

enum Connection { RGB, SVIDEO, COMPOSITE, RF }

const NAMES := ["RGB", "S-Video", "Composite", "RF"]

## Overall degradation: mix of the decoded picture over the clean one.
const STRENGTHS := [0.0, 0.35, 0.65, 1.0]
const STRENGTH_NAMES := ["Off", "Low", "Medium", "High"]
const DEFAULT_STRENGTH := 1

## TV's Y/C separation for composite and RF.
enum Decoder { NOTCH, COMB }
const DECODER_NAMES := ["Notch", "Comb"]

const PRESETS := {
	Connection.SVIDEO: {"mode": 2, "chroma_sigma": 2.4, "noise": 0.003},
	Connection.COMPOSITE: {"mode": 0, "chroma_sigma": 2.6, "noise": 0.004},
	# "Famicom RF": an 8-bit console on the antenna socket.
	Connection.RF: {
		"mode": 0, "chroma_sigma": 3.2, "noise": 0.014, "rf_amount": 1.0,
		"ghost_strength": 0.10, "ghost_delay": 26.0, "rf_snow": 0.05,
		"rf_gain_wobble": 0.06, "sync_jitter": 1.6, "burst_phase_noise": 0.03,
		"rf_tuning_error": 0.05,
	},
}
const DEFAULTS := {
	"rf_amount": 0.0, "ghost_strength": 0.0, "ghost_delay": 24.0, "rf_snow": 0.0,
	"rf_gain_wobble": 0.0, "sync_jitter": 0.0, "burst_phase_noise": 0.0, "rf_tuning_error": 0.0,
	"encoder_chroma_sigma": 0.0,
}


static func apply(mat: ShaderMaterial, input: int, strength: float, decoder: int) -> void:
	var p: Dictionary = DEFAULTS.duplicate()
	p.merge(PRESETS.get(input, {}), true)
	if p.mode == 0 and decoder == Decoder.COMB:
		p.mode = 1
	p.signal_amount = strength
	for key in p:
		mat.set_shader_parameter(key, p[key])
