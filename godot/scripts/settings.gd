class_name VrtSettings
extends RefCounted
## Persistent user settings (user://vrt.cfg).

const PATH := "user://vrt.cfg"
const PKG := "io.github.willho89.vrt"

var cfg := ConfigFile.new()


func _init() -> void:
	cfg.load(PATH)


func save() -> void:
	cfg.save(PATH)


## Where content is looked for. On Quest:
##   /sdcard/VRT/roms/<System>/...    needs All Files Access (asked on start)
##   /sdcard/VRT/video/               DVD images and VIDEO_TS folders
##   /sdcard/Android/data/<pkg>/files/{roms,video}  always readable, no permission
func content_roots() -> Array:
	if cfg.has_section_key("content", "roots"):
		return cfg.get_value("content", "roots")
	if OS.get_name() == "Android":
		var app := "/sdcard/Android/data/%s/files" % PKG
		return [
			{"path": "/sdcard/VRT/roms"},
			{"path": "/sdcard/VRT/video", "core": "deevee"},
			{"path": "/sdcard/VRT/vhs", "core": "ffmpeg"},
			{"path": app.path_join("roms")},
			{"path": app.path_join("video"), "core": "deevee"},
			{"path": app.path_join("vhs"), "core": "ffmpeg"},
		]
	var home := OS.get_environment("HOME")
	return [
		{"path": ProjectSettings.globalize_path("res://../testdata/roms")},
		{"path": home.path_join("ROMS")},
		{"path": home.path_join("Videos/DVD"), "core": "deevee"},
		{"path": home.path_join("Videos/VHS"), "core": "ffmpeg"},
		{"path": home.path_join(".claude/projects/DeeVee/TestISOs"), "core": "deevee"},
	]


func get_value(section: String, key: String, default: Variant) -> Variant:
	return cfg.get_value(section, key, default)


func set_value(section: String, key: String, value: Variant) -> void:
	cfg.set_value(section, key, value)
	save()
