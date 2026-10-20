class_name TvControls
extends RefCounted
## The set's picture controls (raster.gdshader uniforms). The OSD shows each
## as 0..100 with the factory setting at 50, like a real TV.

const ALL := [
	{"key": "brightness", "label": "BRIGHT", "min": -0.15, "max": 0.15},
	{"key": "contrast", "label": "PICTURE", "min": 0.6, "max": 1.4},
	{"key": "color", "label": "COLOR", "min": 0.0, "max": 2.0},
	{"key": "tint", "label": "TINT", "min": -30.0, "max": 30.0},
	{"key": "sharpness", "label": "SHARP", "min": -0.5, "max": 0.5},
]
## 50 is neutral for every control (no change to the picture).
const DEFAULT_LEVEL := 50


static func value(index: int, level: int) -> float:
	var c: Dictionary = ALL[index]
	return lerpf(c.min, c.max, clampi(level, 0, 100) / 100.0)
