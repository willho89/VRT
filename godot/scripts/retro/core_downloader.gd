class_name CoreDownloader
extends Node
## Fetches libretro cores VRT does not bundle from the official libretro
## buildbot on first need, the way RetroArch's core updater does. Keeping them
## out of the APK keeps VRT's release clean: several cores have licences that
## do not allow redistribution inside a GPLv3 app (Snes9x, Genesis Plus GX are
## non-commercial), and the rest are best taken from their own builds anyway.
##
## Downloads run one at a time; installed(core) fires when one lands.

signal installed(core: String)
signal failed(core: String, why: String)

const BUILDBOT := "https://buildbot.libretro.com/nightly/"
const PLATFORM_PATH := {
	"Android": ["android/latest/arm64-v8a/", "_libretro_android.so"],
	"Linux": ["linux/x86_64/latest/", "_libretro.so"],
}

var cores_dir: String
var _queue: Array[String] = []
var _http := HTTPRequest.new()
var _busy := ""


func _init(dir: String) -> void:
	cores_dir = dir


func _ready() -> void:
	_http.use_threads = true
	_http.download_chunk_size = 262144
	_http.request_completed.connect(_on_completed)
	add_child(_http)


func core_file(core: String) -> String:
	var p: Array = PLATFORM_PATH.get(OS.get_name(), PLATFORM_PATH.Linux)
	return core + p[1]


func is_installed(core: String) -> bool:
	return FileAccess.file_exists(cores_dir.path_join(core_file(core)))


func is_busy(core: String) -> bool:
	return core == _busy or core in _queue


func request(core: String) -> void:
	if is_installed(core) or is_busy(core):
		return
	_queue.append(core)
	_next()


func _next() -> void:
	if _busy != "" or _queue.is_empty():
		return
	_busy = _queue.pop_front()
	var p: Array = PLATFORM_PATH.get(OS.get_name(), PLATFORM_PATH.Linux)
	var url: String = BUILDBOT + p[0] + core_file(_busy) + ".zip"
	_http.download_file = OS.get_cache_dir().path_join(_busy + ".zip") if OS.get_cache_dir() != "" \
			else ProjectSettings.globalize_path("user://" + _busy + ".zip")
	print("VRT: downloading core ", url)
	if _http.request(url) != OK:
		_finish(false, "request failed")


func _on_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_finish(false, "HTTP %d (result %d)" % [code, result])
		return
	var zip := ZIPReader.new()
	if zip.open(_http.download_file) != OK:
		_finish(false, "bad zip")
		return
	var want := core_file(_busy)
	var ok := false
	for f in zip.get_files():
		if f.get_file() == want:
			DirAccess.make_dir_recursive_absolute(cores_dir)
			var out := FileAccess.open(cores_dir.path_join(want), FileAccess.WRITE)
			if out:
				out.store_buffer(zip.read_file(f))
				out.close()
				ok = true
	zip.close()
	DirAccess.remove_absolute(_http.download_file)
	_finish(ok, "" if ok else want + " not in zip")


func _finish(ok: bool, why: String) -> void:
	var core := _busy
	_busy = ""
	if ok:
		print("VRT: core installed ", core)
		installed.emit(core)
	else:
		push_warning("VRT: core download failed %s: %s" % [core, why])
		failed.emit(core, why)
	_next()
