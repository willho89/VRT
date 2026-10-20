class_name TvMenu
extends RefCounted
## The TV's settings menu: builds the OSD pages, applies each setting to the
## set and saves it. Everything about how the picture looks lives here; the
## floating panel is for content and session actions only.

const DETAIL_LABELS := ["CLEAN", "BALANCED", "STRONG", "EXAGGERATED"]
const NO_SIGNAL_LABELS := ["BLUE", "SNOW"]
const STYLE_LABELS := ["GREEN", "WHITE"]
## How the set labels each input when it switches to it.
const INPUT_BANNERS := ["RGB", "S-VIDEO", "VIDEO 1", "CH 03"]
const BAR_STEP := 2

var settings: VrtSettings
var tv: Tv
var xr: XrSession  # null in flat desktop mode


func _init(s: VrtSettings, t: Tv, x: XrSession) -> void:
	settings = s
	tv = t
	xr = x
	_load()
	tv.osd.pages = _pages()


func open() -> void:
	tv.osd.open("main", "MENU")


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
	tv.osd.set_style(settings.get_value("tv", "osd_style", TvOsd.Style.GREEN))
	if xr:
		xr.set_eye_width(settings.get_value("xr", "eye_width", xr.default_eye_width()))


func _level(i: int) -> int:
	return settings.get_value("tv", TvControls.ALL[i].key, TvControls.DEFAULT_LEVEL)


static func _cycle(v: int, dir: int, n: int) -> int:
	return (v + dir + n) % n


func _pages() -> Dictionary:
	var p := tv.pipeline
	var main := [
		{"label": "PICTURE", "value": func(): return ">", "enter": func(): tv.osd.enter_page("picture", "PICTURE")},
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
	main.append_array([
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
	return {"main": main, "picture": picture}


func _eye() -> int:
	return settings.get_value("xr", "eye_width", xr.default_eye_width())
