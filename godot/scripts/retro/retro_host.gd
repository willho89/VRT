class_name RetroHost
extends Node3D
## VRT's front door to the libretro-godot fork: installs bundled cores, starts
## and stops content, feeds input, and exposes the current frame + field.
##
## Directory layout (libretro-godot convention) under user://retro:
##   cores/<core>_libretro[_android].so   copied from the bundle on startup
##   save/<core>/<game>.srm, states/<core>/<game>.state
##   system/<core>/ (BIOS), core_options/, temp/
## Cores must run from app-private storage: /sdcard is noexec on Android.

signal content_started(entry: ContentLibrary.Entry)
signal content_failed(message: String)
signal content_stopped

## Desktop: cores come from the repo's cores/linux-x86_64 (tools/fetch_cores.sh).
## Android: from res://cores_bundle, packed into the APK.
const BUNDLE_ANDROID := "res://cores_bundle"
const BUNDLE_DESKTOP := "res://../cores/linux-x86_64"

var root := ProjectSettings.globalize_path("user://retro")
var current: ContentLibrary.Entry
var libretro: Node3D

var _last_serial := -1
var _state_waiting := false


func _ready() -> void:
	libretro = ClassDB.instantiate("Libretro")
	add_child(libretro)
	libretro.connect("content_load_failed", _on_load_failed)
	libretro.connect("savestate_ready", _on_savestate_ready)
	libretro.call("SetInputEnabled", false)  # InputRouter drives the ports
	install_cores()


## Copy bundled cores into root/cores when missing or changed (size check).
func install_cores() -> void:
	var src := BUNDLE_ANDROID if OS.get_name() == "Android" else ProjectSettings.globalize_path(BUNDLE_DESKTOP)
	var dst := root.path_join("cores")
	DirAccess.make_dir_recursive_absolute(dst)
	for f in DirAccess.get_files_at(src):
		if f.get_extension() != "so":
			continue
		var from := src.path_join(f)
		var to := dst.path_join(f)
		var data := FileAccess.get_file_as_bytes(from)
		if FileAccess.file_exists(to) and FileAccess.open(to, FileAccess.READ).get_length() == data.size():
			continue
		var out := FileAccess.open(to, FileAccess.WRITE)
		out.store_buffer(data)
		out.close()
		print("VRT: installed core ", f)


func start(entry: ContentLibrary.Entry) -> void:
	stop()
	var path := ContentLibrary.resolve_launch_path(entry, root.path_join("temp/content"))
	if path == "":
		content_failed.emit("Nothing playable in %s" % entry.path.get_file())
		return
	var save_dir := root.path_join("save").path_join(entry.core)
	DirAccess.make_dir_recursive_absolute(save_dir)
	libretro.call("SetSramPath", save_dir.path_join(entry.title + ".srm"))
	libretro.call("StartContent", root, entry.core, path)
	current = entry
	_last_serial = -1
	print("VRT: started ", entry.core, " ", path)
	content_started.emit(entry)


func stop() -> void:
	if current == null:
		return
	libretro.call("RequestSramFlush")
	libretro.call("StopContent")
	current = null
	content_stopped.emit()


func is_running() -> bool:
	return current != null


## Current frame; re-read every frame (a resolution change makes a new texture).
func video_texture() -> Texture2D:
	return libretro.call("GetVideoTexture")


## enum vrt_field of the current frame: 0 progressive, 1 top, 2 bottom.
func video_field() -> int:
	return libretro.call("GetVideoField")


## Frames that landed since the last call (0 = none, >1 = some were skipped
## between our render frames, which matters for field persistence later).
func take_new_frames() -> int:
	var serial: int = libretro.call("GetVideoFrameSerial")
	var n := 0 if _last_serial < 0 else serial - _last_serial
	_last_serial = serial
	return n


func set_joypad(port: int, mask: int, lx := 0, ly := 0, rx := 0, ry := 0) -> void:
	libretro.call("SetJoypadState", port, mask, lx, ly, rx, ry)


## uv in [0,1]^2 over the video output (top-left origin).
func set_pointer(port: int, uv: Vector2, pressed: bool) -> void:
	var x := int(clampf(uv.x * 2.0 - 1.0, -1.0, 1.0) * 32767.0)
	var y := int(clampf(uv.y * 2.0 - 1.0, -1.0, 1.0) * 32767.0)
	libretro.call("SetPointerState", port, x, y, pressed)


func quick_save() -> void:
	if current and not _state_waiting:
		_state_waiting = true
		libretro.call("RequestSaveState")


func quick_load() -> void:
	if current == null:
		return
	var f := FileAccess.open(_state_path(), FileAccess.READ)
	if f == null:
		return
	var frame := f.get_64()
	libretro.call("RequestLoadState", f.get_buffer(f.get_length() - 8), frame)


func _state_path() -> String:
	var d := root.path_join("states").path_join(current.core)
	DirAccess.make_dir_recursive_absolute(d)
	return d.path_join(current.title + ".state")


func _on_savestate_ready(data: PackedByteArray, frame: int) -> void:
	_state_waiting = false
	if current == null:
		return
	var f := FileAccess.open(_state_path(), FileAccess.WRITE)
	f.store_64(frame)
	f.store_buffer(data)
	print("VRT: saved state ", _state_path(), " (", data.size(), " bytes)")


func _on_load_failed(message: String) -> void:
	push_warning("VRT: content failed: " + message)
	current = null
	content_failed.emit(message)


func _exit_tree() -> void:
	stop()
