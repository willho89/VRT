class_name SystemTiming
extends RefCounted
## How each console's video lines up with the NTSC colour subcarrier
## (fsc = 3.579545 MHz). This decides what composite artifacts look like:
##
##   cycles_per_px  subcarrier cycles per console pixel (pixel clock vs fsc)
##   line_step      phase advance per line, in cycles. 1/3 (227.33 cycles a
##                  line) gives NES/SNES their diagonal 3-line pattern; 0 (228)
##                  makes Genesis artifacts stand still, which is why its
##                  dithered "transparency" blends into solid colour; 1/2
##                  (227.5, broadcast) gives the classic checkerboard.
##   frame_steps    phase offset of successive frames (or fields), cycling.
##                  Movement here is what reads as dot crawl.
##
## Derived from the consoles' master clocks: NES PPU 8 master clocks a pixel
## vs 12 a subcarrier cycle, alternate frames one pixel short; SNES likewise
## (21.477 MHz = 6 fsc, short line every other frame); Mega Drive 53.693 MHz
## = 15 fsc, 3420 clocks a line; PC Engine 21.477 MHz, 1365 clocks a line.

const FSC_HZ := 3579545.0
## Active picture of a broadcast line (52.6 us) in subcarrier cycles: the
## fallback when a core's pixel clock is unknown.
const BROADCAST_ACTIVE_CYCLES := 188.3


## Timing for a core's current output. width is the frame's pixel width;
## fields is true when the core sends interlaced fields one at a time.
static func for_core(core: String, width: int, fields: bool) -> Dictionary:
	match core:
		"fceumm", "nestopia", "mesen":
			return _t(2.0 / 3.0, 1.0 / 3.0, [0.0, 1.0 / 3.0])
		"snes9x", "bsnes", "bsnes_mercury":
			# 512 px hi-res modes run the dot clock at twice the rate.
			return _t((1.0 / 3.0) if width > 300 else (2.0 / 3.0), 1.0 / 3.0, [0.0, 1.0 / 3.0])
		"genesis_plus_gx", "picodrive":
			# H40 (320 px) uses an 8-clock dot, H32 (256 px) a 10-clock dot.
			return _t((8.0 / 15.0) if width >= 320 else (2.0 / 3.0), 0.0, [0.0])
		"mednafen_pce_fast", "mednafen_pce":
			var cpp := 2.0 / 3.0
			if width > 400:
				cpp = 1.0 / 3.0
			elif width > 300:
				cpp = 0.5
			return _t(cpp, 0.5, [0.0])
		"deevee":
			# BT.601: 13.5 MHz pixels. A field is 262.5 lines of 227.5 cycles.
			var cpp := FSC_HZ / 13.5e6
			if fields:
				return _t(cpp, 0.5, [0.0, 0.75, 0.5, 0.25])
			return _t(cpp, 0.5, [0.0, 0.5])
	return _t(BROADCAST_ACTIVE_CYCLES / maxf(width, 1.0), 0.5, [0.0, 0.5])


static func _t(cycles_per_px: float, line_step: float, frame_steps: Array) -> Dictionary:
	return {"cycles_per_px": cycles_per_px, "line_step": line_step, "frame_steps": frame_steps}


## Signal width in samples (4 per subcarrier cycle) for a frame width.
static func samples(timing: Dictionary, width: int) -> int:
	return maxi(int(round(width * timing.cycles_per_px * 4.0)), width)
