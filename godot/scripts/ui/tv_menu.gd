class_name TvMenu
extends RefCounted
## The TV's settings menu: builds the OSD pages, applies each setting to the
## set and saves it. Everything about how the picture looks lives here; the
## floating panel is for content and session actions only.

const DETAIL_LABELS := ["CLEAN", "BALANCED", "STRONG", "EXAGGERATED", "RAW"]
const NO_SIGNAL_LABELS := ["BLUE", "SNOW"]
const STYLE_LABELS := ["GREEN", "WHITE"]
## How the set labels each input when it switches to it.
const INPUT_BANNERS := ["RGB", "S-VIDEO", "VIDEO 1", "CH 03"]
const BAR_STEP := 2
const DEFAULT_VOLUME := 70
## Overscan in percent per side. Real 90s sets hid 5-7%; less shows more of
## the picture (and of the junk some consoles leave at the edges).
const DEFAULT_OVERSCAN := 3
const MAX_OVERSCAN := 10

var settings: VrtSettings
var tv: Tv
var xr: XrSession  # null in flat desktop mode
var mover: TvMover
var types: TvTypes
var rooms: Array[Dictionary] = []
var select_room: Callable  # app: switch VR rooms
var host: RetroHost
## WIDE: how 16:9 DVDs fit a 4:3 tube. LETTERBOX and PAN&SCAN are the DVD
## player's own modes (a disc may only permit one). ZOOM and STRETCH are the
## TV's: the player sends anamorphic 16:9 and the set either shows its middle
## 4:3 full screen (correct shapes, sides cut) or the whole frame squeezed.
enum Wide { LETTERBOX, PAN_SCAN, ZOOM, STRETCH }
const WIDESCREEN_LABELS := ["LETTERBOX", "PAN&SCAN", "ZOOM", "STRETCH"]
const WIDESCREEN_OPTION := ["4:3_letterbox", "4:3_panscan", "16:9", "16:9"]
## Full screen with true shapes, as most people watched 16:9 discs on 4:3 sets.
const DEFAULT_WIDE := Wide.ZOOM


func _init(s: VrtSettings, t: Tv, x: XrSession, m: TvMover, ty: TvTypes) -> void:
	settings = s
	tv = t
	xr = x
	mover = m
	types = ty
	_load()
	tv.osd.pages = _pages()


func open() -> void:
	tv.osd.open("main", "MENU")


func open_placement() -> void:
	tv.osd.open("placement", "TV PLACEMENT")


## Show the current input the way the set does after switching to it.
func show_input_banner() -> void:
	tv.osd.banner(INPUT_BANNERS[tv.pipeline.input])


func _load() -> void:
	var p := tv.pipeline
	p.set_input(settings.get_value("crt", "input", tv.profile.default_input))
	p.set_strength_level(settings.get_value("crt", "signal_strength", SignalPresets.DEFAULT_STRENGTH))
	p.set_decoder(settings.get_value("crt", "decoder", SignalPresets.Decoder.NOTCH))
	p.set_detail_level(settings.get_value("crt", "detail", CrtPipeline.DEFAULT_DETAIL))
	for i in TvControls.ALL.size():
		p.set_tv_control(i, _level(i))
	tv.set_no_signal(settings.get_value("tv", "no_signal", Tv.NoSignal.BLUE))
	tv.set_volume(settings.get_value("tv", "volume", DEFAULT_VOLUME))
	tv.set_overscan(settings.get_value("tv", "overscan", DEFAULT_OVERSCAN) / 100.0)
	tv.osd.set_style(settings.get_value("tv", "osd_style", TvOsd.Style.GREEN))
	if xr:
		xr.set_eye_width(settings.get_value("xr", "eye_width", xr.default_eye_width()))
		xr.preferred_hz = settings.get_value("xr", "refresh_hz", 0.0)
		xr.turn_mode = settings.get_value("comfort", "turn", XrSession.Turn.SNAP)
		xr.snap_angle = settings.get_value("comfort", "snap_angle", 1)
		xr.turn_speed = settings.get_value("comfort", "turn_speed", 1)
		xr.walk_speed = settings.get_value("comfort", "walk_speed", 1)
		xr.walk_by_hand = settings.get_value("comfort", "walk_by_hand", false)
		xr.vignette = settings.get_value("comfort", "vignette", 1)
		xr.set_height_offset(settings.get_value("comfort", "height_cm", 0) / 100.0)


func _level(i: int) -> int:
	return settings.get_value("tv", TvControls.ALL[i].key, TvControls.DEFAULT_LEVEL)


static func _cycle(v: int, dir: int, n: int) -> int:
	return (v + dir + n) % n


func _pages() -> Dictionary:
	var p := tv.pipeline
	var main := [
		{"label": "VOLUME", "level": func(): return settings.get_value("tv", "volume", DEFAULT_VOLUME),
			"change": func(d):
				var v := clampi(settings.get_value("tv", "volume", DEFAULT_VOLUME) + d * BAR_STEP, 0, 100)
				settings.set_value("tv", "volume", v)
				tv.set_volume(v)},
		{"label": "PICTURE", "value": func(): return ">", "enter": func(): tv.osd.enter_page("picture", "PICTURE")},
		# Which set this is (TvTypes; JSON in res://tvs and /sdcard/VRT/tvs).
		{"label": "TV TYPE", "value": func(): return types.find(tv.type_id).get("short_name", "?"),
			"change": func(d):
				if types.types.size() < 2:
					return
				var t: Dictionary = types.types[_cycle(types.index_of(tv.type_id), d, types.types.size())]
				tv.apply_type(t)
				settings.set_value("tv", "type", t.id)
				apply_dvd_display()},
		{"label": "INPUT", "value": func(): return SignalPresets.NAMES[p.input].to_upper(),
			"change": func(d):
				p.set_input(_cycle(p.input, d, SignalPresets.NAMES.size()))
				settings.set_value("crt", "input", p.input)},
		{"label": "SIGNAL", "value": func(): return SignalPresets.STRENGTH_NAMES[p.strength_level].to_upper(),
			"change": func(d):
				p.set_strength_level(_cycle(p.strength_level, d, SignalPresets.STRENGTHS.size()))
				settings.set_value("crt", "signal_strength", p.strength_level)},
		{"label": "Y/C SEP", "value": func(): return SignalPresets.DECODER_NAMES[p.decoder].to_upper(),
			"change": func(d):
				p.set_decoder(_cycle(p.decoder, d, SignalPresets.DECODER_NAMES.size()))
				settings.set_value("crt", "decoder", p.decoder)},
		{"label": "OVERSCAN", "value": func(): return "%d%%" % settings.get_value("tv", "overscan", DEFAULT_OVERSCAN),
			"change": func(d):
				var o := clampi(settings.get_value("tv", "overscan", DEFAULT_OVERSCAN) + d, 0, MAX_OVERSCAN)
				settings.set_value("tv", "overscan", o)
				tv.set_overscan(o / 100.0)},
		{"label": "DETAIL", "value": func(): return DETAIL_LABELS[p.detail_level],
			"change": func(d):
				p.set_detail_level(_cycle(p.detail_level, d, DETAIL_LABELS.size()))
				settings.set_value("crt", "detail", p.detail_level)},
	]
	if xr:
		main.append({"label": "RES", "value": func(): return str(xr.eye_widths()[_eye()]),
			"change": func(d):
				var e := _cycle(_eye(), d, xr.eye_widths().size())
				xr.set_eye_width(e)
				settings.set_value("xr", "eye_width", e)})
		# 120 Hz shows 60 fps games and 59.94 Hz video evenly; lower rates
		# save power and GPU but judder 60 fps motion.
		main.append({"label": "REFRESH", "value": func(): return "%d HZ" % xr.xr.get_display_refresh_rate(),
			"change": func(d):
				var rates := xr.refresh_rates()
				if rates.is_empty():
					return
				var i := rates.find(xr.xr.get_display_refresh_rate())
				var hz: float = rates[_cycle(maxi(i, 0), d, rates.size())]
				xr.set_preferred_hz(hz)
				settings.set_value("xr", "refresh_hz", hz)})
	main.append_array([
		{"label": "WIDE", "value": func(): return "16:9 TV" if _tube_is_wide() else WIDESCREEN_LABELS[settings.get_value("tv", "widescreen", DEFAULT_WIDE)],
			"change": func(d):
				settings.set_value("tv", "widescreen", _cycle(settings.get_value("tv", "widescreen", DEFAULT_WIDE), d, WIDESCREEN_LABELS.size()))
				apply_dvd_display()},
		{"label": "NO SIG", "value": func(): return NO_SIGNAL_LABELS[tv.no_signal],
			"change": func(d):
				tv.set_no_signal(_cycle(tv.no_signal, d, NO_SIGNAL_LABELS.size()))
				settings.set_value("tv", "no_signal", tv.no_signal)},
		{"label": "OSD", "value": func(): return STYLE_LABELS[tv.osd.style],
			"change": func(d):
				tv.osd.set_style(_cycle(tv.osd.style, d, STYLE_LABELS.size()))
				settings.set_value("tv", "osd_style", tv.osd.style)},
		{"label": "EXIT", "enter": func(): tv.osd.close()},
	])

	var picture := []
	for i in TvControls.ALL.size():
		picture.append({"label": TvControls.ALL[i].label, "level": func(): return _level(i),
			"change": func(d):
				var lv := clampi(_level(i) + d * BAR_STEP, 0, 100)
				settings.set_value("tv", TvControls.ALL[i].key, lv)
				p.set_tv_control(i, lv)})
	picture.append({"label": "RESET", "enter": func():
		for i in TvControls.ALL.size():
			settings.set_value("tv", TvControls.ALL[i].key, TvControls.DEFAULT_LEVEL)
			p.set_tv_control(i, TvControls.DEFAULT_LEVEL)
		tv.osd.refresh()})
	picture.append({"label": "RETURN", "enter": func(): tv.osd.press(TvOsd.Key.BACK)})

	# Fine placement: left/right steps; hold to repeat. Grab with grip for coarse moves.
	var place := [
		{"label": "HEIGHT", "value": func(): return "%d CM" % roundi(tv.global_position.y * 100.0),
			"change": func(d): mover.nudge("height", d)},
		{"label": "DEPTH", "value": func(): return "<  >", "change": func(d): mover.nudge("distance", d)},
		{"label": "SIDE", "value": func(): return "<  >", "change": func(d): mover.nudge("left_right", d)},
		{"label": "TURN", "value": func(): return "%d DEG" % roundi(rad_to_deg(mover.yaw_angle())),
			"change": func(d): mover.nudge("yaw", -d)},
		{"label": "TILT", "value": func(): return "%d DEG" % roundi(rad_to_deg(mover.tilt())),
			"change": func(d): mover.nudge("tilt", d)},
		{"label": "SIZE", "value": func(): return "%d%%" % roundi(mover.scale_factor() * 100.0),
			"change": func(d): mover.nudge("scale", d)},
	]
	if xr:
		place.append({"label": "FACE ME", "enter": func(): mover.face_viewer(); tv.osd.refresh()})
	place.append({"label": "ON STAND", "enter": func(): mover.reset_to_stand(); tv.osd.refresh()})
	place.append({"label": "DONE", "enter": func(): tv.osd.close()})
	main.insert(1, {"label": "PLACE TV", "value": func(): return ">",
		"enter": func(): tv.osd.enter_page("placement", "TV PLACEMENT")})

	# Which VR room (rooms/*.json; docs/rooms.md).
	main.insert(2, {"label": "ROOM", "value": func():
			return UserDefs.find(rooms, settings.get_value("room", "id", Room.DEFAULT_ID), Room.DEFAULT_ID).get("short_name", "?"),
		"change": func(d):
			if rooms.size() < 2:
				return
			var i := UserDefs.index_of(rooms, settings.get_value("room", "id", Room.DEFAULT_ID))
			select_room.call(rooms[_cycle(i, d, rooms.size())])})
	var comfort := []
	if xr:
		main.insert(2, {"label": "COMFORT", "value": func(): return ">",
			"enter": func(): tv.osd.enter_page("comfort", "COMFORT")})
		comfort = [
			{"label": "TURN", "value": func(): return "SNAP" if xr.turn_mode == XrSession.Turn.SNAP else "SMOOTH",
				"change": func(_d):
					xr.turn_mode = XrSession.Turn.SMOOTH if xr.turn_mode == XrSession.Turn.SNAP else XrSession.Turn.SNAP
					settings.set_value("comfort", "turn", xr.turn_mode)},
			{"label": "SNAP", "value": func(): return "%d DEG" % XrSession.SNAP_ANGLES[xr.snap_angle],
				"change": func(d):
					xr.snap_angle = _cycle(xr.snap_angle, d, XrSession.SNAP_ANGLES.size())
					settings.set_value("comfort", "snap_angle", xr.snap_angle)},
			{"label": "TURN SPD", "value": func(): return "%d DEG/S" % XrSession.TURN_SPEEDS[xr.turn_speed],
				"change": func(d):
					xr.turn_speed = _cycle(xr.turn_speed, d, XrSession.TURN_SPEEDS.size())
					settings.set_value("comfort", "turn_speed", xr.turn_speed)},
			{"label": "WALK SPD", "value": func(): return XrSession.WALK_SPEED_NAMES[xr.walk_speed],
				"change": func(d):
					xr.walk_speed = _cycle(xr.walk_speed, d, XrSession.WALK_SPEEDS.size())
					settings.set_value("comfort", "walk_speed", xr.walk_speed)},
			{"label": "WALK DIR", "value": func(): return "HAND" if xr.walk_by_hand else "HEAD",
				"change": func(_d):
					xr.walk_by_hand = not xr.walk_by_hand
					settings.set_value("comfort", "walk_by_hand", xr.walk_by_hand)},
			{"label": "VIGNETTE", "value": func(): return XrSession.VIGNETTE_NAMES[xr.vignette],
				"change": func(d):
					xr.vignette = _cycle(xr.vignette, d, XrSession.VIGNETTE_LEVELS.size())
					settings.set_value("comfort", "vignette", xr.vignette)},
			{"label": "HEIGHT", "value": func(): return "%+d CM" % settings.get_value("comfort", "height_cm", 0),
				"change": func(d):
					var cm := clampi(settings.get_value("comfort", "height_cm", 0) + d * 5, -50, 50)
					settings.set_value("comfort", "height_cm", cm)
					xr.set_height_offset(cm / 100.0)},
			{"label": "RETURN", "enter": func(): tv.osd.press(TvOsd.Key.BACK)},
		]
	return {"main": main, "picture": picture, "placement": place, "comfort": comfort}


func _tube_is_wide() -> bool:
	var s := tv.profile.visible_size_mm
	return s.x / s.y > 1.6


## The set's zoom for what is on screen: ZOOM crops anamorphic 16:9 DVD
## video (declared aspect ~1.78) on a 4:3 tube; everything else is shown whole.
func picture_crop(h: RetroHost) -> float:
	if _tube_is_wide() or settings.get_value("tv", "widescreen", DEFAULT_WIDE) != Wide.ZOOM:
		return 1.0
	if not h.is_running() or h.current.core != "deevee":
		return 1.0
	var aspect: float = h.libretro.call("GetDeclaredAspect")
	return 0.75 if aspect > 1.6 else 1.0


## Tell DeeVee what kind of TV it is connected to: a 16:9 tube takes
## anamorphic video as is; a 4:3 one gets letterbox or pan & scan.
func apply_dvd_display() -> void:
	if host == null:
		return
	var v: String = "16:9" if _tube_is_wide() else WIDESCREEN_OPTION[settings.get_value("tv", "widescreen", DEFAULT_WIDE)]
	host.set_core_option("deevee", "deevee_tv_display", v)


func _eye() -> int:
	return settings.get_value("xr", "eye_width", xr.default_eye_width())
